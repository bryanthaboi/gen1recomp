package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness").suite("tile cutout region")
local TileRenderer = require("src.render.TileRenderer")
local BillboardCutout = require("src.render.BillboardCutout")

local activeCanvas = { name = "upright" }
local stack, captures, finalDraw = {}, 0, nil

local function imageData(w, h)
  local pixels = {}
  local rows = w == 9 and h == 5 and {
    ".........", ".####....", ".####.#..", ".####.#..", ".........",
  } or nil
  for y = 0, h - 1 do
    pixels[y] = {}
    for x = 0, w - 1 do
      local dark = rows and rows[y + 1]:sub(x + 1, x + 1) == "#"
        or (not rows and x == math.floor(w / 2) and y == math.floor(h / 2))
      local value = dark and 0.1 or 0.9
      pixels[y][x] = { value, value, value, 1 }
    end
  end
  return {
    getDimensions = function() return w, h end,
    getPixel = function(_, x, y) return unpack(pixels[y][x]) end,
    setPixel = function(_, x, y, r, g, b, a)
      pixels[y][x] = { r, g, b, a }
    end,
    pixels = pixels,
  }
end

love.graphics.newCanvas = function(w, h)
  local canvas = { w = w, h = h }
  function canvas:setFilter() end
  function canvas:newImageData()
    captures = captures + 1
    return imageData(w, h)
  end
  function canvas:release() self.released = true end
  return canvas
end
love.graphics.newImage = function(data)
  return { data = data, setFilter = function() end, release = function() end }
end
love.graphics.getCanvas = function() return activeCanvas end
love.graphics.setCanvas = function(canvas) activeCanvas = canvas end
love.graphics.push = function() stack[#stack + 1] = activeCanvas end
love.graphics.pop = function() activeCanvas = table.remove(stack) end
love.graphics.origin = function() end
love.graphics.setScissor = function() end
love.graphics.setShader = function() end
love.graphics.setColor = function() end
love.graphics.clear = function() end
love.graphics.draw = function(image, x, y)
  finalDraw = { image = image, x = x, y = y, target = activeCanvas }
end

local renderer = setmetatable({}, { __index = TileRenderer })
function renderer:drawWindow() end

T.check(type(renderer.drawCutoutRegion) == "function",
  "TileRenderer exposes an alpha-cutout region draw")
if type(renderer.drawCutoutRegion) == "function" then
  renderer:drawCutoutRegion(10, 20, 9, 5, -1, -2,
    { x = 6, y = 2, width = 1, height = 2 })
  local firstImage = finalDraw.image
  T.eq(firstImage.data.pixels[0][0][4], 0,
    "boundary ground is transparent in the card")
  T.eq(firstImage.data.pixels[1][1][4], 0,
    "a neighbouring structure outside the seed is transparent")
  T.eq(firstImage.data.pixels[2][6][4], 1,
    "the seeded structure remains opaque")
  T.same({ finalDraw.x, finalDraw.y }, { -1, -2 },
    "the card draws at its billboard-local offset")

  renderer:drawCutoutRegion(10, 20, 9, 5, -4, -5,
    { x = 6, y = 2, width = 1, height = 2 })
  T.eq(captures, 1, "a stable map region reuses its cached cutout")
  T.eq(finalDraw.image, firstImage, "the cached cutout image is reused")

  local upright = { name = "upright-after-failure" }
  activeCanvas = upright
  love.graphics.newCanvas = function(w, h)
    return {
      w = w, h = h,
      setFilter = function() end,
      newImageData = function() error("readback unavailable") end,
      release = function() end,
    }
  end
  local broken = setmetatable({}, { __index = TileRenderer })
  function broken:drawWindow() end
  T.eq(broken:drawCutoutRegion(1, 2, 3, 3, 0, 0), false,
    "a failed GPU readback degrades without drawing a card")
  T.eq(activeCanvas, upright,
    "a failed capture restores the upright render target")
end

local underlay = setmetatable({}, { __index = TileRenderer })
function underlay:drawWindow() end
activeCanvas = { name = "ground" }
love.graphics.newCanvas = function(w, h)
  local canvas = { w = w, h = h }
  function canvas:setFilter() end
  function canvas:newImageData()
    captures = captures + 1
    return imageData(w, h)
  end
  function canvas:release() self.released = true end
  return canvas
end
T.check(type(underlay.drawUnderlayRegion) == "function",
  "TileRenderer exposes a source-preserving ground replacement")
if type(underlay.drawUnderlayRegion) == "function" then
  T.check(underlay:drawUnderlayRegion(10, 20, 9, 5, -1, -2,
    { x = 6, y = 2, width = 1, height = 2 }),
    "ground replacement succeeds")
  T.eq(finalDraw.image.data.pixels[2][6][4], 0,
    "ground replacement clears the selected structure")
  T.eq(finalDraw.image.data.pixels[1][1][4], 1,
    "ground replacement preserves a neighbouring structure")
  T.eq(finalDraw.image.data.pixels[0][0][4], 1,
    "ground replacement preserves surrounding terrain")
  T.same({ finalDraw.x, finalDraw.y }, { -1, -2 },
    "ground replacement uses the requested destination")
end

T.finish("tile cutout region")
