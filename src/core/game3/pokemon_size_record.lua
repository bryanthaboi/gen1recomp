-- FRLG Pokémon Size Record System (pokefirered/src/pokemon_size_record.c).
-- Calculates size hashes, table-interpolated heights, imperial conversions, and record comparisons.

local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

local SizeRecord = {}

SizeRecord.SPECIES_MAGIKARP = 129
SizeRecord.SPECIES_HERACROSS = 214

SizeRecord.VAR_HERACROSS_SIZE_RECORD = 0x403D
SizeRecord.VAR_MAGIKARP_SIZE_RECORD = 0x4040
SizeRecord.VAR_LOTAD_SIZE_RECORD = 0x404F

SizeRecord.DEFAULT_MAX_SIZE = 0
SizeRecord.PARTY_SIZE = 6

-- pokefirered/src/pokemon_size_record.c:18 sBigMonSizeTable
local sBigMonSizeTable = {
  { unk0 = 290,  unk2 = 1,   unk4 = 0 },
  { unk0 = 300,  unk2 = 1,   unk4 = 10 },
  { unk0 = 400,  unk2 = 2,   unk4 = 110 },
  { unk0 = 500,  unk2 = 4,   unk4 = 310 },
  { unk0 = 600,  unk2 = 20,  unk4 = 710 },
  { unk0 = 700,  unk2 = 50,  unk4 = 2710 },
  { unk0 = 800,  unk2 = 100, unk4 = 7710 },
  { unk0 = 900,  unk2 = 150, unk4 = 17710 },
  { unk0 = 1000, unk2 = 150, unk4 = 32710 },
  { unk0 = 1100, unk2 = 100, unk4 = 47710 },
  { unk0 = 1200, unk2 = 50,  unk4 = 57710 },
  { unk0 = 1300, unk2 = 20,  unk4 = 62710 },
  { unk0 = 1400, unk2 = 5,   unk4 = 64710 },
  { unk0 = 1500, unk2 = 2,   unk4 = 65210 },
  { unk0 = 1600, unk2 = 1,   unk4 = 65410 },
  { unk0 = 1700, unk2 = 1,   unk4 = 65510 },
}
SizeRecord.TABLE = sBigMonSizeTable

local SPECIES_HEIGHT_DM = {
  [129] = 9,  -- Magikarp: 0.9 m (9 dm)
  [214] = 15, -- Heracross: 1.5 m (15 dm)
  [270] = 5,  -- Lotad: 0.5 m (5 dm)
  [273] = 5,  -- Seedot: 0.5 m (5 dm)
}

function SizeRecord.getSpeciesHeight(species)
  species = tonumber(species) or 0
  if SPECIES_HEIGHT_DM[species] then
    return SPECIES_HEIGHT_DM[species]
  end
  local okP, PokedexData = pcall(require, "src.core.game3.pokedex_data")
  if okP and PokedexData and PokedexData.getEntry then
    local ent = PokedexData.getEntry(species)
    if ent and ent.heightDm then return ent.heightDm end
  end
  return 10 -- default 1.0 m (10 dm)
end

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

function SizeRecord.sessionOf(ctx)
  if ctx and ctx.session then return ctx.session end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store and Space.store.flags then return Space.store end
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function scriptStore(session, ctx)
  local Space = package.loaded["src.core.game3.scripting.space"]
  return (Space and Space.store) or (ctx and ctx.session) or (session and session.store) or session or nil
end

function SizeRecord.getVar(session, ctx, varId)
  session = session or SizeRecord.sessionOf(ctx)
  return tonumber(flagsMod().getVar(scriptStore(session, ctx), ctx, varId)) or 0
end

function SizeRecord.setVar(session, ctx, varId, value)
  session = session or SizeRecord.sessionOf(ctx)
  flagsMod().setVar(scriptStore(session, ctx), ctx, varId, band(tonumber(value) or 0, 0xFFFF))
end

function SizeRecord.setStringVar(ctx, adapters, index, text)
  if adapters and adapters.setStringVar then adapters.setStringVar(index, text) end
  if ctx and ctx.stringVars then ctx.stringVars[index] = text end
end

--- pokefirered/src/pokemon_size_record.c:47 GetMonSizeHash
function SizeRecord.getMonSizeHash(pkmn)
  if not pkmn then return 0 end
  local personality = band(tonumber(pkmn.personality or pkmn.pid or 0) or 0, 0xFFFFFFFF)
  local ivs = pkmn.ivs or {}
  local hpIV = band(tonumber(pkmn.ivHp or ivs.hp or 0) or 0, 0xF)
  local attackIV = band(tonumber(pkmn.ivAtk or ivs.atk or 0) or 0, 0xF)
  local defenseIV = band(tonumber(pkmn.ivDef or ivs.def or 0) or 0, 0xF)
  local speedIV = band(tonumber(pkmn.ivSpd or ivs.spd or 0) or 0, 0xF)
  local spAtkIV = band(tonumber(pkmn.ivSpAtk or ivs.spAtk or 0) or 0, 0xF)
  local spDefIV = band(tonumber(pkmn.ivSpDef or ivs.spDef or 0) or 0, 0xF)

  local hibyte = band(bxor(bxor(attackIV, defenseIV) * hpIV, band(personality, 0xFF)), 0xFF)
  local lobyte = band(bxor(bxor(spAtkIV, spDefIV) * speedIV, band(rshift(personality, 8), 0xFF)), 0xFF)

  return band(bor(lshift(hibyte, 8), lobyte), 0xFFFF)
