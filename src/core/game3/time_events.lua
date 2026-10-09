local Rtc = require("src.core.game3.rtc")
local Constants = require("src.core.game3.constants")

local TimeEvents = {}

-- pokeemerald/src/clock.c:44
TimeEvents.PER_DAY_ORDER = {
  "ClearDailyFlags",
  "UpdateDewfordTrendPerDay",
  "UpdateTVShowsPerDay",
  "UpdateWeatherPerDay",
  "UpdatePartyPokerusTime",
  "UpdateMirageRnd",
  "UpdateBirchState",
  "UpdateFrontierManiac",
  "UpdateFrontierGambler",
  "SetShoalItemFlag",
  "SetRandomLotteryNumber",
}

-- pokeemerald/src/clock.c:70
TimeEvents.PER_MINUTE_ORDER = {
  "BerryTreeTimeUpdate",
}

local perDay, perMinute = {}, {}
local inPokemonCenter = nil

function TimeEvents.onDay(name, fn)
  assert(type(name) == "string" and name ~= "", "TimeEvents.onDay needs a name")
  perDay[name] = fn
end

function TimeEvents.onMinute(name, fn)
  assert(type(name) == "string" and name ~= "", "TimeEvents.onMinute needs a name")
  perMinute[name] = fn
end

function TimeEvents.setPokemonCenterCheck(fn)
  inPokemonCenter = fn
end

function TimeEvents.handlers()
  return perDay, perMinute
end

function TimeEvents.reset()
  perDay, perMinute = {}, {}
  inPokemonCenter = nil
  TimeEvents._tickState = 0
  TimeEvents.installDefaults()
end

local function storeOf(session, opts)
  if opts and opts.store then return opts.store end
  local Space = package.loaded["src.core.game3.scripting.space"]
  local Runtime = package.loaded["src.core.game3.runtime"]
  local live = Runtime and Runtime.getSession and Runtime.getSession() or nil
  if Space and Space.store and (live == nil or live == session) then return Space.store end
  if type(session) == "table" and type(session.store) == "table" then
    session.store.flags = session.store.flags or {}
    session.store.vars = session.store.vars or {}
    return session.store
  end
  return { flags = {}, vars = {} }
end

local function flags()
  return require("src.core.game3.scripting.flags")
end

local function consts(session)
  return Constants.of(Constants.versionOf(session))
end

local function clockPolicy(session)
  return require("src.core.game3.profile").forSession(session).clock or {}
end

local function policyHandlers(session, kind, defaults)
  local policy = clockPolicy(session)
  if not policy.timeEventsModule then return defaults, policy end
  local own = require(policy.timeEventsModule)[kind] or {}
  local handlers = {}
  for name, fn in pairs(defaults) do handlers[name] = fn end
  for name, fn in pairs(own) do handlers[name] = fn end
  return handlers, policy
end

