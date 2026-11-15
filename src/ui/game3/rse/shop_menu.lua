local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")

local RseShop = {}

-- pokeemerald/src/shop.c:67
RseShop.MART_NORMAL, RseShop.MART_DECOR, RseShop.MART_DECOR2 = "NORMAL", "DECOR", "DECOR2"
-- pokeemerald/src/shop.c:63
local MAX_ITEMS_SHOWN = 8
-- pokeemerald/include/constants/tv.h:5
local POKENEWS_SLATEPORT = 1
-- pokeemerald/include/constants/items.h:455
local MAX_BAG_ITEM_CAPACITY = 99
-- pokeemerald/include/constants/characters.h:74
local CHAR_SPACER = 0x77
-- include/constants/game_stat.h:42
local GAME_STAT_SHOPPED = 38

-- pokeemerald/src/shop.c:343
local WIN = {
  money = Window.template(1, 1, 10, 2),
  list = Window.template(14, 2, 15, 16),
  desc = Window.template(0, 13, 14, 6),
  inBag = Window.template(1, 11, 12, 2),
  qty = Window.template(18, 11, 10, 2),
  message = Window.template(2, 15, 27, 4),
  yesno = Window.template(21, 9, 5, 4),
}
RseShop.WIN = WIN

local function se(name)
  local SE = require("src.core.game3.se_ids")
  pcall(function() require("src.core.game3.audio").playSe(SE[name]) end)
end

local function money(shop)
  return math.max(0, math.floor(tonumber(shop._session and shop._session.money) or 0))
end

local function decor()
  return require("src.core.game3.rse.decoration_inventory")
end

local function is_decor(shop)
  return shop._martType ~= RseShop.MART_NORMAL
end

local function narrow()
  return { font = "narrow" }
end

-- pokeemerald/src/shop.c:1070
local function pokenews_discount(shop)
  local ok, Tv = pcall(require, "src.core.game3.rse.tv")
  if not ok then return 0 end
  local Rse = require("src.core.game3.rse.init")
  local active = Tv.isPokeNewsActive(shop._session, POKENEWS_SLATEPORT, function(kind)
    local r = Rse.call("tv", "shouldApplyPokeNews", "ShouldApplyPokeNewsEffect", nil, kind)
    return r == true
  end)
  return active and 1 or 0
end

local function unit_price(shop, id)
  if is_decor(shop) then
    local d = decor().info(id)
    return d and d.price or 0
  end
  local info = ItemsData.info(id)
  local p = math.max(0, math.floor(tonumber(info and info.price) or 0))
  if pokenews_discount(shop) == 1 then p = math.floor(p / 2) end
  return p
end

local function row_name(shop, id)
  if is_decor(shop) then
    local d = decor().info(id)
    return d and d.name or tostring(id)
  end
  return ItemsData.displayName(id)
end

local function row_desc(shop, id)
  if id == nil then return RomText.plain("gText_QuitShopping") end
  if is_decor(shop) then
    local d = decor().info(id)
    return d and d.description or ""
  end
  return ItemsData.description(id)
end

local function total(shop)
  return #shop._items + 1
end

local function shown(shop)
  return math.min(MAX_ITEMS_SHOWN, total(shop))
end

local function selected(shop)
  return shop._items[shop.scroll + shop.row + 1]
end

local function plain(shop, key, ctx)
  if shop._nativeShopPolicy then return shop._nativeShopPolicy.plain(key, ctx) end
  return RomText.plain(key, ctx)
end

local function say(shop, key, vars, after)
  shop._status = plain(shop, key, { stringVars = vars })
  shop._after = after
  shop.state = "msg"
end

local function menu_rows(shop)
  if is_decor(shop) then return { "buy", "quit" } end
  return { "buy", "sell", "quit" }
end
local LABELS = { buy = "gText_ShopBuy", sell = "gText_ShopSell", quit = "gText_ShopQuit" }

local function fade(shop, fn)
  local ok, Fade = pcall(require, "src.ui.game3.fade")
  if not (ok and Fade and Fade.begin and love and love.graphics) then
    fn()
    return
  end
  shop._fading = true
  Fade.begin(Fade.MODE.TO_BLACK, 1, function()
    fn()
    Fade.begin(Fade.MODE.FROM_BLACK, 1, function() shop._fading = false end)
  end)
