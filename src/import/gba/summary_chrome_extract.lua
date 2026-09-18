-- Bake FRLG Pokémon Summary Screen chrome from ROM into data/generated/gba/pokemon/summary/.
-- Backgrounds, HP/EXP bars, status ailment icons, cursors, shiny star, Pokérus, and layout manifest.

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local SummaryChromeExtract = {}

SummaryChromeExtract.CACHE_SUB = "pokemon/summary"

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function get_byte(t, idx)
  if type(t) == "string" then
    return t:byte(idx) or 0
  elseif type(t) == "table" then
    return t[idx] or 0
  end
  return 0
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
      local byte = get_byte(tileBytes, srcRow * 4 + bx + 1)
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
      colors[c] = get_byte(bytes, i) + get_byte(bytes, i + 1) * 256
    end
    banks[b] = colors
  end
  return banks
end

local function read_bin(candidates)
  for _, p in ipairs(candidates) do
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.readActive then
      local d = CacheFs.readActive(p)
      if d and #d > 0 then return d end
    end
    if love and love.filesystem and love.filesystem.read then
      local ok, d = pcall(love.filesystem.read, p)
      if ok and d and #d > 0 then return d end
    end
    local f = io.open(p, "rb")
    if f then
      local d = f:read("*a")
      f:close()
      if d and #d > 0 then return d end
    end
  end
  return nil
end

--- Bake a BG tilemap to RGBA.
-- On GBA, palette index 0 is transparent (shows lower BGs / backdrop).
-- When transparent0 is true, index 0 is written with alpha 0.
local function bake_bg_rgba(gfx, palBytes, map, W, H, transparent0)
  local tileCount = math.floor(byte_len(gfx) / 32)
  local banks = load_pal_banks(palBytes, math.max(1, math.floor(byte_len(palBytes) / 32)))
  local mapW = 32
  local indices, pals = {}, {}
  for i = 1, W * H do indices[i] = 0; pals[i] = 0 end

  local tilesH = math.min(32, math.floor(H / 8))
  local tilesW = math.min(32, math.floor(W / 8))
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local mi = (ty * mapW + tx) * 2 + 1
      local entry = get_byte(map, mi) + get_byte(map, mi + 1) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local palNum = math.floor(entry / 4096) % 16
      if tileId >= tileCount then tileId = 0 end
      local tile = {}
      local base = tileId * 32
      for i = 1, 32 do tile[i] = get_byte(gfx, base + i) end
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
    if transparent0 and idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local bank = banks[pals[i] or 0] or banks[0]
      local c = bank and bank[idx] or 0
      local r, g, b = bgr555_to_rgb8(c)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks)
end

