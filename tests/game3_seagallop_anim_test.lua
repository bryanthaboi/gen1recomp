-- Tests for Seagallop ferry logic, direction matrix, and animation tick simulation

local Seagallop = require("src.ui.game3.seagallop")
local NativeSeagallop = require("src.core.game3.scripting.natives_seagallop")

local tests = {}

function tests.test_direction_of_travel()
  -- From Vermilion (0): all Sevii islands are Eastbound (1)
  assert(Seagallop.directionOfTravel(0, 1) == 1, "Vermilion -> One Island should be Eastbound")
  assert(Seagallop.directionOfTravel(0, 2) == 1, "Vermilion -> Two Island should be Eastbound")
  assert(Seagallop.directionOfTravel(0, 3) == 1, "Vermilion -> Three Island should be Eastbound")
  assert(Seagallop.directionOfTravel(0, 7) == 1, "Vermilion -> Seven Island should be Eastbound")

  -- From One Island (1): to Vermilion (0) is Westbound (0)
  assert(Seagallop.directionOfTravel(1, 0) == 0, "One Island -> Vermilion should be Westbound")

  -- From Birth Island (10): 0x000 -> all destinations Westbound (0)
  assert(Seagallop.directionOfTravel(10, 0) == 0, "Birth Island -> Vermilion should be Westbound")
end

function tests.test_seagallop_numbers()
  assert(NativeSeagallop.seagallopNumber(8, 0) == 1, "Cinnabar should be Seagallop 1")
  assert(NativeSeagallop.seagallopNumber(1, 2) == 2, "One -> Two Island should be Seagallop 2")
  assert(NativeSeagallop.seagallopNumber(4, 5) == 3, "Four -> Five Island should be Seagallop 3")
  assert(NativeSeagallop.seagallopNumber(6, 7) == 5, "Six -> Seven Island should be Seagallop 5")
  assert(NativeSeagallop.seagallopNumber(0, 1) == 7, "Vermilion -> Island should be Seagallop 7")
  assert(NativeSeagallop.seagallopNumber(9, 1) == 10, "Navel Rock -> Island should be Seagallop 10")
  assert(NativeSeagallop.seagallopNumber(10, 1) == 12, "Birth Island -> Island should be Seagallop 12")
end

function tests.test_simulation_ticks()
  local warped = false
  local done = false
  Seagallop.start(0, 1, function() warped = true end, function() done = true end)
  assert(Seagallop.isActive(), "Seagallop cutscene should be active")

  -- Update through 10 frames (10/60 seconds)
  Seagallop.update(10 / 60)
  local run = Seagallop._run
  assert(run.tick == 10, "Should have simulated exactly 10 ticks (got " .. tostring(run.tick) .. ")")
  assert(run.ferryX == 30, "Eastbound ferry should move +3 px per tick (at x=30)")
  assert(run.bgX == 60, "Eastbound BG should scroll +6 px per tick (at bgX=60)")
  assert(#run.wakes == 2, "Should have spawned 2 wakes at tick 5 and 10 (got " .. tostring(#run.wakes) .. ")")

  Seagallop.stop()
  assert(not Seagallop.isActive(), "Seagallop should be inactive after stop")
end

return tests
