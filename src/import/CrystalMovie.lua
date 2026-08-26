-- Crystal's intro movie and title screen extraction (pokecrystal
-- engine/movie/intro.asm:1678-1777, engine/movie/title.asm:364-374).
-- Called from RomExtractorGen2's extractIntro/extractTitle stages when
-- edition == "crystal"; reads through the passed-in extractor and never
-- mutates it.

local ImageWriter = require("src.import.ImageWriter")

local CrystalMovie = {}

local TILE_BYTES = 16
local SHEET_TILES = 16

-- vBGMap tilemaps and attrmaps are one full 32x32 map
-- (engine/movie/intro.asm:1611-1628 decompresses $40 tiles = 1024 bytes).
local MAP_BYTES = 1024

local function padTiles(raw, count)
  local length = count * TILE_BYTES
  while #raw > length do table.remove(raw) end
  while #raw < length do raw[#raw + 1] = 0 end
  return raw
end

-- Lay `count` tiles of `source` (from tile `from`, 0-based) over `target`
-- starting at tile `at` (0-based).
local function overlayTiles(target, source, at, from, count)
  for offset = 1, count * TILE_BYTES do
    target[at * TILE_BYTES + offset] = source[from * TILE_BYTES + offset] or 0
  end
  return target
end

local function blankTiles(count)
  local out = {}
  for index = 1, count * TILE_BYTES do out[index] = 0 end
  return out
end

-- Sheets are 16 tiles per row so tile id N resolves to (N % 16, N / 16),
-- the same layout data/sprite_anims/oam.asm:120-136 assumes.
local function writeSheet(self, raw, count, relative)
  padTiles(raw, count)
  local rows = math.ceil(count / SHEET_TILES)
  padTiles(raw, rows * SHEET_TILES)
  self:write2bpp(raw, SHEET_TILES * 8, rows * 8, relative, true)
  return "assets/generated/" .. relative
end

local function readMap(self, label)
  local bytes = self:decompressLz3Symbol(label)
  while #bytes > MAP_BYTES do table.remove(bytes) end
  while #bytes < MAP_BYTES do bytes[#bytes + 1] = 0 end
  return bytes
end

-- 16 palettes: 8 BG then 8 OBJ (engine/movie/intro.asm:123-130 copies
-- `16 palettes` over wBGPals1, which wOBPals1 follows).
local function readPalettes(self, label)
  local symbol = self:symbol(label)
  local flat = self:colors(symbol.bank, symbol.address, 64)
  local bg, obj = {}, {}
  for pal = 0, 7 do
    local a, b = {}, {}
    for slot = 1, 4 do
      a[slot] = flat[pal * 4 + slot]
      b[slot] = flat[(pal + 8) * 4 + slot]
    end
    bg[pal + 1], obj[pal + 1] = a, b
  end
  return { bg = bg, obj = obj }
end

local function readColors(self, label, count)
  local symbol = self:symbol(label)
  return self:colors(symbol.bank, symbol.address, count)
end

