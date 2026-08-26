-- The GAME FREAK splash (pokegold engine/movie/splash.asm).
--
-- This is the six-scene jumptable GameFreakPresentsScene walks, not a hold on
-- a logo image: a star spirals in from the edge of the screen, the logo is
-- placed where the star died, sparkles fly off it for 128 frames while the
-- words "GAME FREAK" appear halfway through, then "presents", then a last
-- 128-frame hold.  Any button skips the whole thing.
--
--   scene 0  Star            spawn the star, play SFX_GAME_FREAK_LOGO_GS
--   scene 1  PlaceLogo       wait for the star to die, then place the logo
--   scene 2  LogoSparkles    128 frames of sparkles; "GAME FREAK" at 63
--   scene 3  PlacePresents   "presents", reset the timer
--   scene 4  WaitForTimer    128 frames
--   scene 5  SetDoneFlag     finished
--
-- GRAPHICS.  GameFreakLogoGFX is two INCBINs run together and the extractor
-- splits them (RomExtractorGen2:splashGfx): a 13-tile letter strip at VRAM
-- $80, the 3x5 logo at $8d, the star at $9c and three sparkle frames at $9e.
-- GameFreakPresentsInit points wSpriteAnimDict at $8d, so every OAM set's
-- vtile offset is relative to the logo -- which is why the system's
-- vtileBase is set here and nowhere else.
--
-- COLOUR.  _CGB_GamefreakLogo loads PREDEFPAL_GAMEFREAK_LOGO_OB into OBJ
-- palettes 0 AND 1 (white, white, yellow, yellow) and the BG palette runs
-- black to white.  The two OBJ palettes differ only in the DMG byte indexing
-- them: OBP0 stays %11111000 (star and sparkles are yellow) while OBP1 starts
-- at %00100100 and GameFreakPresents_UpdateLogoPal rotates it right two bits
-- every 16 frames until it reaches %10010000 -- so the logo is white for the
-- first 48 frames and yellow after that.

local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Music = require("src.core.Music")
local Runtime = require("src.mods.Runtime")
local Sound = require("src.core.Sound")
local SpriteAnims = require("src.ui.gen2.SpriteAnims")
local TileSheet = require("src.ui.gen2.TileSheet")

local GameFreakPresents = {}
GameFreakPresents.__index = GameFreakPresents
GameFreakPresents.isOpaque = true

local SCREEN_W, SCREEN_H = 160, 144

-- wSpriteAnimDict[SPRITE_ANIM_DICT_GS_SPLASH] = $8d (GameFreakPresentsInit).
local DICT_VTILE = 0x8d

-- `depixel 10, 11, 4, 0` and `depixel 11, 11` are y-first: x=e, y=d
-- (engine/sprite_anims/core.asm:113).
local LOGO_X, LOGO_Y = 11 * 8 + 0, 10 * 8 + 4
local SPARKLE_X, SPARKLE_Y = 11 * 8, 11 * 8

-- GameFreakPresents_PlaceGameFreak / _PlacePresents.  $8d is the logo's own
-- first tile borrowed as a blank, which is why "GAME FREAK" reads as ten
-- tiles for nine letters and a space.
local GAME_FREAK = { 0x80, 0x81, 0x82, 0x83, 0x8d, 0x84, 0x85, 0x83, 0x81, 0x86 }
local GAME_FREAK_X, GAME_FREAK_Y = 5, 12
local PRESENTS = { 0x87, 0x88, 0x89, 0x8a, 0x8b, 0x8c }
local PRESENTS_X, PRESENTS_Y = 7, 13

-- GameFreakPresents_Sparkle .sparkle_vectors: angle (6 bits), distance.
local SPARKLE_VECTORS = {
  { 0x00, 0x03 }, { 0x08, 0x04 }, { 0x04, 0x03 }, { 0x0c, 0x02 },
  { 0x10, 0x02 }, { 0x18, 0x03 }, { 0x14, 0x04 }, { 0x1c, 0x03 },
  { 0x20, 0x02 }, { 0x28, 0x02 }, { 0x24, 0x03 }, { 0x2c, 0x04 },
  { 0x30, 0x04 }, { 0x38, 0x03 }, { 0x34, 0x02 }, { 0x3c, 0x04 },
}

