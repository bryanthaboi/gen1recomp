local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local RomText = require("src.core.game3.rom_text")
local Rse = require("src.core.game3.rse.init")
local Decor = require("src.core.game3.rse.decoration")
local DecorInv = require("src.core.game3.rse.decoration_inventory")

local D = {}

D.ID = "rse_decoration"
D.open_ = false
D.pendingSprite = nil

-- pokeemerald/src/decoration.c:258
local WIN = {
  main = Window.template(1, 1, 18, 8),
  categories = Window.template(1, 1, 13, 18),
  summary = Window.template(17, 1, 12, 2),
  items = Window.template(16, 13, 13, 6),
}
D.WIN = WIN
-- pokeemerald/src/secret_base.c:178
local REG_WIN = { list = Window.template(18, 1, 11, 18), actions = Window.template(2, 1, 28, 4) }
-- pokeemerald/src/decoration.c:300
local ITEM_X, UP_TEXT_Y, MAX_SHOWN = 8, 9, 8
-- pokeemerald/src/decoration.c:58
local MENU_PLACE, MENU_TOSS, MENU_TRADE = 0, 1, 2
-- pokeemerald/src/menu.c:77
local SPEED_DELAYS = { 8, 4, 1 }
-- pokeemerald/src/main.c:241
local REPEAT_START, REPEAT_CONTINUE = 40, 5

local ACTIONS = { "gText_Decorate", "gText_PutAway", "gText_Toss2", "gText_Cancel" }
local ACTION_DESC = { "gText_PutOutSelectedDecorItem", "gText_StoreChosenDecorInPC", "gText_ThrowAwayUnwantedDecors",
  "gText_GoBackPrevMenu" }
local CAT_NAMES = { [0] = "gText_Desk", "gText_Chair", "gText_Plant", "gText_Ornament", "gText_Mat", "gText_Poster",
  "gText_Doll", "gText_Cushion" }

local function se(name)
  local SE = require("src.core.game3.se_ids")
  pcall(function() require("src.core.game3.audio").playSe(SE[name]) end)
end

local function text(key, vars)
  if D._opts and D._opts.text then return D._opts.text(key, vars) end
  return RomText.plain(key, vars and { stringVars = vars } or nil)
end

local function session()
  return D._session or Rse.session()
end

local function SB()
  return require("src.core.game3.rse.secret_base")
end

local function rgba(bgr)
  bgr = tonumber(bgr) or 0
  local r, g, b = bgr % 32, math.floor(bgr / 32) % 32, math.floor(bgr / 1024) % 32
  return { r / 31, g / 31, b / 31, 1 }
end

local function menuColors(disabled)
  local pal = Decor.manifest().menuPalette or {}
  -- pokeemerald/src/decoration.c:763
  if disabled then return { fg = rgba(pal[5]), shadow = rgba(pal[6]) } end
  return { fg = rgba(pal[3]), shadow = rgba(pal[4]) }
end

local function image(path)
  return require("src.ui.game3.rse.scene_kit").image(path)
end

local function frame(tpl)
  Window.stdFrame(tpl)
  Window.fill(tpl, 1, 1, 1, 1)
end

local function narrow()
  return { font = "narrow" }
end

local function rowHeight()
  local face = FrlgFont.face and FrlgFont.face(narrow())
  return face and face.height or 16
end


local function speedIdx()
  local ok, n = pcall(function() return require("src.core.game3.options").textSpeed(session()) end)
  return ok and n or 1
end

