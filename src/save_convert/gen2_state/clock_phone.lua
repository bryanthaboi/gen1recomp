local M = {}
local Syms = require("src.save_convert.Gen2Syms")
local Gen2EngineFlags = require("src.save_convert.Gen2EngineFlags")

M.KEY = "cartTimers"

M.coverage = {
  { both = { "wStartDay", "wRTC" }, mode = "modeled",
    keys = { "rtc.startDay", "rtc.startMinute", "rtc.startSecond" }, asm = "pokegold ram/wram.asm:2325" },
  { gs = { "wRTC", len = 4 }, crystal = { "wRTC", "wDST" }, mode = "modeled",
    keys = { "rtc.saved" }, asm = "pokegold engine/rtc/rtc.asm:63" },
  { gs = { "wDSTBackupDay", "wDST" }, mode = "static",
    keys = { "cartTimers.clock" }, why = "written only by UpdateTimePredef from Mom's DSTChecks, which the port does not run" },
  { gs = { "wDST", "wGameTimeCap" }, crystal = { "wDST", len = 1 }, mode = "modeled",
    keys = { "rtc.dst" }, asm = "pokegold engine/rtc/timeset.asm:537" },
  { both = { "wGameTimeCap", len = 1 }, mode = "static",
    keys = { "cartTimers.clock", "playTime.capped" }, why = "bit 0 is GAME_TIME_CAPPED, which Save.tickPlayTime sets at 999:59:59; the other bits are never written" },
  { both = { "wCurDay", "wObjectFollow_Leader" }, mode = "modeled",
    keys = { "rtc.curDay" }, asm = "pokegold home/time.asm:122" },

  { both = { "wDailyResetTimer", len = 2 }, mode = "modeled",
    keys = { "dailyReset", "dailyResetDay" }, asm = "pokegold engine/overworld/time.asm:89" },
  { gs = { "wDailyFlags1", "wTimerEventStartDay" }, crystal = { "wDailyFlags1", "wSwarmFlags" }, mode = "modeled",
    keys = { "engineFlags", "dailyFlags.swarm" }, asm = "pokegold data/events/engine_flags.asm:107" },
  { crystal = { "wUnusedDailyFlag", "wTimerEventStartDay" }, mode = "static",
    keys = { "cartTimers.daily" }, why = "no routine sets wUnusedDailyFlag; CheckDailyResetTimer only clears it" },
  { both = { "wTimerEventStartDay", "wFruitTreeFlags" }, mode = "modeled",
    keys = { "pokerusStartDay" }, asm = "pokegold engine/overworld/time.asm:143" },
  { both = { "wFruitTreeFlags", "wLuckyNumberDayTimer" }, mode = "modeled",
    keys = { "fruitTrees" }, asm = "pokegold engine/events/fruit_trees.asm:71" },
  { both = { "wLuckyNumberDayTimer", "wSpecialPhoneCallID" }, mode = "modeled",
    keys = { "luckyNumberReset" }, asm = "pokegold engine/overworld/time.asm:191" },
  { both = { "wSpecialPhoneCallID", "wBugContestStartTime" }, mode = "modeled",
    keys = { "phone.specialCall" }, asm = "pokegold ram/wram.asm:2603" },
  { gs = { "wUnusedTwoDayTimerOn", "wStepCount" }, crystal = { "wUnusedTwoDayTimerOn", "wBuenasPassword" },
    mode = "static", keys = { "cartTimers.daily" },
    why = "the two-day timer has no setter (SetUnusedTwoDayTimer is unreferenced) and the rest is mobile scratch" },
  { crystal = { "wBuenasPassword", "wDailyRematchFlags" }, mode = "modeled",
    keys = { "crystal.buenaPassword" }, asm = "pokecrystal ram/wram.asm:3342" },
  { crystal = { "wDailyRematchFlags", "wKenjiBreakTimer" }, mode = "modeled",
    keys = { "engineFlags" }, asm = "pokecrystal data/events/engine_flags.asm:136" },
  { crystal = { "wKenjiBreakTimer", "wYanmaMapGroup" }, mode = "modeled",
    keys = { "crystal.kenjiBreak" }, asm = "pokecrystal engine/overworld/time.asm:136" },
  { crystal = { "wYanmaMapGroup", "wPlayerMonSelection" }, mode = "modeled",
    keys = { "swarmMaps.YANMA" }, asm = "pokecrystal engine/events/specials.asm:290" },
  { crystal = { "wPlayerMonSelection", "wStepCount" }, mode = "static",
    keys = { "cartTimers.daily" }, why = "mobile adapter scratch, written only by mobile/mobile_40.asm" },

  { both = { "wStepCount", len = 1 }, mode = "modeled", keys = { "stepCount" }, asm = "pokegold ram/wram.asm:2612" },
  { both = { "wPoisonStepCount", "wHappinessStepCount" }, mode = "modeled",
    keys = { "poisonStepCount" }, asm = "pokegold ram/wram.asm:2613" },
  { both = { "wHappinessStepCount", "wParkBallsRemaining" }, mode = "modeled",
    keys = { "happinessStepCount" }, asm = "pokegold ram/wram.asm:2615" },
  { both = { "wParkBallsRemaining", len = 1 }, mode = "modeled",
    keys = { "bugContest.balls" }, asm = "pokegold engine/events/bug_contest/contest.asm:5" },
  { both = { "wSafariTimeRemaining", "wPhoneList" }, mode = "static",
    keys = { "cartTimers.steps" }, why = "Johto has no Safari Zone; only the unreferenced safari menu reads it" },
  { both = { "wPhoneList", "wLuckyNumberShowFlag" }, mode = "modeled",
    keys = { "phone.list", "phoneContacts" }, asm = "pokegold ram/wram.asm:2622" },
  { both = { "wLuckyNumberShowFlag", "wLuckyIDNumber" }, mode = "modeled",
    keys = { "engineFlags" }, asm = "pokegold data/events/engine_flags.asm:103" },
  { both = { "wLuckyIDNumber", "wRepelEffect" }, mode = "modeled",
    keys = { "luckyNumber" }, asm = "pokegold engine/menus/intro_menu.asm:225" },
  { both = { "wRepelEffect", "wBikeStep" }, mode = "modeled", keys = { "repelSteps" }, asm = "pokegold ram/wram.asm:2630" },
  { gs = { "wBikeStep", "wCurMapData" }, crystal = { "wBikeStep", "wKurtApricornQuantity" }, mode = "modeled",
    keys = { "bikeStep" }, asm = "pokegold engine/overworld/events.asm:1267" },
  { crystal = { "wKurtApricornQuantity", "wCurMapData" }, mode = "modeled",
    keys = { "kurtApricornQuantity" }, asm = "pokecrystal ram/wram.asm:3376" },
}

