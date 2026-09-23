-- pokefirered/src/braille_text.c:15

local FrlgFont = require("src.ui.game3.frlg_font")
local TextIR = require("src.core.game3.scripting.text_ir")

local Braille = {}

-- pokefirered/src/braille_text.c:209
Braille.GLYPH_WIDTH = 16
-- pokefirered/src/new_menu_helpers.c:121
Braille.GLYPH_HEIGHT = 16
Braille.LINE_PITCH = 18
-- pokefirered/include/characters.h:335
Braille.NUM_CHARS = 0x40

-- pokefirered/include/characters.h:285
Braille.CODE = {
  [" "] = 0x00,
  A = 0x01, B = 0x05, C = 0x03, D = 0x0B, E = 0x09, F = 0x07, G = 0x0F,
  H = 0x0D, I = 0x06, J = 0x0E, K = 0x11, L = 0x15, M = 0x13, N = 0x1B,
  O = 0x19, P = 0x17, Q = 0x1F, R = 0x1D, S = 0x16, T = 0x1E, U = 0x31,
  V = 0x35, W = 0x2E, X = 0x33, Y = 0x3B, Z = 0x39,
  [","] = 0x04, ["."] = 0x2C, ["?"] = 0x34, ["!"] = 0x1C, [":"] = 0x0C,
  [";"] = 0x14, ["-"] = 0x30, ["/"] = 0x12, ["("] = 0x3C, [")"] = 0x3C,
  ["'"] = 0x10, ["#"] = 0x3A, ['"'] = 0x38,
}

-- pokefirered/include/characters.h:337
Braille.NUMBER = 0x3A
Braille.DIGIT = {
  ["0"] = 0x0E, ["1"] = 0x01, ["2"] = 0x05, ["3"] = 0x03, ["4"] = 0x0B,
  ["5"] = 0x09, ["6"] = 0x07, ["7"] = 0x0F, ["8"] = 0x0D, ["9"] = 0x06,
}

local lower = {}
for ch, code in pairs(Braille.CODE) do
  if ch:match("^%u$") then lower[ch:lower()] = code end
end
for ch, code in pairs(lower) do
  Braille.CODE[ch] = code
end

local RECOVERED = {}
for byte = 0, Braille.NUM_CHARS - 1 do
  local ch = TextIR.CHARMAP[byte]
  if ch and not Braille.CODE[ch] then RECOVERED[ch] = byte end
end

local SHEET_PATHS = {
  "chrome/fonts/braille_fg.rgba",
  "data/generated/gba/chrome/fonts/braille_fg.rgba",
  "chrome/fonts/braille.rgba",
  "data/generated/gba/chrome/fonts/braille.rgba",
  "chrome/fonts/braille_fg.png",
  "data/generated/gba/chrome/fonts/braille_fg.png",
  "chrome/fonts/braille.png",
  "data/generated/gba/chrome/fonts/braille.png",
}

local SHADOW_PATHS = {
  "chrome/fonts/braille_shadow.rgba",
  "data/generated/gba/chrome/fonts/braille_shadow.rgba",
  "chrome/fonts/braille_shadow.png",
  "data/generated/gba/chrome/fonts/braille_shadow.png",
}

local MANIFEST_PATHS = {
  "chrome/fonts/braille.lua",
  "data/generated/gba/chrome/fonts/braille.lua",
}

local SHEET_SIZES = {
  { w = 256, h = 64 },
  { w = 128, h = 128 },
  { w = 256, h = 128 },
}

local WHITE = { 1, 1, 1, 1 }
-- pokefirered/src/field_specials.c:2488
local CURSOR_SEQ = { 0, 1, 2, 3, 2, 1 }

Braille._fg = nil
Braille._sh = nil
Braille._quads = nil
Braille._tried = false
Braille._logged = false
Braille._cursor = nil

local function log(msg)
  if Braille._logged then return end
  Braille._logged = true
  print("[game3/braille] " .. tostring(msg))
end

local function read_bytes(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local okC, cache = pcall(Dataset.cache)
    if okC and cache and cache.read then
      local okR, d = pcall(cache.read, cache, rel)
      if okR and type(d) == "string" and #d > 0 then return d end
    end
  end
  local okF, CacheFs = pcall(require, "src.import.CacheFs")
  if okF and CacheFs and CacheFs.readActive then
    local okR, d = pcall(CacheFs.readActive, rel)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local okR, d = pcall(love.filesystem.read, rel)
    if okR and type(d) == "string" and #d > 0 then return d end
    local alt = "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", ""))
    okR, d = pcall(love.filesystem.read, alt)
    if okR and type(d) == "string" and #d > 0 then return d end
  end
  local candidates = { rel, "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", "")) }
  for _, path in ipairs(candidates) do
    local f = io.open(path, "rb")
    if f then
      local d = f:read("*a")
      f:close()
      if d and #d > 0 then return d end
    end
  end
  return nil
