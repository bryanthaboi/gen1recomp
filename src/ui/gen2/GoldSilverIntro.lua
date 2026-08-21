-- The Gold/Silver intro movie (pokegold engine/movie/intro.asm
-- GoldSilverIntro), transcribed rather than approximated.
--
-- The cart runs the whole thing off one 17-entry jumptable stepped once per
-- frame, and almost everything on screen is a side effect of four bytes:
-- hSCX, hSCY and the two intro frame counters.  So this module keeps those
-- bytes, keeps a real 32x32 BG map, and runs the same scene functions over
-- them.  What that buys is the movement the old timed-fade version had no way
-- to express:
--
--   1-5    underwater.  Shellders drift up out of frame while bubbles rise,
--          then the camera climbs to the surface -- and it climbs by streaming
--          one fresh metatile row into the top of the BG map every 16 pixels
--          (Intro_UpdateTilemapAndBGMap), which is why the act ships a tilemap
--          twice as tall as the map.  Magikarp jump, Lapras surfaces, fade.
--   6-9    grass.  Scroll left to Jigglypuff with notes rising, Pikachu
--          charges in from the right, then the camera drops and fades.
--   10-16  fire.  Climb a black field to the Charizard silhouette while the
--          three Johto starters flash across it, open its mouth in three
--          tilemap redraws, breathe a fireball that spirals outward.
--   17     64 frames of black, then the title screen.
--
-- The ocean's wobble is not a sprite effect: hLCDCPointer points at rSCY and
-- wLYOverrides holds a per-scanline SCY, so the water bends line by line
-- (Intro_InitSineLYOverrides / Intro_UpdateLYOverrides).  That is drawn here
-- as one quad per scanline.
--
-- Any button skips the whole thing, exactly as .PlayFrame does on PAD_BUTTONS.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Logger = require("src.core.Logger")
local Music = require("src.core.Music")
local Palettes = require("src.world.gen2.Palettes")
local Runtime = require("src.mods.Runtime")
local Sound = require("src.core.Sound")
local SpriteAnims = require("src.ui.gen2.SpriteAnims")

local GoldSilverIntro = {}
GoldSilverIntro.__index = GoldSilverIntro
GoldSilverIntro.isOpaque = true

local SCREEN_W, SCREEN_H = 160, 144
local BG_TILES = 32            -- TILEMAP_WIDTH / TILEMAP_HEIGHT
local BG_PIXELS = BG_TILES * 8 -- the BG map wraps every 256 pixels
local META_COLS = 16           -- TILEMAP_WIDTH / 2
local TILEMAP_W, TILEMAP_H = 20, 18 -- SCREEN_WIDTH / SCREEN_HEIGHT

local INTRO_MUSIC = "Music_GoldSilverOpening"
local INTRO_MUSIC_2 = "Music_GoldSilverOpening2"
local SFX_FIREBALL = "Sfx_GsIntroCharizardFireball"
local SFX_APPEARS = "Sfx_GsIntroPokemonAppears"

-- Intro_AnimateOceanWaves' .wave_tiles: four four-tile cycles, each repeated
-- across the whole 32-tile BG row.
local WAVE_TILES = {
  { 0x70, 0x71, 0x72, 0x73 },
  { 0x74, 0x75, 0x76, 0x77 },
  { 0x78, 0x79, 0x7a, 0x7b },
  { 0x7c, 0x7d, 0x7e, 0x7f },
}
-- `vBGMap0 tile $1e` is 480 bytes in, i.e. the whole of BG row 15.
local WAVE_ROW = 15

-- DrawIntroCharizardGraphic .charizard_data: vtile offset, width, height and
-- the tilemap coordinate the rectangle of running tile ids starts at.
local CHARIZARD_GFX = {
  { tile = 0x00, width = 8, height = 8, x = 10, y = 6 }, -- mouth closed
  { tile = 0x40, width = 9, height = 8, x = 9, y = 6 },  -- mouth open
  { tile = 0x88, width = 9, height = 8, x = 8, y = 6 },  -- breathing fire
}

-- IntroScene5 / IntroScene9 / IntroScene12 / IntroScene16 palette ladders.
-- Each is a DMG palette register that DmgToCgbBGPals reorders the loaded CGB
-- colours through, so %11100100 is the identity and %00000000 collapses every
-- shade onto colour 0.
local WATER_FADE = { 0xe4, 0xe4, 0x90, 0x40, 0x00 }
local GRASS_FADE = { 0xe4, 0xe4, 0xe4, 0xe4, 0xe4, 0x90, 0x40, 0x00 }
local CHARIZARD_PALS = { 0x6a, 0xa5, 0xe4, 0x00 }
local FIRE_FADE = { 0xe4, 0x90, 0x40, 0x00 }

