-- Trainer card chrome extractor for Game 3 (FRLG).
-- Bakes card backgrounds (male & female) and badge sheet from ROM into CacheFS (data/generated/gba/trainer_card/).

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local TrainerCardExtract = {}

TrainerCardExtract.CACHE_SUB = "trainer_card"
TrainerCardExtract.FORMAT_VERSION = 1

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
  if type(buf) == "string" then return #buf end
  if type(buf) == "table" then return buf._len or #buf end
  return 0
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
  local n = count or math.max(1, math.floor(byte_len(bytes) / 32))
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

local function bake_card_composite_rgba(gfx, banks, mapFront, mapBg, W, H)
  local tileCount = math.floor(byte_len(gfx) / 32)
  local mapW, mapH = 30, 20
  local indices, pals = {}, {}
  for i = 1, W * H do indices[i] = 0; pals[i] = 0 end

  local function render_layer(map)
    local tilesH = math.min(mapH, math.floor(H / 8))
    local tilesW = math.min(mapW, math.floor(W / 8))
    for ty = 0, tilesH - 1 do
      for tx = 0, tilesW - 1 do
        local mi = (ty * mapW + tx) * 2 + 1
        local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
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
                local idx = tmp[row * 8 + col + 1] or 0
                if idx ~= 0 or indices[py * W + px + 1] == 0 then
                  local di = py * W + px + 1
                  indices[di] = idx
                  pals[di] = palNum
                end
              end
            end
          end
        end
      end
    end
  end

  if mapBg then render_layer(mapBg) end
  if mapFront then render_layer(mapFront) end

  local chunks = {}
  for i = 1, W * H do
    local idx = indices[i] or 0
    local bank = banks[pals[i] or 0] or banks[0]
    local c = bank and bank[idx] or 0
    local r, g, b = bgr555_to_rgb8(c)
    chunks[i] = string.char(r, g, b, 255)
  end
  return table.concat(chunks)
end

--- Decode 8 gym badges (16x16 each, 4 tiles per badge in TL, TR, BL, BR order) into a 128x16 strip.
local function bake_badges_rgba(badgeTiles, palBytes)
  local W, H = 128, 16
  local pal = {}
  for c = 0, 15 do
    local i = c * 2 + 1
    pal[c] = (palBytes[i] or 0) + (palBytes[i + 1] or 0) * 256
  end
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end

  for badge = 0, 7 do
    -- 4 tiles per badge: TL (badge*2), TR (badge*2+1), BL (16+badge*2), BR (16+badge*2+1)
    local tiles = {
      { badge * 2, 0, 0 },
      { badge * 2 + 1, 8, 0 },
      { 16 + badge * 2, 0, 8 },
      { 16 + badge * 2 + 1, 8, 8 },
    }
    for _, t in ipairs(tiles) do
      local tileNum, ox, oy = t[1], t[2], t[3]
      local base = tileNum * 32
      local tile = {}
      for i = 1, 32 do tile[i] = badgeTiles[base + i] or 0 end
      decode_tile_4bpp(tile, pixels, badge * 16 + ox, oy, W, false, false)
    end
  end

  local chunks = {}
  for i = 1, W * H do
    local idx = pixels[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local c = pal[idx] or 0
      local r, g, b = bgr555_to_rgb8(c)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks), W, H
end

function TrainerCardExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. TrainerCardExtract.CACHE_SUB
  local W = opts.width or 240
  local H = opts.height or 160

  local function get(i) return rom and rom.get and rom:get(i) or 0 end
  local function read_bytes(off, len)
    local t = {}
    for i = 1, len do t[i] = get(off + i - 1) end
    return t
  end

  local bgTiles = Lz77.decompress(get, Versions.TRAINER_CARD_BG_TILES or 0xE991F8)
  local mapFront = Lz77.decompress(get, Versions.TRAINER_CARD_FRONT_MAP or 0x3CC6F0)
  local mapBg = Lz77.decompress(get, Versions.TRAINER_CARD_BG_MAP or 0x3CCEC8)
  local palBytes = read_bytes(Versions.TRAINER_CARD_PAL or 0xE99198, 96)
  local femalePalBytes = read_bytes(Versions.TRAINER_CARD_FEMALE_PAL or 0x3CD2A0, 32)
  local badgePalBytes = read_bytes(Versions.TRAINER_CARD_BADGES_PAL or 0x3CD2C0, 32)
  local badgeTiles = Lz77.decompress(get, Versions.TRAINER_CARD_BADGES_TILES or 0x3CD5E8)

  local maleBanks = load_pal_banks(palBytes, 3)
  local femaleBanks = load_pal_banks(palBytes, 3)
  femaleBanks[1] = {}
  for c = 0, 15 do
    local i = c * 2 + 1
    femaleBanks[1][c] = (femalePalBytes[i] or 0) + (femalePalBytes[i + 1] or 0) * 256
  end

  if bgTiles and mapFront and mapBg then
    local maleRgba = bake_card_composite_rgba(bgTiles, maleBanks, mapFront, mapBg, W, H)
    cache:write(root .. "/bg.rgba", maleRgba)

    local femaleRgba = bake_card_composite_rgba(bgTiles, femaleBanks, mapFront, mapBg, W, H)
    cache:write(root .. "/bg_female.rgba", femaleRgba)
  end

  if badgeTiles and badgePalBytes then
    local badgesRgba, bw, bh = bake_badges_rgba(badgeTiles, badgePalBytes)
    cache:write(root .. "/badges.rgba", badgesRgba)
  end

  local manifest = string.format([[
return {
  version = %d,
  width = %d,
  height = %d,
  badgeWidth = 16,
  badgeHeight = 16,
  badgeCount = 8,
}
]], TrainerCardExtract.FORMAT_VERSION, W, H)
  cache:write(root .. "/manifest.lua", manifest)

  return {
    ok = true,
    root = root,
    width = W,
    height = H,
  }
end

function TrainerCardExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. TrainerCardExtract.CACHE_SUB
  local need = root .. "/bg.rgba"
  if cache then
    if cache.read then
      local d = cache:read(need)
      return (d and #d >= 240 * 160 * 4) or false
    elseif cache.exists then
      return cache:exists(need) or false
    end
    return false
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(need)
    if d and #d >= 240 * 160 * 4 then return true end
  end
  if love and love.filesystem and love.filesystem.read then
    local d = love.filesystem.read(need)
    if d and #d >= 240 * 160 * 4 then return true end
  end
  local f = io.open(need, "rb") or io.open("data/generated/gba/" .. TrainerCardExtract.CACHE_SUB .. "/bg.rgba", "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d >= 240 * 160 * 4 then return true end
  end
  return false
end

function TrainerCardExtract.extract(rom, opts)
  return TrainerCardExtract.run(rom, opts and opts.cache, opts)
end

return TrainerCardExtract
