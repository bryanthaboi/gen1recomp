local GameVersion = require("src.core.GameVersion")
local CollPermissions = require("src.core.CollPermissions")

local Permissions = {}

Permissions.LAND = CollPermissions.LAND
Permissions.WATER = CollPermissions.WATER
Permissions.WALL = CollPermissions.WALL

Permissions.of = CollPermissions.of
Permissions.isLand = CollPermissions.isLand
Permissions.isWater = CollPermissions.isWater
Permissions.isWall = CollPermissions.isWall
Permissions.isWalkable = CollPermissions.isWalkable
Permissions.isLedge = CollPermissions.isLedge

-- .CheckSurfable (engine/overworld/player_movement.asm): the same test a
-- surfing player's step runs, and the reason it is three-valued rather than a
-- yes/no is that the LAND answer is what ends the surf.
--
--   "water"   the permission is WATER_TILE, keep surfing
--   "land"    the permission is LAND_TILE, this step is .ExitWater
--   nil       neither, the step bumps
function Permissions.surfable(coll)
  local perm = Permissions.of(coll)
  if perm == Permissions.WATER then return "water" end
  if perm == Permissions.LAND then return "land" end
  return nil
end

-- Tall / long grass, the collisions a step can roll a wild encounter on
-- (constants/collision_constants.asm; the _10 and _1C aliases are unused on
-- the cart but land in the same permission).
local GRASS = {
  [0x10] = true, -- COLL_TALL_GRASS_10 (unused)
  [0x14] = true, -- COLL_LONG_GRASS
  [0x18] = true, -- COLL_TALL_GRASS
  [0x1c] = true, -- COLL_LONG_GRASS_1C (unused)
}

function Permissions.isGrass(coll)
  if coll == nil then return false end
  return GRASS[coll % 256] == true
end

-- CheckSuperTallGrassTile (home/map_objects.asm): the LONG grass pair only, not
-- the tall grass one.  It is what doubles the Bug Contest encounter rate (40
-- percent against 20) and what makes the grass rustle animation play.
local SUPER_TALL_GRASS = {
  [0x14] = true, -- COLL_LONG_GRASS
  [0x1c] = true, -- COLL_LONG_GRASS_1C (unused)
}

function Permissions.isSuperTallGrass(coll)
  if coll == nil then return false end
  return SUPER_TALL_GRASS[coll % 256] == true
end

-- CheckGrassCollision (engine/overworld/tile_events.asm) -- NOT the same list
-- as GRASS above, and the difference is load bearing:
--
--   * COLL_WATER is in it, which is what lets a surfing step roll an
--     encounter at all (CanEncounterWildMon runs this, then
--     ChooseWildEncounter picks the water table off CheckOnWater);
--   * the unused $10 / $1c grass aliases are NOT in it, so a tile the graphics
--     call tall grass but the array does not is a free step.
--
-- The garbage rows ($08, $28, $48-$4c) are in the cart's array verbatim and
-- are kept here for the same reason: a romhack tileset that uses one gets the
-- cart's behaviour rather than the tidy one.
local ENCOUNTER_COLLISION = {
  [0x08] = true, -- COLL_CUT_08
  [0x18] = true, -- COLL_TALL_GRASS
  [0x14] = true, -- COLL_LONG_GRASS
  [0x28] = true, -- COLL_CUT_28
  [0x29] = true, -- COLL_WATER
  [0x48] = true, -- COLL_GRASS_48
  [0x49] = true, -- COLL_GRASS_49
  [0x4a] = true, -- COLL_GRASS_4A
  [0x4b] = true, -- COLL_GRASS_4B
  [0x4c] = true, -- COLL_GRASS_4C
}

function Permissions.isEncounterCollision(coll)
  if coll == nil then return false end
  return ENCOUNTER_COLLISION[coll % 256] == true
end

