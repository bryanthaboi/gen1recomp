#!/usr/bin/env luajit
-- Test Seafoam Islands B3F / B4F boulder puzzle, current stopping, and hole falling.

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

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_seafoam_puzzle_test: " .. tostring(Cache.reason))
  os.exit(0)
end

local Schema = require("src.core.game3.save_schema_firered")
local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local FieldMoves = require("src.core.game3.field_moves")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local Runtime = require("src.core.game3.runtime")
local Warp = require("src.core.game3.warp")

local game = { data = {} }
Dataset.hydrate(game)

local session = Schema.newGame({ name = "RED" })
game.session = session
Runtime.session = session
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
}

local B3F = "FR_SEAFOAM_ISLANDS_B3F"
local B4F = "FR_SEAFOAM_ISLANDS_B4F"

local FLAG_HIDE_SEAFOAM_B3F_BOULDER_1 = 0x46 -- 70
local FLAG_HIDE_SEAFOAM_B3F_BOULDER_2 = 0x47 -- 71
local FLAG_HIDE_SEAFOAM_B3F_BOULDER_3 = 0x48 -- 72
local FLAG_HIDE_SEAFOAM_B3F_BOULDER_4 = 0x49 -- 73
local FLAG_HIDE_SEAFOAM_B3F_BOULDER_5 = 0x4A -- 74
local FLAG_HIDE_SEAFOAM_B3F_BOULDER_6 = 0x4B -- 75
local FLAG_HIDE_SEAFOAM_B4F_BOULDER_1 = 0x4C -- 76
local FLAG_HIDE_SEAFOAM_B4F_BOULDER_2 = 0x4D -- 77
local FLAG_STOPPED_SEAFOAM_B3F_CURRENT = 0x2D2 -- 722
local FLAG_STOPPED_SEAFOAM_B4F_CURRENT = 0x2D3 -- 723

local function enterMap(mapId)
  local def = game.data.maps[mapId]
  if not def then return nil end
  Field._game = game
  session.map = mapId
  Field._session = session
  Field.running = true
  Field.locked = false
  Field.clearMetatiles()
  Space.activate(nil, mapId, game, nil)
  Collision.bindMap(game, mapId, def)
  Objects.loadMap(game, mapId, def)
  Space.runEnterScripts(nil, mapId, game, nil)
  return def
end

local function standAt(x, y, facing)
  Player.moving = false
  Player.progress = 0
  Player.surfing = false
  Player.biking = false
  Player.cellX, Player.cellY = x, y
  Player.targetX, Player.targetY = x, y
  Player.px, Player.py = x * 16, y * 16
  Player.facing = facing or "down"
end

local function pumpVm(limit)
  local vm = Space.vm
  if not vm then return 0 end
  local n = 0
  while vm:isRunning() and n < (limit or 512) do
    if Player and Player.tick then
      Player.tick(game)
    end
    if Objects and Objects.update then
      Objects.update(game)
    end
    vm:tick()
    n = n + 1
  end
  return n
end

print("[test] 1. New game initial Seafoam flag state")
check(Flags.getFlag(session, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_1) == true, "B4F boulder 1 starts HIDDEN")
check(Flags.getFlag(session, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_2) == true, "B4F boulder 2 starts HIDDEN")
check(Flags.getFlag(session, nil, FLAG_HIDE_SEAFOAM_B3F_BOULDER_1) == true, "B3F boulder 1 starts HIDDEN")
check(Flags.getFlag(session, nil, FLAG_HIDE_SEAFOAM_B3F_BOULDER_2) == true, "B3F boulder 2 starts HIDDEN")
check(Flags.getFlag(session, nil, FLAG_STOPPED_SEAFOAM_B3F_CURRENT) == false, "B3F current starts ACTIVE")
check(Flags.getFlag(session, nil, FLAG_STOPPED_SEAFOAM_B4F_CURRENT) == false, "B4F current starts ACTIVE")

print("[test] 2. Enter B4F before solving puzzle: current remains ACTIVE, no boulders in water")
enterMap(B4F)
pumpVm()
check(Flags.getFlag(session, nil, FLAG_STOPPED_SEAFOAM_B4F_CURRENT) == false, "B4F current NOT stopped on enter")
local b4fB1 = Objects.find(1)
local b4fB2 = Objects.find(2)
check(b4fB1 == nil or b4fB1.visible == false, "B4F boulder 1 object is not visible in water")
check(b4fB2 == nil or b4fB2.visible == false, "B4F boulder 2 object is not visible in water")

print("[test] 3. Enter B3F before solving puzzle: pushable boulders visible, dropped boulders hidden")
enterMap(B3F)
pumpVm()
check(Flags.getFlag(session, nil, FLAG_STOPPED_SEAFOAM_B3F_CURRENT) == false, "B3F current NOT stopped on enter")
local b3fB3 = Objects.find(3)
local b3fB6 = Objects.find(6)
check(b3fB3 ~= nil and b3fB3.visible ~= false, "B3F pushable boulder 3 is visible")
check(b3fB6 ~= nil and b3fB6.visible ~= false, "B3F pushable boulder 6 is visible")

print("[test] 4. Push both boulders on B3F into holes (drops to B4F)")
Flags.setFlag(Space.store, nil, FieldMoves.SYS_FLAGS.USE_STRENGTH, true)

-- Move boulder 6 (at 6,17) into hole at (6,18)
standAt(6, 16, "down")
local r1 = Player.tryMove("down", game, false)
eq(r1, "step", "boulder 6 pushed into hole")
check(Flags.getFlag(Space.store, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_1) == false, "B4F boulder 1 is revealed (unhidden)")