local function orderedCall(order, handlers, allowExtra, ...)
  local seen = {}
  for _, name in ipairs(order) do
    seen[name] = true
    local fn = handlers[name]
    if fn then fn(...) end
  end
  if allowExtra == false then return end
  local extra = {}
  for name in pairs(handlers) do
    if not seen[name] then extra[#extra + 1] = name end
  end
  table.sort(extra)
  for _, name in ipairs(extra) do handlers[name](...) end
end

-- pokeemerald/src/event_data.c:50
local function clearDailyFlags(session, _daysSince, _localTime, store)
  local C = consts(session)
  local lo = C:require("flags", "DAILY_FLAGS_START")
  local hi = C:require("flags", "DAILY_FLAGS_END")
  local F = flags()
  for id = lo, hi do F.setFlag(store, nil, id, false) end
end

-- pokeemerald/src/pokemon.c:6170
local function updatePartyPokerusTime(session, daysSince)
  local Pokemon = require("src.core.game3.pokemon")
  if Pokemon.updatePartyPokerusTime then Pokemon.updatePartyPokerusTime(daysSince, session) end
end

function TimeEvents.installDefaults()
  if perDay.ClearDailyFlags == nil then perDay.ClearDailyFlags = clearDailyFlags end
  if perDay.UpdatePartyPokerusTime == nil then perDay.UpdatePartyPokerusTime = updatePartyPokerusTime end
  if perMinute.BerryTreeTimeUpdate == nil then
    -- pokeemerald/src/clock.c:70
    perMinute.BerryTreeTimeUpdate = function(s, m)
      if require("src.core.game3.capabilities").gate(s, "berry_trees") then
        require("src.core.game3.rse.berry_trees").timeUpdate(s, m)
      end
    end
  end
end

-- pokeemerald/src/clock.c:18
function TimeEvents.init(session, opts)
  local store = storeOf(session, opts)
  local C = consts(session)
  local F = flags()
  F.setFlag(store, nil, C:require("flags", "FLAG_SYS_CLOCK_SET"), true)
  local lt = Rtc.calcLocalTime(session)
  if type(session) == "table" then session.lastBerryTreeUpdate = Rtc.copyTime(lt) end
  F.setVar(store, nil, C:require("vars", "VAR_DAYS"), lt.days)
  return lt
end

-- pokeemerald/src/clock.c:36
local function updatePerDay(session, lt, store)
  local C = consts(session)
  local F = flags()
  local varDays = C:require("vars", "VAR_DAYS")
  local days = Rtc.u16(tonumber(F.getVar(store, nil, varDays)) or 0)
  if days ~= lt.days and days <= lt.days then
    local daysSince = Rtc.u16(lt.days - days)
    local handlers, policy = policyHandlers(session, "perDay", perDay)
    orderedCall(policy.perDayOrder or TimeEvents.PER_DAY_ORDER, handlers, policy.allowExtraTimeHandlers, session, daysSince, lt, store)
    F.setVar(store, nil, varDays, lt.days)
    return daysSince
  end
  return nil
end

-- pokeemerald/src/clock.c:59
local function updatePerMinute(session, lt, store)
  local last = type(session) == "table" and session.lastBerryTreeUpdate or nil
  local diff = Rtc.calcTimeDifference(last or Rtc.newTime(0, 0, 0, 0), lt)
  local minutes = Rtc.timeMinutes(diff)
  if minutes ~= 0 and minutes >= 0 then
    local handlers, policy = policyHandlers(session, "perMinute", perMinute)
    orderedCall(policy.perMinuteOrder or TimeEvents.PER_MINUTE_ORDER, handlers, policy.allowExtraTimeHandlers, session, minutes, lt, store)
    if type(session) == "table" then session.lastBerryTreeUpdate = Rtc.copyTime(lt) end
    return minutes
  end
  return nil
end

local CENTERS_PACK = "data/generated/gba/field_specials/manifest.lua"
local centerSets = {}

-- pokeemerald/src/field_specials.c:3887
local function cachedPokemonCenter(session)
  local GameVersion = require("src.core.GameVersion")
  local key = GameVersion.get() .. ":" .. tostring(GameVersion.cachePrefix())
  local set = centerSets[key]
  if not set then
    local src = require("src.core.game3.dataset").cache():read(CENTERS_PACK)
    if type(src) ~= "string" then error("time_events: " .. CENTERS_PACK .. " missing from the cache") end
    local man = assert(load(src, "@" .. CENTERS_PACK, "t", {}))()
    set = {}
    for _, id in ipairs(man.pokemonCenters or {}) do set[id] = true end
    centerSets[key] = set
  end
  local map = type(session) == "table" and session.map or nil
  return map ~= nil and set[map] == true
end

function TimeEvents.inPokemonCenter(session)
  if inPokemonCenter then return inPokemonCenter(session) == true end
  return cachedPokemonCenter(session)
end

-- pokeemerald/src/clock.c:26
function TimeEvents.run(session, opts)
  opts = opts or {}
  if not Rtc.enabled(session) then return false end
  local store = storeOf(session, opts)
  local C = consts(session)
  if not flags().getFlag(store, nil, C:require("flags", "FLAG_SYS_CLOCK_SET")) then return false end
  if not clockPolicy(session).updateInPokemonCenters then
    local inPc = opts.inPokemonCenter
    if inPc == nil then inPc = TimeEvents.inPokemonCenter(session) end
    if inPc then return false end
  end
  local lt = Rtc.calcLocalTime(session)
  local daysSince = updatePerDay(session, lt, store)
  local minutes = updatePerMinute(session, lt, store)
  return true, daysSince, minutes
end

-- pokeemerald/src/field_tasks.c:148
TimeEvents.UPDATE_INTERVAL_BIT = 4096
TimeEvents._tickState = 0

-- pokeemerald/src/field_tasks.c:150
function TimeEvents.tick(session, vblankCounter, opts)
  local on = math.floor((tonumber(vblankCounter) or 0) / TimeEvents.UPDATE_INTERVAL_BIT) % 2 == 1
  if TimeEvents._tickState == 0 then
    if on then
      TimeEvents._tickState = 1
      return TimeEvents.run(session, opts)
    end
  elseif not on then
    TimeEvents._tickState = 0
  end
  return false
end

TimeEvents.installDefaults()

return TimeEvents
