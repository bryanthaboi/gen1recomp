-- A gym leader's badge line prints from TrainerBattleVictory (#1606):
-- scripts/CeruleanGym.asm:111, PewterGym.asm:117, home/trainers.asm:341
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local gyms = require("data.scripts.gyms")
local victories = require("data.scripts.victories")
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

-- one page of text per label, so a joined chain is readable in a failure
local text = {}
for _, key in ipairs({ "OPP_BROCK#1", "OPP_MISTY#1", "OPP_LT_SURGE#1",
                       "OPP_ERIKA#1", "OPP_KOGA#1", "OPP_SABRINA#1",
                       "OPP_BLAINE#1", "OPP_GIOVANNI#3" }) do
  for _, label in ipairs(victories[key].dialogue or {}) do
    text[label] = "text:" .. label
  end
  for _, label in ipairs(victories[key].tmPre or {}) do
    text[label] = "text:" .. label
  end
  for _, label in ipairs(victories[key].tmDialogue or {}) do
    text[label] = "text:" .. label
  end
end

local fakeGame = { data = { text = text }, save = { flags = {} } }

local armed, armedSound
local fakeOw = {
  engageTrainer = function(_, _, _, endBattleText, _, endBattleSound)
    armed, armedSound = endBattleText, endBattleSound
  end,
}

local function armedFor(mapId, textId, victoryKey)
  armed, armedSound = nil, nil
  gyms[mapId].talk[textId](fakeGame, fakeOw, { id = "npc#1" }, function() end)
  local labels = victories[victoryKey].dialogue
  local want = {}
  for i, label in ipairs(labels) do want[i] = text[label] end
  return armed, table.concat(want, "\f")
end

-- every leader, in badge order
local leaders = {
  { "PEWTER_GYM", "TEXT_PEWTERGYM_BROCK", "OPP_BROCK#1" },
  { "CERULEAN_GYM", "TEXT_CERULEANGYM_MISTY", "OPP_MISTY#1" },
  { "VERMILION_GYM", "TEXT_VERMILIONGYM_LT_SURGE", "OPP_LT_SURGE#1" },
  { "CELADON_GYM", "TEXT_CELADONGYM_ERIKA", "OPP_ERIKA#1" },
  { "FUCHSIA_GYM", "TEXT_FUCHSIAGYM_KOGA", "OPP_KOGA#1" },
  { "SAFFRON_GYM", "TEXT_SAFFRONGYM_SABRINA", "OPP_SABRINA#1" },
  { "CINNABAR_GYM", "TEXT_CINNABARGYM_BLAINE", "OPP_BLAINE#1" },
  { "VIRIDIAN_GYM", "TEXT_VIRIDIANGYM_GIOVANNI", "OPP_GIOVANNI#3" },
}
for _, entry in ipairs(leaders) do
  local got, want = armedFor(entry[1], entry[2], entry[3])
  T.eq(got, want, entry[3] .. " arms its badge line for the battle screen")
  -- the dialogue's sound command rides the armed line onto the battle
  -- screen too (sound_get_item_1 / sound_get_key_item) (#1606)
  T.eq(armedSound, victories[entry[3]].badgeSound,
    entry[3] .. " arms its badge jingle beside the line")
end

-- Brock's armed label is one text chain of two text_far pages
-- (PewterGymBrockReceivedBoulderBadgeText), so both ride the battle screen
local brock = select(1, armedFor("PEWTER_GYM", "TEXT_PEWTERGYM_BROCK",
                                 "OPP_BROCK#1"))
T.check(brock:find("\f", 1, true) ~= nil,
  "Brock's badge line keeps its BoulderBadgeInfo page")

-- the beaten branch still talks instead of re-engaging
armed = nil
fakeGame.save.flags.EVENT_BEAT_MISTY = true
fakeGame.save.flags.EVENT_GOT_TM11 = true
local realStack = { push = function() end }
gyms.CERULEAN_GYM.talk.TEXT_CERULEANGYM_MISTY(
  { data = { text = text }, save = fakeGame.save, stack = realStack },
  fakeOw, { id = "npc#1" }, function() end)
T.eq(armed, nil, "a beaten leader does not re-arm the badge line")
fakeGame.save.flags.EVENT_BEAT_MISTY = nil
fakeGame.save.flags.EVENT_GOT_TM11 = nil

-- checkVictoryRewards must not reprint what the battle screen showed
local boxes
local textBoxStub = {
  new = function(_, str, onDone)
    boxes[#boxes + 1] = str
    return { onDone = onDone }
  end,
  soundOpts = function() return nil end,
}
local pushed
local rewardGame = {
  data = { text = text, items = { TM_BUBBLEBEAM = { name = "TM11" } } },
  save = { flags = {}, inventory = {}, player = { name = "RED" } },
  stack = { push = function(_, box) pushed[#pushed + 1] = box end },
}
T.check(setUpvalue(OW.checkVictoryRewards, "Game", rewardGame),
  "Game upvalue on checkVictoryRewards")
-- TextBox is only named inside the rewardChain closure; the chunk-level
-- upvalue cell is shared, so any closure that names it will do
T.check(setUpvalue(OW.engageTrainer, "TextBox", textBoxStub),
  "TextBox upvalue on the reward chain")

local fakeSelf = setmetatable({
  map = { id = "CERULEAN_GYM", def = { label = "CeruleanGym" } },
  runVictoryHook = function() end,
}, { __index = OW })

local function rewardPages(shownOnBattleScreen)
  boxes, pushed = {}, {}
  rewardGame.save.flags = {}
  rewardGame.save.inventory = {}
  fakeSelf:checkVictoryRewards("OPP_MISTY", 1, shownOnBattleScreen)
  -- the chain pushes one box at a time; walk it to the end
  local i = 1
  while pushed[i] do
    local box = pushed[i]
    i = i + 1
    if box.onDone then box.onDone() end
  end
  return table.concat(boxes, "\f")
end

local badge = text["_CeruleanGymMistyReceivedCascadeBadgeText"]
local onMap = rewardPages(false)
T.check(onMap:find(badge, 1, true) ~= nil,
  "without the battle-screen line the reward chain still shows the badge text")
local afterBattleScreen = rewardPages(true)
T.eq(afterBattleScreen:find(badge, 1, true), nil,
  "the badge line is not reprinted on the map once the battle screen showed it")
T.check(afterBattleScreen:find(text["_CeruleanGymMistyCascadeBadgeInfoText"],
                               1, true) ~= nil,
  "the TM hand-over still runs on the map")
T.check(rewardGame.save.inventory.CASCADEBADGE == 1, "the badge is still given")

T.finish("gym end battle text (#1606)")
