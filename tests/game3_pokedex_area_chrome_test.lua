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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playCry = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local Cache = require("tests.game3_cache")
local Versions = require("src.import.gba.versions")
local Extract = require("src.import.gba.pokedex_chrome_extract")
local PokedexChrome = require("src.ui.game3.pokedex_chrome")
local Pokedex = require("src.ui.game3.pokedex")

print("[test] 1. versions.lua carries the area-page / size-page ROM offsets")
check(Versions.CACHE_VERSION >= 103, "CACHE_VERSION at or past the dex chrome import ("
  .. tostring(Versions.CACHE_VERSION) .. ")")
eq(Extract.FORMAT_VERSION, 5, "pokedex FORMAT_VERSION bumped")

local gfxByFile = {}
for _, g in ipairs(Versions.POKEDEX_CHROME_GFX or {}) do gfxByFile[g.file] = g end
check(gfxByFile["map_kanto.rgba"] ~= nil, "map_kanto.rgba is extracted")
if gfxByFile["map_kanto.rgba"] then
  local g = gfxByFile["map_kanto.rgba"]
  -- pokefirered/src/pokedex_screen.c:678
  eq(g.w, 96, "kanto map is 96 px wide")
  eq(g.h, 72, "kanto map is 72 px tall")
  eq(g.gfx, 0x443620, "kanto map comes from sTilemap_AreaMap_Kanto")
  eq(g.lz, true, "kanto map is LZ77")
end
for _, name in ipairs({ "one", "two", "three" }) do
  local g = gfxByFile["map_" .. name .. "_island.rgba"]
  check(g and g.w == 32 and g.h == 24, "map_" .. name .. "_island is 32x24")
end
for _, name in ipairs({ "four", "five", "six", "seven" }) do
  local g = gfxByFile["map_" .. name .. "_island.rgba"]
  check(g and g.w == 32 and g.h == 32, "map_" .. name .. "_island is 32x32")
end
-- pokefirered/src/pokedex_screen.c:3133
check(gfxByFile["blit_wide_ellipse.rgba"] ~= nil, "AREA UNKNOWN ellipse is extracted")
if gfxByFile["blit_wide_ellipse.rgba"] then
  local g = gfxByFile["blit_wide_ellipse.rgba"]
  check(g.w == 88 and g.h == 16 and not g.lz, "wide ellipse is a raw 88x16 4bpp blit")
