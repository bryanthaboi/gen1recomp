-- Headless regression: a gift jingle rides its received-item text instead
-- of firing when the box opens (#374).  pokered's GiveItem (home/give.asm)
-- plays nothing; the sound is a trailing text command in the gift text
-- (scripts/ViridianMart.asm sound_get_key_item), and home/text.asm:506
-- TextCommand_SOUND runs only after the last character is placed, then
-- WaitForSoundToFinish, then home/text_script.asm AfterDisplayingTextID's
-- button wait.  ROM-free: fixture items plus a stub audio source.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)

local Commands = require("src.script.Commands")
local Sound = require("src.core.Sound")
local SaveData = require("src.core.SaveData")
local TextBox = require("src.render.TextBox")

-- a key item to gift: the fixture set has none, and keyItem is what picks
-- Get_Key_Item over Get_Item1
Data.items.FIX_PARCEL = {
  id = "FIX_PARCEL", index = 90, name = "FIX PARCEL", price = 0,
  keyItem = true,
}

-- one stub source per sfx file, with a playing flag the case drives: Sound.
-- play has to hand the source back for the box to block on it.  The A-press
-- beep goes through the same path, so plays records which sound it was.
local plays = {}
local sources = {}
local function newSource(file)
  local src = sources[file]
  if src then return src end
  src = {
    playing = false,
    setVolume = function() end,
    setPitch = function() end,
    stop = function() end,
    isPlaying = function(self) return self.playing end,
    play = function(self)
      plays[#plays + 1] = file
      self.playing = true
    end,
  }
  sources[file] = src
  return src
end
love.audio = { newSource = newSource }

local function jingles()
  local n = 0
  for _, file in ipairs(plays) do
    if file ~= "ab.wav" then n = n + 1 end
  end
  return n
end
Data.audio = {
  sfx = { Get_Key_Item = "key.wav", Get_Item1 = "item.wav", Press_AB = "ab.wav" },
  fanfares = {},
}

local stack = { states = {} }
function stack:push(s) self.states[#self.states + 1] = s end
function stack:pop()
  local t = self.states[#self.states]
  self.states[#self.states] = nil
  return t
end
function stack:top() return self.states[#self.states] end

local pressed = {}
local game = {
  data = Data,
  save = SaveData.newGame(),
  stack = stack,
  input = {
    wasPressed = function(_, key) return pressed[key] or false end,
    isDown = function() return false end,
  },
}
game.save.options = game.save.options or {}
game.save.options.textSpeed = 1

local resumed = 0
local ctx = {
  game = game,
  save = game.save,
  runner = { yield = function() end, resume = function() resumed = resumed + 1 end },
}

local function step(btn)
  pressed = btn and { [btn] = true } or {}
  local top = stack:top()
  if top then top:update(1 / 60) end
  pressed = {}
end

-- ---------------------------------------------------------------- gift text
-- the Viridian Mart shape: the gift text is the whole quest, three pages,
-- and only the last one is "<PLAYER> got / <item>!"
-- uppercase: the fixture font has no lowercase glyphs
local QUEST = "YOU KNOW PROF\nOAK RIGHT\fHE ASKED ME TO\nDELIVER THIS\f"
  .. "{PLAYER} GOT\n{RAM:wStringBuffer}!"

Commands.give_item(ctx, "FIX_PARCEL", 1, QUEST)
T.eq(game.save.inventory.FIX_PARCEL, 1, "the parcel reached the bag")
local box = stack:top()
T.check(getmetatable(box) == TextBox, "the received-item box is up")
T.eq(#box.pages, 3, "the gift text is three pages")
T.eq(jingles(), 0, "no jingle when the box opens")

-- type the whole text out, answering the page breaks; the jingle must stay
-- silent for every frame of it
local pagesSeen = 1
for _ = 1, 2000 do
  if box.done then break end
  step(box.waiting and "a" or nil)
  if box.pageIndex > pagesSeen then
    pagesSeen = box.pageIndex
    T.eq(jingles(), 0, "still silent on page " .. pagesSeen)
  end
end
T.check(box.done, "the last page finished typing")
T.eq(jingles(), 0, "silent until the last character is placed")

step()
T.eq(jingles(), 1, "the jingle fires once the text is out")
T.eq(plays[#plays], "key.wav", "and it is the key-item jingle")
T.eq(box.autoSrc, sources["key.wav"],
  "the box holds the source Sound.play returned")

-- WaitForSoundToFinish: A is dead while the fanfare sounds
step("a")
T.eq(stack:top(), box, "A does not close the box during the jingle")
T.eq(resumed, 0, "the script has not resumed yet")
T.eq(jingles(), 1, "and the jingle is not retriggered")

sources["key.wav"].playing = false
step()
T.check(box.auto == nil, "the sound gate drops when the fanfare ends")
T.eq(stack:top(), box, "the box stays up for the button wait")

step("a")
T.eq(stack:top(), nil, "A closes the box after the jingle")
T.eq(resumed, 1, "the script resumed once")

-- ------------------------------------------------------------- plain gift
-- gotText == false is the script-shows-its-own-text form (Oak's 5 POKE
-- BALLs): nothing to hang the sound on, so it plays on the spot
plays = {}
Commands.give_item(ctx, "FIX_POTION", 1, false)
T.eq(jingles(), 1, "the no-text gift still plays its jingle immediately")
T.eq(plays[1], "item.wav", "with the plain-item sound")
T.eq(stack:top(), nil, "and pushes no box of its own")

-- ------------------------------------------------------------ script data
-- both Viridian Mart paths must hand give_item the quest text, since that
-- is what routes the jingle through the box
local story = require("data.scripts.story")
local mart = story.VIRIDIAN_MART
local rows = mart.talk.TEXT_VIRIDIANMART_CLERK
local gift
for _, row in ipairs(rows) do
  if row[1] == "give_item" and row[2] == "OAKS_PARCEL" then gift = row end
end
T.check(gift ~= nil, "the clerk talk path gifts OAKS_PARCEL")
T.eq(gift and gift[4], "_ViridianMartClerkParcelQuestText",
  "and passes the quest text, not the default got-item line")

T.finish("give_item_jingle")
