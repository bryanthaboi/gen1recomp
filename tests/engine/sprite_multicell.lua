package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local quads = {}
local realLove = _G.love
_G.love = _G.love or {}
local realGraphics = love.graphics
love.graphics = {
  newQuad = function(x, y, w, h, iw, ih)
    local q = { x = x, y = y, w = w, h = h, iw = iw, ih = ih }
    quads[#quads + 1] = q
    return q
  end,
  draw = function() end,
  setColor = function() end,
  getColor = function() return 1, 1, 1, 1 end,
}

local Assets = require("src.render.Assets")
local realImage = Assets.image
Assets.image = function()
  return { getDimensions = function() return 128, 64 end }
end

local SpriteRenderer = require("src.render.SpriteRenderer")
SpriteRenderer.invalidate()

do
  local def = {
    image = "fake.png", frames = 2,
    frameWidth = 16, frameHeight = 16,
    cellWidth = 8, cellHeight = 8, cellColumns = 16,
    cells = {
      { { tile = 0, dx = 0, dy = 0 }, { tile = 17, dx = 8, dy = 8 } },
      { { tile = 3, dx = 4, dy = 2, flipX = true } },
    },
  }
  local r = SpriteRenderer.new(def, 1)
  T.check(r.cellFrames ~= nil, "a sprite with cells builds composite frames")

  local first = r.cellFrames[0]
  T.eq(#first, 2, "frame 0 keeps both of its pieces")
  T.eq(first[1].quad.x, 0, "cell tile 0 sits at column 0")
  T.eq(first[1].quad.y, 0, "and row 0")
  -- tile 17 over 16 columns of 8px = column 1, row 1
  T.eq(first[2].quad.x, 8, "cell tile 17 wraps to column 1")
  T.eq(first[2].quad.y, 8, "and steps down a row")
  T.eq(first[2].dx, 8, "the piece keeps its offset inside the frame")
  T.eq(first[2].dy, 8, "on both axes")
  T.eq(first[1].w, 8, "pieces are cellWidth wide")

  local second = r.cellFrames[1]
  T.eq(#second, 1, "a frame may hold a single piece")
  T.eq(second[1].flipX, true, "a per-cell flip is carried through")
  T.eq(second[1].quad.x, 24, "cell tile 3 is column 3")
end

do
  -- mirroring a frame has to move each piece to the opposite side AND flip it,
  -- or a mirrored facing assembles inside-out
  local dx, flip = SpriteRenderer.mirrorCell(0, 8, 16, false)
  T.eq(dx, 8, "a left-hand piece mirrors to the right")
  T.eq(flip, true, "and is drawn flipped")

  dx, flip = SpriteRenderer.mirrorCell(8, 8, 16, false)
  T.eq(dx, 0, "a right-hand piece mirrors to the left")

  dx, flip = SpriteRenderer.mirrorCell(4, 8, 16, true)
  T.eq(dx, 4, "a centred piece stays centred")
  T.eq(flip, false, "and an already-flipped piece flips back")

  local w = 16
  dx = SpriteRenderer.mirrorCell(0, w, w, false)
  T.eq(dx, 0, "a full-width piece is unmoved by the mirror")
end

do
  local plain = SpriteRenderer.new({
    image = "fake.png", frames = 3, frameWidth = 16, frameHeight = 16,
  }, 1)
  T.eq(plain.cellFrames, nil,
    "a sprite without cells keeps the single-quad path")
  T.eq(plain.frameColumns, 1, "and the vanilla one-frame-per-row layout")
  T.eq(plain.frameOffset, 0, "starting at the top of the sheet")
end

Assets.image = realImage
love.graphics = realGraphics
if realLove == nil then _G.love = nil end

T.finish("sprite_multicell")
