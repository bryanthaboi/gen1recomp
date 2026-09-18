-- Interior demake (top-down):
--   1) Discover room-wide 4-shade ramps per FRLG palSlot (material codebook)
--   2) Assign each 8×8 quad to the best codebook ramp (majority-pal bias)
--   3) Bake 2bpp against that fixed ramp only
-- Outdoor extract keeps BT.709 path in quantize.lua; this module is indoor-only.

local QuantizeLab = {}

QuantizeLab.W_L = 2.0
QuantizeLab.L_TIE = 1.0          -- |ΔL| below this → hue/chroma tie-break
QuantizeLab.NEAR_DUPE_EPS = 12.0 -- Tuned for standard ramp_dist_lab
-- Outdoor bank/merge: slightly tighter than indoor so sand/water stay apart,
-- but not so tight that buildings fragment into noisy near-dupes.
QuantizeLab.OUTDOOR_NEAR_DUPE_EPS = 8.0
QuantizeLab.MAX_SLOTS = 22 -- per tileset-pair codebook budget (sheet also ≤22)
QuantizeLab.WEIGHT_RATIO_CAP = 2 -- max 2:1 usage weights when blending
QuantizeLab.PALSLOT_ADD = 50.0   -- legacy; unused in top-down bake
QuantizeLab.OUTLIER_DE_MIN = 25.0 -- legacy per-quad path
QuantizeLab.DL_SHIFT_MAX = 10.0  -- material merge: reject if rare→blend |ΔL| exceeds
QuantizeLab.DAB_SHIFT_MAX = 4.0  -- material merge: reject if rare→blend chroma shift exceeds
QuantizeLab.KMEANS_ITERS = 6
QuantizeLab.MIN_MATERIAL_PIXELS = 4
QuantizeLab.MIXED_MIN_PIXELS = 10   -- minority palSlot ≥ this (diagnostics)
QuantizeLab.HUE_SPLIT_DE = 28.0    -- split one FRLG palSlot into 2 materials
QuantizeLab.HUE_SPLIT_MIN_FRAC = 0.18
-- Outdoor locked terrain: one 4-shade ramp family (no tip/base hue split).
QuantizeLab.OUTDOOR_TERRAIN_FAMILY = {
  TREE = "TREE",
  WATER = "WATER",
  SAND = "SAND",
  CLIFF = "CLIFF",
  COAST_CLIFF = "CLIFF",
}
QuantizeLab.BLACK_RAMP = {
  { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 },
}

local function bgr555_to_rgb(c)
  c = c or 0
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return r5 * 255 / 31, g5 * 255 / 31, b5 * 255 / 31
end

-- sRGB 0..255 → XYZ (D65) → CIE L*a*b*
local function rgb_to_lab(r, g, b)
  local function lin(u)
    u = u / 255
    if u <= 0.04045 then return u / 12.92 end
    return ((u + 0.055) / 1.055) ^ 2.4
  end
  local R, G, B = lin(r), lin(g), lin(b)
  local x = R * 0.4124564 + G * 0.3575761 + B * 0.1804375
  local y = R * 0.2126729 + G * 0.7151522 + B * 0.0721750
  local z = R * 0.0193339 + G * 0.1191920 + B * 0.9503041
  -- D65 white
  x, y, z = x / 0.95047, y / 1.0, z / 1.08883
  local function f(t)
    if t > 0.008856 then return t ^ (1 / 3) end
    return (7.787 * t) + (16 / 116)
  end
  local fx, fy, fz = f(x), f(y), f(z)
  local L = (116 * fy) - 16
  local a = 500 * (fx - fy)
  local bb = 200 * (fy - fz)
  return L, a, bb
end

local function lab_to_rgb(L, a, bb)
  local fy = (L + 16) / 116
  local fx = a / 500 + fy
  local fz = fy - bb / 200
  local function finv(t)
    local t3 = t * t * t
    if t3 > 0.008856 then return t3 end
    return (t - 16 / 116) / 7.787
  end
  local x = 0.95047 * finv(fx)
  local y = 1.0 * finv(fy)
  local z = 1.08883 * finv(fz)
  local R = x * 3.2404542 + y * -1.5371385 + z * -0.4985314
  local G = x * -0.9692660 + y * 1.8760108 + z * 0.0415560
  local B = x * 0.0556434 + y * -0.2040259 + z * 1.0572252
  local function gamma(u)
    if u <= 0.0031308 then return 12.92 * u end
    return 1.055 * (u ^ (1 / 2.4)) - 0.055
  end
  local function clamp8(u)
    u = gamma(u) * 255
    if u < 0 then return 0 end
    if u > 255 then return 255 end
    return math.floor(u + 0.5)
  end
  return clamp8(R), clamp8(G), clamp8(B)
end

local function chroma(a, b)
  return math.sqrt(a * a + b * b)
end

-- Cosine vs fixed red reference (a=1, b=0); range [-1, 1]. Safe for hue ties.
local function red_ref_cos(a, b)
  local c = chroma(a, b)
  if c < 1e-6 then return 0 end
  return a / c
end

function QuantizeLab.deltaE_w(L1, a1, b1, L2, a2, b2, wL)
  wL = wL or QuantizeLab.W_L
  local dL = (L1 - L2) * wL
  local da = a1 - a2
  local db = b1 - b2
  return math.sqrt(dL * dL + da * da + db * db)
end

local function deltaE_w_lab(p, q, wL)
  return QuantizeLab.deltaE_w(p.L, p.a, p.b, q.L, q.a, q.b, wL)
end

local function rgb_of_lab(p)
  local r, g, b = lab_to_rgb(p.L, p.a, p.b)
  return { r, g, b }
end

local function copy_lab(p)
  return { L = p.L, a = p.a, b = p.b }
