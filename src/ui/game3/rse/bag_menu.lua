local BagChrome = require("src.ui.game3.rse.bag_chrome")
local Kit = require("src.ui.game3.rse.scene_kit")
local FrlgFont = require("src.ui.game3.frlg_font")
local Window = require("src.ui.game3.window")
local Chrome = require("src.ui.game3.chrome")
local RomText = require("src.core.game3.rom_text")
local ItemsData = require("src.core.game3.items_data")

local RseBag = {}

-- pokeemerald/src/item_menu.c:68
RseBag.MAX_SHOWN = 8
-- pokeemerald/src/item_menu.c:393
RseBag.LIST = { left = 14, top = 2, width = 15, height = 16 }
RseBag.DESC = { left = 0, top = 13, width = 14, height = 6 }
RseBag.POCKET_NAME = { left = 4, top = 1, width = 8, height = 2 }

-- pokeemerald/src/item_menu_icons.c:94
RseBag.BAG_FRAME = { ITEMS = 1, KEY_ITEMS = 2, POKE_BALLS = 3, TM_CASE = 4, BERRY_POUCH = 5 }
-- pokeemerald/src/item_menu_icons.c:110
RseBag.SHAKE = { -2, -4, -2, 0, 2, 4, 2, 0, -2, -4, -2, 0 }

-- pokeemerald/src/item_menu.c:266
RseBag.ACTION_TEXT = {
  USE = "gMenuText_Use", TOSS = "gMenuText_Toss", SET = "gMenuText_Register", GIVE = "gMenuText_Give",
  CANCEL = "gText_Cancel2", CHECK = "gMenuText_Check", WALK = "gMenuText_Walk", DESELECT = "gMenuText_Deselect",
  CHECK_TAG = "gMenuText_CheckTag", OPEN = "gMenuText_Use", CONFIRM = "gMenuText_Confirm",
}

-- pokeemerald/src/item_menu.c:286
RseBag.GRIDS = {
  ITEMS = { "USE", "GIVE", "TOSS", "CANCEL" },
  KEY_ITEMS = { "USE", "SET", false, "CANCEL" },
  POKE_BALLS = { "GIVE", false, "TOSS", "CANCEL" },
  TM_CASE = { "USE", "GIVE", false, "CANCEL" },
  BERRY_POUCH = { "CHECK_TAG", false, "USE", "GIVE", "TOSS", "CANCEL" },
}

-- pokeemerald/include/item_menu.h:9
RseBag.LOCATION = { battle = 1, party = 2, shop = 3, berry_tree = 4, blender = 5, itempc = 6, pcbox = 11 }

local st = {
  scroll = {},
  cursor = {},
  lastPocket = nil,
  lastCursor = nil,
  lastMode = nil,
  grid = nil,
  gridPos = 0,
  shake = nil,
  switchY = nil,
  ball = nil,
  k = 0,
}
RseBag._st = st

local function se(name)
  pcall(function() require("src.core.game3.audio").playSe(name) end)
end

local function ui()
  local ok, Profile = pcall(require, "src.core.game3.profile")
  local row = ok and Profile.forSession(nil) or nil
  return row and row.ui or {}
end

local function sound(key, default)
  local s = ui().sounds
  return (s and s[key]) or default
end

local function female(Bag)
  local s = Bag._session
  return s and (s.gender == 1 or s.gender == "female" or s.playerGender == 1) or false
end

local function filtered(input, blocked)
  return setmetatable({}, { __index = function(_, k)
    if k == "wasPressed" then
      return function(_, key) if blocked[key] then return false end return input:wasPressed(key) end
    elseif k == "isDown" then
      return function(_, key)
        if blocked[key] or not input.isDown then return false end
        return input:isDown(key)
      end
    end
    local v = input[k]
    if type(v) == "function" then return function(_, ...) return v(input, ...) end end
    return v
  end })
end

local function pocketOrder()
  return ItemsData.BAG_POCKET_ORDER
end

local function total(Bag)
  return #Bag.list() + 1
