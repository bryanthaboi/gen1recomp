-- CONTROLS rebinding, the #589 feature set beyond the capture deferral that
-- tests/engine/rebind_capture_bug510.lua pins: a captured pad button another
-- row effectively owns SWAPS with that row (no input serves two rows, no row
-- goes empty), a second input of either kind cancels an armed capture,
-- SELECT forgets one row's rebind so it falls back to the default, and START
-- confirms then drops the whole overlay.  Everything is driven through the
-- entry points Game routes raw input to (onKeyPressed/onKeyReleased/
-- onGamepadPressed/onGamepadReleased) and through update() for the menu
-- keys.  No pokered cite: rebinding is port-only (gap C2).
--   luajit tests/engine/rebind_swap_clear_bug589.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Input = require("src.core.Input")
local Strings = require("src.core.Strings")
local Timing = require("src.core.Timing")
local BindingsMenu = require("src.ui.BindingsMenu")

-- same doubles as rebind_capture_bug510: a stack the menu can pop itself
-- off and an input whose queue is one fixed step of edges.  data = {} keeps
-- ChoiceBox's un-guarded Sound.play on the headless no-audio path.
local function newGame()
  local game = { save = { options = {} }, data = {}, wroteOptions = 0 }
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
  state.game.input.queue = { [btn] = true }
  state:update(1 / 60)
  state.game.input.queue = {}
end

-- ChoiceBox now holds YES/NO answers on screen for Timing.YES_NO_ANSWER
-- frames before it commits and pops (DisplayTwoOptionMenu's 15-frame hold,
-- #GH-627 timing parity); a bare press only arms the choice, so answering
-- it needs the hold run out before the pop/commit is visible.
local function settleChoice(state)
  for _ = 1, Timing.YES_NO_ANSWER do state:update(1 / 60) end
end

-- rows are BindingsMenu's BUTTONS order
local ROW_A, ROW_B, ROW_SELECT = 5, 6, 8

-- ---- (a) pad capture swaps with the row that owns the button --------------

Input:init()
local game = newGame()
local bm = BindingsMenu.new(game)
game.stack:push(bm)

bm.index = ROW_A
press(bm, "a")
eq(bm.capture, bm.items[ROW_A], "A arms the A row")
bm:onGamepadPressed("b")
check(game.save.options.bindings == nil,
      "a pad capture holds its press; nothing stores before the release")
bm:onGamepadReleased("b")
local bindings = game.save.options.bindings
eq(bindings.a.pad, "b", "releasing pad B stores it on the A row")
eq(bindings.b.pad, "a",
   "and the B row, which owned pad B, inherits the A row's old pad (#589)")
eq(bm.items[ROW_A].right, "Z/B", "the A row redraws with the new pad")
eq(bm.items[ROW_B].right, "X/A", "so does the B row")

-- after applying, every row's effective pad is unique and none is lost
Input:applyBindings(bindings)
eq(Input.padBindings["b"], "a", "applied: pad B is action A")
eq(Input.padBindings["a"], "b", "applied: pad A is action B")
local seen, actions = {}, {}
for button, action in pairs(Input.padBindings) do
  check(not seen[action], "no action is reachable from two pad buttons: "
        .. tostring(action))
  seen[action] = button
  actions[#actions + 1] = action
end
eq(#actions, 8, "all eight actions still have exactly one pad button")
Input:init()

-- ---- (b) a second input while the first is held cancels -------------------

-- key then key: the straggling release of the first press writes nothing
bm.index = ROW_SELECT
press(bm, "a")
bm:onKeyPressed("q")
bm:onKeyPressed("w")
check(bm.capture == nil, "a second key cancels the armed capture")
if bm.onKeyReleased then bm:onKeyReleased("q") end
check(bindings.select == nil, "the cancelled key capture wrote nothing")

-- key then pad: cancel crosses input kinds too
press(bm, "a")
bm:onKeyPressed("q")
bm:onGamepadPressed("x")
check(bm.capture == nil, "a pad press cancels a held key capture")
if bm.onKeyReleased then bm:onKeyReleased("q") end
if bm.onGamepadReleased then bm:onGamepadReleased("x") end
check(bindings.select == nil, "and still nothing stored")
local writesAfterSwap = game.wroteOptions

-- ---- (c) commit happens on release, not press -----------------------------

press(bm, "a")
bm:onKeyPressed("q")
check(bindings.select == nil, "press alone commits nothing (#589)")
eq(game.wroteOptions, writesAfterSwap, "and touches nothing on disk")
bm:onKeyReleased("q")
eq(bindings.select.key, "q", "the release is the commit")
eq(bm.items[ROW_SELECT].right, "Q/BACK", "the row shows the new key")

-- ---- (d) SELECT on a row forgets its rebind -------------------------------

press(bm, "select")
check(bindings.select == nil, "SELECT drops the row's overlay entry (#589)")
eq(bm.items[ROW_SELECT].right, "TAB/BACK", "the row falls back to the default")
-- the swapped B row clears the same way; a second SELECT on the now
-- default row is a no-op, not a write
local writes = game.wroteOptions
bm.index = ROW_B
press(bm, "select")
eq(game.wroteOptions, writes + 1, "clearing the swapped B row writes once")
check(game.save.options.bindings.b == nil, "and drops its overlay entry")
press(bm, "select")
eq(game.wroteOptions, writes + 1, "clearing an already-default row writes nothing")

-- ---- (e) START confirms, then drops the whole overlay ---------------------

-- rebuild a dirty overlay to reset
bm.index = ROW_A
press(bm, "a")
bm:onKeyPressed("p")
bm:onKeyReleased("p")
eq(game.save.options.bindings.a.key, "p", "fixture rebind in place")

press(bm, "start")
local box = game.stack:top()
check(box ~= bm, "START pushes the confirm box instead of resetting outright")
eq(bm.footer, Strings("RESET ALL BINDINGS?"),
   "the footer doubles as the prompt")

-- the box starts on NO: a bare A press must keep the overlay
press(box, "a")
settleChoice(box)
eq(game.stack:top(), bm, "answering pops the box")
check(game.save.options.bindings ~= nil, "NO keeps the bindings (defaultNo)")
eq(bm.items[ROW_A].right, "P/B", "and the rows keep showing them")

-- again, flip to YES: the overlay goes away and every row reads default
press(bm, "start")
box = game.stack:top()
press(box, "up")
press(box, "a")
settleChoice(box)
check(game.save.options.bindings == nil, "YES clears options.bindings (#589)")
eq(bm.items[ROW_A].right, "Z/A", "the A row reads its default again")
eq(bm.items[ROW_B].right, "X/B", "so does the B row the swap had touched")

-- closing after the reset leaves the live map at the defaults
press(bm, "b")
eq(#game.stack.states, 0, "B closes the screen")
eq(Input.keyBindings["z"], "a", "the live map is back to Z = A")
eq(Input.padBindings["b"], "b", "and pad B = B")

Input:init()
T.finish("rebind_swap_clear_bug589")
