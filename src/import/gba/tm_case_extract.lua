-- Bake FRLG TM Case chrome from ROM into CacheFS (data/generated/gba/items/tm_case/).
-- Source: pret graphics/tm_case/ (tm_case.4bpp.lz, menu.bin.lz, tm_case.bin.lz, menu_male.gbapal.lz, menu_female.gbapal.lz, disc.4bpp.lz, disc_types_1.gbapal.lz, disc_types_2.gbapal.lz, hm.4bpp).

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local TmCaseExtract = {}

TmCaseExtract.CACHE_SUB = "items/tm_case"
TmCaseExtract.FORMAT_VERSION = 1

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

--- Render BG2 base background (menu tilemap).
local function bake_tm_case_bg_rgba(gfx, palBytes, mapMenu, W, H)
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
      local entry = (mapMenu[mi] or 0) + (mapMenu[mi + 1] or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local palNum = math.floor(entry / 4096) % 16
      if tileId < tileCount then
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
  end

  local chunks = {}
  for i = 1, W * H do
    local bank = banks[pals[i]] or banks[0] or {}
    local col = bank[indices[i]] or 0
    local r, g, b = bgr555_to_rgb8(col)
    chunks[i] = string.char(r, g, b, 255)
  end
  return table.concat(chunks)
end

--- Render BG1 pocket cover overlay (foreground layer with alpha transparency).
local function bake_tm_case_cover_rgba(gfx, palBytes, mapBg, W, H)
  local tileCount = math.floor(byte_len(gfx) / 32)
  local banks = load_pal_banks(palBytes)
  local mapW = 32
  local indices, pals, hasTile = {}, {}, {}
  for i = 1, W * H do indices[i] = 0; pals[i] = 0; hasTile[i] = false end

  local tilesH = math.min(32, math.floor(H / 8))
  local tilesW = math.min(32, math.floor(W / 8))
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local mi = (ty * mapW + tx) * 2 + 1
      local entry = (mapBg[mi] or 0) + (mapBg[mi + 1] or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local palNum = math.floor(entry / 4096) % 16
      if tileId > 0 and tileId < tileCount then
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
              local idx = tmp[row * 8 + col + 1] or 0
              if idx ~= 0 then
                indices[di] = idx
                pals[di] = palNum
                hasTile[di] = true
              end
            end
          end
        end
      end
    end
  end

  local chunks = {}
  for i = 1, W * H do
    if not hasTile[i] then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local bank = banks[pals[i]] or banks[0] or {}
      local col = bank[indices[i]] or 0
      local r, g, b = bgr555_to_rgb8(col)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks)
end

--- Render 32x32 disc sprite with a given type palette (TM or HM).
local function bake_disc_rgba(discGfx, palBank, isHm)
  local W, H = 32, 32
  local tileCount = math.floor(byte_len(discGfx) / 32)
  local tileOffset = isHm and 16 or 0
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end
  local ti = 0
  for ty = 0, 3 do
    for tx = 0, 3 do
      local tileIndex = tileOffset + ti
      if tileIndex < tileCount then
        local tile = {}
        local base = tileIndex * 32
        for i = 1, 32 do tile[i] = discGfx[base + i] or 0 end
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
      local r, g, b = bgr555_to_rgb8(palBank[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks)
end

--- Render 16x12 raw HM icon (2x2 8x8 tiles cropped).
local function bake_hm_icon_rgba(hmGfx, palBank)
  local W, H = 16, 12
  local pixels = {}
  for i = 1, 16 * 16 do pixels[i] = 0 end
  local ti = 0
  for ty = 0, 1 do
    for tx = 0, 1 do
      local tile = {}
      local base = ti * 32
      for i = 1, 32 do tile[i] = hmGfx[base + i] or 0 end
      decode_tile_4bpp(tile, pixels, tx * 8, ty * 8, 16, false, false)
      ti = ti + 1
    end
  end

  local chunks = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local idx = pixels[y * 16 + x + 1] or 0
      if idx == 0 then
        chunks[#chunks + 1] = string.char(0, 0, 0, 0)
      else
        local r, g, b = bgr555_to_rgb8(palBank[idx] or 0)
        chunks[#chunks + 1] = string.char(r, g, b, 255)
      end
    end
  end
  return table.concat(chunks)
end

function TmCaseExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. TmCaseExtract.CACHE_SUB
  local W = opts.width or 240
  local H = opts.height or 160

  local function get(i) return rom:get(i) end

  local gfx = Lz77.decompress(get, Versions.TM_CASE_BG_GFX)
  local mapBg = Lz77.decompress(get, Versions.TM_CASE_BG_TILEMAP)
  local mapMenu = Lz77.decompress(get, Versions.TM_CASE_MENU_TILEMAP)
  local palMale = Lz77.decompress(get, Versions.TM_CASE_MENU_MALE_PAL)
  local palFemale = Lz77.decompress(get, Versions.TM_CASE_MENU_FEMALE_PAL)

  -- 1. BG2 Base Backgrounds
  local bgMale = bake_tm_case_bg_rgba(gfx, palMale, mapMenu, W, H)
  local bgFemale = bake_tm_case_bg_rgba(gfx, palFemale, mapMenu, W, H)
  cache:write(root .. "/bg_male.rgba", bgMale)
  cache:write(root .. "/bg_female.rgba", bgFemale)

  -- 2. BG1 Foreground Pocket Covers (Priority 0 over sprites)
  local coverMale = bake_tm_case_cover_rgba(gfx, palMale, mapBg, W, H)
  local coverFemale = bake_tm_case_cover_rgba(gfx, palFemale, mapBg, W, H)
  cache:write(root .. "/cover_male.rgba", coverMale)
  cache:write(root .. "/cover_female.rgba", coverFemale)

  -- 3. Discs (TM + HM for each type 0..16)
  local discGfx = Lz77.decompress(get, Versions.TM_CASE_DISC_GFX)
  local discPal1 = Lz77.decompress(get, Versions.TM_CASE_DISC_TYPES1_PAL)
  local discPal2 = Lz77.decompress(get, Versions.TM_CASE_DISC_TYPES2_PAL)
  local banks1 = load_pal_banks(discPal1, 16)
  local banks2 = load_pal_banks(discPal2, 1)

  local discBanks = {}
  for b = 0, 15 do discBanks[b] = banks1[b] end
  discBanks[16] = banks2[0] -- Dragon type

  for typeIdx = 0, 16 do
    local bank = discBanks[typeIdx] or {}
    local discRgba = bake_disc_rgba(discGfx, bank, false)
    cache:write(string.format("%s/disc_%d.rgba", root, typeIdx), discRgba)
    local hmDiscRgba = bake_disc_rgba(discGfx, bank, true)
    cache:write(string.format("%s/disc_hm_%d.rgba", root, typeIdx), hmDiscRgba)
  end

  -- 4. HM Icon
  local hmGfx = {}
  for i = 1, 96 do hmGfx[i] = rom:get(Versions.TM_CASE_HM_GFX + i - 1) end
  local hmRgba = bake_hm_icon_rgba(hmGfx, banks1[0] or {})
  cache:write(root .. "/hm_icon.rgba", hmRgba)

  local manifest = string.format([[
return {
  format_version = %d,
  width = %d,
  height = %d,
  discW = 32,
  discH = 32,
  discCount = 17,
  hmW = 16,
  hmH = 12,
}
]], TmCaseExtract.FORMAT_VERSION, W, H)
  cache:write(root .. "/manifest.lua", manifest)

  print(string.format("[tm_case_extract] TM Case chrome baked (2 BGs, 2 Covers, 17 TM discs, 17 HM discs, HM icon) -> %s", root))
  return {
    root = root,
    width = W,
    height = H,
    discCount = 17,
  }
end

function TmCaseExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. TmCaseExtract.CACHE_SUB
  if cache and cache.exists then
    return cache:exists(root .. "/bg_male.rgba") and cache:exists(root .. "/cover_male.rgba") and cache:exists(root .. "/disc_0.rgba")
  end
  return false
end

return TmCaseExtract

