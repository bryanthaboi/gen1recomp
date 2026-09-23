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

local RegionMapExtract = require("src.import.gba.region_map_extract")
local MultichoiceExtract = require("src.import.gba.multichoice_extract")

print("[test] 1. extractor readiness contract")
check(type(RegionMapExtract.run) == "function", "region_map_extract has a run()")
check(type(RegionMapExtract.ready) == "function", "region_map_extract has a ready()")
check(#RegionMapExtract.FILES == 28, "region_map_extract names 28 baked files")

local function stubCache(present)
  return {
    read = function(_, rel)
      if present[rel] then return string.rep("x", 4096) end
      return nil
    end,
  }
end
local ROOT = "data/generated/gba"
local all = {}
for _, name in ipairs(RegionMapExtract.FILES) do
  all[ROOT .. "/region_map/" .. name] = true
end
check(RegionMapExtract.ready(stubCache(all), ROOT) == true,
  "ready() is true when every file is baked")
for _, name in ipairs(RegionMapExtract.FILES) do
  local missing = {}
  for k, v in pairs(all) do missing[k] = v end
  missing[ROOT .. "/region_map/" .. name] = nil
  check(RegionMapExtract.ready(stubCache(missing), ROOT) == false,
    "ready() is false without " .. name)
end
check(MultichoiceExtract.ready(stubCache({}), ROOT) == false,
  "multichoice ready() is false on an empty cache")
check(MultichoiceExtract.ready({
  read = function() return "return { [0] = { count = 2, labels = { \"YES\", \"NO\" } } }" end,
}, ROOT) == true, "multichoice ready() is true once the list table is cached")

print("[test] 2. baked assets in an imported cache")
local Cache = require("tests.game3_cache")
local root = Cache.root("region_map/extract_status.json")
if not root then
  print("[skip] region map assets: " .. tostring(Cache.reason))
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end
print("[info] FireRed cache at " .. root)

local function readFile(rel)
  local f = io.open(root .. "/" .. rel, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function pngSize(data)
  if type(data) ~= "string" or #data < 24 or data:sub(1, 8) ~= "\137PNG\r\n\026\n" then
    return nil
  end
  local function be32(at)
    local a, b, c, d = data:byte(at, at + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return be32(17), be32(21)
end

local EXPECT = {
  ["kanto_map.png"] = { 240, 160 },
  ["sevii123_map.png"] = { 240, 160 },
  ["sevii45_map.png"] = { 240, 160 },
  ["sevii67_map.png"] = { 240, 160 },
  ["frame_normal.png"] = { 240, 160 },
  ["frame_fly.png"] = { 240, 160 },
  ["switch_menu_123.png"] = { 240, 160 },
  ["switch_menu_all.png"] = { 240, 160 },
  ["switch_button.png"] = { 24, 24 },
  ["navel_rock_patch.png"] = { 24, 16 },
  ["birth_island_patch.png"] = { 24, 24 },
  ["switch_cursor_left.png"] = { 32, 64 },
  ["switch_cursor_right.png"] = { 32, 64 },
  ["edge_top_left.png"] = { 32, 64 },
  ["edge_top_right.png"] = { 32, 64 },
  ["edge_mid_left.png"] = { 32, 64 },
  ["edge_mid_right.png"] = { 32, 64 },
  ["edge_bottom_left.png"] = { 32, 64 },
  ["edge_bottom_right.png"] = { 32, 64 },
  ["cursor.png"] = { 16, 32 },
  ["fly_icon.png"] = { 16, 32 },
  ["dungeon_icon.png"] = { 8, 8 },
  ["dungeon_icon_visited.png"] = { 8, 8 },
  ["player_red.png"] = { 16, 16 },
  ["player_leaf.png"] = { 16, 16 },
}
for _, name in ipairs(RegionMapExtract.FILES) do
  if not name:find("%.png$") then goto continue end
  local data = readFile("region_map/" .. name)
  local w, h = pngSize(data)
  local want = EXPECT[name]
  check(w == want[1] and h == want[2], string.format(
    "region_map/%s is %sx%s (want %dx%d)", name, tostring(w), tostring(h), want[1], want[2]))
  ::continue::
end

-- pokefirered/src/region_map.c:790 sAnim_DungeonIconVisited is frame 1, :795 frame 0
local frame0 = readFile("region_map/dungeon_icon.rgba")
local frame1 = readFile("region_map/dungeon_icon_visited.rgba")
check(frame0 and #frame0 == 8 * 8 * 4, "dungeon_icon.rgba is one 8x8 frame")
check(frame1 and #frame1 == 8 * 8 * 4, "dungeon_icon_visited.rgba is one 8x8 frame")
check(frame0 ~= frame1, "the visited marker is the second frame of the icon sheet")
if frame0 and frame1 then
  local function opaque(blob)
    local n = 0
    for i = 4, #blob, 4 do
      if blob:byte(i) == 255 then n = n + 1 end
    end
    return n
  end
  check(opaque(frame1) > opaque(frame0), string.format(
    "the visited ring paints more of the cell than the unvisited blob (%d > %d)",
    opaque(frame1), opaque(frame0)))
end

local mapSections = readFile("region_map/map_sections.lua")
check(type(mapSections) == "string" and #mapSections > 100,
  "region_map/map_sections.lua is in the cache")
if mapSections then
  local chunk = loadstring(mapSections)
  local parsed = chunk and chunk()
  check(type(parsed) == "table" and type(parsed.sections) == "table",
    "map_sections.lua parses to a section table")
  local pallet = parsed and parsed.sections and parsed.sections[88]
  check(pallet and pallet.id == "MAPSEC_PALLET_TOWN" and pallet.name == "PALLET TOWN",
    "mapsec 88 is PALLET TOWN (" .. tostring(pallet and pallet.name) .. ")")
end

local multichoice = readFile("scripts/multichoice.lua")
check(type(multichoice) == "string" and #multichoice > 100,
  "scripts/multichoice.lua is in the cache")
if multichoice then
  local chunk = loadstring(multichoice)
  local lists = chunk and chunk()
  check(type(lists) == "table" and type(lists[0]) == "table",
    "multichoice.lua parses to a list table")
  local yesNo = lists and lists[0]
  check(yesNo and yesNo.labels and yesNo.labels[1] == "YES" and yesNo.labels[2] == "NO",
    "list 0 is YES / NO")
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
