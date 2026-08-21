-- The Fly map draws no Pokegear mode arrow (engine/pokegear/pokegear.asm:1999) (#1477)
--   luajit tests/engine/gen2_fly_map_arrow_bug1477.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

local Pokegear = require("src.ui.gen2.Pokegear")

local function drawnArrow(fly)
  local drew = false
  local self = setmetatable({
    fly = fly,
    styled = function() return true end,
    groundColor = function() return { 0, 0, 0 } end,
    card = function() return { id = "map", label = fly and "FLY" or "MAP" } end,
    drawMap = function() end,
    drawModeArrow = function() drew = true end,
  }, { __index = Pokegear })
  local realRect = love.graphics.rectangle
  love.graphics.rectangle = function() end
  self:drawPanel()
  love.graphics.rectangle = realRect
  return drew
end

check(drawnArrow(false), "the Pokegear MAP card still animates the arrow")
check(not drawnArrow(true), "_FlyMap draws no mode-indicator arrow")

T.finish("gen2 fly map arrow bug 1477")
