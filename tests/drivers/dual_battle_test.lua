-- Driver: DUAL SCREEN battle.  Opens a wild battle, asserts the 160x288
-- stacked surface, and captures the command screen, the move menu and a
-- send-out POOF so the field/menu split and animation seams are visible.
--   DISPLAY=:1 SDL_VIDEODRIVER=x11 POKEPORT_IDENTITY=ds-shots POKEPORT_TOUCH=0 \
--     SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/dual_battle_test.lua \
--     POKEPORT_SPEED=8 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  local Renderer = require("src.render.Renderer")

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  game.save.options.dualScreen = true
  game:applyOptions(game.save.options)
  game.save.party = { Pokemon.new(game.data, "SQUIRTLE", 5) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(30)
  U.shot(game, DIR .. "/db_0_overworld.png")

  local battle = BattleState.newWild(game, "PIDGEY", 3, { onFinish = function() end })
  game.overworld:pushBattle(battle)
  U.wait(360)

  check("the battle is on top", getmetatable(game.stack:top()) == BattleState)
  check("the battle asked for the 160x288 stacked surface",
        Renderer.uiWidth == 160 and Renderer.uiHeight == 288)

  battle.introSlide = 0
  battle.introBalls = nil
  battle.showEnemyTrainer = false
  battle.showPlayerBack = false
  battle.enemySendingOut = false
  battle.sendingOut = false
  battle.phase = "menu"
  battle.menuIndex = 1
  U.wait(2)
  check("command screenshot", U.shot(game, DIR .. "/db_1_command.png"))

  battle.phase = "moveSelect"
  battle.moveIndex = 1
  U.wait(2)
  check("move menu screenshot", U.shot(game, DIR .. "/db_2_moves.png"))

  -- an opaque menu opened over the battle (the BAG / PARTY) collapses the
  -- 160x288 surface to 160x144; the fight must stay frozen on the top screen
  -- while the menu takes the bottom
  battle.phase = "menu"
  local Font = require("src.render.Font")
  local overlay = { isOpaque = true }
  function overlay:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw("BAG", 64, 64)
    love.graphics.setColor(1, 1, 1, 1)
  end
  game.stack:push(overlay)
  U.wait(6)
  check("overlay is on top, battle beneath", game.stack:top() == overlay)
  check("bag screenshot", U.shot(game, DIR .. "/db_4_bag.png"))
  game.stack:pop()
  U.wait(4)

  battle.phase = "messages"
  battle.current = nil
  if battle.animPlayer then
    battle.animPlayer:start("POOF_ANIM", false)
    battle.animPlayer.stepIndex = 3
    battle.animPlaying = true
  end
  U.wait(2)
  check("send-out POOF screenshot", U.shot(game, DIR .. "/db_3_poof.png"))
  battle.animPlaying = false

  U.log("RESULT", failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
  love.event.quit(failures == 0 and 0 or 1)
end
