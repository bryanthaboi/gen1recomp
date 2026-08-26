-- Gen 2 evolution: which species a party member turns into, whether its
-- condition is met right now, and what the party record becomes afterwards.
--
-- Love-free on purpose, the same way src/core/gen2/Boxes.lua is: every
-- question a screen asks here is table math over data/generated/pokemon.lua's
-- `evolutions` rows, so tests/gen2_evolution_test.lua can drive a whole
-- evolution with no window.  src/ui/gen2/EvolutionAnim.lua is the only half
-- that draws.
--
-- Ported from engine/pokemon/evolve.asm:
--   EvolveAfterBattle          the master loop over the party, one flagged
--                              slot at a time, and the condition walk inside
--                              each species' EvosAttacks rows
--   UpdateSpeciesNameIfNotNicknamed   the nickname keeps only if it is a real
--                              nickname and not the old species' own name
--   LearnLevelMoves            the new species' moves for the level it is
--                              already at, run right after the pic changes
-- and the frame counts of engine/movie/evolution_animation.asm, which live
-- here rather than in the screen so the schedule is assertable.
--
-- What flags a slot: engine/battle/core.asm sets wEvolvableFlags for a mon the
-- moment it levels up (right after its LearnLevelMoves run), and ExitBattle
-- calls EvolveAfterBattle only on a win.  src/ui/gen2/BattleState.lua keeps
-- that flag set from the battle's own `level` events.
--
-- Everything a party member becomes is built by src/battle/gen2/Mon.lua and
-- nothing else: Evolution.apply recomputes stats through Mon.stats and rebuilds
-- the record through Mon.new, so an evolved mon can never end up with the
-- half-filled shape a second builder would hand back.

local Mon = require("src.battle.gen2.Mon")
local Runtime = require("src.mods.Runtime")

local Evolution = {}

-- constants/pokemon_data_constants.asm, as the extractor spells them into
-- pokemon.lua's `evolutions` rows.
Evolution.LEVEL = "EVOLVE_LEVEL"
Evolution.ITEM = "EVOLVE_ITEM"
Evolution.TRADE = "EVOLVE_TRADE"
Evolution.HAPPINESS = "EVOLVE_HAPPINESS"
Evolution.STAT = "EVOLVE_STAT"

-- HAPPINESS_TO_EVOLVE EQU 220.
Evolution.HAPPINESS_TO_EVOLVE = 220

-- IsMonHoldingEverstone: one item id, checked before LEVEL, HAPPINESS, STAT
-- and TRADE.  It is deliberately NOT checked on the ITEM path -- .item in
-- EvolveAfterBattle never calls it -- which is why a stone still works on a
-- mon holding an Everstone in Gen 2.
Evolution.EVERSTONE = "EVERSTONE"

-- EVOLVE_HAPPINESS triggers (TR_ANYTIME / TR_MORNDAY / TR_NITE).  A row with
-- no `time` is TR_ANYTIME, the first constant.
Evolution.ANYTIME = "ANYTIME"
Evolution.MORNDAY = "MORNDAY"
Evolution.NITE = "NITE"

-- EVOLVE_STAT comparisons (ATK_GT_DEF / ATK_LT_DEF / ATK_EQ_DEF).
Evolution.ATK_GT_DEF = "ATK_GT_DEF"
Evolution.ATK_LT_DEF = "ATK_LT_DEF"
Evolution.ATK_EQ_DEF = "ATK_EQ_DEF"

--------------------------------------------------------------------------
-- Conditions
--------------------------------------------------------------------------

function Evolution.holdsEverstone(mon)
  return (mon and mon.item) == Evolution.EVERSTONE
end

-- .got_tyrogue_evo: CompareBytes over wTempMonAttack vs wTempMonDefense, so
-- the comparison is on the mon's CURRENT stats, not its base stats or DVs.
function Evolution.statComparison(mon)
  local stats = (mon and mon.stats) or {}
  local attack, defense = stats.attack or 0, stats.defense or 0
  if attack == defense then return Evolution.ATK_EQ_DEF end
  if attack < defense then return Evolution.ATK_LT_DEF end
  return Evolution.ATK_GT_DEF
