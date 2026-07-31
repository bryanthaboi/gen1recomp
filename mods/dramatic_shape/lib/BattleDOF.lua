-- Overworld battles: the depth-of-field pass over the arena.
--
-- A photographic lens focused on two subjects three cells apart holds a
-- narrow slab of the world sharp and loses everything in front of and
-- behind it. On this shot that slab is a BAND ACROSS THE FRAME, because the
-- camera is fixed and looking down at a floor: distance from the lens runs
-- monotonically up the picture, so screen height IS depth, and a band of
-- rows is a slab of world. The floor the mons stand on stays sharp, the
-- middle distance and the horizon soften, and the foreground the camera is
-- leaning over softens the other way.
--
-- BOTH MONS ARE IN FOCUS, and not by tuning: they are drawn as the battle
-- screen's own pics AFTER this runs, so they are never blurred at all. This
-- pass only ever touches the world behind them -- which is exactly the
-- separation a real shot of two subjects at the same distance would have.
--
-- Two separable gaussian passes over a 160x144 image: two full-frame draws
-- of 23,040 pixels, which is nothing, and it buys the one cue that stops a
-- 3D backdrop reading as wallpaper.

local BattleDOF = {}

-- Switched off for now. The pass is kept whole -- band maths, shader,
-- canvases -- because the reason to have it has not gone away: it is the one
-- cue that separates the pair from the ground behind them. It is off because
-- the mons are geometry in the scene now rather than pics over it, and a blur
-- that softens their own tile softens THEM, which the pinned-pic version
-- never had to answer for. Turning it back on means solving that first.
BattleDOF.ENABLED = false

-- Fallbacks for the band, in canvas uv. The caller normally measures it off
-- the two ground marks -- the whole point is that the slab in focus is the
-- one the mons are standing in -- and these are what a caller that cannot
-- gets instead.
BattleDOF.FOCUS_Y = 0.52
BattleDOF.BAND = 0.16
BattleDOF.RANGE = 0.32

-- How much floor either side of the two marks stays sharp, as a fraction of
-- the gap between them: a mon is taller than the patch it stands on, and the
-- ground just in front of and behind it belongs to the same slab.
BattleDOF.BAND_MARGIN = 0.55

-- How far past the band it takes to reach full blur, in the same units as
-- the band itself.
BattleDOF.RANGE_SCALE = 2.0

-- Tap spacing at full blur, as a fraction of the canvas height, so the blur
-- is the same depth of field in a window and fullscreen. The gaussian's
-- reach is four taps and the two passes compound, so a little goes a long
-- way.
BattleDOF.SPACING = 0.0095

-- A touch of saturation on the way out, the same trick the tilt-shift pass
-- uses: a blurred background reads as further away when it is also a
-- little richer than the sharp subject in front of it.
BattleDOF.SATURATION = 1.12

local SHADER = [[
  uniform vec2 dir;        // one texel step along the axis being blurred
  uniform float focusY;
  uniform float band;
  uniform float range;
  uniform float spacing;
  uniform float boost;     // 0 = plain blur pass, 1 = final pass (colour pop)
  uniform float saturation;
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float d = abs(tc.y - focusY) - band;
    float s = clamp(d / range, 0.0, 1.0);
    s = s * s;             // ease in, so the band edge has no visible seam
    vec2 o = dir * (s * spacing);
    vec4 sum = Texel(tex, tc) * 0.2270270270;
    sum += (Texel(tex, tc + o) + Texel(tex, tc - o)) * 0.1945945946;
    sum += (Texel(tex, tc + 2.0 * o) + Texel(tex, tc - 2.0 * o)) * 0.1216216216;
    sum += (Texel(tex, tc + 3.0 * o) + Texel(tex, tc - 3.0 * o)) * 0.0540540541;
    sum += (Texel(tex, tc + 4.0 * o) + Texel(tex, tc - 4.0 * o)) * 0.0162162162;
    if (boost > 0.5) {
      float luma = dot(sum.rgb, vec3(0.299, 0.587, 0.114));
      sum.rgb = mix(vec3(luma), sum.rgb, saturation);
    }
    return sum * color;
  }
]]

