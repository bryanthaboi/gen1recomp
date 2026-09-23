local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_hidden_item_persistence"
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
  local Field = require("src.core.game3.field")
  local Bag = require("src.core.game3.bag")
  local Message = require("src.ui.game3.message")
  local Start = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local session = Runtime.getSession()
  if not check(session ~= nil, "hidden_new_game") then return finish() end
  session.bag = Bag.new()
  Flags.setVar(Space.store, nil, 0x4070, 1)
  Space.persistSession(nil, game)
  local function forest()
    Map.load(nil, game, "FR_VIRIDIAN_FOREST", { x = 28, y = 58, facing = "up" })
    Player.cellX, Player.cellY, Player.targetX, Player.targetY = 28, 58, 28, 58
    Player.px, Player.py, Player.facing = 448, 928, "up"
    session.x, session.y, session.facing = 28, 58, "up"
    local MapPreview = require("src.ui.game3.map_preview_screen")
    for _ = 1, 600 do
      if not MapPreview.isActive() and not Field.locked then break end
      U.wait(1)
    end
    U.wait(10)
  end
  forest()
  if not check(Field.hiddenItemAt(game, 28, 57, 0) ~= nil, "hidden_forest_antidote_present") then return finish() end
  U.tap(game, "a")
  U.wait(120)
  if not check(Message.isOpen() and Bag.get(session.bag, 14) == 1, "hidden_first_pickup") then return finish() end
  check(U.shot(game, DIR .. "/2364_antidote_found.png"), "hidden_pickup_screenshot_written")
  for _ = 1, 30 do
    if not Message.isOpen() then break end
    U.tap(game, "a")
    U.wait(15)
  end
  U.tap(game, "start")
  U.wait(40)
  if not check(Start.isOpen(), "hidden_start_open") then return finish() end
  check(U.shot(game, DIR .. "/2364_start_after_pickup.png"), "hidden_start_screenshot_written")
  U.tap(game, "b")
  U.wait(30)
  U.tap(game, "a")
  U.wait(30)
  check(not Message.isOpen() and Bag.get(session.bag, 14) == 1, "hidden_no_duplicate_after_start")
  check(Flags.getFlag(Space.store, nil, 0x3E9) and Flags.getFlag(session, nil, 0x3E9), "hidden_live_and_saved_flags")
  check(not Field.useItemfinder(session, false), "hidden_itemfinder_ignores_collected")
  Map.load(nil, game, "FR_PALLET_TOWN", { x = 5, y = 7, facing = "down" })
  U.wait(60)
  forest()
  U.tap(game, "a")
  U.wait(30)
  check(not Message.isOpen() and Bag.get(session.bag, 14) == 1, "hidden_no_duplicate_after_map_return")
  U.tap(game, "start")
  U.wait(30)
  for _ = 1, #Start.ENTRIES do
    if Start.ENTRIES[Start.cursor].id == "bag" then break end
    U.tap(game, "down")
    U.wait(5)
  end
  U.tap(game, "a")
  U.wait(60)
  if check(BagMenu.isOpen() and BagMenu.currentPocket() == "ITEMS", "hidden_bag_quantity_visible") then
    check(U.shot(game, DIR .. "/2364_one_antidote_after_menu_and_map.png"), "hidden_quantity_screenshot_written")
  end
  finish()
end
