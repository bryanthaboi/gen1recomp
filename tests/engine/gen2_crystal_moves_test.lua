package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")
local eq, check = T.eq, T.check
local pokemon = {
  growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1,
    squared = 0, linear = 0, constant = 0 } },
  TEST = { id = "TEST", index = 1, name = "TEST", baseStats = {
    hp = 100, attack = 100, defense = 100, speed = 100,
    specialAttack = 100, specialDefense = 100 }, types = { "NORMAL", "NORMAL" },
    catchRate = 45, baseExp = 100, growthRate = "GROWTH_MEDIUM_FAST",
    genderRatio = 127, levelMoves = {}, evolutions = {} },
}
local moves = {}
local effects = { HAZE = "RESET_STATS", HEAL_BELL = "HEAL_BELL",
  PAIN_SPLIT = "PAIN_SPLIT", SWAGGER = "SWAGGER", MIMIC = "MIMIC",
  CONVERSION = "CONVERSION", CONVERSION2 = "CONVERSION2",
  DESTINY_BOND = "DESTINY_BOND", RAPID_SPIN = "RAPID_SPIN",
  HIDDEN_POWER = "HIDDEN_POWER", FLAIL = "REVERSAL", PRESENT = "PRESENT",
  TACKLE = "NORMAL_HIT", EMBER = "BURN_HIT", TRIPLE_KICK = "TRIPLE_KICK" }
for id, effect in pairs(effects) do
  moves[id] = { id = id, name = id, effect = "EFFECT_" .. effect,
    power = 0, accuracy = 100, accuracyRaw = 255, pp = 20, type = "NORMAL" }
end
for _, id in ipairs({ "RAPID_SPIN", "HIDDEN_POWER", "FLAIL", "PRESENT",
    "TACKLE", "EMBER", "TRIPLE_KICK" }) do moves[id].power = 1 end
moves.EMBER.type = "FIRE"
local text = require("tests.fixture_data.gen2_rom_text_s7_a").text(
  require("tests.fixture_data.gen2_rom_text_s7_b").text(nil, "crystal"), "crystal")
for _, label in ipairs({ "EliminatedStatsText", "BellChimedText", "SharedPainText",
    "DestinyBondEffectText", "MimicLearnedMoveText", "TransformedTypeText",
    "ShedLeechSeedText", "BlewSpikesText", "ReleasedByText", "RageBuildingText",
    "TookDownWithItText", "AttackMissedText", "AttackMissed2Text", "DoesntAffectText", "ButItFailedText", "ItFailedText", "DidntAffect1Text", "DidntAffect2Text", "PresentFailedText", "RegainedHealthText" }) do text[label] = label end
local data = { pokemon = pokemon, moves = moves, items = {}, text = text,
  type_chart = { types = { NORMAL = { index = 0, name = "NORMAL", category = "physical" },
    FIRE = { index = 20, name = "FIRE", category = "special" },
    DARK = { index = 27, name = "DARK", category = "special" } },
    matchups = { { attacker = "FIRE", defender = "FIRE", multiplier = 5 } },
    battleRules = { presentPower = { { 102, 40 }, { 179, 80 }, { 204, 120 } },
      flailPower = { { 1, 200 }, { 4, 150 }, { 9, 100 }, { 16, 80 }, { 32, 40 }, { 48, 20 } } } } }
