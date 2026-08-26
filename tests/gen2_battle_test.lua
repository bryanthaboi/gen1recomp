-- Gen 2 battle math and turn engine.  ROM-free: the fixtures below are the
-- shapes the extractor writes, with numbers traceable to pokegold so a failure
-- names the ASM it disagrees with.

package.path = "./?.lua;" .. package.path

local Battle = require("src.battle.gen2.Battle")
local Catching = require("src.battle.gen2.Catching")
local Damage = require("src.battle.gen2.Damage")
local Encounter = require("src.battle.gen2.Encounter")
local HpBar = require("src.battle.gen2.HpBar")
local Mon = require("src.battle.gen2.Mon")

local failures, checks = 0, 0

local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(
      name, tostring(got), tostring(want)))
  end
end

local function checkNear(name, got, want, slack)
  checks = checks + 1
  if math.abs((got or 0) - want) > (slack or 0) then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s +/- %s"):format(
      name, tostring(got), tostring(want), tostring(slack)))
  end
end

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  FIGHTING = { id = "FIGHTING", index = 1, category = "physical" },
  FLYING = { id = "FLYING", index = 2, category = "physical" },
  GROUND = { id = "GROUND", index = 4, category = "physical" },
  ROCK = { id = "ROCK", index = 5, category = "physical" },
  STEEL = { id = "STEEL", index = 9, category = "physical" },
  FIRE = { id = "FIRE", index = 20, category = "special" },
  WATER = { id = "WATER", index = 21, category = "special" },
  GRASS = { id = "GRASS", index = 22, category = "special" },
  ELECTRIC = { id = "ELECTRIC", index = 23, category = "special" },
  DARK = { id = "DARK", index = 27, category = "special" },
}

-- A slice of data/types/type_matchups.asm.
local MATCHUPS = {
  { attacker = "FIRE", defender = "GRASS", multiplier = 20 },
  { attacker = "FIRE", defender = "WATER", multiplier = 5 },
  { attacker = "FIRE", defender = "STEEL", multiplier = 20 },
  { attacker = "WATER", defender = "FIRE", multiplier = 20 },
  { attacker = "WATER", defender = "ROCK", multiplier = 20 },
  { attacker = "WATER", defender = "GROUND", multiplier = 20 },
  { attacker = "NORMAL", defender = "ROCK", multiplier = 5 },
  { attacker = "NORMAL", defender = "STEEL", multiplier = 5 },
  { attacker = "ELECTRIC", defender = "GROUND", multiplier = 0 },
  -- Sonic Boom is Normal; Gen 2 StaticDamage still respects Ghost immunity.
  { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  EMBER = { id = "EMBER", name = "EMBER", power = 40, type = "FIRE",
    accuracy = 100, pp = 25, effect = "EFFECT_BURN_HIT", effectChance = 10 },
  WATER_GUN = { id = "WATER_GUN", name = "WATER GUN", power = 40,
    type = "WATER", accuracy = 100, pp = 25, effect = "EFFECT_NORMAL_HIT" },
  THUNDER_WAVE = { id = "THUNDER_WAVE", name = "THUNDERWAVE", power = 0,
    type = "ELECTRIC", accuracy = 100, pp = 20, effect = "EFFECT_PARALYZE" },
  QUICK_ATTACK = { id = "QUICK_ATTACK", name = "QUICK ATTACK", power = 40,
    type = "NORMAL", accuracy = 100, pp = 30,
    effect = "EFFECT_PRIORITY_HIT" },
  SPORE = { id = "SPORE", name = "SPORE", power = 0, type = "GRASS",
    accuracy = 100, pp = 15, effect = "EFFECT_SLEEP" },
  -- The status-shaped moves the effect layer models, at their real numbers.
  RAIN_DANCE = { id = "RAIN_DANCE", name = "RAIN DANCE", power = 0,
    type = "WATER", accuracy = 100, pp = 5, effect = "EFFECT_RAIN_DANCE" },
  SPIKES = { id = "SPIKES", name = "SPIKES", power = 0, type = "GROUND",
    accuracy = 100, pp = 20, effect = "EFFECT_SPIKES" },
  PERISH_SONG = { id = "PERISH_SONG", name = "PERISH SONG", power = 0,
    type = "NORMAL", accuracy = 100, pp = 5, effect = "EFFECT_PERISH_SONG" },
  TRANSFORM = { id = "TRANSFORM", name = "TRANSFORM", power = 0,
    type = "NORMAL", accuracy = 100, pp = 10, effect = "EFFECT_TRANSFORM" },
  ENDURE = { id = "ENDURE", name = "ENDURE", power = 0, type = "NORMAL",
    accuracy = 100, pp = 10, effect = "EFFECT_ENDURE" },
  RAGE = { id = "RAGE", name = "RAGE", power = 20, type = "NORMAL",
    accuracy = 100, pp = 20, effect = "EFFECT_RAGE" },
  -- data/moves/moves.asm:133, :230, :189 and :92 rows, unedited.
  BIDE = { id = "BIDE", name = "BIDE", power = 0, type = "NORMAL",
    accuracy = 100, pp = 10, effect = "EFFECT_BIDE" },
  SLEEP_TALK = { id = "SLEEP_TALK", name = "SLEEP TALK", power = 0,
    type = "NORMAL", accuracy = 100, pp = 10, effect = "EFFECT_SLEEP_TALK" },
  SNORE = { id = "SNORE", name = "SNORE", power = 40, type = "NORMAL",
    accuracy = 100, pp = 15, effect = "EFFECT_SNORE", effectChance = 30 },
  SOLARBEAM = { id = "SOLARBEAM", name = "SOLARBEAM", power = 120,
    type = "GRASS", accuracy = 100, pp = 10, effect = "EFFECT_SOLARBEAM" },
}

local GROWTH = {
  -- data/growth_rates.asm rows.
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15,
    linear = 100, constant = 140 },
  GROWTH_FAST = { numerator = 4, denominator = 5, squared = 0, linear = 0,
    constant = 0 },
  GROWTH_SLOW = { numerator = 5, denominator = 4, squared = 0, linear = 0,
    constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  CYNDAQUIL = {
    id = "CYNDAQUIL", index = 155, name = "CYNDAQUIL",
    baseStats = { hp = 39, attack = 52, defense = 43, speed = 65,
      specialAttack = 60, specialDefense = 50 },
    types = { "FIRE", "FIRE" }, catchRate = 45, baseExp = 65,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = {
      { level = 1, move = "TACKLE" }, { level = 1, move = "LEER" },
      { level = 6, move = "SMOKESCREEN" }, { level = 12, move = "EMBER" },
      { level = 19, move = "QUICK_ATTACK" }, { level = 27, move = "FLAME_WHEEL" },
    },
    evolutions = { { method = "EVOLVE_LEVEL", level = 14, into = "QUILAVA" } },
  },
  TOTODILE = {
    id = "TOTODILE", index = 158, name = "TOTODILE",
    baseStats = { hp = 50, attack = 65, defense = 64, speed = 43,
      specialAttack = 44, specialDefense = 48 },
    types = { "WATER", "WATER" }, catchRate = 45, baseExp = 66,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "SCRATCH" },
      { level = 7, move = "WATER_GUN" } },
    evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "FLYING" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } },
    evolutions = {},
  },
  GEODUDE = {
    id = "GEODUDE", index = 74, name = "GEODUDE",
    baseStats = { hp = 40, attack = 80, defense = 100, speed = 20,
      specialAttack = 30, specialDefense = 30 },
    types = { "ROCK", "GROUND" }, catchRate = 255, baseExp = 73,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } },
    evolutions = {},
  },
  GASTLY = {
    id = "GASTLY", index = 92, name = "GASTLY",
    baseStats = { hp = 30, attack = 35, defense = 30, speed = 80,
      specialAttack = 100, specialDefense = 35 },
    types = { "GHOST", "POISON" }, catchRate = 190, baseExp = 62,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 127,
    levelMoves = { { level = 1, move = "LICK" } },
    evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = MATCHUPS },
  items = {
    POKE_BALL = { id = "POKE_BALL", pocket = "BALL" },
    POTION = { id = "POTION", pocket = "ITEM" },
  },
}

-- Deterministic "random": always returns 0, i.e. the first outcome.  Passed as
-- random(n) -> 0..n-1, which is the same contract BattleRandom has.
local function zeroRandom() return 0 end
-- Always the *last* outcome.
local function maxRandom(n) return n - 1 end

-- ------------------------------------------------------------------- stats

