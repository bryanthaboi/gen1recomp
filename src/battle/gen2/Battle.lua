-- Gen 2 battle engine: the turn loop, as pure logic.
--
-- No love calls and no rendering: a battle is a state machine that consumes
-- actions and produces a queue of events, so the same engine drives the screen
-- (src/ui/gen2/BattleState.lua), a headless driver, and the tests.  Gen 1's
-- src/battle/BattleState.lua interleaves logic with drawing, which is exactly
-- what makes its turn order hard to assert; this does not repeat that.
--
-- Ported from engine/battle/core.asm's turn structure:
--   * both sides choose (a move, an item, a switch, or run)
--   * order is by Speed after stat stages, with a coin flip on a tie
--     (DetermineMoveOrder); a switch or item always goes first
--   * each attack: PP, status gates (sleep/freeze/paralysis), accuracy, damage,
--     then the move's secondary effect
--   * end of turn: burn and poison tick, then faint checks and experience
--
-- Status handling follows Gen 2's rules rather than Gen 1's: burn is 1/8 max HP
-- (not 1/16) and halves physical Attack, poison is 1/8, and sleep counts down
-- from 1-7 turns.

local Damage = require("src.battle.gen2.Damage")
local Ai = require("src.battle.gen2.Ai")
local Effects = require("src.battle.gen2.Effects")
local Mon = require("src.battle.gen2.Mon")
local Happiness = require("src.core.gen2.Happiness")
local Pokerus = require("src.core.gen2.Pokerus")
local Roamers = require("src.core.gen2.Roamers")
local Prize = require("src.battle.gen2.Prize")
-- The mod event/hook buses.  Every name raised from this file is the SAME name
-- src/battle/BattleState.lua raises on Gen 1, carrying the same payload keys
-- with the same meaning -- a mod written against Red's battle reads Gold's
-- without learning a second vocabulary (docs/mod-api-gen2-compat.md).  Where
-- Gen 2 genuinely carries more (split special stats, a held item on either
-- battler) the extra rides BESIDE the Gen 1 key, never instead of it.
--
-- Two shape differences are unavoidable and are called out at each site:
--   * Gen 1's `user` / `target` / `battler` are battler wrappers around a mon
--     ({ mon = , name = , isPlayer = }); Gen 2's engine works on the party mon
--     table directly, so that is what these payloads carry.
--   * Gen 1's `rng` is love.math.random (rng(n) → 1..n, rng(lo,hi) → lo..hi).
--     Gen 2's cart BattleRandom is random(n) → 0..n-1.  Both live on the
--     battle: `random` / `roller()` are BattleRandom for damage, accuracy,
--     Magnitude, etc.; `rng` is the Gen 1 / love-style view of the same stream.
local Runtime = require("src.mods.Runtime")
-- The two battle lines that carry the cart's own `line` break: a marker-bearing
-- literal has to stay reachable from a translation mod (#186, #245), which is
-- what tests/engine/gate_strings_coverage.lua watches for.
local Strings = require("src.core.Strings")

local Battle = {}
Battle.__index = Battle

-- Burn and poison both tick 1/8 of max HP at the end of a turn in Gen 2.
Battle.BURN_FRACTION = 8
Battle.POISON_FRACTION = 8
-- Burn halves physical Attack; paralysis quarters Speed.
Battle.BURN_ATTACK_DIVISOR = 2
Battle.PARALYSIS_SPEED_DIVISOR = 4
-- A paralysed mon loses its turn a quarter of the time.
Battle.PARALYSIS_SKIP_CHANCE = 4
-- A frozen mon thaws on a 1-in-5 roll each turn it tries to move.
Battle.THAW_CHANCE = 5

-- Moves whose effect the engine models.  Everything else lands as a plain hit
-- (or, with no power, as a no-op message), which is honest: an unmodelled
-- effect never silently does the wrong thing.
Battle.STATUS_EFFECTS = {
  EFFECT_SLEEP = "sleep",
  EFFECT_POISON = "poison",
  EFFECT_TOXIC = "toxic",
  EFFECT_PARALYZE = "paralyze",
  EFFECT_BURN = "burn",
  EFFECT_FREEZE = "freeze",
  EFFECT_CONFUSE = "confuse",
}
Battle.SECONDARY_EFFECTS = {
  EFFECT_POISON_HIT = "poison",
  EFFECT_BURN_HIT = "burn",
  EFFECT_FREEZE_HIT = "freeze",
  EFFECT_PARALYZE_HIT = "paralyze",
  EFFECT_SLEEP_HIT = "sleep",
  EFFECT_CONFUSE_HIT = "confuse",
  EFFECT_SACRED_FIRE = "burn", -- data/moves/effects.asm:1696
}

local function rand(random, n)
  if random then return random(n) end
  if love and love.math and love.math.random then
    return love.math.random(n) - 1
  end
  return math.random(n) - 1
end

-- Gen 1 / love.math view of BattleRandom: rng(n) → 1..n, rng(lo,hi) → lo..hi.
local function loveStyleRng(random)
  return function(lo, hi)
    if hi == nil then
      local n = lo or 1
      if n < 1 then n = 1 end
      return (rand(random, n) or 0) + 1
    end
    if hi < lo then lo, hi = hi, lo end
    return lo + (rand(random, hi - lo + 1) or 0)
  end
end

-- data/trainers/leaders.asm.  The two lists are ONE array in the ROM: only
-- KantoGymLeaders carries the -1 terminator, and GymLeaders falls through into
-- it, so IsGymLeader matches all twenty-two classes while IsKantoGymLeader
-- (which starts halfway down) matches the last eight.  Splitting them into two
-- separate tables here and forgetting the fallthrough would deny Brock's party
-- its HAPPINESS_GYMBATTLE, which is exactly the bug the comment at the top of
-- leaders.asm warns about.
Battle.KANTO_GYM_LEADER_CLASSES = {
  BROCK = true, MISTY = true, LT_SURGE = true, ERIKA = true,
  JANINE = true, SABRINA = true, BLAINE = true, BLUE = true,
}
Battle.GYM_LEADER_CLASSES = {
  FALKNER = true, WHITNEY = true, BUGSY = true, MORTY = true,
  PRYCE = true, JASMINE = true, CHUCK = true, CLAIR = true,
  WILL = true, BRUNO = true, KAREN = true, KOGA = true,
  CHAMPION = true, RED = true,
}
for class in pairs(Battle.KANTO_GYM_LEADER_CLASSES) do
  Battle.GYM_LEADER_CLASSES[class] = true
end

-- IsGymLeader / IsKantoGymLeader, as predicates.
function Battle.isGymLeader(class)
  return class ~= nil and Battle.GYM_LEADER_CLASSES[class] == true
end

function Battle.isKantoGymLeader(class)
  return class ~= nil and Battle.KANTO_GYM_LEADER_CLASSES[class] == true
end

-- The four items XItemEffect covers (data/items/x_stats.asm).  DIRE_HIT and
-- GUARD_SPEC have their own effect routines and award nothing, so they are
-- deliberately not here.
Battle.X_ITEMS = {
  X_ATTACK = true, X_DEFEND = true, X_SPEED = true, X_SPECIAL = true,
}

-- data/items/x_stats.asm: which stat each X item raises one stage of.
-- X SPECIAL is SP_ATTACK only in Gen 2.
Battle.X_ITEM_STATS = {
  X_ATTACK = "attack", X_DEFEND = "defense", X_SPEED = "speed",
  X_SPECIAL = "specialAttack",
}

-- XAccuracyEffect / DireHitEffect / GuardSpecEffect (engine/items/
-- item_effects.asm:2079-2113): each sets one wPlayerSubStatus4 bit on the
-- active mon and refuses when it is already up.  The bits live in the mon's
-- volatile so a switch drops them, which is what SUBSTATUS4 does too.
Battle.SUBSTATUS_ITEMS = {
  X_ACCURACY = "xAccuracy",  -- SUBSTATUS_X_ACCURACY: skip the accuracy roll
  DIRE_HIT = "focusEnergy",  -- SUBSTATUS_FOCUS_ENERGY: +1 critical level
  GUARD_SPEC = "mist",       -- SUBSTATUS_MIST: no stat drops from the foe
}

-- constants/battle_constants.asm const order: the two battle types whose
-- whole meaning is "no escape".  TryToRunAwayFromBattle jumps straight to
-- .cant_escape for both, ahead of even the trainer check, and
-- BattleCommand_ForceSwitch fails outright for both -- the Lake of Rage
-- Gyarados (FORCESHINY) and the Rocket base's exploding traps (TRAP) cannot
-- be run from or Roared away.
Battle.BATTLETYPE_FORCESHINY = 7
Battle.BATTLETYPE_TRAP = 9

-- BadgeStatBoosts (engine/battle/core.asm:6534): each of these Johto badges
-- raises the PLAYER's in-battle stat by 1/8.  The routine walks every other
-- badge bit after swapping PlainBadge and MineralBadge, which is what lands
-- Mineral on Defense and Plain on Speed; Glacier boosts Special Attack, and
-- its Special Defense re-check is the buggy tail modelled in
-- Battle.glacierBoostsSpDef below.
Battle.BADGE_STAT_BOOSTS = {
  attack = "ZEPHYR",
  defense = "MINERAL",
  speed = "PLAIN",
  specialAttack = "GLACIER",
}

-- data/types/badge_type_boosts.asm, in the cart's own walk order: the eight
-- wJohtoBadges bits, then the eight wKantoBadges bits.  DoBadgeTypeBoosts
-- boosts the player's damage by 1/8 when an owned badge's type matches the
-- move's.
Battle.BADGE_TYPE_BOOSTS = {
  { store = "badges", badge = "ZEPHYR", type = "FLYING" },
  { store = "badges", badge = "HIVE", type = "BUG" },
  { store = "badges", badge = "PLAIN", type = "NORMAL" },
  { store = "badges", badge = "FOG", type = "GHOST" },
  { store = "badges", badge = "MINERAL", type = "STEEL" },
  { store = "badges", badge = "STORM", type = "FIGHTING" },
  { store = "badges", badge = "GLACIER", type = "ICE" },
  { store = "badges", badge = "RISING", type = "DRAGON" },
  { store = "kantoBadges", badge = "BOULDER", type = "ROCK" },
  { store = "kantoBadges", badge = "CASCADE", type = "WATER" },
  { store = "kantoBadges", badge = "THUNDER", type = "ELECTRIC" },
  { store = "kantoBadges", badge = "RAINBOW", type = "GRASS" },
  { store = "kantoBadges", badge = "SOUL", type = "POISON" },
  { store = "kantoBadges", badge = "MARSH", type = "PSYCHIC_TYPE" },
  { store = "kantoBadges", badge = "VOLCANO", type = "FIRE" },
  { store = "kantoBadges", badge = "EARTH", type = "GROUND" },
}

-- wJohtoBadges bit order, for the positional keying FieldMoves.hasBadge also
-- accepts (a save may key player.badges by name or by bit position).
Battle.JOHTO_BADGE_ORDER = {
  "ZEPHYR", "HIVE", "PLAIN", "FOG", "MINERAL", "STORM", "GLACIER", "RISING",
}
Battle.KANTO_BADGE_ORDER = {
  "BOULDER", "CASCADE", "THUNDER", "RAINBOW",
  "SOUL", "MARSH", "VOLCANO", "EARTH",
}

-- opts:
--   data      { pokemon, moves, type_chart, items }
--   party     the player's party (array of Mon)
--   wild      a single Mon for a wild battle
--   trainer   { class, name, party, baseMoney } for a trainer battle;
--             baseMoney is the class's TRNATTR_BASE_REWARD and is what
--             src/battle/gen2/Prize.lua pays out of when the trainer loses
--   save      the Gold save, for the two money accounts WinTrainerBattle
--             writes.  Optional: a headless turn-order test hands in no save
--             and the payout is simply skipped, the way wMoney is untouched
--             by a link battle
--   roaming   the save's roamer slot index (1 Raikou, 2 Entei, 3 Suicune) when
--             this wild battle is BATTLETYPE_ROAMING; the caller built `wild`
--             through Roamers.beginBattle and reads Battle.roaming back to
--             bank the beast's HP afterwards
--   random(n) 0..n-1, injected so a test is deterministic (BattleRandom)
--   rng(lo,hi) / rng(n) Gen 1 / love.math contract; defaults over `random`
function Battle.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Battle)
  self.data = opts.data or {}
  self.random = opts.random or function(n) return rand(nil, n) end
  -- Same stream as `random`, Gen 1 / love.math calling convention.
  self.rng = opts.rng or loveStyleRng(self.random)
  self.party = opts.party or {}
  self.trainer = opts.trainer
  self.save = opts.save
  -- wBattleType, when the caller knows it: "fish" gates the Lure Ball's x3
  -- (BATTLETYPE_FISH is the one condition LureBallMultiplier reads), and the
  -- FORCESHINY / TRAP no-escape rules will hang off the same field.
  self.battleType = opts.battleType
  self.events = {}
  self.turn = 0
  self.over = false
  self.outcome = nil -- "win" | "lose" | "run" | "caught"
  -- Participants earn experience; a switch adds to the set.
  self.participants = {}

  self.playerIndex = Battle.firstHealthy(self.party) or 1
  self.player = self.party[self.playerIndex]
  if self.player then self.participants[self.playerIndex] = true end
  -- wAmuletCoin, latched by CheckAmuletCoin on every send-out and never
  -- cleared again until the next battle starts.
  self.amuletCoin = false
  self:checkAmuletCoin(self.player)

  if opts.wild then
    self.wild = true
    self.enemy = opts.wild
    self.enemyParty = { opts.wild }
    self.enemyIndex = 1
    -- wBattleType = BATTLETYPE_ROAMING.  Kept as the SLOT index rather than a
    -- boolean because BattleEnd_HandleRoamMons needs to know whose HP byte to
    -- write, and GetRoamMonHP resolves that from the species.
    self.roaming = opts.roaming
  else
    self.wild = false
    self.enemyParty = (self.trainer and self.trainer.party) or {}
    -- trainer.party, the same hook BattleState:startTrainer calls on Gen 1 and
    -- with the same three arguments: the class, which roster of that class, and
    -- the roster itself, returning the roster to fight.  Gen 2's rows carry a
    -- held item and split special stats; a mod that hands back rows it built
    -- itself keeps them, because nothing here rewrites what the hook returned.
    -- The second argument is the party MEMBER id (RIVAL2_2_CHIKORITA), which is
    -- what picks a roster out of a class in Gen 2 -- Gen 1's numeric index by
    -- another name.
    if self.trainer and Runtime.wantsHook("trainer.party") then
      self.enemyParty = Runtime.call("trainer.party", function(_, _, party)
        return party
      end, self.trainer.classId or self.trainer.class,
      self.trainer.memberId or self.trainer.index or 1,
      self.enemyParty) or self.enemyParty
    end
    self.enemyIndex = Battle.firstHealthy(self.enemyParty) or 1
    self.enemy = self.enemyParty[self.enemyIndex]
  end

  for _, mon in ipairs(self.party) do
    Mon.refreshStats(mon, self.data)
  end
  for _, mon in ipairs(self.enemyParty or {}) do
    Mon.refreshStats(mon, self.data)
  end

  -- Battle RAM opens empty on both sides: NewBattleMonStatus and
  -- NewEnemyMonStatus run at the first send-out of every battle.
  self:clearAllVolatiles()

  self.stages = {
    player = Battle.newStages(),
    enemy = Battle.newStages(),
  }
  -- wBattleWeather / wWeatherCount: field state, not per-mon, so it survives a
  -- switch on either side.
  self.weather = nil
  self.weatherTurns = 0
  -- wPlayerScreens / wEnemyScreens SCREENS_SPIKES: laid on the side that will
  -- be switching INTO them.
  self.spikes = { player = false, enemy = false }
  -- The other two wPlayerScreens bits, with their five-turn counts
  -- (BattleCommand_Screen / HandleScreens): SIDE state like the spikes, so
  -- a switch does not take a screen down.
  self.screens = { player = {}, enemy = {} }

  -- The side substrate Gen 1's battle carries (src/battle/BattleState.lua's
  -- own self.sides): index 1 is the player's side, index 2 the foe's, and the
  -- engine writes nothing into screens/hazards/tokens -- they are the stable
  -- shape mods hang their own state on.  This is what battle.battler_switched
  -- names as `side`, so a mod reading payload.side.index reads the same number
  -- it does on Red.  `battlers[1]` is kept current by Battle:syncSides.
  self.sides = Battle.newSides()

  -- InitEnemyTrainer's tail: a Gym Leader (or an Elite Four member, or the
  -- Champion, or Red -- IsGymLeader's list is longer than its name) raises the
  -- happiness of every party mon still standing, BEFORE the first turn.  You
  -- are paid for showing up, not for winning.
  if self.trainer and Battle.isGymLeader(self.trainer.class) then
    Happiness.changeParty(self.party, "GYMBATTLE")
  end
  -- battle.started, the payload BattleState:enter emits on Gen 1: `kind` is the
  -- battle's shape, `trainerId` the class the fight is against (nil for a wild
  -- one), and `species` / `level` the mon standing opposite.  The battle object
  -- differs between generations and always has -- a mod reads it through the
  -- fields it knows, which is why the four scalars are here at all.
  Runtime.emit("battle.started", {
    battle = self, kind = self.wild and "wild" or "trainer",
    trainerId = self.trainer
      and (self.trainer.classId or self.trainer.class) or nil,
    species = self.enemy and self.enemy.species,
    level = self.enemy and self.enemy.level,
    -- Gen 2 additions: the wBattleType byte (BATTLETYPE_FORCESHINY and friends,
    -- or "fish"), and the roster this trainer brought, held items and all.
    battleType = self.battleType,
    trainer = self.trainer,
  })
  return self
end

-- The side substrate, kept next to the stage table it sits beside in the
-- constructor.  Built lazily by Battle:syncSides as well, so a caller that
-- assembles a battle by hand (the tests drive resolveFaints against a stub)
-- still gets the shape battle.battler_switched reports.
function Battle.newSides()
  return {
    { index = 1, key = "player", battlers = {}, screens = {}, hazards = {},
      tokens = {} },
    { index = 2, key = "enemy", battlers = {}, screens = {}, hazards = {},
      tokens = {} },
  }
end

function Battle.newStages()
  return {
    attack = 0, defense = 0, speed = 0,
    specialAttack = 0, specialDefense = 0,
    accuracy = 0, evasion = 0,
  }
end

-- The first party member that can actually FIGHT.
--
-- An EGG has HP and is not fainted, and nothing here used to exclude it -- so
-- carrying the Togepi egg (which the game hands you in Violet City and expects
-- you to keep until it hatches) meant it counted as a battler: the wipe check
-- never fired while the egg was intact, and the game asked you to send an egg
-- out against Morty.  The cart cannot: CheckCurPartyMon and the switch menu
-- both refuse an egg, and `wPartyCount` minus the eggs is what decides a
-- whiteout.
function Battle.firstHealthy(party)
  for index, mon in ipairs(party or {}) do
    if not mon.isEgg and (mon.hp or 0) > 0 then return index end
  end
  return nil
end

function Battle:emit(event)
  self.events[#self.events + 1] = event
  return event
end

-- Drain the event queue; the screen calls this each time it finishes showing
-- what it already had.
function Battle:takeEvents()
  local out = self.events
  self.events = {}
  return out
end

-- The one place a battle is decided, so battle.ended is raised exactly once
-- however many times the faint sweep runs over an already-finished battle.
-- Gen 1's payload is { battle, result }; `result` here is the same string
-- Battle.outcome carries, with Gen 2's own two extra outcomes ("fled" for
-- WildFled_EnemyFled, "draw" for a Bug Contest that ran out of balls) beside
-- Gen 1's win / lose / run / caught.
function Battle:endBattle(outcome)
  self.over = true
  self.outcome = outcome
  -- Whoever is still standing leaves the battle as itself: the copy Transform
  -- wrote is battle ram on the cart and CleanUpBattleRAM takes it.  The screen
  -- reaches the same restore through Battle:clearAllVolatiles, but a caller
  -- that ends a battle without a screen (every headless test, and the scripted
  -- exits) has to leave the party clean too -- Battle.party IS save.party.
  self:untransform(self.player)
  self:untransform(self.enemy)
  if self.endedEmitted then return end
  self.endedEmitted = true
  Runtime.emit("battle.ended", { battle = self, result = outcome })
end

-- Never-nil BattleRandom (0..n-1) for call sites that want the cart byte.
-- `battle.rng` is the Gen 1 / love.math view of the same stream.
function Battle:roller()
  if not self.rollerFn then
    self.rollerFn = function(n) return rand(self.random, n) end
  end
  return self.rollerFn
end

function Battle:sideOf(mon)
  return (mon == self.player) and "player" or "enemy"
end

-- Point each side record at whoever is standing on it, the way Gen 1's
-- BattleState:syncSides does.
function Battle:syncSides()
  self.sides = self.sides or Battle.newSides()
  self.sides[1].battlers[1] = self.player
  self.sides[2].battlers[1] = self.enemy
end

