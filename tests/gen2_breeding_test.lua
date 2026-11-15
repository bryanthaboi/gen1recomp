-- Gen 2 Day-Care, breeding and eggs: the compatibility matrix, the egg species
-- walk, DV and move inheritance from a seeded roll, the step counters, the fee,
-- and the conversation that drives all of it.
--   GOLD_CACHE="$HOME/Library/Application Support/LOVE/gold-dev/gold" \
--     luajit tests/gen2_breeding_test.lua
--
-- The fixtures below are the shapes data/generated/pokemon.lua writes, with
-- every number traceable to pokegold so a failure names the ASM it disagrees
-- with.  The last block re-runs the species questions against a real Gold cache
-- when one is present, and skips when it is not.
--
-- Every roll is scripted: `call Random` yields one byte and Breeding takes its
-- source as a parameter, so each assertion below names the exact bytes the
-- cart would have drawn rather than hoping a seed lands somewhere useful.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 breeding")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Breeding = require("src.core.gen2.Breeding")
local Mon = require("src.battle.gen2.Mon")

-- ---- fixtures -------------------------------------------------------------

-- GROWTH_MEDIUM_FAST is plain n^3 (data/growth_rates.asm), which keeps every
-- experience number below readable: level 10 is 1000, level 12 is 1728.
local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

-- constants/pokemon_data_constants.asm's gender ratios, as the byte BaseData
-- carries.  GENDER_F100 is `100 percent - 1` = 254 and GENDER_UNKNOWN is -1.
local F0, F12_5, F50, F100, UNKNOWN = 0, 31, 127, 254, 255

local POKEMON = { growthRates = GROWTH }
local nextIndex = 0

local function species(id, opts)
  opts = opts or {}
  nextIndex = nextIndex + 1
  POKEMON[id] = {
    id = id, index = nextIndex, dex = nextIndex, name = id,
    baseStats = { hp = 45, attack = 49, defense = 49, speed = 45,
      specialAttack = 65, specialDefense = 65 },
    types = { "NORMAL", "NORMAL" },
    growthRate = "GROWTH_MEDIUM_FAST",
    genderRatio = opts.genderRatio or F50,
    eggGroups = opts.eggGroups or { "EGG_GROUND", "EGG_GROUND" },
    eggGroupsRaw = opts.eggGroupsRaw,
    eggSteps = opts.eggSteps or 20,
    evolutions = opts.evolutions or {},
    levelMoves = opts.levelMoves or { { level = 1, move = "TACKLE" } },
    tmhm = opts.tmhm or {},
    eggMoves = opts.eggMoves or {},
  }
  return POKEMON[id]
end

-- Declared in dex order, because GetPreEvolution takes the FIRST species that
-- evolves into its target and that tie-break is the table's ordering.
local BULBA_MOVES = {
  { level = 1, move = "TACKLE" },
  { level = 4, move = "GROWL" },
  { level = 7, move = "LEECH_SEED" },
  { level = 10, move = "VINE_WHIP" },
  { level = 12, move = "RAZOR_LEAF" },
}
species("BULBASAUR", { genderRatio = F12_5,
  eggGroups = { "EGG_MONSTER", "EGG_PLANT" }, eggGroupsRaw = 0x17,
  eggSteps = 20, levelMoves = BULBA_MOVES,
  eggMoves = { "LIGHT_SCREEN", "SKULL_BASH" }, tmhm = { "HEADBUTT", "TOXIC" },
  evolutions = { { method = "EVOLVE_LEVEL", level = 16, into = "IVYSAUR" } } })
species("IVYSAUR", { genderRatio = F12_5,
  eggGroups = { "EGG_MONSTER", "EGG_PLANT" }, eggGroupsRaw = 0x17,
  levelMoves = BULBA_MOVES,
  evolutions = { { method = "EVOLVE_LEVEL", level = 32, into = "VENUSAUR" } } })
species("VENUSAUR", { genderRatio = F12_5,
  eggGroups = { "EGG_MONSTER", "EGG_PLANT" }, eggGroupsRaw = 0x17,
  levelMoves = BULBA_MOVES })

-- The Nidoran lines: NIDORAN_F is female-only, NIDORAN_M male-only, and the
-- female line is the one DayCare_InitBreeding names outright.
species("NIDORAN_F", { genderRatio = F100,
  eggGroups = { "EGG_MONSTER", "EGG_GROUND" }, eggGroupsRaw = 0x15,
  evolutions = { { method = "EVOLVE_LEVEL", level = 16, into = "NIDORINA" } } })
species("NIDORINA", { genderRatio = F100,
  eggGroups = { "EGG_NONE", "EGG_NONE" }, eggGroupsRaw = 0xff,
  evolutions = { { method = "EVOLVE_ITEM", item = "MOON_STONE",
    into = "NIDOQUEEN" } } })
species("NIDOQUEEN", { genderRatio = F100,
  eggGroups = { "EGG_NONE", "EGG_NONE" }, eggGroupsRaw = 0xff })
species("NIDORAN_M", { genderRatio = F0,
  eggGroups = { "EGG_MONSTER", "EGG_GROUND" }, eggGroupsRaw = 0x15 })

-- A three-stage chain that is not Nidoran, for the plain double-walk.
species("PICHU", { genderRatio = F50,
  eggGroups = { "EGG_NONE", "EGG_NONE" }, eggGroupsRaw = 0xff })
species("PIKACHU", { genderRatio = F50,
  eggGroups = { "EGG_GROUND", "EGG_FAIRY" }, eggGroupsRaw = 0x56,
  evolutions = { { method = "EVOLVE_ITEM", item = "THUNDERSTONE",
    into = "RAICHU" } } })
species("RAICHU", { genderRatio = F50,
  eggGroups = { "EGG_GROUND", "EGG_FAIRY" }, eggGroupsRaw = 0x56 })
POKEMON.PICHU.evolutions = { { method = "EVOLVE_HAPPINESS", into = "PIKACHU" } }

-- TYROGUE is male-only and evolves three ways, so every Hitmon walks back to
-- it in ONE step -- and can only ever breed with a Ditto.
species("TYROGUE", { genderRatio = F0,
  eggGroups = { "EGG_NONE", "EGG_NONE" }, eggGroupsRaw = 0xff,
  evolutions = {
    { method = "EVOLVE_STAT", level = 20, comparison = "ATK_GT_DEF",
      into = "HITMONLEE" },
    { method = "EVOLVE_STAT", level = 20, comparison = "ATK_EQ_DEF",
      into = "HITMONTOP" } } })
species("HITMONLEE", { genderRatio = F0,
  eggGroups = { "EGG_HUMANSHAPE", "EGG_HUMANSHAPE" }, eggGroupsRaw = 0x88 })
species("HITMONTOP", { genderRatio = F0,
  eggGroups = { "EGG_HUMANSHAPE", "EGG_HUMANSHAPE" }, eggGroupsRaw = 0x88 })

species("DITTO", { genderRatio = UNKNOWN,
  eggGroups = { "EGG_DITTO", "EGG_DITTO" }, eggGroupsRaw = 0xdd })
species("MAGNEMITE", { genderRatio = UNKNOWN,
  eggGroups = { "EGG_MINERAL", "EGG_MINERAL" }, eggGroupsRaw = 0xaa,
  eggSteps = 20 })
