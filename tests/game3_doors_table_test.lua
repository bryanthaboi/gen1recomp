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

local Versions = require("src.import.gba.versions")
local DoorAnimExtract = require("src.import.gba.door_anim_extract")

local TABLE_OFF = Versions.DOOR_GRAPHICS_TABLE
local STRIDE = 12

local function fakeRom(entries)
  local bytes = {}
  local function put32(off, v)
    for i = 0, 3 do
      bytes[off + i] = math.floor(v / (256 ^ i)) % 256
    end
  end
  for i, e in ipairs(entries) do
    local base = TABLE_OFF + (i - 1) * STRIDE
    put32(base, e.mid + e.sound * 0x10000 + e.size * 0x1000000)
    put32(base + 4, e.tiles or 0)
    put32(base + 8, e.pal or 0)
  end
  return {
    get = function(_, off) return bytes[off] or 0 end,
    u16 = function(self, off) return self:get(off) + self:get(off + 1) * 256 end,
    u32 = function(self, off)
      return self:get(off) + self:get(off + 1) * 256
        + self:get(off + 2) * 65536 + self:get(off + 3) * 16777216
    end,
    ptrOffset = function(_, ptr)
      if ptr < 0x08000000 or ptr >= 0x0A000000 then return nil end
      return ptr - 0x08000000
    end,
    clearCache = function() end,
  }
end

local function fakeCache()
  local files = {}
  return {
    files = files,
    write = function(_, rel, body) files[rel] = body; return true end,
    read = function(_, rel) return files[rel] end,
    exists = function(_, rel) return files[rel] ~= nil end,
  }
end

print("[test] 1. sDoorGraphics decode reads the sound and size bytes from the ROM")

local ROOT = "data/generated/gba"
local rom = fakeRom({
  { mid = 0x101, sound = 0, size = 0, tiles = 0x08100000, pal = 0x08200000 },
  { mid = 0x102, sound = 1, size = 0, tiles = 0x08100400, pal = 0x08200008 },
  { mid = 0x103, sound = 1, size = 1, tiles = 0x08100800, pal = 0x08200010 },
  { mid = 0x000, sound = 0, size = 0, tiles = 0, pal = 0 },
})
local cache = fakeCache()
local ok = DoorAnimExtract.run(rom, cache, { cacheRoot = ROOT })
check(ok == true, "run() extracted the synthetic table")

