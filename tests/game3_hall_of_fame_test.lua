#!/usr/bin/env luajit
-- FRLG Hall of Fame Induction Screen & Egg Skipping Unit Test Suite

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

local HallOfFame = require("src.ui.game3.hall_of_fame")
local Pokemon = require("src.core.game3.pokemon")
local Adapters = require("src.core.game3.scripting.adapters")
local Natives = require("src.core.game3.scripting.natives")
local Std = require("src.core.game3.scripting.stdscripts")

print("=== [TEST 1] Hall of Fame Strict Egg Skipping & Mon Progression ===")
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
  })

  check(HallOfFame.isOpen() == true, "HallOfFame is open")
  check(#HallOfFame._mons == 4, "Eligible mons count is exactly 4 (skipped 2 eggs)")

  -- Mon 1: Charizard
  local m1 = HallOfFame.getCurrentMon()
  check(m1 and m1.name == "CHARIZARD", "Mon 1 is CHARIZARD")

  local inpA = {
    wasPressed = function(_, k) return k == "a" end,
    isDown = function() return false end,
  }

  -- Advance to Mon 2: Pikachu (skipping egg at slot 2)
  HallOfFame.handleInput(inpA)
  local m2 = HallOfFame.getCurrentMon()
  check(m2 and m2.name == "PIKACHU", "Mon 2 is PIKACHU (skipped egg)")

  -- Advance to Mon 3: Blastoise (skipping egg at slot 4)
  HallOfFame.handleInput(inpA)
  local m3 = HallOfFame.getCurrentMon()
  check(m3 and m3.name == "BLASTOISE", "Mon 3 is BLASTOISE (skipped egg)")

  -- Advance to Mon 4: Snorlax
  HallOfFame.handleInput(inpA)
  local m4 = HallOfFame.getCurrentMon()
  check(m4 and m4.name == "SNORLAX", "Mon 4 is SNORLAX")

  -- Advance to Congratulations screen
  HallOfFame.handleInput(inpA)
  check(HallOfFame._phase == "congrats", "Advanced to CONGRATULATIONS phase")

  -- Advance from Congratulations to close and yield to credits
  HallOfFame.handleInput(inpA)
  check(HallOfFame.isOpen() == false, "HallOfFame closed cleanly")
  check(doneCalled == true, "onDone credits yield callback executed")

  -- Verify Flag & Debut Timestamp Recording
  check(session.flags[0x82C] == true, "FLAG_SYS_GAME_CLEAR (0x82C) is set")
  check(session.game_cleared == true, "session.game_cleared is true")
  check(session.hofDebutTime == "14:22:35", "session.hofDebutTime stamped correctly")
  check(session.hofDebutHours == 14 and session.hofDebutMinutes == 22, "hofDebutHours and Minutes stamped")
  check(#session.hallOfFameTeams == 1, "Hall of fame team record saved")
  check(#session.hallOfFameTeams[1] == 4, "Saved team record contains exactly 4 non-egg mons")
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
  check(session.flags[0x82C] == true, "FLAG_SYS_GAME_CLEAR set by native")

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
