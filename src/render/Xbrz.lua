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
-- The shader then scales that grid straight to the output size in a single
-- pass ("freescale"), so any window size works without a 2x/3x/4x ladder.
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

-- ------- shader

local SHADER_SOURCE = [[
#define BLEND_NONE 0.0
#define BLEND_NORMAL 1.0
#define BLEND_DOMINANT 2.0
#define LUMINANCE_WEIGHT 1.0
#define EQUAL_COLOR_TOLERANCE (30.0 / 255.0)
#define STEEP_DIRECTION_THRESHOLD 2.2
#define DOMINANT_DIRECTION_THRESHOLD 3.6
#define HALF_SQRT2 0.70710678

extern vec2 srcSize;
extern float outScale;

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

float leftRatio(vec2 center, vec2 origin, vec2 direction, vec2 scale) {
  vec2 p0 = center - origin;
  vec2 proj = direction * (dot(p0, direction) / dot(direction, direction));
  vec2 orth = vec2(-direction.y, direction.x);
  float side = sign(dot(p0, orth));
  float v = side * length((p0 - proj) * scale);
  return smoothstep(-HALF_SQRT2, HALF_SQRT2, v);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 texel = 1.0 / srcSize;
  vec2 scale = vec2(outScale);
  vec2 pos = fract(uv * srcSize) - vec2(0.5);
  vec2 coord = uv - pos * texel;

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

  vec4 res = E;

  if (blend.z != BLEND_NONE) {
    float fg = dist(F, G);
    float hc = dist(H, C);
    bool doLine = blend.z == BLEND_DOMINANT ||
      !((blend.y != BLEND_NONE && !near(E, G)) || (blend.w != BLEND_NONE && !near(E, C)) ||
        (near(G, H) && near(H, I) && near(I, F) && near(F, C) && !near(E, I)));
    vec2 origin = vec2(0.0, HALF_SQRT2);
    vec2 direction = vec2(1.0, -1.0);
    if (doLine) {
      bool shallow = (STEEP_DIRECTION_THRESHOLD * fg <= hc) && neq(E, G) && neq(D, G);
      bool steep = (STEEP_DIRECTION_THRESHOLD * hc <= fg) && neq(E, C) && neq(B, C);
      origin = shallow ? vec2(0.0, 0.25) : vec2(0.0, 0.5);
      direction.x += shallow ? 1.0 : 0.0;
      direction.y -= steep ? 1.0 : 0.0;
    }
    vec4 pix = mix(H, F, step(dist(E, F), dist(E, H)));
    res = mix(res, pix, leftRatio(pos, origin, direction, scale));
  }
  if (blend.w != BLEND_NONE) {
    float ha = dist(H, A);
    float di = dist(D, I);
    bool doLine = blend.w == BLEND_DOMINANT ||
      !((blend.z != BLEND_NONE && !near(E, A)) || (blend.x != BLEND_NONE && !near(E, I)) ||
        (near(A, D) && near(D, G) && near(G, H) && near(H, I) && !near(E, G)));
    vec2 origin = vec2(-HALF_SQRT2, 0.0);
    vec2 direction = vec2(1.0, 1.0);
    if (doLine) {
      bool shallow = (STEEP_DIRECTION_THRESHOLD * ha <= di) && neq(E, A) && neq(B, A);
      bool steep = (STEEP_DIRECTION_THRESHOLD * di <= ha) && neq(E, I) && neq(F, I);
      origin = shallow ? vec2(-0.25, 0.0) : vec2(-0.5, 0.0);
      direction.y += shallow ? 1.0 : 0.0;
      direction.x += steep ? 1.0 : 0.0;
    }
    vec4 pix = mix(H, D, step(dist(E, D), dist(E, H)));
    res = mix(res, pix, leftRatio(pos, origin, direction, scale));
  }
  if (blend.y != BLEND_NONE) {
    float bi = dist(B, I);
    float fa = dist(F, A);
    bool doLine = blend.y == BLEND_DOMINANT ||
      !((blend.x != BLEND_NONE && !near(E, I)) || (blend.z != BLEND_NONE && !near(E, A)) ||
        (near(I, F) && near(F, C) && near(C, B) && near(B, A) && !near(E, C)));
    vec2 origin = vec2(HALF_SQRT2, 0.0);
    vec2 direction = vec2(-1.0, -1.0);
    if (doLine) {
      bool shallow = (STEEP_DIRECTION_THRESHOLD * bi <= fa) && neq(E, I) && neq(H, I);
      bool steep = (STEEP_DIRECTION_THRESHOLD * fa <= bi) && neq(E, A) && neq(D, A);
      origin = shallow ? vec2(0.25, 0.0) : vec2(0.5, 0.0);
      direction.y -= shallow ? 1.0 : 0.0;
      direction.x -= steep ? 1.0 : 0.0;
    }
    vec4 pix = mix(F, B, step(dist(E, B), dist(E, F)));
    res = mix(res, pix, leftRatio(pos, origin, direction, scale));
  }
  if (blend.x != BLEND_NONE) {
    float dc = dist(D, C);
    float bg = dist(B, G);
    bool doLine = blend.x == BLEND_DOMINANT ||
      !((blend.w != BLEND_NONE && !near(E, C)) || (blend.y != BLEND_NONE && !near(E, G)) ||
        (near(C, B) && near(B, A) && near(A, D) && near(D, G) && !near(E, A)));
    vec2 origin = vec2(0.0, -HALF_SQRT2);
    vec2 direction = vec2(-1.0, 1.0);
    if (doLine) {
      bool shallow = (STEEP_DIRECTION_THRESHOLD * dc <= bg) && neq(E, C) && neq(F, C);
      bool steep = (STEEP_DIRECTION_THRESHOLD * bg <= dc) && neq(E, G) && neq(H, G);
      origin = shallow ? vec2(0.0, -0.25) : vec2(0.0, -0.5);
      direction.x -= shallow ? 1.0 : 0.0;
      direction.y += steep ? 1.0 : 0.0;
    }
    vec4 pix = mix(D, B, step(dist(E, B), dist(E, D)));
    res = mix(res, pix, leftRatio(pos, origin, direction, scale));
  }

  return res * color;
}
]]
Xbrz.SHADER_SOURCE = SHADER_SOURCE

