-- src/seagallop.c:41

local SeagallopExtract = {}

SeagallopExtract.CACHE_SUB = "seagallop"
SeagallopExtract.FORMAT_VERSION = 1

-- src/seagallop.c:41
SeagallopExtract.BLOBS = {
  { key = "water_gfx", rel = "water.4bpp", offset = 0x468C98, size = 1312 },
  { key = "water_pal", rel = "water.gbapal", offset = 0x4691B8, size = 32 },
  { key = "wb_tilemap", rel = "wb_tilemap.bin", offset = 0x4691D8, size = 2048 },
  { key = "eb_tilemap", rel = "eb_tilemap.bin", offset = 0x4699D8, size = 2048 },
  { key = "ferry_gfx", rel = "ferry.4bpp", offset = 0x46A1D8, size = 1280 },
  { key = "ferry_wake_pal", rel = "ferry_wake.gbapal", offset = 0x46A6D8, size = 32 },
  { key = "wake_gfx", rel = "wake.4bpp", offset = 0x46A6F8, size = 2048 },
}

-- src/seagallop.c:42
SeagallopExtract.SHEETS = {
  { key = "water", gfx = "water_gfx", pal = "water_pal", cols = 8, rel = "water.rgba" },
  { key = "ferry", gfx = "ferry_gfx", pal = "ferry_wake_pal", cols = 8, rel = "ferry.rgba" },
  { key = "wake", gfx = "wake_gfx", pal = "ferry_wake_pal", cols = 4, rel = "wake.rgba" },
}

SeagallopExtract.MAP_W = 32
SeagallopExtract.MAP_H = 32

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

local function decode_tile_4bpp(gfx, base, out, hflip, vflip)
  for row = 0, 7 do
    for col = 0, 7 do
      local b = gfx[base + row * 4 + math.floor(col / 2) + 1] or 0
      local idx
      if col % 2 == 0 then idx = b % 16 else idx = math.floor(b / 16) end
      local sx = hflip and (7 - col) or col
      local sy = vflip and (7 - row) or row
      out[sy * 8 + sx + 1] = idx
    end
  end
end

function SeagallopExtract.bakeSheet(gfxBytes, palBytes, cols)
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
    decode_tile_4bpp(gfx, t * 32, tmp, false, false)
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

function SeagallopExtract.bakeTilemap(gfxBytes, palBytes, mapBytes, mapW, mapH)
  local gfx = bytes_to_array(gfxBytes)
  local map = bytes_to_array(mapBytes)
  local pal = load_pal(palBytes, 16)
  local tileCount = math.floor(#gfx / 32)
  local W, H = mapW * 8, mapH * 8
  local chunks = {}
  for i = 1, W * H do chunks[i] = "\0\0\0\0" end
  local tmp = {}
  for ty = 0, mapH - 1 do
    for tx = 0, mapW - 1 do
      local mi = (ty * mapW + tx) * 2 + 1
      local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      if tileId >= tileCount then tileId = 0 end
      decode_tile_4bpp(gfx, tileId * 32, tmp, hflip, vflip)
      for row = 0, 7 do
        for col = 0, 7 do
          local idx = tmp[row * 8 + col + 1] or 0
          local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
          chunks[(ty * 8 + row) * W + tx * 8 + col + 1] = string.char(r, g, b, 255)
        end
      end
    end
  end
  return table.concat(chunks), W, H
end

function SeagallopExtract.readBlobs(rom, cfg)
  cfg = cfg or {}
  local out = {}
  for _, blob in ipairs(SeagallopExtract.BLOBS) do
    local off = cfg[blob.key] or blob.offset
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
  if not ok or res == nil then
    res, err = cache.write(rel, data)
  end
  if res == false then
    error("seagallop_extract: could not write " .. rel .. ": " .. tostring(err))
  end
  return res
end

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then return Extract.CACHE_ROOT end
  return "data/generated/gba"
end

function SeagallopExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. SeagallopExtract.CACHE_SUB
  if not (cache and cache.read) then return false end
  local manifest = cache:read(root .. "/manifest.lua")
  if type(manifest) ~= "string" then return false end
  if tonumber(manifest:match("format%s*=%s*(%d+)")) ~= SeagallopExtract.FORMAT_VERSION then
    return false
  end
  for _, blob in ipairs(SeagallopExtract.BLOBS) do
    local data = cache:read(root .. "/" .. blob.rel)
    if type(data) ~= "string" or #data < blob.size then return false end
  end
  local wb = cache:read(root .. "/wb.rgba")
  return type(wb) == "string"
    and #wb == SeagallopExtract.MAP_W * 8 * SeagallopExtract.MAP_H * 8 * 4
end

function SeagallopExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. SeagallopExtract.CACHE_SUB
  local cfg = opts.offsets or {}
  local blobs = SeagallopExtract.readBlobs(rom, cfg)

  for _, blob in ipairs(SeagallopExtract.BLOBS) do
    write_cache(cache, root .. "/" .. blob.rel, blobs[blob.key])
  end

  local sheetMeta = {}
  for _, sheet in ipairs(SeagallopExtract.SHEETS) do
    local rgba, w, h, tiles =
      SeagallopExtract.bakeSheet(blobs[sheet.gfx], blobs[sheet.pal], sheet.cols)
    write_cache(cache, root .. "/" .. sheet.rel, rgba)
    sheetMeta[#sheetMeta + 1] = string.format(
      "    %s = { file = %q, w = %d, h = %d, tiles = %d },",
      sheet.key, sheet.rel, w, h, tiles)
  end

  local mapW, mapH = SeagallopExtract.MAP_W, SeagallopExtract.MAP_H
  local bgMeta = {}
  for _, bg in ipairs({ { "wb", "wb_tilemap" }, { "eb", "eb_tilemap" } }) do
    local rgba, w, h = SeagallopExtract.bakeTilemap(
      blobs.water_gfx, blobs.water_pal, blobs[bg[2]], mapW, mapH)
    write_cache(cache, root .. "/" .. bg[1] .. ".rgba", rgba)
    bgMeta[#bgMeta + 1] = string.format(
      "    %s = { file = %q, w = %d, h = %d },", bg[1], bg[1] .. ".rgba", w, h)
  end

  write_cache(cache, root .. "/manifest.lua", string.format([[
return {
  format = %d,
  sheets = {
%s
  },
  backgrounds = {
%s
  },
}
]], SeagallopExtract.FORMAT_VERSION,
    table.concat(sheetMeta, "\n"), table.concat(bgMeta, "\n")))

  return { format = SeagallopExtract.FORMAT_VERSION, blobs = #SeagallopExtract.BLOBS }
end

return SeagallopExtract