end
check(gfxByFile["mini_page.rgba"] ~= nil, "mini_page is extracted")
check(gfxByFile["caught_marker.rgba"] ~= nil, "caught_marker is extracted")
eq(#(Versions.POKEDEX_CATEGORY_ICONS or {}), 16, "all 16 category icons have offsets")
eq(Versions.POKEDEX_SILHOUETTE_PAL, 0x452368, "sPalette_Silhouette offset present")
-- pokefirered/src/pokedex_area_markers.c:219
eq(Versions.POKEDEX_MARKER_BLEND_EVA, 12, "BLDALPHA eva")
eq(Versions.POKEDEX_MARKER_BLEND_EVB, 8, "BLDALPHA evb")

-- pokefirered/src/pokedex_area_markers.c:41
local shapes = Versions.POKEDEX_AREA_MARKER_SHAPES or {}
eq(#shapes, 7, "seven area marker shapes")
local wantShapes = {
  { 0, 8, 8 }, { 1, 16, 8 }, { 3, 8, 16 }, { 5, 32, 16 },
  { 13, 16, 32 }, { 21, 32, 16 }, { 29, 16, 32 },
}
for i, w in ipairs(wantShapes) do
  local s = shapes[i]
  check(s and s.tile == w[1] and s.w == w[2] and s.h == w[3],
    string.format("marker shape %d is tile %d, %dx%d", i - 1, w[1], w[2], w[3]))
end

print("[test] 2. bakeImage turns 4bpp tiles into RGBA with a transparent index 0")
check(type(Extract.bakeImage) == "function", "Extract.bakeImage present")
if type(Extract.bakeImage) == "function" then
  local tile = {}
  for i = 1, 32 do tile[i] = 0x11 end
  tile[1] = 0x10
  local pal = {}
  for i = 0, 15 do pal[i] = 0 end
  pal[0] = 0x7FFF
  pal[1] = 0x001F
  local out = Extract.bakeImage(tile, pal, 8, 8)
  eq(#out, 8 * 8 * 4, "8x8 tile bakes to 256 RGBA bytes")
  eq(out:byte(4), 0, "index 0 is transparent")
  eq(out:byte(5), 255, "index 1 red channel is the palette color")
  eq(out:byte(8), 255, "index 1 is opaque")

  local opaque = Extract.bakeImage(tile, pal, 8, 8, { opaqueZero = true })
  eq(opaque:byte(4), 255, "opaqueZero keeps index 0 visible")
  eq(opaque:byte(1), 255, "opaqueZero index 0 uses the palette color")

  local mask = Extract.bakeImage(tile, pal, 8, 8, { mask = true })
  eq(mask:byte(4), 0, "mask index 0 is transparent")
  eq(mask:byte(5), 255, "mask non-zero index is white")
  eq(mask:byte(8), 255, "mask non-zero index is opaque")

  local two = {}
  for i = 1, 64 do two[i] = (i <= 32) and 0x00 or 0x11 end
  local second = Extract.bakeImage(two, pal, 8, 8, { tile0 = 1, mask = true })
  eq(second:byte(8), 255, "tile0=1 reads the second tile")
  local first = Extract.bakeImage(two, pal, 8, 8, { tile0 = 0, mask = true })
  eq(first:byte(4), 0, "tile0=0 reads the first tile")
end

print("[test] 3. ready() gates on the new area-page assets")
local files = {}
local fakeCache = {
  read = function(_, rel) return files[rel] end,
}
local root = "R/" .. Extract.CACHE_SUB
local base = {
  "manifest.lua", "entries.lua", "categories.lua", "orders.lua", "area_markers.lua",
  Extract.TILE_SHEETS.kanto, Extract.TILE_SHEETS.national,
}
for _, f in ipairs(base) do files[root .. "/" .. f] = string.rep("x", 4096) end
check(Extract.ready(fakeCache, "R") == false, "ready() is false without the chrome graphics")
for _, f in ipairs({ Extract.CHROME_FILE, "map_kanto.rgba", "mini_page.rgba",
  "blit_wide_ellipse.rgba", "marker_0.rgba", "cat_icon_grassland.rgba" }) do
  files[root .. "/" .. f] = string.rep("x", 4096)
end
check(Extract.ready(fakeCache, "R") == false, "ready() is false without the dex page assets")
files[root .. "/" .. Extract.PAPER_BG_FILE] =
  string.rep("x", Extract.PAPER_BG_W * Extract.PAPER_BG_H * 4)
for _, f in ipairs({ "1.rgba", "bulbasaur.rgba", Extract.FOOTPRINT_QUESTION_MARK_FILE }) do
  files[root .. "/" .. Extract.FOOTPRINT_SUB .. "/" .. f] =
    string.rep("x", Extract.FOOTPRINT_W * Extract.FOOTPRINT_H * 4)
end
check(Extract.ready(fakeCache, "R") == true, "ready() is true once they are present")

print("[test] 4. PokedexChrome reads the ROM-derived chrome colors")
check(type(PokedexChrome.getColor) == "function", "PokedexChrome.getColor present")
if type(PokedexChrome.getColor) == "function" then
  PokedexChrome._installed = true
  PokedexChrome._colors = nil
  eq(PokedexChrome.getColor("marker"), nil, "no chrome.lua means no color")
  PokedexChrome._colors = { marker = { 10, 20, 30, 40 }, silhouette = { 50, 60, 70 } }
  local r, g, b, a = PokedexChrome.getColor("marker")
  eq(math.floor(r * 255 + 0.5), 10, "marker red")
  eq(math.floor(g * 255 + 0.5), 20, "marker green")
  eq(math.floor(b * 255 + 0.5), 30, "marker blue")
  eq(math.floor(a * 255 + 0.5), 40, "marker alpha passes through")
  local sr, _, _, sa = PokedexChrome.getColor("silhouette")
  eq(math.floor(sr * 255 + 0.5), 50, "silhouette grey")
  eq(sa, 1, "silhouette has no alpha entry")
  check(type(PokedexChrome.getMarkerBlend) == "function", "PokedexChrome.getMarkerBlend present")
  if type(PokedexChrome.getMarkerBlend) == "function" then
    eq(PokedexChrome.getMarkerBlend(), nil, "no marker_blend entry means no blend pair")
    PokedexChrome._colors.marker_blend = { 4, 2 }
    local eva, evb = PokedexChrome.getMarkerBlend()
    eq(eva, 4 / 16, "eva is sixteenths")
    eq(evb, 2 / 16, "evb is sixteenths")
  end
  PokedexChrome._colors = nil
end

print("[test] 5. Size comparison uses both pret sprites")
-- pokefirered/src/trainer_pokemon_sprites.c:276, include/constants/trainers.h:156
check(type(PokedexChrome.TRAINER_PIC_IDS) == "table", "trainer pic ids present")
if type(PokedexChrome.TRAINER_PIC_IDS) == "table" then
  eq(PokedexChrome.TRAINER_PIC_IDS.male, 135, "TRAINER_PIC_RED")
  eq(PokedexChrome.TRAINER_PIC_IDS.female, 136, "TRAINER_PIC_LEAF")
end
-- pokefirered/src/pokedex_screen.c:3113
check(type(Pokedex.silhouetteScale) == "function", "Pokedex.silhouetteScale present")
if type(Pokedex.silhouetteScale) == "function" then
  eq(Pokedex.silhouetteScale(256), 1, "scale 256 draws 1:1")
  eq(Pokedex.silhouetteScale(512), 0.5, "scale 512 draws at half size")
  eq(Pokedex.silhouetteScale(128), 2, "scale 128 draws at double size")
  eq(Pokedex.silhouetteScale(0), 1, "scale 0 falls back to 1:1")
  eq(Pokedex.silhouetteScale(nil), 1, "missing scale falls back to 1:1")
end
check(type(Pokedex.playerGender) == "function", "Pokedex.playerGender present")
if type(Pokedex.playerGender) == "function" then
  Pokedex._session = nil
  eq(Pokedex.playerGender(), "male", "no session defaults to RED")
  Pokedex._session = { gender = 1 }
  eq(Pokedex.playerGender(), "female", "gender 1 is LEAF")
  Pokedex._session = { gender = "female" }
  eq(Pokedex.playerGender(), "female", "gender \"female\" is LEAF")
  Pokedex._session = { gender = 0 }
  eq(Pokedex.playerGender(), "male", "gender 0 is RED")
  Pokedex._session = nil
end

print("[test] 6. Registration closes on A or B only (pokedex_screen.c:3427)")
local pressed = {}
local fakeInput = { wasPressed = function(_, b) return pressed[b] == true end }

local calls = 0
Pokedex.showRegistration(19, { onDone = function() calls = calls + 1 end })
eq(Pokedex.screen, "registration", "registration screen open")
pressed.start = true
Pokedex.handleInput(fakeInput)
eq(calls, 0, "START does not close the registration card")
eq(Pokedex.open, true, "registration card still open after START")
pressed.start = false
pressed.select = true
Pokedex.handleInput(fakeInput)
eq(calls, 0, "SELECT does not close the registration card")
pressed.select = false
pressed.b = true
Pokedex.handleInput(fakeInput)
eq(calls, 1, "B closes the registration card")
eq(Pokedex.open, false, "registration card closed on B")
pressed.b = false

calls = 0
Pokedex.showRegistration(19, { onDone = function() calls = calls + 1 end })
pressed.a = true
Pokedex.handleInput(fakeInput)
eq(calls, 1, "A closes the registration card")
pressed.a = false

print("[test] 7. Imported cache holds the area-page graphics")
local cacheRoot = Cache.root("meta.json")
if not cacheRoot then
  print("[skip] no FireRed cache mounted")
else
  local dexRoot = cacheRoot .. "/pokemon/pokedex"
  local function slurp(rel)
    local f = io.open(dexRoot .. "/" .. rel, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
  end
  local kanto = slurp("map_kanto.rgba")
  if not kanto then
    print("[skip] cache predates the dex chrome import (CACHE_VERSION < 103)")
  else
    eq(#kanto, 96 * 72 * 4, "map_kanto.rgba is a 96x72 RGBA buffer")
    local opaque = 0
    for i = 4, #kanto, 4 do
      if kanto:byte(i) ~= 0 then opaque = opaque + 1 end
    end
    check(opaque > 1000, "map_kanto.rgba has real opaque pixels (" .. opaque .. ")")
    local ellipse = slurp("blit_wide_ellipse.rgba")
    check(ellipse and #ellipse == 88 * 16 * 4, "blit_wide_ellipse.rgba is 88x16")
    local marker = slurp("marker_0.rgba")
    check(marker and #marker == 8 * 8 * 4, "marker_0.rgba is 8x8")
    if marker then
      local hit = false
      for i = 4, #marker, 4 do
        if marker:byte(i) == 255 then
          hit = true
          eq(marker:byte(i - 3), 255, "marker mask pixels are white")
          break
        end
      end
      check(hit, "marker_0.rgba has an opaque mask")
    end
    local chrome = slurp(Extract.CHROME_FILE)
    check(chrome ~= nil, "chrome.lua present in the cache")
    if chrome then
      local tbl = assert(loadstring(chrome))()
      eq(type(tbl.marker), "table", "chrome.lua carries the marker blend color")
      eq(tbl.marker[4], 191, "marker alpha is 12/16")
      eq(type(tbl.marker_blend), "table", "chrome.lua carries the BLDALPHA pair")
      if type(tbl.marker_blend) == "table" then
        eq(tbl.marker_blend[1], Versions.POKEDEX_MARKER_BLEND_EVA, "marker_blend eva")
        eq(tbl.marker_blend[2], Versions.POKEDEX_MARKER_BLEND_EVB, "marker_blend evb")
      end
      eq(type(tbl.silhouette), "table", "chrome.lua carries the silhouette color")
    end
    local icon = slurp("cat_icon_grassland.rgba")
    check(icon and #icon == 64 * 48 * 4, "cat_icon_grassland.rgba is 64x48")
    local mini = slurp("mini_page.rgba")
    check(mini and #mini == 64 * 40 * 4, "mini_page.rgba is 64x40")
  end
end

print("")
if failed > 0 then
  print("FAILED: " .. failed)
  os.exit(1)
end
print("ALL PASS")
