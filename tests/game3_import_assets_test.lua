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

local PokemonExtract = require("src.import.gba.pokemon_extract")
local TextChrome = require("src.import.gba.text_chrome_extract")
local Seagallop = require("src.import.gba.seagallop_extract")
local BattleChrome = require("src.import.gba.battle_chrome_extract")
local CacheContract = require("src.import.CacheContract")
local Versions = require("src.import.gba.versions")

local function fakeRom(str)
  return {
    size = #str,
    get = function(_, off) return str:byte(off + 1) or 0 end,
    readBytes = function(_, off, len)
      local out = {}
      for i = 0, len - 1 do out[i + 1] = str:byte(off + i + 1) or 0 end
      return out
    end,
  }
end

print("[test] 1. safariZoneFleeRate rides the base-stats row")
-- include/pokemon.h:233
check(Versions.SPECIES_INFO_SIZE >= 0x19,
  "the SpeciesInfo stride covers offset 0x18 (" .. tostring(Versions.SPECIES_INFO_SIZE) .. ")")
check(PokemonExtract.FORMAT_VERSION >= 6,
  "the pokemon pack format version is bumped for the flee rate ("
    .. tostring(PokemonExtract.FORMAT_VERSION) .. ")")

print("[test] 2. the braille font decodes at the pret addressing")
-- src/braille_text.c:15
check(TextChrome.BRAILLE_GFX == 0x46FB0C, "sBrailleGlyphs is at 0x46FB0C")
check(TextChrome.BRAILLE_GLYPHS == 64, "the braille font has 64 glyphs")

do
  -- src/braille_text.c:333
  local probes = {
    { gid = 0, part = 0 },
    { gid = 1, part = 0 },
    { gid = 7, part = 0 },
    { gid = 8, part = 0 },
    { gid = 63, part = 0 },
    { gid = 9, part = 16 },
    { gid = 9, part = 256 },
    { gid = 9, part = 272 },
  }
  for _, probe in ipairs(probes) do
    local off = 512 * math.floor(probe.gid / 8) + 32 * (probe.gid % 8) + probe.part
    local bytes = {}
    for i = 1, 4096 do bytes[i] = "\0" end
    for i = 1, 16 do bytes[off + i] = string.char(0x55) end
    local rom = fakeRom(("\0"):rep(TextChrome.BRAILLE_GFX) .. table.concat(bytes))
    local sheet = TextChrome.extractBraille(rom)
    check(sheet.width == 256 and sheet.height == 64,
      "the braille sheet is 256x64 (" .. sheet.width .. "x" .. sheet.height .. ")")
    local ox = (probe.gid % 16) * 16 + ((probe.part == 16 or probe.part == 272) and 8 or 0)
    local oy = math.floor(probe.gid / 16) * 16 + (probe.part >= 256 and 8 or 0)
    local lit, total = 0, 0
    for y = 0, 63 do
      for x = 0, 255 do
        if sheet.fgRgba:byte((y * 256 + x) * 4 + 4) == 255 then
          total = total + 1
          if x >= ox and x < ox + 8 and y >= oy and y < oy + 8 then lit = lit + 1 end
        end
      end
    end
    check(lit == 64 and total == 64,
      string.format("glyph %d quarter +%d lands at (%d,%d) alone (%d/%d)",
        probe.gid, probe.part, ox, oy, lit, total))
  end
end

