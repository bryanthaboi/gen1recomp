local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")
local Storage = require("src.core.game3.storage")
local Bag = require("src.core.game3.bag")

local ItemStorage = { isMenu = true }

ItemStorage.open = false

-- pokeemerald/src/player_pc.c:305
local WIN = {
  list = Window.template(16, 1, 13, 18),
  message = Window.template(1, 13, 13, 6),
  icon = Window.template(1, 8, 3, 3),
  title = Window.template(1, 1, 13, 2),
  quantity = Window.template(8, 9, 6, 2),
  yesno = Window.template(9, 7, 5, 4),
}
ItemStorage.WIN = WIN
-- pokeruby/src/player_pc.c:973
local WIN_RS = {
  list = WIN.list,
  message = WIN.message,
  title = Window.template(1, 1, 10, 2),
  -- pokeruby/src/player_pc.c:606
  quantity = Window.template(7, 9, 6, 2),
  -- pokeruby/src/player_pc.c:703
  yesno = Window.template(8, 7, 5, 4),
}
ItemStorage.WIN_RS = WIN_RS

local function is_rs()
  return require("src.ui.game3.rs.player_pc_policy").matches(ItemStorage._session)
end
-- pokeemerald/src/player_pc.c:283
local ITEM_X, UP_TEXT_Y = 8, 9
-- pokeemerald/src/player_pc.c:699
local PAGE_MAX = 8
-- pokeemerald/src/main.c:309
local REPEAT_START, REPEAT_CONTINUE = 40, 5
-- pokeemerald/src/player_pc.c:88
local SWAP_LINE_LENGTH = 7
-- pokeemerald/src/menu_helpers.c:399 CreateSwapLineSprites
local SWAP_LINE = {}
for i = 0, SWAP_LINE_LENGTH - 1 do
  -- pokeemerald/src/player_pc.c:1341
  SWAP_LINE[i + 1] = { frame = i == 0 and 0 or 4, x = i * 16 + 128, y = 0 }
end
local swapLineImg = {}
-- pokeemerald/src/player_pc.c:356
local SWAP_ARROW_COLORS = { bg = FrlgFont.STDPAL[1], fg = FrlgFont.STDPAL[3], shadow = FrlgFont.STDPAL[2] }
ItemStorage.SWAP_ARROW_COLORS = SWAP_ARROW_COLORS

local function se(name)
  local SE = require("src.core.game3.se_ids")
  pcall(function() require("src.core.game3.audio").playSe(SE[name]) end)
end

local function items()
  return Storage.ensure(ItemStorage._session).items
end

local function item_name(id)
  return require("src.core.game3.items_data").displayName(id)
end

local function count()
  return #items() + 1
end

local function page_items()
  local n = count()
  return n > PAGE_MAX and PAGE_MAX or n
end

local function pos()
  return ItemStorage.scroll + ItemStorage.row
end

local function narrow()
  if is_rs() then return { font = "normal" } end
  return { font = "narrow" }
end

local function row_height()
  if is_rs() then return 16 end
  local face = FrlgFont.face and FrlgFont.face(narrow())
  return face and face.height or 16
end

-- pokeemerald/src/list_menu.c:1119
local function clamp_cursor()
  local n, shown = count(), page_items()
  if ItemStorage.scroll ~= 0 and ItemStorage.scroll + shown > n then
    ItemStorage.scroll = n - shown
  end
  if ItemStorage.scroll + ItemStorage.row >= n then
    ItemStorage.row = n - 1 - ItemStorage.scroll
  end
  if ItemStorage.row < 0 then ItemStorage.row = 0 end
end

local function description()
  local e = items()[pos() + 1]
  if not e then return RomText.plain("gText_GoBackPrevMenu") end
  local ItemsData = require("src.core.game3.items_data")
  local ok, d = pcall(ItemsData.description, e.id)
  return ok and d or ""
end

local function set_message(key, vars)
  if key == nil then
    ItemStorage._message = description()
  else
    ItemStorage._message = RomText.plain(key, { stringVars = vars })
  end
end

