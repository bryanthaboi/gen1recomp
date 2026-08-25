-- The PACK screen's chrome, drawn from the cart's own tiles.
--
-- engine/items/pack.asm builds this screen out of tiles, not rectangles, and
-- transcribing it that way is what makes the bag picture, the pocket plaque and
-- the ◀▶/▼▲ header land on the 8px grid by construction:
--
--   Pack_InitGFX   copies PackMenuGFX ($60 tiles) to vTiles2 tile $00, fills
--                  rows 1-11 with the background tile $24, clears the item
--                  area at (5,1) 15x11, and lays the header at (0,0) as the
--                  20 running tiles $28..$3b
--   PlacePackGFX   lays $50..$5e as a 5x3 block at (0,3) -- the bag picture,
--                  which DrawPackGFX swaps per pocket out of PackGFX
--   DrawPocketName lays a 5x3 block at (0,7) from its own 5x12 tilemap
--   _CGB_PackPals  loads six BG palettes and colours five rectangles with
--                  them: the two header halves, the CURSOR column (7,2) 1x9
--                  whose colour 3 is red, the pocket plaque (red) and the bag
--                  picture (green) -- engine/gfx/cgb_layouts.asm:715-734
--
-- A cache from before the pack stage simply has no `pack` table; PackMenu
-- falls back to its plain boxes then.

local Assets = require("src.render.Assets")
local GbcPalette = require("src.render.GbcPalette")

local PackGfx = {}
PackGfx.__index = PackGfx

local SCREEN_W, SCREEN_H = 20, 18
-- Textbox(0, TEXTBOX_Y - 2) with a 4-row interior: rows 12..17.
local DESCRIPTION_Y = 12

function PackGfx.new(menuGfx)
  local self = setmetatable({}, PackGfx)
  self.gfx = menuGfx and menuGfx.pack or nil
  self.images = {}
  self.quads = {}
  if self.gfx then
    -- paletteZones is a list of rectangles; flatten it to a per-cell lookup so
    -- drawing a tile is one table read rather than a scan.
    self.zone = {}
    for _, z in ipairs(self.gfx.paletteZones or {}) do
      local x0, y0, w, h, pal = z[1], z[2], z[3], z[4], z[5]
      for y = y0, y0 + h - 1 do
        for x = x0, x0 + w - 1 do
          self.zone[y * SCREEN_W + x] = pal
        end
      end
    end
  end
  return self
end

function PackGfx:available()
  return self.gfx ~= nil and self:image("menu") ~= nil
end

function PackGfx:image(key)
  local path = self.gfx and self.gfx[key]
  if not path then return nil end
  local cached = self.images[path]
  if cached == nil then
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    self.images[path] = cached
  end
  return cached or nil
end

-- One 8x8 tile out of a sheet `tilesWide` tiles across.
function PackGfx:quad(image, tilesWide, index)
  local key = tostring(image) .. ":" .. tilesWide .. ":" .. index
  local quad = self.quads[key]
  if not quad then
    local w, h = image:getDimensions()
    quad = love.graphics.newQuad(
      (index % tilesWide) * 8, math.floor(index / tilesWide) * 8, 8, 8, w, h)
    self.quads[key] = quad
  end
  return quad
end

-- The palette a screen cell draws with: its attrmap zone, else palette 0.
function PackGfx:colorsAt(tx, ty)
  local pals = self.gfx and self.gfx.palettes
  if not pals then return nil end
  local index = (self.zone and self.zone[ty * SCREEN_W + tx]) or 1
  return pals[index]
end

function PackGfx:blit(image, tilesWide, index, tx, ty)
  if not image then return end
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  local colors = self:colorsAt(tx, ty)
  local function body()
    G.draw(image, self:quad(image, tilesWide, index), tx * 8, ty * 8)
  end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
end

-- A tile out of PackMenuGFX, addressed by its VRAM id ($00 is the sheet's
-- first tile, so id and index are the same here).
function PackGfx:menuTile(tile, tx, ty)
  self:blit(self:image("menu"), self.gfx.menuTilesWide or 16, tile, tx, ty)
end

-- Everything behind the item list: the header strip, the background column,
-- the bag picture for this pocket, and the pocket plaque.
function PackGfx:draw(pocketId)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, SCREEN_W * 8, SCREEN_H * 8)

  -- ◀▶ POCKET       ▼▲ ITEMS: 20 running tiles from $28.
  local header = self.gfx.headerFirstTile or 0x28
  for tx = 0, SCREEN_W - 1 do
    self:menuTile(header + tx, tx, 0)
  end

  -- Rows 1-11 are filled with $24; the item area at (5,1) is then cleared, so
  -- only the left five columns keep the pattern.
  local background = self.gfx.backgroundTile or 0x24
  for ty = 1, 11 do
    for tx = 0, 4 do
      self:menuTile(background, tx, ty)
    end
  end

  -- The bag picture: 15 tiles, 5 across, from this pocket's row in PackGFX.
  local packImage = self:image("pack")
  local firstRow = self.gfx.pocketPicture and self.gfx.pocketPicture[pocketId]
  if packImage and firstRow then
    local wide = self.gfx.packTilesWide or 5
    for i = 0, wide * (self.gfx.packTilesHigh or 3) - 1 do
      self:blit(packImage, wide, firstRow + i,
        i % wide, 3 + math.floor(i / wide))
    end
  end

  -- The pocket plaque, from DrawPocketName's own tilemap.
  local order = self.gfx.pocketOrder or {}
  local block
  for i, id in ipairs(order) do
    if id == pocketId then block = self.gfx.pocketName[i] end
  end
  if block then
    for i, tile in ipairs(block) do
      self:menuTile(tile, (i - 1) % 5, 7 + math.floor((i - 1) / 5))
    end
  end
end

PackGfx.DESCRIPTION_Y = DESCRIPTION_Y
PackGfx.SCREEN_W = SCREEN_W

return PackGfx
