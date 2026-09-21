-- Script specials for Size Records and Prof Oak's Rating (pokefirered/src/pokemon_size_record.c, prof_pc.c).
-- Covers specials 0x77-0x7A and 0xD5 (pokefirered/data/specials.inc:130-133, 224).

local Std = require("src.core.game3.scripting.stdscripts")
local SizeRecord = require("src.core.game3.pokemon_size_record")
local PokedexRating = require("src.core.game3.pokedex_rating")

local SizeRecordNatives = {}

local VAR_RESULT = 0x800D

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function sessionOf(ctx)
  if ctx and ctx.session then return ctx.session end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store and Space.store.flags then return Space.store end
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function scriptStore(ctx)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local session = sessionOf(ctx)
  return (Space and Space.store) or (ctx and ctx.session) or (session and session.store) or session or nil
end

local function setResult(ctx, value)
  flagsMod().setVar(scriptStore(ctx), ctx, VAR_RESULT, tonumber(value) or 0)
end

SizeRecordNatives.HANDLERS = {
  -- pokefirered/src/pokemon_size_record.c:160 GetHeracrossSizeRecordInfo
  [Std.SPECIAL.GetHeracrossSizeRecordInfo] = function(ctx, adapters)
    SizeRecord.getMonSizeRecordInfo(sessionOf(ctx), ctx, adapters, SizeRecord.SPECIES_HERACROSS, SizeRecord.VAR_HERACROSS_SIZE_RECORD)
    return false
  end,

  -- pokefirered/src/pokemon_size_record.c:167 CompareHeracrossSize
  [Std.SPECIAL.CompareHeracrossSize] = function(ctx, adapters)
    local code = SizeRecord.compareMonSize(sessionOf(ctx), ctx, adapters, SizeRecord.SPECIES_HERACROSS, SizeRecord.VAR_HERACROSS_SIZE_RECORD)
    setResult(ctx, code)
    return false
  end,

  -- pokefirered/src/pokemon_size_record.c:179 GetMagikarpSizeRecordInfo
  [Std.SPECIAL.GetMagikarpSizeRecordInfo] = function(ctx, adapters)
    SizeRecord.getMonSizeRecordInfo(sessionOf(ctx), ctx, adapters, SizeRecord.SPECIES_MAGIKARP, SizeRecord.VAR_MAGIKARP_SIZE_RECORD)
    return false
  end,

  -- pokefirered/src/pokemon_size_record.c:186 CompareMagikarpSize
  [Std.SPECIAL.CompareMagikarpSize] = function(ctx, adapters)
    local code = SizeRecord.compareMonSize(sessionOf(ctx), ctx, adapters, SizeRecord.SPECIES_MAGIKARP, SizeRecord.VAR_MAGIKARP_SIZE_RECORD)
    setResult(ctx, code)
    return false
  end,

  -- pokefirered/src/prof_pc.c:106 GetProfOaksRatingMessage
  [Std.SPECIAL.GetProfOaksRatingMessage] = function(ctx, adapters)
    PokedexRating.getProfOaksRatingMessage(sessionOf(ctx), ctx, adapters)
    return false
  end,
}

return SizeRecordNatives
