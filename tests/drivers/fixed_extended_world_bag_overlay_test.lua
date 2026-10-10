-- Visual regression coverage for Professor Oak's scripted Yellow capture Bag
-- over the WIDE + FIXED + EXTENDED + WORLD composition.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")

  love.window.setMode(2048, 1152, { resizable = true })
  U.wait(3)

  local options = game.save.options
  options.battleLayout = "wide"
  options.battleFit = "fixed"
  options.battleHud = "extended"
  options.battleBg = "world"

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 20) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(30)

  local demo = BattleState.newWild(game, "CHARMANDER", 5)
  demo:makeOldManDemo("oak")
  demo.onFinish = function() end
  game.overworld:pushBattle(demo)

  for _ = 1, 100 do
    if demo.phase == "menu" and (demo.demoTimer or 0) > 5 then break end
    U.tap(game, "a")
    U.wait(4)
  end
  for _ = 1, 180 do
    if game.stack:top() ~= demo then break end
    U.wait(1)
  end
  U.wait(3)

  local path = DIR .. "/fixed_extended_world_oak_charmander_bag.png"
  os.remove(path)
  local ok = game.stack:top() ~= demo and U.shot(game, path)
  U.log(ok and "FIXED_EXTENDED_WORLD_BAG_PASS"
           or "FIXED_EXTENDED_WORLD_BAG_FAIL")
  love.event.quit(ok and 0 or 1)
end
