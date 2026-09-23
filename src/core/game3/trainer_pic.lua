-- Trainer front / player back pics (cache only).

local Extract = require("src.import.gba.extract_island1")

local TrainerPic = {}

TrainerPic._front = {}
TrainerPic._back = {}
TrainerPic._cache = nil

local function cache_root()
  return (Extract.CACHE_ROOT or "data/generated/gba") .. "/trainers"
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
    write = function(_, rel, bytes)
      local ok, CacheFs = pcall(require, "src.import.CacheFs")
      if ok and CacheFs and CacheFs.writeActive then
        return CacheFs.writeActive(rel, bytes)
      end
    end,
  }
end

local function image_from_rgba(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local ok, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not imageData then return nil end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

local function read_pic_rgba(cacheRel, frames)
  local cache = TrainerPic._cache
  if not (cache and cache.read) then return nil end
  local d = cache:read(cacheRel)
  if d and #d >= 64 * 64 * frames * 4 then return d end
  return nil
end

function TrainerPic.install(cache)
  TrainerPic._cache = resolve_cache(cache)
  TrainerPic._front = {}
  TrainerPic._back = {}
end

--- Opponent trainer front pic (64×64). Returns nil if unavailable (no placeholder).
function TrainerPic.front(picId)
  picId = tonumber(picId)
  if not picId or picId < 0 then return nil end
  if TrainerPic._front[picId] then return TrainerPic._front[picId] end
  if not TrainerPic._cache then TrainerPic.install(nil) end
  local rel = cache_root() .. "/front/" .. picId .. ".rgba"
  local rgba = read_pic_rgba(rel, 1)
  local image = image_from_rgba(rgba, 64, 64)
  if not image then return nil end
  local entry = { image = image, w = 64, h = 64 }
  TrainerPic._front[picId] = entry
  return entry
end

--- Player back pic strip (64×320, 5 frames). gender 0=boy, 1=girl.
function TrainerPic.back(gender)
  gender = tonumber(gender) or 0
  if gender < 0 or gender > 5 then gender = 0 end
  if TrainerPic._back[gender] then return TrainerPic._back[gender] end
  if not TrainerPic._cache then TrainerPic.install(nil) end
  local rel = cache_root() .. "/back_" .. gender .. ".rgba"
  local frames = (gender == 0 or gender == 1) and 5 or 4
  local rgba = read_pic_rgba(rel, frames)
  if not rgba then return nil end
  local actualFrames = math.floor(#rgba / (64 * 64 * 4))
  if actualFrames <= 0 then return nil end
  local image = image_from_rgba(rgba, 64, 64 * actualFrames)
  if not image then return nil end
  local entry = { image = image, w = 64, h = 64 * actualFrames, frames = actualFrames }
  TrainerPic._back[gender] = entry
  return entry
end

return TrainerPic
