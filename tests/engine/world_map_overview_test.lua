package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Assets = require("src.render.Assets")
local WorldAPI = require("src.world.WorldAPI")

Assets.imageData = function()
  return { getPixel = function(_, x, y)
    local shade = x >= 8 and 0 or ({ 1, 0, 2 / 3, 1 / 3 })[
      math.floor(y / 4) * 2 + math.floor(x / 4) + 1]
    return shade, shade, shade, 1
  end }
end

local api = WorldAPI.new({ stack = { states = {} } }, "tester")
local overview, err = api:mapOverview()
T.eq(overview, nil, "map overview is unavailable outside the overworld")
T.eq(err, "no overworld", "map overview reports why it is unavailable")

local map = {
  id = "TEST_MAP", widthCells = 2, heightCells = 2,
  def = {
    warps = { { x = 1, y = 0 } },
    objects = { { index = 1, x = 0, y = 1, item = "POTION" } },
  },
}
function map:isWarpTileCell(x, y) return x == 1 and y == 0 end
function map:isWaterCell(x, y) return x == 0 and y == 1 end
function map:isWalkableCell(x, y) return x == 0 and y == 0 end
function map:tileAt(x) return x % 2 end

local save = {}
local world = {
  isOverworld = true,
  map = map,
  objectVisible = function(s, mapId, obj)
    return not (s.itemsTaken and s.itemsTaken[mapId .. "_obj_" .. obj.index])
  end,
}
local game = {
  save = save,
  data = { field = { hiddenItems = {
    TEST_MAP = { { x = 1, y = 1, item = "NUGGET" } },
  } } },
  stack = { states = { world } },
}
api = WorldAPI.new(game, "tester")
overview = api:mapOverview()
T.eq(overview.mapId, "TEST_MAP", "map overview identifies the active map")
T.eq(overview.width, 2, "map overview reports its width")
T.eq(overview.height, 2, "map overview reports its height")
T.eq(overview.rows[1], ".+", "walkable land and warps are distinct")
T.eq(overview.rows[2], "~ ", "water and blocked terrain are distinct")
T.eq(overview.tileRows, nil, "tile overview is optional")
T.eq(#overview.markers, 3, "active exits and untaken items are marked")
T.eq(overview.markers[1].kind, "warp", "warp marker is semantic")
T.eq(overview.markers[2].kind, "item", "visible item marker is semantic")
T.eq(overview.markers[3].kind, "hidden", "hidden item marker is semantic")

save.itemsTaken = { TEST_MAP_obj_1 = true }
save.hiddenTaken = { TEST_MAP_1_1 = true }
overview = api:mapOverview()
T.eq(#overview.markers, 1, "collected items disappear from the overview")
T.eq(overview.markers[1].kind, "warp", "exits remain after collecting items")

map.tileset = { image = "test.png", tilesPerRow = 2 }
overview = api:mapOverview()
T.eq(overview.tileWidth, 4, "tile overview reports its width")
T.eq(overview.tileHeight, 4, "tile overview reports its height")
T.eq(overview.tileRows[1], "2323", "tile overview preserves average shading")
T.eq(overview.tileDetailWidth, 8, "detail overview reports its width")
T.eq(overview.tileDetailHeight, 8, "detail overview reports its height")
T.eq(overview.tileDetailRows[1], "03330333",
  "detail overview preserves top tile quadrants")
T.eq(overview.tileDetailRows[2], "12331233",
  "detail overview preserves bottom tile quadrants")

T.finish("world map overview")