species("GEODUDE", { genderRatio = F50,
  eggGroups = { "EGG_MINERAL", "EGG_MINERAL" }, eggGroupsRaw = 0xaa })
-- EGG_NONE in BOTH nibbles ($ff) is the No-Eggs group.
species("ARTICUNO", { genderRatio = UNKNOWN,
  eggGroups = { "EGG_NONE", "EGG_NONE" }, eggGroupsRaw = 0xff })

local MOVES = {}
for _, id in ipairs({ "TACKLE", "GROWL", "LEECH_SEED", "VINE_WHIP",
    "RAZOR_LEAF", "LIGHT_SCREEN", "SKULL_BASH", "HEADBUTT", "TOXIC",
    "FISSURE", "THUNDERSHOCK" }) do
  MOVES[id] = { id = id, name = id, pp = 20 }
end

local DATA = { pokemon = POKEMON, moves = MOVES,
  items = { FLOWER_MAIL = { id = "FLOWER_MAIL", isMail = true },
            POTION = { id = "POTION" } } }

-- ---- helpers --------------------------------------------------------------

local function dv(attack, defense, speed, special)
  return { attack = attack, defense = defense, speed = speed,
    special = special }
end

local function mon(id, opts)
  opts = opts or {}
  local moves
  if opts.moves then
    moves = {}
    for i, move in ipairs(opts.moves) do
      moves[i] = { id = move, pp = 20, maxPp = 20 }
    end
  end
  local built = Mon.new(DATA, id, opts.level or 10, {
    dvs = opts.dvs or dv(5, 5, 5, 5),
    moves = moves,
    nickname = opts.nickname,
    item = opts.item,
  })
  built.otId = opts.otId
  if opts.hp then built.hp = opts.hp end
  if opts.experience then built.experience = opts.experience end
  return built
end

-- `call Random` as a scripted byte list, cycling so a rejection sample cannot
-- run off the end of the fixture.
local function rolls(...)
  local list = { ... }
  local index = 0
  return function()
    index = index % #list + 1
    return list[index]
  end
end

-- Two DV shapes that read the same under BOTH the port's Mon.gender and
-- GetGender's own `attackDV * 16 + speedDV` comparison, so nothing below
-- depends on the rounding difference between them.
local FEMALE_DVS = dv(0, 3, 5, 2)   -- attack 0: female for F12_5 and F100
local MALE_DVS = dv(15, 7, 5, 9)    -- attack 15: male for F12_5 and F50

local function newSave(party, money)
  return { party = party or {}, player = { name = "GOLD", id = 1234,
    money = money or 3000 }, pokedex = { seen = {}, caught = {} }, events = {} }
end

-- ---- constants ------------------------------------------------------------

eq(Breeding.EGG_LEVEL, 5, "EGG_LEVEL is 5")
eq(Breeding.HATCH_HAPPINESS, 120, "a hatchling starts at happiness $78")
eq(Breeding.MIN_STEPS_TO_EGG, 150, "the first countdown rejects under 150")
eq(Breeding.STEP_CYCLE, 256, "one step cycle is 256 footfalls")
eq(Breeding.EGG_STEP_PHASE, 0x80, "DoEggStep runs at wStepCount $80")
eq(Breeding.MAX_DAY_CARE_EXP, 0x50FFFF, "the exp ceiling is $50ffff")
eq(Breeding.WITHDRAW_FEE, 100, "the flat fee is 100")
eq(Breeding.PARTY_SIZE, 6, "PARTY_LENGTH is 6")

-- ---- egg groups -----------------------------------------------------------

local first, second = Breeding.eggGroups(POKEMON.BULBASAUR)
eq(first, "EGG_MONSTER", "the high nibble is the first group")
eq(second, "EGG_PLANT", "and the low nibble the second")
check(Breeding.isNoEggs(POKEMON.ARTICUNO), "$ff is the No-Eggs group")
check(not Breeding.isNoEggs(POKEMON.BULBASAUR), "BULBASAUR breeds")
-- The raw byte wins when it is there, and the names are the fixture fallback.
check(Breeding.isNoEggs({ eggGroups = { "EGG_NONE", "EGG_NONE" } }),
  "two EGG_NONE names read as No Eggs with no raw byte")
check(not Breeding.isNoEggs({ eggGroups = { "EGG_NONE", "EGG_PLANT" } }),
  "one EGG_NONE nibble is not the No-Eggs group")

-- .CheckBreedingGroupCompatibility
check(Breeding.groupsCompatible(DATA, "BULBASAUR", "VENUSAUR"),
  "two mons in the same groups are compatible")
check(not Breeding.groupsCompatible(DATA, "BULBASAUR", "GEODUDE"),
  "plant/monster shares nothing with mineral")
check(Breeding.groupsCompatible(DATA, "NIDORAN_F", "BULBASAUR"),
  "one shared group (MONSTER) is enough")
check(Breeding.groupsCompatible(DATA, "DITTO", "GEODUDE"),
  "Ditto is compatible with anything that breeds")
-- The No-Eggs refusal happens BEFORE the Ditto shortcut, which is the whole
-- reason a legendary cannot be bred with a Ditto.
check(not Breeding.groupsCompatible(DATA, "DITTO", "ARTICUNO"),
  "...but not with a No-Eggs species")
check(not Breeding.groupsCompatible(DATA, "ARTICUNO", "DITTO"),
  "and the refusal is symmetric")

-- ---- compatibility --------------------------------------------------------

local femaleBulba = mon("BULBASAUR", { dvs = FEMALE_DVS, otId = 1 })
local maleBulba = mon("BULBASAUR", { dvs = MALE_DVS, otId = 2 })
local maleVenu = mon("VENUSAUR", { dvs = MALE_DVS, otId = 2 })

eq(Breeding.genderOf(DATA, femaleBulba), "female", "attack DV 0 is female")
eq(Breeding.genderOf(DATA, maleBulba), "male", "attack DV 15 is male")

eq(Breeding.compatibility(DATA, femaleBulba, maleBulba), 254,
  "same species, different OT ids")
eq(Breeding.compatibility(DATA,
  mon("BULBASAUR", { dvs = FEMALE_DVS, otId = 7 }),
  mon("BULBASAUR", { dvs = MALE_DVS, otId = 7 })), 254 - 77,
  "same species, same OT id: 254 - 77")
eq(Breeding.compatibility(DATA, femaleBulba, maleVenu), 128,
  "different species, different OT ids")
eq(Breeding.compatibility(DATA,
  mon("BULBASAUR", { dvs = FEMALE_DVS, otId = 7 }),
  mon("VENUSAUR", { dvs = MALE_DVS, otId = 7 })), 128 - 77,
  "different species, same OT id: 128 - 77")
-- The port's records carry no OT id yet, so two home-caught mons both read
-- nil and take the same -77 the cart gives two mons with one trainer.
eq(Breeding.compatibility(DATA, mon("BULBASAUR", { dvs = FEMALE_DVS }),
  mon("VENUSAUR", { dvs = MALE_DVS })), 51,
  "two mons with no OT id are treated as one trainer's")

eq(Breeding.compatibility(DATA, femaleBulba,
  mon("BULBASAUR", { dvs = FEMALE_DVS, otId = 2 })), 0,
  "two females never breed")
