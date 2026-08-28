-- Shared public data shape used by the additive TILT billboard stage. The
-- generation-specific world renderers build this view from their Map objects
-- so mods read one semantic collision vocabulary on every supported game.

local OverworldBillboards = {}

function OverworldBillboards.gen1GroundScreenPoint(wx, wy, camX, camY)
  return wx - math.floor(tonumber(camX) or 0),
         wy - math.floor(tonumber(camY) or 0)
end

function OverworldBillboards.gen2GroundScreenPoint(wx, wy, camX, camY, scale)
  scale = tonumber(scale) or 1
  return wx * scale + math.floor(-(tonumber(camX) or 0) * scale),
         wy * scale + math.floor(-(tonumber(camY) or 0) * scale)
end

function OverworldBillboards.drawLocal(graphics, x, y, draw)
  graphics.push()
  graphics.translate(x, y)
  local ok, err = xpcall(draw, debug.traceback)
  graphics.pop()
  if not ok then error(err, 0) end
end

local function predicate(map, name, x, y)
  local fn = map and map[name]
  return type(fn) == "function" and fn(map, x, y) == true
end

function OverworldBillboards.mapView(map, outdoor)
  assert(type(map) == "table", "billboard map is required")
  local view = {
    id = map.id,
    width = map.widthCells or (map.width and map.width * 2) or 0,
    height = map.heightCells or (map.height and map.height * 2) or 0,
    cellSize = 16,
    outdoor = outdoor == true,
  }

  function view.cell(x, y)
    local inside = type(map.inBounds) == "function"
      and map:inBounds(x, y)
      or (x >= 0 and y >= 0 and x < view.width and y < view.height)
    if not inside then
      return { inside = false, walkable = false, water = false,
               grass = false, warp = false, solid = false }
    end
    local walkable = predicate(map, "isWalkableCell", x, y)
    local water = predicate(map, "isWaterCell", x, y)
    return {
      inside = true,
      walkable = walkable,
      water = water,
      grass = predicate(map, "isGrassCell", x, y),
      warp = predicate(map, "isWarpTileCell", x, y),
      solid = not walkable and not water,
    }
  end

  return view
end

return OverworldBillboards
