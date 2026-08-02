-- Two-pass renderer.  The UI pass is the classic 160x144 Game Boy canvas
-- drawn at the integer window fit scale S, letterboxed in the window.
-- The world pass (overworld survey zoom) is a variable-size canvas that
-- fills the *entire* window at the effective integer scale s',  so black
-- letterbox voids become more map, not empty bars.  Both use nearest-
-- neighbor filtering.
-- Spec: docs/new-features.md (survey zoom)

local Zoom = require("src.render.Zoom")
local Tilt = require("src.render.Tilt")
local PaletteFX = require("src.render.PaletteFX")
local Pipelines = require("src.render.Pipelines")
local PixelCanvas = require("src.render.PixelCanvas")
local Runtime = require("src.mods.Runtime")

local Renderer = {}

-- The Game Boy surface.  WIDTH/HEIGHT are the classic dimensions every
-- screen is laid out in; uiWidth/uiHeight are the surface actually
-- allocated this frame, which a state may widen through setUISize (the
-- widescreen battle layout asks for 304x144).  Anything drawing a normal
-- 160x144 screen can keep reading WIDTH/HEIGHT.
Renderer.WIDTH = 160
Renderer.HEIGHT = 144
Renderer.MAX_UI_WIDTH = 640
Renderer.MAX_UI_HEIGHT = 576

-- Whether a value is a real Canvas we can composite.  Real LOVE canvases are
-- userdata answering typeOf("Canvas"); the headless test stub fakes them as
-- tables carrying the Canvas method shape.  A mod pipeline handing back a
-- non-canvas must be rejected before it reaches love.graphics.draw, which
-- would otherwise take the frame down with it.
local function isCanvas(v)
  if type(v) == "userdata" then
    return type(v.getWidth) == "function" and type(v.getHeight) == "function"
  end
  if type(v) == "table" then
    return type(v.getWidth) == "function" and type(v.getHeight) == "function"
  end
  return false
end

-- Tilt mode: the upright billboard canvas is grown by this many world
-- pixels on every side beyond the ground world view, so a structure or
-- sprite standing near a view edge still draws in full instead of being
-- clipped where the ground canvas ends (a receding tree wall at the top of
-- the view rises above row 0; a fence at the bottom-left drops below/left).
-- endFrame composites the padded canvas back with a matching offset.
Renderer.UPRIGHT_MARGIN = 160

