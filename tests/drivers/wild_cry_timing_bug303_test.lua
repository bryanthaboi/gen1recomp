-- Manual listening test for issue #303 ("Wild Pokemon's cry plays later
-- than intended").
--
-- Symptom: entering a wild battle, the enemy cry did not sound with the
-- "Wild X appeared!" box.  It only fired once the player pressed A to
-- clear that box, so the cry landed on top of "Go! CHARMANDER!".
--
-- Cause: BattleState:enter queued the cry in the block it SHARED with the
-- trainer and link branches, i.e. after self:say(self.introText).  The
-- battle message queue is strictly serial -- BattleState:updateQueue will
-- not pull the next row while self.current is set, and a text row clears
-- self.current only on A/B -- so the cry act could not run until the intro
-- box was dismissed.  The fix queues the cry per branch, ahead of the say
-- on the wild path.
--
-- pokered: PrintBeginningBattleText (engine/battle/common_text.asm) takes
-- the wild path through `call PlayCry` and only then reaches `call
-- PrintText` with WildMonAppearedText, whose _WildMonAppearedText
-- (data/text/text_2.asm:1236-1241) ends in `prompt`.  Cry first, button
-- wait after.  Trainer and link battles keep the opposite order on purpose
-- (EnemySendOutFirstMon, engine/battle/core.asm:1421-1434: PrintText, then
-- AnimateSendingOutMon, then PlayCry), so this driver exercises only the
-- wild path; hearing a trainer's mon cry after its send-out text is
-- correct, not a regression.
--
-- This is an audio bug, so nothing here can assert it: the driver parks a
-- human at the exact moment and then hands the pad back.  It deliberately
-- never presses A (the whole point is hearing the cry BEFORE any A press)
-- and must run at real speed, so do not set POKEPORT_SPEED.
--
-- Run:
--   POKEPORT_IDENTITY=bug303 \
--     POKEPORT_DRIVER=tests/drivers/wild_cry_timing_bug303_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local BattleState = require("src.battle.BattleState")

  -- a healthy lead, or BattleState.newWild finds no Party.firstHealthy,
  -- sets self.dead and pops straight back out of enter()
  game.save.party = { Pokemon.new(game.data, "CHARMANDER", 12) }

  -- VIRIDIAN_FOREST, the south-west grass patch (cells 1-5 x 40-43).  The
  -- forced encounter below is one this map really rolls: PIKACHU is grass
  -- slots 9 and 10 in both versions (data/wild/maps/ViridianForest.asm),
  -- and its cry is the one a listener is least likely to mistake for an
  -- SFX or for the battle theme's first bar.  The corner also sits clear
  -- of the forest's Bug Catchers, whose sight lines would otherwise open a
  -- trainer battle -- the branch whose cry order is deliberately unchanged.
  U.teleport(game, "VIRIDIAN_FOREST", 3, 42, "down")
  local ow = game.overworld

  -- Gate the encounter on the player rather than on a frame count: an
  -- audio test is worthless if the cry fires while they are still reaching
  -- for the headphones.  TextBox pops itself on A and then calls onDone.
  local ready = false
  game.stack:push(TextBox.new(game, "Cry timing test.\nPress A to start!",
                              function() ready = true end))
  U.log("issue #303 -- wild cry timing, MANUAL listening test")
  U.log("nothing here asserts; your ears are the verdict")
  U.log("press A in the game window when you are ready to listen")
  while not ready do U.wait(1) end
  U.wait(10)

  local battle = BattleState.newWild(game, "PIKACHU", 5)
  -- the real encounter path (OverworldState:checkEncounter) hands the
  -- result to afterBattle, which is what heals, blacks out and offers
  -- evolutions; keep it so the hand-off below leaves a normal game behind
  battle.onFinish = function(result) ow:afterBattle(result, battle) end

  U.log("LISTEN: PIKACHU's cry should sound the instant the battle screen")
  U.log("        wipes in, under the 'Wild PIKACHU appeared!' box, while")
  U.log("        it types out and BEFORE you press anything")
  U.log("BROKEN:  that box is silent, and the cry only arrives after your")
  U.log("        A press, over 'Go! CHARMANDER!'")
  -- pushBattle starts the battle theme and the wipe first
  -- (audio/play_battle_music.asm runs before the transition), so the cry
  -- is a beat away, not immediate
  ow:pushBattle(battle)

  -- mark the moment in the terminal so the log line and the sound line up
  for _ = 1, 600 do
    if game.stack:top() == battle then break end
    U.wait(1)
  end
  U.log("battle up: the cry belongs to THIS box, not the one after A")

  -- popup_fake_save hand-off: never touch input again, so the player owns
  -- the A press that clears the intro box.  Another listen costs nothing:
  -- run or win, then pace the grass tuft for a fresh wild roll (the forest
  -- rate is 8/256 a step, so re-running this driver is the quicker repeat).
  while true do
    coroutine.yield()
  end
end
