-- Gold VOID FILL (#1418): FADE (each map's own border, dissolving across a
-- boundary), WATER, TREES, or BLACK.  Parks you on Cherrygrove zoomed out so
-- the void is most of the window, cycles the four modes, then hands the pad
-- over.  Do not add POKEPORT_SPEED: the water anim and the dissolve both run
-- on the real clock.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold \
--     POKEPORT_DRIVER=tests/drivers/gold_void_fill_bug1418_test.lua love .

local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-void-fill"
  local BorderFill = require("src.world.gen2.BorderFill")
  local Tilt = require("src.render.Tilt")
  local Zoom = require("src.render.Zoom")
  local failures = 0

  local function ok(label, condition, detail)
    if condition then
      print("[void] ok   " .. label)
    else
      failures = failures + 1
      print("[void] FAIL " .. label .. " " .. tostring(detail))
    end
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  -- Cherrygrove's header border is water ($35).  FADE shows that water,
  -- TREES replaces it, BLACK drops the sheet.  attributes.asm:123.
  world:setMap("CHERRYGROVE_CITY", 22, 16, "down")
  U.wait(10)

  Zoom.offset = -3
  world:rebuildNeighbors()
  world:rebuildPeople({ seamless = true })
  Tilt.setLevel(3)
  for _ = 1, 40 do
    Tilt.update(1 / 60)
    U.wait(1)
  end

  local function show(mode, file, label)
    BorderFill.setVoidFill(mode)
    if game.options then game.options.voidFill = mode end
    if game.save and game.save.options then
      game.save.options.voidFill = mode
    end
    U.wait(8)
    ok(label, BorderFill.voidFill == mode, BorderFill.voidFill)
    U.shot(game, out .. "/" .. file)
  end

  show("fade", "01-fade.png", "FADE is the live fill")
  show("water", "02-water.png", "WATER forces the water block")
  show("trees", "03-trees.png", "TREES forces the tree wall")
  show("black", "04-black.png", "BLACK drops the tiled void")
  show("fade", "05-fade-again.png", "and FADE restores the map's own border")

  Tilt.setLevel(0)
  Zoom.offset = 0
  world:rebuildNeighbors()
  world:rebuildPeople({ seamless = true })

  if failures > 0 then
    print(("[driver] FAIL gold void fill: %d check(s)"):format(failures))
    return
  end
  print("[driver] PASS gold void fill in " .. out)
  U.log("cycled fade/water/trees/black on cherrygrove (#1418).")
  U.log("OPTION > VOID FILL, zoom out (-) to see the void.")

  while true do
    coroutine.yield()
  end
end