end

local function shown(n)
  return math.min(RseBag.MAX_SHOWN, n)
end

-- pokeemerald/src/list_menu.c:694
local function fixScroll(Bag)
  local p = Bag.pocketIdx
  local n = total(Bag)
  local s = shown(n)
  local scroll = st.scroll[p] or 0
  local cur = Bag.cursor
  if cur > n then cur = n end
  if cur < 1 then cur = 1 end
  if cur <= scroll then scroll = cur - 1 end
  if cur > scroll + s then scroll = cur - s end
  if scroll > n - s then scroll = n - s end
  if scroll < 0 then scroll = 0 end
  st.scroll[p] = scroll
  return scroll, s, n
end

-- pokeemerald/src/list_menu.c:694
local function moveCursor(Bag, down)
  local n = total(Bag)
  local s = shown(n)
  local scroll = select(1, fixScroll(Bag))
  local row = Bag.cursor - scroll - 1
  local newRow
  if not down then
    newRow = (s == 1) and 0 or (s - (math.floor(s / 2) + s % 2) - 1)
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
    newRow = (s == 1) and 0 or (math.floor(s / 2) + s % 2)
    if scroll == n - s then
      if row >= s - 1 then return false end
      row = row + 1
    elseif row < newRow then
      row = row + 1
    else
      row = newRow
      scroll = scroll + 1
    end
  end
  st.scroll[Bag.pocketIdx] = scroll
  Bag.cursor = scroll + row + 1
  Bag.scroll = scroll
  return true
end

local function startShake()
  if st.shake == nil or st.shake >= #RseBag.SHAKE then st.shake = 0 end
end