end

-- pokeemerald/src/shop.c:465
local function back_to_menu(shop)
  shop.mode = "root"
  shop.state = "root"
  shop.cursor = 1
  shop._status = plain(shop, shop._martType == RseShop.MART_DECOR2 and "gText_CanIHelpWithAnythingElse"
    or "gText_AnythingElseICanHelp")
end

local function last_page(shop, key)
  local TextIR = require("src.core.game3.scripting.text_ir")
  local ir = shop._nativeShopPolicy and shop._nativeShopPolicy.ir(key) or RomText.ir(key)
  local start = 1
  for i, seg in ipairs(ir) do
    if seg.t == "para" then start = i + 1 end
  end
  local tail = {}
  for i = start, #ir do tail[#tail + 1] = ir[i] end
  return TextIR.toPlain(tail, {})
end

function RseShop.show(shop, opts)
  shop._nativeShopPolicy = opts.nativePolicy
  local mart = opts.mart
  shop._martType = (mart and mart.martType) or opts.martType or RseShop.MART_NORMAL
  shop.mode = "root"
  shop.state = "root"
  shop.cursor = 1
  shop.scroll, shop.row = 0, 0
  shop._fading = false
  -- pokeemerald/data/scripts/pokemart.inc:1
  shop._status = last_page(shop, "gText_HowMayIServeYou")
  -- pokeemerald/src/shop.c:1211
  shop._history = {}
end

-- pokeemerald/src/shop.c:1217
local function record_purchase(shop, id, qty)
  local h = shop._history or {}
  shop._history = h
  for _, row in ipairs(h) do
    if row.itemId == id and row.quantity ~= 0 then
      row.quantity = math.min(255, row.quantity + qty)
      return
    end
  end
  if #h < 3 then h[#h + 1] = { itemId = id, quantity = qty } end
end

-- pokeemerald/src/shop.c:444
local function quit(shop)
  require("src.core.game3.rse.init").call("tv", "tryPutSmartShopperOnAir", "TryPutSmartShopperOnAir", nil,
    shop._history or {})
  shop.close()
end

-- pokeemerald/src/shop.c:1003
local function after_purchase(shop, id, qty)
  se("SE_SELECT")
  local C = require("src.core.game3.constants").of(require("src.core.game3.profile").forSession(shop._session).id)
  local ball, premier = C:require("items", "ITEM_POKE_BALL"), C:require("items", "ITEM_PREMIER_BALL")
  if not is_decor(shop) and id == ball and qty >= 10 and Bag.add(shop._session.bag, premier, 1) then
    say(shop, "gText_ThrowInPremierBall", nil, function() shop.state = "list" end)
  else
    shop.state = "list"
  end
end

-- pokeemerald/src/shop.c:1110
local function subtract_money(shop, id, qty)
  local session = shop._session
  if type(session.gameStats) ~= "table" then session.gameStats = {} end
  local count = math.floor(tonumber(session.gameStats[GAME_STAT_SHOPPED]) or 0)
  session.gameStats[GAME_STAT_SHOPPED] = count < 0xFFFFFF and count + 1 or 0xFFFFFF
  shop._session.money = money(shop) - shop._totalCost
  se("SE_SHOP")
  shop._afterAnyKey = function() after_purchase(shop, id, qty) end
end

-- pokeemerald/src/shop.c:1080
local function try_purchase(shop)
  local id, qty = shop._itemId, shop.qty
  local policy = shop._nativeShopPolicy
  if policy and policy.canPurchase and not policy.canPurchase(shop) then
    say(shop, "gText_YouDontHaveMoney", nil, function() shop.state = "list" end)
    return
  end
  if not is_decor(shop) then
    local bag = shop._session.bag
    if Bag.canAdd(bag, id, qty) and Bag.add(bag, id, qty) then
      record_purchase(shop, id, qty)
      say(shop, "gText_HereYouGoThankYou")
      subtract_money(shop, id, qty)
    else
      say(shop, "gText_NoMoreRoomForThis", nil, function() shop.state = "list" end)
    end
    return
  end
  if decor().add(id, shop._session) then
    say(shop, shop._martType == RseShop.MART_DECOR and "gText_ThankYouIllSendItHome" or "gText_ThanksIllSendItHome")
    subtract_money(shop, id, qty)
  else
    say(shop, "gText_SpaceForVar1Full", { row_name(shop, id) }, function() shop.state = "list" end)
  end
