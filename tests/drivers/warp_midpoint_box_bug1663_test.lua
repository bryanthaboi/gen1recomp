-- data/maps/force_bike_surf.asm:5 / engine/overworld/player_state.asm:34-72,
-- home/overworld.asm:690-703 (the map-change fade has no fade back in).
--   POKEPORT_DRIVER=tests/drivers/warp_midpoint_box_bug1663_test.lua \
--   POKEPORT_IDENTITY=bug1663 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
-- Ride into the Route 16 gate, drop the BICYCLE inside, then walk back out
-- the west door.  The warp lands on a forced-bike tile, so the refusal box
-- opens from inside the fade's midpoint: it must be on screen when the fade
-- ends (#1663 ate it), and dismissing it must leave the player on Route 16's
-- (17,10), not shoved into the gate wall at (18,10) (#1548).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end

  local function where()
    local ow = game.overworld
    return ow.map.id, ow.player.cellX, ow.player.cellY
  end
  local function bikeless()
    game.save.inventory.BICYCLE = nil
    game.save.onBike, game.save.forcedBike = false, nil
  end

  game.save.player.name = "PROBE"
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.inventory.BICYCLE = 1
  game.save.onBike, game.save.forcedBike = false, nil

  -- (16,10) is the open cell west of the gate door; (17,10) is the forced
  -- tile the door sits on, so the step onto it mounts and then warps
  U.teleport(game, "ROUTE_16", 16, 10, "right")
  U.wait(20)
  U.hold(game, "right", 40)
  U.wait(40)
  local map, x, y = where()
  U.log(("rode east into the gate -> %s (%d,%d)"):format(map, x, y))
  check("the bike carried the player into the gate",
        map == "ROUTE_16_GATE_1F")

  bikeless()
  U.hold(game, "left", 40)
  -- the map-change fade is 32 frames and hands back with no fade in
  U.wait(50)

  map, x, y = where()
  local top = game.stack:top()
  U.log(("walked back out -> %s (%d,%d), top=%s"):format(map, x, y,
        tostring(getmetatable(top) == TextBox and "TextBox" or top)))
  check("the west door lands back on Route 16", map == "ROUTE_16")
  check("on the forced tile the gate exit warps to", x == 17 and y == 10)
  check("the refusal box the warp opened is on screen",
        getmetatable(top) == TextBox)
  U.shot(game, SHOT_DIR .. "/bug1663_refusal.png")

  -- close it: the shove back east is refused by collision, (18,10) is wall
  for _ = 1, 12 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "a")
    U.wait(25)
  end
  U.wait(30)
  map, x, y = where()
  local walkable = game.overworld.map:isWalkableCell(x, y)
  U.log(("after the refusal -> %s (%d,%d) walkable=%s")
        :format(map, x, y, tostring(walkable)))
  check("dismissing it leaves the player on a walkable cell", walkable)
  check("and not inside the gate wall at (18,10)", not (x == 18 and y == 10))
  U.shot(game, SHOT_DIR .. "/bug1663_after.png")

  U.log(ok and "all clear" or "a check failed")
  while true do coroutine.yield() end
end
