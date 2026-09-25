package.path = "./?.lua;./?/init.lua;" .. package.path
require("src.core.GameVersion").set("firered")

local ExtractMapEvents = require("src.import.gba.extract_map_events")
local MapTree = require("src.import.gba.map_tree")
local Versions = require("src.import.gba.versions")

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

local function fakeRom(bytes)
  local rom = { bytes = bytes }
  function rom:get(off) return self.bytes[off + 1] or 0 end
  function rom:u32(off)
    return self:get(off) + self:get(off + 1) * 256
      + self:get(off + 2) * 65536 + self:get(off + 3) * 16777216
  end
  function rom:ptrOffset(p)
    if p < 0x08000000 or p >= 0x0A000000 then return nil end
    return p - 0x08000000
  end
  return rom
end

local function putU32(bytes, off, v)
  if v < 0 then v = v + 0x100000000 end
  for i = 0, 3 do
    bytes[off + i + 1] = math.floor(v / 256 ^ i) % 256
  end
end

local ENTRIES = {
  { dirByte = 3, offset = 0, group = 3, num = 0 },
  { dirByte = 3, offset = 40, group = 3, num = 1 },
  { dirByte = 3, offset = 80, group = 3, num = 2 },
  { dirByte = 4, offset = -12, group = 3, num = 19 },
}

local bytes = {}
for i = 1, 0x100 do bytes[i] = 0 end
local HEADER, LIST = 0x10, 0x40
putU32(bytes, HEADER, #ENTRIES)
putU32(bytes, HEADER + 4, 0x08000000 + LIST)
for i, e in ipairs(ENTRIES) do
  local base = LIST + (i - 1) * 12
  bytes[base + 1] = e.dirByte
  putU32(bytes, base + 4, e.offset)
  bytes[base + 9] = e.group
  bytes[base + 10] = e.num
end
local rom = fakeRom(bytes)

print("[test] 1. ExtractMapEvents.parseConnections keeps every entry in ROM order")
local list = ExtractMapEvents.parseConnections(rom, 0x08000000 + HEADER)
check(#list == 4, "four connections survive (got " .. #list .. ")")
local wantDir = { "west", "west", "west", "east" }
for i, e in ipairs(ENTRIES) do
  local c = list[i] or {}
  check(c.dir == wantDir[i], ("entry %d dir %s"):format(i, tostring(c.dir)))
  check(c.offset == e.offset, ("entry %d offset %s"):format(i, tostring(c.offset)))
  check(c.map == Versions.frMapFor(e.group, e.num),
    ("entry %d map %s"):format(i, tostring(c.map)))
end
check(list.west == nil and list.east == nil, "no direction-keyed fields")

print("[test] 2. MapTree.parseConnections keeps every entry in ROM order")
local tree = MapTree.parseConnections(rom, 0x08000000 + HEADER, nil)
check(#tree == 4, "four census connections survive (got " .. #tree .. ")")
for i, e in ipairs(ENTRIES) do
  local c = tree[i] or {}
  check(c.dir == wantDir[i] and c.offset == e.offset
    and c.mapGroup == e.group and c.mapNum == e.num,
    ("census entry %d is %s %s %s:%s"):format(i, tostring(c.dir),
      tostring(c.offset), tostring(c.mapGroup), tostring(c.mapNum)))
end

print("[test] 3. an imported cache carries Water Path's three west entries")
local Cache = require("tests.game3_cache")
local root = Cache.root("connections.lua")
if not root then
  print("[skip] cache section: " .. tostring(Cache.reason))
else
  local ok, conns = pcall(dofile, root .. "/connections.lua")
  check(ok and type(conns) == "table", "connections.lua loads")
  local wp = ok and conns.FR_SIX_ISLAND_WATER_PATH or {}
  local want = {
    { "west", "FR_SIX_ISLAND_GREEN_PATH", 0 },
    { "west", "FR_SIX_ISLAND", 40 },
    { "west", "FR_SIX_ISLAND_RUIN_VALLEY", 80 },
  }
  check(#wp == 3, "Water Path has three connections (got " .. #wp .. ")")
  for i, w in ipairs(want) do
    local c = wp[i] or {}
    check(c.dir == w[1] and c.map == w[2] and c.offset == w[3],
      ("Water Path entry %d is %s %s %s"):format(i, tostring(c.dir),
        tostring(c.map), tostring(c.offset)))
  end
  local six = ok and conns.FR_SIX_ISLAND or {}
  check(#six == 1 and six[1].dir == "east"
    and six[1].map == "FR_SIX_ISLAND_WATER_PATH" and six[1].offset == -40,
    "Six Island keeps its one east connection")
  local total = 0
  for _, entries in pairs(ok and conns or {}) do total = total + #entries end
  check(total == 116, "every ROM connection is in the cache (got " .. total .. ")")
end

if failures > 0 then
  print(("game3_connection_list_test: %d failure(s)"):format(failures))
  os.exit(1)
end
print("game3_connection_list_test: all passed")