print("[test] 3. the seagallop blobs are the pret INCBIN run")
-- src/seagallop.c:41
local EXPECT_BLOBS = {
  { "water.4bpp", 0x468C98, 1312 },
  { "water.gbapal", 0x4691B8, 32 },
  { "wb_tilemap.bin", 0x4691D8, 2048 },
  { "eb_tilemap.bin", 0x4699D8, 2048 },
  { "ferry.4bpp", 0x46A1D8, 1280 },
  { "ferry_wake.gbapal", 0x46A6D8, 32 },
  { "wake.4bpp", 0x46A6F8, 2048 },
}
check(#Seagallop.BLOBS == #EXPECT_BLOBS,
  "seven blobs are declared (" .. #Seagallop.BLOBS .. ")")
for i, want in ipairs(EXPECT_BLOBS) do
  local got = Seagallop.BLOBS[i]
  check(got ~= nil and got.rel == want[1] and got.offset == want[2] and got.size == want[3],
    string.format("blob %d is %s at 0x%X, %d bytes", i, want[1], want[2], want[3]))
end
do
  local prev = nil
  local contiguous = true
  for _, blob in ipairs(Seagallop.BLOBS) do
    if prev and prev ~= blob.offset then contiguous = false end
    prev = blob.offset + blob.size
  end
  check(contiguous, "the blobs are one contiguous run inside src/seagallop.o(.rodata)")
end
check(Seagallop.MAP_W == 32 and Seagallop.MAP_H == 32,
  "the water tilemaps are 32x32 entries")

local seagallopRomBytes
do
  local romLen = 0x46B000
  local parts = {}
  for i = 1, romLen do parts[i] = "\0" end
  for i, blob in ipairs(Seagallop.BLOBS) do
    for j = 1, blob.size do parts[blob.offset + j] = string.char(i) end
  end
  seagallopRomBytes = table.concat(parts)
  local blobs = Seagallop.readBlobs(fakeRom(seagallopRomBytes))
  for i, blob in ipairs(Seagallop.BLOBS) do
    local data = blobs[blob.key]
    check(type(data) == "string" and #data == blob.size
      and data == string.char(i):rep(blob.size),
      blob.rel .. " is read from its own offset")
  end
end

do
  local written = {}
  local refusing = {
    write = function(_, rel, data)
      if rel:find("manifest%.lua$") then return false, "read-only cache" end
      written[rel] = #data
      return true
    end,
  }
  local ok, err = pcall(Seagallop.run, fakeRom(seagallopRomBytes), refusing,
    { cacheRoot = "data/generated/gba" })
  check(ok == false and tostring(err):find("could not write") ~= nil,
    "a refused seagallop write aborts the bake instead of publishing a half cache")
  check(written["data/generated/gba/seagallop/water.4bpp"] == Seagallop.BLOBS[1].size,
    "the blobs before the refused write did reach the cache")
end

print("[test] 4. the 4bpp seagallop art decodes through the real baker")
do
  local t0 = string.char(0x11):rep(32)
  local t1 = (string.char(0x22, 0x22, 0x00, 0x00)):rep(8)
  local pal = string.char(0, 0) .. string.char(0x1F, 0x00) .. string.char(0xE0, 0x03)
    .. string.char(0, 0):rep(13)
  local rgba, w, h, tiles = Seagallop.bakeSheet(t0 .. t1, pal, 2)
  check(w == 16 and h == 8 and tiles == 2, "two tiles at two columns bake 16x8")
  local function px(x, y)
    local o = (y * w + x) * 4
    return rgba:byte(o + 1), rgba:byte(o + 2), rgba:byte(o + 3), rgba:byte(o + 4)
  end
  local r, g, b, a = px(0, 0)
  check(r == 255 and g == 0 and b == 0 and a == 255, "colour 1 is the first palette entry")
  r, g, b, a = px(8, 0)
  check(r == 0 and g == 255 and b == 0 and a == 255, "colour 2 is the second palette entry")
  r, g, b, a = px(12, 0)
  check(a == 0, "colour 0 stays transparent in a sprite sheet")

  local map = {}
  for i = 1, 4 do map[i] = "\0" end
  map[1] = string.char(0x01)
  map[2] = string.char(0x04)
  map[3] = string.char(0x01)
  map[4] = string.char(0x00)
  local bg, bw, bh = Seagallop.bakeTilemap(t0 .. t1, pal, table.concat(map), 2, 1)
  check(bw == 16 and bh == 8, "a 2x1 tilemap bakes 16x8")
  local function bpx(x, y)
    local o = (y * bw + x) * 4
    return bg:byte(o + 1), bg:byte(o + 2), bg:byte(o + 3), bg:byte(o + 4)
  end
  r, g, b, a = bpx(7, 0)
  check(r == 0 and g == 255 and b == 0 and a == 255,
    "entry 0 draws tile 1 hflipped, its coloured half on the right")
  r, g, b, a = bpx(0, 0)
  check(a == 255 and r == 0 and g == 0 and b == 0,
    "the hflip moved colour 0 to the left edge")
  r, g, b, a = bpx(8, 0)
  check(r == 0 and g == 255 and b == 0 and a == 255, "entry 1 draws tile 1 unflipped")
  r, g, b, a = bpx(15, 0)
  check(a == 255, "colour 0 is opaque in a background layer")
end

print("[test] 5. the contract requires the new keys")
local required = {}
for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.firered) do
  required[path] = true
