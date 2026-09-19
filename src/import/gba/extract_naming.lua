-- Extract FRLG naming-screen chrome from ROM → firered cache.
-- Offsets: Versions.NAMING (FireRed USA 1.0).
-- Layout reference: pret naming_screen.c (ROM is source of truth for pixels).

local Lz77 = require("src.import.gba.lz77")
local Versions = require("src.import.gba.versions")

local ExtractNaming = {}

ExtractNaming.CACHE_SUB = "gba/naming"
ExtractNaming.ASSETS = Versions.NAMING

local function write(cache, path, data)
  if cache and cache.write then
    return cache:write(path, data)
  end
  if love and love.filesystem and love.filesystem.write then
    return love.filesystem.write(path, data)
  end
  return false
end

local function romBytes(rom)
  if type(rom) == "string" then return rom end
  if type(rom) == "table" and type(rom.data) == "string" then return rom.data end
  return nil
end

local function makeGet(data)
  return function(i)
    return data:byte(i + 1) or 0
  end
end

local function decompress(get, off)
  local out = Lz77.decompress(get, off)
  local len = out._len or #out
  local bytes = {}
  for i = 1, len do bytes[i] = out[i] or 0 end
  return bytes, len
end

local function readRaw(get, off, n)
  local bytes = {}
  for i = 1, n do bytes[i] = get(off + i - 1) end
  return bytes
end

local function readPal(get, off, count)
  local pal = {}
  for i = 0, count - 1 do
    local lo = get(off + i * 2)
    local hi = get(off + i * 2 + 1)
    pal[i] = lo + hi * 256
  end
  return pal
end

local function bgr555_to_rgba(c, transparent0)
  c = (tonumber(c) or 0) % 32768
  if transparent0 and c == 0 then return 0, 0, 0, 0 end
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  local r = math.floor(r5 * 255 / 31 + 0.5)
  local g = math.floor(g5 * 255 / 31 + 0.5)
  local b = math.floor(b5 * 255 / 31 + 0.5)
  -- Magenta key
  if r > 240 and g < 16 and b > 240 then return 0, 0, 0, 0 end
  return r, g, b, 255
end

local function encodePng(W, H, setPixel)
  if not (love and love.image and love.image.newImageData) then
    return nil
  end
  local id = love.image.newImageData(W, H)
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local r, g, b, a = setPixel(x, y)
      id:setPixel(x, y, r / 255, g / 255, b / 255, a / 255)
    end
  end
  local fd = id:encode("png")
  return fd:getString()
end

