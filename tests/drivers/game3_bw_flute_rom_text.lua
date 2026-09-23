local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_bw_flute_rom_text"

-- pokefirered/src/item_use.c:582
local ITEM_BLACK_FLUTE = 42
local ITEM_WHITE_FLUTE = 43
-- pokefirered/include/constants/flags.h:1330
local FLAG_SYS_WHITE_FLUTE_ACTIVE = 0x803
local FLAG_SYS_BLACK_FLUTE_ACTIVE = 0x804
local PALLET = "FR_PALLET_TOWN"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_bw_flute_rom_text")
    love.event.quit(0)
  else
    print("FAIL game3_bw_flute_rom_text failures=" .. failures)
    love.event.quit(1)
  end
end

local function run(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Bag = require("src.core.game3.bag")
  local Party = require("src.core.game3.party")
  local ItemsData = require("src.core.game3.items_data")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local Message = require("src.ui.game3.message")
  local StepEvents = require("src.core.game3.step_events")
  local RomText = require("src.core.game3.rom_text")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return end

  session.party = {}
  Party.giveMon(session, 7, 15)
  session.bag = session.bag or {}
  Bag.add(session.bag, ITEM_WHITE_FLUTE, 1)
  Bag.add(session.bag, ITEM_BLACK_FLUTE, 1)

  Map.load(nil, game, PALLET, { x = 7, y = 10, facing = "down" })
  U.wait(90)

  result(ItemsData.fieldUseKind(ITEM_WHITE_FLUTE) == "black_white_flute",
    "WHITE FLUTE carries FieldUseFunc_BlackWhiteFlute from the ROM item table")

  U.tap(game, "start")
  U.wait(30)
  U.shot(game, DIR .. "/refix_start_menu_rom_glyph_cursor.png")

  local function selectBag()
    for _ = 1, 12 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "bag" then break end
      U.tap(game, "down")
      U.wait(8)
    end
    U.tap(game, "a")
    U.wait(60)
  end

  local function onItem(itemId)
    for _ = 1, 5 do
      if BagMenu.currentPocket() == "ITEMS" then break end
      U.tap(game, "left")
      U.wait(15)
    end
    for _ = 1, 24 do
      local want
      for i, r in ipairs(BagMenu.list() or {}) do
        if ItemsData.toNumericId(r.id) == itemId then want = i end
      end
      if not want or BagMenu.cursor == want then break end
      U.tap(game, (BagMenu.cursor > want) and "up" or "down")
      U.wait(8)
    end
    local row = BagMenu.isOpen() and BagMenu.list()[BagMenu.cursor]
    return row and ItemsData.toNumericId(row.id) == itemId
  end

  local Audio = require("src.core.game3.audio")
  local seFrame
  local frameNo = 0
  local realPlaySe = Audio.playSe
  Audio.playSe = function(id, ...)
    if id == 110 then seFrame = frameNo end
    return realPlaySe(id, ...)
  end

  local function useSelected(label)
    U.tap(game, "a")
    U.wait(25)
    for _ = 1, 6 do
      if BagMenu.ACTIONS[BagMenu.actionCursor] == "USE" then break end
      U.tap(game, "down")
      U.wait(8)
    end
    seFrame = nil
    frameNo = 0
    U.tap(game, "a")
    local waitSeen = BagMenu.mode == "flute_wait"
    local msgAt
    for i = 1, 60 do
      frameNo = i
      if BagMenu.mode == "flute_wait" then waitSeen = true end
      if not msgAt and BagMenu.mode == "message" then msgAt = i end
      U.wait(1)
    end
    result(waitSeen and msgAt ~= nil and msgAt >= 7 and msgAt <= 9 and seFrame ~= nil and math.abs(seFrame - msgAt) <= 1,
      label .. " waits 8 frames before SE_GLASS_FLUTE + message (msg at +"
        .. tostring(msgAt) .. ", se at +" .. tostring(seFrame) .. ")")
  end

  local function firstPage(text)
    return (tostring(text):match("^([^\f]*)")) or ""
  end

  local function dismiss()
    for _ = 1, 60 do
      if BagMenu.mode ~= "message" then break end
      U.tap(game, "a")
      U.wait(8)
    end
  end

  selectBag()
  if not result(onItem(ITEM_WHITE_FLUTE), "bag cursor on the WHITE FLUTE") then return end
  useSelected("WHITE FLUTE")
  local ctx = { playerName = tostring(session.name or session.playerName or ""),
    stringVars = { [2] = ItemsData.displayName(ITEM_WHITE_FLUTE) } }
  local want = firstPage(RomText.box("gText_UsedVar2WildLured", ctx))
  result(BagMenu.mode == "message" and BagMenu.messageText == want,
    "WHITE FLUTE prints ROM gText_UsedVar2WildLured page 1 (" .. tostring(BagMenu.messageText) .. ")")
  result(Flags.getFlag(Space.store, nil, FLAG_SYS_WHITE_FLUTE_ACTIVE) == true
    and not Flags.getFlag(Space.store, nil, FLAG_SYS_BLACK_FLUTE_ACTIVE),
    "FLAG_SYS_WHITE_FLUTE_ACTIVE set, BLACK clear")
  U.shot(game, DIR .. "/refix_white_flute_lured_text.png")
  dismiss()
  result(BagMenu.isOpen() and BagMenu.mode == "list", "message paged back to the bag list")

  if not result(onItem(ITEM_BLACK_FLUTE), "bag cursor on the BLACK FLUTE") then return end
  useSelected("BLACK FLUTE")
  ctx.stringVars[2] = ItemsData.displayName(ITEM_BLACK_FLUTE)
  want = firstPage(RomText.box("gText_UsedVar2WildRepelled", ctx))
  result(BagMenu.mode == "message" and BagMenu.messageText == want,
    "BLACK FLUTE prints ROM gText_UsedVar2WildRepelled page 1 (" .. tostring(BagMenu.messageText) .. ")")
  result(Flags.getFlag(Space.store, nil, FLAG_SYS_BLACK_FLUTE_ACTIVE) == true
    and not Flags.getFlag(Space.store, nil, FLAG_SYS_WHITE_FLUTE_ACTIVE),
    "FLAG_SYS_BLACK_FLUTE_ACTIVE set, WHITE clear")
  dismiss()

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
  result(not BagMenu.isOpen(), "bag closed back to the field")

  session.repelSteps = 1
  session.vars[0x4021] = 1
  StepEvents.onRepelStep(session, game)
  local page
  for _ = 1, 240 do
    U.wait(1)
    page = Message.currentPage and Message.currentPage() or nil
    if page and page ~= "" and Message.isWaiting and Message.isWaiting() then break end
  end
  result(page == RomText.box("Text_RepelWoreOff"),
    "repel expiry prints ROM Text_RepelWoreOff (" .. tostring(page) .. ")")
  U.shot(game, DIR .. "/refix_repel_wore_off_text.png")
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then result(false, "driver error: " .. tostring(err)) end
  finish()
end
