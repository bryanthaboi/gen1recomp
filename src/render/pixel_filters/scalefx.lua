-- PIXEL FILTER "scalefx": ScaleFX.  Driven by src/render/PixelFilter.lua.
--
-- An edge interpolator made for pixel art: it follows slopes up to level 6
-- and every output pixel is a colour already present in the source, so it
-- smooths lines without inventing blends -- kinder than xBRZ to detailed,
-- dithered GBA art.  ScaleFX produces exactly 3x, so its last pass writes a
-- 3x grid and the output pass fits that to the window with sharp-bilinear
-- (src/render/pixel_filters/sharp.lua), keeping subpixels even at any scale.
--
-- Passes, as libretro's scalefx.slangp: metric and strength (float canvases,
-- the comparisons need more than 8 bits), junction rules and edge levels
-- (packed codes, rgba8), then the 3x subpixel pick.  The metric also weighs
-- alpha, so the transparent UI layer's edges read as edges; on opaque frames
-- it is the reference metric.  Parameters are the preset's defaults
-- (threshold 0.5, filter AA and corners on).
--
-- ScaleFX by Sp00kyFox, 2016 (MIT):
--
-- Copyright (c) 2016 Sp00kyFox - ScaleFX@web.de
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

local Sharp = require("src.render.pixel_filters.sharp")

-- Every pass but the last runs at 1x; `coord` is the centre of this texel.
local HEAD = [[
extern vec2 srcSize;
]]

-- Pass 0: colour distance from E to A, B, C and F.
local METRIC = HEAD .. [[
// Reference: http://www.compuphase.com/cmetric.htm, plus alpha
float dist(vec4 A, vec4 B) {
  float r = 0.5 * (A.r + B.r);
  vec4 d = A - B;
  vec3 c = vec3(2.0 + r, 4.0, 3.0 - r);
  return sqrt(dot(c * d.rgb, d.rgb) + 9.0 * d.a * d.a) / 3.0;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 texel = 1.0 / srcSize;
  vec2 coord = (floor(uv * srcSize) + vec2(0.5)) * texel;
#define TEX(x, y) Texel(tex, coord + texel * vec2(x, y))
  vec4 A = TEX(-1.0, -1.0);
  vec4 B = TEX( 0.0, -1.0);
  vec4 C = TEX( 1.0, -1.0);
  vec4 E = TEX( 0.0,  0.0);
  vec4 F = TEX( 1.0,  0.0);
  return vec4(dist(E, A), dist(E, B), dist(E, C), dist(E, F));
}
]]

-- Pass 1: the strength of each corner's interpolation candidate.
local STRENGTH = HEAD .. [[
extern Image sfxMetric;

#define SFX_CLR 0.5

float str(float d, vec2 a, vec2 b) {
  float diff = a.x - a.y;
  float wght1 = max(SFX_CLR - d, 0.0) / SFX_CLR;
  float wght2 = clamp((1.0 - d) + (min(a.x, b.x) + a.x > min(a.y, b.y) + a.y ? diff : -diff), 0.0, 1.0);
  return (wght1 * wght2) * (a.x * a.y);
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 texel = 1.0 / srcSize;
  vec2 coord = (floor(uv * srcSize) + vec2(0.5)) * texel;
#define TEX(x, y) Texel(sfxMetric, coord + texel * vec2(x, y))
  vec4 A = TEX(-1.0, -1.0), B = TEX( 0.0, -1.0);
  vec4 D = TEX(-1.0,  0.0), E = TEX( 0.0,  0.0), F = TEX( 1.0,  0.0);
  vec4 G = TEX(-1.0,  1.0), H = TEX( 0.0,  1.0), I = TEX( 1.0,  1.0);

  vec4 res;
  res.x = str(D.z, vec2(D.w, E.y), vec2(A.w, D.y));
  res.y = str(F.x, vec2(E.w, E.y), vec2(B.w, F.y));
  res.z = str(H.z, vec2(E.w, H.y), vec2(H.w, I.y));
  res.w = str(H.x, vec2(D.w, H.y), vec2(G.w, G.y));
  return res;
}
]]

