-- #1097 (and the absorbed #1116): walking out of Dark Cave and pressing UP
-- puts the player inside the mountain on Route 31.
--   POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1097_test.lua love .
local Mon = require("src.battle.gen2.Mon")

return function(game)
  local function wait(n) for _ = 1, n do coroutine.yield() end end
  local function clearDirs()
    for _, d in ipairs({ "up", "down", "left", "right" }) do
      game.input.state[d] = false
    end
  end
  local function hold(dir, frames, trace)
    local last
    for _ = 1, frames do
      clearDirs()
      game.input.state[dir] = true
      table.insert(game.input.pressQueue, dir)
      coroutine.yield()
      local w = game.world
      local at = ("%s (%d,%d)"):format(w.map.id, w.player.cellX, w.player.cellY)
      if trace and at ~= last then print("      " .. at); last = at end
    end
    clearDirs()
  end

  wait(30)
  local world = game.world
  game.save.party = { Mon.new(game.data, "PIDGEY", 5) }

  -- Route31CheckMomCallCallback (maps/Route31.asm:14) fires on every NEWMAP
  -- arrival until the errand is over; set its event so the walk is not spent
  -- behind a phone call.  constants/event_flags.asm:73.
  if world.events then world.events:set(64, true) end

  -- maps/DarkCaveVioletEntrance.asm warp 1 is (3,15) -> ROUTE_31 warp 3.
  world:setMap("DARK_CAVE_VIOLET_ENTRANCE", 3, 14, "down")
  wait(20)
  hold("down", 40)
  -- the ROUTE_31 arrival runs Route31CheckMomCallCallback (maps/Route31.asm:14)
  for _ = 1, 900 do
    if not world:busy() then break end
    coroutine.yield()
  end
  wait(20)
  print(("[driver] out of the cave at %s (%d,%d)")
    :format(world.map.id, world.player.cellX, world.player.cellY))
  assert(world.map.id == "ROUTE_31", "did not reach ROUTE_31")

  print("[driver] holding UP:")
  hold("up", 120, true)
  wait(30)
  local m, x, y = world.map.id, world.player.cellX, world.player.cellY
  print(("[driver] ended at %s (%d,%d)"):format(m, x, y))
  -- Anything above y=5 on Route 31 in that column is the inside of the
  -- mountain; the honest outcomes are re-entering the cave or bumping.
  local inside = (m == "ROUTE_31" and y < 5)
  assert(not inside, ("walked into the mountain at (%d,%d)"):format(x, y))
  -- The other two Dark Cave mouths, same shape: maps/Route46.asm warp 3 is
  -- (14,5) and maps/Route45.asm warp 1 is (2,5), both COLL_CAVE tiles with
  -- ordinary FLOOR above them in the collision data.
  for _, c in ipairs({ { "ROUTE_46", 14, 5 }, { "ROUTE_45", 2, 5 } }) do
    local mapId, wx, wy = c[1], c[2], c[3]
    world:setMap(mapId, wx, wy, "up")
    wait(20)
    hold("up", 90)
    wait(20)
    if world.map.id == mapId then
      assert(world.player.cellY >= wy,
        ("%s: walked above the cave mouth to (%d,%d)")
          :format(mapId, world.player.cellX, world.player.cellY))
    end
    print(("[driver] %s mouth ended at %s (%d,%d)"):format(
      mapId, world.map.id, world.player.cellX, world.player.cellY))
  end

  print("[driver] PASS the cave mouth cannot be walked through")
end