M.sram = {
  { both = { "sRTCStatusFlags", "sLuckyNumberDay" }, mode = "static", keys = { "cartTimers.sram" },
    why = "only StartClock/RecordRTCStatus and SaveRTC touch it, and the port has no RTC hardware" },
  { both = { "sLuckyNumberDay", len = 3 }, mode = "modeled", keys = { "luckyNumber" },
    asm = "pokegold engine/menus/intro_menu.asm:225" },
}

local DAY_WRAP = 140
local FRUIT_TREES = 30
local CONTACTS = 10

-- pokegold data/events/engine_flags.asm:103
-- pokecrystal data/events/engine_flags.asm:104
local LUCKY_SHOW_GS = Gen2EngineFlags.id("gold", "ENGINE_LUCKY_NUMBER_SHOW")
local LUCKY_SHOW_CRYSTAL = Gen2EngineFlags.id("crystal", "ENGINE_LUCKY_NUMBER_SHOW")
-- pokegold data/events/engine_flags.asm:107
local DAILY_GS = Gen2EngineFlags.run("gold", "ENGINE_KURT_MAKING_BALLS", "ENGINE_INDIGO_PLATEAU_RIVAL_FIGHT")
-- pokecrystal data/events/engine_flags.asm:108
local DAILY_CRYSTAL = Gen2EngineFlags.run("crystal", "ENGINE_KURT_MAKING_BALLS", "ENGINE_DAILY_MOVE_TUTOR")
-- pokecrystal data/events/engine_flags.asm:124
local BUENA_FLAG = Gen2EngineFlags.id("crystal", "ENGINE_BUENAS_PASSWORD")
-- pokegold constants/ram_constants.asm:305
local SWARM_BIT = 2
-- pokecrystal data/events/engine_flags.asm:136, :161, :172
local CRYSTAL_ARRAYS = {
  { label = "wDailyRematchFlags", first = "ENGINE_JACK_READY_FOR_REMATCH", count = 24 },
  { label = "wDailyPhoneItemFlags", first = "ENGINE_BEVERLY_HAS_NUGGET", count = 10 },
  { label = "wDailyPhoneTimeOfDayFlags", first = "ENGINE_JACK_MONDAY_MORNING", count = 24 },
}
for _, array in ipairs(CRYSTAL_ARRAYS) do array.first = Gen2EngineFlags.id("crystal", array.first) end

