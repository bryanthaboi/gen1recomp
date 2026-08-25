-- In-process launcher session teardown: Game:reset, Renderer canvas release,
-- SessionLifecycle mount/game tiers, and editor package.loaded discovery flush.
--   luajit tests/engine/launcher_session_teardown_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Runtime = require("src.mods.Runtime")
local Assets = require("src.render.Assets")
local LegacyCompat = require("src.mods.LegacyCompat")
local Game = require("src.core.Game")
local Game2 = require("src.core.Game2")
local Renderer = require("src.render.Renderer")
local StateStack = require("src.core.StateStack")
local SessionLifecycle = require("src.core.SessionLifecycle")
local MapLoader = require("src.world.MapLoader")
local World = require("src.world.gen2.World")

-- ---- Game:reset drops instance state, keeps methods ----------------------
do
  StateStack:init()
  StateStack:push({ name = "stale" })
  Game.mods = { id = "orphan" }
  Game.save = { money = 1 }
  Game.network = { live = true } -- future field: must not need a whitelist
  Game.stack = StateStack
  Game.renderer = Renderer
  Game.SKIN_FAST_FORWARD = 4
  Renderer.canvas = love.graphics.newCanvas(8, 8)

  -- Handle-style :release (Fetch/SyncClient) must not run as instance teardown.
  local shared = {
    release = function(self) self.killed = true end,
  }
  Game.sharedNet = shared

  Game:reset()

  check(type(Game.load) == "function", "Game:reset keeps methods")
  check(type(Game.reset) == "function", "Game:reset keeps itself")
  check(Game.mods == nil, "Game:reset clears mods")
  check(Game.save == nil, "Game:reset clears save")
  check(Game.network == nil, "Game:reset clears arbitrary future fields")
  check(Game.stack == nil, "Game:reset clears stack reference")
  check(Game.renderer == nil, "Game:reset clears renderer reference")
  check(StateStack:top() == nil, "Game:reset cleared the shared StateStack")
  check(shared.killed ~= true,
    "Game:reset does not call handle-style :release on session fields")
  check(Game.SKIN_FAST_FORWARD == 4,
    "Game:reset preserves module scalars like SKIN_FAST_FORWARD")
end

-- ---- endGameSession must leave Gen1 Game.load callable for Play-again ------
do
  Game.save = { money = 1 }
  Game.stack = { clear = function() end }
  -- Poison pattern from the Android crash: a field whose :release is a
  -- job-handle API.  Old reset called it as value:release() and could leave
  -- the singleton unbootable (Game.load nil → main.lua bootGame crash).
  local jobs = {}
  Game.linkFetch = {
    release = function(id) jobs[id] = nil end,
  }
  SessionLifecycle.endGameSession(Game)
  check(type(Game.load) == "function",
    "endGameSession leaves Game.load intact for the next bootGame")
  check(package.loaded["src.core.Game"] == Game
      or type((package.loaded["src.core.Game"] or {}).load) == "function",
    "Gen1 Game module remains require-able after endGameSession")
end

-- ---- Game2:reset releases world GPU and present canvases ------------------
do
  local game2 = Game2.new()
  local canvas = love.graphics.newCanvas(4, 4)
  game2.world = World.new({})
  game2.world.mapImages = { ["MAP|d|1"] = canvas }
  game2._canvases = { love.graphics.newCanvas(8, 8) }
  game2:reset()
  check(canvas.released == true, "Game2:reset releases World mapImages")
  check(game2.world == nil, "Game2:reset clears world reference")
  check(game2._canvases == nil, "Game2:reset clears _canvases")
end

-- ---- World:release frees owned GPU caches --------------------------------
do
  local world = World.new({})
  local bake = love.graphics.newCanvas(16, 16)
  local strip = love.graphics.newCanvas(8, 64)
  local tilt = love.graphics.newCanvas(160, 144)
  world.mapImages = { ["R1|DAY|1"] = bake }
  world.scrollStrips = { ["TS|1|0,0"] = strip }
  world.tiltCanvas = tilt
  world:release()
  check(bake.released == true, "World:release frees map bake canvases")
  check(strip.released == true, "World:release frees scroll strips")
  check(tilt.released == true, "World:release frees tiltCanvas")
  eq(next(world.mapImages), nil, "World:release clears mapImages table")
