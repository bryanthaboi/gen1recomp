-- core.update / core.quit_to_launcher through the public mod API: a
-- platform-launcher integration can pause the simulation and veto the
-- return-to-launcher decision from a mod, with no main.lua patch.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local PlatformHooks = require("src.core.PlatformHooks")

local FIXTURE = {
  ["mods/fix_platform_bridge/manifest.json"] = [[{
    "id": "fix_platform_bridge",
    "name": "Fixture Platform Bridge",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/fix_platform_bridge/main.lua"] = [[
    local mod = ...
    local paused = false
    local extraPolls = 0
    mod.hooks:wrap("core.update", function(nextFn, game, dt)
      extraPolls = extraPolls + 1
      if not paused then nextFn(game, dt) end
    end)
    mod.hooks:wrap("core.quit_to_launcher", function(nextFn)
      if os.getenv("FIXTURE_VETO_QUIT") == "1" then return false end
      return nextFn()
    end)
    -- test-only knobs, read back through mod.storage-free globals since
    -- this fixture never leaves the process
    _G.__fixturePlatformBridge = {
      setPaused = function(v) paused = v end,
      extraPolls = function() return extraPolls end,
    }
  ]],
}

-- core.update: a subscriber can pause (skip vanilla) and still run every frame
do
  local run = T.sdk.loadMods({ "mods/fix_platform_bridge" },
    { fs = T.sdk.memfs(FIXTURE) })
  T.eq(#run.errors, 0,
    "the fixture mod loads clean (" .. tostring(run.errors[1]) .. ")")

  local calls = 0
  local fakeGame = { update = function(self, dt) calls = calls + 1 end }

  _G.__fixturePlatformBridge.setPaused(false)
  PlatformHooks.update(fakeGame, 1 / 60)
  T.eq(calls, 1, "unpaused: vanilla Game:update runs")
  T.eq(_G.__fixturePlatformBridge.extraPolls(), 1,
    "the subscriber's wrapper runs every frame")

  _G.__fixturePlatformBridge.setPaused(true)
  PlatformHooks.update(fakeGame, 1 / 60)
  T.eq(calls, 1, "paused: vanilla Game:update is skipped")
  T.eq(_G.__fixturePlatformBridge.extraPolls(), 2,
    "the subscriber keeps polling every frame while paused")

  run.release()
  _G.__fixturePlatformBridge = nil
end

-- core.quit_to_launcher: a subscriber can veto without the vanilla
-- condition ever running, or pass it through unchanged
do
  local run = T.sdk.loadMods({ "mods/fix_platform_bridge" },
    { fs = T.sdk.memfs(FIXTURE) })
  T.eq(#run.errors, 0,
    "the fixture mod loads clean (" .. tostring(run.errors[1]) .. ")")

  local realGetenv = os.getenv
  os.getenv = function(name)
    if name == "FIXTURE_VETO_QUIT" then return "1" end
    return realGetenv(name)
  end
  local vanillaCalls = 0
  local vetoed = PlatformHooks.quitToLauncher(function()
    vanillaCalls = vanillaCalls + 1
    return true
  end)
  T.eq(vetoed, false, "a subscriber can veto the return-to-launcher decision")
  T.eq(vanillaCalls, 0, "a veto never evaluates the vanilla condition")
  os.getenv = realGetenv

  local passed = PlatformHooks.quitToLauncher(function() return true end)
  T.eq(passed, true, "with no veto, the vanilla decision passes through unchanged")

  run.release()
end

T.finish("platform_lifecycle_hooks")
