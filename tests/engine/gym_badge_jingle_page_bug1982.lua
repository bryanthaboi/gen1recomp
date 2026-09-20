-- scripts/PewterGym.asm:156-159
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq
local gyms = require("data.scripts.gyms")
local victories = require("data.scripts.victories")

local text = {}
local armed, armedSound, armedSoundPage
local fakeOw = {
  engageTrainer = function(_, _, _, endBattleText, _, endBattleSound, _,
                           endBattleSoundPage)
    armed, armedSound, armedSoundPage =
      endBattleText, endBattleSound, endBattleSoundPage
  end,
}
local fakeGame = { data = { text = text }, save = { flags = {} } }

local function pages(n, tag)
  local out = {}
  for i = 1, n do out[i] = tag .. i end
  return table.concat(out, "\f")
end

local function armFor(mapId, textId, victoryKey, firstLabelPages)
  local reward = victories[victoryKey]
  for i, label in ipairs(reward.dialogue or {}) do
    text[label] = pages(i == 1 and firstLabelPages or 2, label .. "#")
  end
  armed, armedSound, armedSoundPage = nil, nil, nil
  gyms[mapId].talk[textId](fakeGame, fakeOw, { id = "npc#1" }, function() end)
  return armed, armedSound, armedSoundPage
end

local leaders = {
  { "PEWTER_GYM", "TEXT_PEWTERGYM_BROCK", "OPP_BROCK#1", 3 },
  { "CERULEAN_GYM", "TEXT_CERULEANGYM_MISTY", "OPP_MISTY#1", 3 },
  { "SAFFRON_GYM", "TEXT_SAFFRONGYM_SABRINA", "OPP_SABRINA#1", 3 },
  { "CINNABAR_GYM", "TEXT_CINNABARGYM_BLAINE", "OPP_BLAINE#1", 2 },
  { "VIRIDIAN_GYM", "TEXT_VIRIDIANGYM_GIOVANNI", "OPP_GIOVANNI#3", 1 },
}
-- The jingle the cartridge really plays (#2339).  A badge line is an
-- end-battle text (SaveEndBattleTextPointers), so it is printed while the
-- battle sound engine is loaded, and that engine's own SFX_Headers_2 gives the
-- line's sound id a different sound than the overworld engine's table does:
-- the id behind sound_get_item_1 / sound_level_up is SFX_Level_Up, and the id
-- behind sound_get_key_item is SFX_Ball_Poof.  Vermilion, Celadon and Fuchsia
-- carry no sound command at all, and Yellow's CeruleanGym.asm drops it from
-- Cerulean's line, which is the only version difference.
local GameVersion = require("src.core.GameVersion")
local wasVersion = GameVersion.get()
local jingle = {
  red = {
    ["OPP_BROCK#1"] = "Level_Up",
    ["OPP_MISTY#1"] = "Ball_Poof",
    ["OPP_LT_SURGE#1"] = nil,
    ["OPP_ERIKA#1"] = nil,
    ["OPP_KOGA#1"] = nil,
    ["OPP_SABRINA#1"] = "Ball_Poof",
    ["OPP_BLAINE#1"] = "Ball_Poof",
    ["OPP_GIOVANNI#3"] = "Level_Up",
  },
  yellow = {
    ["OPP_BROCK#1"] = "Level_Up",
    ["OPP_MISTY#1"] = nil,
    ["OPP_LT_SURGE#1"] = nil,
    ["OPP_ERIKA#1"] = nil,
    ["OPP_KOGA#1"] = nil,
    ["OPP_SABRINA#1"] = "Ball_Poof",
    ["OPP_BLAINE#1"] = "Ball_Poof",
    ["OPP_GIOVANNI#3"] = "Level_Up",
  },
}
for _, version in ipairs({ "red", "blue", "yellow" }) do
  local want = jingle[version == "yellow" and "yellow" or "red"]
  GameVersion.set(version)
  for key, sound in pairs(want) do
    eq(victories.badgeSoundFor(key), sound,
       key .. " badge jingle under " .. version)
  end
  for _, entry in ipairs(leaders) do
    local _, sound, page = armFor(entry[1], entry[2], entry[3], entry[4])
    eq(sound, want[entry[3]],
       entry[3] .. " arms " .. version .. "'s jingle beside its badge line")
    eq(page, want[entry[3]] and entry[4] or nil,
       entry[3] .. " pages " .. version .. "'s jingle like the cartridge")
  end
  local _, surgeSound, surgePage = armFor("VERMILION_GYM",
    "TEXT_VERMILIONGYM_LT_SURGE", "OPP_LT_SURGE#1", 3)
  eq(surgeSound, nil, "LT.SURGE arms no badge jingle under " .. version)
  eq(surgePage, nil, "and no jingle page under " .. version)
end
GameVersion.set(wasVersion)

local ok, real = pcall(dofile, "data/generated/text.lua")
if ok and type(real) == "table"
   and real._PewterGymBrockReceivedBoulderBadgeText then
  local n = 0
  for page in (real._PewterGymBrockReceivedBoulderBadgeText .. "\f")
              :gmatch("(.-)\f") do
    if page ~= "" then n = n + 1 end
  end
  eq(n, 3, "Brock's badge label really is three pages")
end

local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")

local function queueFor(soundPage)
  local save = SaveData.newGame()
  save.player.name = "RED"
  save.party = { Pokemon.new(Data, "FIXMON_A", 60) }
  local game = { data = Data, save = save }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  local battle = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  battle.participants = {}
  battle.playVictoryMusic = function() end
  battle.slidePic = function() end
  battle.endBattleText = "one\ftwo\fthree"
  battle.endBattleSound = "Get_Item1"
  battle.endBattleSoundPage = soundPage
  for _, mon in ipairs(battle.enemyParty) do mon.hp = 0 end
  battle.queue, battle.nextInsert = {}, 0
  battle:enemyMonFainted()
  return battle.queue
end

local function sfxRow(queue)
  for _, row in ipairs(queue) do
    if row.waitForLearningSfx then return row end
  end
end

local row = sfxRow(queueFor(3))
check(row ~= nil, "the badge jingle is queued with a page")
check(row and row.text and row.text:find("three", 1, true) ~= nil,
      "the jingle rides the third page, not the first")

local first = sfxRow(queueFor(nil))
check(first and first.text and first.text:find("one", 1, true) ~= nil,
      "an unpaged end-battle sound still rides the first page")

T.finish("gym badge jingle page (#1982)")
