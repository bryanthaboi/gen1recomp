-- scripts/SSAnneCaptainsRoom.asm:5-10,45-68
--   POKEPORT_SHOT_DIR=/tmp/shots POKEPORT_VERSION=yellow \
--     POKEPORT_DRIVER=tests/drivers/ss_anne_captain_2189.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Music = require("src.core.Music")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
                   or "/tmp/shots"
  local failed = false
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end
  local function quit()
    U.wait(2)
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end

  local MAP = "SS_ANNE_CAPTAINS_ROOM"

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.player.name = "bryan"
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_HM01 = nil
  game.save.flags.EVENT_RUBBED_CAPTAINS_BACK = nil

  U.teleport(game, MAP, 4, 3, "up")
  U.wait(20)

  local ow = game.overworld
  if not check("captain's room loaded", ow and ow.map and ow.map.id == MAP) then
    quit()
  end
  check("the map script set the no-face bit", ow.noNpcFacePlayer == true)

  local captain
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def and npc.def.sprite == "SPRITE_CAPTAIN" then captain = npc end
  end
  captain = captain or (ow.npcs and ow.npcs[1])
  if not check("the captain is on the map", captain ~= nil) then quit() end
  check("he starts facing up", captain.facing == "up")

  U.tap(game, "a")
  U.wait(20)
  local box = game.stack:top()
  check("talking to him opens a text box", box ~= ow)
  check("and he keeps his back to the player", captain.facing == "up")
  U.shot(game, SHOT_DIR .. "/2189_01_captain_back_turned.png")

  local jingle = false
  for _ = 1, 20 do
    if Music.oneShotPlaying() then jingle = true break end
    U.tap(game, "a")
    for _ = 1, 40 do
      if Music.oneShotPlaying() then break end
      U.wait(1)
    end
  end
  jingle = jingle or Music.oneShotPlaying()
  check("MUSIC_PKMN_HEALED plays", jingle)
  check("the rub box is still up while it plays", game.stack:top() ~= ow)
  check("and he is still facing up", captain.facing == "up")
  U.shot(game, SHOT_DIR .. "/2189_02_rub_box_holds_jingle.png")

  for _ = 1, 1200 do
    if not Music.oneShotPlaying() then break end
    U.wait(1)
  end

  for _ = 1, 400 do
    if game.stack:top() == ow then break end
    U.tap(game, "a")
    U.wait(6)
  end
  check("the conversation closes", game.stack:top() == ow)
  check("HM01 handed over", game.save.flags.EVENT_GOT_HM01 == true)
  check("EVENT_RUBBED_CAPTAINS_BACK set",
        game.save.flags.EVENT_RUBBED_CAPTAINS_BACK == true)
  U.wait(10)
  check("and only now does he turn around", captain.facing == "down")
  U.shot(game, SHOT_DIR .. "/2189_03_captain_turned_after_rub.png")

  quit()
end