-- The single-collision predicates out of home/map_objects.asm.  Every one of
-- them is a `cp COLL_x / ret z` pair over a real constant and its unused
-- alias, so they are pairs here too.
local ICE = { [0x23] = true, [0x2b] = true }         -- CheckIceTile
local WHIRLPOOL = { [0x24] = true, [0x2c] = true }   -- CheckWhirlpoolTile
local CUT_TREE = { [0x12] = true, [0x1a] = true }    -- CheckCutTreeTile
local HEADBUTT_TREE = { [0x15] = true, [0x1d] = true } -- CheckHeadbuttTreeTile
-- CheckWaterfallTile pairs COLL_WATERFALL with COLL_CURRENT_DOWN, not with a
-- $3x alias of itself: the downward current is the tile at the TOP of a
-- waterfall, and the climb has to keep going while the player is on one.
local WATERFALL = { [0x33] = true, [0x3b] = true }
-- CheckCounterTile.  The counter is not walkable, so it never shows up in a
-- movement test -- its whole job is in CheckFacingObject, which DOUBLES the
-- reach of an A press over one so the player can talk to the nurse or the
-- clerk standing on the far side.  See World:interact.
local COUNTER = { [0x90] = true, [0x98] = true }

local function member(set, coll)
  if coll == nil or coll < 0 then return false end
  return set[coll % 256] == true
end

function Permissions.isIce(coll) return member(ICE, coll) end
function Permissions.isWhirlpool(coll) return member(WHIRLPOOL, coll) end
function Permissions.isCutTree(coll) return member(CUT_TREE, coll) end
function Permissions.isHeadbuttTree(coll) return member(HEADBUTT_TREE, coll) end
function Permissions.isWaterfall(coll) return member(WATERFALL, coll) end
function Permissions.isCounter(coll) return member(COUNTER, coll) end

-- DoPlayerMovement's .CheckTile, HI_NYBBLE_CURRENT arm
-- (engine/overworld/player_movement.asm).  Every $3x collision is a CURRENT
-- tile, and the direction it forces is its LOW TWO BITS indexed into
-- .water_table (`maskbits NUM_DIRECTIONS`), so COLL_WATERFALL $33 and
-- COLL_CURRENT_DOWN $3b both come out DOWN.
--
-- The arm runs ABOVE .CheckTurning and .TryStep and returns
-- PLAYERMOVEMENT_CONTINUE, which is the whole mechanic: a current OVERRIDES
-- the d-pad rather than being refused by it.  That is what makes the plunge
-- down a waterfall automatic and what makes a waterfall column unclimbable by
-- walking -- HM07's scripted climb (World:runWaterfall) moves the player with
-- its own steps, and it runs under World:busy where this never gets a look in.
--
-- COLL_WHIRLPOOL is tested before the nybble and takes PLAYERMOVEMENT_FORCE_TURN
-- instead, so it is not one of these.
local CURRENT_DIR = { [0] = "right", "left", "up", "down" }

function Permissions.currentDirection(coll)
  if coll == nil or coll < 0 then return nil end
  coll = coll % 256
  if coll - (coll % 16) ~= 0x30 then return nil end
  return CURRENT_DIR[coll % 4]
end

-- DoPlayerMovement .CheckTile, HI_NYBBLE_WARPS arm (.warps): landing on a
-- door/staircase/cave forces a walk DOWN off it (engine/overworld/player_movement.asm).
local DOOR_FORCED = {
  [0x71] = true, -- COLL_DOOR
  [0x79] = true, -- COLL_DOOR_79 (unused)
  [0x7a] = true, -- COLL_STAIRCASE
  [0x7b] = true, -- COLL_CAVE
}

function Permissions.doorForcedDirection(coll)
  if DOOR_FORCED[coll] then return "down" end
  return nil
end

-- CheckCutCollision (engine/overworld/tile_events.asm): the collisions CUT is
-- allowed to swing at.  Both grasses are in it, which is why CUT mows a patch
-- of tall grass down to bare ground and not only trees.
local CUTTABLE = {
  [0x12] = true, -- COLL_CUT_TREE
  [0x1a] = true, -- COLL_CUT_TREE_1A
  [0x10] = true, -- COLL_TALL_GRASS_10
  [0x18] = true, -- COLL_TALL_GRASS
  [0x14] = true, -- COLL_LONG_GRASS
  [0x1c] = true, -- COLL_LONG_GRASS_1C
}

function Permissions.isCuttable(coll) return member(CUTTABLE, coll) end

