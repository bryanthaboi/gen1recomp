#!/usr/bin/env luajit
-- MB_IMPASSABLE_* (0x30-0x37) edge walls: pokefirered/src/metatile_behavior.c:546
-- and pokefirered/src/event_object_movement.c:4889.

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local MB = {
  EAST = 0x30, WEST = 0x31, NORTH = 0x32, SOUTH = 0x33,
  NORTHEAST = 0x34, NORTHWEST = 0x35, SOUTHEAST = 0x36, SOUTHWEST = 0x37,
}

print("[test] 1. the classifier keeps a directional metatile's own walkability")
local ScriptColl = require("src.core.game3.scripting.collision")
for name, beh in pairs(MB) do
  local openByte = ScriptColl.fromCell(721, 0, beh, "indoor")
  local shutByte = ScriptColl.fromCell(721, 1, beh, "indoor")
  check(openByte ~= 0x07 and openByte ~= 0xff,
    string.format("MB_IMPASSABLE_%s with mapColl 0 stays walkable (0x%02X)", name, openByte))
  check(shutByte == 0x07,
    string.format("MB_IMPASSABLE_%s with mapColl 1 is solid (0x%02X)", name, shutByte))
end

print("[test] 2. the four blocked-edge predicates")
local Collision = require("src.core.game3.collision")
local PREDS = {
  isNorthBlocked = { MB.NORTH, MB.NORTHEAST, MB.NORTHWEST },
  isSouthBlocked = { MB.SOUTH, MB.SOUTHEAST, MB.SOUTHWEST },
  isEastBlocked = { MB.EAST, MB.NORTHEAST, MB.SOUTHEAST },
  isWestBlocked = { MB.WEST, MB.NORTHWEST, MB.SOUTHWEST },
}
for name, want in pairs(PREDS) do
  local fn = Collision[name]
  if type(fn) ~= "function" then
    check(false, "Collision." .. name .. " exists")
  else
    local set = {}
    for _, beh in ipairs(want) do set[beh] = true end
    local wrong = 0
    for beh = 0x00, 0xFF do
      if (fn(beh) and true or false) ~= (set[beh] == true) then wrong = wrong + 1 end
    end
    check(wrong == 0, name .. " matches pret over every behavior byte, wrong=" .. wrong)
    check(fn(nil) ~= true, name .. "(nil) is false")
  end
end

print("[test] 3. directionallyImpassable pairs leave-tile and enter-tile")
if type(Collision.directionallyImpassable) ~= "function" then
  check(false, "Collision.directionallyImpassable exists")
else
  local behs = {}
  local realBehavior = Collision.behavior
  Collision.behavior = function(x, y) return behs[x .. "," .. y] end
  local function D(fx, fy, tx, ty, dir)
    return Collision.directionallyImpassable(fx, fy, tx, ty, dir) and true or false
  end
  behs["1,1"] = MB.NORTH
  check(D(1, 1, 1, 0, "up"), "leaving an IMPASSABLE_NORTH tile northward is blocked")
  check(not D(1, 1, 1, 2, "down"), "leaving an IMPASSABLE_NORTH tile southward is allowed")
  check(not D(1, 1, 2, 1, "right"), "leaving an IMPASSABLE_NORTH tile eastward is allowed")
  check(not D(1, 1, 0, 1, "left"), "leaving an IMPASSABLE_NORTH tile westward is allowed")
  behs = { ["1,1"] = MB.NORTH }
  check(D(1, 0, 1, 1, "down"), "entering an IMPASSABLE_NORTH tile from the north is blocked")
  check(not D(1, 2, 1, 1, "up"), "entering an IMPASSABLE_NORTH tile from the south is allowed")
  behs = { ["1,1"] = MB.SOUTHWEST }
  check(D(1, 1, 1, 2, "down"), "IMPASSABLE_SOUTHWEST blocks leaving southward")
  check(D(1, 1, 0, 1, "left"), "IMPASSABLE_SOUTHWEST blocks leaving westward")
  check(not D(1, 1, 1, 0, "up"), "IMPASSABLE_SOUTHWEST allows leaving northward")
  check(not D(1, 1, 2, 1, "right"), "IMPASSABLE_SOUTHWEST allows leaving eastward")
  behs = { ["1,1"] = MB.SOUTHWEST }
  check(D(1, 0, 1, 1, "down") == false, "IMPASSABLE_SOUTHWEST does not seal its north edge")
  check(D(1, 2, 1, 1, "up"), "entering an IMPASSABLE_SOUTHWEST tile from the south is blocked")
  check(D(0, 1, 1, 1, "right"), "entering an IMPASSABLE_SOUTHWEST tile from the west is blocked")
  behs = {}
  check(not D(1, 1, 1, 0, "up"), "a plain tile blocks nothing")
  check(not D(nil, nil, 1, 0, nil), "a missing direction blocks nothing")
  Collision.behavior = realBehavior
