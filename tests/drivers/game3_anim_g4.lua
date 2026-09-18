local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

local MOVES = {
  { "moves", 85, "thunderbolt", { 10, 24, 40 } },
  { "moves", 86, "thunder_wave", { 8, 20, 40 } },
  { "moves", 87, "thunder_bg", { 20, 45, 70 } },
  { "moves", 58, "ice_beam", { 12, 30, 55 } },
  { "moves", 59, "blizzard_bg", { 30, 60, 90 } },
  { "moves", 61, "bubblebeam", { 10, 25, 45 } },
  { "moves", 56, "hydro_pump", { 10, 25, 45 } },
  { "moves", 62, "aurora_beam", { 30, 50, 70 } },
  { "moves", 188, "sludge_bomb", { 10, 22, 40 } },
  { "moves", 42, "pin_missile", { 6, 12, 20 } },
  { "moves", 157, "rock_slide", { 10, 22, 36 } },
  { "moves", 155, "bonemerang", { 10, 20, 32 } },
  { "moves", 224, "megahorn", { 30, 50, 70 } },
  { "moves", 69, "seismic_toss_bg", { 30, 60, 100 } },
  { "moves", 81, "string_shot", { 10, 25, 45 } },
  { "moves", 90, "fissure_bg", { 25, 50, 80 } },
  { "moves", 123, "smog", { 10, 25, 45 } },
  { "moves", 139, "poison_gas", { 10, 30, 60 } },
  { "moves", 323, "water_spout", { 30, 60, 110 } },
  { "moves", 346, "water_sport", { 20, 50, 90 } },
  { "moves", 331, "bullet_seed_ctl", { 10, 20, 30 } },
  { "general", 4, "bait_throw", { 22, 40, 60 }, true },
  { "special", 1, "switch_out_player", { 4, 8, 12 } },
  { "special", 3, "ball_throw", { 20, 60, 110 } },
  { "general", 13, "hail_continues", { 20, 40, 70 } },
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

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 9, level = 30 }, { fade = false })
  result(ok == true, "g4 wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  for _ = 1, 1500 do
    if Ui._mode == "menu" then break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  result(Ui._mode == "menu", "g4 reached action menu")
  U.wait(10)

  Anim.scriptForMove(1)
  local vm = Anim.vm()
  local pack = Anim._pack
  result(pack ~= nil and pack.animBgs ~= nil, "g4 pack has animBgs")

  for _, m in ipairs(MOVES) do
    local kind, id, name, shots, safari = m[1], m[2], m[3], m[4], m[5]
    require("src.core.game3.battle.ball_open").reset()
    local tp = Anim.stage().trainer.player
    tp.visible, tp.frame, tp.ox = safari and true or false, 0, 0
    Anim.present("player").visible = true
    Anim.present("enemy").visible = true
    Anim.present("player").ox, Anim.present("player").oy = 0, 0
    Anim.present("enemy").ox, Anim.present("enemy").oy = 0, 0
    if safari then Anim.present("player").visible = false end
    local ended = false
    vm:launchTable(kind, id, {
      attackerSide = "player", targetSide = "enemy",
      attackerSpecies = 6, targetSpecies = 9,
      ctx = { ballThrowCaseId = 0, lastUsedItem = 4, movePower = 100, moveDamage = 40 },
      onEnd = function() ended = true end,
    })
    local f, si = 0, 1
    while not ended and f < 900 do
      U.wait(1)
      f = f + 1
      if shots[si] and f == shots[si] then
        U.shot(game, string.format("%s/g4_%s_%02d.png", DIR, name, si))
        si = si + 1
      end
    end
    result(ended, string.format("g4 %s[%d] %s ended in %d frames", kind, id, name, f))
    Anim.present("player").visible = true
    Anim.present("enemy").visible = true
    U.wait(20)
  end

  print(string.format("g4 driver done fails=%d", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