eq(Breeding.compatibility(DATA, maleBulba,
  mon("VENUSAUR", { dvs = MALE_DVS, otId = 1 })), 0,
  "two males never breed")
eq(Breeding.compatibility(DATA, femaleBulba, mon("ARTICUNO")), 0,
  "a No-Eggs species never breeds")
eq(Breeding.compatibility(DATA, mon("DITTO"), mon("DITTO", { otId = 9 })), 0,
  "two Dittos are the one .genderless pair with no way out")
eq(Breeding.compatibility(DATA, mon("MAGNEMITE"),
  mon("GEODUDE", { dvs = MALE_DVS })), 0,
  "a genderless mon and a gendered one need a Ditto")
eq(Breeding.compatibility(DATA, mon("DITTO", { otId = 1, dvs = FEMALE_DVS }),
  mon("MAGNEMITE", { otId = 2, dvs = MALE_DVS })), 128,
  "a Ditto rescues a genderless partner")
eq(Breeding.compatibility(DATA, mon("MAGNEMITE", { otId = 2, dvs = MALE_DVS }),
  mon("DITTO", { otId = 1, dvs = FEMALE_DVS })), 128,
  "on either side of the box")
eq(Breeding.compatibility(DATA, mon("HITMONTOP", { dvs = MALE_DVS, otId = 1 }),
  mon("DITTO", { otId = 2 })), 128,
  "a male-only species breeds through a Ditto")

-- .CheckDVs: equal Defense DVs and equal low-3-bits of Special.  255 reads as
-- the FRIENDLIEST message and is the one value DayCare_InitBreeding refuses.
local twinA = mon("BULBASAUR", { dvs = dv(0, 3, 5, 2), otId = 1 })
local twinB = mon("BULBASAUR", { dvs = dv(15, 3, 5, 10), otId = 2 })
check(Breeding.dvsMatch(twinA, twinB), "Defense equal and Special % 8 equal")
eq(Breeding.compatibility(DATA, twinA, twinB), 255, "which is the 255 sentinel")
check(not Breeding.dvsMatch(twinA, maleBulba), "different Defense DVs do not")

-- DayCareMonCompatibilityText's fall-through order.
eq(Breeding.compatibilityText(255), Breeding.COMPATIBILITY_BRIMMING,
  "255 is 'brimming with energy'")
eq(Breeding.compatibilityText(0), Breeding.COMPATIBILITY_NONE, "0 is no interest")
eq(Breeding.compatibilityText(254), Breeding.COMPATIBILITY_CARES,
  "254 appears to care for")
eq(Breeding.compatibilityText(230), Breeding.COMPATIBILITY_CARES,
  "and 230 is the boundary")
eq(Breeding.compatibilityText(177), Breeding.COMPATIBILITY_FRIENDLY,
  "177 is friendly")
eq(Breeding.compatibilityText(70), Breeding.COMPATIBILITY_FRIENDLY,
  "and 70 is that boundary")
eq(Breeding.compatibilityText(51), Breeding.COMPATIBILITY_INTEREST,
  "51 only shows interest")

-- happiness_egg.asm's ladder, with `percent` = `* $ff / 100`.
eq(Breeding.eggChance(255), 80, "255 rolls at 31 percent + 1")
eq(Breeding.eggChance(230), 80, "230 is the top boundary")
eq(Breeding.eggChance(229), 40, "229 drops to 16 percent")
eq(Breeding.eggChance(170), 40, "170 is that boundary")
eq(Breeding.eggChance(128), 30, "128 is 12 percent")
eq(Breeding.eggChance(110), 30, "110 is that boundary")
eq(Breeding.eggChance(51), 10, "51 is the 4 percent floor")

-- ---- which parent is the mother -------------------------------------------

eq(Breeding.motherSlot(DATA, femaleBulba, maleBulba), 1,
  "a female in slot 1 is the mother")
eq(Breeding.motherSlot(DATA, maleBulba, femaleBulba), 2,
  "a male in slot 1 makes slot 2 the mother")
eq(Breeding.motherSlot(DATA, mon("DITTO"), maleBulba), 2,
  "a Ditto is never the mother: the other one is")
eq(Breeding.motherSlot(DATA, maleBulba, mon("DITTO")), 1,
  "on either side")
-- GetGender's `jr z` catches genderless as well as female.
eq(Breeding.motherSlot(DATA, mon("MAGNEMITE"), maleBulba), 1,
  "a genderless mon in slot 1 is treated as the mother")

-- ---- the egg's species ----------------------------------------------------

eq(Breeding.preEvolution(DATA, "IVYSAUR"), "BULBASAUR", "one step back")
eq(Breeding.preEvolution(DATA, "BULBASAUR"), nil, "a base form has none")
eq(Breeding.baseForm(DATA, "VENUSAUR"), "BULBASAUR",
  "two GetPreEvolution calls walk a three-stage chain to its base")
eq(Breeding.baseForm(DATA, "IVYSAUR"), "BULBASAUR", "and a two-stage one")
eq(Breeding.baseForm(DATA, "BULBASAUR"), "BULBASAUR", "a base form stays put")
eq(Breeding.baseForm(DATA, "RAICHU"), "PICHU",
  "a happiness/stone chain walks back just as far as a level one")
eq(Breeding.baseForm(DATA, "NIDOQUEEN"), "NIDORAN_F",
  "NIDOQUEEN walks back to NIDORAN_F")
-- EVOLVE_STAT's extra parameter does not change the walk: every Hitmon has
-- exactly one pre-evolution and it is one step away.
eq(Breeding.baseForm(DATA, "HITMONTOP"), "TYROGUE", "HITMONTOP is a TYROGUE egg")
eq(Breeding.baseForm(DATA, "HITMONLEE"), "TYROGUE", "so is HITMONLEE")

-- The mother decides, not the father.
eq(select(1, Breeding.eggSpecies(DATA,
  mon("VENUSAUR", { dvs = FEMALE_DVS }), mon("PIKACHU", { dvs = MALE_DVS }),
  rolls(0))), "BULBASAUR", "the egg is the MOTHER's base form")
eq(select(1, Breeding.eggSpecies(DATA,
  mon("PIKACHU", { dvs = MALE_DVS }), mon("VENUSAUR", { dvs = FEMALE_DVS }),
  rolls(0))), "BULBASAUR", "whichever side of the box she is on")
-- With a Ditto the non-Ditto is the mother whatever its gender, which is how
-- a male-only line has any egg at all.
eq(select(1, Breeding.eggSpecies(DATA, mon("DITTO"),
  mon("HITMONTOP", { dvs = MALE_DVS }), rolls(0))), "TYROGUE",
  "a Ditto pairing takes the other mon's base form")

-- "Nidoran can give birth to either gender of Nidoran": `cp 50 percent + 1`
-- is `cp 128` and `jr c` keeps the female.
local nidoMother = mon("NIDORINA", { dvs = FEMALE_DVS })
local nidoFather = mon("NIDORAN_M", { dvs = MALE_DVS })
eq(select(1, Breeding.eggSpecies(DATA, nidoMother, nidoFather, rolls(127))),
  "NIDORAN_F", "a roll of 127 keeps NIDORAN_F")
eq(select(1, Breeding.eggSpecies(DATA, nidoMother, nidoFather, rolls(128))),
  "NIDORAN_M", "a roll of 128 flips to NIDORAN_M")

