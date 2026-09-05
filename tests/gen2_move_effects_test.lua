-- Gen 2 move effects with real handlers: confusion, Curse (both arms),
-- Reflect / Light Screen, Leech Seed, the *_HIT flinch, the Bind class
-- partial trap, Solarbeam's sun charge-skip and False Swipe's 1-HP floor.
--
--   luajit tests/gen2_move_effects_test.lua
--
-- ROM-free.  Each block names the pokegold routine it asserts:
-- effect_commands.asm BattleCommand_FinishConfusingTarget / _Screen /
-- _FlinchTarget / _TrapTarget / _SkipSunCharge, move_effects/curse.asm,
-- move_effects/leech_seed.asm, move_effects/false_swipe.asm, and core.asm
-- HandleWrap / HandleScreens / ResidualDamage.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 move effects")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  GHOST = { id = "GHOST", index = 8, category = "physical" },
  ROCK = { id = "ROCK", index = 5, category = "physical" },
  GRASS = { id = "GRASS", index = 22, category = "special" },
  FIRE = { id = "FIRE", index = 20, category = "special" },
  GROUND = { id = "GROUND", index = 4, category = "physical" },
  PSYCHIC = { id = "PSYCHIC", index = 24, category = "special" },
  WATER = { id = "WATER", index = 21, category = "special" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  CONFUSE_RAY = { id = "CONFUSE_RAY", name = "CONFUSE RAY", power = 0,
    type = "GHOST", accuracy = 100, pp = 10, effect = "EFFECT_CONFUSE" },
  CURSE = { id = "CURSE", name = "CURSE", power = 0, type = "NORMAL",
    accuracy = 0, pp = 10, effect = "EFFECT_CURSE" },
  REFLECT = { id = "REFLECT", name = "REFLECT", power = 0, type = "NORMAL",
    accuracy = 0, pp = 20, effect = "EFFECT_REFLECT" },
  LIGHT_SCREEN = { id = "LIGHT_SCREEN", name = "LIGHT SCREEN", power = 0,
    type = "NORMAL", accuracy = 0, pp = 30, effect = "EFFECT_LIGHT_SCREEN" },
  LEECH_SEED = { id = "LEECH_SEED", name = "LEECH SEED", power = 0,
    type = "GRASS", accuracy = 90, pp = 10, effect = "EFFECT_LEECH_SEED" },
  ROCK_SLIDE = { id = "ROCK_SLIDE", name = "ROCK SLIDE", power = 75,
    type = "ROCK", accuracy = 90, pp = 10, effect = "EFFECT_FLINCH_HIT",
    effectChance = 30 },
  WRAP = { id = "WRAP", name = "WRAP", power = 15, type = "NORMAL",
    accuracy = 85, pp = 20, effect = "EFFECT_TRAP_TARGET" },
  FIRE_SPIN = { id = "FIRE_SPIN", name = "FIRE SPIN", power = 15,
    type = "FIRE", accuracy = 70, pp = 15, effect = "EFFECT_TRAP_TARGET" },
  SOLARBEAM = { id = "SOLARBEAM", name = "SOLARBEAM", power = 120,
    type = "GRASS", accuracy = 100, pp = 10, effect = "EFFECT_SOLARBEAM" },
  SUNNY_DAY = { id = "SUNNY_DAY", name = "SUNNY DAY", power = 0,
    type = "FIRE", accuracy = 0, pp = 5, effect = "EFFECT_SUNNY_DAY" },
  FALSE_SWIPE = { id = "FALSE_SWIPE", name = "FALSE SWIPE", power = 40,
    type = "NORMAL", accuracy = 100, pp = 40, effect = "EFFECT_FALSE_SWIPE" },
  EMBER = { id = "EMBER", name = "EMBER", power = 40, type = "FIRE",
    accuracy = 100, pp = 25, effect = "EFFECT_BURN_HIT", effectChance = 100 },
  -- data/moves/moves.asm: SPLASH is power 0, MAGNITUDE is stored at power 1
  -- because getmagnitude overwrites it, SPITE is power 0.
  SPLASH = { id = "SPLASH", name = "SPLASH", power = 0, type = "NORMAL",
    accuracy = 100, pp = 40, effect = "EFFECT_SPLASH" },
  MAGNITUDE = { id = "MAGNITUDE", name = "MAGNITUDE", power = 1,
    type = "GROUND", accuracy = 100, pp = 30, effect = "EFFECT_MAGNITUDE" },
  SPITE = { id = "SPITE", name = "SPITE", power = 0, type = "GHOST",
    accuracy = 100, pp = 10, effect = "EFFECT_SPITE" },
  DREAM_EATER = { id = "DREAM_EATER", name = "DREAM EATER", power = 100,
    type = "PSYCHIC", accuracy = 100, pp = 15,
    effect = "EFFECT_DREAM_EATER" },
  TRANSFORM = { id = "TRANSFORM", name = "TRANSFORM", power = 0,
    type = "NORMAL", accuracy = 0, pp = 10, effect = "EFFECT_TRANSFORM" },
  SWORDS_DANCE = { id = "SWORDS_DANCE", name = "SWORDS DANCE", power = 0,
    type = "NORMAL", accuracy = 0, pp = 30, effect = "EFFECT_ATTACK_UP_2" },
  RECOVER = { id = "RECOVER", name = "RECOVER", power = 0, type = "NORMAL",
    accuracy = 0, pp = 20, effect = "EFFECT_HEAL" },
  SAFEGUARD = { id = "SAFEGUARD", name = "SAFEGUARD", power = 0,
    type = "NORMAL", accuracy = 0, pp = 25, effect = "EFFECT_SAFEGUARD" },
  EARTHQUAKE = { id = "EARTHQUAKE", name = "EARTHQUAKE", power = 100,
    type = "GROUND", accuracy = 100, pp = 10, effect = "EFFECT_EARTHQUAKE" },
  -- STRUGGLE is in the move table like any other move and in nobody's move
  -- list, which is the whole of what makes Battle.STRUGGLE work.
  STRUGGLE = { id = "STRUGGLE", name = "STRUGGLE", power = 50, type = "NORMAL",
    accuracy = 100, pp = 1, effect = "EFFECT_RECOIL_HIT" },
}