function ItemStorage.show(opts)
  opts = opts or {}
  ItemStorage.open = true
  ItemStorage._session = opts.session
  ItemStorage._onClose = opts.onClose
  ItemStorage._toss = opts.toss == true
  ItemStorage.scroll = 0
  ItemStorage.row = 0
  ItemStorage.state = "list"
  ItemStorage.swapFrom = nil
  ItemStorage.quantity = 1
  ItemStorage._frames = 0
  clamp_cursor()
  set_message(nil)
  Stack.push("rse_item_storage", ItemStorage, { hideBelow = false })
end

function ItemStorage.isOpen()
  return ItemStorage.open
end

function ItemStorage.close()
  if not ItemStorage.open then return end
  ItemStorage.open = false
  Stack.pop("rse_item_storage")
  local cb = ItemStorage._onClose
  ItemStorage._onClose = nil
  if cb then cb() end
end

function ItemStorage.reset()
  ItemStorage.open = false
  ItemStorage._onClose = nil
  Stack.pop("rse_item_storage")
end

local function track_held(input)
  local key
  if input.isDown then
    for _, k in ipairs({ "up", "down", "left", "right" }) do
      local ok, down = pcall(input.isDown, input, k)
      if ok and down then key = k break end
    end
  end
  if key ~= ItemStorage._held or (key and input:wasPressed(key)) then
    ItemStorage._held = key
    ItemStorage._heldFrames = 0
  elseif key then
    ItemStorage._heldFrames = (ItemStorage._heldFrames or 0) + 1
  end
end

local function repeated(input, key)
  if input:wasPressed(key) then return true end
  local f = ItemStorage._heldFrames or 0
  return ItemStorage._held == key and f >= REPEAT_START and (f - REPEAT_START) % REPEAT_CONTINUE == 0
end

-- pokeemerald/src/list_menu.c:438
local function step(down)
  local n, shown = count(), page_items()
  local row, scroll = ItemStorage.row, ItemStorage.scroll
  if not down then
    local newRow = shown == 1 and 0 or (shown - (math.floor(shown / 2) + shown % 2) - 1)
    if scroll == 0 then
      if row == 0 then return false end
      ItemStorage.row = row - 1
    elseif row > newRow then
      ItemStorage.row = row - 1
    else
      ItemStorage.row = newRow
      ItemStorage.scroll = scroll - 1
    end
  else
    local newRow = shown == 1 and 0 or (math.floor(shown / 2) + shown % 2)
    if scroll == n - shown then
      if row >= shown - 1 then return false end
      ItemStorage.row = row + 1
    elseif row < newRow then
      ItemStorage.row = row + 1
    else
      ItemStorage.row = newRow
      ItemStorage.scroll = scroll + 1
    end
  end
  return true
end

local function list_move(input)
  if repeated(input, "up") then
    if step(false) then
      se("SE_SELECT")
      return true
    end
  elseif repeated(input, "down") then
    if step(true) then
      se("SE_SELECT")
      return true
    end
  end
  return false
end

-- pokeemerald/src/player_pc.c:1440
local function do_withdraw()
  local e = items()[pos() + 1]
  local bag = ItemStorage._session and ItemStorage._session.bag
  if bag and Bag.canAdd(bag, e.id, ItemStorage.quantity) and Bag.add(bag, e.id, ItemStorage.quantity) then
    set_message("gText_WithdrawXItems", { item_name(e.id), tostring(ItemStorage.quantity) })
    ItemStorage.state = "remove"
  else
    ItemStorage.quantity = 0
    set_message("gText_NoRoomInBag")
    ItemStorage.state = "error"
  end
end

-- pokeemerald/src/player_pc.c:1442
local function do_toss()
  local e = items()[pos() + 1]
  local ItemsData = require("src.core.game3.items_data")
  local info = ItemsData.info(e.id)
  if info and (tonumber(info.importance) or 0) ~= 0 then
    ItemStorage.quantity = 0
    set_message("gText_TooImportantToToss")
    ItemStorage.state = "error"
    return
  end
  set_message("gText_ConfirmTossItems", { item_name(e.id), tostring(ItemStorage.quantity) })
  ItemStorage.yesCursor = 1
  ItemStorage.state = "yesno"
