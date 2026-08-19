-- Gen 2 title: colored TitleScreenTilemap BG, scrolling clouds, Ho-Oh
-- wing-flap (Frameset_GSIntroHoOhLugia), spark trails, A/Start to continue.
-- drawWidescreen fills the window with sky/clouds so widescreen has no
-- pillarbox voids; the 160x144 art stays aspect-centered on top.

-- src/render/Assets.lua is the mod-override choke point: a raw
-- love.graphics.newImage skips overrides/ and AssetTransform output.
local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Music = require("src.core.Music")
local Runtime = require("src.mods.Runtime")
local SpriteAnims = require("src.ui.gen2.SpriteAnims")

local TitleState = {}
TitleState.__index = TitleState
TitleState.isOpaque = true

-- title_bg_gold.pal mid-sky shade (sampled from composed title_screen.png).
local SKY = { 123 / 255, 165 / 255, 255 / 255, 1 }
-- ...and its grey stand-in, for when COLOR is not GBC.  The title art is the
-- one thing in the port baked with its colours in (see the extractor), so the
-- window fill that matches it has to be picked the same way the sheet is.
-- The sky is BG colour 2, and LoadTitleScreenPals' rBGP (%11011000) sends
-- that colour to shade 1, not to shade 2 -- the grey sheet is baked through
-- the same register, so the fill has to follow it or the surround comes out
-- darker than the screen it surrounds.
local SKY_GRAY = { 170 / 255, 170 / 255, 170 / 255, 1 }

local function tryImage(path)
  if not path then return nil end
  local ok, image = pcall(Assets.image, path)
  if ok then return image end
  return nil
end

function TitleState:wantsFillScale() return true end
function TitleState:drawsWidescreen() return true end

function TitleState.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, TitleState)
  self.game = game
  self.onContinue = opts.onContinue
  local title = opts.title or {}
  self.title = title
  self.screenColor = tryImage(title.screen
    or "assets/generated/title/title_screen.png")
  self.cloudsColor = tryImage(title.clouds
    or "assets/generated/title/clouds.png")
  self.trailColor = tryImage(title.trail or "assets/generated/title/trail.png")
  -- The uncoloured set, absent from a cache built before COLOR existed -- in
  -- which case pickArt falls back to the colour one and DMG simply looks the
  -- way it did before rather than failing to draw.
  self.screenGray = tryImage(title.screenGray)
  self.cloudsGray = tryImage(title.cloudsGray)
  self.trailGray = tryImage(title.trailGray)
  -- `depixel 12, 11` less the OAM bias and the pose's own origin; see the
  -- extractor, which writes the same pair into title.lua.
  self.hoohX = tonumber(title.hoohX) or 48
  self.hoohY = tonumber(title.hoohY) or 56
  self.cloudY = tonumber(title.cloudY) or 88
  self.cloudScrollEvery = tonumber(title.cloudScrollEvery) or 8

  self.hoohColor, self.hoohGray = {}, {}
  local paths = title.hoohFrames
  if type(paths) == "table" then
    for i, path in ipairs(paths) do
      self.hoohColor[i] = tryImage(path)
    end
  end
  if #self.hoohColor == 0 then
    self.hoohColor[1] = tryImage(title.hooh or "assets/generated/title/hooh.png")
  end
  if type(title.hoohFramesGray) == "table" then
    for i, path in ipairs(title.hoohFramesGray) do
      self.hoohGray[i] = tryImage(path)
    end
  end
  self.sequence = title.hoohSequence or {
    { 1, 10 }, { 2, 9 }, { 3, 10 }, { 4, 10 }, { 3, 9 }, { 5, 10 },
  }
  self.seqIndex = 1
  self.seqLeft = self.sequence[1] and self.sequence[1][2] or 10
  self.frame = 1

  -- AnimSeq_GSIntroHoOhLugia's SPRITEANIMSTRUCT_VAR1.
  self.hoohPhase = 0
  self.frameCounter = 0
  self.cloudScroll = 0
  self.trails = {}
  -- UpdateTitleTrailSprite / TitleTrailCoords (intro_menu.asm), in pixels.
  self.trailSpawns = {
    { 80, 88 }, { 104, 88 }, { 104, 88 }, { 120, 88 },
    { 120, 88 }, { 88, 88 },
  }
  self.trailSpawnIndex = 1
  -- How far past the 160px frame trails may fly (GB pixels); set each draw.
  self.trailMaxX = 200
  self.musicStarted = false
  return self
end

function TitleState:enter()
  local data = self.game and self.game.data
  if data and data.audio and data.audio.runtime and not self.musicStarted then
    Music.play(data, "Music_TitleScreen", true, { reason = "title" })
    self.musicStarted = true
  end
  -- intro.boot.title: the last card of the GS boot cinema, up with its music
  -- started.  Gen 2 only, like the rest of intro.boot.* (see
  -- src/ui/gen2/CopyrightSplash.lua for why the set is new rather than shared).
  -- Its end is the main menu opening, which src/ui/gen2/MainMenu.lua owns, so
  -- there is no `ended` name here.  The title's MENU is a different seam again:
  -- that is Gen 1's `ui.title_menu.items`, which Gold reaches through the main
  -- menu rather than through this screen.
  if Runtime.wants("intro.boot.title") then
    Runtime.emit("intro.boot.title", { screen = self, game = self.game })
  end
end

