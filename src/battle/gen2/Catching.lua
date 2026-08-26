-- Gen 2 catch rate (engine/items/item_effects.asm PokeBallEffect).
--
-- The rate itself, transcribed from the ASM:
--
--   rate = ((3 * maxHP - 2 * curHP) * ballAdjustedCatchRate) / (3 * maxHP)
--   rate = max(1, rate) + statusBonus
--   rate = min(255, rate)
--
-- Two documented cart bugs are reproduced deliberately, because a port that
-- "fixes" them catches mons at rates the real game never would (both are in
-- pokegold's docs/bugs_and_glitches.md):
--
--   * When 3 * maxHP >= 256 the routine shifts both HP terms right by two
--     before subtracting, which loses precision and makes the formula
--     misbehave for maxHP above 341.
--   * The status bonus was meant to be 10 for sleep/freeze and 5 for
--     burn/poison/paralysis, but the `and` that tests for sleep/freeze leaves
--     the accumulator zero on the fall-through, so burn, poison and paralysis
--     give no bonus at all.
--
-- Pass `fixBugs = true` to get the intended behaviour instead; nothing in the
-- game sets it, but it makes the difference testable and documents intent.

-- The mod event/hook buses.  `catch.rate` and `battle.ball_thrown` are the SAME
-- names src/battle/BattleState.lua raises on Gen 1, with the same argument
-- order and the same payload keys (docs/mod-api-gen2-compat.md).
local Runtime = require("src.mods.Runtime")
local Mon = require("src.battle.gen2.Mon")

local Catching = {}

-- Ball multipliers applied to the species catch rate before the HP term.
-- MASTER_BALL never fails, so it short-circuits rather than multiplying.
-- The specialty balls (BallMultiplierFunctionTable) are conditional and live
-- in Catching.specialtyRate below; FRIEND_BALL has no rate function at all --
-- its whole effect is the caught mon's happiness, which the catch site sets.
Catching.BALL_MULTIPLIER = {
  MASTER_BALL = math.huge,
  ULTRA_BALL = 2,
  -- SafariBallMultiplier, GreatBallMultiplier and ParkBallMultiplier are one
  -- shared routine on the cart (x1.5); Safari is the RBY leftover.
  GREAT_BALL = 1.5,
  POKE_BALL = 1,
  SAFARI_BALL = 1.5,
  PARK_BALL = 1.5,
  FRIEND_BALL = 1,
}

-- FastBallMultiplier (engine/items/item_effects.asm): meant to cover all
-- three FleeMons tables, but the loop advances `d` on every byte instead of
-- every table (`jr nz, .next` where the intended jump is `.loop`), so only
-- the first three rows of SometimesFleeMons (data/wild/flee_mons.asm) ever
-- get the x4.  Reproduced deliberately, like the two catch-formula bugs.
Catching.FAST_BALL_SPECIES = {
  MAGNEMITE = true, GRIMER = true, TANGELA = true,
}

-- FRIEND_BALL_HAPPINESS (constants/pokemon_data_constants.asm): the one thing
-- a Friend Ball does.  The catch site stamps it on the caught mon.
Catching.FRIEND_BALL_HAPPINESS = 200

-- HeavyBallMultiplier's weight conversion: the dex weight (tenths of a
-- pound) is turned into tenths of a kilogram with three shift-subtracts
-- (w/2 - w/32 - w/64), and only the HIGH byte of that is compared.
function Catching.heavyBallBoost(weight)
  local half = math.floor((weight or 0) / 2)
  local sub1 = math.floor(half / 16)
  local sub2 = math.floor(sub1 / 2)
  local high = math.floor((half - sub1 - sub2) / 256)
  if high < 4 then return -20 end   -- under 102.4 kg
  if high < 8 then return 0 end     -- under 204.8 kg
  if high < 12 then return 20 end   -- under 307.2 kg
  if high < 16 then return 30 end   -- under 409.6 kg
  return 40
end

