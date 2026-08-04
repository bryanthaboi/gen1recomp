-- UI LAYOUT (save.options.uiLayout): "centered" keeps every element where it
-- was drawn in the 160x144 canvas, so the letterbox centres the whole screen
-- the way the port composed it before edge docking existed.  "dynamic" opts
-- into docking: the dialogue box to the window's bottom edge, the START menu
-- to its top right.
--
-- Centered is the DEFAULT.  Docking is a real change to where screen
-- furniture sits, so it is opt-in rather than something a player has to
-- discover and turn off.
--
-- One gate, at Renderer:setUIAnchor, so the switch covers the dialogue box,
-- its YES/NO, the START menu and anything added later without any of them
-- knowing the option exists.
--   luajit tests/engine/ui_layout_option.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Game = require("src.core.Game")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")

-- ------------------------------------------------------------- the default

T.eq(SaveData.newGame().options.uiLayout, "centered",
  "a new game starts centered, not docked")

-- ------------------------------------------------------ reading the option

-- Only the explicit "dynamic" switches docking on.  Everything else means
-- centered, which is what makes this safe for a save written before the
-- option existed: the key is simply absent and the player keeps the layout
-- they already had.
T.eq(Game.dynamicUI({ options = { uiLayout = "dynamic" } }), true,
  "DYNAMIC turns edge docking on")
T.eq(Game.dynamicUI({ options = { uiLayout = "centered" } }), false,
  "CENTERED leaves it off")
T.eq(Game.dynamicUI({ options = {} }), false,
  "a save from before the option existed is centered")
T.eq(Game.dynamicUI({}), false, "a save with no options at all is centered")
T.eq(Game.dynamicUI(nil), false, "and no save at all is centered")

-- ------------------------------------------------------------- the gate

local function anchorsAfter(opts)
  Renderer.uiAnchors = nil
  Renderer.uiAnchorHold = opts.hold or false
  Renderer.uiCentered = opts.centered or false
  -- the dialogue box's own declaration (TextBox:draw)
  Renderer:setUIAnchor(0, 96, 160, 48, "bottom")
  -- and the START menu's (Menu:draw, anchor "topright")
  Renderer:setUIAnchor(80, 0, 80, 88, "topright")
  local n = #(Renderer.uiAnchors or {})
  Renderer.uiAnchors, Renderer.uiAnchorHold, Renderer.uiCentered =
    nil, false, false
  return n
end

T.eq(anchorsAfter({ centered = true }), 0,
  "CENTERED: neither the dialogue box nor the START menu leaves the canvas")
T.eq(anchorsAfter({ centered = false }), 2,
  "DYNAMIC: both dock to the window edge")

-- the battle hold is unchanged by any of this -- a battle still keeps its own
-- prompts inside its screen even with DYNAMIC on (see battle_fixed_menu_scale)
T.eq(anchorsAfter({ centered = false, hold = true }), 0,
  "a battle still holds the anchors while DYNAMIC is on")
T.eq(anchorsAfter({ centered = true, hold = true }), 0, "and with it off")

-- ------------------------------------------------- the scale half of it

-- CENTERED is a FIXED letterbox, so the UI must not follow the survey zoom
-- either: the box that stopped moving must not start resizing instead.
local g = love.graphics
local realDims, realPixelDims = g.getDimensions, g.getPixelDimensions
g.getDimensions = function() return 640, 576 end
g.getPixelDimensions = function() return 640, 576 end
T.eq(Renderer:fitScale(), 4, "the fixture window fits the classic surface at 4x")

local Zoom = require("src.render.Zoom")
local function scaleAt(offset, centered)
  local oldOff, oldActive, oldCentered =
    Zoom.offset, Renderer.worldActive, Renderer.uiCentered
  -- worldActive true: a live overworld pass, the one case DYNAMIC steps down
  Zoom.offset, Renderer.worldActive, Renderer.uiCentered = offset, true, centered
  local s = Renderer:uiScale()
  Zoom.offset, Renderer.worldActive, Renderer.uiCentered =
    oldOff, oldActive, oldCentered
  return s
end

T.eq(scaleAt(0, true), 4, "CENTERED at rest is the fit scale")
T.eq(scaleAt(-2, true), 4, "CENTERED zoomed out is STILL the fit scale")
T.eq(scaleAt(0, false), 4, "DYNAMIC at rest matches it")
T.eq(scaleAt(-2, false), 2, "DYNAMIC zoomed out steps the UI down, as before")

g.getDimensions, g.getPixelDimensions = realDims, realPixelDims

-- ------------------------------------------------------------- the row

-- fixture data, not Data:load(): this tier runs ROM-free in CI, so a real
-- load has no data/generated/ to read and takes the suite down with it
local OptionsMenu = require("src.ui.OptionsMenu")
local Data = T.fixtures.load()
require("src.render.Font").load(Data)

local game = { data = Data, save = SaveData.newGame(),
               stack = { states = {}, push = function() end,
                         pop = function() end, top = function() end } }
local menu = OptionsMenu.new(game)
local row
for _, r in ipairs(menu.rows) do
  if r.id == "uiLayout" then row = r end
end
T.check(row ~= nil, "OPTIONS carries a UI LAYOUT row")
T.eq(row.value(game), "CENTERED", "and it opens on CENTERED")
row.step(game, 1)
T.eq(game.save.options.uiLayout, "dynamic", "stepping it turns docking on")
T.eq(row.value(game), "DYNAMIC", "and the row says so")
row.step(game, 1)
T.eq(game.save.options.uiLayout, "centered", "stepping again returns to it")

T.finish("ui layout option")
