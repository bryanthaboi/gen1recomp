-- Test suite for Game3 Pokédex Area & Where-to-Find extraction and rendering logic.

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local PokedexData = require("src.core.game3.pokedex_data")
assert(PokedexData.init(), "PokedexData should initialize successfully")

print("[test] 1. Dynamic wild area extraction for common Kanto species")
local pidgeyAreas = PokedexData.getWildAreasForSpecies(16)
assert(#pidgeyAreas > 0, "Pidgey (16) must have wild area locations")
local pidgeyHasRoute1 = false
for _, a in ipairs(pidgeyAreas) do
  if a == "DEX_AREA_ROUTE_1" then pidgeyHasRoute1 = true end
  assert(PokedexData.getAreaMarker(a) ~= nil, "Area marker for " .. a .. " must exist")
end
assert(pidgeyHasRoute1, "Pidgey must have DEX_AREA_ROUTE_1")

local rattataAreas = PokedexData.getWildAreasForSpecies(19)
assert(#rattataAreas > 0, "Rattata (19) must have wild area locations")
local rattataHasRoute22 = false
for _, a in ipairs(rattataAreas) do
  if a == "DEX_AREA_ROUTE_22" then rattataHasRoute22 = true end
  assert(PokedexData.getAreaMarker(a) ~= nil, "Area marker for " .. a .. " must exist")
end
assert(rattataHasRoute22, "Rattata must have DEX_AREA_ROUTE_22")

local pikachuAreas = PokedexData.getWildAreasForSpecies(25)
assert(#pikachuAreas >= 2, "Pikachu must have Viridian Forest and Power Plant")
local pikaViridian, pikaPower = false, false
for _, a in ipairs(pikachuAreas) do
  if a == "DEX_AREA_VIRIDIAN_FOREST" then pikaViridian = true end
  if a == "DEX_AREA_POWER_PLANT" then pikaPower = true end
end
assert(pikaViridian and pikaPower, "Pikachu must spawn in Viridian Forest and Power Plant")

local diglettAreas = PokedexData.getWildAreasForSpecies(50)
assert(#diglettAreas > 0, "Diglett (50) must have wild area locations")
assert(diglettAreas[1] == "DEX_AREA_DIGLETTS_CAVE", "Diglett must spawn in Diglett's Cave")

print("[test] 2. Sevii Island species wild area extraction and map assignment")
local dunsparceAreas = PokedexData.getWildAreasForSpecies(206)
assert(#dunsparceAreas > 0, "Dunsparce (206) must have wild area locations")
assert(dunsparceAreas[1] == "DEX_AREA_THREE_ISLE_PATH", "Dunsparce spawns in Three Isle Path")
assert(PokedexData.getAreaMapKey("DEX_AREA_THREE_ISLE_PATH") == "three_island", "Three Isle Path belongs to three_island")

local slugmaAreas = PokedexData.getWildAreasForSpecies(218)
assert(#slugmaAreas > 0, "Slugma (218) must have wild area locations")
assert(slugmaAreas[1] == "DEX_AREA_MT_EMBER", "Slugma spawns in Mt. Ember")
assert(PokedexData.getAreaMapKey("DEX_AREA_MT_EMBER") == "one_island", "Mt Ember belongs to one_island")

local phanpyAreas = PokedexData.getWildAreasForSpecies(231)
assert(#phanpyAreas > 0, "Phanpy (231) must have wild area locations")
assert(PokedexData.getAreaMapKey("DEX_AREA_SEVAULT_CANYON") == "seven_island", "Sevault Canyon belongs to seven_island")

print("[test] 3. Non-wild species return empty area table (Area Unknown)")
local bulbasaurAreas = PokedexData.getWildAreasForSpecies(1)
assert(#bulbasaurAreas == 0, "Starter Bulbasaur has no wild areas (Area Unknown)")

local mewtwoAreas = PokedexData.getWildAreasForSpecies(150)
assert(#mewtwoAreas == 0, "Mewtwo has no wild grass encounter table (Area Unknown)")

local deoxysAreas = PokedexData.getWildAreasForSpecies(386)
assert(#deoxysAreas == 0, "Deoxys has no wild grass encounter table (Area Unknown)")

print("[test] 4. All extracted markers have valid shape and coordinates")
local checkedCount = 0
for sp = 1, 386 do
  local areas = PokedexData.getWildAreasForSpecies(sp)
  for _, aKey in ipairs(areas) do
    local m = PokedexData.getAreaMarker(aKey)
    assert(m ~= nil, "Marker must exist for " .. aKey)
    assert(type(m.x) == "number" and type(m.y) == "number", "Coordinates must be numbers for " .. aKey)
    assert(type(m.shape) == "string", "Shape must be string for " .. aKey)
    local mapKey = PokedexData.getAreaMapKey(aKey)
    assert(type(mapKey) == "string", "Map key must be string for " .. aKey)
    checkedCount = checkedCount + 1
  end
end
assert(checkedCount > 100, "Should have verified > 100 area marker references")
print(string.format("OK: Verified %d area marker references across all species", checkedCount))

print("[ALL TESTS PASSED] Pokédex Area & Where-to-Find extraction is 100% verified.")
