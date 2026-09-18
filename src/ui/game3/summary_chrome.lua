-- Pokémon Summary Screen Chrome (ROM-baked textures, bars, icons, and layout).
-- Handles Love2D texture creation and quad rendering with fallbacks.

local Display = require("src.core.game3.display")
local Extract = require("src.import.gba.extract_island1")
local SummaryChromeExtract = require("src.import.gba.summary_chrome_extract")

local SummaryChrome = {}

SummaryChrome._cache = nil
SummaryChrome._pages = {}
SummaryChrome._hpBars = {}
SummaryChrome._expBar = nil
SummaryChrome._statusIcons = nil
SummaryChrome._cursorLeft = nil
SummaryChrome._cursorRight = nil
SummaryChrome._shinyStar = nil
SummaryChrome._pokerus = nil
SummaryChrome._menuInfo = nil
SummaryChrome._manifest = nil
SummaryChrome._quads = {}
SummaryChrome._logged = false

local function cache_root()
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.mountExtractRoots then
    Dataset.mountExtractRoots()
  end
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function summary_root()
  return cache_root() .. "/pokemon/summary"
end

local function log(msg)
  if SummaryChrome._logged then return end
  SummaryChrome._logged = true
  print("[game3/summary_chrome] " .. tostring(msg))
end

local function read_bytes(rel)
  local cache = SummaryChrome._cache
  if cache and cache.read then
    local d = cache:read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local d = Dataset.cache():read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local d = love.filesystem.read(rel)
    if type(d) == "string" and #d > 0 then return d end
    local alt = "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", ""))
    d = love.filesystem.read(alt)
    if type(d) == "string" and #d > 0 then return d end
  end
  local candidates = {
    rel,
    "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", "")),
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p, "rb")
    if f then
      local d = f:read("*a")
      f:close()
      if d and #d > 0 then return d end
    end
  end
  return nil
end

