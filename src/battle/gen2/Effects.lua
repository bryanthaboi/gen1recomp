-- Gen 2 move effects, as data plus the small amount of arithmetic each one
-- needs.  Ported from engine/battle/effect_commands.asm; the battle engine
-- (src/battle/gen2/Battle.lua) owns the turn loop and calls in here for what a
-- move does beyond "roll damage, maybe inflict a status".
--
-- Everything is keyed by the move's *effect*, the same byte data/moves/moves.asm
-- stores, so a modded move that copies an effect inherits its behaviour -- and
-- an effect this table does not name still lands as an ordinary hit rather than
-- silently doing the wrong thing.
--
-- No love calls and no engine state: every function takes what it needs and
-- returns a value or a small table, which is what lets the tests drive them
-- directly.

local Strings = require("src.core.Strings")

local Effects = {}

-- --------------------------------------------------------------- stat stages
--
-- Stat changes come in four shapes and the effect name says which:
--   *_UP / *_UP_2      raise the user, by one stage or two
--   *_DOWN / *_DOWN_2  lower the target
--   *_UP_HIT           raise the user after a damaging hit
--   *_DOWN_HIT         lower the target after a damaging hit
-- StatUpMessage / StatDownMessage are the same either way, so the direction
-- and the target are the only things worth tabulating.

-- { stat, stages, target } where target is "self" or "foe".
Effects.STAT_CHANGES = {
  EFFECT_ATTACK_UP = { "attack", 1, "self" },
  EFFECT_DEFENSE_UP = { "defense", 1, "self" },
  EFFECT_SP_ATK_UP = { "specialAttack", 1, "self" },
  EFFECT_EVASION_UP = { "evasion", 1, "self" },
  EFFECT_ATTACK_UP_2 = { "attack", 2, "self" },
  EFFECT_DEFENSE_UP_2 = { "defense", 2, "self" },
  EFFECT_SPEED_UP_2 = { "speed", 2, "self" },
  EFFECT_SP_DEF_UP_2 = { "specialDefense", 2, "self" },
  -- Defense Curl also arms Rollout, which Battle tracks separately.
  EFFECT_DEFENSE_CURL = { "defense", 1, "self" },

  EFFECT_ATTACK_DOWN = { "attack", -1, "foe" },
  EFFECT_DEFENSE_DOWN = { "defense", -1, "foe" },
  EFFECT_SPEED_DOWN = { "speed", -1, "foe" },
  EFFECT_ACCURACY_DOWN = { "accuracy", -1, "foe" },
  EFFECT_EVASION_DOWN = { "evasion", -1, "foe" },
  EFFECT_ATTACK_DOWN_2 = { "attack", -2, "foe" },
  EFFECT_DEFENSE_DOWN_2 = { "defense", -2, "foe" },
  EFFECT_SPEED_DOWN_2 = { "speed", -2, "foe" },
}

