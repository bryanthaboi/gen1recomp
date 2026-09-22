-- FRLG PC Hub Menu & Player PC Item Storage (pret data/scripts/pc.inc).
--
-- Options:
-- 1. BILL'S PC / SOMEONE'S PC (Opens Pokémon Storage System)
-- 2. <PLAYER>'S PC (ITEM STORAGE / MAILBOX / TURN OFF)
-- 3. PROF. OAK'S PC (Pokédex Rating)
-- 4. HALL OF FAME (Game Clear check)
-- 5. LOG OFF (Turns off PC with SE_PC_OFF)

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")
local Strings = require("src.core.Strings")

local PcMenu = {}

PcMenu.open = false
PcMenu.mode = "root" -- root | player_pc | item_storage | withdraw_item | withdraw_qty | deposit_item | deposit_qty | oak_pc | msg
PcMenu.cursor = 1
PcMenu.itemCursor = 1
PcMenu.itemScroll = 0
PcMenu.itemQty = 1
PcMenu.yesNoCursor = 2
PcMenu.selectedPocket = "ITEMS"
PcMenu.pocketIdx = 1

local VISIBLE_ITEMS = 6

-- pokefirered/src/player_pc.c:85
-- Labels, descriptions and TEXT_* are English sources, translated where they
-- are drawn or put in PcMenu._status.
PcMenu.TOP_ACTIONS = {
  { id = "item_storage", label = Strings.source("ITEM STORAGE") },
  { id = "mailbox", label = Strings.source("MAILBOX") },
  { id = "turn_off", label = Strings.source("TURN OFF") },
}

-- pokefirered/src/player_pc.c:94
PcMenu.ITEM_STORAGE_ACTIONS = {
  { id = "withdraw", label = Strings.source("WITHDRAW ITEM"), desc = Strings.source("Take out items from the PC.") },
  { id = "deposit", label = Strings.source("DEPOSIT ITEM"), desc = Strings.source("Store items in the PC.") },
  { id = "cancel", label = Strings.source("CANCEL"), desc = Strings.source("Go back to the\nprevious menu.") },
}

PcMenu.TEXT_WHAT_TO_DO = Strings.source("What would you like to do?") -- pokefirered/src/strings.c:158
PcMenu.TEXT_NO_ITEMS = Strings.source("There are no items.") -- pokefirered/src/strings.c:381
PcMenu.TEXT_NO_MAIL = Strings.source("There's no MAIL here.") -- pokefirered/src/strings.c:388

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local FLAG_SYS_NOT_SOMEONES_PC = 0x834 -- pokefirered/include/constants/flags.h:1386

local function script_store(session)
  local Space = package.loaded["src.core.game3.scripting.space"]
  return (Space and Space.store) or (session and session.store) or session
end

-- pokefirered/src/script_menu.c:1027
local function someone_or_bill_name(session)
  local Flags = require("src.core.game3.scripting.flags")
  local isBill = Flags.getFlag(script_store(session), nil, FLAG_SYS_NOT_SOMEONES_PC)
  return isBill and Strings("BILL'S PC") or Strings("SOMEONE'S PC")
end
PcMenu.storageLabel = someone_or_bill_name

local function player_pc_name(session)
  local name = (session and (session.name or session.playerName)) or "RED"
  return Strings("%s's PC", name)
end

function PcMenu._rootEntries()
  local who = someone_or_bill_name(PcMenu._session)
  local player = player_pc_name(PcMenu._session)
  local key = (Strings.active() and "t" or "e") .. "\0" .. who .. "\0" .. player
  if PcMenu._rootKey ~= key then
    PcMenu._rootKey = key
    PcMenu._rootRows = {
      { id = "storage", label = who },
      { id = "player", label = player },
      { id = "oak", label = Strings("PROF. OAK's PC") },
      { id = "hall", label = Strings("HALL OF FAME") },
      { id = "quit", label = Strings("LOG OFF") },
    }
  end
  return PcMenu._rootRows
end

