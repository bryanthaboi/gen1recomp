-- Gen 2 Day-Care, breeding and eggs: the whole model, love-free.
--
-- Sits beside src/core/gen2/Boxes.lua and src/core/gen2/Evolution.lua for the
-- same reason they are separate from their screens: every question the Day-Care
-- conversation asks is table math over data/generated/pokemon.lua's
-- `eggGroups`, `eggSteps`, `genderRatio`, `evolutions` and `levelMoves` rows,
-- so tests/gen2_breeding_test.lua can deposit two mons, walk 5120 steps and
-- hatch an egg with no window open.  src/ui/gen2/DayCareMenu.lua is the only
-- half that draws.
--
-- Ported from:
--   engine/events/daycare.asm        DayCareMan / DayCareLady (the whole
--                                    conversation), DayCareAskDepositPokemon,
--                                    GetPriceToRetrieveBreedmon, DayCareGiveEgg,
--                                    DayCareManOutside and DayCare_InitBreeding
--                                    (which is where the egg is actually built)
--   engine/pokemon/breeding.asm      CheckBreedmonCompatibility, DoEggStep,
--                                    HatchEggs, InitEggMoves, GetEggMove,
--                                    LoadEggMove, GetHeritableMoves,
--                                    GetBreedmonMovePointer and
--                                    DayCareMonCompatibilityText
--   engine/events/happiness_egg.asm  DayCareStep: the +1 exp per step and the
--                                    wStepsToEgg countdown that rolls the egg
--   engine/pokemon/move_mon.asm      DepositBreedmon / RetrieveBreedmon
--   engine/pokemon/breedmon_level_growth.asm  GetBreedMon1LevelGrowth
--   engine/overworld/events.asm      the step block that orders DoEggStep
--                                    against DayCareStep
--
-- A hatched mon is built by src/battle/gen2/Mon.lua and nothing else, the same
-- rule Evolution.apply follows: Breeding.hatch hands Mon.new the egg's species,
-- level, DVs and moves and lets the one builder produce the record, so a
-- hatchling can never end up with the half-filled shape a second builder gives.
--
-- Two data fields this reads that the extractor does not write yet:
--   def.eggMoves   data/pokemon/egg_moves.asm, one list of move ids per
--                  species.  Absent from the cache today; every reader below
--                  falls back to an empty list, which costs exactly the
--                  "father passes an egg move" branch of GetEggMove and
--                  nothing else.  It starts working the moment the field
--                  appears -- see the test's cache block.
-- (def.tmhm, def.eggGroups, def.eggSteps, def.genderRatio and def.evolutions
-- are all already in data/generated/pokemon.lua.)

local Mail = require("src.core.gen2.Mail")
local Mon = require("src.battle.gen2.Mon")
local Runtime = require("src.mods.Runtime")

local Breeding = {}

--------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------

-- constants/battle_constants.asm: an egg hatches at level 5.
Breeding.EGG_LEVEL = 5

-- HatchEggs' `ld [hl], $78`: the hatch counter's byte becomes the hatchling's
-- happiness, and $78 is 120 -- not BASE_HAPPINESS (70), which is what a caught
-- mon gets.  A hatchling really does start friendlier than a catch.
Breeding.HATCH_HAPPINESS = 0x78

-- DayCare_InitBreeding's .String_EGG.  An egg is a party member whose species
-- is already the hatchling's (the cart keeps it in the box struct and only
-- writes EGG into wPartySpecies), so the port marks the slot with `isEgg`
-- rather than overwriting the species -- see Breeding.isEgg.
Breeding.EGG_NAME = "EGG"

-- constants/pokemon_data_constants.asm PARTY_LENGTH / NUM_MOVES.
Breeding.PARTY_SIZE = Mon.PARTY_SIZE
Breeding.NUM_MOVES = 4
Breeding.MAX_LEVEL = Mon.MAX_LEVEL

-- DayCare_InitBreeding's `.loop: call Random / cp 150 / jr c, .loop` -- a
-- rejection sample, so the first countdown is 150..255 steps and never less.
-- Every countdown AFTER that is a plain `call Random` (happiness_egg.asm
-- .check_egg), i.e. 0..255, which is why the first egg is reliably slower than
-- the ones that follow it.
Breeding.MIN_STEPS_TO_EGG = 150

-- engine/overworld/events.asm: wStepCount is a byte, StepHappiness fires when
-- it wraps to 0 and DoEggStep when it reads $80 -- so both run once per 256
-- steps, 128 steps out of phase with each other.
Breeding.STEP_CYCLE = 256
Breeding.EGG_STEP_PHASE = 0x80

-- constants/misc_constants.asm MAX_DAY_CARE_EXP is $500000, but DayCareStep
-- only clamps the HIGH byte (`cp HIGH(MAX_DAY_CARE_EXP >> 8)` is `cp $50`)
-- once a carry reaches it, so the real ceiling is $50ffff.
Breeding.MAX_DAY_CARE_EXP = 0x50FFFF

-- GetPriceToRetrieveBreedmon: `hl = 100 * levelsGrown` then `add hl, 100`.
Breeding.WITHDRAW_FEE = 100
Breeding.WITHDRAW_FEE_PER_LEVEL = 100

-- The two species the routines name outright.
Breeding.DITTO = "DITTO"
Breeding.NIDORAN_F = "NIDORAN_F"
Breeding.NIDORAN_M = "NIDORAN_M"
Breeding.TOGEPI = "TOGEPI"

-- constants/pokemon_data_constants.asm's egg-group enum.  EGG_NONE is $f, and
-- a species with EGG_NONE in BOTH nibbles ($ff) is the "No Eggs" group that
-- .CheckBreedingGroupCompatibility refuses before it looks at anything else.
Breeding.EGG_NONE = "EGG_NONE"
Breeding.NO_EGGS_RAW = 0xFF

-- wDayCareMan / wDayCareLady are two separate bytes, so the two sides carry
-- their own HAS_MON and their own DAYCARE_INTRO_SEEN_F.  MONS_COMPATIBLE_F and
-- HAS_EGG_F live only on the man's byte, which is why both are on the shared
-- day-care record below rather than on a side.
Breeding.SIDES = { "man", "lady" }

--------------------------------------------------------------------------
-- Random
--------------------------------------------------------------------------

-- `call Random` yields one byte.  Every roll below goes through this so a test
-- can hand in a scripted sequence and get the cart's exact decisions back.
local function randomByte(rng)
  if rng then return math.floor(rng()) % 256 end
  if love and love.math and love.math.random then
    return love.math.random(0, 255)
  end
  return math.random(0, 255)
end

Breeding.randomByte = randomByte

