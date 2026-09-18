-- Berry Pouch chrome loader and renderer from CacheFS (items/berry_pouch/).

local Extract = require("src.import.gba.extract_island1")
local BerryPouchExtract = require("src.import.gba.berry_pouch_extract")

local BerryPouchChrome = {}

BerryPouchChrome._cache = nil
BerryPouchChrome._bgMale = nil
BerryPouchChrome._bgFemale = nil
BerryPouchChrome._pouch = nil
BerryPouchChrome._manifest = nil
BerryPouchChrome._logged = false

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function bp_root()
  return cache_root() .. "/" .. BerryPouchExtract.CACHE_SUB
end

local function read_bytes(rel)
  local cache = BerryPouchChrome._cache
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

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  local okD, data = pcall(love.image.newImageData, w, h)
  if not okD or not data then return nil end
  local ffiOk, ffi = pcall(require, "ffi")
  if ffiOk and ffi and data.getFFIPointer then
    local ptr = data:getFFIPointer()
    ffi.copy(ptr, rgba, w * h * 4)
  else
    local p = 1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r = rgba:byte(p) / 255
        local g = rgba:byte(p + 1) / 255
        local b = rgba:byte(p + 2) / 255
        local a = rgba:byte(p + 3) / 255
        p = p + 4
        data:setPixel(x, y, r, g, b, a)
      end
    end
  end
  local img = love.graphics.newImage(data)
  if img and img.setFilter then
    img:setFilter("nearest", "nearest")
  end
  return img
end

function BerryPouchChrome.ready()
  if BerryPouchChrome._bgMale then return true end
  local d = read_bytes(bp_root() .. "/bg_male.rgba")
  return d ~= nil and #d > 0
end

function BerryPouchChrome.loadBg(female)
  if female and BerryPouchChrome._bgFemale then return BerryPouchChrome._bgFemale end
  if not female and BerryPouchChrome._bgMale then return BerryPouchChrome._bgMale end
  local filename = female and "/bg_female.rgba" or "/bg_male.rgba"
  local raw = read_bytes(bp_root() .. filename)
  if not raw or #raw < 240 * 160 * 4 then return nil end
  local img = rgba_to_image(raw, 240, 160)
  if female then
    BerryPouchChrome._bgFemale = img
  else
    BerryPouchChrome._bgMale = img
  end
  return img
end

function BerryPouchChrome.loadPouch()
  if BerryPouchChrome._pouch then return BerryPouchChrome._pouch end
  local raw = read_bytes(bp_root() .. "/pouch.rgba")
  if not raw or #raw < 64 * 64 * 4 then return nil end
  local img = rgba_to_image(raw, 64, 64)
  BerryPouchChrome._pouch = img
  return img
end

function BerryPouchChrome.drawBg(x, y, opts)
  opts = opts or {}
  local img = BerryPouchChrome.loadBg(opts.female)
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x or 0, y or 0)
    return true
  end
  return false
end

function BerryPouchChrome.drawPouch(x, y, angle)
  local img = BerryPouchChrome.loadPouch()
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    if angle and math.abs(angle) > 0.001 then
      love.graphics.draw(img, (x or 0) + 32, (y or 0) + 32, angle, 1, 1, 32, 32)
    else
      love.graphics.draw(img, x or 0, y or 0)
    end
    return true
  end
  return false
end

return BerryPouchChrome
