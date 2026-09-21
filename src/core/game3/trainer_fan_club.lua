-- FRLG Trainer Fan Club system (pokefirered/src/trainer_fan_club.c).
-- Manages fan states, Saffron fan club house members, playtime decay, and link battle updates.

local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

local TrainerFanClub = {}

-- Member indices (pokefirered/include/constants/trainer_fan_club.h)
TrainerFanClub.MEMBER = {
  MEMBER1 = 0, -- Crush Girl (Battle Girl)
  MEMBER2 = 1, -- Youngster
  MEMBER3 = 2, -- Gentleman
  MEMBER4 = 3, -- Little Girl
  MEMBER5 = 4, -- Rocker
  MEMBER6 = 5, -- Woman
  MEMBER7 = 6, -- Beauty
  MEMBER8 = 7, -- Black Belt
}

TrainerFanClub.NUM_MEMBERS = 8

-- Variables and Flags (pokefirered/include/constants/vars.h, flags.h)
TrainerFanClub.VAR_FANCLUB_FAN_COUNTER = 0x4038
TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER = 0x4039
TrainerFanClub.VAR_MAP_SCENE_SAFFRON_CITY_POKEMON_TRAINER_FAN_CLUB = 0x4073

TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_BLACK_BELT = 0x6C
TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_ROCKER = 0x6D
TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_WOMAN = 0x6E
TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_BEAUTY = 0x6F

-- Counter increment array (pokefirered/src/trainer_fan_club.c:74)
local sCounterIncrements = { [0] = 2, [1] = 1, [2] = 2, [3] = 1 }
TrainerFanClub.COUNTER_INCREMENTS = sCounterIncrements

-- Candidate search order for gaining a fan (pokefirered/src/trainer_fan_club.c:100)
local sGainOrder = { 1, 3, 5, 0, 7, 6, 4, 2 }
TrainerFanClub.GAIN_ORDER = sGainOrder

-- Candidate search order for losing a fan (pokefirered/src/trainer_fan_club.c:133)
local sLoseOrder = { 5, 6, 3, 7, 4, 1, 0, 2 }
TrainerFanClub.LOSE_ORDER = sLoseOrder

--- Bit-unpack VAR_FANCLUB_FAN_COUNTER (u16)
--- bits 0..6: timer (0..127)
--- bit 7: gotInitialFans (0 or 1)
--- bits 8..15: fanFlags (8-bit bitmask for members 0..7)
function TrainerFanClub.unpack(raw)
  raw = band(tonumber(raw) or 0, 0xFFFF)
  local timer = band(raw, 0x7F)
  local gotInitialFans = band(raw, 0x80) ~= 0
  local fanFlags = band(rshift(raw, 8), 0xFF)
  return timer, gotInitialFans, fanFlags
end

--- Bit-pack into 16-bit VAR_FANCLUB_FAN_COUNTER
function TrainerFanClub.pack(timer, gotInitialFans, fanFlags)
  timer = band(math.max(0, math.min(127, tonumber(timer) or 0)), 0x7F)
  local initialBit = gotInitialFans and 0x80 or 0
  local flagsByte = band(tonumber(fanFlags) or 0, 0xFF)
  return band(bor(timer, initialBit, lshift(flagsByte, 8)), 0xFFFF)
end

function TrainerFanClub.getFanFlag(fanFlags, memberId)
  memberId = tonumber(memberId) or 0
  if memberId < 0 or memberId >= 8 then return false end
  return band(rshift(fanFlags, memberId), 1) == 1
end

function TrainerFanClub.setFanFlag(fanFlags, memberId)
  memberId = tonumber(memberId) or 0
  if memberId < 0 or memberId >= 8 then return fanFlags end
  return band(bor(fanFlags, lshift(1, memberId)), 0xFF)
end

function TrainerFanClub.flipFanFlag(fanFlags, memberId)
  memberId = tonumber(memberId) or 0
  if memberId < 0 or memberId >= 8 then return fanFlags end
  return band(bxor(fanFlags, lshift(1, memberId)), 0xFF)
end

function TrainerFanClub.countFans(fanFlags)
  local count = 0
  fanFlags = band(tonumber(fanFlags) or 0, 0xFF)
  for i = 0, TrainerFanClub.NUM_MEMBERS - 1 do
    if band(rshift(fanFlags, i), 1) == 1 then
      count = count + 1
    end
  end
  return count
