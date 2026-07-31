-- Overworld battles: the HUD's footing on a world that is not white.
--
-- Gen 1 draws its battle HUDs as black glyphs and bar tiles straight onto
-- the white field, with no box around them -- the field IS the backing. Take
-- the field away and put a route underneath and the name, the level and the
-- HP numbers are black on grass, which is not readable.
--
-- So each HUD block gets a panel: the world behind it, blurred to frosted
-- glass and laid back down translucent, with a tint that pushes it away from
-- whatever colour the text is about to be. Frosted rather than opaque
-- because the point of the mode is that you can see where you are standing,
-- and an opaque slab in the corner of the frame is the white field back
-- again by another name.
--
-- And the text flips. A panel over a sunlit meadow is bright and wants black
-- glyphs; the same panel over a cave floor or a dark roof is not, and wants
-- white ones. So the panel's average brightness is measured and the glyphs
-- follow it, with hysteresis so a slow camera drift across the threshold
-- cannot strobe them.
--
-- The measurement is a one-pixel readback, which is a GPU stall, so it runs
-- a few times a second rather than every frame. The camera drifts at about
-- a pixel a second; brightness cannot outrun that.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleHud = {}

-- How solid the frost is over the world behind it, and how far the tint
-- pushes it toward the far end from the text.
--
-- Both deliberately light. The panel is there to make glyphs legible, not to
-- put a slab in the corner of the frame: at these values the sharp world
-- still reads through it and the blur registers as a pane of glass rather
-- than as a second background.
BattleHud.FROST = 0.55
BattleHud.TINT = 0.26

-- The luminance the glyphs flip at, with a dead band so a drift across it
-- settles rather than strobes.
BattleHud.DARK_ENTER = 0.44   -- below this, the panel is dark: white glyphs
BattleHud.DARK_LEAVE = 0.56   -- above this, back to black ones

-- Frames between brightness readbacks.
BattleHud.SAMPLE_EVERY = 12

-- The frost buffer's height; width follows the source's aspect. Small on
-- purpose: the downscale is most of the blur, and what is read back for the
-- brightness is one pixel of it.
BattleHud.FROST_H = 72

local frost, frostW, frostH = nil, 0, 0
local blurA, blurB = nil, nil
local probe = nil
local frame = 0
local luma = {}      -- panel key -> { value, dark, at }

local SHADER = [[
  uniform vec2 dir;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 sum = Texel(tex, tc) * 0.2270270270;
    sum += (Texel(tex, tc + dir) + Texel(tex, tc - dir)) * 0.1945945946;
    sum += (Texel(tex, tc + 2.0 * dir) + Texel(tex, tc - 2.0 * dir)) * 0.1216216216;
    sum += (Texel(tex, tc + 3.0 * dir) + Texel(tex, tc - 3.0 * dir)) * 0.0540540541;
    sum += (Texel(tex, tc + 4.0 * dir) + Texel(tex, tc - 4.0 * dir)) * 0.0162162162;
    return sum * color;
  }
]]

local shader = nil            -- nil = untried, false = unavailable

local function getShader()
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER)
    shader = (ok and sh) or false
  end
  return shader or nil
end

local function canvasOf(w, h, filter)
  local ok, c = pcall(love.graphics.newCanvas, w, h)
  if not ok then return nil end
  c:setFilter(filter or "linear", filter or "linear")
  return c
end

