-- Extract pret General tileset anim frames and per-mid RGBA banks.
-- FireRed: TilesetAnim_General — water@416, sand@464, flower@508.

local Versions = require("src.import.gba.versions")
local Tileset = require("src.import.gba.tileset")
local Metatile = require("src.import.gba.metatile")
local NativePack = require("src.import.gba.native_pack")

local AnimPack = {}

-- Destination tile ranges (primary tileset ids).
AnimPack.WATER_TILE = 416
AnimPack.WATER_COUNT = 48 -- tiles
AnimPack.SAND_TILE = 464
AnimPack.SAND_COUNT = 18
AnimPack.FLOWER_TILE = 508
AnimPack.FLOWER_COUNT = 4

local TILE_BYTES = 32

-- FireRed USA 1.0 file offsets (from pokefirered.sym).
local DEFAULT_FRAMES = {
  flower = {
    base = 0x3A73E0,
    stride = 0x80,
    count = 5,
    bytes = 4 * TILE_BYTES, -- 0x80
  },
  water = {
    base = 0x3A7674,
    stride = 0x600,
    count = 8,
    bytes = 48 * TILE_BYTES, -- 0x600; frame7 is 0x5E0 in sym — pad
  },
  sand = {
    base = 0x3AA674,
    stride = 0x240,
    count = 8,
    bytes = 18 * TILE_BYTES, -- 0x240
  },
}

local function pairs_using_general(version)
  local catalog = (version and version.tileset_pairs) or Versions.TILESET_PAIRS
  local tilesets = (version and version.tilesets) or Versions.TILESETS
  local out = {}
  for name, pair in pairs(catalog or {}) do
    local pri = tilesets[pair.primary]
    -- general primary is the animating one
    if pair.primary == "general" or (pri and pri.tiles == Versions.TILESETS.general.tiles) then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

local function mid_uses_range(bundle, mid, t0, t1)
  local entries = Tileset.metatileEntries(bundle.primaryMt, bundle.secondaryMt, mid)
  if not entries then return false end
  for i = 1, 8 do
    local tid = (entries[i] or 0) % 1024
    if tid >= t0 and tid < t1 then return true end
  end
  return false
end

local function classify_mid(bundle, mid)
  local water = mid_uses_range(bundle, mid, AnimPack.WATER_TILE, AnimPack.WATER_TILE + AnimPack.WATER_COUNT)
  local sand = mid_uses_range(bundle, mid, AnimPack.SAND_TILE, AnimPack.SAND_TILE + AnimPack.SAND_COUNT)
  local flower = mid_uses_range(bundle, mid, AnimPack.FLOWER_TILE, AnimPack.FLOWER_TILE + AnimPack.FLOWER_COUNT)
  if water then return "water" end
  if sand then return "sand" end
  if flower then return "flower" end
  return nil
end

