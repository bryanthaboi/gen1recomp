package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Coll = require("src.core.CollPermissions")
local Permissions = require("src.world.gen2.Permissions")
local NativePack = require("src.import.gba.native_pack")

local function sourceOf(rel)
  local f = io.open(rel, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

do
  local pack = sourceOf("src/import/gba/native_pack.lua")
  check(pack ~= nil, "native_pack.lua is readable")
  check(pack:find('require("src.world', 1, true) == nil,
    "native_pack no longer requires anything under src/world (I9 edge removed)")

  local neutral = sourceOf("src/core/CollPermissions.lua")
  check(neutral ~= nil, "CollPermissions.lua is readable")
  check(neutral:find("require(", 1, true) == nil,
    "CollPermissions has no requires at all (neutral module)")
  check(neutral:find("src.world", 1, true) == nil, "CollPermissions never mentions src.world")

  local island = sourceOf("src/import/gba/extract_island1.lua")
  check(island ~= nil and island:find('require("src.world', 1, true) == nil,
    "extract_island1 still has no src.world require (the edge was not moved here)")

  local perms = sourceOf("src/world/gen2/Permissions.lua")
  check(perms ~= nil and perms:find("local TABLE", 1, true) == nil,
    "the permission table no longer lives in the gen2 world module")
end

eq(Coll.LAND, Permissions.LAND, "LAND matches")
eq(Coll.WATER, Permissions.WATER, "WATER matches")
eq(Coll.WALL, Permissions.WALL, "WALL matches")
check(Permissions.of == Coll.of, "Permissions.of is the re-exported function")
check(Permissions.isWalkable == Coll.isWalkable, "isWalkable is re-exported")
check(Permissions.isLedge == Coll.isLedge, "isLedge is re-exported")

local mismatches = 0
local cases = { -1, -256, 0 }
for b = 0, 255 do cases[#cases + 1] = b end
cases[#cases + 1] = 256
cases[#cases + 1] = 257
cases[#cases + 1] = 0x1FF
for _, c in ipairs(cases) do
  if Coll.of(c) ~= Permissions.of(c) then mismatches = mismatches + 1 end
  if Coll.isWalkable(c) ~= Permissions.isWalkable(c) then mismatches = mismatches + 1 end
  if Coll.isLedge(c) ~= Permissions.isLedge(c) then mismatches = mismatches + 1 end
  if Coll.isLand(c) ~= Permissions.isLand(c) then mismatches = mismatches + 1 end
  if Coll.isWater(c) ~= Permissions.isWater(c) then mismatches = mismatches + 1 end
  if Coll.isWall(c) ~= Permissions.isWall(c) then mismatches = mismatches + 1 end
end
if Coll.of(nil) ~= Permissions.of(nil) then mismatches = mismatches + 1 end
if Coll.isWalkable(nil) ~= Permissions.isWalkable(nil) then mismatches = mismatches + 1 end
if Coll.isLedge(nil) ~= Permissions.isLedge(nil) then mismatches = mismatches + 1 end
eq(mismatches, 0, "CollPermissions and Permissions agree on every tested byte")

eq(Coll.of(0), Coll.LAND, "coll 0 is LAND")
check(Coll.isWalkable(0) == true, "coll 0 is walkable")
eq(Coll.of(0x07), Coll.WALL, "coll 0x07 is WALL (row 1, index 8)")
check(Coll.isWalkable(0x07) == false, "a wall is not walkable")
eq(Coll.of(0x20), Coll.WATER, "coll 0x20 is WATER")
check(Coll.isWalkable(0x20) == false, "water is not walkable on foot")
check(Coll.isLedge(0xa0) == true, "0xa0 is a ledge tile")
eq(Coll.of(0xa0), Coll.LAND, "a ledge tile is LAND in the permission table")
check(Coll.isLedge(0x9f) == false, "0x9f is not a ledge")
check(Coll.isLedge(0xb0) == false, "0xb0 is not a ledge")
eq(Coll.of(nil), Coll.WALL, "nil reads as WALL")
eq(Coll.of(-1), Coll.WALL, "negative reads as WALL")
check(Coll.isLedge(nil) == false, "nil is not a ledge")

eq(Permissions.surfable(0x20), "water", "surfable still answers water (Permissions.of re-export)")
eq(Permissions.surfable(0), "land", "surfable still answers land")
check(type(Permissions.ledgeFacings(0xa0)) == "table",
  "ledgeFacings still resolves (LEDGE_FACINGS + isLedge)")

local Seed = require("src.core.game3.scripting.collision")
local seeded = Seed.seed("BLOCKED")

eq(NativePack.resolveLayoutColl(5, 0, false), 5,
  "mapColl 0: the layout's coll passes through (branch 1)")
eq(NativePack.resolveLayoutColl(0xa0, 1, false), 0xa0,
  "a ledge keeps its layout coll (branch 2)")
eq(NativePack.resolveLayoutColl(0x60, 1, true), 0x60,
  "a warp cell keeps its layout coll (branch 3, pokefirered field_control_avatar.c:987)")
eq(NativePack.resolveLayoutColl(0x07, 1, false), 0x07,
  "a non-walkable layout coll keeps itself (branch 4)")
eq(NativePack.resolveLayoutColl(0, 1, false), seeded,
  "a walkable layout coll under a blocking map coll seeds BLOCKED (branch 5)")
eq(NativePack.resolveLayoutColl(0, 1, true), seeded,
  "0x00 is not in the warp range, so it still seeds")

T.finish("game3_coll_permissions_test")
