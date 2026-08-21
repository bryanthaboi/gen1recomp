-- The trade animation's art (engine/movie/trade_animation.asm, gfx/trade/).
--   GOLD_CACHE="..." luajit tests/gen2_trade_gfx_test.lua
--
-- The animation itself is pinned in tests/gen2_events_test.lua; what is here
-- is the art it draws with, which used to be nothing at all -- src/ui/gen2/
-- TradeAnim.lua drew the shapes those tiles are.  Four things are worth
-- holding down: that the extractor stage exists AND is called from run(), that
-- the nine labels it reads are in the curated manifest set (a missing symbol
-- is a silently empty stage), that what it wrote matches ../pokegold/gfx/
-- trade/ byte for byte, and that the screen actually blits it rather than
-- carrying dead cache data.
--
-- ROM-free.  The decomp section SKIPs with no ../pokegold beside the repo and
-- the cache section SKIPs (or asks for a re-import) with no Gold cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 trade gfx")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Chrome = require("src.ui.gen2.Chrome")
local TradeAnimView = require("src.ui.gen2.TradeAnim")

-- TradeGameBoyLZ decompresses to 49 tiles into vTiles2 tile $31: 34 of
-- game_boy.2bpp (--remove-duplicates) then 15 of link_cable.2bpp.
local SCENE_TILES = 49
local SCENE_SHEET_TILES = 7
local BASE_TILE = 0x31
local GAMEBOY_W, GAMEBOY_H = 6, 8
local TUBE_W, TUBE_H = 12, 3

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
check(type(RomExtractorGen2.extractTrade) == "function",
  "RomExtractorGen2:extractTrade exists")
check(extractorSource:find("results.trade = self:extractTrade()", 1, true)
  ~= nil, "and RomExtractorGen2:run calls it")
check(extractorSource:find("local STAGE_COUNT = 26", 1, true) ~= nil,
  "STAGE_COUNT counts the new stage, so the progress bar still ends at 1")

-- pokegold.sym, bank $0a.  These are also what the cache is checked against
-- below, so a manifest that drifts shows up here rather than as a blank
-- screen.
local SYMBOLS = {
  TradeGameBoyTilemap = { 0x0a, 0x5713 },
  TradeLinkTubeTilemap = { 0x0a, 0x5743 },
  TradeArrowRightGFX = { 0x0a, 0x5767 },
  TradeArrowLeftGFX = { 0x0a, 0x5777 },
  TradeCableGFX = { 0x0a, 0x5787 },
  TradeBubbleGFX = { 0x0a, 0x57a7 },
  TradeGameBoyLZ = { 0x0a, 0x57e7 },
  TradeBallGFX = { 0x0a, 0x5927 },
  TradePoofGFX = { 0x0a, 0x5987 },
}

do
  local f = assert(io.open("tools/make_gold_manifest.py", "r"))
  local manifestSource = f:read("*a")
  f:close()
  for label in pairs(SYMBOLS) do
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
    for label, location in pairs(SYMBOLS) do
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
local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local decompGameBoy = readFile(pokegold .. "/gfx/trade/game_boy.tilemap")
local decompTube = readFile(pokegold .. "/gfx/trade/link_cable.tilemap")
if not (decompGameBoy and decompTube) then
  check(true, "no ../pokegold: the two tilemaps are not pinned (SKIP)")
