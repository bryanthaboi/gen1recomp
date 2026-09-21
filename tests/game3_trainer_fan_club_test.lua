#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local TrainerFanClub = require("src.core.game3.trainer_fan_club")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Flags = require("src.core.game3.scripting.flags")
local Rng = require("src.core.game3.rng")

local passed = 0
local failed = 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, (msg or "equal") .. " (got " .. tostring(a) .. ", expected " .. tostring(b) .. ")")
end

local function makeSession()
  local s = {
    flags = {},
    vars = {},
    stringVars = {},
    specialVars = {},
    playtime = { hours = 10, minutes = 0, seconds = 0 },
    rivalName = "GARY",
    linkBattleRecords = {},
  }
  return s
end

local function makeCtx(session)
  return {
    session = session,
    stringVars = session.stringVars,
    specialVars = session.specialVars,
  }
end

print("=== 1. Bit Packing and Unpacking ===")
do
  local raw0 = 0
  local timer, gotInitial, flags = TrainerFanClub.unpack(raw0)
  eq(timer, 0, "unpack raw 0 timer")
  eq(gotInitial, false, "unpack raw 0 gotInitial")
  eq(flags, 0, "unpack raw 0 flags")

  local packed = TrainerFanClub.pack(15, true, 0x07)
  -- 15 | 0x80 | (0x07 << 8) = 15 | 128 | 1792 = 1935 (0x078F)
  eq(packed, 0x078F, "pack timer=15, gotInitial=true, flags=0x07")
  local t2, g2, f2 = TrainerFanClub.unpack(packed)
  eq(t2, 15, "unpacked timer 15")
  eq(g2, true, "unpacked gotInitial true")
  eq(f2, 0x07, "unpacked flags 0x07")

  -- Timer clamping at 127 (7 bits) and not overflowing into bit 7
  local overflowPacked = TrainerFanClub.pack(200, false, 0x00)
  local tOver, gOver, _ = TrainerFanClub.unpack(overflowPacked)
  eq(tOver, 127, "timer clamped to 127 on pack")
  eq(gOver, false, "timer does not overflow into gotInitialFans bit")
end

