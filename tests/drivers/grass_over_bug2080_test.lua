local U = require("tests.drivers.util")

-- pokecrystal engine/overworld/map_objects.asm:2924
-- pokecrystal data/sprites/facings.asm:47-52
local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0

  local function say(line) print("[2080] " .. line) end
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

  world:warpToMapId("ROUTE_29", 10, 5, "down")
  U.wait(20)
  ok(world.map and world.map.id == "ROUTE_29", "warped to ROUTE_29")

  local map = world.map
  local gx, gy
  for cy = 0, (map.height or 0) * 2 - 1 do
    for cx = 0, (map.width or 0) * 2 - 1 do
      if world:grassAt(cx, cy) and world:grassAt(cx + 1, cy)
        and world:grassAt(cx, cy + 1) then
        gx, gy = cx, cy
        break
      end
    end
    if gx then break end
  end
  ok(gx ~= nil, "found a tall grass cell on ROUTE_29")
  if not gx then
    love.event.quit(1)
    return
  end
  say(("grass cell = (%d, %d)"):format(gx, gy))

  world:warpToMapId("ROUTE_29", gx, gy, "down")
  U.wait(20)
  local p = world.player
  ok(p and p.inGrass == true, "player.inGrass is set standing in the grass")
  ok(p and not p.moving, "player is standing still")

  local atlas = world:atlasFor(world.map.def)
  ok(atlas ~= nil, "the map tileset atlas exists for feet overdraw")

  local records = {}
  local origDraw = love.graphics.draw
  love.graphics.draw = function(img, quad, x, y, ...)
    if img == atlas and type(quad) ~= "number" and quad ~= nil then
      local okv, _, _, w, h = pcall(quad.getViewport, quad)
      if okv then
        records[#records + 1] = { x = x, y = y, w = w, h = h }
      end
    end
    return origDraw(img, quad, x, y, ...)
  end
  U.wait(3)
  love.graphics.draw = origDraw

  ok(#records > 0, "drawGrassOver drew grass over the standing player")
  local maxH, ys = 0, {}
  for _, r in ipairs(records) do
    if r.h > maxH then maxH = r.h end
    ys[r.y] = true
  end
  local distinctYs = 0
  for _ in pairs(ys) do distinctYs = distinctYs + 1 end
  ok(maxH == 8,
    "each blit is a full 8x8 tile (not a sub-quad sliver), saw max h="
    .. tostring(maxH))
  ok(distinctYs >= 2,
    "feet strip crosses two tile rows when py is not 8-aligned: "
    .. distinctYs .. " distinct rows")

  U.shot(game, SHOT_DIR .. "/2080-grass-over.png")
  say("compare the shot against issue #2080's expected screenshot: grass "
    .. "tufts overlap the sprite's lower half, legs show through colour 0")

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