end
local NEW_KEYS = {
  "data/generated/gba/chrome/fonts/braille_fg.rgba",
  "data/generated/gba/chrome/fonts/braille_shadow.rgba",
  "data/generated/gba/chrome/fonts/braille.lua",
  "data/generated/gba/seagallop/manifest.lua",
  "data/generated/gba/seagallop/water.4bpp",
  "data/generated/gba/seagallop/ferry.4bpp",
  "data/generated/gba/seagallop/wake.4bpp",
  "data/generated/gba/seagallop/wb_tilemap.bin",
  "data/generated/gba/seagallop/eb_tilemap.bin",
  "data/generated/gba/seagallop/wb.rgba",
  "data/generated/gba/seagallop/eb.rgba",
  "data/generated/gba/pokemon/battle/terrain_grass.rgba",
  "data/generated/gba/pokemon/battle/terrain_cave.rgba",
  "data/generated/gba/pokemon/battle/terrain_water.rgba",
  "data/generated/gba/pokemon/battle/terrain_champion.rgba",
  "data/generated/gba/pokemon/battle/terrain_bg_cave.rgba",
}
for _, path in ipairs(NEW_KEYS) do
  check(required[path] == true, "the firered contract requires " .. path)
  local fs = {
    getInfo = function(candidate) return candidate ~= path and { type = "file" } or nil end,
    exists = function(candidate) return candidate ~= path end,
  }
  local complete, missing = CacheContract.allRequiredFilesExist("firered", fs)
  check(complete == false and missing == path,
    "a cache without " .. path .. " is incomplete (" .. tostring(missing) .. ")")
end

print("[test] 6. every sBattleTerrainTable id is a contract-visible key")
do
  local keys = {}
  for id = 0, 19 do keys[id] = BattleChrome.TERRAIN_KEYS[id] end
  check(keys[7] == "cave" and keys[4] == "water" and keys[19] == "champion",
    "the terrain key list still names cave, water and champion")
end

