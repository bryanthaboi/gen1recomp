-- Script specials for Trainer Fan Club (pokefirered/src/trainer_fan_club.c).
-- Covers specials 0xA3 through 0xAA (pokefirered/data/specials.inc:174-181).

local Std = require("src.core.game3.scripting.stdscripts")
local TrainerFanClub = require("src.core.game3.trainer_fan_club")

local FanClub = {}

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319

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

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(ctx), ctx, id)) or 0
end

local function setResult(ctx, value)
  flagsMod().setVar(scriptStore(ctx), ctx, VAR_RESULT, tonumber(value) or 0)
end

FanClub.HANDLERS = {
  -- pokefirered/src/trainer_fan_club.c:223 Script_IsFanClubMemberFanOfPlayer
  [Std.SPECIAL.Script_IsFanClubMemberFanOfPlayer] = function(ctx)
    local memberId = varGet(ctx, VAR_0x8004)
    local isFan = TrainerFanClub.isFanClubMemberFanOfPlayer(sessionOf(ctx), ctx, memberId)
    setResult(ctx, isFan and 1 or 0)
    return false
  end,

  -- pokefirered/src/trainer_fan_club.c:170 Script_GetNumFansOfPlayerInTrainerFanClub
  [Std.SPECIAL.Script_GetNumFansOfPlayerInTrainerFanClub] = function(ctx)
    local count = TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(sessionOf(ctx), ctx)
    setResult(ctx, count)
    return false
  end,

  -- pokefirered/src/trainer_fan_club.c:240 Script_BufferFanClubTrainerName
  [Std.SPECIAL.Script_BufferFanClubTrainerName] = function(ctx, adapters)
    local memberId = varGet(ctx, VAR_0x8004)
    TrainerFanClub.bufferFanClubTrainerName(sessionOf(ctx), ctx, adapters, memberId)
    return false
  end,

  -- pokefirered/src/trainer_fan_club.c:40 Script_TryLoseFansFromPlayTimeAfterLinkBattle
  [Std.SPECIAL.Script_TryLoseFansFromPlayTimeAfterLinkBattle] = function(ctx)
    TrainerFanClub.tryLoseFansFromPlayTimeAfterLinkBattle(sessionOf(ctx), ctx)
    return false
  end,

  -- pokefirered/src/trainer_fan_club.c:189 Script_TryLoseFansFromPlayTime
  [Std.SPECIAL.Script_TryLoseFansFromPlayTime] = function(ctx)
    TrainerFanClub.tryLoseFansFromPlayTime(sessionOf(ctx), ctx)
    return false
  end,

  -- pokefirered/src/trainer_fan_club.c:334 Script_SetPlayerGotFirstFans
  [Std.SPECIAL.Script_SetPlayerGotFirstFans] = function(ctx)
    TrainerFanClub.setPlayerGotFirstFans(sessionOf(ctx), ctx)
    return false
  end,

  -- pokefirered/src/trainer_fan_club.c:54 Script_UpdateTrainerFanClubGameClear
  [Std.SPECIAL.Script_UpdateTrainerFanClubGameClear] = function(ctx)
    TrainerFanClub.updateTrainerFanClubGameClear(sessionOf(ctx), ctx)
    return false
  end,

  -- pokefirered/src/trainer_fan_club.c:344 Script_TryGainNewFanFromCounter
  [Std.SPECIAL.Script_TryGainNewFanFromCounter] = function(ctx)
    local counterIdx = varGet(ctx, VAR_0x8004)
    local timer = TrainerFanClub.tryGainNewFanFromCounter(sessionOf(ctx), ctx, counterIdx)
    setResult(ctx, timer)
    return false
  end,
}

return FanClub
