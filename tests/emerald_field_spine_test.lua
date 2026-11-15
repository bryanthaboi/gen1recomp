package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
if not cache:read("data/generated/gba/native/manifest.lua") or not cache:read("data/generated/gba/scripts/labels.lua") then
  print("emerald_field_spine_test: skipped (no Emerald cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d") .. ")")
  os.exit(0)
end

Dataset.mountExtractRoots()
local maps = Dataset.buildMaps()
Dataset.attachMidLayouts(maps, cache)
local n = 0
for _ in pairs(maps) do n = n + 1 end
check(n >= 518, "every Emerald map has a def (" .. n .. ")")

local town, route, house = maps.EM_LITTLEROOT_TOWN, maps.EM_ROUTE101, maps.EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F
check(town and town.midLayout, "Littleroot has a native layout")
eq(town and town.kind, "town", "Littleroot is a town")
eq(route and route.kind, "route", "Route 101 is a route")
eq(house and house.kind, "indoor", "Brendan's house is indoor")
eq(town and town.bikingAllowed, 1, "Littleroot allows cycling")
eq(house and #house.warps, 3, "Brendan's house 1F has its two door mats and the stairs")

local function connTo(def, dir)
  for _, c in ipairs(require("src.core.game3.connections").each(def)) do
    if c.dir == dir then return c.map end
  end
end
eq(connTo(town, "north"), "EM_ROUTE101", "Littleroot north connects to Route 101")
eq(connTo(route, "south"), "EM_LITTLEROOT_TOWN", "Route 101 south connects to Littleroot")
eq(connTo(route, "north"), "EM_OLDALE_TOWN", "Route 101 north connects to Oldale")
eq(maps.EM_ROUTE124 and maps.EM_ROUTE124.dive and maps.EM_ROUTE124.dive.map, "EM_UNDERWATER_ROUTE124",
  "Route 124 dive row is def.dive")
eq(maps.EM_UNDERWATER_ROUTE124 and maps.EM_UNDERWATER_ROUTE124.emerge and maps.EM_UNDERWATER_ROUTE124.emerge.map,
  "EM_ROUTE124", "Underwater Route 124 emerge row is def.emerge")

local Space = require("src.core.game3.scripting.space")
Space.bundle = nil
local bundle = Space.ensureBundle(nil)
check(bundle and bundle.labels, "labels.lua loaded into the bundle")
local rescue = Space.scriptKey("Route101_EventScript_StartBirchRescue")
check(rescue and bundle.scripts[rescue], "Route101_EventScript_StartBirchRescue resolves through labels.lua")
check(bundle.scripts.EventScript_BookShelf ~= nil or Space.scriptKey("EventScript_BookShelf") ~= nil,
  "EventScript_BookShelf is reachable by name")

local I = require("src.core.game3.scripting.interaction_scripts")
check(I.interactions ~= nil, "objects pack installed RSE interaction rows")
local MB = require("src.core.game3.mb")
local key = I.scriptFor(MB.require("BOOKSHELF"), "up", true)
eq(key, Space.scriptKey("EventScript_BookShelf"), "facing a bookshelf runs EventScript_BookShelf")
check(require("src.core.game3.scripting.collision_rse")._tileBits ~= nil, "tile bits installed")

local found
for id, def in pairs(maps) do
  local L = def.midLayout
  local behaviors = L and I.behaviors[def.pair]
  if behaviors and not found then
    for y = 0, L.height - 1 do
      for x = 0, L.width - 1 do
        if behaviors[L:midAt(x, y)] == MB.require("BOOKSHELF") then found = found or (id .. " " .. x .. "," .. y) end
      end
    end
  end
end
check(found ~= nil, "some Emerald map has a bookshelf cell (" .. tostring(found) .. ")")

local HealLocations = require("src.core.game3.heal_locations")
HealLocations.invalidate()
eq(HealLocations.model(), "heal_row", "Emerald heal pack is the heal row model")
local home = HealLocations.get(1)
eq(home and home.map, "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", "HEAL_LOCATION 1 is Brendan's 2F")
eq(home and home.healerLocalId, nil, "no healer npc")
eq(HealLocations.get(23), nil, "no row past the 22 Emerald heal locations")

local Trainers = require("src.core.game3.scripting.trainers")
Trainers._pack = nil
local t1 = Trainers.get(1)
check(t1 and t1.dialogs and type(t1.dialogs.intro) == "string" and #t1.dialogs.intro > 0,
  "trainer 1 intro text comes from trainers/dialogs.lua")

local TilesetAnim = require("src.core.game3.tileset_anim")
TilesetAnim.install(cache)
check(TilesetAnim.enterMap(town.pair, false), "Littleroot pair has an RSE anim manifest")
eq(TilesetAnim._rse.primaryMax, 256, "InitTilesetAnim_General max 256")

T.finish()