local function fixture(id)
  local a = Mon.new(data, "TEST", 50, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
  local b = Mon.new(data, "TEST", 50, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
  a.moves = { { id = id, pp = 20, maxPp = 20 } }
  b.moves = { { id = "TACKLE", pp = 20, maxPp = 20 } }
  local rules = require("tests.gen2_battle_rules_fixture")()
  for key, value in pairs(rules) do
    if data.type_chart.battleRules[key] == nil then data.type_chart.battleRules[key] = value end
  end
  local battle = Battle.new({ data = data, party = { a }, wild = b, random = function() return 0 end })
  battle.accuracyRoll = function() return true end
  battle.hitOnce = function(self, user, target, def, opts)
    self.lastHit = { type = def.type, power = opts.power, multiplier = opts.damageMultiplier }
    return self:dealDamage(user, target, 1, { move = def }), { effectiveness = 10 }
  end
  return battle, a, b
end
local battle, a, b = fixture("HAZE")
battle.stages.player.attack, battle.stages.enemy.evasion = 4, -2
battle:useMove(a, b, "HAZE")
eq(battle.stages.player.attack, 0, "Haze clears user stages")
eq(battle.stages.enemy.evasion, 0, "Haze clears opposing stages")
battle, a, b = fixture("HEAL_BELL")
local bench = { hp = 20, status = "poison", statusTurns = 2 }
battle.party[2], a.status = bench, "burn"
battle:volatile(a).nightmare = true
battle:useMove(a, b, "HEAL_BELL")
eq(a.status, nil, "Heal Bell active status")
eq(bench.status, nil, "Heal Bell bench status")
eq(battle:volatile(a).nightmare, nil, "Heal Bell nightmare")
battle, a, b = fixture("PAIN_SPLIT")
a.hp, b.hp = 31, 80
battle:useMove(a, b, "PAIN_SPLIT")
eq(a.hp, 55, "Pain Split rounds down")
eq(b.hp, 55, "Pain Split opponent shares HP")
battle, a, b = fixture("SWAGGER")
battle:useMove(a, b, "SWAGGER")
eq(battle.stages.enemy.attack, 2, "Swagger raises target attack")
check(battle:volatile(b).confuseCount ~= nil, "Swagger confuses target")
battle, a, b = fixture("MIMIC")
battle:volatile(b).lastMove = "TACKLE"
battle:useMove(a, b, "MIMIC")
eq(a.moves[1].id, "TACKLE", "Mimic copies target last move")
eq(a.moves[1].pp, 5, "Mimic has five PP")
battle:clearVolatile(a)
eq(a.moves[1].id, "MIMIC", "Mimic restores on switch")
battle, a, b = fixture("CONVERSION")
a.moves[2] = { id = "EMBER", pp = 20 }
battle:useMove(a, b, "CONVERSION")
eq(battle:battlerTypes(a)[1], "FIRE", "Conversion changes active type")
battle:clearVolatile(a)
eq(battle:battlerTypes(a)[1], "NORMAL", "Conversion resets on switch")
battle, a, b = fixture("DESTINY_BOND")
battle:useMove(a, b, "DESTINY_BOND")
battle:dealDamage(b, a, a.hp, { move = moves.TACKLE })
eq(b.hp, 0, "Destiny Bond takes down attack user")
battle, a, b = fixture("RAPID_SPIN")
battle.spikes.player = true
local state = battle:volatile(a)
state.leechSeed, state.wrapCount, state.wrapMoveId = true, 3, "TACKLE"
battle:useMove(a, b, "RAPID_SPIN")
eq(battle.spikes.player, false, "Rapid Spin clears spikes")
eq(state.leechSeed, nil, "Rapid Spin clears leech seed")
eq(state.wrapCount, nil, "Rapid Spin clears binding")
battle, a, b = fixture("HIDDEN_POWER")
battle:useMove(a, b, "HIDDEN_POWER")
eq(battle.lastHit.power, 70, "Hidden Power derives power from DVs")
eq(battle.lastHit.type, "DARK", "Hidden Power derives type from DVs")
battle, a, b = fixture("FLAIL")
a.hp = 1
battle:useMove(a, b, "FLAIL")
eq(battle.lastHit.power, 200, "Flail selects lowest HP band")
battle, a, b = fixture("PRESENT")
battle:useMove(a, b, "PRESENT")
eq(battle.lastHit.power, 40, "Present selects 40 power first interval")
battle, a, b = fixture("PRESENT")
b.hp = 1
battle.random = function() return 255 end
battle:useMove(a, b, "PRESENT")
eq(b.hp, 1 + math.floor(b.maxHp / 4), "Present heal branch restores quarter HP")
battle, a, b = fixture("PRESENT")
b.hp = 1
battle.random = function() return 255 end
battle.accuracyRoll = function() return false end
battle:useMove(a, b, "PRESENT")
eq(b.hp, 1, "Present heal branch still checks accuracy")
battle, a, b = fixture("TRIPLE_KICK")
battle:useMove(a, b, "TRIPLE_KICK")
eq(battle.lastHit.multiplier, 1, "Triple Kick zero sample selects one hit")
battle, a, b = fixture("TRIPLE_KICK")
battle.random = function(n) return n == 3 and 2 or 0 end
local kicks = {}
local recordHit = battle.hitOnce
battle.hitOnce = function(self, ...)
  local dealt, info = recordHit(self, ...)
  kicks[#kicks + 1] = self.lastHit.multiplier
  return dealt, info
end
battle:useMove(a, b, "TRIPLE_KICK")
eq(table.concat(kicks, ","), "1,2,3", "Triple Kick climbs x1, x2, x3 across its kicks")
T.finish("Crystal move effects")