local function load_lua(rel)
  local src = read_bytes(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok then return t end
  return nil
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local ok, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not imageData then
    imageData = love.image.newImageData(w, h)
    local i = 1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        imageData:setPixel(x, y,
          (rgba:byte(i) or 0) / 255,
          (rgba:byte(i + 1) or 0) / 255,
          (rgba:byte(i + 2) or 0) / 255,
          (rgba:byte(i + 3) or 0) / 255)
        i = i + 4
      end
    end
  end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

local function sanitize_menu_info_imagedata(id)
  if not id or not id.getPixel or not id.setPixel then return id end
  local ok, w, h = pcall(function() return id:getDimensions() end)
  if not ok or not w or not h then return id end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = id:getPixel(x, y)
      if math.abs(r - 123/255) < 0.02 and math.abs(g - 156/255) < 0.02 and math.abs(b - 131/255) < 0.02 then
        id:setPixel(x, y, 1, 1, 1, 0)
      end
    end
  end
  return id
end

local function load_png(rel)
  local bytes = read_bytes(rel)
  if bytes and love and love.image and love.graphics then
    local ok, img = pcall(function()
      local fd = love.filesystem.newFileData(bytes, "img.png")
      local id = sanitize_menu_info_imagedata(love.image.newImageData(fd))
      local image = love.graphics.newImage(id)
      if image.setFilter then image:setFilter("nearest", "nearest") end
      return image
    end)
    if ok and img then return img end
  end
  if love and love.graphics and love.image and love.image.newImageData then
    local ok, img = pcall(function()
      local id = sanitize_menu_info_imagedata(love.image.newImageData(rel))
      local image = love.graphics.newImage(id)
      if image.setFilter then image:setFilter("nearest", "nearest") end
      return image
    end)
    if ok and img then return img end
  end
  return nil
end

function SummaryChrome.install(cache)
  if not cache or not cache.read then
    local okD, Dataset = pcall(require, "src.core.game3.dataset")
    if okD and Dataset and Dataset.cache then
      cache = Dataset.cache()
    end
  end
  SummaryChrome._cache = cache
  SummaryChrome._pages = {}
  SummaryChrome._hpBars = {}
  SummaryChrome._expBar = nil
  SummaryChrome._statusIcons = nil
  SummaryChrome._cursorLeft = nil
  SummaryChrome._cursorRight = nil
  SummaryChrome._shinyStar = nil
  SummaryChrome._pokerus = nil
  SummaryChrome._menuInfo = nil
  SummaryChrome._manifest = nil
  SummaryChrome._quads = {}
end

function SummaryChrome.manifest()
  if SummaryChrome._manifest then return SummaryChrome._manifest end
  SummaryChrome._manifest = load_lua(summary_root() .. "/manifest.lua")
  return SummaryChrome._manifest
end

function SummaryChrome.pageImage(pageIndex)
  if SummaryChrome._pages[pageIndex] then return SummaryChrome._pages[pageIndex] end
  local filenames = {
    [0] = "page_info.rgba",
    [1] = "page_skills.rgba",
    [2] = "page_moves.rgba",
    [3] = "page_moves_info.rgba",
    [4] = "page_egg.rgba",
  }
  local fn = filenames[pageIndex] or "page_info.rgba"
  local raw = read_bytes(summary_root() .. "/" .. fn)
  if raw then
    local img = rgba_to_image(raw, 240, 160)
    SummaryChrome._pages[pageIndex] = img
    return img
  end
  return nil
end

function SummaryChrome.hpBarImage(color)
  color = color or "green"
  if SummaryChrome._hpBars[color] then return SummaryChrome._hpBars[color] end
  local raw = read_bytes(summary_root() .. "/hp_bar_" .. color .. ".rgba")
  if raw then
    local img = rgba_to_image(raw, 96, 8)
    SummaryChrome._hpBars[color] = img
    return img
  end
  return nil
end

function SummaryChrome.expBarImage()
  if SummaryChrome._expBar then return SummaryChrome._expBar end
  local raw = read_bytes(summary_root() .. "/exp_bar.rgba")
  if raw then
    local img = rgba_to_image(raw, 96, 8)
    SummaryChrome._expBar = img
    return img
  end
  return nil
end

function SummaryChrome.statusIconsImage()
  if SummaryChrome._statusIcons then return SummaryChrome._statusIcons end
  local raw = read_bytes(summary_root() .. "/status_icons.rgba")
  if raw then
    local img = rgba_to_image(raw, 32, 64)
    SummaryChrome._statusIcons = img
    return img
  end
  return nil
end

function SummaryChrome.menuInfoImage()
  if SummaryChrome._menuInfo then return SummaryChrome._menuInfo end
  local raw = read_bytes(summary_root() .. "/menu_info.rgba")
  local img = raw and rgba_to_image(raw, 128, 128)
  if not img then
    img = load_png(summary_root() .. "/menu_info.png")
  end
  if not img then
    img = load_png("src/import/gba/chrome/menus/menu_info.png")
  end
  SummaryChrome._menuInfo = img
  return img
end

function SummaryChrome.cursorImages()
  if SummaryChrome._cursorLeft and SummaryChrome._cursorRight then
    return SummaryChrome._cursorLeft, SummaryChrome._cursorRight
  end
  local rawL = read_bytes(summary_root() .. "/cursor_left.rgba")
  local rawR = read_bytes(summary_root() .. "/cursor_right.rgba")
  if rawL then SummaryChrome._cursorLeft = rgba_to_image(rawL, 64, 64) end
  if rawR then SummaryChrome._cursorRight = rgba_to_image(rawR, 64, 64) end
  return SummaryChrome._cursorLeft, SummaryChrome._cursorRight
end

function SummaryChrome.shinyStarImage()
  if SummaryChrome._shinyStar then return SummaryChrome._shinyStar end
  local raw = read_bytes(summary_root() .. "/shiny_star.rgba")
  if raw then
    local img = rgba_to_image(raw, 8, 16)
    SummaryChrome._shinyStar = img
    return img
  end
  return nil
end

function SummaryChrome.pokerusImage()
  if SummaryChrome._pokerus then return SummaryChrome._pokerus end
  local raw = read_bytes(summary_root() .. "/pokerus.rgba")
  if raw then
    local img = rgba_to_image(raw, 8, 8)
    SummaryChrome._pokerus = img
    return img
  end
  return nil
end

local function get_quad(key, x, y, w, h, sw, sh)
  if not (love and love.graphics and love.graphics.newQuad) then return nil end
  if not SummaryChrome._quads[key] then
    SummaryChrome._quads[key] = love.graphics.newQuad(x, y, w, h, sw, sh)
  end
  return SummaryChrome._quads[key]
end

--- Draw the background texture for a page with horizontal offset for slide animations.
function SummaryChrome.drawPageBg(pageIndex, xOffset)
  xOffset = xOffset or 0
  local img = SummaryChrome.pageImage(pageIndex)
  if img and love and love.graphics then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, xOffset, 0)
    return true
  end
  return false
end

