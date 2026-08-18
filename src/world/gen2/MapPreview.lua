-- Bake a Gen 2 map canvas without a World instance.  The save editor's map
-- tab uses this so Gold rooms draw the same tiles the overworld would,
-- instead of the checkerboard fallback Map2 has no renderer for.

local Assets = require("src.render.Assets")
local BorderFill = require("src.world.gen2.BorderFill")
local GbcPalette = require("src.render.GbcPalette")
local Palettes = require("src.world.gen2.Palettes")
local PixelCanvas = require("src.render.PixelCanvas")

local MapPreview = {}

-- home/map.asm:1739-1748 LoadTilesetGFX
local ROOF_TILESETS = {
  TILESET_JOHTO = true,
  TILESET_JOHTO_MODERN = true,
}

local function applyRoofOverlay(atlasPath, roofPath, tilesPerRow)
  local atlasData = love.image.newImageData(Assets.resolve(atlasPath))
  local roofData = love.image.newImageData(Assets.resolve(roofPath))
  for t = 0, 8 do
    local destId = 0x0a + t
    local dx = (destId % tilesPerRow) * 8
    local dy = math.floor(destId / tilesPerRow) * 8
    local sx = t * 8
    for y = 0, 7 do
      for x = 0, 7 do
        local r, g, b, a = roofData:getPixel(sx + x, y)
        atlasData:setPixel(dx + x, dy + y, r, g, b, a)
      end
    end
  end
  local image = love.graphics.newImage(atlasData)
  image:setFilter("nearest", "nearest")
  return image
end

local function optionalTable(data, gen2Key, plainKey, generated)
  if data[gen2Key] then return data[gen2Key] end
  if data[plainKey] then return data[plainKey] end
  local ok, mod = pcall(require, "data.generated." .. generated)
  if ok and type(mod) == "table" then return mod end
  return nil
end

function MapPreview.baker(data)
  data = data or {}
  return {
    tilesets = data.gen2Tilesets or data.tilesets or {},
    -- Data:load does not pull roofs.lua; the Gold cache still has it.
    roofs = optionalTable(data, "gen2Roofs", "roofs", "roofs"),
    palettes = optionalTable(data, "gen2Palettes", "palettes", "palettes"),
    atlasCache = {},
    mapImages = {},
  }
end

function MapPreview.atlasFor(baker, mapDef)
  if not (baker and mapDef) then return nil, nil end
  local tileset = baker.tilesets and baker.tilesets[mapDef.tileset]
  if not tileset then return nil, nil end
  local cacheKey = mapDef.tileset
  local roofName = nil
  local roofs = baker.roofs
  if ROOF_TILESETS[mapDef.tileset] then
    roofName = roofs and roofs.mapGroupRoofs and roofs.mapGroupRoofs[mapDef.group]
  end
  if roofName then cacheKey = cacheKey .. "|" .. roofName end
  local cached = baker.atlasCache[cacheKey]
  if cached then return cached, tileset end

  local tilesPerRow = tileset.tilesPerRow or 16
  local atlas
  local roofSpec = roofName and roofs and roofs.roofs and roofs.roofs[roofName]
  if roofSpec and roofSpec.image and love.image and love.image.newImageData then
    local ok, img = pcall(applyRoofOverlay, tileset.image, roofSpec.image, tilesPerRow)
    if ok then atlas = img end
  end
  if not atlas then
    if not tileset.image then return nil, tileset end
    local ok, img = pcall(Assets.image, tileset.image)
    if not ok then return nil, tileset end
    atlas = img
    if atlas.setFilter then atlas:setFilter("nearest", "nearest") end
  end
  baker.atlasCache[cacheKey] = atlas
  return atlas, tileset
end

-- Same bake as World:bakeMapImage (src/world/gen2/World.lua), minus the
-- World fields the overworld keeps for anim overlays and cave flicker.
function MapPreview.bake(baker, map, daytime)
  local atlas, tileset = MapPreview.atlasFor(baker, map.def)
  if not atlas or not tileset then return nil end
  if not (love.graphics and love.graphics.newCanvas) then return nil end
  local blocks = tileset.blocks
  local tilesPerRow = tileset.tilesPerRow or 16
  local pw, ph = map.width * 32, map.height * 32
  local okCanvas, canvas = pcall(PixelCanvas.new, pw, ph, "nearest")
  if not okCanvas or not canvas then return nil end
  local quads = {}
  local function quadFor(tile)
    local q = quads[tile]
    if q then return q end
    local sx = (tile % tilesPerRow) * 8
    local sy = math.floor(tile / tilesPerRow) * 8
    q = love.graphics.newQuad(sx, sy, 8, 8, atlas:getDimensions())
    quads[tile] = q
    return q
  end

  local tilePalettes = tileset.tilePalettes
  local bgSet = baker.palettes and daytime
    and Palettes.bgSet(baker.palettes, map.def, daytime) or nil
  local colored = bgSet and tilePalettes and GbcPalette.available()
  local clearColor = { 0.15, 0.55, 0.25 }
  if bgSet and bgSet[1] and bgSet[1][1] then
    local c = GbcPalette.color(bgSet[1], 1)
    clearColor = { c[1] / 255, c[2] / 255, c[3] / 255 }
  end

  local function drawTiles(slot)
    for by = 0, map.height - 1 do
      for bx = 0, map.width - 1 do
        local blockId = BorderFill.blockFor(
          map.blocks[by * map.width + bx + 1], map.borderBlock)
        local block = blocks and blocks[(blockId or 0) + 1]
        if block then
          for i = 0, 15 do
            local tile = block[i + 1] or 0
            local tileSlot = tilePalettes and tilePalettes[tile + 1] or 1
            if not slot or tileSlot == slot then
              local tx = bx * 32 + (i % 4) * 8
              local ty = by * 32 + math.floor(i / 4) * 8
              love.graphics.draw(atlas, quadFor(tile), tx, ty)
            end
          end
        end
      end
    end
  end

  local function paint()
    love.graphics.clear(clearColor[1], clearColor[2], clearColor[3], 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.push()
    love.graphics.origin()
    if colored then
      for slot = 1, 8 do
        GbcPalette.with(bgSet[slot], function() drawTiles(slot) end)
      end
    else
      drawTiles(nil)
    end
    love.graphics.pop()
  end
  if canvas.renderTo then
    canvas:renderTo(paint)
  else
    paint()
  end
  return canvas
end

function MapPreview.imageFor(baker, map)
  if not (baker and map and map.id) then return nil end
  local cached = baker.mapImages[map.id]
  if cached then return cached end
  local img = MapPreview.bake(baker, map, "DAY")
  baker.mapImages[map.id] = img or false
  return img
end

function MapPreview.renderer(baker, map)
  local img = MapPreview.imageFor(baker, map)
  if not img then return nil end
  return {
    draw = function(_, camX, camY)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, -math.floor(camX or 0), -math.floor(camY or 0))
    end,
  }
end

return MapPreview