end

local function load_lua(paths)
  for _, path in ipairs(paths) do
    local src = read_bytes(path)
    if src then
      local chunk = (load or loadstring)(src, "@" .. path, "t", {})
      if chunk then
        local ok, t = pcall(chunk)
        if ok and type(t) == "table" then return t end
      end
    end
  end
  return nil
end

local function image_from(data, path, manifest)
  if not (love and love.image and love.graphics) then return nil end
  local sizes = {}
  if type(manifest) == "table" and tonumber(manifest.width) and tonumber(manifest.height) then
    sizes[1] = { w = math.floor(tonumber(manifest.width)), h = math.floor(tonumber(manifest.height)) }
  end
  for _, size in ipairs(SHEET_SIZES) do sizes[#sizes + 1] = size end
  for _, size in ipairs(sizes) do
    if #data == size.w * size.h * 4 then
      local okId, id = pcall(love.image.newImageData, size.w, size.h, "rgba8", data)
      if okId and id then
        local img = love.graphics.newImage(id)
        if img and img.setFilter then img:setFilter("nearest", "nearest") end
        return img
      end
    end
  end
  if love.filesystem and love.filesystem.newFileData then
    local okFd, fd = pcall(love.filesystem.newFileData, data, path)
    if okFd and fd then
      local okId, id = pcall(love.image.newImageData, fd)
      if okId and id then
        local img = love.graphics.newImage(id)
        if img and img.setFilter then img:setFilter("nearest", "nearest") end
        return img
      end
    end
  end
  return nil
end

local function load_sheet(paths, manifest)
  for _, path in ipairs(paths) do
    local data = read_bytes(path)
    if data then
      local img = image_from(data, path, manifest)
      if img then return img, path end
    end
  end
  return nil, nil
end

function Braille.sheetCols(manifest, imageWidth)
  local cols = type(manifest) == "table" and tonumber(manifest.cols)
  if cols and cols >= 1 then return math.floor(cols) end
  return math.max(1, math.floor((tonumber(imageWidth) or Braille.GLYPH_WIDTH) / Braille.GLYPH_WIDTH))
end

-- pokefirered/src/braille_text.c:200
function Braille.glyphCell(code, cols)
  cols = math.max(1, math.floor(tonumber(cols) or 1))
  code = math.floor(tonumber(code) or 0)
  return (code % cols) * Braille.GLYPH_WIDTH, math.floor(code / cols) * Braille.GLYPH_HEIGHT
end

local function ensure()
  if Braille._quads then return true end
  if Braille._tried then return Braille._fg ~= nil end
  Braille._tried = true
  if not (love and love.graphics and love.graphics.newQuad) then return false end
  local manifest = load_lua(MANIFEST_PATHS)
  local fg, path = load_sheet(SHEET_PATHS, manifest)
  if not fg then
    log("no braille glyph sheet in the cache; printing the plain text instead")
    return false
  end
  Braille._fg = fg
  Braille._sh = load_sheet(SHADOW_PATHS, manifest)
  local w, h = fg:getWidth(), fg:getHeight()
  local cols = Braille.sheetCols(manifest, w)
  local quads = {}
  for code = 0, Braille.NUM_CHARS - 1 do
    local gx, gy = Braille.glyphCell(code, cols)
    if gy + Braille.GLYPH_HEIGHT <= h then
      quads[code] = love.graphics.newQuad(gx, gy, Braille.GLYPH_WIDTH, Braille.GLYPH_HEIGHT, w, h)
    end
  end
  Braille._quads = quads
  log("braille glyph sheet from " .. tostring(path))
  return true
end

function Braille.hasSheet()
  return ensure() and Braille._quads ~= nil
end

function Braille.invalidate()
  Braille._fg = nil
  Braille._sh = nil
  Braille._quads = nil
  Braille._tried = false
end

local function chars(text)
  return tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*")
end

-- A Unicode braille cell (U+2800-U+283F, dots 1-6 as bits 0-5) is drawn as that
-- cell: pokefirered/include/characters.h:282 keeps every dot combination in the
-- braille font, numbered dot 1 = 0x01, 4 = 0x02, 2 = 0x04, 5 = 0x08, 3 = 0x10,
-- 6 = 0x20.  A mod can hand over a European cart's own braille this way, cells
-- such as German ä that no Latin character spells included.
local CELL_BIT = { 0x01, 0x04, 0x10, 0x02, 0x08, 0x20 }

local function unicode_cell(ch)
  local b1, b2, b3 = ch:byte(1, 3)
  if #ch ~= 3 or b1 ~= 0xE2 or b2 ~= 0xA0 or not b3 or b3 < 0x80 or b3 > 0xBF then
    return nil
  end
  local dots, code = b3 - 0x80, 0
  for dot = 1, 6 do
    if dots % 2 == 1 then code = code + CELL_BIT[dot] end
    dots = math.floor(dots / 2)
  end
  return code
end
Braille.unicodeCell = unicode_cell

local encodeCache = {}
local encodeCacheN = 0

function Braille.encode(text)
  local key = tostring(text or "")
  local hit = encodeCache[key]
  if hit then return hit end
  local lines = { {} }
  local cur = lines[1]
  local inNumber = false
  for ch in chars(text) do
    if ch == "\n" then
      lines[#lines + 1] = {}
      cur = lines[#lines]
      inNumber = false
    elseif ch ~= "\r" then
      local cell = unicode_cell(ch)
      local digit = not cell and Braille.DIGIT[ch]
      local code = cell or Braille.CODE[ch] or RECOVERED[ch]
      if cell then
        -- a cell spells its own number sign, as the carts' braille does
        inNumber = false
      elseif digit then
        if not inNumber then
          inNumber = true
          cur[#cur + 1] = Braille.NUMBER
        end
        code = digit
      elseif code == 0x00 then
        inNumber = false
      end
      cur[#cur + 1] = code or false
    end
  end
  if encodeCacheN > 64 then
    encodeCache = {}
    encodeCacheN = 0
  end
  encodeCache[key] = lines
  encodeCacheN = encodeCacheN + 1
  return lines
end

-- pokefirered/src/text.c:1020
function Braille.width(text)
  local best = 0
  for _, line in ipairs(Braille.encode(text)) do
    local w = #line * Braille.GLYPH_WIDTH
    if w > best then best = w end
  end
  return best
end

function Braille.countGlyphs(text)
  local n = 0
  for _, line in ipairs(Braille.encode(text)) do
    n = n + #line
  end
  return n
end

-- pokefirered/src/field_specials.c:2478
function Braille.setCursor(px, py)
  Braille._cursor = { x = tonumber(px) or 0, y = tonumber(py) or 0 }
end

function Braille.clearCursor()
  Braille._cursor = nil
end

function Braille.cursor()
  return Braille._cursor
end

-- pokefirered/src/scrcmd.c:1558
function Braille.show(text, opts)
  if type(opts) ~= "table" then opts = {} end
  local body = tostring(text or "")
  Braille._text = body
  Braille._width = tonumber(opts.width) or Braille.width(body)
  Braille.clearCursor()
  local Message = require("src.ui.game3.message")
  Message.showStay(body, { frame = "braille", speed = opts.speed, session = opts.session })
  return true
end

function Braille.isOpen()
  local Message = package.loaded["src.ui.game3.message"]
  return (Message and Message.isOpen() and Message.frameKind() == "braille") or false
end

function Braille.hide()
  local Message = package.loaded["src.ui.game3.message"]
  if Message and Message.isOpen() and Message.frameKind() == "braille" then
    Message.close()
  end
  Braille.clearCursor()
end

-- pokefirered/src/braille_text.c:196
function Braille.drawText(text, x, y, opts)
  opts = opts or {}
  local limit = tonumber(opts.limitChars)
  if not ensure() then
    FrlgFont.draw(tostring(text or ""), x, y, {
      maxWidth = opts.maxWidth or 208,
      limitChars = limit,
      colors = opts.colors or FrlgFont.COLOR.NORMAL,
    })
    return false
  end
  local colors = opts.colors or FrlgFont.COLOR.NORMAL
  local drawn = 0
  for row, line in ipairs(Braille.encode(text)) do
    local penY = y + (row - 1) * Braille.LINE_PITCH
    for col, code in ipairs(line) do
      if limit and drawn >= limit then
        love.graphics.setColor(1, 1, 1, 1)
        return true
      end
      drawn = drawn + 1
      local quad = code and Braille._quads[code]
      if quad then
        local penX = x + (col - 1) * Braille.GLYPH_WIDTH
        if Braille._sh and colors.shadow then
          love.graphics.setColor(colors.shadow)
          love.graphics.draw(Braille._sh, quad, penX, penY)
        end
        love.graphics.setColor(colors.fg or WHITE)
        love.graphics.draw(Braille._fg, quad, penX, penY)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

function Braille.drawCursor()
  local c = Braille._cursor
  if not c then return end
  local Chrome = require("src.ui.game3.chrome")
  local t = love and love.timer and love.timer.getTime and love.timer.getTime() or 0
  Chrome.promptArrow(c.x, c.y, CURSOR_SEQ[1 + (math.floor(t * 8) % #CURSOR_SEQ)] or 0)
end

return Braille