-- pokegold data/moves/effects.asm:187-352, :1488, :2068
-- ../pokecrystal/data/moves/effects_pointers.asm, effects.asm
-- ../pokecrystal/engine/battle/effect_commands.asm:5448
Effects.NO_CHECKHIT = {
  EFFECT_MIRROR_MOVE = true,
  EFFECT_ATTACK_UP = true,
  EFFECT_DEFENSE_UP = true,
  EFFECT_SPEED_UP = true,
  EFFECT_SP_ATK_UP = true,
  EFFECT_SP_DEF_UP = true,
  EFFECT_ACCURACY_UP = true,
  EFFECT_EVASION_UP = true,
  EFFECT_RESET_STATS = true,
  EFFECT_CONVERSION = true,
  EFFECT_HEAL = true,
  EFFECT_LIGHT_SCREEN = true,
  EFFECT_MIST = true,
  EFFECT_FOCUS_ENERGY = true,
  EFFECT_ATTACK_UP_2 = true,
  EFFECT_DEFENSE_UP_2 = true,
  EFFECT_SPEED_UP_2 = true,
  EFFECT_SP_ATK_UP_2 = true,
  EFFECT_SP_DEF_UP_2 = true,
  EFFECT_ACCURACY_UP_2 = true,
  EFFECT_EVASION_UP_2 = true,
  EFFECT_TRANSFORM = true,
  EFFECT_REFLECT = true,
  EFFECT_SUBSTITUTE = true,
  EFFECT_METRONOME = true,
  EFFECT_SPLASH = true,
  EFFECT_COUNTER = true,
  EFFECT_SKETCH = true,
  EFFECT_DEFROST_OPPONENT = true,
  EFFECT_SLEEP_TALK = true,
  EFFECT_DESTINY_BOND = true,
  EFFECT_HEAL_BELL = true,
  EFFECT_MEAN_LOOK = true,
  EFFECT_NIGHTMARE = true,
  EFFECT_CURSE = true,
  EFFECT_PROTECT = true,
  EFFECT_SPIKES = true,
  EFFECT_PERISH_SONG = true,
  EFFECT_SANDSTORM = true,
  EFFECT_ENDURE = true,
  EFFECT_SAFEGUARD = true,
  EFFECT_BATON_PASS = true,
  EFFECT_MORNING_SUN = true,
  EFFECT_SYNTHESIS = true,
  EFFECT_MOONLIGHT = true,
  EFFECT_RAIN_DANCE = true,
  EFFECT_SUNNY_DAY = true,
  EFFECT_BELLY_DRUM = true,
  EFFECT_PSYCH_UP = true,
  EFFECT_MIRROR_COAT = true,
  EFFECT_TELEPORT = true,
  EFFECT_DEFENSE_CURL = true,
}

-- ../pokecrystal/engine/battle/effect_commands.asm:1947
-- ../pokecrystal/data/moves/effects.asm
Effects.AFTER_ANIM = {
  EFFECT_NORMAL_HIT = "damage",
  EFFECT_POISON_HIT = "damage",
  EFFECT_LEECH_HIT = "damage",
  EFFECT_BURN_HIT = "damage",
  EFFECT_FREEZE_HIT = "damage",
  EFFECT_PARALYZE_HIT = "damage",
  EFFECT_SELFDESTRUCT = "damage",
  EFFECT_DREAM_EATER = "damage",
  EFFECT_ALWAYS_HIT = "damage",
  EFFECT_BIDE = "damage",
  EFFECT_RAMPAGE = "damage",
  EFFECT_MULTI_HIT = "damage",
  EFFECT_FLINCH_HIT = "damage",
  EFFECT_PAY_DAY = "damage",
  EFFECT_TRI_ATTACK = "damage",
  EFFECT_UNUSED_25 = "damage",
  EFFECT_OHKO = "damage",
  EFFECT_RAZOR_WIND = "damage",
  EFFECT_SUPER_FANG = "damage",
  EFFECT_STATIC_DAMAGE = "damage",
  EFFECT_TRAP_TARGET = "damage",
  EFFECT_UNUSED_2B = "damage",
  EFFECT_DOUBLE_HIT = "damage",
  EFFECT_JUMP_KICK = "damage",
  EFFECT_RECOIL_HIT = "damage",
  EFFECT_ATTACK_DOWN_HIT = "damage",
  EFFECT_DEFENSE_DOWN_HIT = "damage",
  EFFECT_SPEED_DOWN_HIT = "damage",
  EFFECT_SP_ATK_DOWN_HIT = "damage",
  EFFECT_SP_DEF_DOWN_HIT = "damage",
  EFFECT_ACCURACY_DOWN_HIT = "damage",
  EFFECT_EVASION_DOWN_HIT = "damage",
  EFFECT_SKY_ATTACK = "damage",
  EFFECT_CONFUSE_HIT = "damage",
  EFFECT_POISON_MULTI_HIT = "damage",
  EFFECT_UNUSED_4E = "damage",
  EFFECT_HYPER_BEAM = "damage",
  EFFECT_RAGE = "damage",
  EFFECT_LEVEL_DAMAGE = "damage",
  EFFECT_PSYWAVE = "damage",
  EFFECT_COUNTER = "damage",
  EFFECT_SNORE = "damage",
  EFFECT_REVERSAL = "damage",
  EFFECT_FALSE_SWIPE = "damage",
  EFFECT_PRIORITY_HIT = "damage",
  EFFECT_TRIPLE_KICK = "damage",
  EFFECT_THIEF = "damage",
  EFFECT_FLAME_WHEEL = "damage",
  EFFECT_UNUSED_6E = "damage",
  EFFECT_ROLLOUT = "damage",
  EFFECT_FURY_CUTTER = "damage",
  EFFECT_RETURN = "damage",
  EFFECT_FRUSTRATION = "damage",
  EFFECT_SACRED_FIRE = "damage",
  EFFECT_MAGNITUDE = "damage",
  EFFECT_PURSUIT = "damage",
  EFFECT_RAPID_SPIN = "damage",
  EFFECT_UNUSED_82 = "damage",
  EFFECT_UNUSED_83 = "damage",
  EFFECT_HIDDEN_POWER = "damage",
  EFFECT_DEFENSE_UP_HIT = "damage",
  EFFECT_ATTACK_UP_HIT = "damage",
  EFFECT_ALL_UP_HIT = "damage",
  EFFECT_FAKE_OUT = "damage",
  EFFECT_MIRROR_COAT = "damage",
  EFFECT_SKULL_BASH = "damage",
  EFFECT_TWISTER = "damage",
  EFFECT_EARTHQUAKE = "damage",
  EFFECT_FUTURE_SIGHT = "damage",
  EFFECT_GUST = "damage",
  EFFECT_STOMP = "damage",
  EFFECT_SOLARBEAM = "damage",
  EFFECT_THUNDER = "damage",
  EFFECT_BEAT_UP = "damage",
  EFFECT_FLY = "damage",
  EFFECT_ATTACK_DOWN = "statdown",
  EFFECT_DEFENSE_DOWN = "statdown",
  EFFECT_SPEED_DOWN = "statdown",
  EFFECT_SP_ATK_DOWN = "statdown",
  EFFECT_SP_DEF_DOWN = "statdown",
  EFFECT_ACCURACY_DOWN = "statdown",
  EFFECT_EVASION_DOWN = "statdown",
  EFFECT_ATTACK_DOWN_2 = "statdown",
  EFFECT_DEFENSE_DOWN_2 = "statdown",
  EFFECT_SPEED_DOWN_2 = "statdown",
  EFFECT_SP_ATK_DOWN_2 = "statdown",
  EFFECT_SP_DEF_DOWN_2 = "statdown",
  EFFECT_ACCURACY_DOWN_2 = "statdown",
  EFFECT_EVASION_DOWN_2 = "statdown",
}

