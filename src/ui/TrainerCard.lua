-- Trainer card (engine/menus/start_sub_menus.asm DrawTrainerInfo):
-- NAME / MONEY / TIME with the player's front pic upper-right, the
-- circle-dotted BADGES banner, and the numbered badge grid.  The boxes
-- are built from the real trainer_info.png frame tiles (the patterned
-- band + line style).

local Assets = require("src.render.Assets")
local Badges = require("src.inventory.Badges")
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")

local TrainerCard = {}
TrainerCard.__index = TrainerCard
TrainerCard.isOpaque = true

-- SGB: PalPacket_TrainerCard leads with MEWMON
function TrainerCard:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

-- through Assets.resolve so an enabled mod's overrides/ shadows these the
-- same way it shadows every other generated asset
local function tryImage(path)
  if not path then return nil end
  local ok, img = pcall(love.graphics.newImage, Assets.resolve(path))
  return ok and img or nil
end

local function quads16(img, count, stride, x0, y0)
  local q = {}
  local iw, ih = img:getDimensions()
  for i = 0, count - 1 do
    q[i] = love.graphics.newQuad(x0 or 0, (y0 or 0) + i * stride, 16, 16, iw, ih)
  end
  return q
end

function TrainerCard.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, onCancel = opts.onCancel },
                            TrainerCard)
  local img = tryImage("assets/generated/trainer_card/badges.png")
  if img then
    -- badges.2bpp is 8 stacked [face, badge] pairs (DrawBadges FaceBadgeTiles)
    self.faces = { img = img, quads = quads16(img, 8, 32, 0, 0) }
    self.badges = { img = img, quads = quads16(img, 8, 32, 0, 16) }
  end
  local nums = tryImage("assets/generated/trainer_card/badge_numbers.png")
  if nums then
    self.nums = { img = nums, quads = {} }
    local iw, ih = nums:getDimensions()
    for i = 0, 7 do
      self.nums.quads[i] = love.graphics.newQuad((i % 2) * 8,
                                                 math.floor(i / 2) * 8,
                                                 8, 8, iw, ih)
    end
  end
  -- frame tiles (3x3 sheet): 0 bottom, 1 right, 2 tl, 3 top, 4 tr,
  -- 5 left, 6 bl, 7 br, 8 solid pattern
  local frame = tryImage("assets/generated/trainer_card/trainer_info.png")
  if frame then
    self.frame = { img = frame, quads = {} }
    for i = 0, 8 do
      self.frame.quads[i] = love.graphics.newQuad((i % 3) * 8,
                                                  math.floor(i / 3) * 8,
                                                  8, 8, frame:getDimensions())
    end
  end
  self.circle = tryImage("assets/generated/trainer_card/circle_tile.png")

  -- Capture both return values from playerPath: path and trueColor flag.
  -- The trueColor flag is set by the player.sprite hook when a mod injects
  -- a custom portrait that should bypass the MEWMON palette pipeline.
  local picPath, picTrueColor = require("src.pokemon.Sprites").playerPath(
    game.data, "front", { kind = "trainer_card" })
  self.pic          = tryImage(picPath)
  self.picTrueColor = self.pic and picTrueColor or false
  -- engine/menus/start_sub_menus.asm:480-487
  if self.pic then
    local pw, ph = self.pic:getDimensions()
    self.picW = math.max(0, math.min(40, pw))
    self.picH = math.min(56, ph)
    self.picQuad = love.graphics.newQuad(0, 0, self.picW, self.picH, pw, ph)
  end

  return self
end

function TrainerCard:update(dt)
  local input = self.game.input
  -- either button dismisses the card back to the start menu
  -- (StartMenu_TrainerInfo: WaitForTextScrollButtonPress then
  -- RedisplayStartMenu)
  if input:wasPressed("a") or input:wasPressed("b") then
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  end
end

