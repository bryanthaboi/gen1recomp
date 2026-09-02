-- Per-tile GBC attribute lookup for Crystal tilesets (palette, VRAM bank,
-- flips, BG priority).  Gold and Silver keep tilePalettes only; missing
-- tileAttrs entries fall back to palette slot 1 with no bank or flags.

local TileAttrs = {}

local DEFAULT = {
  palette = 1,
  vramBank = 0,
  priority = false,
  xFlip = false,
  yFlip = false,
}

function TileAttrs.forTile(tileset, tileId)
  local attrs = tileset and tileset.tileAttrs
  if attrs then
    local a = attrs[tileId + 1]
    if a then return a end
    -- Metatile bytes are often 0-95 with bank 1 in the attr nybble; pret stores
    -- those attrs at $80+ on the PalMap (RomExtractorGen2.readCrystalPalMap).
    if tileId < 0x80 then
      a = attrs[0x80 + tileId + 1]
      if a and a.vramBank == 1 then return a end
    end
  end
  local bankFromId = (tileId >= 0x80 and tileId < 0xe0) and 1 or 0
  local normId = tileId % 0x80
  local slot = tileset and tileset.tilePalettes
    and (tileset.tilePalettes[tileId + 1]
      or (bankFromId == 1 and tileset.tilePalettes[0x80 + normId + 1])
      or tileset.tilePalettes[normId + 1]) or 1
  return {
    palette = slot,
    vramBank = bankFromId,
    priority = false,
    xFlip = false,
    yFlip = false,
  }
end

function TileAttrs.paletteSlot(tileset, tileId)
  return TileAttrs.forTile(tileset, tileId).palette
end

-- VRAM tile index in the baked 256-tile sheet (Crystal bank 0 at 0-127,
-- bank 1 at 128-255 per crystalTilesetSheet).  Metatile bytes are often
-- 0-95 with B_BG_BANK1 in the attr nibble; hardware fetches bank 1 VRAM.
function TileAttrs.sheetTileId(tileId, attr)
  if tileId >= 0x80 then return tileId end
  if attr and attr.vramBank == 1 then return 0x80 + tileId end
  return tileId
end

function TileAttrs.quadFor(atlas, tileId, attr, tilesPerRow, cache)
  local sheetId = TileAttrs.sheetTileId(tileId, attr)
  tilesPerRow = tilesPerRow or 16
  cache = cache or {}
  local q = cache[sheetId]
  if q then return q end
  local aw, ah = atlas:getDimensions()
  q = love.graphics.newQuad(
    (sheetId % tilesPerRow) * 8,
    math.floor(sheetId / tilesPerRow) * 8,
    8, 8, aw, ah)
  cache[sheetId] = q
  return q
end

local function quadSize(quad)
  if quad and quad.w and quad.h then return quad.w, quad.h end
  if quad and quad.getViewport then
    local ok, _, _, w, h = pcall(quad.getViewport, quad)
    if ok and w then return w, h end
  end
  return 8, 8
end

-- Draw an 8x8 tile (or sub-rect quad) at map/screen pixel (tx, ty).
-- Flips scale around the sub-rect centre so the tile stays in its cell.
function TileAttrs.drawFlippedTile(atlas, quad, tx, ty, attr, sx, sy)
  sx = sx or 1
  sy = sy or 1
  if not attr or (not attr.xFlip and not attr.yFlip) then
    love.graphics.draw(atlas, quad, tx, ty, 0, sx, sy)
    return
  end
  local qw, qh = quadSize(quad)
  local ox, oy = qw / 2, qh / 2
  love.graphics.draw(atlas, quad, tx + ox, ty + oy, 0,
    (attr.xFlip and -1 or 1) * sx, (attr.yFlip and -1 or 1) * sy, ox, oy)
end

return TileAttrs