-- pokecrystal/data/growth_rates.asm
local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15,
    linear = 100, constant = 140 },
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
  -- pokecrystal/data/pokemon/base_stats/ditto.asm
  DITTO = {
    id = "DITTO", index = 132, name = "DITTO",
    baseStats = { hp = 48, attack = 48, defense = 48, speed = 48,
      specialAttack = 48, specialDefense = 48 },
    types = { "NORMAL", "NORMAL" }, catchRate = 35, baseExp = 61,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 255,
    levelMoves = { { level = 1, move = "TRANSFORM" },
      { level = 10, move = "SWORDS_DANCE" } }, evolutions = {},
  },
  -- pokecrystal/data/pokemon/base_stats/pidgey.asm
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" },
      { level = 11, move = "EMBER" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = {} },
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

local function findText(events, text)
  for _, event in ipairs(events or {}) do
    if event.kind == "message" and event.text == text then return true end
  end
  return false
end

-- ---- confusion: a volatile with a 2-5 turn count --------------------------
do
  -- accuracy roll 0 hits; the count roll 1 -> and %11 = 1, plus 2 = 3 turns.
  local battle, player, wild = newBattle({ random = rolls({ 0, 1 }, 0) })
  battle:useMove(player, wild, "CONFUSE_RAY")
  eq(wild.volatile.confuseCount, 3,
    "FinishConfusingTarget: `and %11` plus two turns")
  eq(wild.status, nil, "SUBSTATUS_CONFUSED never touches the status byte")
  check(findText(battle:takeEvents(), "MACHOP became confused!"),
    "BecameConfusedText")

  -- A second ray answers AlreadyConfusedText and changes nothing.
  battle:useMove(player, wild, "CONFUSE_RAY")
  eq(wild.volatile.confuseCount, 3, "no re-roll on a repeat")
  check(findText(battle:takeEvents(), "MACHOP's already confused!"),
    "AlreadyConfusedText")

  -- The 50 percent self-hit: canAct decrements, then a byte under 128 hurts.
  local before = wild.hp
  battle.random = rolls({ 0 }, 0) -- roll 0 < 128: self-hit
  eq(battle:canAct(wild), false, "the confused turn is spent on the self-hit")
  eq(wild.volatile.confuseCount, 2, "the count decrements first")
  check(wild.hp < before, "HitConfusion's typeless 40-power hit landed")
  check(findText(battle:takeEvents(),
    "It hurt itself in its confusion!"), "with the cart's line")

  -- A byte at or above 128 lets the mon act.
  battle.random = rolls({ 200 }, 0)
  eq(battle:canAct(wild), true, "at or over 50 percent + 1 it acts")
  eq(wild.volatile.confuseCount, 1, "count now on its last turn")

  -- The next decrement snaps out, and the mon still acts THAT turn.
  battle.random = rolls({}, 0)
  eq(battle:canAct(wild), true, "the snap-out turn is not lost")
  eq(wild.volatile.confuseCount, nil, "ConfusedNoMoreText clears the count")

  -- The status byte stayed free the whole time: a burn lands on a mon that
  -- is confused (the old status-slot storage shielded it).
  battle.random = rolls({ 0, 1, 0, 0 }, 0)
  battle:useMove(player, wild, "CONFUSE_RAY")
  battle:useMove(player, wild, "EMBER")
  eq(wild.status, "burn", "a confused mon can still be burned")
  eq(wild.volatile.confuseCount, 3, "and stays confused")
end

-- ---- Curse, non-Ghost arm -------------------------------------------------
do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "CURSE", pp = 10, maxPp = 10 } },
    random = rolls({}, 0) })
  battle:useMove(player, wild, "CURSE")
  eq(battle.stages.player.speed, -1, "Speed falls first")
  eq(battle.stages.player.attack, 1, "then Attack rises")
  eq(battle.stages.player.defense, 1, "then Defense rises")
  check(wild.volatile == nil or wild.volatile.cursed == nil,
    "no curse lands on the target from the stat arm")

  -- Refused only when BOTH raises are capped.
  battle.stages.player.attack = 6
  battle.stages.player.defense = 6
  local speedBefore = battle.stages.player.speed
  battle:useMove(player, wild, "CURSE")
  eq(battle.stages.player.speed, speedBefore,
    "with Attack and Defense capped, nothing moves at all")
  check(findText(battle:takeEvents(),
    "MACHOP's ATTACK won't rise anymore!"), "WontRiseAnymoreText")
end

