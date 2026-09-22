-- TM Case chrome loader and renderer from CacheFS (items/tm_case/).

local Extract = require("src.import.gba.extract_island1")
local TmCaseExtract = require("src.import.gba.tm_case_extract")

local TmCaseChrome = {}

TmCaseChrome._cache = nil
TmCaseChrome._bgMale = nil
TmCaseChrome._bgFemale = nil
TmCaseChrome._coverMale = nil
TmCaseChrome._coverFemale = nil
TmCaseChrome._discs = {} -- typeIdx (0..16) -> Image (TM)
TmCaseChrome._discsHm = {} -- typeIdx (0..16) -> Image (HM)
TmCaseChrome._hmIcon = nil
TmCaseChrome._manifest = nil
TmCaseChrome._logged = false

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function tm_root()
  return cache_root() .. "/" .. TmCaseExtract.CACHE_SUB
end

local function read_bytes(rel)
  local cache = TmCaseChrome._cache
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

function TmCaseChrome.ready()
  if TmCaseChrome._ready ~= nil then return TmCaseChrome._ready end
  local d = read_bytes(tm_root() .. "/bg_male.rgba")
  TmCaseChrome._ready = d ~= nil and #d > 0
  return TmCaseChrome._ready
end

function TmCaseChrome.loadBg(female)
  if female and TmCaseChrome._bgFemale then return TmCaseChrome._bgFemale end
  if not female and TmCaseChrome._bgMale then return TmCaseChrome._bgMale end
  local filename = female and "/bg_female.rgba" or "/bg_male.rgba"
  local raw = read_bytes(tm_root() .. filename)
  if not raw or #raw < 240 * 160 * 4 then return nil end
  local img = rgba_to_image(raw, 240, 160)
  if female then
    TmCaseChrome._bgFemale = img
  else
    TmCaseChrome._bgMale = img
  end
  return img
end

function TmCaseChrome.loadCover(female)
  if female and TmCaseChrome._coverFemale then return TmCaseChrome._coverFemale end
  if not female and TmCaseChrome._coverMale then return TmCaseChrome._coverMale end
  local filename = female and "/cover_female.rgba" or "/cover_male.rgba"
  local raw = read_bytes(tm_root() .. filename)
  if not raw or #raw < 240 * 160 * 4 then return nil end
  local img = rgba_to_image(raw, 240, 160)
  if female then
    TmCaseChrome._coverFemale = img
  else
    TmCaseChrome._coverMale = img
  end
  return img
end

function TmCaseChrome.loadDisc(typeIdx, isHm)
  typeIdx = tonumber(typeIdx) or 0
  local tbl = isHm and TmCaseChrome._discsHm or TmCaseChrome._discs
  if tbl[typeIdx] then return tbl[typeIdx] end
  local filename = isHm and string.format("%s/disc_hm_%d.rgba", tm_root(), typeIdx)
    or string.format("%s/disc_%d.rgba", tm_root(), typeIdx)
  local raw = read_bytes(filename)
  if not raw or #raw < 32 * 32 * 4 then
    if isHm then
      -- Fallback to standard TM disc if HM disc not baked yet
      return TmCaseChrome.loadDisc(typeIdx, false)
    end
    return nil
  end
  local img = rgba_to_image(raw, 32, 32)
  tbl[typeIdx] = img
  return img
end

function TmCaseChrome.loadHmIcon()
  if TmCaseChrome._hmIcon then return TmCaseChrome._hmIcon end
  local raw = read_bytes(tm_root() .. "/hm_icon.rgba")
  if not raw or #raw < 16 * 12 * 4 then return nil end
  local img = rgba_to_image(raw, 16, 12)
  TmCaseChrome._hmIcon = img
  return img
end

function TmCaseChrome.drawBg(x, y, opts)
  opts = opts or {}
  local img = TmCaseChrome.loadBg(opts.female)
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x or 0, y or 0)
    return true
  end
  return false
end

function TmCaseChrome.drawCover(x, y, opts)
  opts = opts or {}
  local img = TmCaseChrome.loadCover(opts.female)
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x or 0, y or 0)
    return true
  end
  return false
end

function TmCaseChrome.drawDisc(typeIdx, x, y, isHm)
  local img = TmCaseChrome.loadDisc(typeIdx, isHm)
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y)
    return true
  end
  return false
end

function TmCaseChrome.drawHmIcon(x, y)
  local img = TmCaseChrome.loadHmIcon()
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y)
    return true
  end
  return false
end

return TmCaseChrome
