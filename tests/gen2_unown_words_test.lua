-- The Ruins of Alph wall words: engine/events/unown_walls.asm:102
-- DisplayUnownWords and data/events/unown_walls.asm:7 UnownWalls.
--   CRYSTAL_CACHE="..." luajit tests/gen2_unown_words_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 unown words")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Json = require("src.link.Json")
local UnownWords = require("src.world.gen2.UnownWords")

local function readFile(path, mode)
  local f = io.open(path, mode or "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local function pngSize(body)
  local function be32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return be32(body, 17), be32(body, 21)
end

local function loadTable(path)
  local chunk = loadfile(path)
  return chunk and chunk() or nil
end

-- engine/events/unown_walls.asm:201 .ConvertChar
do
  local tl, tr, bl, br = UnownWords.square(0x00) -- 'A'
  eq(tl, 0x80, "A's top-left is bank 1 tile $00")
  eq(tr, 0x81, "top-right is the next tile")
  eq(bl, 0x90, "bottom-left is a 16-tile row down")
  eq(br, 0x91, "and bottom-right beside it")
  eq((UnownWords.square(0x0e)), 0x8e, "H is bank 1 tile $0e")
  eq((UnownWords.square(0x20)), 0xa0, "I steps a whole row: bank 1 tile $20")
  eq((UnownWords.square(0x4e)), 0xce, "X is the last computed letter")
  local y1, y2, y3, y4 = UnownWords.square(0x60)
  eq(y1 * 0x1000000 + y2 * 0x10000 + y3 * 0x100 + y4,
    0x5b5c4d5d, "Y is .YChar's four bank 0 tiles")
  local z1, z2, z3, z4 = UnownWords.square(0x62)
  eq(z1 * 0x1000000 + z2 * 0x10000 + z3 * 0x100 + z4,
    0x4e4f5e5f, "Z is .ZChar's")
  local d1, d2, d3, d4 = UnownWords.square(0x64)
  eq(d1 * 0x1000000 + d2 * 0x10000 + d3 * 0x100 + d4,
    0x02030302, "and the dash is .DashChar's")
end

-- data/events/unown_walls.asm:15 MenuHeaders_UnownWalls, the n = 6 row.
do
  local escape = { x1 = 3, y1 = 4, x2 = 16, y2 = 9,
                   chars = { 0x08, 0x44, 0x04, 0x00, 0x2e, 0x08 } }
  local bx, by, bw, bh = UnownWords.boxRect(escape)
  eq(bx, 3, "the box starts at column 3")
  eq(by, 4, "row 4")
  eq(bw, 14, "and spans the coordinate pair inclusive: 14 columns")
  eq(bh, 6, "by 6 rows")
  local ox, oy = UnownWords.origin(escape)
  eq(ox, 4, "the first square is one column inside the frame")
  eq(oy, 6, "and two rows down")
  local squares = UnownWords.layout(escape)
  eq(#squares, 6, "ESCAPE is six squares")
  eq(squares[1].tx, 4, "the E starts at column 4")
  eq(squares[2].tx, 6, "and every letter is two tiles wide")
  eq(squares[6].tx, 14, "so the last one ends on the frame's inner edge")
  eq(squares[1].ty, 6, "all of them on the same row")
  eq(squares[4].tl, 0x80, "the A in ESCAPE is bank 1 tile $00")
end

-- constants/charmap.asm:424 the `unown` charmap.
do
  local body = readFile("tools/rom_manifest_crystal.json", "r")
  if not body then
    check(true, "no tools/rom_manifest_crystal.json (SKIP)")
  else
    local manifest = Json.decode(body)
    local map = manifest.unownCharmap
    if not map then
      check(false, "the Crystal manifest carries unownCharmap")
    else
      eq(map["0"], "A", "$00 is A")
      eq(map["2"], "B", "$02 is B, two tiles along")
      eq(map["14"], "H", "$0e is H, the last of the first row")
      eq(map["32"], "I", "$20 is I: the row step is $10 every eight letters")
      eq(map["78"], "X", "$4e is X")
      eq(map["96"], "Y", "$60 is Y")
      eq(map["98"], "Z", "$62 is Z")
      eq(map["100"], "-", "$64 is the dash")
      eq(map["255"], "@", "and $ff terminates a word")
      local count = 0
      for _ in pairs(map) do count = count + 1 end
      eq(count, 28, "27 printable characters plus the terminator")
    end
    -- constants/charmap.asm:5 -- $00 is <NULL> in the main charmap.
    local main = manifest.charmap or {}
    check(main["0"] ~= "A", "the main charmap did not absorb the Unown rows")
    eq(manifest.symbols.UnownWalls[1], 0x22,
      "UnownWalls is in the bank pokecrystal.sym says")
    eq(manifest.symbols.UnownWalls[2], 0x6ebc, "and at its address")
    eq(manifest.symbols.MenuHeaders_UnownWalls[2], 0x6ed5,
      "with the menu headers immediately after it")
  end
end

do
  for _, edition in ipairs({ "gold", "silver" }) do
    local body = readFile("tools/rom_manifest_" .. edition .. ".json", "r")
    if not body then
      check(true, "no " .. edition .. " manifest (SKIP)")
    else
      local manifest = Json.decode(body)
      check(manifest.unownCharmap == nil,
        edition .. " has no Unown charmap: the block is Crystal only")
      check(manifest.symbols.UnownWalls == nil,
        edition .. " has no UnownWalls either")
    end
  end
end

-- constants/charmap.asm:423,433 the two `pushc` blocks the main parser skips.
do
  local source = readFile("tools/make_gold_manifest.py", "r")
  if not source then
    check(true, "no tools/make_gold_manifest.py (SKIP)")
  else
    check(source:find('if re.match(r"(pushc|newcharmap)\\b", stripped):',
      1, true) ~= nil, "the main charmap parser still stops at newcharmap")
  end
  local crystal = readFile("tools/make_crystal_manifest.py", "r")
  if not crystal then
    check(true, "no tools/make_crystal_manifest.py (SKIP)")
  else
    check(crystal:find('data["unownCharmap"] = unown_charmap(', 1, true) ~= nil,
      "and the Unown one is generated beside it, under its own key")
    check(crystal:find("PRINTABLE_UNOWN", 1, true) == nil,
      "with the letter set read out of charmap.asm, not copied here")
  end
end

-- home/map.asm:1357-1370 LoadTilesetGFX's two CopyBytes.
do
  local source = assert(readFile("src/import/RomExtractorGen2.lua", "r"))
  check(source:find("local function crystalTilesetSheet(pixels)", 1, true)
    ~= nil, "the Crystal sheet lays both VRAM banks out at their tile ids")
  check(source:find("if twoBank then pixels = crystalTilesetSheet(pixels) end",
    1, true) ~= nil, "and extractTilesets uses it")
  check(source:find("local CRYSTAL_PAL_MAP_BYTES = 112", 1, true) ~= nil,
    "the PalMap read covers the bank 1 rows too")
  check(source:find("out.unownWalls = walls", 1, true) ~= nil,
    "and readEventTables emits the wall words")
end

-- gfx/tilesets/ruins_of_alph.png, whose bottom half is the Unown alphabet.
do
  local png = readFile(
    "../pokecrystal/gfx/tilesets/ruins_of_alph.png")
  if not png then
    check(true, "no ../pokecrystal: the tileset's shape is not pinned (SKIP)")
  else
    local w, h = pngSize(png)
    eq(w, 128, "pret's ruins_of_alph.png is 16 tiles across")
    eq(h, 96, "and 12 down: $60 tiles per VRAM bank, two banks")
  end
end

local cache = os.getenv("CRYSTAL_CACHE")
if not cache then
  cache = (os.getenv("HOME") or "")
    .. "/Library/Application Support/LOVE/crystal-dev/crystal"
end

local events = loadTable(cache .. "/data/generated/events.lua")
local tilesets = loadTable(cache .. "/data/generated/tilesets.lua")

-- data/events/unown_walls.asm:2-5
local EXPECTED = {
  { word = "ESCAPE", x1 = 3, y1 = 4, x2 = 16, y2 = 9 },
  { word = "LIGHT", x1 = 4, y1 = 4, x2 = 15, y2 = 9 },
  { word = "WATER", x1 = 4, y1 = 4, x2 = 15, y2 = 9 },
  { word = "HO-OH", x1 = 4, y1 = 4, x2 = 15, y2 = 9 },
}

if not events then
  check(true, "no Crystal cache: the wall words are not read (SKIP)")
elseif not events.unownWalls then
  check(true, "cache predates the wall words: re-import Crystal (SKIP)")
else
  local walls = events.unownWalls
  eq(#walls, 4, "NUM_UNOWN_WALLS rows came out")
  for index, want in ipairs(EXPECTED) do
    local got = walls[index] or {}
    eq(got.word, want.word, want.word .. " decoded through the Unown charmap")
    eq(got.id, index - 1, "at the UNOWNWORDS_* value the setval uses")
    eq(#(got.chars or {}), #want.word, "with one character byte per letter")
    eq(got.x1, want.x1, want.word .. "'s box left edge")
    eq(got.y1, want.y1, "top edge")
    eq(got.x2, want.x2, "right edge")
    eq(got.y2, want.y2, "bottom edge")
    -- data/events/unown_walls.asm:20 MENU_BACKUP_TILES
    eq(got.flags, 0x40, "and MENU_BACKUP_TILES set")
    -- data/events/unown_walls.asm:21 `menu_coords 9 - n, 4, 10 + n, 9`
    local _, _, bw = UnownWords.boxRect(got)
    eq(bw - 2, #want.word * 2, "the frame is 2 columns per letter wide")
  end
  -- engine/events/unown_walls.asm:249 .DashChar
  local dash = UnownWords.layout(walls[4])[3]
  eq(dash.tl, 0x02, "HO-OH's dash comes out of .DashChar, not the alphabet")
end

if not tilesets then
  check(true, "no Crystal cache: the tileset sheet is not read (SKIP)")
else
  local roa = tilesets.TILESET_RUINS_OF_ALPH
  if not roa then
    check(false, "the Ruins of Alph tileset is in the cache")
  elseif roa.imageHeight ~= 128 then
    check(true, "cache predates the two-bank sheet: re-import Crystal (SKIP)")
  else
    eq(roa.imageWidth, 128, "the sheet is 16 tiles across")
    eq(roa.imageHeight, 128, "and 16 down: 256 tile ids, both VRAM banks")
    eq(roa.tilesPerRow, 16, "so a tile id indexes it directly")
    eq(#roa.tilePalettes, 224, "the PalMap covers every id the blocks use")
    local png = readFile(cache .. "/assets/generated/tilesets/ruins_of_alph.png")
    if not png then
      check(false, "the sheet PNG is actually in the cache")
    else
      local w, h = pngSize(png)
      eq(w, 128, "the written PNG is 128 wide")
      eq(h, 128, "and 128 tall")
    end
    -- constants/tileset_constants.asm:34-38, the five Crystal-only tilesets.
    for _, name in ipairs({ "TILESET_KABUTO_WORD_ROOM",
        "TILESET_OMANYTE_WORD_ROOM", "TILESET_AERODACTYL_WORD_ROOM",
        "TILESET_HO_OH_WORD_ROOM", "TILESET_BETA_WORD_ROOM" }) do
      local set = tilesets[name]
      if not set then
        check(false, name .. " extracted")
      else
        eq(set.imageHeight, 128, name .. " is a two-bank sheet")
        -- engine/tilesets/map_palettes.asm:40 -- bit 7 is the VRAM bank.
        local high = 0
        for _, block in ipairs(set.blocks) do
          for _, tile in ipairs(block) do
            if tile >= 0x80 and tile < 0xe0 then high = high + 1 end
          end
        end
        check(high > 0, name .. " really does draw out of bank 1")
      end
    end
  end
end

-- data/events/special_pointers.asm:151 add_special DisplayUnownWords
do
  local Specials = require("src.script.gen2.Specials")
  check(type(Specials.ALL.DisplayUnownWords) == "function",
    "DisplayUnownWords is a handler and not a stub")
  eq(Specials.HANDLER_SOURCE.DisplayUnownWords,
    "specials/unown_words.lua", "owned by this unit's module")
end

do
  local maps = loadTable(cache .. "/data/generated/maps.lua")
  local scripts = loadTable(cache .. "/data/generated/scripts.lua")
  local consts = loadTable(cache .. "/data/generated/constants.lua")
  if not (maps and scripts and consts and events and events.unownWalls) then
    check(true, "no Crystal cache: the chambers are not walked (SKIP)")
  else
    local index
    for id, name in pairs(consts.specialOrder or {}) do
      if name == "DisplayUnownWords" then index = id - 1 end
    end
    check(index ~= nil, "the cache's specialOrder names DisplayUnownWords")
    local chambers = {
      RUINS_OF_ALPH_KABUTO_CHAMBER = 0,
      RUINS_OF_ALPH_AERODACTYL_CHAMBER = 1,
      RUINS_OF_ALPH_OMANYTE_CHAMBER = 2,
      RUINS_OF_ALPH_HO_OH_CHAMBER = 3,
    }
    for mapId, want in pairs(chambers) do
      local def = maps[mapId]
      local walls = 0
      for _, bg in ipairs((def or {}).bgEvents or {}) do
        local rows = bg.scriptKey and scripts[bg.scriptKey]
        local pending
        for _, row in ipairs(rows or {}) do
          if row.op == "setval" then
            pending = row.value or (row.args and row.args[1])
          elseif row.op == "special" and row.id == index then
            walls = walls + 1
            eq(pending, want, mapId .. " asks for its own word")
            check(UnownWords.wallFor(
              { gen2EventTables = events }, pending) ~= nil,
              "and that value indexes a real wall row")
          end
        end
      end
      eq(walls, 2, mapId .. " has both of its wall patterns")
    end
  end
end

S.finish()
