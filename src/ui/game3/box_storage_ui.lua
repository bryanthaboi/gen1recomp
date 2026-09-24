-- FRLG Pokémon Storage System UI (pret src/pokemon_storage_system.c & User Image 2).
--
-- Layout:
-- 1. Left Data Panel: ~~~ PKMN DATA ~~~ header, TV monitor with cyan scanlines & front sprite,
--    and bottom stats/markings card.
-- 2. Top Bar: PARTY POKéMON button (green) and CLOSE BOX button (cyan).
-- 3. Box Header: ◀ [ Tree BOX 1 Tree ] ▶
-- 4. 6×5 Box Grid: 30 slots (420 capacity across 14 boxes) with 2-frame mini-icon hover bounce.
-- 5. Hand Cursor with authentic dark oval drop shadow.

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local Storage = require("src.core.game3.storage")
local PcChrome = require("src.ui.game3.pc_chrome")
local ReleaseSeq = require("src.ui.game3.release_seq")
local SummaryMenu = require("src.ui.game3.summary_menu")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")

local BoxStorageUI = {}

-- pokefirered/src/pokemon_storage_system_data.c:2027
local MENU_TEXT = {
  CANCEL = 0, STORE = 1, WITHDRAW = 2, MOVE = 3, SUMMARY = 6, RELEASE = 7,
  ["SWITCH BOX"] = 9, WALLPAPER = 10, TAKE = 12,
}
local MENU_TEXT_FOREST = 22

local function menu_text(act)
  return RomText.at("sMenuTexts", (assert(MENU_TEXT[act], act)))
end

BoxStorageUI.open = false
BoxStorageUI.mode = "browse" -- browse | action_menu | box_menu | pick_box | pick_wallpaper | party_drawer | message
BoxStorageUI.subMode = "move" -- withdraw | deposit | move | move_items

-- Grid cursor:
-- 1..30 = 6 cols × 5 rows in current box
-- 0 = Box Title Header
-- -10 = PARTY POKéMON button
-- -20 = CLOSE BOX button
-- -1..-6 = Party Drawer slots 1..6 (when party drawer is open)
BoxStorageUI.cursorSlot = 1
BoxStorageUI.holdingMon = nil
BoxStorageUI.holdingSource = nil -- { loc = "box"|"party", boxId = 1, slot = 1 }

BoxStorageUI.actionCursor = 1
BoxStorageUI.boxMenuCursor = 1
BoxStorageUI.wallpaperCursor = 1
BoxStorageUI.partyCursor = 1

BoxStorageUI.hoverTimer = 0
BoxStorageUI.hoverFrame = 0

-- Grid positioning constants (6 cols × 5 rows inside 154×118 wallpaper at X: 80, Y: 16)
local GRID_ORIGIN_X = 84
local GRID_ORIGIN_Y = 28
local COL_W = 24
local ROW_H = 24

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

-- pokefirered/include/constants/vars.h:105
local VAR_PC_BOX_TO_SEND_MON = 0x4037
-- pokefirered/include/constants/flags.h:1401
local FLAG_SHOWN_BOX_WAS_FULL_MESSAGE = 0x843

local function script_store(session)
  local Space = package.loaded["src.core.game3.scripting.space"]
  return (Space and Space.store) or (session and session.store) or nil
end

-- pokefirered/src/pokemon_storage_system_tasks.c:2763
local function update_box_to_send_mons()
  local storage = Storage.ensure(BoxStorageUI._session)
  if not storage then return end
  local cur = (tonumber(storage.currentBox) or 1) - 1
  if BoxStorageUI._lastUsedBox == cur then return end
  local Flags = require("src.core.game3.scripting.flags")
  local store = script_store(BoxStorageUI._session)
  Flags.setFlag(store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, false)
  Flags.setVar(store, nil, VAR_PC_BOX_TO_SEND_MON, cur)
  BoxStorageUI._lastUsedBox = cur
end

local function current_box_data()
  local storage = Storage.ensure(BoxStorageUI._session)
  if not storage then return nil, nil end
  local bId = storage.currentBox or 1
  return storage.boxes[bId], bId
end

