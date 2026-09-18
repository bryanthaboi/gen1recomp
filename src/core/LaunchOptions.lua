-- Launch options: boot straight into a game, skipping the launcher.
--
--   love . --game=red               -- boot Red
--   love . --game=yellow --slot=2   -- boot Yellow on save slot 2
--   love . --game=gold              -- boot Gold (src/core/Game2.lua)
--   love . --game=firered           -- boot FireRed (src/core/game3.lua)
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
local normalizeVersion
local argValue
local argFlag

local function trim(value)
  if type(value) ~= "string" then return nil end
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  return value ~= "" and value or nil
end

local function normalizeCart(value)
  value = trim(value)
  if not value or #value > 64 or not value:match("^[%w_%-]+$") then
    return nil
  end
  return value
end

local function encodeURIComponent(value)
  return tostring(value):gsub("([^%w%-%._~])", function(char)
    return ("%%%02X"):format(char:byte())
  end)
end

local function decodeURIComponent(value)
  local result = {}
  local index = 1
  while index <= #value do
    local char = value:sub(index, index)
    if char == "%" then
      local hex = value:sub(index + 1, index + 2)
      if not hex:match("^%x%x$") then return nil end
      result[#result + 1] = string.char(tonumber(hex, 16))
      index = index + 3
    else
      result[#result + 1] = char
      index = index + 1
    end
  end
  return table.concat(result)
end

local function booleanValue(value)
  if value == nil then return nil end
  value = trim(value)
  if not value then return true end
  value = value:lower()
  if value == "1" or value == "true" or value == "yes" or value == "on" then
    return true
  end
  if value == "0" or value == "false" or value == "no" or value == "off" then
    return false
  end
  return nil
end

-- Set by main.lua when a requested game turns out not to be importable yet:
-- the launcher opens on that tab instead of booting.
LaunchOptions.pendingTab = nil

normalizeVersion = function(v)
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
    c = "crystal", crystal = "crystal",
    firered = "firered", fr = "firered", fire_red = "firered",
  }
  v = alias[v] or v
  if GameVersion.VERSIONS and not GameVersion.VERSIONS[v] then return nil end
  return v
end

-- Pull "--flag value" (and "--flag=value") out of LOVE's arg table.
argValue = function(argv, name)
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

argFlag = function(argv, name)
  if type(argv) ~= "table" then return false end
  for i = 1, #argv do
    local a = argv[i]
    if a == "--" .. name or a == "-" .. name then return true end
  end
  return false
end

local cachedIntentGame = nil

local function uriAuthority(uri)
  if type(uri) ~= "string" or uri == "" then return nil end

  local withoutFragment = uri:match("^([^#]*)")
  local queryStart = withoutFragment:find("?", 1, true)
  local authority = queryStart and withoutFragment:sub(1, queryStart - 1)
    or withoutFragment
  local scheme, host, path = authority:match(
    "^([%a][%w+%-%.]*):%/%/([^/]*)(.*)$")
  if not scheme or scheme:lower() ~= "gen1recomp++"
      or host:lower() ~= "launch" or (path ~= "" and path ~= "/") then
    return nil
  end
  return withoutFragment, queryStart
end

function LaunchOptions.isLaunchURI(uri)
  return uriAuthority(uri) ~= nil
end

function LaunchOptions.parseURI(uri)
  local withoutFragment, queryStart = uriAuthority(uri)
  if not withoutFragment then return nil end
  local query = queryStart and withoutFragment:sub(queryStart + 1) or ""

  local values = {}
  for pair in query:gmatch("[^&]+") do
    local equals = pair:find("=", 1, true)
    local rawKey = equals and pair:sub(1, equals - 1) or pair
    local rawValue = equals and pair:sub(equals + 1) or ""
    local key = decodeURIComponent(rawKey)
    local value = decodeURIComponent(rawValue)
    if not key or not value then return nil end
    key = key:lower()
    if key ~= "" and values[key] == nil then
      values[key] = value
    end
  end

  local request = {
    source = "uri",
    game = normalizeVersion(values.game),
    cart = normalizeCart(values.cart),
    slot = trim(values.slot),
    gameSpecified = values.game ~= nil,
    cartSpecified = values.cart ~= nil,
  }
  request.launcher = booleanValue(values.launcher)
  request.sync = booleanValue(values.sync)
  request.update = booleanValue(values.update)
  return request
end

local function launchURIRaw(method)
  if type(love) ~= "table" or type(love.system) ~= "table"
      or type(love.system[method]) ~= "function" then
    return nil
  end
  local ok, uri = pcall(love.system[method])
  if not ok or type(uri) ~= "string" or uri == "" then return nil end
  return uri
end

local function launchURIRequest()
  return LaunchOptions.parseURI(launchURIRaw("getLaunchURI"))
end

local function intentGame()
  if cachedIntentGame == nil then
    if type(love) == "table" and type(love.system) == "table"
        and type(love.system.getOS) == "function"
        and love.system.getOS() == "Android"
        and type(love.system.getLaunchGame) == "function" then
      cachedIntentGame = normalizeVersion(love.system.getLaunchGame()) or false
    else
      cachedIntentGame = false
    end
  end
  return cachedIntentGame or nil
end

local function request(argv, rawArgv, uri)
  local game = normalizeVersion(argValue(argv, "game"))
  if not game then
    if uri and uri.gameSpecified then
      game = uri.game
    else
      game = intentGame()
        or normalizeVersion(os.getenv("POKEPORT_GAME"))
        or normalizeVersion(os.getenv("POKEPORT_LAUNCH"))
    end
  end
  local slot = trim(argValue(argv, "slot"))
    or (uri and uri.slot)
    or trim(os.getenv("POKEPORT_SLOT"))
  local rawCart = argValue(argv, "cart")
  local cart = normalizeCart(rawCart)
  local cartSpecified = rawCart ~= nil
  if rawCart == nil and uri and uri.cartSpecified then
    cart = uri.cart
    cartSpecified = true
  end
  local launcher
  if argFlag(argv, "launcher") or argFlag(rawArgv, "launcher") then
    launcher = true
  elseif uri and uri.launcher ~= nil then
    launcher = uri.launcher
  else
    launcher = os.getenv("POKEPORT_FORCE_LAUNCHER") == "1"
  end
  return {
    game = game,
    cart = cart,
    slot = slot,
    cartSpecified = cartSpecified,
    launcher = launcher,
    uri = uri,
  }
end

-- Returns version, slotId (either may be nil).  Command line wins over env,
-- so a shortcut can override a machine-wide default.
function LaunchOptions.resolve(argv)
  local resolved = LaunchOptions.resolveRequest(argv, nil)
  return resolved.game, resolved.slot
end

function LaunchOptions.forceLauncher(argv)
  return LaunchOptions.resolveRequest(argv, nil).launcher
end

local function taskFlag(argv, rawArgv, name, env, uriValue)
  if argFlag(argv, "no-" .. name) or argFlag(rawArgv, "no-" .. name) then
    return false
  end
  if argFlag(argv, name) or argFlag(rawArgv, name) then return true end
  if uriValue ~= nil then return uriValue end
  local v = os.getenv(env)
  if v == "1" then return true end
  if v == "0" then return false end
  return nil
end

function LaunchOptions.tasks(argv, rawArgv, uri)
  uri = uri or launchURIRequest()
  return {
    sync = taskFlag(argv, rawArgv, "sync", "POKEPORT_LAUNCH_SYNC",
      uri and uri.sync),
    update = taskFlag(argv, rawArgv, "update", "POKEPORT_LAUNCH_UPDATE",
      uri and uri.update) == true,
  }
end

function LaunchOptions.resolveRequest(argv, rawArgv)
  local uri = launchURIRequest()
  local resolved = request(argv, rawArgv, uri)
  resolved.tasks = LaunchOptions.tasks(argv, rawArgv, uri)
  return resolved
end

function LaunchOptions.pollURI()
  return launchURIRaw("pollLaunchURI")
end

function LaunchOptions.fromGame(game)
  local normalized = normalizeVersion(game)
  if not normalized then return nil end
  local tasks = LaunchOptions.tasks({}, {})
  tasks.update = false
  return {
    source = "intent",
    game = normalized,
    cart = nil,
    cartSpecified = false,
    slot = nil,
    launcher = false,
    tasks = tasks,
  }
end

function LaunchOptions.uriFor(version, options)
  options = options or {}
  version = normalizeVersion(version)
  if not version then return nil end
  local query = { "game=" .. encodeURIComponent(version) }
  local cart = normalizeCart(options.cart)
  if cart then query[#query + 1] = "cart=" .. encodeURIComponent(cart) end
  local slot = trim(options.slot)
  if slot then query[#query + 1] = "slot=" .. encodeURIComponent(slot) end
  if options.launcher ~= nil then
    query[#query + 1] = "launcher=" .. (options.launcher and "1" or "0")
  end
  if options.sync ~= nil then
    query[#query + 1] = "sync=" .. (options.sync and "1" or "0")
  end
  if options.update ~= nil then
    query[#query + 1] = "update=" .. (options.update and "1" or "0")
  end
  return "gen1recomp++://launch?" .. table.concat(query, "&")
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
function LaunchOptions.commandFor(version, slot, tasks)
  local cmd = "--game " .. tostring(version)
  if slot then cmd = cmd .. " --slot " .. tostring(slot) end
  if type(tasks) == "table" then
    if tasks.update then cmd = cmd .. " --update" end
    if tasks.sync == false then cmd = cmd .. " --no-sync" end
  end
  return cmd
end

return LaunchOptions
