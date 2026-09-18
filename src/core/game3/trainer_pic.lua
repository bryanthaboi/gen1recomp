-- Trainer front / player back pics (ROM-lazy + cache write-through).

local Versions = require("src.import.gba.versions")
local Extract = require("src.import.gba.extract_island1")

local TrainerPic = {}

TrainerPic._front = {}
TrainerPic._back = {}
TrainerPic._cache = nil
TrainerPic._rom = nil

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

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

local function load_rom_bytes()
  if TrainerPic._rom then return TrainerPic._rom end
  local candidates = {
    "1636 - Pokemon Fire Red (U)(Squirrels).gba",
    "firered.gba",
    "Pokemon - FireRed Version (USA).gba",
  }
  local bases = {
    "",
    (os.getenv("HOME") or "") .. "/src/gen1recomp-gaia/",
  }
  for _, base in ipairs(bases) do
    for _, name in ipairs(candidates) do
      local path = (base ~= "" and (base .. name)) or name
      local f = io.open(path, "rb")
      if f then
        local data = f:read("*a")
        f:close()
        if data and #data > 0 then
          TrainerPic._rom = data
          return data
        end
      end
    end
  end
  if love and love.filesystem and love.filesystem.read then
    for _, name in ipairs(candidates) do
      local data = love.filesystem.read(name)
      if data and #data > 0 then
        TrainerPic._rom = data
        return data
      end
    end
  end
  return nil
end

local function rom_u8(data, i)
  return data:byte(i + 1) or 0
end

local function rom_u32(data, off)
  return rom_u8(data, off)
    + rom_u8(data, off + 1) * 256
    + rom_u8(data, off + 2) * 65536
    + rom_u8(data, off + 3) * 16777216
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

local function decode_pic_rgba(index, picTable, palTable, cacheRel, frames)
  index = tonumber(index)
  frames = math.max(1, tonumber(frames) or 1)
  if not index or index < 0 then return nil end
  local cache = TrainerPic._cache
  if cache and cache.read then
    local d = cache:read(cacheRel)
    if d and #d >= 64 * 64 * frames * 4 then return d end
  end

  local data = load_rom_bytes()
  if not data then return nil end
  local Lz77 = require("src.import.gba.lz77")
  local sheetOff = picTable + index * 8
  local palOff = palTable + index * 8
  local tilePtr = rom_u32(data, sheetOff)
  local palPtr = rom_u32(data, palOff)
  local size = rom_u8(data, sheetOff + 4) + rom_u8(data, sheetOff + 5) * 256
  local tileFile = Versions.gbaToFile(tilePtr)
  local palFile = Versions.gbaToFile(palPtr)
  if not tileFile or not palFile then return nil end
  local function get(i)
    return rom_u8(data, i)
  end
  local tiles
  local okP, palBytes = pcall(Lz77.decompress, get, palFile)
  if not okP or type(palBytes) ~= "table" then
    return nil
  end
  if frames > 1 then
    -- Player back pics: uncompressed 4bpp strip.
    if size < 0x800 then size = frames * 0x800 end
    tiles = {}
    for i = 0, size - 1 do
      tiles[i + 1] = rom_u8(data, tileFile + i)
    end
  else
    local okT
    okT, tiles = pcall(Lz77.decompress, get, tileFile)
    if not okT or type(tiles) ~= "table" then
      return nil
    end
    -- Multi-frame front sheets (size 0x1000): use first 2048 tile bytes only.
    if size >= 0x1000 and #tiles > 2048 then
      local trimmed = {}
      for i = 1, 2048 do trimmed[i] = tiles[i] end
      tiles = trimmed
    end
  end
  local pal = {}
  for c = 0, 15 do
    local lo = palBytes[c * 2 + 1] or 0
    local hi = palBytes[c * 2 + 2] or 0
    pal[c] = lo + hi * 256
  end
  local rgb = {}
  for c = 0, 15 do
    local r, g, b = bgr555_to_rgb8(pal[c] or 0)
    rgb[c] = { r, g, b }
  end
  local w, h = 64, 64 * frames
  local chunks = {}
  local ti = 0
  local tilesH = 8 * frames
  for ty = 0, tilesH - 1 do
    for tx = 0, 7 do
      local tileOff = ti * 32
      for row = 0, 7 do
        for bx = 0, 3 do
          local bi = tileOff + row * 4 + bx + 1
          local byte = tiles[bi] or 0
          local p0 = byte % 16
          local p1 = math.floor(byte / 16) % 16
          local x0 = tx * 8 + bx * 2
          local y0 = ty * 8 + row
          local function put(x, y, idx)
            local i = y * w + x + 1
            if idx == 0 then
              chunks[i] = string.char(0, 0, 0, 0)
            else
              local c = rgb[idx] or rgb[0]
              chunks[i] = string.char(c[1], c[2], c[3], 255)
            end
          end
          put(x0, y0, p0)
          put(x0 + 1, y0, p1)
        end
      end
      ti = ti + 1
    end
  end
  local rgba = table.concat(chunks)
  if cache and cache.write then
    pcall(cache.write, cache, cacheRel, rgba)
  end
  return rgba
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
  local rgba = decode_pic_rgba(
    picId,
    Versions.TRAINER_FRONT_PIC_TABLE or 0x23957C,
    Versions.TRAINER_FRONT_PIC_PAL_TABLE or 0x239A1C,
    rel,
    1)
  local image = image_from_rgba(rgba, 64, 64)
  if not image then return nil end
  local entry = { image = image, w = 64, h = 64 }
  TrainerPic._front[picId] = entry
  return entry
end

--- Player back pic strip (64×320, 5 frames). gender 0=boy, 1=girl.
function TrainerPic.back(gender)
  gender = tonumber(gender) or 0
  if gender ~= 0 and gender ~= 1 then gender = 0 end
  if TrainerPic._back[gender] then return TrainerPic._back[gender] end
  if not TrainerPic._cache then TrainerPic.install(nil) end
  local rel = cache_root() .. "/back_" .. gender .. ".rgba"
  local cache = TrainerPic._cache
  local rgba = cache and cache.read and cache:read(rel)
  if not rgba or #rgba < 64 * 320 * 4 then
    rgba = decode_pic_rgba(
      gender,
      Versions.TRAINER_BACK_PIC_TABLE or 0x239FA4,
      Versions.TRAINER_BACK_PIC_PAL_TABLE or 0x239FD4,
      rel,
      5)
  end
  local image = image_from_rgba(rgba, 64, 320)
  if not image then return nil end
  local entry = { image = image, w = 64, h = 320, frames = 5 }
  TrainerPic._back[gender] = entry
  return entry
end

return TrainerPic
