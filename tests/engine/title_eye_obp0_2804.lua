-- engine/movie/title.asm:76
--   luajit tests/engine/title_eye_obp0_2804.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("title eye rOBP0 2804")
local check = S.check

local ImageWriter = require("src.import.ImageWriter")
local SHADES = ImageWriter.SHADES

local function fakeImage(pixels)
  local img = { px = pixels }
  function img:getWidth() return #self.px end
  function img:getHeight() return 1 end
  function img:getPixel(x) return unpack(self.px[x + 1]) end
  function img:setPixel(x, _, r, g, b, a) self.px[x + 1] = { r, g, b, a } end
  return img
end

local img = fakeImage({
  { SHADES[1][1], SHADES[1][2], SHADES[1][3], 1 },
  { SHADES[2][1], SHADES[2][2], SHADES[2][3], 1 },
  { SHADES[3][1], SHADES[3][2], SHADES[3][3], 1 },
  { SHADES[4][1], SHADES[4][2], SHADES[4][3], 1 },
  { SHADES[3][1], SHADES[3][2], SHADES[3][3], 0 },
})
ImageWriter.applyTitleObp0(img)

local function shadeAt(i) return img.px[i][1] end
check(math.abs(shadeAt(1) - 1) < 1e-6, "OBJ color 0 stays white")
check(math.abs(shadeAt(2) - 1) < 1e-6, "OBJ color 1 maps to white")
check(math.abs(shadeAt(3) - SHADES[3][1]) < 1e-6,
  "OBJ color 2 keeps dark shade (red under the title GBC palette)")
check(math.abs(shadeAt(4) - 0) < 1e-6, "OBJ color 3 stays black")
check(img.px[5][4] == 0, "transparent pixel untouched")

S.finish()
