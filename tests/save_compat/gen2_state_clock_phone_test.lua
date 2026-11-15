package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local G2 = require("tests.fixtures.save.gen2_build")
local Gen2Save = require("src.save_convert.Gen2Save")
local Gen2State = require("src.save_convert.Gen2State")
local Gen2Syms = require("src.save_convert.Gen2Syms")
local M = require("src.save_convert.gen2_state.clock_phone")

local Save = require("src.core.gen2.Save")
local Clock = require("src.core.gen2.Clock")
local Apricorns = require("src.core.gen2.Apricorns")
local Phone = require("src.core.gen2.Phone")
require("tests.fixtures.gen2_phone_events").install()
local Pokerus = require("src.core.gen2.Pokerus")
local Happiness = require("src.core.gen2.Happiness")
local BugContest = require("src.core.gen2.BugContest")
local Roamers = require("src.core.gen2.Roamers")
local StepEvents = require("src.world.gen2.StepEvents")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Specials = require("src.script.gen2.Specials")
local Buena = require("src.core.gen2.Buena")
local Radio = require("src.ui.gen2.Pokegear").Radio
local BuenaData = require("tests.fixtures.gen2_buena")

local VERSIONS = { "gold", "silver", "crystal" }
local REGIONS = {
  both = { "wStartDay", "wRTC", "wDST", "wGameTimeCap", "wCurDay", "wDailyResetTimer", "wDailyFlags1",
           "wTimerEventStartDay", "wFruitTreeFlags", "wLuckyNumberDayTimer", "wSpecialPhoneCallID",
           "wUnusedTwoDayTimerOn", "wStepCount", "wPoisonStepCount", "wHappinessStepCount", "wParkBallsRemaining",
           "wSafariTimeRemaining", "wPhoneList", "wLuckyNumberShowFlag", "wLuckyIDNumber", "wRepelEffect",
           "wBikeStep", "sRTCStatusFlags", "sLuckyNumberDay" },
  gold = { "wDSTBackupDay" },
  crystal = { "wUnusedDailyFlag", "wBuenasPassword", "wDailyRematchFlags", "wKenjiBreakTimer", "wYanmaMapGroup",
              "wPlayerMonSelection", "wKurtApricornQuantity" },
}
REGIONS.silver = REGIONS.gold

local function syms(v) return Gen2State.symsFor(v) end
local function u8(s, at) return s:byte(at + 1) end
local function be2(s, at) return u8(s, at) * 256 + u8(s, at + 1) end

