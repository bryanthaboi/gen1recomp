local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_mods_restart_bug2691"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " game3_mods_restart_bug2691 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    print("[driver] " .. label .. " error: " .. tostring(err))
    failures = failures + 1
  end
  return ok
end

local PROBE = "bug2691_probe"

local function titleOptions(game)
  local SaveData = require("src.core.SaveData")
  local Rows = require("src.ui.game3.option_rows")
  local ModManager = require("src.ui.game3.mod_manager")
  check(game.save == nil, "title: no save table before field entry")
  local ctx = { game = game, session = nil, options = game.options }
  local row
  for _, r in ipairs(Rows.build(ctx)) do
    if r.id == "mods" then row = r end
  end
  if not check(row ~= nil, "title: OPTION menu has the MODS row") then return end
  row.activate(ctx)
  U.wait(5)
  if not check(ModManager.isOpen(), "title: MODS row opens the manager") then return end
  local m = ModManager._mgr
  check(m:optionsTable() == game.options, "title: manager edits the live Game3.options")
  local scope = m:enableScope()
  m:commitToggle({ [PROBE] = false })
  check(SaveData.modEnabled(game.options, PROBE, scope) == false,
    "title: toggle mirrored into Game3.options")
  m:persistOptions()
  local disk = SaveData.loadOptions()
  check(disk and SaveData.modEnabled(disk, PROBE, scope) == false,
    "title: toggle survives into options.lua")
  ModManager.close()
  U.wait(5)
  check(not ModManager.isOpen(), "title: manager closed")
end

local function fieldRestart(game)
  local ModManager = require("src.ui.game3.mod_manager")
  local Game3 = require("src.core.Game3")
  check(game.phase == "field", "field: reached the overworld")
  check(game.restartWithMods == Game3.restartWithMods, "field: Game3 owns restartWithMods")
  ModManager.show({ game = game, session = game.session })
  U.wait(20)
  if not check(ModManager.isOpen(), "field: START > MODS manager open") then return end
  U.still(game, DIR .. "/mod_manager_open.png")
  local restarts = 0
  local real = package.loaded["src.core.HostShell"]
  package.loaded["src.core.HostShell"] = { restart = function() restarts = restarts + 1 end }
  local titled = false
  local rtt = game.returnToTitle
  game.returnToTitle = function(...) titled = true return rtt(...) end
  ModManager._mgr:restartGame()
  game.returnToTitle = nil
  package.loaded["src.core.HostShell"] = real
  check(restarts == 1, "APPLY & RESTART reaches HostShell.restart")
  check(not titled, "APPLY & RESTART no longer soft-returns to the title")
  check(not ModManager.isOpen(), "APPLY & RESTART closes the manager")
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  local Runtime = require("src.mods.Runtime")
  local safeMode = Runtime.safeMode
  Runtime.safeMode = false
  try("title", function() titleOptions(game) end)
  Runtime.safeMode = safeMode
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "RED" }) end)
  for _ = 1, 600 do
    if game.phase == "field" then break end
    U.wait(1)
  end
  U.wait(60)
  try("field", function() fieldRestart(game) end)
  return finish()
end
