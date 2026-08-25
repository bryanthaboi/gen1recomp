-- The dex-completion diploma (engine/events/diploma.asm DisplayDiploma /
-- diploma2.asm DisplayDiplomaTop): a bordered certificate page with the
-- player's name and character sprite, shown by the Celadon Mansion 3F game designer
-- once 150 species are owned. Diploma.render also backs the printed copy
-- (engine/printer/printer.asm PrintDiploma -> src/core/Printer.lua).

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local PaletteFX = require("src.render.PaletteFX")
local Sprites = require("src.pokemon.Sprites")
local SpriteRenderer = require("src.render.SpriteRenderer")
local Strings = require("src.core.Strings")

-- engine/events/diploma.asm:65
local OBP0_90 = { { 255, 255, 255 }, { 255, 255, 255 },
                  { 170, 170, 170 }, { 85, 85, 85 } }

local Diploma = {}
Diploma.__index = Diploma
Diploma.isOpaque = true

-- SGB: PalPacket_Generic (MEWMON), whole screen (engine/events/diploma.asm:67)
function Diploma:sgbPalettes(game)
  return PaletteFX.wholeNamed(game.data, "MEWMON")
end

local function tryImage(path)
  if not path then return nil end
  local ok, img = pcall(Assets.image, path)
  if ok and img then return img end
  local ok2, img2 = pcall(love.graphics.newImage, path)
  return ok2 and img2 or nil
end

local function loadFrame()
  local frame = tryImage("assets/generated/trainer_card/trainer_info.png")
  if not frame then return nil end
  local quads = {}
  for i = 0, 8 do
    quads[i] = love.graphics.newQuad((i % 3) * 8,
                                     math.floor(i / 3) * 8,
                                     8, 8, frame:getDimensions())
  end
  return { img = frame, quads = quads }
end

local function drawFrameBox(frame, tx, ty, tw, th)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
  if not frame then
    Font.drawBox(tx, ty, tw, th)
    return
  end
  local img = frame.img
  local q = frame.quads
  love.graphics.setColor(1, 1, 1, 1)
  -- engine/link/cable_club.asm:937
  love.graphics.draw(img, q[2], tx * 8, ty * 8)
  love.graphics.draw(img, q[4], (tx + tw - 1) * 8, ty * 8)
  love.graphics.draw(img, q[6], tx * 8, (ty + th - 1) * 8)
  love.graphics.draw(img, q[7], (tx + tw - 1) * 8, (ty + th - 1) * 8)
  for x = 1, tw - 2 do
    love.graphics.draw(img, q[3], (tx + x) * 8, ty * 8)
    love.graphics.draw(img, q[0], (tx + x) * 8, (ty + th - 1) * 8)
  end
  for y = 1, th - 2 do
    love.graphics.draw(img, q[5], tx * 8, (ty + y) * 8)
    love.graphics.draw(img, q[1], (tx + tw - 1) * 8, (ty + y) * 8)
  end
end

function Diploma.new(game, onDone)
  local self = setmetatable({
    game = game,
    onDone = onDone,
  }, Diploma)
  return self
end

function Diploma:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

-- the DisplayDiploma / DisplayDiplomaTop layout (hlcoord tiles -> x*8, y*8)
function Diploma.render(game)
  local frame = loadFrame()
  local circle = tryImage("assets/generated/trainer_card/circle_tile.png")

  -- 1. Outer ornate frame border: hlcoord 0, 0 / bc 16, 18 -> (0, 0, 20, 18)
  drawFrameBox(frame, 0, 0, 20, 18)

  -- 2. Draw Player character sprite: farcall DrawPlayerCharacter
  -- engine/movie/title.asm:321
  local title = (game.data and game.data.field and game.data.field.title) or {}
  local titlePlayer = title.player
  if type(titlePlayer) == "table" then titlePlayer = titlePlayer.path end
  local picPath, picTrueColor = Sprites.playerPic(
    titlePlayer or "assets/generated/title/player.png",
    { side = "front", kind = "diploma", data = game.data })
  local pic
  if picPath then
    if picTrueColor then
      pic = tryImage(picPath)
    else
      local ok, faded = pcall(SpriteRenderer.obpImage, picPath, OBP0_90,
                              "diploma")
      pic = (ok and faded) or tryImage(picPath)
    end
  end
  if pic then
    love.graphics.setColor(1, 1, 1, 1)
    local sx, sy, sw, sh = love.graphics.getScissor()
    -- engine/events/diploma.asm:44
    love.graphics.setScissor(8, 8, 144, 128)
    love.graphics.draw(pic, 115, 80)
    if sx then love.graphics.setScissor(sx, sy, sw, sh)
    else love.graphics.setScissor() end
    if picTrueColor then
      PaletteFX.markTrueColor(115, 80, pic:getDimensions())
    end
  end

  -- 3. Header: hlcoord 5, 2 with flanking circle tiles ($70)
  love.graphics.setColor(1, 1, 1, 1)
  if circle then
    love.graphics.draw(circle, 40, 16)   -- hlcoord 5, 2
    love.graphics.draw(circle, 104, 16)  -- hlcoord 13, 2
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("Diploma"), 48, 16)  -- hlcoord 6, 2

  -- 4. Player info: hlcoord 3, 4 ("PLAYER" / "Player") and hlcoord 10, 4 (name)
  Font.draw(Strings("Player"), 24, 32)
  local playerName = (game.save.player and game.save.player.name) or "RED"
  Font.draw(playerName, 80, 32)

  -- 5. Congratulations text: hlcoord 2, 6 double-spaced lines (rows 6, 8, 10, 12, 14)
  local congrats = {
    { text = "Congrats! This",     y = 48 },   -- hlcoord 2, 6
    { text = "diploma certifies",  y = 64 },   -- hlcoord 2, 8
    { text = "that you have",      y = 80 },   -- hlcoord 2, 10
    { text = "completed your",     y = 96 },   -- hlcoord 2, 12
    { text = "POKéDEX.",           y = 112 },  -- hlcoord 2, 14
  }
  for _, line in ipairs(congrats) do
    Font.draw(Strings(line.text), 16, line.y)
  end

  -- 6. Developer signature: hlcoord 9, 16
  Font.draw(Strings("GAME FREAK"), 72, 128)
  love.graphics.setColor(1, 1, 1, 1)
end

function Diploma:draw()
  Diploma.render(self.game)
end

return Diploma