-- Intro_CheckSCYEvent .scy_jumptable: the SCY values the fire act's climb
-- fires its palette flashes and starter entrances on.
local SCY_EVENTS = {
  [0x86] = "loadChikorita",
  [0x87] = "chikoritaAppears",
  [0x88] = "flashMonPalette",
  [0x98] = "flashSilhouette",
  [0x99] = "loadCyndaquil",
  [0xaf] = "cyndaquilAppears",
  [0xb0] = "flashMonPalette",
  [0xc0] = "flashSilhouette",
  [0xc1] = "loadTotodile",
  [0xd7] = "totodileAppears",
  [0xd8] = "flashMonPalette",
  [0xe8] = "flashSilhouette",
  [0xe9] = "loadCharizard",
}

local WHITE = { 255, 255, 255 }
local BLACK = { 0, 0, 0 }

--------------------------------------------------------------------------
-- Palette plumbing
--------------------------------------------------------------------------

-- CopyPals: colour i of the displayed palette is colour (reg >> 2i) & 3 of the
-- loaded one.  DmgToCgbBGPals runs it over every BG palette with rBGP and
-- DmgToCgbObjPals over every OBJ palette with rOBP0, which is what makes the
-- fades work without touching the artwork.
local function remap(palette, register)
  local out = {}
  for index = 0, 3 do
    local slot = math.floor(register / 4 ^ index) % 4
    out[index + 1] = (palette and palette[slot + 1]) or BLACK
  end
  return out
end

local function copyPalette(source)
  local out = {}
  for index = 1, 4 do
    local color = source and source[index]
    out[index] = color and { color[1], color[2], color[3] } or BLACK
  end
  return out
end

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

function GoldSilverIntro:wantsFillScale() return true end
function GoldSilverIntro:drawsWidescreen() return true end

function GoldSilverIntro.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, GoldSilverIntro)
  self.game = game
  self.onDone = opts.onDone
  local data = (game and game.data) or {}
  self.monPalettes = data.gen2Palettes
  self.assets = opts.intro or data.gen2Intro or (game and game.introData) or nil
  if not self.assets then
    -- The scene script runs either way, so a cache with no intro.lua plays
    -- the movie's full 2335 frames over an empty screen and reads exactly
    -- like "the intro does not work".  Say so instead: the fix is a
    -- re-import, and nothing else in the boot chain will mention it.
    Logger.warn("gen2 intro: no intro.lua in the cache -- re-import "
      .. "this version or the movie plays blank")
  end
  self.images = {}
  self.sheets = {}

  self.anims = SpriteAnims.new()
  self.scene = 1
  self.done = false
  self.frames = 0

  -- Hardware registers and the movie's own WRAM.
  self.scx, self.scy = 0, 0
  self.counter1, self.counter2 = 0, 0
  self.bgp, self.obp0 = 0xe4, 0xe4
  self.lyActive = false
  self.lyOverrides = {}
  self.lySine = {}
  for line = 1, SCREEN_H do
    self.lyOverrides[line] = 0
    self.lySine[line] = 0
  end

  self.bgPals = { copyPalette(nil) }
  self.obPals = { copyPalette(nil), copyPalette(nil) }
  self.bgmap = {}
  for index = 1, BG_TILES * BG_TILES do self.bgmap[index] = 0 end
  self.tilemap = {}
  for index = 1, TILEMAP_W * TILEMAP_H do self.tilemap[index] = 0 end
  self.act = nil
  self.mapDirty = true
  return self
end

--------------------------------------------------------------------------
-- BG map
--------------------------------------------------------------------------

local function mapGet(self, col, row)
  return self.bgmap[(row % BG_TILES) * BG_TILES + (col % BG_TILES) + 1]
end

local function mapSet(self, col, row, tile)
  self.bgmap[(row % BG_TILES) * BG_TILES + (col % BG_TILES) + 1] = tile
  self.mapDirty = true
end

local function actData(self)
  return self.assets and self.act and self.assets[self.act] or nil
end

-- Intro_Draw2x2Tiles: metatile `index` of the act's table is four tile ids in
-- reading order, laid into the 2x2 block whose top-left corner is (col, row).
local function draw2x2(self, source, index, col, row)
  local meta = source.meta
  for quad = 0, 3 do
    local tile = meta[index * 4 + quad + 1] or 0
    mapSet(self, col + quad % 2, row + math.floor(quad / 2), tile)
  end
end

-- Intro_DrawBackground: 16 metatile rows of 16, starting at tilemap row
-- `firstRow`, laid across the whole BG map from BG row 0.
local function drawBackground(self, source, firstRow)
  for metaRow = 0, BG_TILES / 2 - 1 do
    for metaCol = 0, META_COLS - 1 do
      local index = source.tilemap[(firstRow + metaRow) * META_COLS + metaCol + 1]
      draw2x2(self, source, index or 0, metaCol * 2, metaRow * 2)
    end
  end
end

-- Intro_UpdateTilemapAndBGMap: step the tilemap pointer back one metatile row
-- and the BG pointer back two tile rows, then draw the new row in at the top
-- of the map -- which, because the map wraps, is the row that just scrolled
-- off the bottom.  It also ticks counter1 down, and that counter is what ends
-- the climb.
local function updateTilemapAndBGMap(self, source)
  self.tilemapRow = self.tilemapRow - 1
  self.bgRow = (self.bgRow - 2) % BG_TILES
  for metaCol = 0, META_COLS - 1 do
    local index = source.tilemap[self.tilemapRow * META_COLS + metaCol + 1]
    draw2x2(self, source, index or 0, metaCol * 2, self.bgRow)
  end
  self.counter1 = (self.counter1 - 1) % 256