print("=== 2. New Game Reset ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)
  TrainerFanClub.setFanClubData(s, ctx, 10, true, 0xFF)
  TrainerFanClub.setVar(s, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER, 50)

  TrainerFanClub.reset(s, ctx)
  eq(TrainerFanClub.getVar(s, ctx, TrainerFanClub.VAR_FANCLUB_FAN_COUNTER), 0, "reset VAR_FANCLUB_FAN_COUNTER")
  eq(TrainerFanClub.getVar(s, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER), 0, "reset VAR_FANCLUB_LOSE_FAN_TIMER")
end

print("=== 3. Game Clear Fan Setup ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)
  s.playtime.hours = 25

  -- Set hide flags initially
  Flags.setFlag(s, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_BLACK_BELT, true)
  Flags.setFlag(s, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_ROCKER, true)
  Flags.setFlag(s, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_WOMAN, true)
  Flags.setFlag(s, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_BEAUTY, true)

  TrainerFanClub.updateTrainerFanClubGameClear(s, ctx)

  local timer, gotInitial, fanFlags = TrainerFanClub.getFanClubData(s, ctx)
  eq(gotInitial, true, "gotInitialFans set on game clear")
  eq(TrainerFanClub.countFans(fanFlags), 3, "player has 3 initial fans")
  eq(TrainerFanClub.isFanClubMemberFanOfPlayer(s, ctx, 0), true, "Member 1 is fan")
  eq(TrainerFanClub.isFanClubMemberFanOfPlayer(s, ctx, 1), true, "Member 2 is fan")
  eq(TrainerFanClub.isFanClubMemberFanOfPlayer(s, ctx, 2), true, "Member 3 is fan")
  eq(TrainerFanClub.isFanClubMemberFanOfPlayer(s, ctx, 3), false, "Member 4 is not fan")

  eq(Flags.getFlag(s, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_BLACK_BELT), false, "Black belt unhidden")
  eq(Flags.getFlag(s, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_ROCKER), false, "Rocker unhidden")
  eq(Flags.getFlag(s, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_WOMAN), false, "Woman unhidden")
  eq(Flags.getFlag(s, ctx, TrainerFanClub.FLAG_HIDE_SAFFRON_FAN_CLUB_BEAUTY), false, "Beauty unhidden")

  eq(TrainerFanClub.getVar(s, ctx, TrainerFanClub.VAR_MAP_SCENE_SAFFRON_CITY_POKEMON_TRAINER_FAN_CLUB), 1, "map scene set to 1")
  eq(TrainerFanClub.getVar(s, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER), 25, "lose timer set to playtime hours")

  -- Verify idempotent / doesn't re-run if already got initial fans
  TrainerFanClub.setFanFlag(fanFlags, 3) -- add extra fan
  TrainerFanClub.setVar(s, ctx, TrainerFanClub.VAR_MAP_SCENE_SAFFRON_CITY_POKEMON_TRAINER_FAN_CLUB, 2)
  TrainerFanClub.updateTrainerFanClubGameClear(s, ctx)
  eq(TrainerFanClub.getVar(s, ctx, TrainerFanClub.VAR_MAP_SCENE_SAFFRON_CITY_POKEMON_TRAINER_FAN_CLUB), 2, "scene stays 2 on subsequent calls")
end

print("=== 4. Random Gain and Lose ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)

  -- Seed RNG to known state
  Rng.seedNewGame({ seed = 12345 })

  -- Start with initial fans (0, 1, 2)
  TrainerFanClub.updateTrainerFanClubGameClear(s, ctx)
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 3, "starting 3 fans")

  -- Gain a fan
  local gained = TrainerFanClub.playerGainRandomTrainerFan(s, ctx)
  check(gained >= 0 and gained < 8, "gained valid member id: " .. tostring(gained))
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 4, "fan count now 4")
  eq(TrainerFanClub.isFanClubMemberFanOfPlayer(s, ctx, gained), true, "gained member is fan")

  -- Lose a fan
  local lost = TrainerFanClub.playerLoseRandomTrainerFan(s, ctx)
  check(lost >= 0 and lost < 8, "lost valid member id: " .. tostring(lost))
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 3, "fan count now 3")
  eq(TrainerFanClub.isFanClubMemberFanOfPlayer(s, ctx, lost), false, "lost member is not fan")

  -- Cannot drop below 1 fan
  TrainerFanClub.setFanClubData(s, ctx, 0, true, 0x01) -- only member 0 is fan
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 1, "exactly 1 fan")
  local cantLose = TrainerFanClub.playerLoseRandomTrainerFan(s, ctx)
  eq(cantLose, 0, "returns 0 when attempting to lose from 1 fan")
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 1, "still has 1 fan")
end

print("=== 5. Playtime Decay ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)

  -- Less than 5 fans: no decay, syncs timer
  s.playtime.hours = 100
  TrainerFanClub.setFanClubData(s, ctx, 0, true, 0x0F) -- 4 fans
  TrainerFanClub.setVar(s, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER, 20)

  TrainerFanClub.tryLoseFansFromPlayTime(s, ctx)
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 4, "fans not lost when count < 5")
  eq(TrainerFanClub.getVar(s, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER), 100, "lose timer synced to playtime")

  -- 6 fans, 30 hours elapsed since lose timer (2 decay steps of 12 hours)
  TrainerFanClub.setFanClubData(s, ctx, 0, true, 0x3F) -- 6 fans (0,1,2,3,4,5)
  TrainerFanClub.setVar(s, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER, 70)
  s.playtime.hours = 100 -- delta = 30 hours >= 24 hours (2 steps)

  TrainerFanClub.tryLoseFansFromPlayTime(s, ctx)
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 4, "lost 2 fans down to 4")
  eq(TrainerFanClub.getVar(s, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER), 100, "lose timer synced to 100")

  -- Over 999 hours cap: no decay evaluated
  s.playtime.hours = 1000
  TrainerFanClub.setFanClubData(s, ctx, 0, true, 0xFF) -- 8 fans
  TrainerFanClub.setVar(s, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER, 100)
  TrainerFanClub.tryLoseFansFromPlayTime(s, ctx)
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 8, "no decay when playtime >= 999")
end

