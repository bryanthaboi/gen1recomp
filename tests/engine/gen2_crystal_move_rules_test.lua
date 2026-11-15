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
local effects = { FUTURE_SIGHT = "FUTURE_SIGHT", COUNTER = "COUNTER", MIRROR_COAT = "MIRROR_COAT", PURSUIT = "PURSUIT", HAZE = "RESET_STATS", HEAL_BELL = "HEAL_BELL",
  PAIN_SPLIT = "PAIN_SPLIT", SWAGGER = "SWAGGER", MIMIC = "MIMIC",
  CONVERSION = "CONVERSION", CONVERSION2 = "CONVERSION2",
  DESTINY_BOND = "DESTINY_BOND", RAPID_SPIN = "RAPID_SPIN",
  HIDDEN_POWER = "HIDDEN_POWER", FLAIL = "REVERSAL", PRESENT = "PRESENT",
  TACKLE = "NORMAL_HIT", EMBER = "BURN_HIT", TRIPLE_KICK = "TRIPLE_KICK",
  TRANSFORM = "TRANSFORM", BATON_PASS = "BATON_PASS", PROTECT = "PROTECT", RAGE = "RAGE",
  MINIMIZE = "EVASION_UP", JUMP_KICK = "JUMP_KICK", DISABLE = "DISABLE", ENCORE = "ENCORE",
  LOCK_ON = "LOCK_ON", DOUBLE_KICK = "DOUBLE_HIT" }
for id, effect in pairs(effects) do
  moves[id] = { id = id, name = id, effect = "EFFECT_" .. effect,
    power = 0, accuracy = 100, accuracyRaw = 255, pp = 20, type = "NORMAL" }
end
for _, id in ipairs({ "RAPID_SPIN", "HIDDEN_POWER", "FLAIL", "PRESENT",
    "TACKLE", "EMBER", "TRIPLE_KICK", "FUTURE_SIGHT", "PURSUIT" }) do moves[id].power = 1 end
moves.EMBER.type = "FIRE"
moves.FUTURE_SIGHT.type = "PSYCHIC_TYPE"
moves.FUTURE_SIGHT.power = 80
moves.COUNTER.type = "FIGHTING"
moves.MIRROR_COAT.type = "PSYCHIC_TYPE"
moves.PURSUIT.type = "DARK"
moves.RAGE.power, moves.DOUBLE_KICK.power = 20, 30
moves.JUMP_KICK.power, moves.JUMP_KICK.type = 70, "FIGHTING"
local text = require("tests.fixture_data.gen2_rom_text_s7_a").text(
  require("tests.fixture_data.gen2_rom_text_s7_b").text(nil, "crystal"), "crystal")
for _, label in ipairs({ "EliminatedStatsText", "BellChimedText", "SharedPainText",
    "DestinyBondEffectText", "MimicLearnedMoveText", "TransformedTypeText",
    "ShedLeechSeedText", "BlewSpikesText", "ReleasedByText", "RageBuildingText",
    "TookDownWithItText", "AttackMissedText", "AttackMissed2Text", "DoesntAffectText", "ButItFailedText", "ItFailedText", "DidntAffect1Text", "DidntAffect2Text", "PresentFailedText", "HurtItselfText", "WasDisabledText", "GotAnEncoreText", "TookAimText", "RegainedHealthText", "CrashedText", "ForesawAttackText", "BattleText_TargetWasHitByFutureSight" }) do text[label] = label end
