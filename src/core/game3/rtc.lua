local bit = require("bit")
local Profile = require("src.core.game3.profile")

local Rtc = {}

-- pokeemerald/include/rtc.h:6
Rtc.ERR = {
  INIT_ERROR = 0x0001,
  INIT_WARNING = 0x0002,
  TWELVE_HOUR_CLOCK = 0x0010,
  POWER_FAILURE = 0x0020,
  INVALID_YEAR = 0x0040,
  INVALID_MONTH = 0x0080,
  INVALID_DAY = 0x0100,
  INVALID_HOUR = 0x0200,
  INVALID_MINUTE = 0x0400,
  INVALID_SECOND = 0x0800,
  FLAG_MASK = 0x0FF0,
}

Rtc.SAVE_FIELDS = { "localTimeOffset", "lastBerryTreeUpdate", "rtcSkew" }

-- pokeemerald/src/rtc.c:19
local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local SECONDS_PER_DAY = 86400

local state = {
  errorStatus = nil,
  fixedBase = nil,
  advanced = 0,
  host = nil,
}

Rtc.localTime = { days = 0, hours = 0, minutes = 0, seconds = 0 }

local function s8(v)
  v = math.floor(v) % 256
  if v >= 128 then v = v - 256 end
  return v
end

local function s16(v)
  v = math.floor(v) % 65536
  if v >= 32768 then v = v - 65536 end
  return v
end

local function u16(v)
  return math.floor(v) % 65536
end

Rtc.s8, Rtc.s16, Rtc.u16 = s8, s16, u16

function Rtc.newTime(days, hours, minutes, seconds)
  return {
    days = s16(tonumber(days) or 0),
    hours = s8(tonumber(hours) or 0),
    minutes = s8(tonumber(minutes) or 0),
    seconds = s8(tonumber(seconds) or 0),
  }
end

function Rtc.copyTime(t)
  t = type(t) == "table" and t or {}
  return Rtc.newTime(t.days, t.hours, t.minutes, t.seconds)
end

function Rtc.enabled(session)
  local ok, row = pcall(Profile.forSession, session)
  if not ok or type(row) ~= "table" then return false end
  return type(row.clock) == "table" and row.clock.rtc == true
end

-- pokeemerald/src/rtc.c:57
function Rtc.isLeapYear(year)
  return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

-- pokeemerald/src/rtc.c:65
function Rtc.dayCount(year, month, day)
  local count = 0
  for i = year - 1, 0, -1 do
    count = count + 365
    if Rtc.isLeapYear(i) then count = count + 1 end
  end
  for i = 1, month - 1 do
    count = count + (DAYS_IN_MONTH[i] or 0)
  end
  if month > 2 and Rtc.isLeapYear(year) then count = count + 1 end
  count = count + day
  return u16(count)
end

-- pokeemerald/src/rtc.c:89
function Rtc.getDayCount(info)
  return Rtc.dayCount(info.year, info.month, info.day)
end

local function parseFixed(spec)
  if type(spec) ~= "string" then return nil end
  local y, mo, d, h, mi, se = spec:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):?(%d?%d?)$")
  if not y then
    y, mo, d = spec:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    h, mi, se = "0", "0", "0"
  end
  if not y then return nil end
  return {
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), minute = tonumber(mi), second = tonumber(se) ~= nil and tonumber(se) or 0,
  }
end

local function hostFields()
  if state.host then return state.host() end
  local t = os.date("*t")
  return { year = t.year, month = t.month, day = t.day, hour = t.hour, minute = t.min, second = t.sec }
end

local function linearOf(f)
  local y = f.year - 2000
  local dc = 0
  if y > 0 then
    for i = y - 1, 0, -1 do
      dc = dc + 365
      if Rtc.isLeapYear(i) then dc = dc + 1 end
    end
  elseif y < 0 then
    for i = y, -1 do
      dc = dc - 365
      if Rtc.isLeapYear(i) then dc = dc - 1 end
    end
  end
  for i = 1, f.month - 1 do dc = dc + (DAYS_IN_MONTH[i] or 0) end
  if f.month > 2 and Rtc.isLeapYear(y) then dc = dc + 1 end
  dc = dc + f.day - 1
  return dc * SECONDS_PER_DAY + f.hour * 3600 + f.minute * 60 + f.second
