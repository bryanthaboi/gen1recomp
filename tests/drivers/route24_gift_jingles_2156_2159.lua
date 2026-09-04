-- ../pokeyellow/scripts/Route24.asm:149-158
-- ../pokeyellow/engine/events/give_pokemon.asm:45-46
--   POKEPORT_DRIVER=tests/drivers/route24_gift_jingles_2156_2159.lua \
--     POKEPORT_IDENTITY=yellow-sep02 POKEPORT_VERSION=yellow POKEPORT_TOUCH=0 \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  U.newGame(game)
  local flags = game.save.flags
  flags.EVENT_GOT_NUGGET = nil
  flags.EVENT_BEAT_ROUTE24_ROCKET = nil
  flags.EVENT_54F = nil

  U.teleport(game, "ROUTE_24", 10, 16, "up")
  U.wait(30)
  U.shot(game, DIR .. "/route24_jingles_2156_2159.png")

  U.log("PASS setup: ROUTE_24 (10,16), nugget and Charmander quests cleared")
  U.log("#2156 step 1: press UP onto (10,15) -- the recruiter talks.")
  U.log("#2156 expect: the fanfare plays at the END of the")
  U.log("  'You beat our 5 contest trainers!' box, before the arrow.")
  U.log("#2156 expect: the NUGGET receipt box plays SFX_GET_KEY_ITEM on")
  U.log("  Yellow, SFX_GET_ITEM_1 on Red/Blue.")
  U.log("#2159 step 2: walk north to Damian and accept his CHARMANDER.")
  U.log("#2159 expect: 'got CHARMANDER!' + SFX_GET_ITEM_1 BEFORE the")
  U.log("  nickname prompt.")
end
