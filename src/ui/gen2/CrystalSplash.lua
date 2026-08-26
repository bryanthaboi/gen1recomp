-- The Crystal GAME FREAK splash (pokecrystal engine/movie/splash.asm:1-342):
-- Ditto bounces in, rests, transforms into the logo, then GAME FREAK / presents.

local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Music = require("src.core.Music")
local Runtime = require("src.mods.Runtime")
local Sound = require("src.core.Sound")
local SpriteAnims = require("src.ui.gen2.SpriteAnims")
local TileSheet = require("src.ui.gen2.TileSheet")

local CrystalSplash = {}
CrystalSplash.__index = CrystalSplash
CrystalSplash.isOpaque = true

local SCREEN_W, SCREEN_H = 160, 144

-- splash.asm:91 `depixel 10, 11, 4, 0` is y-first: x=e, y=d
-- (pokecrystal engine/sprite_anims/core.asm:113).
local LOGO_X, LOGO_Y = 11 * 8 + 0, 10 * 8 + 4
-- pokecrystal constants/gfx_constants.asm:36 OAM_YCOORD_HIDDEN.
local YCOORD_HIDDEN = 160

-- splash.asm:161-164 and :183-186; tile $0d is the logo's own first tile
-- borrowed as the space.
local GAME_FREAK = { 0x00, 0x01, 0x02, 0x03, 0x0d, 0x04, 0x05, 0x03, 0x01, 0x06 }
local GAME_FREAK_X, GAME_FREAK_Y = 5, 10
local PRESENTS = { 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c }
local PRESENTS_X, PRESENTS_Y = 7, 11

-- splash.asm:121-122 `ld c, 16 / call DelayFrames`.
local EXIT_FRAMES = 16

local BLACK = { 0, 0, 0 }
local WHITE = { 255, 255, 255 }

-- pokecrystal gfx/splash/ditto.pal, loaded into OBJ pals 0 and 1 by
-- _CGB_GamefreakLogo (engine/gfx/cgb_layouts.asm:876-893).
local DITTO_OB = { WHITE, { 107, 90, 0 }, { 189, 99, 230 }, BLACK }
-- pokecrystal gfx/sgb/predef.pal:79 PREDEFPAL_GAMEFREAK_LOGO_BG.
local DEFAULT_BG = { BLACK, { 66, 90, 90 }, { 173, 173, 173 }, WHITE }

--------------------------------------------------------------------------
-- Sprite-anim data, registered into SpriteAnims' shared tables
--------------------------------------------------------------------------

-- dbsprite (pokecrystal macros/gfx.asm): y byte first.
local function s(xTile, yTile, xPixel, yPixel, tile, attr)
  return {
    y = (yTile * 8 + yPixel) % 256,
    x = (xTile * 8 + xPixel) % 256,
    tile = tile,
    attr = attr,
  }
end

