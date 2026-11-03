-- TILT with a render.viewport rect: the projection pass has to land on the
-- game viewport's canvas.  It used to bind the present target, which is nil
-- without a present canvas, so the tilted world went to the backbuffer
-- behind the viewport and the game area turned black.
package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Renderer = require("src.render.Renderer")
local GameViewport = require("src.render.GameViewport")
local G = love.graphics

local function canvas(w, h)
  return {
    getWidth = function() return w end,
    getHeight = function() return h end,
  }
end

local mesh = { setTexture = function() end, setVertices = function() end }
local projectedOnto
local draw = G.draw
G.draw = function(drawable, ...)
  if drawable == mesh then projectedOnto = G.getCanvas() or "screen" end
  return draw(drawable, ...)
end

local world = canvas(160, 144)
local stub = setmetatable({
  worldCanvas = world,
  tiltCanvas = canvas(160, 144),
  tiltShader = function() return {} end,
  tiltMesh = function() return mesh end,
}, { __index = Renderer })

local viewportCanvas = canvas(466, 280)
local oldCanvas = GameViewport.canvas

-- a viewport canvas and no present target: project into the viewport
GameViewport.canvas = viewportCanvas
projectedOnto = nil
T.check(stub:drawTiltedWorld(nil, 2, 2, 0, 0, nil), "tilt pass runs")
T.check(projectedOnto == viewportCanvas, "tilt projects into the viewport canvas")

-- a present target still wins over the viewport canvas
local present = canvas(466, 280)
projectedOnto = nil
stub:drawTiltedWorld(nil, 2, 2, 0, 0, present)
T.check(projectedOnto == present, "a present target still takes the projection")

-- full-window play (no viewport canvas, no target) still draws to the screen
GameViewport.canvas = nil
projectedOnto = nil
stub:drawTiltedWorld(nil, 2, 2, 0, 0, nil)
T.eq(projectedOnto, "screen", "without a viewport the projection goes to the screen")

GameViewport.canvas = oldCanvas
G.draw = draw
T.finish("tilt viewport target")
