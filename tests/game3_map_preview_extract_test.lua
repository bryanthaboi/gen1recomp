#!/usr/bin/env luajit
-- Location preview screen (sMapPreviewScreenData) extraction & screen logic.
-- Source of truth: pret/pokefirered src/map_preview_screen.c + src/region_map.c.
--
-- The ROM section SKIPs when no FireRed dump is present, mirroring
-- tests/game3_tm_case_berry_pouch_extract_test.lua.

package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

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
local BgBake = require("src.import.gba.bg_bake")
local RegionMapTables = require("src.import.gba.region_map_tables")
local MapPreviewExtract = require("src.import.gba.map_preview_extract")
local Extract = require("src.import.gba.extract_island1")
local MapPreviewScreen = require("src.ui.game3.map_preview_screen")

print("=== 1. Versions offsets ===")
check(Versions.MAP_PREVIEW_SCREEN_DATA == 0x43E9E8, "MAP_PREVIEW_SCREEN_DATA is 0x43E9E8")
check(Versions.MAP_PREVIEW_COUNT == 28, "MAP_PREVIEW_COUNT is 28")
check(Versions.MAP_PREVIEW_ENTRY_SIZE == 16, "MAP_PREVIEW_ENTRY_SIZE is 16")
check(Versions.MAP_PREVIEW_TYPE_CAVE == 0 and Versions.MAP_PREVIEW_TYPE_FOREST == 1,
  "MPS_TYPE_CAVE/FOREST are 0/1")
check(Versions.MAPSEC_NAMES == 0x3EECFC, "MAPSEC_NAMES is 0x3EECFC")
check(Versions.MAPSEC_NAME_POINTERS == 0x3F1CAC, "MAPSEC_NAME_POINTERS is 0x3F1CAC")
check(Versions.MAPSEC_FIRST == 88 and Versions.MAPSEC_LAST == 196, "mapsec range is 88..196")
check(Versions.MAPSEC_COUNT == 109, "MAPSEC_COUNT is 109")
check(Versions.DUNGEON_INFO == 0x3F1B3C, "DUNGEON_INFO is 0x3F1B3C")
check(Versions.DUNGEON_INFO_COUNT == 19, "DUNGEON_INFO_COUNT is 19")
check(Versions.DUNGEON_INFO_ENTRY_SIZE == 12, "DUNGEON_INFO_ENTRY_SIZE is 12")

print("\n=== 2. Extractor constants ===")
check(MapPreviewExtract.WIDTH == 240 and MapPreviewExtract.HEIGHT == 160, "artwork is 240x160")
check(MapPreviewExtract.PALETTE_BANK_LO == 13 and MapPreviewExtract.PALETTE_BANK_HI == 14,
  "palette banks are 13 and 14")
check(MapPreviewExtract.PALETTE_COLORS == 32 and MapPreviewExtract.PALETTE_BANKS == 2,
  "0x40 palette bytes split into 2 banks")
check(MapPreviewExtract.TYPE_CAVE == 0 and MapPreviewExtract.TYPE_FOREST == 1,
  "extractor cave/forest types match Versions")
check(MapPreviewScreen.FADE_OUT_FRAMES == 48, "fade-out lasts 48 frames")
check(MapPreviewScreen.DURATION_FIRST_VISIT == 120, "first visit holds 120 frames")
check(MapPreviewScreen.DURATION_REVISIT == 40, "revisit holds 40 frames")

print("\n=== 3. BGR555 -> RGB8 ===")
local r, g, b = BgBake.bgr555ToRgb8(0)
check(r == 0 and g == 0 and b == 0, "0x0000 decodes to black")
r, g, b = BgBake.bgr555ToRgb8(0x7FFF)
check(r == 255 and g == 255 and b == 255, "0x7FFF decodes to white")
r, g, b = BgBake.bgr555ToRgb8(0x001F)
check(r == 255 and g == 0 and b == 0, "0x001F decodes to red")

print("\n=== 4. Screen logic (synthetic manifest) ===")
local SYNTH_ROOT = "data/test_gba_map_preview"
local synthCache = {
  files = {},
  write = function(self, path, bytes) self.files[path] = bytes; return true end,
  exists = function(self, path) return self.files[path] ~= nil end,
  read = function(self, path) return self.files[path] end,
}
local FOREST_SEC, CAVE_SEC = 176, 100
local ARTWORK = 999
synthCache:write(SYNTH_ROOT .. "/map_preview/manifest.lua", ([[
return {
  format_version = 2,
  width = 240, height = 160,
  type_cave = 0, type_forest = 1,
  artwork_count = 1, entry_count = 2,
  name_window = { fill = { 247, 247, 255 }, fg = { 247, 247, 255 },
                  shadow = { 0, 0, 0 }, bg = { 214, 214, 214 } },
  entries = {
    { mapsec = %d, name = "BERRY FOREST", type = 1, flagId = 2231, artwork = %d },
    { mapsec = %d, name = "ROCK TUNNEL", type = 0, flagId = 2200, artwork = %d },
  },
  by_mapsec = { [%d] = 1, [%d] = 2 },
}
]]):format(FOREST_SEC, ARTWORK, CAVE_SEC, ARTWORK, FOREST_SEC, CAVE_SEC))
synthCache:write(SYNTH_ROOT .. "/map_preview/" .. ARTWORK .. ".rgba", string.rep("\0", 240 * 160 * 4))

