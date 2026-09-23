local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

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
  local Chrome = require("src.ui.game3.chrome")
  local SaveMenu = require("src.ui.game3.save_menu")

  local seen = {}
  local function spy(name, fn, argOffset)
    Chrome[name] = function(...)
      local a = { ... }
      seen[#seen + 1] = { kind = name, tx = a[1 + argOffset], ty = a[2 + argOffset] }
      return fn(...)
    end
  end
  spy("fixedStdFrame", Chrome.fixedStdFrame, 0)
  spy("stdFrame", Chrome.stdFrame, 0)
  spy("dialogueFrame", Chrome.dialogueFrame, 0)
  spy("userFrame", Chrome.userFrame, 1)

  SaveMenu.show({ session = Runtime.getSession(), game = game })
  U.wait(20)
  seen = {}
  U.wait(2)
  U.shot(game, DIR .. "/save_frames_01_default_frame.png")

  local function frameOf(tx, ty)
    for _, c in ipairs(seen) do
      if c.tx == tx and c.ty == ty then return c.kind end
    end
    return "none"
  end

  result(frameOf(1, 1) == "fixedStdFrame",
    "save stats window drew the fixed std frame (" .. tostring(frameOf(1, 1)) .. ")")
  result(frameOf(21, 9) == "stdFrame",
    "YES/NO drew the user-selected std frame (" .. tostring(frameOf(21, 9)) .. ")")
  local sawDialogue = false
  for _, c in ipairs(seen) do
    if c.kind == "dialogueFrame" then sawDialogue = true end
  end
  result(sawDialogue, "message box drew the dialogue frame")

  Chrome.setFrameType(5)
  U.wait(4)
  seen = {}
  U.wait(2)
  U.shot(game, DIR .. "/save_frames_02_user_frame_5.png")
  result(frameOf(1, 1) == "fixedStdFrame",
    "save stats window ignores the user frame setting (" .. tostring(frameOf(1, 1)) .. ")")
  result(frameOf(21, 9) == "stdFrame",
    "YES/NO still routes through the user frame (" .. tostring(frameOf(21, 9)) .. ")")

  Chrome.setFrameType(0)
  U.wait(4)
  SaveMenu.cancel()
  U.wait(20)

  local RomText = require("src.core.game3.rom_text")
  local StartMenu = require("src.ui.game3.start_menu")
  StartMenu.show({ session = Runtime.getSession(), game = game })
  U.wait(10)
  U.shot(game, DIR .. "/start_menu_rom_labels.png")
  local labels = {}
  for _, e in ipairs(StartMenu.ENTRIES) do labels[e.id] = e.label end
  result(labels.bag == RomText.at("sStartMenuActionTable", 2) and labels.trainer == Runtime.getSession().name,
    "start menu labels come from sStartMenuActionTable (" .. tostring(labels.bag) .. ", " .. tostring(labels.trainer) .. ")")
  StartMenu.close(true)
  U.wait(10)

  local OptionMenu = require("src.ui.game3.option_menu")
  OptionMenu.show({ session = Runtime.getSession(), game = game })
  U.wait(10)
  local function top() return OptionMenu._pages[#OptionMenu._pages] end
  local function cursor_to(id)
    for _ = 1, 20 do
      local p = top()
      local row = p.rows[p.index]
      if row and row.id == id then return true end
      U.tap(game, "down")
      U.wait(4)
    end
    return false
  end
  result(cursor_to("buttonMode"), "the cursor reaches the BUTTON MODE row")
  local p = top()
  local buttonRow = p.rows[p.index]
  local onScreen = p.index > p.scroll and p.index <= p.scroll + 7
  local buttonValue = buttonRow and buttonRow.value and buttonRow.value(OptionMenu._ctx)
  result(onScreen and buttonRow.label == RomText.at("sOptionMenuItemsNames", 4)
    and buttonValue == RomText.at("sButtonTypeOptions", 0),
    "the BUTTON MODE row on screen reads sOptionMenuItemsNames / sButtonTypeOptions (" .. tostring(buttonRow and buttonRow.label)
      .. " " .. tostring(buttonValue) .. ")")
  U.shot(game, DIR .. "/option_menu_button_mode_row.png")

  result(cursor_to("group.battle"), "the cursor reaches BATTLE OPTIONS")
  U.tap(game, "a")
  U.wait(10)
  local battle = top()
  local r1, r2 = battle.rows[1], battle.rows[2]
  result(#OptionMenu._pages == 2 and r1 and r1.label == RomText.at("sOptionMenuItemsNames", 1)
      and r2 and r2.label == RomText.at("sOptionMenuItemsNames", 2)
      and r1.value(OptionMenu._ctx) == RomText.at("sBattleSceneOptions", 0),
    "BATTLE OPTIONS lists the ROM BATTLE SCENE / BATTLE STYLE rows (" .. tostring(r1 and r1.label)
      .. ", " .. tostring(r2 and r2.label) .. ")")
  U.shot(game, DIR .. "/option_menu_rom_labels.png")
  U.tap(game, "b")
  U.wait(6)
  OptionMenu.close()
  U.wait(10)

  love.event.quit(fails == 0 and 0 or 1)
end