-- The secondary versions, rolled against the move's effect chance after a hit.
Effects.STAT_CHANGES_ON_HIT = {
  EFFECT_ATTACK_UP_HIT = { "attack", 1, "self" },
  EFFECT_DEFENSE_UP_HIT = { "defense", 1, "self" },
  EFFECT_ATTACK_DOWN_HIT = { "attack", -1, "foe" },
  EFFECT_DEFENSE_DOWN_HIT = { "defense", -1, "foe" },
  EFFECT_SPEED_DOWN_HIT = { "speed", -1, "foe" },
  EFFECT_ACCURACY_DOWN_HIT = { "accuracy", -1, "foe" },
  EFFECT_SP_DEF_DOWN_HIT = { "specialDefense", -1, "foe" },
}

-- Ancient Power raises every one of the user's stats at once.
Effects.ALL_UP_STATS = {
  "attack", "defense", "speed", "specialAttack", "specialDefense",
}

Effects.STAT_NAMES = {
  attack = Strings.source("ATTACK"), defense = Strings.source("DEFENSE"),
  speed = Strings.source("SPEED"),
  specialAttack = Strings.source("SPCL.ATK"),
  specialDefense = Strings.source("SPCL.DEF"),
  accuracy = Strings.source("ACCURACY"), evasion = Strings.source("EVASION"),
}

