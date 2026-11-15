-- pokegold engine/overworld/map_objects.asm:1995, :879-893 (#1888)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

local Player = require("src.world.gen2.Player")
local World = require("src.world.gen2.World")

local SHEET = {}

local function newWorld()
  return setmetatable({ jumpShadowImage = SHEET, palettes = nil }, {
    __index = World,
  })
end

local function record(fn)
  local G = love.graphics
  local realDraw, realEllipse = G.draw, G.ellipse
  local draws, ellipses = {}, 0
  G.draw = function(image, x, y, r, sx, sy)
    draws[#draws + 1] = { image = image, x = x, y = y, sx = sx, sy = sy }
  end
  G.ellipse = function() ellipses = ellipses + 1 end
  local ok, err = pcall(fn)
  G.draw, G.ellipse = realDraw, realEllipse
  if not ok then error(err, 0) end
  return draws, ellipses
end

do
  local world = newWorld()
  local jumper = { jumping = true, facing = "down", px = 32, py = 48 }
  local draws = record(function() world:drawJumpShadow(jumper, 0, 0, 1) end)
  T.eq(#draws, 2, "FacingShadow's `db 2` is two OAM entries, so two blits")
  T.eq(draws[1].image, SHEET, "both of them the ripped JumpShadowGFX tile")
  T.eq(draws[2].image, SHEET, "not an invented shape")
  T.eq(draws[1].sx, 1, "the first entry draws unflipped")
  T.eq(draws[2].sx, -1, "the second carries OAM_XFLIP")
  T.eq(draws[1].x, 32, "at the jumper's own cell x")
  T.eq(draws[2].x, 48, "and the flip hangs off the far edge of the 16px pair")
  T.eq(draws[1].y, 58, "DOWN puts it 10 pixels under the ground cell's top")
  T.eq(draws[2].y, 58, "both entries share the row")
end

do
  local world = newWorld()
  for _, facing in ipairs({ "left", "right" }) do
    local jumper = { jumping = true, facing = facing, px = 0, py = 0 }
    local draws = record(function() world:drawJumpShadow(jumper, 0, 0, 1) end)
    T.eq(draws[1].y, 8,
      facing .. " takes MovementFunction_Shadow's 1 * TILE_WIDTH + 4 arm")
  end
end

do
  local world = newWorld()
  local standing = { jumping = false, facing = "down", px = 0, py = 0 }
  local draws = record(function() world:drawJumpShadow(standing, 0, 0, 1) end)
  T.eq(#draws, 0, "SpawnShadow only runs from JumpStep, so no hop no shadow")
end

do
  local world = setmetatable({ game = { data = { gen2MenuGfx = {
    emotes = { grassRustle = "rustle.png", cutGrass = "cut.png",
      fishing = "fishing.png" },
    healMachine = { sheet = "heal.png", palette = { 0, 0, 0, 0 } },
  } } } }, { __index = World })
  local ok, err = pcall(world.loadMenuGfx, world)
  T.check(not ok and tostring(err):find("menu_gfx.lua has no emotes.jumpShadow",
    1, true), "a menu_gfx.lua without the shadow tile does not load")
end

do
  local player = setmetatable({
    jumping = true, facing = "down", px = 0, py = 0, spriteYOffset = -12,
    turnTimer = 0, moving = false, animClock = 0,
    sprite = { draw = function() end },
  }, { __index = Player })
  local _, ellipses = record(function() player:draw(0, 0, 1) end)
  T.eq(ellipses, 0, "the 40%-black love.graphics.ellipse placeholder is gone")
end

T.finish("gen2_ledge_shadow_bug1888")
