-- Gen 2 battle core: where the weather multiplier sits in the damage chain,
-- which failures suppress the attack animation, and the two move lock-ins
-- (Rollout and the EFFECT_RAMPAGE pair, Thrash and Petal Dance).
--
--   luajit tests/gen2_battle_lockin_test.lua
--
-- ROM-free.  Every expectation names the pokegold routine it asserts:
-- engine/battle/misc.asm DoWeatherModifiers, engine/battle/effect_commands.asm
-- BattleCommand_Stab / _MoveAnimNoSub / _CheckRampage / _Rampage / _StatDown /
-- _Poison, engine/battle/move_effects/rollout.asm and leech_seed.asm, and
-- engine/battle/core.asm CheckPlayerLockedIn.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle lock-in")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Damage = require("src.battle.gen2.Damage")
local Effects = require("src.battle.gen2.Effects")
local Mon = require("src.battle.gen2.Mon")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  GHOST = { id = "GHOST", index = 8, category = "physical" },
  ROCK = { id = "ROCK", index = 5, category = "physical" },
  GRASS = { id = "GRASS", index = 22, category = "special" },
  WATER = { id = "WATER", index = 21, category = "special" },
  POISON = { id = "POISON", index = 3, category = "physical" },
}

-- data/type_matchups.asm's own row: NORMAL does nothing at all to GHOST.
local MATCHUPS = {
  { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  ROLLOUT = { id = "ROLLOUT", name = "ROLLOUT", power = 30, type = "ROCK",
    accuracy = 90, accuracyRaw = 229, pp = 20, effect = "EFFECT_ROLLOUT" },
  THRASH = { id = "THRASH", name = "THRASH", power = 90, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 20, effect = "EFFECT_RAMPAGE" },
  LEECH_SEED = { id = "LEECH_SEED", name = "LEECH SEED", power = 0,
    type = "GRASS", accuracy = 90, accuracyRaw = 229, pp = 10, effect = "EFFECT_LEECH_SEED" },
  TOXIC = { id = "TOXIC", name = "TOXIC", power = 0, type = "POISON",
    accuracy = 85, accuracyRaw = 216, pp = 10, effect = "EFFECT_TOXIC" },
  POISONPOWDER = { id = "POISONPOWDER", name = "POISONPOWDER", power = 0,
    type = "GRASS", accuracy = 75, accuracyRaw = 191, pp = 35, effect = "EFFECT_POISON" },
  GROWL = { id = "GROWL", name = "GROWL", power = 0, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 40, effect = "EFFECT_ATTACK_DOWN" },
  -- An *_HIT twin: the drop rides a hit that already animated, so a refused
  -- drop must leave the move event unmarked (data/moves/effects.asm,
  -- AttackDownHit puts `attackdown` after `moveanim`).
  AURORA_BEAM = { id = "AURORA_BEAM", name = "AURORA BEAM", power = 65,
    type = "WATER", accuracy = 100, accuracyRaw = 255, pp = 20,
    effect = "EFFECT_ATTACK_DOWN_HIT", effectChance = 100, effectChanceRaw = 255 },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  MACHOP = {
    id = "MACHOP", index = 66, name = "MACHOP",
    baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  GASTLY = {
    id = "GASTLY", index = 92, name = "GASTLY",
    baseStats = { hp = 30, attack = 35, defense = 30, speed = 80,
      specialAttack = 100, specialDefense = 35 },
    types = { "GHOST", "GHOST" }, catchRate = 190, baseExp = 95,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  TANGELA = {
    id = "TANGELA", index = 114, name = "TANGELA",
    baseStats = { hp = 65, attack = 55, defense = 115, speed = 60,
      specialAttack = 100, specialDefense = 40 },
    types = { "GRASS", "GRASS" }, catchRate = 45, baseExp = 166,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = MATCHUPS },
  items = {},
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function rolls(queue, fill)
  local at = 0
  return function(n)
    at = at + 1
    local value = queue[at]
    if value == nil then value = fill or 0 end
    return value % math.max(1, n or 1)
  end
end

local function newBattle(opts)
  opts = opts or {}
  local player = Mon.new(DATA, opts.playerSpecies or "MACHOP",
    opts.playerLevel or 15, { dvs = perfect })
  player.moves = opts.playerMoves or { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(DATA, opts.wildSpecies or "MACHOP",
    opts.wildLevel or 15, { dvs = perfect })
  wild.moves = opts.wildMoves or { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = opts.random })
  return battle, player, wild
end

-- The screen animates off the move event and skips a marked one
-- (src/ui/gen2/BattleState.lua reads `event.missed`), so "did the attack
-- animation play" is exactly "is this flag nil".
local function moveEvent(events)
  for _, event in ipairs(events or {}) do
    if event.kind == "move" then return event end
  end
  return nil
end

local function findText(events, text)
  for _, event in ipairs(events or {}) do
    if event.kind == "message" and event.text == text then return true end
  end
  return false
end

-- ---- DoWeatherModifiers sits FIRST in BattleCommand_Stab -------------------
--
-- effect_commands.asm:1254 farcalls DoWeatherModifiers before DoBadgeTypeBoosts
-- (:1261), before the STAB x1.5 and before .TypesLoop (:1299), and long before
-- BattleCommand_DamageVariation.  Every one of those steps floors, so the
-- multiply has to land where the cart puts it, not on the finished number.
do
  -- data/battle/weather_modifiers.asm pairs rain with MORE_EFFECTIVE, and
  -- MORE_EFFECTIVE is 15, not 20 (constants/battle_constants.asm:22).
  eq(Effects.weatherModifier("rain", "WATER"), 1.5,
    "rain is MORE_EFFECTIVE (15), a half again -- not the chart's x2")
  eq(Effects.weatherModifier("sun", "WATER"), 0.5,
    "sun is NOT_VERY_EFFECTIVE (05) against Water")

  -- Chosen so the two orders disagree.  Base damage floors to 1, the tail
  -- adds MIN_DAMAGE for 3, and the mon is Water so STAB applies:
  --   cart: 3 -> weather 4 -> STAB 6 -> variation 85% -> 5
  --   port's old order: 3 -> STAB 4 -> variation 85% -> 3 -> weather -> 4
  local opts = {
    level = 5, power = 20, moveType = "WATER",
    attacker = { attack = 10, specialAttack = 10, types = { "WATER" },
      stages = {} },
    defender = { defense = 10, specialDefense = 10, types = {}, stages = {} },
    types = TYPES, matchups = {}, variation = 217,
  }
  opts.weatherPercent = nil
  local clear = Damage.calc(opts)
  opts.weatherPercent = 15
  local rain = Damage.calc(opts)
  eq(clear, 3, "clear weather: the plain chain")
  eq(rain, 5, "rain multiplies ahead of STAB and DamageVariation")
  check(rain ~= 4,
    "and not on the finished number, which would have floored to 4")

  -- The .ApplyModifier zero-quotient arm forces the result back to 1, so a
  -- halved hit never falls to nothing (misc.asm:129-136).
  opts.weatherPercent = 5
  opts.variation = 255
  local weak = Damage.calc(opts)
  check(weak >= 1, "a weather-halved hit still deals at least 1")
end

-- ---- immunity suppresses the animation -----------------------------------
--
-- BattleCommand_Stab's `.GotMatchup` writes wAttackMissed when the matchup
-- byte is 0 (effect_commands.asm:1337), `stab` runs ahead of `moveanim` in
-- every damaging effect list (data/moves/effects.asm:5), and
-- BattleCommand_MoveAnimNoSub early-outs on wAttackMissed (:1958), so an
-- immune move plays MoveDelay and nothing else.
do
  local battle, player, wild = newBattle({
    wildSpecies = "GASTLY", random = rolls({}, 0) })
  battle:useMove(player, wild, "TACKLE")
  local events = battle:takeEvents()
  check(findText(events, "It doesn't affect\nEnemy GASTLY!"), "DoesntAffectText")
  eq(moveEvent(events).missed, true,
    "and wAttackMissed is set, so no attack animation plays")
  eq(wild.hp, wild.maxHp, "an immune hit deals nothing")
end

-- ---- the other AnimateFailedMove arms -------------------------------------
do
  -- leech_seed.asm `.grass`: AnimateFailedMove, then PrintDoesntAffect.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "LEECH_SEED", pp = 10, maxPp = 10 } },
    wildSpecies = "TANGELA", random = rolls({}, 0) })
  battle:useMove(player, wild, "LEECH_SEED")
  local events = battle:takeEvents()
  check(findText(events, "It doesn't affect\nEnemy TANGELA!"), "PrintDoesntAffect")
  eq(moveEvent(events).missed, true, "a Grass target plays no animation")
  eq(wild.volatile and wild.volatile.leechSeed, nil, "and nothing is seeded")
