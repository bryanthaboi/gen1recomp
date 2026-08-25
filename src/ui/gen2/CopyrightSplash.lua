-- The boot copyright card (pokegold SplashScreen -> Copyright), ~100 frames
-- then on to the GAME FREAK splash; A/B/START skip it.
--
-- The cart's card is the three Nintendo / Creatures / GAME FREAK lines from
-- CopyrightGFX.  RomExtractorGen2 composes that into title/copyright_splash.png
-- and this screen draws it.

-- src/render/Assets.lua is the mod-override choke point: a raw
-- love.graphics.newImage skips overrides/ and AssetTransform output.
local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local Runtime = require("src.mods.Runtime")

local CopyrightSplash = {}
CopyrightSplash.__index = CopyrightSplash
CopyrightSplash.isOpaque = true

local SCREEN_W, SCREEN_H = 160, 144
local HOLD_FRAMES = 100

-- Rows are the Gen 1 card's, which sit where the cart's own three lines do.
-- Only used when the extracted splash image is missing.
local LINE_Y = { 48, 64, 80 }

-- Gold boots on the default BGP; Crystal inverts under SCGB_GAMEFREAK_LOGO
-- (../pokecrystal/engine/movie/splash.asm:20-30).
local DEFAULT_BACKDROP = { 1, 1, 1 }
local DEFAULT_INK = { 0, 0, 0 }

local function tryImage(path)
  if not path then return nil end
  local ok, image = pcall(Assets.image, path)
  if ok then return image end
  return nil
end

function CopyrightSplash:wantsFillScale() return true end
function CopyrightSplash:drawsWidescreen() return true end

function CopyrightSplash.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, CopyrightSplash)
  self.game = game
  self.onDone = opts.onDone
  local title = opts.title or {}
  -- Prefer an explicit override, then the extracted splash from title.lua.
  self.image = tryImage(opts.image)
    or tryImage(title.copyrightSplash)
    or tryImage("assets/generated/title/copyright_splash.png")
  self.backdrop = opts.backdrop or title.copyrightBackdrop or DEFAULT_BACKDROP
  self.ink = opts.ink or title.copyrightInk or DEFAULT_INK
  -- Text fallback only when the ROM extract is missing (tests / bare boots).
  self.lines = opts.lines
  self.frames = 0
  self.done = false
  return self
end

-- intro.boot.copyright: the first card of the GS boot cinema is on screen.
--
-- The four intro.boot.* names are Gen 2 ONLY, and deliberately new rather than
-- borrowed: Red boots straight into IntroMovie and has no copyright card, no
-- GAME FREAK splash and no attract movie, so there is no Gen 1 moment for any
-- of them to share a name with (see docs/mod-api-gen2-compat.md).  One name per
-- card, emitted the frame the card comes up, because that is the moment a mod
-- can act on -- swap the art, start its own jingle, or count the boot.  The
-- card's END needs no name of its own: Game2:showCopyright chains straight into
-- the next card, so intro.boot.gamefreak IS this card's end.
function CopyrightSplash:enter()
  if Runtime.wants("intro.boot.copyright") then
    Runtime.emit("intro.boot.copyright", { screen = self, game = self.game })
  end
end

function CopyrightSplash:update(_dt)
  self.frames = self.frames + 1
  local input = self.game.input
  local skip = input and (input:wasPressed("a") or input:wasPressed("start")
    or input:wasPressed("b") or input:wasPressed("select"))
  if skip or self.frames >= HOLD_FRAMES then
    if self.done then return end
    self.done = true
    if self.onDone then self.onDone() end
  end
end

function CopyrightSplash:fillBackdrop(width, height)
  local G = love.graphics
  local c = self.backdrop
  G.setColor(c[1], c[2], c[3], 1)
  G.rectangle("fill", 0, 0, width, height)
end

function CopyrightSplash:drawPanel()
  local G = love.graphics
  self:fillBackdrop(SCREEN_W, SCREEN_H)
  if self.image then
    G.setColor(1, 1, 1, 1)
    G.draw(self.image, 0, 0)
    return
  end
  if not self.lines then return end
  -- The Gen 2 font is a fixed 8px cell, so centring is a character count.
  G.setColor(self.ink[1], self.ink[2], self.ink[3], 1)
  for index, line in ipairs(self.lines) do
    local y = LINE_Y[index]
    if y then
      Font.draw(line, math.floor((SCREEN_W - #line * 8) / 2), y)
    end
  end
  G.setColor(1, 1, 1, 1)
end

function CopyrightSplash:draw()
  self:drawPanel()
end

function CopyrightSplash:drawWidescreen(winW, winH)
  local G = love.graphics
  self:fillBackdrop(winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return CopyrightSplash
