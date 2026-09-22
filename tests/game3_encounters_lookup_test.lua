#!/usr/bin/env luajit
-- Test wild encounter table resolution and rolls across multiple map ID alias formats.

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_encounters_lookup_test")

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

local Encounters = require("src.core.game3.encounters")
local MapCatalog = require("src.import.gba.map_catalog")
local Rng = require("src.core.game3.rng")

MapCatalog.rebuildIndex()
Encounters.loadFromMod(nil)
check(Encounters.ensureLoaded(), "Encounters tables loaded successfully")

print("\n--- Test 1: Route 22 multi-alias resolution ---")
local r22_keys = { "ROUTE_22", "FR_ROUTE_22", "ROUTE22", "FR_ROUTE22", "3:41" }
for _, k in ipairs(r22_keys) do
  local t = Encounters.tableFor(k)
  check(t ~= nil, "tableFor succeeds for Route 22 alias: " .. k)
  if t then
    check(t.land ~= nil and #t.land.slots == 12, "Route 22 has 12 land slots")
    check(t.water ~= nil and #t.water.slots == 5, "Route 22 has 5 water slots")
    check(t.fishing ~= nil and #t.fishing.slots == 10, "Route 22 has 10 fish slots")
    -- Verify Rattata (19), Mankey (56), Spearow (21)
    local speciesSet = {}
    for _, s in ipairs(t.land.slots) do speciesSet[s.species] = true end
    check(speciesSet[19] and speciesSet[56] and speciesSet[21], "Route 22 contains Rattata, Mankey, and Spearow")
  end
end

print("\n--- Test 2: Route 2 multi-alias resolution ---")
local r2_keys = { "ROUTE_2", "FR_ROUTE_2", "ROUTE2", "FR_ROUTE2", "3:20" }
for _, k in ipairs(r2_keys) do
  local t = Encounters.tableFor(k)
  check(t ~= nil, "tableFor succeeds for Route 2 alias: " .. k)
  if t then
    check(t.land ~= nil and #t.land.slots == 12, "Route 2 has 12 land slots")
    local speciesSet = {}
    for _, s in ipairs(t.land.slots) do speciesSet[s.species] = true end
    check(speciesSet[19] and speciesSet[16] and speciesSet[10] and speciesSet[13],
      "Route 2 contains Rattata (19), Pidgey (16), Caterpie (10), Weedle (13)")
  end
end

print("\n--- Test 3: Route 3, 4, 11, 24 multi-alias resolution ---")
local other_routes = { "ROUTE_3", "ROUTE_4", "ROUTE_11", "ROUTE_24" }
for _, k in ipairs(other_routes) do
  local t = Encounters.tableFor(k)
  check(t ~= nil and t.land ~= nil, "tableFor succeeds for: " .. k)
end

print("\n--- Test 4: Viridian Forest & Diglett's Cave ---")
local vf = Encounters.tableFor("FR_VIRIDIAN_FOREST") or Encounters.tableFor("VIRIDIAN_FOREST")
check(vf ~= nil and vf.land ~= nil, "tableFor succeeds for Viridian Forest")
if vf and vf.land then
  local speciesSet = {}
  for _, s in ipairs(vf.land.slots) do speciesSet[s.species] = true end
  -- Caterpie (10), Weedle (13), Metapod (11), Kakuna (14), Pikachu (25)
  check(speciesSet[10] and speciesSet[13] and speciesSet[25], "Viridian Forest contains Caterpie, Weedle, Pikachu")
end

local dc = Encounters.tableFor("FR_DIGLETTS_CAVE_B1F") or Encounters.tableFor("DIGLETTS_CAVE_B1F")
check(dc ~= nil and dc.land ~= nil, "tableFor succeeds for Digletts Cave B1F")
if dc and dc.land then
  local speciesSet = {}
  for _, s in ipairs(dc.land.slots) do speciesSet[s.species] = true end
  check(speciesSet[50] and speciesSet[51], "Digletts Cave contains Diglett (50) and Dugtrio (51)")
end

print("\n--- Test 5: Step Encounter Generation ---")
local count = 0
for step = 1, 100 do
  local r = Encounters.rollLand("ROUTE_22", 100, false)
  if r then
    count = count + 1
    check(r.species == 19 or r.species == 56 or r.species == 21,
      string.format("Step %d rolled valid Route 22 mon: %d lv %d", step, r.species, r.level))
  end
end
check(count > 0, string.format("Route 22 generated %d encounters in 100 steps", count))

if failed > 0 then
  print(string.format("\nFAILED: %d errors", failed))
  os.exit(1)
else
  print("\nALL TESTS PASSED")
end
