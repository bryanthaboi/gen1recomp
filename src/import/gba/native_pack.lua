-- Encode/decode Sevii native FRLG mid atlas + palette + layout blobs.
-- Pure Lua (no love / no ROM). Shared by extract, register, and tests.

local Tileset = require("src.import.gba.tileset")
local Metatile = require("src.import.gba.metatile")
local Versions = require("src.import.gba.versions")

local NativePack = {}

NativePack.MAGIC_IDX = "SVMI"
NativePack.MAGIC_PAL = "SVMP"
NativePack.MAGIC_MID = "SVML"
NativePack.FORMAT_VERSION = 1

local function u8(n)
  return string.char((tonumber(n) or 0) % 256)
end

local function u16le(n)
  n = (tonumber(n) or 0) % 65536
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function read_u16(s, i)
  return s:byte(i) + s:byte(i + 1) * 256
end

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

-- flags bit0: legacy flattened (pre dual-layer). bit1: under/over split.
NativePack.FLAG_FLAT = 1
NativePack.FLAG_LAYERED = 2

local function build_idx_with(compositeFn, bundle, midList, flags)
  midList = midList or {}
  local midCount = #midList
  local atlasCols = 16
  local atlasRows = math.max(1, math.ceil(midCount / atlasCols))
  local pixels = {}
  for i = 1, midCount * 256 do pixels[i] = 0 end
  for i, mid in ipairs(midList) do
    local idxBuf = compositeFn(bundle, mid)
    local base = (i - 1) * 256
    for p = 1, 256 do
      pixels[base + p] = idxBuf[p] or 0
    end
  end
  return {
    formatVersion = NativePack.FORMAT_VERSION,
    flags = flags or 0,
    midCount = midCount,
    atlasCols = atlasCols,
    atlasRows = atlasRows,
    midIds = midList,
    pixels = pixels,
  }
end

--- Build indexed mid atlas for one tileset pair (legacy flat composite).
-- @param bundle Tileset.loadPair result
-- @param midList sorted list of ROM mid ids to include
function NativePack.buildIdx(bundle, midList)
  return build_idx_with(Metatile.compositeIndexed, bundle, midList, NativePack.FLAG_FLAT)
end

--- Under (BG3/BG1) + over (BG2) atlases matching pret DrawMetatile layer split.
function NativePack.buildLayeredIdx(bundle, midList)
  local under = build_idx_with(
    Metatile.compositeIndexedUnder, bundle, midList, NativePack.FLAG_LAYERED)
  local over = build_idx_with(
    Metatile.compositeIndexedOver, bundle, midList, NativePack.FLAG_LAYERED)
  return under, over
end

