local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Status = require("src.core.game3.link.status")

local LinkMenu = {}

LinkMenu.CACHE_DIR = "wireless_status"
LinkMenu.SCREEN_W = 240
LinkMenu.SCREEN_H = 160
-- pokefirered/src/wireless_communication_status_screen.c:251 CyclePalette
LinkMenu.CYCLE_FRAMES = 6
LinkMenu.ANIM_FIRST = 2
LinkMenu.ANIM_COUNT = 14
LinkMenu.CYCLE_COLORS = 8

-- pokefirered/src/wireless_communication_status_screen.c:91 sWindowTemplates
LinkMenu.TITLE_TEMPLATE = Window.template(3, 0, 24, 3)
LinkMenu.LIST_TEMPLATE = Window.template(3, 4, 22, 15)
LinkMenu.COUNT_TEMPLATE = Window.template(25, 4, 2, 15)

LinkMenu.open = false
LinkMenu.mode = nil
LinkMenu.rows = {}
LinkMenu.palIdx = 0
LinkMenu._counter = 0
LinkMenu._rowsWait = 0
LinkMenu._plaza = false
LinkMenu._art = nil
LinkMenu._artTried = false
LinkMenu._variants = {}
LinkMenu._onClose = nil

-- pokefirered/src/wireless_communication_status_screen.c:353 WCSS_AddTextPrinterParameterized
LinkMenu.COLOR = {
  NORMAL = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] },
  TOTAL = { fg = FrlgFont.STDPAL[4], shadow = FrlgFont.STDPAL[5], bg = FrlgFont.STDPAL[0] },
  TITLE = { fg = FrlgFont.STDPAL[7], shadow = FrlgFont.STDPAL[6], bg = FrlgFont.STDPAL[0] },
}

