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

-- --------------------------------------------------------- the save panel

-- engine/menus/draw_start_menu.asm:5 hlcoord 10,0
-- engine/menus/main_menu.asm:384 hlcoord 4,0
-- engine/menus/start_sub_menus.asm:645-646
do
  local StartMenu = require("src.ui.StartMenu")
  local DataFx = T.fixtures.load()
  require("src.render.Font").load(DataFx)
  local pushed = {}
  local panelGame = {
    data = DataFx, save = SaveData.newGame(), renderer = Renderer,
    stack = { states = pushed,
              push = function(_, s) pushed[#pushed + 1] = s end,
              pop = function() end,
              top = function() return pushed[#pushed] end },
  }
  panelGame.save.player.name = "RED"
  local menu = StartMenu.new(panelGame)
  pushed[#pushed + 1] = menu
  local saveRow
  for _, item in ipairs(menu.items) do
    if tostring(item.label):match("SAVE") then saveRow = item end
  end
  T.check(saveRow ~= nil, "the START menu carries a SAVE row")
  T.eq(Game.uiAnchorsHeldInStack({ states = pushed }), false,
    "the START menu alone still docks")
  local shiftIn = Game.uiShiftRightInStack
  T.check(shiftIn ~= nil and shiftIn({ states = pushed }) == false,
    "the START menu alone does not shift the screen")
  saveRow.onSelect()
  local panel = pushed[#pushed]
  T.check(panel ~= menu, "SAVE puts the panel up over the kept-open menu")
  T.eq(Game.uiAnchorsHeldInStack({ states = pushed }), false,
    "the SAVE panel does not hold the screen in the letterbox")
  T.check(shiftIn ~= nil and shiftIn({ states = pushed }) == true,
    "the SAVE panel shifts the whole screen right")

  local saveBox = require("src.ui.Theme").saveBox
  Renderer.canvas = Renderer.canvas or love.graphics.newCanvas(160, 144)
  Renderer.uiCentered, Renderer.uiAnchorHold = false, false
  Renderer:beginFrame(true)
  Renderer.uiShiftRight = shiftIn ~= nil and shiftIn({ states = pushed })
  for _, state in ipairs(pushed) do state:draw() end
  Renderer:setUIAnchor(saveBox.tx * 8, saveBox.ty * 8, saveBox.tw * 8,
                       saveBox.th * 8, "bottom")
  Renderer:setUIAnchor(0, 96, 160, 48, "bottom")
  T.eq(#(Renderer.uiAnchors or {}), 0,
    "no piece of the save screen docks on its own, so none is cut from the canvas")

  local gfx = love.graphics
  local dims, pdims = gfx.getDimensions, gfx.getPixelDimensions
  local pieces = {
    { "START box", menu.tx, menu.tw, menu.ty, menu.th },
    { "save panel", 4, 16, 0, 10 },
    { "YES/NO", saveBox.tx, saveBox.tw, saveBox.ty, saveBox.th },
    { "text box", 0, 20, 12, 6 },
  }
  for _, win in ipairs({ { 1280, 720 }, { 1000, 700 }, { 960, 544 } }) do
    local tag = ("%dx%d"):format(win[1], win[2])
    gfx.getDimensions = function() return win[1], win[2] end
    gfx.getPixelDimensions = function() return win[1], win[2] end
    local R = Renderer:frameRects()
    local want = R.vux + R.vuw - 160 * R.Ux
    T.eq(R.uox, want, tag .. ": the canvas is flush with the window's right edge")
    for _, pc in ipairs(pieces) do
      local x = R.uox + pc[2] * 8 * R.Ux
      T.eq(x - pc[2] * 8 * R.Ux, want, tag .. ": the " .. pc[1] .. " rides the same x offset")
    end
    local startRight = R.uox + (menu.tx + menu.tw) * 8 * R.Ux
    local panelRight = R.uox + 20 * 8 * R.Ux
    local textRight = R.uox + 20 * 8 * R.Ux
    T.eq(startRight, R.vux + R.vuw, tag .. ": the START box ends at the window edge")
    T.check(startRight <= panelRight and startRight <= textRight
      and menu.ty + menu.th <= 18,
      tag .. ": no START box pixel lies outside the panel and text box columns")
    Renderer.uiShiftRight = false
    local C = Renderer:frameRects()
    T.eq(C.uox, R.vux + math.floor((R.vuw - 160 * R.Ux) / 2),
      tag .. ": without the save screen the letterbox is centred as before")
    Renderer.uiCentered, Renderer.uiShiftRight = true, true
    C = Renderer:frameRects()
    T.eq(C.uox, R.vux + math.floor((R.vuw - 160 * R.Ux) / 2),
      tag .. ": CENTERED ignores the shift")
    Renderer.uiCentered, Renderer.uiShiftRight = false, true
  end
  gfx.getDimensions, gfx.getPixelDimensions = dims, pdims
  Renderer.uiAnchors, Renderer.uiShiftRight = nil, false
end

-- ----------------------------------------------------------- the bag list

-- data/text_boxes.asm:13 LIST_MENU_BOX 4,2,19,12
-- data/text_boxes.asm:28 USE_TOSS_MENU_TEMPLATE 13,10,19,14
-- engine/menus/draw_start_menu.asm:5 hlcoord 10,0
do
  local StartMenu = require("src.ui.StartMenu")
  local BagMenu = require("src.ui.BagMenu")
  local DataFx = T.fixtures.load()
  require("src.render.Font").load(DataFx)
  local pushed = {}
  local bagGame = {
    data = DataFx, save = SaveData.newGame(), renderer = Renderer,
    stack = { states = pushed,
              push = function(_, s) pushed[#pushed + 1] = s end,
              pop = function() pushed[#pushed] = nil end,
              top = function() return pushed[#pushed] end },
  }
  bagGame.save.player.name = "RED"
  require("src.inventory.Bag").add(bagGame.save, "FIX_POTION", 1, DataFx)
  local menu = StartMenu.new(bagGame)
  pushed[#pushed + 1] = menu
  local list = BagMenu.new(bagGame, { onClose = function() end })
  pushed[#pushed + 1] = list
  local bagAt = #pushed
  T.eq(Game.uiAnchorsHeldInStack({ states = pushed }), false,
    "the bag does not hold the screen in the letterbox")
  T.eq(Game.uiShiftRightInStack({ states = pushed }), true,
    "the bag shifts the whole screen right")

  local Font = require("src.render.Font")
  local baseDrawBox = Font.drawBox
  local boxes = {}
  Font.drawBox = function(tx, ty, tw, th, ...)
    boxes[#boxes + 1] = { tx = tx, ty = ty, tw = tw, th = th }
    return baseDrawBox(tx, ty, tw, th, ...)
  end
  local function boxesOf(state)
    boxes = {}
    state:draw()
    return boxes
  end
  local function boxAt(list_, ty)
    for _, b in ipairs(list_) do
      if b.ty == ty then return b end
    end
  end

  Renderer.canvas = Renderer.canvas or love.graphics.newCanvas(160, 144)
  Renderer.uiCentered, Renderer.uiAnchorHold = false, false
  Renderer:beginFrame(true)
  Renderer.uiShiftRight = Game.uiShiftRightInStack({ states = pushed })
  menu:draw()
  local listBox = boxAt(boxesOf(list), 2)
  T.check(listBox ~= nil and listBox.tx == 4 and listBox.tw == 16 and listBox.th == 11,
    "the item list box is LIST_MENU_BOX 4,2-19,12")
  T.check(list.items[1] and list.items[1].value == "FIX_POTION",
    "the bag lists the item")
  list.onChoose(list.items[1], list)
  local useToss = pushed[#pushed]
  T.check(useToss ~= list, "A on an item puts the USE/TOSS box up over the bag")
  local useTossBox = useToss ~= list and boxAt(boxesOf(useToss), 10) or nil
  T.check(useTossBox ~= nil and useTossBox.tx == 13 and useTossBox.tw == 7
    and useTossBox.th == 5,
    "the USE/TOSS box is USE_TOSS_MENU_TEMPLATE 13,10-19,14")
  Font.drawBox = baseDrawBox
  Renderer:setUIAnchor(0, 96, 160, 48, "bottom")
  T.eq(#(Renderer.uiAnchors or {}), 0,
    "no piece of the bag screen docks on its own, so none is cut from the canvas")
  T.eq(Game.uiShiftRightInStack({ states = pushed }), true,
    "the USE/TOSS box keeps the bag's shift")

  local party = setmetatable({}, { __index = require("src.ui.PartyMenu") })
  T.eq(party.isOpaque, true, "the party menu is a full-screen state")
  pushed[#pushed + 1] = party
  local over = { states = pushed }
  local drawFrom = Game.drawBaseInStack(over, #pushed)
  T.eq(drawFrom, #pushed, "the party menu over the bag is the draw base")
  T.eq(Game.uiShiftRightInStack(over, drawFrom), false,
    "a party menu opened from the bag does not ride the bag's shift")
  T.eq(Game.uiShiftRightInStack(over, bagAt), true,
    "drawn from the bag, the shift is on")
  pushed[#pushed] = nil

  local gfx = love.graphics
  local dims, pdims = gfx.getDimensions, gfx.getPixelDimensions
  for _, win in ipairs({ { 1280, 720 }, { 1000, 700 }, { 960, 544 } }) do
    local tag = ("%dx%d"):format(win[1], win[2])
    gfx.getDimensions = function() return win[1], win[2] end
    gfx.getPixelDimensions = function() return win[1], win[2] end
    Renderer.uiCentered, Renderer.uiShiftRight = false, true
    local R = Renderer:frameRects()
    local edge = R.vux + R.vuw
    T.eq(R.uox + (menu.tx + menu.tw) * 8 * R.Ux, edge,
      tag .. ": the START box under the bag ends at the window edge")
    T.eq(listBox and (R.uox + (listBox.tx + listBox.tw) * 8 * R.Ux), edge,
      tag .. ": the item list box the bag draws ends at the window edge")
    T.eq(useTossBox and (R.uox + (useTossBox.tx + useTossBox.tw) * 8 * R.Ux), edge,
      tag .. ": the USE/TOSS box the bag draws ends at the window edge")
    Renderer.uiCentered = true
    local C = Renderer:frameRects()
    T.eq(C.uox, R.vux + math.floor((R.vuw - 160 * R.Ux) / 2),
      tag .. ": CENTERED keeps the bag in the centred letterbox")
  end
  gfx.getDimensions, gfx.getPixelDimensions = dims, pdims
  Renderer.uiAnchors, Renderer.uiShiftRight, Renderer.uiCentered = nil, false, false
end

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
