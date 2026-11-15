-- The #DEX-completion diploma (engine/events/diploma.asm PlaceDiplomaOnScreen,
-- reached through `special Diploma` after Celadon Mansion 3F's game designer
-- checks VAR_DEXCAUGHT == 251).  Only page 1 is ever shown in play --
-- PrintDiplomaPage2 is the Game Boy Printer's second sheet
-- (engine/printer/printer.asm:420), built with hBGMapMode zeroed and undone by
-- SafeLoadTempTilemapToTilemap, so it never reaches the screen on the cart
-- either -- so this transcribes PlaceDiplomaOnScreen alone, not diploma2.asm.
--
-- THE CERTIFICATE IS A TILEMAP, NOT A TEXT BOX.  PlaceDiplomaOnScreen
-- decompresses DiplomaGFX into vTiles2 and then CopyBytes' DiplomaPage1Tilemap
-- (a whole SCREEN_AREA of tile ids) straight over the background before a
-- single string is placed, so the border, the seal and the ribbon are cart
-- art.  Both come out of the cache as `data.gen2Diploma`
-- (RomExtractorGen2:extractDiploma).
--
-- Positions below are the literal hlcoord operands PlaceDiplomaOnScreen
-- calls PlaceString with, not a layout guessed from a screenshot:
--
--   hlcoord 2, 5    "PLAYER" (.Player, "PLAYER@")
--   hlcoord 15, 5   .EmptyString ("@") -- a bare terminator, nothing to draw
--   hlcoord 9, 5    wPlayerName, dropped in over the row .Player/.EmptyString
--                   bracket
--   hlcoord 2, 8    .Certification, five `next`-joined lines that PlaceString
--                   walks one row down at column 2 apiece: rows 8-12
--
-- WaitPressAorB_BlinkCursor just parks on A or B; there is no menu here.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local RomText = require("src.core.RomText")

local Diploma = {}
Diploma.__index = Diploma
Diploma.isOpaque = true

function Diploma:wantsFillScale() return true end

-- opts: playerName, gfx, onClose()
function Diploma.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Diploma)
  self.game = game
  local save = game and game.save
  self.playerName = opts.playerName
    or (save and save.player and save.player.name) or "?"
  self.onClose = opts.onClose
  local data = game and game.data
  self.player = RomText(data, "PlaceDiplomaOnScreen.Player")
  self.certification = {}
  for line in (RomText(data, "PlaceDiplomaOnScreen.Certification") .. "\n"):gmatch("(.-)\n") do
    self.certification[#self.certification + 1] = line
  end
  self.gfx = opts.gfx or (data or {}).gen2Diploma
  self.images = {}
  self.done = false
  return self
end

function Diploma:finish()
  if self.done then return end
  self.done = true
  if self.onClose then self.onClose() end
end

function Diploma:update(_dt)
  if self.done then return end
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("a") or input:wasPressed("b") then
    self:finish()
  end
end

function Diploma:need(key)
  local value = self.gfx and self.gfx[key]
  if value == nil then error("diploma.lua has no " .. key, 2) end
  return value
end

-- engine/gfx/cgb_layouts.asm:495
function Diploma:palette()
  return self:need("bgPalette")
end

function Diploma:image(path)
  local cached = self.images[path]
  if not cached then
    cached = Assets.image(path)
    cached:setFilter("nearest", "nearest")
    self.images[path] = cached
  end
  return cached
end

-- The page as one batch of 8x8 tiles.  Built once, because the tilemap is
-- copied once and nothing on this screen ever moves; the palette is applied at
-- draw time instead of baked in, so a COLOR mode change needs no rebuild.
function Diploma:batch()
  if self.tilemap then return self.tilemap end
  local page1 = self:need("page1")
  local image = self:image(self:need("image"))
  local across = self:need("sheetTiles")
  local width = self:need("width")
  local height = self:need("height")
  local batch = love.graphics.newSpriteBatch(image, width * height)
  local quads = {}
  for index = 0, width * height - 1 do
    local tile = page1[index + 1]
    local quad = quads[tile]
    if not quad then
      quad = love.graphics.newQuad(tile % across * 8,
        math.floor(tile / across) * 8, 8, 8, image:getDimensions())
      quads[tile] = quad
    end
    batch:add(quad, index % width * 8, math.floor(index / width) * 8)
  end
  self.tilemap = batch
  return batch
end

function Diploma:drawPanel()
  local palette = self:palette()
  local batch = self:batch()

  local paper = GbcPalette.color(palette, 1)
  love.graphics.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  love.graphics.rectangle("fill", 0, 0,
    Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
  love.graphics.setColor(1, 1, 1, 1)
  GbcPalette.with(palette, function() love.graphics.draw(batch, 0, 0) end)
  love.graphics.setColor(1, 1, 1, 1)

  Chrome.printThrough(self.player, 2, 5, palette)
  Chrome.printThrough(self.playerName, 9, 5, palette)

  for i, line in ipairs(self.certification) do
    Chrome.printThrough(line, 2, 7 + i, palette)
  end
end

function Diploma:draw()
  self:drawPanel()
end

-- PlaceDiplomaOnScreen opens on ClearBGPalettes / ClearTilemap
-- (engine/events/diploma.asm:13-14), so the map is gone and the diploma's own
-- paper is the whole screen.
function Diploma:drawsWidescreen() return true end

function Diploma:drawWidescreen(winW, winH)
  local G = love.graphics
  local paper = GbcPalette.color(self:palette(), 1)
  Chrome.letterbox(winW, winH, paper[1] / 255, paper[2] / 255, paper[3] / 255)
  G.setColor(1, 1, 1, 1)
  local scale = Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  G.push()
  G.translate(ox, oy)
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return Diploma
