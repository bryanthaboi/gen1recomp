-- pokeyellow engine/menus/save.asm:260
-- pokeyellow engine/pikachu/pikachu_pic_animation.asm:1
-- pokeyellow engine/events/poison.asm:137
-- pokeyellow engine/pikachu/pikachu_status.asm:117
-- pokeyellow engine/battle/end_of_battle.asm:49
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local PikachuFollower = require("src.world.PikachuFollower")
local GenSave = require("src.save_convert.GenSave")

local OFF = GenSave.OFFSETS
eq(OFF.pikachuMood, 0x271D, "wPikachuMood is sav byte 0x271D (d470 - d2f6 = 378)")
eq(OFF.pikachuMood, OFF.pikachuHappiness + 1, "wPikachuMood follows wPikachuHappiness")
eq(OFF.pikachuEmotionModifier, OFF.mainData + 421,
   "wPikachuEmotionModifier is 421 bytes past sMainData (d49b - d2f6)")
check(OFF.pikachuMood >= OFF.checksumStart and OFF.pikachuMood < OFF.checksumEnd
      and OFF.pikachuEmotionModifier < OFF.checksumEnd,
      "mood and modifier sit inside the main checksum window")

GameVersion.set("yellow")

local function starterSave(h, mood)
  return {
    player = { name = "YELLOW", id = 1234 },
    party = { { species = "PIKACHU", hp = 20, ot = "YELLOW", otId = 1234 } },
    pikachuHappiness = h, pikachuMood = mood, flags = {},
  }
end

local cells = {
  { 120, 128, 1 }, { 120, 108, 3 }, { 120, 130, 8 }, { 90, 128, 5 },
  { 255, 255, 20 }, { 40, 30, 14 }, { 180, 200, 2 },
}
for _, c in ipairs(cells) do
  eq(PikachuFollower.moodEmotion(starterSave(c[1], c[2])), c[3],
     string.format("happiness %d mood %d picks emotion %d", c[1], c[2], c[3]))
end

local s = starterSave(120, 0x81)
s.pikachuEmotionModifier = 2
PikachuFollower.onStep(s)
eq(s.pikachuMood, 128, "mood $81 converges to 128 in one step")
eq(s.pikachuEmotionModifier, nil, "reaching 128 clears the emotion modifier")

s = starterSave(120, 0x85)
s.pikachuEmotionModifier = 1
PikachuFollower.onStep(s)
eq(s.pikachuEmotionModifier, 1, "the modifier holds while mood is above 128")

s = starterSave(120, 128)
s.pikachuEmotionModifier = 5
PikachuFollower.onStep(s)
eq(s.pikachuEmotionModifier, nil, "a step at a steady 128 clears the modifier")

s = starterSave(120, 108)
PikachuFollower.moodAfterBattle(s)
eq(s.pikachuMood, 0x82, "a battle win lifts mood 108 to $82")
s = starterSave(120, 200)
PikachuFollower.moodAfterBattle(s)
eq(s.pikachuMood, 200, "a battle win leaves mood 200 alone")
s = starterSave(120, 108)
s.party[1].hp = 0
PikachuFollower.moodAfterBattle(s)
eq(s.pikachuMood, 108, "a fainted starter gets no after-battle mood")

s = starterSave(120, 128)
PikachuFollower.onMoveLearned(s, s.party[1], "THUNDERBOLT")
eq(s.pikachuEmotionModifier, 5, "the starter learning THUNDERBOLT sets modifier 5")
eq(s.pikachuMood, 0x85, "and mood $85")
s = starterSave(120, 128)
PikachuFollower.onMoveLearned(s, s.party[1], "THUNDERSHOCK")
eq(s.pikachuEmotionModifier, nil, "other moves leave the modifier alone")

GameVersion.set("red")
s = starterSave(120, 108)
PikachuFollower.moodAfterBattle(s)
eq(s.pikachuMood, 108, "Red/Blue never touch Pikachu's mood")
GameVersion.set("yellow")

if not loadfile("data/generated/pokemon.lua") then
  print("pikachu_mood_save_2344 codec half skipped (needs data/generated/)")
  GameVersion.set("red")
  T.finish("pikachu_mood_save_2344")
  return
end

local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local stampMapWindow = loadfile("tests/fixture_data/map_window.lua")()
local yellowData = assert(SaveConvert.loadData("yellow"))
local redData = assert(SaveConvert.loadData("red"))
stampMapWindow(yellowData, "REDS_HOUSE_2F")
stampMapWindow(redData, "REDS_HOUSE_2F")

local function newSave()
  return SaveData.newGame({ playerName = "RED", rivalName = "BLUE" })
end

local y = newSave()
y.pikachuHappiness = 120
y.pikachuMood = 0x62
y.pikachuEmotionModifier = 2
local yBytes = GenSave.encode(y, yellowData, nil)
eq(yBytes:byte(OFF.pikachuMood + 1), 0x62, "mood $62 reaches sav byte 0x271D")
eq(yBytes:byte(OFF.pikachuEmotionModifier + 1), 2, "modifier 2 reaches its sav byte")
local yBack = GenSave.decode(yBytes, yellowData)
eq(yBack.pikachuMood, 0x62, "mood survives export -> import on Yellow")
eq(yBack.pikachuEmotionModifier, 2, "the emotion modifier survives the round trip")
eq(yBack.pikachuHappiness, 120, "happiness still round-trips next to it")
eq(PikachuFollower.moodEmotion(yBack), 3,
   "the imported save talks with the low-mood pic (emotion 3), not emotion 1")

local seed = newSave()
seed.pikachuMood, seed.pikachuEmotionModifier = nil, nil
local seedBytes = GenSave.encode(seed, yellowData, nil)
eq(seedBytes:byte(OFF.pikachuMood + 1), 0x80, "a missing mood exports as the $80 seed")
eq(seedBytes:byte(OFF.pikachuEmotionModifier + 1), 0, "a missing modifier exports as 0")
eq(GenSave.decode(seedBytes, yellowData).pikachuEmotionModifier, nil,
   "a zero modifier byte imports as no modifier")

local r = newSave()
r.pikachuMood = 0x62
r.pikachuEmotionModifier = 2
local rBytes = GenSave.encode(r, redData, nil)
eq(rBytes:byte(OFF.pikachuMood + 1), 0, "a Red/Blue export leaves 0x271D alone")
local rBack = GenSave.decode(rBytes, redData)
eq(rBack.pikachuMood, nil, "a Red/Blue import never invents a mood")
eq(rBack.pikachuEmotionModifier, nil, "a Red/Blue import never invents a modifier")

GameVersion.set("red")
T.finish("pikachu_mood_save_2344")
