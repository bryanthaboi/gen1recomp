-- Crystal world data: the roamer roster and swarm pairs that differ from
-- Gold, then the facts only a real Crystal cache can answer.
-- Self-contained: `luajit tests/crystal_world_test.lua`; also dofile'd by
-- tests/run_tests.lua.  The cache half SKIPs when no crystal cache is present.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("crystal world")
local check, eq = S.check, S.eq

local Permissions = require("src.world.gen2.Permissions")
local Roamers = require("src.core.gen2.Roamers")
local Swarm = Roamers.Swarm

-- ---------------------------------------------------------------- ROM-free

check(Permissions.isWalkable(0x00), "COLL_FLOOR walkable")
check(not Permissions.isWalkable(0x07), "COLL_WALL blocked")
-- pokecrystal/constants/collision_constants.asm:19
check(Permissions.isGrass(0x18), "COLL_TALL_GRASS is grass")
check(Permissions.isWater(0x29), "COLL_WATER is water")
check(Permissions.isWarpCollision(0x71), "COLL_DOOR is a warp")
check(Permissions.isLedge(0xa0), "COLL_HOP_DOWN is a ledge")
eq(Permissions.of(0xff), Permissions.WALL, "a missing coll reads as wall")

local bare = {}
Roamers.init(bare)
eq(#bare.roamers, 3, "no cache -> the three-beast Gold roster")
check(Roamers.SPECIES ~= nil and #Roamers.SPECIES == 3,
  "Roamers.SPECIES survives as the ROM-free fallback")

-- pokecrystal/constants/script_constants.asm:256-257
local pair = {}
Swarm.set(pair, "DARK_CAVE_VIOLET_ENTRANCE", 0)
Swarm.set(pair, "ROUTE_35", 1)
eq(pair.swarmMaps.DUNSPARCE, "DARK_CAVE_VIOLET_ENTRANCE", "SWARM_DUNSPARCE key")
eq(pair.swarmMaps.YANMA, "ROUTE_35", "SWARM_YANMA key, independently")
eq(Swarm.onMap(pair, "ROUTE_35"), "YANMA", "the Yanma map answers YANMA")
eq(Swarm.mapId(pair, "YANMA"), "ROUTE_35", "mapId takes a kind")
eq(Swarm.mapId(pair), "DARK_CAVE_VIOLET_ENTRANCE", "and defaults to Gold's key")
Swarm.timeEvents(pair, 100)
check(Swarm.timeEvents(pair, 101), "the next day ends the swarm")
eq(Swarm.onMap(pair, "ROUTE_35"), nil, "and both pairs are stranded")

local legacy = { swarmMap = "ROUTE_35", dailyFlags = { swarm = true } }
eq(Swarm.mapId(legacy), "ROUTE_35", "an old scalar save answers mapId")
eq(Swarm.onMap(legacy, "ROUTE_35"), "DUNSPARCE", "normalized onto the Gold key")
eq(Swarm.onMap(legacy, "ROUTE_36"), nil, "another map is not the swarm map")
check(Swarm.entry(legacy, { swarmGrass = { ROUTE_35 = { "row" } }, grass = {} },
  "ROUTE_35", "grass") ~= nil, "and its swarm table still resolves")

-- ------------------------------------------------------------ cache-gated

local cache = os.getenv("CRYSTAL_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/crystal-dev/crystal"
end

local mapsPath = cache .. "/data/generated/maps.lua"
local mapsFile = io.open(mapsPath, "r")
if not mapsFile then
  check(true, "crystal cache absent : SKIP")
  S.finish()
  return
end
mapsFile:close()

local function loadLua(rel)
  local chunk = loadfile(cache .. "/" .. rel)
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  return ok and value or nil
end

local maps = loadLua("data/generated/maps.lua")
local encounters = loadLua("data/generated/encounters.lua")
local tilesets = loadLua("data/generated/tilesets.lua")
local constants = loadLua("data/generated/constants.lua")

check(maps ~= nil, "maps.lua loads")
check(encounters ~= nil, "encounters.lua loads")
check(tilesets ~= nil, "tilesets.lua loads")
check(constants ~= nil, "constants.lua loads")

-- ---- 1. the maps Phase 1 has to reach

local count = 0
for _ in pairs(maps or {}) do count = count + 1 end
eq(count, 388, "the cache carries 388 maps")
for _, id in ipairs({
  "NEW_BARK_TOWN", "PLAYERS_HOUSE_1F", "PLAYERS_HOUSE_2F", "ELMS_LAB",
  "ROUTE_29", "CHERRYGROVE_CITY", "ROUTE_30", "ROUTE_31", "VIOLET_CITY",
  "SPROUT_TOWER_1F", "VIOLET_GYM",
}) do
  check(maps[id] ~= nil, "the New Bark to Violet route has " .. id)
end
check(maps.BATTLE_TOWER_1F ~= nil, "and the Crystal-only Battle Tower")
-- pokegold/constants/map_constants.asm:152
eq(maps.ECRUTEAK_TIN_TOWER_BACK_ENTRANCE, nil,
  "the one map Crystal drops is absent")

-- ---- 2. roamers (CT-4)

check(type(encounters.roamMons) == "table",
  "the cache emits encounters.roamMons")
eq(#encounters.roamMons, 2, "Crystal seeds two beasts, not three")
eq(encounters.roamMons[1].species, "RAIKOU", "slot 1 is Raikou")
eq(encounters.roamMons[1].map, "ROUTE_42", "on Route 42")
eq(encounters.roamMons[2].species, "ENTEI", "slot 2 is Entei")
eq(encounters.roamMons[2].map, "ROUTE_37", "on Route 37")
eq(encounters.roamMons[1].level, 40, "both start at level 40")
eq(encounters.roamMons[2].level, 40, "both start at level 40")

local save = {}
Roamers.init(save, { encounters = encounters })
eq(#save.roamers, 2, "Roamers.init over the cache builds two slots")
eq(save.roamers[1].species, "RAIKOU", "slot 1 Raikou")
eq(save.roamers[2].species, "ENTEI", "slot 2 Entei")
eq(save.roamers[3], nil, "and no Suicune slot")
eq(save.roamers[1].hp, 0, "hp is zeroed so stats regenerate on contact")

local data = {}
Roamers.init(data, { data = { gen2Encounters = encounters } })
eq(#data.roamers, 2, "the opts.data path resolves the same roster")

eq(Roamers.checkEncounter(save, "ROUTE_38", false, function() return 3 end), nil,
  "the Suicune slot roll finds nothing on a Crystal save")
local hit = Roamers.checkEncounter(save, "ROUTE_42", false, function() return 1 end)
check(hit and hit.species == "RAIKOU", "the Raikou roll still hits")

-- ---- 3. the swarm tables the kind byte indexes

check(encounters.swarmGrass ~= nil, "the cache carries swarmGrass")
check(encounters.swarmGrass.DARK_CAVE_VIOLET_ENTRANCE ~= nil,
  "with the Dunsparce table")
check(encounters.swarmGrass.ROUTE_35 ~= nil, "and the Yanma table")

-- ---- 4. the tileset palette-map bank
-- pokecrystal.sym 13:40e5 TilesetJohtoPalMap (pokegold.sym 02:40c7)
local johto = (tilesets or {}).TILESET_JOHTO
check(johto ~= nil, "TILESET_JOHTO is in the cache")
eq(johto and johto.palMap and johto.palMap.bank, 0x13,
  "TilesetJohtoPalMap is read out of bank $13")
eq(johto and johto.palMap and johto.palMap.address, 0x40e5,
  "at $40e5")
local kanto = (tilesets or {}).TILESET_KANTO
eq(kanto and kanto.palMap and kanto.palMap.bank, 0x13,
  "TilesetKantoPalMap is bank $13 too")
eq(kanto and kanto.palMap and kanto.palMap.address, 0x4075, "at $4075")
check(johto and johto.tilePalettes and #johto.tilePalettes > 0,
  "and the map decoded to a per-tile palette list")
check(johto and johto.tileAttrs ~= nil,
  "Crystal Johto carries per-tile GBC attrs")
if johto and johto.tileAttrs then
  check(johto.tileAttrs[0x80 + 1] ~= nil,
    "bank-1 tile $80 has attrs from the second PalMap section")
end

-- ---- 5. the special table the cache pins

eq(#(constants.specialOrder or {}), 169,
  "the cache's specialOrder has Crystal's 169 rows")

S.finish()