end

do
  -- leech_seed.asm `.evaded`: a repeat seeds nothing and animates nothing.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "LEECH_SEED", pp = 10, maxPp = 10 } },
    random = rolls({}, 0) })
  battle:useMove(player, wild, "LEECH_SEED")
  eq(moveEvent(battle:takeEvents()).missed, nil,
    "the seeding arm reaches AnimateCurrentMove")
  battle:useMove(player, wild, "LEECH_SEED")
  local events = battle:takeEvents()
  check(findText(events, battle:romText("EvadedText", player, wild)), "EvadedText")
  eq(moveEvent(events).missed, true, "and the repeat plays nothing")
end

do
  -- BattleCommand_StatDown's `.CantLower` sets wAttackMissed
  -- (effect_commands.asm:4380-4390) and `statdownanim` reads it.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "GROWL", pp = 40, maxPp = 40 } },
    random = rolls({}, 0) })
  battle.stages.enemy.attack = -Effects.MAX_STAGE
  battle:useMove(player, wild, "GROWL")
  local events = battle:takeEvents()
  check(findText(events, battle:romText("WontDropAnymoreText", player, wild,
    battle.data.text["StatNames#1"])), "the refusal line")
  eq(moveEvent(events).missed, true, "a capped drop plays no animation")
end

