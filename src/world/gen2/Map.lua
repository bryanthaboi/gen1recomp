-- Gen 2 runtime map: block grid + COLL_* quads (not Gen 1 walkable lists).
-- Coordinates are unpadded cells (extract stores width×height blocks as-is;
-- WRAM's 3-block border is not mirrored here).

local Permissions = require("src.world.gen2.Permissions")

local Map = {}
Map.__index = Map

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
Map.DELTA = DELTA

-- The 16-tile content of a block id, through the same graft contract as
-- src/world/Map.lua:53 (mods/mapamap): native block ids resolve through the
-- tileset's `blocks` array; a block id at/above the native count is a GRAFTED
-- block (a cross-tileset paint) and resolves through the map def's
-- `graftBlocks` list, which stores the tileset-atlas slots the imported
-- graphic occupies.  Returns the tile array, or nil when unknown.
function Map.blockTiles(def, tilesetDef, id)
  if not (def and tilesetDef and tilesetDef.blocks) then return nil end
  if id == nil then return nil end
  local native = #tilesetDef.blocks
  if id < native then
    return tilesetDef.blocks[id + 1]
  end
  local g = def.graftBlocks and def.graftBlocks[id - native]
  return g and g.tiles
end

-- The warp-lookup table a Map builds once; extracted so a warp edit (place,
-- move, remove -- mods/mapamap domain/warps.lua) can rebuild the index on the
-- LIVE instance instead of recreating the Map.
function Map.buildWarpIndex(warps)
  local warpAt = {}
  for i, w in ipairs(warps or {}) do
    if w and w.x ~= nil and w.y ~= nil then
      warpAt[w.y * 1024 + w.x] = { index = i, def = w }
    end
  end
  return warpAt
end

function Map.new(def, tileset)
  local self = setmetatable({}, Map)
  self.def = def
  self.id = def.id
  self.tileset = tileset
  self.width = def.width
  self.height = def.height
  self.widthCells = def.width * 2
  self.heightCells = def.height * 2
  self.blocks = def.blocks
  self.borderBlock = def.borderBlock or 0
  self.collision = tileset.collision
  self.warps = def.warps or {}
  self.connections = def.connections or {}
  -- A Gen 1 mod reads conn.map; a Gold extraction may only carry conn.mapId,
  -- which is why World.computeNeighbors:514 reads both.  Normalise here so
  -- one read answers on either cache.
  for _, conn in pairs(self.connections) do
    if type(conn) == "table" and conn.map == nil then conn.map = conn.mapId end
  end
  -- Warp lookup by cell.
  self._warpAt = Map.buildWarpIndex(self.warps)
  return self
end

-- Warp placement/move/remove edits land in def.warps after Map.new built the
-- index, so the lookup rebuilt on the live instance (deferred to the draw
-- frame by WorldAdapter.flushLiveRebuild -- never inside the input event).
function Map:rebuildWarpIndex()
  self.warps = self.def and self.def.warps or {}
  self._warpAt = Map.buildWarpIndex(self.warps)
  return self
end

-- Re-captures every field Map.new snapshots out of the def.  Patch replay
-- (mods/mapamap on save.loaded) and editor expansion REPLACE def.blocks /
-- def.connections / width with fresh tables, but this instance kept its
-- building-time references -- cellCollision and the seam walks kept answering
-- the PRE-edit grid until the player re-entered the map.  Tileset/collision
-- are untouched: grafts rebuild through their own path.
function Map:refreshFromDef()
  local def = self.def
  if not def then return self end
  self.id = def.id
  self.width = def.width
  self.height = def.height
  self.widthCells = def.width * 2
  self.heightCells = def.height * 2
  self.blocks = def.blocks
  self.borderBlock = def.borderBlock or 0
  self.warps = def.warps or {}
  self.connections = def.connections or {}
  for _, conn in pairs(self.connections) do
    if type(conn) == "table" and conn.map == nil then conn.map = conn.mapId end
  end
  self._warpAt = Map.buildWarpIndex(self.warps)
  return self
end

function Map:inBounds(cx, cy)
  return cx >= 0 and cy >= 0
     and cx < self.widthCells and cy < self.heightCells
end

function Map:blockId(bx, by)
  if bx < 0 or by < 0 or bx >= self.width or by >= self.height then
    return self.borderBlock
  end
  return self.blocks[by * self.width + bx + 1] or 0
end

-- COLL_* byte for cell (cx, cy).  Block id 0 is impassable sentinel
-- (GetCoordTileCollision .nope → $ff).
function Map:cellCollision(cx, cy)
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  local id = self:blockId(bx, by)
  if id == 0 then return 0xff end
  local quad = self.collision and self.collision[id + 1]
  if not quad then return 0xff end
  local lx, ly = cx % 2, cy % 2
  return quad[ly * 2 + lx + 1] or 0xff
end

function Map:isWalkable(cx, cy)
  if not self:inBounds(cx, cy) then return false end
  return Permissions.isWalkable(self:cellCollision(cx, cy))
end

-- ------- the shared cell vocabulary a mod binds to
--
-- Same four names src/world/Map.lua answers, so one mod's placement and
-- behaviour code reads either generation's map (mod.world hands this object
-- out, and a mod that guards on `map.isWalkableCell and ...` otherwise
-- silently concludes every cell is walkable, dry and grassless).  Gen 1
-- answers from tile ids and a per-tileset set; Gold answers from the COLL_*
-- byte, which is the same question asked of a different grid.