Extract.CACHE_ROOT = SYNTH_ROOT
MapPreviewScreen.install(synthCache)

check(MapPreviewScreen.ready(), "screen reports ready from a synthetic manifest")
check(MapPreviewScreen.has(FOREST_SEC), "has() matches any type when type is nil")
check(MapPreviewScreen.has(FOREST_SEC, MapPreviewExtract.TYPE_FOREST), "Berry Forest is a forest preview")
check(not MapPreviewScreen.has(FOREST_SEC, MapPreviewExtract.TYPE_CAVE), "Berry Forest is not a cave preview")
check(MapPreviewScreen.has(CAVE_SEC, MapPreviewExtract.TYPE_CAVE), "Rock Tunnel is a cave preview")
check(not MapPreviewScreen.has(4242), "unknown mapsec has no preview")

-- MapPreview_SetFlag captures the pre-visit state: first visit 120, revisit 40.
MapPreviewScreen.hasVisitedBefore = false
check(MapPreviewScreen.durationFor(FOREST_SEC) == 40, "forest without a prior visit holds 40")
MapPreviewScreen.setVisitedFlag(2231, false)
check(MapPreviewScreen.hasVisitedBefore == true, "setVisitedFlag records a first visit")
check(MapPreviewScreen.durationFor(FOREST_SEC) == 120, "forest first visit holds 120")
MapPreviewScreen.setVisitedFlag(2231, true)
check(MapPreviewScreen.hasVisitedBefore == false, "setVisitedFlag records a revisit")
check(MapPreviewScreen.durationFor(FOREST_SEC) == 40, "forest revisit holds 40")
check(MapPreviewScreen.durationFor(CAVE_SEC) == 120, "cave with an unset flag holds 120")
check(MapPreviewScreen.durationFor(4242) == 0, "unknown mapsec holds 0")

check(MapPreviewScreen.show(CAVE_SEC) == false, "show() refuses a cave preview by default")
check(MapPreviewScreen.show(FOREST_SEC) == true, "show() accepts a forest preview")
check(MapPreviewScreen.isActive(), "screen is active after show()")
check(MapPreviewScreen.mapsec() == FOREST_SEC, "active mapsec is Berry Forest")
MapPreviewScreen.dismiss()
check(not MapPreviewScreen.isActive(), "dismiss() clears the active screen")

print("\n=== 5. Extraction from FireRed ROM ===")

local romPath = "1636 - Pokemon Fire Red (U)(Squirrels).gba"
local f = io.open(romPath, "rb")
if not f then
  print("[SKIP] ROM not found at " .. romPath)
