-- A screen's own tile sheet, addressed the way the cart addresses it.
--
-- The Gen 2 menus that are not built out of text boxes -- the #DEX, the
-- POKeGEAR, the trainer card -- work by copying a sheet into VRAM at a known
-- tile id and then writing tile ids into the tilemap.  Transcribing one of
-- those screens means writing the same ids at the same hlcoords, so the only
-- primitive needed is "draw sheet tile $NN at (tx, ty)".
--
-- `firstTile` is the VRAM id the sheet's tile 0 was loaded at (vTiles2 tile
-- $31 for the dex, $00 for the town map), so a tile id maps to a sheet index
-- by subtracting it.  A sheet is `wide` tiles across, which is how the
-- extractor writes them.

local Assets = require("src.render.Assets")
local GbcPalette = require("src.render.GbcPalette")

local TileSheet = {}
TileSheet.__index = TileSheet

-- opts: path, wide, firstTile, palette (a 4-colour table) or palettes + a
function TileSheet.new(opts)
  local self = setmetatable({}, TileSheet)
  self.path = opts and opts.path
  self.wide = (opts and opts.wide) or 16
  self.firstTile = (opts and opts.firstTile) or 0
  self.palette = opts and opts.palette
  self.paletteFor = opts and opts.paletteFor
  self.raw = opts and opts.raw
  self.quads = {}
  return self
end

function TileSheet.loadImage(path)
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  if not path then error("tile sheet has no path", 2) end
  return Assets.image(path)
end

function TileSheet:image()
  if self.loaded == nil then
    self.loaded = TileSheet.loadImage(self.path) or false
  end
  return self.loaded or nil
end

function TileSheet:available()
  return self:image() ~= nil
end

function TileSheet:quad(index)
  local quad = self.quads[index]
  if not quad then
    local image = self:image()
    if not image then return nil end
    local w, h = image:getDimensions()
    quad = love.graphics.newQuad(
      (index % self.wide) * 8, math.floor(index / self.wide) * 8, 8, 8, w, h)
    self.quads[index] = quad
  end
  return quad
end

-- Draws VRAM tile `tile` at tile coordinates (tx, ty).  A tile outside the
-- sheet is silently skipped, which is what lets a screen name a tile that
-- belongs to the font page instead.
function TileSheet:draw(tile, tx, ty)
  local image = self:image()
  if not image then return false end
  local index = tile - self.firstTile
  if index < 0 then return false end
  local quad = self:quad(index)
  if not quad then return false end
  local _, sy = quad:getViewport()
  local _, ih = image:getDimensions()
  if sy >= ih then return false end
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  local colors = self.palette
  if self.paletteFor then colors = self.paletteFor(tile, tx, ty) or colors end
  local batch = self.batch
  if colors and GbcPalette.available() then
    if batch then
      -- Inside begin/finish: the shader only changes when the palette does.
      if batch.active ~= colors then
        if self.raw then GbcPalette.useRaw(colors) else GbcPalette.use(colors) end
        batch.active = colors
      end
      G.draw(image, quad, tx * 8, ty * 8)
    else
      -- GbcPalette.with / withRaw without the closure: set, draw, restore.
      local previous = G.getShader and G.getShader() or nil
      if self.raw then GbcPalette.useRaw(colors) else GbcPalette.use(colors) end
      G.draw(image, quad, tx * 8, ty * 8)
      G.setShader(previous)
    end
  else
    if batch then self:suspend() end
    G.draw(image, quad, tx * 8, ty * 8)
  end
  return true
end

-- Batch a pass of draws: between begin and finish the palette shader is set
-- once per run of tiles sharing a palette rather than once per tile, and the
-- caller's shader comes back at finish.  Anything drawn between two tiles
-- that is not a sheet tile (a flat rect, text) calls suspend first so it
-- draws under the caller's shader, as it would have outside the batch.
function TileSheet:begin()
  local G = love.graphics
  self.batch = { previous = G.getShader and G.getShader() or nil, active = nil }
end

function TileSheet:suspend()
  local batch = self.batch
  if batch and batch.active then
    love.graphics.setShader(batch.previous)
    batch.active = nil
  end
end

function TileSheet:finish()
  self:suspend()
  self.batch = nil
end

-- A run of consecutive ids, left to right: the shape most of these routines
-- use for a header strip or a caption.
function TileSheet:run(first, count, tx, ty)
  for i = 0, count - 1 do
    self:draw(first + i, tx + i, ty)
  end
end

-- A rectangle of consecutive ids, row-major.
function TileSheet:block(first, wide, high, tx, ty)
  for row = 0, high - 1 do
    for col = 0, wide - 1 do
      self:draw(first + row * wide + col, tx + col, ty + row)
    end
  end
end

return TileSheet
