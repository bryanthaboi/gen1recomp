local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_anim_g2"

local MOVES = {
  { 19, "FLY", { 6, 14, 24 }, 0 },
  { 19, "FLY", { 8, 16, 24 }, 1 },
  { 340, "BOUNCE", { 6, 16 }, 0 },
  { 340, "BOUNCE", { 6, 12 }, 1 },
  { 291, "DIVE", { 10, 30 }, 0 },
  { 143, "SKY_ATTACK", { 30, 60 }, 1 },
  { 16, "GUST", { 10, 30, 50 } },
  { 17, "WING_ATTACK", { 8, 16, 24 } },
  { 177, "AEROBLAST", { 20, 40 } },
  { 297, "FEATHER_DANCE", { 30, 60, 100 } },
  { 18, "WHIRLWIND", { 10, 30 } },
  { 65, "DRILL_PECK", { 10, 24 } },
  { 349, "DRAGON_DANCE", { 20, 50, 80 } },
  { 200, "OUTRAGE", { 20, 50, 90 } },
  { 82, "DRAGON_RAGE", { 10, 30 } },
  { 225, "DRAGON_BREATH", { 10, 25 } },
  { 126, "FIRE_BLAST", { 12, 30, 60 } },
  { 7, "FIRE_PUNCH", { 10, 30 } },
  { 52, "EMBER", { 10, 20 } },
  { 261, "WILL_O_WISP", { 20, 50, 80 } },
  { 284, "ERUPTION", { 30, 60, 100 } },
  { 257, "HEAT_WAVE", { 20, 60 } },
  { 238, "CROSS_CHOP", { 10, 25 } },
  { 5, "MEGA_PUNCH", { 10, 30 } },
  { 26, "JUMP_KICK", { 6, 16 } },
  { 27, "ROLLING_KICK", { 8, 20 } },
  { 23, "STOMP", { 8, 16 } },
  { 280, "BRICK_BREAK", { 10, 30, 50 } },
  { 276, "SUPERPOWER", { 40, 150, 200 } },
  { 327, "SKY_UPPERCUT", { 20, 40 } },
  { 264, "FOCUS_PUNCH", { 10, 30 } },
  { 292, "ARM_THRUST", { 6, 14 } },
  { 279, "REVENGE", { 10, 30 } },
  { 146, "DIZZY_PUNCH", { 10, 30 } },
  { 14, "SWORDS_DANCE", { 10, 30 } },
  { 6, "PAY_DAY", { 10, 30 } },
  { 12, "GUILLOTINE", { 8, 30 } },
  { 11, "VICE_GRIP", { 6, 12 } },
  { 49, "SONIC_BOOM", { 6, 14 } },
  { 13, "RAZOR_WIND", { 20, 40 }, 0 },
  { 314, "AIR_CUTTER", { 20, 40 } },
  { 110, "WITHDRAW", { 12, 40 } },
  { 107, "MINIMIZE", { 16, 40 } },
  { 50, "DISABLE", { 40, 60 } },
  { 150, "SPLASH", { 10, 20 } },
  { 166, "SKETCH", { 40, 90, 140 } },
  { 304, "HYPER_VOICE", { 10, 30 } },
  { 253, "UPROAR", { 10, 30 } },
  { 135, "SOFT_BOILED", { 20, 60, 100 } },
  { 245, "EXTREME_SPEED", { 20, 40 } },
  { 215, "HEAL_BELL", { 30, 60 } },
  { 252, "FAKE_OUT", { 3, 8, 12 } },
  { 213, "ATTRACT", { 40, 90 } },
  { 184, "SCARY_FACE", { 20, 40 } },
  { 237, "HIDDEN_POWER", { 20, 50 } },
  { 195, "PERISH_SONG", { 30, 90, 150 } },
  { 186, "SWEET_KISS", { 20, 50 } },
  { 142, "LOVELY_KISS", { 20, 50 } },
  { 154, "FURY_SWIPES", { 4, 10 } },
  { 165, "STRUGGLE", { 10, 30 } },
  { 331, "BULLET_SEED", { 10, 20 } },
  { 204, "CHARM", { 20, 40 } },
  { 37, "THRASH", { 10, 30 } },
  { 134, "KINESIS", { 10, 30 } },
  { 207, "SWAGGER", { 10, 40 } },
  { 219, "SAFEGUARD", { 10, 30 } },
  { 255, "SPIT_UP", { 10, 20 } },
  { 137, "GLARE", { 10, 30 } },
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
  Party.giveMon(session, 6, 36)

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 9, level = 36 }, { fade = false })
  result(ok == true, "g2 wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  local ready = false
  for _ = 1, 3000 do
    if Ui._mode == "menu" and not Anim.busy() then ready = true break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  result(ready, "g2 battle reached the action menu")
  if not ready then love.event.quit(1) return end
  U.wait(20)

  local st = Battle._st
  local pSpecies = st and st.player and (st.player.species or (st.player.mon and st.player.mon.species)) or 6
  local eSpecies = st and st.enemy and (st.enemy.species or (st.enemy.mon and st.enemy.mon.species)) or 9
  local only = os.getenv("G2_MOVES")
  local sides = os.getenv("G2_SIDES") or "player,enemy"

  local AnimSprites = require("src.core.game3.battle.anim_sprites")
  local AnimTasks = require("src.core.game3.battle.anim_tasks")
  local P = require("src.core.game3.battle.anim_port.g2_pret")
  local function g2_active()
    local hit = false
    AnimSprites.forEachActive(function(s)
      if s.callback == P.runner and not s.invisible then hit = true end
    end)
    if hit then return true end
    AnimTasks.init()
    for i = 1, AnimTasks.MAX do
      local t = AnimTasks._pool[i]
      if t.active and t.g2 then return true end
    end
    return false
  end

  local function runMove(entry, side)
    local id, name, shots, turn = entry[1], entry[2], entry[3], entry[4]
    local opts = {
      attackerSide = side,
      targetSide = side == "player" and "enemy" or "player",
      isReversed = side == "enemy",
      attackerSpecies = side == "player" and pSpecies or eSpecies,
      targetSpecies = side == "player" and eSpecies or pSpecies,
      moveTurn = turn or 0,
      turn = turn or 0,
    }
    Anim.launchMove(id, opts)
    local f, si = 0, 1
    local maxF = 1200
    local tag = turn and ("t" .. turn) or ""
    local first = nil
    local auto = { 2, 10, 20, 35 }
    while f < maxF do
      if not first and g2_active() then first = f end
      local due = first and auto[si] and f >= first + auto[si]
      if due then
        U.shot(game, string.format("%s/%s%s_%s_%03d.png", DIR, name:lower(), tag, side, f))
        f = f + 2
        si = si + 1
      else
        U.wait(1)
        f = f + 1
      end
      if not Anim.busy() then break end
    end
    result(first ~= nil, string.format("%s%s (%s) ran a G2 port (first at %s)", name, tag, side, tostring(first)))
    local vm = Anim.vm()
    local done = vm and vm:idle()
    result(done, string.format("%s%s (%s) finished in %d frames", name, tag, side, f))
    for _, s in ipairs({ "player", "enemy" }) do
      local p = Anim.present(s)
      if p and not turn then
        result(p.visible ~= false, string.format("%s%s (%s) leaves %s mon visible", name, tag, side, s))
      end
      if p then
        p.visible = true
        p.ox, p.oy, p.sx, p.sy, p.rotation = 0, 0, 1, 1, 0
        p._g2bx, p._g2by, p.hShift, p.grayscale = nil, nil, nil, nil
      end
    end
    for _ = 1, 20 do U.wait(1) end
  end

  for _, entry in ipairs(MOVES) do
    if not only or only:find(entry[2], 1, true) then
      for side in sides:gmatch("[^,]+") do
        runMove(entry, side)
      end
    end
  end

  love.event.quit(fails == 0 and 0 or 1)
end