-- Position boulder 3 at (9,17) and push into hole at (9,18)
Objects.setObjectXY(3, 9, 17)
standAt(9, 16, "down")
local r2 = Player.tryMove("down", game, false)
eq(r2, "step", "boulder 3 pushed into hole")
check(Flags.getFlag(Space.store, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_2) == false, "B4F boulder 2 is revealed (unhidden)")

print("[test] 5. Enter B4F after dropping both boulders: current STOPS, calm water layout applied")
enterMap(B4F)
pumpVm()
check(Flags.getFlag(Space.store, nil, FLAG_STOPPED_SEAFOAM_B4F_CURRENT) == true, "B4F current is now STOPPED")
local b4fB1_after = Objects.find(1)
local b4fB2_after = Objects.find(2)
check(b4fB1_after ~= nil and b4fB1_after.visible ~= false, "B4F boulder 1 is now visible in water")
check(b4fB2_after ~= nil and b4fB2_after.visible ~= false, "B4F boulder 2 is now visible in water")

print("[test] 6. Falling through hole to B4F when current is active triggers sweep onFrame")
-- Reset flags to test falling when current is active
Flags.setFlag(Space.store, nil, FLAG_STOPPED_SEAFOAM_B4F_CURRENT, false)
Flags.setFlag(Space.store, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_1, true)
Flags.setFlag(Space.store, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_2, true)

enterMap(B4F)
Flags.setVar(Space.store, Space.vm.ctx, 0x4001, 1)
Player.surfing = true
Player.cellX, Player.cellY = 8, 17 -- Actual drop hole landing position

-- Trigger onFrame script
Space.runOnFrame()
pumpVm()
-- Current sweep script executes SeafoamIslandsB4F_CurrentDumpsPlayerOnLand
eq(Player.surfing, false, "player was dumped on land and is no longer surfing")
eq(Player.facing, "up", "player facing snapped to up (North)")
eq(Player.cellY, 12, "player jumped up onto the stairs/land (y=12)")

print("[test] 7. Legacy save repair: empty flags restored with correct defaults and invariants")
local legacySave = {
  schemaVersion = 1,
  name = "ASH",
  flags = {}, -- completely unseeded legacy flags
  vars = {},
}
local restoredSession = Schema.fromSaveTable(legacySave)
check(Flags.getFlag(restoredSession, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_1) == true, "Legacy save: B4F boulder 1 is hidden")
check(Flags.getFlag(restoredSession, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_2) == true, "Legacy save: B4F boulder 2 is hidden")
check(Flags.getFlag(restoredSession, nil, FLAG_STOPPED_SEAFOAM_B4F_CURRENT) == false, "Legacy save: B4F current is active")
check(Flags.getFlag(restoredSession, nil, 0x02C) == true, "Legacy save: Pallet Town Oak is hidden")
check(Flags.getFlag(restoredSession, nil, 0x033) == true, "Legacy save: Bill (human) is hidden")
check(Flags.getFlag(restoredSession, nil, 0x092) == true, "Legacy save: Pewter running shoes aide is hidden")
check(Flags.getFlag(restoredSession, nil, 0x035) == true, "Legacy save: Mr. Fuji in house is hidden")
check(Flags.getFlag(restoredSession, nil, 0x05A) == true, "Legacy save: Oak in champ room is hidden")

print("[test] 8. Legacy save repair: premature calm water flag fixed when boulders were not dropped")
local corruptedSave = {
  schemaVersion = 1,
  name = "RED",
  flags = {
    [tostring(FLAG_STOPPED_SEAFOAM_B4F_CURRENT)] = true, -- erroneously set
  },
  vars = {},
}
local fixedSession = Schema.fromSaveTable(corruptedSave)
check(Flags.getFlag(fixedSession, nil, FLAG_STOPPED_SEAFOAM_B4F_CURRENT) == false, "Corrupted calm water flag corrected to false")
check(Flags.getFlag(fixedSession, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_1) == true, "Corrupted save: B4F boulder 1 hidden")
check(Flags.getFlag(fixedSession, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_2) == true, "Corrupted save: B4F boulder 2 hidden")

print("[test] 9. Legacy save repair: completed puzzle retains calm water and visible dropped boulders")
local solvedSave = {
  schemaVersion = 1,
  name = "RED",
  flags = {
    [tostring(FLAG_HIDE_SEAFOAM_B3F_BOULDER_3)] = true, -- B3F obj 6 dropped
    [tostring(FLAG_HIDE_SEAFOAM_B3F_BOULDER_5)] = true, -- B3F obj 3 dropped
  },
  vars = {},
}
local solvedSession = Schema.fromSaveTable(solvedSave)
check(Flags.getFlag(solvedSession, nil, FLAG_STOPPED_SEAFOAM_B4F_CURRENT) == true, "Solved save: B4F current stopped")
check(Flags.getFlag(solvedSession, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_1) == false, "Solved save: B4F boulder 1 visible")
check(Flags.getFlag(solvedSession, nil, FLAG_HIDE_SEAFOAM_B4F_BOULDER_2) == false, "Solved save: B4F boulder 2 visible")

if failed > 0 then
  print("[FAIL] " .. failed .. " tests failed")
  os.exit(1)
end
print("[test] ALL SEAFOAM PUZZLE AND SAVE REPAIR TESTS PASSED!")
os.exit(0)

