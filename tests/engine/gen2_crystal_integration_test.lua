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
local effects = { DISABLE = "DISABLE", ENCORE = "ENCORE", LOCK_ON = "LOCK_ON", BEAT_UP = "BEAT_UP", JUMP_KICK = "JUMP_KICK", PSYCHIC = "SP_DEF_DOWN_HIT", FUTURE_SIGHT = "FUTURE_SIGHT", COUNTER = "COUNTER", MIRROR_COAT = "MIRROR_COAT", PURSUIT = "PURSUIT", HAZE = "RESET_STATS", HEAL_BELL = "HEAL_BELL",
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
    "TACKLE", "EMBER", "TRIPLE_KICK", "FUTURE_SIGHT", "PURSUIT", "BEAT_UP", "JUMP_KICK", "PSYCHIC" }) do moves[id].power = 1 end
moves.EMBER.type = "FIRE"
moves.PSYCHIC.type = "PSYCHIC_TYPE"
moves.PSYCHIC.power = 90
moves.PSYCHIC.effectChance, moves.PSYCHIC.effectChanceRaw = 100, 255
moves.JUMP_KICK.type = "FIGHTING"
moves.JUMP_KICK.power = 70
moves.TRIPLE_KICK.power = 10
moves.PURSUIT.power = 40
moves.FUTURE_SIGHT.type = "PSYCHIC_TYPE"
moves.FUTURE_SIGHT.power = 80
moves.COUNTER.type = "FIGHTING"
moves.MIRROR_COAT.type = "PSYCHIC_TYPE"
moves.PURSUIT.type = "DARK"
local text = require("tests.fixture_data.gen2_rom_text_s7_a").text(
  require("tests.fixture_data.gen2_rom_text_s7_b").text(nil, "crystal"), "crystal")
for _, label in ipairs({ "EliminatedStatsText", "BellChimedText", "SharedPainText",
    "DestinyBondEffectText", "MimicLearnedMoveText", "TransformedTypeText",
    "ShedLeechSeedText", "BlewSpikesText", "ReleasedByText", "RageBuildingText",
    "TookDownWithItText", "AttackMissedText", "AttackMissed2Text", "DoesntAffectText", "ButItFailedText", "ItFailedText", "DidntAffect1Text", "DidntAffect2Text", "PresentFailedText", "RegainedHealthText", "CrashedText", "ForesawAttackText", "BattleText_TargetWasHitByFutureSight", "FullyParalyzedText", "FrozenSolidText", "FlinchedText", "DisabledNoMoreText", "RecoveredUsingText", "HurtItselfText" }) do text[label] = label end
local data = { pokemon = pokemon, moves = moves, items = {}, text = text,
  type_chart = { types = { NORMAL = { index = 0, name = "NORMAL", category = "physical" },
    FIRE = { index = 20, name = "FIRE", category = "special" },
    FIGHTING = { index = 1, name = "FIGHTING", category = "physical" },
    GHOST = { index = 8, name = "GHOST", category = "physical" },
    PSYCHIC_TYPE = { index = 24, name = "PSYCHIC", category = "special" },
    DARK = { index = 27, name = "DARK", category = "special" } },
    matchups = { { attacker = "FIGHTING", defender = "GHOST", multiplier = 0 },
      { attacker = "PSYCHIC_TYPE", defender = "DARK", multiplier = 0 } },
    battleRules = { presentPower = { { 102, 40 }, { 179, 80 }, { 204, 120 } },
      flailPower = { { 1, 200 }, { 4, 150 }, { 9, 100 }, { 16, 80 }, { 32, 40 }, { 48, 20 } } } } }
