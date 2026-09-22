#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_pokedex_card_chrome_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

local playedSe = {}
package.loaded["src.core.game3.audio"] = {
  playSe = function(id) playedSe[#playedSe + 1] = id end,
  playCry = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local SE = require("src.core.game3.se_ids")
local PokedexChrome = require("src.ui.game3.pokedex_chrome")
local Pokedex = require("src.ui.game3.pokedex")

print("[test] 0. PokedexChrome exposes the pret entry-card chrome")
local hasCard = type(PokedexChrome.dataCardLayout) == "function"
  and type(PokedexChrome.areaCardLayout) == "function"
  and type(PokedexChrome.cardTilemap) == "function"
  and type(PokedexChrome.composeCard) == "function"
  and type(PokedexChrome.cardSheet) == "function"
check(hasCard, "card layout / tilemap / compose / sheet API present")
check(PokedexChrome.CARD_TILES == nil, "no tile rows live in source")
check(PokedexChrome.CARD_PALETTE == nil, "no palette table lives in source")

if hasCard then

print("[test] 1. Data card layout matches DexScreen_DexPageZoomEffectFrame(3, 6)")
local L = PokedexChrome.dataCardLayout()
eq(L.left, 0, "data left")
eq(L.top, 2, "data top")
eq(L.width, 28, "data width")
eq(L.height, 14, "data height")
eq(L.divTile, 11, "data divider tile row")
eq(L.x, 0, "data x")
eq(L.y, 16, "data y")
eq(L.w, 240, "data w")
eq(L.h, 128, "data h")
eq(L.borderLeft, 1, "data border left")
eq(L.borderRight, 237, "data border right")
eq(L.borderTop, 17, "data border top")
eq(L.borderBottom, 141, "data border bottom")
eq(L.borderThickness, 2, "data border thickness")
eq(L.dividerY, 88, "data divider y")
eq(L.upperY, 19, "data upper interior y")
eq(L.upperH, 69, "data upper interior height")
eq(L.lowerY, 96, "data lower interior y")
eq(L.lowerH, 45, "data lower interior height")

print("[test] 2. Area card layout has no divider and a full-height interior")
local A = PokedexChrome.areaCardLayout()
eq(A.divTile, nil, "area divider tile row is nil")
eq(A.dividerY, nil, "area divider y is nil")
eq(A.y, 16, "area y")
eq(A.h, 128, "area h")
eq(A.upperY, 19, "area interior y")
eq(A.upperH, 122, "area interior height")

print("[test] 3. composeCard blits a cached tile sheet through the tilemap")
local function synthetic_sheet(tag)
  local px = {}
  for sy = 0, 31 do
    for sx = 0, 63 do
      local tile = math.floor(sy / 8) * 8 + math.floor(sx / 8)
      px[#px + 1] = string.char(tile, sx % 8 + tag, sy % 8, 255)
    end
  end
  return table.concat(px)
end
local sheet = synthetic_sheet(0)
local card = PokedexChrome.composeCard(L, sheet)
check(type(card) == "string" and #card == 240 * 160 * 4, "data card is 240x160 RGBA")
local function at(buf, x, y)
  local o = (y * 240 + x) * 4
  return buf:byte(o + 1), buf:byte(o + 2), buf:byte(o + 3), buf:byte(o + 4)
end
local function px_eq(buf, x, y, t, sx, sy, msg)
  local r, gch, b, a = at(buf, x, y)
  check(r == t and gch == sx and b == sy and a == 255,
    string.format("%s (%d,%d) = tile %s px %s,%s", msg, x, y, tostring(r), tostring(gch), tostring(b)))
end
px_eq(card, 5, 3, 0, 5, 3, "backdrop above the card is tile 0")
px_eq(card, 100, 155, 0, 4, 3, "backdrop below the card is tile 0")
px_eq(card, 1, 18, 4, 1, 2, "top-left corner")
px_eq(card, 233, 18, 4, 6, 2, "top-right corner is mirrored")
px_eq(card, 42, 17, 5, 2, 1, "top edge")
px_eq(card, 42, 30, 1, 2, 6, "upper interior")
px_eq(card, 42, 89, 8, 2, 1, "divider row")
px_eq(card, 42, 100, 2, 2, 4, "lower interior")
px_eq(card, 3, 90, 7, 3, 2, "left edge at divider")
px_eq(card, 236, 90, 7, 3, 2, "right edge at divider is mirrored")
px_eq(card, 2, 138, 10, 2, 2, "bottom-left corner")
px_eq(card, 42, 141, 11, 2, 5, "bottom edge")

local areaCard = PokedexChrome.composeCard(A, sheet)
px_eq(areaCard, 42, 89, 1, 2, 1, "area card has no divider row")
px_eq(areaCard, 1, 138, 4, 1, 5, "area bottom-left corner is tile 4 upside down")
px_eq(areaCard, 233, 138, 4, 6, 5, "area bottom-right corner is tile 4 rotated")
px_eq(areaCard, 42, 141, 5, 2, 2, "area bottom edge is tile 5 upside down")

print("[test] 4. Missing or short sheet composes nothing, sheet follows the dex mode")
eq(PokedexChrome.composeCard(L, nil), nil, "no sheet, no card")
eq(PokedexChrome.composeCard(L, "short"), nil, "truncated sheet, no card")
local PokedexData = require("src.core.game3.pokedex_data")
local realUnlocked = PokedexData.isNationalUnlocked
local natSheet = synthetic_sheet(100)
PokedexChrome._installed = true
PokedexChrome._sheets = {}
eq((PokedexChrome.cardSheet()), nil, "cache without the asset yields no sheet")
PokedexChrome._sheets = { kanto = sheet, national = natSheet }
PokedexData.isNationalUnlocked = function() return false end
eq(select(2, PokedexChrome.cardSheet()), "kanto", "kanto dex uses the kanto sheet")
PokedexData.isNationalUnlocked = function() return true end
eq(select(2, PokedexChrome.cardSheet()), "national", "national dex uses the national sheet")
PokedexChrome._sheets = { kanto = sheet }
eq(select(2, PokedexChrome.cardSheet()), "kanto", "national dex without its sheet falls back to kanto")
PokedexData.isNationalUnlocked = realUnlocked

local drawn = { rectangle = 0, draw = 0 }
PokedexChrome._sheets = {}
love = { graphics = {
  setColor = function() end,
  rectangle = function() drawn.rectangle = drawn.rectangle + 1 end,
  draw = function() drawn.draw = drawn.draw + 1 end,
} }
local okFallback = pcall(PokedexChrome.drawDataCardBg)
love = nil
check(okFallback, "drawDataCardBg survives a cache without the asset")
check(drawn.rectangle > 0 and drawn.draw == 0, "missing asset falls back to the paper background")
PokedexChrome._installed = false

print("[test] 4b. Importer bakes a 4bpp sheet the UI can read back")
local Extractor = require("src.import.gba.pokedex_chrome_extract")
local gfx = {}
for i = 1, 64 do gfx[i] = 0 end
gfx[33] = 0x21
local bakedPal = { [0] = 0, [1] = 0x001F, [2] = 0x03E0 }
local baked, bw, bh = Extractor.bakeTileSheet(gfx, bakedPal)
eq(bw, 64, "baked sheet is 8 tiles wide")
eq(bh, 8, "two tiles bake to one row")
eq(#baked, 64 * 8 * 4, "baked sheet is RGBA")
eq(baked:sub(8 * 4 + 1, 8 * 4 + 4), string.char(255, 0, 0, 255), "low nibble is the left pixel")
eq(baked:sub(9 * 4 + 1, 9 * 4 + 4), string.char(0, 255, 0, 255), "high nibble is the right pixel")
eq(baked:sub(1, 4), string.char(0, 0, 0, 255), "index 0 is opaque backdrop")
local Versions = require("src.import.gba.versions")
check(type(Versions.POKEDEX_BG_TILES) == "table"
  and Versions.POKEDEX_BG_TILES.kanto and Versions.POKEDEX_BG_TILES.national, "both dex sheets have ROM offsets")
local fake = {}
local fakeCache = { read = function(_, rel) return fake[rel] end }
for _, f in ipairs({ "manifest.lua", "entries.lua", "categories.lua", "orders.lua", "area_markers.lua" }) do
  fake["root/pokemon/pokedex/" .. f] = string.rep("x", 32)
end
eq(Extractor.ready(fakeCache, "root"), false, "a cache without the tile sheets is not ready")
fake["root/pokemon/pokedex/dex_tiles_kanto.rgba"] = string.rep("x", 64)
fake["root/pokemon/pokedex/dex_tiles_national.rgba"] = string.rep("x", 64)
for _, f in ipairs({ Extractor.CHROME_FILE, "map_kanto.rgba", "mini_page.rgba",
  "blit_wide_ellipse.rgba", "marker_0.rgba", "cat_icon_grassland.rgba" }) do
  fake["root/pokemon/pokedex/" .. f] = string.rep("x", 64)
end
eq(Extractor.ready(fakeCache, "root"), false, "a cache without the dex page assets is not ready")
fake["root/pokemon/pokedex/" .. Extractor.PAPER_BG_FILE] =
  string.rep("x", Extractor.PAPER_BG_W * Extractor.PAPER_BG_H * 4)
for _, f in ipairs({ "1.rgba", "bulbasaur.rgba", Extractor.FOOTPRINT_QUESTION_MARK_FILE }) do
  fake["root/pokemon/pokedex/" .. Extractor.FOOTPRINT_SUB .. "/" .. f] =
    string.rep("x", Extractor.FOOTPRINT_W * Extractor.FOOTPRINT_H * 4)
end
eq(Extractor.ready(fakeCache, "root"), true, "tile sheets and chrome graphics complete the cache")

print("[test] 5. Data card tilemap lays the pret tiles")
local g = PokedexChrome.cardTilemap(L)
eq(g[2][0].tile, 4, "top-left corner tile")
eq(g[2][29].tile, 4, "top-right corner tile")
check(g[2][29].flipH == true, "top-right corner is H-flipped")
eq(g[2][1].tile, 5, "top edge tile")
eq(g[17][0].tile, 10, "bottom-left corner tile")
eq(g[17][1].tile, 11, "bottom edge tile")
eq(g[3][0].tile, 6, "left edge above divider")
eq(g[10][0].tile, 6, "left edge still above divider at row 10")
eq(g[11][0].tile, 7, "left edge at divider")
eq(g[12][0].tile, 9, "left edge below divider")
eq(g[16][0].tile, 9, "left edge below divider at last interior row")
check(g[11][29].flipH == true, "right edge at divider is H-flipped")
eq(g[3][1].tile, 1, "upper interior tile")
eq(g[11][1].tile, 8, "divider interior tile")
eq(g[12][1].tile, 2, "lower interior tile")
eq(g[1], nil, "nothing drawn above the card")
eq(g[18], nil, "nothing drawn below the card")

print("[test] 6. Area card tilemap uses flipped tile 4/5 edges and one interior")
local ga = PokedexChrome.cardTilemap(A)
eq(ga[17][0].tile, 4, "area bottom-left corner is tile 4")
check(ga[17][0].flipV == true, "area bottom-left corner is V-flipped")
check(ga[17][29].flipH == true and ga[17][29].flipV == true, "area bottom-right corner is HV-flipped")
eq(ga[17][1].tile, 5, "area bottom edge is tile 5")
check(ga[17][1].flipV == true, "area bottom edge is V-flipped")
eq(ga[11][1].tile, 1, "area interior is unbroken at the data card's divider row")
eq(ga[16][1].tile, 1, "area interior runs to the last row")
eq(ga[3][0].tile, 6, "area left edge")

end

print("[test] 7. Card draws are love-free no-ops headless")
check(love == nil, "no love in this harness")
check(pcall(PokedexChrome.drawDataCardBg), "drawDataCardBg is safe without love")
check(pcall(PokedexChrome.drawAreaCardBg), "drawAreaCardBg is safe without love")

print("[test] 8. Control info matches DexScreen_DrawMonDexPage(justRegistered)")
check(type(Pokedex.controlInfoForDataPage) == "function", "Pokedex.controlInfoForDataPage present")
if type(Pokedex.controlInfoForDataPage) == "function" then
  local regCry, regInfo = Pokedex.controlInfoForDataPage("registration")
  eq(regCry, nil, "registration prints no CRY hint")
  eq(regInfo, "{A_BUTTON}NEXT", "registration prints gText_Next")
  local dataCry, dataInfo = Pokedex.controlInfoForDataPage("data")
  eq(dataCry, "{START_BUTTON}CRY", "browse prints gText_Cry")
  eq(dataInfo, "{A_BUTTON}NEXT DATA {B_BUTTON}CANCEL", "browse prints gText_NextDataCancel")
end

print("[test] 9. Species map to their own habitat category page")
check(type(Pokedex.categoryForSpecies) == "function", "Pokedex.categoryForSpecies present")
if type(Pokedex.categoryForSpecies) == "function" then
  eq(Pokedex.categoryForSpecies(19), "grassland", "Rattata is a grassland mon")
  eq(Pokedex.categoryForSpecies(10), "forest", "Caterpie is a forest mon")
  eq(Pokedex.categoryForSpecies(41), "cave", "Zubat is a cave mon")
  eq(Pokedex.categoryForSpecies(144), "rare", "Articuno is a rare mon")
end

print("[test] 10. Registration close runs _onClose once and plays no SE")
local calls = 0
playedSe = {}
Pokedex.showRegistration(19, { onDone = function() calls = calls + 1 end })
eq(Pokedex.screen, "registration", "screen is registration")
eq(Pokedex.subScreenPrev, "category_grid", "header comes from the category page")
eq(Pokedex.currentCategory, "grassland", "header category is the species' habitat")
eq(Pokedex._onDone, nil, "no dead _onDone field is set")
check(type(Pokedex._onClose) == "function", "_onClose holds the callback")

local pressed = {}
local fakeInput = { wasPressed = function(_, b) return pressed[b] == true end }
pressed.a = true
Pokedex.handleInput(fakeInput)
eq(calls, 1, "A on the registration card fires the callback once")
eq(Pokedex.open, false, "registration card closed")
pressed.a = false
Pokedex.handleInput(fakeInput)
eq(calls, 1, "callback is not fired twice")

for _, id in ipairs(playedSe) do
  check(id ~= SE.SE_FLEE, "close did not play SE_FLEE (pokedex_screen.c:1045)")
end
check(#playedSe == 0, "close plays no SE at all (" .. #playedSe .. " played)")

print("")
if failed > 0 then
  print("FAILED: " .. failed)
  os.exit(1)
end
print("ALL PASS")
