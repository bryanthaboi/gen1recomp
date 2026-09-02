-- Crystal IN_GRASS feet-strip regression (#2080): grass must not appear above
-- the RELATIVE_ATTRIBUTES row (map y = py+4 .. py+12).  Samples the feet
-- canvas composite and counts keyed grass pixels outside the 8px strip.
--
-- Run: POKEPORT_DRIVER=tests/drivers/grass_over_feet_strip_test.lua \
--      POKEPORT_VERSION=crystal love .

local U = require("tests.drivers.util")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0

  local function say(line) print("[2080-feet] " .. line) end
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
  ok(gx ~= nil, "found tall grass on ROUTE_29")
  if not gx then
    love.event.quit(1)
    return
  end

  world:warpToMapId("ROUTE_29", gx, gy, "down")
  U.wait(20)
  local p = world.player
  ok(p and p.inGrass, "player.inGrass standing in grass")

  local OamFootprint = require("src.world.gen2.OamFootprint")
  local x0, y0, x1, y1 = OamFootprint.feetStrip(p)
  local fw, fh = x1 - x0, y1 - y0

  local canvas = world:feetCompositeCanvas(fw, fh)
  ok(canvas ~= nil, "feet composite canvas exists")

  if canvas and love.graphics.readbackTexture then
    local G = love.graphics
    G.push("all")
    G.origin()
    G.setCanvas(canvas)
    G.clear(0, 0, 0, 0)
    G.translate(-x0, -y0)
    if p.sprite then
      p.sprite:draw(p.px, p.py, 0, 0, p.facing, p:walkPhase(), p:drawFlip(),
        nil, nil, nil, "bottom")
    end
    world:blitBgOverRegionLocal(world.map.def, 0, 0, x0, y0, x1, y1,
      true, function() return true end, 1)
    G.setCanvas()
    G.pop()

    local data = G.readbackTexture(canvas)
    if data then
      local leakAbove = 0
      for y = 0, fh - 1 do
        for x = 0, fw - 1 do
          local _, _, _, a = data:getPixel(x, y)
          if a > 0.05 and y < 0 then leakAbove = leakAbove + 1 end
        end
      end
      ok(leakAbove == 0, "no grass pixels above feet canvas origin")
      local opaque = 0
      for y = 0, fh - 1 do
        for x = 0, fw - 1 do
          local _, _, _, a = data:getPixel(x, y)
          if a > 0.5 then opaque = opaque + 1 end
        end
      end
      ok(opaque > 0, "feet canvas has visible grass/sprite pixels")
    else
      say("SKIP readbackTexture unavailable; screenshot only")
    end
  end

  ok(U.shot(game, SHOT_DIR .. "/2080-feet-strip.png"),
    "screenshot captured for manual compare")

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
