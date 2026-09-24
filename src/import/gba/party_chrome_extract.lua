-- Bake FRLG party-menu chrome from ROM into extract/v1/pokemon/party/.
-- BG tilemap + slot panels (slot_*.bin) + pokéball frames.

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local PartyChromeExtract = {}

PartyChromeExtract.CACHE_SUB = "pokemon/party"

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

local function bake_status_icons_rgba(gfx, palBytes)
  local W, H = 32, 64 -- 4 tiles wide x 8 frames
  local banks = load_pal_banks(palBytes, math.max(1, math.floor(byte_len(palBytes) / 32)))
  local pal = banks[0] or {}
  local tileCount = math.floor(byte_len(gfx) / 32)
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end

  local ti = 0
  for ty = 0, 7 do
    for tx = 0, 3 do
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
  return table.concat(chunks), W, H
end

local function bake_bg_rgba(gfx, palBytes, map, W, H)
  local tileCount = math.floor(byte_len(gfx) / 32)
  local banks = load_pal_banks(palBytes, math.floor(byte_len(palBytes) / 32))
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
    chunks[i] = string.char(r, g, b, 255)
  end
  return table.concat(chunks)
end

local function build_party_box_pal(palBytes, selected, multi)
  local banks = load_pal_banks(palBytes, math.floor(byte_len(palBytes) / 32))
  local base = banks[3] or banks[0] or {}
  local pal = {}
  for i = 0, 15 do pal[i] = base[i] or 0 end
  local function get_pal_color(id)
    local b = math.floor(id / 16)
    local c = id % 16
    return (banks[b] and banks[b][c]) or 0
  end
  -- src/party_menu.c:2273
  if multi and selected then
    pal[4] = get_pal_color(132)
    pal[5] = get_pal_color(133)
    pal[6] = get_pal_color(134)
    pal[1] = get_pal_color(97)
    pal[7] = get_pal_color(103)
    pal[8] = get_pal_color(104)
  elseif multi then
    pal[4] = get_pal_color(68)
    pal[5] = get_pal_color(69)
    pal[6] = get_pal_color(70)
    pal[1] = get_pal_color(65)
    pal[7] = get_pal_color(71)
    pal[8] = get_pal_color(72)
  elseif selected then
    -- LOAD_PARTY_BOX_PAL(sPartyBoxCurrSelectionPalIds1, sPartyBoxPalOffsets1)
    -- sPartyBoxCurrSelectionPalIds1 = {116, 117, 118}, sPartyBoxPalOffsets1 = {4, 5, 6}
    pal[4] = get_pal_color(116)
    pal[5] = get_pal_color(117)
    pal[6] = get_pal_color(118)
    -- LOAD_PARTY_BOX_PAL(sPartyBoxCurrSelectionPalIds2, sPartyBoxPalOffsets2)
    -- sPartyBoxCurrSelectionPalIds2 = {97, 103, 104}, sPartyBoxPalOffsets2 = {1, 7, 8}
    pal[1] = get_pal_color(97)
    pal[7] = get_pal_color(103)
    pal[8] = get_pal_color(104)
  else
    -- sPartyBoxEmptySlotPalIds1 = {52, 53, 54}, sPartyBoxPalOffsets1 = {4, 5, 6}
    pal[4] = get_pal_color(52)
    pal[5] = get_pal_color(53)
    pal[6] = get_pal_color(54)
    -- sPartyBoxEmptySlotPalIds2 = {49, 55, 56}, sPartyBoxPalOffsets2 = {1, 7, 8}
    pal[1] = get_pal_color(49)
    pal[7] = get_pal_color(55)
    pal[8] = get_pal_color(56)
  end
  return pal
end

--- Blit slot tilemap (u8 tile ids) using party BG gfx + custom pal or pal bank.
-- Color 0 → transparent (window chrome).
local function bake_slot_rgba(gfx, palBytes, tilemap, tilesW, tilesH, customPalOrBank)
  local W, H = tilesW * 8, tilesH * 8
  local pal
  if type(customPalOrBank) == "table" then
    pal = customPalOrBank
  else
    local banks = load_pal_banks(palBytes, math.floor(byte_len(palBytes) / 32))
    pal = banks[customPalOrBank] or banks[0] or {}
  end
  local tileCount = math.floor(byte_len(gfx) / 32)
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end

  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local tileId = tilemap:byte(ty * tilesW + tx + 1) or 0
      if tileId >= tileCount then tileId = 0 end
      local tile = {}
      local base = tileId * 32
      for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
      decode_tile_4bpp(tile, pixels, tx * 8, ty * 8, W, false, false)
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
  return table.concat(chunks), W, H
end