end

-- Intro_AnimateOceanWaves.  Real hardware queues this as a 2bpp request that
-- lands in the next VBlank; there is no queue here, so the row changes on the
-- frame that asks for it.
local function animateOceanWaves(self)
  if self.counter2 % 4 == 3 then return end
  local cycle = WAVE_TILES[math.floor(self.counter2 % 0x40 / 0x10) + 1]
  for col = 0, BG_TILES - 1 do
    mapSet(self, col, WAVE_ROW, cycle[col % 4 + 1])
  end
end

--------------------------------------------------------------------------
-- LY overrides
--------------------------------------------------------------------------

-- Intro_InitSineLYOverrides fills a 144-entry table with sin(line * pi/32) at
-- amplitude 4; Intro_UpdateLYOverrides then rotates that table by one entry a
-- frame and adds hSCY, so the wave travels down the screen.  The top 16
-- scanlines are held flat at hSCY.
local function initSineLYOverrides(self)
  for line = 0, SCREEN_H - 1 do
    self.lySine[line + 1] = SpriteAnims.sine(line, 4)
  end
end

local function resetLYOverrides(self)
  for line = 1, SCREEN_H do self.lyOverrides[line] = 0 end
  self.lyActive = false
end

local function updateLYOverrides(self)
  for line = 1, 16 do self.lyOverrides[line] = self.scy end
  local first = self.lySine[1]
  for offset = 0, 0x7f do
    local value = self.lySine[offset + 2]
    self.lySine[offset + 1] = value
    self.lyOverrides[17 + offset] = (value + self.scy) % 256
  end
  self.lySine[0x81] = first
end

--------------------------------------------------------------------------
-- Audio
--------------------------------------------------------------------------

function GoldSilverIntro:playMusic(song)
  local data = self.game and self.game.data
  local audio = data and data.audio
  if audio and audio.runtime and audio.songs and audio.songs[song] then
    Music.play(data, song)
  end
end

function GoldSilverIntro:playSfx(name)
  local data = self.game and self.game.data
  local audio = data and data.audio
  if audio and audio.runtime and audio.sfx and audio.sfx[name] then
    Sound.play(data, name)
  end
end

--------------------------------------------------------------------------
-- Scenes
--------------------------------------------------------------------------

local Scenes = {}

-- IntroScene1: set up the water cutscene.
Scenes[1] = function(self)
  self.scene = 2
  self.act = "water"
  local source = actData(self)
  if source then
    self.tilemapRow = source.firstRow or 15
    self.bgRow = 0
    drawBackground(self, source, self.tilemapRow)
  end
  self.anims:clear()
  self.scy = 0
  self.anims.globalY, self.anims.globalX = 0, 0
  self.scx = 0x58
  self.counter2 = 0
  self.counter1 = 0x80
  self.lyActive = true
  initSineLYOverrides(self)
  self.anims.flag = 0

  -- GetSGBLayout SCGB_GS_INTRO 0 -> _CGB_GSIntro.ShellderLaprasScene.
  local palettes = self.assets and self.assets.palettes or {}
  self.bgPals[1] = copyPalette(palettes.waterBg)
  self.obPals[1] = copyPalette(palettes.waterOb and palettes.waterOb[1])
  self.obPals[2] = copyPalette(palettes.waterOb and palettes.waterOb[2])
  self.bgp, self.obp0 = 0xe4, 0xe4

  -- Intro_InitShellders.
  self.anims:init("GS_INTRO_SHELLDER", 7 * 8, 18 * 8)
  self.anims:init("GS_INTRO_SHELLDER", 10 * 8, 14 * 8)
  self.anims:init("GS_INTRO_SHELLDER", 15 * 8, 16 * 8)
  self:playMusic(INTRO_MUSIC)
end

-- Intro_InitBubble .pixel_table, as {x, y} pairs.  The counter picks a slot
-- 0-7 out of a six-entry table, so on hardware two of the nine bubbles read
-- past its end and surface at whatever the following code bytes say; those two
-- are dropped here rather than reproduced.
local BUBBLE_SPOTS = {
  { 6 * 8, 14 * 8 + 4 }, { 14 * 8, 18 * 8 + 4 }, { 10 * 8, 16 * 8 + 4 },
  { 12 * 8, 15 * 8 }, { 4 * 8, 13 * 8 }, { 8 * 8, 17 * 8 },
}

local function initBubble(self)
  if self.counter1 % 16 ~= 0 then return end
  local spot = BUBBLE_SPOTS[math.floor(self.counter1 % 0x80 / 0x10) + 1]
  if not spot then return end
  self.anims:init("GS_INTRO_BUBBLE", spot[1], spot[2])
