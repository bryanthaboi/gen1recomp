-- BATTLE SIZE "fixed" + BATTLE BG "world": the battle draws as a fixed
-- letterbox over the map, stepped down with the survey zoom.  The PKMN and
-- ITEM menus it opens have to stay that size, and its YES/NO prompt has to
-- stay inside it.
--
-- Both broke the same way -- by reading a fact about THIS FRAME instead of
-- about the battle:
--
--   * Renderer:uiScale follows the zoom only while a world is behind the UI,
--     gated on worldActive (beginWorldPass set it this frame).  A "world"-bg
--     battle is non-opaque so the map keeps drawing under it -- but PartyMenu
--     and ListMenu ARE opaque, so pushing one makes StateStack:visibleBase
--     skip the map, the world pass never runs, and the menu loses the
--     step-down and blits a whole integer scale larger than the battle it
--     just covered.  ("fill" hid this: it overrides the scale outright.)
--
--   * ChoiceBox bottom-anchored unconditionally, which docks it to the
--     WINDOW's bottom edge.  That is right only when it is riding the
--     dialogue box below it, which is anchored there too.  The battle draws
--     its own text inside the battle canvas, so the switch offer's YES/NO was
--     the only piece of that prompt flung to the window edge -- further off
--     the smaller the fixed battle is drawn.
--   luajit tests/engine/battle_fixed_menu_scale.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Renderer = require("src.render.Renderer")
local Zoom = require("src.render.Zoom")
local TextBox = require("src.render.TextBox")
local ChoiceBox = require("src.ui.ChoiceBox")

-- ------------------------------------------------- the UI scale holds its size

-- pin the window so the scales below are exact numbers rather than whatever
-- the runner happens to be sized at (this suite also runs under real LOVE)
local g = love.graphics
local realDims, realPixelDims = g.getDimensions, g.getPixelDimensions
g.getDimensions = function() return 640, 576 end
g.getPixelDimensions = function() return 640, 576 end

-- 640x576 fits the 160x144 classic surface at exactly 4x
T.eq(Renderer:fitScale(), 4, "the fixture window fits the classic surface at 4x")

local function uiScaleWith(offset, worldActive, hold)
  local oldOffset, oldActive, oldHold =
    Zoom.offset, Renderer.worldActive, Renderer.uiWorldHold
  Zoom.offset, Renderer.worldActive, Renderer.uiWorldHold =
    offset, worldActive, hold
  local s = Renderer:uiScale()
  Zoom.offset, Renderer.worldActive, Renderer.uiWorldHold =
    oldOffset, oldActive, oldHold
  return s
end

T.eq(uiScaleWith(0, true, false), 4, "unzoomed, the UI is the fit scale")
T.eq(uiScaleWith(-2, true, false), 2,
  "zoomed out over a live world pass, the UI steps down with it")
T.eq(uiScaleWith(-2, false, false), 4,
  "with no world behind it at all (title screen), the zoom is ignored")

-- the fix: the party menu / bag ended the world pass, but the battle under
-- them is still drawn over the map, so the surface must not grow
T.eq(uiScaleWith(-2, false, true), 2,
  "an opaque menu over a world-bg battle keeps the battle's stepped-down scale")
T.eq(uiScaleWith(0, false, true), 4,
  "and the hold changes nothing when the player never zoomed out")

g.getDimensions, g.getPixelDimensions = realDims, realPixelDims

-- the hold is the same whole-stack answer the dim already uses, so a menu
-- opened over the battle cannot drop it for a frame (Game:draw wires
-- uiWorldHold to worldBgBattleDim ~= nil; battle_fit_option covers the scan)
local Game = require("src.core.Game")
local BattleState = require("src.battle.BattleState")
-- isOpaque false is what "world" actually does to a live battle (BattleState
-- drops it per-instance at start, so the class default stays opaque for every
-- other battle) -- and it is the whole reason the map draws underneath
local worldBattle = setmetatable(
  { game = { save = { options = { battleBg = "world" } } }, isOpaque = false },
  { __index = BattleState })
T.check(Game.worldBgBattleDim({ states = { {}, worldBattle, {} } }) ~= nil,
  "the stack scan the hold reads still finds the battle under an opaque menu")

-- --------------------------------------------- the backdrop holds under menus

