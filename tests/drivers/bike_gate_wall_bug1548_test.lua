-- scripts/Route16Gate1F.asm:38 / home/overworld.asm:1224
-- data/maps/force_bike_surf.asm:5
--   POKEPORT_DRIVER=tests/drivers/bike_gate_wall_bug1548_test.lua \
--   POKEPORT_IDENTITY=bug1548 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
-- Watch the sprite after each teleport: it must never overlap the gate
-- building's black outline.  Compare .bazinga/august21p2/media/1548-1.jpg.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local OverworldState = require("src.world.OverworldController")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end

  local function settle()
    for _ = 1, 12 do
      if game.stack:top() == game.overworld then break end
      U.tap(game, "a")
      U.wait(25)
    end
    U.wait(60)
  end
  local function landed()
    local ow = game.overworld
    local p = ow.player
    return p.cellX, p.cellY, ow.map:isWalkableCell(p.cellX, p.cellY)
  end
  local function bikeless()
    game.save.inventory.BICYCLE = nil
    game.save.onBike, game.save.forcedBike = false, nil
  end

  game.save.player.name = "PROBE"
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  bikeless()

  local fm = game.data.field.forcedMovement
  check("field.forcedMovement carries the Route 16 cells",
        fm and fm.tiles and fm.tiles.ROUTE_16 ~= nil)

  for _, c in ipairs({ { "ROUTE_16", 17, 10 }, { "ROUTE_16", 17, 11 },
                       { "ROUTE_18", 33,  8 }, { "ROUTE_18", 33,  9 } }) do
    bikeless()
    U.teleport(game, c[1], c[2], c[3], "left")
    U.wait(20)
    settle()
    local x, y, walk = landed()
    U.log(("%s (%d,%d) facing left -> (%d,%d) walkable=%s")
          :format(c[1], c[2], c[3], x, y, tostring(walk)))
    check(("%s (%d,%d): the refusal leaves the player on a walkable cell")
          :format(c[1], c[2], c[3]), walk)
  end

  bikeless()
  U.teleport(game, "ROUTE_16", 17, 10, "left")
  U.wait(20)
  settle()
  U.shot(game, SHOT_DIR .. "/bug1548_route16_after.png")

  bikeless()
  U.teleport(game, "ROUTE_16", 16, 10, "right")
  U.wait(20)
  U.hold(game, "right", 24)
  settle()
  local bx, by = landed()
  U.log(("stepped onto ROUTE_16 (17,10) from the west -> (%d,%d)"):format(bx, by))
  check("a shove with open ground behind it still moves one cell",
        bx == 16 and by == 10)

  bikeless()
  while game.stack:top() do game.stack:pop() end
  game.stack:push(OverworldState, "ROUTE_16", 18, 10, "left")
  game.overworld:setMap("ROUTE_16", 18, 10, "left", { via = "boot" })
  U.wait(20)
  local cx, cy, cwalk = landed()
  U.log(("boot inside the wall (18,10) -> (%d,%d) walkable=%s")
        :format(cx, cy, tostring(cwalk)))
  check("a save parked inside the gate wall is lifted out on load", cwalk)
  settle()
  local dx, dy, dwalk = landed()
  U.log(("after the refusal that follows -> (%d,%d) walkable=%s")
        :format(dx, dy, tostring(dwalk)))
  check("and the refusal it lands on cannot push it back in", dwalk)
  U.shot(game, SHOT_DIR .. "/bug1548_repaired.png")

  game.save.inventory.BICYCLE = 1
  game.save.onBike, game.save.forcedBike = false, nil
  U.teleport(game, "ROUTE_16", 17, 10, "left")
  U.wait(30)
  local ex, ey, ewalk = landed()
  check("with a BICYCLE the forced tile mounts instead of shoving",
        game.save.onBike == true and ex == 17 and ey == 10 and ewalk)

  U.log(ok and "all clear" or "a check failed")
  while true do coroutine.yield() end
end
