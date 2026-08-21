-- The #DEX diploma page (engine/events/diploma.asm PlaceDiplomaOnScreen).
--   GOLD_CACHE="..." luajit tests/gen2_diploma_test.lua
--
-- The certificate is a tilemap, not a text box: DiplomaGFX decompresses into
-- vTiles2 and DiplomaPage1Tilemap is copied over the whole background before
-- any string is placed.  So there are three things worth pinning here -- that
-- the extractor stage exists AND is called from run(), that what it wrote
-- matches ../pokegold/gfx/diploma/ byte for byte, and that the screen draws
-- that tilemap rather than laying the page out by eye.
--
-- ROM-free.  The decomp section SKIPs with no ../pokegold beside the repo and
-- the cache section SKIPs (or asks for a re-import) with no Gold cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 diploma")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Chrome = require("src.ui.gen2.Chrome")
local Diploma = require("src.ui.gen2.Diploma")
local Screens = require("src.ui.Screens")

-- gfx/diploma/diploma.png is 16x7 tiles and page1.tilemap is one SCREEN_AREA.
local DIPLOMA_TILES = 112
local DIPLOMA_SHEET_TILES = 16
local SCREEN_W, SCREEN_H = 20, 18
local SCREEN_AREA = SCREEN_W * SCREEN_H

-- ---- the extractor stage --------------------------------------------------
-- A stage nothing calls writes nothing, and the cache checks below would then
-- SKIP forever without anyone noticing, so the call site is read out of the
-- source rather than assumed.
local extractorSource
do
  local f = assert(io.open("src/import/RomExtractorGen2.lua", "r"))
  extractorSource = f:read("*a")
  f:close()
end
local RomExtractorGen2 = require("src.import.RomExtractorGen2")
check(type(RomExtractorGen2.extractDiploma) == "function",
  "RomExtractorGen2:extractDiploma exists")
check(extractorSource:find("results.diploma = self:extractDiploma()", 1, true)
  ~= nil, "and RomExtractorGen2:run calls it")
check(extractorSource:find("local STAGE_COUNT = 26", 1, true) ~= nil,
  "STAGE_COUNT counts the new stage, so the progress bar still ends at 1")

-- The three symbols the stage reads have to be in the curated manifest set or
-- self.symbols[label] is nil and the stage silently writes nothing.
do
  local f = assert(io.open("tools/make_gold_manifest.py", "r"))
  local manifestSource = f:read("*a")
  f:close()
  for _, label in ipairs({ "DiplomaGFX", "DiplomaPage1Tilemap",
                           "DiplomaPalettes" }) do
    check(manifestSource:find('"' .. label .. '"', 1, true) ~= nil,
      label .. " is in make_gold_manifest.py's REQUIRED_SYMBOLS")
  end
end

local Json = require("src.link.Json")
do
  local f = io.open("tools/rom_manifest_gold.json", "r")
  if not f then
    check(true, "no tools/rom_manifest_gold.json (SKIP)")
  else
    local manifest = Json.decode(f:read("*a"))
    f:close()
    local symbols = manifest.symbols or {}
    -- pokegold.sym: 38:4105 DiplomaGFX, 38:454b DiplomaPage1Tilemap,
    -- 02:7a86 DiplomaPalettes.
    local want = {
      DiplomaGFX = { 0x38, 0x4105 },
      DiplomaPage1Tilemap = { 0x38, 0x454b },
      DiplomaPalettes = { 0x02, 0x7a86 },
    }
    for label, location in pairs(want) do
      local got = symbols[label]
      if not got then
        check(false, "the generated manifest carries " .. label)
      else
        eq(got[1], location[1], label .. " is in the bank pokegold.sym says")
        eq(got[2], location[2], label .. " is at the address pokegold.sym says")
      end
    end
  end
end

