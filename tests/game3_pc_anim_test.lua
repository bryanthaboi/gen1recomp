-- tests/game3_pc_anim_test.lua
-- Verifies PC animation turn on / turn off metatile behavior and task cancellation.

local PcAnim = require("src.core.game3.pc_anim")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")

local testsPassed = 0

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("FAILED: %s (expected %s, got %s)", msg or "assert_eq", tostring(expected), tostring(actual)))
  end
end

-- Track metatiles set
local lastSet = nil
PcAnim.setter(function(x, y, mid, impassable)
  lastSet = { x = x, y = y, mid = mid, impassable = impassable }
end)

-- Mock player
local Player = require("src.core.game3.player")
Player.cellX = 5
Player.cellY = 10
Player.facing = "up"

print("--- Test 1: Pokemon Center PC Turn On & Flicker Sequence ---")
do
  local ctx = { specialVars = { [0x8004] = 0 } }
  PcAnim.reset()
  PcAnim.turnOn(ctx)
  assert_eq(PcAnim.task ~= nil, true, "task created on turnOn")

  -- State 0 -> timer ticks to 6 -> turns ON (0x063)
  for _ = 1, 7 do PcAnim.update() end
  assert_eq(lastSet and lastSet.mid, 0x063, "state 0 turns ON (0x063)")
  assert_eq(PcAnim.task.state, 1, "task state is 1")

  -- State 1 -> timer ticks to 6 -> flickers OFF (0x062)
  for _ = 1, 6 do PcAnim.update() end
  assert_eq(lastSet and lastSet.mid, 0x062, "state 1 flickers OFF (0x062)")
  assert_eq(PcAnim.task.state, 2, "task state is 2")

  -- State 2 -> timer ticks to 6 -> flickers ON (0x063)
  for _ = 1, 6 do PcAnim.update() end
  assert_eq(lastSet and lastSet.mid, 0x063, "state 2 flickers ON (0x063)")
  assert_eq(PcAnim.task.state, 3, "task state is 3")

  -- State 3 -> timer ticks to 6 -> flickers OFF (0x062)
  for _ = 1, 6 do PcAnim.update() end
  assert_eq(lastSet and lastSet.mid, 0x062, "state 3 flickers OFF (0x062)")
  assert_eq(PcAnim.task.state, 4, "task state is 4")

  -- State 4 -> timer ticks to 6 -> final ON (0x063) and task finishes
  for _ = 1, 6 do PcAnim.update() end
  assert_eq(lastSet and lastSet.mid, 0x063, "state 4 turns ON (0x063)")
  assert_eq(PcAnim.task, nil, "task destroyed after state 4")

  print("ok  Pokemon Center PC turnOn animation sequence complete")
  testsPassed = testsPassed + 1
end

print("--- Test 2: Pokemon Center PC Turn Off and Task Cancellation ---")
do
  local ctx = { specialVars = { [0x8004] = 0 } }
  PcAnim.reset()
  -- Player interacts with PC: turnOn started
  PcAnim.turnOn(ctx)
  -- 1 frame elapsed before menu opened
  PcAnim.update()

  -- Player closes PC: turnOff is called
  PcAnim.turnOff(ctx)
  assert_eq(lastSet and lastSet.mid, 0x062, "turnOff sets METATILE_OFF (0x062)")
  assert_eq(PcAnim.task, nil, "task cancelled by turnOff")

  -- Subsequent overworld ticks must NOT turn PC back on
  for _ = 1, 30 do PcAnim.update() end
  assert_eq(lastSet and lastSet.mid, 0x062, "screen remains OFF (0x062) on subsequent ticks")

  print("ok  Pokemon Center PC turnOff cancels task and leaves screen OFF")
  testsPassed = testsPassed + 1
end

print("--- Test 3: Player Bedroom PC (VAR_0x8004 = 1) Turn On / Turn Off ---")
do
  local ctx = { specialVars = { [0x8004] = 1 } }
  PcAnim.reset()
  PcAnim.turnOn(ctx)
  for _ = 1, 7 do PcAnim.update() end
  assert_eq(lastSet and lastSet.mid, 0x28A, "bedroom PC state 0 is METATILE_GenericBuilding1_PlayersPCOn (0x28A)")

  PcAnim.turnOff(ctx)
  assert_eq(lastSet and lastSet.mid, 0x28F, "bedroom PC turnOff is METATILE_GenericBuilding1_PlayersPCOff (0x28F)")
  assert_eq(PcAnim.task, nil, "bedroom PC task cancelled")

  for _ = 1, 30 do PcAnim.update() end
  assert_eq(lastSet and lastSet.mid, 0x28F, "bedroom PC screen remains OFF (0x28F)")

  print("ok  Bedroom PC (0x28F / 0x28A) works correctly")
  testsPassed = testsPassed + 1
end

print("--- Test 4: EventScript_PC Execution Flow Verification ---")
do
  local Vm = require("src.core.game3.scripting.vm")
  local Natives = require("src.core.game3.scripting.natives")

  local Fixture = require("tests.fixture_data.game3_pc_scripts")

  local Adapters = require("src.core.game3.scripting.adapters")
  local vm = Vm.new({
    scripts = Fixture.SCRIPTS,
    text = Fixture.TEXT,
    adapters = Adapters.stub({
      openPc = function(done)
        -- Simulate user closing PC immediately
        done()
      end,
      openMessage = function() end,
      openMessageStay = function() end,
      closeMessage = function() end,
    }),
  })

  PcAnim.reset()
  local ok = vm:start("EventScript_PC")
  assert_eq(ok, true, "vm started EventScript_PC")

  -- Run script to completion
  local steps = 0
  while vm:isRunning() and steps < 50 do
    vm:step()
    steps = steps + 1
  end

  assert_eq(vm:isRunning(), false, "EventScript_PC completed")
  assert_eq(lastSet and lastSet.mid, 0x062, "EventScript_PC final metatile is METATILE_OFF (0x062)")
  assert_eq(PcAnim.task, nil, "EventScript_PC left no dangling animation task")

  -- Tick overworld frames after script completion
  for _ = 1, 60 do PcAnim.update() end
  assert_eq(lastSet and lastSet.mid, 0x062, "Screen remains 0x062 after 60 overworld frames")

  print("ok  EventScript_PC script run leaves screen OFF permanently")
  testsPassed = testsPassed + 1
end

print(string.format("\nALL %d PC ANIMATION TESTS PASSED!", testsPassed))