local function mon_at_cursor()
  local session = BoxStorageUI._session
  local storage = Storage.ensure(session)
  if BoxStorageUI.mode == "action_menu" and BoxStorageUI._actionTarget then
    return BoxStorageUI._actionTarget.mon, BoxStorageUI._actionTarget.loc, BoxStorageUI._actionTarget.boxId, BoxStorageUI._actionTarget.slot
  elseif BoxStorageUI.mode == "party_drawer" or (BoxStorageUI.drawerOpen and BoxStorageUI._actionSource == "party") then
    local pIdx = BoxStorageUI.partyCursor or 1
    if pIdx < 1 or pIdx > 6 then return nil, "party", nil, pIdx end
    local isPickedUp = (BoxStorageUI.holdingMon and BoxStorageUI.holdingSource
      and BoxStorageUI.holdingSource.loc == "party"
      and BoxStorageUI.holdingSource.slot == pIdx)
    if isPickedUp then
      return nil, "party", nil, pIdx
    end
    return session and session.party and session.party[pIdx], "party", nil, pIdx
  elseif BoxStorageUI.cursorSlot >= 1 and BoxStorageUI.cursorSlot <= 30 then
    if not storage then return nil, "box", nil, BoxStorageUI.cursorSlot end
    local box = storage.boxes[storage.currentBox or 1]
    return box and box.mons[BoxStorageUI.cursorSlot], "box", storage.currentBox, BoxStorageUI.cursorSlot
  elseif BoxStorageUI.cursorSlot <= -1 and BoxStorageUI.cursorSlot >= -6 then
    local pIdx = -BoxStorageUI.cursorSlot
    return session and session.party and session.party[pIdx], "party", nil, pIdx
  end
  return nil, nil, nil, nil
end

function BoxStorageUI.show(opts)
  opts = opts or {}
  BoxStorageUI.open = true
  BoxStorageUI._session = opts.session
  BoxStorageUI._onClose = opts.onClose
  BoxStorageUI.mode = "browse"
  BoxStorageUI.subMode = opts.subMode or "move"
  BoxStorageUI.cursorSlot = 1
  BoxStorageUI._prevPartySlot = nil
  BoxStorageUI.holdingMon = nil
  BoxStorageUI.holdingSource = nil
  BoxStorageUI.hoverTimer = 0
  BoxStorageUI.hoverFrame = 0
  BoxStorageUI.partyCursor = 1
  BoxStorageUI.drawerOpen = false
  BoxStorageUI._actionSource = nil
  BoxStorageUI._actionTarget = nil
  local storage = Storage.ensure(BoxStorageUI._session)
  -- pokefirered/src/pokemon_storage_system_tasks.c:426
  BoxStorageUI._lastUsedBox = storage and ((tonumber(storage.currentBox) or 1) - 1) or nil

  if BoxStorageUI.subMode == "deposit" then
    -- In deposit submode, start directly in party drawer mode
    BoxStorageUI.mode = "party_drawer"
    BoxStorageUI.drawerOpen = true
    BoxStorageUI.partyCursor = 1
  end

  Stack.push("box_storage", BoxStorageUI, { hideBelow = true, fullscreen = true })
  se(5)
end

function BoxStorageUI.close()
  -- pokefirered/src/pokemon_storage_system_tasks.c:1979
  update_box_to_send_mons()
  BoxStorageUI.open = false
  BoxStorageUI.holdingMon = nil
  BoxStorageUI.holdingSource = nil
  BoxStorageUI.drawerOpen = false
  BoxStorageUI._actionSource = nil
  BoxStorageUI._actionTarget = nil
  Stack.pop("box_storage")
  local cb = BoxStorageUI._onClose
  BoxStorageUI._onClose = nil
  if cb then cb() end
end

function BoxStorageUI.isOpen()
  return BoxStorageUI.open
end

function BoxStorageUI.update(dt)
  if not BoxStorageUI.open then return end

  -- Release sequence animation update
  if ReleaseSeq.isActive() then
    ReleaseSeq.update(dt)
    return
  end

  -- Hover Bounce animation: toggles frame 0 and frame 1 every 0.14s
  BoxStorageUI.hoverTimer = BoxStorageUI.hoverTimer + (dt or (1 / 60))
  if BoxStorageUI.hoverTimer >= 0.14 then
    BoxStorageUI.hoverTimer = 0
    BoxStorageUI.hoverFrame = (BoxStorageUI.hoverFrame == 0) and 1 or 0
  end
end

local function switch_box(delta)
  local storage = Storage.ensure(BoxStorageUI._session)
  local cur = storage.currentBox or 1
  storage.currentBox = ((cur - 1 + delta) % Storage.TOTAL_BOXES_COUNT) + 1
  se(5)
end