end

-- pokeemerald/src/shop.c:975
local function choose_item(shop, id)
  shop._itemId = id
  shop.qty = 1
  shop._totalCost = unit_price(shop, id)
  if money(shop) < shop._totalCost then
    say(shop, "gText_YouDontHaveMoney", nil, function() shop.state = "list" end)
    return
  end
  if not is_decor(shop) then
    local name = row_name(shop, id)
    if ItemsData.pocketOf(id) == "TM_CASE" then
      local Pokemon = require("src.core.game3.pokemon")
      local move = Pokemon.moveFromTmItem and Pokemon.moveFromTmItem(id)
      say(shop, "gText_Var1CertainlyHowMany2", { name, move and Pokemon.moveName(move) or "" })
    else
      say(shop, "gText_Var1CertainlyHowMany", { name })
    end
    -- pokeemerald/src/shop.c:1034
    local maxQ = math.floor(money(shop) / math.max(1, shop._totalCost))
    shop._maxQty = math.min(MAX_BAG_ITEM_CAPACITY, maxQ)
    shop.state = "qty"
  else
    local key = shop._martType == RseShop.MART_DECOR and "gText_Var1IsItThatllBeVar2" or "gText_YouWantedVar1ThatllBeVar2"
    say(shop, key, { row_name(shop, id), tostring(shop._totalCost) })
    shop.yesCursor = 1
    shop.state = "confirm"
  end
end

-- pokeemerald/src/menu_helpers.c:212
local function adjust_quantity(shop, input)
  local q, max = shop.qty, math.max(1, shop._maxQty or 1)
  if input:wasPressed("up") then
    q = q + 1
    if q > max then q = 1 end
  elseif input:wasPressed("down") then
    q = q - 1
    if q <= 0 then q = max end
  elseif input:wasPressed("right") then
    if q == max then return false end
    q = math.min(max, q + 10)
  elseif input:wasPressed("left") then
    if q == 1 then return false end
    q = math.max(1, q - 10)
  else
    return false
  end
  if q == shop.qty then return false end
  shop.qty = q
  shop._totalCost = unit_price(shop, shop._itemId) * q
  se("SE_SELECT")
  return true
end

-- pokeemerald/src/list_menu.c:438
local function step(shop, down)
  if shop._nativeShopPolicy then return shop._nativeShopPolicy.step(shop, down) end
  local n, s = total(shop), shown(shop)
  local row, scroll = shop.row, shop.scroll
  if not down then
    local newRow = s == 1 and 0 or (s - (math.floor(s / 2) + s % 2) - 1)
    if scroll == 0 then
      if row == 0 then return false end
      shop.row = row - 1
    elseif row > newRow then
      shop.row = row - 1
    else
      shop.row, shop.scroll = newRow, scroll - 1
    end
  else
    local newRow = s == 1 and 0 or (math.floor(s / 2) + s % 2)
    if scroll == n - s then
      if row >= s - 1 then return false end
      shop.row = row + 1
    elseif row < newRow then
      shop.row = row + 1
    else
      shop.row, shop.scroll = newRow, scroll + 1
    end
  end
  return true
end

local function open_sell(shop)
  shop.state = "sell"
  shop.mode = "sell"
  local sess = shop._session
  local ok, Fade = pcall(require, "src.ui.game3.fade")
  if ok and Fade and Fade.clear then Fade.clear() end
  require("src.ui.game3.bag_menu").show(sess and sess.bag, {
    session = sess,
    location = "shop",
    onClose = function() back_to_menu(shop) end,
  })
end

