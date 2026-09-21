#!/usr/bin/env luajit
-- pokefirered/src/battle_interface.c:615, pokefirered/src/pokemon_summary_screen.c:4716
-- pokefirered/src/region_map.c:425

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

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local Versions = require("src.import.gba.versions")
local CacheContract = require("src.import.CacheContract")
local BattleChromeExtract = require("src.import.gba.battle_chrome_extract")
local SummaryChromeExtract = require("src.import.gba.summary_chrome_extract")

local BATTLE_REL = "pokemon/battle"
local SUMMARY_REL = "pokemon/summary"
local SAFARI_REL = BATTLE_REL .. "/healthbox_safari.rgba"
local FLY_ICON_REL = "region_map/fly_icon.rgba"
local SAFARI_W, SAFARI_H = 128, 64

print("[test] 1. ROM pins and the firered required list")

eq(Versions.BATTLE_UI.healthbox_safari, 0xD1FABC, "gHealthboxSafariGfx is pinned")
eq(Versions.REGION_MAP_FLY_ICON_GFX, 0x3F1908, "sFlyIcon is pinned")

do
  local required = CacheContract.requiredFiles("firered")
  local want = {
    ["data/generated/gba/" .. FLY_ICON_REL] = false,
    ["data/generated/gba/region_map/fly_icon.png"] = false,
  }
  for _, path in ipairs(required) do
    if want[path] ~= nil then want[path] = true end
  end
  for path, seen in pairs(want) do
    check(seen, "firered required list carries " .. path)
  end
end

print("[test] 2. the bake against pret")

local PRET = "../pokefirered"
local ROM_SHA1 = "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"
local mapSrc = slurp(PRET .. "/pokefirered.map")
local safariRaw = slurp(PRET .. "/graphics/battle_interface/healthbox_safari.4bpp")
local summarySrc = slurp(PRET .. "/src/pokemon_summary_screen.c")
local romPresent = io.open(PRET .. "/pokefirered.gba", "rb")
if romPresent then romPresent:close() end

local baked, summaryManifest
if not (mapSrc and safariRaw and summarySrc and romPresent) then
  print("[skip] " .. PRET .. " sources or ROM not present; pret section skipped")
