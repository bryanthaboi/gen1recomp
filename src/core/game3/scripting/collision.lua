-- FRLG metatile behavior → Gen1/Gen2 collision bytes (Island 1 seed table).

local Collision = {}

local WATER_BEH = {
  [0x10] = true, [0x11] = true, [0x12] = true, [0x13] = true,
  [0x15] = true, [0x16] = true, [0x17] = true, [0x1A] = true, [0x1B] = true,
}
local JUMP_DIR = {
  [0x38] = "E", [0x39] = "W", [0x3A] = "N", [0x3B] = "S",
}
local DOOR_BEH = {
  [0x60] = true, [0x62] = true, [0x63] = true, [0x64] = true,
  [0x65] = true, [0x67] = true, [0x69] = true,
}
-- MB_ROCK_STAIRS: walkable tier bands (not warps).
local STAIR_BEH = { [0x2A] = true }
-- MB_UP/DOWN_ESCALATOR (+ ladder/warp stairs): Gen2 COLL_STAIRCASE.
local WARP_STAIR_BEH = {
  [0x61] = true, -- MB_LADDER
  [0x6A] = true, -- MB_UP_ESCALATOR
  [0x6B] = true, -- MB_DOWN_ESCALATOR
  [0x6C] = true, [0x6D] = true, [0x6E] = true, [0x6F] = true,
}
local SIGN_BEH = { [0x84] = true, [0x87] = true, [0x88] = true }
local PC_BEH = { [0x83] = true }           -- MB_PC
local COUNTER_BEH = { [0x80] = true }      -- MB_COUNTER (nurse desk)
local MOUNTAIN_TOP_BEH = 0x0C

local TREE_MIDS = {
  [0x00A] = true, [0x00B] = true, [0x00C] = true, [0x00E] = true,
  [0x00F] = true, [0x013] = true,
}
for mid = 0x014, 0x01F do TREE_MIDS[mid] = true end
for mid = 0x024, 0x027 do TREE_MIDS[mid] = true end

local SHRUB_MIDS = {
  [0x286] = true, [0x287] = true, [0x28E] = true, [0x28F] = true,
  [0x296] = true, [0x29E] = true, [0x29F] = true,
  [0x2A5] = true, [0x2A6] = true, [0x2A7] = true,
  [0x2AD] = true, [0x2AE] = true, [0x2AF] = true,
}

local PIER_MIDS = {
  [0x1C5] = true, [0x1C6] = true, [0x1C7] = true, [0x2B4] = true, [0x2B6] = true,
}

local CLIFF_MIDS = {
  [0x070] = true, [0x071] = true, [0x072] = true, [0x073] = true,
  [0x075] = true, [0x07A] = true, [0x07B] = true, [0x07C] = true, [0x07D] = true,
  [0x0B2] = true, [0x0B3] = true, [0x0B4] = true, [0x0B5] = true,
}

local LEDGE_COLL = { E = 0xA0, W = 0xA1, N = 0xA2, S = 0xA3 }
local CAT_COLL = {
  WATER = 0x29,
  TALL_GRASS = 0x18,
  TREE = 0x07,
  CLIFF = 0x07,
  COAST_CLIFF = 0x07,
  BLOCKED = 0x07,
  BUILDING = 0x07,
  -- Outdoor doorway default. Indoor exits override in seed() — see below.
  DOOR = 0x71,
  SIGN = 0x82,
  PC = 0x93,       -- Gen2 COLL_PC → TileCollisionStdScripts PCScript
  COUNTER = 0x90,  -- Gen2 COLL_COUNTER → talk through desk
  CAVE = 0x2B,
  STAIR = 0x00,
  SAND = 0x00,
  PATH = 0x00,
  PIER = 0x00,
  SHORT_GRASS = 0x00,
  TOWN_PATH = 0x00,
  ROCK_DECK = 0x00,
  LEDGE = 0xA3,
}

local NUM_PRIMARY = 640

