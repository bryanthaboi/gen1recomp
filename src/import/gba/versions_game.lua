local GameVersion = require("src.core.GameVersion")

local VersionsGame = {}

VersionsGame.GAMES = {
  firered = "src.import.gba.versions",
  leafgreen = "src.import.gba.versions",
}

VersionsGame.FALLBACK = "firered"

local cache, warned = {}, {}

local function log(msg)
  print("[versions_game] " .. tostring(msg))
end

local function load(id)
  local path = VersionsGame.GAMES[id]
  if type(path) ~= "string" or path == "" then return nil end
  local ok, mod = pcall(require, path)
  if ok and type(mod) == "table" then return mod end
  return nil
end

function VersionsGame.game(id)
  if type(id) ~= "string" or id == "" then
    local active = GameVersion.get()
    local info = GameVersion.info(active)
    id = (info and (info.generation or 1) == 3) and active or VersionsGame.FALLBACK
  end
  local row = cache[id]
  if row then return row end
  local mod = load(id)
  if mod then
    cache[id] = mod
    return mod
  end
  if id == VersionsGame.FALLBACK then
    error("versions_game: fallback row '" .. VersionsGame.FALLBACK .. "' does not load")
  end
  if not warned[id] then
    warned[id] = true
    log("no version table for '" .. id .. "'; using " .. VersionsGame.FALLBACK)
  end
  return VersionsGame.game(VersionsGame.FALLBACK)
end

function VersionsGame.register(id, modulePath)
  if type(id) ~= "string" or id == "" then return false end
  if type(modulePath) ~= "string" or modulePath == "" then return false end
  VersionsGame.GAMES[id] = modulePath
  cache[id] = nil
  return true
end

function VersionsGame.reset()
  cache = {}
  warned = {}
end

return VersionsGame
