-- pokefirered/src/daycare.c:1271

local Breeding = {}

local SPECIES_NONE = 0 -- pokefirered/include/constants/species.h:4
local SPECIES_NIDORAN_F = 29 -- pokefirered/include/constants/species.h:33
local SPECIES_NIDORAN_M = 32 -- pokefirered/include/constants/species.h:36
local SPECIES_DITTO = 132 -- pokefirered/include/constants/species.h:136
local SPECIES_MARILL = 183 -- pokefirered/include/constants/species.h:190
local SPECIES_WOBBUFFET = 202 -- pokefirered/include/constants/species.h:209
local SPECIES_AZURILL = 350 -- pokefirered/include/constants/species.h:359
local SPECIES_WYNAUT = 360 -- pokefirered/include/constants/species.h:369
local SPECIES_VOLBEAT = 386 -- pokefirered/include/constants/species.h:395
local SPECIES_ILLUMISE = 387 -- pokefirered/include/constants/species.h:396

local ITEM_POKE_BALL = 4 -- pokefirered/include/constants/items.h:8
local ITEM_SEA_INCENSE = 220 -- pokefirered/include/constants/items.h:231
local ITEM_LAX_INCENSE = 221 -- pokefirered/include/constants/items.h:232
local ITEM_TM01 = 289 -- pokefirered/include/constants/items.h:300
-- pokefirered/include/constants/items.h:453 NUM_TECHNICAL_MACHINES + NUM_HIDDEN_MACHINES
local NUM_MACHINES = 58

-- pokefirered/include/constants/daycare.h:5
local PARENTS_INCOMPATIBLE = 0
local PARENTS_LOW_COMPATIBILITY = 20
local PARENTS_MED_COMPATIBILITY = 50
local PARENTS_MAX_COMPATIBILITY = 70

local INHERITED_IV_COUNT = 3 -- pokefirered/include/constants/daycare.h:16
local EGG_HATCH_LEVEL = 5 -- pokefirered/include/constants/daycare.h:17
local EGG_GENDER_MALE = 0x8000 -- pokefirered/include/constants/daycare.h:18

local EGG_GROUP_DITTO = 13 -- pokefirered/include/constants/pokemon.h:131
local EGG_GROUP_UNDISCOVERED = 15 -- pokefirered/include/constants/pokemon.h:133
local EGG_GROUPS_PER_MON = 2 -- pokefirered/include/constants/pokemon.h:135
local NUM_STATS = 6 -- pokefirered/include/constants/pokemon.h:172
local EVOS_PER_MON = 5 -- pokefirered/include/constants/pokemon.h:282

local DAYCARE_MON_COUNT = 2 -- pokefirered/include/constants/global.h:34
local MAX_MON_MOVES = 4 -- pokefirered/include/constants/global.h:77
local PARTY_SIZE = 6 -- pokefirered/include/constants/global.h:78
local USHRT_MAX = 65535
local FLAG_PENDING_DAYCARE_EGG = 0x266 -- pokefirered/include/constants/flags.h:639

-- pokefirered/src/daycare.c:822 selectedIvs order
local IV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }

Breeding.PARENTS_INCOMPATIBLE = PARENTS_INCOMPATIBLE
Breeding.PARENTS_LOW_COMPATIBILITY = PARENTS_LOW_COMPATIBILITY
Breeding.PARENTS_MED_COMPATIBILITY = PARENTS_MED_COMPATIBILITY
Breeding.PARENTS_MAX_COMPATIBILITY = PARENTS_MAX_COMPATIBILITY
Breeding.EGG_HATCH_LEVEL = EGG_HATCH_LEVEL
Breeding.EGG_GENDER_MALE = EGG_GENDER_MALE
Breeding.INHERITED_IV_COUNT = INHERITED_IV_COUNT
Breeding.FLAG_PENDING_DAYCARE_EGG = FLAG_PENDING_DAYCARE_EGG
Breeding.IV_KEYS = IV_KEYS

local function daycareMod()
  return package.loaded["src.core.game3.daycare"] or require("src.core.game3.daycare")
end

local function pokemonMod()
  local Pokemon = require("src.core.game3.pokemon")
  if not Pokemon._names then pcall(Pokemon.install, nil) end
  return Pokemon
end

local function rngMod()
  return require("src.core.game3.rng")
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId)) or SPECIES_NONE
end

