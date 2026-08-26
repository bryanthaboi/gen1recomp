-- Crystal's Kris battle/Hall-of-Fame art and the Mobile System GB sheets.
--   luajit tests/gen2_crystal_mobile_gfx_test.lua
--
-- Two imports that had no consumer at the time they landed, so nothing else
-- would notice them rotting: Kris's backpic and KRIS trainer-class pic (wave A
-- shipped the female protagonist but battles and the Hall of Fame still drew
-- Chris), and the whole gfx/mobile + gfx/mystery_gift set, imported ahead of
-- the phase that uses it so Crystal never has to re-import for it.
--
-- What is held down: the stage exists and run() calls it, it is gated on the
-- crystal edition so Gold and Silver emit nothing, every label it reads is in
-- the generated Crystal manifest at the address pokecrystal.sym gives, and the
-- blobs it wrote are ../pokecrystal/gfx/mobile byte for byte.
--
-- ROM-free.  The decomp half SKIPs with no ../pokecrystal beside the repo, the
-- cache half with no Crystal cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 crystal mobile gfx")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

-- ------------------------------------------------------- the stage itself

local extractorSource = assert(readFile("src/import/RomExtractorGen2.lua"))
local RomExtractorGen2 = require("src.import.RomExtractorGen2")

check(type(RomExtractorGen2.extractMobileGfx) == "function",
  "RomExtractorGen2:extractMobileGfx exists")
check(extractorSource:find("results.mobileGfx = self:extractMobileGfx()",
  1, true) ~= nil, "and RomExtractorGen2:run calls it")
check(extractorSource:find(
  'if self.edition ~= "crystal" then return nil end', 1, true) ~= nil,
  "gated on the edition, so Gold and Silver write no mobile art")
-- The two suites that pin the progress bar read this same literal; a new
-- stage must not move it (tests/gen2_diploma_test.lua:45).
check(extractorSource:find("local STAGE_COUNT = 27", 1, true) ~= nil,
  "and it did not disturb STAGE_COUNT")

-- ------------------------------------------------------------ the symbols

