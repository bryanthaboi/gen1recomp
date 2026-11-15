return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local fails = 0
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  local function waitFor(cond, n)
    for _ = 1, n or 900 do
      if cond() then return true end
      U.wait(1)
    end
    return false
  end
  local text = game.data.text

  U.newGame(game)
  game.save.party = { Pokemon.new(game.data, "BULBASAUR", 12) }
  U.teleport(game, "ROUTE_3", 10, 6, "RIGHT")
  U.wait(10)

  local battle = BattleState.newTrainer(game, "OPP_BUG_CATCHER", 4)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)
  local intro = text._TrainerWantsToFightText:gsub("{RAM:wTrainerName}", battle.trainer.name)
  check("the trainer intro is the cached _TrainerWantsToFightText", battle.introText == intro)
  check("intro reached the box", waitFor(function()
    return battle.current and battle.current.text == battle.introText
      and (battle.introSlide or 0) == 0 and (battle.charIndex or 0) >= (battle.total or 1)
  end))
  U.still(game, DIR .. "/rf4_01_trainer_wants_to_fight.png")

  check("battle menu reached", waitFor(function()
    if battle.phase == "menu" then return true end
    if battle.msgWaiting or battle.msgPrompt then U.tap(game, "a") end
    return false
  end, 1800))
  U.still(game, DIR .. "/rf4_02_battle_menu_rom_text.png")

  battle.menuIndex = 1
  U.tap(game, "a")
  check("move select opened", waitFor(function() return battle.phase == "moveSelect" end, 120))
  U.still(game, DIR .. "/rf4_03_move_select_type_text.png")

  local name = battle.enemy.name
  battle.enemy.rageMove = true
  battle.queue = {}
  battle:handleBuildingRage(battle.enemy)
  local said
  for _, item in ipairs(battle.queue) do if item.text then said = item.text end end
  check("the enemy prefix is the cached EnemyText",
    said ~= nil and said:find(text.EnemyText .. name, 1, true) == 1)
  battle.queue = {}

  print(("%s gen1_battle_text_rf4 failures=%d"):format(fails == 0 and "PASS" or "FAIL", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