--------------------------------------------------------------------------
-- Species lookup
--------------------------------------------------------------------------

-- GetPreEvolution walks species 1..NUM_POKEMON in index order and takes the
-- FIRST one that evolves into the target, so the walk needs the dex ordering
-- rather than pairs() order.  Cached against the data table itself (weak keys,
-- so a hot reload's replacement table does not pin the old one).
local orderCache = setmetatable({}, { __mode = "k" })

local function speciesOrder(data)
  local pokemon = data and data.pokemon
  if not pokemon then return {} end
  local hit = orderCache[pokemon]
  if hit then return hit end
  local rows = {}
  for id, def in pairs(pokemon) do
    -- growthRates / tmhmMoves ride the same table and carry no index.
    if type(def) == "table" and type(def.index) == "number" then
      rows[#rows + 1] = { id = id, index = def.index }
    end
  end
  table.sort(rows, function(a, b) return a.index < b.index end)
  local out = {}
  for i, row in ipairs(rows) do out[i] = row.id end
  orderCache[pokemon] = out
  return out
end

Breeding.speciesOrder = speciesOrder

local function defOf(data, species)
  if not (data and data.pokemon and species) then return nil end
  local def = data.pokemon[species]
  return type(def) == "table" and def or nil
end

-- Mon.growthFor, not the raw coefficient table: a hatched egg's starting
-- experience has to sit on the same curve battle EXP and a Rare Candy use, or
-- a mod-registered curve would apply to some of a mon's life and not the rest.
local function growthOf(data, def)
  return require("src.battle.gen2.Mon").growthFor(data, def and def.growthRate)
end

--------------------------------------------------------------------------
-- Eggs as party members
--------------------------------------------------------------------------

-- wPartySpecies holds EGG ($fd) for an egg slot while the box struct under it
-- still holds the hatchling's real species.  The port keeps the species and
-- flags the slot, so every reader that wants "is this thing a mon" asks here.
function Breeding.isEgg(mon)
  return type(mon) == "table" and mon.isEgg == true
end

-- An egg is carried, not fought: DayCareAskDepositPokemon refuses it, the
-- party menu greys it, and it is worth nothing to CheckCurPartyMonFainted
-- because DayCare_GiveEgg zeroes its HP.
function Breeding.canFight(mon)
  return type(mon) == "table" and not Breeding.isEgg(mon)
end

-- How many party members could still battle.  Eggs are excluded by their zero
-- HP alone, but saying so out loud is what keeps a party of one mon and five
-- eggs from reading as six fighters.
function Breeding.healthyCount(party)
  local n = 0
  for _, mon in ipairs(party or {}) do
    if Breeding.canFight(mon) and (mon.hp or 0) > 0 then n = n + 1 end
  end
  return n
end

--------------------------------------------------------------------------
-- Gender
--------------------------------------------------------------------------

-- GetGender (engine/pokemon/mon_stats.asm) against BASE_GENDER.  Deliberately
-- delegated to the port's ONE gender routine rather than transcribed a second
-- time here: a mon that reads "female" in the party menu and "male" to the
-- Day-Care would be a worse bug than the rounding Mon.gender currently has.
--
-- (That rounding: GetGender compares the ratio byte against
-- `attackDV * 16 + speedDV`, and Mon.gender drops the speed term.  The two
-- disagree only for one Attack DV per species -- see the note in this port's
-- Breeding report -- and the fix belongs in src/battle/gen2/Mon.lua, which
-- this file does not own.)
function Breeding.gender(def, dvs)
  return Mon.gender(def, dvs)
end

function Breeding.genderOf(data, mon)
  if not mon then return "unknown" end
  return Breeding.gender(defOf(data, mon.species), mon.dvs)
end

--------------------------------------------------------------------------
-- Egg groups and compatibility
--------------------------------------------------------------------------

-- BASE_EGG_GROUPS is one `dn EGG_x, EGG_y` byte: high nibble first.  The
-- extractor writes both names into `eggGroups` and the raw byte into
-- `eggGroupsRaw`.
function Breeding.eggGroups(def)
  local groups = def and def.eggGroups
  if type(groups) ~= "table" then return nil, nil end
  return groups[1], groups[2]
end

-- `cp EGG_NONE * $11`, i.e. the whole byte is $ff: BOTH nibbles have to be
-- EGG_NONE.  Prefer the raw byte when the cache carries it, because that is
-- the comparison the ASM makes; the names are the fallback for a fixture.
function Breeding.isNoEggs(def)
  if not def then return true end
  if type(def.eggGroupsRaw) == "number" then
    return def.eggGroupsRaw == Breeding.NO_EGGS_RAW
  end
  local first, second = Breeding.eggGroups(def)
  return first == Breeding.EGG_NONE and second == Breeding.EGG_NONE
end

-- .CheckBreedingGroupCompatibility, in its own order: mon2's No-Eggs check,
-- then mon1's, then Ditto (which is compatible with everything that got this
-- far), and only then the four-way nibble comparison.  The order is preserved
-- because it is what makes a Ditto x Legendary pair incompatible: the No-Eggs
-- refusal happens BEFORE the Ditto shortcut.
function Breeding.groupsCompatible(data, species1, species2)
  local def1, def2 = defOf(data, species1), defOf(data, species2)
  if not (def1 and def2) then return false end
  if Breeding.isNoEggs(def2) then return false end
  if Breeding.isNoEggs(def1) then return false end
  if species2 == Breeding.DITTO then return true end
  if species1 == Breeding.DITTO then return true end
  local b, c = Breeding.eggGroups(def2)
  local d, e = Breeding.eggGroups(def1)
  -- `cp b / cp c` for each of mon1's two groups: four comparisons, any hit
  -- wins.  Spelled out rather than looped over {d, e}, because ipairs stops at
  -- the first nil and a def with only one group would drop the second test.
  if d ~= nil and (d == b or d == c) then return true end
  if e ~= nil and (e == b or e == c) then return true end
  return false
end

-- .CheckDVs, verbatim: the Defense DVs and the LOW THREE BITS of the Special
-- DVs both matching is the cart's "these two are too alike" sentinel.  It is
-- not a compatibility bonus even though it produces the highest number --
-- DayCare_InitBreeding's `inc a / ret z` throws 255 out, so the pair never
-- breeds and the Day-Care Man cheerfully reports the mon is "brimming with
-- energy" anyway.
function Breeding.dvsMatch(mon1, mon2)
  local a = (mon1 and mon1.dvs) or {}
  local b = (mon2 and mon2.dvs) or {}
  if (a.defense or 0) % 16 ~= (b.defense or 0) % 16 then return false end
  return (a.special or 0) % 8 == (b.special or 0) % 8
end

-- wBreedMon1ID / wBreedMon2ID.  The port's party record carries no OT id yet,
-- so two home-caught mons both read nil and compare EQUAL -- which is exactly
-- what the cart sees for two mons the player caught himself, and is the whole
-- reason `-77` is the common case rather than the rare one.
local function otId(mon)
  return mon and mon.otId
end

-- CheckBreedmonCompatibility.  Returns wBreedingCompatibility:
--   0    incompatible (no eggs ever)
--   255  the matching-DVs sentinel: the Day-Care Man likes them, they do not
--        breed (see Breeding.dvsMatch)
--   254  same species, different OT ids
--   177  same species, same OT id           (254 - 77)
--   128  different species, different OT ids
--   51   different species, same OT id      (128 - 77)
-- breeding.compatibility, a Gen 2 invention: Gen 1 has no Day-Care pair and so
-- no name to share (docs/mod-api-gen2-compat.md, "New in Gen 2").  The hook
-- wraps the whole of CheckBreedmonCompatibility rather than one of its gates,
-- because every answer the routine can give is a number on the same scale and
-- a mod that wants "these two may breed" only has to return one:
--
--   ctx.data          the Data table the species records come out of
--   ctx.mon1, mon2    the two day-care records, man's side first
--   ctx.dayCare       true when the call came from the yard, false for a
--                     bare query (the DAY-CARE MAN's compatibility line)
--
-- Returning 0 means "no eggs ever" and 255 means the matching-DVs sentinel;
-- both are refusals to Breeding.initBreeding, so a mod that wants a pair to
-- breed must return one of the four real values.
function Breeding.compatibility(data, mon1, mon2, opts)
  if not Runtime.wantsHook("breeding.compatibility") then
    return Breeding.vanillaCompatibility(data, mon1, mon2)
  end
  local value = Runtime.call("breeding.compatibility", function(c)
    return Breeding.vanillaCompatibility(c.data, c.mon1, c.mon2)
  end, { data = data, mon1 = mon1, mon2 = mon2,
         dayCare = (opts and opts.dayCare) == true })
  return math.max(0, math.min(255, math.floor(tonumber(value) or 0)))
end

function Breeding.vanillaCompatibility(data, mon1, mon2)
  if not (mon1 and mon2) then return 0 end
  if not Breeding.groupsCompatible(data, mon1.species, mon2.species) then
    return 0
  end

  -- The gender test: two different genders reach .compute directly.  Anything
  -- else -- either mon genderless, or both the same gender -- falls into
  -- .genderless, where only a Ditto can rescue the pair.
  local gender1 = Breeding.genderOf(data, mon1)
  local gender2 = Breeding.genderOf(data, mon2)
  local paired = gender1 ~= "unknown" and gender2 ~= "unknown"
    and gender1 ~= gender2
  if not paired then
    if mon1.species == Breeding.DITTO then
      -- .ditto1: two Dittos are the one pair that fails here.
      if mon2.species == Breeding.DITTO then return 0 end
    elseif mon2.species ~= Breeding.DITTO then
      return 0
    end
  end

  -- .compute
  if Breeding.dvsMatch(mon1, mon2) then return 255 end
  local value = (mon1.species == mon2.species) and 254 or 128
  -- .compare_ids: `sub 77` on a shared OT id, which is the cart's way of
  -- discouraging inbreeding without forbidding it.
  if otId(mon1) == otId(mon2) then value = value - 77 end
  return value
end

-- DayCareMonCompatibilityText, in the ASM's own fall-through order: the 255
-- sentinel first, then 0, then the two `jr nc` thresholds.
Breeding.COMPATIBILITY_BRIMMING = "brimming"
Breeding.COMPATIBILITY_NONE = "none"
Breeding.COMPATIBILITY_CARES = "cares"
Breeding.COMPATIBILITY_FRIENDLY = "friendly"
Breeding.COMPATIBILITY_INTEREST = "interest"

function Breeding.compatibilityText(value)
  value = value or 0
  if value == 255 then return Breeding.COMPATIBILITY_BRIMMING end
  if value == 0 then return Breeding.COMPATIBILITY_NONE end
  if value >= 230 then return Breeding.COMPATIBILITY_CARES end
  if value >= 70 then return Breeding.COMPATIBILITY_FRIENDLY end
  return Breeding.COMPATIBILITY_INTEREST
end

-- happiness_egg.asm .check_egg's ladder, with `percent` expanded the way
-- macros/data.asm defines it (`* $ff / 100`, integer division):
--   31 percent + 1 = 80,  16 percent = 40,  12 percent = 30,  4 percent = 10
-- The roll that follows is `call Random / cp b / ret nc`, so an egg appears
-- when the byte is STRICTLY under this number.
function Breeding.eggChance(value)
  value = value or 0
  if value >= 230 then return 80 end
  if value >= 170 then return 40 end
  if value >= 110 then return 30 end
  return 10
end

--------------------------------------------------------------------------
-- Which parent is the mother
--------------------------------------------------------------------------

-- wBreedMotherOrNonDitto, as a 1-based slot rather than the cart's 0/1 byte.
-- The Ditto tests come first, so a Ditto is never "the mother": the other mon
-- is, whatever its gender.  With no Ditto the test is GetGender on breedmon 1,
-- and its `jr z` catches female AND genderless (GetGender's .Genderless path
-- leaves z set from its own `cp GENDER_UNKNOWN`), so a genderless breedmon 1
-- is treated as the mother.
function Breeding.motherSlot(data, mon1, mon2)
  if not (mon1 and mon2) then return 1 end
  if mon1.species == Breeding.DITTO then return 2 end
  if mon2.species == Breeding.DITTO then return 1 end
  return Breeding.genderOf(data, mon1) == "male" and 2 or 1
end

--------------------------------------------------------------------------
-- The egg's species
--------------------------------------------------------------------------

-- GetPreEvolution: the first species in dex order whose EvosAttacks rows
-- contain an evolution INTO `species`.  Nothing about the evolution's method
-- is looked at, which is why a stone or trade evolution is walked back through
-- just as readily as a level one.
function Breeding.preEvolution(data, species)
  if not species then return nil end
  for _, id in ipairs(speciesOrder(data)) do
    local def = defOf(data, id)
    for _, evo in ipairs((def and def.evolutions) or {}) do
      if evo.into == species then return id end
    end
  end
  return nil
end

-- `callfar GetPreEvolution` TWICE, which is what walks a three-stage chain all
-- the way back (VENUSAUR -> IVYSAUR -> BULBASAUR) and leaves a two-stage one
-- alone on the second pass.  Exactly two: a hypothetical four-stage line would
-- stop one short, and that bound is the routine, not an optimisation.
function Breeding.baseForm(data, species)
  for _ = 1, 2 do
    local previous = Breeding.preEvolution(data, species)
    if not previous then break end
    species = previous
  end
  return species
end

-- The mother's base form, plus the one documented exception: "Nidoran♀ can
-- give birth to either gender of Nidoran".  `cp 50 percent + 1` is `cp 128`
-- and `jr c` keeps NIDORAN_F, so the roll is a clean half.
--
-- Returns species, motherSlot.
function Breeding.eggSpecies(data, mon1, mon2, rng)
  local slot = Breeding.motherSlot(data, mon1, mon2)
  local mother = (slot == 1) and mon1 or mon2
  local species = Breeding.baseForm(data, mother and mother.species)
  if species == Breeding.NIDORAN_F then
    species = randomByte(rng) < 128 and Breeding.NIDORAN_F
      or Breeding.NIDORAN_M
  end
  return species, slot
end

--------------------------------------------------------------------------
-- Inherited moves
--------------------------------------------------------------------------

local function moveIdAt(moves, slot)
  local entry = moves and moves[slot]
  if entry == nil then return nil end
  if type(entry) == "table" then return entry.id end
  return entry
end

-- GetHeritableMoves: the FATHER's four move slots, which is the list
-- InitEggMoves walks.
--
-- With a Ditto in the box the roles are decided by the OTHER mon's gender:
-- a male or genderless partner passes its own moves, and a FEMALE partner
-- makes the Ditto the father -- which is the famous "breed a female with Ditto
-- to pass nothing" rule, and also why a female with a Ditto passes the Ditto's
-- (empty of anything useful) moves.
--
-- .ditto2's last branch is a fall-through, not a jump: GetGender on breedmon 1
-- returning z (female) drops into .inherit_mon2_moves rather than jumping.
function Breeding.heritableMoves(data, mon1, mon2, motherSlot)
  if not (mon1 and mon2) then return {} end
  if mon1.species == Breeding.DITTO then
    return Breeding.genderOf(data, mon2) == "female" and (mon1.moves or {})
      or (mon2.moves or {})
  end
  if mon2.species == Breeding.DITTO then
    return Breeding.genderOf(data, mon1) == "female" and (mon2.moves or {})
      or (mon1.moves or {})
  end
  motherSlot = motherSlot or Breeding.motherSlot(data, mon1, mon2)
  return motherSlot == 1 and (mon2.moves or {}) or (mon1.moves or {})
end

-- GetBreedmonMovePointer: the MOTHER's four move slots -- or, when a Ditto is
-- in the box, that Ditto's, whichever side it sits on.  This is the list
-- GetEggMove's .loop2 checks a candidate against, so it is the "does the other
-- parent know it too" half of the level-up rule.
function Breeding.breedmonMoves(data, mon1, mon2, motherSlot)
  if not (mon1 and mon2) then return {} end
  if mon1.species == Breeding.DITTO then return mon1.moves or {} end
  if mon2.species == Breeding.DITTO then return mon2.moves or {} end
  motherSlot = motherSlot or Breeding.motherSlot(data, mon1, mon2)
  return motherSlot == 1 and (mon1.moves or {}) or (mon2.moves or {})
end

-- GetEggMove: may this move be inherited by `eggSpecies`?  Three ways in, in
-- the ASM's order, and the second one is the one people misremember:
--   1. it is an egg move of the egg species (data/pokemon/egg_moves.asm)
--   2. .reached_end -> .loop2 -> .found_eggmove: the OTHER parent knows it too
--      AND it is one of the egg species' own level-up moves
--   3. .inherit_tmhm: it is a TM/HM move the egg species can learn
-- Returns ok, reason.
function Breeding.canInheritMove(data, eggSpecies, move, otherMoves)
  local def = defOf(data, eggSpecies)
  if not (def and move) then return false end

  for _, id in ipairs(def.eggMoves or {}) do
    if id == move then return true, "eggMove" end
  end

  -- .loop2 walks all four of the other parent's slots; an empty slot is 0 and
  -- a move id is never 0, so a short moveset simply never matches.
  local shared = false
  for slot = 1, Breeding.NUM_MOVES do
    if moveIdAt(otherMoves, slot) == move then shared = true break end
  end
  if shared then
    for _, row in ipairs(def.levelMoves or {}) do
      if row.move == move then return true, "levelMove" end
    end
  end

  -- CanLearnTMHMMove against BASE_TMHM, which the extractor has already
  -- expanded into a list of move ids.
  for _, id in ipairs(def.tmhm or {}) do
    if id == move then return true, "tmhm" end
  end
  return false
end

-- LoadEggMove: into the first empty slot, or -- when all four are full --
-- shift slots 2..4 down and write the newcomer into slot 4.  The OLDEST move
-- is the one that goes, which is why a father with four heritable moves leaves
-- the baby with none of its own level-up set.
function Breeding.loadEggMove(moves, moveId, data)
  local def = data and data.moves and data.moves[moveId]
  local pp = (def and def.pp) or 0
  if #moves >= Breeding.NUM_MOVES then table.remove(moves, 1) end
  moves[#moves + 1] = { id = moveId, pp = pp, maxPp = pp }
  return moves
end

-- InitEggMoves: the father's four slots in order, stopping at the first empty
-- one, skipping anything the egg already knows, and loading whatever
-- GetEggMove approves.  Mutates and returns `moves`.
function Breeding.initEggMoves(data, eggSpecies, moves, fatherMoves, motherMoves)
  moves = moves or {}
  for slot = 1, Breeding.NUM_MOVES do
    local move = moveIdAt(fatherMoves, slot)
    -- `ld a, [de] / and a / jr z, .done`: an empty slot ends the walk, it does
    -- not skip to the next one.
    if not move then break end
    local known = false
    for _, entry in ipairs(moves) do
      if entry.id == move then known = true break end
    end
    if not known and
        Breeding.canInheritMove(data, eggSpecies, move, motherMoves) then
      Breeding.loadEggMove(moves, move, data)
    end
  end
  return moves
end

--------------------------------------------------------------------------
-- Building the egg
--------------------------------------------------------------------------

-- DayCare_InitBreeding's .UselessJump block: everything from the egg's species
-- down to its hatch counter, decided the moment the pair becomes compatible --
-- NOT when the egg finally appears.  Depositing two mons fixes the species,
-- the DVs and the moveset there and then; walking around only decides when the
-- Day-Care Man will hand it over.
--
-- opts: rng, playerName, playerId.
function Breeding.makeEgg(data, mon1, mon2, opts)
  opts = opts or {}
  local rng = opts.rng
  local species, motherSlot = Breeding.eggSpecies(data, mon1, mon2, rng)
  local def = defOf(data, species)
  if not def then return nil end
  local level = Breeding.EGG_LEVEL

  -- `predef FillMoves` with wSkipMovesBeforeLevelUp = FALSE at wCurPartyLevel
  -- = EGG_LEVEL: the base form's level-up moves at level 5, before any
  -- inheritance.
  local moves = Mon.movesAtLevel(def, level, data.moves)
  -- `farcall InitEggMoves` right after, so the father's moves push the
  -- level-up ones out rather than the other way round.
  Breeding.initEggMoves(data, species, moves,
    Breeding.heritableMoves(data, mon1, mon2, motherSlot),
    Breeding.breedmonMoves(data, mon1, mon2, motherSlot))

  -- Two `call Random` bytes, laid out the way the DV word is: byte 0 is
  -- Attack<<4 | Defense, byte 1 is Speed<<4 | Special.
  local byte0, byte1 = randomByte(rng), randomByte(rng)
  local dvs = {
    attack = math.floor(byte0 / 16), defense = byte0 % 16,
    speed = math.floor(byte1 / 16), special = byte1 % 16,
  }

  -- Which parent's DVs bleed through.  The Ditto tests come FIRST, before the
  -- gender branch, so a Ditto always donates -- even to a genderless egg,
  -- which would otherwise take the .SkipDVs exit and keep everything it rolled.
  local source
  if mon1.species == Breeding.DITTO then
    source = mon1
  elseif mon2.species == Breeding.DITTO then
    source = mon2
  else
    -- GetGender with TEMPMON on the DVs just rolled, i.e. the EGG's own
    -- gender, against the EGG's species ratio.
    local gender = Breeding.gender(def, dvs)
    local mother = (motherSlot == 1) and mon1 or mon2
    local father = (motherSlot == 1) and mon2 or mon1
    if gender == "male" then
      source = mother
    elseif gender == "female" then
      source = father
    end
    -- "unknown" is .SkipDVs: source stays nil and every rolled DV survives.
  end

  if source then
    local parent = source.dvs or {}
    -- `ld a, [de] / and $f` then `ld a, [hl] / and $f0 / add b`: the whole
    -- Defense nibble is replaced and the rolled Attack nibble is kept.
    dvs.defense = (parent.defense or 0) % 16
    -- `and $7` of the parent against `and $f8` of the roll: only the LOW THREE
    -- BITS of Special are inherited, so the egg keeps bit 3 of its own roll.
    dvs.special = dvs.special - (dvs.special % 8) + ((parent.special or 0) % 8)
  end
  dvs.hp = Mon.hpDV(dvs)

  -- The one builder.  hp = 0 is DayCare_GiveEgg's `ld hl, MON_HP / xor a /
  -- ld [hli], a / ld [hl], a`: an egg is carried at zero HP and cannot fight.
  local egg = Mon.new(data, species, level, {
    dvs = dvs,
    moves = moves,
    hp = 0,
    nickname = Breeding.EGG_NAME,
    happiness = Breeding.HATCH_HAPPINESS,
  })
  if not egg then return nil end
  -- `callfar CalcExpAtLevel` at wCurPartyLevel; Mon.new already writes exactly
  -- this, spelled out because the cart does it as its own step.
  egg.experience = Mon.experienceForLevel(growthOf(data, def), level)
  egg.isEgg = true
  -- wEggMonHappiness doubles as the hatch counter while the thing is an egg
  -- (`ld a, [wBaseEggSteps] / ld [hli], a`), and only becomes happiness when
  -- HatchEggs writes $78 over it.  The port keeps the two apart so `happiness`
  -- never means two things at once.
  egg.eggSteps = def.eggSteps or 0
  -- wEggMonOT / wEggMonID: the player is always an egg's original trainer.
  egg.ot = opts.playerName
  egg.otId = opts.playerId
  return egg
end

--------------------------------------------------------------------------
-- The day-care record
--------------------------------------------------------------------------

-- The three ENGINE_* ids that are literal bits of the two day-care bytes:
-- data/events/engine_flags.asm's table maps them to wDayCareMan's
-- DAYCAREMAN_HAS_EGG_F and DAYCAREMAN_HAS_MON_F and to wDayCareLady's
-- DAYCARELADY_HAS_MON_F, and constants/engine_flags.asm numbers them 5, 6 and
-- 7 (the pokegear block is 0..4).  They are NOT a save flag byte of their own:
-- checkflag/setflag on any of these three reads or writes the day-care record
-- below, which is why the DayCare and ROUTE_34 object callbacks see the yard
-- mons and the gramps outside the moment a mon is deposited or an egg is due.
Breeding.ENGINE_DAY_CARE_MAN_HAS_EGG = 5
Breeding.ENGINE_DAY_CARE_MAN_HAS_MON = 6
Breeding.ENGINE_DAY_CARE_LADY_HAS_MON = 7

-- save.dayCare, created on demand the way Boxes.box creates a box.
--   man / lady  { mon = <party record>, introSeen = bool }
--   compatible  DAYCAREMAN_MONS_COMPATIBLE_F
--   hasEgg      DAYCAREMAN_HAS_EGG_F  (ENGINE_DAY_CARE_MAN_HAS_EGG)
--   stepsToEgg  wStepsToEgg
--   egg         wEggMon, built at DayCare_InitBreeding time
function Breeding.dayCare(save)
  if type(save) ~= "table" then return nil end
  save.dayCare = save.dayCare or {}
  local dc = save.dayCare
  dc.man = dc.man or {}
  dc.lady = dc.lady or {}
  dc.compatible = dc.compatible or false
  dc.hasEgg = dc.hasEgg or false
  dc.stepsToEgg = dc.stepsToEgg or 0
  return dc
end

function Breeding.side(save, which)
  local dc = Breeding.dayCare(save)
  if not dc then return nil end
  return dc[which == "lady" and "lady" or "man"]
end

-- DAYCARE_INTRO_SEEN_F, bit 7 of each side's own byte.  DayCareIntroText tests
-- it, sets it, and `inc a` picks the LONGER "do you know about EGGS?" script
-- the first time round -- so the egg explanation is the intro you get once,
-- not a line about an egg you are owed.
function Breeding.takeIntro(save, which)
  local slot = Breeding.side(save, which)
  if not slot then return false end
  if slot.introSeen then return false end
  slot.introSeen = true
  return true
end

--------------------------------------------------------------------------
-- Deposit
--------------------------------------------------------------------------

-- CheckCurPartyMonFainted (engine/pokemon/bills_pc_top.asm), despite its name:
-- it walks the party SKIPPING wCurPartyMon and returns "ok" the moment it
-- finds any other slot with HP left.  The mon being given away is not tested
-- at all, so handing over your only healthy mon is what it blocks, not handing
-- over a fainted one.
function Breeding.hasAnotherHealthyMon(party, partyIndex)
  for index, mon in ipairs(party or {}) do
    if index ~= partyIndex and (mon.hp or 0) > 0 then return true end
  end
  return false
end

-- DayCareAskDepositPokemon's refusals, in the order it makes them.  The keys
-- are the DAYCARETEXT_* constants they map to; DayCareMenu turns them into the
-- transcribed lines.
Breeding.REFUSE_LAST_MON = "lastMon"
Breeding.REFUSE_EGG = "cantAcceptEgg"
Breeding.REFUSE_LAST_ALIVE = "lastAliveMon"
Breeding.REFUSE_MAIL = "removeMail"
Breeding.REFUSE_PARTY_FULL = "partyFull"
Breeding.REFUSE_NO_MONEY = "notEnoughMoney"
Breeding.REFUSE_OCCUPIED = "occupied"
Breeding.REFUSE_NO_MON = "noMon"

-- `ld a, [wPartyCount] / cp 2 / jr c, .OnlyOneMon` -- checked BEFORE the party
-- menu opens, so a lone mon never even gets a list to pick from.
function Breeding.canOpenDeposit(save)
  local party = (save and save.party) or {}
  if #party < 2 then return false, Breeding.REFUSE_LAST_MON end
  return true
end

-- ItemIsMail (engine/pokemon/mail_2.asm), which is a search of the ten-entry
-- MailItems list and nothing else.  This used to guess from the item id's
-- spelling, which missed LITEBLUEMAIL and PORTRAITMAIL -- neither ends in
-- "_MAIL" -- so the Day-Care would happily take a mon carrying either.  `data`
-- stays in the signature because every call site passes it.
function Breeding.holdsMail(_data, mon)
  return Mail.monHoldsMail(mon)
end

function Breeding.canDeposit(data, save, which, partyIndex)
  local slot = Breeding.side(save, which)
  if not slot then return false, Breeding.REFUSE_NO_MON end
  if slot.mon then return false, Breeding.REFUSE_OCCUPIED end
  local ok, reason = Breeding.canOpenDeposit(save)
  if not ok then return false, reason end
  local mon = save.party[partyIndex]
  if not mon then return false, Breeding.REFUSE_NO_MON end
  if Breeding.isEgg(mon) then return false, Breeding.REFUSE_EGG end
  if not Breeding.hasAnotherHealthyMon(save.party, partyIndex) then
    return false, Breeding.REFUSE_LAST_ALIVE
  end
  if Breeding.holdsMail(data, mon) then return false, Breeding.REFUSE_MAIL end
  return true
end

-- DepositBreedmon + RemoveMonFromPartyOrBox, then DayCare_InitBreeding.  The
-- mon's `level` is frozen here on purpose: wBreedMon1Level is the box struct's
-- MON_LEVEL and DayCareStep only ever raises MON_EXP, which is what makes
-- GetBreedMon1LevelGrowth's subtraction mean anything.
--
-- Returns ok, mon (or false, reason).
function Breeding.deposit(data, save, which, partyIndex, opts)
  local ok, reason = Breeding.canDeposit(data, save, which, partyIndex)
  if not ok then return false, reason end
  local slot = Breeding.side(save, which)
  local mon = table.remove(save.party, partyIndex)
  -- RemoveMonFromPartyOrBox's mail shift: sPartyMail is keyed by party slot,
  -- so a letter behind the deposited mon moves up with its owner.
  Mail.removeSlot(save, partyIndex)
  slot.mon = mon
  Breeding.initBreeding(data, save, opts)
  return true, mon
end

--------------------------------------------------------------------------
-- Withdraw
--------------------------------------------------------------------------

-- GetBreedMon1LevelGrowth: CalcLevel from the exp the mon has NOW against the
-- level it was deposited at.  Returns storedLevel, newLevel, grown.
function Breeding.levelGrowth(data, slot)
  local mon = slot and slot.mon
  if not mon then return 0, 0, 0 end
  local stored = mon.level or 1
  local def = defOf(data, mon.species)
  local newLevel = Mon.levelForExperience(growthOf(data, def),
    mon.experience or 0)
  if newLevel < stored then newLevel = stored end
  return stored, newLevel, newLevel - stored
end

-- GetPriceToRetrieveBreedmon: `AddNTimes` of 100 by the number of levels
-- grown, plus a flat 100.  A mon that grew nothing still costs ¥100, which is
-- the number _BackAlreadyText spells out.
function Breeding.retrievePrice(grown)
  return Breeding.WITHDRAW_FEE_PER_LEVEL * math.max(0, grown or 0)
    + Breeding.WITHDRAW_FEE
end

-- DayCare_AskWithdrawBreedMon's two gates, after the yes/no boxes: the money
-- first, then the party space.
function Breeding.canWithdraw(data, save, which)
  local slot = Breeding.side(save, which)
  if not (slot and slot.mon) then return false, Breeding.REFUSE_NO_MON end
  local _, _, grown = Breeding.levelGrowth(data, slot)
  local price = Breeding.retrievePrice(grown)
  local money = (save.player and save.player.money) or 0
  if money < price then return false, Breeding.REFUSE_NO_MONEY, price end
  if #(save.party or {}) >= Breeding.PARTY_SIZE then
    return false, Breeding.REFUSE_PARTY_FULL, price
  end
  return true, nil, price
end

-- FillMoves with wSkipMovesBeforeLevelUp = TRUE: only the level-up moves in
-- (prevLevel, newLevel] are learned, each into the first empty slot or -- once
-- all four are full -- over the oldest, which is ShiftMoves.  This is the same
-- shape LoadEggMove has, and it is why a mon left in the Day-Care for thirty
-- levels comes out with a completely replaced moveset.
function Breeding.learnMovesFromDayCare(data, mon, fromLevel, toLevel)
  local def = defOf(data, mon and mon.species)
  mon.moves = mon.moves or {}
  for _, row in ipairs((def and def.levelMoves) or {}) do
    if row.level > fromLevel and row.level <= toLevel then
      local known = false
      for _, entry in ipairs(mon.moves) do
        if entry.id == row.move then known = true break end
      end
      if not known then Breeding.loadEggMove(mon.moves, row.move, data) end
    end
  end
  return mon.moves
end

-- RetrieveBreedmon.  Level jumps to the one the exp bought, stats are
-- recalculated through the one builder, the moves between the two levels are
-- learned, HealPartyMon refills everything, and then -- this is the bug the
-- ASM flags in move_mon.asm -- CalcExpAtLevel OVERWRITES the exp with the
-- minimum for the new level, so every point past that threshold is thrown
-- away.  Transcribed, bug included.
--
-- Returns ok, mon, price (or false, reason).
function Breeding.withdraw(data, save, which)
  local ok, reason, price = Breeding.canWithdraw(data, save, which)
  if not ok then return false, reason, price end
  local slot = Breeding.side(save, which)
  local stored, newLevel = Breeding.levelGrowth(data, slot)
  local mon = slot.mon
  local def = defOf(data, mon.species)

  local rebuilt = Mon.new(data, mon.species, newLevel, {
    dvs = mon.dvs,
    moves = mon.moves,
    item = mon.item,
    happiness = mon.happiness,
    nickname = mon.nickname,
  })
  if not rebuilt then return false, Breeding.REFUSE_NO_MON end
  Breeding.learnMovesFromDayCare(data, rebuilt, stored, newLevel)
  -- HealPartyMon: full HP, full PP, no status.
  rebuilt.hp = rebuilt.maxHp
  rebuilt.status = nil
  for _, move in ipairs(rebuilt.moves) do move.pp = move.maxPp end
  rebuilt.caughtLevel = mon.caughtLevel or rebuilt.caughtLevel
  -- RetrieveBreedmon copies the stored struct back whole, MON_CAUGHTDATA
  -- included -- engine/pokemon/move_mon.asm:805.
  rebuilt.caughtTime = mon.caughtTime
  rebuilt.caughtLocation = mon.caughtLocation
  rebuilt.caughtByGender = mon.caughtByGender
  rebuilt.ot, rebuilt.otId = mon.ot, mon.otId
  -- CalcExpAtLevel, which is the experience loss.
  rebuilt.experience = Mon.experienceForLevel(growthOf(data, def), newLevel)

  save.player = save.player or {}
  save.player.money = math.max(0, (save.player.money or 0) - price)
  save.party = save.party or {}
  save.party[#save.party + 1] = rebuilt
  slot.mon = nil

  -- Both withdrawal paths clear MONS_COMPATIBLE_F: the man's also clears his
  -- own HAS_MON, the lady's reaches across to the man's byte to clear the
  -- shared compatibility bit.  HAS_EGG is deliberately NOT cleared -- an egg
  -- already earned survives taking a parent home.
  local dc = Breeding.dayCare(save)
  dc.compatible = false
  return true, rebuilt, price
end

--------------------------------------------------------------------------
-- Starting a clutch
--------------------------------------------------------------------------

-- DayCare_InitBreeding.  Runs after every deposit and after every egg is
-- collected; returns early unless both sides are occupied.
--
-- `and a / ret z` throws out compatibility 0, and `inc a / ret z` throws out
-- 255 -- the matching-DVs sentinel.  Only then is MONS_COMPATIBLE_F set, the
-- countdown seeded and the egg itself built.
function Breeding.initBreeding(data, save, opts)
  opts = opts or {}
  local dc = Breeding.dayCare(save)
  if not (dc and dc.man.mon and dc.lady.mon) then return false end
  local value = Breeding.compatibility(data, dc.man.mon, dc.lady.mon,
    { dayCare = true })
  if value == 0 then return false end
  if value == 255 then return false end
  dc.compatible = true
  local steps
  repeat steps = randomByte(opts.rng) until steps >= Breeding.MIN_STEPS_TO_EGG
  dc.stepsToEgg = steps
  dc.egg = Breeding.makeEgg(data, dc.man.mon, dc.lady.mon, {
    rng = opts.rng,
    playerName = opts.playerName
      or (save.player and save.player.name),
    playerId = opts.playerId or (save.player and save.player.id),
  })
  -- breeding.egg_created, a Gen 2 invention.  It fires HERE and not when the
  -- Day-Care Man hands the egg over, because .UselessJump is where the record
  -- is decided: species, DVs, inherited moves and hatch counter are all fixed
  -- the moment the pair becomes compatible, and Breeding.collectEgg only moves
  -- that same table into the party.  A mod that wants to edit an egg has to be
  -- here; by collection time the answer is already written.
  --
  --   egg          the record just built (nil if makeEgg refused the pair)
  --   mother/father  the two day-care records, resolved through motherSlot so
  --                  the names mean what they say rather than "man's side"
  --   compatibility  wBreedingCompatibility, the value that let this run
  --   stepsToEgg     wStepsToEgg, the countdown this egg is waiting out
  if Runtime.wants("breeding.egg_created") then
    local motherSlot = Breeding.motherSlot(data, dc.man.mon, dc.lady.mon)
    Runtime.emit("breeding.egg_created", {
      egg = dc.egg,
      mother = (motherSlot == 1) and dc.man.mon or dc.lady.mon,
      father = (motherSlot == 1) and dc.lady.mon or dc.man.mon,
      compatibility = value,
      stepsToEgg = dc.stepsToEgg,
    })
  end
  return true
end

--------------------------------------------------------------------------
-- Walking
--------------------------------------------------------------------------

-- DayCareStep's first half: +1 experience per step for each deposited mon, up
-- to the $50ffff ceiling, and nothing at all once the mon's STORED level is
-- MAX_LEVEL (the stored level, not the grown one, so a mon deposited at 99
-- keeps earning past 100's threshold).
local function growDeposited(slot)
  local mon = slot and slot.mon
  if not mon then return end
  if (mon.level or 1) >= Breeding.MAX_LEVEL then return end
  mon.experience = math.min((mon.experience or 0) + 1,
    Breeding.MAX_DAY_CARE_EXP)
end

-- DayCareStep, in full.  Called once per overworld step.
function Breeding.dayCareStep(data, save, rng)
  local dc = Breeding.dayCare(save)
  if not dc then return false end
  growDeposited(dc.man)
  growDeposited(dc.lady)

  -- .check_egg: the countdown only runs while the pair is flagged compatible,
  -- so withdrawing either parent stops it dead.
  if not dc.compatible then return false end
  -- `dec [hl] / ret nz` on a byte: a counter already at 0 wraps to 255 rather
  -- than firing, which is why a zero rolled below costs a further 256 steps.
  dc.stepsToEgg = ((dc.stepsToEgg or 0) - 1) % 256
  if dc.stepsToEgg ~= 0 then return false end

  -- `call Random / ld [hl], a`: the NEXT countdown is a plain byte, with none
  -- of the >= 150 rejection the first one had.
  dc.stepsToEgg = randomByte(rng)
  local value = Breeding.compatibility(data, dc.man.mon, dc.lady.mon,
    { dayCare = true })
  if randomByte(rng) >= Breeding.eggChance(value) then return false end
  dc.compatible = false
  dc.hasEgg = true
  return true
end

-- DoEggStep: one tick off the FIRST egg in party order whose counter does not
-- reach zero, and a stop the moment one does.  Eggs after that one are not
-- decremented on that step at all, which is the cart's behaviour and the
-- reason two eggs never hatch on the same footfall.
function Breeding.doEggStep(save)
  for _, mon in ipairs((save and save.party) or {}) do
    if Breeding.isEgg(mon) then
      mon.eggSteps = ((mon.eggSteps or 0) - 1) % 256
      if mon.eggSteps == 0 then return true end
    end
  end
  return false
end

-- engine/overworld/events.asm's step block, in its order:
--   wStepCount++            (StepHappiness when it wraps, not modelled here)
--   at $80: DoEggStep, and a hatch SKIPS DayCareStep for that step
--   DayCareStep
-- Returns "hatch" when an egg is ready, otherwise nil.
function Breeding.step(data, save, rng)
  if type(save) ~= "table" then return nil end
  save.stepCount = ((save.stepCount or 0) + 1) % Breeding.STEP_CYCLE
  if save.stepCount == Breeding.EGG_STEP_PHASE then
    if Breeding.doEggStep(save) then return "hatch" end
  end
  Breeding.dayCareStep(data, save, rng)
  return nil
end

-- How many footfalls are still owed on an egg, for a driver or a test: the
-- counter is in 256-step cycles and the tick lands 128 steps into each one.
function Breeding.stepsToHatch(mon)
  if not Breeding.isEgg(mon) then return nil end
  return (mon.eggSteps or 0) * Breeding.STEP_CYCLE
end

--------------------------------------------------------------------------
-- Collecting and hatching
--------------------------------------------------------------------------

-- DayCareManOutside .AskGiveEgg -> DayCare_GiveEgg, then the following
-- DayCare_InitBreeding that rolls the NEXT egg.  The record handed over is the
-- one built when the pair became compatible, not one made here.
function Breeding.collectEgg(data, save, opts)
  local dc = Breeding.dayCare(save)
  if not (dc and dc.hasEgg) then return false, Breeding.REFUSE_NO_MON end
  save.party = save.party or {}
  -- `.PartyFull` sets wScriptVar to TRUE and keeps the egg for later.
  if #save.party >= Breeding.PARTY_SIZE then
    return false, Breeding.REFUSE_PARTY_FULL
  end
  local egg = dc.egg
  if not egg then return false, Breeding.REFUSE_NO_MON end
  save.party[#save.party + 1] = egg
  dc.egg = nil
  dc.hasEgg = false
  Breeding.initBreeding(data, save, opts)
  return true, egg
end

-- HatchEggs' loop condition: an egg slot whose counter has reached 0.
function Breeding.readyToHatch(save)
  local out = {}
  for index, mon in ipairs((save and save.party) or {}) do
    if Breeding.isEgg(mon) and (mon.eggSteps or 0) == 0 then
      out[#out + 1] = index
    end
  end
  return out
end

-- HatchEggs, for one slot.  The hatchling is built by Mon.new and nothing
-- else; its DVs, moves, level and experience are the egg's, its happiness is
-- $78, and MON_HP is copied straight from MON_MAXHP so it walks out at full
-- health.  A nickname of nil is the "no thanks" answer -- HatchEggs copies the
-- species name into the slot then, and the port stores that as no nickname.
--
-- Returns the new record plus a table of side effects the caller owes:
--   { species = , togepi = bool } -- SetSeenAndCaughtMon, and the
--   EVENT_TOGEPI_HATCHED flag the ASM sets by hand for exactly one species.
-- `where` is the hatch site for SetEggMonCaughtData: landmark, timeOfDay and
-- playerGender -- engine/pokemon/breeding.asm:228.
function Breeding.hatch(data, save, index, nickname, where)
  local party = (save and save.party) or {}
  local egg = party[index]
  if not Breeding.isEgg(egg) then return nil end
  local def = defOf(data, egg.species)
  if not def then return nil end

  local hatched = Mon.new(data, egg.species, egg.level or Breeding.EGG_LEVEL, {
    dvs = egg.dvs,
    moves = egg.moves,
    nickname = nickname,
    happiness = Breeding.HATCH_HAPPINESS,
  })
  if not hatched then return nil end
  hatched.experience = egg.experience
  -- `ld a, [de] / ld [hli], a` twice: HP := MaxHP.
  hatched.hp = hatched.maxHp
  hatched.ot = egg.ot or (save.player and save.player.name)
  hatched.otId = egg.otId or (save.player and save.player.id)
  hatched.caughtLevel = egg.level or Breeding.EGG_LEVEL
  -- SetEggMonCaughtData swaps wCurPartyLevel for CAUGHT_EGG_LEVEL around the
  -- shared setter -- engine/pokemon/caught_data.asm:235-246.
  if Mon.hasCaughtData(save and save.version) then
    where = where or {}
    Mon.setCaughtData(hatched, {
      level = Mon.CAUGHT_EGG_LEVEL,
      timeOfDay = where.timeOfDay,
      landmark = where.landmark,
      playerGender = where.playerGender
        or (save.player and save.player.gender),
    })
  end
  party[index] = hatched

  Breeding.markPokedex(save, egg.species)
  -- egg.hatched, a Gen 2 invention: Gen 1 has no egg, so there is no name to
  -- share and none of pokemon.caught / pokemon.received fits (nothing was
  -- caught and nothing was given).  Raised AFTER the slot is replaced and the
  -- #DEX marked, so a listener that walks the party sees the hatchling rather
  -- than the egg it grew out of.
  --
  --   mon       the hatchling, the record now sitting in the party
  --   egg       the egg record it replaced, still holding the hatch counter
  --   slot      the party index, 1 based
  --   species   the species that hatched, the same id SetSeenAndCaughtMon took
  --   nickname  what the player answered the naming screen, or nil for "no"
  if Runtime.wants("egg.hatched") then
    Runtime.emit("egg.hatched", {
      mon = hatched, egg = egg, slot = index,
      species = egg.species, nickname = nickname,
    })
  end
  return hatched, {
    species = egg.species,
    togepi = egg.species == Breeding.TOGEPI,
  }
end

-- SetSeenAndCaughtMon, the same pair Evolution.markPokedex sets: a hatchling
-- is in the party, so it is both.
function Breeding.markPokedex(save, species)
  if not (save and species) then return false end
  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.caught = save.pokedex.caught or {}
  save.pokedex.seen[species] = true
  save.pokedex.caught[species] = true
  return true
end

return Breeding
