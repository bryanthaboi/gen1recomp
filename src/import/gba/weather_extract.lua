-- Weather graphics and palette extraction (Fog, Rain, default weather palette)
-- pokefirered/src/field_weather.c

local Versions = require("src.import.gba.versions")

local WeatherExtract = {}

WeatherExtract.CACHE_SUB = "weather"
WeatherExtract.FORMAT_VERSION = 1

WeatherExtract.BLOBS = {
  { key = "default_pal", rel = "default.gbapal", offset = 0x3C2CE0, size = 32 },
  { key = "fog_h_gfx", rel = "fog_horizontal.4bpp", offset = 0x3C3540, size = 2048 },
  { key = "rain_gfx", rel = "rain.4bpp", offset = 0x3C55E0, size = 1536 },
}

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

local function bytes_to_array(v)
  if type(v) == "table" then return v end
  local out = {}
  if type(v) == "string" then
    for i = 1, #v do out[i] = v:byte(i) end
  end
  return out
end

local function load_pal(bytes, count)
  bytes = bytes_to_array(bytes)
  local pal = {}
  for i = 0, count - 1 do
    pal[i] = (bytes[i * 2 + 1] or 0) + (bytes[i * 2 + 2] or 0) * 256
  end
  return pal
end

local function decode_tile_4bpp(gfx, base, out)
  for row = 0, 7 do
    for col = 0, 7 do
      local b = gfx[base + row * 4 + math.floor(col / 2) + 1] or 0
      local idx
      if col % 2 == 0 then idx = b % 16 else idx = math.floor(b / 16) end
      out[row * 8 + col + 1] = idx
    end
  end
end

function WeatherExtract.bakeSheet(gfxBytes, palBytes, cols)
  local gfx = bytes_to_array(gfxBytes)
  local pal = load_pal(palBytes, 16)
  local tileCount = math.floor(#gfx / 32)
  cols = math.max(1, cols or 8)
  local rows = math.ceil(tileCount / cols)
  local W, H = cols * 8, rows * 8
  local chunks = {}
  for i = 1, W * H do chunks[i] = "\0\0\0\0" end
  local tmp = {}
  for t = 0, tileCount - 1 do
    decode_tile_4bpp(gfx, t * 32, tmp)
    local ox, oy = (t % cols) * 8, math.floor(t / cols) * 8
    for row = 0, 7 do
      for col = 0, 7 do
        local idx = tmp[row * 8 + col + 1] or 0
        if idx ~= 0 then
          local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
          chunks[(oy + row) * W + ox + col + 1] = string.char(r, g, b, 255)
        end
      end
    end
  end
  return table.concat(chunks), W, H, tileCount
end

function WeatherExtract.readBlobs(rom, cfg)
  cfg = cfg or {}
  local out = {}
  for _, blob in ipairs(WeatherExtract.BLOBS) do
    local off = cfg[blob.key] or Versions.address(blob.offset)
    local bytes = rom:readBytes(off, blob.size)
    local chars = {}
    for i = 1, blob.size do chars[i] = string.char(bytes[i] or 0) end
    out[blob.key] = table.concat(chars)
  end
  return out
end

local function write_cache(cache, rel, data)
  if type(cache) ~= "table" or type(cache.write) ~= "function" then return end
  local ok, res, err = pcall(function() return cache:write(rel, data) end)
  if not ok or res == nil then res, err = cache.write(rel, data) end
  return res
end

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then return Extract.CACHE_ROOT end
  return "data/generated/gba"
end

function WeatherExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. WeatherExtract.CACHE_SUB
  if not (cache and cache.read) then return false end
  local fog = cache:read(root .. "/fog_horizontal.rgba")
  return type(fog) == "string" and #fog == 64 * 64 * 4
end

function WeatherExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. WeatherExtract.CACHE_SUB
  local cfg = opts.offsets or {}
  local blobs = WeatherExtract.readBlobs(rom, cfg)

  for _, blob in ipairs(WeatherExtract.BLOBS) do
    write_cache(cache, root .. "/" .. blob.rel, blobs[blob.key])
  end

  local fogRgba, fogW, fogH = WeatherExtract.bakeSheet(blobs.fog_h_gfx, blobs.default_pal, 8)
  write_cache(cache, root .. "/fog_horizontal.rgba", fogRgba)

  local rainRgba, rainW, rainH = WeatherExtract.bakeSheet(blobs.rain_gfx, blobs.default_pal, 2)
  write_cache(cache, root .. "/rain.rgba", rainRgba)

  write_cache(cache, root .. "/manifest.lua", string.format([[
return {
  format = %d,
  fog_h = { file = "fog_horizontal.rgba", w = %d, h = %d },
  rain = { file = "rain.rgba", w = %d, h = %d },
}
]], WeatherExtract.FORMAT_VERSION, fogW, fogH, rainW, rainH))

  return { format = WeatherExtract.FORMAT_VERSION }
end

return WeatherExtract
