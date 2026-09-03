-- Nurse Joy bows between the two closing lines (#995).
-- pokered engine/events/pokecenter.asm.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()

-- the ROM-extracted strings the fixture text table does not carry
Data.text._PokemonFightingFitText = "Thank you for\nwaiting.\fYour POKéMON are\nfighting fit!"
Data.text._PokemonCenterFarewellText = "We hope to see\nyou again!"

local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local pushed = {}
local stackStub = { push = function(_, item) pushed[#pushed + 1] = item end }
local textBoxStub = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts }
  end,
}
local fakeGame = { data = Data, stack = stackStub }
T.check(setUpvalue(OW.finishNurseHeal, "TextBox", textBoxStub),
  "TextBox upvalue on finishNurseHeal")
T.check(setUpvalue(OW.finishNurseHeal, "Game", fakeGame),
  "Game upvalue on finishNurseHeal")

local FIT = Data.text._PokemonFightingFitText
local BYE = Data.text._PokemonCenterFarewellText

local player = { cellX = 3, cellY = 5 }
local faced
local function newNurse()
  faced = 0
  return {
    facing = "down",
    facePlayer = function(self) faced = faced + 1; self.facing = "down" end,
  }
end

local fakeSelf
local function reset()
  pushed = {}
  fakeSelf = setmetatable({ player = player }, { __index = OW })
end

-- === with the nurse on the counter: fit line, bow, farewell
reset()
local nurse = newNurse()
local finished = 0
fakeSelf:finishNurseHeal(BYE, function() finished = finished + 1 end, nurse)
T.eq(#pushed, 1, "the fighting-fit line goes up on its own")
T.eq(pushed[1].text, FIT, "first box is exactly the fighting-fit text")
T.check(pushed[1].text:find(BYE, 1, true) == nil,
  "the farewell is no longer merged into it with a page break (#995)")

pushed[1].onDone()
T.eq(#pushed, 1, "the farewell waits for the bow")
T.eq(nurse.frameOverride, 1, "image index $14: the nurse bows")
T.check(fakeSelf.emote ~= nil, "the bow is a world hold, not a text pause")
local hold = fakeSelf.emote or {}
T.eq(hold.npc, nurse, "the hold is anchored on the nurse")
T.eq(hold.frames, 20, "DelayFrames $14 is 20 frames")
T.eq(hold.bubble, false, "no emotion bubble is drawn over her")
T.check(not hold.skippable, "the bow cannot be skipped with A/B")
T.eq(finished, 0, "the pokecenter is still busy during the bow")

-- OverworldState:update counts emote.frames down and then calls onDone
if hold.onDone then hold.onDone() end
T.eq(#pushed, 2, "the farewell follows the bow")
local farewell = pushed[2] or {}
T.eq(farewell.text, BYE, "second box is the farewell text")
T.eq(nurse.frameOverride, nil, "the bow ends before the farewell prints")
T.eq(nurse.facing, "down", "the nurse faces the player for the farewell")

if farewell.onDone then farewell.onDone() end
T.eq(nurse.facing, "down", "the trailing UpdateSprites keeps her facing")
T.eq(faced, 2, "she is turned back before and after the farewell")
T.eq(finished, 1, "control returns to the player once, after the farewell")

-- === no nurse sprite (the Yellow/rest-stop callers): no bow, same text
reset()
finished = 0
fakeSelf:finishNurseHeal(BYE, function() finished = finished + 1 end)
T.eq(pushed[1].text, FIT, "npc-less caller still opens with the fit line")
pushed[1].onDone()
T.check(fakeSelf.emote == nil, "nothing to bow, so no world hold")
T.eq(#pushed, 2, "the farewell follows immediately")
farewell = pushed[2] or {}
T.eq(farewell.text, BYE, "npc-less caller still closes with the farewell")
if farewell.onDone then farewell.onDone() end
T.eq(finished, 1, "npc-less caller returns control once")

-- === Yellow: pokeyellow engine/events/pokecenter.asm:75-88 (#2123)
local yellowStub = { isYellow = function() return true end }
T.check(setUpvalue(OW.finishNurseHeal, "GameVersion", yellowStub),
  "GameVersion upvalue on finishNurseHeal")
fakeGame.save = { party = { { species = "PIKACHU", hp = 12 } } }
reset()
nurse = newNurse()
nurse.sprite = { frames = { [0] = true, true, true, true } }
finished = 0
fakeSelf:finishNurseHeal(BYE, function() finished = finished + 1 end, nurse)
pushed[1].onDone()
hold = fakeSelf.emote or {}
T.eq(hold.frames, 9, "Pikachu faces down (6) plus Delay3 before the bow")
T.eq(nurse.frameOverride, nil, "no bow yet during that hold")
if hold.onDone then hold.onDone() end
hold = fakeSelf.emote or {}
T.eq(nurse.frameOverride, 3, "image index 1: the 4th sheet frame is the bow")
T.eq(hold.frames, 40, "DelayFrames 40")
T.eq(#pushed, 1, "the farewell waits for the bow")
if hold.onDone then hold.onDone() end
T.eq(#pushed, 2, "the farewell follows the bow")
T.eq(nurse.frameOverride, nil, "the bow ends before the farewell prints")

fakeGame.save = { party = {} }
reset()
nurse = newNurse()
fakeSelf:finishNurseHeal(BYE, function() end, nurse)
pushed[1].onDone()
hold = fakeSelf.emote or {}
T.eq(hold.frames, 3, "no PIKACHU in the party: Delay3 only")

T.finish("nurse_bow_bug995")
