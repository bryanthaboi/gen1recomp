-- Game3-owned field collision grid.
-- Built from mapDef.blocks + tileset.collision (Gen2 COLL_* quads baked from
-- FRLG metatile attrs at extract). Does not call World:step / Player:tryMove.

local Collision = {}

local DELTA = {
  up = { 0, -1 },
  down = { 0, 1 },
  left = { -1, 0 },
  right = { 1, 0 },
}

Collision._grid = nil -- 1-based flat COLL_* bytes, widthCells * heightCells
Collision._widthCells = 0
Collision._heightCells = 0
Collision._mapId = nil
Collision._mapDef = nil
Collision._warps = {} -- [cy*1024+cx] = warp def
Collision._logged = false

local function log(msg)
  print("[game3/collision] " .. tostring(msg))
end

local function permissions()
  local ok, P = pcall(require, "src.world.gen2.Permissions")
  return ok and P or nil
end

local function resolveTileset(game, mapDef)
  if not mapDef then return nil end
  local tsId = mapDef.tileset
  local data = game and game.data
  local sets = data and (data.tilesets or data.gen2Tilesets)
  return tsId and sets and sets[tsId], tsId
end

local function hostWorld(game)
  return game and (game.overworld or game.world)
end

--- Expand mapDef blocks × tileset.collision into a per-cell COLL_* grid.
-- Prefer native midLayout when present (already 16px COLL_* bytes).
function Collision.bindMap(game, mapId, mapDef)
  Collision._grid = nil
  Collision._mapId = mapId
  Collision._mapDef = mapDef
  Collision._warps = {}
  Collision._widthCells = 0
  Collision._heightCells = 0

  if mapDef and mapDef.midLayout then
    local layout = mapDef.midLayout
    Collision._grid = layout:collArray()
    Collision._widthCells = layout.width
    Collision._heightCells = layout.height
    Collision.installWarps(mapDef)
    if not Collision._logged then
      log(string.format("grid ready (native) map=%s cells=%dx%d warps=%d",
        tostring(mapId), layout.width, layout.height, #(mapDef.warps or {})))
      Collision._logged = true
    end
    return true
  end

  if not mapDef or type(mapDef.blocks) ~= "table" then
    log("bindMap failed — no blocks for " .. tostring(mapId))
    return false
  end

  local tileset = resolveTileset(game, mapDef)
  local collTbl = tileset and tileset.collision
  if not collTbl then
    log("bindMap failed — no tileset.collision for " .. tostring(mapDef.tileset))
    return false
  end

  local bw = mapDef.width or 0
  local bh = mapDef.height or 0
  local wc = bw * 2
  local hc = bh * 2
  local grid = {}
  local border = mapDef.borderBlock or 0

  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      local bx, by = math.floor(cx / 2), math.floor(cy / 2)
      local bid = border
      if bx >= 0 and by >= 0 and bx < bw and by < bh then
        bid = mapDef.blocks[by * bw + bx + 1] or border
      end
      local quad = collTbl[(bid or 0) + 1]
      local lx, ly = cx % 2, cy % 2
      local byte = 0xff
      if type(quad) == "table" then
        byte = quad[ly * 2 + lx + 1] or 0xff
      end
      grid[cy * wc + cx + 1] = byte
    end
  end

  Collision._grid = grid
  Collision._widthCells = wc
  Collision._heightCells = hc

  Collision.installWarps(mapDef)

  if not Collision._logged then
    log(string.format("grid ready map=%s cells=%dx%d warps=%d",
      tostring(mapId), wc, hc, #(mapDef.warps or {})))
    Collision._logged = true
  end
  return true
end

local function isWarpBehavior(coll)
  if not coll then return false end
  return (coll >= 0x60 and coll <= 0x7F)
end

-- pokefirered/src/field_control_avatar.c: a map-header warp event only fires
-- when the metatile behavior is a live warp behavior. That is the arrow warps
-- 0x62-0x65 (TryArrowWarp), the directional stair warps 0x6C-0x6F
-- (IsDirectionalStairWarpMetatileBehavior), and everything IsWarpMetatileBehavior
-- accepts: MB_CAVE_DOOR 0x60, MB_LADDER 0x61, MB_FALL_WARP 0x66,
-- MB_REGULAR_WARP 0x67, MB_LAVARIDGE_1F_WARP 0x68, MB_WARP_DOOR 0x69,
-- escalators 0x6A-0x6B, MB_UNION_ROOM_WARP 0x71. Together: 0x60-0x6F plus 0x71.
function Collision.isWarpMetatileBehavior(beh)
  if not beh then return false end
  return (beh >= 0x60 and beh <= 0x6F) or beh == 0x71
end

-- Index warps and force door/warp cells walkable. Extract can leave outdoor
-- MB_WARP_DOOR tiles as solid when tileset attrs were read past EOF — there the
-- behavior is unknown (nil) and the repair still applies. A *readable* non-warp
-- behavior means the cell is a real wall that merely happens to carry a (dead)
-- warp event, e.g. PalletTown_PlayersHouse_1F (3,9): pret never lets the player
-- stand on it, so opening it would let the player walk out through the wall.
local COLL_DOOR = 0x71
function Collision.installWarps(mapDef)
  Collision._warps = Collision._warps or {}
  local layout = mapDef and mapDef.midLayout
  for _, w in ipairs((mapDef and mapDef.warps) or {}) do
    local x, y = tonumber(w.x), tonumber(w.y)
    if x and y then
      local cur = nil
      if Collision._grid and Collision._widthCells > 0 then
        local i = y * Collision._widthCells + x + 1
        cur = Collision._grid[i]
        local beh = Collision.behavior(x, y)
        local repair = beh == nil or Collision.isWarpMetatileBehavior(beh)
        -- pokefirered/src/field_control_avatar.c:860
        if beh ~= nil and repair and cur == 0x00 then
          local ScriptColl = require("src.core.game3.scripting.collision")
          local seeded = ScriptColl.fromCell(layout and layout:midAt(x, y) or 0, 0, beh, mapDef.kind)
          if isWarpBehavior(seeded) then
            Collision._grid[i] = seeded
            cur = seeded
          end
        elseif repair and (cur == nil or cur == 0x07 or cur == 0xff) then
          Collision._grid[i] = COLL_DOOR
          cur = COLL_DOOR
          if layout and layout.applyOverride then
            local mid = layout.midAt and layout:midAt(x, y) or nil
            local elev = layout.elevAt and layout:elevAt(x, y) or nil
            layout:applyOverride(x, y, mid, COLL_DOOR, elev)
          end
        end
      end
      -- In pret, a warp in map header is only active if the metatile behavior is a warp behavior
      if isWarpBehavior(cur) then
        Collision._warps[y * 1024 + x] = w
      end
    end
  end
end

function Collision.clear()
  Collision._grid = nil
  Collision._mapId = nil
  Collision._mapDef = nil
  Collision._warps = {}
  Collision._widthCells = 0
  Collision._heightCells = 0
end

function Collision.inBounds(cx, cy)
  return cx >= 0 and cy >= 0
    and cx < Collision._widthCells and cy < Collision._heightCells
end

-- Preserve original MB semantics independently of the walkability COLL grid.
function Collision.behaviorOn(mapDef, cx, cy)
  local layout = mapDef and mapDef.midLayout
  if not layout or cx<0 or cy<0 or cx>=layout.width or cy>=layout.height then return nil end
  local pair = mapDef.pair or layout.pair
  local behaviors = require("src.core.game3.scripting.interaction_scripts").behaviors[pair]
  return behaviors and behaviors[layout:midAt(cx,cy)]
end

function Collision.behavior(cx,cy)
  return Collision.behaviorOn(Collision._mapDef, cx, cy)
end

-- pokefirered/include/constants/metatile_behaviors.h:39
local MB_IMPASSABLE_EAST = 0x30
local MB_IMPASSABLE_WEST = 0x31
local MB_IMPASSABLE_NORTH = 0x32
local MB_IMPASSABLE_SOUTH = 0x33
local MB_IMPASSABLE_NORTHEAST = 0x34
local MB_IMPASSABLE_NORTHWEST = 0x35
local MB_IMPASSABLE_SOUTHEAST = 0x36
local MB_IMPASSABLE_SOUTHWEST = 0x37

-- pokefirered/src/metatile_behavior.c:546
function Collision.isEastBlocked(beh)
  return beh == MB_IMPASSABLE_EAST or beh == MB_IMPASSABLE_NORTHEAST
    or beh == MB_IMPASSABLE_SOUTHEAST
end

-- pokefirered/src/metatile_behavior.c:556
function Collision.isWestBlocked(beh)
  return beh == MB_IMPASSABLE_WEST or beh == MB_IMPASSABLE_NORTHWEST
    or beh == MB_IMPASSABLE_SOUTHWEST
end

-- pokefirered/src/metatile_behavior.c:566
function Collision.isNorthBlocked(beh)
  return beh == MB_IMPASSABLE_NORTH or beh == MB_IMPASSABLE_NORTHEAST
    or beh == MB_IMPASSABLE_NORTHWEST
end

-- pokefirered/src/metatile_behavior.c:576
function Collision.isSouthBlocked(beh)
  return beh == MB_IMPASSABLE_SOUTH or beh == MB_IMPASSABLE_SOUTHEAST
    or beh == MB_IMPASSABLE_SOUTHWEST
end

-- pokefirered/src/event_object_movement.c:888 gOppositeDirectionBlockedMetatileFuncs
local LEAVE_BLOCKED = {
  down = Collision.isSouthBlocked,
  up = Collision.isNorthBlocked,
  left = Collision.isWestBlocked,
  right = Collision.isEastBlocked,
}
-- pokefirered/src/event_object_movement.c:895 gDirectionBlockedMetatileFuncs
local ENTER_BLOCKED = {
  down = Collision.isNorthBlocked,
  up = Collision.isSouthBlocked,
  left = Collision.isEastBlocked,
  right = Collision.isWestBlocked,
}

-- pokefirered/src/event_object_movement.c:4889 IsMetatileDirectionallyImpassable
function Collision.directionallyImpassableOn(mapDef, fromX, fromY, tx, ty, dir)
  local leave = LEAVE_BLOCKED[dir]
  if not leave then return false end
  if fromX and fromY and leave(Collision.behaviorOn(mapDef, fromX, fromY)) then
    return true
  end
  return ENTER_BLOCKED[dir](Collision.behaviorOn(mapDef, tx, ty)) == true
end

function Collision.directionallyImpassable(fromX, fromY, tx, ty, dir)
  local leave = LEAVE_BLOCKED[dir]
  if not leave then return false end
  if fromX and fromY and leave(Collision.behavior(fromX, fromY)) then return true end
  return ENTER_BLOCKED[dir](Collision.behavior(tx, ty)) == true
end

-- pokefirered/src/metatile_behavior.c:5 sBehaviorSurfable
local SURFABLE_BEH = {
  [0x10] = true, [0x11] = true, [0x12] = true, [0x13] = true, [0x15] = true,
  [0x1A] = true, [0x1B] = true,
  [0x50] = true, [0x51] = true, [0x52] = true, [0x53] = true,
}

-- pokefirered/src/metatile_behavior.c:204
function Collision.isSurfable(beh)
  return SURFABLE_BEH[beh] == true
end

-- pokefirered/include/constants/metatile_behaviors.h:17
local MB_WATERFALL = 0x13
-- pokefirered/include/constants/metatile_behaviors.h:20
local MB_PUDDLE = 0x16
local MB_SHALLOW_WATER = 0x17
-- pokefirered/include/constants/metatile_behaviors.h:27
local MB_STRENGTH_BUTTON = 0x20
local MB_ICE = 0x23
local MB_THIN_ICE = 0x26
local MB_CRACKED_ICE = 0x27
local MB_HOT_SPRINGS = 0x28
-- pokefirered/include/constants/metatile_behaviors.h:62
local MB_EASTWARD_CURRENT = 0x50
local MB_WESTWARD_CURRENT = 0x51
local MB_NORTHWARD_CURRENT = 0x52
local MB_SOUTHWARD_CURRENT = 0x53
local MB_SPIN_RIGHT = 0x54
local MB_SPIN_LEFT = 0x55
local MB_SPIN_UP = 0x56
local MB_SPIN_DOWN = 0x57
local MB_STOP_SPINNING = 0x58
-- pokefirered/include/constants/metatile_behaviors.h:52
local MB_WALK_EAST = 0x40
local MB_WALK_WEST = 0x41
local MB_WALK_NORTH = 0x42
local MB_WALK_SOUTH = 0x43
local MB_SLIDE_EAST = 0x44
local MB_SLIDE_WEST = 0x45
local MB_SLIDE_NORTH = 0x46
local MB_SLIDE_SOUTH = 0x47
local MB_TRICK_HOUSE_PUZZLE_8_FLOOR = 0x48
-- pokefirered/include/constants/metatile_behaviors.h:128
local MB_CYCLING_ROAD_PULL_DOWN = 0xD0
local MB_CYCLING_ROAD_PULL_DOWN_GRASS = 0xD1

-- pokefirered/src/metatile_behavior.c:846
function Collision.isStrengthButton(beh) return beh == MB_STRENGTH_BUTTON end

-- pokefirered/src/metatile_behavior.c:102
function Collision.isIce(beh) return beh == MB_ICE end

-- pokefirered/src/metatile_behavior.c:502
function Collision.isThinIce(beh) return beh == MB_THIN_ICE end

-- pokefirered/src/metatile_behavior.c:510
function Collision.isCrackedIce(beh) return beh == MB_CRACKED_ICE end

-- pokefirered/src/metatile_behavior.c:586
function Collision.isHotSprings(beh) return beh == MB_HOT_SPRINGS end

-- pokefirered/src/metatile_behavior.c:350
function Collision.isEastwardCurrent(beh) return beh == MB_EASTWARD_CURRENT end

-- pokefirered/src/metatile_behavior.c:342
function Collision.isWestwardCurrent(beh) return beh == MB_WESTWARD_CURRENT end

-- pokefirered/src/metatile_behavior.c:326
function Collision.isNorthwardCurrent(beh) return beh == MB_NORTHWARD_CURRENT end

-- pokefirered/src/metatile_behavior.c:334
function Collision.isSouthwardCurrent(beh) return beh == MB_SOUTHWARD_CURRENT end

-- pokefirered/src/metatile_behavior.c:754
function Collision.isSpinRight(beh) return beh == MB_SPIN_RIGHT end

-- pokefirered/src/metatile_behavior.c:762
function Collision.isSpinLeft(beh) return beh == MB_SPIN_LEFT end

-- pokefirered/src/metatile_behavior.c:770
function Collision.isSpinUp(beh) return beh == MB_SPIN_UP end

-- pokefirered/src/metatile_behavior.c:778
function Collision.isSpinDown(beh) return beh == MB_SPIN_DOWN end

-- pokefirered/src/metatile_behavior.c:786
function Collision.isStopSpinning(beh) return beh == MB_STOP_SPINNING end

-- pokefirered/src/metatile_behavior.c:794
function Collision.isSpinTile(beh)
  return beh ~= nil and beh >= MB_SPIN_RIGHT and beh <= MB_SPIN_DOWN
end

-- pokefirered/src/metatile_behavior.c:668
function Collision.isCyclingRoadPullDown(beh)
  return beh ~= nil and beh >= MB_CYCLING_ROAD_PULL_DOWN
    and beh <= MB_CYCLING_ROAD_PULL_DOWN_GRASS
end

-- pokefirered/src/metatile_behavior.c:676
function Collision.isCyclingRoadPullDownGrass(beh)
  return beh == MB_CYCLING_ROAD_PULL_DOWN_GRASS
end

-- pokefirered/src/metatile_behavior.c:318
function Collision.isWalkEast(beh) return beh == MB_WALK_EAST end

-- pokefirered/src/metatile_behavior.c:310
function Collision.isWalkWest(beh) return beh == MB_WALK_WEST end

-- pokefirered/src/metatile_behavior.c:294
function Collision.isWalkNorth(beh) return beh == MB_WALK_NORTH end

-- pokefirered/src/metatile_behavior.c:302
function Collision.isWalkSouth(beh) return beh == MB_WALK_SOUTH end

-- pokefirered/src/metatile_behavior.c:382
function Collision.isSlideEast(beh) return beh == MB_SLIDE_EAST end

-- pokefirered/src/metatile_behavior.c:374
function Collision.isSlideWest(beh) return beh == MB_SLIDE_WEST end

-- pokefirered/src/metatile_behavior.c:358
function Collision.isSlideNorth(beh) return beh == MB_SLIDE_NORTH end

-- pokefirered/src/metatile_behavior.c:366
function Collision.isSlideSouth(beh) return beh == MB_SLIDE_SOUTH end

-- pokefirered/src/metatile_behavior.c:286
function Collision.isTrickHouseSlipperyFloor(beh)
  return beh == MB_TRICK_HOUSE_PUZZLE_8_FLOOR
end

-- pokefirered/src/metatile_behavior.c:594
function Collision.isWaterfall(beh) return beh == MB_WATERFALL end

-- pokefirered/include/constants/metatile_behaviors.h:72
local MB_CAVE_DOOR = 0x60
local MB_LADDER = 0x61
local MB_EAST_ARROW_WARP = 0x62
local MB_WEST_ARROW_WARP = 0x63
local MB_NORTH_ARROW_WARP = 0x64
local MB_SOUTH_ARROW_WARP = 0x65
local MB_FALL_WARP = 0x66
local MB_REGULAR_WARP = 0x67
local MB_LAVARIDGE_1F_WARP = 0x68
local MB_WARP_DOOR = 0x69
-- pokefirered/include/constants/metatile_behaviors.h:82
local MB_UP_ESCALATOR = 0x6A
local MB_DOWN_ESCALATOR = 0x6B
local MB_UP_RIGHT_STAIR_WARP = 0x6C
local MB_UP_LEFT_STAIR_WARP = 0x6D
local MB_DOWN_RIGHT_STAIR_WARP = 0x6E
local MB_DOWN_LEFT_STAIR_WARP = 0x6F
-- pokefirered/include/constants/metatile_behaviors.h:89
local MB_UNION_ROOM_WARP = 0x71

-- pokefirered/src/metatile_behavior.c:110
function Collision.isWarpDoor(beh) return beh == MB_WARP_DOOR end

-- pokefirered/src/metatile_behavior.c:186
function Collision.isLadder(beh) return beh == MB_LADDER end

-- pokefirered/src/metatile_behavior.c:194
function Collision.isNonAnimDoor(beh) return beh == MB_CAVE_DOOR end

-- pokefirered/src/metatile_behavior.c:202
function Collision.isDeepSouthWarp() return false end

-- pokefirered/src/metatile_behavior.c:624
function Collision.isLavaridge1FWarp(beh) return beh == MB_LAVARIDGE_1F_WARP end

-- pokefirered/src/metatile_behavior.c:632
function Collision.isWarpPad(beh) return beh == MB_REGULAR_WARP end

-- pokefirered/src/metatile_behavior.c:640
function Collision.isUnionRoomWarp(beh) return beh == MB_UNION_ROOM_WARP end

-- pokefirered/src/metatile_behavior.c:658
function Collision.isFallWarp(beh) return beh == MB_FALL_WARP end

-- pokefirered/src/metatile_behavior.c:126
function Collision.isEscalator(beh)
  return beh == MB_UP_ESCALATOR or beh == MB_DOWN_ESCALATOR
end

-- pokefirered/src/field_control_avatar.c:944
local ARROW_WARP_DIR = {
  [MB_EAST_ARROW_WARP] = "right",
  [MB_WEST_ARROW_WARP] = "left",
  [MB_NORTH_ARROW_WARP] = "up",
  [MB_SOUTH_ARROW_WARP] = "down",
}

-- pokefirered/src/metatile_behavior.c:253
function Collision.isArrowWarpBehavior(beh)
  return ARROW_WARP_DIR[beh] ~= nil
end

-- pokefirered/src/field_control_avatar.c:944
function Collision.arrowWarpDir(beh) return ARROW_WARP_DIR[beh] end

-- pokefirered/src/field_control_avatar.c:901
function Collision.isStepWarpBehavior(beh)
  if beh == nil then return false end
  return Collision.isWarpDoor(beh) or Collision.isLadder(beh)
    or Collision.isEscalator(beh) or Collision.isNonAnimDoor(beh)
    or Collision.isLavaridge1FWarp(beh) or Collision.isWarpPad(beh)
    or Collision.isFallWarp(beh) or Collision.isUnionRoomWarp(beh)
end

-- pokefirered/src/metatile_behavior.c:174
function Collision.isStairWarpBehavior(beh)
  return beh == MB_UP_RIGHT_STAIR_WARP or beh == MB_UP_LEFT_STAIR_WARP
    or beh == MB_DOWN_RIGHT_STAIR_WARP or beh == MB_DOWN_LEFT_STAIR_WARP
end

-- pokefirered/src/field_control_avatar.c:924
function Collision.stairWarpDir(beh)
  if beh == MB_UP_LEFT_STAIR_WARP or beh == MB_DOWN_LEFT_STAIR_WARP then
    return "left"
  end
  if beh == MB_UP_RIGHT_STAIR_WARP or beh == MB_DOWN_RIGHT_STAIR_WARP then
    return "right"
  end
  return nil
end

-- pokefirered/src/overworld.c:921
function Collision.stairArrivalFacing(beh)
  if beh == MB_UP_RIGHT_STAIR_WARP or beh == MB_DOWN_RIGHT_STAIR_WARP then
    return "left"
  end
  if beh == MB_UP_LEFT_STAIR_WARP or beh == MB_DOWN_LEFT_STAIR_WARP then
    return "right"
  end
  return nil
end

-- pokefirered/src/overworld.c:910
local ARRIVAL_FACING = {
  [MB_CAVE_DOOR] = "down",
  [MB_WARP_DOOR] = "down",
  [MB_SOUTH_ARROW_WARP] = "up",
  [MB_NORTH_ARROW_WARP] = "down",
  [MB_WEST_ARROW_WARP] = "right",
  [MB_EAST_ARROW_WARP] = "left",
  [MB_UP_RIGHT_STAIR_WARP] = "left",
  [MB_DOWN_RIGHT_STAIR_WARP] = "left",
  [MB_UP_LEFT_STAIR_WARP] = "right",
  [MB_DOWN_LEFT_STAIR_WARP] = "right",
}

function Collision.arrivalFacing(destBeh, storedDir)
  local f = ARRIVAL_FACING[destBeh]
  if f then return f end
  if destBeh == MB_LADDER then return storedDir or "down" end
  return "down"
end

-- pokefirered/src/field_fadetransition.c:866
function Collision.stairSpeeds(beh)
  if beh == MB_UP_RIGHT_STAIR_WARP then return 16, -10 end
  if beh == MB_UP_LEFT_STAIR_WARP then return -17, -10 end
  if beh == MB_DOWN_RIGHT_STAIR_WARP then return 17, 3 end
  if beh == MB_DOWN_LEFT_STAIR_WARP then return -17, 3 end
  return 0, 0
end

function Collision.cell(cx, cy)
  if not Collision._grid or not Collision.inBounds(cx, cy) then
    return 0xff
  end
  return Collision._grid[cy * Collision._widthCells + cx + 1] or 0xff
end

-- Player dirs ↔ mapDef.connections keys (Dataset / pret use cardinal names).
local DIR_CONN = {
  up = "north",
  down = "south",
  left = "west",
  right = "east",
}

local function mapCellSize(def)
  if not def then return 0, 0 end
  local L = def.midLayout
  if L and L.width and L.height then
    return L.width, L.height
  end
  return tonumber(def.width) or 0, tonumber(def.height) or 0
end

--- Landing cell on dest after stepping off `dir` edge (FRLG metatile = one cell).
function Collision.connectionLanding(destDef, conn, dir, fromCx, fromCy)
  if not (destDef and conn) then return nil end
  local destW, destH = mapCellSize(destDef)
  if destW < 1 or destH < 1 then return nil end
  local offset = tonumber(conn.offset) or 0
  local x, y
  if dir == "up" then
    x, y = fromCx - offset, destH - 1
  elseif dir == "down" then
    x, y = fromCx - offset, 0
  elseif dir == "left" then
    x, y = destW - 1, fromCy - offset
  elseif dir == "right" then
    x, y = 0, fromCy - offset
  else
    return nil
  end
  x = math.max(0, math.min(destW - 1, x))
  y = math.max(0, math.min(destH - 1, y))
  return x, y
end

local function collWalkable(coll)
  local P = permissions()
  -- FRLG ledge metatiles carry map collision=1 (impassable). Extract encodes
  -- hop facing as Gen2 0xA0–0xA7, which Permissions treats as LAND — reject
  -- them here so you cannot climb from below; only ledgeLanding may clear them.
  if P and P.isLedge and P.isLedge(coll) then return false end
  if P and P.isWalkable then return P.isWalkable(coll) end
  return coll ~= 0x07 and coll ~= 0xff and coll ~= 0x29
end

--- Outdoor edge transition (Pallet↔Route 1). Seamless remap mid-step like
-- pret CameraMove → LoadMapFromCameraTransition / Gen2 World:tryConnection.
-- Returns true if the crossing was accepted.
function Collision.tryConnection(game, fromX, fromY, dir, run)
  local d = DELTA[dir]
  if not d then return false end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
    return false
  end
  local WarpMod = package.loaded["src.core.game3.warp"]
  if WarpMod and WarpMod.isBusy and WarpMod.isBusy() then
    return false
  end

  local mapDef = Collision._mapDef
  if not mapDef or type(mapDef.connections) ~= "table" then return false end
  local conn = mapDef.connections[dir]
    or mapDef.connections[DIR_CONN[dir] or ""]
  if not conn then return false end
  local destMap = conn.map or conn.mapId
  if type(destMap) ~= "string" then return false end

  local data = game and game.data and game.data.maps
  local destDef = data and data[destMap]
  if not destDef then return false end
  local Map = require("src.core.game3.map")
  if Map.ensureMidLayout then Map.ensureMidLayout(game, destMap, destDef) end

  local lx, ly = Collision.connectionLanding(destDef, conn, dir, fromX, fromY)
  if not lx then return false end

  local Player = require("src.core.game3.player")
  local L = destDef.midLayout
  local landingWater = Collision.isWaterOn(destDef, lx, ly)
  if L and L.collAt then
    local coll = L:collAt(lx, ly)
    local P = permissions()
    if not collWalkable(coll) and not (P and P.isWater and P.isWater(coll)) then
      return false
    end
    if landingWater and not Player.surfing then return false end
  end
  -- pokefirered/src/event_object_movement.c:4889
  if LEAVE_BLOCKED[dir](Collision.behaviorOn(mapDef, fromX, fromY))
      or ENTER_BLOCKED[dir](Collision.behaviorOn(destDef, lx, ly)) then
    return false
  end
  if Player.surfing and L and L.elevAt then
    local elevation = L:elevAt(lx, ly)
    -- pokefirered/src/field_player_avatar.c:597
    if not landingWater then
      if elevation ~= 3 then return false end
    -- pokefirered/src/event_object_movement.c:8346
    elseif elevation ~= 0 and elevation ~= 15 and Player.elevation ~= 0
        and elevation ~= Player.elevation then
      return false
    end
  end
  local Ghosts = require("src.core.game3.ghosts")
  if Ghosts.blocksOn(destMap, destDef, lx, ly) then return false end

  local Runtime = package.loaded["src.core.game3.runtime"]
  local mod = Runtime and Runtime._mod
  local g = game or (Runtime and Runtime._game)

  Map.load(mod, g, destMap, {
    x = lx,
    y = ly,
    facing = dir,
    seamless = true,
    depth1Connections = true,
  })

  -- Park one cell before landing and keep the step running so the seam does
  -- not hitch (same world pixels the neighbor strip already showed).
  local CELL = 16
  local WALK_FRAMES = 16
  local RUN_FRAMES = 8
  Player.cellX, Player.cellY = lx - d[1], ly - d[2]
  Player.px, Player.py = Player.cellX * CELL, Player.cellY * CELL
  Player.facing = dir
  Player.targetX, Player.targetY = lx, ly
  Player.moving = true
  Player.progress = 0
  Player.animClock = 0
  Player.running = run and true or false
  Player.jumping = false
  Player.dismounting = Player.surfing and not landingWater or false
  Player.spriteYOffset = 0
  Player.stepFrames = run and RUN_FRAMES or WALK_FRAMES
  Player.syncSavePosition(g)

  if Collision.isGrass and Collision.isGrass(lx, ly) then
    local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
    if okFx and FieldEffects and FieldEffects.tallGrassAt then
      FieldEffects.tallGrassAt(lx, ly, false)
    end
  end

  return true
end

function Collision.isWalkable(cx, cy)
  local P = permissions()
  local coll = Collision.cell(cx, cy)
  if P and P.isLedge and P.isLedge(coll) then
    return false
  end
  if P and P.isWalkable then
    return P.isWalkable(coll)
  end
  -- Fallback: treat 0x07 / 0xff as solid, water 0x29 as solid on foot.
  return coll ~= 0x07 and coll ~= 0xff and coll ~= 0x29
end

function Collision.isGrass(cx, cy)
  local P = permissions()
  local coll = Collision.cell(cx, cy)
  if P and P.isGrass then return P.isGrass(coll) end
  return coll == 0x18 or coll == 0x14
end

-- pokefirered/src/event_object_movement.c:8346 IsElevationMismatchAt
function Collision.elevationAt(cx, cy)
  local layout = Collision._mapDef and Collision._mapDef.midLayout
  if not (layout and layout.elevAt) then return nil end
  if cx < 0 or cy < 0 or cx >= layout.width or cy >= layout.height then return nil end
  return layout:elevAt(cx, cy)
end

-- pokefirered/src/field_player_avatar.c:597 CanStopSurfing
function Collision.isWaterOn(mapDef, cx, cy, coll)
  local layout = mapDef and mapDef.midLayout
  if layout and (cx < 0 or cy < 0 or cx >= layout.width or cy >= layout.height) then
    return false
  end
  if coll == nil then
    if not layout then return false end
    coll = layout:collAt(cx, cy)
  end
  local P = permissions()
  if P and P.isWater then
    if P.isWater(coll) then return true end
  elseif coll == 0x29 then
    return true
  end
  if not (layout and layout.elevAt) or layout:elevAt(cx, cy) ~= 1 then return false end
  local beh = Collision.behaviorOn(mapDef, cx, cy)
  return beh == MB_PUDDLE or beh == MB_SHALLOW_WATER
end

function Collision.isWater(cx, cy)
  return Collision.isWaterOn(Collision._mapDef, cx, cy, Collision.cell(cx, cy))
end

local function entityBlocks(game, tx, ty)
  local okO, Objects = pcall(require, "src.core.game3.objects")
  if okO and Objects and Objects.hasMap and Objects.hasMap() then
    if Objects.blocks(tx, ty) then return true end
    return false
  end
  local world = hostWorld(game)
  if not (world and world.npcs) then return false end
  for _, npc in ipairs(world.npcs) do
    if not npc.passable then
      local nx = npc.cellX or (npc.def and npc.def.x)
      local ny = npc.cellY or (npc.def and npc.def.y)
      if nx == tx and ny == ty then return true end
      if npc.moving and npc.targetX == tx and npc.targetY == ty then
        return true
      end
    end
  end
  return false
end

local function overrideBlocks(tx, ty)
  local Field = package.loaded["src.core.game3.field"]
  if not (Field and Field.metatileOverrideAt) then return false end
  local mapId = Collision._mapId
  if not mapId then
    local session = Field._session
    mapId = session and session.map
  end
  local o = Field.metatileOverrideAt(mapId, tx, ty)
  return o ~= nil and o.impassable == true
end

--- Can the avatar enter cell (tx, ty) on foot?
-- Returns ok, reason ("bounds"|"tile"|"entity"|"water"|nil)
function Collision.canEnter(game, tx, ty, opts)
  opts = opts or {}
  local surfing = opts.surfing
  if surfing == nil then
    local P = package.loaded["src.core.game3.player"]
    surfing = P and P.surfing == true
  end

  if Collision._grid and Collision._grid[1] ~= nil then
    if not Collision.inBounds(tx, ty) then return false, "bounds" end
    if overrideBlocks(tx, ty) then return false, "tile" end
    -- pokefirered/src/event_object_movement.c:4835 GetCollisionAtCoords
    if Collision.directionallyImpassable(opts.fromX, opts.fromY, tx, ty, opts.dir) then
      return false, "tile"
    end
    if entityBlocks(game, tx, ty) then return false, "entity" end
    local isW = Collision.isWater(tx, ty)
    if surfing then
      if isW then
        return true, nil
      else
        -- Dismount onto land: verify land tile is walkable
        if not Collision.isWalkable(tx, ty) then return false, "tile" end
        return true, nil
      end
    else
      if isW then return false, "water" end
      if not Collision.isWalkable(tx, ty) then return false, "tile" end
      return true, nil
    end
  end

  local world = hostWorld(game)
  local map = world and world.map
  if not map then return false, "bounds" end
  if map.inBounds and not map:inBounds(tx, ty) then return false, "bounds" end
  if overrideBlocks(tx, ty) then return false, "tile" end
  if entityBlocks(game, tx, ty) then return false, "entity" end
  if map.isWalkable and not map:isWalkable(tx, ty) then return false, "tile" end
  return true, nil
end

--- pret GetLedgeJumpDirection / ShouldJumpLedge: the DESTINATION cell (one
-- step along `dir`) is an impassable hop metatile whose facing matches `dir`.
-- Landing is two cells from `from` (Jump2). Wrong-facing approaches bump on
-- the ledge (isWalkable false); only the matching direction hops over it.
function Collision.ledgeLanding(game, fromX, fromY, dir)
  local P = permissions()
  if not (P and P.ledgeFacings) then return nil end
  local d = DELTA[dir]
  if not d then return nil end
  local destX, destY = fromX + d[1], fromY + d[2]
  local coll
  if Collision._grid and Collision._grid[1] ~= nil then
    if not Collision.inBounds(destX, destY) then return nil end
    coll = Collision.cell(destX, destY)
  else
    local map = hostWorld(game) and hostWorld(game).map
    if not map then return nil end
    if map.inBounds and not map:inBounds(destX, destY) then return nil end
    if map.cellCollision then
      coll = map:cellCollision(destX, destY)
    end
  end
  local facings = P.ledgeFacings(coll)
  if not (facings and facings[dir]) then return nil end
  local tx, ty = fromX + d[1] * 2, fromY + d[2] * 2
  local ok = Collision.canEnter(game, tx, ty, {})
  if not ok then return nil end
  return tx, ty
end

-- pokefirered/include/constants/maps.h:9
local MAP_DYNAMIC_NUM = 0x7F
-- pokefirered/include/constants/maps.h:26
local WARP_ID_NONE = 0xFF

local function sessionOf()
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and Runtime.getSession and Runtime.getSession() or nil
end

local function catalogMapId(mapId, group, num)
  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  if type(mapId) == "string" and mapId ~= "" then
    if okC and MapCatalog and MapCatalog.resolve then
      return MapCatalog.resolve(mapId) or mapId
    end
    return mapId
  end
  if okC and MapCatalog and group ~= nil then
    return MapCatalog.mapIdFor(group, num)
  end
  return nil
end

-- pokefirered/src/overworld.c:610 SetWarpDestinationToDynamicWarp
local function resolveDynamicDest(game)
  local session = sessionOf()
  local dw = session and session.dynamicWarp
  if type(dw) == "string" then dw = { map = dw } end
  if type(dw) ~= "table" then return nil end
  local destMap = catalogMapId(dw.map or dw.mapId or dw.destMap, dw.mapGroup, dw.mapNum)
  if type(destMap) ~= "string" then return nil end
  local destDef = game and game.data and game.data.maps and game.data.maps[destMap]
  -- pokefirered/src/overworld.c:564 SetPlayerCoordsFromWarp
  local warps = destDef and destDef.warps
  local id = tonumber(dw.warpId)
  local landing = id and id >= 0 and id < WARP_ID_NONE and warps and warps[id + 1]
  if landing then
    return destMap, tonumber(landing.x) or 0, tonumber(landing.y) or 0
  end
  local x, y = tonumber(dw.x), tonumber(dw.y)
  if x and y and x >= 0 and y >= 0 then return destMap, x, y end
  local w, h = mapCellSize(destDef)
  return destMap, math.floor(w / 2), math.floor(h / 2)
end

local function resolveDest(game, warp)
  -- pokefirered/src/field_control_avatar.c:971 SetupWarp
  if tonumber(warp.mapNum) == MAP_DYNAMIC_NUM then
    return resolveDynamicDest(game)
  end
  local destMap = warp.destMap or warp.map
  if type(destMap) ~= "string" or destMap == "" then
    local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
    if okC and MapCatalog and warp.mapGroup ~= nil then
      destMap = MapCatalog.mapIdFor(warp.mapGroup, warp.mapNum)
    end
    if type(destMap) ~= "string" then
      local Versions = require("src.import.gba.versions")
      destMap = Versions.mapIdFor and Versions.mapIdFor(warp.mapGroup, warp.mapNum)
    end
  else
    local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
    if okC and MapCatalog and MapCatalog.resolve then
      destMap = MapCatalog.resolve(destMap) or destMap
    end
  end
  local destWarp = tonumber(warp.destWarp) or 1
  if type(destMap) ~= "string" then return nil end
  local data = game and game.data and game.data.maps
  local destDef = data and data[destMap]
  local warps = destDef and destDef.warps
  local landing = warps and warps[destWarp]
  if landing then
    return destMap, tonumber(landing.x) or 0, tonumber(landing.y) or 0
  end
  -- Fallback: use warp's own destX/destY if present.
  if warp.destX ~= nil then
    return destMap, tonumber(warp.destX) or 0, tonumber(warp.destY) or 0
  end
  return destMap, 0, 0
end

function Collision.warpAt(cx, cy)
  return Collision._warps[cy * 1024 + cx]
end

-- pokefirered/src/field_control_avatar.c:960 GetWarpEventAtMapPosition
local function triggeringWarp()
  local P = package.loaded["src.core.game3.player"]
  if not P then return nil end
  local cx, cy = tonumber(P.cellX), tonumber(P.cellY)
  if not (cx and cy) then return nil end
  local w = Collision.warpAt(cx, cy)
  if w then return w end
  local d = DELTA[P.facing]
  if not d then return nil end
  return Collision.warpAt(cx + d[1], cy + d[2])
end

-- pokefirered/src/field_control_avatar.c:982 SetupWarp
function Collision.noteDynamicWarpEntry(game, destMap, destX, destY, srcX, srcY)
  local destDef = game and game.data and game.data.maps and game.data.maps[destMap]
  local hit = false
  for _, w in ipairs((destDef and destDef.warps) or {}) do
    if tonumber(w.mapNum) == MAP_DYNAMIC_NUM
        and tonumber(w.x) == tonumber(destX) and tonumber(w.y) == tonumber(destY) then
      hit = true
      break
    end
  end
  if not hit then return false end
  local session = sessionOf()
  if not session then return false end
  local from = (srcX and srcY and Collision.warpAt(tonumber(srcX), tonumber(srcY)))
    or triggeringWarp()
  local P = package.loaded["src.core.game3.player"]
  -- pokefirered/src/overworld.c:600 SetDynamicWarp
  session.dynamicWarp = {
    map = (game and game.currentMap) or Collision._mapId or session.map,
    warpId = WARP_ID_NONE,
    x = (from and tonumber(from.x)) or (P and tonumber(P.cellX)) or session.x,
    y = (from and tonumber(from.y)) or (P and tonumber(P.cellY)) or session.y,
  }
  return true
end

local function isBuilding(name)
  local n = string.upper(tostring(name or ""))
  return n:find("POKECENTER") or n:find("POKEMON_CENTER") or n:find("CENTER")
      or n:find("MART") or n:find("DEPT_STORE")
      or n:find("SILPH_CO") or n:find("HOUSE")
      or n:find("LAB") or n:find("GYM")
      or n:find("SAFARI_ZONE") or n:find("GAME_CORNER")
      or n:find("FAN_CLUB") or n:find("MUSEUM")
      or n:find("DAYCARE") or n:find("DAY_CARE")
      or n:find("CABLE_CLUB") or n:find("SCHOOL")
      or n:find("GATE") or n:find("BUILDING")
      or n:find("_1F") or n:find("_2F") or n:find("_3F")
      or n:find("_4F") or n:find("_5F")
end

--- Check if cell (cx, cy) is an entrance door warp
function Collision.isDoorWarp(game, cx, cy)
  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return nil end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return nil end

  local curMap = (game and game.currentMap) or (Collision._mapId)
  local okDoors, Doors = pcall(require, "src.core.game3.doors")
  if okDoors and Doors and Doors.getDoorEntryAt then
    local entry = Doors.getDoorEntryAt(curMap, cx, cy)
    if entry then
      return {
        warp = w,
        destMap = destMap,
        destX = destX,
        destY = destY,
        x = cx,
        y = cy,
        doorEntry = entry,
      }
    end
  end

  return nil
end

--- Check if cell (cx, cy) is an indoor exit mat warp leading to an outdoor animated door
function Collision.isExitWarp(game, cx, cy)
  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return nil end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return nil end

  local okDoors, Doors = pcall(require, "src.core.game3.doors")
  if okDoors and Doors and Doors.getDoorEntryAt then
    local entry = Doors.getDoorEntryAt(destMap, destX, destY)
    if entry then
      return {
        warp = w,
        destMap = destMap,
        destX = destX,
        destY = destY,
        x = cx,
        y = cy,
        doorEntry = entry,
      }
    end
  end

  return nil
end

--- Check if cell (cx, cy) is an escalator warp
function Collision.isEscalatorWarp(game, cx, cy, dir)
  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return nil end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return nil end

  local coll = Collision.cell(cx, cy)
  local curMap = (game and game.currentMap) or (Collision._mapId)
  local curUpper = string.upper(tostring(curMap or ""))
  local destUpper = string.upper(tostring(destMap or ""))

  -- pokefirered/src/metatile_behavior.c:126
  local beh = Collision.behavior(cx, cy)
  if beh ~= nil then
    if beh ~= MB_UP_ESCALATOR and beh ~= MB_DOWN_ESCALATOR then return nil end
    return {
      warp = w,
      destMap = destMap,
      destX = destX,
      destY = destY,
      escDir = (beh == MB_DOWN_ESCALATOR) and "down" or "up",
      x = cx,
      y = cy,
    }
  end

  local isEscalator = (curUpper:find("POKECENTER") or curUpper:find("POKEMON_CENTER") or curUpper:find("DEPT_STORE"))
      and (destUpper:find("POKECENTER") or destUpper:find("POKEMON_CENTER") or destUpper:find("DEPT_STORE"))

  if isEscalator then
    local escDir = "up"
    if curUpper:find("2F") and (destUpper:find("1F") or not destUpper:find("2F")) then
      escDir = "down"
    elseif curUpper:find("3F") and (destUpper:find("2F") or destUpper:find("1F")) then
      escDir = "down"
    elseif curUpper:find("4F") and (destUpper:find("3F") or destUpper:find("2F") or destUpper:find("1F")) then
      escDir = "down"
    elseif curUpper:find("5F") and (destUpper:find("4F") or destUpper:find("3F") or destUpper:find("2F") or destUpper:find("1F")) then
      escDir = "down"
    elseif coll == 0x6B then
      escDir = "down"
    end
    return {
      warp = w,
      destMap = destMap,
      destX = destX,
      destY = destY,
      escDir = escDir,
      x = cx,
      y = cy,
    }
  end
  return nil
end

-- pokefirered/src/field_control_avatar.c:832
function Collision.isArrowWarp(game, cx, cy, dir)
  local beh = Collision.behavior(cx, cy)
  if not Collision.isArrowWarpBehavior(beh) then return nil end
  if Collision.arrowWarpDir(beh) ~= dir then return nil end

  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return nil end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return nil end

  return {
    warp = w,
    destMap = destMap,
    destX = destX,
    destY = destY,
    behavior = beh,
    x = cx,
    y = cy,
  }
end

-- pokefirered/src/field_control_avatar.c:839
function Collision.isStairWarp(game, cx, cy, dir)
  local beh = Collision.behavior(cx, cy)
  if not Collision.isStairWarpBehavior(beh) then return nil end
  if dir and Collision.stairWarpDir(beh) ~= dir then return nil end

  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return nil end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return nil end

  return {
    warp = w,
    destMap = destMap,
    destX = destX,
    destY = destY,
    behavior = beh,
    x = cx,
    y = cy,
  }
end

-- pokefirered/src/overworld.c:910
function Collision.destArrivalFacing(game, destMap, destX, destY, storedDir)
  local data = game and game.data and game.data.maps
  local destDef = data and data[destMap]
  if destDef then
    local Map = package.loaded["src.core.game3.map"] or require("src.core.game3.map")
    if Map.ensureMidLayout then pcall(Map.ensureMidLayout, game, destMap, destDef) end
  end
  local destBeh = Collision.behaviorOn(destDef, destX, destY)
  if destBeh == nil then return storedDir or "down" end
  return Collision.arrivalFacing(destBeh, storedDir)
end

--- If standing on a warp cell, trigger game3 map load / host warp.
-- Door entrances (pressing UP in front of door), exit mats (pressing DOWN on mat),
-- and escalators (moving into escalator from adjacent cell) are triggered explicitly
-- via Player.tryMove, not on initial step landing.
function Collision.tryWarpAt(game, cx, cy, facing, opts)
  local arrowPress = opts ~= nil and opts.arrow == true
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
    return false
  end

  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return false end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return false end

  local curMap = (game and game.currentMap) or (Collision._mapId)
  local curUpper = string.upper(tostring(curMap or ""))
  local destUpper = string.upper(tostring(destMap or ""))
  local coll = Collision.cell(cx, cy)

  local beh = Collision.behavior(cx, cy)

  -- pokefirered/src/field_control_avatar.c:825
  if not arrowPress then
    if Collision.isDoorWarp and Collision.isDoorWarp(game, cx, cy) then
      return false
    end
    if Collision.isExitWarp and Collision.isExitWarp(game, cx, cy) then
      return false
    end
    if Collision.isEscalatorWarp and Collision.isEscalatorWarp(game, cx, cy, facing) then
      return false
    end
    -- pokefirered/src/field_control_avatar.c:944
    if Collision.isStairWarpBehavior(beh) or Collision.isArrowWarpBehavior(beh) then
      return false
    end
    -- pokefirered/src/field_control_avatar.c:856
    if beh ~= nil and not Collision.isStepWarpBehavior(beh) then
      return false
    end
  end

  local Runtime = package.loaded["src.core.game3.runtime"]
  local mod = Runtime and Runtime._mod
  local g = game or (Runtime and Runtime._game)

  local MapIds = require("src.core.game3.map_ids")
  if MapIds.isGame3Map(destMap) then
    local Warp = require("src.core.game3.warp")

    -- pokefirered/src/field_control_avatar.c:879
    local isTeleport
    if beh ~= nil then
      isTeleport = Collision.isWarpPad(beh)
    else
      isTeleport = (curUpper:find("SILPH_CO") or curUpper:find("SAFFRON_GYM") or curUpper:find("ROCKET_HIDEOUT") or curUpper:find("POKEMON_MANSION"))
        and not (destUpper:find("ELEVATOR") or destUpper:find("1F") or destUpper:find("PLAYERS_HOUSE"))
        and (coll == 0x75 or coll == 0x72)
    end

    -- pokefirered/src/field_control_avatar.c:889
    local isFallHole = (beh ~= nil) and Collision.isFallWarp(beh) or (beh == nil and coll == 0x76)

    if isTeleport then
      return Warp.startTeleport(mod, g, destMap, destX, destY, cx, cy)
    end

    if isFallHole then
      return Warp.startFall(mod, g, destMap, destX, destY, cx, cy)
    end

    Warp.request(mod, g, destMap, destX, destY,
      Collision.destArrivalFacing(g, destMap, destX, destY, facing), {
      fade = true,
      door = false,
      doorX = cx,
      doorY = cy,
    })
    return true
  end

  if not mod then return false end

  -- Leaving Sevii — hand back to host.
  if Runtime and Runtime.isActive and Runtime.isActive() then
    local Bridge = require("src.core.game3.bridge")
    if Bridge.persistSessionOnly then
      Bridge.persistSessionOnly(mod, g)
    end
    Runtime.stop(mod, g)
  end

  local world = hostWorld(g)
  if world and world.warpToMapId then
    world:warpToMapId(destMap, destX, destY, facing or "down")
    return true
  end
  return false
end

return Collision