local SCENE_TIMER = 128
-- The `ld c, 16 / call DelayFrames` every exit path runs before returning.
local EXIT_FRAMES = 16

-- DmgToCgbObjPals / DmgToCgbObjPal1: the DMG palette byte is four 2-bit
-- indices into the real four-colour palette, colour 0 in the low bits.
local OBP0 = 0xf8 -- %11111000, the star and the sparkles
local OBP1_START = 0x24 -- %00100100, the logo before the rotation runs
local OBP1_FINAL = 0x90 -- %10010000, where UpdateLogoPal stops

local BLACK = { 0, 0, 0 }
local WHITE = { 255, 255, 255 }
local YELLOW = { 206, 247, 0 } -- RGB 25,30,00 out of gfx/sgb/predef.pal

local DEFAULT_OB = { WHITE, WHITE, YELLOW, YELLOW }
local DEFAULT_BG = { BLACK, { 66, 90, 90 }, { 173, 173, 173 }, WHITE }

local function permute(colors, byte)
  local out = {}
  for index = 0, 3 do
    out[index + 1] = colors[math.floor(byte / 4 ^ index) % 4 + 1] or BLACK
  end
  return out
end

function GameFreakPresents:wantsFillScale() return true end
function GameFreakPresents:drawsWidescreen() return true end

-- opts: oakSpeech (data/generated/oak_speech.lua, for its `splash` table),
-- onDone
function GameFreakPresents.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, GameFreakPresents)
  self.game = game
  self.onDone = opts.onDone
  local splash = (opts.oakSpeech or {}).splash or {}
  self.obColors = splash.obPalette or DEFAULT_OB
  self.bgColors = splash.bgPalette or DEFAULT_BG

  -- One sheet per INCBIN, each addressed by the VRAM id its tiles were
  -- loaded at, so an OAM entry's tile id picks its own sheet.
  self.sheets = {
    TileSheet.new({ path = splash.presents
      or "assets/generated/splash/presents.png", wide = 13, firstTile = 0x80 }),
    TileSheet.new({ path = splash.logo
      or "assets/generated/splash/logo.png", wide = 3, firstTile = 0x8d }),
    TileSheet.new({ path = splash.star
      or "assets/generated/splash/star.png", wide = 1, firstTile = 0x9c }),
    TileSheet.new({ path = splash.sparkle
      or "assets/generated/splash/sparkle.png", wide = 3, firstTile = 0x9e }),
  }

  self.anims = SpriteAnims.new()
  self.anims.vtileBase = DICT_VTILE
  self.scene = 0
  self.timer = 0
  self.obp1 = OBP1_START
  self.tiles = {} -- the BG tilemap, sparse: [y][x] = tile id
  self.frames = 0
  -- exitTail, not `exit`: enter/exit are the StateStack's own callback names
  -- and a state is an ordinary table, so a field there is a call the stack
  -- would make on a pop.
  self.exitTail = nil
  self.done = false
  self.sfxPlayed = false
  return self
end

function GameFreakPresents:enter()
  local data = self.game and self.game.data
  if data and data.audio and data.audio.runtime then
    Music.stop()
  end
  -- intro.boot.gamefreak: scene 0 of GameFreakPresentsScene is about to run,
  -- i.e. the splash is up and its star has not been spawned yet.  Gen 2 only:
  -- Red has no splash.asm counterpart, so this is a new name rather than a
  -- borrowed one (see CopyrightSplash for the set).  It also marks the end of
  -- the copyright card, which is why that card has no `ended` name.
  if Runtime.wants("intro.boot.gamefreak") then
    Runtime.emit("intro.boot.gamefreak", { screen = self, game = self.game })
  end
end

function GameFreakPresents:finish()
  if self.done then return end
  self.done = true
  if self.onDone then self.onDone(self.skipped) end
end

