-- Bag menu chrome + item icons from firered CacheFS (items/bag/).

local Extract = require("src.import.gba.extract_island1")
local BagChromeExtract = require("src.import.gba.bag_chrome_extract")

local BagChrome = {}

BagChrome._cache = nil
BagChrome._bg = nil
BagChrome._bagMale = nil
BagChrome._bagFemale = nil
BagChrome._bagQuads = {}
BagChrome._bagData = {}
BagChrome._rotated = {}
BagChrome._images = {}
BagChrome._icons = {} -- id → Image
BagChrome._manifest = nil
BagChrome._logged = false

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function bag_root()
  return cache_root() .. "/" .. BagChromeExtract.CACHE_SUB
end

local function log(msg)
  if BagChrome._logged then return end
  BagChrome._logged = true
  print("[game3/bag_chrome] " .. tostring(msg))
end

local function read_bytes(rel)
  local cache = BagChrome._cache
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

local function rgba_to_imagedata(rgba, w, h)
  if not (love and love.image) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local ok, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if ok and imageData then return imageData end
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

function BagChrome.install(cache)
  if not cache or not cache.read then
    local okD, Dataset = pcall(require, "src.core.game3.dataset")
    if okD and Dataset and Dataset.cache then
      cache = Dataset.cache()
    end
  end
  BagChrome._cache = cache
  BagChrome._bg = nil
  BagChrome._bagMale = nil
  BagChrome._bagFemale = nil
  BagChrome._bagQuads = {}
  BagChrome._bagData = {}
  BagChrome._rotated = {}
  BagChrome._images = {}
  BagChrome._icons = {}
  BagChrome._manifest = nil
  BagChrome._ready = nil
  BagChrome._logged = false
end

function BagChrome.ready()
  if BagChrome._ready ~= nil then return BagChrome._ready end
  local man = BagChrome._manifest or load_lua(bag_root() .. "/manifest.lua")
  BagChrome._manifest = man
  BagChrome._ready = man ~= nil and read_bytes(bag_root() .. "/bg.rgba") ~= nil
  return BagChrome._ready
end

local function ensure_bg()
  if BagChrome._bg then return BagChrome._bg end
  local man = BagChrome._manifest or load_lua(bag_root() .. "/manifest.lua")
  BagChrome._manifest = man
  local w = (man and man.width) or 240
  local h = (man and man.height) or 160
  local rgba = read_bytes(bag_root() .. "/bg.rgba")
  BagChrome._bg = rgba_to_image(rgba, w, h)
  if BagChrome._bg then log("bg ready") end
  return BagChrome._bg
end

local function ensure_bag_sheet(female)
  if female then
    if BagChrome._bagFemale then return BagChrome._bagFemale end
  else
    if BagChrome._bagMale then return BagChrome._bagMale end
  end
  local man = BagChrome._manifest or load_lua(bag_root() .. "/manifest.lua")
  BagChrome._manifest = man
  local w = (man and man.bagW) or 64
  local h = (man and man.bagH) or 256
  local rel = bag_root() .. (female and "/bag_female.rgba" or "/bag_male.rgba")
  local img = rgba_to_image(read_bytes(rel), w, h)
  if female then BagChrome._bagFemale = img else BagChrome._bagMale = img end
  return img
end

local function bag_quad(frame)
  frame = math.max(0, math.min(3, tonumber(frame) or 0))
  local q = BagChrome._bagQuads[frame]
  if q then return q end
  local img = BagChrome._bagMale or BagChrome._bagFemale
  if not img then return nil end
  local iw, ih = img:getDimensions()
  q = love.graphics.newQuad(0, frame * 64, 64, 64, iw, ih)
  BagChrome._bagQuads[frame] = q
  return q
end

-- src/item_menu_icons.c:52
local POCKET_FRAME = { 2, 3, 1 }

function BagChrome.frameForPocket(pocketIdx)
  return POCKET_FRAME[tonumber(pocketIdx) or 1] or 2
end

local function named_image(name, w, h)
  local img = BagChrome._images[name]
  if img ~= nil then return img or nil end
  img = rgba_to_image(read_bytes(bag_root() .. "/" .. name .. ".rgba"), w, h)
  BagChrome._images[name] = img or false
  return img
end

function BagChrome.drawBg(x, y, opts)
  local img = (opts and opts.female) and named_image("bg_female", 240, 160) or nil
  img = img or ensure_bg()
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x or 0, y or 0)
  return true
end

-- src/item_menu.c:1163, 1332
function BagChrome.drawListFrame(rows, female)
  local suffix = female and "_female" or ""
  local blank = named_image("list_blank" .. suffix, 144, 96) or named_image("list_blank", 144, 96)
  local list = named_image("list" .. suffix, 144, 96) or named_image("list", 144, 96)
  if not (blank and list) then return false end
  rows = math.max(0, math.min(12, tonumber(rows) or 0))
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(blank, 88, 8)
  if rows > 0 then
    local key = "list_rows_" .. rows
    local q = BagChrome._bagQuads[key]
    if not q then
      q = love.graphics.newQuad(0, (12 - rows) * 8, 144, rows * 8, 144, 96)
      BagChrome._bagQuads[key] = q
    end
    love.graphics.draw(list, q, 88, 8 + (12 - rows) * 8)
  end
  return true
