-- PIXEL FILTER "sharp": sharp-bilinear.  Driven by src/render/PixelFilter.lua.
--
-- Nearest-neighbour at a fractional scale (FireRed's 240x160 is 6.75x on a
-- 1080p window) makes source pixels alternately 6 and 7 output pixels wide,
-- which shows as uneven pixels and shimmer while the screen scrolls.  This
-- prescales by the largest whole factor and lets the hardware's bilinear
-- blend only the seam left between two pixels, so every pixel keeps a crisp,
-- even interior at any scale and the art itself is never redrawn.  One tap
-- per output pixel, so it is cheap enough to stay on at every PERFORMANCE
-- tier.
--
-- After rsn8887's sharp-bilinear-simple (public domain), as in libretro's
-- pixel-art-scaling shaders.

-- `sharpBilinear(img, size, scale, uv)`: sample `img`, a `size`-texel grid
-- shown at `scale` output pixels per texel, through a linear sampler.
-- Shared with the filters that end on an intermediate grid (scalefx).
local SAMPLE = [[
vec4 sharpBilinear(Image img, vec2 size, float scale, vec2 uv) {
  vec2 texel = uv * size;
  vec2 floored = floor(texel);
  vec2 centerDist = texel - floored - vec2(0.5);
  float k = max(floor(scale), 1.0);
  float range = 0.5 - 0.5 / k;
  vec2 f = (centerDist - clamp(centerDist, -range, range)) * k + vec2(0.5);
  return Texel(img, (floored + f) / size);
}
]]

return {
  id = "sharp",
  label = "SHARP",
  sourceFilter = "linear",
  tiers = { high = true, balanced = true, low = true },
  SAMPLE = SAMPLE,
  passes = {
    { scope = "output", source = [[
extern vec2 srcSize;
extern float outScale;
]] .. SAMPLE .. [[
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  return sharpBilinear(tex, srcSize, outScale, uv) * color;
}
]] },
  },
}