-- The Gen 1 name for "the byte that decides this cell".  Gold's is the
-- collision quad entry, not a tile id, so the ids are NOT comparable across
-- generations: use the predicates, not the number.
local warnedCellTile = false

function Map:cellTile(cx, cy)
  -- Loud once, because the call SUCCEEDS and the number is plausible: a mod
  -- comparing it to 0x52 (Gen 1 grass) or 0x14 (water) gets a wrong answer
  -- with nothing to show for it.  No Gen 2 caller reaches this name.
  if not warnedCellTile then
    warnedCellTile = true
    require("src.core.Logger").warn(
      "Map:cellTile on Gold returns a COLL_* byte, not a Gen 1 tile id; the "
      .. "two number spaces are unrelated -- use the cell predicates")
  end
  return self:cellCollision(cx, cy)
end

function Map:isWalkableCell(cx, cy)
  return self:isWalkable(cx, cy)
end

function Map:isWaterCell(cx, cy)
  if not self:inBounds(cx, cy) then return false end
  return Permissions.isWater(self:cellCollision(cx, cy))
end

-- Off-map cells never count as grass, for the reason Gen 1 guards the same
-- way (src/world/Map.lua:224): the border block is filler scenery.
function Map:isGrassCell(cx, cy)
  if not self:inBounds(cx, cy) then return false end
  return Permissions.isGrass(self:cellCollision(cx, cy))
end

function Map:warpAt(cx, cy)
  return self._warpAt[cy * 1024 + cx]
end

-- Three more Gen 1 spellings, for the reason the four above exist: a mod
-- guarding on `map.isCounterCell and ...` otherwise sees no counter anywhere.
function Map:warpAtCell(cx, cy)
  return self:warpAt(cx, cy)
end

function Map:isCounterCell(cx, cy)
  if not self:inBounds(cx, cy) then return false end
  return Permissions.isCounter(self:cellCollision(cx, cy))
end

-- Gen 1 asks this of a def plus the outdoor tileset set; Gold's header says
-- so outright, so the second argument is ignored.
function Map.isOutside(def, _tilesets)
  local env = def and def.environment
  return env == "TOWN" or env == "ROUTE"
end

