-- FRLG Poké Mart shop chrome loader (items/shop/bg.rgba).

local Extract = require("src.import.gba.extract_island1")
local ShopChromeExtract = require("src.import.gba.shop_chrome_extract")

local ShopChrome = {}

ShopChrome._cache = nil
ShopChrome._manifest = nil
ShopChrome._bg = nil
ShopChrome._bgTm = nil
ShopChrome._logged = false

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function shop_root()
  return cache_root() .. "/" .. ShopChromeExtract.CACHE_SUB
end

local function log(msg)
  if ShopChrome._logged then return end
  ShopChrome._logged = true
  print("[game3/shop_chrome] " .. tostring(msg))
end

local function resolve_cache(cache)
  if cache and cache.read then return cache end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    return Dataset.cache()
  end
  return {
    read = function(_, rel)
      local ok, CacheFs = pcall(require, "src.import.CacheFs")
      if ok and CacheFs and CacheFs.readActive then
        return CacheFs.readActive(rel)
      end
      return nil
    end,
  }
end

local function read_bytes(rel)
  local cache = ShopChrome._cache
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
  if not ok or not imageData then return nil end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

function ShopChrome.install(cache)
  ShopChrome._cache = resolve_cache(cache)
  ShopChrome._manifest = nil
  ShopChrome._bg = nil
  ShopChrome._bgTm = nil
  ShopChrome._logged = false

  local root = shop_root()
  ShopChrome._manifest = load_lua(root .. "/manifest.lua")
  local bgData = read_bytes(root .. "/bg.rgba")
  local bgTmData = read_bytes(root .. "/bg_tm.rgba")

  ShopChrome._bg = rgba_to_image(bgData, 240, 160)
  ShopChrome._bgTm = rgba_to_image(bgTmData, 240, 160)

  if not ShopChrome._bg then
    log("shop chrome missing — re-run extract")
  end
end

function ShopChrome.ensureInstalled()
  if not ShopChrome._cache then
    ShopChrome.install()
  end
end

function ShopChrome.ready()
  ShopChrome.ensureInstalled()
  return ShopChrome._bg ~= nil
end

function ShopChrome.bg(isTm)
  ShopChrome.ensureInstalled()
  if isTm and ShopChrome._bgTm then
    return ShopChrome._bgTm
  end
  return ShopChrome._bg
end

function ShopChrome.drawBg(x, y, isTm)
  local img = ShopChrome.bg(isTm)
  if img and love and love.graphics then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x or 0, y or 0)
    return true
  end
  return false
end

return ShopChrome
