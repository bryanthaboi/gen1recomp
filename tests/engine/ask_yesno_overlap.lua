-- The script DSL's `ask` command (src/script/Commands.lua) has to bring its
-- YES/NO box up WHILE the question text is still on screen, the same as
-- every hand-written prompt
-- (OverworldController's healer, BattleState's nickname ask, OakSpeech,
-- MoveLearnMenu -- all TextBox opts.choice).  DisplayTextID never clears
-- the box itself before a YES/NO row; ManualTextScroll's button wait is
-- what `ask` used to run through, closing the text box first and popping a
-- bare ChoiceBox in afterwards.  Commands.ask now rides opts.choice like
-- the rest of the engine instead of chaining show_text + a second push.
--   luajit tests/engine/ask_yesno_overlap.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Commands = require("src.script.Commands")
local TextBox = require("src.render.TextBox")
local Timing = require("src.core.Timing")

local function newGame()
  local game = { save = { player = {} }, data = { text = {} } }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  -- data = {} downstream (Sound.play(game.data, ...)) keeps ChoiceBox's
  -- un-guarded beep on the headless no-audio path, same as
  -- rebind_swap_clear_bug589.lua's fixture.
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function() return false end,
  }
  return game
end

local game = newGame()
game.data.text.TEST_ASK = "Shall we heal\nyour POKEMON?"

local resumeCount = 0
local runner = { yield = function() end,
                  resume = function() resumeCount = resumeCount + 1 end }
local ctx = { game = game, runner = runner }

Commands.ask(ctx, "TEST_ASK")

eq(#game.stack.states, 1, "ask opens the question as one text box, not a text box plus a bare choice box up front")
local box = game.stack:top()
check(getmetatable(box) == TextBox, "the state on the stack is the text box")

-- type the question out
for _ = 1, 600 do
  if box.done then break end
  box:update(1 / 60)
end
check(box.done, "the question finished typing")
eq(#game.stack.states, 1, "the text box does not pop itself on its own once typing is done (#589-parity)")

-- the very next update is what used to require an A press to clear the box
-- first; now it pushes the YES/NO box straight over the still-open text
box:update(1 / 60)
eq(#game.stack.states, 2, "a YES/NO box appears while the question text is still up")
check(game.stack.states[1] == box, "the text box is still there, underneath")
local choiceBox = game.stack:top()
check(choiceBox ~= box, "the choice box is a separate state on top of it")

-- answer YES (the default cursor position) and let the 15-frame hold run
-- out, same hold rebind_swap_clear_bug589.lua's settleChoice() drains
game.input.queue = { a = true }
choiceBox:update(1 / 60)
game.input.queue = {}
for _ = 1, Timing.YES_NO_ANSWER do choiceBox:update(1 / 60) end

eq(#game.stack.states, 0, "answering pops both the choice box and the text box")
eq(ctx.lastCheck, true, "YES lands in ctx.lastCheck")
eq(resumeCount, 1, "the script runner resumes exactly once")

T.finish("ask_yesno_overlap")