function RseShop.handleInput(shop, input)
  if shop._fading then return end
  local st = shop.state
  if st == "root" then
    local rows = menu_rows(shop)
    -- pokeemerald/src/shop.c:254
    if input:wasPressed("up") and shop.cursor > 1 then
      shop.cursor = shop.cursor - 1
      se("SE_SELECT")
    elseif input:wasPressed("down") and shop.cursor < #rows then
      shop.cursor = shop.cursor + 1
      se("SE_SELECT")
    elseif input:wasPressed("a") then
      se("SE_SELECT")
      local id = rows[shop.cursor]
      if id == "buy" then
        fade(shop, function()
          shop.mode = "buy"
          shop.state = "list"
          shop.scroll, shop.row = 0, 0
          shop._status = nil
        end)
      elseif id == "sell" then
        fade(shop, function() open_sell(shop) end)
      else
        quit(shop)
      end
    elseif input:wasPressed("b") then
      se("SE_SELECT")
      quit(shop)
    end
    return
  end
  if st == "list" then
    if input:wasPressed("up") then
      if step(shop, false) then se("SE_SELECT") end
    elseif input:wasPressed("down") then
      if step(shop, true) then se("SE_SELECT") end
    elseif input:wasPressed("a") then
      se("SE_SELECT")
      local id = selected(shop)
      if id == nil then
        fade(shop, function() back_to_menu(shop) end)
      else
        choose_item(shop, id)
      end
    elseif input:wasPressed("b") then
      se("SE_SELECT")
      fade(shop, function() back_to_menu(shop) end)
    end
    return
  end
  if st == "msg" then
    if input:wasPressed("a") or input:wasPressed("b") then
      local anyKey = shop._afterAnyKey
      local after = shop._after
      shop._afterAnyKey, shop._after = nil, nil
      shop._status = nil
      if anyKey then anyKey() elseif after then after() else shop.state = "list" end
    end
    return
  end
  if st == "qty" then
    if adjust_quantity(shop, input) then return end
    if input:wasPressed("a") then
      se("SE_SELECT")
      -- pokeemerald/src/shop.c:1054
      say(shop, "gText_Var1AndYouWantedVar2", { row_name(shop, shop._itemId), tostring(shop.qty), tostring(shop._totalCost) })
      shop.yesCursor = 1
      shop.state = "confirm"
    elseif input:wasPressed("b") then
      se("SE_SELECT")
      shop._status = nil
      shop.state = "list"
    end
    return
  end
  if st == "confirm" then
    if input:wasPressed("up") and shop.yesCursor ~= 1 then
      shop.yesCursor = 1
      se("SE_SELECT")
    elseif input:wasPressed("down") and shop.yesCursor ~= 2 then
      shop.yesCursor = 2
      se("SE_SELECT")
    elseif input:wasPressed("a") then
      se("SE_SELECT")
      if shop.yesCursor == 1 then
        try_purchase(shop)
      else
        shop._status = nil
        shop.state = "list"
      end
    elseif input:wasPressed("b") then
      se("SE_SELECT")
      shop._status = nil
      shop.state = "list"
    end
  end
end

local function frame(tpl)
  Window.stdFrame(tpl)
  Window.fill(tpl, 1, 1, 1, 1)
end

local function draw_message(shop, text)
  Window.dialogueFrame()
  local y = WIN.message.top * 8 + 1
  for line in tostring(text or ""):gmatch("[^\n]+") do
    Window.printPx(line, WIN.message.left * 8, y)
    y = y + FrlgFont.linePitch()
  end
end