--- Pret UpdateHpBarObjs: 9 sprites at (x + i*8, y).
--- anim 9=HP label, 10=left cap, 0..8=fill (0 empty..8 full), 11=right cap.
--- Fill spans sprites[2..7] (6 tiles); `x` is sprite[0] left edge (pret: 172).
local function bar_fill_anims(cur, max, fillSlots)
  -- Mirror pret: pointsPerTile = (max<<2)/slots; accumulate whole tiles from sprite index 2.
  local anims = {}
  for i = 1, fillSlots do anims[i] = 0 end
  cur = math.max(0, tonumber(cur) or 0)
  max = math.max(1, tonumber(max) or 1)
  if cur >= max then
    for i = 1, fillSlots do anims[i] = 8 end
    return anims
  end
  local pointsPerTile = (max * 4) / fillSlots
  if pointsPerTile <= 0 then return anims end
  local totalPoints = cur * 4
  local whole = 0
  while totalPoints > pointsPerTile do
    totalPoints = totalPoints - pointsPerTile
    whole = whole + 1
  end
  for i = 1, math.min(whole, fillSlots) do
    anims[i] = 8
  end
  if whole < fillSlots then
    local partial = math.floor((totalPoints * fillSlots) / pointsPerTile)
    if partial < 0 then partial = 0 end
    if partial > 7 then partial = 7 end
    anims[whole + 1] = partial
  end
  return anims
end

local function draw_bar_tile(img, quadKey, tileIndex, dx, dy)
  local q = get_quad(quadKey .. tileIndex, tileIndex * 8, 0, 8, 8, 96, 8)
  love.graphics.draw(img, q, dx, dy)
end

function SummaryChrome.drawHpBar(x, y, curHp, maxHp)
  if not (love and love.graphics) then return end
  curHp = math.max(0, tonumber(curHp) or 0)
  maxHp = math.max(1, tonumber(maxHp) or 1)
  local ratio = curHp / maxHp
  local color = "green"
  if ratio <= 0.20 then
    color = "red"
  elseif ratio <= 0.50 then
    color = "yellow"
  end

  local img = SummaryChrome.hpBarImage(color)
  if not img then
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    love.graphics.rectangle("fill", x + 16, y + 2, 48, 4)
    if color == "green" then love.graphics.setColor(0.2, 0.8, 0.2, 1)
    elseif color == "yellow" then love.graphics.setColor(0.9, 0.8, 0.1, 1)
    else love.graphics.setColor(0.9, 0.2, 0.2, 1) end
    love.graphics.rectangle("fill", x + 16, y + 2, math.floor(48 * ratio), 4)
    return
  end

  love.graphics.setColor(1, 1, 1, 1)
  local fills = bar_fill_anims(curHp, maxHp, 6)
  -- sprites[0]=HP, [1]=cap, [2..7]=fill, [8]=end  (pret CreateHpBarObjs)
  draw_bar_tile(img, "hp_t", 9, x + 0 * 8, y)
  draw_bar_tile(img, "hp_t", 10, x + 1 * 8, y)
  for i = 0, 5 do
    draw_bar_tile(img, "hp_t", fills[i + 1] or 0, x + (2 + i) * 8, y)
  end
  draw_bar_tile(img, "hp_t", 11, x + 8 * 8, y)
end

--- Pret UpdateExpBarObjs: 11 sprites at (x + i*8, y).
--- anim 9=EXP label, 10=left cap, 0..8=fill, 11=right cap. Fill = sprites[2..9].
function SummaryChrome.drawExpBar(x, y, progressPercent)
  if not (love and love.graphics) then return end
  progressPercent = math.max(0.0, math.min(1.0, tonumber(progressPercent) or 0.0))
  local img = SummaryChrome.expBarImage()
  if not img then
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    love.graphics.rectangle("fill", x + 16, y + 2, 64, 4)
    love.graphics.setColor(0.2, 0.5, 0.9, 1)
    love.graphics.rectangle("fill", x + 16, y + 2, math.floor(64 * progressPercent), 4)
    return
  end

  love.graphics.setColor(1, 1, 1, 1)
  -- progressPercent is already cur/needed within the level; fake a 100-unit bar.
  local fills = bar_fill_anims(math.floor(progressPercent * 100 + 0.5), 100, 8)
  draw_bar_tile(img, "exp_t", 9, x + 0 * 8, y)
  draw_bar_tile(img, "exp_t", 10, x + 1 * 8, y)
  for i = 0, 7 do
    draw_bar_tile(img, "exp_t", fills[i + 1] or 0, x + (2 + i) * 8, y)
  end
  draw_bar_tile(img, "exp_t", 11, x + 10 * 8, y)
end

--- Draw Status Ailment Icon (32x8 px)
--- 1: PSN, 2: PRZ, 3: SLP, 4: FRZ, 5: BRN, 6: PKRS, 7: FNT
function SummaryChrome.drawStatusIcon(x, y, ailmentCode)
  if not (love and love.graphics) then return end
  ailmentCode = tonumber(ailmentCode) or 0
  if ailmentCode < 1 or ailmentCode > 7 then return end
  local img = SummaryChrome.statusIconsImage()
  if not img then return end
  local frame = ailmentCode - 1
  local q = get_quad("status_" .. frame, 0, frame * 8, 32, 8, 32, 64)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, q, x, y)