-- Ledges (HI_NYBBLE_LEDGES, $a0-$a7) and the facings that hop them.
--
-- `.TryJump` (engine/overworld/player_movement.asm) runs after `.TryStep`
-- fails: standing ON a ledge tile, facing a direction its `.ledge_table` row
-- allows, the refused step becomes a STEP_LEDGE -- a two-cell jump.  The tile
-- itself is LAND in the permission table (walk onto it from any side); the
-- one-way-ness comes from the tile past it being refused, which on every cart
-- map it is (a wall or a side-wall tile).  Gold's direction order differs from
-- Crystal's: $a0 is HOP_RIGHT here, not HOP_DOWN.
local LEDGE_FACINGS = {
  [0x0] = { right = true },               -- COLL_HOP_RIGHT
  [0x1] = { left = true },                -- COLL_HOP_LEFT
  [0x2] = { up = true },                  -- COLL_HOP_UP (unused)
  [0x3] = { down = true },                -- COLL_HOP_DOWN
  [0x4] = { down = true, right = true },  -- COLL_HOP_DOWN_RIGHT
  [0x5] = { down = true, left = true },   -- COLL_HOP_DOWN_LEFT
  [0x6] = { up = true, right = true },    -- COLL_HOP_UP_RIGHT (unused)
  [0x7] = { up = true, left = true },     -- COLL_HOP_UP_LEFT (unused)
}

-- The facings that jump this ledge, or nil for a non-ledge.
function Permissions.ledgeFacings(coll)
  if not Permissions.isLedge(coll) then return nil end
  return LEDGE_FACINGS[coll % 8]
end

