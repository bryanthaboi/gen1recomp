local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")
local RomText = require("src.core.game3.rom_text")
local Trig = require("src.core.game3.trig")

local ItemPc = {}

ItemPc.open = false
ItemPc.mode = "list"
ItemPc.scroll = 0
ItemPc.row = 0

-- src/item_pc.c:733 ItemPc_CountPcItems
local MAX_SHOWED = 6
-- src/list_menu.c:305
local ROW_H = 16
-- src/item_pc.c:131 sWindowTemplates[0]
local LIST_X, LIST_Y = 7 * 8, 1 * 8
local UP_TEXT_Y = 2
local ITEM_X = 9
local CURSOR_X = 1
local QTY_X = 110

local SE_SELECT = 5
-- include/constants/songs.h:6
local SE_PC_LOGIN = 2
local SE_PC_OFF = 3

-- src/item_pc.c:124 sTextColors
local COLORS = {
  [0] = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] },
  [1] = FrlgFont.COLOR.NORMAL,
  [2] = { fg = FrlgFont.STDPAL[3], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] },
  [3] = { fg = FrlgFont.STDPAL[10], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] },
}

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local function item_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  local root = (ok and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
  return root .. "/items/item_pc"
end

local function load_bg(name)
  ItemPc._images = ItemPc._images or {}
  local img = ItemPc._images[name]
  if img then return img end
  local rel = item_root() .. "/" .. name .. ".rgba"
  local bytes = require("src.core.game3.dataset").cache():read(rel)
  if not bytes or #bytes < 240 * 160 * 4 then
    error("ItemPc: " .. rel .. " is not in the cache", 0)
  end
  img = love.graphics.newImage(love.image.newImageData(240, 160, "rgba8", bytes))
  ItemPc._images[name] = img
  return img
end

local function items()
  return Storage.ensure(ItemPc._session).items
end

local function total()
  return #items() + 1
end

local function max_showed()
  return math.min(total(), MAX_SHOWED)
end

local function cursor_pos()
  return ItemPc.scroll + ItemPc.row
end

-- src/item_pc.c:620 ItemPc_SetCursorPosition
local function set_cursor_position()
  local n = #items()
  local shown = max_showed()
  if ItemPc.scroll ~= 0 and ItemPc.scroll + shown > n + 1 then
    ItemPc.scroll = (n + 1) - shown
  end
  if ItemPc.scroll + ItemPc.row >= n + 1 then
    if n + 1 < 2 then ItemPc.row = 0 else ItemPc.row = n end
  end
  if ItemPc.row > shown - 1 then
    ItemPc.scroll = ItemPc.scroll + ItemPc.row - (shown - 1)
    ItemPc.row = shown - 1
  end
end

-- src/item_pc.c:747 ItemPc_SetScrollPosition
local function set_scroll_position()
  local shown = max_showed()
  if ItemPc.row > 3 then
    local i = 0
    while i <= ItemPc.row - 3 do
      if ItemPc.scroll + shown == #items() + 1 then break end
      ItemPc.row = ItemPc.row - 1
      ItemPc.scroll = ItemPc.scroll + 1
      i = i + 1
    end
  end
end

-- src/list_menu.c:438
local function move_cursor(down)
  local count = total()
  local shown = max_showed()
  local scroll, row = ItemPc.scroll, ItemPc.row
  local newRow
  if not down then
    newRow = (shown == 1) and 0 or (shown - (math.floor(shown / 2) + shown % 2) - 1)
    if scroll == 0 then
      if row == 0 then return false end
      row = row - 1
    elseif row > newRow then
      row = row - 1
    else
      row = newRow
      scroll = scroll - 1
    end
  else
    newRow = (shown == 1) and 0 or (math.floor(shown / 2) + shown % 2)
    if scroll == count - shown then
      if row >= shown - 1 then return false end
      row = row + 1
    elseif row < newRow then
      row = row + 1
    else
      row = newRow
      scroll = scroll + 1
    end
  end
  ItemPc.scroll, ItemPc.row = scroll, row
  return true
end

local function held_repeat(input, key)
  if input:wasPressed(key) then return true end
  -- src/main.c:309
  return ItemPc._heldKey == key and ItemPc._heldFrames >= 40 and (ItemPc._heldFrames - 40) % 5 == 0
end

local function track_held(input)
  local key
  if input.isDown then
    if input:isDown("up") then key = "up" elseif input:isDown("down") then key = "down" end
  end
  if key ~= ItemPc._heldKey or input:wasPressed(key or "") then
    ItemPc._heldKey = key
    ItemPc._heldFrames = 0
  elseif key then
    ItemPc._heldFrames = (ItemPc._heldFrames or 0) + 1
  end
end

-- src/pc_screen_effect.c:52 Task_PCScreenEffect_TurnOn
local function fx_on()
  return { on = true, state = 0, l = 120, r = 120, t = 80, b = 81 }
end

-- src/pc_screen_effect.c:118 Task_PCScreenEffect_TurnOff
local function fx_off(cb)
  return { on = false, state = 0, l = 0, r = 240, t = 0, b = 160, cb = cb }
end

local function step_fx(fx)
  if fx.on then
    if fx.state == 2 then
      fx.l, fx.r = fx.l - 16, fx.r + 16
      if fx.l <= 0 or fx.r >= 240 then fx.l, fx.r, fx.white = 0, 240, false end
      if fx.l ~= 0 then return false end
    elseif fx.state == 3 then
      fx.t, fx.b = fx.t - 20, fx.b + 20
      if fx.t <= 0 or fx.b >= 160 then fx.t, fx.b = 0, 160 end
      if fx.t ~= 0 then return false end
    elseif fx.state == 1 then
      fx.white = true
    elseif fx.state >= 4 then
      return true
    end
  else
    if fx.state == 2 then
      fx.t, fx.b = fx.t + 20, fx.b - 20
      if fx.t >= 80 or fx.b <= 81 then fx.t, fx.b, fx.white = 80, 81, true end
      if fx.t ~= 80 then return false end
    elseif fx.state == 3 then
      fx.l, fx.r = fx.l + 16, fx.r - 16
      if fx.l >= 120 or fx.r <= 120 then fx.l, fx.r, fx.black = 120, 120, true end
      if fx.l ~= 120 then return false end
    elseif fx.state >= 4 then
      return true
    end
  end
  fx.state = fx.state + 1
  return false
end

function ItemPc.isOpen()
  return ItemPc.open
end

-- src/item_pc.c:218 ItemPc_Init
function ItemPc.show(opts)
  opts = opts or {}
  ItemPc.open = true
  ItemPc._session = opts.session
  ItemPc._onClose = opts.onClose
  if not opts.keepPosition then
    ItemPc.scroll, ItemPc.row = 0, 0
  end
  ItemPc.mode = "list"
  ItemPc.moveOrig = nil
  ItemPc.k = 0
  set_cursor_position()
  set_scroll_position()
  ItemPc._fx = fx_on()
  se(SE_PC_LOGIN)
  Stack.push("item_pc", ItemPc, { hideBelow = true })
end

local function finish_close()
  ItemPc.open = false
  Stack.pop("item_pc")
  local cb = ItemPc._onClose
  ItemPc._onClose = nil
  if cb then cb() end
end

-- src/item_pc.c:668 Task_ItemPcTurnOff1
local function turn_off(after)
  se(SE_PC_OFF)
  ItemPc._fx = fx_off(after or finish_close)
end

local function selected_entry()
  return items()[cursor_pos() + 1]
end

local function return_from_submenu()
  ItemPc.mode = "list"
end

-- src/item_pc.c:917 Task_ItemPcCleanUpWithdraw
local function clean_up_withdraw()
  set_cursor_position()
  return_from_submenu()
end

-- src/item_pc.c:880 ItemPc_DoWithdraw
local function do_withdraw()
  local entry = selected_entry()
  local id, qty = entry.id, ItemPc.qty
  local session = ItemPc._session
  if Bag.canAdd(session.bag, id, qty) and Bag.add(session.bag, id, qty) then
    require("src.core.game3.quest_log_recorder").event(session, "WithdrewItemFromPC",
      { ItemsData.displayName(id) })
    ItemPc.mode = "result"
    ItemPc.resultText = RomText.plain("gText_WithdrewQuantItem",
      { stringVars = { ItemsData.displayName(id), tostring(qty) } })
    ItemPc._pending = { pos = cursor_pos() + 1, qty = qty }
  else
    ItemPc.mode = "result"
    ItemPc.resultText = RomText.plain("gText_NoMoreRoomInBag")
    ItemPc._pending = nil
  end
end

-- src/item_pc.c:1011 Task_ItemPcGive
local function give()
  local session = ItemPc._session
  local party = (session and session.party) or {}
  if #party == 0 then
    ItemPc.mode = "msg"
    ItemPc.msgText = RomText.plain("gText_ThereIsNoPokemon")
    return
  end
  local id = selected_entry().id
  local hole
  ItemPc.mode = "party"
  local PartyMenu = require("src.ui.game3.party_menu")
  PartyMenu.show(party, session.moveOverlay, {
    session = session,
    bag = session.bag,
    item = id,
    mode = "give",
    giveSource = {
      -- src/item.c:416 RemovePCItem
      remove = function(itemId)
        local list = items()
        for i, e in ipairs(list) do
          if e.id == itemId then
            e.qty = e.qty - 1
            if e.qty <= 0 then
              table.remove(list, i)
              hole = i
            end
            return true
          end
        end
        return false
      end,
      -- src/item.c:385 AddPCItem
      restore = function(itemId)
        local list = items()
        for _, e in ipairs(list) do
          if e.id == itemId then
            e.qty = e.qty + 1
            return true
          end
        end
        table.insert(list, math.min(hole or (#list + 1), #list + 1), { id = itemId, qty = 1 })
        return true
      end,
      -- src/quest_log_events.c:1168 LoadEvent_GaveHeldItemFromPC
      quest = function(monName, itemName) return "GaveMonHeldItemFromPC", { itemName, monName } end,
    },
    onClose = function()
      set_cursor_position()
      return_from_submenu()
    end,
  })
end

local SUBMENU = {
  { key = "gText_Withdraw", run = "withdraw" },
  { key = "gOtherText_Give", run = "give" },
  { key = "gFameCheckerText_Cancel", run = "cancel" },
}

-- src/item_pc.c:766 ItemPc_MoveItemModeInit
local function begin_move()
  ItemPc.moveOrig = cursor_pos()
  ItemPc.mode = "move"
end

-- src/item_pc.c:800 ItemPc_InsertItemIntoNewSlot, :818 ItemPc_MoveItemModeCancel
local function end_move(commit)
  local from, pos = ItemPc.moveOrig, cursor_pos()
  ItemPc.moveOrig = nil
  ItemPc.mode = "list"
  if commit and not (from == pos or from == pos - 1) then
    local list = items()
    local slot = table.remove(list, from + 1)
    local to = pos > from and pos - 1 or pos
    table.insert(list, to + 1, slot)
  end
  if from < pos then ItemPc.row = ItemPc.row - 1 end
  if ItemPc.row < 0 then
    ItemPc.row = 0
    ItemPc.scroll = math.max(0, ItemPc.scroll - 1)
  end
end

function ItemPc.handleInput(input)
  if not ItemPc.open then return end
  ItemPc.k = ItemPc.k + 1
  local fx = ItemPc._fx
  if fx then
    if step_fx(fx) then
      ItemPc._fx = nil
      if fx.cb then fx.cb() end
    end
    return
  end
  track_held(input)
  local mode = ItemPc.mode

  if mode == "list" then
    -- src/item_pc.c:707 Task_ItemPcMain
    if input:wasPressed("select") then
      if cursor_pos() ~= #items() then
        se(SE_SELECT)
        begin_move()
      end
      return
    end
    if input:wasPressed("a") then
      se(SE_SELECT)
      if cursor_pos() == #items() then
        turn_off()
      else
        ItemPc.mode = "submenu"
        ItemPc.subCursor = 1
      end
    elseif input:wasPressed("b") then
      se(SE_SELECT)
      turn_off()
    elseif held_repeat(input, "up") then
      if move_cursor(false) then se(SE_SELECT) end
    elseif held_repeat(input, "down") then
      if move_cursor(true) then se(SE_SELECT) end
    end
  elseif mode == "move" then
    -- src/item_pc.c:782 Task_ItemPcMoveItemModeRun
    if held_repeat(input, "up") then
      if move_cursor(false) then se(SE_SELECT) end
    elseif held_repeat(input, "down") then
      if move_cursor(true) then se(SE_SELECT) end
    end
    if input:wasPressed("a") or input:wasPressed("select") then
      se(SE_SELECT)
      end_move(true)
    elseif input:wasPressed("b") then
      se(SE_SELECT)
      end_move(false)
    end
  elseif mode == "submenu" then
    -- src/menu.c:614 Menu_ProcessInputNoWrapAround
    if input:wasPressed("up") then
      if ItemPc.subCursor > 1 then ItemPc.subCursor = ItemPc.subCursor - 1; se(SE_SELECT) end
    elseif input:wasPressed("down") then
      if ItemPc.subCursor < #SUBMENU then ItemPc.subCursor = ItemPc.subCursor + 1; se(SE_SELECT) end
    elseif input:wasPressed("a") then
      se(SE_SELECT)
      local run = SUBMENU[ItemPc.subCursor].run
      if run == "withdraw" then
        -- src/item_pc.c:853 Task_ItemPcWithdraw
        ItemPc.qty = 1
        if selected_entry().qty == 1 then
          do_withdraw()
        else
          ItemPc.mode = "qty"
        end
      elseif run == "give" then
        give()
      else
        return_from_submenu()
      end
    elseif input:wasPressed("b") then
      se(SE_SELECT)
      return_from_submenu()
    end
  elseif mode == "qty" then
    -- src/item_pc.c:975 Task_ItemPcHandleWithdrawMultiple, src/menu_helpers.c:169
    local qmax = selected_entry().qty
    local q = ItemPc.qty
    if input:wasPressed("up") then
      q = q + 1
      if q > qmax then q = 1 end
    elseif input:wasPressed("down") then
      q = q - 1
      if q <= 0 then q = qmax end
    elseif input:wasPressed("right") then
      q = math.min(qmax, q + 10)
    elseif input:wasPressed("left") then
      q = math.max(1, q - 10)
    end
    if q ~= ItemPc.qty then
      ItemPc.qty = q
      se(SE_SELECT)
    elseif input:wasPressed("a") then
      se(SE_SELECT)
      do_withdraw()
    elseif input:wasPressed("b") then
      se(SE_SELECT)
      return_from_submenu()
    end
  elseif mode == "result" then
    -- src/item_pc.c:894 Task_ItemPcWaitButtonAndFinishWithdrawMultiple
    if input:wasPressed("a") or input:wasPressed("b") then
      se(SE_SELECT)
      local p = ItemPc._pending
      ItemPc._pending = nil
      if p then
        -- src/item_pc.c:924 RemovePCItem, ItemPcCompaction
        local list = items()
        list[p.pos].qty = list[p.pos].qty - p.qty
        if list[p.pos].qty <= 0 then table.remove(list, p.pos) end
      end
      clean_up_withdraw()
    end
  elseif mode == "msg" then
    -- src/item_pc.c:1037 gTask_ItemPcWaitButtonAndExitSubmenu
    if input:wasPressed("a") then
      se(SE_SELECT)
      ItemPc.msgText = nil
      return_from_submenu()
    end
  end
end

-- src/menu_indicators.c:270 SpriteCallback_ScrollIndicatorArrow
local function bob(k, freq)
  local v = Trig.sin((k * freq) % 256) * 2 / 256
  return v < 0 and math.ceil(v) or math.floor(v)
end

local function draw_fx(fx)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, 240, fx.t)
  love.graphics.rectangle("fill", 0, fx.b, 240, 160 - fx.b)
  love.graphics.rectangle("fill", 0, fx.t, fx.l, fx.b - fx.t)
  love.graphics.rectangle("fill", fx.r, fx.t, 240 - fx.r, fx.b - fx.t)
  if fx.black then
    love.graphics.rectangle("fill", 0, 0, 240, 160)
  elseif fx.white then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", fx.l, fx.t, fx.r - fx.l, fx.b - fx.t)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function ItemPc.draw()
  if not ItemPc.open then return end
  local mode = ItemPc.mode
  local sub = mode ~= "list" and mode ~= "move"
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(load_bg(sub and "bg_submenu" or "bg"), 0, 0)

  -- src/item_pc.c:578 ItemPc_PrintWithdrawItem
  FrlgFont.draw(RomText.plain("gText_WithdrawItem"), 8, 8 + 1,
    { small = true, colors = COLORS[0], linePitch = 13 + 1 })

  local list = items()
  local n = #list
  local shown = max_showed()
  local BagChrome = require("src.ui.game3.bag_chrome")
  for i = 0, shown - 1 do
    local idx = ItemPc.scroll + i
    if idx > n then break end
    local y = LIST_Y + UP_TEXT_Y + i * ROW_H
    if idx == n then
      FrlgFont.draw(RomText.plain("gFameCheckerText_Cancel"), LIST_X + ITEM_X, y, { colors = COLORS[1] })
    else
      local e = list[idx + 1]
      FrlgFont.draw(ItemsData.displayName(e.id), LIST_X + ITEM_X, y, { colors = COLORS[1] })
      -- src/item_pc.c:553 ItemPc_ItemPrintFunc
      FrlgFont.draw(RomText.plain("gText_TimesStrVar1", { stringVars = { string.format("%3d", e.qty) } }),
        LIST_X + QTY_X, y, { small = true, colors = COLORS[1] })
    end
    if mode == "move" and idx == ItemPc.moveOrig then
      FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, LIST_X, y, { colors = COLORS[2] })
    end
  end
  local cursorY = LIST_Y + UP_TEXT_Y + ItemPc.row * ROW_H
  if mode == "list" then
    FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, LIST_X + CURSOR_X, cursorY, { colors = COLORS[1] })
  elseif mode ~= "move" then
    FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, LIST_X, cursorY, { colors = COLORS[2] })
  end

  -- src/item_pc.c:515 ItemPc_MoveCursorFunc
  local pos = mode == "move" and ItemPc.moveOrig or cursor_pos()
  local entry = list[pos + 1]
  BagChrome.drawItemIcon(entry and entry.id or (ItemsData.ITEMS_COUNT or 375), 8, 124)
  if mode == "move" then
    FrlgFont.draw(RomText.plain("gOtherText_WhereShouldTheStrVar1BePlaced",
      { stringVars = { ItemsData.displayName(entry.id) } }), 40, 112 + 3,
      { colors = COLORS[0], linePitch = 14 + 3 })
    -- src/item_menu_icons.c:282 UpdateSwapLinePos
    BagChrome.drawSwapLine(96 - 32, cursorY - LIST_Y + 7)
  elseif mode == "list" then
    local desc
    if not entry then
      desc = RomText.plain("gText_ReturnToPC")
    elseif ItemsData.pocketOf(entry.id) == "TM_CASE" then
      local Pokemon = require("src.core.game3.pokemon")
      desc = Pokemon.moveName(Pokemon.moveFromTmItem(entry.id))
    else
      desc = ItemsData.description(entry.id)
    end
    FrlgFont.draw(desc, 40, 112 + 3, { colors = COLORS[3], linePitch = 14 })
  end

  -- src/item_pc.c:640 ItemPc_PlaceTopMenuScrollIndicatorArrows
  if mode == "list" then
    if ItemPc.scroll > 0 then
      BagChrome.drawArrow("up", 128 - 8, 8 - 8 + bob(ItemPc.k, 8))
    end
    if ItemPc.scroll < total() - shown then
      BagChrome.drawArrow("down", 128 - 8, 104 - 8 + bob(ItemPc.k, -8))
    end
  end

  if mode == "submenu" then
    -- src/item_pc.c:835 Task_ItemPcSubmenuInit
    Window.stdFrame(Window.template(22, 13, 7, 6))
    for i, opt in ipairs(SUBMENU) do
      local y = 13 * 8 + 2 + (i - 1) * ROW_H
      FrlgFont.draw(RomText.plain(opt.key), 22 * 8 + 8, y, { colors = COLORS[1] })
      if i == ItemPc.subCursor then
        FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, 22 * 8, y, { colors = COLORS[1] })
      end
    end
    Window.fixedStdFrame(Window.template(6, 15, 14, 4))
    FrlgFont.draw(RomText.box("gText_Var1IsSelected", { stringVars = { ItemsData.displayName(entry.id) } }),
      6 * 8, 15 * 8 + 2, { colors = COLORS[1], maxWidth = 14 * 8 })
  elseif mode == "qty" then
    -- src/item_pc.c:942 ItemPc_WithdrawMultipleInitWindow
    Window.fixedStdFrame(Window.template(6, 15, 16, 4))
    FrlgFont.draw(RomText.box("gText_WithdrawHowMany", { stringVars = { ItemsData.displayName(entry.id) } }),
      6 * 8, 15 * 8 + 2, { colors = FrlgFont.COLOR.NORMAL, maxWidth = 16 * 8 })
    Window.stdFrame(Window.template(24, 15, 5, 4))
    FrlgFont.draw(RomText.plain("gText_TimesStrVar1", { stringVars = { string.format("%03d", ItemPc.qty) } }),
      24 * 8 + 8, 15 * 8 + 10, { small = true, letterSpacing = 1, colors = COLORS[1] })
    -- src/item_pc.c:646 ItemPc_PlaceWithdrawQuantityScrollIndicatorArrows
    BagChrome.drawArrow("up", 212 - 8, 120 - 8 + bob(ItemPc.k, 8))
    BagChrome.drawArrow("down", 212 - 8, 152 - 8 + bob(ItemPc.k, -8))
  elseif mode == "result" then
    Window.fixedStdFrame(Window.template(6, 15, 23, 4))
    FrlgFont.draw(ItemPc.resultText, 6 * 8, 15 * 8 + 2, { colors = FrlgFont.COLOR.NORMAL, maxWidth = 23 * 8 })
  elseif mode == "msg" then
    -- src/item_pc.c:1140 ItemPc_PrintOnWindow5WithContinueTask
    local Chrome = require("src.ui.game3.chrome")
    Window.dialogueFrame()
    FrlgFont.draw(ItemPc.msgText, Chrome.DLG_LEFT * 8, Chrome.DLG_TOP * 8 + 1,
      { maxWidth = Chrome.DLG_W * 8, colors = FrlgFont.COLOR.NORMAL })
  end

  if ItemPc._fx then draw_fx(ItemPc._fx) end
end

return ItemPc