-- ---- Curse, Ghost arm -----------------------------------------------------
do
  local battle, player, wild = newBattle({ playerSpecies = "GASTLY",
    playerMoves = { { id = "CURSE", pp = 10, maxPp = 10 } },
    random = rolls({}, 0) })
  local maxHp = player.maxHp
  battle:useMove(player, wild, "CURSE")
  eq(wild.volatile.cursed, true, "SUBSTATUS_CURSE set on the target")
  eq(player.hp, maxHp - math.floor(maxHp / 2),
    "the user pays half its max HP")
  eq(battle.stages.player.attack, 0, "no stat change from the Ghost arm")

  -- ResidualDamage's curse arm: a quarter of max HP at the end of the turn.
  local before = wild.hp
  battle:tickSeedAndCurse(wild)
  eq(wild.hp, before - math.floor((wild.maxHp) / 4),
    "the cursed mon loses a quarter of max HP a turn")

  -- A second Ghost curse on the same target fails.
  battle:takeEvents()
  battle:useMove(player, wild, "CURSE")
  check(findText(battle:takeEvents(), "But it failed!"),
    "an already-cursed target refuses")
end

-- pokegold data/moves/effects.asm:1488
do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "CURSE", pp = 10, maxPp = 10 } },
    random = rolls({}, 0) })
  battle:volatile(wild).vanished = true
  battle:useMove(player, wild, "CURSE")
  eq(battle.stages.player.speed, -1,
    "non-Ghost Curse ignores a dug-in target: Speed falls")
  eq(battle.stages.player.attack, 1, "Attack rises")
  eq(battle.stages.player.defense, 1, "Defense rises")
  check(not findText(battle:takeEvents(), "MACHOP's attack missed!"),
    "a chain without checkhit cannot miss")
end

-- pokegold engine/battle/move_effects/curse.asm:58
do
  local battle, player, wild = newBattle({ playerSpecies = "GASTLY",
    playerMoves = { { id = "CURSE", pp = 10, maxPp = 10 } },
    random = rolls({}, 0) })
  battle:volatile(wild).vanished = true
  local hpBefore = player.hp
  battle:useMove(player, wild, "CURSE")
  check(findText(battle:takeEvents(), "But it failed!"),
    "CheckHiddenOpponent fails the Ghost arm")
  eq(battle:volatile(wild).cursed, nil, "no curse lands")
  eq(player.hp, hpBefore, "no HP cut on the failed arm")
end

-- pokegold data/moves/effects.asm:272
do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "SWORDS_DANCE", pp = 30, maxPp = 30 } },
    random = rolls({}, 0) })
  battle:volatile(wild).vanished = true
  battle:useMove(player, wild, "SWORDS_DANCE")
  eq(battle.stages.player.attack, 2,
    "AttackUp2 has no checkhit and reaches its stat change")
  check(not findText(battle:takeEvents(), "MACHOP's attack missed!"),
    "no invented miss against a dug-in target")
end

-- ../pokecrystal/data/moves/effects.asm:1011-1016 LightScreen
do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "REFLECT", pp = 20, maxPp = 20 } },
    random = rolls({}, 0) })
  battle:volatile(wild).vanished = true
  battle:volatile(wild).chargeMove = "DIG"
  battle:useMove(player, wild, "REFLECT")
  eq(battle.screens.player.reflect, Battle.SCREEN_TURNS,
    "Reflect goes up against a dug-in target")
  check(not findText(battle:takeEvents(), "MACHOP's attack missed!"),
    "Reflect has no checkhit: no invented miss")
end

do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "LIGHT_SCREEN", pp = 30, maxPp = 30 } },
    random = rolls({}, 0) })
  battle:volatile(wild).vanished = true
  battle:volatile(wild).chargeMove = "DIG"
  battle:useMove(player, wild, "LIGHT_SCREEN")
  eq(battle.screens.player.lightScreen, Battle.SCREEN_TURNS,
    "Light Screen goes up against a dug-in target")
  check(not findText(battle:takeEvents(), "MACHOP's attack missed!"),
    "Light Screen has no checkhit: no invented miss")
end

-- ../pokecrystal/data/moves/effects.asm Heal
do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "RECOVER", pp = 20, maxPp = 20 } },
    random = rolls({}, 0) })
  battle:volatile(wild).vanished = true
  battle:volatile(wild).chargeMove = "DIG"
  player.hp = 1
  battle:useMove(player, wild, "RECOVER")
  check(player.hp > 1, "Recover heals while the target is underground")
  check(not findText(battle:takeEvents(), "MACHOP's attack missed!"),
    "Heal has no checkhit: no invented miss")
end

-- ../pokecrystal/data/moves/effects.asm Safeguard
do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "SAFEGUARD", pp = 25, maxPp = 25 } },
    random = rolls({}, 0) })
  battle:volatile(wild).vanished = true
  battle:volatile(wild).chargeMove = "DIG"
  battle:useMove(player, wild, "SAFEGUARD")
  eq(battle.screens.player.safeguard, Battle.SCREEN_TURNS,
    "Safeguard goes up against a dug-in target")
  check(not findText(battle:takeEvents(), "MACHOP's attack missed!"),
    "Safeguard has no checkhit: no invented miss")
end

-- ../pokecrystal/engine/battle/effect_commands.asm:1713-1746
do
  local battle, player, wild = newBattle({ random = rolls({}, 0) })
  battle:volatile(wild).vanished = true
  battle:volatile(wild).chargeMove = "DIG"
  local before = wild.hp
  battle:useMove(player, wild, "TACKLE")
  eq(wild.hp, before, "Tackle still cannot reach a dug-in target")
  check(findText(battle:takeEvents(), "MACHOP's attack missed!"),
    ".DigMoves: a checkhit chain misses")