end

local function fieldsOf(total)
  local dc = math.floor(total / SECONDS_PER_DAY)
  local rem = total - dc * SECONDS_PER_DAY
  local y = 0
  while dc < 0 do
    y = y - 1
    dc = dc + (Rtc.isLeapYear(y) and 366 or 365)
  end
  while true do
    local len = Rtc.isLeapYear(y) and 366 or 365
    if dc < len then break end
    dc = dc - len
    y = y + 1
  end
  local month = 1
  while true do
    local len = DAYS_IN_MONTH[month]
    if month == 2 and Rtc.isLeapYear(y) then len = len + 1 end
    if dc < len then break end
    dc = dc - len
    month = month + 1
  end
  return {
    year = y + 2000, month = month, day = dc + 1,
    hour = math.floor(rem / 3600), minute = math.floor(rem / 60) % 60, second = rem % 60,
  }
end

Rtc._linearOf, Rtc._fieldsOf = linearOf, fieldsOf

local function envFixed()
  local spec = os.getenv and os.getenv("POKEPORT_RTC") or nil
  if spec == nil or spec == "" then return nil end
  local f = parseFixed(spec)
  if not f then error("POKEPORT_RTC must be YYYY-MM-DD[THH:MM[:SS]], got " .. tostring(spec), 0) end
  return linearOf(f)
end

local function nowLinear(session)
  local base = state.fixedBase
  if base == nil then
    base = envFixed()
    if base ~= nil then state.fixedBase = base end
  end
  if base == nil then base = linearOf(hostFields()) end
  local skew = type(session) == "table" and tonumber(session.rtcSkew) or 0
  return base + state.advanced + skew
end

function Rtc.hostInfo(session)
  local f = fieldsOf(nowLinear(session))
  return {
    year = f.year - 2000, month = f.month, day = f.day,
    hour = f.hour, minute = f.minute, second = f.second,
  }
end

local function checkInfo(info)
  local err = 0
  if info.year < 0 or info.year > 99 then err = err + Rtc.ERR.INVALID_YEAR end
  return err
end

-- pokeemerald/src/rtc.c:97
function Rtc.init()
  local forced = os.getenv and os.getenv("POKEPORT_RTC_ERROR") or nil
  if forced and forced ~= "" then
    state.errorStatus = tonumber(forced) or tonumber(forced, 16) or 0
    return state.errorStatus
  end
  state.errorStatus = checkInfo(Rtc.hostInfo(nil))
  return state.errorStatus
end

-- pokeemerald/src/rtc.c:121
function Rtc.errorStatus()
  if state.errorStatus == nil then Rtc.init() end
  return state.errorStatus
end

-- pokeemerald/src/rtc.c:126
function Rtc.getInfo(session)
  if bit.band(Rtc.errorStatus(), Rtc.ERR.FLAG_MASK) ~= 0 then
    return { year = 0, month = 1, day = 1, hour = 0, minute = 0, second = 0 }
  end
  return Rtc.hostInfo(session)
end

local function borrow(r)
  if r.seconds < 0 then
    r.seconds = r.seconds + 60
    r.minutes = r.minutes - 1
  end
  if r.minutes < 0 then
    r.minutes = r.minutes + 60
    r.hours = r.hours - 1
  end
  if r.hours < 0 then
    r.hours = r.hours + 24
    r.days = r.days - 1
  end
  return Rtc.newTime(r.days, r.hours, r.minutes, r.seconds)
end

-- pokeemerald/src/rtc.c:263
function Rtc.calcTimeDifferenceRtc(info, t)
  t = t or {}
  return borrow({
    seconds = s8(info.second - (t.seconds or 0)),
    minutes = s8(info.minute - (t.minutes or 0)),
    hours = s8(info.hour - (t.hours or 0)),
    days = s16(Rtc.getDayCount(info) - (t.days or 0)),
  })
end

-- pokeemerald/src/rtc.c:311
function Rtc.calcTimeDifference(t1, t2)
  t1, t2 = t1 or {}, t2 or {}
  return borrow({
    seconds = s8((t2.seconds or 0) - (t1.seconds or 0)),
    minutes = s8((t2.minutes or 0) - (t1.minutes or 0)),
    hours = s8((t2.hours or 0) - (t1.hours or 0)),
    days = s16((t2.days or 0) - (t1.days or 0)),
  })
