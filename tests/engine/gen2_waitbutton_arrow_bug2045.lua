-- ../pokecrystal/home/joypad.asm:302 WaitButton

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local TextBox = require("src.render.TextBox")
local Sound = require("src.core.Sound")
local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")

local presses = 0
local realPress, realPlay = Sound.playPress, Sound.play
Sound.playPress = function() presses = presses + 1 return nil end
Sound.play = function() return nil end

local function newGame()
  local game = {
    save = { player = {}, options = { textSpeed = "FAST" }, generation = 2 },
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

local function runOut(box)
  local frames = 0
  while not box.done and frames < 600 do
    box:update(1 / 60)
    frames = frames + 1
  end
end

-- ../pokecrystal/maps/Route30.asm:302 YoungsterMikeySeenText
do
  local game = newGame()
  local popped = false
  local box = TextBox.new(game, "I'm gonna win,\nfor sure!",
                          function() popped = true end, { waitButton = true })
  game.stack:push(box)
  runOut(box)
  check(box.done, "the seen text finished typing")
  check(not box:arrowVisible(), "a done text shows no blinking cursor")

  presses = 0
  game.input.queue.a = true
  box:update(1 / 60)
  check(popped, "A still closes it: WaitButton is a real press")
  eq(presses, 0, "and WaitButton plays no SFX")
  eq(#game.stack.states, 0, "the box popped itself")
end

do
  local game = newGame()
  local box = TextBox.new(game, "I'm gonna win,\nfor sure!", nil,
                          { waitButton = true })
  box.waiting = true
  check(box:arrowVisible(), "a mid-text page break still arrows")
end

-- ../pokecrystal/home/text.asm:548 PromptText
do
  local game = newGame()
  local popped = false
  local box = TextBox.new(game, "I'm gonna win,\nfor sure!",
                          function() popped = true end)
  game.stack:push(box)
  runOut(box)
  check(box:arrowVisible(), "a box with no waitButton opt still arrows")
  presses = 0
  game.input.queue.a = true
  box:update(1 / 60)
  check(popped, "and closes on A")
  eq(presses, 1, "with the press beep the Gen 1 path expects")
end

eq(TextBox.new(newGame(), "hi").waitButton, nil,
  "waitButton is opt-in; no Gen 1 caller sets it")

Sound.playPress, Sound.play = realPress, realPlay

-- ../pokecrystal/engine/events/trainer_scripts.asm:19
local function arrowsFor(tail)
  local scripts = {
    generation = 2,
    ["s:t"] = {
      { op = "opentext" },
      { op = "writetext", text = "t:seen" },
      { op = tail },
      { op = "closetext" },
      { op = "end" },
    },
  }
  local seen
  local vm = Vm.new(scripts, { ["t:seen"] = "I'm gonna win,\nfor sure!" },
                    Events.new(), {
    showText = function(body, onDone, stay, hold, sfxWait, arrows)
      seen = { body = body, arrows = arrows }
      onDone()
    end,
  })
  check(vm:start("s:t"), "the trainer script starts")
  for _ = 1, 200 do vm:update() end
  check(seen, "the box went up")
  return seen.arrows
end

eq(arrowsFor("waitbutton"), false, "writetext / waitbutton is cursorless")
eq(arrowsFor("promptbutton"), true, "writetext / promptbutton blinks")

T.finish("gen2 waitbutton arrow bug2045")
