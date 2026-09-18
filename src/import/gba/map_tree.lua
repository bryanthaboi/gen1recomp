-- Walk FireRed gMapGroups → MapHeader → MapLayout → Tileset (pret map tree).
-- One ROM pin (gMapGroups) + pret group lengths/names; no per-map header offsets.

local Versions = require("src.import.gba.versions")
local ExtractMapEvents = require("src.import.gba.extract_map_events")

local MapTree = {}

local CONN_DIR = {
  [1] = "south",
  [2] = "north",
  [3] = "west",
  [4] = "east",
}

local function gba_off(rom, ptr)
  return rom:ptrOffset(ptr)
end

local function s32(rom, offset)
  local v = rom:u32(offset)
  if v >= 0x80000000 then return v - 0x100000000 end
  return v
end

function MapTree.loadGroups()
  return require("src.import.gba.map_groups_firered")
end

--- Stable id for a (group, map) tuple. Prefer pret name; else g{G}_m{N}.
-- Engine FR_* aliases are intentionally not preferred here — map_tree is census-first.
function MapTree.mapId(group, num, pretName)
  if type(pretName) == "string" and pretName ~= "" then
    return pretName
  end
  return string.format("g%d_m%d", group, num)
end

function MapTree.slotKey(group, num)
  return string.format("%d_%d", group, num)
end

function MapTree.tilesetId(gbaPtr)
  return string.format("ts_%08x", gbaPtr or 0)
end

--- Full MapHeader (pret global.fieldmap.h).
function MapTree.parseHeader(rom, headerOff)
  local base = ExtractMapEvents.parseHeader(rom, headerOff)
  base.regionMapSectionId = rom:get(headerOff + 20)
  base.cave = rom:get(headerOff + 21)
  base.weather = rom:get(headerOff + 22)
  base.mapType = rom:get(headerOff + 23)
  base.bikingAllowed = rom:get(headerOff + 24)
  local flags = rom:get(headerOff + 25) or 0
  base.allowEscaping = flags % 2
  base.allowRunning = math.floor(flags / 2) % 2
  base.showMapName = math.floor(flags / 4) % 64
  local floor = rom:get(headerOff + 26) or 0
  if floor >= 0x80 then floor = floor - 0x100 end
  base.floorNum = floor
  base.battleType = rom:get(headerOff + 27)
  base.headerOff = headerOff
  return base
end

--- MapLayout at file offset.
function MapTree.parseLayout(rom, layoutOff)
  if not layoutOff then return nil end
  local width = s32(rom, layoutOff)
  local height = s32(rom, layoutOff + 4)
  if width < 1 or height < 1 or width > 512 or height > 512 then
    return nil
  end
  return {
    layoutOff = layoutOff,
    width = width,
    height = height,
    borderPtr = rom:u32(layoutOff + 8),
    mapPtr = rom:u32(layoutOff + 12),
    primaryTilesetPtr = rom:u32(layoutOff + 16),
    secondaryTilesetPtr = rom:u32(layoutOff + 20),
    borderWidth = rom:get(layoutOff + 24) or 2,
    borderHeight = rom:get(layoutOff + 25) or 2,
  }
end

--- struct Tileset; metatile/attr sizes inferred from pointer gap (valid for FR 1.0).
function MapTree.parseTileset(rom, tilesetPtr)
  local off = gba_off(rom, tilesetPtr)
  if not off then return nil end
  local isCompressed = rom:get(off) ~= 0
  local isSecondary = rom:get(off + 1) ~= 0
  local tilesPtr = rom:u32(off + 4)
  local palsPtr = rom:u32(off + 8)
  local mtPtr = rom:u32(off + 12)
  local callbackPtr = rom:u32(off + 16)
  local attrPtr = rom:u32(off + 20)
  local mtOff = gba_off(rom, mtPtr)
  local attrOff = gba_off(rom, attrPtr)
  local metatileBytes = 0
  if mtOff and attrOff and attrOff > mtOff then
    metatileBytes = attrOff - mtOff
  elseif not isSecondary then
    metatileBytes = 10240 -- NUM_PRIMARY_METATILES * 16
  end
  if metatileBytes % 16 ~= 0 then
    metatileBytes = metatileBytes - (metatileBytes % 16)
  end
  local midCount = math.floor(metatileBytes / 16)
  local attrBytes = midCount * 4
  return {
    ptr = tilesetPtr,
    id = MapTree.tilesetId(tilesetPtr),
    structOff = off,
    compressed = isCompressed,
    secondary = isSecondary,
    tilesPtr = tilesPtr,
    palettesPtr = palsPtr,
    metatilesPtr = mtPtr,
    callbackPtr = callbackPtr,
    attributesPtr = attrPtr,
    metatile_bytes = metatileBytes,
    attr_bytes = attrBytes,
    mid_count = midCount,
    palette_count = 16,
  }
end

function MapTree.parseConnections(rom, connectionsPtr, groupsData)
  local off = gba_off(rom, connectionsPtr)
  if not off then return {} end
  local count = rom:u32(off)
  if count >= 0x80000000 or count > 8 then return {} end
  local listOff = gba_off(rom, rom:u32(off + 4))
  if not listOff or count < 1 then return {} end
  local out = {}
  for i = 0, count - 1 do
    local base = listOff + i * 12
    local direction = rom:get(base)
    local offset = rom:u32(base + 4)
    if offset >= 0x80000000 then offset = offset - 0x100000000 end
    local mapGroup = rom:get(base + 8)
    local mapNum = rom:get(base + 9)
    local dirName = CONN_DIR[direction]
    if dirName then
      local pretName = nil
      if groupsData and groupsData.groups and groupsData.groups[mapGroup] then
        local maps = groupsData.groups[mapGroup].maps
        pretName = maps and maps[mapNum + 1]
      end
      out[dirName] = {
        mapGroup = mapGroup,
        mapNum = mapNum,
        offset = offset,
        map = MapTree.mapId(mapGroup, mapNum, pretName),
      }
    end
  end
  return out
