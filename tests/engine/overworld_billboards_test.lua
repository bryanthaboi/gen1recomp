package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness").suite("overworld billboard context")
local loaded, OverworldBillboards = pcall(require,
  "src.render.OverworldBillboards")
T.check(loaded and type(OverworldBillboards) == "table",
  "the engine exposes shared overworld billboard helpers")

if loaded then
  local map = { id = "TEST_TOWN", widthCells = 3, heightCells = 2 }
  function map:inBounds(x, y)
    return x >= 0 and y >= 0
      and x < self.widthCells and y < self.heightCells
  end
  function map:isWalkableCell(x, y) return x == 0 and y == 0 end
  function map:isWaterCell(x, y) return x == 2 and y == 1 end
  function map:isGrassCell(x, y) return x == 1 and y == 0 end
  function map:isWarpTileCell(x, y) return x == 2 and y == 0 end

  local view = OverworldBillboards.mapView(map, true)
  T.eq(view.id, "TEST_TOWN", "map view carries the map id")
  T.eq(view.width, 3, "map view carries cell width")
  T.eq(view.height, 2, "map view carries cell height")
  T.eq(view.cellSize, 16, "map view defines map-pixel cell size")
  T.eq(view.outdoor, true, "map view carries outdoor classification")
  T.check(view.cell(0, 0).walkable and not view.cell(0, 0).solid,
    "walkable cells are not solid")
  T.check(view.cell(1, 1).solid,
    "blocked cells expose conservative solid semantics")
  T.check(view.cell(2, 1).water and not view.cell(2, 1).solid,
    "water is distinct from solid terrain")
  T.check(view.cell(2, 0).warp, "warp semantics are preserved")

  local gen2Map = {
    id = "GEN2_TOWN", width = 4, height = 3,
    inBounds = function(_, x, y)
      return x >= 0 and y >= 0 and x < 8 and y < 6
    end,
  }
  function gen2Map:isWalkableCell() return true end
  function gen2Map:isWaterCell() return false end
  function gen2Map:isGrassCell() return false end
  function gen2Map:isWarpTileCell() return false end
  local gen2View = OverworldBillboards.mapView(gen2Map, true)
  T.eq(gen2View.width, 8, "Gen 2 block width expands to collision cells")
  T.eq(gen2View.height, 6, "Gen 2 block height expands to collision cells")

  local sx, sy = OverworldBillboards.gen1GroundScreenPoint(
    64, 80, 8.25, 16.75)
  T.same({ sx, sy }, { 56, 64 },
    "Gen 1 anchors use the same integer camera snap as the map")
  local gx, gy = OverworldBillboards.gen2GroundScreenPoint(
    64, 80, 8.25, 16.75, 2)
  T.same({ gx, gy }, { 111, 126 },
    "Gen 2 anchors use the same scaled camera snap as the map")

  local scoped = { pushes = 0, pops = 0 }
  local graphics = {
    push = function() scoped.pushes = scoped.pushes + 1 end,
    pop = function() scoped.pops = scoped.pops + 1 end,
    translate = function(x, y) scoped.x, scoped.y = x, y end,
  }
  T.check(type(OverworldBillboards.drawLocal) == "function",
    "custom cards expose a scoped local-origin draw helper")
  if type(OverworldBillboards.drawLocal) == "function" then
    OverworldBillboards.drawLocal(graphics, 56, 64, function()
      scoped.called = true
    end)
    T.same({ scoped.x, scoped.y }, { 56, 64 },
      "custom cards draw from their ground anchor")
    T.check(scoped.called and scoped.pushes == 1 and scoped.pops == 1,
      "the local transform is scoped to one callback")
  end
end

T.finish("overworld billboard context")