-- ../pokecrystal-symbols/pokecrystal.sym, international v1.0.  Every one of
-- these resolves in that build: the Japanese-only part of Mobile System GB is
-- the text and the menu entries that reach it, not the art.
local SYMBOLS = {
  AsciiFontGFX = { 0x5c, 0x5db1 },
  PichuAnimatedMobileGFX = { 0x5c, 0x4d16 },
  ElectroBallMobileGFX = { 0x5c, 0x55a4 },
  PichuBorderMobileGFX = { 0x5c, 0x5848 },
  Stadium2N64GFX = { 0x5c, 0x6f1f },
  Stadium2N64Tilemap = { 0x5c, 0x73af },
  Stadium2N64Attrmap = { 0x5c, 0x7517 },
  PasswordTopTilemap = { 0x5c, 0x6491 },
  PasswordBottomTilemap = { 0x5c, 0x651d },
  PasswordShiftTilemap = { 0x5c, 0x65f9 },
  ChooseMobileCenterTilemap = { 0x5c, 0x6685 },
  MobilePasswordAttrmap = { 0x5c, 0x67ed },
  ChooseMobileCenterAttrmap = { 0x5c, 0x6955 },
  MobilePasswordPalettes = { 0x5c, 0x5d71 },
  MobileCardGFX = { 0x5e, 0x59ef },
  ChrisSilhouetteGFX = { 0x5e, 0x5bef },
  KrisSilhouetteGFX = { 0x5e, 0x5e1f },
  MobileCard2GFX = { 0x5e, 0x604f },
  CardLargeSpriteAndFolderGFX = { 0x5e, 0x61bf },
  CardSpriteGFX = { 0x5e, 0x664f },
  DialpadTilemap = { 0x5e, 0x6cd5 },
  DialpadAttrmap = { 0x5e, 0x6e3d },
  DialpadGFX = { 0x5e, 0x6fa5 },
  DialpadCursorGFX = { 0x5e, 0x7465 },
  MobileCardListGFX = { 0x5e, 0x74b9 },
  HaveWantGFX = { 0x5f, 0x4083 },
  MobileSelectGFX = { 0x5f, 0x4983 },
  HaveWantMap = { 0x5f, 0x4b83 },
  PokemonNewsGFX = { 0x5f, 0x66fe },
  PokemonNewsTileAttrmap = { 0x5f, 0x6b8e },
  PokemonNewsPalettes = { 0x5f, 0x6ff6 },
  ["MobileSystemSplashScreen_InitGFX.Tiles"] = { 0x5b, 0x4173 },
  ["MobileSystemSplashScreen_InitGFX.Tilemap"] = { 0x5b, 0x4633 },
  ["MobileSystemSplashScreen_InitGFX.Attrmap"] = { 0x5b, 0x479b },
  MobileSplashScreenPalettes = { 0x5b, 0x4903 },
  MobileAdapterCheckGFX = { 0x5b, 0x4ca3 },
  MobileTradeSpritesGFX = { 0x42, 0x4d27 },
  MobileTradeGFX = { 0x42, 0x4da7 },
  MobileTradeTilemapLZ = { 0x42, 0x4fe7 },
  MobileTradeAttrmapLZ = { 0x42, 0x50a7 },
  MobileCable1GFX = { 0x42, 0x51c7 },
  MobileCable2GFX = { 0x42, 0x52c7 },
  UnusedMobilePulsePalettes = { 0x42, 0x50f7 },
  MobileTradeBGPalettes = { 0x42, 0x5107 },
  MobileTradeOB1Palettes = { 0x42, 0x5147 },
  MobileTradeOB2Palettes = { 0x42, 0x5187 },
  MobileAdapterPalettes = { 0x42, 0x53c7 },
  MobileTradeLightsGFX = { 0x40, 0x72a2 },
  MobileTradeLightsPalettes = { 0x40, 0x72e2 },
  PichuBorderMobileOBPalettes = { 0x45, 0x730e },
  PichuBorderMobileBGPalettes = { 0x45, 0x734e },
  PichuBorderMobileTilemapAttrmap = { 0x45, 0x7356 },
  MobileDialingGFX = { 0x45, 0x601a },
  MobileUpArrowGFX = { 0x12, 0x48c3 },
  MobileDownArrowGFX = { 0x12, 0x48cb },
  EZChatCursorGFX = { 0x22, 0x540b },
  MobileDialingFrameGFX = { 0x41, 0x6514 },
  SelectStartGFX = { 0x47, 0x567e },
  MobileMenuGFX = { 0x12, 0x5c0c },
  MobilePhoneTilesGFX = { 0x3e, 0x5234 },
  MysteryGiftGFX = { 0x41, 0x5258 },
  CardTradeGFX = { 0x41, 0x5930 },
  CardTradeSpriteGFX = { 0x41, 0x5d30 },
}

-- Kris's own two pics.  KrisBackpic needs no delta row: embedded_symbols in
-- make_gold_manifest.py adds every unqualified *Backpic label on sight.
local KRIS_SYMBOLS = {
  KrisBackpic = { 0x22, 0x4ed6 },
  KrisPic = { 0x22, 0x4bb9 },
  ChrisPic = { 0x22, 0x48a9 },
}

do
  local deltas = assert(readFile("tools/crystal_symbol_deltas.py"))
  for label in pairs(SYMBOLS) do
    check(deltas:find('"' .. label .. '"', 1, true) ~= nil,
      label .. " is in crystal_symbol_deltas.MOBILE_SYMBOLS")
  end
end

local Json = require("src.link.Json")
local function manifestSymbols(path)
  local body = readFile(path)
  if not body then return nil end
  return (Json.decode(body) or {}).symbols or {}
end