local function fixture(id)
  local a = Mon.new(data, "TEST", 50, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
  local b = Mon.new(data, "TEST", 50, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
  a.moves = { { id = id, pp = 20, maxPp = 20 } }
  b.moves = { { id = "TACKLE", pp = 20, maxPp = 20 } }
  local tables = require("tests.gen2_battle_rules_fixture")()
  for key, value in pairs(tables) do
    if data.type_chart.battleRules[key] == nil then data.type_chart.battleRules[key] = value end
  end
  local battle = Battle.new({ data = data, party = { a }, wild = b, random = function(n) return math.min(127, n - 1) end })
  battle.accuracyRoll = function() return true end
  return battle, a, b
end
local battle, a, b = fixture("PRESENT")
b.hp = 1
battle.random = function(n) return n - 1 end
battle.accuracyRoll = function() return false end
battle:useMove(a, b, "PRESENT")
eq(b.hp, 1, "Present healing outcome can miss")

battle, a, b = fixture("FUTURE_SIGHT")
battle:volatile(b).protect, battle:volatile(b).vanished = true, true
battle:volatile(b).lockOn = true
battle:useMove(a, b, "FUTURE_SIGHT")
check(battle.moveRuleFutureSight and battle.moveRuleFutureSight.player ~= nil,
  "Future Sight cast starts through Protect and hidden target")
check(battle:volatile(b).lockOn, "Future Sight cast preserves Lock On for landing")

battle, a, b = fixture("TRIPLE_KICK")
local checks, hp = 0, b.hp
battle.accuracyRoll = function()
  checks = checks + 1
  return checks == 1
end
battle.random = function(n) return n == 3 and 2 or math.min(127, n - 1) end
battle:useMove(a, b, "TRIPLE_KICK")
eq(checks, 1, "Triple Kick checks accuracy only once")
check(b.hp < hp - 10, "Triple Kick later kicks land after first accuracy check")

battle, a, b = fixture("PSYCHIC")
battle:volatile(b).substitute = 1
battle.random = function() return 0 end
battle:useMove(a, b, "PSYCHIC")
eq(battle:volatile(b).substitute, nil, "Psychic breaks one HP substitute")
eq(battle.stages.enemy.specialDefense, 0, "Broken substitute still blocks same hit secondary")

for _, id in ipairs({ "DISABLE", "ENCORE", "LOCK_ON", "BEAT_UP" }) do
  battle, a, b = fixture(id)
  battle:volatile(b).lastMove = "TACKLE"
  local before, rolls = b.hp, 0
  battle.accuracyRoll = function() rolls = rolls + 1 return false end
  battle:useMove(a, b, id)
  eq(rolls, 1, id .. " checks accuracy")
  eq(battle:volatile(b).disabled, nil, id .. " miss does not disable")
  eq(battle:volatile(b).encore, nil, id .. " miss does not encore")
  eq(battle:volatile(b).lockOn, nil, id .. " miss does not lock on")
  eq(b.hp, before, id .. " miss deals no damage")
end

battle, a, b = fixture("JUMP_KICK")
local before = a.hp
battle.accuracyRoll = function() return false end
battle:useMove(a, b, "JUMP_KICK")
check(a.hp < before, "Jump Kick actual miss applies crash")
eq(b.hp, b.maxHp, "Jump Kick missed target takes no damage")

battle, a, b = fixture("PURSUIT")
local bench = Mon.new(data, "TEST", 50, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
bench.moves = { { id = "TACKLE", pp = 20, maxPp = 20 } }
battle.enemyParty, battle.enemyIndex, battle.linkBattle = { b, bench }, 1, true
local outgoing, incoming = b.hp, bench.hp
battle:takeLinkTurn({ kind = "move", move = "PURSUIT" }, { kind = "switch", index = 2 })
check(b.hp < outgoing, "Pursuit attacks outgoing mon before switch")
eq(bench.hp, incoming, "Pursuit action is consumed before incoming mon")
eq(a.moves[1].pp, 19, "Pursuit spends PP once on switch")
eq(battle.enemy, bench, "Pursuit switch completes with healthy replacement")

battle, a, b = fixture("PRESENT")
data.text.PresentFailedText = "present failed fixture"
battle.random = function(n) return n - 1 end
battle:useMove(a, b, "PRESENT")
eq(b.hp, b.maxHp, "Present cannot heal a full HP target")
eq(battle.events[#battle.events].text, "TEST\nused PRESENT!", "Present full HP is silent with battle scene on")
battle, a, b = fixture("PRESENT")
battle.save = { options = { battleScene = false } }
battle.random = function(n) return n - 1 end
battle:useMove(a, b, "PRESENT")
eq(battle.events[#battle.events].text, "present failed fixture", "Present full HP failure text with battle scene off")

battle, a, b = fixture("TACKLE")
battle:volatile(b).types = { "FIRE", "FIRE" }
Battle.MOVE_EFFECTS.EFFECT_TRANSFORM(battle, a, b)
eq(battle:battlerTypes(a)[1], "FIRE", "Transform copies Conversion type override")
battle:clearVolatile(a)
eq(battle:battlerTypes(a)[1], "NORMAL", "Transform type override restores on switch")

battle, a, b = fixture("TACKLE")
battle.firstMover = "enemy"
battle:volatile(b).recharge = true
eq(battle:flinch(b), false, "Natural flinch refuses a target that moved first")
eq(battle:volatile(b).recharge, true, "Refused natural flinch preserves recharge")
eq(battle:flinch(b, true), true, "Held flinch has its own first mover behavior")
eq(battle:volatile(b).recharge, nil, "Held flinch clears recharge")

battle, a, b = fixture("TACKLE")
battle:volatile(a).protect = true
battle:volatile(a).endure = true
battle:volatile(a).flinched = true
battle.linkBattle = true
battle:takeLinkTurn({ kind = "move", move = "TACKLE" }, { kind = "move", move = "TACKLE" })
check(b.hp < b.maxHp, "Previous round flinch does not cancel new round action")
check(a.hp < a.maxHp, "Previous round Protect does not block new round attack")

battle, a, b = fixture("PRESENT")
battle.linkBattle = true
a.stats.attack, b.stats.defense = 400, 1
battle.random = function(n) return math.min(100, n - 1) end
before = b.hp
battle:useMove(a, b, "PRESENT")
eq(before - b.hp, 27, "Link Present preserves cartridge type register damage bug")

moves.IRON_TAIL = { id = "IRON_TAIL", name = "IRON TAIL", type = "NORMAL",
  power = 100, accuracy = 100, accuracyRaw = 255, pp = 15,
  effect = "EFFECT_DEFENSE_DOWN_HIT", effectChanceRaw = 255 }
battle, a, b = fixture("IRON_TAIL")
data.type_chart.battleRules.moveScripts.EFFECT_DEFENSE_DOWN_HIT = {
  "effectchance", "applydamage", "effectchance", "defensedown" }
battle:volatile(b).substitute = 1
battle.random = function() return 0 end
battle:useMove(a, b, "IRON_TAIL")
eq(battle.stages.enemy.defense, -1, "Defense drop script repeats effect chance after Substitute breaks")

battle, a, b = fixture("FUTURE_SIGHT")
battle:useMove(a, b, "FUTURE_SIGHT")
battle.moveRuleFutureSight.player.count = 2
battle.moveRuleLastDamage = 99
battle.accuracyRoll = function() return false end
before = b.hp
battle:tickFutureSight(a)
eq(b.hp, before, "Future Sight miss leaves target HP unchanged")
eq(battle.moveRuleLastDamage, 0, "Future Sight miss clears cartridge current damage")

moves.FISSURE = { id = "FISSURE", name = "FISSURE", type = "NORMAL", power = 1,
  accuracy = 30, accuracyRaw = 76, pp = 5, effect = "EFFECT_OHKO" }
moves.THUNDER = { id = "THUNDER", name = "THUNDER", type = "NORMAL", power = 120,
  accuracy = 70, accuracyRaw = 178, pp = 10, effect = "EFFECT_THUNDER",
  effectChance = 30, effectChanceRaw = 77 }
moves.SELFDESTRUCT = { id = "SELFDESTRUCT", name = "SELFDESTRUCT", type = "NORMAL",
  power = 200, accuracy = 100, accuracyRaw = 255, pp = 5, effect = "EFFECT_SELFDESTRUCT" }

local function byteRoll(value)
  return function(n) if n == 256 then return value end return 0 end
end

local function fissure(userLevel, targetLevel, roll)
  local fb, fa, fe = fixture("FISSURE")
  fb.accuracyRoll = nil
  fa.level, fe.level = userLevel, targetLevel
  fb.random = byteRoll(roll)
  local hp = fe.hp
  fb:useMove(fa, fe, "FISSURE")
  return fe.hp < hp
end
check(fissure(50, 40, 95), "Fissure +10 levels hits on byte 95 (76 + 20 = 96)")
check(not fissure(50, 40, 96), "Fissure +10 levels misses on byte 96")
check(fissure(75, 40, 145), "Fissure +35 levels hits on byte 145 (76 + 70 = 146)")
check(not fissure(75, 40, 146), "Fissure +35 levels misses on byte 146, not a sure hit")
check(not fissure(40, 50, 0), "Fissure fails against a higher level target")

local function thunder(weather, evasion, roll)
  local tb, ta, te = fixture("THUNDER")
  tb.accuracyRoll = nil
  tb.weather = weather
  tb.stages.enemy.evasion = evasion
  tb.random = byteRoll(roll)
  local hp = te.hp
  tb:useMove(ta, te, "THUNDER")
  return te.hp < hp
end
check(thunder("rain", 6, 255), "Thunder in rain hits through +6 evasion on the highest byte")
check(not thunder(nil, 6, 255), "Thunder without rain still misses on the highest byte")
check(thunder("sun", 0, 127), "Thunder in sun hits on byte 127 (128/256)")
check(not thunder("sun", 0, 128), "Thunder in sun misses on byte 128")

moves.CLUBHIT = { id = "CLUBHIT", name = "CLUBHIT", type = "NORMAL", power = 80,
  accuracy = 100, accuracyRaw = 255, pp = 20, effect = "EFFECT_NORMAL_HIT" }
pokemon.MAROWAK = {}
for key, value in pairs(pokemon.TEST) do pokemon.MAROWAK[key] = value end
pokemon.MAROWAK.id, pokemon.MAROWAK.name = "MAROWAK", "MAROWAK"
local function clubDamage(species, partySpecies, item)
  local tb, ta, te = fixture("CLUBHIT")
  ta.species, ta.item = species, item
  if partySpecies then tb:volatile(ta).preTransform = { species = partySpecies } end
  tb.random = byteRoll(0)
  local hp = te.hp
  tb:useMove(ta, te, "CLUBHIT")
  return hp - te.hp
end
local plain = clubDamage("TEST", nil, nil)
check(plain > 0, "Club hit deals damage")
check(clubDamage("TEST", "MAROWAK", "THICK_CLUB") > plain,
  "a transformed MAROWAK-party mon still gets Thick Club")
eq(clubDamage("MAROWAK", "TEST", "THICK_CLUB"), plain,
  "a mon transformed into MAROWAK from another party species gets no Thick Club")

local function obeyDamage(moveId)
  local ob, oa = fixture("TACKLE")
  oa.level, oa.otId = 50, 1
  ob.save = { player = { id = 2 } }
  oa.stats.attack, oa.stats.defense = 100, 100
  local calls = 0
  local script = { 20, 20, 50 }
  ob.random = function() calls = calls + 1 return script[calls] or 0 end
  local hp = oa.hp
  check(ob:checkObedience(moveId), "an over-level traded mon disobeys")
  return hp - oa.hp
end
check(obeyDamage("SELFDESTRUCT") > obeyDamage("TACKLE"),
  "the disobedience self-hit halves Defense when the picked move is Selfdestruct")

local function typedSpecies(id, kind)
  local entry = {}
  for k, v in pairs(pokemon.TEST) do entry[k] = v end
  entry.id, entry.name, entry.types = id, id, { kind, kind }
  pokemon[id] = entry
end
typedSpecies("GHOSTLY", "GHOST")
typedSpecies("ROCKY", "ROCK")
typedSpecies("FIRY", "FIRE")
data.type_chart.types.ROCK = { index = 5, name = "ROCK", category = "physical" }
table.insert(data.type_chart.matchups, { attacker = "NORMAL", defender = "GHOST", multiplier = 0 })
table.insert(data.type_chart.matchups, { attacker = "NORMAL", defender = "ROCK", multiplier = 5 })
moves.STRUGGLE = { id = "STRUGGLE", name = "STRUGGLE", effect = "EFFECT_RECOIL_HIT",
  power = 50, accuracy = 100, accuracyRaw = 255, pp = 1, type = "NORMAL" }
moves.TWINEEDLE = { id = "TWINEEDLE", name = "TWINEEDLE", effect = "EFFECT_POISON_MULTI_HIT",
  power = 25, accuracy = 100, accuracyRaw = 255, pp = 20, type = "NORMAL",
  effectChance = 20, effectChanceRaw = 255 }

local function struggleDamage(attackerSpecies, targetSpecies)
  local sb, sa, st = fixture("STRUGGLE")
  local attacker = Mon.new(data, attackerSpecies, 50, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
  local target = Mon.new(data, targetSpecies, 50, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
  attacker.moves = { { id = "STRUGGLE", pp = 20, maxPp = 20 } }
  sb.player, sb.enemy = attacker, target
  sb.party = { attacker }
  local hp = target.hp
  sb:useMove(attacker, target, "STRUGGLE")
  return hp - target.hp
end
local baseline = struggleDamage("FIRY", "TEST")
check(baseline > 0, "Struggle damages a plain target")
eq(struggleDamage("TEST", "TEST"), baseline, "Struggle gets no STAB from a Normal user")
check(struggleDamage("TEST", "GHOSTLY") > 0, "Struggle hits a Ghost")
eq(struggleDamage("TEST", "GHOSTLY"), baseline, "Struggle ignores the Ghost immunity row")
eq(struggleDamage("TEST", "ROCKY"), baseline, "Struggle is not resisted by Rock")

local function twineedle(effectRoll)
  local tb, ta, tt = fixture("TWINEEDLE")
  tb.random = function(n) return math.min(effectRoll, n - 1) end
  tb:useMove(ta, tt, "TWINEEDLE")
  return tt
end
eq(twineedle(0).status, "poison", "Twineedle poisons through its effect chance")
eq(twineedle(255).status, nil, "Twineedle leaves a target alone when the effect roll fails")

T.finish("Crystal battle integration")