local body = cache.files[ROOT .. "/doors/manifest.lua"]
check(type(body) == "string" and #body > 0, "run() wrote doors/manifest.lua")
local manifest = body and assert(loadstring(body))()
check(type(manifest) == "table", "the manifest parses")

if type(manifest) == "table" then
  check(type(DoorAnimExtract.MANIFEST_VERSION) == "number"
    and manifest.version == DoorAnimExtract.MANIFEST_VERSION,
    "the manifest carries the extractor's manifest version")
  check(manifest.count == 3, "the walk stopped at the null tiles pointer, count=" .. tostring(manifest.count))
  local e = manifest.by_mid or {}
  check(e[0x101] ~= nil and e[0x101].sound == "normal" and e[0x101].sound_type == 0,
    "sound byte 0 decodes to normal, got " .. tostring(e[0x101] and e[0x101].sound))
  check(e[0x102] ~= nil and e[0x102].sound == "sliding" and e[0x102].sound_type == 1,
    "sound byte 1 decodes to sliding, got " .. tostring(e[0x102] and e[0x102].sound))
  check(e[0x103] ~= nil and e[0x103].sound == "sliding" and e[0x103].sound_type == 1,
    "the third entry keeps its sliding sound byte")
  check(e[0x101] ~= nil and e[0x101].size == "1x1" and e[0x101].size_type == 0,
    "size byte 0 decodes to 1x1")
  check(e[0x103] ~= nil and e[0x103].size == "1x2" and e[0x103].size_type == 1,
    "size byte 1 decodes to 1x2")
  check(type(manifest.entries) == "table" and #manifest.entries == 3
    and manifest.entries[1].index == 0 and manifest.entries[3].index == 2,
    "the manifest keeps the table order")
end

local smallName = manifest and manifest.by_mid and manifest.by_mid[0x101]
local largeName = manifest and manifest.by_mid and manifest.by_mid[0x103]
local small = smallName and cache.files[ROOT .. "/doors/" .. smallName.tile:lower() .. ".rgba"]
check(type(small) == "string" and #small == 16 * 48 * 4,
  "a 1x1 door bakes 16x48 RGBA, got " .. tostring(small and #small))
local large = largeName and cache.files[ROOT .. "/doors/" .. largeName.tile:lower() .. ".rgba"]
check(type(large) == "string" and #large == 16 * 96 * 4,
  "a 1x2 door bakes 16x96 RGBA, got " .. tostring(large and #large))

print("[test] 2. ready() repairs a cache written before the sound byte was read")
check(DoorAnimExtract.ready(cache, ROOT) == false,
  "ready() is false while the synthetic cache holds fewer entries than the cart")
check(DoorAnimExtract.ready(fakeCache(), ROOT) == false, "ready() is false on an empty cache")
local legacy = fakeCache()
legacy:write(ROOT .. "/doors/manifest.lua", [[
return {
  doors = {},
  by_mid = {
    [347] = { mid = 347, tile = "SlidingDouble", sound = "sliding", size = "1x1", tileset = "primary" },
  }
}
]])
check(DoorAnimExtract.ready(legacy, ROOT) == false,
  "ready() is false for a manifest with no sound_type")

print("[test] 3. doors.lua holds no metatile table")
local src = assert(io.open("src/core/game3/doors.lua", "r"))
local doorsSrc = src:read("*a")
src:close()
check(not doorsSrc:find("DEFAULT_BY_MID", 1, true),
  "doors.lua has no builtin by_mid table")
local literals = 0
for _ in doorsSrc:gmatch("%[0[xX]%x%x%x%]%s*=") do literals = literals + 1 end
check(literals == 0, "doors.lua has no metatile id literals, found " .. literals)
check(not doorsSrc:find("SlidingDouble", 1, true) or doorsSrc:find("tileName == \"SlidingDouble\"", 1, true) ~= nil,
  "doors.lua names SlidingDouble only where it branches on the cached tile")

print("[test] 4. the baked cache table")
local Cache = require("tests.game3_cache")
local root = Cache.mount("doors/manifest.lua", { native = true })
if not root then
  print("[skip] baked door table: " .. tostring(Cache.reason))
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end
print("[info] FireRed cache at " .. root)

local f = assert(io.open(root .. "/doors/manifest.lua", "rb"))
local bakedSrc = f:read("*a")
f:close()
local baked = assert(loadstring(bakedSrc))()
check(type(baked.by_mid) == "table", "the baked manifest has a by_mid table")

local n = 0
for _, entry in pairs(baked.by_mid or {}) do
  n = n + 1
  if entry.sound ~= "normal" and entry.sound ~= "sliding" then
    check(false, "entry " .. tostring(entry.mid) .. " has sound " .. tostring(entry.sound))
  end
end
check(n == Versions.DOOR_GRAPHICS_COUNT,
  "the baked table holds every sDoorGraphics entry, got " .. n)

-- src/field_door.c:253
local double = (baked.by_mid or {})[0x15B]
check(double ~= nil and double.tile == "SlidingDouble" and double.sound == "sliding"
  and double.size == "1x1",
  "metatile 0x15B is the sliding double door")
-- src/field_door.c:252
local single = (baked.by_mid or {})[0x062]
check(single ~= nil and single.sound == "sliding", "metatile 0x062 is a sliding door")
-- src/field_door.c:256
local wooden = (baked.by_mid or {})[0x299]
check(wooden ~= nil and wooden.sound == "normal", "metatile 0x299 is a normal door")

if baked.version == DoorAnimExtract.MANIFEST_VERSION then
  local typed = true
  for _, entry in pairs(baked.by_mid) do
    if type(entry.sound_type) ~= "number" then typed = false end
  end
  check(typed, "every baked entry carries the ROM sound byte")
  check(DoorAnimExtract.ready(Cache.cache(), root) == true,
    "ready() accepts the baked cache")
else
  print("[info] this cache predates the sound byte extraction; the importer repairs it on the next run")
end

print("[test] 5. the engine resolves a door from the cache table")
local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local Doors = require("src.core.game3.doors")
local entry = Doors.getDoorEntryAt("VIRIDIAN_CITY", 36, 10)
check(entry ~= nil and entry.tile == "SlidingDouble",
  "the Viridian Gym door cell resolves to SlidingDouble, got " .. tostring(entry and entry.tile))
local snd, kind = Doors.getSoundForWarp("VIRIDIAN_CITY", 36, 10, "MAP_VIRIDIAN_CITY_GYM", true)
check(snd == Doors.SOUND_SLIDING and kind == "SlidingDouble",
  "the Viridian Gym door plays SE_SLIDING_DOOR")
local house = Doors.getDoorEntryAt("VIRIDIAN_CITY", 25, 11)
check(house ~= nil and house.sound == "normal",
  "the Viridian wooden house door is a normal door, got " .. tostring(house and house.sound))
local hsnd = Doors.getSoundForWarp("VIRIDIAN_CITY", 25, 11, "MAP_VIRIDIAN_CITY_HOUSE", true)
check(hsnd == Doors.SOUND_NORMAL, "the wooden house door plays SE_DOOR")
-- src/field_door.c:510
local dojo = Doors.getDoorEntryAt("FR_SAFFRON_CITY", 40, 12)
check(dojo == nil, "the Saffron Dojo metatile is not in the cart's door table")
local dsnd, dkind = Doors.getSoundForWarp("FR_SAFFRON_CITY", 40, 12, "MAP_SAFFRON_CITY_DOJO", true)
check(dsnd == Doors.SOUND_SLIDING and dkind == nil,
  "an unlisted door metatile falls to SE_SLIDING_DOOR with no animation")

print("[test] 6. the metatile behaviour decides, not the tileset name")
local bundle = Cache.bundle("doors/manifest.lua", { native = true })
if not bundle then
  print("[skip] behaviour gate: " .. tostring(Cache.reason))
else
  local silph = Doors.getDoorEntryAt("FR_SAFFRON_CITY", 33, 30)
  check(silph ~= nil and silph.tile == "SilphCo",
    "the Silph Co door resolves on a map whose pair is a rom-named tileset, got "
      .. tostring(silph and silph.tile))
  local ssnd = Doors.getSoundForWarp("FR_SAFFRON_CITY", 33, 30, "MAP_SILPH_CO_1F", true)
  check(ssnd == Doors.SOUND_SLIDING, "the Silph Co door plays SE_SLIDING_DOOR")
  local dojo2 = Doors.getDoorEntryAt("FR_SAFFRON_CITY", 40, 12)
  check(dojo2 == nil, "the Dojo warp cell stays out of the door table")
  local floor = Doors.getDoorEntryAt("FR_VIRIDIAN_CITY", 36, 11)
  check(floor == nil, "the cell below the gym door is not a door")
end

print("[test] 7. an unlisted door metatile animates nothing and holds nothing up")
love = love or {}
love.graphics = love.graphics or { rectangle = function() end, setColor = function() end }
local realEntryAt = Doors.getDoorEntryAt
local lookups = 0
Doors.getDoorEntryAt = function(...)
  lookups = lookups + 1
  return realEntryAt(...)
end
local walked = false
local dojoAnim = Doors.open("FR_SAFFRON_CITY", 40, 12,
  { destMap = "MAP_SAFFRON_CITY_DOJO", playSound = false }, function() walked = true end)
check(dojoAnim ~= nil and dojoAnim.tile == nil,
  "the Dojo doorway anim carries no door tile, got " .. tostring(dojoAnim and dojoAnim.tile))
lookups = 0
for _ = 1, 30 do Doors.draw(40 * 16 - 100, 12 * 16 - 60) end
-- src/field_door.c:457
check(lookups == 0,
  "draw never resolves the door again, got " .. lookups .. " lookups in 30 frames")
-- src/field_fadetransition.c:757
Doors.update(1)
check(walked == true, "the walk starts on the first tick, as a -1 from FieldAnimateDoorOpen does")
Doors.getDoorEntryAt = realEntryAt
Doors.reset()

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)