end

-- IntroScene2: Shellders drift, bubbles rise, for $80 frames.
Scenes[2] = function(self)
  updateLYOverrides(self)
  if self.counter1 ~= 0 then
    self.counter1 = self.counter1 - 1
    initBubble(self)
    return
  end
  self.counter1 = 0x10
  self.scene = 3
  return Scenes[3](self)
end

-- Intro_InitMagikarps: three at once, alternating between two sets of spots
-- every 64 frames.  Its rate and phase masks come out of a `depixel` used as a
-- pair of constants (8, 7 -> $40 and $3f).
local MAGIKARP_SPOTS = {
  { { 28 * 8, 29 * 8 }, { 0 * 8, 26 * 8 }, { 24 * 8, 0 * 8 } },
  { { 30 * 8, 28 * 8 }, { 24 * 8, 31 * 8 }, { 28 * 8, 2 * 8 } },
}

local function initMagikarps(self)
  if self.counter2 % 0x40 ~= 0 then return end
  local set = MAGIKARP_SPOTS[self.counter2 % 0x80 ~= 0 and 2 or 1]
  for _, spot in ipairs(set) do
    self.anims:init("GS_INTRO_MAGIKARP", spot[1], spot[2])
  end
end

local function initLapras(self)
  if self.counter2 % 0x20 ~= 0 then return end
  self.anims:init("GS_INTRO_LAPRAS", 24 * 8, 16 * 8)
end

-- IntroScene3_Jumper's 17 entries, indexed by counter1 -- which counts the
-- remaining metatile rows down from $10, so this table reads bottom-up: the
-- wobble runs while the camera is still deep, then Magikarp jump, then Lapras
-- arrives just before the surface.
local SCENE3_STEPS = {
  [0] = "waves", "waves", "waves", "lapras", "waves", "waves",
  "magikarp", "magikarp", "magikarp", "palettes", "noLY",
  "ly", "ly", "ly", "ly", "ly", "ly",
}

local function scene3Jumper(self)
  local step = SCENE3_STEPS[self.counter1]
  if step == "lapras" then
    initLapras(self)
    self.obp0 = 0xe4 -- DmgToCgbObjPals with depixel 28, 28, 4, 4
    animateOceanWaves(self)
  elseif step == "waves" then
    animateOceanWaves(self)
  elseif step == "magikarp" then
    initMagikarps(self)
    animateOceanWaves(self)
  elseif step == "palettes" then
    if self.counter2 % 0x20 == 0 then
      -- Intro_LoadMagikarpPalettes swaps in the school's own colours.
      local palettes = self.assets and self.assets.palettes or {}
      self.bgPals[1] = copyPalette(palettes.magikarpBg)
      self.obPals[1] = copyPalette(palettes.magikarpOb)
    else
      initMagikarps(self)
    end
  elseif step == "noLY" then
    self.lyActive = false
  elseif step == "ly" then
    updateLYOverrides(self)
  end
end

-- IntroScene3_ScrollToSurface: hSCX creeps left a quarter as fast as the climb,
-- hSCY steps up every other frame, and a new metatile row streams in every 16
-- pixels.  Carry (the act ending) is counter1 reaching zero.
local function scrollToSurface(self)
  self.counter2 = (self.counter2 + 1) % 256
  if self.counter2 % 4 == 0 then
    self.scx = (self.scx - 1) % 256
  end
  if self.counter2 % 2 ~= 0 then return false end
  self.anims.globalY = (self.anims.globalY + 1) % 256
  local before = self.scy
  self.scy = (self.scy - 1) % 256
  if before % 16 == 0 then
    local source = actData(self)
    if source then updateTilemapAndBGMap(self, source) end
  end
  return self.counter1 == 0
end

-- IntroScene3: rise towards the surface.
Scenes[3] = function(self)
  scene3Jumper(self)
  if not scrollToSurface(self) then return end
  resetLYOverrides(self)
  self.scy = (self.scy + 1) % 256
  self.scene = 4
  return Scenes[4](self)
end

-- IntroScene4: at the surface; hold until Lapras has swum off to the left.
Scenes[4] = function(self)
  if self.anims.flag == 0 then
    self.counter2 = (self.counter2 + 1) % 256
    if self.counter2 % 16 == 0 then
      self.scx = (self.scx - 2) % 256
    end
    animateOceanWaves(self)
    return
  end
  self.scene = 5
  self.counter1 = 0
  return Scenes[5](self)
end

-- IntroScene5: fade out, one palette step every 16 frames.
Scenes[5] = function(self)
  local step = math.floor(self.counter1 / 16) + 1
  self.counter1 = (self.counter1 + 1) % 256
  local palette = WATER_FADE[step]
  if not palette then
    self.scene = 6
    return
  end
  self.bgp = palette
  animateOceanWaves(self)
  self.scx = (self.scx - 2) % 256
end

