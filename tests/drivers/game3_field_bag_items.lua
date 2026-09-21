local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_bag_items"

-- pokefirered/src/item_use.c:286 FieldUseFunc_Rod
-- pokefirered/src/item_use.c:359 FieldUseFunc_PokeFlute
local ITEM_OLD_ROD = 262
local ITEM_POKE_FLUTE = 350
local PALLET = "FR_PALLET_TOWN"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS field_bag_items")
    love.event.quit(0)
  else
    print("FAIL field_bag_items failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Bag = require("src.core.game3.bag")
  local Party = require("src.core.game3.party")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local Message = require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, 7, 15)
  session.party[1].status = "SLP"
  session.party[1].sleep = 3
  session.bag = session.bag or {}
  Bag.add(session.bag, ITEM_OLD_ROD, 1)
  Bag.add(session.bag, ITEM_POKE_FLUTE, 1)

  local function place(x, y, facing)
    Player.moving = false
    Player.progress = 0
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  Map.load(nil, game, PALLET, { x = 7, y = 16, facing = "down" })
  place(7, 16, "down")
  U.wait(90)
  result(Space.mapId == PALLET, "stood on the Pallet Town beach, map=" .. tostring(Space.mapId))

  local function openBagOn(itemId)
    U.tap(game, "start")
    U.wait(30)
    for _ = 1, 12 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "bag" then break end
      U.tap(game, "down")
      U.wait(8)
    end
    U.tap(game, "a")
    U.wait(60)
    for _ = 1, 5 do
      if BagMenu.currentPocket() == "KEY_ITEMS" then break end
      U.tap(game, "right")
      U.wait(15)
    end
    for _ = 1, 24 do
      if not BagMenu.isOpen() then break end
      local want
      for i, r in ipairs(BagMenu.list() or {}) do
        if r.id == itemId then want = i end
      end
      if not want or BagMenu.cursor == want then break end
      U.tap(game, (BagMenu.cursor > want) and "up" or "down")
      U.wait(8)
    end
    local row = BagMenu.isOpen() and BagMenu.list()[BagMenu.cursor]
    if not (row and row.id == itemId) then
      local ids = {}
      for i, r in ipairs(BagMenu.list() or {}) do ids[i] = tostring(r.id) end
      print(string.format("[driver] bag=%s pocket=%s mode=%s cursor=%s row=%s list=%s",
        tostring(BagMenu.isOpen()), tostring(BagMenu.currentPocket()),
        tostring(BagMenu.mode), tostring(BagMenu.cursor),
        tostring(row and row.id), table.concat(ids, ",")))
    end
    return row and row.id == itemId
  end

  if not result(openBagOn(ITEM_POKE_FLUTE), "bag cursor on the POKe FLUTE") then
    return finish()
  end
  U.shot(game, DIR .. "/field_bag_items_01_flute_selected.png")
  U.tap(game, "a")
  U.wait(25)
  U.tap(game, "a")
  U.wait(60)

  -- pokefirered/src/item_use.c:359 FieldUseFunc_PokeFlute
  result(session.party[1].status ~= "SLP", "the flute woke the sleeping mon")
  -- pokefirered/src/item_menu.c:471 a bag USE runs with data[3] == 0
  local bagPage = BagMenu.messageText or ""
  result(BagMenu.mode == "message" and bagPage:find("FLUTE", 1, true) ~= nil,
    "gText_PlayedPokeFlute is in the bag's message box (" .. tostring(bagPage) .. ")")
  result(BagMenu.isOpen() == true, "and DisplayItemMessageInBag kept the bag up")
  U.shot(game, DIR .. "/field_bag_items_02_flute_message.png")
  for _ = 1, 60 do
    if BagMenu.mode ~= "message" then break end
    U.tap(game, "a")
    U.wait(8)
  end
  -- pokefirered/src/item_use.c:388 Task_DisplayPokeFluteMessage
  result(BagMenu.isOpen() == true and BagMenu.mode == "list",
    "A pages through it back to the item list (mode=" .. tostring(BagMenu.mode) .. ")")

  result(Message.isOpen() == false,
    "and nothing escaped to the field message box")

  -- pokefirered/src/item_menu.c:1085 the bag's own B exit
  U.tap(game, "b")
  for _ = 1, 180 do
    if not BagMenu.isOpen() then break end
    U.wait(1)
  end
  U.wait(30)
  if StartMenu.isOpen and StartMenu.isOpen() then
    U.tap(game, "b")
    U.wait(30)
  end
  result(BagMenu.isOpen() == false, "and B handed the field back")

  place(7, 16, "down")
  U.wait(60)
  result(Field.locked == false, "the D-pad is free again")

  if not result(openBagOn(ITEM_OLD_ROD), "bag cursor on the OLD ROD") then return finish() end
  U.shot(game, DIR .. "/field_bag_items_03_rod_selected.png")
  U.tap(game, "a")
  U.wait(25)
  U.tap(game, "a")
  U.wait(60)

  -- pokefirered/src/item_use.c:324 ItemUseOnFieldCB_Rod
  result(Field.isFishing() == true, "USE on the rod started the fishing task")
  result(BagMenu.isOpen() == false, "and left the bag for the field")
  local t0 = Field._fishing and Field._fishing.timer
  U.wait(45)
  local t1 = Field._fishing and Field._fishing.timer
  result(t0 ~= nil and t1 ~= nil and t1 ~= t0,
    "the fishing task ticks (timer " .. tostring(t0) .. " -> " .. tostring(t1) .. ")")
  U.shot(game, DIR .. "/field_bag_items_04_rod_cast.png")

  for _ = 1, 900 do
    U.wait(1)
    local p = Message.currentPage() or ""
    if Message.isWaiting() and (p:find("nibble", 1, true) or p:find("hook", 1, true)) then
      result(true, "the cast resolved (" .. p .. ")")
      break
    end
  end

  finish()
end