end

--- pokefirered/src/pokemon_size_record.c:62 TranslateBigMonSizeTableIndex
local function translateBigMonSizeTableIndex(a)
  a = band(tonumber(a) or 0, 0xFFFF)
  for i = 2, 15 do -- 1-based (i = 1 in C is index 2 in Lua)
    if a < sBigMonSizeTable[i].unk4 then
      return i - 1
    end
  end
  return 16
end
SizeRecord.translateIndex = translateBigMonSizeTableIndex

--- pokefirered/src/pokemon_size_record.c:74 GetMonSize
function SizeRecord.getMonSize(species, b)
  b = band(tonumber(b) or 0, 0xFFFF)
  local height = SizeRecord.getSpeciesHeight(species)
  local var = translateBigMonSizeTableIndex(b)
  local row = sBigMonSizeTable[var]
  local unk0 = row.unk0
  local unk2 = row.unk2
  local unk4 = row.unk4
  unk0 = unk0 + math.floor((b - unk4) / unk2)
  return math.floor(height * unk0 / 10)
end

--- pokefirered/src/pokemon_size_record.c:91 FormatMonSizeRecord
--- Converts size from centimeters to inches with 1 decimal place (UNITS_IMPERIAL).
function SizeRecord.formatMonSizeRecord(size)
  size = tonumber(size) or 0
  local inches = math.floor(size * 100 / 254)
  local whole = math.floor(inches / 10)
  local frac = inches % 10
  return string.format("%d.%d", whole, frac)
end

--- pokefirered/src/pokemon_size_record.c:104 CompareMonSize
--- Returns:
---   0: Invalid slot / cancel
---   1: Is egg or wrong species
---   2: Smaller than record (newSize < oldSize)
---   3: New record (newSize > oldSize) - updates varId
---   4: Tied record (newSize == oldSize)
function SizeRecord.compareMonSize(session, ctx, adapters, species, varId, slot)
  session = session or SizeRecord.sessionOf(ctx)
  slot = tonumber(slot)
  if slot == nil then
    local VAR_RESULT = 0x800D
    slot = tonumber(flagsMod().getVar(scriptStore(session, ctx), ctx, VAR_RESULT)) or 0
  end

  if slot < 0 or slot >= SizeRecord.PARTY_SIZE then
    return 0
  end

  local party = (session and session.party) or {}
  local pkmn = party[slot + 1]

  if not pkmn or pkmn.isEgg or pkmn.is_egg or (tonumber(pkmn.species or pkmn.speciesId) ~= tonumber(species)) then
    return 1
  end

  local sizeParams = SizeRecord.getMonSizeHash(pkmn)
  local newSize = SizeRecord.getMonSize(species, sizeParams)
  local oldRecord = SizeRecord.getVar(session, ctx, varId)
  local oldSize = SizeRecord.getMonSize(species, oldRecord)

  SizeRecord.setStringVar(ctx, adapters, 3, SizeRecord.formatMonSizeRecord(oldSize))
  SizeRecord.setStringVar(ctx, adapters, 2, SizeRecord.formatMonSizeRecord(newSize))

  if newSize == oldSize then
    return 4
  elseif newSize < oldSize then
    return 2
  else
    SizeRecord.setVar(session, ctx, varId, sizeParams)
    return 3
  end
end

--- pokefirered/src/pokemon_size_record.c:147 GetMonSizeRecordInfo
function SizeRecord.getMonSizeRecordInfo(session, ctx, adapters, species, varId)
  session = session or SizeRecord.sessionOf(ctx)
  local sizeRecord = SizeRecord.getVar(session, ctx, varId)
  local size = SizeRecord.getMonSize(species, sizeRecord)

  SizeRecord.setStringVar(ctx, adapters, 3, SizeRecord.formatMonSizeRecord(size))

  local speciesName = (species == SizeRecord.SPECIES_MAGIKARP and "MAGIKARP")
    or (species == SizeRecord.SPECIES_HERACROSS and "HERACROSS")
    or "POKéMON"
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if okP and Pokemon and Pokemon.name then
    local n = Pokemon.name(species)
    if n and n ~= "" then speciesName = n end
  end
  SizeRecord.setStringVar(ctx, adapters, 1, speciesName)
end

function SizeRecord.initMagikarpSizeRecord(session, ctx)
  SizeRecord.setVar(session, ctx, SizeRecord.VAR_MAGIKARP_SIZE_RECORD, SizeRecord.DEFAULT_MAX_SIZE)
end

function SizeRecord.initHeracrossSizeRecord(session, ctx)
  SizeRecord.setVar(session, ctx, SizeRecord.VAR_HERACROSS_SIZE_RECORD, SizeRecord.DEFAULT_MAX_SIZE)
end

return SizeRecord
