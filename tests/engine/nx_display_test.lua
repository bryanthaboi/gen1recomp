-- NX handheld/dock display sync (portable 720p / docked 1080p).
-- Self-contained: luajit tests/engine/nx_display_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local savedLove = _G.love

package.loaded["src.core.Platform"] = nil
package.loaded["src.core.NxDisplay"] = nil

local NxDisplay = require("src.core.NxDisplay")

local function withWindow(state, fn)
  local setCalls = {}
  _G.love = {
    system = {
      getOS = function() return state.os or "NX" end,
    },
    window = {
      getMode = function()
        return state.w, state.h, {
          fullscreen = state.fullscreen,
          resizable = state.resizable,
          vsync = 1,
        }
      end,
      setMode = function(w, h, flags)
        setCalls[#setCalls + 1] = { w = w, h = h, flags = flags }
        state.w, state.h = w, h
        state.fullscreen = flags and flags.fullscreen
        state.resizable = flags and flags.resizable
      end,
    },
  }
  package.loaded["src.core.Platform"] = nil
  require("src.core.Platform")._resetForTests()
  NxDisplay._resetForTests()
  package.loaded["src.core.NxDisplay"] = nil
  NxDisplay = require("src.core.NxDisplay")
  local ok, err = pcall(fn, setCalls)
  _G.love = savedLove
  package.loaded["src.core.Platform"] = nil
  package.loaded["src.core.NxDisplay"] = nil
  NxDisplay = require("src.core.NxDisplay")
  NxDisplay._resetForTests()
  if not ok then error(err) end
end

-- Size mapping
do
  local w, h = NxDisplay.desiredSize(0)
  eq(w, 1280, "handheld mode → 1280 wide")
  eq(h, 720, "handheld mode → 720 tall")
  w, h = NxDisplay.desiredSize(1)
  eq(w, 1920, "console/docked mode → 1920 wide")
  eq(h, 1080, "console/docked mode → 1080 tall")
  w, h = NxDisplay.desiredSize(nil)
  -- With no test hook and no real Switch FFI, operationMode is nil → no size.
  check(w == nil and h == nil, "nil/unknown mode returns no size (do not force)")
  w, h = NxDisplay.desiredSize(99)
  check(w == nil and h == nil, "unknown mode returns no size")
end

-- Non-NX: sync is a no-op
withWindow({ os = "Linux", w = 1024, h = 768, fullscreen = false, resizable = true }, function(setCalls)
  NxDisplay._forceNXForTests = false
  NxDisplay._operationModeForTests = 1
  eq(NxDisplay.sync(), false, "sync returns false off NX")
  eq(#setCalls, 0, "sync never calls setMode off NX")
end)

-- NX handheld already correct: no setMode (even if flags look "wrong")
withWindow({
  os = "NX", w = 1280, h = 720, fullscreen = true, resizable = false,
}, function(setCalls)
  NxDisplay._forceNXForTests = true
  NxDisplay._operationModeForTests = 0
  eq(NxDisplay.sync(), false, "sync skips setMode when size already matches")
  eq(#setCalls, 0, "no setMode when only flags differ (avoids flicker)")
end)

-- NX docked boot from 720p hint → 1080p
withWindow({
  os = "NX", w = 1280, h = 720, fullscreen = true, resizable = false,
}, function(setCalls)
  NxDisplay._forceNXForTests = true
  NxDisplay._operationModeForTests = 1
  eq(NxDisplay.sync(), true, "sync upgrades docked boot to 1080p")
  eq(#setCalls, 1, "one setMode on docked boot")
  eq(setCalls[1].w, 1920, "docked setMode width")
  eq(setCalls[1].h, 1080, "docked setMode height")
  eq(setCalls[1].flags.fullscreen, false, "docked setMode clears exclusive fullscreen")
  eq(setCalls[1].flags.resizable, true, "docked setMode enables resizable for SDL backup")
  -- Second sync must not setMode again (flicker guard)
  eq(NxDisplay.sync(), false, "second sync is no-op after size matches")
  eq(#setCalls, 1, "still only one setMode after repeated sync")
end)

-- NX undock: 1080p → 720p
withWindow({
  os = "NX", w = 1920, h = 1080, fullscreen = false, resizable = true,
}, function(setCalls)
  NxDisplay._forceNXForTests = true
  NxDisplay._operationModeForTests = 0
  eq(NxDisplay.sync(), true, "sync shrinks to handheld after undock")
  eq(setCalls[1].w, 1280, "undock setMode width")
  eq(setCalls[1].h, 720, "undock setMode height")
end)

-- Unknown mode: do not force a size (would fight SDL and flicker)
withWindow({
  os = "NX", w = 1920, h = 1080, fullscreen = false, resizable = true,
}, function(setCalls)
  NxDisplay._forceNXForTests = true
  NxDisplay._operationModeForTests = nil
  -- Force operationMode() to return nil by using a sentinel the API treats
  -- as "use live" then stubbing via desiredSize path — set a mode that
  -- desiredSize rejects by clearing the hook after setting force NX, and
  -- monkey-patching operationMode through the test hook to a non-value:
  -- _operationModeForTests = false is not nil, so use a dedicated unknown.
  -- Actually nil hook means live FFI; in tests FFI has no symbol → nil mode.
  eq(NxDisplay.sync(), false, "sync no-ops when mode unknown")
  eq(#setCalls, 0, "unknown mode never calls setMode")
end)

T.finish("nx_display")
