return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local function fail(msg)
    error("FAIL speed lock: " .. msg, 0)
  end
  local function key(k)
    love.keypressed(k, k, false)
    love.keyreleased(k, k)
  end

  local squirtle = Pokemon.new(game.data, "SQUIRTLE", 30, function(_, b) return b end)
  game.save.party = { squirtle }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local o = game.save.options
  game.speedOverride = nil
  o.speedOverworld, o.speedBattle, o.speedMenu = 10, 4, 1
  U.wait(2)
  if game:logicSpeed() ~= 10 then
    fail(("overworld at OVERWORLD SPEED 10 reads %s"):format(tostring(game:logicSpeed())))
  end
  U.log("overworld logic speed", game:logicSpeed())

  local battle = BattleState.newWild(game, "RATTATA", 2)
  battle.onFinish = function() end
  battle.enemy.mon.hp = 1
  ow:pushBattle(battle)

  local function inBattle()
    for _, st in ipairs(game.stack.states) do
      if st == battle then return true end
    end
    return false
  end

  for _ = 1, 600 do
    if inBattle() then break end
    U.wait(1)
  end
  if not inBattle() then fail("the battle never reached the stack") end

  local checked, shot = 0, false
  for _ = 1, 2400 do
    if not inBattle() then break end
    if game:logicSpeed() ~= 4 then
      fail(("local battle ran at %sX with speedBattle 4"):format(tostring(game:logicSpeed())))
    end
    checked = checked + 1
    if checked == 20 then
      game.linkSession = true
      key("1")
      game:gamepadaxis(nil, "triggerright", 1)
      game:gamepadaxis(nil, "triggerright", 0)
      if o.speedOverworld ~= 10 or o.speedBattle ~= 4 or o.speedMenu ~= 1 then
        fail(("speed presses in a link battle changed options (%s/%s/%s)"):format(
          tostring(o.speedOverworld), tostring(o.speedBattle), tostring(o.speedMenu)))
      end
      game.speedOverride = 200
      if game:logicSpeed() ~= 1 then fail("a link battle was not locked to 1X") end
      game.speedOverride = nil
      game.linkSession = nil
    end
    if battle.phase == "menu" and not shot then
      shot = U.shot(game, DIR .. "/red_battle_speed.png")
    end
    U.tap(game, "a")
    U.wait(2)
  end
  if inBattle() then fail("battle never ended") end
  U.log("battle frames checked at 4X", checked)
  U.wait(10)
  if game:logicSpeed() ~= 10 then
    fail(("after the battle logic speed is %s, want 10"):format(tostring(game:logicSpeed())))
  end
  game.linkSession = true
  if game:logicSpeed() ~= 1 then fail("a link session did not lock 1X") end
  game.linkSession = nil
  U.shot(game, DIR .. "/red_after_battle.png")
  U.log("PASS red local battle at BATTLE SPEED 4, link locked to 1X")
  love.event.quit(0)
end
