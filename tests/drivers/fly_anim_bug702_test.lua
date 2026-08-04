-- Driver: Fly overworld animation (#702).
--
--   POKEPORT_DRIVER=tests/drivers/fly_anim_bug702_test.lua \
--     POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
--
-- Teleports to Route 17, starts Fly to Pallet Town and captures the
-- departure (in-place flap, up-right path, top-left exit) and the
-- landing swoop.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  U.teleport(game, "ROUTE_17", 4, 10, "down")
  local ow = game.stack:top()
  ow:flyTo("PALLET_TOWN")

  local function waitFrames(n)
    for _ = 1, n do coroutine.yield() end
  end

  waitFrames(12) -- mid in-place flap
  U.shot(game, DIR .. "/fly_1_flap.png")
  waitFrames(24) -- path1 ~half-way (24 + 12 = 36 into the anim)
  U.shot(game, DIR .. "/fly_2_path1.png")
  waitFrames(50) -- hold + start of path2
  U.shot(game, DIR .. "/fly_3_path2.png")

  -- wait out the warp transition, then catch the swoop mid-flight
  local guard = 0
  while ow.map.id == "ROUTE_17" and guard < 600 do
    guard = guard + 1
    coroutine.yield()
  end
  guard = 0
  while not ow.flyArrive and guard < 600 do
    guard = guard + 1
    coroutine.yield()
  end
  waitFrames(12) -- mid swoop
  U.shot(game, DIR .. "/fly_4_arrive.png")
  guard = 0
  while ow.flyArrive and guard < 600 do
    guard = guard + 1
    coroutine.yield()
  end
  U.shot(game, DIR .. "/fly_5_landed.png")

  U.log("Screenshots are under " .. DIR)
  while true do coroutine.yield() end
end
