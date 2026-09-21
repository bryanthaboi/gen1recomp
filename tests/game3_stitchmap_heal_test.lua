#!/usr/bin/env luajit
-- pokefirered/src/heal_location.c:62 SetWhiteoutRespawnWarpAndHealerNpc

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

local Cache = require("tests.game3_cache")
local CACHE_ROOT = Cache.mountOrSkip("stitchmap heal locations", "map_tree/census.json")

local Dataset = require("src.core.game3.dataset")
local MapCatalog = require("src.import.gba.map_catalog")
local HealLocations = require("src.core.game3.heal_locations")

-- pokefirered/src/heal_location.c:65
local PRET = {
  [1] = { pret = "PalletTown_PlayersHouse_1F", x = 8, y = 5, healer = 1 },
  [2] = { pret = "ViridianCity_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [3] = { pret = "PewterCity_PokemonCenter_1F", x = 7, y = 4, healer = 3 },
  [4] = { pret = "CeruleanCity_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [5] = { pret = "LavenderTown_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [6] = { pret = "VermilionCity_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [7] = { pret = "CeladonCity_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [8] = { pret = "FuchsiaCity_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [9] = { pret = "CinnabarIsland_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [10] = { pret = "IndigoPlateau_PokemonCenter_1F", x = 13, y = 12, healer = 2 },
  [11] = { pret = "SaffronCity_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [12] = { pret = "Route4_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [13] = { pret = "Route10_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [14] = { pret = "OneIsland_PokemonCenter_1F", x = 5, y = 4, healer = 1 },
  [15] = { pret = "TwoIsland_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [16] = { pret = "ThreeIsland_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [17] = { pret = "FourIsland_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [18] = { pret = "FiveIsland_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [19] = { pret = "SevenIsland_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
  [20] = { pret = "SixIsland_PokemonCenter_1F", x = 7, y = 4, healer = 1 },
}
local LAST_ID = 20

print("[test] 1. every heal destination is a map the cache actually has")
local maps = Dataset.buildMaps()
local missing = 0
for id = 1, LAST_ID do
  local loc = HealLocations.get(id)
  if type(loc) ~= "table" or type(loc.map) ~= "string" then
    missing = missing + 1
    check(false, "heal location " .. id .. " has no row")
  elseif maps[loc.map] == nil then
    missing = missing + 1
    check(false, "heal location " .. id .. " loads " .. loc.map .. ", which the cache has no def for")
  end
end
eq(missing, 0, "heal destinations that do not exist in the cache")
eq(HealLocations.get(0), nil, "HEAL_LOCATION_NONE has no row")
eq(HealLocations.get(LAST_ID + 1), nil, "an out-of-range heal location has no row")

print("[test] 2. the rows are pret's whiteout warp, tile and healer")
for id = 1, LAST_ID do
  local want = PRET[id]
  local wantMap = MapCatalog.pretToEngine(want.pret)
  local loc = HealLocations.get(id) or {}
  eq(loc.map, wantMap, "heal location " .. id .. " map (" .. want.pret .. ")")
  eq(loc.x, want.x, "heal location " .. id .. " x")
  eq(loc.y, want.y, "heal location " .. id .. " y")
  eq(loc.healerLocalId, want.healer, "heal location " .. id .. " healer localId")
end

print("[test] 3. setrespawn stamps the session the whiteout reads")
local session = { healMap = "FR_PLAYERS_HOUSE_2F" }
HealLocations.normalizeSession(session)
eq(session.healMap, "FR_PLAYERS_HOUSE_1F", "the bedroom default migrates to Mom's floor")
eq(session.healX, 8, "migrated heal x")
eq(session.healY, 5, "migrated heal y")
check(HealLocations.applyToSession(session, 12), "setrespawn HEAL_LOCATION_ROUTE4 applies")
eq(session.healMap, MapCatalog.pretToEngine("Route4_PokemonCenter_1F"), "session heal map after setrespawn")
eq(session.healX, 7, "session heal x after setrespawn")
eq(session.healY, 4, "session heal y after setrespawn")
check(maps[session.healMap] ~= nil, "the whiteout map loader has a def for the session heal map")

print("[test] 4. the baked importer table wins, missing rows fall back to source")
if type(HealLocations.load) ~= "function" then
  check(false, "HealLocations.load reads the baked region_map/heal_locations.lua")
else
  local FIXTURE_ROOT = "tests/fixtures/stitchmap_heal"
  local function cacheOf(src)
    local files = src and { [FIXTURE_ROOT .. "/" .. HealLocations.BAKED_REL] = src } or {}
    return {
      read = function(_, rel) return files[rel] end,
      exists = function(_, rel) return files[rel] ~= nil end,
    }
  end

  local keyed = table.concat({
    "return { whiteout = {",
    "  [2] = { map = 'FR_VIRIDIAN_CITY_POKEMON_CENTER_1F', x = 7, y = 4, healerLocalId = 1 },",
    "  [12] = { map = 'FR_ROUTE_4_POKEMON_CENTER_1F', x = 7, y = 4, healerLocalId = 1 },",
    "} }",
  }, "\n")

  eq(HealLocations.load(cacheOf(keyed), FIXTURE_ROOT), 2, "baked rows installed from the cache")
  local two = HealLocations.get(2)
  check(two ~= HealLocations.BY_ID[2], "id 2 now comes from the baked table, not the source table")
  eq(two.map, "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", "baked id 2 map")
  eq(HealLocations.get(3), HealLocations.BY_ID[3], "an id the baked table omits falls back to source")
  eq(HealLocations.get(12).map, "FR_ROUTE_4_POKEMON_CENTER_1F", "baked id 12 map")

  local list = table.concat({
    "return { whiteout = {",
    "  { id = 12, map = 'FR_ROUTE_4_POKEMON_CENTER_1F', x = 7, y = 4, healerLocalId = 1 },",
    "  { id = 3, map = 'FR_PEWTER_CITY_POKEMON_CENTER_1F', x = 7, y = 4, healerLocalId = 3 },",
    "} }",
  }, "\n")
  eq(HealLocations.load(cacheOf(list), FIXTURE_ROOT), 2, "a list of rows carrying their own id installs")
  eq(HealLocations.get(12).map, "FR_ROUTE_4_POKEMON_CENTER_1F", "list row 1 is keyed by its id, not its position")
  eq(HealLocations.get(3).healerLocalId, 3, "list row 2 is keyed by its id, not its position")
  eq(HealLocations.get(1), HealLocations.BY_ID[1], "list position 1 does not overwrite HEAL_LOCATION_PALLET_TOWN")

  -- pokefirered/src/data/heal_locations.h:6 sHealLocations
  local flyRows = table.concat({
    "return {",
    "  [1] = { map = 'FR_PALLET_TOWN', x = 6, y = 8 },",
    "  [2] = { map = 'FR_VIRIDIAN_CITY', x = 26, y = 27 },",
    "}",
  }, "\n")
  eq(HealLocations.load(cacheOf(flyRows), FIXTURE_ROOT), 0, "rows outside the whiteout key install nothing")
  eq(HealLocations.get(2), HealLocations.BY_ID[2], "the outdoor fly landing never replaces the whiteout center")
  local flyKeyed = table.concat({
    "return { fly = {",
    "  [2] = { map = 'FR_VIRIDIAN_CITY', x = 26, y = 27 },",
    "} }",
  }, "\n")
  eq(HealLocations.load(cacheOf(flyKeyed), FIXTURE_ROOT), 0, "a fly table beside the whiteout one is ignored here")
  eq(HealLocations.get(2), HealLocations.BY_ID[2], "id 2 still whiteouts to the center")

  eq(HealLocations.load(cacheOf(nil), FIXTURE_ROOT), 0, "a cache without the key installs nothing")
  eq(HealLocations.get(2), HealLocations.BY_ID[2], "with no baked table every id comes from source")
  eq(HealLocations.get(12).map, "FR_ROUTE_4_POKEMON_CENTER_1F", "the source table is the corrected one")
  HealLocations.invalidate()
end

print("[test] 5. the cache's own baked table, when it has one")
if type(HealLocations.load) == "function" then
  local diskCache = Cache.cache()
  if not diskCache:exists(CACHE_ROOT .. "/" .. HealLocations.BAKED_REL) then
    print("[skip] this cache predates the heal-location bake")
  else
    eq(HealLocations.load(diskCache, CACHE_ROOT), LAST_ID, "every baked row installs from the cache")
    for id = 1, LAST_ID do
      local want = PRET[id]
      local loc = HealLocations.get(id) or {}
      check(loc ~= HealLocations.BY_ID[id], "heal location " .. id .. " comes from the cache")
      eq(loc.map, MapCatalog.pretToEngine(want.pret), "baked heal location " .. id .. " map")
      eq(loc.x, want.x, "baked heal location " .. id .. " x")
      eq(loc.y, want.y, "baked heal location " .. id .. " y")
      eq(loc.healerLocalId, want.healer, "baked heal location " .. id .. " healer localId")
    end
  end
  HealLocations.invalidate()
end

if failed == 0 then
  print("ALL STITCHMAP HEAL TESTS PASSED")
  os.exit(0)
end
print(failed .. " CHECK(S) FAILED")
os.exit(1)
