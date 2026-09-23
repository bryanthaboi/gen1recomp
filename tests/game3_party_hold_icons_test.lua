#!/usr/bin/env luajit
-- src/data/party_menu.h:664, src/party_menu.c:2743, :2785

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

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
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

local Versions = require("src.import.gba.versions")
local Chrome = require("src.import.gba.party_chrome_extract")
local CacheContract = require("src.import.CacheContract")

local FR = { gfx = 0x45A3AC, pal = 0x45A3EC }
local LG = { gfx = 0x459DCC, pal = 0x459E0C }

print("[test] 1. the held-item icon offsets are pret's party_menu.o statics")
eq(Versions.PARTY_MENU_HOLD_ICONS_GFX, FR.gfx, "FireRed sHeldItemGfx")
eq(Versions.PARTY_MENU_HOLD_ICONS_PAL, FR.pal, "FireRed sHeldItemPalette")
Versions.select("leafgreen")
eq(Versions.PARTY_MENU_HOLD_ICONS_GFX, LG.gfx, "LeafGreen sHeldItemGfx")
eq(Versions.PARTY_MENU_HOLD_ICONS_PAL, LG.pal, "LeafGreen sHeldItemPalette")
Versions.select("firered")

print("[test] 2. the sheet is two 8x8 frames, item over mail, colour 0 clear")
do
  local gfx, pal = {}, {}
  for i = 1, 32 do gfx[i] = 0x11 end
  for i = 33, 64 do gfx[i] = 0x20 end
  for i = 1, 32 do pal[i] = 0 end
  pal[3], pal[4] = 0x1F, 0x00
  pal[5], pal[6] = 0xE0, 0x03
  local rgba, w, h, frames = Chrome.bakeHoldIcons(gfx, pal)
  eq(w, 8, "sheet width")
  eq(h, 16, "sheet height")
  eq(frames, 2, "two frames")
  eq(#rgba, 8 * 16 * 4, "RGBA bytes")
  eq(opaque(rgba, 0, 0, 8, 8, 8), 64, "frame 0 (item) is solid colour 1")
  eq(opaque(rgba, 0, 8, 8, 8, 8), 32, "frame 1 (mail) keeps colour 0 transparent")
  eq(rgba:byte(1), 255, "colour 1 is the palette's red")
  eq(rgba:byte((8 * 8 + 1) * 4 + 2), 255, "colour 2 is the palette's green")
end

print("[test] 3. the offsets hit pret's hold_icons in a matching build")
local PRET = "../pokefirered"
local g4 = slurp(PRET .. "/graphics/party_menu/hold_icons.4bpp")
local gp = slurp(PRET .. "/graphics/party_menu/hold_icons.gbapal")
local compared = 0
if g4 and gp then
  for _, b in ipairs({ { "pokefirered.gba", FR }, { "pokeleafgreen.gba", LG } }) do
    local image = slurp(PRET .. "/" .. b[1])
    if image then
      compared = compared + 1
      check(image:sub(b[2].gfx + 1, b[2].gfx + #g4) == g4, b[1] .. " sHeldItemGfx")
      check(image:sub(b[2].pal + 1, b[2].pal + #gp) == gp, b[1] .. " sHeldItemPalette")
    end
  end
  local gfx, pal = { g4:byte(1, -1) }, { gp:byte(1, -1) }
  local rgba = Chrome.bakeHoldIcons(gfx, pal)
  check(opaque(rgba, 0, 0, 8, 8, 8) > 0, "pret's item frame has pixels")
  check(opaque(rgba, 0, 8, 8, 8, 8) > 0, "pret's mail frame has pixels")
  check(rgba:sub(1, 256) ~= rgba:sub(257, 512), "and the two frames differ")
end
if compared == 0 then print("[skip] no pret build next to the checkout") end

print("[test] 4. the cache contract lists the new party and trade sheets")
do
  local have = {}
  for _, p in ipairs(CacheContract.requiredFiles("firered")) do have[p] = true end
  check(have["data/generated/gba/pokemon/party/hold_icons.rgba"], "party/hold_icons.rgba is required")
  for _, name in ipairs({ "menu_bg1", "stripes_bg2", "stripes_bg3", "party_box", "moves_box",
      "mon_box", "menu_tiles", "cursor" }) do
    check(have["data/generated/gba/trade/" .. name .. ".rgba"], "trade/" .. name .. ".rgba is required")
  end
  local lg = {}
  for _, p in ipairs(CacheContract.requiredFiles("leafgreen")) do lg[p] = true end
  check(lg["data/generated/gba/pokemon/party/hold_icons.rgba"], "LeafGreen requires it too")
end

local Cache = require("tests.game3_cache")
local root = Cache.root("pokemon/party/hold_icons.rgba")
if not root then
  print("[skip] baked held-item icons: " .. tostring(Cache.reason))
  finish()
end

print("[test] 5. a built cache carries the held-item sheet")
do
  local blob = slurp(root .. "/pokemon/party/hold_icons.rgba")
  eq(blob and #blob or nil, 8 * 16 * 4, "cached pokemon/party/hold_icons.rgba size")
  local man = loadstring(slurp(root .. "/pokemon/party/manifest.lua") or "")
  man = man and man()
  eq(man and man.holdIconW, 8, "manifest holdIconW")
  eq(man and man.holdIconSheetH, 16, "manifest holdIconSheetH")
  eq(man and man.holdIconFrames, 2, "manifest holdIconFrames")
  if blob and g4 and gp then
    check(blob == (Chrome.bakeHoldIcons({ g4:byte(1, -1) }, { gp:byte(1, -1) })), "the cached sheet is pret's art")
  end
end

print("[test] 6. the partner's own catch from outside the region was met somewhere")
if Cache.mount() then
  local SummaryData = require("src.core.game3.summary_data")
  local mon = { metLocation = 0, metLevel = 7, personality = 3, otName = "BLUE", otId = 0x2222 }
  local me = { name = "RED", trainerId = 0x1234 }
  local owner = { playerName = "BLUE", trainerId = 0x2222 }
  -- src/pokemon_summary_screen.c:2636
  local line = table.concat(SummaryData.formatTrainerMemo(mon, me, { enemyParty = true, owner = owner }), " ")
  check(line:find("Somewhere", 1, true) ~= nil, "partner party prints gText_Somewhere (" .. line .. ")")
  local own = table.concat(SummaryData.formatTrainerMemo(mon, owner), " ")
  check(own:find("a trade", 1, true) ~= nil, "the same mon in its OT's own party says a trade (" .. own .. ")")
else
  print("[skip] memo text needs a mounted cache: " .. tostring(Cache.reason))
end

finish()
