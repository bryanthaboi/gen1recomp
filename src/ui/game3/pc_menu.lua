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
local Storage = require("src.core.game3.storage")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")

local PcMenu = {}

PcMenu.open = false
PcMenu.mode = "root"
PcMenu.cursor = 1
PcMenu.yesNoCursor = 2

local function rom_entry(id, labelKey, descKey)
  local e = RomText.lazy({ label = labelKey, desc = descKey })
  e.id = id
  return e
end

-- pokefirered/src/player_pc.c:85
PcMenu.TOP_ACTIONS = {
  rom_entry("item_storage", "sMenuActions_TopMenu[0]"),
  rom_entry("mailbox", "sMenuActions_TopMenu[1]"),
  rom_entry("turn_off", "sMenuActions_TopMenu[2]"),
}

-- pokefirered/src/player_pc.c:94
PcMenu.ITEM_STORAGE_ACTIONS = {
  rom_entry("withdraw", "sMenuActions_ItemPc[0]", "sItemStorageActionDescriptionPtrs[0]"),
  rom_entry("deposit", "sMenuActions_ItemPc[1]", "sItemStorageActionDescriptionPtrs[1]"),
  rom_entry("cancel", "sMenuActions_ItemPc[2]", "sItemStorageActionDescriptionPtrs[2]"),
}

local TEXT = RomText.lazy({
  WHAT_TO_DO = "gText_WhatWouldYouLikeToDo", -- pokefirered/src/player_pc.c:160
  NO_ITEMS = "gText_ThereAreNoItems", -- pokefirered/src/player_pc.c:367
  NO_MAIL = "gText_TheresNoMailHere", -- pokefirered/src/player_pc.c:232
  ACCESS_WHICH_PC = "Text_AccessWhichPC", -- data/scripts/pc.inc:21
})

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local FLAG_SYS_NOT_SOMEONES_PC = 0x834 -- pokefirered/include/constants/flags.h:1386
local FLAG_SYS_POKEDEX_GET = 0x829 -- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_GAME_CLEAR = 0x82C -- pokefirered/include/constants/flags.h:1378

local function script_store(session)
  local Space = package.loaded["src.core.game3.scripting.space"]
  return (Space and Space.store) or (session and session.store) or session
end

-- pokefirered/src/script_menu.c:1027
local function someone_or_bill_name(session)
  local Flags = require("src.core.game3.scripting.flags")
  local isBill = Flags.getFlag(script_store(session), nil, FLAG_SYS_NOT_SOMEONES_PC)
  return isBill and RomText.plain("gText_BillSPc") or RomText.plain("gText_SomeoneSPc")
end
PcMenu.storageLabel = someone_or_bill_name

-- pokefirered/src/script_menu.c:1031
local function player_pc_name(session)
  return RomText.plain("gText_SPc", { playerName = session and (session.name or session.playerName) })
end

