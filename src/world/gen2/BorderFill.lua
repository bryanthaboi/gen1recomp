-- The border block that surrounds a map.
--
-- home/map.asm LoadBlockData byte-fills wOverworldMapBlocks with 0 before
-- ChangeMap copies the map's own blocks into the middle of it, and then
-- LoadMetatiles resolves every block it reads:
--
--   ; If the current map block is a border block, load the border block.
--   ld a, [de]
--   and a
--   jr nz, .ok
--   ld a, [wMapBorderBlock]
--
-- So block id 0 is not "tileset block 0": it is a stand-in for the map
-- header's border block, both in the margin ChangeMap never wrote to and
-- anywhere inside the map's own block list.  A map smaller than the 20x18
-- viewport (GOLDENROD_DEPT_STORE_ELEVATOR is 2x2 blocks) is almost all
-- margin, which is why it showed as black around a postage stamp instead of
-- the wall block the cart tiles across the whole screen.
--
-- The fill is one 32x32 bake wrap-tiled over the view, drawn under the map
-- and the connection strips, so it costs a single quad however small the map
-- is.  Gen 1 already does this in src/render/TileRenderer.lua (its border
-- block comes straight from the map header and block 0 means nothing there),
-- so this is the Gen 2 half rather than a change to the shared renderer.

local GbcPalette = require("src.render.GbcPalette")
local PixelCanvas = require("src.render.PixelCanvas")

local BorderFill = {}

-- One block, in pixels: 4x4 tiles of 8.
BorderFill.SIZE = 32

-- LoadMetatiles' `and a / jr nz` in one place: id 0 (or a hole in the block
-- list) reads as the map header's border block.
function BorderFill.blockFor(blockId, borderBlock)
  if blockId == nil or blockId == 0 then return borderBlock or 0 end
  return blockId
end

-- Bakes are cached alongside the map canvases and share their key, so the
-- daytime rollover, the COLOR option and the cave flicker all invalidate the
-- border with the map it belongs to.  The suffix keeps World:dropMapImages'
-- "<mapId>|" prefix sweep working on it.
function BorderFill.cacheKey(mapKey)
  return tostring(mapKey) .. "|border"
end