-- pokeemerald/src/item_menu.c:1313
local function switchPocket(Bag, dir)
  local order = pocketOrder()
  st.cursor[Bag.pocketIdx] = Bag.cursor
  local p = ((Bag.pocketIdx - 1 + dir) % #order) + 1
  Bag.pocketIdx = p
  Bag.cursor = st.cursor[p] or 1
  Bag._switch = { dir = dir, k = 0 }
  Bag._bagAnim = { n = 0 }
  fixScroll(Bag)
  st.switchY = -5
  st.ball = { k = 0, dir = dir }
  se(sound("bagPocket", "SE_SELECT"))
end

local function actionNames(Bag)
  local out = {}
  for i, a in ipairs(Bag.ACTIONS or {}) do out[a] = i end
  return out
end

local function buildGrid(Bag)
  local names = actionNames(Bag)
  local tpl = (not Bag._battle and Bag._location == nil) and RseBag.GRIDS[Bag.currentPocket()] or nil
  local cells = {}
  if tpl then
    local usable = 0
    for i, a in ipairs(tpl) do
      local idx = a and names[a] or nil
      cells[i] = idx and { name = a, idx = idx } or false
      if idx then usable = usable + 1 end
    end
    if usable == #(Bag.ACTIONS or {}) then
      return { cols = 2, rows = #tpl / 2, cells = cells }
    end
  end
  cells = {}
  for i, a in ipairs(Bag.ACTIONS or {}) do cells[i] = { name = a, idx = i } end
  return { cols = 1, rows = #cells, cells = cells }
end

local function firstCell(grid)
  for i, c in ipairs(grid.cells) do if c then return i - 1 end end
  return 0
end

local function syncActionCursor(Bag)
  local c = st.grid and st.grid.cells[st.gridPos + 1]
  if c then Bag.actionCursor = c.idx end
end

-- pokeemerald/src/item_menu.c:1712
local function moveGrid(Bag, input)
  local g = st.grid
  if not g then return false end
  local pos = st.gridPos
  local cols = g.cols
  local target
  if input:wasPressed("up") then target = pos - cols
  elseif input:wasPressed("down") then target = pos + cols
  elseif cols > 1 and input:wasPressed("left") and pos % cols > 0 then target = pos - 1
  elseif cols > 1 and input:wasPressed("right") and pos % cols < cols - 1 then target = pos + 1
  end
  if target == nil then return false end
  if target >= 0 and target < #g.cells and g.cells[target + 1] then
    st.gridPos = target
    syncActionCursor(Bag)
    se("SE_SELECT")
  end
  return true
end

local function tick(Bag)
  st.k = st.k + 1
  if st.shake then
    st.shake = st.shake + 1
    if st.shake > #RseBag.SHAKE then st.shake = nil end
  end
  if st.switchY then
    st.switchY = st.switchY + 1
    if st.switchY >= 0 then st.switchY = nil end
  end
  if st.ball then
    st.ball.k = st.ball.k + 1
    if st.ball.k > 16 then st.ball = nil end
  end
  if Bag.mode == "action" and st.lastMode ~= "action" then
    st.grid = buildGrid(Bag)
    st.gridPos = firstCell(st.grid)
    syncActionCursor(Bag)
  elseif Bag.mode ~= "action" then
    st.grid = nil
  end
  st.lastMode = Bag.mode
end

function RseBag.handleInput(input, Bag)
  Bag = Bag or require("src.ui.game3.bag_menu")
  if not input then return Bag.handleInput(input) end
  if Bag._pokedude or Bag._statBoost or Bag._open or Bag._exit then
    require("src.ui.game3.screens").withTextAliases(Bag._session, Bag.handleInput, input)
    tick(Bag)
    return
  end
  local blocked = {}
  if Bag.mode == "move" then
    -- pokeemerald/src/item_menu.c:1447 Task_HandleSwappingItemsInput
    if not Bag._switch and not input:wasPressed("select") then
      local down = input:wasPressed("down")
      local up = input:wasPressed("up")
      if (up or down) and moveCursor(Bag, down) then
        se(sound("bagCursor", "SE_SELECT"))
        startShake()
      end
    end
    blocked = { up = true, down = true, left = true, right = true, l = true, r = true }
  elseif Bag.mode == "list" then
    local lr = require("src.core.game3.options").lrMode(Bag._session)
    local dir = 0
    if Bag._location ~= "itempc" and Bag._location ~= "berry_tree" and Bag._location ~= "blender" then
      if input:wasPressed("left") or (lr and input:wasPressed("l")) then dir = -1
      elseif input:wasPressed("right") or (lr and input:wasPressed("r")) then dir = 1 end
    end
    if dir ~= 0 then
      switchPocket(Bag, dir)
    elseif not Bag._switch then
      local down = input:wasPressed("down")
      local up = input:wasPressed("up")
      if (up or down) and moveCursor(Bag, down) then
        se(sound("bagCursor", "SE_SELECT"))
        startShake()
      end
    end
    blocked = { up = true, down = true, left = true, right = true, l = true, r = true }
  elseif Bag.mode == "action" then
    if st.lastMode ~= "action" then tick(Bag) end
    if moveGrid(Bag, input) or input:wasPressed("left") or input:wasPressed("right")
        or input:wasPressed("up") or input:wasPressed("down") then
      blocked = { up = true, down = true, left = true, right = true }
    end
    syncActionCursor(Bag)
  end
  require("src.ui.game3.screens").withTextAliases(Bag._session, Bag.handleInput,
    next(blocked) and filtered(input, blocked) or input)
  tick(Bag)
end

local function descColors(pal)
  return { fg = BagChrome.color(pal, 17), shadow = BagChrome.color(pal, 19), bg = { 0, 0, 0, 0 } }
end

local function pocketNameColors(pal)
  return { fg = BagChrome.color(pal, 17), shadow = BagChrome.color(pal, 20), bg = { 0, 0, 0, 0 } }
end

local function grayCursorColors(pal)
  return { fg = BagChrome.color(pal, 19), shadow = BagChrome.color(pal, 22), bg = { 0, 0, 0, 0 } }
end

-- pokeemerald/src/text.c:1063
local function irString(key, vars)
  local out = {}
  for _, node in ipairs(RomText.ir(key)) do
    if node.t == "text" then out[#out + 1] = node.s
    elseif node.t == "strvar" then out[#out + 1] = vars[node.n] or ""
    elseif node.t == "ext" and (node.cmd == 0x11 or node.cmd == 0x13) then
      out[#out + 1] = string.char(0xFC, node.cmd, node.args and node.args[1] or 0)
    end
  end
  return table.concat(out)
end
RseBag.irString = irString

-- pokeemerald/src/item_menu.c:896
local function itemLabel(pocket, row)
  if pocket == "TM_CASE" then
    local Pokemon = require("src.core.game3.pokemon")
    local move = Pokemon.moveFromTmItem(row.id)
    local moveName = move and Pokemon.moveName(move) or row.name
    if ItemsData.isHm(row.id) then
      return irString("gText_NumberItem_HM", { tostring(ItemsData.tmNumber(row.id)), moveName }), true
    end
    return irString("gText_NumberItem_TMBerry", { string.format("%02d", ItemsData.tmNumber(row.id) or 0), moveName })
  elseif pocket == "BERRY_POUCH" then
    return irString("gText_NumberItem_TMBerry", { string.format("%02d", ItemsData.berryNumber(row.id) or 0), row.name })
  end
  return row.name
end

local function quantityText(pocket, qty)
  -- pokeemerald/src/item_menu.c:975
  local digits = pocket == "BERRY_POUCH" and 3 or 2
  return RomText.plain("gText_xVar1", { stringVars = { string.format("%" .. digits .. "d", qty or 1) } })
end

local function drawList(Bag, pocket, rows, pal, selected)
  local scroll, s = fixScroll(Bag)
  local L = RseBag.LIST
  local x0, y0 = L.left * 8, L.top * 8
  local colors = descColors(pal)
  local session = Bag._session
  local registered = session and ItemsData.toNumericId(session.registeredItem)
  local m = BagChrome.manifest()
  for i = 1, s do
    local idx = scroll + i
    local y = y0 + 1 + (i - 1) * 16
    local r = rows[idx]
    if Bag.mode == "move" then
      if idx == Bag.moveFrom then
        -- pokeemerald/src/item_menu.c:958
        FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, x0, y, { colors = grayCursorColors(pal) })
      end
    elseif idx == Bag.cursor then
      local cc = selected and grayCursorColors(pal) or colors
      FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, x0, y, { colors = cc })
    end
    if not r then
      FrlgFont.draw(RomText.plain("gText_CloseBag"), x0 + 8, y, { font = "narrow", colors = colors })
    else
      local label, isHm = itemLabel(pocket, r)
      if isHm and m then
        local img = Kit.image(m.hm)
        if img then love.graphics.setColor(1, 1, 1, 1) love.graphics.draw(img, x0 + 8, y - 1) end
      end
      FrlgFont.draw(label, x0 + 8, y, { font = "narrow", colors = colors })
      local info = r.info or ItemsData.info(r.id)
      local important = info and (tonumber(info.importance) or 0) ~= 0
      if pocket == "BERRY_POUCH" or (pocket ~= "KEY_ITEMS" and not important) then
        local q = quantityText(pocket, r.qty)
        FrlgFont.draw(q, x0 + 119 - FrlgFont.measure(q, { font = "narrow" }), y, { font = "narrow", colors = colors })
      elseif registered and registered == ItemsData.toNumericId(r.id) and m then
        local img = Kit.image(m.select)
        if img then love.graphics.setColor(1, 1, 1, 1) love.graphics.draw(img, x0 + 96, y - 1) end
      end
    end
  end
  if Bag.mode == "move" then
    local g = require("src.ui.game3.rse.pokeblock_gfx").of("rse/pokeblock")
    local swapPal = g:manifest().palettes.swap_line
    local arrow = g:sprite("swap_line", 0, 16, 16, swapPal)
    local line = g:sprite("swap_line", 4, 16, 16, swapPal)
    -- pokeemerald/src/item_menu_icons.c:587, src/menu_helpers.c:434 UpdateSwapLineSpritesPos
    local row = Bag.cursor - 1 - scroll
    local cy = 1 + (row + 1) * 16
    love.graphics.setColor(1, 1, 1, 1)
    for i = 0, 7 do
      local cx = 120 + i * 16 - (i == 7 and 8 or 0)
      love.graphics.draw(i == 0 and arrow or line, cx - 8, cy - 8)
    end
  end
  return scroll, s
end

local function drawDescription(text, pal)
  local D = RseBag.DESC
  FrlgFont.draw(text, D.left * 8 + 3, D.top * 8 + 1, { colors = descColors(pal), maxWidth = D.width * 8 - 3 })
end

-- pokeemerald/src/item_menu.c:2548
local function drawTmHmInfo(sel)
  local m = BagChrome.manifest()
  local info = m and m.menuInfo
  local Pokemon = require("src.core.game3.pokemon")
  local move = info and Pokemon.moveFromTmItem(sel.id)
  local row = move and Pokemon.battleMove(move)
  if not row then return false end
  local I = BagChrome.MENU_INFO
  BagChrome.drawMenuInfoIcon(I.TYPE, 8, 104)
  BagChrome.drawMenuInfoIcon(I.POWER, 8, 116)
  BagChrome.drawMenuInfoIcon(I.ACCURACY, 8, 128)
  BagChrome.drawMenuInfoIcon(I.PP, 8, 140)
  BagChrome.drawMenuInfoIcon((tonumber(row.type) or 0) + 1, 56, 104)
  local colors = { fg = BagChrome.color(info.palette, 14), shadow = BagChrome.color(info.palette, 10), bg = { 0, 0, 0, 0 } }
  local power, accuracy = tonumber(row.power) or 0, tonumber(row.accuracy) or 0
  FrlgFont.draw(power <= 1 and "---" or string.format("%3d", power), 63, 116, { colors = colors })
  FrlgFont.draw(accuracy == 0 and "---" or string.format("%3d", accuracy), 63, 128, { colors = colors })
  FrlgFont.draw(string.format("%3d", tonumber(row.pp) or 0), 63, 140, { colors = colors })
  return true
end

local function drawGrid(Bag, sel)
  local g = st.grid or buildGrid(Bag)
  local w
  if g.cols == 1 then
    w = #g.cells <= 1 and { 22, 17, 7, 2 } or { 22, 15, 7, 4 }
  else
    w = g.rows <= 2 and { 15, 15, 14, 4 } or { 15, 13, 14, 6 }
  end
  if g.cols == 1 and #g.cells > 2 then w = { 22, 19 - #g.cells * 2, 7, #g.cells * 2 } end
  Window.stdFrame(Window.template(w[1], w[2], w[3], w[4]))
  local x0, y0 = w[1] * 8, w[2] * 8
  local session = Bag._session
  for i, c in ipairs(g.cells) do
    if c then
      local col = (i - 1) % g.cols
      local row = math.floor((i - 1) / g.cols)
      local x = x0 + 8 + col * 56
      local y = y0 + 1 + row * 16
      local name = c.name
      if name == "SET" and session and sel and ItemsData.toNumericId(session.registeredItem) == ItemsData.toNumericId(sel.id) then
        name = "DESELECT"
      end
      FrlgFont.draw(RomText.plain(RseBag.ACTION_TEXT[name] or "gText_Cancel2"), x, y,
        { font = "narrow", colors = FrlgFont.COLOR.NORMAL })
      if (st.gridPos + 1) == i or (not st.grid and c.idx == Bag.actionCursor) then
        Window.cursorPx(x - 8, y)
      end
    end
  end
end

local function drawMessageBox(text)
  Chrome.dialogueFrame()
  local left, top, width = Chrome.dialogueWindow()
  FrlgFont.draw(FrlgFont.wrap(text, width * 8), left * 8, top * 8 + 1,
    { maxWidth = width * 8, colors = FrlgFont.COLOR.NORMAL, linePitch = FrlgFont.linePitch() })
end

-- pokeemerald/src/item_menu.c:1192
local function drawQuantity(pocket, qty)
  Window.stdFrame(Window.template(24, 17, 5, 2))
  local digits = pocket == "BERRY_POUCH" and 3 or 2
  local t = RomText.plain("gText_xVar1", { stringVars = { string.format("%0" .. digits .. "d", qty) } })
  FrlgFont.draw(t, 24 * 8 + math.floor((40 - FrlgFont.measure(t)) / 2), 17 * 8 + 2, { colors = FrlgFont.COLOR.NORMAL })
end

function RseBag.draw(Bag)
  Bag = Bag or require("src.ui.game3.bag_menu")
  if not Bag.open then return end
  local m = BagChrome.manifest()
  if not m then return Bag.draw() end
  local pocket = Bag.currentPocket()
  local rows = Bag.list()
  local fem = female(Bag)
  local variant = fem and "female" or nil
  local pal = fem and m.palettes.female or m.palettes.male
  local switching = Bag._switch ~= nil
  local moving = Bag.mode == "move"
  local selected = Bag.mode ~= "list" and not moving

  local bgE = m.layers.bg
  local img = Kit.image(variant and bgE.variants and bgE.variants.female or bgE.png)
  love.graphics.setColor(1, 1, 1, 1)
  if img then love.graphics.draw(img, 0, 0) end

  -- pokeemerald/src/item_menu.c:1407
  local ind = m.layers.indicator
  local indImg = Kit.image(variant and ind.variants and ind.variants.female or ind.png)
  if indImg then
    local iw, ih = indImg:getDimensions()
    for i = 1, #pocketOrder() do
      local q = love.graphics.newQuad(i == Bag.pocketIdx and 8 or 0, 0, 8, 8, iw, ih)
      love.graphics.draw(indImg, q, (i - 1 + 5) * 8, 3 * 8)
    end
  end

  -- pokeemerald/src/item_menu.c:2408
  local label = ItemsData.POCKET_LABEL[pocket] or ""
  local P = RseBag.POCKET_NAME
  FrlgFont.draw(label, P.left * 8 + math.floor((64 - FrlgFont.measure(label)) / 2), P.top * 8 + 1,
    { colors = pocketNameColors(pal) })

  -- pokeemerald/src/item_menu_icons.c:440
  local frame = RseBag.BAG_FRAME[pocket] or 0
  local y2 = st.switchY or 0
  if st.switchY then frame = 0 end
  local rot = st.shake and RseBag.SHAKE[st.shake] or 0
  BagChrome.drawFrame(fem and m.sprites.female or m.sprites.male, frame, 68 - 32, 66 - 32 + y2,
    { rotation = rot * math.pi * 2 / 256 })
  if st.ball then
    local r = (st.ball.dir == -1 and 8 or -8) * st.ball.k * math.pi * 2 / 256
    BagChrome.drawFrame(m.sprites.ball, 0, 16 - 8, 16 - 8, { rotation = r })
  end

  local scroll, s = 0, 0
  if not switching then
    scroll, s = drawList(Bag, pocket, rows, pal, selected)
  end

  -- pokeemerald/src/item_menu.c:933
  local sel = rows[moving and Bag.moveFrom or Bag.cursor]
  if not switching then
    -- pokeemerald/src/item_menu_icons.c:535
    local icon = sel and ItemsData.toNumericId(sel.id) or BagChrome.returnIconIndex()
    BagChrome.drawItemIcon(icon, 24 - 16, 88 - 16)
  end

  if Bag.mode == "list" and not switching then
    local desc
    if sel then
      desc = sel.description or ItemsData.description(sel.id)
    else
      local loc = RseBag.LOCATION[Bag._battle and "battle" or (Bag._location or "")] or 0
      desc = RomText.plain("gText_ReturnToVar1", { stringVars = { RomText.at("gBagMenu_ReturnToStrings", loc) } })
    end
    if desc then drawDescription(desc, pal) end
  elseif moving and sel and not switching then
    -- pokeemerald/src/item_menu.c:1438
    drawDescription(RomText.plain("gText_MoveVar1Where", { stringVars = { sel.name } }), pal)
  elseif Bag.mode == "action" and sel then
    if not (pocket == "TM_CASE" and drawTmHmInfo(sel)) then
      drawDescription(RomText.plain("gText_Var1IsSelected", { stringVars = { sel.name } }), pal)
    end
    drawGrid(Bag, sel)
  elseif (Bag.mode == "toss" or Bag.mode == "deposit") and sel then
    -- pokeemerald/src/item_menu.c:2203
    local key = Bag.mode == "deposit" and "gText_DepositHowManyVar1" or "gText_TossHowManyVar1s"
    drawDescription(RomText.plain(key, { stringVars = { sel.name } }), pal)
    drawQuantity(pocket, Bag.tossQty or 1)
  elseif Bag.mode == "toss_confirm" and sel then
    drawDescription(RomText.plain("gText_ConfirmTossItems", { stringVars = { sel.name, tostring(Bag.tossQty) } }), pal)
    -- pokeemerald/src/item_menu.c:499
    Window.stdFrame(Window.template(24, 15, 5, 4))
    FrlgFont.draw(RomText.plain("gText_Yes"), 24 * 8 + 8, 15 * 8 + 1, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(RomText.plain("gText_No"), 24 * 8 + 8, 15 * 8 + 17, { colors = FrlgFont.COLOR.NORMAL })
    Window.cursorPx(24 * 8, 15 * 8 + 1 + (Bag.yesNoCursor == 2 and 16 or 0))
  elseif Bag.mode == "toss_done" and sel then
    drawDescription(RomText.plain("gText_ThrewAwayVar2Var1s", { stringVars = { sel.name, tostring(Bag.tossQty) } }), pal)
  elseif Bag.mode == "deposit_done" and Bag._depositText then
    drawMessageBox(Bag._depositText)
  end

  if (Bag.mode == "list" or moving) and not switching then
    local t = st.k
    -- pokeemerald/src/item_menu.c:360, :1442
    if not moving and Bag._location ~= "itempc" and Bag._location ~= "berry_tree" and Bag._location ~= "blender" then
      BagChrome.drawArrow("left", 28, 16, t)
      BagChrome.drawArrow("right", 100, 16, t)
    end
    -- pokeemerald/src/item_menu.c:1027
    local n = #rows + 1
    if scroll > 0 then BagChrome.drawArrow("up", 172, 12, t) end
    if scroll < n - s then BagChrome.drawArrow("down", 172, 148, t) end
  end

  if Bag.mode == "message" and Bag.messageText then
    drawMessageBox(Bag.messageText)
  end
  if Bag.mode == "sell" and Bag._sell then
    Bag._sell:draw()
  end

  local level = 0
  local op, ex = Bag._open, Bag._exit
  if op then
    level = math.max(0, 16 - 2 * math.floor(op.k / 2))
  elseif ex then
    level = math.min(16, 4 * math.floor(ex.k / 2))
  end
  if level > 0 then
    love.graphics.setColor(0, 0, 0, level / 16)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function RseBag.reset()
  st.scroll, st.cursor = {}, {}
  st.grid, st.gridPos, st.shake, st.switchY, st.ball, st.k, st.lastMode = nil, 0, nil, nil, nil, 0, nil
end

-- pokeemerald/src/item_menu.c:576
function RseBag.chooseBerry(ctx, done, location)
  local Rse = require("src.core.game3.rse.init")
  local sess = (type(ctx) == "table" and (ctx.session or (ctx.bag and ctx))) or Rse.session()
  local Bag = require("src.ui.game3.screens").get("bag", sess)
  Bag.show(sess and sess.bag, { session = sess, location = location or "berry_tree", pocket = "BERRIES",
    onChoose = done })
end

do
  local ok, Rse = pcall(require, "src.core.game3.rse.init")
  if ok and Rse then Rse.register("bag", RseBag) end
end

return RseBag