-- Gen 1 keeps isOutdoor NARROWER than isOutside (src/world/Map.lua:148, :155);
-- Gold decides both from the header's environment byte, so they collapse.
function Map.isOutdoor(def)
  if def and def.outdoor ~= nil then return def.outdoor end
  return Map.isOutside(def)
end

-- src/world/Map.lua:176 verbatim: def.region, else the id prefix.  Gold's
-- defs carry no region, so the prefix arm is the live one.
function Map.inRegion(def, region, prefix)
  if not def then return false end
  if def.region ~= nil then return def.region == region end
  return prefix ~= nil and def.id ~= nil and def.id:find(prefix, 1, true) == 1
end

-- Gen 1 asks the SPRITE NAME (src/world/Map.lua:191); on Gold a boulder is
-- the STRENGTH_BOULDER movement byte (src/world/gen2/Npc.lua:56), so a
-- sprite-name test here would answer false for every real boulder.
function Map.isPushable(objDef)
  if not objDef then return false end
  if objDef.pushable ~= nil then return objDef.pushable end
  return objDef.movement == 0x19
end

-- ------- the Gen 1 spellings that read a raw def
--
-- Gen 1 answers these from tile ids and the tileset's walkable list; Gold
-- answers from the COLL_* quad, which lives on the TILESET either way, so an
-- unloaded neighbour (a connection crossing) can be asked without a Map.

-- The cell's COLL_* byte off a raw def.  NOT a tile id: the number space is
-- unrelated to Gen 1's, so compare with the predicates below, never a literal.
function Map.defCellTile(def, tilesetDef, cx, cy)
  if not (def and tilesetDef and tilesetDef.collision and def.blocks) then
    return nil
  end
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  local id
  if bx < 0 or by < 0 or bx >= def.width or by >= def.height then
    id = def.borderBlock or 0
  else
    id = def.blocks[by * def.width + bx + 1] or 0
  end
  if id == 0 then return 0xff end
  local quad = tilesetDef.collision[id + 1]
  if not quad then return 0xff end
  return quad[(cy % 2) * 2 + (cx % 2) + 1] or 0xff
end

function Map.defIsWalkableCell(def, tilesetDef, cx, cy)
  local coll = Map.defCellTile(def, tilesetDef, cx, cy)
  if coll == nil then return false end
  return Permissions.isWalkable(coll)
end

function Map.defIsWaterCell(def, tilesetDef, cx, cy)
  local coll = Map.defCellTile(def, tilesetDef, cx, cy)
  if coll == nil then return false end
  return Permissions.isWater(coll)
end

-- Fails CLOSED on missing data, for the reason src/world/Map.lua:104 does:
-- no data means we cannot prove the landing is safe, so the step bumps.
function Map.defPassable(def, tilesetDef, cx, cy, surfing)
  if not (def and tilesetDef and tilesetDef.collision and def.blocks) then
    return false
  end
  if Map.defIsWalkableCell(def, tilesetDef, cx, cy) then return true end
  if surfing then
    local coll = Map.defCellTile(def, tilesetDef, cx, cy)
    return coll ~= nil and Permissions.surfable(coll) ~= nil
  end
  return false
end

-- ------- the Gen 1 instance spellings a mod calls on world.map

-- Gen 1's name for blockId, same border extension (src/world/Map.lua:196).
function Map:blockAt(bx, by)
  return self:blockId(bx, by)
end

-- Writes the block grid in place and nothing else, exactly as
-- src/world/Map.lua:247 does.  The VISIBLE edit is World:changeBlock, which
-- also records the blockEdits undo a map reload restores from -- a bare write
-- here leaves a Cut tree gone forever.
function Map:setBlock(bx, by, block)
  if bx < 0 or by < 0 or bx >= self.width or by >= self.height then return end
  self.blocks[by * self.width + bx + 1] = block
end

