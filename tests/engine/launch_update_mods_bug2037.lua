package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local LaunchOptions = require("src.core.LaunchOptions")
local ModUpdate = require("src.mods.ModUpdate")
local LauncherMods = require("src.mods.LauncherMods")
local Platform = require("src.core.Platform")
local CartStore = require("src.carts.CartStore")
local RomImporter = require("src.import.RomImporter")

local realGetenv = os.getenv
local env = {}
os.getenv = function(name)
  if env[name] ~= nil then return env[name] end
  return realGetenv(name)
end

local function tasks(argv, rawArgv, uri)
  return LaunchOptions.tasks(argv, rawArgv, uri or false)
end

do
  eq(tasks({}, nil).mods, false, "with no flag the mods pass is off")
  eq(tasks({ "--update-mods" }, nil).mods, true, "--update-mods turns it on")
  eq(tasks({ "--updatemods" }, nil).mods, true,
    "--updatemods, the spelling from the request, does too")
  eq(tasks({ "-update-mods" }, nil).mods, true, "as does -update-mods")
  eq(tasks({}, { "--update-mods" }).mods, true,
    "a copy only in the raw argv is still found")
  eq(tasks({ "--update-mods", "--no-update-mods" }, nil).mods, false,
    "--no-update-mods beats the positive flag")
  eq(tasks({ "--updatemods", "--no-update-mods" }, nil).mods, false,
    "across the two spellings")
  eq(tasks({ "--update" }, nil).mods, false,
    "--update stays the engine updater and never touches mods")
  eq(tasks({ "--update-mods" }, nil).update, false,
    "and --update-mods never runs the engine updater")
  env.POKEPORT_LAUNCH_UPDATE_MODS = "1"
  eq(tasks({}, nil).mods, true, "the env var turns it on")
  eq(tasks({ "--no-update-mods" }, nil).mods, false, "a flag beats the env")
  env.POKEPORT_LAUNCH_UPDATE_MODS = "0"
  eq(tasks({}, nil).mods, false, "and 0 leaves it off")
  env.POKEPORT_LAUNCH_UPDATE_MODS = "maybe"
  eq(tasks({}, nil).mods, false, "anything else leaves it off")
  env.POKEPORT_LAUNCH_UPDATE_MODS = nil
end

do
  local uri = LaunchOptions.parseURI(
    "gen1recomp++://launch?game=red&update_mods=1")
  eq(uri and uri.updateMods, true, "a launch URI can ask for the mods pass")
  eq(tasks({}, nil, uri).mods, true, "and the task picks it up")
  eq(tasks({ "--no-update-mods" }, nil, uri).mods, false,
    "the command line still wins over the URI")
  local built = LaunchOptions.uriFor("red", { updateMods = true })
  check(built and built:find("update_mods=1", 1, true) ~= nil,
    "uriFor writes the parameter")
  eq(LaunchOptions.parseURI(built).updateMods, true, "which reads back")
  local intent = LaunchOptions.fromGame("red")
  eq(intent and intent.tasks.mods, false,
    "a legacy Android intent never runs the mods pass")
  check(LaunchOptions.commandFor("red", nil, { mods = true })
    :find("--update-mods", 1, true) ~= nil,
    "the shortcut command quotes the flag")
end

local RELEASES = {
  { version = "2.0.0", zip = { url = "https://example.invalid/a.zip" } },
}

local oldBeginFetch = ModUpdate.beginFetchReleases
local oldBeginZip = ModUpdate.beginDownloadZip
local oldPumpZip = ModUpdate.pumpDownloadZip
local oldInstall = LauncherMods.installDownloadedZip
local oldDeps = LauncherMods.checkDependencies
local oldRemote = Platform.canFetchRemote
local oldCartList = CartStore.list
local oldCartIndex = CartStore.index
local oldCartListFor = CartStore.listFor

local failId = nil
local installs = {}
local depIssue = false

