#!/usr/bin/env luajit
-- pokefirered/src/pokemon_summary_screen.c:1862

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local PRET = "../pokefirered"
local GFX = PRET .. "/graphics/summary_screen/"
local ROM_SHA1 = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"

local function slurp(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local tiles = slurp(GFX .. "bg.4bpp")
local pal = slurp(GFX .. "bg.gbapal")
local romPresent = slurp(PRET .. "/pokefirered.gba") ~= nil
if not (tiles and pal and romPresent) then
  print("[skip] " .. PRET .. " summary graphics or ROM not present")
  os.exit(0)
end

local function u16(s, i) return s:byte(i + 1) + s:byte(i + 2) * 256 end

-- pokefirered/src/pokemon_summary_screen.c:3276
local BASE = 345
local PROGRESS = {
  info = { { 17, 13, 0 }, { 33, 13, 1 }, { 16, 14, 0 }, { 32, 14, 1 }, { 18, 15, 0 }, { 34, 15, 1 },
           { 20, 16, 0 }, { 36, 16, 1 }, { 18, 17, 0 }, { 34, 17, 1 }, { 21, 18, 0 }, { 37, 18, 1 } },
  moves = { { 49, 13, 0 }, { 65, 13, 1 }, { 1, 14, 0 }, { 19, 14, 1 }, { 49, 15, 0 }, { 65, 15, 1 },
            { 1, 16, 0 }, { 19, 16, 1 }, { 17, 17, 0 }, { 33, 17, 1 }, { 48, 18, 0 }, { 64, 18, 1 } },
  moves_info_select = { { 1, 13, 0 }, { 1, 14, 0 }, { 1, 15, 0 }, { 1, 16, 0 },
                        { 19, 13, 1 }, { 19, 14, 1 }, { 19, 15, 1 }, { 19, 16, 1 },
                        { 50, 17, 0 }, { 66, 17, 1 }, { 48, 18, 0 }, { 64, 18, 1 } },
}

local function render(binName, progressKind, shiny)
  local map = assert(slurp(GFX .. binName), binName)
  local entries = {}
  for i = 0, 32 * 20 - 1 do entries[i] = u16(map, i * 2) end
  for _, p in ipairs(PROGRESS[progressKind] or {}) do
    entries[p[3] * 32 + p[2]] = p[1] + BASE
  end
  local out = {}
  for ty = 0, 19 do
    for tx = 0, 29 do
      local e = entries[ty * 32 + tx]
      local tile, hf, vf, pn = e % 1024, math.floor(e / 1024) % 2 == 1, math.floor(e / 2048) % 2 == 1, math.floor(e / 4096)
      local bank = pn
      if shiny and pn == 0 then bank = 6 elseif shiny and pn == 1 then bank = 5 end
      for y = 0, 7 do
        for x = 0, 7 do
          local sx, sy = hf and (7 - x) or x, vf and (7 - y) or y
          local b = tiles:byte(tile * 32 + sy * 4 + math.floor(sx / 2) + 1) or 0
          local idx = (sx % 2 == 0) and (b % 16) or math.floor(b / 16)
          if idx ~= 0 then
            out[(ty * 8 + y) * 240 + tx * 8 + x] = u16(pal, bank * 32 + idx * 2) % 32768
          end
        end
      end
    end
  end
  return out
end

local function to15(rgba, i)
  local r, g, b = rgba:byte(i * 4 + 1), rgba:byte(i * 4 + 2), rgba:byte(i * 4 + 3)
  local function c5(v) return math.floor(v * 31 / 255 + 0.5) end
  return c5(r) + c5(g) * 32 + c5(b) * 1024, rgba:byte(i * 4 + 4)
end

local function compare(label, bake, want, w, h, ox, oy, opaque)
  if not bake then check(false, label .. " was baked") return end
  eq(#bake, w * h * 4, label .. " size")
  local bad = 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local c, a = to15(bake, y * w + x)
      local p = want[(y + oy) * 240 + x + ox]
      if p == nil then
        if not opaque and a ~= 0 then bad = bad + 1 end
      elseif a == 0 or c ~= p then
        bad = bad + 1
      end
    end
  end
  eq(bad, 0, label .. " matches pret's tilemap render pixel for pixel")
end

local FileIO = require("src.import.gba.file_io")
local imports = FileIO.makeImports(PRET .. "/pokefirered.gba", ROM_SHA1, "firered")
local rom = assert(require("src.import.gba.rom").open(imports, "firered"))
local mem = { files = {} }
function mem:write(p, d) self.files[p] = d end
function mem:exists(p) return self.files[p] ~= nil end
require("src.import.gba.summary_chrome_extract").run(rom, mem, { cacheRoot = "X" })
local function baked(name) return mem.files["X/pokemon/summary/" .. name] end

print("[test] 1. KNOWN MOVES keeps the picture frame; move detail swaps it")
for _, shiny in ipairs({ false, true }) do
  local sfx = shiny and "_shiny" or ""
  compare("bg3_info" .. sfx, baked("bg3_info" .. sfx .. ".rgba"), render("moves_info_page.bin", nil, shiny), 240, 160, 0, 0, true)
  compare("bg3_moves" .. sfx, baked("bg3_moves" .. sfx .. ".rgba"), render("moves_page.bin", nil, shiny), 240, 160, 0, 0, true)
  for _, layer in ipairs({ "info", "moves", "moves_info" }) do
    compare("layer_" .. layer .. sfx, baked("layer_" .. layer .. sfx .. ".rgba"),
      render("page_" .. layer .. ".bin", nil, shiny), 240, 160, 0, 0, false)
  end
  for _, kind in ipairs({ "info", "moves", "moves_info_select" }) do
    local base = kind == "moves_info_select" and "moves_page.bin" or "moves_info_page.bin"
    compare("progress_" .. kind .. sfx, baked("progress_" .. kind .. sfx .. ".rgba"),
      render(base, kind, shiny), 48, 16, 104, 0, true)
  end
end
check(baked("page_moves.rgba") == nil, "the old move-detail bake under the KNOWN MOVES name is gone")
check(baked("page_info.rgba") ~= nil, "page_info.rgba still marks the cache ready")

print("[test] 2. manifest carries the ROM tables the screen reads")
local manifest = baked("manifest.lua")
local m = manifest and load(manifest, "=manifest", "t", {})()
check(m ~= nil, "the manifest loads")
if m then
  local n = 0
  for _ in pairs(m.noFlip or {}) do n = n + 1 end
  eq(n, 18, "eighteen species are never flipped")
  eq(m.noFlip and m.noFlip[25], nil, "Pikachu is flipped")
  local lens = {}
  for i, d in ipairs(m.monPicBounce or {}) do lens[i] = #d end
  eq(table.concat(lens, ","), "3,5,7,7", "four pic bounce tables")
  eq(m.monPicBounce and m.monPicBounce[4] and m.monPicBounce[4][1], -5, "the full-HP bounce starts at -5")
  local el = {}
  for i, d in ipairs(m.eggPicShake or {}) do el[i] = #d end
  eq(table.concat(el, ","), "11,11,15", "three egg shake tables")
  eq(m.eggPicShake and m.eggPicShake[3] and m.eggPicShake[3][7], -2, "AlmostReadyToHatch step 7 is -2")
  local c = m.moveTextColors and m.moveTextColors[3]
  check(c and c.fg[1] > 200 and c.fg[2] < 40, "PP colour 3 is red")
  eq(m.coords and m.coords.status and m.coords.status.y, 34, "status is stored as a top-left")
end

print("[test] 3. markings sheet")
local marks = baked("markings.rgba")
eq(marks and #marks, 32 * 128 * 4, "sixteen 32x8 marking combos")
if marks then
  local lit0, lit5 = 0, 0
  for i = 0, 32 * 8 - 1 do
    if marks:byte(i * 4 + 4) > 0 then lit0 = lit0 + 1 end
    if marks:byte((5 * 256 + i) * 4 + 4) > 0 then lit5 = lit5 + 1 end
  end
  check(lit0 > 0 and lit5 > 0, "combos have pixels")
end

print("[test] 4. the imported cache")
local Cache = require("tests.game3_cache")
local root = Cache.root("meta.json")
if not root then
  print("[skip] " .. tostring(Cache.reason))
else
  for _, name in ipairs({ "bg3_info.rgba", "layer_moves.rgba", "progress_moves_info_select.rgba", "markings.rgba" }) do
    local d = slurp(root .. "/pokemon/summary/" .. name)
    check(d ~= nil and d == baked(name), "the cache's " .. name .. " is the current bake")
  end
end

T.finish("game3_summary_chrome_bake_s3_test")