function CrystalMovie.extractIntro(self)
  self:beginStage("Intro movie")
  local out = {
    generation = 2,
    layout = "crystal",
    source = "ROM:CrystalIntro (engine/movie/intro.asm)",
  }

  local unowns = padTiles(self:decompressLz3Symbol("IntroUnownsGFX"), 128)
  local grassSym = self:symbol("IntroGrass4GFX")
  local grass4 = self.rom:bytes(grassSym.bank, grassSym.address, TILE_BYTES)

  local unownsPath = writeSheet(self, unowns, 128, "intro/unowns_tiles.png")
  local pulsePath = writeSheet(self,
    self:decompressLz3Symbol("IntroPulseGFX"), 16, "intro/pulse_sprites.png")
  local backgroundPath = writeSheet(self,
    self:decompressLz3Symbol("IntroBackgroundGFX"), 128,
    "intro/background_tiles.png")
  local runPath = writeSheet(self,
    self:decompressLz3Symbol("IntroSuicuneRunGFX"), 192,
    "intro/suicune_run_sprites.png")
  local pichuPath = writeSheet(self,
    self:decompressLz3Symbol("IntroPichuWooperGFX"), 128,
    "intro/pichu_wooper_sprites.png")
  self:tick("Intro movie", 1, 4)

  -- IntroScene15: jump BG at vTiles2 plus IntroGrass4GFX at vTiles1 tile 0,
  -- i.e. BG id $80 (engine/movie/intro.asm:744-753).
  local jump = blankTiles(256)
  overlayTiles(jump, self:decompressLz3Symbol("IntroSuicuneJumpGFX"), 0, 0, 128)
  overlayTiles(jump, grass4, 0x80, 0, 1)
  local jumpPath = writeSheet(self, jump, 256, "intro/suicune_jump_tiles.png")

  -- The same grass tile is the whole of the SUICUNE_AWAY object's sheet
  -- (data/sprite_anims/oam.asm:136 base $80; engine/movie/intro.asm:750-753).
  local unownBack = blankTiles(144)
  overlayTiles(unownBack, self:decompressLz3Symbol("IntroUnownBackGFX"), 0, 0, 48)
  overlayTiles(unownBack, grass4, 0x80, 0, 1)
  local unownBackPath = writeSheet(self, unownBack, 144,
    "intro/unown_back_sprites.png")

  -- IntroScene17 loads 255 tiles from vTiles1, so BG id $80 is close tile 0
  -- and ids wrap through $00-$7e (engine/movie/intro.asm:825-828).
  local closeRaw = padTiles(self:decompressLz3Symbol("IntroSuicuneCloseGFX"), 255)
  local close = blankTiles(256)
  for id = 0, 255 do
    local from = (id + 128) % 256
    if from < 255 then overlayTiles(close, closeRaw, id, from, 1) end
  end
  local closePath = writeSheet(self, close, 256, "intro/suicune_close_tiles.png")

  -- IntroScene19: suicune_back at vTiles2, the Unown ring at vTiles1, and
  -- grass over vTiles1 tile $7f = BG id $ff (engine/movie/intro.asm:890-901).
  local back = blankTiles(256)
  overlayTiles(back, self:decompressLz3Symbol("IntroSuicuneBackGFX"), 0, 0, 128)
  overlayTiles(back, unowns, 128, 0, 128)
  overlayTiles(back, grass4, 0xff, 0, 1)
  local backPath = writeSheet(self, back, 256, "intro/suicune_back_tiles.png")

  local crystalUnownsPath = writeSheet(self,
    self:decompressLz3Symbol("IntroCrystalUnownsGFX"), 32,
    "intro/crystal_unowns_tiles.png")

  -- Intro_RustleGrass swaps 4 tiles at vTiles2 tile $09 through grass1/2/3
  -- (engine/movie/intro.asm:1521-1547); one 16-tile row, frame f at f*4.
  local grassStrip = blankTiles(16)
  for frame, label in ipairs({ "IntroGrass1GFX", "IntroGrass2GFX",
      "IntroGrass3GFX" }) do
    local sym = self:symbol(label)
    overlayTiles(grassStrip,
      self.rom:bytes(sym.bank, sym.address, 4 * TILE_BYTES), (frame - 1) * 4,
      0, 4)
  end
  out.grassFrames = writeSheet(self, grassStrip, 16, "intro/grass_anim.png")
  self:tick("Intro movie", 2, 4)

  local unownPals = readPalettes(self, "IntroUnownsPalette")
  local backgroundPals = readPalettes(self, "IntroBackgroundPalette")
  local suicunePals = readPalettes(self, "IntroSuicunePalette")
  local closePals = readPalettes(self, "IntroSuicuneClosePalette")
  local crystalUnownsPals = readPalettes(self, "IntroCrystalUnownsPalette")

  local function act(tiles, sprites, tilemapLabel, attrmapLabel, palettes)
    return {
      tiles = tiles,
      sprites = sprites,
      tilemap = readMap(self, tilemapLabel),
      attrmap = readMap(self, attrmapLabel),
      palettes = palettes,
    }
  end

  out.acts = {
    unownA = act(unownsPath, pulsePath,
      "IntroUnownATilemap", "IntroUnownAAttrmap", unownPals),
    unownHI = act(unownsPath, pulsePath,
      "IntroUnownHITilemap", "IntroUnownHIAttrmap", unownPals),
    unowns = act(unownsPath, pulsePath,
      "IntroUnownsTilemap", "IntroUnownsAttrmap", unownPals),
    background = act(backgroundPath, runPath,
      "IntroBackgroundTilemap", "IntroBackgroundAttrmap", backgroundPals),
    suicuneJump = act(jumpPath, unownBackPath,
      "IntroSuicuneJumpTilemap", "IntroSuicuneJumpAttrmap", suicunePals),
    suicuneClose = act(closePath, nil,
      "IntroSuicuneCloseTilemap", "IntroSuicuneCloseAttrmap", closePals),
    suicuneBack = act(backPath, unownBackPath,
      "IntroSuicuneBackTilemap", "IntroSuicuneBackAttrmap", suicunePals),
    crystalUnowns = act(crystalUnownsPath, nil,
      "IntroCrystalUnownsTilemap", "IntroCrystalUnownsAttrmap",
      crystalUnownsPals),
  }
  -- IntroScene7/10 load pichu_wooper into VRAM bank 1
  -- (engine/movie/intro.asm:340-348); OAM_BANK1 picks this sheet.
  out.acts.background.sprites1 = pichuPath
  self:tick("Intro movie", 3, 4)

  out.fades = {
    toWhite = {},
    unownAppear = readColors(self, "Intro_Scene20_AppearUnown.pal1", 4),
    unownAppear2 = readColors(self, "Intro_Scene20_AppearUnown.pal2", 4),
    wordFast = readColors(self, "Intro_FadeUnownWordPals.FastFadePalettes", 16),
    wordSlow = readColors(self, "Intro_FadeUnownWordPals.SlowFadePalettes", 16),
  }
  -- Intro_Scene24_ApplyPaletteFade steps 8 rows of one palette each
  -- (engine/movie/intro.asm:1155-1189).
  local fade = readColors(self, "Intro_Scene24_ApplyPaletteFade.FadePals", 32)
  for row = 0, 7 do
    local pal = {}
    for slot = 1, 4 do pal[slot] = fade[row * 4 + slot] end
    out.fades.toWhite[row + 1] = pal
  end

  self:write("intro", out)
  self:tick("Intro movie", 4, 4)
  return out
