-- Extract FRLG intro / title assets into firered cache for Game3 boot UI.

local Lz77 = require("src.import.gba.lz77")
local Versions = require("src.import.gba.versions")

local ExtractIntro = {}

ExtractIntro.ASSETS = Versions.INTRO

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
  if type(rom) == "table" then
    if type(rom.data) == "string" then return rom.data end
  end
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
  for i = 1, len do
    bytes[i] = out[i] or 0
  end
  return bytes, len
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
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5),
    255
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

local function isMagenta(r, g, b)
  return r == 255 and g == 0 and b == 255
end

--- 64×96 Oak-speech portrait (8bpp tiles, 32-color pal, idx & 0x1F).
-- Color 0 + magenta are transparent so the oak_speech_bg shows through.
local function bakePortraitPng(tiles, pal)
  local W, H = 64, 96
  return encodePng(W, H, function(x, y)
    local tx, ty = math.floor(x / 8), math.floor(y / 8)
    local ti = ty * 8 + tx
    local base = ti * 64
    local idx = tiles[base + (y % 8) * 8 + (x % 8) + 1] or 0
    local li = idx % 32
    if li == 0 then return 0, 0, 0, 0 end
    local c = pal[li] or 0
    local r, g, b = bgr555_to_rgba(c, false)
    if isMagenta(r, g, b) then return 0, 0, 0, 0 end
    return r, g, b, 255
  end)
end

--- Sequential 4bpp tile sheet (no tilemap).
local function bake4bppSheetPng(tiles, pal, cols, rows, transparent0)
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
    if transparent0 and idx == 0 then return 0, 0, 0, 0 end
    local r, g, b = bgr555_to_rgba(pal[idx] or 0, false)
    if isMagenta(r, g, b) then return 0, 0, 0, 0 end
    return r, g, b, 255
  end)
end

--- 4bpp tiles + u16 tilemap → RGBA screen (mapW×mapH tiles).
-- `pal` is either 16 colors (indices 0..15) or 64+ for multi-bank
-- (entry bits 12..15 select bank; color = pals[bank*16 + idx]).
-- screenSize: 0 = 32x32/linear, 1 = 64x32 (horizontal blocks), 2 = 32x64 (vertical blocks).
local function bake4bppMapPng(tiles, pal, map, mapW, mapH, transparent0, screenSize)
  local tileCount = math.floor(#tiles / 32)
  local multi = (pal[16] ~= nil) or (pal[32] ~= nil)
  local W, H = mapW * 8, mapH * 8
  return encodePng(W, H, function(x, y)
    local tx, ty = math.floor(x / 8), math.floor(y / 8)
    local mi
    if screenSize == 2 then
      local block = math.floor(ty / 32)
      local subY = ty % 32
      mi = (block * 1024 + subY * 32 + tx) * 2 + 1
    elseif screenSize == 1 then
      local block = math.floor(tx / 32)
      local subX = tx % 32
      mi = (block * 1024 + ty * 32 + subX) * 2 + 1
    else
      mi = (ty * mapW + tx) * 2 + 1
    end
    local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
    local tid = entry % 1024
    local hflip = math.floor(entry / 1024) % 2 == 1
    local vflip = math.floor(entry / 2048) % 2 == 1
    local pbank = math.floor(entry / 4096) % 16
    if tid >= tileCount then return 0, 0, 0, 0 end
    local sx = hflip and (7 - (x % 8)) or (x % 8)
    local sy = vflip and (7 - (y % 8)) or (y % 8)
    local base = tid * 32
    local byte = tiles[base + sy * 4 + math.floor(sx / 2) + 1] or 0
    local idx = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16) % 16
    if transparent0 and idx == 0 then return 0, 0, 0, 0 end
    local c
    if multi then
      c = pal[pbank * 16 + idx] or pal[idx] or 0
    else
      c = pal[idx] or 0
    end
    local r, g, b = bgr555_to_rgba(c, false)
    if isMagenta(r, g, b) then return 0, 0, 0, 0 end
    return r, g, b, 255
  end)
end

--- Separate Title Screen Copyright and Press Start layers cleanly from ROM.
-- Press Start uses indices 1..5 of pal bank 15.
-- Copyright notice uses indices 7..15.
local function bakeTitleLayers(tiles, pal, map, mapW, mapH)
  local tileCount = math.floor(#tiles / 32)
  local W, H = mapW * 8, mapH * 8
  local copyPng = encodePng(W, H, function(x, y)
    local tx, ty = math.floor(x / 8), math.floor(y / 8)
    local mi = (ty * mapW + tx) * 2 + 1
    local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
    local tid = entry % 1024
    local hflip = math.floor(entry / 1024) % 2 == 1
    local vflip = math.floor(entry / 2048) % 2 == 1
    if tid >= tileCount then return 0, 0, 0, 0 end
    local sx = hflip and (7 - (x % 8)) or (x % 8)
    local sy = vflip and (7 - (y % 8)) or (y % 8)
    local base = tid * 32
    local byte = tiles[base + sy * 4 + math.floor(sx / 2) + 1] or 0
    local idx = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16) % 16
    if idx == 0 or (idx >= 1 and idx <= 5) then return 0, 0, 0, 0 end
    local r, g, b = bgr555_to_rgba(pal[idx] or 0, false)
    return r, g, b, 255
  end)

  local pressPng = encodePng(W, H, function(x, y)
    local tx, ty = math.floor(x / 8), math.floor(y / 8)
    local mi = (ty * mapW + tx) * 2 + 1
    local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
    local tid = entry % 1024
    local hflip = math.floor(entry / 1024) % 2 == 1
    local vflip = math.floor(entry / 2048) % 2 == 1
    if tid >= tileCount then return 0, 0, 0, 0 end
    local sx = hflip and (7 - (x % 8)) or (x % 8)
    local sy = vflip and (7 - (y % 8)) or (y % 8)
    local base = tid * 32
    local byte = tiles[base + sy * 4 + math.floor(sx / 2) + 1] or 0
    local idx = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16) % 16
    if idx >= 1 and idx <= 5 then
      local r, g, b = bgr555_to_rgba(pal[idx] or 0, false)
      return r, g, b, 255
    end
    return 0, 0, 0, 0
  end)

  return copyPng, pressPng