-- Build (or rebuild) the frosted copy of `src` for this frame.
--
-- Two steps, because one is not enough: the downscale to a 72-row buffer
-- averages the world down to something that no longer reads as terrain, and
-- the separable gaussian over that turns the remaining structure into
-- frosted glass rather than a mosaic of the tiles it came from.
function BattleHud.build(src)
  if not src then return nil end
  local blur = getShader()
  local sw, sh = src:getDimensions()
  if sw <= 0 or sh <= 0 then return nil end
  local h = BattleHud.FROST_H
  local w = math.max(1, math.floor(sw * h / sh + 0.5))
  if not frost or frostW ~= w or frostH ~= h then
    frost = canvasOf(w, h)
    blurA = canvasOf(w, h)
    blurB = canvasOf(w, h)
    probe = probe or canvasOf(1, 1)
    if not (frost and blurA and blurB) then
      frost, blurA, blurB, frostW, frostH = nil, nil, nil, 0, 0
      return nil
    end
    frostW, frostH = w, h
  end

  local prevCanvas = love.graphics.getCanvas()
  local prevBlend, prevAlpha = love.graphics.getBlendMode()
  local prevFilter = { src:getFilter() }
  src:setFilter("linear", "linear")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode("replace", "premultiplied")

  local ok = pcall(function()
    love.graphics.setCanvas(frost)
    love.graphics.draw(src, 0, 0, 0, w / sw, h / sh)
    if blur then
      love.graphics.setShader(blur)
      love.graphics.setCanvas(blurA)
      pcall(blur.send, blur, "dir", { 2.5 / w, 0 })
      love.graphics.draw(frost)
      love.graphics.setCanvas(blurB)
      pcall(blur.send, blur, "dir", { 0, 2.5 / h })
      love.graphics.draw(blurA)
      love.graphics.setShader()
      frost, blurB = blurB, frost   -- the blurred one is the frost now
    end
  end)

  love.graphics.setShader()
  if prevCanvas then
    love.graphics.setCanvas(prevCanvas)
  else
    love.graphics.setCanvas()
  end
  love.graphics.setBlendMode(prevBlend or "alpha", prevAlpha)
  src:setFilter(prevFilter[1] or "nearest", prevFilter[2] or "nearest")
  frame = frame + 1
  return ok and frost or nil
end

function BattleHud.frame()
  return frame
end

-- Average luminance of the frost under `key`'s rect, in frost-canvas pixels.
--
-- Averaged by letting the GPU do it: the rect is drawn into a one-pixel
-- canvas, which IS the mean, and that one pixel is read back. Cached for
-- SAMPLE_EVERY frames because the readback synchronises the pipeline and
-- nothing it measures moves faster than that.
local function sampleLuma(key, fx, fy, fw, fh)
  local hit = luma[key]
  if hit and (frame - hit.at) < BattleHud.SAMPLE_EVERY then return hit.value end
  if not (frost and probe and frostW > 0) then return hit and hit.value end
  if fw <= 0 or fh <= 0 then return hit and hit.value end

  local prevCanvas = love.graphics.getCanvas()
  local prevBlend, prevAlpha = love.graphics.getBlendMode()
  local value = hit and hit.value or 1
  local ok = pcall(function()
    love.graphics.setCanvas(probe)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    local quad = love.graphics.newQuad(fx, fy, fw, fh, frostW, frostH)
    love.graphics.draw(frost, quad, 0, 0, 0, 1 / fw, 1 / fh)
    love.graphics.setCanvas()
    local data = probe:newImageData()
    local r, g, b = data:getPixel(0, 0)
    if data.release then pcall(data.release, data) end
    value = 0.299 * r + 0.587 * g + 0.114 * b
  end)

  if prevCanvas then
    love.graphics.setCanvas(prevCanvas)
  else
    love.graphics.setCanvas()
  end
  love.graphics.setBlendMode(prevBlend or "alpha", prevAlpha)
  if not ok then return hit and hit.value end

  luma[key] = { value = value, at = frame }
  return value
end

-- Map a GB-frame rect onto the frost canvas, given where the letterbox sits
-- in the source the frost was built from.
local function frostRect(rect, box)
  local kx = frostW / box.pw
  local ky = frostH / box.ph
  local fx = (box.lx + rect[1] * box.scale) * kx
  local fy = (box.ly + rect[2] * box.scale) * ky
  local fw = rect[3] * box.scale * kx
  local fh = rect[4] * box.scale * ky
  return fx, fy, math.max(1, fw), math.max(1, fh)
end

