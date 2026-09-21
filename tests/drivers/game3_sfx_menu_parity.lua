local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_sfx_menu_parity"

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

  local Audio = require("src.core.game3.audio")
  local StartMenu = require("src.ui.game3.start_menu")
  local SaveMenu = require("src.ui.game3.save_menu")

  local log = {}
  local realPlaySe = Audio.playSe
  Audio.playSe = function(id, opts)
    local SE = require("src.core.game3.se_ids")
    log[#log + 1] = SE.resolve(id)
    return realPlaySe(id, opts)
  end

  local function since(n)
    local out = {}
    for i = n + 1, #log do out[#out + 1] = tostring(log[i]) end
    return table.concat(out, ",")
  end
  local function has_exit(n)
    for i = n + 1, #log do if log[i] == 9 then return true end end
    return false
  end

  -- pokefirered/src/field_control_avatar.c:288
  local mark = #log
  U.tap(game, "start")
  U.wait(20)
  result(StartMenu.isOpen(), "start menu opened")
  result(log[mark + 1] == 6, "start menu open -> SE_WIN_OPEN [" .. since(mark) .. "]")
  U.shot(game, DIR .. "/2306_01_start_menu.png")

  -- pokefirered/src/start_menu.c:430
  local saveIdx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "save" then saveIdx = i break end
  end
  result(saveIdx ~= nil, "SAVE entry present")
  if saveIdx then
    for _ = 1, 20 do
      if StartMenu.cursor == saveIdx then break end
      U.tap(game, "down")
      U.wait(4)
    end
    result(StartMenu.cursor == saveIdx, "cursor on SAVE")
  end
  mark = #log
  U.tap(game, "a")
  U.wait(30)
  result(SaveMenu.isOpen(), "save dialog opened")
  result(since(mark) == "5", "save dialog open -> SE_SELECT once [" .. since(mark) .. "]")
  U.shot(game, DIR .. "/2306_02_save_dialog.png")

  -- pokefirered/src/menu.c:381
  mark = #log
  U.tap(game, "b")
  U.wait(30)
  result(not SaveMenu.isOpen(), "save dialog cancelled")
  result(since(mark) == "", "save dialog B press -> silence [" .. since(mark) .. "]")

  -- pokefirered/src/start_menu.c:1005
  mark = #log
  U.tap(game, "b")
  U.wait(30)
  result(not StartMenu.isOpen(), "start menu closed")
  result(since(mark) == "5", "start menu close -> SE_SELECT [" .. since(mark) .. "]")
  U.shot(game, DIR .. "/2306_03_overworld_after_close.png")

  -- pokefirered/src/start_menu.c:583
  U.tap(game, "start")
  U.wait(20)
  if saveIdx then
    for _ = 1, 20 do
      if StartMenu.cursor == saveIdx then break end
      U.tap(game, "down")
      U.wait(4)
    end
  end
  U.tap(game, "a")
  U.wait(30)
  result(SaveMenu.isOpen(), "save dialog reopened")
  SaveMenu._phase = "saved"
  mark = #log
  U.tap(game, "a")
  U.wait(30)
  result(not SaveMenu.isOpen() and not StartMenu.isOpen(), "saved message dismissed to the field")
  result(since(mark) == "", "saved message dismissal -> silence [" .. since(mark) .. "]")

  result(not has_exit(0), "no menu path played SE_EXIT")

  local Player = require("src.core.game3.m4a_player")
  local Mix = require("src.core.game3.m4a_mix")
  local secs = -1
  if Audio._pack then
    local slot = { voices = {} }
    if Player.start(Audio._pack, Audio._cache, slot, 319, { forceSeq = true }) then
      local L = Player.bakeSlot(slot, { raw = true, maxSec = 6.0, stopOnGoto = false })
      secs = #L / Mix.SAMPLE_RATE
    end
  end
  result(secs >= 4.5, string.format("MUS_CAUGHT_INTRO bakes %.3fs (>= 4.5)", secs))

  Audio.playSe = realPlaySe
  U.wait(10)
  love.event.quit(fails == 0 and 0 or 1)
end