end

-- wTimeOfDay is compared against NITE_F and nothing else, so every daytime
-- that is not night reads the same to a happiness evolution.
local function isNight(timeOfDay)
  return timeOfDay == Evolution.NITE or timeOfDay == "NITE_F"
end

-- One EvosAttacks row against one mon.  Returns true, or false plus the short
-- reason the row was skipped (for tests and the driver; the cart just falls
-- through to .dont_evolve_N).
--
-- `ctx` is the state EvolveAfterBattle reads out of WRAM:
--   link          wLinkMode ~= 0 (a trade is in progress)
--   timeCapsule   wLinkMode == LINK_TIMECAPSULE
--   force         wForceEvolution ~= 0 (an evolution stone was just used),
--                 which is what gates the ITEM path ON and every other
--                 non-trade path OFF
--   item          wCurItem, the stone being used
--   timeOfDay     wTimeOfDay, one of MORN / DAY / NITE / DARK
-- One record per EvosAttacks method, in the shape src/mods/Schemas.lua's
-- `evolution_methods` registry validates.  Same registry NAME Gen 1 fills from
-- src/pokemon/Evolution.lua, because a mod that adds a way to evolve should not
-- have to learn a second noun -- only the ids differ, and they have to: Gold's
-- extractor writes EVOLVE_LEVEL where Red's writes LEVEL.
--
-- `check` is the schema's required field and keeps its Gen 1 job of answering
-- "does this row fire right now"; the signature is Gold's own
-- fn(entry, mon, ctx) -> ok, reason, consumesHeldItem, because Gold reads an
-- EvosAttacks row and a party record rather than Gen 1's game/mon/evo/trigger.
--
-- Two fields Gen 2 adds rather than renaming anything, and both exist because
-- EvolveAfterBattle's two cross-cutting gates are per-method:
--
--   requiresLink   EVOLVE_TRADE, the one method a link ENABLES rather than
--                  blocks, so it is tested ahead of the link gate
--   requiresForce  EVOLVE_ITEM, which only ever fires from a stone's use, so
--                  wForceEvolution does not block it the way it blocks the rest
Evolution.METHODS = {
  [Evolution.TRADE] = {
    requiresLink = true,
    check = function(entry, mon, ctx)
      if not ctx.link then return false, "not trading" end
      if Evolution.holdsEverstone(mon) then return false, "everstone" end
      -- `ld a, [hli] / ld b, a / inc a / jr z, .proceed`: $ff (the extractor
      -- writes that as no item at all) means any trade will do.
      if entry.item then
        if ctx.timeCapsule then return false, "time capsule" end
        if (mon and mon.item) ~= entry.item then return false, "wrong item" end
        -- The held item is consumed by the trade evolution.
        return true, nil, true
      end
      return true
    end,
  },
  [Evolution.ITEM] = {
    requiresForce = true,
    check = function(entry, _, ctx)
      if entry.item and ctx.item ~= entry.item then
        return false, "wrong item"
      end
      -- .item's own `ld a, [wForceEvolution] / and a / jp z, .dont_evolve_3`:
      -- a stone evolution only ever fires from the item's use, never from the
      -- after-battle sweep.
      if not ctx.force then return false, "not forced" end
      return true
    end,
  },
  [Evolution.LEVEL] = {
    check = function(entry, mon, _)
      if ((mon and mon.level) or 1) < (entry.level or 0) then
        return false, "level"
      end
      if Evolution.holdsEverstone(mon) then return false, "everstone" end
      return true
    end,
  },
  [Evolution.HAPPINESS] = {
    check = function(entry, mon, ctx)
      if ((mon and mon.happiness) or 0) < Evolution.HAPPINESS_TO_EVOLVE then
        return false, "happiness"
      end
      if Evolution.holdsEverstone(mon) then return false, "everstone" end
      local trigger = entry.time or Evolution.ANYTIME
      if trigger == Evolution.NITE and not isNight(ctx.timeOfDay) then
        return false, "daytime"
      end
      if trigger == Evolution.MORNDAY and isNight(ctx.timeOfDay) then
        return false, "night"
      end
      return true
    end,
  },
  [Evolution.STAT] = {
    check = function(entry, mon, _)
      if ((mon and mon.level) or 1) < (entry.level or 0) then
        return false, "level"
      end
      if Evolution.holdsEverstone(mon) then return false, "everstone" end
      if entry.comparison ~= Evolution.statComparison(mon) then
        return false, "stats"
      end
      return true
    end,
  },
}

