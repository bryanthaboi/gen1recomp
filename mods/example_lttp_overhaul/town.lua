-- Bank02.asm Map32ToMap16; Kakariko $18/$19/$20/$21; Bank0F.asm Map16ToMap8.
local HOUSE = {
  { 0x3F7, 0x3F8, 0x3F9, 0x3F9, 0x3FA, 0x3FB },
  { 0x3FC, 0x3FD, 0x3FE, 0x3FE, 0x3FF, 0x400 },
  { 0x402, 0x403, 0x404, 0x404, 0x405, 0x406 },
  { 0x40A, 0x40B, 0x40C, 0x40D, 0x40B, 0x40E },
  { 0x0F9, 0x0FA, 0x0FB, 0x0FC, 0x0FD, 0x0FE },
}
local LAB = {
  { 0x5AC, 0x5AD, 0x5AE, 0x5AE, 0x5AF, 0x5B0 },
  { 0x5B1, 0x5B6, 0x5B3, 0x5B3, 0x5B7, 0x5B5 },
  { 0x5B8, 0x5B9, 0x5BA, 0x5BA, 0x5BB, 0x5BC },
  { 0x5BD, 0x5BE, 0x5BF, 0x5C0, 0x5BE, 0x5C1 },
  HOUSE[5],
}
local TREE = {
  { 0x0AE, 0x0AF, 0x07E, 0x07F },
  { 0x0B0, 0x014, 0x015, 0x0A8 },
  { 0x089, 0x01C, 0x01D, 0x076 },
  { 0x0F1, 0x04E, 0x04F, 0x0D9 },
  { 0x09A, 0x09B, 0x09C, 0x095 },
}

