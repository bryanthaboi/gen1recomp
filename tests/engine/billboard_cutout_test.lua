package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness").suite("billboard cutout")
local loaded, Cutout = pcall(require, "src.render.BillboardCutout")
T.check(loaded and type(Cutout) == "table",
  "the engine exposes a billboard cutout helper")

if loaded then
  local rows = {
    ".........",
    ".####....",
    ".####.#..",
    ".####.#..",
    ".........",
  }
  local pixels = {}
  for y, row in ipairs(rows) do
    pixels[y] = {}
    for x = 1, #row do
      local dark = row:sub(x, x) == "#"
      local value = dark and 0.1 or 0.9
      pixels[y][x] = { value, value, value, 1 }
    end
  end
  local data = {}
  function data:getDimensions() return #rows[1], #rows end
  function data:getPixel(x, y) return unpack(pixels[y + 1][x + 1]) end
  function data:setPixel(x, y, r, g, b, a)
    pixels[y + 1][x + 1] = { r, g, b, a }
  end

  T.check(type(Cutout.erase) == "function",
    "the helper exposes source-preserving component erasure")
  if type(Cutout.erase) == "function" then
    T.check(Cutout.erase(data, { x = 6, y = 2, width = 1, height = 2 }),
      "the collision seed selects the intended component")
    T.eq(pixels[3][7][4], 0,
      "the selected component becomes transparent")
    T.eq(pixels[2][2][4], 1,
      "a neighbouring structure remains unchanged")
    T.eq(pixels[1][1][4], 1,
      "surrounding ground remains unchanged")
  end
end

T.finish("billboard cutout")