-- pokecrystal data/sprite_anims/oam.asm:1098-1108 .OAMData_GameFreakLogo1_3.
local DITTO_SMALL = {}
for row = 0, 2 do
  for col = 0, 2 do
    DITTO_SMALL[#DITTO_SMALL + 1] =
      s(col - 2, row - 2, 4, 0, row * 0x10 + col, 1)
  end
end

-- pokecrystal data/sprite_anims/oam.asm:1110-1135 .OAMData_GameFreakLogo4_11.
local DITTO_MORPH = {}
for row = 0, 5 do
  for col = 0, 3 do
    DITTO_MORPH[#DITTO_MORPH + 1] =
      s(col - 2, row - 5, 4, 0, row * 0x10 + col, 1)
  end
end

-- pokecrystal data/sprite_anims/oam.asm:139-149: vtile bases into the
-- 256-tile Ditto sheet GameFreakPresentsInit loads whole (splash.asm:72-85).
local OAMSETS = {
  CRYSTAL_GAMEFREAK_LOGO_1 = { 0xd0, DITTO_SMALL },
  CRYSTAL_GAMEFREAK_LOGO_2 = { 0xd3, DITTO_SMALL },
  CRYSTAL_GAMEFREAK_LOGO_3 = { 0xd6, DITTO_SMALL },
  CRYSTAL_GAMEFREAK_LOGO_4 = { 0x6c, DITTO_MORPH },
  CRYSTAL_GAMEFREAK_LOGO_5 = { 0x68, DITTO_MORPH },
  CRYSTAL_GAMEFREAK_LOGO_6 = { 0x64, DITTO_MORPH },
  CRYSTAL_GAMEFREAK_LOGO_7 = { 0x60, DITTO_MORPH },
  CRYSTAL_GAMEFREAK_LOGO_8 = { 0x0c, DITTO_MORPH },
  CRYSTAL_GAMEFREAK_LOGO_9 = { 0x08, DITTO_MORPH },
  CRYSTAL_GAMEFREAK_LOGO_10 = { 0x04, DITTO_MORPH },
  CRYSTAL_GAMEFREAK_LOGO_11 = { 0x00, DITTO_MORPH },
}

local function f(oamset, duration, flags)
  return { oamset = oamset, duration = duration, flags = flags or 0 }
end

-- pokecrystal data/sprite_anims/framesets.asm:142-158 .Frameset_GameFreakLogo.
local FRAMESETS = {
  CrystalGameFreakLogo = {
    f("CRYSTAL_GAMEFREAK_LOGO_1", 12), f("CRYSTAL_GAMEFREAK_LOGO_2", 1),
    f("CRYSTAL_GAMEFREAK_LOGO_3", 1), f("CRYSTAL_GAMEFREAK_LOGO_2", 4),
    f("CRYSTAL_GAMEFREAK_LOGO_1", 12), f("CRYSTAL_GAMEFREAK_LOGO_2", 12),
    f("CRYSTAL_GAMEFREAK_LOGO_3", 4), f("CRYSTAL_GAMEFREAK_LOGO_4", 32),
    f("CRYSTAL_GAMEFREAK_LOGO_5", 3), f("CRYSTAL_GAMEFREAK_LOGO_6", 3),
    f("CRYSTAL_GAMEFREAK_LOGO_7", 4), f("CRYSTAL_GAMEFREAK_LOGO_8", 4),
    f("CRYSTAL_GAMEFREAK_LOGO_9", 4), f("CRYSTAL_GAMEFREAK_LOGO_10", 10),
    f("CRYSTAL_GAMEFREAK_LOGO_11", 7),
    "end",
  },
}

local SEQUENCES = {}

-- GameFreakLogoSpriteAnim (splash.asm:201-342): VAR1 jump height, VAR2 sine
-- offset / frame counter; sys.flag carries the transform's NextScene call.
SEQUENCES.CrystalGameFreakLogo = function(sys, st)
  local splash = sys.splash
  if st.jt == 0 then
    -- GameFreakLogo_Init (splash.asm:221-225).
    st.jt = 1
  elseif st.jt == 1 then
    -- GameFreakLogo_Bounce (splash.asm:227-283).
    if st.var1 == 0 then
      st.jt = 2
      st.var2 = 0
      if splash then splash:playSfx("Sfx_DittoPopUp") end
      return
    end
    local angle = st.var2 % 0x40
    if angle < 32 then angle = angle + 32 end
    st.yOffset = SpriteAnims.sine(angle, st.var1)
    local before = st.var2
    st.var2 = (st.var2 - 1) % 256
    if before % 0x20 == 0 then
      st.var1 = (st.var1 - 48) % 256
      if splash then splash:playSfx("Sfx_DittoBounce") end
    end
  elseif st.jt == 2 then
    -- GameFreakLogo_Ditto (splash.asm:285-304).
    if st.var2 >= 32 then
      st.jt = 3
      st.var2 = 0
      if splash then splash:playSfx("Sfx_DittoTransform") end
    else
      st.var2 = st.var2 + 1
    end
  elseif st.jt == 3 then
    -- GameFreakLogo_Transform (splash.asm:306-340).
    if st.var2 == 64 then
      st.jt = 4
      sys.flag = 1
    else
      local step = math.floor(st.var2 / 4)
      st.var2 = st.var2 + 1
      if splash then splash:fadeTo(step) end
    end
  end
end

-- pokecrystal data/sprite_anims/objects.asm:11-12 SPRITE_ANIM_OBJ_GAMEFREAK_LOGO.
local OBJECTS = {
  CRYSTAL_GAMEFREAK_LOGO = { "CrystalGameFreakLogo", "CrystalGameFreakLogo" },
}

local function register(target, entries)
  for name, value in pairs(entries) do
    if target[name] == nil then target[name] = value end
  end
end

register(SpriteAnims.OAMSETS, OAMSETS)
register(SpriteAnims.FRAMESETS, FRAMESETS)
register(SpriteAnims.OBJECTS, OBJECTS)
register(SpriteAnims.SEQUENCES, SEQUENCES)

--------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------

function CrystalSplash:wantsFillScale() return true end
function CrystalSplash:drawsWidescreen() return true end

-- opts: oakSpeech (data/generated/oak_speech.lua, for its `splash` table),
-- onDone(skipped)
function CrystalSplash.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, CrystalSplash)
  self.game = game
  self.onDone = opts.onDone
  local splash = (opts.oakSpeech or {}).splash or {}
  local ob = splash.dittoPalette or DITTO_OB
  self.obColors = { ob[1], ob[2], ob[3], ob[4] }
  self.bgColors = splash.bgPalette or DEFAULT_BG
  self.dittoFade = splash.dittoFade

  -- GameFreakLogoGFX's 28 1bpp tiles land at vTiles2 $00 (splash.asm:62-65):
  -- letters $00-$0c, the 3x5 logo $0d-$1b.
  self.sheets = {
    TileSheet.new({ path = splash.presents
      or "assets/generated/splash/presents.png", wide = 13, firstTile = 0x00 }),
    TileSheet.new({ path = splash.logo
      or "assets/generated/splash/logo.png", wide = 3, firstTile = 0x0d }),
  }
  self.ditto = TileSheet.new({ path = splash.ditto
    or "assets/generated/splash/ditto.png",
    wide = splash.dittoTilesWide or 16, firstTile = 0x00 })

  self.anims = SpriteAnims.new()
  self.anims.splash = self
  -- splash.asm:91-102: spawn hidden, VAR1=96, VAR2=48.
  local st = self.anims:init("CRYSTAL_GAMEFREAK_LOGO", LOGO_X, LOGO_Y)
  if st then
    st.yOffset = YCOORD_HIDDEN
    st.var1 = 96
    st.var2 = 48
  end

  self.scene = 0
  self.timer = 0
  self.tiles = {} -- the BG tilemap, sparse: [y][x] = tile id
  self.frames = 0
  self.exitTail = nil
  self.done = false
  self.skipped = nil
  return self
end

function CrystalSplash:enter()
  local data = self.game and self.game.data
  if data and data.audio and data.audio.runtime then
    Music.stop()
  end
  if Runtime.wants("intro.boot.gamefreak") then
    Runtime.emit("intro.boot.gamefreak", { screen = self, game = self.game })
  end
end

function CrystalSplash:finish()
  if self.done then return end
  self.done = true
  if self.onDone then self.onDone(self.skipped) end
end

function CrystalSplash:playSfx(name)
  local data = self.game and self.game.data
  if data and data.audio and data.audio.sfx and data.audio.sfx[name] then
    Sound.play(data, name)
  end
end

-- The transform walks OBJ pal 1 colour 2 down GameFreakDittoPaletteFade
-- (splash.asm:306-334, gfx/splash/ditto_fade.pal).
function CrystalSplash:fadeTo(step)
  local fade = self.dittoFade
  local color = fade and fade[step + 1]
  if color then self.obColors[3] = color end
end

function CrystalSplash:placeString(tiles, tx, ty)
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
-- GameFreakPresentsScene (splash.asm:125-199)
--------------------------------------------------------------------------

function CrystalSplash:sceneWaitSpriteAnim()
  if self.anims.flag == 0 then return end
  self.scene = 1
  self.timer = 0
end

function CrystalSplash:scenePlaceGameFreak()
  if self.timer < 32 then
    self.timer = self.timer + 1
    return
  end
  self.timer = 0
  self:placeString(GAME_FREAK, GAME_FREAK_X, GAME_FREAK_Y)
  self.scene = 2
  self:playSfx("Sfx_GameFreakPresents")
end

function CrystalSplash:scenePlacePresents()
  if self.timer < 64 then
    self.timer = self.timer + 1
    return
  end
  self.timer = 0
  self:placeString(PRESENTS, PRESENTS_X, PRESENTS_Y)
  self.scene = 3
end

function CrystalSplash:sceneWaitForTimer()
  if self.timer < 128 then
    self.timer = self.timer + 1
    return
  end
  self:beginExit()
end

local SCENES = {
  CrystalSplash.sceneWaitSpriteAnim,
  CrystalSplash.scenePlaceGameFreak,
  CrystalSplash.scenePlacePresents,
  CrystalSplash.sceneWaitForTimer,
}

-- GameFreakPresentsEnd (splash.asm:117-123).
function CrystalSplash:beginExit()
  if self.exitTail then return end
  self.anims:clear()
  self.tiles = {}
  self.exitTail = 0
end

function CrystalSplash:update(_dt)
  self.frames = self.frames + 1
  if self.exitTail then
    self.exitTail = self.exitTail + 1
    if self.exitTail > EXIT_FRAMES then self:finish() end
    return
  end
  local input = self.game and self.game.input
  if input and (input:wasPressed("a") or input:wasPressed("b")
      or input:wasPressed("start") or input:wasPressed("select")) then
    -- SplashScreen.pressed_button (splash.asm:51-54) returns carry.
    self.skipped = true
    self:beginExit()
    return
  end
  local scene = SCENES[self.scene + 1]
  if scene then scene(self) end
  self.anims:playFrame()
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

function CrystalSplash:sheetFor(tile)
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

function CrystalSplash:drawTile(tile, tx, ty, colors)
  local sheet = self:sheetFor(tile)
  if not sheet then return end
  sheet.palette = colors
  sheet:draw(tile, tx, ty)
end

function CrystalSplash:drawObjects()
  local G = love.graphics
  local sheet = self.ditto
  if not sheet:available() then return end
  local oam = self.anims.oam
  for index = #oam, 1, -1 do
    local entry = oam[index]
    local quad = sheet:quad(entry.tile)
    if quad then
      local flipX = math.floor(entry.attr / SpriteAnims.OAM_XFLIP) % 2 == 1
      local flipY = math.floor(entry.attr / SpriteAnims.OAM_YFLIP) % 2 == 1
      local function body()
        G.setColor(1, 1, 1, 1)
        G.draw(sheet:image(), quad,
          entry.x - 8 + (flipX and 8 or 0), entry.y - 16 + (flipY and 8 or 0),
          0, flipX and -1 or 1, flipY and -1 or 1)
      end
      if GbcPalette.available() then
        GbcPalette.with(self.obColors, body)
      else
        body()
      end
    end
  end
end

function CrystalSplash:drawPanel()
  local G = love.graphics
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

function CrystalSplash:draw()
  self:drawPanel()
end

function CrystalSplash:drawWidescreen(winW, winH)
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

return CrystalSplash
