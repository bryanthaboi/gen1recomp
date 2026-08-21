-- CONTROLS rebinding: a captured key must not reach the live map while the
-- screen that captured it is still steering by that map (#510).  Swapping A
-- and B used to close the screen mid-swap, because Input:applyBindings ran
-- inside BindingsMenu:storeBinding and turned the player's next confirm
-- press into a cancel.  A capture commits on the RELEASE of its press, a
-- second held input cancels it, and a captured input that another row owns
-- swaps rather than steals (#589).  No pokered cite: rebinding is
-- port-only (gap C2).
--   luajit tests/engine/rebind_capture_bug510.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Input = require("src.core.Input")
local BindingsMenu = require("src.ui.BindingsMenu")

-- the two doubles BindingsMenu touches: a stack it can pop itself off and
-- an input whose queue is one fixed step of edges
local function newGame()
  local game = { save = { options = {} }, wroteOptions = 0 }
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
  function game:writeOptions() self.wroteOptions = self.wroteOptions + 1 end
  return game
end

local function press(state, btn)
  while (state.inputHold or 0) > 0 do
    state.game.input.queue = {}
    state:update(1 / 60)
  end
  state.game.input.queue = { [btn] = true }
  state:update(1 / 60)
  state.game.input.queue = {}
end

local function openMenu(game)
  local bm = BindingsMenu.new(game)
  game.stack:push(bm)
  return bm
end

-- rows are BindingsMenu's BUTTONS order; 5 = A, 6 = B
local ROW_A, ROW_B = 5, 6

-- The mechanism, pinned so a future "just apply it immediately" revert
-- fails here: a rebind overwrites whatever the key used to do, so B = Z
-- costs Z its default A action.
Input:init()
eq(Input.keyBindings["z"], "a", "Z presses A in the default map")
Input:applyBindings({ b = { key = "z" } })
eq(Input.keyBindings["z"], "b",
   "applying B = Z takes Z away from A, so a live apply would flip confirm "
   .. "into cancel")
Input:init()

-- The reporter's flow: arm B, bind Z to it, then keep using the menu.
local game = newGame()
local bm = openMenu(game)
press(bm, "a")            -- open the row the cursor starts on to prove arming
eq(bm.capture, bm.items[1], "A on a row arms the capture")
bm:onKeyPressed("escape")
check(bm.capture == nil, "escape disarms an armed capture")
check(game.save.options.bindings == nil,
      "escaping a capture writes no binding")
eq(game.wroteOptions, 0, "and does not touch options on disk")

bm.index = ROW_B
press(bm, "a")
bm:onKeyPressed("z")
check(game.save.options.bindings == nil,
      "a capture holds its press; nothing stores before the release (#589)")
bm:onKeyReleased("z")
eq(game.save.options.bindings.b.key, "z", "releasing the press stores B = Z")
eq(bm.items[ROW_B].right, "Z/B", "the row shows the new key straight away")
eq(game.wroteOptions, 1, "the choice persists immediately")
eq(Input.keyBindings["z"], "a",
   "but the live map still reads Z as A while the screen is open (#510)")
eq(#game.stack.states, 1, "capturing Z does not close the screen")

-- Z was the A row's effective key, so the steal became a swap: the A row
-- inherits B's previous key and no key serves two rows (#589)
eq(game.save.options.bindings.a.key, "x",
   "capturing A's key for B hands A the old B key")
eq(bm.items[ROW_A].right, "X/A", "and the A row redraws with it")

-- the next Z the player presses is still confirm, so the A row can be armed
bm.index = ROW_A
press(bm, "a")
eq(bm.capture, bm.items[ROW_A], "the A row arms instead of the screen closing")
bm:onKeyPressed("x")
bm:onKeyReleased("x")
eq(game.save.options.bindings.a.key, "x", "re-capturing A's own key keeps it")
eq(Input.keyBindings["x"], "b", "and X is still cancel until the screen closes")

-- closing commits both halves at once, through ListMenu's onCancel
press(bm, "b")
eq(#game.stack.states, 0, "B closes the rebind screen")
eq(Input.keyBindings["z"], "b", "closing puts the swap live: Z is B")
eq(Input.keyBindings["x"], "a", "and X is A")

-- A close that never runs the hook still ends up correct, because
-- Game:applyOptions re-applies save.options.bindings on load.
Input:init()
Input:applyBindings(game.save.options.bindings)
eq(Input.keyBindings["z"], "b", "a reload reaches the same map as the close")

-- pad captures ride the same deferral
Input:init()
local padGame = newGame()
local padBm = openMenu(padGame)
padBm.index = ROW_B
press(padBm, "a")
padBm:onGamepadPressed("y")
padBm:onGamepadReleased("y")
eq(padGame.save.options.bindings.b.pad, "y", "a pad capture stores")
eq(Input.padBindings["y"], nil, "and stays out of the live pad map until close")

-- a second input going down while the first is held backs the capture out
-- with no keyboard in reach, the pad's Escape (#589)
padBm.index = ROW_A
press(padBm, "a")
padBm:onGamepadPressed("x")
padBm:onGamepadPressed("b")
check(padBm.capture == nil, "a second press cancels the armed capture")
-- Game only calls the hook while it is armed; the straggling release of
-- the first button reaches a disarmed menu and stores nothing
if padBm.onGamepadReleased then padBm:onGamepadReleased("x") end
eq(padGame.save.options.bindings.a, nil,
   "a cancelled capture's release writes no binding")

press(padBm, "b")
eq(Input.padBindings["y"], "b", "closing commits the pad half too")

Input:init()
T.finish("rebind_capture_bug510")
