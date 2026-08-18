-- Driver: where the "Will PLAYER change POKéMON?" YES/NO box sits (#1398).
--
--   POKEPORT_DRIVER=tests/drivers/shift_prompt_box_bug1398_test.lua \
--     POKEPORT_IDENTITY=bug1398 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .
--
-- EnemySendOutFirstMon (engine/battle/core.asm:1378-1384) does NOT go through
-- InitYesNoTextBoxParameters for this one prompt: it inlines its own
-- TWO_OPTION_MENU at hlcoord 0,7, i.e. hard against the LEFT edge, while every
-- other YES/NO in the game sits at hlcoord 14,7 on the right.  The port only
-- had the shared right-hand box, so the SHIFT offer came up on the wrong side.
--
-- The run stops with the prompt on screen and the controls in a human's hands.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local Theme = require("src.ui.Theme")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- roster 1 is RATTATA 11 / EKANS 11: two mons, so the KO of the first one
  -- reaches EnemySendOutFirstMon with a reserve to announce.
  local OPP, ROSTER = "OPP_YOUNGSTER", 1

  check("trainer class " .. OPP .. " is in the data",
        game.data.trainers ~= nil and game.data.trainers[OPP] ~= nil)
  check("Theme carries the left-edge box",
        Theme.trainerSwitchBox ~= nil and Theme.trainerSwitchBox.tx == 0
          and Theme.trainerSwitchBox.ty == 7)

  -- SHIFT is what makes the prompt appear at all (the BIT_BATTLE_SHIFT test at
  -- core.asm:1375-1377 skips it under SET).
  game.save.options = game.save.options or {}
  game.save.options.battleStyle = "shift"
  game.save.player.name = "bryan"
  game.save.party = {
    Pokemon.new(game.data, "MEWTWO", 70),
    Pokemon.new(game.data, "CHARIZARD", 50),
  }

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)
  local ow = game.overworld
  check("overworld is up to push the battle from", ow ~= nil)

  local ok, battle = pcall(BattleState.newTrainer, game, OPP, ROSTER)
  check("trainer battle constructed", ok and battle ~= nil)
  if not ok then
    U.log("could not start", OPP, "->", tostring(battle))
    while true do coroutine.yield() end
  end
  check("the foe has a reserve to send out", #battle.enemyParty >= 2)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  local function tapUntil(cond, taps, gap)
    for _ = 1, (taps or 60) do
      if cond() then return true end
      U.tap(game, "a")
      for _ = 1, (gap or 6) do
        if cond() then return true end
        U.wait(1)
      end
    end
    return cond()
  end

  if not check("reached the FIGHT/PKMN/ITEM/RUN menu",
               tapUntil(function() return battle.phase == "menu" end, 200)) then
    U.log("phase is", tostring(battle.phase))
  end

  -- FIGHT, first move: L70 MEWTWO one-shots the L11 lead.
  U.tap(game, "a")
  U.wait(10)
  U.tap(game, "a")
  U.wait(10)

  -- Stop the moment the YES/NO goes up over the still-visible prompt page.
  local function choiceBox()
    local top = game.stack:top()
    return (top and top.tx and top.labels and top.labels[1] == "YES") and top
      or nil
  end
  local reached = tapUntil(function() return choiceBox() ~= nil end, 200, 4)
  if not check("the SHIFT prompt opened its YES/NO box", reached) then
    U.log("phase", tostring(battle.phase),
          "enemy hp", tostring(battle.enemy and battle.enemy.mon.hp),
          "top", tostring(game.stack:top()))
  end

  local box = choiceBox()
  if box then
    check("the box is at hlcoord 0,7 (core.asm:1378-1384)",
          box.tx == 0 and box.ty == 7)
    U.log("box tx=" .. tostring(box.tx) .. " ty=" .. tostring(box.ty))
    check("prompt screenshot reached disk",
          U.shot(game, DIR .. "/bug1398_shift_prompt.png"))
    U.log("captured", DIR .. "/bug1398_shift_prompt.png")
  end

  U.log("The foe's lead is down and the SHIFT offer is on screen.")
  U.log("YES/NO must sit against the LEFT edge, over the text box's left half,")
  U.log("not on the right where every other YES/NO in the game lives (#1398).")

  while true do
    coroutine.yield()
  end
end
