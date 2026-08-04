-- Manual check on the Silph Co. Giovanni aftermath (#722).  pokered
-- scripts/SilphCo11F.asm SilphCo11FGiovanniAfterBattleScript: the loss line,
-- then TEXT_SILPHCO11F_GIOVANNI_YOU_RUINED_OUR_PLANS, GBFadeOutToBlack, the
-- rockets leaving, Delay3, GBFadeInFromBlack.  The order and the fade are the
-- whole report, so no POKEPORT_SPEED here -- it scales only the logic clock.
--   SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/silph_giovanni_bug722_test.lua POKEPORT_IDENTITY=bug722 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local BattleState = require("src.battle.BattleState")
  local ScriptRunner = require("src.script.ScriptRunner")
  local mapScripts = require("data.scripts.init")
  local victories = require("data.scripts.victories")

  -- pokered data/maps/objects/SilphCo11F.asm: GIOVANNI (6,9), ROCKET1 (3,16),
  -- ROCKET2 (15,9).  SilphCo11FDefaultScript.PlayerCoordsArray is (6,13) and
  -- (7,12); each is stepped onto from the cell directly below it, and the
  -- trigger only reads the cell the player lands on.
  local MAP = "SILPH_CO_11F"
  local TRIGGERS = { { stand = { 7, 13 }, cell = { 7, 12 } },
                     { stand = { 6, 14 }, cell = { 6, 13 } } }
  local ELEVENTH = { "SILPHCO11F_GIOVANNI", "SILPHCO11F_ROCKET1",
                     "SILPHCO11F_ROCKET2" }
  local SPEECH = "_SilphCo11FGiovanniYouRuinedOurPlansText"
  local LOSS = "_SilphCo10FGiovanniILostAgainText"
  -- SilphCo11FTeamRocketLeavesScript hides 31 toggles across 2F-11F; the
  -- Saffron street half is M.SAFFRON_CITY.onEnter (data/scripts/story4.lua).
  local HIDE_ROWS = 31

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function spawned(name)
    for _, n in ipairs(game.overworld and game.overworld.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  local function boxText(top)
    local lines = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    return table.concat(lines, " ")
  end

  local function topBox()
    local top = game.stack:top()
    if getmetatable(top) == TextBox then return top end
    return nil
  end

  -- ---- the half the eye cannot judge -------------------------------------
  -- A missing text key, a renamed command and a script that never gets queued
  -- all look the same on screen: the battle ends and the rockets are gone.
  local hooks = mapScripts.get(MAP)
  check("SILPH_CO_11F still has the coordinate trigger",
        hooks ~= nil and type(hooks.onStep) == "function")

  for _, key in ipairs({ SPEECH, LOSS }) do
    local body = game.data.text[key]
    check(key .. " is extracted",
          type(body) == "string" and body ~= "")
  end
  local speech = game.data.text[SPEECH]
  if type(speech) == "string" then
    U.log("  the speech reads:",
          (speech:gsub("\n", " "):gsub("\f", " <page> ")))
  end

  local reward = victories["OPP_GIOVANNI#2"]
  check("OPP_GIOVANNI#2 still sets EVENT_BEAT_SILPH_CO_GIOVANNI",
        reward ~= nil and reward.flag == "EVENT_BEAT_SILPH_CO_GIOVANNI")
  check("and now carries the loss line he has no trainer header for (#722)",
        reward ~= nil and reward.dialogue ~= nil and reward.dialogue[1] == LOSS)

  local vol = game.save.options and game.save.options.sfxVol
  if (vol or 0) == 0 then
    U.log("sfxVol is 0 -- the battle and its text will be silent, raise it in OPTION")
  else
    U.log("sfxVol", tostring(vol))
  end

  -- ---- put the fight back on the table -----------------------------------
  local function armFight()
    game.save.party = {
      Pokemon.new(game.data, "CHARIZARD", 70),
      Pokemon.new(game.data, "SNORLAX", 70),
      Pokemon.new(game.data, "LAPRAS", 70),
    }
    game.save.player.name = "bryan"
    game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI = nil
    game.save.flags.EVENT_BEAT_SILPH_CO_11F_TRAINER_0 = nil
    game.save.flags.EVENT_BEAT_SILPH_CO_11F_TRAINER_1 = nil
    game.save.objectToggles = {}
    game.save.defeatedTrainers = {}
  end
  armFight()

  -- ---- walk onto the trigger pad -----------------------------------------
  local function liveBattle()
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == BattleState then return s end
    end
    return nil
  end

  local battle, cell
  for i, t in ipairs(TRIGGERS) do
    U.teleport(game, MAP, t.stand[1], t.stand[2], "up")
    U.wait(10)
    if i == 1 then
      for _, name in ipairs(ELEVENTH) do
        check(name .. " is on the floor before the fight", spawned(name) ~= nil)
      end
      U.shot(game, DIR .. "/bug722_0_before.png")
    end
    U.hold(game, "up", 24)
    for _ = 1, 300 do
      U.wait(1)
      battle = liveBattle()
      if battle then break end
      -- his pre-battle line holds the overworld while he walks down
      if topBox() then U.tap(game, "a") end
    end
    if battle then cell = t.cell break end
    U.log(("the step up from (%d,%d) missed the trigger; trying the other pad")
            :format(t.stand[1], t.stand[2]))
  end
  cell = cell or TRIGGERS[1].cell
  check(("stepping onto (%d,%d) started GIOVANNI"):format(cell[1], cell[2]),
        battle ~= nil)
  if not battle then
    U.log("nothing below ran: the trigger pads moved, check")
    U.log("SilphCo11FDefaultScript.PlayerCoordsArray against M.SILPH_CO_11F.onStep")
    while true do coroutine.yield() end
  end
  U.shot(game, DIR .. "/bug722_1_battle.png")

  -- ---- win it ------------------------------------------------------------
  for _ = 1, 1200 do
    if battle.result then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("the battle was won", battle.result == "win")
  if battle.result ~= "win" then
    U.log("the party lost, so the aftermath never runs; nothing below applies")
    while true do coroutine.yield() end
  end

  -- The aftermath is queued, not run inline: the battle's own callbacks are
  -- still unwinding when engageTrainer's onDone fires, so it has to wait for
  -- an idle overworld frame (OverworldState:drainPendingScripts).
  local queued
  for _ = 1, 900 do
    local ow = game.overworld
    local pending = ow and ow.pendingScripts and ow.pendingScripts[1]
    if pending then queued = pending.script break end
    if game.stack:top() == ow and not (ow.runner and ow.runner:isRunning()) then
      -- already drained: nothing left to inspect
      break
    end
    U.tap(game, "a")
    U.wait(4)
  end
  check("the win queues an aftermath script (#722)", type(queued) == "table")
  if type(queued) == "table" then
    local problems = ScriptRunner.validate(queued)
    check("it validates: " .. (problems[1] or "no problems"), #problems == 0)
    local first, second, last = queued[1], queued[2], queued[#queued]
    check("row 1 is the Blast-it-all speech",
          first and first[1] == "show_text" and first[2] == SPEECH)
    check("row 2 fades out before anyone leaves",
          second and second[1] == "fade" and second[2] == "out")
    check("the last row fades back in",
          last and last[1] == "fade" and last[2] == "in")
    local hides, waits, sawWait = 0, 0, false
    for _, row in ipairs(queued) do
      if row[1] == "hide_object" then hides = hides + 1 end
      if row[1] == "wait" then waits = waits + 1 sawWait = true end
    end
    check(("all %d rockets leave behind the fade (found %d)")
            :format(HIDE_ROWS, hides), hides == HIDE_ROWS)
    check("Delay3 is held between the hides and the fade in",
          sawWait and waits >= 1)
  end

  -- ---- the loss line, then the speech ------------------------------------
  local sawLoss, sawSpeech = false, false
  for _ = 1, 600 do
    local box = topBox()
    if box then
      local txt = boxText(box)
      if txt:find("lost again", 1, true) then sawLoss = true end
      if txt:find("Blast it all", 1, true) and not sawSpeech then
        sawSpeech = true
        U.wait(60)   -- let the box finish typing before the capture
        if not U.shot(game, DIR .. "/bug722_2_speech.png") then
          U.log("the speech screenshot did not reach disk")
        end
      end
    end
    if sawSpeech and not topBox() then break end
    U.tap(game, "a")
    U.wait(6)
  end
  check("his \"Arrgh!! I lost again!?\" box came first", sawLoss)
  check("then the \"Blast it all!\" speech played", sawSpeech)

  -- ---- the fade ----------------------------------------------------------
  local sawFade, shotFade = false, false
  for _ = 1, 600 do
    local ow = game.overworld
    local overlay = ow and ow.fadeOverlay
    if overlay then
      sawFade = true
      if (overlay.alpha or 0) > 0.85 and not shotFade then
        shotFade = U.shot(game, DIR .. "/bug722_3_black.png")
      end
    end
    if sawFade and shotFade and (not overlay or (overlay.alpha or 0) < 0.05) then
      break
    end
    U.wait(1)
  end
  check("the screen faded to black over the departure", sawFade)

  for _ = 1, 240 do
    local ow = game.overworld
    if game.stack:top() == ow and not (ow.runner and ow.runner:isRunning()) then
      break
    end
    U.wait(1)
  end
  U.shot(game, DIR .. "/bug722_4_after.png")

  for _, name in ipairs(ELEVENTH) do
    check(name .. " left the floor", spawned(name) == nil)
  end
  check("EVENT_BEAT_SILPH_CO_GIOVANNI is set",
        game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI == true)
  local toggles = game.save.objectToggles[MAP] or {}
  check("the 11F toggles were written to the save",
        toggles.SILPHCO11F_GIOVANNI == false)
  local twoF = game.save.objectToggles.SILPH_CO_2F or {}
  check("the lower floors were cleared in the same pass",
        twoF.SILPHCO2F_ROCKET1 == false)

  U.log(("%d passed, %d failed"):format(pass, fail))
  if fail > 0 then
    U.log("something above failed, so what is on screen is not the fix")
  end

  -- ---- hand off ----------------------------------------------------------
  -- re-arm and park the player one cell below the pad so the whole thing can
  -- be watched again from a step and a mash
  armFight()
  U.teleport(game, MAP, TRIGGERS[1].stand[1], TRIGGERS[1].stand[2], "up")
  U.wait(10)

  U.log("fought giovanni on silph 11F and watched the aftermath once (#722).")
  U.log("walk up one cell and win again: he should say \"Arrgh!!\", then the")
  U.log("whole \"Blast it all!\" speech, and only then should the screen fade")
  U.log("out, the rockets vanish behind the black, and fade back in.  the")
  U.log("near miss to watch for is the room going quiet and empty with no")
  U.log("speech, or the rockets popping out in plain sight before the fade.")

  while true do
    coroutine.yield()
  end
end