-- Stages clamp at ±6 (BattleCommand_StatUp's .CantRaise / .CantLower).
Effects.MAX_STAGE = 6

-- Applies a change and says what happened, so the caller can emit the cart's
-- own message: nil when the stage was already at the cap.
function Effects.applyStage(stages, stat, delta)
  if not (stages and stat) then return nil end
  local current = stages[stat] or 0
  local wanted = current + delta
  if wanted > Effects.MAX_STAGE then wanted = Effects.MAX_STAGE end
  if wanted < -Effects.MAX_STAGE then wanted = -Effects.MAX_STAGE end
  if wanted == current then return nil end
  stages[stat] = wanted
  return wanted - current
end

-- BattleCommand_StatUpMessage / StatDownMessage: one stage is "rose"/"fell",
-- two are "sharply rose" / "sharply fell".
function Effects.stageMessage(name, stat, applied)
  local label = Strings(Effects.STAT_NAMES[stat] or stat)
  if applied > 0 then
    if math.abs(applied) >= 2 then
      return Strings("%s's %s sharply rose!", name, label)
    end
    return Strings("%s's %s rose!", name, label)
  end
  if math.abs(applied) >= 2 then
    return Strings("%s's %s sharply fell!", name, label)
  end
  return Strings("%s's %s fell!", name, label)
end

-- ------------------------------------------------------------------ hit count
--
-- BattleCommand_CheckHit's multi-hit roll: 2 and 3 hits are 3/8 each, 4 and 5
-- are 1/8 each, which is what the `and 3` on a 0-3 roll plus the two-step
-- fallthrough in .DetermineNumberOfHits produces.
function Effects.multiHitCount(random)
  local function roll(n)
    if random then return random(n) end
    if love and love.math and love.math.random then
      return love.math.random(n) - 1
    end
    return math.random(n) - 1
  end
  -- engine/battle/effect_commands.asm:5228
  local first = roll(4)
  if first < 2 then return first + 2 end
  return roll(4) + 2
end

Effects.HIT_COUNTS = {
  EFFECT_DOUBLE_HIT = 2,
  EFFECT_POISON_MULTI_HIT = 2,
  -- Triple Kick stops early if a hit misses; Battle rolls that per hit.
  EFFECT_TRIPLE_KICK = 3,
}

function Effects.hitCount(effect, random)
  if effect == "EFFECT_MULTI_HIT" then
    return Effects.multiHitCount(random)
  end
  return Effects.HIT_COUNTS[effect] or 1
end

-- Triple Kick's power climbs 10/20/30 across its three kicks
-- (BattleCommand_TripleKick).
function Effects.tripleKickPower(base, hit)
  return (base or 10) * hit
end

-- ----------------------------------------------------------- recoil and drain

-- BattleCommand_Recoil: a quarter of the damage dealt, minimum 1.
function Effects.recoilDamage(damageDealt)
  return math.max(1, math.floor((damageDealt or 0) / 4))
end

-- BattleCommand_DrainTarget: half the damage dealt, minimum 1.
function Effects.drainAmount(damageDealt)
  return math.max(1, math.floor((damageDealt or 0) / 2))
end

Effects.DRAIN = {
  EFFECT_LEECH_HIT = true,
  EFFECT_DREAM_EATER = true,
}

-- --------------------------------------------------------------- two-turn
--
-- The charge moves all share BattleCommand_Charge: turn one prints a line and
-- stores the move, turn two attacks.  Fly and Dig also make the user
-- untargetable in between, which is the `semi-invulnerable` flag here.
Effects.CHARGE = {
  EFFECT_RAZOR_WIND = { text = Strings.source("%s made a whirlwind!") },
  EFFECT_SOLARBEAM = { text = Strings.source("%s took in sunlight!") },
  EFFECT_SKULL_BASH = { text = Strings.source("%s lowered its head!") },
  EFFECT_SKY_ATTACK = { text = Strings.source("%s is glowing!") },
  EFFECT_FLY = { text = Strings.source("%s flew up high!"), vanish = true },
}

-- CheckHit's .FlyDigMoves (effect_commands.asm:1713-1746): a vanished target
-- is not a flat miss, four moves reach it in the air and three underground.
Effects.FLY_DIG_EXCEPTIONS = {
  FLY = { GUST = true, WHIRLWIND = true, THUNDER = true, TWISTER = true },
  DIG = { EARTHQUAKE = true, FISSURE = true, MAGNITUDE = true },
}

-- Keyed by the charge move the target is partway through, which is what the
-- port carries in place of SUBSTATUS_FLYING / SUBSTATUS_UNDERGROUND.
function Effects.hitsVanished(chargeMove, moveId)
  local reaches = Effects.FLY_DIG_EXCEPTIONS[chargeMove]
  return (reaches and reaches[moveId]) and true or false
end

-- --------------------------------------------------------------- fixed damage

-- BattleCommand_ConstantDamage (engine/battle/effect_commands.asm:3131-3205),
-- one command for the whole SuperFang / Psywave / StaticDamage list.
function Effects.fixedDamage(effect, attacker, defender, random, power)
  if effect == "EFFECT_LEVEL_DAMAGE" then
    return math.max(1, attacker.level or 1)
  end
  if effect == "EFFECT_SUPER_FANG" then
    return math.max(1, math.floor((defender.hp or 1) / 2))
  end
  if effect == "EFFECT_PSYWAVE" then
    -- .psywave rerolls until the byte is nonzero AND below level * 1.5, so the
    -- top of the range is that ceiling minus one (effect_commands.asm:3163).
    local ceiling = math.max(2, math.floor((attacker.level or 1) * 3 / 2))
    return math.max(1, (random and random(ceiling - 1) or 0) + 1)
  end
  -- SONIC BOOM and DRAGON RAGE share EFFECT_STATIC_DAMAGE, whose arm reads
  -- BATTLE_VARS_MOVE_POWER straight into the damage word: their stored power
  -- (20 and 40) IS the damage, never a formula input
  -- (effect_commands.asm:3157-3161).
  if effect == "EFFECT_STATIC_DAMAGE" then
    return math.max(1, math.floor(power or 0))
  end
  return nil
end

-- --------------------------------------------------------------- Substitute

-- BattleCommand_Substitute: a quarter of max HP, which is also what the user
-- pays.  Refuses when the user has that much HP or less.
function Effects.substituteCost(maxHp)
  return math.max(1, math.floor((maxHp or 1) / 4))
end

-- ------------------------------------------------------------ counter moves

-- Counter answers physical damage, Mirror Coat special, both at double and
-- both only when the foe hit the user this turn (BattleCommand_Counter).
Effects.COUNTER = {
  EFFECT_COUNTER = "physical",
  EFFECT_MIRROR_COAT = "special",
}

function Effects.counterDamage(taken)
  return math.max(1, (taken or 0) * 2)
end

-- ------------------------------------------------------ rollout / fury cutter

-- Both double their power per consecutive use, Rollout for five turns and Fury
-- Cutter until it misses; the cart caps the doubling at 5 steps either way.
Effects.RAMPING = {
  EFFECT_ROLLOUT = 5,
  EFFECT_FURY_CUTTER = 5,
}

function Effects.rampedPower(base, count, curled)
  local steps = math.min(math.max(count or 0, 0), 4)
  local power = (base or 1) * 2 ^ steps
  -- Defense Curl doubles Rollout again (BattleCommand_RolloutPower).
  if curled then power = power * 2 end
  return math.floor(power)
end

-- ----------------------------------------------------------------- magnitude
--
-- data/moves/magnitude_power.asm, one row per magnitude: { chance, power,
-- magnitude number }.  The chance column is assembled through `percent`
-- (`* $ff / 100`, macros/data.asm:23), so `5 percent + 1` is 13 and
-- `100 percent` is 255 -- the thresholds below are those bytes, not the
-- percentages they were written as.
Effects.MAGNITUDE_POWER = {
  { 13, 10, 4 },
  { 38, 30, 5 },
  { 89, 50, 6 },
  { 166, 70, 7 },
  { 217, 90, 8 },
  { 242, 110, 9 },
  { 255, 150, 10 },
}

-- BattleCommand_GetMagnitude (engine/battle/move_effects/magnitude.asm): ONE
-- random byte walks the table and the first row whose threshold is not below
-- it wins (`ld a, [hli] / cp b / jr nc`).  The row's power goes into d, which
-- is what damagecalc reads as the move's power -- data/moves/moves.asm stores
-- MAGNITUDE at power 1 precisely because this overwrites it.  Returns the
-- power and the magnitude number the text prints.
--
-- `random` is BattleRandom (0..n-1).  If none is supplied, roll via love.math
-- / math.random -- never hard-code 0 (that always yields Magnitude 4).
function Effects.magnitudePower(random)
  local roll
  if type(random) == "function" then
    roll = random(256) or 0
  elseif love and love.math and love.math.random then
    roll = love.math.random(256) - 1
  else
    roll = math.random(256) - 1
  end
  for _, row in ipairs(Effects.MAGNITUDE_POWER) do
    if row[1] >= roll then return row[2], row[3] end
  end
  local last = Effects.MAGNITUDE_POWER[#Effects.MAGNITUDE_POWER]
  return last[2], last[3]
end

-- engine/battle/move_effects/return.asm:1-24, frustration.asm:1-25
function Effects.happinessPower(happiness, frustration)
  local h = happiness or 0
  if h < 0 then h = 0 elseif h > 255 then h = 255 end
  if frustration then h = 255 - h end
  return math.floor(h * 10 / 25)
end

-- ------------------------------------------------------------------- weather
--
-- BattleCommand_StartRain / StartSun / StartSandstorm all set wWeatherCount to
-- 5, which HandleWeather decrements at the end of every turn; the turn it
-- reaches zero the weather ends.  data/battle/weather_modifiers.asm is the
-- whole of what weather does to damage.

Effects.WEATHER = {
  EFFECT_RAIN_DANCE = "rain",
  EFFECT_SUNNY_DAY = "sun",
  EFFECT_SANDSTORM = "sandstorm",
}

Effects.WEATHER_TURNS = 5

Effects.WEATHER_START_TEXT = {
  rain = Strings.source("It started to rain!"),
  sun = Strings.source("The sunlight got bright!"),
  sandstorm = Strings.source("A sandstorm brewed!"),
}

Effects.WEATHER_TURN_TEXT = {
  rain = Strings.source("Rain continues to fall."),
  sun = Strings.source("The sunlight is strong."),
  sandstorm = Strings.source("The sandstorm rages."),
}

Effects.WEATHER_END_TEXT = {
  rain = Strings.source("The rain stopped."),
  sun = Strings.source("The sunlight faded."),
  sandstorm = Strings.source("The sandstorm subsided."),
}

-- data/battle/weather_modifiers.asm pairs each weather with MORE_EFFECTIVE or
-- NOT_VERY_EFFECTIVE, and those are 15 and 05 in tenths
-- (constants/battle_constants.asm:22, :24) -- MORE_EFFECTIVE is x1.5, NOT the
-- type chart's x2, which is SUPER_EFFECTIVE (20).  Gen 2's weather boost is a
-- half again, and only the type chart doubles.
Effects.WEATHER_TYPE_MODIFIERS = {
  rain = { WATER = 1.5, FIRE = 0.5 },
  sun = { FIRE = 1.5, WATER = 0.5 },
}

-- The one move whose EFFECT rather than type is modified: Solarbeam in rain.
Effects.WEATHER_MOVE_MODIFIERS = {
  rain = { EFFECT_SOLARBEAM = 0.5 },
}

function Effects.weatherModifier(weather, moveType, effect)
  if not weather then return 1 end
  local byType = Effects.WEATHER_TYPE_MODIFIERS[weather]
  if byType and byType[moveType] then return byType[moveType] end
  local byMove = Effects.WEATHER_MOVE_MODIFIERS[weather]
  if byMove and byMove[effect] then return byMove[effect] end
  return 1
end

-- HandleWeather's .SandstormDamage: an eighth of max HP, and Rock, Ground and
-- Steel are immune.  A mon underground (Dig) is skipped too.
Effects.SANDSTORM_IMMUNE = { ROCK = true, GROUND = true, STEEL = true }

function Effects.sandstormDamage(maxHp)
  return math.max(1, math.floor((maxHp or 8) / 8))
end

function Effects.sandstormHits(types)
  for _, type_ in ipairs(types or {}) do
    if Effects.SANDSTORM_IMMUNE[type_] then return false end
  end
  return true
end

-- BattleCommand_TimeBasedHealContinue's .Multipliers
-- (engine/battle/effect_commands.asm:6450-6454).
Effects.HEAL_MULTIPLIERS = { 1 / 8, 1 / 4, 1 / 2, 1 }

-- wTimeOfDay (constants/ram_constants.asm:134-139): MORN_F 0, DAY_F 1,
-- NITE_F 2, DARKNESS_F 3.
Effects.TIME_OF_DAY_ID = { MORN = 0, DAY = 1, NITE = 2, DARK = 3 }

-- Morning Sun / Synthesis / Moonlight and the wTimeOfDay each one wants
-- (engine/battle/effect_commands.asm:6362-6371).
Effects.SUN_HEAL = {
  EFFECT_MORNING_SUN = 0,
  EFFECT_SYNTHESIS = 1,
  EFFECT_MOONLIGHT = 2,
}

function Effects.timeOfDayIndex(timeOfDay)
  if type(timeOfDay) == "number" then return math.floor(timeOfDay) end
  return Effects.TIME_OF_DAY_ID[timeOfDay]
end

-- engine/battle/effect_commands.asm:6388-6417: the index opens at a half, the
-- wrong time of day steps it down, sun steps it up, rain and sandstorm down.
function Effects.timeBasedHealFraction(weather, wants, timeOfDay)
  local index = 3
  local now = Effects.timeOfDayIndex(timeOfDay)
  if wants ~= nil and now ~= nil and now ~= wants then index = index - 1 end
  if weather then
    index = index + 1
    if weather ~= "sun" then index = index - 2 end
  end
  return Effects.HEAL_MULTIPLIERS[math.max(1, math.min(4, index))]
end

-- ---------------------------------------------------------------- Perish Song
--
-- BattleCommand_PerishSong sets the counter to 4 on BOTH sides; it ticks down
-- at the end of every turn and the mon faints when it reaches 0.
Effects.PERISH_TURNS = 4

-- -------------------------------------------------------------------- Encore
--
-- 3-6 turns (`and $3` plus three increments), and the target is locked into
-- the move it last used.  Encore, Mirror Move and Struggle cannot be encored,
-- and neither can a move with no PP left.
Effects.ENCORE_BLOCKED = {
  ENCORE = true, MIRROR_MOVE = true, STRUGGLE = true,
}

function Effects.encoreTurns(random)
  return (random and random(4) or 0) + 3
end

-- ------------------------------------------------------------------- Disable
--
-- The count is a packed byte: the low nybble is the number of turns (1-8, the
-- `and 7` retried until nonzero, then incremented) and the high nybble is the
-- move slot plus one.  Only the turn count matters to the port, but the shape
-- is what says a slot of 0 means "nothing disabled".
function Effects.disableTurns(random)
  local roll = 0
  for _ = 1, 8 do
    roll = (random and random(8) or 1) % 8
    if roll ~= 0 then break end
  end
  if roll == 0 then roll = 1 end
  return roll + 1
end

-- --------------------------------------------------------- Protect and Endure
--
-- ProtectChance halves the success chance for every CONSECUTIVE use: the
-- threshold starts at $ff and is shifted right once per use, so use n
-- succeeds with probability (256 >> n) / 256.  Once the shift reaches zero the
-- move always fails, which is five uses.
function Effects.protectChance(consecutive)
  local threshold = 0xff
  for _ = 1, (consecutive or 0) do
    threshold = math.floor(threshold / 2)
    if threshold == 0 then return 0 end
  end
  return threshold
end

-- The roll is a non-zero byte, decremented, and the move succeeds when it is
-- BELOW the threshold.
function Effects.protectSucceeds(consecutive, random)
  local threshold = Effects.protectChance(consecutive)
  if threshold == 0 then return false end
  local roll = (random and random(255) or 0) + 1
  return (roll - 1) < threshold
end

-- ---------------------------------------------------------------------- Bide
--
-- BattleCommand_UnleashEnergy stores for 2 or 3 turns (`and 1` plus two
-- increments) and BattleCommand_StoreEnergy pays back DOUBLE everything the
-- user took while storing, capped at the 16-bit maximum.
function Effects.bideTurns(random)
  return (random and random(2) or 0) + 2
end

function Effects.bideDamage(stored)
  return math.min(0xffff, (stored or 0) * 2)
end

-- ---------------------------------------------------------------------- Rage
--
-- SUBSTATUS_RAGE: while it is set, every hit the user takes raises its Attack
-- one stage.  It is cleared by using any other move.

-- ---------------------------------------------------------------- Future Sight
--
-- Four turns: the damage is rolled NOW, stored, and lands when the counter
-- reaches one.  The move itself does nothing on the turn it is used.
Effects.FUTURE_SIGHT_TURNS = 4

-- ---------------------------------------------------------------------- OHKO
--
-- BattleCommand_OHKO fails outright when the target is the higher level; when
-- it is not, the move's accuracy becomes acc + 2 * (level difference), capped
-- at 255, and a hit sets damage to $ffff.
function Effects.ohkoAccuracy(baseAccuracy, userLevel, targetLevel)
  if (targetLevel or 1) > (userLevel or 1) then return nil end
  local bonus = ((userLevel or 1) - (targetLevel or 1)) * 2
  return math.min(255, (baseAccuracy or 0) + bonus)
end

-- ------------------------------------------------------------------- Beat Up
--
-- One hit per party member that is alive and free of any major status, each
-- swinging with that member's own base Attack and level against the target's
-- base Defense.  The move fails outright when nobody qualifies.
function Effects.beatUpParty(party, activeIndex)
  local hits = {}
  for index, mon in ipairs(party or {}) do
    local healthy = (mon.hp or 0) > 0
    -- The ACTIVE mon is checked against its battle status rather than its
    -- party record, which is the same thing here.
    local clean = not mon.status or (index == activeIndex and not mon.status)
    if healthy and clean then
      hits[#hits + 1] = { index = index, mon = mon }
    end
  end
  return hits
end

-- --------------------------------------------------------------- Baton Pass
--
-- ResetBatonPassStatus: what does NOT survive the switch.  Everything else --
-- the stat stages, Substitute, Leech Seed, Perish Song, the confusion counter
-- -- goes with the incoming mon, which is the whole point of the move.
--
-- `preTransform` is deliberately NOT on this list even though `transformed` is:
-- it is the passer's own identity waiting to be put back, and the drops run
-- BEFORE Battle:clearVolatile, which is what puts it back and clears both keys
-- (Battle:untransform).  Dropping it here would strand a passing DITTO as a
-- permanent copy instead.
Effects.BATON_PASS_DROPS = {
  "nightmare", "disable", "disableTurns", "attract", "transformed",
  "encore", "encoreTurns", "lastMove",
}

-- ------------------------------------------------------------------ Metronome
--
-- data/moves/metronome_exception_moves.asm: Metronome cannot pick these, and
-- it also never picks a move the user already knows.
Effects.METRONOME_EXCEPTIONS = {
  METRONOME = true, STRUGGLE = true, SKETCH = true, MIMIC = true,
  COUNTER = true, MIRROR_COAT = true, PROTECT = true, DETECT = true,
  ENDURE = true, DESTINY_BOND = true, SLEEP_TALK = true, THIEF = true,
}

-- Picks a move id uniformly out of `moveOrder`, rerolling on an excepted move
-- or one the user already has -- the same reject loop .GetMove runs.
function Effects.metronomePick(moveOrder, known, random)
  local count = #(moveOrder or {})
  if count == 0 then return nil end
  local owned = {}
  for _, move in ipairs(known or {}) do owned[move.id or move] = true end
  for _ = 1, 64 do
    local pick = moveOrder[(random and random(count) or 0) + 1]
    if pick and not Effects.METRONOME_EXCEPTIONS[pick] and not owned[pick] then
      return pick
    end
  end
  return nil
end

-- ---------------------------------------------------------------- Mirror Move
--
-- Copies the OPPONENT's last move, and fails when there is none or when the
-- user already knows it -- CheckUserMove returns "found", and Mirror Move
-- takes the .failed branch on a hit.

return Effects