print("=== 6. Counter Increments (Lance's Room) ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)

  -- Scene != 2: counter does not advance
  TrainerFanClub.setVar(s, ctx, TrainerFanClub.VAR_MAP_SCENE_SAFFRON_CITY_POKEMON_TRAINER_FAN_CLUB, 1)
  TrainerFanClub.setFanClubData(s, ctx, 0, true, 0x03) -- 2 fans
  local t = TrainerFanClub.tryGainNewFanFromCounter(s, ctx, 0)
  eq(t, 0, "counter doesn't increment when scene != 2")

  -- Scene == 2: counter advances
  TrainerFanClub.setVar(s, ctx, TrainerFanClub.VAR_MAP_SCENE_SAFFRON_CITY_POKEMON_TRAINER_FAN_CLUB, 2)
  t = TrainerFanClub.tryGainNewFanFromCounter(s, ctx, 0) -- arg 0: inc 2
  eq(t, 2, "counter incremented by 2")

  -- Fast-forward timer to 18
  TrainerFanClub.setFanClubData(s, ctx, 18, true, 0x03) -- 2 fans
  t = TrainerFanClub.tryGainNewFanFromCounter(s, ctx, 0) -- 18 + 2 = 20 -> gain fan and reset
  eq(t, 0, "counter resets to 0 when fan gained at threshold 20")
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 3, "fan count grew to 3")

  -- At 3 fans: reaches 20 but caps at 20 without gaining fan
  TrainerFanClub.setFanClubData(s, ctx, 18, true, 0x07) -- 3 fans
  t = TrainerFanClub.tryGainNewFanFromCounter(s, ctx, 0)
  eq(t, 20, "counter capped at 20 when fans >= 3")
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 3, "fan count stays 3")
end