-- pokeemerald/src/menu.c:457
local function message(str, onPrinted)
  D.msg = { text = str, shown = 0, total = #str, delay = 0, onPrinted = onPrinted, printed = false }
end

local function clearMessage()
  D.msg = nil
end

local function tickMessage(input)
  local m = D.msg
  if not m or m.printed then return end
  local held = input and (input:isDown("a") or input:isDown("b"))
  if m.delay > 0 and not held then
    m.delay = m.delay - 1
    return
  end
  m.shown = m.shown + 1
  if m.shown >= m.total then
    m.printed = true
    if m.onPrinted then m.onPrinted() end
  else
    local d = SPEED_DELAYS[speedIdx() + 1] or 4
    m.delay = d > 0 and d - 1 or 0
  end
end

local function waitPress(fn)
  D.state = "wait_press"
  D._afterPress = fn
end

local function yesNo(onYes, onNo)
  D.state = "yesno"
  D.yesCursor = 1
  D._yes, D._no = onYes, onNo
end


local function context()
  return Decor.context(session(), D.isPlayerRoom)
end

-- pokeemerald/src/decoration.c:625
local function showDescription()
  message(text(ACTION_DESC[D.actionCursor + 1]))
  D.msg.shown, D.msg.printed = D.msg.total, true
end

local function toActions()
  D.state = "actions"
  D.view = "actions"
  showDescription()
end

-- pokeemerald/src/decoration.c:581
function D.open(opts)
  opts = opts or {}
  D._opts = opts
  D.open_ = true
  D._session = opts.session or Rse.session()
  D.isPlayerRoom = opts.isPlayerRoom == true
  D._onClose = opts.onClose
  D.actionCursor = 0
  D.category = Decor.CAT.DESK
  D.frames = 0
  local Message = package.loaded["src.ui.game3.message"]
  if Message and Message.isOpen and Message.isOpen() and Message.close then Message.close() end
  Stack.push(D.ID, D, { hideBelow = true })
  toActions()
  return true
end

function D.isOpen()
  return D.open_
end

local function finish()
  D.open_ = false
  clearMessage()
  Stack.pop(D.ID)
  local cb = D._onClose
  D._onClose = nil
  return cb
end

-- pokeemerald/src/decoration.c:678
local function cancelActions()
  local cb = finish()
  if not D.isPlayerRoom then
    SB().startScript("SecretBase_EventScript_PCCancel")
  elseif cb then
    cb()
  end
end

function D.reset()
  D._opts = nil
  D._trade = nil
  D.open_ = false
  D._onClose = nil
  D.msg = nil
  D.mode = nil
  D.pendingSprite = nil
  D._marked = nil
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView and FieldView.setCameraPanning then FieldView.setCameraPanning(0, 0) end
  Stack.pop(D.ID)
end


local function catDisabled(cat)
  -- pokeemerald/src/decoration.c:731
  return D.isPlayerRoom and D.command == MENU_PLACE and cat ~= Decor.CAT.DOLL and cat ~= Decor.CAT.CUSHION
end

local function toCategories()
  D.state = "categories"
  D.view = "categories"
  D.catCursor = D.category
  clearMessage()
end

-- pokeemerald/src/decoration.c:631
local function startCommand(cmd)
  if DecorInv.count(session()) == 0 then
    message(text("gText_NoDecorations"), function() waitPress(toActions) end)
    D.state = "printing"
    return
  end
  D.command = cmd
  D.category = Decor.CAT.DESK
  toCategories()
end

local function itemsCount()
  return DecorInv.countInCategory(D.category, session())
end

local function inventoryList()
  return DecorInv.inventories(session())[D.category]
end

local function toItems(keepCursor)
  D.state = "items"
  D.view = "items"
  if not keepCursor then D.scroll, D.row = 0, 0 end
  D.inBase, D.inRoom = Decor.inUse(session(), D.category)
  local n = itemsCount() + 1
  local shown = math.min(n, MAX_SHOWN)
  if D.scroll + shown > n then D.scroll = math.max(0, n - shown) end
  if D.scroll + D.row >= n then D.row = n - 1 - D.scroll end
  clearMessage()
end

-- pokeemerald/src/decoration.c:801
local function selectCategory()
  local n = itemsCount()
  if n ~= 0 then
    DecorInv.condense(D.category, session())
    toItems(false)
  else
    D.view = nil
    message(text("gText_NoDecorations"), function() waitPress(toCategories) end)
    D.state = "printing"
  end
end

local function selectedIndex()
  return D.scroll + D.row + 1
end

local function selectedDecor()
  return inventoryList()[selectedIndex()] or 0
end

local function invalidToItems(key, vars)
  D.view = nil
  message(text(key, vars), function() waitPress(function() toItems(true) end) end)
  D.state = "printing"
end


local function player()
  return package.loaded["src.core.game3.player"] or require("src.core.game3.player")
end

local function fieldView()
  return package.loaded["src.core.game3.field_view"] or require("src.core.game3.field_view")
end

local function setPan()
  local p = D.mode
  fieldView().setCameraPanning(p.panX, p.panY)
end

local function fade(mode, fn)
  local Fade = require("src.ui.game3.fade")
  D.state = "fading"
  Fade.begin(Fade.MODE[mode], 1, fn)
end

-- pokeemerald/src/decoration.c:1178
local function initialPositions(kind, decor)
  D.view = nil
  local P = player()
  local w, h = 1, 1
  if decor then w, h = Decor.dims(decor) end
  D.mode = {
    kind = kind, decor = decor, w = w, h = h,
    initialX = P.cellX, initialY = P.cellY, x = P.cellX, y = P.cellY,
    panX = 0, panY = 0, dx = 0, dy = 0, step = 0, button = nil, blink = 0, solid = false,
  }
  -- pokeemerald/src/decoration.c:1450
  if decor and DecorInv.info(decor).shape == Decor.SHAPE_1x3 then D.mode.y = D.mode.y + 1 end
end

local function continueMode()
  clearMessage()
  D.mode.solid = false
  D.mode.button = nil
  D.state = D.mode.kind
end

local function returnToItemsAfterPlace()
  local sess = session()
  D.mode = nil
  fieldView().setCameraPanning(0, 0)
  -- pokeemerald/src/decoration.c:1764
  SB().hideDecorationSprites(sess)
  SB().initDecorationSprites(0, sess)
  Rse.setVar("VAR_SECRET_BASE_INITIALIZED", 1, sess)
  toItems(true)
  fade("FROM_BLACK", function() D.state = "items" end)
end

-- pokeemerald/src/decoration.c:1742
local function cancelDecorating()
  clearMessage()
  fade("TO_BLACK", returnToItemsAfterPlace)
end

local function inSecretBaseSection()
  local Map = package.loaded["src.core.game3.map"]
  local def = Map and Map.currentDef and Map.currentDef()
  local ok, sec = pcall(function()
    return require("src.core.game3.constants").active(session()):require("region_map_sections", "MAPSEC_SECRET_BASE")
  end)
  return def and ok and def.regionMapSectionId == sec
end

-- pokeemerald/src/decoration.c:1663
local function placeDecoration()
  local m = D.mode
  local sess = session()
  Decor.record(context(), m.decor, m.x, m.y)
  if not Decor.isSprite(m.decor) then
    Decor.showOnMap(SB().fieldGrid(), m.x, m.y, m.decor)
  else
    D.pendingSprite = { decor = m.decor, x = m.x, y = m.y }
    SB().setDecoration(m.decor, m.x, m.y, sess)
  end
  if not (D._opts and D._opts.recordSecretBaseVisit == false) and inSecretBaseSection() then
    Rse.call("tv", "tryPutSecretBaseVisitOnAir", "TryPutSecretBaseVisitOnAir", nil,
      SB().base(sess, Rse.var("VAR_CURRENT_SECRET_BASE", sess)).decorations)
  end
  cancelDecorating()
end

-- pokeemerald/src/decoration.c:1642
local function attemptPlace()
  local m = D.mode
  m.solid = true
  local grid = SB().fieldGrid()
  if Decor.canPlace(grid, { x = m.x, y = m.y, initialX = m.initialX, initialY = m.initialY }, m.decor) then
    message(text("gText_PlaceItHere"), function() yesNo(placeDecoration, continueMode) end)
  else
    se("SE_FAILURE")
    message(text("gText_CantBePlacedHere"), function() waitPress(continueMode) end)
  end
  D.state = "printing"
end

local function attemptCancelPlace()
  D.mode.solid = true
  message(text("gText_CancelDecorating"), function() yesNo(cancelDecorating, continueMode) end)
  D.state = "printing"
end

-- pokeemerald/src/decoration.c:1325
local function attemptPlaceSelected()
  local decor = selectedDecor()
  local cat = D.category
  if D.isPlayerRoom and cat ~= Decor.CAT.DOLL and cat ~= Decor.CAT.CUSHION then
    return invalidToItems("gText_CantPlaceInRoom")
  end
  if not Decor.isInPc(session(), cat, selectedIndex()) then
    return invalidToItems("gText_InUseAlready")
  end
  local ctx = context()
  if not Decor.hasSpace(ctx) then
    return invalidToItems(D.isPlayerRoom and "gText_NoMoreDecorations2" or "gText_NoMoreDecorations",
      { string.format("%2d", ctx.size) })
  end
  D.view = nil
  fade("TO_BLACK", function()
    initialPositions("place", decor)
    fade("FROM_BLACK", continueMode)
  end)
end

-- pokeemerald/src/decoration.c:1799
local function moveInvalid(m, w, h)
  local lw, lh = SB().fieldGrid().size()
  if m.dir == "up" and m.y - h + 1 < 0 then m.y = m.y + 1 return true end
  if m.dir == "down" and m.y >= lh then m.y = m.y - 1 return true end
  if m.dir == "left" and m.x < 0 then m.x = m.x + 1 return true end
  if m.dir == "right" and m.x + w - 1 >= lw then m.x = m.x - 1 return true end
  return false
end

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function heldDir(input)
  local found
  for k in pairs(DIRS) do
    if input:isDown(k) then
      if found then return nil end
      found = k
    end
  end
  return found
end

-- pokeemerald/src/decoration.c:1845
local function selectLocation(input)
  local m = D.mode
  if m.step == 0 then
    if m.button == "a" then
      m.button = nil
      if m.kind == "place" then attemptPlace() else D.attemptPutAway() end
      return
    elseif m.button == "b" then
      m.button = nil
      if m.kind == "place" then attemptCancelPlace() else D.attemptCancelPutAway() end
      return
    end
    local dir = heldDir(input)
    m.dir = nil
    if dir then
      m.dir = dir
      m.x, m.y = m.x + DIRS[dir][1], m.y + DIRS[dir][2]
      if moveInvalid(m, m.w, m.h) then
        m.dir = nil
      else
        m.dx, m.dy = DIRS[dir][1] * 2, DIRS[dir][2] * 2
      end
    end
  end
  if m.dir then
    m.panX, m.panY = m.panX + m.dx, m.panY + m.dy
    setPan()
    m.step = (m.step + 1) % 8
    if m.step == 0 then m.dir = nil end
  end
  if not m.button then
    if input:wasPressed("a") then m.button = "a" elseif input:wasPressed("b") then m.button = "b" end
  end
end


-- pokeemerald/src/decoration.c:646
local function startPutAway()
  if not Decor.hasInUse(context()) then
    message(text("gText_NoDecorationsInUse"), function() waitPress(toActions) end)
    D.state = "printing"
    return
  end
  clearMessage()
  D.view = nil
  fade("TO_BLACK", function()
    initialPositions("putaway", nil)
    fade("FROM_BLACK", continueMode)
  end)
end

-- pokeemerald/src/decoration.c:2685
local function stopPuttingAway()
  clearMessage()
  fade("TO_BLACK", function()
    D.mode = nil
    fieldView().setCameraPanning(0, 0)
    local sess = session()
    SB().hideDecorationSprites(sess)
    SB().initDecorationSprites(0, sess)
    Rse.setVar("VAR_SECRET_BASE_INITIALIZED", 1, sess)
    D.actionCursor = 0
    fade("FROM_BLACK", toActions)
  end)
end

function D.attemptCancelPutAway()
  D.mode.solid = true
  message(text("gText_StopPuttingAwayDecorations"), function() yesNo(stopPuttingAway, continueMode) end)
  D.state = "printing"
end

-- pokeemerald/src/decoration.c:2191
function D.putAwayIteration(i)
  local marked = D._marked or {}
  local r = Decor.putAwayIteration(context(), marked, tonumber(i) or 0)
  if r.flagId and r.flagId ~= 0 then
    for _, t in ipairs((package.loaded["src.core.game3.objects"] or {})._defs or {}) do
      if tonumber(t.flag or t.flagId) == r.flagId then r.localId = tonumber(t.localId or t.index) break end
    end
  end
  return r
end

-- pokeemerald/src/decoration.c:2260
local function putAwayDecoration()
  clearMessage()
  local grid = SB().fieldGrid()
  local ctx = context()
  fade("TO_BLACK", function()
    Decor.clearNonSprites(grid, ctx, D._marked)
    local O = package.loaded["src.core.game3.objects"] or require("src.core.game3.objects")
    for i = 0, #D._marked do
      local r = D.putAwayIteration(i)
      if r.done then break end
      if r.localId then O.removeObject(r.localId) end
      if r.flagId and r.flagId ~= 0 then
        require("src.core.game3.scripting.flags").setFlag(Rse.store(), nil, r.flagId, true)
      end
    end
    D._marked = nil
    fade("FROM_BLACK", function()
      message(text("gText_DecorationReturnedToPC"), function() waitPress(continueMode) end)
      D.state = "printing"
      if not (D._opts and D._opts.recordSecretBaseVisit == false) and inSecretBaseSection() then
        Rse.call("tv", "tryPutSecretBaseVisitOnAir", "TryPutSecretBaseVisitOnAir", nil,
          SB().base(session(), Rse.var("VAR_CURRENT_SECRET_BASE", session())).decorations)
      end
    end)
  end)
end

-- pokeemerald/src/decoration.c:2384
function D.attemptPutAway()
  local m = D.mode
  local grid = SB().fieldGrid()
  D._marked = Decor.markForRemoval(grid, context(), m.x, m.y)
  if #D._marked > 0 then
    local first = D._marked[1]
    local ox, oy = Decor.decodePos(context().pos[first.idx])
    -- pokeemerald/src/decoration.c:2474
    m.avatarDX, m.avatarDY = (first.width or 1) - (m.x - ox + 1), oy - m.y
    m.hideCursor = true
    message(text("gText_ReturnDecorationToPC"), function()
      yesNo(putAwayDecoration, function()
        m.hideCursor, m.avatarDX, m.avatarDY = false, nil, nil
        continueMode()
      end)
    end)
  else
    local beh = grid.behavior(m.x, m.y)
    if Decor.isBeh(beh, "SECRET_BASE_PC") or Decor.isBeh(beh, "PLAYER_ROOM_PC_ON") then
      m.solid = true
      message(text("gText_StopPuttingAwayDecorations"), function() yesNo(stopPuttingAway, continueMode) end)
    else
      message(text("gText_NoDecorationHere"), function() waitPress(continueMode) end)
    end
  end
  D.state = "printing"
end


-- pokeemerald/src/decoration.c:2719
local function attemptToss()
  local decor = selectedDecor()
  if Decor.isInPc(session(), D.category, selectedIndex()) then
    D.view = nil
    local name = (DecorInv.info(decor) or {}).name or ""
    message(text("gText_DecorationWillBeDiscarded", { name }), function()
      yesNo(function()
        Decor.toss(session(), D.category, selectedIndex())
        invalidToItems("gText_DecorationThrownAway")
      end, function() toItems(true) end)
    end)
    D.state = "printing"
  else
    invalidToItems("gText_CantThrowAwayInUse")
  end
end


-- pokeemerald/src/trader.c:192
function D.finishTrade(value)
  local t = D._trade
  D._trade = nil
  finish()
  if t then
    Rse.setSpecialVar(t.ctx, 0x8006, value)
    if t.done then t.done() end
  end
end

-- pokeemerald/src/trader.c:176
function D.trade()
  local t = D._trade
  if Decor.isInPc(session(), D.category, selectedIndex()) then
    local decor = selectedDecor()
    local give = DecorInv.info(Rse.specialVar(t.ctx, 0x8004)) or {}
    if t.ctx and t.ctx.stringVars then
      t.ctx.stringVars[3] = give.name or ""
      t.ctx.stringVars[2] = (DecorInv.info(decor) or {}).name or ""
    end
    D.finishTrade(decor)
  else
    D.finishTrade(0xFFFF)
  end
end

-- pokeemerald/src/decoration.c:844
function D.openTrade(ctx, done, opts)
  D._opts = opts or {}
  D.open_ = true
  D._session = Rse.session()
  D.isPlayerRoom = false
  D._onClose = nil
  D._trade = { ctx = ctx, done = done }
  D.command = MENU_TRADE
  D.category = Decor.CAT.DESK
  D.frames = 0
  local Message = package.loaded["src.ui.game3.message"]
  if Message and Message.isOpen and Message.isOpen() and Message.close then Message.close() end
  Stack.push(D.ID, D, { hideBelow = true })
  toCategories()
  return true
end


-- pokeemerald/src/secret_base.c:1112
local function registryExit()
  local cb = finish()
  if Rse.var("VAR_CURRENT_SECRET_BASE") == 0 then
    SB().startScript("SecretBase_EventScript_PCCancel")
  else
    SB().startScript("SecretBase_EventScript_ShowRegisterMenu")
  end
  if cb then cb() end
end

-- pokeemerald/src/secret_base.c:916
function D.openRegistry(opts)
  opts = opts or {}
  D._opts = opts
  D.open_ = true
  D._session = opts.session or Rse.session()
  D._onClose = opts.onClose
  D.frames = 0
  local Message = package.loaded["src.ui.game3.message"]
  if Message and Message.isOpen and Message.isOpen() and Message.close then Message.close() end
  Stack.push(D.ID, D, { hideBelow = true })
  D.regScroll, D.regRow = 0, 0
  if SB().numRegistered(session()) == 0 then
    message(text("gText_NoRegistry"), function() waitPress(registryExit) end)
    D.state = "printing"
  else
    clearMessage()
    D.state = "registry"
    D.view = "registry"
  end
  return true
end

local function registryEntries()
  local list = SB().registryEntries(session())
  list[#list + 1] = { id = nil, name = text("gText_Cancel") }
  return list
end


local function trackHeld(input)
  local key
  for _, k in ipairs({ "up", "down", "left", "right" }) do
    if input:isDown(k) then key = k break end
  end
  if key ~= D._held or (key and input:wasPressed(key)) then
    D._held, D._heldFrames = key, 0
  elseif key then
    D._heldFrames = (D._heldFrames or 0) + 1
  end
end

local function repeated(input, key)
  if input:wasPressed(key) then return true end
  local f = D._heldFrames or 0
  return D._held == key and f >= REPEAT_START and (f - REPEAT_START) % REPEAT_CONTINUE == 0
end

-- pokeemerald/src/list_menu.c:819
local function listStep(down, n)
  local shown = math.min(n, MAX_SHOWN)
  local row, scroll = D.row, D.scroll
  if not down then
    local newRow = shown == 1 and 0 or (shown - (math.floor(shown / 2) + shown % 2) - 1)
    if scroll == 0 then
      if row == 0 then return false end
      D.row = row - 1
    elseif row > newRow then
      D.row = row - 1
    else
      D.row, D.scroll = newRow, scroll - 1
    end
  else
    local newRow = shown == 1 and 0 or (math.floor(shown / 2) + shown % 2)
    if scroll == n - shown then
      if row >= shown - 1 then return false end
      D.row = row + 1
    elseif row < newRow then
      D.row = row + 1
    else
      D.row, D.scroll = newRow, scroll + 1
    end
  end
  return true
end

local function menuMove(input, cursorKey, count)
  if input:wasPressed("up") and D[cursorKey] > 0 then
    D[cursorKey] = D[cursorKey] - 1
    se("SE_SELECT")
    return true
  elseif input:wasPressed("down") and D[cursorKey] < count - 1 then
    D[cursorKey] = D[cursorKey] + 1
    se("SE_SELECT")
    return true
  end
  return false
end

function D.handleInput(input)
  if not D.open_ or not input then return end
  trackHeld(input)
  local s = D.state
  if s == "printing" or s == "fading" then
    return
  elseif s == "wait_press" then
    if input:wasPressed("a") or input:wasPressed("b") then
      local fn = D._afterPress
      D._afterPress = nil
      if fn then fn() end
    end
  elseif s == "yesno" then
    -- pokeemerald/src/menu.c:1211
    if input:wasPressed("up") and D.yesCursor ~= 1 then
      D.yesCursor = 1
      se("SE_SELECT")
    elseif input:wasPressed("down") and D.yesCursor ~= 2 then
      D.yesCursor = 2
      se("SE_SELECT")
    elseif input:wasPressed("a") then
      se("SE_SELECT")
      local fn = D.yesCursor == 1 and D._yes or D._no
      D._yes, D._no = nil, nil
      if fn then fn() end
    elseif input:wasPressed("b") then
      se("SE_SELECT")
      local fn = D._no
      D._yes, D._no = nil, nil
      if fn then fn() end
    end
  elseif s == "actions" then
    -- pokeemerald/src/decoration.c:601
    if menuMove(input, "actionCursor", #ACTIONS) then
      showDescription()
    elseif input:wasPressed("a") then
      se("SE_SELECT")
      if D.actionCursor == 0 then startCommand(MENU_PLACE)
      elseif D.actionCursor == 1 then startPutAway()
      elseif D.actionCursor == 2 then startCommand(MENU_TOSS)
      else cancelActions() end
    elseif input:wasPressed("b") then
      se("SE_SELECT")
      cancelActions()
    end
  elseif s == "categories" then
    -- pokeemerald/src/decoration.c:778
    if menuMove(input, "catCursor", Decor.CATEGORY_COUNT + 1) then return end
    if input:wasPressed("a") or input:wasPressed("b") then
      se("SE_SELECT")
      if input:wasPressed("b") or D.catCursor == Decor.CATEGORY_COUNT then
        if D.command == MENU_TRADE then D.finishTrade(0) else toActions() end
      else
        D.category = D.catCursor
        selectCategory()
      end
    end
  elseif s == "items" then
    -- pokeemerald/src/decoration.c:988
    local n = itemsCount() + 1
    if repeated(input, "up") then
      if listStep(false, n) then se("SE_SELECT") end
    elseif repeated(input, "down") then
      if listStep(true, n) then se("SE_SELECT") end
    elseif input:wasPressed("a") or input:wasPressed("b") then
      se("SE_SELECT")
      if input:wasPressed("b") or selectedIndex() == n then
        toCategories()
      elseif D.command == MENU_PLACE then
        attemptPlaceSelected()
      elseif D.command == MENU_TRADE then
        D.trade()
      else
        attemptToss()
      end
    end
  elseif s == "place" or s == "putaway" then
    selectLocation(input)
  elseif s == "registry" then
    -- pokeemerald/src/secret_base.c:993
    local list = registryEntries()
    if repeated(input, "up") then
      D.row, D.scroll = D.regRow, D.regScroll
      if listStep(false, #list) then se("SE_SELECT") end
      D.regRow, D.regScroll = D.row, D.scroll
    elseif repeated(input, "down") then
      D.row, D.scroll = D.regRow, D.regScroll
      if listStep(true, #list) then se("SE_SELECT") end
      D.regRow, D.regScroll = D.row, D.scroll
    elseif input:wasPressed("a") or input:wasPressed("b") then
      se("SE_SELECT")
      local e = list[D.regScroll + D.regRow + 1]
      if input:wasPressed("b") or not e.id then
        registryExit()
      else
        D.regSelected = e
        D.regAction = 0
        D.state = "registry_actions"
      end
    end
  elseif s == "registry_actions" then
    -- pokeemerald/src/secret_base.c:1037
    if menuMove(input, "regAction", 2) then return end
    if input:wasPressed("b") or (input:wasPressed("a") and D.regAction == 1) then
      se("SE_SELECT")
      D.state = "registry"
    elseif input:wasPressed("a") then
      se("SE_SELECT")
      local e = D.regSelected
      D.view = nil
      message(text("gText_OkayToDeleteFromRegistry", { e.name }), function()
        yesNo(function()
          message(text("gText_RegisteredDataDeleted"), function()
            waitPress(function()
              SB().unregister(e.id, session())
              local n = #registryEntries()
              D.regRow = math.min(D.regRow, math.max(0, n - 1 - D.regScroll))
              clearMessage()
              D.state, D.view = "registry", "registry"
            end)
          end)
          D.state = "printing"
        end, function()
          clearMessage()
          D.state, D.view = "registry", "registry"
        end)
      end)
      D.state = "printing"
    end
  end
end

function D.update()
  if not D.open_ then return end
  D.frames = (D.frames or 0) + 1
  local game = require("src.core.game3.runtime")._game
  tickMessage(game and game.input)
  if D.mode then D.mode.blink = (D.mode.blink + 1) % 32 end
end


local function drawMessage()
  local m = D.msg
  if not m then return end
  Window.dialogueFrame()
  local Chrome = require("src.ui.game3.chrome")
  local L, Top, W = Chrome.dialogueWindow()
  FrlgFont.draw(m.text, L * 8, Top * 8 + 1, { maxWidth = W * 8, limitChars = m.shown })
end

local function drawYesNo()
  local t = Decor.manifest().yesNoWindow or { left = 21, top = 9, width = 5, height = 4 }
  local tpl = Window.template(t.left, t.top, t.width, t.height)
  frame(tpl)
  local ph = Window.optionHeight()
  Window.printPx(text("gText_Yes"), tpl.left * 8 + 8, tpl.top * 8 + 1)
  Window.printPx(text("gText_No"), tpl.left * 8 + 8, tpl.top * 8 + 1 + ph)
  Window.cursorPx(tpl.left * 8, tpl.top * 8 + 1 + (D.yesCursor - 1) * ph)
end

local function actionsWidth()
  local w = 0
  for _, k in ipairs(ACTIONS) do w = math.max(w, FrlgFont.measure(text(k))) end
  -- pokeemerald/src/international_string_util.c:37
  local tiles = math.floor((w + 9) / 8) + 1
  return math.min(tiles, 18)
end

-- pokeemerald/src/decoration.c:566
local function drawActions()
  local tpl = Window.template(1, 1, actionsWidth(), 8)
  frame(tpl)
  local ph = Window.optionHeight()
  for i, k in ipairs(ACTIONS) do
    Window.printPx(text(k), tpl.left * 8 + 8, tpl.top * 8 + 1 + (i - 1) * ph)
  end
  Window.cursorPx(tpl.left * 8, tpl.top * 8 + 1 + D.actionCursor * ph)
end

-- pokeemerald/src/decoration.c:745
local function drawCategories()
  local tpl = WIN.categories
  frame(tpl)
  local ox, oy = tpl.left * 8, tpl.top * 8
  for cat = 0, Decor.CATEGORY_COUNT - 1 do
    local y = oy + cat * 16 + 1
    local colors = menuColors(catDisabled(cat))
    FrlgFont.draw(text(CAT_NAMES[cat]), ox + 8, y, { colors = colors })
    local count = string.format("%2d/%2d", DecorInv.countInCategory(cat, session()), DecorInv.SIZES[cat])
    FrlgFont.draw(count, ox + 104 - FrlgFont.measure(count), y, { colors = colors })
  end
  Window.printPx(text(D.command == MENU_TRADE and "gText_Exit" or "gText_Cancel"), ox + 8, oy + Decor.CATEGORY_COUNT * 16 + 1)
  Window.cursorPx(ox, oy + 1 + (D.catCursor or 0) * 16)
end

local function drawItems()
  local list = WIN.categories
  frame(list)
  local ox, oy = list.left * 8, list.top * 8
  local rh = rowHeight()
  local inv = inventoryList()
  local n = itemsCount() + 1
  local shown = math.min(n, MAX_SHOWN)
  local disabled = D.isPlayerRoom and D.command == MENU_PLACE and D.category ~= Decor.CAT.DOLL
    and D.category ~= Decor.CAT.CUSHION
  local red, blue = Decor.manifest().inUseRed, Decor.manifest().inUseBlue
  for i = 0, shown - 1 do
    local idx = D.scroll + i + 1
    local y = oy + UP_TEXT_Y + i * rh
    if idx < n then
      local d = DecorInv.info(inv[idx]) or {}
      FrlgFont.draw(d.name or "", ox + ITEM_X, y, { font = "narrow", colors = menuColors(disabled) })
      -- pokeemerald/src/decoration.c:925
      local icon = (D.inBase and D.inBase[idx]) and red or ((D.inRoom and D.inRoom[idx]) and blue or nil)
      local img = icon and image(icon.png)
      if img then love.graphics.draw(img, ox + 92, y + 2) end
    else
      FrlgFont.draw(text("gText_Cancel"), ox + ITEM_X, y, { font = "narrow" })
    end
  end
  Window.cursorPx(ox, oy + UP_TEXT_Y + D.row * rh)
  local sum = WIN.summary
  frame(sum)
  local sx, sy = sum.left * 8, sum.top * 8 + 1
  FrlgFont.draw(text(CAT_NAMES[D.category]), sx, sy, { colors = menuColors(false) })
  local count = string.format("%2d/%2d", DecorInv.countInCategory(D.category, session()), DecorInv.SIZES[D.category])
  FrlgFont.draw(count, sx + 96 - FrlgFont.measure(count), sy, { colors = menuColors(false) })
  local desc = WIN.items
  frame(desc)
  local d = selectedIndex() < n and DecorInv.info(inv[selectedIndex()]) or nil
  local str = d and d.description or text("gText_GoBackPrevMenu")
  FrlgFont.draw(str, desc.left * 8, desc.top * 8 + 1, { maxWidth = desc.width * 8 })
end

local function nativeTiles()
  local Collision = package.loaded["src.core.game3.collision"]
  local def = Collision and Collision._mapDef
  local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
  local NativeTileset = require("src.core.game3.tileset_native")
  return pair and NativeTileset.get(pair) or nil
end

local function drawOw(gid, x, y)
  local OwSprites = require("src.core.game3.ow_sprites")
  local spr = OwSprites.getDraw(gid)
  local q = spr and spr.quads and spr.quads[0]
  if not q then return nil end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(spr.image, q, x, y)
  return spr
end

local function isFemale()
  local g = session() and session().gender
  return g == 1 or g == "female" or g == "F" or g == "girl"
end

local function avatarGfx()
  if D._opts and D._opts.avatarGfx then return D._opts.avatarGfx(session(), isFemale()) end
  local C = require("src.core.game3.constants").of("emerald")
  return C:require("event_objects", isFemale() and "OBJ_EVENT_GFX_MAY_DECORATING" or "OBJ_EVENT_GFX_BRENDAN_DECORATING")
end

-- pokeemerald/src/decoration.c:1401
local function drawPlacing()
  local m = D.mode
  local cx, cy = 112, 72
  local visible = m.solid or m.blink < 15
  local d = Decor.info(m.decor)
  if visible and d then
    if d.permission == Decor.PERM.SPRITE then
      local OwSprites = require("src.core.game3.ow_sprites")
      local spr = OwSprites.getDraw(d.tiles[1])
      if spr then drawOw(d.tiles[1], cx + (16 - spr.width) / 2, cy + 16 - spr.height) end
    else
      local ts = nativeTiles()
      if ts then
        local NativeTileset = require("src.core.game3.tileset_native")
        love.graphics.setColor(1, 1, 1, 1)
        for j = 0, m.h - 1 do
          for i = 0, m.w - 1 do
            local mid = (d.tiles[j * m.w + i + 1] or 0) + Decor.PRIMARY
            local slot = NativeTileset.slotFor(ts, mid)
            local px, py = cx + i * 16, cy - (m.h - 1 - j) * 16 - 2
            local q = slot and NativeTileset.quad(ts, slot)
            if q and ts.image then love.graphics.draw(ts.image, q, px, py) end
            local oq = slot and ts.layered and NativeTileset.overQuad(ts, slot)
            if oq and ts.overImage then love.graphics.draw(ts.overImage, oq, px, py) end
          end
        end
      end
    end
  end
  local mv = d and Decor.manifest().movement[d.shape]
  local ax = 16 * m.w + (mv and mv.cameraX or 120) - 8 * (m.w - 1) - 8
  if d and (d.shape == 2 or d.shape == 8 or d.shape == 9) then ax = ax - 8 end
  drawOw(avatarGfx(), ax, cy - 16)
end

-- pokeemerald/src/decoration.c:2324
local function drawPutAway()
  local m = D.mode
  local cx, cy = 112, 72
  if not m.hideCursor and (m.solid or m.blink <= 15) then
    local cur = Decor.manifest().putAwayCursor
    local path = cur and cur.variants and cur.variants[isFemale() and "female" or "male"]
    local img = path and image(path)
    if img then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, cx, cy)
    end
  end
  local ax, ay = cx + 16, cy - 16
  if m.avatarDX then ax, ay = cx + 16 + m.avatarDX * 16, cy - 16 + m.avatarDY * 16 end
  drawOw(avatarGfx(), ax, ay)
end

local function drawRegistry()
  local list = registryEntries()
  local tpl = REG_WIN.list
  frame(tpl)
  local ox, oy = tpl.left * 8, tpl.top * 8
  local shown = math.min(#list, MAX_SHOWN)
  for i = 0, shown - 1 do
    local e = list[D.regScroll + i + 1]
    if e then Window.printPx(e.name, ox + 8, oy + 9 + i * 16) end
  end
  Window.cursorPx(ox, oy + 9 + D.regRow * 16)
  if D.state == "registry_actions" then
    local a = Window.template(REG_WIN.actions.left, REG_WIN.actions.top,
      math.floor((math.max(FrlgFont.measure(text("gText_DelRegist")), FrlgFont.measure(text("gText_Cancel"))) + 9) / 8) + 1, 4)
    frame(a)
    local ph = Window.optionHeight()
    Window.printPx(text("gText_DelRegist"), a.left * 8 + 8, a.top * 8 + 1)
    Window.printPx(text("gText_Cancel"), a.left * 8 + 8, a.top * 8 + 1 + ph)
    Window.cursorPx(a.left * 8, a.top * 8 + 1 + D.regAction * ph)
  end
end

function D.draw()
  if not D.open_ then return end
  if D._opts and D._opts.draw then
    return D._opts.draw(D, {drawPlacing = drawPlacing, drawPutAway = drawPutAway})
  end
  local mode = D.mode
  if mode then
    if mode.kind == "place" then drawPlacing() else drawPutAway() end
  elseif D.view == "actions" then
    drawActions()
  elseif D.view == "categories" then
    drawCategories()
  elseif D.view == "items" then
    drawItems()
  elseif D.view == "registry" then
    drawRegistry()
  end
  if D.msg and D.view ~= "items" and D.view ~= "categories" then drawMessage() end
  if D.state == "yesno" then drawYesNo() end
end

-- pokeemerald/src/decoration.c:591
function D.openPlayerRoom(opts)
  opts = opts or {}
  opts.isPlayerRoom = true
  return D.open(opts)
end

return D