local function bake4bppSheet(tiles, pal, cols, rows, transparent0, keep)
  local tileCount = math.floor(#tiles / 32)
  local W, H = cols * 8, rows * 8
  return encodePng(W, H, function(x, y)
    local tx, ty = math.floor(x / 8), math.floor(y / 8)
    local ti = ty * cols + tx
    if ti >= tileCount then return 0, 0, 0, 0 end
    local base = ti * 32
    local row = y % 8
    local px = x % 8
    local byte = tiles[base + row * 4 + math.floor(px / 2) + 1] or 0
    local idx = (px % 2 == 0) and (byte % 16) or math.floor(byte / 16) % 16
    if keep and not keep[idx] then return 0, 0, 0, 0 end
    if transparent0 and idx == 0 then return 0, 0, 0, 0 end
    return bgr555_to_rgba(pal[idx] or 0, false)
  end)
end

--- 16×16 OBJ: 4 tiles in row-major 2×2 (matches pret cursor.png).
local function bakeObj16(tiles4, pal)
  return encodePng(16, 16, function(x, y)
    local tx, ty = math.floor(x / 8), math.floor(y / 8)
    local ti = ty * 2 + tx
    local base = ti * 32
    local row = y % 8
    local px = x % 8
    local byte = tiles4[base + row * 4 + math.floor(px / 2) + 1] or 0
    local idx = (px % 2 == 0) and (byte % 16) or math.floor(byte / 16) % 16
    if idx == 0 then return 0, 0, 0, 0 end
    return bgr555_to_rgba(pal[idx] or 0, false)
  end)
end

local function bake4bppMap(tiles, palBanks, map, mapW, mapH, defaultBank, transparent0)
  defaultBank = defaultBank or 0
  local tileCount = math.floor(#tiles / 32)
  local W, H = mapW * 8, mapH * 8
  return encodePng(W, H, function(x, y)
    local tx, ty = math.floor(x / 8), math.floor(y / 8)
    local mi = (ty * mapW + tx) * 2 + 1
    local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
    local tid = entry % 1024
    local hflip = math.floor(entry / 1024) % 2 == 1
    local vflip = math.floor(entry / 2048) % 2 == 1
    local bank = math.floor(entry / 4096) % 16
    if tid >= tileCount then return 0, 0, 0, 0 end
    local pal = palBanks[bank] or palBanks[defaultBank] or palBanks[0]
    local sx = hflip and (7 - (x % 8)) or (x % 8)
    local sy = vflip and (7 - (y % 8)) or (y % 8)
    local base = tid * 32
    local byte = tiles[base + sy * 4 + math.floor(sx / 2) + 1] or 0
    local idx = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16) % 16
    if transparent0 and idx == 0 then return 0, 0, 0, 0 end
    return bgr555_to_rgba(pal[idx] or 0, false)
  end)
end

local function cropPng(pngBytes, srcW, srcH, x0, y0, cw, ch)
  if not (love and love.image and love.image.newImageData) then return pngBytes end
  local ok, id = pcall(love.image.newImageData, love.filesystem.newFileData(pngBytes, "tmp.png"))
  if not ok or not id then return pngBytes end
  local out = love.image.newImageData(cw, ch)
  for y = 0, ch - 1 do
    for x = 0, cw - 1 do
      local sx, sy = x0 + x, y0 + y
      if sx >= 0 and sy >= 0 and sx < srcW and sy < srcH then
        out:setPixel(x, y, id:getPixel(sx, sy))
      else
        out:setPixel(x, y, 0, 0, 0, 0)
      end
    end
  end
  return out:encode("png"):getString()
end

local function loadMenuPalBanks(get, off)
  local banks = {}
  for b = 0, 5 do
    banks[b] = readPal(get, off + b * 32, 16)
  end
  return banks
end

--- @return boolean ok
function ExtractNaming.run(rom, cache, opts)
  opts = opts or {}
  local data = romBytes(rom)
  if not data then return false, "no rom bytes" end
  local get = makeGet(data)
  local A = Versions.NAMING
  local root = opts.root or ("data/generated/" .. ExtractNaming.CACHE_SUB)
  local function out(name)
    return root .. "/" .. name
  end

  local menuGfx = select(1, decompress(get, A.menu_gfx))
  local menuBanks = loadMenuPalBanks(get, A.menu_pal)
  local rivalPal = readPal(get, A.rival_pal, 16)

  local bgMap = select(1, decompress(get, A.background_map))
  local kbUpper = select(1, decompress(get, A.keyboard_upper_map))
  local kbLower = select(1, decompress(get, A.keyboard_lower_map))
  local kbSym = select(1, decompress(get, A.keyboard_symbols_map))

  local bgPng = bake4bppMap(menuGfx, menuBanks, bgMap, 32, 20, 0, false)
  if bgPng then
    -- Visible 240×160 (map is 256×160)
    write(cache, out("bg.png"), cropPng(bgPng, 256, 160, 0, 0, 240, 160) or bgPng)
  end

  -- Keyboard page chrome: full blue frame + SELECT tab (not just WIN_KB).
  -- Opaque bbox ≈ (17,75)-(189,151); crop (16,72) 176×80 keeps the border/tab
  -- that page_swap sprites sit on (pret BG1/BG2 keyboard_* tilemaps).
  local KB_X, KB_Y, KB_W, KB_H = 16, 72, 176, 80
  local function bakeKb(map, name)
    local full = bake4bppMap(menuGfx, menuBanks, map, 32, 20, 0, false)
    if not full then return end
    local cropped = cropPng(full, 256, 160, KB_X, KB_Y, KB_W, KB_H)
    write(cache, out(name), cropped or full)
  end
  bakeKb(kbUpper, "kb_upper.png")
  bakeKb(kbLower, "kb_lower.png")
  bakeKb(kbSym, "kb_symbols.png")

  local btnPal = menuBanks[4] or menuBanks[0]
  local curPal = menuBanks[5] or menuBanks[0]

  local function sheet(off, nbytes, cols, rows, pal, fname, transparent0, keep)
    local tiles = readRaw(get, off, nbytes)
    local png = bake4bppSheet(tiles, pal, cols, rows, transparent0 ~= false, keep)
    if png then write(cache, out(fname), png) end
  end

  local glowPal = {}
  for i = 0, 15 do glowPal[i] = 0 end
  glowPal[14] = 0x7FFF -- White mask for index 14 (tinted by naming screen cursor pulse)

  local pillBorder = { [14] = true }
  sheet(A.back_button, 0x1E0, 5, 3, btnPal, "back_button.png")
  sheet(A.ok_button, 0x1E0, 5, 3, btnPal, "ok_button.png")
  sheet(A.page_swap_frame, 0x280, 5, 4, glowPal, "page_swap_button_glow.png", true, pillBorder)
  sheet(A.back_button, 0x1E0, 5, 3, glowPal, "back_button_glow.png", true, pillBorder)
  sheet(A.ok_button, 0x1E0, 5, 3, glowPal, "ok_button_glow.png", true, pillBorder)
  sheet(A.page_swap_frame, 0x280, 5, 4, btnPal, "page_swap_frame.png")
  sheet(A.page_swap_button, 0x100, 4, 2, menuBanks[1] or btnPal, "page_swap_button.png")
  sheet(A.page_swap_button, 0x100, 4, 2, menuBanks[1] or btnPal, "page_swap_button_upper.png")
  sheet(A.page_swap_button, 0x100, 4, 2, menuBanks[2] or btnPal, "page_swap_button_lower.png")
  sheet(A.page_swap_button, 0x100, 4, 2, menuBanks[3] or btnPal, "page_swap_button_others.png")
  sheet(A.page_swap_upper, 0x60, 5, 1, btnPal, "page_swap_upper.png")
  sheet(A.page_swap_lower, 0x60, 5, 1, btnPal, "page_swap_lower.png")
  sheet(A.page_swap_others, 0x60, 5, 1, btnPal, "page_swap_others.png")
  sheet(A.input_arrow, 0x20, 1, 1, btnPal, "input_arrow.png")
  sheet(A.underscore, 0x20, 1, 1, btnPal, "underscore.png")

  -- Cursor: 3× 16×16 frames (idle / squish / filled), row-major 2×2 tiles each.
  local frames = {
    readRaw(get, A.cursor, 0x80),
    readRaw(get, A.cursor_squished, 0x80),
    readRaw(get, A.cursor_filled, 0x80),
  }
  local curStrip = encodePng(48, 16, function(x, y)
    local fi = math.floor(x / 16)
    local lx = x % 16
    local tiles = frames[fi + 1]
    if not tiles then return 0, 0, 0, 0 end
    local tx, ty = math.floor(lx / 8), math.floor(y / 8)
    local ti = ty * 2 + tx
    local base = ti * 32
    local row = y % 8
    local px = lx % 8
    local byte = tiles[base + row * 4 + math.floor(px / 2) + 1] or 0
    local idx = (px % 2 == 0) and (byte % 16) or math.floor(byte / 16) % 16
    if idx == 0 then return 0, 0, 0, 0 end
    return bgr555_to_rgba(curPal[idx] or 0, false)
  end)
  if curStrip then write(cache, out("cursor.png"), curStrip) end

  sheet(A.rival_gfx, 0x900, 2, 36, rivalPal, "rival.png")

  local manifest = string.format([[
return {
  version = 3,
  bg = %q,
  kb_upper = %q,
  kb_lower = %q,
  kb_symbols = %q,
  back_button = %q,
  ok_button = %q,
  page_swap_frame = %q,
  page_swap_button = %q,
  page_swap_button_upper = %q,
  page_swap_button_lower = %q,
  page_swap_button_others = %q,
  page_swap_upper = %q,
  page_swap_lower = %q,
  page_swap_others = %q,
  page_swap_button_glow = %q,
  back_button_glow = %q,
  ok_button_glow = %q,
  cursor = %q,
  input_arrow = %q,
  underscore = %q,
  rival = %q,
  kb_x = 16,
  kb_y = 72,
  kb_w = 176,
  kb_h = 80,
}
]],
    out("bg.png"), out("kb_upper.png"), out("kb_lower.png"), out("kb_symbols.png"),
    out("back_button.png"), out("ok_button.png"), out("page_swap_frame.png"),
    out("page_swap_button.png"), out("page_swap_button_upper.png"),
    out("page_swap_button_lower.png"), out("page_swap_button_others.png"),
    out("page_swap_upper.png"), out("page_swap_lower.png"), out("page_swap_others.png"),
    out("page_swap_button_glow.png"), out("back_button_glow.png"), out("ok_button_glow.png"),
    out("cursor.png"), out("input_arrow.png"),
    out("underscore.png"), out("rival.png"))
  write(cache, out("manifest.lua"), manifest)
  return true
end

function ExtractNaming.ready(cache, cacheRoot)
  local root = (cacheRoot or "data/generated") .. "/" .. ExtractNaming.CACHE_SUB
  local path = root .. "/manifest.lua"
  if cache and cache.exists then
    return cache:exists(path)
  end
  if love and love.filesystem and love.filesystem.getInfo then
    return love.filesystem.getInfo(path) ~= nil
  end
  return false
end

return ExtractNaming
