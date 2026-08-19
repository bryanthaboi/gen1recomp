-- Gold Gen 2 extractor: pret/pokegold's ROM layout, parallel to
-- src/import/RomExtractor.lua (Gen 1) but never branched into it -- the two
-- generations disagree on almost everything below the constants layer
-- (species order IS dex order, pics/tilesets are lz3-compressed rather than
-- pkmncompress'd, maps are grouped instead of flat).  See docs/gold-phase1.md.
local bit = require("bit")
local ImageWriter = require("src.import.ImageWriter")
local LuaWriter = require("src.import.LuaWriter")
local Rom = require("src.import.Rom")

-- engine/gfx/load_pics.asm FixPicBank.  `dba_pic` does NOT store the real
-- bank for the three "Pics" sections that live above the 8-bit-friendly range:
-- it writes $13, $14 or $1f and the loader maps them back on the way out.
-- A reader that trusts the stored byte lands in the wrong bank entirely, which
-- is why nine of the Unown letters decoded as noise and the rest as nothing.
local FIX_PIC_BANK = {
  [0x13] = 0x1f, -- BANK("Pics 12")
  [0x14] = 0x20, -- BANK("Pics 13")
  [0x1f] = 0x2e, -- BANK("Pics 14")
}

local RomExtractorGen2 = {}
RomExtractorGen2.__index = RomExtractorGen2

-- constants, font, palettes, tilesets, maps, sprites, scripts+text, std
-- scripts, pokemon, moves, items, marts, encounters, trainers, pokedex,
-- landmarks, intro movie, menu gfx, title, credits, diploma, trade animation,
-- audio, stubs
local STAGE_COUNT = 26
local Opcodes = require("src.script.gen2.Opcodes")

-- BG palette slots inside one loaded 8-palette set (constants/tileset_constants.asm
-- PAL_BG_*); PAL_BG_ROOF is the one LoadMapPals overrides per map group.
local PAL_BG_NAMES = {
  "GRAY", "RED", "GREEN", "WATER", "YELLOW", "BROWN", "ROOF", "TEXT",
}
local PAL_BG_ROOF = 6 -- 0-based slot index
-- Time-of-day palette sets, in wTimeOfDayPal order (MORN_F..DARKNESS_F).
local DAYTIMES = { "MORN", "DAY", "NITE", "DARK" }
-- gfx/tilesets/bg_tiles.pal: morn/day/nite/dark/indoor (8 each) plus the two
-- overworld-water palettes at $28-$29 -- "Valid indices: $00 - $29".
local BG_PALETTE_COUNT = 0x2a
-- gfx/overworld/npc_sprites.pal is PAL_OW_* x NUM_DAYTIMES.
local OW_PALETTE_COUNT = 8
-- data/maps/environment_colors.asm rows are 8 indices per daytime.
local ENV_POINTER_COUNT = 8 -- NUM_ENVIRONMENTS + 1 (row 0 is unused)
local MAP_GROUP_COUNT = 26 -- constants/map_constants.asm NUM_MAP_GROUPS
-- gfx/tileset_palette_maps.asm lives in "bank2" (main.asm) alongside
-- EnvironmentColorsPointers, and the Tilesets row only stores a 16-bit
-- pointer, so the bank has to come from here.
local PAL_MAP_BANK = 0x02
-- LoadBallIconGFX.gfx (engine/battle/trainer_huds.asm:225-232); bank $0b
-- carries no manifest symbol to resolve it through.
local BALL_ICON_GFX = { 0x0b, 0x41a4 }
-- A tileset sheet is 96 tiles (128x48 at 8x8), and its PalMap packs two
-- tiles per byte: low nibble first tile, high nibble second (`dn` in the
-- tilepal macro).  The high bit of each nibble is the VRAM bank, not colour.
local TILESET_TILE_COUNT = 96
-- Every Gen 2 back pic is 6x6 tiles (48x48); only front pics vary in size.
local BACK_PIC_TILES = 6

-- Gen 2 tilesets always ship 128 metatiles (16 tile ids each) and 128
-- collision quads (4 COLL_* bytes each) -- see gfx/tilesets/*_metatiles.bin.
local METATILE_COUNT = 128
local MAP_LENGTH = 9
local ATTR_LENGTH = 12
local CONNECTION_LENGTH = 12
local WARP_LENGTH = 5
local COORD_LENGTH = 8
local BG_LENGTH = 5
local OBJECT_LENGTH = 13
-- constants/script_constants.asm OBJECTTYPE_*: the object_event function byte
-- that says whether its pointer is bytecode, a `trainer` struct, or an item.
local OBJECTTYPE_ITEMBALL, OBJECTTYPE_TRAINER = 1, 2
-- constants/script_constants.asm BGEVENT_*: the bg_event function byte does the
-- same job for a sign's pointer.  BGEVENT_ITEM is a HIDDEN ITEM and its operand
-- aims at `hiddenitem item, flag` (macros/scripts/maps.asm), not at bytecode --
-- 87 of them, and disassembling those three bytes as commands is where most of
-- the port's unknown-opcode rows came from.
local BGEVENT_ITEM = 7
-- constants/map_setup_constants.asm.  `def_callbacks` asserts one callback per
-- type at most, so a count above this is a misread header rather than data.
local NUM_MAPCALLBACK_TYPES = 5
-- constants/script_constants.asm: the cmdqueue entry a `writecmdqueue` names
-- (dbw type, addr + dw filler) and the stonetable row it points at
-- (db warp, object + dw script), a `db -1` ending the list.
local CMDQUEUE_ENTRY_SIZE = 6
local CMDQUEUE_STONETABLE = 2
local STONETABLE_LENGTH = 4
-- MenuHeader (ram/wram.asm wMenuHeader): db flags; menu_coords lays the
-- corners down y-first (macros/coords.asm `db \2, \1` twice); dw the data
-- pointer; db the default cursor position.
local MENU_HEADER_LENGTH = 8
-- constants/npc_trade_constants.asm.  The rsreset block ends on an `rb_skip`
-- padding byte, so the stride is 32 rather than the 31 the fields add up to --
-- the same "read the rsreset, not the macro" rule TrainerClassAttributes'
-- seven bytes came from.  `dname` pads with '@', so each name field carries
-- its own terminator inside its 11 bytes.
local NPCTRADE_STRUCT_LENGTH = 32
local MON_NAME_LENGTH, NAME_LENGTH = 11, 11
local NUM_NPC_TRADES = 6
-- constants/script_constants.asm NUM_BUG_CONTESTANTS, "not counting the
-- player", which data/events/bug_contest_flags.asm asserts its length against.
local NUM_BUG_CONTESTANTS = 10
-- constants/phone_constants.asm PHONE_CONTACT_SIZE and SPECIALCALL_SIZE.
local PHONE_CONTACT_SIZE = 12
local SPECIALCALL_SIZE = 6

-- The WRAM string buffers a `text_ram` can name (ram/wram.asm, addresses from
-- pokegold.sym).  Every one of them decodes to the same `{STRBUF}` marker --
-- this port has one shared buffer -- so the names are only recorded where a
-- caller asks, to tell two markers in one line apart.
local TEXT_BUFFERS = {
  [0xcf48] = "wMonOrItemNameBuffer",
  [0xcf6b] = "wStringBuffer1",
  [0xcf7e] = "wStringBuffer2",
  [0xcf91] = "wStringBuffer3",
  [0xcfa4] = "wStringBuffer4",
  [0xcfb7] = "wStringBuffer5",
  -- The trade animation names the two trademon records instead
  -- (data/text/common_1.asm _MonWasSentToText and the rest), and the four it
  -- reaches for are the only way to tell "MACHOP was sent to MIKE" from the
  -- line with the two names the other way round.
  [0xc5d1] = "wPlayerTrademonSpeciesName",
  [0xc5e7] = "wPlayerTrademonSenderName",
  [0xc602] = "wOTTrademonSpeciesName",
  [0xc618] = "wOTTrademonSenderName",
}
-- The text commands that print nothing and carry no argument
-- (macros/scripts/text.asm, in TextCommands order): TX_LOW, TX_SCROLL,
-- TX_PAUSE, TX_WAIT_BUTTON, TX_DAY, and the six TX_SOUND_* jingles.
local TEXT_NO_GLYPH = {
  [0x05] = true, [0x07] = true, [0x0a] = true, [0x0b] = true, [0x0d] = true,
  [0x0e] = true, [0x0f] = true, [0x10] = true, [0x11] = true, [0x12] = true,
  [0x13] = true, [0x15] = true,
}

local ROOF_TILES = 9
local SPRITEDATA_LENGTH = 6

-- data/sprites/sprites.asm overworld_sprite type / palette bytes.
local WALKING_SPRITE, STANDING_SPRITE, STILL_SPRITE = 1, 2, 3
local SPRITE_TYPE_NAME = {
  [WALKING_SPRITE] = "WALKING_SPRITE",
  [STANDING_SPRITE] = "STANDING_SPRITE",
  [STILL_SPRITE] = "STILL_SPRITE",
}
local SPRITE_PALETTE_NAME = {
  [0] = "PAL_OW_RED", [1] = "PAL_OW_BLUE", [2] = "PAL_OW_GREEN",
  [3] = "PAL_OW_BROWN", [4] = "PAL_OW_PINK", [5] = "PAL_OW_EMOTE",
  [6] = "PAL_OW_TREE", [7] = "PAL_OW_ROCK",
}

-- Connection flag bits (constants/map_data_constants.asm shift_const order).
local CONN_EAST, CONN_WEST, CONN_SOUTH, CONN_NORTH = 0x01, 0x02, 0x04, 0x08

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[copy(key)] = copy(item) end
  return result
end

function RomExtractorGen2.new(romData, manifest, progress)
  return setmetatable({
    rom = Rom.new(romData),
    manifest = manifest,
    symbols = manifest.symbols,
    progress = progress,
    stage = 0,
  }, RomExtractorGen2)
end

function RomExtractorGen2:symbol(name)
  local location = self.symbols[name]
  if not location then error("required symbol is missing: " .. tostring(name)) end
  return { bank = location[1], address = location[2], name = name }
end

-- A headless import shows nothing but a spinner, so a stage that dies takes
-- its own name down with it.  POKEPORT_IMPORT_TRACE=1 prints each stage as it
-- starts, which is what turns "the import hung" into "the import hung in
-- Pokemon".
local TRACE = os.getenv("POKEPORT_IMPORT_TRACE") == "1"

function RomExtractorGen2:beginStage(name)
  self.stage = self.stage + 1
  if TRACE then
    io.write(("[gold import] %d/%d %s\n"):format(self.stage, STAGE_COUNT, name))
    io.flush()
  end
  if self.progress then self.progress(self.stage - 1, STAGE_COUNT, name, 0, 1) end
end

-- Sub-stage trace: the same POKEPORT_IMPORT_TRACE switch, for the places
-- inside a stage where a bad pointer could send a terminator-driven walk into
-- the weeds.
function RomExtractorGen2:trace(message)
  if not TRACE then return end
  io.write(("[gold import]   %s\n"):format(message))
  io.flush()
end

function RomExtractorGen2:tick(name, current, total)
  if self.progress then
    self.progress(self.stage - 1 + current / total, STAGE_COUNT,
      name, current, total)
  end
end

function RomExtractorGen2:write(name, value)
  LuaWriter.write("data/generated/" .. name .. ".lua", value)
end

function RomExtractorGen2:save(image, relative)
  ImageWriter.save(image, "assets/generated/" .. relative)
end

-- Pics and tileset graphics are lz3-compressed (home/decompress.asm); the
-- terminator ($ff) is what actually ends the stream, so -- same trick as
-- Gen 1's writeCompressedPic -- it is safe to just hand over everything to
-- the end of the bank rather than track an exact compressed length.
function RomExtractorGen2:decompressLz3Symbol(label)
  local symbol = self:symbol(label)
  local compressed = self.rom:bytes(
    symbol.bank, symbol.address, 0x8000 - symbol.address)
  return Rom.decompressLz3(compressed)
end

function RomExtractorGen2:write2bpp(raw, width, height, relative, transparent)
  local image = ImageWriter.decode2bpp(raw, width, height, transparent)
  self:save(image, relative)
end

-- Decompresses a lz3 Pokemon/trainer pic and writes it at its native size
-- (BASE_PIC_SIZE low nibble, tiles wide/tall -- Gen 2 pics are always
-- square).  pret builds these with `rgbgfx --columns`, so the 2bpp stream
-- is column-major; ImageWriter.columnsToRows puts them back into a normal
-- top-to-bottom PNG (same as Gen 1's interleave handling).
function RomExtractorGen2:writeCompressedPic(label, tiles, relative)
  local pixels = self:decompressLz3Symbol(label)
  local size = tiles * 8
  local byteLength = size * size / 4
  while #pixels < byteLength do pixels[#pixels + 1] = 0 end
  while #pixels > byteLength do table.remove(pixels) end
  pixels = ImageWriter.columnsToRows(pixels, tiles, tiles)
  -- pokegold engine/battle/core.asm GetTrainerBackpic: no hardware masking,
  -- so matte the white backdrop like Gen 1's writeCompressedPic does.
  self:save(ImageWriter.matteColor0(
    ImageWriter.decode2bpp(pixels, size, size)), relative)
end

function RomExtractorGen2:extractConstants()
  self:beginStage("Game constants")
  local data = copy(self.manifest.constants)
  data.generation = 2
  self:write("constants", data)
  self:tick("Game constants", 1, 1)
  return data
end

-- GBC colour.  Gen 2 is a CGB-native game: everything on screen is drawn
-- through eight 4-colour BG palettes plus eight OBJ palettes, so unlike Gen 1
-- (where SGB palette *zones* tint a fundamentally 4-shade image) the colours
-- here are not decoration -- a tile's palette is part of its identity.
--
-- engine/gfx/color.asm LoadMapPals is the whole overworld colour pipeline:
--   1. EnvironmentColorsPointers[wEnvironment] -> a table of 4 rows (one per
--      time of day), each 8 bytes.  Each byte is an index into the shared
--      TilesetBGPalette pool, and lands in BG palette slot 0-7.
--   2. MapObjectPals[wTimeOfDayPal] -> the 8 OBJ palettes for OW sprites
--      (each sprite's PAL_OW_* comes from data/sprites/sprites.asm).
--   3. Outdoors only, RoofPals[wMapGroup] overwrites PAL_BG_ROOF colours 1
--      and 2, which is what makes each town's roofs a different colour while
--      sharing one roof tile sheet.
--
-- Colours are stored 0-255 per channel to match Gen 1's palettes.lua, so a
-- reader can hand either generation's table to the same shader.
local function scale5(value) return math.floor(value * 255 / 31 + 0.5) end

-- RGBDS's `percent` macro stores N% as 255*N/100, so $ff is 100% and $e6 is
-- 90%.  Move accuracy and effect chance both go through it; converting back
-- here keeps moves.lua reading like Gen 1's (accuracy 90, not 230).
local function percentOf(raw)
  return math.floor((raw or 0) * 100 / 255 + 0.5)
end

-- ITEMMENU_* (constants/item_data_constants.asm) is NOT contiguous: NOUSE is 0,
-- then `const_skip 3`, then CURRENT 4, PARTY 5, CLOSE 6.  A positional list
-- cannot be indexed by value, so the enum is spelled out with its real numbers.
local ITEM_MENU_NAME = {
  [0] = "ITEMMENU_NOUSE",
  [4] = "ITEMMENU_CURRENT",
  [5] = "ITEMMENU_PARTY",
  [6] = "ITEMMENU_CLOSE",
}

-- Font is 1bpp in Gen 2 (gfx/font.asm); FontExtra/FontBattleExtra are 2bpp.
-- TextBox / Font.drawCode multiply by the current color, so sheets MUST be
-- black ink on transparent (Gen 1's shape) -- opaque white+black becomes a
-- solid black rectangle when drawn with color (0,0,0).
--
-- Textbox borders ┌─┐│└┘ live in Frames (1bpp, loaded at $79), NOT FontExtra
-- (engine/gfx/load_font.asm LoadFrame).  We composite frame 0 into imageExtra.
local TEXTBOX_FRAME_TILES = 6
local NUM_FRAMES = 8

local function inkFrom1bpp(raw, width, height)
  local image = ImageWriter.blank(width, height, 0, 0, 0, 0)
  local tilesPerRow = width / 8
  for tile = 0, #raw / 8 - 1 do
    local tileX, tileY = tile % tilesPerRow * 8, math.floor(tile / tilesPerRow) * 8
    for y = 0, 7 do
      local row = raw[tile * 8 + y + 1]
      for x = 0, 7 do
        if bit.band(row, 2 ^ (7 - x)) ~= 0 then
          image:setPixel(tileX + x, tileY + y, 0, 0, 0, 1)
        end
      end
    end
  end
  return image
end

local function inkFrom2bpp(raw, width, height)
  local shaded = ImageWriter.decode2bpp(raw, width, height)
  local image = ImageWriter.blank(width, height, 0, 0, 0, 0)
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local r = shaded:getPixel(x, y)
      if r < 0.5 then image:setPixel(x, y, 0, 0, 0, 1) end
    end
  end
  return image
end

-- NUM_UNOWN + 1 tiles (the letters plus the cursor), on pret's own 3-wide
-- sheet; see the block in extractFont below.
local UNOWN_FONT_TILES = 27
local UNOWN_FONT_WIDE = 3

function RomExtractorGen2:extractFont()
  self:beginStage("Fonts")
  local font = self:symbol("Font")
  local raw = self.rom:bytes(font.bank, font.address, 128 * 8)
  self:save(inkFrom1bpp(raw, 128, 64), "fonts/font.png")
  self:tick("Fonts", 1, 4)

  -- Extra page ($60+): FontExtra 2bpp ink, then Frames borders at $79-$7E.
  local extra = self:symbol("FontExtra")
  local extraImg = inkFrom2bpp(
    self.rom:bytes(extra.bank, extra.address, 128 * 16 / 4), 128, 16)
  local frames = self:symbol("Frames")
  -- gfx/font.asm:10 Frames: NUM_FRAMES rows of TEXTBOX_FRAME_TILES 1bpp tiles,
  -- which is what LoadFrame's AddNTimes indexes off wTextboxFrame.
  local frameRaw = self.rom:bytes(
    frames.bank, frames.address, NUM_FRAMES * TEXTBOX_FRAME_TILES * 8)
  local frameSheet = inkFrom1bpp(frameRaw,
    TEXTBOX_FRAME_TILES * 8, NUM_FRAMES * 8)
  self:save(frameSheet, "fonts/frames.png")
  -- Row 0 still bakes into the extra page, so a cache without the sheet keeps
  -- frame 1 exactly as before.
  for t = 0, TEXTBOX_FRAME_TILES - 1 do
    local destId = 0x79 + t - 0x60 -- tile index in the $60-based extra sheet
    local dx, dy = (destId % 16) * 8, math.floor(destId / 16) * 8
    ImageWriter.blit(extraImg, frameSheet, dx, dy, t * 8, 0, 8, 8)
  end
  -- _LoadFontsExtra (engine/gfx/load_font.asm:7-20) does NOT lay FontExtra
  -- down from $60.  It writes three sources, and only the third is FontExtra:
  --
  --   $60-$61  FontsExtra_SolidBlackAndUpArrowGFX, 2 tiles, Get1bpp
  --   $62      PokegearPhoneIconGFX, 1 tile, Get2bpp
  --   $63+     FontExtra + 3 tiles, 22 tiles, Get2bpp
  --
  -- The third line is why the page above is still right from $63 up: FontExtra
  -- tile n lands at $60 + n either way, so only the first three cells differ.
  -- Left alone they hold FontExtra's own <BOLD_A>/<BOLD_B>/<BOLD_C>, which the
  -- cart never shows -- constants/charmap.asm:41 marks the $62 one "unused"
  -- and :88 gives $62 to "☎" -- and that is exactly the bold C the Pokegear's
  -- caller box drew where the phone icon belongs.
  --
  -- Both are tolerated rather than required, like UnownFont below: a manifest
  -- built before these symbols were listed still imports and simply keeps the
  -- three unused letters.
  if self.symbols["FontsExtra_SolidBlackAndUpArrowGFX"] then
    local solid = self:symbol("FontsExtra_SolidBlackAndUpArrowGFX")
    -- gfx/font/black.1bpp then gfx/font/up_arrow.1bpp, one tile each
    local solidImg = inkFrom1bpp(
      self.rom:bytes(solid.bank, solid.address, 2 * 8), 16, 8)
    ImageWriter.blit(extraImg, solidImg, 0, 0, 0, 0, 8, 8)   -- $60
    ImageWriter.blit(extraImg, solidImg, 8, 0, 8, 0, 8, 8)   -- $61
  end
  if self.symbols["PokegearPhoneIconGFX"] then
    local phone = self:symbol("PokegearPhoneIconGFX")
    local phoneImg = inkFrom2bpp(
      self.rom:bytes(phone.bank, phone.address, 8 * 8 / 4), 8, 8)
    ImageWriter.blit(extraImg, phoneImg, 16, 0, 0, 0, 8, 8)  -- $62
  end
  self:save(extraImg, "fonts/font_extra.png")
  self:tick("Fonts", 2, 4)

  local battleExtra = self:symbol("FontBattleExtra")
  self:save(inkFrom2bpp(
    self.rom:bytes(battleExtra.bank, battleExtra.address, 128 * 16 / 4),
    128, 16), "fonts/font_battle_extra.png")
  self:tick("Fonts", 3, 5)

  local data = {
    generation = 2,
    source = "ROM:Font, FontExtra, Frames, FontBattleExtra, PokegearPhoneIconGFX, FontsExtra_SolidBlackAndUpArrowGFX",
    image = "assets/generated/fonts/font.png",
    imageExtra = "assets/generated/fonts/font_extra.png",
    imageBattleExtra = "assets/generated/fonts/font_battle_extra.png",
    imageFrames = "assets/generated/fonts/frames.png",
    frameBase = 0x79, frameTiles = TEXTBOX_FRAME_TILES,
    mainBase = 0x80, extraBase = 0x60, glyphsPerRow = 16,
    charmap = self.manifest.fontCharmap or {},
  }

  -- The Unown font (gfx/font/unown_font.2bpp, gfx/font.asm UnownFont).  It is
  -- not a page of the ordinary font: Pokedex_LoadUnownFont copies 27 tiles to
  -- vTiles2 tile FIRST_UNOWN_CHAR ($40) only while the #DEX's UNOWN MODE is
  -- up, so the letters are addressed as tiles rather than as characters and
  -- this is written as a SHEET (four shades, drawn through a palette) rather
  -- than as ink like the three pages above.
  --
  -- Tile n is letter n + 1 (A..Z) and tile 26 -- FIRST_UNOWN_CHAR + NUM_UNOWN
  -- -- is the diamond cursor the ring of letters is pointed at with.  pret's
  -- PNG is 3 tiles across and 9 down and the 2bpp is built without
  -- --columns, so a straight row-major 24x72 decode IS gfx/font/
  -- unown_font.png, byte for byte.
  --
  -- The sheet goes out UNINVERTED, the way it sits in the ROM: the routine's
  -- Pokedex_InvertTiles pass is the same flip Chrome.printInverted already
  -- applies to the ordinary font (the palette read backwards), so inverting
  -- here would only make the drawing side undo it.
  --
  -- Tolerated rather than required, like credits and the diploma: a manifest
  -- built before this symbol was listed still imports, it just leaves UNOWN
  -- MODE printing its letters in the ordinary font.
  if self.symbols["UnownFont"] then
    local unown = self:symbol("UnownFont")
    self:write2bpp(
      self.rom:bytes(unown.bank, unown.address, UNOWN_FONT_TILES * 16),
      UNOWN_FONT_WIDE * 8, UNOWN_FONT_TILES / UNOWN_FONT_WIDE * 8,
      "fonts/unown_font.png")
    data.imageUnown = "assets/generated/fonts/unown_font.png"
    data.unownTiles = UNOWN_FONT_TILES
    data.unownWide = UNOWN_FONT_WIDE
    data.unownBase = 0x40 -- FIRST_UNOWN_CHAR
    data.source = data.source .. ", UnownFont"
  end
  self:tick("Fonts", 4, 5)

  self:write("font", data)
  self:tick("Fonts", 5, 5)
  return data
end

-- One GBC colour word: little-endian BGR555 (bits 0-4 red, 5-9 green,
-- 10-14 blue).
function RomExtractorGen2:color(bank, address)
  local value = self.rom:word(bank, address)
  return {
    scale5(value % 32),
    scale5(math.floor(value / 32) % 32),
    scale5(math.floor(value / 1024) % 32),
  }
end

-- `count` consecutive colours starting at address.
function RomExtractorGen2:colors(bank, address, count)
  local out = {}
  for i = 0, count - 1 do
    out[#out + 1] = self:color(bank, address + i * 2)
  end
  return out
end

-- BattleObjectPals (gfx/battle_anims/battle_anims.pal): SIX four-colour
-- palettes, and the first of them is PAL_BATTLE_OB_GRAY -- not slot 0.  Slots
-- 0 and 1 are PAL_BATTLE_OB_ENEMY / PAL_BATTLE_OB_PLAYER, which
-- _CGB_BattleColors fills with the two battlers' own colours, so the block on
-- disk starts two slots in and `battleAnimObPaletteOrder` is indexed from
-- PAL_BATTLE_OB_GRAY onward here.
function RomExtractorGen2:battleObjectPals()
  local names = (self.manifest.constants or {}).battleAnimObPaletteOrder or {}
  -- Tolerated rather than required: a manifest built before this symbol was
  -- listed still imports, it just leaves the runtime on its fallback ramp.
  if not self.symbols["BattleObjectPals"] then return nil end
  local symbol = self:symbol("BattleObjectPals")
  local out = {}
  -- The block's row 0 is PAL_BATTLE_OB_GRAY, which is index 3 of the 1-based
  -- name list (ENEMY, PLAYER, GRAY, ...).
  for row = 0, 5 do
    local name = names[row + 3]
    if name then
      out[name] = self:colors(symbol.bank, symbol.address + row * 8, 4)
    end
  end
  return out
end

-- A tileset's PalMap: 48 bytes, two tiles apiece.  `tilepal` emits
-- `dn (bank | PAL_BG_second), (bank | PAL_BG_first)`, so the low nibble is
-- the even tile and the high nibble the odd one; masking to 3 bits drops the
-- OAM_BANK flag and leaves the PAL_BG_* slot.  Returned 1-based so the value
-- indexes an 8-entry Lua palette set directly.
function RomExtractorGen2:readPalMap(address)
  local raw = self.rom:bytes(PAL_MAP_BANK, address, TILESET_TILE_COUNT / 2)
  local out = {}
  for i, byte in ipairs(raw) do
    out[(i - 1) * 2 + 1] = byte % 8 + 1
    out[(i - 1) * 2 + 2] = math.floor(byte / 16) % 8 + 1
  end
  return out
end

function RomExtractorGen2:extractPalettes()
  self:beginStage("Color palettes")
  local consts = self.manifest.constants

  -- The shared pool every BG palette slot is filled from.
  local bgSymbol = self:symbol("TilesetBGPalette")
  local bg = {}
  for index = 0, BG_PALETTE_COUNT - 1 do
    bg[index + 1] = self:colors(bgSymbol.bank, bgSymbol.address + index * 8, 4)
  end
  self:tick("Color palettes", 1, 6)

  -- environment -> daytime -> 8 pool indices (stored 1-based to index `bg`).
  local envSymbol = self:symbol("EnvironmentColorsPointers")
  local environments = {}
  local environmentOrder = consts.environmentOrder or {}
  for slot = 0, ENV_POINTER_COUNT - 1 do
    local rowAddress = self.rom:word(
      envSymbol.bank, envSymbol.address + slot * 2)
    -- Slot 0 is the unused leading entry; environment ids are 1-based.
    local name = environmentOrder[slot]
    if name then
      local perDaytime = {}
      for day = 0, #DAYTIMES - 1 do
        local indices = {}
        for i = 0, 7 do
          indices[i + 1] = self.rom:byte(
            envSymbol.bank, rowAddress + day * 8 + i) + 1
        end
        perDaytime[DAYTIMES[day + 1]] = indices
      end
      environments[name] = perDaytime
    end
  end
  self:tick("Color palettes", 2, 6)

  -- OW sprite OBJ palettes, one set of 8 per time of day.
  local objSymbol = self:symbol("MapObjectPals")
  local objects = {}
  for day = 0, #DAYTIMES - 1 do
    local set = {}
    for pal = 0, OW_PALETTE_COUNT - 1 do
      set[pal + 1] = self:colors(objSymbol.bank,
        objSymbol.address + (day * OW_PALETTE_COUNT + pal) * 8, 4)
    end
    objects[DAYTIMES[day + 1]] = set
  end
  self:tick("Color palettes", 3, 6)

  -- RoofPals rows are `table_width COLOR_SIZE * 2 * 2`: two morn/day colours
  -- followed by two nite colours, copied over PAL_BG_ROOF colours 1-2.
  local roofSymbol = self:symbol("RoofPals")
  local roofs = {}
  for group = 0, MAP_GROUP_COUNT do
    local base = roofSymbol.address + group * 8
    roofs[group] = {
      mornDay = self:colors(roofSymbol.bank, base, 2),
      nite = self:colors(roofSymbol.bank, base + 4, 2),
    }
  end
  self:tick("Color palettes", 4, 6)

  -- Mon and trainer pics ship only their two middle colours; white and black
  -- bracket them (data/pokemon/palettes.asm "only the middle two colors").
  local monSymbol = self:symbol("PokemonPalettes")
  local pokemon = {}
  for index, species in ipairs(consts.speciesOrder or {}) do
    if species and species ~= "UNUSED" then
      local base = monSymbol.address + index * 8
      pokemon[species] = {
        normal = self:colors(monSymbol.bank, base, 2),
        shiny = self:colors(monSymbol.bank, base + 4, 2),
      }
    end
  end
  -- The table runs past the 251 species: data/pokemon/palettes.asm:530 gives
  -- EGG ($fd, constants/pokemon_constants.asm:271) a row of its own, which is
  -- why `assert_table_length EGG + 1` sits right under it.  _CGB_Evolution
  -- reaches it through GetPlayerOrMonPalettePointer (engine/gfx/color.asm:620)
  -- whenever a pic's species is EGG, which is what Hatch_LoadFrontpicPal and
  -- the egg stats screen both hand it.
  pokemon.EGG = {
    normal = self:colors(monSymbol.bank, monSymbol.address + 253 * 8, 2),
    shiny = self:colors(monSymbol.bank, monSymbol.address + 253 * 8 + 4, 2),
  }
  self:tick("Color palettes", 5, 6)

  local trainerSymbol = self:symbol("TrainerPalettes")
  local trainers = {}
  for index, class in ipairs(consts.trainerClassOrder or {}) do
    -- Row 0 is PlayerPalette (Chris shares Cal's colours); TRAINER_NONE has
    -- no pic of its own, so name that row PLAYER instead.
    local name = (index == 1) and "PLAYER" or class
    trainers[name] = self:colors(
      trainerSymbol.bank, trainerSymbol.address + (index - 1) * 4, 2)
  end

  local hpSymbol = self:symbol("HPBarPals")
  local expSymbol = self:symbol("ExpBarPalette")
  local partySymbol = self:symbol("PartyMenuOBPals")

  local data = {
    generation = 2,
    source = "ROM:TilesetBGPalette/EnvironmentColorsPointers/MapObjectPals/RoofPals",
    daytimes = { DAYTIMES[1], DAYTIMES[2], DAYTIMES[3], DAYTIMES[4] },
    slotNames = PAL_BG_NAMES,
    roofSlot = PAL_BG_ROOF + 1,
    bg = bg,
    environments = environments,
    objects = objects,
    roofs = roofs,
    pokemon = pokemon,
    trainers = trainers,
    -- Two colours per HP-bar state (green/yellow/red plus the unused blue).
    hpBar = {
      green = self:colors(hpSymbol.bank, hpSymbol.address, 2),
      yellow = self:colors(hpSymbol.bank, hpSymbol.address + 4, 2),
      red = self:colors(hpSymbol.bank, hpSymbol.address + 8, 2),
      blue = self:colors(hpSymbol.bank, hpSymbol.address + 12, 2),
    },
    expBar = self:colors(expSymbol.bank, expSymbol.address, 2),
    partyMenu = {
      self:colors(partySymbol.bank, partySymbol.address, 4),
      self:colors(partySymbol.bank, partySymbol.address + 8, 4),
    },
    -- The six animation-object palettes, keyed by the PAL_BATTLE_OB_* name so
    -- an object's palette byte resolves straight through
    -- battleAnimObPaletteOrder.  Slots 0 and 1 (ENEMY / PLAYER) are the two
    -- battlers' own colours and are not in this block.
    battleObjects = self:battleObjectPals(),
  }
  self:write("palettes", data)
  self:tick("Color palettes", 6, 6)
  return data
end

-- The functions a `tileframe` row can name (data/tileset_anims.asm's macro:
-- `dw argument` then `dw function`), reverse-mapped by address so a tileset's
-- Anim pointer decodes into named steps instead of raw bank $3f addresses.
local ANIM_FUNCTIONS = {
  "DoneTileAnimation", "WaitTileAnimation",
  "StandingTileFrame", "StandingTileFrame8",
  "AnimateWaterTile", "AnimateFlowerTile", "AnimateWaterPalette",
  "ReadTileToAnimBuffer", "WriteTileFromAnimBuffer",
  "ScrollTileRightLeft", "ScrollTileDown", "ScrollTileUp",
  "ScrollTileLeft", "ScrollTileRight", "AnimateWhirlpoolTile",
  "AnimateLavaBubbleTile1", "AnimateLavaBubbleTile2",
  "AnimateTowerPillarTile", "FlickeringCaveEntrancePalette",
}

local ANIM_BANK = 0x3f
local ANIM_MAX_FRAMES = 32
local VTILES2 = 0x9000

-- How many tiles of each shared strip its animation function can index:
-- whirlpool `and %11` (engine/tilesets/tileset_anims.asm:368), tower pillar's
-- 0..4 offsets table (:334-342), lava `and %011` (:245).
local ANIM_STRIP_FRAMES = { whirlpool = 4, tower = 5, lava = 4 }

-- The two functions whose `tileframe` argument is a `dw vTiles2 tile, dw
-- frames` pair in bank $3f rather than a VRAM address (:290, :350).
local ANIM_POINTER_KIND = {
  AnimateWhirlpoolTile = "whirlpool",
  AnimateTowerPillarTile = "tower",
}

-- One shared frame strip, written once however many tilesets name it: the
-- source tiles stacked into an 8x(n*8) sheet, same shape as water_frames.png.
function RomExtractorGen2:animStrip(strips, name, kind, bank, address)
  if not strips[name] then
    local count = ANIM_STRIP_FRAMES[kind]
    local rel = "tilesets/anim/" .. name .. ".png"
    self:write2bpp(self.rom:bytes(bank, address, count * 16), 8, count * 8, rel)
    strips[name] = { image = "assets/generated/" .. rel, frames = count }
  end
  return strips[name]
end

-- One tileset's `wTilesetAnim` program.  _AnimateTileset (engine/tilesets/
-- tileset_anims.asm:11) runs ONE row per frame and DoneTileAnimation (:48)
-- wraps the index, so the row count IS the frames per pass.
function RomExtractorGen2:readTilesetAnim(address, byAddress, strips)
  if not (address and address > 0) then return nil end
  local frames = {}
  -- A ReadTileToAnimBuffer/ScrollTile*/WriteTileFromAnimBuffer run (:399, :65,
  -- :139, :386) scrolls the tileset's OWN tile, so the write row carries how
  -- far one pass moves it instead of naming a strip.
  local pending = nil
  for index = 0, ANIM_MAX_FRAMES - 1 do
    local at = address + index * 4
    if at + 3 >= 0x8000 then break end
    local arg = self.rom:word(ANIM_BANK, at)
    local func = self.rom:word(ANIM_BANK, at + 2)
    local name = byAddress[func]
    if not name then return nil end
    local frame = { func = name }
    -- A vTiles2 argument is the VRAM tile the step writes; a wTileAnimBuffer
    -- one is WRAM and has no tile id.
    if arg >= VTILES2 and arg < VTILES2 + 0x800 then
      frame.tile = math.floor((arg - VTILES2) / 16)
    end
    local kind = ANIM_POINTER_KIND[name]
    if kind then
      local dest = self.rom:word(ANIM_BANK, arg)
      if dest >= VTILES2 and dest < VTILES2 + 0x800 then
        frame.tile = math.floor((dest - VTILES2) / 16)
        local strip = self:animStrip(strips,
          ("%s_%02x"):format(kind, frame.tile), kind,
          ANIM_BANK, self.rom:word(ANIM_BANK, arg + 2))
        frame.sheet, frame.frames = strip.image, strip.frames
      end
    elseif name == "AnimateLavaBubbleTile1" or name == "AnimateLavaBubbleTile2"
    then
      -- Both take no argument: tile $5b and tile $38, one strip (:254, :279).
      frame.tile = (name == "AnimateLavaBubbleTile1") and 0x5b or 0x38
      local lava = self.symbols["LavaBubbleTileFrames"]
      if lava then
        local strip = self:animStrip(
          strips, "lava", "lava", lava[1], lava[2])
        frame.sheet, frame.frames = strip.image, strip.frames
      end
    elseif name == "ReadTileToAnimBuffer" then
      pending = { h = 0, v = 0 }
    elseif name == "ScrollTileRightLeft" then
      if pending then pending.h = pending.h + 1 end
    elseif name == "ScrollTileDown" then
      if pending then pending.v = pending.v + 1 end
    elseif name == "ScrollTileUp" then
      if pending then pending.v = pending.v - 1 end
    elseif name == "WriteTileFromAnimBuffer" then
      if pending and frame.tile then frame.scroll = pending end
      pending = nil
    end
    frames[#frames + 1] = frame
    if name == "DoneTileAnimation" then
      return { period = #frames, frames = frames }
    end
  end
  return nil
end

-- Every Tilesets row is TILESET_LENGTH (15) bytes: dba GFX, dba Meta,
-- dba Coll, dw Anim, dw NULL, dw PalMap (data/tilesets.asm's `tileset`
-- macro).  Row 0 is the unused "Tileset0" alias of TilesetJohto, and row
-- index == the TILESET_* constant value, so tilesetOrder[n]'s row starts at
-- headers.address + n*15.  GFX is lz3; Meta and Coll are raw.
function RomExtractorGen2:extractTilesets()
  self:beginStage("World tiles")
  local order = self.manifest.constants.tilesetOrder
  local headers = self:symbol("Tilesets")
  local imageWidth, imageHeight = 128, 48
  local byteLength = imageWidth * imageHeight / 4

  -- A cache built from a manifest without the tileset_anims symbols simply
  -- resolves nothing here, and every `anim` below comes out nil.
  local animByAddress = {}
  for _, label in ipairs(ANIM_FUNCTIONS) do
    local location = self.symbols[label]
    if location and location[1] == ANIM_BANK then
      animByAddress[location[2]] = label
    end
  end

  -- Whirlpool/tower-pillar/lava strips live in bank $3f, not in a tileset, so
  -- one table dedupes them across every program that names them.
  local animStrips = {}

  local out = {}
  for index, constName in ipairs(order) do
    local rowAddress = headers.address + index * 15
    local gfxBank = self.rom:byte(headers.bank, rowAddress)
    local gfxAddress = self.rom:word(headers.bank, rowAddress + 1)
    local metaBank = self.rom:byte(headers.bank, rowAddress + 3)
    local metaAddress = self.rom:word(headers.bank, rowAddress + 4)
    local collBank = self.rom:byte(headers.bank, rowAddress + 6)
    local collAddress = self.rom:word(headers.bank, rowAddress + 7)
    local animAddress = self.rom:word(headers.bank, rowAddress + 9)
    local palMapAddress = self.rom:word(headers.bank, rowAddress + 13)

    local compressed = self.rom:bytes(
      gfxBank, gfxAddress, 0x8000 - gfxAddress)
    local pixels = Rom.decompressLz3(compressed)
    while #pixels < byteLength do pixels[#pixels + 1] = 0 end
    while #pixels > byteLength do table.remove(pixels) end
    local base = constName:lower():gsub("^tileset_", "")
    self:write2bpp(pixels, imageWidth, imageHeight, "tilesets/" .. base .. ".png")

    local metaRaw = self.rom:bytes(
      metaBank, metaAddress, METATILE_COUNT * 16)
    local blocks = {}
    for offset = 1, #metaRaw, 16 do
      local block = {}
      for pos = offset, offset + 15 do block[#block + 1] = metaRaw[pos] end
      blocks[#blocks + 1] = block
    end

    local collRaw = self.rom:bytes(
      collBank, collAddress, METATILE_COUNT * 4)
    local collision = {}
    for offset = 1, #collRaw, 4 do
      collision[#collision + 1] = {
        collRaw[offset], collRaw[offset + 1],
        collRaw[offset + 2], collRaw[offset + 3],
      }
    end

    out[constName] = {
      id = constName,
      generation = 2,
      source = ("ROM:Tilesets[%d]"):format(index),
      header = self.rom:bytes(headers.bank, rowAddress, 15),
      image = "assets/generated/tilesets/" .. base .. ".png",
      imageWidth = imageWidth, imageHeight = imageHeight,
      tilesPerRow = imageWidth / 8,
      blocks = blocks,
      collision = collision,
      -- Anim callbacks live in bank $3f (data/tilesets.asm).
      anim = self:readTilesetAnim(animAddress, animByAddress, animStrips),
      palMap = { bank = PAL_MAP_BANK, address = palMapAddress },
      -- Which of the eight loaded BG palettes each of the 96 tiles draws
      -- with, 1-based into palettes.bg slots (see readPalMap).
      tilePalettes = self:readPalMap(palMapAddress),
    }
    self:tick("World tiles", index, #order)
  end
  -- The two frame strips every tileset's water/flower step writes from
  -- (engine/tilesets/tileset_anims.asm:194 and :225), four 8x8 tiles each,
  -- stacked into one 8x32 sheet.  BG tiles, so no colour-0 key.
  local waterFrames = self.symbols["AnimateWaterTile.WaterTileFrames"]
  if waterFrames then
    self:write2bpp(self.rom:bytes(waterFrames[1], waterFrames[2], 4 * 16),
      8, 32, "tilesets/water_frames.png")
    out.waterFrames = "assets/generated/tilesets/water_frames.png"
  end
  local flowerFrames = self.symbols["AnimateFlowerTile.FlowerTileFrames"]
  if flowerFrames then
    self:write2bpp(self.rom:bytes(flowerFrames[1], flowerFrames[2], 4 * 16),
      8, 32, "tilesets/flower_frames.png")
    out.flowerFrames = "assets/generated/tilesets/flower_frames.png"
    -- dmg_1, cgb_1, dmg_2, cgb_2: `and %10` plus hCGB picks rows 2 and 4
    -- (tileset_anims.asm:204-212).
    out.flowerCgbFrames = { 2, 4 }
  end
  -- Every shared strip the programs above named, for tests and mods; the anim
  -- rows themselves already carry their own image path.
  out.animFrames = animStrips
  self:write("tilesets", out)
  return out
end

function RomExtractorGen2:extractRoofs()
  -- Outdoor Johto towns replace VRAM tiles $0a-$12 from Roofs, indexed by
  -- MapGroupRoofs[group] (engine/tilesets/mapgroup_roofs.asm).
  local roofs = self:symbol("Roofs")
  local groupRoofs = self:symbol("MapGroupRoofs")
  local out = { generation = 2, roofs = {}, mapGroupRoofs = {} }
  -- Five roof sets (ROOF_NEW_BARK .. ROOF_GOLDENROD), 9 tiles each.
  local roofNames = {
    "NEW_BARK", "VIOLET", "AZALEA", "OLIVINE", "GOLDENROD",
  }
  for index, name in ipairs(roofNames) do
    local addr = roofs.address + (index - 1) * ROOF_TILES * 16
    local pixels = self.rom:bytes(roofs.bank, addr, ROOF_TILES * 16)
    local rel = "tilesets/roofs/" .. name:lower() .. ".png"
    self:write2bpp(pixels, 72, 8, rel)
    out.roofs[name] = {
      id = name, index = index - 1,
      image = "assets/generated/" .. rel,
    }
  end
  -- MapGroupRoofs: one signed byte per map group (groups are 1-based; the
  -- table is indexed by group id, with a leading -1 for group 0).
  for group = 1, 26 do
    local value = self.rom:byte(groupRoofs.bank, groupRoofs.address + group)
    if value < 0x80 and roofNames[value + 1] then
      out.mapGroupRoofs[group] = roofNames[value + 1]
    end
  end
  self:write("roofs", out)
  return out
end

local function signedByte(value)
  if value >= 0x80 then return value - 0x100 end
  return value
end

local function orderName(list, index, fallback)
  if type(list) ~= "table" then return fallback or index end
  return list[index] or fallback or index
end

-- Resolve (group, map) -> const name from the manifest's mapGroups list.
function RomExtractorGen2:mapNameByIds(group, map)
  if not self._mapByIds then
    self._mapByIds = {}
    for _, spec in ipairs(self.manifest.constants.mapGroups or {}) do
      self._mapByIds[spec.group * 1000 + spec.map] = spec.name
    end
  end
  return self._mapByIds[group * 1000 + map]
end

function RomExtractorGen2:readMapGroupEntry(group, map)
  local pointers = self:symbol("MapGroupPointers")
  local groupPtr = self.rom:word(
    pointers.bank, pointers.address + (group - 1) * 2)
  local entry = groupPtr + (map - 1) * MAP_LENGTH
  local bank = pointers.bank
  return {
    attributesBank = self.rom:byte(bank, entry),
    tileset = self.rom:byte(bank, entry + 1),
    environment = self.rom:byte(bank, entry + 2),
    attributesAddress = self.rom:word(bank, entry + 3),
    landmark = self.rom:byte(bank, entry + 5),
    music = self.rom:byte(bank, entry + 6),
    phoneAndPalette = self.rom:byte(bank, entry + 7),
    fishGroup = self.rom:byte(bank, entry + 8),
  }
end

function RomExtractorGen2:readConnections(bank, address, flags)
  local connections = {}
  local dirs = {
    { bit = CONN_NORTH, key = "north" },
    { bit = CONN_SOUTH, key = "south" },
    { bit = CONN_WEST, key = "west" },
    { bit = CONN_EAST, key = "east" },
  }
  local cursor = address
  for _, dir in ipairs(dirs) do
    if bit.band(flags, dir.bit) ~= 0 then
      local group = self.rom:byte(bank, cursor)
      local map = self.rom:byte(bank, cursor + 1)
      local yOffset = signedByte(self.rom:byte(bank, cursor + 8))
      local xOffset = signedByte(self.rom:byte(bank, cursor + 9))
      local offset
      if dir.key == "north" or dir.key == "south" then
        offset = -math.floor(xOffset / 2)
      else
        offset = -math.floor(yOffset / 2)
      end
      -- Avoid Lua's signed-zero (-0) from -math.floor(0/2).
      if offset == 0 then offset = 0 end
      connections[dir.key] = {
        group = group, map = map,
        mapId = self:mapNameByIds(group, map),
        stripLength = self.rom:byte(bank, cursor + 6),
        width = self.rom:byte(bank, cursor + 7),
        yOffset = yOffset, xOffset = xOffset,
        offset = offset,
      }
      cursor = cursor + CONNECTION_LENGTH
    end
  end
  return connections
end

function RomExtractorGen2:readMapEvents(bank, address, spriteOrder)
  -- *_MapEvents always starts with `db 0, 0 ; filler`.
  local cursor = address + 2
  local warpCount = self.rom:byte(bank, cursor)
  cursor = cursor + 1
  local warps = {}
  for i = 1, warpCount do
    local y = self.rom:byte(bank, cursor)
    local x = self.rom:byte(bank, cursor + 1)
    local destWarp = self.rom:byte(bank, cursor + 2)
    local destGroup = self.rom:byte(bank, cursor + 3)
    local destMap = self.rom:byte(bank, cursor + 4)
    warps[i] = {
      x = x, y = y, destWarp = destWarp,
      destGroup = destGroup, destMapNum = destMap,
      destMap = self:mapNameByIds(destGroup, destMap),
    }
    cursor = cursor + WARP_LENGTH
  end

  local coordCount = self.rom:byte(bank, cursor)
  cursor = cursor + 1
  local coordEvents = {}
  for i = 1, coordCount do
    coordEvents[i] = {
      sceneId = self.rom:byte(bank, cursor),
      y = self.rom:byte(bank, cursor + 1),
      x = self.rom:byte(bank, cursor + 2),
      script = self.rom:word(bank, cursor + 4),
    }
    cursor = cursor + COORD_LENGTH
  end

  local bgCount = self.rom:byte(bank, cursor)
  cursor = cursor + 1
  local bgEvents = {}
  for i = 1, bgCount do
    local kind = self.rom:byte(bank, cursor + 2)
    local pointer = self.rom:word(bank, cursor + 3)
    local ev = {
      y = self.rom:byte(bank, cursor),
      x = self.rom:byte(bank, cursor + 1),
      kind = kind,
      script = pointer,
    }
    -- BGEVENT_IFSET (5) and BGEVENT_IFNOTSET (6) do not point at a script.
    -- They point at a `conditional_event` (dw event / dba script): two bytes of
    -- EVENT id followed by a three-byte far pointer to the script proper.
    -- `.ifset` / `.ifnotset` in engine/overworld/events.asm read the flag, and
    -- only then `inc hl / inc hl / GetFarWord` to reach the real thing.
    --
    -- Extracted as a plain script pointer, those five bytes were disassembled
    -- as commands and produced nonsense -- TeamRocketBaseB3F's locked door came
    -- out as a lone `sjump` to an unrelated address. Nothing could run it, so
    -- Giovanni's door never opened and the whole Rocket hideout dead-ended.
    -- `MACRO conditional_event` is `dw \1, \2` -- two WORDS, the event then
    -- the script address, both in the map's own bank. (Not a `dba`: the
    -- handler's `inc hl / inc hl / GetFarWord` skips one word and reads the
    -- next, and GetMapScriptsBank supplies the bank.)
    if kind == 5 or kind == 6 then
      ev.event = self.rom:word(bank, pointer)
      ev.script = self.rom:word(bank, pointer + 2)
    end
    bgEvents[i] = ev
    cursor = cursor + BG_LENGTH
  end

  local objectCount = self.rom:byte(bank, cursor)
  cursor = cursor + 1
  local objects = {}
  for i = 1, objectCount do
    local spriteId = self.rom:byte(bank, cursor)
    local y = self.rom:byte(bank, cursor + 1) - 4
    local x = self.rom:byte(bank, cursor + 2) - 4
    local movement = self.rom:byte(bank, cursor + 3)
    local radius = self.rom:byte(bank, cursor + 4)
    local hour1 = signedByte(self.rom:byte(bank, cursor + 5))
    local hour2 = signedByte(self.rom:byte(bank, cursor + 6))
    local palType = self.rom:byte(bank, cursor + 7)
    local sight = self.rom:byte(bank, cursor + 8)
    local script = self.rom:word(bank, cursor + 9)
    local eventFlag = self.rom:word(bank, cursor + 11)
    objects[i] = {
      index = i,
      spriteId = spriteId,
      sprite = orderName(spriteOrder, spriteId),
      x = x, y = y,
      movement = movement,
      radius = { y = math.floor(radius / 16), x = radius % 16 },
      hours = { hour1, hour2 },
      palette = math.floor(palType / 16),
      type = palType % 16,
      sight = sight,
      script = script,
      eventFlag = eventFlag == 0xFFFF and nil or eventFlag,
    }
    cursor = cursor + OBJECT_LENGTH
  end

  return {
    warps = warps, coordEvents = coordEvents,
    bgEvents = bgEvents, objects = objects,
  }
end

function RomExtractorGen2:extractMaps()
  self:beginStage("Maps")
  local consts = self.manifest.constants
  local mapOrder = consts.mapOrder
  local tilesetOrder = consts.tilesetOrder
  local envOrder = consts.environmentOrder
  local paletteOrder = consts.paletteOrder
  local fishOrder = consts.fishGroupOrder
  local spriteOrder = consts.spriteOrder

  local out = {}
  for index, name in ipairs(mapOrder) do
    local spec = self.manifest.maps[name]
    local entry = self:readMapGroupEntry(spec.group, spec.map)
    local attrBank = entry.attributesBank
    local attrAddr = entry.attributesAddress

    local border = self.rom:byte(attrBank, attrAddr)
    local height = self.rom:byte(attrBank, attrAddr + 1)
    local width = self.rom:byte(attrBank, attrAddr + 2)
    assert(width == spec.width and height == spec.height,
      name .. ": attributes dims mismatch manifest")
    local blocksBank = self.rom:byte(attrBank, attrAddr + 3)
    local blocksAddr = self.rom:word(attrBank, attrAddr + 4)
    local eventsBank = self.rom:byte(attrBank, attrAddr + 6)
    local scriptsAddr = self.rom:word(attrBank, attrAddr + 7)
    local eventsAddr = self.rom:word(attrBank, attrAddr + 9)
    local connFlags = self.rom:byte(attrBank, attrAddr + 11)

    local blocks = self.rom:bytes(
      blocksBank, blocksAddr, width * height)
    local connections = self:readConnections(
      attrBank, attrAddr + ATTR_LENGTH, connFlags)
    local events = self:readMapEvents(eventsBank, eventsAddr, spriteOrder)

    local phonePalette = entry.phoneAndPalette
    -- Map scripts header (macros/scripts/maps.asm): db scene_count;
    -- scene_script {dw script, dw filler} × N; db callback_count;
    -- callback {db type, dw script} × M.  Scene 0 runs on map enter (Elm
    -- walk-up, etc.); the callbacks are what RunMapCallback dispatches on a
    -- load -- MAPCALLBACK_TILES repaints blocks, _OBJECTS moves NPCs,
    -- _CMDQUEUE refills wCmdQueue (the two stone tables), _SPRITES swaps
    -- sheets, _NEWMAP runs once per new game.
    local sceneScripts, callbacks = {}, {}
    if eventsBank and eventsBank > 0 and scriptsAddr and scriptsAddr >= 0x4000 then
      local okCount, sceneCount = pcall(
        self.rom.byte, self.rom, eventsBank, scriptsAddr)
      if okCount and sceneCount and sceneCount < 32 then
        for si = 0, sceneCount - 1 do
          local addr = scriptsAddr + 1 + si * 4
          local okSc, script = pcall(self.rom.word, self.rom, eventsBank, addr)
          if okSc and script and script ~= 0 then
            sceneScripts[si] = {
              sceneId = si,
              script = script,
              scriptKey = Opcodes.key(eventsBank, script),
            }
          end
        end
        local cbBase = scriptsAddr + 1 + sceneCount * 4
        local okCb, cbCount = pcall(self.rom.byte, self.rom, eventsBank, cbBase)
        if okCb and cbCount and cbCount <= NUM_MAPCALLBACK_TYPES then
          for ci = 0, cbCount - 1 do
            local row = cbBase + 1 + ci * 3
            local okType, kind = pcall(self.rom.byte, self.rom, eventsBank, row)
            local okAddr, script = pcall(
              self.rom.word, self.rom, eventsBank, row + 1)
            if okType and okAddr and script and script ~= 0 then
              -- MAPCALLBACK_* is `const_def 1` and mapCallbackOrder carries a
              -- placeholder in front of it, so a type byte lands on Lua index
              -- byte + 1 like every other 0-based order in this file.
              local name = orderName(consts.mapCallbackOrder, kind + 1)
              callbacks[#callbacks + 1] = {
                type = kind,
                callback = name,
                script = script,
                scriptKey = Opcodes.key(eventsBank, script),
              }
            end
          end
        end
      end
    end

    out[name] = {
      id = name,
      generation = 2,
      group = spec.group, map = spec.map,
      width = width, height = height,
      borderBlock = border,
      tileset = orderName(tilesetOrder, entry.tileset),
      tilesetId = entry.tileset,
      environment = orderName(envOrder, entry.environment),
      environmentId = entry.environment,
      landmark = entry.landmark,
      music = entry.music,
      -- GetMapPhoneService (home/map.asm): the attribute byte's HIGH nybble,
      -- and every caller tests `and a` -- ZERO means the map HAS service, so
      -- the boolean is the nybble's emptiness.  Caves and Kanto's dead zones
      -- carry a non-zero nybble; towns and routes carry zero.
      phoneService = math.floor(phonePalette / 16) == 0,
      palette = orderName(paletteOrder, phonePalette % 16 + 1)
        or (phonePalette % 16),
      fishGroup = orderName(fishOrder, entry.fishGroup + 1)
        or entry.fishGroup,
      blocks = blocks,
      -- Where those blocks live in ROM.  `changemapblocks` hands the VM a raw
      -- bank/pointer into blockdata and nothing else in the cache is keyed by
      -- one, so World:blockdataAt places the pointer by walking these.
      blockdata = { bank = blocksBank, address = blocksAddr },
      connections = connections,
      warps = events.warps,
      coordEvents = events.coordEvents,
      bgEvents = events.bgEvents,
      objects = events.objects,
      sceneScripts = sceneScripts,
      callbacks = callbacks,
      scripts = { bank = eventsBank, address = scriptsAddr },
      events = { bank = eventsBank, address = eventsAddr },
      source = ("ROM:MapGroupPointers[%d][%d]"):format(spec.group, spec.map),
    }
    self:tick("Maps", index, #mapOrder)
  end

  self:extractRoofs()
  self:write("maps", out)
  return out
end

-- OverworldSprites rows are NUM_SPRITEDATA_FIELDS (6) bytes each
-- (data/sprites/sprites.asm): dw addr, db length, bank, type, palette.
-- Length is already in bytes (`N tiles` in RGBDS).  WALKING_SPRITE sheets
-- store standing + walking halves back-to-back (see ChrisSpriteGFX + 12
-- tiles), so ROM length is size*2; STANDING/STILL use size as-is.  Layout
-- matches Gen 1's 16-wide strips that SpriteRenderer already understands
-- (stand down/up/left, walk down/up/left; right = X-flip).
--
-- Only the first `numOverworldSprites` ids are rows of that table; the ids from
-- SPRITE_POKEMON on are SpriteMons rows instead (extractMonSprites below), and
-- reading them out of OverworldSprites would decode whatever data follows it.
function RomExtractorGen2:extractSprites()
  self:beginStage("Overworld sprites")
  local consts = self.manifest.constants
  local order = consts.spriteOrder
  local rows = consts.numOverworldSprites or #order
  local table = self:symbol("OverworldSprites")
  local out, written = {}, {}
  for index = 1, rows do
    local constName = order[index]
    local rowAddr = table.address + (index - 1) * SPRITEDATA_LENGTH
    local pointer = self.rom:word(table.bank, rowAddr)
    local sizeBytes = self.rom:byte(table.bank, rowAddr + 2)
    local bank = self.rom:byte(table.bank, rowAddr + 3)
    local spriteType = self.rom:byte(table.bank, rowAddr + 4)
    local palette = self.rom:byte(table.bank, rowAddr + 5)
    local byteLength = sizeBytes
    if spriteType == WALKING_SPRITE then
      byteLength = sizeBytes * 2
    end
    local width = 16
    assert(byteLength > 0 and byteLength % 16 == 0,
      constName .. ": sprite length not tile-aligned")
    local height = byteLength * 4 / width
    assert(height % 16 == 0, constName .. ": sprite height not frame-aligned")
    local frames = height / 16
    local base = constName:lower():gsub("^sprite_", "")
    if not written[base] then
      self:write2bpp(self.rom:bytes(bank, pointer, byteLength),
        width, height, "sprites/" .. base .. ".png", true)
      written[base] = true
    end
    out[constName] = {
      id = constName,
      source = ("ROM:OverworldSprites[%d]"):format(index - 1),
      image = "assets/generated/sprites/" .. base .. ".png",
      frames = frames,
      walker = spriteType == WALKING_SPRITE or frames >= 6,
      spriteType = SPRITE_TYPE_NAME[spriteType] or spriteType,
      palette = SPRITE_PALETTE_NAME[palette] or palette,
      paletteId = palette,
    }
    self:tick("Overworld sprites", index, #order)
  end
  self:extractMonSprites(out)
  self:write("sprites", out)
  return out
end

-- The mon-doll half of the sprite ids (data/sprites/sprite_mons.asm).
--
-- SpriteMons is a `table_width 1` list of species, one per id from
-- SPRITE_POKEMON ($80) up, and GetMonSprite (engine/overworld/overworld.asm)
-- is what makes it a sprite: its .Icon arm subtracts SPRITE_POKEMON, reads the
-- species out of SpriteMons and hands it to LoadOverworldMonIcon, which is
-- ReadMonMenuIcon + IconPointers -- i.e. the mon's PARTY MENU icon, eight
-- tiles, no sheet of its own.  So the rows here point at the icon sheets
-- extractIcons already writes rather than at a second copy of them.
--
-- One frame, not two.  _DoesSpriteHaveFacings sends everything from
-- SPRITE_POKEMON up to .only_down, and a doll is a still object that never
-- steps, so the only OAM set it ever uses is FacingStepDown0 -- tiles $00..$03,
-- the icon's FIRST frame (data/sprites/facings.asm).  The second frame is the
-- party menu's bob and never reaches the map.
--
-- Palette 0 because _GetSpritePalette answers `xor a` for every mon sprite,
-- which is PAL_OW_RED in the MapObjectPals set.
function RomExtractorGen2:extractMonSprites(out)
  local consts = self.manifest.constants
  local order = consts.spriteOrder
  local first = consts.spritePokemon
  if not first or first > #order then return out end
  local spriteMons = self:symbol("SpriteMons")
  local monIcons = self:symbol("MonMenuIcons")
  local iconOrder = consts.iconOrder or {}
  local speciesOrder = consts.speciesOrder or {}
  for index = first, #order do
    local constName = order[index]
    if constName and constName ~= "UNUSED" then
      local row = index - first
      local species = self.rom:byte(spriteMons.bank, spriteMons.address + row)
      -- MonMenuIcons is 0-based on species-1, the same shift extractIcons uses.
      local iconId = self.rom:byte(
        monIcons.bank, monIcons.address + (species - 1))
      local icon = iconOrder[iconId + 1]
      assert(icon, constName .. ": no ICON_* name for icon " .. iconId)
      local base = icon:lower():gsub("^icon_", "")
      out[constName] = {
        id = constName,
        source = ("ROM:SpriteMons[%d]"):format(row),
        image = "assets/generated/icons/gen2/" .. base .. ".png",
        frames = 1,
        walker = false,
        spriteType = "POKEMON_SPRITE",
        palette = SPRITE_PALETTE_NAME[0],
        paletteId = 0,
        species = speciesOrder[species],
        icon = icon,
      }
    end
    self:tick("Overworld sprites", index, #order)
  end
  return out
end

-- BaseData rows are BASE_DATA_SIZE (32) bytes, and -- unlike Gen 1's Kanto
-- reorder -- the row index already IS the dex number (data/pokemon/
-- base_stats.asm lists species in constants/pokemon_constants.asm order,
-- and each row's own first byte repeats that same dex number).  Unown's base
-- data is read like everything else; only its PICS are special -- there is no
-- PokemonPicPointers row for it, because the 26 letters come out of
-- UnownPicPointers instead, and letter A's pics stand in for the species.
-- EvosAttacks: a per-species blob of 3-byte evolution rows terminated by 0,
-- then (level, move) pairs terminated by 0.  Both halves are variable length,
-- so there is no row stride to index -- the terminators are the structure.
--
-- EVOLVE_STAT's second byte is a level and its *third* is the ATK_*_DEF
-- comparison, which is why that method takes four bytes where the rest take
-- three (data/pokemon/evos_attacks.asm's header comment).
local EVOLVE_LEVEL, EVOLVE_ITEM = 1, 2
local EVOLVE_TRADE, EVOLVE_HAPPINESS, EVOLVE_STAT = 3, 4, 5
-- EVOLVE_HAPPINESS parameter (constants/pokemon_data_constants.asm TR_*).
-- Both of these blocks are `const_def 1`, so the stored byte is 1-based and
-- the table must be too: a [0]-based one shifts every row down and drops the
-- last to nil, which silently made TR_NITE and ATK_EQ_DEF unreachable.
local TR_NAMES = { "ANYTIME", "MORNDAY", "NITE" }
-- EVOLVE_STAT comparison.  The ROM order is GT, LT, EQ -- not the order the
-- method reads in, which is the easy way to get this pair backwards.
local ATK_NAMES = { "ATK_GT_DEF", "ATK_LT_DEF", "ATK_EQ_DEF" }

function RomExtractorGen2:readEvosAttacks(bank, address)
  local moveOrder = self.manifest.constants.moveOrder or {}
  local itemOrder = self.manifest.constants.itemOrder or {}
  local evolutions, levelMoves = {}, {}
  local pc = address
  for _ = 1, 16 do
    local method = self.rom:byte(bank, pc)
    if method == 0 then pc = pc + 1 break end
    if method == EVOLVE_STAT then
      evolutions[#evolutions + 1] = {
        method = "EVOLVE_STAT",
        level = self.rom:byte(bank, pc + 1),
        comparison = ATK_NAMES[self.rom:byte(bank, pc + 2)],
        into = self:speciesName(self.rom:byte(bank, pc + 3)),
      }
      pc = pc + 4
    else
      local parameter = self.rom:byte(bank, pc + 1)
      local into = self:speciesName(self.rom:byte(bank, pc + 2))
      local row = { into = into }
      if method == EVOLVE_LEVEL then
        row.method, row.level = "EVOLVE_LEVEL", parameter
      elseif method == EVOLVE_ITEM then
        row.method, row.item = "EVOLVE_ITEM", itemOrder[parameter]
      elseif method == EVOLVE_TRADE then
        row.method = "EVOLVE_TRADE"
        -- -1 means "no held item required".
        row.item = (parameter ~= 0xff) and itemOrder[parameter] or nil
      elseif method == EVOLVE_HAPPINESS then
        row.method, row.time = "EVOLVE_HAPPINESS", TR_NAMES[parameter]
      else
        row.method, row.parameter = method, parameter
      end
      evolutions[#evolutions + 1] = row
      pc = pc + 3
    end
  end
  for _ = 1, 64 do
    local level = self.rom:byte(bank, pc)
    if level == 0 then break end
    local move = self.rom:byte(bank, pc + 1)
    levelMoves[#levelMoves + 1] = {
      level = level,
      move = moveOrder[move] or move,
    }
    pc = pc + 2
  end
  return evolutions, levelMoves
end

function RomExtractorGen2:extractPokemon()
  self:beginStage("Pokemon")
  local speciesOrder = self.manifest.constants.speciesOrder
  local typeById = {}
  for name, value in pairs(self.manifest.constants.types) do typeById[value] = name end
  local baseData = self:symbol("BaseData")
  local names = self:symbol("PokemonNames")
  local evos = self:symbol("EvosAttacksPointers")
  local growthRates = self:symbol("GrowthRates")
  local tmhmMoves = self:symbol("TMHMMoves")
  local eggMovePointers = self.symbols["EggMovePointers"]
    and self:symbol("EggMovePointers") or nil
  local growthOrder = self.manifest.constants.growthRateOrder or {}
  local eggGroupOrder = self.manifest.constants.eggGroupOrder or {}
  local moveOrder = self.manifest.constants.moveOrder or {}
  local itemOrder = self.manifest.constants.itemOrder or {}

  -- TMHMMoves maps a TM/HM number to the move it teaches; a species' BASE_TMHM
  -- bitfield is indexed by that same number (see the tmhm macro), so decoding
  -- it needs this table rather than a move id.
  local tmhmList = {}
  for i = 0, 63 do
    local moveId = self.rom:byte(tmhmMoves.bank, tmhmMoves.address + i)
    if moveId == 0 then break end
    tmhmList[i + 1] = moveOrder[moveId] or moveId
  end

  -- GrowthRates rows: dn numerator, denominator; then the n^2, n and constant
  -- terms, with a $80 sign bit on the n^2 term (data/growth_rates.asm).
  local growth = {}
  for index, name in ipairs(growthOrder) do
    local base = growthRates.address + (index - 1) * 4
    local packed = self.rom:byte(growthRates.bank, base)
    local squared = self.rom:byte(growthRates.bank, base + 1)
    local negative = squared >= 0x80
    growth[name] = {
      id = name, index = index - 1,
      numerator = math.floor(packed / 16),
      denominator = packed % 16,
      squared = negative and -(squared - 0x80) or squared,
      linear = self.rom:byte(growthRates.bank, base + 2),
      constant = self.rom:byte(growthRates.bank, base + 3),
    }
  end

  local out = { growthRates = growth, tmhmMoves = tmhmList }
  for index, species in ipairs(speciesOrder) do
    if species then
      local row = self.rom:bytes(
        baseData.bank, baseData.address + (index - 1) * 32, 32)
      assert(row[1] == index, species .. ": base data dex mismatch")
      local name = self.rom:decodeText(
        self.rom:bytes(names.bank, names.address + (index - 1) * 10, 10),
        self.manifest.charmap)

      local asset = self.manifest.pokemonAssets[species]
      local tiles = row[18] % 16 -- BASE_PIC_SIZE low nibble, tiles wide/tall
      local front, back
      if asset and asset.frontLabel then
        self:writeCompressedPic(asset.frontLabel, tiles,
          "battle/front/" .. asset.front .. ".png")
        front = asset.front
      end
      if asset and asset.backLabel then
        -- Back pics are ALWAYS 6x6 tiles (48x48).  BASE_PIC_SIZE's low nibble
        -- describes the *front* pic only -- Cyndaquil's front is 5x5 and Onix's
        -- 7x7, but both backs are 48x48 (gfx/pokemon/*/back.png).  Decoding a
        -- back at the front's size reads the wrong number of tiles and lays
        -- them out in the wrong number of columns, which comes out as garbage.
        self:writeCompressedPic(asset.backLabel, BACK_PIC_TILES,
          "battle/back/" .. asset.back .. ".png")
        back = asset.back
      end

      -- EvosAttacksPointers is `table_width 2`, i.e. plain `dw` pointers, and
      -- the blobs sit in the same bank as the table (main.asm's "Evolutions
      -- and Attacks" section) -- there is no bank byte to read.
      local evoAddress = self.rom:word(
        evos.bank, evos.address + (index - 1) * 2)
      local evolutions, levelMoves = self:readEvosAttacks(evos.bank, evoAddress)

      -- Egg moves (data/pokemon/egg_moves.asm): EggMovePointers is a `dw` per
      -- species into its OWN bank -- GetEggMove reads the pointer with
      -- BANK(EggMovePointers) and then the list with BANK("Egg Moves"), and on
      -- Gold those are the same bank.  A species with none points at
      -- NoEggMoves, which is a bare `db -1`, so it comes out as an empty list
      -- rather than as nil: "this was extracted and there are none" is a
      -- different claim from "this was never extracted".
      local eggMoves = {}
      if eggMovePointers then
        local listAddr = self.rom:word(
          eggMovePointers.bank, eggMovePointers.address + (index - 1) * 2)
        for offset = 0, 15 do
          local move = self.rom:byte(eggMovePointers.bank, listAddr + offset)
          if move == 0xff then break end
          eggMoves[#eggMoves + 1] = moveOrder[move] or move
        end
      end

      -- BASE_TMHM is (NUM_TM_HM + 7) / 8 bytes, bit i of byte n meaning
      -- TM/HM number n * 8 + i + 1 (the tmhm macro's layout).
      local tmhmRaw = { row[25], row[26], row[27], row[28],
        row[29], row[30], row[31], row[32] }
      local tmhm = {}
      for byteIndex, byteValue in ipairs(tmhmRaw) do
        for bit = 0, 7 do
          if math.floor(byteValue / 2 ^ bit) % 2 == 1 then
            local number = (byteIndex - 1) * 8 + bit + 1
            local move = tmhmList[number]
            if move then tmhm[#tmhm + 1] = move end
          end
        end
      end

      out[species] = {
        id = species, index = index, dex = index, name = name,
        source = ("ROM:BaseData[%d]"):format(index),
        baseStats = {
          hp = row[2], attack = row[3], defense = row[4], speed = row[5],
          specialAttack = row[6], specialDefense = row[7],
        },
        types = { typeById[row[8]] or row[8], typeById[row[9]] or row[9] },
        catchRate = row[10], baseExp = row[11],
        items = { itemOrder[row[12]], itemOrder[row[13]] },
        -- Gender ratio is a raw threshold: a DV roll under it is female, so
        -- GENDER_F0 = 0 is male-only and $fe (GENDER_F100) female-only.
        genderRatio = row[14],
        eggSteps = row[16],
        picSize = row[18] % 16,
        growthRateId = row[23],
        growthRate = growthOrder[row[23] + 1],
        -- One nibble per egg group (dn EGG_x, EGG_y).
        eggGroups = {
          eggGroupOrder[math.floor(row[24] / 16)],
          eggGroupOrder[row[24] % 16],
        },
        eggGroupsRaw = row[24],
        tmhmRaw = tmhmRaw,
        tmhm = tmhm,
        evolutions = evolutions,
        levelMoves = levelMoves,
        eggMoves = eggMoves,
        spriteFront = front and ("assets/generated/battle/front/" .. front .. ".png") or nil,
        spriteBack = back and ("assets/generated/battle/back/" .. back .. ".png") or nil,
      }
    end
    self:tick("Pokemon", index, #speciesOrder)
  end
  -- UnownPicPointers: 26 rows of `dba_pics front, back` -- a three-byte far
  -- pointer each -- one per letter.  PokemonPicPointers' UNOWN row is only
  -- the A form, so without this table the other twenty-five letters have no
  -- pic at all.  Both pics are the usual lz3 column-major blobs.
  if self.symbols["UnownPicPointers"] and out.UNOWN then
    local symbol = self:symbol("UnownPicPointers")
    local letters = {}
    local tiles = out.UNOWN.picSize or 6
    for index = 0, 25 do
      local letter = string.char(string.byte("A") + index)
      local base = symbol.address + index * 6
      local entry = {}
      local function readPic(offset, size, folder, key)
        local bank = FIX_PIC_BANK[self.rom:byte(symbol.bank, base + offset)]
          or self.rom:byte(symbol.bank, base + offset)
        local address = self.rom:word(symbol.bank, base + offset + 1)
        local rel = ("battle/%s/unown_%s.png"):format(folder, letter:lower())
        local ok, err = pcall(function()
          -- GetLZByte bumps the bank and drops back to $4000 when the read
          -- pointer passes $8000, so a pic near the top of its bank keeps
          -- going into the next one.
          local compressed = self.rom:bytes(bank, address, 0x8000 - address)
          local nextBank = self.rom:bytes(bank + 1, 0x4000, 0x4000)
          for _, byte in ipairs(nextBank) do
            compressed[#compressed + 1] = byte
          end
          local pixels = Rom.decompressLz3(compressed)
          local pixelSize = size * 8
          local byteLength = pixelSize * pixelSize / 4
          while #pixels < byteLength do pixels[#pixels + 1] = 0 end
          while #pixels > byteLength do table.remove(pixels) end
          pixels = ImageWriter.columnsToRows(pixels, size, size)
          self:write2bpp(pixels, pixelSize, pixelSize, rel)
        end)
        if ok then
          entry[key] = "assets/generated/" .. rel
        else
          self:trace(("unown %s %s: %s"):format(letter, key, tostring(err)))
        end
      end
      readPic(0, tiles, "front", "spriteFront")
      readPic(3, 6, "back", "spriteBack")
      letters[letter] = entry
    end
    out.UNOWN.letters = letters
    -- The species' own pics: letter A, which is what the cart shows when
    -- nothing has picked a form yet (GetUnownLetter defaults to it).
    out.UNOWN.spriteFront = out.UNOWN.spriteFront
      or (letters.A and letters.A.spriteFront)
    out.UNOWN.spriteBack = out.UNOWN.spriteBack
      or (letters.A and letters.A.spriteBack)
  end

  self:write("pokemon", out)
  return out
end

-- Title screen: TitleScreenGFX1 -> vTiles2 (BG ids $00-$7F), GFX2 ->
-- vTiles1 (ids $80+), then LoadTitleScreenTilemap streams
-- TitleScreenTilemap (gfx/title/logo.tilemap) into the BG map until $FF.
-- Same class of trap as Yellow -- never trust a naive atlas stack for the
-- on-screen image (see RomExtractor:extractYellowTitleArt).  Ho-Oh is OBJ
-- (TitleScreenGFX4 @ vTiles0); trail tiles (GFX3) are animated OAM.
-- FillTitleScreenPals / title_bg_gold.pal colorize BG zones; title_fg.pal
-- tints Ho-Oh.  Clouds (rows 11+) scroll via LYOverrides in retail.
function RomExtractorGen2:extractTitle()
  self:beginStage("Title screen")

  local function tilesFrom2bpp(raw, transparent)
    local tiles = {}
    for offset = 1, #raw - (#raw % 16), 16 do
      local one = {}
      for i = offset, offset + 15 do one[#one + 1] = raw[i] end
      tiles[#tiles + 1] = ImageWriter.decode2bpp(one, 8, 8, transparent)
    end
    return tiles
  end

  local function blitSprite(target, tile, tx, ty)
    if not tile then return end
    for y = 0, 7 do
      for x = 0, 7 do
        local r, g, b, a = tile:getPixel(x, y)
        if a ~= 0 then target:setPixel(tx + x, ty + y, r, g, b, a) end
      end
    end
  end

  local function shadeOf(r)
    if r > 0.9 then return 0 end
    if r > 0.5 then return 1 end
    if r > 0.2 then return 2 end
    return 3
  end

  -- pret gfx/title/title_bg_gold.pal / title_fg.pal (5 BG pals, 2 OBJ pals).
  local BG_PALS = {
    { { 31, 31, 31 }, { 18, 23, 31 }, { 15, 20, 31 }, { 0, 0, 0 } },
    { { 31, 21, 0 }, { 12, 14, 12 }, { 15, 20, 31 }, { 0, 0, 17 } },
    { { 31, 31, 31 }, { 31, 0, 0 }, { 15, 20, 31 }, { 0, 0, 0 } },
    { { 31, 31, 31 }, { 29, 25, 0 }, { 15, 20, 31 }, { 17, 10, 1 } },
    { { 31, 31, 31 }, { 23, 26, 31 }, { 18, 23, 31 }, { 0, 0, 0 } },
  }
  -- title_fg.pal: pal 0 = Ho-Oh silhouette (shades 1-3 are the same brown);
  -- pal 1 = gold trail sparks (OAM_PAL1 on GSTitleTrail).
  local OBJ_HOOH = {
    { 31, 31, 31 }, { 7, 6, 3 }, { 7, 6, 3 }, { 7, 6, 3 },
  }
  local OBJ_TRAIL = {
    { 31, 31, 31 }, { 31, 31, 0 }, { 26, 22, 0 }, { 0, 0, 0 },
  }

  local function palColor(pal, shade)
    local c = pal[shade + 1] or pal[4]
    return c[1] / 31, c[2] / 31, c[3] / 31, 1
  end

  -- LoadTitleScreenPals' non-CGB branch (engine/movie/title.asm) is what the
  -- greyscale set has to be baked through, and Gold's registers are not the
  -- identity: rBGP is %11011000, so the BG's colours 1 and 2 come out the
  -- OTHER WAY ROUND from the shade the tile stores, and rOBP0 is %11111111 --
  -- all four of Ho-Oh's colours map to shade 3, which is why the bird is a
  -- solid BLACK silhouette on a monochrome screen rather than the shaded pose
  -- a straight decode gives.  rOBP1 (%11111000) carries the gold trail.
  local DMG_BGP = { 0, 2, 1, 3 }
  local DMG_OBP0 = { 3, 3, 3, 3 }
  local DMG_OBP1 = { 0, 2, 3, 3 }
  -- ImageWriter's four hardware shades, by shade number.
  local DMG_SHADE = { 1, 2 / 3, 1 / 3, 0 }

  -- Re-shade a decoded image through one of those registers, keeping whatever
  -- alpha the decode gave it (an OBJ's colour 0 is transparent on hardware, so
  -- it never reaches a palette register at all).
  local function throughRegister(image, register)
    local w, h = image:getDimensions()
    local out = ImageWriter.blank(w, h, 0, 0, 0, 0)
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, _, _, a = image:getPixel(x, y)
        if a ~= 0 then
          local v = DMG_SHADE[register[shadeOf(r) + 1] + 1]
          out:setPixel(x, y, v, v, v, 1)
        end
      end
    end
    return out
  end

  -- FillTitleScreenPals (engine/movie/title.asm): pal 1 on rows 0-6,
  -- pal 3 on the GOLD VERSION strip (row 6, cols 5-14), pal 4 on rows 12+.
  local function bgPalAt(col, row)
    if row >= 12 then return 4 end
    if row == 6 and col >= 5 and col <= 14 then return 3 end
    if row <= 6 then return 1 end
    return 0
  end

  local function colorize(image, palFor)
    local w, h = image:getDimensions()
    local out = ImageWriter.blank(w, h, 0, 0, 0, 1)
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r, g, b, a = image:getPixel(x, y)
        if a == 0 then
          out:setPixel(x, y, 0, 0, 0, 0)
        else
          local pal = palFor(x, y)
          local cr, cg, cb = palColor(pal, shadeOf(r))
          out:setPixel(x, y, cr, cg, cb, 1)
        end
      end
    end
    return out
  end

  local vtiles2 = tilesFrom2bpp(self:decompressLz3Symbol("TitleScreenGFX1"))
  local vtiles1 = tilesFrom2bpp(self:decompressLz3Symbol("TitleScreenGFX2"))
  self:tick("Title screen", 1, 5)

  local function tileFor(id)
    if id < 0x80 then return vtiles2[id + 1] end
    return vtiles1[id - 0x80 + 1]
  end

  -- TILEMAP_WIDTH = 32; visible screen is 20x18.  Bytes stream linearly
  -- into vBGMap until the $FF terminator (engine/movie/title.asm).
  local map = self:symbol("TitleScreenTilemap")
  local screen = ImageWriter.blank(160, 144, 1, 1, 1, 1)
  local index = 0
  while true do
    local id = self.rom:byte(map.bank, map.address + index)
    if id == 0xFF then break end
    local col = index % 32
    local row = math.floor(index / 32)
    index = index + 1
    if col < 20 and row < 18 then
      local tile = tileFor(id)
      if tile then ImageWriter.blit(screen, tile, col * 8, row * 8) end
    end
  end

  local colored = colorize(screen, function(x, y)
    return BG_PALS[bgPalAt(math.floor(x / 8), math.floor(y / 8)) + 1]
  end)
  self:save(colored, "title/title_screen.png")
  -- ...and the same composition BEFORE colorize.  Unlike every other Gen 2
  -- sheet the title's are baked with their colours in, because the screen is
  -- one tilemap with a hand-written per-region palette map rather than a
  -- tileset the renderer can colour per tile.  That leaves the COLOR option
  -- nothing to substitute, so the grey source is kept alongside: under DMG and
  -- CLASSIC it IS the picture, and under GBC it is simply unused.  It goes
  -- through rBGP rather than out of the decoder raw, or the logo's two middle
  -- shades read inverted against the colour sheet.
  local screenGray = throughRegister(screen, DMG_BGP)
  self:save(screenGray, "title/title_screen_gray.png")
  -- Cloud band for ScrollTitleScreenClouds (rows 11-16).
  local clouds = ImageWriter.blank(160, 48, 0, 0, 0, 1)
  ImageWriter.blit(clouds, colored, 0, 0, 0, 88, 160, 48)
  self:save(clouds, "title/clouds.png")
  local cloudsGray = ImageWriter.blank(160, 48, 0, 0, 0, 1)
  ImageWriter.blit(cloudsGray, screenGray, 0, 0, 0, 88, 160, 48)
  self:save(cloudsGray, "title/clouds_gray.png")
  -- Logo strip (rows 0-6): readiness marker.
  local logo = ImageWriter.blank(160, 56, 0, 0, 0, 1)
  ImageWriter.blit(logo, colored, 0, 0, 0, 0, 160, 56)
  self:save(logo, "title/pokemon_logo.png")
  self:tick("Title screen", 2, 5)

  -- Ho-Oh frames from OAMData_GSIntroHoOh1..5 (data/sprite_anims/oam.asm).
  local hoohTiles = tilesFrom2bpp(self:decompressLz3Symbol("TitleScreenGFX4"), true)
  local HOOH_FRAMES = {
    { -- 1
      { -4, -1, 0, 0, 0x00 }, { -3, -2, 0, 0, 0x02 }, { -3, 0, 0, 0, 0x04 },
      { -2, -3, 0, 0, 0x06 }, { -2, -1, 0, 0, 0x08 }, { -2, 1, 0, 0, 0x0a },
      { -1, -3, 0, 0, 0x0c }, { -1, -1, 0, 0, 0x0e }, { -1, 1, 0, 0, 0x10 },
      { 0, -3, 0, 0, 0x12 }, { 0, -1, 0, 0, 0x14 }, { 0, 1, 0, 0, 0x16 },
      { 1, -3, 0, 0, 0x18 }, { 1, -1, 0, 0, 0x1a }, { 1, 1, 0, 0, 0x1c },
      { 2, -1, 0, 0, 0x1e }, { 2, 1, 0, 0, 0x20 },
      { 3, -2, 0, 0, 0x22 }, { 3, 0, 0, 0, 0x24 },
    },
    { -- 2
      { -4, -1, 0, 0, 0x00 }, { -3, -2, 0, 0, 0x02 }, { -3, 0, 0, 0, 0x04 },
      { -2, -1, 0, 0, 0x26 }, { -2, 1, 0, 0, 0x0a },
      { -1, -3, 0, 0, 0x28 }, { -1, -1, 0, 0, 0x2a }, { -1, 1, 0, 0, 0x10 },
      { 0, -1, 0, 0, 0x2c }, { 0, 1, 0, 0, 0x16 },
      { 1, -1, 0, 0, 0x30 }, { 1, 1, 0, 0, 0x1c },
      { 2, -1, 0, 0, 0x1e }, { 2, 1, 0, 0, 0x20 },
      { 3, -2, 0, 0, 0x22 }, { 3, 0, 0, 0, 0x24 },
    },
    { -- 3
      { -4, -1, 0, 0, 0x00 }, { -3, -2, 0, 0, 0x02 }, { -3, 0, 0, 0, 0x32 },
      { -2, -1, 0, 0, 0x34 }, { -2, 1, 0, 0, 0x36 },
      { -1, -1, 0, 0, 0x38 }, { -1, 1, 0, 0, 0x3a },
      { 0, -1, 0, 0, 0x3c }, { 0, 1, 0, 0, 0x3e },
      { 1, -1, 0, 0, 0x30 }, { 1, 1, 0, 0, 0x1c },
      { 2, -1, 0, 0, 0x1e }, { 2, 1, 0, 0, 0x20 },
      { 3, -2, 0, 0, 0x22 }, { 3, 0, 0, 0, 0x24 },
    },
    { -- 4
      { -4, -1, 0, 0, 0x00 }, { -3, -2, 0, 0, 0x02 }, { -3, 0, 0, 0, 0x04 },
      { -2, -1, 0, 0, 0x40 }, { -2, 1, 0, 0, 0x42 }, { -2, 3, 0, 0, 0x44 },
      { -1, -1, 0, 0, 0x46 }, { -1, 1, 0, 0, 0x48 }, { -1, 3, 0, 0, 0x4a },
      { 0, -1, 0, 0, 0x4c }, { 0, 1, 0, 0, 0x4e },
      { 1, -1, 0, 0, 0x30 }, { 1, 1, 0, 0, 0x1c },
      { 2, -1, 0, 0, 0x1e }, { 2, 1, 0, 0, 0x20 },
      { 3, -2, 0, 0, 0x22 }, { 3, 0, 0, 0, 0x24 },
    },
    { -- 5
      { -4, -1, 0, 0, 0x00 }, { -3, -2, 0, 0, 0x02 }, { -3, 0, 0, 0, 0x04 },
      { -2, -1, 0, 0, 0x50 }, { -2, 1, 0, 0, 0x0a },
      { -1, -3, 0, 0, 0x52 }, { -1, -1, 0, 0, 0x54 }, { -1, 1, 0, 0, 0x10 },
      { 0, -3, 0, 0, 0x56 }, { 0, -1, 0, 0, 0x2e }, { 0, 1, 0, 0, 0x16 },
      { 1, -1, 0, 0, 0x30 }, { 1, 1, 0, 0, 0x1c },
      { 2, -1, 0, 0, 0x1e }, { 2, 1, 0, 0, 0x20 },
      { 3, -2, 0, 0, 0x22 }, { 3, 0, 0, 0, 0x24 },
    },
  }
  -- Frameset_GSIntroHoOhLugia (Gold): 1,2,3,4,3,5 with these durations.
  local HOOH_SEQUENCE = {
    { 1, 10 }, { 2, 9 }, { 3, 10 }, { 4, 10 }, { 3, 9 }, { 5, 10 },
  }
  local hoohPaths, hoohGrayPaths = {}, {}
  local originX, originY = 32, 24
  for fi, oam in ipairs(HOOH_FRAMES) do
    -- The pose starts EMPTY, not white: an OBJ's colour 0 is transparent
    -- wherever it falls, so a gap enclosed by the bird shows the sky through
    -- exactly like one outside it, and there is no matte to flood-fill.
    local pose = ImageWriter.blank(64, 64, 0, 0, 0, 0)
    for _, spr in ipairs(oam) do
      local px = originX + spr[1] * 8 + spr[3]
      local py = originY + spr[2] * 8 + spr[4]
      blitSprite(pose, hoohTiles[spr[5] + 1], px, py)
      blitSprite(pose, hoohTiles[spr[5] + 2], px, py + 8)
    end
    local tinted = colorize(pose, function() return OBJ_HOOH end)
    local rel = ("title/hooh_%d.png"):format(fi)
    self:save(tinted, rel)
    hoohPaths[fi] = "assets/generated/" .. rel
    -- ...and the same pose through rOBP0, which is the black silhouette.
    local grayRel = ("title/hooh_%d_gray.png"):format(fi)
    self:save(throughRegister(pose, DMG_OBP0), grayRel)
    hoohGrayPaths[fi] = "assets/generated/" .. grayRel
    if fi == 1 then
      -- Readiness marker + older stubs expect hooh.png == frame 1.
      self:save(tinted, "title/hooh.png")
    end
  end
  self:tick("Title screen", 3, 5)

  -- Trail: TitleScreenGFX3 is raw 2bpp (8 tiles); Gold OAM uses one 8x16
  -- on OAM_PAL1 (gold), not the Ho-Oh silhouette pal.
  local trailSym = self:symbol("TitleScreenGFX3")
  local trailRaw = self.rom:bytes(trailSym.bank, trailSym.address, 8 * 16)
  local trailTiles = tilesFrom2bpp(trailRaw, true)
  local trail = ImageWriter.blank(8, 16, 0, 0, 0, 0)
  blitSprite(trail, trailTiles[1], 0, 0)
  blitSprite(trail, trailTiles[2], 0, 8)
  local trailTint = colorize(trail, function() return OBJ_TRAIL end)
  self:save(trailTint, "title/trail.png")
  self:save(throughRegister(trail, DMG_OBP1), "title/trail_gray.png")
  self:tick("Title screen", 4, 5)

  -- Copyright splash (data/copyright.asm PlaceString over CopyrightGFX).
  local copyright = self:symbol("CopyrightGFX")
  local copyRaw = self.rom:bytes(copyright.bank, copyright.address, 30 * 16)
  local copyTiles = tilesFrom2bpp(copyRaw)
  self:write2bpp(copyRaw, 240, 8, "title/copyright.png")
  local copyLines = {
    { 0x60, 0x61, 0x62, 0x63, 0x7a, 0x7b, 0x7c, 0x7d,
      0x65, 0x66, 0x67, 0x68, 0x69, 0x6a },
    { 0x60, 0x61, 0x62, 0x63, 0x7a, 0x7b, 0x7c, 0x7d,
      0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72 },
    { 0x60, 0x61, 0x62, 0x63, 0x7a, 0x7b, 0x7c, 0x7d,
      0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x71, 0x72 },
  }
  local splash = ImageWriter.blank(160, 144, 1, 1, 1, 1)
  for li, line in ipairs(copyLines) do
    local y = (7 + (li - 1)) * 8 -- hlcoord 2, 7 + next
    local x = 2 * 8
    for _, tid in ipairs(line) do
      local tile = copyTiles[tid - 0x60 + 1]
      if tile then ImageWriter.blit(splash, tile, x, y) end
      x = x + 8
    end
  end
  self:save(splash, "title/copyright_splash.png")
  self:tick("Title screen", 5, 5)

  local data = {
    generation = 2,
    layout = "gold_title",
    source = "ROM:TitleScreenTilemap + TitleScreenGFX1/2/3/4, CopyrightGFX",
    screen = "assets/generated/title/title_screen.png",
    clouds = "assets/generated/title/clouds.png",
    image = "assets/generated/title/pokemon_logo.png",
    hooh = "assets/generated/title/hooh.png",
    hoohFrames = hoohPaths,
    -- The uncoloured set the COLOR option's DMG and CLASSIC modes draw.
    screenGray = "assets/generated/title/title_screen_gray.png",
    cloudsGray = "assets/generated/title/clouds_gray.png",
    hoohFramesGray = hoohGrayPaths,
    trailGray = "assets/generated/title/trail_gray.png",
    -- Frameset_GSIntroHoOhLugia (Gold), frame index 1-based + duration frames.
    hoohSequence = HOOH_SEQUENCE,
    -- `depixel 12, 11` (engine/movie/title.asm).  Two traps, and the port had
    -- fallen into both, which is what put Ho-Oh off-centre:
    --  * ldpixel's own comment calls its first tile argument the X one and is
    --    WRONG.  It builds `lb de, arg1 * 8, arg2 * 8`, and
    --    _InitSpriteAnimStruct takes "x=e, y=d" -- so arg1 is the Y tile.
    --    NamingScreen .InitCursor proves it: it overrides `d` alone to move
    --    the cursor two rows up on the box screen.  So this is x 88, y 96.
    --  * those are OAM coordinates, which are biased; a drawn object sits at
    --    (x - 8, y - 16) on screen.
    -- The pose canvas holds its own origin at (32, 24), so the sheet's corner
    -- is (88 - 8 - 32, 96 - 16 - 24) -- and the bird's 64px width then lands
    -- centred on the screen, 48 to 112.
    hoohX = 48,
    hoohY = 56,
    trail = "assets/generated/title/trail.png",
    copyright = "assets/generated/title/copyright.png",
    copyrightSplash = "assets/generated/title/copyright_splash.png",
    -- ScrollTitleScreenClouds: Gold decrements the cloud-band SCX every
    -- 8 vblanks, so the strip slides 1px right.  Silver does the same
    -- decrement every frame.
    cloudScrollEvery = 8,
    cloudY = 88,
  }
  self:write("title", data)
  return data
end

-- The credits roll's graphics (engine/movie/credits.asm).  Four things come
-- out of the ROM here, and the shapes are all fixed by the load calls at the
-- top of `Credits::`:
--
--   CreditsBorderGFX   9 tiles -> vTiles2 $20.  DrawCreditsBorder writes four
--                      running ids five times across a row, starting at $24
--                      for row 4 and $20 for row 13 -- so tiles 5-8 of the
--                      strip are the TOP border and tiles 1-4 the bottom.
--                      The 9th, $28, is the tile ConstructCreditsTilemap
--                      ByteFills the whole screen with before anything else,
--                      which makes it the banner's backdrop.
--   Credits<Mon>GFX    4x4-tile frames stacked: three for Bellossom, Togepi
--                      and Elekid, four for Sentret (Credits_LoadBorderGFX's
--                      .Frames offsets run to +48 tiles for Sentret alone).
--                      pret builds these WITHOUT --columns, so the 2bpp
--                      stream is already row-major over the whole sheet and
--                      a 32 x (32 * frames) decode is the pret PNG.
--   TheEndGFX          16 tiles, its own "The End" section in gfx/misc.asm,
--                      loaded to $40 and placed 8 wide on rows 8 and 9.
--   CreditsPalettes    gfx/credits/credits.pal, six four-colour sets.
--                      GetCreditsPalette masks the scene with %11, so only
--                      the first four are reachable from the script, but all
--                      six are written out because the block is one table.
--
-- Everything is tolerated rather than required: a manifest built before these
-- symbols were listed still imports, it just leaves the credits on the mon
-- icon fallback src/ui/gen2/Credits.lua carries.
local CREDITS_SCENES = {
  { species = "BELLOSSOM", label = "CreditsBellossomGFX", frames = 3 },
  { species = "TOGEPI", label = "CreditsTogepiGFX", frames = 3 },
  { species = "ELEKID", label = "CreditsElekidGFX", frames = 3 },
  { species = "SENTRET", label = "CreditsSentretGFX", frames = 4 },
}
local CREDITS_BORDER_TILES = 9
local CREDITS_THEEND_TILES = 16

function RomExtractorGen2:extractCredits()
  self:beginStage("Credits")
  local steps = #CREDITS_SCENES + 3
  local data = {
    generation = 2,
    source = "ROM:CreditsBorderGFX + Credits<Mon>GFX + TheEndGFX"
      .. " + CreditsPalettes",
  }

  if self.symbols["CreditsBorderGFX"] then
    local border = self:symbol("CreditsBorderGFX")
    self:write2bpp(self.rom:bytes(border.bank, border.address,
      CREDITS_BORDER_TILES * 16), CREDITS_BORDER_TILES * 8, 8,
      "credits/border.png")
    data.border = "assets/generated/credits/border.png"
    data.borderTiles = CREDITS_BORDER_TILES
    -- 1-based tile columns of the strip, as DrawCreditsBorder's start ids.
    data.borderTopTile = 5
    data.borderBottomTile = 1
    data.borderFillTile = 9
  end
  self:tick("Credits", 1, steps)

  if self.symbols["TheEndGFX"] then
    local theEnd = self:symbol("TheEndGFX")
    self:write2bpp(self.rom:bytes(theEnd.bank, theEnd.address,
      CREDITS_THEEND_TILES * 16), 64, 16, "credits/theend.png")
    data.theEnd = "assets/generated/credits/theend.png"
    -- Credits_TheEnd: hlcoord 6, 8 and 6, 9, eight tiles apiece.
    data.theEndX, data.theEndY, data.theEndWidth = 6, 8, 8
  end
  self:tick("Credits", 2, steps)

  local scenes = {}
  for index, scene in ipairs(CREDITS_SCENES) do
    if self.symbols[scene.label] then
      local sym = self:symbol(scene.label)
      local raw = self.rom:bytes(sym.bank, sym.address, scene.frames * 16 * 16)
      local rel = ("credits/%s.png"):format(scene.species:lower())
      self:write2bpp(raw, 32, 32 * scene.frames, rel)
      scenes[index] = {
        species = scene.species,
        image = "assets/generated/" .. rel,
        frames = scene.frames,
        width = 32,
        height = 32,
      }
    end
    self:tick("Credits", 2 + index, steps)
  end
  if #scenes == #CREDITS_SCENES then data.scenes = scenes end

  if self.symbols["CreditsPalettes"] then
    local pal = self:symbol("CreditsPalettes")
    local palettes = {}
    for set = 0, 5 do
      palettes[set + 1] = self:colors(pal.bank, pal.address + set * 8, 4)
    end
    data.palettes = palettes
  end
  self:tick("Credits", steps, steps)

  self:write("credits", data)
  return data
end

-- The #DEX diploma's page (engine/events/diploma.asm PlaceDiplomaOnScreen).
-- The certificate is not a text box: the routine decompresses DiplomaGFX into
-- vTiles2 and then CopyBytes' DiplomaPage1Tilemap straight over the whole
-- background before a single string is placed, so the border, the seal and
-- the ribbon are one 20x18 tilemap of cart art.
--
--   DiplomaGFX            gfx/diploma/diploma.2bpp.lz, 112 tiles.  pret
--                         builds it WITHOUT --columns (gfx/lz.mk only sets
--                         LZFLAGS), so the stream is row-major over the 16x7
--                         sheet and a straight 128x56 decode IS the pret PNG.
--   DiplomaPage1Tilemap   gfx/diploma/page1.tilemap, exactly SCREEN_AREA
--                         bytes of tile ids into that sheet.  Page 2 is the
--                         Game Boy Printer's second sheet and is not read
--                         here, the same way PrintDiploma stays stubbed.
--   DiplomaPalettes       gfx/diploma/diploma.pal, eight four-colour sets.
--                         _CGB_Diploma (engine/gfx/cgb_layouts.asm) loads all
--                         eight and then WipeAttrmap zeroes the attrmap, so
--                         set 0 is the one the whole screen actually draws
--                         through; the rest are written out because the block
--                         is one table.
--
-- Tolerated rather than required, like credits: a manifest built before these
-- three symbols were listed still imports, it just leaves src/ui/gen2/
-- Diploma.lua on its placeholder frame.
local DIPLOMA_TILES = 112
local DIPLOMA_SHEET_TILES = 16 -- tiles per row of the sheet
local DIPLOMA_SCREEN_W, DIPLOMA_SCREEN_H = 20, 18
local DIPLOMA_PALETTE_SETS = 8

function RomExtractorGen2:extractDiploma()
  self:beginStage("Diploma")
  local data = {
    generation = 2,
    source = "ROM:DiplomaGFX + DiplomaPage1Tilemap + DiplomaPalettes",
  }

  if self.symbols["DiplomaGFX"] then
    local pixels = self:decompressLz3Symbol("DiplomaGFX")
    local byteLength = DIPLOMA_TILES * 16
    while #pixels < byteLength do pixels[#pixels + 1] = 0 end
    while #pixels > byteLength do table.remove(pixels) end
    self:write2bpp(pixels, DIPLOMA_SHEET_TILES * 8,
      DIPLOMA_TILES / DIPLOMA_SHEET_TILES * 8, "diploma/diploma.png")
    data.image = "assets/generated/diploma/diploma.png"
    data.tiles = DIPLOMA_TILES
    data.sheetTiles = DIPLOMA_SHEET_TILES
  end
  self:tick("Diploma", 1, 3)

  if self.symbols["DiplomaPage1Tilemap"] then
    local sym = self:symbol("DiplomaPage1Tilemap")
    local raw = self.rom:bytes(sym.bank, sym.address,
      DIPLOMA_SCREEN_W * DIPLOMA_SCREEN_H)
    -- Kept flat, in the row-major order CopyBytes writes it, because that is
    -- what the drawing side indexes with row * SCREEN_WIDTH + column.
    data.page1 = raw
    data.width = DIPLOMA_SCREEN_W
    data.height = DIPLOMA_SCREEN_H
  end
  self:tick("Diploma", 2, 3)

  if self.symbols["DiplomaPalettes"] then
    local pal = self:symbol("DiplomaPalettes")
    local palettes = {}
    for set = 0, DIPLOMA_PALETTE_SETS - 1 do
      palettes[set + 1] = self:colors(pal.bank, pal.address + set * 8, 4)
    end
    data.palettes = palettes
  end
  self:tick("Diploma", 3, 3)

  self:write("diploma", data)
  return data
end

-- The trade animation's art (engine/movie/trade_animation.asm, gfx/trade/).
-- Everything the cable-and-ball sequence draws that is not a frontpic or a
-- mon icon comes out of nine labels at the bottom of that file, and the
-- animation is a BACKGROUND that scrolls plus a handful of OAM objects, so
-- the two halves are extracted differently:
--
--   TradeGameBoyLZ        gfx/trade/game_boy_cable.2bpp.lz, which the
--                         Makefile builds as game_boy.2bpp (--remove-
--                         duplicates) then link_cable.2bpp run together.  It
--                         decompresses to 49 tiles into vTiles2 tile $31, and
--                         because Gen 2 runs the BG in $8800 mode a BG id of
--                         N < $80 IS vTiles2 tile N: the two tilemaps below
--                         and the loose cable ids the jumptable ByteFills
--                         ($5b, $5d, $5f, $60, $61) all index this one sheet
--                         from $31.  Written flat with its base tile beside
--                         it rather than re-split, since nothing on the
--                         drawing side wants the Game Boy and the cable as
--                         separate sheets.
--   TradeGameBoyTilemap   gfx/trade/game_boy.tilemap, 6x8 ids, stamped at
--                         hlcoord 3, 2 in state 0 and hlcoord 10, 6 in
--                         state 2 (TradeAnim_CopyTradeGameBoyTilemap).
--   TradeLinkTubeTilemap  gfx/trade/link_cable.tilemap, 12x3, stamped at
--                         hlcoord 8, 2 by TradeAnim_EnterLinkTube1.
--
-- The objects are all mirrored quadrants, which is why so few tiles draw so
-- much (data/sprite_anims/oam.asm):
--
--   TradeBallGFX     6 tiles.  Frame 1 is .OAMData_TradePokeBall1: tiles 0
--                    and 1 are the ball's LEFT half and the right half is the
--                    same two X-flipped.  Frame 2 is .OAMData_MagnetTrainRed,
--                    four distinct tiles in a plain 2x2.  pret's ball.png is
--                    16x32 because it holds the blank right half of frame 1;
--                    the 2bpp is built with --remove-whitespace, so the ROM
--                    has 6 tiles and not 8 and this writes them as a strip
--                    rather than inventing the two blanks back.
--   TradePoofGFX     12 tiles, three .OAMData_TradePoofBubble frames of 4;
--                    each frame is a 2x2 quadrant mirrored into a 32x32
--                    object, so the sheet is pret's own 16x48.
--   TradeCableGFX    2 tiles, one per .OAMData_TradeTubeBulge frame: the
--                    bulge that travels inside the tube, one quadrant tile
--                    mirrored into 16x16.  Named "cable" in gfx/trade/ but
--                    loaded at vTiles0 tile $74, which is where the bulge's
--                    $12/$13 dictionary offsets land.
--   TradeBubbleGFX   4 tiles, the quadrant of the 32x32 bubble the mon icon
--                    rides in (SPRITE_ANIM_OAMSET_TRADEMON_BUBBLE, offset
--                    $10 off the $62 dictionary base).
--   TradeArrowRightGFX / TradeArrowLeftGFX
--                    one BG tile each, ByteFilled six across at hlcoord 7, 2
--                    of the window map by TradeAnim_PlaceTrademonStatsOnTube-
--                    Anim to point the trade the way it is going.  Two
--                    symbols, one two-tile sheet.
--
-- Object tiles are written with colour 0 transparent, because that is what
-- colour 0 means to an OBJ; the BG sheets keep it as white.
--
-- Tolerated rather than required, like credits and the diploma: a manifest
-- built before these labels were listed still imports, it just leaves
-- src/ui/gen2/TradeAnim.lua drawing its placeholder shapes.
local TRADE_BASE_TILE = 0x31
local TRADE_SCENE_TILES = 49
local TRADE_SHEET_TILES = 7 -- 49 tiles is exactly 7x7, so nothing is padded
local TRADE_GAMEBOY_W, TRADE_GAMEBOY_H = 6, 8
local TRADE_TUBE_W, TRADE_TUBE_H = 12, 3
local TRADE_BALL_TILES = 6
local TRADE_POOF_TILES = 12
local TRADE_BULGE_TILES = 2
local TRADE_BUBBLE_TILES = 4

function RomExtractorGen2:extractTrade()
  self:beginStage("Trade animation")
  local data = {
    generation = 2,
    source = "ROM:TradeGameBoyLZ + TradeGameBoyTilemap + TradeLinkTubeTilemap"
      .. " + TradeBallGFX + TradePoofGFX + TradeCableGFX + TradeBubbleGFX"
      .. " + TradeArrowRightGFX + TradeArrowLeftGFX",
  }

  if self.symbols["TradeGameBoyLZ"] then
    local pixels = self:decompressLz3Symbol("TradeGameBoyLZ")
    local byteLength = TRADE_SCENE_TILES * 16
    while #pixels < byteLength do pixels[#pixels + 1] = 0 end
    while #pixels > byteLength do table.remove(pixels) end
    self:write2bpp(pixels, TRADE_SHEET_TILES * 8, TRADE_SHEET_TILES * 8,
      "trade/scene.png")
    data.image = "assets/generated/trade/scene.png"
    data.tiles = TRADE_SCENE_TILES
    data.sheetTiles = TRADE_SHEET_TILES
    -- The id a tilemap byte carries, minus this, is the tile's index into
    -- the sheet above.
    data.baseTile = TRADE_BASE_TILE
  end
  self:tick("Trade animation", 1, 3)

  -- Both tilemaps stay flat, in the order TradeAnim_CopyBoxFromDEtoHL walks
  -- them (row by row), because that is what the drawing side indexes with
  -- row * width + column.
  local function tilemap(label, width, height)
    if not self.symbols[label] then return nil end
    local sym = self:symbol(label)
    return {
      width = width,
      height = height,
      tiles = self.rom:bytes(sym.bank, sym.address, width * height),
    }
  end
  data.gameBoy = tilemap("TradeGameBoyTilemap", TRADE_GAMEBOY_W,
    TRADE_GAMEBOY_H)
  data.tube = tilemap("TradeLinkTubeTilemap", TRADE_TUBE_W, TRADE_TUBE_H)
  self:tick("Trade animation", 2, 3)

  local function sprite(label, tiles, across, relative)
    if not self.symbols[label] then return nil end
    local sym = self:symbol(label)
    local raw = self.rom:bytes(sym.bank, sym.address, tiles * 16)
    self:write2bpp(raw, across * 8, tiles / across * 8, relative, true)
    return { image = "assets/generated/" .. relative, tiles = tiles,
             sheetTiles = across }
  end
  data.ball = sprite("TradeBallGFX", TRADE_BALL_TILES, 1, "trade/ball.png")
  data.poof = sprite("TradePoofGFX", TRADE_POOF_TILES, 2, "trade/poof.png")
  data.bulge = sprite("TradeCableGFX", TRADE_BULGE_TILES, 1, "trade/bulge.png")
  data.bubble = sprite("TradeBubbleGFX", TRADE_BUBBLE_TILES, 2,
    "trade/bubble.png")

  -- The arrows are two one-tile symbols, kept in the order the port draws
  -- them: index 0 sends, index 1 receives.  They are background tiles, so
  -- colour 0 stays white.
  if self.symbols["TradeArrowRightGFX"] and self.symbols["TradeArrowLeftGFX"]
  then
    local right = self:symbol("TradeArrowRightGFX")
    local left = self:symbol("TradeArrowLeftGFX")
    local raw = self.rom:bytes(right.bank, right.address, 16)
    for _, byte in ipairs(self.rom:bytes(left.bank, left.address, 16)) do
      raw[#raw + 1] = byte
    end
    self:write2bpp(raw, 8, 16, "trade/arrows.png")
    data.arrows = { image = "assets/generated/trade/arrows.png", tiles = 2,
                    sheetTiles = 1 }
  end
  self:tick("Trade animation", 3, 3)

  self:write("trade", data)
  return data
end

-- Dump Gen 2 audio banks and wire song/wave/drum metadata for ChipSynth's
-- generation-2 channel driver.  Banks are NOT Gen 1's {2,8,31}.
function RomExtractorGen2:extractAudio(maps)
  self:beginStage("Sound programs")
  local bankOrder = { 0x07, 0x33, 0x3a, 0x3b, 0x3c, 0x3d }
  local chunks = {}
  for index, bank in ipairs(bankOrder) do
    local first = Rom.offset(bank, 0x4000) + 1
    chunks[index] = self.rom.data:sub(first, first + 0x3FFF)
    self:tick("Sound programs", index, #bankOrder + 2)
  end
  local CacheFs = require("src.import.CacheFs")
  local ok, writeError = CacheFs.write(
    "assets/generated/audio/programs.bin", table.concat(chunks))
  if not ok then
    error("could not write audio programs: " .. tostring(writeError))
  end

  local musicOrder = self.manifest.constants.musicOrder or {}
  local songs = {}
  for _, name in ipairs(musicOrder) do
    if name ~= "Music_Nothing" and self.symbols[name] then
      local loc = self.symbols[name]
      songs[name] = { bank = loc[1], address = loc[2], generation = 2 }
    end
  end

  -- Prefer live Music: dba table when a label is missing from the sym embed.
  local musicPtr = self:symbol("Music")
  for index, name in ipairs(musicOrder) do
    if name ~= "Music_Nothing" and not songs[name] then
      local row = self.rom:bytes(
        musicPtr.bank, musicPtr.address + (index - 1) * 3, 3)
      songs[name] = {
        bank = row[1],
        address = row[2] + row[3] * 256,
        generation = 2,
      }
    end
  end

  local wave = self:symbol("WaveSamples")
  local drums = self:symbol("Drumkits")
  local mapSongs = {}
  if maps then
    for mapId, def in pairs(maps) do
      local id = def.music
      if type(id) == "number" and id > 0 then
        local label = musicOrder[id + 1]
        if label and songs[label] then
          mapSongs[mapId] = label
        end
      end
    end
  end

  -- SFX pointer table (audio/sfx_pointers.asm): 3-byte dba per SFX_* id.
  local sfxOrder = self.manifest.constants.sfxOrder or {}
  local sfxPtr = self:symbol("SFX")
  local sfx, fanfares = {}, {}
  local FANFARE_NAMES = {
    Sfx_CaughtMon = true, Sfx_Item = true,
    Sfx_DexFanfare2049 = true, Sfx_DexFanfare5079 = true,
    Sfx_DexFanfare80109 = true, Sfx_Fanfare = true,
  }
  for index, name in ipairs(sfxOrder) do
    local row = self.rom:bytes(
      sfxPtr.bank, sfxPtr.address + (index - 1) * 3, 3)
    local def = {
      bank = row[1],
      address = row[2] + row[3] * 256,
      generation = 2,
    }
    if FANFARE_NAMES[name] then def.fanfare = true end
    sfx[name] = def
  end
  for name in pairs(FANFARE_NAMES) do
    if sfx[name] then fanfares[name] = true end
  end

  -- Cry base headers (Cries:) + per-species PokemonCries (dw index,pitch,length).
  local cryPtr = self:symbol("Cries")
  local cryHeaders = {}
  local NUM_CRIES = 68 -- pret NUM_CRIES
  for i = 0, NUM_CRIES - 1 do
    local row = self.rom:bytes(cryPtr.bank, cryPtr.address + i * 3, 3)
    cryHeaders[i] = {
      bank = row[1],
      address = row[2] + row[3] * 256,
      generation = 2,
    }
  end
  local pokeCryPtr = self:symbol("PokemonCries")
  local speciesOrder = self.manifest.constants.speciesOrder or {}
  local cries = {}
  for index, species in ipairs(speciesOrder) do
    if species ~= "UNOWN" and not tostring(species):match("^UNUSED") then
      local row = self.rom:bytes(
        pokeCryPtr.bank, pokeCryPtr.address + (index - 1) * 6, 6)
      local cryIndex = row[1] + row[2] * 256
      local pitch = row[3] + row[4] * 256
      local length = row[5] + row[6] * 256
      local header = cryHeaders[cryIndex]
      if header then
        cries[species] = {
          header = header,
          pitch = pitch,
          length = length,
        }
      end
    end
  end

  local data = {
    generation = 2,
    runtime = true,
    programFile = "assets/generated/audio/programs.bin",
    bankOrder = bankOrder,
    music = musicPtr,
    songs = songs,
    musicOrder = musicOrder,
    mapSongs = mapSongs,
    sfx = sfx,
    sfxOrder = sfxOrder,
    fanfares = fanfares,
    cries = cries,
    -- ChipSynth Gen 1 shape: one wave bank key; Gen 2 uses WaveSamples.
    waveBanks = {
      ["1"] = { bank = wave.bank, address = wave.address, name = "WaveSamples" },
    },
    drumkits = { bank = drums.bank, address = drums.address, name = "Drumkits" },
    source = "canonical Pokemon Gold ROM sound programs (Gen 2 driver)",
  }
  self:write("audio", data)
  self:tick("Sound programs", #bankOrder + 2, #bankOrder + 2)
  return data
end

-- Decode a Gen 2 text stream (macros/scripts/text.asm) into the port's
-- TextBox markers: \n line, \f page, \v scroll, {PLAYER}/{RIVAL}.
--
-- home/text.asm is TWO interleaved loops and the difference is load bearing:
--
--   DoTextUntilTerminator reads a COMMAND byte, and $50 there is TX_END -- the
--     whole stream stops.
--   TextCommand_START hands over to PlaceString, which prints CHARACTERS until
--     it meets $50 -- which is `@`, the end of that chunk and nothing more.
--
-- So the same byte ends a string or ends the text depending on which loop is
-- holding it, and `line "@"` really does sit inside the chunk `text "..."`
-- opened (a `text` macro emits no terminator of its own).  Reading $50 as
-- "skip" everywhere works for a map string, which ends on `done` ($57), and
-- runs off the end of any string that ends on `text_end` -- which is every
-- string in data/text/*.asm, i.e. everything the phone and the decorations say.
--
-- `buffers`, when a caller passes one, collects the WRAM name behind each
-- TX_RAM in the order they appear.  The decoded string writes every one of
-- them as the same `{STRBUF}` -- the port has one shared string buffer and
-- src/render/TextBox.lua resolves that single token -- but the cart has six,
-- and a line like the trade intro names two DIFFERENT ones.  Recording which
-- is which alongside the text lets a caller fill them in order without
-- changing a marker every screen already reads.
function RomExtractorGen2:decodeGen2Text(bank, address, charmap, buffers)
  local out = {}
  local i = 0
  local hops = 0
  -- false = DoTextUntilTerminator, true = inside PlaceString.
  local inString = false
  while i < 4096 do
    local b = self.rom:byte(bank, address + i)
    if b == 0x50 then
      if not inString then break end -- TX_END
      inString = false               -- `@`: end of this chunk
    elseif b == 0x57 or b == 0x58 then -- DONE / PROMPT, both PlaceString's
      break
    elseif b == 0x00 then
      inString = true -- TX_START
    elseif b == 0x16 and not inString then
      -- TX_FAR: `db TX_FAR / dw addr / db bank` (macros/scripts/text.asm).
      -- The stream CONTINUES at the far address rather than embedding it, and
      -- everything after the pointer in this bank is the next string.  No map
      -- text uses one -- the 620 that do are engine strings, which is why this
      -- only started mattering once the extractor reached banks $09 and $41.
      local farAddr = self.rom:word(bank, address + i + 1)
      local farBank = self.rom:byte(bank, address + i + 3)
      hops = hops + 1
      if hops > 8 or farBank == 0 or farBank > 0x7f
          or farAddr < 0x4000 or farAddr >= 0x8000 then
        break
      end
      -- The loop's own `i = i + 1` runs after this branch, so -1 lands on the
      -- far stream's first byte.
      bank, address, i = farBank, farAddr, -1
    elseif b == 0x01 then
      -- TX_RAM: dw wStringBuffer*; runtime fills via getmonname etc.
      out[#out + 1] = "{STRBUF}"
      if buffers then
        local target = self.rom:word(bank, address + i + 1)
        buffers[#buffers + 1] = TEXT_BUFFERS[target] or target
      end
      i = i + 2
    elseif b == 0x4e or b == 0x4f then
      out[#out + 1] = "\n"
    elseif b == 0x51 then
      out[#out + 1] = "\f"
    elseif b == 0x55 then
      out[#out + 1] = "\v"
    elseif b == 0x52 then
      out[#out + 1] = "{PLAYER}"
    elseif b == 0x53 then
      out[#out + 1] = "{RIVAL}"
    elseif b == 0x54 then
      out[#out + 1] = "POKé"
    elseif b == 0x06 then
      -- TX_PROMPT_BUTTON (e.g. empty _OakText3) : no glyphs.
    elseif b == 0x09 and not inString then
      -- TX_DECIMAL: `dw address / dn bytes, digits` (macros/scripts/text.asm).
      -- PrintNum writes a runtime number here -- the price the Day-Care asks,
      -- the quantity a mart clerk rings up -- so the marker stands in for it
      -- and the call site fills it, the same way {STRBUF} stands in for a
      -- TX_RAM.  Four bytes: the byte AFTER the `dn` is the next command.
      out[#out + 1] = "{NUM}"
      i = i + 3
    elseif b == 0x14 and not inString then
      -- TX_STRINGBUFFER: `db buffer id`.  Another name spliced at runtime, so
      -- it decodes to the same marker TX_RAM does.
      out[#out + 1] = "{STRBUF}"
      i = i + 1
    elseif b == 0x0c and not inString then
      i = i + 1 -- TX_DOTS: `db count`, an animated ellipsis with no glyphs.
    elseif not inString and TEXT_NO_GLYPH[b] then
      -- TX_LOW / TX_SCROLL / TX_PAUSE / TX_WAIT_BUTTON / TX_DAY and the six
      -- TX_SOUND_* jingles: box and timing commands that print nothing.  Read
      -- as characters they came out as whatever glyph the charmap had at that
      -- byte -- `sound_caught_mon` inside _BreedEggHatchText decoded as a
      -- kana -- so they are consumed here rather than printed.
    else
      local ch = charmap[tostring(b)]
      if ch and not ch:match("^<") then
        out[#out + 1] = ch
      elseif ch == "<……>" or b == 0x56 then
        out[#out + 1] = "……"
      elseif not ch then
        out[#out + 1] = ("{BYTE:%02X}"):format(b)
      end
      -- Skip other <$xx> control glyphs from the charmap.
    end
    i = i + 1
  end
  return table.concat(out)
end

local function wordFromArgs(args)
  return (args[1] or 0) + (args[2] or 0) * 0x100
end

-- The `dba` operand every far-reaching opcode carries (farscall, farsjump,
-- farwritetext).  macros/data.asm: `dba` is `dbw BANK(\1), \1`, so the BANK
-- comes FIRST and the address follows little-endian -- the opposite layout
-- from the neighbouring `dab`.  Script_farsjump (engine/overworld/scripting.asm
-- 1190) reads it in that order too: `ld b, a` on the first byte, then l then h.
local function dbaFromArgs(args)
  return (args[1] or 0), (args[2] or 0) + (args[3] or 0) * 0x100
end

local function romAddrOk(bank, address)
  if type(bank) ~= "number" or type(address) ~= "number" then return false end
  if bank < 0 or bank > 0x7f then return false end
  if bank == 0 then return address >= 0 and address < 0x4000 end
  return address >= 0x4000 and address < 0x8000
end

-- The side tables a script command NAMES rather than carries: the phone book,
-- the in-game trades, the elevator's floor labels, and the five decoration
-- descriptions.  Each row's script pointers come back with the rest so
-- extractScriptsAndText can seed its queue from them -- which is the only way
-- into ROM bank $41, where every phone script lives and which no map points at.
--
-- Returns the table that is written as data/generated/events.lua; the caller
-- adds the disassembly.
function RomExtractorGen2:readEventTables()
  local consts = self.manifest.constants
  local charmap = self.manifest.charmap or {}
  local out = {}

  local function name(list, index, fallback)
    if type(list) ~= "table" then return fallback end
    return list[index + 1] or fallback
  end
  local function readName(bank, address, length)
    local ok, str = pcall(self.rom.readString, self.rom,
      bank, address, charmap, 0x50, length)
    return ok and str or nil
  end

  -- data/phone/phone_contacts.asm.  The struct (constants/phone_constants.asm
  -- rsreset) is class, number, map group, map number, then two
  -- {time, bank, addr} triples -- SCRIPT1 is the CALLEE half (you rang them),
  -- SCRIPT2 the CALLER half (they rang you).  Both are `dba`, so the bank byte
  -- comes first and the address after it.
  local contacts = self:symbol("PhoneContacts")
  local phone = {}
  for row = 0, #(consts.phoneContactOrder or {}) - 1 do
    local base = contacts.address + row * PHONE_CONTACT_SIZE
    local raw = self.rom:bytes(contacts.bank, base, PHONE_CONTACT_SIZE)
    local group, mapNum = raw[3], raw[4]
    phone[row] = {
      id = row,
      contact = name(consts.phoneContactOrder, row),
      trainerClass = raw[1],
      number = raw[2],
      -- N_A is group $ff / map $ff, which no real map equals.
      map = (group ~= 0xff) and self:mapNameByIds(group, mapNum) or nil,
      calleeTime = raw[5],
      callee = Opcodes.key(raw[6], raw[7] + raw[8] * 0x100),
      calleeBank = raw[6], calleeAddress = raw[7] + raw[8] * 0x100,
      callerTime = raw[9],
      caller = Opcodes.key(raw[10], raw[11] + raw[12] * 0x100),
      callerBank = raw[10], callerAddress = raw[11] + raw[12] * 0x100,
    }
  end
  out.phone = phone

  -- data/phone/special_calls.asm: `dw condition; db contact; dba script`.
  -- The condition is a routine (SpecialCallOnlyWhenOutside /
  -- SpecialCallWhereverYouAre), so its address is kept as a number for
  -- Phone.lua to recognise rather than as anything runnable.
  local special = self:symbol("SpecialPhoneCallList")
  local specialCalls = {}
  for row = 0, #(consts.specialCallOrder or {}) - 1 do
    local base = special.address + row * SPECIALCALL_SIZE
    local raw = self.rom:bytes(special.bank, base, SPECIALCALL_SIZE)
    specialCalls[row + 1] = {
      id = row + 1, -- SPECIALCALL_NONE is 0, so row 0 is SPECIALCALL_POKERUS
      call = name(consts.specialCallOrder, row + 1),
      condition = raw[1] + raw[2] * 0x100,
      contact = raw[3],
      script = Opcodes.key(raw[4], raw[5] + raw[6] * 0x100),
      scriptBank = raw[4], scriptAddress = raw[5] + raw[6] * 0x100,
    }
  end
  out.specialCalls = specialCalls

  -- engine/phone/phone.asm's own three scripts, which no contact row and no
  -- map points at: the wrong-number arm, the no-signal arm, and "they are on
  -- this map, go talk to them".  Named by the port's own labels rather than by
  -- the symbol's, because WrongNumber.script is a local label.
  out.phoneScripts = {}
  for label, symbol in pairs({
    WrongNumberScript = "WrongNumber.script",
    PhoneOutOfAreaScript = "PhoneOutOfAreaScript",
    PhoneScript_JustTalkToThem = "PhoneScript_JustTalkToThem",
  }) do
    local sym = self.symbols[symbol]
    if sym then
      out.phoneScripts[label] = {
        script = Opcodes.key(sym[1], sym[2]),
        scriptBank = sym[1], scriptAddress = sym[2],
      }
    end
  end

  -- data/events/npc_trades.asm, the `trade` command's own table.
  local trades = self:symbol("NPCTrades")
  -- NPCTRADE_ITEM is an item id byte (data/events/npc_trades.asm), and every
  -- other item byte this file writes is named at extraction: wild held items
  -- (:1329), trainer parties (:4120), givepokemail (:3178).  Name it here too
  -- so the cache carries the items.lua key the rest of the port indexes with.
  local itemOrder = self.manifest.constants.itemOrder or {}
  local tradeRows = {}
  for row = 0, NUM_NPC_TRADES - 1 do
    local base = trades.address + row * NPCTRADE_STRUCT_LENGTH
    local raw = self.rom:bytes(trades.bank, base, 3)
    local dvBase = base + 3 + MON_NAME_LENGTH
    local tail = self.rom:bytes(trades.bank, dvBase, 5)
    tradeRows[row + 1] = {
      id = row,
      dialog = name(consts.tradeDialogOrder, raw[1]),
      -- The mon the player HANDS OVER is GIVEMON and the one they receive is
      -- GETMON; the macro's own argument names are "requested, offered".
      give = self:speciesName(raw[2]),
      giveIndex = raw[2],
      get = self:speciesName(raw[3]),
      getIndex = raw[3],
      nickname = readName(trades.bank, base + 3, MON_NAME_LENGTH),
      -- NPCTRADE_DVS is a `dw` read as two raw DV bytes (attack/defense then
      -- speed/special), not as a number.
      dvs = { tail[1], tail[2] },
      -- NO_ITEM (0) drops entirely; the numeric fallback keeps a manifest
      -- built before itemOrder existed importable.
      item = (tail[3] ~= 0) and (itemOrder[tail[3]] or tail[3]) or nil,
      otId = tail[4] + tail[5] * 0x100,
      otName = readName(trades.bank, dvBase + 5, NAME_LENGTH),
      gender = name(consts.tradeGenderOrder,
        self.rom:byte(trades.bank, dvBase + 5 + NAME_LENGTH)),
    }
  end
  out.trades = tradeRows

  -- The trade conversation's five lines, one set per TRADE_DIALOGSET_*.
  -- PrintTradeText is `TradeTexts + 6 * dialog + 2 * dialogset`, so the table
  -- is stored dialog-major: three INTROs, then three CANCELs, and so on.
  local tradeTexts = self:symbol("TradeTexts")
  local dialogs = { "TRADE_DIALOG_INTRO", "TRADE_DIALOG_CANCEL",
    "TRADE_DIALOG_WRONG", "TRADE_DIALOG_COMPLETE", "TRADE_DIALOG_AFTER" }
  local sets = consts.tradeDialogOrder or {}
  out.tradeTexts, out.tradeBuffers = {}, {}
  -- The two markers a trade line splices are DIFFERENT buffers -- the intro is
  -- wStringBuffer1 ("do you have X?") then wStringBuffer2 ("for my Y?") --
  -- and both decode to {STRBUF}, so the order has to be recorded next to the
  -- text or the two mons come out swapped.
  for d, dialog in ipairs(dialogs) do
    local row, bufRow = {}, {}
    for s = 1, #sets do
      local addr = self.rom:word(tradeTexts.bank,
        tradeTexts.address + (d - 1) * 6 + (s - 1) * 2)
      local buffers = {}
      row[sets[s]] =
        self:decodeGen2Text(tradeTexts.bank, addr, charmap, buffers)
      bufRow[sets[s]] = buffers
    end
    out.tradeTexts[dialog] = row
    out.tradeBuffers[dialog] = bufRow
  end
  -- The two lines NPCTrade prints around the swap, then the six the trade
  -- ANIMATION prints (engine/movie/trade_animation.asm, text in
  -- data/text/common_1.asm).  They all land in the same table because they are
  -- all named rather than indexed; the empty _MonNameSentToText is skipped,
  -- since an open box with nothing in it needs no string.
  for _, label in ipairs({ "NPCTradeCableText", "TradedForText",
      "_MonWasSentToText", "_ForYourMonSendsText", "_OTSendsText",
      "_BidsFarewellToMonText", "_MonNameBidsFarewellText",
      "_TakeGoodCareOfMonText" }) do
    local sym = self.symbols[label]
    if sym then
      local buffers = {}
      out.tradeTexts[label] =
        self:decodeGen2Text(sym[1], sym[2], charmap, buffers)
      out.tradeBuffers[label] = buffers
    end
  end

  -- data/events/bug_contest_flags.asm: `table_width 2`, one
  -- EVENT_BUG_CATCHING_CONTESTANT_*A word per contestant.  These are wEventFlags
  -- NUMBERS, not names, which is what SelectRandomBugContestContestants
  -- (engine/events/bug_contest/contest_2.asm) hands to EventFlagAction -- it
  -- resets all ten and then sets five, and a SET flag is what keeps that
  -- object off NationalParkBugContest.  A missing symbol is skipped rather
  -- than fatal so an older manifest still imports and BugContest.FLAGS carries
  -- the map.
  local contestFlags = self.symbols.BugCatchingContestantEventFlagTable
  if contestFlags then
    local flagTable = self:symbol("BugCatchingContestantEventFlagTable")
    local flags = {}
    for row = 0, NUM_BUG_CONTESTANTS - 1 do
      flags[row + 1] =
        self.rom:word(flagTable.bank, flagTable.address + row * 2)
    end
    out.bugContestFlags = flags
  end

  -- data/events/elevator_floors.asm: a `dw` per FLOOR_* at a "B1F@" string.
  local floors = self:symbol("ElevatorFloorNames")
  local floorNames = {}
  for row = 0, #(consts.floorOrder or {}) - 1 do
    local addr = self.rom:word(floors.bank, floors.address + row * 2)
    floorNames[row + 1] = readName(floors.bank, addr, 8)
  end
  out.floorNames = floorNames

  -- describedecoration's five arms (engine/overworld/decorations.asm).  Each
  -- arm is ASM that hands back a script, so what is emitted is the SCRIPT each
  -- can pick: the poster table plus its "nothing installed" miss, the one
  -- script the two ornaments and the console share, and the giant ornament's.
  local function scriptRef(bank, address)
    return { script = Opcodes.key(bank, address),
             scriptBank = bank, scriptAddress = address }
  end
  local posterTable = self:symbol("DecorationDesc_PosterPointers")
  local posters = {}
  for i = 0, 15 do
    local row = posterTable.address + i * 3
    local deco = self.rom:byte(posterTable.bank, row)
    if deco == 0xff then break end
    local ref = scriptRef(posterTable.bank,
      self.rom:word(posterTable.bank, row + 1))
    ref.decoration = deco
    posters[#posters + 1] = ref
  end
  local nullPoster = self:symbol("DecorationDesc_NullPoster")
  local ornament = self:symbol(
    "DecorationDesc_OrnamentOrConsole.OrnamentConsoleScript")
  local bigDoll = self:symbol("DecorationDesc_GiantOrnament.BigDollScript")
  local poster = scriptRef(nullPoster.bank, nullPoster.address)
  poster.posters = posters
  out.decorations = {
    DECODESC_POSTER = poster,
    DECODESC_LEFT_DOLL = scriptRef(ornament.bank, ornament.address),
    DECODESC_RIGHT_DOLL = scriptRef(ornament.bank, ornament.address),
    DECODESC_BIG_DOLL = scriptRef(bigDoll.bank, bigDoll.address),
    DECODESC_CONSOLE = scriptRef(ornament.bank, ornament.address),
  }
  out.decorationOrder = consts.decoDescOrder

  return out
end

-- Text NO script pointer reaches, seeded by name.
--
-- The walker below only decodes a string some `writetext` / `farwritetext` /
-- `trainer` struct named, which is every line an NPC says and nothing else.
-- A line an ENGINE routine prints -- `ld hl, .SomeText / call PrintText` --
-- has no pointer in any bytecode, so three whole blocks used to arrive only
-- as hand transcriptions at their call sites:
--
--   the Day-Care and breeding block of data/text/common_1.asm and
--     common_2.asm, printed by engine/events/daycare.asm and
--     engine/pokemon/breeding.asm (src/ui/gen2/DayCareMenu.lua),
--   the POKeMART clerk's whole conversation in data/text/common_2.asm,
--     printed by engine/items/mart.asm (src/ui/gen2/MartMenu.lua),
--   and the Hall of Fame's three flavour strings, which are plain `db "…@"`
--     inside engine/events/halloffame.asm rather than text streams at all
--     (src/ui/gen2/HallOfFame.lua).
--
-- Each label below is the FAR string (`_Foo`), not the near `text_far` stub
-- that names it: both decode to the same characters, and the far one is the
-- symbol the whole block shares a bank with.  They are written out as
-- text.labels[label] -> the "bank:addr" key the string landed on, so a call
-- site asks for a pokegold label and never for an address.
local NAMED_TEXT = {
  -- engine/events/daycare.asm, in its own text-table order.
  "_DaycareDummyText",
  "_DayCareManIntroText", "_DayCareManIntroEggText",
  "_DayCareLadyIntroText", "_DayCareLadyIntroEggText",
  "_WhatShouldIRaiseText", "_OnlyOneMonText", "_CantAcceptEggText",
  "_RemoveMailText", "_LastHealthyMonText", "_IllRaiseYourMonText",
  "_ComeBackLaterText", "_AreWeGeniusesText", "_YourMonHasGrownText",
  "_PerfectHeresYourMonText", "_GotBackMonText", "_BackAlreadyText",
  "_HaveNoRoomText", "_NotEnoughMoneyText", "_OhFineThenText",
  "_ComeAgainText", "_NotYetText", "_FoundAnEggText", "_ReceivedEggText",
  "_TakeGoodCareOfEggText", "_IllKeepItThanksText", "_NoRoomForEggText",
  -- engine/pokemon/breeding.asm: the hatch, the "you left X here" lines the
  -- DayCareMon specials print, and the five compatibility verdicts.
  "Text_BreedHuh", "_BreedClearboxText", "_BreedEggHatchText",
  "_BreedAskNicknameText",
  "_LeftWithDayCareManText", "_LeftWithDayCareLadyText",
  "_BreedBrimmingWithEnergyText", "_BreedNoInterestText",
  "_BreedAppearsToCareForText", "_BreedFriendlyText",
  "_BreedShowsInterestText",
  -- engine/items/mart.asm: the four MARTTYPE_* dialogs and the sell flow.
  "_MartWelcomeText", "_MartAskMoreText", "_MartComeAgainText",
  "_MartHowManyText", "_MartFinalPriceText", "_MartThanksText",
  "_MartNoMoneyText", "_MartPackFullText",
  "_HerbShopLadyIntroText", "_HerbalLadyHowManyText",
  "_HerbalLadyFinalPriceText", "_HerbalLadyThanksText",
  "_HerbalLadyPackFullText", "_HerbalLadyNoMoneyText",
  "_HerbalLadyComeAgainText",
  "_BargainShopIntroText", "_BargainShopFinalPriceText",
  "_BargainShopThanksText", "_BargainShopPackFullText",
  "_BargainShopSoldOutText", "_BargainShopNoFundsText",
  "_BargainShopComeAgainText",
  "_PharmacyIntroText", "_PharmacyHowManyText", "_PharmacyFinalPriceText",
  "_PharmacyThanksText", "_PharmacyPackFullText", "_PharmacyNoMoneyText",
  "_PharmacyComeAgainText",
  "_NothingToSellText", "_MartSellHowManyText", "_MartSellPriceText",
  "_MartCantBuyText", "_MartBoughtText",
  -- engine/events/halloffame.asm.  These three are `db` strings ending on the
  -- same "@" a text chunk ends on, so the text walker reads them unchanged --
  -- and their leading spaces are load bearing, because PrintNum writes the
  -- win count over the first two columns of "    -Time Famer".
  "AnimateHallOfFame.String_NewHallOfFamer",
  "_HallOfFamePC.TimeFamer", "_HallOfFamePC.HOFMaster",
  -- data/text/common_2.asm's MAIL block, printed by engine/pokemon/mail.asm's
  -- MailboxPC and engine/pokemon/mon_menu.asm's MonMailAction
  -- (src/ui/gen2/MailboxMenu.lua and src/ui/gen2/MailMenu.lua).  Same shape as
  -- the Day-Care block above: asm prints these, so no bytecode points at them
  -- and the walker has to be seeded by name.
  "_EmptyMailboxText", "_MailClearedPutAwayText", "_MailPackFullText",
  "_MailMessageLostText", "_MailAlreadyHoldingItemText", "_MailEggText",
  "_MailMovedFromBoxText", "_MailLoseMessageText", "_MailDetachedText",
  "_MailNoSpaceText", "_MailAskSendToPCText", "_MailboxFullText",
  "_MailSentToPCText", "_PCMonHoldingMailText", "_PokemonRemoveMailText",
}

-- Walk every map's object/bg/coord/scene script pointers, disassemble
-- bytecode into command lists, rip writetext strings, and capture
-- applymovement byte streams.  Runtime never needs the ROM -- just
-- data/generated/scripts.lua + text.lua.
function RomExtractorGen2:extractScriptsAndText(maps, stdScripts)
  self:beginStage("Scripts & text")
  local charmap = self.manifest.charmap or {}
  local scripts, text = { generation = 2 }, { generation = 2 }
  local movements = {}
  local queue = {}
  local queued = {}

  local function enqueue(bank, address)
    if not romAddrOk(bank, address) or address == 0 then return end
    -- Scripts live in banked ROM, not ROM0.
    if bank == 0 then return end
    local key = Opcodes.key(bank, address)
    if queued[key] then return end
    queued[key] = true
    queue[#queue + 1] = { bank = bank, address = address, key = key }
  end

  -- home/map.asm ObjectEvent ("jumptextfaceplayer ObjectEventText") is the
  -- line an object with no script of its own says, and 44 object_events across
  -- the maps point at it with the same `dw`.  It lives in ROM0, which is
  -- visible from every bank, so its pointer is BELOW $4000 -- exactly what
  -- enqueue rejects, because a real map script pointer is always banked.  The
  -- shared body is walked once at bank 0 and every object that names it points
  -- at that one key, rather than at a key in its own map's script bank where
  -- nothing was ever disassembled.
  --
  -- Returns the key so a caller can use it as its scriptKey, or nil when the
  -- address is not a ROM0 one after all.
  local function enqueueHome(address)
    if not romAddrOk(0, address) or address == 0 then return nil end
    local key = Opcodes.key(0, address)
    if not queued[key] then
      queued[key] = true
      queue[#queue + 1] = { bank = 0, address = address, key = key }
    end
    return key
  end

  local function ensureText(bank, address)
    if not romAddrOk(bank, address) then return nil end
    local key = Opcodes.key(bank, address)
    if not text[key] then
      local ok, decoded = pcall(self.decodeGen2Text, self, bank, address, charmap)
      text[key] = ok and decoded or ""
    end
    return key
  end

  local function ensureMovement(bank, address)
    if not romAddrOk(bank, address) or address == 0 then return nil end
    local key = Opcodes.key(bank, address)
    if movements[key] then return key end
    local bytes = {}
    for i = 0, 64 do
      local ok, b = pcall(self.rom.byte, self.rom, bank, address + i)
      if not ok then break end
      bytes[#bytes + 1] = b
      if b == 0x47 or b == 0x48 then break end -- step_end / step_wait_end
    end
    movements[key] = bytes
    return key
  end

  -- A MAIL message: raw charmap bytes terminated by '@', NOT a text stream.
  -- Both mail opcodes point at one (Script_givepokemail FarCopyBytes's
  -- MAIL_MSG_LENGTH of them into wMonMailMessageBuffer; Script_checkpokemail
  -- hands its pointer to CheckPokeMail, which compares byte for byte until the
  -- '@'), so neither can go through decodeGen2Text -- that walks TX_* commands
  -- and would treat a $16 in the middle of somebody's sentence as a far jump.
  --
  -- The one control byte that IS meaningful here is `next` ($4e), the line
  -- break the message carries across the struct's two MAIL_LINE_LENGTH rows;
  -- it decodes to "\n" so the stored letter and the expected one compare equal
  -- (src/core/gen2/Mail.lua).
  local function readMailMessage(bank, address, limit)
    if not romAddrOk(bank, address) then return nil end
    local out = {}
    for i = 0, (limit or 0x20) - 1 do
      local ok, b = pcall(self.rom.byte, self.rom, bank, address + i)
      if not ok then break end
      if b == 0x50 then break end
      if b == 0x4e or b == 0x4f then
        out[#out + 1] = "\n"
      else
        local ch = charmap[tostring(b)]
        if ch and not ch:match("^<") then
          out[#out + 1] = ch
        elseif not ch then
          out[#out + 1] = ("{BYTE:%02X}"):format(b)
        end
      end
    end
    return table.concat(out)
  end

  -- MenuHeader (home/menu.asm LoadMenuHeader, ram/wram.asm wMenuHeader):
  --   db flags; menu_coords x1, y1, x2, y2; dw data; db default cursor
  -- `menu_coords` lays each corner down Y FIRST (macros/coords.asm is
  -- `db \2, \1` twice), so the four bytes are top, left, bottom, right.
  --
  -- The data block behind it is read two ways depending on which command
  -- consumes it.  A vertical menu is `db flags; db items;` then one `@`-ended
  -- string per item.  A 2D menu is `db flags; dn rows, cols; db spacing;
  -- dba strings; dbw bank, function` -- so its strings sit behind ANOTHER far
  -- pointer, and rows * cols is how many of them to read.
  --
  -- Both shapes are emitted; the command that follows loadmenu picks.  Reading
  -- both is safe because neither walks past the item count it was given.
  local function readMenuStrings(bank, address, count, limit)
    local items, cursor = {}, address
    for _ = 1, count do
      if not romAddrOk(bank, cursor) then break end
      local ok, str = pcall(self.rom.readString, self.rom,
        bank, cursor, charmap, 0x50, limit or 24)
      if not ok then break end
      items[#items + 1] = str
      -- readString stops AT the terminator and does not report how far it got,
      -- so the stride is measured here.
      local len = 0
      while len < (limit or 24) do
        local okB, b = pcall(self.rom.byte, self.rom, bank, cursor + len)
        if not okB or b == 0x50 then break end
        len = len + 1
      end
      cursor = cursor + len + 1
    end
    return items
  end

  local function readMenuHeader(bank, address)
    if not romAddrOk(bank, address) then return nil end
    local okRaw, raw = pcall(self.rom.bytes, self.rom,
      bank, address, MENU_HEADER_LENGTH)
    if not okRaw then return nil end
    local dataAddr = raw[6] + raw[7] * 0x100
    local header = {
      flags = raw[1],
      top = raw[2], left = raw[3], bottom = raw[4], right = raw[5],
      cursor = raw[8],
      key = Opcodes.key(bank, address),
    }
    if not romAddrOk(bank, dataAddr) then return header end
    local okData, data = pcall(self.rom.bytes, self.rom, bank, dataAddr, 8)
    if not okData then return header end
    header.dataFlags = data[1]
    -- Vertical: db items, then the strings inline.
    local count = data[2]
    if count > 0 and count <= 16 then
      header.items = readMenuStrings(bank, dataAddr + 2, count)
    end
    -- 2D: dn rows, cols (one byte) / db spacing / dba strings.
    local rows, cols = math.floor(data[2] / 16), data[2] % 16
    if rows > 0 and cols > 0 and rows * cols <= 32 then
      local strBank = data[4]
      local strAddr = data[5] + data[6] * 0x100
      if romAddrOk(strBank, strAddr) then
        header.grid = { rows = rows, cols = cols, spacing = data[3] }
        header.gridItems = readMenuStrings(strBank, strAddr, rows * cols)
      end
    end
    return header
  end

  -- `writecmdqueue` names a cmdqueue entry (macros/scripts/maps.asm):
  --   dbw type, addr; dw filler
  -- and the only type any map uses is CMDQUEUE_STONETABLE, whose address is a
  -- `stonetable warp, object, script` list ending on `db -1`.  Following it is
  -- what puts the per-boulder scripts in scripts.lua: nothing else points at
  -- them, so without this the Ice Path and Blackthorn Gym tables have to be
  -- hand-ported.
  local function readCmdQueueEntry(bank, address)
    if not romAddrOk(bank, address) then return nil end
    local okRaw, raw = pcall(self.rom.bytes, self.rom,
      bank, address, CMDQUEUE_ENTRY_SIZE)
    if not okRaw then return nil end
    local kind = raw[1]
    local target = raw[2] + raw[3] * 0x100
    local entry = {
      type = kind,
      queue = orderName(self.manifest.constants.cmdQueueOrder, kind + 1),
      address = target,
    }
    if kind ~= CMDQUEUE_STONETABLE or not romAddrOk(bank, target) then
      return entry
    end
    local rows = {}
    for i = 0, 15 do
      local row = target + i * STONETABLE_LENGTH
      local okWarp, warp = pcall(self.rom.byte, self.rom, bank, row)
      if not okWarp or warp == 0xff then break end
      local okScript, script = pcall(self.rom.word, self.rom, bank, row + 2)
      if not okScript then break end
      rows[#rows + 1] = {
        warp = warp,
        object = self.rom:byte(bank, row + 1),
        scriptKey = Opcodes.key(bank, script),
      }
      enqueue(bank, script)
    end
    entry.rows = rows
    return entry
  end

  -- `elevator` names a floor list: db count, then `elevfloor floor, warp, map`
  -- (db floor, warp; map_id) rows.  Elevator itself performs the ride, so the
  -- warp number and destination map are the whole of what the port needs.
  local function readElevator(bank, address)
    if not romAddrOk(bank, address) then return nil end
    local okCount, count = pcall(self.rom.byte, self.rom, bank, address)
    if not okCount or count == 0 or count > 16 then return nil end
    local floors = {}
    for i = 0, count - 1 do
      local row = address + 1 + i * 4
      local okRaw, raw = pcall(self.rom.bytes, self.rom, bank, row, 4)
      if not okRaw then break end
      floors[#floors + 1] = {
        floor = orderName(self.manifest.constants.floorOrder, raw[1] + 1),
        floorId = raw[1],
        destWarp = raw[2],
        destGroup = raw[3], destMapNum = raw[4],
        destMap = self:mapNameByIds(raw[3], raw[4]),
      }
    end
    return floors
  end

  -- `trainer` struct (macros/scripts/maps.asm):
  --   dw beat-event flag; db class, member; dw seen, win, loss; dw after-script
  -- The after-script is the only part that is bytecode, so it is the pointer
  -- the object's scriptKey ends up naming.
  local function readTrainerHeader(bank, address)
    if not romAddrOk(bank, address) then return nil end
    local ok, raw = pcall(self.rom.bytes, self.rom, bank, address, 12)
    if not ok then return nil end
    local function word(i) return raw[i] + raw[i + 1] * 0x100 end
    local afterAddr = word(11)
    local entry = {
      event = word(1),
      class = raw[3],
      member = raw[4],
      seenText = ensureText(bank, word(5)),
      winText = ensureText(bank, word(7)),
      lossText = ensureText(bank, word(9)),
    }
    if entry.event == 0xFFFF then entry.event = nil end
    if afterAddr ~= 0 and romAddrOk(bank, afterAddr) then
      entry.scriptKey = Opcodes.key(bank, afterAddr)
      enqueue(bank, afterAddr)
    end
    return entry
  end

  -- `itemball item, quantity` -- two bytes, no script.
  local function readItemBall(bank, address)
    if not romAddrOk(bank, address) then return nil end
    local ok, raw = pcall(self.rom.bytes, self.rom, bank, address, 2)
    if not ok then return nil end
    return { item = raw[1], quantity = raw[2] }
  end

  -- `hiddenitem item, flag` is `dwb \2, \1` (macros/scripts/maps.asm): the
  -- EVENT_* flag first as a word, the item id after it as a byte.  Three bytes,
  -- no script -- CheckForHiddenItems (engine/events/checkforhiddenitems.asm)
  -- reads the word straight into EventFlagAction and HiddenItemScript
  -- (engine/events/hidden_item.asm) reads the byte through wHiddenItemID.
  --
  -- The word comes first and the byte last, which is the opposite of the way
  -- `itemball` above lays its two bytes down; `dwb` is where that order lives,
  -- not the macro's argument list.
  local function readHiddenItem(bank, address)
    if not romAddrOk(bank, address) then return nil end
    local ok, raw = pcall(self.rom.bytes, self.rom, bank, address, 3)
    if not ok then return nil end
    return { event = raw[1] + raw[2] * 0x100, item = raw[3] }
  end

  -- Seed the std scripts first: they are reachable only through callstd /
  -- jumpstd ids, never through a map pointer, so nothing else would queue
  -- them and every `callstd` would dead-end at a missing key.
  for _, entry in pairs(stdScripts and stdScripts.scripts or {}) do
    enqueue(entry.bank, entry.address)
  end

  -- Seed the side tables next, for the same reason: the phone's callee/caller
  -- scripts all live in ROM bank $41 and no map points into it, so without
  -- these three seeds the bank is unreachable and every phone call arrives
  -- with a descriptor and no body.  The decoration scripts are the same shape
  -- one bank over.
  local events = self:readEventTables()
  for _, row in pairs(events.phone or {}) do
    enqueue(row.calleeBank, row.calleeAddress)
    enqueue(row.callerBank, row.callerAddress)
  end
  for _, row in ipairs(events.specialCalls or {}) do
    enqueue(row.scriptBank, row.scriptAddress)
  end
  for _, row in pairs(events.phoneScripts or {}) do
    enqueue(row.scriptBank, row.scriptAddress)
  end
  for _, arm in pairs(events.decorations or {}) do
    enqueue(arm.scriptBank, arm.scriptAddress)
    for _, poster in ipairs(arm.posters or {}) do
      enqueue(poster.scriptBank, poster.scriptAddress)
    end
  end

  -- And seed home/map.asm ObjectEvent, for a third flavour of the same reason:
  -- it is the shared generic line, it lives in an engine bank the map walk
  -- never enters, and the maps that name it all name it by an address enqueue
  -- would throw away.  Seeding it from the symbol keeps the body present even
  -- if the maps ever stop pointing at it.
  local objectEvent = self.symbols.ObjectEvent
  if objectEvent and objectEvent[1] == 0 then
    enqueueHome(objectEvent[2])
  end

  -- And seed the NAMED_TEXT blocks, which are the same problem one step
  -- further out: no script points at them because no SCRIPT prints them.  A
  -- missing symbol is skipped rather than fatal, so an older manifest still
  -- imports and the call sites fall back to their transcriptions.
  local labels = {}
  for _, label in ipairs(NAMED_TEXT) do
    local sym = self.symbols[label]
    if sym then
      local key = ensureText(sym[1], sym[2])
      if key then labels[label] = key end
    end
  end
  text.labels = labels

  -- Seed from every map event that carries a script pointer.
  local mapCount = 0
  for mapId, def in pairs(maps) do
    if type(def) == "table" and def.scripts and def.scripts.bank then
      mapCount = mapCount + 1
      local bank = def.scripts.bank
      for _, obj in ipairs(def.objects or {}) do
        -- object_event's function byte decides what its pointer *is*.  Only
        -- OBJECTTYPE_SCRIPT aims at bytecode; OBJECTTYPE_TRAINER aims at the
        -- `trainer` struct (macros/scripts/maps.asm) and OBJECTTYPE_ITEMBALL
        -- at two raw bytes.  Disassembling those as commands yields noise.
        if obj.type == OBJECTTYPE_TRAINER and obj.script then
          obj.trainer = readTrainerHeader(bank, obj.script)
          if obj.trainer and obj.trainer.scriptKey then
            obj.scriptKey = obj.trainer.scriptKey
          end
        elseif obj.type == OBJECTTYPE_ITEMBALL and obj.script then
          obj.itemball = readItemBall(bank, obj.script)
        elseif obj.script then
          -- A pointer below $4000 is ROM0, i.e. the shared ObjectEvent line,
          -- and belongs to bank 0 rather than to this map's script bank.
          obj.scriptKey = enqueueHome(obj.script)
          if not obj.scriptKey then
            obj.scriptKey = Opcodes.key(bank, obj.script)
            enqueue(bank, obj.script)
          end
        end
      end
      for _, ev in ipairs(def.bgEvents or {}) do
        -- A bg_event's function byte decides what its pointer *is*, exactly as
        -- an object_event's does above.  BGEVENT_ITEM aims at `hiddenitem`
        -- data, so it is read rather than walked: queueing it disassembled the
        -- flag word and the item byte as opcodes and, worse, followed whatever
        -- jump the noise happened to spell into more noise.
        if ev.kind == BGEVENT_ITEM and ev.script then
          ev.hiddenItem = readHiddenItem(bank, ev.script)
        elseif ev.script then
          -- IFSET/IFNOTSET already resolved their `conditional_event` above;
          -- the script it names is in the map's own bank.
          local scriptBank = bank
          local key = Opcodes.key(scriptBank, ev.script)
          ev.scriptKey = key
          enqueue(scriptBank, ev.script)
        end
      end
      for _, ev in ipairs(def.coordEvents or {}) do
        if ev.script then
          local key = Opcodes.key(bank, ev.script)
          ev.scriptKey = key
          enqueue(bank, ev.script)
        end
      end
      for _, sc in pairs(def.sceneScripts or {}) do
        if type(sc) == "table" and sc.script then
          enqueue(bank, sc.script)
        end
      end
      for _, cb in ipairs(def.callbacks or {}) do
        enqueue(bank, cb.script)
      end
    end
  end

  local qi, disassembled = 1, 0
  while queue[qi] do
    local item = queue[qi]
    qi = qi + 1
    local bank, pc = item.bank, item.address
    local commands = {}
    for _ = 1, 256 do
      if not romAddrOk(bank, pc) then
        commands[#commands + 1] = { op = "truncated", reason = "pc" }
        break
      end
      local okByte, opcode = pcall(self.rom.byte, self.rom, bank, pc)
      if not okByte then
        commands[#commands + 1] = { op = "truncated", reason = "read" }
        break
      end
      local info = Opcodes[opcode]
      if not info then
        commands[#commands + 1] = {
          op = "unknown", code = opcode,
          source = ("ROM:%s"):format(item.key),
        }
        break
      end
      -- givepoke is variable-length: 4 bytes, or 8 when the trainer flag is set.
      local size = info.size
      if info.name == "givepoke" then
        local okTr, trainer = pcall(self.rom.byte, self.rom, bank, pc + 4)
        size = (okTr and trainer ~= 0) and 8 or 4
      end
      if not romAddrOk(bank, pc + size) then
        commands[#commands + 1] = { op = "truncated", reason = "args" }
        break
      end
      local okArgs, args = pcall(self.rom.bytes, self.rom, bank, pc + 1, size)
      if not okArgs then
        commands[#commands + 1] = { op = "truncated", reason = "args" }
        break
      end
      local cmd = { op = info.name }
      local nextPc = pc + 1 + size

      if info.name == "writetext" or info.name == "jumptext"
          or info.name == "jumptextfaceplayer" then
        cmd.text = ensureText(bank, wordFromArgs(args))
      elseif info.name == "farwritetext" then
        local tBank, tAddr = dbaFromArgs(args)
        cmd.text = ensureText(tBank, tAddr)
      elseif info.name == "checkevent" or info.name == "setevent"
          or info.name == "clearevent" then
        cmd.event = wordFromArgs(args)
      elseif info.name == "checkflag" or info.name == "setflag"
          or info.name == "clearflag" then
        cmd.flag = wordFromArgs(args)
      elseif info.name == "iftrue" or info.name == "iffalse"
          or info.name == "sjump" or info.name == "scall"
          or info.name == "stopandsjump" or info.name == "sdefer" then
        local target = wordFromArgs(args)
        cmd.script = Opcodes.key(bank, target)
        enqueue(bank, target)
      elseif info.name == "ifequal" or info.name == "ifnotequal"
          or info.name == "ifgreater" or info.name == "ifless" then
        cmd.value = args[1]
        local target = args[2] + args[3] * 0x100
        cmd.script = Opcodes.key(bank, target)
        enqueue(bank, target)
      elseif info.name == "farscall" or info.name == "farsjump" then
        local tBank, tAddr = dbaFromArgs(args)
        cmd.script = Opcodes.key(tBank, tAddr)
        enqueue(tBank, tAddr)
      elseif info.name == "jumpstd" or info.name == "callstd" then
        cmd.id = wordFromArgs(args)
        -- Resolve now so the VM can jump straight to a scripts.lua key
        -- instead of carrying a std-script table of its own.
        local label = stdScripts and stdScripts.byId
          and stdScripts.byId[cmd.id]
        local entry = label and stdScripts.scripts[label]
        if entry then
          cmd.std = label
          cmd.script = entry.key
        end
      elseif info.name == "special" or info.name == "playmusic"
          or info.name == "playsound" or info.name == "cry" then
        cmd.id = wordFromArgs(args)
      elseif info.name == "pause" then
        cmd.frames = args[1]
      elseif info.name == "setscene" then
        cmd.scene = args[1]
      elseif info.name == "setmapscene" then
        cmd.group, cmd.map, cmd.scene = args[1], args[2], args[3]
      elseif info.name == "turnobject" then
        cmd.object = args[1]
        cmd.facing = args[2]
      elseif info.name == "applymovement" then
        cmd.object = args[1]
        local movAddr = wordFromArgs({ args[2], args[3] })
        cmd.movement = ensureMovement(bank, movAddr)
      elseif info.name == "applymovementlasttalked" then
        local movAddr = wordFromArgs(args)
        cmd.movement = ensureMovement(bank, movAddr)
      elseif info.name == "givepoke" then
        cmd.species, cmd.level, cmd.item, cmd.trainer =
          args[1], args[2], args[3], args[4]
      elseif info.name == "pokepic" or info.name == "disappear" then
        cmd.species = args[1] -- pokepic
        cmd.object = args[1]  -- disappear (same byte)
        cmd.args = args
      elseif info.name == "getmonname" then
        cmd.species, cmd.buffer = args[1], args[2]
      elseif info.name == "getitemname" then
        cmd.item, cmd.buffer = args[1], args[2]
      elseif info.name == "getstring" then
        -- `getstring buffer, pointer` lays the pointer down first (dw) and the
        -- buffer id last -- see macros/scripts/events.asm.  The target is a
        -- plain `@`-terminated name, not a text stream, so read it as a string:
        -- Script_getstring CopyName1's it into wStringBuffer2, which is what
        -- the following writetext's TX_RAM ({STRBUF}) prints.
        cmd.buffer = args[3]
        local sAddr = wordFromArgs(args)
        if romAddrOk(bank, sAddr) then
          local okStr, str = pcall(self.rom.readString, self.rom,
            bank, sAddr, charmap, 0x50, 32)
          cmd.string = okStr and str or nil
        end
      elseif info.name == "givepokemail" then
        -- `givepokemail pointer` (Script_givepokemail): the target is `db item`
        -- followed by MAIL_MSG_LENGTH message bytes, in the SCRIPT'S own bank
        -- (`ld a, [wScriptBank] / call GetFarByte`).  One call site in the
        -- game, RandyScript's GiftSpearowMail in
        -- maps/Route35GoldenrodGate.asm.  `args` is kept alongside so a reader
        -- that only knows the raw word still has it.
        cmd.args = args
        local mAddr = wordFromArgs(args)
        if romAddrOk(bank, mAddr) then
          local okItem, itemByte = pcall(self.rom.byte, self.rom, bank, mAddr)
          local message = readMailMessage(bank, mAddr + 1, 0x20)
          if okItem and message then
            cmd.mail = {
              item = (self.manifest.constants.itemOrder or {})[itemByte],
              message = message,
            }
          end
        end
      elseif info.name == "checkpokemail" then
        -- `checkpokemail pointer`: the target is the EXPECTED message alone --
        -- no item byte -- and CheckPokeMail walks it until the '@', so a
        -- message stored longer than this one still matches.
        cmd.args = args
        local mAddr = wordFromArgs(args)
        local message = readMailMessage(bank, mAddr, 0x20)
        if message then cmd.mail = { message = message } end
      elseif info.name == "gettrainername" then
        cmd.group, cmd.trainer, cmd.buffer = args[1], args[2], args[3]
      elseif info.name == "loadtrainer" then
        cmd.class, cmd.member = args[1], args[2]
      elseif info.name == "loadwildmon" then
        cmd.species, cmd.level = args[1], args[2]
      elseif info.name == "winlosstext" then
        -- Overrides the `trainer` struct's win/loss text for one battle.
        cmd.winText = ensureText(bank, wordFromArgs(args))
        cmd.lossText = ensureText(bank, args[3] + args[4] * 0x100)
      elseif info.name == "trainertext" then
        cmd.index = args[1]
      elseif info.name == "trainerflagaction" then
        cmd.action = args[1]
      elseif info.name == "setlasttalked" then
        cmd.object = args[1]
      elseif info.name == "showemote" then
        cmd.emote, cmd.object, cmd.frames = args[1], args[2], args[3]
      elseif info.name == "giveitem" or info.name == "verbosegiveitem" then
        cmd.item, cmd.quantity = args[1], args[2]
      elseif info.name == "addcellnum" or info.name == "delcellnum"
          or info.name == "checkcellnum" then
        cmd.phone = args[1]
      elseif info.name == "readvar" or info.name == "writevar" then
        cmd.var = args[1]
      elseif info.name == "follow" or info.name == "faceobject"
          or info.name == "follownotexact" then
        cmd.a, cmd.b = args[1], args[2]
      elseif info.name == "loadmenu" then
        -- The header sits in the SCRIPT'S own bank (Script_loadmenu calls
        -- LoadMenuHeader through Call_a_de with wScriptBank in a).
        cmd.menu = readMenuHeader(bank, wordFromArgs(args))
      elseif info.name == "writecmdqueue" then
        cmd.queue = readCmdQueueEntry(bank, wordFromArgs(args))
      elseif info.name == "elevator" then
        cmd.floors = readElevator(bank, wordFromArgs(args))
      elseif info.name == "trade" then
        cmd.trade = args[1]
      elseif info.name == "describedecoration" then
        cmd.decoration = args[1]
        cmd.decorationName = orderName(
          self.manifest.constants.decoDescOrder, args[1] + 1)
      elseif size > 0 then
        cmd.args = args
      end

      commands[#commands + 1] = cmd
      if Opcodes.TERMINATORS[info.name] then break end
      pc = nextPc
    end
    scripts[item.key] = commands
    disassembled = disassembled + 1
    if disassembled % 64 == 0 then
      self:tick("Scripts & text", disassembled, math.max(disassembled, #queue))
    end
  end

  scripts.movements = movements

  -- Rewrite maps.lua with scriptKey fields now that objects were annotated.
  self:write("maps", maps)
  self:write("scripts", scripts)
  self:write("text", text)
  self:write("events", events)
  self:extractInitialEvents()
  self:tick("Scripts & text", 1, 1)
  return { scripts = scripts, text = text, events = events,
    mapCount = mapCount, scriptCount = disassembled }
end

-- New-game seed: walk InitializeEventsScript and collect what it sets.
--
-- Retail Gold's numeric EVENT_* values differ from pret's current const_def
-- order, so we must take them from the cart, not hardcode.
--
-- It is not only `setevent`.  The same script ends with nine `variablesprite`
-- assignments, and they are not decoration: SPRITE_WEIRD_TREE ($f4) is a
-- wVariableSprites SLOT, not a sheet, so until something fills it nothing
-- spawns at all.  Dropping them meant the Sudowoodo on Route 36 was simply not
-- there -- and with it TM08 ROCK SMASH, the Burned Tower, Morty, FOGBADGE and
-- SURF -- along with the Olivine rival, the Azalea Rocket, the four Fuchsia
-- gym Janines, the Copycat and the Janine impersonator.
function RomExtractorGen2:extractInitialEvents()
  local sym = self.symbols.InitializeEventsScript
  if not sym then
    self:write("initial_events", {
      generation = 2,
      source = "missing symbol InitializeEventsScript",
      flags = {}, engineFlags = {}, sprites = {},
    })
    return
  end
  local bank, pc = sym[1], sym[2]
  local flags, seen = {}, {}
  local engineFlags, engineSeen = {}, {}
  local sprites = {}
  for _ = 1, 512 do
    if not romAddrOk(bank, pc) then break end
    local okByte, opcode = pcall(self.rom.byte, self.rom, bank, pc)
    if not okByte then break end
    local info = Opcodes[opcode]
    if not info then break end
    local size = info.size
    local okArgs, args = true, {}
    if size > 0 then
      okArgs, args = pcall(self.rom.bytes, self.rom, bank, pc + 1, size)
      if not okArgs then break end
    end
    if info.name == "setevent" then
      local id = wordFromArgs(args)
      if not seen[id] then
        seen[id] = true
        flags[#flags + 1] = id
      end
    elseif info.name == "setflag" then
      local id = wordFromArgs(args)
      if not engineSeen[id] then
        engineSeen[id] = true
        engineFlags[#engineFlags + 1] = id
      end
    elseif info.name == "variablesprite" then
      -- Script_variablesprite: two bytes, `wVariableSprites + slot = sprite`.
      -- The slot operand is already the offset from SPRITE_VARS.
      if args[1] and args[2] then
        sprites[#sprites + 1] = { slot = args[1], sprite = args[2] }
      end
    end
    pc = pc + 1 + size
    if Opcodes.TERMINATORS[info.name] then break end
  end
  self:write("initial_events", {
    generation = 2,
    source = "ROM:InitializeEventsScript",
    flags = flags,
    engineFlags = engineFlags,
    sprites = sprites,
  })
end

-- PREDEFPAL_GAMEFREAK_LOGO_OB / _BG (constants/scgb_constants.asm), the two
-- palettes _CGB_GamefreakLogo loads: the OB pair is white/white/yellow/yellow
-- and the BG runs black to white.
-- constants/scgb_constants.asm, the constant immediately before
-- PREDEFPAL_GAMEFREAK_LOGO_OB.
local PREDEFPAL_UNOWN_PUZZLE = 76
local PREDEFPAL_GAMEFREAK_LOGO_OB = 77
local PREDEFPAL_GAMEFREAK_LOGO_BG = 78

-- The GameFreak Presents splash's own graphics (engine/movie/splash.asm
-- GameFreakPresentsInit).  Both labels are two INCBINs run together, which is
-- the thing that used to be got wrong here: the 15 tiles at the START of
-- GameFreakLogoGFX are gamefreak_presents' letter strip, not the logo, so the
-- old "first 15 tiles are the mark" read wrote a slice of text glyphs and the
-- splash drew nothing recognisable.
--
--   GameFreakLogoGFX      = gamefreak_presents.1bpp (13 tiles, vTiles1 $80-$8c)
--                         + gamefreak_logo.1bpp     (15 tiles,         $8d-$9b)
--   GameFreakLogoStarsGFX = logo_star.2bpp          (2 tiles,          $9c-$9d)
--                         + logo_sparkle.2bpp       (3 tiles,          $9e-$a0)
--
-- The logo's 15 tiles are laid out row-major by OAMData_GSGameFreakLogo (tile
-- $00 at the top-left of a 3x5 block, then left to right), so a 24x40 sheet
-- indexes straight off it.  The star is 1x2 tiles and the OAM set mirrors it
-- to make the other half; the sparkle strip is 3 frames in a row.
function RomExtractorGen2:splashGfx()
  if not (self.symbols.GameFreakLogoGFX
      and self.symbols.GameFreakLogoStarsGFX) then
    return nil
  end
  local gfx = self:symbol("GameFreakLogoGFX")
  local raw = self.rom:bytes(gfx.bank, gfx.address, 28 * 8)
  local presents, logo = {}, {}
  for i = 1, 13 * 8 do presents[i] = raw[i] or 0 end
  for i = 1, 15 * 8 do logo[i] = raw[13 * 8 + i] or 0 end
  -- 1bpp, so black ink on transparent: the splash paints its own black field
  -- and these draw over it through the palette the port picks.
  self:save(inkFrom1bpp(presents, 104, 8), "splash/presents.png")
  self:save(inkFrom1bpp(logo, 24, 40), "splash/logo.png")
  -- Kept at the old path too: a cache reader that predates this table still
  -- finds a logo image there, and now it is the right one.
  self:save(inkFrom1bpp(logo, 24, 40), "intro/gamefreak_logo.png")

  local stars = self:symbol("GameFreakLogoStarsGFX")
  local starRaw = self.rom:bytes(stars.bank, stars.address, 2 * 16)
  local sparkleRaw = self.rom:bytes(stars.bank, stars.address + 2 * 16, 3 * 16)
  -- 2bpp with shade 0 transparent, the way every OBJ sheet is written.
  self:write2bpp(starRaw, 8, 16, "splash/star.png", true)
  self:write2bpp(sparkleRaw, 24, 8, "splash/sparkle.png", true)

  return {
    presents = "assets/generated/splash/presents.png",
    logo = "assets/generated/splash/logo.png",
    star = "assets/generated/splash/star.png",
    sparkle = "assets/generated/splash/sparkle.png",
    obPalette = self:predefPal(PREDEFPAL_GAMEFREAK_LOGO_OB),
    bgPalette = self:predefPal(PREDEFPAL_GAMEFREAK_LOGO_BG),
  }
end

-- OakSpeech (engine/menus/intro_menu.asm): named _OakText* strings plus the
-- POKEMON_PROF / CAL trainer pics shown before NamePlayer.  Also pulls
-- Shrink1/2 pics and the GameFreak splash sheets for the boot cinema.
function RomExtractorGen2:extractOakSpeech(pokemon)
  local charmap = self.manifest.charmap or {}
  local texts = {}
  for i = 1, 7 do
    local label = ("_OakText%d"):format(i)
    local sym = self:symbol(label)
    texts[label] = self:decodeGen2Text(sym.bank, sym.address, charmap)
  end
  -- Trainer pics are always 7x7 tiles (GetTrainerPic / PlaceGraphic).
  self:writeCompressedPic("PokemonProfPic", 7, "intro/oak.png")
  self:writeCompressedPic("CalPic", 7, "intro/cal.png")
  -- ShrinkPlayer frames (gfx/new_game/shrink{1,2}.2bpp.lz) : also 7x7.
  if self.symbols.Shrink1Pic then
    pcall(self.writeCompressedPic, self, "Shrink1Pic", 7, "intro/shrink1.png")
  end
  if self.symbols.Shrink2Pic then
    pcall(self.writeCompressedPic, self, "Shrink2Pic", 7, "intro/shrink2.png")
  end
  local splash = self:splashGfx()
  local marill = pokemon and pokemon.MARILL
  local data = {
    generation = 2,
    source = "ROM:OakSpeech (_OakText1-7, PokemonProfPic, CalPic)",
    music = "Music_Route30",
    demoSpecies = "MARILL",
    oakPic = "assets/generated/intro/oak.png",
    playerPic = "assets/generated/intro/cal.png",
    marillPic = marill and marill.spriteFront
      or "assets/generated/battle/front/marill.png",
    shrink1 = "assets/generated/intro/shrink1.png",
    shrink2 = "assets/generated/intro/shrink2.png",
    gamefreakLogo = "assets/generated/intro/gamefreak_logo.png",
    splash = splash,
    text = texts,
  }
  self:write("oak_speech", data)
  return data
end

-- ItemNames only (attributes / effects / TMs stay Phase 2).
function RomExtractorGen2:extractItems()
  self:beginStage("Items")
  local order = self.manifest.constants and self.manifest.constants.itemOrder
  if not order or #order == 0 then
    self:write("items", {
      generation = 2,
      source = "Gold items: itemOrder missing from manifest : re-run make_gold_manifest.py",
    })
    self:tick("Items", 1, 1)
    return {}
  end
  local charmap = self.manifest.charmap or {}
  local consts = self.manifest.constants
  local names = self:symbol("ItemNames")
  local attributes = self:symbol("ItemAttributes")
  local descriptions = self:symbol("ItemDescriptions")
  local pocketOrder = consts.pocketOrder or {}
  local menuOrder = consts.itemMenuOrder or {}
  local heldOrder = consts.heldEffectOrder or {}
  local out = {
    generation = 2,
    source = "ROM:ItemNames + ItemAttributes + constants/item_constants.asm",
    pockets = pocketOrder,
  }
  -- ItemNames only has rows for item ids 1..NUM_ITEMS; the TM and HM items
  -- past that carry no name of their own on the cart (the PACK prints
  -- "TM08" from their TM number instead), so reading a name for them would
  -- walk off the end of the table.
  local nameCount = consts.itemNameCount or #order
  local address = names.address
  for index, itemId in ipairs(order) do
    local value
    if index <= nameCount then
      local consumed
      value, consumed = self.rom:readString(
        names.bank, address, charmap, 0x50, 32)
      address = address + consumed
    end
    if itemId and itemId ~= "UNUSED" then
      -- ItemAttributes rows (ITEMATTR_STRUCT_LENGTH = 7): dw price;
      -- db held effect, parameter, property, pocket; dn field menu, battle
      -- menu.  Rows are 1-based on item id, so MASTER_BALL (1) is row 0.
      local base = attributes.address + (index - 1) * 7
      local price = self.rom:word(attributes.bank, base)
      local property = self.rom:byte(attributes.bank, base + 4)
      local pocket = self.rom:byte(attributes.bank, base + 5)
      local menus = self.rom:byte(attributes.bank, base + 6)
      local descAddress = self.rom:word(
        descriptions.bank, descriptions.address + (index - 1) * 2)
      out[itemId] = {
        id = itemId,
        index = index,
        name = value,
        source = ("ROM:ItemNames[%d]"):format(index),
        price = price,
        heldEffect = heldOrder[self.rom:byte(attributes.bank, base + 2) + 1],
        heldParameter = self.rom:byte(attributes.bank, base + 3),
        -- `property` is a bitfield, not an enum: shift_const CANT_SELECT is
        -- bit 6 and CANT_TOSS bit 7 (constants/item_data_constants.asm), so
        -- NO_LIMITS = 0 means "both allowed".
        canSelect = math.floor(property / 0x40) % 2 == 0,
        canToss = math.floor(property / 0x80) % 2 == 0,
        propertyRaw = property,
        -- Item types are declared `const_def 1`, so ITEM is 1 and the list is
        -- indexed by the value itself, not value + 1.
        pocket = pocketOrder[pocket] or pocket,
        pocketId = pocket,
        -- dn field, battle: high nibble is the field menu behavior.  The
        -- ITEMMENU_* enum has a `const_skip 3` hole between NOUSE and CURRENT,
        -- so a positional list cannot be indexed by value.
        fieldMenu = ITEM_MENU_NAME[math.floor(menus / 16)],
        battleMenu = ITEM_MENU_NAME[menus % 16],
        description = self.rom:readString(
          descriptions.bank, descAddress, charmap, 0x50, 128),
      }
    end
    if index % 32 == 0 then
      self:tick("Items", index, #order)
    end
  end

  -- TM/HM items carry no name of their own in ItemNames: add_tm/add_hm name
  -- the item TM_<MOVE> (the "TM08" form is only the TM##_MOVE alias) and give
  -- it a TM/HM number, which is its position in that declaration order.  The
  -- move it teaches comes from TMHMMoves, indexed by that number -- which is
  -- also what makes a species' BASE_TMHM bitfield readable.
  local tmhmMoves = self:symbol("TMHMMoves")
  local moveOrder = consts.moveOrder or {}
  local number = 0
  local hmCount = 0
  for _, itemId in ipairs(order) do
    local entry = out[itemId]
    if entry and (itemId:match("^TM_") or itemId:match("^HM_")) then
      number = number + 1
      local moveId = self.rom:byte(
        tmhmMoves.bank, tmhmMoves.address + number - 1)
      entry.tmNumber = number
      entry.teaches = moveOrder[moveId] or moveId
      -- The label the PACK prints: TM01..TM50, then HM01 onwards (the HMs
      -- restart their own numbering).
      if itemId:match("^HM_") then
        hmCount = hmCount + 1
        entry.tmLabel = ("HM%02d"):format(hmCount)
      else
        entry.tmLabel = ("TM%02d"):format(number)
      end
      -- These items have no ItemNames row, so the label IS the name.
      entry.name = entry.name or entry.tmLabel
    end
  end
  self:write("items", out)
  self:tick("Items", #order, #order)
  return out
end

-- Mart shelves (data/items/marts.asm).  Marts is NUM_MARTS same-bank `dw`
-- pointers in MART_* order; each list is `db count`, count item ids, `db -1`.
-- Written as `lists`, a 1-based array in that same order, so
-- src/ui/gen2/MartMenu.lua's inventory() indexes it with martId + 1 exactly
-- the way GetMart adds the id to the table.  BargainShopData
-- (data/items/bargain_shop.asm) is its own `dbw item, price` rows -- the one
-- shop whose prices bypass ItemAttributes -- and lands under `bargain`.
--
-- Both symbols are post-Phase-2 manifest additions, so a manifest from before
-- them writes a marts.lua with no lists at all rather than failing the whole
-- import; MartMenu treats that as the empty shelf it already handles.
local NUM_MARTS = 34 -- constants/mart_constants.asm, MART_UNDERGROUND is 33
function RomExtractorGen2:extractMarts()
  self:beginStage("Marts")
  local order = (self.manifest.constants
    and self.manifest.constants.itemOrder) or {}
  local out = {
    generation = 2,
    source = "ROM:Marts + BargainShopData (data/items/marts.asm)",
  }
  local marts = self.symbols["Marts"]
  if marts then
    local bank = marts[1]
    local lists = {}
    for index = 0, NUM_MARTS - 1 do
      local address = self.rom:word(bank, marts[2] + index * 2)
      local count = self.rom:byte(bank, address)
      local list = {}
      for slot = 1, count do
        local id = self.rom:byte(bank, address + slot)
        if id == 0xff then break end
        list[#list + 1] = order[id] or id
      end
      lists[index + 1] = list
    end
    out.lists = lists
  end
  local bargain = self.symbols["BargainShopData"]
  if bargain then
    local bank, address = bargain[1], bargain[2] + 1 -- past the count byte
    local rows = {}
    while true do
      local id = self.rom:byte(bank, address)
      if id == 0xff then break end
      rows[#rows + 1] = {
        item = order[id] or id,
        price = self.rom:word(bank, address + 1),
      }
      address = address + 3
    end
    out.bargain = rows
  end
  self:write("marts", out)
  self:tick("Marts", 1, 1)
  return out
end

-- Moves + type chart.  Shapes deliberately match Gen 1's moves.lua and
-- type_chart.lua so src/battle/TypeChart.lua reads either generation, but the
-- contents are Gen 2's: 251 moves, an effect-chance byte, and the Steel/Dark
-- rows that make the matchup table longer than Gen 1's.
function RomExtractorGen2:extractMoves()
  self:beginStage("Moves")
  local consts = self.manifest.constants
  local order = consts.moveOrder or {}
  local effects = consts.moveEffectOrder or {}
  local typeById = {}
  for name, value in pairs(consts.types or {}) do typeById[value] = name end
  local charmap = self.manifest.charmap or {}

  local moves = self:symbol("Moves")
  local names = self:symbol("MoveNames")
  local descriptions = self:symbol("MoveDescriptions")
  local out = { generation = 2, source = "ROM:Moves + MoveNames" }
  local nameAddress = names.address
  for index, moveId in ipairs(order) do
    local row = self.rom:bytes(
      moves.bank, moves.address + (index - 1) * 7, 7)
    local name, consumed = self.rom:readString(
      names.bank, nameAddress, charmap, 0x50, 32)
    nameAddress = nameAddress + consumed
    -- Descriptions are a pointer table into the same bank, one per move.
    local descAddress = self.rom:word(
      descriptions.bank, descriptions.address + (index - 1) * 2)
    local description = self.rom:readString(
      descriptions.bank, descAddress, charmap, 0x50, 128)
    if moveId and moveId ~= "UNUSED" then
      out[moveId] = {
        id = moveId,
        index = index,
        name = name,
        source = ("ROM:Moves[%d]"):format(index),
        animation = row[1],
        effect = effects[row[2] + 1] or row[2],
        effectId = row[2],
        power = row[3],
        type = typeById[row[4]] or row[4],
        -- `db N percent` stores 255*N/100, so 100% is $ff; convert back to a
        -- real percentage the way Gen 1's moves.lua reads (BLIZZARD 90, not
        -- $e6).  The raw byte is kept for anything that wants to reproduce the
        -- cart's out-of-256 accuracy roll exactly.
        accuracy = percentOf(row[5]),
        accuracyRaw = row[5],
        pp = row[6],
        effectChance = percentOf(row[7]),
        effectChanceRaw = row[7],
      }
      out[moveId].description = description
    end
    if index % 32 == 0 then self:tick("Moves", index, #order) end
  end
  self:write("moves", out)

  -- TypeMatchups: attacker/defender/x10 triples.  -2 ends the normal rows and
  -- starts the Foresight-only block (which removes Ghost's immunities); -1
  -- ends the table.  Both blocks are kept, tagged, so a Foresight
  -- implementation has the rows without re-reading the cart.
  local matchupSymbol = self:symbol("TypeMatchups")
  local matchups, foresight = {}, {}
  local target = matchups
  local offset = 0
  while offset < 0x400 do
    local attacker = self.rom:byte(
      matchupSymbol.bank, matchupSymbol.address + offset)
    if attacker == 0xff then break end
    if attacker == 0xfe then
      target = foresight
      offset = offset + 1
    else
      local defender = self.rom:byte(
        matchupSymbol.bank, matchupSymbol.address + offset + 1)
      local multiplier = self.rom:byte(
        matchupSymbol.bank, matchupSymbol.address + offset + 2)
      target[#target + 1] = {
        attacker = typeById[attacker] or attacker,
        defender = typeById[defender] or defender,
        multiplier = multiplier,
      }
      offset = offset + 3
    end
  end

  -- Gen 2 still splits physical/special by *type*, not by move: ids below
  -- SPECIAL are physical.  The type constants leave a gap before the special
  -- block, so the boundary is the numeric id, not a position in a list.
  local specialBoundary = (consts.types and consts.types.FIRE) or 0x14
  local typeNames = self:symbol("TypeNames")
  local names2, records = {}, {}
  for name, value in pairs(consts.types or {}) do
    local pointer = self.rom:word(
      typeNames.bank, typeNames.address + value * 2)
    local display = self.rom:readString(
      typeNames.bank, pointer, charmap, 0x50, 16)
    names2[name] = display
    records[name] = {
      id = name, index = value, name = display,
      category = (value < specialBoundary) and "physical" or "special",
    }
  end
  self:write("type_chart", {
    generation = 2,
    source = "ROM:TypeMatchups + TypeNames",
    names = names2,
    types = records,
    matchups = matchups,
    foresightMatchups = foresight,
  })
  self:tick("Moves", #order, #order)
  return out
end

-- Wild encounters.  Grass tables carry three separate 7-slot lists (morn /
-- day / nite) plus a per-time encounter rate, which is the Gen 2 mechanic
-- that makes the clock part of gameplay rather than just lighting.
local GRASS_SLOTS = 7   -- NUM_GRASSMON
local WATER_SLOTS = 3   -- NUM_WATERMON
local GRASS_RECORD = 2 + 3 + GRASS_SLOTS * 2 * 3 -- GRASS_WILDDATA_LENGTH (47)
local WATER_RECORD = 2 + 1 + WATER_SLOTS * 2     -- WATER_WILDDATA_LENGTH (9)

function RomExtractorGen2:readGrassTable(symbolName)
  local symbol = self:symbol(symbolName)
  local out = {}
  local offset = 0
  -- Terminator-driven, but bounded: a bad pointer must fail the import loudly
  -- rather than walk the whole cart.
  for _ = 1, 512 do
    local group = self.rom:byte(symbol.bank, symbol.address + offset)
    if group == 0xff then break end
    local mapNum = self.rom:byte(symbol.bank, symbol.address + offset + 1)
    local mapId = self:mapNameByIds(group, mapNum)
    local rates = {}
    for i = 0, 2 do
      rates[DAYTIMES[i + 1]] = self.rom:byte(
        symbol.bank, symbol.address + offset + 2 + i)
    end
    local slots = {}
    for day = 0, 2 do
      local list = {}
      for slot = 0, GRASS_SLOTS - 1 do
        local base = symbol.address + offset + 5
          + (day * GRASS_SLOTS + slot) * 2
        list[slot + 1] = {
          level = self.rom:byte(symbol.bank, base),
          species = self:speciesName(
            self.rom:byte(symbol.bank, base + 1)),
        }
      end
      slots[DAYTIMES[day + 1]] = list
    end
    if mapId then
      out[mapId] = { map = mapId, rates = rates, slots = slots }
    end
    offset = offset + GRASS_RECORD
  end
  return out
end

function RomExtractorGen2:readWaterTable(symbolName)
  local symbol = self:symbol(symbolName)
  local out = {}
  local offset = 0
  for _ = 1, 512 do
    local group = self.rom:byte(symbol.bank, symbol.address + offset)
    if group == 0xff then break end
    local mapNum = self.rom:byte(symbol.bank, symbol.address + offset + 1)
    local mapId = self:mapNameByIds(group, mapNum)
    local rate = self.rom:byte(symbol.bank, symbol.address + offset + 2)
    local slots = {}
    for slot = 0, WATER_SLOTS - 1 do
      local base = symbol.address + offset + 3 + slot * 2
      slots[slot + 1] = {
        level = self.rom:byte(symbol.bank, base),
        species = self:speciesName(self.rom:byte(symbol.bank, base + 1)),
      }
    end
    if mapId then
      out[mapId] = { map = mapId, rate = rate, slots = slots }
    end
    offset = offset + WATER_RECORD
  end
  return out
end

function RomExtractorGen2:speciesName(index)
  local order = self.manifest.constants.speciesOrder or {}
  return order[index] or index
end

-- data/wild/treemon_maps.asm: `treemon_map` rows of a two-byte map_id plus one
-- TREEMON_SET_* byte, ending at -1.  TreeMonMaps and RockMonMaps are the same
-- table read twice -- GetTreeMonSet takes the list in hl, so HEADBUTT passes
-- one and ROCK SMASH the other (engine/events/treemons.asm).
function RomExtractorGen2:readTreeMonMaps(symbolName)
  local symbol = self:symbol(symbolName)
  local out = {}
  local offset = 0
  while offset < 0x200 do
    local group = self.rom:byte(symbol.bank, symbol.address + offset)
    if group == 0xff then break end
    local mapNum = self.rom:byte(symbol.bank, symbol.address + offset + 1)
    local set = self.rom:byte(symbol.bank, symbol.address + offset + 2)
    local mapId = self:mapNameByIds(group, mapNum)
    if mapId then
      out[mapId] = (self.manifest.constants.treeMonSetOrder or {})[set + 1]
        or set
    end
    offset = offset + 3
  end
  return out
end

-- data/wild/roammon_maps.asm RoamMaps.  A row is `map_id` (group, number), a
-- count byte, that many `map_id` pairs and a 0 that ends the row -- the 0 is
-- what `.Update`'s `.next` scan walks to when the start map does not match --
-- and -1 ends the table.  ORDER IS BEHAVIOUR: `.Update` picks a connection by
-- a two-bit index into the row and JumpRoamMon picks a ROW by a four-bit
-- index, so a reordered table sends the beasts somewhere else.
function RomExtractorGen2:readRoamMaps()
  local symbol = self:symbol("RoamMaps")
  local out = {}
  local at = symbol.address
  for _ = 1, 64 do
    local group = self.rom:byte(symbol.bank, at)
    if group == 0xff then break end
    local mapNum = self.rom:byte(symbol.bank, at + 1)
    local count = self.rom:byte(symbol.bank, at + 2)
    local to = {}
    for i = 0, count - 1 do
      local toId = self:mapNameByIds(
        self.rom:byte(symbol.bank, at + 3 + i * 2),
        self.rom:byte(symbol.bank, at + 4 + i * 2))
      if toId then to[#to + 1] = toId end
    end
    local mapId = self:mapNameByIds(group, mapNum)
    if mapId then out[#out + 1] = { map = mapId, to = to } end
    at = at + 3 + count * 2 + 1
  end
  return out
end

-- data/wild/bug_contest_mons.asm.  A shape of its own, and deliberately not
-- read through readGrassTable: there is no map key, no per-time rate and no
-- seven-slot list, just `db %, species, min, max` rows that
-- ChooseWildEncounter_BugContest (engine/overworld/events.asm) walks with
-- `ld de, 4`, subtracting each chance byte from a 0..99 roll until it borrows.
--
-- The list has no terminator.  The ten real rows already add to 100, so the
-- walk cannot get past the eleventh -- whose chance byte is -1, i.e. "always"
-- -- and that row is what ends the read here.  It is carried anyway, because
-- it is a row of the cart's table and it is the row a chance list edited
-- anywhere above it would fall through to.
local CONTEST_MON_RECORD = 4

function RomExtractorGen2:readContestMons()
  local symbol = self:symbol("ContestMons")
  local out = {}
  for row = 0, 31 do
    local base = symbol.address + row * CONTEST_MON_RECORD
    -- Bounded the way the rod lists above are: a table with no terminator must
    -- stop at the end of its bank rather than assert out of the import
    -- coroutine.
    if not romAddrOk(symbol.bank, base + CONTEST_MON_RECORD - 1) then break end
    local raw = self.rom:bytes(symbol.bank, base, CONTEST_MON_RECORD)
    out[row + 1] = {
      chance = raw[1],
      species = self:speciesName(raw[2]),
      min = raw[3],
      max = raw[4],
    }
    if raw[1] == 0xff then break end
  end
  return out
end

function RomExtractorGen2:extractEncounters()
  self:beginStage("Wild encounters")
  local grass = {}
  for _, name in ipairs({ "JohtoGrassWildMons", "KantoGrassWildMons" }) do
    self:trace("grass " .. name)
    for mapId, entry in pairs(self:readGrassTable(name)) do
      grass[mapId] = entry
    end
  end
  self:tick("Wild encounters", 1, 3)
  local water = {}
  for _, name in ipairs({ "JohtoWaterWildMons", "KantoWaterWildMons" }) do
    self:trace("water " .. name)
    for mapId, entry in pairs(self:readWaterTable(name)) do
      water[mapId] = entry
    end
  end
  self:tick("Wild encounters", 2, 3)

  -- FishGroups rows: chance byte then old/good/super rod pointers, each a
  -- list of (cumulative chance, species, level) triples ending at 100%.
  -- Rows with species == 0 (time_group in pokegold data/wild/fish.asm) index
  -- TimeFishGroups [day_species, day_level, nite_species, nite_level].
  self:trace("fish groups")
  local fish = self:symbol("FishGroups")
  local timeFishSym = self.symbols.TimeFishGroups and self:symbol("TimeFishGroups")
  local timeFishBank = timeFishSym and timeFishSym.bank or (fish and fish.bank)
  local timeFishAddr = timeFishSym and timeFishSym.address or (fish and 0x6BDE)
  local timeFishGroups = {}
  if timeFishBank and timeFishAddr then
    for idx = 0, 31 do
      local base = timeFishAddr + idx * 4
      if not romAddrOk(timeFishBank, base + 3) then break end
      local daySp = self.rom:byte(timeFishBank, base)
      local dayLv = self.rom:byte(timeFishBank, base + 1)
      local niteSp = self.rom:byte(timeFishBank, base + 2)
      local niteLv = self.rom:byte(timeFishBank, base + 3)
      if daySp == 0 or daySp > 251 or niteSp == 0 or niteSp > 251 then break end
      timeFishGroups[idx] = {
        day = { species = self:speciesName(daySp), level = dayLv },
        nite = { species = self:speciesName(niteSp), level = niteLv },
      }
    end
  end

  local fishGroups = {}
  local function readRod(address)
    local list = {}
    for i = 0, 7 do
      -- A rod list is terminated by its 100% row, not a length, so bail on a
      -- pointer that has left the bank rather than letting Rom.offset assert
      -- from inside the import coroutine.
      if not romAddrOk(fish.bank, address + i * 3 + 2) then break end
      local chance = self.rom:byte(fish.bank, address + i * 3)
      local species = self.rom:byte(fish.bank, address + i * 3 + 1)
      local level = self.rom:byte(fish.bank, address + i * 3 + 2)
      local entry = { chance = chance }
      if species == 0 then
        entry.timeGroup = level
        local tg = timeFishGroups[level]
        if tg then
          entry.day = tg.day
          entry.nite = tg.nite
          entry.species = tg.day.species
          entry.level = tg.day.level
        else
          entry.species = 0
          entry.level = level
        end
      else
        entry.species = self:speciesName(species)
        entry.level = level
      end
      list[#list + 1] = entry
      -- Rows are cumulative and the last one is 100% ($ff after `percent`).
      if chance >= 0xfe then break end
    end
    return list
  end
  -- FishGroups has NUM_FISHGROUPS (13) rows, one per group *except*
  -- FISHGROUP_NONE: the constants start at 0 with NONE, so the table's row for
  -- a group is its id minus one.  Walking fishGroupOrder from position 1 reads
  -- every row shifted by one and runs a row off the end of the table.
  local fishOrder = self.manifest.constants.fishGroupOrder or {}
  for index = 2, #fishOrder do
    local groupId = fishOrder[index]
    local row = index - 2
    local base = fish.address + row * 7
    fishGroups[groupId] = {
      id = groupId,
      index = index - 1,
      chance = self.rom:byte(fish.bank, base),
      old = readRod(self.rom:word(fish.bank, base + 1)),
      good = readRod(self.rom:word(fish.bank, base + 3)),
      super = readRod(self.rom:word(fish.bank, base + 5)),
    }
  end

  -- Headbutt trees: map -> TREEMON_SET_*, and each set's common/rare lists.
  self:trace("headbutt trees")
  local trees = self:readTreeMonMaps("TreeMonMaps")
  -- RockMonMaps, the four maps whose smashable rocks can hold a wild mon
  -- (Cianwood, Route 40, Dark Cave Violet Entrance, Slowpoke Well B1F).  Gated
  -- on the symbol so an older manifest still imports; RockMonEncounter answers
  -- "nothing here" for every map when the table is missing.
  local rocks = self.symbols.RockMonMaps
    and self:readTreeMonMaps("RockMonMaps") or nil

  -- TreeMons: a pointer per TREEMON_SET_*, each aiming at TWO `db %, species,
  -- level` lists back to back -- the common one and the rare one -- with a
  -- -1 between them.  Which of the two is rolled comes from how hard the tree
  -- was hit (engine/events/treemons.asm), so both are carried here.
  local treeSets = {}
  local treeMonsSymbol = self.symbols["TreeMons"] and self:symbol("TreeMons")
  if treeMonsSymbol then
    local setOrder = self.manifest.constants.treeMonSetOrder or {}
    for index, name in ipairs(setOrder) do
      local pointer = self.rom:word(treeMonsSymbol.bank,
        treeMonsSymbol.address + (index - 1) * 2)
      local at = pointer
      local lists = {}
      for _ = 1, 2 do
        local rows = {}
        for _ = 1, 16 do
          local chance = self.rom:byte(treeMonsSymbol.bank, at)
          if chance == 0xff then
            at = at + 1
            break
          end
          local species = self.rom:byte(treeMonsSymbol.bank, at + 1)
          local level = self.rom:byte(treeMonsSymbol.bank, at + 2)
          rows[#rows + 1] = {
            chance = chance,
            species = (self.manifest.constants.speciesOrder or {})[species],
            level = level,
          }
          at = at + 3
        end
        lists[#lists + 1] = rows
      end
      treeSets[name] = { common = lists[1] or {}, rare = lists[2] or {} }
    end
  end

  -- The Bug Catching Contest's own table.  It sits beside the grass rather
  -- than inside it because the park's encounters come from HERE for the
  -- twenty minutes the contest runs and from NATIONAL_PARK's grass row the
  -- rest of the time.
  -- Gated on the symbol the same way TreeMons above is, so an older manifest
  -- still imports and BugContest.MONS carries the park.
  self:trace("bug contest mons")
  local bugContest = self.symbols.ContestMons and self:readContestMons() or nil

  -- The two tables that sit IN FRONT of the ordinary ones.  Swarms are the
  -- same grass / water records keyed by map (_SwarmWildmonCheck searches them
  -- before the Johto list), and RoamMaps is where the three beasts may walk.
  -- Both were hand-written in src/core/gen2/Roamers.lua until the extractor
  -- reached them; that table stays as the fallback for an older cache.
  self:trace("swarms and roam maps")
  local swarmGrass = self.symbols.SwarmGrassWildMons
    and self:readGrassTable("SwarmGrassWildMons") or nil
  local swarmWater = self.symbols.SwarmWaterWildMons
    and self:readWaterTable("SwarmWaterWildMons") or nil
  local roamMaps = self.symbols.RoamMaps and self:readRoamMaps() or nil

  local data = {
    generation = 2,
    source = "ROM:JohtoGrassWildMons/KantoGrassWildMons/*WaterWildMons/FishGroups",
    grass = grass,
    water = water,
    fishGroups = fishGroups,
    timeFishGroups = timeFishGroups,
    trees = trees,
    rocks = rocks,
    treeSets = treeSets,
    bugContest = bugContest,
    swarmGrass = swarmGrass,
    swarmWater = swarmWater,
    roamMaps = roamMaps,
  }
  self:trace("writing encounters.lua")
  self:write("encounters", data)
  self:tick("Wild encounters", 3, 3)
  return data
end

-- Trainers.  TrainerGroups is indexed by trainer class - 1 (the table starts
-- at FALKNER = 1); each group is a run of variable-length parties whose shape
-- depends on the party's own TRAINERTYPE_* byte, ending at -1.
function RomExtractorGen2:extractTrainers()
  self:beginStage("Trainers")
  local consts = self.manifest.constants
  local classOrder = consts.trainerClassOrder or {}
  local members = consts.trainerClassMembers or {}
  local moveOrder = consts.moveOrder or {}
  local itemOrder = consts.itemOrder or {}
  local charmap = self.manifest.charmap or {}

  local groups = self:symbol("TrainerGroups")
  local trainers = self:symbol("Trainers")
  local classNames = self:symbol("TrainerClassNames")
  local attributes = self:symbol("TrainerClassAttributes")
  -- data/trainers/encounter_music.asm: `table_width 1`, one MUSIC_* id per
  -- trainer class starting at class 0 (TRAINER_NONE), which is what
  -- PlayTrainerEncounterMusic plays while the trainer walks up to you -- the
  -- short encounter jingle, not the battle theme that follows it.
  local encounterMusic = self:symbol("TrainerEncounterMusic")
  local musicOrder = consts.musicOrder or {}

  local out = {
    generation = 2,
    source = "ROM:TrainerGroups + Trainers + TrainerClassNames"
      .. " + TrainerEncounterMusic",
    classes = {},
  }

  -- TrainerClassNames is a plain @-terminated list in class order, starting
  -- at class 1 (TRAINER_NONE has no name row).
  local nameAddress = classNames.address
  local classDisplay = {}
  for index = 2, #classOrder do
    local value, consumed = self.rom:readString(
      classNames.bank, nameAddress, charmap, 0x50, 24)
    nameAddress = nameAddress + consumed
    classDisplay[classOrder[index]] = value
  end

  local typeOrder = consts.trainerTypeOrder or {}
  for classIndex = 2, #classOrder do
    local className = classOrder[classIndex]
    local classId = classIndex - 1
    local pointer = self.rom:word(
      groups.bank, groups.address + (classId - 1) * 2)
    local address = pointer
    local parties = {}
    local memberNames = members[className] or {}
    -- A group has no end marker: FalknerGroup's single party is followed
    -- straight by WhitneyGroup's label, so a scan that only watches for the
    -- party's own -1 walks through every remaining group and off the bank.
    -- The count comes from trainer_constants.asm (each `trainerclass` opens a
    -- const_def whose entries ARE that group's trainers), with the next
    -- group's pointer as the belt-and-braces bound.
    local expected = #memberNames
    local nextPointer = 0x8000
    if classIndex < #classOrder then
      local following = self.rom:word(
        groups.bank, groups.address + classId * 2)
      if following > pointer then nextPointer = following end
    end
    while (expected > 0 and #parties < expected)
        or (expected == 0 and #parties < 1) do
      if address >= nextPointer or not romAddrOk(trainers.bank, address) then
        break
      end
      local first = self.rom:byte(trainers.bank, address)
      if first == 0xff then break end
      local name, consumed = self.rom:readString(
        trainers.bank, address, charmap, 0x50, 16)
      address = address + consumed
      local trainerType = self.rom:byte(trainers.bank, address)
      address = address + 1
      local hasMoves = trainerType == 1 or trainerType == 3
      local hasItem = trainerType == 2 or trainerType == 3
      local party = {}
      while #party < 6 do
        local level = self.rom:byte(trainers.bank, address)
        if level == 0xff then break end
        local species = self.rom:byte(trainers.bank, address + 1)
        address = address + 2
        local mon = {
          level = level,
          species = self:speciesName(species),
        }
        if hasItem then
          mon.item = itemOrder[self.rom:byte(trainers.bank, address)]
          address = address + 1
        end
        if hasMoves then
          local moves = {}
          for i = 0, 3 do
            local moveId = self.rom:byte(trainers.bank, address + i)
            if moveId ~= 0 then moves[#moves + 1] = moveOrder[moveId] end
          end
          address = address + 4
          mon.moves = moves
        end
        party[#party + 1] = mon
      end
      -- Skip the -1 that ends this party.
      address = address + 1
      parties[#parties + 1] = {
        id = memberNames[#parties + 1] or
          ("%s%d"):format(className, #parties + 1),
        index = #parties + 1,
        name = name,
        trainerType = typeOrder[trainerType + 1] or trainerType,
        party = party,
      }
    end
    -- TrainerClassAttributes is SEVEN bytes a class, not eight:
    -- NUM_TRAINER_ATTRIBUTES is `_RS` after three `rb` and two `rw`
    -- (constants/trainer_data_constants.asm):
    --   1-2  TRNATTR_ITEM1 / ITEM2   the two items the trainer may use
    --   3    TRNATTR_BASEMONEY       the reward multiplier
    --   4-5  TRNATTR_AI_MOVE_WEIGHTS which scoring layers run
    --   6-7  TRNATTR_AI_ITEM_SWITCH  how eager it is to rotate, and when it
    --                                is allowed to reach for an item
    -- An eight-byte stride walks a byte further off with every class, which is
    -- why the AI flags used to be noise past the first few trainers.
    local attrRow = self.rom:bytes(
      attributes.bank, attributes.address + (classId - 1) * 7, 7)
    local carried = {}
    for slot = 1, 2 do
      local name = itemOrder[attrRow[slot]]
      if name and name ~= "NO_ITEM" then carried[#carried + 1] = name end
    end
    local musicId = self.rom:byte(
      encounterMusic.bank, encounterMusic.address + classId)
    out.classes[className] = {
      id = className,
      index = classId,
      name = classDisplay[className] or className,
      encounterMusic = musicOrder[(musicId or 0) + 1],
      -- Row 3, not row 1: the first two bytes are the items.
      baseMoney = attrRow[3],
      attributes = attrRow,
      items = carried,
      trainers = parties,
    }
    self:tick("Trainers", classIndex, #classOrder)
  end
  self:write("trainers", out)
  return out
end

-- callstd / jumpstd targets.  StdScripts is a `dba` table (bank $40), and its
-- ids are exactly the stdScriptOrder the manifest scraped from
-- engine/events/std_scripts.asm.  Resolving them is what lets
-- ReceiveItemScript, the mart/statue helpers and the phone-number scripts run
-- without every map duplicating their text.
--
-- The bodies themselves are disassembled by extractScriptsAndText, which seeds
-- its walk from `key` here -- one code path for map and std scripts alike.
function RomExtractorGen2:extractStdScripts()
  self:beginStage("Std scripts")
  local order = self.manifest.constants.stdScriptOrder or {}
  local table_ = self:symbol("StdScripts")
  local out = {
    generation = 2,
    source = "ROM:StdScripts + engine/events/std_scripts.asm order",
    order = order,
    scripts = {},
    -- id -> label, so a `callstd 2` in a disassembled script reads as a name.
    byId = {},
  }
  for index, label in ipairs(order) do
    local base = table_.address + (index - 1) * 3
    local bank = self.rom:byte(table_.bank, base)
    local address = self.rom:word(table_.bank, base + 1)
    local entry = {
      id = label,
      index = index - 1,
      bank = bank,
      address = address,
      key = Opcodes.key(bank, address),
    }
    out.scripts[label] = entry
    out.byId[index - 1] = label
    self:tick("Std scripts", index, #order)
  end
  self:write("std_scripts", out)
  return out
end

-- Pokedex: the two alternate orderings the #DEX screen can sort by, plus each
-- species' entry (kind name, height/weight, description pages).
function RomExtractorGen2:extractPokedex()
  self:beginStage("Pokedex")
  local consts = self.manifest.constants
  local speciesOrder = consts.speciesOrder or {}
  local charmap = self.manifest.charmap or {}

  -- Entries are spread over four banks ("Pokedex Entries 001-064" and
  -- friends) and the game picks the bank by rotating the species id
  -- (engine/pokegear/radio.asm), so each entry's own symbol is the reliable
  -- address -- the same reason pic labels are resolved per species.
  local entries = {}
  for index, species in ipairs(speciesOrder) do
    local asset = self.manifest.pokemonAssets[species]
    local symbol = asset and asset.dexLabel and self.symbols[asset.dexLabel]
    if symbol and species ~= "UNUSED" then
      local bank, address = symbol[1], symbol[2]
      local kind, consumed = self.rom:readString(
        bank, address, charmap, 0x50, 24)
      local sizeAt = address + consumed
      -- Both little-endian, and both are already the digits DisplayDexEntry
      -- prints rather than a physical unit: the height word is fed to PrintNum
      -- as 4 digits with 2 in front of the point (204 -> 2'04") and the weight
      -- word as 5 digits with 4 in front (150 -> 15.0 lb).
      local height = self.rom:word(bank, sizeAt)
      local weight = self.rom:word(bank, sizeAt + 2)
      -- The description is two pages: the `page` macro is a bare "@", so the
      -- second page begins where the first one's terminator left off and
      -- GetDexEntryPagePointer finds it by walking past that @.
      local text, page1Length = self.rom:readString(
        bank, sizeAt + 4, charmap, 0x50, 256)
      local text2 = self.rom:readString(
        bank, sizeAt + 4 + page1Length, charmap, 0x50, 256)
      entries[species] = {
        id = species, dex = index,
        kind = kind, height = height, weight = weight,
        text = text, text2 = text2,
      }
    end
    if index % 32 == 0 then self:tick("Pokedex", index, #speciesOrder) end
  end

  local function readOrder(symbolName, length)
    local symbol = self:symbol(symbolName)
    local list = {}
    for i = 0, length - 1 do
      local id = self.rom:byte(symbol.bank, symbol.address + i)
      list[i + 1] = speciesOrder[id] or id
    end
    return list
  end

  local data = {
    generation = 2,
    source = "ROM:PokedexDataPointerTable + NewPokedexOrder",
    entries = entries,
    -- New (Johto) order is what Gold's #DEX lists by default; alphabetical is
    -- the other sort the screen offers.
    newOrder = readOrder("NewPokedexOrder", #speciesOrder),
    alphabeticalOrder = readOrder("AlphabeticalPokedexOrder", #speciesOrder),
  }
  self:write("pokedex", data)
  self:tick("Pokedex", #speciesOrder, #speciesOrder)
  return data
end

-- Pokegear town map: each landmark's pixel position and name.  The macro adds
-- the screen origin (x + 8, y + 16) so the values are already OAM
-- coordinates; store them back in tilemap space, which is what a UI wants.
function RomExtractorGen2:extractLandmarks()
  self:beginStage("Landmarks")
  local order = self.manifest.constants.landmarkOrder or {}
  local symbol = self:symbol("Landmarks")
  local charmap = self.manifest.charmap or {}
  local out = { generation = 2, source = "ROM:Landmarks", order = order,
    landmarks = {} }
  for index, id in ipairs(order) do
    local base = symbol.address + (index - 1) * 4
    local x = self.rom:byte(symbol.bank, base) - 8
    local y = self.rom:byte(symbol.bank, base + 1) - 16
    local pointer = self.rom:word(symbol.bank, base + 2)
    local name = self.rom:readString(
      symbol.bank, pointer, charmap, 0x50, 24)
    -- charmap.asm: <BSP> ($1f) is a "breakable space", which the Town Map
    -- renders as a line break -- that is what splits NEW BARK / TOWN onto two
    -- rows.  Store it as a newline so a UI can lay it out either way.
    name = tostring(name):gsub("<BSP>", "\n")
    out.landmarks[id] = { id = id, index = index - 1, x = x, y = y, name = name }
    self:tick("Landmarks", index, #order)
  end

  -- SpawnPoints (data/maps/spawn_points.asm): map_id + x/y, one row per
  -- SPAWN_*.  SPAWN_HOME is where a New Game puts the player -- the bedroom
  -- upstairs in the player's house, not outside (intro_menu.asm NewGame sets
  -- wDefaultSpawnpoint = SPAWN_HOME and warps there).  The rest are Pokecenter
  -- respawns.
  local spawnSymbol = self:symbol("SpawnPoints")
  out.spawns = {}
  for index, id in ipairs(self.manifest.constants.spawnOrder or {}) do
    local base = spawnSymbol.address + (index - 1) * 4
    local group = self.rom:byte(spawnSymbol.bank, base)
    local mapNum = self.rom:byte(spawnSymbol.bank, base + 1)
    out.spawns[id] = {
      id = id,
      index = index - 1,
      map = self:mapNameByIds(group, mapNum),
      x = self.rom:byte(spawnSymbol.bank, base + 2),
      y = self.rom:byte(spawnSymbol.bank, base + 3),
    }
  end

  self:write("landmarks", out)
  return out
end

-- Party-menu mon icons: 16x32 sheets (two 16x16 animation frames stacked),
-- shared between species via MonMenuIcons.
local ICON_TILES = 8

function RomExtractorGen2:extractIcons()
  self:beginStage("Menu icons")
  local consts = self.manifest.constants
  local iconOrder = consts.iconOrder or {}
  local speciesOrder = consts.speciesOrder or {}
  local pointers = self:symbol("IconPointers")
  local icons = self:symbol("Icons")

  local out = { generation = 2, source = "ROM:IconPointers + MonMenuIcons",
    icons = {}, species = {} }
  for index, iconId in ipairs(iconOrder) do
    local address = self.rom:word(
      pointers.bank, pointers.address + (index - 1) * 2)
    local raw = self.rom:bytes(icons.bank, address, ICON_TILES * 16)
    local base = iconId:lower():gsub("^icon_", "")
    local rel = "icons/gen2/" .. base .. ".png"
    -- Icons are OBJ sprites, so shade 0 is the transparent color.
    self:write2bpp(raw, 16, 32, rel, true)
    out.icons[iconId] = {
      id = iconId, index = index - 1,
      image = "assets/generated/" .. rel,
      width = 16, height = 32, frames = 2,
    }
    self:tick("Menu icons", index, #iconOrder)
  end
  local monIcons = self:symbol("MonMenuIcons")
  for index, species in ipairs(speciesOrder) do
    local iconId = self.rom:byte(
      monIcons.bank, monIcons.address + (index - 1))
    out.species[species] = iconOrder[iconId + 1] or iconId
  end

  -- .SpawnItemIcon (engine/gfx/mon_icons.asm:218-228): a party mon holding
  -- something swaps its icon's BOTTOM-LEFT tile for one of the two
  -- HeldItemIcons tiles (gfx/stats/mail.2bpp then gfx/stats/item.2bpp), which
  -- GetIconGFX uploads straight after the eight icon tiles.  One 8x16 sheet,
  -- mail on top: the row order is load bearing, it is what
  -- src/ui/gen2/PartyMenu.lua heldMarkerRow indexes with.
  -- Tolerated rather than required, like UnownFont above: a manifest built
  -- before the symbol was listed still imports, it just leaves the markers
  -- undrawn.
  if self.symbols["HeldItemIcons"] then
    local markers = self:symbol("HeldItemIcons")
    local rel = "icons/gen2/held_item_markers.png"
    -- OBJ tiles, so shade 0 is transparent, the same as the icons above.
    self:write2bpp(self.rom:bytes(markers.bank, markers.address, 2 * 16),
      8, 16, rel, true)
    out.heldItem = { image = "assets/generated/" .. rel,
      width = 8, height = 8, mailRow = 0, itemRow = 1 }
  end

  self:write("icons", out)
  return out
end

-- The Gold/Silver intro movie's data (engine/movie/intro.asm).
--
-- The water and grass acts build their background the same way
-- (Intro_DrawBackground / Intro_Draw2x2Tiles): a compressed tile sheet, a
-- metatile table where every entry is four tile ids in 2x2 order, and a grid
-- of metatile indices laid across the whole 32x32 BG map.  None of it is
-- composed into a finished picture here, because the movie keeps editing the
-- map as it plays -- the water act streams a fresh metatile row in at the top
-- every 16 pixels of climb (Intro_UpdateTilemapAndBGMap) and repaints BG row
-- 15 from a four-frame wave cycle (Intro_AnimateOceanWaves), and the fire act
-- writes its Charizard rectangles straight into the map
-- (DrawIntroCharizardGraphic).  So the tables ship as tables and
-- src/ui/gen2/GoldSilverIntro.lua runs the same routines over them.
--
-- Tile sheets are written 16 tiles per row so a tile id resolves to
-- (id % 16, id / 16).  That is what data/sprite_anims/oam.asm assumes -- a
-- 4x4 OBJ is $00..$03 over $10..$13 -- and what the BG maps assume too.
local INTRO_TILEMAP_WIDTH = 16 -- TILEMAP_WIDTH / 2, counted in metatiles
local INTRO_METATILE_LENGTH = 4
local INTRO_SHEET_TILES = 16

-- The water tilemap is 16 metatiles wide by 32 tall; IntroScene1 starts
-- reading it at `Intro_WaterTilemap + 15 tiles` (row 15) and the climb walks
-- backwards a row at a time from there.  The grass tilemap is just the 16
-- rows that fill the BG map once.
local INTRO_WATER_TILEMAP_ROWS = 32
local INTRO_GRASS_TILEMAP_ROWS = 16
local INTRO_WATER_FIRST_ROW = 15

-- constants/scgb_constants.asm PREDEFPAL_*, for the palettes _CGB_GSIntro
-- pulls out of the shared pool rather than carrying inline.
local PREDEFPAL_GS_INTRO_JIGGLYPUFF_PIKACHU_BG = 56
local PREDEFPAL_GS_INTRO_JIGGLYPUFF_PIKACHU_OB = 57
local PREDEFPAL_GS_INTRO_STARTERS_TRANSITION = 58

-- OAMData_GSIntroStarter lays 25 tiles in five columns of five, which is how
-- big the three Johto starters' front pics are.
local INTRO_STARTER_TILES = 25
-- IntroScene10's three `Intro_GetMonFrontpic` destinations, as tile ids in
-- the act's OBJ sheet (vTiles0).
local INTRO_STARTER_VTILES = { 0x10, 0x29, 0x42 }

-- Pads a decompressed 2bpp stream out to whole 16-tile rows and writes it as
-- one sheet.  Returns the asset path.
function RomExtractorGen2:writeIntroSheet(pixels, relative, transparent)
  local tiles = math.floor(#pixels / 16)
  local rows = math.max(1, math.ceil(tiles / INTRO_SHEET_TILES))
  local length = rows * INTRO_SHEET_TILES * 16
  while #pixels > length do table.remove(pixels) end
  while #pixels < length do pixels[#pixels + 1] = 0 end
  self:write2bpp(pixels, INTRO_SHEET_TILES * 8, rows * 8, relative, transparent)
  return "assets/generated/" .. relative
end

-- One act's BG data: the tile sheet plus the two tables Intro_Draw2x2Tiles
-- reads.  Both tables ship as flat 1-based byte arrays; the metatile count is
-- taken from the highest index the grid actually names, so the table's end
-- does not have to be bounded by the next symbol.
function RomExtractorGen2:introBackground(gfxLabel, metaLabel, tilemapLabel,
    tilemapRows, relative)
  local out = {}
  -- BG sheets are written with colour 0 transparent so a priority OBJ shows
  -- through exactly where the hardware would let it; the backdrop the movie
  -- draws under everything is BG palette colour 0.
  out.tiles = self:writeIntroSheet(
    self:decompressLz3Symbol(gfxLabel), relative, true)

  local tilemap = self:symbol(tilemapLabel)
  local grid, highest = {}, 0
  for index = 0, tilemapRows * INTRO_TILEMAP_WIDTH - 1 do
    local value = self.rom:byte(tilemap.bank, tilemap.address + index)
    grid[index + 1] = value
    if value > highest then highest = value end
  end
  out.tilemap = grid
  out.tilemapRows = tilemapRows

  local meta = self:symbol(metaLabel)
  local metatiles = {}
  for index = 0, (highest + 1) * INTRO_METATILE_LENGTH - 1 do
    metatiles[index + 1] = self.rom:byte(meta.bank, meta.address + index)
  end
  out.meta = metatiles
  return out
end

-- PredefPals is a flat pool of 4-colour palettes; GetPredefPal indexes it by
-- the PREDEFPAL_* constant (engine/gfx/color.asm).
function RomExtractorGen2:predefPal(index)
  local pals = self:symbol("PredefPals")
  return self:colors(pals.bank, pals.address + index * 8, 4)
end

-- The movie's CGB palettes.  Every act calls WipeAttrmap, so BG palette 0
-- colours the entire screen; an OBJ's palette is the low 3 bits of its OAM
-- attribute byte, which is why the water act needs two and the others one.
function RomExtractorGen2:introPalettes()
  local waterBg = self:symbol("_CGB_GSIntro.ShellderLaprasBGPalette")
  local waterOb = self:symbol("_CGB_GSIntro.ShellderLaprasOBPals")
  local karpBg = self:symbol("Intro_LoadMagikarpPalettes.MagikarpBGPal")
  local karpOb = self:symbol("Intro_LoadMagikarpPalettes.MagikarpOBPal")
  -- _CGB_GSIntro.StartersCharizardScene runs CopyFourPalettes over
  -- PalPacket_Pack + 1, so the fire act's BG palettes are four PREDEFPAL_*
  -- indices stored inside that SGB packet.
  local packet = self:symbol("PalPacket_Pack")
  local fireBg = {}
  for slot = 1, 4 do
    fireBg[slot] = self:predefPal(
      self.rom:byte(packet.bank, packet.address + slot))
  end
  return {
    waterBg = self:colors(waterBg.bank, waterBg.address, 4),
    waterOb = {
      self:colors(waterOb.bank, waterOb.address, 4),
      self:colors(waterOb.bank, waterOb.address + 8, 4),
    },
    magikarpBg = self:colors(karpBg.bank, karpBg.address, 4),
    magikarpOb = self:colors(karpOb.bank, karpOb.address, 4),
    grassBg = self:predefPal(PREDEFPAL_GS_INTRO_JIGGLYPUFF_PIKACHU_BG),
    grassOb = self:predefPal(PREDEFPAL_GS_INTRO_JIGGLYPUFF_PIKACHU_OB),
    startersOb = self:predefPal(PREDEFPAL_GS_INTRO_STARTERS_TRANSITION),
    fireBg = fireBg,
  }
end

function RomExtractorGen2:extractIntro()
  self:beginStage("Intro movie")
  local out = { generation = 2, source = "ROM:Intro_*GFX/Tilemap/Meta" }

  -- Act 1, underwater.
  out.water = self:introBackground("Intro_WaterGFX1", "Intro_WaterMeta",
    "Intro_WaterTilemap", INTRO_WATER_TILEMAP_ROWS, "intro/water_tiles.png")
  out.water.firstRow = INTRO_WATER_FIRST_ROW
  out.water.sprites = self:writeIntroSheet(
    self:decompressLz3Symbol("Intro_WaterGFX2"), "intro/water_sprites.png",
    true)
  self:tick("Intro movie", 1, 4)

  -- Act 2, grass: same shape, its own sheet and grid, read from row 0.
  out.grass = self:introBackground("Intro_GrassGFX1", "Intro_GrassMeta",
    "Intro_GrassTilemap", INTRO_GRASS_TILEMAP_ROWS, "intro/grass_tiles.png")
  out.grass.firstRow = 0
  out.grass.sprites = self:writeIntroSheet(
    self:decompressLz3Symbol("Intro_GrassGFX2"), "intro/grass_sprites.png",
    true)
  self:tick("Intro movie", 2, 4)

  -- Act 3 has no tilemap: DrawIntroCharizardGraphic writes the silhouette's
  -- rectangle of running tile ids into the map itself.  Its BG tiles are
  -- Intro_FireGFX1 at vTiles2 ($00-$7f) followed by Intro_FireGFX2 at
  -- vTiles1 ($80-$cf), so the two decompress into one sheet.
  local fireTiles = self:decompressLz3Symbol("Intro_FireGFX1")
  while #fireTiles < 0x80 * 16 do fireTiles[#fireTiles + 1] = 0 end
  while #fireTiles > 0x80 * 16 do table.remove(fireTiles) end
  for _, byte in ipairs(self:decompressLz3Symbol("Intro_FireGFX2")) do
    fireTiles[#fireTiles + 1] = byte
  end
  out.fire = {
    tiles = self:writeIntroSheet(fireTiles, "intro/fire_tiles.png", true),
  }
  self:tick("Intro movie", 3, 4)

  -- The act's OBJ sheet is Intro_FireGFX3 (the fireball) with the three
  -- Johto starters' front pics decompressed over the top of it at $10/$29/$42.
  -- Pics are stored column-major and OAMData_GSIntroStarter reads them that
  -- way, so they go in as-is rather than through columnsToRows.
  local fireSprites = self:decompressLz3Symbol("Intro_FireGFX3")
  for index, label in ipairs({
    "ChikoritaFrontpic", "CyndaquilFrontpic", "TotodileFrontpic",
  }) do
    local pic = self:decompressLz3Symbol(label)
    local base = INTRO_STARTER_VTILES[index] * 16
    for offset = 1, INTRO_STARTER_TILES * 16 do
      fireSprites[base + offset] = pic[offset] or 0
    end
  end
  out.fire.sprites = self:writeIntroSheet(fireSprites,
    "intro/fire_sprites.png", true)

  out.palettes = self:introPalettes()
  self:write("intro", out)
  self:tick("Intro movie", 4, 4)
  return out
end

-- Menu chrome that is not part of the font: the naming screen's patterned
-- backdrop tile, its 2-tile cursor, and the middle/under line glyphs that mark
-- the name-entry field.  These are loaded straight into VRAM by
-- LoadNamingScreenGFX rather than living in a font page, so nothing else in
-- the import would pick them up.
function RomExtractorGen2:extractMenuGfx()
  self:beginStage("Menu graphics")
  local out = { generation = 2, source = "ROM:NamingScreenGFX_*" }

  -- Border is 2bpp and tiles the whole screen, so it stays opaque.
  local border = self:symbol("NamingScreenGFX_Border")
  self:write2bpp(self.rom:bytes(border.bank, border.address, 16), 8, 8,
    "naming/border.png")
  out.border = "assets/generated/naming/border.png"

  -- Cursor is 2bpp and 2 tiles, drawn as an 8x16 OBJ (the naming screen's
  -- cursor is a tall arrow, not a wide one), so the sheet is one tile wide by
  -- two tall.  It is an OBJ, so color 0 is transparent.
  local cursor = self:symbol("NamingScreenGFX_Cursor")
  self:write2bpp(self.rom:bytes(cursor.bank, cursor.address, 32), 8, 16,
    "naming/cursor.png", true)
  out.cursor = "assets/generated/naming/cursor.png"

  -- Both lines are 1bpp; inkFrom1bpp gives black-on-transparent so they can be
  -- drawn in whatever color the screen is using.
  for key, label in pairs({
    middleLine = "NamingScreenGFX_MiddleLine",
    underLine = "NamingScreenGFX_UnderLine",
  }) do
    local symbol = self:symbol(label)
    local raw = self.rom:bytes(symbol.bank, symbol.address, 8)
    local rel = "naming/" .. key:lower() .. ".png"
    self:save(inkFrom1bpp(raw, 8, 8), rel)
    out[key] = "assets/generated/" .. rel
  end

  -- Battle HUD tiles (engine/gfx/load_font.asm LoadHPBar).  The HUD is built
  -- out of tiles on the cart, so extracting them is what makes the layout
  -- align on the 8px grid by construction instead of by eye:
  --
  --   FontBattleExtra    -> $60: "HP:" is $60/$61, then the HP bar's cells
  --                         $62 (empty) .. $6a (8px full) and $6b (end cap)
  --   EnemyHPBarBorderGFX-> $6c: 4 tiles; $6d left side, $6f bottom left
  --   HPExpBarBorderGFX  -> $73: 6 tiles; $73 right side, $74 bottom left,
  --                         $76 bottom side, $77/$78 bottom right
  --   ExpBarGFX          -> $55: 9 exp-bar fill cells
  --
  -- The two border sheets are 1bpp, so they come out as black ink on
  -- transparent and can be drawn in any color; the exp bar is 2bpp.
  local hud = {}
  local enemyBorder = self:symbol("EnemyHPBarBorderGFX")
  self:save(inkFrom1bpp(
    self.rom:bytes(enemyBorder.bank, enemyBorder.address, 4 * 8), 32, 8),
    "battle/hud/enemy_border.png")
  hud.enemyBorder = "assets/generated/battle/hud/enemy_border.png"
  hud.enemyBorderFirstTile = 0x6c

  local playerBorder = self:symbol("HPExpBarBorderGFX")
  self:save(inkFrom1bpp(
    self.rom:bytes(playerBorder.bank, playerBorder.address, 6 * 8), 48, 8),
    "battle/hud/player_border.png")
  hud.playerBorder = "assets/generated/battle/hud/player_border.png"
  hud.playerBorderFirstTile = 0x73

  -- The player's own back-pic, which stands in the player's box for the whole
  -- battle intro.  gfx/player/chris_back.png is 48x48, i.e. SIX tiles square:
  -- GetTrainerBackpic's `ld c, 7 * 7` is how many tiles of VRAM it asks for,
  -- not how big the pic is, and reading it as 7x7 scrambles every column.
  -- Column-major like every other pic, hence columnsToRows.
  if self.symbols["ChrisBackpic"] then
    local ok = pcall(function()
      self:writeCompressedPic("ChrisBackpic", 6, "battle/player_back.png")
    end)
    if ok then hud.playerBack = "assets/generated/battle/player_back.png" end
  end

  -- GetTrainerBackpic's "Special exception for Dude": the catching tutorial
  -- draws DudeBackpic in that same box, from the same bank and at the same six
  -- tiles square (src/core/gen2/CatchTutorial.lua).
  if self.symbols["DudeBackpic"] then
    local ok = pcall(function()
      self:writeCompressedPic("DudeBackpic", 6, "battle/dude_back.png")
    end)
    if ok then hud.dudeBack = "assets/generated/battle/dude_back.png" end
  end

  -- TrainerPicPointers (data/trainers/pic_pointers.asm): one `dba_pic` per
  -- trainer class, `table_width 3`.  GetTrainerPic (engine/gfx/load_pics.asm:
  -- 254-257) indexes it with `ld a, [wTrainerClass] / dec a / ld bc, 3`, so
  -- row 0 is FALKNER and TRAINER_NONE has no row at all.  Trainer pics are
  -- always 7 tiles square (`ld c, 7 * 7`, :277) and, unlike a mon frontpic,
  -- are never PadFrontpic'd.
  if self.symbols["TrainerPicPointers"] then
    local symbol = self:symbol("TrainerPicPointers")
    local classOrder = (self.manifest.constants or {}).trainerClassOrder or {}
    local pics = {}
    for index, class in ipairs(classOrder) do
      -- index 1 is TRAINER_NONE (class 0), which the `dec a` skips.
      if index >= 2 then
        local base = symbol.address + (index - 2) * 3
        local bank = FIX_PIC_BANK[self.rom:byte(symbol.bank, base)]
          or self.rom:byte(symbol.bank, base)
        local address = self.rom:word(symbol.bank, base + 1)
        local rel = ("battle/trainers/%s.png"):format(class:lower())
        local ok, err = pcall(function()
          -- Same bank-crossing read as the Unown pics: GetLZByte drops back
          -- to $4000 in the next bank once the read pointer passes $8000.
          local compressed = self.rom:bytes(bank, address, 0x8000 - address)
          local nextBank = self.rom:bytes(bank + 1, 0x4000, 0x4000)
          for _, byte in ipairs(nextBank) do
            compressed[#compressed + 1] = byte
          end
          local pixels = Rom.decompressLz3(compressed)
          local byteLength = 56 * 56 / 4
          while #pixels < byteLength do pixels[#pixels + 1] = 0 end
          while #pixels > byteLength do table.remove(pixels) end
          pixels = ImageWriter.columnsToRows(pixels, 7, 7)
          self:write2bpp(pixels, 56, 56, rel)
        end)
        if ok then
          pics[class] = "assets/generated/" .. rel
        else
          self:trace(("trainer pic %s: %s"):format(class, tostring(err)))
        end
      end
    end
    hud.trainerPics = pics
  end

  local expBar = self:symbol("ExpBarGFX")
  self:write2bpp(self.rom:bytes(expBar.bank, expBar.address, 9 * 16),
    72, 8, "battle/hud/exp_bar.png")
  hud.expBar = "assets/generated/battle/hud/exp_bar.png"
  hud.expBarFirstTile = 0x55
  hud.expBarCells = 9

  -- Four OAM tiles at $31 -- normal, statused, fainted, empty -- and OBJ
  -- colour 0 is transparent (engine/battle/trainer_huds.asm:47-99, :225-232).
  local balls = self.symbols["LoadBallIconGFX.gfx"] or BALL_ICON_GFX
  self:write2bpp(self.rom:bytes(balls[1], balls[2], 4 * 16), 32, 8,
    "battle/hud/balls.png", true)
  hud.balls = "assets/generated/battle/hud/balls.png"
  hud.ballsFirstTile = 0x31

  -- "HP:" and the bar cells, as a plain 2bpp sheet rather than the ink-on-
  -- transparent font page: the bar's rule is shade 3 (black) while its fill is
  -- shade 1/2 (the HP colour), so flattening it to one ink loses the very
  -- distinction that makes the bar readable.  Drawn through GbcPalette with
  -- palettes.hpBar, exactly like the cart colours it from HPBarPals.
  local battleExtra = self:symbol("FontBattleExtra")
  self:write2bpp(
    self.rom:bytes(battleExtra.bank, battleExtra.address, 12 * 16),
    96, 8, "battle/hud/hp_bar.png")
  hud.hpBar = "assets/generated/battle/hud/hp_bar.png"
  hud.hpBarTiles = 12
  hud.battleExtra = "assets/generated/fonts/font_battle_extra.png"
  hud.battleExtraFirstTile = 0x60
  hud.hpLabelTiles = { 0x60, 0x61 }
  hud.hpBarEmptyTile = 0x62
  hud.hpBarFullTile = 0x6a
  hud.hpBarEndTile = 0x6b
  out.battleHud = hud

  -- PACK (engine/items/pack.asm).  The screen is built the same way the
  -- battle HUD is -- out of the cart's own tiles at the cart's own coordinates
  -- -- rather than from rectangles:
  --
  --   PackMenuGFX -> $00: $60 tiles.  Pack_InitGFX copies the whole sheet to
  --                  vTiles2 tile $00, fills rows 1-11 with $24, and lays the
  --                  header strip at (0,0) as $28..$3b (20 running tiles).
  --   PackGFX     -> $50: four 15-tile (5x3) pack pictures.  DrawPackGFX swaps
  --                  in the one for wCurPocket and PlacePackGFX lays $50..$5e
  --                  at (0,3).  PackGFXPointers orders them KEY_ITEM, ITEM,
  --                  TM_HM, BALL in ROM, indexed by pocket.
  --   pocket name -> DrawPocketName's 5x12 tilemap: four 5x3 blocks, laid at
  --                  (0,7), one per pocket in *_POCKET order.
  --   palettes    -> _CGB_PackPals: six BG palettes and the attrmap zones that
  --                  make the header halves, the pack picture and the pocket
  --                  name different colours.
  local pack = {}
  local packMenu = self:symbol("PackMenuGFX")
  self:write2bpp(self.rom:bytes(packMenu.bank, packMenu.address, 0x60 * 16),
    128, 48, "pack/menu.png")
  pack.menu = "assets/generated/pack/menu.png"
  pack.menuTiles = 0x60
  pack.menuTilesWide = 16
  pack.backgroundTile = 0x24
  pack.headerFirstTile = 0x28

  local packGfx = self:symbol("PackGFX")
  self:write2bpp(self.rom:bytes(packGfx.bank, packGfx.address, 60 * 16),
    40, 96, "pack/pack.png")
  pack.pack = "assets/generated/pack/pack.png"
  pack.packFirstTile = 0x50
  pack.packTilesWide = 5
  pack.packTilesHigh = 3
  -- PackGFXPointers, as the tile row each pocket's picture starts on.
  pack.pocketPicture = {
    ITEM = 15, BALL = 45, KEY_ITEM = 0, TM_HM = 30,
  }

  local pocketMap = self:symbol("DrawPocketName.tilemap")
  local pocketRaw = self.rom:bytes(pocketMap.bank, pocketMap.address, 60)
  pack.pocketName = {}
  for block = 0, 3 do
    local tiles = {}
    for i = 1, 15 do tiles[i] = pocketRaw[block * 15 + i] end
    pack.pocketName[block + 1] = tiles
  end
  -- constants/item_data_constants.asm *_POCKET order.
  pack.pocketOrder = { "ITEM", "BALL", "KEY_ITEM", "TM_HM" }

  local packPals = self:symbol("_CGB_PackPals.PackPals")
  pack.palettes = {}
  for i = 0, 5 do
    pack.palettes[i + 1] = self:colors(packPals.bank, packPals.address + i * 8, 4)
  end
  -- _CGB_PackPals' FillBoxCGB calls, as {x, y, width, height, palette}.
  pack.paletteZones = {
    { 0, 0, 10, 1, 2 },
    { 10, 0, 10, 1, 3 },
    { 7, 2, 1, 9, 4 },
    { 0, 7, 5, 3, 5 },
    { 0, 3, 5, 3, 6 },
  }
  out.pack = pack
  out.pokedex = self:pokedexGfx()
  out.pokegear = self:pokegearGfx()
  out.trainerCard = self:trainerCardGfx()
  out.unownPuzzle = self:unownPuzzleGfx()

  -- Emote bubbles (data/sprites/emotes.asm).  Each is 4 tiles laid row-major
  -- (TL, TR, BL, BR), unlike the pics, so they decode straight to a 16x16
  -- sheet.  They are OBJs, so colour 0 is transparent.  Only the ones a
  -- walkthrough reaches are pulled; showemote shows no bubble for the rest.
  local emotes = {}
  for key, label in pairs({
    shock = "ShockEmote",
    question = "QuestionEmote",
    happy = "HappyEmote",
    sad = "SadEmote",
    heart = "HeartEmote",
    bolt = "BoltEmote",
    sleep = "SleepEmote",
    fish = "FishEmote",
  }) do
    local symbol = self.symbols[label]
    if symbol then
      local raw = self.rom:bytes(symbol[1], symbol[2], 4 * 16)
      self:write2bpp(raw, 16, 16, "emotes/" .. key .. ".png", true)
      emotes[key] = "assets/generated/emotes/" .. key .. ".png"
    end
  end
  -- constants/script_constants.asm:188-195 EMOTE_* order, so showemote's byte
  -- indexes straight into it.
  emotes.order = { "shock", "question", "happy", "sad", "heart", "bolt",
    "sleep", "fish" }
  -- data/sprites/emotes.asm:22 `emote GrassRustleGFX, 1, $fe`: one tile, the
  -- object ShakeGrass spawns (engine/overworld/map_objects.asm:2031).
  local rustle = self.symbols["GrassRustleGFX"]
  if rustle then
    self:write2bpp(self.rom:bytes(rustle[1], rustle[2], 16),
      8, 8, "emotes/grass_rustle.png", true)
    emotes.grassRustle = "assets/generated/emotes/grass_rustle.png"
  end
  out.emotes = emotes

  -- The Pokecenter heal machine's OBJ art (engine/events/heal_machine_anim
  -- .asm .HealMachineGFX): two tiles side by side -- $7c the machine's light,
  -- $7d the ball -- decoded as a 16x8 sheet with colour 0 transparent, the
  -- way every OBJ sheet is.  `.palettes` is gfx/overworld/heal_machine.pal,
  -- the four colours .LoadPalettes copies over PAL_OW_TREE while the machine
  -- runs; World's anim rotates them per flash the way .FlashPalettes does.
  -- Both symbols are post-Phase-2 manifest additions, so a cache built from
  -- an older manifest simply has no healMachine entry and the anim degrades
  -- to its sounds.
  local healGfx = self.symbols["HealMachineAnim.HealMachineGFX"]
  if healGfx then
    self:write2bpp(self.rom:bytes(healGfx[1], healGfx[2], 2 * 16),
      16, 8, "emotes/heal_machine.png", true)
    local healPal = self.symbols["HealMachineAnim.palettes"]
    out.healMachine = {
      sheet = "assets/generated/emotes/heal_machine.png",
      palette = healPal and self:colors(healPal[1], healPal[2], 4) or nil,
    }
  end

  -- The egg hatch cutscene's two assets (engine/pokemon/breeding.asm
  -- EggHatch_AnimationSequence).
  --
  --   EggPic       gfx/pokemon/egg/egg.2bpp.lz.  EGG has no BaseData row, so
  --                GetBaseData's `.egg` arm hardcodes `ld b, $55` -- 5 tiles
  --                square (home/pokemon.asm:239-245) -- and GetFrontpic reads
  --                the label directly instead of walking PokemonPicPointers.
  --                A `--columns` pic like every other frontpic.
  --   EggHatchGFX  gfx/evo/egg_hatch.2bpp, TWO tiles copied to vTiles0 tile
  --                $00 (breeding.asm:777): the crack and the shell fragment
  --                the ten SPRITE_ANIM_OBJ_EGG_HATCH objects all draw from.
  --                An OBJ sheet, so colour 0 is transparent.
  --
  -- Both are guarded: a cache built from an older manifest simply has no
  -- eggHatch entry and src/ui/gen2/EggHatchAnim.lua runs its timing-only beat.
  local eggHatch = {}
  if self.symbols["EggPic"] then
    local ok = pcall(function()
      self:writeCompressedPic("EggPic", 5, "battle/front/egg.png")
    end)
    if ok then eggHatch.egg = "assets/generated/battle/front/egg.png" end
  end
  local hatchGfx = self.symbols["EggHatchGFX"]
  if hatchGfx then
    local symbol = self:symbol("EggHatchGFX")
    self:write2bpp(self.rom:bytes(symbol.bank, symbol.address, 2 * 16),
      8, 16, "menu/egg_hatch.png", true)
    eggHatch.shell = "assets/generated/menu/egg_hatch.png"
    eggHatch.shellTiles = 2
  end
  if eggHatch.egg or eggHatch.shell then out.eggHatch = eggHatch end

  self:write("menu_gfx", out)
  self:tick("Menu graphics", 1, 1)
  return out
end

-- Unown puzzle art (engine/games/unown_puzzle.asm).
--
-- The four pictures are stored SMALL: each `*PuzzleLZ` decompresses to 36
-- tiles (48x48), and ConvertLoadedPuzzlePieces doubles them on the way into
-- VRAM.  `.EnlargePuzzlePieceTiles` walks one source ROW at a time, first the
-- top four pixel rows of its six tiles and then the bottom four, splitting
-- each tile's high and low nibbles into two destination tiles -- which adds up
-- to a plain 2x nearest-neighbour scale laid out as a 12x12 tile sheet.  The
-- scale is done here rather than at draw time so the border pass below, which
-- is a bitplane OR at the ENLARGED resolution, lands on the same bytes the
-- cart ORs.
--
-- .EnlargedTiles: each nibble bit becomes two bits, so $f -> $ff and $8 ->
-- $c0.  Built rather than transcribed; the `for x, 16` in the asm builds it
-- the same way.
local ENLARGED_NIBBLE = {}
for value = 0, 15 do
  ENLARGED_NIBBLE[value] = (value % 2) * 3
    + (math.floor(value / 2) % 2) * 0x0c
    + (math.floor(value / 4) % 2) * 0x30
    + (math.floor(value / 8) % 2) * 0xc0
end

local function orByte(a, b)
  local out, bit = 0, 1
  for _ = 1, 8 do
    if (a % 2) == 1 or (b % 2) == 1 then out = out + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return out
end

-- UnownPuzzle_AddPuzzlePieceBorders' eight destination tiles: the outline is
-- drawn on every tile of a 3x3 piece EXCEPT its centre ($0d), and .LoadGFX
-- repeats each one across the 4x4 grid of pieces (+3 tiles per column, +36 per
-- row, since the sheet is 12 tiles wide).
local PUZZLE_BORDER_TILES = { 0x00, 0x01, 0x02, 0x0c, 0x0e, 0x18, 0x19, 0x1a }

function RomExtractorGen2:unownPuzzlePicture(label, relative)
  local small = self:decompressLz3Symbol(label)
  local out = {}
  for row = 0, 5 do
    for half = 0, 1 do
      for col = 0, 5 do
        local base = (row * 6 + col) * 16 + half * 8
        for nibble = 0, 1 do
          for line = 0, 3 do
            local low = small[base + line * 2 + 1] or 0
            local high = small[base + line * 2 + 2] or 0
            if nibble == 0 then
              low, high = math.floor(low / 16), math.floor(high / 16)
            else
              low, high = low % 16, high % 16
            end
            low, high = ENLARGED_NIBBLE[low], ENLARGED_NIBBLE[high]
            out[#out + 1] = low
            out[#out + 1] = high
            out[#out + 1] = low
            out[#out + 1] = high
          end
        end
      end
    end
  end
  local borders = self:symbol("PuzzlePieceBorderData.TileBordersGFX")
  local raw = self.rom:bytes(borders.bank, borders.address, 8 * 16)
  for index, target in ipairs(PUZZLE_BORDER_TILES) do
    for pieceRow = 0, 3 do
      for pieceCol = 0, 3 do
        local tile = target + pieceCol * 3 + pieceRow * 36
        for byte = 1, 16 do
          local at = tile * 16 + byte
          out[at] = orByte(out[at] or 0, raw[(index - 1) * 16 + byte] or 0)
        end
      end
    end
  end
  self:write2bpp(out, 96, 96, relative)
  return "assets/generated/" .. relative
end

function RomExtractorGen2:unownPuzzleGfx()
  local puzzle = {}
  -- .LZPointers, in UNOWNPUZZLE_* order (constants/script_constants.asm), so
  -- the `setval` the chamber's bg_event runs indexes this list from 0.
  puzzle.pictures = {}
  for index, row in ipairs({
    { "KABUTO", "KabutoPuzzleLZ" },
    { "OMANYTE", "OmanytePuzzleLZ" },
    { "AERODACTYL", "AerodactylPuzzleLZ" },
    { "HO_OH", "HoOhPuzzleLZ" },
  }) do
    puzzle.pictures[index] = self:unownPuzzlePicture(row[2],
      "menu/unown_puzzle/" .. row[1]:lower() .. ".png")
  end
  -- The picture is 4x4 pieces of 3x3 tiles; `.Corners` is the same arithmetic
  -- written out, so a piece id (1..16) is a quad rather than a tile run.
  puzzle.pieceTiles = 3
  puzzle.piecesWide = 4

  -- UnownPuzzleStartCancelLZ lands at vTiles0 tile $ed: $ee is PUZZLE_BORDER,
  -- $ef PUZZLE_VOID, $f0..$f5 the START>CANCEL box corners and edges, and
  -- $f6..$ff the ten tiles of the caption itself.
  local chrome = self:decompressLz3Symbol("UnownPuzzleStartCancelLZ")
  self:write2bpp(chrome, 152, 8, "menu/unown_puzzle/chrome.png")
  puzzle.chrome = "assets/generated/menu/unown_puzzle/chrome.png"
  puzzle.chromeFirstTile = 0xed
  puzzle.chromeTiles = 19

  -- UnownPuzzleCursorGFX is four OBJ tiles at vTiles0 $e0; the cursor's OAM
  -- template mirrors them into a 3x3 bracket, so the sheet stays one row of
  -- four rather than a 2x2 square.
  local cursor = self:symbol("UnownPuzzleCursorGFX")
  self:write2bpp(self.rom:bytes(cursor.bank, cursor.address, 4 * 16),
    32, 8, "menu/unown_puzzle/cursor.png", true)
  puzzle.cursor = "assets/generated/menu/unown_puzzle/cursor.png"
  puzzle.cursorFirstTile = 0xe0

  -- _CGB_UnownPuzzle (engine/gfx/cgb_layouts.asm:570) runs CopyFourPalettes
  -- over PalPacket_UnownPuzzle, which is PREDEFPAL_UNOWN_PUZZLE four times, and
  -- WipeAttrmap then puts every BG tile on palette 0: the whole board is
  -- white / tan / dark brown / black.  The `ld a, $e4` in _UnownPuzzle
  -- (engine/games/unown_puzzle.asm:53) runs AFTER GetSGBLayout and is the
  -- identity reorder of that palette, not a grey ramp.
  puzzle.palette = self:predefPal(PREDEFPAL_UNOWN_PUZZLE)
  -- The same palette goes into wOBPals1 with colour 0 overwritten by
  -- `palred 31` (cgb_layouts.asm:577-581), and `ld a, $24 / call
  -- DmgToCgbObjPal0` reorders OBJ pal 0 to entries 0, 1, 2, 0 -- so the cursor
  -- bracket draws red.
  local ob = self:predefPal(PREDEFPAL_UNOWN_PUZZLE)
  ob[1] = { 255, 0, 0 }
  puzzle.cursorPalette = { ob[1], ob[2], ob[3], ob[1] }
  return puzzle
end

-- constants/scgb_constants.asm PREDEFPAL_*, for the two screens that colour
-- themselves out of the shared pool rather than an inline palette.
local PREDEFPAL_POKEDEX = 29
local PREDEFPAL_CGB_BADGE = 36

-- The GB tilemap, in tiles (SCREEN_WIDTH * SCREEN_HEIGHT).
local SCREEN_AREA = 20 * 18

-- #DEX chrome (engine/pokedex/pokedex.asm).
--
-- Pokedex_LoadGFX is four steps and only the last one is a sheet of its own:
-- the standard font goes to vTiles1 and is *inverted* (xor $ff flips both
-- bitplanes, so colour c becomes 3 - c), FontExtra lands at $60 and is
-- inverted too, and then PokedexLZ decompresses over vTiles2 tile $31 and
-- takes $31..$70 back off it.  The inversion is why the dex prints white on
-- black: under PREDEFPAL_POKEDEX (white, orange, dark red, black) an inverted
-- glyph's ink is colour 0 and its cell is colour 3.  Nothing here has to
-- invert anything -- the font pages are ink on transparent and the screen
-- draws them in white over the sheet's own dark tiles.
--
-- Tile ids the screens name, all relative to that one sheet:
--   $31 solid black, $32 the dark-red background ByteFill uses
--   $33..$3a the box frame (Pokedex_PlaceBorder: corners $33/$35/$38/$3a,
--            edges $34 top, $36 left, $37 right, $39 bottom)
--   $3b/$3c the ◀/▶ card arrows, $3d/$3e the ▲/▼ ones
--   $41..$4e the START/SEARCH/SELECT/OPTION word tiles, $4f the caught ball
--   $53/$54/$59/$5a/$5b the listing's vertical rule and its end caps
--   $55..$58 the dex entry's PAGE 1/2 marker, $5c/$5d "No.",
--            $5e ' and $5f ", $61 the horizontal divider, $62..$65 footprint
function RomExtractorGen2:pokedexGfx()
  local dex = {}
  local pixels = self:decompressLz3Symbol("PokedexLZ")
  local tiles = math.floor(#pixels / 16)
  local rows = math.ceil(tiles / 16)
  while #pixels < rows * 16 * 16 do pixels[#pixels + 1] = 0 end
  self:write2bpp(pixels, 128, rows * 8, "pokedex/dex.png")
  dex.tiles = "assets/generated/pokedex/dex.png"
  dex.tilesWide = 16
  dex.firstTile = 0x31
  dex.tileCount = tiles
  -- The dex's OBJ sheet, at vTiles0.  The search screen's Slowpoke is the
  -- front of it; $30..$33 are the bracket the listing cursor is drawn from
  -- (Pokedex_PutNewModeABCModeCursorOAM) and $0f the scrollbar thumb.
  local objs = self:decompressLz3Symbol("PokedexSlowpokeLZ")
  local objTiles = math.floor(#objs / 16)
  local objRows = math.ceil(objTiles / 16)
  while #objs < objRows * 16 * 16 do objs[#objs + 1] = 0 end
  self:write2bpp(objs, 128, objRows * 8, "pokedex/objs.png", true)
  dex.objs = "assets/generated/pokedex/objs.png"
  dex.objsWide = 16
  -- _CGB_Pokedex loads PREDEFPAL_POKEDEX as BG palette 0 for the whole
  -- interface and the mon's own palette as 1 for the 7x7 frontpic;
  -- _CGB_Pokedex_Resume puts PokedexCursorPalette in OBJ slot 7, which is the
  -- palette every cursor sprite names.
  dex.palette = self:predefPal(PREDEFPAL_POKEDEX)
  local cursorPal = self:symbol("PokedexCursorPalette")
  dex.cursorPalette = self:colors(cursorPal.bank, cursorPal.address, 4)

  -- An unseen mon shows LoadQuestionMarkPic's 7x7 pic where the frontpic
  -- goes, in its own green palette.  It is a `--columns` pic like the mons'.
  self:writeCompressedPic("LoadQuestionMarkPic.QuestionMarkLZ", 7,
    "pokedex/question_mark.png")
  dex.questionMark = "assets/generated/pokedex/question_mark.png"
  local qmPal = self:symbol("PokedexQuestionMarkPalette")
  dex.questionMarkPalette = self:colors(qmPal.bank, qmPal.address, 4)

  -- Footprints (Pokedex_LoadAnyFootprint).  Each is 16x16 in 1bpp, but not
  -- contiguously: the table is 256-byte blocks of eight species, the eight
  -- top halves first and the eight bottom halves 128 bytes later, which the
  -- ASM's own comment blames on a mis-set tile editor.  Written as one
  -- 16-pixel-wide strip, two tile rows per species in speciesOrder.
  local prints = self:symbol("Footprints")
  local species = self.manifest.constants.speciesOrder or {}
  local stream = {}
  for index = 1, #species do
    local base = math.floor((index - 1) / 8) * 256 + ((index - 1) % 8) * 16
    for i = 0, 15 do
      stream[#stream + 1] = self.rom:byte(prints.bank, prints.address + base + i)
    end
    for i = 0, 15 do
      stream[#stream + 1] =
        self.rom:byte(prints.bank, prints.address + base + 128 + i)
    end
  end
  self:save(ImageWriter.decode1bpp(stream, 16, #species * 16),
    "pokedex/footprints.png")
  dex.footprints = "assets/generated/pokedex/footprints.png"
  dex.footprintOrder = species
  return dex
end

-- Reads a `tile, count` RLE tilemap (Pokegear_LoadTilemapRLE).  The routine's
-- own comment says "repeat count, tile ID" and has it backwards: it loads b
-- from the first byte, c from the second, and writes `b` c times.  $ff ends
-- the stream.
function RomExtractorGen2:readTilemapRLE(label, cells)
  local symbol = self:symbol(label)
  local out, offset = {}, 0
  while #out < cells do
    local tile = self.rom:byte(symbol.bank, symbol.address + offset)
    if tile == 0xff then break end
    local count = self.rom:byte(symbol.bank, symbol.address + offset + 1)
    offset = offset + 2
    for _ = 1, count do
      if #out >= cells then break end
      out[#out + 1] = tile
    end
  end
  -- A stream that stops short leaves the screen holding whatever
  -- InitPokegearTilemap put there, and that is `ld a, $4f / call ByteFill`
  -- over the whole SCREEN_AREA (engine/pokegear/pokegear.asm:232-238), not a
  -- blank.  Only rows 12-17 are ever reached, which every card covers with its
  -- bottom Textbox, so this is invisible until a card stops doing that.
  while #out < cells do out[#out + 1] = 0x4f end
  return out
end

-- Reads a flat $ff-terminated tilemap (FillTownMap).
function RomExtractorGen2:readFlatTilemap(label, cells)
  local symbol = self:symbol(label)
  local out = {}
  for i = 0, cells - 1 do
    local tile = self.rom:byte(symbol.bank, symbol.address + i)
    if tile == 0xff then break end
    out[i + 1] = tile
  end
  -- Same InitPokegearTilemap fill as readTilemapRLE above.
  while #out < cells do out[#out + 1] = 0x4f end
  return out
end

-- POKeGEAR (engine/pokegear/pokegear.asm).
--
-- Pokegear_LoadGFX puts TownMapGFX (48 tiles) at vTiles2 $00 and PokegearGFX
-- (48 tiles) at $30, so a card's tilemap addresses one 96-tile sheet and the
-- split at $30 is the only seam.  Each card is a tilemap rather than a
-- layout: InitPokegearTilemap fills the screen with $4f, runs the card's
-- entry (an RLE tilemap for CLOCK/PHONE/RADIO, the painted region map for
-- MAP), then Pokegear_FinishTilemap lays the card icons across the top two
-- rows -- MAP at (2,0) from $40, PHONE at (4,0) from $44, RADIO at (6,0)
-- from $42, and the gear itself at (0,0) from $46, each a 2x2 written
-- $n, $n+1 / $n+2, $n+3.
--
-- Colour is by tile id, not by rectangle: TownMapPals walks the tilemap and
-- reads .PalMap, a nybble per tile for $00..$5f (low nybble even ids, high
-- odd), with $60 and up falling back to palette 0.
function RomExtractorGen2:pokegearGfx()
  local gear = {}
  local townMap = self:decompressLz3Symbol("TownMapGFX")
  local gearTiles = self:decompressLz3Symbol("PokegearGFX")
  -- One sheet, 16 tiles per row, so a tile id is (id % 16, id / 16) the same
  -- way the intro's sheets read.
  local sheet = {}
  for i = 1, 0x30 * 16 do sheet[i] = townMap[i] or 0 end
  for i = 1, 0x30 * 16 do sheet[0x30 * 16 + i] = gearTiles[i] or 0 end
  self:write2bpp(sheet, 128, 48, "pokegear/gear.png")
  gear.tiles = "assets/generated/pokegear/gear.png"
  gear.tilesWide = 16
  gear.townMapTiles = 0x30

  local sprites = self:decompressLz3Symbol("PokegearSpritesGFX")
  while #sprites < 10 * 16 do sprites[#sprites + 1] = 0 end
  self:write2bpp(sprites, 16, 40, "pokegear/sprites.png", true)
  gear.sprites = "assets/generated/pokegear/sprites.png"
  gear.spritesWide = 2

  local cells = SCREEN_AREA
  gear.cards = {
    clock = self:readTilemapRLE("ClockTilemapRLE", cells),
    phone = self:readTilemapRLE("PhoneTilemapRLE", cells),
    radio = self:readTilemapRLE("RadioTilemapRLE", cells),
  }
  gear.maps = {
    johto = self:readFlatTilemap("JohtoMap", cells),
    kanto = self:readFlatTilemap("KantoMap", cells),
  }

  local pals = self:symbol("PokegearPals")
  gear.palettes = {}
  for i = 0, 5 do
    gear.palettes[i + 1] = self:colors(pals.bank, pals.address + i * 8, 4)
  end
  -- TownMapPals.PalMap: 48 bytes covering tiles $00..$5f, 1-based so the value
  -- indexes gear.palettes directly.
  local palMap = self:symbol("TownMapPals.PalMap")
  gear.palMap = {}
  for i = 0, 47 do
    local byte = self.rom:byte(palMap.bank, palMap.address + i)
    gear.palMap[i * 2 + 1] = byte % 8 + 1
    gear.palMap[i * 2 + 2] = math.floor(byte / 16) % 8 + 1
  end
  return gear
end

-- Trainer card (engine/menus/trainer_card.asm).
--
-- ChrisPicAndTrainerCardGFX is two INCBINs run together -- chris_card (35
-- tiles, the 5x7 portrait) then trainer_card (6 tiles, the frame) -- copied
-- as one 41-tile block to vTiles2 $00, so the frame tiles start at $23:
-- $23 is the card's border cell, $24 and $04 the two notches
-- TrainerCard_InitBorder pokes into rows 7 and 1 of each box.
--
-- Page 1 then requests 86 tiles of CardStatusGFX at $29 and pages 2/3
-- request LeaderGFX at the same address; the badges themselves are OBJs out
-- of BadgeGFX with TrainerCard_JohtoBadgesOAM as their template table.
function RomExtractorGen2:trainerCardGfx()
  local card = {}
  local chris = self:symbol("ChrisPicAndTrainerCardGFX")
  -- 41 tiles padded out to three 16-tile rows so the sheet is addressable as
  -- (id % 16, id / 16) like every other one here.
  local cardTiles = self.rom:bytes(chris.bank, chris.address, 41 * 16)
  while #cardTiles < 48 * 16 do cardTiles[#cardTiles + 1] = 0 end
  self:write2bpp(cardTiles, 128, 24, "trainer_card/card.png")
  card.card = "assets/generated/trainer_card/card.png"
  card.cardTilesWide = 16
  card.portraitTiles = 35
  card.portraitWide = 5
  card.frameFirstTile = 0x23

  local status = self:symbol("CardStatusGFX")
  self:write2bpp(self.rom:bytes(status.bank, status.address, 6 * 16),
    48, 8, "trainer_card/status.png")
  card.status = "assets/generated/trainer_card/status.png"
  card.statusWide = 6
  card.statusFirstTile = 0x29

  -- LeaderGFX is 86 tiles from $29: eight 10-tile gym-leader faces followed
  -- by the five "BADGES" caption tiles at $79.
  local leaders = self:symbol("LeaderGFX")
  local leaderTiles = self.rom:bytes(leaders.bank, leaders.address, 86 * 16)
  while #leaderTiles < 90 * 16 do leaderTiles[#leaderTiles + 1] = 0 end
  self:write2bpp(leaderTiles, 80, 72, "trainer_card/leaders.png")
  card.leaders = "assets/generated/trainer_card/leaders.png"
  card.leadersWide = 10
  card.leadersFirstTile = 0x29

  local badges = self:symbol("BadgeGFX")
  self:write2bpp(self.rom:bytes(badges.bank, badges.address, 44 * 16),
    16, 176, "trainer_card/badges.png", true)
  card.badges = "assets/generated/trainer_card/badges.png"
  card.badgesWide = 2

  -- TrainerCard_JohtoBadgesOAM: a wJohtoBadges pointer, then per badge
  -- `y, x, palette` and two 4-byte animation cycles.  y/x are OAM values, so
  -- screen space is (x - 8, y - 16).
  local oam = self:symbol("TrainerCard_JohtoBadgesOAM")
  card.badgeOam = {}
  for i = 0, 7 do
    local at = oam.address + 2 + i * 11
    local frames = {}
    for f = 0, 7 do
      frames[f + 1] = self.rom:byte(oam.bank, at + 3 + f)
    end
    card.badgeOam[i + 1] = {
      y = self.rom:byte(oam.bank, at) - 16,
      x = self.rom:byte(oam.bank, at + 1) - 8,
      palette = self.rom:byte(oam.bank, at + 2),
      frames = frames,
    }
  end
  -- _CGB_TrainerCard loads nine palettes into an eight-palette table: BG 0 is
  -- the player's own colours, BG 1-7 the first seven gym leaders', and the
  -- ninth (PREDEFPAL_CGB_BADGE) runs off the end into OBJ palette 0, which is
  -- exactly the palette every badge sprite names.  The whole attrmap is
  -- filled with palette 1 first, so the card frame -- and the eighth leader's
  -- face, which gets no zone of its own -- wears Falkner's colours.
  card.badgePalette = self:predefPal(PREDEFPAL_CGB_BADGE)
  card.leaderClasses = { "FALKNER", "BUGSY", "WHITNEY", "MORTY", "CHUCK",
    "JASMINE", "PRYCE" }
  -- The FillBoxCGB zones, as {x, y, width, height, palette}, 1-based so the
  -- palette indexes a Lua table directly.
  card.paletteZones = {
    { 14, 1, 5, 7, 1 },
    { 18, 1, 1, 1, 2 },
    { 2, 11, 4, 2, 2 }, { 6, 11, 4, 2, 3 },
    { 10, 11, 4, 2, 4 }, { 14, 11, 4, 2, 5 },
    { 2, 14, 4, 2, 6 }, { 6, 14, 4, 2, 7 },
    { 10, 14, 4, 2, 8 },
  }
  return card
end

--------------------------------------------------------------------------
-- Battle animations (data/moves/animations.asm, data/battle_anims/*)
--------------------------------------------------------------------------

-- macros/scripts/battle_anims.asm.  Anything under FIRST_BATTLE_ANIM_CMD
-- ($d0) is `anim_wait <n>` and carries no argument bytes; everything from
-- $d0 up is a command whose argument count is fixed.  anim_obj's macro has
-- two spellings (a four-argument one and a legacy tile+offset one) but both
-- emit the same four bytes.
local ANIM_CMDS = {
  [0xd0] = { "obj", 4 }, [0xd1] = { "1gfx", 1 }, [0xd2] = { "2gfx", 2 },
  [0xd3] = { "3gfx", 3 }, [0xd4] = { "4gfx", 4 }, [0xd5] = { "5gfx", 5 },
  [0xd6] = { "incobj", 1 }, [0xd7] = { "setobj", 2 },
  [0xd8] = { "incbgeffect", 1 },
  [0xd9] = { "battlergfx_2row", 0 }, [0xda] = { "battlergfx_1row", 0 },
  [0xdb] = { "checkpokeball", 0 }, [0xdc] = { "transform", 0 },
  [0xdd] = { "raisesub", 0 }, [0xde] = { "dropsub", 0 },
  [0xdf] = { "resetobp0", 0 },
  [0xe0] = { "sound", 2 }, [0xe1] = { "cry", 1 },
  [0xe2] = { "minimizeopp", 0 }, [0xe3] = { "oamon", 0 },
  [0xe4] = { "oamoff", 0 }, [0xe5] = { "clearobjs", 0 },
  [0xe6] = { "beatup", 0 }, [0xe7] = { "unknown_e7", 0 },
  [0xe8] = { "updateactorpic", 0 }, [0xe9] = { "minimize", 0 },
  [0xea] = { "unknown_ea", 0 }, [0xeb] = { "unknown_eb", 0 },
  [0xec] = { "unknown_ec", 0 }, [0xed] = { "unknown_ed", 0 },
  [0xee] = { "if_param_and", 3 }, [0xef] = { "jumpuntil", 2 },
  [0xf0] = { "bgeffect", 4 },
  [0xf1] = { "bgp", 1 }, [0xf2] = { "obp0", 1 }, [0xf3] = { "obp1", 1 },
  [0xf4] = { "keepsprites", 0 }, [0xf5] = { "unknown_f5", 0 },
  [0xf6] = { "unknown_f6", 0 }, [0xf7] = { "unknown_f7", 0 },
  [0xf8] = { "if_param_equal", 3 }, [0xf9] = { "setvar", 1 },
  [0xfa] = { "incvar", 0 }, [0xfb] = { "if_var_equal", 3 },
  [0xfc] = { "jump", 2 }, [0xfd] = { "loop", 3 },
  [0xfe] = { "call", 2 }, [0xff] = { "ret", 0 },
}
-- The commands whose LAST two argument bytes are an address in the same
-- bank, which is what the disassembler follows to find sub-scripts.
local ANIM_BRANCHES = {
  jumpuntil = 1, if_param_and = 2, if_param_equal = 2, if_var_equal = 2,
  jump = 1, loop = 2, call = 1,
}
local NUM_BATTLE_ANIMS = 278 -- data/moves/animations.asm's table_width 2 rows
-- constants/move_constants.asm: the animation ids past the moves.  The block
-- restarts at `const_next $ff`, so rows $fc-$fe of BattleAnimations are dead
-- padding and ANIM_SWEET_SCENT_2 is row $ff.  These are the animations the
-- engine plays by id rather than by move -- the ball throw, the send-out, the
-- status loops, and the six "after" animations wBattleAfterAnim indexes.
local BATTLE_ANIM_IDS = {
  [0xff] = "ANIM_SWEET_SCENT_2", [0x100] = "ANIM_THROW_POKE_BALL",
  [0x101] = "ANIM_SEND_OUT_MON", [0x102] = "ANIM_RETURN_MON",
  [0x103] = "ANIM_CONFUSED", [0x104] = "ANIM_SLP", [0x105] = "ANIM_BRN",
  [0x106] = "ANIM_PSN", [0x107] = "ANIM_SAP", [0x108] = "ANIM_FRZ",
  [0x109] = "ANIM_PAR", [0x10a] = "ANIM_IN_LOVE",
  [0x10b] = "ANIM_IN_SANDSTORM", [0x10c] = "ANIM_IN_NIGHTMARE",
  [0x10d] = "ANIM_IN_WHIRLPOOL", [0x10e] = "ANIM_MISS",
  [0x10f] = "ANIM_ENEMY_DAMAGE", [0x110] = "ANIM_ENEMY_STAT_DOWN",
  [0x111] = "ANIM_PLAYER_STAT_DOWN", [0x112] = "ANIM_PLAYER_DAMAGE",
  [0x113] = "ANIM_WOBBLE", [0x114] = "ANIM_SHAKE",
  [0x115] = "ANIM_HIT_CONFUSION",
}

-- Disassemble one animation script, following every branch target so a
-- sub-script that is only ever reached by anim_call ends up in the pool too.
-- Scripts are keyed by their ROM address because that is what a branch names;
-- the per-move table then points at one of those keys.
function RomExtractorGen2:readBattleAnimScript(bank, address, pool, order)
  local key = ("%04x"):format(address)
  if pool[key] then return key end
  local rows = {}
  pool[key] = rows -- claimed before the walk, so a self-jump terminates
  order[#order + 1] = key
  local at = address
  local pending = {}
  for _ = 1, 4096 do
    local byte = self.rom:byte(bank, at)
    at = at + 1
    local spec = ANIM_CMDS[byte]
    if not spec then
      -- Under $d0 the byte IS the wait length.
      rows[#rows + 1] = { "wait", byte }
    else
      local row = { spec[1] }
      for i = 1, spec[2] do
        row[i + 1] = self.rom:byte(bank, at)
        at = at + 1
      end
      local branch = ANIM_BRANCHES[spec[1]]
      if branch then
        -- The address is the last two bytes, little-endian.
        local low, high = row[branch + 1], row[branch + 2]
        local target = low + high * 256
        row[branch + 1] = ("%04x"):format(target)
        row[branch + 2] = nil
        pending[#pending + 1] = target
      end
      rows[#rows + 1] = row
      if spec[1] == "ret" then break end
      -- An unconditional jump ends this run; its target is walked below.
      if spec[1] == "jump" then break end
    end
  end
  for _, target in ipairs(pending) do
    self:readBattleAnimScript(bank, target, pool, order)
  end
  return key
end

-- BattleAnimObjects: seven bytes an entry (battleanimobj), naming the
-- frameset it plays, the per-frame function that moves it, its palette and
-- which GFX sheet its tiles come from.
function RomExtractorGen2:readBattleAnimObjects()
  local consts = self.manifest.constants or {}
  local names = consts.battleAnimObjectOrder or {}
  local framesets = consts.battleAnimFramesetOrder or {}
  local funcs = consts.battleAnimFuncOrder or {}
  -- An animation object is an OBJ, so its palette byte names an OBJ palette:
  -- PAL_BATTLE_OB_*, which is its own const block starting at zero, not the
  -- BG one beside it in the same file.
  local pals = consts.battleAnimObPaletteOrder or {}
  local gfx = consts.battleAnimGfxOrder or {}
  local symbol = self:symbol("BattleAnimObjects")
  local out = {}
  for index, name in ipairs(names) do
    -- BATTLEANIMOBJ_LENGTH is `_RS - 1` -- the struct's INDEX byte is runtime
    -- state and is NOT in the table -- so a row is SIX bytes, not seven.
    local row = self.rom:bytes(symbol.bank, symbol.address + (index - 1) * 6, 6)
    out[name] = {
      -- bit 0 is "fix the enemy's coordinates"; bits 5-7 are flip/priority.
      flags = row[1],
      fixY = row[2],
      frameset = framesets[row[3] + 1] or row[3],
      func = funcs[row[4] + 1] or row[4],
      palette = pals[row[5] + 1] or row[5],
      -- battleAnimGfxOrder carries a placeholder for AnimObjGFX's empty row 0
      -- (the const block itself starts at 1), so value + 1 indexes it like
      -- every other list here.
      gfx = gfx[row[6] + 1] or row[6],
      tileOffset = row[7],
    }
  end
  return out
end

-- BattleAnimFrameData: a pointer table of oamframe lists, in the SAME format
-- the overworld sprite anims use -- which is the point.  src/ui/gen2/
-- SpriteAnims.lua already runs these, so the runtime is shared rather than
-- written twice.
function RomExtractorGen2:readBattleAnimFramesets()
  local names = (self.manifest.constants or {}).battleAnimFramesetOrder or {}
  local oamsets = (self.manifest.constants or {}).battleAnimOamsetOrder or {}
  local symbol = self:symbol("BattleAnimFrameData")
  local out = {}
  for index, name in ipairs(names) do
    local low = self.rom:byte(symbol.bank, symbol.address + (index - 1) * 2)
    local high = self.rom:byte(symbol.bank, symbol.address + (index - 1) * 2 + 1)
    local at = low + high * 256
    local frames = {}
    -- macros/scripts/oam_anims.asm counts DOWN from $ff: oamend $ff,
    -- oamrestart $fe, oamwait $fd, oamdelete $fc.  Everything below is an OAM
    -- set id, and with 216 of them there is no collision.
    for _ = 1, 64 do
      local byte = self.rom:byte(symbol.bank, at)
      at = at + 1
      if byte == 0xff then
        frames[#frames + 1] = { "end" }
        break
      elseif byte == 0xfe then
        frames[#frames + 1] = { "restart" }
        break
      elseif byte == 0xfd then
        frames[#frames + 1] = { "wait", self.rom:byte(symbol.bank, at) }
        at = at + 1
      elseif byte == 0xfc then
        frames[#frames + 1] = { "delete" }
        break
      else
        -- oamframe's OWN comment calls its first byte the duration and is
        -- wrong: `oamframe BATTLE_ANIM_OAMSET_00, 6` passes the OAM SET as
        -- \1, so the set comes first and the duration second.  The duration's
        -- top two bits are the flip arguments, one bit above the OAM flags
        -- they become -- GetSpriteAnimFrame shifts them back down.
        local duration = self.rom:byte(symbol.bank, at)
        at = at + 1
        frames[#frames + 1] = {
          "frame", oamsets[byte + 1] or byte,
          bit.band(duration, 0x3f),
          bit.rshift(bit.band(duration, 0xc0), 1),
        }
      end
    end
    out[name] = frames
  end
  return out
end

-- BattleAnimOAMData: `battleanimoam <vtile offset>, <length>, <data>` and
-- then a run of dbsprite rows.
function RomExtractorGen2:readBattleAnimOamsets()
  local names = (self.manifest.constants or {}).battleAnimOamsetOrder or {}
  local symbol = self:symbol("BattleAnimOAMData")
  local out = {}
  for index, name in ipairs(names) do
    local row = self.rom:bytes(symbol.bank, symbol.address + (index - 1) * 4, 4)
    local at = row[3] + row[4] * 256
    local sprites = {}
    for i = 1, row[2] do
      -- dbsprite is four bytes: y, x, vtile offset, attributes -- and the y
      -- byte comes FIRST even though the macro's arguments read x first.
      local entry = self.rom:bytes(symbol.bank, at + (i - 1) * 4, 4)
      sprites[i] = {
        y = entry[1], x = entry[2], tile = entry[3], attr = entry[4],
      }
    end
    out[name] = { vtile = row[1], sprites = sprites }
  end
  return out
end

-- AnimObjGFX: `anim_obj_gfx <tiles>, <label>` -- a count and a three-byte
-- far pointer at a compressed sheet.
function RomExtractorGen2:readBattleAnimGfx()
  local names = (self.manifest.constants or {}).battleAnimGfxOrder or {}
  local symbol = self:symbol("AnimObjGFX")
  local out = {}
  for index, name in ipairs(names) do
    local row = self.rom:bytes(symbol.bank, symbol.address + (index - 1) * 4, 4)
    local tiles = row[1]
    if tiles > 0 then
      local bank, address = row[2], row[3] + row[4] * 256
      local ok, pixels = pcall(function()
        local compressed = self.rom:bytes(bank, address, 0x8000 - address)
        return Rom.decompressLz3(compressed)
      end)
      if ok and pixels then
        local wide = math.min(tiles, 8)
        local high = math.ceil(tiles / wide)
        local need = wide * high * 16
        while #pixels < need do pixels[#pixels + 1] = 0 end
        while #pixels > need do table.remove(pixels) end
        local rel = ("battle_anims/%s.png"):format(name:lower())
        self:write2bpp(pixels, wide * 8, high * 8, rel, true)
        out[name] = {
          tiles = tiles, wide = wide,
          image = "assets/generated/" .. rel,
        }
      end
    end
  end
  return out
end

function RomExtractorGen2:extractBattleAnims()
  self:beginStage("Battle animations")
  local moveOrder = (self.manifest.constants or {}).moveOrder or {}
  local table_ = self:symbol("BattleAnimations")
  local pool, order = {}, {}
  local byMove, byId = {}, {}
  for index = 1, NUM_BATTLE_ANIMS do
    local base = table_.address + (index - 1) * 2
    local low = self.rom:byte(table_.bank, base)
    local high = self.rom:byte(table_.bank, base + 1)
    local address = low + high * 256
    -- Row 0 is BattleAnim_Dummy; rows 1..NUM_MOVES are the moves in order,
    -- and the rows past them are the shared non-move animations (status,
    -- stat changes, the ball throw) the engine plays by id.
    local key = self:readBattleAnimScript(table_.bank, address, pool, order)
    local name = (index > 1) and moveOrder[index - 1] or nil
    if name then byMove[name] = key end
    local idName = BATTLE_ANIM_IDS[index - 1]
    if idName then byId[idName] = key end
    if index % 40 == 0 then
      self:tick("Battle animations", index, NUM_BATTLE_ANIMS)
    end
  end
  local scripts = {}
  for _, key in ipairs(order) do scripts[key] = pool[key] end
  local data = {
    generation = 2,
    source = "ROM:BattleAnimations + data/battle_anims/*",
    bank = table_.bank,
    -- Every script in one pool keyed by its ROM address; `moves` and `ids`
    -- point into it.  A sub-script reached only by anim_call has no name of
    -- its own, which is why the pool is addressed rather than named.
    scripts = scripts,
    scriptOrder = order,
    moves = byMove,
    -- The animations the engine plays by id: the ball throw, the send-out
    -- slide, the status loops and the six wBattleAfterAnim entries.
    ids = byId,
    objects = self:readBattleAnimObjects(),
    framesets = self:readBattleAnimFramesets(),
    oamsets = self:readBattleAnimOamsets(),
    gfx = self:readBattleAnimGfx(),
  }
  self:write("battle_anims", data)
  self:tick("Battle animations", NUM_BATTLE_ANIMS, NUM_BATTLE_ANIMS)
  return data
end

-- The Magnet Train's two tilemaps (engine/events/magnet_train.asm).
--
-- MagnetTrainBGTiles is a 2x18 strip: two tile ids per screen row, which
-- DrawMagnetTrain's .FillAlt repeats across all TILEMAP_WIDTH / 2 column pairs
-- to build the scrolling scenery.  MagnetTrainTilemap is the 20x4 train itself,
-- laid over BG rows 6-9 on top of it.
--
-- Neither is compressed and neither is pointed at by anything the script
-- walker follows, so both are read straight off their labels.  No tile GRAPHICS
-- come with them: MagnetTrain_LoadGFX_PlayMusic loads none, and every id above
-- indexes whatever the station's own tileset (TILESET_TRAIN_STATION) already
-- had in VRAM.
local MAGNET_TRAIN_BG_ROWS = 18   -- SCREEN_HEIGHT
local MAGNET_TRAIN_FG_WIDTH = 20  -- SCREEN_WIDTH
local MAGNET_TRAIN_FG_ROWS = 4

function RomExtractorGen2:readMagnetTrain()
  -- A manifest generated before these two labels were required carries neither,
  -- and an import that hard-errored on that would take the whole cache build
  -- down over a cutscene; the ride runs without the art.
  if not (self.symbols["MagnetTrainBGTiles"]
      and self.symbols["MagnetTrainTilemap"]) then
    return nil
  end
  local bgSymbol = self:symbol("MagnetTrainBGTiles")
  local bgTiles = {}
  for index = 0, MAGNET_TRAIN_BG_ROWS * 2 - 1 do
    bgTiles[index + 1] = self.rom:byte(bgSymbol.bank, bgSymbol.address + index)
  end
  local fgSymbol = self:symbol("MagnetTrainTilemap")
  local tilemap = {}
  for index = 0, MAGNET_TRAIN_FG_WIDTH * MAGNET_TRAIN_FG_ROWS - 1 do
    tilemap[index + 1] = self.rom:byte(fgSymbol.bank, fgSymbol.address + index)
  end
  return {
    source = "ROM:MagnetTrainBGTiles + MagnetTrainTilemap",
    bgTiles = bgTiles,
    tilemap = tilemap,
    width = MAGNET_TRAIN_FG_WIDTH,
    rows = MAGNET_TRAIN_FG_ROWS,
  }
end

-- The field table is mostly still a stub; `extras` is what a table has already
-- grown real contents in, merged over the stub note so the rest of it stays
-- honestly marked as unextracted.
function RomExtractorGen2:extractStubs()
  self:beginStage("Remaining data (stubs)")
  local names = {
    "field",
  }
  local extras = {
    field = { magnetTrain = self:readMagnetTrain() },
  }
  for index, name in ipairs(names) do
    local data = {
      generation = 2,
      source = "Gold Phase 2 stub -- not yet extracted, see docs/gold-phase1.md",
    }
    for key, value in pairs(extras[name] or {}) do data[key] = value end
    self:write(name, data)
    self:tick("Remaining data (stubs)", index, #names)
  end
  return true
end

function RomExtractorGen2:run()
  local results = {}
  results.constants = self:extractConstants()
  results.font = self:extractFont()
  results.palettes = self:extractPalettes()
  results.tilesets = self:extractTilesets()
  results.maps = self:extractMaps()
  results.sprites = self:extractSprites()
  results.stdScripts = self:extractStdScripts()
  results.scripts = self:extractScriptsAndText(results.maps, results.stdScripts)
  results.pokemon = self:extractPokemon()
  results.moves = self:extractMoves()
  results.items = self:extractItems()
  results.marts = self:extractMarts()
  results.encounters = self:extractEncounters()
  results.trainers = self:extractTrainers()
  results.pokedex = self:extractPokedex()
  results.landmarks = self:extractLandmarks()
  results.icons = self:extractIcons()
  results.intro = self:extractIntro()
  results.menuGfx = self:extractMenuGfx()
  results.oakSpeech = self:extractOakSpeech(results.pokemon)
  results.title = self:extractTitle()
  results.credits = self:extractCredits()
  results.diploma = self:extractDiploma()
  results.trade = self:extractTrade()
  results.audio = self:extractAudio(results.maps)
  results.battleAnims = self:extractBattleAnims()
  results.stubs = self:extractStubs()
  if self.progress then
    self.progress(STAGE_COUNT, STAGE_COUNT, "Ready", 1, 1)
  end
  return results
end

return RomExtractorGen2
