-- Driver: dual-screen (DS-style) layout. World pass on the top screen, UI
-- pass (menu, dialog, battle) on the bottom. During a battle the top screen
-- holds the frozen last overworld frame.
--   POKEPORT_IDENTITY=ds-shots POKEPORT_DRIVER=tests/drivers/dualscreen_test.lua \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")

  game.save.options.dualScreen = true
  game:applyOptions(game.save.options)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(30)
  U.shot(game, DIR .. "/ds_0_overworld.png")

  -- START menu: overworld stays on the top screen, the menu lands below
  U.tap(game, "start")
  U.wait(12)
  U.shot(game, DIR .. "/ds_1_menu.png")
  U.tap(game, "b")
  U.wait(6)

  -- battle: top screen freezes the last overworld frame, battle draws below
  table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 12))
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(20)
  U.shot(game, DIR .. "/ds_2_prebattle.png")
  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)
  U.wait(40)
  U.shot(game, DIR .. "/ds_3_battle_intro.png")
  for _ = 1, 12 do U.tap(game, "a"); U.wait(6) end
  U.shot(game, DIR .. "/ds_4_battle_menu.png")

  game.save.options.dualScreen = false
  game:applyOptions(game.save.options)
end