end

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

function TrainerFanClub.sessionOf(ctx)
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

function TrainerFanClub.getVar(session, ctx, varId)
  session = session or TrainerFanClub.sessionOf(ctx)
  return tonumber(flagsMod().getVar(scriptStore(session, ctx), ctx, varId)) or 0
end

function TrainerFanClub.setVar(session, ctx, varId, value)
  session = session or TrainerFanClub.sessionOf(ctx)
  flagsMod().setVar(scriptStore(session, ctx), ctx, varId, band(tonumber(value) or 0, 0xFFFF))
end

function TrainerFanClub.getFlag(session, ctx, flagId)
  session = session or TrainerFanClub.sessionOf(ctx)
  return flagsMod().getFlag(scriptStore(session, ctx), ctx, flagId)
end

function TrainerFanClub.setFlag(session, ctx, flagId, value)
  session = session or TrainerFanClub.sessionOf(ctx)
  flagsMod().setFlag(scriptStore(session, ctx), ctx, flagId, value)
end

function TrainerFanClub.clearFlag(session, ctx, flagId)
  TrainerFanClub.setFlag(session, ctx, flagId, false)
end

function TrainerFanClub.getFanClubData(session, ctx)
  local raw = TrainerFanClub.getVar(session, ctx, TrainerFanClub.VAR_FANCLUB_FAN_COUNTER)
  return TrainerFanClub.unpack(raw)
end

function TrainerFanClub.setFanClubData(session, ctx, timer, gotInitialFans, fanFlags)
  local packed = TrainerFanClub.pack(timer, gotInitialFans, fanFlags)
  TrainerFanClub.setVar(session, ctx, TrainerFanClub.VAR_FANCLUB_FAN_COUNTER, packed)
end

function TrainerFanClub.getPlayTimeHours(session, ctx)
  session = session or TrainerFanClub.sessionOf(ctx)
  if not session then return 0 end
  local pt = session.playtime or session.playTime
  if type(pt) == "table" and pt.hours ~= nil then
    return tonumber(pt.hours) or 0
  end
  if session.playTimeHours ~= nil then
    return tonumber(session.playTimeHours) or 0
  end
  return 0
end

function TrainerFanClub.setStringVar(ctx, adapters, index, text)
  if adapters and adapters.setStringVar then adapters.setStringVar(index, text) end
  if ctx and ctx.stringVars then ctx.stringVars[index] = text end
end

--- pokefirered/src/trainer_fan_club.c:34 ResetTrainerFanClub
function TrainerFanClub.reset(session, ctx)
  TrainerFanClub.setVar(session, ctx, TrainerFanClub.VAR_FANCLUB_FAN_COUNTER, 0)
  TrainerFanClub.setVar(session, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER, 0)
end

--- pokefirered/src/trainer_fan_club.c:228 IsFanClubMemberFanOfPlayer
function TrainerFanClub.isFanClubMemberFanOfPlayer(session, ctx, memberId)
  local _, _, fanFlags = TrainerFanClub.getFanClubData(session, ctx)
  return TrainerFanClub.getFanFlag(fanFlags, memberId)
end

--- pokefirered/src/trainer_fan_club.c:175 GetNumFansOfPlayerInTrainerFanClub
function TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(session, ctx)
  local _, _, fanFlags = TrainerFanClub.getFanClubData(session, ctx)
  return TrainerFanClub.countFans(fanFlags)
end

--- pokefirered/src/trainer_fan_club.c:98 PlayerGainRandomTrainerFan
function TrainerFanClub.playerGainRandomTrainerFan(session, ctx)
  local timer, gotInitialFans, fanFlags = TrainerFanClub.getFanClubData(session, ctx)
  local Rng = require("src.core.game3.rng")
  local idx = 1

  for i = 1, TrainerFanClub.NUM_MEMBERS do
    local memberId = sGainOrder[i]
    if not TrainerFanClub.getFanFlag(fanFlags, memberId) then
      idx = i
      if (Rng.Random() % 2) ~= 0 then
        fanFlags = TrainerFanClub.setFanFlag(fanFlags, memberId)
        TrainerFanClub.setFanClubData(session, ctx, timer, gotInitialFans, fanFlags)
        return memberId
      end
    end
  end

  local fallbackMember = sGainOrder[idx]
  fanFlags = TrainerFanClub.setFanFlag(fanFlags, fallbackMember)
  TrainerFanClub.setFanClubData(session, ctx, timer, gotInitialFans, fanFlags)
  return fallbackMember
