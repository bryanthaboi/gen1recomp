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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local VoidFill = require("src.core.game3.void_fill")

local T = { 11, 12, 13, 14 }
local W = 21
local LAYOUTS = {
  FR_PALLET_TOWN = {
    pair = "pallet_outdoor", borderWidth = 2, borderHeight = 2,
    borderMids = { T[1], T[2], T[3], T[4] },
  },
  FR_CINNABAR_ISLAND = {
    pair = "sevii_outdoor", borderWidth = 2, borderHeight = 2,
    borderMids = { W, W, W, W },
  },
}
local lookups = 0
VoidFill.layoutFor = function(mapId)
  lookups = lookups + 1
  return LAYOUTS[mapId]
end
VoidFill.invalidate()

local function fill(mode, cx, cy, hasMid)
  return VoidFill.fillAt(mode, cx, cy, hasMid, "general")
end

print("[test] 1. mode plumbing")
eq(VoidFill.normalize("trees"), "trees", "normalize trees")
eq(VoidFill.normalize("nope"), "map", "normalize unknown -> map")
eq(VoidFill.normalize(nil), "map", "normalize nil -> map")
eq(VoidFill.cycle("map", 1), "trees", "cycle map -> trees")
eq(VoidFill.cycle("trees", 1), "water", "cycle trees -> water")
eq(VoidFill.cycle("water", 1), "black", "cycle water -> black")
eq(VoidFill.cycle("black", 1), "map", "cycle black wraps to map")
eq(VoidFill.cycle("map", -1), "black", "cycle map backwards -> black")
eq(VoidFill.label("trees"), "TREES", "label trees")
eq(VoidFill.label("black"), "BLACK", "label black")

print("[test] 2. map / black branches")
eq(VoidFill.fillAt("map", 0, 0), nil, "map fill is nil")
eq(VoidFill.fillAt("map", 7, -3), nil, "map fill is nil off-origin")
eq(VoidFill.fillAt("black", 0, 0), false, "black fill is false")
eq(VoidFill.fillAt("black", -5, 9), false, "black fill is false off-origin")

print("[test] 3. tree border is the cart 2x2 (PalletTown/border.bin)")
eq(fill("trees", 0, 0), T[1], "trees (0,0)")
eq(fill("trees", 1, 0), T[2], "trees (1,0)")
eq(fill("trees", 0, 1), T[3], "trees (0,1)")
eq(fill("trees", 1, 1), T[4], "trees (1,1)")
eq(fill("trees", 2, 2), T[1], "trees (2,2) wraps to (0,0)")
eq(fill("trees", 43, 16), T[2], "trees (43,16) odd/even")

print("[test] 4. negative coords wrap non-negative")
eq(fill("trees", -1, -1), T[4], "trees (-1,-1)")
eq(fill("trees", -2, -2), T[1], "trees (-2,-2)")
eq(fill("trees", -1, 0), T[2], "trees (-1,0)")
eq(fill("trees", 0, -1), T[3], "trees (0,-1)")

print("[test] 5. water border is one metatile (CinnabarIsland/border.bin)")
for _, xy in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { -3, 7 }, { 12, -9 } }) do
  eq(fill("water", xy[1], xy[2]), W,
    string.format("water (%d,%d)", xy[1], xy[2]))
end

print("[test] 6. availability gate falls through to the map's own border")
eq(fill("trees", 0, 0, function() return false end), nil,
  "trees gated off when the pair has no tree mids")
eq(fill("water", 0, 0, function() return false end), nil,
  "water gated off when the pair lacks the water mid")
local partial = { [T[1]] = true, [T[2]] = true, [T[3]] = true }
eq(fill("trees", 1, 1, function(m) return partial[m] == true end), nil,
  "no partial tree when one quadrant is missing")
eq(fill("trees", 1, 1, function() return true end), T[4],
  "gate passes when every mid is packed")
eq(VoidFill.fillAt("black", 0, 0, function() return false end), false,
  "gate does not apply to black")

print("[test] 7. regression: the fill is not a single metatile (#2309)")
local seen, n = {}, 0
for cy = 0, 1 do
  for cx = 0, 1 do
    local mid = fill("trees", cx, cy)
    if not seen[mid] then
      seen[mid] = true
      n = n + 1
    end
  end
end
eq(n, 4, "a 2x2 tree window yields 4 distinct mids")
eq(VoidFill.borderFor("trees").w, 2, "tree border width")
eq(VoidFill.borderFor("trees").h, 2, "tree border height")
check(VoidFill.midFor == nil, "modal-scan midFor is gone")
check(VoidFill.TREE_BORDER == nil and VoidFill.WATER_BORDER == nil,
  "no literal border tables in the module")

print("[test] 8. primary tileset gate (building pairs never get General mids)")
local all = function() return true end
eq(VoidFill.fillAt("trees", 0, 0, all, "building"), nil,
  "trees on a building primary with every mid packed -> nil")
eq(VoidFill.fillAt("water", 0, 0, all, "building"), nil,
  "water on a building primary with every mid packed -> nil")
