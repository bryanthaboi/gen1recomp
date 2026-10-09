local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_anim_shadow_ball_layer"

-- pokefirered/include/constants/moves.h:251
local MOVE_SHADOW_BALL = 247

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Anim = require("src.core.game3.battle.anim")
  local AnimSprites = require("src.core.game3.battle.anim_sprites")
  local AnimCoords = require("src.core.game3.battle.anim_coords")
  local Ui = require("src.core.game3.battle.ui")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 94, 40)

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 9, level = 30 }, { fade = false })
  result(ok == true, "wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  for _ = 1, 1500 do
    if Ui._mode == "menu" then break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  result(Ui._mode == "menu", "reached action menu")
  U.wait(10)

  Anim.scriptForMove(1)
  local vm = Anim.vm()
  local ended = false
  vm:launchTable("moves", MOVE_SHADOW_BALL, {
    attackerSide = "player", targetSide = "enemy",
    attackerSpecies = 94, targetSpecies = 9,
    ctx = { movePower = 80, moveDamage = 40 },
    onEnd = function() ended = true end,
  })

  local ball, shots, f = nil, 0, 0
  while not ended and f < 900 do
    U.wait(1)
    f = f + 1
    if not ball then
      for i = 1, AnimSprites.MAX do
        local s = AnimSprites._pool[i]
        if s.active and s._op and s._op.callback == "ShadowBall" then ball = s end
      end
      if ball then
        local z = ball._pz and AnimCoords.layerZ(ball.subpriority) or ball.z
        -- pokefirered/data/battle_anim_scripts.s:7481
        result(z < AnimCoords.monBehindZ("player"), "shadow ball under the player back sprite (z=" .. tostring(z) .. ")")
        result(z > AnimCoords.monBehindZ("enemy"), "shadow ball over the enemy (z=" .. tostring(z) .. ")")
      end
    end
    if ball and shots < 3 and f % 3 == 0 then
      shots = shots + 1
      U.still(game, string.format("%s/shadow_ball_leaving_attacker_%d.png", DIR, shots))
    end
  end
  result(ball ~= nil, "shadow ball sprite appeared")
  result(ended, "shadow ball anim ended in " .. f .. " frames")

  print(string.format("shadow_ball_layer fails=%d", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