end

--- pokefirered/src/trainer_fan_club.c:131 PlayerLoseRandomTrainerFan
function TrainerFanClub.playerLoseRandomTrainerFan(session, ctx)
  local timer, gotInitialFans, fanFlags = TrainerFanClub.getFanClubData(session, ctx)
  if TrainerFanClub.countFans(fanFlags) == 1 then
    return 0
  end

  local Rng = require("src.core.game3.rng")
  local idx = 1

  for i = 1, TrainerFanClub.NUM_MEMBERS do
    local memberId = sLoseOrder[i]
    if TrainerFanClub.getFanFlag(fanFlags, memberId) then
      idx = i
      if (Rng.Random() % 2) ~= 0 then
        fanFlags = TrainerFanClub.flipFanFlag(fanFlags, memberId)
        TrainerFanClub.setFanClubData(session, ctx, timer, gotInitialFans, fanFlags)
        return memberId
      end
    end
  end

  local fallbackMember = sLoseOrder[idx]
  if TrainerFanClub.getFanFlag(fanFlags, fallbackMember) then
    fanFlags = TrainerFanClub.flipFanFlag(fanFlags, fallbackMember)
  end
  TrainerFanClub.setFanClubData(session, ctx, timer, gotInitialFans, fanFlags)
  return fallbackMember
end

--- pokefirered/src/trainer_fan_club.c:194 TryLoseFansFromPlayTime
function TrainerFanClub.tryLoseFansFromPlayTime(session, ctx)
  local hours = TrainerFanClub.getPlayTimeHours(session)
  if hours < 999 then
    local i = 0
    while true do
      local _, _, fanFlags = TrainerFanClub.getFanClubData(session, ctx)
      if TrainerFanClub.countFans(fanFlags) < 5 then
        TrainerFanClub.setVar(session, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER, hours)
        break
      end
      if i == TrainerFanClub.NUM_MEMBERS then
        break
      end

      local loseTimer = TrainerFanClub.getVar(session, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER)
      if (hours - loseTimer) < 12 then
        break
      end

      TrainerFanClub.playerLoseRandomTrainerFan(session, ctx)
      loseTimer = TrainerFanClub.getVar(session, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER)
      TrainerFanClub.setVar(session, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER, band(loseTimer + 12, 0xFFFF))
      i = i + 1
    end
  end
end

--- pokefirered/src/trainer_fan_club.c:45 TryLoseFansFromPlayTimeAfterLinkBattle
function TrainerFanClub.tryLoseFansFromPlayTimeAfterLinkBattle(session, ctx)
  local _, gotInitialFans, _ = TrainerFanClub.getFanClubData(session, ctx)
  if gotInitialFans then
    TrainerFanClub.tryLoseFansFromPlayTime(session, ctx)
    local hours = TrainerFanClub.getPlayTimeHours(session)
    TrainerFanClub.setVar(session, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER, hours)
  end
end

--- pokefirered/src/trainer_fan_club.c:59 UpdateTrainerFanClubGameClear
function TrainerFanClub.updateTrainerFanClubGameClear(session, ctx)
  local timer, gotInitialFans, fanFlags = TrainerFanClub.getFanClubData(session, ctx)
  if not gotInitialFans then
    gotInitialFans = true
    fanFlags = TrainerFanClub.setFanFlag(fanFlags, TrainerFanClub.MEMBER.MEMBER1)
    fanFlags = TrainerFanClub.setFanFlag(fanFlags, TrainerFanClub.MEMBER.MEMBER2)
    fanFlags = TrainerFanClub.setFanFlag(fanFlags, TrainerFanClub.MEMBER.MEMBER3)
    TrainerFanClub.setFanClubData(session, ctx, timer, gotInitialFans, fanFlags)

    local hours = TrainerFanClub.getPlayTimeHours(session)
    TrainerFanClub.setVar(session, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER, hours)

    TrainerFanClub.clearFlag(session, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_BLACK_BELT)
    TrainerFanClub.clearFlag(session, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_ROCKER)
    TrainerFanClub.clearFlag(session, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_WOMAN)
    TrainerFanClub.clearFlag(session, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_BEAUTY)

    TrainerFanClub.setVar(session, ctx, TrainerFanClub.VAR_MAP_SCENE_SAFFRON_CITY_POKEMON_TRAINER_FAN_CLUB, 1)
  end
