-- BGR555 → BT.709 luminance → 4-shade 2bpp (engine ImageWriter.SHADES ramp)
-- plus per-tile RGB ramps clustered into BG palette slots.
-- Outdoor stays ≤8; Sevii interiors may use up to Quantize.MAX_PALETTE_SLOTS.

local Quantize = {}

-- Matches src/import/ImageWriter.lua SHADES (white → black).
Quantize.SHADES_Y = { 1.0, 2 / 3, 1 / 3, 0.0 }
Quantize.MAX_PALETTE_SLOTS = 22

-- Squared RGB distance threshold for merging demake ramps into one GBC slot.
-- Low enough that pink PC floors and green outdoor grass stay separate while
-- near-duplicate tiles still share a slot (Gen2 only has 8 BG palettes).
Quantize.RAMP_MERGE_DIST = 18000

local function bgr555_to_rgb(c)
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return r5 * 255 / 31, g5 * 255 / 31, b5 * 255 / 31
end

local function bgr555_to_y(c)
  local r, g, b = bgr555_to_rgb(c)
  return 0.2126 * (r / 255) + 0.7152 * (g / 255) + 0.0722 * (b / 255)
end

--- Per-tile thresholds from Y histogram (quartile-ish breakpoints).
local function thresholds_from_tile(ys)
  local sorted = {}
  for i = 1, #ys do sorted[i] = ys[i] end
  table.sort(sorted)
  local function at(p)
    local i = math.max(1, math.min(#sorted, math.floor(p * #sorted)))
    return sorted[i]
  end
  local t1 = at(0.25)
  local t2 = at(0.50)
  local t3 = at(0.75)
  if t2 <= t1 then t2 = t1 + 1e-4 end
  if t3 <= t2 then t3 = t2 + 1e-4 end
  return t1, t2, t3
end

local function shade_for_y(y, t1, t2, t3)
  if y >= t3 then return 0 end
  if y >= t2 then return 1 end
  if y >= t1 then return 2 end
  return 3
end

local function copy_ramp(ramp)
  local out = {}
  for i = 1, 4 do
    local c = ramp[i]
    out[i] = { c[1], c[2], c[3] }
  end
  return out
end

local function ramp_dist2(a, b)
  local d = 0
  for i = 1, 4 do
    for ch = 1, 3 do
      local x = (a[i][ch] or 0) - (b[i][ch] or 0)
      d = d + x * x
    end
  end
  return d
end

local function blend_ramp(dst, src, n)
  -- Running average: dst already holds mean of n samples; fold in src.
  local n1 = n + 1
  for i = 1, 4 do
    for ch = 1, 3 do
      dst[i][ch] = math.floor((dst[i][ch] * n + src[i][ch]) / n1 + 0.5)
    end
  end
end

local function gray_ramp()
  local out = {}
  for i = 1, 4 do
    local v = math.floor(Quantize.SHADES_Y[i] * 255 + 0.5)
    out[i] = { v, v, v }
  end
  return out
end

--- Quantize 8×8 BGR555 (64 entries) → 16 bytes of GB 2bpp (1-based array).
-- Optional shared thresholds (t1,t2,t3) keep shade cuts identical across every
-- tile on the same Gen2 slot so sand/cliff edges stay continuous (no checkers).
function Quantize.tileTo2bpp(buf64, t1, t2, t3)
  local ys = {}
  for i = 1, 64 do
    ys[i] = bgr555_to_y(buf64[i] or 0)
  end
  if not (t1 and t2 and t3) then
    t1, t2, t3 = thresholds_from_tile(ys)
    local ymin, ymax = ys[1], ys[1]
    for i = 2, 64 do
      if ys[i] < ymin then ymin = ys[i] end
      if ys[i] > ymax then ymax = ys[i] end
    end
    if ymax - ymin < 0.05 then
      t1, t2, t3 = 0.25, 0.5, 0.75
    end
  end

  local shades = {}
  local out = {}
  for y = 0, 7 do
    local low, high = 0, 0
    for x = 0, 7 do
      local shade = shade_for_y(ys[y * 8 + x + 1], t1, t2, t3)
      shades[y * 8 + x + 1] = shade
      local bit = 7 - x
      local mask = 2 ^ bit
      if shade % 2 == 1 then low = low + mask end
      if math.floor(shade / 2) % 2 == 1 then high = high + mask end
    end
    out[y * 2 + 1] = low
    out[y * 2 + 2] = high
  end
  return out, ys, shades
end

--- Quartile thresholds from a pooled luminance list (one set per Gen2 slot).
function Quantize.thresholdsFromYs(ys)
  if not ys or #ys == 0 then return 0.25, 0.5, 0.75 end
  local sorted = {}
  for i = 1, #ys do sorted[i] = ys[i] end
  table.sort(sorted)
  local function at(p)
    local i = math.max(1, math.min(#sorted, math.floor(p * #sorted)))
    return sorted[i]
  end
  local t1, t2, t3 = at(0.25), at(0.50), at(0.75)
  if t2 <= t1 then t2 = t1 + 1e-4 end
  if t3 <= t2 then t3 = t2 + 1e-4 end
  return t1, t2, t3
end

--- Mean RGB of an 8×8 BGR555 tile (for soft slot hints).
function Quantize.meanRgb(buf64)
  local r, g, b, n = 0, 0, 0, 0
  for i = 1, 64 do
    local rr, gg, bb = bgr555_to_rgb(buf64[i] or 0)
    r, g, b, n = r + rr, g + gg, b + bb, n + 1
  end
  if n == 0 then return 0, 0, 0 end
  return r / n, g / n, b / n
end

--- Average BGR555 colours per quantized shade → 4 RGB entries for GbcPalette.
function Quantize.rampFromTile(buf64, shades)
  local sums = {}
  for s = 0, 3 do sums[s + 1] = { 0, 0, 0, 0 } end
  for i = 1, 64 do
    local shade = (shades and shades[i]) or 0
    local r, g, b = bgr555_to_rgb(buf64[i] or 0)
    local bucket = sums[shade + 1]
    bucket[1] = bucket[1] + r
    bucket[2] = bucket[2] + g
    bucket[3] = bucket[3] + b
    bucket[4] = bucket[4] + 1
  end
  local ramp = gray_ramp()
  for s = 1, 4 do
    local n = sums[s][4]
    if n > 0 then
      ramp[s] = {
        math.floor(sums[s][1] / n + 0.5),
        math.floor(sums[s][2] / n + 0.5),
        math.floor(sums[s][3] / n + 0.5),
      }
    end
  end
  return ramp
end

--- Quantize + demake ramp in one pass.
function Quantize.tileTo2bppAndRamp(buf64)
  local bpp, ys, shades = Quantize.tileTo2bpp(buf64)
  return bpp, Quantize.rampFromTile(buf64, shades), ys, shades
end

local function dist2_rgb(r, g, b, c)
  local dr, dg, db = r - c[1], g - c[2], b - c[3]
  return dr * dr + dg * dg + db * db
end

--- Snap each BGR555 pixel to the nearest colour in a fixed 4-shade ramp, then
-- pack as 2bpp indices. Adjacent tiles that share the same ramp get matching
-- edges; mixed grass|sand tiles pick one owning ramp (from context) so they
-- do not invent a third hue.
function Quantize.tileTo2bppAgainstRamp(buf64, ramp)
  ramp = ramp or gray_ramp()
  local shades = {}
  local out = {}
  for y = 0, 7 do
    local low, high = 0, 0
    for x = 0, 7 do
      local r, g, b = bgr555_to_rgb(buf64[y * 8 + x + 1] or 0)
      local best, bestD = 0, math.huge
      for s = 0, 3 do
        local d = dist2_rgb(r, g, b, ramp[s + 1])
        if d < bestD then best, bestD = s, d end
      end
      shades[y * 8 + x + 1] = best
      local bit = 7 - x
      local mask = 2 ^ bit
      if best % 2 == 1 then low = low + mask end
      if math.floor(best / 2) % 2 == 1 then high = high + mask end
    end
    out[y * 2 + 1] = low
    out[y * 2 + 2] = high
  end
  return out, shades
end

--- Hue spread in an 8×8 — high means grass|sand-style mixed tile.
function Quantize.tileHueSpread(buf64)
  local minR, minG, minB = 255, 255, 255
  local maxR, maxG, maxB = 0, 0, 0
  for i = 1, 64 do
    local r, g, b = bgr555_to_rgb(buf64[i] or 0)
    if r < minR then minR = r end
    if g < minG then minG = g end
    if b < minB then minB = b end
    if r > maxR then maxR = r end
    if g > maxG then maxG = g end
    if b > maxB then maxB = b end
  end
  return (maxR - minR) + (maxG - minG) + (maxB - minB)
end

Quantize.MIXED_HUE_SPREAD = 120 -- above this → treat as transition; use map context

--- Hash 16-byte 2bpp tile for dedupe.
function Quantize.tileKey(bpp16)
  local parts = {}
  for i = 1, 16 do
    parts[i] = string.char(bpp16[i] or 0)
  end
  return table.concat(parts)
end

--- Grow a sheet of unique 2bpp tiles; returns tileId (0-based) and sheet state.
-- Palette slot is NOT part of tile identity (per-tileset banks attach colour via
-- tilePalettesByTileset); sheet.tilePalettes is a legacy scratch field only.
function Quantize.Sheet()
  return {
    keys = {},
    tiles = {}, -- list of 16-byte arrays
    tilePalettes = {}, -- legacy; prefer tilePalettesByTileset in extract
    palettes = {}, -- demake ramps { {r,g,b} x4 }
    paletteCounts = {},
    count = 0,
  }
end

--- FRLG map pal 0..12 → Gen2 BG slot 1..7 (legacy helper / tests).
function Quantize.frlgPalToGen2(palSlot)
  palSlot = math.floor(tonumber(palSlot) or 0) % 16
  return (palSlot % 7) + 1
end

--- Force-accumulate a demake ramp into a specific BG slot.
function Quantize.accumulatePalette(sheet, slot, ramp)
  if slot < 1 then slot = 1 end
  if slot > Quantize.MAX_PALETTE_SLOTS then slot = Quantize.MAX_PALETTE_SLOTS end
  if not sheet.palettes[slot] then
    sheet.palettes[slot] = copy_ramp(ramp)
    sheet.paletteCounts[slot] = 1
    return slot
  end
  blend_ramp(sheet.palettes[slot], ramp, sheet.paletteCounts[slot])
  sheet.paletteCounts[slot] = sheet.paletteCounts[slot] + 1
  return slot
end

--- Demake one FRLG 16-colour BGR555 palette → 4 RGB shades (light→dark by Y).
-- Colour 0 is transparent in FRLG and is skipped.
function Quantize.rampFromFrlgPal(pal16)
  local entries = {}
  for i = 1, 15 do
    local c = pal16 and pal16[i] or 0
    local r, g, b = bgr555_to_rgb(c)
    local y = 0.2126 * (r / 255) + 0.7152 * (g / 255) + 0.0722 * (b / 255)
    entries[#entries + 1] = { y = y, r = r, g = g, b = b }
  end
  if #entries == 0 then return gray_ramp() end
  table.sort(entries, function(a, b) return a.y > b.y end)
  local ramp = {}
  for s = 0, 3 do
    local idx = 1 + math.floor(s * (#entries - 1) / 3 + 0.5)
    local e = entries[idx]
    ramp[s + 1] = {
      math.floor(e.r + 0.5),
      math.floor(e.g + 0.5),
      math.floor(e.b + 0.5),
    }
  end
  return ramp
end

-- Semantic families: groups in different families avoid sharing a Gen2 slot
-- until we are forced to by the 8-slot budget.
Quantize.CAT_FAMILY = {
  WATER = "blue",
  TREE = "green",
  SHORT_GRASS = "green",
  TALL_GRASS = "green",
  SAND = "yellow",
  CLIFF = "brown",
  COAST_CLIFF = "brown",
  ROCK_DECK = "brown",
  LEDGE = "brown",
  BUILDING = "struct",
  DOOR = "struct",
  SIGN = "struct",
  PATH = "path",
  TOWN_PATH = "path",
  PIER = "path",
  STAIR = "path",
  CAVE = "brown",
  BLOCKED = "path",
}

local FAMILY_CROSS_PENALTY = 80000 -- squared RGB; prefer same-family merges
-- Same family but very different hues (red roof vs blue wall) may take another slot.
local FAMILY_SPLIT_DIST = 45000

local function family_of(category)
  return Quantize.CAT_FAMILY[category or ""] or "path"
end

local function majority_key(votes)
  local best, bestN = nil, 0
  for k, n in pairs(votes) do
    if n > bestN then best, bestN = k, n end
  end
  return best
end

--- Build ≤8 Gen2 slots from FRLG-palette groups (joint / context-aware).
-- groups: list of {
--   key, ramp, count, family (or categoryVotes),
-- }
-- Returns map key→slot (1..8) and writes sheet.palettes.
function Quantize.mapGroupsToSlots(sheet, groups)
  sheet.palettes = {}
  sheet.paletteCounts = {}
  local keyToSlot = {}
  if #groups == 0 then
    sheet.palettes[1] = gray_ramp()
    sheet.paletteCounts[1] = 1
    return keyToSlot
  end

  local G = {}
  for i = 1, #groups do
    local g = groups[i]
    local fam = g.family
    if not fam and g.categoryVotes then
      fam = family_of(majority_key(g.categoryVotes))
    end
    G[i] = {
      key = g.key,
      ramp = copy_ramp(g.ramp),
      count = g.count or 1,
      family = fam or "path",
    }
  end
  table.sort(G, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.key < b.key
  end)

  -- One seed per family from the most-used group in that family.
  local seeds = {}
  local used = {}
  local familiesSeen = {}
  for i = 1, #G do
    local fam = G[i].family
    if not familiesSeen[fam] and #seeds < 8 then
      familiesSeen[fam] = true
      used[i] = true
      seeds[#seeds + 1] = {
        ramp = copy_ramp(G[i].ramp),
        family = fam,
        members = { i },
        count = G[i].count,
      }
    end
  end

  -- Leftovers: merge into nearest same-family seed, or split if hue is far
  -- and we still have free Gen2 slots (roof red vs wall blue).
  for i = 1, #G do
    if not used[i] then
      local bestS, bestD = 1, math.huge
      local bestSameS, bestSameD = nil, math.huge
      for s = 1, #seeds do
        local d = ramp_dist2(seeds[s].ramp, G[i].ramp)
        local dPen = d
        if seeds[s].family ~= G[i].family then
          dPen = d + FAMILY_CROSS_PENALTY
        else
          if d < bestSameD then bestSameS, bestSameD = s, d end
        end
        if dPen < bestD then bestS, bestD = s, dPen end
      end
      if bestSameS and bestSameD > FAMILY_SPLIT_DIST and #seeds < 8 then
        used[i] = true
        seeds[#seeds + 1] = {
          ramp = copy_ramp(G[i].ramp),
          family = G[i].family,
          members = { i },
          count = G[i].count,
        }
      else
        local seed = seeds[bestSameS or bestS]
        seed.members[#seed.members + 1] = i
        blend_ramp(seed.ramp, G[i].ramp, seed.count)
        seed.count = seed.count + G[i].count
        used[i] = true
      end
    end
  end

  for s = 1, #seeds do
    sheet.palettes[s] = seeds[s].ramp
    sheet.paletteCounts[s] = seeds[s].count
    for _, gi in ipairs(seeds[s].members) do
      keyToSlot[G[gi].key] = s
    end
  end
  return keyToSlot
end

--- Snap a mid's four quadrant slots toward majority when they disagree weakly.
-- slots/ramps are length-4 arrays. Returns possibly-updated slots.
function Quantize.cohereMetatileSlots(slots, ramps)
  local counts = {}
  for i = 1, 4 do
    local s = slots[i] or 1
    counts[s] = (counts[s] or 0) + 1
  end
  local maj, majN = slots[1] or 1, 0
  for s, n in pairs(counts) do
    if n > majN then maj, majN = s, n end
  end
  if majN < 3 then return slots end -- only snap clear 3–1 majorities
  local majRamp = nil
  for i = 1, 4 do
    if slots[i] == maj then majRamp = ramps[i] break end
  end
  if not majRamp then return slots end
  local out = { slots[1], slots[2], slots[3], slots[4] }
  for i = 1, 4 do
    if out[i] ~= maj then
      local d = ramp_dist2(ramps[i], majRamp)
      -- Allow snap when the odd tile is not a wildly different material.
      if d <= Quantize.RAMP_MERGE_DIST * 3 then
        out[i] = maj
      end
    end
  end
  return out
end

--- Outdoor LAB: snap a mid's four codebook indices on a clear 3–1 majority.
-- nil entries (void quads) are left alone and do not vote.
function Quantize.cohereCodebookIndices(indices)
  local counts = {}
  for i = 1, 4 do
    local s = indices[i]
    if s ~= nil then
      counts[s] = (counts[s] or 0) + 1
    end
  end
  local maj, majN = nil, 0
  for s, n in pairs(counts) do
    if n > majN or (n == majN and (maj == nil or s < maj)) then
      maj, majN = s, n
    end
  end
  if not maj or majN < 3 then return indices end
  local out = { indices[1], indices[2], indices[3], indices[4] }
  for i = 1, 4 do
    if out[i] ~= nil and out[i] ~= maj then
      out[i] = maj
    end
  end
  return out
end

function Quantize.categoryFamily(category)
  return Quantize.CAT_FAMILY[category or ""] or "path"
end

local function ramp_chroma(ramp)
  local m = 0
  for i = 1, 4 do
    local c = ramp[i]
    local spread = math.max(c[1], c[2], c[3]) - math.min(c[1], c[2], c[3])
    if spread > m then m = spread end
  end
  return m
end

--- Nearest existing Gen2 slot for a ramp (no create / no blend). Returns 1..8.
function Quantize.nearestPaletteSlot(sheet, ramp)
  local best, bestD = 1, math.huge
  for i = 1, #sheet.palettes do
    local d = ramp_dist2(sheet.palettes[i], ramp)
    if d < bestD then best, bestD = i, d end
  end
  return best
end

--- Seed ≤8 GBC slots via farthest-point sampling, biased toward high-chroma ramps.
-- Kept for tests / fallbacks; prefer mapGroupsToSlots for extract.
function Quantize.seedPalettes(sheet, ramps)
  if #ramps == 0 then
    sheet.palettes[1] = gray_ramp()
    sheet.paletteCounts[1] = 1
    return
  end
  local scored = {}
  for i = 1, #ramps do
    scored[i] = { ramp = ramps[i], chroma = ramp_chroma(ramps[i]), i = i }
  end
  table.sort(scored, function(a, b)
    if a.chroma ~= b.chroma then return a.chroma > b.chroma end
    return a.i < b.i
  end)
  local candN = math.max(8, math.min(#scored, math.floor(#scored / 2)))
  local seeds = { scored[1].ramp }
  while #seeds < 8 and #seeds < candN do
    local bestIdx, bestMin = nil, -1
    for ci = 1, candN do
      local ramp = scored[ci].ramp
      local minD = math.huge
      for s = 1, #seeds do
        local d = ramp_dist2(seeds[s], ramp)
        if d < minD then minD = d end
      end
      if minD > bestMin then
        bestMin = minD
        bestIdx = ci
      end
    end
    if not bestIdx or bestMin <= Quantize.RAMP_MERGE_DIST then break end
    seeds[#seeds + 1] = scored[bestIdx].ramp
  end
  for i = 1, #seeds do
    sheet.palettes[i] = copy_ramp(seeds[i])
    sheet.paletteCounts[i] = 1
  end
end

--- Assign (or merge) a demake ramp into one of 8 Gen2 BG slots. Returns 1..8.
function Quantize.assignPaletteSlot(sheet, ramp)
  local best, bestD = nil, math.huge
  for i = 1, #sheet.palettes do
    local d = ramp_dist2(sheet.palettes[i], ramp)
    if d < bestD then best, bestD = i, d end
  end
  if best and bestD <= Quantize.RAMP_MERGE_DIST then
    -- Near-duplicate of an existing slot: refine centroid.
    blend_ramp(sheet.palettes[best], ramp, sheet.paletteCounts[best])
    sheet.paletteCounts[best] = sheet.paletteCounts[best] + 1
    return best
  end
  if #sheet.palettes < 8 then
    local i = #sheet.palettes + 1
    sheet.palettes[i] = copy_ramp(ramp)
    sheet.paletteCounts[i] = 1
    return i
  end
  -- All 8 slots taken and not near any: keep seed hues pure (no blend).
  return best
end

--- Intern a 2bpp tile by bit pattern only. Palette meaning is attached per
-- tileset bank via tilePalettesByTileset[tilesetId][tileId+1] = localSlot —
-- not baked into the dedupe key (pair-local slot 3 ≠ bank-local slot 3).
-- gen2Slot is accepted for call-site compatibility but ignored for identity.
function Quantize.intern(sheet, bpp16, _gen2Slot)
  local key = Quantize.tileKey(bpp16)
  local existing = sheet.keys[key]
  if existing then return existing end
  local id = sheet.count
  sheet.count = id + 1
  sheet.keys[key] = id
  sheet.tiles[id + 1] = bpp16
  return id
end

--- Always allocate a new tile id (no bpp dedupe). Used for indoor void so
-- solid-black content tiles do not share the void's palette slot.
function Quantize.internUnique(sheet, bpp16)
  local id = sheet.count
  sheet.count = id + 1
  sheet.tiles[id + 1] = bpp16
  -- Deliberately omit sheet.keys — content may still dedupe the same bpp.
  return id
end

--- Pack sheet tiles into a contiguous 2bpp byte string (for ImageWriter.decode2bpp).
-- tiles arranged left-to-right, 16 per row by default.
function Quantize.sheetToRaw(sheet, tilesPerRow)
  tilesPerRow = tilesPerRow or 16
  local n = sheet.count
  if n == 0 then return "", 0, 0 end
  local rows = math.ceil(n / tilesPerRow)
  local width = tilesPerRow * 8
  local height = rows * 8
  local raw = {}
  local expected = width * height / 4 -- 2bpp
  for i = 1, expected do raw[i] = 0 end

  for tid = 0, n - 1 do
    local tile = sheet.tiles[tid + 1]
    local col = tid % tilesPerRow
    local row = math.floor(tid / tilesPerRow)
    local destTile = row * tilesPerRow + col
    local base = destTile * 16
    for b = 1, 16 do
      raw[base + b] = tile[b] or 0
    end
  end
  local parts = {}
  local CHUNK = 4096
  for i = 1, #raw, CHUNK do
    local t = {}
    for j = i, math.min(i + CHUNK - 1, #raw) do
      t[#t + 1] = string.char(raw[j])
    end
    parts[#parts + 1] = table.concat(t)
  end
  return table.concat(parts), width, height
end

--- Ensure special-tileset slots exist (fill unused with gray). At least 8 for
-- stock Gen2; Sevii interiors may write up to MAX_PALETTE_SLOTS.
function Quantize.finalizePalettes(sheet)
  local n = 8
  for i = 1, Quantize.MAX_PALETTE_SLOTS do
    if sheet.palettes[i] then n = i end
  end
  if n < 8 then n = 8 end
  local pals = {}
  for i = 1, n do
    if sheet.palettes[i] then
      pals[i] = copy_ramp(sheet.palettes[i])
    else
      pals[i] = gray_ramp()
    end
  end
  return pals
end

Quantize.bgr555_to_y = bgr555_to_y
Quantize.bgr555_to_rgb = bgr555_to_rgb
Quantize.copy_ramp = copy_ramp
Quantize.ramp_dist2 = ramp_dist2

return Quantize