end

local function sort_centroids_light_to_dark(cents)
  table.sort(cents, function(u, v)
    local dL = u.L - v.L
    if math.abs(dL) >= QuantizeLab.L_TIE then
      return u.L > v.L -- lightest first → shade 0
    end
    local cu, cv = red_ref_cos(u.a, u.b), red_ref_cos(v.a, v.b)
    if math.abs(cu - cv) > 1e-9 then
      return cu > cv
    end
    return chroma(u.a, u.b) > chroma(v.a, v.b)
  end)
end

local function encode_2bpp(shades)
  local out = {}
  for y = 0, 7 do
    local low, high = 0, 0
    for x = 0, 7 do
      local shade = shades[y * 8 + x + 1] or 0
      local bit = 7 - x
      local mask = 2 ^ bit
      if shade % 2 == 1 then low = low + mask end
      if math.floor(shade / 2) % 2 == 1 then high = high + mask end
    end
    out[y * 2 + 1] = low
    out[y * 2 + 2] = high
  end
  return out
end

--- Pad unique colours (sorted light→dark) into DMG slots 0=lightest … 3=darkest.
-- Interpolate internal slots so Pass 3 sees a natural ramp (not duplicated dummies).
local function pad_unique_to_ramp(sorted) -- light→dark LAB list
  local n = #sorted
  if n == 0 then
    local g = { L = 50, a = 0, b = 0 }
    return { g, g, g, g }
  elseif n == 1 then
    local c = sorted[1]
    return { c, c, c, c }
  elseif n == 2 then
    local c1, c4 = sorted[1], sorted[2]
    local c2 = {
      L = c1.L * 0.66 + c4.L * 0.34,
      a = c1.a * 0.66 + c4.a * 0.34,
      b = c1.b * 0.66 + c4.b * 0.34,
    }
    local c3 = {
      L = c1.L * 0.34 + c4.L * 0.66,
      a = c1.a * 0.34 + c4.a * 0.66,
      b = c1.b * 0.34 + c4.b * 0.66,
    }
    return { c1, c2, c3, c4 }
  elseif n == 3 then
    local c1, c2, c4 = sorted[1], sorted[2], sorted[3]
    local c3 = {
      L = (c2.L + c4.L) / 2,
      a = (c2.a + c4.a) / 2,
      b = (c2.b + c4.b) / 2,
    }
    return { c1, c2, c3, c4 }
  else
    return { sorted[1], sorted[2], sorted[3], sorted[4] }
  end
end