local function rangesOf(v)
  local R = M.ranges(syms(v), v == "crystal")
  local all = {}
  for _, k in ipairs({ "clock", "daily", "steps", "sram" }) do
    for _, r in ipairs(R[k]) do all[#all + 1] = r end
  end
  return all
end

local function sameRanges(v, a, b, label)
  local diffs = {}
  for _, r in ipairs(rangesOf(v)) do
    for i = r[1], r[2] - 1 do
      if u8(a, i) ~= u8(b, i) then diffs[#diffs + 1] = ("%04X:%02X>%02X"):format(i, u8(a, i), u8(b, i)) end
    end
  end
  check(#diffs == 0, label .. (#diffs > 0 and (" " .. table.concat(diffs, ",", 1, math.min(#diffs, 8))) or ""))
end

local function regionsFor(v)
  local mod = require("src.save_convert.regions.gen2")
  return mod.layouts[v]
end

local function regionNamed(v, name)
  for _, r in ipairs(regionsFor(v)) do
    if r.name == name then return r end
  end
end

for _, v in ipairs(VERSIONS) do
  require("tests.fixture_data.gen2_engine_flags").bind(v)
  for _, list in ipairs({ REGIONS.both, REGIONS[v] }) do
    for _, name in ipairs(list) do
      local r = regionNamed(v, name)
      check(r ~= nil and r.offset == syms(v)[name], ("%s: region %s exists at its label"):format(v, name))
    end
  end
end

local function deepcopy(x)
  if type(x) ~= "table" then return x end
  local o = {}
  for k, y in pairs(x) do o[k] = deepcopy(y) end
  return o
end


local function realistic(v)
  return function(b)
    local S = syms(v)
    local crystal = v == "crystal"
    b[S.wStartDay], b[S.wStartHour], b[S.wStartMinute], b[S.wStartSecond] = 3, 13, 45, 20
    b[S.wRTC], b[S.wRTC + 1], b[S.wRTC + 2], b[S.wRTC + 3] = 57, 22, 10, 5
    if S.wDSTBackupDay then
      b[S.wDSTBackupDay], b[S.wDSTBackupHours], b[S.wDSTBackupMinutes], b[S.wDSTBackupSeconds] = 57, 21, 10, 5
    end
    b[S.wDST] = 0x80
    b[S.wCurDay] = 57
    b[S.wDailyResetTimer], b[S.wDailyResetTimer + 1] = 1, 57
    b[S.wDailyFlags1] = 0x15
    b[S.wDailyFlags2] = crystal and 0x83 or 0x03
    b[S.wTimerEventStartDay] = 50
    b[S.wFruitTreeFlags], b[S.wFruitTreeFlags + 1], b[S.wFruitTreeFlags + 3] = 0x05, 0x80, 0x02
    b[S.wLuckyNumberDayTimer], b[S.wLuckyNumberDayTimer + 1] = 3, 55
    b[S.wSpecialPhoneCallID] = 2
    if crystal then
      b[S.wBuenasPassword], b[S.wBlueCardBalance] = 0x21, 7
      b[S.wDailyRematchFlags], b[S.wDailyRematchFlags + 2] = 0x05, 0x80
      b[S.wDailyPhoneItemFlags], b[S.wDailyPhoneItemFlags + 1] = 0x01, 0x02
      b[S.wDailyPhoneTimeOfDayFlags + 1] = 0x10
      b[S.wKenjiBreakTimer] = 4
      b[S.wYanmaMapGroup], b[S.wYanmaMapNumber] = 24, 7
      b[S.wKurtApricornQuantity] = 1
    end
    b[S.wStepCount], b[S.wPoisonStepCount], b[S.wHappinessStepCount] = 0x42, 3, 1
    b[S.wParkBallsRemaining] = 12
    local list = { 1, 4, 15, 0, 0, 0, 0, 0, 0, 0 }
    for i = 1, 10 do b[S.wPhoneList + i - 1] = list[i] end
    b[S.wLuckyNumberShowFlag] = 1
    b[S.wLuckyIDNumber], b[S.wLuckyIDNumber + 1] = 0xBE, 0xEF
    b[S.wRepelEffect] = 50
    b[S.wBikeStep], b[S.wBikeStep + 1] = 0x01, 0x23
    b[S.sLuckyNumberDay], b[S.sLuckyIDNumber], b[S.sLuckyIDNumber + 1] = 58, 0xBE, 0xEF
  end
end

local function glitch(v)
  return function(b)
    local k = 0
    for _, r in ipairs(rangesOf(v)) do
      for i = r[1], r[2] - 1 do
        k = k + 1
        b[i] = (k * 29 + 7) % 256
      end
    end
  end
end

local function build(v, paint)
  return G2.build({ version = v, patch = paint })
end

local function import(v, bytes)
  local save, err = K.import(2, v, bytes)
  check(save ~= nil, v .. ": import -- " .. tostring(err))
  return save
end

local function export(v, save, template)
  local out, err = K.export(2, v, save, template)
  check(out ~= nil, v .. ": export -- " .. tostring(err))
  return out
end


local function n0(x) return math.floor(tonumber(x) or 0) end

local function myFlagIds(v)
  local ids = {}
  local first = v == "crystal" and 80 or 79
  for i = 0, (v == "crystal" and 14 or 13) do ids[#ids + 1] = first + i end
  ids[#ids + 1] = v == "crystal" and 78 or 77
  if v == "crystal" then
    for id = 101, 158 do ids[#ids + 1] = id end
  end
  return ids
end

local function view(v, save)
  local s = deepcopy(save)
  local out = {}
  local rtc = s.rtc or {}
  out.startDay, out.startMinute, out.startSecond = n0(rtc.startDay), n0(rtc.startMinute), n0(rtc.startSecond)
  out.dst = tostring(rtc.dst == true)
  out.weekday = (Clock.hostWeekday() + n0(rtc.startDay)) % 7
  out.minutes = Clock.minutes(s)
  local function pair(x) return x and (n0(x.remaining) .. "/" .. n0(x.day)) or "0/0" end
  out.dailyReset, out.luckyReset = pair(s.dailyReset), pair(s.luckyNumberReset)
  out.resetDay = tostring((s.dailyReset and s.dailyReset.day) or s.dailyResetDay)
  out.pokerus = n0(s.pokerusStartDay)
  local trees = {}
  for i = 1, 30 do if (s.fruitTrees or {})[i] then trees[#trees + 1] = i end end
  out.trees = table.concat(trees, ",")
  out.phone = table.concat(Phone.contacts(s), ",")
  out.special = Phone.specialCallVar(s)
  local flags = s.engineFlags or {}
  for _, id in ipairs(myFlagIds(v)) do out["flag" .. id] = tostring(flags[id] == true) end
  if v ~= "crystal" then
    out.flag81 = tostring(flags[81] == true or Roamers.Swarm.active(s))
    out.swarm = tostring(Roamers.Swarm.active(s))
  end
  out.steps = n0(s.stepCount) .. "/" .. n0(s.poisonStepCount) .. "/" .. n0(s.happinessStepCount)
  out.balls = n0((s.bugContest or {}).balls)
  out.lucky = n0(s.luckyNumber)
  out.repel, out.bike = n0(s.repelSteps), n0(s.bikeStep)
  if v == "crystal" then
    local c = s.crystal or {}
    local buena = c.buenaPassword or {}
    out.buena = n0(buena.word) .. "/" .. n0(buena.balance) .. "/" .. tostring(buena.day)
    out.kenji, out.kurt = n0(c.kenjiBreak), n0(s.kurtApricornQuantity)
    out.yanma = tostring((s.swarmMaps or {}).YANMA)
  end
  return out
end

local function sameView(v, a, b, label)
  local va, vb = view(v, a), view(v, b)
  local keys = {}
  for k in pairs(va) do keys[#keys + 1] = k end
  table.sort(keys)
  local bad = {}
  for _, k in ipairs(keys) do
    if tostring(va[k]) ~= tostring(vb[k]) then bad[#bad + 1] = ("%s %s>%s"):format(k, tostring(va[k]), tostring(vb[k])) end
  end
  check(#bad == 0, label .. (#bad > 0 and (" " .. table.concat(bad, "; ")) or ""))
end


for _, v in ipairs(VERSIONS) do
  require("tests.fixture_data.gen2_engine_flags").bind(v)
  for _, kind in ipairs({ "realistic", "glitch" }) do
    local label = ("%s %s clock, daily, step, phone and lucky regions"):format(v, kind)
    local bytes = build(v, kind == "realistic" and realistic(v) or glitch(v))
    local save = import(v, bytes)
    local out = export(v, save, bytes)
    if out then
      sameRanges(v, bytes, out, label .. ": template export is byte-identical")
      local entries = K.r1Diff(2, v, bytes, out)
      check(#entries == 0, label .. ": no region differs " .. require("tests.save_compat._diff").format(entries, 6))
    end
    local fresh = deepcopy(save)
    fresh.rawImport = nil
    local f1 = export(v, fresh, false)
    if f1 then
      sameRanges(v, bytes, f1, label .. ": carriers reproduce the bytes with no template")
      local again = import(v, f1)
      local f2 = again and export(v, again, false)
      check(f2 == f1, label .. ": templateless export is a fixed point")
      if again then sameView(v, save, again, label .. ": reimport matches") end
    end
  end
end

do
  local S = syms("gold")
  local save = import("gold", build("gold", realistic("gold")))
  eq(save.rtc.startDay, 3, "wStartDay is the weekday offset Clock.weekday adds")
  eq(save.rtc.startMinute, 13 * 60 + 45, "wStartHour:wStartMinute is Clock's startMinute")
  eq(save.rtc.startSecond, 20, "wStartSecond rides along")
  eq(save.rtc.dst, true, "wDST bit 7 is rtc.dst")
  eq(save.rtc.saved.day, 57, "wRTC is the StageRTCTimeForSave snapshot")
  eq(save.rtc.curDay, 57, "wCurDay")
  eq(save.dailyReset.remaining, 1, "wDailyResetTimer remaining")
  eq(save.dailyReset.day, 57, "wDailyResetTimer start day")
  eq(save.dailyResetDay, 57, "Swarm.checkDailyReset's stamp is the same start day")
  check(save.engineFlags[79] and save.engineFlags[81] and save.engineFlags[83], "wDailyFlags1 bits 0, 2, 4")
  check(save.engineFlags[87] and save.engineFlags[88], "wDailyFlags2 bits 0, 1")
  eq(save.dailyFlags and save.dailyFlags.swarm, true, "Gold DAILYFLAGS1_SWARM_F is also Swarm.active")
  eq(save.pokerusStartDay, 50, "wTimerEventStartDay")
  check(save.fruitTrees[1] and save.fruitTrees[3] and save.fruitTrees[16] and save.fruitTrees[26], "fruit tree bits")
  eq(save.luckyNumberReset.remaining, 3, "wLuckyNumberDayTimer")
  eq(table.concat(Phone.contacts(deepcopy(save)), ","), "1,4,15,0,0,0,0,0,0,0", "wPhoneList")
  eq(save.phone.specialCall, 2, "wSpecialPhoneCallID")
  check(save.phoneContacts[1] and save.phoneContacts[4] and save.phoneContacts[15], "phoneContacts mirror")
  eq(save.engineFlags[77], true, "wLuckyNumberShowFlag is ENGINE_LUCKY_NUMBER_SHOW")
  eq(save.luckyNumber, 0xBEEF, "wLuckyIDNumber big endian")
  eq(save.stepCount, 0x42, "wStepCount")
  eq(save.bugContest.balls, 12, "wParkBallsRemaining")
  eq(save.repelSteps, 50, "wRepelEffect")
  eq(save.bikeStep, 0x0123, "wBikeStep big endian")
  check(S.wDSTBackupDay ~= nil, "Gold has the DST backup bytes")
  local c = import("crystal", build("crystal", realistic("crystal")))
  eq(c.crystal.buenaPassword.word, 0x21, "wBuenasPassword")
  eq(c.crystal.buenaPassword.balance, 7, "wBlueCardBalance")
  eq(c.crystal.buenaPassword.day, 57, "DAILYFLAGS2_BUENAS_PASSWORD_F means rolled on wCurDay")
  check(c.engineFlags[80] and c.engineFlags[82] and c.engineFlags[84], "Crystal wDailyFlags1 ids are one higher")
  eq(c.dailyFlags and c.dailyFlags.swarm, nil, "Crystal bit 2 is ENGINE_QWILFISH_SWARM only")
  check(c.engineFlags[101] and c.engineFlags[103] and c.engineFlags[124], "wDailyRematchFlags")
  check(c.engineFlags[125] and c.engineFlags[134], "wDailyPhoneItemFlags")
  check(c.engineFlags[147], "wDailyPhoneTimeOfDayFlags")
  eq(c.engineFlags[78], true, "Crystal ENGINE_LUCKY_NUMBER_SHOW is 78")
  eq(c.crystal.kenjiBreak, 4, "wKenjiBreakTimer")
  eq(c.swarmMaps.YANMA, K.GEN2_MAP, "wYanmaMapGroup/Number")
  eq(c.kurtApricornQuantity, 1, "wKurtApricornQuantity")
end


local function engineSave(v)
  local base = import(v, build(v, nil))
  base.rawImport = nil
  for _, k in ipairs({ M.KEY, "rtc", "dailyReset", "dailyResetDay", "pokerusStartDay", "fruitTrees", "luckyNumberReset", "phone",
                       "phoneContacts", "luckyNumber", "stepCount", "poisonStepCount", "happinessStepCount",
                       "repelSteps", "bikeStep", "kurtApricornQuantity", "crystal", "dailyFlags", "swarmMaps",
                       "swarmMap", "bugContest" }) do
    base[k] = nil
  end
  local fresh = Save.newGame()
  for _, k in ipairs({ "rtc", "phoneContacts" }) do base[k] = fresh[k] end
  if v == "crystal" then Save.crystalState(base) end
  return base
end

local function specialVm(save)
  return {
    scriptVar = 0,
    specials = { save = function() return save end, setEngineFlag = function() end },
    setStringBuffer = function() end, showRaw = function() end,
  }
end

for _, v in ipairs(VERSIONS) do
  require("tests.fixture_data.gen2_engine_flags").bind(v)
  local label = v .. " R2 engine-built"
  local s = engineSave(v)
  Clock.setTime(s, 7, 30)
  Clock.setWeekday(s, 4)
  s.rtc.dst = true
  Apricorns.startDailyResetTimer(s)
  Apricorns.tryResetFruitTrees(s)
  Apricorns.pickTree(s, 2)
  Apricorns.pickTree(s, 30)
  s.engineFlags[v == "crystal" and 80 or 79] = true
  Phone.addContact(s, Phone.PHONECONTACT_MOM)
  Phone.addContact(s, Phone.PHONECONTACT_ELM)
  Phone.addContact(s, 15)
  Phone.queueSpecialCall(s, 3)
  Pokerus.checkTick(s)
  local realRandom = Specials.random
  Specials.random = function() return 0x2345 end
  local vm = specialVm(s)
  Specials.HANDLERS.CheckLuckyNumberShowFlag(vm)
  Specials.HANDLERS.ResetLuckyNumberShowFlag(vm)
  Specials.random = realRandom
  for _ = 1, 3 do StepEvents.repelStep(s) end
  s.repelSteps = 100
  StepEvents.repelStep(s)
  Happiness.stepCycle(s)
  s.stepCount = 0x7F
  s.poisonStepCount = 2
  s.engineFlags[FieldMoves.BIKE_SHOP_CALL_FLAG] = true
  for _ = 1, 5 do StepEvents.bikeStep(s, { playerState = "bike" }) end
  BugContest.start(s)
  BugContest.useBall(s)
  BugContest.stop(s)
  if v == "crystal" then
    local radio = Radio.new({ data = { crystal = true, hour = 21,
      buenaSave = s, buenaData = BuenaData }, rng = function() return 1 end })
    radio:tune("BUENAS_PASSWORD")
    for _ = 1, 410 do radio:step() end
    Save.crystalState(s).buenaPassword.balance = 12
    s.rtc.day = Save.crystalState(s).buenaPassword.day
    Save.crystalState(s).kenjiBreak = 5
    s.kurtApricornQuantity = 1
    Roamers.Swarm.set(s, K.GEN2_MAP, 1)
  else
    Roamers.Swarm.set(s, K.GEN2_MAP)
  end
  local out = export(v, s, false)
  if out then
    local back = import(v, out)
    if back then
      sameView(v, s, back, label .. ": every cart-backed field survives")
      local again = export(v, back, false)
      check(again == out, label .. ": fixed point")
    end
    local S = syms(v)
    eq(u8(out, S.wStartDay), s.rtc.startDay, label .. ": wStartDay")
    eq(u8(out, S.wPhoneList) * 256 + u8(out, S.wPhoneList + 1), 1 * 256 + 4, label .. ": Mom then Elm")
    eq(be2(out, S.wLuckyIDNumber), 0x2345, label .. ": lucky number")
    eq(be2(out, S.sLuckyIDNumber), 0x2345, label .. ": sLuckyIDNumber follows the roll")
    eq(u8(out, S.sLuckyNumberDay), (s.luckyNumberReset.day + 1) % 256, label .. ": sLuckyNumberDay is the roll day + 1")
    eq(u8(out, S.wCurDay), s.rtc.day % 140, label .. ": an engine save stages its rtc.day on the 140-day wrap")
    eq(u8(out, S.wRTC), s.rtc.day % 140, label .. ": wRTC day from rtc.day")
    eq(u8(out, S.wRTC + 1), s.rtc.hour, label .. ": wRTC hour from rtc.hour")
    eq(u8(out, S.wRTC + 2), s.rtc.minute, label .. ": wRTC minute from rtc.minute")
    eq(u8(out, S.wRTC + 3), 0, label .. ": wRTC second is 0")
  end
end

-- pokecrystal/engine/pokegear/radio.asm:1467
do
  local S = syms("crystal")
  local bytes = build("crystal", realistic("crystal"))
  local s = import("crystal", bytes)
  local buena = s.crystal.buenaPassword
  local word, points, day = buena.word, buena.balance, buena.day
  s.engineFlags[96] = true
  local radio = Radio.new({ data = { crystal = true, hour = 21,
    buenaSave = s, buenaData = BuenaData }, rng = function() error("imported word rerolled") end })
  radio:tune("BUENAS_PASSWORD")
  for _ = 1, 410 do radio:step() end
  eq(buena.word, word, "2639 imported listening word survives radio")
  eq(buena.day, day, "2639 imported listening day survives radio")
  local listening = export("crystal", s, bytes)
  if listening then
    eq(u8(listening, S.wBuenasPassword), word, "2639 listening exports captured word")
    eq(u8(listening, S.wBlueCardBalance), points, "2639 listening exports points")
    eq(math.floor(u8(listening, S.wDailyFlags2) / 128), 1, "2639 listening exports source bit7")
  end
  Buena.clearListening(s, BuenaData)
  local offair = export("crystal", s, bytes)
  if offair then
    local back = import("crystal", offair)
    eq(back.crystal.buenaPassword.word, word, "2639 off-air preserves packed word through SRAM")
    eq(back.crystal.buenaPassword.balance, points, "2639 off-air preserves points through SRAM")
    eq(back.crystal.buenaPassword.day, nil, "2639 off-air does not resurrect cleared listened day")
    eq(math.floor(u8(offair, S.wDailyFlags2) / 128), 0, "2639 off-air clears SRAM listened bit7")
    eq(u8(offair, S.wSwarmFlags) % 2, 1, "2639 off-air preserves SRAM played bit0")
  end
  Apricorns.dailyReset(s)
  local reset = export("crystal", s, bytes)
  if reset then
    eq(u8(reset, S.wSwarmFlags) % 2, 0, "2639 daily reset clears SRAM played bit0")
    eq(u8(reset, S.wBuenasPassword), word, "2639 daily reset preserves SRAM packed word")
    eq(u8(reset, S.wBlueCardBalance), points, "2639 daily reset preserves SRAM points")
  end
end

do
  local s = engineSave("gold")
  s.luckyNumber = 99999
  local out, err = K.export(2, "gold", s, false)
  check(out == nil and tostring(err):find("lucky number", 1, true) ~= nil,
    "a five-digit lucky number past 65535 is refused, not truncated: " .. tostring(err))
  local p = engineSave("gold")
  for id = 5, 15 do p.phoneContacts[id] = true end
  local out2, err2 = K.export(2, "gold", p, false)
  check(out2 == nil and tostring(err2):find("wPhoneList", 1, true) ~= nil, "eleven contacts are refused: " .. tostring(err2))
  local c = engineSave("crystal")
  Save.crystalState(c).buenaPassword.streak = 2
  local out3, err3 = K.export(2, "crystal", c, false)
  check(out3 == nil and tostring(err3):find("streak", 1, true) ~= nil, "a Buena streak has no byte: " .. tostring(err3))
end

do
  local s = engineSave("crystal")
  Clock.setTime(s, 9, 15)
  local buena = Save.crystalState(s).buenaPassword
  buena.word, buena.balance, buena.day = 0x12, 3, (s.rtc.day + 1) % 140
  local out = export("crystal", s, false)
  local back = out and import("crystal", out)
  if back then
    eq(back.crystal.buenaPassword.word, 0x12, "a password rolled on another day keeps its word")
    eq(back.crystal.buenaPassword.day, nil, "but not the rolled-today bit, which needs buena.day == wCurDay")
    eq(u8(out, syms("crystal").wDailyFlags2) >= 0x80, false, "DAILYFLAGS2_BUENAS_PASSWORD_F stays clear")
  end
end

do
  local trapped = {}
  local real = { time = os.time, date = os.date, clock = os.clock, random = math.random }
  local function trap(name) return function() trapped[#trapped + 1] = name; error("export consulted " .. name) end end
  for _, v in ipairs(VERSIONS) do
    local s = engineSave(v)
    Clock.setTime(s, 7, 30)
    Clock.setWeekday(s, 4)
    s.rtc.dst = true
    Apricorns.startDailyResetTimer(s, { day = 12 })
    Apricorns.pickTree(s, 2)
    Phone.addContact(s, Phone.PHONECONTACT_MOM)
    Phone.queueSpecialCall(s, 3)
    s.luckyNumber = 0x1234
    s.luckyNumberReset = { remaining = 4, day = 12 }
    os.time, os.date, os.clock, math.random = trap("os.time"), trap("os.date"), trap("os.clock"), trap("math.random")
    local a = K.export(2, v, deepcopy(s), false)
    local b = K.export(2, v, deepcopy(s), false)
    os.time, os.date, os.clock, math.random = real.time, real.date, real.clock, real.random
    check(a ~= nil and a == b, v .. ": a fresh export never reads the wall clock or RNG and is byte-identical twice")
  end
  eq(#trapped, 0, "no clock or RNG call was trapped: " .. table.concat(trapped, ","))
end


for _, v in ipairs(VERSIONS) do
  require("tests.fixture_data.gen2_engine_flags").bind(v)
  local S = syms(v)
  local label = v .. " dailyResetDay"
  local s = engineSave(v)
  Clock.setTime(s, 8, 0)
  check(not Roamers.Swarm.timeEvents(s, 33), label .. ": the first poll only stamps the day")
  eq(s.dailyReset, nil, label .. ": Swarm keeps its own stamp, not save.dailyReset")
  local out = export(v, s, false)
  if out then
    eq(u8(out, S.wDailyResetTimer), 1, label .. ": a stamped day is a one-day countdown")
    eq(u8(out, S.wDailyResetTimer + 1), 33, label .. ": started that day")
    local back = import(v, out)
    if back then
      eq(back.dailyResetDay, 33, label .. ": the import keeps Swarm's stamp")
      eq(back.dailyReset.day, 33, label .. ": and the pair agrees")
      local a, b = deepcopy(s), deepcopy(back)
      eq(Roamers.Swarm.checkDailyReset(a, 33), Roamers.Swarm.checkDailyReset(b, 33), label .. ": same day, no reset either way")
      a, b = deepcopy(s), deepcopy(back)
      local kurt = v == "crystal" and 80 or 79
      a.engineFlags[kurt], b.engineFlags[kurt] = true, true
      eq(Roamers.Swarm.checkDailyReset(a, 34), true, label .. ": the engine stamp rolls over next day")
      eq(Apricorns.checkDailyResetTimer(b, { day = 34 }), true, label .. ": and so does the imported wDailyResetTimer")
      eq(b.engineFlags[kurt], nil, label .. ": clearing the daily flags like CheckDailyResetTimer")
      eq(b.dailyReset.day, 34, label .. ": RestartDailyResetTimer stamps the new day")
    end
  end
  local bytes = build(v, realistic(v))
  local g = import(v, bytes)
  Roamers.Swarm.checkDailyReset(g, 101)
  eq(g.dailyResetDay, 101, label .. ": the real rollover restamps")
  local out2 = export(v, g, bytes)
  if out2 then
    eq(u8(out2, S.wDailyResetTimer), 1, label .. ": changed stamp keeps remaining 1")
    eq(u8(out2, S.wDailyResetTimer + 1), 101, label .. ": changed stamp is exported as the start day")
  end
  local h = import(v, bytes)
  h.dailyResetDay = 90
  Apricorns.startDailyResetTimer(h, { day = 95 })
  local out3 = export(v, h, bytes)
  if out3 then eq(u8(out3, S.wDailyResetTimer + 1), 95, label .. ": the live save.dailyReset wins when both changed") end
end

for _, v in ipairs(VERSIONS) do
  require("tests.fixture_data.gen2_engine_flags").bind(v)
  local label = v .. " changes"
  local S = syms(v)
  local crystal = v == "crystal"
  local bytes = build(v, realistic(v))
  local s = import(v, bytes)
  Clock.setTime(s, 7, 30)
  Clock.setWeekday(s, 2)
  s.rtc.dst = false
  Apricorns.dailyReset(s)
  Apricorns.startDailyResetTimer(s, { day = 99 })
  Apricorns.pickTree(s, 5)
  Phone.addContact(s, 22)
  Phone.queueSpecialCall(s, 3)
  Pokerus.checkTick(s, { day = 70 })
  StepEvents.repelStep(s)
  Happiness.stepCycle(s)
  BugContest.useBall(s)
  s.engineFlags[FieldMoves.BIKE_SHOP_CALL_FLAG] = true
  StepEvents.bikeStep(s, { playerState = "bike" })
  s.bargainShop = { ULTRA_BALL = true }
  s.engineFlags[crystal and 78 or 77] = nil
  if crystal then
    Save.crystalState(s).buenaPassword.word = 0x12
    Save.crystalState(s).buenaPassword.day = nil
    Save.crystalState(s).buenaPassword.balance = 9
    Save.crystalState(s).kenjiBreak = 6
    s.swarmMaps.YANMA = nil
    s.kurtApricornQuantity = nil
    s.engineFlags[103] = nil
    s.engineFlags[149] = true
  end
  local out = export(v, s, bytes)
  if out then
    local sm = s.rtc.startMinute
    eq(u8(out, S.wStartHour), math.floor(sm / 60), label .. ": _InitTime start hour")
    eq(u8(out, S.wStartMinute), sm % 60, label .. ": _InitTime start minute")
    eq(u8(out, S.wStartDay), (2 - Clock.hostWeekday()) % 7, label .. ": InitDayOfWeek start day")
    eq(u8(out, S.wDST), 0x00, label .. ": InitialClearDSTFlag clears bit 7")
    eq(u8(out, S.wStartSecond), 20, label .. ": the start second is untouched")
    eq(u8(out, S.wDailyResetTimer), 1, label .. ": InitOneDayCountdown remaining 1")
    eq(u8(out, S.wDailyResetTimer + 1), 99, label .. ": and the start day")
    eq(u8(out, S.wDailyFlags1), 0x40, label .. ": daily flags cleared, bargain merchant closed bit 6 set")
    eq(u8(out, S.wDailyFlags2), 0x00, label .. ": wDailyFlags2 cleared")
    eq(u8(out, S.wTimerEventStartDay), 70, label .. ": CalcDaysSince advanced the Pokerus stamp")
    eq(u8(out, S.wFruitTreeFlags), 0x15, label .. ": tree 5 is bit 4")
    eq(u8(out, S.wPhoneList + 3), 22, label .. ": AddPhoneNumber's first open slot")
    eq(u8(out, S.wSpecialPhoneCallID), 3, label .. ": wSpecialPhoneCallID")
    eq(u8(out, S.wRepelEffect), 49, label .. ": DoRepelStep")
    eq(u8(out, S.wHappinessStepCount), 0, label .. ": StepHappiness toggle")
    eq(u8(out, S.wParkBallsRemaining), 11, label .. ": a park ball thrown")
    eq(be2(out, S.wBikeStep), 0x0124, label .. ": DoBikeStep big endian")
    eq(u8(out, S.wLuckyNumberShowFlag), 0, label .. ": ENGINE_LUCKY_NUMBER_SHOW cleared")
    eq(u8(out, S.sLuckyNumberDay), 58, label .. ": an unchanged lucky number keeps sLuckyNumberDay")
    if crystal then
      eq(u8(out, S.wBuenasPassword), 0x12, label .. ": wBuenasPassword")
      eq(u8(out, S.wBlueCardBalance), 9, label .. ": wBlueCardBalance")
      eq(u8(out, S.wKenjiBreakTimer), 6, label .. ": wKenjiBreakTimer")
      eq(u8(out, S.wYanmaMapGroup) + u8(out, S.wYanmaMapNumber), 0, label .. ": a cleared Yanma swarm")
      eq(u8(out, S.wKurtApricornQuantity), 0, label .. ": wKurtApricornQuantity")
      eq(u8(out, S.wDailyRematchFlags), 0, label .. ": Crystal daily rematch array cleared")
      eq(u8(out, S.wDailyPhoneTimeOfDayFlags + 1), 0x40, label .. ": only today's Alan call slot set")
    end
  end
  if not crystal then
    local g = import(v, bytes)
    Apricorns.dailyReset(g)
    Roamers.Swarm.set(g, K.GEN2_MAP)
    local out2 = export(v, g, bytes)
    if out2 then eq(u8(out2, S.wDailyFlags1), 0x04, label .. ": StoreSwarmMapIndices sets DAILYFLAGS1_SWARM_F") end
  end
end


do
  local patterns = { "dstBackup", "rtcStatus", "twoDay", "unusedDaily", "safariTime",
                     "mobileOrCable", "monSelection" }
  local hits = {}
  local pipe = io.popen("grep -rn --include=*.lua -E '\\.[A-Za-z_]*(" .. table.concat(patterns, "|")
    .. ")[A-Za-z_]*[[:space:]]*=[^=]' src")
  for line in pipe:lines() do
    if not line:find("^src/save_convert/") then hits[#hits + 1] = line end
  end
  pipe:close()
  check(#hits == 0, "no engine code writes the DST backup, sRTCStatusFlags, the two-day timer, "
    .. "wUnusedDailyFlag, wSafariTimeRemaining or the mobile bytes: " .. table.concat(hits, " | "))
end


for _, v in ipairs(VERSIONS) do
  require("tests.fixture_data.gen2_engine_flags").bind(v)
  local S = syms(v)
  local which = v == "crystal" and "crystal" or "gs"
  local spans = {}
  for _, row in ipairs(M.coverage) do
    local run = row.both or row[which]
    if run then
      local from = S[run[1]]
      local to = run.len and from + run.len or S[run[2]]
      check(from ~= nil and to ~= nil and to > from, ("%s coverage %s resolves"):format(v, tostring(run[1])))
      spans[#spans + 1] = { from, to }
    end
  end
  table.sort(spans, function(a, b) return a[1] < b[1] end)
  local want = {}
  for _, r in ipairs(M.ranges(S, v == "crystal").clock) do want[#want + 1] = r end
  for _, r in ipairs(M.ranges(S, v == "crystal").daily) do want[#want + 1] = r end
  for _, r in ipairs(M.ranges(S, v == "crystal").steps) do want[#want + 1] = r end
  local merged = {}
  for _, sp in ipairs(spans) do
    local last = merged[#merged]
    if last and last[2] == sp[1] then last[2] = sp[2] else merged[#merged + 1] = { sp[1], sp[2] } end
  end
  local mergedWant = {}
  table.sort(want, function(a, b) return a[1] < b[1] end)
  for _, sp in ipairs(want) do
    local last = mergedWant[#mergedWant]
    if last and last[2] == sp[1] then last[2] = sp[2] else mergedWant[#mergedWant + 1] = { sp[1], sp[2] } end
  end
  local function str(list)
    local o = {}
    for _, sp in ipairs(list) do o[#o + 1] = ("%04X-%04X"):format(sp[1], sp[2]) end
    return table.concat(o, " ")
  end
  eq(str(merged), str(mergedWant), v .. ": coverage rows tile exactly the bytes the module carries")
  for i = 2, #spans do
    check(spans[i][1] >= spans[i - 1][2], ("%s coverage rows do not overlap at %04X"):format(v, spans[i][1]))
  end
  check(S.wBugContestStartTime + 4 == S.wUnusedTwoDayTimerOn, v .. ": wBugContestStartTime is skipped whole")
end
check(Gen2Syms.goldSilver.wSwarmFlags == nil, "Gold has no wSwarmFlags")

T.finish("gen2_state clock_phone")