end

print("[test] 4. Victory Road 1F cliff band")
local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_directional_impassable_test map checks: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local game = { data = {} }
Dataset.hydrate(game)

local MAP = "FR_VICTORY_ROAD_1F"
local def = game.data.maps[MAP]
check(def ~= nil, MAP .. " is in the cache")
if not def then finish() end
Collision.bindMap(game, MAP, def)

check(Collision.behavior(14, 5) == MB.NORTH, "(14,5) carries MB_IMPASSABLE_NORTH")
check(Collision.behavior(14, 4) == 0x08, "(14,4) above it is MB_CAVE")
check(Collision.behavior(14, 6) == 0x08, "(14,6) below it is MB_CAVE")

if Collision.cell(14, 5) == 0x07 then
  print("[skip] the mounted cache was baked before the classifier change; "
    .. "re-import to run the walkability checks")
  finish()
end

check(Collision.canEnter(game, 14, 5, { fromX = 14, fromY = 6, dir = "up" }) == true,
  "the player can step up onto the cliff band at (14,5)")
check(Collision.canEnter(game, 14, 6, { fromX = 14, fromY = 5, dir = "down" }) == true,
  "and step back down off it")
check(Collision.canEnter(game, 15, 5, { fromX = 14, fromY = 5, dir = "right" }) == true,
  "and walk along the band eastward")
local okUp, whyUp = Collision.canEnter(game, 14, 4, { fromX = 14, fromY = 5, dir = "up" })
check(okUp == false and whyUp == "tile",
  "walking north off the band is refused (" .. tostring(whyUp) .. ")")
local okDown, whyDown = Collision.canEnter(game, 14, 5, { fromX = 14, fromY = 4, dir = "down" })
check(okDown == false and whyDown == "tile",
  "dropping south onto the band from above is refused (" .. tostring(whyDown) .. ")")
check(Collision.canEnter(game, 14, 4, { fromX = 14, fromY = 3, dir = "down" }) == true,
  "the cave floor above the band is otherwise open")

print("[test] 5. mapColl still decides which directional cells are solid")
local function tally(mapId)
  local d = game.data.maps[mapId]
  if not d then return nil end
  Collision.bindMap(game, mapId, d)
  local walk, solid = 0, 0
  for y = 0, Collision._heightCells - 1 do
    for x = 0, Collision._widthCells - 1 do
      local beh = Collision.behavior(x, y)
      if beh and beh >= 0x30 and beh <= 0x37 then
        if Collision.cell(x, y) == 0x07 then solid = solid + 1 else walk = walk + 1 end
      end
    end
  end
  return walk, solid
end
local vrWalk, vrSolid = tally(MAP)
check(vrWalk == 20 and vrSolid == 19,
  string.format("Victory Road 1F: 20 walkable / 19 solid, got %s / %s",
    tostring(vrWalk), tostring(vrSolid)))
local emWalk, emSolid = tally("FR_MT_EMBER_SUMMIT_PATH_2F")
check(emWalk == 87 and emSolid == 177,
  string.format("Mt Ember Summit Path 2F: 87 walkable / 177 solid, got %s / %s",
    tostring(emWalk), tostring(emSolid)))

print("[test] 6. Mt Ember Summit Path 2F seals every north edge in the block")
local EM = "FR_MT_EMBER_SUMMIT_PATH_2F"
if game.data.maps[EM] then
  Collision.bindMap(game, EM, game.data.maps[EM])
  check(Collision.behavior(25, 44) == MB.NORTH, "(25,44) carries MB_IMPASSABLE_NORTH")
  check(Collision.cell(25, 44) ~= 0x07, "(25,44) is walkable rock, not a wall")
  check(Collision.canEnter(game, 25, 43, { fromX = 25, fromY = 44, dir = "up" }) == false,
    "climbing north inside the Mt Ember block is refused")
  check(Collision.canEnter(game, 26, 44, { fromX = 25, fromY = 44, dir = "right" }) == true,
    "walking east along the Mt Ember block is allowed")
end

finish()