do
  -- The negative regression that matters: AttackDownHit's `attackdown` runs
  -- AFTER `moveanim`, so a refused SECONDARY drop must leave the event alone.
  -- Battle:markMissed marks the move event retroactively, and the screen only
  -- reads the flag when the queue drains, so marking here would delete an
  -- animation the cart played.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "AURORA_BEAM", pp = 20, maxPp = 20 } },
    random = rolls({}, 0) })
  battle.stages.enemy.attack = -Effects.MAX_STAGE
  battle:useMove(player, wild, "AURORA_BEAM")
  local events = battle:takeEvents()
  eq(moveEvent(events).missed, nil,
    "a refused secondary drop keeps the animation the hit already played")
  check(wild.hp < wild.maxHp, "and the hit still landed")
end

do
  -- BattleCommand_Poison's already-statused arm loads its text and jumps to
  -- `.failed`, which is AnimateFailedMove (effect_commands.asm:3748-3750).
  -- AnimateCurrentMove only runs on `.apply_poison` (:3752).
  local battle, player, wild = newBattle({
    playerMoves = { { id = "POISONPOWDER", pp = 35, maxPp = 35 },
      { id = "TOXIC", pp = 10, maxPp = 10 } },
    random = rolls({}, 0) })
  battle:useMove(player, wild, "POISONPOWDER")
  eq(wild.status, "poison", "the first one lands")
  eq(moveEvent(battle:takeEvents()).missed, nil, "and animates")
  battle:useMove(player, wild, "TOXIC")
  local events = battle:takeEvents()
  eq(moveEvent(events).missed, true,
    "a status move aimed at an already-statused target plays nothing")
  eq(wild.status, "poison", "and changes nothing")
end

-- ---- Rollout locks the user in --------------------------------------------
--
-- BattleCommand_RolloutPower sets SUBSTATUS_ROLLOUT while the counter is short
-- of MAX_ROLLOUT_COUNT (move_effects/rollout.asm), and CheckPlayerLockedIn
-- quits ParsePlayerAction while it is set (core.asm:546), so no menu is
-- offered, no PP is spent and no obedience check is made.
do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "ROLLOUT", pp = 20, maxPp = 20 },
      { id = "TACKLE", pp = 35, maxPp = 35 } },
    wildLevel = 60, random = rolls({}, 0) })
  eq(battle:forcedMove(player), nil, "nothing forces the first Rollout")
  for turn = 1, 4 do
    battle:useMove(player, wild, "ROLLOUT")
    battle:takeEvents()
    eq(battle:forcedMove(player), "ROLLOUT",
      "turn " .. turn .. " of five leaves SUBSTATUS_ROLLOUT set")
  end
  eq(player.moves[1].pp, 19, "only the first turn spent PP (checkrollout skips doturn)")
  battle:useMove(player, wild, "ROLLOUT")
  battle:takeEvents()
  eq(battle:forcedMove(player), nil,
    "MAX_ROLLOUT_COUNT reached: the fifth hit clears the bit")
  eq(player.moves[1].pp, 19, "and still no extra PP was spent")
end

