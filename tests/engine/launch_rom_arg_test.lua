package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
love.data = love.data or {}
love.data.hash = love.data.hash or function() return "digest" end
love.data.encode = love.data.encode or function(_, _, value) return value end

local LaunchOptions = require("src.core.LaunchOptions")
local RomImporter = require("src.import.RomImporter")

local function read(path)
  local file = assert(io.open(path, "rb"))
  local body = file:read("*a")
  file:close()
  return body
end

local launchSource = assert(read("main.lua")
  :match("local function startLaunchRequest%(request%).-\nend\n"))

local function launchScenario(opts)
  local rec = { booted = {}, slots = {}, launchers = {}, romImports = {} }
  local env = setmetatable({ launchedIntoGame = false }, { __index = _G })
  local ready = opts.ready or {}
  local importer = {
    startLaunchRom = function(_, path, version, onImported)
      rec.romImports[#rec.romImports + 1] = { path = path, version = version }
      rec.onImported = onImported
    end,
  }
  env.launcherBusy = function() return false end
  env.wantsModUpdate = function() return false end
  env.autoUpdateMods = function() end
  env.showLauncher = function(version)
    rec.launchers[#rec.launchers + 1] = version
    env.Importer = env.Importer or importer
  end
  env.bootGame = function(version, cartId)
    rec.booted[#rec.booted + 1] = { version = version, cart = cartId }
  end
  env.LaunchOptions = {
    selectSlot = function(version, slot) rec.slots[#rec.slots + 1] = { version, slot } end,
  }
  local prelaunch = { new = function(o) rec.prelaunchVersion = o.version return nil end }
  local window = { observe = function() end, flush = function() end }
  env.require = function(name)
    if name == "src.import.RomImporter" then
      return { isReady = function(version) return ready[version] == true end }
    end
    if name == "src.core.Prelaunch" then return prelaunch end
    if name == "src.import.LauncherWindow" then return window end
    error("unexpected module " .. name)
  end
  local chunk = assert(loadstring(launchSource .. "\nreturn startLaunchRequest",
    "@main.lua:startLaunchRequest"))
  setfenv(chunk, env)
  return chunk(), rec, env, ready
end

do
  local request = LaunchOptions.resolveRequest({ "--game=red" }, nil)
  eq(request.rom, nil, "without --rom there is no ROM to import")
end

do
  local request = LaunchOptions.resolveRequest(
    { "--game=blue", "--rom=C:\\Roms\\Pokemon Blue.gb" }, nil)
  eq(request.rom, "C:\\Roms\\Pokemon Blue.gb", "--rom keeps a path with spaces")
end

do
  local request = LaunchOptions.resolveRequest({ "--game=red", "--rom=" }, nil)
  eq(request.rom, nil, "an empty --rom counts as none")
end

do
  local request = LaunchOptions.resolveRequest({ "--rom=crystal.gbc" }, nil)
  eq(request.rom, nil, "--rom without --game is ignored")
end

do
  local start, rec = launchScenario({ ready = { blue = true } })
  start({ game = "blue", rom = "blue.gb" })
  eq(#rec.romImports, 0, "an imported game ignores --rom")
  eq(rec.booted[1] and rec.booted[1].version, "blue", "and boots as before")
end

do
  local start, rec = launchScenario({})
  start({ game = "blue", rom = "blue.gb", slot = "2" })
  eq(rec.launchers[1], "blue", "a game not imported yet opens the launcher on its tab")
  eq(rec.romImports[1] and rec.romImports[1].path, "blue.gb", "and imports the --rom path")
  eq(rec.romImports[1] and rec.romImports[1].version, "blue",
    "checked against the --game version")
  eq(#rec.booted, 0, "nothing boots before the import finishes")
end

do
  local start, rec, env, ready = launchScenario({})
  start({ game = "blue", rom = "blue.gb", slot = "2" })
  ready.blue = true
  rec.onImported("blue")
  eq(rec.prelaunchVersion, "blue", "a finished import goes through the prelaunch stage")
  eq(rec.slots[1] and rec.slots[1][2], "2", "keeps --slot")
  eq(rec.booted[1] and rec.booted[1].version, "blue", "and boots the game")
  eq(env.launchedIntoGame, true, "as a shortcut session, so closing the window exits")
end

do
  local start, rec, _, ready = launchScenario({})
  start({ game = "blue", rom = "blue.gb" })
  rec.onImported("blue")
  eq(#rec.romImports, 1, "an import that leaves the game not ready is not retried")
  eq(#rec.booted, 0, "and does not boot")
  eq(ready.blue, nil, "the game stays not ready")
end

local function launchImporter(version)
  local errors = {}
  local imp = setmetatable({
    tab = version,
    _launchRom = { version = version, onImported = function() end },
    _versionForSha1 = function() return "red" end,
  }, { __index = RomImporter })
  imp.setError = function(self, message, errorVersion)
    errors[#errors + 1] = { message = message, version = errorVersion }
    RomImporter.setError(self, message, errorVersion)
  end
  return imp, errors
end

do
  local imp, errors = launchImporter("blue")
  imp:startData(string.rep("\0", 0x100000), "red.gb")
  eq(errors[1] and errors[1].version, "blue", "a ROM of another game errors on the --game tab")
  eq(imp.errorVersion, "blue", "the launcher shows it on that tab")
  check(imp.workState ~= "working", "and the other game is not imported")
  eq(imp.importing, nil, "nothing is extracting")
  eq(imp._launchRom, nil, "a later manual import is not tied to the launch")
end

do
  local imp = launchImporter("blue")
  imp:startData("not a rom", "blue.gb")
  eq(imp.errorVersion, "blue", "a ROM that fails to import shows its error on the --game tab")
end

T.finish("launch --rom argument")
