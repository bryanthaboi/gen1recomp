-- Parse FRLG MapHeader / MapEvents from ROM → game3 event tables.
-- Primary writer for scripts/events cache (Gen2 extractScriptsAndText pattern).

local Versions = require("src.import.gba.versions")
local Opcodes = require("src.core.game3.scripting.opcodes")
local GfxIds = require("src.core.game3.scripting.gfx_ids")

local ExtractMapEvents = {}

local OBJ_SIZE = 24
local BG_SIZE = 12
local WARP_SIZE = 8
local COORD_SIZE = 16

-- Map script types (pret constants/maps.h)
local MAP_SCRIPT_ON_LOAD = 1
local MAP_SCRIPT_ON_FRAME_TABLE = 2
local MAP_SCRIPT_ON_TRANSITION = 3
local MAP_SCRIPT_ON_WARP_INTO_MAP_TABLE = 4
local MAP_SCRIPT_ON_RESUME = 5
local MAP_SCRIPT_ON_DIVER_WARP_TABLE = 6
local MAP_SCRIPT_ON_RETURN_TO_FIELD = 7

local BG_EVENT_HIDDEN_ITEM = 7

local function gba_off(rom, ptr)
  return rom:ptrOffset(ptr)
end

local function parse_objects(rom, ptr, count)
  local off = gba_off(rom, ptr)
  if not off or count <= 0 then return {} end
  local objects = {}
  for i = 0, count - 1 do
    local base = off + i * OBJ_SIZE
    local localId = rom:get(base)
    local graphics = rom:get(base + 1)
    local x = rom:u16(base + 4)
    if x >= 0x8000 then x = x - 0x10000 end
    local y = rom:u16(base + 6)
    if y >= 0x8000 then y = y - 0x10000 end
    local elev = rom:get(base + 8)
    local movementType = rom:get(base + 9)
    local rangeWord = rom:u16(base + 10)
    local rangeX = rangeWord % 16
    local rangeY = math.floor(rangeWord / 16) % 16
    local trainerType = rom:u16(base + 12)
    local sight = rom:u16(base + 14)
    local scriptPtr = rom:u32(base + 16)
    local flag = rom:u16(base + 20)
    local host = GfxIds.hostMovement(movementType, rangeX, rangeY)
    local scriptKey = nil
    if scriptPtr ~= 0 and gba_off(rom, scriptPtr) then
      scriptKey = Opcodes.key(scriptPtr)
    end
    objects[#objects + 1] = {
      localId = localId,
      index = localId,
      graphicsId = graphics,
      graphics = graphics,
      sprite = GfxIds.spriteFor(graphics),
      x = x,
      y = y,
      elevation = elev,
      movementType = movementType,
      movement = host.movement,
      range = host.range,
      radius = host.radius,
      trainerType = trainerType,
      sight = sight,
      trainerRange = sight,
      scriptPtr = scriptPtr,
      scriptKey = scriptKey,
      flag = flag,
    }
  end
  return objects
end