ModUpdate.beginFetchReleases = function() return {} end
ModUpdate.beginDownloadZip = function() return {} end
ModUpdate.pumpDownloadZip = function()
  love.filesystem.write("install.zip", "BYTES")
  return true, "install.zip"
end
LauncherMods.installDownloadedZip = function(id, _, version)
  installs[#installs + 1] = id
  if id == failId then return nil, "the archive had no manifest" end
  return true, version
end
LauncherMods.checkDependencies = function()
  return { hasIssues = depIssue }
end
Platform.canFetchRemote = function() return true end
CartStore.list = function() return {} end
CartStore.listFor = function() return {} end
CartStore.index = function() return {} end

local function info(status, best)
  return { status = status, latest = best and best.version or nil,
           best = best, releases = RELEASES }
end

local function launcher(allCurrent)
  local ri = setmetatable({
    mods = {
      { id = "one", name = "One", version = "1.0.0", github = "a/one" },
      { id = "two", name = "Two", version = "1.0.0" },
    },
    modUpdateInfo = {
      one = allCurrent and info("current") or info("available", RELEASES[1]),
    },
    activeCart = {},
    carts = {},
    findLoaded = true,
    findIndex = { mods = {}, carts = {} },
  }, RomImporter)
  ri._refreshMods = function() end
  ri._syncModUpdateInfo = function() end
  return ri
end

local function run(ri)
  local confirms, fired = 0, 0
  for _ = 1, 40 do
    if ri._modConfirm then confirms = confirms + 1 end
    if ri:_fireAutoUpdateAll() then fired = fired + 1 end
    if not ri._updateAll and not ri._autoUpdateAll then break end
    ri:_pumpUpdateAll()
    ri:_pumpModInstall()
  end
  return confirms, fired
end

do
  installs = {}
  local ri = launcher()
  local results = {}
  check(ri:autoUpdateAll(function(r) results[#results + 1] = r end),
    "the launch flag starts the sweep")
  local confirms, fired = run(ri)
  eq(confirms, 0, "with no confirm modal for a CLI launch to answer")
  eq(#installs, 1, "the outdated mod is installed")
  eq(installs[1], "one", "by id")
  eq(fired, 1, "the caller hears back once")
  eq(#results, 1, "exactly once")
  eq((results[1] or {}).ok, true, "that it worked")
  eq((results[1] or {}).updated, 1, "with the count")
  eq(ri.modNotice and ri.modNotice.text, "Updated 1 items.",
    "and the launcher shows the same notice the button would")
  eq(ri._autoUpdateAll, nil, "the auto job is cleared")
  eq(ri._busy, nil, "with the overlay down")
end

do
  installs = {}
  local ri = launcher(true)
  local results = {}
  ri:autoUpdateAll(function(r) results[#results + 1] = r end)
  run(ri)
  eq(#installs, 0, "nothing outdated, nothing installed")
  eq((results[1] or {}).ok, true, "an up-to-date set still boots")
  eq(ri.modNotice and ri.modNotice.text, "Everything is up to date.",
    "and says so")
end

do
  installs = {}
  failId = "one"
  local ri = launcher()
  local results = {}
  ri:autoUpdateAll(function(r) results[#results + 1] = r end)
  run(ri)
  failId = nil
  eq((results[1] or {}).ok, false, "a failed install is reported as not ok")
  eq(#((results[1] or {}).failures or {}), 1, "with the failure line")
  check(ri.modNotice and not ri.modNotice.ok,
    "and the failure stays on the launcher")
end

do
  installs = {}
  depIssue = true
  local ri = launcher()
  local results = {}
  ri:autoUpdateAll(function(r) results[#results + 1] = r end)
  run(ri)
  depIssue = false
  eq((results[1] or {}).ok, false,
    "an update that raises the dependency resolver is not ok")
  check(ri._modDepResolver ~= nil, "so the resolver can be answered")
end

do
  installs = {}
  local ri = launcher()
  ri._syncModUpdateInfo = function(self) self._modInfoFetch = {} end
  local results = {}
  ri:autoUpdateAll(function(r) results[#results + 1] = r end)
  eq((ri._updateAll or {}).stage, "check",
    "the sweep waits on the release checks")
  ri:_cancelUpdateAll()
  run(ri)
  eq((results[1] or {}).cancelled, true, "cancel is reported as cancelled")
  eq(#installs, 0, "with nothing installed")
end

do
  Platform.canFetchRemote = function() return false end
  local ri = launcher()
  local results = {}
  eq(ri:autoUpdateAll(function(r) results[#results + 1] = r end), false,
    "no remote fetch, no sweep")
  run(ri)
  eq((results[1] or {}).skipped, true, "reported as skipped")
  Platform.canFetchRemote = function() return true end
end

do
  local ri = launcher()
  ri.safeMode = true
  local results = {}
  eq(ri:autoUpdateAll(function(r) results[#results + 1] = r end), false,
    "safe mode refuses the sweep")
  run(ri)
  eq((results[1] or {}).skipped, true, "and reports it skipped")
  check(ri.modNotice ~= nil, "with a notice saying why")
end

do
  local ri = launcher()
  local switched
  ri._switchTab = function(self, id) switched = id; self.tab = id end
  ri:autoUpdateAll(function() end, { tab = "mods" })
  eq(switched, "mods", "the sweep can put the launcher on the MODS tab")
  eq(ri:autoUpdateAll(function() end), false,
    "a second request while one runs is ignored")
  run(ri)
end

do
  installs = {}
  local ri = launcher()
  check(ri:pressUpdateAllMods(), "the button still starts the sweep")
  ri:_pumpUpdateAll()
  eq((ri._updateAll or {}).stage, "confirm", "and still asks first")
  eq((ri._modConfirm or {}).kind, "updateAllRun", "with the modal up")
  eq(#installs, 0, "installing nothing before the answer")
  ri._modConfirm = nil
  ri:_pumpUpdateAll()
end

do
  local forced = {}
  local ri = launcher()
  ri._syncModUpdateInfo = function(_, force) forced[#forced + 1] = force end
  ri:autoUpdateAll(function() end)
  run(ri)
  eq(forced[1], false, "the launch flag keeps the 6h release cache")
  local rb = launcher()
  rb._syncModUpdateInfo = function(_, force) forced[#forced + 1] = force end
  rb:pressUpdateAllMods()
  eq(forced[2], true, "while the button still forces a fresh check")
  rb._modConfirm = nil
  rb._updateAll = nil
  rb._busy = nil
end

do
  local f = assert(io.open("main.lua", "r"))
  local src = f:read("*a")
  f:close()
  check(src:find("Importer:autoUpdateAll(", 1, true) ~= nil,
    "main.lua runs the sweep on a launcher it opens for the flag")
  check(src:find("if not Prelaunch then bootAfterMods()", 1, true) ~= nil,
    "after the pre-boot stage")
  check(src:find("onBoot = function(v, c, opts)", 1, true) ~= nil
    and src:find("if onBoot and onBoot(version, cartId, opts) then return end", 1, true) ~= nil,
    "Play after a failed sweep boots through the shortcut, keeping --slot")
  check(src:find("if launcherBusy() then\n    deferredLaunchRequest = request", 1, true) ~= nil,
    "a launch request during a download waits instead of dropping the launcher")
  check(src:find("if deferredLaunchRequest and not launcherBusy() then", 1, true) ~= nil,
    "and runs once the launcher is idle")
end

ModUpdate.beginFetchReleases = oldBeginFetch
ModUpdate.beginDownloadZip = oldBeginZip
ModUpdate.pumpDownloadZip = oldPumpZip
LauncherMods.installDownloadedZip = oldInstall
LauncherMods.checkDependencies = oldDeps
Platform.canFetchRemote = oldRemote
CartStore.list = oldCartList
CartStore.index = oldCartIndex
CartStore.listFor = oldCartListFor
os.getenv = realGetenv

T.finish("launch --update-mods (#2037)")