-- ---- inherited moves ------------------------------------------------------

local father = mon("BULBASAUR",
  { dvs = MALE_DVS, moves = { "LIGHT_SCREEN", "HEADBUTT", "FISSURE" } })
local mother = mon("BULBASAUR",
  { dvs = FEMALE_DVS, moves = { "TACKLE", "GROWL" } })

-- GetHeritableMoves: the FATHER's list.
eq(Breeding.heritableMoves(DATA, mother, father, 1)[1].id, "LIGHT_SCREEN",
  "the father's moves are the heritable ones")
eq(Breeding.heritableMoves(DATA, father, mother, 2)[1].id, "LIGHT_SCREEN",
  "from either side of the box")
-- GetBreedmonMovePointer: the MOTHER's list.
eq(Breeding.breedmonMoves(DATA, mother, father, 1)[1].id, "TACKLE",
  "the other list is the mother's")

-- A Ditto plays whichever role the partner leaves open.
local ditto = mon("DITTO", { moves = { "TRANSFORM" } })
eq(Breeding.heritableMoves(DATA, ditto, father, 2)[1].id, "LIGHT_SCREEN",
  "a MALE partner still passes its own moves past a Ditto")
eq(Breeding.heritableMoves(DATA, ditto, mother, 2)[1].id, "TRANSFORM",
  "a FEMALE partner makes the Ditto the father")
eq(Breeding.heritableMoves(DATA, mother, ditto, 1)[1].id, "TRANSFORM",
  "and .ditto2 falls through to the same answer")
eq(Breeding.heritableMoves(DATA, father, ditto, 1)[1].id, "LIGHT_SCREEN",
  "while a male partner keeps its own")
eq(Breeding.breedmonMoves(DATA, ditto, mother, 2)[1].id, "TRANSFORM",
  "the Ditto is always the other list")
eq(Breeding.breedmonMoves(DATA, mother, ditto, 1)[1].id, "TRANSFORM",
  "on either side")

-- GetEggMove's three ways in.
local motherMoves = mother.moves
eq(select(2, Breeding.canInheritMove(DATA, "BULBASAUR", "LIGHT_SCREEN",
  motherMoves)), "eggMove", "an egg move needs nothing else")
eq(select(2, Breeding.canInheritMove(DATA, "BULBASAUR", "GROWL",
  motherMoves)), "levelMove",
  "a move BOTH parents know that the baby learns by level")
check(not Breeding.canInheritMove(DATA, "BULBASAUR", "GROWL",
  { { id = "TACKLE" } }), "...but not when the mother does not know it")
check(not Breeding.canInheritMove(DATA, "BULBASAUR", "THUNDERSHOCK",
  { { id = "THUNDERSHOCK" } }),
  "...nor when the baby has no level-up row for it")
eq(select(2, Breeding.canInheritMove(DATA, "BULBASAUR", "HEADBUTT",
  motherMoves)), "tmhm", "a TM/HM the baby can learn")
check(not Breeding.canInheritMove(DATA, "BULBASAUR", "FISSURE", motherMoves),
  "and nothing else gets through")
check(not Breeding.canInheritMove(DATA, "GEODUDE", "LIGHT_SCREEN", {}),
  "a species whose eggMoves list is empty has no egg moves")
do
  local saved = POKEMON.GEODUDE.eggMoves
  POKEMON.GEODUDE.eggMoves = nil
  local ok, err = pcall(Breeding.canInheritMove, DATA, "GEODUDE",
    "LIGHT_SCREEN", {})
  POKEMON.GEODUDE.eggMoves = saved
  check(not ok and tostring(err):find("pokemon.lua has no eggMoves for GEODUDE",
    1, true), "a species with no eggMoves field is an error")
end