end

local function offsetOf(session)
  if type(session) ~= "table" then return Rtc.newTime(0, 0, 0, 0) end
  if type(session.localTimeOffset) ~= "table" then
    session.localTimeOffset = Rtc.newTime(0, 0, 0, 0)
  end
  return session.localTimeOffset
end

-- pokeemerald/src/rtc.c:290
function Rtc.calcLocalTime(session)
  Rtc._info = Rtc.getInfo(session)
  Rtc.localTime = Rtc.calcTimeDifferenceRtc(Rtc._info, offsetOf(session))
  return Rtc.copyTime(Rtc.localTime)
end

-- pokeemerald/src/rtc.c:301
function Rtc.calcLocalTimeOffset(session, days, hours, minutes, seconds)
  Rtc.localTime = Rtc.newTime(days, hours, minutes, seconds)
  Rtc._info = Rtc.getInfo(session)
  local off = Rtc.calcTimeDifferenceRtc(Rtc._info, Rtc.localTime)
  if type(session) == "table" then session.localTimeOffset = off end
  return Rtc.copyTime(off)
end

-- pokeemerald/src/rtc.c:296
function Rtc.initLocalTimeOffset(session, hour, minute)
  return Rtc.calcLocalTimeOffset(session, 0, hour, minute, 0)
end

local function toBcd(v)
  return math.floor(v / 10) * 16 + v % 10
end

-- pokeemerald/src/rtc.c:337
function Rtc.minuteCount(session)
  local info = Rtc.getInfo(session)
  Rtc._info = info
  return 24 * 60 * Rtc.getDayCount(info) + 60 * toBcd(info.hour) + toBcd(info.minute)
end

-- pokeemerald/src/rtc.c:343
function Rtc.localDayCount()
  local info = Rtc._info or Rtc.getInfo(nil)
  return Rtc.getDayCount(info)
end

function Rtc.timeMinutes(t)
  t = t or {}
  return 24 * 60 * (t.days or 0) + 60 * (t.hours or 0) + (t.minutes or 0)
end

Rtc.IMPORT_HOST_CLOCK_WINDOW = 366 * SECONDS_PER_DAY

function Rtc.anchorToLastUpdate(session)
  if type(session) ~= "table" then return 0 end
  local last = session.lastBerryTreeUpdate
  if type(last) ~= "table" then return tonumber(session.rtcSkew) or 0 end
  local off = offsetOf(session)
  session.rtcSkew = 0
  local host = Rtc.getInfo(session)
  local target = (last.days + off.days) * SECONDS_PER_DAY
    + (last.hours + off.hours) * 3600 + (last.minutes + off.minutes) * 60
    + (last.seconds + off.seconds)
  local cur = Rtc.getDayCount(host) * SECONDS_PER_DAY + host.hour * 3600 + host.minute * 60 + host.second
  local behind = cur - target
  if behind >= 0 and behind <= Rtc.IMPORT_HOST_CLOCK_WINDOW then return 0 end
  session.rtcSkew = target - cur
  return session.rtcSkew
end

function Rtc.setFixed(spec)
  if spec == nil then
    state.fixedBase = nil
    return
  end
  local f = type(spec) == "table" and spec or parseFixed(spec)
  if not f then error("Rtc.setFixed: bad spec " .. tostring(spec), 2) end
  state.fixedBase = linearOf(f)
  state.errorStatus = nil
end

function Rtc.advance(minutes, seconds)
  state.advanced = state.advanced + (tonumber(minutes) or 0) * 60 + (tonumber(seconds) or 0)
  return state.advanced
end

function Rtc.setHostClock(fn)
  state.host = fn
  state.errorStatus = nil
end

function Rtc.reset()
  state.errorStatus = nil
  state.fixedBase = nil
  state.advanced = 0
  state.host = nil
  Rtc._info = nil
  Rtc.localTime = Rtc.newTime(0, 0, 0, 0)
end

function Rtc.fixedActive()
  return state.fixedBase ~= nil or (os.getenv and (os.getenv("POKEPORT_RTC") or "") ~= "")
end

return Rtc
