-- Professor Oak's Pokédex Rating Evaluation (pokefirered/src/prof_pc.c).
-- Evaluates caught Pokémon count brackets, Mew exception, and triggers rating messages.

local PokedexRating = {}

local KANTO_DEX_COUNT = 151
local SPECIES_MEW = 151

-- pokefirered/src/prof_pc.c:6-21
local RATING_MESSAGES = {
  LESS_THAN_10 = "PokedexRating_Text_LessThan10",
  LESS_THAN_20 = "PokedexRating_Text_LessThan20",
  LESS_THAN_30 = "PokedexRating_Text_LessThan30",
  LESS_THAN_40 = "PokedexRating_Text_LessThan40",
  LESS_THAN_50 = "PokedexRating_Text_LessThan50",
  LESS_THAN_60 = "PokedexRating_Text_LessThan60",
  LESS_THAN_70 = "PokedexRating_Text_LessThan70",
  LESS_THAN_80 = "PokedexRating_Text_LessThan80",
  LESS_THAN_90 = "PokedexRating_Text_LessThan90",
  LESS_THAN_100 = "PokedexRating_Text_LessThan100",
  LESS_THAN_110 = "PokedexRating_Text_LessThan110",
  LESS_THAN_120 = "PokedexRating_Text_LessThan120",
  LESS_THAN_130 = "PokedexRating_Text_LessThan130",
  LESS_THAN_140 = "PokedexRating_Text_LessThan140",
  LESS_THAN_150 = "PokedexRating_Text_LessThan150",
  COMPLETE = "PokedexRating_Text_Complete",
}
PokedexRating.TEXT = RATING_MESSAGES

local function sessionOf(ctx)
  if ctx and ctx.session then return ctx.session end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store and Space.store.flags then return Space.store end
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function dexOf(session, ctx)
  session = session or sessionOf(ctx)
  return (session and (session.dex or session.pokedex)) or nil
end

--- pokefirered/src/prof_pc.c:38 GetProfOaksRatingMessageByCount
--- Evaluates Pokédex count and returns: messageText, isComplete (boolean)
function PokedexRating.getRatingMessage(count, dex)
  count = tonumber(count) or 0

  if count < 10 then return RATING_MESSAGES.LESS_THAN_10, false end
  if count < 20 then return RATING_MESSAGES.LESS_THAN_20, false end
  if count < 30 then return RATING_MESSAGES.LESS_THAN_30, false end
  if count < 40 then return RATING_MESSAGES.LESS_THAN_40, false end
  if count < 50 then return RATING_MESSAGES.LESS_THAN_50, false end
  if count < 60 then return RATING_MESSAGES.LESS_THAN_60, false end
  if count < 70 then return RATING_MESSAGES.LESS_THAN_70, false end
  if count < 80 then return RATING_MESSAGES.LESS_THAN_80, false end
  if count < 90 then return RATING_MESSAGES.LESS_THAN_90, false end
  if count < 100 then return RATING_MESSAGES.LESS_THAN_100, false end
  if count < 110 then return RATING_MESSAGES.LESS_THAN_110, false end
  if count < 120 then return RATING_MESSAGES.LESS_THAN_120, false end
  if count < 130 then return RATING_MESSAGES.LESS_THAN_130, false end
  if count < 140 then return RATING_MESSAGES.LESS_THAN_140, false end
  if count < 150 then return RATING_MESSAGES.LESS_THAN_150, false end

  if count == (KANTO_DEX_COUNT - 1) then -- 150
    -- In pokefirered: Mew (151) does not count towards completing the 150 requirement.
    -- If Mew is caught in Kanto Dex, the player has 149 regular + Mew = 150 total,
    -- which means they haven't completed the 150 standard species yet!
    local Dex = require("src.core.game3.dex")
    if dex and Dex.isCaught(dex, SPECIES_MEW) then
      return RATING_MESSAGES.LESS_THAN_150, false
    end
    return RATING_MESSAGES.COMPLETE, true
  end

  if count >= KANTO_DEX_COUNT then -- 151
    return RATING_MESSAGES.COMPLETE, true
  end

  return RATING_MESSAGES.LESS_THAN_10, false
end

--- pokefirered/src/prof_pc.c:106 GetProfOaksRatingMessage
function PokedexRating.getProfOaksRatingMessage(session, ctx, adapters)
  session = session or sessionOf(ctx)
  local flagsMod = require("src.core.game3.scripting.flags")
  local scriptStore = (ctx and ctx.session) or session

  local count = tonumber(flagsMod.getVar(scriptStore, ctx, 0x8004)) or 0
  local dex = dexOf(session, ctx)
  local key, isComplete = PokedexRating.getRatingMessage(count, dex)
  local msg = require("src.core.game3.rom_text").box(key, ctx)

  flagsMod.setVar(scriptStore, ctx, 0x800D, isComplete and 1 or 0)

  -- ShowFieldMessage (pokefirered/src/field_message_box.c:65)
  if ctx then
    ctx.messageOpen = true
    ctx.printerDone = false
  end
  local open = adapters and (adapters.openMessageStay or adapters.openMessageAsync)
  if open then
    open(msg, nil)
  elseif adapters and adapters.openMessage then
    adapters.openMessage(msg)
  end

  return false, msg
end

return PokedexRating
