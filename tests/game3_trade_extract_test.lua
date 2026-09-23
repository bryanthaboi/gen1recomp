#!/usr/bin/env luajit
-- src/trade.c:1368, src/graphics.c:1222

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

local function finish()
  if failed > 0 then
    print(string.format("[result] %d CHECK(S) FAILED", failed))
    os.exit(1)
  end
  print("[result] all checks passed")
  os.exit(0)
end

local Versions = require("src.import.gba.versions")
local Trade = require("src.import.gba.trade_extract")

local MENU_SHEETS = {
  { "menu_bg1", 240, 160 },
  { "stripes_bg2", 256, 160 },
  { "stripes_bg3", 256, 160 },
  { "party_box", 120, 136 },
  { "moves_box", 120, 136 },
  { "mon_box", 48, 24 },
  { "menu_tiles", 128, 80 },
  { "cursor", 64, 64 },
}

local FR = {
  TRADE_MOVES_BOX_MAP = 0x260834,
  TRADE_PARTY_BOX_MAP = 0x260A32,
  TRADE_STRIPES_BG2_MAP = 0x260C30,
  TRADE_STRIPES_BG3_MAP = 0x261430,
  TRADE_MENU_PAL = 0xE9CEDC,
  TRADE_CURSOR_PAL = 0xE9CF3C,
  TRADE_MENU_GFX = 0xE9CF5C,
  TRADE_CURSOR_GFX = 0xE9E1DC,
  TRADE_MENU_MAP = 0xE9E9FC,
  TRADE_MENU_MON_BOX_MAP = 0xE9F1FC,
  TRADE_MON_SHADOW_MAP = 0x26601C,
}
local LG = {
  TRADE_MOVES_BOX_MAP = 0x260814,
  TRADE_PARTY_BOX_MAP = 0x260A12,
  TRADE_STRIPES_BG2_MAP = 0x260C10,
  TRADE_STRIPES_BG3_MAP = 0x261410,
  TRADE_MENU_PAL = 0xE9CF5C,
  TRADE_CURSOR_PAL = 0xE9CFBC,
  TRADE_MENU_GFX = 0xE9CFDC,
  TRADE_CURSOR_GFX = 0xE9E25C,
  TRADE_MENU_MAP = 0xE9EA7C,
  TRADE_MENU_MON_BOX_MAP = 0xE9F27C,
  TRADE_MON_SHADOW_MAP = 0x265FFC,
}
local BINS = {
  TRADE_MOVES_BOX_MAP = "moves_box_map.bin",
  TRADE_PARTY_BOX_MAP = "party_box_map.bin",
  TRADE_STRIPES_BG2_MAP = "stripes_bg2_map.bin",
  TRADE_STRIPES_BG3_MAP = "stripes_bg3_map.bin",
  TRADE_MENU_PAL = "menu.gbapal",
  TRADE_CURSOR_PAL = "cursor.gbapal",
  TRADE_MENU_GFX = "menu.4bpp",
  TRADE_CURSOR_GFX = "cursor.4bpp",
  TRADE_MENU_MAP = "menu.bin",
  TRADE_MENU_MON_BOX_MAP = "menu_mon_box.bin",
  TRADE_MON_SHADOW_MAP = "shadow_map.bin",
}

print("[test] 1. the trade menu offsets are pret's symbols in both editions")
for key, off in pairs(FR) do
  eq(Versions[key], off, "FireRed " .. key)
end
Versions.select("leafgreen")
for key, off in pairs(LG) do
  eq(Versions[key], off, "LeafGreen " .. key)
end
Versions.select("firered")
eq(Versions.TRADE_MENU_GFX, FR.TRADE_MENU_GFX, "selecting FireRed again restores the base offsets")

print("[test] 2. run() bakes every trade menu sheet at its manifest size")
local written = {}
local stub = {
  write = function(_, rel, bytes) written[rel] = bytes end,
  read = function(_, rel) return written[rel] end,
  exists = function(_, rel) return written[rel] ~= nil end,
}
local rom = {
  get = function(_, off) return (off * 7 + 3) % 256 end,
  u16 = function(self, off) return self:get(off) + self:get(off + 1) * 256 end,
}
check(Trade.ready(stub, "x") == false, "ready() is false with nothing written")
local okRun, err = pcall(Trade.run, rom, stub, { cacheRoot = "x" })
check(okRun, "run() completes on a synthetic ROM (" .. tostring(err) .. ")")
for _, sheet in ipairs(MENU_SHEETS) do
  local blob = written["x/trade/" .. sheet[1] .. ".rgba"]
  eq(blob and #blob or nil, sheet[2] * sheet[3] * 4,
    "trade/" .. sheet[1] .. ".rgba is " .. sheet[2] .. "x" .. sheet[3])
