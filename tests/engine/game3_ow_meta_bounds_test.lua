-- A corrupt OW sprite .meta must not size an allocation.
--
-- L4 regression: load_one read width/height/frameCount straight out of the
-- u16 header (OwExtract.decodeMeta does not validate) and only sanity-checked
-- the byte count against ONE frame.  A header with a large frameCount passed
-- that check and then allocated aw x (h * frameCount) pixels -- with
-- frameCount = 65535 and a 32x32 frame that is 2,097,120 rows, and u16 maxima
-- reach ~4.3e9 pixels.  The cache that supplies it lives in the user-writable
-- save directory.
--   luajit tests/engine/game3_ow_meta_bounds_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local OwSprites = require("src.core.game3.ow_sprites")
local OwExtract = require("src.import.gba.ow_extract")

local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end

-- A well-formed header with an absurd frame count: MAGIC + version + inanimate
-- + graphicsId + width + height + frameCount + paletteTag.
local W, H, FRAMES = 32, 32, 65535
local meta = OwExtract.MAGIC .. string.char(1, 0) .. u16(0)
  .. u16(W) .. u16(H) .. u16(FRAMES) .. u16(0)
local rgba = string.rep("\0", W * H * 4) -- exactly one frame of pixels

local decoded = OwExtract.decodeMeta(meta)
check(decoded and decoded.frameCount == FRAMES, "the fixture carries an absurd frame count")

OwSprites.install({
  read = function(_, rel)
    if rel:sub(-5) == ".meta" then return meta end
    if rel:sub(-5) == ".rgba" then return rgba end
    return nil
  end,
})

-- Spy the allocation the loader asks for.
local asked = {}
local realNew = love.image.newImageData
love.image.newImageData = function(a, b, ...)
  asked[#asked + 1] = { a, b }
  return realNew(a, b, ...)
end
local spr = OwSprites.get(0)
love.image.newImageData = realNew

check(spr == nil, "a corrupt .meta is rejected instead of allocated")
eq(#asked, 0, "no image allocation is attempted from a corrupt header")
if #asked > 0 then
  print(string.format("      (asked for %sx%s)", tostring(asked[1][1]), tostring(asked[1][2])))
end

-- A sane header still loads (regression guard).
local sane = OwExtract.MAGIC .. string.char(1, 0) .. u16(0)
  .. u16(W) .. u16(H) .. u16(4) .. u16(0)
OwSprites.install({
  read = function(_, rel)
    if rel:sub(-5) == ".meta" then return sane end
    if rel:sub(-5) == ".rgba" then return string.rep("\0", W * H * 4 * 4) end
    return nil
  end,
})
check(OwSprites.get(0) ~= nil, "a sane sprite sheet still loads")

T.finish("game3_ow_meta_bounds_test")