-- AnimSeq_GSIntroHoOhLugia (engine/sprite_anims/functions.asm): VAR1 counts up
-- one per frame and the struct's Y offset becomes `d * sin(VAR1 * pi/32)` with
-- d = 2 on Gold (Silver counts DOWN with d = 8).  Sprites_Sine hands back the
-- byte the ASM leaves in a, so the down half of the wave arrives in two's
-- complement and has to be read as a signed pixel delta here.
function TitleState:hoohBob()
  local value = SpriteAnims.sine(self.hoohPhase, 2)
  if value >= 0x80 then value = value - 0x100 end
  return value
end

function TitleState:advanceHooh()
  self.hoohPhase = (self.hoohPhase + 1) % 256
  self.seqLeft = self.seqLeft - 1
  if self.seqLeft > 0 then return end
  self.seqIndex = self.seqIndex + 1
  if self.seqIndex > #self.sequence then self.seqIndex = 1 end
  local step = self.sequence[self.seqIndex]
  self.frame = step[1]
  self.seqLeft = step[2]
end

function TitleState:spawnTrail()
  if not (self.trailColor or self.trailGray) then return end
  if self.frameCounter % 4 ~= 0 then return end
  local spawn = self.trailSpawns[self.trailSpawnIndex]
  self.trailSpawnIndex = self.trailSpawnIndex % #self.trailSpawns + 1
  if not spawn then return end
  self.trails[#self.trails + 1] = {
    x = spawn[1], y = spawn[2], phase = love.math.random(0, 255),
  }
end

function TitleState:stepTrails()
  local alive = {}
  local maxX = self.trailMaxX or 200
  for _, t in ipairs(self.trails) do
    t.x = t.x + 4
    t.y = t.y + 1
    t.phase = t.phase + 3
    t.drawY = t.y + math.floor(math.sin(t.phase / 16) * 2)
    if t.x < maxX then alive[#alive + 1] = t end
  end
  self.trails = alive
end

function TitleState:update(_dt)
  self.frameCounter = self.frameCounter + 1
  self:advanceHooh()
  if self.frameCounter % self.cloudScrollEvery == 0 then
    self.cloudScroll = (self.cloudScroll - 1) % 160
  end
  self:spawnTrail()
  self:stepTrails()

  local input = self.game.input
  if input and (input:wasPressed("a") or input:wasPressed("start")) then
    if self.onContinue then self.onContinue() end
  end
end

-- Which of the two baked sets is showing.  GBC is the cart's colour; every
-- other COLOR mode wants the grey source, and CLASSIC's green comes from the
-- present pass over the finished frame rather than from a third set of art.
function TitleState:gray()
  return GbcPalette.mode ~= "gbc"
end

function TitleState:art()
  if self:gray() then
    return self.screenGray or self.screenColor,
      self.cloudsGray or self.cloudsColor,
      self.trailGray or self.trailColor,
      (#self.hoohGray > 0) and self.hoohGray or self.hoohColor
  end
  return self.screenColor, self.cloudsColor, self.trailColor, self.hoohColor
end

-- Tile the cloud strip across [x0, x1) in GB pixel space (y = 0 of strip).
function TitleState:drawCloudSpan(x0, x1)
  local _, clouds = self:art()
  if not clouds then return end
  local G = love.graphics
  local s = self.cloudScroll % 160
  -- First tile origin such that the scroll lines up with the 160px frame.
  local start = math.floor((x0 + s) / 160) * 160 - s
  for x = start, x1, 160 do
    G.draw(clouds, x, 0)
  end
end

function TitleState:drawContent()
  local G = love.graphics
  local screen, _, trail, hoohFrames = self:art()
  G.setColor(1, 1, 1, 1)
  if screen then
    -- title_screen.png already carries the cart's © GAME FREAK line on row 17.
    G.draw(screen, 0, 0)
  else
    G.rectangle("fill", 0, 0, 160, 144)
  end

  -- Center cloud scroll (matches the side tiles from drawWidescreen).
  G.push()
  G.translate(0, self.cloudY)
  self:drawCloudSpan(0, 160)
  G.pop()

  local bob = self:hoohBob()
  local hooh = hoohFrames[self.frame] or hoohFrames[1]
  if hooh then
    G.draw(hooh, self.hoohX, self.hoohY + bob)
  end

  if trail then
    for _, t in ipairs(self.trails) do
      G.draw(trail, t.x, t.drawY or t.y)
    end
  end
end

-- Letterboxed fallback (non-widescreen hosts).
function TitleState:draw()
  self:drawContent()
end

-- Full-window sky + cloud wrap, then centered 160x144 art.
function TitleState:drawWidescreen(winW, winH)
  local G = love.graphics
  local scale = Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  local cloudTop = oy + self.cloudY * scale
  -- Let trails fly into the side bands.
  self.trailMaxX = math.ceil((winW - ox) / scale) + 16

  -- Sky above the cloud line, paper white below : edge to edge.  The fill has
  -- to match whichever baked set is showing, or the surround would stay blue
  -- around a grey screen.
  local sky = self:gray() and SKY_GRAY or SKY
  G.setColor(sky[1], sky[2], sky[3], 1)
  G.rectangle("fill", 0, 0, winW, math.max(0, cloudTop))
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, cloudTop, winW, winH - cloudTop)

  -- Clouds across the full window width, aligned to the GB cloud band.
  G.push()
  G.translate(ox, cloudTop)
  G.scale(scale, scale)
  local left = -math.ceil(ox / scale) - 160
  local right = math.ceil((winW - ox) / scale) + 160
  self:drawCloudSpan(left, right)
  G.pop()

  -- Centered original composition (logo / Ho-Oh / copyright / trails).
  G.push()
  G.translate(ox, oy)
  G.scale(scale, scale)
  self:drawContent()
  G.pop()
end

return TitleState
