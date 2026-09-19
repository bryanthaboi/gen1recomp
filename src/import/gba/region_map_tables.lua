-- FireRed region map / location preview ROM tables.
-- Source: pokefirered src/region_map.c (sDungeonInfo, sMapsecName_*,
-- sRegionMapSectionIdToName) and include/map_preview_screen.h
-- (sMapPreviewScreenData).
--
-- Locating is verify-then-scan: the pinned offset is authoritative for every
-- supported dump (the extractor only runs for SHA-1s in Versions.BY_SHA1), so a
-- bounded window scan around it is only a belt-and-braces guard.

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")

local RegionMapTables = {}

RegionMapTables.NOT_FOUND = "location preview data not found in this ROM revision"

-- Bounded re-scan window (bytes) around the pinned offset.
local SCAN_WINDOW = 0x8000
local SCAN_STEP = 4

local CHARMAP = TextIR.CHARMAP
local CTRL = TextIR.CTRL

local function u16le(get, o)
  return get(o) + get(o + 1) * 256
end

local function u32le(get, o)
  return get(o) + get(o + 1) * 256 + get(o + 2) * 65536 + get(o + 3) * 16777216
end

local function romPtrToOffset(addr, romSize)
  if addr < 0x08000000 or addr >= 0x08000000 + romSize then return nil end
  return addr - 0x08000000
end

