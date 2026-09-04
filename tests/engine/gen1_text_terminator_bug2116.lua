-- home/text.asm:209 PromptText, :221 DoneText; constants/charmap.asm:12

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Json = require("src.link.Json")
local Extractor = require("src.import.RomExtractor")
local TextBox = require("src.render.TextBox")
local Sound = require("src.core.Sound")
local romText = require("src.core.RomText")

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

local charmap = manifest("tools/rom_manifest.json").charmap
eq(charmap["74"], "<PK><MN>",
  "the manifest maps $4A to the two-tile ligature, not POKeMON")
eq(manifest("tools/rom_manifest_blue.json").charmap["74"], "<PK><MN>",
  "Blue's manifest too")
eq(manifest("tools/rom_manifest_yellow.json").charmap["74"], "<PK><MN>",
  "and Yellow's")

local function decode(bytes)
  local rom = {}
  function rom:byte(_, address) return bytes[address] or 0x50 end
  local extractor = setmetatable({ rom = rom, manifest = { charmap = charmap } },
    Extractor)
  return extractor:decodeTextCommands(
    { bank = 0, address = 0, name = "_Test" }, {})
end

local H, i = 0x87, 0xa8
eq(decode({ [0] = 0x00, H, i, 0x57 }), "Hi{DONE}", "a `done` text carries {DONE}")
eq(decode({ [0] = 0x00, H, i, 0x58 }), "Hi{PROMPT}",
  "a `prompt` text carries {PROMPT}")
-- data/text/text_3.asm:32
eq(decode({ [0] = 0x00, H, i, 0x50, 0x50 }), "Hi{DONE}",
  "a text_end text is a done too")
eq(decode({ [0] = 0x00, H, i, 0x5F }), "Hi",
  "<DEXEND> stays unmarked for DexEntryMenu")
eq(decode({ [0] = 0x50 }), "", "an empty text stays empty")
eq(decode({ [0] = 0x00, 0x4A, 0x57 }), "<PK><MN>{DONE}",
  "$4A decodes to the ligature, whole, not a {PK><MN} token")
eq(decode({ [0] = 0x00, 0x52, 0x57 }), "{PLAYER}{DONE}",
  "a lone <NAME> entry is still a token")

eq(TextBox.ending("Hi{DONE}"), "done", "TextBox reads {DONE}")
eq(TextBox.ending("Hi{PROMPT}"), "prompt", "and {PROMPT}")
eq(TextBox.ending("Hi"), nil, "and nothing for an untagged text")

local function newGame()
  local game = {
    save = { player = {}, options = { textSpeed = "FAST" }, generation = 1 },
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

local function finished(text, opts)
  local game = newGame()
  local box = TextBox.new(game, text, nil, opts)
  game.stack:push(box)
  local frames = 0
  while not box.done and frames < 600 do
    box:update(1 / 60)
    frames = frames + 1
  end
  presses = 0
  game.input.queue.a = true
  box:update(1 / 60)
  return box, presses
end

-- text/Route25.asm:153
do
  local box, beeps = finished("SEA COTTAGE\nBILL lives here!{DONE}")
  eq(box.waitButton, true, "an extracted `done` text is a WaitButton box")
  -- home/text_script.asm:96 -> home/joypad2.asm:71-72
  check(box:arrowVisible(), "and still blinks the arrow WaitForTextScrollButtonPress draws")
  eq(select(2, box:arrowPos()), 128, "at hlcoord 18,16")
  -- SFX_PRESS_AB lives only in ManualTextScroll, home/joypad2.asm:90-92
  eq(beeps, 0, "and closes silently")
  eq(box.pages[1][1], "SEA COTTAGE", "the marker never reaches the glyphs")
  eq(box.pages[1][2], "BILL lives here!", "on either line")
end

do
  local box, beeps = finished("SEA COTTAGE\nBILL lives here!{PROMPT}")
  eq(box.waitButton, false, "an extracted `prompt` text blinks")
  check(box:arrowVisible(), "and shows the cursor")
  eq(beeps, 1, "and beeps on the press")
  eq(box.pages[1][2], "BILL lives here!", "with the marker stripped")
end

do
  local box = finished("Hi")
  check(box:arrowVisible(), "an untagged text keeps the blinking default")
end

Sound.playPress, Sound.play = realPress, realPlay

do
  local pages = TextBox.paginate("Choose a\n<PK><MN> BOX.{DONE}", 18)
  eq(pages[1][1], "Choose a", "paginate drops the terminator")
  eq(pages[1][2], "<PK><MN> BOX.", "and keeps the ligature")
  eq(TextBox.paginate("Take your time.{PROMPT}", 18)[1][1], "Take your time.",
    "for {PROMPT} as well")
end

do
  local data = { text = { _PotionText = "{RAM:wcf4b} recovered\nby {NUM}!{DONE}" } }
  eq(romText(data, "_PotionText", "fallback", "POLIWHIRL", 4),
    "POLIWHIRL recovered\nby 4!{DONE}",
    "RomText does not count the terminator as a slot")
end

T.finish("gen1 text terminator bug2116")