-- IntroScene6: set up the grass cutscene.
Scenes[6] = function(self)
  self.scene = 7
  self.act = "grass"
  self.anims:clear()
  resetLYOverrides(self)
  local source = actData(self)
  if source then
    self.tilemapRow = source.firstRow or 0
    self.bgRow = 0
    drawBackground(self, source, self.tilemapRow)
  end
  self.scy = 0
  self.anims.globalY = 0
  self.scx = 0x60
  self.anims.globalX = 0xa0
  self.counter2 = 0

  local palettes = self.assets and self.assets.palettes or {}
  self.bgPals[1] = copyPalette(palettes.grassBg)
  self.obPals[1] = copyPalette(palettes.grassOb)
  self.obPals[2] = copyPalette(palettes.grassOb)
  self.bgp, self.obp0 = 0xe4, 0xe4

  -- Intro_InitJigglypuff.
  self.anims:init("GS_INTRO_JIGGLYPUFF", 6 * 8, 14 * 8)
  self.anims.flag = 0
end

-- Intro_InitNote: one note every 64 frames, and every other one is the
-- invisible variant that only leaves the little sparkle tile.
local function initNote(self)
  if self.anims.flag ~= 0 then return end
  if self.counter2 % 0x40 ~= 0 then return end
  if self.counter2 % 0x80 ~= 0 then
    self.anims:init("GS_INTRO_NOTE", 6 * 8, 11 * 8 + 4)
  else
    self.anims:init("GS_INTRO_INVISIBLE_NOTE", 6 * 8, 10 * 8 + 4)
  end
end

-- IntroScene7: scroll left to Jigglypuff.  wGlobalAnimXOffset counts up as
-- hSCX counts down so the sprites hold still while the field slides.
Scenes[7] = function(self)
  initNote(self)
  local before = self.counter2
  self.counter2 = (self.counter2 + 1) % 256
  -- `and 3 / ret z`: the camera holds still one frame in four.
  if before % 4 == 0 then return end
  if self.scx ~= 0 then
    self.scx = self.scx - 1
    self.anims.globalX = (self.anims.globalX + 1) % 256
    return
  end
  self.counter1 = 0xff
  -- Intro_InitPikachu: body and tail are two objects at the same spot.
  self.anims:init("GS_INTRO_PIKACHU", 24 * 8, 14 * 8)
  self.anims:init("GS_INTRO_PIKACHU_TAIL", 24 * 8, 14 * 8)
  self.scene = 8
end

-- IntroScene8: stop scrolling; Pikachu runs in and attacks.
Scenes[8] = function(self)
  if self.counter1 ~= 0 then
    self.counter1 = self.counter1 - 1
    initNote(self)
    self.counter2 = (self.counter2 + 1) % 256
    return
  end
  self.counter1 = 0
  self.scene = 9
end

-- IntroScene9: scroll down and fade, one palette step every 8 frames.
Scenes[9] = function(self)
  local step = math.floor(self.counter1 / 8) + 1
  self.counter1 = (self.counter1 + 1) % 256
  local palette = GRASS_FADE[step]
  if not palette then
    self.scene = 10
    return
  end
  self.bgp = palette
  self.scy = (self.scy + 1) % 256
  self.anims.globalY = (self.anims.globalY - 1) % 256
end

-- DrawIntroCharizardGraphic: wipe tilemap rows 6-13, then fill a rectangle
-- with running tile ids and push the tilemap to the BG map.
local function drawCharizard(self, stage)
  for row = 6, 13 do
    for col = 0, TILEMAP_W - 1 do
      self.tilemap[row * TILEMAP_W + col + 1] = 0
    end
  end
  local gfx = CHARIZARD_GFX[stage + 1]
  local tile = gfx.tile
  for row = 0, gfx.height - 1 do
    for col = 0, gfx.width - 1 do
      self.tilemap[(gfx.y + row) * TILEMAP_W + gfx.x + col + 1] = tile % 256
      tile = tile + 1
    end
  end
  for row = 0, TILEMAP_H - 1 do
    for col = 0, TILEMAP_W - 1 do
      mapSet(self, col, row, self.tilemap[row * TILEMAP_W + col + 1])
    end
  end
end

-- IntroScene10: set up the fireball cutscene.
Scenes[10] = function(self)
  self.scene = 11
  self.act = "fire"
  self.anims:clear()
  resetLYOverrides(self)
  for index = 1, BG_TILES * BG_TILES do self.bgmap[index] = 0 end
  for index = 1, TILEMAP_W * TILEMAP_H do self.tilemap[index] = 0 end
  self.mapDirty = true
  drawCharizard(self, 0)

  self.scy = 0x80
  self.scx = 0
  self.anims.globalY, self.anims.globalX = 0, 0
  self.counter2 = 0

  local palettes = self.assets and self.assets.palettes or {}
  self.bgPals[1] = copyPalette(palettes.fireBg and palettes.fireBg[1])
  self.obPals[1] = copyPalette(palettes.startersOb)
  self.obPals[2] = copyPalette(palettes.startersOb)
  -- %00111111 paints the silhouette flat: every shade takes colour 3.
  self.bgp = 0x3f
  self.obp0 = 0xff
  self:playMusic(INTRO_MUSIC_2)
