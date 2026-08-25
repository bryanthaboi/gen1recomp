-- Launcher navigation performance seams.  MOD INDEX must not pay the full
-- MODS validation pass, background index prefetch must not create a blocking
-- overlay, and visible-row enrichment must be scheduled from update state
-- rather than from immediate-mode draw calls.
--   luajit tests/engine/launcher_navigation_perf.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local LauncherMods = require("src.mods.LauncherMods")
local ModIndex = require("src.mods.ModIndex")
local RomImporter = require("src.import.RomImporter")

check(type(LauncherMods.installedVersions) == "function",
  "LauncherMods exposes a lightweight installed-version scan")

do
  local old = LauncherMods.installedVersions
  local called = 0
  LauncherMods.installedVersions = function()
    called = called + 1
    return { alpha = "1.2.3" }
  end
  local imp = setmetatable({}, RomImporter)
  local installed = imp:_findInstalledMap()
  eq(called, 1, "MOD INDEX asks for the lightweight scan when MODS is cold")
  eq(installed.alpha, "1.2.3",
    "the lightweight scan supplies installed versions")
  LauncherMods.installedVersions = old
end

do
  local imp = setmetatable({ tab = "find", findLoaded = false }, RomImporter)
  imp._refreshFindSources = function(self)
    self.findSources = { { feed = "https://example.invalid/index.json" } }
  end
  local oldBegin = ModIndex.beginFetch
  ModIndex.beginFetch = function() return { test = true } end
  imp:_refreshFind(false)
  check(imp._findFetch ~= nil, "background index refresh starts asynchronously")
  eq(imp._busy, nil,
    "background index refresh does not block navigation with a loader")
  imp:_clearBusy()
  imp._findFetch = nil
  ModIndex.beginFetch = oldBegin
end

do
  local requests = 0
  local imp = setmetatable({ tab = "find", findLoaded = true,
    _findVisibleEntries = {
      { id = "one", thumbnail = "one.png", github = "a/one" },
      { id = "two", thumbnail = "two.png", github = "a/two" },
      { id = "three", thumbnail = "three.png", github = "a/three" },
    } }, RomImporter)
  imp._findThumb = function() return nil end
  imp._findThumbPending = function() return false end
  imp._findStatsCached = function() return nil end
  imp._startFindThumb = function() requests = requests + 1 end
  imp._requestFindStats = function() requests = requests + 1 end
  imp:_queueFindEnrichment()
  eq(requests, 4,
    "update schedules a bounded thumbnail and stats batch for visible rows")
end

do
  local requests = 0
  local imp = setmetatable({}, RomImporter)
  imp._findStatsCached = function() return nil end
  imp._requestFindStats = function() requests = requests + 1 end
  imp:_findStats({ id = "draw-only", github = "a/draw-only" })
  eq(requests, 0, "reading row stats during draw never starts a request")
end

do
  local f = assert(io.open("src/import/LauncherView.lua", "rb"))
  local src = f:read("*a")
  f:close()
  local start = assert(src:find("local function buildFindPanel", 1, true))
  local finish = assert(src:find("\nlocal function ", start + 1, true))
  local panel = src:sub(start, finish - 1)
  check(not panel:find("imp:_ensureMods()", 1, true),
    "MOD INDEX panel does not force the full MODS list")
end

T.finish("launcher_navigation_perf")