--- Decode a 0xFF-terminated FRLG string at `offset`.
-- 0xFE (\n) and 0xFA (\l) both become "\n"; unknown control bytes are dropped.
-- Returns the decoded string and the offset of the terminator.
function RegionMapTables.decodeString(get, offset, limit)
  local out = {}
  local o = offset
  local last = limit or (offset + 512)
  while o < last do
    local b = get(o)
    if not b or b == CTRL.EOS then break end
    if b == CTRL.NL or b == CTRL.SCROLL then
      out[#out + 1] = "\n"
    else
      local ch = CHARMAP[b]
      if ch then out[#out + 1] = ch end
    end
    o = o + 1
  end
  return table.concat(out), o
end

-- struct MapPreviewScreen { u8 mapsec; u8 type; u16 flagId;
--                          const void *tilesptr, *tilemapptr, *palptr; }
local PREVIEW_ENTRY_SIZE = Versions.MAP_PREVIEW_ENTRY_SIZE
local PREVIEW_COUNT = Versions.MAP_PREVIEW_COUNT

--- Validate one 16-byte sMapPreviewScreenData entry. Returns the entry or nil.
local function readPreviewEntry(get, romSize, off)
  local mapsec = get(off)
  local typ = get(off + 1)
  if not mapsec or not typ then return nil end
  if mapsec < Versions.MAPSEC_FIRST or mapsec > Versions.MAPSEC_LAST then return nil end
  if typ ~= Versions.MAP_PREVIEW_TYPE_CAVE and typ ~= Versions.MAP_PREVIEW_TYPE_FOREST then
    return nil
  end
  local flagId = u16le(get, off + 2)
  local tilesPtr = u32le(get, off + 4)
  local tilemapPtr = u32le(get, off + 8)
  local palPtr = u32le(get, off + 12)
  local tiles = romPtrToOffset(tilesPtr, romSize)
  local tilemap = romPtrToOffset(tilemapPtr, romSize)
  local pal = romPtrToOffset(palPtr, romSize)
  if not tiles or not tilemap or not pal then return nil end
  -- Structural invariant of the shipped table: the palette is physically the
  -- first 32 colours of the tile block (holds for all 28 entries).
  if pal + 0x40 ~= tiles then return nil end
  return {
    mapsec = mapsec,
    type = typ,
    flagId = flagId,
    tilesOffset = tiles,
    tilemapOffset = tilemap,
    paletteOffset = pal,
  }
end

--- True when `off` starts a full, valid sMapPreviewScreenData table.
local function isPreviewTable(get, romSize, off)
  for i = 0, PREVIEW_COUNT - 1 do
    if not readPreviewEntry(get, romSize, off + i * PREVIEW_ENTRY_SIZE) then
      return false
    end
  end
  return true
end

--- Locate sMapPreviewScreenData. Returns the file offset or nil.
function RegionMapTables.locatePreviewTable(get, romSize, hint)
  hint = hint or Versions.MAP_PREVIEW_SCREEN_DATA
  if hint and hint >= 0 and hint + PREVIEW_COUNT * PREVIEW_ENTRY_SIZE <= romSize then
    if isPreviewTable(get, romSize, hint) then return hint end
  end
  local lo = math.max(0, (hint or 0) - SCAN_WINDOW)
  local hi = math.min(romSize - PREVIEW_COUNT * PREVIEW_ENTRY_SIZE, (hint or 0) + SCAN_WINDOW)
  for off = lo, hi, SCAN_STEP do
    if off ~= hint and isPreviewTable(get, romSize, off) then return off end
  end
  return nil
end

--- Read all 28 sMapPreviewScreenData entries, in table order.
function RegionMapTables.readPreviews(get, romSize, base)
  local out = {}
  for i = 0, PREVIEW_COUNT - 1 do
    local e = readPreviewEntry(get, romSize, base + i * PREVIEW_ENTRY_SIZE)
    if not e then
      error(("map preview entry %d invalid at 0x%X"):format(i, base + i * PREVIEW_ENTRY_SIZE))
    end
    out[#out + 1] = e
  end
  return out
end

--- sMapsecName_* — mapsec 88..196 → display name.
-- Cross-checked against sRegionMapSectionIdToName when that table is intact.
function RegionMapTables.readMapsecNames(get, romSize, base)
  base = base or Versions.MAPSEC_NAMES
  local names = {}
  local order = {}
  local o = base
  for sec = Versions.MAPSEC_FIRST, Versions.MAPSEC_LAST do
    local name, next0 = RegionMapTables.decodeString(get, o)
    names[sec] = name
    order[#order + 1] = o
    o = next0 + 1
  end
  return names, order
end

--- Verify sMapsecName_* against sRegionMapSectionIdToName[].
-- Returns true when every pointer matches the sequentially decoded string.
function RegionMapTables.verifyNamePointers(get, romSize, order, tableBase)
  tableBase = tableBase or Versions.MAPSEC_NAME_POINTERS
  if #order ~= Versions.MAPSEC_COUNT then return false end
  for i = 1, #order do
    local ptr = u32le(get, tableBase + (i - 1) * 4)
    local off = romPtrToOffset(ptr, romSize)
    if off ~= order[i] then return false end
  end
  return true
end

--- sDungeonInfo[] — { id = mapsec, name, desc }.
function RegionMapTables.readDungeonInfo(get, romSize, base)
  base = base or Versions.DUNGEON_INFO
  local out = {}
  local off = base
  for _ = 1, Versions.DUNGEON_INFO_COUNT do
    local mapsec = u32le(get, off)
    local nameOff = romPtrToOffset(u32le(get, off + 4), romSize)
    local descOff = romPtrToOffset(u32le(get, off + 8), romSize)
    if not nameOff or not descOff then break end
    local name = RegionMapTables.decodeString(get, nameOff)
    local desc = RegionMapTables.decodeString(get, descOff)
    out[#out + 1] = { mapsec = mapsec, name = name, desc = desc }
    off = off + Versions.DUNGEON_INFO_ENTRY_SIZE
  end
  return out
end

--- Decode every region-map table this module knows about.
-- Returns a table, or nil + error message.
function RegionMapTables.load(rom)
  local romSize = rom.size
  local get = function(i) return rom:get(i) end

  local previewBase = RegionMapTables.locatePreviewTable(get, romSize)
  if not previewBase then
    return nil, RegionMapTables.NOT_FOUND
  end

  local names, order = RegionMapTables.readMapsecNames(get, romSize)
  local namesVerified = RegionMapTables.verifyNamePointers(get, romSize, order)

  return {
    previewBase = previewBase,
    previews = RegionMapTables.readPreviews(get, romSize, previewBase),
    names = names,
    namesVerified = namesVerified,
    dungeonInfo = RegionMapTables.readDungeonInfo(get, romSize),
  }
end

return RegionMapTables
