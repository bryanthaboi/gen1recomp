-- #1441: the Magnet Train ride drew a flat white screen.
--
--   POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1441_test.lua love .
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1441   (default)
--
-- Nothing here is assertable: the bug IS what the screen shows.  The ride
-- bakes its background out of data.gen2Field.magnetTrain, TILESET_TRAIN_
-- STATION's sheet and the TOWN palettes, and every one of those was read
-- under its Gen 1 key, so all four came back nil and GbcPalette's fallback
-- filled the panel with DMG_SHADES[1].
--
-- The run boots into the Goldenrod station, prints whether the four tables
-- are actually there, shoots the Saffron-bound ride from JUMPTABLE_INIT
-- through to the arrival, then plays the Goldenrod-bound one back at 1x with
-- no screenshots in the way -- a human watching the window sees the whole
-- animation, which is the only place this bug ever showed.
local U = require("tests.drivers.util")

local STATION = "GOLDENROD_MAGNET_TRAIN_STATION"

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1441"

  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")
  world:setMap(STATION, 11, 8, "up")
  U.wait(10)

  local data = game.data or {}
  local field = data.gen2Field and data.gen2Field.magnetTrain
  U.log("gen2Field.magnetTrain:", field and #field.bgTiles or "MISSING")
  U.log("gen2Tilesets.TILESET_TRAIN_STATION:",
    data.gen2Tilesets and data.gen2Tilesets.TILESET_TRAIN_STATION
      and data.gen2Tilesets.TILESET_TRAIN_STATION.image or "MISSING")
  U.log("gen2Palettes:", data.gen2Palettes and "ok" or "MISSING")
  U.log("gen2Sprites.SPRITE_CHRIS:",
    data.gen2Sprites and data.gen2Sprites.SPRITE_CHRIS and "ok" or "MISSING")

  local done = false
  world:magnetTrain(true, function() done = true end)
  U.wait(2)

  local ride = game.stack:top()
  U.log("ride background:", ride and ride.background
    and (ride:background() and "baked" or "nil canvas") or "no screen")

  -- SFX_TRAIN_ARRIVED lands a good while in; shoot across the whole ride so
  -- the departure, the three scrolling bands and the stop are all on disk.
  for index = 0, 11 do
    U.shot(game, ("%s/%02d-ride.png"):format(out, index))
    U.wait(20)
    if done then break end
  end
  for _ = 1, 600 do
    if done then break end
    U.wait(5)
  end
  U.log("ride finished at frame", U.frame())
  U.log("shots in " .. out)

  -- The return leg, played out in full with nothing else on screen: watch the
  -- window, not the PNGs.  The ride reads no input, so it ends on its own.
  local back = false
  world:magnetTrain(false, function() back = true end)
  for _ = 1, 900 do
    if back then break end
    U.wait(1)
  end
  U.wait(60)
end
