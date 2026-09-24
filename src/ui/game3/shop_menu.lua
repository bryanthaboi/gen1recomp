-- FRLG Poké Mart (shop.c / buy_menu_helpers.c): BUY / SELL / SEE YA!
-- 1:1 pret GBA buy menu background, money box, stock list, in-bag popup, item icon, and description.

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local MoneyBox = require("src.ui.game3.money_box")
local RomText = require("src.core.game3.rom_text")

local ShopMenu = {}

ShopMenu.open = false
ShopMenu.mode = "root"
ShopMenu.cursor = 1
ShopMenu.scroll = 0
ShopMenu.qty = 1
ShopMenu.yesNoCursor = 1
-- src/shop.c:140 sShopMenuActions_BuySellQuit
ShopMenu.ROOT = {
  { id = "buy" },
  { id = "sell" },
  { id = "quit" },
}

local VISIBLE = 6

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local function money_of(session)
  return math.max(0, math.floor(tonumber(session and session.money) or 0))
end

local function set_money(session, amount)
  if not session then return end
  session.money = math.max(0, math.floor(tonumber(amount) or 0))
end

local function queue_shop_se(text, money)
  local n = 0
  for _ in tostring(text or ""):gmatch("[^\r\n]") do n = n + 1 end
  ShopMenu._shopSe = { frames = n, money = money } -- pokefirered/src/menu_helpers.c:29
end

local function tick_shop_se(force)
  local p = ShopMenu._shopSe
  if not p then return false end
  p.frames = p.frames - 1
  if not force and p.frames > 0 then return false end
  ShopMenu._shopSe = nil
  MoneyBox.update(p.money)
  se(248)
  return true
end

local function buy_price(itemId)
  local info = ItemsData.info(itemId)
  return math.max(0, math.floor(tonumber(info and info.price) or 0))
end