end

local function do_action()
  local e = items()[pos() + 1]
  ItemStorage.quantity = 1
  if (tonumber(e.qty) or 0) == 1 then
    if ItemStorage._toss then do_toss() else do_withdraw() end
    return
  end
  set_message(ItemStorage._toss and "gText_TossHowManyVar1s" or "gText_WithdrawHowManyItems", { item_name(e.id) })
  ItemStorage.state = "quantity"
end

-- pokeemerald/src/player_pc.c:1480
local function remove_item()
  local i = pos() + 1
  local list = items()
  local e = list[i]
  if e then
    e.qty = (tonumber(e.qty) or 0) - ItemStorage.quantity
    if e.qty <= 0 then table.remove(list, i) end
  end
  clamp_cursor()
  set_message(nil)
  ItemStorage.state = "list"
end

-- pokeemerald/src/menu_helpers.c:212
local function adjust_quantity(input, max)
  local q = ItemStorage.quantity
  if repeated(input, "up") then
    q = q + 1
    if q > max then q = 1 end
  elseif repeated(input, "down") then
    q = q - 1
    if q <= 0 then q = max end
  elseif repeated(input, "right") then
    if q == max then return false end
    q = q + 10
    if q > max then q = max end
  elseif repeated(input, "left") then
    if q == 1 then return false end
    q = q - 10
    if q <= 0 then q = 1 end
  else
    return false
  end
  if q == ItemStorage.quantity then return false end
  ItemStorage.quantity = q
  se("SE_SELECT")
  return true
end

-- pokeemerald/src/player_pc.c:1318
local function finish_swap(canceled)
  se("SE_SELECT")
  local from = ItemStorage.swapFrom
  local to = pos()
  local list = items()
  if not canceled and from ~= to and from ~= to - 1 then
    local e = table.remove(list, from + 1)
    local dest = to
    if from < to then dest = to - 1 end
    table.insert(list, dest + 1, e)
  end
  if from < to then ItemStorage.row = ItemStorage.row - 1 end
  ItemStorage.swapFrom = nil
  clamp_cursor()
  set_message(nil)
  ItemStorage.state = "list"
end

function ItemStorage.handleInput(input)
  if not ItemStorage.open or not input then return end
  track_held(input)
  local state = ItemStorage.state
  if state == "list" then
    -- pokeemerald/src/player_pc.c:1207
    if input:wasPressed("select") then
      if pos() ~= count() - 1 then
        se("SE_SELECT")
        ItemStorage.swapFrom = pos()
        set_message("gText_MoveVar1Where", { item_name(items()[pos() + 1].id) })
        ItemStorage.state = "swap"
      end
      return
    end
    if input:wasPressed("a") then
      se("SE_SELECT")
      if pos() == count() - 1 then
        ItemStorage.close()
      else
        do_action()
      end
      return
    end
    if input:wasPressed("b") then
      se("SE_SELECT")
      ItemStorage.close()
      return
    end
    if list_move(input) then set_message(nil) end
  elseif state == "swap" then
    -- pokeemerald/src/player_pc.c:1288
    if input:wasPressed("select") then
      finish_swap(false)
    elseif input:wasPressed("a") then
      finish_swap(false)
    elseif input:wasPressed("b") then
      finish_swap(pos() ~= count() - 1 and false or true)
    else
      list_move(input)
    end
  elseif state == "quantity" then
    -- pokeemerald/src/player_pc.c:1392
    local e = items()[pos() + 1]
    if adjust_quantity(input, tonumber(e.qty) or 1) then return end
    if input:wasPressed("a") then
      se("SE_SELECT")
      if ItemStorage._toss then do_toss() else do_withdraw() end
    elseif input:wasPressed("b") then
      se("SE_SELECT")
      set_message(nil)
      ItemStorage.state = "list"
    end
  elseif state == "yesno" then
    -- pokeemerald/src/menu.c:2175
    if input:wasPressed("up") and ItemStorage.yesCursor ~= 1 then
      ItemStorage.yesCursor = 1
      se("SE_SELECT")
    elseif input:wasPressed("down") and ItemStorage.yesCursor ~= 2 then
      ItemStorage.yesCursor = 2
      se("SE_SELECT")
    elseif input:wasPressed("a") or input:wasPressed("b") then
      se("SE_SELECT")
      if input:wasPressed("a") and ItemStorage.yesCursor == 1 then
        local e = items()[pos() + 1]
        set_message("gText_ThrewAwayVar2Var1s", { item_name(e.id), tostring(ItemStorage.quantity) })
        ItemStorage.state = "remove"
      else
        set_message(nil)
        ItemStorage.state = "list"
      end
    end
  elseif state == "remove" then
    if input:wasPressed("a") or input:wasPressed("b") then remove_item() end
  elseif state == "error" then
    -- pokeemerald/src/player_pc.c:1494
    if input:wasPressed("a") or input:wasPressed("b") then
      set_message(nil)
      ItemStorage.state = "list"
    end
  end