--- Blit button tilemap (16-bit tile entries) using party BG gfx + pal bank.
-- Color 0 → transparent.
local function bake_button_rgba(gfx, palBytes, tilemap16Bytes, tilesW, tilesH, palBank)
  local W, H = tilesW * 8, tilesH * 8
  local banks = load_pal_banks(palBytes, math.floor(byte_len(palBytes) / 32))
  local pal = (palBank and banks[palBank]) or banks[1] or {}
  local tileCount = math.floor(byte_len(gfx) / 32)
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end

  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local idx = (ty * tilesW + tx) * 2 + 1
      local entry = (tilemap16Bytes:byte(idx) or 0) + (tilemap16Bytes:byte(idx + 1) or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      if tileId >= tileCount then tileId = 0 end
      local tile = {}
      local base = tileId * 32
      for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
      decode_tile_4bpp(tile, pixels, tx * 8, ty * 8, W, hflip, vflip)
    end
  end

  local chunks = {}
  for i = 1, W * H do
    local cIdx = pixels[i] or 0
    if cIdx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[cIdx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks), W, H
end

--- Two 32×32 frames (closed / open) stacked vertically.
local function bake_ball_sheet(gfx, palBytes)
  local fw, fh = 32, 32
  local banks = load_pal_banks(palBytes, math.max(1, math.floor(byte_len(palBytes) / 32)))
  local pal = banks[0] or {}
  local tileCount = math.floor(byte_len(gfx) / 32)
  local sheetH = fh * 2
  local pixels = {}
  for i = 1, fw * sheetH do pixels[i] = 0 end

  for frame = 0, 1 do
    local ti = frame * 16 -- 16 tiles per 32×32
    for ty = 0, 3 do
      for tx = 0, 3 do
        if ti < tileCount then
          local tile = {}
          local base = ti * 32
          for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
          decode_tile_4bpp(tile, pixels, tx * 8, frame * fh + ty * 8, fw, false, false)
        end
        ti = ti + 1
      end
    end
  end

  local chunks = {}
  for i = 1, fw * sheetH do
    local idx = pixels[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks), fw, sheetH, 2
end

local function bake_hold_icons(gfx, palBytes)
  local W, frames = 8, math.floor(byte_len(gfx) / 32)
  local H = 8 * frames
  local pal = load_pal_banks(palBytes, 1)[0] or {}
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end
  for f = 0, frames - 1 do
    local tile = {}
    for i = 1, 32 do tile[i] = gfx[f * 32 + i] or 0 end
    decode_tile_4bpp(tile, pixels, 0, f * 8, W, false, false)
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
  return table.concat(chunks), W, H, frames
end

PartyChromeExtract.bakeHoldIcons = bake_hold_icons

function PartyChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. PartyChromeExtract.CACHE_SUB
  local W = opts.width or 240
  local H = opts.height or 160

  local function get(i) return rom:get(i) end
  local gfx = Lz77.decompress(get, Versions.PARTY_MENU_BG_GFX)
  local pal = Lz77.decompress(get, Versions.PARTY_MENU_BG_PAL)
  local map = Lz77.decompress(get, Versions.PARTY_MENU_BG_TILEMAP)
  cache:write(root .. "/bg.rgba", bake_bg_rgba(gfx, pal, map, W, H))

  local palUnsel = build_party_box_pal(pal, false)
  local palSel = build_party_box_pal(pal, true)
  local palMulti = build_party_box_pal(pal, false, true)
  local palMultiSel = build_party_box_pal(pal, true, true)

  local function raw(off, len)
    local t = {}
    for i = 1, len do t[i] = string.char(get(off + i - 1)) end
    return table.concat(t)
  end
  local mainBin = raw(Versions.PARTY_MENU_SLOT_MAIN_TILEMAP, 70)
  local wideBin = raw(Versions.PARTY_MENU_SLOT_WIDE_TILEMAP, 54)
  local emptyBin = raw(Versions.PARTY_MENU_SLOT_WIDE_EMPTY_TILEMAP, 54)
  do
    local rgba = bake_slot_rgba(gfx, pal, mainBin, 10, 7, palUnsel)
    cache:write(root .. "/slot_main.rgba", rgba)
    local rgbaSel = bake_slot_rgba(gfx, pal, mainBin, 10, 7, palSel)
    cache:write(root .. "/slot_main_selected.rgba", rgbaSel)
    cache:write(root .. "/slot_main_multi.rgba", bake_slot_rgba(gfx, pal, mainBin, 10, 7, palMulti))
    cache:write(root .. "/slot_main_multi_selected.rgba", bake_slot_rgba(gfx, pal, mainBin, 10, 7, palMultiSel))
  end
  do
    local rgba = bake_slot_rgba(gfx, pal, wideBin, 18, 3, palUnsel)
    cache:write(root .. "/slot_wide.rgba", rgba)
    local rgbaSel = bake_slot_rgba(gfx, pal, wideBin, 18, 3, palSel)
    cache:write(root .. "/slot_wide_selected.rgba", rgbaSel)
    cache:write(root .. "/slot_wide_multi.rgba", bake_slot_rgba(gfx, pal, wideBin, 18, 3, palMulti))
    cache:write(root .. "/slot_wide_multi_selected.rgba", bake_slot_rgba(gfx, pal, wideBin, 18, 3, palMultiSel))
  end
  do
    local rgba = bake_slot_rgba(gfx, pal, emptyBin, 18, 3, palUnsel)
    cache:write(root .. "/slot_wide_empty.rgba", rgba)
  end

  local cancelBin = raw(Versions.PARTY_MENU_CANCEL_BUTTON_TILEMAP, 28)
  do
    local cancelRgba = bake_button_rgba(gfx, pal, cancelBin, 7, 2, 1)
    cache:write(root .. "/cancel_button.rgba", cancelRgba)
    local cancelRgbaSel = bake_button_rgba(gfx, pal, cancelBin, 7, 2, 2)
    cache:write(root .. "/cancel_button_selected.rgba", cancelRgbaSel)
  end

  local confirmBin = raw(Versions.PARTY_MENU_CONFIRM_BUTTON_TILEMAP, 28)
  do
    local confirmRgba = bake_button_rgba(gfx, pal, confirmBin, 7, 2, 1)
    cache:write(root .. "/confirm_button.rgba", confirmRgba)
    local confirmRgbaSel = bake_button_rgba(gfx, pal, confirmBin, 7, 2, 2)
    cache:write(root .. "/confirm_button_selected.rgba", confirmRgbaSel)
  end

  local ballGfx = Lz77.decompress(get, Versions.PARTY_MENU_BALL_GFX)
  local ballPal = Lz77.decompress(get, Versions.PARTY_MENU_BALL_PAL)
  local ballRgba, bw, bh, frames = bake_ball_sheet(ballGfx, ballPal)
  cache:write(root .. "/status_balls.rgba", ballRgba)

  -- src/data/party_menu.h:664
  local holdGfx, holdPal = {}, {}
  for i = 1, 64 do holdGfx[i] = get(Versions.PARTY_MENU_HOLD_ICONS_GFX + i - 1) end
  for i = 1, 32 do holdPal[i] = get(Versions.PARTY_MENU_HOLD_ICONS_PAL + i - 1) end
  local holdRgba, holdW, holdH, holdFrames = bake_hold_icons(holdGfx, holdPal)
  cache:write(root .. "/hold_icons.rgba", holdRgba)

  if Versions.SUMMARY_STATUS_ICONS_GFX and Versions.SUMMARY_STATUS_ICONS_PAL then
    local statusGfx = Lz77.decompress(get, Versions.SUMMARY_STATUS_ICONS_GFX)
    local function read_pal_bytes(off, len)
      local t = {}
      for i = 1, len do t[i] = get(off + i - 1) end
      return t
    end
    local statusPal = read_pal_bytes(Versions.SUMMARY_STATUS_ICONS_PAL, 32)
    if statusGfx and statusPal then
      local statusRgba = bake_status_icons_rgba(statusGfx, statusPal)
      cache:write(root .. "/status_icons.rgba", statusRgba)
      local summaryRoot = (opts.cacheRoot or default_cache_root()) .. "/pokemon/summary"
      cache:write(summaryRoot .. "/status_icons.rgba", statusRgba)
    end
  end

  local manifest = string.format(
    "return {\n  width = %d, height = %d,\n  ballW = %d, ballSheetH = %d, ballFrames = %d,\n  slotMainW = 80, slotMainH = 56,\n  slotWideW = 144, slotWideH = 24,\n  cancelButtonW = 56, cancelButtonH = 16,\n  holdIconW = %d, holdIconSheetH = %d, holdIconFrames = %d,\n  pokemonVersion = %d,\n}\n",
    W, H, bw, bh, frames or 2, holdW, holdH, holdFrames, Versions.POKEMON_VERSION or 1)
  cache:write(root .. "/manifest.lua", manifest)

  return {
    root = root, width = W, height = H,
    ballW = bw, ballSheetH = bh, ballFrames = frames,
    holdIconW = holdW, holdIconSheetH = holdH, holdIconFrames = holdFrames,
  }
end

function PartyChromeExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. PartyChromeExtract.CACHE_SUB
  local need = root .. "/slot_main.rgba"
  if cache then
    if cache.read then
      local d = cache:read(need)
      return (d and #d >= 80 * 56 * 4) or false
    elseif cache.exists then
      return cache:exists(need) or false
    end
    return false
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(need)
    if d and #d >= 80 * 56 * 4 then return true end
  end
  if love and love.filesystem and love.filesystem.read then
    local d = love.filesystem.read(need)
    if d and #d >= 80 * 56 * 4 then return true end
  end
  local f = io.open(need, "rb") or io.open("data/generated/gba/" .. PartyChromeExtract.CACHE_SUB .. "/slot_main.rgba", "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d >= 80 * 56 * 4 then return true end
  end
  return false
end

return PartyChromeExtract
