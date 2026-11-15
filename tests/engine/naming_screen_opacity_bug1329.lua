-- The NEW NAME / preset box drew on top of a full letter grid because
-- NamingScreen stayed isOpaque while the preset Menu was up, so the stack's
-- visibleBase never fell through to the screen underneath (#1329).
-- engine/movie/oak_speech/oak_speech2.asm:1
--   luajit tests/engine/naming_screen_opacity_bug1329.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Sound"] = { play = function() end }

local StateStack = require("src.core.StateStack")
local NamingScreen = require("src.ui.NamingScreen")

local function newGame()
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local game = { data = { text = dofile("tests/fixture_data/text.lua") } }
  game.stack = stack
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function() return false end,
  }
  return game, stack
end

local game, stack = newGame()

-- stand-in for OakSpeech: opaque, and the state a fixed background lives on
local backgroundDraws = 0
local background = { isOpaque = true, draw = function() backgroundDraws = backgroundDraws + 1 end }
stack:push(background)

local result = { name = nil }
local ns = NamingScreen.new(game,
  { presets = { "RED", "ASH", "JACK" }, onDone = function(n) result.name = n end })
stack:push(ns) -- StateStack:push calls ns:enter(), which pushes the preset Menu

eq(ns.choosing, true, "the screen marks itself as choosing a preset")
eq(ns.isOpaque, false, "isOpaque is shadowed false while the preset box is up")

local menu = stack:top()
check(menu ~= nil and menu ~= ns, "the preset Menu is on top of the naming screen")
eq(#menu.items, 4, "NEW NAME plus the three presets")
eq(menu.items[1].label, "NEW NAME", "row 1 is NEW NAME")

eq(stack:visibleBase(), 1, "the background (index 1) is visible, not the naming screen")

backgroundDraws = 0
stack:draw()
eq(backgroundDraws, 1, "the background actually got a draw call this frame")

-- picking NEW NAME (row 1) restores the grid's normal opacity
menu.index = 1
menu.game.input.queue.a = true
menu:update(0)
menu.game.input.queue.a = false

check(stack:top() == ns, "the Menu popped itself, the naming screen is back on top")
eq(ns.choosing, nil, "choosing cleared")
eq(rawget(ns, "isOpaque"), nil, "the instance field is cleared, unshadowing the class default")
eq(ns.isOpaque, true, "isOpaque now reads true again, through the class default")
eq(stack:visibleBase(), 2, "the naming screen itself is now the opaque base")

-- a preset pick instead closes the whole naming flow with that name
local game2, stack2 = newGame()
local background2 = { isOpaque = true, draw = function() end }
stack2:push(background2)
local result2 = { name = nil }
local ns2 = NamingScreen.new(game2,
  { presets = { "RED", "ASH", "JACK" }, onDone = function(n) result2.name = n end })
stack2:push(ns2)
local menu2 = stack2:top()
eq(menu2.items[4].label, "JACK", "row 4 is the third preset")
menu2.index = 4 -- "JACK"
menu2.game.input.queue.a = true
menu2:update(0)

eq(result2.name, "JACK", "selecting a preset pops the whole flow with that name")
eq(#stack2.states, 1, "only the background remains on the stack")

T.finish("naming screen opacity bug 1329")