-- nil = not built yet, false = the driver refused it (logged once, and the
-- filter then reports inactive so the frame falls back to the plain blit)
local shader = nil

local function getShader()
  if shader == nil then
    if not (love and love.graphics and love.graphics.newShader) then
      shader = false
      return nil
    end
    local ok, result = pcall(love.graphics.newShader, SHADER_SOURCE)
    if ok and result then
      shader = result
    else
      shader = false
      Logger.error("PIXEL FILTER: xBRZ shader failed to compile: %s", tostring(result))
    end
  end
  return shader or nil
end

-- Whether the final present should run through xBRZ this frame.  The
-- PERFORMANCE tier's `xbrz` cap turns it off on the low tier without
-- rewriting the player's choice, the way TILT and SHADER FX clamp.
function Xbrz.active()
  if Xbrz.mode ~= "xbrz" then return false end
  local Performance = require("src.core.Performance")
  local caps = Performance.CAPS[Performance.tier]
  if caps and caps.xbrz == false then return false end
  return getShader() ~= nil
end

-- ------- present

-- One crop canvas per layer ("main", "ui"), reallocated only on a real size
-- change, the same caching ShaderFX's crop uses.
local cropCache = {}

-- The run of whole source pixels covering [lo, lo + len) on an axis whose
-- pixel 0 starts at `origin`, `s` physical pixels apiece.  Returns the first
-- pixel's physical start and the pixel count.
local function gridSpan(lo, len, origin, s)
  local first = math.floor((lo - origin) / s + 1e-6)
  local last = math.ceil((lo + len - origin) / s - 1e-6)
  return origin + first * s, math.max(1, last - first)
end
Xbrz._gridSpan = gridSpan

-- Read `canvas` back down to one texel per source pixel: each output texel
-- samples the physical pixel at the centre of its block, which lands inside
-- the block for any scale >= 1, integer or not.
local function cropToSource(canvas, layer, gx, gy, cols, rows, s)
  local out = cropCache[layer]
  if not out or out:getWidth() ~= cols or out:getHeight() ~= rows then
    out = PixelCanvas.new(cols, rows, "nearest")
    cropCache[layer] = out
  end
  local minF, magF = canvas:getFilter()
  canvas:setFilter("nearest", "nearest")
  local quad = love.graphics.newQuad(gx, gy, cols * s, rows * s,
    canvas:getPixelWidth(), canvas:getPixelHeight())
  love.graphics.push("all")
  love.graphics.setCanvas(out)
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setShader()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, quad, 0, 0, 0, 1 / s, 1 / s)
  love.graphics.pop()
  canvas:setFilter(minF, magF)
  return out
end

-- Same contract as ShaderFX.render: `canvas` is the finished window-size
-- composite, `rect` the area to shade in PHYSICAL pixels with `rect.scale`
-- physical pixels per source pixel, and opts.originX/originY the physical
-- position of a source pixel's top-left corner, which pins the grid.
-- `opts.mask` composites a transparent layer (the UI a zoomed world split
-- off) over what is already on screen instead of replacing it.
function Xbrz.render(canvas, rect, source, dpiX, dpiY, opts)
  local sh = getShader()
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

  local clipX, clipY, clipW, clipH = love.graphics.getScissor()
  love.graphics.flushBatch()
  local ok, src = pcall(cropToSource, canvas, (opts and opts.layer) or "main",
    gx, gy, cols, rows, s)

  love.graphics.setColor(1, 1, 1, 1)
  if not masked then
    -- what the grid does not cover (a cutout's surround) still shows
    love.graphics.setBlendMode("replace")
    love.graphics.draw(canvas, 0, 0)
  end
  if not ok then
    Logger.error("PIXEL FILTER: crop failed: %s", tostring(src))
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
  love.graphics.setShader(sh)
  sh:send("srcSize", { cols, rows })
  sh:send("outScale", s)
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.draw(src, gx / dpiX, gy / dpiY, 0, s / dpiX, s / dpiY)
  love.graphics.setShader()
  love.graphics.setBlendMode("alpha")
  if not clipX then love.graphics.setScissor() end
end

return Xbrz