end

do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "EARTHQUAKE", pp = 10, maxPp = 10 } },
    random = rolls({}, 0) })
  battle:volatile(wild).vanished = true
  battle:volatile(wild).chargeMove = "DIG"
  local before = wild.hp
  battle:useMove(player, wild, "EARTHQUAKE")
  check(wild.hp < before, "Earthquake reaches a dug-in target")
  check(not findText(battle:takeEvents(), "MACHOP's attack missed!"),
    ".DigMoves lets EARTHQUAKE through")
end

-- ../pokecrystal/engine/battle/move_effects/transform.asm:7
do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "TRANSFORM", pp = 10, maxPp = 10 } },
    random = rolls({}, 0) })
  battle:volatile(wild).vanished = true
  battle:volatile(wild).chargeMove = "DIG"
  battle:useMove(player, wild, "TRANSFORM")
  local events = battle:takeEvents()
  check(findText(events, "But it failed!"),
    "CheckHiddenOpponent fails Transform with the fail line")
  check(not findText(events, "MACHOP's attack missed!"),
    "and never with the miss line")
  eq(battle:volatile(player).transformed, nil, "no copy lands")
end

-- ../pokecrystal/data/moves/effects.asm
-- ../pokecrystal/engine/battle/effect_commands.asm:5448
do
  local Effects = require("src.battle.gen2.Effects")
  local expected = {
    "EFFECT_MIRROR_MOVE", "EFFECT_ATTACK_UP", "EFFECT_DEFENSE_UP",
    "EFFECT_SPEED_UP", "EFFECT_SP_ATK_UP", "EFFECT_SP_DEF_UP",
    "EFFECT_ACCURACY_UP", "EFFECT_EVASION_UP", "EFFECT_RESET_STATS",
    "EFFECT_CONVERSION", "EFFECT_HEAL", "EFFECT_LIGHT_SCREEN", "EFFECT_MIST",
    "EFFECT_FOCUS_ENERGY", "EFFECT_ATTACK_UP_2", "EFFECT_DEFENSE_UP_2",
    "EFFECT_SPEED_UP_2", "EFFECT_SP_ATK_UP_2", "EFFECT_SP_DEF_UP_2",
    "EFFECT_ACCURACY_UP_2", "EFFECT_EVASION_UP_2", "EFFECT_TRANSFORM",
    "EFFECT_REFLECT", "EFFECT_SUBSTITUTE", "EFFECT_METRONOME",
    "EFFECT_SPLASH", "EFFECT_COUNTER", "EFFECT_SKETCH",
    "EFFECT_DEFROST_OPPONENT", "EFFECT_SLEEP_TALK", "EFFECT_DESTINY_BOND",
    "EFFECT_HEAL_BELL", "EFFECT_MEAN_LOOK", "EFFECT_NIGHTMARE",
    "EFFECT_CURSE", "EFFECT_PROTECT", "EFFECT_SPIKES", "EFFECT_PERISH_SONG",
    "EFFECT_SANDSTORM", "EFFECT_ENDURE", "EFFECT_SAFEGUARD",
    "EFFECT_BATON_PASS", "EFFECT_MORNING_SUN", "EFFECT_SYNTHESIS",
    "EFFECT_MOONLIGHT", "EFFECT_RAIN_DANCE", "EFFECT_SUNNY_DAY",
    "EFFECT_BELLY_DRUM", "EFFECT_PSYCH_UP", "EFFECT_MIRROR_COAT",
    "EFFECT_TELEPORT", "EFFECT_DEFENSE_CURL",
  }
  local count = 0
  for _ in pairs(Effects.NO_CHECKHIT) do count = count + 1 end
  eq(count, #expected, "NO_CHECKHIT lists the 52 chains without checkhit")
  for _, effect in ipairs(expected) do
    eq(Effects.NO_CHECKHIT[effect], true, effect .. " has no checkhit")
  end
  eq(Effects.NO_CHECKHIT.EFFECT_OHKO, nil, "OHKO stays behind CheckHit")
  eq(Effects.NO_CHECKHIT.EFFECT_MIMIC, nil, "Mimic carries checkhit")
end

-- ---- Reflect and Light Screen ---------------------------------------------
do
  -- Reflect doubles Defense against a physical hit: with the seeded
  -- variation the halving is exact enough to compare two identical hits.
  local battle, player, wild = newBattle({ random = rolls({}, 1) })
  local bare = wild.hp
  battle:useMove(player, wild, "TACKLE")
  local plainDamage = bare - wild.hp
  check(plainDamage > 2, "the unscreened tackle deals real damage")

  battle, player, wild = newBattle({ random = rolls({}, 1) })
  battle:useMove(wild, player, "REFLECT")
  eq(battle.screens.enemy.reflect, 5, "BattleCommand_Screen: five turns")
  check(findText(battle:takeEvents(), "MACHOP's DEFENSE rose!"),
    "ReflectEffectText")
  local screened = wild.hp
  battle:useMove(player, wild, "TACKLE")
  local screenedDamage = screened - wild.hp
  check(screenedDamage < plainDamage,
    "Reflect halves the physical hit (got " .. screenedDamage
      .. " vs bare " .. plainDamage .. ")")

  -- A second cast while the first is up fails.
  battle:takeEvents()
  battle:useMove(wild, player, "REFLECT")
  check(findText(battle:takeEvents(), "But it failed!"),
    "one Reflect at a time per side")

  -- A special hit sails through Reflect (Light Screen's business).
  battle, player, wild = newBattle({ random = rolls({}, 1) })
  bare = wild.hp
  battle:useMove(player, wild, "EMBER")
  local emberPlain = bare - wild.hp
  wild.status = nil
  battle, player, wild = newBattle({ random = rolls({}, 1) })
  battle:useMove(wild, player, "REFLECT")
  screened = wild.hp
  battle:useMove(player, wild, "EMBER")
  eq(screened - wild.hp, emberPlain, "Reflect ignores special moves")

  -- HandleScreens: the count ticks each turn and the screen falls at zero.
  battle, player, wild = newBattle({ random = rolls({}, 1) })
  battle:useMove(wild, player, "LIGHT_SCREEN")
  eq(battle.screens.enemy.lightScreen, 5, "Light Screen is five turns too")
  for _ = 1, 4 do battle:tickScreens() end
  eq(battle.screens.enemy.lightScreen, 1, "four ticks down")
  battle:takeEvents()
  battle:tickScreens()
  eq(battle.screens.enemy.lightScreen, nil, "the fifth drops it")
  check(findText(battle:takeEvents(), "Enemy POKéMON's LIGHT SCREEN fell!"),
    "BattleText_MonsLightScreenFell")
end

-- ---- Leech Seed -----------------------------------------------------------
do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "LEECH_SEED", pp = 10, maxPp = 10 } },
    random = rolls({ 0 }, 0) })
  battle:useMove(player, wild, "LEECH_SEED")
  eq(wild.volatile.leechSeed, true, "SUBSTATUS_LEECH_SEED on the target")
  check(findText(battle:takeEvents(), "MACHOP was seeded!"), "WasSeededText")

  -- ResidualDamage: an eighth crosses to the other active mon.
  player.hp = 10
  local seededBefore = wild.hp
  battle:tickSeedAndCurse(wild)
  local drained = seededBefore - wild.hp
  eq(drained, math.floor(wild.maxHp / 8), "an eighth of max HP drains")
  eq(player.hp, 10 + drained, "and lands on the seeder's side")
  check(findText(battle:takeEvents(), "LEECH SEED saps MACHOP!"),
    "LeechSeedSapsText")

  -- A second seed "evaded"; a Grass target is immune outright.
  battle:useMove(player, wild, "LEECH_SEED")
  check(findText(battle:takeEvents(), "MACHOP evaded the attack!"),
    "a seeded target evades the repeat")
  local battle2, player2, tangela = newBattle({ wildSpecies = "TANGELA",
    playerMoves = { { id = "LEECH_SEED", pp = 10, maxPp = 10 } },
    random = rolls({ 0 }, 0) })
  battle2:useMove(player2, tangela, "LEECH_SEED")
  check(tangela.volatile == nil or tangela.volatile.leechSeed == nil,
    "a Grass target cannot be seeded")
  check(findText(battle2:takeEvents(), "It doesn't affect TANGELA..."),
    "PrintDoesntAffect for Grass")