else
  local romData = f:read("*all")
  f:close()

  local rom = {
    size = #romData,
    get = function(_, i) return romData:byte(i + 1) or 0 end,
  }

  local previewBase = RegionMapTables.locatePreviewTable(
    function(i) return rom:get(i) end, rom.size)
  check(previewBase == Versions.MAP_PREVIEW_SCREEN_DATA,
    ("sMapPreviewScreenData located at 0x%X"):format(previewBase or -1))

  local tables = assert(RegionMapTables.load(rom))
  check(#tables.previews == 28, "28 sMapPreviewScreenData entries decoded")
  check(tables.namesVerified, "sMapsecName_* pointers match sRegionMapSectionIdToName")
  check(#tables.dungeonInfo == 19, "19 sDungeonInfo entries decoded")
  check(tables.names[126] == "VIRIDIAN FOREST", "mapsec 126 is VIRIDIAN FOREST")
  check(tables.names[88] == "PALLET TOWN", "mapsec 88 is PALLET TOWN")
  check((tables.names[196] or ""):len() > 0, "mapsec 196 is non-empty")

  local forest, cave = 0, 0
  local flagOwners = {}
  for _, e in ipairs(tables.previews) do
    if e.type == Versions.MAP_PREVIEW_TYPE_FOREST then forest = forest + 1 else cave = cave + 1 end
    flagOwners[e.flagId] = flagOwners[e.flagId] or {}
    table.insert(flagOwners[e.flagId], e.mapsec)
  end
  check(forest == 8, "8 forest-type previews")
  check(cave == 20, "20 cave-type previews")
  check(#(flagOwners[2231] or {}) == 2, "MPS_ROCKET_WAREHOUSE and BERRY FOREST share flag 2231")

  local plan = assert(MapPreviewExtract.build(rom))
  check(#plan.entries == 28, "build() produces 28 entries")
  check(plan.artworkCount == 21, "build() deduplicates 28 entries into 21 artworks")
  check(plan.nameCount == 109, "build() decodes 109 mapsec names")
  check(#plan.dungeonInfo == 19, "build() decodes 19 dungeon entries")
  check(plan.dungeonInfo[1].mapsec == 126 and plan.dungeonInfo[1].name == "VIRIDIAN FOREST",
    "dungeon entry 1 is Viridian Forest")
  check(plan.dungeonInfo[1].desc:find("\n", 1, true) ~= nil,
    "dungeon flavour text keeps its ROM line breaks")
  check(plan.nameWindow and plan.nameWindow.fg[1] == plan.nameWindow.fill[1],
    "name window fill and fg share palette bank 14 entry 1")
  check(plan.nameWindow.shadow[1] < plan.nameWindow.fg[1],
    "name window shadow is darker than its fg")

  local files = 0
  for name, bytes in pairs(plan.files) do
    files = files + 1
    check(#bytes == 240 * 160 * 4, "artwork " .. name .. " is 240x160x4")
  end
  check(files == 21, "build() returns 21 artwork files")

  local memoryCache = {
    files = {},
    write = function(self, path, bytes) self.files[path] = bytes; return true end,
    exists = function(self, path) return self.files[path] ~= nil end,
    read = function(self, path) return self.files[path] end,
  }
  local ROM_ROOT = "data/test_gba_map_preview_rom"
  local ok, res = MapPreviewExtract.run(rom, memoryCache, { cacheRoot = ROM_ROOT })
  check(ok, "MapPreviewExtract.run() succeeded")
  check(res and res.artworks == 21 and res.entries == 28, "run() reports 21 artworks / 28 entries")
  check(res and res.names == 109 and res.dungeonInfo == 19, "run() reports 109 names / 19 dungeons")
  check(res and res.namesVerified == true, "run() reports verified names")
  check(memoryCache:exists(ROM_ROOT .. "/map_preview/manifest.lua"), "manifest.lua written")
  check(memoryCache:exists(ROM_ROOT .. "/region_map/names.lua"), "region_map/names.lua written")
  check(memoryCache:exists(ROM_ROOT .. "/region_map/dungeon_info.lua"), "region_map/dungeon_info.lua written")
  check(MapPreviewExtract.ready(memoryCache, ROM_ROOT), "ready() reports true after run()")

  local skipOk, skipRes = MapPreviewExtract.run(rom, memoryCache, { cacheRoot = ROM_ROOT })
  check(skipOk and skipRes and skipRes.skipped == true, "run() is a no-op when the cache is ready")

  local names = MapPreviewExtract.loadNames(memoryCache, ROM_ROOT)
  check(names and names[126] == "VIRIDIAN FOREST", "loadNames() round-trips through the cache")
  local dinfo = MapPreviewExtract.loadDungeonInfo(memoryCache, ROM_ROOT)
  check(dinfo and dinfo[126] and dinfo[126].name == "VIRIDIAN FOREST",
    "loadDungeonInfo() round-trips through the cache")

  -- Live screen against the real cache.
  Extract.CACHE_ROOT = ROM_ROOT
  MapPreviewScreen.install(memoryCache)
  MapPreviewScreen._manifest = nil
  MapPreviewScreen._manifestTried = false
  MapPreviewScreen._images = {}
  check(MapPreviewScreen.ready(), "screen loads the real manifest")
  check(MapPreviewScreen.has(126, MapPreviewExtract.TYPE_FOREST), "Viridian Forest is a forest preview")
  check(MapPreviewScreen.durationFor(126) == 40, "Viridian Forest revisit holds 40 frames")
  MapPreviewScreen.setVisitedFlag(2212, false)
  check(MapPreviewScreen.show(126) == true, "show() starts the Viridian Forest preview")
  check(MapPreviewScreen.mapsec() == 126, "active mapsec is 126")
  MapPreviewScreen.dismiss()
  check(MapPreviewScreen.has(182, MapPreviewExtract.TYPE_FOREST)
    and MapPreviewScreen.artworkFor(182) == 126,
    "Pattern Bush reuses Viridian Forest's artwork")
end

print("\n==========================================")
if failed == 0 then
  print("ALL LOCATION PREVIEW TESTS PASSED!")
else
  print(("LOCATION PREVIEW TESTS FAILED WITH %d ERRORS"):format(failed))
  os.exit(1)
end
