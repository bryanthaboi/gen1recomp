-- Hands-on check for #487: walk pacing after a map-connection seam.
-- Parks the player in Viridian City's south exit column (pokered
-- data/maps/objects/ViridianCity.asm, border block $f, south connection to
-- Route 1) so DOWN alone crosses into ROUTE_1, then gives input back.
--   POKEPORT_DRIVER=tests/drivers/route1_seam_pacing_bug487_test.lua POKEPORT_IDENTITY=bug487 POKEPORT_TOUCH=0 love .
-- Never add POKEPORT_SPEED: fast-forward scales the logic clock only, so it
-- reorders audio against logic and hides the very wobble being judged.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local FrameCap = require("src.core.FrameCap")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Viridian City is 20x18 blocks == 40x36 cells; the exit path south runs
  -- down column cellX 20 to the bottom row cellY 35, where crossConnection
  -- (src/world/OverworldController.lua) swaps in ROUTE_1 and calls
  -- FixedStep:discardCatchup -- the only caller, which is why #487 showed up
  -- at route/city seams and nowhere else.  Warps take the Transition path
  -- instead, so a Viridian door is the control case.
  local MAP, EXIT_X, START_Y = "VIRIDIAN_CITY", 20, 31

  local maps = game.data.maps
  local vc, r1 = maps and maps[MAP], maps and maps.ROUTE_1
  check("VIRIDIAN_CITY and ROUTE_1 are both in data/generated/maps.lua",
        vc ~= nil and r1 ~= nil)
  check("Viridian's south connection still points at Route 1",
        vc ~= nil and vc.connections and vc.connections.south
          and vc.connections.south.map == "ROUTE_1")

  -- the door the human re-checks afterwards: ViridianCity.asm warp_event
  -- 21, 15 -> VIRIDIAN_SCHOOL_HOUSE
  local doorOk = false
  for _, w in ipairs((vc and vc.warps) or {}) do
    if w.x == 21 and w.y == 15 then doorOk = true end
  end
  check("the school house door at (21, 15) is still a warp", doorOk)

  -- Judging pacing needs real frame times, and main.lua's driver branch feeds
  -- Game:update a pinned 1/60 so the accumulator never sees display jitter.
  -- Under POKEPORT_DRIVER this is expected to read FAIL: the position below
  -- is still useful, the verdict has to come from a plain run.
  check("the running build feeds FixedStep real frame times",
        os.getenv("POKEPORT_DRIVER") == nil)
  check("no fast-forward multiplier is set",
        (tonumber(os.getenv("POKEPORT_SPEED")) or 1) == 1
          and (game.save.options.speedOverworld or 1) == 1
          and (game.save.options.speedBattle or 1) == 1
          and (game.save.options.speedMenu or 1) == 1)
  check("a window is up to watch (this is a visual call)",
        love.window ~= nil and love.window.isOpen and love.window.isOpen())
  U.log("MAX FPS reads", FrameCap.label(game.save.options.fpsCap),
        "and vsync is",
        (love.window.getVSync and tostring(love.window.getVSync())) or "unknown")

  -- Probe copy of the timing module so the reseed can be asserted without
  -- disturbing the live loop this driver is running inside.  discardCatchup
  -- still zeroes accum on the way out; the fix is that the frame absorbing
  -- the hitch hands it back mid-step instead of parked on a step boundary.
  local probe = loadfile("src/core/FixedStep.lua")()
  probe:init(function() end)
  probe:discardCatchup()
  probe:update(0.25)
  check("an absorbed hitch frame leaves the accumulator mid-step",
        probe.accum > probe.STEP * 0.25 and probe.accum < probe.STEP * 0.75)

  -- a party and the starter flag so the overworld behaves like a real save
  game.save.flags.EVENT_GOT_STARTER = true
  if #game.save.party == 0 then
    local Pokemon = require("src.pokemon.Pokemon")
    table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))
  end

  U.teleport(game, MAP, EXIT_X, START_Y, "down")
  local ow = game.overworld

  -- a map edit or a mod could block column 20; walk down whichever nearby
  -- column is clear all the way to the bottom row instead
  local function columnIsClear(x)
    for y = START_Y, 35 do
      if not ow.map:isWalkableCell(x, y) then return false end
    end
    return true
  end
  local col = EXIT_X
  if not columnIsClear(col) then
    for _, dx in ipairs({ -1, 1, -2, 2, -3, 3 }) do
      if columnIsClear(EXIT_X + dx) then col = EXIT_X + dx break end
    end
    U.log(("column %d is blocked, using column %d"):format(EXIT_X, col))
    U.teleport(game, MAP, col, START_Y, "down")
    ow = game.overworld
  end
  check("the exit column is walkable from here to the south edge",
        columnIsClear(col))

  -- cross it once so the seam is known reachable from this cell, then come
  -- back and leave the player a few steps short of it
  local crossed = false
  for _ = 1, 200 do
    table.insert(game.input.pressQueue, "down")
    game.input.state.down = true
    coroutine.yield()
    if ow.map.id == "ROUTE_1" and ow.player.cellY >= 0 then crossed = true break end
  end
  game.input.state.down = false
  U.wait(5)
  check("holding DOWN from that cell reaches Route 1", crossed)

  U.teleport(game, MAP, col, START_Y, "down")
  U.wait(10)

  U.log(("Standing in Viridian City at cell (%d, %d), four steps above the"):format(col, START_Y))
  U.log("Route 1 seam.  Hold DOWN and keep holding it for about ten seconds")
  U.log("once you are on Route 1: past the single hitch on the crossing frame")
  U.log("the scroll should stay dead even, a pixel a frame, the same as the")
  U.log("walk through the city.  Broken, the sprite stalls for a frame then")
  U.log("jumps two pixels, again and again, and never settles down.  The easy")
  U.log("misread is grading the crossing frame itself: that one hitch is")
  U.log("expected and this change does not touch it, so watch the seconds")
  U.log("after.  Then step into the school house door at (21, 15) to confirm")
  U.log("warps look the way they always did, and run the walk once more with")
  U.log("MAX FPS set to 30 in Options, where the wobble also showed up.")

  while true do
    coroutine.yield()
  end
end
