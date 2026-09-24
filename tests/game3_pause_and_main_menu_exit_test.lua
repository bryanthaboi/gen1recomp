-- Unit tests for Game 3 pause menu (StartMenu) exit flow and Main Menu exit option.
-- Run: luajit tests/game3_pause_and_main_menu_exit_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
local ROM_TEXT = { ["sStartMenuActionTable[3]"] = "{PLAYER}" }
local function romTextKey(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end
local function romTextPlain(key, ctx) return ((ROM_TEXT[key] or key):gsub("{PLAYER}", ctx and ctx.playerName or "")) end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = romTextKey, at = function(n, i, j, ctx) return romTextPlain(romTextKey(n, i, j), ctx) end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local StartMenu = require("src.ui.game3.start_menu")
local Stack = require("src.ui.game3.stack")
local Boot = require("src.ui.game3.boot")
local Game3 = require("src.core.Game3")

-- Test 1: StartMenu EXIT flow and confirmation
do
  local returnToTitleCalled = false
  local dummyGame = {
    returnToTitle = function()
      returnToTitleCalled = true
    end,
  }
  local session = { name = "RED", game = dummyGame }

  StartMenu.resetCursor()
  StartMenu.show({ session = session, game = dummyGame })
  check(StartMenu.isOpen(), "StartMenu is open")
  check(#StartMenu.ENTRIES > 0, "StartMenu has entries")

  -- Locate EXIT entry index
  local exitIdx = nil
  for i, e in ipairs(StartMenu.ENTRIES) do
    if e.id == "exit" then
      exitIdx = i
      break
    end
  end
  check(exitIdx ~= nil, "StartMenu contains exit entry")

  -- Move to EXIT entry
  StartMenu.cursor = exitIdx
  check(not StartMenu._confirmExit, "Not in confirm exit mode yet")

  -- Press confirm on EXIT
  StartMenu.confirm()
  check(StartMenu._confirmExit, "Now in confirm exit mode")
  eq(StartMenu._confirmCursor, 2, "Default confirm cursor is 2 (NO)")

  -- Move toggles between 1 (YES) and 2 (NO)
  StartMenu.move(1)
  eq(StartMenu._confirmCursor, 1, "Cursor moved to 1 (YES)")
  StartMenu.move(1)
  eq(StartMenu._confirmCursor, 2, "Cursor moved back to 2 (NO)")

  -- B / cancel cancels confirm mode without closing menu or quitting
  StartMenu.cancel()
  check(not StartMenu._confirmExit, "Cancel exited confirm mode")
  check(StartMenu.isOpen(), "StartMenu is still open after canceling prompt")
  check(not returnToTitleCalled, "returnToTitle not called on cancel")

  -- Re-enter confirm mode and confirm NO
  StartMenu.confirm()
  check(StartMenu._confirmExit, "Re-entered confirm exit mode")
  eq(StartMenu._confirmCursor, 2, "Defaulted to NO")
  StartMenu.confirm()
  check(not StartMenu._confirmExit, "Confirming NO exited confirm mode")
  check(StartMenu.isOpen(), "StartMenu is still open after choosing NO")
  check(not returnToTitleCalled, "returnToTitle not called on NO")

  -- Re-enter confirm mode, switch to YES, and confirm
  StartMenu.confirm()
  check(StartMenu._confirmExit, "Re-entered confirm exit mode")
  StartMenu.move(1)
  eq(StartMenu._confirmCursor, 1, "Moved cursor to YES")
  StartMenu.confirm()
  check(not StartMenu._confirmExit, "Exited confirm mode on YES")
  check(not StartMenu.isOpen(), "StartMenu closed on YES")
  check(returnToTitleCalled, "returnToTitle was called on YES")
end

-- Test 2: Game3:returnToTitle cleans up and sets boot to title phase
do
  local game = Game3.new()
  game.session = { map = "FR_PALLET_TOWN", x = 5, y = 5 }
  game.phase = "field"

  game:returnToTitle()
  eq(game.phase, "boot", "Game phase returned to boot")
  check(game.session == nil, "Game session cleared")
  check(game.boot ~= nil, "Game boot state created")
  eq(game.boot.phase, Boot.PHASE.TITLE, "Boot phase is title")
  eq(Stack.depth(), 0, "Stack is cleared")
end

-- Test 3: Boot main menu items and EXIT handling
do
  local stateWithContinue = Boot.new()
  Boot.setHasContinue(stateWithContinue, true)
  local items1 = Boot.menuItems(stateWithContinue)
  eq(#items1, 4, "Main menu has 4 items when continue save exists")
  eq(items1[1], "CONTINUE", "Item 1 is CONTINUE")
  eq(items1[2], "NEW GAME", "Item 2 is NEW GAME")
  eq(items1[3], "MYSTERY GIFT", "Item 3 is MYSTERY GIFT")
  eq(items1[4], "EXIT", "Item 4 is EXIT")

  local stateNoContinue = Boot.new()
  Boot.setHasContinue(stateNoContinue, false)
  local items2 = Boot.menuItems(stateNoContinue)
  eq(#items2, 2, "Main menu has 2 items when no continue save exists")
  eq(items2[1], "NEW GAME", "Item 1 is NEW GAME")
  eq(items2[2], "EXIT", "Item 2 is EXIT")
end

-- Test 4: Boot update choosing EXIT returns { action = "exit" }
do
  local state = Boot.new()
  Boot.setHasContinue(state, true)
  state.phase = Boot.PHASE.MENU
  state.menuIndex = 4 -- EXIT
  state.fadeT, state.fadeTarget = 0, 0

  local pressedKey = nil
  local inputStub = {
    wasPressed = function(self, key)
      return key == pressedKey
    end,
  }

  pressedKey = "a"
  local act = Boot.update(state, inputStub, 1/60)
  eq(act, nil, "First frame initiates fade")
  eq(state.fadeThen, "exit", "Fade action set to exit")

  -- Advance fade until finished
  while state.fadeThen do
    act = Boot.update(state, inputStub, 1/60)
  end
  check(type(act) == "table" and act.action == "exit", "Selecting EXIT returns { action = 'exit' }")
end

-- Test 5: Game3:_handleBootAction({ action = "exit" }) triggers returnToLauncher or onExit
do
  local launcherCalled = false
  local exitCalled = false

  local game = Game3.new()
  game.returnToLauncher = function()
    launcherCalled = true
  end
  game.onExit = function()
    exitCalled = true
  end

  game:_handleBootAction({ action = "exit" })
  check(launcherCalled, "returnToLauncher called when available")
  check(not exitCalled, "returnToLauncher prioritized over onExit")

  launcherCalled = false
  game.returnToLauncher = nil
  game:_handleBootAction({ action = "exit" })
  check(exitCalled, "onExit called when returnToLauncher is nil")
end

-- Test 6: Boot.draw handles main menu with and without continue without errors
do
  local stateWith = Boot.new()
  Boot.setHasContinue(stateWith, true)
  stateWith.phase = Boot.PHASE.MENU
  stateWith.continueInfo = {
    name = "ASH",
    hours = 12,
    minutes = 34,
    hasDex = true,
    dexCount = 50,
    badges = 4,
    gender = 0,
  }
  local ListMenu = require("src.ui.game3.list_menu")
  local realArrow = ListMenu.drawArrow
  local arrows = {}
  ListMenu.drawArrow = function(dir) arrows[#arrows + 1] = dir end
  for idx = 1, 4 do
    stateWith.menuIndex = idx
    stateWith.menuScroll = idx == 4 and 4 or nil
    arrows = {}
    local ok, err = pcall(Boot.draw, stateWith)
    check(ok, "drawMainMenu with continue at index " .. idx .. " runs without error: " .. tostring(err))
    if idx == 4 then
      eq(#arrows, 0, "no down arrow once EXIT is scrolled into view")
    else
      eq(arrows[1], "down", "down arrow flags EXIT below the fold at index " .. idx)
    end
  end
  ListMenu.drawArrow = realArrow

  local stateWithout = Boot.new()
  Boot.setHasContinue(stateWithout, false)
  stateWithout.phase = Boot.PHASE.MENU
  for idx = 1, 2 do
    stateWithout.menuIndex = idx
    local ok, err = pcall(Boot.draw, stateWithout)
    check(ok, "drawMainMenu without continue at index " .. idx .. " runs without error: " .. tostring(err))
  end
end

-- Test 7: Hud.isMenuOpen reflects pause menu and other modal menus
do
  local Hud = require("src.ui.game3.hud")
  StartMenu.close()
  check(not Hud.isMenuOpen(), "isMenuOpen is false when no menu open")

  StartMenu.show({ session = {}, game = {} })
  check(Hud.isMenuOpen(), "isMenuOpen is true when StartMenu open")
  check(Hud.busy(), "Hud.busy is true when StartMenu open")

  StartMenu.close()
  check(not Hud.isMenuOpen(), "isMenuOpen is false after closing StartMenu")
end

-- Test 8: Runtime.update pauses field and pumpRtc while pause menu is open
do
  local Runtime = require("src.core.game3.runtime")
  local Field = require("src.core.game3.field")
  local session = {
    map = "FR_PALLET_TOWN",
    x = 5, y = 5,
    playtime = { hours = 1, minutes = 20, seconds = 30, vblanks = 0 },
  }
  local game = { session = session, save = {} }
  Runtime.start(nil, game, session, { reason = "test", alreadyOnMap = true })

  local fieldUpdateCount = 0
  local origFieldUpdate = Field.update
  Field.update = function(dt)
    fieldUpdateCount = fieldUpdateCount + 1
  end

  -- 1. Normal field tick (unpaused)
  Runtime.update(1 / 60)
  eq(fieldUpdateCount, 1, "Field.update called when unpaused")

  -- 2. Open pause menu (StartMenu)
  StartMenu.show({ session = session, game = game })
  local prevSeconds = session.playtime.seconds
  local prevAcc = Runtime._playTimeAcc or 0

  -- Tick many frames while pause menu is open (simulating fast-forward logic ticks)
  for _ = 1, 120 do
    Runtime.update(1 / 60)
  end

  eq(fieldUpdateCount, 1, "Field.update was NOT called while pause menu open")
  eq(session.playtime.seconds, prevSeconds, "Playtime seconds did NOT tick while pause menu open")
  eq(Runtime._playTimeAcc, prevAcc, "Playtime accumulator did NOT advance while pause menu open")

  -- 3. Close pause menu
  StartMenu.close()
  Runtime.update(1 / 60)
  eq(fieldUpdateCount, 2, "Field.update resumed after closing pause menu")

  Field.update = origFieldUpdate
  Runtime.stop(nil, game)
end

T.finish("game3_pause_and_main_menu_exit_test")
