-- BATTLE LAYOUT = WIDE (src/battle/WideBattle.lua): the surface it asks
-- for, the 2x2 move-grid navigation, and the rigid per-frame offset that
-- moves an animation authored in 160px space onto one of the two anchors.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local WideBattle = require("src.battle.WideBattle")
local Renderer = require("src.render.Renderer")
local Game = require("src.core.Game")

T.eq(WideBattle.WIDTH, 304, "the wide layout runs on a 304px native surface")
T.eq(WideBattle.HEIGHT, 144, "the wide surface keeps the native height")
T.eq(WideBattle.FIELD_BOTTOM, 104,
  "the lower 40 rows are the message / command windows")

local wide = { isWideBattleLayout = function() return true end }
local normal = { isWideBattleLayout = function() return false end }
T.eq(Game.wideBattleInStack({ states = { normal, wide, normal } }), wide,
  "a wide battle remains the surface owner under a classic overlay")
T.eq(Game.wideBattleInStack({ states = { normal } }), nil,
  "a classic stack keeps the normal surface")

-- move grid: slots are laid out 1 2 / 3 4
T.eq(WideBattle.moveGridIndex(1, 4, "right"), 2, "RIGHT crosses the row")
T.eq(WideBattle.moveGridIndex(2, 4, "left"), 1, "LEFT crosses the row")
T.eq(WideBattle.moveGridIndex(1, 4, "down"), 3, "DOWN crosses the column")
T.eq(WideBattle.moveGridIndex(4, 4, "up"), 2, "UP crosses the column")
T.eq(WideBattle.moveGridIndex(3, 3, "right"), 3,
  "an absent fourth move cannot be selected")
T.eq(WideBattle.moveGridIndex(1, 0, "right"), nil,
  "an empty move list has nothing to navigate")

local function pressing(key)
  return { wasPressed = function(_, k) return k == key end }
end
T.eq(WideBattle.navigate(1, 4, pressing("right")), 2,
  "navigate maps a direction onto the grid")
T.eq(WideBattle.navigate(1, 4, pressing("a")), nil,
  "navigate leaves A / B / SELECT to the battle engine")

-- animation frames shift as one rigid group toward the side they play on
local px, py = WideBattle.animationOffset({ { x = 24 }, { x = 64 } })
T.eq(px, 20, "a player-side frame lands on the player anchor")
T.eq(py, 8, "a player-side frame lands on the player baseline")
local ex, ey = WideBattle.animationOffset({ { x = 104 }, { x = 144 } })
T.eq(ex, 136, "an enemy-side frame lands on the enemy anchor")
T.eq(ey, 0, "an enemy-side frame lands on the enemy baseline")

-- the surface: a request outside the bounds falls back to the GB screen,
-- and the canvas is only reallocated when the size actually changes
Renderer:init()
T.eq(select(1, Renderer:uiSize()), 160, "the default surface is the GB screen")
Renderer:setUISize(WideBattle.WIDTH, WideBattle.HEIGHT)
local w, h = Renderer:uiSize()
T.eq(w, 304, "setUISize widens the surface")
T.eq(h, 144, "setUISize keeps the height")
Renderer:setUISize(64, 64)
T.eq(select(1, Renderer:uiSize()), 160,
  "a surface smaller than the GB screen falls back")
Renderer:setUISize(99999, 99999)
T.eq(select(1, Renderer:uiSize()), 160, "an oversized surface falls back")
Renderer:setUISize(160, 144)

-- The WIDE HUD uses a dedicated registration path.  It must bypass the two
-- gates that continue to hold ordinary battle TextBox / ChoiceBox anchors,
-- without weakening those gates globally.
Renderer.uiAnchors = nil
Renderer.uiCentered = true
Renderer.uiAnchorHold = true
Renderer:setUIAnchor(0, 104, 304, 40, "bottom")
T.eq(Renderer.uiAnchors, nil,
  "ordinary UI anchors remain held inside a battle")
Renderer:setBattleUIAnchor(0, 104, 304, 40, "bottom")
T.eq(#(Renderer.uiAnchors or {}), 1,
  "the dedicated WIDE HUD region reaches the window compositor")
T.eq(Renderer.uiAnchors[1].windowClamped, true,
  "a battle HUD region is constrained to the physical window")
T.eq(Renderer.uiAnchors[1].extract, false,
  "a battle HUD region does not cut a hole in the main battle canvas")
Renderer.uiAnchors = nil
Renderer.uiCentered = false
Renderer.uiAnchorHold = false

-- The actual WIDE path draws those regions into a transparent layer and
-- restores the main battle canvas before the frame compositor runs.
local mainCanvas = Renderer.canvas
local previous = Renderer:beginBattleHUDPass()
T.eq(previous, mainCanvas, "the HUD pass remembers the battle canvas")
T.check(Renderer.battleHUDCanvas ~= mainCanvas,
  "the HUD pass owns a separate transparent canvas")
T.eq(love.graphics.getCanvas(), Renderer.battleHUDCanvas,
  "HUD drawing is redirected to the transparent canvas")
Renderer:endBattleHUDPass(previous)
T.eq(love.graphics.getCanvas(), mainCanvas,
  "ending the HUD pass restores the battle canvas")

-- At a 1000x700 window the 304x144 surface fits at 3x, centred at (44,134).
-- Pin the exact draw origins of all three extracted regions: these are real
-- physical-window coordinates, not points outside the source canvas.
local g = love.graphics
local realDims, realPixelDims, realDraw =
  g.getDimensions, g.getPixelDimensions, g.draw
g.getDimensions = function() return 1000, 700 end
g.getPixelDimensions = function() return 1000, 700 end
local draws = {}
g.draw = function(canvas, x, y, rotation, sx, sy)
  if canvas == Renderer.canvas then
    draws[#draws + 1] = { x = x, y = y, sx = sx, sy = sy }
  end
end
Renderer:setUISize(WideBattle.WIDTH, WideBattle.HEIGHT)
Renderer.uiCentered, Renderer.uiFill = true, false
Renderer:beginFrame(false)
Renderer:setBattleUIAnchor(0, 0, 128, 32, "topleft")
Renderer:setBattleUIAnchor(184, 56, 120, 40, "bottomright")
Renderer:setBattleUIAnchor(0, 104, 304, 40, "bottom")
Renderer:endFrame(WideBattle.zones(), nil)

local function sawOrigin(x, y)
  for _, d in ipairs(draws) do
    if d.x == x and d.y == y and d.sx == 3 and d.sy == 3 then return true end
  end
  return false
end
T.check(sawOrigin(0, 0), "the foe panel is composited at the physical top-left")
T.check(sawOrigin(88, 268),
  "the player panel keeps its lower-right gaps in window space")
T.check(sawOrigin(44, 268),
  "the full-width bottom strip is composited against the window bottom")

g.getDimensions, g.getPixelDimensions, g.draw = realDims, realPixelDims, realDraw
Renderer:setUISize(160, 144)
Renderer.uiAnchors = nil
Renderer.uiCentered, Renderer.uiFill = false, false

T.finish("wide battle layout")