local function heldItemOf(mon)
  local ItemsData = require("src.core.game3.items_data")
  local raw = mon and (mon.item or mon.heldItem)
  if raw == nil then return 0 end
  return tonumber(raw) or tonumber(ItemsData.toNumericId(raw)) or 0
end

local function scriptStore(session)
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store then return Space.store end
  return session and session.store or nil
end

local function movesOf(mon)
  local out = {}
  for i = 1, MAX_MON_MOVES do
    local raw = mon and mon.moves and mon.moves[i]
    if type(raw) == "table" then raw = raw.id or raw.move end
    out[i] = tonumber(raw) or 0
  end
  return out
end

-- pokefirered/src/daycare.c:1287 gSpeciesInfo[species].eggGroups
function Breeding.eggGroups(species)
  local Pokemon = pokemonMod()
  local meta = (Pokemon.speciesMeta and Pokemon.speciesMeta(species)) or {}
  return {
    tonumber(meta.eggGroup1) or EGG_GROUP_UNDISCOVERED,
    tonumber(meta.eggGroup2) or EGG_GROUP_UNDISCOVERED,
  }
end

-- pokefirered/src/daycare.c:1255 EggGroupsOverlap
function Breeding.eggGroupsOverlap(a, b)
  for i = 1, EGG_GROUPS_PER_MON do
    for j = 1, EGG_GROUPS_PER_MON do
      if a[i] == b[j] then return true end
    end
  end
  return false
end

-- pokefirered/src/daycare.c:1271 GetDaycareCompatibilityScore
function Breeding.compatibility(dc)
  local Daycare = daycareMod()
  local Pokemon = pokemonMod()
  local groups, species, ids, genders = {}, {}, {}, {}
  for i = 1, DAYCARE_MON_COUNT do
    local mon = Daycare.mon(dc, i)
    species[i] = speciesOf(mon)
    ids[i] = tonumber(mon and (mon.otId or mon.ot_id)) or 0
    genders[i] = (mon and Pokemon.gender and Pokemon.gender(species[i], mon.personality)) or "U"
    groups[i] = Breeding.eggGroups(species[i])
  end
  if groups[1][1] == EGG_GROUP_UNDISCOVERED or groups[2][1] == EGG_GROUP_UNDISCOVERED then
    return PARENTS_INCOMPATIBLE
  end
  if groups[1][1] == EGG_GROUP_DITTO and groups[2][1] == EGG_GROUP_DITTO then
    return PARENTS_INCOMPATIBLE
  end
  if groups[1][1] == EGG_GROUP_DITTO or groups[2][1] == EGG_GROUP_DITTO then
    if ids[1] == ids[2] then return PARENTS_LOW_COMPATIBILITY end
    return PARENTS_MED_COMPATIBILITY
  end
  if genders[1] == genders[2] then return PARENTS_INCOMPATIBLE end
  if genders[1] == "U" or genders[2] == "U" then return PARENTS_INCOMPATIBLE end
  if not Breeding.eggGroupsOverlap(groups[1], groups[2]) then return PARENTS_INCOMPATIBLE end
  if species[1] == species[2] then
    if ids[1] == ids[2] then return PARENTS_MED_COMPATIBILITY end
    return PARENTS_MAX_COMPATIBILITY
  end
  if ids[1] ~= ids[2] then return PARENTS_MED_COMPATIBILITY end
  return PARENTS_LOW_COMPATIBILITY
end