end

-- ---- Renderer:init releases prior canvases before realloc ----------------
do
  local first = love.graphics.newCanvas(16, 16)
  Renderer.canvas = first
  Renderer.battleHUDCanvas = love.graphics.newCanvas(16, 16)
  Renderer.worldCanvas = love.graphics.newCanvas(16, 16)
  Renderer.uprightCanvas = love.graphics.newCanvas(16, 16)
  Renderer:init()
  check(first.released == true,
    "Renderer:init Object:release()s the previous primary canvas")
  check(Renderer.canvas ~= nil and Renderer.canvas ~= first,
    "Renderer:init allocates a fresh primary canvas")
  check(Renderer.canvas.released ~= true,
    "the new primary canvas is not released")
  local second = Renderer.canvas
  Renderer:init()
  check(second.released == true,
    "a second Renderer:init releases the canvas from the prior init")
end

-- ---- SessionLifecycle.endMountedSession (closeEditor / returnToLauncher) --
do
  Runtime.install({ emit = function() end }, { call = function() end }, { "e" })
  Assets.installLoader({
    overrideOrder = function() return {} end,
    derivedPath = function() return nil end,
  })
  LegacyCompat.reports = { some_mod = { order = {} } }

  SessionLifecycle.endMountedSession(nil)

  check(Runtime.errors == nil, "endMountedSession clears Runtime.errors")
  check(Assets.loader == nil, "endMountedSession clears Assets.loader")
  eq(next(LegacyCompat.reports), nil, "endMountedSession clears LegacyCompat.reports")
end

-- ---- releaseSession empties MapLoader via releaseAll, not flush -------------
do
  local data = {
    maps = { T1 = { id = "T1", tileset = "TS", width = 1, height = 1,
      blocks = { 0 }, borderBlock = 0, objects = {}, warps = {}, signs = {} } },
    tilesets = { TS = { id = "TS", image = "assets/generated/t.png",
      walkable = {}, blocks = { { 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0 } },
      tilesPerRow = 1 } },
  }
  MapLoader.load(data, "T1")
  check(MapLoader.cached("T1") ~= nil, "MapLoader holds a map before release")
  Assets.releaseSession()
  check(MapLoader.cached("T1") == nil,
    "releaseSession evicts MapLoader via releaseAll")
end

-- ---- Editor package.loaded discovery flush via endEditorSession -----------
do
  love.filesystem.write("tools/save-editor/App.lua", "return {}")
  love.filesystem.write("tools/save-editor/panels/NewPanel.lua", "return {}")
  package.loaded["App"] = { stale = true }
  package.loaded["NewPanel"] = { stale = true }
  package.loaded["src.core.Data"] = package.loaded["src.core.Data"]

  SessionLifecycle.endEditorSession({ version = nil, app = nil })

  check(package.loaded["App"] == nil, "endEditorSession drops flat App")
  check(package.loaded["NewPanel"] == nil,
    "endEditorSession drops a new panel without a hardcoded list")
  check(package.loaded["src.core.Data"] ~= nil,
    "endEditorSession leaves engine modules alone")
  love.filesystem.remove("tools/save-editor/App.lua")
  love.filesystem.remove("tools/save-editor/panels/NewPanel.lua")
end

-- ---- Fetch shutdown clears ready so Play-again can respawn workers ---------
do
  local Fetch = require("src.net.Fetch")
  local spawnAttempts = 0
  love.thread = love.thread or {}
  local savedNewThread = love.thread.newThread
  local savedGetChannel = love.thread.getChannel
  love.thread.getChannel = function()
    return {
      clear = function() end,
      push = function() end,
      pop = function() return nil end,
      demand = function() end,
    }
  end
  love.thread.newThread = function()
    spawnAttempts = spawnAttempts + 1
    return {
      start = function() end,
      wait = function() end,
      getError = function() return nil end,
    }
  end
  Fetch.available()
  local afterFirst = spawnAttempts
  Fetch.shutdown()
  Fetch.available()
  check(spawnAttempts > afterFirst,
    "Fetch.available retries worker spawn after shutdown (ready=nil)")
  love.thread.newThread = savedNewThread
  love.thread.getChannel = savedGetChannel
end

T.finish("launcher_session_teardown_test")