local shader = nil            -- nil = untried, false = unavailable
local ping, pong, cw, ch = nil, nil, 0, 0

local function getShader()
  if shader == nil then
    local ok, sh = pcall(love.graphics.newShader, SHADER)
    shader = (ok and sh) or false
  end
  return shader or nil
end

-- Its own pair of canvases rather than the tilt-shift pass's: those are
-- sized to the window and this is sized to the GB frame, and sharing them
-- would reallocate both every time a battle started or ended.
local function getCanvases(w, h)
  if not ping or cw ~= w or ch ~= h then
    local ok, a = pcall(love.graphics.newCanvas, w, h)
    if not ok then return nil end
    local okB, b = pcall(love.graphics.newCanvas, w, h)
    if not okB then return nil end
    -- the gaussian's fractional tap offsets need linear filtering
    a:setFilter("linear", "linear")
    b:setFilter("linear", "linear")
    ping, pong, cw, ch = a, b, w, h
  end
  return ping, pong
end

-- The sharp band for a shot whose two ground marks land at canvas rows
-- `y1` and `y2`, as (focusY, band, range) in uv. This is the depth of field
-- proper: the band is the slab of world the two mons occupy, and everything
-- nearer or further softens away from it.
function BattleDOF.bandFor(y1, y2, h)
  if not (y1 and y2 and h and h > 0) then
    return BattleDOF.FOCUS_Y, BattleDOF.BAND, BattleDOF.RANGE
  end
  local mid = (y1 + y2) / 2 / h
  local half = math.abs(y1 - y2) / 2 / h
  local band = half * (1 + BattleDOF.BAND_MARGIN)
  return math.min(1, math.max(0, mid)),
         band,
         math.max(1e-3, band * BattleDOF.RANGE_SCALE)
end

-- Run the pass over `canvas` and return the result, or the input unchanged
-- when it cannot run (headless, no shader support) -- so the caller always
-- has something to composite. `focusY`, `band` and `range` are in canvas uv;
-- omit them for the fixed fallback band.
function BattleDOF.apply(canvas, focusY, band, range)
  if not (canvas and BattleDOF.ENABLED) then return canvas end
  local sh = getShader()
  if not sh then return canvas end
  local w, h = canvas:getDimensions()
  local a, b = getCanvases(w, h)
  if not a then return canvas end
  focusY = focusY or BattleDOF.FOCUS_Y
  band = band or BattleDOF.BAND
  range = range or BattleDOF.RANGE

  local prevBlend, prevAlpha = love.graphics.getBlendMode()
  local prevCanvas = love.graphics.getCanvas()

  -- the scene canvas filters nearest for its 1:1 blit; the taps need linear,
  -- restored below so the composite sees what it expects
  canvas:setFilter("linear", "linear")
  love.graphics.setShader(sh)
  love.graphics.setColor(1, 1, 1, 1)
  -- replace, not alpha-blend: these are image-processing copies
  love.graphics.setBlendMode("replace", "premultiplied")
  pcall(sh.send, sh, "focusY", focusY)
  pcall(sh.send, sh, "band", band)
  pcall(sh.send, sh, "range", range)
  pcall(sh.send, sh, "spacing", math.max(0.75, h * BattleDOF.SPACING))
  pcall(sh.send, sh, "saturation", BattleDOF.SATURATION)

  local ok = pcall(function()
    love.graphics.setCanvas(a)
    pcall(sh.send, sh, "dir", { 1 / w, 0 })
    pcall(sh.send, sh, "boost", 0)
    love.graphics.draw(canvas)
    love.graphics.setCanvas(b)
    pcall(sh.send, sh, "dir", { 0, 1 / h })
    pcall(sh.send, sh, "boost", 1)
    love.graphics.draw(a)
  end)

  if prevCanvas then
    love.graphics.setCanvas(prevCanvas)
  else
    love.graphics.setCanvas()
  end
  love.graphics.setShader()
  love.graphics.setBlendMode(prevBlend or "alpha", prevAlpha)
  canvas:setFilter("nearest", "nearest")
  return ok and b or canvas
end

-- Drop the GPU objects (window resize, hot reload).
function BattleDOF.invalidate()
  ping, pong, cw, ch = nil, nil, 0, 0
end

return BattleDOF
