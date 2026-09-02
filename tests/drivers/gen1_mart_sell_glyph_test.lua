-- home/list_menu.asm:478-494
--   POKEPORT_IDENTITY=red-aug28 POKEPORT_VERSION=red POKEPORT_DRIVER=tests/drivers/gen1_mart_sell_glyph_test.lua POKEPORT_SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Bag = require("src.inventory.Bag")
  local Flags = require("src.script.Flags")
  local ListMenu = require("src.ui.ListMenu")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function topList()
    local top = game.stack:top()
    if top and getmetatable(top) == ListMenu and top.itemBox then return top end
    return nil
  end

  local function waitForList(frames)
    for _ = 1, frames do
      local l = topList()
      if l then return l end
      U.wait(1)
    end
    return nil
  end

  local function checkRows(name, list)
    if not check(name .. ": an item ListMenu is open", list ~= nil) then return end
    local counted, ascii = 0, 0
    for _, it in ipairs(list.items) do
      if type(it.count) == "number" then counted = counted + 1 end
      if type(it.right) == "string" and it.right:sub(1, 1) == "x" then ascii = ascii + 1 end
    end
    check(name .. ": rows carry numeric counts (" .. counted .. ")", counted > 0)
    check(name .. ": no row carries an ASCII 'x' prefix", ascii == 0)
  end

  local function closeAll()
    for _ = 1, 8 do
      if game.stack:top() == game.overworld then break end
      U.tap(game, "b")
      U.wait(8)
    end
  end

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  game.save.inventory = {}
  game.save.bagOrder = nil
  for _, row in ipairs({ { "POTION", 6 }, { "POKE_BALL", 5 }, { "TM34", 1 },
                         { "RARE_CANDY", 2 }, { "ANTIDOTE", 12 } }) do
    Bag.add(game.save, row[1], row[2], game.data)
  end
  game.save.pcItems = { POTION = 3, ANTIDOTE = 10, ESCAPE_ROPE = 1 }
  Flags.set(game.save, "EVENT_GOT_STARTER")
  Flags.set(game.save, "EVENT_GOT_OAKS_PARCEL")
  Flags.set(game.save, "EVENT_OAK_GOT_PARCEL")

  local MAP = "VIRIDIAN_MART"
  local list
  for _, stand in ipairs({ { 2, 5 }, { 1, 5 } }) do
    U.teleport(game, MAP, stand[1], stand[2], "left")
    U.wait(20)
    U.tap(game, "a")
    U.wait(40)
    for _ = 1, 6 do
      local top = game.stack:top()
      if top and top.items and top.items[2] and top.items[2].label == "SELL" then
        top.index = 2
        U.tap(game, "a")
        break
      end
      U.tap(game, "a")
      U.wait(20)
    end
    list = waitForList(60)
    if list then break end
    closeAll()
  end
  checkRows("mart SELL", list)
  U.wait(10)
  U.shot(game, DIR .. "/mart_sell.png")
  closeAll()
  U.wait(20)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)
  U.tap(game, "start")
  U.wait(15)
  local menu = game.stack:top()
  if menu and menu.items then
    for i, it in ipairs(menu.items) do
      if it.label == "ITEM" then menu.index = i end
    end
  end
  U.tap(game, "a")
  list = waitForList(60)
  checkRows("bag", list)
  U.wait(10)
  U.shot(game, DIR .. "/bag.png")
  closeAll()
  U.wait(20)

  local pc = (game.data.field.hiddenExtras.pcTiles.REDS_HOUSE_2F or {})[1]
              or { x = 0, y = 1 }
  U.teleport(game, "REDS_HOUSE_2F", pc.x, pc.y + 1, "up")
  U.wait(20)
  U.tap(game, "a")
  U.wait(40)
  for _ = 1, 6 do
    if topList() then break end
    U.tap(game, "a")
    U.wait(20)
  end
  list = waitForList(60)
  checkRows("PC WITHDRAW", list)
  U.wait(10)
  U.shot(game, DIR .. "/pc_withdraw.png")

  U.log(failures == 0 and "PASS" or "FAIL", "gen1 quantity glyph driver;",
        "look for '×' (not 'x') before each count in", DIR)
  love.event.quit()
end