-- vanilla registrations, engine-owned (Schemas.ENGINE), so a mod's register of
-- one of these ids collides the way it does on Red and has to say override
function Evolution.registerInto(registry, _, owner)
  for id, record in pairs(Evolution.METHODS) do
    registry:register(id, record, owner)
  end
end

-- the merged `evolution_methods` record for a method id, the module's own when
-- no loader ran (src/pokemon/Evolution.lua:pendingFor is the Gen 1 twin)
function Evolution.methodFor(data, method)
  if method == nil then return nil end
  local merged = data and data.gen2EvolutionMethods
  return (merged and merged[method]) or Evolution.METHODS[method]
end

function Evolution.rowMatches(entry, mon, ctx, data)
  ctx = ctx or {}
  if not (entry and entry.method and entry.into) then return false, "empty" end
  local record = Evolution.methodFor(data, entry.method)
  local check = record and record.check

  -- The two cross-cutting gates in EvolveAfterBattle's own order, with each
  -- method's exemption tested just ahead of the gate it is exempt from -- so
  -- an unknown method still reports "linked" or "forced" first, exactly as the
  -- if-chain this replaced did.
  --
  -- .trade runs BEFORE the link check, because it is the one method that
  -- requires a link rather than being blocked by one.
  if check and record.requiresLink then return check(entry, mon, ctx) end
  -- `ld a, [wLinkMode] / and a / jp nz, .dont_evolve_2`: nothing else fires
  -- while a link is up.
  if ctx.link then return false, "linked" end
  -- .item runs before the force check for the mirror reason: a stone
  -- evolution only ever fires WITH wForceEvolution set.
  if check and record.requiresForce then return check(entry, mon, ctx) end
  -- Everything else is blocked once wForceEvolution is set, so using a stone
  -- cannot also trip a level or happiness evolution on the same mon.
  if ctx.force then return false, "forced" end

  if not check then return false, "unknown method" end
  return check(entry, mon, ctx)
end

-- The first row of `def.evolutions` that fires, walked in EvosAttacks order
-- exactly the way .loop does -- the order in the ROM is the tiebreak, which is
-- why Poliwhirl's WATER_STONE row beats its KING'S ROCK trade row.
--
-- Returns entry, consumesHeldItem.
--
-- Each row's decision is wrapped by the evolution.check hook so a mod can
-- cancel or force any evolution.  The contract is the Gen 1 one verbatim
-- (src/pokemon/Evolution.lua:pendingFor): four arguments, and the chain
-- returns ONE boolean.  Positions 2, 3 and 4 carry the same things in both
-- games -- the mon, the evolutions[] row, the trigger -- so a wrap written
-- once serves both.  Position 1 is Gen 1's `game`, which does not exist this
-- deep in Gold; it carries `data` here, which is the object a listener would
-- reach through game.data anyway.
--
-- rowMatches is a pure predicate, so running it as the chain's vanilla costs
-- nothing when a mod skips it.  `consumes` (the trade row that eats its held
-- item) rides an upvalue rather than a second return, because a Gen 1 mod
-- returns a bare boolean and would otherwise silently clear it; a mod that
-- forces an evolution without calling next() therefore gets consumes = false,
-- which is the safe direction -- an item not eaten, never one eaten twice.
function Evolution.check(def, mon, ctx, data)
  local hooked = Runtime.wantsHook("evolution.check")
  for _, entry in ipairs((def and def.evolutions) or {}) do
    local consumes = false
    local function vanilla()
      local matched, _, eats = Evolution.rowMatches(entry, mon, ctx, data)
      consumes = eats or false
      return matched and true or false
    end
    local ok
    if hooked then
      ok = Runtime.call("evolution.check", vanilla, data, mon, entry, ctx)
    else
      ok = vanilla()
    end
    if ok then return entry, consumes end
  end
  return nil