eq(VoidFill.fillAt("trees", 0, 0, all, nil), nil, "unknown primary fails closed")
eq(VoidFill.fillAt("trees", 0, 0, all), nil, "omitted primary fails closed")
eq(VoidFill.fillAt("trees", 0, 0, all, "general"), T[1], "general primary passes")
eq(VoidFill.fillAt("black", 0, 0, all, "building"), false, "black ignores the primary")
eq(VoidFill.primaryFor("player_house"), "building", "primaryFor player_house")
eq(VoidFill.primaryFor("pallet_outdoor"), "general", "primaryFor pallet_outdoor")
eq(VoidFill.primaryFor("general__rom_082d4af4"), "general", "primaryFor auto general pair")
eq(VoidFill.primaryFor("building__rom_082d4bcc"), "building", "primaryFor auto building pair")
eq(VoidFill.primaryFor("no_such_pair"), nil, "primaryFor unknown pair")
eq(VoidFill.primaryFor(nil), nil, "primaryFor nil")

print("[test] 9. borders come from the cached layouts, resolved once")
VoidFill.invalidate()
lookups = 0
for cy = 0, 9 do
  for cx = 0, 9 do fill("trees", cx, cy, all) end
end
eq(lookups, 1, "one layout lookup for 100 cells")
eq(VoidFill.borderFromLayout(nil), nil, "no layout -> no border")
eq(VoidFill.borderFromLayout({
  pair = "player_house", borderWidth = 1, borderHeight = 1, borderMids = { T[1] },
}), nil, "a building-primary source layout is refused")
eq(VoidFill.borderFromLayout({
  pair = "pallet_outdoor", borderWidth = 1, borderHeight = 1,
  borderMids = { VoidFill.PRIMARY_MIDS },
}), nil, "a secondary-tileset mid is refused")
LAYOUTS.FR_PALLET_TOWN = nil
VoidFill.invalidate()
lookups = 0
eq(fill("trees", 0, 0, all), nil, "missing source layout falls through")
eq(fill("trees", 1, 0, all), nil, "missing source layout falls through again")
eq(lookups, 1, "the miss is cached until invalidate")
local realLayoutFor = VoidFill.layoutFor
VoidFill.layoutFor = function() return nil, true end
VoidFill.invalidate()
eq(fill("trees", 0, 0, all), nil, "no game yet falls through")
VoidFill.layoutFor = realLayoutFor
LAYOUTS.FR_PALLET_TOWN = {
  pair = "pallet_outdoor", borderWidth = 2, borderHeight = 2,
  borderMids = { T[1], T[2], T[3], T[4] },
}
eq(fill("trees", 0, 0, all), T[1], "a pending lookup is not cached as a miss")

print("[test] 10. cached Pallet / Cinnabar borders are usable (skipped without cache)")
local root = os.getenv("HOME")
  .. "/Library/Application Support/LOVE/firered-sep20/firered/data/generated/gba"
local function readAll(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local blob = readAll(root .. "/native/layouts/FR_PALLET_TOWN.mid")
if not blob then
  print("[skip] no firered-sep20 cache; canonical mids unverified against ROM")
else
  local NativePack = require("src.import.gba.native_pack")
  local decoded = NativePack.decodeMidLayout(blob)
  check(decoded ~= nil, "decoded FR_PALLET_TOWN.mid")
  local Versions = require("src.import.gba.versions")
  local function pairOf(mapId)
    local spec = Versions.MAPS and Versions.MAPS[mapId]
    if spec and spec.pair then return spec.pair end
    local NATIVE = root .. "/native/manifest.lua"
    local chunk = loadfile(NATIVE)
    local manifest = chunk and chunk() or {}
    local info = manifest.layouts and manifest.layouts[mapId]
    return info and info.pair
  end
  if decoded then
    decoded.pair = pairOf("FR_PALLET_TOWN")
    local b = VoidFill.borderFromLayout(decoded)
    check(b ~= nil, "Pallet border accepted as a General border")
    if b then
      eq(b.w, 2, "Pallet border width")
      eq(b.h, 2, "Pallet border height")
      local distinct, saw = 0, {}
      for _, mid in ipairs(b.mids) do
        if not saw[mid] then saw[mid] = true; distinct = distinct + 1 end
      end
      eq(distinct, 4, "Pallet border is four distinct metatiles")
    end
  end
  local cin = readAll(root .. "/native/layouts/FR_CINNABAR_ISLAND.mid")
  if cin then
    local d2 = NativePack.decodeMidLayout(cin)
    if d2 then
      d2.pair = pairOf("FR_CINNABAR_ISLAND")
      local b2 = VoidFill.borderFromLayout(d2)
      check(b2 ~= nil, "Cinnabar border accepted as a General border")
      if b2 then
        for i = 2, #b2.mids do
          eq(b2.mids[i], b2.mids[1], "Cinnabar border is uniform [" .. i .. "]")
        end
      end
    end
  end
  local house = readAll(root .. "/native/layouts/FR_PLAYERS_HOUSE_1F.mid")
  if house then
    local d3 = NativePack.decodeMidLayout(house)
    if d3 then
      d3.pair = pairOf("FR_PLAYERS_HOUSE_1F")
      eq(VoidFill.primaryFor(d3.pair), "building", "player's house primary is building")
      eq(VoidFill.borderFromLayout(d3), nil, "player's house border is refused as a source")
    end
  end
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