do
  local symbols = manifestSymbols("tools/rom_manifest_crystal.json")
  if not symbols then
    check(true, "no tools/rom_manifest_crystal.json (SKIP)")
  else
    local wrong = {}
    for label, at in pairs(SYMBOLS) do
      local got = symbols[label]
      if not got or got[1] ~= at[1] or got[2] ~= at[2] then
        wrong[#wrong + 1] = label
      end
    end
    check(#wrong == 0, #wrong == 0
      and "the Crystal manifest carries all 63 mobile symbols where "
        .. "pokecrystal.sym puts them"
      or ("mobile symbols missing or misplaced: " .. table.concat(wrong, ", ")))
    for label, at in pairs(KRIS_SYMBOLS) do
      local got = symbols[label]
      if not got then
        check(false, "the Crystal manifest carries " .. label)
      else
        eq(got[1], at[1], label .. " is in the bank pokecrystal.sym says")
        eq(got[2], at[2], label .. " is at the address it says")
      end
    end
  end
end

do
  -- Gold has no mobile banks; a delta that leaked into the shared set would
  -- break the Gold import rather than show up here as a missing sheet.
  local symbols = manifestSymbols("tools/rom_manifest_gold.json")
  if not symbols then
    check(true, "no tools/rom_manifest_gold.json (SKIP)")
  else
    local leaked = {}
    for label in pairs(SYMBOLS) do
      if symbols[label] then leaked[#leaked + 1] = label end
    end
    check(#leaked == 0, #leaked == 0
      and "and the Gold manifest carries none of them"
      or ("mobile symbols leaked into Gold: " .. table.concat(leaked, ", ")))
    check(symbols.KrisBackpic == nil, "nor Gold's non-existent KrisBackpic")
  end
end

-- --------------------------------------------------------------- the cache

local cache = os.getenv("CRYSTAL_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/crystal-dev/crystal"
end

local GameVersion = require("src.core.GameVersion")
local CacheContract = require("src.import.CacheContract")

local function crystalCacheRevision()
  local fs = { prefix = "", read = function(rel) return readFile(cache .. "/" .. rel) end }
  local marker = CacheContract.readMarker("crystal", fs)
  if not marker then return "1.0" end
  for _, revision in ipairs(GameVersion.revisions("crystal")) do
    if marker == CacheContract.markerFor("crystal", revision.sha1) then
      return revision.label or "1.0"
    end
  end
  return "1.0"
end

local function loadCache(rel)
  local chunk = loadfile(cache .. "/data/generated/" .. rel .. ".lua")
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  return ok and value or nil
end

-- PNG IHDR: width and height are big-endian at bytes 17 and 21.
local function pngSize(relative)
  local png = readFile(cache .. "/" .. relative)
  if not png then return nil end
  local function be32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return be32(png, 17), be32(png, 21)
end

-- ../pokecrystal/gfx/player/kris_back.png is 48x48 and kris.png 56x56, the
-- same six and seven tiles square Chris uses.
local BACK_PIC_PX = 48
local TRAINER_PIC_PX = 56

-- Kris's art and the mobile sheets ride one import, so mobile_gfx.lua doubles
-- as the marker for both: a cache built before this unit has neither, and the
-- whole cache half stands down rather than failing on an old sandbox.
local mobile = loadCache("mobile_gfx")
local menuGfx = mobile and loadCache("menu_gfx") or nil
if not menuGfx then
  check(true, "no Crystal cache with mobile_gfx.lua at " .. cache
    .. " : re-import for gfx/mobile (SKIP)")
else
  local hud = menuGfx.battleHud or {}
  eq(hud.playerBackFemale, "assets/generated/battle/player_back_female.png",
    "menu_gfx points battles and the Hall of Fame at Kris's backpic")
  local w, h = pngSize("assets/generated/battle/player_back_female.png")
  eq(w, BACK_PIC_PX, "GetKrisBackpic's pic is 48px wide")
  eq(h, BACK_PIC_PX, "and 48 tall, not the 7*7 tiles of VRAM it asks for")
  check(hud.playerBack ~= hud.playerBackFemale,
    "and it is not the same file Chris gets")

  local pics = hud.trainerPics or {}
  eq(pics.KRIS, "assets/generated/battle/trainers/kris.png",
    "HOF_LoadTrainerFrontpic's KRIS class has a pic of its own")
  eq(pics.CHRIS, "assets/generated/battle/trainers/chris.png",
    "as does CHRIS, which TrainerPicPointers has no row for")
  for _, key in ipairs({ "kris", "chris" }) do
    local pw, ph = pngSize("assets/generated/battle/trainers/" .. key .. ".png")
    eq(pw, TRAINER_PIC_PX, key .. ".png is 56px wide")
    eq(ph, TRAINER_PIC_PX, "and 56 tall, like every other trainer pic")
  end
end

local oakSpeech = mobile and loadCache("oak_speech") or nil
if not oakSpeech then
  check(true, "no oak_speech.lua beside a mobile_gfx.lua cache (SKIP)")
else
  eq(oakSpeech.playerPicFemale, "assets/generated/intro/kris.png",
    "and DrawIntroPlayerPic's female arm is named in oak_speech.lua")
end

-- Sheets whose tile count fills the pret PNG's grid exactly once padded, so
-- the cache PNG must come out at the source PNG's own size.  The three left
-- out (mobile_splash, electro_ball, phone_tiles) are built with
-- --remove-duplicates / --remove-whitespace, so the ROM holds fewer tiles than
-- the PNG does and only the tilemap puts them back (../pokecrystal/Makefile:
-- 343,344,348).
local SHEETS = {
  { "asciiFont", "mobile/ascii_font.png", 110, 16, "gfx/mobile/ascii_font.png" },
  { "card", "mobile/card.png", 32, 16, "gfx/mobile/card.png" },
  { "card2", "mobile/card_2.png", 23, 12, "gfx/mobile/card_2.png" },
  { "cardLargeSprite", "mobile/card_large_sprite.png", 8, 4,
    "gfx/mobile/card_large_sprite.png" },
  { "cardFolder", "mobile/card_folder.png", 65, 6,
    "gfx/mobile/card_folder.png" },
  { "cardList", "mobile/card_list.png", 24, 12, "gfx/mobile/card_list.png" },
  { "cardSprite", "mobile/card_sprite.png", 4, 2, "gfx/mobile/card_sprite.png" },
  { "chrisSilhouette", "mobile/chris_silhouette.png", 35, 5,
    "gfx/mobile/chris_silhouette.png" },
  { "krisSilhouette", "mobile/kris_silhouette.png", 35, 5,
    "gfx/mobile/kris_silhouette.png" },
  { "dialing", "mobile/dialing.png", 20, 2, "gfx/mobile/dialing.png" },
  { "dialingFrame", "mobile/dialing_frame.png", 8, 2,
    "gfx/mobile/dialing_frame.png" },
  { "dialpad", "mobile/dialpad.png", 76, 16, "gfx/mobile/dialpad.png" },
  { "dialpadCursor", "mobile/dialpad_cursor.png", 5, 2,
    "gfx/mobile/dialpad_cursor.png" },
  { "ezChatCursor", "mobile/ez_chat_cursor.png", 2, 1,
    "gfx/mobile/ez_chat_cursor.png" },
  { "haveWant", "mobile/havewant.png", 144, 16, "gfx/mobile/havewant.png" },
  { "select", "mobile/select.png", 32, 4, "gfx/mobile/select.png" },
  { "selectStart", "mobile/select_start.png", 6, 3,
    "gfx/mobile/select_start.png" },
  { "cable1", "mobile/mobile_cable_1.png", 16, 4,
    "gfx/mobile/mobile_cable_1.png" },
  { "cable2", "mobile/mobile_cable_2.png", 16, 4,
    "gfx/mobile/mobile_cable_2.png" },
  { "menu", "mobile/mobile_menu.png", 13, 13, "gfx/mobile/mobile_menu.png" },
  { "adapterCheck", "mobile/mobile_splash_check.png", 48, 16,
    "gfx/mobile/mobile_splash_check.png" },
  { "tradeLights", "mobile/mobile_trade_lights.png", 4, 2,
    "gfx/mobile/mobile_trade_lights.png" },
  { "pichuBorder", "mobile/pichu_border.png", 24, 4,
    "gfx/mobile/pichu_border.png" },
  { "pokemonNews", "mobile/pokemon_news.png", 72, 8,
    "gfx/mobile/pokemon_news.png" },
  { "stadium2N64", "mobile/stadium2_n64.png", 73, 11,
    "gfx/mobile/stadium2_n64.png" },
  { "pichuAnimated", "mobile/pichu_animated.png", 193, 16,
    "gfx/mobile/pichu_animated.png" },
  { "trade", "mobile/mobile_trade.png", 128, 8, "gfx/mobile/mobile_trade.png" },
  { "tradeSprites", "mobile/mobile_trade_sprites.png", 16, 4,
    "gfx/mobile/mobile_trade_sprites.png" },
  { "upArrow", "mobile/up_arrow.png", 1, 1, "gfx/mobile/up_arrow.png" },
  { "downArrow", "mobile/down_arrow.png", 1, 1, "gfx/mobile/down_arrow.png" },
  { "mysteryGift", "mobile/mystery_gift/mystery_gift.png", 67, 16,
    "gfx/mystery_gift/mystery_gift.png" },
  { "cardTrade", "mobile/mystery_gift/card_trade.png", 64, 16,
    "gfx/mystery_gift/card_trade.png" },
  { "cardTradeSprite", "mobile/mystery_gift/card_sprite.png", 8, 4,
    "gfx/mystery_gift/card_sprite.png" },
}

-- The three the dedupe passes shrink: only the declared tile count is checked.
local DEDUPED = {
  { "splash", "mobile/mobile_splash.png", 76, 14 },
  { "electroBall", "mobile/electro_ball.png", 83, 16 },
  { "phoneTiles", "mobile/phone_tiles.png", 17, 2 },
}

-- key, cache file, byte length, ../pokecrystal source it must equal.
local MAPS = {
  { "passwordTop", "password_top", 140, "gfx/mobile/password_top.tilemap" },
  { "passwordBottom", "password_bottom", 220,
    "gfx/mobile/password_bottom.tilemap" },
  { "passwordShift", "password_shift", 140,
    "gfx/mobile/password_shift.tilemap" },
  { "passwordAttrmap", "password_attrmap", 360,
    "gfx/mobile/password.attrmap" },
  { "centerTilemap", "mobile_center_tilemap", 360,
    "gfx/mobile/mobile_center.tilemap" },
  { "centerAttrmap", "mobile_center_attrmap", 360,
    "gfx/mobile/mobile_center.attrmap" },
  { "stadium2N64Tilemap", "stadium2_n64_tilemap", 360,
    "revision" },
  { "stadium2N64Attrmap", "stadium2_n64_attrmap", 360,
    "gfx/mobile/stadium2_n64.attrmap" },
  { "dialpadTilemap", "dialpad_tilemap", 360, "gfx/mobile/dialpad.tilemap" },
  { "dialpadAttrmap", "dialpad_attrmap", 360, "gfx/mobile/dialpad.attrmap" },
  { "haveWantMap", "havewant_map", 1136, "gfx/mobile/havewant_map.bin" },
  { "newsAttrmap", "pokemon_news_attrmap", 1128,
    "gfx/mobile/pokemon_news.bin" },
  { "splashTilemap", "mobile_splash_tilemap", 360,
    "gfx/mobile/mobile_splash.tilemap" },
  { "splashAttrmap", "mobile_splash_attrmap", 360,
    "gfx/mobile/mobile_splash.attrmap" },
  { "pichuBorderTilemap", "pichu_border_tilemap", 384,
    "gfx/mobile/pichu_border.tilemap" },
  { "pichuBorderAttrmap", "pichu_border_attrmap", 384,
    "gfx/mobile/pichu_border.attrmap" },
  { "tradeTilemap", "mobile_trade_tilemap", 1024,
    "gfx/mobile/mobile_trade.tilemap" },
  { "tradeAttrmap", "mobile_trade_attrmap", 1024,
    "gfx/mobile/mobile_trade.attrmap" },
}

local PALETTE_COLORS = {
  splash = 32, password = 32, pokemonNews = 32, pichuBorderOB = 32,
  pichuBorderBG = 4, tradeBG = 32, tradeOB1 = 32, tradeOB2 = 32,
  tradeLights = 16, adapters = 8, unusedPulses = 8,
}

local pokecrystal = "../pokecrystal"
local havePret = readFile(pokecrystal .. "/gfx/mobile/ascii_font.2bpp") ~= nil

if not mobile then
  check(true, "no mobile_gfx.lua in the Crystal cache (SKIP)")
else
  eq(mobile.generation, 2, "mobile_gfx.lua is a Gen 2 table")
  local sheets = mobile.sheets or {}
  local maps = mobile.maps or {}
  local palettes = mobile.palettes or {}

  local function checkSheet(row, pretPng)
    local key, rel, tiles, wide = row[1], row[2], row[3], row[4]
    local entry = sheets[key]
    if type(entry) ~= "table" then
      check(false, "mobile_gfx carries the " .. key .. " sheet")
      return
    end
    eq(entry.tiles, tiles, key .. " is the tile count the ROM block holds")
    eq(entry.tilesWide, wide, "and is written " .. wide .. " tiles across")
    eq(entry.path, "assets/generated/" .. rel, "at the path it advertises")
    local w, h = pngSize("assets/generated/" .. rel)
    eq(w, wide * 8, key .. ".png is " .. (wide * 8) .. "px wide")
    eq(h, math.ceil(tiles / wide) * 8, "and tall enough for every tile")
    if pretPng and havePret then
      local png = readFile(pokecrystal .. "/" .. pretPng)
      if png then
        local function be32(s, i)
          local a, b, c, d = s:byte(i, i + 3)
          return ((a * 256 + b) * 256 + c) * 256 + d
        end
        eq(w, be32(png, 17), "which is " .. pretPng .. "'s own width")
        eq(h, be32(png, 21), "and its own height")
      end
    end
  end

  for _, row in ipairs(SHEETS) do checkSheet(row, row[5]) end
  for _, row in ipairs(DEDUPED) do checkSheet(row, nil) end

  for _, row in ipairs(MAPS) do
    local key, file, bytes, source = row[1], row[2], row[3], row[4]
    local revisionLabel
    if key == "stadium2N64Tilemap" then
      -- ../pokecrystal/mobile/mobile_5c.asm:869
      revisionLabel = crystalCacheRevision()
      source = revisionLabel == "1.1"
        and "gfx/mobile/stadium2_n64_corrupt.tilemap"
        or "gfx/mobile/stadium2_n64.tilemap"
    end
    local entry = maps[key]
    local rel = "assets/generated/mobile/" .. file .. ".bin"
    if type(entry) ~= "table" then
      check(false, "mobile_gfx carries the " .. key .. " map")
    else
      eq(entry.bytes, bytes, key .. " is " .. bytes .. " bytes")
      eq(entry.path, rel, "at the path it advertises")
      local blob = readFile(cache .. "/" .. rel)
      if not blob then
        check(false, rel .. " was written")
      else
        eq(#blob, bytes, "and the file on disk is that long")
        local want = havePret and readFile(pokecrystal .. "/" .. source) or nil
        if not want then
          check(true, "no ../pokecrystal: " .. source .. " not diffed (SKIP)")
        else
          check(blob == want:sub(1, bytes),
            "it is ../pokecrystal/" .. source .. " byte for byte"
              .. (revisionLabel
                and (" (cache built from Crystal " .. revisionLabel .. ")")
                or ""))
        end
      end
    end
  end

  for key, colors in pairs(PALETTE_COLORS) do
    local pal = palettes[key]
    if type(pal) ~= "table" then
      check(false, "mobile_gfx carries the " .. key .. " palette block")
    else
      eq(#pal, colors, key .. " is " .. colors .. " RGB words")
      eq(#(pal[1] or {}), 3, "each one decoded to an r,g,b triple")
    end
  end
end

-- A Gold cache must have gone nowhere near any of this.
local goldCache = os.getenv("GOLD_CACHE")
if not goldCache then
  local home = os.getenv("HOME") or ""
  goldCache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
if not loadfile(goldCache .. "/data/generated/menu_gfx.lua") then
  check(true, "no Gold cache at " .. goldCache .. " (SKIP)")
else
  check(loadfile(goldCache .. "/data/generated/mobile_gfx.lua") == nil,
    "a Gold cache has no mobile_gfx.lua")
  local chunk = loadfile(goldCache .. "/data/generated/menu_gfx.lua")
  local ok, gold = pcall(chunk)
  local hud = (ok and gold or {}).battleHud or {}
  check(hud.playerBackFemale == nil, "and no Kris backpic")
  check((hud.trainerPics or {}).KRIS == nil, "and no KRIS trainer pic")
end

S.finish()