local function draw_money(shop, tpl, x, y)
  local s = tostring(money(shop))
  local pad = math.max(0, 6 - #s)
  local w = FrlgFont.advance(CHAR_SPACER)
  -- pokeemerald/src/money.c:138
  Window.printPx(RomText.plain("gText_PokedollarVar1", { stringVars = { s } }), tpl.left * 8 + x + pad * w, tpl.top * 8 + y)
end
RseShop.drawMoneyAmount = function(shop, tpl, amount)
  local s = tostring(amount)
  local pad = math.max(0, 6 - #s)
  local w = FrlgFont.advance(CHAR_SPACER)
  Window.printPx(RomText.plain("gText_PokedollarVar1", { stringVars = { s } }), tpl.left * 8 + 38 + pad * w, tpl.top * 8 + 1)
end

local labelImage

local function draw_money_label()
  if labelImage == nil then
    local rel = "data/generated/gba/items/shop/money_label.rgba"
    local bytes = require("src.core.game3.dataset").cache():read(rel)
    if bytes and #bytes == 32 * 16 * 4 then
      labelImage = love.graphics.newImage(love.image.newImageData(32, 16, "rgba8", bytes))
      labelImage:setFilter("nearest", "nearest")
    else
      labelImage = false
    end
  end
  if labelImage then
    love.graphics.setColor(1, 1, 1, 1)
    -- pokeemerald/src/shop.c:772
    love.graphics.draw(labelImage, 19 - 16, 11 - 8)
  end
end

RseShop.drawMoneyBox = function(amount)
  local m = WIN.money
  Window.stdFrame(m)
  Window.fill(m, 1, 1, 1, 1)
  draw_money_label()
  RseShop.drawMoneyAmount(nil, m, amount)
end

local iconsImage
local blankIcons = {}

-- pokeemerald/src/decoration.c:2103
local function draw_object_icon(id, x, y)
  local Decor = require("src.core.game3.rse.decoration")
  local d = Decor.info(id)
  if not d then return end
  love.graphics.setColor(1, 1, 1, 1)
  if d.permission == Decor.PERM.SPRITE then
    local spr = require("src.core.game3.ow_sprites").getDraw(d.tiles[1])
    local q = spr and spr.quads and spr.quads[0]
    if q then love.graphics.draw(spr.image, q, x - spr.width / 2, y - spr.height / 2) end
    return
  end
  local NT = require("src.core.game3.tileset_native")
  -- pokeemerald/src/decoration.c:2117
  local ts = NT.get(Decor.ICON_PAIR)
  if not ts then return end
  local w, h = Decor.dims(id)
  -- pokeemerald/src/decoration.c:2159
  if id == Decor.DECOR_SILVER_SHIELD or id == Decor.DECOR_GOLD_SHIELD then y = y - 4 end
  local x0, y0 = x - w * 8, y - h * 8
  for j = 0, h - 1 do
    for i = 0, w - 1 do
      local tile = d.tiles[j * w + i + 1] or 0
      local slot = NT.slotFor(ts, tile + Decor.PRIMARY)
      -- pokeemerald/src/data/decoration/tilemaps.h:112
      local img = Decor.layerType(tile) == 1 and ts.midImage or ts.overImage
      local q = img and slot and NT.quad(ts, slot)
      if q then love.graphics.draw(img, q, x0 + i * 16, y0 + j * 16) end
    end
  end
end

local function draw_icon(shop, id)
  if is_decor(shop) and id ~= nil then
    -- pokeruby/shop.c:550
    if decor().data().nativeIcons == false then return end
    if blankIcons[id] then return draw_object_icon(id, 20, 84) end
    if iconsImage == nil then
      local rel = "data/generated/gba/decorations/icons.rgba"
      local bytes = require("src.core.game3.dataset").cache():read(rel)
      local n = bytes and math.floor(#bytes / (24 * 24 * 4)) or 0
      if n > 0 then
        local stride = 24 * 24 * 4
        for k = 0, n - 1 do
          local chunk = bytes:sub(k * stride + 1, (k + 1) * stride)
          if not chunk:find("[^%z]") then blankIcons[k] = true end
        end
        iconsImage = love.graphics.newImage(love.image.newImageData(24, 24 * n, "rgba8", bytes))
        iconsImage:setFilter("nearest", "nearest")
      else
        iconsImage = false
      end
    end
    if blankIcons[id] then return draw_object_icon(id, 20, 84) end
    if iconsImage then
      local _, h = iconsImage:getDimensions()
      love.graphics.setColor(1, 1, 1, 1)
      -- pokeemerald/src/shop.c:699
      love.graphics.draw(iconsImage, love.graphics.newQuad(0, id * 24, 24, 24, 24, h), 20 - 12, 84 - 12)
    end
    return
  end
  local BagChrome = require("src.ui.game3.rse.bag_chrome")
  local icon = id ~= nil and ItemsData.toNumericId(id) or BagChrome.returnIconIndex()
  -- pokeemerald/src/shop.c:693
  BagChrome.drawItemIcon(icon, 24 - 16, 88 - 16)
end

function RseShop.draw(shop)
  if shop._nativeShopPolicy then return shop._nativeShopPolicy.draw(shop) end
  if shop.state == "root" then
    local rows = menu_rows(shop)
    local labels, w = {}, 0
    for i, id in ipairs(rows) do
      labels[i] = RomText.plain(LABELS[id])
      w = math.max(w, FrlgFont.measure(labels[i]))
    end
    -- pokeemerald/src/shop.c:201
    local tpl = Window.template(2, 1, math.floor((w + 8 + 7) / 8), #rows * 2)
    frame(tpl)
    local pitch = Window.optionHeight()
    for i, l in ipairs(labels) do
      local y = tpl.top * 8 + 1 + (i - 1) * pitch
      Window.printPx(l, tpl.left * 8 + 8, y)
      if i == shop.cursor then Window.cursorPx(tpl.left * 8, y) end
    end
    draw_message(shop, shop._status)
    return
  end
  if shop.state == "sell" then return end
  local okSC, ShopChrome = pcall(require, "src.ui.game3.shop_chrome")
  if okSC and ShopChrome.ready and ShopChrome.ready() then ShopChrome.drawBg(0, 0) end
  local m = WIN.money
  Window.stdFrame(m)
  Window.fill(m, 1, 1, 1, 1)
  draw_money_label()
  draw_money(shop, m, 38, 1)
  local l = WIN.list
  local ox, oy = l.left * 8, l.top * 8
  local face = FrlgFont.face and FrlgFont.face(narrow())
  local rh = face and face.height or 16
  for i = 0, shown(shop) - 1 do
    local idx = shop.scroll + i + 1
    local id = shop._items[idx]
    local y = oy + 1 + i * rh
    FrlgFont.draw(id and row_name(shop, id) or RomText.plain("gText_Cancel2"), ox + 8, y, narrow())
    if id then
      -- pokeemerald/src/shop.c:627
      local p = RomText.plain("gText_PokedollarVar1", { stringVars = { tostring(unit_price(shop, id)) } })
      FrlgFont.draw(p, ox + 120 - FrlgFont.measure(p, narrow()), y, narrow())
    end
  end
  local busy = shop.state ~= "list"
  local cy = oy + 1 + shop.row * rh
  if busy then
    Window.cursorPx(ox, cy, { colors = { fg = FrlgFont.STDPAL[3], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] } })
  else
    Window.cursorPx(ox, cy)
  end
  local sel = busy and shop._itemId or selected(shop)
  draw_icon(shop, sel)
  if not busy then
    local d = WIN.desc
    local y = d.top * 8 + 1
    for line in tostring(row_desc(shop, sel)):gmatch("[^\n]+") do
      Window.printPx(line, d.left * 8 + 3, y)
      y = y + FrlgFont.linePitch()
    end
  end
  if shop.state == "qty" then
    local b = WIN.inBag
    frame(b)
    local have = Bag.get(shop._session.bag, shop._itemId)
    -- pokeemerald/src/shop.c:1027
    Window.printPx(RomText.plain("gText_InBagVar1", { stringVars = { string.format("%4d", have) } }), b.left * 8, b.top * 8 + 1)
    local q = WIN.qty
    frame(q)
    Window.printPx(RomText.plain("gText_xVar1", { stringVars = { string.format("%02d", shop.qty) } }), q.left * 8, q.top * 8 + 1)
    RseShop.drawMoneyAmount(shop, q, shop._totalCost)
  elseif shop.state == "confirm" then
    local yn = WIN.yesno
    frame(yn)
    local pitch = Window.optionHeight()
    Window.printPx(RomText.plain("gText_Yes"), yn.left * 8 + 8, yn.top * 8 + 1)
    Window.printPx(RomText.plain("gText_No"), yn.left * 8 + 8, yn.top * 8 + 1 + pitch)
    Window.cursorPx(yn.left * 8, yn.top * 8 + 1 + (shop.yesCursor - 1) * pitch)
  end
  if shop._status and (shop.state == "msg" or shop.state == "confirm" or shop.state == "qty") then
    draw_message(shop, shop._status)
  end
end

-- pokeemerald/src/shop.c:753
RseShop.CAMERA_OFFSET = { x = -4, y = -4 }

return RseShop
