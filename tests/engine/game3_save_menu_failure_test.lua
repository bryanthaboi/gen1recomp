-- SaveMenu must not report "<name> saved the game." when the write failed.
--
-- Regression: do_save() (src/ui/game3/save_menu.lua) discarded both pcall
-- results and set SaveMenu._phase = "saved" unconditionally, so a refused or
-- failed save still rendered the success message and closed the menu.  The
-- engine's saveGame returns explicit false for a refused write, nil for a
-- deliberate no-op (no session / quest-log phase), and true only for a
-- confirmed write -- so only a truthy return may report success.
--
-- The menu's boundaries (runtime singleton, bridge, audio) are stubbed so the
-- suite exercises the real confirm -> overwrite -> do_save path.
--   luajit tests/engine/game3_save_menu_failure_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local RuntimeStub = { _game = nil, _mod = nil }
local sidecarRaise = nil

package.preload["src.core.game3.runtime"] = function() return RuntimeStub end
package.preload["src.core.game3.bridge"] = function()
  return {
    persistSessionOnly = function()
      if sidecarRaise then error(sidecarRaise) end
    end,
  }
end
package.preload["src.core.game3.audio"] = function() return { playSe = function() end } end

local FrlgFont = require("src.ui.game3.frlg_font")
FrlgFont.draw = function() end
FrlgFont.measure = function(text) return #tostring(text) * 6 end

local SaveMenu = require("src.ui.game3.save_menu")

-- Drive YES (confirm) -> YES (overwrite) -> do_save, like the input path does.
local function run_save(game)
  RuntimeStub._game, RuntimeStub._mod = game, {}
  sidecarRaise = nil
  SaveMenu.show({ session = { name = "RED" }, game = game })
  SaveMenu.cursor = 1
  SaveMenu.confirm()
  SaveMenu.confirm()
  return SaveMenu._phase
end

-- A refused write (Game3:saveGame returns false) must not report success.
local phase = run_save({ saveGame = function() return false end })
check(phase ~= "saved", "a refused write does not report success (phase=" .. tostring(phase) .. ")")
eq(phase, "save_failed", "a refused write enters the failure phase")

-- A throwing write must not report success.
phase = run_save({ saveGame = function() error("simulated disk failure") end })
check(phase ~= "saved", "a throwing write does not report success (phase=" .. tostring(phase) .. ")")
eq(phase, "save_failed", "a throwing write enters the failure phase")

-- No saveGame at all must not report success.
phase = run_save({})
check(phase ~= "saved", "an absent saveGame does not report success (phase=" .. tostring(phase) .. ")")

-- A throwing sidecar persist must not report success, even if the write works.
RuntimeStub._game, RuntimeStub._mod = { saveGame = function() return true end }, {}
sidecarRaise = "simulated sidecar failure"
SaveMenu.show({ session = { name = "RED" }, game = RuntimeStub._game })
SaveMenu.cursor = 1
SaveMenu.confirm()
SaveMenu.confirm()
check(SaveMenu._phase ~= "saved",
  "a throwing sidecar persist does not report success (phase=" .. tostring(SaveMenu._phase) .. ")")

-- A confirmed write still reports success (regression guard).
eq(run_save({ saveGame = function() return true end }), "saved",
  "a confirmed write still reports 'saved'")

-- The failure state is readable and dismissable rather than stuck.
RuntimeStub._game, RuntimeStub._mod = { saveGame = function() return false end }, {}
sidecarRaise = nil
SaveMenu.show({ session = { name = "RED" }, game = RuntimeStub._game })
SaveMenu.cursor = 1
SaveMenu.confirm()
SaveMenu.confirm()
eq(SaveMenu._phase, "save_failed", "the dialog stays up showing the failure")
check(SaveMenu._error ~= nil, "the failure reason is recorded for the log")
SaveMenu.confirm()
eq(SaveMenu.open, false, "confirm from the failure state closes the dialog")

T.finish("game3_save_menu_failure_test")