-- Pass 2: resolve ambiguous junctions and find orthogonal edges.
local RULES = HEAD .. [[
extern Image sfxMetric;
extern Image sfxStrength;

#define LE(x, y) (1.0 - step(y, x))
#define GE(x, y) (1.0 - step(x, y))
#define LEQ(x, y) step(x, y)
#define GEQ(x, y) step(y, x)
#define NOT(x) (1.0 - (x))

// corner dominance at junctions
vec4 dom(vec3 x, vec3 y, vec3 z, vec3 w) {
  return 2.0 * vec4(x.y, y.y, z.y, w.y) - (vec4(x.x, y.x, z.x, w.x) + vec4(x.z, y.z, z.z, w.z));
}

// necessary but not sufficient junction condition for orthogonal edges
float clear(vec2 crn, vec2 a, vec2 b) {
  return (crn.x >= max(min(a.x, a.y), min(b.x, b.y))) && (crn.y >= max(min(a.x, b.y), min(b.x, a.y))) ? 1.0 : 0.0;
}

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 texel = 1.0 / srcSize;
  vec2 coord = (floor(uv * srcSize) + vec2(0.5)) * texel;
#define TEXm(x, y) Texel(sfxMetric, coord + texel * vec2(x, y))
#define TEXs(x, y) Texel(sfxStrength, coord + texel * vec2(x, y))
  vec4 A = TEXm(-1.0, -1.0), B = TEXm( 0.0, -1.0);
  vec4 D = TEXm(-1.0,  0.0), E = TEXm( 0.0,  0.0), F = TEXm( 1.0,  0.0);
  vec4 G = TEXm(-1.0,  1.0), H = TEXm( 0.0,  1.0), I = TEXm( 1.0,  1.0);

  vec4 As = TEXs(-1.0, -1.0), Bs = TEXs( 0.0, -1.0), Cs = TEXs( 1.0, -1.0);
  vec4 Ds = TEXs(-1.0,  0.0), Es = TEXs( 0.0,  0.0), Fs = TEXs( 1.0,  0.0);
  vec4 Gs = TEXs(-1.0,  1.0), Hs = TEXs( 0.0,  1.0), Is = TEXs( 1.0,  1.0);

  // strength & dominance junctions
  vec4 jSx = vec4(As.z, Bs.w, Es.x, Ds.y), jDx = dom(As.yzw, Bs.zwx, Es.wxy, Ds.xyz);
  vec4 jSy = vec4(Bs.z, Cs.w, Fs.x, Es.y), jDy = dom(Bs.yzw, Cs.zwx, Fs.wxy, Es.xyz);
  vec4 jSz = vec4(Es.z, Fs.w, Is.x, Hs.y), jDz = dom(Es.yzw, Fs.zwx, Is.wxy, Hs.xyz);
  vec4 jSw = vec4(Ds.z, Es.w, Hs.x, Gs.y), jDw = dom(Ds.yzw, Es.zwx, Hs.wxy, Gs.xyz);

  // majority vote for ambiguous dominance junctions
  vec4 zero4 = vec4(0.0);
  vec4 jx = min(GE(jDx, zero4) * (LEQ(jDx.yzwx, zero4) * LEQ(jDx.wxyz, zero4) + GE(jDx + jDx.zwxy, jDx.yzwx + jDx.wxyz)), 1.0);
  vec4 jy = min(GE(jDy, zero4) * (LEQ(jDy.yzwx, zero4) * LEQ(jDy.wxyz, zero4) + GE(jDy + jDy.zwxy, jDy.yzwx + jDy.wxyz)), 1.0);
  vec4 jz = min(GE(jDz, zero4) * (LEQ(jDz.yzwx, zero4) * LEQ(jDz.wxyz, zero4) + GE(jDz + jDz.zwxy, jDz.yzwx + jDz.wxyz)), 1.0);
  vec4 jw = min(GE(jDw, zero4) * (LEQ(jDw.yzwx, zero4) * LEQ(jDw.wxyz, zero4) + GE(jDw + jDw.zwxy, jDw.yzwx + jDw.wxyz)), 1.0);

  // inject strength without creating new contradictions
  vec4 res;
  res.x = min(jx.z + NOT(jx.y) * NOT(jx.w) * GE(jSx.z, 0.0) * (jx.x + GE(jSx.x + jSx.z, jSx.y + jSx.w)), 1.0);
  res.y = min(jy.w + NOT(jy.z) * NOT(jy.x) * GE(jSy.w, 0.0) * (jy.y + GE(jSy.y + jSy.w, jSy.x + jSy.z)), 1.0);
  res.z = min(jz.x + NOT(jz.w) * NOT(jz.y) * GE(jSz.x, 0.0) * (jz.z + GE(jSz.x + jSz.z, jSz.y + jSz.w)), 1.0);
  res.w = min(jw.y + NOT(jw.x) * NOT(jw.z) * GE(jSw.y, 0.0) * (jw.w + GE(jSw.y + jSw.w, jSw.x + jSw.z)), 1.0);

  // single pixel & end of line detection
  res = min(res * (vec4(jx.z, jy.w, jz.x, jw.y) + NOT(res.wxyz * res.yzwx)), 1.0);

  vec4 clr;
  clr.x = clear(vec2(D.z, E.x), vec2(D.w, E.y), vec2(A.w, D.y));
  clr.y = clear(vec2(F.x, E.z), vec2(E.w, E.y), vec2(B.w, F.y));
  clr.z = clear(vec2(H.z, I.x), vec2(E.w, H.y), vec2(H.w, I.y));
  clr.w = clear(vec2(H.x, G.z), vec2(D.w, H.y), vec2(G.w, G.y));

  vec4 h = vec4(min(D.w, A.w), min(E.w, B.w), min(E.w, H.w), min(D.w, G.w));
  vec4 v = vec4(min(E.y, D.y), min(E.y, F.y), min(H.y, I.y), min(H.y, G.y));

  vec4 orien = GE(h + vec4(D.w, E.w, E.w, D.w), v + vec4(E.y, E.y, H.y, H.y)); // orientation
  vec4 hori  = LE(h, v) * clr; // horizontal edges
  vec4 vert  = GE(h, v) * clr; // vertical edges

  return (res + 2.0 * hori + 4.0 * vert + 8.0 * orien) / 15.0;
}
]]