-- Gen 2's stat formula is Gen 1's.  A level-5 Cyndaquil with perfect DVs:
--   HP  = floor(((39*2 + 15*2) * 5) / 100) + 5 + 10 = 20
--   Atk = floor(((52*2 + 15*2) * 5) / 100) + 5      = 11
local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)
check("perfect HP DV", perfect.hp, 15)
local stats = Mon.stats(POKEMON.CYNDAQUIL.baseStats, perfect, 5)
check("cyndaquil L5 hp", stats.hp, 20)
check("cyndaquil L5 attack", stats.attack, 11)
-- SpA and SpD both read the one Special DV, so they differ only by base stat
-- (Cyndaquil's are 60 and 50).
check("cyndaquil L5 spA", stats.specialAttack, 12)
check("cyndaquil L5 spD", stats.specialDefense, 11)

local zero = { attack = 0, defense = 0, speed = 0, special = 0 }
zero.hp = Mon.hpDV(zero)
check("zero HP DV", zero.hp, 0)
check("cyndaquil L5 hp zero DVs", Mon.stats(
  POKEMON.CYNDAQUIL.baseStats, zero, 5).hp, 18)

-- --------------------------------------------------------------- experience

-- MEDIUM_FAST is n^3, so level 10 costs 1000.
check("medium fast L10", Mon.experienceForLevel(GROWTH.GROWTH_MEDIUM_FAST, 10),
  1000)
check("fast L10", Mon.experienceForLevel(GROWTH.GROWTH_FAST, 10), 800)
check("slow L10", Mon.experienceForLevel(GROWTH.GROWTH_SLOW, 10), 1250)
-- MEDIUM_SLOW: 6/5 n^3 - 15 n^2 + 100 n - 140.  At 10: 1200 - 1500 + 1000 - 140.
check("medium slow L10", Mon.experienceForLevel(GROWTH.GROWTH_MEDIUM_SLOW, 10),
  560)
check("level for 1000 medium fast",
  Mon.levelForExperience(GROWTH.GROWTH_MEDIUM_FAST, 1000), 10)
check("level for 999 medium fast",
  Mon.levelForExperience(GROWTH.GROWTH_MEDIUM_FAST, 999), 9)

-- exp = baseExp * level / 7, halved per extra participant, x1.5 for a trainer.
check("exp gain wild", Mon.experienceGain(POKEMON.PIDGEY, 7, 1, false),
  math.floor(55 * 7 / 7))
check("exp gain split", Mon.experienceGain(POKEMON.PIDGEY, 7, 2, false),
  math.floor(math.floor(55 * 7 / 7) / 2))
check("exp gain trainer", Mon.experienceGain(POKEMON.PIDGEY, 7, 1, true),
  math.floor(math.floor(55 * 7 / 7) * 3 / 2))

-- Moves at a level: the last four learned at or below it.
local moves = Mon.movesAtLevel(POKEMON.CYNDAQUIL, 19, MOVES)
check("moves at L19 count", #moves, 4)
check("moves at L19 first", moves[1].id, "LEER")
check("moves at L19 last", moves[4].id, "QUICK_ATTACK")
check("move pp", Mon.movesAtLevel(POKEMON.CYNDAQUIL, 12, MOVES)[4].pp, 25)

-- Level-up: the gain reports which levels and moves it crossed.
local cyndaquil = Mon.new(DATA, "CYNDAQUIL", 5, { dvs = perfect })
check("new mon level", cyndaquil.level, 5)
check("new mon at full hp", cyndaquil.hp, cyndaquil.maxHp)
local growth = GROWTH.GROWTH_MEDIUM_SLOW
local toSix = Mon.experienceForLevel(growth, 6)
  - Mon.experienceForLevel(growth, 5)
local result = Mon.gainExperience(cyndaquil, toSix, DATA)
check("levelled once", result.levels, 1)
check("levelled to 6", cyndaquil.level, 6)
check("learned smokescreen at 6", result.learned[1], "SMOKESCREEN")

-- AskLearnMove on a full moveset: resolveForget drops a slot and learns the
-- newcomer, declineForget keeps the four.  Before these existed the
-- choose-forget event was emitted and dropped, so no mon could learn a move
-- past a full set -- the bot's starter reached the League on its level-1
-- moves.  Powers come from MOVES above; the pending move is a fresh entry.
do
  local learner = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
  learner.moves = {
    { id = "TACKLE", pp = 35, maxPp = 35 },       -- power 35, the weakest
    { id = "EMBER", pp = 25, maxPp = 25 },        -- power 40
    { id = "QUICK_ATTACK", pp = 30, maxPp = 30 }, -- power 40
    { id = "WATER_GUN", pp = 25, maxPp = 25 },    -- power 40
  }
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  local b = Battle.new({ data = DATA, party = { learner }, wild = wild,
    random = zeroRandom })
  b:takeEvents()  -- clear intro

  local newMove = { id = "SPORE", pp = 15, maxPp = 15 }
  check("resolveForget drops slot 1 and learns the new move",
    b:resolveForget(1, 1, newMove, "SPORE"), true)
  check("the slot now holds the newcomer", learner.moves[1].id, "SPORE")
  check("the other three are untouched", learner.moves[2].id, "EMBER")
  local ev = b:takeEvents()
  check("it queues a forgot line then a learned line", #ev, 2)
  check("forgot text names the dropped move",
    ev[1].text:find("forgot TACKLE") ~= nil, true)
  check("learned text names the new move",
    ev[2].text:find("learned SPORE") ~= nil, true)

  -- Decline keeps the moveset and says so.
  b:declineForget(1, "SPORE")
  local dev = b:takeEvents()
  check("decline queues one line", #dev, 1)
  check("and it is the did-not-learn line",
    dev[1].text:find("did not learn SPORE") ~= nil, true)
end

-- Evolution threshold.
check("cyndaquil evolves at 14",
  (Mon.evolutionAtLevel(POKEMON.CYNDAQUIL, 14) or {}).into, "QUILAVA")
check("cyndaquil not at 13",
  Mon.evolutionAtLevel(POKEMON.CYNDAQUIL, 13), nil)

-- ------------------------------------------------------------------ damage

-- The formula, with every multiplier pinned so the arithmetic is checkable:
--   base = ((2*10/5 + 2) * 40 * 20 / 20) / 50 = (6 * 40) / 50 = 4
check("base damage", Damage.base(10, 40, 20, 20), 4)
-- Defence of 0 is clamped to 1 rather than dividing by zero.
check("base damage zero defence", Damage.base(10, 40, 20, 0),
  Damage.base(10, 40, 20, 1))
check("base damage no power", Damage.base(10, 0, 20, 20), 0)

-- Physical / special split is by type: NORMAL physical, FIRE special.
check("normal is physical", Damage.isPhysical("NORMAL", TYPES), true)
check("fire is special", Damage.isPhysical("FIRE", TYPES), false)
check("steel is physical", Damage.isPhysical("STEEL", TYPES), true)
check("dark is special", Damage.isPhysical("DARK", TYPES), false)

-- ...and it decides which stats are read.  Same numbers, different stats.
local physicalAttacker = {
  attack = 100, specialAttack = 10, types = { "NORMAL" },
}
local defender = { defense = 50, specialDefense = 200, types = { "FIRE" } }
local physicalDamage = Damage.calc({
  level = 50, power = 40, moveType = "NORMAL",
  attacker = physicalAttacker, defender = defender,
  types = TYPES, matchups = MATCHUPS, variation = 100,
})
local specialDamage = Damage.calc({
  level = 50, power = 40, moveType = "FIRE",
  attacker = { attack = 100, specialAttack = 10, types = { "NORMAL" } },
  defender = defender,
  types = TYPES, matchups = MATCHUPS, variation = 100,
})
check("physical reads attack/defense", physicalDamage > specialDamage, true)

-- Type effectiveness stacks per row and floors between: Water on Rock/Ground
-- is 2x twice.
check("water vs rock/ground",
  Damage.typeMultiplier("WATER", { "ROCK", "GROUND" }, MATCHUPS), 40)
check("normal vs rock", Damage.typeMultiplier("NORMAL", { "ROCK" }, MATCHUPS), 5)
check("fire vs steel", Damage.typeMultiplier("FIRE", { "STEEL" }, MATCHUPS), 20)
check("electric vs ground immune",
  Damage.typeMultiplier("ELECTRIC", { "GROUND" }, MATCHUPS), 0)
check("neutral", Damage.typeMultiplier("NORMAL", { "FIRE" }, MATCHUPS), 10)

-- An immune matchup does no damage at all.
local immune = Damage.calc({
  level = 50, power = 95, moveType = "ELECTRIC",
  attacker = { specialAttack = 100, types = { "ELECTRIC" } },
  defender = { specialDefense = 50, types = { "GROUND" } },
  types = TYPES, matchups = MATCHUPS, variation = 100,
})
check("immune deals nothing", immune, 0)

-- STAB is x1.5, and a critical hit is x2 on top.
local plain = Damage.calc({
  level = 50, power = 40, moveType = "NORMAL",
  attacker = { attack = 100, types = { "FIRE" } },
  defender = { defense = 50, types = { "FIRE" } },
  types = TYPES, matchups = MATCHUPS, variation = 100,
})
local stabbed = Damage.calc({
  level = 50, power = 40, moveType = "NORMAL",
  attacker = { attack = 100, types = { "NORMAL" } },
  defender = { defense = 50, types = { "FIRE" } },
  types = TYPES, matchups = MATCHUPS, variation = 100,
})
check("stab is 1.5x", stabbed, math.floor(plain * 15 / 10))
local crit = Damage.calc({
  level = 50, power = 40, moveType = "NORMAL",
  attacker = { attack = 100, types = { "FIRE" } },
  defender = { defense = 50, types = { "FIRE" } },
  types = TYPES, matchups = MATCHUPS, variation = 100, critical = true,
})
-- The x2 runs inside DamageCalc, BEFORE its tail adds MIN_DAMAGE back, so a
-- crit is twice the pre-minimum damage plus 2, not twice the finished number.
check("critical is 2x", crit, (plain - Damage.MIN_DAMAGE) * 2
  + Damage.MIN_DAMAGE)

-- A critical hit ignores the attacker's negative stages and the defender's
-- positive ones -- but keeps the ones that help.
local lowered = Damage.calc({
  level = 50, power = 40, moveType = "NORMAL",
  attacker = { attack = 100, types = { "FIRE" }, stages = { attack = -2 } },
  defender = { defense = 50, types = { "FIRE" }, stages = { defense = 2 } },
  types = TYPES, matchups = MATCHUPS, variation = 100,
})
local loweredCrit = Damage.calc({
  level = 50, power = 40, moveType = "NORMAL",
  attacker = { attack = 100, types = { "FIRE" }, stages = { attack = -2 } },
  defender = { defense = 50, types = { "FIRE" }, stages = { defense = 2 } },
  types = TYPES, matchups = MATCHUPS, variation = 100, critical = true,
})
check("crit ignores bad stages", loweredCrit, crit)
check("stages do apply without a crit", lowered < plain, true)
local raised = Damage.calc({
  level = 50, power = 40, moveType = "NORMAL",
  attacker = { attack = 100, types = { "FIRE" }, stages = { attack = 2 } },
  defender = { defense = 50, types = { "FIRE" } },
  types = TYPES, matchups = MATCHUPS, variation = 100, critical = true,
})
check("crit keeps good stages", raised > loweredCrit, true)

-- Reflect / Light Screen doubles defence, and a crit ignores it.
local screened = Damage.calc({
  level = 50, power = 40, moveType = "NORMAL",
  attacker = { attack = 100, types = { "FIRE" } },
  defender = { defense = 50, types = { "FIRE" } },
  types = TYPES, matchups = MATCHUPS, variation = 100, screen = true,
})
check("screen halves damage", screened < plain, true)
local screenedCrit = Damage.calc({
  level = 50, power = 40, moveType = "NORMAL",
  attacker = { attack = 100, types = { "FIRE" } },
  defender = { defense = 50, types = { "FIRE" } },
  types = TYPES, matchups = MATCHUPS, variation = 100, screen = true,
  critical = true,
})
check("crit ignores screen", screenedCrit, crit)

-- Damage variation is 85-100% of the maximum.
local low = Damage.calc({
  level = 50, power = 40, moveType = "NORMAL",
  attacker = { attack = 100, types = { "FIRE" } },
  defender = { defense = 50, types = { "FIRE" } },
  types = TYPES, matchups = MATCHUPS, variation = 85,
})
check("85% is the floor", low, math.floor(plain * 85 / 100))
check("100% is the max", plain > low, true)

-- Stat stage table matches the cart's fractions.
check("stage +2 doubles", Damage.applyStage(100, 2), 200)
check("stage -2 halves", Damage.applyStage(100, -2), 50)
check("stage +6 quadruples", Damage.applyStage(100, 6), 400)
check("stage clamps above 6", Damage.applyStage(100, 9),
  Damage.applyStage(100, 6))
check("stage never reaches zero", Damage.applyStage(1, -6), 1)

-- Critical chance ladder (data/battle/critical_hit_chances.asm).
check("crit level 0 is 1/15", Damage.criticalChance(0), 15)
check("crit level 1 is 1/8", Damage.criticalChance(1), 8)
check("crit level 2 is 1/4", Damage.criticalChance(2), 4)
check("crit level 4 is 1/2", Damage.criticalChance(4), 2)
check("focus energy is +1",
  Damage.criticalLevel({ focusEnergy = true }), 1)
check("high crit move is +2",
  Damage.criticalLevel({ highCritMove = true }), 2)
check("focus + high crit + lens",
  Damage.criticalLevel({ focusEnergy = true, highCritMove = true,
    scopeLens = true }), 4)
check("crit level caps at 6",
  Damage.criticalLevel({ focusEnergy = true, highCritMove = true,
    scopeLens = true, speciesItemBonus = true }), 6)
check("roll 0 crits", Damage.rollCritical(0, zeroRandom), true)
check("max roll misses", Damage.rollCritical(0, maxRandom), false)

-- Accuracy: 0 in the data means never miss.
check("accuracy 0 always hits", Damage.rollHit(0, 0, 0, maxRandom), true)
check("accuracy 100 always hits", Damage.rollHit(100, 0, 0, maxRandom), true)
check("accuracy 50 misses on a high roll",
  Damage.rollHit(50, 0, 0, maxRandom), false)
check("accuracy 50 hits on a low roll",
  Damage.rollHit(50, 0, 0, zeroRandom), true)
check("evasion lowers accuracy", Damage.rollHit(95, 0, 6, function() return 30 end),
  false)

-- ------------------------------------------------------------------- HP bar

-- ComputeHPBarPixels: curHP * 48 / maxHP, floored, with a live mon never
-- showing an empty bar and a fainted one showing exactly nothing.
check("bar length", HpBar.LENGTH_PX, 48)
check("full bar", HpBar.pixels(20, 20), 48)
check("empty bar", HpBar.pixels(0, 20), 0)
check("half bar", HpBar.pixels(10, 20), 24)
check("quarter bar", HpBar.pixels(5, 20), 12)
-- 1 HP out of 100 rounds down to 0 pixels, which the routine forces to 1: a
-- living mon always has some bar left.
check("1 of 100 shows one pixel", HpBar.pixels(1, 100), 1)
check("floors rather than rounds", HpBar.pixels(7, 20),
  math.floor(7 * 48 / 20))
-- The maxHP >= 256 shift: both sides divide by 4 first, so the bar moves in
-- coarser steps than the exact ratio.  Reproduced on purpose.
check("high HP shifts", HpBar.pixels(300, 400),
  math.floor(math.floor(300 * 48 / 4) / math.floor(400 / 4)))

-- GetHPPal boundaries are on the *pixel* count: 24 is still green and 10 is
-- still yellow, which is why exactly half HP is not yellow.
check("green threshold", HpBar.GREEN_PIXELS, 24)
check("yellow threshold", HpBar.YELLOW_PIXELS, 10)
check("24 pixels is green", HpBar.palette(24), "green")
check("23 pixels is yellow", HpBar.palette(23), "yellow")
check("10 pixels is yellow", HpBar.palette(10), "yellow")
check("9 pixels is red", HpBar.palette(9), "red")
check("exactly half HP is green", HpBar.paletteFor(10, 20), "green")
check("just under half is yellow", HpBar.paletteFor(9, 20), "yellow")
check("one HP is red", HpBar.paletteFor(1, 20), "red")
check("fainted is red", HpBar.palette(0), "red")

-- ---------------------------------------------------------------- catching

-- A full-HP mon with catchRate 45 in a Poke Ball is a poor bet; the same mon at
-- 1 HP asleep is a good one.
local fullRate = Catching.rate({
  maxHp = 60, hp = 60, catchRate = 45, ball = "POKE_BALL" })
local hurtRate = Catching.rate({
  maxHp = 60, hp = 1, catchRate = 45, ball = "POKE_BALL" })
check("hurt is easier to catch", hurtRate > fullRate, true)
local asleepRate = Catching.rate({
  maxHp = 60, hp = 1, catchRate = 45, ball = "POKE_BALL", status = "sleep" })
check("sleep adds 10", asleepRate, math.min(255, hurtRate + 10))
checkNear("preview converts the exact byte roll", Catching.chance({
  maxHp = 60, hp = 60, catchRate = 45, ball = "POKE_BALL" }),
  fullRate * 100 / 256, 0.000001)
check("master ball preview is certain", Catching.chance({
  maxHp = 60, hp = 60, catchRate = 1, ball = "MASTER_BALL" }), 100)
-- The cart's bug: burn/poison/paralysis add nothing.
check("poison adds nothing (cart bug)", Catching.rate({
  maxHp = 60, hp = 1, catchRate = 45, ball = "POKE_BALL",
  status = "poison" }), hurtRate)
check("poison adds 5 with fixBugs", Catching.rate({
  maxHp = 60, hp = 1, catchRate = 45, ball = "POKE_BALL",
  status = "poison", fixBugs = true }), math.min(255, hurtRate + 5))
-- Better balls multiply the species rate.
check("ultra beats great", Catching.rate({
  maxHp = 60, hp = 30, catchRate = 45, ball = "ULTRA_BALL" })
  > Catching.rate({ maxHp = 60, hp = 30, catchRate = 45,
    ball = "GREAT_BALL" }), true)
-- A Master Ball never fails.
-- The second return is wFinalCatchRate, the row GetPokeBallWobble re-rolls
-- against once per wobble; the wobble COUNT is the animation's, not this
-- routine's (engine/battle_anims/pokeball_wobble.asm).
local caught, finalRate = Catching.attempt({
  maxHp = 300, hp = 300, catchRate = 3, ball = "MASTER_BALL",
  random = maxRandom })
check("master ball always catches", caught, true)
check("master ball reports its final rate", finalRate, 255)
check("poke ball can fail", (Catching.attempt({
  maxHp = 60, hp = 60, catchRate = 3, ball = "POKE_BALL",
  random = maxRandom })), false)
-- A rate that reaches the 255 cap is certain even on the worst roll; without
-- the sleep bonus the same mon sits at 252 and can still break out.
check("capped rate catches", (Catching.attempt({
  maxHp = 60, hp = 1, catchRate = 255, ball = "ULTRA_BALL",
  status = "sleep", random = maxRandom })), true)
check("252 is not certain", (Catching.attempt({
  maxHp = 60, hp = 1, catchRate = 255, ball = "ULTRA_BALL",
  random = maxRandom })), false)

-- -------------------------------------------------------------- encounters

local ENCOUNTERS = {
  grass = {
    ROUTE_29 = {
      map = "ROUTE_29",
      rates = { MORN = 25, DAY = 25, NITE = 25 },
      slots = {
        MORN = { { level = 2, species = "PIDGEY" },
          { level = 2, species = "SENTRET" }, { level = 3, species = "PIDGEY" },
          { level = 3, species = "SENTRET" }, { level = 4, species = "PIDGEY" },
          { level = 2, species = "RATTATA" }, { level = 3, species = "RATTATA" } },
        DAY = { { level = 2, species = "PIDGEY" },
          { level = 2, species = "SENTRET" }, { level = 3, species = "PIDGEY" },
          { level = 3, species = "SENTRET" }, { level = 4, species = "PIDGEY" },
          { level = 2, species = "RATTATA" }, { level = 3, species = "RATTATA" } },
        NITE = { { level = 2, species = "HOOTHOOT" },
          { level = 2, species = "HOOTHOOT" }, { level = 3, species = "HOOTHOOT" },
          { level = 3, species = "RATTATA" }, { level = 4, species = "HOOTHOOT" },
          { level = 2, species = "RATTATA" }, { level = 3, species = "RATTATA" } },
      },
    },
  },
  water = {
    ROUTE_30 = { map = "ROUTE_30", rate = 2,
      slots = { { level = 15, species = "POLIWAG" },
        { level = 20, species = "POLIWHIRL" },
        { level = 15, species = "POLIWAG" } } },
  },
  fishGroups = {
    FISHGROUP_SHORE = { id = "FISHGROUP_SHORE", chance = 128,
      old = { { chance = 179, species = "MAGIKARP", level = 10 },
        { chance = 217, species = "MAGIKARP", level = 10 },
        { chance = 255, species = "KRABBY", level = 10 } },
      good = {}, super = {} },
  },
  trees = { ROUTE_29 = "TREEMON_SET_CANYON" },
}

-- The time of day picks the list: morning is Pidgey, night is Hoothoot.
check("morn slot 1", Encounter.grassSlot(ENCOUNTERS, "ROUTE_29", "MORN",
  zeroRandom).species, "PIDGEY")
check("nite slot 1", Encounter.grassSlot(ENCOUNTERS, "ROUTE_29", "NITE",
  zeroRandom).species, "HOOTHOOT")
-- DARK reuses the night list, since the cart only stores three.
check("dark reuses nite", Encounter.grassSlot(ENCOUNTERS, "ROUTE_29", "DARK",
  zeroRandom).species, "HOOTHOOT")
-- Slot probabilities: a roll of 99 lands in the last (1%) slot.
check("roll 99 is slot 7", Encounter.grassSlot(ENCOUNTERS, "ROUTE_29", "MORN",
  function() return 99 end).slot, 7)
check("roll 0 is slot 1", Encounter.grassSlot(ENCOUNTERS, "ROUTE_29", "MORN",
  zeroRandom).slot, 1)
check("roll 30 is slot 2", Encounter.grassSlot(ENCOUNTERS, "ROUTE_29", "MORN",
  function() return 30 end).slot, 2)
check("no table means no encounter",
  Encounter.grassSlot(ENCOUNTERS, "NEW_BARK_TOWN", "DAY", zeroRandom), nil)

check("rate morn", Encounter.grassRate(ENCOUNTERS, "ROUTE_29", "MORN"), 25)
check("rate for a mapless entry",
  Encounter.grassRate(ENCOUNTERS, "NEW_BARK_TOWN", "DAY"), 0)
check("rate 25 triggers on a low roll",
  Encounter.triggers(25, zeroRandom), true)
check("rate 25 misses on a high roll",
  Encounter.triggers(25, maxRandom), false)
check("rate 0 never triggers", Encounter.triggers(0, zeroRandom), false)

check("water slot 1", Encounter.waterSlot(ENCOUNTERS, "ROUTE_30",
  zeroRandom).species, "POLIWAG")
check("water roll 60 is slot 2", Encounter.waterSlot(ENCOUNTERS, "ROUTE_30",
  function() return 60 end).slot, 2)
check("fishing old rod", Encounter.fish(ENCOUNTERS, "FISHGROUP_SHORE", "old",
  zeroRandom).species, "MAGIKARP")
check("fishing high roll is krabby", Encounter.fish(ENCOUNTERS,
  "FISHGROUP_SHORE", "old", function() return 220 end).species, "KRABBY")
check("headbutt set", Encounter.treeSet(ENCOUNTERS, "ROUTE_29"),
  "TREEMON_SET_CANYON")

-- ------------------------------------------------------------------ battle

local function newBattle(opts)
  opts = opts or {}
  local player = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  player.moves = {
    { id = "TACKLE", pp = 35, maxPp = 35 },
    { id = "EMBER", pp = 25, maxPp = 25 },
  }
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  return Battle.new({
    data = DATA,
    party = opts.party or { player },
    wild = opts.wild ~= false and wild or nil,
    trainer = opts.trainer,
    random = opts.random or zeroRandom,
  }), player, wild
end

local battle, player, wild = newBattle()
check("battle picks the first healthy mon", battle.player, player)
check("wild battle flag", battle.wild, true)

-- Gen 2 battles expose BattleRandom (`random` / :roller()) and the Gen 1 /
-- love.math `rng` over the same stream.
check("battle.rng is present", type(battle.rng), "function")
check("battle.rng(lo,hi) respects bounds", battle.rng(10, 10), 10)
check("battle.rng(lo,hi) another fixed point", battle.rng(50, 50), 50)
do
  local roll = battle.rng(0, 255)
  check("battle.rng(0,255) is an integer", roll == math.floor(roll), true)
  check("battle.rng(0,255) in range", roll >= 0 and roll <= 255, true)
end
-- zeroRandom always returns 0, so the love adapter maps:
--   rng(n) → 0+1 = 1; rng(lo,hi) → lo + 0 = lo
check("battle.rng(n) is 1..n over BattleRandom", battle.rng(7), 1)
check("battle.rng(0,99) uses both args", battle.rng(0, 99), 0)

-- A move spends PP and deals damage.
local before = wild.hp
battle:takeTurn({ kind = "move", move = "TACKLE" })
check("pp spent", player.moves[1].pp, 34)
check("wild took damage", wild.hp < before, true)

-- Priority beats Speed: Quick Attack goes first even from the slower side.
local orderBattle = newBattle()
orderBattle.player.stats.speed = 1
orderBattle.enemy.stats.speed = 200
check("slower side still first with priority",
  orderBattle:orderOf("QUICK_ATTACK", "TACKLE"), "player")
check("faster side first otherwise",
  orderBattle:orderOf("TACKLE", "TACKLE"), "enemy")
orderBattle.player.stats.speed = 200
orderBattle.enemy.stats.speed = 1
check("faster player first", orderBattle:orderOf("TACKLE", "TACKLE"), "player")

-- Paralysis quarters Speed, which can flip the order.
orderBattle.player.stats.speed = 100
orderBattle.enemy.stats.speed = 50
check("player faster", orderBattle:orderOf("TACKLE", "TACKLE"), "player")
orderBattle.player.status = "paralyze"
check("paralysed player is slower",
  orderBattle:orderOf("TACKLE", "TACKLE"), "enemy")
orderBattle.player.status = nil

-- A status move lands its status, and a second one fails.
local statusBattle = newBattle()
statusBattle.player.moves = { { id = "THUNDER_WAVE", pp = 20, maxPp = 20 } }
statusBattle:takeTurn({ kind = "move", move = "THUNDER_WAVE" })
check("thunder wave paralysed", statusBattle.enemy.status, "paralyze")
statusBattle.player.moves[1].pp = 20
statusBattle:takeTurn({ kind = "move", move = "THUNDER_WAVE" })
check("a second status fails", statusBattle.enemy.status, "paralyze")

-- Sleep lands with a turn counter, and canAct spends it.  The counter opens at
-- 2, so the target cannot wake in the round it was slept
-- (engine/battle/effect_commands.asm:3591-3598, #1707).
local sleepBattle = newBattle()
sleepBattle.player.moves = { { id = "SPORE", pp = 15, maxPp = 15 } }
sleepBattle:useMove(sleepBattle.player, sleepBattle.enemy, "SPORE")
check("spore slept the target", sleepBattle.enemy.status, "sleep")
check("sleep never opens shorter than two turns",
  (sleepBattle.enemy.statusTurns or 0) >= 2, true)
check("the lowest roll is exactly two", sleepBattle.enemy.statusTurns, 2)
-- A sleeping mon cannot act, and the counter runs down to a wake-up.
sleepBattle.enemy.statusTurns = 2
check("asleep cannot act", sleepBattle:canAct(sleepBattle.enemy), false)
check("counter spent", sleepBattle.enemy.statusTurns, 1)
check("wakes on the last turn", sleepBattle:canAct(sleepBattle.enemy), true)
check("status cleared on waking", sleepBattle.enemy.status, nil)

-- Burn chips 1/8 max HP at end of turn and halves physical attack.
local burnBattle = newBattle()
burnBattle.enemy.status = "burn"
local enemyMax = burnBattle.enemy.maxHp
local hpBefore = burnBattle.enemy.hp
burnBattle:takeTurn({ kind = "move", move = "TACKLE" })
check("burn ticked", burnBattle.enemy.hp
  <= hpBefore - math.floor(enemyMax / 8), true)

-- Fainting the wild mon ends the battle and awards experience.
local expBattle, expPlayer, expWild = newBattle()
local expBefore = expPlayer.experience
expWild.hp = 1
expBattle:takeTurn({ kind = "move", move = "TACKLE" })
check("battle over after faint", expBattle.over, true)
check("outcome win", expBattle.outcome, "win")
check("experience gained", expPlayer.experience > expBefore, true)

-- Losing with no healthy party ends it the other way.
local loseBattle, losePlayer = newBattle()
losePlayer.hp = 0
loseBattle.player.hp = 0
loseBattle:resolveFaints()
check("outcome lose", loseBattle.outcome, "lose")

-- Running: a faster mon always escapes, a trainer battle never lets you.
local runBattle = newBattle()
runBattle.player.stats.speed = 200
runBattle.enemy.stats.speed = 1
check("faster mon runs", runBattle:tryRun(), true)
check("run outcome", runBattle.outcome, "run")

local trainerParty = { Mon.new(DATA, "GEODUDE", 8, { dvs = perfect }) }
trainerParty[1].moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
local trainerBattle = Battle.new({
  data = DATA,
  party = { Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect }) },
  trainer = { class = "YOUNGSTER", name = "JOEY", party = trainerParty },
  random = zeroRandom,
})
check("trainer battle is not wild", trainerBattle.wild, false)
check("cannot run from a trainer", trainerBattle:tryRun(), false)
check("trainer battle still going", trainerBattle.over, false)

-- A trainer's second mon comes out when the first faints.
local twoParty = {
  Mon.new(DATA, "GEODUDE", 8, { dvs = perfect }),
  Mon.new(DATA, "PIDGEY", 8, { dvs = perfect }),
}
for _, mon in ipairs(twoParty) do
  mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
end
local twoBattle = Battle.new({
  data = DATA,
  party = { Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect }) },
  trainer = { class = "YOUNGSTER", name = "JOEY", party = twoParty },
  random = zeroRandom,
})
twoBattle.player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
twoParty[1].hp = 1
twoBattle:takeTurn({ kind = "move", move = "TACKLE" })
check("second mon sent out", twoBattle.enemy, twoParty[2])
check("battle not over yet", twoBattle.over, false)

do
  -- ...and it does NOT answer on the turn it walked in.  Battle_PlayerFirst
  -- reaches HandleEnemyMonFaint with `jp`, not `call`
  -- (engine/battle/core.asm:872), so the round's attack phase is over -- and
  -- the move that was picked for the mon that fainted is never spent by the one
  -- that replaced it.  The lead knows a move the bench mon does not, so a stale
  -- selection would be visible by name.
  local staleParty = {
    Mon.new(DATA, "GEODUDE", 8, { dvs = perfect }),
    Mon.new(DATA, "PIDGEY", 8, { dvs = perfect }),
  }
  staleParty[1].moves = { { id = "EMBER", pp = 25, maxPp = 25 } }
  staleParty[2].moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local staleBattle = Battle.new({
    data = DATA,
    party = { Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect }) },
    trainer = { class = "YOUNGSTER", name = "JOEY", party = staleParty },
    random = zeroRandom,
  })
  staleBattle.player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  staleParty[1].hp = 1
  local hpBeforeFaint = staleBattle.player.hp
  local staleEvents = staleBattle:takeTurn({ kind = "move", move = "TACKLE" })
  local sawSend, enemyMovedAfterSend = false, false
  for _, event in ipairs(staleEvents) do
    if event.kind == "send" and event.side == "enemy" then sawSend = true end
    if sawSend and event.kind == "move" and event.side == "enemy" then
      enemyMovedAfterSend = true
    end
  end
  check("the replacement was sent out", sawSend, true)
  check("and never attacked on the way in", enemyMovedAfterSend, false)
  check("so the player took nothing back", staleBattle.player.hp, hpBeforeFaint)
  check("and the dead mon's EMBER was not spent by it",
    staleParty[2].moves[1].pp, 35)

    -- A mid-turn rotation announces the mon coming OFF the field first.
  -- AI_Switch prints EnemyWithdrewText before it farcalls EnemySwitch
  -- (engine/battle/ai/items.asm:685), which is the only cue a trainer
  -- swapping between two mons of the same species gives.
  local rotateParty = {
    Mon.new(DATA, "GEODUDE", 8, { dvs = perfect }),
    Mon.new(DATA, "PIDGEY", 8, { dvs = perfect }),
  }
  for _, mon in ipairs(rotateParty) do
    mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  end
  local rotateBattle = Battle.new({
    data = DATA,
    party = { Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect }) },
    -- attributes[6] is the low byte of the switch flags: OFTEN.
    trainer = { class = "YOUNGSTER", name = "JOEY", party = rotateParty,
      attributes = { 0, 0, 0, 0, 0, 0x01, 0 } },
    random = zeroRandom,
  })
  -- Perish Song at one turn left is CheckAbleToSwitch's maximum score, which
  -- is the cheapest way to make the AI commit to the rotation.
  rotateBattle:volatile(rotateBattle.enemy).perish = 1
  check("the AI rotated", rotateBattle:enemyTrySwitchOrItem(), true)
  local withdrew, sentOut = nil, nil
  for _, event in ipairs(rotateBattle:takeEvents()) do
    if event.kind == "message" and not withdrew then withdrew = event.text end
    if event.kind == "send" then sentOut = event.text end
  end
  check("EnemyWithdrewText comes first", withdrew, "JOEY withdrew GEODUDE!")
  check("then the send-out line", sentOut, "JOEY sent out PIDGEY!")

  -- A refused RUN costs nothing.  .cant_run_from_trainer leaves
  -- wBattlePlayerAction at BATTLEPLAYERACTION_USEMOVE, so BattleMenu_Run's
  -- `jp BattleMenu` (engine/battle/core.asm:5035-5038) reopens the menu with the
  -- turn unspent; only the failed roll writes BATTLEPLAYERACTION_USEITEM.
  local refuseParty = { Mon.new(DATA, "GEODUDE", 8, { dvs = perfect }) }
  refuseParty[1].moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local refuseBattle = Battle.new({
    data = DATA,
    party = { Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect }) },
    trainer = { class = "YOUNGSTER", name = "JOEY", party = refuseParty },
    random = zeroRandom,
  })
  refuseBattle.player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local hpBeforeRun = refuseBattle.player.hp
  local refuseEvents = refuseBattle:takeTurn({ kind = "run" })
  local enemyAnswered = false
  for _, event in ipairs(refuseEvents) do
    if event.kind == "move" and event.side == "enemy" then enemyAnswered = true end
  end
  check("the trainer refusal ends the turn there", enemyAnswered, false)
  check("and the enemy got no free hit", refuseBattle.player.hp, hpBeforeRun)
  check("the trainer's PP is untouched", refuseParty[1].moves[1].pp, 35)
