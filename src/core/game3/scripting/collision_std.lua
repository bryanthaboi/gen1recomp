-- Gen3 collision → shared std script keys (mirrors Gen2 TILE_COLLISION_STD_SCRIPTS).
-- Wired from FRLG metatile behaviors in collision.lua (MB_PC → COLL_PC, etc.).
-- Any map whose extract tagged a tile with that behavior gets this script — no
-- per-map coordinate hardcoding.

local CollisionStd = {}

-- Gen2 COLL_* bytes we emit from sevii/gba/collision.lua
CollisionStd.COLL_PC = 0x93
CollisionStd.COLL_COUNTER = 0x90
CollisionStd.COLL_BOOKSHELF = 0x91

-- Facing this collision runs the named game3 script (shared, not map-local).
CollisionStd.SCRIPTS = {
  [0x93] = "EventScript_PC", -- MB_PC → COLL_PC
}

function CollisionStd.scriptFor(coll)
  if coll == nil then return nil end
  return CollisionStd.SCRIPTS[coll % 256]
end

function CollisionStd.isCounter(coll)
  if coll == nil then return false end
  return (coll % 256) == CollisionStd.COLL_COUNTER
end

return CollisionStd