-- The same map for a rect that is ALREADY in world-canvas pixels. A HUD
-- snapped out to the window's edge has left the GB frame, so it has no GB
-- coordinates to be placed from -- see OverworldBattle.snapRects.
local function frostRectWorld(rect, box)
  local kx = frostW / box.pw
  local ky = frostH / box.ph
  return rect[1] * kx, rect[2] * ky,
         math.max(1, rect[3] * kx), math.max(1, rect[4] * ky)
end

-- Which of the two the caller's rects are in. One frost buffer, one panel
-- draw, two coordinate spaces: the GB frame (rects land in the 160x144 UI
-- canvas) or world pixels (rects land in the window-resolution world image).
local function mapper(world)
  return world and frostRectWorld or frostRect
end

-- ------- the verdict
--
-- ONE answer for the whole frame, not one per panel. Both HUDs draw in a
-- single pass and there is only one glyph colour to be had out of it -- and
-- a frame with a black-lettered HUD in one corner and a white-lettered one
-- in the other would read as a bug rather than as adaptation. The DARKER
-- panel decides, because it is the one that cannot afford to be wrong, and
-- the tint below then commits both panels to that reading.
local wasDark = false

function BattleHud.verdict(rects, box, world)
  if not (frost and box and box.scale and box.scale > 0) then return false end
  local toFrost = mapper(world)
  local darkest = nil
  for key, rect in pairs(rects) do
    local fx, fy, fw, fh = toFrost(rect, box)
    local v = sampleLuma(key, fx, fy, fw, fh)
    if v and (not darkest or v < darkest) then darkest = v end
  end
  if not darkest then return wasDark end
  -- hysteresis: it takes a clear move past the far threshold to flip back,
  -- so a camera drifting across the boundary settles instead of strobing
  if wasDark then
    wasDark = darkest < BattleHud.DARK_LEAVE
  else
    wasDark = darkest < BattleHud.DARK_ENTER
  end
  return wasDark
end

-- Draw one HUD panel into the current target, in that target's own
-- coordinates: GB ones for the 160x144 UI canvas, world pixels (world = true)
-- for a panel laid straight onto the world image.
--
-- The tint always pushes AWAY from the glyph colour that is about to be
-- used, so the contrast is guaranteed rather than hoped for: a dark panel
-- gets darker under white text, a bright one brighter under black text.
function BattleHud.panel(rect, box, dark, world)
  if not (frost and box and box.scale and box.scale > 0) then return false end
  local fx, fy, fw, fh = mapper(world)(rect, box)
  local ok = pcall(function()
    local quad = love.graphics.newQuad(fx, fy, fw, fh, frostW, frostH)
    love.graphics.setColor(1, 1, 1, BattleHud.FROST)
    love.graphics.draw(frost, quad, rect[1], rect[2], 0,
                       rect[3] / fw, rect[4] / fh)
    local shade = dark and 0 or 1
    love.graphics.setColor(shade, shade, shade, BattleHud.TINT)
    love.graphics.rectangle("fill", rect[1], rect[2], rect[3], rect[4])
    love.graphics.setColor(1, 1, 1, 1)
  end)
  return ok
end

-- ------- flipping the glyphs
--
-- Over a dark panel the HUD's black text has to go white, and it cannot be
-- done by setting a draw colour: LOVE MULTIPLIES by it, and a black glyph
-- times white is still black. The colour channel has to be REPLACED.
--
-- So the HUD is drawn into a scratch layer and that layer is composited back
-- through a shader that whitens whatever is nearly black and leaves the rest
-- alone. "Nearly black" is the text, the tick marks and the bar's outline --
-- everything the HUD draws as ink -- while the HP bar's own greens and reds
-- are well clear of the threshold and come through untouched.
--
-- Composited back into whatever the caller had bound, which is what makes it
-- work in both pipelines without knowing which one it is in: in the colorized
-- one that target is the grayscale BG canvas, where white IS shade 0 and the
-- zone pass then colours the flipped glyphs like every other lightest-shade
-- surface; in the flat fallback it is the screen, where white is white.
local INK = 0.35   -- luminance at or under which a pixel counts as ink