-- Where to put the wrap-tiled quad for a camera at (camX, camY) world pixels
-- filling a w x h screen at scale s.  The source origin is floored so the
-- 32x32 texture is sampled on whole texels (a fractional offset would soften
-- the wall against the map's own pixels), and the draw position takes the
-- fraction back so the tiling still meshes with the map canvas next to it.
-- The extra block of width/height covers that shift.
function BorderFill.viewport(camX, camY, w, h, s)
  s = (s and s > 0) and s or 1
  local ix, iy = math.floor(camX), math.floor(camY)
  local vw = math.ceil(w / s) + BorderFill.SIZE
  local vh = math.ceil(h / s) + BorderFill.SIZE
  local sx = math.floor((ix - camX) * s)
  local sy = math.floor((iy - camY) * s)
  return ix, iy, vw, vh, sx, sy
end

-- Bake `blockId` of `tileset` into a 32x32 repeat-wrapped image.
--
-- Same palette pass as World:bakeMapImage: a tile's four colors come from its
-- PalMap slot inside the eight BG palettes of `bgSet`, so the walk is by slot
-- and not by tile.  32x32 real pixels through PixelCanvas -- a DPI-scaled
-- canvas would bake the block at a fractional texel size and the repeat wrap
-- would then tile at non-square pixels (#208).
--
-- `waterFrame` is the optional { image, row, tile, slot } descriptor of this
-- frame's AnimateWaterTile graphic (engine/tilesets/tileset_anims.asm:167).
-- The fill is a wrap-tiled 32x32 texture and cannot be overlaid, so a border
-- block made of water is re-baked per frame instead.
function BorderFill.bake(atlas, tileset, blockId, bgSet, waterFrame)
  if not (atlas and tileset and love and love.graphics) then return nil end
  local block = tileset.blocks and tileset.blocks[(blockId or 0) + 1]
  if not block then return nil end
  local tilesPerRow = tileset.tilesPerRow or 16
  local tilePalettes = tileset.tilePalettes
  local colored = bgSet and tilePalettes and GbcPalette.available()
  local aw, ah = atlas:getDimensions()
  local quads = {}
  local function quadFor(tile)
    local q = quads[tile]
    if q then return q end
    q = love.graphics.newQuad((tile % tilesPerRow) * 8,
      math.floor(tile / tilesPerRow) * 8, 8, 8, aw, ah)
    quads[tile] = q
    return q
  end
  local function drawTiles(slot)
    for i = 0, 15 do
      local tile = block[i + 1] or 0
      -- tilePalettes is 1-based over the sheet tiles; anything past it takes
      -- slot 1, exactly as the map bake does.
      local tileSlot = tilePalettes and tilePalettes[tile + 1] or 1
      if not slot or tileSlot == slot then
        love.graphics.draw(atlas, quadFor(tile),
          (i % 4) * 8, math.floor(i / 4) * 8)
      end
    end
  end
  local canvas = PixelCanvas.new(BorderFill.SIZE, BorderFill.SIZE, "nearest")
  if not canvas then return nil end
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  -- A LOVE canvas does not reset the transform, and this bake is reachable
  -- from inside World:draw (the first frame after a COLOR change), so the
  -- renderer's world transform would otherwise be baked in and then cached.
  love.graphics.push()
  love.graphics.origin()
  if colored then
    for slot = 1, 8 do
      GbcPalette.with(bgSet[slot], function() drawTiles(slot) end)
    end
  else
    drawTiles(nil)
  end
  if waterFrame and waterFrame.image and waterFrame.tile then
    local quad = love.graphics.newQuad(0, ((waterFrame.row or 1) - 1) * 8,
      8, 8, 8, 32)
    local function frames()
      love.graphics.setColor(1, 1, 1, 1)
      for i = 0, 15 do
        if (block[i + 1] or 0) == waterFrame.tile then
          love.graphics.draw(waterFrame.image, quad,
            (i % 4) * 8, math.floor(i / 4) * 8)
        end
      end
    end
    local set = colored and bgSet[waterFrame.slot or 1]
    if set then GbcPalette.with(set, frames) else frames() end
  end
  love.graphics.pop()
  love.graphics.setCanvas()
  love.graphics.pop()
  local img = canvas
  if canvas.newImageData then
    local ok, data = pcall(canvas.newImageData, canvas)
    if ok and data then
      local okImg, made = pcall(love.graphics.newImage, data)
      if okImg and made then img = made end
    end
  end
  img:setWrap("repeat", "repeat")
  img:setFilter("nearest", "nearest")
  return img
end

-- VOID FILL (#1418): the beyond-edge scenery under survey zoom.  FADE (the
-- default) is each map header's own border block with the dissolve below;
-- WATER / TREES force one block on outdoor tilesets that actually have that
-- scenery; BLACK is a flat void.  Indoor and cave tilesets have no tree wall
-- or water metatile, so water/trees fall through to the map's own border
-- rather than painting a random block.
--
-- Canonical ids are the wMapBorderBlock values already used as those fills
-- in data/maps/attributes.asm: New Bark / Route 30 $05 trees, Cherrygrove
-- $35 water, Pallet $0f trees, Cinnabar $43 water, Ilex Forest $05 trees.
BorderFill.VOID_FILLS = { "fade", "water", "trees", "black" }
BorderFill.voidFill = "fade"

local FILL_BLOCKS = {
  TILESET_JOHTO = { trees = 0x05, water = 0x35 },
  TILESET_JOHTO_MODERN = { trees = 0x05, water = 0x35 },
  TILESET_KANTO = { trees = 0x0f, water = 0x43 },
  TILESET_FOREST = { trees = 0x05 },
}

function BorderFill.setVoidFill(mode)
  local ok = false
  for _, name in ipairs(BorderFill.VOID_FILLS) do
    if name == mode then ok = true; break end
  end
  BorderFill.voidFill = ok and mode or "fade"
end

function BorderFill.cycle(delta)
  local cur = BorderFill.voidFill or "fade"
  local at = 1
  for i, name in ipairs(BorderFill.VOID_FILLS) do
    if name == cur then at = i; break end
  end
  local n = #BorderFill.VOID_FILLS
  at = (at - 1 + (delta or 1)) % n + 1
  BorderFill.setVoidFill(BorderFill.VOID_FILLS[at])
  return BorderFill.voidFill
end

function BorderFill.applyOptions(opts)
  BorderFill.setVoidFill(opts and opts.voidFill or "fade")
end

function BorderFill.voidFillLabel(mode)
  mode = mode or BorderFill.voidFill or "fade"
  if mode == "water" then return "WATER" end
  if mode == "trees" then return "TREES" end
  if mode == "black" then return "BLACK" end
  -- trailing space blanks the 5-char WATER/TREES/BLACK from the value column
  return "FADE "
end

-- The metatile the void should bake, or false when BLACK skips tiling.
function BorderFill.fillBlock(def)
  local mode = BorderFill.voidFill or "fade"
  if mode == "black" then return false end
  if (mode == "water" or mode == "trees") and def then
    local fills = FILL_BLOCKS[def.tileset]
    local block = fills and fills[mode]
    if block ~= nil then return block end
  end
  return def and def.borderBlock or 0
end

-- Crossfade identity: FADE dissolves per map (Cherrygrove water -> Route 30
-- trees).  WATER/TREES dissolve only when the forced block itself changes
-- (Johto water -> Kanto water), so walking two Johto routes does not fade
-- identical water against itself.  BLACK is one sheet everywhere.
function BorderFill.fillKey(def)
  local mode = BorderFill.voidFill or "fade"
  if mode == "black" then return "black" end
  local block = BorderFill.fillBlock(def)
  if mode == "water" or mode == "trees" then
    return mode .. "|" .. tostring(def and def.tileset) .. "|" .. tostring(block)
  end
  return "fade|" .. tostring(def and def.id)
end

-- Each map header carries its OWN border block, so crossing a boundary swaps
-- the whole void from one block to another: Cherrygrove's water becomes Route
-- 30's trees between one frame and the next.  On a 20x18 viewport that is a few
-- pixels at the screen edge and nobody sees it; under survey zoom the void is
-- most of the window, and the swap reads as the background popping.
--
-- So the swap is dissolved rather than cut.  `key` is the fill identity
-- (BorderFill.fillKey), not the image itself: the same block gets re-baked by
-- the daytime rollover, the COLOR option and the two-frame cave flicker, and a
-- dissolve on any of those would smear the flicker into mush.
BorderFill.CROSSFADE_FRAMES = 20

-- The bookkeeping half, love-free so it can be checked without a canvas.
-- Returns the image to draw underneath (nil on the first fill and once the
-- dissolve is over) and the alpha the incoming image draws at.
function BorderFill.crossfade(owner, image, key)
  if not owner or key == nil then return nil, 1 end
  if owner.borderKey ~= key then
    -- Nothing to dissolve from on the first map of a session.
    owner.borderFrom = (owner.borderKey ~= nil) and owner.borderLast or nil
    owner.borderKey = key
    owner.borderFade = owner.borderFrom and 0 or nil
  end
  owner.borderLast = image
  if not owner.borderFade then return nil, 1 end
  owner.borderFade = owner.borderFade + 1
  if owner.borderFade >= BorderFill.CROSSFADE_FRAMES then
    owner.borderFade, owner.borderFrom = nil, nil
    return nil, 1
  end
  return owner.borderFrom, owner.borderFade / BorderFill.CROSSFADE_FRAMES
end

-- Tile `image` across the whole view, world-aligned so it meshes with the map
-- canvas drawn over it.  One reused Quad per caller table: this runs every
-- overworld frame, and a fresh Quad here churns the GC.
function BorderFill.draw(owner, image, camX, camY, w, h, s, key)
  if not (image and love and love.graphics) then return false end
  local ix, iy, vw, vh, sx, sy = BorderFill.viewport(camX, camY, w, h, s)
  local q = owner and owner.borderQuad
  if q then
    q:setViewport(ix, iy, vw, vh, BorderFill.SIZE, BorderFill.SIZE)
  else
    q = love.graphics.newQuad(ix, iy, vw, vh,
      BorderFill.SIZE, BorderFill.SIZE)
    if owner then owner.borderQuad = q end
  end
  local from, alpha = BorderFill.crossfade(owner, image, key)
  if from then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(from, q, sx, sy, 0, s, s)
  end
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.draw(image, q, sx, sy, 0, s, s)
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

return BorderFill