local data = { pokemon = pokemon, moves = moves, items = {}, text = text,
  type_chart = { types = { NORMAL = { index = 0, name = "NORMAL", category = "physical" },
    FIRE = { index = 20, name = "FIRE", category = "special" },
    FIGHTING = { index = 1, name = "FIGHTING", category = "physical" },
    GHOST = { index = 8, name = "GHOST", category = "physical" },
    PSYCHIC_TYPE = { index = 24, name = "PSYCHIC", category = "special" },
    DARK = { index = 27, name = "DARK", category = "special" } },
    matchups = { { attacker = "FIGHTING", defender = "GHOST", multiplier = 0 },
      { attacker = "PSYCHIC_TYPE", defender = "DARK", multiplier = 0 },
      { attacker = "NORMAL", defender = "GHOST", multiplier = 0 } },
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
  local battle = Battle.new({ data = data, party = { a }, wild = b, random = function() return 0 end })
  battle.accuracyRoll = function() return true end
  return battle, a, b
end
local battle, a, b = fixture("FUTURE_SIGHT")
battle:useMove(a, b, "FUTURE_SIGHT")
local hp = b.hp
battle:tickFutureSight(a)
eq(b.hp, hp, "Future Sight does not land on opening turn")
local incoming = Mon.new(data, "TEST", 50, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
battle:clearVolatile(a)
battle.player = incoming
battle:tickFutureSight(incoming)
eq(b.hp, hp, "Future Sight remains pending on second turn")
battle:tickFutureSight(incoming)
check(b.hp < hp, "Future Sight survives caster switching and lands third turn")
battle, a, b = fixture("FUTURE_SIGHT")
battle:volatile(b).types = { "DARK", "DARK" }
battle:useMove(a, b, "FUTURE_SIGHT")
for _ = 1, 3 do battle:tickFutureSight(a) end
check(b.hp < b.maxHp, "Future Sight ignores Dark immunity")
battle, a, b = fixture("FUTURE_SIGHT")
battle:useMove(a, b, "FUTURE_SIGHT")
battle.accuracyRoll = function() return false end
for _ = 1, 3 do battle:tickFutureSight(a) end
eq(b.hp, b.maxHp, "Future Sight accuracy checked on landing")
battle, a, b = fixture("FUTURE_SIGHT")
battle:volatile(b).protect, battle:volatile(b).vanished = true, true
battle:useMove(a, b, "FUTURE_SIGHT")
check(battle.moveRuleFutureSight and battle.moveRuleFutureSight.player ~= nil,
  "Future Sight cast ignores Protect and hidden target")
battle, a, b = fixture("COUNTER")
battle.turn = 1
battle.moveRuleFirstSide = "enemy"
battle:volatile(b).lastMove = "TACKLE"
battle:volatile(a).substitute = 20
battle:dealDamage(b, a, 12, { move = moves.TACKLE })
battle:useMove(a, b, "COUNTER")
eq(b.hp, b.maxHp, "Counter fails after a hit on the user's substitute")
eq(battle.events[#battle.events].text, "AttackMissedText", "Counter failure prints the miss text")
battle, a, b = fixture("COUNTER")
battle.turn = 1
battle.moveRuleFirstSide = "enemy"
battle:volatile(b).types = { "GHOST", "GHOST" }
battle:volatile(b).lastMove = "TACKLE"
battle:dealDamage(b, a, 12, { move = moves.TACKLE })
battle:useMove(a, b, "COUNTER")
eq(b.hp, b.maxHp, "Counter fails on Ghost target")
battle, a, b = fixture("COUNTER")
battle.moveRuleFirstSide = "player"
battle:volatile(b).lastMove = "TACKLE"
battle:dealDamage(b, a, 12, { move = moves.TACKLE })
battle:useMove(a, b, "COUNTER")
eq(b.hp, b.maxHp, "Counter fails if user goes first")
battle, a, b = fixture("PURSUIT")
local called, before = 0, b.hp
battle.canAct = function() return true end
battle.useMove = function(self, user, target, id)
  called = called + 1
  eq(id, "PURSUIT", "Pursuit intercept uses chosen move")
  eq(self.moveRuleSwitching, "enemy", "Pursuit marks outgoing side")
  self:dealDamage(user, target, 10, { move = moves.PURSUIT })
end
check(battle:pursuitSwitch(b, "PURSUIT"), "Pursuit intercepts switch")
eq(b.hp, before - 10, "Pursuit damages outgoing mon")
check(not battle:pursuitSwitch(b, "PURSUIT"), "Pursuit cannot act twice this turn")
eq(called, 1, "Pursuit consumes one action")
battle, a, b = fixture("TACKLE")
battle:jumpKickCrash(a, b, 79, { effectiveness = 10 })
eq(a.hp, a.maxHp - 9, "Jump Kick crash is one eighth calculated damage")
battle:jumpKickCrash(a, b, 79, { effectiveness = 0 })
eq(a.hp, a.maxHp - 9, "Jump Kick immunity causes no crash")
local function lastText(battle)
  for i = #battle.events, 1, -1 do
    if battle.events[i].text then return battle.events[i].text end
  end
end
local function hasText(battle, wanted)
  for _, event in ipairs(battle.events) do
    if event.text == wanted then return true end
  end
  return false
end

battle, a, b = fixture("MIMIC")
a.moves = { { id = "MIMIC", pp = 20, maxPp = 20 }, { id = "TACKLE", pp = 20, maxPp = 20 } }
battle:volatile(b).lastMove = "TRANSFORM"
battle:useMove(a, b, "MIMIC")
eq(a.moves[1].id, "TRANSFORM", "Mimic copies Transform")
battle:useMove(a, b, "TRANSFORM")
battle:clearAllVolatiles()
eq(a.moves[1].id, "MIMIC", "Mimic then Transform leaves the party Mimic slot")

battle, a, b = fixture("MIMIC")
battle:volatile(b).lastMove = "TACKLE"
battle:useMove(a, b, "MIMIC")
battle:endBattle("win")
eq(a.moves[1].id, "MIMIC", "endBattle restores the Mimic slot")

battle, a, b = fixture("MIMIC")
local receiver = Mon.new(data, "TEST", 50, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
receiver.moves = { { id = "EMBER", pp = 20, maxPp = 20 } }
battle.party[2] = receiver
a.moves = { { id = "MIMIC", pp = 20, maxPp = 20 }, { id = "BATON_PASS", pp = 20, maxPp = 20 } }
battle:volatile(b).lastMove = "TACKLE"
battle:useMove(a, b, "MIMIC")
battle:volatile(a).types = { "FIRE", "FIRE" }
battle:useMove(a, b, "BATON_PASS")
eq(battle.player, receiver, "Baton Pass sends the receiver")
eq(battle:battlerTypes(receiver)[1], "NORMAL", "Baton Pass does not carry the Conversion type")
battle:clearAllVolatiles()
eq(receiver.moves[1].id, "EMBER", "Baton Pass after Mimic keeps the receiver's moves")
eq(a.moves[1].id, "MIMIC", "Baton Pass after Mimic restores the passer's Mimic")

battle, a, b = fixture("COUNTER")
battle.turn, battle.moveRuleFirstSide = 1, "enemy"
battle:volatile(b).lastMove = "TACKLE"
a.hp = 5
battle:volatile(a).endure = true
battle:dealDamage(b, a, 50, { move = moves.TACKLE })
eq(a.hp, 1, "Endure leaves one HP")
battle:useMove(a, b, "COUNTER")
eq(b.hp, b.maxHp - 8, "Counter after Endure doubles HP-1")

battle, a, b = fixture("COUNTER")
battle.linkBattle = true
battle.moveRuleLastDamage = 40
battle.accuracyRoll = function() return false end
battle:takeLinkTurn({ kind = "move", move = "COUNTER" }, { kind = "move", move = "TACKLE" })
eq(battle:volatile(b).lastMove, "TACKLE", "Foe's missed Tackle is its last move")
eq(b.hp, b.maxHp, "Counter fails after the foe missed (damage cleared at turn start)")
battle:confusionSelfHit(b)
eq(battle.moveRuleLastDamage, 0, "Confusion self-hit resets the Counter damage")

battle, a, b = fixture("DESTINY_BOND")
battle.linkBattle = true
a.stats.speed = b.stats.speed + 10
battle:takeLinkTurn({ kind = "move", move = "DESTINY_BOND" }, { kind = "move", move = "TACKLE" })
eq(battle:volatile(a).destinyBond, nil, "Destiny Bond ends after the foe's next move")
battle, a, b = fixture("TACKLE")
battle:volatile(b).destinyBond = true
b.hp = 1
battle:useMove(a, b, "TACKLE")
eq(a.hp, 0, "Destiny Bond takes the attacker down")
local textAt, faintAt
for i, event in ipairs(battle.events) do
  if event.text == "TookDownWithItText" then textAt = i end
  if event.kind == "damage" and event.side == "player" then faintAt = i end
end
check(textAt and faintAt and textAt < faintAt, "Took-down text prints before the attacker's HP drops")
battle, a, b = fixture("TACKLE")
battle.moveRuleFutureSight = { player = { count = 2, damage = 500 } }
battle:volatile(b).destinyBond = true
battle:tickFutureSight(a)
eq(b.hp, 0, "Future Sight KOs the Destiny Bond holder")
eq(a.hp, 0, "Future Sight KO triggers Destiny Bond")

battle, a, b = fixture("SWAGGER")
battle.stages.enemy.attack = 6
battle:useMove(a, b, "SWAGGER")
eq(battle:volatile(b).confuseCount, nil, "Swagger at +6 Attack does not confuse")
eq(lastText(battle), "AttackMissedText", "Swagger at +6 Attack prints the miss text")
battle, a, b = fixture("SWAGGER")
battle:volatile(b).confuseCount = 3
battle:useMove(a, b, "SWAGGER")
eq(battle.stages.enemy.attack, 2, "Swagger raises an already confused target")
check(not lastText(battle):find("confused"), "Swagger is silent on an already confused target")
battle, a, b = fixture("SWAGGER")
battle.accuracyRoll = function() return false end
battle:useMove(a, b, "SWAGGER")
eq(lastText(battle), "AttackMissedText", "Swagger miss prints the miss text")

battle, a, b = fixture("TACKLE")
battle.linkBattle = true
b.moves = { { id = "PROTECT", pp = 20, maxPp = 20 } }
battle.moveRuleFutureSight = { player = { count = 2, damage = 30 } }
local turnEvents = battle:takeLinkTurn({ kind = "move", move = "TACKLE" }, { kind = "move", move = "PROTECT" })
local blocked = false
for _, event in ipairs(turnEvents) do
  if event.text == battle:romText("ProtectingItselfText", battle.player, battle.enemy) then
    blocked = true
  end
end
check(blocked, "Protect blocks the Tackle")
check(b.hp < b.maxHp, "Future Sight lands on a target whose Protect ended with the foe's move")

battle, a, b = fixture("TACKLE")
local bench = Mon.new(data, "TEST", 50, { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
bench.moves = { { id = "TACKLE", pp = 20, maxPp = 20 } }
battle.enemyParty = { b, bench }
battle:volatile(a).lastMove = "TACKLE"
battle:forcedReplacement("enemy", 2)
eq(battle:volatile(a).lastMove, nil, "Send-out clears the opponent's last counter move")
battle.player.moves = { { id = "TACKLE", pp = 20, maxPp = 20 } }
bench.moves[2] = { id = "ENCORE", pp = 20, maxPp = 20 }
battle:useMove(bench, a, "ENCORE")
eq(battle:volatile(a).encore, "TACKLE", "Encore still reads the opponent's last move after a send-out")

battle, a, b = fixture("RAGE")
battle.accuracyRoll = function() return false end
battle:useMove(a, b, "RAGE")
eq(battle:volatile(a).rage, nil, "Missed Rage does not start rage")
battle, a, b = fixture("TACKLE")
battle.linkBattle = true
battle:volatile(a).rage, battle:volatile(a).rageCount = true, 2
battle:takeLinkTurn({ kind = "item", item = "POTION" }, { kind = "move", move = "TACKLE" })
eq(battle:volatile(a).rage, nil, "Choosing an item clears rage")
eq(battle:volatile(a).rageCount, nil, "Choosing an item clears the rage counter")

battle, a, b = fixture("HEAL_BELL")
a.status, a.toxicCounter = "toxic", 3
battle:useMove(a, b, "HEAL_BELL")
eq(a.status, nil, "Heal Bell cures toxic")
battle:applyStatus(a, "poison", b)
eq(a.status, "toxic", "Heal Bell keeps the toxic bit for a later poisoning")
eq(a.toxicCounter, 3, "Heal Bell keeps the toxic counter")

battle, a, b = fixture("MINIMIZE")
battle.stages.player.evasion = 6
battle:useMove(a, b, "MINIMIZE")
eq(battle:volatile(a).minimized, nil, "Minimize at +6 evasion does not set the minimize flag")
battle.stages.player.evasion = 0
battle:useMove(a, b, "MINIMIZE")
eq(battle:volatile(a).minimized, true, "Minimize sets the flag when evasion rises")

battle, a, b = fixture("PURSUIT")
b.moves = { { id = "PURSUIT", pp = 20, maxPp = 20 } }
a.hp, a.happiness = 1, 70
battle:pursuitSwitch(a, "PURSUIT")
eq(a.hp, 0, "Pursuit KOs the outgoing mon")
eq(a.happiness, 70, "Pursuit KO costs no happiness")

battle, a, b = fixture("TRANSFORM")
a.dvs = { attack = 0, defense = 0, speed = 0, special = 0 }
local wantPower, wantType = battle:hiddenPower(b)
battle:useMove(a, b, "TRANSFORM")
local gotPower, gotType = battle:hiddenPower(a)
eq(gotPower, wantPower, "Transformed Hidden Power uses copied DVs for power")
eq(gotType, wantType, "Transformed Hidden Power uses copied DVs for type")

battle, a, b = fixture("PRESENT")
battle.accuracyRoll = function() return false end
battle:useMove(a, b, "PRESENT")
eq(lastText(battle), "AttackMissedText", "Present miss prints the miss text")
battle, a, b = fixture("PRESENT")
battle:volatile(b).types = { "GHOST", "GHOST" }
battle:useMove(a, b, "PRESENT")
eq(lastText(battle), "DoesntAffectText", "Present into a Ghost prints doesn't affect")

battle, a, b = fixture("PAIN_SPLIT")
battle:volatile(b).substitute = 10
battle:useMove(a, b, "PAIN_SPLIT")
eq(lastText(battle), "DidntAffect1Text", "Pain Split into a Substitute prints didn't affect")
battle, a, b = fixture("PAIN_SPLIT")
battle.accuracyRoll = function() return false end
battle:useMove(a, b, "PAIN_SPLIT")
eq(lastText(battle), "DidntAffect1Text", "Pain Split miss prints didn't affect")

battle, a, b = fixture("JUMP_KICK")
battle:volatile(b).types = { "GHOST", "GHOST" }
local hpBefore = a.hp
battle:useMove(a, b, "JUMP_KICK")
eq(lastText(battle), "DoesntAffectText", "Jump Kick into a Ghost prints doesn't affect")
check(battle.moveEvent.missed, "Jump Kick into a Ghost plays no hit animation")
eq(a.hp, hpBefore, "Jump Kick into a Ghost does not crash")

for _, case in ipairs({ { "DISABLE", "ButItFailedText" }, { "ENCORE", "DidntAffect1Text" },
    { "LOCK_ON", "DidntAffect1Text" } }) do
  battle, a, b = fixture(case[1])
  battle:volatile(b).lastMove = "TACKLE"
  battle.accuracyRoll = function() return false end
  battle:useMove(a, b, case[1])
  eq(lastText(battle), case[2], case[1] .. " miss text")
end
battle, a, b = fixture("ENCORE")
battle:useMove(a, b, "ENCORE")
eq(lastText(battle), "DidntAffect1Text", "Encore with no last move prints didn't affect")

battle, a, b = fixture("FUTURE_SIGHT")
battle:useMove(a, b, "FUTURE_SIGHT")
battle:useMove(a, b, "FUTURE_SIGHT")
eq(lastText(battle), "ButItFailedText", "Future Sight while one is pending prints but it failed")
battle.accuracyRoll = function() return false end
for _ = 1, 3 do battle:tickFutureSight(a) end
eq(lastText(battle), "ButItFailedText", "Future Sight landing miss prints but it failed")

battle, a, b = fixture("TRIPLE_KICK")
battle:useMove(a, b, "TRIPLE_KICK")
check(hasText(battle, "Hit 1 times!"), "One-kick Triple Kick prints Hit 1 times!")
battle, a, b = fixture("DOUBLE_KICK")
battle:useMove(a, b, "DOUBLE_KICK")
check(hasText(battle, "Hit 2 times!"), "Double Kick prints its hit count")
local firstHit
for _, event in ipairs(battle.events) do
  if event.kind == "damage" and event.side == "enemy" then firstHit = firstHit or event.amount end
end
battle, a, b = fixture("DOUBLE_KICK")
b.hp = firstHit + 1
battle:useMove(a, b, "DOUBLE_KICK")
eq(b.hp, 0, "Double Kick KOs on the second hit")
check(not hasText(battle, "Hit 2 times!"), "No hit count after a KO mid-loop")

T.finish("Crystal delayed and reactive moves")
