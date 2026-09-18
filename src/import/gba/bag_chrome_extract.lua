-- Bake FRLG bag chrome + item icons into CacheFS (data/generated/gba/items/bag/).
-- BG tilemap, male/female bag sprites, 24×24 item icons from sItemIconTable.

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local BagChromeExtract = {}

BagChromeExtract.CACHE_SUB = "items/bag"
BagChromeExtract.FORMAT_VERSION = 2

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

local function bake_tiles_rgba(gfx, banks, W, H, entryAt)
  local tileCount = math.floor(byte_len(gfx) / 32)
  local chunks = {}
  local tmp = {}
  for ty = 0, math.floor(H / 8) - 1 do
    for tx = 0, math.floor(W / 8) - 1 do
      local entry = entryAt(tx, ty) or 0
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local bank = banks[math.floor(entry / 4096) % 16] or banks[0]
      if tileId >= tileCount then tileId = 0 end
      local tile = {}
      local base = tileId * 32
      for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
      for i = 1, 64 do tmp[i] = 0 end
      decode_tile_4bpp(tile, tmp, 0, 0, 8, hflip, vflip)
      for row = 0, 7 do
        for col = 0, 7 do
          local c = bank and bank[tmp[row * 8 + col + 1] or 0] or 0
          local r, g, b = bgr555_to_rgb8(c)
          chunks[(ty * 8 + row) * W + tx * 8 + col + 1] = string.char(r, g, b, 255)
        end
      end
    end
  end
  return table.concat(chunks)
end

local function map_entry(map, tx, ty)
  local mi = (ty * 32 + tx) * 2 + 1
  return (map[mi] or 0) + (map[mi + 1] or 0) * 256
end

local function bake_bg_rgba(gfx, banks, map, W, H)
  return bake_tiles_rgba(gfx, banks, W, H, function(tx, ty)
    return map_entry(map, tx, ty)
  end)
end

local function female_banks(palBytes, femaleBytes)
  local banks = load_pal_banks(palBytes)
  local over = load_pal_banks(femaleBytes, 1)
  if over[0] then banks[0] = over[0] end
  return banks
end

local function bake_red_arrow(gfx, palBytes)
  local W, H = 16, 32
  local pal = load_pal_banks(palBytes, 1)[0] or {}
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end
  local ti = 0
  for ty = 0, 3 do
    for tx = 0, 1 do
      local tile = {}
      for i = 1, 32 do tile[i] = gfx[ti * 32 + i] or 0 end
      decode_tile_4bpp(tile, pixels, tx * 8, ty * 8, W, false, false)
      ti = ti + 1
    end
  end
  local chunks = {}
  for i = 1, W * H do
    local idx = pixels[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks)
end

--- 64×256 sheet: 4 pocket frames × 64×64 (8×8 tiles each). Color0 transparent.
local function bake_bag_sprite(gfx, palBytes)
  local W, H = 64, 256
  local banks = load_pal_banks(palBytes, 1)
  local pal = banks[0] or {}
  local tileCount = math.floor(byte_len(gfx) / 32)
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end
  local ti = 0
  for frame = 0, 3 do
    for ty = 0, 7 do
      for tx = 0, 7 do
        if ti < tileCount then
          local tile = {}
          local base = ti * 32
          for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
          decode_tile_4bpp(tile, pixels, tx * 8, frame * 64 + ty * 8, W, false, false)
        end
        ti = ti + 1
      end
    end
  end
  local chunks = {}
  for i = 1, W * H do
    local idx = pixels[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks), W, H, 4
end

--- 24×24 item icon (3×3 tiles). Color0 transparent.
local function bake_icon_rgba(gfx, palBytes)
  local W, H = 24, 24
  local banks = load_pal_banks(palBytes, 1)
  local pal = banks[0] or {}
  local tileCount = math.floor(byte_len(gfx) / 32)
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end
  local ti = 0
  for ty = 0, 2 do
    for tx = 0, 2 do
      if ti < tileCount then
        local tile = {}
        local base = ti * 32
        for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
        decode_tile_4bpp(tile, pixels, tx * 8, ty * 8, W, false, false)
      end
      ti = ti + 1
    end
  end
  local chunks = {}
  for i = 1, W * H do
    local idx = pixels[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks)
end

local function gba_to_file(ptr)
  ptr = tonumber(ptr) or 0
  if ptr < 0x08000000 or ptr >= 0x0A000000 then return nil end
  return ptr - 0x08000000
end

function BagChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. BagChromeExtract.CACHE_SUB
  local W = opts.width or 240
  local H = opts.height or 160
  local progress = opts.progress

  local function get(i) return rom:get(i) end
  local gfx = Lz77.decompress(get, Versions.BAG_BG_GFX)
  local pal = Lz77.decompress(get, Versions.BAG_BG_PAL)
  local map = Lz77.decompress(get, Versions.BAG_BG_TILEMAP)
  local femalePal = Lz77.decompress(get, Versions.BAG_BG_PAL_FEMALE)
  local maleBanks = load_pal_banks(pal)
  local femaleBanks = female_banks(pal, femalePal)
  cache:write(root .. "/bg.rgba", bake_bg_rgba(gfx, maleBanks, map, W, H))
  cache:write(root .. "/bg_female.rgba", bake_bg_rgba(gfx, femaleBanks, map, W, H))

  local LW, LH = Versions.BAG_LIST_TILES_W, Versions.BAG_LIST_TILES_H
  local listMap = rom:readBytes(Versions.BAG_LIST_TILEMAP, LW * LH * 2)
  local function list_entry(tx, ty)
    local i = (ty * LW + tx) * 2 + 1
    return (listMap[i] or 0) + (listMap[i + 1] or 0) * 256
  end
  local function blank_entry() return Versions.BAG_LIST_BLANK_TILE end
  cache:write(root .. "/list.rgba", bake_tiles_rgba(gfx, maleBanks, LW * 8, LH * 8, list_entry))
  cache:write(root .. "/list_female.rgba", bake_tiles_rgba(gfx, femaleBanks, LW * 8, LH * 8, list_entry))
  cache:write(root .. "/list_blank.rgba", bake_tiles_rgba(gfx, maleBanks, LW * 8, LH * 8, blank_entry))
  cache:write(root .. "/list_blank_female.rgba", bake_tiles_rgba(gfx, femaleBanks, LW * 8, LH * 8, blank_entry))
  -- src/item_menu.c:1118
  cache:write(root .. "/desc_sel.rgba", bake_tiles_rgba(gfx, maleBanks, W, 48, function(tx, ty)
    return map_entry(map, tx, ty + 14) % 4096 + 2 * 4096
  end))

  local arrowGfx = Lz77.decompress(get, Versions.RED_ARROW_OTHER_GFX)
  local arrowPal = rom:readBytes(Versions.RED_ARROW_PAL, 32)
  cache:write(root .. "/red_arrow.rgba", bake_red_arrow(arrowGfx, arrowPal))

  local maleGfx = Lz77.decompress(get, Versions.BAG_MALE_GFX)
  local femaleGfx = Lz77.decompress(get, Versions.BAG_FEMALE_GFX)
  local sprPal = Lz77.decompress(get, Versions.BAG_SPRITE_PAL)
  local maleRgba, bw, bh, frames = bake_bag_sprite(maleGfx, sprPal)
  local femaleRgba = bake_bag_sprite(femaleGfx, sprPal)
  cache:write(root .. "/bag_male.rgba", maleRgba)
  cache:write(root .. "/bag_female.rgba", femaleRgba)

  local itemCount = Versions.ITEMS_COUNT or 375
  local tableOff = Versions.ITEM_ICON_TABLE
  local iconDir = root .. "/icons"
  local baked, failed = 0, 0
  local uniqGfx = {}

  for id = 0, itemCount do
    if progress and id % 50 == 0 then
      progress("icons", id, itemCount + 1)
    end
    local entryOff = tableOff + id * 8
    local gfxPtr = rom:u32(entryOff)
    local palPtr = rom:u32(entryOff + 4)
    local gfxOff = gba_to_file(gfxPtr)
    local palOff = gba_to_file(palPtr)
    if gfxOff and palOff then
      local ok, err = pcall(function()
        local key = string.format("%08x:%08x", gfxPtr, palPtr)
        local rgba = uniqGfx[key]
        if not rgba then
          local igfx = Lz77.decompress(get, gfxOff)
          local ipal = Lz77.decompress(get, palOff)
          rgba = bake_icon_rgba(igfx, ipal)
          uniqGfx[key] = rgba
        end
        cache:write(string.format("%s/%d.rgba", iconDir, id), rgba)
        baked = baked + 1
      end)
      if not ok then
        failed = failed + 1
        if failed <= 3 then
          print("[bag_chrome] icon " .. id .. " fail: " .. tostring(err))
        end
      end
    else
      failed = failed + 1
    end
  end
  if progress then progress("icons", itemCount + 1, itemCount + 1) end

  local manifest = string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
  bagW = %d,
  bagH = %d,
  bagFrames = %d,
  listW = %d,
  listH = %d,
  iconW = 24,
  iconH = 24,
  itemCount = %d,
  iconsBaked = %d,
  iconsFailed = %d,
}
]],
    BagChromeExtract.FORMAT_VERSION, W, H, bw, bh, frames or 4,
    LW * 8, LH * 8, itemCount, baked, failed)
  cache:write(root .. "/manifest.lua", manifest)

  print(string.format("[bag_chrome] bg + bag sprites + %d icons (%d fail) → %s",
    baked, failed, root))
  return {
    root = root,
    width = W,
    height = H,
    iconsBaked = baked,
    iconsFailed = failed,
  }
end

function BagChromeExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. BagChromeExtract.CACHE_SUB
  local need = root .. "/bg.rgba"
  if cache and cache.exists and cache:exists(need) then
    return cache:exists(root .. "/icons/4.rgba")
  end
  return false
end

return BagChromeExtract
