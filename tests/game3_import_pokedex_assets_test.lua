#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Extract = require("src.import.gba.pokedex_chrome_extract")
local Versions = require("src.import.gba.versions")
local CacheContract = require("src.import.CacheContract")

local PAPER_BYTES = 240 * 160 * 4
local FOOT_BYTES = 16 * 16 * 4

print("[test] 1. the dex page background and the footprint table are pinned")
check(Extract.PAPER_BG_FILE == "paper_bg.rgba", "paper_bg.rgba is the baked dex page background")
check(Extract.PAPER_BG_W == 240 and Extract.PAPER_BG_H == 160, "the dex page background is 240x160")
-- src/pokedex_screen.c:930
check(Extract.PAPER_TILE == 0x001, "the page fill is tile 0x001 on palette 0")
-- src/pokedex_screen.c:1161
check(Extract.PAPER_BAR_PAL == 15 and Extract.PAPER_BAR_COLOR == 15,
  "the top and bottom bars are PIXEL_FILL(15) on palette 15")
check(Extract.PAPER_BAR_ROWS == 2, "the bars are two tile rows tall")
check(Extract.FOOTPRINT_TABLE == 0x43FAB0, "gMonFootprintTable is at 0x43FAB0")
check(Extract.FOOTPRINT_BYTES == 32 and Extract.FOOTPRINT_W == 16 and Extract.FOOTPRINT_H == 16,
  "a footprint is 32 bytes of 1bpp, 16x16")
-- src/data/pokemon_graphics/footprint_table.h:255
check(Extract.FOOTPRINT_QUESTION_MARK_SPECIES == 252,
  "the unused slots carry gMonFootprint_QuestionMark")
check(type(Extract.extractPaperBg) == "function"
  and type(Extract.extractFootprints) == "function"
  and type(Extract.bakeFootprint) == "function"
  and type(Extract.footprintTable) == "function",
  "pokedex_chrome_extract bakes the page background and the footprints")
if type(Extract.bakeFootprint) ~= "function" or type(Extract.footprintTable) ~= "function" then
  finish()
end