end

function ItemStorage.update()
  if ItemStorage.open then ItemStorage._frames = (ItemStorage._frames or 0) + 1 end
end

local function frame(tpl)
  Window.stdFrame(tpl)
  Window.fill(tpl, 1, 1, 1, 1)
end

-- pokeruby/src/player_pc.c:862
local function draw_list_rs()
  local tpl = WIN_RS.list
  frame(tpl)
  local ox = tpl.left * 8
  local list = items()
  local shown = page_items()
  local font = narrow()
  local ItemsData = require("src.core.game3.items_data")
  for i = 0, shown - 1 do
    local idx = ItemStorage.scroll + i
    local y = (i * 2 + 2) * 8
    local e = list[idx + 1]
    if not e then
      FrlgFont.draw(RomText.plain("gText_Cancel2"), ox, y,
        { font = "normal", colors = { fg = FrlgFont.STDPAL[1], bg = { 0, 0, 0, 0 }, shadow = FrlgFont.STDPAL[8] } })
      break
    end
    local colors = { fg = FrlgFont.STDPAL[ItemStorage.swapFrom == idx and 2 or 1], bg = { 0, 0, 0, 0 },
      shadow = FrlgFont.STDPAL[8] }
    FrlgFont.draw(item_name(e.id), ox, y, { font = "normal", colors = colors })
    local pocket = ItemsData.pocketOf(e.id)
    -- pokeruby/src/player_pc.c:815
    if pocket ~= "KEY_ITEMS" and not ItemsData.isHm(e.id) then
      local qx = 26 * 8
      FrlgFont.draw("×", qx, y, { font = "normal", colors = colors })
      local digits = tostring(tonumber(e.qty) or 0)
      local dx = qx + FrlgFont.measure("×", font) + (3 - #digits) * 6
      for c = 1, #digits do
        FrlgFont.draw(digits:sub(c, c), dx + (c - 1) * 6, y, { font = "normal", colors = colors })
      end
    end
  end
  require("src.ui.game3.rs.menu_cursor").draw(ox, 16 + ItemStorage.row * 16, 13 * 8)
end

local function draw_list()
  if is_rs() then return draw_list_rs() end
  local tpl = WIN.list
  frame(tpl)
  local ox, oy = tpl.left * 8, tpl.top * 8
  local rh = row_height()
  local list = items()
  local shown = page_items()
  for i = 0, shown - 1 do
    local idx = ItemStorage.scroll + i
    local y = oy + UP_TEXT_Y + i * rh
    local e = list[idx + 1]
    local label = e and item_name(e.id) or RomText.plain("gText_Cancel2")
    FrlgFont.draw(label, ox + ITEM_X, y, narrow())
    if e then
      -- pokeemerald/src/player_pc.c:830
      local q = RomText.plain("gText_xVar1", { stringVars = { string.format("%3d", tonumber(e.qty) or 0) } })
      FrlgFont.draw(q, ox + 104 - FrlgFont.measure(q, narrow()), y, narrow())
    end
    -- pokeemerald/src/player_pc.c:1030
    if ItemStorage.swapFrom == idx then Window.cursorPx(ox, y, { colors = SWAP_ARROW_COLORS }) end
  end
  if ItemStorage.state ~= "swap" then
    Window.cursorPx(ox, oy + UP_TEXT_Y + ItemStorage.row * rh)
  end
end

-- pokeemerald/src/player_pc.c:1339 ItemStorage_UpdateSwapLinePos
function ItemStorage.swapLine()
  if not ItemStorage.open or ItemStorage.state ~= "swap" or is_rs() then return nil end
  local y = 1 + (ItemStorage.row + 1) * 16
  for i = 1, #SWAP_LINE do SWAP_LINE[i].y = y end
  return SWAP_LINE
end

local function draw_swap_line()
  local sprites = ItemStorage.swapLine()
  if not sprites then return end
  local g = require("src.ui.game3.rse.pokeblock_gfx").of("rse/pokeblock")
  if swapLineImg.gfx ~= g then
    local pal = g:manifest().palettes.swap_line
    swapLineImg.gfx = g
    swapLineImg[0] = g:sprite("swap_line", 0, 16, 16, pal)
    swapLineImg[4] = g:sprite("swap_line", 4, 16, 16, pal)
  end
  love.graphics.setColor(1, 1, 1, 1)
  for i = 1, #sprites do
    local s = sprites[i]
    love.graphics.draw(swapLineImg[s.frame], s.x - 8, s.y - 8)
  end
end

-- pokeemerald/src/player_pc.c:1015
function ItemStorage.iconItem()
  local e = items()[(ItemStorage.state == "swap" and ItemStorage.swapFrom or pos()) + 1]
  return e and e.id or nil
end

local function draw_icon()
  local tpl = WIN.icon
  frame(tpl)
  local id = ItemStorage.iconItem()
  local BagChrome = require("src.ui.game3.rse.bag_chrome")
  local ItemsData = require("src.core.game3.items_data")
  local icon = id and ItemsData.toNumericId(id) or BagChrome.returnIconIndex()
  -- pokeemerald/src/player_pc.c:1110
  BagChrome.drawItemIcon(icon, 24 - 16, 80 - 16)
end

function ItemStorage.draw()
  if not ItemStorage.open then return end
  local rs = is_rs()
  local W = rs and WIN_RS or WIN
  local title = W.title
  frame(title)
  local t = RomText.plain(ItemStorage._toss and "gText_TossItem" or "gText_WithdrawItem")
  if rs then
    Window.printPx(t, title.left * 8, title.top * 8)
  else
    -- pokeemerald/src/player_pc.c:960
    Window.printPx(t, title.left * 8 + math.floor((104 - FrlgFont.measure(t)) / 2), title.top * 8 + 1)
  end
  draw_list()
  if not rs then draw_icon() end
  local m = W.message
  frame(m)
  local pitch = FrlgFont.linePitch()
  local y = m.top * 8 + 1
  for line in tostring(ItemStorage._message or ""):gmatch("[^\n]+") do
    Window.printPx(line, m.left * 8, y)
    y = y + pitch
  end
  if ItemStorage.state == "quantity" then
    local q = W.quantity
    frame(q)
    local s = RomText.plain("gText_xVar1", { stringVars = { string.format("%03d", ItemStorage.quantity) } })
    -- pokeemerald/src/player_pc.c:1361
    Window.printPx(s, q.left * 8 + math.floor((48 - FrlgFont.measure(s)) / 2), q.top * 8 + 1)
  elseif ItemStorage.state == "yesno" then
    local yn = W.yesno
    frame(yn)
    local ph = Window.optionHeight()
    Window.printPx(RomText.plain("gText_Yes"), yn.left * 8 + 8, yn.top * 8 + 1)
    Window.printPx(RomText.plain("gText_No"), yn.left * 8 + 8, yn.top * 8 + 1 + ph)
    Window.cursorPx(yn.left * 8, yn.top * 8 + 1 + (ItemStorage.yesCursor - 1) * ph)
  end
  draw_swap_line()
end

return ItemStorage
