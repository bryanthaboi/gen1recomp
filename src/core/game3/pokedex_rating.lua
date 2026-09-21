-- Professor Oak's Pokédex Rating Evaluation (pokefirered/src/prof_pc.c).
-- Evaluates caught Pokémon count brackets, Mew exception, and triggers rating messages.

local PokedexRating = {}

local KANTO_DEX_COUNT = 151
local SPECIES_MEW = 151

-- pokefirered/data/text/pokedex_rating.inc
local RATING_MESSAGES = {
  LESS_THAN_10 = "You still have lots to do.\nGo into every patch of grass you\nsee and look for POKéMON!",
  LESS_THAN_20 = "It looks as if you're getting on\nthe right track!\nI've given one of my AIDES a FLASH\nHM. Make sure you go get it!",
  LESS_THAN_30 = "Your POKéDEX could use a bit more\nvolume still!\nTry to catch other species of\nPOKéMON!",
  LESS_THAN_40 = "Good, it's apparent that you're\ntrying hard!\nI've given one of my AIDES an\nITEMFINDER. Be sure to collect it!",
  LESS_THAN_50 = "Your POKéDEX is coming along quite\nwell!\nI've given one of my AIDES an\nAMULET COIN. Be sure to get it!",
  LESS_THAN_60 = "Ah, you've finally topped 50\nspecies!\nI've given one of my AIDES an EXP.\nSHARE. Be sure to go get it!",
  LESS_THAN_70 = "Hoho! This is turning into quite the\nrespectable POKéDEX!",
  LESS_THAN_80 = "Very good!\nI think you'll collect even more\nPOKéMON by going fishing!",
  LESS_THAN_90 = "Wonderful! Let me guess… You\nlike to collect things, don't you?",
  LESS_THAN_100 = "I'm impressed!\nIt must have been difficult to do!",
  LESS_THAN_110 = "You've finally hit 100 species!\nI can't believe how good you are!",
  LESS_THAN_120 = "You even have the evolved forms\nof POKéMON! Super!",
  LESS_THAN_130 = "Excellent! Trade with friends to\nget some more!",
  LESS_THAN_140 = "Outstanding!\nYou've become a real pro at this!",
  LESS_THAN_150 = "I have nothing left to say!\nYou're the POKéMON PROFESSOR now!",
  COMPLETE = "Your POKéDEX is entirely complete!\nCongratulations!!",
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
  local msg, isComplete = PokedexRating.getRatingMessage(count, dex)

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
