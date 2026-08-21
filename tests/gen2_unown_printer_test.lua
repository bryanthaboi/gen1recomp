-- The Unown font (gfx/font/unown_font.png) and the ALPH RUINS STAMP viewer
-- (engine/events/print_unown.asm _UnownPrinter).
--   GOLD_CACHE="..." luajit tests/gen2_unown_printer_test.lua
--
-- Two leftovers from the Ruins of Alph, and they share a suite because they
-- share a subject: the letters.  The font is the alphabet UNOWN MODE prints
-- its ring and its word in, and the viewer is the screen that lays the caught
-- forms out for a printer this port does not have.
--
-- Three things are worth pinning about the font: that the extractor block
-- exists and is reached from a stage run() actually calls, that the symbol it
-- reads is in the curated manifest set (a label missing from REQUIRED_SYMBOLS
-- makes self.symbols[label] nil and the block silently writes nothing -- the
-- exact way givepokemail and the trade texts were lost), and that what landed
-- in the cache has the shape of ../pokegold/gfx/font/unown_font.png.
--
-- And two about the viewer: that its wheel is the cart's (27 slots, the 27th
-- VACANT, wrapping both ways) and that it is REACHED -- Screens id, World
-- hook, and a `special UnownPrinter` dispatched by name.
--
-- ROM-free.  The decomp section SKIPs with no ../pokegold beside the repo and
-- the cache section SKIPs (or asks for a re-import) with no Gold cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 unown printer")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local Screens = require("src.ui.Screens")
local Specials = require("src.script.gen2.Specials")
local Unown = require("src.core.gen2.Unown")
local UnownPrinter = require("src.ui.gen2.UnownPrinter")
local Vm = require("src.script.gen2.Vm")

-- NUM_UNOWN + 1 tiles on pret's 3-wide sheet, and FIRST_UNOWN_CHAR is $40.
local UNOWN_TILES = 27
local UNOWN_WIDE = 3
local FIRST_UNOWN_CHAR = 0x40

