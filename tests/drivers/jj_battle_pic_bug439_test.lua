-- Eye check on the enemy pic in the Mt Moon Jessie & James fight (#439).
-- pokeyellow home/trainers2.asm:36-50 IsFightingJessieJames points
-- wTrainerPicPointer at JessieJamesPic when ROCKET fights with wTrainerNo
-- >= $2a, leaving GetTrainerName alone.  Needs a Yellow cache re-imported
-- after #439.  No POKEPORT_SPEED: the theme sting rides the audio clock.
--   POKEPORT_VERSION=yellow POKEPORT_DRIVER=tests/drivers/jj_battle_pic_bug439_test.lua POKEPORT_IDENTITY=bug439 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local GameVersion = require("src.core.GameVersion")
  local CacheFs = require("src.import.CacheFs")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- pokeyellow data/maps/objects/MtMoonB2F.asm parks JESSIE at (9, 3) and
  -- JAMES at (9, 4); MtMoonB2FScript's coordinate trigger is the (3, 5) tile
  -- west of them, reachable from (3, 6) once a fossil is in the bag.
  local MAP = "MT_MOON_B2F"
  local TRIGGER = { x = 3, y = 5 }
  local BEAT = "EVENT_BEAT_MT_MOON_3_JESSIE_JAMES"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- what the eye cannot check -----------------------------------------
  local opts = game.save.options or {}
  local sfxVol = opts.sfxVol or 7
  if sfxVol == 0 then
    U.log("FAIL sfx volume is 0: the theme sting that opens the ambush is")
    U.log("     silent, so the scene's audio half cannot be judged. Set SFX")
    U.log("     to 7 in OPTION first.")
  end
  check(("sfx volume %d"):format(sfxVol), sfxVol > 0)

  check("running Yellow", GameVersion.isYellow())
  local trainer = game.data.trainers.OPP_ROCKET
  check("OPP_ROCKET is in the trainer table", trainer ~= nil)
  trainer = trainer or {}
  check("the name is still ROCKET, as GetTrainerName leaves it",
        trainer.name == "ROCKET")
  -- a Yellow cache built before #439 has no duo pic at all, and every check
  -- below it would then be measuring the old grunt-only behaviour
  if not trainer.picJessieJames then
    U.log("FAIL the Yellow cache predates #439: no duo pic was extracted.")
    U.log("     Re-import the Yellow ROM from the launcher, then run again.")
  end
  check("the cache carries a duo pic", trainer.picJessieJames ~= nil)
  if trainer.picJessieJames then
    check("the duo pic file is on the read path",
          CacheFs.exists(trainer.picJessieJames)
          or love.filesystem.getInfo(trainer.picJessieJames) ~= nil)
  end
  local picked = BattleState.trainerPicPath(trainer, "OPP_ROCKET", 42)
  U.log("pic:", tostring(picked))
  check("party 42 selects the duo pic", picked == trainer.picJessieJames)
  check("a lone grunt party still selects the class pic",
        BattleState.trainerPicPath(trainer, "OPP_ROCKET", 3) == trainer.pic)

  -- ---- reach the ambush ---------------------------------------------------
  -- one strong mon so the fight is survivable if the reader plays it out
  game.save.party = { Pokemon.new(game.data, "MEWTWO", 100) }
  game.save.flags[BEAT] = nil
  game.save.flags.EVENT_GOT_HELIX_FOSSIL = true

  U.teleport(game, MAP, TRIGGER.x, TRIGGER.y + 1, "up")
  local ow = game.overworld
  U.hold(game, "up", 20)
  U.wait(10)
  if not ow.runner:isRunning() then
    -- a map or mod edit blocked the approach from below: come down onto the
    -- trigger from whichever free walkable neighbour is left
    local sides = {
      { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = TRIGGER.x + s[1], TRIGGER.y + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("approach from below failed, stepping in from", cx, cy)
        U.teleport(game, MAP, cx, cy, s[3])
        ow = game.overworld
        U.hold(game, s[3], 20)
        U.wait(10)
        if ow.runner:isRunning() then break end
      end
    end
  end
  check("the ambush script is running", ow.runner:isRunning())
  U.shot(game, DIR .. "/jj439_0_trigger.png")

  -- A-mash the motto and the challenge line until the battle is pushed, then
  -- stop: the trainer pic stays up until the intro text is dismissed
  local battle = nil
  for _ = 1, 1200 do
    local top = game.stack:top()
    if getmetatable(top) == BattleState then
      battle = top
      break
    end
    U.tap(game, "a")
    U.wait(3)
  end
  check("the ambush opened a battle", battle ~= nil)
  if battle then
    for _ = 1, 240 do
      if battle.showEnemyTrainer and (battle.introSlide or 0) <= 0 then break end
      U.wait(1)
    end
    check("the enemy trainer pic is on screen", battle.showEnemyTrainer == true)
    U.shot(game, DIR .. "/jj439_1_intro.png")
    U.wait(40)
    U.shot(game, DIR .. "/jj439_2_intro_late.png")
    U.log("intro text:", tostring(battle.introText))
  end

  U.log("Both intro shots must show the two-character duo pic: a woman on the")
  U.log("left and a man on the right, one 7x7 pic, no Meowth -- not the single")
  U.log("crouching ROCKET grunt. The name in the intro line stays ROCKET.")
  U.log("The theme under the trigger shot is Music_MeetJessieJames.")

  while true do
    coroutine.yield()
  end
end
