local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Strings = require("src.core.Strings")
local RomText = require("src.core.game3.rom_text")
local FrlgFont = require("src.ui.game3.frlg_font")
local ListMenu = require("src.ui.game3.list_menu")

local UnionRoomScreen = {}

-- pokefirered/src/data/union_room.h:56
UnionRoomScreen.LIST_TEMPLATE = Window.template(1, 3, 13, 10)
-- pokefirered/src/data/union_room.h:66
UnionRoomScreen.COUNT_TEMPLATE = Window.template(16, 3, 7, 4)
-- pokefirered/src/data/union_room.h:165
UnionRoomScreen.INVITE_TEMPLATE = Window.template(20, 6, 8, 7)
-- pokefirered/src/data/union_room.h:203
UnionRoomScreen.REGISTER_TEMPLATE = Window.template(18, 8, 11, 5)
-- pokefirered/src/data/union_room.h:240
UnionRoomScreen.TYPES_TEMPLATE = Window.template(20, 2, 9, 11)
-- pokefirered/src/data/union_room.h:292
UnionRoomScreen.BOARD_HEADER_TEMPLATE = Window.template(1, 1, 28, 2)
-- pokefirered/src/data/union_room.h:302
UnionRoomScreen.BOARD_TEMPLATE = Window.template(1, 5, 28, 10)

-- pokefirered/src/data/union_room.h:197
UnionRoomScreen.ROW_HEIGHT = 14

-- pokefirered/src/link_rfu_3.c:949 CreateWirelessStatusIndicatorSprite
UnionRoomScreen.INDICATOR_X = 231
UnionRoomScreen.INDICATOR_Y = 8

-- pokefirered/src/data/union_room.h:250
UnionRoomScreen.TYPE_IDS = { 0, 10, 11, 13, 12, 15, 4, 5, 2, 14, 1, 3, 6, 7, 16, 8, 17 }
-- pokefirered/include/constants/pokemon.h:115
UnionRoomScreen.TYPE_EXIT = 18

-- pokefirered/src/union_room.c:4093
UnionRoomScreen.BOARD_OTHER = { fg = FrlgFont.STDPAL[14], shadow = FrlgFont.STDPAL[9], bg = FrlgFont.STDPAL[0] }
-- pokefirered/src/union_room.c:4086
UnionRoomScreen.BOARD_SELF = { fg = FrlgFont.STDPAL[7], shadow = FrlgFont.STDPAL[9], bg = FrlgFont.STDPAL[0] }
-- pokefirered/src/data/union_room.h:336
UnionRoomScreen.BOARD_CURSOR = { fg = FrlgFont.STDPAL[14], shadow = FrlgFont.STDPAL[13], bg = FrlgFont.STDPAL[0] }

UnionRoomScreen.open = false
UnionRoomScreen.mode = nil
UnionRoomScreen.items = {}
UnionRoomScreen.players = {}
UnionRoomScreen.lines = {}
UnionRoomScreen.cursor = 1
UnionRoomScreen._pollWait = 0
UnionRoomScreen._onSay = nil
UnionRoomScreen.list = nil
UnionRoomScreen.header = nil
UnionRoomScreen.capacity = nil
UnionRoomScreen.partner = nil
UnionRoomScreen._onChoose = nil
UnionRoomScreen._onCancel = nil
UnionRoomScreen._onConfirm = nil
UnionRoomScreen._onPoll = nil

function UnionRoomScreen.isOpen()
  return UnionRoomScreen.open and true or false
end

local function push()
  UnionRoomScreen.open = true
  Stack.push("union_room", UnionRoomScreen, { hideBelow = false, drawUnder = true })
end

local function clearCallbacks()
  UnionRoomScreen._onChoose = nil
  UnionRoomScreen._onCancel = nil
  UnionRoomScreen._onConfirm = nil
  UnionRoomScreen._onPoll = nil
  UnionRoomScreen._onSay = nil
  UnionRoomScreen.list = nil
  UnionRoomScreen.header = nil
end