-- Pass 3: edge levels 1-6, as the subpixel each 3x cell copies.
local LEVELS = HEAD .. [[
extern Image sfxRules;

// the four bool4s packed into each rules texel
bvec4 loadCorn(vec4 x) { return bvec4(floor(mod(x * 15.0 + 0.5, 2.0))); }
bvec4 loadHori(vec4 x) { return bvec4(floor(mod(x * 7.5 + 0.25, 2.0))); }
bvec4 loadVert(vec4 x) { return bvec4(floor(mod(x * 3.75 + 0.125, 2.0))); }
bvec4 loadOr(vec4 x) { return bvec4(floor(mod(x * 1.875 + 0.0625, 2.0))); }

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 texel = 1.0 / srcSize;
  vec2 coord = (floor(uv * srcSize) + vec2(0.5)) * texel;
#define TEX(x, y) Texel(sfxRules, coord + texel * vec2(x, y))
  vec4 E = TEX( 0.0, 0.0);
  vec4 D = TEX(-1.0, 0.0), D0 = TEX(-2.0, 0.0), D1 = TEX(-3.0, 0.0);
  vec4 F = TEX( 1.0, 0.0), F0 = TEX( 2.0, 0.0), F1 = TEX( 3.0, 0.0);
  vec4 B = TEX( 0.0,-1.0), B0 = TEX( 0.0,-2.0), B1 = TEX( 0.0,-3.0);
  vec4 H = TEX( 0.0, 1.0), H0 = TEX( 0.0, 2.0), H1 = TEX( 0.0, 3.0);

  bvec4 Ec = loadCorn(E), Eh = loadHori(E), Ev = loadVert(E), Eo = loadOr(E);
  bvec4 Dc = loadCorn(D), Dh = loadHori(D), Do = loadOr(D), D0c = loadCorn(D0), D0h = loadHori(D0), D1h = loadHori(D1);
  bvec4 Fc = loadCorn(F), Fh = loadHori(F), Fo = loadOr(F), F0c = loadCorn(F0), F0h = loadHori(F0), F1h = loadHori(F1);
  bvec4 Bc = loadCorn(B), Bv = loadVert(B), Bo = loadOr(B), B0c = loadCorn(B0), B0v = loadVert(B0), B1v = loadVert(B1);
  bvec4 Hc = loadCorn(H), Hv = loadVert(H), Ho = loadOr(H), H0c = loadCorn(H0), H0v = loadVert(H0), H1v = loadVert(H1);

  // lvl1 corners (filter corners on)
  bool lvl1x = Ec.x;
  bool lvl1y = Ec.y;
  bool lvl1z = Ec.z;
  bool lvl1w = Ec.w;

  // lvl2 mid (left, right / up, down)
  bvec2 lvl2x = bvec2((Ec.x && Eh.y) && Dc.z, (Ec.y && Eh.x) && Fc.w);
  bvec2 lvl2y = bvec2((Ec.y && Ev.z) && Bc.w, (Ec.z && Ev.y) && Hc.x);
  bvec2 lvl2z = bvec2((Ec.w && Eh.z) && Dc.y, (Ec.z && Eh.w) && Fc.x);
  bvec2 lvl2w = bvec2((Ec.x && Ev.w) && Bc.z, (Ec.w && Ev.x) && Hc.y);

  // lvl3 corners (hori, vert)
  bvec2 lvl3x = bvec2(lvl2x.y && (Dh.y && Dh.x) && Fh.z, lvl2w.y && (Bv.w && Bv.x) && Hv.z);
  bvec2 lvl3y = bvec2(lvl2x.x && (Fh.x && Fh.y) && Dh.w, lvl2y.y && (Bv.z && Bv.y) && Hv.w);
  bvec2 lvl3z = bvec2(lvl2z.x && (Fh.w && Fh.z) && Dh.x, lvl2y.x && (Hv.y && Hv.z) && Bv.x);
  bvec2 lvl3w = bvec2(lvl2z.y && (Dh.z && Dh.w) && Fh.y, lvl2w.x && (Hv.x && Hv.w) && Bv.y);

  // lvl4 corners (hori, vert)
  bvec2 lvl4x = bvec2((Dc.x && Dh.y && Eh.x && Eh.y && Fh.x && Fh.y) && (D0c.z && D0h.w), (Bc.x && Bv.w && Ev.x && Ev.w && Hv.x && Hv.w) && (B0c.z && B0v.y));
  bvec2 lvl4y = bvec2((Fc.y && Fh.x && Eh.y && Eh.x && Dh.y && Dh.x) && (F0c.w && F0h.z), (Bc.y && Bv.z && Ev.y && Ev.z && Hv.y && Hv.z) && (B0c.w && B0v.x));
  bvec2 lvl4z = bvec2((Fc.z && Fh.w && Eh.z && Eh.w && Dh.z && Dh.w) && (F0c.x && F0h.y), (Hc.z && Hv.y && Ev.z && Ev.y && Bv.z && Bv.y) && (H0c.x && H0v.w));
  bvec2 lvl4w = bvec2((Dc.w && Dh.z && Eh.w && Eh.z && Fh.w && Fh.z) && (D0c.y && D0h.x), (Hc.w && Hv.x && Ev.w && Ev.x && Bv.w && Bv.x) && (H0c.y && H0v.z));

  // lvl5 mid (left, right / up, down)
  bvec2 lvl5x = bvec2(lvl4x.x && (F0h.x && F0h.y) && (D1h.z && D1h.w), lvl4y.x && (D0h.y && D0h.x) && (F1h.w && F1h.z));
  bvec2 lvl5y = bvec2(lvl4y.y && (H0v.y && H0v.z) && (B1v.w && B1v.x), lvl4z.y && (B0v.z && B0v.y) && (H1v.x && H1v.w));
  bvec2 lvl5z = bvec2(lvl4w.x && (F0h.w && F0h.z) && (D1h.y && D1h.x), lvl4z.x && (D0h.z && D0h.w) && (F1h.x && F1h.y));
  bvec2 lvl5w = bvec2(lvl4x.y && (H0v.x && H0v.w) && (B1v.z && B1v.y), lvl4w.y && (B0v.w && B0v.x) && (H1v.y && H1v.z));

  // lvl6 corners (hori, vert)
  bvec2 lvl6x = bvec2(lvl5x.y && (D1h.y && D1h.x), lvl5w.y && (B1v.w && B1v.x));
  bvec2 lvl6y = bvec2(lvl5x.x && (F1h.x && F1h.y), lvl5y.y && (B1v.z && B1v.y));
  bvec2 lvl6z = bvec2(lvl5z.x && (F1h.w && F1h.z), lvl5y.x && (H1v.y && H1v.z));
  bvec2 lvl6w = bvec2(lvl5z.y && (D1h.z && D1h.w), lvl5w.x && (H1v.x && H1v.w));

  // subpixels - 0 = E, 1 = D, 2 = D0, 3 = F, 4 = F0, 5 = B, 6 = B0, 7 = H, 8 = H0
  vec4 crn;
  crn.x = (lvl1x && Eo.x || lvl3x.x && Eo.y || lvl4x.x && Do.x || lvl6x.x && Fo.y) ? 5.0 : (lvl1x || lvl3x.y && !Eo.w || lvl4x.y && !Bo.x || lvl6x.y && !Ho.w) ? 1.0 : lvl3x.x ? 3.0 : lvl3x.y ? 7.0 : lvl4x.x ? 2.0 : lvl4x.y ? 6.0 : lvl6x.x ? 4.0 : lvl6x.y ? 8.0 : 0.0;
  crn.y = (lvl1y && Eo.y || lvl3y.x && Eo.x || lvl4y.x && Fo.y || lvl6y.x && Do.x) ? 5.0 : (lvl1y || lvl3y.y && !Eo.z || lvl4y.y && !Bo.y || lvl6y.y && !Ho.z) ? 3.0 : lvl3y.x ? 1.0 : lvl3y.y ? 7.0 : lvl4y.x ? 4.0 : lvl4y.y ? 6.0 : lvl6y.x ? 2.0 : lvl6y.y ? 8.0 : 0.0;
  crn.z = (lvl1z && Eo.z || lvl3z.x && Eo.w || lvl4z.x && Fo.z || lvl6z.x && Do.w) ? 7.0 : (lvl1z || lvl3z.y && !Eo.y || lvl4z.y && !Ho.z || lvl6z.y && !Bo.y) ? 3.0 : lvl3z.x ? 1.0 : lvl3z.y ? 5.0 : lvl4z.x ? 4.0 : lvl4z.y ? 8.0 : lvl6z.x ? 2.0 : lvl6z.y ? 6.0 : 0.0;
  crn.w = (lvl1w && Eo.w || lvl3w.x && Eo.z || lvl4w.x && Do.w || lvl6w.x && Fo.z) ? 7.0 : (lvl1w || lvl3w.y && !Eo.x || lvl4w.y && !Ho.w || lvl6w.y && !Bo.x) ? 1.0 : lvl3w.x ? 3.0 : lvl3w.y ? 5.0 : lvl4w.x ? 2.0 : lvl4w.y ? 8.0 : lvl6w.x ? 4.0 : lvl6w.y ? 6.0 : 0.0;

  vec4 mid;
  mid.x = (lvl2x.x &&  Eo.x || lvl2x.y &&  Eo.y || lvl5x.x &&  Do.x || lvl5x.y &&  Fo.y) ? 5.0 : lvl2x.x ? 1.0 : lvl2x.y ? 3.0 : lvl5x.x ? 2.0 : lvl5x.y ? 4.0 : (Ec.x && Dc.z && Ec.y && Fc.w) ? ( Eo.x ?  Eo.y ? 5.0 : 3.0 : 1.0) : 0.0;
  mid.y = (lvl2y.x && !Eo.y || lvl2y.y && !Eo.z || lvl5y.x && !Bo.y || lvl5y.y && !Ho.z) ? 3.0 : lvl2y.x ? 5.0 : lvl2y.y ? 7.0 : lvl5y.x ? 6.0 : lvl5y.y ? 8.0 : (Ec.y && Bc.w && Ec.z && Hc.x) ? (!Eo.y ? !Eo.z ? 3.0 : 7.0 : 5.0) : 0.0;
  mid.z = (lvl2z.x &&  Eo.w || lvl2z.y &&  Eo.z || lvl5z.x &&  Do.w || lvl5z.y &&  Fo.z) ? 7.0 : lvl2z.x ? 1.0 : lvl2z.y ? 3.0 : lvl5z.x ? 2.0 : lvl5z.y ? 4.0 : (Ec.z && Fc.x && Ec.w && Dc.y) ? ( Eo.z ?  Eo.w ? 7.0 : 1.0 : 3.0) : 0.0;
  mid.w = (lvl2w.x && !Eo.x || lvl2w.y && !Eo.w || lvl5w.x && !Bo.x || lvl5w.y && !Ho.w) ? 1.0 : lvl2w.x ? 5.0 : lvl2w.y ? 7.0 : lvl5w.x ? 6.0 : lvl5w.y ? 8.0 : (Ec.w && Hc.y && Ec.x && Bc.z) ? (!Eo.w ? !Eo.x ? 1.0 : 5.0 : 7.0) : 0.0;

  return (crn + 9.0 * mid) / 80.0;
}
]]