local function readFile(path, mode)
  local f = io.open(path, mode or "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

-- PNG IHDR: width and height are big-endian at bytes 17 and 21.
local function pngSize(body)
  local function be32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return be32(body, 17), be32(body, 21)
end

-- ---- the extractor --------------------------------------------------------
-- The font is written inside the Fonts stage rather than as a stage of its
-- own, so what has to be proved here is that the block is in extractFont and
-- that extractFont is still called from run().
local extractorSource = assert(readFile("src/import/RomExtractorGen2.lua", "r"))
check(extractorSource:find("results.font = self:extractFont()", 1, true) ~= nil,
  "RomExtractorGen2:run still calls extractFont")
check(extractorSource:find('if self.symbols["UnownFont"] then', 1, true) ~= nil,
  "and extractFont reads UnownFont out of the manifest")
check(extractorSource:find('"fonts/unown_font.png"', 1, true) ~= nil,
  "and writes it as fonts/unown_font.png")
check(extractorSource:find("local UNOWN_FONT_TILES = 27", 1, true) ~= nil,
  "27 tiles: NUM_UNOWN letters plus the cursor")
check(extractorSource:find("local UNOWN_FONT_WIDE = 3", 1, true) ~= nil,
  "on pret's own 3-tile-wide sheet, so the decode IS the pret PNG")

do
  local manifestSource = assert(readFile("tools/make_gold_manifest.py", "r"))
  check(manifestSource:find('"UnownFont"', 1, true) ~= nil,
    "UnownFont is in make_gold_manifest.py's REQUIRED_SYMBOLS")
end

local Json = require("src.link.Json")
do
  local body = readFile("tools/rom_manifest_gold.json", "r")
  if not body then
    check(true, "no tools/rom_manifest_gold.json (SKIP)")
  else
    local symbols = (Json.decode(body).symbols) or {}
    local got = symbols.UnownFont
    if not got then
      check(false, "the generated manifest carries UnownFont")
    else
      -- pokegold.sym: 3e:730e UnownFont.
      eq(got[1], 0x3e, "UnownFont is in the bank pokegold.sym says")
      eq(got[2], 0x730e, "and at the address pokegold.sym says")
    end
  end
end

-- ---- the decomp -----------------------------------------------------------
-- gfx/font/unown_font.png is the source of truth for the sheet's shape.  Its
-- PIXELS were checked against the ROM at UnownFont directly (a row-major
-- 2bpp decode of 27 tiles is the PNG byte for byte, both planes equal, so the
-- glyphs are shade 3 on shade 0); what a Lua suite can read without a PNG
-- decoder is the header, which is what pins 3x9 tiles here.
do
  local root = os.getenv("POKEGOLD") or "../pokegold"
  local png = readFile(root .. "/gfx/font/unown_font.png")
  if not png then
    check(true, "no ../pokegold: the font's shape is not pinned (SKIP)")
  else
    local w, h = pngSize(png)
    eq(w, UNOWN_WIDE * 8, "gfx/font/unown_font.png is 3 tiles across")
    eq(h, UNOWN_TILES / UNOWN_WIDE * 8, "and 9 down, which is 27 tiles")
  end
end

-- ---- the cache ------------------------------------------------------------
local cache = os.getenv("GOLD_CACHE")
  or ((os.getenv("HOME") or "")
      .. "/Library/Application Support/LOVE/gold-dev/gold")
local fontData = (function()
  local chunk = loadfile(cache .. "/data/generated/font.lua")
  return chunk and chunk() or nil
end)()

if not fontData then
  check(true, "no Gold cache: the font table is not read (SKIP)")
elseif not fontData.imageUnown then
  check(true,
    "cache predates the Unown font : re-import for gfx/font/unown_font (SKIP)")
else
  eq(fontData.imageUnown, "assets/generated/fonts/unown_font.png",
    "the sheet went where the #DEX looks for it")
  eq(fontData.unownTiles, UNOWN_TILES, "27 tiles came out")
  eq(fontData.unownWide, UNOWN_WIDE, "as a 3-wide sheet")
  eq(fontData.unownBase, FIRST_UNOWN_CHAR,
    "based at FIRST_UNOWN_CHAR, the VRAM tile Pokedex_LoadUnownFont loads at")
  local png = readFile(cache .. "/assets/generated/fonts/unown_font.png")
  if not png then
    check(false, "the sheet PNG is actually in the cache")
  else
    local w, h = pngSize(png)
    eq(w, UNOWN_WIDE * 8, "the cached sheet is 24px wide")
    eq(h, UNOWN_TILES / UNOWN_WIDE * 8,
      "and 72px tall, which is the pret PNG's own shape")
  end
end

-- ---- UNOWN MODE draws through it ------------------------------------------
-- The ring of letters is `add FIRST_UNOWN_CHAR - 1` and the cursor is
-- FIRST_UNOWN_CHAR + NUM_UNOWN, so the mapping from a letter to a tile is the
-- whole of what this screen has to get right.  The sheet itself never loads
-- in a harness with no real love, so it is replaced with a recorder.
do
  local dexGame = {
    data = {
      pokemon = {},
      gen2MenuGfx = { pokedex = { tiles = "x.png",
        palette = { { 255, 255, 255 }, { 200, 100, 0 }, { 100, 0, 0 },
                    { 0, 0, 0 } } } },
      font = { imageUnown = "assets/generated/fonts/unown_font.png",
               unownWide = UNOWN_WIDE, unownBase = FIRST_UNOWN_CHAR },
    },
    save = { pokedex = { seen = {}, caught = {} }, unownDex = { 3, 1 } },
  }
  local dex = PokedexMenu.new(dexGame, {})
  check(dex.unownFont ~= nil,
    "the #DEX builds an Unown font sheet when the cache carries one")
  eq(dex.unownFontBase, FIRST_UNOWN_CHAR, "based at FIRST_UNOWN_CHAR")

  -- The dex's own sheet is a recorder too: love_stub's quads have no
  -- viewport, so a real TileSheet cannot draw in this harness and the chrome
  -- around the ring is not what is under test here.
  local quiet = { available = function() return true end,
                  draw = function() return true end }
  dex.sheet, dex.objs = quiet, quiet

  local drawn = {}
  dex.unownFont = {
    available = function() return true end,
    draw = function(_, tile, tx, ty)
      drawn[#drawn + 1] = { tile = tile, tx = tx, ty = ty }
      return true
    end,
  }
  dex:unownText("AZ", 4, 11)
  eq(#drawn, 2, "both letters went through the Unown sheet")
  eq(drawn[1].tile, FIRST_UNOWN_CHAR, "A is FIRST_UNOWN_CHAR")
  eq(drawn[2].tile, FIRST_UNOWN_CHAR + 25, "Z is FIRST_UNOWN_CHAR + 25")
  eq(drawn[2].tx, 5, "and the second glyph is one cell along")
  drawn = {}
  dex:unownCursor(3, 11)
  eq(drawn[1] and drawn[1].tile, FIRST_UNOWN_CHAR + Unown.NUM_UNOWN,
    "the cursor is the 27th tile, FIRST_UNOWN_CHAR + NUM_UNOWN")

  -- The word under the picture is spelled in the same font: unown_words.asm's
  -- `unownword` macro is `CHARVAL(...) - 'A' + FIRST_UNOWN_CHAR`.
  drawn = {}
  dex.view = "unown"
  local ok = pcall(function() dex:drawUnown() end)
  check(ok, "UNOWN MODE draws")
  local sawWord = false
  for _, row in ipairs(drawn) do
    if row.ty == 15 then sawWord = true end
  end
  check(sawWord, "and the word at hlcoord 4, 15 is Unown-font tiles too")

  -- A cache with no Unown font at all still prints the ring, in the ordinary
  -- inverted font, exactly as this screen did before the sheet existed.
  dexGame.data.font = {}
  local plain = PokedexMenu.new(dexGame, {})
  check(plain.unownFont == nil, "no sheet in the cache, no sheet on the screen")
  plain.sheet, plain.objs = quiet, quiet
  plain.view = "unown"
  check(pcall(function() plain:drawUnown() end),
    "and UNOWN MODE still draws without it")
end

-- ---- the viewer -----------------------------------------------------------
local hasId = false
for _, id in ipairs(Screens.GEN2_IDS) do
  if id == "Gen2UnownPrinter" then hasId = true end
end
check(hasId, "the viewer is pushed through the Gen2UnownPrinter Screens id")

local function newViewer()
  local pressed = {}
  local game = {
    data = { pokemon = {}, gen2Palettes = {} },
    input = { wasPressed = function(_, button) return pressed[button] end },
  }
  local closed = 0
  local screen = UnownPrinter.new(game, { onClose = function()
    closed = closed + 1
  end })
  return screen, pressed, function() return closed end
end

do
  local screen, pressed = newViewer()
  eq(screen.index, 0, "the wheel starts on the first letter")
  eq(screen:slots(), Unown.NUM_UNOWN + 1,
    "27 slots: the 26 forms and the vacant stamp")
  eq(screen:letter(), 1, "slot 0 is letter A")

  pressed.left = true
  screen:update(0)
  eq(screen.index, Unown.NUM_UNOWN,
    "LEFT off the first slot wraps to the vacant one (.press_left)")
  eq(screen:letter(), nil, "which has no letter to show")
  pressed.left = nil

  pressed.right = true
  screen:update(0)
  eq(screen.index, 0, "RIGHT past the vacant slot comes back to A")
  screen:update(0)
  eq(screen.index, 1, "and otherwise steps one letter at a time")
  pressed.right = nil
end

do
  local screen, pressed, closed = newViewer()
  pressed.a = true
  screen:update(0)
  eq(closed(), 0,
    "A is the print, and with no Game Boy Printer it does nothing at all")
  check(not screen.done, "the viewer stays up, the way .pressed_a loops back")
  pressed.a = nil
  pressed.b = true
  screen:update(0)
  eq(closed(), 1, "B closes it (.pressed_b, ReturnToMapFromSubmenu)")
  screen:update(0)
  eq(closed(), 1, "and closing twice is not two closes")
end

do
  -- Drawing with no art at all: every pic lookup fails in this harness, so
  -- this is a crash check, not a layout one.
  local screen = newViewer()
  check(pcall(function() screen:draw() end), "a letter slot draws")
  screen.index = Unown.NUM_UNOWN
  check(pcall(function() screen:draw() end), "and so does the vacant one")
end

-- ---- the special ----------------------------------------------------------
check(Specials.HANDLERS.UnownPrinter ~= nil,
  "UnownPrinter has a handler: the viewer half needs no printer")
eq(Specials.STUBS.UnownPrinter, nil, "and is not also stubbed")
check(Specials.STUBS.PrintDiploma ~= nil,
  "PrintDiploma, which is nothing but a print, still is")

-- The hook a Specials handler reaches for lives in World:specialHooks, NOT in
-- the table handed to Vm.new -- a hook registered in the wrong one is
-- reachable by nobody.
do
  local worldSource = assert(readFile("src/world/gen2/World.lua", "r"))
  local hooks = worldSource:find("function World:specialHooks", 1, true)
  local hook = worldSource:find("showUnownPrinter = function(onDone)", 1, true)
  check(hooks ~= nil and hook ~= nil and hook > hooks,
    "World:specialHooks is where showUnownPrinter is registered")
  check(worldSource:find('self:pushScreen("Gen2UnownPrinter"', 1, true) ~= nil,
    "and World:showUnownPrinter pushes the screen through the registry")
end

-- Dispatch by NAME through the cache's specialOrder, the way every other
-- special is dispatched.
do
  local ORDER = { [40] = "UnownPrinter" } -- 0-based id 39 in the real cache
  local opened = 0
  local vm = Vm.new({}, {}, {}, {
    specialOrder = ORDER,
    specials = {
      save = function() return { unownDex = { 1 } } end,
      showUnownPrinter = function(done) opened = opened + 1 done() end,
    },
  })
  vm.scriptVar = 7
  vm:runSpecial(39)
  eq(opened, 1, "`special UnownPrinter` opens the viewer")
  eq(vm.scriptVar, 7,
    "and leaves wScriptVar alone, because the routine never writes it")

  -- `ld a, [wUnownDex] / and a / ret z`: no Unown caught, no screen.
  local empty = 0
  local gated = Vm.new({}, {}, {}, {
    specialOrder = ORDER,
    specials = {
      save = function() return { unownDex = {} } end,
      showUnownPrinter = function(done) empty = empty + 1 done() end,
    },
  })
  gated.scriptVar = 4
  gated:runSpecial(39)
  eq(empty, 0, "an empty #DEX returns before the screen is drawn")
  eq(gated.scriptVar, 4, "still without touching wScriptVar")

  -- No hook at all (a Vm with no World behind it) has to return, not hang.
  local bare = Vm.new({}, {}, {},
    { specialOrder = ORDER, specials = {} })
  bare.scriptVar = 2
  bare:runSpecial(39)
  eq(bare.scriptVar, 2, "and a hookless VM carries on untouched")
end

S.finish()
