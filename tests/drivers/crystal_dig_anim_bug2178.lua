local U = require("tests.drivers.util")

-- ../pokecrystal/engine/events/overworld.asm:755-846
local MAP = "DARK_CAVE_VIOLET_ENTRANCE"
local BACK = "ROUTE_31"

return function(game)
  local fails = 0
  local function say(line) print("[dig2178] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the crystal world did not boot")
    love.event.quit(1)
    return
  end

  local mouth = world.maps and world.maps[MAP] and world.maps[MAP].warps
    and world.maps[MAP].warps[1]
  ok(mouth ~= nil, MAP .. " carries its Route 31 mouth")
  if not mouth then love.event.quit(1) return end

  world:warpToMapId(MAP, mouth.x, mouth.y + 1, "down")
  U.wait(60)
  ok(world.map and world.map.id == MAP, "arrived in the cave")
  world.noWildEncounters = true
  world.backupWarp = { map = BACK, warp = 3 }

  local destMapId, destWarp = world:escapeRopeTarget()
  ok(destMapId == BACK, "the rope resolves back to " .. BACK)
  if not destWarp then love.event.quit(1) return end

  U.shot(game, "/tmp/pokeport-shots/dig2178_before.png")
  ok(world:runEscapeWarp(destMapId, destWarp), "the dig warp runs")
  ok(world.moveState ~= nil, ".DigOut armed a movement stream")
  for i = 1, 4 do
    U.wait(8)
    U.shot(game, ("/tmp/pokeport-shots/dig2178_spin%d.png"):format(i))
  end
  U.wait(8)
  ok(world.playerHidden == true, "hide_object hid the player for the fade")

  for _ = 1, 300 do
    if world.map and world.map.id == BACK then break end
    U.wait(1)
  end
  ok(world.map and world.map.id == BACK, "landed on " .. BACK)

  for _ = 1, 240 do
    if not world.playerHidden then break end
    U.wait(1)
  end
  ok(world.moveState ~= nil, ".DigReturn armed the return stream")
  ok(not world.playerHidden, "show_object brought the player back")
  for i = 1, 6 do
    U.shot(game, ("/tmp/pokeport-shots/dig2178_return%d.png"):format(i))
    U.wait(1)
  end
  local walkable = false
  for _ = 1, 120 do
    if not world:busy() then walkable = true break end
    U.wait(1)
  end
  ok(walkable, "and the world is walkable again")
  U.shot(game, "/tmp/pokeport-shots/dig2178_after.png")

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
