local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")

return function(game)
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local function fail(msg)
    error("FAIL speed lock: " .. msg, 0)
  end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 6)
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then return fail("gold world did not boot") end

  game.speedOverride = nil
  game.options.speed = 10
  U.wait(2)
  if game:logicSpeed() ~= 10 then
    return fail(("overworld at GAME SPEED 10 reads %s"):format(tostring(game:logicSpeed())))
  end
  U.log("overworld logic speed", game:logicSpeed())

  local player = Mon.new(game.data, "CYNDAQUIL", 10)
  game.save.party = { player }
  local wild = Mon.new(game.data, "PIDGEY", 2)
  if not world:startBattle({ wild = wild }) then return fail("startBattle failed") end

  local battle
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.battle then battle = top break end
    U.wait(1)
  end
  if not battle then return fail("battle screen never came up") end

  local function inBattle()
    for _, st in ipairs(game.stack.states) do
      if st == battle then return true end
    end
    return false
  end

  local checked, shot = 0, false
  for _ = 1, 2000 do
    if not inBattle() then break end
    if game:logicSpeed() ~= 10 then
      return fail(("local battle ran at %sX with GAME SPEED 10"):format(tostring(game:logicSpeed())))
    end
    checked = checked + 1
    if checked == 30 then
      game.linkNet = { closed = false }
      game.speedOverride = 200
      if game:logicSpeed() ~= 1 then
        return fail("a link battle was not locked to 1X")
      end
      game:_cycleSpeed(1)
      if game.options.speed ~= 10 then
        return fail(("speed press in a link battle moved GAME SPEED to %s"):format(tostring(game.options.speed)))
      end
      game.speedOverride = nil
      game.linkNet = nil
    end
    if battle.phase == "menu" and not shot then
      shot = U.shot(game, DIR .. "/gold_battle_speed.png")
    end
    if battle.battle and battle.battle.over then
      tap("a", 3)
    elseif battle.phase == "menu" then
      tap("a", 4)
      tap("a", 4)
    else
      tap("a", 3)
    end
  end
  if inBattle() then
    local top = game.stack:top()
    return fail(("battle never ended (phase %s, over %s, top %s)"):format(
      tostring(battle.phase), tostring(battle.battle and battle.battle.over),
      tostring(top and (top.screenId or top.name) or top)))
  end
  U.log("battle frames checked at 10X", checked)
  U.wait(30)
  if game:logicSpeed() ~= 10 then
    return fail(("after the battle logic speed is %s, want 10"):format(tostring(game:logicSpeed())))
  end
  game.linkNet = { closed = false }
  if game:logicSpeed() ~= 1 then return fail("an open linkNet did not lock 1X") end
  game.linkNet = nil
  game.linkSession = true
  if game:logicSpeed() ~= 1 then return fail("a linkSession did not lock 1X") end
  game.linkSession = nil
  U.shot(game, DIR .. "/gold_after_battle.png")
  U.log("PASS gold local battle at GAME SPEED 10, link locked to 1X")
  love.event.quit(0)
end
