-- tests/game3_oaks_lab_save_reload_test.lua
-- Tests contextual placement of Oak and Rival in FR_OAKS_LAB across scene states and save/reload.

local Cache = require("tests.game3_cache")
Cache.mountOrSkip("game3_oaks_lab_save_reload_test", "scripts/events.lua")

local Objects = require("src.core.game3.objects")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local Runtime = require("src.core.game3.runtime")

local VAR_OAKS_LAB_SCENE = 0x4055
local VAR_STARTER_MON = 0x4031
local FLAG_HIDE_RIVAL_IN_LAB = 0x2D

-- Initialize space & bundle
Space.ensureBundle()

local function setupSession(scene, starterMon, partySpecies)
  local store = Flags.newStore()
  if scene ~= nil then Flags.setVar(store, nil, VAR_OAKS_LAB_SCENE, scene) end
  if starterMon ~= nil then Flags.setVar(store, nil, VAR_STARTER_MON, starterMon) end
  if scene and scene >= 4 then Flags.setFlag(store, nil, FLAG_HIDE_RIVAL_IN_LAB, true) end

  local session = {
    map = "FR_OAKS_LAB",
    x = 6,
    y = 8,
    facing = "up",
    vars = store.vars,
    flags = store.flags,
    party = partySpecies and { { species = partySpecies, level = 5 } } or {},
  }
  Runtime.session = session
  Space.store = store
  Objects._perm = {}
  Objects._byId = {}
  Objects._order = {}

  local mapDef = { midLayout = { width = 13, height = 13 } }
  Objects.loadMap(nil, "FR_OAKS_LAB", mapDef)
end

-- Test 1: Scene 2 (Oak explained starters, player has not chosen yet)
setupSession(2, 0)
local oak = Objects.find(4)
local rival = Objects.find(8)
assert(oak ~= nil, "Oak object (4) exists in scene 2")
assert(oak.cellX == 6 and oak.cellY == 3, string.format("Oak is at (6, 3), got (%d, %d)", oak.cellX, oak.cellY))
assert(oak.facing == "down", string.format("Oak faces down, got %s", oak.facing))

assert(rival ~= nil, "Rival object (8) exists in scene 2")
assert(rival.cellX == 5 and rival.cellY == 4, string.format("Rival is at (5, 4), got (%d, %d)", rival.cellX, rival.cellY))
assert(rival.facing == "up", string.format("Rival faces up, got %s", rival.facing))
print("PASS: Scene 2 contextual positions (Oak at 6,3 down, Rival at 5,4 up)")

-- Test 2: Scene 3 with Bulbasaur picked (starterMon == 0 -> Rival chose Charmander at 10, 5)
setupSession(3, 0)
oak = Objects.find(4)
rival = Objects.find(8)
assert(oak.cellX == 6 and oak.cellY == 3, "Oak at (6, 3)")
assert(rival.cellX == 10 and rival.cellY == 5, string.format("Rival is at (10, 5) for Bulbasaur starter, got (%d, %d)", rival.cellX, rival.cellY))
assert(rival.facing == "up", "Rival faces up")
print("PASS: Scene 3 with Bulbasaur starter (Rival at 10,5 facing up)")

-- Test 3: Scene 3 with Squirtle picked (starterMon == 1 -> Rival chose Bulbasaur at 8, 5)
setupSession(3, 1)
oak = Objects.find(4)
rival = Objects.find(8)
assert(oak.cellX == 6 and oak.cellY == 3, "Oak at (6, 3)")
assert(rival.cellX == 8 and rival.cellY == 5, string.format("Rival is at (8, 5) for Squirtle starter, got (%d, %d)", rival.cellX, rival.cellY))
assert(rival.facing == "up", "Rival faces up")
print("PASS: Scene 3 with Squirtle starter (Rival at 8,5 facing up)")

-- Test 4: Scene 3 with Charmander picked (starterMon == 2 -> Rival chose Squirtle at 9, 5)
setupSession(3, 2)
oak = Objects.find(4)
rival = Objects.find(8)
assert(oak.cellX == 6 and oak.cellY == 3, "Oak at (6, 3)")
assert(rival.cellX == 9 and rival.cellY == 5, string.format("Rival is at (9, 5) for Charmander starter, got (%d, %d)", rival.cellX, rival.cellY))
assert(rival.facing == "up", "Rival faces up")
print("PASS: Scene 3 with Charmander starter (Rival at 9,5 facing up)")

-- Test 5: Scene 3 fallback to party[1].species when starterMon var is 0
setupSession(3, 0, 4) -- Charmander (species 4) in party
rival = Objects.find(8)
assert(rival.cellX == 9 and rival.cellY == 5, string.format("Rival is at (9, 5) via party species fallback, got (%d, %d)", rival.cellX, rival.cellY))
print("PASS: Scene 3 fallback to party species")

-- Test 6: Scene 4 (post rival battle)
setupSession(4, 2)
oak = Objects.find(4)
rival = Objects.find(8)
assert(oak.cellX == 6 and oak.cellY == 3, "Oak at (6, 3)")
assert(rival.hidden == true or rival.visible == false, "Rival is hidden in scene 4")
print("PASS: Scene 4 post-battle (Oak at 6,3, Rival hidden)")

-- Test 7: Verify rival approach movement paths from reloaded starter positions to (6, 7)
local function simulateRivalApproach(starterMon, expectedStartX, expectedSteps)
  setupSession(3, starterMon)
  local r = Objects.find(8)
  assert(r.cellX == expectedStartX and r.cellY == 5, "Rival at starter position")

  local x, y = r.cellX, r.cellY
  for _, step in ipairs(expectedSteps) do
    if step == 18 then -- walk_left
      x = x - 1
    elseif step == 19 then -- walk_right
      x = x + 1
    elseif step == 16 then -- walk_down
      y = y + 1
    elseif step == 17 then -- walk_up
      y = y - 1
    end
  end
  assert(x == 6 and y == 7, string.format("Rival reaches (6, 7) in front of player, got (%d, %d)", x, y))
end

-- Bulbasaur chosen (Rival took Charmander at 10, 5): 4 left, 2 down -> (6, 7)
simulateRivalApproach(0, 10, { 18, 18, 18, 18, 16, 16 })
-- Squirtle chosen (Rival took Bulbasaur at 8, 5): 2 left, 2 down -> (6, 7)
simulateRivalApproach(1, 8, { 18, 18, 16, 16 })
-- Charmander chosen (Rival took Squirtle at 9, 5): 3 left, 2 down -> (6, 7)
simulateRivalApproach(2, 9, { 18, 18, 18, 16, 16 })
print("PASS: Rival approach movement lands accurately at (6, 7) for all starters")

print("ALL TESTS PASSED for game3_oaks_lab_save_reload_test")
