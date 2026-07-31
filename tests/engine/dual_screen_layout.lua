-- DUAL SCREEN (src/render/DualScreen.lua): the stacked composite surface,
-- the two screen rects in framebuffer pixels and LOVE units, point routing,
-- and the mode flag / persistence. Renderer:worldViewSize collapses to the
-- classic 160x144 world while the mode is on.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local DualScreen = require("src.render.DualScreen")
local Renderer = require("src.render.Renderer")

-- surface: one screen wide, two screens tall plus the gutter
local sw, sh = DualScreen.surfaceSize(160, 144)
T.eq(sw, 160, "the stacked surface is one screen wide")
T.eq(sh, 144 * 2 + DualScreen.GAP, "two screens tall plus the gutter")

-- regions in framebuffer pixels: integer fit scale, world on top, ui below
local scale, world, ui = DualScreen.regions(640, 640)
T.eq(scale, 2, "the fit scale floors the tighter of the two axes")
T.eq(world.ox, 160, "the column is centred horizontally")
T.eq(world.oy, 24, "the stack is centred vertically")
T.eq(world.w, 320, "each screen is 160 GB px at the fit scale")
T.eq(world.h, 288, "each screen is 144 GB px at the fit scale")
T.eq(ui.ox, 160, "both screens share the same column")
T.eq(ui.oy, 24 + 288 + DualScreen.GAP * scale,
  "the ui screen sits a gutter below the world screen")
T.eq(ui.w, 320, "the ui screen matches the world screen width")

-- layout in LOVE units divides the pixel rects by each axis dpi
local uscale, uworld, uui = DualScreen.layout(1280, 1280, 2, 2)
T.eq(uscale, 4, "the fit scale is computed from framebuffer pixels")
T.eq(uworld.ox, 160, "unit origin is the pixel origin over dpiX")
T.eq(uworld.oy, 24, "unit origin is the pixel origin over dpiY")
T.eq(uworld.sx, 2, "the draw scale is the fit scale over dpiX")
T.eq(uworld.sy, 2, "the draw scale is the fit scale over dpiY")
T.eq(uui.oy, uworld.oy + uworld.h + DualScreen.GAP * uscale / 2,
  "the ui screen keeps its gutter offset in units")

-- point routing across the two screens and the dead zones between/around them
T.eq(DualScreen.screenAt(300, 100, 640, 640), "world",
  "a point on the top screen routes to the world")
T.eq(DualScreen.screenAt(300, 400, 640, 640), "ui",
  "a point on the bottom screen routes to the ui")
T.eq(DualScreen.screenAt(300, 315, 640, 640), nil,
  "the gutter between the screens is dead")
T.eq(DualScreen.screenAt(10, 100, 640, 640), nil,
  "the letterbox beside the column is dead")

-- the mode flag and its persistence key
DualScreen.setEnabled(false)
T.eq(DualScreen.active(), false, "starts off")
T.eq(DualScreen.label(), "OFF", "label reads OFF while off")
T.eq(DualScreen.toggle(), true, "toggle turns it on")
T.eq(DualScreen.label(), "ON", "label reads ON while on")
DualScreen.applyOptions({ dualScreen = false })
T.eq(DualScreen.active(), false, "applyOptions restores the persisted state")
DualScreen.applyOptions({ dualScreen = true })
T.eq(DualScreen.active(), true, "applyOptions reads save.options.dualScreen")

-- the world pass collapses to the classic GB screen while the mode is on
Renderer:init()
DualScreen.setEnabled(true)
local vw, vh = Renderer:worldViewSize()
T.eq(vw, 160, "the world view is the classic width while dual screen is on")
T.eq(vh, 144, "the world view is the classic height while dual screen is on")
DualScreen.setEnabled(false)

-- battle dual layout: which screen the battlefield vs the menu lands on
local BATTLE = { isOpaque = true, isBattleScreen = true }
local OVERWORLD = { isOpaque = true }
local BAG = { isOpaque = true }            -- bag/party cover the battle
local CHOICE = { isOpaque = false }        -- YES/NO etc. over a live battle
local function mode(...) return DualScreen.battleMode({ ... }) end

local b, t = mode(OVERWORLD)
T.eq(b, false, "no battle in the stack -> not battle mode")
T.eq(t, false, "no battle -> no split")
b, t = mode(OVERWORLD, BATTLE)
T.eq(b, true, "a battle on top is battle mode")
T.eq(t, true, "battle on top -> split battlefield/menu")
b, t = mode(OVERWORLD, BATTLE, BAG)
T.eq(b, true, "battle still active under an opaque bag/party screen")
T.eq(t, false, "opaque bag/party covers the battle -> whole thing to the menu screen")
b, t = mode(OVERWORLD, BATTLE, CHOICE)
T.eq(t, true, "a non-opaque overlay over a live battle keeps the split")

T.finish("dual screen layout")
