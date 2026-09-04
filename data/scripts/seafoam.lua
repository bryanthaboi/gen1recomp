-- Seafoam Islands boulder/current puzzle wiring + the Vermilion Gym
-- locked door (map-enter hooks; the mechanics themselves live in
-- src/world/OverworldController.lua driven by field.seafoam and the
-- trash can data).
--
-- Sources: scripts/SeafoamIslands1F.asm / B1F.asm / B3F.asm / B4F.asm
-- (currents, holes), scripts/VermilionGym.asm (VermilionGymSetDoorTile:
-- the door block at (2,2) is $24 until EVENT_2ND_LOCK_OPENED, then $5).
--
-- The 1F->B1F->B2F->B3F->B4F boulder cascade is fully data-driven via
-- field.seafoam (SEAFOAM_ISLANDS_1F/B1F/B3F holes+holeDestination and
-- B3F's pluggedByHolesOn) plus the generic
-- OverworldState:boulderIntoHole in src/world/OverworldController.lua;
-- no per-map onEnter hook is needed for the boulders.

local M = {}

M.VERMILION_GYM = {
  onEnter = function(game, ow)
    if not game.save.flags.EVENT_2ND_LOCK_OPENED then
      ow:replaceBlock(2, 2, 36) -- $24: the closed double door
    end
  end,
}

-- The PLAYER falling down those same holes (#599).  field.seafoam's holes
-- carry only the BOULDER's object cell on the floor below (landsAt), not
-- the player's landing, so the player's landing is spelled out here: it
-- comes from data/maps/special_warps.asm DungeonWarpList/DungeonWarpData,
-- which the importer does not extract.  Same shape as MANSION_HOLES in
-- data/scripts/story6.lua and VICTORY_ROAD_3F.onStep in
-- data/scripts/story.lua; CAVERN $22 is a walkable tile, so the fall has
-- to be an onStep, not a collision block.
--
-- Sources: scripts/SeafoamIslands1F.asm Seafoam1HolesCoords (17,6)/(24,6),
-- B1F.asm Seafoam2HolesCoords (18,6)/(23,6), B2F.asm Seafoam3HolesCoords
-- (19,6)/(22,6), B3F.asm Seafoam4HolesCoords (3,16)/(6,16).  Each floor
-- sets wDungeonWarpDestinationMap and calls IsPlayerOnDungeonWarp, and
-- wCoordIndex picks that floor's DungeonWarpData row.  Unconditional in
-- the original: a plugged hole still drops the player.  The B3F and B4F
-- landings are water; setMap's CheckForceBikeOrSurf pass
-- (OverworldState:checkForcedMovement) mounts SURF on arrival.
local HOLE_FALLS = {
  SEAFOAM_ISLANDS_1F  = { { 17, 6, "SEAFOAM_ISLANDS_B1F", 18, 7 },
                          { 24, 6, "SEAFOAM_ISLANDS_B1F", 23, 7 } },
  SEAFOAM_ISLANDS_B1F = { { 18, 6, "SEAFOAM_ISLANDS_B2F", 19, 7 },
                          { 23, 6, "SEAFOAM_ISLANDS_B2F", 22, 7 } },
  SEAFOAM_ISLANDS_B2F = { { 19, 6, "SEAFOAM_ISLANDS_B3F", 18, 7 },
                          { 22, 6, "SEAFOAM_ISLANDS_B3F", 19, 7 } },
  SEAFOAM_ISLANDS_B3F = { {  3, 16, "SEAFOAM_ISLANDS_B4F", 4, 14 },
                          {  6, 16, "SEAFOAM_ISLANDS_B4F", 5, 14 } },
}

for mapId, holes in pairs(HOLE_FALLS) do
  M[mapId] = M[mapId] or {}
  M[mapId].onStep = function(game, ow, x, y)
    for _, h in ipairs(holes) do
      if x == h[1] and y == h[2] then
        ow:fallThroughHole(h[3], h[4], h[5], ow.player.facing)
        return true
      end
    end
    return false
  end
end

return M