end

local function monColors(self, species)
  return self.monPalettes and Palettes.monColors(self.monPalettes, species)
    or nil
end

-- Intro_LoadMonPalette (CGB): white, the mon's two colours, black, into OBJ
-- palette 0.  Intro_LoadCharizardPalette deliberately uses Cyndaquil's on a
-- CGB and only reaches for Charizard's on a DMG.
local function loadMonPalette(self, species)
  local colors = monColors(self, species)
  if not colors then return end
  self.obPals[1] = { WHITE, colors[2] or BLACK, colors[3] or BLACK, BLACK }
end

local SCY_HANDLERS = {
  loadChikorita = function(self) loadMonPalette(self, "CHIKORITA") end,
  loadCyndaquil = function(self) loadMonPalette(self, "CYNDAQUIL") end,
  loadTotodile = function(self) loadMonPalette(self, "TOTODILE") end,
  loadCharizard = function(self) loadMonPalette(self, "CYNDAQUIL") end,
  chikoritaAppears = function(self)
    self:playSfx(SFX_APPEARS)
    self.anims:init("GS_INTRO_CHIKORITA", 1 * 8, 22 * 8)
  end,
  cyndaquilAppears = function(self)
    self:playSfx(SFX_APPEARS)
    self.anims:init("GS_INTRO_CYNDAQUIL", 20 * 8, 22 * 8)
  end,
  totodileAppears = function(self)
    self:playSfx(SFX_APPEARS)
    self.anims:init("GS_INTRO_TOTODILE", 1 * 8, 22 * 8)
  end,
  -- Intro_FlashMonPalette shows the starter and blacks the silhouette out;
  -- Intro_FlashSilhouette does the reverse.
  flashMonPalette = function(self)
    self.obp0 = 0xe4
    self.bgp = 0x00
  end,
  flashSilhouette = function(self)
    self.obp0 = 0xff
    self.bgp = 0x3f
  end,
}

-- IntroScene11: climb to the silhouette, every other frame, firing the events
-- above as hSCY passes them.
Scenes[11] = function(self)
  local before = self.counter2
  self.counter2 = (self.counter2 + 1) % 256
  if before % 2 == 0 then return end
  local handler = SCY_HANDLERS[SCY_EVENTS[self.scy] or ""]
  if handler then handler(self) end
  if self.scy ~= 0 then
    self.scy = (self.scy + 1) % 256
    return
  end
  self.scene = 12
  self.counter1 = 0
  return Scenes[12](self)
end

-- IntroScene12: four Charizard palettes, four frames apiece, ending on the
-- one that reads as $00 and moves the scene on.
Scenes[12] = function(self)
  local step = math.floor(self.counter1 / 4) % 4 + 1
  self.counter1 = (self.counter1 + 1) % 256
  local palette = CHARIZARD_PALS[step]
  if palette == 0 then
    self.scene = 13
    self.counter1 = 0x80
    return
  end
  self.bgp = palette
  self.obp0 = palette
end

-- IntroScene13: hold, then open the mouth.
Scenes[13] = function(self)
  if self.counter1 ~= 0 then
    self.counter1 = self.counter1 - 1
    return
  end
  self.scene = 14
  drawCharizard(self, 1)
  self.counter1 = 4
end

-- IntroScene14: hold four frames, then breathe.
Scenes[14] = function(self)
  if self.counter1 ~= 0 then
    self.counter1 = self.counter1 - 1
    return
  end
  self.scene = 15
  drawCharizard(self, 2)
  self.counter1 = 64
  self.counter2 = 0
  self:playSfx(SFX_FIREBALL)
  return Scenes[15](self)
end

-- Intro_AnimateFireball: a new fireball every 4 frames, each one leaving the
-- mouth on its own angle, while the field slides left underneath them.
local function animateFireball(self)
  local before = self.counter2
  self.counter2 = (self.counter2 + 1) % 256
  if before % 4 ~= 0 then return end
  self.anims:init("GS_INTRO_FIREBALL", 10 * 8 + 4, 12 * 8 + 4)
  self.scx = (self.scx - 1) % 256
  self.anims.globalX = (self.anims.globalX + 1) % 256
end

-- IntroScene15: 64 frames of fireball.
Scenes[15] = function(self)
  animateFireball(self)
  if self.counter1 ~= 0 then
    self.counter1 = self.counter1 - 1
    return
  end
  self.scene = 16
  self.counter1 = 0
end

-- IntroScene16: keep the fireball going while the palettes fade out.
Scenes[16] = function(self)
  animateFireball(self)
  local step = math.floor(self.counter1 / 16) % 8 + 1
  self.counter1 = (self.counter1 + 1) % 256
  local palette = FIRE_FADE[step]
  if not palette then
    self.scene = 17
    self.hold = 0
    return
  end
  self.bgp = palette
  self.obp0 = palette
end

