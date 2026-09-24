local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")
local Strings = require("src.core.Strings")
local ListMenu = require("src.ui.game3.list_menu")

local PinEntry = {}

PinEntry.ID = "pin_entry"
PinEntry.WINDOW = Window.template(9, 6, 12, 5)
PinEntry.LENGTH = 4
PinEntry.CHARSET = "0123456789"
-- pokefirered/charmap.txt:81
PinEntry.MASK_GLYPH = 0xAF
PinEntry.LOCK = "assets/game3/lock8.png"
PinEntry.CELL_W = 16
PinEntry.LOCK_X = 80
PinEntry.CELL_X = 96
PinEntry.DIGIT_Y = 59
PinEntry.RING_Y = 57
PinEntry.UNDERSCORE_Y = 68
PinEntry.ARROW_UP_Y = 48
PinEntry.ARROW_DOWN_Y = 88
-- pokefirered/src/naming_screen.c:1100
PinEntry.BOB = { 2, 3, 2, 1 }
PinEntry.BOB_DELAY = 9
PinEntry.CURSOR_PATH = "data/generated/gba/naming/cursor.png"

PinEntry.open = false
PinEntry.mode = "enter"
PinEntry.title = nil
PinEntry.error = nil
PinEntry.digits = {}
PinEntry.visited = {}
PinEntry.cursor = 1
PinEntry.frames = 0
PinEntry._onDone = nil
PinEntry._held = nil
PinEntry._heldFrames = 0
PinEntry._ring = nil

local function playSe(name) ListMenu.playSe(name) end

function PinEntry.defaultTitle(mode)
  if mode == "set" then return Strings("Set a 4-digit PIN.") end
  return Strings("Enter the 4-digit PIN.")
end

local function resetDigits()
  PinEntry.digits = {}
  PinEntry.visited = {}
  for i = 1, PinEntry.LENGTH do PinEntry.digits[i] = 0 end
  PinEntry.visited[1] = true
  PinEntry.cursor = 1
end

function PinEntry.show(opts)
  opts = opts or {}
  PinEntry.mode = opts.mode == "set" and "set" or "enter"
  PinEntry.title = opts.title or PinEntry.defaultTitle(PinEntry.mode)
  PinEntry.error = nil
  PinEntry._onDone = opts.onDone
  PinEntry.frames = 0
  PinEntry._held = nil
  PinEntry._heldFrames = 0
  resetDigits()
  PinEntry.open = true
  Stack.push(PinEntry.ID, PinEntry, { hideBelow = false, drawUnder = true })
  return true
end

function PinEntry.isOpen()
  return PinEntry.open and true or false
end

function PinEntry.setError(text)
  PinEntry.error = text
  resetDigits()
end

function PinEntry.close()
  if not PinEntry.open then return false end
  PinEntry.open = false
  Stack.pop(PinEntry.ID)
  return true
end

function PinEntry.reset()
  PinEntry.close()
  PinEntry.error = nil
  PinEntry.title = nil
  PinEntry._onDone = nil
  resetDigits()
end

function PinEntry.pin()
  local out = {}
  for i = 1, PinEntry.LENGTH do out[i] = PinEntry.CHARSET:sub(PinEntry.digits[i] + 1, PinEntry.digits[i] + 1) end
  return table.concat(out)
end

local function finish(pin)
  local cb = PinEntry._onDone
  PinEntry._onDone = nil
  PinEntry.close()
  if cb then cb(pin) end
end

function PinEntry.scrub(delta)
  local i = PinEntry.cursor
  PinEntry.digits[i] = (PinEntry.digits[i] + delta) % #PinEntry.CHARSET
  PinEntry.error = nil
  playSe("SE_SELECT")
end

function PinEntry.move(delta)
  local c = PinEntry.cursor + delta
  if c < 1 or c > PinEntry.LENGTH then return false end
  PinEntry.cursor = c
  PinEntry.visited[c] = true
  playSe("SE_SELECT")
  return true
end

function PinEntry.confirm()
  playSe("SE_SELECT")
  finish(PinEntry.pin())
end

function PinEntry.cancel()
  playSe("SE_SELECT")
  finish(nil)
end

local HELD = { "up", "down", "left", "right" }

local function trackHeld(input)
  local key
  if input.isDown then
    for _, k in ipairs(HELD) do
      if input:isDown(k) then
        key = k
        break
      end
    end
  end
  if key ~= PinEntry._held or (key and input:wasPressed(key)) then
    PinEntry._held = key
    PinEntry._heldFrames = 0
  elseif key then
    PinEntry._heldFrames = PinEntry._heldFrames + 1
  end
end

local function repeated(input, key)
  if input:wasPressed(key) then return true end
  return PinEntry._held == key and PinEntry._heldFrames >= ListMenu.REPEAT_START
    and (PinEntry._heldFrames - ListMenu.REPEAT_START) % ListMenu.REPEAT_CONTINUE == 0
end