end

-- ---- the *_HIT flinch -----------------------------------------------------
do
  -- Rolls: crit roll, accuracy, damage variation, then the 30% flinch: 10
  -- lands under 30.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "ROCK_SLIDE", pp = 10, maxPp = 10 } },
    random = rolls({ 1, 0, 0, 10 }, 1) })
  battle:useMove(player, wild, "ROCK_SLIDE")
  eq(wild.volatile.flinched, true,
    "BattleCommand_FlinchTarget: the effect chance landed")
  eq(battle:canAct(wild), false, "the flinched mon loses its turn")
  check(findText(battle:takeEvents(), "MACHOP flinched!"), "FlinchedText")

  -- A roll past the chance leaves no flinch.
  battle, player, wild = newBattle({
    playerMoves = { { id = "ROCK_SLIDE", pp = 10, maxPp = 10 } },
    random = rolls({ 1, 0, 0, 90 }, 1) })
  battle:useMove(player, wild, "ROCK_SLIDE")
  check(wild.volatile == nil or wild.volatile.flinched == nil,
    "a 90 roll misses the 30 percent chance")
end

-- ---- the Bind class partial trap ------------------------------------------
do
  -- Rolls: crit, accuracy, variation, then the wrap count roll 1 -> 1+3 = 4.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "WRAP", pp = 20, maxPp = 20 } },
    random = rolls({ 1, 0, 0, 1 }, 1) })
  battle:useMove(player, wild, "WRAP")
  eq(wild.volatile.wrapCount, 4,
    "BattleCommand_TrapTarget: `and %11` plus three")
  eq(wild.volatile.wrapMove, "WRAP", "the trapping move is remembered")
  check(findText(battle:takeEvents(), "MACHOP was WRAPPED by MACHOP!"),
    "WrappedByText")

  -- HandleWrap: decrement first, then a sixteenth -- and release at zero.
  local before = wild.hp
  battle:tickWrap(wild)
  eq(wild.volatile.wrapCount, 3, "the count decrements first")
  eq(before - wild.hp, math.max(1, math.floor(wild.maxHp / 16)),
    "a sixteenth of max HP a turn")
  battle:tickWrap(wild)
  battle:tickWrap(wild)
  battle:takeEvents()
  battle:tickWrap(wild)
  eq(wild.volatile.wrapCount, nil, "the last tick releases")
  check(findText(battle:takeEvents(), "MACHOP was released from WRAP!"),
    "UserWasReleasedFromStringBuffer1")

  -- No re-trap while one is running.
  battle.random = rolls({ 1, 0, 0, 1 }, 1)
  battle:useMove(player, wild, "WRAP")
  battle.random = rolls({ 1, 0, 0, 1 }, 1)
  local count = wild.volatile.wrapCount
  battle:useMove(player, wild, "WRAP")
  eq(wild.volatile.wrapCount, count, "an existing trap is not re-rolled")
