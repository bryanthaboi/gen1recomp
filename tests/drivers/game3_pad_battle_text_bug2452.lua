local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_pad_battle_text_bug2452"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 6, 50)

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 45 }, { fade = false })
  result(ok == true, "2452_wild_battle_started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  local physical = {}
  local pad = {
    isGamepad = function() return true end,
    isGamepadDown = function(_, button) return physical[button] == true end,
    getGamepadAxis = function() return 0 end,
    getName = function() return "Xbox Controller" end,
    getGUID = function() return "030000005e040000" end,
    getID = function() return 1 end,
    isConnected = function() return true end,
  }

  local input = game.input
  local edges = 0
  local origStep = input.step
  input.step = function(self, ...)
    local r = origStep(self, ...)
    if self.pressed and self.pressed.a then edges = edges + 1 end
    return r
  end

  local win = love.window
  local origMin, origFocus = win.isMinimized, win.hasFocus
  local minimized, focused = false, true
  win.isMinimized = function() return minimized end
  win.hasFocus = function() return focused end

  local function padA()
    local before = edges
    physical.a = true
    love.gamepadpressed(pad, "a")
    U.wait(2)
    physical.a = false
    love.gamepadreleased(pad, "a")
    U.wait(12)
    return edges - before
  end

  local function atCommand()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local presses, doubles = 0, 0
  for _ = 1, 300 do
    if atCommand() then break end
    if Ui.dialogPending and Ui.dialogPending() then
      focused = (presses % 2 == 1)
      local n = padA()
      presses = presses + 1
      if n ~= 1 then doubles = doubles + 1 end
    else
      U.wait(1)
    end
  end
  focused = true
  result(atCommand(), "2452_battle_text_advanced_on_pad_a")
  result(presses > 0, "2452_pad_presses_used " .. presses)
  result(doubles == 0, "2452_one_edge_per_pad_press")
  U.still(game, DIR .. "/2452_command_menu_after_pad_a.png")

  local sawText = false
  for i = 1, 600 do
    if Ui.dialogPending and Ui.dialogPending() then sawText = true break end
    if i % 20 == 1 then U.tap(game, "a") else U.wait(1) end
  end
  if sawText then
    minimized = true
    local dropped = padA()
    result(dropped == 0, "2452_minimized_pad_press_dropped")
    minimized = false
    local landed = padA()
    result(landed == 1, "2452_restored_pad_press_lands")
  else
    result(false, "2452_no_text_after_fight")
  end

  input.step = origStep
  win.isMinimized, win.hasFocus = origMin, origFocus
  love.event.quit(fails == 0 and 0 or 1)
end
