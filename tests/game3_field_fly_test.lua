#!/usr/bin/env luajit
-- pokefirered/src/region_map.c:828 sMapFlyDestinations
-- pokefirered/src/region_map.c:4022 SetFlyWarpDestination

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Field = require("src.core.game3.field")
local FieldMoves = require("src.core.game3.field_moves")

-- pokefirered/src/region_map.c:829
local FLYABLE = {
  "MAPSEC_PALLET_TOWN", "MAPSEC_VIRIDIAN_CITY", "MAPSEC_PEWTER_CITY",
  "MAPSEC_CERULEAN_CITY", "MAPSEC_LAVENDER_TOWN", "MAPSEC_VERMILION_CITY",
  "MAPSEC_CELADON_CITY", "MAPSEC_FUCHSIA_CITY", "MAPSEC_CINNABAR_ISLAND",
  "MAPSEC_INDIGO_PLATEAU", "MAPSEC_SAFFRON_CITY", "MAPSEC_ROUTE_4_POKECENTER",
  "MAPSEC_ROUTE_10_POKECENTER", "MAPSEC_ONE_ISLAND", "MAPSEC_TWO_ISLAND",
  "MAPSEC_THREE_ISLAND", "MAPSEC_FOUR_ISLAND", "MAPSEC_FIVE_ISLAND",
  "MAPSEC_SIX_ISLAND", "MAPSEC_SEVEN_ISLAND",
}

print("[test] 1. the fly table is the twenty heal locations")
local n = 0
for _ in pairs(Field.FLY_DESTINATIONS) do n = n + 1 end
check(n == 20, "twenty fly destinations (" .. n .. ")")
for _, sec in ipairs(FLYABLE) do
  local d = Field.flyDestination(sec)
  check(d ~= nil and type(d.map) == "string" and d.x ~= nil and d.y ~= nil,
    sec .. " has a destination")
end
check(Field.flyDestination("MAPSEC_ROUTE_1") == nil, "a plain route is not flyable")
check(Field.flyDestination(nil) == nil, "nil is not flyable")
-- pokefirered/src/region_map.c:4023
local MapSections = require("src.import.gba.map_sections_extract")
local viridianId = MapSections.ID_TO_SECTION["MAPSEC_VIRIDIAN_CITY"]
check(tonumber(viridianId) ~= nil, "MAPSEC_VIRIDIAN_CITY has a numeric id")
check(Field.flyDestination(viridianId) == Field.flyDestination("MAPSEC_VIRIDIAN_CITY"),
  "the numeric mapsec resolves to the same destination")
check(Field.flyDestination(999) == nil, "an unknown numeric mapsec is not flyable")
local pallet = Field.flyDestination("MAPSEC_PALLET_TOWN")
check(pallet.map == "FR_PALLET_TOWN" and pallet.x == 6 and pallet.y == 8,
  "Pallet Town lands outside the house at (6,8)")
local indigo = Field.flyDestination("MAPSEC_INDIGO_PLATEAU")
check(indigo.map == "FR_INDIGO_PLATEAU_EXTERIOR" and indigo.x == 11 and indigo.y == 7,
  "Indigo Plateau lands on the exterior at (11,7)")

print("[test] 2. the menu arm")
local outdoors = { mapType = FieldMoves.MAP_TYPES.CITY, party = {}, store = { flags = {} } }
outdoors.store.flags[FieldMoves.BADGE_FLAGS.FLY] = true
local res = FieldMoves.fromMenu("FLY", outdoors)
check(res.ok == true and res.action == "fly", "Fly outdoors returns action fly")
local indoors = { mapType = FieldMoves.MAP_TYPES.INDOOR, party = {}, store = outdoors.store }
check(FieldMoves.fromMenu("FLY", indoors).ok == false, "Fly indoors is refused")
local noBadge = { mapType = FieldMoves.MAP_TYPES.CITY, party = {}, store = { flags = {} } }
check(FieldMoves.fromMenu("FLY", noBadge).ok == false, "Fly without the THUNDERBADGE is refused")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_field_fly_test (cache-backed sections): " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local Runtime = require("src.core.game3.runtime")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = nil, flags = {}, vars = {}, party = {}, name = "RED" }
game.session = session
Runtime.session = session
Field._game = game
Field._session = session
Field.running = true

print("[test] 3. every destination is a real cell you can stand on")
for _, sec in ipairs(FLYABLE) do
  local d = Field.flyDestination(sec)
  local def = game.data.maps[d.map]
  check(def ~= nil, d.map .. " is in the cache")
  if def then
    Collision.bindMap(game, d.map, def)
    check(Collision.isWalkable(d.x, d.y) == true,
      string.format("%s (%d,%d) is walkable", d.map, d.x, d.y))
  end
end

print("[test] 4. flying moves the player")
local dest = Field.flyDestination("MAPSEC_PEWTER_CITY")
session.map = "FR_PALLET_TOWN"
Collision.bindMap(game, "FR_PALLET_TOWN", game.data.maps["FR_PALLET_TOWN"])
Player.cellX, Player.cellY = 6, 8
check(Field.flyTo("MAPSEC_NOWHERE") == false, "an unknown section refuses")
check(Player.cellX == 6 and Player.cellY == 8, "and does not move the player")
check(Field.flyTo("MAPSEC_PEWTER_CITY") == true, "flying to Pewter City is accepted")
check(Player.cellX == dest.x and Player.cellY == dest.y,
  string.format("the player stands at (%d,%d), got (%d,%d)",
    dest.x, dest.y, Player.cellX, Player.cellY))
check(session.map == dest.map, "on " .. dest.map .. " (" .. tostring(session.map) .. ")")

finish()
