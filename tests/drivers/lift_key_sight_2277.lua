-- pokeyellow/scripts/RocketHideoutB4F.asm:401, home/trainers.asm:341
--   POKEPORT_IDENTITY=yellow-sep04 POKEPORT_VERSION=yellow POKEPORT_TOUCH=0 \
--   POKEPORT_SHOT_DIR=.bazinga/BSA/09-16-26-00-standard/shots \
--   POKEPORT_DRIVER=tests/drivers/lift_key_sight_2277.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
                   or "/tmp/shots"

  local failures = 0
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function bail()
    U.log(failures == 0 and "DRIVER PASS" or "DRIVER FAIL", failures, "failure(s)")
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  local MAP = "ROCKET_HIDEOUT_B4F"
  local TEXT = "TEXT_ROCKETHIDEOUTB4F_ROCKET"
  local BALL = "ROCKETHIDEOUTB4F_LIFT_KEY"

  local GameVersion = require("src.core.GameVersion")
  if not check("running on Yellow", GameVersion.isYellow()) then bail() end

  local function npcNamed(ow, name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
  end
  local function gruntIn(ow)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.text == TEXT then return n end
    end
  end

  local Pokemon = require("src.pokemon.Pokemon")
  game.save.party = { Pokemon.new(game.data, "MEWTWO", 80) }
  game.save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY = nil
  if game.save.objectToggles then game.save.objectToggles[MAP] = nil end

  U.teleport(game, MAP, 14, 6, "up")
  U.wait(10)
  local ow = game.overworld
  local grunt = gruntIn(ow)
  if not check("the Yellow grunt is on B4F", grunt ~= nil) then bail() end
  U.log(("grunt at (%d, %d) facing %s")
          :format(grunt.cellX, grunt.cellY, tostring(grunt.facing)))
  check("the LIFT KEY ball starts hidden", npcNamed(ow, BALL) == nil)

  local waypoints = { { 14, grunt.cellY + 1 }, { grunt.cellX, grunt.cellY + 1 } }
  for _, wp in ipairs(waypoints) do
    for _ = 1, 10 do
      local p = game.overworld.player
      if game.overworld.engaging or game.overworld.emote then break end
      if p.cellX == wp[1] and p.cellY == wp[2] then break end
      U.log(("player at (%d, %d) heading for (%d, %d)")
              :format(p.cellX, p.cellY, wp[1], wp[2]))
      if p.cellY > wp[2] then U.hold(game, "up", 16)
      elseif p.cellY < wp[2] then U.hold(game, "down", 16)
      elseif p.cellX > wp[1] then U.hold(game, "left", 16)
      else U.hold(game, "right", 16) end
      U.wait(4)
    end
  end

  local sighted = false
  for _ = 1, 120 do
    ow = game.overworld
    if ow.engaging or ow.emote then sighted = true break end
    U.wait(1)
  end
  if not check("he spots the player and engages on sight", sighted) then bail() end

  local BattleState = require("src.battle.BattleState")
  local fought = false
  for _ = 1, 90 do
    if getmetatable(game.stack:top()) == BattleState then fought = true break end
    U.tap(game, "a")
    U.wait(8)
  end
  if not check("the walk-up runs into the battle", fought) then bail() end

  local won = false
  for _ = 1, 600 do
    if getmetatable(game.stack:top()) ~= BattleState then won = true break end
    U.tap(game, "a")
    U.wait(10)
  end
  if not check("the battle ends", won) then bail() end

  for _ = 1, 60 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "a")
    U.wait(8)
  end
  U.wait(30)

  ow = game.overworld
  check("EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_2 is set",
        game.save.flags.EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_2 == true)
  local dropped = game.save.flags.EVENT_ROCKET_DROPPED_LIFT_KEY == true
  check("the sight win sets EVENT_ROCKET_DROPPED_LIFT_KEY (#2277)", dropped)
  local ball = npcNamed(ow, BALL)
  check("the LIFT KEY ball is spawned on the floor", ball ~= nil)
  if ball then
    U.log(("ball at (%d, %d)"):format(ball.cellX, ball.cellY))
  end

  if not U.shot(game, SHOT_DIR .. "/2277_01_lift_key_ball_after_sight_battle.png") then
    failures = failures + 1
  else
    U.log("captured", SHOT_DIR .. "/2277_01_lift_key_ball_after_sight_battle.png")
  end

  U.log("Right: after the grunt's SIGHT battle the POKE BALL is on the floor")
  U.log("to his left, with no second conversation.  Wrong is an empty cell.")
  bail()
end