-- The battle establishes the surround too, and the same opaque menu used to
-- take that over: it becomes visibleBase, the overworld stops drawing, and
-- the world the battle was composed over collapses to a flat black clear.
local overworld = { isOpaque = true }
local menu = { isOpaque = true } -- PartyMenu / ListMenu
local whiteBattle = setmetatable(
  { game = { save = { options = { battleBg = "white" } } } },
  { __index = BattleState })
local function stack(...) return { states = { ... },
  visibleBase = function(self)
    for i = #self.states, 1, -1 do
      if self.states[i].isOpaque then return i end
    end
    return 1
  end } end

local s = stack(overworld, worldBattle, menu)
T.eq(s:visibleBase(), 3, "the menu is the topmost opaque state, as before")
T.eq(Game.drawBaseInStack(s, s:visibleBase()), 1,
  "but the frame still starts at the overworld, so the map keeps drawing")

-- unchanged everywhere else
local s2 = stack(overworld, worldBattle)
T.eq(s2:visibleBase(), 1, "the battle alone already drew from the overworld")
T.eq(Game.drawBaseInStack(s2, s2:visibleBase()), 1, "and still does")
local s3 = stack(overworld, whiteBattle, menu)
T.eq(Game.drawBaseInStack(s3, s3:visibleBase()), 3,
  "a white-bg battle has no map to hold, so nothing moves")
local s4 = stack(overworld, menu)
T.eq(Game.drawBaseInStack(s4, s4:visibleBase()), 2,
  "and a menu outside a battle is untouched")
T.eq(Game.drawBaseInStack(stack(overworld), 1), 1, "a lone base is safe")
T.eq(Game.drawBaseInStack(nil, 1), 1, "and so is no stack at all")

-- ------------------------------------------- the YES/NO stays with its screen

-- a bare choice box -- the battle's switch offer, a shop or PC confirm -- has
-- no anchored dialogue box under it to ride
T.eq(ChoiceBox.new({}, function() end).anchor, nil,
  "a bare choice box does not anchor itself to the window edge")
T.eq(ChoiceBox.new({}, function() end, { defaultNo = true }).anchor, nil,
  "and neither does one that only asked to start on NO")

-- ...but the one a dialogue box opens does, because that box is anchored too
local game = { save = { player = {} }, data = { text = {} } }
game.stack = {
  states = {},
  push = function(self, s) table.insert(self.states, s) end,
  pop = function(self) return table.remove(self.states) end,
  top = function(self) return self.states[#self.states] end,
}
game.input = {
  wasPressed = function() return false end,
  isDown = function() return false end,
}

local box = TextBox.new(game, "Shall we heal\nyour POKEMON?", nil,
                        { choice = function() end })
game.stack:push(box)
for _ = 1, 600 do
  if box.done then break end
  box:update(1 / 60)
end
T.check(box.done, "the question finished typing")
box:update(1 / 60) -- the update after done is the one that pushes the choice
T.eq(#game.stack.states, 2, "the dialogue box opened its YES/NO")
T.eq(game.stack:top().anchor, "bottom",
  "a choice box riding a dialogue box shares its bottom anchor")

-- ...and inside a battle even THAT one stays put, because the battle is the
-- screen: the caught-mon nickname prompt prints on the blanked battle field
-- (BattleState.blankForAskName), and docking it to the window edge drops it a
-- whole letterbox below what it is printed on.
T.eq(BattleState.holdsUIAnchors, true, "a battle composes its own screen")
T.eq(Game.uiAnchorsHeldInStack(stack(overworld, worldBattle)), true,
  "so the anchors are held while it is up")
T.eq(Game.uiAnchorsHeldInStack(stack(overworld, worldBattle, {})), true,
  "including for the text box and YES/NO it opens above itself")
T.eq(Game.uiAnchorsHeldInStack(stack(overworld)), false,
  "the overworld's own dialogue box still docks to the screen edge")
T.eq(Game.uiAnchorsHeldInStack(nil), false, "and no stack is safe")

Renderer.uiAnchors = nil
Renderer.uiAnchorHold = true
Renderer:setUIAnchor(0, 96, 160, 48, "bottom")
T.eq(Renderer.uiAnchors, nil, "a held anchor never reaches the frame")
Renderer.uiAnchorHold = false
Renderer:setUIAnchor(0, 96, 160, 48, "bottom")
T.eq(#(Renderer.uiAnchors or {}), 1, "and an unheld one still does")
Renderer.uiAnchors = nil

T.finish("battle fixed menu scale")