--- Overlay `top` onto `bottom` where top alpha > 0 (both raw RGBA strings).
local function composite_rgba(bottom, top)
  if not bottom or bottom == "" then return top end
  if not top or top == "" then return bottom end
  local n = math.min(#bottom, #top)
  local out = {}
  local i = 1
  while i <= n do
    local a = top:byte(i + 3) or 0
    if a > 0 then
      out[#out + 1] = top:sub(i, i + 3)
    else
      out[#out + 1] = bottom:sub(i, i + 3)
    end
    i = i + 4
  end
  if #bottom > n then out[#out + 1] = bottom:sub(n + 1) end
  return table.concat(out)
end

--- Pret uses BG3 base tilemaps under the page overlays:
---   INFO/SKILLS/EGG → sBgTilemap_MovesInfoPage (ROM 0x463B88, LZ 1280 B)
---   MOVES/MOVES_INFO → sBgTilemap_MovesPage (ROM 0x463C80, LZ 2048 B)
--- First try ROM decompress (works on Android), then fall back to external .bin files.
local function load_base_tilemap(kind, get)
  -- ROM path (always works on Android, iOS, etc.)
  if get then
    local off = (kind == "moves") and (Versions.SUMMARY_PAGE_MOVES_BASE_TILEMAP or 0x463C80)
                                    or  (Versions.SUMMARY_PAGE_MOVES_INFO_BASE_TILEMAP or 0x463B88)
    local dec = Lz77.decompress(get, off)
    if dec and byte_len(dec) > 0 then return dec end
  end
  -- Fallback: pret source tree or pre-extracted cache
  local names = {
    info  = { "moves_info_page.bin" },
    moves = { "moves_page.bin" },
  }
  local list = names[kind] or names.info
  local candidates = {}
  for _, n in ipairs(list) do
    candidates[#candidates + 1] = "pokefirered/graphics/summary_screen/" .. n
    candidates[#candidates + 1] = "data/generated/gba/pokemon/summary/" .. n
  end
  return read_bin(candidates)
end

local function bake_page_composited(gfx, palBytes, pageMap, baseMap, W, H)
  local baseRgba
  if baseMap then
    -- Base layer keeps opaque color0 only where tiles actually use it; page overlay
    -- punches through with transparent index 0 (GBA BG transparency).
    baseRgba = bake_bg_rgba(gfx, palBytes, baseMap, W, H, false)
  end
  local pageRgba = bake_bg_rgba(gfx, palBytes, pageMap, W, H, true)
  if baseRgba then
    return composite_rgba(baseRgba, pageRgba)
  end
  -- No base: replace chromakey with opaque so Love does not clear to magenta.
  return bake_bg_rgba(gfx, palBytes, pageMap, W, H, false)
end

--- Bake tile strip (e.g. 12 tiles in a horizontal line: 96x8 px).
local function bake_strip_rgba(gfx, palBytes, numTiles, palBank)
  local W = numTiles * 8
  local H = 8
  local banks = load_pal_banks(palBytes, math.max(1, math.floor(byte_len(palBytes) / 32)))
  local pal = banks[palBank or 0] or banks[0] or {}
  local tileCount = math.floor(byte_len(gfx) / 32)
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end

  for ti = 0, numTiles - 1 do
    if ti < tileCount then
      local tile = {}
      local base = ti * 32
      for i = 1, 32 do tile[i] = get_byte(gfx, base + i) end
      decode_tile_4bpp(tile, pixels, ti * 8, 0, W, false, false)
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

--- Bake multi-tile sprite sheet (e.g. status icons: 4 tiles wide x 8 frames = 32x64).
local function bake_sheet_rgba(gfx, palBytes, tilesX, tilesY, palBank)
  local W = tilesX * 8
  local H = tilesY * 8
  local banks = load_pal_banks(palBytes, math.max(1, math.floor(byte_len(palBytes) / 32)))
  local pal = banks[palBank or 0] or banks[0] or {}
  local tileCount = math.floor(byte_len(gfx) / 32)
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end

  local ti = 0
  for ty = 0, tilesY - 1 do
    for tx = 0, tilesX - 1 do
      if ti < tileCount then
        local tile = {}
        local base = ti * 32
        for i = 1, 32 do tile[i] = get_byte(gfx, base + i) end
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

--- Set a tile (or rectangle of tiles) in a 32-wide GBA tilemap.
local function set_tilemap_rect(map, tileNum, tx, ty, tw, th)
  tw = tw or 1
  th = th or 1
  local lo = tileNum % 256
  local hi = math.floor(tileNum / 256)
  for dy = 0, th - 1 do
    for dx = 0, tw - 1 do
      local idx = ((ty + dy) * 32 + (tx + dx)) * 2 + 1
      map[idx] = lo
      map[idx + 1] = hi
    end
  end
end

--- Apply FRLG PokeSum_DrawPageProgressTiles dynamically to the base BG3 tilemap.
-- Base tile number offset is 345 (0x159).
local function apply_page_progress_tiles(baseMapBytes, pageKind)
  if not baseMapBytes then return nil end
  local map = {}
  local blen = byte_len(baseMapBytes)
  for i = 1, blen do
    map[i] = get_byte(baseMapBytes, i)
  end
  local BASE = 345

  if pageKind == "info" then
    set_tilemap_rect(map, 17 + BASE, 13, 0, 1, 1)
    set_tilemap_rect(map, 33 + BASE, 13, 1, 1, 1)
    set_tilemap_rect(map, 16 + BASE, 14, 0, 1, 1)
    set_tilemap_rect(map, 32 + BASE, 14, 1, 1, 1)
    set_tilemap_rect(map, 18 + BASE, 15, 0, 1, 1)
    set_tilemap_rect(map, 34 + BASE, 15, 1, 1, 1)
    set_tilemap_rect(map, 20 + BASE, 16, 0, 1, 1)
    set_tilemap_rect(map, 36 + BASE, 16, 1, 1, 1)
    set_tilemap_rect(map, 18 + BASE, 17, 0, 1, 1)
    set_tilemap_rect(map, 34 + BASE, 17, 1, 1, 1)
    set_tilemap_rect(map, 21 + BASE, 18, 0, 1, 1)
    set_tilemap_rect(map, 37 + BASE, 18, 1, 1, 1)
  elseif pageKind == "skills" then
    set_tilemap_rect(map, 49 + BASE, 13, 0, 1, 1)
    set_tilemap_rect(map, 65 + BASE, 13, 1, 1, 1)
    set_tilemap_rect(map,  1 + BASE, 14, 0, 1, 1)
    set_tilemap_rect(map, 19 + BASE, 14, 1, 1, 1)
    set_tilemap_rect(map, 17 + BASE, 15, 0, 1, 1)
    set_tilemap_rect(map, 33 + BASE, 15, 1, 1, 1)
    set_tilemap_rect(map, 16 + BASE, 16, 0, 1, 1)
    set_tilemap_rect(map, 32 + BASE, 16, 1, 1, 1)
    set_tilemap_rect(map, 18 + BASE, 17, 0, 1, 1)
    set_tilemap_rect(map, 34 + BASE, 17, 1, 1, 1)
    set_tilemap_rect(map, 21 + BASE, 18, 0, 1, 1)
    set_tilemap_rect(map, 37 + BASE, 18, 1, 1, 1)
  elseif pageKind == "moves" then
    set_tilemap_rect(map, 49 + BASE, 13, 0, 1, 1)
    set_tilemap_rect(map, 65 + BASE, 13, 1, 1, 1)
    set_tilemap_rect(map,  1 + BASE, 14, 0, 1, 1)
    set_tilemap_rect(map, 19 + BASE, 14, 1, 1, 1)
    set_tilemap_rect(map, 49 + BASE, 15, 0, 1, 1)
    set_tilemap_rect(map, 65 + BASE, 15, 1, 1, 1)
    set_tilemap_rect(map,  1 + BASE, 16, 0, 1, 1)
    set_tilemap_rect(map, 19 + BASE, 16, 1, 1, 1)
    set_tilemap_rect(map, 17 + BASE, 17, 0, 1, 1)
    set_tilemap_rect(map, 33 + BASE, 17, 1, 1, 1)
    set_tilemap_rect(map, 48 + BASE, 18, 0, 1, 1)
    set_tilemap_rect(map, 64 + BASE, 18, 1, 1, 1)
  elseif pageKind == "moves_info" then
    set_tilemap_rect(map, 49 + BASE, 13, 0, 1, 1)
    set_tilemap_rect(map, 65 + BASE, 13, 1, 1, 1)
    set_tilemap_rect(map,  1 + BASE, 14, 0, 1, 1)
    set_tilemap_rect(map, 19 + BASE, 14, 1, 1, 1)
    set_tilemap_rect(map, 49 + BASE, 15, 0, 1, 1)
    set_tilemap_rect(map, 65 + BASE, 15, 1, 1, 1)
    set_tilemap_rect(map,  1 + BASE, 16, 0, 1, 1)
    set_tilemap_rect(map, 19 + BASE, 16, 1, 1, 1)
    set_tilemap_rect(map, 50 + BASE, 17, 0, 1, 1)
    set_tilemap_rect(map, 66 + BASE, 17, 1, 1, 1)
    set_tilemap_rect(map, 48 + BASE, 18, 0, 1, 1)
    set_tilemap_rect(map, 64 + BASE, 18, 1, 1, 1)
  elseif pageKind == "egg" then
    set_tilemap_rect(map, 17 + BASE, 13, 0, 1, 1)
    set_tilemap_rect(map, 33 + BASE, 13, 1, 1, 1)
    set_tilemap_rect(map, 48 + BASE, 14, 0, 1, 1)
    set_tilemap_rect(map, 64 + BASE, 14, 1, 1, 1)
    set_tilemap_rect(map,  2 + BASE, 15, 0, 4, 2)
  end

  local chars = {}
  for i = 1, #map do
    chars[i] = string.char(map[i])
  end
  return table.concat(chars)
end

function SummaryChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. SummaryChromeExtract.CACHE_SUB
  local W = opts.width or 240
  local H = opts.height or 160

  local function get(i) return rom and rom.get and rom:get(i) or 0 end
  local function read_bytes(off, len)
    local t = {}
    for i = 1, len do t[i] = get(off + i - 1) end
    return t
  end

  -- Background tiles & palettes
  local bgGfx = rom and Lz77.decompress(get, Versions.SUMMARY_BG_GFX)
  local bgPal = rom and read_bytes(Versions.SUMMARY_BG_PAL, 7 * 32)

  -- Tilemaps for each page
  local mapInfo = rom and Lz77.decompress(get, Versions.SUMMARY_PAGE_INFO_TILEMAP)
  local mapSkills = rom and Lz77.decompress(get, Versions.SUMMARY_PAGE_SKILLS_TILEMAP)
  local mapMoves = rom and Lz77.decompress(get, Versions.SUMMARY_PAGE_MOVES_TILEMAP)
  local mapMovesInfo = rom and Lz77.decompress(get, Versions.SUMMARY_PAGE_MOVES_INFO_TILEMAP)
  local mapEgg = rom and Lz77.decompress(get, Versions.SUMMARY_PAGE_EGG_TILEMAP)

  -- Pret stacks BG3 base (moves_info_page / moves_page) under page overlays.
  -- ROM decompression is tried first so Android never needs the pokefirered/ source tree.
  local baseInfo  = load_base_tilemap("info",  get)
  local baseMoves = load_base_tilemap("moves", get)

  if bgGfx and bgPal and mapInfo then
    local baseInfoP1 = apply_page_progress_tiles(baseInfo, "info")
    local baseSkillsP2 = apply_page_progress_tiles(baseInfo, "skills")
    local baseMovesP3 = apply_page_progress_tiles(baseMoves, "moves")
    local baseMovesInfoP4 = apply_page_progress_tiles(baseMoves, "moves_info")
    local baseEggPEgg = apply_page_progress_tiles(baseInfo, "egg")

    cache:write(root .. "/page_info.rgba", bake_page_composited(bgGfx, bgPal, mapInfo, baseInfoP1, W, H))
    cache:write(root .. "/page_skills.rgba", bake_page_composited(bgGfx, bgPal, mapSkills, baseSkillsP2, W, H))
    cache:write(root .. "/page_moves.rgba", bake_page_composited(bgGfx, bgPal, mapMoves, baseMovesP3, W, H))
    cache:write(root .. "/page_moves_info.rgba", bake_page_composited(bgGfx, bgPal, mapMovesInfo, baseMovesInfoP4, W, H))
    cache:write(root .. "/page_egg.rgba", bake_page_composited(bgGfx, bgPal, mapEgg, baseEggPEgg, W, H))
  end

  -- HP Bar & EXP Bar
  local hpGfx = rom and Lz77.decompress(get, Versions.SUMMARY_HP_BAR_GFX)
  local expGfx = rom and Lz77.decompress(get, Versions.SUMMARY_EXP_BAR_GFX)
  local hpExpPal = rom and read_bytes(Versions.SUMMARY_HP_EXP_PAL, 32)
  local hpYellowPal = rom and read_bytes(Versions.SUMMARY_HP_BAR_YELLOW_PAL, 32)
  local hpRedPal = rom and read_bytes(Versions.SUMMARY_HP_BAR_RED_PAL, 32)

  if hpGfx and hpExpPal then
    local hpGreenRgba = bake_strip_rgba(hpGfx, hpExpPal, 12, 0)
    local hpYellowRgba = bake_strip_rgba(hpGfx, hpYellowPal, 12, 0)
    local hpRedRgba = bake_strip_rgba(hpGfx, hpRedPal, 12, 0)
    cache:write(root .. "/hp_bar_green.rgba", hpGreenRgba)
    cache:write(root .. "/hp_bar_yellow.rgba", hpYellowRgba)
    cache:write(root .. "/hp_bar_red.rgba", hpRedRgba)
  end

  if expGfx and hpExpPal then
    local expRgba = bake_strip_rgba(expGfx, hpExpPal, 12, 0)
    cache:write(root .. "/exp_bar.rgba", expRgba)
  end

  -- Status Ailment Icons (LZ 4bpp, 1024 bytes = 32 tiles = 4 tiles wide x 8 frames = 32x64)
  local statusGfx = rom and Lz77.decompress(get, Versions.SUMMARY_STATUS_ICONS_GFX)
  local statusPal = rom and read_bytes(Versions.SUMMARY_STATUS_ICONS_PAL, 32)
  if statusGfx and statusPal then
    local statusRgba = bake_sheet_rgba(statusGfx, statusPal, 4, 8, 0)
    cache:write(root .. "/status_icons.rgba", statusRgba)
  end

  -- Cursors (LZ 4bpp, 64x64 = 8 tiles wide x 8 tiles high)
  local curLeftGfx = rom and Lz77.decompress(get, Versions.SUMMARY_CURSOR_LEFT_GFX)
  local curRightGfx = rom and Lz77.decompress(get, Versions.SUMMARY_CURSOR_RIGHT_GFX)
  local curPal = rom and read_bytes(Versions.SUMMARY_CURSOR_PAL, 32)
  if curLeftGfx and curPal then
    local curLeftRgba = bake_sheet_rgba(curLeftGfx, curPal, 8, 8, 0)
    cache:write(root .. "/cursor_left.rgba", curLeftRgba)
  end
  if curRightGfx and curPal then
    local curRightRgba = bake_sheet_rgba(curRightGfx, curPal, 8, 8, 0)
    cache:write(root .. "/cursor_right.rgba", curRightRgba)
  end

  -- Shiny star (8x16) & Pokérus (8x8)
  local starGfx = rom and Lz77.decompress(get, Versions.SUMMARY_SHINY_STAR_GFX)
  local starPal = rom and read_bytes(Versions.SUMMARY_SHINY_STAR_PAL, 32)
  if starGfx and starPal then
    local starRgba = bake_sheet_rgba(starGfx, starPal, 1, 2, 0)
    cache:write(root .. "/shiny_star.rgba", starRgba)
  end

  local pkrsGfx = rom and Lz77.decompress(get, Versions.SUMMARY_POKERUS_GFX)
  local pkrsPal = rom and read_bytes(Versions.SUMMARY_POKERUS_PAL, 32)
  if pkrsGfx and pkrsPal then
    local pkrsRgba = bake_sheet_rgba(pkrsGfx, pkrsPal, 1, 1, 0)
    cache:write(root .. "/pokerus.rgba", pkrsRgba)
  end

  -- pokefirered/src/list_menu.c:738
  if rom and Versions.MENU_INFO_GFX and Versions.MENU_INFO_PAL then
    local miGfx = read_bytes(Versions.MENU_INFO_GFX, 128 * 128 / 2)
    local miPal = read_bytes(Versions.MENU_INFO_PAL, 64)
    local caught = bake_sheet_rgba(miGfx, miPal, 16, 16, 0)
    local types = bake_sheet_rgba(miGfx, miPal, 16, 16, 1)
    local split = 16 * 128 * 4
    cache:write(root .. "/menu_info.rgba", caught:sub(1, split) .. types:sub(split + 1))
  end

  local menuInfoBin = read_bin({
    "src/import/gba/chrome/menus/menu_info.png",
    "data/generated/gba/pokemon/summary/menu_info.png",
  })
  if menuInfoBin then
    cache:write(root .. "/menu_info.png", menuInfoBin)
  end



  -- Manifest: absolute screen coords derived from pret window templates + printers
  -- (pokemon_summary_screen.c PrintInfoPage / PrintSkillsPage / PrintMovesPage / etc.).
  local manifest = string.format([[
return {
  width = %d,
  height = %d,
  pages = {
    INFO = 0,
    SKILLS = 1,
    MOVES = 2,
    MOVES_INFO = 3,
    EGG = 4,
  },
  coords = {
    -- CreateMonPicSprite(..., 60, 65) — CreateSprite center of 64x64 (draw at cx-32,cy-32)
    monPic = { x = 60, y = 65, w = 64, h = 64 },
    ball = { x = 106, y = 88, w = 16, h = 16 },
    -- WIN_LVL_NICK at (0,16): Lv(4,2) Nick(40,2) Gender(105,2)
    level = { x = 4, y = 18 },
    name = { x = 40, y = 18 },
    gender = { x = 105, y = 18 },
    -- WIN_INFO_3 at (120,16): dex/species/OT/ID/item + type blit
    dexNo = { x = 167, y = 21 },
    species = { x = 167, y = 35 },
    type1 = { x = 167, y = 51, w = 32, h = 12 },
    type2 = { x = 203, y = 51, w = 32, h = 12 },
    otName = { x = 167, y = 65 },
    otId = { x = 167, y = 80 },
    item = { x = 167, y = 95 },
    -- WIN_INFO_4 trainer memo at (8,112)
    memo = { x = 8, y = 115, w = 224, h = 40 },
    -- WIN_SKILLS_3 at (160,16) + HP/EXP bar sprites
    hpText = { x = 174, y = 20 },
    hpBar = { x = 168, y = 32, w = 48, h = 8 },
    atk = { x = 210, y = 38 },
    def = { x = 210, y = 51 },
    spAtk = { x = 210, y = 64 },
    spDef = { x = 210, y = 77 },
    spd = { x = 210, y = 90 },
    expPointsLabel = { x = 74, y = 103 },
    nextLvLabel = { x = 74, y = 116 },
    expTotal = { x = 175, y = 103 },
    expNext = { x = 175, y = 116 },
    expBar = { x = 152, y = 128, w = 64, h = 8 },
    -- WIN_SKILLS_5 ability pane at (8,128)
    abilityName = { x = 74, y = 129 },
    abilityDesc = { x = 10, y = 143, w = 232, h = 16 },
    status = { x = 16, y = 38 },
    statusMovesInfo = { x = 16, y = 45 },
    shinyStar = { x = 8, y = 40 },
    pokerus = { x = 8, y = 44 },
  },
  -- WIN_MOVES_5 types at (120,16); WIN_MOVES_3 names/PP at (160,16)
  -- GetMoveNamePrinterYpos(i)=i*28+5, GetMovePpPrinterYpos(i)=i*28+16
  moveSlots = {
    { nameX = 163, nameY = 21, typeX = 123, typeY = 21, ppX = 196, ppY = 32 },
    { nameX = 163, nameY = 49, typeX = 123, typeY = 49, ppX = 196, ppY = 60 },
    { nameX = 163, nameY = 77, typeX = 123, typeY = 77, ppX = 196, ppY = 88 },
    { nameX = 163, nameY = 105, typeX = 123, typeY = 105, ppX = 196, ppY = 116 },
  },
  -- WIN_MOVES_4 move stats at (0,56)
  movesInfo = {
    power = { x = 57, y = 57 },
    accuracy = { x = 57, y = 71 },
    desc = { x = 7, y = 98, w = 112, h = 48 },
  },
}
]], W, H)
  cache:write(root .. "/manifest.lua", manifest)

  return {
    root = root,
    width = W,
    height = H,
  }
end

function SummaryChromeExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. SummaryChromeExtract.CACHE_SUB
  local need = root .. "/page_info.rgba"
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
  local f = io.open(need, "rb") or io.open("data/generated/gba/" .. SummaryChromeExtract.CACHE_SUB .. "/page_info.rgba", "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d >= 240 * 160 * 4 then return true end
  end
  return false
end

return SummaryChromeExtract
