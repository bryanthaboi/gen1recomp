-- The self-updater's host gate: which builds may hand off to a downloaded
-- payload.  A packaged build updates in place -- fused (AppImage, Flatpak's
-- game.love) or unpacked (every PortMaster-style port, which runs
-- `love <dir>` and so reports isFused() false).  A dev / source checkout must
-- not, and an unknown host must fail closed.
--
-- This gate is the difference between the PortMaster SBC port applying an
-- update and silently ignoring it after the launcher already said "Restart to
-- update", so the unpacked case is pinned here.
--   luajit tests/engine/update_boot_host_gate.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Boot = require("src.update.Boot")
local love_stub = require("tests.love_stub")

local VERSION_KEY = "src.core.Version"

-- A packaged build stamps a real engine (X.Y.Z); a working tree keeps the
-- "0.0.0-dev" placeholder, which is what Version.isDev() reports.
local function withVersion(isDev, fn)
  local saved = package.loaded[VERSION_KEY]
  package.loaded[VERSION_KEY] = { isDev = function() return isDev end }
  local ok, err = pcall(fn)
  package.loaded[VERSION_KEY] = saved
  if not ok then error(err, 0) end
end

-- Stand in for the running LÖVE process: nil (no love at all) or a filesystem
-- that reports the given fused state.
local function withLove(fs, fn)
  local saved = _G.love
  _G.love = fs and { filesystem = fs } or nil
  local ok, err = pcall(fn)
  _G.love = saved
  if not ok then error(err, 0) end
end

local function fsWith(isFused)
  if isFused == nil then return {} end
  return { isFused = function() return isFused end }
end

-- no love at all (headless host): never update
withLove(nil, function()
  eq(Boot.canUpdateInPlace(), false, "no love.filesystem -> no in-place update")
end)

-- fused wins outright: a binary carrying its own game archive is a packaged
-- build whatever the engine string says
withLove(fsWith(true), function()
  withVersion(false, function()
    eq(Boot.canUpdateInPlace(), true, "fused packaged build updates in place")
  end)
  withVersion(true, function()
    eq(Boot.canUpdateInPlace(), true, "fused build updates even with a dev engine string")
  end)
end)

-- the fix: an unpacked packaged build (PortMaster SBC / RG34XXSP) is not fused,
-- but it carries a released engine and its source on disk is never rewritten,
-- so a downloaded payload can be mounted over it
withLove(fsWith(false), function()
  withVersion(false, function()
    eq(Boot.canUpdateInPlace(), true,
      "unpacked released build (love <dir>) updates in place")
  end)
  withVersion(true, function()
    eq(Boot.canUpdateInPlace(), false,
      "unpacked dev checkout (engine 0.0.0-dev) never updates")
  end)
end)

-- a filesystem that cannot answer the fused question at all still updates when
-- the engine proves this is a packaged build
withLove(fsWith(nil), function()
  withVersion(false, function()
    eq(Boot.canUpdateInPlace(), true,
      "released build without isFused() still updates")
  end)
end)

-- fail closed: an unreadable / malformed Version must not open the gate
withLove(fsWith(false), function()
  local saved = package.loaded[VERSION_KEY]
  package.loaded[VERSION_KEY] = "not a module"
  eq(Boot.canUpdateInPlace(), false, "non-table Version -> no in-place update")
  package.loaded[VERSION_KEY] = { engine = "1.4.2" }
  eq(Boot.canUpdateInPlace(), false, "Version without isDev -> no in-place update")
  package.loaded[VERSION_KEY] = nil
  eq(Boot.canUpdateInPlace(), false, "unloadable Version -> no in-place update")
  package.loaded[VERSION_KEY] = saved
end)

-- Boot.run is the first line of love.load: in a dev checkout it must return
-- false immediately, leaving the bundled game to boot as normal
withLove(love_stub.filesystem, function()
  withVersion(true, function()
    eq(Boot.run(nil), false, "Boot.run is a no-op in a dev checkout")
  end)
end)

T.finish("update_boot_host_gate")