else
  local pin = Versions.BATTLE_UI.healthbox_safari
  local mapAddr = mapSrc:match("0x(%x+)%s+gHealthboxSafariGfx")
  eq(tonumber(mapAddr, 16), 0x08000000 + (pin or 0),
    "pokefirered.map puts gHealthboxSafariGfx at the pinned offset")
  eq(#safariRaw, 0x1000, "healthbox_safari.4bpp is sSpriteSheet_SafariHealthbox .size")

  local FileIO = require("src.import.gba.file_io")
  local imports = FileIO.makeImports(PRET .. "/pokefirered.gba", ROM_SHA1, "firered")
  local rom = assert(require("src.import.gba.rom").open(imports, "firered"))
  if not pin then
    check(false, "the decompressed blob is pret's healthbox_safari.4bpp byte for byte")
  else
    local Lz77 = require("src.import.gba.lz77")
    local decoded = Lz77.decompress(function(i) return rom:get(i) end, pin)
    local decodedStr = decoded
    if type(decoded) == "table" then
      local bytes = {}
      for i = 1, #decoded do bytes[i] = string.char(decoded[i]) end
      decodedStr = table.concat(bytes)
    end
    eq(#decodedStr, #safariRaw, "the ROM blob decompresses to the 4bpp size")
    check(decodedStr == safariRaw, "the decompressed blob is pret's healthbox_safari.4bpp byte for byte")
  end

  local mem = { files = {} }
  function mem:write(path, data) self.files[path] = data end
  function mem:exists(path) return self.files[path] ~= nil end
  BattleChromeExtract.run(rom, mem, { cacheRoot = "data/generated/gba" })
  baked = mem.files["data/generated/gba/" .. SAFARI_REL]
  check(baked ~= nil, "the extractor writes " .. SAFARI_REL)
  if baked then
    eq(#baked, SAFARI_W * SAFARI_H * 4, "the safari sheet is 128x64 RGBA")
    local player = mem.files["data/generated/gba/" .. BATTLE_REL .. "/healthbox_player.rgba"]
    check(player and baked ~= player, "the safari sheet is not the singles player sheet")
    local opaque, palette = 0, {}
    for i = 4, #baked, 4 do
      if baked:byte(i) > 0 then
        opaque = opaque + 1
        palette[baked:sub(i - 3, i - 1)] = true
      end
    end
    check(opaque > 1000, "the safari sheet has real opaque pixels (" .. opaque .. ")")
    local playerColors = {}
    for i = 4, #player, 4 do
      if player:byte(i) > 0 then playerColors[player:sub(i - 3, i - 1)] = true end
    end
    local stray = 0
    for color in pairs(palette) do
      if not playerColors[color] then stray = stray + 1 end
    end
    eq(stray, 0, "every safari color comes from the shared TAG_HEALTHBOX_PAL")
  end

  local battleManifest = mem.files["data/generated/gba/" .. BATTLE_REL .. "/manifest.lua"]
  local row = battleManifest and battleManifest:match("safariBox%s*=%s*{(.-)}")
  check(row ~= nil, "the battle manifest carries a safariBox row")
  if row then
    eq(tonumber(row:match("w%s*=%s*(%d+)")), SAFARI_W, "safariBox width")
    eq(tonumber(row:match("h%s*=%s*(%d+)")), SAFARI_H, "safariBox height")
    -- src/battle_interface.c:735
    eq(tonumber(row:match("x%s*=%s*(%d+)")), 158, "safariBox x is the player healthbox x")
    eq(tonumber(row:match("y%s*=%s*(%d+)")), 88, "safariBox y is the player healthbox y")
    eq(row:match('file%s*=%s*"([^"]+)"'), "healthbox_safari.rgba", "safariBox file")
  end

  local mem2 = { files = {} }
  function mem2:write(path, data) self.files[path] = data end
  function mem2:exists(path) return self.files[path] ~= nil end
  SummaryChromeExtract.run(rom, mem2, { cacheRoot = "data/generated/gba" })
  summaryManifest = mem2.files["data/generated/gba/" .. SUMMARY_REL .. "/manifest.lua"]
  check(summaryManifest ~= nil, "the extractor writes the summary manifest")

  -- src/pokemon_summary_screen.c:4716, :4800, :4830
  local pokerusCx, pokerusCy = summarySrc:match(
    "sPokerusIconObj%s*!=%s*NULL.-CreateSprite%(&template,%s*(%d+),%s*(%d+),")
  local starCx, starCy = summarySrc:match(
    "sShinyStarObjData%s*!=%s*NULL.-CreateSprite%(&template,%s*(%d+),%s*(%d+),")
  local movesCx, movesCy = summarySrc:match(
    "curPageIndex%s*==%s*PSS_PAGE_MOVES_INFO%s*%)%s*{?%s*"
      .. "sShinyStarObjData%->sprite%->x%s*=%s*(%d+);%s*"
      .. "sShinyStarObjData%->sprite%->y%s*=%s*(%d+);")
  check(pokerusCx and starCx and movesCx, "pret still creates both icons with literal centers")
  if pokerusCx and starCx and movesCx and summaryManifest then
    local function coord(key)
      local body = summaryManifest:match(key .. "%s*=%s*{(.-)}")
      if not body then return nil end
      return tonumber(body:match("x%s*=%s*(%d+)")), tonumber(body:match("y%s*=%s*(%d+)"))
    end
    -- src/pokemon_summary_screen.c:565, :594
    local sx, sy = coord("shinyStar")
    eq(sx, tonumber(starCx) - 4, "shinyStar x is pret's sprite center less 4")
    eq(sy, tonumber(starCy) - 4, "shinyStar y is pret's sprite center less 4")
    local mx, my = coord("shinyStarMovesInfo")
    eq(mx, tonumber(movesCx) - 4, "shinyStarMovesInfo x is the MOVES_INFO center less 4")
    eq(my, tonumber(movesCy) - 4, "shinyStarMovesInfo y is the MOVES_INFO center less 4")
    local px, py = coord("pokerus")
    eq(px, tonumber(pokerusCx) - 4, "pokerus x is pret's sprite center less 4")
    eq(py, tonumber(pokerusCy) - 4, "pokerus y is pret's sprite center less 4")
  end
end

print("[test] 3. the imported cache")

local Cache = require("tests.game3_cache")
local root = Cache.root("meta.json")
if not root then
  print("[skip] " .. tostring(Cache.reason))
else
  print("[cache] " .. root)
  local safari = slurp(root .. "/" .. SAFARI_REL)
  check(safari ~= nil, "the cache carries " .. SAFARI_REL)
  if safari then
    eq(#safari, SAFARI_W * SAFARI_H * 4, "the cached safari sheet is 128x64 RGBA")
    if baked then
      check(safari == baked, "the cached safari sheet matches a fresh bake byte for byte")
    end
  end

  local flyIcon = slurp(root .. "/" .. FLY_ICON_REL)
  check(flyIcon ~= nil, "the cache carries " .. FLY_ICON_REL)
  if flyIcon then
    eq(#flyIcon, 16 * 16 * 4, "the cached fly icon is 16x16 RGBA")
    local opaque = 0
    for i = 4, #flyIcon, 4 do
      if flyIcon:byte(i) > 0 then opaque = opaque + 1 end
    end
    check(opaque > 0, "the cached fly icon has opaque pixels (" .. opaque .. ")")
  end

  local cachedSummary = slurp(root .. "/" .. SUMMARY_REL .. "/manifest.lua")
  check(cachedSummary ~= nil, "the cache carries the summary manifest")
  if cachedSummary and summaryManifest then
    local function coords(src, key)
      local body = src:match(key .. "%s*=%s*{(.-)}")
      if not body then return "missing" end
      return (body:match("x%s*=%s*(%d+)") or "?") .. "," .. (body:match("y%s*=%s*(%d+)") or "?")
    end
    for _, key in ipairs({ "shinyStar", "shinyStarMovesInfo", "pokerus" }) do
      eq(coords(cachedSummary, key), coords(summaryManifest, key),
        "cached summary coords." .. key .. " matches a fresh bake")
    end
  end

  local missing = {}
  for _, path in ipairs(CacheContract.requiredFiles("firered")) do
    local rel = path:match("^data/generated/gba/(.+)$")
    if rel and not slurp(root .. "/" .. rel) then missing[#missing + 1] = rel end
  end
  for _, rel in ipairs(missing) do print("      missing " .. rel) end
  eq(#missing, 0, "every firered required file is in the cache")
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("\nALL PASS")