end

-- src/item_menu.c:1118
function BagChrome.drawDescSelected()
  local img = named_image("desc_sel", 240, 48)
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, 0, 112)
  return true
end

-- src/menu_indicators.c:259
function BagChrome.drawArrow(dir, x, y)
  local img = named_image("red_arrow", 16, 32)
  if not img then return false end
  local key = "arrow_" .. tostring(dir)
  local q = BagChrome._bagQuads[key]
  if not q then
    local top = (dir == "up" or dir == "down") and 16 or 0
    q = love.graphics.newQuad(0, top, 16, 16, 16, 32)
    BagChrome._bagQuads[key] = q
  end
  local sx = (dir == "right") and -1 or 1
  local sy = (dir == "down") and -1 or 1
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, q, x + (sx < 0 and 16 or 0), y + (sy < 0 and 16 or 0), 0, sx, sy)
  return true
end

local BIOS_SIN = {}
for i = 0, 255 do
  BIOS_SIN[i] = math.floor(math.sin(i * 2 * math.pi / 256) * 16384 + 0.5)
end

local function bag_data(female)
  local key = female and "f" or "m"
  local d = BagChrome._bagData[key]
  if d ~= nil then return d or nil end
  local man = BagChrome._manifest or load_lua(bag_root() .. "/manifest.lua")
  BagChrome._manifest = man
  local w = (man and man.bagW) or 64
  local h = (man and man.bagH) or 256
  d = rgba_to_imagedata(read_bytes(bag_root() .. (female and "/bag_female.rgba" or "/bag_male.rgba")), w, h)
  BagChrome._bagData[key] = d or false
  return d
end

-- src/sprite.c:1292
local function rotated_image(female, frame, rot)
  local key = (female and "f" or "m") .. frame .. ":" .. rot
  local img = BagChrome._rotated[key]
  if img ~= nil then return img or nil end
  local src = bag_data(female)
  if not src then
    BagChrome._rotated[key] = false
    return nil
  end
  local idx = rot % 256
  local sn, cs = BIOS_SIN[idx], BIOS_SIN[(idx + 64) % 256]
  local pa = math.floor(256 * cs / 16384)
  local pb = math.floor(-(256 * sn) / 16384)
  local pc = math.floor(256 * sn / 16384)
  local pd = math.floor(256 * cs / 16384)
  local out = love.image.newImageData(64, 64)
  local base = frame * 64
  for y = 0, 63 do
    local iy = y - 32
    for x = 0, 63 do
      local ix = x - 32
      local tx = math.floor((pa * ix + pb * iy) / 256) + 32
      local ty = math.floor((pc * ix + pd * iy) / 256) + 32
      if tx >= 0 and tx < 64 and ty >= 0 and ty < 64 then
        out:setPixel(x, y, src:getPixel(tx, base + ty))
      else
        out:setPixel(x, y, 0, 0, 0, 0)
      end
    end
  end
  img = love.graphics.newImage(out)
  img:setFilter("nearest", "nearest")
  BagChrome._rotated[key] = img
  return img
end

--- Draw bag sprite. pret field position ≈ (40, 68).
function BagChrome.drawBag(px, py, opts)
  opts = opts or {}
  local female = opts.female == true
  local img = ensure_bag_sheet(female)
  if not img then
    female = not female
    img = ensure_bag_sheet(female)
  end
  if not img then return false end
  local frame = opts.frame
  if frame == nil then frame = BagChrome.frameForPocket(opts.pocketIdx) end
  frame = math.max(0, math.min(3, math.floor(frame)))
  local rot = math.floor(tonumber(opts.rotation) or 0)
  love.graphics.setColor(1, 1, 1, 1)
  if rot % 256 ~= 0 then
    local r = rotated_image(female, frame, rot)
    if r then
      love.graphics.draw(r, px or 8, py or 36)
      return true
    end
  end
  local q = bag_quad(frame)
  if q then
    love.graphics.draw(img, q, px or 8, py or 36)
  else
    love.graphics.draw(img, px or 8, py or 36)
  end
  return true
end

function BagChrome.iconImage(itemId)
  local ItemsData = require("src.core.game3.items_data")
  local id = ItemsData.toNumericId(itemId) or tonumber(itemId)
  if not id then return nil end
  if BagChrome._icons[id] ~= nil then
    return BagChrome._icons[id] or nil
  end
  local rgba = read_bytes(string.format("%s/icons/%d.rgba", bag_root(), id))
  local img = rgba_to_image(rgba, 24, 24)
  BagChrome._icons[id] = img or false
  return img
end

--- Draw 24×24 item icon at pixel coords.
function BagChrome.drawItemIcon(itemId, px, py, scale)
  local img = BagChrome.iconImage(itemId)
  if not img then return false end
  scale = scale or 1
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, px or 0, py or 0, 0, scale, scale)
  return true
end

return BagChrome
