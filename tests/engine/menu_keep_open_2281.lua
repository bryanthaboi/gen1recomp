-- engine/events/cinnabar_lab.asm:29, home/text_script.asm:105
--   luajit tests/engine/menu_keep_open_2281.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.Sound"] = { play = function() end }

local Menu = require("src.ui.Menu")

local function newGame()
  local game = { data = {} }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function() return false end,
  }
  return game
end

local function press(state, btn)
  state.game.input.queue = { [btn] = true }
  state:update(1 / 60)
  state.game.input.queue = {}
end

local function fossilMenu(opts)
  local game = newGame()
  local fired = {}
  local items = {
    { label = "DOME FOSSIL", keepOpen = true,
      onSelect = function() fired[#fired + 1] = "DOME FOSSIL" end },
    { label = "OLD AMBER", keepOpen = true,
      onSelect = function() fired[#fired + 1] = "OLD AMBER" end },
  }
  opts = opts or {}
  opts.tx, opts.ty, opts.tw = 0, 0, 15
  local menu = Menu.new(game, items, opts)
  game.stack:push(menu)
  return menu, game, fired
end

local menu, game, fired = fossilMenu()
press(menu, "a")
eq(#game.stack.states, 1, "a keepOpen row leaves the menu on the stack")
check(game.stack:top() == menu, "and the menu is still the state that was pushed")
eq(fired[1], "DOME FOSSIL", "while onSelect still ran for the picked row")

menu.frozen = true
press(menu, "down")
eq(menu.index, 1, "a frozen menu ignores the d-pad")
press(menu, "a")
eq(#fired, 1, "and swallows A rather than re-running onSelect")
eq(#game.stack.states, 1, "with nothing popped")
press(menu, "b")
eq(#game.stack.states, 1, "B on a frozen menu pops nothing")

local cancelled = 0
local keep, keepGame = fossilMenu({ keepOnCancel = true,
  onCancel = function() cancelled = cancelled + 1 end })
press(keep, "b")
eq(cancelled, 1, "keepOnCancel still fires onCancel on B")
eq(#keepGame.stack.states, 1, "but leaves the menu box on screen")

local plainGame = newGame()
local plainFired, plainCancel = 0, 0
local plain = Menu.new(plainGame,
  { { label = "POKéDEX", onSelect = function() plainFired = plainFired + 1 end } })
plainGame.stack:push(plain)
press(plain, "a")
eq(#plainGame.stack.states, 0, "an ordinary menu still pops itself on A")
eq(plainFired, 1, "and still runs onSelect")

plainGame.stack:push(plain)
plain.onCancel = function() plainCancel = plainCancel + 1 end
press(plain, "b")
eq(#plainGame.stack.states, 0, "and still pops itself on B")
eq(plainCancel, 1, "with onCancel after the pop")

eq(plain.frozen, nil, "frozen is unset for every caller that does not ask")
eq(plain.keepOnCancel, false, "and keepOnCancel defaults off")

T.finish("menu_keep_open_2281")