end

--- Type badge mapping in menu_info.png (128x128)
local TYPE_RECTS = {
  [0]  = { x = 0,  y = 16, w = 32, h = 12 },  -- NORMAL
  [1]  = { x = 32, y = 48, w = 32, h = 12 },  -- FIGHTING
  [2]  = { x = 0,  y = 48, w = 32, h = 12 },  -- FLYING
  [3]  = { x = 0,  y = 64, w = 32, h = 12 },  -- POISON
  [4]  = { x = 64, y = 32, w = 32, h = 12 },  -- GROUND
  [5]  = { x = 32, y = 32, w = 32, h = 12 },  -- ROCK
  [6]  = { x = 96, y = 48, w = 32, h = 12 },  -- BUG
  [7]  = { x = 64, y = 48, w = 32, h = 12 },  -- GHOST
  [8]  = { x = 64, y = 64, w = 32, h = 12 },  -- STEEL
  [9]  = { x = 32, y = 80, w = 32, h = 12 },  -- MYSTERY
  [10] = { x = 32, y = 16, w = 32, h = 12 },  -- FIRE
  [11] = { x = 64, y = 16, w = 32, h = 12 },  -- WATER
  [12] = { x = 96, y = 16, w = 32, h = 12 },  -- GRASS
  [13] = { x = 0,  y = 32, w = 32, h = 12 },  -- ELECTRIC
  [14] = { x = 32, y = 64, w = 32, h = 12 },  -- PSYCHIC
  [15] = { x = 96, y = 32, w = 32, h = 12 },  -- ICE
  [16] = { x = 0,  y = 80, w = 32, h = 12 },  -- DRAGON
  [17] = { x = 96, y = 64, w = 32, h = 12 },  -- DARK
}

local TYPE_NAMES = {
  NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4,
  ROCK = 5, BUG = 6, GHOST = 7, STEEL = 8, MYSTERY = 9,
  FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14,
  ICE = 15, DRAGON = 16, DARK = 17,
}

--- Draw Type Badge (32x12)
function SummaryChrome.drawTypeBadge(typeId, x, y)
  if not (love and love.graphics) then return end
  if type(typeId) == "string" then
    typeId = TYPE_NAMES[typeId:upper()] or 0
  end
  typeId = tonumber(typeId) or 0
  local rect = TYPE_RECTS[typeId] or TYPE_RECTS[0]
  local img = SummaryChrome.menuInfoImage()
  if not img then
    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.rectangle("fill", x, y, 32, 12)
    return
  end
  local q = get_quad("type_" .. typeId, rect.x, rect.y, rect.w, rect.h, 128, 128)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, q, x, y)
end

--- Draw Move Selection Cursor (Red for selecting, Blue for swap target)
--- 1:1 pret PokeSum_CreateMoveSelectionCursorObjs (two 64x32 sprites at x, x+64)
function SummaryChrome.drawMoveSelectionCursor(x, y, w, h, isBlue)
  if not (love and love.graphics) then return end
  if type(w) == "boolean" then
    isBlue = w
    w, h = 128, 32
  end
  local curL, curR = SummaryChrome.cursorImages()
  if curL and curR then
    -- Frame 0 is Red (selecting: 0..31), Frame 1 is Blue (swapping: 32..63)
    local vOffset = isBlue and 32 or 0
    local qL = get_quad("cur_l_" .. (isBlue and "b" or "r"), 0, vOffset, 64, 32, 64, 64)
    local qR = get_quad("cur_r_" .. (isBlue and "b" or "r"), 0, vOffset, 64, 32, 64, 64)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(curL, qL, x, y)
    love.graphics.draw(curR, qR, x + 64, y)
  else
    -- Fallback outline
    love.graphics.setColor(isBlue and { 0.2, 0.4, 0.9, 1 } or { 0.9, 0.2, 0.2, 1 })
    love.graphics.rectangle("line", x, y, w or 128, h or 32)
  end
end

--- Draw Shiny Star (8x8)
function SummaryChrome.drawShinyStar(x, y)
  if not (love and love.graphics) then return end
  local img = SummaryChrome.shinyStarImage()
  if not img then return end
  local q = get_quad("shiny_star", 0, 0, 8, 8, 8, 16)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, q, x, y)
end

--- Draw Cured Pokérus icon (8x8)
function SummaryChrome.drawPokerus(x, y)
  if not (love and love.graphics) then return end
  local img = SummaryChrome.pokerusImage()
  if not img then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x, y)
end

return SummaryChrome
