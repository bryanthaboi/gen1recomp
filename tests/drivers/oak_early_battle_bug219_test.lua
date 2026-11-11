-- Driver: regression coverage for #219 "Early Blue Battle".
--
-- TEXT_OAKSLAB_RIVAL (data/scripts/oaks_lab.lua) is the rival's *talk*
-- handler.  In pret/pokered scripts/OaksLab.asm OaksLabText8, talking to
-- the rival after you have a starter but before the lab battle only prints
-- _OaksLabRivalMyPokemonLooksStrongerText: the battle itself is a
-- coordinate trigger (OaksLabRivalChallengesPlayerScript, wYCoord == 6),
-- never a talk action.  The buggy handler fell through from that line
-- straight into start_battle OPP_RIVAL1, so talking to Blue at the table
-- immediately launched the rival fight.
--
-- Scenario A (the #219 regression): talk to the rival with a starter but
--   no lab battle yet.  Correct: the "looks stronger" line shows and NO
--   battle starts.  Fails before the fix (start_battle fires on talk).
-- Scenario B (guard against over-correction): step onto the coordinate
--   trigger (y >= 6).  Correct: the onStep challenge still starts the
--   battle.  Passes both before and after the fix.
--
-- start_battle is stubbed to record the call and return "end" (halts the
-- script cleanly, no BattleState push, no yield) so the run never hangs
-- and needs no full party.  We also read the raw text handed to
-- TextBox.new (before {PLAYER}/{RIVAL} substitution) so "stronger" is
-- detectable.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- Capture the raw text the next TextBox is built with.
  local TextBox = require("src.render.TextBox")
  local origNew = TextBox.new
  local lastText
  TextBox.new = function(g, text, ...)
    lastText = text
    return origNew(g, text, ...)
  end

  -- Stub start_battle: record it and halt the script instead of pushing a
  -- BattleState (which would need a real party) or yielding (which would
  -- hang the driver).  ScriptRunner resolves the live Commands.start_battle
  -- when no mod overrides it, so this monkeypatch intercepts both the talk
  -- handler and the onStep challenge.
  local Commands = require("src.script.Commands")
  local origStartBattle = Commands.start_battle
  local battleStarted = false
  Commands.start_battle = function(_ctx, _kind, _a, _b)
    battleStarted = true
    return "end"
  end

  local function restore()
    TextBox.new = origNew
    Commands.start_battle = origStartBattle
  end

  local function setFlags()
    local flags = game.save.flags or {}
    game.save.flags = flags
    flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
    flags.EVENT_FOLLOWED_OAK_INTO_LAB_2 = true
    flags.EVENT_GOT_STARTER = true
    flags.EVENT_CHOSE_SQUIRTLE = true
    flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = nil
  end

  -- ---- Scenario A: talk to the rival at the table.
  -- fresh overworld in Oak's lab, player one cell right of the rival
  -- (object 1 at cell 4,3) and facing him.
  U.teleport(game, "OAKS_LAB", 5, 3, "left")
  setFlags()
  U.wait(6)
  battleStarted = false
  lastText = nil

  U.shot(game, DIR .. "/a_before.png")

  -- open the rival's textbox
  U.tap(game, "left"); U.wait(2)
  for _ = 1, 8 do
    U.tap(game, "a")
    for _ = 1, 30 do
      if lastText then break end
      U.wait(1)
    end
    if lastText then break end
  end
  local strongerSeen = lastText ~= nil and lastText:find("stronger") ~= nil
  -- let the typewriter reveal the line, then shoot the box: the "looks
  -- stronger" taunt, still overworld, no battle intro
  U.wait(30)
  U.shot(game, DIR .. "/a_after.png")

  -- dismiss the taunt box.  Before the fix, closing it drops the script
  -- into the buggy start_battle rows (battleStarted flips true); after the
  -- fix it hits jump "end" and the stack settles back to the overworld.
  -- Stop the moment either happens so we never re-open the box by talking
  -- again (which would leave a stray TextBox on top and false-fail the
  -- overworld check).
  for _ = 1, 20 do
    if battleStarted then break end
    if game.stack:top() == game.overworld then break end
    U.tap(game, "a")
    U.wait(3)
  end
  U.wait(10) -- let any fall-through start_battle fire

  local aBattleStarted = battleStarted
  local aOverworld = (game.stack:top() == game.overworld)
  local aText = lastText or "<none>"
  local aPass = strongerSeen and (aBattleStarted == false) and aOverworld
  U.log("SCENARIO A text:", aText)
  U.log("SCENARIO A strongerSeen:", tostring(strongerSeen),
        "battleStarted:", tostring(aBattleStarted),
        "overworld:", tostring(aOverworld))
  U.log("SCENARIO A", aPass and "PASS" or "FAIL")

  -- close any open box before scenario B
  for _ = 1, 10 do U.tap(game, "a"); U.wait(2) end

  -- ---- Scenario B: step onto the coordinate trigger (y >= 6).
  -- Guards the real challenge path so the fix doesn't kill the lab battle.
  U.teleport(game, "OAKS_LAB", 4, 5, "down")
  setFlags()
  U.wait(6)
  battleStarted = false
  do
    local p = game.overworld.player
    U.log("SCENARIO B start cell:", tostring(p.cellX), tostring(p.cellY),
          "rival:", tostring(game.overworld:npcByIndex(1) ~= nil))
  end
  -- walk down until the player crosses y == 6 (OaksLabRivalChallenges),
  -- pausing to mash A so the "I'll take you on" box + rival walk advance
  for _ = 1, 6 do
    U.hold(game, "down", 8)
    for _ = 1, 12 do
      U.tap(game, "a")
      U.wait(3)
      if battleStarted then break end
    end
    if battleStarted then break end
  end
  do
    local p = game.overworld.player
    U.log("SCENARIO B end cell:", tostring(p.cellX), tostring(p.cellY),
          "lastText:", tostring(lastText))
  end
  U.shot(game, DIR .. "/b_after.png")
  local bPass = (battleStarted == true)
  U.log("SCENARIO B battleStarted:", tostring(battleStarted))
  U.log("SCENARIO B", bPass and "PASS" or "FAIL")

  -- restore hooks before any assert so a failure can't leave them installed
  restore()

  U.log("RESULT bug219", (aPass and bPass) and "PASS" or "FAIL")
  assert(aPass,
    "Scenario A: talking to the rival must only show the 'looks stronger' "
    .. "line and start no battle (strongerSeen/battleStarted=false/overworld); "
    .. "text=" .. aText .. " battleStarted=" .. tostring(aBattleStarted))
  assert(bPass,
    "Scenario B: stepping onto the coordinate trigger must still start the "
    .. "lab battle")
end
