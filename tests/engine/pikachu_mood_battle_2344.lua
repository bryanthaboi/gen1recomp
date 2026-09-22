-- pokeyellow engine/battle/end_of_battle.asm:49
-- pokeyellow engine/pikachu/pikachu_status.asm:1
-- pokeyellow engine/items/item_effects.asm:564
-- pokeyellow engine/items/item_effects.asm:810
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)

local GameVersion = require("src.core.GameVersion")
local BattleState = require("src.battle.BattleState")
local ItemEffects = require("src.inventory.ItemEffects")
local PikachuFollower = require("src.world.PikachuFollower")
local SaveData = require("src.core.SaveData")

local Pokemon = require("src.pokemon.Pokemon")
if not Data.pokemon.PIKACHU then
  local def = {}
  for k, v in pairs(Data.pokemon.FIXMON_A) do def[k] = v end
  def.name = "PIKACHU"
  def.evolutions = { { method = "ITEM", item = "THUNDER_STONE", species = "FIXMON_B" } }
  Data.pokemon.PIKACHU = def
end

GameVersion.set("yellow")

local function starterSave(mood, opts)
  opts = opts or {}
  local save = SaveData.newGame()
  save.player.name, save.player.id = "YELLOW", 1234
  local pika = Pokemon.new(Data, "PIKACHU", 12)
  pika.ot, pika.otId = opts.ot or "YELLOW", opts.otId or 1234
  save.party = { pika }
  save.pikachuHappiness = 120
  save.pikachuMood = mood
  save.pikachuEmotionModifier = nil
  return save
end

local function finishWith(result, opts)
  opts = opts or {}
  local save = starterSave(0x6c)
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end,
                           push = function() end, pop = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 8)
  battle.evolutionsChecked = true
  battle.result = result
  battle.playerRan = opts.playerRan
  battle.demo = opts.demo
  pcall(battle.finish, battle)
  return save
end

T.eq(finishWith("win").pikachuMood, 0x82, "a win lifts the starter's mood to $82")
T.eq(finishWith("run", { playerRan = true }).pikachuMood, 0x6c,
  "the player running away leaves the mood alone (wBattleResult 2)")
T.eq(finishWith("run").pikachuMood, 0x82,
  "the enemy fleeing (wBattleResult 0) still lifts the mood")
T.eq(finishWith("caught").pikachuMood, 0x6c,
  "a catch skips the after-battle lift (wBattleResult 2)")
T.eq(finishWith("lose").pikachuMood, 0x6c, "a loss skips the after-battle lift")
T.eq(finishWith("win", { demo = true }).pikachuMood, 0x6c,
  "the demo battle never touches the mood")

do
  local s = starterSave(0x6c, { ot = "ASH", otId = 999 })
  PikachuFollower.moodAfterBattle(s)
  T.eq(s.pikachuMood, 0x6c, "a traded-in Pikachu does not count as the starter")
end
do
  local s = starterSave(0x6c)
  table.insert(s.party, 1, { species = "PIKACHU", hp = 20, ot = "ASH", otId = 999 })
  PikachuFollower.moodAfterBattle(s)
  T.eq(s.pikachuMood, 0x82, "the OT-matched starter behind a traded Pikachu counts")
end

do
  local save = starterSave(0x6c)
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 8)
  battle:storeCaughtMon()
  T.eq(save.pikachuEmotionModifier, 1, "a catch sets emotion modifier 1")
  T.eq(save.pikachuMood, 0x85, "a catch sets mood $85")
end

for _, stone in ipairs({ "FIRE_STONE", "MOON_STONE", "THUNDER_STONE" }) do
  local save = starterSave(0x6c)
  local result = ItemEffects.use(Data, save, stone, save.party[1])
  T.eq(result, "failed", stone .. " on the starter is not consumed")
  if stone == "THUNDER_STONE" then
    T.eq(save.pikachuEmotionModifier, 4, "THUNDER_STONE refusal sets modifier 4")
    T.eq(save.pikachuMood, 0x82, "THUNDER_STONE refusal sets mood $82")
  else
    T.eq(save.pikachuEmotionModifier, nil, stone .. " leaves the modifier alone")
    T.eq(save.pikachuMood, 0x6c, stone .. " leaves the mood alone")
  end
end

GameVersion.set("red")
do
  local save = starterSave(0x6c)
  ItemEffects.use(Data, save, "THUNDER_STONE", save.party[1])
  T.eq(save.pikachuMood, 0x6c, "Red/Blue stones never touch the mood")
end

T.finish("pikachu_mood_battle_2344")