end

--- Read raw map.bin u16 cells (metatile | coll<<10 | elev<<12).
function MapTree.readGridBytes(rom, layout)
  local mapOff = gba_off(rom, layout.mapPtr)
  if not mapOff then return nil end
  local nbytes = layout.width * layout.height * 2
  local bytes = rom:readBytes(mapOff, nbytes)
  local buf = {}
  for i = 1, #bytes do
    buf[i] = string.char(bytes[i])
  end
  return table.concat(buf)
end

function MapTree.readBorderBytes(rom, layout)
  local borderOff = gba_off(rom, layout.borderPtr)
  local bw = layout.borderWidth or 2
  local bh = layout.borderHeight or 2
  if not borderOff or bw < 1 or bh < 1 then return nil end
  local nbytes = bw * bh * 2
  local bytes = rom:readBytes(borderOff, nbytes)
  local buf = {}
  for i = 1, #bytes do
    buf[i] = string.char(bytes[i])
  end
  return table.concat(buf)
end

--- Census every map under gMapGroups. Dedupes tileset structs by pointer.
-- @return { maps = {...}, tilesets = { [ptr] = spec }, groups = ... }
function MapTree.walk(rom, version, opts)
  opts = opts or {}
  version = version or Versions.lookup(rom.md5)
  local groupsData = MapTree.loadGroups()
  local gMapGroups = (version and version.g_map_groups) or Versions.G_MAP_GROUPS
  if not gMapGroups then
    return nil, "version missing g_map_groups"
  end

  local allowGroups = opts.groups -- optional set/list of group indices
  local allowSet = nil
  if allowGroups then
    allowSet = {}
    for _, g in ipairs(allowGroups) do allowSet[g] = true end
  end

  local maps = {}
  local tilesets = {}
  local groupSummaries = {}
  local order = groupsData.group_order or {}
  local numGroups = #order

  for gi = 0, numGroups - 1 do
    if allowSet and not allowSet[gi] then
      goto continue_group
    end
    local groupInfo = groupsData.groups[gi]
    if not groupInfo then
      goto continue_group
    end
    local groupPtr = rom:u32(gMapGroups + gi * 4)
    local groupOff = gba_off(rom, groupPtr)
    if not groupOff then
      goto continue_group
    end
    local mapNames = groupInfo.maps or {}
    local groupMaps = {}
    for mi = 0, #mapNames - 1 do
      local headerPtr = rom:u32(groupOff + mi * 4)
      local headerOff = gba_off(rom, headerPtr)
      if not headerOff then
        goto continue_map
      end
      local header = MapTree.parseHeader(rom, headerOff)
      local layoutOff = gba_off(rom, header.layout)
      local layout = MapTree.parseLayout(rom, layoutOff)
      if not layout then
        goto continue_map
      end

      local pretName = mapNames[mi + 1]
      local mapId = MapTree.mapId(gi, mi, pretName)
      local slot = MapTree.slotKey(gi, mi)

      for _, tsPtr in ipairs({ layout.primaryTilesetPtr, layout.secondaryTilesetPtr }) do
        if tsPtr and tsPtr ~= 0 and not tilesets[tsPtr] then
          local ts = MapTree.parseTileset(rom, tsPtr)
          if ts then tilesets[tsPtr] = ts end
        end
      end

      local connections = MapTree.parseConnections(rom, header.connections, groupsData)
      local events = ExtractMapEvents.parseMapEvents(rom, header.events)

      -- Resolve warp dest names with pret census (not only hand FRLG_MAP_TO_FR).
      if events and events.warps then
        for _, w in ipairs(events.warps) do
          local ginfo = groupsData.groups[w.mapGroup]
          local n = ginfo and ginfo.maps and ginfo.maps[(w.mapNum or 0) + 1]
          w.destMap = MapTree.mapId(w.mapGroup, w.mapNum, n)
        end
      end

      local entry = {
        group = gi,
        num = mi,
        slot = slot,
        id = mapId,
        pretName = pretName,
        groupName = groupInfo.name,
        header = header,
        layout = layout,
        connections = connections,
        events = events,
        primaryTileset = MapTree.tilesetId(layout.primaryTilesetPtr),
        secondaryTileset = MapTree.tilesetId(layout.secondaryTilesetPtr),
      }
      maps[#maps + 1] = entry
      groupMaps[#groupMaps + 1] = { slot = slot, id = mapId, num = mi }
      ::continue_map::
    end
    groupSummaries[#groupSummaries + 1] = {
      group = gi,
      name = groupInfo.name,
      count = #groupMaps,
      maps = groupMaps,
    }
    ::continue_group::
  end

  table.sort(maps, function(a, b)
    if a.group ~= b.group then return a.group < b.group end
    return a.num < b.num
  end)

  return {
    maps = maps,
    tilesets = tilesets,
    groups = groupSummaries,
    g_map_groups = gMapGroups,
    map_count = #maps,
    tileset_count = (function()
      local n = 0
      for _ in pairs(tilesets) do n = n + 1 end
      return n
    end)(),
  }
end

return MapTree