-- IntroScene17: 64 frames of black, then the done flag.  The cart spends them
-- in a blocking `ld c, 64` loop rather than a counter, so this one gets a
-- field of its own.
Scenes[17] = function(self)
  self.hold = (self.hold or 0) + 1
  if self.hold >= 64 then self.done = true end
end

--------------------------------------------------------------------------
-- Frame loop
--------------------------------------------------------------------------

-- GoldSilverIntro.PlayFrame, minus the joypad read: sprite animations first,
-- then the scene.  Returns true once the movie is over.
function GoldSilverIntro:step()
  if self.done then return true end
  self.frames = self.frames + 1
  self.anims:playFrame()
  local scene = Scenes[self.scene]
  if scene then scene(self) end
  return self.done
end

function GoldSilverIntro:enter()
  -- IntroScene1 is what starts the music, and it has not run yet.
  --
  -- intro.boot.movie: the attract movie is up, on frame zero of scene 1.  Gen 2
  -- only, like the rest of intro.boot.* (see src/ui/gen2/CopyrightSplash.lua):
  -- Red's IntroMovie is a different sequence on a different screen and shares
  -- no moment with this one.
  if Runtime.wants("intro.boot.movie") then
    Runtime.emit("intro.boot.movie", { screen = self, game = self.game })
  end
end