local function parse_bg_events(rom, ptr, count)
  local off = gba_off(rom, ptr)
  if not off or count <= 0 then return {} end
  local bgs = {}
  for i = 0, count - 1 do
    local base = off + i * BG_SIZE
    local x = rom:u16(base)
    local y = rom:u16(base + 2)
    local elev = rom:get(base + 4)
    local kind = rom:get(base + 5)
    local scriptPtr = rom:u32(base + 8)
    local row = {
      type = "sign",
      x = x,
      y = y,
      elevation = elev,
      kind = kind,
      scriptPtr = scriptPtr,
    }
    -- Hidden items store item data in the union, not a script pointer.
    if kind ~= BG_EVENT_HIDDEN_ITEM and scriptPtr ~= 0 and gba_off(rom, scriptPtr) then
      row.scriptKey = Opcodes.key(scriptPtr)
    end
    bgs[#bgs + 1] = row
  end
  return bgs
end

local function parse_coord_events(rom, ptr, count)
  local off = gba_off(rom, ptr)
  if not off or count <= 0 then return {} end
  local coords = {}
  for i = 0, count - 1 do
    local base = off + i * COORD_SIZE
    local x = rom:u16(base)
    local y = rom:u16(base + 2)
    local elev = rom:get(base + 4)
    local var = rom:u16(base + 6)
    local value = rom:u16(base + 8)
    local scriptPtr = rom:u32(base + 12)
    local row = {
      x = x, y = y, elevation = elev,
      var = var, value = value,
      scriptPtr = scriptPtr,
    }
    if scriptPtr ~= 0 and gba_off(rom, scriptPtr) then
      row.scriptKey = Opcodes.key(scriptPtr)
    end
    coords[#coords + 1] = row
  end
  return coords
end

--- Parse mapScripts table → seeds + mapScripts summary for game3.
local function parse_map_scripts(rom, scriptsPtr)
  local off = gba_off(rom, scriptsPtr)
  if not off then
    return { onTransition = nil, onResume = {}, onFrame = {} }, {}
  end
  local seeds = {}
  local mapScripts = {
    onTransition = nil,
    onResume = {},
    onFrame = {},
  }
  local i = off
  local guard = 0
  while guard < 32 do
    guard = guard + 1
    local typ = rom:get(i)
    if typ == 0 then break end
    local ptr = rom:u32(i + 1)
    i = i + 5
    local poff = gba_off(rom, ptr)
    if not poff then goto continue end
    if typ == MAP_SCRIPT_ON_TRANSITION or typ == MAP_SCRIPT_ON_LOAD
        or typ == MAP_SCRIPT_ON_RESUME or typ == MAP_SCRIPT_ON_RETURN_TO_FIELD then
      local key = Opcodes.key(ptr)
      seeds[#seeds + 1] = ptr
      if typ == MAP_SCRIPT_ON_TRANSITION then
        mapScripts.onTransition = key
      elseif typ == MAP_SCRIPT_ON_RESUME then
        mapScripts.onResume[#mapScripts.onResume + 1] = key
      end
    elseif typ == MAP_SCRIPT_ON_FRAME_TABLE
        or typ == MAP_SCRIPT_ON_WARP_INTO_MAP_TABLE
        or typ == MAP_SCRIPT_ON_DIVER_WARP_TABLE then
      -- Table of { u16 var, u16 value, script* } terminated by var==0.
      local t = poff
      for _ = 1, 32 do
        local var = rom:u16(t)
        if var == 0 then break end
        local value = rom:u16(t + 2)
        local sp = rom:u32(t + 4)
        t = t + 8
        if gba_off(rom, sp) then
          local key = Opcodes.key(sp)
          seeds[#seeds + 1] = sp
          if typ == MAP_SCRIPT_ON_FRAME_TABLE then
            mapScripts.onFrame[#mapScripts.onFrame + 1] = {
              var = var, value = value, script = key,
            }
          end
        end
      end
    end
    ::continue::
  end
  return mapScripts, seeds
end

function ExtractMapEvents.parseHeader(rom, headerOff)
  local layout = rom:u32(headerOff)
  local events = rom:u32(headerOff + 4)
  local scripts = rom:u32(headerOff + 8)
  local connections = rom:u32(headerOff + 12)
  local music = rom:u16(headerOff + 16)
  local layoutId = rom:u16(headerOff + 18)
  return {
    layout = layout,
    events = events,
    scripts = scripts,
    connections = connections,
    music = music,
    layoutId = layoutId,
  }
end

local function s16(rom, offset)
  local v = rom:u16(offset)
  if v >= 0x8000 then return v - 0x10000 end
  return v
end

-- pret CONNECTION_SOUTH/NORTH/WEST/EAST = 1..4
local CONN_DIR = {
  [1] = "south",
  [2] = "north",
  [3] = "west",
  [4] = "east",
}

local function parse_warps(rom, ptr, count)
  local off = gba_off(rom, ptr)
  if not off or not count or count < 1 then return {} end
  local out = {}
  for i = 0, count - 1 do
    local base = off + i * WARP_SIZE
    local x = s16(rom, base)
    local y = s16(rom, base + 2)
    local warpId = rom:get(base + 5)
    local mapNum = rom:get(base + 6)
    local mapGroup = rom:get(base + 7)
    -- Keep ROM order so destWarp indices from other maps stay valid.
    out[#out + 1] = {
      x = x,
      y = y,
      destMap = Versions.frMapFor(mapGroup, mapNum),
      destWarp = (tonumber(warpId) or 0) + 1,
      mapGroup = mapGroup,
      mapNum = mapNum,
    }
  end
  return out
end

function ExtractMapEvents.parseMapEvents(rom, eventsPtr)
  local off = gba_off(rom, eventsPtr)
  if not off then return nil end
  local objN = rom:get(off)
  local warpN = rom:get(off + 1)
  local coordN = rom:get(off + 2)
  local bgN = rom:get(off + 3)
  local objP = rom:u32(off + 4)
  local warpP = rom:u32(off + 8)
  local coordP = rom:u32(off + 12)
  local bgP = rom:u32(off + 16)
  return {
    objects = parse_objects(rom, objP, objN),
    bgEvents = parse_bg_events(rom, bgP, bgN),
    coordEvents = parse_coord_events(rom, coordP, coordN),
    warps = parse_warps(rom, warpP, warpN),
    warpCount = warpN,
    objectCount = objN,
    bgCount = bgN,
    coordCount = coordN,
  }
end

function ExtractMapEvents.parseConnections(rom, connectionsPtr)
  local off = gba_off(rom, connectionsPtr)
  if not off then return {} end
  -- struct MapConnections { s32 count; MapConnection *connections; }
  local count = rom:u32(off)
  -- interpret as signed
  if count >= 0x80000000 then count = 0 end
  if count > 8 then count = 0 end -- sanity
  local listPtr = rom:u32(off + 4)
  local listOff = gba_off(rom, listPtr)
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
    local destMap = Versions.frMapFor(mapGroup, mapNum)
    if dirName and destMap then
      out[dirName] = { map = destMap, offset = offset }
    end
  end
  return out
end

--- ROM warps + connections for every map in MAP_HEADERS.
-- @return warpsByMapId, connectionsByMapId
function ExtractMapEvents.extractWarpsAndConnections(rom, version)
  version = version or Versions.lookup(rom.md5)
  local headers = (version and version.map_headers) or Versions.MAP_HEADERS
  local warps, connections = {}, {}
  for mapId, headerOff in pairs(headers) do
    local hdr = ExtractMapEvents.parseHeader(rom, headerOff)
    local ev = ExtractMapEvents.parseMapEvents(rom, hdr.events)
    warps[mapId] = (ev and ev.warps) or {}
    connections[mapId] = ExtractMapEvents.parseConnections(rom, hdr.connections) or {}
  end
  return warps, connections
end

--- Extract all Island 1 maps listed in Versions.MAP_HEADERS.
-- @return eventsByMapId, scriptSeedPtrs (list of GBA pointers)
function ExtractMapEvents.extractIsland1(rom, version)
  version = version or Versions.lookup(rom.md5)
  local headers = (version and version.map_headers) or Versions.MAP_HEADERS
  local events = {}
  local seeds = {}
  local seen = {}
  local function add_seed(ptr)
    if not ptr or ptr == 0 then return end
    if seen[ptr] then return end
    if not gba_off(rom, ptr) then return end
    seen[ptr] = true
    seeds[#seeds + 1] = ptr
  end

  for mapId, headerOff in pairs(headers) do
    local hdr = ExtractMapEvents.parseHeader(rom, headerOff)
    local ev = ExtractMapEvents.parseMapEvents(rom, hdr.events)
    if not ev then
      events[mapId] = {
        objects = {}, bgEvents = {}, coordEvents = {},
        mapScripts = { onTransition = nil, onResume = {}, onFrame = {} },
        music = hdr.music,
      }
    else
      local mapScripts, scriptSeeds = parse_map_scripts(rom, hdr.scripts)
      for _, o in ipairs(ev.objects) do
        if o.scriptPtr and o.scriptPtr ~= 0 then add_seed(o.scriptPtr) end
      end
      for _, b in ipairs(ev.bgEvents) do
        if b.scriptKey and b.scriptPtr then add_seed(b.scriptPtr) end
      end
      for _, c in ipairs(ev.coordEvents) do
        if c.scriptPtr then add_seed(c.scriptPtr) end
      end
      for _, sp in ipairs(scriptSeeds) do add_seed(sp) end
      events[mapId] = {
        objects = ev.objects,
        bgEvents = ev.bgEvents,
        coordEvents = ev.coordEvents,
        mapScripts = mapScripts,
        headerOff = headerOff,
        music = hdr.music,
      }
    end
  end
  return events, seeds
end

return ExtractMapEvents