-- One-way walls (HI_NYBBLE_SIDE_WALLS $b0, HI_NYBBLE_SIDE_BUOYS $c0).
--
-- GetMovementPermissions (home/map.asm) builds wTilePermissions from two
-- sources, and `.CheckLandPerms` / `.CheckSurfPerms` refuse a step whose
-- facing bit is set:
--
--   * the STANDING tile: `.MovementPermissionsData[coll & 7]`.  The stored
--     masks are DOWN/UP/LEFT/RIGHT_MASK (1/2/4/8) but they are compared
--     against FACE_* bits (FACE_DOWN=8, FACE_UP=4, FACE_LEFT=2, FACE_RIGHT=1),
--     so the row that reads DOWN_MASK blocks FACE_RIGHT -- which lands each
--     COLL_x_WALL on blocking exactly direction x.  Standing on an UP_WALL,
--     you cannot leave upward.
--   * the four NEIGHBOUR tiles.  Each arm matches its own wall kinds (below:
--     UP/UP_RIGHT/UP_LEFT; above: DOWN/DOWN_*; right: LEFT/*_LEFT; left:
--     RIGHT/*_RIGHT).
--     ../pokegold/home/map.asm:1960 -- all four arms `set RIGHT, [hl]`
--     ../pokecrystal/home/map.asm:1638 -- each arm sets its own FACE_* bit
local SIDE_BLOCKS = {
  [0x0] = { right = true },               -- COLL_RIGHT_WALL / RIGHT_BUOY
  [0x1] = { left = true },                -- COLL_LEFT_WALL / LEFT_BUOY
  [0x2] = { up = true },                  -- COLL_UP_WALL / UP_BUOY
  [0x3] = { down = true },                -- COLL_DOWN_WALL (unused)
  [0x4] = { down = true, right = true },  -- COLL_DOWN_RIGHT_WALL (unused)
  [0x5] = { down = true, left = true },   -- COLL_DOWN_LEFT_WALL (unused)
  [0x6] = { up = true, right = true },    -- COLL_UP_RIGHT_WALL (unused)
  [0x7] = { up = true, left = true },     -- COLL_UP_LEFT_WALL (unused)
}

function Permissions.isSideWall(coll)
  if coll == nil or coll < 0 then return false end
  local hi = math.floor((coll % 256) / 16)
  return hi == 0xb or hi == 0xc
end

-- Directions a player STANDING on this tile may not move, or nil.
function Permissions.sideBlocks(coll)
  if not Permissions.isSideWall(coll) then return nil end
  return SIDE_BLOCKS[coll % 8]
end

-- The neighbour arms of GetMovementPermissions.  `neighborDir` names where
-- the tile sits relative to the player ("down" = the tile below).
-- ../pokegold/home/map.asm:1946, ../pokecrystal/home/map.asm:1511
local NEIGHBOR_ARM = {
  down  = { [0x2] = true, [0x6] = true, [0x7] = true }, -- UP_WALL kinds below
  up    = { [0x3] = true, [0x4] = true, [0x5] = true }, -- DOWN_WALL kinds above
  right = { [0x1] = true, [0x5] = true, [0x7] = true }, -- LEFT_WALL kinds right
  left  = { [0x0] = true, [0x4] = true, [0x6] = true }, -- RIGHT_WALL kinds left
}

-- ../pokecrystal/home/map.asm:1638
function Permissions.neighborBlocks(neighborDir, coll)
  if not Permissions.isSideWall(coll) then return nil end
  local arm = NEIGHBOR_ARM[neighborDir]
  if not (arm and arm[coll % 8]) then return nil end
  if GameVersion.fixes().sideWallArms then return neighborDir end
  return "down"
end

function Permissions.neighborBlocksDown(neighborDir, coll)
  return Permissions.neighborBlocks(neighborDir, coll) == "down"
end

-- The whole GetMovementPermissions verdict: may a step `dir` leave (cx, cy)?
-- `collOf(x, y)` answers the collision byte, so the same rule serves the live
-- Map, the bot's planner and the offline graph without three copies drifting.
local NEIGHBOR_DELTA = {
  up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
}

function Permissions.stepPermitted(collOf, cx, cy, dir)
  local standing = Permissions.sideBlocks(collOf(cx, cy))
  if standing and standing[dir] then return false end
  if dir == "down" or GameVersion.fixes().sideWallArms then
    for nd, d in pairs(NEIGHBOR_DELTA) do
      if Permissions.neighborBlocks(nd, collOf(cx + d[1], cy + d[2])) == dir then
        return false
      end
    end
  end
  return true
end

-- WillObjectBumpIntoTile .dir_masks, engine/overworld/npc_movement.asm:116
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

function Permissions.entryBlocks(coll)
  local row = Permissions.sideBlocks(coll)
  if not row then return nil end
  local out = {}
  for d in pairs(row) do out[OPPOSITE[d]] = true end
  return out
end

-- WillObjectBumpIntoWater, engine/overworld/npc_movement.asm:60
function Permissions.objectStepPermitted(fromColl, toColl, dir)
  local leave = Permissions.sideBlocks(fromColl)
  if leave and leave[dir] then return false end
  if not Permissions.isLand(toColl) then return false end
  local enter = Permissions.entryBlocks(toColl)
  if enter and enter[dir] then return false end
  return true
end

function Permissions.isWarpCollision(coll)
  if coll == nil or coll < 0 then return false end
  -- COLL_PIT / COLL_PIT_68 plus high-nybble $7 (CheckWarpCollision /
  -- HI_NYBBLE_WARPS in engine/overworld/tile_events.asm).
  if coll == 0x60 or coll == 0x68 then return true end
  return math.floor(coll / 16) == 7
end

-- Carpet warps need a press in their direction (CheckDirectionalWarp).
local CARPET_DIR = {
  [0x70] = "down",  -- COLL_WARP_CARPET_DOWN
  [0x76] = "left",  -- COLL_WARP_CARPET_LEFT
  [0x78] = "up",    -- COLL_WARP_CARPET_UP
  [0x7e] = "right", -- COLL_WARP_CARPET_RIGHT
}

function Permissions.carpetDirection(coll)
  return CARPET_DIR[coll]
end

-- CheckWarpFacingDown (engine/overworld/tile_events.asm).  RefreshPlayerSprite
-- runs this against the tile the player ARRIVES on and calls SpawnInFacingDown
-- when it hits; every other arrival tile keeps the facing they walked in with.
-- The four `; unused` rows are transcribed rather than dropped -- the array is
-- what the cart tests against, and a tileset that ever emitted $73 would find
-- them.
local WARP_FACING_DOWN = {
  [0x71] = true, -- COLL_DOOR
  [0x79] = true, -- COLL_DOOR_79 (unused)
  [0x7a] = true, -- COLL_STAIRCASE
  [0x73] = true, -- COLL_STAIRCASE_73 (unused)
  [0x7b] = true, -- COLL_CAVE
  [0x74] = true, -- COLL_CAVE_74 (unused)
  [0x7c] = true, -- COLL_WARP_PANEL
  [0x75] = true, -- COLL_DOOR_75 (unused)
  [0x7d] = true, -- COLL_DOOR_7D (unused)
}

function Permissions.warpFacesDown(coll) return member(WARP_FACING_DOWN, coll) end

-- Immediate warp on landing (doors, stairs, caves, panels) vs carpet.
function Permissions.isImmediateWarp(coll)
  if not Permissions.isWarpCollision(coll) then return false end
  return CARPET_DIR[coll] == nil
end

return Permissions