end

-- The same, looking the species up in pokemon.lua for the caller.  `data`
-- carries on to rowMatches, which is where the merged evolution_methods
-- registry is read.
function Evolution.checkMon(data, mon, ctx)
  local def = data and data.pokemon and mon and data.pokemon[mon.species]
  if not def then return nil end
  return Evolution.check(def, mon, ctx, data)
end

-- ExitBattle's gate: the sweep runs only when `wBattleResult & $f` is WIN, so
-- a loss (and the whiteout that follows it) never evolves anything.
function Evolution.runsAfterBattle(outcome)
  return outcome ~= "lose" and outcome ~= "draw"
end

-- EvolveAfterBattle_MasterLoop: the flagged party slots in party order, each
-- with the row that will fire.  `flags` is a set of party indices, matching
-- wEvolvableFlags; nil means every slot is eligible (the item path, which sets
-- the flag for wCurPartyMon only, passes a single-entry set).
function Evolution.plan(data, party, flags, ctx)
  local out = {}
  for index, mon in ipairs(party or {}) do
    if not flags or flags[index] then
      local entry, consumes = Evolution.checkMon(data, mon, ctx)
      if entry then
        out[#out + 1] = {
          index = index,
          mon = mon,
          entry = entry,
          into = entry.into,
          consumesHeldItem = consumes,
        }
      end
    end
  end
  return out
end

--------------------------------------------------------------------------
-- Applying it
--------------------------------------------------------------------------

-- The species' display name, which is what the nickname is compared against.
function Evolution.speciesName(data, species)
  local def = data and data.pokemon and data.pokemon[species]
  return (def and def.name) or species
end

-- UpdateSpeciesNameIfNotNicknamed: wStringBuffer2 (the nickname captured
-- before the animation) is compared byte for byte against the OLD species'
-- name, and only a mon whose "nickname" is not that name keeps it.  The port
-- stores nil for an un-nicknamed mon, so both shapes have to read as "no
-- nickname" here.
function Evolution.keptNickname(data, mon)
  local nickname = mon and mon.nickname
  if not nickname or nickname == "" then return nil end
  if nickname == Evolution.speciesName(data, mon.species) then return nil end
  return nickname
end

