local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_help_system_controls"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS help_system_controls")
    love.event.quit(0)
  else
    print("FAIL help_system_controls failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local RomText = require("src.core.game3.rom_text")
  local Help = require("src.ui.game3.help_system")

  if not result(Runtime.getSession() ~= nil, "new game reached the game3 field") then return finish() end

  Help.seenIntro = false
  local session = Runtime.getSession()
  if session.flags then
    local Flags = require("src.core.game3.scripting.flags")
    local Space = require("src.core.game3.scripting.space")
    Flags.setFlag(Space.store or session, nil, Flags.IDS.SYS_SAW_HELP_SYSTEM_INTRO, false)
    Flags.setFlag(session, nil, Flags.IDS.SYS_SAW_HELP_SYSTEM_INTRO, false)
  end
  if not result(Help.show(game) == true and Help.isOpen(), "Help opened on the field") then return finish() end
  U.wait(4)

  result(RomText.plain("gString_Help") == "HELP", "gString_Help is HELP")
  result(RomText.plain("gText_HelpSystemControls_A_Next") == "{A_BUTTON}NEXT",
    "gText_HelpSystemControls_A_Next is {A_BUTTON}NEXT")
  result(Help.level == "welcome", "first open shows the welcome page")
  U.shot(game, DIR .. "/help_welcome_a_next.png")

  U.tap(game, "a")
  U.wait(6)
  result(Help.level == "main", "A leaves the welcome page")
  result(RomText.plain("gText_HelpSystemControls_PickOkEnd") == "{DPAD_UPDOWN}PICK {A_BUTTON}OK {B_BUTTON}END",
    "gText_HelpSystemControls_PickOkEnd")
  U.shot(game, DIR .. "/help_main_pick_ok_end.png")

  U.tap(game, "a")
  U.wait(6)
  result(Help.level == "submenu", "A opens a topic")
  U.shot(game, DIR .. "/help_submenu_pick_ok_cancel.png")

  U.tap(game, "a")
  U.wait(6)
  result(Help.level == "article", "A opens an article")
  U.shot(game, DIR .. "/help_article_ab_cancel.png")

  U.tap(game, "l")
  U.wait(6)
  result(not Help.isOpen(), "L closes Help")
  finish()
end
