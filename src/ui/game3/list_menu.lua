local Display = require("src.core.game3.display")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")

local ListMenu = {}
ListMenu.__index = ListMenu

local T = Display.TILE

ListMenu.CHROME = "data/generated/gba/chrome/"
ListMenu.LOCK_NORMAL = "assets/game3/lock8.png"
-- pokefirered/src/main.c:286
ListMenu.REPEAT_START = 40
ListMenu.REPEAT_CONTINUE = 5
ListMenu.LOCK_W = 10

-- pokefirered/src/union_room.c:4072
ListMenu.COLOR_WHITE = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] }

ListMenu._arrows = nil
ListMenu._locks = {}

local function playSe(name)
  local okA, Audio = pcall(require, "src.core.game3.audio")
  local okS, SE = pcall(require, "src.core.game3.se_ids")
  if okA and okS and Audio.playSe and SE[name] then pcall(Audio.playSe, SE[name]) end
end

ListMenu.playSe = playSe

function ListMenu.new(opts)
  opts = opts or {}
  local self = setmetatable({}, ListMenu)
  self.template = opts.template or Window.template(0, 0, 8, 2)
  self.frame = opts.frame or "std"
  self.items = opts.items or {}
  self.maxShowed = math.max(1, math.floor(tonumber(opts.maxShowed) or #self.items))
  self.itemX = tonumber(opts.itemX) or 8
  self.cursorX = tonumber(opts.cursorX) or 0
  self.upTextY = tonumber(opts.upTextY) or 1
  self.rowHeight = tonumber(opts.rowHeight) or 16
  self.letterSpacing = tonumber(opts.letterSpacing) or 0
  self.scrollMultiple = opts.scrollMultiple or "none"
  self.sound = opts.sound ~= false
  self.cursorKind = tonumber(opts.cursorKind) or 0
  self.arrows = opts.arrows ~= false
  self.onSelect = opts.onSelect
  self.onCancel = opts.onCancel
  self.onMove = opts.onMove
  self.scroll = 0
  self.row = 0
  self.frames = 0
  self._held = nil
  self._heldFrames = 0
  return self
end

function ListMenu:shown()
  return math.max(0, math.min(self.maxShowed, #self.items))
end

function ListMenu:clamp()
  local n = #self.items
  local shown = self:shown()
  if n == 0 then
    self.scroll, self.row = 0, 0
    return
  end
  if self.scroll > n - shown then self.scroll = math.max(0, n - shown) end
  if self.scroll < 0 then self.scroll = 0 end
  if self.row > shown - 1 then self.row = math.max(0, shown - 1) end
  if self.row < 0 then self.row = 0 end
end

function ListMenu:setItems(items, keepCursor)
  self.items = items or {}
  if not keepCursor then
    self.scroll, self.row = 0, 0
  end
  self:clamp()
end

function ListMenu:selected()
  local index = self.scroll + self.row + 1
  return self.items[index], index
end

function ListMenu:setSelected(index)
  local n = #self.items
  local shown = self:shown()
  index = math.max(1, math.min(n, math.floor(tonumber(index) or 1)))
  if n == 0 then return end
  local scroll = math.max(0, math.min(index - 1, n - shown))
  self.scroll = scroll
  self.row = index - 1 - scroll
end

-- pokefirered/src/list_menu.c:438
function ListMenu:step(down)
  local n = #self.items
  local shown = self:shown()
  if shown == 0 then return 0 end
  local row, scroll = self.row, self.scroll
  if not down then
    local newRow = shown == 1 and 0 or (shown - (math.floor(shown / 2) + shown % 2) - 1)
    if scroll == 0 then
      if row > 0 then
        self.row = row - 1
        return 1
      end
      return 0
    end
    if row > newRow then
      self.row = row - 1
      return 1
    end
    self.row = newRow
    self.scroll = scroll - 1
    return 2
  end
  local newRow = shown == 1 and 0 or (math.floor(shown / 2) + shown % 2)
  if scroll == n - shown then
    if row < shown - 1 then
      self.row = row + 1
      return 1
    end
    return 0
  end
  if row < newRow then
    self.row = row + 1
    return 1
  end
  self.row = newRow
  self.scroll = scroll + 1
  return 2
end

-- pokefirered/src/list_menu.c:558
function ListMenu:changeSelection(count, down)
  local changed = false
  for _ = 1, math.max(1, count or 1) do
    if self:step(down) ~= 0 then changed = true end
  end
  if changed then
    -- pokefirered/src/list_menu.c:620
    if self.sound then playSe("SE_SELECT") end
    if self.onMove then
      local item, index = self:selected()
      self.onMove(item, index)
    end
  end
  return changed
end

local HELD_KEYS = { "up", "down", "left", "right", "l", "r" }

function ListMenu:trackHeld(input)
  local key
  if input and input.isDown then
    for _, k in ipairs(HELD_KEYS) do
      local ok, down = pcall(input.isDown, input, k)
      if ok and down then
        key = k
        break
      end
    end
  end
  local fresh = key and input:wasPressed(key)
  if key ~= self._held or fresh then
    self._held = key
    self._heldFrames = 0
  elseif key then
    self._heldFrames = self._heldFrames + 1
  end
end

function ListMenu:repeated(input, key)
  if input:wasPressed(key) then return true end
  return self._held == key and self._heldFrames >= ListMenu.REPEAT_START
    and (self._heldFrames - ListMenu.REPEAT_START) % ListMenu.REPEAT_CONTINUE == 0
end

-- pokefirered/src/list_menu.c:166
function ListMenu:handleInput(input)
  if not input then return nil end
  self:trackHeld(input)
  if input:wasPressed("a") then
    local item, index = self:selected()
    if not item then return nil end
    if item.disabled then
      -- pokefirered/src/union_room.c:1234
      playSe("SE_WALL_HIT")
      return nil
    end
    if self.onSelect then self.onSelect(item, index) end
    return "select"
  end
  if input:wasPressed("b") then
    if self.onCancel then self.onCancel() end
    return "cancel"
  end
  if self:repeated(input, "up") then
    return self:changeSelection(1, false) and "move" or nil
  end
  if self:repeated(input, "down") then
    return self:changeSelection(1, true) and "move" or nil
  end
  local left, right = false, false
  if self.scrollMultiple == "dpad" then
    left, right = self:repeated(input, "left"), self:repeated(input, "right")
  elseif self.scrollMultiple == "lr" then
    left, right = self:repeated(input, "l"), self:repeated(input, "r")
  end
  if left then return self:changeSelection(self.maxShowed, false) and "move" or nil end
  if right then return self:changeSelection(self.maxShowed, true) and "move" or nil end
  return nil
end

function ListMenu:update(_dt)
  self.frames = self.frames + 1
end

function ListMenu.itemColors(item)
  if item.locked or item.disabled then return ListMenu.COLOR_WHITE end
  return item.colors or FrlgFont.COLOR.NORMAL
end

function ListMenu.printItem(item, px, py, letterSpacing)
  local x = px
  if item.locked then
    ListMenu.drawLock(px, py + 3)
    x = px + ListMenu.LOCK_W
  end
  FrlgFont.draw(tostring(item.label or ""), x, py, {
    colors = ListMenu.itemColors(item),
    letterSpacing = letterSpacing,
  })
end

function ListMenu:rowY(i)
  return (self.template.top or self.template.tilemapTop) * T + i * self.rowHeight + self.upTextY
end

function ListMenu:draw()
  if not (love and love.graphics) then return end
  local tpl = self.template
  if self.frame == "std" then
    Window.stdFrame(tpl)
  elseif self.frame == "fixed" then
    Window.fixedStdFrame(tpl)
  end
  local ox = (tpl.left or tpl.tilemapLeft) * T
  local shown = self:shown()
  for i = 0, shown - 1 do
    local index = self.scroll + i + 1
    local item = self.items[index]
    if item then
      local px, py = ox + self.itemX, self:rowY(i)
      if item.print then
        item.print(item, px, py, i == self.row, index)
      else
        ListMenu.printItem(item, px, py, self.letterSpacing)
      end
    end
  end
  if self.cursorKind == 0 and shown > 0 then
    Window.cursorPx(ox + self.cursorX, self:rowY(self.row))
  end
  local n = #self.items
  if self.arrows and n > shown then
    ListMenu.drawScrollArrows(tpl, self.scroll > 0, self.scroll < n - shown, self.frames)
  end
end

local function lockImage(path)
  local cached = ListMenu._locks[path]
  if cached then return cached end
  local image = love.graphics.newImage(path)
  image:setFilter("nearest", "nearest")
  ListMenu._locks[path] = image
  return image
end

function ListMenu.drawLock(px, py, path)
  if not (love and love.graphics) then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(lockImage(path or ListMenu.LOCK_NORMAL), px, py)
end

-- pokefirered/src/menu_indicators.c:323
function ListMenu.loadArrows()
  if ListMenu._arrows then return ListMenu._arrows end
  local cache = require("src.core.game3.dataset").cache()
  local src = cache:read(ListMenu.CHROME .. "manifest.lua")
  assert(type(src) == "string", "chrome/manifest.lua missing from the cache")
  local manifest = assert(load(src, "@chrome/manifest.lua", "t", {}))()
  local entry = assert(manifest.scroll_arrows, "chrome manifest has no scroll_arrows")
  local w, h = tonumber(entry.width), tonumber(entry.height)
  local fw, fh = tonumber(entry.frame_w) or 16, tonumber(entry.frame_h) or 16
  local rgba = cache:read(ListMenu.CHROME .. entry.file)
  assert(type(rgba) == "string" and #rgba == w * h * 4, "chrome/scroll_arrows.rgba missing")
  local image = love.graphics.newImage(love.image.newImageData(w, h, "rgba8", rgba))
  image:setFilter("nearest", "nearest")
  local frames = {}
  for i, name in ipairs(entry.order) do
    frames[name] = {
      quad = love.graphics.newQuad(0, (i - 1) * fh, fw, fh, w, h),
      bounce = entry.bounce[i],
    }
  end
  ListMenu._arrows = { image = image, frames = frames, w = fw, h = fh }
  return ListMenu._arrows
end

local function sine(pos)
  local v = math.sin((pos % 256) * math.pi * 2 / 256) * 256
  return v < 0 and math.ceil(v - 0.5) or math.floor(v + 0.5)
end

-- pokefirered/src/menu_indicators.c:270
function ListMenu.bounce(entry, t)
  if not entry then return 0, 0 end
  local pos = (math.floor(tonumber(t) or 0) * entry.frequency) % 256
  local v = sine(pos) * entry.multiplier / 256
  v = v < 0 and math.ceil(v) or math.floor(v)
  if entry.bounceDir == 1 then return 0, v end
  return v, 0
end

function ListMenu.drawArrow(dir, cx, cy, t)
  if not (love and love.graphics) then return end
  local art = ListMenu.loadArrows()
  local frame = art.frames[dir]
  if not frame then return end
  local dx, dy = ListMenu.bounce(frame.bounce, t)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(art.image, frame.quad, cx - art.w / 2 + dx, cy - art.h / 2 + dy)
end

function ListMenu.drawScrollArrows(template, showUp, showDown, t)
  local left = template.left or template.tilemapLeft
  local top = template.top or template.tilemapTop
  local w = template.w or template.width
  local h = template.h or template.height
  local cx = (left + w / 2) * T
  if showUp then ListMenu.drawArrow("up", cx, top * T, t) end
  if showDown then ListMenu.drawArrow("down", cx, (top + h) * T, t) end
end

return ListMenu
