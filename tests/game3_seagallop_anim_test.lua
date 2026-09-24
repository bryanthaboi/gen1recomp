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

function tests.test_arrival_fade_does_not_strand_overlay()
  local Fade = require("src.ui.game3.fade")
  Fade.active, Fade.doneCb, Fade.t = false, nil, 0
  local warped, done, arrived = 0, false, false
  local tAtWarp, pendingArrival
  Seagallop.start(0, 1, function()
    warped = warped + 1
    tAtWarp = Fade.t
    pendingArrival = true
  end, function() done = true end)
  for _ = 1, 260 do
    Fade.tick(1 / 60)
    if Seagallop.isActive() then Seagallop.update(1 / 60) end
    if pendingArrival then
      pendingArrival = false
      Fade.begin(Fade.MODE.FROM_BLACK, 1, function() arrived = true end)
    end
  end
  assert(warped == 1, "onWarp should fire exactly once (got " .. warped .. ")")
  assert(tAtWarp == 16, "screen should be fully black at the warp (t=" .. tostring(tAtWarp) .. ")")
  assert(done, "onDone should fire even when the arrival fade takes the Fade slot")
  assert(arrived, "the arrival fade-in should complete")
  assert(not Seagallop.isActive(), "overlay must be inactive after arrival")
  assert(Fade.t == 0, "screen should be clear after arrival (t=" .. tostring(Fade.t) .. ")")
end

function tests.test_warp_waits_for_music_fade()
  local Fade = require("src.ui.game3.fade")
  Fade.active, Fade.doneCb, Fade.t = false, nil, 0
  local savedAudio = package.loaded["src.core.game3.audio"]
  local fakeAudio = {}
  function fakeAudio.fadeOutBgm() fakeAudio._fadeOut = { t = 0 } end
  function fakeAudio.playSe() end
  package.loaded["src.core.game3.audio"] = fakeAudio
  local warpTick, fadeDoneTick
  local ok, err = pcall(function()
    Seagallop.start(0, 1, function() warpTick = Seagallop._lastTick end, function() end)
    local tick = 0
    while Seagallop.isActive() and tick < 400 do
      tick = tick + 1
      Fade.tick(1 / 60)
      if not fadeDoneTick and Fade.t == 16 and not Fade.isActive() then fadeDoneTick = tick end
      local run = Seagallop._run
      Seagallop._lastTick = run and (run.tick + 1)
      Seagallop.update(1 / 60)
    end
  end)
  package.loaded["src.core.game3.audio"] = savedAudio
  Seagallop._lastTick = nil
  assert(ok, err)
  assert(warpTick, "ferry should warp even while the music fade never reports done")
  assert(warpTick >= 140 + 64, "warp should wait 64 frames for the music fade (warped at tick " .. tostring(warpTick) .. ")")
  assert(warpTick <= 140 + 66, "warp should not wait past the music fade (warped at tick " .. tostring(warpTick) .. ")")
  assert(fadeDoneTick and fadeDoneTick < warpTick, "screen should already be black before the warp")
end

local failed = 0
local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  Seagallop.stop()
  local ok, err = pcall(tests[name])
  if ok then
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end
if failed > 0 then os.exit(1) end
print("[test] all passed")
os.exit(0)