-- PlaceString into the sparse tilemap.
function GameFreakPresents:placeString(tiles, tx, ty)
  local row = self.tiles[ty]
  if not row then
    row = {}
    self.tiles[ty] = row
  end
  for index, tile in ipairs(tiles) do
    row[tx + index - 1] = tile
  end
end

--------------------------------------------------------------------------
-- GameFreakPresentsScene
--------------------------------------------------------------------------

function GameFreakPresents:sceneStar()
  self.anims.flag = 0 -- wIntroSceneFrameCounter
  local st = self.anims:init("GS_GAMEFREAK_LOGO_STAR", LOGO_X, LOGO_Y)
  if st then st.var1 = 0x80 end
  local data = self.game and self.game.data
  if data and data.audio and data.audio.sfx
      and data.audio.sfx.Sfx_GameFreakLogoGs then
    Sound.play(data, "Sfx_GameFreakLogoGs")
  end
  self.scene = self.scene + 1
end

function GameFreakPresents:scenePlaceLogo()
  -- The star's own sequence sets the flag when it reaches the middle.
  if self.anims.flag == 0 then return end
  self.anims:init("GAMEFREAK_LOGO", LOGO_X, LOGO_Y)
  -- UpdateLogoPal is called out of the LOGO's own AnimSeq, so its clock only
  -- runs once the logo exists.  Without this the rotation would fire on every
  -- frame of the star scene (the timer is still 0 there, and 0 % 16 == 0) and
  -- the logo would be yellow before it was ever placed.
  self.logoAlive = true
  self.scene = self.scene + 1
  self.timer = SCENE_TIMER
end

-- GameFreakPresents_Sparkle: one new sparkle on every second frame, its
-- direction taken from the low four bits of half the timer.
function GameFreakPresents:sparkle(counter)
  if counter % 2 ~= 0 then return end
  local st = self.anims:init("GS_GAMEFREAK_LOGO_SPARKLE",
    SPARKLE_X, SPARKLE_Y)
  if not st then return end -- all ten structs busy, as on hardware
  local vector = SPARKLE_VECTORS[math.floor(counter / 2) % 16 + 1]
  st.jt = vector[1]
  st.var1 = 0
  st.var2 = vector[2]
end

function GameFreakPresents:sceneLogoSparkles()
  local counter = self.timer
  if counter == 0 then
    self.timer = SCENE_TIMER
    self.scene = self.scene + 1
    return
  end
  self.timer = self.timer - 1
  if counter == 63 then
    self:placeString(GAME_FREAK, GAME_FREAK_X, GAME_FREAK_Y)
  end
  self:sparkle(counter)
end

function GameFreakPresents:scenePlacePresents()
  self:placeString(PRESENTS, PRESENTS_X, PRESENTS_Y)
  self.scene = self.scene + 1
  self.timer = SCENE_TIMER
end

function GameFreakPresents:sceneWaitForTimer()
  if self.timer == 0 then
    self.scene = self.scene + 1
    return
  end
  self.timer = self.timer - 1
end

local SCENES = {
  GameFreakPresents.sceneStar,
  GameFreakPresents.scenePlaceLogo,
  GameFreakPresents.sceneLogoSparkles,
  GameFreakPresents.scenePlacePresents,
  GameFreakPresents.sceneWaitForTimer,
  -- GameFreakPresents_SetDoneFlag.
  function(self) self:beginExit() end,
}

-- The tail both exit paths share: ClearSpriteAnims, ClearTilemap and
-- ClearSprites, then `ld c, 16 / call DelayFrames` on an empty screen.
function GameFreakPresents:beginExit()
  if self.exitTail then return end
  self.anims:clear()
  self.tiles = {}
  self.logoAlive = false
  self.exitTail = 0
end

-- GameFreakPresents_UpdateLogoPal, called out of the logo's AnimSeq: rotate
-- OBP1 right by one colour slot every 16 frames until it reaches its final
-- state, then leave it alone.
function GameFreakPresents:updateLogoPal()
  if not self.logoAlive then return end
  if self.obp1 == OBP1_FINAL then return end
  if self.timer % 16 ~= 0 then return end
  local low = self.obp1 % 4
  self.obp1 = math.floor(self.obp1 / 4) + low * 64
