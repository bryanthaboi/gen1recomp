local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_invisible_journal_2414"

-- pokefirered/include/constants/flags.h:176
local FLAG_HIDE_FAME_CHECKER_LT_SURGE_JOURNAL = 0x0A0

return function(game)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish() love.event.quit(failures == 0 and 0 or 1) end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Objects = require("src.core.game3.objects")
  local Message = require("src.ui.game3.message")
  local session = Runtime.getSession()
  if not check(session ~= nil, "journal_new_game") then return finish() end
  local function place(x, y, facing)
    Player.moving, Player.progress = false, 0
    Player.cellX, Player.cellY, Player.targetX, Player.targetY = x, y, x, y
    Player.px, Player.py, Player.facing = x * 16, y * 16, facing
    session.x, session.y, session.facing = x, y, facing
  end
  Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, FLAG_HIDE_FAME_CHECKER_LT_SURGE_JOURNAL, false)
  Map.load(nil, game, "FR_VERMILION_CITY_POKEMON_CENTER_1F", { x = 3, y = 2, facing = "up" })
  place(3, 2, "up")
  U.wait(90)
  local j6, j7 = Objects.find(6), Objects.find(7)
  check(j6 ~= nil and j7 ~= nil and j6.visible and j7.visible, "journal_objects_live")
  check(j6 and j6.invisible and j7 and j7.invisible, "journal_objects_marked_invisible")
  local drawn = false
  for _, eo in ipairs(Objects.forDraw()) do
    if eo.localId == 6 or eo.localId == 7 then drawn = true end
  end
  check(not drawn, "journal_objects_not_drawn")
  check(U.shot(game, DIR .. "/2414_vermilion_pc_shelf_empty.png"), "journal_shelf_screenshot_written")
  U.tap(game, "a")
  local opened = false
  for _ = 1, 120 do
    if Message.isOpen() then opened = true break end
    U.wait(1)
  end
  check(opened, "journal_readable_on_a")
  if opened then
    U.wait(60)
    check(U.shot(game, DIR .. "/2414_vermilion_journal_text.png"), "journal_text_screenshot_written")
  end
  for _ = 1, 120 do
    if not Message.isOpen() and not Space.vm:isRunning() then break end
    U.tap(game, "a")
    U.wait(8)
  end
  finish()
end