-- ---- the decomp -----------------------------------------------------------
local pokegold = os.getenv("POKEGOLD") or "../pokegold"
local function readFile(path, mode)
  local f = io.open(path, mode or "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local decompTilemap = readFile(pokegold .. "/gfx/diploma/page1.tilemap")
if not decompTilemap then
  check(true, "no ../pokegold: page1.tilemap is not pinned (SKIP)")
else
  eq(#decompTilemap, SCREEN_AREA,
    "gfx/diploma/page1.tilemap is exactly SCREEN_AREA bytes")
  local highest = 0
  for i = 1, #decompTilemap do
    local id = decompTilemap:byte(i)
    if id > highest then highest = id end
  end
  check(highest < DIPLOMA_TILES,
    "every id in it indexes DiplomaGFX's own 112 tiles, nothing past them")
end

-- gfx/diploma/diploma.pal, colour by colour, so the extracted palette can be
-- checked against the source rather than against itself.  DiplomaPalettes is
-- eight sets; only set 0 is reachable because _CGB_Diploma calls WipeAttrmap.
local DECOMP_PAL_SET0 = { { 27, 31, 27 }, { 21, 21, 21 }, { 13, 13, 13 },
                          { 0, 0, 0 } }
local function scale5(value) return math.floor(value * 255 / 31 + 0.5) end

-- ---- the cache ------------------------------------------------------------
-- Same default every other gen2 suite uses, so a run with no GOLD_CACHE set
-- still reads the cache instead of skipping silently.
local cache = os.getenv("GOLD_CACHE")
  or ((os.getenv("HOME") or "") .. "/Library/Application Support/LOVE/gold-dev/gold")
local function loadCache(name)
  local chunk = loadfile(cache .. "/data/generated/" .. name .. ".lua")
  return chunk and chunk() or nil
end

local diploma = loadCache("diploma")
if not diploma then
  check(true,
    "cache predates the Diploma stage : re-import for gfx/diploma (SKIP)")
else
  eq(diploma.generation, 2, "diploma.lua is a Gen 2 table")
  eq(diploma.tiles, DIPLOMA_TILES, "DiplomaGFX decompressed to 112 tiles")
  eq(diploma.sheetTiles, DIPLOMA_SHEET_TILES,
    "written as the 16-tile-wide sheet pret builds, so a tile id maps by /16")
  eq(diploma.width, SCREEN_W, "the tilemap is SCREEN_WIDTH across")
  eq(diploma.height, SCREEN_H, "and SCREEN_HEIGHT down")
  eq(diploma.image, "assets/generated/diploma/diploma.png",
    "the sheet went where the screen looks for it")

  local png = readFile(cache .. "/assets/generated/diploma/diploma.png")
  if not png then
    check(false, "the sheet PNG is actually in the cache")
  else
    -- PNG IHDR: width and height are big-endian at bytes 17 and 21.
    local function be32(s, i)
      local a, b, c, d = s:byte(i, i + 3)
      return ((a * 256 + b) * 256 + c) * 256 + d
    end
    eq(be32(png, 17), DIPLOMA_SHEET_TILES * 8, "the sheet is 128px wide")
    eq(be32(png, 21), DIPLOMA_TILES / DIPLOMA_SHEET_TILES * 8,
      "and 56px tall, which is the pret PNG's own shape")
  end

  local page1 = diploma.page1
  if type(page1) ~= "table" then
    check(false, "diploma.lua carries the page 1 tilemap")
  else
    eq(#page1, SCREEN_AREA, "the tilemap is one whole SCREEN_AREA")
    if decompTilemap then
      local mismatch
      for i = 1, SCREEN_AREA do
        if page1[i] ~= decompTilemap:byte(i) then mismatch = i break end
      end
      check(mismatch == nil, mismatch
        and ("the extracted tilemap differs from the decomp at byte "
          .. mismatch)
        or "the extracted tilemap is ../pokegold/gfx/diploma/page1.tilemap"
          .. " byte for byte")
    else
      check(true, "no ../pokegold: the tilemap is not diffed (SKIP)")
    end
  end

  local palettes = diploma.palettes
  if type(palettes) ~= "table" then
    check(false, "diploma.lua carries DiplomaPalettes")
  else
    eq(#palettes, 8, "all eight sets, because the block is one table")
    local set0 = palettes[1]
    for index, rgb in ipairs(DECOMP_PAL_SET0) do
      local got = set0 and set0[index] or {}
      eq(got[1], scale5(rgb[1]),
        ("set 0 colour %d red matches gfx/diploma/diploma.pal"):format(index - 1))
      eq(got[2], scale5(rgb[2]),
        ("set 0 colour %d green matches gfx/diploma/diploma.pal"):format(index - 1))
      eq(got[3], scale5(rgb[3]),
        ("set 0 colour %d blue matches gfx/diploma/diploma.pal"):format(index - 1))
    end
  end
end

-- ---- the screen -----------------------------------------------------------
local hasId = false
for _, id in ipairs(Screens.GEN2_IDS) do
  if id == "Gen2Diploma" then hasId = true end
end
check(hasId, "the diploma is pushed through the Gen2Diploma Screens id")

-- A tilemap standing in for page1: every cell holds its own index modulo the
-- sheet, which makes each quad's expected position arithmetic rather than a
-- lookup.
local fakePage1 = {}
for index = 0, SCREEN_AREA - 1 do
  fakePage1[index + 1] = index % DIPLOMA_TILES
end
local fakeGfx = {
  image = "assets/generated/diploma/diploma.png",
  tiles = DIPLOMA_TILES,
  sheetTiles = DIPLOMA_SHEET_TILES,
  width = SCREEN_W,
  height = SCREEN_H,
  page1 = fakePage1,
  palettes = { { { 222, 255, 222 }, { 173, 173, 173 }, { 107, 107, 107 },
                 { 0, 0, 0 } } },
}

local screen = Diploma.new(nil, { playerName = "GOLD", gfx = fakeGfx })
eq(screen.playerName, "GOLD", "the screen takes the player's name")
local palette = screen:palette()
check(palette ~= nil and palette[1][2] == 255,
  "and draws through DiplomaPalettes set 0, the one WipeAttrmap leaves it on")

local batch = screen:batch()
if not batch then
  check(false, "the screen builds a sprite batch from the tilemap")
else
  eq(#batch.sprites, SCREEN_AREA,
    "one 8x8 sprite per cell, the whole background CopyBytes writes")
  eq(screen:batch(), batch, "built once, not per frame")
  -- Cell 0 is tile 0: sheet column 0, row 0, screen 0,0.
  local first = batch.sprites[1]
  eq(first[2], 0, "cell 0 lands at x 0")
  eq(first[3], 0, "cell 0 lands at y 0")
  eq(first[1].x, 0, "and reads sheet column 0")
  eq(first[1].y, 0, "and sheet row 0")
  -- Cell 21 is screen (1, 1) and, with this tilemap, tile 21: sheet column
  -- 21 % 16 = 5, row 1.
  local cell21 = batch.sprites[22]
  eq(cell21[2], 8, "cell 21 lands one tile in")
  eq(cell21[3], 8, "and one tile down")
  eq(cell21[1].x, 5 * 8, "reading sheet column 5")
  eq(cell21[1].y, 8, "of sheet row 1")
end

-- The strings, at the literal hlcoord operands PlaceDiplomaOnScreen uses.
local placed = {}
local realPrintThrough = Chrome.printThrough
Chrome.printThrough = function(text, tx, ty, pal)
  placed[#placed + 1] = { text = text, x = tx, y = ty, palette = pal }
  return 0
end
local okDraw, drawErr = pcall(function() screen:draw() end)
Chrome.printThrough = realPrintThrough
check(okDraw, "the screen draws: " .. tostring(drawErr))
eq(#placed, 7, "PLAYER, the name and the five certification lines")
eq(placed[1].text, "PLAYER", "hlcoord 2, 5 is .Player")
eq(placed[1].x, 2, "at column 2")
eq(placed[1].y, 5, "on row 5")
eq(placed[2].text, "GOLD", "hlcoord 9, 5 is wPlayerName")
eq(placed[2].x, 9, "at column 9")
eq(placed[2].y, 5, "on the same row")
local CERTIFICATION = { "This certifies", "that you have", "completed the",
                        "new #DEX.", "Congratulations!" }
for index, line in ipairs(CERTIFICATION) do
  local entry = placed[index + 2]
  eq(entry.text, line, ".Certification line " .. index)
  eq(entry.x, 2, "at column 2, where PlaceString restarts each `next`")
  eq(entry.y, 7 + index,
    "on row " .. (7 + index) .. ", one down from hlcoord 2, 8")
end
check(placed[1].palette ~= nil,
  "and every string goes through the page's own palette, not a black print")

-- A cache without the stage still opens the screen: the placeholder frame.
local bare = Diploma.new(nil, { playerName = "GOLD" })
check(bare:batch() == nil, "no gen2Diploma in the cache means no tilemap")
local okBare = pcall(function() bare:draw() end)
check(okBare, "and the screen still draws its placeholder frame")

S.finish()
