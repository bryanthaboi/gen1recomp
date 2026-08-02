-- Raw-stick rebinding, and the recognized-pad duplicate event that used to
-- defeat every controller rebind (#632).  LOVE raises love.joystickpressed
-- for EVERY stick, gamepads included, and those raise love.gamepadpressed
-- for the same press as well; Input's fixed raw table answered both, so it
-- re-asserted the factory A/B/START/SELECT map underneath a CONTROLS
-- rebind and a swapped A and B pressed at once.  A recognized pad is now
-- served by the gamepad path alone, and a raw stick's buttons are
-- rebindable as "joyN" in the same pad slot every other controller uses.
-- No pokered cite: rebinding is port-only (gap C2).
--   luajit tests/engine/rebind_joystick_bug632.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Input = require("src.core.Input")
local BindingsMenu = require("src.ui.BindingsMenu")

-- an SDL-recognized pad versus a stick with no database entry
local pad = { isGamepad = function() return true end }
local raw = { isGamepad = function() return false end }

Input:init()

-- ---- (a) a recognized pad is served by the gamepad path alone ------------
Input:reset()
Input:joystickpressed(pad, 1)
Input:step()
check(not Input:isDown("a"),
  "a recognized pad's duplicate joystick event is ignored (#632)")
Input:joystickhat(pad, 1, "u")
Input:step()
check(not Input:isDown("up"),
  "and its duplicate hat event is ignored too (#632)")

-- ---- (b) a raw stick keeps its defaults ----------------------------------
Input:reset()
Input:joystickpressed(raw, 1)
Input:step()
check(Input:isDown("a"), "a raw stick's button 1 still presses A")
Input:joystickreleased(raw, 1)
check(not Input:isDown("a"), "and its release clears A")

-- ---- (c) a "joyN" pad binding reaches the raw lookup ---------------------
Input:applyBindings({ up = { pad = "joy1" } })
Input:reset()
Input:joystickpressed(raw, 1)
Input:step()
check(Input:isDown("up"), "a joy1 rebind wins the raw button (#632)")
check(not Input:isDown("a"), "and the raw default no longer presses A")
Input:joystickreleased(raw, 1)
Input:applyBindings(nil)

-- ---- (d) the CONTROLS row captures a raw button --------------------------
-- same doubles as rebind_swap_clear_bug589: a stack the menu can pop itself
-- off and an input whose queue is one fixed step of edges.  data = {} keeps
-- ChoiceBox's un-guarded Sound.play on the headless no-audio path.
local game = { save = { options = {} }, data = {} }
function game:writeOptions() end
game.stack = {
  states = {},
  push = function(self, s) table.insert(self.states, s) end,
  pop = function(self) return table.remove(self.states) end,
  top = function(self) return self.states[#self.states] end,
}
game.input = { wasPressed = function() return false end,
               isDown = function() return false end }

local ROW_A = 5 -- BindingsMenu's BUTTONS order
local bm = BindingsMenu.new(game)
bm:beginCapture(bm.items[ROW_A])
bm:onJoystickPressed(3)
check(game.save.options.bindings == nil,
  "press alone commits nothing, the release is the commit (#589)")
bm:onJoystickReleased(3)
eq(game.save.options.bindings.a.pad, "joy3",
  "a released raw button lands in the row's pad slot (#632)")
check(bm.items[ROW_A].right:find("JOY3", 1, true) ~= nil,
  "and the row's controller column reads JOY3")

Input:init()
T.finish("rebind_joystick_bug632")
