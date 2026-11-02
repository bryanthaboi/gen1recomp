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
local RsStorage = require("src.ui.game3.rs.storage_policy")
local RsMarkings = require("src.ui.game3.rs.storage_markings")
local Presentation = require("src.ui.game3.storage_presentation")

local BoxStorageUI = { isMenu = true }
local function is_rs() return RsStorage.matches(BoxStorageUI._session) end
local function storage_text(native, shared)
  return is_rs() and RsStorage.text(native) or RomText.plain(shared)
end
local function box_actions()
  return is_rs() and RsStorage.boxActions() or {"SWITCH BOX", "WALLPAPER", "CANCEL"}
end
local function native_message(text)
  Window.userFrame(Window.template(11, 17, 18, 2))
  Window.printPx(text, 88, 136)
end
local function native_rows(rows, cursor)
  local width = 0
  for _, text in ipairs(rows) do width = math.max(width, math.ceil(FrlgFont.measure(text) / 8)) end
  local left, top = 29 - width, 15 - #rows * 2
  Window.userFrame(Window.template(left, top, width, #rows * 2))
  for i, text in ipairs(rows) do Window.printPx(text, left * 8, (top + (i - 1) * 2) * 8) end
  require("src.ui.game3.rs.menu_cursor").draw(left * 8, (top + (cursor - 1) * 2) * 8, width * 8)
end
local function reject_native(errorName)
  if not errorName then return false end
  BoxStorageUI._status, BoxStorageUI.mode = RsStorage.text(errorName), "message"
  pcall(function() require("src.core.game3.audio").playSe(require("src.core.game3.se_ids").SE_FAILURE) end)
  return true
end

-- pokefirered/src/pokemon_storage_system_data.c:2027
local MENU_TEXT = {
  CANCEL = 0, STORE = 1, WITHDRAW = 2, MOVE = 3, SUMMARY = 6, RELEASE = 7,
  ["SWITCH BOX"] = 9, WALLPAPER = 10, TAKE = 12,
}
local MENU_TEXT_FOREST = 22
-- pokeemerald/src/pokemon_storage_system.c:135
local MENU_TEXT_FOREST_RSE = 23

local function menu_text_forest(session)
  local Profile = require("src.core.game3.profile")
  return Profile.family(session) == "rse" and MENU_TEXT_FOREST_RSE or MENU_TEXT_FOREST
end

local function menu_text(act)
  if is_rs() then return RsStorage.menuText(act) end
  return RomText.at("sMenuTexts", (assert(MENU_TEXT[act], act)))
end

local function wallpaper_count(session)
  if RsStorage.matches(session) then return 16 end
  local count = #PcChrome.wallpaperNames()
  local walda = type(session) == "table" and session.waldaPhrase
  -- pokeemerald/src/pokemon_storage_system.c:4334
  if require("src.core.game3.profile").family(session) == "rse" and type(walda) == "table"
      and walda.unlocked == true and PcChrome.hasFriends() then count = count + 1 end
  return count
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

local function se_id(name)
  return require("src.core.game3.se_ids")[name]
end

local function storage_ids(session)
  local Profile = require("src.core.game3.profile")
  local row = Profile.forSession(session)
  local C = require("src.core.game3.constants").of(row.id)
  local names = row.save.storage
  return names.sendVar and C:require("vars", names.sendVar), names.boxFullFlag and C:require("flags", names.boxFullFlag)
end

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
  local VAR_PC_BOX_TO_SEND_MON, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE = storage_ids(BoxStorageUI._session)
  if FLAG_SHOWN_BOX_WAS_FULL_MESSAGE then Flags.setFlag(store, nil, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, false) end
  if VAR_PC_BOX_TO_SEND_MON then Flags.setVar(store, nil, VAR_PC_BOX_TO_SEND_MON, cur) end
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
    local isPickedUp = (BoxStorageUI.holdingMon == (session and session.party and session.party[pIdx]) and BoxStorageUI.holdingSource
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
  if is_rs() and BoxStorageUI.subMode == "move_items" then BoxStorageUI.subMode = "move" end
  BoxStorageUI._markings = nil
  BoxStorageUI._pendingDeposit, BoxStorageUI._pickBox = nil, nil
  -- pokefirered/src/pokemon_storage_system_tasks.c:481
  BoxStorageUI._depositBox = 1
  BoxStorageUI.cursorSlot = 1
  BoxStorageUI._prevPartySlot = nil
  BoxStorageUI.holdingMon = nil
  BoxStorageUI.holdingSource = nil
  BoxStorageUI._holdingOrigin = nil
  BoxStorageUI.hoverTimer = 0
  BoxStorageUI.hoverFrame = 0
  BoxStorageUI.partyCursor = 1
  BoxStorageUI.drawerOpen = false
  BoxStorageUI._actionSource = nil
  BoxStorageUI._actionTarget = nil
  local storage = Storage.ensure(BoxStorageUI._session)
  -- Repair a party left with gaps by an older build before any slot is indexed.
  if BoxStorageUI._session then Storage.compactParty(BoxStorageUI._session.party) end
  -- pokefirered/src/pokemon_storage_system_tasks.c:426
  BoxStorageUI._lastUsedBox = storage and ((tonumber(storage.currentBox) or 1) - 1) or nil

  if BoxStorageUI.subMode == "deposit" then
    -- In deposit submode, start directly in party drawer mode
    BoxStorageUI.mode = "party_drawer"
    BoxStorageUI.drawerOpen = true
    BoxStorageUI.partyCursor = 1
  end

  Stack.push("box_storage", BoxStorageUI, { hideBelow = true, fullscreen = true })
  local manifest, game = PcChrome.presentationManifest()
  BoxStorageUI._presentation = Presentation.new(game, manifest)
  BoxStorageUI._presentation:open(Presentation.capture(BoxStorageUI))
  se(se_id("SE_PC_LOGIN"))
end

function BoxStorageUI.close()
  if BoxStorageUI.holdingMon then
    local restored = Storage.restoreHeldMon(BoxStorageUI._session, BoxStorageUI.holdingMon, BoxStorageUI._holdingOrigin)
    if not restored then return false end
  end
  -- pokefirered/src/pokemon_storage_system_tasks.c:1979
  update_box_to_send_mons()
  BoxStorageUI.open = false
  BoxStorageUI.holdingMon = nil
  BoxStorageUI.holdingSource = nil
  BoxStorageUI._holdingOrigin, BoxStorageUI._presentation = nil, nil
  BoxStorageUI.drawerOpen = false
  BoxStorageUI._actionSource = nil
  BoxStorageUI._actionTarget = nil
  Stack.pop("box_storage")
  local cb = BoxStorageUI._onClose
  BoxStorageUI._onClose = nil
  if cb then cb() end
end

function BoxStorageUI.reset()
  BoxStorageUI.open = false
  BoxStorageUI._session, BoxStorageUI._onClose = nil, nil
  BoxStorageUI._presentation = nil
  BoxStorageUI.holdingMon, BoxStorageUI.holdingSource, BoxStorageUI._holdingOrigin = nil, nil, nil
  BoxStorageUI._actionSource, BoxStorageUI._actionTarget, BoxStorageUI._activeActions = nil, nil, nil
  BoxStorageUI._markings, BoxStorageUI._markReturnMode = nil, nil
  BoxStorageUI._pendingDeposit, BoxStorageUI._pickBox = nil, nil
  BoxStorageUI._status, BoxStorageUI._lastUsedBox, BoxStorageUI._wallpaperGroup = nil, nil, nil
  BoxStorageUI._prevPartySlot = nil
  BoxStorageUI.mode, BoxStorageUI.subMode = "browse", "move"
  BoxStorageUI.drawerOpen = false
  BoxStorageUI.cursorSlot, BoxStorageUI.partyCursor = 1, 1
  BoxStorageUI.actionCursor, BoxStorageUI.boxMenuCursor, BoxStorageUI.wallpaperCursor = 1, 1, 1
  BoxStorageUI.hoverTimer, BoxStorageUI.hoverFrame = 0, 0
  Stack.pop("box_storage")
end

local function request_close()
  if BoxStorageUI.holdingMon then
    BoxStorageUI._status = storage_text("HoldingPoke", "gText_YoureHoldingAPkmn")
    BoxStorageUI.mode = "message"
    se(se_id("SE_FAILURE"))
    return
  end
  local p = BoxStorageUI._presentation
  if p then
    p:close(function()
      if BoxStorageUI.open and BoxStorageUI._presentation == p then BoxStorageUI.close() end
    end)
  else BoxStorageUI.close() end
  se(se_id("SE_PC_OFF"))
end

local function place_held(loc, boxId, slot)
  local held = BoxStorageUI.holdingMon
  if loc == "box" and is_rs() and reject_native(RsStorage.hasMail(held) and "PleaseRemoveMail") then return end
  if loc == "party" and is_rs() then
    if reject_native(not RsStorage.canReplaceParty(BoxStorageUI._session, slot, held) and "LastPoke") then return end
  end
  -- pokefirered/src/pokemon_storage_system_tasks.c:977
  se(se_id("SE_SELECT"))
  local ok, target, errorName = Storage.placeHeldMon(BoxStorageUI._session, held, loc, slot, boxId, BoxStorageUI.holdingSource)
  if not ok then
    BoxStorageUI._status, BoxStorageUI.mode = tostring(errorName or ""), "message"
    return
  end
  BoxStorageUI.holdingMon = target
  BoxStorageUI.holdingSource = target and {loc = loc, boxId = boxId, slot = slot} or nil
  if not target then BoxStorageUI._holdingOrigin = nil end
end

function BoxStorageUI.isOpen()
  return BoxStorageUI.open
end

function BoxStorageUI.hasPendingMon() return BoxStorageUI.open and BoxStorageUI.holdingMon ~= nil end
function BoxStorageUI.isPresentationBusy()
  return BoxStorageUI._presentation ~= nil and BoxStorageUI._presentation:busy()
end

function BoxStorageUI.update(dt)
  if not BoxStorageUI.open then return end

  -- Release sequence animation update
  if ReleaseSeq.isActive() then
    local before = Presentation.capture(BoxStorageUI)
    ReleaseSeq.update(dt)
    if BoxStorageUI._presentation then
      local after = Presentation.capture(BoxStorageUI)
      if not ReleaseSeq.isActive() then BoxStorageUI._presentation:observe(before, after) end
      BoxStorageUI._presentation:update(after)
    end
    return
  end

  if BoxStorageUI._presentation then BoxStorageUI._presentation:update(Presentation.capture(BoxStorageUI)) end
  if BoxStorageUI.mode == "pick_box" or BoxStorageUI.mode == "deposit_box_full" then
    BoxStorageUI._pickFrames = (BoxStorageUI._pickFrames or 0) + 1
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

  if is_rs() then
    local session, presentation = BoxStorageUI._session, BoxStorageUI._presentation
    local mons, maxIndex
    if loc == "box" then mons, maxIndex = current_box_data().mons, Storage.IN_BOX_COUNT - 1
    elseif loc == "party" then mons, maxIndex = session.party, #session.party - 1 end
    if not mons then return end
    BoxStorageUI.mode = returnMode
    local function show()
      if not BoxStorageUI.open or BoxStorageUI._session ~= session or BoxStorageUI._presentation ~= presentation then return end
      SummaryMenu.openMenu(mons, sId, {
        session = session, context = loc, maxMonIndex = maxIndex,
        onClose = function(index)
          if not BoxStorageUI.open or BoxStorageUI._session ~= session or BoxStorageUI._presentation ~= presentation then return end
          if index then
            if loc == "box" then BoxStorageUI.cursorSlot = index else BoxStorageUI.partyCursor = index end
          end
          BoxStorageUI.mode = returnMode
          if presentation then presentation:summaryReturn(Presentation.capture(BoxStorageUI)) end
          se(se_id("SE_SELECT"))
        end,
      })
    end
    if not presentation or not presentation:summaryOut(show) then show() end
    return
  end

  local function show_shared_summary(mons, startIndex, context)
    local session, presentation = BoxStorageUI._session, BoxStorageUI._presentation
    BoxStorageUI.mode = returnMode
    local function show()
      if not BoxStorageUI.open or BoxStorageUI._session ~= session or BoxStorageUI._presentation ~= presentation then return end
      SummaryMenu.openMenu(mons, startIndex, {
        session = session, context = context,
        onClose = function()
          if not BoxStorageUI.open or BoxStorageUI._session ~= session or BoxStorageUI._presentation ~= presentation then return end
          BoxStorageUI.mode = returnMode
          if presentation then presentation:summaryReturn(Presentation.capture(BoxStorageUI)) end
          se(se_id("SE_SELECT"))
        end,
      })
    end
    if not presentation or not presentation:summaryOut(show) then show() end
  end

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
      show_shared_summary(boxMons, startIndex, "box")
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
    show_shared_summary(partyMons, startIndex, "party")
  end
end

local function handle_input(input)
  if not BoxStorageUI.open then return end

  if BoxStorageUI.mode == "markings" then
    local result = RsMarkings.input(BoxStorageUI._markings, input)
    if result == "closed" then BoxStorageUI.mode, BoxStorageUI._markings = BoxStorageUI._markReturnMode, nil end
    if result then se(se_id("SE_SELECT")) end
    return
  end
  if BoxStorageUI.mode == "deposit_box_full" then
    local dpad = not is_rs() and (input:wasPressed("up") or input:wasPressed("down")
      or input:wasPressed("left") or input:wasPressed("right"))
    -- pokefirered/src/pokemon_storage_system_tasks.c:1246
    if input:wasPressed("a") or input:wasPressed("b") or dpad then BoxStorageUI.mode = "pick_box" end
    return
  end

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
        request_close()
      else
        BoxStorageUI.mode = "browse"
        BoxStorageUI.drawerOpen = false
        BoxStorageUI.cursorSlot = 1
        se(5)
      end
    elseif input:wasPressed("a") then
      if BoxStorageUI.partyCursor == 7 then -- CANCEL button
        if BoxStorageUI.subMode == "deposit" and BoxStorageUI.holdingMon == nil then
          request_close()
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
          place_held("party", nil, pIdx)
        elseif mon then
          BoxStorageUI._actionSource = "party"
          BoxStorageUI._actionTarget = { mon = mon, loc = "party", boxId = nil, slot = pIdx }
          if is_rs() then
            BoxStorageUI._activeActions = RsStorage.actions(BoxStorageUI.subMode, "party", false, true)
          elseif BoxStorageUI.subMode == "deposit" then
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
            se(se_id("SE_SELECT")) -- pokefirered/src/pokemon_storage_system_tasks.c:992
          else
            BoxStorageUI._status = storage_text("PartyFull", "gText_YourPartysFull")
            BoxStorageUI.mode = "message"
            se(5) -- pokefirered/src/pokemon_storage_system_tasks.c:992
          end
        end
      elseif choice == "STORE" or choice == "DEPOSIT" then
        local mon, loc, bId, sId = mon_at_cursor()
        if loc == "party" and mon then
          local party = (BoxStorageUI._session and BoxStorageUI._session.party) or {}
          if is_rs() and reject_native(RsStorage.depositError(BoxStorageUI._session, sId)) then return end
          if is_rs() then
            BoxStorageUI._pendingDeposit = {slot = sId, returnMode = returnMode}
            -- pokeruby/src/pokemon_storage_system_2.c:896
            BoxStorageUI._pickBox = BoxStorageUI._depositBox or 1
            BoxStorageUI.mode = "pick_box"
            se(se_id("SE_SELECT"))
            return
          end
          if #party <= 1 then
            BoxStorageUI._status = RomText.plain("gText_JustOnePkmn")
            BoxStorageUI.mode = "message"
            se(se_id("SE_FAILURE")) -- pokefirered/src/pokemon_storage_system_tasks.c:1052
          else
            -- pokefirered/src/pokemon_storage_system_tasks.c:1196
            BoxStorageUI._pendingDeposit = {slot = sId, returnMode = returnMode}
            BoxStorageUI._pickBox = BoxStorageUI._depositBox or 1
            BoxStorageUI._pickFrames = 0
            BoxStorageUI.mode = "pick_box"
            se(se_id("SE_SELECT"))
          end
        end
      elseif choice == "MOVE" then
        local mon, loc, bId, sId = mon_at_cursor()
        if mon then
          if is_rs() and loc == "party" and reject_native(not RsStorage.canRemoveParty(BoxStorageUI._session, sId) and "LastPoke") then return end
          local picked = Storage.pickUpMon(BoxStorageUI._session, loc, sId, bId)
          if not picked then
            BoxStorageUI._status = storage_text("LastPoke", "gText_JustOnePkmn")
            BoxStorageUI.mode = "message"; return
          end
          BoxStorageUI.holdingMon = picked
          BoxStorageUI.holdingSource = { loc = loc, boxId = bId, slot = sId }
          BoxStorageUI._holdingOrigin = BoxStorageUI.holdingSource
          BoxStorageUI.mode = returnMode
          se(5)
        end
      elseif choice == "SUMMARY" then
        BoxStorageUI.mode = returnMode
        open_summary_for_cursor()
      elseif choice == "MARK" then
        local mon = mon_at_cursor()
        if mon and is_rs() then
          BoxStorageUI._markings, BoxStorageUI._markReturnMode = RsMarkings.open(mon), returnMode
          BoxStorageUI.mode = "markings"
        end
      elseif choice == "TAKE" then
        local mon = mon_at_cursor()
        if mon then
          local ok, err = Storage.detachHeldItem(BoxStorageUI._session, mon)
          if ok then
            -- pokefirered/src/pokemon_storage_system_tasks.c:1501
            BoxStorageUI._status = RomText.plain("gText_PlacedItemInBag")
            BoxStorageUI.mode = "message"
            se(se_id("SE_SELECT")) -- pokefirered/src/pokemon_storage_system_tasks.c:1493
          elseif err == "bag_full" then
            BoxStorageUI._status = RomText.plain("gText_BagIsFull2")
            BoxStorageUI.mode = "message"
            se(se_id("SE_FAILURE")) -- pokefirered/src/pokemon_storage_system_tasks.c:1487
          else
            BoxStorageUI._status = Strings("This POKéMON isn't holding anything.")
            BoxStorageUI.mode = "message"
            se(5) -- pokefirered/src/pokemon_storage_system_tasks.c:1493
          end
        end
      elseif choice == "RELEASE" then
        local mon, loc, bId, sId = mon_at_cursor()
        if mon and (loc == "box" or is_rs() and loc == "party") then
          if is_rs() and reject_native(RsStorage.releaseError(BoxStorageUI._session, mon, loc, sId)) then return end
          local col = (sId - 1) % 6
          local row = math.floor((sId - 1) / 6)
          local px = GRID_ORIGIN_X + col * COL_W + 12
          local py = GRID_ORIGIN_Y + row * ROW_H + 12
          if loc == "party" then px, py = PcChrome.getPartyCursorCoords(sId) end
          se(se_id("SE_SELECT")) -- pokefirered/src/pokemon_storage_system_tasks.c:1017
          BoxStorageUI.mode = "browse"
          BoxStorageUI.drawerOpen = false
          ReleaseSeq.start({
            session = BoxStorageUI._session,
            mon = mon,
            loc = loc,
            boxId = bId,
            slotIdx = sId,
            startX = px,
            startY = py,
            onComplete = function()
              BoxStorageUI.mode = returnMode
              if loc == "party" then
                BoxStorageUI.drawerOpen = true
                BoxStorageUI.partyCursor = math.max(1, math.min(sId, #(BoxStorageUI._session.party or {})))
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
    local boxActions = box_actions()
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
        -- pokefirered/src/pokemon_storage_system_tasks.c:1833
        BoxStorageUI._pendingDeposit, BoxStorageUI._pickBox = nil, Storage.ensure(BoxStorageUI._session).currentBox or 1
        BoxStorageUI._pickFrames = 0
        se(5)
      elseif choice == "WALLPAPER" then
        BoxStorageUI.mode = is_rs() and "pick_wallpaper_group" or "pick_wallpaper"
        BoxStorageUI._wallpaperGroup = 1
        local box = current_box_data()
        BoxStorageUI.wallpaperCursor = box and box.wallpaper or 1
        se(5)
      elseif choice == "NAME" then
        local box = current_box_data()
        BoxStorageUI.mode = "browse"
        require("src.ui.game3.naming").open({template = "BOX", session = BoxStorageUI._session,
          initialText = box.name, seed = box.name, onDone = function(name)
            if name and name ~= "" then box.name = name end
          end})
      end
    elseif input:wasPressed("b") then
      BoxStorageUI.mode = "browse"
      se(5)
    end
    return
  end

  -- Pick Wallpaper
  if BoxStorageUI.mode == "pick_wallpaper_group" then
    if input:wasPressed("up") then BoxStorageUI._wallpaperGroup = (BoxStorageUI._wallpaperGroup - 2) % 4 + 1; se(se_id("SE_SELECT"))
    elseif input:wasPressed("down") then BoxStorageUI._wallpaperGroup = BoxStorageUI._wallpaperGroup % 4 + 1; se(se_id("SE_SELECT"))
    elseif input:wasPressed("a") then
      BoxStorageUI.wallpaperCursor = (BoxStorageUI._wallpaperGroup - 1) * 4 + 1
      BoxStorageUI.mode = "pick_wallpaper"; se(se_id("SE_SELECT"))
    elseif input:wasPressed("b") then BoxStorageUI.mode = "browse"; se(se_id("SE_SELECT")) end
    return
  end
  if BoxStorageUI.mode == "pick_wallpaper" then
    local count = wallpaper_count(BoxStorageUI._session)
    local base = is_rs() and (BoxStorageUI._wallpaperGroup - 1) * 4 or 0
    if is_rs() then count = 4 end
    if input:wasPressed("up") then
      BoxStorageUI.wallpaperCursor = ((BoxStorageUI.wallpaperCursor - base - 2) % count) + 1 + base
      se(5)
    elseif input:wasPressed("down") then
      BoxStorageUI.wallpaperCursor = ((BoxStorageUI.wallpaperCursor - base) % count) + 1 + base
      se(5)
    elseif input:wasPressed("a") then
      local box = current_box_data()
      if box then box.wallpaper = BoxStorageUI.wallpaperCursor end
      BoxStorageUI.mode = "browse"
      se(se_id("SE_SELECT")) -- pokefirered/src/pokemon_storage_system_tasks.c:1808
    elseif input:wasPressed("b") then
      BoxStorageUI.mode = is_rs() and "pick_wallpaper_group" or "browse"
      se(5)
    end
    return
  end

  -- Pick Box
  if BoxStorageUI.mode == "pick_box" then
    local storage = Storage.ensure(BoxStorageUI._session)
    local total = Storage.TOTAL_BOXES_COUNT
    -- pokefirered/src/pokemon_storage_system_menu.c:463
    if input:wasPressed("left") then BoxStorageUI._pickBox = (BoxStorageUI._pickBox - 2) % total + 1; se(se_id("SE_SELECT"))
    elseif input:wasPressed("right") then BoxStorageUI._pickBox = BoxStorageUI._pickBox % total + 1; se(se_id("SE_SELECT"))
    elseif input:wasPressed("b") then
      BoxStorageUI.mode = BoxStorageUI._pendingDeposit and BoxStorageUI._pendingDeposit.returnMode or "browse"
      BoxStorageUI._pendingDeposit = nil; se(se_id("SE_SELECT"))
    elseif input:wasPressed("a") then
      if BoxStorageUI._pendingDeposit then
        local pending = BoxStorageUI._pendingDeposit
        if is_rs() and reject_native(RsStorage.depositError(BoxStorageUI._session, pending.slot)) then BoxStorageUI._pendingDeposit = nil; return end
        local ok = Storage.deposit(BoxStorageUI._session, pending.slot, BoxStorageUI._pickBox)
        se(se_id("SE_SELECT"))
        -- pokeruby/src/pokemon_storage_system_2.c:923
        if is_rs() then BoxStorageUI._depositBox = BoxStorageUI._pickBox end
        if ok then
          -- pokefirered/src/pokemon_storage_system_tasks.c:1216
          BoxStorageUI._depositBox = BoxStorageUI._pickBox
          BoxStorageUI.mode, BoxStorageUI._pendingDeposit = pending.returnMode, nil
          local party = BoxStorageUI._session.party or {}
          if #party == 0 then
            BoxStorageUI.drawerOpen, BoxStorageUI.mode, BoxStorageUI.cursorSlot = false, "browse", 1
          else
            BoxStorageUI.partyCursor = math.max(1, math.min(pending.slot, #party))
          end
        else BoxStorageUI.mode = "deposit_box_full" end
      else storage.currentBox, BoxStorageUI.mode = BoxStorageUI._pickBox, "browse"; se(se_id("SE_SELECT")) end
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
        request_close()
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
        request_close()
      elseif input:wasPressed("b") then
        request_close()
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
        request_close()
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
        local storage = Storage.ensure(BoxStorageUI._session)
        place_held("box", storage.currentBox, slot)
      else
        local mon, loc, bId, sId = mon_at_cursor()
        if mon then
          BoxStorageUI._actionSource = "box"
          BoxStorageUI._actionTarget = { mon = mon, loc = "box", boxId = bId, slot = slot }
          if is_rs() then
            BoxStorageUI._activeActions = RsStorage.actions(BoxStorageUI.subMode, "box", false, true)
          elseif BoxStorageUI.subMode == "withdraw" then
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
        request_close()
      else
        request_close()
      end
    end
  end
end

function BoxStorageUI.handleInput(input)
  if not BoxStorageUI.open then return end
  local p = BoxStorageUI._presentation
  if p and p:busy() then return end
  local before = p and Presentation.capture(BoxStorageUI)
  handle_input(input)
  if p and BoxStorageUI.open and not ReleaseSeq.isActive() then
    p:observe(before, Presentation.capture(BoxStorageUI))
  end
end

local function draw_icon(mon, x, y, frame)
  if not mon then return end
  local icon = Pokemon.monIcon(mon)
  if not (icon and icon.image) then return end
  local q = icon.quads and (icon.quads[frame or 0] or icon.quads[0])
  love.graphics.setColor(1, 1, 1, 1)
  PcChrome.effectLayer("obj", function()
    if q then love.graphics.draw(icon.image, q, x - 16, y - 16)
    else love.graphics.draw(icon.image, x - 16, y - 16) end
  end)
end

local function screen_mask(fx)
  if not fx then return end
  if fx.rs then PcChrome.drawScreenBars(fx); return end
  local f, left, right, top, bottom, white = fx.frame, 0, 240, 0, 160, false
  if fx.opening then
    if f < 2 then left, right, top, bottom = 120, 120, 80, 81
    elseif f < 7 then left, right, top, bottom, white = math.max(0, 120 - (f - 1) * 20), math.min(240, 120 + (f - 1) * 20), 80, 81, true
    else top, bottom = math.max(0, 80 - (f - 7) * 20), math.min(160, 81 + (f - 7) * 20) end
  else
    if f < 6 then top, bottom = math.min(80, math.max(0, f - 1) * 20), math.max(81, 160 - math.max(0, f - 1) * 20)
    else left, right, top, bottom, white = math.min(120, (f - 5) * 20), math.max(120, 240 - (f - 5) * 20), 80, 81, true end
  end
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 240, top)
  love.graphics.rectangle("fill", 0, bottom, 240, 160 - bottom)
  love.graphics.rectangle("fill", 0, top, left, bottom - top)
  love.graphics.rectangle("fill", right, top, 240 - right, bottom - top)
  if white then love.graphics.setColor(1, 1, 1, 1); love.graphics.rectangle("fill", left, top, right - left, bottom - top) end
  love.graphics.setColor(1, 1, 1, 1)
end

function BoxStorageUI.draw()
  if not BoxStorageUI.open then return end
  local session = BoxStorageUI._session
  local storage = Storage.ensure(session)
  if not storage then return end
  local live = Presentation.capture(BoxStorageUI)
  local p = BoxStorageUI._presentation
  local visual = p and p:drawState(live) or {view = live, cursor = Presentation.cursor(live),
    hover = Presentation.hover(live), holding = live.holdingMon, clock = 0, handAge = 0, waveAge = 0, headerAge = 0,
    overlays = {}, hidden = {}}
  local function render()
  local view = visual.view
  local bId = view.currentBox
  local box = view.boxes[bId]

  -- 1. Full Salmon / Scrolling Background (BG3)
  PcChrome.drawBackground(visual.clock)

  -- 2. Box Wallpaper (BG2, X: 80, Y: 16)
  PcChrome.clip(80, 16, 160, 144, function()
    if visual.scroll then
      local t = visual.scroll
      local offset = math.min(t.frame, 32) * 6 * t.direction
      PcChrome.drawWallpaper(box and box.wallpaper or 1, session.waldaPhrase, -offset)
      local incoming = t.b.boxes[t.b.currentBox]
      PcChrome.drawWallpaper(incoming and incoming.wallpaper or 1, session.waldaPhrase, t.direction * 192 - offset)
    else PcChrome.drawWallpaper(box and box.wallpaper or 1, session.waldaPhrase) end
  end)

  -- 3. Interface Frame (BG1, X: 0, Y: 0)
  PcChrome.drawInterfaceFrame()

  -- 4. Top Buttons (PARTY POKéMON & CLOSE BOX)
  local activeBtn = nil
  if BoxStorageUI.cursorSlot == -10 then activeBtn = "party"
  elseif BoxStorageUI.cursorSlot == -20 then activeBtn = "close" end
  PcChrome.drawTopButtons(activeBtn)

  -- 5. Box Title Header (◀  BOX 1  ▶)
  PcChrome.clip(80, 16, 160, 24, function()
    if visual.scroll then
      local t = visual.scroll
      local offset = math.min(math.max(0, t.frame - 1), 32) * 6 * t.direction
      local incomingOffset = math.min(t.frame, 32) * 6 * t.direction
      PcChrome.drawBoxHeader(box and box.name, bId, false, {offsetX = -offset, noArrows = true})
      local incoming = t.b.boxes[t.b.currentBox]
      PcChrome.drawBoxHeader(incoming and incoming.name, t.b.currentBox, false,
        {offsetX = 192 * t.direction - incomingOffset, noArrows = true})
      local function arrow(index)
        local delay = (t.direction > 0 and index == 0 or t.direction < 0 and index == 1) and 5 or 29
        local step = math.max(0, t.frame - 1)
        local x = 92 + index * 136 - step * 6 * t.direction
        if step >= delay then x = (t.direction > 0 and 248 or 72) - (step - delay) * 6 * t.direction end
        return x - 4
      end
      PcChrome.drawBoxHeader("", 0, false, {leftArrow = arrow(0), rightArrow = arrow(1), noTitle = true})
    else PcChrome.drawBoxHeader(box and box.name, bId, view.cursorSlot == 0, {age = visual.headerAge}) end
  end)

  -- 6. Left TV Monitor & Info Panel Text/Sprite
  PcChrome.drawLeftDataPanel(visual.hover, visual.waveAge, visual.mosaic)

  -- 7. 30 Mini-Icons in Box Grid (6 cols × 5 rows)
  PcChrome.clip(80, 16, 160, 144, function()
  if visual.scroll then
    for _, sprite in ipairs(visual.scroll.icons) do
      if not sprite.dead then draw_icon(sprite.mon, sprite.x, sprite.y) end
    end
  else
  for s = 1, Storage.IN_BOX_COUNT do
    local mon = box and box.mons[s]
    if visual.hidden[mon] then mon = nil end
    if is_rs() and ReleaseSeq.isActive() and ReleaseSeq.loc == "box" and ReleaseSeq.boxId == bId and ReleaseSeq.slotIdx == s
      and ReleaseSeq.state ~= "confirm" and ReleaseSeq.state ~= "came_back" and ReleaseSeq.state ~= "worried" then mon = nil end
    if mon then
      local col = (s - 1) % 6
      local row = math.floor((s - 1) / 6)
      local px = GRID_ORIGIN_X + col * COL_W
      local py = GRID_ORIGIN_Y + row * ROW_H

      local isHovered = (not is_rs() and view.cursorSlot == s and view.mode ~= "party_drawer" and not visual.holding)
      local bounceY = (isHovered and BoxStorageUI.hoverFrame == 1) and -2 or 0
      local f = (isHovered and BoxStorageUI.hoverFrame == 1) and 1 or 0
      local icon = Pokemon.monIcon(mon)

      if icon and icon.image then
        local q = icon.quads and (icon.quads[f] or icon.quads[0])
        love.graphics.setColor(1, 1, 1, 1)
        PcChrome.effectLayer("obj", function()
          if q then love.graphics.draw(icon.image, q, px, py + bounceY)
          else love.graphics.draw(icon.image, px, py + bounceY) end
        end)
      end
    end
  end
  end
  end)

  -- 8. Party Drawer Overlay (if active or drawer open)
  local drawDrawer = visual.drawer
  if drawDrawer == nil then drawDrawer = view.mode == "party_drawer" or view.drawerOpen end
  if drawDrawer then
    PcChrome.clip(80, 0, 96, 160, function()
      PcChrome.drawPartyDrawer(view.party, view.partyCursor, is_rs() and 0 or BoxStorageUI.hoverFrame, nil,
        {y = visual.drawerY, hidden = visual.hidden, partyIcons = visual.partyIcons})
      for _, sprite in ipairs(visual.partyIcons or {}) do draw_icon(sprite.mon, sprite.x, sprite.y) end
    end)
  end

  -- 9. Draw Hand Cursor & Shadow
  local curX, curY = visual.cursor.x, visual.cursor.y
  local showShadow = false
  local vFlip = visual.cursor.flip
  if not visual.cursor.party and not visual.cursor.header and view.cursorSlot >= 1 and view.cursorSlot <= 30 then
    local s = view.cursorSlot
    -- Shadow only shows when hovering over an EMPTY box slot
    local monInSlot = box and box.mons[s]
    if visual.hidden[monInSlot] then monInSlot = nil end
    showShadow = (monInSlot == nil)
  end

  for _, sprite in ipairs(visual.overlays) do draw_icon(sprite.mon, sprite.x, sprite.y) end
  if visual.holding then draw_icon(visual.holding, curX, curY + 4) end
  local cursorState = visual.hand or (visual.holding and "holding" or p and p:busy() and "moving" or "idle")
  PcChrome.drawHandCursor(curX, curY, cursorState, showShadow, vFlip, visual.handAge)

  -- 10. Context Action Menu Popup
  if BoxStorageUI.mode == "action_menu" then
    local actions = BoxStorageUI._activeActions or { "CANCEL" }
    if is_rs() then
      local rows = {}; for _, act in ipairs(actions) do rows[#rows + 1] = menu_text(act) end
      native_rows(rows, BoxStorageUI.actionCursor)
      native_message(RsStorage.text("IsSelected", mon_at_cursor()))
    else
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
  end

  -- 10. Box Menu Popup
  if BoxStorageUI.mode == "box_menu" then
    local boxActions = box_actions()
    if is_rs() then
      local rows = {}; for _, act in ipairs(boxActions) do rows[#rows + 1] = menu_text(act) end
      native_rows(rows, BoxStorageUI.boxMenuCursor)
      native_message(RsStorage.text("WhatYouDo"))
    else
    Window.stdFrame(Window.template(5, 3, 12, #boxActions * 2))
    for i, act in ipairs(boxActions) do
      local yPx = 26 + (i - 1) * 16
      if i == BoxStorageUI.boxMenuCursor then Window.cursorPx(42, yPx) end
      Window.printPx(menu_text(act), 50, yPx)
    end
    end
  end

  -- 11. Wallpaper Picker Popup
  if is_rs() and (BoxStorageUI.mode == "pick_box" or BoxStorageUI.mode == "deposit_box_full") then
    require("src.ui.game3.rs.storage_popup").draw(storage, BoxStorageUI._pickBox)
    native_message(RsStorage.text(BoxStorageUI.mode == "deposit_box_full" and "BoxIsFull"
      or BoxStorageUI._pendingDeposit and "DepositInWhichBox" or "JumpToWhichBox"))
  elseif BoxStorageUI.mode == "pick_box" or BoxStorageUI.mode == "deposit_box_full" then
    require("src.ui.game3.storage_choose_box").draw(storage, BoxStorageUI._pickBox, BoxStorageUI._pickFrames,
      require("src.core.game3.profile").family(BoxStorageUI._session))
    Window.dialogueFrame()
    -- pokefirered/src/pokemon_storage_system_tasks.c:281-284
    Window.printPx(RomText.plain(BoxStorageUI.mode == "deposit_box_full" and "gText_BoxIsFull2"
      or BoxStorageUI._pendingDeposit and "gText_DepositInWhichBox" or "gText_JumpToWhichBox"), 16, 120)
  end
  if BoxStorageUI.mode == "pick_wallpaper_group" then
    local rows = {}; for _, name in ipairs({"Scenery1", "Scenery2", "Scenery3", "Etc"}) do rows[#rows + 1] = RsStorage.text(name) end
    native_rows(rows, BoxStorageUI._wallpaperGroup)
    native_message(RsStorage.text("PickATheme"))
  end
  if BoxStorageUI.mode == "pick_wallpaper" then
    if is_rs() then
      local rows, base = {}, (BoxStorageUI._wallpaperGroup - 1) * 4
      for i = 1, 4 do rows[i] = RsStorage.wallpaperName(base + i) end
      native_rows(rows, BoxStorageUI.wallpaperCursor - base)
      native_message(RsStorage.text("PickAWallpaper"))
    else
    Window.stdFrame(Window.template(5, 2, 14, 10))
    -- pokefirered/src/pokemon_storage_system_tasks.c:279
    Window.printPx(storage_text("PickAWallpaper", "gText_PickTheWallpaper"), 44, 18, { small = true })
    local count = wallpaper_count(BoxStorageUI._session)
    for i = 1, 4 do
      local wpId = ((BoxStorageUI.wallpaperCursor - 1 + i - 1) % count) + 1
      local textId = wpId > #PcChrome.wallpaperNames() and menu_text_forest(BoxStorageUI._session) - 1
        or menu_text_forest(BoxStorageUI._session) + wpId - 1
      local wpName = is_rs() and RsStorage.wallpaperName(wpId) or RomText.at("sMenuTexts", textId)
      local yPx = 34 + (i - 1) * 14
      if i == 1 then Window.cursorPx(44, yPx) end
      Window.printPx(wpName, 52, yPx)
    end
    end
  end

  -- 12. Message Overlay
  if BoxStorageUI.mode == "message" then
    if is_rs() then native_message(BoxStorageUI._status or "")
    else Window.dialogueFrame()
    if BoxStorageUI._status then
      Window.printPx(BoxStorageUI._status, 16, 120)
    end
    end
  end

  -- 13. Release Sequence Rendering
  if BoxStorageUI.mode == "markings" then RsMarkings.draw(BoxStorageUI._markings) end
  if ReleaseSeq.isActive() then
    ReleaseSeq.draw()
  end
  screen_mask(visual.screen)
  end
  PcChrome.effectFrame(visual, render)
end

return BoxStorageUI
