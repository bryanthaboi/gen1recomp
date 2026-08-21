-- Launch options: boot straight into a game, skipping the launcher.
--
--   love . --game=red               -- boot Red
--   love . --game=yellow --slot=2   -- boot Yellow on save slot 2
--   love . --game=gold              -- boot Gold (src/core/Game2.lua)
--   love . --game=red --launcher    -- open the launcher anyway (a shortcut
--                                      the player wants to edit)
--   POKEPORT_GAME=blue love .       -- same, for launchers that only pass env
--
-- The "--flag value" spelling parses here (argValue reads argv[i + 1]), but it
-- does not survive LOVE: boot.lua takes the first bare argument as a path to a
-- game to run, so `--game red` dies with "Cannot load game at path .../red"
-- before love.load is ever called, fused or not.  Only the "=" spelling is
-- reachable, so that is the one the docs quote.
--
-- This exists for the click-once cases: a desktop shortcut per game, a Steam
-- entry, an EmulationStation/Playnite entry, a handheld frontend.  Those all
-- want "start the thing" and treat any menu in between as a defect.
--
-- Everything here is pure resolution and validation -- no love.* beyond the
-- filesystem read that slot selection needs -- so the engine test tier can
-- cover the parsing without a window.

local GameVersion = require("src.core.GameVersion")

local LaunchOptions = {}

-- Set by main.lua when a requested game turns out not to be importable yet:
-- the launcher opens on that tab instead of booting.
LaunchOptions.pendingTab = nil

local function normalizeVersion(v)
  if type(v) ~= "string" then return nil end
  v = v:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if v == "" then return nil end
  -- Accept the aliases people actually type.
  local alias = {
    r = "red", red = "red",
    b = "blue", blue = "blue",
    y = "yellow", yellow = "yellow",
    g = "gold", gold = "gold",
    s = "silver", silver = "silver",
  }
  v = alias[v] or v
  if GameVersion.VERSIONS and not GameVersion.VERSIONS[v] then return nil end
  return v
end

-- Pull "--flag value" (and "--flag=value") out of LOVE's arg table.
local function argValue(argv, name)
  if type(argv) ~= "table" then return nil end
  for i = 1, #argv do
    local a = argv[i]
    if a == "--" .. name then
      return argv[i + 1]
    end
    local inline = type(a) == "string" and a:match("^%-%-" .. name .. "=(.*)$")
    if inline then return inline end
  end
  return nil
end

local function argFlag(argv, name)
  if type(argv) ~= "table" then return false end
  for i = 1, #argv do
    if argv[i] == "--" .. name then return true end
  end
  return false
end

local cachedIntentGame = nil

-- Returns version, slotId (either may be nil).  Command line wins over env,
-- so a shortcut can override a machine-wide default.
function LaunchOptions.resolve(argv)
  if cachedIntentGame == nil then
    if love.system and love.system.getOS and love.system.getOS() == "Android"
        and love.system.getLaunchGame then
      cachedIntentGame = normalizeVersion(love.system.getLaunchGame()) or false
    else
      cachedIntentGame = false
    end
  end
  local intentGame = cachedIntentGame or nil

  local game = normalizeVersion(argValue(argv, "game"))
    or intentGame
    or normalizeVersion(os.getenv("POKEPORT_GAME"))
    or normalizeVersion(os.getenv("POKEPORT_LAUNCH"))
  local slot = argValue(argv, "slot") or os.getenv("POKEPORT_SLOT")
  if type(slot) == "string" then
    slot = slot:gsub("^%s+", ""):gsub("%s+$", "")
    if slot == "" then slot = nil end
  end
  return game, slot
end

function LaunchOptions.forceLauncher(argv)
  return argFlag(argv, "launcher") or os.getenv("POKEPORT_FORCE_LAUNCHER") == "1"
end

-- Point a version at a save slot before it boots.  Accepts either a slot id
-- ("slot2") or a 1-based index ("2"), because a shortcut author should not
-- have to know the internal id scheme.  A slot that does not exist is
-- ignored: booting the game on its previous slot beats refusing to start.
-- Returns the id actually selected, or nil.
function LaunchOptions.selectSlot(version, slot)
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if not ok then return nil end
  local listed = SaveData.listSlots and SaveData.listSlots(version) or nil
  if type(listed) ~= "table" or #listed == 0 then return nil end

  local target
  local index = tonumber(slot)
  if index and listed[index] then
    target = listed[index].id
  else
    for _, s in ipairs(listed) do
      if s.id == slot then target = s.id break end
    end
  end
  if not target then return nil end
  pcall(SaveData.setActiveSlot, version, target)
  return target
end

-- The shortcut command a player would use for this game, for the launcher to
-- show and for docs to quote.
function LaunchOptions.commandFor(version, slot)
  local cmd = "--game " .. tostring(version)
  if slot then cmd = cmd .. " --slot " .. tostring(slot) end
  return cmd
end

return LaunchOptions