print("[test] 7. a built cache carries the baked assets")
local Cache = require("tests.game3_cache")
local root = Cache.root("pokemon/manifest.lua")
if not root then
  print("[skip] baked import assets: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. root)

local function readFile(rel)
  local f = io.open(root .. "/" .. rel, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local pokeManifest = readFile("pokemon/manifest.lua")
local pm = pokeManifest and loadstring(pokeManifest)
pm = pm and pm()
if type(pm) ~= "table" or (tonumber(pm.format) or 0) < 6 then
  print("[skip] baked import assets: pokemon manifest is format "
    .. tostring(pm and pm.format) .. ", these assets need 6")
  finish()
end

do
  local metaSrc = readFile("pokemon/meta.lua")
  local meta = metaSrc and loadstring(metaSrc)
  meta = meta and meta()
  check(type(meta) == "table", "pokemon/meta.lua loads")
  if type(meta) == "table" then
    local seen, missing, outOfRange, nonZero = 0, 0, 0, 0
    local values = {}
    for _, row in pairs(meta) do
      seen = seen + 1
      local v = row.safariZoneFleeRate
      if v == nil then
        missing = missing + 1
      elseif type(v) ~= "number" or v < 0 or v > 255 or v % 1 ~= 0 then
        outOfRange = outOfRange + 1
      elseif v > 0 then
        nonZero = nonZero + 1
        values[v] = (values[v] or 0) + 1
      end
    end
    check(seen >= (Versions.NUM_SPECIES or 412) - 1,
      "every species has a meta row (" .. seen .. ")")
    check(missing == 0, "every meta row carries safariZoneFleeRate (" .. missing .. " missing)")
    check(outOfRange == 0, "every flee rate is a byte in 0..255 (" .. outOfRange .. " bad)")
    -- src/data/pokemon/species_info.h:30
    local EXPECT_COUNTS = { [25] = 1, [50] = 9, [75] = 7, [100] = 1, [125] = 6 }
    local wrong = {}
    for v, n in pairs(values) do
      if EXPECT_COUNTS[v] ~= n then
        wrong[#wrong + 1] = string.format("%d x%d", v, n)
      end
    end
    for v, n in pairs(EXPECT_COUNTS) do
      if values[v] == nil then wrong[#wrong + 1] = string.format("%d missing (want %d)", v, n) end
    end
    check(#wrong == 0,
      "the nonzero flee rates are the pret histogram (" .. table.concat(wrong, ", ") .. ")")
    check(nonZero == 24,
      "24 species carry a Safari Zone flee rate (" .. nonZero .. ")")
  end
end

do
  local fg = readFile("chrome/fonts/braille_fg.rgba")
  local sh = readFile("chrome/fonts/braille_shadow.rgba")
  local metaSrc = readFile("chrome/fonts/braille.lua")
  local meta = metaSrc and loadstring(metaSrc)
  meta = meta and meta()
  check(fg ~= nil and #fg == 256 * 64 * 4,
    "braille_fg.rgba is 256x64 (" .. tostring(fg and #fg) .. ")")
  check(sh ~= nil and #sh == 256 * 64 * 4,
    "braille_shadow.rgba is 256x64 (" .. tostring(sh and #sh) .. ")")
  check(type(meta) == "table" and meta.glyphCount == 64 and meta.glyphW == 16
    and meta.glyphH == 16, "braille.lua declares 64 glyphs of 16x16")
  if fg then
    local ink = 0
    for i = 4, #fg, 4 do
      if fg:byte(i) == 255 then ink = ink + 1 end
    end
    check(ink > 1000 and ink < 256 * 64,
      "the braille sheet has ink and empty space (" .. ink .. ")")
  end
end

do
  local manifestSrc = readFile("seagallop/manifest.lua")
  local manifest = manifestSrc and loadstring(manifestSrc)
  manifest = manifest and manifest()
  check(type(manifest) == "table" and manifest.format == Seagallop.FORMAT_VERSION,
    "seagallop/manifest.lua is format " .. Seagallop.FORMAT_VERSION)
  for _, blob in ipairs(Seagallop.BLOBS) do
    local data = readFile("seagallop/" .. blob.rel)
    check(data ~= nil and #data == blob.size,
      "seagallop/" .. blob.rel .. " is " .. blob.size .. " bytes ("
        .. tostring(data and #data) .. ")")
  end
  for _, sheet in ipairs({ { "water.rgba", 64, 48 }, { "ferry.rgba", 64, 40 },
                           { "wake.rgba", 32, 128 } }) do
    local data = readFile("seagallop/" .. sheet[1])
    check(data ~= nil and #data == sheet[2] * sheet[3] * 4,
      "seagallop/" .. sheet[1] .. " is " .. sheet[2] .. "x" .. sheet[3]
        .. " (" .. tostring(data and #data) .. ")")
  end
  local wb = readFile("seagallop/wb.rgba")
  local eb = readFile("seagallop/eb.rgba")
  check(wb ~= nil and #wb == 256 * 256 * 4, "seagallop/wb.rgba is 256x256")
  check(eb ~= nil and #eb == 256 * 256 * 4, "seagallop/eb.rgba is 256x256")
  check(wb ~= nil and eb ~= nil and wb ~= eb,
    "the westbound and eastbound water is different art")
  if wb then
    local opaque = 0
    for i = 4, #wb, 4 do
      if wb:byte(i) == 255 then opaque = opaque + 1 end
    end
    check(opaque == 256 * 256, "the ferry background is a solid layer (" .. opaque .. ")")
  end
end

do
  local missing = {}
  for id = 0, 19 do
    local key = BattleChrome.TERRAIN_KEYS[id]
    local full = readFile("pokemon/battle/terrain_" .. key .. ".rgba")
    if full == nil or #full ~= 256 * 256 * 4 then
      missing[#missing + 1] = key
    end
    for _, layer in ipairs({ "bg", "enemy", "player" }) do
      local split = readFile("pokemon/battle/terrain_" .. layer .. "_" .. key .. ".rgba")
      if split == nil or #split ~= 256 * 160 * 4 then
        missing[#missing + 1] = layer .. "_" .. key
      end
    end
  end
  check(#missing == 0,
    "all 20 terrain sets are in the cache (missing: "
      .. (#missing > 0 and table.concat(missing, ",") or "none") .. ")")
end

finish()
