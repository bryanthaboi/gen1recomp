-- home/text.asm:506 (#1952/#2087, #1990/#1991/#1997)
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Growth = require("src.pokemon.Growth")
  local BattleState = require("src.battle.BattleState")
  local Sound = require("src.core.Sound")

  game.speedOverride = 4

  local squirtle = Pokemon.new(game.data, "SQUIRTLE", 5, function(_, b) return b end)
  local def = game.data.pokemon.SQUIRTLE
  squirtle.exp = Growth.expForLevel(def.growthRate, 6, game.data.growth_rates) - 1
  game.save.party = { squirtle }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local battle = BattleState.newWild(game, "SLOWPOKE", 2)
  battle.onFinish = function() end
  battle.rng = function(a, _) return a end
  battle.enemy.mon.hp = 1
  battle.enemy.mon.stats.speed = 1
  ow:pushBattle(battle)

  U.log("logic speed", game:logicSpeed(), "sfx rate", Sound.rate())
  if Sound.rate() ~= 1 then
    error(("bug1952: Game:update pitched SFX off GAME SPEED (rate %s at 4X)")
      :format(tostring(Sound.rate())))
  end

  for _ = 1, 240 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(3)
  end
  if battle.phase ~= "menu" then error("bug1952: never reached the FIGHT menu") end

  U.tap(game, "a")
  for _ = 1, 60 do
    if battle.phase == "moveSelect" then break end
    U.wait(1)
  end
  if battle.phase ~= "moveSelect" then error("bug1952: never reached move select") end
  U.tap(game, "a")

  local t0, dur, pitch, held
  local shot = false
  for _ = 1, 1200 do
    U.wait(1)
    if battle.waitingSound and not t0 then
      local src = battle.waitingSound
      t0 = love.timer.getTime()
      local okd, d = pcall(src.getDuration, src)
      local okp, p = pcall(src.getPitch, src)
      dur = okd and d or nil
      pitch = okp and p or nil
      if pitch and pitch ~= 1 then
        error(("bug1952: the level-up fanfare was pitched with GAME SPEED (%s)")
          :format(tostring(pitch)))
      end
      if not shot then
        shot = U.shot(game, DIR .. "/bug1952_fanfare.png")
      end
    elseif t0 and not battle.waitingSound and not held then
      held = love.timer.getTime() - t0
      break
    end
    U.tap(game, "a")
  end

  if not t0 then error("bug1952: the level-up fanfare never armed the gate") end
  if not held then error("bug1952: the fanfare gate never released") end

  U.log(("fanfare duration %.3fs pitch %s held %.3fs"):format(
    dur or -1, tostring(pitch), held))
  U.shot(game, DIR .. "/bug1952_after.png")

  if not dur then error("bug1952: no duration for the level-up fanfare") end
  if held < dur * 0.9 then
    error(("bug2087: the 4X battle cut the fanfare short (%.3fs of %.3fs)")
      :format(held, dur))
  end
  if held > dur + 1 then
    error(("bug1952: the fanfare dragged past its length (%.3fs of %.3fs)")
      :format(held, dur))
  end
  U.log("PASS the fanfare kept natural pitch and played to completion at 4X")
  love.event.quit(0)
end
