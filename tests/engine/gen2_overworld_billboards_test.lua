package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness").suite("gen2 overworld billboards")
local World = require("src.world.gen2.World")

local seen = {}
love.graphics.translate = function(x, y) seen.localX, seen.localY = x, y end
local world = {
  camera = { x = 4.25, y = 8.25 },
  player = {}, npcs = {}, ghosts = {}, flyAnim = {},
}
setmetatable(world, { __index = World })

World.drawPeople(world, 2, function(x, y, body)
  seen.x, seen.y = x, y
  body()
end, {
  { kind = "custom", py = 40, wx = 20, wy = 40,
    draw = function() seen.drawn = true end },
})

T.eq(seen.x, 40 + math.floor(-4.25 * 2),
  "custom billboard x uses the map's integer camera snap")
T.eq(seen.y, 80 + math.floor(-8.25 * 2),
  "custom billboard y uses the map's integer camera snap")
T.same({ seen.localX, seen.localY }, { 31, 63 },
  "custom callbacks receive a local origin at the ground anchor")
T.check(seen.drawn, "the Gen 2 people pass drains custom billboards")

T.finish("gen2 overworld billboards")