-- Graphics tile id on the 8px grid, border-extended: the same math
-- World:bgTileAt (src/world/gen2/World.lua:7728) does in pixels.  Gen 2
-- blocks are 4x4 tiles too, so src/world/Map.lua:204's index math ports
-- unchanged.  Border cells read the border block, not BorderFill.blockFor.
function Map:tileAt(tx, ty)
  local blocks = self.tileset and self.tileset.blocks
  if not blocks then return nil end
  local id = self:blockId(math.floor(tx / 4), math.floor(ty / 4))
  local block = Map.blockTiles(self.def, self.tileset, id)
  if not block then return nil end
  return block[(ty % 4) * 4 + (tx % 4) + 1]
end

-- Gold has no door TILE set: a door is a warp collision kind.  This is the
-- narrow arm (a door walked INTO), so a floor mat does not answer true.
function Map:isDoorTileCell(cx, cy)
  if not self:inBounds(cx, cy) then return false end
  return Permissions.isImmediateWarp(self:cellCollision(cx, cy))
end

-- Gen 1 spells this as two sets (doors OR warp-activating tiles); Gold's
-- warp collision kinds are that union already.
function Map:isWarpTileCell(cx, cy)
  if not self:inBounds(cx, cy) then return false end
  return Permissions.isWarpCollision(self:cellCollision(cx, cy))
end

-- Coordinate-only, so it cannot apply the facing and event filters
-- World:bgEventAt (src/world/gen2/World.lua:7084) applies: it reports bg
-- events the engine would not read.  The record is a bgEvent, not a Gen 1
-- sign -- sign.text is nil on Gold.
function Map:signAtCell(cx, cy)
  for _, ev in ipairs(self.def and self.def.bgEvents or {}) do
    if ev.x == cx and ev.y == cy then return ev end
  end
  return nil
end

-- GetMovementPermissions (home/map.asm): may a step `dir` LEAVE (cx, cy)?
--
-- Two refusals, both invisible to a plain walkable test.  The STANDING tile's
-- side-wall kind blocks its own directions (on an UP_WALL you cannot move up).
-- And Gold's four neighbour arms each set the FACE_DOWN bit when the adjacent
-- tile is their wall kind, so a matching neighbour -- on real maps, an UP_WALL
-- below -- forbids the DOWN step.  This is what ends an Ice Path slide on the
-- last ice cell above the $b2 strip instead of gliding onto it, and that rest
-- chain is the only route to HM07 WATERFALL.  See Permissions.sideBlocks /
-- neighborBlocksDown for the cart derivation.
function Map:stepPermitted(cx, cy, dir)
  return Permissions.stepPermitted(
    function(x, y) return self:cellCollision(x, y) end, cx, cy, dir)
end

-- CanObjectMoveInDirection, engine/overworld/npc_movement.asm:1
-- GetCoordTileCollision's .nope, ../pokegold/home/map.asm:2095
function Map:objectStepPermitted(cx, cy, dir)
  local d = DELTA[dir]
  if not d then return false end
  local tx, ty = cx + d[1], cy + d[2]
  if not self:inBounds(tx, ty) then return false end
  return Permissions.objectStepPermitted(
    self:cellCollision(cx, cy), self:cellCollision(tx, ty), dir)
end

function Map:connection(dir)
  return self.connections[dir]
end

-- Destination cell after stepping off this edge onto a connected map.
-- Same strip math as Gen 1 (offset is in blocks).  Returns nil if no conn.
function Map.connectionLanding(def, conn, dir, fromCx, fromCy)
  if not (def and conn) then return nil end
  local destW, destH = def.width * 2, def.height * 2
  local offset = conn.offset or 0
  local x, y
  if dir == "up" then
    x, y = fromCx - offset * 2, destH - 1
  elseif dir == "down" then
    x, y = fromCx - offset * 2, 0
  elseif dir == "left" then
    x, y = destW - 1, fromCy - offset * 2
  else
    x, y = 0, fromCy - offset * 2
  end
  x = math.max(0, math.min(destW - 1, x))
  y = math.max(0, math.min(destH - 1, y))
  return x, y
end

return Map