LinkMenu.OPT = {}
for key, colors in pairs(LinkMenu.COLOR) do LinkMenu.OPT[key] = { colors = colors } end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local okR, d = pcall(function() return Dataset.cache():read(rel) end)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local okR, d = pcall(CacheFs.readActive, rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local okR, d = pcall(love.filesystem.read, "data/generated/gba/" .. rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  local f = io.open("data/generated/gba/" .. rel, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 0 then return d end
  end
  return nil
end

local function load_manifest()
  local src = read_bytes(LinkMenu.CACHE_DIR .. "/manifest.lua")
  if not src then return nil end
  local chunk = load(src, "@wireless_status/manifest.lua", "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok and type(t) == "table" then return t end
  return nil
end

local function palette_banks(raw, banks)
  local out = {}
  for b = 0, banks - 1 do
    local bank = {}
    for c = 0, 15 do
      local off = (b * 16 + c) * 3
      bank[c] = {
        raw:byte(off + 1) or 0,
        raw:byte(off + 2) or 0,
        raw:byte(off + 3) or 0,
      }
    end
    out[b] = bank
  end
  return out
end

-- pokefirered/src/wireless_communication_status_screen.c:209 DecompressAndLoadBgGfxUsingHeap
function LinkMenu.loadArt()
  if LinkMenu._artTried then return LinkMenu._art end
  LinkMenu._artTried = true
  if not (love and love.graphics and love.image) then return nil end
  local manifest = load_manifest()
  local bg = manifest and manifest.bg
  local w, h = bg and tonumber(bg.width), bg and tonumber(bg.height)
  if not (w and h) then return nil end
  local rgba = read_bytes(LinkMenu.CACHE_DIR .. "/bg.rgba")
  if not rgba or #rgba ~= w * h * 4 then return nil end
  local okD, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not (okD and imageData) then return nil end
  local okI, image = pcall(love.graphics.newImage, imageData)
  if not okI then return nil end
  local pals = manifest.palettes or {}
  local banks = tonumber(pals.banks) or 16
  local raw = read_bytes(LinkMenu.CACHE_DIR .. "/palettes.pal")
  local index = read_bytes(LinkMenu.CACHE_DIR .. "/" .. (bg.index or "bg_index.bin"))
  if not index or #index ~= w * h then return nil end
  LinkMenu._art = {
    image = image,
    data = imageData,
    index = index,
    width = w,
    height = h,
    banks = raw and palette_banks(raw, banks) or nil,
    animFirst = tonumber(pals.anim_first) or LinkMenu.ANIM_FIRST,
    animCount = tonumber(pals.anim_count) or LinkMenu.ANIM_COUNT,
  }
  return LinkMenu._art
end

-- pokefirered/src/wireless_communication_status_screen.c:251 CyclePalette
function LinkMenu.variant(index)
  local art = LinkMenu._art
  if not (art and art.banks) then return art and art.image or nil end
  index = math.floor(tonumber(index) or 0)
  if index < 0 then return art.image end
  local cached = LinkMenu._variants[index]
  if cached then return cached end
  local anim = art.banks[art.animFirst + index]
  if not (anim and art.index) then return art.image end
  if not art.cycling then
    local list = {}
    local plane, w = art.index, art.width
    for i = 1, #plane do
      local v = plane:byte(i)
      if v >= 1 and v < LinkMenu.CYCLE_COLORS then
        list[#list + 1] = { (i - 1) % w, math.floor((i - 1) / w), v }
      end
    end
    art.cycling = list
  end
  if #art.cycling == 0 then
    LinkMenu._variants[index] = art.image
    return art.image
  end
  local okC, data = pcall(art.data.clone, art.data)
  if not (okC and data) then return art.image end
  for _, px in ipairs(art.cycling) do
    local to = anim[px[3]]
    data:setPixel(px[1], px[2], to[1] / 255, to[2] / 255, to[3] / 255, 1)
  end
  local okI, image = pcall(love.graphics.newImage, data)
  if not okI then return art.image end
  LinkMenu._variants[index] = image
  return image
end

function LinkMenu.isOpen()
  return LinkMenu.open and true or false
end

local function linkMod()
  return require("src.core.game3.link")
end

-- pokefirered/src/wireless_communication_status_screen.c:195 ShowWirelessCommunicationScreen
function LinkMenu.show(opts)
  opts = opts or {}
  LinkMenu.open = true
  LinkMenu.mode = "status"
  LinkMenu.palIdx = 0
  LinkMenu._counter = 0
  LinkMenu._rowsWait = LinkMenu.ROWS_FRAMES
  LinkMenu._onClose = opts.onClose
  LinkMenu._plaza = false
  local L = linkMod()
  if L.adapterConnected() then
    L.clientCall("joinPlaza", "wireless", L.liveProfile(), L.avatar())
    LinkMenu._plaza = true
  end
  LinkMenu.rows = Status.rows()
  if love and love.graphics then LinkMenu.loadArt() end
  Stack.push("wireless_status", LinkMenu, { hideBelow = true, fullscreen = true })
  return true
end

local function leavePlaza()
  if not LinkMenu._plaza then return end
  LinkMenu._plaza = false
  linkMod().clientCall("leavePlaza", "wireless")
end

function LinkMenu.close()
  if not LinkMenu.open then return false end
  LinkMenu.open = false
  leavePlaza()
  Stack.pop("wireless_status")
  local cb = LinkMenu._onClose
  LinkMenu._onClose = nil
  if cb then cb() end
  return true
end

function LinkMenu.reset()
  leavePlaza()
  LinkMenu.open = false
  LinkMenu.mode = nil
  LinkMenu.rows = {}
  LinkMenu.palIdx = 0
  LinkMenu._counter = 0
  LinkMenu._rowsWait = 0
  LinkMenu._onClose = nil
  LinkMenu._variants = {}
  LinkMenu._art = nil
  LinkMenu._artTried = false
  Stack.pop("wireless_status")
  return true
end

-- pokefirered/src/wireless_communication_status_screen.c:472 UpdateCommunicationCounts
LinkMenu.ROWS_FRAMES = 30

-- pokefirered/src/wireless_communication_status_screen.c:292 Task_WirelessCommunicationScreen
function LinkMenu.update(_dt)
  if not LinkMenu.open then return end
  local wait = (LinkMenu._rowsWait or 0) - 1
  if wait > 0 then
    LinkMenu._rowsWait = wait
  else
    LinkMenu._rowsWait = LinkMenu.ROWS_FRAMES
    LinkMenu.rows = Status.rows()
  end
  LinkMenu._counter = LinkMenu._counter + 1
  if LinkMenu._counter > 5 then
    LinkMenu._counter = 0
    LinkMenu.palIdx = LinkMenu.palIdx + 1
    if LinkMenu.palIdx >= LinkMenu.ANIM_COUNT then LinkMenu.palIdx = 0 end
  end
end

function LinkMenu.handleInput(input)
  if not (input and LinkMenu.open) then return end
  if input:wasPressed("a") or input:wasPressed("b") then
    local okA, Audio = pcall(require, "src.core.game3.audio")
    local okS, SE = pcall(require, "src.core.game3.se_ids")
    if okA and okS and Audio.playSe then pcall(Audio.playSe, SE.SE_SELECT) end
    LinkMenu.close()
  end
end

local function count_text(n)
  local value = math.floor(tonumber(n) or 0)
  if value < 10 then return " " .. tostring(value) end
  return tostring(value)
end

LinkMenu.countText = count_text

-- pokefirered/src/wireless_communication_status_screen.c:264 PrintHeaderTexts
function LinkMenu.draw()
  if not (LinkMenu.open and love and love.graphics) then return end
  local art = LinkMenu._art
  if art then
    local image = LinkMenu.variant(LinkMenu.palIdx)
    if image then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image, 0, 0)
    end
  else
    Window.stdFrame(LinkMenu.TITLE_TEMPLATE)
    Window.stdFrame(LinkMenu.LIST_TEMPLATE)
    Window.stdFrame(LinkMenu.COUNT_TEMPLATE)
  end

  local title = Status.HEADER[0]
  local titleW = FrlgFont.measure and FrlgFont.measure(title) or (#title * 5)
  Window.printPx(title, 24 + math.floor((192 - titleW) / 2), 6, LinkMenu.OPT.TITLE)
  for i, row in ipairs(LinkMenu.rows) do
    local y = 32 + 30 * (i - 1) + 10
    local opt = row.total and LinkMenu.OPT.TOTAL or LinkMenu.OPT.NORMAL
    Window.printPx(row.label, 24, y, opt)
    Window.printPx(count_text(row.count), 204, y, opt)
  end
end

local Direct = {}
LinkMenu.Direct = Direct

Direct.ID = "direct_corner"
-- pokefirered/src/data/union_room.h:165
Direct.MODES_TEMPLATE = Window.template(20, 6, 8, 7)
-- pokefirered/src/data/union_room.h:27
Direct.BAR_TEMPLATE = Window.template(0, 0, 30, 2)
-- pokefirered/src/data/union_room.h:105
Direct.LIST_TEMPLATE = Window.template(1, 3, 17, 10)
-- pokefirered/src/data/union_room.h:115
Direct.NAME_TEMPLATE = Window.template(20, 3, 7, 4)
-- pokefirered/src/cable_club.c:59
Direct.COUNT_TEMPLATE = Window.template(16, 11, 11, 2)
-- pokefirered/src/data/union_room.h:125
Direct.SLOTS = 16
-- pokefirered/src/union_room.c:1656
Direct.NEW_FRAMES = 64
Direct.REFRESH_FRAMES = 10
Direct.MODES = { "auto", "choose", "pin", "exit" }

-- pokefirered/src/union_room.c:4079
Direct.BAR_COLORS = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] }
Direct.BAR_FILL = FrlgFont.STDPAL[2]

Direct.open = false
Direct.view = nil
Direct.opts = {}
Direct.frozen = false
Direct.onLeave = nil
Direct.notice = false
Direct.count = 0
Direct.slots = {}
Direct.fresh = {}
Direct.rows = {}
Direct.modes = nil
Direct.list = nil
Direct._refresh = 0

local function RomText() return require("src.core.game3.rom_text") end
local function ListMenu() return require("src.ui.game3.list_menu") end
local function Message() return require("src.ui.game3.message") end
local function Choice() return require("src.ui.game3.choice") end

function Direct.modeLabel(key)
  local Strings = require("src.core.Strings")
  if key == "auto" then return Strings("AUTO") end
  if key == "choose" then return Strings("CHOOSE") end
  if key == "pin" then return Strings("SET PIN") end
  -- pokefirered/src/data/union_room.h:179
  return RomText().plain("gText_UR_Exit")
end

function Direct.isOpen()
  return Direct.open and true or false
end

function Direct.show(opts)
  Direct.opts = opts or {}
  Direct.open = true
  Direct.frozen = false
  Direct.onLeave = nil
  Direct.notice = false
  Stack.push(Direct.ID, Direct, { hideBelow = false, drawUnder = true })
  return true
end

function Direct.close()
  if not Direct.open then return false end
  Direct.open = false
  Direct.view = nil
  Direct.modes = nil
  Direct.list = nil
  Direct.frozen = false
  Direct.onLeave = nil
  Direct.notice = false
  Direct.count = 0
  Stack.pop(Direct.ID)
  return true
end

function Direct.reset()
  Direct.close()
  Direct.opts = {}
  Direct.slots = {}
  Direct.fresh = {}
  Direct.rows = {}
  Direct._refresh = 0
end

-- pokefirered/src/data/union_room.h:182
function Direct.showModes(opts)
  opts = opts or {}
  local LM = ListMenu()
  local items = {}
  for _, key in ipairs(Direct.MODES) do
    items[#items + 1] = { label = Direct.modeLabel(key), id = key }
  end
  Direct.view = "modes"
  Direct.frozen = false
  Direct.modes = LM.new({
    template = Direct.MODES_TEMPLATE, frame = "std", items = items, maxShowed = #items,
    itemX = 8, cursorX = 0, upTextY = 0, rowHeight = FrlgFont.GLYPH_HEIGHT, letterSpacing = 1,
    arrows = false,
    onSelect = function(item)
      LM.playSe("SE_SELECT")
      if opts.onChoose then opts.onChoose(item.id) end
    end,
    onCancel = function()
      LM.playSe("SE_SELECT")
      if opts.onCancel then opts.onCancel() end
    end,
  })
  if opts.cursor then Direct.modes:setSelected(opts.cursor) end
  return Direct.modes
end

local function rowColors(row)
  local LM = ListMenu()
  if row.locked or row.disabled then return LM.COLOR_WHITE, LM.COLOR_WHITE end
  if (Direct.fresh[row.key] or 0) > 0 then return FrlgFont.COLOR.GREEN, FrlgFont.COLOR.GREEN end
  local name = row.gender == 1 and FrlgFont.COLOR.FEMALE_NPC or FrlgFont.COLOR.MALE_NPC
  return name, FrlgFont.COLOR.NORMAL
end

Direct.rowColors = rowColors

-- pokefirered/src/union_room.c:4215
function Direct.printRow(item, px, py, _selected, index)
  local RT = RomText()
  FrlgFont.draw(("%02d"):format(index) .. RT.plain("gText_UR_Colon"), px, py,
    { small = true, colors = FrlgFont.COLOR.NORMAL })
  local row = item.row
  if not row then return end
  local nameColors, idColors = rowColors(row)
  local x = px + 18
  if row.locked then
    ListMenu().drawLock(x, py + 3)
    x = x + ListMenu().LOCK_W
  end
  FrlgFont.draw(tostring(row.name or ""), x, py, { colors = nameColors })
  local id = ("%05d"):format(math.floor(tonumber(row.trainerId) or 0) % 65536)
  FrlgFont.draw(RT.plain("gText_UR_ID") .. id, px + 95, py, { small = true, colors = idColors })
end

function Direct.buildItems()
  local items = {}
  local last = Direct.SLOTS
  for slot in pairs(Direct.slots) do
    if slot > last then last = slot end
  end
  for i = 1, last do
    local key = Direct.slots[i]
    local row = key and Direct.rows[key] or nil
    items[i] = { id = i, row = row, disabled = row == nil or row.disabled == true, print = Direct.printRow }
  end
  return items
end

-- pokefirered/src/union_room.c:1637
function Direct.refresh(entries)
  local present, order = {}, {}
  for _, row in ipairs(entries or {}) do
    if type(row) == "table" and row.key ~= nil and not present[row.key] then
      present[row.key] = row
      order[#order + 1] = row
    end
  end
  local placed = {}
  for slot, key in pairs(Direct.slots) do
    if present[key] then
      placed[key] = slot
    else
      Direct.slots[slot] = nil
      Direct.fresh[key] = nil
    end
  end
  local arrived = false
  for _, row in ipairs(order) do
    if not placed[row.key] then
      local slot = 1
      while Direct.slots[slot] ~= nil do slot = slot + 1 end
      Direct.slots[slot] = row.key
      placed[row.key] = slot
      Direct.fresh[row.key] = Direct.NEW_FRAMES
      arrived = true
    end
  end
  Direct.rows = present
  if Direct.list then Direct.list:setItems(Direct.buildItems(), true) end
  return arrived
end

-- pokefirered/src/union_room.c:1146
function Direct.showChoose(opts)
  opts = opts or {}
  local LM = ListMenu()
  Direct.view = "choose"
  Direct.frozen = false
  Direct.onLeave = nil
  Direct.me = opts.me or Direct.me
  Direct.source = opts.rows
  Direct.slots, Direct.fresh, Direct.rows = {}, {}, {}
  Direct.list = LM.new({
    template = Direct.LIST_TEMPLATE, frame = "std", items = {}, maxShowed = 5,
    itemX = 8, cursorX = 0, upTextY = 0, rowHeight = FrlgFont.GLYPH_HEIGHT + 2,
    scrollMultiple = "dpad", arrows = true,
    onSelect = function(item)
      if Direct.frozen then return end
      if opts.onPick then opts.onPick(item.row, item.id) end
    end,
    onCancel = function()
      if Direct.frozen then return end
      if opts.onCancel then opts.onCancel() end
    end,
  })
  if type(Direct.source) == "function" then Direct.refresh(Direct.source()) end
  Direct.list:setItems(Direct.buildItems(), false)
  Direct._refresh = Direct.REFRESH_FRAMES
  return Direct.list
end

function Direct.setFrozen(frozen)
  Direct.frozen = frozen and true or false
  if not Direct.frozen then Direct.onLeave = nil end
end

-- pokefirered/src/union_room.c:1332
function Direct.setLeave(cb)
  Direct.onLeave = cb
end

function Direct.showWait(opts)
  opts = opts or {}
  Direct.view = "wait"
  Direct.frozen = false
  Direct.onWaitCancel = opts.onCancel
  Direct.count = tonumber(opts.count) or 0
end

function Direct.setCount(n)
  Direct.count = tonumber(n) or 0
end

function Direct.setNotice(on)
  Direct.notice = on and true or false
end

local function forwardChoice(input)
  local C = Choice()
  if input:wasPressed("up") then C.move(-1, 0)
  elseif input:wasPressed("down") then C.move(1, 0)
  elseif input:wasPressed("left") then C.move(0, -1)
  elseif input:wasPressed("right") then C.move(0, 1)
  elseif input:wasPressed("a") then C.confirm()
  elseif input:wasPressed("b") then C.cancel()
  end
end

function Direct.handleInput(input)
  if not (input and Direct.open) then return end
  if Choice().isOpen() then return forwardChoice(input) end
  local M = Message()
  if Direct.notice then
    if M.isOpen() and (input:wasPressed("a") or input:wasPressed("b")) then
      if M.isWaiting() then M.advance() else M.skipReveal() end
    end
    return
  end
  if Direct.view == "modes" and Direct.modes then
    Direct.modes:handleInput(input)
  elseif Direct.view == "choose" and Direct.list then
    if Direct.frozen then
      if Direct.onLeave and input:wasPressed("b") then Direct.onLeave() end
      return
    end
    Direct.list:handleInput(input)
  elseif Direct.view == "wait" then
    if input:wasPressed("b") and Direct.onWaitCancel then Direct.onWaitCancel() end
  end
end

function Direct.update(dt)
  if not Direct.open then return end
  local M = Message()
  if M.isOpen() then M.tick() end
  if Direct.modes then Direct.modes:update(dt) end
  if Direct.list then
    Direct.list:update(dt)
    for key, n in pairs(Direct.fresh) do
      if n > 0 then Direct.fresh[key] = n - 1 end
    end
    Direct._refresh = Direct._refresh - 1
    if Direct._refresh <= 0 and type(Direct.source) == "function" then
      Direct._refresh = Direct.REFRESH_FRAMES
      -- pokefirered/src/union_room.c:1204
      if Direct.refresh(Direct.source()) then ListMenu().playSe("SE_PC_LOGIN") end
    end
  end
  local cb = Direct.opts.onUpdate
  if cb then cb(dt) end
end

-- pokefirered/src/union_room.c:346
local function drawNameAndId()
  local tpl = Direct.NAME_TEMPLATE
  Window.stdFrame(tpl)
  local me = Direct.me or {}
  local x, y = tpl.left * 8, tpl.top * 8
  FrlgFont.draw(tostring(me.name or ""), x, y + 2, { colors = FrlgFont.COLOR.NORMAL })
  local id = ("%05d"):format(math.floor(tonumber(me.trainerId) or 0) % 65536)
  FrlgFont.draw(RomText().plain("gText_UR_ID") .. id, x, y + 16, { small = true, colors = FrlgFont.COLOR.NORMAL })
end

-- pokefirered/src/union_room.c:1181
local function drawCancelBar()
  local tpl = Direct.BAR_TEMPLATE
  love.graphics.setColor(Direct.BAR_FILL)
  love.graphics.rectangle("fill", tpl.left * 8, tpl.top * 8, tpl.w * 8, tpl.h * 8)
  love.graphics.setColor(1, 1, 1, 1)
  FrlgFont.draw(RomText().plain("gText_UR_ChooseJoinCancel"), tpl.left * 8 + 8, tpl.top * 8 + 2,
    { small = true, colors = Direct.BAR_COLORS })
end

-- pokefirered/src/cable_club.c:87
local function drawPlayerCount()
  local tpl = Direct.COUNT_TEMPLATE
  Window.stdFrame(tpl)
  FrlgFont.draw(RomText().plain("gText_NumPlayerLink", { stringVars = { tostring(Direct.count) } }),
    tpl.left * 8, tpl.top * 8, { colors = FrlgFont.COLOR.NORMAL })
end

function Direct.draw()
  if not (Direct.open and love and love.graphics) then return end
  if Direct.view == "modes" and Direct.modes then
    Direct.modes:draw()
  elseif Direct.view == "choose" and Direct.list then
    drawCancelBar()
    Direct.list:draw()
    drawNameAndId()
  end
  if Direct.count >= 2 then drawPlayerCount() end
end

return LinkMenu