function PcMenu.show(opts)
  opts = opts or {}
  PcMenu.open = true
  PcMenu._session = opts.session
  PcMenu._onClose = opts.onClose
  PcMenu._closeOnExit = opts.closeOnExit == true
  PcMenu.cursor = 1
  PcMenu._prevStatus = nil
  PcMenu._prevCursor = nil
  Storage.ensure(PcMenu._session)
  if opts.startMode == "player_pc" then
    PcMenu.mode = "player_pc"
    PcMenu._status = Strings(PcMenu.TEXT_WHAT_TO_DO) -- pokefirered/src/player_pc.c:160
  else
    PcMenu.mode = "root"
    PcMenu._status = Strings("Which PC would you like to access?")
    se(2) -- SE_PC_ON / SE_PC_LOGIN
  end
  Stack.push("pc_menu", PcMenu, { hideBelow = false })
end

function PcMenu.close()
  PcMenu.open = false
  Stack.pop("pc_menu")
  se(3) -- SE_PC_OFF
  local cb = PcMenu._onClose
  PcMenu._onClose = nil
  if cb then cb() end
end

function PcMenu.isOpen()
  return PcMenu.open
end

local function clamp_item_cursor(items)
  items = items or {}
  local total = #items + 1 -- include CANCEL
  if PcMenu.itemCursor > total then PcMenu.itemCursor = total end
  if PcMenu.itemCursor < 1 then PcMenu.itemCursor = 1 end
  if PcMenu.itemCursor <= PcMenu.itemScroll then
    PcMenu.itemScroll = PcMenu.itemCursor - 1
  end
  if PcMenu.itemCursor > PcMenu.itemScroll + VISIBLE_ITEMS then
    PcMenu.itemScroll = PcMenu.itemCursor - VISIBLE_ITEMS
  end
  if PcMenu.itemScroll < 0 then PcMenu.itemScroll = 0 end
end

local function show_msg(text, prevMode, prevStatus, prevCursor)
  PcMenu._status = text
  PcMenu._prevMode = prevMode
  PcMenu._prevStatus = prevStatus
  PcMenu._prevCursor = prevCursor
  PcMenu.mode = "msg"
end

local function open_item_storage(cursor)
  PcMenu.mode = "item_storage"
  PcMenu.cursor = cursor
  PcMenu._status = Strings(PcMenu.ITEM_STORAGE_ACTIONS[cursor].desc)
end

local function draw_status_lines()
  Window.dialogueFrame()
  if not PcMenu._status then return end
  local lines = {}
  for line in tostring(PcMenu._status):gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  if #lines > 0 then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
  if #lines > 1 then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
end

