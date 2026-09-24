-- Manual check that challenging a trainer by talking to them plays the
-- encounter sting (#764).  TalkToTrainer (pokered home/trainers.asm:88)
-- prints the before-battle text and then EngageMapTrainer ->
-- PlayTrainerMusic; the port only did that on the sight-line path, so a
-- trainer approached from the side or back went into battle in map music.
--   POKEPORT_DRIVER=tests/drivers/trainer_fanfare_bug764_test.lua POKEPORT_IDENTITY=bug764 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")

  -- data/maps/objects/ViridianForest.asm:32
  local MAP = "VIRIDIAN_FOREST"
  local TRAINER = "VIRIDIANFOREST_YOUNGSTER2"
  local STAND = { x = 30, y = 32, facing = "down" }

  local failed = false
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end

  -- record every song the engine starts; wrapping keeps real playback so
  -- the human half of this check still has something to hear
  local Music = require("src.core.Music")
  local played = {}
  local realPlay = Music.play
  Music.play = function(data, song, ...)
    played[#played + 1] = song
    return realPlay(data, song, ...)
  end

  check("new game reached the overworld", U.newGame(game))
  check("music volume is audible (save.options.musicVol)",
        (game.save.options.musicVol or 0) > 0)

  local Pokemon = require("src.pokemon.Pokemon")
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 30, function(_, b) return b end) }

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(90)

  local ow = game.overworld
  local npc
  for _, n in ipairs(ow and ow.npcs or {}) do
    if n.def and n.def.name == TRAINER then npc = n end
  end
  check("Bug Catcher object loaded on " .. MAP, npc ~= nil)
  check(string.format("teleport kept the stand cell (%d,%d)", STAND.x, STAND.y),
        ow.player.cellX == STAND.x and ow.player.cellY == STAND.y)
  if npc then
    check("standing on his blind side, facing him",
          ow:npcAtCell(ow.player:facingCell()) == npc)
    check("he did not spot us on the way in", not ow.engaging)
  end

  -- home/trainers.asm:109
  played = {}
  U.tap(game, "a")
  U.wait(30)
  check("no sting while the dialogue is up", #played == 0)
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  U.shot(game, SHOT_DIR .. "/764_bugcatcher_talk_dialogue.png")

  -- home/trainers.asm:123
  local sting
  for _ = 1, 8 do
    U.tap(game, "a")
    U.wait(30)
    for _, song in ipairs(played) do
      if song:find("Music_Meet", 1, true) then sting = song end
    end
    if sting then break end
  end
  check("the last page started an encounter sting", sting ~= nil)
  check("it is the male trainer sting", sting == "Music_MeetMaleTrainer")
  U.still(game, SHOT_DIR .. "/764_bugcatcher_sting_last_page.png")
  U.log("songs started since the A press:", table.concat(played, ", "))

  -- home/text_script.asm:93
  U.tap(game, "a")
  local left = false
  for _ = 1, 300 do
    U.wait(1)
    if game.stack:top() ~= ow then left = true break end
  end
  check("A on the last page opens the battle", left)

  U.log("The male trainer sting should begin as the Bug Catcher's last page")
  U.log("(\"Let's battle 'em!\") lands, before A is pressed, and carry into")
  U.log("the battle transition.  Before #764 the forest theme played straight")
  U.log("through into the fight.")

  love.event.quit(failed and 1 or 0)
end