end

-- ResetBattleParticipants falls through into AddBattleParticipant
-- (engine/battle/core.asm:3033 and :3037), so every ENEMY-initiated mon change
-- wipes both bitfields and re-credits the mon the player has out.  The player's
-- own send-outs only ever call AddBattleParticipant (core.asm:2655, :2681,
-- :3783, :4989, :5014).
do
  local function creditBattle()
    local party = {
      Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect }),
      Mon.new(DATA, "TOTODILE", 20, { dvs = perfect }),
    }
    local foes = {
      Mon.new(DATA, "GEODUDE", 8, { dvs = perfect }),
      Mon.new(DATA, "PIDGEY", 8, { dvs = perfect }),
    }
    for _, mon in ipairs(party) do
      mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    end
    for _, mon in ipairs(foes) do
      mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    end
    local battle = Battle.new({
      data = DATA, party = party,
      -- attributes[6] is the low byte of the switch flags: OFTEN.
      trainer = { class = "YOUNGSTER", name = "JOEY", party = foes,
        attributes = { 0, 0, 0, 0, 0, 0x01, 0 } },
      random = zeroRandom,
    })
    battle:switch(2)
    return battle, party, foes
  end

  -- AI_Switch (engine/battle/ai/items.asm:697).
  local rotate, rotateParty, rotateFoes = creditBattle()
  check("both mons are credited before the rotation",
    rotate.participants[1] and rotate.participants[2], true)
  rotate:volatile(rotate.enemy).perish = 1
  check("the AI rotated", rotate:enemyTrySwitchOrItem(), true)
  check("the rotation installed the second foe", rotate.enemy, rotateFoes[2])
  check("the bench mon lost its credit", rotate.participants[1], nil)
  check("only the mon on the field keeps it", rotate.participants[2], true)
  local benchExp = rotateParty[1].experience
  local activeExp = rotateParty[2].experience
  rotate:awardExperience(rotate.enemy)
  check("the bench mon earns nothing from the new foe",
    rotateParty[1].experience, benchExp)
  check("and the mon that faced it is still paid",
    rotateParty[2].experience > activeExp, true)

  -- ForceEnemySwitch (engine/battle/core.asm:2937), reached only from
  -- BattleCommand_ForceSwitch (effect_commands.asm:4999).
  local roar, _, roarFoes = creditBattle()
  roar.firstMover = "enemy"
  Battle.MOVE_EFFECTS.EFFECT_FORCE_SWITCH(roar, roar.player, roar.enemy,
    nil, "ROAR", true)
  check("Roar dragged the second foe out", roar.enemy, roarFoes[2])
  check("the bench mon lost its credit to Roar", roar.participants[1], nil)
  check("and the mon on the field keeps it", roar.participants[2], true)

  -- engine/battle/move_effects/baton_pass.asm:59.
  local baton, _, batonFoes = creditBattle()
  Battle.MOVE_EFFECTS.EFFECT_BATON_PASS(baton, baton.enemy)
  check("the baton passed to the second foe", baton.enemy, batonFoes[2])
  check("the bench mon lost its credit to the baton",
    baton.participants[1], nil)
  check("and the mon on the field keeps it", baton.participants[2], true)

  -- PassedBattleMonEntrance only adds (engine/battle/core.asm:5014): the
  -- player's own baton pass must NOT wipe the set.
  local playerBaton, playerBatonParty = creditBattle()
  Battle.MOVE_EFFECTS.EFFECT_BATON_PASS(playerBaton, playerBaton.player)
  check("the player's baton pass moved the lead back in",
    playerBaton.player, playerBatonParty[1])
  check("and credited both mons",
    playerBaton.participants[1] and playerBaton.participants[2], true)
end

-- Switching costs the turn and adds the newcomer to the participant set.
local switchParty = {
  Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect }),
  Mon.new(DATA, "TOTODILE", 10, { dvs = perfect }),
}
for _, mon in ipairs(switchParty) do
  mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
end
local switchBattle = Battle.new({
  data = DATA, party = switchParty,
  wild = (function()
    local m = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
    m.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    return m
  end)(),
  random = zeroRandom,
})
switchBattle:takeTurn({ kind = "switch", index = 2 })
check("switched active mon", switchBattle.player, switchParty[2])
check("both are participants",
  switchBattle.participants[1] and switchBattle.participants[2], true)
check("switch spent no PP", switchParty[2].moves[1].pp, 35)

-- ------------------------------------------------------------- move effects

local Effects = require("src.battle.gen2.Effects")

-- Stat stages clamp at +/-6 and report how far they actually moved, which is
-- what decides between "rose" and "sharply rose".
local stages = Battle.newStages()
check("one stage up", Effects.applyStage(stages, "attack", 1), 1)
check("two more", Effects.applyStage(stages, "attack", 2), 2)
check("stage total", stages.attack, 3)
Effects.applyStage(stages, "attack", 6)
check("clamped at +6", stages.attack, 6)
check("and refuses to go higher", Effects.applyStage(stages, "attack", 1), nil)
check("message names the stat", Effects.stageMessage("PIDGEY", "attack", 1),
  "PIDGEY's ATTACK rose!")
check("two stages are sharp",
  Effects.stageMessage("PIDGEY", "defense", -2),
  "PIDGEY's DEFENSE sharply fell!")

-- Recoil is a quarter of the damage dealt, drain half, both at least 1.
check("recoil quarter", Effects.recoilDamage(40), 10)
check("recoil floors at 1", Effects.recoilDamage(1), 1)
check("drain half", Effects.drainAmount(41), 20)

-- Rollout doubles per consecutive use and Defense Curl doubles it again; the
-- ramp caps after four doublings.
check("first rollout", Effects.rampedPower(30, 0), 30)
check("second", Effects.rampedPower(30, 1), 60)
check("fifth is capped", Effects.rampedPower(30, 9), 480)
check("curled doubles again", Effects.rampedPower(30, 0, true), 60)

-- Triple Kick climbs 10/20/30.
check("first kick", Effects.tripleKickPower(10, 1), 10)
check("third kick", Effects.tripleKickPower(10, 3), 30)

-- Fixed damage skips the formula: Seismic Toss is the user's level, Super
-- Fang half the target's current HP.
check("level damage", Effects.fixedDamage("EFFECT_LEVEL_DAMAGE",
  { level = 24 }, { hp = 90 }), 24)
check("super fang", Effects.fixedDamage("EFFECT_SUPER_FANG",
  { level = 24 }, { hp = 91 }), 45)
check("an unmodelled effect has no fixed damage",
  Effects.fixedDamage("EFFECT_NORMAL_HIT", { level = 5 }, { hp = 20 }), nil)

-- Substitute costs a quarter of max HP.
check("substitute cost", Effects.substituteCost(64), 16)

-- ------------------------------------------------- effects through the engine

local EFFECT_MOVES = {
  GROWL = { id = "GROWL", name = "GROWL", power = 0, type = "NORMAL",
    accuracy = 100, pp = 40, effect = "EFFECT_ATTACK_DOWN" },
  SWORDS_DANCE = { id = "SWORDS_DANCE", name = "SWORDSDANCE", power = 0,
    type = "NORMAL", accuracy = 100, pp = 30, effect = "EFFECT_ATTACK_UP_2" },
  DOUBLE_KICK = { id = "DOUBLE_KICK", name = "DOUBLEKICK", power = 30,
    type = "FIGHTING", accuracy = 100, pp = 30, effect = "EFFECT_DOUBLE_HIT" },
  TAKE_DOWN = { id = "TAKE_DOWN", name = "TAKE DOWN", power = 90,
    type = "NORMAL", accuracy = 85, pp = 20, effect = "EFFECT_RECOIL_HIT" },
  ABSORB = { id = "ABSORB", name = "ABSORB", power = 20, type = "GRASS",
    accuracy = 100, pp = 20, effect = "EFFECT_LEECH_HIT" },
  FLY = { id = "FLY", name = "FLY", power = 70, type = "FLYING",
    accuracy = 95, pp = 15, effect = "EFFECT_FLY" },
  SUBSTITUTE = { id = "SUBSTITUTE", name = "SUBSTITUTE", power = 0,
    type = "NORMAL", accuracy = 100, pp = 10, effect = "EFFECT_SUBSTITUTE" },
  SEISMIC_TOSS = { id = "SEISMIC_TOSS", name = "SEISMICTOSS", power = 1,
    type = "FIGHTING", accuracy = 100, pp = 20,
    effect = "EFFECT_LEVEL_DAMAGE" },
  -- EFFECT_STATIC_DAMAGE: Sonic Boom (20) and Dragon Rage (40).
  SONICBOOM = { id = "SONICBOOM", name = "SONICBOOM", power = 20,
    type = "NORMAL", accuracy = 90, pp = 20,
    effect = "EFFECT_STATIC_DAMAGE" },
  DRAGON_RAGE = { id = "DRAGON_RAGE", name = "DRAGON RAGE", power = 40,
    type = "DRAGON", accuracy = 100, pp = 10,
    effect = "EFFECT_STATIC_DAMAGE" },
  MAGNITUDE = { id = "MAGNITUDE", name = "MAGNITUDE", power = 1,
    type = "GROUND", accuracy = 100, pp = 30,
    effect = "EFFECT_MAGNITUDE" },
  LOCK_ON = { id = "LOCK_ON", name = "LOCK-ON", power = 0, type = "NORMAL",
    accuracy = 100, accuracyRaw = 0xff, pp = 5, effect = "EFFECT_LOCK_ON" },
  -- data/moves/moves.asm:169, :172, :151.
  EXPLOSION = { id = "EXPLOSION", name = "EXPLOSION", power = 250,
    type = "NORMAL", accuracy = 100, pp = 5,
    effect = "EFFECT_SELFDESTRUCT" },
  REST = { id = "REST", name = "REST", power = 0, type = "NORMAL",
    accuracy = 100, pp = 10, effect = "EFFECT_HEAL" },
  RECOVER = { id = "RECOVER", name = "RECOVER", power = 0, type = "NORMAL",
    accuracy = 100, pp = 20, effect = "EFFECT_HEAL" },
  PROTECT = { id = "PROTECT", name = "PROTECT", power = 0, type = "NORMAL",
    accuracy = 100, pp = 10, effect = "EFFECT_PROTECT" },
}
for id, def in pairs(EFFECT_MOVES) do MOVES[id] = def end