-- pokefirered/src/union_room.c:3917
function UnionRoomScreen.showList(mode, opts)
  clearCallbacks()
  UnionRoomScreen.mode = mode
  UnionRoomScreen.items = opts.items or {}
  UnionRoomScreen.cursor = 1
  UnionRoomScreen.header = opts.header
  UnionRoomScreen._onChoose = opts.onChoose
  UnionRoomScreen._onCancel = opts.onCancel
  UnionRoomScreen.list = ListMenu.new({
    template = opts.template,
    frame = opts.frame or "std",
    items = UnionRoomScreen.items,
    maxShowed = opts.maxShowed or #UnionRoomScreen.items,
    itemX = opts.itemX or 8,
    cursorX = opts.cursorX or 0,
    upTextY = opts.upTextY or 0,
    rowHeight = opts.rowHeight or UnionRoomScreen.ROW_HEIGHT,
    letterSpacing = opts.letterSpacing or 1,
    onMove = function(_, index) UnionRoomScreen.cursor = index end,
  })
  UnionRoomScreen.list.cursorColors = opts.cursorColors
  UnionRoomScreen.list.fill = opts.fill
  if opts.cursor then
    local lm = UnionRoomScreen.list
    if opts.cursor <= lm:shown() then
      lm.scroll, lm.row = 0, opts.cursor - 1
    else
      lm:setSelected(opts.cursor)
    end
    UnionRoomScreen.cursor = opts.cursor
  end
  push()
  return true
end

-- pokefirered/src/union_room.c:2896
function UnionRoomScreen.showActivities(items, opts)
  opts = opts or {}
  local rows = {}
  for i, item in ipairs(items or {}) do
    rows[i] = { label = UnionRoomScreen.labelFor(item), id = item.key, item = item }
  end
  UnionRoomScreen.partner = opts.partner
  UnionRoomScreen.showList("activity", {
    template = UnionRoomScreen.INVITE_TEMPLATE,
    items = rows,
    maxShowed = 4,
    onChoose = opts.onChoose,
    onCancel = opts.onCancel,
  })
  UnionRoomScreen.items = items or {}
  return true
end