end

-- ---- Solarbeam under the sun ----------------------------------------------
do
  local battle, player, wild = newBattle({
    playerMoves = { { id = "SOLARBEAM", pp = 10, maxPp = 10 } },
    random = rolls({}, 1) })
  local before = wild.hp
  battle:useMove(player, wild, "SOLARBEAM")
  eq(wild.hp, before, "without sun, turn one only charges")
  eq(player.volatile.chargeMove, "SOLARBEAM", "the charge is stored")

  battle, player, wild = newBattle({
    playerMoves = { { id = "SOLARBEAM", pp = 10, maxPp = 10 } },
    random = rolls({}, 1) })
  battle.weather = "sun"
  before = wild.hp
  battle:useMove(player, wild, "SOLARBEAM")
  check(wild.hp < before,
    "BattleCommand_SkipSunCharge: in sun the beam fires in one turn")
  eq(player.volatile.chargeMove, nil, "no charge stored")
end

-- ---- False Swipe's 1-HP floor ---------------------------------------------
do
  -- A hit that would KO leaves exactly 1 HP.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "FALSE_SWIPE", pp = 40, maxPp = 40 } },
    random = rolls({ 1 }, 1) })
  wild.hp = 3
  battle:useMove(player, wild, "FALSE_SWIPE")
  eq(wild.hp, 1,
    "BattleCommand_FalseSwipe: damage is capped at the target's HP minus 1")

  -- At 1 HP already, the swipe deals nothing at all.
  battle.random = rolls({ 1 }, 1)
  battle:useMove(player, wild, "FALSE_SWIPE")
  eq(wild.hp, 1, "a 1-HP target cannot be KOed by it either")
end

-- ---- Splash prints the line and does nothing else -------------------------
do
  -- BattleCommand_Splash (move_effects/splash.asm) is the animation and then
  -- `jp PrintNothingHappened`; the effect list has no checkhit at all.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "SPLASH", pp = 40, maxPp = 40 } },
    random = rolls({}, 1) })
  local before = wild.hp
  local playerBefore = player.hp
  battle:useMove(player, wild, "SPLASH")
  check(findText(battle:takeEvents(), "But nothing\nhappened."),
    "NothingHappenedText, with the cart's own line break")
  eq(wild.hp, before, "and the target is never touched")
  eq(player.hp, playerBefore, "nor the user")
end

-- ---- Magnitude rolls its power off MagnitudePower -------------------------
do
  -- One BattleRandom byte walks data/moves/magnitude_power.asm and the first
  -- row whose threshold is not below it wins: 200 falls in the `85 percent + 1`
  -- row (217), which is Magnitude 8 at 90 power.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "MAGNITUDE", pp = 30, maxPp = 30 } },
    random = rolls({ 200 }, 1) })
  local before = wild.hp
  battle:useMove(player, wild, "MAGNITUDE")
  check(findText(battle:takeEvents(), "Magnitude 8!"),
    "MagnitudeText names the magnitude before checkhit")
  check(before - wild.hp > 5,
    "and the rolled power replaces the ROM's stored 1")

  -- The bottom row: a roll of 0 is under every threshold, so Magnitude 4.
  battle, player, wild = newBattle({
    playerMoves = { { id = "MAGNITUDE", pp = 30, maxPp = 30 } },
    random = rolls({ 0 }, 1) })
  battle:useMove(player, wild, "MAGNITUDE")
  check(findText(battle:takeEvents(), "Magnitude 4!"),
    "`cp b / jr nc` takes the first row whose threshold covers the roll")
end

-- ---- Spite drains 2-5 PP from the target's last move ----------------------
do
  -- BattleCommand_Spite reads BATTLE_VARS_LAST_COUNTER_MOVE_OPP: the move the
  -- TARGET used last.  `and %11` plus two is 2-5, clamped to what is left.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "SPITE", pp = 10, maxPp = 10 } },
    random = rolls({ 0, 3 }, 0) })
  battle:volatile(wild).lastMove = "TACKLE"
  battle:useMove(player, wild, "SPITE")
  eq(wild.moves[1].pp, 30, "a roll of 3 takes five PP")
  check(findText(battle:takeEvents(), "MACHOP's TACKLE was reduced by 5!"),
    "SpiteEffectText names the move and the figure")

  -- The clamp: never more than the slot still holds.
  battle, player, wild = newBattle({
    playerMoves = { { id = "SPITE", pp = 10, maxPp = 10 } },
    random = rolls({ 0, 3 }, 0) })
  battle:volatile(wild).lastMove = "TACKLE"
  wild.moves[1].pp = 3
  battle:useMove(player, wild, "SPITE")
  eq(wild.moves[1].pp, 0, "`cp b / jr nc` keeps the loss inside the slot")

  -- Nothing to spite: `.failed` is `jp PrintDidntAffect2`.
  battle, player, wild = newBattle({
    playerMoves = { { id = "SPITE", pp = 10, maxPp = 10 } },
    random = rolls({ 0 }, 0) })
  battle:useMove(player, wild, "SPITE")
  check(findText(battle:takeEvents(), "It didn't affect MACHOP!"),
    "a target that has not moved yet cannot be spited")
  eq(wild.moves[1].pp, 35, "and nothing was taken")