print("[test] 2. the 1bpp footprint decode matches DexScreen_DrawMonFootprint")
local blob = {}
for i = 1, 32 do blob[i] = 0 end
blob[1] = 0x01
blob[9] = 0x80
blob[24] = 0x01
blob[28] = 0x02
local rgba = Extract.bakeFootprint(string.char(unpack(blob)), 0, 0, 0)
check(#rgba == FOOT_BYTES, "a baked footprint is " .. FOOT_BYTES .. " bytes (" .. #rgba .. ")")
local function pixel(data, x, y)
  local o = (y * 16 + x) * 4
  return data:byte(o + 1), data:byte(o + 2), data:byte(o + 3), data:byte(o + 4)
end
local function alphaAt(data, x, y)
  local _, _, _, a = pixel(data, x, y)
  return a
end
check(alphaAt(rgba, 0, 0) == 255, "bit 0 of tile 0 row 0 is the top left pixel")
check(alphaAt(rgba, 15, 0) == 255, "bit 7 of tile 1 row 0 is the top right pixel")
check(alphaAt(rgba, 0, 15) == 255, "tile 2 row 7 is the bottom left pixel")
check(alphaAt(rgba, 9, 11) == 255, "tile 3 row 3 bit 1 lands at x=9 y=11")
local lit = 0
for i = 4, #rgba, 4 do
  if rgba:byte(i) ~= 0 then lit = lit + 1 end
end
check(lit == 4, "only the four set bits are opaque (" .. lit .. ")")
local colored = Extract.bakeFootprint(string.char(unpack(blob)), 12, 34, 56)
local r, g, b, a = pixel(colored, 0, 0)
check(r == 12 and g == 34 and b == 56 and a == 255, "a set bit takes the dex text colour")
r, g, b, a = pixel(colored, 1, 0)
check(r == 0 and g == 0 and b == 0 and a == 0, "a clear bit is transparent")

print("[test] 3. gMonFootprintTable is read out of the ROM and refused when it does not fit")
local bytes = {}
local function poke32(off, value)
  for i = 0, 3 do bytes[off + i] = math.floor(value / 256 ^ i) % 256 end
end
local base = Extract.FOOTPRINT_TABLE
local count = Versions.NUM_SPECIES or 412
for sp = 0, count - 1 do
  poke32(base + sp * 4, 0x08D30000 + sp * 32)
end
-- src/data/pokemon_graphics/footprint_table.h:3
poke32(base, 0x08D30000)
poke32(base + 4, 0x08D30000)
local rom = { get = function(_, off) return bytes[off] or 0 end }
local offsets = Extract.footprintTable(rom)
check(type(offsets) == "table", "the table parses")
if type(offsets) == "table" then
  check(offsets[0] == 0xD30000 and offsets[1] == 0xD30000,
    "SPECIES_NONE and SPECIES_BULBASAUR share gMonFootprint_Bulbasaur")
  check(offsets[count - 1] == 0xD30000 + (count - 1) * 32,
    "every species down to " .. (count - 1) .. " has an entry")
end
poke32(base + 4, 0x08D30020)
check(Extract.footprintTable(rom) == nil, "a table whose first two entries differ is refused")
poke32(base + 4, 0x08D30000)
poke32(base, 0x02000000)
check(Extract.footprintTable(rom) == nil, "a pointer outside the ROM is refused")
poke32(base, 0x08D30000)
check(type(Extract.footprintTable(rom, { footprint_table = base })) == "table",
  "the table address can be overridden")

print("[test] 4. the dex page background is the ROM page tile plus the two bars")
local gfx = {}
for i = 1, 4 * 32 do gfx[i] = 0 end
for i = 1, 32 do gfx[1 * 32 + i] = 0x55 end
for i = 1, 32 do gfx[3 * 32 + i] = 0x20 end
local pal = {}
for i = 0, 255 do pal[i] = 0 end
pal[5] = 0x7FFF
pal[240 + 15] = 0x294A
local paper = Extract.bakePaperBg(gfx, pal)
check(#paper == PAPER_BYTES, "the page background is " .. PAPER_BYTES .. " bytes (" .. #paper .. ")")
local function paperPixel(x, y)
  local o = (y * 240 + x) * 4
  return paper:byte(o + 1), paper:byte(o + 2), paper:byte(o + 3), paper:byte(o + 4)
end
r, g, b, a = paperPixel(120, 80)
check(r == 255 and g == 255 and b == 255 and a == 255, "the page body is palette 0 colour 5")
r, g, b, a = paperPixel(1, 3)
check(r == 82 and g == 82 and b == 82 and a == 255, "the top bar is palette 15 colour 15")
r, g, b, a = paperPixel(1, 151)
check(r == 82 and g == 82 and b == 82 and a == 255, "the bottom bar is palette 15 colour 15")
r, g, b, a = paperPixel(0, 15)
check(r == 82 and g == 82 and b == 82 and a == 255, "the bar fill covers every pixel of the two rows")
local opaque = true
for i = 4, #paper, 4 do
  if paper:byte(i) ~= 255 then opaque = false break end
end
check(opaque, "the page background is fully opaque")

print("[test] 5. the cache contract requires the dex page background and the footprints")
local required = CacheContract.requiredFiles("firered")
local want = {
  "data/generated/gba/pokemon/pokedex/paper_bg.rgba",
  "data/generated/gba/pokemon/pokedex/footprints/1.rgba",
  "data/generated/gba/pokemon/pokedex/footprints/bulbasaur.rgba",
  "data/generated/gba/pokemon/pokedex/footprints/question_mark.rgba",
}
local have = {}
for _, path in ipairs(required) do have[path] = true end
for _, path in ipairs(want) do
  check(have[path] == true, "the firered contract requires " .. path)
end
for _, path in ipairs(want) do
  local fs = {
    prefix = "",
    exists = function(candidate) return candidate ~= path end,
  }
  local complete, missing = CacheContract.allRequiredFilesExist("firered", fs)
  check(complete == false and missing == path,
    "a cache without " .. path .. " is incomplete (" .. tostring(missing) .. ")")
end

print("[test] 6. a built cache carries the baked assets")
local Cache = require("tests.game3_cache")
local root = Cache.root("pokemon/pokedex/manifest.lua")
if not root then
  print("[skip] baked dex assets: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. root)

local function readFile(rel)
  local f = io.open(root .. "/pokemon/pokedex/" .. rel, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local manifestSrc = readFile("manifest.lua")
local manifest = manifestSrc and loadstring(manifestSrc)
manifest = manifest and manifest()
if type(manifest) ~= "table" or (tonumber(manifest.format) or 0) < 5 then
  print("[skip] baked dex assets: cache manifest is format "
    .. tostring(manifest and manifest.format) .. ", the dex bake needs 5")
  finish()
end

local cachedPaper = readFile("paper_bg.rgba")
check(cachedPaper ~= nil and #cachedPaper == PAPER_BYTES,
  "paper_bg.rgba is " .. PAPER_BYTES .. " bytes (" .. tostring(cachedPaper and #cachedPaper) .. ")")
if cachedPaper then
  local chrome = loadstring(readFile("chrome.lua") or "return {}")()
  local want = chrome.bar_kanto or {}
  local white, bar = 0, 0
  for i = 1, #cachedPaper, 4 do
    local r, g, b = cachedPaper:byte(i, i + 2)
    if r == 255 then white = white + 1
    elseif r == want[1] and g == want[2] and b == want[3] then bar = bar + 1 end
  end
  check(white == 240 * 128, "the page body is 128 rows of white (" .. white .. ")")
  -- src/pokedex_screen.c:1161
  check(bar == 240 * 32, "the bars are 32 rows of the Kanto bar colour (" .. bar .. ")")
end

local bulbasaur = readFile("footprints/1.rgba")
check(bulbasaur ~= nil and #bulbasaur == FOOT_BYTES,
  "footprints/1.rgba is " .. FOOT_BYTES .. " bytes (" .. tostring(bulbasaur and #bulbasaur) .. ")")
if bulbasaur then
  local ink = 0
  for i = 4, #bulbasaur, 4 do
    if bulbasaur:byte(i) == 255 then ink = ink + 1 end
  end
  check(ink > 0 and ink < 256, "the bulbasaur footprint has ink and transparency (" .. ink .. ")")
end
check(readFile("footprints/bulbasaur.rgba") == bulbasaur,
  "the species name alias is the same footprint as the id")
local qmark = readFile("footprints/question_mark.rgba")
check(qmark ~= nil and #qmark == FOOT_BYTES, "footprints/question_mark.rgba is baked")
check(qmark ~= bulbasaur, "the question mark footprint is its own art")
local last = readFile("footprints/" .. tostring((Versions.NUM_SPECIES or 412) - 1) .. ".rgba")
check(last ~= nil and #last == FOOT_BYTES,
  "the last species has a footprint (" .. tostring(last and #last) .. ")")
local nidoranF = readFile("footprints/nidoran\226\153\128.rgba")
local nidoranM = readFile("footprints/nidoran\226\153\130.rgba")
check(nidoranF ~= nil and nidoranM ~= nil and nidoranF ~= nidoranM,
  "the two NIDORAN keep their own footprints")
check(readFile("footprints/nidoran.rgba") == nil,
  "no ambiguous nidoran.rgba shadows either of them")
check(readFile("footprints/29.rgba") == nidoranF and readFile("footprints/32.rgba") == nidoranM,
  "the gendered aliases match their species ids")

finish()
