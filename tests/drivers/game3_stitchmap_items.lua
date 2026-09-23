local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchmap_items"

-- pokefirered/include/constants/items.h:89
local ITEM_ESCAPE_ROPE = 85
-- pokefirered/include/constants/items.h:271
local ITEM_COIN_CASE = 260
-- pokefirered/include/constants/items.h:444
local ITEM_POWDER_JAR = 372
-- pokefirered/include/constants/items.h:327
local ITEM_TM28 = 316
local PALLET = "FR_PALLET_TOWN"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchmap_items")
    love.event.quit(0)
  else
    print("FAIL stitchmap_items failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local ItemsData = require("src.core.game3.items_data")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local FieldMoves = require("src.core.game3.field_moves")
  local Message = require("src.ui.game3.message")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local MapCatalog = require("src.import.gba.map_catalog")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local MT_MOON = MapCatalog.pretToEngine("MtMoon_1F")
  if not result(type(MT_MOON) == "string", "Mt Moon 1F resolves to a cache map id") then
    return finish()
  end

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

  session.bag = session.bag or {}
  Bag.add(session.bag, ITEM_COIN_CASE, 1)
  Bag.add(session.bag, ITEM_POWDER_JAR, 1)
  Bag.add(session.bag, ITEM_ESCAPE_ROPE, 3)
  Bag.add(session.bag, ITEM_TM28, 1)

  -- pokefirered/src/coins.c:16 SetCoins
  Bag.Coins.set(session, 2750)
  result(Bag.Coins.get(session) == 2750, "the player has 2750 coins")

  require("src.core.game3.scripting.flags").setFlag(require("src.core.game3.scripting.space").store, nil, 0x828, true) -- data/maps/PalletTown_ProfessorOaksLab/scripts.inc:1120
  if #(session.party or {}) == 0 then
    Party.giveMon(session, 4, 8)
  end
  local mon = session.party and session.party[1]
  if not result(type(mon) == "table", "the player has a party mon") then return finish() end
  result(mon.nickname == "", "the mon came out of Party.giveMon with no nickname")
  local monName = Pokemon.displayMonName(mon)
  result(monName ~= "" and monName ~= nil, "its display name is " .. tostring(monName))

  local tmOk = ItemUse.useTm(session, session.bag, ITEM_TM28, 1)
  result(tmOk == true, "TM28 taught it DIG")
  result(Pokemon.knowsMove(mon, FieldMoves.MOVES.DIG) == true, "the mon knows DIG")

  local function openStart()
    for _ = 1, 20 do
      if StartMenu.isOpen() then return true end
      U.tap(game, "start")
      U.wait(12)
    end
    return StartMenu.isOpen()
  end

  local function startEntry(id)
    if not openStart() then return false end
    for _ = 1, 20 do
      local e = StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == id then return true end
      U.tap(game, "down")
      U.wait(8)
    end
    local e = StartMenu.ENTRIES[StartMenu.cursor]
    return e and e.id == id
  end

  local function openBag()
    if not startEntry("bag") then return false end
    U.tap(game, "a")
    for _ = 1, 60 do
      if BagMenu.isOpen() and not BagMenu._open then break end
      U.wait(4)
    end
    return BagMenu.isOpen()
  end

  local function toPocket(pocket)
    local want
    for i, p in ipairs(ItemsData.BAG_POCKET_ORDER or {}) do
      if p == pocket then want = i end
    end
    if not want then return false end
    for _ = 1, 12 do
      if BagMenu.pocketIdx == want then return true end
      U.tap(game, BagMenu.pocketIdx < want and "right" or "left")
      U.wait(20)
    end
    return BagMenu.currentPocket() == pocket
  end

  local function toRow(itemId)
    local target
    for i, r in ipairs(BagMenu.list()) do
      if ItemsData.toNumericId(r.id) == itemId then target = i end
    end
    if not target then return false end
    for _ = 1, 30 do
      if BagMenu.cursor == target then return true end
      U.tap(game, BagMenu.cursor < target and "down" or "up")
      U.wait(8)
    end
    return BagMenu.cursor == target
  end

  local function pressUse()
    U.tap(game, "a")
    U.wait(10)
    if BagMenu.mode ~= "action" then return false end
    for _ = 1, 8 do
      if BagMenu.ACTIONS[BagMenu.actionCursor] == "USE" then break end
      U.tap(game, "down")
      U.wait(8)
    end
    U.tap(game, "a")
    U.wait(40)
    return true
  end

  Map.load(nil, game, PALLET, { x = 12, y = 11, facing = "down" })
  place(12, 11, "down")
  U.wait(90)
  result(Map.current == PALLET, "standing in Pallet Town, map=" .. tostring(Map.current))

  -- pokefirered/src/item_use.c:337 FieldUseFunc_CoinCase
  result(openBag(), "the START menu opened the bag")
  result(toPocket("KEY_ITEMS"), "on the KEY ITEMS pocket, got " .. tostring(BagMenu.currentPocket()))
  result(toRow(ITEM_COIN_CASE), "cursor on the COIN CASE")
  result(pressUse(), "USE picked for the COIN CASE")
  result(BagMenu.isOpen() == true, "the bag stayed open for the COIN CASE message")
  result(BagMenu.mode == "message", "the bag is in message mode, got " .. tostring(BagMenu.mode))
  local coinText = tostring(BagMenu.messageText)
  result(coinText:find("Your COINS:", 1, true) == 1, "the line is gText_CoinCase: " .. coinText)
  result(coinText:find("2750", 1, true) ~= nil, "it shows the live coin count")
  result(U.shot(game, DIR .. "/stitchmap_items_01_coin_case.png"), "coin case screenshot")

  U.tap(game, "b")
  U.wait(20)
  result(BagMenu.mode == "list" and BagMenu.isOpen(), "B returned to the item list")

  -- pokefirered/src/item_use.c:348 FieldUseFunc_PowderJar
  result(toRow(ITEM_POWDER_JAR), "cursor on the POWDER JAR")
  result(pressUse(), "USE picked for the POWDER JAR")
  local powderText = tostring(BagMenu.messageText)
  result(BagMenu.mode == "message", "the bag is in message mode for the POWDER JAR")
  result(powderText:find("POWDER QTY:", 1, true) == 1, "the line is gText_PowderQty: " .. powderText)
  result(U.shot(game, DIR .. "/stitchmap_items_02_powder_jar.png"), "powder jar screenshot")

  U.tap(game, "b")
  U.wait(20)

  -- pokefirered/src/item_use.c:614 CanUseEscapeRopeOnCurrMap
  local ropesBefore = Bag.get(session.bag, ITEM_ESCAPE_ROPE)
  result(toPocket("ITEMS"), "on the ITEMS pocket, got " .. tostring(BagMenu.currentPocket()))
  result(toRow(ITEM_ESCAPE_ROPE), "cursor on the ESCAPE ROPE")
  result(pressUse(), "USE picked for the ESCAPE ROPE in Pallet Town")
  local ropeText = tostring(BagMenu.messageText)
  result(BagMenu.mode == "message", "Pallet Town answered with a message")
  result(ropeText:find("OAK:", 1, true) == 1, "Pallet Town refuses the ESCAPE ROPE: " .. ropeText)
  result(Bag.get(session.bag, ITEM_ESCAPE_ROPE) == ropesBefore, "the refused rope was not spent")
  result(U.shot(game, DIR .. "/stitchmap_items_03_rope_refused_pallet.png"),
    "refused escape rope screenshot")

  U.tap(game, "b")
  U.wait(20)
  for _ = 1, 40 do
    if not BagMenu.isOpen() then break end
    U.tap(game, "b")
    U.wait(10)
  end
  if StartMenu.isOpen() then
    U.tap(game, "b")
    U.wait(20)
  end
  result(BagMenu.isOpen() == false, "the bag closed")

  Map.load(nil, game, MT_MOON, { x = 5, y = 35, facing = "down" })
  place(5, 35, "down")
  U.wait(120)
  result(Map.current == MT_MOON, "standing in Mt Moon 1F, map=" .. tostring(Map.current))
  local moonDef = Map.currentDef()
  result(moonDef ~= nil and (tonumber(moonDef.allowEscaping) or 0) ~= 0,
    "the live Mt Moon def carries allowEscaping")

  -- pokefirered/src/fldeff_dig.c:12 SetUpFieldMove_Dig
  result(startEntry("pokemon"), "the START menu is on POKEMON")
  U.tap(game, "a")
  for _ = 1, 60 do
    if PartyMenu.isOpen and PartyMenu.isOpen() then break end
    U.wait(4)
  end
  result(PartyMenu.isOpen == nil or PartyMenu.isOpen() == true, "the party menu opened")
  U.tap(game, "a")
  U.wait(20)
  local digIdx
  for i, act in ipairs(PartyMenu.ACTIONS or {}) do
    if act == "DIG" then digIdx = i end
  end
  if not result(digIdx ~= nil, "DIG is offered in the party action menu") then return finish() end
  for _ = 1, 10 do
    if PartyMenu.actionCursor == digIdx then break end
    U.tap(game, PartyMenu.actionCursor < digIdx and "down" or "up")
    U.wait(8)
  end
  result(PartyMenu.actionCursor == digIdx, "cursor on DIG")
  U.tap(game, "a")
  U.wait(30)
  for _ = 1, 120 do
    if Message.isOpen() and not Message.isTyping() then break end
    U.wait(2)
  end
  local digLine = tostring(Message.currentPage() or "")
  result(Message.isOpen() == true, "DIG printed a field message")
  result(digLine:find("^ used") == nil, "the DIG line is not blank-named: " .. digLine)
  result(digLine:find(monName, 1, true) == 1, "the DIG line names the mon: " .. digLine)
  result(U.shot(game, DIR .. "/stitchmap_items_04_dig_named.png"), "dig message screenshot")

  for _ = 1, 400 do
    if Map.current ~= MT_MOON then break end
    U.wait(4)
  end
  result(Map.current ~= MT_MOON, "DIG warped out of Mt Moon to " .. tostring(Map.current))
  U.wait(60)
  for _ = 1, 40 do
    if not Message.isOpen() then break end
    U.tap(game, "a")
    U.wait(8)
  end

  Map.load(nil, game, MT_MOON, { x = 5, y = 35, facing = "down" })
  place(5, 35, "down")
  U.wait(120)
  result(Map.current == MT_MOON, "back in Mt Moon 1F for the escape rope")
  result(U.shot(game, DIR .. "/stitchmap_items_05_mt_moon.png"), "Mt Moon screenshot")

  result(openBag(), "the bag opened inside Mt Moon")
  result(toPocket("ITEMS"), "on the ITEMS pocket, got " .. tostring(BagMenu.currentPocket()))
  local ropes = Bag.get(session.bag, ITEM_ESCAPE_ROPE)
  result(toRow(ITEM_ESCAPE_ROPE), "cursor on the ESCAPE ROPE in Mt Moon")
  result(pressUse(), "USE picked for the ESCAPE ROPE in Mt Moon")
  for _ = 1, 300 do
    if not BagMenu.isOpen() and Message.isOpen() and not Message.isTyping() then break end
    U.wait(1)
  end
  -- pokefirered/src/item_use.c:159 SetUpItemUseOnFieldCallback
  result(BagMenu.isOpen() == false,
    "the bag faded out before the rope's line printed (mode=" .. tostring(BagMenu.mode) .. ")")
  -- pokefirered/src/item_use.c:634 ItemUseOnFieldCB_EscapeRope
  result(Message.isOpen() == true
      and tostring(Message.currentPage() or ""):find("ESCAPE ROPE", 1, true) ~= nil,
    "and it is gText_PlayerUsedVar2 on the field box ("
      .. tostring(Message.currentPage()) .. ")")
  result(Map.current == MT_MOON, "nothing warped while it was up")
  -- pokefirered/src/item_use.c:642 Task_UseDigEscapeRopeOnField
  for _ = 1, 40 do
    if not Message.isOpen() then break end
    U.tap(game, "a")
    U.wait(8)
  end
  for _ = 1, 400 do
    if Map.current ~= MT_MOON then break end
    U.wait(4)
  end
  result(Map.current ~= MT_MOON, "the rope warped out of Mt Moon to " .. tostring(Map.current))
  result(Bag.get(session.bag, ITEM_ESCAPE_ROPE) == ropes - 1, "the used rope was spent")
  U.wait(90)
  for _ = 1, 40 do
    if not Message.isOpen() then break end
    U.tap(game, "a")
    U.wait(8)
  end
  U.wait(60)
  result(U.shot(game, DIR .. "/stitchmap_items_06_rope_arrival.png"), "escape rope arrival screenshot")

  finish()
end
