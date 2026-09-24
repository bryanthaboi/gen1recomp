-- PIXEL FILTER: xBRZ, a built-in edge-directed upscaler for the final frame.
--
-- Runs where SHADER FX runs (Renderer:endFrame for Gen 1 / Gen 3, Game2's
-- present for Gen 2) and with the same render() signature, so both call sites
-- dispatch to one or the other.  A SHADER FX preset wins when both are set:
-- a slang chain expects the raw 1x grid as its Source, and handing it an
-- already-smoothed image would just smear its mask/scanline math.
--
-- The composite is window-sized and nearest-upscaled, so the first step
-- reads it back down to one texel per GB pixel -- the same crop ShaderFX
-- does, but grid-exact for fractional scales too (BATTLE SIZE "fill"),
-- since xBRZ needs the true source pixels rather than a resample of them.
-- xBRZ then scales that grid straight to the output size ("freescale"), so
-- any window size works without a 2x/3x/4x ladder.
--
-- The shader is a GLSL port of the xBRZ algorithm by Zenju (GPLv3), via
-- the libretro xbrz-freescale shader by Hyllian / Desty.  Pixels are
-- handled as premultiplied RGBA rather than RGB so the transparent UI layer
-- a zoomed world splits off scales without dark fringes on its edges.

local Logger = require("src.core.Logger")
local PixelCanvas = require("src.render.PixelCanvas")

local Xbrz = {}

-- Set from applyOptions on every generation, like Letterbox.mode, so a draw
-- call needs no options table in hand.
Xbrz.mode = "off"

Xbrz.MODES = { "off", "xbrz" }

local LABELS = { off = "OFF", xbrz = "XBRZ" }

function Xbrz.normalize(mode)
  for _, id in ipairs(Xbrz.MODES) do
    if mode == id then return id end
  end
  return "off"
end

function Xbrz.label(mode)
  return LABELS[Xbrz.normalize(mode)]
end

function Xbrz.cycle(mode, dir)
  local at = 1
  for i, id in ipairs(Xbrz.MODES) do
    if id == Xbrz.normalize(mode) then at = i break end
  end
  local n = #Xbrz.MODES
  return Xbrz.MODES[(at - 1 + (dir or 1)) % n + 1]
end

function Xbrz.setMode(mode)
  Xbrz.mode = Xbrz.normalize(mode)
  return Xbrz.mode
end

function Xbrz.applyOptions(options)
  return Xbrz.setMode(options and options.pixelFilter)
end

-- ------- shaders
--
-- Two passes.  Everything xBRZ decides (which corners blend, whether as a
-- line, shallow or steep, and toward which neighbour) depends only on the
-- source pixel, never on where inside it an output pixel falls.  So ANALYZE
-- runs once per SOURCE pixel (23k for a GB frame) and packs those decisions
-- into an info texture, and SCALE runs once per OUTPUT pixel (2M at 1080p)
-- reading just E, its four edge neighbours and that one info texel.  The
-- single-pass form redid the 21-tap, ~40-sqrt analysis for every output
-- pixel.  The output is the same.
--
-- Info texel layout: one channel per corner (r = top-left, g = top-right,
-- b = bottom-right, a = bottom-left, matching blend.xyzw), holding code/255
-- where code sums these bits (0 = that corner does not blend):
--   1 blends   2 as a line   4 shallow   8 steep
--   16 blends toward the second candidate (see each corner in SCALE)

local SHARED_SOURCE = [[
#define HALF_SQRT2 0.70710678

extern vec2 srcSize;
]]

