-- Driver: the starter Pikachu's battle entrance (#1429).
--
--   POKEPORT_DRIVER=tests/drivers/pikachu_entrance_bug1429_test.lua \
--     POKEPORT_VERSION=yellow POKEPORT_IDENTITY=bug1429 POKEPORT_TOUCH=0 \
--     SHOT_DIR=/tmp/shots love .   (never under POKEPORT_SPEED: audio-timed)
--
-- SendOutMon branches on IsThisPartyMonStarterPikachu (pokeyellow
-- engine/battle/core.asm:1798-1819): the starter never gets POOF_ANIM or
-- AnimateSendingOutMon.  It walks in instead --
-- StarterPikachuBattleEntranceAnimation (engine/battle/pikachu_entrance_anim.asm)
-- paints the back pic one column at a time from hlcoord 0,5, eight columns two
-- frames apart, and only then does PlayPikachuSoundClip voice it.
--
-- The run halts in the middle of the walk-in, then again on the finished pic.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local GameVersion = require("src.core.GameVersion")
  local PF = require("src.world.PikachuFollower")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  check("running as Yellow (needs POKEPORT_VERSION=yellow)",
        GameVersion.isYellow())

  game.save.player.name = "bryan"
  local pika = Pokemon.new(game.data, "PIKACHU", 20)
  BattleState.stampOT(game.save, pika)
  game.save.party = { pika, Pokemon.new(game.data, "CHARMANDER", 20) }
  check("the lead reads as the starter Pikachu",
        PF.isStarterPikachu(game.save, pika))

  U.teleport(game, "ROUTE_1", 5, 20, "down")
  U.wait(20)
  local ow = game.overworld
  check("overworld is up to push the battle from", ow ~= nil)

  local battle = BattleState.newWild(game, "PIDGEY", 5)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  local function tapUntil(cond, taps, gap)
    for _ = 1, (taps or 90) do
      if cond() then return true end
      U.tap(game, "a")
      for _ = 1, (gap or 4) do
        if cond() then return true end
        U.wait(1)
      end
    end
    return cond()
  end

  -- Poll every frame: the slide is 16 frames long and the ball poof, if the
  -- bug were back, would never set this slot at all.
  local sliding = tapUntil(function()
    return battle.picOff ~= nil and battle.picOff.playerMon ~= nil
  end, 120, 2)
  check("the send-out started the entrance slide, not the ball poof", sliding)
  check("no grow-in is running alongside it", battle.growIn == nil)

  if sliding then
    U.log("slide x =", tostring(battle.picOff.playerMon.x))
    check("mid-slide screenshot reached disk",
          U.shot(game, DIR .. "/bug1429_pikachu_sliding.png"))
    U.log("captured", DIR .. "/bug1429_pikachu_sliding.png")
    for _ = 1, 40 do
      if battle:picOffset("playerMon") == 0 then break end
      U.wait(1)
    end
    check("the pic landed on its own column", battle:picOffset("playerMon") == 0)
    check("landed screenshot reached disk",
          U.shot(game, DIR .. "/bug1429_pikachu_landed.png"))
    U.log("captured", DIR .. "/bug1429_pikachu_landed.png")
  end

  U.log("Pikachu should have walked in from the LEFT edge of the screen,")
  U.log("column by column, with no ball, no poof and no grow-out-of-the-ball,")
  U.log("and voiced its PCM clip only once it was fully drawn (#1429).")

  while true do
    coroutine.yield()
  end
end