local function stock_rows(items)
  local rows = {}
  for _, id in ipairs(items or {}) do
    local name = ItemsData.displayName(id)
    local price = buy_price(id)
    local desc = ItemsData.description(id)
    rows[#rows + 1] = { id = id, name = name, price = price, description = desc }
  end
  return rows
end


local rows_cache = { key = false, rows = nil }
local function cached_rows(kind, src)
  local key = kind .. "|" .. tostring(src) .. "|" .. tostring(ShopMenu._rowsGen or 0)
  if rows_cache.key == key and rows_cache.rows then return rows_cache.rows end
  local rows
  rows = stock_rows(src)
  rows_cache.key, rows_cache.rows = key, rows
  return rows
end

function ShopMenu.show(opts)
  opts = opts or {}
  ShopMenu.open = true
  ShopMenu.mode = "root"
  ShopMenu.cursor = 1
  ShopMenu.scroll = 0
  ShopMenu.qty = 1
  ShopMenu.yesNoCursor = 1
  ShopMenu._pending = nil
  ShopMenu._shopSe = nil
  ShopMenu._fading = false
  ShopMenu._items = opts.items or {}
  ShopMenu._rowsGen = (ShopMenu._rowsGen or 0) + 1
  ShopMenu._session = opts.session
  ShopMenu._onClose = opts.onClose
  -- data/text/poke_mart.inc:1
  ShopMenu._status = RomText.box("Text_MayIHelpYou")
  local okMB, MoneyBox = pcall(require, "src.ui.game3.money_box")
  if okMB and MoneyBox and MoneyBox.hide then MoneyBox.hide() end
  local okC, Chrome = pcall(require, "src.ui.game3.chrome")
  if okC and Chrome and Chrome.invalidate then Chrome.invalidate() end
  Stack.push("shop", ShopMenu, { hideBelow = false })
  -- pokefirered/src/shop.c:205
end

function ShopMenu.close()
  ShopMenu.open = false
  Stack.pop("shop")
  local okMB, MoneyBox = pcall(require, "src.ui.game3.money_box")
  if okMB and MoneyBox and MoneyBox.hide then MoneyBox.hide() end
  local cb = ShopMenu._onClose
  ShopMenu._onClose = nil
  if cb then cb() end
end

-- pokefirered/src/main.c:480
function ShopMenu.reset()
  ShopMenu.open = false
  ShopMenu._fading = false
  ShopMenu.mode = "root"
  ShopMenu._onClose = nil
  ShopMenu._pending = nil
  ShopMenu._shopSe = nil
  ShopMenu._session = nil
end

function ShopMenu.isOpen()
  return ShopMenu.open
end

function ShopMenu.isShopCamera()
  return ShopMenu.open and ShopMenu.mode ~= "root"
end

local open_sell_bag

local function do_fade_transition(onDark, onDone)
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade and Fade.begin and love and love.graphics then
    ShopMenu._fading = true
    Fade.begin(Fade.MODE.TO_BLACK, 1, function()
      if onDark then onDark() end
      Fade.begin(Fade.MODE.FROM_BLACK, 1, function()
        ShopMenu._fading = false
        if onDone then onDone() end
      end)
    end)
  else
    if onDark then onDark() end
    if onDone then onDone() end
  end
end

local function clamp_buy_cursor()
  local rows = cached_rows("stock", ShopMenu._items)
  local total = #rows + 1 -- including CANCEL
  if ShopMenu.cursor > total then ShopMenu.cursor = total end
  if ShopMenu.cursor < 1 then ShopMenu.cursor = 1 end
  if ShopMenu.cursor <= ShopMenu.scroll then
    ShopMenu.scroll = ShopMenu.cursor - 1
  end
  if ShopMenu.cursor > ShopMenu.scroll + VISIBLE then
    ShopMenu.scroll = ShopMenu.cursor - VISIBLE
  end
  if ShopMenu.scroll < 0 then ShopMenu.scroll = 0 end
  return rows
end


local function begin_buy_qty(item)
  if not item then return end
  local session = ShopMenu._session
  local curMoney = money_of(session)
  if item.price > curMoney then
    ShopMenu._status = RomText.box("gText_YouDontHaveMoney")
    ShopMenu.mode = "buy_msg"
    ShopMenu._pending = nil
    se(5) -- pokefirered/src/shop.c:888
    return
  end
  ShopMenu._pending = item
  ShopMenu.qty = 1
  ShopMenu.mode = "buy_qty"
  -- src/shop.c:902
  ShopMenu._status = RomText.box("gText_Var1CertainlyHowMany", { stringVars = { item.name } })
  se(5)
end


local function commit_buy()
  local p = ShopMenu._pending
  local session = ShopMenu._session
  if not p or not session then return end
  ShopMenu._rowsGen = (ShopMenu._rowsGen or 0) + 1
  local cost = (p.price or 0) * ShopMenu.qty
  local curMoney = money_of(session)
  if cost > curMoney then
    ShopMenu._status = RomText.box("gText_YouDontHaveMoney")
    ShopMenu.mode = "buy_msg"
    ShopMenu._pending = nil
    return
  end
  local bag = session.bag
  if not bag then
    session.bag = Bag.new()
    bag = session.bag
  end
  -- src/shop.c:991
  if not Bag.canAdd(bag, p.id, ShopMenu.qty) or not Bag.add(bag, p.id, ShopMenu.qty) then
    ShopMenu._status = RomText.box("gText_NoMoreRoomForThis")
    ShopMenu.mode = "buy_msg"
    ShopMenu._pending = nil
    return
  end
  set_money(session, curMoney - cost)
  local Q=require("src.core.game3.quest_log_recorder")
  local rt=package.loaded["src.core.game3.runtime"]
  Q.event(session,ShopMenu.qty==1 and "BoughtItem" or "BoughtItemsIncludingItem",
    {D0=Q.location(rt and rt._game,session),D1=ItemsData.displayName(p.id),D2=cost})

  -- src/shop.c:985
  ShopMenu._status = RomText.box("gText_HereYouGoThankYou")

  queue_shop_se(ShopMenu._status, session.money) -- pokefirered/src/shop.c:999
  ShopMenu.mode = "buy_msg"
  ShopMenu._pending = nil
end


-- src/shop.c:281 Task_HandleShopMenuSell, :288 CB2_GoToSellMenu
open_sell_bag = function()
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  ShopMenu._fading = true
  local function go()
    ShopMenu._fading = false
    ShopMenu.mode = "sell"
    ShopMenu._status = nil
    if okF and Fade and Fade.clear then Fade.clear() end
    local session = ShopMenu._session
    require("src.ui.game3.bag_menu").show(session and session.bag, {
      session = session,
      location = "shop",
      -- src/shop.c:325 Task_ReturnToShopMenu
      onClose = function()
        ShopMenu.mode = "root"
        ShopMenu.cursor = 1
        ShopMenu._status = RomText.box("gText_AnythingElseICanHelp")
      end,
    })
  end
  if okF and Fade and Fade.begin then
    Fade.begin(Fade.MODE.TO_BLACK, 1, go)
  else
    go()
  end
end

function ShopMenu.handleInput(input)
  if not ShopMenu.open or ShopMenu._fading then return end

  if ShopMenu.mode == "buy_msg" then
    if input:wasPressed("a") or input:wasPressed("b") then
      ShopMenu.mode = "buy"
      ShopMenu._status = nil
      clamp_buy_cursor()
      if not tick_shop_se(true) then se(5) end -- pokefirered/src/shop.c:1008
    else
      tick_shop_se(false)
    end
    return
  end


  if ShopMenu.mode == "buy_confirm" then
    if input:wasPressed("up") or input:wasPressed("down") then
      ShopMenu.yesNoCursor = (ShopMenu.yesNoCursor == 1) and 2 or 1
      se(5)
    elseif input:wasPressed("a") then
      se(5) -- pokefirered/src/menu_helpers.c:52
      if ShopMenu.yesNoCursor == 1 then
        commit_buy()
      else
        ShopMenu.mode = "buy"
        ShopMenu._pending = nil
        ShopMenu._status = nil
      end
    elseif input:wasPressed("b") then
      ShopMenu.mode = "buy"
      ShopMenu._pending = nil
      ShopMenu._status = nil
      se(5) -- pokefirered/src/menu_helpers.c:57
    end
    return
  end


  if ShopMenu.mode == "buy_qty" then
    local p = ShopMenu._pending
    local session = ShopMenu._session
    local unit = p and p.price or 0
    local money = money_of(session)
    local maxQ = math.max(1, math.min(99, math.floor(money / math.max(1, unit))))

    if input:wasPressed("up") then
      ShopMenu.qty = math.min(maxQ, ShopMenu.qty + 1)
      se(5)
    elseif input:wasPressed("down") then
      ShopMenu.qty = math.max(1, ShopMenu.qty - 1)
      se(5)
    elseif input:wasPressed("right") then
      ShopMenu.qty = math.min(maxQ, ShopMenu.qty + 10)
      se(5)
    elseif input:wasPressed("left") then
      ShopMenu.qty = math.max(1, ShopMenu.qty - 10)
      se(5)
    elseif input:wasPressed("a") then
      ShopMenu.mode = "buy_confirm"
      ShopMenu.yesNoCursor = 1
      local totalCost = unit * ShopMenu.qty
      -- src/shop.c:958
      ShopMenu._status = RomText.box("gText_Var1AndYouWantedVar2",
        { stringVars = { p.name, tostring(ShopMenu.qty), tostring(totalCost) } })
      se(5)
    elseif input:wasPressed("b") then
      ShopMenu.mode = "buy"
      ShopMenu._pending = nil
      ShopMenu._status = nil
      se(5) -- pokefirered/src/shop.c:962
    end
    return
  end


  if ShopMenu.mode == "buy" then
    local rows = cached_rows("stock", ShopMenu._items)
    local total = #rows + 1

    if input:wasPressed("up") then
      ShopMenu.cursor = ((ShopMenu.cursor - 2) % total) + 1
      clamp_buy_cursor()
      se(5)
    elseif input:wasPressed("down") then
      ShopMenu.cursor = (ShopMenu.cursor % total) + 1
      clamp_buy_cursor()
      se(5)
    elseif input:wasPressed("a") then
      if ShopMenu.cursor > #rows then
        se(5) -- pokefirered/src/shop.c:884
        do_fade_transition(function()
          ShopMenu.mode = "root"
          ShopMenu.cursor = 1
          ShopMenu._status = RomText.plain("gText_AnythingElseICanHelp")
        end)
      else
        begin_buy_qty(rows[ShopMenu.cursor])
      end
    elseif input:wasPressed("b") then
      se(5) -- pokefirered/src/shop.c:884
      do_fade_transition(function()
        ShopMenu.mode = "root"
        ShopMenu.cursor = 1
        ShopMenu._status = RomText.plain("gText_AnythingElseICanHelp")
      end)
    end
    return
  end


  -- root mode
  if ShopMenu.mode == "root" then
    if input:wasPressed("up") then
      ShopMenu.cursor = ((ShopMenu.cursor - 2) % #ShopMenu.ROOT) + 1
      se(5)
    elseif input:wasPressed("down") then
      ShopMenu.cursor = (ShopMenu.cursor % #ShopMenu.ROOT) + 1
      se(5)
    elseif input:wasPressed("a") then
      local e = ShopMenu.ROOT[ShopMenu.cursor]
      if not e or e.id == "quit" then
        se(5) -- pokefirered/src/menu.c:376
        ShopMenu.close()
        return
      elseif e.id == "buy" then
        se(5)
        do_fade_transition(function()
          ShopMenu.mode = "buy"
          ShopMenu.cursor = 1
          ShopMenu.scroll = 0
          ShopMenu._status = nil
          ShopMenu._pending = nil
        end)
      elseif e.id == "sell" then
        se(5)
        open_sell_bag()
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      se(5) -- pokefirered/src/shop.c:265
      ShopMenu.close()
    end
  end
end

function ShopMenu.draw()
  if not ShopMenu.open then return end
  local session = ShopMenu._session

  local okSC, ShopChrome = pcall(require, "src.ui.game3.shop_chrome")
  local shopChrome = okSC and ShopChrome and ShopChrome.ready and ShopChrome.ready()
  local okBC, BagChrome = pcall(require, "src.ui.game3.bag_chrome")

  if ShopMenu.mode == "root" then
    -- Top-left Menu Box (sShopMenuWindowTemplate: tile 2, 1, 12, 6)
    Window.stdFrame(Window.template(2, 1, 12, 6))
    for i, e in ipairs(ShopMenu.ROOT) do
      local yPx = 10 + (i - 1) * 16
      if i == ShopMenu.cursor then Window.cursorPx(20, yPx) end
      Window.printPx(RomText.at("sShopMenuActions_BuySellQuit", i - 1), 28, yPx)
    end

    -- Bottom Clerk Dialogue Window
    Window.dialogueFrame()
    if ShopMenu._status then
      local lines = {}
      for line in tostring(ShopMenu._status):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
      end
      if #lines > 0 then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
      if #lines > 1 then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
    end
    return
  end

  if ShopMenu.mode == "sell" then return end
  local isInteractiveQty = (ShopMenu.mode == "buy_qty" or ShopMenu.mode == "buy_confirm")
  local isSpeech = isInteractiveQty or ShopMenu.mode == "buy_msg"

  if shopChrome then
    ShopChrome.drawBg(0, 0)
  end

  -- Top-left Money Window (Window 0: tile 1, 1, 8, 3 with border)
  Window.stdFrame(Window.template(1, 1, 8, 3))
  -- src/money.c:110, :86
  Window.printPx(RomText.plain("gText_TrainerCardMoney"), 8, 8)
  local moneyStr = RomText.plain("gText_PokedollarVar1", { stringVars = { tostring(money_of(session)) } })
  local mw = (FrlgFont.measure and FrlgFont.measure(moneyStr, { small = true })) or (6 * #moneyStr)
  Window.printPx(moneyStr, math.max(8, 72 - mw), 20, { small = true })

  -- Right Stock / Bag List
  local rows = cached_rows("stock", ShopMenu._items)
  local total = #rows + 1

  if ShopMenu.scroll > 0 then
    Window.print("▲", 26, 1)
  end
  if ShopMenu.scroll + VISIBLE < total then
    Window.print("▼", 26, 12)
  end

  local selId = nil
  local selDesc = nil

  for vis = 1, VISIBLE do
    local idx = ShopMenu.scroll + vis
    if idx > total then break end
    local y = 1 + (vis - 1) * 2
    if idx == ShopMenu.cursor then
      Window.cursor(11, y)
    end
    if idx > #rows then
      -- src/shop.c:525, :577
      Window.print(RomText.plain("gFameCheckerText_Cancel"), 12, y)
      if idx == ShopMenu.cursor then selDesc = RomText.plain("gText_QuitShopping") end
    else
      local r = rows[idx]
      if idx == ShopMenu.cursor then
        selId = r.id
        selDesc = r.description
      end
      Window.print(r.name, 12, y, { clipTiles = 9 })
      -- src/shop.c:611
      local pStr = RomText.plain("gText_PokedollarVar1", { stringVars = { tostring(r.price) } })
      local pw = (FrlgFont.measure and FrlgFont.measure(pStr)) or (8 * #pStr)
      Window.printPx(pStr, math.max(168, 222 - pw), y * 8)
    end
  end

  local activeId = (ShopMenu._pending and ShopMenu._pending.id) or selId

  -- Bottom Description Bar (Window 5) vs Speech Bubble (Window 2)
  if isSpeech and ShopMenu._status then
    -- When clerk is speaking (e.g. quantity selection or confirmation), draw dialogue bubble
    Window.dialogueFrame()
    local lines = {}
    for line in tostring(ShopMenu._status):gmatch("[^\r\n]+") do
      lines[#lines + 1] = line
    end
    if #lines > 0 then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
    if #lines > 1 then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
  else
    -- Standard browsing mode: 24×24 item icon inside white square + 2-3 line description
    if okBC and BagChrome and BagChrome.drawItemIcon and activeId then
      BagChrome.drawItemIcon(activeId, 8, 124)
    end
    if selDesc then
      local lines = {}
      for line in tostring(selDesc):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
      end
      local whiteColor = FrlgFont.COLOR.WHITE
      if #lines > 0 then Window.printPx(lines[1], 40, 117, { maxWidth = 192, colors = whiteColor }) end
      if #lines > 1 then Window.printPx(lines[2], 40, 131, { maxWidth = 192, colors = whiteColor }) end
      if #lines > 2 then Window.printPx(lines[3], 40, 145, { maxWidth = 192, colors = whiteColor }) end
    end
  end

  -- In-Bag Overlay Box (Window 1: tile 1, 11, 13, 2) — ONLY visible during quantity/purchase dialogue
  if isInteractiveQty and activeId then
    local inBagCount = 0
    if session and session.bag then
      inBagCount = Bag.get(session.bag, activeId)
    end
    Window.stdFrame(Window.template(1, 11, 13, 2))
    -- src/shop.c:917
    local inBag = RomText.plain("gText_InBagVar1", { stringVars = { "\1" } })
    local label, countStr = inBag:match("^(.-)%s*\1(.*)$")
    Window.printPx(label, 12, 89)
    countStr = tostring(inBagCount) .. countStr
    local cw = (FrlgFont.measure and FrlgFont.measure(countStr, { small = true })) or (6 * #countStr)
    Window.printPx(countStr, math.max(64, 106 - cw), 89, { small = true })
  end

  -- Quantity Selection Pop-up (Window 3: tile 17, 9, 12, 4)
  if (ShopMenu.mode == "buy_qty") and ShopMenu._pending then
    Window.stdFrame(Window.template(17, 9, 12, 4))
    local unit = ShopMenu._pending.price or 0
    -- Red scroll arrows at (152, 68) and (152, 100)
    love.graphics.setColor(220 / 255, 60 / 255, 30 / 255, 1)
    Window.printPx("▲", 152, 68)
    Window.printPx("▼", 152, 100)
    love.graphics.setColor(1, 1, 1, 1)

    local qtyStr = string.format("×%02d", ShopMenu.qty)
    Window.printPx(qtyStr, 138, 82, { small = true })
    local totalStr = RomText.plain("gText_PokedollarVar1", { stringVars = { tostring(unit * ShopMenu.qty) } })
    local tw = (FrlgFont.measure and FrlgFont.measure(totalStr, { small = true })) or (6 * #totalStr)
    Window.printPx(totalStr, math.max(170, 228 - tw), 82, { small = true })
  end

  -- YES / NO Confirmation Pop-up (Standard GBA tile 21, 9, 6, 4)
  if ShopMenu.mode == "buy_confirm" then
    Window.stdFrame(Window.template(21, 9, 6, 4))
    Window.printPx(RomText.plain("gText_Yes"), 184, 76)
    Window.printPx(RomText.plain("gText_No"), 184, 92)
    Window.cursorPx(174, ShopMenu.yesNoCursor == 2 and 92 or 76)
  end
end

return ShopMenu
