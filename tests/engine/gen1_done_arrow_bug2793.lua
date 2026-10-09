-- home/text.asm:209 PromptText, :221 DoneText; home/joypad2.asm:55; home/window.asm:225

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local TextBox = require("src.render.TextBox")
local Sound = require("src.core.Sound")

local realPress, realPlay = Sound.playPress, Sound.play
Sound.playPress = function() return nil end
Sound.play = function() return nil end

local function newGame(version, generation)
  local game = {
    save = { player = {}, options = { textSpeed = "FAST" },
             generation = generation or 1, version = version },
    data = { text = {} },
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

local function run(game, box, untilFn, press)
  local frames = 0
  while not untilFn(box) and frames < 2000 do
    game.input.queue.a = press and box.waiting and frames % 2 == 0 or nil
    box:update(1 / 60)
    frames = frames + 1
  end
  game.input.queue.a = nil
  return frames < 2000
end

local function finished(text, version, opts)
  local game = newGame(version)
  local box = TextBox.new(game, text, nil, opts)
  game.stack:push(box)
  check(run(game, box, function(b) return b.done end, true), "the text types out")
  return box, game
end

-- text/OaksLab.asm:187
local FED_UP = "{RIVAL}: Gramps!\nI'm fed up with\vwaiting!{DONE}"

for _, version in ipairs({ "red", "blue", "yellow" }) do
  local box = finished(FED_UP, version)
  check(not box:arrowVisible(), version .. ": a `done` text ends with no arrow")
end

for _, version in ipairs({ "red", "yellow" }) do
  local box = finished("Take your time.{PROMPT}", version)
  check(box:arrowVisible(), version .. ": a `prompt` text ends with the arrow")
end

do
  local box = finished("Hi")
  check(box:arrowVisible(), "an untagged text keeps the arrow")
end

do
  local game = newGame("red")
  local box = TextBox.new(game, FED_UP, nil)
  game.stack:push(box)
  check(run(game, box, function(b) return b.waiting or b.done end),
    "the cont line is reached")
  check(box.waiting and box.contAdvance, "the `cont` waits before scrolling")
  check(box:arrowVisible(), "and shows the arrow there (_ContText)")
end

do
  local game = newGame("red")
  local box = TextBox.new(game, "First\npage.\fSecond\npage.{DONE}", nil)
  game.stack:push(box)
  check(run(game, box, function(b) return b.waiting or b.done end),
    "the para break is reached")
  check(box.waiting and not box.contAdvance, "the `para` waits before clearing")
  check(box:arrowVisible(), "and shows the arrow there (Paragraph)")
  game.input.queue.a = true
  box:update(1 / 60)
  game.input.queue.a = nil
  check(run(game, box, function(b) return b.done end, true), "the last page types out")
  check(not box:arrowVisible(), "and the `done` end has no arrow")
end

do
  local box = finished("Hi{DONE}", "red", { stay = { prompt = true } })
  check(box:arrowVisible(), "stay.prompt keeps its arrowed wait on a `done` text")
end

do
  local box = finished("Hi{DONE}", "red",
    { auto = { wait = false, delay = 0, promptFirst = true } })
  check(box:arrowVisible(), "auto.promptFirst keeps its arrowed wait too")
end

do
  local game = newGame("gold", 2)
  local box = TextBox.new(game, "Hi{DONE}", nil)
  game.stack:push(box)
  check(run(game, box, function(b) return b.done end), "gold text types out")
  check(not box:arrowVisible(), "gold `done` stays arrowless")
end

Sound.playPress, Sound.play = realPress, realPlay

T.finish("gen1 done arrow bug2793")
