#!/usr/bin/env luajit
-- pokefirered/src/heal_location.c:62, pokefirered/src/region_map.c:4023

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local okHL, HealLocationsExtract = pcall(require, "src.import.gba.heal_locations_extract")
if not okHL then
  HealLocationsExtract = {
    FILES = {},
    RESPAWN_TILE = {},
    build = function() return nil, "module missing" end,
  }
end
local Versions = require("src.import.gba.versions")
local CacheContract = require("src.import.CacheContract")
local MapCatalog = require("src.import.gba.map_catalog")
local MapSections = require("src.import.gba.map_sections_extract")

local HEAL_REL = "region_map/heal_locations.lua"
local FLY_REL = "region_map/fly_destinations.lua"

print("[test] 1. the baked heal-location contract")

check(okHL, "src/import/gba/heal_locations_extract.lua is loadable")
eq(Versions.S_HEAL_LOCATIONS, 0x3EEBF8, "sHealLocations is pinned")
eq(Versions.S_WHITEOUT_RESPAWN_MAP_IDXS, 0x3EEC98, "sWhiteoutRespawnHealCenterMapIdxs is pinned")
eq(Versions.S_WHITEOUT_RESPAWN_HEALER_NPC_IDS, 0x3EECE8, "sWhiteoutRespawnHealerNpcIds is pinned")
eq(Versions.S_MAP_FLY_DESTINATIONS, 0x3F2EE0, "sMapFlyDestinations is pinned")
eq(Versions.NUM_HEAL_LOCATIONS, 20, "NUM_HEAL_LOCATIONS - 1 rows")
eq(Versions.NUM_MAP_FLY_DESTINATIONS, 108, "sMapFlyDestinations row count")

do
  local required = CacheContract.requiredFiles("firered")
  local want = {
    ["data/generated/gba/" .. HEAL_REL] = false,
    ["data/generated/gba/" .. FLY_REL] = false,
  }
  for _, path in ipairs(required) do
    if want[path] ~= nil then want[path] = true end
  end
  for path, seen in pairs(want) do
    check(seen, "firered required list carries " .. path)
  end
end

print("[test] 2. the ROM read against pret")

local PRET = "../pokefirered"
local romFile = io.open(PRET .. "/pokefirered.gba", "rb")
local healSrc = slurp(PRET .. "/src/data/heal_locations.h")
local healEnum = slurp(PRET .. "/include/constants/heal_locations.h")
local mapGroupsSrc = slurp(PRET .. "/include/constants/map_groups.h")
local localIdSrc = slurp(PRET .. "/include/constants/map_event_ids.h")
local regionSrc = slurp(PRET .. "/src/region_map.c")
local mapsecSrc = slurp(PRET .. "/include/constants/region_map_sections.h")

local plan
if not okHL then
  check(false, "HealLocationsExtract.build reads the three heal tables")
elseif not (romFile and healSrc and healEnum and mapGroupsSrc and localIdSrc
  and regionSrc and mapsecSrc) then
  if romFile then romFile:close() end
  print("[skip] " .. PRET .. " sources or ROM not present; ROM section skipped")