end

--------------------------------------------------------------------------

local function shadeOf(r)
  if r > 0.9 then return 0 end
  if r > 0.5 then return 1 end
  if r > 0.2 then return 2 end
  return 3
end

local function tilesFrom2bpp(raw)
  local tiles = {}
  for offset = 1, #raw - (#raw % TILE_BYTES), TILE_BYTES do
    local one = {}
    for index = offset, offset + TILE_BYTES - 1 do one[#one + 1] = raw[index] end
    tiles[#tiles + 1] = ImageWriter.decode2bpp(one, 8, 8, true)
  end
  return tiles
end

local function blitTile(target, tile, tx, ty)
  if not tile then return end
  for y = 0, 7 do
    for x = 0, 7 do
      local r, g, b, a = tile:getPixel(x, y)
      if a ~= 0 then target:setPixel(tx + x, ty + y, r, g, b, a) end
    end
  end
end

local function colorize(image, palFor)
  local w, h = image:getDimensions()
  local out = ImageWriter.blank(w, h, 0, 0, 0, 0)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, _, _, a = image:getPixel(x, y)
      if a ~= 0 then
        local pal = palFor(x, y)
        local c = pal[shadeOf(r) + 1] or pal[4] or { 0, 0, 0 }
        out:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, 1)
      end
    end
  end
  return out
end

-- engine/movie/splash.asm:20-30 sets SCGB_GAMEFREAK_LOGO before Copyright, so
-- the card runs on gfx/sgb/predef.pal:79 PREDEFPAL_GAMEFREAK_LOGO_BG.
local COPYRIGHT_TILES = 29
local COPYRIGHT_BG = {
  { 0, 0, 0 }, { 66, 90, 90 }, { 173, 173, 173 }, { 255, 255, 255 },
}

-- data/copyright.asm at hlcoord 2, 7 (engine/menus/intro_menu.asm:1315-1326).
local COPYRIGHT_LINES = {
  { 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66,
    0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c },
  { 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66,
    0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x7a, 0x7b, 0x7c },
  { 0x60, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66,
    0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x7b, 0x7c },
}

local function extractCopyright(self)
  local symbol = self:symbol("CopyrightGFX")
  local raw = self.rom:bytes(symbol.bank, symbol.address,
    COPYRIGHT_TILES * TILE_BYTES)
  self:write2bpp(raw, COPYRIGHT_TILES * 8, 8, "title/copyright.png")

  local painted = {}
  for index, tile in ipairs(tilesFrom2bpp(raw)) do
    painted[index] = colorize(tile, function() return COPYRIGHT_BG end)
  end
  local backdrop = COPYRIGHT_BG[1]
  local splash = ImageWriter.blank(160, 144,
    backdrop[1] / 255, backdrop[2] / 255, backdrop[3] / 255, 1)
  for row, line in ipairs(COPYRIGHT_LINES) do
    for column, id in ipairs(line) do
      blitTile(splash, painted[id - 0x60 + 1], (1 + column) * 8, (6 + row) * 8)
    end
  end
  self:save(splash, "title/copyright_splash.png")
end

function CrystalMovie.extractTitle(self)
  self:beginStage("Title screen")

  -- TitleLogoGFX decompresses to vTiles1, so BG id $80 is logo tile 0 and
  -- ids $00-$1b wrap on past it (engine/movie/title.asm:91-94).
  local logoTiles = tilesFrom2bpp(self:decompressLz3Symbol("TitleLogoGFX"))
  -- TitleSuicuneGFX fills vTiles4-vTiles5: bank-1 ids $80-$ff then $00-$7f
  -- (engine/movie/title.asm:24-27).
  local suicuneTiles = tilesFrom2bpp(self:decompressLz3Symbol("TitleSuicuneGFX"))
  local gemTiles = tilesFrom2bpp(self:decompressLz3Symbol("TitleCrystalGFX"))
  local pals = readPalettes(self, "TitleScreenPalettes")
  self:tick("Title screen", 1, 5)

  -- Attribute regions from _TitleScreen's ByteFills
  -- (engine/movie/title.asm:39-85): logo gradient rows, the version strip,
  -- pal 7 on the window copyright line, pal 0 everywhere else.
  local function bgPalAt(col, row)
    if row == 9 and col >= 5 and col <= 15 then return 1 end
    if row >= 3 and row <= 4 then return 2 end
    if row == 5 then return 3 end
    if row == 6 then return 4 end
    if row == 7 then return 5 end
    if row >= 8 and row <= 9 then return 6 end
    if row == 17 then return 7 end
    return 0
  end

  local shade = ImageWriter.blank(160, 144, 0, 0, 0, 0)
  -- DrawTitleGraphic lays 7 rows of 20 running tiles from d=$80
  -- (engine/movie/title.asm:107-112,275-302).
  for row = 0, 6 do
    for col = 0, 19 do
      blitTile(shade, logoTiles[row * 20 + col + 1], col * 8, (row + 3) * 8)
    end
  end
  -- Copyright line: 13 tiles from d=$c on the window's row 0, shown at
  -- hWY = $88 (engine/movie/title.asm:114-119; engine/menus/intro_menu.asm:1121-1122).
  for index = 0, 12 do
    blitTile(shade, logoTiles[128 + 12 + index + 1], (3 + index) * 8, 17 * 8)
  end

  local colored = colorize(shade, function(x, y)
    return pals.bg[bgPalAt(math.floor(x / 8), math.floor(y / 8)) + 1]
  end)
  self:save(colored, "title/crystal_screen.png")
  self:save(shade, "title/crystal_screen_gray.png")

  local logo = ImageWriter.blank(160, 56, 0, 0, 0, 0)
  ImageWriter.blit(logo, colored, 0, 0, 0, 24, 160, 56)
  self:save(logo, "title/crystal_logo.png")
  local wordmark = ImageWriter.blank(88, 8, 0, 0, 0, 0)
  ImageWriter.blit(wordmark, colored, 0, 0, 40, 72, 88, 8)
  self:save(wordmark, "title/crystal_wordmark.png")
  self:tick("Title screen", 2, 5)

  -- LoadSuicuneFrame: 6 rows of 8 tiles at hlcoord 6,12, row stride 16;
  -- frame bases $80/$88/$00/$08 (engine/movie/title.asm:245-273).
  local suicunePaths, suicuneGrayPaths = {}, {}
  for index, base in ipairs({ 0x00, 0x08, 0x80, 0x88 }) do
    local frame = ImageWriter.blank(64, 48, 0, 0, 0, 0)
    for row = 0, 5 do
      for col = 0, 7 do
        blitTile(frame, suicuneTiles[base + row * 16 + col + 1],
          col * 8, row * 8)
      end
    end
    local tinted = colorize(frame, function() return pals.bg[1] end)
    local rel = ("title/crystal_suicune_%d.png"):format(index)
    self:save(tinted, rel)
    suicunePaths[index] = "assets/generated/" .. rel
    local grayRel = ("title/crystal_suicune_%d_gray.png"):format(index)
    self:save(frame, grayRel)
    suicuneGrayPaths[index] = "assets/generated/" .. grayRel
    if index == 1 then self:save(tinted, "title/crystal_suicune.png") end
  end
  self:tick("Title screen", 3, 5)

  -- InitializeBackground: five 48x16 strips of six 8x16 OBJs, consecutive
  -- tile pairs, OBJ pal 0, OAM_PRIO (engine/movie/title.asm:304-338).
  local gem = ImageWriter.blank(48, 80, 0, 0, 0, 0)
  for strip = 0, 4 do
    for slot = 0, 5 do
      local tile = strip * 12 + slot * 2
      blitTile(gem, gemTiles[tile + 1], slot * 8, strip * 16)
      blitTile(gem, gemTiles[tile + 2], slot * 8, strip * 16 + 8)
    end
  end
  local gemTinted = colorize(gem, function() return pals.obj[1] end)
  self:save(gemTinted, "title/crystal_gem.png")
  self:save(gem, "title/crystal_gem_gray.png")
  extractCopyright(self)
  self:tick("Title screen", 4, 5)

  local function unit(color) return { color[1] / 255, color[2] / 255, color[3] / 255 } end

  local data = {
    generation = 2,
    layout = "crystal_title",
    source = "ROM:TitleSuicuneGFX + TitleLogoGFX + TitleCrystalGFX"
      .. " + TitleScreenPalettes + CopyrightGFX",
    screen = "assets/generated/title/crystal_screen.png",
    screenGray = "assets/generated/title/crystal_screen_gray.png",
    image = "assets/generated/title/crystal_logo.png",
    wordmark = "assets/generated/title/crystal_wordmark.png",
    suicune = "assets/generated/title/crystal_suicune.png",
    suicuneFrames = suicunePaths,
    suicuneFramesGray = suicuneGrayPaths,
    -- hlcoord 6, 12 (engine/movie/title.asm:252) in screen pixels.
    suicuneX = 48,
    suicuneY = 96,
    -- SuicuneFrameIterator advances every 8 frames (engine/movie/title.asm:217-243).
    suicuneEvery = 8,
    gem = "assets/generated/title/crystal_gem.png",
    gemGray = "assets/generated/title/crystal_gem_gray.png",
    copyright = "assets/generated/title/copyright.png",
    copyrightSplash = "assets/generated/title/copyright_splash.png",
    copyrightBackdrop = unit(COPYRIGHT_BG[1]),
    copyrightInk = unit(COPYRIGHT_BG[4]),
    -- Strip 0 starts at OAM (64, -$22) and stops at OAM y 22, i.e. screen
    -- (56, 6) (engine/movie/title.asm:306-311,340-362).
    gemX = 56,
    gemY = 6,
    gemFromY = -50,
    gemStep = 2,
    -- TitleScreenEntrance: hSCX from +112 to 0 by 4 with alternating-line
    -- signage over the logo's 80 lines; the copyright window sits at
    -- hWY = $88 only after it lands (engine/menus/intro_menu.asm:1078-1111).
    entrance = { scx = 112, step = 4, lines = 80, hideBelow = 136 },
    entranceSfx = "Sfx_TitleScreenEntrance",
    -- TitleScreenTimer (engine/menus/intro_menu.asm:1125-1136).
    timeoutFrames = 73 * 60 + 36,
    sky = unit(pals.bg[1][1]),
    below = unit(pals.bg[1][1]),
    palettes = { bg = pals.bg, obj = pals.obj },
  }
  self:write("title", data)
  self:tick("Title screen", 5, 5)
  return data
end

return CrystalMovie