print("=== 7. Buffer Trainer Name ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)
  s.rivalName = "BLUE"
  local adapters = {
    setStringVar = function(idx, val)
      s.stringVars[idx] = val
    end,
  }

  -- Fallbacks without link records
  TrainerFanClub.bufferFanClubTrainerName(s, ctx, adapters, TrainerFanClub.MEMBER.MEMBER1)
  eq(s.stringVars[1], "BLUE", "Member 1 buffers Rival")

  TrainerFanClub.bufferFanClubTrainerName(s, ctx, adapters, TrainerFanClub.MEMBER.MEMBER5)
  eq(s.stringVars[1], "LT. SURGE", "Member 5 buffers LT. SURGE")

  TrainerFanClub.bufferFanClubTrainerName(s, ctx, adapters, TrainerFanClub.MEMBER.MEMBER7)
  eq(s.stringVars[1], "KOGA", "Member 7 buffers KOGA")

  -- With link records
  s.linkBattleRecords = {
    { name = "ASH", wins = 5, losses = 1 },
    { name = "MISTY", wins = 2, losses = 3 },
  }

  TrainerFanClub.bufferFanClubTrainerName(s, ctx, adapters, TrainerFanClub.MEMBER.MEMBER1)
  eq(s.stringVars[1], "ASH", "Member 1 buffers Link Record 0 (ASH)")

  TrainerFanClub.bufferFanClubTrainerName(s, ctx, adapters, TrainerFanClub.MEMBER.MEMBER6)
  eq(s.stringVars[1], "MISTY", "Member 6 buffers Link Record 1 (MISTY)")
end

print("=== 8. Script Specials Execution via Natives ===")
do
  local s = makeSession()
  local ctx = makeCtx(s)
  local Space = require("src.core.game3.scripting.space")
  Space.store = s

  local adapters = {
    setStringVar = function(idx, val)
      s.stringVars[idx] = val
    end,
  }

  -- 1. Script_UpdateTrainerFanClubGameClear (0xA9)
  s.playtime.hours = 12
  Natives.special(ctx, Std.SPECIAL.Script_UpdateTrainerFanClubGameClear, adapters)
  eq(TrainerFanClub.getNumFansOfPlayerInTrainerFanClub(s, ctx), 3, "special 0xA9 granted 3 fans")

  -- 2. Script_GetNumFansOfPlayerInTrainerFanClub (0xA4)
  Natives.special(ctx, Std.SPECIAL.Script_GetNumFansOfPlayerInTrainerFanClub, adapters)
  eq(Flags.getVar(s, ctx, 0x800D), 3, "special 0xA4 set VAR_RESULT to 3")

  -- 3. Script_IsFanClubMemberFanOfPlayer (0xA3)
  Flags.setVar(s, ctx, 0x8004, 0) -- Member 1
  Natives.special(ctx, Std.SPECIAL.Script_IsFanClubMemberFanOfPlayer, adapters)
  eq(Flags.getVar(s, ctx, 0x800D), 1, "special 0xA3 member 0 is fan (VAR_RESULT = 1)")

  Flags.setVar(s, ctx, 0x8004, 5) -- Member 6
  Natives.special(ctx, Std.SPECIAL.Script_IsFanClubMemberFanOfPlayer, adapters)
  eq(Flags.getVar(s, ctx, 0x800D), 0, "special 0xA3 member 5 is not fan (VAR_RESULT = 0)")

  -- 4. Script_BufferFanClubTrainerName (0xA5)
  Flags.setVar(s, ctx, 0x8004, 4) -- Member 5 (Rocker)
  Natives.special(ctx, Std.SPECIAL.Script_BufferFanClubTrainerName, adapters)
  eq(s.stringVars[1], "LT. SURGE", "special 0xA5 buffered LT. SURGE to stringVars[1]")

  -- 5. Script_TryGainNewFanFromCounter (0xAA)
  Flags.setVar(s, ctx, TrainerFanClub.VAR_MAP_SCENE_SAFFRON_CITY_POKEMON_TRAINER_FAN_CLUB, 2)
  Flags.setVar(s, ctx, 0x8004, 0) -- increment index 0 (+2)
  Natives.special(ctx, Std.SPECIAL.Script_TryGainNewFanFromCounter, adapters)
  eq(Flags.getVar(s, ctx, 0x800D), 2, "special 0xAA advanced timer to 2")

  -- 6. Script_SetPlayerGotFirstFans (0xA8)
  TrainerFanClub.setFanClubData(s, ctx, 0, false, 0)
  Natives.special(ctx, Std.SPECIAL.Script_SetPlayerGotFirstFans, adapters)
  local _, gotFirst, _ = TrainerFanClub.getFanClubData(s, ctx)
  eq(gotFirst, true, "special 0xA8 set gotInitialFans")

  -- 7. Script_TryLoseFansFromPlayTime (0xA7)
  s.playtime.hours = 50
  Natives.special(ctx, Std.SPECIAL.Script_TryLoseFansFromPlayTime, adapters)
  eq(TrainerFanClub.getVar(s, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER), 50, "special 0xA7 synced lose timer")

  -- 8. Script_TryLoseFansFromPlayTimeAfterLinkBattle (0xA6)
  s.playtime.hours = 75
  Natives.special(ctx, Std.SPECIAL.Script_TryLoseFansFromPlayTimeAfterLinkBattle, adapters)
  eq(TrainerFanClub.getVar(s, ctx, TrainerFanClub.VAR_FANCLUB_LOSE_FAN_TIMER), 75, "special 0xA6 synced lose timer")
end

print(string.format("\nTotal: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
