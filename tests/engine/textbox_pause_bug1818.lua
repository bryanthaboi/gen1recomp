-- The forget-a-move text is not one uninterrupted string: pokered's
-- OneTwoAndText holds the box with text_pause, plays SFX_SWAP, prints
-- " Poof!" and holds it again before the paragraph break
-- (engine/pokemon/learn_move.asm:208-222, home/text.asm:492-504).  The port
-- typed all of it straight through in silence (#1818).  TextBox.PAUSE now
-- carries those waits inside the string, with opts.pauseSounds naming the
-- sfx each one fires.  ROM-free.
--   luajit tests/engine/textbox_pause_bug1818.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local TextBox = require("src.render.TextBox")
local MoveLearnMenu = require("src.ui.MoveLearnMenu")
local Sound = require("src.core.Sound")

local played = {}
local realPlay = Sound.play
Sound.play = function(data, name)
  played[#played + 1] = name
  return nil
end

local function newGame()
  local game = {
    save = { player = {}, options = { textSpeed = "FAST" } },
    data = { text = dofile("tests/fixture_data/text.lua"), moves = { MEGA_PUNCH = { name = "MEGA PUNCH" } },
             pokemon = { NIDORINO = { name = "NIDORINO" } } },
  }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function(self, btn) return self.queue[btn] or false end,
  }
  return game
end

local game = newGame()
local box = TextBox.new(game, "1, 2 and..." .. TextBox.PAUSE .. " Poof!",
                        nil, { pauseSounds = { "Swap" } })

eq(box.pages[1][1], "1, 2 and... Poof!",
   "the marker is stripped out of the line the font ever sees")
check(box.pauseAt and box.pauseAt[1] and box.pauseAt[1][1],
      "the pause is re-anchored onto page 1, line 1")
eq(box.pauseAt[1][1][11], 1, "it sits on the 11th glyph, the last of \"1, 2 and...\"")

-- type up to the marker
local frames = 0
while not box.pauseFrames and frames < 600 do
  box:update(1 / 60)
  frames = frames + 1
end
check(box.pauseFrames, "typing stops at the marker")
eq(box.charIndex, 11, "it stops with \"1, 2 and...\" printed and nothing after it")
eq(#played, 0, "SFX_SWAP has not sounded yet -- the wait comes first")

local frozen = box.charIndex
for _ = 1, 31 do
  box:update(1 / 60)
  if #played > 0 then break end
  eq(box.charIndex, frozen, "nothing types while the pause runs")
end
eq(played[1], "Swap", "the wait ends with SFX_SWAP (learn_move.asm:210-213)")

for _ = 1, 600 do
  if box.done then break end
  box:update(1 / 60)
end
check(box.done, "\" Poof!\" types out after the sound")
eq(box.charIndex, 17, "the whole line printed, marker included in nothing")

-- a held A/B skips the wait: TextCommand_PAUSE reads hJoyHeld
local held = newGame()
held.input.queue = { a = true }
local box2 = TextBox.new(held, "1, 2 and..." .. TextBox.PAUSE .. " Poof!",
                         nil, { pauseSounds = { "Swap" } })
local before = #played
for _ = 1, 40 do
  if box2.done then break end
  box2:update(1 / 60)
end
check(box2.done, "with A held the box runs straight through the pause")
check(#played > before, "the sound still plays on the skipped wait")

-- and the real caller wires both waits with the swap on the first
local mlm = MoveLearnMenu.new(game, { species = "NIDORINO", level = 20,
                                      moves = {} }, "MEGA_PUNCH")
mlm.forgot = "HORN ATTACK"
game.stack:push(mlm)
mlm:finish(true)
local learned = game.stack:top()
check(learned.pauseAt, "the learned-move box carries text_pause waits")
eq(learned.pauseSounds[1], "Swap", "the first wait carries SFX_SWAP")
local count = 0
for _, lines in pairs(learned.pauseAt) do
  for _, chars in pairs(lines) do
    for _ in pairs(chars) do count = count + 1 end
  end
end
eq(count, 2, "both of learn_move.asm's text_pause commands survive")

Sound.play = realPlay
T.finish()
