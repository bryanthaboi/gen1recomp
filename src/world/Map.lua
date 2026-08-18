-- Runtime map built from generated data.  All queries use "cells": the
-- 16x16 walk grid (2x2 tiles).  A map is width x height blocks; each block
-- is 2x2 cells (4x4 tiles).
--
-- Collision follows the original engine: a cell is passable when the
-- BOTTOM-LEFT 8x8 tile of the cell is in the tileset's walkable list
-- (pokered checks the tile at the sprite's feet).  Doors, warp tiles and
-- grass use the same convention.

local Map = {}
Map.__index = Map

-- Stale-cache fallbacks for the tileset properties the importer does not
-- stamp yet (item_effects.asm IsNextTileShoreOrWater, home/overworld.asm
-- CollisionCheckOnWater): $14 is water everywhere; the shore tiles $32 and
-- $48 (Safari Zone) everywhere EXCEPT SHIP_PORT, where $32 is the dock's
-- boarding platform -- a land tile.  A tileset record that carries
-- waterTiles/shoreTiles wins outright, which is how a new tileset gets
-- surfable water without naming Kanto's.
local WATER_TILES = { 0x14 }
local SHORE_TILES = { 0x32, 0x48 }
local NO_SHORE_TILESETS = { SHIP_PORT = true }

-- what counts as "outside" for the wLastMap memory (CheckIfInOutsideMap)
local OUTSIDE_TILESETS = { "OVERWORLD", "PLATEAU" }

-- pokered's fly destination gate: BuildFlyLocationsList
-- (engine/items/town_map.asm) walks map ids 0..NUM_CITY_MAPS-1, the eleven
-- towns PALLET_TOWN..SAFFRON_CITY, so routes never appear even though
-- ROUTE_4/ROUTE_10 carry fly-warp landing spots (those exist for the
-- dungeon-escape/heal tables, special_warps.asm FlyWarpDataPtr)
local NUM_CITY_MAPS = 11

-- warp pads and fall-through holes (data/tilesets/warp_pad_hole_tile_ids
-- .asm WarpPadAndHoleData); a tileset record carrying warpPadTiles
-- ({ [tileId] = "pad"|"hole" }) wins over these vanilla rows
local WARP_PAD_TILES = {
  FACILITY = { [0x20] = "pad", [0x11] = "hole" },
  CAVERN = { [0x22] = "hole" },
  INTERIOR = { [0x55] = "pad" },
}

local function hashSet(list, into)
  for _, t in ipairs(list) do into[t] = true end
  return into
end

-- The 16-tile content of a block: native block ids resolve through the
-- tileset's `blocks` array; a block id at/above the native count is a
-- GRAFTED block (cross-tileset paint, mods/mapamap) and resolves through the
-- map def's `graftBlocks` list, which stores the tileset-atlas slots the
-- imported graphic occupies.  Returns the tile array, or nil when unknown.
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

-- Collision tile (bottom-left 8x8) of a cell on an UNLOADED map def --
-- the connected neighbor during an edge crossing.  pokered's
-- GetTileAndCoordsInFrontOfPlayer / collision checks read the neighbor
-- strip's tile bytes the same way.
function Map.defCellTile(def, tilesetDef, cx, cy)
  if not (def and tilesetDef and tilesetDef.blocks) then return nil end
  local tx, ty = cx * 2, cy * 2 + 1
  local bx, by = math.floor(tx / 4), math.floor(ty / 4)
  local id
  if bx < 0 or by < 0 or bx >= def.width or by >= def.height then
    id = def.borderBlock
  else
    id = def.blocks[by * def.width + bx + 1]
  end
  local block = Map.blockTiles(def, tilesetDef, id or 0)
  if not block then return nil end
  return block[(ty % 4) * 4 + (tx % 4) + 1]
end

local function defWaterTileSet(def, tilesetDef)
  local water = {}
  hashSet(tilesetDef.waterTiles or WATER_TILES, water)
  local shore = tilesetDef.shoreTiles
  if shore == nil and not NO_SHORE_TILESETS[def.tileset] then shore = SHORE_TILES end
  hashSet(shore or {}, water)
  return water
end

-- Water/shore on an unloaded map def (same tile ids as Map:isWaterCell).
function Map.defIsWaterCell(def, tilesetDef, cx, cy)
  local tile = Map.defCellTile(def, tilesetDef, cx, cy)
  if tile == nil then return false end
  return defWaterTileSet(def, tilesetDef)[tile] or false
end

function Map.defIsWalkableCell(def, tilesetDef, cx, cy)
  if not (tilesetDef and tilesetDef.walkable) then return false end
  local tile = Map.defCellTile(def, tilesetDef, cx, cy)
  if tile == nil then return false end
  for _, t in ipairs(tilesetDef.walkable) do
    if t == tile then return true end
  end
  return false
end

-- Passability of a cell of an UNLOADED map def -- the connected neighbor
-- during an edge crossing.  pokered's collision check reads the neighbor
-- strip's tile bytes, so a step off the map edge onto a solid tile of
-- the connected map bumps exactly like an in-map wall; the port needs
-- the same read without building the whole Map.  Same math as cellTile
-- on the raw blocks, honoring the surf rule (water/shore passable only
-- while surfing, same fallbacks as Map.new).
function Map.defPassable(def, tilesetDef, cx, cy, surfing)
  -- Fail closed: a missing tileset used to return true and re-open the
  -- Pallet south-shore stranding (cross onto ROUTE_21 solids). No data
  -- means we cannot prove the landing is safe, so the step bumps.
  if not (def and tilesetDef and tilesetDef.blocks and tilesetDef.walkable) then
    return false
  end
  if Map.defIsWalkableCell(def, tilesetDef, cx, cy) then return true end
  if surfing and Map.defIsWaterCell(def, tilesetDef, cx, cy) then return true end
  return false
end

function Map.new(def, tilesetDef)
  local self = setmetatable({}, Map)
  self.def = def
  self.tileset = tilesetDef
  self.id = def.id
  self.widthCells = def.width * 2
  self.heightCells = def.height * 2

  self.walkable = {}
  for _, t in ipairs(tilesetDef.walkable) do self.walkable[t] = true end
  self.doorTiles = {}
  for _, t in ipairs(tilesetDef.doorTiles or {}) do self.doorTiles[t] = true end
  self.warpTiles = {}
  for _, t in ipairs(tilesetDef.warpTiles or {}) do self.warpTiles[t] = true end
  -- water and shore share one lookup: both are surfable, only the caller's
  -- water_tilesets.asm membership check separates them
  self.waterTiles = hashSet(tilesetDef.waterTiles or WATER_TILES, {})
  local shore = tilesetDef.shoreTiles
  if shore == nil and not NO_SHORE_TILESETS[def.tileset] then shore = SHORE_TILES end
  hashSet(shore or {}, self.waterTiles)

  self.warpAt = {}
  for i, w in ipairs(def.warps or {}) do
    self.warpAt[w.y * self.widthCells + w.x] = { index = i, def = w }
  end
  self.signAt = {}
  for _, s in ipairs(def.signs or {}) do
    self.signAt[s.y * self.widthCells + s.x] = s
  end
  return self
end

-- ------- map record properties (authored maps set them; vanilla falls back)

-- town/route surface: door SFX, the walk-out step, the Fly menu and the
-- town map all mean this one
function Map.isOutdoor(def)
  if def.outdoor ~= nil then return def.outdoor end
  return def.tileset == "OVERWORLD"
end

-- CheckIfInOutsideMap, a strictly wider set: Route 23 / Indigo Plateau are
-- outside for the wLastMap memory without being outdoor for the door SFX
function Map.isOutside(def, tilesets)
  if Map.isOutdoor(def) then return true end
  for _, ts in ipairs(tilesets or OUTSIDE_TILESETS) do
    if ts == def.tileset then return true end
  end
  return false
end

-- FLY destination (LoadTownMap_Fly / BuildFlyLocationsList): the eleven
-- towns, map indices 0..NUM_CITY_MAPS-1.  ROUTE_4 and ROUTE_10 are outdoor
-- and have fly warps but are not towns, so the outdoor test alone offered
-- their Pokemon Centers as fly targets (#788).  Maps without a vanilla
-- index (mod-authored) keep the old outdoor/PLATEAU surface test, which is
-- how a mod adds its own fly town.
function Map.isFlyTown(def)
  if def.index ~= nil then return def.index < NUM_CITY_MAPS end
  return Map.isOutdoor(def) or def.tileset == "PLATEAU"
end

-- region groups maps a rule applies to without naming them; the id prefix
-- is the fallback for caches that predate the property
function Map.inRegion(def, region, prefix)
  if def.region ~= nil then return def.region == region end
  return prefix ~= nil and def.id:find(prefix, 1, true) == 1
end

-- unidentifiable wild battles on this map unless the player holds an item
function Map.ghostBattles(def)
  if def.ghostBattles ~= nil then return def.ghostBattles end
  if def.id:find("POKEMON_TOWER", 1, true) == 1 then
    return { unlessItem = "SILPH_SCOPE" }
  end
  return nil
end

-- strength-pushable map objects (engine/overworld/push_boulder.asm)
function Map.isPushable(objDef)
  if objDef.pushable ~= nil then return objDef.pushable end
  return objDef.sprite == "SPRITE_BOULDER"
end

function Map:blockAt(bx, by)
  if bx < 0 or by < 0 or bx >= self.def.width or by >= self.def.height then
    return self.def.borderBlock
  end
  return self.def.blocks[by * self.def.width + bx + 1]
end

-- tile id at tile coordinates (8px grid), border-extended.  Block content is
-- resolved through Map.blockTiles so a grafted (cross-tileset) block id reads
-- its def.graftBlocks entry too.
function Map:tileAt(tx, ty)
  local bx, by = math.floor(tx / 4), math.floor(ty / 4)
  local block = Map.blockTiles(self.def, self.tileset, self:blockAt(bx, by))
  local ix = (ty % 4) * 4 + (tx % 4) + 1
  return block and block[ix]
end

-- the collision tile of a cell: bottom-left 8x8 tile
function Map:cellTile(cx, cy)
  return self:tileAt(cx * 2, cy * 2 + 1)
end

function Map:inBounds(cx, cy)
  return cx >= 0 and cy >= 0 and cx < self.widthCells and cy < self.heightCells
end

function Map:isWalkableCell(cx, cy)
  return self.walkable[self:cellTile(cx, cy)] or false
end

function Map:isGrassCell(cx, cy)
  -- Off-map cells never count as tall grass (issue #217).  cellTile
  -- border-extends out-of-bounds coordinates with the map's borderBlock,
  -- and some border blocks (e.g. ROUTE_1's block 11) have the grass tile
  -- ($52 = 82) in their bottom row -- filler scenery, never standable
  -- grass.  During a map-connection seam step crossConnection parks the
  -- player one cell before the entry point (cellY = -1 crossing Viridian
  -- City -> Route 1), so without this guard the feet-overdraw painted an
  -- animated grass tuft over the player's head for the whole step.  pokered
  -- only ever reads $52 from loaded map tiles, not the border filler.
  if not self:inBounds(cx, cy) then return false end
  local grass = self.tileset.grassTile
  return grass ~= nil and self:cellTile(cx, cy) == grass
end

-- Water and eastern-shore tiles, from the tileset's waterTiles/shoreTiles
-- (hash sets built in Map.new).  Tileset membership in water_tilesets.asm
-- is checked by the caller.
function Map:isWaterCell(cx, cy)
  return self.waterTiles[self:cellTile(cx, cy)] or false
end

-- Replace a block (Cut trees); the caller rebuilds the renderer.
function Map:setBlock(bx, by, block)
  if bx < 0 or by < 0 or bx >= self.def.width or by >= self.def.height then
    return
  end
  self.def.blocks[by * self.def.width + bx + 1] = block
end

-- true if the cell's collision tile is a door tile
-- (pokered IsPlayerStandingOnDoorTile)
function Map:isDoorTileCell(cx, cy)
  return self.doorTiles[self:cellTile(cx, cy)] or false
end

-- true if the cell's collision tile is a door or warp-activating tile
function Map:isWarpTileCell(cx, cy)
  local t = self:cellTile(cx, cy)
  return self.doorTiles[t] or self.warpTiles[t] or false
end

-- "pad"/"hole" when the cell's collision tile is a teleporter warp pad or
-- a fall-through hole (IsPlayerStandingOnWarpPadOrHole), nil otherwise
function Map:warpPadOrHoleAt(cx, cy)
  local table_ = self.tileset.warpPadTiles or WARP_PAD_TILES[self.def.tileset]
  if not table_ then return nil end
  return table_[self:cellTile(cx, cy)]
end

-- counter tiles allow talking to NPCs across them (mart clerks, nurses)
function Map:isCounterCell(cx, cy)
  local t = self:cellTile(cx, cy)
  for _, c in ipairs(self.tileset.counterTiles or {}) do
    if c == t then return true end
  end
  return false
end

function Map:rebuildWarpIndex()
  self.warpAt = {}
  for i, w in ipairs(self.def.warps or {}) do
    self.warpAt[w.y * self.widthCells + w.x] = { index = i, def = w }
  end
end

function Map:warpAtCell(cx, cy)
  return self.warpAt[cy * self.widthCells + cx]
end

function Map:signAtCell(cx, cy)
  return self.signAt[cy * self.widthCells + cx]
end

function Map:connection(dir)
  return self.def.connections and self.def.connections[dir]
end

return Map
