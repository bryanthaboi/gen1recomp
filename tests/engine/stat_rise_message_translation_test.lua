package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local ItemEffects = require("src.inventory.ItemEffects")
local TrainerAI = require("src.battle.TrainerAI")

local function withText(overrides, fn)
  local saved = {}
  for k, v in pairs(overrides) do saved[k] = Data.text[k]; Data.text[k] = v end
  local ok, err = pcall(fn)
  for k in pairs(overrides) do Data.text[k] = saved[k] end
  if not ok then error(err, 0) end
end

-- ------------------------------------------------------- player X-item

local save = SaveData.newGame()
local player = { name = "FIXMON", stages = {} }
local xBattle = { player = player, kind = "wild" }

local _, baseline, baselineExtra = ItemEffects.use(Data, save, "X_ATTACK", nil, xBattle)
local baselineRose = baselineExtra and baselineExtra.afterMessages
  and baselineExtra.afterMessages[1] or baseline[1]
T.check(baselineRose:find("ATTACK", 1, true) ~= nil,
  "X ATTACK's rose! message names the stat in English with no catalog")

withText({ ["StatModTextStrings.1"] = "ATTAQUE" }, function()
  player.stages.attack = nil
  local _, msgs, extra = ItemEffects.use(Data, save, "X_ATTACK", nil, xBattle)
  local rose = extra and extra.afterMessages and extra.afterMessages[1] or msgs[1]
  T.check(rose:find("ATTAQUE", 1, true) ~= nil,
    "a StatModTextStrings override reaches the X ATTACK rose! message")
  T.check(rose:find("ATTACK", 1, true) == nil,
    "...and the untranslated English stat name is gone")
end)

-- --------------------------------------------------------- player vitamin

local target = Pokemon.new(Data, "FIXMON_A", 10)
withText({ ["VitaminStats.3"] = "DEFENSE_FR" }, function()
  local _, msgs = ItemEffects.use(Data, save, "IRON", target)
  T.check(msgs[1]:find("DEFENSE_FR", 1, true) ~= nil,
    "a VitaminStats override reaches the IRON (vitamin) rose! message")
end)

local hpTarget = Pokemon.new(Data, "FIXMON_A", 10)
withText({ ["VitaminStats.1"] = "PV" }, function()
  local _, msgs = ItemEffects.use(Data, save, "HP_UP", hpTarget)
  T.check(msgs[1]:find("PV", 1, true) ~= nil,
    "a VitaminStats override reaches the HP UP rose message")
end)

-- ------------------------------------------------------- AI trainer X-item

local enemy = { name = "FOE", stages = {} }
local aiBattle = { enemy = enemy, trainer = { name = "TRAINER" }, data = Data }

withText({ ["StatModTextStrings.3"] = "VITESSE" }, function()
  local msgs = TrainerAI.useItem(aiBattle, "X_SPEED")
  T.check(type(msgs[2]) == "table" and msgs[2].anim == "XSTATITEM_DUPLICATE_ANIM",
    "the AI trainer's X item plays the stat-up animation before the rose! page")
  T.check(msgs[3]:find("VITESSE", 1, true) ~= nil,
    "a StatModTextStrings override reaches the AI trainer's X SPEED rose! message")
end)

-- ------------------------------------------------------- Gold: Light Screen / Reflect

local Gen2Battle = require("src.battle.gen2.Battle")
local Gen2Mon = require("src.battle.gen2.Mon")

local GEN2_DATA = {
  pokemon = {
    MACHOP = {
      id = "MACHOP", index = 66, name = "MACHOP",
      baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
        specialAttack = 35, specialDefense = 35 },
      types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
      growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
      levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
    },
  },
  moves = {
    TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
      accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  },
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = { NORMAL = { id = "NORMAL", index = 0,
    category = "physical" } }, matchups = {} },
  items = {},
}
local perfectDvs = { attack = 15, defense = 15, speed = 15, special = 15 }
perfectDvs.hp = Gen2Mon.hpDV(perfectDvs)

local function newGen2Battle()
  local player = Gen2Mon.new(GEN2_DATA, "MACHOP", 15, { dvs = perfectDvs })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Gen2Mon.new(GEN2_DATA, "MACHOP", 15, { dvs = perfectDvs })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  return Gen2Battle.new({ data = GEN2_DATA, party = { player }, wild = wild })
end

local function screenLine(effect, label, translated)
  local battle = newGen2Battle()
  battle.data.text = require("tests.gen2_battle_text_fixture")()
  battle.data.text[label] = translated
  Gen2Battle.MOVE_EFFECTS[effect](battle, battle.player)
  for _, event in ipairs(battle:takeEvents()) do
    if event.kind == "message" then return event.text end
  end
end

T.eq(screenLine("EFFECT_LIGHT_SCREEN", "LightScreenEffectText",
    "{USER} voit sa DEF.SPÉ augmenter !{PROMPT}"),
  "MACHOP voit sa DEF.SPÉ augmenter !",
  "a translated LightScreenEffectText reaches Light Screen's rose! message")

T.eq(screenLine("EFFECT_REFLECT", "ReflectEffectText",
    "{USER} voit sa DEFENSE augmenter !{PROMPT}"),
  "MACHOP voit sa DEFENSE augmenter !",
  "a translated ReflectEffectText reaches Reflect's rose! message")

T.finish("stat rise message translation")