local function effectBattle(moveIds)
  local battle_, player_, wild_ = newBattle()
  player_.moves = {}
  for _, id in ipairs(moveIds) do
    player_.moves[#player_.moves + 1] = { id = id, pp = 10, maxPp = 10 }
  end
  return battle_, player_, wild_
end

-- A stat move moves the right side's stage and spends its PP.
local statBattle, statPlayer, statWild = effectBattle({ "GROWL" })
statBattle:takeTurn({ kind = "move", move = "GROWL" })
check("GROWL lowers the foe", statBattle.stages.enemy.attack, -1)
check("and not the user", statBattle.stages.player.attack, 0)

local upBattle = effectBattle({ "SWORDS_DANCE" })
upBattle:takeTurn({ kind = "move", move = "SWORDS_DANCE" })
check("SWORDS DANCE raises the user by two",
  upBattle.stages.player.attack, 2)

-- A double-hit move lands twice.
local hitBattle, _, hitWild = effectBattle({ "DOUBLE_KICK" })
local hitBefore = hitWild.hp
hitBattle:takeTurn({ kind = "move", move = "DOUBLE_KICK" })
check("double kick hit twice", (hitBefore - hitWild.hp) > 0, true)
check("hit count comes off the effect",
  Effects.hitCount("EFFECT_DOUBLE_HIT"), 2)

-- Recoil costs the user a quarter of what it dealt.
local recoilBattle, recoilPlayer, recoilWild = effectBattle({ "TAKE_DOWN" })
local recoilHp = recoilPlayer.hp
recoilBattle:takeTurn({ kind = "move", move = "TAKE_DOWN" })
check("recoil hurt the user", recoilPlayer.hp < recoilHp, true)

-- ANIM_x_DAMAGE is the MOVE's after-anim (effect_commands.asm:1963-1972), so
-- the emits the cart animates differently carry their own `anim`: none for
-- BattleCommand_Recoil (:5674-5687), ANIM_HIT_CONFUSION for a self-hit
-- (:624-632) and ANIM_BRN for the burn tick (core.asm:958-976).
do
local animBattle = effectBattle({ "TAKE_DOWN" })
local animEvents = animBattle:takeTurn({ kind = "move", move = "TAKE_DOWN" })
local hitAnim, recoilAnim, sawHit = "unset", "unset", false
for index, event in ipairs(animEvents) do
  if event.kind == "damage" and event.side == "enemy" and not sawHit then
    sawHit, hitAnim = true, event.anim
  end
  if event.kind == "message" and event.text
      and event.text:find("hit with recoil", 1, true) then
    recoilAnim = (animEvents[index - 1] or {}).anim
  end
end
check("the move's own hit keeps the after-anim", hitAnim, nil)
check("recoil plays nothing", recoilAnim, false)

local confBattle = effectBattle({ "TACKLE" })
confBattle:confusionSelfHit(confBattle.player)
local confAnim, confSide
for _, event in ipairs(confBattle:takeEvents()) do
  if event.kind == "damage" then
    confAnim, confSide = event.anim, event.animSide
  end
end
check("a confusion self-hit flickers instead", confAnim, "ANIM_HIT_CONFUSION")
check("...on its own side", confSide, "player")

local brnBattle = effectBattle({ "TACKLE" })
brnBattle.enemy.status = "burn"
local brnEvents = brnBattle:takeTurn({ kind = "move", move = "TACKLE" })
local brnAnim
for index, event in ipairs(brnEvents) do
  if event.kind == "message" and event.text
      and event.text:find("hurt by its burn", 1, true) then
    brnAnim = (brnEvents[index + 1] or {}).anim
  end
end
check("the burn tick plays its status anim", brnAnim, "ANIM_BRN")
end

-- Drain heals the user for half the damage.  Asserted off the heal event
-- rather than the net HP, since the foe's answering hit also moves the total.
local drainBattle, drainPlayer = effectBattle({ "ABSORB" })
drainPlayer.hp = 5
local drainEvents = drainBattle:takeTurn({ kind = "move", move = "ABSORB" })
local drainHealed = false
for _, event in ipairs(drainEvents) do
  if event.kind == "heal" and event.side == "player" then drainHealed = true end
end
check("absorb healed the user", drainHealed, true)

-- A charge move takes two turns and spends PP only on the first.
local flyBattle, flyPlayer, flyWild = effectBattle({ "FLY" })
local flyHp = flyWild.hp
flyBattle:takeTurn({ kind = "move", move = "FLY" })
check("turn one charges", flyPlayer.volatile.chargeMove, "FLY")
check("and deals nothing", flyWild.hp, flyHp)
check("PP spent once", flyPlayer.moves[1].pp, 9)
flyBattle:takeTurn({ kind = "move", move = "FLY" })
check("turn two lands", flyWild.hp < flyHp, true)
check("and charges no more", flyPlayer.volatile.chargeMove, nil)
check("with no second PP", flyPlayer.moves[1].pp, 9)

-- Substitute costs a quarter of max HP and then soaks the next hit.
local subBattle, subPlayer = effectBattle({ "SUBSTITUTE", "TACKLE" })
local subMax = subPlayer.maxHp or subPlayer.stats.hp
subBattle:takeTurn({ kind = "move", move = "SUBSTITUTE" })
check("substitute cost its quarter",
  subPlayer.hp, subMax - Effects.substituteCost(subMax))
-- The enemy attacked in the same turn, so the substitute is already down by
-- that hit -- which is the point: it is standing and the mon behind it is not
-- the one taking damage.
check("and stands", subPlayer.volatile.substitute > 0, true)
local behind = subPlayer.hp
subBattle:takeTurn({ kind = "move", move = "TACKLE" })
check("the substitute took the hit, not the mon", subPlayer.hp, behind)

-- BattleCommand_LockOn: the flag lands on the TARGET, and the next move aimed
-- at it skips the accuracy roll entirely and then clears the flag.  maxRandom
-- is the roll that misses everything, so a hit here can only be the lock-on.
-- Scoped, because the file is already close to Lua's 200-locals-per-function
-- ceiling and these fixtures are wanted nowhere else.
do
local function lockOnBattle()
  local battle_, player_, wild_ = newBattle({ random = maxRandom })
  player_.moves = {
    { id = "LOCK_ON", pp = 5, maxPp = 5 },
    { id = "TAKE_DOWN", pp = 20, maxPp = 20 },
  }
  return battle_, player_, wild_
end

local missBattle, _, missWild = lockOnBattle()
local missHp = missWild.hp
missBattle:takeTurn({ kind = "move", move = "TAKE_DOWN" })
check("an 85% move misses on the top roll", missWild.hp, missHp)

local lockBattle, _, lockWild = lockOnBattle()
lockBattle:takeTurn({ kind = "move", move = "LOCK_ON" })
check("Lock-On marks the target, not the user",
  lockBattle:volatile(lockWild).lockOn, true)
local lockHp = lockWild.hp
lockBattle:takeTurn({ kind = "move", move = "TAKE_DOWN" })
check("...and the next move cannot miss", lockWild.hp < lockHp, true)
check("...after which the flag is spent",
  lockBattle:volatile(lockWild).lockOn, nil)
end

-- Seismic Toss deals the user's level, whatever the type chart says.
local tossBattle, tossPlayer, tossWild = effectBattle({ "SEISMIC_TOSS" })
local tossBefore = tossWild.hp
tossBattle:takeTurn({ kind = "move", move = "SEISMIC_TOSS" })
check("seismic toss deals the level",
  tossBefore - tossWild.hp, tossPlayer.level)

-- EFFECT_STATIC_DAMAGE: Sonic Boom (20) and Dragon Rage (40).
-- Cart: constantdamage + resettypematchup (effects.asm StaticDamage).
do
  check("static damage uses move power",
    Effects.fixedDamage("EFFECT_STATIC_DAMAGE", { level = 10 }, { hp = 50 }, nil,
      40), 40)
  check("sonic boom fixed damage is 20",
    Effects.fixedDamage("EFFECT_STATIC_DAMAGE", { level = 10 }, { hp = 50 }, nil,
      20), 20)

  local boomBattle, _, boomWild = effectBattle({ "SONICBOOM" })
  boomWild.hp = 100
  boomWild.maxHp = 100
  local boomBefore = boomWild.hp
  boomBattle:takeTurn({ kind = "move", move = "SONICBOOM" })
  check("sonic boom deals flat 20", boomBefore - boomWild.hp, 20)

  -- Normal vs Ghost is 0x; StaticDamage's resettypematchup misses.
  local ghostBattle, _, ghostWild = effectBattle({ "SONICBOOM" })
  ghostWild.species = "GASTLY"
  local ghostBefore = ghostWild.hp
  ghostBattle:takeTurn({ kind = "move", move = "SONICBOOM" })
  check("sonic boom misses Ghost in Gen 2", ghostWild.hp, ghostBefore)

  local rageBattle, _, rageWild = effectBattle({ "DRAGON_RAGE" })
  rageWild.hp = 100
  rageWild.maxHp = 100
  local rageBefore = rageWild.hp
  rageBattle:takeTurn({ kind = "move", move = "DRAGON_RAGE" })
  check("dragon rage deals flat 40", rageBefore - rageWild.hp, 40)
end

-- Magnitude: BattleRandom walks magnitude_power.asm.  Nil random must not
-- collapse to roll 0 (always Magnitude 4); Battle.new always supplies a roller.
do
  local p4, n4 = Effects.magnitudePower(function() return 0 end)
  check("magnitude roll 0 is power 10", p4, 10)
  check("magnitude roll 0 is number 4", n4, 4)

  local p8, n8 = Effects.magnitudePower(function() return 200 end)
  check("magnitude roll 200 is power 90", p8, 90)
  check("magnitude roll 200 is number 8", n8, 8)

  local seen = {}
  for roll = 0, 255 do
    local _, number = Effects.magnitudePower(function() return roll end)
    seen[number] = true
  end
  for want = 4, 10 do
    check(("magnitude table reaches %d"):format(want), seen[want] == true, true)
  end

  -- Engine path: inject a mid-table roll and confirm the announce + damage.
  local magBattle, magPlayer, magWild = newBattle({
    random = function(n)
      -- Pin the getmagnitude byte: return 200 whenever n == 256.
      if n == 256 then return 200 end
      return 0
    end,
  })
  magPlayer.moves = { { id = "MAGNITUDE", pp = 30, maxPp = 30 } }
  magWild.hp = 200
  magWild.maxHp = 200
  local magEvents = magBattle:takeTurn({ kind = "move", move = "MAGNITUDE" })
  local announced
  for _, ev in ipairs(magEvents) do
    if ev.kind == "message" and type(ev.text) == "string"
        and ev.text:match("^Magnitude %d+") then
      announced = ev.text
      break
    end
  end
  check("magnitude announces rolled number", announced, "Magnitude 8!")
  check("magnitude deals more than power-1 would",
    magWild.hp < 200, true)
end

-- --------------------------------------------------------------- held items

local Ai = require("src.battle.gen2.Ai")

DATA.items = DATA.items or {}
DATA.items.LEFTOVERS = { id = "LEFTOVERS", name = "LEFTOVERS",
  heldEffect = "HELD_LEFTOVERS", heldParameter = 10 }
DATA.items.BERRY = { id = "BERRY", name = "BERRY",
  heldEffect = "HELD_BERRY", heldParameter = 10 }

-- Driven directly rather than through a turn: a turn also lets the enemy
-- attack, and what is under test here is the end-of-turn item step itself.
local itemBattle, itemPlayer = effectBattle({ "TACKLE" })
itemPlayer.item = "LEFTOVERS"
itemPlayer.hp = 5
itemBattle:tickHeldItem(itemPlayer)
check("leftovers healed at the end of the turn", itemPlayer.hp > 5, true)
check("and is not consumed", itemPlayer.item, "LEFTOVERS")
itemPlayer.hp = itemPlayer.maxHp or itemPlayer.stats.hp
itemBattle:tickHeldItem(itemPlayer)
check("a full mon gets nothing", itemPlayer.hp,
  itemPlayer.maxHp or itemPlayer.stats.hp)

local berryBattle, berryPlayer = effectBattle({ "TACKLE" })
berryPlayer.item = "BERRY"
berryPlayer.hp = 2
berryBattle:tickHeldItem(berryPlayer)
check("the berry was eaten", berryPlayer.item, nil)
check("and healed", berryPlayer.hp > 2, true)

-- ...but only below half.
local wholeBattle, wholePlayer = effectBattle({ "TACKLE" })
wholePlayer.item = "BERRY"
wholeBattle:tickHeldItem(wholePlayer)
check("a healthy mon keeps its berry", wholePlayer.item, "BERRY")

-- ------------------------------------------------------------------- AI

-- The AI word is bytes 4 and 5 of TrainerClassAttributes, little-endian.
check("flags come off the attributes",
  Ai.flagsOf({ 0, 0, 25, 211, 3, 68, 0, 0 }), 979)
check("a class with no attributes has no AI", Ai.flagsOf(nil), 0)
check("BASIC is bit 0", Ai.has(979, "BASIC"), true)
check("TYPES is bit 2", Ai.has(979, "TYPES"), false)
check("AGGRESSIVE is bit 6", Ai.has(979, "AGGRESSIVE"), true)

-- With AI_TYPES on, a move the target is immune to is dismissed and a
-- super-effective one is preferred.
local aiChoice = Ai.choose({
  moves = { { id = "THUNDERBOLT", pp = 10 }, { id = "WATER_GUN", pp = 10 } },
  moveDef = function(id)
    if id == "THUNDERBOLT" then
      return { id = id, power = 95, type = "ELECTRIC", effect = "EFFECT_NORMAL_HIT" }
    end
    return MOVES.WATER_GUN
  end,
  attacker = { level = 20, stats = { attack = 50, specialAttack = 50 },
    types = { "WATER" } },
  defender = { hp = 60, stats = { defense = 40, specialDefense = 40 },
    types = { "GROUND" } },
  typeChart = { types = TYPES, matchups = MATCHUPS },
  attackerStages = Battle.newStages(),
  defenderStages = Battle.newStages(),
  flags = Ai.FLAGS.TYPES,
  random = zeroRandom,
})
check("AI skips a move the target is immune to", aiChoice, "WATER_GUN")

-- With no flags at all it just picks, which is what a wild mon does.
check("no flags means no scoring", (Ai.choose({
  moves = { { id = "TACKLE", pp = 10 } },
  flags = 0, random = zeroRandom,
})), "TACKLE")


-- ---------------------------------------------------- the remaining effects
--
-- Every expectation below is a literal from engine/battle/move_effects/, so a
-- failure names the file it disagrees with.

local Effects = require("src.battle.gen2.Effects")

-- BattleCommand_StartRain: five turns, and data/battle/weather_modifiers.asm
-- is the whole of what weather does to damage.
-- MORE_EFFECTIVE is 15, not 20 (constants/battle_constants.asm:22): the
-- weather boost is a half again, and only the type chart doubles.
check("rain boosts Water by a half",
  Effects.weatherModifier("rain", "WATER"), 1.5)
check("rain halves Fire", Effects.weatherModifier("rain", "FIRE"), 0.5)
check("sun boosts Fire by a half", Effects.weatherModifier("sun", "FIRE"), 1.5)
check("sun halves Water", Effects.weatherModifier("sun", "WATER"), 0.5)
check("rain halves Solarbeam by EFFECT, not type",
  Effects.weatherModifier("rain", "GRASS", "EFFECT_SOLARBEAM"), 0.5)
check("sandstorm changes no damage",
  Effects.weatherModifier("sandstorm", "ROCK"), 1)
check("weather lasts five turns", Effects.WEATHER_TURNS, 5)

-- HandleWeather's .SandstormDamage: an eighth, and three types are immune.
check("sandstorm chips an eighth", Effects.sandstormDamage(64), 8)
check("Rock is immune", Effects.sandstormHits({ "ROCK" }), false)
check("Ground is immune", Effects.sandstormHits({ "NORMAL", "GROUND" }), false)
check("Steel is immune", Effects.sandstormHits({ "STEEL" }), false)
check("Flying is not", Effects.sandstormHits({ "NORMAL", "FLYING" }), true)

-- BattleCommand_TimeBasedHealContinue's .Multipliers ladder, walked by the
-- time of day and the weather (engine/battle/effect_commands.asm:6388-6454).
local DAY_F = Effects.SUN_HEAL.EFFECT_SYNTHESIS
check("Synthesis heals half in the day in clear weather",
  Effects.timeBasedHealFraction(nil, DAY_F, 1), 1 / 2)
check("...the lot in sun", Effects.timeBasedHealFraction("sun", DAY_F, 1), 1)
check("...a quarter in rain",
  Effects.timeBasedHealFraction("rain", DAY_F, 1), 1 / 4)
check("...a quarter at night in clear weather",
  Effects.timeBasedHealFraction(nil, DAY_F, 2), 1 / 4)
check("...a half at night in sun",
  Effects.timeBasedHealFraction("sun", DAY_F, 2), 1 / 2)
check("...an eighth at night in a sandstorm",
  Effects.timeBasedHealFraction("sandstorm", DAY_F, 2), 1 / 8)
check("Moonlight wants NITE instead",
  Effects.timeBasedHealFraction(nil, Effects.SUN_HEAL.EFFECT_MOONLIGHT, 2),
  1 / 2)
check("a battle with no clock still heals half",
  Effects.timeBasedHealFraction(nil, DAY_F, nil), 1 / 2)

-- ProtectChance halves for every consecutive use and gives up after eight.
check("first Protect always works", Effects.protectChance(0), 0xff)
check("the second is half as likely", Effects.protectChance(1), 0x7f)
check("the third a quarter", Effects.protectChance(2), 0x3f)
check("and the ninth never", Effects.protectChance(8), 0)
-- `.rand` compares the decremented byte against the threshold (protect.asm:50-57).
check("a 254 roll beats the first Protect",
  Effects.protectSucceeds(0, function() return 253 end), true)
check("...and loses the second",
  Effects.protectSucceeds(1, function() return 253 end), false)

-- BattleCommand_OHKO: no effect on a higher-level target, and the level gap
-- is worth two accuracy points each.
check("OHKO fails upward", Effects.ohkoAccuracy(30, 10, 20), nil)
check("OHKO gains 2 per level", Effects.ohkoAccuracy(30, 20, 10), 50)
check("...capped at 255", Effects.ohkoAccuracy(200, 100, 1), 255)

-- BattleCommand_StoreEnergy pays back double, capped at the 16-bit maximum.
check("Bide doubles what it took", Effects.bideDamage(50), 100)
check("...and caps", Effects.bideDamage(60000), 0xffff)

-- Beat Up counts only the healthy, unstatused party members.
local beatParty = {
  { species = "CYNDAQUIL", hp = 20 },
  { species = "PIDGEY", hp = 0 },
  { species = "RATTATA", hp = 15, status = "sleep" },
  { species = "SENTRET", hp = 9 },
}
check("Beat Up skips the fainted and the statused",
  #Effects.beatUpParty(beatParty, 1), 2)

-- Metronome never picks its own exception list.
check("Metronome cannot pick Metronome",
  Effects.METRONOME_EXCEPTIONS.METRONOME, true)
check("...nor Struggle", Effects.METRONOME_EXCEPTIONS.STRUGGLE, true)
local metroPick = Effects.metronomePick({ "METRONOME", "TACKLE" },
  { { id = "TACKLE" } }, function() return 0 end)
check("...nor a move the user already knows", metroPick, nil)
check("Metronome picks what is left",
  Effects.metronomePick({ "METRONOME", "EMBER" }, {},
    function(n) return n - 1 end), "EMBER")

-- ------------------------------------------------------- effects in a battle

local function effectBattle(moves, enemyMoves)
  local player = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
  player.moves = moves
  local wild = Mon.new(DATA, "PIDGEY", 20, { dvs = perfect })
  wild.moves = enemyMoves or { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local b = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = zeroRandom })
  return b, player, wild
end

-- Weather: set, ticked and ended by the turn loop, not by the move.
local rainBattle = effectBattle({
  { id = "RAIN_DANCE", pp = 5, maxPp = 5 },
  { id = "TACKLE", pp = 35, maxPp = 35 },
})
-- Both sides made unkillable, so the five turns below are five turns of
-- weather and not a faint cutting the end-of-turn block short.
rainBattle.enemy.hp, rainBattle.enemy.maxHp = 9999, 9999
rainBattle.player.hp, rainBattle.player.maxHp = 9999, 9999
rainBattle:takeTurn({ kind = "move", move = "RAIN_DANCE" })
check("Rain Dance sets the weather", rainBattle.weather, "rain")
check("...for four more turns", rainBattle.weatherTurns, 4)
-- Four ordinary turns run the counter out; casting it again would just reset
-- it to five, which is the point of testing with a different move.
for _ = 1, 4 do rainBattle:takeTurn({ kind = "move", move = "TACKLE" }) end
check("...and then it stops", rainBattle.weather, nil)

-- Spikes land on the side that will switch into them.
local spikeBattle = effectBattle({ { id = "SPIKES", pp = 20, maxPp = 20 } })
spikeBattle:takeTurn({ kind = "move", move = "SPIKES" })
check("Spikes land on the target's side", spikeBattle.spikes.enemy, true)
local spikeEvents = spikeBattle:takeTurn({ kind = "move", move = "SPIKES" })
local failed = false
for _, e in ipairs(spikeEvents) do
  if e.text == "But it failed!" then failed = true end
end
check("a second layer fails", failed, true)

-- Perish Song counts four turns on both sides and then faints them.
local perishBattle = effectBattle({ { id = "PERISH_SONG", pp = 5, maxPp = 5 } })
perishBattle:takeTurn({ kind = "move", move = "PERISH_SONG" })
check("Perish Song counts down on the user too",
  perishBattle:volatile(perishBattle.player).perish, 3)
check("...and on the target", perishBattle:volatile(perishBattle.enemy).perish, 3)

-- Substitute's own counter is not Perish Song's: an Endure leaves 1 HP.
local endureBattle = effectBattle({ { id = "ENDURE", pp = 10, maxPp = 10 } })
endureBattle:volatile(endureBattle.player).endure = true
endureBattle:dealDamage(endureBattle.enemy, endureBattle.player, 9999, {})
check("Endure leaves one hit point", endureBattle.player.hp, 1)

-- Rage raises Attack every time its user is hit.
local rageBattle = effectBattle({ { id = "RAGE", pp = 20, maxPp = 20 } })
rageBattle:volatile(rageBattle.player).rage = true
rageBattle:dealDamage(rageBattle.enemy, rageBattle.player, 1, {})
check("being hit while raging raises Attack",
  rageBattle.stages.player.attack, 1)

-- Disable and Encore both narrow what may be picked next turn.
local lockBattle = effectBattle({
  { id = "TACKLE", pp = 35, maxPp = 35 },
  { id = "EMBER", pp = 25, maxPp = 25 },
})
lockBattle:volatile(lockBattle.player).encore = "TACKLE"
check("an encored mon has one move", #lockBattle:usableMoves(lockBattle.player), 1)
lockBattle:volatile(lockBattle.player).encore = nil
lockBattle:volatile(lockBattle.player).disabled = "TACKLE"
check("a disabled move drops out",
  #lockBattle:usableMoves(lockBattle.player), 1)
check("...and it is the other one",
  lockBattle:usableMoves(lockBattle.player)[1].id, "EMBER")

-- Transform copies everything but HP.
local transformBattle = effectBattle({ { id = "TRANSFORM", pp = 10, maxPp = 10 } })
local playerMaxHp = transformBattle.player.maxHp
transformBattle:takeTurn({ kind = "move", move = "TRANSFORM" })
check("Transform takes the target's species",
  transformBattle.player.species, "PIDGEY")
-- Everything but HP is copied, which is why a Transformed mon keeps its own
-- hit points and takes the target's Attack.
check("...and keeps its own max HP", transformBattle.player.maxHp, playerMaxHp)
check("...but takes the target's Attack",
  transformBattle.player.stats.attack, transformBattle.enemy.stats.attack)
check("...and copies the moves at 5 PP",
  transformBattle.player.moves[1].pp, 5)

-- ------------------------------------------------------------- the AI layers

-- TrainerClassAttributes rows are SEVEN bytes, so the AI word is bytes 4-5 of
-- {item1, item2, money, aiLo, aiHi, switchLo, switchHi}.
local falkner = { 0, 0, 25, 0xd3, 0x03, 0x44, 0x00 }
check("Falkner's AI word", Ai.flagsOf(falkner), 0x03d3)
check("...includes SMART", Ai.has(Ai.flagsOf(falkner), "SMART"), true)
check("...and SETUP", Ai.has(Ai.flagsOf(falkner), "SETUP"), true)
check("Falkner switches sometimes",
  Ai.switchFlagsOf(falkner) % 8, Ai.SWITCH_FLAGS.SOMETIMES)

-- AI_Smart_Substitute: dismissed below half HP.
check("Smart drops Substitute when hurt",
  Ai.SMART.EFFECT_SUBSTITUTE({ random = zeroRandom },
    { enemyHp = 10, enemyMaxHp = 100 }), 10)
check("...and allows it at full",
  Ai.SMART.EFFECT_SUBSTITUTE({ random = zeroRandom },
    { enemyHp = 100, enemyMaxHp = 100 }), 0)

-- AI_Smart_Ohko: dismissed against a higher-level target.
check("Smart dismisses an OHKO it cannot land",
  Ai.SMART.EFFECT_OHKO({ random = zeroRandom },
    { playerLevel = 30, enemyLevel = 20 }), 10)

-- AI_Smart_BellyDrum: dismissed once Attack is already high.
check("Smart refuses a second Belly Drum",
  Ai.SMART.EFFECT_BELLY_DRUM({ random = zeroRandom },
    { stages = { attack = 3 } }), 5)

-- ------------------------------------------ AI_Smart, every effect handler
--
-- The layer's chance() is `(random(100) + 1) <= percent`, which is the cart's
-- `call Random / cp N percent / ret c`: the LOW roll is the one that returns
-- without scoring.  zeroRandom therefore takes every "ret c" and highRandom
-- takes none of them, so the two together walk both sides of every coin flip.
local function highRandom(n) return (n or 1) - 1 end
local lowRoll = { random = zeroRandom }
local highRoll = { random = highRandom }

-- AI_Smart_EffectHandlers, in the jumptable's own order (scoring.asm).  A name
-- in this list with no Ai.SMART entry is an effect the layer would silently
-- stop scoring, which never shows up as a crash in play.
local SMART_EFFECTS = {
  "EFFECT_SLEEP", "EFFECT_LEECH_HIT", "EFFECT_SELFDESTRUCT",
  "EFFECT_DREAM_EATER", "EFFECT_MIRROR_MOVE", "EFFECT_EVASION_UP",
  "EFFECT_ALWAYS_HIT", "EFFECT_ACCURACY_DOWN", "EFFECT_RESET_STATS",
  "EFFECT_BIDE", "EFFECT_FORCE_SWITCH", "EFFECT_HEAL", "EFFECT_TOXIC",
  "EFFECT_LIGHT_SCREEN", "EFFECT_OHKO", "EFFECT_RAZOR_WIND",
  "EFFECT_SUPER_FANG", "EFFECT_TRAP_TARGET", "EFFECT_UNUSED_2B",
  "EFFECT_CONFUSE", "EFFECT_SP_DEF_UP_2", "EFFECT_REFLECT", "EFFECT_PARALYZE",
  "EFFECT_SPEED_DOWN_HIT", "EFFECT_SUBSTITUTE", "EFFECT_HYPER_BEAM",
  "EFFECT_RAGE", "EFFECT_MIMIC", "EFFECT_LEECH_SEED", "EFFECT_DISABLE",
  "EFFECT_COUNTER", "EFFECT_ENCORE", "EFFECT_PAIN_SPLIT", "EFFECT_SNORE",
  "EFFECT_CONVERSION2", "EFFECT_LOCK_ON", "EFFECT_DEFROST_OPPONENT",
  "EFFECT_SLEEP_TALK", "EFFECT_DESTINY_BOND", "EFFECT_REVERSAL",
  "EFFECT_SPITE", "EFFECT_HEAL_BELL", "EFFECT_PRIORITY_HIT", "EFFECT_THIEF",
  "EFFECT_MEAN_LOOK", "EFFECT_NIGHTMARE", "EFFECT_FLAME_WHEEL", "EFFECT_CURSE",
  "EFFECT_PROTECT", "EFFECT_FORESIGHT", "EFFECT_PERISH_SONG",
  "EFFECT_SANDSTORM", "EFFECT_ENDURE", "EFFECT_ROLLOUT", "EFFECT_SWAGGER",
  "EFFECT_FURY_CUTTER", "EFFECT_ATTRACT", "EFFECT_SAFEGUARD",
  "EFFECT_MAGNITUDE", "EFFECT_BATON_PASS", "EFFECT_PURSUIT",
  "EFFECT_RAPID_SPIN", "EFFECT_MORNING_SUN", "EFFECT_SYNTHESIS",
  "EFFECT_MOONLIGHT", "EFFECT_HIDDEN_POWER", "EFFECT_RAIN_DANCE",
  "EFFECT_SUNNY_DAY", "EFFECT_BELLY_DRUM", "EFFECT_PSYCH_UP",
  "EFFECT_MIRROR_COAT", "EFFECT_SKULL_BASH", "EFFECT_TWISTER",
  "EFFECT_EARTHQUAKE", "EFFECT_FUTURE_SIGHT", "EFFECT_GUST", "EFFECT_STOMP",
  "EFFECT_SOLARBEAM", "EFFECT_THUNDER", "EFFECT_FLY",
}

check("the AI_Smart jumptable is 80 entries long", #SMART_EFFECTS, 80)
local smartMissing = {}
for _, name in ipairs(SMART_EFFECTS) do
  if type(Ai.SMART[name]) ~= "function" then
    smartMissing[#smartMissing + 1] = name
  end
end
check("...and every one of them has a handler",
  table.concat(smartMissing, ","), "")

-- Ai.choose adds the delta straight onto the score, so a handler that errors
-- or returns a nil on a state it cannot read would poison the whole pick.
local smartUnsafe = {}
for _, name in ipairs(SMART_EFFECTS) do
  local handler = Ai.SMART[name]
  if type(handler) == "function" then
    for _, roll in ipairs({ zeroRandom, highRandom }) do
      local ok, delta = pcall(handler, { random = roll }, {})
      if (not ok or type(delta) ~= "number")
          and smartUnsafe[#smartUnsafe] ~= name then
        smartUnsafe[#smartUnsafe + 1] = name
      end
    end
  end
end
check("every handler survives an empty state",
  table.concat(smartUnsafe, ","), "")

-- The cart bodies that carry more than one label share one Lua function, so
-- they cannot drift apart under a later edit.
check("Morning Sun is AI_Smart_Heal's body",
  Ai.SMART.EFFECT_MORNING_SUN, Ai.SMART.EFFECT_HEAL)
check("...and so is Synthesis",
  Ai.SMART.EFFECT_SYNTHESIS, Ai.SMART.EFFECT_HEAL)
check("...and Moonlight", Ai.SMART.EFFECT_MOONLIGHT, Ai.SMART.EFFECT_HEAL)
check("Unused2B is AI_Smart_RazorWind's body",
  Ai.SMART.EFFECT_UNUSED_2B, Ai.SMART.EFFECT_RAZOR_WIND)
check("Sleep Talk is AI_Smart_Snore's body",
  Ai.SMART.EFFECT_SLEEP_TALK, Ai.SMART.EFFECT_SNORE)
check("Destiny Bond is AI_Smart_Reversal's body",
  Ai.SMART.EFFECT_DESTINY_BOND, Ai.SMART.EFFECT_REVERSAL)
check("Baton Pass is AI_Smart_ForceSwitch's body",
  Ai.SMART.EFFECT_BATON_PASS, Ai.SMART.EFFECT_FORCE_SWITCH)
check("Earthquake is AI_Smart_Magnitude's body",
  Ai.SMART.EFFECT_EARTHQUAKE, Ai.SMART.EFFECT_MAGNITUDE)
check("Gust is AI_Smart_Twister's body",
  Ai.SMART.EFFECT_GUST, Ai.SMART.EFFECT_TWISTER)
check("Swagger is AI_Smart_Attract's body",
  Ai.SMART.EFFECT_SWAGGER, Ai.SMART.EFFECT_ATTRACT)

-- AI_Smart_Toxic / AI_Smart_LeechSeed: AICheckPlayerHalfHP sets carry when the
-- player is ABOVE half and the routine is `ret c`, so the discouragement lands
-- BELOW half, not above it.
check("Toxic is left alone against a healthy target",
  Ai.SMART.EFFECT_TOXIC(lowRoll, { playerHp = 60, playerMaxHp = 100 }), 0)
check("...and discouraged against a hurt one",
  Ai.SMART.EFFECT_TOXIC(lowRoll, { playerHp = 40, playerMaxHp = 100 }), 1)

-- AI_Smart_Selfdestruct: greatly discouraged above half, ignored at or below a
-- quarter, and 92% discouraged in between.
check("Selfdestruct is greatly discouraged at high HP",
  Ai.SMART.EFFECT_SELFDESTRUCT(lowRoll,
    { enemyHp = 60, enemyMaxHp = 100 }), 3)
check("...and left alone with nothing to lose",
  Ai.SMART.EFFECT_SELFDESTRUCT(lowRoll,
    { enemyHp = 20, enemyMaxHp = 100 }), 0)
check("...and discouraged again on the high roll in between",
  Ai.SMART.EFFECT_SELFDESTRUCT(highRoll,
    { enemyHp = 30, enemyMaxHp = 100 }), 3)
check("...but not on the low one",
  Ai.SMART.EFFECT_SELFDESTRUCT(lowRoll,
    { enemyHp = 30, enemyMaxHp = 100 }), 0)

-- AI_Smart_MirrorMove: dismissed from AHEAD with nothing to copy, because a
-- faster enemy moves first and would copy nothing.
check("Mirror Move is dismissed from ahead with nothing to copy",
  Ai.SMART.EFFECT_MIRROR_MOVE(lowRoll, { enemyFaster = true }), 10)
check("...and left alone from behind",
  Ai.SMART.EFFECT_MIRROR_MOVE(lowRoll, { enemyFaster = false }), 0)
check("...ignores a boring last move",
  Ai.SMART.EFFECT_MIRROR_MOVE(highRoll,
    { playerLastMove = "TACKLE", enemyFaster = true }), 0)
check("...and encourages a UsefulMoves entry twice from ahead",
  Ai.SMART.EFFECT_MIRROR_MOVE(highRoll,
    { playerLastMove = "SURF", enemyFaster = true }), -2)
check("...but only once from behind",
  Ai.SMART.EFFECT_MIRROR_MOVE(highRoll,
    { playerLastMove = "SURF", enemyFaster = false }), -1)

-- AI_Smart_AccuracyDown's `.hp_mismatch_2` falls INTO `.not_encouraged`, so the
-- +2 it just added can be cancelled by the Fury Cutter branch on the way out.
check("Accuracy Down cancels its own discouragement mid ramp",
  Ai.SMART.EFFECT_ACCURACY_DOWN(lowRoll,
    { playerHp = 10, playerMaxHp = 100, playerFuryCutter = 2 }), 0)
check("...and keeps it when nothing is ramping",
  Ai.SMART.EFFECT_ACCURACY_DOWN(lowRoll,
    { playerHp = 10, playerMaxHp = 100 }), 3)
check("...and greatly encourages against a poisoned full-HP target",
  Ai.SMART.EFFECT_ACCURACY_DOWN(lowRoll,
    { playerHp = 100, playerMaxHp = 100, enemyHp = 100, enemyMaxHp = 100,
      playerToxic = true }), -2)

-- AI_Smart_RazorWind's `.dismiss` is `add 6`, deliberately not
-- AIDiscourageMove's ten.
check("Razor Wind answers a shown Protect with six, not ten",
  Ai.SMART.EFFECT_RAZOR_WIND(lowRoll,
    { enemyHp = 100, enemyMaxHp = 100,
      playerUsedEffects = { EFFECT_PROTECT = true } }), 6)
check("...drops itself while perishing",
  Ai.SMART.EFFECT_RAZOR_WIND(lowRoll,
    { enemyPerishCount = 2, enemyHp = 100, enemyMaxHp = 100 }), 1)
check("...and says nothing from full health",
  Ai.SMART.EFFECT_RAZOR_WIND(lowRoll,
    { enemyHp = 100, enemyMaxHp = 100 }), 0)
check("...but discourages itself when hurt",
  Ai.SMART.EFFECT_RAZOR_WIND(highRoll,
    { enemyHp = 30, enemyMaxHp = 100 }), 1)

-- AI_Smart_Mimic: the three matchup bands, then the UsefulMoves tail.  The
-- `.dismiss` path falls through into `.discourage`, so a slower enemy with
-- nothing to copy scores +1 rather than nothing.
check("Mimic is dismissed from ahead with nothing to copy",
  Ai.SMART.EFFECT_MIMIC(lowRoll, { enemyFaster = true }), 10)
check("...and merely discouraged from behind",
  Ai.SMART.EFFECT_MIMIC(lowRoll, { enemyFaster = false }), 1)
check("...refuses to spend a turn while hurt",
  Ai.SMART.EFFECT_MIMIC(lowRoll,
    { playerLastMove = "SURF", enemyHp = 40, enemyMaxHp = 100 }), 1)
check("...discourages copying a resisted move",
  Ai.SMART.EFFECT_MIMIC(lowRoll,
    { playerLastMove = "SURF", enemyHp = 100, enemyMaxHp = 100,
      playerLastMoveMatchup = 5 }), 1)
check("...and stacks both encouragements on a useful super-effective one",
  Ai.SMART.EFFECT_MIMIC(highRoll,
    { playerLastMove = "SURF", enemyHp = 100, enemyMaxHp = 100,
      playerLastMoveMatchup = 20 }), -2)
check("...but says nothing about a neutral boring one",
  Ai.SMART.EFFECT_MIMIC(highRoll,
    { playerLastMove = "TACKLE", enemyHp = 100, enemyMaxHp = 100,
      playerLastMoveMatchup = 10 }), 0)

-- AI_Smart_Disable: only worth it from ahead, and the "does my own move have
-- power" bail-out never fires for a stock 0-power Disable.
check("Disable answers a useful move from ahead",
  Ai.SMART.EFFECT_DISABLE(highRoll,
    { enemyFaster = true, playerLastMove = "SURF" }), -1)
check("...falls through to the discourage on a boring one",
  Ai.SMART.EFFECT_DISABLE(highRoll,
    { enemyFaster = true, playerLastMove = "TACKLE" }), 1)
check("...unless the move being scored has power of its own",
  Ai.SMART.EFFECT_DISABLE(highRoll,
    { enemyFaster = true, playerLastMove = "TACKLE" }, 10, 40), 0)
check("...and skips straight to it from behind",
  Ai.SMART.EFFECT_DISABLE(highRoll,
    { enemyFaster = false, playerLastMove = "SURF" }), 1)

-- AI_Smart_Snore / AI_Smart_SleepTalk compare the counter against 1, so only
-- the LAST sleeping turn is discouraged.
check("Snore is greatly encouraged with sleep left",
  Ai.SMART.EFFECT_SNORE(lowRoll, { enemySleepTurns = 4 }), -3)
check("...and greatly discouraged on the waking turn",
  Ai.SMART.EFFECT_SNORE(lowRoll, { enemySleepTurns = 1 }), 3)

-- AI_Smart_Spite goes by the drained move's remaining PP.
check("Spite is dismissed from ahead with nothing to drain",
  Ai.SMART.EFFECT_SPITE(lowRoll, { enemyFaster = true }), 10)
check("...greatly encouraged against a nearly empty move",
  Ai.SMART.EFFECT_SPITE(highRoll,
    { playerLastMove = "SURF", playerLastMovePp = 3 }), -2)
check("...and discouraged against a full one",
  Ai.SMART.EFFECT_SPITE(highRoll,
    { playerLastMove = "SURF", playerLastMovePp = 20 }), 1)
check("...with no opinion when the move has left the list",
  Ai.SMART.EFFECT_SPITE(highRoll, { playerLastMove = "SURF" }), 0)

-- AI_Smart_HealBell: `.ok` is reached both by the `jr z` and by falling through
-- the `dec [hl]`, so sleep stacks on top of the first step of encouragement.
check("Heal Bell is dismissed with a clean party",
  Ai.SMART.EFFECT_HEAL_BELL(lowRoll, { enemyPartyStatus = false }), 10)
check("...but not while the active mon is statused",
  Ai.SMART.EFFECT_HEAL_BELL(lowRoll,
    { enemyPartyStatus = false, enemyStatus = "burn" }), 0)
check("...one step for a burn",
  Ai.SMART.EFFECT_HEAL_BELL(lowRoll,
    { enemyPartyStatus = true, enemyStatus = "burn" }), -1)
check("...and three for a sleep it cannot wait out",
  Ai.SMART.EFFECT_HEAL_BELL(highRoll,
    { enemyPartyStatus = true, enemyStatus = "sleep" }), -3)

-- AI_Smart_Curse splits on the ENEMY's own Ghost typing.
check("a Ghost Curse is dismissed when it would be suicide",
  Ai.SMART.EFFECT_CURSE(lowRoll,
    { enemyTypes = { "GHOST" }, enemyHp = 20, enemyMaxHp = 100 }), 10)
check("...and greatly encouraged against a fresh target",
  Ai.SMART.EFFECT_CURSE(highRoll,
    { enemyTypes = { "GHOST" }, enemyHp = 100, enemyMaxHp = 100,
      playerTurns = 0 }), -2)
check("...but not after the target has moved",
  Ai.SMART.EFFECT_CURSE(highRoll,
    { enemyTypes = { "GHOST" }, enemyHp = 100, enemyMaxHp = 100,
      playerTurns = 2 }), 0)
check("a physical Curse is greatly discouraged against a Ghost",
  Ai.SMART.EFFECT_CURSE(highRoll,
    { enemyTypes = { "NORMAL" }, enemyHp = 100, enemyMaxHp = 100,
      playerTypes = { "GHOST" } }), 2)
check("...and encouraged against something it can punch",
  Ai.SMART.EFFECT_CURSE(highRoll,
    { enemyTypes = { "NORMAL" }, enemyHp = 100, enemyMaxHp = 100,
      playerTypes = { "NORMAL" } }), -2)
check("...but not against a special attacker",
  Ai.SMART.EFFECT_CURSE(highRoll,
    { enemyTypes = { "NORMAL" }, enemyHp = 100, enemyMaxHp = 100,
      playerTypes = { "FIRE" }, playerSpecialType = true }), 0)

-- AI_Smart_MeanLook reads its OWN toxic bit, which is the cart's documented bug.
check("Mean Look is dismissed against the player's last mon",
  Ai.SMART.EFFECT_MEAN_LOOK(lowRoll,
    { enemyHp = 100, enemyMaxHp = 100, playerLastMon = true }), 10)
check("...and greatly encouraged when the AI itself is badly poisoned",
  Ai.SMART.EFFECT_MEAN_LOOK(highRoll,
    { enemyHp = 100, enemyMaxHp = 100, playerLastMon = false,
      enemyToxic = true }), -3)
check("...left alone when the player has nothing effective",
  Ai.SMART.EFFECT_MEAN_LOOK(highRoll,
    { enemyHp = 100, enemyMaxHp = 100, playerLastMon = false,
      playerMatchupScore = 11 }), 0)
check("...and discouraged when it does",
  Ai.SMART.EFFECT_MEAN_LOOK(highRoll,
    { enemyHp = 100, enemyMaxHp = 100, playerLastMon = false,
      playerMatchupScore = 10 }), 1)

-- AI_Smart_LockOn.  The dismissal of Lock-On itself is the declarative half;
-- the cross-move half is Ai.lockOnPostPass, checked below.
check("Lock-On is dismissed once it has already landed",
  Ai.SMART.EFFECT_LOCK_ON(lowRoll, { playerLockOn = true }), 10)
check("...discouraged when nearly dead",
  Ai.SMART.EFFECT_LOCK_ON(lowRoll, { enemyHp = 20, enemyMaxHp = 100 }), 1)
check("...greatly encouraged against a raised evasion",
  Ai.SMART.EFFECT_LOCK_ON(highRoll,
    { enemyHp = 100, enemyMaxHp = 100,
      playerStages = { evasion = 3 } }), -2)
check("...and discouraged when it has nothing shaky to aim",
  Ai.SMART.EFFECT_LOCK_ON(highRoll,
    { enemyHp = 100, enemyMaxHp = 100,
      enemyInaccurateEffectiveMove = false }), 1)
check("...but not when it does",
  Ai.SMART.EFFECT_LOCK_ON(highRoll,
    { enemyHp = 100, enemyMaxHp = 100,
      enemyInaccurateEffectiveMove = true }), 0)

-- `.player_locked_on`: with the lock-on up, every move under `71 percent - 1`
-- ($b4) raw accuracy is encouraged twice over, and everything at or above it
-- is left exactly where it was.  Scoped for the same reason as the Lock-On
-- engine fixtures above: locals are a finite resource in this file.
do
local LOCK_ON_DEFS = {
  { id = "LOCK_ON", effect = "EFFECT_LOCK_ON", accuracyRaw = 0xff },
  { id = "FISSURE", effect = "EFFECT_OHKO", accuracyRaw = 0x4c },
  { id = "TACKLE", effect = "EFFECT_NORMAL_HIT", accuracyRaw = 0xf0 },
}
local lockScores = Ai.lockOnPostPass({ 20, 20, 20 }, LOCK_ON_DEFS)
check("a shaky move is doubly encouraged once the lock-on is up",
  lockScores[2], 18)
check("...an accurate one is left alone", lockScores[3], 20)
-- The loop is the scoring layer's, so it runs once per Lock-On in the list.
check("...and Lock-On's own slot is above the threshold", lockScores[1], 20)
local twoLockOns = Ai.lockOnPostPass({ 20, 20 }, {
  { id = "LOCK_ON", effect = "EFFECT_LOCK_ON", accuracyRaw = 0xff },
  { id = "MIND_READER", effect = "EFFECT_LOCK_ON", accuracyRaw = 0x4c },
})
check("two Lock-Ons run the layer twice", twoLockOns[2], 16)
check("no Lock-On in the list means no post-pass",
  Ai.lockOnPostPass({ 20 }, { LOCK_ON_DEFS[2] })[1], 20)

-- And it is reached from Ai.choose, which is what makes it a scoring layer
-- rather than a model with no caller.
local lockChoice = Ai.choose({
  moves = { { id = "LOCK_ON", pp = 5 }, { id = "FISSURE", pp = 5 } },
  moveDef = function(id) return LOCK_ON_DEFS[id == "LOCK_ON" and 1 or 2] end,
  flags = Ai.FLAGS.SMART,
  smart = { playerLockOn = true, enemyHp = 100, enemyMaxHp = 100 },
  random = zeroRandom,
})
check("the AI aims its shaky move once the lock-on has landed",
  lockChoice, "FISSURE")
end

-- AI_Smart_PerishSong: nothing on the bench and the countdown kills the AI too.
check("Perish Song is worth five points of discouragement alone",
  Ai.SMART.EFFECT_PERISH_SONG(lowRoll, { enemyHasBench = false }), 5)
check("...is left alone while the AI is losing the matchup",
  Ai.SMART.EFFECT_PERISH_SONG(highRoll,
    { enemyHasBench = true, playerMatchupScore = 9 }), 0)
check("...and discouraged while it is winning",
  Ai.SMART.EFFECT_PERISH_SONG(highRoll,
    { enemyHasBench = true, playerMatchupScore = 10 }), 1)
check("...but encouraged against a player that cannot run",
  Ai.SMART.EFFECT_PERISH_SONG(highRoll,
    { enemyHasBench = true, playerTrapped = true }), -1)

-- AI_Smart_Magnitude / AI_Smart_Earthquake only ever fire off a shown Dig.
check("Magnitude ignores a player that has not dug",
  Ai.SMART.EFFECT_MAGNITUDE(highRoll, { playerLastMove = "TACKLE" }), 0)
check("...greatly encourages against a player underground",
  Ai.SMART.EFFECT_MAGNITUDE(lowRoll,
    { playerLastMove = "DIG", playerUnderground = true,
      enemyFaster = true }), -2)
check("...but not from behind",
  Ai.SMART.EFFECT_MAGNITUDE(lowRoll,
    { playerLastMove = "DIG", playerUnderground = true,
      enemyFaster = false }), 0)
check("...and predicts a second Dig only from behind",
  Ai.SMART.EFFECT_MAGNITUDE(highRoll,
    { playerLastMove = "DIG", enemyFaster = false }), -1)

-- AI_Smart_RainDance / AI_Smart_SunnyDay read the type slots IN ORDER, so a
-- swapped pair scores differently.
check("Rain Dance is greatly discouraged against a Water type",
  Ai.SMART.EFFECT_RAIN_DANCE(lowRoll, { playerTypes = { "WATER" } }), 3)
check("...and greatly encouraged against a Fire type",
  Ai.SMART.EFFECT_RAIN_DANCE(lowRoll,
    { playerTypes = { "FIRE" }, playerHp = 100, playerMaxHp = 100,
      playerTurns = 0 }), -2)
check("...with Water/Fire reading as bad",
  Ai.SMART.EFFECT_RAIN_DANCE(lowRoll,
    { playerTypes = { "WATER", "FIRE" }, playerHp = 100, playerMaxHp = 100,
      playerTurns = 0 }), 3)
check("...and Fire/Water as good",
  Ai.SMART.EFFECT_RAIN_DANCE(lowRoll,
    { playerTypes = { "FIRE", "WATER" }, playerHp = 100, playerMaxHp = 100,
      playerTurns = 0 }), -2)
check("...encouraged when the enemy has a RainDanceMoves entry",
  Ai.SMART.EFFECT_RAIN_DANCE(highRoll,
    { playerTypes = { "NORMAL" }, playerHp = 100, playerMaxHp = 100,
      enemyMoveIds = { SURF = true } }), -1)
check("...and greatly discouraged when it has none",
  Ai.SMART.EFFECT_RAIN_DANCE(highRoll,
    { playerTypes = { "NORMAL" }, playerHp = 100, playerMaxHp = 100,
      enemyMoveIds = { TACKLE = true } }), 3)

-- CART BUG, kept: SunnyDayMoves omits SOLARBEAM, so the AI never sets up the
-- sun for the one move that wants it most.
check("Sunny Day is not encouraged for Solar Beam",
  Ai.SMART.EFFECT_SUNNY_DAY(highRoll,
    { playerTypes = { "NORMAL" }, playerHp = 100, playerMaxHp = 100,
      enemyMoveIds = { SOLARBEAM = true } }), 3)
check("...but is for Flamethrower",
  Ai.SMART.EFFECT_SUNNY_DAY(highRoll,
    { playerTypes = { "NORMAL" }, playerHp = 100, playerMaxHp = 100,
      enemyMoveIds = { FLAMETHROWER = true } }), -1)

-- AI_Smart_HiddenPower scores the DV-derived type and power, not the move
-- table's Normal / 1 power stub.
check("Hidden Power is encouraged at full power and neutral",
  Ai.SMART.EFFECT_HIDDEN_POWER(lowRoll,
    { hiddenPowerPower = 70, hiddenPowerMatchup = 10 }), -1)
check("...and encouraged super-effective once past the power gate",
  Ai.SMART.EFFECT_HIDDEN_POWER(lowRoll,
    { hiddenPowerPower = 60, hiddenPowerMatchup = 20 }), -1)
check("...with the power gate tested FIRST, as the cart orders it",
  Ai.SMART.EFFECT_HIDDEN_POWER(lowRoll,
    { hiddenPowerPower = 31, hiddenPowerMatchup = 20 }), 1)
check("...discouraged under 50 power",
  Ai.SMART.EFFECT_HIDDEN_POWER(lowRoll,
    { hiddenPowerPower = 40, hiddenPowerMatchup = 10 }), 1)
check("...discouraged when resisted",
  Ai.SMART.EFFECT_HIDDEN_POWER(lowRoll,
    { hiddenPowerPower = 70, hiddenPowerMatchup = 5 }), 1)
check("...and neutral in between",
  Ai.SMART.EFFECT_HIDDEN_POWER(lowRoll,
    { hiddenPowerPower = 60, hiddenPowerMatchup = 10 }), 0)

-- AI_Smart_MirrorCoat is AI_Smart_Counter's routine with the type test flipped.
check("Mirror Coat is discouraged against an all-physical player",
  Ai.SMART.EFFECT_MIRROR_COAT(highRoll, { playerSpecialMoves = 0 }), 1)
check("...encouraged once three special moves have been shown",
  Ai.SMART.EFFECT_MIRROR_COAT(highRoll, { playerSpecialMoves = 3 }), -1)
check("...and on a single one only when the last move was special too",
  Ai.SMART.EFFECT_MIRROR_COAT(highRoll,
    { playerSpecialMoves = 1, playerLastMove = "SURF",
      playerLastMoveSpecial = true }, 10, 0, 90), -1)
check("...but not when the last move was physical",
  Ai.SMART.EFFECT_MIRROR_COAT(highRoll,
    { playerSpecialMoves = 1, playerLastMove = "TACKLE",
      playerLastMoveSpecial = false }, 10, 0, 40), 0)

-- AI_Smart_Twister / AI_Smart_Gust want SUBSTATUS_FLYING specifically, which is
-- why they read playerFlyingUp and not the combined playerFlying mask.
check("Gust greatly encourages against a player in the air",
  Ai.SMART.EFFECT_GUST(lowRoll,
    { playerLastMove = "FLY", playerFlyingUp = true, enemyFaster = true }), -2)
check("...ignores a player that never flew",
  Ai.SMART.EFFECT_GUST(lowRoll,
    { playerLastMove = "TACKLE", playerFlyingUp = true,
      enemyFaster = true }), 0)
check("...and predicts a second Fly only from behind",
  Ai.SMART.EFFECT_GUST(highRoll,
    { playerLastMove = "FLY", enemyFaster = false }), -1)

-- AI_Smart_Fly and AI_Smart_FutureSight both read the combined mask.
check("Fly is greatly encouraged against a vanished player from ahead",
  Ai.SMART.EFFECT_FLY(lowRoll,
    { playerFlying = true, enemyFaster = true }), -3)
check("...and says nothing from behind",
  Ai.SMART.EFFECT_FLY(lowRoll,
    { playerFlying = true, enemyFaster = false }), 0)
check("Future Sight lands as the player comes back down",
  Ai.SMART.EFFECT_FUTURE_SIGHT(lowRoll,
    { playerFlying = true, enemyFaster = true }), -2)

-- AI_Smart_Solarbeam and AI_Smart_Thunder are the only weather readers.
check("Solar Beam is greatly encouraged in the sun",
  Ai.SMART.EFFECT_SOLARBEAM(highRoll, { weather = "sun" }), -2)
check("...and greatly discouraged in the rain",
  Ai.SMART.EFFECT_SOLARBEAM(highRoll, { weather = "rain" }), 2)
check("...with no opinion in a sandstorm",
  Ai.SMART.EFFECT_SOLARBEAM(highRoll, { weather = "sandstorm" }), 0)
check("Thunder is discouraged in the sun",
  Ai.SMART.EFFECT_THUNDER(highRoll, { weather = "sun" }), 1)
check("...and says nothing in the rain, as the cart does",
  Ai.SMART.EFFECT_THUNDER(highRoll, { weather = "rain" }), 0)

-- AI_Smart_Sandstorm's `.greatly_discourage` falls into `.discourage`, hence +2.
check("Sandstorm is greatly discouraged against an immune type",
  Ai.SMART.EFFECT_SANDSTORM(lowRoll, { playerTypes = { "GROUND" } }), 2)
check("...including in the second slot",
  Ai.SMART.EFFECT_SANDSTORM(lowRoll, { playerTypes = { "FIRE", "ROCK" } }), 2)
check("...discouraged once the chip cannot decide the fight",
  Ai.SMART.EFFECT_SANDSTORM(lowRoll,
    { playerTypes = { "NORMAL" }, playerHp = 30, playerMaxHp = 100 }), 1)
check("...and encouraged against a healthy target",
  Ai.SMART.EFFECT_SANDSTORM(highRoll,
    { playerTypes = { "NORMAL" }, playerHp = 100, playerMaxHp = 100 }), -1)

-- The short ones, both branches each.
check("Thief is three dismissals", Ai.SMART.EFFECT_THIEF(lowRoll, {}), 30)
check("Bide wants full HP",
  Ai.SMART.EFFECT_BIDE(highRoll, { enemyHp = 40, enemyMaxHp = 100 }), 1)
check("...and says nothing at full",
  Ai.SMART.EFFECT_BIDE(highRoll, { enemyHp = 100, enemyMaxHp = 100 }), 0)
check("Super Fang wants something left to halve",
  Ai.SMART.EFFECT_SUPER_FANG(lowRoll,
    { playerHp = 20, playerMaxHp = 100 }), 1)
check("...and is happy at full",
  Ai.SMART.EFFECT_SUPER_FANG(lowRoll,
    { playerHp = 100, playerMaxHp = 100 }), 0)
check("Pain Split gives HP away against a hurt player",
  Ai.SMART.EFFECT_PAIN_SPLIT(lowRoll, { enemyHp = 10, playerHp = 100 }), 0)
check("...and is worth it when the AI is the hurt one",
  Ai.SMART.EFFECT_PAIN_SPLIT(lowRoll, { enemyHp = 60, playerHp = 100 }), 1)
check("Safeguard is discouraged against a dying target",
  Ai.SMART.EFFECT_SAFEGUARD(highRoll,
    { playerHp = 40, playerMaxHp = 100 }), 1)
check("...and left alone against a healthy one",
  Ai.SMART.EFFECT_SAFEGUARD(highRoll,
    { playerHp = 60, playerMaxHp = 100 }), 0)
check("Pursuit chases a target that is about to leave",
  Ai.SMART.EFFECT_PURSUIT(highRoll,
    { playerHp = 20, playerMaxHp = 100 }), -2)
check("...and is discouraged at full HP",
  Ai.SMART.EFFECT_PURSUIT(highRoll,
    { playerHp = 100, playerMaxHp = 100 }), 1)
check("Rapid Spin is only worth it with something to clear",
  Ai.SMART.EFFECT_RAPID_SPIN(highRoll, { enemySpikes = true }), -2)
check("...and says nothing on a clean field",
  Ai.SMART.EFFECT_RAPID_SPIN(highRoll, {}), 0)
check("Haze wants the board to have turned",
  Ai.SMART.EFFECT_RESET_STATS(highRoll, { stages = { attack = -3 } }), -1)
check("...and is discouraged on an even board",
  Ai.SMART.EFFECT_RESET_STATS(highRoll, {}), 1)
check("Amnesia wants a special attacker",
  Ai.SMART.EFFECT_SP_DEF_UP_2(highRoll,
    { enemyHp = 100, enemyMaxHp = 100, playerSpecialType = true }), -2)
check("...and stops at +4",
  Ai.SMART.EFFECT_SP_DEF_UP_2(highRoll,
    { enemyHp = 100, enemyMaxHp = 100, playerSpecialType = true,
      stages = { specialDefense = 4 } }), 1)
check("Foresight answers a Ghost",
  Ai.SMART.EFFECT_FORESIGHT(highRoll, { playerTypes = { "GHOST" } }), -2)
check("...and is discouraged otherwise",
  Ai.SMART.EFFECT_FORESIGHT(highRoll, { playerTypes = { "NORMAL" } }), 1)
check("Stomp waits for a Minimize",
  Ai.SMART.EFFECT_STOMP(highRoll, { playerMinimized = true }), -1)
check("...and is inert without one",
  Ai.SMART.EFFECT_STOMP(highRoll, {}), 0)
check("Flame Wheel thaws its own user",
  Ai.SMART.EFFECT_FLAME_WHEEL(lowRoll, { enemyStatus = "freeze" }), -5)
check("Defrost Opponent reads its OWN freeze, as the cart does",
  Ai.SMART.EFFECT_DEFROST_OPPONENT(lowRoll, { enemyStatus = "freeze" }), -3)
check("Psych Up is discouraged while the AI is the one set up",
  Ai.SMART.EFFECT_PSYCH_UP(highRoll,
    { stages = { attack = 2 }, playerStages = {} }), 1)
check("...and reaches no further than nothing, the cart's dead branch",
  Ai.SMART.EFFECT_PSYCH_UP(highRoll,
    { stages = {}, playerStages = { attack = 2 } }), 0)
check("Conversion2 discourages once the player HAS moved, the cart's bug",
  Ai.SMART.EFFECT_CONVERSION2(highRoll, { playerLastMove = "TACKLE" }), 1)
check("...and scores nothing on the turn-one garbage read",
  Ai.SMART.EFFECT_CONVERSION2(highRoll, {}), 0)
check("Trap Target locks down a poisoned player",
  Ai.SMART.EFFECT_TRAP_TARGET(highRoll,
    { playerToxic = true, enemyHp = 100, enemyMaxHp = 100 }), -2)
check("...and is discouraged once the trap is already running",
  Ai.SMART.EFFECT_TRAP_TARGET(highRoll,
    { playerTrapped = true, enemyHp = 100, enemyMaxHp = 100 }), 1)

-- AI_Smart_SpeedDownHit gates on MOVE_ANIM, so only Icy Wind reaches the body.
check("Icy Wind is greatly encouraged as an opener",
  Ai.SMART.EFFECT_SPEED_DOWN_HIT({ random = highRandom, moveId = "ICY_WIND" },
    { enemyHp = 100, enemyMaxHp = 100, playerTurns = 0,
      enemyFaster = false }), -2)
check("...and Bubble, which shares the effect, never is",
  Ai.SMART.EFFECT_SPEED_DOWN_HIT({ random = highRandom, moveId = "BUBBLE" },
    { enemyHp = 100, enemyMaxHp = 100, playerTurns = 0,
      enemyFaster = false }), 0)

-- ------------------------------------------------- the state the layer reads

-- HiddenPowerDamage takes the TOP bit of each DV for the power (not the low
-- bits the HP DV is built from) and the low two bits of Attack and Defense for
-- the type.
local hpBattle = newBattle()
local hpPower, hpType = hpBattle:hiddenPower({ dvs = perfect })
check("perfect DVs give Hidden Power its maximum", hpPower, 70)
check("...and its last type", hpType, "DARK")
local zeroPower, zeroType = hpBattle:hiddenPower({
  dvs = { attack = 0, defense = 0, speed = 0, special = 0 } })
check("blank DVs give the minimum", zeroPower, 31)
check("...and the first type", zeroType, "FIGHTING")
local lowPower, lowType = hpBattle:hiddenPower({
  dvs = { attack = 1, defense = 2, speed = 0, special = 3 } })
check("low DVs move the type without moving the power", lowPower, 32)
check("...to the (Atk & 3) * 4 + (Def & 3) slot", lowType, "GHOST")
check("a mon with no DVs has no Hidden Power",
  hpBattle:hiddenPower({}), nil)

-- Battle:smartAiState feeds the layer.  A wild battle is one mon a side, so
-- FindAliveEnemyMons and AICheckLastPlayerMon both come back empty-handed.
local aiState = hpBattle:smartAiState()
check("a lone wild mon has no bench", aiState.enemyHasBench, false)
check("...and the player's only mon is its last", aiState.playerLastMon, true)
check("an untouched board scores the matchup at the base",
  aiState.playerMatchupScore, Ai.BASE_SWITCH_SCORE)
check("an awake mon has no sleep counter", aiState.enemySleepTurns, 0)
check("the player's types arrive in slot order", aiState.playerTypes[1], "FIRE")
check("...and a Fire type reads as special", aiState.playerSpecialType, true)
check("the enemy's move ids are a set", aiState.enemyMoveIds.TACKLE, true)
check("Hidden Power rides along", aiState.hiddenPowerPower, 70)
check("nothing the port does not model is faked",
  aiState.playerMinimized == nil
    and aiState.playerTrapped == nil and aiState.conversion2Matchup == nil,
  true)
-- Lock-On IS modelled now, so the field is real: nil while the bit is down.
check("no lock-on means no flag", aiState.playerLockOn, nil)
hpBattle:volatile(hpBattle.player).lockOn = true
check("...and the enemy's own Lock-On shows through",
  hpBattle:smartAiState().playerLockOn, true)
hpBattle:volatile(hpBattle.player).lockOn = nil

-- One super-effective move shown by the player walks the matchup score down,
-- and both the switch layer and AI_Smart read that same number.
local matchupBattle = newBattle()
matchupBattle.player.moves = { { id = "WATER_GUN", pp = 25, maxPp = 25 } }
matchupBattle:volatile(matchupBattle.player).usedMoves = { "WATER_GUN" }
-- CheckPlayerMoveTypeMatchups reads the SPECIES types, so the swap has to go
-- through the species and not through the mon's own copy.
matchupBattle.enemy.species = "GEODUDE"
check("a shown super-effective move drops the matchup score",
  matchupBattle:playerMatchupScore(), Ai.BASE_SWITCH_SCORE - 1)
check("...and Whirlwind stops discouraging itself",
  Ai.SMART.EFFECT_FORCE_SWITCH(lowRoll,
    { playerMatchupScore = matchupBattle:playerMatchupScore() }), 0)

-- CheckAbleToSwitch: a perish count of one is the maximum urge to rotate.
local score, target = Ai.switchScore({
  bench = { { index = 2, healthy = true } },
  perishCount = 1,
})
check("Perish Song forces the switch score to its maximum", score, 0x30)
check("...and names a bench slot", target, 2)
check("no bench, no switch",
  (Ai.switchScore({ bench = {} })), 0)

-- AI_TryItem: healing only below half, and only for the highest-level mon.
check("the AI drinks a potion when it is hurt",
  Ai.chooseItem({ items = { "HYPER_POTION" }, isHighestLevel = true,
    hp = 20, maxHp = 100 }), "HYPER_POTION")
check("...but not at full health",
  Ai.chooseItem({ items = { "HYPER_POTION" }, isHighestLevel = true,
    hp = 100, maxHp = 100 }), nil)
check("...and never for a lower-level mon",
  Ai.chooseItem({ items = { "HYPER_POTION" }, isHighestLevel = false,
    hp = 20, maxHp = 100 }), nil)
check("FULL_HEAL wants a status",
  Ai.chooseItem({ items = { "FULL_HEAL" }, isHighestLevel = true,
    hp = 100, maxHp = 100, status = "sleep" }), "FULL_HEAL")

-- ------------------------------------------------ battle music and transition

local BattleMusic = require("src.battle.gen2.BattleMusic")
local Transition = require("src.ui.gen2.BattleTransition")

-- PlayBattleMusic (engine/battle/start_battle.asm).  LANDMARK indices are
-- constants.lua's landmarkOrder: New Bark is 1, Pallet Town 46, Victory Road 87.
check("a Johto wild battle by day",
  BattleMusic.battleSong({ landmark = 1, daytime = "DAY" }),
  "Music_JohtoWildBattle")
check("...and its own theme at night",
  BattleMusic.battleSong({ landmark = 1, daytime = "NITE" }),
  "Music_JohtoWildBattleNight")
check("a Kanto wild battle has no night variant",
  BattleMusic.battleSong({ landmark = 50, daytime = "NITE" }),
  "Music_KantoWildBattle")
check("Victory Road counts as Johto again",
  BattleMusic.battleSong({ landmark = 88, daytime = "DAY" }),
  "Music_JohtoWildBattle")
check("Falkner gets the Johto gym theme",
  BattleMusic.battleSong({ class = "FALKNER", landmark = 1 }),
  "Music_JohtoGymBattle")
check("Brock gets Kanto's",
  BattleMusic.battleSong({ class = "BROCK", landmark = 50 }),
  "Music_KantoGymBattle")
check("the Champion has her own",
  BattleMusic.battleSong({ class = "CHAMPION", landmark = 1 }),
  "Music_ChampionBattle")
check("a Rocket grunt gets the Rocket theme",
  BattleMusic.battleSong({ class = "GRUNTM", landmark = 1 }),
  "Music_RocketBattle")
-- The cart's own bug: only GRUNTM/GRUNTF are tested, so an EXECUTIVE fights to
-- the ordinary trainer theme.
check("...but an executive does not",
  BattleMusic.battleSong({ class = "EXECUTIVEM", landmark = 1 }),
  "Music_JohtoTrainerBattle")
check("a Kanto trainer gets Kanto's trainer theme",
  BattleMusic.battleSong({ class = "YOUNGSTER", landmark = 50 }),
  "Music_KantoTrainerBattle")

local RIVAL2_MEMBERS = {
  "RIVAL2_1_CHIKORITA", "RIVAL2_1_CYNDAQUIL", "RIVAL2_1_TOTODILE",
  "RIVAL2_2_CHIKORITA", "RIVAL2_2_CYNDAQUIL", "RIVAL2_2_TOTODILE",
}
check("RIVAL1 is always the rival theme",
  BattleMusic.battleSong({ class = "RIVAL1", landmark = 1 }),
  "Music_RivalBattle")
check("RIVAL2's first battle too",
  BattleMusic.battleSong({ class = "RIVAL2", member = "RIVAL2_1_TOTODILE",
    members = RIVAL2_MEMBERS, landmark = 80 }), "Music_RivalBattle")
check("...but from RIVAL2_2 on it is the Champion's",
  BattleMusic.battleSong({ class = "RIVAL2", member = "RIVAL2_2_CHIKORITA",
    members = RIVAL2_MEMBERS, landmark = 80 }), "Music_ChampionBattle")

check("a wild win plays the wild jingle",
  BattleMusic.victorySong({}), "Music_WildPokemonVictory")
-- PlayVictoryMusic's `.lost` path: no participant left standing means no
-- PlayMusic call at all.
check("...unless every participant fainted",
  BattleMusic.victorySong({ participantsFainted = true }), nil)
check("a gym leader's defeat plays the gym jingle",
  BattleMusic.victorySong({ class = "FALKNER" }), "Music_GymLeaderVictory")
check("and the Champion's does too (IsGymLeader lists her)",
  BattleMusic.victorySong({ class = "CHAMPION" }), "Music_GymLeaderVictory")
check("an ordinary trainer gets the trainer jingle",
  BattleMusic.victorySong({ class = "YOUNGSTER" }), "Music_TrainerVictory")

-- StartTrainerBattle_DetermineWhichAnimation's two bits.
check("outdoors against something weaker: the spin",
  Transition.pick({ environment = "TOWN", playerLevel = 12, enemyLevel = 4 }),
  "spin")
check("outdoors against something stronger: the speckle",
  Transition.pick({ environment = "ROUTE", playerLevel = 5, enemyLevel = 30 }),
  "speckle")
check("in a cave against something weaker: the sine wave",
  Transition.pick({ environment = "CAVE", playerLevel = 12, enemyLevel = 4 }),
  "sine")
check("in a cave against something stronger: the zoom",
  Transition.pick({ environment = "DUNGEON", playerLevel = 5, enemyLevel = 30 }),
  "zoom")
-- `ld a, [wBattleMonLevel] / add 3 / cp [hl] / jr nc, .not_stronger`: three
-- levels of slack, and the boundary belongs to the player.
check("three levels up is still not stronger",
  Transition.pick({ environment = "TOWN", playerLevel = 10, enemyLevel = 13 }),
  "spin")
check("four is",
  Transition.pick({ environment = "TOWN", playerLevel = 10, enemyLevel = 14 }),
  "speckle")

-- The flash table's extremes are solid black and solid white; the identity
-- row is no veil at all.
checkNear("3,3,3,3 is solid black",
  Transition.flashVeil({ 3, 3, 3, 3 }), 1, 0.001)
checkNear("0,0,0,0 is solid white",
  Transition.flashVeil({ 0, 0, 0, 0 }), -1, 0.001)
checkNear("3,2,1,0 is the identity",
  Transition.flashVeil({ 3, 2, 1, 0 }), 0, 0.001)
check("the flash runs 72 frames (12 palettes x 2 x 3 passes)",
  Transition.FLASH_FRAMES, 72)

-- The twenty spin steps must black out the whole 20x18 tilemap between them,
-- which is the point of the wedge table.
local spun = {}
for _, step in ipairs(Transition.SPIN_STEPS) do
  Transition.spinStep(spun, step)
end
local spunCount = 0
for _ in pairs(spun) do spunCount = spunCount + 1 end
check("the spin covers every tile", spunCount, 20 * 18)

-- The zoom's last box is the whole screen.
local zoomed = {}
for _, box in ipairs(Transition.ZOOM_BOXES) do
  Transition.zoomStep(zoomed, box)
end
local zoomCount = 0
for _ in pairs(zoomed) do zoomCount = zoomCount + 1 end
check("the zoom ends on the whole screen", zoomCount, 20 * 18)
check("...and starts on a 4x2 box in the middle", (function()
  local first = {}
  Transition.zoomStep(first, Transition.ZOOM_BOXES[1])
  local n = 0
  for _ in pairs(first) do n = n + 1 end
  return n
end)(), 8)

-- The Poke Ball is only stamped for a trainer, and it is 16 rows tall out of
-- hlcoord 2, 1.
local ball = Transition.pokeballCells()
-- 112 set bits across the sixteen bigdw rows of .PokeBallTransition.
check("the Poke Ball overlay is 112 tiles", #ball, 112)
check("...and every one of them is on screen", (function()
  for _, cell in ipairs(ball) do
    if cell[1] < 0 or cell[1] >= 20 or cell[2] < 0 or cell[2] >= 18 then
      return false
    end
  end
  return true
end)(), true)

-- The sine outro's amplitude grows by the frame index and stops at $60.
local sine = Transition.sineFrames()
check("the sine outro runs 15 frames", #sine, 15)
check("...starting flat", sine[1][0], 0)
check("...and ending well past a tile", math.abs(sine[#sine][8]) > 8, true)

-- ----------------------------------------------------------------- happiness
--
-- data/events/happiness_changes.asm event by event.  Every row is asserted at
-- all three tiers, because the tiers are the part a paraphrase gets wrong:
-- the three columns are NOT "small, smaller, smallest" -- the four penalties
-- get HARSHER in the third column while every bonus shrinks.

local Happiness = require("src.core.gen2.Happiness")

check("the enum is one based (HAPPINESS_GAINLEVEL is 01)",
  Happiness.EVENT.GAINLEVEL, 1)
check("...and its last row is HAPPINESS_GROOMING at 12",
  Happiness.EVENT.GROOMING, 18)
check("every HAPPINESS_* has a row", #Happiness.CHANGES,
  Happiness.NUM_EVENTS)
check("the last row did not fall off the end",
  Happiness.CHANGES[18] ~= nil, true)

-- HAPPINESS_THRESHOLD_1 is 100 and HAPPINESS_THRESHOLD_2 is 200, and the cart
-- compares with `cp` + `jr c`, so each boundary belongs to the tier ABOVE it.
check("99 is tier 1", Happiness.tier(99), 1)
check("100 is tier 2", Happiness.tier(100), 2)
check("199 is tier 2", Happiness.tier(199), 2)
check("200 is tier 3", Happiness.tier(200), 3)
check("0 is tier 1", Happiness.tier(0), 1)
check("255 is tier 3", Happiness.tier(255), 3)

-- The whole table, transcribed independently of the module so a typo in either
-- copy shows up as a disagreement rather than as agreement with itself.
local HAPPINESS_TABLE = {
  { "GAINLEVEL",          5,   3,   2 },
  { "USEDITEM",           5,   3,   2 },
  { "USEDXITEM",          1,   1,   0 },
  { "GYMBATTLE",          3,   2,   1 },
  { "LEARNMOVE",          1,   1,   0 },
  { "FAINTED",           -1,  -1,  -1 },
  { "POISONFAINT",       -5,  -5, -10 },
  { "BEATENBYSTRONGFOE", -5,  -5, -10 },
  { "OLDERCUT1",          1,   1,   1 },
  { "OLDERCUT2",          3,   3,   1 },
  { "OLDERCUT3",          5,   5,   2 },
  { "YOUNGCUT1",          1,   1,   1 },
  { "YOUNGCUT2",          3,   3,   1 },
  { "YOUNGCUT3",         10,  10,   4 },
  { "BITTERPOWDER",      -5,  -5, -10 },
  { "ENERGYROOT",       -10, -10, -15 },
  { "REVIVALHERB",      -15, -15, -20 },
  { "GROOMING",           3,   3,   1 },
}
-- One value per tier that is safely inside it, so `delta` reads the column and
-- not a boundary.
local TIER_SAMPLE = { 50, 150, 250 }
for index, row in ipairs(HAPPINESS_TABLE) do
  local name = row[1]
  check("HAPPINESS_" .. name .. " is row " .. index,
    Happiness.EVENT[name], index)
  for tier = 1, 3 do
    check(("HAPPINESS_%s tier %d"):format(name, tier),
      Happiness.delta(name, TIER_SAMPLE[tier]), row[tier + 1])
  end
end

-- The boundaries themselves, on the one row where all three columns differ.
check("GAINLEVEL at 99 still pays 5", Happiness.delta("GAINLEVEL", 99), 5)
check("GAINLEVEL at 100 drops to 3", Happiness.delta("GAINLEVEL", 100), 3)
check("GAINLEVEL at 199 still pays 3", Happiness.delta("GAINLEVEL", 199), 3)
check("GAINLEVEL at 200 drops to 2", Happiness.delta("GAINLEVEL", 200), 2)
-- ...and on the row where the third column is WORSE, not better.
check("POISONFAINT at 199 costs 5", Happiness.delta("POISONFAINT", 199), -5)
check("POISONFAINT at 200 costs 10", Happiness.delta("POISONFAINT", 200), -10)

-- Either spelling of the event resolves.
check("the full constant name resolves",
  Happiness.delta("HAPPINESS_GROOMING", 50), 3)
check("the raw index resolves", Happiness.delta(18, 50), 3)
check("an unknown event moves nothing", Happiness.delta("NOT_A_THING", 50), nil)

-- The carry clamps.  Both edges are reachable in play, so both are asserted on
-- a mon rather than on the table.
local happyMon = { happiness = 254 }
check("a bonus that overflows lands on 255",
  Happiness.change(happyMon, "YOUNGCUT3"), 255)
happyMon.happiness = 255
check("...and 255 does not wrap",
  Happiness.change(happyMon, "GROOMING"), 255)
local sadMon = { happiness = 3 }
check("a penalty that underflows lands on 0",
  Happiness.change(sadMon, "REVIVALHERB"), 0)
sadMon.happiness = 0
check("...and 0 does not wrap", Happiness.change(sadMon, "FAINTED"), 0)

-- ChangeHappiness reads the tier off the value BEFORE the change, so one call
-- can never straddle two columns.
local straddle = { happiness = 98 }
Happiness.change(straddle, "GAINLEVEL")
check("the tier is read before the step, not after", straddle.happiness, 103)

-- `cp EGG / ret z`: an egg's happiness byte is its hatch counter, and touching
-- it would hand the player a hatchling early.
local egg = { happiness = 40, isEgg = true }
check("an egg is refused", Happiness.change(egg, "GAINLEVEL"), nil)
check("...and its byte is untouched", egg.happiness, 40)

-- StepHappiness: called on the wrap of a 256-step counter, and only pays out
-- on every SECOND call, so the visible period is 512 footfalls.
local walker = { party = { { happiness = 100 }, { happiness = 100 } },
  stepCount = 0 }
check("the first step cycle pays nothing", Happiness.stepCycle(walker), false)
check("...and the party has not moved", walker.party[1].happiness, 100)
check("the second step cycle pays", Happiness.stepCycle(walker), true)
check("...one point, to every mon", walker.party[1].happiness, 101)
check("...including the last", walker.party[2].happiness, 101)
check("the third pays nothing again", Happiness.stepCycle(walker), false)

-- Walked for real through the counter Breeding.step owns: 512 footfalls, one
-- point.  Only the step that takes the counter back to 0 calls StepHappiness.
local Breeding = require("src.core.gen2.Breeding")
local hiker = { party = { { happiness = 70 } }, stepCount = 0 }
local paid = 0
for _ = 1, 1024 do
  Breeding.step(DATA, hiker)
  if Happiness.step(hiker) then paid = paid + 1 end
end
check("1024 steps pay exactly twice", paid, 2)
check("...for two points of happiness", hiker.party[1].happiness, 72)

-- An egg in the party is skipped by the walk as well.
local eggWalker = { party = { { happiness = 10, isEgg = true },
  { happiness = 10 } } }
Happiness.stepCycle(eggWalker)
Happiness.stepCycle(eggWalker)
check("the egg slot is skipped", eggWalker.party[1].happiness, 10)
check("...and the mon beside it is not", eggWalker.party[2].happiness, 11)

-- GetFirstPokemonHappiness skips leading eggs; the rater's two `ifless`
-- boundaries are 50 and 150.
local raterParty = { { happiness = 200, isEgg = true }, { happiness = 149 } }
local first, slot = Happiness.firstMon(raterParty)
check("the rater reads the first non-egg", first, raterParty[2])
check("...at its real slot", slot, 2)
check("49 is unhappy", Happiness.raterBand(49), "unhappy")
check("50 is kinda happy", Happiness.raterBand(50), "kinda")
check("149 is kinda happy", Happiness.raterBand(149), "kinda")
check("150 adores you", Happiness.raterBand(150), "happy")

-- BASE_HAPPINESS 70, FRIEND_BALL_HAPPINESS 200, HAPPINESS_TO_EVOLVE 220.
check("a new mon starts on BASE_HAPPINESS", Happiness.forNewMon(), 70)
check("a FRIEND BALL capture starts on 200",
  Happiness.forNewMon({ ball = "FRIEND_BALL" }), 200)
check("Mon.new agrees with BASE_HAPPINESS",
  Mon.new(DATA, "PIDGEY", 5, { dvs = perfect }).happiness, Happiness.BASE)
check("the evolution threshold is 220", Happiness.TO_EVOLVE, 220)

-- ------------------------------------------------- happiness inside a battle

-- The level-up award, from the exp path.  One call however many levels the
-- mon jumped, because ChangeHappiness sits outside the level loop.
local levelBattle, levelPlayer, levelWild = newBattle()
levelPlayer.happiness = 70
-- One point short of level 11, so the Pidgey's 39 exp carries it over.
levelPlayer.experience =
  Mon.experienceForLevel(GROWTH.GROWTH_MEDIUM_SLOW, 11) - 1
levelWild.hp = 1
levelBattle:takeTurn({ kind = "move", move = "TACKLE" })
check("the mon actually levelled", levelPlayer.level, 11)
check("a level up pays HAPPINESS_GAINLEVEL", levelPlayer.happiness, 75)

-- Exp that does not cross a level pays nothing.
local noLevelBattle, noLevelPlayer, noLevelWild = newBattle()
noLevelPlayer.happiness = 70
noLevelWild.hp = 1
noLevelBattle:takeTurn({ kind = "move", move = "TACKLE" })
check("exp without a level pays nothing", noLevelPlayer.happiness, 70)

-- A faint against an ordinary foe is HAPPINESS_FAINTED (-1); the same faint
-- against a foe thirty levels up is HAPPINESS_BEATENBYSTRONGFOE (-5).
local faintBattle, faintPlayer = newBattle()
faintPlayer.happiness = 70
faintBattle.player.hp = 0
faintBattle:resolveFaints()
check("a plain faint costs one point", faintPlayer.happiness, 69)

local stompBattle, stompPlayer = newBattle()
stompPlayer.happiness = 70
stompBattle.enemy.level = stompPlayer.level + 30
stompBattle.player.hp = 0
stompBattle:resolveFaints()
check("a much stronger foe costs five", stompPlayer.happiness, 65)

-- ...and one level short of thirty is still a plain faint (`jr c` keeps
-- HAPPINESS_FAINTED while the foe is BELOW yourLevel + 30).
local nearBattle, nearPlayer = newBattle()
nearPlayer.happiness = 70
nearBattle.enemy.level = nearPlayer.level + 29
nearBattle.player.hp = 0
nearBattle:resolveFaints()
check("twenty-nine levels up is still a plain faint", nearPlayer.happiness, 69)

-- IsGymLeader's list is one ROM array with the Kanto leaders falling through,
-- so all twenty-two classes match it while only eight match IsKantoGymLeader.
check("FALKNER is a gym leader", Battle.isGymLeader("FALKNER"), true)
check("BROCK is one too, through the fallthrough",
  Battle.isGymLeader("BROCK"), true)
check("so is RED", Battle.isGymLeader("RED"), true)
check("YOUNGSTER is not", Battle.isGymLeader("YOUNGSTER"), false)
check("BROCK is a KANTO gym leader", Battle.isKantoGymLeader("BROCK"), true)
check("FALKNER is not", Battle.isKantoGymLeader("FALKNER"), false)

-- The Gym Leader award lands at battle START, on every mon still standing.
local gymParty = {
  Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect }),
  Mon.new(DATA, "TOTODILE", 10, { dvs = perfect }),
  Mon.new(DATA, "PIDGEY", 10, { dvs = perfect }),
}
gymParty[1].happiness, gymParty[2].happiness = 70, 150
gymParty[3].happiness, gymParty[3].hp = 70, 0
Battle.new({
  data = DATA, party = gymParty,
  trainer = { class = "FALKNER", name = "FALKNER",
    party = { Mon.new(DATA, "PIDGEY", 9, { dvs = perfect }) } },
  random = zeroRandom,
})
check("a gym leader pays tier 1 three points", gymParty[1].happiness, 73)
check("...and tier 2 only two", gymParty[2].happiness, 152)
check("...and nothing to a fainted mon", gymParty[3].happiness, 70)

local nonGymParty = { Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect }) }
nonGymParty[1].happiness = 70
Battle.new({
  data = DATA, party = nonGymParty,
  trainer = { class = "YOUNGSTER", name = "JOEY",
    party = { Mon.new(DATA, "PIDGEY", 9, { dvs = perfect }) } },
  random = zeroRandom,
})
check("an ordinary trainer pays nothing", nonGymParty[1].happiness, 70)

-- XItemEffect awards to whoever is OUT, and only for the four X items.
local xBattle, xPlayer = newBattle()
xPlayer.happiness = 70
xBattle:takeTurn({ kind = "item", item = "X_ATTACK" })
check("an X item pays one point", xPlayer.happiness, 71)
xBattle.over = false
xBattle:takeTurn({ kind = "item", item = "POTION" })
check("a POTION pays nothing", xPlayer.happiness, 71)
-- The third tier pays zero, which is a real row and not a missing one.
check("an X item pays nothing at 200", Happiness.delta("USEDXITEM", 200), 0)

-- ---------------------------------------------------------------- fleeing
--
-- data/wild/flee_mons.asm through TryEnemyFlee.  AlwaysFleeMons short-circuits
-- before the random byte, which is why a roaming beast never gets a turn.

local Roamers = require("src.core.gen2.Roamers")

check("RAIKOU always flees", Roamers.ALWAYS_FLEE.RAIKOU, true)
check("ENTEI always flees", Roamers.ALWAYS_FLEE.ENTEI, true)
check("SUICUNE always flees", Roamers.ALWAYS_FLEE.SUICUNE, true)
check("CUBONE often flees", Roamers.OFTEN_FLEE.CUBONE, true)
check("MAGNEMITE sometimes flees", Roamers.SOMETIMES_FLEE.MAGNEMITE, true)
check("PIDGEY never flees", Roamers.SOMETIMES_FLEE.PIDGEY, nil)

local function fleeBattle(species, random)
  local runner = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  runner.species = species
  runner.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local mine = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  mine.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  return Battle.new({ data = DATA, party = { mine }, wild = runner,
    random = random or zeroRandom }), runner
end

-- maxRandom puts the byte at 255, past both thresholds, so ONLY the always
-- list can flee.
local alwaysB = fleeBattle("RAIKOU", maxRandom)
check("an always-flee mon goes before its own turn",
  alwaysB:tryEnemyFlee(), true)
check("...ending the battle", alwaysB.over, true)
check("...as a flee, not a win", alwaysB.outcome, "fled")

local oftenHigh = fleeBattle("CUBONE", maxRandom)
check("an often-flee mon stays on a high roll",
  oftenHigh:tryEnemyFlee(), false)
-- 127 is under 50 percent + 1 (128) but over 10 percent + 1 (26).
local oftenLow = fleeBattle("CUBONE", function() return 127 end)
check("...and goes at 127", oftenLow:tryEnemyFlee(), true)
local sometimesMid = fleeBattle("MAGNEMITE", function() return 127 end)
check("a sometimes-flee mon stays at 127", sometimesMid:tryEnemyFlee(), false)
local sometimesLow = fleeBattle("MAGNEMITE", function() return 25 end)
check("...and goes at 25", sometimesLow:tryEnemyFlee(), true)
local neverB = fleeBattle("PIDGEY", zeroRandom)
check("a mon on no list never goes", neverB:tryEnemyFlee(), false)

-- Frozen or asleep pins it, whatever the list says.
local frozen = fleeBattle("RAIKOU", zeroRandom)
frozen.enemy.status = "freeze"
check("a frozen beast cannot flee", frozen:tryEnemyFlee(), false)
frozen.enemy.status = "sleep"
check("nor can a sleeping one", frozen:tryEnemyFlee(), false)

-- A trainer's mon never flees, whatever it is.
local trainerRunner = Mon.new(DATA, "GEODUDE", 8, { dvs = perfect })
trainerRunner.species = "RAIKOU"
trainerRunner.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
local trainerFlee = Battle.new({
  data = DATA, party = { Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect }) },
  trainer = { class = "FALKNER", name = "FALKNER", party = { trainerRunner } },
  random = zeroRandom,
})
check("a trainer's mon never flees", trainerFlee:tryEnemyFlee(), false)

-- The flee lands inside a real turn: the beast goes before it ever attacks,
-- and the player's mon takes nothing.
local turnFlee, beast = fleeBattle("SUICUNE", zeroRandom)
beast.stats.speed = 999
local mineHp = turnFlee.player.hp
turnFlee:takeTurn({ kind = "move", move = "TACKLE" })
check("the beast fled inside the turn", turnFlee.outcome, "fled")
check("...before it could attack", turnFlee.player.hp, mineHp)

-- SpikesDamage runs on EVERY send-out (core.asm), so a trainer's faint
-- replacement walks into the layer its predecessor died on; a Flying-type
-- replacement still takes nothing.  (A closure, not a do-block: the main
-- chunk is at Lua 5.1's 200-local ceiling.)
;(function()
  local player = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local downed = Mon.new(DATA, "GEODUDE", 20, { dvs = perfect })
  local ground = Mon.new(DATA, "GEODUDE", 20, { dvs = perfect })
  local flyer = Mon.new(DATA, "PIDGEY", 20, { dvs = perfect })
  local b = Battle.new({ data = DATA, party = { player },
    trainer = { name = "TRAINER", party = { downed, ground, flyer } },
    random = zeroRandom })
  b.spikes.enemy = true
  downed.hp = 0
  b:resolveFaints()
  check("the faint replacement is sent in", b.enemy, ground)
  check("and Spikes hurt it on the way in",
    ground.hp, ground.maxHp - math.floor(ground.maxHp / 8))
  ground.hp = 0
  b:resolveFaints()
  check("a Flying replacement is sent in", b.enemy, flyer)
  check("and takes nothing from Spikes", flyer.hp, flyer.maxHp)
end)()

-- BattleCommand_Heal splits on the MOVE, not the effect: REST takes GetMaxHP
-- and writes REST_SLEEP_TURNS + 1 (effect_commands.asm:6007-6027, :6043).
;(function()
  local function healBattle(id, pp)
    local player = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
    player.moves = { { id = id, pp = pp, maxPp = pp } }
    local wild = Mon.new(DATA, "PIDGEY", 20, { dvs = perfect })
    wild.moves = { { id = "GROWL", pp = 40, maxPp = 40 } }
    local b = Battle.new({ data = DATA, party = { player }, wild = wild,
      random = zeroRandom })
    b:takeEvents()
    return b, player
  end
  local b, player = healBattle("REST", 10)
  player.hp = math.floor(player.maxHp / 2)
  player.status = "burn"
  b:takeTurn({ kind = "move", move = "REST" })
  check("Rest fills the bar", player.hp, player.maxHp)
  check("and puts the user to sleep", player.status, "sleep")
  check("for REST_SLEEP_TURNS + 1", player.statusTurns, 3)

  local b2, player2 = healBattle("RECOVER", 20)
  player2.hp = 1
  b2:takeTurn({ kind = "move", move = "RECOVER" })
  check("Recover heals a half", player2.hp,
    math.min(player2.maxHp, 1 + math.floor(player2.maxHp / 2)))
  check("and leaves the status alone", player2.status, nil)
end)()

-- ProtectChance rolls a real byte even when no random was injected
-- (engine/battle/move_effects/protect.asm:50-57).
;(function()
  local function said(events, text)
    for _, e in ipairs(events) do
      if e.kind == "message" and e.text == text then return true end
    end
    return false
  end
  local player = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
  player.moves = { { id = "PROTECT", pp = 10, maxPp = 10 },
    { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(DATA, "PIDGEY", 20, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  wild.hp, wild.maxHp = 9999, 9999
  local b = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = function(n) return n - 1 end })
  b:takeEvents()
  check("the first Protect holds",
    said(b:takeTurn({ kind = "move", move = "PROTECT" }),
      "CYNDAQUIL protected itself!"), true)
  -- A different move zeroes the count, so the next Protect is back to $ff.
  b:takeTurn({ kind = "move", move = "TACKLE" })
  check("an ordinary move resets the count",
    said(b:takeTurn({ kind = "move", move = "PROTECT" }),
      "CYNDAQUIL protected itself!"), true)
  check("and the consecutive one is refused on the halved odds",
    said(b:takeTurn({ kind = "move", move = "PROTECT" }),
      "But it failed!"), true)
end)()

-- BattleCommand_Selfdestruct zeroes the user's status and both HP bytes
-- (engine/battle/move_effects/selfdestruct.asm:6-12).
;(function()
  local player = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
  player.moves = { { id = "EXPLOSION", pp = 5, maxPp = 5 } }
  player.status = "burn"
  local wild = Mon.new(DATA, "PIDGEY", 20, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  wild.hp, wild.maxHp = 9999, 9999
  local b = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = zeroRandom })
  b:takeEvents()
  b:takeTurn({ kind = "move", move = "EXPLOSION" })
  check("Explosion faints its user", player.hp, 0)
  check("and clears the status byte with it", player.status, nil)
  check("while the target still takes the hit", wild.hp < wild.maxHp, true)
end)()

-- `srl c` in BattleCommand_DamageCalc (effect_commands.asm:2905-2913).
;(function()
  local opts = { level = 50, power = 250, moveType = "NORMAL",
    attacker = { attack = 100 }, defender = { defense = 100 },
    types = TYPES, matchups = MATCHUPS, variation = 100 }
  local plain = Damage.calc(opts)
  opts.defenseHalved = true
  check("halving the defence raises the damage", Damage.calc(opts) > plain,
    true)
end)()

-- CheckPlayerTurn refuses a move Disable landed on after the menu closed and
-- spends the turn (engine/battle/effect_commands.asm:314-326).
;(function()
  local function said(events, text)
    for _, e in ipairs(events) do
      if e.kind == "message" and e.text == text then return true end
    end
    return false
  end
  local player = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 },
    { id = "EMBER", pp = 25, maxPp = 25 } }
  local wild = Mon.new(DATA, "PIDGEY", 20, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  wild.hp, wild.maxHp = 9999, 9999
  local b = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = zeroRandom })
  b:takeEvents()
  b:volatile(player).disabled = "TACKLE"
  local events = b:takeTurn({ kind = "move", move = "TACKLE" })
  check("a disabled move is refused at execution",
    said(events, "CYNDAQUIL's TACKLE is DISABLED!"), true)
  check("and the turn is spent, not re-picked", player.moves[1].pp, 35)
  check("no other move is substituted", player.moves[2].pp, 25)
  -- MoveDisabled clears the charge so a disabled FLY cannot land (:599-603).
  b:volatile(player).chargeMove, b:volatile(player).vanished = "TACKLE", true
  b:takeTurn({ kind = "move", move = "TACKLE" })
  check("a disabled charge move fails", b:volatile(player).chargeMove, nil)
  check("and its user reappears", b:volatile(player).vanished, nil)
end)()

-- ------------------------------------------------------------------- Bide
--
-- data/moves/effects.asm:795-800 runs `storeenergy` ahead of `doturn`, and
-- BattleCommand_DoTurn's mask drops SUBSTATUS_BIDE outright
-- (engine/battle/effect_commands.asm:977-979), so the whole Bide costs the
-- one PP its opening turn spent.  The lock is ParsePlayerAction's own arm
-- (engine/battle/core.asm:569-576) for the player and CheckEnemyLockedIn
-- (:5650) for the foe.
;(function()
  local function said(events, text)
    for _, e in ipairs(events) do
      if e.kind == "message" and e.text == text then return true end
    end
    return false
  end
  local player = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
  player.moves = { { id = "BIDE", pp = 10, maxPp = 10 },
    { id = "TACKLE", pp = 35, maxPp = 35 } }
  player.hp, player.maxHp = 999, 999
  local wild = Mon.new(DATA, "PIDGEY", 20, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  wild.hp, wild.maxHp = 9999, 9999
  local b = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = zeroRandom })
  b:takeEvents()

  check("nothing forces the first BIDE", b:forcedMove(player), nil)
  b:useMove(player, wild, "BIDE")
  b:takeEvents()
  check("the opening turn spends one PP", player.moves[1].pp, 9)
  check("and the FIGHT menu is locked into it", b:forcedMove(player), "BIDE")
  check("with the move list narrowed to the one",
    #b:usableMoves(player), 1)

  -- BattleCommand_StoreEnergy banks wPlayerDamageTaken while the bit is up.
  b:dealDamage(wild, player, 5, {})
  b:takeEvents()
  b:useMove(player, wild, "BIDE")
  check("a storing turn spends no PP", player.moves[1].pp, 9)
  check("and stays locked", b:forcedMove(player), "BIDE")
  check("`.still_storing` prints rather than attacking",
    said(b:takeEvents(), "CYNDAQUIL is storing energy!"), true)

  -- A dry BIDE keeps running: the bide arm jumps past MoveSelectionScreen,
  -- where .CheckPlayerHasUsableMoves lives (engine/battle/core.asm:5058).
  player.moves[1].pp = 0
  check("a spent BIDE is still offered", #b:usableMoves(player), 1)
  check("...and it is the BIDE", b:usableMoves(player)[1].id, "BIDE")
  player.moves[1].pp = 9

  local hpBefore = wild.hp
  b:useMove(player, wild, "BIDE")
  b:takeEvents()
  check("the release spends no PP either", player.moves[1].pp, 9)
  check("UnleashEnergy pays back double", wild.hp, hpBefore - 10)
  check("and the lock is gone", b:forcedMove(player), nil)

  -- CheckEnemyLockedIn holds SUBSTATUS_BIDE, so the AI is never asked.
  local es = b:volatile(b.enemy)
  es.bideTurns, es.bideMove, es.bideStored = 2, "BIDE", 0
  check("a biding foe re-uses its Bide", b:enemyMove(), "BIDE")
  es.bideTurns, es.bideMove, es.bideStored = nil, nil, nil

  -- .reset_bide (engine/battle/core.asm:572-573, :627-629): the PACK cancels
  -- a Bide, a switch does not.
  b:useMove(player, wild, "BIDE")
  b:takeEvents()
  check("locked again", b:forcedMove(player), "BIDE")
  b:takeTurn({ kind = "item", item = "POTION" })
  b:takeEvents()
  check("using an item cancels the Bide", b:forcedMove(player), nil)
  check("and drops the bank", b:volatile(player).bideStored, nil)

  -- CantMove (engine/battle/effect_commands.asm:344-353) clears SUBSTATUS_BIDE
  -- on every arm that spends the turn, so a flinch ends the Bide.
  b:useMove(player, wild, "BIDE")
  b:takeEvents()
  check("locked once more", b:forcedMove(player), "BIDE")
  b:volatile(player).flinched = true
  check("a flinch spends the turn", b:canAct(player, "BIDE"), false)
  b:takeEvents()
  check("and CantMove ends the Bide", b:forcedMove(player), nil)
  check("bank dropped with it", b:volatile(player).bideStored, nil)

  -- .not_linked reads SUBSTATUS_ENCORED before CheckEnemyLockedIn
  -- (engine/battle/core.asm:5524-5533), so an encored foe obeys the Encore.
  es.bideTurns, es.bideMove, es.bideStored = 2, "BIDE", 0
  es.encore, es.encoreTurns = "TACKLE", 3
  check("Encore outranks the foe's Bide lock", b:enemyMove(), "TACKLE")
  es.encore, es.encoreTurns = nil, nil
  check("without it the Bide lock holds", b:enemyMove(), "BIDE")
  es.bideTurns, es.bideMove, es.bideStored = nil, nil, nil
end)()

-- --------------------------------------------------- Snore and Sleep Talk
--
-- `.fast_asleep` prints FastAsleepText and then falls into `.not_asleep` for
-- those two moves instead of `call CantMove / jp EndTurn`
-- (engine/battle/effect_commands.asm:188-200).  BattleCommand_SleepTalk opens
-- on ClearLastMove and ends in ResetTurn (move_effects/sleep_talk.asm:2, :61).
;(function()
  local function said(events, text)
    for _, e in ipairs(events) do
      if e.kind == "message" and e.text == text then return true end
    end
    return false
  end
  local function sleeper(moves)
    local player = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
    player.moves = moves
    player.hp, player.maxHp = 999, 999
    local wild = Mon.new(DATA, "PIDGEY", 20, { dvs = perfect })
    wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    wild.hp, wild.maxHp = 9999, 9999
    local b = Battle.new({ data = DATA, party = { player }, wild = wild,
      random = zeroRandom })
    b:takeEvents()
    return b, player, wild
  end

  local b, player, wild = sleeper({
    { id = "SLEEP_TALK", pp = 10, maxPp = 10 },
    { id = "TACKLE", pp = 35, maxPp = 35 } })

  player.status, player.statusTurns = "sleep", 3
  check("an ordinary move still loses the turn to sleep",
    b:canAct(player, "TACKLE"), false)
  check("and the counter was spent", player.statusTurns, 2)
  check("FastAsleepText still goes up",
    said(b:takeEvents(), "CYNDAQUIL is fast asleep!"), true)

  player.statusTurns = 3
  check("SLEEP TALK is let through", b:canAct(player, "SLEEP_TALK"), true)
  check("...and still spends its sleep turn", player.statusTurns, 2)
  check("...and still prints the line",
    said(b:takeEvents(), "CYNDAQUIL is fast asleep!"), true)
  player.statusTurns = 3
  check("SNORE is let through too", b:canAct(player, "SNORE"), true)
  b:takeEvents()

  -- The wake-up arm is not a bypass: it answers for the whole turn.
  player.statusTurns = 1
  check("the last sleep turn wakes up", b:canAct(player, "SLEEP_TALK"), true)
  check("and clears the status", player.status, nil)

  player.status, player.statusTurns = "sleep", 5
  local hpBefore = wild.hp
  b:useMove(player, wild, "SLEEP_TALK")
  b:takeEvents()
  check("SLEEP TALK pays its own PP through doturn", player.moves[1].pp, 9)
  check("but the move it calls pays none (ResetTurn)", player.moves[2].pp, 35)
  check("and that move really landed", wild.hp < hpBefore, true)
  check("ClearLastMove leaves no last move (used_move_text.asm:30-36)",
    b:volatile(player).lastMove, nil)

  -- .check_two_turn_move (sleep_talk.asm:117-141) drops the five charge
  -- effects and EFFECT_BIDE, so a mon with nothing else fails.
  local b2, player2, wild2 = sleeper({
    { id = "SLEEP_TALK", pp = 10, maxPp = 10 },
    { id = "SOLARBEAM", pp = 10, maxPp = 10 } })
  player2.status, player2.statusTurns = "sleep", 5
  b2:useMove(player2, wild2, "SLEEP_TALK")
  check("a two-turn move is never sampled",
    said(b2:takeEvents(), "But it failed!"), true)
  check("and nothing was called", b2:volatile(player2).chargeMove, nil)

  -- BattleCommand_SleepTalk's own `and SLP_MASK / jr z, .fail` (:16-19).
  local b3, player3, wild3 = sleeper({
    { id = "SLEEP_TALK", pp = 10, maxPp = 10 },
    { id = "TACKLE", pp = 35, maxPp = 35 } })
  b3:useMove(player3, wild3, "SLEEP_TALK")
  check("an awake SLEEP TALK fails",
    said(b3:takeEvents(), "But it failed!"), true)

  -- BattleCommand_Snore (move_effects/snore.asm:1-9) is the same refusal.
  local b4, player4, wild4 = sleeper({ { id = "SNORE", pp = 15, maxPp = 15 } })
  local snoreBefore = wild4.hp
  b4:useMove(player4, wild4, "SNORE")
  check("an awake SNORE fails", said(b4:takeEvents(), "But it failed!"), true)
  check("and deals nothing", wild4.hp, snoreBefore)
  player4.status, player4.statusTurns = "sleep", 5
  b4:useMove(player4, wild4, "SNORE")
  b4:takeEvents()
  check("a sleeping SNORE hits", wild4.hp < snoreBefore, true)
end)()

-- ------------------------------------------- fainted mons stop participating
--
-- UpdateFaintedPlayerMon RESET_FLAGs wBattleParticipantsNotFainted
-- (engine/battle/core.asm:2551-2556) and .EvenlyDivideExpAmongParticipants
-- divides by the count of set bits (:7118-7130), so the survivor of a lost
-- lead collects a whole share, not half of one.
;(function()
  local function twoMonBattle()
    local one = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
    one.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local two = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
    two.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local wild = Mon.new(DATA, "PIDGEY", 20, { dvs = perfect })
    wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local b = Battle.new({ data = DATA, party = { one, two }, wild = wild,
      random = zeroRandom })
    b:takeEvents()
    return b, one, two, wild
  end

  local b, one, two, wild = twoMonBattle()
  check("the lead starts as a participant", b.participants[1], true)
  one.hp = 0
  b:resolveFaints()
  b:takeEvents()
  check("a fainted participant drops out", b.participants[1], nil)

  -- The clear is one-shot: GiveExperiencePoints' `.done` falls through
  -- ResetBattleParticipants into AddBattleParticipant (:7116, :3033-3037) and
  -- puts the dead slot's bit back, and nothing takes it off again.
  local oneShot = twoMonBattle()
  oneShot.player.hp = 0
  oneShot:resolveFaints()
  oneShot:takeEvents()
  oneShot:resetParticipants()
  oneShot:resolveFaints()
  oneShot:takeEvents()
  check("and the cart's own re-add survives a second pass",
    oneShot.participants[1], true)

  b:switch(2)
  b:takeEvents()
  check("the replacement is a participant", b.participants[2], true)
  check("...and the fainted lead is not", b.participants[1], nil)
  local before = two.experience
  wild.hp = 0
  b:resolveFaints()
  b:takeEvents()
  local shared = two.experience - before

  -- The control: the same KO with the same mon as the only party member.
  local solo = Mon.new(DATA, "CYNDAQUIL", 20, { dvs = perfect })
  solo.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local soloWild = Mon.new(DATA, "PIDGEY", 20, { dvs = perfect })
  soloWild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local soloBattle = Battle.new({ data = DATA, party = { solo },
    wild = soloWild, random = zeroRandom })
  soloBattle:takeEvents()
  local soloBefore = solo.experience
  soloWild.hp = 0
  soloBattle:resolveFaints()
  soloBattle:takeEvents()
  check("the survivor gets a whole share, not half",
    shared, solo.experience - soloBefore)
  check("and the share is a real number", shared > 0, true)
end)()

print(("gen2 battle: %d checks, %d failures"):format(checks, failures))

-- Raise rather than os.exit: tests/run_tests.lua dofiles this file, so an
-- exit here takes the whole tier down with it and silently skips every
-- suite listed after this one (see tests/harness.lua's T.suite note).
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
