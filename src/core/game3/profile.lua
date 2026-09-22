local GameVersion = require("src.core.GameVersion")

local Profile = {}

Profile.FALLBACK_ID = "firered"

local cache = {}
local warned = {}

local function log(msg)
  print("[game3/profile] " .. tostring(msg))
end

local function load(id)
  local ok, row = pcall(require, "src.core.game3.profiles." .. id)
  if ok and type(row) == "table" and row.id == id then return row end
  return nil
end

function Profile.of(id)
  if type(id) ~= "string" or id == "" then return Profile.active() end
  local row = cache[id]
  if row then return row end
  row = load(id)
  if row then
    cache[id] = row
    return row
  end
  if id == Profile.FALLBACK_ID then
    error("game3 profile '" .. Profile.FALLBACK_ID .. "' is missing")
  end
  if not warned[id] then
    warned[id] = true
    log("no profile for '" .. id .. "'; using " .. Profile.active().id)
  end
  return Profile.active()
end

function Profile.active()
  local id = GameVersion.get()
  local info = GameVersion.info(id)
  if not info or (info.generation or 1) ~= 3 then id = Profile.FALLBACK_ID end
  local row = cache[id]
  if row then return row end
  row = load(id) or load(Profile.FALLBACK_ID)
  if not row then
    error("game3 profiles missing: " .. id .. " and " .. Profile.FALLBACK_ID)
  end
  cache[id] = row
  return row
end

function Profile.isGame3Version(id)
  local info = GameVersion.info(id)
  return info ~= nil and (info.generation or 1) == 3
end

function Profile.capabilitiesFor(session)
  local id = type(session) == "table" and session.version or nil
  return Profile.of(id).capabilities or {}
end

function Profile.has(session, capability)
  return Profile.capabilitiesFor(session)[capability] == true
end

function Profile.reset()
  cache = {}
  warned = {}
end

return Profile