do
  -- A SECOND sequence, started after the first ran its five hits out.
  -- BattleCommand_CheckRollout takes its `.reset` arm whenever
  -- SUBSTATUS_ROLLOUT is clear as the move starts, and zeroes
  -- wPlayerRolloutCount there (move_effects/rollout.asm), so a spent counter
  -- never feeds the next sequence: the new ROLLOUT opens at base power, locks
  -- the menu again, and pays its one PP through the doturn the `.reset` arm
  -- falls through to.
  --
  -- The port used to decide "continue the ramp?" by asking whether the LAST
  -- move was also ROLLOUT, which has no cart equivalent: it held the counter at
  -- the cap, so the second sequence opened at 16x power and left
  -- CheckPlayerLockedIn (core.asm:546) with no bit to read.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "ROLLOUT", pp = 20, maxPp = 20 } },
    wildLevel = 60, random = rolls({}, 0) })

  -- Topped up each time so the target never faints out from under the ramp.
  local function rolloutDamage()
    wild.hp = wild.maxHp
    battle:useMove(player, wild, "ROLLOUT")
    battle:takeEvents()
    return wild.maxHp - wild.hp
  end

  local opening = rolloutDamage()
  eq(battle:forcedMove(player), "ROLLOUT", "the opening hit locks")
  local capped
  for _ = 2, 5 do capped = rolloutDamage() end
  eq(battle:forcedMove(player), nil, "the fifth hit clears SUBSTATUS_ROLLOUT")
  eq(player.moves[1].pp, 19, "the whole first sequence cost one PP")
  check(capped > opening, "the ramp really did double along the way")

  local restarted = rolloutDamage()
  eq(restarted, opening, "the restarted ROLLOUT is back at base power")
  eq(battle:forcedMove(player), "ROLLOUT", "and it locks the menu again")
  eq(player.moves[1].pp, 18, "and pays PP, because .reset falls through to doturn")
end

do
  -- `.skip_set_rampage` reads wAttackMissed before the counter and clears
  -- SUBSTATUS_ROLLOUT outright, so a miss releases the lock.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "ROLLOUT", pp = 20, maxPp = 20 } },
    wildLevel = 60, random = rolls({}, 0) })
  battle:useMove(player, wild, "ROLLOUT")
  battle:takeEvents()
  eq(battle:forcedMove(player), "ROLLOUT", "the first hit locks")
  -- 99 against ROLLOUT's 90 accuracy is a miss on every roll of the turn.
  battle.random = rolls({}, 255)
  battle:useMove(player, wild, "ROLLOUT")
  check(findText(battle:takeEvents(), battle:romText("AttackMissedText", player)),
    "a miss")
  eq(battle:forcedMove(player), nil, "and the miss releases the lock")
end

-- ---- Thrash / Petal Dance: EFFECT_RAMPAGE ---------------------------------
--
-- BattleCommand_Rampage rolls 1 or 2 MORE turns (effect_commands.asm:4886), so
-- the move runs for two or three turns in all; BattleCommand_CheckRampage
-- (:4851) runs the counter down and, at zero, clears the bit and writes
-- SUBSTATUS_CONFUSED with its own `and %00000001` plus two count.
do
  -- rolls: the rampage length (0 -> one MORE turn, two in all), then the
  -- confusion count (0 -> `and 1` plus two, two turns).
  local battle, player, wild = newBattle({
    playerMoves = { { id = "THRASH", pp = 20, maxPp = 20 },
      { id = "TACKLE", pp = 35, maxPp = 35 } },
    wildLevel = 80, random = rolls({ 0 }, 0) })
  battle:useMove(player, wild, "THRASH")
  battle:takeEvents()
  eq(battle:forcedMove(player), "THRASH", "the opening turn locks the user in")
  eq(player.moves[1].pp, 19, "the opening turn spends PP")
  eq(player.volatile.confuseCount, nil, "and nothing is confused yet")

  battle:useMove(player, wild, "THRASH")
  battle:takeEvents()
  eq(battle:forcedMove(player), nil, "the count runs out on the second turn")
  eq(player.moves[1].pp, 19, "a continuing rampage skips doturn, so no PP")
  eq(player.volatile.confuseCount, 2,
    "CheckRampage writes the confusion count itself, `and 1` plus two")
  check(wild.hp < wild.maxHp, "and the last turn still attacked")
end

do
  -- The long roll: 2 more turns, so three in all.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "THRASH", pp = 20, maxPp = 20 } },
    wildLevel = 80, random = rolls({ 1 }, 0) })
  battle:useMove(player, wild, "THRASH")
  battle:takeEvents()
  eq(battle:forcedMove(player), "THRASH", "turn one")
  battle:useMove(player, wild, "THRASH")
  battle:takeEvents()
  eq(battle:forcedMove(player), "THRASH", "turn two")
  battle:useMove(player, wild, "THRASH")
  battle:takeEvents()
  eq(battle:forcedMove(player), nil, "turn three ends it")
  check(player.volatile.confuseCount ~= nil, "and leaves the user confused")
end

do
  -- Switching out is CleanUpBattleRAM: every substatus goes, lock included.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "THRASH", pp = 20, maxPp = 20 } },
    wildLevel = 80, random = rolls({ 1 }, 0) })
  battle:useMove(player, wild, "THRASH")
  battle:takeEvents()
  eq(battle:forcedMove(player), "THRASH", "locked")
  battle:clearVolatile(player)
  eq(battle:forcedMove(player), nil, "a send-out zeroes the substatus")
end

S.finish()