-- a frame box in tile coords from the trainer_info tiles
function TrainerCard:frameBox(tx, ty, tw, th)
  if not self.frame then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("line", tx * 8 + 0.5, ty * 8 + 0.5,
                            tw * 8 - 1, th * 8 - 1)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local img, q = self.frame.img, self.frame.quads
  love.graphics.setColor(1, 1, 1, 1)
  local x1, y1 = (tx + tw - 1) * 8, (ty + th - 1) * 8
  love.graphics.draw(img, q[2], tx * 8, ty * 8)
  love.graphics.draw(img, q[4], x1, ty * 8)
  love.graphics.draw(img, q[6], tx * 8, y1)
  love.graphics.draw(img, q[7], x1, y1)
  for i = 1, tw - 2 do
    love.graphics.draw(img, q[3], (tx + i) * 8, ty * 8)
    love.graphics.draw(img, q[0], (tx + i) * 8, y1)
  end
  for j = 1, th - 2 do
    love.graphics.draw(img, q[5], tx * 8, (ty + j) * 8)
    love.graphics.draw(img, q[1], x1, (ty + j) * 8)
  end
end

function TrainerCard:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local save = self.game.save

  -- top card (rows 0-7): NAME / MONEY / TIME, pic upper-right
  self:frameBox(0, 0, 20, 8)
  if self.pic and self.picQuad then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.pic, self.picQuad, 120, 8)
    -- True-colour portraits (e.g. mod-injected custom characters) carry their
    -- own colours and must not be re-mapped by the MEWMON zone shader.
    -- markTrueColor appends a colors=false zone that the Renderer splices at
    -- the end of the zone list, causing it to re-blit just this rect without
    -- the palette shader on top of the already-colourised frame.
    -- This matches the pattern used by OakSpeech, HallOfFame and SummaryMenu.
    if self.picTrueColor then
      require("src.render.PaletteFX").markTrueColor(120, 8, self.picW, self.picH)
    end
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("NAME/%s", save.player.name or "RED"), 16, 16)
  Font.draw(Strings("MONEY/¥%d", save.money or 0), 16, 32)
  local t = math.floor(save.playTime or 0)
  -- home/print_num.asm:217
  Font.draw(Strings("TIME/  %d:%02d", math.floor(t / 3600),
                    math.floor(t / 60) % 60), 16, 48)

  -- the circle-dotted BADGES banner (TrainerInfo_BadgesText)
  -- engine/menus/start_sub_menus.asm:544
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("BADGES"), 56, 72)
  if self.circle then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.circle, 48, 72)
    love.graphics.draw(self.circle, 104, 72)
    love.graphics.setColor(0, 0, 0, 1)
  end

  -- numbered badge grid (rows 10-17): face by default, badge when owned
  -- engine/menus/start_sub_menus.asm:537
  self:frameBox(1, 10, 18, 8)
  if self.frame then
    love.graphics.setColor(1, 1, 1, 1)
    for j = 0, 7 do
      love.graphics.draw(self.frame.img, self.frame.quads[8], 0, (10 + j) * 8)
      love.graphics.draw(self.frame.img, self.frame.quads[8], 152, (10 + j) * 8)
    end
  end
  local badges = Badges.list(self.game.data)
  for i = 1, #badges do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    -- engine/menus/draw_badges.asm:46
    local tx, ty = 16 + col * 32, 88 + row * 24
    -- the extracted sheets cover the eight Kanto slots; a longer badge
    -- list draws its extra entries unnumbered rather than crashing
    if self.nums and self.nums.quads[i - 1] then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(self.nums.img, self.nums.quads[i - 1], tx, ty)
    end
    if self.faces and self.faces.quads[i - 1] then
      love.graphics.setColor(1, 1, 1, 1)
      local owned = save.inventory[Badges.itemFor(badges[i])]
      local sheet = owned and self.badges or self.faces
      love.graphics.draw(sheet.img, sheet.quads[i - 1], tx + 8, ty + 8)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return TrainerCard
