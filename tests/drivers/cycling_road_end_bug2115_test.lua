-- home/overworld.asm:1817
--   POKEPORT_DRIVER=tests/drivers/cycling_road_end_bug2115_test.lua \
--     POKEPORT_IDENTITY=bug2115 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  game.save.onBike = true
  U.teleport(game, "ROUTE_17", 7, 135, "down")
  U.wait(15)
  local ow = game.overworld
  check("standing near the bottom of Cycling Road on the bike",
        ow.map.id == "ROUTE_17" and game.save.onBike == true)
  check("the last row of ROUTE_17 is the impassable ledge tile",
        not ow.map:isWalkableCell(7, 143))
  U.shot(game, SHOT_DIR .. "/bug2115_before.png")

  for _ = 1, 900 do
    if game.overworld.map.id ~= "ROUTE_17" then break end
    coroutine.yield()
  end
  ow = game.overworld
  check(("the roll hopped the ledge and landed on %s"):format(tostring(ow.map.id)),
        ow.map.id == "ROUTE_18")
  U.wait(30)
  U.shot(game, SHOT_DIR .. "/bug2115_route18.png")

  U.log("Hands off the pad on Cycling Road: the roll should carry you all the")
  U.log("way down and hop the ledge onto Route 18 with no input at all.")
  U.log("#2115 was the roll pedalling in place on the last row.")
  U.log("Shots in " .. SHOT_DIR .. "/bug2115_*.png")

  while true do
    coroutine.yield()
  end
end