-- LearnLevelMoves at wCurPartyLevel: the NEW species' level-up moves whose
-- level is EXACTLY the level the mon is already at (`cp b / jr nz`, not a
-- range), skipping any it already knows.  An evolution at level 16 therefore
-- teaches only the moves the new species learns at 16 -- everything it "should"
-- have learned earlier stays unlearned, which is the cart's behaviour.
function Evolution.learnedOnEvolve(data, species, level, mon)
  local def = data and data.pokemon and data.pokemon[species]
  local known = {}
  for _, move in ipairs((mon and mon.moves) or {}) do known[move.id] = true end
  local out = {}
  for _, row in ipairs((def and def.levelMoves) or {}) do
    if row.level == level and not known[row.move] then
      known[row.move] = true
      out[#out + 1] = row.move
    end
  end
  return out
end

-- Every field src/battle/gen2/Mon.lua's builder writes.  Evolution.apply hands
-- all of these to Mon.new (or sets them straight after) and carries only the
-- keys outside this set across, so the two files cannot drift into disagreeing
-- about who owns a party record's shape.
Evolution.MON_FIELDS = {
  species = true, name = true, nickname = true, level = true,
  experience = true, dvs = true, stats = true, hp = true, maxHp = true,
  types = true, moves = true, item = true, status = true, happiness = true,
  caughtLevel = true, shiny = true, gender = true,
  caughtTime = true, caughtLocation = true, caughtByGender = true,
}

-- Turn `mon` into `entry.into`.  Returns the NEW record; the caller writes it
-- back into the party slot the way `.pop de / pop hl / ld [hl], a` does.
--
-- The cart's order, and the reason each step is where it is:
--   UpdateSpeciesNameIfNotNicknamed  before GetBaseData, so the comparison is
--                                    still against the old species' name
--   GetBaseData + CalcMonStats       new stats at the SAME level and DVs
--   HP += (newMaxHP - oldMaxHP)      the delta, not a refill and not a refill
--                                    to full: a mon that walked in at half
--                                    health walks out at half health plus the
--                                    max-HP gain
--   CopyBytes tempmon -> party slot
--   LearnLevelMoves                  handled by the caller so it can print
--   SetSeenAndCaughtMon              Evolution.markPokedex
function Evolution.apply(data, mon, entry)
  local species = entry and entry.into
  local def = data and data.pokemon and species and data.pokemon[species]
  if not def then return nil end

  local level = mon.level or 1
  -- CalcMonStats runs through the one builder, so an evolved mon's stats can
  -- never disagree with a freshly built one's.
  local stats = Mon.stats(def.baseStats, mon.dvs, level, mon.statExp)
  local previousMax = mon.maxHp or (mon.stats and mon.stats.hp) or stats.hp
  local hp = (mon.hp or previousMax) + (stats.hp - previousMax)
  -- The cart does not clamp; the bound only matters for data where an
  -- evolution LOSES max HP, which no shipped species does.
  hp = math.max(0, math.min(stats.hp, hp))

  -- `xor a / ld [wTempMonItem], a`: only the trade branch that DEMANDED a held
  -- item consumes it; the `$ff` (any trade) branch jumps to .proceed with the
  -- item still on.  Spelled out rather than as `cond and nil or item`, which
  -- would quietly evaluate to the item in both cases.
  local heldItem = mon.item
  if entry.method == Evolution.TRADE and entry.item then heldItem = nil end

  local evolved = Mon.new(data, species, level, {
    dvs = mon.dvs,
    moves = mon.moves,
    hp = hp,
    item = heldItem,
    happiness = mon.happiness,
    nickname = Evolution.keptNickname(data, mon),
  })
  if not evolved then return nil end

  -- wTempMonExp is never touched: the mon keeps the experience it walked in
  -- with, so an evolution cannot push it up or down a level.
  evolved.experience = mon.experience
  evolved.status = mon.status
  evolved.caughtLevel = mon.caughtLevel
  -- Nothing between GetBaseData and the PARTYMON_STRUCT_LENGTH copy back
  -- touches MON_CAUGHTDATA -- engine/pokemon/evolve.asm:291-293.
  evolved.caughtTime = mon.caughtTime
  evolved.caughtLocation = mon.caughtLocation
  evolved.caughtByGender = mon.caughtByGender
  -- Anything a future field adds to a party record (mail, pokerus) rides along
  -- rather than being silently dropped.  Only fields Mon.new does NOT own may
  -- be carried: copying `nickname` back would undo
  -- UpdateSpeciesNameIfNotNicknamed, and copying `item` back would undo the
  -- trade evolution's `xor a / ld [wTempMonItem], a`.
  for key, value in pairs(mon) do
    if Evolution.MON_FIELDS[key] == nil then evolved[key] = value end
  end
  -- Same name and payload keys as the Gen 1 site (src/pokemon/Evolution.lua),
  -- so one subscription covers both games.  `mon` is the EVOLVED record, not
  -- the one that walked in: Gen 1 emits after the species swap, and a listener
  -- reading mon.species expects the new one.  `via` is the method id that
  -- fired (EVOLVE_LEVEL, EVOLVE_ITEM, EVOLVE_TRADE, EVOLVE_HAPPINESS, ...),
  -- which is Gen 2's equivalent of Gen 1's trigger kind.
  Runtime.emit("pokemon.evolved", {
    mon = evolved, fromSpecies = mon.species, toSpecies = species,
    via = entry.method,
  })
  return evolved
end

-- SetSeenAndCaughtMon: an evolution ticks the new species off as BOTH seen and
-- caught, the same pair GivePoke sets, because the mon is in the party.
function Evolution.markPokedex(save, species)
  if not (save and species) then return false end
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.caught = save.pokedex.caught or {}
  save.pokedex.seen[species] = true
  save.pokedex.caught[species] = true
  return true
end

--------------------------------------------------------------------------
-- Animation schedule (engine/movie/evolution_animation.asm)
--------------------------------------------------------------------------

-- EvolveAfterBattle prints EvolvingText ("What? <NICK> is evolving!") and then
-- `ld c, 50 / call DelayFrames` before it clears the top 12 rows and starts
-- the animation.  The text box itself is NOT cleared, so that line stays under
-- the pic for the whole animation.
Evolution.EVOLVING_FRAMES = 50

-- The old mon's cry, then MUSIC_EVOLUTION, then `ld c, 80 / call DelayFrames`
-- before the palette goes to PREDEFPAL_BLACKOUT and the flashing starts.
Evolution.MUSIC_FRAMES = 80

-- Each .ReplaceFrontpic ends in WaitBGMap, i.e. one frame per pic swap, and a
-- "flash" is two of them: the new stage's tiles, then back to the old.
Evolution.SWAP_FRAMES = 1

-- .PlayEvolvedSFX: 32 frames spawning balls of light (two every other frame,
-- 32 in all) and then `ld c, 32` more frames animating them out.
Evolution.BALL_SPAWN_FRAMES = 32
Evolution.BALL_TAIL_FRAMES = 32

-- After the animation: CongratulationsYourPokemonText, EvolvedIntoText,
-- MUSIC_NONE, SFX_CAUGHT_MON, WaitSFX, then `ld c, 40 / call DelayFrames`.
Evolution.CONGRATS_FRAMES = 40

-- `lb bc, 1, 16` then, per round, `inc b / dec c / dec c`: eight rounds of
-- "hold the old pic for c frames (watching for B), then alternate the two pics
-- b times".  The hold shrinks by two frames a round while the alternation gets
-- one flash longer, which is what makes the flicker accelerate.
function Evolution.flashRounds()
  local rounds = {}
  local flashes, wait = 1, 16
  while wait > 0 do
    rounds[#rounds + 1] = { wait = wait, flashes = flashes }
    flashes = flashes + 1
    wait = wait - 2
  end
  return rounds
end

-- How many frames the flashing half of the animation takes, end to end.
function Evolution.flashFrames()
  local total = 0
  for _, round in ipairs(Evolution.flashRounds()) do
    total = total + round.wait + round.flashes * 2 * Evolution.SWAP_FRAMES
  end
  return total
end

-- .GenerateBallOfLight spawns two balls on every EVEN jumptable index over the
-- 32 spawn frames, 180 degrees apart, and AnimSeq_RevealNewMon walks each one
-- out from radius $10 in steps of $08 until it passes $80.
Evolution.BALL_RADIUS_START = 0x10
Evolution.BALL_RADIUS_STEP = 0x08
Evolution.BALL_RADIUS_END = 0x80

-- depixel 9, 11 -- Y TILE FIRST -- and an OAM object draws at (x - 8, y - 16),
-- so the balls come out of (80, 56), just under the middle of the 7x7 pic box
-- at hlcoord 7, 2.
Evolution.BALL_ORIGIN_X = 11 * 8 - 8
Evolution.BALL_ORIGIN_Y = 9 * 8 - 16

return Evolution