-- Pass 4, drawn into a 3x canvas: each subpixel copies the source pixel its
-- level picked.
local SUBPIXELS = [[
extern vec2 srcSize;
extern Image sfxLevels;

vec4 loadCrn(vec4 x) { return floor(mod(x * 80.0 + 0.5, 9.0)); }
vec4 loadMid(vec4 x) { return floor(mod(x * 8.888888 + 0.055555, 9.0)); }

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  vec2 texel = 1.0 / srcSize;
  vec2 cell = floor(uv * srcSize);
  vec2 coord = (cell + vec2(0.5)) * texel;
  vec4 E = Texel(sfxLevels, coord);
  vec4 crn = loadCrn(E);
  vec4 mid = loadMid(E);

  vec2 fp = min(floor(3.0 * (uv * srcSize - cell)), vec2(2.0));
  float sp = fp.y == 0.0 ? (fp.x == 0.0 ? crn.x : fp.x == 1.0 ? mid.x : crn.y)
    : (fp.y == 1.0 ? (fp.x == 0.0 ? mid.w : fp.x == 1.0 ? 0.0 : mid.y)
    : (fp.x == 0.0 ? crn.w : fp.x == 1.0 ? mid.z : crn.z));

  // 0 = E, 1 = D, 2 = D0, 3 = F, 4 = F0, 5 = B, 6 = B0, 7 = H, 8 = H0
  vec2 res = sp == 0.0 ? vec2(0.0, 0.0) : sp == 1.0 ? vec2(-1.0, 0.0) : sp == 2.0 ? vec2(-2.0, 0.0)
    : sp == 3.0 ? vec2(1.0, 0.0) : sp == 4.0 ? vec2(2.0, 0.0) : sp == 5.0 ? vec2(0.0, -1.0)
    : sp == 6.0 ? vec2(0.0, -2.0) : sp == 7.0 ? vec2(0.0, 1.0) : vec2(0.0, 2.0);

  return Texel(tex, coord + res * texel);
}
]]

-- Output: the 3x grid fitted to the window.
local OUTPUT = [[
extern vec2 srcSize;
extern float outScale;
extern Image sfx3x;
]] .. Sharp.SAMPLE .. [[
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
  return sharpBilinear(sfx3x, srcSize * 3.0, outScale / 3.0, uv) * color;
}
]]

return {
  id = "scalefx",
  label = "SCALEFX",
  passes = {
    { scope = "source", name = "sfxMetric", format = "rgba16f", source = METRIC },
    { scope = "source", name = "sfxStrength", format = "rgba16f", source = STRENGTH },
    { scope = "source", name = "sfxRules", source = RULES },
    { scope = "source", name = "sfxLevels", source = LEVELS },
    { scope = "source", name = "sfx3x", scale = 3, filter = "linear", source = SUBPIXELS },
    { scope = "output", source = OUTPUT },
  },
}