-- The side RECORD a mon is on (Gen 1's payload shape) rather than the string
-- key the Gen 2 engine indexes its own tables with.
function Battle:sideRecord(mon)
  self:syncSides()
  return (mon == self.player) and self.sides[1] or self.sides[2]
end

function Battle:monName(mon)
  if not mon then return "?" end
  return mon.nickname or mon.name or mon.species or "?"
end

function Battle:moveDef(moveId)
  return self.data.moves and self.data.moves[moveId] or nil
end

-- The board as AI_Smart reads it.  Every field is optional on the AI side, so
-- a value the engine does not model simply never fires its branch.
-- CheckPlayerMoveTypeMatchups (engine/battle/ai/switch.asm).
-- wEnemyAISwitchScore starts at BASE_AI_SWITCH_SCORE and walks down one for
-- every super-effective move the player has ACTUALLY shown against whatever the
-- AI has out; below that base means the player is winning the type war.  Both
-- the switch layer and four AI_Smart handlers (ForceSwitch, BatonPass,
-- PerishSong, MeanLook) read this one number, so it lives in one place and the
-- two cannot drift apart.
function Battle:playerMatchupScore()
  local score = Ai.BASE_SWITCH_SCORE
  local enemyTypes = (self:speciesDef(self.enemy) or {}).types
    or self.enemy.types or {}
  local matchups = self.data.type_chart and self.data.type_chart.matchups
  for _, id in ipairs(self:volatile(self.player).usedMoves or {}) do
    local def = self:moveDef(id)
    if def and (def.power or 0) > 0
        and Damage.typeMultiplier(def.type, enemyTypes, matchups) > 10 then
      score = score - 1
    end
  end
  return score
end

-- engine/battle/hidden_power.asm's type table, as the sixteen values
-- (Atk & 3) * 4 + (Def & 3) can take.  The routine's `inc a` past NORMAL, its
-- second `inc a` past BIRD and its `add UNUSED_TYPES_END - UNUSED_TYPES`
-- collapse to exactly this list, in this order.
Battle.HIDDEN_POWER_TYPES = {
  "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
  "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC_TYPE", "ICE", "DRAGON", "DARK",
}

-- HiddenPowerDamage: Hidden Power's real base power (31..70) and type come from
-- the user's DVs, not from the move table's stub.  Returns nil, nil when the
-- mon carries no DVs to read, which is the only honest answer for a mon the
-- fixtures built by hand.
--
-- The power byte takes the TOP bit of each of the four DVs (`and %1000`), NOT
-- the low bits Mon.hpDV builds the HP DV out of, so this cannot borrow that
-- helper.
function Battle:hiddenPower(mon)
  local dvs = mon and mon.dvs
  if not dvs then return nil, nil end
  local function high(value) return math.floor((value or 0) / 8) % 2 end
  local bits = high(dvs.attack) * 8 + high(dvs.defense) * 4
    + high(dvs.speed) * 2 + high(dvs.special)
  local power = math.floor((bits * 5 + (dvs.special or 0) % 4) / 2) + 31
  local index = ((dvs.attack or 0) % 4) * 4 + ((dvs.defense or 0) % 4)
  return power, Battle.HIDDEN_POWER_TYPES[index + 1]
end

-- Everything the AI_Smart layer reads, gathered once per enemy decision.  A
-- field the engine cannot answer honestly is simply left nil, and the matching
-- handler branch never fires: see the "read but never produced" list in Ai.lua.
function Battle:smartAiState()
  local enemyState = self:volatile(self.enemy)
  local playerState = self:volatile(self.player)
  local chart = self.data.type_chart
  local typeTable = chart and chart.types
  local matchups = chart and chart.matchups

  -- AIHasMoveEffect walks the enemy's list by effect; AIHasMoveInArray (the
  -- weather moves) matches raw move IDS, so both shapes are built here.
  local known, ids = {}, {}
  for _, move in ipairs(self.enemy.moves or {}) do
    local def = self:moveDef(move.id)
    if def and def.effect then known[def.effect] = true end
    ids[move.id] = true
  end

  -- wPlayerUsedMoves, read three ways: AI_Smart_Counter counts the physical
  -- damaging entries, AI_Smart_MirrorCoat the special ones, and
  -- AI_Smart_RazorWind wants the EFFECTS behind them (it dismisses itself on
  -- EFFECT_PROTECT).
  local physical, special = 0, 0
  local usedEffects = {}
  for _, id in ipairs(playerState.usedMoves or {}) do
    local def = self:moveDef(id)
    if def then
      if def.effect then usedEffects[def.effect] = true end
      if (def.power or 0) > 0 then
        if Damage.isPhysical(def.type, typeTable) then
          physical = physical + 1
        else
          special = special + 1
        end
      end
    end
  end

  local enemyTypes = (self:speciesDef(self.enemy) or {}).types
    or self.enemy.types or {}
  local playerTypes = (self:speciesDef(self.player) or {}).types
    or self.player.types or {}
  -- `cp SPECIAL` against wBattleMonType1/2: AI_Smart_SpDefenseUp2 and
  -- AI_Smart_Curse ask the same question, "is EITHER player type special".
  -- nil rather than false when the types are unknown, so the branch stays shut.
  local playerSpecialType
  for _, name in ipairs(playerTypes) do
    if not Damage.isPhysical(name, typeTable) then playerSpecialType = true end
  end

  -- The player's own ramp.  The port keeps ONE counter pair for Rollout and
  -- Fury Cutter, so the loaded move is what tells wPlayerFuryCutterCount from
  -- SUBSTATUS_ROLLOUT apart.
  local rampDef = playerState.rampMove and self:moveDef(playerState.rampMove)
  local rampEffect = rampDef and rampDef.effect

  -- wLastPlayerCounterMove: what Spite drains, what Mimic would copy (the cart
  -- sets hBattleTurn to 1, so the matchup defends with the PLAYER's own types)
  -- and what Mirror Coat's tail tests.
  local lastId = playerState.lastMove
  local lastDef = lastId and self:moveDef(lastId)
  local lastEntry = lastId and self:findMove(self.player, lastId)

  -- AI_Smart_LockOn's `.checkmove`: a move worth aiming, meaning one under
  -- `71 percent - 1` ($b4) raw accuracy whose type is at least neutral against
  -- the player.  Explicitly false when the loop found nothing, since that is
  -- the case the cart discourages on.
  local aimable = false
  for _, move in ipairs(self.enemy.moves or {}) do
    local def = self:moveDef(move.id)
    if def and (def.accuracyRaw or 255) < 0xb4
        and Damage.typeMultiplier(def.type, playerTypes, matchups) >= 10 then
      aimable = true
    end
  end

  -- AI_Smart_HealBell ORs the status byte of every unfainted mon in wOTParty,
  -- the active one included.
  local partyStatus = false
  for _, mon in ipairs(self.enemyParty or {}) do
    if (mon.hp or 0) > 0 and mon.status then partyStatus = true end
  end

  -- FindAliveEnemyMons and AICheckLastPlayerMon: both skip the mon that is out
  -- and ask whether anything is left behind it.
  local enemyHasBench = false
  for index, mon in ipairs(self.enemyParty or {}) do
    if index ~= self.enemyIndex and (mon.hp or 0) > 0 then
      enemyHasBench = true
    end
  end
  local playerLastMon = true
  for index, mon in ipairs(self.party or {}) do
    if index ~= self.playerIndex and (mon.hp or 0) > 0 then
      playerLastMon = false
    end
  end

  local hiddenPowerPower, hiddenPowerType = self:hiddenPower(self.enemy)

  return {
    enemyHp = self.enemy.hp,
    enemyMaxHp = self.enemy.maxHp or (self.enemy.stats or {}).hp,
    playerHp = self.player.hp,
    playerMaxHp = self.player.maxHp or (self.player.stats or {}).hp,
    enemyLevel = self.enemy.level, playerLevel = self.player.level,
    enemyFaster = self:effectiveSpeed(self.enemy)
      > self:effectiveSpeed(self.player),
    enemyStatus = self.enemy.status, playerStatus = self.player.status,
    enemyTurns = enemyState.turnsTaken or 0,
    playerTurns = playerState.turnsTaken or 0,
    stages = self.stages.enemy, playerStages = self.stages.player,
    playerToxic = self.player.status == "toxic",
    playerLeechSeed = playerState.leechSeed,
    playerCharged = playerState.chargeMove ~= nil,
    playerFlying = playerState.vanished,
    playerLastMove = lastId,
    -- wPlayerSubStatus5 & SUBSTATUS_LOCK_ON: the enemy's OWN Lock-On, since
    -- BattleCommand_LockOn sets the bit on the target it was aimed at.
    playerLockOn = playerState.lockOn or nil,
    playerPhysicalMoves = physical,
    enemyRage = enemyState.rage,
    enemyRageCount = enemyState.rageCount,
    enemyProtectCount = enemyState.protectCount,
    enemyFuryCutterCount = enemyState.rampCount,
    enemyConfused = enemyState.confuseCount ~= nil,
    -- wPlayerWrapCount and SUBSTATUS_CURSE, live now that the trap and
    -- curse volatiles are modelled.
    playerTrapped = ((playerState.wrapCount or 0) > 0) or nil,
    playerCursed = playerState.cursed or nil,
    knownEffects = known,
    enemyMoveIds = ids,

    -- Types, IN SLOT ORDER: the weather handlers read slot 1 before slot 2 and
    -- a swapped pair scores differently, so this is never sorted.
    enemyTypes = enemyTypes,
    playerTypes = playerTypes,
    playerSpecialType = playerSpecialType,

    playerMatchupScore = self:playerMatchupScore(),
    playerSpecialMoves = special,
    playerUsedEffects = usedEffects,

    -- SUBSTATUS_FLYING and SUBSTATUS_UNDERGROUND split apart.  Both Fly and Dig
    -- carry EFFECT_FLY in Gen 2, so the vanish flag alone is ambiguous and the
    -- stored move is what separates them; playerFlying above stays the combined
    -- mask AI_Smart_Fly and AI_Smart_FutureSight want.
    playerFlyingUp = (playerState.vanished
      and playerState.chargeMove == "FLY") or nil,
    playerUnderground = (playerState.vanished
      and playerState.chargeMove == "DIG") or nil,

    playerFuryCutter = (rampEffect == "EFFECT_FURY_CUTTER")
      and (playerState.rampCount or 0) or nil,
    playerRollout = (rampEffect == "EFFECT_ROLLOUT") or nil,

    playerLastMovePp = lastEntry and lastEntry.pp or nil,
    playerLastMoveMatchup = lastDef
      and Damage.typeMultiplier(lastDef.type, playerTypes, matchups) or nil,
    playerLastMoveSpecial = lastDef ~= nil
      and not Damage.isPhysical(lastDef.type, typeTable) or nil,
    playerLastMon = playerLastMon,

    enemyToxic = self.enemy.status == "toxic",
    enemyLeechSeed = enemyState.leechSeed,
    enemySpikes = self.spikes and self.spikes.enemy or nil,
    enemyPerishCount = enemyState.perish,
    -- wEnemyMonStatus & SLP_MASK, on the cart's own scale: Battle:canAct
    -- decrements statusTurns and clears the status at zero, so a value of 1 is
    -- exactly the `cp 1` last sleeping turn.  Always a number, never nil, or
    -- AI_Smart_Snore scores nothing at all.
    enemySleepTurns = (self.enemy.status == "sleep")
      and (self.enemy.statusTurns or 0) or 0,
    enemyPartyStatus = partyStatus,
    enemyHasBench = enemyHasBench,
    enemyInaccurateEffectiveMove = aimable,

    hiddenPowerPower = hiddenPowerPower,
    hiddenPowerMatchup = hiddenPowerType
      and Damage.typeMultiplier(hiddenPowerType, playerTypes, matchups) or nil,

    weather = self.weather,
  }
end

-- Every move id the cache knows, for Metronome.  Sorted so the pick is
-- reproducible from a seeded roll rather than from Lua's hash order.
function Battle:moveOrder()
  if self._moveOrder then return self._moveOrder end
  local out = {}
  for id, def in pairs(self.data.moves or {}) do
    if type(def) == "table" and def.power ~= nil then out[#out + 1] = id end
  end
  table.sort(out)
  self._moveOrder = out
  return out
end

function Battle:speciesDef(mon)
  return mon and self.data.pokemon and self.data.pokemon[mon.species] or nil
end

-- One badge, read the way FieldMoves.hasBadge reads it: save.player.badges /
-- save.player.kantoBadges keyed by name, with the bit position accepted as a
-- fallback key so the two readers cannot disagree about who owns what.
function Battle:hasBadge(store, badge)
  local player = self.save and self.save.player
  local owned = player and player[store]
  if type(owned) ~= "table" then return false end
  if owned[badge] then return true end
  local order = store == "kantoBadges" and Battle.KANTO_BADGE_ORDER
    or Battle.JOHTO_BADGE_ORDER
  for index, name in ipairs(order) do
    if name == badge then return owned[index] == true end
  end
  return false
end

-- BoostStat (engine/battle/core.asm:6590): raise a stat by 1/8, capped at
-- MAX_STAT_VALUE (999).  The eighth is a plain shift, so a stat under 8
-- gains nothing.
function Battle.boostStat(value)
  return math.min(999, value + math.floor(value / 8))
end

-- BadgeStatBoosts' buggy tail: the Special Defense re-check does `srl a`
-- assuming `a` still holds the badge bits, but when GlacierBadge fired for
-- Special Attack the preceding BoostStat overwrote `a` with its cap-check
-- arithmetic.  So with Glacier owned, whether SpDef is ALSO boosted depends
-- on the boosted Special Attack value:
--   * at or past the 999 cap, `a` leaves as LOW(999) = $e7, odd: boosted
--   * otherwise `a` is high(v) - 3 - borrow, where the borrow is set when
--     low(v) < LOW(999); the shifted-out low bit decides
-- (pokegold's own comment at core.asm:6584 marks the check buggy.)
function Battle.glacierBoostsSpDef(boostedSpAtk)
  local v = boostedSpAtk or 0
  if v >= 999 then return true end
  local borrow = (v % 256) < 231 and 1 or 0
  local a = (math.floor(v / 256) - 3 - borrow) % 256
  return a % 2 == 1
end

-- The stat a hit actually reads: the party stat, plus the player-side badge
-- boost.  BadgeStatBoosts runs against wBattleMon (the PLAYER's active mon
-- only, never the enemy and never in link), so the boost is applied here at
-- read time rather than mutating mon.stats, which IS the party slot in this
-- port and must survive the battle unboosted.
function Battle:battleStat(mon, key)
  local value = (mon.stats or {})[key] or 1
  if mon ~= self.player then return value end
  local badge = Battle.BADGE_STAT_BOOSTS[key]
  if badge and self:hasBadge("badges", badge) then
    return Battle.boostStat(value)
  end
  if key == "specialDefense" and self:hasBadge("badges", "GLACIER") then
    local spAtk = Battle.boostStat((mon.stats or {}).specialAttack or 1)
    if Battle.glacierBoostsSpDef(spAtk) then
      return Battle.boostStat(value)
    end
  end
  return value
end

-- DoBadgeTypeBoosts (engine/battle/misc.asm:146): player's turn only, and
-- the first owned badge whose BadgeTypeBoosts row matches the move's type
-- boosts the damage.  Each type appears once, so this is a plain scan.
function Battle:badgeTypeBoost(attacker, moveType)
  if attacker ~= self.player or not moveType then return false end
  for _, row in ipairs(Battle.BADGE_TYPE_BOOSTS) do
    if row.type == moveType then
      return self:hasBadge(row.store, row.badge)
    end
  end
  return false
end

-- The screen guarding this defender against this KIND of hit, the way
-- DamageStats consults wEnemyScreens/wPlayerScreens: Reflect doubles the
-- defending side's Defense against a physical move, Light Screen its
-- Special Defense against a special one.
function Battle:screenActive(defender, physical)
  local side = self.screens and self.screens[self:sideOf(defender)]
  if not side then return false end
  local turns = physical and (side.reflect or 0) or (side.lightScreen or 0)
  return turns > 0
end

-- GetUserItem's b/c pair: the held effect id and its parameter out of
-- ItemAttributes, or nil/0 for an empty hand.
--
-- held_item.trigger, the most load-bearing of the names Gen 2 invents: Gen 1
-- has no held items at all, so there is no name to share.  It wraps this
-- function rather than each of the eight places an item acts, because on the
-- cart those eight places are all one routine -- GetUserItem / GetOpponentItem
-- loading b and c and the caller comparing b against the HELD_* it cares about
-- -- and `trigger` says which comparison is about to happen:
--
--   "priority"  DetermineMoveOrder's .equal_priority (Quick Claw)
--   "damage"    DamageCalc's crit ladder and .DoneItem type boost (Scope Lens,
--               the HELD_<TYPE>_BOOST family)
--   "endure"    the 1 HP clamp (Focus Band)
--   "flinch"    the post-hit flinch roll (King's Rock)
--   "accuracy"  BattleCommand_CheckHit's .BrightPowder
--   "confuse"   the confusion gate (HELD_PREVENT_CONFUSE)
--   "residual"  Battle:tickHeldItem, the end-of-turn Leftovers/Berry/cure arm
--   "check"     any other read; nothing in the engine passes this today
--
-- ctx: battle, mon, item (the item id), def (its record), effect, parameter,
-- trigger.  Vanilla answers `ctx.effect, ctx.parameter`, so a chain that wants
-- the item to do nothing at this trigger returns nil and one that wants a
-- different behaviour returns another HELD_* name -- the call sites all
-- compare against a name, so substitution is the whole mechanism.  A returned
-- effect that is not a string is read as "no effect"; the parameter falls back
-- to the item's own rather than to 0, because 0 is a meaningful parameter
-- (a 0% BrightPowder) and a mod that only wanted to rename the effect should
-- not silently lose the number.
function Battle:heldEffect(mon, trigger)
  local def = self:itemDef(mon and mon.item)
  local effect = def and def.heldEffect or nil
  local parameter = (def and def.heldParameter) or 0
  if not Runtime.wantsHook("held_item.trigger") then return effect, parameter end
  local hookedEffect, hookedParameter = Runtime.call("held_item.trigger",
    function(c) return c.effect, c.parameter end,
    { battle = self, mon = mon, item = mon and mon.item, def = def,
      effect = effect, parameter = parameter, trigger = trigger or "check" })
  if type(hookedEffect) ~= "string" then return nil, 0 end
  return hookedEffect, tonumber(hookedParameter) or parameter
end

-- Effective Speed for ordering: stat stages, then the paralysis quarter.
function Battle:effectiveSpeed(mon)
  local stages = self.stages[self:sideOf(mon)]
  local speed = Damage.applyStage(self:battleStat(mon, "speed"), stages.speed)
  return Battle.statusPenaltyFor(self.data, mon, "speed", speed)
end

-- DetermineMoveOrder: faster side first, a coin flip on a tie.  Priority comes
-- from the move (Quick Attack and friends) and beats Speed outright.
function Battle:orderOf(playerMove, enemyMove)
  local playerPriority = self:movePriority(playerMove)
  local enemyPriority = self:movePriority(enemyMove)
  if playerPriority ~= enemyPriority then
    return playerPriority > enemyPriority and "player" or "enemy"
  end
  -- HELD_QUICK_CLAW (engine/battle/core.asm `.equal_priority`): consulted
  -- only once priority ties, ahead of the Speed compare.  One byte against
  -- the item's parameter (60 -> 60/256).  When both sides hold one the
  -- ENEMY's roll goes first, exactly as the non-link `.both_have_quick_claw`
  -- arm orders them.
  local playerEffect, playerParam = self:heldEffect(self.player, "priority")
  local enemyEffect, enemyParam = self:heldEffect(self.enemy, "priority")
  local playerClaw = playerEffect == "HELD_QUICK_CLAW"
  local enemyClaw = enemyEffect == "HELD_QUICK_CLAW"
  if playerClaw and enemyClaw then
    if rand(self.random, 256) < enemyParam then return "enemy" end
    if rand(self.random, 256) < playerParam then return "player" end
  elseif playerClaw then
    if rand(self.random, 256) < playerParam then return "player" end
  elseif enemyClaw then
    if rand(self.random, 256) < enemyParam then return "enemy" end
  end
  local playerSpeed = self:effectiveSpeed(self.player)
  local enemySpeed = self:effectiveSpeed(self.enemy)
  if playerSpeed ~= enemySpeed then
    return playerSpeed > enemySpeed and "player" or "enemy"
  end
  return rand(self.random, 2) == 0 and "player" or "enemy"
end

-- Gen 2 priority moves.  data/moves/effects_priorities.asm keys off the move
-- *effect*, so a modded move inherits the priority of whatever it copies.
Battle.PRIORITY = {
  EFFECT_PRIORITY_HIT = 1,   -- Quick Attack, Mach Punch
  EFFECT_PROTECT = 3,
  EFFECT_ENDURE = 3,
  EFFECT_COUNTER = -1,
  EFFECT_MIRROR_COAT = -1,
  EFFECT_VITAL_THROW = -1,
}

function Battle:movePriority(moveId)
  local def = self:moveDef(moveId)
  return (def and Battle.PRIORITY[def.effect]) or 0
end

-- Can this mon act?  Returns true, or false plus the message the cart prints.
function Battle:canAct(mon)
  local name = self:monName(mon)
  -- SUBSTATUS_RECHARGE, and it is checked BEFORE status: CheckPlayerTurn reads
  -- it first, clears it, prints MustRechargeText and jumps to EndTurn, so a mon
  -- that is both recharging and asleep spends this turn recharging.
  local vol = self:volatile(mon)
  if vol.recharge then
    vol.recharge = nil
    self:emit({ kind = "message", text = name .. " must recharge!" })
    return false
  end
  -- The status arms, through the merged record.  beforeMovePriority is what
  -- puts sleep (40) and freeze (30) ahead of the flinch/confusion block and
  -- paralysis (10) after it, the way CheckPlayerTurn orders them; the high
  -- arms answer for the whole turn (a mon that woke up does not then get
  -- asked about flinching) and the low one falls through when it lets the
  -- move go.
  local record = Battle.statusRecordFor(self.data, mon.status)
  local beforeMove = record and record.beforeMove
  if beforeMove
      and (record.beforeMovePriority or 0) > Battle.VOLATILE_PRIORITY then
    return beforeMove(self, mon, name) and true or false
  end
  -- SUBSTATUS_FLINCHED, read and cleared right after the freeze check
  -- (CheckPlayerTurn / CheckEnemyTurn `.not_frozen`).  Set this turn by the
  -- opponent's HELD_FLINCH item (King's Rock) -- and the EFFECT_FLINCH_HIT
  -- moves once they write the same flag.
  if vol.flinched then
    vol.flinched = nil
    self:emit({ kind = "message", text = name .. " flinched!" })
    return false
  end
  -- SUBSTATUS_CONFUSED (CheckPlayerTurn past `.not_flinched`): the count
  -- decrements FIRST and zero snaps out -- the mon still acts that turn.
  -- While it holds, one byte under 50 percent + 1 spends the turn on
  -- HitConfusion's self-hit instead.
  if vol.confuseCount then
    vol.confuseCount = vol.confuseCount - 1
    if vol.confuseCount <= 0 then
      vol.confuseCount = nil
      self:emit({ kind = "message", text = name .. "'s confused no more!" })
    else
      self:emit({ kind = "message", text = name .. " is confused!" })
      if rand(self.random, 256) < 128 then
        self:confusionSelfHit(mon)
        return false
      end
    end
  end
  if beforeMove then
    return beforeMove(self, mon, name) and true or false
  end
  return true
end

-- STRUGGLE, the move a mon with nothing left to spend falls back to
-- (engine/battle/core.asm `.CheckPlayerHasUsableMoves` for the player and
-- `.struggle` for the enemy).  It lives in the move table like any other move
-- -- typeless-in-practice NORMAL, 50 power, EFFECT_RECOIL_HIT -- and is
-- deliberately NOT in anyone's move list, which is why useMove's PP guard is
-- written `if move and ...`: findMove returns nil for it and the guard is
-- skipped rather than tripped.
Battle.STRUGGLE = "STRUGGLE"

-- .LockOn's three exceptions against a flying target
-- (engine/battle/effect_commands.asm:1683-1688).
Battle.LOCK_ON_GROUND_MOVES = { EARTHQUAKE = true, FISSURE = true,
  MAGNITUDE = true }

-- .CheckPlayerHasUsableMoves skips the disabled slot (engine/battle/core.asm:5290-5305).
function Battle:hasUsableMoves(mon)
  local disabled = mon and mon.volatile and mon.volatile.disabled
  for _, move in ipairs((mon and mon.moves) or {}) do
    if (move.pp or 0) > 0 and move.id ~= disabled then return true end
  end
  return false
end

function Battle:findMove(mon, moveId)
  for _, move in ipairs(mon.moves or {}) do
    if move.id == moveId then return move end
  end
  return nil
end

-- A "state" is the per-mon volatile bookkeeping a turn needs: the charge a
-- two-turn move is midway through, a Substitute's remaining HP, the counters
-- Rollout and Fury Cutter ramp on, and what the mon took this turn so Counter
-- and Mirror Coat have something to answer.  It hangs off the mon rather than
-- the battle so a switch takes it away, which is what the cart does.
function Battle:volatile(mon)
  mon.volatile = mon.volatile or {}
  return mon.volatile
end

-- Clears everything a switch clears (ResetBattleParticipants / SwitchOutMon).
--
-- SwitchOutMon reloads the battle struct from the party slot, which is what
-- takes a Transform down with the switch; the port's one-table-per-mon shape
-- makes that a restore rather than a reload (Battle:untransform).  It has to
-- happen HERE and not only at the switch sites, because CleanUpBattleRAM at
-- the end of the battle runs through Battle:clearAllVolatiles -- and for a
-- wild catch that table is already sitting in the player's party.
function Battle:clearVolatile(mon)
  if not mon then return end
  self:untransform(mon)
  mon.volatile = nil
end

-- The cart keeps every substatus in battle RAM (wPlayerSubStatus1-5), which
-- NewBattleMonStatus zeroes at each send-out and CleanUpBattleRAM zeroes on
-- the way out of the battle.  This port hangs the same bookkeeping off the mon
-- record, and Battle.party IS save.party, so nothing a battle wrote may be
-- left on a party table: an X item's bit, a confusion count or a wrap counter
-- would otherwise be written to the save file and read back by the next
-- battle, where DIRE HIT is then refused forever as an already-set bit.
function Battle:clearAllVolatiles()
  for _, mon in ipairs(self.party or {}) do self:clearVolatile(mon) end
  for _, mon in ipairs(self.enemyParty or {}) do self:clearVolatile(mon) end
  self:clearVolatile(self.player)
  self:clearVolatile(self.enemy)
end

-- A battle.damage chain may be a Gen 1 mod, which returns Gen 1's info table
-- ({ crit, typeMult }) rather than Gen 2's ({ critical, effectiveness, ... }).
-- The two names mean the same thing in both generations, so read either --
-- src/battle/gen2/Damage.lua answers to both for the same reason.
local function normalizeDamageInfo(info)
  if type(info) ~= "table" then return info end
  if info.critical == nil and info.crit ~= nil then info.critical = info.crit end
  if info.effectiveness == nil and info.typeMult ~= nil then
    info.effectiveness = info.typeMult
  end
  return info
end

-- One damaging hit.  Returns the damage actually dealt (0 when the move did
-- not connect at all), so recoil, drain and Counter all read the same number.
function Battle:hitOnce(attacker, defender, def, opts)
  opts = opts or {}
  local attackerStages = self.stages[self:sideOf(attacker)]
  local defenderStages = self.stages[self:sideOf(defender)]
  local types = self.data.type_chart and self.data.type_chart.types
  local matchups = self.data.type_chart and self.data.type_chart.matchups

  local heldEffect, heldParam = self:heldEffect(attacker, "damage")
  -- BattleCommand_Critical: SUBSTATUS_FOCUS_ENERGY (Focus Energy or a
  -- DIRE HIT) and HELD_CRITICAL_UP (Scope Lens) each raise the ladder a
  -- rung; a high-crit move raises it two.
  local criticalLevel = Damage.criticalLevel({
    highCritMove = def.effect == "EFFECT_ALWAYS_CRIT",
    focusEnergy = self:volatile(attacker).focusEnergy,
    scopeLens = heldEffect == "HELD_CRITICAL_UP",
  })
  -- battle.crit, the same hook src/battle/Damage.lua calls on Gen 1, with the
  -- same ctx keys: a mod that forces or refuses criticals reads `attacker`,
  -- `moveId` and `highCrit` exactly where it did on Red.  `ruleset` has no Gen 2
  -- counterpart (Gold's engine IS the ruleset) so it is absent rather than
  -- invented, and `criticalLevel` is the Gen 2 addition -- the rung of
  -- data/battle/critical_hit_chances.asm this hit reached, which Gen 1's
  -- base-Speed derivation had no equivalent of.
  local critical
  if Runtime.wantsHook("battle.crit") then
    critical = Runtime.call("battle.crit", function(c)
      return Damage.rollCritical(c.criticalLevel, c.battle.random)
    end, { battle = self, attacker = attacker, moveId = opts.moveId or def.id,
           rng = self:roller(), random = self.random,
           highCrit = def.effect == "EFFECT_ALWAYS_CRIT",
           criticalLevel = criticalLevel })
  else
    critical = Damage.rollCritical(criticalLevel, self.random)
  end
  local attack = self:battleStat(attacker, "attack")
  -- Burn halves physical Attack (Gen 2 does this in DamageStats), off the
  -- status record's statPenalty.
  attack = Battle.statusPenaltyFor(self.data, attacker, "attack", attack)
  -- The HELD_<TYPE>_BOOST items (Charcoal, Mystic Water, ...): the item's
  -- parameter is the percent boost DamageCalc's .DoneItem applies when the
  -- held type matches the move's.  PSYCHIC's type id is PSYCHIC_TYPE in the
  -- port's chart, so the effect name is rebuilt from the move type.
  local itemBoost
  if def.type and heldEffect then
    local wanted = "HELD_" .. (def.type == "PSYCHIC_TYPE" and "PSYCHIC"
      or def.type) .. "_BOOST"
    if heldEffect == wanted then itemBoost = heldParam end
  end
  local calcOpts = {
    level = attacker.level or 1,
    power = opts.power or def.power,
    moveType = def.type,
    attacker = {
      attack = attack,
      specialAttack = self:battleStat(attacker, "specialAttack"),
      types = (self:speciesDef(attacker) or {}).types or attacker.types,
      stages = attackerStages,
    },
    defender = {
      defense = self:battleStat(defender, "defense"),
      specialDefense = self:battleStat(defender, "specialDefense"),
      types = (self:speciesDef(defender) or {}).types or defender.types,
      stages = defenderStages,
    },
    types = types,
    matchups = matchups,
    critical = critical,
    itemBoostPercent = itemBoost,
    -- DoWeatherModifiers, the first thing BattleCommand_Stab farcalls
    -- (effect_commands.asm:1254): rain boosts Water and cuts Fire, sun the
    -- reverse, and rain cuts Solarbeam by its EFFECT rather than its type.
    -- Scaled to the cart's tenths here so Damage.calc can apply it where the
    -- cart does, ahead of the badge boost, STAB, the type rows and the roll.
    weatherPercent = math.floor(
      Effects.weatherModifier(self.weather, def.type, def.effect) * 10),
    -- DoBadgeTypeBoosts, farcalled between the weather modifiers and STAB.
    badgeTypeBoost = self:badgeTypeBoost(attacker, def.type),
    -- SCREENS_REFLECT / SCREENS_LIGHT_SCREEN on the defending side double
    -- the matching defence (the crit exemption lives in Damage.calc).
    screen = self:screenActive(defender,
      Damage.isPhysical(def.type, types)),
    -- BattleCommand_DamageCalc's `srl c` (effect_commands.asm:2905-2913).
    defenseHalved = def.effect == "EFFECT_SELFDESTRUCT",
    random = self.random,
  }
  -- battle.damage, the same hook BattleState:computeDamage calls on Gen 1 and
  -- with the same ctx keys: `user`, `target`, `move` and the `opts` table the
  -- formula is actually run on, so a mod that edits c.opts (or returns its own
  -- number) works the same way it does on Red.  Gen 2's opts carry more than
  -- Gen 1's -- the split special stats live inside c.opts.attacker /
  -- c.opts.defender, and the weather, badge and held-item modifiers are there
  -- as their own fields.  `ruleset` is absent for the reason given on
  -- battle.crit above.  The ctx table is only built when a chain is installed,
  -- so a mod-free boot pays nothing.
  local damage, info
  if Runtime.wantsHook("battle.damage") then
    damage, info = Runtime.call("battle.damage", function(c)
      return Damage.calc(c.opts)
    end, { battle = self, user = attacker, target = defender, move = def,
           moveId = opts.moveId or def.id, opts = calcOpts,
           rng = self:roller(), random = self.random })
    info = normalizeDamageInfo(info) or { effectiveness = 10 }
    damage = damage or 0
  else
    damage, info = Damage.calc(calcOpts)
  end

  if info.effectiveness == 0 then
    -- BattleCommand_Stab's `.GotMatchup` arm writes wAttackMissed when the
    -- matchup byte is 0 (effect_commands.asm:1337), and `stab` runs ahead of
    -- `moveanim` in every damaging effect list (data/moves/effects.asm:5), so
    -- BattleCommand_MoveAnimNoSub's wAttackMissed early-out (:1958) turns an
    -- immune hit into MoveDelay and no animation at all.
    self:markMissed()
    self:emit({ kind = "message",
      text = "It doesn't affect " .. self:monName(defender) .. "..." })
    return 0, info
  end
  -- BattleCommand_FalseSwipe (engine/battle/move_effects/false_swipe.asm):
  -- wCurDamage is capped at the target's HP minus one before applydamage, so
  -- the move can never KO -- the clamp that makes it a safe catching tool
  -- against a mon (a roamer above all) a win would retire.
  if def.effect == "EFFECT_FALSE_SWIPE" and damage >= (defender.hp or 0) then
    damage = math.max(0, (defender.hp or 0) - 1)
  end
  return self:dealDamage(attacker, defender, damage, {
    critical = critical, effectiveness = info.effectiveness,
    -- Counter answers physical damage and Mirror Coat special, so what kind
    -- of hit this was has to be recorded with it.
    kind = Damage.isPhysical(def.type, types) and "physical" or "special",
    -- Carried only so battle.damage_dealt can name the move, the way Gen 1's
    -- EffectRegistry damage loop does.
    move = def, moveId = opts.moveId or def.id,
  }), info
end

-- Applies damage, routing it through the target's Substitute first: a
-- Substitute soaks the whole hit and breaks when it runs out
-- (BattleCommand_SubstituteFadeIfDead), so the mon behind it never loses HP.
function Battle:dealDamage(attacker, defender, damage, opts)
  opts = opts or {}
  damage = math.max(0, math.floor(damage or 0))
  local state = self:volatile(defender)
  if (state.substitute or 0) > 0 then
    local absorbed = math.min(state.substitute, damage)
    state.substitute = state.substitute - absorbed
    self:emit({ kind = "message",
      text = "The SUBSTITUTE took damage for " .. self:monName(defender) .. "!" })
    if state.substitute <= 0 then
      state.substitute = nil
      self:emit({ kind = "message",
        text = self:monName(defender) .. "'s SUBSTITUTE broke!" })
    end
    return absorbed
  end

  local defenderState = self:volatile(defender)
  -- Endure leaves the holder on one hit point, however big the hit was.
  -- BattleCommand_ApplyDamage calls BattleCommand_FalseSwipe unconditionally
  -- for the Endure bit and FalseSwipe clamps wCurDamage to MonHP - 1, so a mon
  -- braced at exactly 1 HP takes zero and still holds.
  -- HELD_FOCUS_BAND rides the same clamp: the band is only consulted once
  -- Endure is down, rolling one byte against the item parameter
  -- (30 -> 30/256) and reusing the False Swipe clamp on success.
  local endured, hungOn = false, false
  if defenderState.endure and damage >= (defender.hp or 0)
      and (defender.hp or 0) > 0 then
    damage = (defender.hp or 0) - 1
    endured = true
  elseif damage >= (defender.hp or 0) and (defender.hp or 0) > 0 then
    local effect, parameter = self:heldEffect(defender, "endure")
    if effect == "HELD_FOCUS_BAND"
        and rand(self.random, 256) < parameter then
      damage = (defender.hp or 0) - 1
      hungOn = true
    end
  end
  defender.hp = math.max(0, (defender.hp or 0) - damage)
  defenderState.tookThisTurn = (defenderState.tookThisTurn or 0) + damage
  defenderState.tookKind = opts.kind or "physical"
  -- Bide stores everything the user takes while it is counting down.
  if defenderState.bideTurns then
    defenderState.bideStored = (defenderState.bideStored or 0) + damage
  end
  self:emit({
    kind = "damage", side = self:sideOf(defender),
    amount = damage, hp = defender.hp, critical = opts.critical,
    effectiveness = opts.effectiveness,
  })
  if opts.critical then
    self:emit({ kind = "message", text = "A critical hit!" })
  end
  if opts.effectiveness and opts.effectiveness > 10 then
    self:emit({ kind = "message", text = "It's super effective!" })
  elseif opts.effectiveness and opts.effectiveness < 10 then
    self:emit({ kind = "message", text = "It's not very effective..." })
  end
  if endured then
    self:emit({ kind = "message",
      text = self:monName(defender) .. " endured the hit!" })
  elseif hungOn then
    -- HungOnText, named after the item the way the cart pipes it through
    -- wStringBuffer1.
    local def = self:itemDef(defender.item)
    self:emit({ kind = "message",
      text = self:monName(defender) .. " hung on with "
        .. ((def and def.name) or "FOCUS BAND") .. "!" })
  end
  -- SUBSTATUS_RAGE: being hit while raging raises the rager's Attack.
  if defenderState.rage and damage > 0 and (defender.hp or 0) > 0 then
    self:changeStage(defender, "attack", 1)
  end
  -- battle.damage_dealt, the payload src/battle/EffectRegistry.lua emits once
  -- per landed hit on Gen 1, guarded the same way so an unsubscribed boot
  -- builds nothing.  `typeMult` is the x10 type multiplier under Gen 1's name;
  -- Gen 2's own name for the same number is `effectiveness`, and both are here.
  -- `move` is nil for the damage no move owns (Counter's answer, Future Sight's
  -- delayed hit, spikes), which is a Gen 2 shape Gen 1 has no site for.
  if Runtime.wants("battle.damage_dealt") then
    Runtime.emit("battle.damage_dealt", {
      battle = self, user = attacker, target = defender,
      move = opts.move, moveId = opts.moveId,
      damage = damage, crit = opts.critical or false,
      typeMult = opts.effectiveness or 10,
      -- Gen 2 additions: which side took it and whether the hit was physical
      -- or special, which is what Counter and Mirror Coat answer.
      effectiveness = opts.effectiveness or 10,
      side = self:sideOf(defender), kind = opts.kind,
    })
  end
  return damage
end

function Battle:heal(mon, amount, opts)
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 1
  local before = mon.hp or 0
  mon.hp = math.min(maxHp, before + math.max(0, math.floor(amount or 0)))
  local healed = mon.hp - before
  if healed > 0 then
    self:emit({ kind = "heal", side = self:sideOf(mon), amount = healed,
      hp = mon.hp, anim = opts and opts.anim })
  end
  return healed
end

-- move_effects/selfdestruct.asm:6-12: the user's status and both HP bytes are
-- zeroed, and the user's Leech Seed goes with them.
function Battle:selfdestructUser(attacker)
  local lost = attacker.hp or 0
  attacker.status, attacker.statusTurns = nil, nil
  attacker.toxicCounter = nil
  attacker.hp = 0
  self:volatile(attacker).leechSeed = nil
  -- The move carries ONE after-anim for the whole thing
  -- (move_effects/selfdestruct.asm:2-3), and the target's hit already plays it.
  self:emit({ kind = "damage", side = self:sideOf(attacker),
    amount = lost, hp = 0, anim = false })
end

-- One stat change, with the cart's own message (or its refusal).
function Battle:changeStage(target, stat, stages)
  local applied = Effects.applyStage(self.stages[self:sideOf(target)], stat,
    stages)
  local name = self:monName(target)
  if not applied then
    -- WontRiseAnymoreText / WontDropAnymoreText (data/text/battle.asm:718-732).
    self:emit({ kind = "message", text = ("%s's %s won't %s anymore!"):format(
      name, Effects.STAT_NAMES[stat] or stat,
      stages > 0 and "rise" or "drop") })
    return false
  end
  self:emit({ kind = "stage", side = self:sideOf(target), stat = stat,
    stages = applied, text = Effects.stageMessage(name, stat, applied) })
  return true
end

-- wAttackMissed, modelled on the event the screen animates off.  Every path
-- that sets it (CheckHit's .Miss arms and the effect commands' own `.failed`
-- tails, which reach AnimateFailedMove: a delay and no animation) marks the
-- move event, and the screen skips the attack animation for a marked one --
-- BattleCommand_MoveAnimNoSub, engine/battle/effect_commands.asm:1958.
function Battle:markMissed()
  if self.moveEvent then self.moveEvent.missed = true end
end

-- engine/battle/effect_commands.asm:3615
Battle.AI_FAIL_STATUSES = {
  sleep = true, poison = true, toxic = true, paralyze = true,
}

-- engine/battle/effect_commands.asm:3615
function Battle:aiRandomFail(attacker, defender)
  if self:sideOf(attacker) ~= "enemy" then return false end
  if self:volatile(defender).lockOn then return false end
  return rand(self.random, 256) < 64
end

-- One attack, start to finish.
function Battle:useMove(attacker, defender, moveId)
  local move = self:findMove(attacker, moveId)
  local def = self:moveDef(moveId)
  local name = self:monName(attacker)
  local state = self:volatile(attacker)
  -- wAttackMissed is per-move: BattleTurn's ResetTurn clears it before the
  -- effect list runs, so nothing a previous move set can reach this one.
  self.moveEvent = nil
  if not def then
    self:emit({ kind = "message", text = name .. " has no move to use!" })
    return
  end

  -- A mon locked into the second half of a two-turn move spends no PP and
  -- makes no new choice: it just lands the stored attack.
  local charging = state.chargeMove == moveId
  if charging then
    state.chargeMove = nil
    state.vanished = nil
  end

  -- BattleCommand_CheckRampage (effect_commands.asm:4851) is the FIRST command
  -- in the Rampage list, ahead of checkobedience and doturn, and
  -- SkipToBattleCommand leaves the script pointer PAST the command it looked
  -- for (:6674-6689) -- so a continuing Thrash or Petal Dance spends no PP,
  -- makes no obedience check and never re-rolls its count.  The counter runs
  -- down here; when it reaches zero the lock ends and the user is confused,
  -- and the move STILL resolves this turn (`.continue_rampage`).
  local rampaging = def.effect == "EFFECT_RAMPAGE"
    and state.rampageMove == moveId and (state.rampageTurns or 0) > 0
  if rampaging then
    state.rampageTurns = state.rampageTurns - 1
    if state.rampageTurns <= 0 then
      state.rampageMove, state.rampageTurns = nil, nil
      -- CheckRampage writes SUBSTATUS_CONFUSED and the count itself rather
      -- than calling FinishConfusingTarget, so there is no text, no
      -- Substitute test and no HELD_PREVENT_CONFUSE test -- just the same
      -- `and %00000001` plus two roll, 2 or 3 turns.  The cart's one
      -- exemption is the user's own Safeguard, which this port does not model
      -- yet.
      state.confuseCount = state.confuseCount or (rand(self.random, 2) + 2)
    end
  end

  -- BattleCommand_CheckRollout (move_effects/rollout.asm) skips past
  -- doturn_command while SUBSTATUS_ROLLOUT is set, so a continuing Rollout is
  -- free of PP and obedience in exactly the same way.
  local rolling = state.rolloutLock == moveId

  if not (charging or rampaging or rolling) then
    if move and (move.pp or 0) <= 0 then
      self:emit({ kind = "message", text = "No PP left for this move!" })
      return
    end
    if move then move.pp = (move.pp or 1) - 1 end
    -- BattleCommand_Rampage (effect_commands.asm:4886): the opening turn rolls
    -- 1 or 2 MORE turns of lock-in, so Thrash and Petal Dance run for two or
    -- three turns in all.  A mon acting through Sleep Talk never rampages.
    if def.effect == "EFFECT_RAMPAGE" and attacker.status ~= "sleep" then
      state.rampageMove = moveId
      state.rampageTurns = rand(self.random, 2) + 1
    end
  end

  -- BattleCommand_Rage sets SUBSTATUS_RAGE and leaves the move to hit
  -- normally; any OTHER move clears it, which is why Rage has no entry in
  -- MOVE_EFFECTS -- it falls straight through to the damage path.
  state.rage = (def.effect == "EFFECT_RAGE") or nil
  -- Fury Cutter and Rollout reset the moment another move is used; the ramp
  -- itself is maintained below.
  -- UsedMoveText is built out of _ActorNameText followed by _UsedMove1Text,
  -- which is `text_start` plus `line "used @"` (data/text/common_2.asm:339),
  -- so the break after the user's name is part of the string and lands on the
  -- box's second row however short the name is.  It is not a wrap, and the
  -- panel must not be left to invent one.
  --
  -- The event is kept so the miss paths below can mark it: the screen animates
  -- off this event, and BattleCommand_MoveAnimNoSub
  -- (engine/battle/effect_commands.asm:1958) opens on
  -- `ld a, [wAttackMissed] / and a / jp nz, BattleCommand_MoveDelay`, so a
  -- move that missed or failed burns the delay and plays nothing at all.
  self.moveEvent = self:emit({ kind = "move", side = self:sideOf(attacker),
    move = moveId,
    text = Strings("%s\nused %s!", name, def.name or moveId) })

  -- battle.move_used, where BattleState:executeMove raises it on Gen 1: after
  -- the announcement and before the effect runs, so a mod sees the move that
  -- is about to resolve.  `move` is the move record (it carries `id`, the way
  -- Gen 1's does) and `isCalled` is true for the move Metronome or Mirror Move
  -- picked -- Gen 2 tracks that as the copy depth rather than a flag argument.
  if Runtime.wants("battle.move_used") then
    Runtime.emit("battle.move_used", {
      battle = self, user = attacker, target = defender, move = def,
      isCalled = (self.copyDepth or 0) > 0,
      -- Gen 2 additions: the id on its own (Gen 1 mods read move.id), and
      -- which side is swinging.
      moveId = moveId, side = self:sideOf(attacker),
    })
  end

  -- Metronome and Mirror Move do not attack: they pick another move and run
  -- it instead (both end in `ResetTurn`).  `copyDepth` is the port's own
  -- guard -- the cart cannot recurse because it restarts the turn, and
  -- Metronome's own exception list keeps it from picking itself.
  if def.effect == "EFFECT_METRONOME" or def.effect == "EFFECT_MIRROR_MOVE" then
    local picked
    if def.effect == "EFFECT_METRONOME" then
      local order = (self.data.constants or {}).moveOrder
        or (self.data.moves and self.data.moves.order)
      picked = Effects.metronomePick(order or self:moveOrder(),
        attacker.moves, self.random)
    else
      -- Mirror Move copies the OPPONENT's last move and fails when there is
      -- none, or when the user already knows it (CheckUserMove).
      local last = self:volatile(defender).lastMove
      picked = last
      for _, own in ipairs(attacker.moves or {}) do
        if own.id == last then picked = nil break end
      end
    end
    if not picked or (self.copyDepth or 0) > 0 then
      self:markMissed()
      self:emit({ kind = "message", text = "But it failed!" })
      return
    end
    self.copyDepth = (self.copyDepth or 0) + 1
    self:useMove(attacker, defender, picked)
    self.copyDepth = self.copyDepth - 1
    return
  end

  -- Everything past here counts as "the user's last move" for Mirror Move,
  -- Encore and Disable.
  state.lastMove = moveId
  state.turnsTaken = (state.turnsTaken or 0) + 1
  state.usedMoves = state.usedMoves or {}
  local seen = false
  for _, id in ipairs(state.usedMoves) do if id == moveId then seen = true end end
  if not seen then state.usedMoves[#state.usedMoves + 1] = moveId end

  -- ParsePlayerAction (core.asm:618-624) and its enemy twin (core.asm:5621-
  -- 5627) zero the protect count for any move that is not Protect or Endure.
  if def.effect ~= "EFFECT_PROTECT" and def.effect ~= "EFFECT_ENDURE" then
    state.protectCount = nil
  end

  -- Turn one of a charge move: print the line, remember the move, done.
  -- BattleCommand_SkipSunCharge (effect_commands.asm:6488): in sun,
  -- Solarbeam's effect list jumps straight past the charge command and the
  -- beam fires in one turn.
  local charge = Effects.CHARGE[def.effect]
  if def.effect == "EFFECT_SOLARBEAM" and self.weather == "sun" then
    charge = nil
  end
  if charge and not charging then
    state.chargeMove = moveId
    state.vanished = charge.vanish or nil
    -- engine/battle/effect_commands.asm:5458
    if self.moveEvent then self.moveEvent.animParam = 1 end
    -- BattleCommand_Charge picks the line off the MOVE, not the shared
    -- EFFECT_FLY (`cp DIG`, effect_commands.asm:5464).
    local text = charge.text
    if moveId == "DIG" then text = "%s dug a hole!" end
    self:emit({ kind = "message", text = text:format(name) })
    return
  end

  -- Counter and Mirror Coat answer what the user took this turn, at double,
  -- and fail outright when nothing of the right kind landed.
  local counterKind = Effects.COUNTER[def.effect]
  if counterKind then
    local taken = state.tookThisTurn or 0
    if taken <= 0 or state.tookKind ~= counterKind then
      self:markMissed()
      self:emit({ kind = "message", text = "But it failed!" })
      return
    end
    self:dealDamage(attacker, defender, Effects.counterDamage(taken),
      { move = def, moveId = moveId })
    return
  end

  -- Protect turns the whole move aside before accuracy is even rolled.
  if self:volatile(defender).protect then
    -- CheckHit's .Protect arm jumps to .Miss (effect_commands.asm:1557).
    if def.effect == "EFFECT_SELFDESTRUCT" then self:selfdestructUser(attacker) end
    self:markMissed()
    self:emit({ kind = "message",
      text = self:monName(defender) .. " protected itself!" })
    return
  end

  -- BattleCommand_CheckHit's .LockOn: the flag Lock-On left on the TARGET is
  -- read and cleared by the very next move aimed at it, and while it is up the
  -- accuracy roll does not happen at all.
  local locked = self:consumeLockOn(defender)
  -- CheckHit's .XAccuracy and EFFECT_ALWAYS_HIT arms
  -- (effect_commands.asm:1572-1579).
  local sureHit = locked or self:volatile(attacker).xAccuracy == true
    or def.effect == "EFFECT_ALWAYS_HIT"

  -- .LockOn runs ahead of .FlyDigMoves and returns a HIT unless the target is
  -- flying and the move is one of the three (effect_commands.asm:1563-1567,
  -- :1674-1691).
  local lockedThrough = locked and not (
    self:volatile(defender).chargeMove == "FLY"
    and Battle.LOCK_ON_GROUND_MOVES[moveId])

  -- .FlyDigMoves: four moves reach a flying target, three an underground one
  -- (effect_commands.asm:1566-1567, :1713-1746).
  if self:volatile(defender).vanished and not lockedThrough
      and not Effects.hitsVanished(self:volatile(defender).chargeMove, moveId) then
    -- CheckHit's .Miss only sets wAttackMissed (effect_commands.asm:1619-1630),
    -- so `selfdestruct` still runs ahead of failuretext.
    if def.effect == "EFFECT_SELFDESTRUCT" then self:selfdestructUser(attacker) end
    self:markMissed()
    self:emit({ kind = "message", text = name .. "'s attack missed!" })
    return
  end

  -- The status-shaped moves: each one either sets its own state and returns,
  -- or falls through to the ordinary damage path.  Through the merged
  -- `move_effects` record, so a mod's own primary effect is dispatched here
  -- the way BattleState:performMove dispatches one on Gen 1.
  local effectRecord = Battle.moveEffectRecordFor(self.data, def.effect)
  local handler = effectRecord and effectRecord.run
  if handler then
    handler(self, attacker, defender, def, moveId, sureHit)
    return
  end

  -- BattleCommand_CheckHit opens on `call .DreamEater / jp z, .Miss`
  -- (engine/battle/effect_commands.asm:1554): DREAM EATER against a target
  -- that is not asleep is a MISS, before anything is rolled, so no damage
  -- lands and nothing is sapped.  The gate sits ahead of CheckHit's .LockOn
  -- and .XAccuracy arms, which is why `sureHit` does not carry the move past
  -- it -- and ahead of the damage block, which is where this used to sit,
  -- refusing the move only after it had already hit and healed.
  if def.effect == "EFFECT_DREAM_EATER" and defender.status ~= "sleep" then
    self:markMissed()
    self:emit({ kind = "message", text = name .. "'s attack missed!" })
    return
  end

  -- MAGNITUDE rolls its power before checkhit (`getmagnitude` sits between
  -- damagestats and damagecalc, data/moves/effects.asm:1705), so the number is
  -- announced even on a miss.  The rolled power replaces the move's stored
  -- one, which the ROM keeps at 1 for exactly this reason.
  local powerOverride
  if def.effect == "EFFECT_MAGNITUDE" then
    local rolled, number = Effects.magnitudePower(self.random)
    powerOverride = rolled
    self:emit({ kind = "message",
      text = ("Magnitude %d!"):format(number) })
  end

  if not sureHit
      and not self:accuracyRoll(def, attacker, defender) then
    -- data/moves/effects.asm:148-151: `selfdestruct` sits between checkhit and
    -- failuretext, so a missed Explosion still kills the user.
    if def.effect == "EFFECT_SELFDESTRUCT" then self:selfdestructUser(attacker) end
    self:markMissed()
    self:emit({ kind = "message", text = name .. "'s attack missed!" })
    -- Fury Cutter's ramp resets the moment it misses.
    state.rampMove = nil
    state.rampCount = nil
    -- BattleCommand_RolloutPower reads wAttackMissed before it touches the
    -- counter and clears SUBSTATUS_ROLLOUT outright (rollout.asm), so a missed
    -- Rollout releases the lock as well as the power ramp.  A missed rampage
    -- does NOT: `rampage` runs ahead of checkhit and nothing reads the miss.
    state.rolloutLock = nil
    return
  end

  -- move_effects/selfdestruct.asm:6-12, run before applydamage.
  if def.effect == "EFFECT_SELFDESTRUCT" then self:selfdestructUser(attacker) end

  -- Substitute: a quarter of max HP, refused when the user has no more than
  -- that to give.
  if def.effect == "EFFECT_SUBSTITUTE" then
    local maxHp = attacker.maxHp or (attacker.stats and attacker.stats.hp) or 1
    local cost = Effects.substituteCost(maxHp)
    if (attacker.hp or 0) <= cost or (state.substitute or 0) > 0 then
      self:markMissed()
      self:emit({ kind = "message", text = "But it failed!" })
      return
    end
    attacker.hp = attacker.hp - cost
    state.substitute = cost
    -- The cost is paid silently: SUBSTITUTE's own anim is all that plays
    -- (move_effects/substitute.asm:57-68).
    self:emit({ kind = "damage", side = self:sideOf(attacker), amount = cost,
      hp = attacker.hp, anim = false })
    self:emit({ kind = "message",
      text = name .. " made a SUBSTITUTE!" })
    return
  end

  -- Damage that skips the formula entirely.  The move's own power goes with
  -- it: EFFECT_STATIC_DAMAGE's arm of BattleCommand_ConstantDamage reads
  -- BATTLE_VARS_MOVE_POWER as the damage (effect_commands.asm:3157-3161).
  local fixed = Effects.fixedDamage(def.effect, attacker, defender, self.random,
    def.power)
  if fixed then
    -- The constant-damage effect list carries `resettypematchup` instead of
    -- `stab`, and that command misses the move outright when the matchup byte
    -- is 0 (effect_commands.asm:1480-1493) -- an immune target is the one
    -- thing that stops SONIC BOOM, NIGHT SHADE or SUPER FANG.
    local defenderTypes = (self:speciesDef(defender) or {}).types
      or defender.types
    local matchups = self.data.type_chart and self.data.type_chart.matchups
    if Damage.typeMultiplier(def.type, defenderTypes, matchups) == 0 then
      self:markMissed()
      self:emit({ kind = "message",
        text = "It doesn't affect " .. self:monName(defender) .. "..." })
      return
    end
    self:dealDamage(attacker, defender, fixed, { move = def, moveId = moveId })
    return
  end

  local dealt, info = 0, nil
  if ((powerOverride or def.power) or 0) > 0 then
    -- Rollout and Fury Cutter double their power for each consecutive use.
    local power = powerOverride or def.power
    if Effects.RAMPING[def.effect] then
      -- The two ramps are separate bytes on the cart with separate reset
      -- rules, so "is this a continuation?" is asked differently for each.
      --
      -- ROLLOUT: BattleCommand_CheckRollout's `.reset` arm zeroes
      -- wPlayerRolloutCount whenever SUBSTATUS_ROLLOUT is CLEAR as the move
      -- starts (move_effects/rollout.asm), and the fifth hit is what clears
      -- that bit.  So a sequence that has run its five hits out does NOT feed
      -- the next one: picking ROLLOUT again opens a fresh count, at base power
      -- and re-locked.  Testing "was the last move also ROLLOUT?" instead kept
      -- the spent counter, which left the second sequence starting at the 16x
      -- cap and never locking the menu at all.
      --
      -- FURY CUTTER: wPlayerFuryCutterCount has no such bit.  It is zeroed by
      -- ResetFuryCutterCount, which move_effects/fury_cutter.asm calls on a
      -- miss and effect_commands.asm:355 calls whenever another move is used,
      -- which is exactly the same-move test below.
      local continuing
      if def.effect == "EFFECT_ROLLOUT" then
        continuing = state.rolloutLock == moveId
      else
        continuing = state.rampMove == moveId
      end
      if continuing then
        state.rampCount = math.min((state.rampCount or 0) + 1,
          Effects.RAMPING[def.effect] - 1)
      else
        state.rampMove, state.rampCount = moveId, 0
      end
      power = Effects.rampedPower(def.power, state.rampCount,
        def.effect == "EFFECT_ROLLOUT" and state.curled)
      -- BattleCommand_RolloutPower's `.hit` arm sets SUBSTATUS_ROLLOUT while
      -- the incremented counter is still short of MAX_ROLLOUT_COUNT and
      -- clears it on the fifth (rollout.asm), and CheckPlayerLockedIn
      -- (core.asm:546) offers no menu at all while the bit is set.  Fury
      -- Cutter shares the power ramp but not the lock: its effect list
      -- carries no checkrollout.  `rampCount` is the cart's counter minus
      -- one, so the last locked turn is the one below the cap.
      if def.effect == "EFFECT_ROLLOUT" then
        local last = state.rampCount >= (Effects.RAMPING[def.effect] - 1)
        state.rolloutLock = (not last) and moveId or nil
      end
    else
      state.rampMove, state.rampCount = nil, nil
      state.rolloutLock = nil
    end

    local hits = Effects.hitCount(def.effect, self:roller())
    local landed = 0
    for hit = 1, hits do
      if (defender.hp or 0) <= 0 then break end
      local hitPower = power
      if def.effect == "EFFECT_TRIPLE_KICK" then
        hitPower = Effects.tripleKickPower(def.power, hit)
        -- Each kick rolls its own accuracy and the sequence stops on a miss.
        if hit > 1 and not sureHit
            and not self:accuracyRoll(def, attacker, defender) then
          break
        end
      end
      local amount
      amount, info = self:hitOnce(attacker, defender, def, { power = hitPower })
      if info and info.effectiveness == 0 then
        -- rolloutpower sits after checkhit and reads the wAttackMissed that
        -- `stab` set for the immunity, so an immune target breaks the Rollout
        -- lock (rollout.asm, the arm above `.hit`).
        state.rolloutLock = nil
        return
      end
      dealt = dealt + amount
      landed = landed + 1
    end
    if landed > 1 then
      self:emit({ kind = "message",
        text = ("Hit %d time(s)!"):format(landed) })
    end

    -- move_effects/pay_day.asm:13
    if def.effect == "EFFECT_PAY_DAY" and dealt > 0 then
      self.payDay = (self.payDay or 0) + 2 * (attacker.level or 1)
      self:emit({ kind = "message",
        text = Strings("Coins scattered\neverywhere!") })
    end

    -- Recoil is a quarter of what was dealt; drain heals half of it.
    if def.effect == "EFFECT_RECOIL_HIT" and dealt > 0 then
      local recoil = Effects.recoilDamage(dealt)
      attacker.hp = math.max(0, (attacker.hp or 0) - recoil)
      -- BattleCommand_Recoil is bar, huds and RecoilText only: no anim at all
      -- (effect_commands.asm:5674-5687).
      self:emit({ kind = "damage", side = self:sideOf(attacker),
        amount = recoil, hp = attacker.hp, anim = false })
      self:emit({ kind = "message", text = name .. " is hit with recoil!" })
    elseif Effects.DRAIN[def.effect] and dealt > 0 then
      self:heal(attacker, Effects.drainAmount(dealt))
      self:emit({ kind = "message",
        text = self:monName(defender) .. "'s energy was drained!" })
    end

    -- BattleCommand_RechargeNextTurn (effect_commands.asm:5899): HYPER BEAM
    -- sets SUBSTATUS_RECHARGE on the user, and CheckPlayerTurn /
    -- CheckEnemyTurn spend the next turn clearing it.  Nothing here implemented
    -- it, so HYPER BEAM was a 150-power move with no cost at all.
    --
    -- Found by the Gold route bot: CHAMPION LANCE's three DRAGONITE all carry
    -- it, and they were firing it every single turn -- twice the damage output
    -- the fight is balanced around, against a bot with one healthy mon.
    -- Unlike Gen 1 there is no "no recharge if it KOs" exemption; the command
    -- runs at the end of the effect list whenever the move connected.
    if def.effect == "EFFECT_HYPER_BEAM" and dealt > 0 then
      state.recharge = true
    end

    -- BattleCommand_HeldFlinch (effect_commands.asm:5349): a damaging move
    -- that connected lets the ATTACKER's HELD_FLINCH item (King's Rock)
    -- flinch the target, one byte against the parameter (30 -> 30/256).
    -- Silent when it lands -- the message is the target's own "flinched!"
    -- when it tries to act.  A Substitute blocks it.
    if dealt > 0 and (defender.hp or 0) > 0 then
      local held, parameter = self:heldEffect(attacker, "flinch")
      if held == "HELD_FLINCH"
          and (self:volatile(defender).substitute or 0) <= 0
          and rand(self.random, 256) < parameter then
        self:volatile(defender).flinched = true
      end
    end

    -- BattleCommand_FlinchTarget (effect_commands.asm:5314): the *_HIT
    -- flinch moves (Rock Slide, Headbutt, Bite) roll the move's effect
    -- chance after a connected hit; a Substitute blocks it.  Silent when it
    -- lands, same as the held-item flinch above.
    if def.effect == "EFFECT_FLINCH_HIT" and dealt > 0
        and (defender.hp or 0) > 0
        and (self:volatile(defender).substitute or 0) <= 0 then
      local chance = def.effectChance or 0
      if chance > 0 and rand(self.random, 100) < chance then
        self:volatile(defender).flinched = true
      end
    end

    -- BattleCommand_TrapTarget (effect_commands.asm:5569): a connected Bind
    -- class hit starts a 2-5 turn partial trap on the target -- unless one
    -- is already running or a Substitute is up.  The stored count is
    -- `and %11` plus three because HandleWrap decrements BEFORE it acts, so
    -- a count of n hurts on n-1 turns and releases on the last.
    if def.effect == "EFFECT_TRAP_TARGET" and dealt > 0
        and (defender.hp or 0) > 0 then
      local target = self:volatile(defender)
      if not target.wrapCount and (target.substitute or 0) <= 0 then
        target.wrapCount = rand(self.random, 4) + 3
        target.wrapMove = def.name or moveId
        -- wFXAnimID keeps the trapping move itself, which is what HandleWrap
        -- replays every turn (core.asm:1185-1202).
        target.wrapMoveId = moveId
        local trapText = Battle.TRAP_TEXT[moveId]
        self:emit({ kind = "message",
          text = trapText and trapText(self:monName(defender), name)
            or (self:monName(defender) .. " was trapped!") })
      end
    end
  end

  -- Defense Curl arms Rollout as well as raising Defense.
  if def.effect == "EFFECT_DEFENSE_CURL" then state.curled = true end

  -- A refused primary change writes wAttackMissed (effect_commands.asm:4191,
  -- :4380-4400); the *_HIT twins animate first and must stay unmarked.
  local change = Effects.STAT_CHANGES[def.effect]
  if change then
    local target = change[3] == "self" and attacker or defender
    -- CheckMist first (effect_commands.asm:4290), then .ComputerMiss (:4318)
    local misted = target ~= attacker and (change[2] or 0) < 0
      and self:volatile(target).mist
    if not misted and change[3] == "foe"
        and def.effect ~= "EFFECT_ACCURACY_DOWN_HIT"
        and self:aiRandomFail(attacker, target) then
      self:markMissed()
      self:emit({ kind = "message", text = "But it failed!" })
    elseif not self:changeStageAgainstMist(attacker, target, change[1], change[2])
    then
      self:markMissed()
    end
  else
    local onHit = Effects.STAT_CHANGES_ON_HIT[def.effect]
    if onHit and dealt > 0 then
      local chance = def.effectChance or 0
      if chance > 0 and rand(self.random, 100) < chance then
        local target = onHit[3] == "self" and attacker or defender
        self:changeStageAgainstMist(attacker, target, onHit[1], onHit[2])
      end
    elseif def.effect == "EFFECT_ALL_UP_HIT" and dealt > 0 then
      local chance = def.effectChance or 0
      if chance > 0 and rand(self.random, 100) < chance then
        for _, stat in ipairs(Effects.ALL_UP_STATS) do
          self:changeStage(attacker, stat, 1)
        end
      end
    end
  end

  -- Status moves land their status; damaging moves roll their effect chance.
  -- Both come off the merged `move_effects` record: a primary record's
  -- `status` is the one a zero-power move lands, a secondary record's is the
  -- one rolled against the move's effect chance after a hit.
  local record = Battle.moveEffectRecordFor(self.data, def.effect)
  local status = record and record.kind == "primary" and record.status or nil
  if status and (def.power or 0) == 0 then
    -- A refused primary status is a failed move (effect_commands.asm:3748,
    -- :6656); a refused secondary already animated and stays unmarked (:3752).
    if self:statusRefusedByType(defender, def.type, status) then
      self:markMissed()
      self:emit({ kind = "message",
        text = "It doesn't affect " .. self:monName(defender) .. "..." })
    elseif Battle.AI_FAIL_STATUSES[status]
        and self:aiRandomFail(attacker, defender) then
      self:markMissed()
      self:emit({ kind = "message", text = "But it failed!" })
    elseif not self:applyStatus(defender, status, attacker) then
      self:markMissed()
    end
  else
    local secondary = record and record.kind == "secondary"
      and record.status or nil
    -- engine/battle/effect_commands.asm:6325
    if secondary and (defender.hp or 0) > 0
        and not self:safeguarded(defender)
        and not self:statusRefusedByType(defender, def.type, secondary) then
      local chance = def.effectChance or 0
      if chance > 0 and rand(self.random, 100) < chance then
        self:applyStatus(defender, secondary, attacker)
      end
    end
  end
end

--------------------------------------------------------------------------
-- The moves whose whole job is to set state
--------------------------------------------------------------------------
--
-- Each entry is one command out of engine/battle/move_effects/, and each one
-- either sets its state and returns or prints the cart's own failure line.
-- Anything NOT in this table falls through to the ordinary damage path, which
-- is what keeps an unmodelled effect honest.
--
-- Cross-file contract: useMove does NOT dispatch on this table any more, it
-- dispatches on Battle.MOVE_EFFECT_RECORDS, which is folded out of this one
-- (and out of STATUS_EFFECTS / SECONDARY_EFFECTS) at the bottom of the block.
-- A new effect goes here, ABOVE that fold; one added below it would be a
-- handler nothing ever calls.

Battle.MOVE_EFFECTS = {}

-- Every effect command's own `.failed` tail reaches AnimateFailedMove
-- (effect_commands.asm:6656): a delay and no animation, so a failed move is
-- marked the same way a missed one is.
local function fail(self)
  self:markMissed()
  self:emit({ kind = "message", text = "But it failed!" })
end

-- BattleCommand_Splash (engine/battle/move_effects/splash.asm): the whole
-- command is the animation and then `jp PrintNothingHappened`, and the effect
-- list (data/moves/effects.asm:1156) has no checkhit at all, so the move never
-- rolls accuracy and never touches the target.  Without an entry here SPLASH
-- fell through to the damage path, where its zero power meant it announced
-- itself and then said nothing.
Battle.MOVE_EFFECTS.EFFECT_SPLASH = function(self)
  -- NothingHappenedText (data/text/battle.asm:870): "But nothing" / "happened."
  self:emit({ kind = "message",
    text = Strings("But nothing\nhappened.") })
end

-- BattleCommand_StartRain / StartSun / StartSandstorm.  Sandstorm is the only
-- one that refuses to re-cast itself.
for effect, weather in pairs(Effects.WEATHER) do
  Battle.MOVE_EFFECTS[effect] = function(self, attacker)
    if weather == "sandstorm" and self.weather == "sandstorm" then
      return fail(self)
    end
    self.weather = weather
    self.weatherTurns = Effects.WEATHER_TURNS
    self:emit({ kind = "weather", weather = weather,
      text = Effects.WEATHER_START_TEXT[weather] })
  end
end

-- BattleCommand_PerishSong: four turns on BOTH sides, and it fails only when
-- both are already counting.
Battle.MOVE_EFFECTS.EFFECT_PERISH_SONG = function(self)
  local mine = self:volatile(self.player)
  local theirs = self:volatile(self.enemy)
  if mine.perish and theirs.perish then return fail(self) end
  if not mine.perish then mine.perish = Effects.PERISH_TURNS end
  if not theirs.perish then theirs.perish = Effects.PERISH_TURNS end
  self:emit({ kind = "message",
    text = "All POKéMON hearing the song will faint in three turns!" })
end

-- BattleCommand_Encore: 3-6 turns locked into the move the target last used.
Battle.MOVE_EFFECTS.EFFECT_ENCORE = function(self, attacker, defender)
  local target = self:volatile(defender)
  local last = target.lastMove
  if not last or Effects.ENCORE_BLOCKED[last] or target.encore then
    return fail(self)
  end
  -- The move has to still be in the target's list with PP left.
  local found
  for _, move in ipairs(defender.moves or {}) do
    if move.id == last and (move.pp or 0) > 0 then found = move end
  end
  if not found then return fail(self) end
  target.encore = last
  target.encoreTurns = Effects.encoreTurns(self.random)
  self:emit({ kind = "message",
    text = self:monName(defender) .. " got an ENCORE!" })
end

-- BattleCommand_Disable: one of the target's moves, for 2-9 turns.  It fails
-- when something is already disabled, or when the target has not moved.
Battle.MOVE_EFFECTS.EFFECT_DISABLE = function(self, attacker, defender)
  local target = self:volatile(defender)
  if target.disabled then return fail(self) end
  local last = target.lastMove
  if not last or last == "STRUGGLE" then return fail(self) end
  local found
  for _, move in ipairs(defender.moves or {}) do
    if move.id == last and (move.pp or 0) > 0 then found = move end
  end
  if not found then return fail(self) end
  target.disabled = last
  target.disabledTurns = Effects.disableTurns(self.random)
  self:emit({ kind = "message",
    text = self:monName(defender) .. "'s " .. last .. " was disabled!" })
end

-- BattleCommand_LockOn: Lock-On and Mind Reader set SUBSTATUS_LOCK_ON on the
-- TARGET, not on the user, which is why the AI reads wPlayerSubStatus5 to ask
-- whether its own lock-on has landed.  A Substitute blocks it outright.
Battle.MOVE_EFFECTS.EFFECT_LOCK_ON = function(self, attacker, defender)
  local target = self:volatile(defender)
  if (target.substitute or 0) > 0 then
    -- lock_on.asm's `.fail`: AnimateFailedMove, then PrintDidntAffect.  The
    -- animation is AnimateCurrentMove on the success arm only.
    self:markMissed()
    self:emit({ kind = "message",
      text = "It doesn't affect " .. self:monName(defender) .. "..." })
    return
  end
  target.lockOn = true
  self:emit({ kind = "message",
    text = self:monName(attacker) .. " took aim!" })
end

-- BattleCommand_CheckHit's .LockOn: the flag is read AND cleared by the next
-- move aimed at the mon carrying it, whether or not that move was the one the
-- lock-on was meant for, and whether or not the exception at :1683-1688 then
-- misses (effect_commands.asm:1671-1672).
function Battle:consumeLockOn(defender)
  local target = self:volatile(defender)
  if not target.lockOn then return false end
  target.lockOn = nil
  return true
end

-- BattleCommand_CheckHit's `.BrightPowder`: the DEFENDER's HELD_BRIGHTPOWDER
-- subtracts its parameter (20) from the accuracy byte before the roll.  The
-- port rolls accuracy in the percent domain, so the byte penalty is scaled
-- by 100/256 and floored -- never below 1, because rollHit reads a
-- non-positive accuracy as "never misses", the exact opposite of the cart's
-- underflow-to-zero always-miss.
function Battle:moveAccuracy(accuracy, defender)
  if not accuracy or accuracy <= 0 then return accuracy end
  local effect, parameter = self:heldEffect(defender, "accuracy")
  if effect == "HELD_BRIGHTPOWDER" then
    accuracy = math.max(1,
      accuracy - math.floor((parameter or 0) * 100 / 256))
  end
  return accuracy
end

-- The one accuracy roll (BattleCommand_CheckHit), hooked as battle.accuracy --
-- the same hook BattleState:accuracyRoll calls on Gen 1, with the same ctx
-- keys: `move`, `user`, `target` and the rng, so a mod that makes a move never
-- miss reads the same fields it did on Red.  `ruleset` has no Gen 2
-- counterpart and is absent rather than invented; `accuracy` (the byte the
-- roll is actually made against, after Bright Powder) and `moveId` are Gen 2
-- additions.  The ctx table is built only when a chain is installed.
function Battle:accuracyRoll(def, attacker, defender, accuracy)
  accuracy = accuracy or (def and def.accuracy)
  if Runtime.wantsHook("battle.accuracy") then
    return Runtime.call("battle.accuracy", function(c)
      return c.battle:vanillaAccuracyRoll(c.accuracy, c.user, c.target)
    end, { battle = self, move = def, moveId = def and def.id,
           user = attacker, target = defender, accuracy = accuracy,
           rng = self:roller(), random = self.random })
  end
  return self:vanillaAccuracyRoll(accuracy, attacker, defender)
end

function Battle:vanillaAccuracyRoll(accuracy, attacker, defender)
  return Damage.rollHit(self:moveAccuracy(accuracy, defender),
    self.stages[self:sideOf(attacker)].accuracy,
    self.stages[self:sideOf(defender)].evasion, self.random)
end

-- BattleCommand_StatDown's SUBSTATUS_MIST arm (a GUARD SPEC): a drop the FOE
-- aims at the holder answers ProtectedByMistText and changes nothing.  The
-- holder's own drops are not Mist's business, so self-targeted changes pass
-- straight through.
function Battle:changeStageAgainstMist(attacker, target, stat, stages)
  if target ~= attacker and (stages or 0) < 0
      and self:volatile(target).mist then
    self:emit({ kind = "message",
      text = self:monName(target) .. "'s protected by MIST." })
    return false
  end
  return self:changeStage(target, stat, stages)
end

-- BattleCommand_Spikes: laid on the side that will switch into them, and it
-- refuses a second layer (Gen 2 has only one).
Battle.MOVE_EFFECTS.EFFECT_SPIKES = function(self, attacker, defender)
  local side = self:sideOf(defender)
  if self.spikes[side] then return fail(self) end
  self.spikes[side] = true
  self:emit({ kind = "message", text = "Spikes were scattered all around!" })
end

-- BattleCommand_Protect / Endure share ProtectChance, which halves the odds
-- for every consecutive use and zeroes the counter the moment one fails.
local function protectLike(field, text)
  return function(self, attacker)
    local state = self:volatile(attacker)
    -- move_effects/protect.asm:22-23: `call CheckOpponentWentFirst / jr nz,
    -- .failed`, ahead of everything else ProtectChance rolls.
    -- move_effects/protect.asm:27-30: no Protect from behind a Substitute.
    if (self.firstMover and self.firstMover ~= self:sideOf(attacker))
        or (state.substitute or 0) > 0
        or not Effects.protectSucceeds(state.protectCount or 0, self:roller())
    then
      state.protectCount = 0
      return fail(self)
    end
    state.protectCount = (state.protectCount or 0) + 1
    state[field] = true
    self:emit({ kind = "message", text = self:monName(attacker) .. text })
  end
end

Battle.MOVE_EFFECTS.EFFECT_PROTECT = protectLike("protect", " protected itself!")
Battle.MOVE_EFFECTS.EFFECT_ENDURE = protectLike("endure", " braced itself!")

-- BattleCommand_UnleashEnergy / StoreEnergy.  Turn one starts the store; the
-- turn the counter runs out the user hits for double everything it took.
Battle.MOVE_EFFECTS.EFFECT_BIDE = function(self, attacker, defender, def, moveId)
  local state = self:volatile(attacker)
  if not state.bideTurns then
    state.bideTurns = Effects.bideTurns(self.random)
    state.bideStored = 0
    self:emit({ kind = "message",
      text = self:monName(attacker) .. " is storing energy!" })
    return
  end
  state.bideTurns = state.bideTurns - 1
  if state.bideTurns > 0 then
    self:emit({ kind = "message",
      text = self:monName(attacker) .. " is storing energy!" })
    return
  end
  local damage = Effects.bideDamage(state.bideStored)
  state.bideTurns, state.bideStored = nil, nil
  self:emit({ kind = "message",
    text = self:monName(attacker) .. " unleashed energy!" })
  if damage <= 0 then return fail(self) end
  self:dealDamage(attacker, defender, damage, { move = def, moveId = moveId })
end

-- BattleCommand_Transform: the user takes the target's species, types, moves
-- and stats, keeping its own HP and level.  Every copied move gets 5 PP.
Battle.MOVE_EFFECTS.EFFECT_TRANSFORM = function(self, attacker, defender)
  local state = self:volatile(attacker)
  if state.transformed or self:volatile(defender).substitute then
    return fail(self)
  end
  state.transformed = true
  -- The cart copies the target into BATTLE ram (wBattleMon / wEnemyMon) and
  -- leaves the struct the mon was loaded FROM alone, so every route out of the
  -- battle -- SwitchOutMon reloading the party slot, and PokeBallEffect
  -- reloading the caught mon out of its base data -- hands back a DITTO.  This
  -- port has one table per mon, so the identity the copy is about to overwrite
  -- is kept here and put back by Battle:untransform, which every one of those
  -- routes goes through.  Without it a Ditto that transformed was a permanent
  -- copy of whatever it last faced: the caught record, and the player's own
  -- party slot, went into the save as the wrong species with the wrong moves.
  state.preTransform = {
    species = attacker.species,
    types = attacker.types,
    moves = attacker.moves,
    shiny = attacker.shiny,
    stats = {},
  }
  local targetDef = self:speciesDef(defender)
  attacker.species = defender.species
  attacker.types = (targetDef and targetDef.types) or defender.types
  attacker.shiny = defender.shiny
  local moves = {}
  for index, move in ipairs(defender.moves or {}) do
    moves[index] = { id = move.id, pp = 5, maxPp = 5 }
  end
  attacker.moves = moves
  -- Everything but HP is copied, which is why a Transformed Ditto has the
  -- target's Attack and its own hit points.
  local stats = attacker.stats or {}
  local theirs = defender.stats or {}
  for _, key in ipairs({ "attack", "defense", "speed", "specialAttack",
      "specialDefense" }) do
    state.preTransform.stats[key] = stats[key]
    stats[key] = theirs[key] or stats[key]
  end
  attacker.stats = stats
  self:emit({ kind = "message", text = self:monName(attacker)
    .. " TRANSFORMED into " .. (defender.species or "?") .. "!" })
  -- The moment itself, for the screen.  src/ui/gen2/BattleState.lua draws each
  -- side's pic and HUD from `shownMon`, which follows the EVENT QUEUE rather
  -- than the battle -- a whole round is resolved by Battle:takeTurn before its
  -- first message is read, so anything written straight into the mon record is
  -- on screen a beat before its own line.  That is what made a wild DITTO
  -- change shape the instant the player confirmed a move.  Damage has
  -- `shownHp` and a switch has the `send` event for exactly this; a transform
  -- is the third identity swap and this is its event.  `mon` is the battler
  -- whose pic changes (the same key `send` carries) and `from` is what it was.
  self:emit({ kind = "transform", side = self:sideOf(attacker),
    mon = attacker, species = attacker.species,
    from = state.preTransform.species })
end

-- SwitchOutMon / PokeBallEffect's reload: the copy Transform wrote lives in
-- battle ram on the cart, so it never survives the mon leaving the field.
-- Called from Battle:clearVolatile (every switch, and CleanUpBattleRAM at the
-- end of the battle) and from Battle:caught, which is the catch's own reload.
-- Returns whether anything was restored.
function Battle:untransform(mon)
  local state = mon and mon.volatile
  local before = state and state.preTransform
  if not before then return false end
  mon.species = before.species
  mon.types = before.types
  mon.moves = before.moves
  mon.shiny = before.shiny
  -- The stat table is written through in place (a mon's `stats` is handed
  -- around by reference), so the five copied numbers are put back one by one.
  local stats = mon.stats
  if stats then
    for key, value in pairs(before.stats) do stats[key] = value end
  end
  state.preTransform = nil
  state.transformed = nil
  return true
end

-- BattleCommand_FutureSight: four turns, damage rolled and stored now.
Battle.MOVE_EFFECTS.EFFECT_FUTURE_SIGHT = function(self, attacker, defender, def)
  local state = self:volatile(attacker)
  if state.futureSight then return fail(self) end
  local damage = Damage.calc({
    level = attacker.level or 1,
    power = def.power,
    moveType = def.type,
    attacker = {
      attack = (attacker.stats or {}).attack,
      specialAttack = (attacker.stats or {}).specialAttack,
      types = (self:speciesDef(attacker) or {}).types or attacker.types,
      stages = self.stages[self:sideOf(attacker)],
    },
    defender = {
      defense = (defender.stats or {}).defense,
      specialDefense = (defender.stats or {}).specialDefense,
      types = (self:speciesDef(defender) or {}).types or defender.types,
      stages = self.stages[self:sideOf(defender)],
    },
    types = self.data.type_chart and self.data.type_chart.types,
    matchups = self.data.type_chart and self.data.type_chart.matchups,
    random = self.random,
  })
  state.futureSight = Effects.FUTURE_SIGHT_TURNS
  state.futureSightDamage = math.max(1, damage)
  state.futureSightSide = self:sideOf(defender)
  self:emit({ kind = "message",
    text = self:monName(attacker) .. " foresaw an attack!" })
end

-- BattleCommand_OHKO: fails outright against a higher-level target, and the
-- level difference is worth two accuracy points each.
Battle.MOVE_EFFECTS.EFFECT_OHKO = function(self, attacker, defender, def, _,
    locked)
  local accuracy = Effects.ohkoAccuracy(def.accuracy, attacker.level,
    defender.level)
  if not accuracy then
    -- `.no_effect` sets wAttackMissed (effect_commands.asm:5414-5419) and
    -- `ohko` sits ahead of `moveanim` in OHKOHit (data/moves/effects.asm:917),
    -- so the level refusal plays MoveDelay and nothing else.
    self:markMissed()
    self:emit({ kind = "message",
      text = "It doesn't affect " .. self:monName(defender) .. "..." })
    return
  end
  -- BattleCommand_OHKO ends on `call BattleCommand_CheckHit`, so a lock-on
  -- carries Fissure past the level-scaled roll -- and so does
  -- SUBSTATUS_X_ACCURACY, which is why an X ACCURACY makes the OHKO moves
  -- sure hits in Gen 2 (`locked` here is useMove's sureHit).
  local hit = locked or self:accuracyRoll(def, attacker, defender, accuracy)
  if not hit then
    self:markMissed()
    self:emit({ kind = "message",
      text = self:monName(attacker) .. "'s attack missed!" })
    return
  end
  self:dealDamage(attacker, defender, defender.hp or 1,
    { move = def, moveId = def and def.id })
  self:emit({ kind = "message", text = "It's a one-hit KO!" })
end

-- BattleCommand_BeatUp: one hit per healthy, unstatused party member, each
-- swinging with its own base Attack.
Battle.MOVE_EFFECTS.EFFECT_BEAT_UP = function(self, attacker, defender, def)
  local party = attacker == self.player and self.party or self.enemyParty
  local active = attacker == self.player and self.playerIndex or self.enemyIndex
  local hits = Effects.beatUpParty(party, active)
  if #hits == 0 then return fail(self) end
  local targetDef = self:speciesDef(defender)
  local landed = 0
  for _, entry in ipairs(hits) do
    if (defender.hp or 0) <= 0 then break end
    local monDef = self.data.pokemon and self.data.pokemon[entry.mon.species]
    local base = monDef and monDef.baseStats or {}
    local damage = Damage.calc({
      level = entry.mon.level or attacker.level or 1,
      power = def.power,
      moveType = def.type,
      -- The BASE stats, not the battle stats: Beat Up asks GetBaseData for
      -- each party member and the target both.
      attacker = { attack = base.attack or 1, specialAttack = base.attack or 1,
        types = {}, stages = {} },
      defender = {
        defense = (targetDef and targetDef.baseStats
          and targetDef.baseStats.defense) or 1,
        specialDefense = (targetDef and targetDef.baseStats
          and targetDef.baseStats.defense) or 1,
        types = {}, stages = {},
      },
      types = self.data.type_chart and self.data.type_chart.types,
      matchups = self.data.type_chart and self.data.type_chart.matchups,
      random = self.random,
    })
    self:emit({ kind = "message",
      text = self:monName(entry.mon) .. "'s attack!" })
    self:dealDamage(attacker, defender, math.max(1, damage),
      { move = def, moveId = def and def.id })
    landed = landed + 1
  end
  self:emit({ kind = "message", text = ("Hit %d time(s)!"):format(landed) })
end

-- BattleCommand_Heal (effect_commands.asm:5986): Recover and Rest are both
-- EFFECT_HEAL and split on the MOVE (:6007), Rest taking GetMaxHP (:6043).
Battle.MOVE_EFFECTS.EFFECT_HEAL = function(self, attacker, _, _, moveId)
  local maxHp = attacker.maxHp or (attacker.stats and attacker.stats.hp) or 1
  -- effect_commands.asm:6061: full HP answers HPIsFullText, not the fail line.
  if (attacker.hp or 0) >= maxHp then
    self:markMissed()
    self:emit({ kind = "message",
      text = self:monName(attacker) .. "'s HP is full!" })
    return
  end
  if moveId == "REST" then
    -- effect_commands.asm:6015-6027: the toxic bit clears, the status byte
    -- becomes REST_SLEEP_TURNS + 1, and the line depends on the old status.
    local cured = attacker.status ~= nil
    attacker.status = "sleep"
    attacker.statusTurns = 3
    attacker.toxicCounter = nil
    self:emit({ kind = "status", side = self:sideOf(attacker),
      status = "sleep", text = self:monName(attacker)
        .. (cured and " fell asleep and became healthy!"
          or " went to sleep!") })
    self:heal(attacker, maxHp)
  else
    self:heal(attacker, math.max(1, math.floor(maxHp / 2)))
  end
  -- effect_commands.asm:6058, RegainedHealthText.
  self:emit({ kind = "message",
    text = self:monName(attacker) .. " regained health!" })
end

-- BattleCommand_TimeBasedHealContinue (effect_commands.asm:6374) answers the
-- same two lines BattleCommand_Heal does: HPIsFullText (:6447) and
-- RegainedHealthText (:6440).
for effect in pairs(Effects.SUN_HEAL) do
  Battle.MOVE_EFFECTS[effect] = function(self, attacker)
    local maxHp = attacker.maxHp or (attacker.stats and attacker.stats.hp) or 1
    if (attacker.hp or 0) >= maxHp then
      self:markMissed()
      self:emit({ kind = "message",
        text = self:monName(attacker) .. "'s HP is full!" })
      return
    end
    local fraction = Effects.weatherHealFraction(self.weather)
    self:heal(attacker, math.max(1, math.floor(maxHp * fraction)))
    self:emit({ kind = "message",
      text = self:monName(attacker) .. " regained health!" })
  end
end

-- BattleCommand_BatonPass: the switch keeps everything ResetBatonPassStatus
-- does NOT clear -- the stat stages above all, which is the point of the move.
Battle.MOVE_EFFECTS.EFFECT_BATON_PASS = function(self, attacker)
  local side = self:sideOf(attacker)
  local party = side == "player" and self.party or self.enemyParty
  local current = side == "player" and self.playerIndex or self.enemyIndex
  local target
  for index, mon in ipairs(party) do
    if index ~= current and (mon.hp or 0) > 0 then
      target = index
      break
    end
  end
  if not target then return fail(self) end
  local carried = self:volatile(attacker)
  for _, key in ipairs(Effects.BATON_PASS_DROPS) do carried[key] = nil end
  -- The area moves with the baton rather than being copied: what the passer
  -- leaves the field with is an empty one, the same as any other switch out.
  self:clearVolatile(attacker)
  self:emit({ kind = "baton-pass", side = side, index = target,
    text = self:monName(attacker) .. " passed the baton!" })
  if side == "player" then
    self.playerIndex = target
    self.player = party[target]
    self.participants[target] = true
    self.player.volatile = carried
  else
    self.enemyIndex = target
    self.enemy = party[target]
    self.enemy.volatile = carried
  end
  self:emit({ kind = "send", side = side,
    mon = side == "player" and self.player or self.enemy,
    text = "Go! " .. self:monName(side == "player" and self.player
      or self.enemy) .. "!" })
end

-- BattleCommand_TrapTarget's .Traps table, one line per move: target first,
-- user second.  FIRE_SPIN and WHIRLPOOL share the plain WasTrappedText
-- fallback in the caller.
Battle.TRAP_TEXT = {
  BIND = function(target, user)
    return user .. " used BIND on " .. target .. "!"
  end,
  WRAP = function(target, user)
    return target .. " was WRAPPED by " .. user .. "!"
  end,
  CLAMP = function(target, user)
    return target .. " was CLAMPED by " .. user .. "!"
  end,
}

-- BattleCommand_Screen (effect_commands.asm:6100): one wPlayerScreens bit
-- and a five-turn count per side; the second cast fails while the first is
-- still up.
Battle.SCREEN_TURNS = 5

Battle.MOVE_EFFECTS.EFFECT_LIGHT_SCREEN = function(self, attacker)
  local side = self.screens[self:sideOf(attacker)]
  if (side.lightScreen or 0) > 0 then return fail(self) end
  side.lightScreen = Battle.SCREEN_TURNS
  self:emit({ kind = "message",
    text = Strings("%s's SPCL.DEF rose!", self:monName(attacker)) })
end

Battle.MOVE_EFFECTS.EFFECT_REFLECT = function(self, attacker)
  local side = self.screens[self:sideOf(attacker)]
  if (side.reflect or 0) > 0 then return fail(self) end
  side.reflect = Battle.SCREEN_TURNS
  self:emit({ kind = "message",
    text = Strings("%s's DEFENSE rose!", self:monName(attacker)) })
end

-- engine/battle/move_effects/safeguard.asm:1
Battle.MOVE_EFFECTS.EFFECT_SAFEGUARD = function(self, attacker)
  local side = self.screens[self:sideOf(attacker)]
  if (side.safeguard or 0) > 0 then return fail(self) end
  side.safeguard = Battle.SCREEN_TURNS
  self:emit({ kind = "message",
    text = self:monName(attacker) .. "'s covered by a veil!" })
end

-- BattleCommand_Curse (engine/battle/move_effects/curse.asm): two moves in
-- one body.  A non-Ghost user trades a stage of Speed for one each of Attack
-- and Defense, refused only when BOTH raises are already capped; a Ghost
-- user pays half its max HP -- the cut can faint it -- to set
-- SUBSTATUS_CURSE on the target, worth a quarter of max HP every turn
-- (ResidualDamage's curse arm, Battle:tickSeedAndCurse).
Battle.MOVE_EFFECTS.EFFECT_CURSE = function(self, attacker, defender)
  local ghost = false
  for _, type_ in ipairs((self:speciesDef(attacker) or {}).types
      or attacker.types or {}) do
    if type_ == "GHOST" then ghost = true end
  end
  local name = self:monName(attacker)
  if not ghost then
    local stages = self.stages[self:sideOf(attacker)]
    if (stages.attack or 0) >= Effects.MAX_STAGE
        and (stages.defense or 0) >= Effects.MAX_STAGE then
      -- curse.asm's `.cantraise`: AnimateFailedMove, then WontRiseAnymoreText.
      -- The raising arm is the only one that calls AnimateCurrentMove.
      self:markMissed()
      self:emit({ kind = "message",
        text = name .. "'s ATTACK won't rise anymore!" })
      return
    end
    -- The cart's own order: Speed down first, then the two raises.  The
    -- user's own drop is not Mist's business.
    self:changeStage(attacker, "speed", -1)
    self:changeStage(attacker, "attack", 1)
    self:changeStage(attacker, "defense", 1)
    return
  end
  local target = self:volatile(defender)
  if target.vanished or (target.substitute or 0) > 0 or target.cursed then
    return fail(self)
  end
  target.cursed = true
  local maxHp = attacker.maxHp or (attacker.stats and attacker.stats.hp) or 1
  local cost = math.max(1, math.floor(maxHp / 2))
  attacker.hp = math.max(0, (attacker.hp or 0) - cost)
  -- AnimateCurrentMove has already run; SubtractHPFromUser adds nothing
  -- (move_effects/curse.asm:70-76).
  self:emit({ kind = "damage", side = self:sideOf(attacker), amount = cost,
    hp = attacker.hp, anim = false })
  self:emit({ kind = "message",
    text = name .. " cut its own HP and put a CURSE on "
      .. self:monName(defender) .. "!" })
end

-- BattleCommand_LeechSeed (engine/battle/move_effects/leech_seed.asm): the
-- flag sits on the SEEDED mon and ResidualDamage drains an eighth every turn
-- into whoever stands on the other side by then.  A Grass target does not
-- take it at all; a miss, a Substitute or a repeat all "evaded" -- and the
-- move's own 90 accuracy rolls first, since its effect list carries
-- checkhit.
--
-- All three refusals (`.evaded` and `.grass`) end on AnimateFailedMove, so
-- none of them animates; only the seeding arm reaches AnimateCurrentMove.
Battle.MOVE_EFFECTS.EFFECT_LEECH_SEED = function(self, attacker, defender,
    def, _, sureHit)
  if not sureHit
      and not self:accuracyRoll(def, attacker, defender) then
    self:markMissed()
    self:emit({ kind = "message",
      text = self:monName(defender) .. " evaded the attack!" })
    return
  end
  for _, type_ in ipairs((self:speciesDef(defender) or {}).types
      or defender.types or {}) do
    if type_ == "GRASS" then
      self:markMissed()
      self:emit({ kind = "message",
        text = "It doesn't affect " .. self:monName(defender) .. "..." })
      return
    end
  end
  local target = self:volatile(defender)
  if (target.substitute or 0) > 0 or target.leechSeed then
    self:markMissed()
    self:emit({ kind = "message",
      text = self:monName(defender) .. " evaded the attack!" })
    return
  end
  target.leechSeed = true
  self:emit({ kind = "message",
    text = self:monName(defender) .. " was seeded!" })
end

-- BattleCommand_Spite (engine/battle/move_effects/spite.asm): 2-5 PP off the
-- move the TARGET used last, clamped to what it has left.  The cart reads
-- BATTLE_VARS_LAST_COUNTER_MOVE_OPP, so a target that has not moved yet -- or
-- that answered with STRUGGLE, or whose slot is already dry -- falls into
-- `.failed`, which is `jp PrintDidntAffect2`.  The effect list carries
-- checkhit (data/moves/effects.asm:1366), and MOVE_EFFECTS handlers run ahead
-- of useMove's own roll, so the roll is made here the way Leech Seed makes it.
--
-- No party writeback: the cart copies the new PP into the party struct and
-- wWildMonPP behind the battle struct, but Battle.party IS save.party here and
-- the move table this edits is the live one.
Battle.MOVE_EFFECTS.EFFECT_SPITE = function(self, attacker, defender, def, _,
    sureHit)
  -- DidntAffect2Text (data/text/battle.asm:888).  BattleCommand_Spite calls
  -- AnimateCurrentMove itself and only on the way to the success text, so a
  -- refused SPITE plays nothing.
  local function didntAffect()
    self:markMissed()
    self:emit({ kind = "message",
      text = "It didn't affect " .. self:monName(defender) .. "!" })
  end
  if not sureHit
      and not self:accuracyRoll(def, attacker, defender) then
    return didntAffect()
  end
  local last = self:volatile(defender).lastMove
  if not last or last == Battle.STRUGGLE then return didntAffect() end
  local entry = self:findMove(defender, last)
  if not entry or (entry.pp or 0) <= 0 then return didntAffect() end
  -- `call BattleRandom / and %11 / inc a / inc a`, then `cp b / jr nc` keeps
  -- the loss inside what the slot still holds.
  local loss = math.min(rand(self.random, 4) + 2, entry.pp)
  entry.pp = entry.pp - loss
  local moveName = (self:moveDef(last) or {}).name or last
  self:emit({ kind = "message",
    text = ("%s's %s was reduced by %d!"):format(self:monName(defender),
      moveName, loss) })
end

-- BattleCommand_ArenaTrap (effect_commands.asm:6238): Mean Look and Spider
-- Web set SUBSTATUS_CANT_RUN on the USER's side, meaning "my opponent cannot
-- run or switch" -- which is why the pin dies with its user (a switch drops
-- the volatile) and why TryEnemyFlee reads the PLAYER's substatus to hold a
-- roamer.  No accuracy roll: the effect list has no checkhit, only the
-- hidden-target and repeat guards.
Battle.MOVE_EFFECTS.EFFECT_MEAN_LOOK = function(self, attacker, defender)
  if self:volatile(defender).vanished
      or self:volatile(attacker).trapsTarget then
    return fail(self)
  end
  self:volatile(attacker).trapsTarget = true
  self:emit({ kind = "message",
    text = self:monName(defender) .. " can't escape now!" })
end

-- BattleCommand_ForceSwitch (effect_commands.asm:4913).  Fails outright for
-- BATTLETYPE_FORCESHINY and BATTLETYPE_TRAP.  Against a WILD mon the battle
-- simply ENDS -- either direction writes DRAW into wBattleResult, which is
-- what makes a Roared-away roamer bank its HP -- with the level ladder
-- deciding: the user's level at or above the target's succeeds outright,
-- and below it one re-rolled byte can still get past a quarter of the
-- target's level.  In a TRAINER battle the user must be moving SECOND (both
-- arms read wEnemyGoesFirst) and a random other able mon is dragged out.
Battle.MOVE_EFFECTS.EFFECT_FORCE_SWITCH = function(self, attacker, defender,
    def, moveId, sureHit)
  if self.battleType == Battle.BATTLETYPE_FORCESHINY
      or self.battleType == Battle.BATTLETYPE_TRAP then
    return fail(self)
  end
  -- checkhit runs ahead of forceswitch in the effect list; `.missed` fails.
  if not sureHit
      and not self:accuracyRoll(def, attacker, defender) then
    return fail(self)
  end

  if self.wild then
    -- `.wild_force_flee` / `.wild_succeed_playeristarget`.
    local userLevel = attacker.level or 1
    local targetLevel = defender.level or 1
    local succeeds = userLevel >= targetLevel
    if not succeeds then
      local roll = self:rollBelow(math.min(256, userLevel + targetLevel + 1))
      succeeds = roll >= math.floor(targetLevel / 4)
    end
    if not succeeds then return fail(self) end
    self.over = true
    self.outcome = "fled"
    -- FledInFearText for ROAR, BlownAwayText for everything else, naming
    -- the mon that was sent away.
    self.forcedSwitch = true
    self:emit({ kind = "run", side = self:sideOf(defender),
      text = self:monName(defender)
        .. (moveId == "ROAR" and " fled in fear!" or " was blown away!") })
    return
  end

  -- `.trainer` / `.vs_trainer`: the user has to be moving second, and the
  -- other side needs someone able on the bench.
  if self.firstMover == self:sideOf(attacker) then return fail(self) end
  local party = defender == self.player and self.party or self.enemyParty
  local active = defender == self.player and self.playerIndex
    or self.enemyIndex
  local bench = {}
  for index, mon in ipairs(party) do
    if index ~= active and (mon.hp or 0) > 0 and not mon.isEgg then
      bench[#bench + 1] = index
    end
  end
  if #bench == 0 then return fail(self) end
  local pick = bench[rand(self.random, #bench) + 1]
  self:clearVolatile(defender)
  local incoming = party[pick]
  if defender == self.player then
    self.playerIndex = pick
    self.player = incoming
    self.participants[pick] = true
    self.stages.player = Battle.newStages()
    self:checkAmuletCoin(incoming)
  else
    self.enemyIndex = pick
    self.enemy = incoming
    self.stages.enemy = Battle.newStages()
  end
  self:emit({ kind = "send", side = self:sideOf(incoming), mon = incoming,
    text = self:monName(incoming) .. " was dragged out!" })
  self:breakTrapsOnSend(incoming)
  self:spikesDamage(incoming)
  -- wForcedSwitch: the round ends here, skipping the between-turn effects.
  self.forcedSwitch = true
end

-- BattleCommand_Teleport (engine/battle/move_effects/teleport.asm).  Fails
-- outright for BATTLETYPE_FORCESHINY/TRAP, for a trapped user, and in any
-- TRAINER battle; in a WILD battle the level ladder is identical to
-- EFFECT_FORCE_SWITCH's.  Without an entry here TELEPORT fell through to
-- the (0-power) damage path and never ended the battle.
Battle.MOVE_EFFECTS.EFFECT_TELEPORT = function(self, attacker, defender)
  if self.battleType == Battle.BATTLETYPE_FORCESHINY
      or self.battleType == Battle.BATTLETYPE_TRAP
      or self:volatile(defender).trapsTarget then
    return fail(self)
  end
  if not self.wild then return fail(self) end

  local userLevel = attacker.level or 1
  local targetLevel = defender.level or 1
  local succeeds = userLevel >= targetLevel
  if not succeeds then
    local roll = self:rollBelow(math.min(256, userLevel + targetLevel + 1))
    succeeds = roll >= math.floor(targetLevel / 4)
  end
  if not succeeds then return fail(self) end

  self.over = true
  self.outcome = "fled"
  self.forcedSwitch = true
  self:emit({ kind = "run", side = self:sideOf(attacker),
    text = self:monName(attacker) .. " fled from battle!" })
end

-- -------------------------------------------------------- the move effects
--
-- The three tables above as records, in the shape src/mods/Schemas.lua's
-- `move_effects` registry validates.  Same registry NAME Gen 1 fills from
-- src/battle/MoveEffects.lua, and the same `kind` vocabulary:
--
--   primary    the effect runs INSTEAD of the damage path.  Both the
--              state-setting commands above (`run`) and the zero-power status
--              moves (`status`) are primary; which one a record is is which
--              field it carries.
--   secondary  a side-effect rolled against the move's effect chance after a
--              hit that already landed.
--
-- `run` is the Gold signature fn(battle, attacker, defender, def, moveId,
-- sureHit), the same six arguments useMove has always dispatched on -- Gen 1's
-- run takes its own engine's context for the same reason the status records
-- above do.
--
-- One field Gen 2 adds rather than renaming anything: `status`, the name the
-- effect writes into mon.status, which is what makes EFFECT_TOXIC and
-- EFFECT_POISON_HIT records rather than two more lookup tables.  Effects that
-- are steered from inside the damage pipeline (EFFECT_MULTI_HIT, the recoil
-- and drain families) have no standalone handler and so no record yet, exactly
-- as Gen 1's "full" effects have none: they fall through to the damage path,
-- which is what keeps an unmodelled effect honest.
Battle.MOVE_EFFECT_RECORDS = {}

for id, run in pairs(Battle.MOVE_EFFECTS) do
  Battle.MOVE_EFFECT_RECORDS[id] = { kind = "primary", run = run }
end
for id, status in pairs(Battle.STATUS_EFFECTS) do
  Battle.MOVE_EFFECT_RECORDS[id] = { kind = "primary", status = status }
end
for id, status in pairs(Battle.SECONDARY_EFFECTS) do
  Battle.MOVE_EFFECT_RECORDS[id] = { kind = "secondary", status = status }
end

-- vanilla registrations, engine-owned (Schemas.ENGINE), so a mod's register of
-- one of these ids collides the way it does on Red and has to say override
function Battle.registerMoveEffectsInto(registry, _, owner)
  for id, record in pairs(Battle.MOVE_EFFECT_RECORDS) do
    registry:register(id, record, owner)
  end
end

-- the merged `move_effects` record for an effect id, the module's own when no
-- loader ran; a plain function over `data` for the same reason
-- Battle.statusRecordFor is one
function Battle.moveEffectRecordFor(data, effect)
  if effect == nil then return nil end
  local merged = data and data.gen2MoveEffects
  return (merged and merged[effect]) or Battle.MOVE_EFFECT_RECORDS[effect]
end

-- ------------------------------------------------------------ the statuses
--
-- Gold's persistent conditions as records, in the shape src/mods/Schemas.lua's
-- `statuses` registry validates.  Same registry NAME Gen 1 fills from
-- src/battle/Status.lua, because a mod that adds a status should not have to
-- learn a second noun -- only the ids differ, and they have to: Gold's engine
-- writes "sleep" and "burn" into mon.status where Red writes SLP and BRN.
--
-- The Gen 1 fields keep their Gen 1 meaning:
--
--   label / hudLabel        the three-letter code the HUD draws
--   catchBonus              what PokeBallEffect adds to the catch rate
--   statPenalty             the one stat this status cuts, and by what
--   beforeMove              CheckPlayerTurn's arm, run before the move
--   beforeMovePriority      above VOLATILE_PRIORITY runs ahead of the
--                           flinch/confusion block, at or below after it,
--                           which is CheckPlayerTurn's own order
--   residual                the end-of-turn chip, HandleStatusOnTurnEnd
--
-- Their SIGNATURES are Gold's, because the two engines carry different
-- objects: Gen 1 hands a battler wrapper and returns message lists, Gold has
-- no battler wrapper and emits its own events, so beforeMove is
-- fn(battle, mon, name) -> canAct, residual is fn(battle, mon, maxHp) ->
-- damage, text, and onInflict is fn(battle, mon) with no return.  A record is
-- generation-specific either way -- the ids are disjoint -- so the field names
-- stay shared and the shapes follow the engine that runs them.
--
-- Three fields Gen 2 genuinely carries that Gen 1 does not, added rather than
-- renaming anything (the catalog's top-level records are extensible):
--
--   inflictText          the tail of the landing line, spliced after the name
--   catchBonusIntended   the bonus the cart MEANT to give: the `and` that
--                        tests for sleep/freeze leaves burn, poison and
--                        paralysis at zero, so catchBonus is 0 for them and
--                        this is the 5 that `fixBugs` asks for
--                        (src/battle/gen2/Catching.lua statusBonus)
--   substatus            true for confusion, which is SUBSTATUS_CONFUSED and
--                        not a status byte at all
--   healClass            the StatusHealingActions class that cures it, which
--                        is how a mod status becomes curable: src/core/gen2/
--                        ItemEffects.lua reads it for any spelling its own
--                        STATUS_CLASS fold does not already know
--
-- Every consumer below reads through Battle:statusRecord, so a mod's sixth
-- status inflicts, chips, blocks a turn and cuts a stat like the vanilla six.
Battle.STATUSES = {
  sleep = {
    id = "sleep", label = "SLP", hudLabel = "SLP", healClass = "slp",
    inflictText = " fell asleep!",
    catchBonus = 10, catchBonusIntended = 10,
    -- BattleCommand_Sleep rolls a 3-bit value, retried until nonzero.
    onInflict = function(battle, mon)
      mon.statusTurns = rand(battle.random, 7) + 1
    end,
    beforeMovePriority = 40,
    beforeMove = function(battle, mon, name)
      mon.statusTurns = (mon.statusTurns or 1) - 1
      if mon.statusTurns <= 0 then
        mon.status = nil
        mon.statusTurns = nil
        battle:emit({ kind = "message", text = name .. " woke up!" })
        return true
      end
      battle:emit({ kind = "message", text = name .. " is fast asleep!" })
      return false
    end,
  },
  poison = {
    id = "poison", label = "PSN", hudLabel = "PSN", healClass = "psn",
    inflictText = " was poisoned!",
    catchBonus = 0, catchBonusIntended = 5,
    residual = function(_, _, maxHp)
      return math.max(1, math.floor(maxHp / Battle.POISON_FRACTION)),
        " is hurt by poison!"
    end,
  },
  toxic = {
    -- SUBSTATUS_TOXIC rides the poison byte, so the HUD says PSN either way.
    id = "toxic", label = "PSN", hudLabel = "PSN", healClass = "psn",
    inflictText = " was badly poisoned!",
    catchBonus = 0, catchBonusIntended = 5,
    onInflict = function(_, mon) mon.toxicCounter = 1 end,
    -- Toxic ramps: n/16 of max HP on the nth turn.
    residual = function(_, mon, maxHp)
      local counter = mon.toxicCounter or 1
      mon.toxicCounter = counter + 1
      return math.max(1, math.floor(maxHp * counter / 16)),
        " is hurt by poison!"
    end,
  },
  paralyze = {
    id = "paralyze", label = "PAR", hudLabel = "PAR", healClass = "par",
    inflictText = " is paralyzed! It may be unable to move!",
    catchBonus = 0, catchBonusIntended = 5,
    statPenalty = { stat = "speed", div = Battle.PARALYSIS_SPEED_DIVISOR },
    -- CheckPlayerTurn's last arm: after the flinch and confusion block.
    beforeMovePriority = 10,
    beforeMove = function(battle, mon, name)
      if rand(battle.random, Battle.PARALYSIS_SKIP_CHANCE) ~= 0 then
        return true
      end
      battle:emit({ kind = "message", text = name .. "'s fully paralyzed!" })
      return false
    end,
  },
  burn = {
    id = "burn", label = "BRN", hudLabel = "BRN", healClass = "brn",
    inflictText = " was burned!",
    catchBonus = 0, catchBonusIntended = 5,
    statPenalty = { stat = "attack", div = Battle.BURN_ATTACK_DIVISOR },
    residual = function(_, _, maxHp)
      return math.max(1, math.floor(maxHp / Battle.BURN_FRACTION)),
        " is hurt by its burn!"
    end,
  },
  freeze = {
    id = "freeze", label = "FRZ", hudLabel = "FRZ", healClass = "frz",
    inflictText = " was frozen solid!",
    catchBonus = 10, catchBonusIntended = 10,
    beforeMovePriority = 30,
    beforeMove = function(battle, mon, name)
      if rand(battle.random, Battle.THAW_CHANCE) == 0 then
        mon.status = nil
        battle:emit({ kind = "message", text = name .. " thawed out!" })
        return true
      end
      battle:emit({ kind = "message", text = name .. " is frozen solid!" })
      return false
    end,
  },
  -- SUBSTATUS_CONFUSED: it lives in the volatile beside the major status, so
  -- applyStatus hands it to applyConfusion rather than writing mon.status.
  -- It is a record all the same because its landing line is one of the seven
  -- src/core/gen2/ItemEffects.lua is held against.
  confuse = {
    id = "confuse", label = "CONFUSED", inflictText = " became confused!",
    substatus = true,
  },
}

-- beforeMovePriority above this runs ahead of the flinch/confusion block,
-- at or below after it -- CheckPlayerTurn's order, and the same constant
-- src/battle/Status.lua uses for the Gen 1 gauntlet.
Battle.VOLATILE_PRIORITY = 20

-- vanilla registrations, engine-owned (Schemas.ENGINE), so a mod's register of
-- one of these ids collides the way it does on Red and has to say override
function Battle.registerStatusesInto(registry, _, owner)
  for id, record in pairs(Battle.STATUSES) do
    registry:register(id, record, owner)
  end
end

-- Kept as the derived view of the records: src/core/gen2/ItemEffects.lua's
-- cross-file contract (every name Battle can write into mon.status resolves to
-- a heal class) is checked against this table, and building it from STATUSES
-- is what stops the two from drifting.
Battle.STATUS_TEXT = {}
for id, record in pairs(Battle.STATUSES) do
  Battle.STATUS_TEXT[id] = record.inflictText
end

-- The merged `statuses` record for a status id, the module's own when no
-- loader ran -- src/battle/BattleState.lua:effectRecord is the Gen 1 twin.
-- A plain function over `data` rather than a method on purpose: the tests
-- drive canAct and tickStatus against hand-built actor stubs that carry a mon
-- and an emit and nothing else, and a lookup that needed a method would make
-- every one of those stubs implement it.
function Battle.statusRecordFor(data, status)
  if status == nil then return nil end
  local merged = data and data.gen2Statuses
  return (merged and merged[status]) or Battle.STATUSES[status]
end

-- The one stat this mon's status cuts, applied.  Burn halves Attack and
-- paralysis quarters Speed on the cart; both come off statPenalty so a mod
-- status cuts a stat through the same seam.
function Battle.statusPenaltyFor(data, mon, stat, value)
  local record = Battle.statusRecordFor(data, mon and mon.status)
  local penalty = record and record.statPenalty
  if not penalty or penalty.stat ~= stat then return value end
  return math.max(1, math.floor(value / math.max(1, penalty.div or 1)))
end

-- engine/battle/effect_commands.asm:6325
function Battle:safeguarded(mon)
  return (self.screens[self:sideOf(mon)].safeguard or 0) > 0
end

-- `source` is the battler that inflicted it, carried only so
-- battle.status_inflicted can name it the way Gen 1's does.
-- BattleCommand_Paralyze and BattleCommand_Poison refuse on a zero matchup,
-- and the poison pair also refuses a POISON-type target: effect_commands.asm
-- :5788 (paralyze), :3671 (poison), :3646 / :4019 (the secondary arms).
-- Sleep, confusion and stat changes are deliberately not gated.
function Battle:statusRefusedByType(defender, moveType, status)
  if not (status == "paralyze" or status == "poison" or status == "toxic") then
    return false
  end
  local types = (self:speciesDef(defender) or {}).types or defender.types or {}
  if moveType then
    local matchups = self.data.type_chart and self.data.type_chart.matchups
    if Damage.typeMultiplier(moveType, types, matchups) == 0 then return true end
  end
  if status == "poison" or status == "toxic" then
    for _, t in ipairs(types) do
      if t == "POISON" then return true end
    end
  end
  return false
end

function Battle:applyStatus(mon, status, source)
  if (mon.hp or 0) <= 0 then return false end
  -- Confusion is SUBSTATUS_CONFUSED on the cart, not a status byte: it lives
  -- in the volatile beside the major status, so a confused mon can still be
  -- burned and a switch shakes the confusion off.
  if status == "confuse" then return self:applyConfusion(mon, nil, source) end
  -- engine/battle/effect_commands.asm:6338
  if source and self:sideOf(source) ~= self:sideOf(mon)
      and self:safeguarded(mon) then
    self:emit({ kind = "message",
      text = self:monName(mon) .. " is protected by SAFEGUARD!" })
    return false
  end
  -- One major status at a time.
  if mon.status then
    self:emit({ kind = "message",
      text = "But it failed!" })
    return false
  end
  mon.status = status
  -- Through the merged record: onInflict is where the sleep roll and the Toxic
  -- counter live, so a mod status can arm its own counter here too.
  local record = Battle.statusRecordFor(self.data, status)
  if record and record.onInflict then record.onInflict(self, mon) end
  self:emit({ kind = "status", side = self:sideOf(mon), status = status,
    text = self:monName(mon)
      .. ((record and record.inflictText) or " is afflicted!") })
  -- battle.status_inflicted, the payload src/battle/StatusRegistry.lua emits on
  -- Gen 1, for the major status only -- confusion is a substatus in both
  -- generations and Gen 1 raises nothing for it either.  The `status` VALUE is
  -- Gen 2's own spelling ("poison", "burn", "paralyze"), not Gen 1's PSN/BRN
  -- code: the key still names the status that landed, and Gold's engine has no
  -- three-letter codes to report.
  Runtime.emit("battle.status_inflicted", {
    battle = self, target = mon, status = status, source = source,
    side = self:sideOf(mon),
  })
  return true
end

-- BattleCommand_FinishConfusingTarget (effect_commands.asm:5734): the
-- SUBSTATUS_CONFUSED bit plus a 2-5 turn count (`and %11` plus two).
-- `turns` is the Berserk Gene's override: HandleBerserkGene sets the bit
-- WITHOUT writing the count (core.asm:301), and the zero count decrements
-- through zero on the cart -- an effectively permanent lock, modelled here
-- as 256 turns.  HELD_PREVENT_CONFUSE on the target blocks it outright.
Battle.BERSERK_GENE_CONFUSE_TURNS = 256

function Battle:applyConfusion(mon, turns, source)
  if (mon.hp or 0) <= 0 then return false end
  -- engine/battle/effect_commands.asm:6338
  if source and self:sideOf(source) ~= self:sideOf(mon)
      and self:safeguarded(mon) then
    self:emit({ kind = "message",
      text = self:monName(mon) .. " is protected by SAFEGUARD!" })
    return false
  end
  local state = self:volatile(mon)
  if (state.substitute or 0) > 0 then return false end
  local held = self:heldEffect(mon, "confuse")
  if held == "HELD_PREVENT_CONFUSE" then return false end
  if state.confuseCount then
    self:emit({ kind = "message",
      text = self:monName(mon) .. "'s already confused!" })
    return false
  end
  state.confuseCount = turns or (rand(self.random, 4) + 2)
  local record = Battle.statusRecordFor(self.data, "confuse")
  self:emit({ kind = "message",
    text = self:monName(mon)
      .. ((record and record.inflictText) or " became confused!") })
  return true
end

-- ResidualDamage picks the anim off the status byte, ANIM_BRN for a burn and
-- ANIM_PSN for either poison (engine/battle/core.asm:958-976).
Battle.RESIDUAL_ANIM = {
  burn = "ANIM_BRN", poison = "ANIM_PSN", toxic = "ANIM_PSN",
}

-- End of turn: burn and poison chip damage, through the merged record's
-- `residual`.  The record computes and advances its own counter; the emit pair
-- stays here because the event shape belongs to this engine, not to the status.
function Battle:tickStatus(mon)
  if (mon.hp or 0) <= 0 or not mon.status then return end
  local record = Battle.statusRecordFor(self.data, mon.status)
  local residual = record and record.residual
  if not residual then return end
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 1
  local name = self:monName(mon)
  local damage, text = residual(self, mon, maxHp)
  if not damage or damage <= 0 then return end
  mon.hp = math.max(0, mon.hp - damage)
  self:emit({ kind = "message", text = name .. (text or " is hurt!") })
  -- Call_PlayBattleAnim_OnlyIfVisible runs on the sufferer's own turn
  -- (core.asm:970-976); a mod status the cart never had gets nothing.
  self:emit({ kind = "damage", side = self:sideOf(mon), amount = damage,
    hp = mon.hp, anim = Battle.RESIDUAL_ANIM[mon.status] or false,
    animSide = self:sideOf(mon) })
end

-- Faint bookkeeping and experience.  Returns true when the battle ended.
function Battle:resolveFaints()
  if (self.enemy.hp or 0) <= 0 then
    self:emit({ kind = "faint", side = "enemy",
      text = (self.wild and "Wild " or "") .. self:monName(self.enemy)
        .. " fainted!" })
    -- battle.fainted, the payload BattleState:onFaint emits on Gen 1.
    -- `battler` is the mon itself here: Gen 2's engine has no battler wrapper.
    Runtime.emit("battle.fainted", { battle = self, battler = self.enemy,
      side = self:sideRecord(self.enemy) })
    self:awardExperience(self.enemy)
    local nextIndex = Battle.firstHealthy(self.enemyParty)
    if not nextIndex then
      if self.trainer then
        self:emit({ kind = "message",
          text = (self.trainer.name or "TRAINER") .. " was defeated!" })
        self:awardPrizeMoney()
      end
      -- CheckPayDay, on the win arm only (engine/battle/core.asm:7971-7976,
      -- :8014-8042).
      local coins = Prize.payDay(self.save, self.payDay, self.amuletCoin)
      if coins then
        self:emit({ kind = "money", text = Prize.payDayMessage(coins,
          self.save.player and self.save.player.name) })
      end
      self.payDay = nil
      self:endBattle("win")
      return true
    end
    local previous = self.enemy
    self:clearVolatile(self.enemy)
    self.enemyIndex = nextIndex
    self.enemy = self.enemyParty[nextIndex]
    -- ResetEnemyBattleVars (engine/battle/core.asm:3016) and NewEnemyMonStatus
    -- clear the move selection and the substatus bytes for the mon coming IN,
    -- so a replacement never inherits anything from its last stint.
    self:clearVolatile(self.enemy)
    self.stages.enemy = Battle.newStages()
    -- `replacement` marks HandleEnemySwitch's send, the only one EnemySwitch
    -- can offer a shift on (engine/battle/core.asm:2241-2278).
    self:emit({ kind = "send", side = "enemy", mon = self.enemy,
      replacement = true,
      text = (self.trainer and self.trainer.name or "Foe") .. " sent out "
        .. self:monName(self.enemy) .. "!" })
    Runtime.emit("battle.battler_switched", {
      battle = self, side = self:sideRecord(self.enemy), battler = self.enemy,
      previous = previous,
    })
    self:breakTrapsOnSend(self.enemy)
    -- core.asm runs SpikesDamage on every send-out; the faint replacement
    -- is not exempt.
    self:spikesDamage(self.enemy)
    -- Battle_PlayerFirst reaches HandleEnemyMonFaint with `jp`, not `call`
    -- (engine/battle/core.asm:872), so the round's attack phase is over: the
    -- mon that just walked in never answers, and the move that was queued for
    -- the one it replaced is never spent.  Battle:takeTurn reads this.
    self.faintInterrupt = true
    return false
  end

  if (self.player.hp or 0) <= 0 then
    -- Announce a faint ONCE.
    --
    -- This branch is the only one that returns without changing whose turn it
    -- is: it emits `choose-switch` and waits for the caller to pick, so the
    -- caller calls back in with the same mon still at 0 HP and the whole branch
    -- ran again.  The visible symptom was "TYPHLOSION fainted!" three times in
    -- a row, but the real damage is one line lower -- `faintHappiness` was
    -- charged once per re-entry, so a single faint cost two or three times the
    -- happiness the cart takes (engine/battle/core.asm, HandlePlayerMonFaint
    -- runs its happiness arm once).
    --
    -- Keyed on the mon itself, so the next one in announces normally.
    if self.faintAnnounced ~= self.player then
      self.faintAnnounced = self.player
      self:emit({ kind = "faint", side = "player",
        text = self:monName(self.player) .. " fainted!" })
      Runtime.emit("battle.fainted", { battle = self, battler = self.player,
        side = self:sideRecord(self.player) })
      self:faintHappiness(self.player)
    end
    local nextIndex = Battle.firstHealthy(self.party)
    if not nextIndex then
      self:emit({ kind = "message", text = "You have no more POKéMON!" })
      self:endBattle("lose")
      return true
    end
    -- The player picks the replacement; the caller drives that with :switch.
    --
    -- Asked for ONCE, keyed the same way the faint line above is: takeTurn
    -- reaches resolveFaints up to three times in a round, and every one of
    -- them still sees a 0 HP mon because nothing switches until the player
    -- answers.  HandlePlayerMonFaint runs ForcePlayerMonChoice a single time
    -- (engine/battle/core.asm:2543) and the turn loop does not come back for
    -- another; three prompts in the queue meant the party menu reopened on top
    -- of the pick that had already been made, so the switch looked like it
    -- took two or three attempts.  Battle:switch releases the guard.
    if not self.pendingSwitch then
      self.pendingSwitch = true
      self:emit({ kind = "choose-switch" })
    end
    -- Same `jp`, not `call`, as the enemy arm above (core.asm:874): whatever
    -- is left of the attack phase is abandoned.
    self.faintInterrupt = true
    return false
  end
  return false
end

-- WinTrainerBattle's money arm, which runs after BattleText_EnemyWasDefeated
-- and the frontpic slide: the four quarters are dealt between the wallet and
-- Mom's savings and then one StdBattleTextbox names the figure.
--
-- The `ld a, [wDebugFlags] / bit DEBUG_BATTLE_F` skip in front of
-- PrintWinLossText is the trainer's own after-battle line, which this port
-- runs from the script on the way out of the battle rather than from here.
-- The payout is not gated on it either way.
function Battle:awardPrizeMoney()
  local save = self.save
  if not (save and save.player) then return nil end
  local award = Prize.award(save, {
    baseMoney = self.trainer and self.trainer.baseMoney,
    -- wCurPartyLevel, left behind by ReadTrainerParty: the LAST row of the
    -- roster, whatever order the mons actually fainted in.
    level = Prize.rewardLevel(self.enemyParty),
    amuletCoin = self.amuletCoin,
  })
  self.prize = award
  self:emit({ kind = "money", award = award,
    text = Prize.message(award, save.player and save.player.name) })
  return award
end

-- UpdateFaintedPlayerMon (engine/battle/core.asm), the happiness half.  Runs
-- on EVERY player faint, not only the whiteout, and picks between two events
-- by how outclassed the mon was:
--
--   ld a, [wBattleMonLevel] / add 30 / ld b, a
--   ld a, [wEnemyMonLevel]  / cp b   / jr c, .got_param
--
-- `jr c` keeps HAPPINESS_FAINTED while the foe is BELOW yourLevel + 30, so the
-- harsher HAPPINESS_BEATENBYSTRONGFOE needs the foe to be at least thirty
-- levels up -- and the two events differ only in the third tier anyway (-1 for
-- a plain loss against -10 for a beating, at happiness 200 or more).
function Battle:faintHappiness(mon)
  if not mon then return end
  local event = "FAINTED"
  if (self.enemy.level or 0) >= (mon.level or 0) + 30 then
    event = "BEATENBYSTRONGFOE"
  end
  -- ChangeHappiness runs against the party slot, and this mon IS that slot's
  -- table, so a fainted mon is still the thing that loses the point.
  Happiness.change(mon, event)
end

-- GiveExperiencePoints' traded check: the mon's OT id against wPlayerID.  A
-- mon with no recorded OT (the port's native catches and gifts) is the
-- player's own.
function Battle:isOutsider(mon)
  local playerId = self.save and self.save.player and self.save.player.id
  if mon.traded == true then return true end
  if mon.otId == nil or playerId == nil then return false end
  return mon.otId ~= playerId
end

-- One pass of GiveExperiencePoints over `recipients` (party indices).
-- `count` is the pass's own divisor -- the participant count for the first
-- pass, the holder count for the EXP.SHARE pass -- and `halved` is whether
-- any Share holder taxed the whole pool.
function Battle:giveExperiencePass(loser, def, recipients, count, halved)
  for _, index in ipairs(recipients) do
    local mon = self.party[index]
    if mon and (mon.hp or 0) > 0 and not mon.isEgg then
      local traded = self:isOutsider(mon)
      -- `cp LUCKY_EGG` on the mon's item byte: by id, not held effect.
      local luckyEgg = mon.item == "LUCKY_EGG"
      -- exp.gain, the same hook src/battle/Experience.lua calls on Gen 1 and
      -- with the same ctx keys (defeatedDef, level, isTrainer, participants,
      -- traded, mon), so a mod that scales exp reads and edits the fields it
      -- did on Red.  `halved` (the EXP.SHARE tax on the whole pool) and
      -- `luckyEgg` are Gen 2's own multipliers and ride beside them.
      local amount
      if Runtime.wantsHook("exp.gain") then
        amount = Runtime.call("exp.gain", function(c)
          return Mon.experienceGain(c.defeatedDef, c.level, c.participants,
            c.isTrainer, { halved = c.halved, traded = c.traded,
                           luckyEgg = c.luckyEgg })
        end, { defeatedDef = def, level = loser.level,
               isTrainer = self.trainer ~= nil, participants = count,
               traded = traded, mon = mon,
               halved = halved, luckyEgg = luckyEgg,
               battle = self, loser = loser })
      else
        amount = Mon.experienceGain(def, loser.level, count,
          self.trainer ~= nil, { halved = halved, traded = traded,
                                 luckyEgg = luckyEgg })
      end
      -- Stat exp first: GiveExperiencePoints awards it before the exp points,
      -- so a mon that levels on this kill recalculates its stats with the
      -- effort it just earned already counted.  Pokerus (or the immune marker
      -- a cured mon keeps) doubles it.
      Mon.gainStatExp(mon, def, count, Pokerus.doublesStatExp(mon), halved)
      local result = Mon.gainExperience(mon, amount, self.data)
      -- battle.exp_gained, the payload BattleState:awardExp emits on Gen 1.
      -- `levels` is the LIST of levels reached, the same shape Gen 1's
      -- Experience.apply returns, built out of Gen 2's from/to pair -- and
      -- built only when something is listening, since a KO in a six-mon party
      -- comes through here once per recipient.
      if Runtime.wants("battle.exp_gained") then
        local levels = {}
        for level = (result.from or 0) + 1, result.to or 0 do
          levels[#levels + 1] = level
        end
        Runtime.emit("battle.exp_gained", {
          battle = self, mon = mon, gained = amount, levels = levels,
          -- Gen 2 addition: the party slot, which is what the engine's own
          -- experience event is keyed by.
          index = index,
        })
      end
      self:emit({ kind = "experience", index = index, amount = amount,
        -- BoostedExpPointsText, keyed on the traded arm alone.
        text = self:monName(mon) .. " gained "
          .. (traded and "a boosted " or "") .. amount .. " EXP. Points!" })
      if result.levels > 0 then
        -- "level up happiness mod", the cart's own comment, sitting right
        -- after the stat recalc and before the "grew to level" text.  It fires
        -- ONCE per exp award however many levels the mon jumped, because
        -- ChangeHappiness is outside the level loop.
        Happiness.change(mon, "GAINLEVEL")
        self:emit({ kind = "level", index = index, level = mon.level,
          text = self:monName(mon) .. " grew to level " .. mon.level .. "!",
          sfx = "Sfx_DexFanfare5079", waitSfx = true })
        for _, moveId in ipairs(result.learned) do
          local ok, reason, entry = Mon.learnMove(mon, moveId, self.data)
          local moveDef = self:moveDef(moveId)
          local moveName = (moveDef and moveDef.name) or moveId
          if ok then
            self:emit({ kind = "message",
              text = self:monName(mon) .. " learned " .. moveName .. "!" })
          elseif reason == "full" then
            -- LearnMove's full-moveset arm calls ForgetMove, which asks with
            -- AskForgetMoveText (engine/pokemon/learn.asm:29-34, :121-124).
            self:emit({ kind = "choose-forget", index = index, move = entry,
              moveName = moveName })
          end
        end
      end
    end
  end
end

-- PokeBallEffect's captured tail, the battle half of it: the catch site
-- (src/ui/gen2/BattleState.lua:pushCaught) owns the #DEX, the party and the
-- nickname prompt, and this owns what the BATTLE still has to say about the
-- mon that was just taken off the field.  The Gen 1 twin is
-- src/battle/BattleState.lua:storeCaughtMon, which opens on exactly these two
-- steps in this order.
--
--   * the reload.  `.catch_without_fail` puts wTempEnemyMonSpecies -- the
--     species the mon was SENT OUT as, which no move rewrites -- into
--     wCurPartySpecies before the mon is added, so a DITTO that transformed is
--     caught as a DITTO with its own moves.  Gen 1 does the same thing for
--     Mimic (BattleState:restoreMimicked, cited at its own call).
--   * battle.catch_exp.  Vanilla catches never grant exp; a mod can flip the
--     hook to true to pay out the same award a faint would have.  Same name,
--     same default and the same one-key ctx as the Gen 1 site, so one
--     subscription covers both games (docs/mod-api-gen2-compat.md).
--
-- Safe to call more than once: the reload is a no-op once the identity is
-- back, and `caughtHandled` keeps a second call from paying the exp twice.
function Battle:caught(mon)
  mon = mon or self.enemy
  if self.caughtHandled then return mon end
  self.caughtHandled = true
  self:untransform(mon)
  if Runtime.wantsHook("battle.catch_exp")
      and Runtime.call("battle.catch_exp", function() return false end,
        { battle = self }) then
    self:awardExperience(mon)
  end
  return mon
end

-- GiveExperiencePoints, both calls (engine/battle/core.asm:2116/2130): with
-- any live EXP.SHARE holder in the party the enemy's base exp and base
-- stats are halved up front, the participants split the first pass, and a
-- second pass pays every holder -- participant or not, so a holder that
-- fought collects twice.  Holders are found by ITEM id, the way
-- IsAnyMonHoldingExpShare's `cp EXP_SHARE` does, and a fainted holder gets
-- nothing (the pass loop skips fainted mons).
function Battle:awardExperience(loser)
  local def = self:speciesDef(loser)

  local participants = {}
  for index in pairs(self.participants) do
    participants[#participants + 1] = index
  end
  table.sort(participants)

  local holders = {}
  for index, mon in ipairs(self.party) do
    if (mon.hp or 0) > 0 and not mon.isEgg and mon.item == "EXP_SHARE" then
      holders[#holders + 1] = index
    end
  end

  local halved = #holders > 0
  local function vanillaAward()
    self:giveExperiencePass(loser, def, participants, #participants, halved)
    if halved then
      self:giveExperiencePass(loser, def, holders, #holders, true)
    end
  end

  -- battle.exp_award, the same hook BattleState:awardExp calls on Gen 1 and
  -- with the same ctx: the participant COUNT, the live participants, and an
  -- applyShare(mon, split) a mod can call to pay one mon its own share.  The
  -- third applyShare argument is Gen 1's EXP.ALL announcement variant; Gen 2
  -- has no EXP.ALL (the EXP.SHARE pass below is its replacement), so it is
  -- accepted and ignored rather than changing what is printed.  `recipients`,
  -- `holders` and `halved` are the Gen 2 additions.
  if Runtime.wantsHook("battle.exp_award") then
    local alive = {}
    for _, index in ipairs(participants) do
      local mon = self.party[index]
      if mon and (mon.hp or 0) > 0 then alive[#alive + 1] = mon end
    end
    local function applyShare(mon, split)
      for index, candidate in ipairs(self.party) do
        if candidate == mon then
          return self:giveExperiencePass(loser, def, { index },
            math.max(1, split or 1), halved)
        end
      end
    end
    Runtime.call("battle.exp_award", vanillaAward, {
      battle = self, participants = #participants, alive = alive,
      applyShare = applyShare, recipients = participants, holders = holders,
      halved = halved, loser = loser,
    })
  else
    vanillaAward()
  end

  -- GiveExperiencePoints .done falls through ResetBattleParticipants into
  -- AddBattleParticipant (engine/battle/core.asm:7116 and :3033).
  self.participants = {}
  if self.playerIndex then self.participants[self.playerIndex] = true end
end

-- The answer to a `choose-forget`: drop the move in `slot` and put the
-- pending one there, then queue the cart's "forgot X / learned Y" lines.  The
-- battle slot aliases the party slot the same way Mimic does, so a mon in play
-- picks up the new move immediately.
function Battle:resolveForget(index, slot, entry, moveName)
  local mon = self.party[index]
  if not (mon and mon.moves and mon.moves[slot] and entry) then return false end
  local old = mon.moves[slot]
  local oldDef = self:moveDef(old.id)
  local oldName = (oldDef and oldDef.name) or old.id
  mon.moves[slot] = entry
  -- Keep the in-play battler's move list pointing at the same table, so a mon
  -- that levelled mid-battle fights the rest of it with the new move.
  if self.player == mon and self.player.moves ~= mon.moves then
    self.player.moves = mon.moves
  end
  self:emit({ kind = "message",
    text = "1, 2 and… " .. self:monName(mon) .. " forgot " .. oldName .. "!" })
  self:emit({ kind = "message",
    text = self:monName(mon) .. " learned "
      .. (moveName or (entry and entry.id) or "?") .. "!" })
  -- The forget path writes the slot itself rather than going through
  -- Mon.learnMove, so pokemon.move_learned is raised here too: a move WAS
  -- learned, and a mod counting moves must not miss the four-slot case.
  Runtime.emit("pokemon.move_learned", { mon = mon, moveId = entry.id })
  return true
end

-- The other answer: keep the four it has.  MoveDidntLearn's line.
function Battle:declineForget(index, moveName)
  local mon = self.party[index]
  self:emit({ kind = "message",
    text = (mon and self:monName(mon) or "It") .. " did not learn "
      .. (moveName or "the move") .. "." })
end

-- NewBattleMonStatus / the enemy switch tail (core.asm:3864 and 3405): ANY
-- send-out ends BOTH partial traps and drops the CANT_RUN pin that was aimed
-- at the incoming side -- whose holder is the opponent, so it is the
-- opponent's volatile that carries it.
function Battle:breakTrapsOnSend(incoming)
  for _, mon in ipairs({ self.player, self.enemy }) do
    local state = self:volatile(mon)
    state.wrapCount, state.wrapMove, state.wrapMoveId = nil, nil, nil
  end
  local opponent = (incoming == self.player) and self.enemy or self.player
  self:volatile(opponent).trapsTarget = nil
end

-- TryPlayerSwitch's `.check_trapped` (core.asm:4886): a live wrap on the
-- active mon or the enemy's CANT_RUN pin refuses a VOLUNTARY switch with
-- "can't be recalled!".  The faint replacement path never asks.
function Battle:switchLocked()
  if (self:volatile(self.player).wrapCount or 0) > 0 then return true end
  return self:volatile(self.enemy).trapsTarget == true
end

-- EnemySwitch's shift arm zeroes both participant bitfields before PlayerSwitch
-- (engine/battle/core.asm:2959-2961).
function Battle:shiftSwitch(index)
  self.participants = {}
  return self:switch(index)
end

-- Switch the player's active mon.  A switch takes the whole turn.
function Battle:switch(index)
  local mon = self.party[index]
  if not mon or (mon.hp or 0) <= 0 then return false end
  if mon == self.player then return false end
  -- Switching out drops every volatile: the Substitute, the charge, the
  -- Rollout ramp and the stat stages all go with it.  The incoming mon starts
  -- from an empty area too (NewBattleMonStatus runs at every send-out), so a
  -- mon that comes back in carries nothing from its last stint.
  local previous = self.player
  self:clearVolatile(self.player)
  self:clearVolatile(mon)
  -- A mon that comes back (a REVIVE, or a second battle) has to be able to
  -- announce its own faint again; see resolveFaints.
  self.faintAnnounced = nil
  -- ForcePlayerMonChoice has been answered, so the next faint may ask again.
  self.pendingSwitch = nil
  self.player = mon
  self.playerIndex = index
  self.participants[index] = true
  self.stages.player = Battle.newStages()
  self:emit({ kind = "send", side = "player", mon = mon,
    text = "Go! " .. self:monName(mon) .. "!" })
  -- battle.battler_switched, the payload BattleState:resolveSwitch emits on
  -- Gen 1: the side record, whoever walked in, and whoever walked out.
  Runtime.emit("battle.battler_switched", {
    battle = self, side = self:sideRecord(mon), battler = mon,
    previous = previous,
  })
  self:breakTrapsOnSend(mon)
  self:checkAmuletCoin(mon)
  self:spikesDamage(mon)
  return true
end

-- CheckAmuletCoin (engine/battle/core.asm), which sits in the send-out path
-- rather than in the payout: `ld a, [wBattleMonItem] / GetItemHeldEffect / cp
-- HELD_AMULET_COIN`, then a 1 into wAmuletCoin.  Nothing clears the byte for
-- the rest of the battle, so a mon that was sent out holding the coin still
-- doubles the prize after it has fainted or been switched away.
function Battle:checkAmuletCoin(mon)
  if mon and mon.item == Prize.AMULET_COIN then self.amuletCoin = true end
end

-- HandleBerserkGene (engine/battle/core.asm:301).  Checked by ITEM id, not
-- held effect (`sub BERSERK_GENE` on the item byte; its attribute byte is
-- HELD_NONE on the cart).  The gene is consumed, Attack jumps two stages
-- (BattleCommand_AttackUp2) and the holder is confused -- with no count
-- written on the cart, the near-permanent lock the walkthroughs warn about
-- (Battle.BERSERK_GENE_CONFUSE_TURNS).
function Battle:checkBerserkGene(mon)
  if not mon or mon.item ~= "BERSERK_GENE" or (mon.hp or 0) <= 0 then
    return false
  end
  local def = self:itemDef(mon.item)
  mon.item = nil
  self:emit({ kind = "message",
    text = self:monName(mon) .. "'s "
      .. ((def and def.name) or "BERSERK GENE") .. " activated!" })
  self:changeStage(mon, "attack", 2)
  self:applyConfusion(mon, Battle.BERSERK_GENE_CONFUSE_TURNS)
  return true
end

-- BattleCommand_CheckObedience's badge ladder: the obedience cap by owned
-- Johto badges.  MAX_LEVEL + 1 for RISINGBADGE means nothing ever disobeys.
function Battle:obedienceLevel()
  if self:hasBadge("badges", "RISING") then return Mon.MAX_LEVEL + 1 end
  if self:hasBadge("badges", "STORM") then return 70 end
  if self:hasBadge("badges", "FOG") then return 50 end
  if self:hasBadge("badges", "HIVE") then return 30 end
  return 10
end

-- The cart's `.rand1` / `.rand2`: one byte, re-rolled until it lands under
-- `limit`.  Guarded so an injected test roller that never goes low cannot
-- spin forever; the fallback fold keeps the result in range.
function Battle:rollBelow(limit)
  for _ = 1, 128 do
    local roll = rand(self.random, 256)
    if roll < limit then return roll end
  end
  return rand(self.random, 256) % math.max(1, limit)
end

-- HitConfusion (engine/battle/effect_commands.asm:613): a typeless 40 power
-- physical hit against the user's OWN Defense -- stat stages and the badge
-- boosts apply through wPlayerStats, but there is no crit, no STAB, no type
-- row and no damage variation; DamageCalc's MIN_DAMAGE floor still holds.
-- Shared by the confusion self-hit and the disobedience self-hit.
function Battle:confusionSelfHit(mon)
  local stages = self.stages[self:sideOf(mon)]
  local attack = Damage.applyStage(self:battleStat(mon, "attack"),
    stages.attack or 0)
  attack = Battle.statusPenaltyFor(self.data, mon, "attack", attack)
  local defense = Damage.applyStage(self:battleStat(mon, "defense"),
    stages.defense or 0)
  local damage = Damage.base(mon.level or 1, 40, attack, defense)
  damage = math.min(damage, Damage.MAX_DAMAGE - Damage.MIN_DAMAGE)
    + Damage.MIN_DAMAGE
  self:emit({ kind = "message",
    text = "It hurt itself in its confusion!" })
  mon.hp = math.max(0, (mon.hp or 0) - damage)
  -- HitConfusion flickers with ANIM_HIT_CONFUSION on the self-hitter's own
  -- turn, not the move after-anim (effect_commands.asm:624-632, :521-529).
  self:emit({ kind = "damage", side = self:sideOf(mon), amount = damage,
    hp = mon.hp, anim = "ANIM_HIT_CONFUSION", animSide = self:sideOf(mon) })
  return damage
end

-- BattleCommand_CheckObedience (engine/battle/effect_commands.asm:642).
-- Player side only; an outsider mon (OT id differs from the player's) above
-- the badge-gated level cap rolls to obey.  Returns true when the mon
-- disobeyed and the turn is spent.
--
-- The outcome ladder, in the asm's order: a first roll under the cap obeys;
-- a second roll under the cap uses a DIFFERENT move instead; past both, the
-- margin above the cap decides between napping, hitting itself and one of
-- the four loafing lines.
function Battle:checkObedience(moveId)
  local mon = self.player
  if not mon then return false end
  -- CheckUserIsCharging: the stored half of a two-turn move is exempt.
  if self:volatile(mon).chargeMove then return false end
  local save = self.save
  local playerId = save and save.player and save.player.id
  if mon.otId == nil or playerId == nil or mon.otId == playerId then
    return false
  end
  local cap = self:obedienceLevel()
  local level = mon.level or 1
  if level <= cap then return false end
  local limit = math.min(255, cap + level)
  if self:rollBelow(limit) < cap then return false end

  local name = self:monName(mon)
  if self:rollBelow(limit) < cap then
    -- `.UseInstead`: another known move with PP, never the picked one and
    -- never a disabled one; with no alternative it falls through to
    -- loafing.
    local others = {}
    for _, move in ipairs(mon.moves or {}) do
      if move.id ~= moveId and (move.pp or 0) > 0
          and not self:moveDisabled(mon, move.id) then
        others[#others + 1] = move.id
      end
    end
    if #others > 0 then
      local pick = others[rand(self.random, #others) + 1]
      self:useMove(mon, self.enemy, pick)
      return true
    end
  end

  local margin = level - cap
  local roll = rand(self.random, 256)
  if roll < margin then
    -- `.Nap`: 1-7 turns of sleep written STRAIGHT into the status byte,
    -- over whatever was there.
    mon.status = "sleep"
    mon.statusTurns = rand(self.random, 7) + 1
    mon.toxicCounter = nil
    self:emit({ kind = "status", side = self:sideOf(mon), status = "sleep",
      text = name .. " began to nap!" })
    return true
  end
  if roll - margin < margin then
    self:emit({ kind = "message", text = name .. " won't obey!" })
    self:confusionSelfHit(mon)
    return true
  end
  -- `.DoNothing`: one of four lines.
  local lines = {
    " is loafing around.", " won't obey!", " turned away!",
    " ignored orders!",
  }
  self:emit({ kind = "message",
    text = name .. lines[rand(self.random, 4) + 1] })
  return true
end

-- The battle half of the PACK's battle items, dispatched by the screen
-- (src/ui/gen2/BattleState.lua): the four X items raise one stage
-- (XItemEffect -> RaiseStat), and X ACCURACY / DIRE HIT / GUARD SPEC set
-- their SUBSTATUS bit, refusing a second use the way
-- WontHaveAnyEffect_NotUsedMessage does -- in that case the item is NOT
-- consumed and the turn not spent, which the false return tells the caller.
function Battle:useBattleItem(itemId)
  local stat = Battle.X_ITEM_STATS[itemId]
  if stat then
    local def = self:itemDef(itemId)
    self:emit({ kind = "message",
      text = "Used the " .. ((def and def.name) or itemId) .. "." })
    self:changeStage(self.player, stat, 1)
    return true
  end
  local field = Battle.SUBSTATUS_ITEMS[itemId]
  if not field then return false, "unknown" end
  local state = self:volatile(self.player)
  if state[field] then return false, "no-effect" end
  state[field] = true
  local def = self:itemDef(itemId)
  self:emit({ kind = "message",
    text = "Used the " .. ((def and def.name) or itemId) .. "." })
  if itemId == "GUARD_SPEC" then
    self:emit({ kind = "message",
      text = self:monName(self.player) .. "'s shrouded in MIST!" })
  elseif itemId == "DIRE_HIT" then
    self:emit({ kind = "message",
      text = self:monName(self.player) .. " is getting pumped!" })
  end
  return true
end

-- SpikesDamage (engine/battle/core.asm): an eighth of max HP the moment a mon
-- walks into them.  Gen 2 has one layer -- the stacking is Gen 3 -- but it
-- does have the Flying immunity: the routine reads wBattleMonType / the enemy
-- pair and `cp FLYING / ret z` on BOTH slots before GetEighthMaxHP, so a
-- Flying-type takes nothing and the line is not printed either.
function Battle:spikesDamage(mon)
  local side = self:sideOf(mon)
  if not self.spikes[side] or (mon.hp or 0) <= 0 then return end
  local def = self:speciesDef(mon)
  for _, monType in ipairs((def and def.types) or mon.types or {}) do
    if monType == "FLYING" then return end
  end
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 8
  local damage = math.max(1, math.floor(maxHp / 8))
  mon.hp = math.max(0, mon.hp - damage)
  self:emit({ kind = "message",
    text = self:monName(mon) .. " is hurt by SPIKES!" })
  -- SpikesDamage is text, HP and a HUD redraw: no anim (core.asm:3902-3910).
  self:emit({ kind = "damage", side = side, amount = damage, hp = mon.hp,
    anim = false })
end

-- CheckPlayerLockedIn (engine/battle/core.asm:533-556) quits ParsePlayerAction
-- outright for SUBSTATUS_ROLLOUT and SUBSTATUS_RAMPAGE, so a mon partway
-- through a Rollout or a Thrash is offered no menu, spends no PP (both
-- checkrollout and checkrampage skip past doturn) and makes no obedience
-- check.  Split out because playerAttack needs the same answer.
function Battle:lockedInMove(mon)
  local state = self:volatile(mon)
  if state.rolloutLock then return state.rolloutLock end
  if state.rampageMove and (state.rampageTurns or 0) > 0 then
    return state.rampageMove
  end
  return nil
end

-- Encore forces the move; Disable forbids one.  Both are read by the screen
-- (to grey out the move list) and by the enemy's own choice below.
function Battle:forcedMove(mon)
  local locked = self:lockedInMove(mon)
  if locked then return locked end
  local state = self:volatile(mon)
  if not state.encore then return nil end
  for _, move in ipairs(mon.moves or {}) do
    if move.id == state.encore and (move.pp or 0) > 0 then return state.encore end
  end
  -- Encore ends early when the move runs out of PP.
  state.encore, state.encoreTurns = nil, nil
  return nil
end

function Battle:moveDisabled(mon, moveId)
  return self:volatile(mon).disabled == moveId
end

-- The moves a side may actually pick this turn.
function Battle:usableMoves(mon)
  local forced = self:forcedMove(mon)
  -- CheckPlayerLockedIn quits ParsePlayerAction ahead of
  -- .CheckPlayerHasUsableMoves (core.asm:533-556), so a Rollout or a rampage
  -- that spent its last PP on the opening turn keeps running: no later turn
  -- of the lock spends any.  Encore is not in this exemption -- forcedMove
  -- ends it the moment the encored move runs dry.
  local locked = self:lockedInMove(mon)
  local out = {}
  for _, move in ipairs(mon.moves or {}) do
    local ok = (move.pp or 0) > 0 and not self:moveDisabled(mon, move.id)
    if move.id == locked then ok = true end
    if forced then ok = ok and move.id == forced end
    if ok then out[#out + 1] = move end
  end
  return out
end

-- Running: Gen 2's odds (engine/battle/core.asm TryToRunAwayFromBattle) are
-- based on the speed ratio and how many times you have tried this battle.
-- Trainers never let you run.
function Battle:tryRun(pSpd)
  -- .cant_escape and .cant_run_from_trainer leave wBattlePlayerAction alone,
  -- which is what BattleMenu_Run reads to decide whether the turn was spent
  -- (engine/battle/core.asm:5035); only .cant_escape_2, the failed roll at the
  -- bottom, writes BATTLEPLAYERACTION_USEITEM and buys the enemy a move.
  self.runRefused = nil
  -- The battle-type ladder runs FIRST: BATTLETYPE_TRAP and
  -- BATTLETYPE_FORCESHINY jump straight to .cant_escape, ahead of the
  -- trainer check and any speed math.  Without this, running from the Red
  -- Gyarados returned a WIN to the script and forfeited the one-shot shiny.
  if self.battleType == Battle.BATTLETYPE_FORCESHINY
      or self.battleType == Battle.BATTLETYPE_TRAP then
    self:emit({ kind = "message", text = "Can't escape!" })
    self.runRefused = true
    return false
  end
  if self.trainer then
    self:emit({ kind = "message", text = "No! There's no running from a "
      .. "trainer battle!" })
    self.runRefused = true
    return false
  end
  -- SUBSTATUS_CANT_RUN held by the ENEMY (its Mean Look pinned the player)
  -- and a live wrap count on the player both refuse before the speed math
  -- and before the attempt is even counted.
  if self:volatile(self.enemy).trapsTarget
      or (self:volatile(self.player).wrapCount or 0) > 0 then
    self:emit({ kind = "message", text = "Can't escape!" })
    self.runRefused = true
    return false
  end
  self.runAttempts = (self.runAttempts or 0) + 1
  -- engine/battle/core.asm:2614
  if self:runRoll(pSpd or self:effectiveSpeed(self.player),
      self:effectiveSpeed(self.enemy)) then
    self:emit({ kind = "run", text = "Got away safely!" })
    self:endBattle("run")
    return true
  end
  self:emit({ kind = "message", text = "Can't escape!" })
  return false
end

-- The escape roll itself, hooked as battle.run -- the same hook
-- BattleState:runRoll calls on Gen 1, with the same ctx keys (pSpd, eSpd,
-- attempts, rng) and the same boolean return.  The attempt has already been
-- counted by the caller, exactly as it is on Gen 1, so a mod that refuses the
-- escape still leaves the count raised.
function Battle:runRoll(pSpd, eSpd)
  if Runtime.wantsHook("battle.run") then
    return Runtime.call("battle.run", function(c)
      return c.battle:runRollVanilla(c.pSpd, c.eSpd)
    end, { battle = self, pSpd = pSpd, eSpd = eSpd,
           attempts = self.runAttempts, rng = self:roller(),
           random = self.random })
  end
  return self:runRollVanilla(pSpd, eSpd)
end

function Battle:runRollVanilla(pSpd, eSpd)
  if pSpd >= eSpd then return true end
  -- (playerSpeed * 32 / (enemySpeed / 4)) + 30 * attempts, out of 256.
  local odds = math.floor(pSpd * 32
    / math.max(1, math.floor(eSpd / 4))) + 30 * (self.runAttempts or 1)
  return odds >= 256 or rand(self.random, 256) < odds
end

-- TryEnemyFlee (engine/battle/core.asm), called at the head of the enemy's
-- half of the turn in BOTH orders (Battle_EnemyFirst runs it first thing,
-- Battle_PlayerFirst runs it once the player's move has resolved).
--
-- The gates, in the asm's order:
--   * trainer battles never flee (`ld a, [wBattleMode] / dec a / jr nz`)
--   * SUBSTATUS_CANT_RUN on the PLAYER (Mean Look, Spider Web) pins it
--   * a live wrap count pins it
--   * frozen or asleep pins it
--   * AlwaysFleeMons -> gone, no roll at all.  Raikou, Entei and Suicune are
--     that whole list, which is why a beast gets exactly one turn of yours
--   * otherwise one random byte: under 50 percent + 1 lets OftenFleeMons go,
--     and under 10 percent + 1 lets SometimesFleeMons go.  ONE byte for both
--     gates, so the two lists are not independent rolls
--
-- `percent` is `* $ff / 100` (macros/data.asm), so those two thresholds are
-- 128 and 26 rather than 128 and 26-ish: 50*255/100 = 127, +1; 10*255/100 =
-- 25, +1.
--
Battle.OFTEN_FLEE_ROLL = 128    -- 50 percent + 1
Battle.SOMETIMES_FLEE_ROLL = 26 -- 10 percent + 1

function Battle:tryEnemyFlee()
  if not self.wild then return false end
  -- SUBSTATUS_CANT_RUN on the player's side (its Mean Look holds the wild
  -- mon) and a live wrap count on the enemy pin it BEFORE the status check
  -- -- the pin that makes a roamer catchable at full HP.
  if self:volatile(self.player).trapsTarget then return false end
  if (self:volatile(self.enemy).wrapCount or 0) > 0 then return false end
  local status = self.enemy.status
  if status == "freeze" or status == "sleep" then return false end
  local species = self.enemy.species
  if Roamers.ALWAYS_FLEE[species] then return self:enemyFled() end
  local roll = rand(self.random, 256)
  if roll >= Battle.OFTEN_FLEE_ROLL then return false end
  if Roamers.OFTEN_FLEE[species] then return self:enemyFled() end
  if roll >= Battle.SOMETIMES_FLEE_ROLL then return false end
  if Roamers.SOMETIMES_FLEE[species] then return self:enemyFled() end
  return false
end

-- WildFled_EnemyFled_LinkBattleCanceled.  The result it writes is DRAW, the
-- same value the player's own successful run writes, which is what makes
-- BattleEnd_HandleRoamMons bank the beast's HP instead of clearing its slot.
-- The port's outcome name is "fled" so a caller can tell the two apart, and
-- Evolution.runsAfterBattle already treats anything that is not a loss or a
-- draw-by-forfeit as evolvable.
function Battle:enemyFled()
  self:endBattle("fled")
  self:emit({ kind = "run", side = "enemy",
    text = "Wild " .. self:monName(self.enemy) .. " fled!" })
  return true
end

-- The AI's move.  A trainer class's TRNATTR_AI_MOVE_WEIGHTS decides which
-- scoring layers run (src/battle/gen2/Ai.lua); a wild mon -- and a class with
-- no flags -- picks at random from what it knows, which is what AIChooseMove
-- does when wEnemyTrainerAIFlags is zero.
-- engine/battle/ai/items.asm AI_SwitchOrTryItem.  Wild mons never do either;
-- a trainer's class decides how eager it is.  Returns true when the turn was
-- spent on the switch or the item.
function Battle:enemyTrySwitchOrItem()
  if self.wild or not self.trainer then return false end
  local attributes = self.trainer.attributes
  if type(attributes) ~= "table" then return false end

  -- The AI cannot rotate out of a trap either: a live wrap count on its
  -- active mon or the player's CANT_RUN pin close the switch branch the way
  -- they close TryPlayerSwitch, leaving only the item check.
  local trapped = (self:volatile(self.enemy).wrapCount or 0) > 0
    or self:volatile(self.player).trapsTarget == true

  -- CheckAbleToSwitch, then the class's own probability.
  local bench = {}
  local playerTypes = (self:speciesDef(self.player) or {}).types
    or self.player.types or {}
  for index, mon in ipairs(self.enemyParty) do
    if index ~= self.enemyIndex and (mon.hp or 0) > 0 then
      local def = self:speciesDef(mon)
      local types = (def and def.types) or mon.types or {}
      -- "Resists" is the player's own type against the bench mon, which is
      -- what FindEnemyMonsThatResistPlayer measures.
      local incoming = Damage.typeMultiplier(playerTypes[1], types,
        self.data.type_chart and self.data.type_chart.matchups)
      local super_ = false
      for _, move in ipairs(mon.moves or {}) do
        local moveDef = self:moveDef(move.id)
        if moveDef and (moveDef.power or 0) > 0 then
          local mult = Damage.typeMultiplier(moveDef.type, playerTypes,
            self.data.type_chart and self.data.type_chart.matchups)
          if (mult or 10) > 10 then super_ = true end
        end
      end
      bench[#bench + 1] = { index = index, mon = mon, healthy = true,
        resists = (incoming or 10) < 10, superEffective = super_ }
    end
  end

  -- CheckPlayerMoveTypeMatchups: below BASE_AI_SWITCH_SCORE means the player's
  -- moves are beating what is out.  Battle:playerMatchupScore owns that loop so
  -- this layer and AI_Smart's four readers of it cannot disagree.
  local score, target = Ai.switchScore({
    bench = bench,
    perishCount = self:volatile(self.enemy).perish,
    matchupScore = self:playerMatchupScore(),
  })
  if not trapped and target
      and Ai.shouldSwitch(attributes, score, self.random) then
    self:clearVolatile(self.enemy)
    -- AI_Switch prints EnemyWithdrewText BEFORE it farcalls EnemySwitch
    -- (engine/battle/ai/items.asm:685), so a rotation announces the mon
    -- coming OFF the field as well as the one coming on; without it a
    -- trainer swapping between two of the same species looked like nothing
    -- had happened.  The line is skipped only when Pursuit hit the mon on
    -- its way out, which this port has no analogue for yet.
    local outgoing = self.enemy
    self:emit({ kind = "message",
      text = (self.trainer.name or "TRAINER") .. " withdrew "
        .. self:monName(outgoing) .. "!" })
    self.enemyIndex = target
    self.enemy = self.enemyParty[target]
    -- ResetEnemyBattleVars (engine/battle/core.asm:3016) zeroes wCurEnemyMove
    -- and wLastEnemyMove and NewEnemyMonStatus wipes the substatus bytes, so
    -- the mon coming IN starts from an empty area -- the same pair of clears
    -- Battle:switch makes for the player's side.
    self:clearVolatile(self.enemy)
    self.stages.enemy = Battle.newStages()
    self:emit({ kind = "send", side = "enemy", mon = self.enemy,
      text = (self.trainer.name or "TRAINER") .. " sent out "
        .. self:monName(self.enemy) .. "!" })
    Runtime.emit("battle.battler_switched", {
      battle = self, side = self:sideRecord(self.enemy), battler = self.enemy,
      previous = outgoing,
    })
    self:breakTrapsOnSend(self.enemy)
    self:spikesDamage(self.enemy)
    return true
  end

  -- AI_TryItem: only the trainer's highest-level mon is worth an item.
  local highest = 0
  for _, mon in ipairs(self.enemyParty) do
    highest = math.max(highest, mon.level or 0)
  end
  local item = Ai.chooseItem({
    items = self.trainer.items,
    isHighestLevel = (self.enemy.level or 0) >= highest,
    hp = self.enemy.hp,
    maxHp = self.enemy.maxHp or (self.enemy.stats or {}).hp,
    status = self.enemy.status,
    enemyTurns = self:volatile(self.enemy).turnsTaken or 0,
  })
  if not item then return false end
  -- Consume it, so a trainer with one Potion cannot drink it every turn.
  for index, id in ipairs(self.trainer.items or {}) do
    if id == item then table.remove(self.trainer.items, index) break end
  end
  local heal = Ai.HEAL_ITEMS[item]
  if heal then
    self:heal(self.enemy, heal == math.huge
      and (self.enemy.maxHp or (self.enemy.stats or {}).hp or 1) or heal)
    if item == "FULL_RESTORE" then
      self.enemy.status = nil
      self:volatile(self.enemy).confuseCount = nil
    end
  elseif item == "FULL_HEAL" then
    self.enemy.status = nil
    self:volatile(self.enemy).confuseCount = nil
  end
  self:emit({ kind = "message", text = (self.trainer.name or "TRAINER")
    .. " used " .. item .. "!" })
  return true
end

-- battle.enemy_action, the same hook BattleState:enemyAction calls on Gen 1:
-- the whole choke point is wrapped, so a mod can rewrite any trainer's choice
-- without registering a brain.  Gen 1's chain returns an ACTION table and
-- Gen 2's engine speaks in bare move ids, so a table with an `id` (or a
-- `move`) is unwrapped rather than refused -- which is what lets one mod
-- source answer this hook on both generations.
function Battle:enemyMove()
  if Runtime.wantsHook("battle.enemy_action") then
    local chosen = Runtime.call("battle.enemy_action", function(battle)
      return Battle.vanillaEnemyMove(battle)
    end, self)
    if type(chosen) == "table" then return chosen.id or chosen.move end
    return chosen
  end
  -- Called through the module rather than the metatable: the charge-lock test
  -- drives this against a bare stub table, which is also how the lock is
  -- proved to read nothing but the volatile.
  return Battle.vanillaEnemyMove(self)
end

function Battle:vanillaEnemyMove()
  -- A mon halfway through a two-turn move does not get to choose again.
  --
  -- On the cart the charge sets SUBSTATUS_CHARGED and `CheckEnemyTurn` reuses
  -- wEnemySelectedMove; the AI is never consulted for the second turn.  Without
  -- that lock the AI picks freely, which skips the stored attack AND -- because
  -- `vanished` is only cleared by the branch in useMove that recognises the
  -- second half -- leaves the mon semi-invulnerable **for the rest of the
  -- battle**.
  --
  -- Found by the Gold route bot: ELITE FOUR BRUNO's HITMONLEE opens with DIG,
  -- then attacks with HI JUMP KICK from underground forever.  Every incoming
  -- move answers "TYPHLOSION's attack missed!", so Hitmonlee cannot be damaged
  -- by anything, at any level.  Fifteen straight attempts at the Elite Four
  -- died there, and no amount of grinding could ever have got past it.
  local charged = self:volatile(self.enemy).chargeMove
  if charged then return charged end

  -- Encore and Disable narrow the pool before the AI ever scores it.
  local moves = self:usableMoves(self.enemy)
  if #moves == 0 then
    -- `.not_linked`'s encore arm runs ahead of the disable scan
    -- (engine/battle/core.asm:5524-5529).
    local forced = self:forcedMove(self.enemy)
    if forced then return forced end
    -- `.disabled` walks off the end into `.struggle` (:5555-5560).
    return nil
  end
  local flags = Ai.flagsOf(self.trainer and self.trainer.attributes)
  if flags == 0 then
    return moves[rand(self.random, #moves) + 1].id
  end
  local chosen = Ai.choose({
    moves = moves,
    moveDef = function(id) return self:moveDef(id) end,
    attacker = {
      level = self.enemy.level,
      stats = self.enemy.stats,
      types = (self:speciesDef(self.enemy) or {}).types or self.enemy.types,
    },
    defender = {
      hp = self.player.hp,
      stats = self.player.stats,
      status = self.player.status,
      -- AI_Basic reads SUBSTATUS_CONFUSED for the confusion moves, not the
      -- status byte.
      confused = self:volatile(self.player).confuseCount ~= nil,
      types = (self:speciesDef(self.player) or {}).types or self.player.types,
    },
    typeChart = self.data.type_chart,
    -- The dataset itself, which is where Ai.layersFor reads the merged
    -- `ai_classes` records from (data.gen2AiClasses).  Without it the module's
    -- own ten layers answer, which is the same behaviour a boot with no loader
    -- has always had.
    data = self.data,
    -- Everything the SETUP / OPPORTUNIST / CAUTIOUS / SMART layers read.
    enemyHp = self.enemy.hp,
    enemyMaxHp = self.enemy.maxHp or (self.enemy.stats or {}).hp,
    enemyTurns = self:volatile(self.enemy).turnsTaken or 0,
    playerTurns = self:volatile(self.player).turnsTaken or 0,
    smart = self:smartAiState(),
    -- wLastPlayerCounterMove's base power, which AI_Smart_Encore and
    -- AI_Smart_MirrorCoat both take as their fifth argument.
    playerLastPower = (function()
      local last = self:volatile(self.player).lastMove
      local def = last and self:moveDef(last)
      return def and def.power or nil
    end)(),
    attackerStages = self.stages.enemy,
    defenderStages = self.stages.player,
    flags = flags,
    random = function(n) return rand(self.random, n) end,
  })
  return chosen or moves[1].id
end

-- Run one turn.  `action` is:
--   { kind = "move", move = <id> }
--   { kind = "switch", index = n }
--   { kind = "run" }
--   { kind = "item", item = <id>, target = n }  (handled by the caller, which
--       applies the effect and then calls this with kind = "item" so the enemy
--       still gets its turn)
local function runTurn(self, action)
  if self.over then return self:takeEvents() end
  self.turn = self.turn + 1
  action = action or { kind = "move" }
  -- HandleBerserkGene sits at the top of BattleTurn's loop
  -- (engine/battle/core.asm:160), player first then enemy, so a holder
  -- fires on its first turn out whether it started the battle or switched
  -- in.  Consuming the item is what keeps it one-shot.
  self:checkBerserkGene(self.player)
  self:checkBerserkGene(self.enemy)
  -- Counter and Mirror Coat answer damage taken *this* turn, so the tally
  -- starts empty (BattleCommand_Counter reads wCurDamage, which the turn
  -- clears).
  self:volatile(self.player).tookThisTurn = nil
  self:volatile(self.enemy).tookThisTurn = nil
  -- Set by resolveFaints; per-round, so it can never leak into the next one.
  self.faintInterrupt = nil

  if action.kind == "run" then
    if self:tryRun() then return self:takeEvents() end
    -- Only the failed ROLL costs the turn.  .cant_escape_2 writes
    -- BATTLEPLAYERACTION_USEITEM before printing its line, so BattleMenu_Run's
    -- `ld a, [wBattlePlayerAction] / and a / ret nz` lets the round proceed;
    -- .cant_escape and .cant_run_from_trainer leave the action at
    -- BATTLEPLAYERACTION_USEMOVE and fall into `jp BattleMenu`
    -- (engine/battle/core.asm:5035-5038), which reopens the 2x2 menu with the
    -- turn unspent -- so a refused RUN never bought the enemy a free attack.
    if self.runRefused then return self:takeEvents() end
    action = { kind = "skip" }
  end

  if action.kind == "switch" then
    self:switch(action.index)
    action = { kind = "skip" }
  end

  -- XItemEffect's tail: the four X items award HAPPINESS_USEDXITEM to
  -- wCurBattleMon, i.e. whoever is out, not whoever the PACK was pointed at.
  -- The caller applies the item's own effect and then hands the turn here, so
  -- this is where the award lands.
  if action.kind == "item" and Battle.X_ITEMS[action.item] then
    Happiness.change(self.player, "USEDXITEM")
  end

  -- AI_SwitchOrTryItem runs BEFORE the move is chosen: a trainer that decides
  -- to rotate or drink a potion spends its whole turn on it.
  local enemyActed = self:enemyTrySwitchOrItem()
  local enemyMoveId = (not enemyActed) and self:enemyMove() or nil

  -- battle.turn_started, where BattleState:resolveTurn raises it on Gen 1:
  -- once both sides have chosen and before either acts.  Gen 1's action tables
  -- key their move as `id` and Gen 2's as `move`, so the payload's copies carry
  -- both spellings rather than making a mod know which engine it is in.
  if Runtime.wants("battle.turn_started") then
    Runtime.emit("battle.turn_started", {
      battle = self, turn = self.turn,
      playerAction = { kind = action.kind, id = action.move,
                       move = action.move, index = action.index,
                       item = action.item },
      enemyAction = enemyMoveId
        and { kind = "move", id = enemyMoveId, move = enemyMoveId } or nil,
    })
  end
  self.turnOpen = true

  -- A switch or item always resolves before the enemy's move; otherwise Speed
  -- decides.
  local playerFirst
  if action.kind == "skip" or action.kind == "item" then
    playerFirst = true
  elseif Runtime.wantsHook("battle.turn_order") then
    -- battle.turn_order, the same hook BattleState:resolveTurn calls on Gen 1
    -- and with the same five arguments: both battlers, both move records, and
    -- a ctx carrying the rng.  Gen 2's ordering reads move IDS rather than
    -- records (priority comes off the id), so the ids are in the ctx as
    -- playerMove / enemyMove and that is what vanilla resolves.
    playerFirst = Runtime.call("battle.turn_order", function(_, _, _, _, c)
      return c.battle:orderOf(c.playerMove, c.enemyMove) == "player"
    end, self.player, action.move and self:moveDef(action.move) or nil,
    self.enemy, enemyMoveId and self:moveDef(enemyMoveId) or nil,
    { battle = self, rng = self:roller(), random = self.random,
      playerMove = action.move, enemyMove = enemyMoveId }) and true or false
  else
    playerFirst = self:orderOf(action.move, enemyMoveId) == "player"
  end
  -- wEnemyGoesFirst, which BattleCommand_ForceSwitch's two trainer arms
  -- read: Roar and Whirlwind only work for a user moving SECOND.
  self.firstMover = playerFirst and "player" or "enemy"

  local function playerAttack()
    if action.kind ~= "move" then return end
    if not self:canAct(self.player) then return end
    local move = action.move
    -- An encored mon has no choice, whatever the menu said.
    local forced = self:forcedMove(self.player)
    if forced then move = forced end
    -- .CheckPlayerHasUsableMoves: a mon with nothing left to spend attacks
    -- with STRUGGLE rather than losing the turn.  The menu can still hand us a
    -- dry move (nothing stops the player picking one), so the substitution is
    -- made here, where the cart makes it, rather than in the menu.
    --
    -- The second half of a two-turn move is exempt: it spends no PP and makes
    -- no new choice, so a mon that went dry while charging still lands the
    -- attack it stored.
    --
    -- The lock itself, same as the enemy's in Battle:enemyMove: whatever the
    -- menu handed us, a mon with a stored charge move uses THAT.  Otherwise
    -- the stored attack is skipped and `vanished` is never cleared, and the
    -- player's own mon spends the rest of the battle underground.
    local stored = self:volatile(self.player).chargeMove
    if stored then move = stored end
    -- CheckPlayerLockedIn quits before .CheckPlayerHasUsableMoves and before
    -- checkobedience, so a locked Rollout or Thrash is exempt from the
    -- Struggle substitution and the obedience roll the same way the second
    -- half of a charge move is.
    local charging = self:volatile(self.player).chargeMove == move
      or self:lockedInMove(self.player) == move
    if not charging and not self:hasUsableMoves(self.player) then
      self:emit({ kind = "message",
        text = self:monName(self.player) .. " has no moves left!" })
      move = Battle.STRUGGLE
    end
    -- CheckPlayerTurn's disabled arm spends the turn, whatever was selected
    -- (engine/battle/effect_commands.asm:314-326).
    if self:moveDisabled(self.player, move) then
      -- MoveDisabled fails the stored charge (:599-603) and CantMove brings a
      -- vanished FLY/DIG user back (:364-368).
      local state = self:volatile(self.player)
      state.chargeMove, state.vanished = nil, nil
      self:emit({ kind = "message",
        text = self:monName(self.player) .. "'s " .. move .. " is DISABLED!" })
      return
    end
    -- BattleCommand_CheckObedience runs at the head of the move's effect
    -- list, after the status gates and before PP is spent; the second half
    -- of a charge move is exempt (CheckUserIsCharging).
    if not charging and self:checkObedience(move) then return end
    self:useMove(self.player, self.enemy, move)
  end
  local function enemyAttack()
    if enemyActed then return end
    if (self.enemy.hp or 0) <= 0 then return end
    -- TryEnemyFlee sits here in both of the cart's turn orders, ahead of the
    -- enemy's move and behind the faint checks.
    if self:tryEnemyFlee() then return end
    if not enemyMoveId then
      -- `.struggle` (engine/battle/core.asm:5630-5632) sets STRUGGLE and
      -- finishes silently: BattleText_MonHasNoMovesLeft is text_ram
      -- wBattleMonNickname (data/text/battle.asm:325-329) and only
      -- .force_struggle (core.asm:5311-5317) ever prints it.  Returning here
      -- instead -- which is what this did -- left a dry enemy unable to act at
      -- all, so a battle where both sides had run out could never end and,
      -- against a trainer, could not be escaped either.
      enemyMoveId = Battle.STRUGGLE
    end
    if not self:canAct(self.enemy) then return end
    -- CheckEnemyTurn's disabled arm (engine/battle/effect_commands.asm:562-574):
    -- the AI chose before the player's Disable landed, so the turn is spent here.
    if self:moveDisabled(self.enemy, enemyMoveId) then
      local state = self:volatile(self.enemy)
      state.chargeMove, state.vanished = nil, nil
      self:emit({ kind = "message",
        text = self:monName(self.enemy) .. "'s " .. enemyMoveId .. " is DISABLED!" })
      return
    end
    self:useMove(self.enemy, self.player, enemyMoveId)
  end

  if playerFirst then
    playerAttack()
    -- A wild Roar or Whirlwind ends the battle from THIS half of the turn the
    -- same way a flee ends it from the other: `.wild_force_flee` writes DRAW
    -- into wBattleResult and the turn loop's `.quit` takes the round with it,
    -- so the mon that was blown away never answers.
    if self.over then return self:takeEvents() end
    if self:resolveFaints() then return self:takeEvents() end
    -- A faint ends the attack phase.  Battle_PlayerFirst reaches both faint
    -- handlers with `jp`, not `call` (engine/battle/core.asm:871-874), so the
    -- enemy's half of the round is never run: the replacement the trainer
    -- just sent out does not attack on the turn it walked in, and the move
    -- picked for the mon it replaced is dropped rather than fired by whoever
    -- happens to be standing there now.  The end-of-turn block below still
    -- runs -- HandleEnemyMonFaint returns into BattleTurn's `.proceed`, which
    -- calls HandleBetweenTurnEffects (core.asm:196).
    if self.faintInterrupt then
      self.faintInterrupt = nil
    elseif (self.player.hp or 0) > 0 then
      enemyAttack()
    end
  else
    enemyAttack()
    -- A flee ends the battle where it stands: the cart jumps straight to
    -- WildFled_EnemyFled_LinkBattleCanceled and never reaches the player's
    -- half of the turn or the residual damage.
    if self.over then return self:takeEvents() end
    if self:resolveFaints() then return self:takeEvents() end
    -- Same `jp` (core.asm:834-837): a mon that fainted to the enemy's move
    -- takes the rest of the attack phase with it.
    if self.faintInterrupt then
      self.faintInterrupt = nil
    elseif (self.player.hp or 0) > 0 then
      playerAttack()
    end
  end
  if self.over then return self:takeEvents() end
  if self:resolveFaints() then return self:takeEvents() end
  self.faintInterrupt = nil

  -- A successful Roar or Whirlwind ends the ROUND: the turn loop's `.quit`
  -- on wForcedSwitch skips HandleBetweenTurnEffects, so nothing ticks on
  -- the turn a mon was dragged out.
  if self.forcedSwitch then
    self.forcedSwitch = nil
    return self:takeEvents()
  end

  -- End of turn, in the cart's own order (HandleWeather runs before the
  -- residual damage, and the counters that end a mon come last):
  --   weather, then status chip and the Leech Seed / Curse residuals, then
  --   the wrap ticks, then held items, then Future Sight and Perish Song,
  --   then the screens and the per-turn counters.
  self:tickWeather()
  self:tickStatus(self.player)
  self:tickSeedAndCurse(self.player)
  self:tickStatus(self.enemy)
  self:tickSeedAndCurse(self.enemy)
  self:tickWrap(self.player)
  self:tickWrap(self.enemy)
  self:tickHeldItem(self.player)
  self:tickHeldItem(self.enemy)
  self:tickFutureSight(self.player)
  self:tickFutureSight(self.enemy)
  self:tickPerish(self.player)
  self:tickPerish(self.enemy)
  self:tickScreens()
  self:tickCounters(self.player)
  self:tickCounters(self.enemy)
  self:resolveFaints()
  return self:takeEvents()
end

-- battle.turn_ended closes the round battle.turn_started opened, whichever of
-- runTurn's exits was taken -- a faint, a flee, a forced switch or the ordinary
-- residual sweep.  A round that never happened (a refused RUN, a battle that
-- was already over) opened nothing and so closes nothing, which is what keeps
-- the two events paired the way Gen 1's endOfTurn keeps them.
function Battle:takeTurn(action)
  local events = runTurn(self, action)
  if self.turnOpen then
    self.turnOpen = nil
    if Runtime.wants("battle.turn_ended") then
      Runtime.emit("battle.turn_ended", { battle = self, turn = self.turn })
    end
  end
  return events
end

-- HandleWeather: the count ticks down every turn and the weather ends the turn
-- it reaches zero.  Sandstorm chips an eighth off everything that is not Rock,
-- Ground or Steel.
function Battle:tickWeather()
  if not self.weather then return end
  self.weatherTurns = self.weatherTurns - 1
  if self.weatherTurns <= 0 then
    self:emit({ kind = "weather", weather = nil,
      text = Effects.WEATHER_END_TEXT[self.weather] })
    self.weather = nil
    return
  end
  self:emit({ kind = "message",
    text = Effects.WEATHER_TURN_TEXT[self.weather] })
  if self.weather ~= "sandstorm" then return end
  for _, mon in ipairs({ self.player, self.enemy }) do
    if (mon.hp or 0) > 0 and not self:volatile(mon).vanished then
      local def = self:speciesDef(mon)
      local types = (def and def.types) or mon.types
      if Effects.sandstormHits(types) then
        local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 8
        local damage = Effects.sandstormDamage(maxHp)
        mon.hp = math.max(0, mon.hp - damage)
        self:emit({ kind = "message",
          text = self:monName(mon) .. " is buffeted by the sandstorm!" })
        -- .SandstormDamage plays ANIM_IN_SANDSTORM between two SwitchTurnCore
        -- calls, so it runs from the OTHER side (core.asm:1688-1693).
        self:emit({ kind = "damage", side = self:sideOf(mon),
          amount = damage, hp = mon.hp, anim = "ANIM_IN_SANDSTORM" })
      end
    end
  end
end

-- BattleCommand_CheckFutureSight: the stored damage lands when the counter
-- reaches one, on whoever is standing on the target's side by then.
function Battle:tickFutureSight(mon)
  local state = self:volatile(mon)
  if not state.futureSight then return end
  state.futureSight = state.futureSight - 1
  if state.futureSight > 0 then return end
  local target = state.futureSightSide == "player" and self.player or self.enemy
  local damage = state.futureSightDamage or 1
  state.futureSight, state.futureSightDamage, state.futureSightSide =
    nil, nil, nil
  if (target.hp or 0) <= 0 then return end
  self:emit({ kind = "message", text = self:monName(target)
    .. " took the FUTURE SIGHT attack!" })
  self:dealDamage(mon, target, damage, {})
end

-- The perish count ticks at the end of every turn and the mon faints on zero.
function Battle:tickPerish(mon)
  local state = self:volatile(mon)
  if not state.perish or (mon.hp or 0) <= 0 then return end
  state.perish = state.perish - 1
  if state.perish > 0 then
    self:emit({ kind = "message", text = self:monName(mon)
      .. "'s PERISH count is " .. state.perish .. "!" })
    return
  end
  state.perish = nil
  mon.hp = 0
  -- HandlePerishSong just zeroes both HP bytes (core.asm:1119-1135).
  self:emit({ kind = "damage", side = self:sideOf(mon), amount = 0, hp = 0,
    anim = false })
end

-- ResidualDamage's Leech Seed and Curse arms (engine/battle/core.asm:1010
-- and 1054): an eighth of the seeded mon's max HP crosses to whoever stands
-- on the OTHER side by now, then a quarter for the curse.  Both run only
-- while the sufferer still stands, and both survive the trapper leaving --
-- the flags sit on the suffering mon itself.
function Battle:tickSeedAndCurse(mon)
  local state = self:volatile(mon)
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 8
  if state.leechSeed and (mon.hp or 0) > 0 then
    local damage = math.min(math.max(1, math.floor(maxHp / 8)), mon.hp)
    mon.hp = mon.hp - damage
    self:emit({ kind = "message",
      text = "LEECH SEED saps " .. self:monName(mon) .. "!" })
    -- ANIM_SAP plays between two SwitchTurnCore calls, from the seeder's side
    -- (core.asm:1013-1021).
    self:emit({ kind = "damage", side = self:sideOf(mon), amount = damage,
      hp = mon.hp, anim = "ANIM_SAP" })
    local other = mon == self.player and self.enemy or self.player
    if (other.hp or 0) > 0 then self:heal(other, damage) end
  end
  if state.cursed and (mon.hp or 0) > 0 then
    local damage = math.max(1, math.floor(maxHp / 4))
    mon.hp = math.max(0, mon.hp - damage)
    self:emit({ kind = "message",
      text = self:monName(mon) .. "'s hurt by the CURSE!" })
    -- The curse arm borrows ANIM_IN_NIGHTMARE, on the sufferer's own turn
    -- (core.asm:1057-1060).
    self:emit({ kind = "damage", side = self:sideOf(mon), amount = damage,
      hp = mon.hp, anim = "ANIM_IN_NIGHTMARE", animSide = self:sideOf(mon) })
  end
end

-- HandleWrap (engine/battle/core.asm:1153): the count on the trapped mon
-- decrements FIRST -- release at zero, else a sixteenth of max HP.  A
-- Substitute suspends the whole tick, count included.
function Battle:tickWrap(mon)
  local state = self:volatile(mon)
  if not state.wrapCount or (mon.hp or 0) <= 0 then return end
  if (state.substitute or 0) > 0 then return end
  state.wrapCount = state.wrapCount - 1
  local moveName = state.wrapMove or "the trap"
  if state.wrapCount <= 0 then
    state.wrapCount, state.wrapMove, state.wrapMoveId = nil, nil, nil
    self:emit({ kind = "message",
      text = self:monName(mon) .. " was released from " .. moveName .. "!" })
    return
  end
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 16
  local damage = math.max(1, math.floor(maxHp / 16))
  mon.hp = math.max(0, mon.hp - damage)
  self:emit({ kind = "message",
    text = self:monName(mon) .. "'s hurt by " .. moveName .. "!" })
  -- The trapping move's own anim, played from the trapper's side between two
  -- SwitchTurnCore calls (core.asm:1198-1203).
  self:emit({ kind = "damage", side = self:sideOf(mon), amount = damage,
    hp = mon.hp, anim = false, animMove = state.wrapMoveId })
end

-- HandleScreens (engine/battle/core.asm:1564): each side's five-turn counts
-- tick down and the screen falls the turn its count reaches zero.
Battle.SCREEN_SIDE_LABEL = { player = "Your", enemy = "Enemy" }
Battle.SCREEN_FALL_TEXT = {
  lightScreen = " POKéMON's LIGHT SCREEN fell!",
  reflect = " POKéMON's REFLECT faded!",
}

function Battle:tickScreens()
  for _, side in ipairs({ "player", "enemy" }) do
    local screens = self.screens[side]
    for _, field in ipairs({ "lightScreen", "reflect", "safeguard" }) do
      if (screens[field] or 0) > 0 then
        screens[field] = screens[field] - 1
        if screens[field] <= 0 then
          screens[field] = nil
          if field == "safeguard" then
            -- engine/battle/core.asm:1527
            self:emit({ kind = "message",
              text = self:monName(self[side]) .. "'s SAFEGUARD faded!" })
          else
            self:emit({ kind = "message",
              text = Battle.SCREEN_SIDE_LABEL[side]
                .. Battle.SCREEN_FALL_TEXT[field] })
          end
        end
      end
    end
  end
end

-- Encore, Disable and the two one-turn braces.  Protect and Endure last only
-- the turn they are used, which is why they are cleared here rather than by
-- whatever they blocked.
function Battle:tickCounters(mon)
  local state = self:volatile(mon)
  state.protect, state.endure = nil, nil
  -- A flinch lasts only the turn it was inflicted; a leftover one (the
  -- target moved first, or fainted) must not eat next turn.
  state.flinched = nil
  if state.encoreTurns then
    state.encoreTurns = state.encoreTurns - 1
    if state.encoreTurns <= 0 then
      state.encore, state.encoreTurns = nil, nil
      self:emit({ kind = "message",
        text = self:monName(mon) .. "'s ENCORE ended!" })
    end
  end
  if state.disabledTurns then
    state.disabledTurns = state.disabledTurns - 1
    if state.disabledTurns <= 0 then
      state.disabled, state.disabledTurns = nil, nil
      self:emit({ kind = "message",
        text = self:monName(mon) .. "'s move is no longer disabled!" })
    end
  end
end

-- Held items with an end-of-turn effect.
--
--   HELD_LEFTOVERS  heals maxHP / 16 every turn (HandleLeftovers)
--   HELD_BERRY      heals its parameter once the holder drops below half
--                   (HandleHealingItems), and is consumed
--   HELD_HEAL_*     cures the status it names, and is consumed
--
-- The rest of the held effects act inside a hit rather than at the end of a
-- turn, so they are not this function's business.
-- Confusion is a volatile, not a status byte, so HELD_HEAL_CONFUSION is not
-- in this table: its cure (and HELD_HEAL_STATUS's catch-all) reads the
-- confuseCount volatile in tickHeldItem's own arm below.
Battle.HELD_STATUS_CURES = {
  HELD_HEAL_POISON = "poison",
  HELD_HEAL_SLEEP = "sleep",
  HELD_HEAL_BURN = "burn",
  HELD_HEAL_FREEZE = "freeze",
  HELD_HEAL_PARALYZE = "paralyze",
}

function Battle:itemDef(itemId)
  local items = self.data.items
  return itemId and items and items[itemId] or nil
end

function Battle:tickHeldItem(mon)
  if (mon.hp or 0) <= 0 then return end
  local def = self:itemDef(mon.item)
  if not def then return end
  -- Through Battle:heldEffect rather than off the record, so the end-of-turn
  -- arm is one more held_item.trigger site and not a hole in it.  `def` stays
  -- the item's own record: the messages below name the ITEM the mon is
  -- holding, which a substituted effect does not change.
  local effect, parameter = self:heldEffect(mon, "residual")
  if not effect then return end
  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 1
  local name = self:monName(mon)

  if effect == "HELD_LEFTOVERS" then
    if (mon.hp or 0) >= maxHp then return end
    local healed = self:heal(mon, math.max(1, math.floor(maxHp / 16)))
    if healed > 0 then
      self:emit({ kind = "message",
        text = name .. "'s " .. (def.name or "item") .. " restored health!" })
    end
    return
  end

  if effect == "HELD_BERRY" and (mon.hp or 0) * 2 <= maxHp then
    -- pokegold engine/battle/core.asm:4074 ItemRecoveryAnim
    self:heal(mon, parameter > 0 and parameter or 10, { anim = "RECOVER" })
    mon.item = nil
    self:emit({ kind = "message",
      text = name .. " ate the " .. (def.name or "BERRY") .. "!" })
    return
  end

  local cure = Battle.HELD_STATUS_CURES[effect]
  if effect == "HELD_HEAL_STATUS" then cure = mon.status end
  if cure and mon.status == cure then
    mon.status = nil
    mon.statusTurns = nil
    mon.toxicCounter = nil
    mon.item = nil
    self:emit({ kind = "status", side = self:sideOf(mon), status = nil,
      text = name .. "'s " .. (def.name or "item") .. " cured its status!" })
  end

  -- UseConfusionHealingItem: HELD_HEAL_CONFUSION (a Bitter Berry) and the
  -- catch-all HELD_HEAL_STATUS also clear the confusion volatile, and are
  -- consumed doing it.
  if (effect == "HELD_HEAL_CONFUSION" or effect == "HELD_HEAL_STATUS")
      and self:volatile(mon).confuseCount then
    self:volatile(mon).confuseCount = nil
    mon.item = nil
    self:emit({ kind = "message",
      text = name .. "'s " .. (def.name or "item")
        .. " cured its confusion!" })
  end
end

Battle.Damage = Damage
Battle.Mon = Mon

return Battle