-- pokefirered/src/script_menu.c:1006
function PcMenu._rootEntries()
  local who = someone_or_bill_name(PcMenu._session)
  local player = player_pc_name(PcMenu._session)
  local Flags = require("src.core.game3.scripting.flags")
  local store = script_store(PcMenu._session)
  local clear = Flags.getFlag(store, nil, FLAG_SYS_GAME_CLEAR)
  local dex = clear or Flags.getFlag(store, nil, FLAG_SYS_POKEDEX_GET)
  local key = (Strings.active() and "t" or "e") .. "\0" .. who .. "\0" .. player
    .. "\0" .. (dex and "d" or "") .. (clear and "c" or "")
  if PcMenu._rootKey ~= key then
    PcMenu._rootKey = key
    local rows = {
      { id = "storage", label = who },
      { id = "player", label = player },
    }
    if dex then rows[#rows + 1] = { id = "oak", label = RomText.plain("gText_ProfOakSPc") } end
    if clear then rows[#rows + 1] = { id = "hall", label = RomText.plain("gText_HallOfFame_2") } end
    rows[#rows + 1] = { id = "quit", label = RomText.plain("gText_LogOff") }
    PcMenu._rootRows = rows
  end
  return PcMenu._rootRows
end

function PcMenu.show(opts)
  opts = opts or {}
  PcMenu.open = true
  PcMenu._session = opts.session
  PcMenu._onClose = opts.onClose
  PcMenu._closeOnExit = opts.closeOnExit == true
  PcMenu._silentClose = opts.silentClose == true
  PcMenu._select = opts.startMode == "select"
  PcMenu._result = nil
  PcMenu.cursor = 1
  PcMenu._prevStatus = nil
  PcMenu._prevCursor = nil
  Storage.ensure(PcMenu._session)
  if opts.startMode == "player_pc" then
    PcMenu.mode = "player_pc"
    PcMenu._status = TEXT.WHAT_TO_DO -- pokefirered/src/player_pc.c:160
  elseif opts.startMode == "storage" then
    PcMenu.mode = "storage_menu"
    PcMenu.storageCursor = 1
    PcMenu._status = PcMenu._storageOptions()[1].desc
  elseif PcMenu._select then
    PcMenu.mode = "root"
    if opts.prompt then PcMenu._lastPrompt = opts.prompt end
    PcMenu._status = PcMenu._lastPrompt
  else
    PcMenu.mode = "root"
    PcMenu._status = TEXT.ACCESS_WHICH_PC
  end
  Stack.push("pc_menu", PcMenu, { hideBelow = false })
end

function PcMenu.close(result)
  PcMenu.open = false
  Stack.pop("pc_menu")
  if not PcMenu._silentClose then se(3) end
  PcMenu._result = result
  local cb = PcMenu._onClose
  PcMenu._onClose = nil
  if cb then cb(result) end
end

-- pokefirered/src/script_menu.c:831
local SCR_MENU_CANCEL = 127
local function return_row(index)
  PcMenu._silentClose = true
  PcMenu.close(index)
end

function PcMenu.isOpen()
  return PcMenu.open
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
  PcMenu._status = PcMenu.ITEM_STORAGE_ACTIONS[cursor].desc
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

function PcMenu._storageOptions()
  return {
    { id = "withdraw", label = RomText.plain("gText_WithdrawPokemon"), desc = RomText.plain("gText_WithdrawMonDescription") },
    { id = "deposit", label = RomText.plain("gText_DepositPokemon"), desc = RomText.plain("gText_DepositMonDescription") },
    { id = "move", label = RomText.plain("gText_MovePokemon"), desc = RomText.plain("gText_MoveMonDescription") },
    { id = "move_items", label = RomText.plain("gText_MoveItems"), desc = RomText.plain("gText_MoveItemsDescription") },
    { id = "quit", label = RomText.plain("gText_SeeYa"), desc = RomText.plain("gText_SeeYaDescription") },
  }
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
  local STORAGE_OPTIONS = PcMenu._storageOptions()

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
      if PcMenu._select or choice.id == "oak" or choice.id == "hall" then
        se(5) -- pokefirered/src/menu.c:347
        return_row(PcMenu.cursor - 1)
      elseif choice.id == "quit" then
        se(5) -- pokefirered/src/menu.c:347
        PcMenu.close()
      elseif choice.id == "storage" then
        se(5)
        se(2) -- data/scripts/pc.inc:47
        PcMenu.mode = "storage_menu"
        PcMenu.storageCursor = PcMenu.storageCursor or 1
        PcMenu.cursor = PcMenu.storageCursor
        PcMenu._status = STORAGE_OPTIONS[PcMenu.cursor].desc
      elseif choice.id == "player" then
        se(5)
        se(2) -- data/scripts/pc.inc:39
        PcMenu.mode = "player_pc"
        PcMenu.cursor = 1
        PcMenu._status = RomText.plain("gText_WhatWouldYouLikeToDo")
      end
    elseif input:wasPressed("b") then
      se(5) -- pokefirered/src/script_menu.c:831
      if PcMenu._select then
        return_row(SCR_MENU_CANCEL)
      else
        PcMenu.close()
      end
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
      if choice.id == "quit" and PcMenu._closeOnExit then
        se(5)
        PcMenu.close()
      elseif choice.id == "quit" then
        PcMenu.mode = "root"
        PcMenu.cursor = 1
        PcMenu._status = TEXT.ACCESS_WHICH_PC
        se(5)
      elseif choice.id == "withdraw" then
        local party = (PcMenu._session and PcMenu._session.party) or {}
        if #party >= 6 then
          PcMenu._status = RomText.plain("gText_PartyFull")
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
          PcMenu._status = RomText.plain("gText_JustOnePkmn")
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
    elseif input:wasPressed("b") and PcMenu._closeOnExit then
      se(5)
      PcMenu.close()
    elseif input:wasPressed("b") then
      PcMenu.mode = "root"
      PcMenu.cursor = 1
      PcMenu._status = TEXT.ACCESS_WHICH_PC
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
        show_msg(TEXT.NO_MAIL, "player_pc", TEXT.WHAT_TO_DO, 1) -- pokefirered/src/player_pc.c:227
      elseif PcMenu._closeOnExit then
        PcMenu.close() -- pokefirered/src/player_pc.c:257
      else
        PcMenu.mode = "root"
        PcMenu.cursor = 2
        PcMenu._status = TEXT.ACCESS_WHICH_PC
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
        PcMenu._status = actions[PcMenu.cursor].desc
        se(5)
      end
    elseif input:wasPressed("down") then
      if PcMenu.cursor < #actions then
        PcMenu.cursor = PcMenu.cursor + 1
        PcMenu._status = actions[PcMenu.cursor].desc
        se(5)
      end
    elseif input:wasPressed("a") or input:wasPressed("b") then
      se(5)
      local id = input:wasPressed("a") and actions[PcMenu.cursor].id or "cancel"
      if id == "withdraw" then
        local storage = Storage.ensure(PcMenu._session)
        if #storage.items < 1 then
          show_msg(TEXT.NO_ITEMS, "item_storage", actions[1].desc, 1) -- pokefirered/src/player_pc.c:352
        else
          -- pokefirered/src/player_pc.c:378 Task_WithdrawItem_WaitFadeAndGoToItemStorage
          PcMenu.mode = "item_pc"
          require("src.ui.game3.item_pc").show({
            session = PcMenu._session,
            onClose = function() open_item_storage(1) end,
          })
        end
      elseif id == "deposit" then
        -- pokefirered/src/player_pc.c:319 Task_DepositItem_WaitFadeAndGoToBag
        PcMenu.mode = "item_pc"
        local session = PcMenu._session
        require("src.ui.game3.bag_menu").show(session and session.bag, {
          session = session,
          location = "itempc",
          pocket = "ITEMS",
          onClose = function() open_item_storage(2) end,
        })
      else
        PcMenu.mode = "player_pc" -- pokefirered/src/player_pc.c:399
        PcMenu.cursor = 1
        PcMenu._status = TEXT.WHAT_TO_DO
      end
    end
    return
  end

end

function PcMenu.draw()
  if not PcMenu.open then return end

  -- Root Menu Box
  if PcMenu.mode == "root" then
    local entries = PcMenu._rootEntries()
    Window.stdFrame(Window.template(1, 1, 14, #entries * 2))
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
    Window.stdFrame(Window.template(1, 1, 16, 10))
    for i, opt in ipairs(PcMenu._storageOptions()) do
      local yPx = 10 + (i - 1) * 16
      if i == PcMenu.cursor then Window.cursorPx(12, yPx) end
      Window.printPx(opt.label, 20, yPx)
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
      Window.printPx(e.label, 20, yPx)
    end
    draw_status_lines()
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