-- LoadEggMove: the first empty slot, or over the OLDEST once full.
local slots = { { id = "A" }, { id = "B" }, { id = "C" } }
Breeding.loadEggMove(slots, "TACKLE", DATA)
eq(#slots, 4, "a fourth move fits")
eq(slots[4].id, "TACKLE", "in the empty slot")
eq(slots[4].pp, 20, "with its PP filled")
Breeding.loadEggMove(slots, "GROWL", DATA)
eq(#slots, 4, "a fifth does not grow the list")
eq(slots[1].id, "B", "the oldest move is the one that goes")
eq(slots[4].id, "GROWL", "and the newcomer takes slot 4")

-- InitEggMoves over a real level-up base.
local eggMoves = Mon.movesAtLevel(POKEMON.BULBASAUR, Breeding.EGG_LEVEL, MOVES)
eq(#eggMoves, 2, "a level-5 BULBASAUR knows two moves")
Breeding.initEggMoves(DATA, "BULBASAUR", eggMoves, father.moves, motherMoves)
eq(#eggMoves, 4, "two of the father's three get through")
eq(eggMoves[3].id, "LIGHT_SCREEN", "the egg move")
eq(eggMoves[4].id, "HEADBUTT", "and the TM, in the father's slot order")
-- `ld a, [de] / and a / jr z, .done`: an empty slot ENDS the walk.
local stopped = {}
Breeding.initEggMoves(DATA, "BULBASAUR", stopped,
  { nil, { id = "LIGHT_SCREEN" } }, motherMoves)
eq(#stopped, 0, "an empty first slot stops the walk dead")

-- ---- building the egg -----------------------------------------------------
--
-- makeEgg spends its rolls in one order: the Nidoran coin (only for a
-- NIDORAN_F egg), then DV byte 0 (Attack<<4|Defense) and DV byte 1
-- (Speed<<4|Special).
local egg = Breeding.makeEgg(DATA, mother, father,
  { rng = rolls(0x9C, 0x35), playerName = "GOLD", playerId = 1234 })
eq(egg.species, "BULBASAUR", "the egg is the mother's base form")
eq(egg.level, 5, "an egg is level EGG_LEVEL")
eq(egg.experience, 125, "with CalcExpAtLevel's exp for it")
eq(egg.hp, 0, "and zero HP: DayCare_GiveEgg zeroes MON_HP")
check(Breeding.isEgg(egg), "it is flagged as an egg")
check(not Breeding.canFight(egg), "and cannot fight")
eq(egg.nickname, "EGG", "its nickname is the .String_EGG literal")
eq(egg.eggSteps, 20, "the hatch counter is BASE_EGG_STEPS")
eq(egg.otId, 1234, "the player is its original trainer")
-- $9c is Attack 9 / Defense 12, $35 is Speed 3 / Special 5.  Attack DV 9
-- against F12_5 is a MALE egg, so the DVs come from the MOTHER: her whole
-- Defense nibble (3) and the low three bits of her Special (2 & 7 = 2) over
-- the roll's own 5.
eq(egg.dvs.attack, 9, "Attack is the roll, untouched")
eq(egg.dvs.speed, 3, "Speed is the roll, untouched")
eq(egg.dvs.defense, 3, "Defense is the mother's, whole")
eq(egg.dvs.special, 2, "Special keeps the roll's bit 3 and takes her low 3")
eq(egg.moves[1].id, "TACKLE", "the level-5 moveset comes first")
eq(egg.moves[3].id, "LIGHT_SCREEN", "then the inherited egg move")
eq(egg.moves[4].id, "HEADBUTT", "and the inherited TM")

-- A FEMALE egg takes the FATHER's Defense and low-3 Special instead.  $0c is
-- Attack 0 / Defense 12, and Attack 0 against F12_5 is female.
local femaleEgg = Breeding.makeEgg(DATA, mother, father,
  { rng = rolls(0x0C, 0x35) })
eq(Breeding.gender(POKEMON.BULBASAUR, femaleEgg.dvs), "female",
  "attack DV 0 hatches female")
eq(femaleEgg.dvs.defense, 7, "so Defense comes from the father")
eq(femaleEgg.dvs.special, 1, "and his Special low bits (9 & 7 = 1)")

-- .SkipDVs: a genderless egg with no Ditto in the box keeps everything it
-- rolled.  (The pair itself would never be compatible -- this is the branch
-- under test, not the conversation.)
local nullEgg = Breeding.makeEgg(DATA, mon("MAGNEMITE"),
  mon("GEODUDE", { dvs = MALE_DVS }), { rng = rolls(0x9C, 0x35) })
eq(nullEgg.species, "MAGNEMITE", "a genderless mother still gives her species")
eq(nullEgg.dvs.defense, 12, "Defense is the roll: .SkipDVs inherits nothing")
eq(nullEgg.dvs.special, 5, "and so is Special")

-- ...but the Ditto tests come FIRST, so a Ditto donates even to a genderless
-- egg that would otherwise have taken .SkipDVs.
local dittoEgg = Breeding.makeEgg(DATA,
  mon("DITTO", { dvs = dv(1, 4, 1, 3) }), mon("MAGNEMITE"),
  { rng = rolls(0x9C, 0x35) })
eq(dittoEgg.species, "MAGNEMITE", "the non-Ditto is the mother")
eq(dittoEgg.dvs.defense, 4, "and the Ditto still donates Defense")
eq(dittoEgg.dvs.special, 3, "and the low three bits of Special")

-- ---- DayCare_InitBreeding -------------------------------------------------

local save = newSave()
local dc = Breeding.dayCare(save)
dc.man.mon = mother
check(not Breeding.initBreeding(DATA, save, { rng = rolls(200) }),
  "one deposited mon starts nothing")
dc.lady.mon = mon("BULBASAUR", { dvs = FEMALE_DVS, otId = 3 })
check(not Breeding.initBreeding(DATA, save, { rng = rolls(200) }),
  "two females start nothing either")
check(not dc.compatible, "and MONS_COMPATIBLE_F stays clear")
dc.lady.mon = twinB
dc.man.mon = twinA
check(not Breeding.initBreeding(DATA, save, { rng = rolls(200) }),
  "`inc a / ret z` throws out the 255 matching-DVs sentinel")

save = newSave()
dc = Breeding.dayCare(save)
dc.man.mon, dc.lady.mon = mother, father
-- The rejection sample: 10 is under 150 and is spent, 200 is taken.
check(Breeding.initBreeding(DATA, save,
  { rng = rolls(10, 200, 0x9C, 0x35) }), "a compatible pair starts breeding")
check(dc.compatible, "MONS_COMPATIBLE_F is set")
eq(dc.stepsToEgg, 200, "and the countdown rejected the roll under 150")
eq(dc.egg.species, "BULBASAUR",
  "the egg is built HERE, not when it finally appears")

-- ---- DayCareStep ----------------------------------------------------------

save = newSave()
dc = Breeding.dayCare(save)
dc.man.mon = mon("BULBASAUR", { level = 10, experience = 1000 })
dc.lady.mon = mon("VENUSAUR", { level = 10, experience = 1000 })
Breeding.dayCareStep(DATA, save)
eq(dc.man.mon.experience, 1001, "each step is one point of exp")
eq(dc.lady.mon.experience, 1001, "for both sides")
eq(dc.man.mon.level, 10, "the STORED level never moves")

dc.man.mon = mon("BULBASAUR", { level = 100, experience = 1000000 })
Breeding.dayCareStep(DATA, save)
eq(dc.man.mon.experience, 1000000, "a mon stored at MAX_LEVEL earns nothing")
dc.man.mon = mon("BULBASAUR", { level = 10, experience = 0x50FFFF })
Breeding.dayCareStep(DATA, save)
eq(dc.man.mon.experience, 0x50FFFF, "and the ceiling is $50ffff")

-- .check_egg only runs while the pair is flagged compatible.
dc.compatible = false
dc.stepsToEgg = 5
Breeding.dayCareStep(DATA, save)
eq(dc.stepsToEgg, 5, "an uncompatible pair does not count down")

save = newSave()
dc = Breeding.dayCare(save)
dc.man.mon = mon("BULBASAUR", { dvs = FEMALE_DVS, otId = 1 })
dc.lady.mon = mon("VENUSAUR", { dvs = MALE_DVS, otId = 2 })
dc.compatible = true
dc.stepsToEgg = 2
-- Their compatibility is 128 (different species, different OT), so the roll
-- has to come in under Breeding.eggChance(128) = 30.
eq(Breeding.compatibility(DATA, dc.man.mon, dc.lady.mon), 128,
  "the fixture pair is 128")
check(not Breeding.dayCareStep(DATA, save, rolls(99)),
  "the first step just decrements")
eq(dc.stepsToEgg, 1, "the countdown moved")
check(not Breeding.dayCareStep(DATA, save, rolls(77, 30)),
  "a chance byte of 30 is NOT under 30")
eq(dc.stepsToEgg, 77, "but the countdown was reseeded with a plain byte")
check(not dc.hasEgg, "and no egg was left")
dc.stepsToEgg = 1
check(Breeding.dayCareStep(DATA, save, rolls(200, 29)),
  "a chance byte of 29 IS under 30")
check(dc.hasEgg, "so DAYCAREMAN_HAS_EGG_F is set")
check(not dc.compatible, "and MONS_COMPATIBLE_F is cleared until it is taken")

-- `dec [hl]` on a zero byte wraps to 255 rather than firing.
dc.compatible = true
dc.stepsToEgg = 0
Breeding.dayCareStep(DATA, save, rolls(0))
eq(dc.stepsToEgg, 255, "a countdown at zero wraps to 255")

-- ---- DoEggStep and the step block ----------------------------------------

local function eggWith(steps)
  local e = Breeding.makeEgg(DATA, mother, father, { rng = rolls(0x9C, 0x35) })
  e.eggSteps = steps
  return e
end

save = newSave({ eggWith(3), eggWith(5) })
check(not Breeding.doEggStep(save), "neither egg is ready")
eq(save.party[1].eggSteps, 2, "the first ticked")
eq(save.party[2].eggSteps, 4, "and so did the second")

save = newSave({ eggWith(1), eggWith(5) })
check(Breeding.doEggStep(save), "the first egg reaches zero")
eq(save.party[1].eggSteps, 0, "and stops there")
eq(save.party[2].eggSteps, 5,
  "the eggs after it are not ticked on that step at all")

save = newSave({ mon("BULBASAUR"), eggWith(5) })
Breeding.doEggStep(save)
eq(save.party[2].eggSteps, 4, "a non-egg party slot is skipped, not counted")

-- engine/overworld/events.asm: wStepCount++, DoEggStep at $80, then
-- DayCareStep -- and a hatch skips DayCareStep for that step.
save = newSave({ eggWith(1) })
dc = Breeding.dayCare(save)
dc.man.mon = mon("BULBASAUR", { level = 10, experience = 1000 })
save.stepCount = 0x7E
eq(Breeding.step(DATA, save), nil, "step $7f is quiet")
eq(save.stepCount, 0x7F, "and the counter moved")
eq(dc.man.mon.experience, 1001, "DayCareStep ran")
eq(save.party[1].eggSteps, 1, "the egg did not tick")
eq(Breeding.step(DATA, save), "hatch", "step $80 ticks the egg and it hatches")
eq(save.party[1].eggSteps, 0, "the counter is spent")
eq(dc.man.mon.experience, 1001,
  "and the hatch skipped DayCareStep for that step")
-- The counter is a byte.
save.stepCount = 255
Breeding.step(DATA, save)
eq(save.stepCount, 0, "wStepCount wraps at 256")

eq(Breeding.stepsToHatch(eggWith(20)), 20 * 256,
  "twenty cycles is 5120 footfalls")
eq(Breeding.stepsToHatch(mon("BULBASAUR")), nil, "a mon has no hatch counter")

-- ---- hatching -------------------------------------------------------------

save = newSave({ eggWith(0) })
local hatched, effects = Breeding.hatch(DATA, save, 1)
check(hatched ~= nil, "the egg hatched")
check(not Breeding.isEgg(hatched), "and is no longer an egg")
eq(hatched.species, "BULBASAUR", "into its stored species")
eq(hatched.level, 5, "at level 5")
eq(hatched.happiness, 120, "with happiness $78, not BASE_HAPPINESS")
eq(hatched.hp, hatched.maxHp, "and MON_HP copied from MON_MAXHP")
eq(hatched.nickname, nil, "declining the naming screen leaves no nickname")
eq(hatched.dvs.defense, 3, "the egg's DVs came through")
eq(hatched.moves[3].id, "LIGHT_SCREEN", "and so did its inherited moves")
check(save.pokedex.seen.BULBASAUR, "SetSeenAndCaughtMon marked it seen")
check(save.pokedex.caught.BULBASAUR, "and caught")
check(not effects.togepi, "and it is not a TOGEPI")
eq(#Breeding.readyToHatch(save), 0, "nothing is left waiting")

save = newSave({ eggWith(0) })
hatched = Breeding.hatch(DATA, save, 1, "SPROUT")
eq(hatched.nickname, "SPROUT", "a nickname taken from the naming screen sticks")

-- HatchEggs writes wPlayerID / wPlayerName over whatever the egg carried, so
-- the ODD_EGG's "ODD" and its table id do not survive the hatch.
-- engine/pokemon/breeding.asm:299-309
save = newSave({ eggWith(0) })
save.party[1].ot = "ODD"
save.party[1].otId = 2048
hatched = Breeding.hatch(DATA, save, 1)
eq(hatched.ot, "GOLD", "the hatchling's OT becomes the player")
eq(hatched.otId, 1234, "and MON_OT_ID becomes wPlayerID")

eq(#Breeding.readyToHatch(newSave({ eggWith(0), eggWith(2), eggWith(0) })), 2,
  "readyToHatch names every spent counter")

-- ---- deposit --------------------------------------------------------------

save = newSave({ mon("BULBASAUR") })
check(not Breeding.canOpenDeposit(save),
  "`cp 2 / jr c` refuses before the party list even opens")
eq(select(2, Breeding.canOpenDeposit(save)), Breeding.REFUSE_LAST_MON,
  "with the OnlyOneMon line")

save = newSave({ eggWith(5), mon("BULBASAUR"), mon("VENUSAUR") })
eq(select(2, Breeding.canDeposit(DATA, save, "man", 1)),
  Breeding.REFUSE_EGG, "an egg cannot be deposited")

save = newSave({ mon("BULBASAUR"), mon("VENUSAUR", { hp = 0 }) })
eq(select(2, Breeding.canDeposit(DATA, save, "man", 1)),
  Breeding.REFUSE_LAST_ALIVE,
  "the last mon that can still battle stays with you")
check(Breeding.canDeposit(DATA, save, "man", 2),
  "but the fainted one may go: CheckCurPartyMonFainted skips the mon itself")

save = newSave({ mon("BULBASAUR", { item = "FLOWER_MAIL" }),
  mon("VENUSAUR") })
eq(select(2, Breeding.canDeposit(DATA, save, "man", 1)),
  Breeding.REFUSE_MAIL, "mail has to come off first")

save = newSave({ mother, father, mon("GEODUDE") })
local ok, deposited = Breeding.deposit(DATA, save, "man", 1,
  { rng = rolls(200, 0x9C, 0x35) })
check(ok, "the deposit went through")
eq(deposited.species, "BULBASAUR", "and handed the mon back")
eq(#save.party, 2, "the party shrank")
eq(Breeding.side(save, "man").mon.species, "BULBASAUR", "the man holds her")
check(not Breeding.dayCare(save).compatible,
  "one mon in the box starts nothing")
eq(select(2, Breeding.canDeposit(DATA, save, "man", 1)),
  Breeding.REFUSE_OCCUPIED, "and he will not take a second")
check(Breeding.deposit(DATA, save, "lady", 1,
  { rng = rolls(200, 0x9C, 0x35) }), "the lady takes the father")
check(Breeding.dayCare(save).compatible,
  "and the second deposit is what starts the clutch")
eq(Breeding.dayCare(save).stepsToEgg, 200, "with the countdown seeded")

-- DAYCARE_INTRO_SEEN_F, one bit per side.
save = newSave()
check(Breeding.takeIntro(save, "man"), "the man's intro plays once")
check(not Breeding.takeIntro(save, "man"), "and not again")
check(Breeding.takeIntro(save, "lady"), "the lady keeps her own bit")

-- ---- withdraw -------------------------------------------------------------

save = newSave({}, 500)
dc = Breeding.dayCare(save)
dc.man.mon = mon("BULBASAUR", { level = 10, experience = 1000,
  moves = { "TACKLE" } })
local stored, grown
stored, _, grown = Breeding.levelGrowth(DATA, dc.man)
eq(stored, 10, "the stored level is where it went in")
eq(grown, 0, "and it has grown nothing yet")
eq(Breeding.retrievePrice(0), 100, "a mon that grew nothing still costs 100")
eq(Breeding.retrievePrice(1), 200, "one level is 200")
eq(Breeding.retrievePrice(2), 300, "and each level after is another 100")

-- Level 12 is 1728 exp under n^3; 1900 is comfortably inside it.
dc.man.mon.experience = 1900
local newLevel
stored, newLevel, grown = Breeding.levelGrowth(DATA, dc.man)
eq(newLevel, 12, "1900 exp buys level 12")
eq(grown, 2, "which is two levels of growth")

save.player.money = 200
eq(select(2, Breeding.canWithdraw(DATA, save, "man")),
  Breeding.REFUSE_NO_MONEY, "300 is more than 200")
save.player.money = 500
save.party = {}
for _ = 1, 6 do save.party[#save.party + 1] = mon("GEODUDE") end
eq(select(2, Breeding.canWithdraw(DATA, save, "man")),
  Breeding.REFUSE_PARTY_FULL, "and a full party has nowhere to put him")

save.party = {}
dc.compatible = true
local back, price
ok, back, price = Breeding.withdraw(DATA, save, "man")
check(ok, "the withdrawal went through")
eq(price, 300, "at 100 per level plus 100")
eq(save.player.money, 200, "and the money came out")
eq(back.level, 12, "the mon comes out at the level its exp bought")
eq(#save.party, 1, "into the party")
eq(Breeding.side(save, "man").mon, nil, "and out of the box")
check(not dc.compatible,
  "either withdrawal clears the shared MONS_COMPATIBLE_F")
-- FillMoves with wSkipMovesBeforeLevelUp: only levels 11 and 12.
eq(#back.moves, 2, "one level-up move was learned on the way out")
eq(back.moves[2].id, "RAZOR_LEAF", "the one BULBASAUR learns at 12")
-- The bug move_mon.asm flags: CalcExpAtLevel overwrites the exp, so the 172
-- points above level 12's threshold are gone.
eq(back.experience, 1728,
  "and the surplus experience is thrown away (the ASM's own BUG note)")
eq(back.hp, back.maxHp, "HealPartyMon refilled it")

-- ---- collecting the egg ---------------------------------------------------

save = newSave()
dc = Breeding.dayCare(save)
eq(select(2, Breeding.collectEgg(DATA, save)), Breeding.REFUSE_NO_MON,
  "there is nothing to collect")
dc.man.mon, dc.lady.mon = mother, father
Breeding.initBreeding(DATA, save, { rng = rolls(200, 0x9C, 0x35) })
dc.hasEgg = true
dc.compatible = false
for _ = 1, 6 do save.party[#save.party + 1] = mon("GEODUDE") end
eq(select(2, Breeding.collectEgg(DATA, save)), Breeding.REFUSE_PARTY_FULL,
  "a full party leaves the egg with him")
check(dc.hasEgg, "and he keeps holding it")
save.party = {}
local taken
ok, taken = Breeding.collectEgg(DATA, save, { rng = rolls(180, 0x0C, 0x35) })
check(ok, "with room, the egg comes over")
eq(taken.species, "BULBASAUR", "and it is the one built at deposit time")
eq(#save.party, 1, "into the party")
check(not dc.hasEgg, "DAYCAREMAN_HAS_EGG_F is cleared")
-- DayCare_InitBreeding runs right after DayCare_GiveEgg, so the next egg is
-- already waiting before you have walked a step.
check(dc.compatible, "and the next clutch has already started")
eq(dc.stepsToEgg, 180, "with its own countdown")
eq(dc.egg.dvs.defense, 7, "and a freshly rolled egg behind it")

-- ---- the conversation -----------------------------------------------------
--
-- DayCareMan / DayCareLady / DayCareManOutside as a screen.  The party list is
-- replaced through the Screens registry so this stays a logic test.
local Screens = require("src.ui.Screens")
local DayCareMenu = require("src.ui.gen2.DayCareMenu")
local DC_TEXT = require("tests.fixtures.gen2_common_text").text()
local DC_REF = DayCareMenu.new(nil,
  { save = { daycare = {} }, side = "man", text = DC_TEXT }).TEXT

local function newInput()
  local input = { pressed = {} }
  function input:press(...)
    for _, button in ipairs({ ... }) do self.pressed[button] = true end
  end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

local partyChoice
Screens.invalidate()
local screenData = { pokemon = POKEMON, moves = MOVES, items = DATA.items,
  audio = {}, screens = {
    Gen2PartyMenu = { new = function(_, opts)
      partyChoice = opts
      return { stub = true }
    end },
  } }

local function newGame(gameSave)
  local input = newInput()
  return {
    input = input,
    save = gameSave,
    data = screenData,
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end },
  }, input
end

-- Press A until the screen stops asking, so a page count never has to be
-- hard-coded here (the strings' own shapes are asserted by reading TEXT).
-- ../pokecrystal/home/print_text.asm:1
local function settle(screen)
  for _ = 1, 600 do
    if not (screen.typer and not screen.typer:done()) then break end
    screen:update(0)
  end
end

local function pressA(screen, input, times)
  for _ = 1, times or 1 do
    settle(screen)
    input:press("a")
    screen:update(0)
  end
end

-- The FIRST visit gets the long "do you know about EGGS?" script, which is
-- what DayCareIntroText's `inc a` picks while DAYCARE_INTRO_SEEN_F is clear.
local depositSave = newSave({ mother, father, mon("GEODUDE") })
local depositGame, depositInput = newGame(depositSave)
local screen = DayCareMenu.new(depositGame, { text = DC_TEXT, save = depositSave,
  side = "man", rng = rolls(200, 0x9C, 0x35) })
eq(#screen.confirm.pages, #DC_REF.manIntroEgg,
  "the first visit is the long egg explanation")
check(Breeding.side(depositSave, "man").introSeen,
  "and DAYCARE_INTRO_SEEN_F is set by showing it")
-- Walk to the last page, where the YES/NO box comes up, then answer YES.
pressA(screen, depositInput, #DC_REF.manIntroEgg - 1)
eq(screen.confirm.choice, 1, "the box opens on YES")
pressA(screen, depositInput, 1)
check(screen.message ~= nil, "YES asks which mon to raise")
pressA(screen, depositInput, 1)
check(screen.picking, "and then opens the party list")
check(partyChoice ~= nil, "through the Screens registry")
partyChoice.onChoose(1)
check(not screen.picking, "choosing pops it")
eq(#depositSave.party, 2, "and the mon went into the box")
eq(Breeding.side(depositSave, "man").mon.species, "BULBASAUR",
  "with the man")

-- Talking to him again is the withdrawal branch, and a mon that grew nothing
-- gets _BackAlreadyText rather than "Are we geniuses".
local withdrawGame, withdrawInput = newGame(depositSave)
depositSave.player.money = 500
screen = DayCareMenu.new(withdrawGame, { text = DC_TEXT, save = depositSave, side = "man" })
eq(#screen.confirm.pages, #DC_REF.backAlready("X"),
  "no growth means one yes/no over _BackAlreadyText")
pressA(screen, withdrawInput, #screen.confirm.pages - 1)
pressA(screen, withdrawInput, 1)
eq(#depositSave.party, 3, "YES takes the mon back")
eq(depositSave.player.money, 400, "at the flat ¥100")

-- A grown mon gets two yes/no boxes: "Are we geniuses" and then the price.
local grownSave = newSave({ mother, father }, 1000)
Breeding.dayCare(grownSave).man.mon = mon("BULBASAUR",
  { level = 10, experience = 1900 })
Breeding.side(grownSave, "man").introSeen = true
local grownGame, grownInput = newGame(grownSave)
screen = DayCareMenu.new(grownGame, { text = DC_TEXT, save = grownSave, side = "man" })
eq(screen.grown, 2, "two levels of growth")
eq(screen.price, 300, "and a ¥300 bill")
pressA(screen, grownInput, #DC_REF.geniuses("X"))
check(screen.confirm ~= nil, "the second question follows the first")
pressA(screen, grownInput, #DC_REF.hasGrown("X", 2, 300))
eq(grownSave.player.money, 700, "and paying takes the 300")
eq(#grownSave.party, 3, "the mon is home")

-- DayCareManOutside: "Not yet…" with no egg, and the party check AFTER the
-- yes, which is the branch that writes wScriptVar = TRUE.
local eggSave = newSave()
local eggGame, eggInput = newGame(eggSave)
screen = DayCareMenu.new(eggGame, { text = DC_TEXT, save = eggSave, side = "outside" })
eq(screen.message.pages[1][1], "Not yet…", "no egg, no conversation")

eggSave = newSave()
local eggDc = Breeding.dayCare(eggSave)
eggDc.man.mon, eggDc.lady.mon = mother, father
Breeding.initBreeding(DATA, eggSave, { rng = rolls(200, 0x9C, 0x35) })
eggDc.hasEgg = true
for _ = 1, 6 do eggSave.party[#eggSave.party + 1] = mon("GEODUDE") end
eggGame, eggInput = newGame(eggSave)
screen = DayCareMenu.new(eggGame, { text = DC_TEXT, save = eggSave, side = "outside",
  rng = rolls(200, 0x9C, 0x35) })
pressA(screen, eggInput, #DC_REF.foundAnEgg)
eq(screen.scriptVar, 1, "a full party sets wScriptVar to TRUE")
check(eggDc.hasEgg, "and he keeps the egg")

eggSave.party = {}
eggGame, eggInput = newGame(eggSave)
screen = DayCareMenu.new(eggGame, { text = DC_TEXT, save = eggSave, side = "outside",
  rng = rolls(200, 0x9C, 0x35) })
pressA(screen, eggInput, #DC_REF.foundAnEgg)
eq(#eggSave.party, 1, "with room, the egg is handed over")
check(Breeding.isEgg(eggSave.party[1]), "as an egg")
eq(screen.scriptVar, 0, "and wScriptVar stays FALSE")
-- _ReceivedEggText, then SFX_GET_EGG and `ld c, 120 / call DelayFrames`
-- before _TakeGoodCareOfEggText: the pause is between the two lines, so it
-- only starts once the first one has been dismissed.
eq(screen.delay, 0, "the pause has not started while he is still talking")
pressA(screen, eggInput, 1)
eq(screen.delay, 120, "and then it is the 120 frames of the jingle")

screenData.screens = nil
Screens.invalidate()

-- The conversation is `opentext` and nothing more: maps/DayCare.asm's two NPC
-- scripts run `special DayCareMan` / `special DayCareLady`, and neither the
-- special nor PrintDayCareText nor YesNoBox blanks the screen, so the Day-Care
-- room stays drawn behind the textbox.  An opaque or widescreen screen would
-- take Game2:drawScene's own-surround branch and drop the map.
eq(DayCareMenu.isOpaque, false, "the screen overlays the map, it does not own it")
eq(DayCareMenu.drawsWidescreen, nil, "and never claims the whole window")
eq(DayCareMenu.drawWidescreen, nil, "so drawScene keeps drawing the world")

-- ---- against a real Gold cache -------------------------------------------

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local path = cache .. "/data/generated/pokemon.lua"
local file = io.open(path, "r")
if not file then
  check(true, "gold pokemon cache absent - SKIP")
  S.finish()
  return
end
file:close()

local cached = assert(loadfile(path))()
local cachedData = { pokemon = cached, moves = {} }

check(cached.DITTO ~= nil, "DITTO is in the cache")
eq(cached.DITTO.eggGroups[1], "EGG_DITTO", "with the EGG_DITTO group")
eq(cached.DITTO.genderRatio, 255, "and GENDER_UNKNOWN")
eq(cached.BULBASAUR.eggSteps, 20, "BULBASAUR's hatch counter is 20 cycles")
eq(Breeding.stepsToHatch({ isEgg = true, eggSteps = cached.BULBASAUR.eggSteps }),
  5120, "which is 5120 footfalls")

-- Every base form, walked down the real chains.
for _, row in ipairs({
    { "VENUSAUR", "BULBASAUR" }, { "CHARIZARD", "CHARMANDER" },
    { "BLASTOISE", "SQUIRTLE" }, { "BUTTERFREE", "CATERPIE" },
    { "RAICHU", "PICHU" }, { "CLEFABLE", "CLEFFA" },
    { "WIGGLYTUFF", "IGGLYBUFF" }, { "NIDOQUEEN", "NIDORAN_F" },
    { "NIDOKING", "NIDORAN_M" }, { "HITMONLEE", "TYROGUE" },
    { "HITMONCHAN", "TYROGUE" }, { "HITMONTOP", "TYROGUE" },
    { "JYNX", "SMOOCHUM" }, { "ELECTABUZZ", "ELEKID" },
    { "MAGMAR", "MAGBY" }, { "TYPHLOSION", "CYNDAQUIL" },
    { "FERALIGATR", "TOTODILE" }, { "MEGANIUM", "CHIKORITA" },
    { "AZUMARILL", "MARILL" }, { "TYRANITAR", "LARVITAR" },
    { "CROBAT", "ZUBAT" }, { "BELLOSSOM", "ODDISH" },
    { "POLITOED", "POLIWAG" }, { "SLOWKING", "SLOWPOKE" } }) do
  eq(Breeding.baseForm(cachedData, row[1]), row[2],
    row[1] .. " walks back to " .. row[2])
end

-- The unbreedable groups the cart really ships.
for _, id in ipairs({ "ARTICUNO", "ZAPDOS", "MOLTRES", "MEWTWO", "MEW",
    "RAIKOU", "ENTEI", "SUICUNE", "LUGIA", "HO_OH", "CELEBI", "UNOWN",
    "DITTO" }) do
  local def = cached[id]
  if def then
    if id == "DITTO" then
      check(not Breeding.isNoEggs(def), "DITTO is not in the No-Eggs group")
    else
      check(Breeding.isNoEggs(def), id .. " is in the No-Eggs group")
    end
  end
end
-- ...and therefore not even a Ditto can breed with one.
check(not Breeding.groupsCompatible(cachedData, "DITTO", "MEWTWO"),
  "a Ditto cannot breed with MEWTWO")
check(Breeding.groupsCompatible(cachedData, "DITTO", "PIKACHU"),
  "but it can with PIKACHU")
-- Baby forms are unbreedable in Gen 2, which is why a PICHU egg needs a
-- PIKACHU parent rather than another PICHU.
check(Breeding.isNoEggs(cached.PICHU), "PICHU cannot breed")
check(Breeding.groupsCompatible(cachedData, "PIKACHU", "PIKACHU"),
  "PIKACHU can")

-- data/pokemon/egg_moves.asm
local withEggMoves, withoutEggMoves = 0, {}
for id, def in pairs(cached) do
  if type(def) == "table" and def.baseStats then
    if type(def.eggMoves) == "table" then
      withEggMoves = withEggMoves + 1
    else
      withoutEggMoves[#withoutEggMoves + 1] = tostring(id)
    end
  end
end
eq(table.concat(withoutEggMoves, ","), "",
  "every species in the cache carries an eggMoves list")
check(withEggMoves >= 251,
  "the cache carries egg moves for " .. withEggMoves .. " species")
check(#cached.BULBASAUR.eggMoves > 0, "including BULBASAUR's")
eq(select(2, Breeding.canInheritMove(cachedData, "BULBASAUR",
  cached.BULBASAUR.eggMoves[1], {})), "eggMove",
  "and GetEggMove's first branch reads them")

S.finish()