function PcMenu.handleInput(input)
  if not PcMenu.open then return end

  -- Message state
  if PcMenu.mode == "msg" then
    if input:wasPressed("a") or input:wasPressed("b") then
      PcMenu.mode = PcMenu._prevMode or "root"
      PcMenu._status = PcMenu._prevStatus
      if PcMenu._prevCursor then PcMenu.cursor = PcMenu._prevCursor end
      PcMenu._prevStatus = nil
      PcMenu._prevCursor = nil
      se(5)
    end
    return
  end

  -- Storage System Menu (WITHDRAW POKéMON, DEPOSIT POKéMON, MOVE POKéMON, MOVE ITEMS, SEE YA!)
  local STORAGE_OPTIONS = {
    { id = "withdraw", label = Strings("WITHDRAW POKéMON"), desc = Strings("You can withdraw a POKéMON if you\nhave any in a BOX.") },
    { id = "deposit", label = Strings("DEPOSIT POKéMON"), desc = Strings("You can deposit your party\nPOKéMON in any BOX.") },
    { id = "move", label = Strings("MOVE POKéMON"), desc = Strings("You can move POKéMON that are\nstored in any BOX.") },
    { id = "move_items", label = Strings("MOVE ITEMS"), desc = Strings("You can move items held by any\nPOKéMON in a BOX or your party.") },
    { id = "quit", label = Strings("SEE YA!"), desc = Strings("See you later!") },
  }

  -- Root Menu
  if PcMenu.mode == "root" then
    local entries = PcMenu._rootEntries()

    if input:wasPressed("up") then
      PcMenu.cursor = ((PcMenu.cursor - 2) % #entries) + 1
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.cursor = (PcMenu.cursor % #entries) + 1
      se(5)
    elseif input:wasPressed("a") then
      local choice = entries[PcMenu.cursor]
      if choice.id == "quit" then
        PcMenu.close()
      elseif choice.id == "storage" then
        se(5)
        PcMenu.mode = "storage_menu"
        PcMenu.storageCursor = PcMenu.storageCursor or 1
        PcMenu.cursor = PcMenu.storageCursor
        PcMenu._status = STORAGE_OPTIONS[PcMenu.cursor].desc
      elseif choice.id == "player" then
        se(5)
        PcMenu.mode = "player_pc"
        PcMenu.cursor = 1
        PcMenu._status = Strings("What would you like to do?")
      elseif choice.id == "oak" then
        se(5)
        local Dex = require("src.core.game3.dex")
        local dex = PcMenu._session and PcMenu._session.dex
        local caught = dex and Dex.countCaught(dex, "kanto") or 0
        local seen = dex and Dex.countSeen(dex, "kanto") or 0
        PcMenu._status = Strings("Current POKéDEX status:\nSeen: %d   Owned: %d", seen, caught)
        PcMenu._prevMode = "root"
        PcMenu.mode = "msg"
      elseif choice.id == "hall" then
        se(5)
        PcMenu._status = Strings("No records in the HALL OF FAME.")
        PcMenu._prevMode = "root"
        PcMenu.mode = "msg"
      end
    elseif input:wasPressed("b") then
      PcMenu.close()
    end
    return
  end

  -- Storage Submenu (Withdraw, Deposit, Move Pokémon, Move Items, See Ya!)
  if PcMenu.mode == "storage_menu" then
    if input:wasPressed("up") then
      PcMenu.cursor = ((PcMenu.cursor - 2) % #STORAGE_OPTIONS) + 1
      PcMenu.storageCursor = PcMenu.cursor
      PcMenu._status = STORAGE_OPTIONS[PcMenu.cursor].desc
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.cursor = (PcMenu.cursor % #STORAGE_OPTIONS) + 1
      PcMenu.storageCursor = PcMenu.cursor
      PcMenu._status = STORAGE_OPTIONS[PcMenu.cursor].desc
      se(5)
    elseif input:wasPressed("a") then
      local choice = STORAGE_OPTIONS[PcMenu.cursor]
      if choice.id == "quit" then
        PcMenu.mode = "root"
        PcMenu.cursor = 1
        PcMenu._status = Strings("Which PC would you like to access?")
        se(5)
      elseif choice.id == "withdraw" then
        local party = (PcMenu._session and PcMenu._session.party) or {}
        if #party >= 6 then
          PcMenu._status = Strings("Can't take any more POKéMON.")
          PcMenu._prevMode = "storage_menu"
          PcMenu.mode = "msg"
          se(5) -- pokefirered/src/pokemon_storage_system_tasks.c:992
        else
          se(5)
          local BoxStorageUI = require("src.ui.game3.box_storage_ui")
          BoxStorageUI.show({
            session = PcMenu._session,
            subMode = "withdraw",
            onClose = function()
              PcMenu.mode = "storage_menu"
              PcMenu.cursor = 1
              PcMenu._status = STORAGE_OPTIONS[1].desc
              se(2)
            end,
          })
        end
      elseif choice.id == "deposit" then
        local party = (PcMenu._session and PcMenu._session.party) or {}
        if #party <= 1 then
          PcMenu._status = Strings("Can't deposit the last POKéMON!")
          PcMenu._prevMode = "storage_menu"
          PcMenu.mode = "msg"
          se(26) -- pokefirered/src/pokemon_storage_system_tasks.c:1052
        else
          se(5)
          local BoxStorageUI = require("src.ui.game3.box_storage_ui")
          BoxStorageUI.show({
            session = PcMenu._session,
            subMode = "deposit",
            onClose = function()
              PcMenu.mode = "storage_menu"
              PcMenu.cursor = 2
              PcMenu._status = STORAGE_OPTIONS[2].desc
              se(2)
            end,
          })
        end
      elseif choice.id == "move" or choice.id == "move_items" then
        se(5)
        local curIdx = PcMenu.cursor
        local BoxStorageUI = require("src.ui.game3.box_storage_ui")
        BoxStorageUI.show({
          session = PcMenu._session,
          subMode = choice.id,
          onClose = function()
            PcMenu.mode = "storage_menu"
            PcMenu.cursor = curIdx
            PcMenu._status = STORAGE_OPTIONS[curIdx].desc
            se(2)
          end,
        })
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "root"
      PcMenu.cursor = 1
      PcMenu._status = Strings("Which PC would you like to access?")
      se(5)
    end
    return
  end

  -- pokefirered/src/player_pc.c:189
  if PcMenu.mode == "player_pc" then
    local actions = PcMenu.TOP_ACTIONS
    if input:wasPressed("up") then
      if PcMenu.cursor > 1 then
        PcMenu.cursor = PcMenu.cursor - 1
        se(5)
      end
    elseif input:wasPressed("down") then
      if PcMenu.cursor < #actions then
        PcMenu.cursor = PcMenu.cursor + 1
        se(5)
      end
    elseif input:wasPressed("a") or input:wasPressed("b") then
      se(5)
      local id = input:wasPressed("a") and actions[PcMenu.cursor].id or "turn_off"
      if id == "item_storage" then
        open_item_storage(1)
      elseif id == "mailbox" then
        show_msg(Strings(PcMenu.TEXT_NO_MAIL), "player_pc", Strings(PcMenu.TEXT_WHAT_TO_DO), 1) -- pokefirered/src/player_pc.c:227
      elseif PcMenu._closeOnExit then
        PcMenu.close() -- pokefirered/src/player_pc.c:257
      else
        PcMenu.mode = "root"
        PcMenu.cursor = 2
        PcMenu._status = Strings("Which PC would you like to access?")
      end
    end
    return
  end

  -- pokefirered/src/player_pc.c:287
  if PcMenu.mode == "item_storage" then
    local actions = PcMenu.ITEM_STORAGE_ACTIONS
    if input:wasPressed("up") then
      if PcMenu.cursor > 1 then
        PcMenu.cursor = PcMenu.cursor - 1
        PcMenu._status = Strings(actions[PcMenu.cursor].desc)
        se(5)
      end
    elseif input:wasPressed("down") then
      if PcMenu.cursor < #actions then
        PcMenu.cursor = PcMenu.cursor + 1
        PcMenu._status = Strings(actions[PcMenu.cursor].desc)
        se(5)
      end
    elseif input:wasPressed("a") or input:wasPressed("b") then
      se(5)
      local id = input:wasPressed("a") and actions[PcMenu.cursor].id or "cancel"
      if id == "withdraw" then
        local storage = Storage.ensure(PcMenu._session)
        if #storage.items < 1 then
          show_msg(Strings(PcMenu.TEXT_NO_ITEMS), "item_storage", Strings(actions[1].desc), 1) -- pokefirered/src/player_pc.c:352
        else
          PcMenu.mode = "withdraw_item"
          PcMenu.itemCursor = 1
          PcMenu.itemScroll = 0
          PcMenu._status = Strings("What do you want to withdraw?")
        end
      elseif id == "deposit" then
        PcMenu.mode = "deposit_item"
        PcMenu.itemCursor = 1
        PcMenu.itemScroll = 0
        PcMenu._status = Strings("What do you want to deposit?")
      else
        PcMenu.mode = "player_pc" -- pokefirered/src/player_pc.c:399
        PcMenu.cursor = 1
        PcMenu._status = Strings(PcMenu.TEXT_WHAT_TO_DO)
      end
    end
    return
  end

  -- Withdraw Item selection
  if PcMenu.mode == "withdraw_item" then
    local storage = Storage.ensure(PcMenu._session)
    local items = storage.items or {}
    clamp_item_cursor(items)

    if input:wasPressed("up") then
      PcMenu.itemCursor = ((PcMenu.itemCursor - 2) % (#items + 1)) + 1
      clamp_item_cursor(items)
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.itemCursor = (PcMenu.itemCursor % (#items + 1)) + 1
      clamp_item_cursor(items)
      se(5)
    elseif input:wasPressed("a") then
      if PcMenu.itemCursor > #items then
        open_item_storage(1) -- pokefirered/src/player_pc.c:371
        se(5)
      else
        local entry = items[PcMenu.itemCursor]
        if (entry.qty or 1) > 1 then
          PcMenu.mode = "withdraw_qty"
          PcMenu.itemQty = 1
          PcMenu._pendingItem = entry
          PcMenu._status = Strings("How many to withdraw?")
        else
          local ok, err = Storage.withdrawItem(PcMenu._session, PcMenu.itemCursor, 1)
          if ok then
            show_msg(Strings("Withdrew 1 %s.", ItemsData.displayName(entry.id)),
              "item_storage", Strings(PcMenu.ITEM_STORAGE_ACTIONS[1].desc), 1)
            se(246)
          else
            PcMenu._status = Strings("The BAG is full.")
            PcMenu._prevMode = "withdraw_item"
            PcMenu.mode = "msg"
            se(5) -- pokefirered/src/item_pc.c:863
          end
        end
      end
    elseif input:wasPressed("b") then
      open_item_storage(1)
      se(5)
    end
    return
  end

  -- Withdraw Quantity selection
  if PcMenu.mode == "withdraw_qty" then
    local entry = PcMenu._pendingItem
    local maxQ = entry and entry.qty or 1

    if input:wasPressed("up") then
      PcMenu.itemQty = (PcMenu.itemQty % maxQ) + 1
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.itemQty = ((PcMenu.itemQty - 2) % maxQ) + 1
      se(5)
    elseif input:wasPressed("right") then
      PcMenu.itemQty = math.min(maxQ, PcMenu.itemQty + 10)
      se(5)
    elseif input:wasPressed("left") then
      PcMenu.itemQty = math.max(1, PcMenu.itemQty - 10)
      se(5)
    elseif input:wasPressed("a") then
      local ok, err = Storage.withdrawItem(PcMenu._session, PcMenu.itemCursor, PcMenu.itemQty)
      if ok then
        show_msg(Strings("Withdrew %d %s.", PcMenu.itemQty, ItemsData.displayName(entry.id)),
          "item_storage", Strings(PcMenu.ITEM_STORAGE_ACTIONS[1].desc), 1)
        se(246)
      else
        PcMenu._status = Strings("The BAG is full.")
        PcMenu._prevMode = "withdraw_item"
        PcMenu.mode = "msg"
        se(5) -- pokefirered/src/item_pc.c:984
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "withdraw_item"
      PcMenu._status = Strings("What do you want to withdraw?")
      se(5)
    end
    return
  end

  -- Deposit Item selection (from bag)
  if PcMenu.mode == "deposit_item" then
    local bag = PcMenu._session and PcMenu._session.bag
    local items = bag and Bag.listPocket(bag, PcMenu.selectedPocket) or {}
    clamp_item_cursor(items)

    if input:wasPressed("up") then
      PcMenu.itemCursor = ((PcMenu.itemCursor - 2) % (#items + 1)) + 1
      clamp_item_cursor(items)
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.itemCursor = (PcMenu.itemCursor % (#items + 1)) + 1
      clamp_item_cursor(items)
      se(5)
    elseif input:wasPressed("left") or input:wasPressed("right") then
      local pockets = ItemsData.POCKET_ORDER or { "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH" }
      local pIdx = PcMenu.pocketIdx or 1
      if input:wasPressed("right") then
        pIdx = (pIdx % #pockets) + 1
      else
        pIdx = ((pIdx - 2) % #pockets) + 1
      end
      PcMenu.pocketIdx = pIdx
      PcMenu.selectedPocket = pockets[pIdx]
      PcMenu.itemCursor = 1
      PcMenu.itemScroll = 0
      se(5)
    elseif input:wasPressed("a") then
      if PcMenu.itemCursor > #items then
        open_item_storage(2) -- pokefirered/src/player_pc.c:342
        se(5)
      else
        local entry = items[PcMenu.itemCursor]
        local isKey = ItemsData.pocketOf(entry.id) == "KEY_ITEMS"
        if isKey then
          PcMenu._status = Strings("That's much too important to deposit!")
          PcMenu._prevMode = "deposit_item"
          PcMenu.mode = "msg"
          se(5) -- pokefirered/src/item_menu.c:1983
        elseif (entry.qty or 1) > 1 then
          PcMenu.mode = "deposit_qty"
          PcMenu.itemQty = 1
          PcMenu._pendingItem = entry
          PcMenu._status = Strings("How many to deposit?")
        else
          local ok, err = Storage.depositItem(PcMenu._session, PcMenu.selectedPocket, PcMenu.itemCursor, 1)
          if ok then
            show_msg(Strings("Stored 1 %s.", ItemsData.displayName(entry.id)),
              "item_storage", Strings(PcMenu.ITEM_STORAGE_ACTIONS[2].desc), 2)
            se(246)
          else
            PcMenu._status = Strings("The PC is full.")
            PcMenu._prevMode = "deposit_item"
            PcMenu.mode = "msg"
            se(5) -- pokefirered/src/item_menu.c:1983
          end
        end
      end
    elseif input:wasPressed("b") then
      open_item_storage(2)
      se(5)
    end
    return
  end

  -- Deposit Quantity selection
  if PcMenu.mode == "deposit_qty" then
    local entry = PcMenu._pendingItem
    local maxQ = entry and entry.qty or 1

    if input:wasPressed("up") then
      PcMenu.itemQty = (PcMenu.itemQty % maxQ) + 1
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.itemQty = ((PcMenu.itemQty - 2) % maxQ) + 1
      se(5)
    elseif input:wasPressed("right") then
      PcMenu.itemQty = math.min(maxQ, PcMenu.itemQty + 10)
      se(5)
    elseif input:wasPressed("left") then
      PcMenu.itemQty = math.max(1, PcMenu.itemQty - 10)
      se(5)
    elseif input:wasPressed("a") then
      local ok, err = Storage.depositItem(PcMenu._session, PcMenu.selectedPocket, PcMenu.itemCursor, PcMenu.itemQty)
      if ok then
        show_msg(Strings("Stored %d %s.", PcMenu.itemQty, ItemsData.displayName(entry.id)),
          "item_storage", Strings(PcMenu.ITEM_STORAGE_ACTIONS[2].desc), 2)
        se(246)
      else
        PcMenu._status = Strings("The PC is full.")
        PcMenu._prevMode = "deposit_item"
        PcMenu.mode = "msg"
        se(5) -- pokefirered/src/item_menu.c:1983
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "deposit_item"
      PcMenu._status = Strings("What do you want to deposit?")
      se(5)
    end
    return
  end

end

function PcMenu.draw()
  if not PcMenu.open then return end

  -- Root Menu Box
  if PcMenu.mode == "root" then
    local entries = PcMenu._rootEntries()
    Window.stdFrame(Window.template(1, 1, 14, 10))
    for i, e in ipairs(entries) do
      local yPx = 10 + (i - 1) * 16
      if i == PcMenu.cursor then Window.cursorPx(12, yPx) end
      Window.printPx(e.label, 20, yPx)
    end

    -- Bottom Dialogue
    Window.dialogueFrame()
    if PcMenu._status then
      local lines = {}
      for line in tostring(PcMenu._status):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
      end
      if #lines > 0 then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
      if #lines > 1 then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
    end
    return
  end

  -- Storage Submenu Box (WITHDRAW, DEPOSIT, MOVE, MOVE ITEMS, SEE YA!)
  if PcMenu.mode == "storage_menu" then
    local storageOptions = {
      "WITHDRAW POKéMON",
      "DEPOSIT POKéMON",
      "MOVE POKéMON",
      "MOVE ITEMS",
      "SEE YA!",
    }
    Window.stdFrame(Window.template(1, 1, 16, 10))
    for i, opt in ipairs(storageOptions) do
      local yPx = 10 + (i - 1) * 16
      if i == PcMenu.cursor then Window.cursorPx(12, yPx) end
      Window.printPx(Strings(opt), 20, yPx)
    end

    -- Bottom Dialogue
    Window.dialogueFrame()
    if PcMenu._status then
      local lines = {}
      for line in tostring(PcMenu._status):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
      end
      if #lines > 0 then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
      if #lines > 1 then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
    end
    return
  end

  -- pokefirered/src/player_pc.c:112
  if PcMenu.mode == "player_pc" or PcMenu.mode == "item_storage" then
    local top = PcMenu.mode == "player_pc"
    local actions = top and PcMenu.TOP_ACTIONS or PcMenu.ITEM_STORAGE_ACTIONS
    Window.stdFrame(Window.template(1, 1, top and 13 or 14, 6))
    for i, e in ipairs(actions) do
      local yPx = 10 + (i - 1) * 16
      if i == PcMenu.cursor then Window.cursorPx(12, yPx) end
      Window.printPx(Strings(e.label), 20, yPx)
    end
    draw_status_lines()
    return
  end

  -- Item List (Withdraw / Deposit)
  if PcMenu.mode == "withdraw_item" or PcMenu.mode == "deposit_item" then
    local items
    if PcMenu.mode == "deposit_item" then
      local bag = PcMenu._session and PcMenu._session.bag
      items = bag and Bag.listPocket(bag, PcMenu.selectedPocket) or {}
      -- Header showing active pocket
      Window.stdFrame(Window.template(1, 1, 12, 2))
      Window.printPx(PcMenu.selectedPocket, 12, 9, { small = true })
    else
      local storage = Storage.ensure(PcMenu._session)
      items = storage.items or {}
      Window.stdFrame(Window.template(1, 1, 12, 2))
      Window.printPx(Strings("PC ITEMS"), 12, 9, { small = true })
    end

    -- Main item list window
    Window.stdFrame(Window.template(1, 4, 28, 10))
    for vis = 1, VISIBLE_ITEMS do
      local idx = PcMenu.itemScroll + vis
      if idx > #items + 1 then break end
      local yPx = 34 + (vis - 1) * 12
      if idx == PcMenu.itemCursor then Window.cursorPx(10, yPx) end
      if idx > #items then
        Window.printPx(Strings("CANCEL"), 18, yPx)
      else
        local entry = items[idx]
        local nameStr = ItemsData.displayName(entry.id) or Strings("ITEM %s", tostring(entry.id))
        Window.printPx(nameStr, 18, yPx)
        local qStr = string.format("×%02d", entry.qty or 1)
        Window.printPx(qStr, 190, yPx)
      end
    end

    -- Bottom Dialogue
    Window.dialogueFrame()
    if PcMenu._status then
      Window.printPx(PcMenu._status, 16, 120)
    end
    return
  end

  -- Quantity Selection (Withdraw / Deposit)
  if PcMenu.mode == "withdraw_qty" or PcMenu.mode == "deposit_qty" then
    Window.stdFrame(Window.template(17, 8, 12, 4))
    love.graphics.setColor(220 / 255, 60 / 255, 30 / 255, 1)
    Window.printPx("▲", 152, 60)
    Window.printPx("▼", 152, 92)
    love.graphics.setColor(1, 1, 1, 1)
    local qStr = string.format("×%02d", PcMenu.itemQty)
    Window.printPx(qStr, 142, 74, { small = true })

    Window.dialogueFrame()
    if PcMenu._status then Window.printPx(PcMenu._status, 16, 120) end
    return
  end

  -- Plain Message Box
  if PcMenu.mode == "msg" then
    Window.dialogueFrame()
    if PcMenu._status then Window.printPx(PcMenu._status, 16, 120) end
    return
  end
end

return PcMenu