end

function GameFreakPresents:update(_dt)
  self.frames = self.frames + 1
  -- The 16-frame tail after the sequence finishes or is skipped.
  if self.exitTail then
    self.exitTail = self.exitTail + 1
    if self.exitTail > EXIT_FRAMES then self:finish() end
    return
  end
  local input = self.game and self.game.input
  if input and (input:wasPressed("a") or input:wasPressed("b")
      or input:wasPressed("start") or input:wasPressed("select")) then
    -- .pressed_button: everything is torn down and the splash is over.
    self.skipped = true
    self:beginExit()
    return
  end
  self.anims:playFrame()
  self:updateLogoPal()
  local scene = SCENES[self.scene + 1]
  if scene then scene(self) end
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

function GameFreakPresents:sheetFor(tile)
  for _, sheet in ipairs(self.sheets) do
    if tile >= sheet.firstTile and sheet:available() then
      local index = tile - sheet.firstTile
      local image = sheet:image()
      local _, height = image:getDimensions()
      if index < sheet.wide * (height / 8) then return sheet end
    end
  end
  return nil
end

function GameFreakPresents:drawTile(tile, tx, ty, colors)
  local sheet = self:sheetFor(tile)
  if not sheet then return end
  sheet.palette = colors
  sheet:draw(tile, tx, ty)
end

-- One pass over wShadowOAM.  The palette is the OAM attribute's low bits:
-- slot 1 is the logo, on the OBP1 that rotates, and everything else is the
-- fixed OBP0 the star and sparkles share.
function GameFreakPresents:drawObjects()
  local G = love.graphics
  local logoPal = permute(self.obColors, self.obp1)
  local objPal = permute(self.obColors, OBP0)
  local oam = self.anims.oam
  for index = #oam, 1, -1 do
    local entry = oam[index]
    -- OBJ palette 1 is the logo and nothing else.
    local isLogo = entry.attr % 8 == 1
    local sheet = self:sheetFor(entry.tile)
    local quad = sheet and sheet:quad(entry.tile - sheet.firstTile)
    if quad then
      local flipX = math.floor(entry.attr / SpriteAnims.OAM_XFLIP) % 2 == 1
      local flipY = math.floor(entry.attr / SpriteAnims.OAM_YFLIP) % 2 == 1
      local colors = isLogo and logoPal or objPal
      local function body()
        G.setColor(1, 1, 1, 1)
        G.draw(sheet:image(), quad,
          entry.x - 8 + (flipX and 8 or 0), entry.y - 16 + (flipY and 8 or 0),
          0, flipX and -1 or 1, flipY and -1 or 1)
      end
      if GbcPalette.available() then
        GbcPalette.with(colors, body)
      else
        body()
      end
    end
  end
end

function GameFreakPresents:drawPanel()
  local G = love.graphics
  -- BG colour 0 is the backdrop the cleared tilemap shows.
  local backdrop = GbcPalette.color(self.bgColors, 1) or BLACK
  G.setColor(backdrop[1] / 255, backdrop[2] / 255, backdrop[3] / 255, 1)
  G.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
  G.setColor(1, 1, 1, 1)
  for ty, row in pairs(self.tiles) do
    for tx, tile in pairs(row) do
      self:drawTile(tile, tx, ty, self.bgColors)
    end
  end
  self:drawObjects()
  G.setColor(1, 1, 1, 1)
end

function GameFreakPresents:draw()
  self:drawPanel()
end

function GameFreakPresents:drawWidescreen(winW, winH)
  local G = love.graphics
  local backdrop = GbcPalette.color(self.bgColors, 1) or BLACK
  G.setColor(backdrop[1] / 255, backdrop[2] / 255, backdrop[3] / 255, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

GameFreakPresents.SPARKLE_VECTORS = SPARKLE_VECTORS
GameFreakPresents.permute = permute

return GameFreakPresents