-- pokefirered/src/data/union_room.h:213
function UnionRoomScreen.showRegister(opts)
  opts = opts or {}
  local rows = {}
  for i = 0, 2 do
    rows[#rows + 1] = { label = RomText.plain(RomText.key("sListMenuItems_RegisterForTrade", i)), id = i + 1 }
  end
  return UnionRoomScreen.showList("register", {
    template = UnionRoomScreen.REGISTER_TEMPLATE,
    items = rows,
    maxShowed = 3,
    onChoose = opts.onChoose,
    onCancel = opts.onCancel,
  })
end

-- pokefirered/src/data/union_room.h:271
function UnionRoomScreen.showTypes(opts)
  opts = opts or {}
  local rows = {}
  for i, typeId in ipairs(UnionRoomScreen.TYPE_IDS) do
    rows[i] = { label = RomText.plain(RomText.key("sListMenuItems_TypeNames", i - 1)), id = typeId }
  end
  rows[#rows + 1] = { label = RomText.plain("gText_UR_Exit"), id = UnionRoomScreen.TYPE_EXIT }
  return UnionRoomScreen.showList("types", {
    template = UnionRoomScreen.TYPES_TEMPLATE,
    items = rows,
    maxShowed = 6,
    upTextY = 2,
    onChoose = opts.onChoose,
    onCancel = opts.onCancel,
  })
end

local function levelText(level)
  return tostring(math.floor(tonumber(level) or 0))
end

-- pokefirered/src/union_room.c:4348
function UnionRoomScreen.printBoardRow(entry, px, py, colors)
  if type(entry) ~= "table" then return end
  local ox = px - 12
  FrlgFont.draw(tostring(entry.name or ""), ox + 8, py, { colors = colors, letterSpacing = 1 })
  local species = tonumber(entry.species) or 0
  -- pokefirered/include/constants/species.h:421
  if species == 412 then
    FrlgFont.draw(RomText.plain("gText_UR_EggTrade"), ox + 68, py, { colors = colors, letterSpacing = 1 })
    return
  end
  local okS, SummaryChrome = pcall(require, "src.ui.game3.summary_chrome")
  if okS and SummaryChrome.drawTypeBadge then
    SummaryChrome.drawTypeBadge(tonumber(entry.wantType) or 0, ox + 68, py + 1)
  end
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  local name = okP and Pokemon.name and Pokemon.name(species) or ""
  FrlgFont.draw(tostring(name or ""), ox + 118, py, { colors = colors, letterSpacing = 1 })
  local lv = levelText(entry.level)
  local w = FrlgFont.measure(lv)
  FrlgFont.draw(lv, ox + 218 - w, py, { colors = colors, letterSpacing = 1 })
end

-- pokefirered/src/data/union_room.h:312
function UnionRoomScreen.showBoard(opts)
  opts = opts or {}
  local rows = {}
  rows[1] = { label = "", id = -3, disabled = true, entry = opts.own,
    print = function(item, px, py)
      if item.entry then UnionRoomScreen.printBoardRow(item.entry, px, py, UnionRoomScreen.BOARD_SELF) end
    end }
  local offers = opts.offers or {}
  for i = 0, 7 do
    local entry = offers[i + 1]
    rows[#rows + 1] = { label = "", id = i, disabled = entry == nil, entry = entry,
      print = function(item, px, py)
        if item.entry then UnionRoomScreen.printBoardRow(item.entry, px, py, UnionRoomScreen.BOARD_OTHER) end
      end }
  end
  rows[#rows + 1] = { label = RomText.plain("gText_UR_Exit2"), id = 8, colors = UnionRoomScreen.BOARD_OTHER }
  local shown = UnionRoomScreen.showList("board", {
    template = UnionRoomScreen.BOARD_TEMPLATE,
    items = rows,
    maxShowed = 5,
    itemX = 12,
    upTextY = 2,
    rowHeight = 15,
    header = UnionRoomScreen.BOARD_HEADER_TEMPLATE,
    cursorColors = UnionRoomScreen.BOARD_CURSOR,
    fill = FrlgFont.STDPAL[15],
    cursor = 2,
    onChoose = opts.onChoose,
    onCancel = opts.onCancel,
  })
  UnionRoomScreen.players = offers
  return shown
end

-- pokefirered/src/union_room.c:435 LL_STATE_PRINT_SEARCH_TEXT
function UnionRoomScreen.showPlayers(players, opts)
  opts = opts or {}
  clearCallbacks()
  UnionRoomScreen.mode = opts.mode or "group"
  UnionRoomScreen.players = players or {}
  UnionRoomScreen.items = {}
  UnionRoomScreen.cursor = 1
  UnionRoomScreen.capacity = opts.capacity
  UnionRoomScreen._onConfirm = opts.onConfirm
  UnionRoomScreen._onCancel = opts.onCancel
  UnionRoomScreen._onPoll = opts.onPoll
  UnionRoomScreen._onChoose = nil
  UnionRoomScreen._onSay = nil
  UnionRoomScreen._pollWait = 0
  push()
  return true
end

function UnionRoomScreen.close()
  if not UnionRoomScreen.open then return false end
  UnionRoomScreen.open = false
  Stack.pop("union_room")
  return true
end

function UnionRoomScreen.reset()
  UnionRoomScreen.open = false
  UnionRoomScreen.mode = nil
  UnionRoomScreen.items = {}
  UnionRoomScreen.players = {}
  UnionRoomScreen.lines = {}
  UnionRoomScreen.cursor = 1
  UnionRoomScreen.capacity = nil
  UnionRoomScreen.partner = nil
  UnionRoomScreen._onChoose = nil
  UnionRoomScreen._onCancel = nil
  UnionRoomScreen._onConfirm = nil
  UnionRoomScreen._onPoll = nil
  UnionRoomScreen._onSay = nil
  UnionRoomScreen._pollWait = 0
  UnionRoomScreen.list = nil
  UnionRoomScreen.header = nil
  Stack.pop("union_room")
  return true
end

function UnionRoomScreen.rowCount()
  if UnionRoomScreen.list then return #UnionRoomScreen.list.items end
  return #UnionRoomScreen.players
end

function UnionRoomScreen.move(delta)
  local lm = UnionRoomScreen.list
  if lm then
    local changed = lm:changeSelection(math.abs(delta), delta > 0)
    local _, index = lm:selected()
    UnionRoomScreen.cursor = index
    return changed
  end
  local n = UnionRoomScreen.rowCount()
  if n < 1 then return false end
  local c = UnionRoomScreen.cursor + delta
  if c < 1 then c = n elseif c > n then c = 1 end
  UnionRoomScreen.cursor = c
  return true
end

function UnionRoomScreen.select(index)
  local lm = UnionRoomScreen.list
  if not lm then return false end
  lm:setSelected(index)
  UnionRoomScreen.cursor = index
  return true
end

function UnionRoomScreen.confirm()
  local lm = UnionRoomScreen.list
  if lm then
    local _, current = lm:selected()
    if UnionRoomScreen.cursor ~= current then lm:setSelected(UnionRoomScreen.cursor) end
    local item, index = lm:selected()
    if not item then return false end
    if item.disabled then
      ListMenu.playSe("SE_WALL_HIT")
      return false
    end
    local cb = UnionRoomScreen._onChoose
    UnionRoomScreen.close()
    if cb then cb(index, item) end
    return true
  end
  local row = UnionRoomScreen.players[UnionRoomScreen.cursor]
  local cb = UnionRoomScreen._onConfirm
  if not cb then
    UnionRoomScreen.close()
    return true
  end
  if UnionRoomScreen.mode == "leader" then
    local min = (UnionRoomScreen.capacity and UnionRoomScreen.capacity.min) or 0
    if #UnionRoomScreen.players < math.max(min, 1) then return false end
  elseif not row then
    return false
  end
  UnionRoomScreen.close()
  cb(row and row.slot or nil)
  return true
end

function UnionRoomScreen.cancel()
  local cb = UnionRoomScreen._onCancel
  UnionRoomScreen.close()
  if cb then cb() end
  return true
end

-- pokefirered/src/union_room.c:2795 HandleUnionRoomPlayerRefresh
UnionRoomScreen.POLL_FRAMES = 30

function UnionRoomScreen.update(dt)
  if not UnionRoomScreen.open then return end
  if UnionRoomScreen.list then UnionRoomScreen.list:update(dt) end
  local Message = package.loaded["src.ui.game3.message"]
  if Message and Message.isOpen and Message.isOpen() then Message.tick() end
  local poll = UnionRoomScreen._onPoll
  if not poll then return end
  local wait = (UnionRoomScreen._pollWait or 0) - 1
  if wait > 0 then
    UnionRoomScreen._pollWait = wait
    return
  end
  UnionRoomScreen._pollWait = UnionRoomScreen.POLL_FRAMES
  local list = poll()
  if type(list) == "table" then
    UnionRoomScreen.players = list
    if UnionRoomScreen.cursor > #list then
      UnionRoomScreen.cursor = math.max(1, #list)
    end
  end
end

function UnionRoomScreen.handleInput(input)
  if not input then return end
  local lm = UnionRoomScreen.list
  if lm then
    if input:wasPressed("a") then
      UnionRoomScreen.confirm()
      return
    end
    if input:wasPressed("b") then
      ListMenu.playSe("SE_SELECT")
      UnionRoomScreen.cancel()
      return
    end
    lm:handleInput(input)
    local item, index = lm:selected()
    if item then UnionRoomScreen.cursor = index end
    return
  end
  if input:wasPressed("up") then UnionRoomScreen.move(-1)
  elseif input:wasPressed("down") then UnionRoomScreen.move(1)
  elseif input:wasPressed("a") then UnionRoomScreen.confirm()
  elseif input:wasPressed("start") and UnionRoomScreen.mode == "leader" then
    UnionRoomScreen.confirm()
  elseif input:wasPressed("b") then UnionRoomScreen.cancel()
  end
end

-- pokefirered/src/data/union_room.h:175 sListMenuItems_InviteToActivity
UnionRoomScreen.LABELS = RomText.lazy({
  GREETINGS = "sListMenuItems_InviteToActivity[0]",
  BATTLE = "sListMenuItems_InviteToActivity[1]",
  CHAT = "sListMenuItems_InviteToActivity[2]",
  EXIT = "sListMenuItems_InviteToActivity[3]",
})

function UnionRoomScreen.labelFor(item)
  return UnionRoomScreen.LABELS[item and item.key] or ""
end

-- pokefirered/src/data/union_room.h:1 sLinkGroupActivityNameTexts
UnionRoomScreen.ACTIVITY_LABELS = RomText.lazy({
  [1] = "sLinkGroupActivityNameTexts[1]",
  [2] = "sLinkGroupActivityNameTexts[2]",
  [4] = "sLinkGroupActivityNameTexts[4]",
  [5] = "sLinkGroupActivityNameTexts[5]",
  [8] = "sLinkGroupActivityNameTexts[8]",
  [12] = "sLinkGroupActivityNameTexts[12]",
})

function UnionRoomScreen.activityLabel(activity)
  local id = (tonumber(activity) or 0) % 0x40
  return UnionRoomScreen.ACTIVITY_LABELS[id] or ""
end

local function draw_frame(tpl)
  Window.stdFrame(tpl)
end

-- pokefirered/src/link_rfu_3.c:949 CreateWirelessStatusIndicatorSprite
local function draw_indicator()
  require("src.ui.game3.wireless_icon").draw(UnionRoomScreen.INDICATOR_X, UnionRoomScreen.INDICATOR_Y)
end

local function fillTemplate(tpl, color)
  local T = 8
  love.graphics.setColor(color[1], color[2], color[3], 1)
  love.graphics.rectangle("fill", tpl.left * T, tpl.top * T, tpl.w * T, tpl.h * T)
  love.graphics.setColor(1, 1, 1, 1)
end

function UnionRoomScreen.fontText(key)
  local out = {}
  for _, seg in ipairs(RomText.ir(key)) do
    if seg.t == "text" then
      out[#out + 1] = seg.s
    elseif seg.t == "ext" and type(seg.args) == "table" and seg.args[1] then
      out[#out + 1] = string.char(0xFC, tonumber(seg.cmd) or 0, (tonumber(seg.args[1]) or 0) % 256)
    end
  end
  return table.concat(out)
end

-- pokefirered/src/union_room.c:3900
local function drawBoardHeader(tpl)
  Window.stdFrame(tpl)
  fillTemplate(tpl, FrlgFont.STDPAL[15])
  FrlgFont.draw(UnionRoomScreen.fontText("gText_UR_NameWantedOfferLv"), tpl.left * 8 + 8, tpl.top * 8 + 1,
    { small = true, colors = UnionRoomScreen.BOARD_OTHER })
end

local function drawList(lm)
  if lm.fill then
    Window.stdFrame(lm.template)
    fillTemplate(lm.template, lm.fill)
    local frame = lm.frame
    lm.frame = "none"
    local cursorKind = lm.cursorKind
    lm.cursorKind = 1
    lm:draw()
    lm.frame, lm.cursorKind = frame, cursorKind
    if cursorKind == 0 and lm:shown() > 0 then
      Window.cursorPx(lm.template.left * 8 + lm.cursorX, lm:rowY(lm.row), { colors = lm.cursorColors })
    end
    return
  end
  lm:draw()
end

function UnionRoomScreen.draw()
  if not UnionRoomScreen.open then return end
  if not (love and love.graphics) then return end
  if UnionRoomScreen.list then
    if UnionRoomScreen.header then drawBoardHeader(UnionRoomScreen.header) end
    drawList(UnionRoomScreen.list)
    return
  end

  local tpl = UnionRoomScreen.LIST_TEMPLATE
  draw_frame(tpl)
  if #UnionRoomScreen.players == 0 then
    Window.print(Strings("Searching..."), Window.labelTx(tpl.left), tpl.top)
  end
  for i, row in ipairs(UnionRoomScreen.players) do
    local ty = Window.menuRowY(tpl.top, i)
    if ty > tpl.top + tpl.height - 1 then break end
    if i == UnionRoomScreen.cursor then Window.cursor(tpl.left, ty) end
    Window.print(tostring(row.name or ""), Window.labelTx(tpl.left), ty)
  end

  draw_indicator()
  local count = UnionRoomScreen.COUNT_TEMPLATE
  draw_frame(count)
  -- pokefirered/src/strings.c:1057 gText_Var1Players
  Window.print(RomText.plain("gText_Var1Players", { stringVars = { tostring(#UnionRoomScreen.players + 1) } }),
    count.left, count.top)
  -- pokefirered/src/data/union_room.h:1 sLinkGroupActivityNameTexts
  local sel = UnionRoomScreen.players[UnionRoomScreen.cursor]
  local label = sel and UnionRoomScreen.activityLabel(sel.activity) or ""
  if label ~= "" then Window.print(label, count.left, count.top + 2) end
end

return UnionRoomScreen