--- Map grid collision nibble (0–3) from FRLG map cell — impassable if ~= 0.
function Collision.classify(mid, mapColl, behavior, kind)
  kind = kind or "route"
  local beh = behavior or 0
  if WATER_BEH[beh] then return "WATER", nil end
  if beh == 0x02 then return "TALL_GRASS", nil end
  if beh == 0x21 then return "SAND", nil end
  if JUMP_DIR[beh] then return "LEDGE", JUMP_DIR[beh] end
  if WARP_STAIR_BEH[beh] then return "STAIR", "WARP" end
  if STAIR_BEH[beh] then return "STAIR", nil end
  if DOOR_BEH[beh] then return "DOOR", nil end
  if SIGN_BEH[beh] then return "SIGN", nil end
  if PC_BEH[beh] then return "PC", nil end
  if COUNTER_BEH[beh] then return "COUNTER", nil end
  if beh == 0x08 then return "CAVE", nil end
  if beh == MOUNTAIN_TOP_BEH then return "ROCK_DECK", nil end
  -- Outdoor General-tileset tree IDs. If mapColl == 0, it is a walkable path behind tree tops.
  if TREE_MIDS[mid] and kind ~= "indoor" then
    if mapColl ~= 0 then return "TREE", nil end
    return (kind == "town") and "TOWN_PATH" or "SHORT_GRASS", nil
  end
  -- Shrub list is primary-tileset decoration only. On Sevii secondary those
  -- same numeric ids are house roofs/walls (were mis-tagged as grass road).
  if SHRUB_MIDS[mid] and mid < NUM_PRIMARY then
    if mapColl ~= 0 then return "BLOCKED", nil end
    return (kind == "town") and "TOWN_PATH" or "SHORT_GRASS", nil
  end
  -- Cliff list is outdoor rock faces; indoor building tilesets reuse ids.
  if CLIFF_MIDS[mid] and kind ~= "indoor" then
    if mapColl ~= 0 then return "CLIFF", nil end
    return (kind == "town") and "TOWN_PATH" or "SHORT_GRASS", nil
  end
  if PIER_MIDS[mid] and mapColl == 0 then return "PIER", nil end
  if beh >= 0x30 and beh <= 0x37 then return "CLIFF", nil end
  -- Secondary solids: houses in town; interior walls/furniture indoors.
  -- On routes the same secondary sheet is cliff / rock — not building-front.
  if mid >= NUM_PRIMARY and kind == "town" then
    if mapColl ~= 0 then return "BUILDING", nil end
  end
  if mid >= NUM_PRIMARY and kind == "indoor" and mapColl ~= 0 then
    return "BUILDING", nil
  end
  if mid >= NUM_PRIMARY and mapColl ~= 0 then return "CLIFF", nil end
  if mapColl ~= 0 and mid < 0x100 and beh == 0 then return "BLOCKED", nil end
  if mapColl ~= 0 then return "BLOCKED", nil end
  if kind == "town" then return "TOWN_PATH", nil end
  return "SHORT_GRASS", nil
end

-- Gen2 spawnFacing: COLL_DOOR / COLL_STAIRCASE force face-down on arrival.
-- Outdoor doors want that (exit onto the street facing out). Indoor door
-- mats and escalators must NOT — keep the facing you walked in with.
-- 0x72 is an unused HI_NYBBLE_WARPS id: immediate warp, walkable, no
-- CheckWarpFacingDown / doorForcedDirection.
local COLL_DOOR = 0x71
local COLL_WARP_KEEP_FACING = 0x72

function Collision.seed(category, ledgeDir, kind)
  if category == "LEDGE" then
    return LEDGE_COLL[ledgeDir or "S"] or 0xA3
  end
  if category == "DOOR" then
    if kind == "indoor" then return COLL_WARP_KEEP_FACING end
    return COLL_DOOR
  end
  if category == "STAIR" and ledgeDir == "WARP" then
    return COLL_WARP_KEEP_FACING
  end
  return CAT_COLL[category] or 0x00
end

function Collision.fromCell(mid, mapColl, behavior, kind)
  local cat, ledge = Collision.classify(mid, mapColl, behavior, kind)
  return Collision.seed(cat, ledge, kind), cat, ledge
end

return Collision