--- Copy primary tiles raw into a mutable 1-based byte array (tid → 32 bytes).
local function mutable_primary(bundle)
  local tiles = bundle.primaryTiles
  local raw = tiles.raw
  local count = tiles.count or 0
  local bytes = {}
  local nbytes = count * TILE_BYTES
  if type(raw) == "string" then
    for i = 1, math.min(nbytes, #raw) do bytes[i] = raw:byte(i) end
  elseif raw._ffi then
    for i = 0, nbytes - 1 do bytes[i + 1] = raw._ffi[i] or 0 end
  else
    for i = 1, nbytes do bytes[i] = raw[i] or 0 end
  end
  return {
    count = count,
    raw = bytes,
    _mutable = true,
  }
end

local function paste_tiles(dstTiles, startTid, frameBytes)
  local base = startTid * TILE_BYTES
  for i = 1, #frameBytes do
    dstTiles.raw[base + i] = frameBytes:byte(i) or 0
  end
end

local function read_frame(rom, off, nbytes)
  local t = rom:readBytes(off, nbytes)
  local s = {}
  for i = 1, nbytes do s[i] = string.char(t[i] or 0) end
  return table.concat(s)
end

function AnimPack.loadFramesFromRom(rom, version)
  local spec = (version and version.tileset_anim_general) or Versions.TILESET_ANIM_GENERAL or DEFAULT_FRAMES
  local frames = {}
  for name, cfg in pairs(spec) do
    local list = {}
    for i = 0, cfg.count - 1 do
      local off = cfg.base + i * cfg.stride
      list[i + 1] = read_frame(rom, off, cfg.bytes)
    end
    frames[name] = list
  end
  return frames
end

local function bake_mid_rgba(bundle, mid, rgbPals)
  -- Animate under-layer atlas (sprites sit above this).
  local idx = Metatile.compositeIndexedUnder(bundle, mid)
  local fake = {
    midCount = 1,
    atlasCols = 1,
    atlasRows = 1,
    midIds = { mid },
    pixels = idx,
  }
  local rgba = NativePack.bakeRgba(fake, rgbPals)
  return rgba
end

--- Write anim frame banks for pairs that use General primary.
-- @param midLists [pair] = sorted mid ids used on that pair's maps
function AnimPack.writeExtract(rom, cache, root, bundles, midLists, version)
  root = root or "data/generated/gba"
  local frames = AnimPack.loadFramesFromRom(rom, version)
  local generalPairs = pairs_using_general(version)
  local rgbCache = {}

  -- Shared raw anim dumps (for debugging / alternate runtimes).
  local animRoot = root .. "/native/general/anim"
  for name, list in pairs(frames) do
    for i, blob in ipairs(list) do
      cache:write(animRoot .. "/" .. name .. "_" .. (i - 1) .. ".4bpp", blob)
    end
  end

  local globalManifest = { anim_version = Versions.ANIM_VERSION or 1, pairs = {} }

  for _, pairName in ipairs(generalPairs) do
    local bundle = bundles[pairName]
    if bundle then
      local mids = midLists and midLists[pairName] or {}
      local byKind = { water = {}, sand = {}, flower = {} }
      for _, mid in ipairs(mids) do
        local kind = classify_mid(bundle, mid)
        if kind then
          byKind[kind][#byKind[kind] + 1] = mid
        end
      end

      local rgbPals = rgbCache[pairName]
      if not rgbPals then
        rgbPals = NativePack.palsToRgb8(bundle.mapPals)
        rgbCache[pairName] = rgbPals
      end

      local pairDir = root .. "/native/" .. pairName
      local pairManifest = {
        water = { mids = byKind.water, frames = #frames.water },
        sand = { mids = byKind.sand, frames = #frames.sand },
        flower = { mids = byKind.flower, frames = #frames.flower },
      }

      local function write_bank(kind, startTid, frameList)
        local midList = byKind[kind]
        if #midList < 1 then return end
        local chunks = {}
        for _, frameBlob in ipairs(frameList) do
          local baseTiles = mutable_primary(bundle)
          paste_tiles(baseTiles, startTid, frameBlob)
          local work = {
            primaryTiles = baseTiles,
            secondaryTiles = bundle.secondaryTiles,
            mapPals = bundle.mapPals,
            primaryMt = bundle.primaryMt,
            secondaryMt = bundle.secondaryMt,
            primaryAttr = bundle.primaryAttr,
            secondaryAttr = bundle.secondaryAttr,
          }
          for _, mid in ipairs(midList) do
            chunks[#chunks + 1] = bake_mid_rgba(work, mid, rgbPals)
          end
        end
        -- Layout: frame-major: frame0[all mids], frame1[all mids], ...
        -- offset = (frame * #mids + midIndex) * 1024
        cache:write(pairDir .. "/anim_" .. kind .. ".rgba", table.concat(chunks))
      end

      write_bank("water", AnimPack.WATER_TILE, frames.water)
      write_bank("sand", AnimPack.SAND_TILE, frames.sand)
      write_bank("flower", AnimPack.FLOWER_TILE, frames.flower)

      local lines = {
        "return {\n",
        ("  anim_version = %d,\n"):format(Versions.ANIM_VERSION or 1),
        "  water = { frames = " .. tostring(#frames.water) .. ", mids = {",
      }
      for i, mid in ipairs(byKind.water) do
        lines[#lines + 1] = (i > 1 and ", " or "") .. tostring(mid)
      end
      lines[#lines + 1] = "} },\n  sand = { frames = " .. tostring(#frames.sand) .. ", mids = {"
      for i, mid in ipairs(byKind.sand) do
        lines[#lines + 1] = (i > 1 and ", " or "") .. tostring(mid)
      end
      lines[#lines + 1] = "} },\n  flower = { frames = " .. tostring(#frames.flower) .. ", mids = {"
      for i, mid in ipairs(byKind.flower) do
        lines[#lines + 1] = (i > 1 and ", " or "") .. tostring(mid)
      end
      lines[#lines + 1] = "} },\n}\n"
      cache:write(pairDir .. "/anim_manifest.lua", table.concat(lines))
      globalManifest.pairs[pairName] = pairManifest
      print(string.format("[anim] %s water=%d sand=%d flower=%d",
        pairName, #byKind.water, #byKind.sand, #byKind.flower))
    end
  end

  return globalManifest
end

function AnimPack.ready(cache, root, pair)
  root = root or "data/generated/gba"
  if not pair then
    return cache and cache:exists(root .. "/native/general/anim/water_0.4bpp")
  end
  return cache and cache:exists(root .. "/native/" .. pair .. "/anim_manifest.lua")
end

AnimPack.DEFAULT_FRAMES = DEFAULT_FRAMES
AnimPack.pairsUsingGeneral = pairs_using_general
AnimPack.classifyMid = classify_mid

return AnimPack
