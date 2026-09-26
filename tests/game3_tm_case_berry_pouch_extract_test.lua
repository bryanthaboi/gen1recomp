#!/usr/bin/env luajit
-- Test TM Case and Berry Pouch ROM Chrome Extraction & Versions offsets.

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

local Versions = require("src.import.gba.versions")
local TmCaseExtract = require("src.import.gba.tm_case_extract")
local BerryPouchExtract = require("src.import.gba.berry_pouch_extract")

print("=== 1. Versions Offsets Verification ===")
check(Versions.TM_CASE_BG_GFX == 0xE845D8, "Versions.TM_CASE_BG_GFX is 0xE845D8")
check(Versions.TM_CASE_MENU_TILEMAP == 0xE84A24, "Versions.TM_CASE_MENU_TILEMAP is 0xE84A24")
check(Versions.TM_CASE_BG_TILEMAP == 0xE84B70, "Versions.TM_CASE_BG_TILEMAP is 0xE84B70")
check(Versions.TM_CASE_MENU_MALE_PAL == 0xE84CB0, "Versions.TM_CASE_MENU_MALE_PAL is 0xE84CB0")
check(Versions.TM_CASE_MENU_FEMALE_PAL == 0xE84D20, "Versions.TM_CASE_MENU_FEMALE_PAL is 0xE84D20")
check(Versions.TM_CASE_DISC_GFX == 0xE84D90, "Versions.TM_CASE_DISC_GFX is 0xE84D90")
check(Versions.TM_CASE_DISC_TYPES1_PAL == 0xE84F20, "Versions.TM_CASE_DISC_TYPES1_PAL is 0xE84F20")
check(Versions.TM_CASE_DISC_TYPES2_PAL == 0xE85068, "Versions.TM_CASE_DISC_TYPES2_PAL is 0xE85068")
check(Versions.TM_CASE_HM_GFX == 0xE99118, "Versions.TM_CASE_HM_GFX is 0xE99118")

check(Versions.BERRY_POUCH_SPRITE_GFX == 0xE8560C, "Versions.BERRY_POUCH_SPRITE_GFX is 0xE8560C")
check(Versions.BERRY_POUCH_BG_GFX == 0xE859D0, "Versions.BERRY_POUCH_BG_GFX is 0xE859D0")
check(Versions.BERRY_POUCH_BG_PAL == 0xE85BA4, "Versions.BERRY_POUCH_BG_PAL is 0xE85BA4")
check(Versions.BERRY_POUCH_BG_PAL_FEMALE == 0xE85BF4, "Versions.BERRY_POUCH_BG_PAL_FEMALE is 0xE85BF4")
check(Versions.BERRY_POUCH_SPRITE_PAL == 0xE85C1C, "Versions.BERRY_POUCH_SPRITE_PAL is 0xE85C1C")
check(Versions.BERRY_POUCH_BG_TILEMAP == 0xE85C44, "Versions.BERRY_POUCH_BG_TILEMAP is 0xE85C44")

print("\n=== 2. Extraction from FireRed ROM ===")

local candidatePaths = {
  "1636 - Pokemon Fire Red (U)(Squirrels).gba",
  "firered_dump.gba",
  "Pokemon - Fire Red Version (U) (V1.1).gba",
}
local f, romPath
for _, p in ipairs(candidatePaths) do
  f = io.open(p, "rb")
  if f then romPath = p; break end
end
if not f then
  print("[SKIP] ROM not found in candidate paths")
  os.exit(0)
end
local romData = f:read("*all")
f:close()
print("Loaded ROM: " .. romPath)

local rom = {
  get = function(self, i)
    return romData:byte(i + 1) or 0
  end
}

local memoryCache = {
  files = {},
  write = function(self, path, bytes)
    self.files[path] = bytes
    return true
  end,
  exists = function(self, path)
    return self.files[path] ~= nil
  end,
  read = function(self, path)
    return self.files[path]
  end,
}

-- 1. TM Case Extraction
local tmRes = TmCaseExtract.run(rom, memoryCache, { cacheRoot = "data/test_gba" })
check(tmRes and tmRes.width == 240 and tmRes.height == 160, "TmCaseExtract completed")
check(memoryCache:exists("data/test_gba/items/tm_case/bg_male.rgba"), "bg_male.rgba written")
check(#memoryCache:read("data/test_gba/items/tm_case/bg_male.rgba") == 240 * 160 * 4, "bg_male.rgba size is 240x160x4")
check(memoryCache:exists("data/test_gba/items/tm_case/bg_female.rgba"), "bg_female.rgba written")
check(#memoryCache:read("data/test_gba/items/tm_case/bg_female.rgba") == 240 * 160 * 4, "bg_female.rgba size is 240x160x4")
check(memoryCache:exists("data/test_gba/items/tm_case/disc_0.rgba"), "disc_0.rgba (Normal) written")
check(#memoryCache:read("data/test_gba/items/tm_case/disc_0.rgba") == 32 * 32 * 4, "disc_0.rgba size is 32x32x4")
check(memoryCache:exists("data/test_gba/items/tm_case/disc_16.rgba"), "disc_16.rgba (Dragon) written")
check(#memoryCache:read("data/test_gba/items/tm_case/disc_16.rgba") == 32 * 32 * 4, "disc_16.rgba size is 32x32x4")
check(memoryCache:exists("data/test_gba/items/tm_case/hm_icon.rgba"), "hm_icon.rgba written")
check(#memoryCache:read("data/test_gba/items/tm_case/hm_icon.rgba") == 16 * 12 * 4, "hm_icon.rgba size is 16x12x4")
check(TmCaseExtract.ready(memoryCache, "data/test_gba"), "TmCaseExtract.ready reports true")

-- 2. Berry Pouch Extraction
local bpRes = BerryPouchExtract.run(rom, memoryCache, { cacheRoot = "data/test_gba" })
check(bpRes and bpRes.width == 240 and bpRes.height == 160, "BerryPouchExtract completed")
check(memoryCache:exists("data/test_gba/items/berry_pouch/bg_male.rgba"), "Berry Pouch bg_male.rgba written")
check(#memoryCache:read("data/test_gba/items/berry_pouch/bg_male.rgba") == 240 * 160 * 4, "Berry Pouch bg_male.rgba size is 240x160x4")
check(memoryCache:exists("data/test_gba/items/berry_pouch/bg_female.rgba"), "Berry Pouch bg_female.rgba written")
check(#memoryCache:read("data/test_gba/items/berry_pouch/bg_female.rgba") == 240 * 160 * 4, "Berry Pouch bg_female.rgba size is 240x160x4")
check(memoryCache:exists("data/test_gba/items/berry_pouch/pouch.rgba"), "pouch.rgba written")
check(#memoryCache:read("data/test_gba/items/berry_pouch/pouch.rgba") == 64 * 64 * 4, "pouch.rgba size is 64x64x4")
check(BerryPouchExtract.ready(memoryCache, "data/test_gba"), "BerryPouchExtract.ready reports true")

print(string.format("\n=========================================="))
if failed == 0 then
  print("ALL EXTRACTION TESTS PASSED SUCCESSFULLY!")
else
  print(string.format("EXTRACTION TESTS FAILED WITH %d ERRORS", failed))
  os.exit(1)
end
