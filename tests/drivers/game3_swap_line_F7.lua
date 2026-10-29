-- pokeemerald/src/battle_pyramid_bag.c:1605 UpdateSwapLinePos
-- pokeemerald/src/player_pc.c:1339 ItemStorage_UpdateSwapLinePos
-- pokefirered/src/item_pc.c:766 ItemPc_MoveItemModeInit

local U = require("tests.drivers.util")

local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_swap_line_F7"
local POTION, ANTIDOTE, REPEL = 13, 14, 86

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " game3_swap_line_F7 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function waitFor(pred, frames)
  for _ = 1, frames or 120 do
    if pred() then return true end
    U.wait(1)
  end
  return pred()
end

local function pcOrder(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = tostring(e.id) end
  return table.concat(out, ",")
end

local function emerald(game, s)
  local Pyramid = require("src.core.game3.rse.frontier.pyramid")
  local PBag = require("src.ui.game3.rse.pyramid_bag")
  local items, qty = Pyramid.bagLists(s)
  for i = 1, Pyramid.BAG_ITEMS_COUNT do items[i], qty[i] = 0, 0 end
  items[1], qty[1] = POTION, 3
  items[2], qty[2] = ANTIDOTE, 2
  items[3], qty[3] = REPEL, 1
  Pyramid.bagCursor = { cursor = 0, scroll = 0 }
  PBag.show({ session = s, location = "field" })
  result(waitFor(function() return PBag.isOpen() and PBag._st.fadeDir == 0 end), "pyramid bag open")
  U.wait(10)
  U.tap(game, "select")
  U.wait(6)
  result(PBag._st.mode == "swap" and PBag._st.swapFrom == 0, "SELECT starts moving POTION in the pyramid bag")
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "down")
  U.wait(20)
  local line = PBag.swapLine()
  result(line and #line == 8 and line[1].x == 120 and line[8].x == 224 and line[1].y == 49,
    "pyramid swap line: 8 sprites x 120..224 at y 49 (row 2)")
  result(PBag.iconItem() == POTION, "pyramid icon stays on POTION")
  result(U.still(game, DIR .. "/F7_01_em_pyramid_swap_line_above_repel.png"), "pyramid swap line screenshot written")
  U.tap(game, "select")
  U.wait(10)
  result(PBag._st.mode == "list" and PBag.swapLine() == nil, "SELECT drops POTION and hides the line")
  result(items[1] == ANTIDOTE and items[2] == POTION and items[3] == REPEL,
    "pyramid order ANTIDOTE, POTION, REPEL")
  result(Pyramid.bagCursor.cursor == 1, "pyramid cursor on POTION")
  U.tap(game, "select")
  U.wait(6)
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "b")
  U.wait(10)
  result(PBag._st.mode == "list" and Pyramid.bagCursor.cursor == 1,
    "B cancel steps the cursor back up (cursor=" .. tostring(Pyramid.bagCursor.cursor) .. ")")
  U.tap(game, "b")
  result(waitFor(function() return not PBag.isOpen() end, 120), "pyramid bag closed")
  U.wait(20)

  local Storage = require("src.core.game3.storage")
  local ItemStorage = require("src.ui.game3.rse.item_storage")
  local st = Storage.ensure(s)
  st.items = { { id = POTION, qty = 3 }, { id = ANTIDOTE, qty = 2 }, { id = REPEL, qty = 1 } }
  ItemStorage.show({ session = s })
  U.wait(10)
  result(ItemStorage.isOpen(), "PC item storage open")
  U.tap(game, "select")
  U.wait(6)
  result(ItemStorage.state == "swap" and ItemStorage.swapFrom == 0, "SELECT starts moving POTION in PC storage")
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "down")
  U.wait(20)
  line = ItemStorage.swapLine()
  result(line and #line == 7 and line[1].x == 128 and line[7].x == 224 and line[1].y == 49,
    "PC swap line: 7 sprites x 128..224 at y 49 (row 2)")
  result(ItemStorage.iconItem() == POTION, "PC icon stays on POTION")
  result(U.still(game, DIR .. "/F7_02_em_pc_swap_line_above_repel.png"), "PC swap line screenshot written")
  U.tap(game, "select")
  U.wait(10)
  result(ItemStorage.state == "list" and pcOrder(st.items) == "14,13,86",
    "PC order ANTIDOTE, POTION, REPEL (" .. pcOrder(st.items) .. ")")
  ItemStorage.close()
  U.wait(10)
end

local function firered(game, s)
  local Storage = require("src.core.game3.storage")
  local ItemPc = require("src.ui.game3.item_pc")
  local st = Storage.ensure(s)
  st.items = { { id = POTION, qty = 3 }, { id = ANTIDOTE, qty = 2 }, { id = REPEL, qty = 1 } }
  ItemPc.show({ session = s })
  result(waitFor(function() return ItemPc.isOpen() and not ItemPc._fx end), "FireRed item PC open")
  U.wait(10)
  U.tap(game, "select")
  U.wait(6)
  result(ItemPc.mode == "move" and ItemPc.moveOrig == 0, "SELECT starts moving POTION in the item PC")
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "down")
  U.wait(20)
  result(U.still(game, DIR .. "/F7_03_frlg_item_pc_swap_line_above_repel.png"), "item PC swap line screenshot written")
  U.tap(game, "select")
  U.wait(10)
  result(ItemPc.mode == "list" and pcOrder(st.items) == "14,13,86",
    "item PC order ANTIDOTE, POTION, REPEL (" .. pcOrder(st.items) .. ")")
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not result(game.boot ~= nil, "boot reached") then return finish() end
  local ok, err = pcall(function()
    game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  end)
  if not ok then print("[driver] new_game error: " .. tostring(err)) end
  U.wait(60)
  local s = require("src.core.game3.runtime").getSession()
  if not result(s ~= nil, "new game session is live") then return finish() end
  local run = s.version == "emerald" and emerald or firered
  local okRun, errRun = xpcall(function() run(game, s) end, debug.traceback)
  result(okRun, "driver body ran" .. (okRun and "" or (": " .. tostring(errRun))))
  finish()
end