-- pokefirered/src/naming_screen.c:1471
function PinEntry.handleInput(input)
  if not (input and PinEntry.open) then return end
  trackHeld(input)
  if input:wasPressed("a") then
    if PinEntry.cursor < PinEntry.LENGTH then
      PinEntry.move(1)
    else
      PinEntry.confirm()
    end
  elseif input:wasPressed("start") then
    if PinEntry.cursor < PinEntry.LENGTH then
      for i = PinEntry.cursor, PinEntry.LENGTH do PinEntry.visited[i] = true end
      PinEntry.cursor = PinEntry.LENGTH
      playSe("SE_SELECT")
    else
      PinEntry.confirm()
    end
  elseif input:wasPressed("b") then
    PinEntry.cancel()
  elseif repeated(input, "up") then
    PinEntry.scrub(1)
  elseif repeated(input, "down") then
    PinEntry.scrub(-1)
  elseif repeated(input, "left") then
    PinEntry.move(-1)
  elseif repeated(input, "right") then
    PinEntry.move(1)
  end
end

function PinEntry.update(_dt)
  if PinEntry.open then PinEntry.frames = PinEntry.frames + 1 end
end

function PinEntry.cellX(i)
  return PinEntry.CELL_X + (i - 1) * PinEntry.CELL_W
end

local function ring()
  if PinEntry._ring then return PinEntry._ring end
  local data = love.image.newImageData(PinEntry.CURSOR_PATH)
  local mask = love.image.newImageData(16, 16)
  local base = love.image.newImageData(16, 16)
  base:paste(data, 0, 0, 0, 0, 16, 16)
  local main
  for y = 0, 15 do
    for x = 0, 15 do
      local r, g, b, a = base:getPixel(x, y)
      if a > 0 and (main == nil or r > main) and g < 0.1 then main = r end
    end
  end
  for y = 0, 15 do
    for x = 0, 15 do
      local r, g, _, a = base:getPixel(x, y)
      if a > 0 and r == main and g < 0.1 then mask:setPixel(x, y, 1, 1, 1, 1) end
    end
  end
  PinEntry._ring = { base = love.graphics.newImage(base), mask = love.graphics.newImage(mask) }
  return PinEntry._ring
end

-- pokefirered/src/naming_screen.c:1039
function PinEntry.flash(frames)
  local step = math.floor(frames / 2) % 16
  local color = step <= 8 and step * 2 or (32 - step * 2)
  return color / 16
end

local function drawCursor(x)
  local art = ring()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(art.base, x, PinEntry.RING_Y)
  love.graphics.setColor(1, 1, 1, PinEntry.flash(PinEntry.frames))
  love.graphics.draw(art.mask, x, PinEntry.RING_Y)
  love.graphics.setColor(1, 1, 1, 1)
end

function PinEntry.draw()
  if not (PinEntry.open and love and love.graphics) then return end
  Window.dialogueFrame()
  FrlgFont.draw(PinEntry.error or PinEntry.title or "", Chrome.DLG_LEFT * 8, Chrome.DLG_TOP * 8 + 1, {
    maxWidth = Chrome.DLG_W * 8, colors = FrlgFont.COLOR.NORMAL,
  })
  Window.stdFrame(PinEntry.WINDOW)
  ListMenu.drawLock(PinEntry.LOCK_X, PinEntry.DIGIT_Y + 3, PinEntry.LOCK)
  local NamingChrome = require("src.ui.game3.naming_chrome")
  local underscore = NamingChrome.get("underscore")
  assert(underscore, "naming/underscore.png missing from the cache")
  local bob = PinEntry.BOB[math.floor(PinEntry.frames / PinEntry.BOB_DELAY) % 4 + 1]
  for i = 1, PinEntry.LENGTH do
    local x = PinEntry.cellX(i)
    if i == PinEntry.cursor then
      local ch = PinEntry.CHARSET:sub(PinEntry.digits[i] + 1, PinEntry.digits[i] + 1)
      local w = FrlgFont.measure(ch)
      FrlgFont.draw(ch, x + math.floor((PinEntry.CELL_W - w) / 2), PinEntry.DIGIT_Y,
        { colors = FrlgFont.COLOR.NORMAL })
    elseif PinEntry.visited[i] then
      local w = FrlgFont.advance(PinEntry.MASK_GLYPH)
      FrlgFont.drawGlyph(PinEntry.MASK_GLYPH, x + math.floor((PinEntry.CELL_W - w) / 2), PinEntry.DIGIT_Y,
        { colors = FrlgFont.COLOR.NORMAL })
    end
    love.graphics.setColor(1, 1, 1, 1)
    local dy = i == PinEntry.cursor and bob or 0
    love.graphics.draw(underscore, x + 4, PinEntry.UNDERSCORE_Y + dy)
  end
  local cx = PinEntry.cellX(PinEntry.cursor)
  drawCursor(cx)
  ListMenu.drawArrow("up", cx + PinEntry.CELL_W / 2, PinEntry.ARROW_UP_Y, PinEntry.frames)
  ListMenu.drawArrow("down", cx + PinEntry.CELL_W / 2, PinEntry.ARROW_DOWN_Y, PinEntry.frames)
end

return PinEntry