end

-- ---- Dream Eater is gated by checkhit, not by the damage block ------------
do
  -- CheckHit opens on `call .DreamEater / jp z, .Miss`
  -- (effect_commands.asm:1554), so an awake target takes nothing at all.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "DREAM_EATER", pp = 15, maxPp = 15 } },
    random = rolls({}, 1) })
  player.hp = math.max(1, player.hp - 20)
  local before, healthBefore = wild.hp, player.hp
  battle:useMove(player, wild, "DREAM_EATER")
  check(findText(battle:takeEvents(), "MACHOP's attack missed!"),
    "AttackMissedText: .Miss, not ButItFailedText")
  eq(wild.hp, before, "no damage against a target that is awake")
  eq(player.hp, healthBefore, "and nothing was sapped")

  -- Asleep, it lands and drains half of what it dealt.
  battle, player, wild = newBattle({
    playerMoves = { { id = "DREAM_EATER", pp = 15, maxPp = 15 } },
    random = rolls({}, 1) })
  player.hp = math.max(1, player.hp - 20)
  wild.status = "sleep"
  before, healthBefore = wild.hp, player.hp
  battle:useMove(player, wild, "DREAM_EATER")
  check(wild.hp < before, "a sleeping target takes the hit")
  check(player.hp > healthBefore, "and the user drains half of it")
end

-- ---- TRANSFORM is battle ram: it never leaves the battle on the mon --------
do
  -- BattleCommand_Transform copies the target into wBattleMon / wEnemyMon and
  -- leaves the struct the mon was loaded from alone, so SwitchOutMon's reload
  -- and PokeBallEffect's `.catch_without_fail` (which reads
  -- wTempEnemyMonSpecies, a byte no move rewrites) both hand back a DITTO.
  -- This port has one table per mon, so what the copy overwrites is kept on
  -- the volatile and Battle:untransform puts it back -- once at every route
  -- out of the battle.  Before this a DITTO that transformed was a permanent
  -- copy: the caught record and the player's own party slot went into the save
  -- as the wrong species, with the wrong moves and the wrong stats.
  local battle, player, wild = newBattle({
    playerMoves = { { id = "TRANSFORM", pp = 10, maxPp = 10 } },
    wildSpecies = "TANGELA",
    wildMoves = { { id = "TACKLE", pp = 35, maxPp = 35 } },
    random = rolls({}, 0) })
  local ownAttack = player.stats.attack
  battle:useMove(player, wild, "TRANSFORM")
  eq(player.species, "TANGELA", "the copy lands at once: the battler IS it")
  eq(player.moves[1].id, "TACKLE", "with the target's moves")
  eq(player.stats.attack, wild.stats.attack, "and the target's stats")
  local state = battle:volatile(player)
  eq(state.preTransform.species, "MACHOP", "and the record it was is kept")

  -- The event the screen swaps its pic on: src/ui/gen2/BattleState.lua draws
  -- from `shownMon`, which follows the event queue, and a whole round is
  -- resolved before its first message is read.
  local sawEvent = false
  for _, event in ipairs(battle:takeEvents()) do
    if event.kind == "transform" then
      sawEvent = true
      eq(event.species, "TANGELA", "the transform event names the copy")
      eq(event.from, "MACHOP", "and what it was")
    end
  end
  check(sawEvent, "TRANSFORM emits its own moment for the screen")

  -- CleanUpBattleRAM, which is where the screen's finishBattle sends it.
  battle:clearAllVolatiles()
  eq(player.species, "MACHOP", "the party slot leaves the battle as itself")
  eq(player.moves[1].id, "TRANSFORM", "with its own moves")
  eq(player.stats.attack, ownAttack, "and its own stats")
  eq(player.volatile, nil, "and no volatile left on a save table")
end

do
  -- pokecrystal/engine/battle/core.asm:6983
  local battle, player, wild = newBattle({
    playerSpecies = "DITTO", playerLevel = 9,
    playerMoves = { { id = "TRANSFORM", pp = 10, maxPp = 10 } },
    wildSpecies = "PIDGEY", wildLevel = 3,
    random = rolls({}, 0) })
  player.experience = 729
  local ownMaxHp = Mon.stats(POKEMON.DITTO.baseStats, player.dvs, 9,
    player.statExp).hp
  battle:useMove(player, wild, "TRANSFORM")
  eq(player.species, "PIDGEY", "the copy is live while the battle runs")
  wild.hp = 0
  battle:resolveFaints()
  eq(player.experience, 752, "23 EXP from a level 3 PIDGEY, banked on 729")
  eq(player.level, 9, "DITTO's own MEDIUM_FAST curve does not reach 10 yet")
  eq(player.maxHp, ownMaxHp, "and maxHP is still DITTO's base 48, not PIDGEY's")
  eq(player.species, "DITTO", "the battle ends with the party slot itself")

  -- pokecrystal/engine/battle/core.asm:8294
  local pinned = false
  for _, event in ipairs(battle:takeEvents()) do
    if event.kind == "identity" then
      pinned = true
      eq(event.side, "player", "the side whose pic must not change")
      eq(event.species, "PIDGEY", "stays the copy for the rest of the screen")
      eq(event.partySpecies, "DITTO", "over the mon that is really there")
    end
  end
  check(pinned, "endBattle emits the identity the screen keeps drawing")
end

