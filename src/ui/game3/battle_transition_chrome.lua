-- FRLG battle transition chrome (ROM-baked under pokemon/battle_transition/).

local Extract = require("src.import.gba.extract_island1")
local BattleTransitionExtract = require("src.import.gba.battle_transition_extract")

local BattleTransitionChrome = {}

BattleTransitionChrome._cache = nil
BattleTransitionChrome._manifest = nil
BattleTransitionChrome._bigPokeball = nil
BattleTransitionChrome._slidingPokeball = nil
BattleTransitionChrome._gridSquare = nil
BattleTransitionChrome._gridQuads = {}
BattleTransitionChrome._gridFrames = {}
BattleTransitionChrome._vsbars = {}
BattleTransitionChrome._banners = {}
BattleTransitionChrome._logged = false

local MUGSHOT_KEYS = { "lorelei", "bruno", "agatha", "lance", "blue" }
local GENDER_KEYS = { "male", "female" }

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function transition_root()
  return cache_root() .. "/" .. BattleTransitionExtract.CACHE_SUB
end

local function log(msg)
  if BattleTransitionChrome._logged then return end
  BattleTransitionChrome._logged = true
  print("[game3/battle_transition_chrome] " .. tostring(msg))
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
  local cache = BattleTransitionChrome._cache
  if cache and cache.read then
    local d = cache:read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local d = Dataset.cache():read(rel)
    if type(d) == "string" and #d > 0 then return d end
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

local function rgba_to_data(rgba, w, h, keyed)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local ok, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not imageData then return nil end
  if keyed then
    local kr, kg, kb = imageData:getPixel(0, 0)
    imageData:mapPixel(function(_, _, r, g, b, a)
      if r == kr and g == kg and b == kb then return r, g, b, 0 end
      return r, g, b, a
    end)
  end
  return imageData
end

local function data_to_image(imageData, wrap)
  if not imageData then return nil end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  if wrap and image.setWrap then pcall(image.setWrap, image, "repeat", "repeat") end
  return image
end

local function rgba_to_image(rgba, w, h, keyed, wrap)
  return data_to_image(rgba_to_data(rgba, w, h, keyed), wrap)
end

function BattleTransitionChrome.install(cache)
  BattleTransitionChrome._cache = resolve_cache(cache)
  BattleTransitionChrome._manifest = nil
  BattleTransitionChrome._bigPokeball = nil
  BattleTransitionChrome._slidingPokeball = nil
  BattleTransitionChrome._gridSquare = nil
  BattleTransitionChrome._gridQuads = {}
  BattleTransitionChrome._gridFrames = {}
  BattleTransitionChrome._vsbars = {}
  BattleTransitionChrome._banners = {}
  BattleTransitionChrome._logged = false

  local root = transition_root()
  BattleTransitionChrome._manifest = load_lua(root .. "/manifest.lua")

  local bp = read_bytes(root .. "/big_pokeball.rgba")
  local sp = read_bytes(root .. "/sliding_pokeball.rgba")
  local gs = read_bytes(root .. "/grid_square.rgba")

  BattleTransitionChrome._bigPokeball = rgba_to_image(bp, 240, 160, true)
  BattleTransitionChrome._slidingPokeball = rgba_to_image(sp, 32, 32)
  local gridData = rgba_to_data(gs, 8, 120, true)
  BattleTransitionChrome._gridSquare = data_to_image(gridData)
  if gridData and love.image.newImageData then
    for frame = 0, 14 do
      local fd = love.image.newImageData(8, 8)
      fd:paste(gridData, 0, 0, 0, frame * 8, 8, 8)
      BattleTransitionChrome._gridFrames[frame] = data_to_image(fd, true)
    end
  end

  if BattleTransitionChrome._gridSquare and love and love.graphics and love.graphics.newQuad then
    for frame = 0, 14 do
      BattleTransitionChrome._gridQuads[frame + 1] = love.graphics.newQuad(
        0, frame * 8, 8, 8, 8, 120
      )
    end
  end

  for _, key in ipairs(MUGSHOT_KEYS) do
    for _, gender in ipairs(GENDER_KEYS) do
      local vsKey = key .. "_" .. gender
      local vsRgba = read_bytes(root .. "/vsbar_" .. vsKey .. ".rgba")
      if vsRgba then
        BattleTransitionChrome._vsbars[vsKey] = rgba_to_image(vsRgba, 256, 160, true, true)
      end
    end
    local bRgba = read_bytes(root .. "/banner_" .. key .. ".rgba")
    if bRgba then
      BattleTransitionChrome._banners[key] = rgba_to_image(bRgba, 120, 8)
    end
  end

  if not BattleTransitionChrome._bigPokeball then
    log("transition chrome missing — re-run --pokemon extract")
  end
end

function BattleTransitionChrome.ensureInstalled()
  if not BattleTransitionChrome._cache then
    BattleTransitionChrome.install()
  end
end

function BattleTransitionChrome.ready()
  BattleTransitionChrome.ensureInstalled()
  return BattleTransitionChrome._bigPokeball ~= nil
end

function BattleTransitionChrome.bigPokeball()
  BattleTransitionChrome.ensureInstalled()
  return BattleTransitionChrome._bigPokeball
end

function BattleTransitionChrome.slidingPokeball()
  BattleTransitionChrome.ensureInstalled()
  return BattleTransitionChrome._slidingPokeball
end

function BattleTransitionChrome.gridSquare()
  BattleTransitionChrome.ensureInstalled()
  return BattleTransitionChrome._gridSquare, BattleTransitionChrome._gridQuads
end

function BattleTransitionChrome.gridFrame(stage)
  BattleTransitionChrome.ensureInstalled()
  return BattleTransitionChrome._gridFrames[stage]
end

function BattleTransitionChrome.vsbar(mugshotKey, genderKey)
  BattleTransitionChrome.ensureInstalled()
  genderKey = (genderKey == "female" or genderKey == 1) and "female" or "male"
  local key = tostring(mugshotKey or "lorelei"):lower() .. "_" .. genderKey
  return BattleTransitionChrome._vsbars[key]
end

function BattleTransitionChrome.banner(mugshotKey)
  BattleTransitionChrome.ensureInstalled()
  local key = tostring(mugshotKey or "lorelei"):lower()
  return BattleTransitionChrome._banners[key]
end

return BattleTransitionChrome