-- LOVE units + framebuffer pixels + per-axis unit→pixel ratios.
-- Android's DisplayMetrics.density is often non-integer (1.5, 2.75, …).
-- Integer scaling in units then maps each GB pixel to a fractional number of
-- framebuffer pixels → shimmer, uneven / non-square "pixels", and movement
-- judder (issue #87).  Always derive the crisp integer scale from the
-- *drawable* pixel size (the window framebuffer we present into -- not a
-- combined multi-display metric), then draw with (pixels / axisDpi) so the
-- GPU lands on whole framebuffer pixels.  Desktop dpi=1 is unchanged.
--
-- LOVE's projection is anisotropic: 1 unit in X covers pw/ww framebuffer
-- pixels and 1 unit in Y covers ph/wh.  Those ratios match on a normal
-- highdpi surface, but diverge when unit sizes are truncated independently
-- (`(int)(pixels/density)`) or when a dual-screen / forced-rotation device
-- reports mismatched unit vs drawable aspects (AYN Thor, issue #208).
-- love.graphics.getDPIScale() is only ph/wh, so using it (or pw/ww alone)
-- for both axes makes the other axis land on a fractional, stretched count.
-- Keep separate dpiX/dpiY so each GB pixel covers fitScale() physical pixels
-- on BOTH axes (square).
local function displayMetrics()
  local ww, wh = love.graphics.getDimensions()
  local pw, ph = ww, wh
  if love.graphics.getPixelDimensions then
    pw, ph = love.graphics.getPixelDimensions()
  end
  local dpiX, dpiY = 1, 1
  if ww > 0 and pw > 0 then dpiX = pw / ww end
  if wh > 0 and ph > 0 then dpiY = ph / wh end
  -- No pixel API (headless / old stub): fall back to getDPIScale, else 1.
  if (dpiX == 1 and dpiY == 1) and not love.graphics.getPixelDimensions
     and love.graphics.getDPIScale then
    local d = love.graphics.getDPIScale()
    if d and d > 1e-6 then dpiX, dpiY = d, d end
  end
  if dpiX < 1e-6 then dpiX = 1 end
  if dpiY < 1e-6 then dpiY = 1 end
  return ww, wh, pw, ph, dpiX, dpiY
end

function Renderer:init()
  -- 160x144 real pixels, never DPI-scaled: see src/render/PixelCanvas.lua
  -- (#208).  Every canvas below is sized in framebuffer pixels for the same
  -- reason -- worldViewSize() already works in drawable pixels.
  self.uiWidth, self.uiHeight = self.WIDTH, self.HEIGHT
  self.canvas = PixelCanvas.new(self.uiWidth, self.uiHeight, "nearest")
  self.worldCanvas = nil
  self.worldActive = false
  -- tilt mode only: a transparent overlay canvas the size of the world
  -- canvas that receives the upright billboard pass (sprites + standing
  -- FX, drawn at their projected ground anchors).  It composites flat over
  -- the projected ground in endFrame; never touched while tilt is off.
  self.uprightCanvas = nil
  self.uprightActive = false
  -- a render pipeline's finished world image, already at window resolution
  -- (see src/render/Pipelines.lua).  nil is "no pipeline rendered this
  -- frame", which is every vanilla frame.
  self.worldOverride = nil
end

-- Hand endFrame a pipeline's world image to composite instead of the world
-- canvas.  Cleared every frame, so a pipeline that declines one frame falls
-- straight back to the 2D path rather than showing a stale image.
function Renderer:setWorldOverride(canvas)
  -- Defensive: a pipeline that hands back a non-canvas (forgotten return, a
  -- truthy sentinel) must not reach the worldOverride blit in endFrame, where
  -- love.graphics.draw on it would crash the frame.  Reject it and fall back
  -- to the 2D path rather than trust it.
  if canvas ~= nil and not isCanvas(canvas) then canvas = nil end
  self.worldOverride = canvas
end

-- Integer framebuffer pixels per GB pixel that fit the window.  Zoom /
-- GBCFX / callers treat this as the crisp scale; endFrame converts to LOVE
-- units via / dpiX and / dpiY when drawing.
function Renderer:fitScale()
  local _, _, pw, ph = displayMetrics()
  local w, h = self:uiSize()
  return math.max(1, math.floor(math.min(pw / w, ph / h)))
end

-- Integer framebuffer pixels per GB pixel for the UI pass.
--
-- Survey zoom only ever scaled the world: the UI kept blitting at fitScale,
-- so zooming out left a full-size dialogue box over a shrunken world, which
-- reads as the UI growing.  Stepping the UI down with the zoom keeps the two
-- in proportion.  Whole integers only, so a UI pixel stays a whole number of
-- screen pixels and the font does not resample; and never below half of
-- fitScale, because past that the text stops being readable.
--
-- Zooming IN does not scale the UI up -- a dialogue box larger than the
-- classic one has no reference to be faithful to, and the letterbox it sits
-- in does not grow either.
function Renderer:uiScale()
  local S = self:fitScale()
  local off = Zoom.offset or 0
  -- Only follow the zoom when a world is actually behind the UI.  Survey zoom
  -- is an OVERWORLD control; the title screen, the intro and the credits show
  -- no world at all, and shrinking them to match a zoom level the player set
  -- for the map is meaningless.  worldActive is this frame's answer --
  -- beginFrame clears it and beginWorldPass sets it -- so a state that draws
  -- no world keeps the full fit scale.
  --
  -- uiWorldHold (Game:draw) is the case worldActive cannot answer: a BATTLE
  -- BG "world" battle stays the scene's backdrop while an OPAQUE state -- the
  -- party menu, the bag -- covers it, whether or not a world pass ran under
  -- that state.  Reading worldActive alone drops the step-down there and
  -- blits those menus a whole scale larger than the battle they cover.
  -- Game.drawBaseInStack keeps the map drawing in the common case, so the two
  -- normally agree; this holds the scale even when it cannot (a battle with
  -- something other than the overworld beneath it).
  if not (self.worldActive or self.uiWorldHold) then return S end
  if off >= 0 then return S end
  local floorS = math.ceil(S / 2) -- at most a 50% reduction
  local s = S + off               -- one integer step per zoom-out step
  if s < floorS then s = floorS end
  return math.max(1, s)
end

-- the native-pixel UI surface in use right now
function Renderer:uiSize()
  return self.uiWidth or self.WIDTH, self.uiHeight or self.HEIGHT
end

-- Ask for a UI surface of w x h native pixels; the canvas is reallocated
-- only when the size actually changes, so the classic path never rebuilds
-- it.  Sizes are resolved before any state draws (Game:draw) and bounded on
-- both ends -- never smaller than the Game Boy screen every layout assumes,
-- never large enough for a bad request to allocate an unbounded canvas.
function Renderer:setUISize(w, h)
  if type(w) ~= "number" or type(h) ~= "number"
     or w < self.WIDTH or h < self.HEIGHT
     or w > self.MAX_UI_WIDTH or h > self.MAX_UI_HEIGHT then
    w, h = self.WIDTH, self.HEIGHT
  end
  w, h = math.floor(w), math.floor(h)
  if w == self.uiWidth and h == self.uiHeight and self.canvas then return end
  if self.canvas and self.canvas.release then self.canvas:release() end
  self.uiWidth, self.uiHeight = w, h
  self.canvas = PixelCanvas.new(w, h, "nearest")
end

-- LOVE-unit draw scales endFrame uses for the UI blit: integer framebuffer
-- scale (fitScale) divided by each axis's unit→pixel factor, so a GB pixel
-- lands on fitScale() whole PHYSICAL pixels on both axes once LOVE applies
-- its projection (fitScale() == drawScaleX() * dpiX == drawScaleY() * dpiY).
-- Exposed for #208's regression (square pixels when dpiX ≠ dpiY).
function Renderer:drawScaleX()
  local _, _, _, _, dpiX = displayMetrics()
  return self:fitScale() / dpiX
end

function Renderer:drawScaleY()
  local _, _, _, _, _, dpiY = displayMetrics()
  return self:fitScale() / dpiY
end

-- Back-compat alias: uniform surfaces have drawScaleX == drawScaleY.
function Renderer:drawScale()
  return self:drawScaleX()
end

-- world-pass canvas size in world pixels: enough to fill the drawable at s'.
-- Sized from framebuffer pixels (not unit dims) so anisotropic dpiX/dpiY
-- cannot over/under-cover the window.  In tilt mode the canvas grows (both
-- dimensions, by Tilt.viewGrowth) so the projected ground plane still covers
-- the whole window with no background peeking at the receded top/bottom
-- corners; flat mode returns exactly today's size (growth factor is 1 when
-- tilt is inactive).
function Renderer:worldViewSize()
  local _, _, pw, ph = displayMetrics()
  local sp = Zoom.scale(self:fitScale())
  local vw, vh = math.ceil(pw / sp), math.ceil(ph / sp)
  -- Even sizes keep Camera:follow on integer pixels (viewW/2 is integral),
  -- so unfloored FX/sprite math cannot phase-shimmer against the tile layer.
  if vw % 2 ~= 0 then vw = vw + 1 end
  if vh % 2 ~= 0 then vh = vh + 1 end
  if Tilt.active() then
    local g = Tilt.viewGrowth()
    vw, vh = math.ceil(vw * g), math.ceil(vh * g)
  end
  return vw, vh
end

-- transparent: the world pass shows through (UI pass draws overlays only)
function Renderer:beginFrame(transparent)
  self.worldActive = false
  self.uprightActive = false
  self.worldOverride = nil
  -- warp-fade overlay from Transition (issue #121); cleared each frame so
  -- a popped transition cannot leave a sticky black veil
  self.worldFadeAlpha = nil
  -- battle-transition wipe, drawn over the whole surface (BattleTransition)
  self.battleWipe = nil
  -- whole-surface veil in screen space (battle-transition flash, the
  -- fade in from white after a battle) -- covers the window, not just the
  -- 160x144 letterbox
  self.screenVeil = nil
  -- edge-anchored UI regions, re-declared by their elements each frame
  self.uiAnchors = nil
  -- last frame's trueColor rects and sprite redraws go before anything
  -- draws this one
  PaletteFX.clearTrueColor()
  PaletteFX.clearSpriteRedraws()
  -- rBGP is a per-frame register here: the state that draws a dark map
  -- re-arms it while it draws (#322), so nothing inherits last frame's
  PaletteFX.setShadeMap(nil)
  PaletteFX.setPass("ui")
  love.graphics.setCanvas(self.canvas)
  if transparent then
    love.graphics.clear(0, 0, 0, 0)
  else
    love.graphics.clear(1, 1, 1, 1)
  end
end

-- The battle-transition wipe, drawn once over the WHOLE surface in screen
-- space rather than as a 160x144 wipe plus a separate fill around it.
--
-- The tile grid is anchored on the letterbox and extended outward at the same
-- tile size, so the figure is continuous: a spiral begins at the outermost
-- edge of the window and works inward through the letterbox to the middle.
-- Nothing is stretched -- the pattern is continued with more tiles, not
-- scaled-up pixels -- and at 1x the grid works out to exactly 20x18, where
-- BattleTransition.gridOrder hands back the ROM's own walk, so an unzoomed
-- window is the classic wipe unchanged.
--
-- Sx/Sy are LOVE-unit scales (Sy defaults to Sx on uniform surfaces).
function Renderer:drawBattleWipe(wipe, ww, wh, ox, oy, vpw, vph, Sx, Sy)
  if not wipe or not wipe.prog or wipe.prog <= 0 then return end
  Sy = Sy or Sx
  local TW, TH = 8 * Sx, 8 * Sy
  if TW < 1 then TW = 1 end
  if TH < 1 then TH = 1 end
  local prog = math.min(1, wipe.prog)

  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.setScissor(0, 0, ww, wh)

  if prog >= 1 then
    love.graphics.rectangle("fill", 0, 0, ww, wh)
    love.graphics.setScissor()
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- whole-tile padding out to each window edge, keeping the grid in phase
  -- with the letterbox's tiles
  local padL = math.max(0, math.ceil(ox / TW))
  local padT = math.max(0, math.ceil(oy / TH))
  local padR = math.max(0, math.ceil((ww - ox - vpw) / TW))
  local padB = math.max(0, math.ceil((wh - oy - vph) / TH))
  local lbCols = math.max(1, math.floor(vpw / TW + 0.5))
  local lbRows = math.max(1, math.floor(vph / TH + 0.5))
  local cols, rows = padL + lbCols + padR, padT + lbRows + padB
  local x0, y0 = ox - padL * TW, oy - padT * TH

  -- required here rather than at the top: BattleTransition reaches the
  -- renderer through game.renderer at draw time, and a module-level require
  -- would put the two files in a load cycle
  local BattleTransition = require("src.render.BattleTransition")
  local order = BattleTransition.gridOrder(wipe.style, cols, rows)

  if order then
    local n = math.floor(#order * prog + 1e-6)
    for i = 1, n do
      local t = order[i]
      love.graphics.rectangle("fill", x0 + t[1] * TW, y0 + t[2] * TH, TW, TH)
    end
  else
    -- shrink / split / the stripes are geometry, not a walk: the same shapes
    -- measured against the window instead of the letterbox
    local style = wipe.style
    if style == "hstripes" then
      local w = ww * prog
      for row = 0, rows - 1 do
        local y = y0 + row * TH
        if row % 2 == 0 then
          love.graphics.rectangle("fill", 0, y, w, TH)
        else
          love.graphics.rectangle("fill", ww - w, y, w, TH)
        end
      end
    elseif style == "vstripes" then
      local h = wh * prog
      for col = 0, cols - 1 do
        local x = x0 + col * TW
        if col % 2 == 0 then
          love.graphics.rectangle("fill", x, 0, TW, h)
        else
          love.graphics.rectangle("fill", x, wh - h, TW, h)
        end
      end
    elseif style == "shrink" then
      local h, w = wh / 2 * prog, ww / 2 * prog
      love.graphics.rectangle("fill", 0, 0, ww, h)
      love.graphics.rectangle("fill", 0, wh - h, ww, h)
      love.graphics.rectangle("fill", 0, 0, w, wh)
      love.graphics.rectangle("fill", ww - w, 0, w, wh)
    else -- split: a black cross growing out of the centre in both axes
      local h, w = wh / 2 * prog, ww / 2 * prog
      love.graphics.rectangle("fill", 0, wh / 2 - h, ww, h * 2)
      love.graphics.rectangle("fill", ww / 2 - w, 0, w * 2, wh)
    end
  end
  love.graphics.setScissor()
  love.graphics.setColor(1, 1, 1, 1)
end

function Renderer:beginWorldPass()
  local vw, vh = self:worldViewSize()
  if not self.worldCanvas or self.worldCanvas:getWidth() ~= vw
     or self.worldCanvas:getHeight() ~= vh then
    -- free the old canvas before replacing it: a zoom/tilt tween changes
    -- the view size every frame, so without this the superseded canvases
    -- pile up in VRAM until a GC finalizer happens to run
    if self.worldCanvas and self.worldCanvas.release then self.worldCanvas:release() end
    self.worldCanvas = PixelCanvas.new(vw, vh, "nearest")
  end
  self.worldActive = true
  PaletteFX.setPass("world")
  love.graphics.setCanvas(self.worldCanvas)
  love.graphics.clear(1, 1, 1, 1)
end

function Renderer:endWorldPass()
  PaletteFX.setPass("ui")
  love.graphics.setCanvas(self.canvas)
end

-- Tilt mode's upright pass: standing things (sprites, tall-grass feet
-- overdraw, screen-anchored FX) draw here instead of into the ground
-- world canvas, each already projected to its ground anchor and colorized
-- with its map's SGB palette (see OverworldController:billboard).  The
-- canvas is transparent so the projected ground shows through the gaps;
-- endFrame blits it flat over the projected ground.  Sized/filtered like
-- the world canvas but kept separate so the ground can be projected as a
-- plane while these stay upright.  Only entered while Tilt.active().
function Renderer:beginUprightPass()
  local vw, vh = self:worldViewSize()
  local M = self.UPRIGHT_MARGIN
  local cw, ch = vw + 2 * M, vh + 2 * M
  if not self.uprightCanvas or self.uprightCanvas:getWidth() ~= cw
     or self.uprightCanvas:getHeight() ~= ch then
    if self.uprightCanvas and self.uprightCanvas.release then self.uprightCanvas:release() end
    self.uprightCanvas = PixelCanvas.new(cw, ch, "nearest")
  end
  self.uprightActive = true
  PaletteFX.setPass(nil)
  love.graphics.setCanvas(self.uprightCanvas)
  love.graphics.clear(0, 0, 0, 0)
  -- shift the whole pass into the padded canvas so billboards keep drawing
  -- in flat world-canvas coordinates (0..vw, 0..vh) while the margin catches
  -- anything that overhangs an edge; endFrame undoes it with the same offset
  love.graphics.push()
  love.graphics.translate(M, M)
end

-- return to the ground world canvas (the world pass owns it until draw()
-- calls endWorldPass)
function Renderer:endUprightPass()
  PaletteFX.setPass("world")
  love.graphics.pop()
  love.graphics.setCanvas(self.worldCanvas)
end

-- Perspective mesh shader for tilt mode.  The mesh already carries CPU-
-- projected 2D corner positions (from Tilt.groundPoint), so the vertex
-- stage does no projection; instead it passes each corner's depthScale as
-- the per-vertex "q" and pre-multiplies the texture coords by it.  The
-- fragment divides back, which reconstructs perspective-correct texture
-- interpolation across the whole quad (no affine-warp seams) using the
-- exact same projection the billboards will anchor to.  false = headless /
-- no shader support, in which case the renderer stays on the flat blit.
local TILT_SHADER = [[
  varying float vScale;
#ifdef VERTEX
  attribute float VertexScale;
  vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vScale = VertexScale;
    VaryingTexCoord = vec4(VertexTexCoord.xy * VertexScale, 0.0, 1.0);
    return transform_projection * vertex_position;
  }
#endif
#ifdef PIXEL
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    return Texel(tex, tc / vScale) * color;
  }
#endif
]]

function Renderer:tiltShader()
  if self._tiltShader == nil then
    local ok, sh = pcall(love.graphics.newShader, TILT_SHADER)
    self._tiltShader = ok and sh or false
  end
  return self._tiltShader or nil
end

-- Dynamic 4-vertex ground quad; positions/depthScale are refreshed each
-- frame from Tilt.meshCorners.  The custom VertexScale attribute rides the
-- perspective "q" through to the shader above.
function Renderer:tiltMesh()
  if self._tiltMesh == nil then
    local format = {
      { "VertexPosition", "float", 2 },
      { "VertexTexCoord", "float", 2 },
      { "VertexScale", "float", 1 },
    }
    local ok, mesh = pcall(love.graphics.newMesh, format, 4, "fan", "dynamic")
    self._tiltMesh = ok and mesh or false
  end
  return self._tiltMesh or nil
end

-- Draw the world pass through the tilt projection.  Two steps: (1) a
-- canvas-to-canvas palette pre-pass that bakes the SGB world zones into a
-- colorized ground canvas in flat space (a perspective transform breaks
-- the rectangular scissors endFrame normally uses), then (2) project that
-- canvas onto the tilted plane via the perspective mesh, scaled/centred
-- exactly like the flat world blit.  `target` is the canvas to project
-- into (nil = default framebuffer; presentCanvas when CRT is on).
-- Returns true on success; false (no shader/mesh) tells endFrame to fall
-- back to the flat blit unchanged.
function Renderer:drawTiltedWorld(zoneList, sx, sy, wox, woy, target)
  local shader = self:tiltShader()
  local mesh = self:tiltMesh()
  if not (shader and mesh) then return false end
  sy = sy or sx
  local wvw = self.worldCanvas:getWidth()
  local wvh = self.worldCanvas:getHeight()

  -- colorized ground canvas, resized to match the world canvas.  Linear
  -- sampling softens the pixel shimmer the perspective warp would cause
  -- (the flat path keeps nearest).  TODO(tilt): optionally render this at
  -- 2x for extra crispness.
  if not self.tiltCanvas or self.tiltCanvas:getWidth() ~= wvw
     or self.tiltCanvas:getHeight() ~= wvh then
    if self.tiltCanvas and self.tiltCanvas.release then self.tiltCanvas:release() end
    self.tiltCanvas = PixelCanvas.new(wvw, wvh, "linear")
  end

  love.graphics.setCanvas(self.tiltCanvas)
  love.graphics.clear(1, 1, 1, 1)
  love.graphics.setColor(1, 1, 1, 1)
  local zoneShader = zoneList and zoneList[1] and PaletteFX.shader() or nil
  if zoneShader then
    love.graphics.setShader(zoneShader)
    -- same trueColor sentinel the flat blit honors (14 §trueColor)
    local bare = false
    for _, z in ipairs(zoneList) do
      local plain = z.colors == false
      if plain ~= bare then
        bare = plain
        love.graphics.setShader(not plain and zoneShader or nil)
      end
      if not plain then PaletteFX.sendColors(zoneShader, z.colors) end
      local x, y = math.max(0, z.x), math.max(0, z.y)
      local x2, y2 = math.min(wvw, z.x + z.w), math.min(wvh, z.y + z.h)
      if x2 > x and y2 > y then
        love.graphics.setScissor(x, y, x2 - x, y2 - y)
        love.graphics.draw(self.worldCanvas, 0, 0)
      end
    end
    love.graphics.setScissor()
    love.graphics.setShader()
  else
    love.graphics.draw(self.worldCanvas, 0, 0)
  end

  -- project onto the tilted plane into the present target (or screen)
  love.graphics.setCanvas(target)
  mesh:setTexture(self.tiltCanvas)
  mesh:setVertices(Tilt.meshCorners(wvw, wvh))
  love.graphics.push()
  love.graphics.translate(wox, woy)
  love.graphics.scale(sx, sy)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setShader(shader)
  love.graphics.draw(mesh)
  love.graphics.setShader()
  love.graphics.pop()
  return true
end

-- Clamp a scissor rect to the viewport box, then round it outward to whole
-- framebuffer pixels.  love.graphics.setScissor truncates x, y, w and h to
-- pixels independently, so a rect with fractional unit edges (Android's
-- non-integer DPI puts fitScale/dpi in Sx/Sy) loses up to a pixel per side
-- and two adjacent SGB zones stop sharing an edge: the letterbox clear shows
-- through as a horizontal seam at every zone boundary (#373).  Rounding
-- outward makes neighbours overlap by at most one row instead -- the overlap
-- redraws the same canvas pixels one palette later, and past the canvas edge
-- there is nothing to draw.  The half pixel keeps LOVE's truncation on the
-- snapped edge rather than one short of it.
local function scissorClamped(x, y, w, h, ox, oy, vpw, vph, dpiX, dpiY)
  local x2, y2 = math.min(x + w, ox + vpw), math.min(y + h, oy + vph)
  x, y = math.max(x, ox), math.max(y, oy)
  if x2 <= x or y2 <= y then return false end
  dpiX, dpiY = dpiX or 1, dpiY or 1
  local px1, py1 = math.floor(x * dpiX), math.floor(y * dpiY)
  local px2, py2 = math.ceil(x2 * dpiX), math.ceil(y2 * dpiY)
  love.graphics.setScissor((px1 + 0.5) / dpiX, (py1 + 0.5) / dpiY,
                           (px2 - px1 + 0.5) / dpiX,
                           (py2 - py1 + 0.5) / dpiY)
  return true
end

-- Splice the pass's trueColor rects (reported by the renderers that drew
-- a record carrying the flag) onto the end of its zone list, so each one
-- re-blits its region with no shader over the colorized pass.  An absent
-- or empty zone list is left alone: that already draws the whole canvas
-- unshaded, which is what the rects were asking for.
local function withTrueColor(zoneList, pass)
  local rects = PaletteFX.trueColorRects(pass)
  if not (rects[1] and zoneList and zoneList[1]) then return zoneList end
  local merged = {}
  for i = 1, #zoneList do merged[i] = zoneList[i] end
  for i = 1, #rects do merged[#merged + 1] = rects[i] end
  return merged
end

-- Palette-correct blit of `canvas` at (sx, sy) LOVE-unit scales into origin
-- (bx, by), scissored to the (boxX, boxY, boxW, boxH) screen rect.  zoneSx/
-- zoneSy convert zone coords (canvas-space) into screen units.  Public so a
-- render.compose mod can composite the world/UI canvases into its own layout.
function Renderer:blitCanvas(canvas, sx, sy, zoneList, zoneSx, zoneSy,
                             bx, by, boxX, boxY, boxW, boxH, dpiX, dpiY)
  local shader = zoneList and zoneList[1] and PaletteFX.shader() or nil
  if not shader then
    love.graphics.setScissor(boxX, boxY, boxW, boxH)
    love.graphics.draw(canvas, bx, by, 0, sx, sy)
    love.graphics.setScissor()
    return
  end
  love.graphics.setShader(shader)
  -- a colors == false zone is the trueColor opt-out: its rect draws with
  -- no shader at all.  Nothing sets one without a mod, so a vanilla zone
  -- list never toggles and issues exactly the calls it always did.
  local bare = false
  for _, z in ipairs(zoneList) do
    local plain = z.colors == false
    if plain ~= bare then
      bare = plain
      love.graphics.setShader(not plain and shader or nil)
    end
    if not plain then PaletteFX.sendColors(shader, z.colors) end
    if scissorClamped(bx + z.x * zoneSx, by + z.y * zoneSy,
                      z.w * zoneSx, z.h * zoneSy,
                      boxX, boxY, boxW, boxH, dpiX, dpiY) then
      love.graphics.draw(canvas, bx, by, 0, sx, sy)
    end
  end
  love.graphics.setScissor()
  love.graphics.setShader()
end

-- Take a rect out of a list of rects, splitting each overlapped one into up
-- to four pieces.  Used to vacate an anchored UI region from the letterbox
-- blit, so the element is drawn at its anchor and not also in place.
local function subtractRect(list, x, y, w, h)
  local out = {}
  local x2, y2 = x + w, y + h
  for _, r in ipairs(list) do
    local rx, ry, rw, rh = r[1], r[2], r[3], r[4]
    local rx2, ry2 = rx + rw, ry + rh
    if x2 <= rx or x >= rx2 or y2 <= ry or y >= ry2 then
      out[#out + 1] = r -- disjoint
    else
      if ry < y then out[#out + 1] = { rx, ry, rw, y - ry } end
      if y2 < ry2 then out[#out + 1] = { rx, y2, rw, ry2 - y2 } end
      local ty, ty2 = math.max(ry, y), math.min(ry2, y2)
      if rx < x then out[#out + 1] = { rx, ty, x - rx, ty2 - ty } end
      if x2 < rx2 then out[#out + 1] = { x2, ty, rx2 - x2, ty2 - ty } end
    end
  end
  return out
end

-- A UI element that should sit against a screen edge rather than inside the
-- centred letterbox.  Declared during the element's own draw, in UI-canvas
-- pixels, and consumed by endFrame this frame only.
--   anchor: "bottom" | "topright" | "topleft" | "bottomright"
function Renderer:setUIAnchor(x, y, w, h, anchor)
  -- uiAnchorHold (Game:draw): a state that composes its own screen -- a
  -- battle -- keeps every element inside it, so the box blits where it was
  -- drawn in the canvas instead of being pulled to the window edge.
  if self.uiAnchorHold then return end
  self.uiAnchors = self.uiAnchors or {}
  self.uiAnchors[#self.uiAnchors + 1] =
    { x = x, y = y, w = w, h = h, anchor = anchor }
end

-- zones: optional list of SGB palette regions (see PaletteFX) in
-- 160x144 UI space, applied to the UI pass.  worldZones: optional
-- regions in world-canvas pixels (overworld survey zoom colors each
-- visible map area separately), applied to the world pass; the world
-- pass falls back to the UI zones when absent.  Each zone is drawn
-- scissored through the shade-remap shader, later zones on top.
-- When GBC FX is active the composite is drawn into presentCanvas and
-- presented through the GBC FX shader as a final pass.
function Renderer:endFrame(zones, worldZones)
  love.graphics.setCanvas()
  local ww, wh, pw, ph, dpiX, dpiY = displayMetrics()
  -- Sp = integer framebuffer pixels per GB pixel;
  -- Sx/Sy = LOVE-unit draw scales (may differ when dpiX ≠ dpiY).
  local Sp = self:fitScale()
  local Sx, Sy = Sp / dpiX, Sp / dpiY
  local uiw, uih = self:uiSize()
  local vpw, vph = uiw * Sx, uih * Sy
  -- Snap the letterbox origin to a framebuffer pixel, then convert to units.
  local ox = math.floor((pw - uiw * Sp) / 2) / dpiX
  local oy = math.floor((ph - uih * Sp) / 2) / dpiY
  -- The UI has its own scale: it steps down as the survey zoom goes out (see
  -- uiScale), so it can be smaller than the world letterbox.  Un-zoomed these
  -- are identical to Sp/ox/oy and every rect below is what it always was.
  local Up = self:uiScale()
  -- BATTLE SIZE "fill" (Renderer.uiFill, set per frame by Game:draw): scale
  -- the surface to the window rather than to whole GB pixels, so the battle
  -- fills vertically at any zoom or window size.  Fractional by nature -- a
  -- GB pixel stops being a whole number of screen pixels, which is the trade
  -- the setting exists to offer.  Clamped on the horizontal too, so a narrow
  -- window scales to fit instead of overflowing off both sides.
  if self.uiFill then
    Up = math.min(ph / uih, pw / uiw)
  end
  local Ux, Uy = Up / dpiX, Up / dpiY
  local uvpw, uvph = uiw * Ux, uih * Uy
  local uox = math.floor((pw - uiw * Up) / 2) / dpiX
  local uoy = math.floor((ph - uih * Up) / 2) / dpiY
  local GBCFX = require("src.render.GBCFX")
  -- Forced mono/Classic modes still need a whole-screen zone when a state
  -- exposes no SGB packets (raw DMG canvas), so sendColors can remap.
  zones = PaletteFX.ensureZones(zones)
  if worldZones then worldZones = PaletteFX.ensureZones(worldZones) end
  -- the UI rects are in 160x144 canvas space and the world rects in world-
  -- canvas pixels, matching the zone list each is appended to.  A world
  -- pass with no world zones falls back to the UI list, whose coordinate
  -- space the world rects are not in, so they are dropped there.
  zones = withTrueColor(zones, "ui")
  worldZones = withTrueColor(worldZones, "world")

  -- render.compose: hand a mod the finished world + UI canvases (and their
  -- SGB zones), the frame metrics, Renderer:blitCanvas and the SecondScreen
  -- bridge, letting it lay the two passes out however it likes -- e.g. as two
  -- stacked Game Boy screens, or driving one onto a second physical display.
  -- The mod returns true to take over the whole window; anything else (or no
  -- mod wrapping the hook) falls through to the normal composite below.
  if Runtime.wantsHook("render.compose") then
    local ctx = {
      renderer = self,
      worldCanvas = self.worldCanvas, uiCanvas = self.canvas,
      worldOverride = self.worldOverride,
      worldActive = self.worldActive and true or false,
      zones = zones, worldZones = worldZones,
      ww = ww, wh = wh, pw = pw, ph = ph, ox = ox, oy = oy,
      vpw = vpw, vph = vph, uiw = uiw, uih = uih,
      scale = Sp, Sx = Sx, Sy = Sy, dpiX = dpiX, dpiY = dpiY,
      secondScreen = require("src.render.SecondScreen"),
    }
    if Runtime.call("render.compose", function() return false end, self, ctx) == true then
      self.worldActive = false
      self.uprightActive = false
      self.worldOverride = nil
      PaletteFX.setPass(nil)
      return {
        width = ww, height = wh, gameX = ox, gameY = oy,
        gameWidth = vpw, gameHeight = vph, scale = Sp, dpiX = dpiX, dpiY = dpiY,
      }
    end
  end

  -- A post-process pipeline needs the whole composite in a canvas for the
  -- same reason GBC FX does, so either one alone is enough to take the
  -- present path; with neither, the frame draws straight to the screen
  -- exactly as it always did.
  local needPresent = GBCFX.active() or Pipelines.wantsPresent()
  local present = nil
  if needPresent then
    if not self.presentCanvas or self.presentCanvas:getWidth() ~= ww
       or self.presentCanvas:getHeight() ~= wh then
      -- The one canvas NOT built through PixelCanvas: it is sized in LOVE
      -- units and blitted back at unit scale 1 (and handed to mod present
      -- passes as ww x wh), so it has to keep the screen's DPI scale for its
      -- texture to cover the framebuffer.  Everything composited into it is
      -- already native-resolution now, so #208's fractional source is gone;
      -- what remains here is the dpiX vs dpiY truncation gap (well under 1%,
      -- one seam across the window) that a single scalar dpiscale cannot
      -- express.
      self.presentCanvas = love.graphics.newCanvas(ww, wh)
      self.presentCanvas:setFilter("linear", "linear")
    end
    present = self.presentCanvas
    love.graphics.setCanvas(present)
  end
  -- Default letterbox is black.  Battle (and any state that opts in via
  -- letterboxWhite) fills the voids with the display mode's paper shade, so
  -- the bars match the canvas they frame instead of showing black.  Not a
  -- literal white: the battle canvas is colorized, and in SGB mode its paper
  -- is the pack's off-white (255,239,255), which a hardcoded 1,1,1 framed in
  -- a visibly brighter border.
  local clearR, clearG, clearB = 0, 0, 0
  if not self.worldActive then
    local ok, Game = pcall(require, "src.core.Game")
    local stack = ok and Game and Game.stack
    local base = stack and stack.visibleBase and stack:visibleBase()
    local state = base and stack.states and stack.states[base]
    -- A battle owns the surround it established until it leaves the stack.
    -- Reading it off visibleBase alone loses that the moment the battle opens
    -- an OPAQUE state -- the party menu, the bag -- because that state becomes
    -- the base and answers no to letterboxWhite, flipping a white battle
    -- surround to flat black for as long as the menu is up.  Same whole-stack
    -- hold as uiFill and the dim.
    for i = #(stack and stack.states or {}), 1, -1 do
      local s = stack.states[i]
      if s and s.letterboxWhite then
        state = s
        break
      end
    end
    -- BATTLE BG "black" keeps the default black clear; "white" (and any
    -- non-battle state that opts in) uses the paper shade.  "world" never
    -- reaches here -- it makes the battle non-opaque, so the world pass is
    -- active and this whole branch is skipped.
    if state and state.letterboxWhite
       and not (state.bgMode and state:bgMode() == "black") then
      clearR, clearG, clearB = PaletteFX.paperShade(Game and Game.data)
    end
  end
  love.graphics.setColor(clearR, clearG, clearB, 1)
  love.graphics.rectangle("fill", 0, 0, ww, wh)
  love.graphics.setColor(1, 1, 1, 1)
  -- render.letterbox: SGB borders / custom void art in the bars around the
  -- 160x144 (or world) blit.  Drawn after the clear and before the game
  -- canvas so the playfield sits on top of the border.
  if Runtime.wantsHook("render.letterbox") then
    Runtime.call("render.letterbox", function() end, {
      ww = ww, wh = wh, pw = pw, ph = ph,
      ox = ox, oy = oy, vpw = vpw, vph = vph,
      scale = Sp, dpiX = dpiX, dpiY = dpiY,
      worldActive = self.worldActive and true or false,
    })
  end

  -- see Renderer:blitCanvas; bound here to the frame's dpi so the composite
  -- call sites below stay unchanged.
  local function blit(canvas, sx, sy, zoneList, zoneSx, zoneSy,
                      bx, by, boxX, boxY, boxW, boxH)
    return self:blitCanvas(canvas, sx, sy, zoneList, zoneSx, zoneSy,
                           bx, by, boxX, boxY, boxW, boxH, dpiX, dpiY)
  end

  if self.worldOverride then
    -- A render pipeline already produced the whole world -- terrain,
    -- characters and its own FX overlay -- as one window-resolution image,
    -- so it composites with a straight 1:1 blit and the world canvas is
    -- skipped entirely (nothing drew into it).  The UI blit below still
    -- runs, so dialogs, menus and the HUD sit on top as usual.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setScissor(0, 0, ww, wh)
    local loveMajor = love.getVersion()
    if love.system and love.system.getOS and love.system.getOS() == "iOS" and loveMajor >= 12 then
      love.graphics.draw(self.worldOverride, 0, wh, 0, 1 / dpiX, -1 / dpiY)
    else
      love.graphics.draw(self.worldOverride, 0, 0, 0, 1 / dpiX, 1 / dpiY)
    end
    love.graphics.setScissor()
    -- the screen-space overlays the flat path draws over its composite
    local fade = self.worldFadeAlpha
    if fade and fade > 0 then
      love.graphics.setColor(0, 0, 0, fade)
      love.graphics.rectangle("fill", 0, 0, ww, wh)
      love.graphics.setColor(1, 1, 1, 1)
    end
  elseif self.worldActive then
    local sp = Zoom.scale(Sp)
    local sx, sy = sp / dpiX, sp / dpiY
    local wvw = self.worldCanvas:getWidth()
    local wvh = self.worldCanvas:getHeight()
    local wox = math.floor((pw - wvw * sp) / 2) / dpiX
    local woy = math.floor((ph - wvh * sp) / 2) / dpiY
    -- Tilt mode projects the ground world pass through the perspective mesh
    -- (SGB zones baked in beforehand -- see drawTiltedWorld -- so no zone
    -- scissoring here).  drawTiltedWorld returns false when tilt is off or
    -- projection is unavailable (headless / no shader); then the ground
    -- falls through to the flat blit, keeping the flat frame byte-for-byte
    -- identical to today.
    local projected =
      Tilt.active() and self:drawTiltedWorld(worldZones or zones, sx, sy, wox, woy, present)
    if not projected then
      if worldZones then
        blit(self.worldCanvas, sx, sy, worldZones, sx, sy, wox, woy, 0, 0, ww, wh)
      else
        blit(self.worldCanvas, sx, sy, zones, Sx, Sy, wox, woy, 0, 0, ww, wh)
      end
      -- OBP-baked overworld sprites replay on top of the zone pass (GBC
      -- mode per-object coloring; see PaletteFX.markSpriteRedraw).  Grass
      -- feet-overdraw entries carry `colors` and re-colorize through the
      -- color-0-keyed shade-remap shader so they keep hiding sprite feet.
      local redraws = PaletteFX.spriteRedraws()
      if redraws[1] then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setScissor(0, 0, ww, wh)
        local activeShader = nil
        for _, r in ipairs(redraws) do
          local wanted = r.colors
            and (r.keyed and PaletteFX.keyedShader() or PaletteFX.shader())
            or nil
          if wanted ~= activeShader then
            activeShader = wanted
            love.graphics.setShader(wanted)
          end
          if wanted then PaletteFX.sendColors(wanted, r.colors) end
          if r.quad then
            love.graphics.draw(r.image, r.quad, wox + r.x * sx, woy + r.y * sy,
                               0, sx * r.sx, sy)
          else
            love.graphics.draw(r.image, wox + r.x * sx, woy + r.y * sy,
                               0, sx * r.sx, sy)
          end
        end
        if activeShader then love.graphics.setShader() end
        love.graphics.setScissor()
      end
    end
    -- Composite the tilt upright pass over the ground (projected or, in the
    -- rare no-shader fallback, flat).  It already carries its billboards'
    -- projected positions and per-sprite SGB colorization on a transparent
    -- canvas, so it just needs the same centred integer-scale blit the flat
    -- world pass uses -- no zone scissoring.  uprightActive is only ever
    -- set in tilt mode, so flat frames skip this and stay identical.
    if self.uprightActive then
      local M = self.UPRIGHT_MARGIN
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.setScissor(0, 0, ww, wh)
      love.graphics.draw(self.uprightCanvas, wox - M * sx, woy - M * sy, 0, sx, sy)
      love.graphics.setScissor()
    end
    -- Screen-space warp fade (Transition) over the full world composite so
    -- survey zoom / tilt edges darken with the center, not only the 160x144
    -- UI letterbox.  Drawn before the UI blit so menus above a fade still
    -- composite normally if one is ever stacked that way.
    local fade = self.worldFadeAlpha
    if fade and fade > 0 then
      love.graphics.setColor(0, 0, 0, fade)
      love.graphics.rectangle("fill", 0, 0, ww, wh)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
  -- BATTLE BG "world": the frozen overworld has just been composited and the
  -- battle is about to blit over it.  Dim the world first, so the battle
  -- reads as the foreground instead of competing with a fully lit map.  Goes
  -- here rather than in the letterbox clear because with the world pass
  -- active there is no clear -- the world already covers the surface.
  if self.battleDim and self.battleDim > 0 then
    love.graphics.setColor(0, 0, 0, self.battleDim)
    love.graphics.rectangle("fill", 0, 0, ww, wh)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- UI: anchored regions against their screen edges, the rest in the classic
  -- centred letterbox.  With nothing anchored this is the single blit it has
  -- always been.
  local anchors = self.uiAnchors
  if not anchors or #anchors == 0 then
    blit(self.canvas, Ux, Uy, zones, Ux, Uy, uox, uoy, uox, uoy, uvpw, uvph)
  else
    local rest = { { uox, uoy, uvpw, uvph } }
    local placed = {}
    for _, a in ipairs(anchors) do
      local dw, dh = a.w * Ux, a.h * Uy
      -- Anchors are edge-RELATIVE: an element keeps its distance from the
      -- canvas edge, measured against the screen edge instead.  That is what
      -- keeps a stack together -- the yes/no box sits 48px above the canvas
      -- bottom, so bottom-anchoring lands it 48px above the screen bottom,
      -- still directly over the dialogue box, rather than on top of it.
      local gapR = (uiw - (a.x + a.w)) * Ux
      local gapB = (uih - (a.y + a.h)) * Uy
      local dx, dy
      if a.anchor == "bottom" then
        dx = uox + a.x * Ux -- horizontally it stays with the letterbox
        dy = wh - gapB - dh
      elseif a.anchor == "topright" then
        dx = ww - gapR - dw
        dy = a.y * Uy
      else -- unknown anchor: leave it where it is
        dx, dy = uox + a.x * Ux, uoy + a.y * Uy
      end
      placed[#placed + 1] = { a = a, dx = dx, dy = dy, dw = dw, dh = dh }
      rest = subtractRect(rest, uox + a.x * Ux, uoy + a.y * Uy, dw, dh)
    end
    for _, r in ipairs(rest) do
      blit(self.canvas, Ux, Uy, zones, Ux, Uy, uox, uoy, r[1], r[2], r[3], r[4])
    end
    for _, p in ipairs(placed) do
      -- shift the draw origin so canvas pixel (a.x, a.y) lands on (dx, dy).
      -- The zone scissors are computed from the same origin, so an SGB
      -- region travels with the element instead of staying in the letterbox.
      blit(self.canvas, Ux, Uy, zones, Ux, Uy,
           p.dx - p.a.x * Ux, p.dy - p.a.y * Uy, p.dx, p.dy, p.dw, p.dh)
    end
  end

  -- The battle wipe covers the whole surface, letterbox included, so it goes
  -- over the finished composite rather than under the UI blit.  On hardware
  -- it is the tilemap being overwritten -- there is nothing it does not cover.
  if self.battleWipe then
    self:drawBattleWipe(self.battleWipe, ww, wh, ox, oy, vpw, vph, Sx, Sy)
  end

  -- Palette-register effects (BattleTransition_FlashScreen's rBGP writes, the
  -- GBFadeInFromWhite after a battle) tint every pixel the LCD shows -- there
  -- is no "outside the screen" on hardware for them to miss.  So they are
  -- painted here, over the finished composite, rather than into the 160x144
  -- UI canvas: at any zoom above 1x a letterbox-only veil left the
  -- surrounding window untouched, which read as the effect happening inside
  -- a window rather than to the whole screen.  { shade, alpha }.
  local veil = self.screenVeil
  if veil and veil[2] > 0 then
    love.graphics.setColor(veil[1], veil[1], veil[1], veil[2])
    love.graphics.rectangle("fill", 0, 0, ww, wh)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if present then
    love.graphics.setCanvas()
    -- Post-process pipelines run over the finished composite -- world, UI
    -- and all -- and before GBC FX, so a blur or colour grade is what the
    -- LCD grid is then drawn over rather than something that smears the
    -- grid itself.  Each pass hands back a canvas; with none registered
    -- this returns `present` unchanged and the frame is byte-identical.
    local composed = Pipelines.present(present,
      { width = ww, height = wh, scale = Sp, dpi = dpiY, dpiX = dpiX, dpiY = dpiY }) or present
    if GBCFX.active() then
      -- shader grid/shadow math is in framebuffer pixels
      GBCFX.present(composed, Sp)
    else
      -- the present canvas only existed for the post-process, so put the
      -- result on the screen at the same 1:1 unit mapping it was built at
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(composed, 0, 0)
    end
  end
  self.worldActive = false
  self.uprightActive = false
  self.worldOverride = nil
  PaletteFX.setPass(nil)
  return {
    width = ww, height = wh,
    gameX = ox, gameY = oy,
    gameWidth = vpw, gameHeight = vph,
    scale = Sp,
    dpiX = dpiX, dpiY = dpiY,
  }
end

return Renderer