local function open_summary_for_cursor()
  local returnMode = (BoxStorageUI._actionSource == "party" or BoxStorageUI.drawerOpen) and "party_drawer" or "browse"
  local mon, loc, bId, sId = mon_at_cursor()
  if not mon then return end

  if loc == "box" then
    local box = current_box_data()
    local boxMons = {}
    local startIndex = 1
    for s = 1, Storage.IN_BOX_COUNT do
      local m = box and box.mons[s]
      if m then
        boxMons[#boxMons + 1] = m
        if s == sId then
          startIndex = #boxMons
        end
      end
    end
    if #boxMons > 0 then
      SummaryMenu.openMenu(boxMons, startIndex, {
        session = BoxStorageUI._session,
        context = "box",
        onClose = function()
          BoxStorageUI.mode = returnMode
          se(5)
        end,
      })
    end
  elseif loc == "party" then
    local partyMons = {}
    local startIndex = 1
    local party = (BoxStorageUI._session and BoxStorageUI._session.party) or {}
    for p = 1, 6 do
      local m = party[p]
      if m then
        partyMons[#partyMons + 1] = m
        if p == sId then
          startIndex = #partyMons
        end
      end
    end
    SummaryMenu.openMenu(partyMons, startIndex, {
      session = BoxStorageUI._session,
      context = "party",
      onClose = function()
        BoxStorageUI.mode = returnMode
        se(5)
      end,
    })
  end
end

function BoxStorageUI.handleInput(input)
  if not BoxStorageUI.open then return end

  if ReleaseSeq.isActive() then
    ReleaseSeq.handleInput(input)
    return
  end

  -- Message dismiss
  if BoxStorageUI.mode == "message" then
    if input:wasPressed("a") or input:wasPressed("b") then
      local returnMode = (BoxStorageUI._actionSource == "party" or BoxStorageUI.drawerOpen) and "party_drawer" or "browse"
      BoxStorageUI.mode = returnMode
      BoxStorageUI._status = nil
      se(5)
    end
    return
  end

  -- Party Drawer Selection Mode
  if BoxStorageUI.mode == "party_drawer" then
    local party = (BoxStorageUI._session and BoxStorageUI._session.party) or {}
    BoxStorageUI.partyCursor = BoxStorageUI.partyCursor or 1
    BoxStorageUI.drawerOpen = true

    if input:wasPressed("up") then
      BoxStorageUI.partyCursor = BoxStorageUI.partyCursor - 1
      if BoxStorageUI.partyCursor < 1 then BoxStorageUI.partyCursor = 7 end
      if BoxStorageUI.partyCursor >= 2 and BoxStorageUI.partyCursor <= 6 then
        BoxStorageUI._prevPartySlot = BoxStorageUI.partyCursor
      end
      se(5)
    elseif input:wasPressed("down") then
      BoxStorageUI.partyCursor = BoxStorageUI.partyCursor + 1
      if BoxStorageUI.partyCursor > 7 then BoxStorageUI.partyCursor = 1 end
      if BoxStorageUI.partyCursor >= 2 and BoxStorageUI.partyCursor <= 6 then
        BoxStorageUI._prevPartySlot = BoxStorageUI.partyCursor
      end
      se(5)
    elseif input:wasPressed("left") then
      if BoxStorageUI.partyCursor ~= 1 then
        BoxStorageUI._prevPartySlot = BoxStorageUI.partyCursor
        BoxStorageUI.partyCursor = 1
        se(5)
      end
    elseif input:wasPressed("right") then
      if BoxStorageUI.partyCursor == 1 then
        BoxStorageUI.partyCursor = BoxStorageUI._prevPartySlot or 2
        se(5)
      else
        -- Exit party drawer to Box 1 slot 1
        BoxStorageUI.mode = "browse"
        BoxStorageUI.drawerOpen = false
        BoxStorageUI.cursorSlot = 1
        se(5)
      end
    elseif input:wasPressed("b") then
      if BoxStorageUI.subMode == "deposit" and BoxStorageUI.holdingMon == nil then
        BoxStorageUI.close()
      else
        BoxStorageUI.mode = "browse"
        BoxStorageUI.drawerOpen = false
        BoxStorageUI.cursorSlot = 1
        se(5)
      end
    elseif input:wasPressed("a") then
      if BoxStorageUI.partyCursor == 7 then -- CANCEL button
        if BoxStorageUI.subMode == "deposit" and BoxStorageUI.holdingMon == nil then
          BoxStorageUI.close()
        else
          BoxStorageUI.mode = "browse"
          BoxStorageUI.drawerOpen = false
          BoxStorageUI.cursorSlot = 1
          se(5)
        end
      else
        local pIdx = BoxStorageUI.partyCursor
        local mon = party[pIdx]

        -- If holding a mon (Move mode)
        if BoxStorageUI.holdingMon then
          if BoxStorageUI.holdingSource and BoxStorageUI.holdingSource.loc == "party" and BoxStorageUI.holdingSource.slot == pIdx then
            -- Place mon back into same slot
            BoxStorageUI.holdingMon = nil
            BoxStorageUI.holdingSource = nil
            se(246)
          elseif BoxStorageUI.holdingSource and BoxStorageUI.holdingSource.loc == "party" then
            -- Swap between two party slots
            local srcIdx = BoxStorageUI.holdingSource.slot
            local targetMon = party[pIdx]
            party[srcIdx] = targetMon
            party[pIdx] = BoxStorageUI.holdingMon
            BoxStorageUI.holdingMon = nil
            BoxStorageUI.holdingSource = nil
            se(246)
          elseif BoxStorageUI.holdingSource and BoxStorageUI.holdingSource.loc == "box" then
            -- Placing/Swapping from box into party
            local srcBox = BoxStorageUI.holdingSource.boxId
            local srcSlot = BoxStorageUI.holdingSource.slot
            local storage = Storage.ensure(BoxStorageUI._session)
            local box = storage.boxes[srcBox]
            if mon then
              -- Swap box mon with party mon
              box.mons[srcSlot] = mon
              party[pIdx] = BoxStorageUI.holdingMon
              BoxStorageUI.holdingMon = nil
              BoxStorageUI.holdingSource = nil
              se(246)
            else
              -- Place into empty party slot
              party[pIdx] = BoxStorageUI.holdingMon
              box.mons[srcSlot] = nil
              BoxStorageUI.holdingMon = nil
              BoxStorageUI.holdingSource = nil
              se(246)
            end
          end
        elseif mon then
          BoxStorageUI._actionSource = "party"
          BoxStorageUI._actionTarget = { mon = mon, loc = "party", boxId = nil, slot = pIdx }
          if BoxStorageUI.subMode == "deposit" then
            BoxStorageUI._activeActions = { "STORE", "SUMMARY", "CANCEL" }
          else
            BoxStorageUI._activeActions = { "STORE", "SUMMARY", "MOVE", "CANCEL" }
          end
          BoxStorageUI.actionCursor = 1
          BoxStorageUI.mode = "action_menu"
          se(5)
        end
      end
    end
    return
  end

  -- Context Action Menu
  if BoxStorageUI.mode == "action_menu" then
    local actions = BoxStorageUI._activeActions or { "CANCEL" }
    local returnMode = (BoxStorageUI._actionSource == "party" or BoxStorageUI.drawerOpen) and "party_drawer" or "browse"

    if input:wasPressed("up") then
      BoxStorageUI.actionCursor = ((BoxStorageUI.actionCursor - 2) % #actions) + 1
      se(5)
    elseif input:wasPressed("down") then
      BoxStorageUI.actionCursor = (BoxStorageUI.actionCursor % #actions) + 1
      se(5)
    elseif input:wasPressed("a") then
      local choice = actions[BoxStorageUI.actionCursor]
      if choice == "CANCEL" then
        BoxStorageUI.mode = returnMode
        se(5)
      elseif choice == "WITHDRAW" then
        local mon, loc, bId, sId = mon_at_cursor()
        if loc == "box" and mon then
          local ok, err = Storage.withdraw(BoxStorageUI._session, bId, sId)
          if ok then
            BoxStorageUI.mode = returnMode
            se(246)
          else
            BoxStorageUI._status = RomText.plain("gText_YourPartysFull")
            BoxStorageUI.mode = "message"
            se(5) -- pokefirered/src/pokemon_storage_system_tasks.c:992
          end
        end
      elseif choice == "STORE" or choice == "DEPOSIT" then
        local mon, loc, bId, sId = mon_at_cursor()
        if loc == "party" and mon then
          local party = (BoxStorageUI._session and BoxStorageUI._session.party) or {}
          if #party <= 1 then
            BoxStorageUI._status = RomText.plain("gText_JustOnePkmn")
            BoxStorageUI.mode = "message"
            se(26) -- pokefirered/src/pokemon_storage_system_tasks.c:1052
          else
            local ok, b, s = Storage.deposit(BoxStorageUI._session, sId)
            if ok then
              local newParty = (BoxStorageUI._session and BoxStorageUI._session.party) or {}
              if #newParty == 0 then
                BoxStorageUI.drawerOpen = false
                BoxStorageUI.mode = "browse"
                BoxStorageUI.cursorSlot = 1
              else
                BoxStorageUI.partyCursor = math.min(#newParty, BoxStorageUI.partyCursor or 1)
                BoxStorageUI.mode = returnMode
              end
              se(246)
            else
              BoxStorageUI._status = RomText.plain("gText_BoxIsFull2")
              BoxStorageUI.mode = "message"
              se(5) -- pokefirered/src/pokemon_storage_system_tasks.c:1225
            end
          end
        end
      elseif choice == "MOVE" then
        local mon, loc, bId, sId = mon_at_cursor()
        if mon then
          BoxStorageUI.holdingMon = mon
          BoxStorageUI.holdingSource = { loc = loc, boxId = bId, slot = sId }
          BoxStorageUI.mode = returnMode
          se(5)
        end
      elseif choice == "SUMMARY" then
        BoxStorageUI.mode = returnMode
        open_summary_for_cursor()
      elseif choice == "TAKE" then
        local mon = mon_at_cursor()
        if mon then
          local ok, err = Storage.detachHeldItem(BoxStorageUI._session, mon)
          if ok then
            -- pokefirered/src/pokemon_storage_system_tasks.c:1501
            BoxStorageUI._status = RomText.plain("gText_PlacedItemInBag")
            BoxStorageUI.mode = "message"
            se(246)
          elseif err == "bag_full" then
            BoxStorageUI._status = RomText.plain("gText_BagIsFull2")
            BoxStorageUI.mode = "message"
            se(26) -- pokefirered/src/pokemon_storage_system_tasks.c:1487
          else
            BoxStorageUI._status = Strings("This POKéMON isn't holding anything.")
            BoxStorageUI.mode = "message"
            se(5) -- pokefirered/src/pokemon_storage_system_tasks.c:1493
          end
        end
      elseif choice == "RELEASE" then
        local mon, loc, bId, sId = mon_at_cursor()
        if loc == "box" and mon then
          local col = (sId - 1) % 6
          local row = math.floor((sId - 1) / 6)
          local px = GRID_ORIGIN_X + col * COL_W + 12
          local py = GRID_ORIGIN_Y + row * ROW_H + 12
          BoxStorageUI.mode = "browse"
          BoxStorageUI.drawerOpen = false
          ReleaseSeq.start({
            session = BoxStorageUI._session,
            mon = mon,
            boxId = bId,
            slotIdx = sId,
            startX = px,
            startY = py,
            onComplete = function(released)
              if released then
                se(246)
              end
            end,
          })
        end
      end
    elseif input:wasPressed("b") then
      BoxStorageUI.mode = returnMode
      se(5)
    end
    return
  end

  -- Box Header Menu (Switch Box, Wallpaper, Cancel)
  if BoxStorageUI.mode == "box_menu" then
    local boxActions = { "SWITCH BOX", "WALLPAPER", "CANCEL" }
    if input:wasPressed("up") then
      BoxStorageUI.boxMenuCursor = ((BoxStorageUI.boxMenuCursor - 2) % #boxActions) + 1
      se(5)
    elseif input:wasPressed("down") then
      BoxStorageUI.boxMenuCursor = (BoxStorageUI.boxMenuCursor % #boxActions) + 1
      se(5)
    elseif input:wasPressed("a") then
      local choice = boxActions[BoxStorageUI.boxMenuCursor]
      if choice == "CANCEL" then
        BoxStorageUI.mode = "browse"
        se(5)
      elseif choice == "SWITCH BOX" then
        BoxStorageUI.mode = "pick_box"
        se(5)
      elseif choice == "WALLPAPER" then
        BoxStorageUI.mode = "pick_wallpaper"
        local box = current_box_data()
        BoxStorageUI.wallpaperCursor = box and box.wallpaper or 1
        se(5)
      end
    elseif input:wasPressed("b") then
      BoxStorageUI.mode = "browse"
      se(5)
    end
    return
  end

  -- Pick Wallpaper
  if BoxStorageUI.mode == "pick_wallpaper" then
    if input:wasPressed("up") then
      BoxStorageUI.wallpaperCursor = ((BoxStorageUI.wallpaperCursor - 2) % 16) + 1
      se(5)
    elseif input:wasPressed("down") then
      BoxStorageUI.wallpaperCursor = (BoxStorageUI.wallpaperCursor % 16) + 1
      se(5)
    elseif input:wasPressed("a") then
      local box = current_box_data()
      if box then box.wallpaper = BoxStorageUI.wallpaperCursor end
      BoxStorageUI.mode = "browse"
      se(246)
    elseif input:wasPressed("b") then
      BoxStorageUI.mode = "browse"
      se(5)
    end
    return
  end

  -- Pick Box
  if BoxStorageUI.mode == "pick_box" then
    local storage = Storage.ensure(BoxStorageUI._session)
    if input:wasPressed("up") then
      storage.currentBox = ((storage.currentBox - 2) % Storage.TOTAL_BOXES_COUNT) + 1
      se(5)
    elseif input:wasPressed("down") then
      storage.currentBox = (storage.currentBox % Storage.TOTAL_BOXES_COUNT) + 1
      se(5)
    elseif input:wasPressed("a") or input:wasPressed("b") then
      BoxStorageUI.mode = "browse"
      se(5)
    end
    return
  end

  -- Standard Browse Navigation
  if BoxStorageUI.mode == "browse" then
    -- L / R Triggers cycle boxes
    if input:wasPressed("l") then
      switch_box(-1)
      return
    elseif input:wasPressed("r") then
      switch_box(1)
      return
    end

    -- Top Buttons: PARTY POKéMON (-10) & CLOSE BOX (-20)
    if BoxStorageUI.cursorSlot == -10 then
      if input:wasPressed("right") then
        BoxStorageUI.cursorSlot = -20
        se(5)
      elseif input:wasPressed("down") then
        BoxStorageUI.cursorSlot = 0
        se(5)
      elseif input:wasPressed("a") then
        BoxStorageUI.mode = "party_drawer"
        BoxStorageUI.drawerOpen = true
        BoxStorageUI.partyCursor = 1
        se(5)
      elseif input:wasPressed("b") then
        BoxStorageUI.close()
      end
      return
    elseif BoxStorageUI.cursorSlot == -20 then
      if input:wasPressed("left") then
        BoxStorageUI.cursorSlot = -10
        se(5)
      elseif input:wasPressed("down") then
        BoxStorageUI.cursorSlot = 0
        se(5)
      elseif input:wasPressed("a") then
        BoxStorageUI.close()
      elseif input:wasPressed("b") then
        BoxStorageUI.close()
      end
      return
    end

    -- Box Header slot = 0
    if BoxStorageUI.cursorSlot == 0 then
      if input:wasPressed("left") then
        switch_box(-1)
      elseif input:wasPressed("right") then
        switch_box(1)
      elseif input:wasPressed("up") then
        BoxStorageUI.cursorSlot = -10
        se(5)
      elseif input:wasPressed("down") then
        BoxStorageUI.cursorSlot = 1 -- enter top row of grid
        se(5)
      elseif input:wasPressed("a") then
        BoxStorageUI.mode = "box_menu"
        BoxStorageUI.boxMenuCursor = 1
        se(5)
      elseif input:wasPressed("b") then
        BoxStorageUI.close()
      end
      return
    end

    -- 6×5 Box Grid slots: 1..30
    local slot = BoxStorageUI.cursorSlot
    local col = (slot - 1) % 6 -- 0..5
    local row = math.floor((slot - 1) / 6) -- 0..4

    if input:wasPressed("up") then
      if row > 0 then
        BoxStorageUI.cursorSlot = slot - 6
        se(5)
      else
        BoxStorageUI.cursorSlot = 0 -- Move to Box Header
        se(5)
      end
    elseif input:wasPressed("down") then
      if row < 4 then
        BoxStorageUI.cursorSlot = slot + 6
        se(5)
      end
    elseif input:wasPressed("left") then
      if col > 0 then
        BoxStorageUI.cursorSlot = slot - 1
        se(5)
      else
        -- Wrap to previous box right edge
        switch_box(-1)
        BoxStorageUI.cursorSlot = row * 6 + 6
      end
    elseif input:wasPressed("right") then
      if col < 5 then
        BoxStorageUI.cursorSlot = slot + 1
        se(5)
      else
        -- Wrap to next box left edge
        switch_box(1)
        BoxStorageUI.cursorSlot = row * 6 + 1
      end
    elseif input:wasPressed("a") then
      if BoxStorageUI.holdingMon then
        -- Place/Swap holding mon into box slot
        local src = BoxStorageUI.holdingSource
        local storage = Storage.ensure(BoxStorageUI._session)
        if src.loc == "box" then
          Storage.moveMon(BoxStorageUI._session, "box", src.slot, "box", slot, src.boxId, storage.currentBox)
        elseif src.loc == "party" then
          Storage.moveMon(BoxStorageUI._session, "party", src.slot, "box", slot, nil, storage.currentBox)
        end
        BoxStorageUI.holdingMon = nil
        BoxStorageUI.holdingSource = nil
        se(246)
      else
        local mon, loc, bId, sId = mon_at_cursor()
        if mon then
          BoxStorageUI._actionSource = "box"
          BoxStorageUI._actionTarget = { mon = mon, loc = "box", boxId = bId, slot = slot }
          if BoxStorageUI.subMode == "withdraw" then
            BoxStorageUI._activeActions = { "WITHDRAW", "SUMMARY", "RELEASE", "CANCEL" }
          elseif BoxStorageUI.subMode == "move_items" then
            BoxStorageUI._activeActions = { "TAKE", "SUMMARY", "CANCEL" }
          else
            BoxStorageUI._activeActions = { "MOVE", "SUMMARY", "WITHDRAW", "RELEASE", "CANCEL" }
          end
          BoxStorageUI.actionCursor = 1
          BoxStorageUI.mode = "action_menu"
          se(5)
        end
      end
    elseif input:wasPressed("b") then
      if BoxStorageUI.holdingMon then
        BoxStorageUI.holdingMon = nil
        BoxStorageUI.holdingSource = nil
        se(5)
      else
        BoxStorageUI.close()
      end
    end
  end
end

function BoxStorageUI.draw()
  if not BoxStorageUI.open then return end
  local session = BoxStorageUI._session
  local storage = Storage.ensure(session)
  if not storage then return end
  local box, bId = current_box_data()

  -- 1. Full Salmon / Scrolling Background (BG3)
  PcChrome.drawBackground()

  -- 2. Box Wallpaper (BG2, X: 80, Y: 16)
  PcChrome.drawWallpaper(box and box.wallpaper or 1)

  -- 3. Interface Frame (BG1, X: 0, Y: 0)
  PcChrome.drawInterfaceFrame()

  -- 4. Top Buttons (PARTY POKéMON & CLOSE BOX)
  local activeBtn = nil
  if BoxStorageUI.cursorSlot == -10 then activeBtn = "party"
  elseif BoxStorageUI.cursorSlot == -20 then activeBtn = "close" end
  PcChrome.drawTopButtons(activeBtn)

  -- 5. Box Title Header (◀  BOX 1  ▶)
  PcChrome.drawBoxHeader(box and box.name, bId, BoxStorageUI.cursorSlot == 0)

  -- 6. Left TV Monitor & Info Panel Text/Sprite
  local hoverMon = BoxStorageUI.holdingMon or mon_at_cursor()
  PcChrome.drawLeftDataPanel(hoverMon, BoxStorageUI.hoverFrame)

  -- 7. 30 Mini-Icons in Box Grid (6 cols × 5 rows)
  for s = 1, Storage.IN_BOX_COUNT do
    local isPickedUp = (BoxStorageUI.holdingMon and BoxStorageUI.holdingSource
      and BoxStorageUI.holdingSource.loc == "box"
      and BoxStorageUI.holdingSource.boxId == bId
      and BoxStorageUI.holdingSource.slot == s)

    local mon = (not isPickedUp) and box and box.mons[s]
    if mon then
      local col = (s - 1) % 6
      local row = math.floor((s - 1) / 6)
      local px = GRID_ORIGIN_X + col * COL_W
      local py = GRID_ORIGIN_Y + row * ROW_H

      local isHovered = (BoxStorageUI.cursorSlot == s and BoxStorageUI.mode ~= "party_drawer" and not BoxStorageUI.holdingMon)
      local bounceY = (isHovered and BoxStorageUI.hoverFrame == 1) and -2 or 0
      local f = (isHovered and BoxStorageUI.hoverFrame == 1) and 1 or 0
      local icon = Pokemon.monIcon(mon)

      if icon and icon.image then
        local q = icon.quads and (icon.quads[f] or icon.quads[0])
        love.graphics.setColor(1, 1, 1, 1)
        if q then
          love.graphics.draw(icon.image, q, px, py + bounceY)
        else
          love.graphics.draw(icon.image, px, py + bounceY)
        end
      end

      -- Held Item indicator (small yellow dot/diamond)
      local held = mon.heldItem or mon.item
      if held and held > 0 then
        love.graphics.setColor(240/255, 180/255, 60/255, 1)
        love.graphics.rectangle("fill", px + 22, py + 22 + bounceY, 3, 3)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end
  end

  -- 8. Party Drawer Overlay (if active or drawer open)
  if BoxStorageUI.mode == "party_drawer" or BoxStorageUI.drawerOpen then
    PcChrome.drawPartyDrawer(session.party, BoxStorageUI.partyCursor, BoxStorageUI.hoverFrame, BoxStorageUI.holdingSource)
  end

  -- 9. Draw Hand Cursor & Shadow
  local curX, curY = 100, 32
  local showShadow = false
  local vFlip = false

  if BoxStorageUI.mode == "party_drawer" or (BoxStorageUI.mode == "action_menu" and BoxStorageUI._actionSource == "party") then
    curX, curY = PcChrome.getPartyCursorCoords(BoxStorageUI.partyCursor)
  elseif BoxStorageUI.cursorSlot == -10 then
    curX = 120
    curY = BoxStorageUI.holdingMon and 8 or 14
    vFlip = true
  elseif BoxStorageUI.cursorSlot == -20 then
    curX = 208
    curY = BoxStorageUI.holdingMon and 8 or 14
    vFlip = true
  elseif BoxStorageUI.cursorSlot == 0 then
    curX = 162
    curY = 12
  elseif BoxStorageUI.cursorSlot >= 1 and BoxStorageUI.cursorSlot <= 30 then
    local s = BoxStorageUI.cursorSlot
    local col = (s - 1) % 6
    local row = math.floor((s - 1) / 6)
    curX = col * 24 + 100
    curY = row * 24 + 32
    -- Shadow only shows when hovering over an EMPTY box slot
    local isPickedUp = (BoxStorageUI.holdingMon and BoxStorageUI.holdingSource
      and BoxStorageUI.holdingSource.loc == "box"
      and BoxStorageUI.holdingSource.boxId == bId
      and BoxStorageUI.holdingSource.slot == s)
    local monInSlot = (not isPickedUp) and box and box.mons[s]
    showShadow = (monInSlot == nil)
  end

  local cursorState = BoxStorageUI.holdingMon and "holding" or "idle"
  PcChrome.drawHandCursor(curX, curY, cursorState, showShadow, vFlip)

  -- If holding a mon, draw floating mini-icon under hand cursor
  if BoxStorageUI.holdingMon then
    local hIcon = Pokemon.monIcon(BoxStorageUI.holdingMon)
    if hIcon and hIcon.image then
      local q = hIcon.quads and hIcon.quads[0]
      love.graphics.setColor(1, 1, 1, 1)
      if q then
        love.graphics.draw(hIcon.image, q, curX - 16, curY - 12)
      else
        love.graphics.draw(hIcon.image, curX - 16, curY - 12)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- 10. Context Action Menu Popup
  if BoxStorageUI.mode == "action_menu" then
    local actions = BoxStorageUI._activeActions or { "CANCEL" }
    local th = #actions * 2
    local menuLeft = 13
    local menuTop = 5
    local textLeft = 114

    if BoxStorageUI._actionSource == "party" or BoxStorageUI.drawerOpen then
      menuLeft = 11
      menuTop = 4
      textLeft = 98
    end

    Window.stdFrame(Window.template(menuLeft, menuTop, 10, th))
    for i, act in ipairs(actions) do
      local yPx = (menuTop * 8 + 2) + (i - 1) * 16
      if i == BoxStorageUI.actionCursor then Window.cursorPx(textLeft - 8, yPx) end
      Window.printPx(menu_text(act), textLeft, yPx)
    end
  end

  -- 10. Box Menu Popup
  if BoxStorageUI.mode == "box_menu" then
    local boxActions = { "SWITCH BOX", "WALLPAPER", "CANCEL" }
    Window.stdFrame(Window.template(5, 3, 12, 6))
    for i, act in ipairs(boxActions) do
      local yPx = 26 + (i - 1) * 16
      if i == BoxStorageUI.boxMenuCursor then Window.cursorPx(42, yPx) end
      Window.printPx(menu_text(act), 50, yPx)
    end
  end

  -- 11. Wallpaper Picker Popup
  if BoxStorageUI.mode == "pick_wallpaper" then
    Window.stdFrame(Window.template(5, 2, 14, 10))
    -- pokefirered/src/pokemon_storage_system_tasks.c:279
    Window.printPx(RomText.plain("gText_PickTheWallpaper"), 44, 18, { small = true })
    for i = 1, 4 do
      local wpId = ((BoxStorageUI.wallpaperCursor - 1 + i - 1) % 16) + 1
      local wpName = RomText.at("sMenuTexts", MENU_TEXT_FOREST + wpId - 1)
      local yPx = 34 + (i - 1) * 14
      if i == 1 then Window.cursorPx(44, yPx) end
      Window.printPx(wpName, 52, yPx)
    end
  end

  -- 12. Message Overlay
  if BoxStorageUI.mode == "message" then
    Window.dialogueFrame()
    if BoxStorageUI._status then
      Window.printPx(BoxStorageUI._status, 16, 120)
    end
  end

  -- 13. Release Sequence Rendering
  if ReleaseSeq.isActive() then
    ReleaseSeq.draw()
  end
end

return BoxStorageUI
