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
-- (RomExtractorGen2:extractDiploma); a cache that predates that stage falls
-- back to the plain Chrome.box frame below, which is a placeholder and not
-- the real seal.
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
-- COLOUR.  _CGB_Diploma (engine/gfx/cgb_layouts.asm) loads all eight
-- DiplomaPalettes sets and then WipeAttrmap zeroes the attrmap, so every tile
-- on the screen -- art and text alike -- draws through set 0.  The strings go
-- down with Chrome.printThrough rather than Chrome.print for that reason: a
-- black print over the art would be the one thing on screen not going through
-- the palette.
--
-- WaitPressAorB_BlinkCursor just parks on A or B; there is no menu here.

local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Strings = require("src.core.Strings")

local Diploma = {}
Diploma.__index = Diploma
Diploma.isOpaque = true

function Diploma:wantsFillScale() return true end

local CERTIFICATION = {
  Strings.source("This certifies"),
  Strings.source("that you have"),
  Strings.source("completed the"),
  Strings.source("new #DEX."),
  Strings.source("Congratulations!"),
}

-- opts: playerName, gfx, onClose()
function Diploma.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Diploma)
  self.game = game
  local save = game and game.save
  self.playerName = opts.playerName
    or (save and save.player and save.player.name) or "?"
  self.onClose = opts.onClose
  self.gfx = opts.gfx or ((game and game.data) or {}).gen2Diploma
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

-- Set 0 of DiplomaPalettes, the one WipeAttrmap leaves the whole screen on.
function Diploma:palette()
  local palettes = self.gfx and self.gfx.palettes
  return palettes and palettes[1] or nil
end

function Diploma:image(path)
  if not path then return nil end
  local cached = self.images[path]
  if cached == nil then
    local Assets = require("src.render.Assets")
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    if cached then cached:setFilter("nearest", "nearest") end
    self.images[path] = cached
  end
  return cached or nil
end

-- The page as one batch of 8x8 tiles.  Built once, because the tilemap is
-- copied once and nothing on this screen ever moves; the palette is applied at
-- draw time instead of baked in, so a COLOR mode change needs no rebuild.
function Diploma:batch()
  if self.tilemap ~= nil then return self.tilemap or nil end
  local gfx = self.gfx
  local image = gfx and gfx.page1 and self:image(gfx.image)
  if not image then
    self.tilemap = false
    return nil
  end
  local across = gfx.sheetTiles or 16
  local width = gfx.width or Chrome.SCREEN_W
  local height = gfx.height or Chrome.SCREEN_H
  local batch = love.graphics.newSpriteBatch(image, width * height)
  local quads = {}
  for index = 0, width * height - 1 do
    local tile = gfx.page1[index + 1] or 0
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

  if batch then
    -- ClearTilemap leaves the screen on colour 0 of the loaded set, and the
    -- page covers all of it, but the fill is what a letterboxed fill-scale
    -- draw shows outside the 160x144 page.
    local paper = GbcPalette.color(palette, 1)
    love.graphics.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
    love.graphics.rectangle("fill", 0, 0,
      Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
    love.graphics.setColor(1, 1, 1, 1)
    local function blit() love.graphics.draw(batch, 0, 0) end
    -- A palette-less cache would send the shader four black entries, so the
    -- sheet's own grey shades are the fallback rather than a black page.
    if palette then GbcPalette.with(palette, blit) else blit() end
    love.graphics.setColor(1, 1, 1, 1)
  else
    -- No gfx/diploma in the cache: a placeholder frame, not the real seal.
    Chrome.clear()
    Chrome.box(0, 0, Chrome.SCREEN_W, Chrome.SCREEN_H)
  end

  Chrome.printThrough(Strings("PLAYER"), 2, 5, palette)
  Chrome.printThrough(self.playerName, 9, 5, palette)

  for i, line in ipairs(CERTIFICATION) do
    Chrome.printThrough(Strings(line), 2, 7 + i, palette)
  end
end

function Diploma:draw()
  self:drawPanel()
end

-- PlaceDiplomaOnScreen opens on ClearBGPalettes / ClearTilemap
-- (engine/events/diploma.asm:13-14), so the map is gone and the diploma's own
-- paper is the whole screen.  Colour 1 of the page palette is that paper (a
-- pale green), which is why the surround cannot be the generic white the
-- fallback paints: the page would sit in a white field instead of running to
-- the window edge.
function Diploma:drawsWidescreen() return true end

function Diploma:drawWidescreen(winW, winH)
  local G = love.graphics
  -- Nil palette degrades to the DMG ramp's colour 1, i.e. white, matching the
  -- Chrome.clear() the panel falls back to when the cache has no gfx/diploma.
  local paper = GbcPalette.color(self:palette(), 1)
  G.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  G.rectangle("fill", 0, 0, winW, winH)
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