else
  eq(#decompGameBoy, GAMEBOY_W * GAMEBOY_H,
    "gfx/trade/game_boy.tilemap is the 6x8 the INCBIN comment says")
  eq(#decompTube, TUBE_W * TUBE_H, "and link_cable.tilemap is 12x3")
  local highest = 0
  for _, body in ipairs({ decompGameBoy, decompTube }) do
    for i = 1, #body do
      local id = body:byte(i)
      if id > highest then highest = id end
    end
  end
  check(highest < BASE_TILE + SCENE_TILES,
    "every id in them, and the loose cable ids, index the one 49-tile sheet")
end

-- ---- the cache ------------------------------------------------------------
-- Same default every other gen2 suite uses, so a run with no GOLD_CACHE set
-- still reads the cache instead of skipping silently.
local cache = os.getenv("GOLD_CACHE")
  or ((os.getenv("HOME") or "") .. "/Library/Application Support/LOVE/gold-dev/gold")
local function loadCache(name)
  local chunk = loadfile(cache .. "/data/generated/" .. name .. ".lua")
  return chunk and chunk() or nil
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

local trade = loadCache("trade")
if not trade then
  check(true,
    "cache predates the Trade animation stage : re-import for gfx/trade (SKIP)")
else
  eq(trade.generation, 2, "trade.lua is a Gen 2 table")
  eq(trade.tiles, SCENE_TILES, "TradeGameBoyLZ decompressed to 49 tiles")
  eq(trade.sheetTiles, SCENE_SHEET_TILES, "written 7 across, so nothing pads")
  eq(trade.baseTile, BASE_TILE,
    "with the vTiles2 tile the BG ids count from, not 0")
  eq(trade.image, "assets/generated/trade/scene.png",
    "the sheet went where the screen looks for it")
  local w, h = pngSize("assets/generated/trade/scene.png")
  eq(w, SCENE_SHEET_TILES * 8, "the sheet is 56px wide")
  eq(h, SCENE_SHEET_TILES * 8, "and 56px tall, which is 49 tiles exactly")

  local function tilemap(key, width, height, decomp, file)
    local map = trade[key]
    if type(map) ~= "table" or type(map.tiles) ~= "table" then
      check(false, "trade.lua carries the " .. key .. " tilemap")
      return
    end
    eq(map.width, width, key .. " is " .. width .. " tiles across")
    eq(map.height, height, "and " .. height .. " down")
    eq(#map.tiles, width * height, "flat, in TradeAnim_CopyBoxFromDEtoHL order")
    if not decomp then
      check(true, "no ../pokegold: " .. file .. " is not diffed (SKIP)")
      return
    end
    local mismatch
    for i = 1, width * height do
      if map.tiles[i] ~= decomp:byte(i) then mismatch = i break end
    end
    check(mismatch == nil, mismatch
      and (key .. " differs from the decomp at byte " .. mismatch)
      or ("it is ../pokegold/gfx/trade/" .. file .. " byte for byte"))
  end
  tilemap("gameBoy", GAMEBOY_W, GAMEBOY_H, decompGameBoy, "game_boy.tilemap")
  tilemap("tube", TUBE_W, TUBE_H, decompTube, "link_cable.tilemap")

  -- The object sheets.  ball is 6 tiles and not 8 because gfx/trade/ball.2bpp
  -- is built with --remove-whitespace: pret's 16x32 PNG holds the blank right
  -- half of the first wobble frame, which is X-flipped at draw time, and the
  -- ROM does not carry it.
  local SHEETS = {
    { "ball", 6, 1, "trade/ball.png" },
    { "poof", 12, 2, "trade/poof.png" },
    { "bulge", 2, 1, "trade/bulge.png" },
    { "bubble", 4, 2, "trade/bubble.png" },
    { "arrows", 2, 1, "trade/arrows.png" },
  }
  for _, sheet in ipairs(SHEETS) do
    local key, tiles, across, relative = sheet[1], sheet[2], sheet[3], sheet[4]
    local entry = trade[key]
    if type(entry) ~= "table" then
      check(false, "trade.lua carries the " .. key .. " sheet")
    else
      eq(entry.image, "assets/generated/" .. relative,
        key .. " went where the screen looks for it")
      eq(entry.tiles, tiles, key .. " is " .. tiles .. " tiles")
      eq(entry.sheetTiles, across, "laid out " .. across .. " across")
      local pw, ph = pngSize("assets/generated/" .. relative)
      eq(pw, across * 8, relative .. " is " .. (across * 8) .. "px wide")
      eq(ph, tiles / across * 8, "and " .. (tiles / across * 8) .. "px tall")
    end
  end
end

-- ---- the way in -----------------------------------------------------------
-- Written data nothing mounts is written data nobody sees, so the loader line
-- is read out of the source the same way the extractor's call site was.
do
  local f = assert(io.open("src/core/Game2.lua", "r"))
  local source = f:read("*a")
  f:close()
  check(source:find('self.data.gen2Trade = loadGenerated'
    .. '("data/generated/trade.lua")', 1, true) ~= nil,
    "Game2 mounts trade.lua as data.gen2Trade")
end
do
  local f = assert(io.open("src/ui/gen2/TradeMenu.lua", "r"))
  local source = f:read("*a")
  f:close()
  check(source:find('Screens.push(game, "Gen2TradeAnim"', 1, true) ~= nil,
    "and TradeMenu:playAnim still opens the screen that reads it")
end

-- ---- the screen -----------------------------------------------------------
-- The whole point of the stage: a screen that reads the cache instead of
-- drawing shapes.  love.graphics.draw is recorded so a blit can be checked
-- against the tilemap byte and the OAM offset it came from.
local DATA = { pokemon = { DROWZEE = { name = "DROWZEE", dex = 96 },
                           MACHOP = { name = "MACHOP", dex = 66 } } }
local SAVE = { player = { name = "SILVER", id = 999 } }
local ROW = { otName = "MIKE", otId = 1234 }
local GIVEN = { species = "DROWZEE", otName = "GOLD", otId = 12345 }
local RECEIVED = { species = "MACHOP", otName = "MIKE", otId = 1234 }

-- A tilemap whose cells are their own index plus the base tile, so a blit's
-- expected sheet position is arithmetic rather than a lookup.
local function fakeTilemap(width, height)
  local tiles = {}
  for index = 0, width * height - 1 do
    tiles[index + 1] = BASE_TILE + index
  end
  return { width = width, height = height, tiles = tiles }
end

local FAKE = {
  image = "assets/generated/trade/scene.png",
  tiles = SCENE_TILES,
  sheetTiles = SCENE_SHEET_TILES,
  baseTile = BASE_TILE,
  gameBoy = fakeTilemap(GAMEBOY_W, GAMEBOY_H),
  tube = fakeTilemap(TUBE_W, TUBE_H),
  ball = { image = "assets/generated/trade/ball.png", tiles = 6,
           sheetTiles = 1 },
  poof = { image = "assets/generated/trade/poof.png", tiles = 12,
           sheetTiles = 2 },
  bulge = { image = "assets/generated/trade/bulge.png", tiles = 2,
            sheetTiles = 1 },
  bubble = { image = "assets/generated/trade/bubble.png", tiles = 4,
             sheetTiles = 2 },
  arrows = { image = "assets/generated/trade/arrows.png", tiles = 2,
             sheetTiles = 1 },
}

local function newView(gfx)
  return TradeAnimView.new({ data = DATA, save = SAVE }, {
    row = ROW, given = GIVEN, received = RECEIVED, save = SAVE, gfx = gfx,
  })
end

-- Records every draw as { path, quadX, quadY, x, y, sx, sy }.
local drawn = {}
local realDraw = love.graphics.draw
local function record(image, quad, x, y, _r, sx, sy)
  if type(quad) == "table" and quad.w == 8 then
    drawn[#drawn + 1] = { path = image and image.path, qx = quad.x,
      qy = quad.y, x = x, y = y, sx = sx or 1, sy = sy or 1 }
  end
end
local function capture(view, body)
  drawn = {}
  love.graphics.draw = record
  local ok, err = pcall(body, view)
  love.graphics.draw = realDraw
  check(ok, "the screen draws: " .. tostring(err))
  return drawn
end

local function countFrom(list, path)
  local n = 0
  for _, entry in ipairs(list) do
    if entry.path == path then n = n + 1 end
  end
  return n
end

do
  local view = newView(FAKE)
  -- The tube beat: TradeLinkTubeTilemap at hlcoord 8, 2, home once the
  -- $a0 scroll has drained.
  local tube = capture(view, function(v) v:drawTube(0) end)
  eq(countFrom(tube, "assets/generated/trade/scene.png"), TUBE_W * TUBE_H,
    "the tube is 36 tile blits, not a rounded rectangle")
  local first = tube[1]
  eq(first.x, 64, "cell 0 lands at hlcoord 8, 2")
  eq(first.y, 16, "which is (64, 16)")
  eq(first.qx, 0, "reading sheet column 0")
  eq(first.qy, 0, "of sheet row 0")
  -- Cell 8 is tile $39: sheet column 8 % 7 = 1, row 1.
  local ninth = tube[9]
  eq(ninth.x, 64 + 8 * 8, "cell 8 is eight tiles along")
  eq(ninth.qx, 8 % SCENE_SHEET_TILES * 8, "reading the sheet column its id says")
  eq(ninth.qy, math.floor(8 / SCENE_SHEET_TILES) * 8, "and the sheet row")

  -- A scrolled tube: EnterLinkTube2 moves hSCX, and hSCX scrolls the
  -- BACKGROUND, so the offset comes off the tube's x.
  local scrolled = capture(view, function(v) v:drawTube(0x20) end)
  eq(scrolled[1].x, 64 - 0x20, "the offset slides the whole stamp left")

  -- The Game Boy: 48 tiles at the pan's own unrolled position.
  local gb = capture(view, function(v) v:drawGameBoy(24, 16) end)
  eq(#gb, GAMEBOY_W * GAMEBOY_H, "the Game Boy is its 6x8 tilemap")
  eq(gb[1].x, 24, "stamped at hlcoord 3, 2")
  eq(gb[1].y, 16, "in state 0")
  eq(gb[GAMEBOY_W + 1].y, 24, "the second row is one tile down")
  eq(gb[GAMEBOY_W + 1].x, 24, "back at the left edge")

  -- The scene: both Game Boys plus the cable the jumptable ByteFills.  The
  -- second one is a whole 256-pixel wrap further along.
  local scene = capture(view, function(v) v:drawScene(0) end)
  eq(#scene, GAMEBOY_W * GAMEBOY_H * 2 + 46,
    "two Game Boys and the 46 cable cells around them")
  local far
  for _, entry in ipairs(scene) do
    if entry.x == 0x100 + 80 and entry.y == 48 then far = entry end
  end
  check(far ~= nil,
    "the second Game Boy sits at hlcoord 10, 6 of the map after the wrap")

  -- The ball: .OAMData_TradePokeBall1 is the left half twice, the right one
  -- X-flipped, centred on the sprite anim's origin.
  local ball = capture(view, function(v) v:drawBall(80, 68, false) end)
  eq(#ball, 4, "four OAM entries")
  eq(ball[1].x, 72, "the first hangs 8 pixels left of the origin")
  eq(ball[1].y, 60, "and 8 above it")
  eq(ball[2].sx, -1, "the right half is the same tile X-flipped")
  eq(ball[2].x, 80 + 8, "whose anchor moves a tile along to compensate")
  eq(ball[1].qy, 0, "reading tile 0")
  eq(ball[3].qy, 8, "and tile 1 underneath it")

  -- The poof and the bubble are 2x2 quadrants mirrored into 32x32.
  local poof = capture(view, function(v) v:drawPoof(80, 68, 0) end)
  eq(#poof, 16, ".OAMData_TradePoofBubble is sixteen entries")
  eq(poof[1].x, 80 - 16, "the top-left quadrant starts two tiles out")
  eq(poof[1].y, 68 - 16, "in both axes")
  local flippedX, flippedY, both = 0, 0, 0
  for _, entry in ipairs(poof) do
    if entry.sx < 0 and entry.sy < 0 then both = both + 1
    elseif entry.sx < 0 then flippedX = flippedX + 1
    elseif entry.sy < 0 then flippedY = flippedY + 1 end
  end
  eq(flippedX, 4, "one quadrant X-flipped")
  eq(flippedY, 4, "one Y-flipped")
  eq(both, 4, "and one both ways")

  -- Frame 2 of the poof reads the next four tiles, not the same four.
  local later = capture(view, function(v) v:drawPoof(80, 68, 4) end)
  eq(later[1].qy, 2 * 8, "the second frame is four tiles further into the sheet")

  -- The bulge is one tile mirrored, which is why gfx/trade/cable.png is 8x16.
  local bulge = capture(view, function(v) v:drawBulge(80, 24, 0) end)
  eq(#bulge, 4, ".OAMData_TradeTubeBulge is one tile drawn four ways")
  eq(bulge[1].x, 72, "top-left of a 16x16 centred on the origin")
  eq(bulge[1].y, 16, "which puts it inside the tube")

  -- The strip under the pan: the rule, the two trainers and the six arrows.
  -- Chrome.print is stubbed out because the headless font has no glyphs, and
  -- what it was handed is worth reading anyway.
  local printed = {}
  local realPrint, realPrintRight = Chrome.print, Chrome.printRight
  Chrome.print = function(text, tx, ty)
    printed[#printed + 1] = { text = text, x = tx, y = ty }
    return 0
  end
  Chrome.printRight = function(text, txEnd, ty)
    printed[#printed + 1] = { text = text, right = txEnd, y = ty }
    return 0
  end
  local strip = capture(view, function(v) v:drawTubeStrip(true) end)
  local back = capture(view, function(v) v:drawTubeStrip(false) end)
  Chrome.print, Chrome.printRight = realPrint, realPrintRight
  eq(#printed, 6, "the rule and the two trainers, on each pan")
  eq(#printed[1].text, #("─"):rep(20), "row 0 is SCREEN_WIDTH of the rule")
  eq(printed[1].y, 0, "on the window's first row")
  eq(printed[2].text, "SILVER",
    "wLinkPlayer1Name is the player, which TradeAnimation loads from"
      .. " wPlayerTrademonSenderName")
  eq(printed[2].y, 1, "at hlcoord 0, 1")
  eq(printed[3].text, "MIKE", "wLinkPlayer2Name is the OT")
  eq(printed[3].right, 20,
    "right-aligned, which is what `hlcoord 0, 4 / add hl, de` lands on")
  eq(printed[3].y, 3, "one row up from the hlcoord, across the row boundary")
  eq(countFrom(strip, "assets/generated/trade/arrows.png"), 6,
    "six arrows, the ByteFill's own count")
  eq(strip[1].x, 7 * 8, "the first at hlcoord 7, 2 of the window")
  eq(strip[1].y, 2 * 8, "on the window's third row")
  eq(strip[1].qy, 0, "sending draws TradeArrowRightGFX")
  eq(back[1].qy, 8, "and receiving draws TradeArrowLeftGFX")
end

-- A cache without the stage still runs the animation: the shapes, not a crash.
do
  local bare = newView(nil)
  check(bare.gfx == nil, "no gen2Trade in the cache means no sheets")
  local ok = pcall(function()
    bare:drawTube(0)
    bare:drawScene(0)
    bare:drawBall(80, 68, true)
    bare:drawPoof(80, 68, 0)
    bare:drawBulge(80, 24, 0)
  end)
  check(ok, "and every routine falls back to the shape it used to draw")
end

S.finish()