do
  local battle, player, wild = newBattle({
    playerSpecies = "DITTO", playerLevel = 9,
    playerMoves = { { id = "TRANSFORM", pp = 10, maxPp = 10 } },
    wildSpecies = "PIDGEY", wildLevel = 3,
    random = rolls({}, 0) })
  player.experience = 729
  battle:useMove(player, wild, "TRANSFORM")
  local copiedAttack = player.stats.attack
  Mon.gainExperience(player, 271, DATA)
  eq(player.level, 10, "1000 EXP is level 10 on MEDIUM_FAST, 12 on MEDIUM_SLOW")
  eq(player.maxHp, Mon.stats(POKEMON.DITTO.baseStats, player.dvs, 10,
    player.statExp).hp, "recomputed off DITTO's base stats")
  eq(player.stats.attack, copiedAttack,
    "the copied battle stats stay in play while transformed")

  -- pokecrystal/engine/pokemon/learn.asm:88
  eq(battle:learnPartyMove(player, "SWORDS_DANCE"), true, "the party learns it")
  eq(#player.moves, 1, "the copied moveset is untouched")
  eq(player.moves[1].id, "TACKLE", "and still the target's move")

  battle:untransform(player)
  eq(player.level, 10, "the level survives the unwind")
  eq(player.stats.attack, Mon.stats(POKEMON.DITTO.baseStats, player.dvs, 10,
    player.statExp).attack, "and the restored stats are the new ones")
  eq(player.moves[2].id, "SWORDS_DANCE", "with the move it learned mid-copy")
end

do
  local ItemEffects = require("src.core.gen2.ItemEffects")
  local battle, player, wild = newBattle({
    playerSpecies = "DITTO", playerLevel = 9,
    playerMoves = { { id = "TRANSFORM", pp = 10, maxPp = 10 } },
    wildSpecies = "PIDGEY", wildLevel = 3,
    random = rolls({}, 0) })
  player.experience = 729
  battle:useMove(player, wild, "TRANSFORM")
  local result = ItemEffects.useOnMon("RARE_CANDY", player, DATA)
  eq(result.used, true, "the candy is spent")
  eq(player.level, 10, "one level, as always")
  eq(player.experience, 1000, "DITTO's MEDIUM_FAST threshold, not PIDGEY's 742")
  eq(player.maxHp, Mon.stats(POKEMON.DITTO.baseStats, player.dvs, 10,
    player.statExp).hp, "and DITTO's base stats behind the new maxHP")
end

-- ---- a DITTO caught while transformed is caught as a DITTO -----------------
do
  local Catching = require("src.battle.gen2.Catching")
  local battle, player, wild = newBattle({
    wildMoves = { { id = "TRANSFORM", pp = 10, maxPp = 10 } },
    playerSpecies = "TANGELA",
    random = rolls({}, 0) })
  battle:useMove(wild, player, "TRANSFORM")
  eq(wild.species, "TANGELA", "the wild mon is the copy while the battle runs")

  -- PokeBallEffect's captured tail, reached through the one call the catch
  -- site makes into the battle rules.  A MASTER BALL so the roll is not what
  -- is being tested.
  local caught = Catching.attempt({ ball = "MASTER_BALL", battle = battle,
    mon = wild, maxHp = wild.maxHp, hp = wild.hp, catchRate = 45 })
  eq(caught, true, "the MASTER BALL never fails")
  eq(wild.species, "MACHOP", "and the record the catch keeps is the real mon")
  eq(wild.moves[1].id, "TRANSFORM", "with its own move list")
end

-- ---- STRUGGLE: full damage, then a quarter of it back ----------------------
do
  -- data/moves/moves.asm gives STRUGGLE 50 power and EFFECT_RECOIL_HIT, and
  -- BattleCommand_Recoil takes a QUARTER of the damage dealt (Gen 1's half is
  -- not Gen 2's formula), minimum 1.
  local battle, player, wild = newBattle({ random = rolls({}, 1) })
  local before, mine = wild.hp, player.hp
  battle:useMove(player, wild, Battle.STRUGGLE)
  local dealt = before - wild.hp
  check(dealt > 5, "STRUGGLE swings its 50 power, not chip damage")
  eq(mine - player.hp, math.max(1, math.floor(dealt / 4)),
    "and the user takes a quarter of what it dealt")
  check(findText(battle:takeEvents(), "MACHOP is hit with recoil!"),
    "RecoilText")
end

-- ---- RUN is refused by a trainer battle without spending the turn ----------
do
  -- `.cant_run_from_trainer` leaves wBattlePlayerAction alone and falls into
  -- `jp BattleMenu` (engine/battle/core.asm:5035-5038), so the 2x2 menu comes
  -- straight back and the trainer never gets a free swing.  Only
  -- `.cant_escape_2`, the failed ROLL, writes BATTLEPLAYERACTION_USEITEM and
  -- costs the round.
  local foe = Mon.new(DATA, "MACHOP", 15, { dvs = perfect })
  foe.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local player = Mon.new(DATA, "MACHOP", 15, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = DATA, party = { player },
    trainer = { class = "YOUNGSTER", party = { foe } }, random = rolls({}, 0) })
  local before = player.hp
  local events = battle:takeTurn({ kind = "run" })
  eq(player.hp, before, "the trainer never moved")
  eq(battle.over, false, "and the battle is still running")
  eq(battle.runRefused, true, "the refusal is what stopped the round")
  check(findText(events, "No! There's no running from a trainer battle!"),
    "NoRunningText")
end

S.finish()