end

--- Build a 30×20 u16 screen map (as byte array) for Controls Guide pages.
-- pret oak_speech.c case7 + ControlsGuide_LoadPage*:
--   Fill whole BG with tile 0; color 0 of pal0 is overridden to stdpal_2[15] blue.
--   Row 2 = red divider (tile 2); row 19 = bottom edge (tile 0xE).
--   Page2/3: CopyToBgTilemapBufferRect overlay at (1,3) 5×16 (button icons).
-- TopBar is a WINDOW with PIXEL_FILL(15) same blue — not a dark navy strip.
local function buildControlsGuideMap(pageOverlay)
  local mapW, mapH = 30, 20
  local map = {}
  for i = 1, mapW * mapH * 2 do map[i] = 0 end
  local function fill(entry, x, y, w, h)
    for yy = y, y + h - 1 do
      for xx = x, x + w - 1 do
        local mi = (yy * mapW + xx) * 2 + 1
        map[mi] = entry % 256
        map[mi + 1] = math.floor(entry / 256) % 256
      end
    end
  end
  -- Entire screen tile 0 / pal 0 (= guide blue after pal[0] override)
  fill(0x0000, 0, 0, 30, 20)
  -- pret uses pal 13 (= stdpal_2) for chrome rows: 0xD00F / 0xD002 / 0xD00E
  fill(0xD00F, 0, 0, 30, 2)
  fill(0xD002, 0, 2, 30, 1)
  fill(0xD00E, 0, 19, 30, 1)
  if pageOverlay then
    -- CopyToBgTilemapBufferRect(1, overlay, 1, 3, 5, 16)
    for y = 0, 15 do
      for x = 0, 4 do
        local oi = (y * 5 + x) * 2 + 1
        local entry = (pageOverlay[oi] or 0) + (pageOverlay[oi + 1] or 0) * 256
        local mi = ((y + 3) * mapW + (x + 1)) * 2 + 1
        map[mi] = entry % 256
        map[mi + 1] = math.floor(entry / 256) % 256
      end
    end
  end
  -- Page 1: pret fills (1,3) 5×16 with 0x3000 to clear icons — that uses pal3
  -- and draws the dark stripe. Skip on page 1 so the intro text page is uniform blue.
  return map, mapW, mapH
end

--- Pikachu intro: 30×18 tilemap placed at (0,2) on a 30×20 screen.
local function buildPikachuIntroMap(tm18)
  local mapW, mapH = 30, 20
  local map = {}
  for i = 1, mapW * mapH * 2 do map[i] = 0 end
  for y = 0, 17 do
    for x = 0, 29 do
      local si = (y * 30 + x) * 2 + 1
      local di = ((y + 2) * mapW + x) * 2 + 1
      map[di] = tm18[si] or 0
      map[di + 1] = tm18[si + 1] or 0
    end
  end
  return map, mapW, mapH
end

