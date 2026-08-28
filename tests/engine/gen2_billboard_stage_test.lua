package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness").suite("gen2 billboard stage")
local Pipelines = require("src.render.Pipelines")
local World = require("src.world.gen2.World")

local order, seen = {}, {}
Pipelines.install({
  render_pipelines = {
    structures = {
      drawBillboards = function(ctx)
        seen.ctx = ctx
        order[#order + 1] = "callback"
        if ctx.maskMapCutout(16, 16, 16, 16,
            { x = 0, y = 0, width = 16, height = 16 }) then
          ctx.billboard(24, 32, function()
            order[#order + 1] = "card"
          end)
        end
      end,
    },
  },
})
Pipelines.setLevel("structures", 1)

local mesh = {
  setTexture = function() end,
  setVertices = function() end,
}
local canvas = love.graphics.newCanvas(160, 144)
local map = {
  id = "TEST_TOWN", width = 10, height = 9,
  def = { outdoor = true },
  inBounds = function(_, x, y) return x >= 0 and y >= 0 end,
  isWalkableCell = function() return false end,
  isWaterCell = function() return false end,
  isGrassCell = function() return false end,
  isWarpTileCell = function() return false end,
}
local world = setmetatable({
  map = map,
  camera = { x = 0, y = 0 },
  viewW = 160,
  viewH = 144,
  tiltCanvas = canvas,
}, { __index = World })
function world:tiltMesh() return mesh, {} end
function world:drawGround() order[#order + 1] = "ground" end
function world:drawMapUnderlay()
  order[#order + 1] = "mask"
  seen.maskCanvas = love.graphics.getCanvas()
  return true
end
function world:drawPeople(_, _, extra)
  order[#order + 1] = "people"
  seen.extra = extra
  if extra and extra[1] then extra[1].draw() end
end

world:drawTilted(160, 144, 1, 160, 144)

T.check(type(seen.ctx) == "table", "TILT dispatches drawBillboards")
T.eq(seen.maskCanvas, canvas,
  "maskMapCutout runs while the TILT ground canvas is active")
local ctx = seen.ctx or {}
T.check(type(ctx.drawMapCutout) == "function"
    and type(ctx.maskMapCutout) == "function"
    and type(ctx.billboard) == "function",
  "the public context exposes card, mask, and queue helpers")
T.check(seen.extra and #seen.extra == 1,
  "the upright people pass receives the queued custom card")
T.same(order, { "ground", "callback", "mask", "people", "card" },
  "ground masking finishes before the upright card draws")

Pipelines.install(nil)
T.finish("gen2 billboard stage")
