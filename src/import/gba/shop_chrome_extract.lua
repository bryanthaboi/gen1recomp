-- Bake FRLG Poké Mart shop/buy menu chrome into CacheFS (data/generated/gba/items/shop/).
-- Source: pret graphics/shop_menu/ (shop_menu.4bpp.lz, shop_tilemap.bin.lz, shop_tm_hm_tilemap.bin.lz, shop_menu.gbapal.lz).

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local ShopChromeExtract = {}

ShopChromeExtract.CACHE_SUB = "items/shop"
ShopChromeExtract.FORMAT_VERSION = 1

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
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

local function byte_len(buf)
  if type(buf) ~= "table" then return 0 end
  return buf._len or #buf
end

local function decode_tile_4bpp(tileBytes, out, baseX, baseY, stride, hflip, vflip)
  for row = 0, 7 do
    local srcRow = vflip and (7 - row) or row
    for bx = 0, 3 do
      local byte = tileBytes[srcRow * 4 + bx + 1] or 0
      local p0 = byte % 16
      local p1 = math.floor(byte / 16) % 16
      local x0 = bx * 2
      local x1 = x0 + 1
      if hflip then
        x0, x1 = 7 - x0, 7 - x1
      end
      out[(baseY + row) * stride + (baseX + x0) + 1] = p0
      out[(baseY + row) * stride + (baseX + x1) + 1] = p1
    end
  end
end

local function load_pal_banks(bytes, count)
  local banks = {}
  local n = count or math.floor(byte_len(bytes) / 32)
  for b = 0, n - 1 do
    local colors = {}
    local off = b * 32
    for c = 0, 15 do
      local i = off + c * 2 + 1
      colors[c] = (bytes[i] or 0) + (bytes[i + 1] or 0) * 256
    end
    banks[b] = colors
  end
  return banks
end

local function bake_bg_rgba(gfx, palBytes, map, W, H)
  local tileCount = math.floor(byte_len(gfx) / 32)
  local banks = load_pal_banks(palBytes)
  local mapW = 32
  local indices, pals = {}, {}
  for i = 1, W * H do indices[i] = 0; pals[i] = 0 end
  local tilesH = math.min(32, math.floor(H / 8))
  local tilesW = math.min(32, math.floor(W / 8))
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local mi = (ty * mapW + tx) * 2 + 1
      local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local palNum = math.floor(entry / 4096) % 16
      if tileId >= tileCount then tileId = 0 end
      local tile = {}
      local base = tileId * 32
      for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
      local tmp = {}
      for i = 1, 64 do tmp[i] = 0 end
      decode_tile_4bpp(tile, tmp, 0, 0, 8, hflip, vflip)
      for row = 0, 7 do
        for col = 0, 7 do
          local px, py = tx * 8 + col, ty * 8 + row
          if px < W and py < H then
            local di = py * W + px + 1
            indices[di] = tmp[row * 8 + col + 1] or 0
            pals[di] = palNum
          end
        end
      end
    end
  end
  local chunks = {}
  for i = 1, W * H do
    local idx = indices[i] or 0
    local bank = banks[pals[i] or 0] or banks[0]
    local c = bank and bank[idx] or 0
    local r, g, b = bgr555_to_rgb8(c)
    local a = (idx == 0) and 0 or 255
    chunks[i] = string.char(r, g, b, a)
  end
  return table.concat(chunks)
end

function ShopChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. ShopChromeExtract.CACHE_SUB
  local W = opts.width or 240
  local H = opts.height or 160

  local function get(i) return rom:get(i) end
  local gfx = Lz77.decompress(get, Versions.SHOP_BG_GFX)
  local pal = Lz77.decompress(get, Versions.SHOP_BG_PAL)
  local map = Lz77.decompress(get, Versions.SHOP_BG_TILEMAP)
  local tmMap = Lz77.decompress(get, Versions.SHOP_BG_TM_TILEMAP)

  cache:write(root .. "/bg.rgba", bake_bg_rgba(gfx, pal, map, W, H))
  cache:write(root .. "/bg_tm.rgba", bake_bg_rgba(gfx, pal, tmMap, W, H))

  local manifest = string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
  bg = "bg.rgba",
  bgTm = "bg_tm.rgba",
}
]], ShopChromeExtract.FORMAT_VERSION, W, H)
  cache:write(root .. "/manifest.lua", manifest)

  print(string.format("[shop_chrome] bg + bg_tm baked → %s", root))
  return {
    root = root,
    width = W,
    height = H,
  }
end

function ShopChromeExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. ShopChromeExtract.CACHE_SUB
  local function valid_file(rel, minSize)
    minSize = minSize or 1
    if cache then
      if cache.read then
        local data = cache:read(rel)
        return (data and #data >= minSize) or false
      elseif cache.exists then
        return cache:exists(rel) or false
      end
      return false
    end
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.readActive then
      local data = CacheFs.readActive(rel)
      if data and #data >= minSize then return true end
    end
    if love and love.filesystem and love.filesystem.read then
      local ok, data = pcall(love.filesystem.read, rel)
      if ok and data and #data >= minSize then return true end
    end
    local f = io.open(rel, "rb")
    if f then
      local data = f:read(minSize)
      f:close()
      if data and #data >= minSize then return true end
    end
    return false
  end

  return valid_file(root .. "/bg.rgba", 240 * 160 * 4)
end

return ShopChromeExtract