local function u8(t, o) return t[o] or 0 end
local function bit(b, n) return math.floor(b / 2 ^ n) % 2 == 1 end
local function setBit(b, n, on)
  if bit(b, n) == on then return b end
  return on and b + 2 ^ n or b - 2 ^ n
end
local function be2(t, o) return u8(t, o) * 256 + u8(t, o + 1) end

local function int(v, default)
  v = tonumber(v)
  if v == nil then return default end
  return math.floor(v)
end

local function hexOf(t, ranges)
  local out = {}
  for _, r in ipairs(ranges) do
    for i = r[1], r[2] - 1 do out[#out + 1] = ("%02X"):format(u8(t, i)) end
  end
  return table.concat(out)
end

local function size(ranges)
  local n = 0
  for _, r in ipairs(ranges) do n = n + r[2] - r[1] end
  return n
end

local function unhex(t, ranges, s)
  if type(s) ~= "string" or #s ~= size(ranges) * 2 or s:find("[^%x]") then return false end
  local k = 1
  for _, r in ipairs(ranges) do
    for i = r[1], r[2] - 1 do
      t[i] = tonumber(s:sub(k, k + 1), 16)
      k = k + 2
    end
  end
  return true
end

local function byteOf(ctx, v, what)
  local n = int(v, 0)
  if n < 0 or n > 255 then ctx.util.refuse(("%s is %s, which does not fit its one cartridge byte"):format(what, tostring(v))) end
  return n
end

local function wordOf(ctx, v, what)
  local n = int(v, 0)
  if n < 0 or n > 0xFFFF then ctx.util.refuse(("%s is %s, which does not fit its two cartridge bytes"):format(what, tostring(v))) end
  return n
end

function M.ranges(S, crystal)
  local a = {
    { S.wStartDay, S.wGameTimeHours },
    { S.wCurDay, S.wObjectFollow_Leader },
  }
  local b
  if crystal then
    b = {
      { S.wDailyResetTimer, S.wSwarmFlags },
      { S.wUnusedDailyFlag, S.wBugContestStartTime },
      { S.wUnusedTwoDayTimerOn, S.wStepCount },
    }
  else
    b = {
      { S.wDailyResetTimer, S.wBugContestStartTime },
      { S.wUnusedTwoDayTimerOn, S.wStepCount },
    }
  end
  local c = { { S.wStepCount, S.wCurMapData } }
  local sram = { { S.sRTCStatusFlags, S.sLuckyIDNumber + 2 } }
  return { clock = a, daily = b, steps = c, sram = sram }
end

function M.dailyReset(save)
  if save.version ~= "crystal" then return end
  local carrier = save[M.KEY]
  if type(carrier) ~= "table" then return end
  local S, t = Syms.crystal, {}
  local ranges = M.ranges(S, true).daily
  if not unhex(t, ranges, carrier.daily) then return end
  t[S.wUnusedDailyFlag] = 0
  for _, array in ipairs(CRYSTAL_ARRAYS) do
    for i = 0, 3 do t[S[array.label] + i] = 0 end
  end
  carrier.daily = hexOf(t, ranges)
end

local function flagsOf(save)
  return type(save.engineFlags) == "table" and save.engineFlags or {}
end

local function timerPair(t, at)
  local remaining, day = u8(t, at), u8(t, at + 1)
  if remaining == 0 and day == 0 then return nil end
  return { remaining = remaining, day = day }
end

local function putTimer(ctx, t, at, timer, what)
  local want = type(timer) == "table" and timer or {}
  local remaining = byteOf(ctx, want.remaining or 0, what .. " remaining days")
  local day = byteOf(ctx, want.day or 0, what .. " start day")
  if u8(t, at) ~= remaining or u8(t, at + 1) ~= day then t[at], t[at + 1] = remaining, day end
end

function M.dailyTimer(t, S, save)
  local have = timerPair(t, S.wDailyResetTimer)
  local timer = type(save.dailyReset) == "table" and save.dailyReset or nil
  local stamp = save.dailyResetDay
  if stamp == nil then return timer end
  stamp = int(stamp, 0) % DAY_WRAP
  local haveDay = have and have.day or nil
  if timer and timer.day ~= nil and int(timer.day) ~= haveDay then return timer end
  if stamp == haveDay then return timer or have end
  return { remaining = timer and timer.remaining or 1, day = stamp }
end

local function nonzero(b) if b ~= 0 then return b end end

function M.stage(rtc)
  return {
    day = int(rtc and rtc.day, 0) % DAY_WRAP,
    hour = int(rtc and rtc.hour, 0) % 24,
    minute = int(rtc and rtc.minute, 0) % 60,
    second = 0,
  }
end


local function decodeClock(ctx, t)
  local S = ctx.S
  return {
    startDay = nonzero(u8(t, S.wStartDay)),
    startMinute = u8(t, S.wStartHour) * 60 + u8(t, S.wStartMinute),
    startSecond = nonzero(u8(t, S.wStartSecond)),
    -- pokegold constants/ram_constants.asm:77
    dst = bit(u8(t, S.wDST), 7),
    saved = { day = u8(t, S.wRTC), hour = u8(t, S.wRTC + 1), minute = u8(t, S.wRTC + 2), second = u8(t, S.wRTC + 3) },
    curDay = u8(t, S.wCurDay),
  }
end

local function dailyIds(ctx)
  return ctx.crystal and DAILY_CRYSTAL or DAILY_GS
end

local function luckyShowId(ctx)
  return ctx.crystal and LUCKY_SHOW_CRYSTAL or LUCKY_SHOW_GS
end

local function eachFlagBit(ctx, fn)
  local S = ctx.S
  for n, id in pairs(dailyIds(ctx)) do
    fn(S.wDailyFlags1 + math.floor(n / 8), n % 8, id)
  end
  fn(S.wLuckyNumberShowFlag, 0, luckyShowId(ctx))
  if ctx.crystal then
    for _, a in ipairs(CRYSTAL_ARRAYS) do
      for i = 0, a.count - 1 do fn(S[a.label] + math.floor(i / 8), i % 8, a.first + i) end
    end
  end
end

local function readPair(ctx, t)
  local S = ctx.S
  local g, n = u8(t, S.wYanmaMapGroup), u8(t, S.wYanmaMapNumber)
  if g == 0 and n == 0 then return nil end
  return ctx.x.maps and ctx.x.maps[g * 256 + n] or nil
end

function M.decode(ctx, decoded)
  local t, S = ctx.t, ctx.S
  local R = M.ranges(S, ctx.crystal)

  decoded.rtc = decodeClock(ctx, t)

  decoded.dailyReset = timerPair(t, S.wDailyResetTimer)
  decoded.dailyResetDay = decoded.dailyReset and decoded.dailyReset.day or nil
  local flags = type(decoded.engineFlags) == "table" and decoded.engineFlags or {}
  decoded.engineFlags = flags
  eachFlagBit(ctx, function(at, n, id)
    if bit(u8(t, at), n) then flags[id] = true end
  end)
  if not ctx.crystal and bit(u8(t, S.wDailyFlags1), SWARM_BIT) then
    decoded.dailyFlags = type(decoded.dailyFlags) == "table" and decoded.dailyFlags or {}
    decoded.dailyFlags.swarm = true
  end
  decoded.pokerusStartDay = nonzero(u8(t, S.wTimerEventStartDay))
  local trees
  for i = 0, FRUIT_TREES - 1 do
    if bit(u8(t, S.wFruitTreeFlags + math.floor(i / 8)), i % 8) then
      trees = trees or {}
      trees[i + 1] = true
    end
  end
  decoded.fruitTrees = trees
  decoded.luckyNumberReset = timerPair(t, S.wLuckyNumberDayTimer)

  local list, any = {}, u8(t, S.wSpecialPhoneCallID) ~= 0
  local contacts = {}
  for i = 1, CONTACTS do
    list[i] = u8(t, S.wPhoneList + i - 1)
    if list[i] ~= 0 then
      any = true
      contacts[list[i]] = true
    end
  end
  if any then
    decoded.phone = { list = list, specialCall = u8(t, S.wSpecialPhoneCallID), timeCycles = 0, delayMins = 20 }
  else
    decoded.phone = nil
  end
  decoded.phoneContacts = contacts

  if ctx.crystal then
    decoded.crystal = type(decoded.crystal) == "table" and decoded.crystal or {}
    local word, balance = u8(t, S.wBuenasPassword), u8(t, S.wBlueCardBalance)
    local rolled = bit(u8(t, S.wDailyFlags2), 7)
    decoded.crystal.buenaPassword = {
      prizesToday = 0, streak = 0,
      word = (word ~= 0 or rolled) and word or nil,
      balance = nonzero(balance),
      day = rolled and u8(t, S.wCurDay) or nil,
    }
    decoded.crystal.kenjiBreak = nonzero(u8(t, S.wKenjiBreakTimer))
    local yanma = readPair(ctx, t)
    if yanma ~= nil then
      decoded.swarmMaps = type(decoded.swarmMaps) == "table" and decoded.swarmMaps or {}
      decoded.swarmMaps.YANMA = yanma
    end
    decoded.kurtApricornQuantity = nonzero(u8(t, S.wKurtApricornQuantity))
  end

  decoded.stepCount = nonzero(u8(t, S.wStepCount))
  decoded.poisonStepCount = nonzero(u8(t, S.wPoisonStepCount))
  decoded.happinessStepCount = nonzero(u8(t, S.wHappinessStepCount))
  local balls = u8(t, S.wParkBallsRemaining)
  if balls ~= 0 then
    decoded.bugContest = type(decoded.bugContest) == "table" and decoded.bugContest or {}
    decoded.bugContest.balls = balls
  end
  local lucky = be2(t, S.wLuckyIDNumber)
  if lucky == 0 and decoded.luckyNumberReset == nil then lucky = nil end
  decoded.luckyNumber = lucky
  decoded.repelSteps = nonzero(u8(t, S.wRepelEffect))
  decoded.bikeStep = nonzero(be2(t, S.wBikeStep))

  decoded[M.KEY] = {
    clock = hexOf(t, R.clock), daily = hexOf(t, R.daily), steps = hexOf(t, R.steps), sram = hexOf(t, R.sram),
  }
end


local function putClock(ctx, t, rtc, carried)
  local S = ctx.S
  local have = decodeClock(ctx, t)
  if int(rtc.startDay, 0) ~= (have.startDay or 0) then t[S.wStartDay] = byteOf(ctx, rtc.startDay, "the clock's start day") end
  local minute = int(rtc.startMinute, 0)
  if minute ~= have.startMinute then
    minute = minute % 1440
    t[S.wStartHour], t[S.wStartMinute] = math.floor(minute / 60), minute % 60
  end
  if int(rtc.startSecond, 0) ~= (have.startSecond or 0) then
    t[S.wStartSecond] = byteOf(ctx, rtc.startSecond, "the clock's start second")
  end
  if (rtc.dst == true) ~= have.dst then t[S.wDST] = setBit(u8(t, S.wDST), 7, rtc.dst == true) end
  local saved = type(rtc.saved) == "table" and rtc.saved or nil
  local curDay = rtc.curDay
  if not (saved and curDay ~= nil) and not carried then
    local now = M.stage(rtc)
    saved = saved or now
    if curDay == nil then curDay = now.day end
  end
  if saved then
    local fields = { "day", "hour", "minute", "second" }
    for i, k in ipairs(fields) do
      local v = byteOf(ctx, saved[k] or 0, "the saved clock " .. k)
      if v ~= have.saved[k] then t[S.wRTC + i - 1] = v end
    end
  end
  if curDay ~= nil then
    local v = byteOf(ctx, curDay, "wCurDay")
    if v ~= have.curDay then t[S.wCurDay] = v end
  end
end

local function putFlags(ctx, t, save)
  local flags = flagsOf(save)
  local daily = type(save.dailyFlags) == "table" and save.dailyFlags or {}
  eachFlagBit(ctx, function(at, n, id)
    local want = flags[id] == true
    if not ctx.crystal and id == DAILY_GS[SWARM_BIT] then want = want or daily.swarm == true end
    -- pokegold engine/items/mart.asm:77
    if id == dailyIds(ctx)[6] and type(save.bargainShop) == "table" and next(save.bargainShop) ~= nil then want = true end
    t[at] = setBit(u8(t, at), n, want)
  end)
end

local function putTrees(ctx, t, trees)
  local S = ctx.S
  trees = type(trees) == "table" and trees or {}
  for key in pairs(trees) do
    local i = tonumber(key)
    if trees[key] == true and not (i and i >= 1 and i <= FRUIT_TREES and i == math.floor(i)) then
      ctx.util.refuse(("fruit tree %s has no wFruitTreeFlags bit"):format(tostring(key)))
    end
  end
  for i = 0, FRUIT_TREES - 1 do
    local at = S.wFruitTreeFlags + math.floor(i / 8)
    t[at] = setBit(u8(t, at), i % 8, trees[i + 1] == true)
  end
end

local function phoneList(ctx, save)
  local phone = type(save.phone) == "table" and save.phone or nil
  local list = {}
  for i = 1, CONTACTS do list[i] = int(phone and type(phone.list) == "table" and phone.list[i], 0) end
  local legacy = type(save.phoneContacts) == "table" and save.phoneContacts or {}
  local extra = {}
  for key, on in pairs(legacy) do
    local id = tonumber(key)
    if on and id and id > 0 then
      local found = false
      for i = 1, CONTACTS do if list[i] == id then found = true end end
      if not found then extra[#extra + 1] = id end
    end
  end
  table.sort(extra)
  for _, id in ipairs(extra) do
    local placed = false
    for i = 1, CONTACTS do
      if list[i] == 0 then list[i], placed = id, true break end
    end
    if not placed then ctx.util.refuse(("phone contact %d does not fit the ten wPhoneList slots"):format(id)) end
  end
  for i = 1, CONTACTS do list[i] = byteOf(ctx, list[i], "phone slot " .. i) end
  return list, int(phone and phone.specialCall, 0)
end

local function putCrystal(ctx, t, save, curDay)
  local S = ctx.S
  local crystal = type(save.crystal) == "table" and save.crystal or {}
  local buena = type(crystal.buenaPassword) == "table" and crystal.buenaPassword or {}
  if int(buena.prizesToday, 0) ~= 0 or int(buena.streak, 0) ~= 0 then
    ctx.util.refuse("Buena's prizesToday/streak counters have no cartridge byte")
  end
  local word = byteOf(ctx, buena.word or 0, "wBuenasPassword")
  if u8(t, S.wBuenasPassword) ~= word then t[S.wBuenasPassword] = word end
  local balance = byteOf(ctx, buena.balance or 0, "wBlueCardBalance")
  if u8(t, S.wBlueCardBalance) ~= balance then t[S.wBlueCardBalance] = balance end
  local rolled = flagsOf(save)[BUENA_FLAG] == true or (buena.day ~= nil and int(buena.day) == curDay)
  -- pokecrystal engine/pokegear/radio.asm:1489
  t[S.wDailyFlags2] = setBit(u8(t, S.wDailyFlags2), 7, rolled)
  local kenji = byteOf(ctx, crystal.kenjiBreak or 0, "wKenjiBreakTimer")
  if u8(t, S.wKenjiBreakTimer) ~= kenji then t[S.wKenjiBreakTimer] = kenji end
  local maps = type(save.swarmMaps) == "table" and save.swarmMaps or {}
  local yanma = maps.YANMA
  if readPair(ctx, t) ~= yanma then
    if yanma == nil then
      t[S.wYanmaMapGroup], t[S.wYanmaMapNumber] = 0, 0
    else
      local ids = ctx.x.mapIds and ctx.x.mapIds[yanma]
      if not ids then ctx.util.refuse(("the Yanma swarm map %s has no map group/number"):format(tostring(yanma))) end
      t[S.wYanmaMapGroup], t[S.wYanmaMapNumber] = ids[1] % 256, ids[2] % 256
    end
  end
  local kurt = byteOf(ctx, save.kurtApricornQuantity or 0, "wKurtApricornQuantity")
  if u8(t, S.wKurtApricornQuantity) ~= kurt then t[S.wKurtApricornQuantity] = kurt end
end

local function putByte(ctx, t, at, v, what)
  local b = byteOf(ctx, v or 0, what)
  if u8(t, at) ~= b then t[at] = b end
end

local function putWord(ctx, t, at, v, what)
  local w = wordOf(ctx, v or 0, what)
  if be2(t, at) ~= w then t[at], t[at + 1] = math.floor(w / 256), w % 256 end
end

function M.encode(ctx, save)
  local t, S = ctx.t, ctx.S
  local R = M.ranges(S, ctx.crystal)
  local carrier = type(save[M.KEY]) == "table" and save[M.KEY] or {}
  local carried = {}
  for _, k in ipairs({ "clock", "daily", "steps", "sram" }) do carried[k] = unhex(t, R[k], carrier[k]) end
  local priorLucky = be2(t, S.wLuckyIDNumber)

  local rtc = type(save.rtc) == "table" and save.rtc or {}
  putClock(ctx, t, rtc, carried.clock)
  local curDay = u8(t, S.wCurDay)

  putTimer(ctx, t, S.wDailyResetTimer, M.dailyTimer(t, S, save), "the daily reset timer")
  putFlags(ctx, t, save)
  putByte(ctx, t, S.wTimerEventStartDay, save.pokerusStartDay, "the Pokerus start day")
  putTrees(ctx, t, save.fruitTrees)
  putTimer(ctx, t, S.wLuckyNumberDayTimer, save.luckyNumberReset, "the lucky number timer")
  local list, special = phoneList(ctx, save)
  putByte(ctx, t, S.wSpecialPhoneCallID, special, "wSpecialPhoneCallID")
  for i = 1, CONTACTS do
    if u8(t, S.wPhoneList + i - 1) ~= list[i] then t[S.wPhoneList + i - 1] = list[i] end
  end
  if ctx.crystal then putCrystal(ctx, t, save, curDay) end

  putByte(ctx, t, S.wStepCount, save.stepCount, "wStepCount")
  putByte(ctx, t, S.wPoisonStepCount, save.poisonStepCount, "wPoisonStepCount")
  putByte(ctx, t, S.wHappinessStepCount, save.happinessStepCount, "wHappinessStepCount")
  putByte(ctx, t, S.wParkBallsRemaining, type(save.bugContest) == "table" and save.bugContest.balls or 0,
          "wParkBallsRemaining")
  putByte(ctx, t, S.wRepelEffect, save.repelSteps, "wRepelEffect")
  putWord(ctx, t, S.wBikeStep, save.bikeStep, "wBikeStep")
  local lucky = wordOf(ctx, save.luckyNumber or 0, "the lucky number")
  putWord(ctx, t, S.wLuckyIDNumber, lucky, "the lucky number")
  if lucky ~= priorLucky then
    -- pokegold engine/menus/intro_menu.asm:238
    local reset = type(save.luckyNumberReset) == "table" and save.luckyNumberReset or {}
    local day = int(reset.day, curDay)
    t[S.sLuckyNumberDay] = (day + 1) % 256
    t[S.sLuckyIDNumber], t[S.sLuckyIDNumber + 1] = math.floor(lucky / 256), lucky % 256
  end
end

return M