return function(mod, base, map, imagePath)
  local source = love.image.newImageData(imagePath)
  local function tile(image, id, x, y)
    image:paste(source, x, y, id % 64 * 16, math.floor(id / 64) * 16, 16, 16)
  end
  local function mosaic(rows)
    local image = love.image.newImageData(#rows[1] * 16, #rows * 16)
    for y, row in ipairs(rows) do
      for x, id in ipairs(row) do tile(image, id, (x - 1) * 16, (y - 1) * 16) end
    end
    return image
  end
  local function scale(target, image, x, y, w, h, sx, sy, sw, sh)
    sx, sy = sx or 0, sy or 0
    sw, sh = sw or image:getWidth(), sh or image:getHeight()
    for py = 0, h - 1 do
      for px = 0, w - 1 do
        target:setPixel(x + px, y + py, image:getPixel(
          sx + math.floor((px + 0.5) * sw / w),
          sy + math.floor((py + 0.5) * sh / h)))
      end
    end
  end
  local width, height = map.width * 32, map.height * 32
  local canvas = love.image.newImageData(width, height + 32)
  local tree = mosaic(TREE)
  local Map = require("src.world.Map")
  local function water(x, y)
    if x < 0 or y < 0 or x >= width / 16 or y >= height / 16 then return true end
    local id = Map.defCellTile(map, base, x, y)
    return id == 0x14 or id == 0x32
  end
  local function shoreline(x, y)
    local sx, sy = 0x2DB % 64 * 16, math.floor(0x2DB / 64) * 16
    for n = 0, 15 do
      for depth = 0, 3 do
        local r, g, b, a = source:getPixel(sx + n, sy + 12 + depth)
        if not water(x - 1, y) then canvas:setPixel(x * 16 + 3 - depth, y * 16 + n, r, g, b, a) end
        if not water(x + 1, y) then canvas:setPixel(x * 16 + 12 + depth, y * 16 + n, r, g, b, a) end
        if not water(x, y - 1) then canvas:setPixel(x * 16 + n, y * 16 + 3 - depth, r, g, b, a) end
        if not water(x, y + 1) then canvas:setPixel(x * 16 + n, y * 16 + 12 + depth, r, g, b, a) end
      end
    end
  end
  for y = 0, height / 16 - 1 do
    for x = 0, width / 16 - 1 do
      local original = Map.defCellTile(map, base, x, y)
      tile(canvas, (x + y) % 7 == 0 and 0x10E or 0x034, x * 16, y * 16)
      if original == 0x3A then
        scale(canvas, tree, x * 16, y * 16, 16, 16)
      elseif original == 0x14 or original == 0x32 then
        local ripple = (x + y * 3) % 5
        tile(canvas, ripple == 0 and 0x2D8 or ripple == 2 and 0x2D9 or 0x2CD,
          x * 16, y * 16)
        shoreline(x, y)
      elseif original == 0x55 then
        tile(canvas, 0x334, x * 16, y * 16)
      elseif original == 0x56 then
        tile(canvas, 0x413, x * 16, y * 16)
      elseif original == 0x52 then
        tile(canvas, 0x3F6, x * 16, y * 16)
      elseif (y == 6 and x >= 3 and x <= 15)
          or (x == 9 and y >= 2 and y <= 16)
          or (y == 12 and x >= 9 and x <= 15) then
        tile(canvas, 0x3D2, x * 16, y * 16)
      elseif original == 0x2C and x > 1 and x < 18 and y > 1 then
        tile(canvas, 0x3C6, x * 16, y * 16)
      end
    end
  end
  local function building(rows, x, y, w, h, doorX)
    local image = mosaic(rows)
    local door = love.image.newImageData(32, 32)
    door:paste(image, 0, 0, 32, 48, 32, 32)
    tile(image, rows[4][2], 32, 48)
    tile(image, rows[4][2], 48, 48)
    tile(image, rows[5][2], 32, 64)
    tile(image, rows[5][5], 48, 64)
    scale(canvas, image, x, y, w, h - 16, 0, 0, 96, 64)
    scale(canvas, image, x, y + h - 16, w, 16, 0, 64, 96, 16)
    scale(canvas, door, doorX, y + h - 24, 16, 24)
    local r, g, b = source:getPixel(0x0FB % 64 * 16 + 14,
      math.floor(0x0FB / 64) * 16 + 7)
    for py = y + h - 17, y + h - 2 do
      for px = doorX + 4, doorX + 11 do canvas:setPixel(px, py, r * 0.15, g * 0.15, b * 0.15, 1) end
    end
    image:release()
    door:release()
  end
  building(HOUSE, 64, 48, 64, 48, 80)
  building(HOUSE, 192, 48, 64, 48, 208)
  building(LAB, 160, 128, 96, 64, 192)
  for y = 0, 1 do
    for x = 0, 1 do scale(canvas, tree, x * 16, height + y * 16, 16, 16) end
  end
  local atlas = love.image.newImageData(256, math.ceil((width * height / 64 + 16) / 32) * 8)
  local blocks, mapBlocks, variants, count = {}, {}, {}, 0
  local sets = {}
  for _, name in ipairs({ "walkable", "doorTiles", "warpTiles", "counterTiles", "waterTiles", "shoreTiles" }) do
    sets[name] = {}
    local fallback = name == "waterTiles" and { 0x14 }
      or name == "shoreTiles" and { 0x32, 0x48 } or {}
    for _, id in ipairs(base[name] or fallback) do sets[name][id] = true end
  end
  local result = { image = "mod_cache/" .. mod.id .. "/pallet.png",
    imageWidth = atlas:getWidth(), imageHeight = atlas:getHeight(),
    tilesPerRow = 32, blocks = blocks, trueColor = true,
    walkable = {}, doorTiles = {}, warpTiles = {}, counterTiles = {}, waterTiles = {}, shoreTiles = {} }
  local piece = love.image.newImageData(8, 8)
  local function addBlock(original, bx, by)
    local row = {}
    for i, old in ipairs(original) do
      local tx, ty = (i - 1) % 4, math.floor((i - 1) / 4)
      piece:paste(canvas, 0, 0, bx * 32 + tx * 8, by * 32 + ty * 8, 8, 8)
      if old == base.grassTile then
        piece:paste(source, 0, 0, 0x3F6 % 64 * 16, math.floor(0x3F6 / 64) * 16, 8, 8)
      end
      local key = old .. ":" .. piece:getString()
      local id = variants[key]
      if id == nil then
        id = count
        count = count + 1
        variants[key] = id
        atlas:paste(piece, id % 32 * 8, math.floor(id / 32) * 8, 0, 0, 8, 8)
        for name, set in pairs(sets) do
          if set[old] then result[name][#result[name] + 1] = id end
        end
        if old == base.grassTile then result.grassTile = id end
      end
      row[i] = id
    end
    blocks[#blocks + 1] = row
    return #blocks - 1
  end
  for i, id in ipairs(map.blocks) do
    mapBlocks[i] = addBlock(assert(base.blocks[id + 1]), (i - 1) % map.width,
      math.floor((i - 1) / map.width))
  end
  local border = addBlock(assert(base.blocks[(map.borderBlock or 0) + 1]), 0, map.height)
  assert(mod.cache:write("pallet.png", atlas:encode("png"):getString()))
  source:release()
  tree:release()
  canvas:release()
  atlas:release()
  piece:release()
  return result, mapBlocks, border
end