else
  romFile:close()
  local FileIO = require("src.import.gba.file_io")
  local imports = FileIO.makeImports(
    PRET .. "/pokefirered.gba", "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc", "firered")
  local rom = assert(require("src.import.gba.rom").open(imports, "firered"))
  MapCatalog.rebuildIndex()

  local err
  plan, err = HealLocationsExtract.build(rom)
  check(plan ~= nil, "build over the real ROM: " .. tostring(err or "ok"))

  -- pokefirered/include/constants/map_groups.h:203
  local mapConst = {}
  for name, num, group in mapGroupsSrc:gmatch("#define%s+(MAP_[%w_]+)%s+%((%d+)%s*|%s*%((%d+)%s*<<%s*8%)%)") do
    mapConst[name] = { group = tonumber(group), num = tonumber(num) }
  end
  local localId = {}
  for name, value in localIdSrc:gmatch("#define%s+(LOCALID_[%w_]+)%s+(%d+)") do
    localId[name] = tonumber(value)
  end

  local healIndex, healOrder = {}, {}
  do
    local body = healEnum:match("enum%s*{(.-)}")
    local i = 0
    for name in (body or ""):gmatch("(HEAL_LOCATION_[%w_]+)") do
      healIndex[name] = i
      if i > 0 then healOrder[i] = name end
      i = i + 1
    end
  end
  eq(#healOrder, 20, "pret declares 20 heal locations")

  local mapsecIndex = {}
  do
    local body = mapsecSrc:match("enum%s*{(.-)}")
    local i = 0
    for name in (body or ""):gmatch("(MAPSEC_[%w_]+)") do
      mapsecIndex[name] = i
      i = i + 1
    end
  end
  eq(mapsecIndex.MAPSEC_PALLET_TOWN, MapSections.KANTO_MAPSEC_START,
    "KANTO_MAPSEC_START agrees with pret")

  local function section(src, symbol)
    local at = src:find(symbol, 1, true)
    if not at then return "" end
    local stop = src:find("\n};", at, true) or #src
    return src:sub(at, stop)
  end

  local pretFly, pretRespawn, pretNpc = {}, {}, {}
  for name, map, x, y in section(healSrc, "sHealLocations"):gmatch(
    "%[(HEAL_LOCATION_[%w_]+)%s*%-%s*1%]%s*=%s*{%s*%.mapGroup%s*=%s*MAP_GROUP%((MAP_[%w_]+)%),%s*" ..
    "%.mapNum%s*=%s*MAP_NUM%(MAP_[%w_]+%),%s*%.x%s*=%s*(%-?%d+),%s*%.y%s*=%s*(%-?%d+),") do
    pretFly[healIndex[name]] = { map = map, x = tonumber(x), y = tonumber(y) }
  end
  for name, map in section(healSrc, "sWhiteoutRespawnHealCenterMapIdxs"):gmatch(
    "%[(HEAL_LOCATION_[%w_]+)%s*%-%s*1%]%s*=%s*{%s*MAP_GROUP%((MAP_[%w_]+)%),%s*MAP_NUM%(MAP_[%w_]+%)%s*}") do
    pretRespawn[healIndex[name]] = map
  end
  for name, npc in section(healSrc, "sWhiteoutRespawnHealerNpcIds"):gmatch(
    "%[(HEAL_LOCATION_[%w_]+)%s*%-%s*1%]%s*=%s*(LOCALID_[%w_]+),") do
    pretNpc[healIndex[name]] = npc
  end
  eq(#pretFly, 20, "pret sHealLocations rows parsed")
  eq(#pretRespawn, 20, "pret sWhiteoutRespawnHealCenterMapIdxs rows parsed")
  eq(#pretNpc, 20, "pret sWhiteoutRespawnHealerNpcIds rows parsed")

  -- pokefirered/src/heal_location.c:89
  local PRET_TILE = {
    MAP_PALLET_TOWN_PLAYERS_HOUSE_1F = { x = 8, y = 5 },
    MAP_INDIGO_PLATEAU_POKEMON_CENTER_1F = { x = 13, y = 12 },
    MAP_ONE_ISLAND_POKEMON_CENTER_1F = { x = 5, y = 4 },
    MAP_TRAINER_TOWER_LOBBY = { x = 4, y = 11 },
  }

  local healMismatch, tileMismatch, npcMismatch = 0, 0, 0
  for id = 1, 20 do
    local row = plan and plan.heal[id]
    local wantMap = pretRespawn[id] and mapConst[pretRespawn[id]]
    local wantId = wantMap and MapCatalog.mapIdFor(wantMap.group, wantMap.num)
    if not (row and wantId and row.map == wantId) then healMismatch = healMismatch + 1 end
    local tile = PRET_TILE[pretRespawn[id]] or { x = 7, y = 4 }
    if not (row and row.x == tile.x and row.y == tile.y) then tileMismatch = tileMismatch + 1 end
    if not (row and row.healerLocalId == localId[pretNpc[id]]) then npcMismatch = npcMismatch + 1 end
  end
  eq(healMismatch, 0, "every respawn map matches pret")
  eq(tileMismatch, 0, "every respawn tile matches SetWhiteoutRespawnWarpAndHealerNpc")
  eq(npcMismatch, 0, "every healer localId matches pret")

  -- pokefirered/src/region_map.c:828
  local pretFlyRows = {}
  for sec, map, heal in section(regionSrc, "sMapFlyDestinations"):gmatch(
    "%[(MAPSEC_[%w_]+)%s*%-%s*KANTO_MAPSEC_START%]%s*=%s*{MAP%((MAP_[%w_]+)%),%s*(HEAL_LOCATION_[%w_]+)},") do
    if heal ~= "HEAL_LOCATION_NONE" then
      pretFlyRows[#pretFlyRows + 1] = { sec = sec, map = map, heal = healIndex[heal] }
    end
  end
  eq(#pretFlyRows, 20, "pret has 20 flyable mapsecs")
  eq(plan and #plan.fly or 0, #pretFlyRows, "the bake has the same count")

  local byName = {}
  for _, row in ipairs((plan and plan.fly) or {}) do byName[row.id] = row end
  local flyMismatch, coordMismatch, secMismatch = 0, 0, 0
  for _, want in ipairs(pretFlyRows) do
    local row = byName[want.sec]
    local c = mapConst[want.map]
    local wantId = c and MapCatalog.mapIdFor(c.group, c.num)
    if not (row and wantId and row.map == wantId) then flyMismatch = flyMismatch + 1 end
    local fly = pretFly[want.heal]
    if not (row and fly and row.x == fly.x and row.y == fly.y) then
      coordMismatch = coordMismatch + 1
    end
    if not (row and row.mapsec == mapsecIndex[want.sec]) then secMismatch = secMismatch + 1 end
  end
  eq(flyMismatch, 0, "every Fly destination map matches pret")
  eq(coordMismatch, 0, "every Fly tile comes from sHealLocations")
  eq(secMismatch, 0, "every mapsec number matches the pret enum")

  -- pokefirered/src/heal_location.c:89
  local pallet = plan and plan.heal[1]
  check(pallet and pallet.map == "FR_PLAYERS_HOUSE_1F" and pallet.x == 8 and pallet.y == 5
    and pallet.healerLocalId == 1, "HEAL_LOCATION_PALLET_TOWN is Mom at (8,5)")
  local indigo = plan and plan.heal[10]
  check(indigo and indigo.map == "FR_INDIGO_PLATEAU_POKEMON_CENTER_1F"
    and indigo.x == 13 and indigo.y == 12 and indigo.healerLocalId == 2,
    "HEAL_LOCATION_INDIGO_PLATEAU is the league nurse at (13,12)")
  local one = plan and plan.heal[14]
  check(one and one.map == "SEVII_ONE_ISLAND_POKECENTER" and one.x == 5 and one.y == 4,
    "HEAL_LOCATION_ONE_ISLAND respawns at (5,4)")
  local route4 = plan and plan.heal[12]
  check(route4 and route4.map == "FR_ROUTE_4_POKEMON_CENTER_1F",
    "HEAL_LOCATION_ROUTE4 respawns in a map the catalog knows")

  -- pokefirered/src/region_map.c:842
  check(byName.MAPSEC_ROUTE_1 == nil, "MAPSEC_ROUTE_1 is not a Fly destination")

  local healText = HealLocationsExtract.formatHealLocations(plan)
  local flyText = HealLocationsExtract.formatFlyDestinations(plan)
  local healPack = load(healText, "@heal", "t", {})
  local flyPack = load(flyText, "@fly", "t", {})
  check(healPack ~= nil and flyPack ~= nil, "both files are loadable Lua")
  local HealLocations = require("src.core.game3.heal_locations")
  local Field = require("src.core.game3.field")
  check(type(HealLocations.install) == "function"
    and type(Field.installFlyDestinations) == "function",
    "the engine reads both baked packs")
  if healPack and flyPack and type(HealLocations.install) == "function"
    and type(Field.installFlyDestinations) == "function" then
    eq(HealLocations.install(healPack()), 20, "the engine installs 20 respawn points")
    eq(Field.installFlyDestinations(flyPack()), 20, "the engine installs 20 Fly destinations")
    local viridian = HealLocations.get(2)
    check(viridian and viridian.map == "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"
      and viridian.x == 7 and viridian.y == 4,
      "HEAL_LOCATION_VIRIDIAN_CITY comes back off the baked pack")
    local pewter = Field.flyDestination("MAPSEC_PEWTER_CITY")
    check(pewter and pewter.map == "FR_PEWTER_CITY" and pewter.x == 17 and pewter.y == 26,
      "MAPSEC_PEWTER_CITY flies to (17,26)")
    local byNum = Field.flyDestination(mapsecIndex.MAPSEC_CELADON_CITY)
    check(byNum and byNum.map == "FR_CELADON_CITY" and byNum.x == 48 and byNum.y == 12,
      "a numeric mapsec resolves too")
    HealLocations.invalidate()
    Field.invalidateFlyDestinations()
  end
end

print("[test] 3. the files an imported cache carries")

local Cache = require("tests.game3_cache")
local root = Cache.root("meta.json")
if not root then
  print("[skip] " .. tostring(Cache.reason))
elseif not io.open(root .. "/" .. HEAL_REL, "rb") then
  print("[skip] " .. root .. " predates this bake; re-import to exercise section 3")
else
  local function loadBaked(rel)
    local src = slurp(root .. "/" .. rel)
    if not src then return nil end
    local chunk = load(src, "@" .. rel, "t", {})
    if not chunk then return nil end
    local ok, data = pcall(chunk)
    return ok and data or nil
  end
  local healPack = loadBaked(HEAL_REL)
  local flyPack = loadBaked(FLY_REL)
  check(healPack ~= nil, "the cache carries " .. HEAL_REL)
  check(flyPack ~= nil, "the cache carries " .. FLY_REL)

  local HealLocations = require("src.core.game3.heal_locations")
  local Field = require("src.core.game3.field")
  if type(HealLocations.install) == "function" then
    eq(HealLocations.install(healPack), 20, "the cache pack installs 20 respawn points")
  else
    check(false, "src/core/game3/heal_locations.lua reads a baked pack")
  end
  if type(Field.installFlyDestinations) == "function" then
    eq(Field.installFlyDestinations(flyPack), 20, "the cache pack installs 20 Fly destinations")
  else
    check(false, "src/core/game3/field.lua reads a baked pack")
  end

  local missing = {}
  local function haveMap(mapId)
    local f = io.open(root .. "/native/layouts/" .. tostring(mapId) .. ".mid", "rb")
    if f then f:close() return true end
    return false
  end
  for id = 1, 20 do
    local row = (healPack.whiteout or healPack.heal_locations or {})[id]
    if not (row and haveMap(row.map)) then
      missing[#missing + 1] = tostring(row and row.map or id)
    end
  end
  eq(#missing, 0, "every respawn map is in the cache" ..
    (#missing > 0 and (": " .. table.concat(missing, " ")) or ""))

  local flyMissing = {}
  for name, row in pairs(flyPack.fly_destinations or {}) do
    if not haveMap(row.map) then flyMissing[#flyMissing + 1] = name end
  end
  eq(#flyMissing, 0, "every Fly destination map is in the cache" ..
    (#flyMissing > 0 and (": " .. table.concat(flyMissing, " ")) or ""))

  if type(HealLocations.invalidate) == "function" then HealLocations.invalidate() end
  if type(Field.invalidateFlyDestinations) == "function" then
    Field.invalidateFlyDestinations()
  end
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