--- 8bpp tiles + u16 tilemap (title logo).
local function bake8bppMapPng(tiles, pal, map, mapW, mapH, transparent0)
  local tileCount = math.floor(#tiles / 64)
  local W, H = mapW * 8, mapH * 8
  return encodePng(W, H, function(x, y)
    local tx, ty = math.floor(x / 8), math.floor(y / 8)
    local mi = (ty * mapW + tx) * 2 + 1
    local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
    local tid = entry % 1024
    local hflip = math.floor(entry / 1024) % 2 == 1
    local vflip = math.floor(entry / 2048) % 2 == 1
    if tid >= tileCount then return 0, 0, 0, 0 end
    local sx = hflip and (7 - (x % 8)) or (x % 8)
    local sy = vflip and (7 - (y % 8)) or (y % 8)
    local idx = tiles[tid * 64 + sy * 8 + sx + 1] or 0
    if transparent0 and idx == 0 then return 0, 0, 0, 0 end
    local r, g, b, a = bgr555_to_rgba(pal[idx] or 0, false)
    return r, g, b, a
  end)
end

local function blitLayer(dst, src, W, H, srcW)
  srcW = srcW or W
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if x < srcW then
        local si = (y * srcW + x) * 4
        local a = src[si + 4] or 0
        local r, g, b = src[si + 1] or 0, src[si + 2] or 0, src[si + 3] or 0
        if a > 0 and not (r == 0 and g == 0 and b == 0) then
          local di = (y * W + x) * 4
          dst[di + 1], dst[di + 2], dst[di + 3], dst[di + 4] = r, g, b, 255
        end
      end
    end
  end
end

local function pngToRgbaTable(pngBytes, W, H)
  -- Re-decode via ImageData when available (composite path).
  if not (love and love.image and love.image.newImageData) then return nil end
  local ok, id = pcall(love.image.newImageData, love.filesystem.newFileData(pngBytes, "tmp.png"))
  if not ok or not id then return nil end
  local rgba = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local r, g, b, a = id:getPixel(x, y)
      local o = (y * W + x) * 4
      rgba[o + 1] = math.floor(r * 255 + 0.5)
      rgba[o + 2] = math.floor(g * 255 + 0.5)
      rgba[o + 3] = math.floor(b * 255 + 0.5)
      rgba[o + 4] = math.floor(a * 255 + 0.5)
    end
  end
  return rgba
end

local function rgbaTableToPng(rgba, W, H)
  return encodePng(W, H, function(x, y)
    local o = (y * W + x) * 4
    return rgba[o + 1] or 0, rgba[o + 2] or 0, rgba[o + 3] or 0, rgba[o + 4] or 0
  end)
end

local function cropPng(pngBytes, srcW, srcH, x0, y0, cw, ch)
  local rgba = pngToRgbaTable(pngBytes, srcW, srcH)
  if not rgba then return nil end
  return encodePng(cw, ch, function(x, y)
    local sx, sy = x0 + x, y0 + y
    if sx < 0 or sy < 0 or sx >= srcW or sy >= srcH then
      return 0, 0, 0, 0
    end
    local o = (sy * srcW + sx) * 4
    return rgba[o + 1] or 0, rgba[o + 2] or 0, rgba[o + 3] or 0, rgba[o + 4] or 0
  end)
end

function ExtractIntro.run(rom, cache, opts)
  opts = opts or {}
  local root = opts.root or "data/generated/gba/intro"
  local data = romBytes(rom)
  local meta = {
    version = 3,
    sha1 = opts.sha1,
    assets = {},
    has_rom = data ~= nil,
  }

  local oakSpeech = [[
return {
  -- ROM-sourced intro strings (FireRed USA 1.0 / pret new_game_intro.inc)
  welcome = "Hello, there!\nGlad to meet you!\fWelcome to the world of POKéMON!\fMy name is OAK.\fPeople affectionately refer to me\nas the POKéMON PROFESSOR.",
  this_world = "This world…",
  inhabited = "…is inhabited far and wide by\ncreatures called POKéMON.",
  study = "For some people, POKéMON are pets.\nOthers use them for battling.\fAs for myself…\fI study POKéMON as a profession.",
  tell_me = "But first, tell me a little about\nyourself.",
  ask_gender = "Now tell me. Are you a boy?\nOr are you a girl?",
  your_name = "Let's begin with your name.\nWhat is it?",
  confirm_player = "Right…\nSo your name is {PLAYER}.",
  rival_intro = "This is my grandson.\fHe's been your rival since you both\nwere babies.\f…Erm, what was his name now?",
  rival_name_ask = "Your rival's name, what was it now?",
  confirm_rival = "…Er, was it {RIVAL}?",
  remember_rival = "That's right! I remember now!\nHis name is {RIVAL}!",
  lets_go = "{PLAYER}!\fYour very own POKéMON legend is\nabout to unfold!\fA world of dreams and adventures\nwith POKéMON awaits! Let's go!",
  maleNames = { "RED", "FIRE", "ASH", "KENE", "GEKI", "JAK", "JANNE", "JONN", "KAMON", "KARL", "TAYLOR", "OSCAR", "HIRO", "MAX", "JON", "RALPH", "KAY", "TOSH", "ROAK" },
  femaleNames = { "RED", "FIRE", "OMI", "JODI", "AMANDA", "HILLARY", "MAKEY", "MICHI", "PAULA", "JUNE", "CASSIE", "REY", "SEDA", "KIKO", "MINA", "NORIE", "SAI", "MOMO", "SUZI" },
  rivalNames = { "GREEN", "GARY", "KAZ", "TORU" },
}
]]
  write(cache, root .. "/oak_speech.lua", oakSpeech)
  write(cache, root .. "/title_text.lua",
    'return { title = "POKeMON FireRed", press_start = "Press Start" }\n')
  write(cache, root .. "/menu.lua",
    'return { "CONTINUE", "NEW GAME", "OPTION" }\n')

  if not data then
    write(cache, root .. "/meta.json",
      string.format('{"version":3,"sha1":"%s","has_rom":false}\n', tostring(opts.sha1 or "")))
    return true, meta
  end

  local get = makeGet(data)
  local A = Versions.INTRO
  local okLove = love and love.image and love.image.newImageData

  local function saveAsset(name, png)
    if not png then return false end
    write(cache, root .. "/" .. name, png)
    meta.assets[name] = root .. "/" .. name
    return true
  end

  if okLove then
    -- Portraits
    do
      local pal = readPal(get, A.oak_pal, 32)
      local tiles = decompress(get, A.oak_tiles)
      saveAsset("oak.png", bakePortraitPng(tiles, pal))
    end
    do
      local pal = readPal(get, A.red_pal, 32)
      local tiles = decompress(get, A.red_tiles)
      saveAsset("boy.png", bakePortraitPng(tiles, pal))
    end
    do
      local pal = readPal(get, A.leaf_pal, 32)
      local tiles = decompress(get, A.leaf_tiles)
      saveAsset("girl.png", bakePortraitPng(tiles, pal))
    end
    if A.rival_pal and A.rival_tiles then
      local pal = readPal(get, A.rival_pal, 32)
      local tiles = decompress(get, A.rival_tiles)
      saveAsset("rival.png", bakePortraitPng(tiles, pal))
    end
    do
      local pal = readPal(get, A.platform_pal, 16)
      local tiles = decompress(get, A.platform_tiles)
      -- pret platform.png is 32×96 (3 stacked 32×32 frames); idx 0 is transparent.
      saveAsset("platform.png", bake4bppSheetPng(tiles, pal, 4, 12, true))
    end

    -- Oak speech BG + Nidoran♀ + poke ball (ROM Versions.INTRO extras)
    if A.oak_speech_bg_tiles and A.oak_speech_bg_map then
      local pal = readPal(get, A.oak_speech_bg_pal or A.platform_pal, 16)
      local tiles = decompress(get, A.oak_speech_bg_tiles)
      local map = decompress(get, A.oak_speech_bg_map)
      saveAsset("oak_speech_bg.png", bake4bppMapPng(tiles, pal, map, 32, 20, false))
    end
    -- Controls guide + Pikachu intro (shared bg_tiles, NOT oak_speech_bg)
    if A.guide_bg_tiles and A.guide_bg_pal then
      local pals = readPal(get, A.guide_bg_pal, 64)
      -- pret LoadPalette(GetTextWindowPalette(2)+15, BG_PLTT_ID(0), 2):
      -- force pal0[0] to stdpal_2 color 15 = RGB(0,123,197).
      local guideBlue
      do
        local r5 = math.floor(0 * 31 / 255 + 0.5)
        local g5 = math.floor(123 * 31 / 255 + 0.5)
        local b5 = math.floor(197 * 31 / 255 + 0.5)
        guideBlue = r5 + g5 * 32 + b5 * 1024
      end
      pals[0] = guideBlue
      -- Icon tile "background" (pal3 index 0) matches field blue so D-Pad/A/B
      -- don't sit in dark rectangles (ROM art uses idx0 as fill).
      pals[48] = guideBlue
      -- TopBar / chrome rows use BG pal 13 = GetTextWindowPalette(2) (stdpal_2).
      if A.stdpal_2 then
        local std2 = readPal(get, A.stdpal_2, 16)
        for i = 0, 15 do pals[13 * 16 + i] = std2[i] end
      else
        -- Fallback: synthesize stdpal_2 color 15 + a few used indices from known RGB.
        for i = 0, 15 do pals[13 * 16 + i] = guideBlue end
        pals[13 * 16 + 12] = (0) + (82 * 32) + (115 * 1024) -- approx idx12
        do
          local r5 = math.floor(0 * 31 / 255 + 0.5)
          local g5 = math.floor(82 * 31 / 255 + 0.5)
          local b5 = math.floor(115 * 31 / 255 + 0.5)
          pals[13 * 16 + 12] = r5 + g5 * 32 + b5 * 1024
        end
        do
          local r5 = math.floor(0 * 31 / 255 + 0.5)
          local g5 = math.floor(115 * 31 / 255 + 0.5)
          local b5 = math.floor(139 * 31 / 255 + 0.5)
          pals[13 * 16 + 13] = r5 + g5 * 32 + b5 * 1024
        end
        pals[13 * 16 + 15] = guideBlue
        -- Red for divider (stdpal_2 idx often maps via tile; use pure red)
        pals[13 * 16 + 1] = 31 -- red-ish low; tile 2 uses 12/13/15
      end
      -- Ensure multi-bank bake sees bank 13
      if pals[13 * 16] == nil then pals[13 * 16] = guideBlue end
      local tiles = decompress(get, A.guide_bg_tiles)
      local map1 = buildControlsGuideMap(nil)
      saveAsset("controls_page1.png", bake4bppMapPng(tiles, pals, map1, 30, 20, false))
      if A.controls_page2_map then
        local overlay = {}
        for i = 0, 159 do overlay[i + 1] = get(A.controls_page2_map + i) end
        local map2 = buildControlsGuideMap(overlay)
        saveAsset("controls_page2.png", bake4bppMapPng(tiles, pals, map2, 30, 20, false))
      end
      if A.controls_page3_map then
        local overlay = {}
        for i = 0, 159 do overlay[i + 1] = get(A.controls_page3_map + i) end
        local map3 = buildControlsGuideMap(overlay)
        saveAsset("controls_page3.png", bake4bppMapPng(tiles, pals, map3, 30, 20, false))
      end
      if A.pikachu_intro_map then
        local tm = decompress(get, A.pikachu_intro_map)
        local mapP = buildPikachuIntroMap(tm)
        saveAsset("pikachu_intro_bg.png", bake4bppMapPng(tiles, pals, mapP, 30, 20, false))
      end
    end
    -- Pikachu intro OBJ (body/ears/eyes) — pret CreateSprite stack on paper BG
    if A.pikachu_pal and A.pikachu_body then
      local pal = readPal(get, A.pikachu_pal, 16)
      local body = decompress(get, A.pikachu_body)
      saveAsset("pikachu_body.png", bake4bppSheetPng(body, pal, 4, 8, true))
      if A.pikachu_ears then
        local ears = decompress(get, A.pikachu_ears)
        saveAsset("pikachu_ears.png", bake4bppSheetPng(ears, pal, 4, 4, true))
      end
      if A.pikachu_eyes then
        local eyes = decompress(get, A.pikachu_eyes)
        -- 0x80 = 4 tiles → two 16×8 frames stacked (tile offsets 0 and 2)
        saveAsset("pikachu_eyes.png", bake4bppSheetPng(eyes, pal, 2, 2, true))
      end
    end
    if A.nidoran_f_tiles and A.nidoran_f_pal then
      local palBytes = decompress(get, A.nidoran_f_pal)
      local pal = {}
      for i = 0, 15 do
        local lo = palBytes[i * 2 + 1] or 0
        local hi = palBytes[i * 2 + 2] or 0
        pal[i] = lo + hi * 256
      end
      local tiles = decompress(get, A.nidoran_f_tiles)
      saveAsset("nidoran_f.png", bake4bppSheetPng(tiles, pal, 8, 8, true))
    end
    if A.ball_poke_tiles and A.ball_poke_pal then
      local palBytes = decompress(get, A.ball_poke_pal)
      local pal = {}
      for i = 0, 15 do
        local lo = palBytes[i * 2 + 1] or 0
        local hi = palBytes[i * 2 + 2] or 0
        pal[i] = lo + hi * 256
      end
      local tiles = decompress(get, A.ball_poke_tiles)
      saveAsset("ball_poke.png", bake4bppSheetPng(tiles, pal, 2, 6, true))
    end

    -- Title layers
    local logoPng, boxPng, copyPng
    do
      local pal = readPal(get, A.logo_pal, 256)
      local tiles = decompress(get, A.logo_tiles)
      local map = decompress(get, A.logo_map)
      logoPng = bake8bppMapPng(tiles, pal, map, 32, 20, true)
      saveAsset("title_logo.png", cropPng(logoPng, 256, 160, 0, 0, 240, 160) or logoPng)
    end
    do
      local pal = readPal(get, A.box_pal, 16)
      local tiles = decompress(get, A.box_tiles)
      local map = decompress(get, A.box_map)
      boxPng = bake4bppMapPng(tiles, pal, map, 32, 20, true)
      saveAsset("box_art_mon.png", cropPng(boxPng, 256, 160, 0, 0, 240, 160) or boxPng)
    end
    do
      local pal = readPal(get, A.copyright_pal, 16)
      local tiles = decompress(get, A.copyright_tiles)
      local map = decompress(get, A.copyright_map)
      local titleCopy, titlePress = bakeTitleLayers(tiles, pal, map, 32, 20)
      local copyCrop = cropPng(titleCopy, 256, 160, 0, 0, 240, 160) or titleCopy
      local pressCrop = cropPng(titlePress, 256, 160, 0, 0, 240, 160) or titlePress
      saveAsset("title_copyright.png", copyCrop)
      saveAsset("title_press_start.png", pressCrop)
      -- CacheContract / boot.lua names (full-screen positioned layers).
      saveAsset("press_start.png", pressCrop)
      saveAsset("copyright_press_start.png", copyCrop)
      copyPng = titleCopy
    end

    -- Full title composite (240×160) without press-start (blinks separately).
    -- CacheContract requires data/generated/gba/intro/title_screen.png.
    if logoPng and boxPng and copyPng then
      local W, H = 240, 160
      local dst = {}
      for i = 1, W * H do
        local o = (i - 1) * 4
        dst[o + 1], dst[o + 2], dst[o + 3], dst[o + 4] = 0, 0, 0, 255
      end
      local boxR = pngToRgbaTable(boxPng, 256, 160)
      local logoR = pngToRgbaTable(logoPng, 256, 160)
      local copyR = pngToRgbaTable(copyPng, 256, 160)
      if boxR then blitLayer(dst, boxR, W, H, 256) end
      if logoR then blitLayer(dst, logoR, W, H, 256) end
      -- Copyright bars only (strip press-start band so boot can blink it)
      if copyR then
        for y = 0, H - 1 do
          local skipPress = y >= 124 and y < 144
          if not skipPress then
            for x = 0, W - 1 do
              local si = (y * 256 + x) * 4
              local a = copyR[si + 4] or 0
              local r, g, b = copyR[si + 1] or 0, copyR[si + 2] or 0, copyR[si + 3] or 0
              if a > 0 and not (r == 0 and g == 0 and b == 0) then
                local di = (y * W + x) * 4
                dst[di + 1], dst[di + 2], dst[di + 3], dst[di + 4] = r, g, b, 255
              end
            end
          end
        end
      end
      saveAsset("title_screen.png", rgbaTableToPng(dst, W, H))
    end

    -- Intro Cutscene Movie assets (pokefirered/src/intro.c)
    local M = Versions.INTRO_MOVIE
    if M then
      -- Copyright Screen: 32×32 map, text already at y≈48 within the visible 160px
      -- (BG0VOFS=0). Crop the GBA viewport — do NOT start at y=48 or text sits at y=0.
      if M.copyright_pal and M.copyright_tiles and M.copyright_map then
        local pal = readPal(get, M.copyright_pal, 16)
        local tiles = decompress(get, M.copyright_tiles)
        local map = decompress(get, M.copyright_map)
        local copyScreen = bake4bppMapPng(tiles, pal, map, 32, 32, false, 0)
        saveAsset("intro_copyright.png", cropPng(copyScreen, 256, 256, 0, 0, 240, 160) or copyScreen)
      end
      -- Game Freak Scene
      if M.gf_bg_pal and M.gf_bg_tiles and M.gf_bg_map then
        local pal = readPal(get, M.gf_bg_pal, 16)
        local tiles = decompress(get, M.gf_bg_tiles)
        local map = decompress(get, M.gf_bg_map)
        local gfBg = bake4bppMapPng(tiles, pal, map, 32, 20, false, 0)
        saveAsset("intro_gf_bg.png", cropPng(gfBg, 256, 160, 0, 0, 240, 160) or gfBg)
      end
      if M.gf_logo_pal and M.gf_text_tiles then
        local pal = readPal(get, M.gf_logo_pal, 16)
        local tiles = decompress(get, M.gf_text_tiles)
        -- 144×16 (18×2 tiles)
        saveAsset("intro_gf_text.png", bake4bppSheetPng(tiles, pal, 18, 2, true))
      end
      if M.gf_logo_pal and M.gf_logo_tiles then
        local pal = readPal(get, M.gf_logo_pal, 16)
        local tiles = decompress(get, M.gf_logo_tiles)
        -- 32×64 (4×8 tiles)
        saveAsset("intro_gf_logo.png", bake4bppSheetPng(tiles, pal, 4, 8, true))
      end
      if M.star_pal and M.star_tiles then
        local pal = readPal(get, M.star_pal, 16)
        local tiles = decompress(get, M.star_tiles)
        -- 16×16 (2×2 tiles)
        saveAsset("intro_star.png", bake4bppSheetPng(tiles, pal, 2, 2, true))
      end
      if M.sparkles_pal and M.sparkles_small_tiles then
        local pal = readPal(get, M.sparkles_pal, 16)
        local tiles = decompress(get, M.sparkles_small_tiles)
        -- 16×16 (2×2 tiles)
        saveAsset("intro_sparkles_small.png", bake4bppSheetPng(tiles, pal, 2, 2, true))
      end
      if M.sparkles_pal and M.sparkles_big_tiles then
        local pal = readPal(get, M.sparkles_pal, 16)
        local tiles = decompress(get, M.sparkles_big_tiles)
        -- 32×128 (4×16 tiles, 4 frames of 32×32)
        saveAsset("intro_sparkles_big.png", bake4bppSheetPng(tiles, pal, 4, 16, true))
      end
      if M.gf_logo_pal and M.presents_tiles then
        local pal = readPal(get, M.gf_logo_pal, 16)
        local tiles = decompress(get, M.presents_tiles)
        -- 64×8 (8×1 tiles)
        saveAsset("intro_presents.png", bake4bppSheetPng(tiles, pal, 8, 1, true))
      end

      -- Scene 1 (Grass Close-up: 32×64 tiles, screenSize=2)
      if M.scene1_grass_pal and M.scene1_grass_tiles and M.scene1_grass_map then
        local pal = readPal(get, M.scene1_grass_pal, 16)
        local tiles = decompress(get, M.scene1_grass_tiles)
        local map = decompress(get, M.scene1_grass_map)
        saveAsset("intro_scene1_grass.png", bake4bppMapPng(tiles, pal, map, 32, 64, true, 2))
      end
      if M.scene1_bg_pal and M.scene1_bg_tiles and M.scene1_bg_map then
        local pal = readPal(get, M.scene1_bg_pal, 16)
        local tiles = decompress(get, M.scene1_bg_tiles)
        local map = decompress(get, M.scene1_bg_map)
        saveAsset("intro_scene1_bg.png", bake4bppMapPng(tiles, pal, map, 32, 64, false, 2))
      end

      -- Scene 2 (Forest Clearing & Close-ups)
      -- LoadPalette(..., BG_PLTT_ID(1), 96) → hardware banks 1..3.
      if M.scene2_bg_pal and M.scene2_bg_tiles and M.scene2_bg_map then
        local filePal = readPal(get, M.scene2_bg_pal, 48)
        local pal = {}
        for i = 0, 15 do
          pal[i] = 0
          pal[16 + i] = filePal[i] or 0
          pal[32 + i] = filePal[16 + i] or 0
          pal[48 + i] = filePal[32 + i] or 0
        end
        local tiles = decompress(get, M.scene2_bg_tiles)
        local map = decompress(get, M.scene2_bg_map)
        saveAsset("intro_scene2_bg.png", bake4bppMapPng(tiles, pal, map, 32, 64, false, 2))
      end
      if M.scene2_plants_pal and M.scene2_plants_tiles and M.scene2_plants_map then
        local pal = readPal(get, M.scene2_plants_pal, 16)
        local tiles = decompress(get, M.scene2_plants_tiles)
        local map = decompress(get, M.scene2_plants_map)
        local plants = bake4bppMapPng(tiles, pal, map, 32, 20, true, 0)
        saveAsset("intro_scene2_plants.png", plants)
      end
      if M.gengar_pal and M.scene2_gengar_close_tiles and M.scene2_gengar_close_map then
        local pal = readPal(get, M.gengar_pal, 16)
        local tiles = decompress(get, M.scene2_gengar_close_tiles)
        local map = decompress(get, M.scene2_gengar_close_map)
        saveAsset("intro_scene2_gengar_close.png", bake4bppMapPng(tiles, pal, map, 32, 32, true, 0))
      end
      if M.scene2_nidorino_close_pal and M.scene2_nidorino_close_tiles and M.scene2_nidorino_close_map then
        local pal = readPal(get, M.scene2_nidorino_close_pal, 16)
        local tiles = decompress(get, M.scene2_nidorino_close_tiles)
        local map = decompress(get, M.scene2_nidorino_close_map)
        saveAsset("intro_scene2_nidorino_close.png", bake4bppMapPng(tiles, pal, map, 32, 32, true, 0))
      end
      if M.gengar_pal and M.scene2_gengar_tiles then
        local pal = readPal(get, M.gengar_pal, 16)
        local tiles = decompress(get, M.scene2_gengar_tiles)
        -- 64×64 (8×8 tiles)
        saveAsset("intro_scene2_gengar.png", bake4bppSheetPng(tiles, pal, 8, 8, true))
      end
      if M.nidorino_pal and M.scene2_nidorino_tiles then
        local pal = readPal(get, M.nidorino_pal, 16)
        local tiles = decompress(get, M.scene2_nidorino_tiles)
        -- 64×64 (8×8 tiles)
        saveAsset("intro_scene2_nidorino.png", bake4bppSheetPng(tiles, pal, 8, 8, true))
      end

      -- Scene 3 (Fight Arena)
      -- Bg pal is LoadPalette(..., BG_PLTT_ID(1), 64) → hardware banks 1..2.
      -- Map entries use banks 1/2 (and 0 for empty); shift file pal into those slots.
      if M.scene3_bg_pal and M.scene3_bg_tiles and M.scene3_bg_map then
        local filePal = readPal(get, M.scene3_bg_pal, 32)
        local pal = {}
        for i = 0, 15 do
          pal[i] = 0
          pal[16 + i] = filePal[i] or 0
          pal[32 + i] = filePal[16 + i] or 0
        end
        local tiles = decompress(get, M.scene3_bg_tiles)
        local map = decompress(get, M.scene3_bg_map)
        local s3Bg = bake4bppMapPng(tiles, pal, map, 32, 20, false, 0)
        saveAsset("intro_scene3_bg.png", s3Bg)
      end
      if M.gengar_pal and M.scene3_gengar_anim_tiles and M.scene3_gengar_anim_map then
        local pal = readPal(get, M.gengar_pal, 16)
        local tiles = decompress(get, M.scene3_gengar_anim_tiles)
        local map = decompress(get, M.scene3_gengar_anim_map)
        -- screenSize=2 → 32×64 tiles (256×512), frames stacked vertically
        saveAsset("intro_scene3_gengar_anim.png", bake4bppMapPng(tiles, pal, map, 32, 64, true, 2))
      end
      if M.scene3_grass_pal and M.scene3_grass_tiles then
        local pal = readPal(get, M.scene3_grass_pal, 16)
        local tiles = decompress(get, M.scene3_grass_tiles)
        -- 64×64 (8×8 tiles)
        saveAsset("intro_scene3_grass.png", bake4bppSheetPng(tiles, pal, 8, 8, true))
      end
      if M.gengar_pal and M.scene3_gengar_static_tiles then
        local pal = readPal(get, M.gengar_pal, 16)
        local tiles = decompress(get, M.scene3_gengar_static_tiles)
        -- 64×192 (8×24 tiles) — 4 OAM pieces, not 3 stacked frames
        saveAsset("intro_scene3_gengar_static.png", bake4bppSheetPng(tiles, pal, 8, 24, true))
      end
      if M.nidorino_pal and M.scene3_nidorino_tiles then
        local pal = readPal(get, M.nidorino_pal, 16)
        local tiles = decompress(get, M.scene3_nidorino_tiles)
        -- 64×320 (8×40 tiles, 5 frames of 64×64)
        saveAsset("intro_scene3_nidorino.png", bake4bppSheetPng(tiles, pal, 8, 40, true))
      end
      if M.scene3_swipe_pal and M.scene3_swipe_tiles then
        local pal = readPal(get, M.scene3_swipe_pal, 16)
        local tiles = decompress(get, M.scene3_swipe_tiles)
        -- 32×160 (4×20 tiles): two 32×64 swipe halves
        saveAsset("intro_scene3_swipe.png", bake4bppSheetPng(tiles, pal, 4, 20, true))
      end
      if M.scene3_recoil_dust_pal and M.scene3_recoil_dust_tiles then
        local pal = readPal(get, M.scene3_recoil_dust_pal, 16)
        local tiles = decompress(get, M.scene3_recoil_dust_tiles)
        -- 16×64 (2×8 tiles)
        saveAsset("intro_scene3_recoil_dust.png", bake4bppSheetPng(tiles, pal, 2, 8, true))
      end
    end

    -- Title Screen particle effects (pokefirered/src/title_screen.c)
    local T = Versions.TITLE_EFFECTS
    if T then
      if T.border_bg_tiles and T.border_bg_map then
        local pal = readPal(get, A.copyright_pal, 16)
        local tiles = decompress(get, T.border_bg_tiles)
        local map = decompress(get, T.border_bg_map)
        local borderBg = bake4bppMapPng(tiles, pal, map, 32, 20, false, 0)
        saveAsset("title_border_bg.png", cropPng(borderBg, 256, 160, 0, 0, 240, 160) or borderBg)
      end
      if T.flames_pal and T.flames_tiles then
        local pal = readPal(get, T.flames_pal, 16)
        local tiles = decompress(get, T.flames_tiles)
        -- 0x500 = 40 tiles → 10 frames of 16×16 (2×20)
        saveAsset("title_flames.png", bake4bppSheetPng(tiles, pal, 2, 20, true))
      end
      if T.flames_pal and T.slash_tiles then
        local pal = readPal(get, T.flames_pal, 16)
        local tiles = decompress(get, T.slash_tiles)
        -- 64×64 (8×8 tiles)
        saveAsset("title_slash.png", bake4bppSheetPng(tiles, pal, 8, 8, true))
      end
    end
  else
    meta.note = "love.image unavailable; wrote text stubs only"
  end

  local assetList = {}
  for k in pairs(meta.assets) do
    assetList[#assetList + 1] = k
  end
  table.sort(assetList)

  write(cache, root .. "/meta.json",
    string.format(
      '{"version":3,"sha1":"%s","has_rom":true,"assets":[%s]}\n',
      tostring(opts.sha1 or ""),
      table.concat((function()
        local q = {}
        for _, n in ipairs(assetList) do
          q[#q + 1] = '"' .. n .. '"'
        end
        return q
      end)(), ",")))

  -- Gen1/2-shaped index: data/generated/intro.lua points at extracted PNGs.
  local indexPath = opts.introIndex or "data/generated/intro.lua"
  local pathMap = {
    { "oakPic", "oak.png" },
    { "playerPic", "boy.png" },
    { "playerPicFemale", "girl.png" },
    { "rivalPic", "rival.png" },
    { "platform", "platform.png" },
    { "oakSpeechBg", "oak_speech_bg.png" },
    { "controlsPage1", "controls_page1.png" },
    { "controlsPage2", "controls_page2.png" },
    { "controlsPage3", "controls_page3.png" },
    { "pikachuIntroBg", "pikachu_intro_bg.png" },
    { "pikachuBody", "pikachu_body.png" },
    { "pikachuEars", "pikachu_ears.png" },
    { "pikachuEyes", "pikachu_eyes.png" },
    { "nidoranFront", "nidoran_f.png" },
    { "ballPoke", "ball_poke.png" },
    { "titleScreen", "title_screen.png" },
    { "titleLogo", "title_logo.png" },
    { "boxArtMon", "box_art_mon.png" },
    { "pressStart", "press_start.png" },
    { "copyrightPressStart", "copyright_press_start.png" },
    { "titleBorder", "title_border_bg.png" },
    { "titleFlames", "title_flames.png" },
    { "titleSlash", "title_slash.png" },
    -- Intro Cutscene Assets
    { "introCopyright", "intro_copyright.png" },
    { "introGfBg", "intro_gf_bg.png" },
    { "introGfText", "intro_gf_text.png" },
    { "introGfLogo", "intro_gf_logo.png" },
    { "introStar", "intro_star.png" },
    { "introSparklesSmall", "intro_sparkles_small.png" },
    { "introSparklesBig", "intro_sparkles_big.png" },
    { "introPresents", "intro_presents.png" },
    { "introScene1Grass", "intro_scene1_grass.png" },
    { "introScene1Bg", "intro_scene1_bg.png" },
    { "introScene2Bg", "intro_scene2_bg.png" },
    { "introScene2Plants", "intro_scene2_plants.png" },
    { "introScene2GengarClose", "intro_scene2_gengar_close.png" },
    { "introScene2NidorinoClose", "intro_scene2_nidorino_close.png" },
    { "introScene2Gengar", "intro_scene2_gengar.png" },
    { "introScene2Nidorino", "intro_scene2_nidorino.png" },
    { "introScene3Bg", "intro_scene3_bg.png" },
    { "introScene3GengarAnim", "intro_scene3_gengar_anim.png" },
    { "introScene3Grass", "intro_scene3_grass.png" },
    { "introScene3GengarStatic", "intro_scene3_gengar_static.png" },
    { "introScene3Nidorino", "intro_scene3_nidorino.png" },
    { "introScene3Swipe", "intro_scene3_swipe.png" },
    { "introScene3RecoilDust", "intro_scene3_recoil_dust.png" },
  }
  local lines = {
    "return {\n",
    "  generation = 3,\n",
    '  version = "firered",\n',
    '  source = "ROM:title_screen + oak_speech",\n',
  }
  if opts.sha1 then
    lines[#lines + 1] = string.format('  sha1 = %q,\n', tostring(opts.sha1))
  end
  for _, pair in ipairs(pathMap) do
    local key, file = pair[1], pair[2]
    if meta.assets[file] then
      lines[#lines + 1] = string.format("  %s = %q,\n", key, root .. "/" .. file)
    end
  end
  lines[#lines + 1] = string.format('  oakSpeech = %q,\n', root .. "/oak_speech.lua")
  lines[#lines + 1] = "}\n"
  write(cache, indexPath, table.concat(lines))
  meta.introIndex = indexPath

  return true, meta
end

return ExtractIntro