local function gather_pixels(buf64, pal64)
  local pixels = {}
  local byKey = {}
  local order = {}
  for i = 1, 64 do
    local c = buf64[i] or 0
    local r, g, b = bgr555_to_rgb(c)
    local L, a, bb = rgb_to_lab(r, g, b)
    local palSlot = (pal64 and pal64[i]) or 0
    local p = { L = L, a = a, b = bb, r = r, g = g, idx = i, key = c, palSlot = palSlot }
    pixels[i] = p
    if not byKey[c] then
      byKey[c] = { L = L, a = a, b = bb, r = r, g = g, key = c, n = 0, palSlot = palSlot }
      order[#order + 1] = c
    end
    byKey[c].n = byKey[c].n + 1
  end
  local uniques = {}
  for _, k in ipairs(order) do
    uniques[#uniques + 1] = byKey[k]
  end
  return pixels, uniques
end

local function group_by_palslot(pixels)
  local groups = {} -- palSlot → { pixels }
  local order = {}
  for i = 1, #pixels do
    local p = pixels[i]
    local s = p.palSlot or 0
    if not groups[s] then
      groups[s] = {}
      order[#order + 1] = s
    end
    groups[s][#groups[s] + 1] = p
  end
  table.sort(order, function(a, b)
    if #groups[a] ~= #groups[b] then return #groups[a] > #groups[b] end
    return a < b
  end)
  return groups, order
end

local function mean_lab(list)
  local L, a, b, n = 0, 0, 0, #list
  if n == 0 then return { L = 50, a = 0, b = 0 } end
  for i = 1, n do
    L = L + list[i].L
    a = a + list[i].a
    b = b + list[i].b
  end
  return { L = L / n, a = a / n, b = b / n }
end

--- ΔE_eff: additive palSlot penalty (not multiplicative).
local function deltaE_eff(p, cent)
  local d = deltaE_w_lab(p, cent)
  if (p.palSlot or 0) ~= (cent.palSlot or 0) then
    d = d + QuantizeLab.PALSLOT_ADD
  end
  return d
end

local function nearest_centroid(p, cents)
  local best, bestD = 1, 1e18
  for i = 1, #cents do
    local d = deltaE_eff(p, cents[i])
    if d < bestD then best, bestD = i, d end
  end
  return best, bestD
end

--- Structural outlier: baseline = mean LAB of majority-count palSlot only.
-- Returns locked centroid (with immutable palSlot) or nil.
local function structural_outlier(pixels)
  local groups, order = group_by_palslot(pixels)
  if #order == 0 then return nil end
  local bgSlot = order[1]
  local baseline = mean_lab(groups[bgSlot])
  local best, bestD = nil, -1
  if #order == 1 then
    for i = 1, #pixels do
      local p = pixels[i]
      local d = deltaE_w_lab(p, baseline)
      if d > bestD then bestD, best = d, p end
    end
  else
    for i = 1, #pixels do
      local p = pixels[i]
      if (p.palSlot or 0) ~= bgSlot then
        local d = deltaE_w_lab(p, baseline)
        if d > bestD then bestD, best = d, p end
      end
    end
  end
  if not best or bestD < QuantizeLab.OUTLIER_DE_MIN then
    return nil
  end
  local c = copy_lab(best)
  c.palSlot = best.palSlot or 0
  return c
end

--- Seed k centroids with immutable palSlot from the seed pixel.
-- Pure perceptual farthest-point (k-means++); do NOT dedicate seeds to every
-- palSlot — stray 1px sprites would starve the floor gradient.
local function seed_centroids(pixels, k, locked)
  local cents = {}
  if locked then
    for i = 1, #locked do
      local c = copy_lab(locked[i])
      c.palSlot = locked[i].palSlot or 0
      cents[#cents + 1] = c
    end
  end
  while #cents < k do
    local bestI, bestD = 1, -1
    for i = 1, #pixels do
      local p = pixels[i]
      local dmin = 1e18
      if #cents == 0 then
        dmin = 1
      else
        for j = 1, #cents do
          -- Perceptual only; assignment phase still uses deltaE_eff (+50 palSlot).
          local d = deltaE_w_lab(p, cents[j])
          if d < dmin then dmin = d end
        end
      end
      if dmin > bestD then bestD, bestI = dmin, i end
    end
    local c = copy_lab(pixels[bestI])
    c.palSlot = pixels[bestI].palSlot or 0
    cents[#cents + 1] = c
  end
  return cents
end

local function kmeans(pixels, k, locked)
  local cents = seed_centroids(pixels, k, locked)
  local lockedN = locked and #locked or 0
  -- palSlot on every centroid is immutable from here on.
  for _ = 1, QuantizeLab.KMEANS_ITERS do
    local sums = {}
    for i = 1, k do
      sums[i] = { L = 0, a = 0, b = 0, w = 0 }
    end
    for i = 1, #pixels do
      local p = pixels[i]
      local ci = nearest_centroid(p, cents)
      local w = (p.n or 1) * (1 + chroma(p.a, p.b) / 40)
      sums[ci].L = sums[ci].L + p.L * w
      sums[ci].a = sums[ci].a + p.a * w
      sums[ci].b = sums[ci].b + p.b * w
      sums[ci].w = sums[ci].w + w
    end
    for i = lockedN + 1, k do
      if sums[i].w > 0 then
        -- Update LAB only; keep cents[i].palSlot unchanged.
        cents[i].L = sums[i].L / sums[i].w
        cents[i].a = sums[i].a / sums[i].w
        cents[i].b = sums[i].b / sums[i].w
      end
    end
  end
  return cents
end

local function assign_shades(pixels, cents)
  local shades = {}
  for i = 1, #pixels do
    local ci = nearest_centroid(pixels[i], cents)
    shades[i] = ci - 1 -- 0..3 light→dark
  end
  return shades
end

local function ramp_from_cents(cents)
  local ramp = {}
  for i = 1, 4 do
    ramp[i] = rgb_of_lab(cents[i])
  end
  return ramp
end

--- Unique ≤ 4: map by L* rank into slots 0=lightest … 3=darkest with extreme padding.
-- Two colours → pixel shades 0 and 3 only (internals padded on the ramp, not as pixel ids).
local function bypass_unique(pixels, uniques)
  sort_centroids_light_to_dark(uniques)
  local n = #uniques
  local keyToShade = {}
  if n == 1 then
    keyToShade[uniques[1].key] = 0
  elseif n == 2 then
    keyToShade[uniques[1].key] = 0 -- lightest
    keyToShade[uniques[2].key] = 3 -- darkest (never slot 1)
  elseif n == 3 then
    keyToShade[uniques[1].key] = 0
    keyToShade[uniques[2].key] = 1
    keyToShade[uniques[3].key] = 3
  else
    for i = 1, 4 do
      keyToShade[uniques[i].key] = i - 1
    end
  end
  local shades = {}
  for i = 1, #pixels do
    shades[i] = keyToShade[pixels[i].key] or 0
  end
  local padded = pad_unique_to_ramp(uniques)
  return encode_2bpp(shades), ramp_from_cents(padded), shades
end

--- Demake one 8×8 BGR555 quad → 2bpp + 4-colour RGB ramp (light→dark).
-- Legacy bottom-up helper (kept for synthetics). Extract uses discover + assign + bake.
-- pal64: optional per-pixel FRLG map palette slot (same layout as buf64).
function QuantizeLab.quadTo2bppAndRamp(buf64, pal64)
  local pixels, uniques = gather_pixels(buf64, pal64)
  if #uniques <= 4 then
    return bypass_unique(pixels, uniques)
  end

  local lock = structural_outlier(pixels)
  local locked = lock and { lock } or nil
  local cents = kmeans(pixels, 4, locked)
  sort_centroids_light_to_dark(cents)
  while #cents < 4 do
    local c = copy_lab(cents[#cents] or { L = 50, a = 0, b = 0 })
    c.palSlot = (cents[#cents] and cents[#cents].palSlot) or 0
    cents[#cents + 1] = c
  end
  local shades = assign_shades(pixels, cents)

  -- No medoid polish: k-means centroids are optimal; mutating them caused L*
  -- inversion / clamp-flat midtones and crushed stool/table contrast.
  return encode_2bpp(shades), ramp_from_cents(cents), shades
end

local function ramp_to_lab(ramp)
  local out = {}
  for i = 1, 4 do
    local c = ramp[i]
    local L, a, b = rgb_to_lab(c[1] or 0, c[2] or 0, c[3] or 0)
    out[i] = { L = L, a = a, b = b }
  end
  return out
end

function QuantizeLab.rampDistance(a, b)
  local la, lb = ramp_to_lab(a), ramp_to_lab(b)
  local d = 0
  for i = 1, 4 do
    d = d + deltaE_w_lab(la[i], lb[i])
  end
  return d
end

local function ramp_dist_lab(la, lb)
  local d = 0
  for i = 1, 4 do
    d = d + deltaE_w_lab(la[i], lb[i])
  end
  return d
end

local function majority_pal_slot(pal64)
  local counts = {}
  local best, bestN = 0, -1
  for i = 1, 64 do
    local s = (pal64 and pal64[i]) or 0
    counts[s] = (counts[s] or 0) + 1
    if counts[s] > bestN or (counts[s] == bestN and s < best) then
      best, bestN = s, counts[s]
    end
  end
  return best, bestN
end

--- Build a 4-shade light→dark ramp from a list of LAB samples (optional .n weight).
local function ramp_from_lab_samples(samples)
  if not samples or #samples == 0 then
    return {
      { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 },
    }
  end
  local uniques, byKey, order = {}, {}, {}
  for i = 1, #samples do
    local p = samples[i]
    local key = p.key
    if key == nil then
      key = string.format("%.3f:%.3f:%.3f", p.L, p.a, p.b)
    end
    if not byKey[key] then
      byKey[key] = {
        L = p.L, a = p.a, b = p.b,
        r = p.r, g = p.g, key = key,
        n = 0, palSlot = p.palSlot or 0,
      }
      order[#order + 1] = key
    end
    byKey[key].n = byKey[key].n + (p.n or 1)
  end
  for _, k in ipairs(order) do
    uniques[#uniques + 1] = byKey[k]
  end
  if #uniques <= 4 then
    sort_centroids_light_to_dark(uniques)
    return ramp_from_cents(pad_unique_to_ramp(uniques))
  end
  local cents = kmeans(uniques, 4, nil)
  sort_centroids_light_to_dark(cents)
  while #cents < 4 do
    local c = copy_lab(cents[#cents] or { L = 50, a = 0, b = 0 })
    cents[#cents + 1] = c
  end
  return ramp_from_cents(cents)
end

--- If a FRLG palSlot holds two far-apart hues (plant green + machine teal),
-- emit two sample lists so they become separate codebook materials.
local function split_hue_modes(samples)
  local chromatic = {}
  local totalW = 0
  for i = 1, #samples do
    local p = samples[i]
    local w = p.n or 1
    totalW = totalW + w
    if chroma(p.a, p.b) >= 8 then
      chromatic[#chromatic + 1] = p
    end
  end
  if #chromatic < 4 or totalW < QuantizeLab.MIN_MATERIAL_PIXELS * 2 then
    return { samples }
  end

  -- Farthest-point k=2 on (a,b), then assign.
  local s0 = chromatic[1]
  local s1, bestD = chromatic[1], -1
  for i = 1, #chromatic do
    local p = chromatic[i]
    local d = (p.a - s0.a) ^ 2 + (p.b - s0.b) ^ 2
    if d > bestD then bestD, s1 = d, p end
  end
  local s2, bestD2 = s1, -1
  for i = 1, #chromatic do
    local p = chromatic[i]
    local d = (p.a - s1.a) ^ 2 + (p.b - s1.b) ^ 2
    if d > bestD2 then bestD2, s2 = d, p end
  end
  local c1 = { L = s1.L, a = s1.a, b = s1.b }
  local c2 = { L = s2.L, a = s2.a, b = s2.b }
  -- Refine means once
  for _ = 1, 4 do
    local a1, b1, w1, L1 = 0, 0, 0, 0
    local a2, b2, w2, L2 = 0, 0, 0, 0
    for i = 1, #chromatic do
      local p = chromatic[i]
      local w = p.n or 1
      local d1 = (p.a - c1.a) ^ 2 + (p.b - c1.b) ^ 2
      local d2 = (p.a - c2.a) ^ 2 + (p.b - c2.b) ^ 2
      if d1 <= d2 then
        a1, b1, L1, w1 = a1 + p.a * w, b1 + p.b * w, L1 + p.L * w, w1 + w
      else
        a2, b2, L2, w2 = a2 + p.a * w, b2 + p.b * w, L2 + p.L * w, w2 + w
      end
    end
    if w1 > 0 then c1 = { L = L1 / w1, a = a1 / w1, b = b1 / w1 } end
    if w2 > 0 then c2 = { L = L2 / w2, a = a2 / w2, b = b2 / w2 } end
  end

  local de = deltaE_w_lab(c1, c2)
  if de < QuantizeLab.HUE_SPLIT_DE then
    return { samples }
  end

  local g1, g2, w1, w2 = {}, {}, 0, 0
  for i = 1, #samples do
    local p = samples[i]
    local w = p.n or 1
    local d1 = deltaE_w_lab(p, c1)
    local d2 = deltaE_w_lab(p, c2)
    if d1 <= d2 then
      g1[#g1 + 1] = p
      w1 = w1 + w
    else
      g2[#g2 + 1] = p
      w2 = w2 + w
    end
  end
  local minW = totalW * QuantizeLab.HUE_SPLIT_MIN_FRAC
  if w1 < minW or w2 < minW or #g1 == 0 or #g2 == 0 then
    return { samples }
  end
  return { g1, g2 }
end

local function significant_pal_slots(pal64)
  local counts = {}
  for i = 1, 64 do
    local s = (pal64 and pal64[i]) or 0
    counts[s] = (counts[s] or 0) + 1
  end
  local sig = {}
  for s, n in pairs(counts) do
    if n >= QuantizeLab.MIXED_MIN_PIXELS then
      sig[#sig + 1] = s
    end
  end
  table.sort(sig)
  return sig, counts
end

function QuantizeLab.isMixedQuad(pal64)
  local sig = significant_pal_slots(pal64)
  return #sig >= 2
end

--- Local 4-shade ramp for one quad (used for mixed / high-residual tiles).
function QuantizeLab.rampFromQuad(buf64, pal64)
  local pixels = gather_pixels(buf64, pal64)
  return ramp_from_lab_samples(pixels)
end

function QuantizeLab.terrainFamily(category)
  return QuantizeLab.OUTDOOR_TERRAIN_FAMILY[category or ""]
end

function QuantizeLab.primaryCategory(catVotes)
  if not catVotes then return nil end
  local bestC, bestN = nil, -1
  for c, n in pairs(catVotes) do
    if n > bestN or (n == bestN and (not bestC or c < bestC)) then
      bestC, bestN = c, n
    end
  end
  return bestC
end

function QuantizeLab.entryHasCategory(entry, category)
  if not category or category == "" then return true end
  local votes = entry and entry.categories
  if not votes then return false end
  if (votes[category] or 0) > 0 then return true end
  local fam = QuantizeLab.terrainFamily(category)
  if not fam then return false end
  for c, n in pairs(votes) do
    if n > 0 and QuantizeLab.terrainFamily(c) == fam then return true end
  end
  return false
end

--- Best codebook index whose categories include `category` (terrain family ok).
function QuantizeLab.primaryCodebookForCategory(codebook, category)
  if not codebook or not category then return nil end
  local fam = QuantizeLab.terrainFamily(category) or category
  local bestI, bestN = nil, -1
  for i = 1, #codebook do
    local e = codebook[i]
    local votes = e.categories or {}
    local n = 0
    for c, v in pairs(votes) do
      if c == category or QuantizeLab.terrainFamily(c) == fam then
        n = n + v
      end
    end
    if n > bestN or (n == bestN and (not bestI or i < bestI)) then
      bestN, bestI = n, i
    end
  end
  if bestN and bestN > 0 then return bestI end
  return nil
end

local function copy_cat_votes(src)
  if not src then return nil end
  local out = {}
  for c, n in pairs(src) do out[c] = n end
  return out
end

local function add_cat_votes(dst, src)
  if not src then return dst end
  dst = dst or {}
  for c, n in pairs(src) do
    dst[c] = (dst[c] or 0) + n
  end
  return dst
end

--- Step 1: discover one (or hue-split) material ramp per (pair, FRLG palSlot).
-- quads: { { buf, pal, pair, category? }, ... }
-- opts.forbidHueSplit: never hue-split (outdoor: keep tip/base one foliage ramp)
-- Returns merge-ready entries { ramp, count, locked, frlgSlot, pair, categories }.
function QuantizeLab.discoverMaterialEntries(quads, opts)
  opts = opts or {}
  local forbidHueSplit = opts.forbidHueSplit and true or false
  local buckets = {} -- key → { pair, frlgSlot, byKey, order, pixelN, quadN, catVotes }
  local majCounts = {} -- key → quads with this majority

  for _, q in ipairs(quads or {}) do
    local pair = q.pair or ""
    local maj = majority_pal_slot(q.pal)
    local majKey = pair .. ":" .. tostring(maj)
    majCounts[majKey] = (majCounts[majKey] or 0) + 1
    local qCat = q.category

    local seen = {}
    for i = 1, 64 do
      local c = (q.buf and q.buf[i]) or 0
      local frlg = (q.pal and q.pal[i]) or 0
      local key = pair .. ":" .. tostring(frlg)
      local b = buckets[key]
      if not b then
        b = {
          pair = pair, frlgSlot = frlg, byKey = {}, order = {},
          pixelN = 0, catVotes = {},
        }
        buckets[key] = b
      end
      b.pixelN = b.pixelN + 1
      if not b.byKey[c] then
        local r, g, bb = bgr555_to_rgb(c)
        local L, a, labB = rgb_to_lab(r, g, bb)
        b.byKey[c] = {
          L = L, a = a, b = labB, r = r, g = g, key = c, n = 0, palSlot = frlg,
        }
        b.order[#b.order + 1] = c
      end
      b.byKey[c].n = b.byKey[c].n + 1
      seen[key] = true
    end
    for key in pairs(seen) do
      local b = buckets[key]
      b.quadN = (b.quadN or 0) + 1
      if qCat and qCat ~= "" then
        b.catVotes[qCat] = (b.catVotes[qCat] or 0) + 1
      end
    end
  end

  local keys = {}
  for k in pairs(buckets) do keys[#keys + 1] = k end
  table.sort(keys)

  local entries = {}
  for _, key in ipairs(keys) do
    local b = buckets[key]
    if b.pixelN >= QuantizeLab.MIN_MATERIAL_PIXELS then
      local samples = {}
      for _, ck in ipairs(b.order) do
        samples[#samples + 1] = b.byKey[ck]
      end
      local primary = QuantizeLab.primaryCategory(b.catVotes)
      -- Only collapse tip/base foliage. Water/sand/cliff keep hue modes so
      -- foam/rocks/highlights can remain separate materials.
      local skipSplit = forbidHueSplit
        or (primary == "TREE")
      local modes = skipSplit and { samples } or split_hue_modes(samples)
      local baseWeight = majCounts[key] or b.quadN or 1
      if baseWeight < 1 then baseWeight = 1 end
      local cats = copy_cat_votes(b.catVotes)
      for mi = 1, #modes do
        local modeSamples = modes[mi]
        local modeW = 0
        for i = 1, #modeSamples do
          modeW = modeW + (modeSamples[i].n or 1)
        end
        local weight = math.max(1, math.floor(baseWeight * modeW / math.max(1, b.pixelN) + 0.5))
        entries[#entries + 1] = {
          ramp = ramp_from_lab_samples(modeSamples),
          count = weight,
          locked = false,
          frlgSlot = b.frlgSlot,
          pair = b.pair,
          categories = cats and copy_cat_votes(cats) or nil,
          primaryCategory = primary,
        }
      end
    end
  end
  return entries
end

local function min_shade_de(p, rampLab)
  local best = 1e18
  for s = 1, 4 do
    local d = deltaE_w_lab(p, rampLab[s])
    if d < best then best = d end
  end
  return best
end

local function quad_ramp_error(pixels, rampLab)
  local sum = 0
  for i = 1, #pixels do
    local p = pixels[i]
    -- Structural outlines + vibrant colours outvote flat floors/walls.
    local w = 1.0
    if p.L < 45 then w = w + 2.0 end
    if chroma(p.a, p.b) > 10 then w = w + 1.5 end
    sum = sum + min_shade_de(p, rampLab) * w
  end
  return sum
end

QuantizeLab.OUTDOOR_FRLG_BIAS = 50.0   -- soft prefer matching FRLG palSlot outdoors
QuantizeLab.OUTDOOR_RAMP_BIAS = 40.0   -- soft prefer semantic seed ramp on mixed edges
-- Soft push plaza grass/path away from water/sand codebook entries.
QuantizeLab.OUTDOOR_CROSS_CAT_PENALTY = 120.0
QuantizeLab.OUTDOOR_GRASS_CATS = {
  SHORT_GRASS = true,
  TALL_GRASS = true,
  TOWN_PATH = true,
}

--- ΔE_w between two BGR555 pixels (MRF seam gating).
function QuantizeLab.pixelDeltaE(cA, cB)
  local r1, g1, b1 = bgr555_to_rgb(cA)
  local r2, g2, b2 = bgr555_to_rgb(cB)
  local L1, a1, bb1 = rgb_to_lab(r1, g1, b1)
  local L2, a2, bb2 = rgb_to_lab(r2, g2, b2)
  return QuantizeLab.deltaE_w(L1, a1, bb1, L2, a2, bb2)
end

--- Step 2: pick codebook index by weighted Σ min_s ΔE_w (pair-scoped).
-- Indoor: unary ΔE only (opts nil). Outdoor may pass preferFrlgSlot / preferRamp.
-- codebook[i] = { ramp, lab?, frlgSlot?, pair?, slot? }
function QuantizeLab.majorityPalSlot(pal64)
  return majority_pal_slot(pal64)
end

function QuantizeLab.quadRampError(buf64, pal64, ramp, _frlgSlot)
  local pixels = gather_pixels(buf64, pal64)
  return quad_ramp_error(pixels, ramp_to_lab(ramp))
end

function QuantizeLab.bestCodebookIndex(buf64, pal64, codebook, pair, opts)
  if not codebook or #codebook == 0 then return 1 end
  local pixels = gather_pixels(buf64, pal64)
  pair = pair or ""
  opts = opts or nil
  local preferFrlg = opts and opts.preferFrlgSlot
  local frlgBias = (opts and opts.frlgBias) or 0
  local preferRamp = opts and opts.preferRamp
  local rampBias = (opts and opts.rampBias) or 0
  local requireCat = opts and opts.requireCategory
  local categoryBias = (opts and opts.categoryBias) or 0
  local itemCat = opts and opts.itemCategory
  local crossPen = (opts and opts.crossCatPenalty) or 0

  local function cross_penalty(e)
    if crossPen <= 0 or not itemCat then return 0 end
    if QuantizeLab.OUTDOOR_GRASS_CATS[itemCat] then
      if QuantizeLab.entryHasCategory(e, "WATER")
        or QuantizeLab.entryHasCategory(e, "SAND") then
        return crossPen
      end
      local primary = e.primaryCategory
      if primary == "WATER" or primary == "SAND" then
        return crossPen
      end
    end
    return 0
  end

  local function score_range(onlyMatching)
    local bestI, bestD = nil, 1e18
    for i = 1, #codebook do
      local e = codebook[i]
      if (e.pair or "") == pair then
        if (not onlyMatching) or QuantizeLab.entryHasCategory(e, requireCat) then
          local lab = e.lab or ramp_to_lab(e.ramp)
          local d = quad_ramp_error(pixels, lab) + cross_penalty(e)
          if preferFrlg ~= nil and frlgBias ~= 0 and (e.frlgSlot or 0) == preferFrlg then
            d = d - frlgBias
          end
          if preferRamp and rampBias > 0 and e.ramp then
            local rd = QuantizeLab.rampDistance(e.ramp, preferRamp)
            d = d - rampBias / (1 + rd / 12)
          end
          if requireCat and categoryBias > 0 and QuantizeLab.entryHasCategory(e, requireCat) then
            d = d - categoryBias
          end
          if d < bestD then bestD, bestI = d, i end
        end
      end
    end
    return bestI
  end

  local bestI = nil
  if requireCat then
    bestI = score_range(true)
  end
  if not bestI then
    bestI = score_range(false)
  end

  -- Safe fallback if a pair string is missing/mismatched
  if not bestI then
    local bestD = 1e18
    for i = 1, #codebook do
      local e = codebook[i]
      local lab = e.lab or ramp_to_lab(e.ramp)
      local d = quad_ramp_error(pixels, lab) + cross_penalty(e)
      if d < bestD then bestD, bestI = d, i end
    end
  end

  return bestI or 1
end

--- Opaque void 2bpp: all shade 3 (atlas black). Used only when stamping FRLG
-- mid 0 / border after content quantize — not as a material-ramp lock.
function QuantizeLab.solidBlackBpp()
  local shades = {}
  for i = 1, 64 do shades[i] = 3 end
  return encode_2bpp(shades)
end

--- Strict codebook adoption (no mixed/local bypass — prevents grid banding).
-- Void is not handled here: FRLG mid 0 is stamped post-quantize from tile data.
-- Returns ramp, sheetSlotOrNil, mode ("codebook"|"local"), codebookIndexOrNil.
function QuantizeLab.resolveQuadRamp(buf64, pal64, codebook, pair, opts)
  if not codebook or #codebook == 0 then
    local pixels = gather_pixels(buf64, pal64)
    return ramp_from_lab_samples(pixels), nil, "local", nil
  end

  local ci = QuantizeLab.bestCodebookIndex(buf64, pal64, codebook, pair, opts)
  local entry = codebook[ci]
  return entry.ramp, entry.slot, "codebook", ci
end

--- Step 3: bake 2bpp by nearest ΔE_w shade in a fixed 4-colour ramp (light→dark).
function QuantizeLab.quadTo2bppAgainstRamp(buf64, ramp)
  local rampLab = ramp_to_lab(ramp)
  local shades = {}
  for i = 1, 64 do
    local r, g, b = bgr555_to_rgb(buf64[i] or 0)
    local L, a, bb = rgb_to_lab(r, g, b)
    local p = { L = L, a = a, b = bb }
    local best, bestD = 0, 1e18
    for s = 1, 4 do
      local d = deltaE_w_lab(p, rampLab[s])
      if d < bestD then best, bestD = s - 1, d end
    end
    shades[i] = best
  end
  return encode_2bpp(shades), shades
end

--- True when any pixel is exact BGR555 0 (void mixed into a content quad).
function QuantizeLab.bufHasExactBlack(buf64)
  for i = 1, 64 do
    if ((buf64[i] or 0) % 0x8000) == 0 then return true end
  end
  return false
end

--- Bake a quad; if it contains exact-black pixels, reserve shade 3 as true
-- black for *this tile only* (door-mat chamfers). Non-black pixels use shades
-- 0–2 of the material ramp. Tiles without black keep the full 4-shade ramp.
-- Returns bpp16, usedRamp, lockedBlack.
function QuantizeLab.bakeQuad(buf64, ramp)
  if not QuantizeLab.bufHasExactBlack(buf64) then
    local bpp = QuantizeLab.quadTo2bppAgainstRamp(buf64, ramp)
    return bpp, ramp, false
  end
  local used = {
    { ramp[1][1], ramp[1][2], ramp[1][3] },
    { ramp[2][1], ramp[2][2], ramp[2][3] },
    { ramp[3][1], ramp[3][2], ramp[3][3] },
    { 0, 0, 0 },
  }
  local rampLab = ramp_to_lab(used)
  local shades = {}
  for i = 1, 64 do
    local c = (buf64[i] or 0) % 0x8000
    if c == 0 then
      shades[i] = 3
    else
      local r, g, b = bgr555_to_rgb(c)
      local L, a, bb = rgb_to_lab(r, g, b)
      local p = { L = L, a = a, b = bb }
      local best, bestD = 0, 1e18
      for s = 1, 3 do -- shades 0–2 only; 3 is reserved black
        local d = deltaE_w_lab(p, rampLab[s])
        if d < bestD then best, bestD = s - 1, d end
      end
      shades[i] = best
    end
  end
  return encode_2bpp(shades), used, true
end

local function clamp_weights(na, nb, cap)
  cap = cap or QuantizeLab.WEIGHT_RATIO_CAP
  if na < 1 then na = 1 end
  if nb < 1 then nb = 1 end
  if na > nb * cap then na = nb * cap end
  if nb > na * cap then nb = na * cap end
  return na, nb
end

local function blend_ramps(a, b, na, nb)
  na, nb = clamp_weights(na, nb)
  local out = {}
  local den = na + nb
  local la, lb = ramp_to_lab(a), ramp_to_lab(b)
  for i = 1, 4 do
    local L = (la[i].L * na + lb[i].L * nb) / den
    local aa = (la[i].a * na + lb[i].a * nb) / den
    local bb = (la[i].b * na + lb[i].b * nb) / den
    local r, g, brgb = lab_to_rgb(L, aa, bb)
    out[i] = { r, g, brgb }
  end
  return out
end

--- Reject merge if the hypothetical blend pushes the rarer ramp too far from
-- its origin (not by comparing the two source ramps to each other).
local function rare_shift_ok_lab(rareLab, blendedLab)
  for i = 1, 4 do
    local r, b = rareLab[i], blendedLab[i]
    local dL = math.abs(r.L - b.L)
    local dab = math.sqrt((r.a - b.a) ^ 2 + (r.b - b.b) ^ 2)
    if dL > QuantizeLab.DL_SHIFT_MAX or dab > QuantizeLab.DAB_SHIFT_MAX then
      return false
    end
  end
  return true
end

--- Agglomerative merge of provisional ramps into ≤ maxSlots (LAB-cached, O(n²) per step).
-- entries: { { ramp, count, locked?, categories? }, ... }
-- opts.nearDupeEps: override NEAR_DUPE_EPS (outdoor uses a tighter value)
-- opts.guardTerrainFamilies: refuse merging distinct outdoor terrain families
-- Returns finalRamps (1-based list) and map oldIndex → finalSlot.
function QuantizeLab.mergeRampsToBudget(entries, maxSlots, opts)
  maxSlots = maxSlots or QuantizeLab.MAX_SLOTS
  opts = opts or {}
  local nearEps = opts.nearDupeEps or QuantizeLab.NEAR_DUPE_EPS
  local guardFam = opts.guardTerrainFamilies and true or false
  if not entries or #entries == 0 then
    return { { { 255, 255, 255 }, { 170, 170, 170 }, { 85, 85, 85 }, { 0, 0, 0 } } }, {}
  end

  local function cluster_family(c)
    local primary = QuantizeLab.primaryCategory(c.catVotes)
    return primary and QuantizeLab.terrainFamily(primary) or nil
  end

  local function families_conflict(ca, cb)
    if not guardFam then return false end
    local fa, fb = cluster_family(ca), cluster_family(cb)
    return fa ~= nil and fb ~= nil and fa ~= fb
  end

  local clusters = {}
  local active = {} -- dense list of cluster ids
  for i = 1, #entries do
    local e = entries[i]
    local ramp = {
      { e.ramp[1][1], e.ramp[1][2], e.ramp[1][3] },
      { e.ramp[2][1], e.ramp[2][2], e.ramp[2][3] },
      { e.ramp[3][1], e.ramp[3][2], e.ramp[3][3] },
      { e.ramp[4][1], e.ramp[4][2], e.ramp[4][3] },
    }
    clusters[i] = {
      ramp = ramp,
      lab = ramp_to_lab(ramp),
      count = e.count or 1,
      locked = e.locked and true or false,
      members = { i },
      alive = true,
      catVotes = copy_cat_votes(e.categories),
    }
    active[#active + 1] = i
  end

  local function try_merge(ia, ib, force)
    local ca, cb = clusters[ia], clusters[ib]
    if not (ca and cb and ca.alive and cb.alive) then return false end
    if ca.locked and cb.locked then return false end
    if families_conflict(ca, cb) then return false end

    -- Keep = locked or higher-count (dominant); drop = rare.
    local keep, drop = ia, ib
    if cb.locked and not ca.locked then
      keep, drop = ib, ia
    elseif not ca.locked and not cb.locked and cb.count > ca.count then
      keep, drop = ib, ia
    end

    local ck, cd = clusters[keep], clusters[drop]
    local blended, blendedLab

    if force then
      -- Panic merge: absorb rare into dominant without corrupting dominant colours.
      blended = ck.ramp
      blendedLab = ck.lab
    else
      blended = blend_ramps(ck.ramp, cd.ramp, ck.count, cd.count)
      blendedLab = ramp_to_lab(blended)
      if not rare_shift_ok_lab(cd.lab, blendedLab) then
        return false
      end
    end

    ck.ramp = blended
    ck.lab = blendedLab
    ck.count = ck.count + cd.count
    ck.locked = ck.locked or cd.locked
    ck.catVotes = add_cat_votes(ck.catVotes, cd.catVotes)
    for _, m in ipairs(cd.members) do
      ck.members[#ck.members + 1] = m
    end
    cd.alive = false
    return true, keep, drop
  end

  -- Near-dupe: single O(n²) sweep (union into lower id)
  do
    local n = #active
    for i = 1, n do
      local a = active[i]
      local ca = clusters[a]
      if ca and ca.alive then
        for j = i + 1, n do
          local b = active[j]
          local cb = clusters[b]
          if cb and cb.alive and not (ca.locked and cb.locked)
            and not families_conflict(ca, cb) then
            if ramp_dist_lab(ca.lab, cb.lab) < nearEps then
              local ok = try_merge(a, b, false)
              if ok then
                ca = clusters[a]
                if not ca.alive then break end
              end
            end
          end
        end
      end
    end
    local nxt = {}
    for _, id in ipairs(active) do
      if clusters[id].alive then nxt[#nxt + 1] = id end
    end
    active = nxt
  end

  -- Hard cap: closest-pair (same design). Rank pairs by LAB distance, then try
  -- shift-ok merges from closest; force only the nearest if all reject.
  while #active > maxSlots do
    local pairs = {}
    for i = 1, #active do
      local a = active[i]
      local ca = clusters[a]
      for j = i + 1, #active do
        local b = active[j]
        local cb = clusters[b]
        if not (ca.locked and cb.locked) and not families_conflict(ca, cb) then
          pairs[#pairs + 1] = { a = a, b = b, d = ramp_dist_lab(ca.lab, cb.lab) }
        end
      end
    end
    if #pairs == 0 then break end
    table.sort(pairs, function(u, v)
      if u.d ~= v.d then return u.d < v.d end
      if u.a ~= v.a then return u.a < v.a end
      return u.b < v.b
    end)
    local mergedOk, drop = false, nil
    for _, p in ipairs(pairs) do
      local ok, _, d = try_merge(p.a, p.b, false)
      if ok then
        mergedOk, drop = true, d
        break
      end
    end
    if not mergedOk then
      local ok, _, d = try_merge(pairs[1].a, pairs[1].b, true)
      if not ok then break end
      drop = d
    end
    local nxt = {}
    for _, id in ipairs(active) do
      if id ~= drop and clusters[id].alive then nxt[#nxt + 1] = id end
    end
    active = nxt
  end

  table.sort(active, function(a, b)
    local ca, cb = clusters[a], clusters[b]
    if ca.locked ~= cb.locked then return ca.locked end
    if ca.count ~= cb.count then return ca.count > cb.count end
    return a < b
  end)

  local finalRamps = {}
  local oldToSlot = {}
  for slot, id in ipairs(active) do
    if slot > maxSlots then break end
    finalRamps[slot] = clusters[id].ramp
    for _, m in ipairs(clusters[id].members) do
      oldToSlot[m] = slot
    end
  end
  for i = 1, #entries do
    if not oldToSlot[i] then
      local best, bestD = 1, 1e18
      local lab = ramp_to_lab(entries[i].ramp)
      for s = 1, #finalRamps do
        local d = ramp_dist_lab(lab, ramp_to_lab(finalRamps[s]))
        if d < bestD then best, bestD = s, d end
      end
      oldToSlot[i] = best
    end
  end
  return finalRamps, oldToSlot
end

-- Expose helpers for tests
QuantizeLab._rgb_to_lab = rgb_to_lab
QuantizeLab._pad_unique_to_ramp = pad_unique_to_ramp
QuantizeLab._red_ref_cos = red_ref_cos
QuantizeLab._sort_centroids = sort_centroids_light_to_dark

return QuantizeLab