end
local manChunk = written["x/trade/manifest.lua"] and loadstring(written["x/trade/manifest.lua"])
local man = manChunk and manChunk()
check(type(man) == "table", "the manifest loads")
if man then
  eq(man.format_version, 3, "the manifest is format 3")
  eq(written["x/trade/mon_shadow_bg.rgba"] and #written["x/trade/mon_shadow_bg.rgba"], 256 * 160 * 4,
    "trade/mon_shadow_bg.rgba is 256x160")
  check(man.mon_shadow_bg and man.mon_shadow_bg.width == 256 and man.mon_shadow_bg.height == 160,
    "manifest sizes mon_shadow_bg")
  for _, sheet in ipairs(MENU_SHEETS) do
    local e = man[sheet[1]] or {}
    check(e.width == sheet[2] and e.height == sheet[3], "manifest sizes " .. sheet[1])
  end
  eq(man.cursor and man.cursor.frames, 2, "the cursor carries the normal and on-cancel frames")
  eq(man.menu_tiles and man.menu_tiles.tiles, 0x1280 / 32, "the tile sheet holds all menu tiles")
  eq(man.menu_tiles and man.menu_tiles.level_ones, 0x70, "level ones digits start at tile 0x70")
  eq(man.menu_tiles and man.menu_tiles.egg_symbol, 0x80, "the egg symbol is tile 0x80")
end
check(Trade.ready(stub, "x") == true, "ready() accepts the full group")
written["x/trade/cursor.rgba"] = nil
check(Trade.ready(stub, "x") == false, "ready() refuses a group without the cursor")

print("[test] 3. the offsets hit pret's graphics/trade bins in a matching build")
local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end
local PRET = "../pokefirered"
local builds = { { "pokefirered.gba", FR }, { "pokeleafgreen.gba", LG } }
local compared = 0
for _, b in ipairs(builds) do
  local image = slurp(PRET .. "/" .. b[1])
  if image then
    for key, off in pairs(b[2]) do
      local bin = slurp(PRET .. "/graphics/trade/" .. BINS[key])
      if bin then
        compared = compared + 1
        check(image:sub(off + 1, off + #bin) == bin, b[1] .. " " .. key .. " matches " .. BINS[key])
      end
    end
  end
end
if compared == 0 then print("[skip] no pret build next to the checkout") end

print("[test] 4. a built cache carries the trade menu sheets")
local Cache = require("tests.game3_cache")
local root = Cache.root("trade/menu_bg1.rgba")
if not root then
  print("[skip] baked trade menu art: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. root)
local cman = loadstring(slurp(root .. "/trade/manifest.lua") or "")
cman = cman and cman()
eq(cman and cman.format_version, 3, "the cached trade manifest is format 3")
local blobs = {}
for _, sheet in ipairs(MENU_SHEETS) do
  local blob = slurp(root .. "/trade/" .. sheet[1] .. ".rgba")
  blobs[sheet[1]] = blob
  eq(blob and #blob or nil, sheet[2] * sheet[3] * 4, "cached trade/" .. sheet[1] .. ".rgba size")
end

local function opaque(blob, x0, y0, w, h, stride)
  local n = 0
  for y = y0, y0 + h - 1 do
    for x = x0, x0 + w - 1 do
      local a = blob:byte((y * stride + x) * 4 + 4)
      if a and a > 0 then n = n + 1 end
    end
  end
  return n
end

if blobs.stripes_bg3 then
  eq(opaque(blobs.stripes_bg3, 0, 0, 256, 160, 256), 256 * 160,
    "BG3 stripes are opaque over the backdrop")
end
if blobs.cursor then
  check(opaque(blobs.cursor, 0, 0, 64, 32, 64) > 0, "the normal cursor frame has pixels")
  check(opaque(blobs.cursor, 0, 32, 64, 32, 64) > 0, "the on-cancel cursor frame has pixels")
end
if blobs.menu_tiles then
  local function tileOpaque(t)
    return opaque(blobs.menu_tiles, (t % 16) * 8, math.floor(t / 16) * 8, 8, 8, 128)
  end
  check(tileOpaque(0x70) > 0, "the level ones digit 0 tile is drawn")
  check(tileOpaque(0x84) > 0, "the male symbol tile is drawn")
  check(tileOpaque(0x85) > 0, "the female symbol tile is drawn")
  eq(tileOpaque(148), 0, "slots past the last menu tile stay empty")
end
if blobs.menu_bg1 then
  check(opaque(blobs.menu_bg1, 0, 0, 240, 160, 240) > 0, "the menu board has pixels")
end

finish()
