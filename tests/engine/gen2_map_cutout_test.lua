package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness").suite("gen2 map cutout")
local World = require("src.world.gen2.World")

local rows = {
  ".........", ".####....", ".####.#..", ".####.#..", ".........",
}
local function sourceData()
  local pixels = {}
  for y, row in ipairs(rows) do
    pixels[y - 1] = {}
    for x = 1, #row do
      local dark = row:sub(x, x) == "#"
      local value = dark and 0.1 or 0.9
      pixels[y - 1][x - 1] = { value, value, value, 1 }
    end
  end
  return {
    getDimensions = function() return 9, 5 end,
    getPixel = function(_, x, y) return unpack(pixels[y][x]) end,
    setPixel = function(_, x, y, r, g, b, a)
      pixels[y][x] = { r, g, b, a }
    end,
    pixels = pixels,
  }
end

local captures, finalDraw = 0, nil
local nextData = sourceData()
love.graphics.newCanvas = function(w, h)
  return {
    getDimensions = function() return w, h end,
    setFilter = function() end,
    renderTo = function(_, draw) draw() end,
    newImageData = function()
      captures = captures + 1
      return nextData
    end,
    release = function() end,
  }
end
love.graphics.newImage = function(data)
  return { data = data, setFilter = function() end, release = function() end }
end
love.graphics.push = function() end
love.graphics.pop = function() end
love.graphics.origin = function() end
love.graphics.clear = function() end
love.graphics.setColor = function() end
love.graphics.draw = function(image, ...)
  if image.data then finalDraw = { image = image, args = { ... } } end
end

local source = { getDimensions = function() return 16, 16 end }
local world = setmetatable({
  mapImage = source,
  camera = { x = 0, y = 0 },
}, { __index = World })

T.check(type(world.drawMapCutout) == "function",
  "Gen 2 exposes an alpha-cutout draw")
if type(world.drawMapCutout) == "function" then
  world:drawMapCutout(2, 4, 9, 5, -1, -2, 2,
    { x = 6, y = 2, width = 1, height = 2 })
  T.eq(finalDraw.image.data.pixels[0][0][4], 0,
    "card boundary ground becomes transparent")
  T.eq(finalDraw.image.data.pixels[1][1][4], 0,
    "a neighbouring component outside the seed becomes transparent")
  T.eq(finalDraw.image.data.pixels[2][6][4], 1,
    "the seeded component remains opaque")
  T.same({ finalDraw.args[1], finalDraw.args[2],
           finalDraw.args[4], finalDraw.args[5] },
         { -2, -4, 2, 2 },
    "the card offset and pixels use the world scale")
  world:drawMapCutout(2, 4, 9, 5, -3, -4, 2,
    { x = 6, y = 2, width = 1, height = 2 })
  T.eq(captures, 1, "stable map geometry reuses the cached card")
end

nextData = sourceData()
T.check(type(world.drawMapUnderlay) == "function",
  "Gen 2 exposes source-preserving ground replacement")
if type(world.drawMapUnderlay) == "function" then
  T.check(world:drawMapUnderlay(2, 4, 9, 5, 2,
    { x = 6, y = 2, width = 1, height = 2 }),
    "ground replacement succeeds")
  T.eq(finalDraw.image.data.pixels[2][6][4], 0,
    "ground replacement clears the selected component")
  T.eq(finalDraw.image.data.pixels[1][1][4], 1,
    "ground replacement preserves a neighbouring component")
  T.eq(finalDraw.image.data.pixels[0][0][4], 1,
    "ground replacement preserves surrounding terrain")
  T.same({ finalDraw.args[1], finalDraw.args[2],
           finalDraw.args[4], finalDraw.args[5] },
         { 4, 8, 2, 2 },
    "ground replacement aligns to the ground canvas")
end

T.finish("gen2 map cutout")
