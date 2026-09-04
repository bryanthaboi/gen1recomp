-- ../pokecrystal/home/text.asm:548 PromptText, :566 DoneText

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Json = require("src.link.Json")
local Extractor = require("src.import.RomExtractorGen2")
local TextBox = require("src.render.TextBox")
local Sound = require("src.core.Sound")
local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")
local romText = require("src.core.RomText")
local CommonText = require("src.core.gen2.CommonText")

local presses = 0
local realPress, realPlay = Sound.playPress, Sound.play
Sound.playPress = function() presses = presses + 1 return nil end
Sound.play = function() return nil end

local function manifest(path)
  local file = assert(io.open(path, "r"))
  local data = assert(Json.decode(file:read("*a")))
  file:close()
  return data
end

do
  local charmap = manifest("tools/rom_manifest_crystal.json").charmap
  local function decode(bytes)
    local rom = {}
    function rom:byte(_, address) return bytes[address] or 0x50 end
    function rom:word(_, address)
      return (bytes[address] or 0) + (bytes[address + 1] or 0) * 0x100
    end
    local extractor = setmetatable({ rom = rom, edition = "crystal" }, Extractor)
    return extractor:decodeGen2Text(0, 0, charmap)
  end
  local H, i = 0x87, 0xa8
  eq(decode({ [0] = 0x00, H, i, 0x57 }), "Hi{DONE}",
    "a `done` text carries {DONE}")
  eq(decode({ [0] = 0x00, H, i, 0x58 }), "Hi{PROMPT}",
    "a `prompt` text carries {PROMPT}")
  eq(decode({ [0] = 0x00, H, i, 0x50, 0x50 }), "Hi",
    "a `text_end` text carries nothing")
  eq(decode({ [0] = 0x57 }), "", "an empty text stays empty")
end

eq(TextBox.ending("Hi{DONE}"), "done", "TextBox reads {DONE}")
eq(TextBox.ending("Hi{PROMPT}"), "prompt", "and {PROMPT}")
eq(TextBox.ending("Hi"), nil, "and nothing for an untagged text")

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

local function finished(text, opts)
  local game = newGame()
  local box = TextBox.new(game, text, nil, opts)
  game.stack:push(box)
  runOut(box)
  presses = 0
  game.input.queue.a = true
  box:update(1 / 60)
  return box, presses
end

-- ../pokecrystal/maps/Route30.asm:302 YoungsterMikeySeenText
do
  local box, beeps = finished("I'm gonna win,\nfor sure!{DONE}")
  eq(box.waitButton, true, "an extracted `done` text is a WaitButton box")
  check(not box:arrowVisible(), "and shows no blinking cursor")
  eq(beeps, 0, "and closes silently")
  eq(box.pages[1][1], "I'm gonna win,", "the marker never reaches the glyphs")
  eq(box.pages[1][2], "for sure!", "on either line")
end

do
  local box, beeps = finished("I'm gonna win,\nfor sure!{PROMPT}")
  eq(box.waitButton, false, "an extracted `prompt` text is a PromptButton box")
  check(box:arrowVisible(), "and shows the cursor")
  eq(beeps, 1, "and beeps on the press")
  eq(box.pages[1][2], "for sure!", "with the marker stripped")
end

do
  local box = finished("Hi{DONE}", { waitButton = false })
  eq(box.waitButton, false,
    "a `done` text followed by promptbutton keeps the caller's cursor")
  box = finished("Hi{PROMPT}", { waitButton = true })
  eq(box.waitButton, false,
    "but a `prompt` text always blinks, whatever the script does after it")
  box = finished("Hi", { waitButton = true })
  eq(box.waitButton, true, "an untagged text keeps the caller's flag")
  box = finished("Hi")
  eq(box.waitButton, nil, "and with no flag stays the Gen 1 default")
end

-- ../pokecrystal/engine/events/trainer_scripts.asm:19
local function boxFor(text, tail)
  local scripts = {
    generation = 2,
    ["s:t"] = {
      { op = "opentext" },
      { op = "writetext", text = "t:x" },
      { op = tail },
      { op = "closetext" },
      { op = "end" },
    },
  }
  local game = newGame()
  local box
  local vm = Vm.new(scripts, { ["t:x"] = text }, Events.new(), {
    showText = function(body, onDone, stay, hold, sfxWait, arrows)
      box = TextBox.new(game, body, onDone, { waitButton = not arrows })
      game.stack:push(box)
    end,
  })
  check(vm:start("s:t"), "the script starts")
  for _ = 1, 50 do vm:update() end
  check(box, "the box went up")
  runOut(box)
  return box
end

check(not boxFor("Hi{DONE}", "waitbutton"):arrowVisible(),
  "done + waitbutton: no cursor")
check(boxFor("Hi{DONE}", "promptbutton"):arrowVisible(),
  "done + promptbutton: the cursor the script asked for")
check(boxFor("Hi{PROMPT}", "waitbutton"):arrowVisible(),
  "prompt + waitbutton: the cursor the text asked for")
check(not boxFor("Hi", "waitbutton"):arrowVisible(),
  "an untagged script text still follows the lookahead")

Sound.playPress, Sound.play = realPress, realPlay

do
  local data = { text = {
    SubTookDamageText = "The SUBSTITUTE\ntook damage for\v{TARGET}!{PROMPT}",
    HitTimesText = "Hit {NUM} times!{DONE}",
  } }
  eq(romText(data, "SubTookDamageText", "fallback", "GEODUDE"),
    "The SUBSTITUTE\ntook damage for\vGEODUDE!{PROMPT}",
    "RomText does not count the terminator as a slot")
  eq(romText(data, "HitTimesText", "fallback", 3), "Hit 3 times!{DONE}",
    "and leaves it on the string for the box to read")
end

do
  local pages = CommonText.pages("Coins:\n{NUM}{DONE}")
  eq(pages[1][1], "Coins:", "CommonText pages drop the terminator")
  eq(pages[1][2], "{NUM}", "and keep the runtime slots")
  eq(CommonText.plain("Hi{PROMPT}"), "Hi", "CommonText.plain strips it")
  eq(CommonText.plain(nil), nil, "and passes nil through")
end

do
  local game = newGame()
  eq(TextBox.substitute(game, "Hi{DONE}"), "Hi",
    "substitute drops {DONE}")
  eq(TextBox.substitute(game, "Hi{PROMPT}"), "Hi",
    "and {PROMPT}")
end

T.finish("gen2 text terminator bug2045")
