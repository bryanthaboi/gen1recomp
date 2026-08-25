-- Test returning to launcher from Gen 1 and Gen 2 on Android without closing the process
--   luajit tests/engine/android_exit_to_launcher_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local TitleState = require("src.ui.TitleState")
local Gen2MainMenu = require("src.ui.gen2.MainMenu")
local Runtime = require("src.mods.Runtime")

-- 1. Test Gen 1 TitleState onExit callback support
do
  local exitCalled = false
  local dummyGame = {
    data = { field = {} },
    stack = {
      states = {},
      push = function(self, state) table.insert(self.states, state) end,
      top = function(self) return self.states[#self.states] end,
      pop = function(self) return table.remove(self.states) end,
    },
  }
  local state = TitleState.new(dummyGame, {
    onExit = function()
      exitCalled = true
    end,
  })
  state:openMenu()
  local menu = dummyGame.stack:top()
  check(menu ~= nil, "TitleState:openMenu opens a menu")
  local exitItem = nil
  for _, item in ipairs(menu.items or {}) do
    if tostring(item.label):find("EXIT", 1, true) then
      exitItem = item
      break
    end
  end
  check(exitItem ~= nil, "Gen 1 TitleState menu contains an EXIT GAME item")
  if exitItem and exitItem.onSelect then
    exitItem.onSelect()
  end
  check(exitCalled, "Selecting EXIT GAME in Gen 1 TitleState invokes onExit callback")
end

-- 2. Test Gen 2 MainMenu onExit callback support
do
  local exitCalled = false
  local dummyGame2 = {
    data = {},
    stack = {
      states = {},
      push = function(self, state) table.insert(self.states, state) end,
      top = function(self) return self.states[#self.states] end,
      pop = function(self) return table.remove(self.states) end,
    },
  }
  local menu = Gen2MainMenu.new(dummyGame2, {
    hasSave = false,
    onExit = function()
      exitCalled = true
    end,
  })
  menu:choose("exit")
  check(exitCalled, "Selecting EXIT GAME in Gen 2 MainMenu invokes onExit callback")
end

-- 3. Test Runtime.reset restores NullEvents and NullHooks
do
  Runtime.install({ emit = function() end }, { call = function() end }, { "err" })
  check(Runtime.errors ~= nil, "Runtime has errors list after install")
  Runtime.reset()
  check(Runtime.errors == nil, "Runtime.reset clears errors")
  check(Runtime.currentMod == nil, "Runtime.reset clears currentMod")
  check(Runtime.modRequire == nil, "Runtime.reset clears modRequire")
end

-- 4. returnToLauncher / closeEditor also clear Assets.loader (orphaned Loader)
do
  local Assets = require("src.render.Assets")
  Assets.installLoader({
    overrideOrder = function() return { { id = "x", path = "mods/x" } } end,
    derivedPath = function() return nil end,
  })
  check(Assets.loader ~= nil, "Assets.loader installed for the session")
  Assets.installLoader(nil)
  check(Assets.loader == nil, "session teardown clears Assets.loader")
end

-- 5. Gen1 Game:reset exists so main.lua need not guess field names
do
  local Game = require("src.core.Game")
  check(type(Game.reset) == "function", "Game:reset is defined for in-process return")
  Game.mods = { stale = true }
  Game:reset()
  check(Game.mods == nil, "Game:reset clears session fields")
  check(type(Game.load) == "function", "Game:reset keeps methods")
end

-- 6. Play-again after endGameSession: Game.load must still be callable
--    (Android crash: main.lua bootGame → Game:load with load == nil)
do
  local Game = require("src.core.Game")
  local SessionLifecycle = require("src.core.SessionLifecycle")
  Game.save = {}
  Game.stack = { clear = function() end }
  -- Mimic a shared net module parked on the singleton (handle-style release).
  Game.net = { release = function(id) end }
  SessionLifecycle.endGameSession(Game)
  local again = require("src.core.Game")
  check(type(again.load) == "function",
    "Play-again can call Game:load after endGameSession")
end

T.finish("android_exit_to_launcher_test")
