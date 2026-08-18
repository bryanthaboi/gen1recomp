-- data/moves/sfx.asm:46, data/moves/animations.asm:448, audio/engine_2.asm:1077
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local opts = game.save.options or {}
  check(("sfx volume %d (needs > 0 to hear anything)"):format(opts.sfxVol or 7),
        (opts.sfxVol or 7) > 0)
  check("battle animations are on", opts.animations ~= false)

  local mdef = game.data.moves.LEER
  check("LEER is in the move table", mdef ~= nil)
  local anim = mdef and mdef.anim
  check(("LEER maps to %s pitch %s tempo %s (wants Battle_31 255 64)"):format(
          anim and tostring(anim.sound) or "?",
          anim and tostring(anim.pitch) or "?",
          anim and tostring(anim.tempo) or "?"),
        anim ~= nil and anim.sound == "Battle_31"
          and anim.pitch == 255 and anim.tempo == 64)

  local lead = Pokemon.new(game.data, "CHARMANDER", 20)
  lead.moves = { { id = "LEER", pp = 30 } }
  game.save.party = { lead }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(15)
  local ow = game.overworld
  check("standing on ROUTE_1", ow.map.id == "ROUTE_1")

  local ChipAudio = require("src.core.ChipAudio")
  local renders = {}
  local origNewSfx = ChipAudio.newSfx
  ChipAudio.newSfx = function(data, name, pitch, tempo, header, plain)
    renders[#renders + 1] = { name = name, pitch = pitch, tempo = tempo,
                              plain = plain }
    return origNewSfx(data, name, pitch, tempo, header, plain)
  end

  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  local function waitPhase(phase, tries)
    for _ = 1, tries do
      if battle.phase == phase then return true end
      U.tap(game, "a")
      U.wait(6)
    end
    return battle.phase == phase
  end

  U.log("")
  U.log("LISTEN: the cart's LEER opens with a short PIERCING high tone")
  U.log("  (about a third of a second, while the seed-drop noise is still")
  U.log("  running) and only then falls to the slow low buzz.  Before the")
  U.log("  fix the recomp skipped the piercing part and played the whole")
  U.log("  sound as the low buzz.")
  U.log("")

  for round = 1, 3 do
    check(("round %d: menu is up"):format(round), waitPhase("menu", 150))
    U.tap(game, "a")
    check(("round %d: move list is up"):format(round),
          waitPhase("moveSelect", 12))
    U.tap(game, "a")
    U.wait(150)
    if round == 1 then U.shot(game, DIR .. "/bug1414_leer.png") end
  end

  ChipAudio.newSfx = origNewSfx
  local sawPlain, sawSeed = false, false
  for _, r in ipairs(renders) do
    if r.name == "Battle_31" and r.pitch == 255 and r.tempo == 64
       and (r.plain or 0) > 0 then
      sawPlain = true
    end
    if r.name == "Battle_1B" then sawSeed = true end
  end
  check("the seed-drop noise (Battle_1B) rendered", sawSeed)
  check("LEER's Battle_31 rendered with an unmodified opening"
          .. " while the noise still ran", sawPlain)
  for _, r in ipairs(renders) do
    U.log(("  rendered %s pitch=%s tempo=%s plainFrames=%s"):format(
            r.name, tostring(r.pitch), tostring(r.tempo), tostring(r.plain)))
  end

  U.log("done; the window stays open, pick LEER again to re-listen")
end