local ANALYZE_SOURCE = SHARED_SOURCE .. [[
#define BLEND_NONE 0.0
#define BLEND_NORMAL 1.0
#define BLEND_DOMINANT 2.0
#define LUMINANCE_WEIGHT 1.0
#define EQUAL_COLOR_TOLERANCE (30.0 / 255.0)
#define STEEP_DIRECTION_THRESHOLD 2.2
#define DOMINANT_DIRECTION_THRESHOLD 3.6

// YCbCr distance (BT.2020 weights) plus alpha, so an opaque black pixel and
// a transparent one never read as the same colour.
float dist(vec4 a, vec4 b) {
  vec4 d = a - b;
  float y = dot(d.rgb, vec3(0.2627, 0.6780, 0.0593));
  float cb = (0.5 / (1.0 - 0.0593)) * (d.b - y);
  float cr = (0.5 / (1.0 - 0.2627)) * (d.r - y);
  return sqrt(LUMINANCE_WEIGHT * y * LUMINANCE_WEIGHT * y + cb * cb + cr * cr + d.a * d.a);
}

bool near(vec4 a, vec4 b) { return dist(a, b) < EQUAL_COLOR_TOLERANCE; }
bool eq(vec4 a, vec4 b) { return a == b; }
bool neq(vec4 a, vec4 b) { return a != b; }

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 texel = 1.0 / srcSize;
  vec2 coord = (floor(uv * srcSize) + vec2(0.5)) * texel;

#define P(x, y) Texel(tex, coord + texel * vec2(x, y))

  //  -|x|x|x|-
  //  x|A|B|C|x
  //  x|D|E|F|x
  //  x|G|H|I|x
  //  -|x|x|x|-
  vec4 A = P(-1.0, -1.0);
  vec4 B = P( 0.0, -1.0);
  vec4 C = P( 1.0, -1.0);
  vec4 D = P(-1.0,  0.0);
  vec4 E = P( 0.0,  0.0);
  vec4 F = P( 1.0,  0.0);
  vec4 G = P(-1.0,  1.0);
  vec4 H = P( 0.0,  1.0);
  vec4 I = P( 1.0,  1.0);

  // corner blend kinds: x = top-left, y = top-right, z = bottom-right,
  // w = bottom-left
  vec4 blend = vec4(BLEND_NONE);

  if (!((eq(E, F) && eq(H, I)) || (eq(E, H) && eq(F, I)))) {
    float hf = dist(G, E) + dist(E, C) + dist(P(0.0, 2.0), I) + dist(I, P(2.0, 0.0)) + 4.0 * dist(H, F);
    float ei = dist(D, H) + dist(H, P(1.0, 2.0)) + dist(B, F) + dist(F, P(2.0, 1.0)) + 4.0 * dist(E, I);
    bool dominant = (DOMINANT_DIRECTION_THRESHOLD * hf) < ei;
    blend.z = (hf < ei && neq(E, F) && neq(E, H)) ? (dominant ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
  }
  if (!((eq(D, E) && eq(G, H)) || (eq(D, G) && eq(E, H)))) {
    float ge = dist(P(-2.0, 1.0), D) + dist(D, B) + dist(P(-1.0, 2.0), H) + dist(H, F) + 4.0 * dist(G, E);
    float dh = dist(P(-2.0, 0.0), G) + dist(G, P(0.0, 2.0)) + dist(A, E) + dist(E, I) + 4.0 * dist(D, H);
    bool dominant = (DOMINANT_DIRECTION_THRESHOLD * dh) < ge;
    blend.w = (ge > dh && neq(E, D) && neq(E, H)) ? (dominant ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
  }
  if (!((eq(B, C) && eq(E, F)) || (eq(B, E) && eq(C, F)))) {
    float ec = dist(D, B) + dist(B, P(1.0, -2.0)) + dist(H, F) + dist(F, P(2.0, -1.0)) + 4.0 * dist(E, C);
    float bf = dist(A, E) + dist(E, I) + dist(P(0.0, -2.0), C) + dist(C, P(2.0, 0.0)) + 4.0 * dist(B, F);
    bool dominant = (DOMINANT_DIRECTION_THRESHOLD * bf) < ec;
    blend.y = (ec > bf && neq(E, B) && neq(E, F)) ? (dominant ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
  }
  if (!((eq(A, B) && eq(D, E)) || (eq(A, D) && eq(B, E)))) {
    float db = dist(P(-2.0, 0.0), A) + dist(A, P(0.0, -2.0)) + dist(G, E) + dist(E, C) + 4.0 * dist(D, B);
    float ae = dist(P(-2.0, -1.0), D) + dist(D, H) + dist(P(-1.0, -2.0), B) + dist(B, F) + 4.0 * dist(A, E);
    bool dominant = (DOMINANT_DIRECTION_THRESHOLD * db) < ae;
    blend.x = (db < ae && neq(E, D) && neq(E, B)) ? (dominant ? BLEND_DOMINANT : BLEND_NORMAL) : BLEND_NONE;
  }

  vec4 code = vec4(0.0);

  if (blend.z != BLEND_NONE) {
    float fg = dist(F, G);
    float hc = dist(H, C);
    bool doLine = blend.z == BLEND_DOMINANT ||
      !((blend.y != BLEND_NONE && !near(E, G)) || (blend.w != BLEND_NONE && !near(E, C)) ||
        (near(G, H) && near(H, I) && near(I, F) && near(F, C) && !near(E, I)));
    code.z = 1.0;
    if (doLine) {
      code.z += 2.0;
      if ((STEEP_DIRECTION_THRESHOLD * fg <= hc) && neq(E, G) && neq(D, G)) code.z += 4.0;
      if ((STEEP_DIRECTION_THRESHOLD * hc <= fg) && neq(E, C) && neq(B, C)) code.z += 8.0;
    }
    if (dist(E, F) <= dist(E, H)) code.z += 16.0;
  }
  if (blend.w != BLEND_NONE) {
    float ha = dist(H, A);
    float di = dist(D, I);
    bool doLine = blend.w == BLEND_DOMINANT ||
      !((blend.z != BLEND_NONE && !near(E, A)) || (blend.x != BLEND_NONE && !near(E, I)) ||
        (near(A, D) && near(D, G) && near(G, H) && near(H, I) && !near(E, G)));
    code.w = 1.0;
    if (doLine) {
      code.w += 2.0;
      if ((STEEP_DIRECTION_THRESHOLD * ha <= di) && neq(E, A) && neq(B, A)) code.w += 4.0;
      if ((STEEP_DIRECTION_THRESHOLD * di <= ha) && neq(E, I) && neq(F, I)) code.w += 8.0;
    }
    if (dist(E, D) <= dist(E, H)) code.w += 16.0;
  }
  if (blend.y != BLEND_NONE) {
    float bi = dist(B, I);
    float fa = dist(F, A);
    bool doLine = blend.y == BLEND_DOMINANT ||
      !((blend.x != BLEND_NONE && !near(E, I)) || (blend.z != BLEND_NONE && !near(E, A)) ||
        (near(I, F) && near(F, C) && near(C, B) && near(B, A) && !near(E, C)));
    code.y = 1.0;
    if (doLine) {
      code.y += 2.0;
      if ((STEEP_DIRECTION_THRESHOLD * bi <= fa) && neq(E, I) && neq(H, I)) code.y += 4.0;
      if ((STEEP_DIRECTION_THRESHOLD * fa <= bi) && neq(E, A) && neq(D, A)) code.y += 8.0;
    }
    if (dist(E, B) <= dist(E, F)) code.y += 16.0;
  }
  if (blend.x != BLEND_NONE) {
    float dc = dist(D, C);
    float bg = dist(B, G);
    bool doLine = blend.x == BLEND_DOMINANT ||
      !((blend.w != BLEND_NONE && !near(E, C)) || (blend.y != BLEND_NONE && !near(E, G)) ||
        (near(C, B) && near(B, A) && near(A, D) && near(D, G) && !near(E, A)));
    code.x = 1.0;
    if (doLine) {
      code.x += 2.0;
      if ((STEEP_DIRECTION_THRESHOLD * dc <= bg) && neq(E, C) && neq(F, C)) code.x += 4.0;
      if ((STEEP_DIRECTION_THRESHOLD * bg <= dc) && neq(E, G) && neq(H, G)) code.x += 8.0;
    }
    if (dist(E, B) <= dist(E, D)) code.x += 16.0;
  }

  return code / 255.0;
}
]]

local SCALE_SOURCE = SHARED_SOURCE .. [[
extern float outScale;
extern Image info;

float leftRatio(vec2 center, vec2 origin, vec2 direction, vec2 scale) {
  vec2 p0 = center - origin;
  vec2 proj = direction * (dot(p0, direction) / dot(direction, direction));
  vec2 orth = vec2(-direction.y, direction.x);
  float side = sign(dot(p0, orth));
  float v = side * length((p0 - proj) * scale);
  return smoothstep(-HALF_SQRT2, HALF_SQRT2, v);
}

// bit `b` (1, 2, 4, ...) of an info code, as 0.0 / 1.0; no integer ops, so
// it runs on GLSL ES 1.0 too
float bit(float code, float b) { return mod(floor(code / b), 2.0); }

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 texel = 1.0 / srcSize;
  vec2 pos = fract(uv * srcSize) - vec2(0.5);
  vec2 coord = uv - pos * texel;

  vec4 E = Texel(tex, coord);
  vec4 code = floor(Texel(info, coord) * 255.0 + 0.5);
  // most of a frame is flat: nothing to blend, so no neighbours to read
  if (code == vec4(0.0)) return E * color;

  vec4 B = Texel(tex, coord + vec2(0.0, -texel.y));
  vec4 D = Texel(tex, coord + vec2(-texel.x, 0.0));
  vec4 F = Texel(tex, coord + vec2(texel.x, 0.0));
  vec4 H = Texel(tex, coord + vec2(0.0, texel.y));
  vec2 scale = vec2(outScale);
  vec4 res = E;

  if (code.z > 0.0) {
    vec2 origin = vec2(0.0, HALF_SQRT2);
    vec2 direction = vec2(1.0, -1.0);
    if (bit(code.z, 2.0) > 0.5) {
      float shallow = bit(code.z, 4.0);
      origin = vec2(0.0, 0.5 - 0.25 * shallow);
      direction.x += shallow;
      direction.y -= bit(code.z, 8.0);
    }
    vec4 pix = bit(code.z, 16.0) > 0.5 ? F : H;
    res = mix(res, pix, leftRatio(pos, origin, direction, scale));
  }
  if (code.w > 0.0) {
    vec2 origin = vec2(-HALF_SQRT2, 0.0);
    vec2 direction = vec2(1.0, 1.0);
    if (bit(code.w, 2.0) > 0.5) {
      float shallow = bit(code.w, 4.0);
      origin = vec2(-0.5 + 0.25 * shallow, 0.0);
      direction.y += shallow;
      direction.x += bit(code.w, 8.0);
    }
    vec4 pix = bit(code.w, 16.0) > 0.5 ? D : H;
    res = mix(res, pix, leftRatio(pos, origin, direction, scale));
  }
  if (code.y > 0.0) {
    vec2 origin = vec2(HALF_SQRT2, 0.0);
    vec2 direction = vec2(-1.0, -1.0);
    if (bit(code.y, 2.0) > 0.5) {
      float shallow = bit(code.y, 4.0);
      origin = vec2(0.5 - 0.25 * shallow, 0.0);
      direction.y -= shallow;
      direction.x -= bit(code.y, 8.0);
    }
    vec4 pix = bit(code.y, 16.0) > 0.5 ? B : F;
    res = mix(res, pix, leftRatio(pos, origin, direction, scale));
  }
  if (code.x > 0.0) {
    vec2 origin = vec2(0.0, -HALF_SQRT2);
    vec2 direction = vec2(-1.0, 1.0);
    if (bit(code.x, 2.0) > 0.5) {
      float shallow = bit(code.x, 4.0);
      origin = vec2(0.0, -0.5 + 0.25 * shallow);
      direction.x -= shallow;
      direction.y += bit(code.x, 8.0);
    }
    vec4 pix = bit(code.x, 16.0) > 0.5 ? B : D;
    res = mix(res, pix, leftRatio(pos, origin, direction, scale));
  }

  return res * color;
}
]]
Xbrz.ANALYZE_SOURCE = ANALYZE_SOURCE
Xbrz.SCALE_SOURCE = SCALE_SOURCE

-- nil = not built yet, false = the driver refused one (logged once, and the
-- filter then reports inactive so the frame falls back to the plain blit),
-- else { analyze = Shader, scale = Shader }
local shaders = nil

local function getShaders()
  if shaders == nil then
    if not (love and love.graphics and love.graphics.newShader) then
      shaders = false
      return nil
    end
    local okA, analyze = pcall(love.graphics.newShader, ANALYZE_SOURCE)
    local okS, scale = pcall(love.graphics.newShader, SCALE_SOURCE)
    if okA and analyze and okS and scale then
      shaders = { analyze = analyze, scale = scale }
    else
      shaders = false
      Logger.error("PIXEL FILTER: xBRZ shader failed to compile: %s",
        tostring(okA and scale or analyze))
    end
  end
  return shaders or nil
end

local Performance = nil

-- Whether the final present should run through xBRZ this frame.  The
-- PERFORMANCE tier's `xbrz` cap turns it off on the low tier without
-- rewriting the player's choice, the way TILT and SHADER FX clamp.
function Xbrz.active()
  if Xbrz.mode ~= "xbrz" then return false end
  Performance = Performance or require("src.core.Performance")
  local caps = Performance.CAPS[Performance.tier]
  if caps and caps.xbrz == false then return false end
  return getShaders() ~= nil
end

-- ------- present

-- Per layer ("main", "ui"): the crop canvas, its info canvas and the crop
-- quad, reallocated only on a real size change, so a steady frame allocates
-- nothing.
local layerCache = {}
-- reused for every srcSize send
local sizeBuf = { 0, 0 }

-- The run of whole source pixels covering [lo, lo + len) on an axis whose
-- pixel 0 starts at `origin`, `s` physical pixels apiece.  Returns the first
-- pixel's physical start and the pixel count.
local function gridSpan(lo, len, origin, s)
  local first = math.floor((lo - origin) / s + 1e-6)
  local last = math.ceil((lo + len - origin) / s - 1e-6)
  return origin + first * s, math.max(1, last - first)
end
Xbrz._gridSpan = gridSpan

local function layerSlot(layer, cols, rows)
  local slot = layerCache[layer]
  if not slot or slot.cols ~= cols or slot.rows ~= rows then
    -- explicit rgba8: the info codes must round-trip exactly, which an sRGB
    -- canvas (LOVE's default under gamma-correct rendering) would not
    local info = love.graphics.newCanvas(cols, rows, { dpiscale = 1, format = "rgba8" })
    info:setFilter("nearest", "nearest")
    slot = {
      cols = cols, rows = rows, info = info,
      src = PixelCanvas.new(cols, rows, "nearest"),
      quad = love.graphics.newQuad(0, 0, 1, 1, 1, 1),
    }
    layerCache[layer] = slot
  end
  return slot
end

-- Read `canvas` back down to one texel per source pixel -- each output texel
-- samples the physical pixel at the centre of its block, which lands inside
-- the block for any scale >= 1, integer or not -- then run ANALYZE over that
-- into the slot's info canvas.
local function prepare(canvas, layer, gx, gy, cols, rows, s, analyze)
  local slot = layerSlot(layer, cols, rows)
  local minF, magF = canvas:getFilter()
  canvas:setFilter("nearest", "nearest")
  slot.quad:setViewport(gx, gy, cols * s, rows * s,
    canvas:getPixelWidth(), canvas:getPixelHeight())
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setCanvas(slot.src)
  love.graphics.setShader()
  love.graphics.draw(canvas, slot.quad, 0, 0, 0, 1 / s, 1 / s)
  love.graphics.setCanvas(slot.info)
  -- "replace" alone still multiplies RGB by alpha on write, which would
  -- scramble three corners' codes with the fourth's
  love.graphics.setBlendMode("replace", "premultiplied")
  love.graphics.setShader(analyze)
  sizeBuf[1], sizeBuf[2] = cols, rows
  analyze:send("srcSize", sizeBuf)
  love.graphics.draw(slot.src, 0, 0)
  love.graphics.pop()
  canvas:setFilter(minF, magF)
  return slot
end

-- Same contract as ShaderFX.render: `canvas` is the finished window-size
-- composite, `rect` the area to shade in PHYSICAL pixels with `rect.scale`
-- physical pixels per source pixel, and opts.originX/originY the physical
-- position of a source pixel's top-left corner, which pins the grid.
-- `opts.mask` composites a transparent layer (the UI a zoomed world split
-- off) over what is already on screen instead of replacing it.
function Xbrz.render(canvas, rect, source, dpiX, dpiY, opts)
  local sh = getShaders()
  local masked = opts and opts.mask
  local s = tonumber(rect.scale)
  dpiX, dpiY = tonumber(dpiX) or 1, tonumber(dpiY) or 1
  if not sh or not s or s < 1 then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, 0, 0)
    return
  end
  local originX = tonumber(opts and opts.originX) or rect.x
  local originY = tonumber(opts and opts.originY) or rect.y
  local gx, cols = gridSpan(rect.x, rect.w, originX, s)
  local gy, rows = gridSpan(rect.y, rect.h, originY, s)

  local clipX = love.graphics.getScissor()
  love.graphics.flushBatch()
  local ok, slot = pcall(prepare, canvas, (opts and opts.layer) or "main",
    gx, gy, cols, rows, s, sh.analyze)

  love.graphics.setColor(1, 1, 1, 1)
  if not masked then
    -- what the grid does not cover (a cutout's surround) still shows
    love.graphics.setBlendMode("replace")
    love.graphics.draw(canvas, 0, 0)
  end
  if not ok then
    Logger.error("PIXEL FILTER: crop failed: %s", tostring(slot))
    if masked then
      love.graphics.setBlendMode("alpha")
      love.graphics.draw(canvas, 0, 0)
    end
    love.graphics.setBlendMode("alpha")
    return
  end

  -- the grid overhangs the rect by up to a source pixel on each side
  if not clipX then
    love.graphics.setScissor(math.floor(rect.x / dpiX), math.floor(rect.y / dpiY),
      math.ceil(rect.w / dpiX), math.ceil(rect.h / dpiY))
  end
  local scale = sh.scale
  love.graphics.setShader(scale)
  scale:send("srcSize", sizeBuf)
  scale:send("outScale", s)
  scale:send("info", slot.info)
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.draw(slot.src, gx / dpiX, gy / dpiY, 0, s / dpiX, s / dpiY)
  love.graphics.setShader()
  love.graphics.setBlendMode("alpha")
  if not clipX then love.graphics.setScissor() end
end

return Xbrz
