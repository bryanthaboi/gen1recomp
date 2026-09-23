#!/usr/bin/env luajit
-- FRLG Hall of Fame Induction Screen & Egg Skipping Unit Test Suite

package.path = "./?.lua;./?/init.lua;" .. package.path
local Game3Cache = require("tests.game3_cache")
if not Game3Cache.bundle() then print("[skip] hall_of_fame: " .. tostring(Game3Cache.reason)) return end

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local HallOfFame = require("src.ui.game3.hall_of_fame")
local Pokemon = require("src.core.game3.pokemon")
local Adapters = require("src.core.game3.scripting.adapters")
local Natives = require("src.core.game3.scripting.natives")
local Std = require("src.core.game3.scripting.stdscripts")

print("=== [TEST 1] Hall of Fame induction order and timing ===")
do
  local party = {
    { species = 6, name = "CHARIZARD", level = 55, otId = 12345, moves = { "FLAMETHROWER", "FLY", "SLASH", "FIRE_SPIN" } },
    { species = 412, isEgg = true, egg = true, name = "EGG", level = 1 }, -- Egg in slot 2
    { species = 25, name = "PIKACHU", level = 52, otId = 12345, moves = { "THUNDERBOLT", "QUICK_ATTACK", "THUNDER_WAVE", "SLAM" } },
    { species = 175, egg = true, name = "TOGEPI EGG", level = 1 }, -- Egg in slot 4
    { species = 9, name = "BLASTOISE", level = 54, otId = 12345, moves = { "SURF", "HYDRO_PUMP", "ICE_BEAM", "BITE" } },
    { species = 143, name = "SNORLAX", level = 53, otId = 12345, moves = { "BODY_SLAM", "REST", "HYPER_BEAM", "EARTHQUAKE" } },
  }

  local session = {
    name = "RED",
    trainerId = 12345,
    playTimeHours = 14,
    playTimeMinutes = 22,
    playTimeSeconds = 35,
    party = party,
    flags = {},
  }

  local doneCalled = false
  HallOfFame.start({
    session = session,
    onDone = function() doneCalled = true end,
    warp = false,
  })

  check(HallOfFame.isOpen() == true, "HallOfFame is open")
  -- pokefirered/src/hall_of_fame.c:390
  check(#HallOfFame._mons == 6, "every occupied party slot is inducted, eggs included")

  local inpA = {
    wasPressed = function(_, k) return k == "a" end,
    isDown = function() return false end,
  }

  local shown = {}
  local lastInfo = nil
  local frames = 0
  while HallOfFame.isOpen() and HallOfFame.phase() ~= "exitwait" and frames < 20000 do
    HallOfFame.handleInput(inpA)
    HallOfFame.update(1 / 60)
    frames = frames + 1
    if HallOfFame._info and HallOfFame._info ~= lastInfo then
      lastInfo = HallOfFame._info
      shown[#shown + 1] = lastInfo.name
    end
  end
  check(HallOfFame.phase() == "exitwait", "the induction ran to the player card on its own timers")
  check(table.concat(shown, ",") == "CHARIZARD,EGG,PIKACHU,TOGEPI EGG,BLASTOISE,SNORLAX",
    "mons were shown in party order: " .. table.concat(shown, ","))
  check(HallOfFame.isOpen() == true, "A presses before the player card did not close the screen")

  HallOfFame.handleInput(inpA)
  for _ = 1, 400 do
    if not HallOfFame.isOpen() then break end
    HallOfFame.update(1 / 60)
  end
  check(HallOfFame.isOpen() == false, "HallOfFame closed cleanly")
  check(doneCalled == true, "onDone credits yield callback executed")

  -- Verify Flag & Debut Timestamp Recording
  check(session.flags[0x82C] == true, "FLAG_SYS_GAME_CLEAR (0x82C) is set")
  check(session.game_cleared == true, "session.game_cleared is true")
  check(session.hofDebutTime == "14:22:35", "session.hofDebutTime stamped correctly")
  check(session.hofDebutHours == 14 and session.hofDebutMinutes == 22, "hofDebutHours and Minutes stamped")
  check(#session.hallOfFameTeams == 1, "Hall of fame team record saved")
  local rec = session.hallOfFameTeams[1]
  check(#rec == 6, "Saved team record keeps all 6 party slots (hall_of_fame.c:389)")
  check(rec[2].species == 412 and rec[4].species == 412, "Eggs are recorded as SPECIES_EGG")
  check(session.gameStats[10] == 1, "GAME_STAT_ENTERED_HOF incremented (save.c:665)")
end

print("=== [TEST 2] Scripting Special Native EnterHallOfFame Integration ===")
do
  local hofCalled = false
  local session = {
    flags = {},
    party = { { species = 1, name = "BULBASAUR", level = 50 } },
    playTimeHours = 5,
    playTimeMinutes = 10,
  }

  local adapters = Adapters.stub({
    session = session,
    hallOfFame = function(done)
      hofCalled = true
      HallOfFame.start({
        session = session,
        onDone = done,
        warp = false,
      })
    end,
  })

  local nativeFn = Natives.ALLOW["special:" .. Std.SPECIAL.EnterHallOfFame]
  check(type(nativeFn) == "function", "Special 272 EnterHallOfFame handler exists")

  local ctx = { pc = 1, waiting = false }
  local yielded = nativeFn(ctx, adapters)
  check(yielded == true, "Special EnterHallOfFame yielded execution to HallOfFame")
  check(hofCalled == true, "adapters.hallOfFame was invoked")
  check(HallOfFame.isOpen() == true, "HallOfFame UI is open")
  for _ = 1, 200 do
    if HallOfFame.phase() == "display" then break end
    HallOfFame.update(1 / 60)
  end
  check(session.flags[0x82C] == true, "FLAG_SYS_GAME_CLEAR saved with the induction")

  -- Close
  HallOfFame.close()
  check(HallOfFame.isOpen() == false, "HallOfFame closed")
end

if failed > 0 then
  print(string.format("\n[FAILED] %d test(s) failed", failed))
  os.exit(1)
else
  print("\nALL HALL OF FAME TESTS PASSED CLEANLY!")
end
