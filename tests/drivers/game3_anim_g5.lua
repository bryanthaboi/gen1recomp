local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"
local ONLY = os.getenv("G5_ONLY")

local SHOTS = { 12, 30, 55, 85, 120, 170, 230, 300 }

local MOVES = {
  { "moves", 213, "attract" },
  { "moves", 184, "scary_face" },
  { "moves", 234, "morning_sun" },
  { "general", 19, "doom_desire_hit" },
  { "moves", 334, "iron_defense_metal_shine" },
  { "moves", 287, "refresh_cure_bubbles" },
  { "moves", 312, "aromatherapy" },
  { "moves", 94, "psychic_bg" },
  { "moves", 174, "curse_lines", nil, 1 },
  { "moves", 114, "haze_fog" },
  { "moves", 296, "mist_ball_fog" },
  { "moves", 201, "sandstorm" },
  { "moves", 57, "surf" },
  { "moves", 330, "muddy_water" },
  { "moves", 91, "dig_turn1", nil, 0 },
  { "moves", 91, "dig_turn2", nil, 1 },
  { "moves", 108, "smokescreen" },
  { "moves", 182, "protect" },
  { "moves", 47, "sing_rainbow" },
  { "moves", 195, "perish_song" },
  { "moves", 199, "lock_on" },
  { "moves", 62, "aurora_beam" },
  { "moves", 115, "reflect" },
  { "moves", 113, "light_screen" },
  { "moves", 16, "gust" },
  { "moves", 215, "heal_bell" },
  { "general", 24, "ghost_get_out", "enemy" },
  { "status", 6, "frozen_ice_cube", "enemy" },
}

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
  local Ui = require("src.core.game3.battle.ui")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 6, 36)

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 9, level = 30 }, { fade = false })
  result(ok == true, "g5 wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  for _ = 1, 1500 do
    if Ui._mode == "menu" then break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  result(Ui._mode == "menu", "g5 reached action menu")
  U.wait(10)

  Anim.scriptForMove(1)
  local vm = Anim.vm()
  local pack = Anim._pack
  result(pack ~= nil and pack.animBgs ~= nil and pack.animBgs.ATTRACT ~= nil, "g5 pack has named anim BGs")
  result(pack ~= nil and pack.tags and pack.tags.PROTECT and pack.tags.PROTECT.idxFile ~= nil, "g5 pack has indexed tag sheets")

  for _, m in ipairs(MOVES) do
    local kind, id, name, atk, turn = m[1], m[2], m[3], m[4] or "player", m[5]
    if not ONLY or name:find(ONLY) then
      require("src.core.game3.battle.ball_open").reset()
      local tp = Anim.stage().trainer.player
      tp.visible, tp.frame, tp.ox = false, 0, 0
      for _, side in ipairs({ "player", "enemy" }) do
        local p = Anim.present(side)
        p.visible, p.invisible, p.ox, p.oy, p.alpha, p.hShift = true, false, 0, 0, 1, nil
      end
      local ended = false
      local tgt = (atk == "player") and "enemy" or "player"
      vm:launchTable(kind, id, {
        attackerSide = atk, targetSide = tgt,
        attackerSpecies = atk == "player" and 6 or 9, targetSpecies = atk == "player" and 9 or 6,
        moveTurn = turn or 0,
        ctx = { movePower = 100, moveDamage = 40 },
        onEnd = function() ended = true end,
      })
      local f, si = 0, 1
      while not ended and f < 900 do
        U.wait(1)
        f = f + 1
        if SHOTS[si] and f == SHOTS[si] then
          U.shot(game, string.format("%s/g5_%s_%02d.png", DIR, name, si))
          si = si + 1
        end
      end
      result(ended, string.format("g5 %s[%d] %s ended in %d frames", kind, id, name, f))
      for _, side in ipairs({ "player", "enemy" }) do
        local p = Anim.present(side)
        p.visible, p.invisible, p.ox, p.oy, p.alpha, p.hShift = true, false, 0, 0, 1, nil
      end
      U.wait(20)
    end
  end

  print(string.format("g5 driver done fails=%d", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
