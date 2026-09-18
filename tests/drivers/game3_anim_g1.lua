local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_anim_g1"

local MOVES = {
  { 30, "HORN_ATTACK", { 8, 20, 30 } },
  { 29, "HEADBUTT", { 8, 16 } },
  { 47, "SING", { 30, 80 } },
  { 80, "PETAL_DANCE", { 20, 60 } },
  { 75, "RAZOR_LEAF", { 15, 45 } },
  { 345, "MAGICAL_LEAF", { 20, 40 } },
  { 73, "LEECH_SEED", { 20, 50 } },
  { 147, "SPORE", { 20, 60 } },
  { 63, "HYPER_BEAM", { 20, 40 } },
  { 182, "PROTECT", { 10, 30 } },
  { 199, "LOCK_ON", { 30, 60, 90 } },
  { 208, "MILK_DRINK", { 20, 60 } },
  { 236, "MOONLIGHT", { 30, 90 } },
  { 15, "CUT", { 6, 12 } },
  { 163, "SLASH", { 6 } },
  { 206, "FALSE_SWIPE", { 8, 20 } },
  { 102, "MIMIC", { 20, 40 } },
  { 275, "INGRAIN", { 20, 50 } },
  { 338, "FRENZY_PLANT", { 20, 40 } },
  { 271, "TRICK", { 20, 60 } },
  { 217, "PRESENT", { 20, 50 } },
  { 162, "SUPER_FANG", { 8 } },
  { 118, "METRONOME", { 20, 50 } },
  { 266, "FOLLOW_ME", { 20, 50 } },
  { 269, "TAUNT", { 20, 50 } },
  { 187, "BELLY_DRUM", { 20, 40 } },
  { 160, "CONVERSION", { 20, 60 } },
  { 176, "CONVERSION_2", { 20, 50 } },
  { 348, "LEAF_BLADE", { 10, 30 } },
  { 173, "SNORE", { 20 } },
  { 311, "WEATHER_BALL", { 10, 40 } },
  { 132, "CONSTRICT", { 10, 30 } },
  { 239, "TWISTER", { 20, 50 } },
  { 64, "PECK", { 6 } },
  { 159, "SHARPEN", { 20 } },
  { 203, "ENDURE", { 20 } },
  { 76, "SOLAR_BEAM", { 20, 40 }, 1 },
  { 244, "PSYCH_UP", { 20 } },
  { 109, "CONFUSE_RAY", { 20, 50 } },
  { 298, "TEETER_DANCE", { 20 } },
  { 185, "FAINT_ATTACK", { 30 } },
  { 315, "OVERHEAT", { 30, 60 } },
  { 41, "TWINEEDLE", { 10 } },
  { 238, "CROSS_CHOP", { 20 } },
  { 129, "SWIFT", { 10, 20 } },
  { 168, "THIEF", { 20, 40 } },
  { 282, "KNOCK_OFF", { 20, 40 } },
  { 97, "AGILITY", { 10, 30 } },
  { 104, "DOUBLE_TEAM", { 30, 60 } },
  { 148, "FLASH", { 10, 30 } },
  { 130, "SKULL_BASH", { 10, 30 }, 0 },
  { 183, "MACH_PUNCH", { 6, 12 } },
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
  result(ok == true, "g1 wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  local ready = false
  for _ = 1, 3000 do
    if Ui._mode == "menu" and not Anim.busy() then ready = true break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  result(ready, "g1 battle reached the action menu")
  if not ready then love.event.quit(1) return end
  U.wait(20)

  local st = Battle._st
  local pSpecies = st and st.player and (st.player.species or (st.player.mon and st.player.mon.species)) or 6
  local eSpecies = st and st.enemy and (st.enemy.species or (st.enemy.mon and st.enemy.mon.species)) or 9
  local only = os.getenv("G1_MOVES")
  local sides = os.getenv("G1_SIDES") or "player,enemy"

  local function runEntry(name, shots, side, launch)
    launch()
    local f, si = 0, 1
    while f < 1200 do
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
    result(vm and vm:idle(), string.format("%s (%s) finished in %d frames", name, side, f))
    for _, s in ipairs({ "player", "enemy" }) do
      local p = Anim.present(s)
      if p then
        p.visible = true
        p.ox, p.oy, p.sx, p.sy, p.rotation = 0, 0, 1, 1, 0
        p.blendCoeff = 0
      end
    end
    for _ = 1, 20 do U.wait(1) end
  end

  local function opts(side, turn)
    return {
      attackerSide = side,
      targetSide = side == "player" and "enemy" or "player",
      isReversed = side == "enemy",
      attackerSpecies = side == "player" and pSpecies or eSpecies,
      targetSpecies = side == "player" and eSpecies or pSpecies,
      moveTurn = turn or 0,
      turn = turn or 0,
    }
  end

  for _, entry in ipairs(MOVES) do
    if not only or only:find(entry[2], 1, true) then
      for side in sides:gmatch("[^,]+") do
        runEntry(entry[2], entry[3], side, function() Anim.launchMove(entry[1], opts(side, entry[4])) end)
      end
    end
  end

  if not only or only:find("CONFUSION", 1, true) then
    for side in sides:gmatch("[^,]+") do
      runEntry("STATUS_CONFUSION", { 20, 50 }, side, function() Anim.launchStatus(1, opts(side)) end)
    end
  end

  love.event.quit(fails == 0 and 0 or 1)
end