local preEvoOf, preEvoSource
local function preEvolution(species)
  local Pokemon = pokemonMod()
  local table_ = Pokemon._evolutions
  if preEvoSource ~= table_ then
    preEvoOf = {}
    local keys = {}
    for key in pairs(table_ or {}) do
      local num = tonumber(key)
      if num then keys[#keys + 1] = num end
    end
    table.sort(keys)
    for _, from in ipairs(keys) do
      for _, row in ipairs(table_[from] or {}) do
        local target = tonumber(row.target or row[3]) or 0
        if target > 0 and preEvoOf[target] == nil then preEvoOf[target] = from end
      end
    end
    preEvoSource = table_
  end
  return preEvoOf[species]
end

-- pokefirered/src/daycare.c:647 GetEggSpecies
function Breeding.eggSpecies(species)
  species = tonumber(species) or SPECIES_NONE
  for _ = 1, EVOS_PER_MON do
    local from = preEvolution(species)
    if not from then break end
    species = from
  end
  return species
end

-- pokefirered/src/daycare.c:721 _TriggerPendingDaycareEgg
function Breeding.triggerPendingEgg(session, dc)
  local Daycare = daycareMod()
  session = Daycare.sessionOf(session)
  dc = dc or Daycare.stateOf(session)
  if not dc then return 0 end
  local Rng = rngMod()
  dc.offspringPersonality = (Rng.Random() % 0xFFFE) + 1
  dc.eggPending = true
  -- pokefirered/src/daycare.c:751 FlagSet(FLAG_PENDING_DAYCARE_EGG)
  local store = scriptStore(session)
  if store then
    require("src.core.game3.scripting.flags").setFlag(store, nil, FLAG_PENDING_DAYCARE_EGG, true)
  end
  return dc.offspringPersonality
end

-- pokefirered/src/daycare.c:1148
function Breeding.tryProduceEgg(session, dc, validEggs)
  local Daycare = daycareMod()
  if not dc then return false end
  if Daycare.isEggPending(dc) then return false end
  if (tonumber(validEggs) or 0) ~= DAYCARE_MON_COUNT then return false end
  -- pokefirered/src/daycare.c:1149 (daycare->mons[1].steps & 0xFF) == 0xFF
  if ((tonumber(dc.steps and dc.steps[2]) or 0) % 256) ~= 255 then return false end
  local Rng = rngMod()
  -- pokefirered/src/daycare.c:1152
  if Breeding.compatibility(dc) > math.floor(Rng.Random() * 100 / USHRT_MAX) then
    Breeding.triggerPendingEgg(session, dc)
    return true
  end
  return false
end

-- pokefirered/src/daycare.c:976 RemoveEggFromDayCare
function Breeding.removeEgg(dc)
  if not dc then return end
  dc.offspringPersonality = 0
  dc.stepCounter = 0
  dc.eggPending = false
end

-- pokefirered/src/daycare.c:1018 DetermineEggSpeciesAndParentSlots
function Breeding.parentSlots(dc)
  local Daycare = daycareMod()
  local Pokemon = pokemonMod()
  local species, mother, father = {}, 1, 2
  for i = 1, DAYCARE_MON_COUNT do
    local mon = Daycare.mon(dc, i)
    species[i] = speciesOf(mon)
    local other = (i == 1) and 2 or 1
    if species[i] == SPECIES_DITTO then
      mother, father = other, i
    elseif mon and Pokemon.gender(species[i], mon.personality) == "F" then
      mother, father = i, other
    end
  end
  local eggSpecies = Breeding.eggSpecies(species[mother])
  local male = (tonumber(dc and dc.offspringPersonality) or 0) % 0x10000 >= EGG_GENDER_MALE
  if eggSpecies == SPECIES_NIDORAN_F and male then eggSpecies = SPECIES_NIDORAN_M end
  if eggSpecies == SPECIES_ILLUMISE and male then eggSpecies = SPECIES_VOLBEAT end
  -- pokefirered/src/daycare.c:1053
  local motherMon = Daycare.mon(dc, mother)
  if species[father] == SPECIES_DITTO
    and not (motherMon and Pokemon.gender(species[mother], motherMon.personality) == "F") then
    mother, father = father, mother
  end
  return eggSpecies, mother, father
end

-- pokefirered/src/daycare.c:987 AlterEggSpeciesWithIncenseItem
function Breeding.alterEggSpeciesWithIncenseItem(species, dc)
  local Daycare = daycareMod()
  if species ~= SPECIES_WYNAUT and species ~= SPECIES_AZURILL then return species end
  local motherItem = heldItemOf(Daycare.mon(dc, 1))
  local fatherItem = heldItemOf(Daycare.mon(dc, 2))
  if species == SPECIES_WYNAUT and motherItem ~= ITEM_LAX_INCENSE and fatherItem ~= ITEM_LAX_INCENSE then
    species = SPECIES_WOBBUFFET
  end
  if species == SPECIES_AZURILL and motherItem ~= ITEM_SEA_INCENSE and fatherItem ~= ITEM_SEA_INCENSE then
    species = SPECIES_MARILL
  end
  return species
end

-- pokefirered/src/daycare.c:791 InheritIVs
function Breeding.inheritIVs(egg, dc)
  local Daycare = daycareMod()
  if not (egg and dc) then return end
  local Rng = rngMod()
  local available = {}
  for i = 1, NUM_STATS do available[i] = i end
  local selected = {}
  for i = 1, INHERITED_IV_COUNT do
    -- pokefirered/src/daycare.c:809
    local pick = (Rng.Random() % (NUM_STATS - (i - 1))) + 1
    selected[i] = available[pick]
    -- pokefirered/src/daycare.c:772 RemoveIVIndexFromList
    table.remove(available, pick)
  end
  local whichParent = {}
  for i = 1, INHERITED_IV_COUNT do
    whichParent[i] = (Rng.Random() % DAYCARE_MON_COUNT) + 1
  end
  egg.ivs = egg.ivs or {}
  for i = 1, INHERITED_IV_COUNT do
    local key = IV_KEYS[selected[i]]
    local parent = Daycare.mon(dc, whichParent[i])
    local parentIvs = parent and parent.ivs
    local value = key and parentIvs and tonumber(parentIvs[key])
    if value then egg.ivs[key] = value end
  end
  return selected, whichParent
end

-- pokefirered/src/daycare.c:854 GetEggMoves
function Breeding.eggMovesOf(species)
  local Pokemon = pokemonMod()
  return (Pokemon.eggMoves and Pokemon.eggMoves(species)) or {}
end

-- pokefirered/src/daycare.c:888 BuildEggMoveset
function Breeding.buildEggMoveset(egg, father, mother)
  local Daycare = daycareMod()
  local Pokemon = pokemonMod()
  if not egg then return end
  local eggSpecies = speciesOf(egg)
  local fatherMoves, motherMoves = movesOf(father), movesOf(mother)
  local eggMoves = Breeding.eggMovesOf(eggSpecies)
  local levelUpMoves = {}
  for _, entry in ipairs(Pokemon.learnset(eggSpecies) or {}) do
    local move = tonumber(entry[2] or entry.move) or 0
    if move > 0 then levelUpMoves[#levelUpMoves + 1] = move end
  end

  -- pokefirered/src/daycare.c:916
  for i = 1, MAX_MON_MOVES do
    local move = fatherMoves[i]
    if move == 0 then break end
    for _, eggMove in ipairs(eggMoves) do
      if move == eggMove then
        Daycare.teachMove(egg, move)
        break
      end
    end
  end

  -- pokefirered/src/daycare.c:935
  for i = 1, MAX_MON_MOVES do
    local move = fatherMoves[i]
    if move ~= 0 then
      for machine = 0, NUM_MACHINES - 1 do
        if move == Pokemon.moveFromTmItem(ITEM_TM01 + machine)
          and Pokemon.canLearnTmIndex(eggSpecies, machine) then
          Daycare.teachMove(egg, move)
        end
      end
    end
  end

  -- pokefirered/src/daycare.c:949
  local shared = {}
  for i = 1, MAX_MON_MOVES do
    local move = fatherMoves[i]
    if move == 0 then break end
    for j = 1, MAX_MON_MOVES do
      if move == motherMoves[j] then shared[#shared + 1] = move end
    end
  end

  -- pokefirered/src/daycare.c:960
  for _, move in ipairs(shared) do
    for _, levelUp in ipairs(levelUpMoves) do
      if move == levelUp then
        Daycare.teachMove(egg, move)
        break
      end
    end
  end
end

-- pokefirered/src/daycare.c:1096 CreateEgg SetMonData block
function Breeding.applyEggData(egg, setHotSpringsLocation)
  if not egg then return nil end
  local Pokemon = pokemonMod()
  local species = speciesOf(egg)
  -- pokefirered/src/daycare.c:1101 gSpeciesInfo[species].eggCycles
  local meta = (Pokemon.speciesMeta and Pokemon.speciesMeta(species)) or {}
  local cycles = tonumber(meta.eggCycles) or 20
  egg.friendship = cycles
  egg.happiness = cycles
  egg.eggCycles = cycles
  egg.level = EGG_HATCH_LEVEL
  egg.metLevel = 0
  egg.pokeball = ITEM_POKE_BALL
  egg.isEgg = true
  if setHotSpringsLocation then
    -- pokefirered/src/daycare.c:1106 METLOC_SPECIAL_EGG
    egg.metLocation = 253
  end
  return egg
end

local function buildEggMon(session, species, personality)
  local Pokemon = pokemonMod()
  local Party = require("src.core.game3.party")
  -- pokefirered/src/daycare.c:1657 GetSetPokedexFlag
  local scratch = setmetatable({ party = {}, dex = { seen = {}, owned = {} } },
    { __index = session })
  local ok, _, egg = Party.giveMon(scratch, species, EGG_HATCH_LEVEL, "EGG")
  if not (ok and egg) then return nil end
  egg.personality = personality
  egg.nature = Pokemon.natureId(personality)
  egg.gender = Pokemon.gender(species, personality)
  egg.ability = Pokemon.abilityId(species, personality)
  egg.abilityId = egg.ability
  Breeding.applyEggData(egg)
  Pokemon.applyStats(egg)
  return egg
end

-- pokefirered/src/daycare.c:1114 SetInitialEggData
function Breeding.setInitialEggData(session, species, dc)
  local Rng = rngMod()
  local personality = ((tonumber(dc and dc.offspringPersonality) or 0)
    + Rng.Random() * 0x10000) % 0x100000000
  return buildEggMon(session, species, personality)
end

-- pokefirered/src/daycare.c:1087 CreateEgg
function Breeding.createEgg(session, species, setHotSpringsLocation)
  local Rng = rngMod()
  local egg = buildEggMon(session, species, Rng.Random32())
  return Breeding.applyEggData(egg, setHotSpringsLocation)
end

-- pokefirered/src/daycare.c:1063 _GiveEggFromDaycare
function Breeding.giveEggFromDaycare(session)
  local Daycare = daycareMod()
  session = Daycare.sessionOf(session)
  local dc = Daycare.stateOf(session)
  if not (session and dc) then return nil end
  local species, mother, father = Breeding.parentSlots(dc)
  if (species or SPECIES_NONE) == SPECIES_NONE then return nil end
  species = Breeding.alterEggSpeciesWithIncenseItem(species, dc)
  local egg = Breeding.setInitialEggData(session, species, dc)
  if not egg then return nil end
  Breeding.inheritIVs(egg, dc)
  Breeding.buildEggMoveset(egg, Daycare.mon(dc, father), Daycare.mon(dc, mother))
  egg.isEgg = true
  session.party = session.party or {}
  -- pokefirered/src/daycare.c:1081 gPlayerParty[PARTY_SIZE - 1] = egg
  session.party[PARTY_SIZE] = egg
  Daycare.compactParty(session)
  Breeding.removeEgg(dc)
  return egg
end

-- pokefirered/src/daycare.c:1639 AddHatchedMonToParty
function Breeding.hatchMon(session, mon)
  local Daycare = daycareMod()
  local Pokemon = pokemonMod()
  if not mon then return nil end
  session = Daycare.sessionOf(session)
  local species = speciesOf(mon)
  mon.isEgg = false
  mon.egg = false
  mon.level = EGG_HATCH_LEVEL
  -- pokefirered/src/daycare.c:1654 SetMonData(mon, MON_DATA_NICKNAME, name)
  mon.nickname = ""
  mon.name = (Pokemon.name and Pokemon.name(species)) or mon.name
  -- pokefirered/src/daycare.c:1631 friendship = 120
  mon.friendship = 120
  mon.happiness = 120
  mon.eggCycles = nil
  mon.pokeball = ITEM_POKE_BALL
  mon.metLevel = 0
  mon.metLocation = (Pokemon.currentMapSec and Pokemon.currentMapSec(session)) or mon.metLocation
  -- pokefirered/src/daycare.c:1671 MonRestorePP
  if type(mon.pp) == "table" and type(mon.maxPp) == "table" then
    for i = 1, #mon.pp do mon.pp[i] = mon.maxPp[i] or mon.pp[i] end
  end
  -- pokefirered/src/daycare.c:1672 CalculateMonStats
  Pokemon.applyStats(mon)
  -- pokefirered/src/daycare.c:1657 GetSetPokedexFlag
  if session and session.dex and species ~= SPECIES_NONE then
    local Dex = require("src.core.game3.dex")
    Dex.setSeen(session.dex, species)
    Dex.setCaught(session.dex, species)
  end
  return mon
end

return Breeding