local FLIP = [[
  uniform float ink;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 p = Texel(tex, tc);
    float luma = dot(p.rgb, vec3(0.299, 0.587, 0.114));
    if (p.a > 0.0 && luma <= ink * p.a) p.rgb = vec3(p.a);
    return p * color;
  }
]]

local flipShader = nil
local layer = nil

local function getFlip()
  if flipShader == nil then
    local ok, sh = pcall(love.graphics.newShader, FLIP)
    flipShader = (ok and sh) or false
  end
  return flipShader or nil
end

-- Whether the flip pass can run at all, for the shot driver's log.
function BattleHud.flipReady()
  return getFlip() ~= nil
end

-- Run `fn` with its ink whitened. Falls back to running it plainly when the
-- scratch layer or the shader is unavailable, so a driver that cannot do
-- either gets the vanilla black HUD rather than no HUD.
function BattleHud.flipGlyphs(w, h, fn)
  local sh = getFlip()
  if not sh then return fn() end
  if not layer or layer:getWidth() ~= w or layer:getHeight() ~= h then
    layer = canvasOf(w, h, "nearest")
    if not layer then return fn() end
  end

  local prevCanvas = love.graphics.getCanvas()
  local prevBlend, prevAlpha = love.graphics.getBlendMode()
  local ok, err = pcall(function()
    love.graphics.setCanvas(layer)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("alpha")
    fn()
  end)
  if prevCanvas then
    love.graphics.setCanvas(prevCanvas)
  else
    love.graphics.setCanvas()
  end
  love.graphics.setBlendMode(prevBlend or "alpha", prevAlpha)
  if not ok then error(err, 0) end

  love.graphics.setShader(sh)
  pcall(sh.send, sh, "ink", INK)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(layer, 0, 0)
  love.graphics.setShader()
end

-- ------- the whole HUD layer as a texture
--
-- The two blocks do not sit in the same place any more: each is snapped to its
-- own side of the WINDOW, which is outside the 160x144 canvas the engine draws
-- them in (see OverworldBattle.snapRects). A draw cannot be aimed at two
-- places at once, so the layer is rendered ONCE into a GB-sized canvas and
-- each block is then blitted out of it as a quad.
--
-- `dark` runs the ink through the same flip the in-frame HUD uses, here baked
-- into the texture rather than composited into the caller's target -- the world
-- image the quads land on is a colour canvas, and a flip pass over it would
-- whiten the terrain behind the glyphs along with them.
local hudLayer = nil

function BattleHud.layerTexture(w, h, dark, fn)
  if not hudLayer or hudLayer:getWidth() ~= w or hudLayer:getHeight() ~= h then
    hudLayer = canvasOf(w, h, "nearest")
    if not hudLayer then return nil end
  end
  local g = love.graphics
  local prevCanvas = g.getCanvas()
  local prevBlend, prevAlpha = g.getBlendMode()
  local ok, err = pcall(function()
    g.setCanvas(hudLayer)
    g.clear(0, 0, 0, 0)
    g.setBlendMode("alpha")
    g.setColor(1, 1, 1, 1)
    -- flipGlyphs renders fn into its own scratch layer and composites the
    -- whitened result into whatever is bound, which is this canvas
    if dark then BattleHud.flipGlyphs(w, h, fn) else fn() end
  end)
  if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
  g.setBlendMode(prevBlend or "alpha", prevAlpha)
  g.setColor(1, 1, 1, 1)
  if not ok then error(err, 0) end
  return hudLayer
end

-- The last luminance measured, for the shot driver's log.
function BattleHud.lastLuma()
  local best = nil
  for _, hit in pairs(luma) do
    if not best or hit.value < best then best = hit.value end
  end
  return best
end

function BattleHud.invalidate()
  frost, blurA, blurB, probe = nil, nil, nil, nil
  frostW, frostH = 0, 0
  luma = {}
  wasDark = false
  layer, hudLayer = nil, nil
end

return BattleHud