-- The conditional balls (engine/items/item_effects.asm
-- BallMultiplierFunctionTable, HeavyBallMultiplier..FastBallMultiplier).
-- `rate` is the species catch rate byte; every arm caps at 255 the way each
-- `sla b / jr c` pins $ff.  Three cart bugs are reproduced deliberately (all
-- in pokegold's own comments): Fast Ball only knows three species, Love Ball
-- boosts SAME-sex pairs, and Moon Ball compares the evolution stone against
-- Gen 1's Moon Stone constant -- Burn Heal in Gen 2 -- so it never boosts.
-- `fixBugs` flips all three to the intended behaviour, same contract as the
-- catch-formula bugs above.
-- One arm per row of BallMultiplierFunctionTable, each fn(rate, opts) -> rate.
-- The records below hang these on `specialty` by identity, so a registry read
-- and Catching.specialtyRate can never answer differently.
local SPECIALTY = {
  HEAVY_BALL = function(rate, opts)
    -- Additive, not a multiplier; the light-mon subtraction floors at 1
    -- (`ld b, $1` on underflow).
    if not opts.weight then return rate end
    return math.max(1, rate + Catching.heavyBallBoost(opts.weight))
  end,
  LEVEL_BALL = function(rate, opts)
    -- x2 / x4 / x8 as the wild level falls below the player's level, its
    -- half and its quarter (strictly below at each rung).
    local player = opts.playerLevel
    local enemy = opts.level
    if not (player and enemy) or enemy >= player then return rate end
    rate = rate * 2
    if enemy < math.floor(player / 2) then rate = rate * 2 end
    if enemy < math.floor(player / 4) then rate = rate * 2 end
    return math.min(255, rate)
  end,
  LURE_BALL = function(rate, opts)
    -- x3, only in a BATTLETYPE_FISH battle.
    if not opts.fishing then return rate end
    return math.min(255, rate * 3)
  end,
  FAST_BALL = function(rate, opts)
    if opts.fixBugs then
      if not opts.fleeing then return rate end
    elseif not Catching.FAST_BALL_SPECIES[opts.species] then
      return rate
    end
    return math.min(255, rate * 4)
  end,
  MOON_BALL = function(rate, opts)
    -- MOON_STONE_RED is BURN_HEAL's Gen 2 id and nothing evolves with a
    -- Burn Heal, so the intended x4 never happens on the cart.
    local wanted = opts.fixBugs and "MOON_STONE" or "BURN_HEAL"
    if opts.evolveItem ~= wanted then return rate end
    return math.min(255, rate * 4)
  end,
  LOVE_BALL = function(rate, opts)
    -- x8 for the same species; the sex test's `ret nz` should be `ret z`,
    -- so the boost lands on SAME-sex pairs.  Genderless mons never boost.
    if not opts.species or opts.species ~= opts.playerSpecies then
      return rate
    end
    local wild, player = opts.gender, opts.playerGender
    if not wild or not player or wild == "unknown"
        or player == "unknown" then
      return rate
    end
    local same = wild == player
    if opts.fixBugs then same = not same end
    if not same then return rate end
    return math.min(255, rate * 8)
  end,
}

function Catching.specialtyRate(rate, ball, opts)
  opts = opts or {}
  local arm = SPECIALTY[ball]
  if not arm then return rate end
  return arm(rate, opts)
end

Catching.STATUS_BONUS = { sleep = 10, freeze = 10 }
Catching.STATUS_BONUS_FIXED = {
  sleep = 10, freeze = 10, burn = 5, poison = 5, toxic = 5, paralyze = 5,
}

-- ------------------------------------------------------------------ registry
--
-- Gold's own ball records, in the shape src/mods/Schemas.lua's `balls` registry
-- validates -- the SAME registry name Gen 1 fills from src/battle/Catching.lua,
-- because a mod that adds a ball should not have to learn a second noun.  The
-- Gen 1 fields keep their Gen 1 meaning where Gen 2 has one:
--
--   randMax    the ceiling of the catch roll.  PokeBallEffect rolls ONE byte
--              against wFinalCatchRate, so every rolling ball is 255 here;
--              Gen 1's per-ball 200/150 ceilings have no Gen 2 counterpart.
--   autoCatch  MASTER_BALL, which returns before the rate is computed.
--   flicker    DoBallTossSpecialEffects' OBJ-palette strobe, Master and Ultra.
--
-- hpFactor / wobbleFactor / tossAnim are deliberately absent: Gen 2 decides the
-- wobble count inside the animation (GetPokeBallWobble re-rolls per wobble), so
-- there is no ballFactor2 to carry, and the toss arc is the animation's.
--
-- Two fields Gen 2 genuinely carries that Gen 1 does not, added rather than
-- renaming anything (the catalog's top-level records are extensible):
--
--   multiplier   the flat factor BallMultiplierFunctionTable applies to the
--                species catch rate.  math.huge is the Master Ball's "never
--                fails" and pairs with autoCatch.
--   specialty    the conditional arm, fn(rate, opts) -> rate, for the balls
--                whose factor depends on the battle rather than the ball.
--                Present exactly where BALL_MULTIPLIER has no row.
--
-- FRIEND_BALL keeps multiplier 1 and carries its one real effect as
-- catchHappiness; src/ui/gen2/BattleState.lua stamps it on the caught mon.
Catching.BALLS = {
  MASTER_BALL = { randMax = 0, autoCatch = true, flicker = true,
                  multiplier = Catching.BALL_MULTIPLIER.MASTER_BALL },
  ULTRA_BALL  = { randMax = 255, flicker = true,
                  multiplier = Catching.BALL_MULTIPLIER.ULTRA_BALL },
  GREAT_BALL  = { randMax = 255,
                  multiplier = Catching.BALL_MULTIPLIER.GREAT_BALL },
  POKE_BALL   = { randMax = 255,
                  multiplier = Catching.BALL_MULTIPLIER.POKE_BALL },
  SAFARI_BALL = { randMax = 255,
                  multiplier = Catching.BALL_MULTIPLIER.SAFARI_BALL },
  PARK_BALL   = { randMax = 255,
                  multiplier = Catching.BALL_MULTIPLIER.PARK_BALL },
  FRIEND_BALL = { randMax = 255,
                  multiplier = Catching.BALL_MULTIPLIER.FRIEND_BALL,
                  catchHappiness = Catching.FRIEND_BALL_HAPPINESS },
  HEAVY_BALL  = { randMax = 255 },
  LEVEL_BALL  = { randMax = 255 },
  LURE_BALL   = { randMax = 255 },
  FAST_BALL   = { randMax = 255 },
  MOON_BALL   = { randMax = 255 },
  LOVE_BALL   = { randMax = 255 },
}

-- the conditional arms, hung on the records they belong to by identity so a
-- registry read and Catching.specialtyRate cannot answer differently
for id, arm in pairs(SPECIALTY) do
  Catching.BALLS[id].specialty = arm
end

-- vanilla registrations, engine-owned (Schemas.ENGINE), so a mod's register of
-- one of these ids collides the way it does on Red and has to say override
function Catching.registerInto(registry, _, owner)
  for id, record in pairs(Catching.BALLS) do
    registry:register(id, record, owner)
  end
end

-- The merged `balls` table for this boot, or nil.  Every catch site hands the
-- module what it already holds -- a Battle (src/battle/gen2/Battle.lua keeps
-- `data`), the data table itself, or the merged subtable -- so no state has to
-- live on this module.
local function mergedBalls(opts)
  if not opts then return nil end
  if opts.balls then return opts.balls end
  local data = opts.data or (opts.battle and opts.battle.data)
  return data and data.gen2Balls or nil
end

-- The merged record for a ball id, the module's own when no loader ran.  An
-- unknown id answers nil on both paths: PokeBallEffect's table has no default
-- row, and the rate math below leaves the species rate alone for one.
function Catching.recordFor(ball, opts)
  local merged = mergedBalls(opts)
  local record = merged and merged[ball]
  if record then return record end
  return Catching.BALLS[ball]
end

local function rand(random, n)
  if random then return random(n) end
  if love and love.math and love.math.random then
    return love.math.random(n) - 1
  end
  return math.random(n) - 1
end

-- The 0..255 rate.  `opts`: maxHp, hp, catchRate, ball, status, fixBugs;
-- the specialty-ball conditions ride the same table (weight, level,
-- playerLevel, fishing, species, playerSpecies, gender, playerGender,
-- evolveItem), each supplied by the catch site out of what it already knows.
--
-- One more optional key and it is the registry seam: `data` (or `battle`, or
-- the merged `balls` / `statuses` subtables directly).  A catch site that
-- passes it gets the merged records, so a mod's ball and a mod's status reach
-- the roll; one that does not gets the module's own, which is what every
-- pure-module test and every loader-free boot has always had.
function Catching.rate(opts)
  opts = opts or {}
  local ball = opts.ball or "POKE_BALL"
  -- Through the merged `balls` registry, module records when no loader ran.
  -- The three arms are exactly the three rows the record can carry: a flat
  -- multiplier, a conditional arm, or neither -- and "neither" is also what an
  -- unknown ball id gets, which is BallMultiplierFunctionTable's own answer of
  -- leaving the species rate alone.
  local record = Catching.recordFor(ball, opts)
  local multiplier = record and record.multiplier
  if record and record.autoCatch then return 255, true end
  if multiplier == math.huge then return 255, true end

  local maxHp = math.max(1, opts.maxHp or 1)
  local hp = math.max(0, math.min(opts.hp or maxHp, maxHp))
  local catchRate
  if multiplier then
    catchRate = math.floor((opts.catchRate or 45) * multiplier)
  elseif record and record.specialty then
    catchRate = record.specialty(opts.catchRate or 45, opts)
  else
    catchRate = opts.catchRate or 45
  end
  catchRate = math.max(1, math.min(255, catchRate))

  local tripleMax = maxHp * 3
  local doubleHp = hp * 2
  if tripleMax >= 256 then
    -- The cart's precision loss: both terms shift right two bits.
    tripleMax = math.floor(tripleMax / 4)
    doubleHp = math.floor(doubleHp / 4)
    if not opts.fixBugs then
      -- And it then compares only the low byte of the shifted max.
      tripleMax = tripleMax % 256
    end
    doubleHp = math.max(1, doubleHp)
  end
  tripleMax = math.max(1, tripleMax)

  local rate = math.floor((tripleMax - doubleHp) * catchRate / tripleMax)
  rate = math.max(1, rate)

  rate = rate + Catching.statusBonus(opts.status, opts)
  return math.min(255, rate), false
end

-- Exact stock catch probability for read-only previews.  A catch.rate hook
-- may replace the roll entirely, so nil is safer than presenting a guess.
function Catching.chance(opts)
  if Runtime.wantsHook("catch.rate") then return nil end
  local rate, guaranteed = Catching.rate(opts)
  if guaranteed or rate >= 255 then return 100 end
  return rate * 100 / 256
end

-- The status half of the rate, off the merged `statuses` record the same way
-- src/battle/Catching.lua reads record.catchBonus on Gen 1.  Gold's records
-- live on src/battle/gen2/Battle.lua (Battle.STATUSES) and carry BOTH numbers:
-- `catchBonus` is what the cart actually adds (the `and` that tests for
-- sleep/freeze leaves burn, poison and paralysis at zero) and
-- `catchBonusIntended` is the 5 the table meant to give them, which is what
-- `fixBugs` asks for.  The two module tables answer when no loader ran.
function Catching.statusBonus(status, opts)
  if not status then return 0 end
  local data = opts and (opts.data or (opts.battle and opts.battle.data))
  local statuses = (opts and opts.statuses) or (data and data.gen2Statuses)
  local record = statuses and statuses[status]
  if record then
    if opts and opts.fixBugs then
      return record.catchBonusIntended or record.catchBonus or 0
    end
    return record.catchBonus or 0
  end
  local bonuses = (opts and opts.fixBugs) and Catching.STATUS_BONUS_FIXED
    or Catching.STATUS_BONUS
  return bonuses[status] or 0
end

-- constants/landmark_constants.asm:24, the fallback when no cache is passed.
Catching.LANDMARK_NATIONAL_PARK = 19

local function landmarkIndex(opts, id, fallback)
  local data = opts and (opts.data or (opts.battle and opts.battle.data))
  local rows = (opts and opts.landmarks)
    or (data and data.gen2Landmarks and data.gen2Landmarks.landmarks)
  local row = rows and rows[id]
  return (row and row.index) or fallback
end

-- GetWorldMapLocation with the POKECENTER_2F backup-map swap
-- (engine/pokemon/caught_data.asm:177-193) and the Bug Contest override (:73-81).
function Catching.caughtLandmark(opts)
  opts = opts or {}
  if opts.bugContest then
    return landmarkIndex(opts, "LANDMARK_NATIONAL_PARK",
      Catching.LANDMARK_NATIONAL_PARK)
  end
  if opts.landmark then return opts.landmark end
  local map = opts.map
  if map and map.id == "POKECENTER_2F" and opts.backupMap then
    map = opts.backupMap
  end
  return (map and map.landmark) or 0
end

-- SetCaughtData (engine/pokemon/caught_data.asm:163-199); no-op off Crystal.
function Catching.stampCaughtData(mon, opts)
  opts = opts or {}
  if not Mon.hasCaughtData(opts.version) then return mon end
  local save = opts.save or (opts.battle and opts.battle.save)
  return Mon.setCaughtData(mon, {
    level = opts.level or (type(mon) == "table" and mon.level) or 0,
    timeOfDay = opts.timeOfDay,
    landmark = Catching.caughtLandmark(opts),
    playerGender = opts.playerGender
      or (save and save.player and save.player.gender),
  })
end

-- Does the ball catch?  Returns caught and the final rate (wFinalCatchRate).
-- A rate of 255 or a Master Ball is certain.
--
-- No wobble count comes out of here: unlike Gen 1, Gen 2 decides how many times
-- the ball rocks DURING the animation.  GetPokeBallWobble
-- (engine/battle_anims/pokeball_wobble.asm) is called once per wobble and
-- re-rolls Random against the WobbleProbabilities row that wFinalCatchRate
-- picks, so the count is a property of the animation loop and not of how near
-- the catch roll was.  The caller runs that loop with the rate returned here.
function Catching.attempt(opts)
  opts = opts or {}
  local caught, rate
  if Runtime.wantsHook("catch.rate") then
    -- catch.rate, the same hook BattleState:catchAttempt calls on Gen 1 and
    -- with the same four arguments: the ball id, the target mon, its species
    -- record, and the options table vanilla is actually run on -- so a mod
    -- that edits o.catchRate or o.status changes the roll exactly as it does
    -- on Red, and one that returns `caught, rate` replaces it outright.
    --
    -- `mon` and `def` are whatever the catch site supplied, and nil rather
    -- than a stand-in a mod would read as the real mon when it supplied
    -- neither.  Gold's battle screen (src/ui/gen2/BattleState.lua) passes them
    -- with `battle` alongside the flat hp/maxHp/catchRate/status fields, which
    -- is what puts the capture tail below on the real catch: the Transform
    -- reload and the battle.catch_exp hook both hang off the battle, and
    -- neither can be reached from a flat table.
    caught, rate = Runtime.call("catch.rate", function(_, _, _, o)
      return Catching.vanillaAttempt(o)
    end, opts.ball or "POKE_BALL", opts.mon, opts.def, opts)
  else
    caught, rate = Catching.vanillaAttempt(opts)
  end
  -- PokeBallEffect's captured tail runs BEFORE the mon is added to anything
  -- (item_effects.asm:514-566), so a caught mon is reloaded out of its base
  -- data -- and the battle.catch_exp hook is asked -- here, while the record
  -- the catch site is about to keep is still the battle's.  Both live on
  -- Battle:caught; this is the seam that reaches it, and it is only reachable
  -- when the site hands over the battle it is catching out of (see the note on
  -- `mon` below).  A caller with no battle -- every pure-module test -- gets
  -- the roll and nothing else, exactly as before.
  if caught and opts.battle and opts.battle.caught then
    opts.battle:caught(opts.mon)
  end
  -- battle.ball_thrown, the payload BattleState:throwBall emits on Gen 1.
  -- `shakes` is deliberately nil rather than 0: Gen 2 does not decide the
  -- wobble count here at all (see the note on Catching.attempt above -- the
  -- animation loop re-rolls GetPokeBallWobble per wobble), so there is no
  -- number to report at throw time and a 0 would read as "it did not rock".
  -- `rate` is the Gen 2 addition, the wFinalCatchRate the animation runs on.
  if Runtime.wants("battle.ball_thrown") then
    Runtime.emit("battle.ball_thrown", {
      battle = opts.battle, ball = opts.ball or "POKE_BALL",
      caught = caught, shakes = nil, rate = rate,
      mon = opts.mon, species = opts.species,
    })
  end
  return caught, rate
end

function Catching.vanillaAttempt(opts)
  local rate, guaranteed = Catching.rate(opts)
  local random = opts and opts.random
  if guaranteed or rate >= 255 then return true, rate end
  -- The cart rolls one byte against the rate; a roll under it catches.
  local roll = rand(random, 256)
  if roll < rate then return true, rate end
  return false, rate
end

return Catching
