package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local World = require("src.world.gen2.World")
local G = love.graphics

local scissor = { 296, 0, 432, 388 }
G.setScissor = function(x, y, w, h)
  if x then scissor = { x, y, w, h } else scissor = nil end
end
G.getScissor = function()
  if scissor then return scissor[1], scissor[2], scissor[3], scissor[4] end
end

local seen, bound
local mesh = {
  setTexture = function() end,
  setVertices = function() end,
}

local stub = setmetatable({
  tiltCanvas = {
    getWidth = function() return 531 end,
    getHeight = function() return 477 end,
  },
  tiltMesh = function()
    return mesh, {}
  end,
  drawGround = function()
    bound = G.getCanvas()
    seen = scissor and "clipped" or "clear"
  end,
  drawPeople = function() end,
}, { __index = World })

World.drawTilted(stub, 432, 388, 2, 531, 477)
T.eq(seen, "clear", "tilt capture has no leftover hole scissor")
T.check(bound ~= nil, "tilt capture is bound to a canvas")
T.eq(scissor and scissor[1], 296, "hole scissor x comes back")
T.eq(scissor and scissor[2], 0, "hole scissor y comes back")
T.eq(scissor and scissor[3], 432, "hole scissor width comes back")
T.eq(scissor and scissor[4], 388, "hole scissor height comes back")

scissor = nil
seen, bound = nil, nil
World.drawTilted(stub, 432, 388, 2, 531, 477)
T.eq(seen, "clear", "a capture with no scissor stays clear")
T.eq(scissor, nil, "and leaves none behind")

T.finish("gen2 tilt playfield scissor")
