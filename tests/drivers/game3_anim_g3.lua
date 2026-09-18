local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_anim_g3"

local MOVES = {
  { 109, "CONFUSE_RAY", { 20, 60, 110, 140 } },
  { 247, "SHADOW_BALL", { 22, 38, 48 } },
  { 122, "LICK", { 18, 24, 40 } },
  { 174, "CURSE", { 8, 16, 60, 150, 300 } },
  { 101, "NIGHT_SHADE", { 20, 40, 80, 110 } },
  { 288, "GRUDGE", { 20, 40, 60 } },
  { 180, "SPITE", { 30, 80, 130 } },
  { 171, "NIGHTMARE", { 20, 50, 75 } },
  { 194, "DESTINY_BOND", { 30, 60, 90 } },
  { 212, "MEAN_LOOK", { 30, 70, 100 } },
  { 108, "SMOKESCREEN", { 20, 40, 60 } },
  { 43, "LEER", { 8, 14 } },
  { 158, "HYPER_FANG", { 10, 20, 30 } },
  { 227, "ENCORE", { 20, 50, 80 } },
  { 229, "RAPID_SPIN", { 10, 25, 40 } },
  { 161, "TRI_ATTACK", { 20, 60, 100 } },
  { 273, "WISH", { 20, 50, 80 } },
  { 234, "MORNING_SUN", { 30, 80, 130 } },
  { 230, "SWEET_SCENT", { 30, 70, 110 } },
  { 260, "FLATTER", { 30, 70, 110 } },
  { 281, "YAWN", { 20, 50, 80 } },
  { 309, "METEOR_MASH", { 15, 30, 45 } },
  { 282, "KNOCK_OFF", { 8, 16, 30 } },
  { 44, "BITE", { 6, 14, 22 } },
  { 232, "METAL_CLAW", { 10, 30, 50 } },
  { 262, "MEMENTO", { 20, 60, 120, 180 } },
  { 185, "FAINT_ATTACK", { 10, 40, 70, 100 } },
  { 113, "LIGHT_SCREEN", { 10, 30, 50 } },
  { 134, "KINESIS", { 20, 50, 80 } },
  { 133, "AMNESIA", { 10, 30 } },
  { 285, "SKILL_SWAP", { 20, 60, 100 } },
  { 326, "EXTRASENSORY", { 20, 50, 80 } },
  { 354, "PSYCHO_BOOST", { 30, 70, 120 } },
  { 286, "IMPRISON", { 20, 50, 80 } },
  { 100, "TELEPORT", { 10, 25, 40 } },
  { 45, "GROWL", { 8, 16, 30 } },
  { 191, "SPIKES", { 15, 30, 45 } },
  { 278, "RECYCLE", { 15, 40, 70 } },
  { 335, "BLOCK", { 15, 40 } },
  { 170, "MIND_READER", { 15, 40, 70 } },
  { 313, "FAKE_TEARS", { 15, 40, 70 } },
  { 193, "FORESIGHT", { 15, 40, 70 } },
  { 270, "HELPING_HAND", { 15, 40, 70 } },
  { 265, "SMELLING_SALT", { 15, 40, 70 } },
  { 316, "ODOR_SLEUTH", { 15, 40, 70 } },
  { 151, "ACID_ARMOR", { 20, 50, 90 } },
  { 272, "ROLE_PLAY", { 20, 40, 60 } },
  { 220, "PAIN_SPLIT", { 15, 40, 70 } },
  { 204, "CHARM", { 15, 40, 70 } },
  { 263, "FACADE", { 15, 40, 70 } },
  { 140, "BARRAGE", { 15, 30, 50 } },
  { 298, "TEETER_DANCE", { 15, 40, 70 } },
  { 137, "GLARE", { 15, 40, 70 } },
  { 287, "REFRESH", { 15, 40, 70 } },
  { 303, "SLACK_OFF", { 15, 40, 70 } },
  { 256, "SWALLOW", { 15, 40, 70 } },
  { 96, "MEDITATE", { 15, 40, 70 } },
  { 115, "REFLECT", { 15, 40, 70 } },
  { 175, "FLAIL", { 15, 30, 45 } },
  { 164, "SUBSTITUTE", { 15, 40, 60 } },
  { 144, "TRANSFORM", { 20, 50, 80 } },
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
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 4, 30)

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 92, level = 30 }, { fade = false })
  result(ok == true, "g3 wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  local ready = false
  for _ = 1, 3000 do
    if Ui._mode == "menu" and not Anim.busy() then ready = true break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  result(ready, "g3 battle reached the action menu")
  if not ready then love.event.quit(1) return end
  U.wait(20)

  local st = Battle._st
  local pSpecies = st and st.player and (st.player.species or (st.player.mon and st.player.mon.species)) or 4
  local eSpecies = st and st.enemy and (st.enemy.species or (st.enemy.mon and st.enemy.mon.species)) or 92
  local only = os.getenv("G3_MOVES")

  local function runMove(entry, side)
    local id, name, shots = entry[1], entry[2], entry[3]
    local opts = {
      attackerSide = side,
      targetSide = side == "player" and "enemy" or "player",
      isReversed = side == "enemy",
      attackerSpecies = side == "player" and pSpecies or eSpecies,
      targetSpecies = side == "player" and eSpecies or pSpecies,
    }
    Anim.launchMove(id, opts)
    local f, si = 0, 1
    local maxF = 900
    while f < maxF do
      if shots[si] and f >= shots[si] then
        U.shot(game, string.format("%s/%s_%s_%03d.png", DIR, name:lower(), side, shots[si]))
        f = f + 2
        si = si + 1
      else
        U.wait(1)
        f = f + 1
      end
      if not Anim.busy() and not shots[si] then break end
    end
    local vm = Anim.vm()
    local done = vm and vm:idle()
    result(done, string.format("%s (%s) finished in %d frames", name, side, f))
    for _ = 1, 20 do U.wait(1) end
    for _, sd in ipairs({ "player", "enemy" }) do
      local p = Anim.present(sd)
      if p then
        p.visible, p.alpha, p.ox, p.oy = true, 1, 0, 0
        p.sx, p.sy, p.rotation = 1, 1, 0
        p.blendCoeff, p.grayscale, p.hShift = 0, nil, nil
      end
    end
    Anim._bgBlend = nil
  end

  for _, entry in ipairs(MOVES) do
    if not only or only:find(entry[2], 1, true) then
      runMove(entry, "player")
      runMove(entry, "enemy")
    end
  end

  love.event.quit(fails == 0 and 0 or 1)
end
