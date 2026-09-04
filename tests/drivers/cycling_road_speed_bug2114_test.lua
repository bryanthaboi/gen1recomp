-- (#2114).  DoBikeSpeedup (pokered home/overworld.asm:377)
--   POKEPORT_DRIVER=tests/drivers/cycling_road_speed_bug2114_test.lua \
--     POKEPORT_IDENTITY=bug2114 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local MAP, START_X, START_Y = "ROUTE_17", 2, 20

  game.save.onBike = true
  U.teleport(game, MAP, START_X, START_Y, "down")
  U.wait(15)
  local ow = game.overworld
  check("standing on Cycling Road on the bike",
        ow.map.id == MAP and game.save.onBike == true)
  check("the player is flagged as on a slope map", ow.player.slopeMap == true)

  local y0 = ow.player.cellY
  U.wait(120)
  local down = ow.player.cellY - y0
  check(("DOWN travelled %d cells in 120 frames"):format(down), down > 0)
  U.shot(game, SHOT_DIR .. "/bug2114_down.png")

  table.insert(game.input.pressQueue, "up")
  game.input.state.up = true
  U.wait(12)
  local y1 = ow.player.cellY
  U.wait(120)
  local up = y1 - ow.player.cellY
  game.input.state.up = false
  check(("UP travelled %d cells in 120 frames"):format(up), up > 0)
  check(("UP is about half of DOWN (%d vs %d)"):format(up, down), up * 2 <= down + 2)
  U.shot(game, SHOT_DIR .. "/bug2114_up.png")

  U.teleport(game, "ROUTE_16", 11, 4, "up")
  U.wait(15)
  ow = game.overworld
  game.save.onBike = true
  check("Route 16 is not a slope map", ow.player.slopeMap ~= true)
  table.insert(game.input.pressQueue, "up")
  game.input.state.up = true
  U.wait(20)
  check(("UP off the slope is a bike step (%s frames)")
          :format(tostring(ow.player.stepFramesCur)),
        ow.player.stepFramesCur == ow.player.bikeStepFrames)
  game.input.state.up = false

  U.teleport(game, MAP, START_X, START_Y, "down")
  U.wait(10)
  game.save.onBike = true

  U.log("On the bike on Cycling Road, rolling south.")
  U.log("Hold UP, LEFT or RIGHT: those three should feel like WALKING pace.")
  U.log("Let go and roll south: twice as fast.  Shots in "
        .. SHOT_DIR .. "/bug2114_*.png")

  while true do
    coroutine.yield()
  end
end