function GoldSilverIntro:finish()
  if self.finished then return end
  self.finished = true
  self.done = true
  -- intro.boot.movie_ended is the one card end that earns a name of its own.
  -- The other three hand off to a card that announces itself, but this one has
  -- a fact nothing downstream carries: whether the player sat through all 2335
  -- frames or cut it short (GoldSilverIntro.PlayFrame's PAD_BUTTONS exit).
  if Runtime.wants("intro.boot.movie_ended") then
    Runtime.emit("intro.boot.movie_ended", {
      screen = self, game = self.game,
      skipped = self.skipped and true or false,
      frames = self.frames,
    })
  end
  if self.onDone then self.onDone() end
end

function GoldSilverIntro:skip()
  self.skipped = true
  self:finish()
end

function GoldSilverIntro:update(_dt)
  if self.finished then return end
  local input = self.game and self.game.input
  if input then
    for _, button in ipairs({ "a", "b", "start", "select" }) do
      if input:wasPressed(button) then
        self:skip()
        return
      end
    end
  end
  if self:step() then self:finish() end
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

function GoldSilverIntro:image(path)
  if not path then return nil end
  local cached = self.images[path]
  if cached == nil then
    local ok, img = pcall(Assets.image, path)
    cached = ok and img or false
    if cached then
      cached:setFilter("nearest", "nearest")
    end
    self.images[path] = cached
  end
  return cached or nil
end

-- A tile sheet is 16 tiles wide, so tile id N is at (N % 16, N / 16).  Quads
-- are built once per sheet.
function GoldSilverIntro:sheet(path)
  if not path then return nil end
  local entry = self.sheets[path]
  if entry ~= nil then return entry or nil end
  local image = self:image(path)
  if not image then
    self.sheets[path] = false
    return nil
  end
  local width, height = image:getDimensions()
  local quads = {}
  for tile = 0, math.floor(width / 8) * math.floor(height / 8) - 1 do
    quads[tile] = love.graphics.newQuad(
      tile % 16 * 8, math.floor(tile / 16) * 8, 8, 8, width, height)
  end
  entry = { image = image, quads = quads }
  self.sheets[path] = entry
  return entry
end

local function bgPalette(self)
  return remap(self.bgPals[1], self.bgp)
end

local function objPalette(self, slot)
  return remap(self.obPals[slot + 1] or self.obPals[1], self.obp0)
end

-- The BG map is rendered into a 256x256 canvas and only redrawn when a scene
-- edits the map, which is what keeps the per-scanline present cheap.
function GoldSilverIntro:bgCanvas()
  local source = actData(self)
  local sheet = source and self:sheet(source.tiles)
  if not sheet then return nil end
  if self.canvasSheet ~= sheet then
    self.canvas = nil
    self.canvasSheet = sheet
    self.mapDirty = true
  end
  if not self.canvas then
    local ok, canvas = pcall(love.graphics.newCanvas, BG_PIXELS, BG_PIXELS)
    if not ok then return nil end
    canvas:setFilter("nearest", "nearest")
    self.canvas = canvas
    self.mapDirty = true
  end
  if self.mapDirty then
    local G = love.graphics
    local previous = G.getCanvas()
    -- The caller is inside the renderer's letterbox transform; a canvas does
    -- not reset it, so the map would land scaled and off the edge.
    G.push()
    G.origin()
    G.setCanvas(self.canvas)
    G.clear(0, 0, 0, 0)
    G.setColor(1, 1, 1, 1)
    for row = 0, BG_TILES - 1 do
      for col = 0, BG_TILES - 1 do
        local quad = sheet.quads[mapGet(self, col, row)]
        if quad then G.draw(sheet.image, quad, col * 8, row * 8) end
      end
    end
    G.setCanvas(previous)
    G.pop()
    self.mapDirty = false
  end
  return self.canvas
end

-- Present the canvas at (hSCX, hSCY), wrapping both ways.  With the LY
-- overrides live each scanline gets its own hSCY, which is the water's bend.
function GoldSilverIntro:drawBackground()
  local canvas = self:bgCanvas()
  if not canvas then return end
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  local scx = self.scx % BG_PIXELS
  if not self.lyActive then
    local scy = self.scy % BG_PIXELS
    for _, ox in ipairs({ 0, BG_PIXELS }) do
      for _, oy in ipairs({ 0, BG_PIXELS }) do
        G.draw(canvas, -scx + ox, -scy + oy)
      end
    end
    return
  end
  self.lineQuad = self.lineQuad
    or love.graphics.newQuad(0, 0, BG_PIXELS, 1, BG_PIXELS, BG_PIXELS)
  for line = 0, SCREEN_H - 1 do
    local scy = (self.lyOverrides[line + 1] + line) % BG_PIXELS
    self.lineQuad:setViewport(0, scy, BG_PIXELS, 1, BG_PIXELS, BG_PIXELS)
    G.draw(canvas, self.lineQuad, -scx, line)
    G.draw(canvas, self.lineQuad, -scx + BG_PIXELS, line)
  end
end

-- One pass over wShadowOAM.  `priority` picks the objects that go behind the
-- BG's opaque pixels (OAM_PRIO), which is what half-submerges Lapras.
function GoldSilverIntro:drawObjects(priority)
  local source = actData(self)
  local sheet = source and self:sheet(source.sprites)
  if not sheet then return end
  local G = love.graphics
  local oam = self.anims.oam
  local shader = GbcPalette.available()
  local current = nil
  for index = #oam, 1, -1 do
    local entry = oam[index]
    local behind = entry.attr >= SpriteAnims.OAM_PRIO
    if behind == priority then
      local quad = sheet.quads[entry.tile]
      if quad then
        local slot = entry.attr % 8
        if shader and current ~= slot then
          GbcPalette.use(objPalette(self, slot))
          current = slot
        end
        local flipX = math.floor(entry.attr / SpriteAnims.OAM_XFLIP) % 2 == 1
        local flipY = math.floor(entry.attr / SpriteAnims.OAM_YFLIP) % 2 == 1
        G.setColor(1, 1, 1, 1)
        G.draw(sheet.image, quad,
          entry.x - 8 + (flipX and 8 or 0), entry.y - 16 + (flipY and 8 or 0),
          0, flipX and -1 or 1, flipY and -1 or 1)
      end
    end
  end
  if current then GbcPalette.clear() end
end

-- Compose one 160x144 frame.  It goes through a canvas of its own because the
-- BG is a 256x256 map drawn at a scroll offset and OBJs hang off both edges:
-- on hardware the LCD simply stops at the screen, and this is what stops.
function GoldSilverIntro:renderFrame()
  local G = love.graphics
  local pal = bgPalette(self)
  -- Priming the BG canvas first keeps the two setCanvas calls from nesting.
  self:bgCanvas()
  if not self.frameCanvas then
    local ok, canvas = pcall(G.newCanvas, SCREEN_W, SCREEN_H)
    if not ok then return nil end
    canvas:setFilter("nearest", "nearest")
    self.frameCanvas = canvas
  end
  local previous = G.getCanvas()
  G.push()
  G.origin()
  G.setCanvas(self.frameCanvas)
  -- BG colour 0 is the backdrop; the tile sheets are written with shade 0
  -- transparent so a priority OBJ shows through exactly where the hardware
  -- would let it.
  local backdrop = GbcPalette.color(pal, 1) or BLACK
  G.clear(backdrop[1] / 255, backdrop[2] / 255, backdrop[3] / 255, 1)
  G.setColor(1, 1, 1, 1)
  self:drawObjects(true)
  if GbcPalette.available() then
    GbcPalette.with(pal, function() self:drawBackground() end)
  else
    self:drawBackground()
  end
  self:drawObjects(false)
  G.setCanvas(previous)
  G.pop()
  return self.frameCanvas
end

function GoldSilverIntro:drawPanel()
  local G = love.graphics
  local canvas = self:renderFrame()
  G.setColor(1, 1, 1, 1)
  if canvas then
    G.draw(canvas, 0, 0)
    return
  end
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
  G.setColor(1, 1, 1, 1)
end

function GoldSilverIntro:draw()
  self:drawPanel()
end

function GoldSilverIntro:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

GoldSilverIntro.Scenes = Scenes
GoldSilverIntro.WATER_FADE = WATER_FADE
GoldSilverIntro.GRASS_FADE = GRASS_FADE
GoldSilverIntro.CHARIZARD_PALS = CHARIZARD_PALS
GoldSilverIntro.FIRE_FADE = FIRE_FADE
GoldSilverIntro.SCY_EVENTS = SCY_EVENTS
GoldSilverIntro.WAVE_TILES = WAVE_TILES
GoldSilverIntro.CHARIZARD_GFX = CHARIZARD_GFX
GoldSilverIntro.remap = remap

return GoldSilverIntro
