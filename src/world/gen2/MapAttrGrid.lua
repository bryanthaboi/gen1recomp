-- Per 8x8 cell tile id + GBC attributes, mirroring pret wSurroundingTiles +
-- wAttrmap as built by LoadOverworldAttrmapPals (engine/tilesets/map_palettes.asm).
--
-- Retail Crystal derives palette (+ VRAM bank in the palmap nybble) from the
-- tileset PalMap indexed by the metatile byte; bit 7 of the tile id is cleared
-- into the attr bank bit and the normalized id is what VRAM fetches.

local BorderFill = require("src.world.gen2.BorderFill")
local TileAttrs = require("src.world.gen2.TileAttrs")

local MapAttrGrid = {}

-- pret _LoadOverworldAttrmapPals: srl a / carry picks upper vs lower nybble;
-- res 7,[hl] clears tile bit 7 after the lookup.
function MapAttrGrid.normalizeTile(rawTileId, tileset)
  if not rawTileId then return nil, nil end
  local bankFromTile = (rawTileId >= 0x80) and 1 or 0
  local normId = rawTileId % 0x80

  local attrs = tileset and tileset.tileAttrs
  local attr
  if attrs then
    if bankFromTile == 1 then
      attr = attrs[0x80 + normId + 1] or attrs[normId + 1]
    else
      attr = attrs[normId + 1] or attrs[0x80 + normId + 1]
    end
  end
  if not attr then
    attr = TileAttrs.forTile(tileset, rawTileId)
  end

  local out = {
    palette = attr.palette,
    vramBank = (attr.vramBank ~= 0 and attr.vramBank or bankFromTile),
    priority = attr.priority,
    xFlip = attr.xFlip,
    yFlip = attr.yFlip,
  }
  return normId, out
end

function MapAttrGrid.tileAt(map, tileset, mx, my)
  local bx, by = math.floor(mx / 32), math.floor(my / 32)
  if bx < 0 or by < 0 or bx >= map.width or by >= map.height then return nil end
  local blockId = BorderFill.blockFor(
    map.blocks[by * map.width + bx + 1], map.borderBlock)
  local block = tileset.blocks and tileset.blocks[(blockId or 0) + 1]
  if not block then return nil end
  local i = math.floor((my % 32) / 8) * 4 + math.floor((mx % 32) / 8)
  return block[i + 1]
end

function MapAttrGrid.cellAt(map, tileset, mx, my)
  local raw = MapAttrGrid.tileAt(map, tileset, mx, my)
  if raw == nil then return nil end
  local tileId, attr = MapAttrGrid.normalizeTile(raw, tileset)
  return { tileId = tileId, rawTileId = raw, attr = attr }
end

-- Full map grid keyed by "mx,my" for fast lookup during overdraw.
function MapAttrGrid.build(map, tileset)
  local grid = {}
  if not (map and tileset) then return grid end
  local pw, ph = map.width * 32, map.height * 32
  for my = 0, ph - 1, 8 do
    for mx = 0, pw - 1, 8 do
      local cell = MapAttrGrid.cellAt(map, tileset, mx, my)
      if cell then grid[mx .. "," .. my] = cell end
    end
  end
  return grid
end

function MapAttrGrid.lookup(grid, mx, my)
  if not grid then return nil end
  local tx = math.floor(mx / 8) * 8
  local ty = math.floor(my / 8) * 8
  return grid[tx .. "," .. ty]
end

return MapAttrGrid