function NativePack.encodeIdx(tbl)
  local parts = {
    NativePack.MAGIC_IDX,
    u8(tbl.formatVersion or NativePack.FORMAT_VERSION),
    u8(tbl.flags or 1),
    u16le(tbl.midCount or 0),
    u16le(tbl.atlasCols or 16),
    u16le(tbl.atlasRows or 1),
  }
  for _, mid in ipairs(tbl.midIds or {}) do
    parts[#parts + 1] = u16le(mid)
  end
  local pix = tbl.pixels or {}
  local n = (tbl.midCount or 0) * 256
  local chunk = {}
  for i = 1, n do
    chunk[i] = u8(pix[i] or 0)
  end
  parts[#parts + 1] = table.concat(chunk)
  return table.concat(parts)
end

function NativePack.decodeIdx(blob)
  if type(blob) ~= "string" or #blob < 12 or blob:sub(1, 4) ~= NativePack.MAGIC_IDX then
    return nil, "bad mids.idx magic"
  end
  local formatVersion = blob:byte(5)
  local flags = blob:byte(6)
  local midCount = read_u16(blob, 7)
  local atlasCols = read_u16(blob, 9)
  local atlasRows = read_u16(blob, 11)
  -- The header comes from a file in the user-writable cache and was trusted:
  -- an absurd midCount walks the pixel loop past the blob (read_u16 does not
  -- bounds-check), and an absurd atlas sizes a ~4 TB buffer downstream in
  -- bake_or_load.  Require the declared tables to fit the blob, and the
  -- dimensions to be sane, before reading anything.
  local MAX_MIDS, MAX_ATLAS_TILES = 4096, 16384
  if midCount < 1 or atlasCols < 1 or atlasRows < 1 then
    return nil, "bad mids.idx dimensions"
  end
  if midCount > MAX_MIDS or atlasCols * atlasRows > MAX_ATLAS_TILES then
    return nil, "mids.idx dimensions out of range"
  end
  if #blob < 12 + midCount * 2 + midCount * 256 then
    return nil, "mids.idx truncated"
  end
  local midIds = {}
  local off = 13
  for i = 1, midCount do
    midIds[i] = read_u16(blob, off)
    off = off + 2
  end
  local pixels = {}
  local n = midCount * 256
  for i = 1, n do
    pixels[i] = blob:byte(off + i - 1) or 0
  end
  return {
    formatVersion = formatVersion,
    flags = flags,
    midCount = midCount,
    atlasCols = atlasCols,
    atlasRows = atlasRows,
    midIds = midIds,
    pixels = pixels,
  }
end

function NativePack.encodePalettes(mapPals)
  local parts = {
    NativePack.MAGIC_PAL,
    u8(NativePack.FORMAT_VERSION),
    u8(Tileset.NUM_PALS_IN_PRIMARY),
    u8(Tileset.NUM_PALS_TOTAL),
    u8(0),
  }
  for p = 0, 15 do
    local colors = mapPals[p] or mapPals[0] or {}
    for c = 0, 15 do
      parts[#parts + 1] = u16le(colors[c] or 0)
    end
  end
  return table.concat(parts)
end

function NativePack.decodePalettes(blob)
  if type(blob) ~= "string" or #blob < 8 + 16 * 16 * 2
      or blob:sub(1, 4) ~= NativePack.MAGIC_PAL then
    return nil, "bad palettes.bin magic"
  end
  local pals = {
    formatVersion = blob:byte(5),
    numPalsInPrimary = blob:byte(6),
    numPalsTotal = blob:byte(7),
  }
  local off = 9
  for p = 0, 15 do
    local colors = {}
    for c = 0, 15 do
      colors[c] = read_u16(blob, off)
      off = off + 2
    end
    pals[p] = colors
  end
  return pals
end

--- Decode BGR555 pals → RGB8 tables for bake / tint.
function NativePack.palsToRgb8(mapPals)
  local out = {}
  for p = 0, 15 do
    local src = mapPals[p] or mapPals[0] or {}
    local colors = {}
    for c = 0, 15 do
      local r, g, b = bgr555_to_rgb8(src[c] or 0)
      colors[c] = { r, g, b }
    end
    out[p] = colors
  end
  return out
end

--- Bake indexed atlas + RGB8 pals → contiguous RGBA8 string (w*h*4 bytes).
-- opts.transparentZero: indexed byte 0 → alpha 0 (overhead / BG2 top layer).
function NativePack.bakeRgba(idxTbl, rgbPals, opts)
  opts = opts or {}
  local transparentZero = opts.transparentZero == true
  local midCount = idxTbl.midCount or 0
  local cols = idxTbl.atlasCols or 16
  local rows = idxTbl.atlasRows or math.max(1, math.ceil(midCount / cols))
  local w, h = cols * 16, rows * 16
  local lut = {}
  for byte = 0, 255 do
    if transparentZero and byte == 0 then
      lut[0] = string.char(0, 0, 0, 0)
    else
      local palSlot = math.floor(byte / 16) % 16
      local colorIndex = byte % 16
      local pal = rgbPals[palSlot] or rgbPals[0]
      local rgb = pal and pal[colorIndex] or { 0, 0, 0 }
      lut[byte] = string.char(rgb[1] or 0, rgb[2] or 0, rgb[3] or 0, 255)
    end
  end
  -- Fill atlas by mid slot: slot i occupies atlas cell (i%cols, floor(i/cols)).
  local pixels = idxTbl.pixels or {}
  local rowChunks = {}
  for ay = 0, h - 1 do
    local midRow = math.floor(ay / 16)
    local py = ay % 16
    local line = {}
    for ax = 0, w - 1 do
      local midCol = math.floor(ax / 16)
      local px = ax % 16
      local slot = midRow * cols + midCol -- 0-based atlas slot
      local byte = 0
      if slot < midCount then
        local base = slot * 256
        byte = pixels[base + py * 16 + px + 1] or 0
      end
      line[ax + 1] = lut[byte] or lut[0]
    end
    rowChunks[ay + 1] = table.concat(line)
  end
  return table.concat(rowChunks), w, h
end

function NativePack.encodeMidLayout(layout)
  local parts = {
    NativePack.MAGIC_MID,
    u8(layout.formatVersion or NativePack.FORMAT_VERSION),
    u8(layout.flags or 0),
    u16le(layout.width),
    u16le(layout.height),
    u16le(layout.trueWidth or layout.width),
    u16le(layout.trueHeight or layout.height),
    u8(layout.borderWidth or 1),
    u8(layout.borderHeight or 1),
  }
  local bw = layout.borderWidth or 1
  local bh = layout.borderHeight or 1
  local border = layout.borderMids or {}
  for i = 1, bw * bh do
    parts[#parts + 1] = u16le(border[i] or 0)
  end
  local cells = layout.cells or {}
  local n = (layout.width or 0) * (layout.height or 0)
  for i = 1, n do
    local c = cells[i] or { mid = 0, coll = 0xff, elev = 0 }
    parts[#parts + 1] = u16le(c.mid or 0)
    parts[#parts + 1] = u8(c.coll or 0)
    parts[#parts + 1] = u8(c.elev or 0)
  end
  return table.concat(parts)
end

function NativePack.decodeMidLayout(blob)
  if type(blob) ~= "string" or #blob < 14 or blob:sub(1, 4) ~= NativePack.MAGIC_MID then
    return nil, "bad layout.mid magic"
  end
  local formatVersion = blob:byte(5)
  local flags = blob:byte(6)
  local width = read_u16(blob, 7)
  local height = read_u16(blob, 9)
  local trueWidth = read_u16(blob, 11)
  local trueHeight = read_u16(blob, 13)
  local borderWidth = blob:byte(15)
  local borderHeight = blob:byte(16)
  local off = 17
  local borderMids = {}
  for i = 1, borderWidth * borderHeight do
    borderMids[i] = read_u16(blob, off)
    off = off + 2
  end
  local cells = {}
  local n = width * height
  for i = 1, n do
    local mid = read_u16(blob, off)
    local coll = blob:byte(off + 2)
    local elev = blob:byte(off + 3)
    cells[i] = { mid = mid, coll = coll, elev = elev }
    off = off + 4
  end
  return {
    formatVersion = formatVersion,
    flags = flags,
    width = width,
    height = height,
    trueWidth = trueWidth,
    trueHeight = trueHeight,
    borderWidth = borderWidth,
    borderHeight = borderHeight,
    borderMids = borderMids,
    cells = cells,
  }
end

local DYNAMIC_MIDS_BY_PAIR = {
  network = {
    0x2D0, 0x2D1, 0x2D8, 0x2D9, 0x2E3, 0x2E4, 0x2EB, 0x2EC,
    0x308, 0x309, 0x30A, 0x30B, 0x310, 0x311, 0x312, 0x313,
    0x314, 0x315, 0x316, 0x317, 0x31C, 0x31E,
  },
  pokemon_center = {
    0x2D0, 0x2D1, 0x2D8, 0x2D9, 0x2E3, 0x2E4, 0x2EB, 0x2EC,
    0x308, 0x309, 0x30A, 0x30B, 0x310, 0x311, 0x312, 0x313,
    0x314, 0x315, 0x316, 0x317, 0x31C, 0x31E,
  },
  dept_store = {
    0x28D, 0x2D0, 0x2D1, 0x2D8, 0x2D9, 0x2E3, 0x2E4, 0x2EB, 0x2EC,
    0x308, 0x309, 0x30A, 0x30B, 0x310, 0x311, 0x312, 0x313,
    0x314, 0x315, 0x316, 0x317, 0x31C, 0x31E,
  },
}

-- pokefirered/src/field_specials.c:283
NativePack.PC_ON_BY_OFF = {
  [0x062] = 0x063, -- pokefirered/include/constants/metatile_labels.h:6
  [0x28F] = 0x28A, -- pokefirered/include/constants/metatile_labels.h:75
}

function NativePack.addPcOnMids(seen)
  for off, on in pairs(NativePack.PC_ON_BY_OFF) do
    if seen[off] then seen[on] = true end
  end
  return seen
end

-- pokefirered/include/fieldmap.h:9
NativePack.NUM_METATILES_TOTAL = 1024

local function scriptTargets(v, out)
  if type(v) == "string" then
    if v:sub(1, 3) == "g3:" then out[#out + 1] = v end
  elseif type(v) == "table" then
    for _, x in pairs(v) do scriptTargets(x, out) end
  end
end

-- pokefirered/src/scrcmd.c:2103
function NativePack.scriptMidsByPair(scripts, events, pairOf)
  local out = {}
  if type(scripts) ~= "table" or type(events) ~= "table" then return out end
  scripts = scripts.scripts or scripts
  events = events.events or events
  for mapId, ev in pairs(events) do
    local pairName = type(ev) == "table" and pairOf(mapId) or nil
    if pairName then
      local stack, visited = {}, {}
      scriptTargets(ev, stack)
      while #stack > 0 do
        local key = table.remove(stack)
        if not visited[key] then
          visited[key] = true
          local rows = scripts[key]
          if type(rows) == "table" then
            for _, row in ipairs(rows) do
              if type(row) == "table" then
                if row.op == "setmetatile" then
                  local mid = tonumber(row[3])
                  if mid and mid >= 0 and mid < NativePack.NUM_METATILES_TOTAL then
                    out[pairName] = out[pairName] or {}
                    out[pairName][mid] = true
                  end
                end
                scriptTargets(row, stack)
              end
            end
          end
        end
      end
    end
  end
  return out
end

NativePack.WARP_KEY_STRIDE = 4096

function NativePack.warpKey(x, y)
  return y * NativePack.WARP_KEY_STRIDE + x
end

-- pokefirered/src/event_object_movement.c:4835
function NativePack.resolveLayoutColl(coll, mapColl, hasWarp)
  if (mapColl or 0) == 0 then return coll end
  local Coll = require("src.core.CollPermissions")
  if Coll.isLedge(coll) then return coll end
  -- pokefirered/src/field_control_avatar.c:987
  if hasWarp and coll >= 0x60 and coll <= 0x7F then return coll end
  if not Coll.isWalkable(coll) then return coll end
  return require("src.core.game3.scripting.collision").seed("BLOCKED")
end

local function addVoidFillMids(seen, borders, pairName)
  local VoidFill = require("src.core.game3.void_fill")
  local spec = Versions.TILESET_PAIRS and Versions.TILESET_PAIRS[pairName]
  if not (spec and spec.primary == VoidFill.PRIMARY) then return end
  for _, mapId in pairs(VoidFill.SOURCES) do
    local border = borders and borders[mapId]
    for _, mid in ipairs(border and border.mids or {}) do
      if mid < VoidFill.PRIMARY_MIDS then seen[mid] = true end
    end
  end
end

--- Collect unique mids used by grids + borders for a pair.
function NativePack.collectMidsForPair(grids, borders, pairName, scriptMids)
  local seen = {}
  for mid in pairs(scriptMids and scriptMids[pairName] or {}) do
    seen[mid] = true
  end
  addVoidFillMids(seen, borders, pairName)
  for _, grid in pairs(grids or {}) do
    if (grid.pair or "sevii_outdoor") == pairName then
      for _, cell in ipairs(grid.cells or {}) do
        seen[cell.mid] = true
      end
    end
  end
  for mapId, border in pairs(borders or {}) do
    local grid = grids and grids[mapId]
    local spec = Versions.MAPS[mapId]
    if ((grid and grid.pair) or (spec and spec.pair) or "sevii_outdoor") == pairName then
      for _, mid in ipairs(border.mids or {}) do
        seen[mid] = true
      end
    end
  end
  if DYNAMIC_MIDS_BY_PAIR[pairName] then
    for _, mid in ipairs(DYNAMIC_MIDS_BY_PAIR[pairName]) do
      seen[mid] = true
    end
  end
  NativePack.addPcOnMids(seen)
  seen[0] = true -- void / default border
  local list = {}
  for mid in pairs(seen) do list[#list + 1] = mid end
  table.sort(list)
  return list
end

--- Write all native blobs for Island 1 extract.
-- grids: padded map grids; borders: mapId → { width, height, mids }
-- midIndex: optional [pair][mid] = { coll, ... } for resolved COLL_* lookup
-- CollisionFn: function(mid, rawColl, behavior, kind) → collByte
function NativePack.writeExtract(cache, root, bundles, grids, borders, pairNames, midIndex, behaviorOf, fromCell, scriptMids, warpCells)
  root = root or require("src.core.game3.cache_paths").CACHE_ROOT
  local NativeRoot = root .. "/native"
  local manifest = {
    native_version = Versions.NATIVE_VERSION or 1,
    pairs = {},
    layouts = {},
  }

  for _, pairName in ipairs(pairNames or {}) do
    local bundle = bundles[pairName]
    if bundle then
      local midList = NativePack.collectMidsForPair(grids, borders, pairName, scriptMids)
      local underTbl, overTbl = NativePack.buildLayeredIdx(bundle, midList)
      local palBlob = NativePack.encodePalettes(bundle.mapPals)
      local pairDir = NativeRoot .. "/" .. pairName
      cache:write(pairDir .. "/mids.idx", NativePack.encodeIdx(underTbl))
      cache:write(pairDir .. "/mids_over.idx", NativePack.encodeIdx(overTbl))
      cache:write(pairDir .. "/palettes.bin", palBlob)
      manifest.pairs[pairName] = {
        midCount = underTbl.midCount,
        atlasCols = underTbl.atlasCols,
        atlasRows = underTbl.atlasRows,
        layered = true,
      }
    end
  end

  for mapId, grid in pairs(grids or {}) do
    local pairName = grid.pair or "sevii_outdoor"
    local bundle = bundles[pairName]
    local indexForPair = midIndex and midIndex[pairName] or {}
    local mapWarps = warpCells and warpCells[grid.altOwner or mapId] or nil
    local trueW = grid.padded_from and grid.padded_from.width or grid.width
    local trueH = grid.padded_from and grid.padded_from.height or grid.height
    local border = borders and borders[mapId] or { width = 1, height = 1, mids = { 0 } }
    local cells = {}
    for i, cell in ipairs(grid.cells or {}) do
      -- Prefer per-cell classify (mapColl + kind). midIndex is first-sight and
      -- wrongly solidifies indoor carpets that share outdoor TREE mid numbers.
      local coll = 0xff
      if fromCell and behaviorOf and bundle then
        local beh = behaviorOf(bundle, cell.mid)
        coll = select(1, fromCell(cell.mid, cell.coll, beh, grid.kind))
      else
        local mi = indexForPair[cell.mid]
        if mi and mi.coll ~= nil then
          coll = mi.coll
        else
          coll = cell.coll or 0
        end
      end
      local cx = (i - 1) % grid.width
      local cy = math.floor((i - 1) / grid.width)
      coll = NativePack.resolveLayoutColl(coll, cell.coll,
        mapWarps and mapWarps[cy * NativePack.WARP_KEY_STRIDE + cx])
      cells[i] = { mid = cell.mid, coll = coll, elev = cell.elev or 0 }
    end
    local layout = {
      formatVersion = NativePack.FORMAT_VERSION,
      flags = (grid.padded_from and 1) or 0,
      width = grid.width,
      height = grid.height,
      trueWidth = trueW,
      trueHeight = trueH,
      borderWidth = border.width or 1,
      borderHeight = border.height or 1,
      borderMids = border.mids or { 0 },
      cells = cells,
      pair = pairName,
    }
    local blob = NativePack.encodeMidLayout(layout)
    cache:write(NativeRoot .. "/layouts/" .. mapId .. ".mid", blob)
    -- pokefirered/src/scrcmd.c:711
    if not grid.altLayoutId then
      manifest.layouts[mapId] = {
        pair = pairName,
        width = layout.width,
        height = layout.height,
        file = "layouts/" .. mapId .. ".mid",
      }
    end
  end

  local lines = {
    "return {\n",
    ("  native_version = %d,\n"):format(manifest.native_version),
    "  pairs = {\n",
  }
  for _, pairName in ipairs(pairNames or {}) do
    local p = manifest.pairs[pairName]
    if p then
      lines[#lines + 1] = ("    [%q] = { midCount = %d, atlasCols = %d, atlasRows = %d, layered = true },\n"):format(
        pairName, p.midCount, p.atlasCols, p.atlasRows)
    end
  end
  lines[#lines + 1] = "  },\n  layouts = {\n"
  local mapIds = {}
  for mapId in pairs(manifest.layouts) do mapIds[#mapIds + 1] = mapId end
  table.sort(mapIds)
  for _, mapId in ipairs(mapIds) do
    local L = manifest.layouts[mapId]
    lines[#lines + 1] = ("    [%q] = { pair = %q, width = %d, height = %d, file = %q },\n"):format(
      mapId, L.pair, L.width, L.height, L.file)
  end
  lines[#lines + 1] = "  },\n}\n"
  cache:write(NativeRoot .. "/manifest.lua", table.concat(lines))
  return manifest
end

NativePack.bgr555ToRgb8 = bgr555_to_rgb8

return NativePack
