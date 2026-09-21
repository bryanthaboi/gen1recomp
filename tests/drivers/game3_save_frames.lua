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

  love.event.quit(fails == 0 and 0 or 1)
end