end

--- pokefirered/src/trainer_fan_club.c:76 TryGainNewFanFromCounter
function TrainerFanClub.tryGainNewFanFromCounter(session, ctx, counterIdx)
  local timer, gotInitialFans, fanFlags = TrainerFanClub.getFanClubData(session, ctx)
  counterIdx = tonumber(counterIdx) or 0
  local inc = sCounterIncrements[counterIdx] or 0
  local scene = TrainerFanClub.getVar(session, ctx, TrainerFanClub.VAR_MAP_SCENE_SAFFRON_CITY_POKEMON_TRAINER_FAN_CLUB)

  if scene == 2 then
    if timer + inc >= 20 then
      if TrainerFanClub.countFans(fanFlags) < 3 then
        TrainerFanClub.playerGainRandomTrainerFan(session, ctx)
        local _unused, newGotInitial, newFanFlags = TrainerFanClub.getFanClubData(session, ctx)
        gotInitialFans = newGotInitial
        fanFlags = newFanFlags
        timer = 0
      else
        timer = 20
      end
    else
      timer = math.min(127, timer + inc)
    end
    TrainerFanClub.setFanClubData(session, ctx, timer, gotInitialFans, fanFlags)
  end

  return timer
end

--- pokefirered/src/trainer_fan_club.c:240 BufferFanClubTrainerName
function TrainerFanClub.bufferFanClubTrainerName(session, ctx, adapters, memberId)
  memberId = tonumber(memberId) or 0
  local whichNPCTrainer = 0
  local whichLinkTrainer = 0

  if memberId == TrainerFanClub.MEMBER.MEMBER1 then
    whichNPCTrainer = 0
    whichLinkTrainer = 0
  elseif memberId == TrainerFanClub.MEMBER.MEMBER5 then
    whichNPCTrainer = 1
    whichLinkTrainer = 0
  elseif memberId == TrainerFanClub.MEMBER.MEMBER6 then
    whichNPCTrainer = 0
    whichLinkTrainer = 1
  elseif memberId == TrainerFanClub.MEMBER.MEMBER7 then
    whichNPCTrainer = 2
    whichLinkTrainer = 1
  else
    whichNPCTrainer = 0
    whichLinkTrainer = 0
  end

  session = session or TrainerFanClub.sessionOf()
  local linkRecords = session and (session.linkBattleRecords or (session.linkRecords and session.linkRecords.entries))
  local entry = type(linkRecords) == "table" and linkRecords[whichLinkTrainer + 1] or nil
  local linkName = (entry and type(entry.name) == "string" and entry.name) or ""

  local resultName
  if linkName == "" then
    if whichNPCTrainer == 1 then
      resultName = "LT. SURGE"
    elseif whichNPCTrainer == 2 then
      resultName = "KOGA"
    else
      resultName = (session and session.rivalName) or "BLUE"
    end
  else
    resultName = linkName:sub(1, 7)
  end

  TrainerFanClub.setStringVar(ctx, adapters, 1, resultName)
  return resultName
end

--- pokefirered/src/trainer_fan_club.c:317 UpdateTrainerFansAfterLinkBattle
function TrainerFanClub.updateTrainerFansAfterLinkBattle(session, ctx, outcome)
  local scene = TrainerFanClub.getVar(session, ctx, TrainerFanClub.VAR_MAP_SCENE_SAFFRON_CITY_POKEMON_TRAINER_FAN_CLUB)
  if scene == 2 then
    TrainerFanClub.tryLoseFansFromPlayTimeAfterLinkBattle(session, ctx)
    if outcome == "won" or outcome == 1 or outcome == 0x01 then -- B_OUTCOME_WON
      TrainerFanClub.playerGainRandomTrainerFan(session, ctx)
    else
      TrainerFanClub.playerLoseRandomTrainerFan(session, ctx)
    end
  end
end

--- pokefirered/src/trainer_fan_club.c:340 SetPlayerGotFirstFans
function TrainerFanClub.setPlayerGotFirstFans(session, ctx)
  local timer, _, fanFlags = TrainerFanClub.getFanClubData(session, ctx)
  TrainerFanClub.setFanClubData(session, ctx, timer, true, fanFlags)
end

return TrainerFanClub
