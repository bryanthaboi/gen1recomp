-- The Crystal intro movie (pokecrystal engine/movie/intro.asm CrystalIntro),
-- transcribed: the 28-entry scene jumptable stepped once per frame
-- (engine/movie/intro.asm:58-94) over hSCX/hSCY, the two intro counters, live
-- wBGPals2 palettes and a real 32x32 BG map with CGB attributes.
-- Any button skips the whole thing (engine/movie/intro.asm:11-15).

local bit = require("bit")

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Logger = require("src.core.Logger")
local Music = require("src.core.Music")
local Runtime = require("src.mods.Runtime")
local Sound = require("src.core.Sound")
local SpriteAnims = require("src.ui.gen2.SpriteAnims")

local CrystalIntro = {}
CrystalIntro.__index = CrystalIntro
CrystalIntro.isOpaque = true

local SCREEN_W, SCREEN_H = 160, 144
local BG_TILES = 32
local BG_PIXELS = BG_TILES * 8

local INTRO_MUSIC = "Music_CrystalOpening"

local BLACK = { 0, 0, 0 }
local WHITE = { 255, 255, 255 }

local OAM_PRIO = SpriteAnims.OAM_PRIO
local OAM_XFLIP = SpriteAnims.OAM_XFLIP
local OAM_YFLIP = SpriteAnims.OAM_YFLIP
-- OAM_BANK1 (constants/hardware.inc:997).
local OAM_BANK1 = 0x08

--------------------------------------------------------------------------
-- Sprite-anim data, registered into SpriteAnims' shared tables
--------------------------------------------------------------------------

-- dbsprite (macros/gfx.asm:67-70): y byte first, tile counts mod $100.
local function s(xTile, yTile, xPixel, yPixel, tile, attr)
  return {
    y = (yTile * 8 + yPixel) % 256,
    x = (xTile * 8 + xPixel) % 256,
    tile = tile,
    attr = attr,
  }
end

-- data/sprite_anims/oam.asm:815-852 .OAMData_IntroSuicune1.
local SUICUNE_1 = {
  s( 1, -3, 0, 0, 0x05, 0), s( 2, -3, 0, 0, 0x06, 0), s( 3, -3, 0, 0, 0x07, 0),
  s(-3, -2, 0, 0, 0x11, 0), s(-2, -2, 0, 0, 0x12, 0), s(-1, -2, 0, 0, 0x13, 0),
  s( 0, -2, 0, 0, 0x14, 0), s( 1, -2, 0, 0, 0x15, 0), s( 2, -2, 0, 0, 0x16, 0),
  s( 3, -2, 0, 0, 0x17, 0),
  s(-4, -1, 0, 0, 0x20, 0), s(-3, -1, 0, 0, 0x21, 0), s(-2, -1, 0, 0, 0x22, 0),
  s(-1, -1, 0, 0, 0x23, 0), s( 0, -1, 0, 0, 0x24, 0), s( 1, -1, 0, 0, 0x25, 0),
  s( 2, -1, 0, 0, 0x26, 0), s( 3, -1, 0, 0, 0x27, 0),
  s(-4,  0, 0, 0, 0x30, 0), s(-3,  0, 0, 0, 0x31, 0), s(-2,  0, 0, 0, 0x32, 0),
  s(-1,  0, 0, 0, 0x33, 0), s( 0,  0, 0, 0, 0x34, 0), s( 1,  0, 0, 0, 0x35, 0),
  s( 2,  0, 0, 0, 0x36, 0),
  s(-4,  1, 0, 0, 0x40, 0), s(-3,  1, 0, 0, 0x41, 0), s(-2,  1, 0, 0, 0x42, 0),
  s(-1,  1, 0, 0, 0x43, 0), s( 0,  1, 0, 0, 0x44, 0), s( 1,  1, 0, 0, 0x45, 0),
  s( 2,  1, 0, 0, 0x46, 0), s( 3,  1, 0, 0, 0x47, 0),
  s(-4,  2, 0, 0, 0x50, 0), s(-3,  2, 0, 0, 0x51, 0), s( 3,  2, 0, 0, 0x57, 0),
}

-- data/sprite_anims/oam.asm:854-883 .OAMData_IntroSuicune2.
local SUICUNE_2 = {
  s( 0, -3, 0, 0, 0x04, 0), s( 1, -3, 0, 0, 0x05, 0), s( 2, -3, 0, 0, 0x06, 0),
  s(-3, -2, 0, 0, 0x11, 0), s(-2, -2, 0, 0, 0x12, 0), s(-1, -2, 0, 0, 0x13, 0),
  s( 0, -2, 0, 0, 0x14, 0), s( 1, -2, 0, 0, 0x15, 0), s( 2, -2, 0, 0, 0x16, 0),
  s(-3, -1, 0, 0, 0x21, 0), s(-2, -1, 0, 0, 0x22, 0), s(-1, -1, 0, 0, 0x23, 0),
  s( 0, -1, 0, 0, 0x24, 0), s( 1, -1, 0, 0, 0x25, 0), s( 2, -1, 0, 0, 0x26, 0),
  s(-4,  0, 0, 0, 0x30, 0), s(-3,  0, 0, 0, 0x31, 0), s(-2,  0, 0, 0, 0x32, 0),
  s(-1,  0, 0, 0, 0x33, 0), s( 0,  0, 0, 0, 0x34, 0), s( 1,  0, 0, 0, 0x35, 0),
  s(-2,  1, 0, 0, 0x42, 0), s(-1,  1, 0, 0, 0x43, 0), s( 0,  1, 0, 0, 0x44, 0),
  s( 1,  1, 0, 0, 0x45, 0),
  s(-1,  2, 0, 0, 0x53, 0), s( 0,  2, 0, 0, 0x54, 0), s( 1,  2, 0, 0, 0x55, 0),
}

-- data/sprite_anims/oam.asm:885-916 .OAMData_IntroSuicune3.
local SUICUNE_3 = {
  s( 0, -3, 0, 0, 0x04, 0), s( 1, -3, 0, 0, 0x05, 0),
  s(-3, -2, 0, 0, 0x11, 0), s(-2, -2, 0, 0, 0x12, 0), s(-1, -2, 0, 0, 0x13, 0),
  s( 0, -2, 0, 0, 0x14, 0), s( 1, -2, 0, 0, 0x15, 0), s( 2, -2, 0, 0, 0x16, 0),
  s( 3, -2, 0, 0, 0x17, 0),
  s(-4, -1, 0, 0, 0x20, 0), s(-3, -1, 0, 0, 0x21, 0), s(-2, -1, 0, 0, 0x22, 0),
  s(-1, -1, 0, 0, 0x23, 0), s( 0, -1, 0, 0, 0x24, 0), s( 1, -1, 0, 0, 0x25, 0),
  s( 2, -1, 0, 0, 0x26, 0),
  s(-4,  0, 0, 0, 0x30, 0), s(-3,  0, 0, 0, 0x31, 0), s(-2,  0, 0, 0, 0x32, 0),
  s(-1,  0, 0, 0, 0x33, 0), s( 0,  0, 0, 0, 0x34, 0), s( 1,  0, 0, 0, 0x35, 0),
  s(-2,  1, 0, 0, 0x42, 0), s(-1,  1, 0, 0, 0x43, 0), s( 0,  1, 0, 0, 0x44, 0),
  s( 1,  1, 0, 0, 0x45, 0),
  s(-2,  2, 0, 0, 0x52, 0), s(-1,  2, 0, 0, 0x53, 0), s( 0,  2, 0, 0, 0x54, 0),
  s( 1,  2, 0, 0, 0x55, 0),
}

-- data/sprite_anims/oam.asm:918-950 .OAMData_IntroSuicune4.
local SUICUNE_4 = {
  s(-3, -2, 0, 0, 0x11, 0), s(-2, -2, 0, 0, 0x12, 0), s(-1, -2, 0, 0, 0x13, 0),
  s( 0, -2, 0, 0, 0x14, 0), s( 1, -2, 0, 0, 0x15, 0), s( 2, -2, 0, 0, 0x16, 0),
  s( 3, -2, 0, 0, 0x17, 0),
  s(-4, -1, 0, 0, 0x20, 0), s(-3, -1, 0, 0, 0x21, 0), s(-2, -1, 0, 0, 0x22, 0),
  s(-1, -1, 0, 0, 0x23, 0), s( 0, -1, 0, 0, 0x24, 0), s( 1, -1, 0, 0, 0x25, 0),
  s( 2, -1, 0, 0, 0x26, 0), s( 3, -1, 0, 0, 0x27, 0),
  s(-4,  0, 0, 0, 0x30, 0), s(-3,  0, 0, 0, 0x31, 0), s(-2,  0, 0, 0, 0x32, 0),
  s(-1,  0, 0, 0, 0x33, 0), s( 0,  0, 0, 0, 0x34, 0), s( 1,  0, 0, 0, 0x35, 0),
  s( 2,  0, 0, 0, 0x36, 0),
  s(-3,  1, 0, 0, 0x41, 0), s(-2,  1, 0, 0, 0x42, 0), s(-1,  1, 0, 0, 0x43, 0),
  s( 0,  1, 0, 0, 0x44, 0), s( 1,  1, 0, 0, 0x45, 0),
  s(-3,  2, 0, 0, 0x51, 0), s(-2,  2, 0, 0, 0x52, 0), s( 0,  2, 0, 0, 0x54, 0),
  s( 1,  2, 0, 0, 0x55, 0),
}

-- data/sprite_anims/oam.asm:952-978 .OAMData_IntroPichu: 5x5 block,
-- OBJ pal 1, VRAM bank 1.
local PICHU = {}
for row = 0, 4 do
  for col = 0, 4 do
    PICHU[#PICHU + 1] = s(col - 3, row - 3, 4, 4, row * 16 + col,
      1 + OAM_BANK1)
  end
end

-- data/sprite_anims/oam.asm:980-997 .OAMData_IntroWooper: 4x4 block,
-- OBJ pal 2, VRAM bank 1.
local WOOPER = {}
for row = 0, 3 do
  for col = 0, 3 do
    WOOPER[#WOOPER + 1] = s(col - 3, row - 2, 4, 0, row * 4 + col,
      2 + OAM_BANK1)
  end
end

-- data/sprite_anims/oam.asm:999-1017 .OAMData_IntroUnown1/2/3.
local UNOWN_1 = { s(-1, -1, 4, 4, 0x00, 0) }
local UNOWN_2 = {
  s(-1,  0, 0, 0, 0x00, 0), s(-1, -1, 0, 0, 0x01, 0), s( 0, -1, 0, 0, 0x02, 0),
}
local UNOWN_3 = {
  s(-2,  1, 0, 0, 0x00, 0), s(-2,  0, 0, 0, 0x01, 0), s(-2, -1, 0, 0, 0x02, 0),
  s(-1, -1, 0, 0, 0x03, 0), s(-1, -2, 0, 0, 0x04, 0), s( 0, -2, 0, 0, 0x05, 0),
  s( 1, -2, 0, 0, 0x06, 0),
}

-- data/sprite_anims/oam.asm:177-182 .OAMData_IntroUnownF2_1.
local UNOWN_F2_1 = {
  s(-1, -1, 0, 0, 0x00, 0), s( 0, -1, 0, 0, 0x00, OAM_XFLIP),
  s(-1,  0, 0, 0, 0x00, OAM_YFLIP), s( 0,  0, 0, 0, 0x00, OAM_XFLIP + OAM_YFLIP),
}

-- data/sprite_anims/oam.asm:1019-1028 .OAMData_IntroUnownF2_2.
local UNOWN_F2_2 = {
  s(-2, -1, 0, 0, 0x00, 0), s(-1, -1, 0, 0, 0x01, 0),
  s( 0, -1, 0, 0, 0x01, OAM_XFLIP), s( 1, -1, 0, 0, 0x00, OAM_XFLIP),
  s(-2,  0, 0, 0, 0x00, OAM_YFLIP), s(-1,  0, 0, 0, 0x01, OAM_YFLIP),
  s( 0,  0, 0, 0, 0x01, OAM_XFLIP + OAM_YFLIP),
  s( 1,  0, 0, 0, 0x00, OAM_XFLIP + OAM_YFLIP),
}

-- data/sprite_anims/oam.asm:1030-1043 .OAMData_IntroUnownF2_3.
local UNOWN_F2_3 = {
  s(-1, -3, 0, 0, 0x00, 0), s(-1, -2, 0, 0, 0x01, 0), s(-1, -1, 0, 0, 0x02, 0),
  s( 0, -3, 0, 0, 0x00, OAM_XFLIP), s( 0, -2, 0, 0, 0x01, OAM_XFLIP),
  s( 0, -1, 0, 0, 0x02, OAM_XFLIP),
  s(-1,  0, 0, 0, 0x02, OAM_YFLIP), s(-1,  1, 0, 0, 0x01, OAM_YFLIP),
  s(-1,  2, 0, 0, 0x00, OAM_YFLIP),
  s( 0,  0, 0, 0, 0x02, OAM_XFLIP + OAM_YFLIP),
  s( 0,  1, 0, 0, 0x01, OAM_XFLIP + OAM_YFLIP),
  s( 0,  2, 0, 0, 0x00, OAM_XFLIP + OAM_YFLIP),
}

-- data/sprite_anims/oam.asm:1045-1066 .OAMData_IntroUnownF2_4_5: 4x5 block.
local UNOWN_F2_45 = {}
for row = 0, 4 do
  for col = 0, 3 do
    UNOWN_F2_45[#UNOWN_F2_45 + 1] = s(col - 2, row - 3, 0, 4, row * 4 + col, 0)
  end
end

-- data/sprite_anims/oam.asm:1068-1089 .OAMData_IntroSuicuneAway: a zigzag of
-- twenty grass tiles, OBJ pal 1, behind the BG.
local AWAY = {}
do
  local ys = { 0, 1, 2, 3, 4, 3, 2, 1, 0, 1, 2, 3, 4, 3, 2, 1 }
  for index, y in ipairs(ys) do
    AWAY[#AWAY + 1] = s(index, y, 0, 0, 0x00, 1 + OAM_PRIO)
  end
  local tail = { { -15, 0 }, { -14, 1 }, { -13, 2 }, { -12, 3 } }
  for _, spot in ipairs(tail) do
    AWAY[#AWAY + 1] = s(spot[1], spot[2], 0, 0, 0x00, 1 + OAM_PRIO)
  end
end

-- spriteanimoam bases (data/sprite_anims/oam.asm:120-136).
local OAMSETS = {
  INTRO_SUICUNE_1 = { 0x00, SUICUNE_1 },
  INTRO_SUICUNE_2 = { 0x08, SUICUNE_2 },
  INTRO_SUICUNE_3 = { 0x60, SUICUNE_3 },
  INTRO_SUICUNE_4 = { 0x68, SUICUNE_4 },
  INTRO_PICHU_1 = { 0x00, PICHU },
  INTRO_PICHU_2 = { 0x05, PICHU },
  INTRO_PICHU_3 = { 0x0a, PICHU },
  INTRO_WOOPER = { 0x50, WOOPER },
  INTRO_UNOWN_1 = { 0x00, UNOWN_1 },
  INTRO_UNOWN_2 = { 0x01, UNOWN_2 },
  INTRO_UNOWN_3 = { 0x04, UNOWN_3 },
  INTRO_UNOWN_F_2_1 = { 0x00, UNOWN_F2_1 },
  INTRO_UNOWN_F_2_2 = { 0x01, UNOWN_F2_2 },
  INTRO_UNOWN_F_2_3 = { 0x03, UNOWN_F2_3 },
  INTRO_UNOWN_F_2_4 = { 0x08, UNOWN_F2_45 },
  INTRO_UNOWN_F_2_5 = { 0x1c, UNOWN_F2_45 },
  INTRO_SUICUNE_AWAY = { 0x80, AWAY },
}

local function f(oamset, duration, flags)
  return { oamset = oamset, duration = duration, flags = flags or 0 }
end

-- data/sprite_anims/framesets.asm:429-489.
local FRAMESETS = {
  IntroSuicune = {
    f("INTRO_SUICUNE_1", 3), f("INTRO_SUICUNE_2", 3),
    f("INTRO_SUICUNE_3", 3), f("INTRO_SUICUNE_4", 3), "restart",
  },
  IntroSuicune2 = { f("INTRO_SUICUNE_4", 3), f("INTRO_SUICUNE_1", 7), "end" },
  IntroPichu = {
    f("INTRO_PICHU_1", 32), f("INTRO_PICHU_2", 7), f("INTRO_PICHU_3", 7), "end",
  },
  IntroWooper = { f("INTRO_WOOPER", 3), "end" },
  IntroUnown1 = {
    f("INTRO_UNOWN_1", 3), f("INTRO_UNOWN_2", 3), f("INTRO_UNOWN_3", 7),
    f("delete", 0),
  },
  IntroUnown2 = {
    f("INTRO_UNOWN_1", 3, OAM_XFLIP), f("INTRO_UNOWN_2", 3, OAM_XFLIP),
    f("INTRO_UNOWN_3", 7, OAM_XFLIP), f("delete", 0),
  },
  IntroUnown3 = {
    f("INTRO_UNOWN_1", 3, OAM_YFLIP), f("INTRO_UNOWN_2", 3, OAM_YFLIP),
    f("INTRO_UNOWN_3", 7, OAM_YFLIP), f("delete", 0),
  },
  IntroUnown4 = {
    f("INTRO_UNOWN_1", 3, OAM_XFLIP + OAM_YFLIP),
    f("INTRO_UNOWN_2", 3, OAM_XFLIP + OAM_YFLIP),
    f("INTRO_UNOWN_3", 7, OAM_XFLIP + OAM_YFLIP), f("delete", 0),
  },
  IntroUnownF2 = {
    f("INTRO_UNOWN_F_2_1", 3), f("INTRO_UNOWN_F_2_2", 3),
    f("INTRO_UNOWN_F_2_3", 3), f("INTRO_UNOWN_F_2_4", 7),
    f("INTRO_UNOWN_F_2_5", 7), "end",
  },
  IntroSuicuneAway = { f("INTRO_SUICUNE_AWAY", 3), "end" },
  IntroUnownF = { f("wait", 0), "end" },
}

local function reinit(st, framesetId)
  st.framesetId = framesetId
  st.duration = 0
  st.frame = -1
end

local SEQUENCES = {}

-- SpriteAnimFunc_IntroSuicune (engine/sprite_anims/functions.asm:750-776):
-- idle while wIntroSceneTimer is 0, then the jump arc on a negated sine.
SEQUENCES.IntroSuicune = function(sys, st)
  if (sys.timer or 0) == 0 then return end
  st.yOffset = 0
  st.var2 = (st.var2 + 2) % 256
  st.yOffset = SpriteAnims.sine((256 - st.var2) % 256, 32)
  reinit(st, "IntroSuicune2")
end

-- SpriteAnimFunc_IntroPichuWooper (engine/sprite_anims/functions.asm:778-795).
SEQUENCES.IntroPichuWooper = function(_, st)
  if st.var1 >= 20 then return end
  st.var1 = st.var1 + 2
  st.yOffset = SpriteAnims.sine((256 - st.var1) % 256, 32)
end

-- SpriteAnimFunc_IntroUnown (engine/sprite_anims/functions.asm:797-821):
-- VAR1 is the angle, the counter is the radius (core.asm:543-545).
SEQUENCES.IntroUnown = function(_, st)
  local radius = st.jt
  st.jt = (st.jt + 3) % 256
  st.yOffset = SpriteAnims.sine(st.var1, radius)
  st.xOffset = SpriteAnims.cosine(st.var1, radius)
end

-- SpriteAnimFunc_IntroUnownF (engine/sprite_anims/functions.asm:823-829):
-- wSlotsDelay aliases wIntroSceneFrameCounter (ram/wram.asm:1602,1649).
SEQUENCES.IntroUnownF = function(sys, st)
  if (sys.counter or 0) ~= 0x40 then return end
  reinit(st, "IntroUnownF2")
end

-- SpriteAnimFunc_IntroSuicuneAway (engine/sprite_anims/functions.asm:831-837).
SEQUENCES.IntroSuicuneAway = function(_, st)
  st.y = (st.y + 16) % 256
end

-- data/sprite_anims/objects.asm:81-92.
local OBJECTS = {
  INTRO_SUICUNE = { "IntroSuicune", "IntroSuicune" },
  INTRO_PICHU = { "IntroPichu", "IntroPichuWooper" },
  INTRO_WOOPER = { "IntroWooper", "IntroPichuWooper" },
  INTRO_UNOWN = { "IntroUnown1", "IntroUnown" },
  INTRO_UNOWN_F = { "IntroUnownF", "IntroUnownF" },
  INTRO_SUICUNE_AWAY = { "IntroSuicuneAway", "IntroSuicuneAway" },
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
-- Palettes
--------------------------------------------------------------------------

local function scale31(value) return math.floor(value * 255 / 31 + 0.5) end

-- CrystalIntro_UnownFade's three 32-step ramps
-- (engine/movie/intro.asm:1312-1328).
local BW_FADE, LBLUE_FADE, BLUE_FADE = {}, {}, {}
for hue = 0, 31 do
  BW_FADE[hue + 1] = { scale31(hue), scale31(hue), scale31(hue) }
  LBLUE_FADE[hue + 1] = { 0, scale31(math.floor(hue / 2)), scale31(hue) }
  BLUE_FADE[hue + 1] = { 0, 0, scale31(hue) }
end

local function palCopy(source)
  local out = {}
  for index = 1, 4 do
    local color = source and source[index]
    out[index] = color and { color[1], color[2], color[3] } or BLACK
  end
  return out
end

local function flatPals(color)
  local out = {}
  for pal = 1, 8 do out[pal] = { color, color, color, color } end
  return out
end

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

function CrystalIntro:wantsFillScale() return true end
function CrystalIntro:drawsWidescreen() return true end

function CrystalIntro.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, CrystalIntro)
  self.game = game
  self.onDone = opts.onDone
  local data = (game and game.data) or {}
  self.assets = opts.intro or data.gen2Intro or (game and game.introData) or nil
  if not (self.assets and self.assets.acts) then
    Logger.warn("crystal intro: no intro.lua in the cache -- re-import "
      .. "this version or the movie plays blank")
  end
  self.images = {}
  self.sheets = {}

  self.anims = SpriteAnims.new()
  self.scene = 1
  self.phase = 0
  self.hold = 0
  self.done = false
  self.frames = 0

  self.scx, self.scy = 0, 0
  self.counter, self.timer = 0, 0
  self.treeScroll, self.grassScroll = 0, 0
  self.lyActive = false
  self.grassFrame = nil

  self.bgPals = flatPals(BLACK)
  self.obPals = flatPals(BLACK)
  self.map, self.attr = {}, {}
  for index = 1, BG_TILES * BG_TILES do
    self.map[index] = 0
    self.attr[index] = 0
  end
  self.act = nil
  self.mapDirty, self.palsDirty = true, true
  return self
end

--------------------------------------------------------------------------
-- Scene plumbing
--------------------------------------------------------------------------

local function actData(self)
  local acts = self.assets and self.assets.acts
  return acts and self.act and acts[self.act] or nil
end

-- ClearSpriteAnims zeroes wSpriteAnimData through wGlobalAnimXOffset
-- (engine/sprite_anims/core.asm:1-11, ram/wram.asm:202-272).
local function clearAnims(self)
  self.anims:clear()
  self.anims.globalX, self.anims.globalY = 0, 0
end

local function fades(self)
  return (self.assets and self.assets.fades) or {}
end

local function markDirty(self)
  self.palsDirty = true
end

local function loadAct(self, key)
  self.act = key
  self.grassFrame = nil
  local act = actData(self)
  for index = 1, BG_TILES * BG_TILES do
    self.map[index] = act and act.tilemap and act.tilemap[index] or 0
    self.attr[index] = act and act.attrmap and act.attrmap[index] or 0
  end
  local palettes = act and act.palettes or {}
  for pal = 1, 8 do
    self.bgPals[pal] = palCopy(palettes.bg and palettes.bg[pal])
    self.obPals[pal] = palCopy(palettes.obj and palettes.obj[pal])
  end
  self.mapDirty, self.palsDirty = true, true
end

-- Intro_ClearBGPals blacks all 16 palettes and burns two frames
-- (engine/movie/intro.asm:1554-1571); IntroScene26 clears to white instead
-- (engine/movie/intro.asm:1058, home/tilemap.asm:1-9,168-196).
-- Request2bpp (home/gfx.asm:1,190-260): TILES_PER_CYCLE tiles per frame,
-- then one more frame for the final short (or empty) request.
local function requestFrames(tiles)
  local frames = 0
  for _, count in ipairs(tiles) do
    frames = frames + math.floor(count / 8) + 1
  end
  return frames
end

local function setup(self, white, tiles, fn)
  if self.phase == 0 then
    self.phase = 1
    local color = white and WHITE or BLACK
    self.bgPals = flatPals(color)
    self.obPals = flatPals(color)
    markDirty(self)
    self.hold = (white and 4 or 2) + requestFrames(tiles) - 1
    return
  end
  self.phase = 0
  fn(self)
  self.scene = self.scene + 1
end

function CrystalIntro:playMusic(song)
  local data = self.game and self.game.data
  local audio = data and data.audio
  if audio and audio.runtime and audio.songs and audio.songs[song] then
    Music.play(data, song)
  end
end

function CrystalIntro:playSfx(name)
  local data = self.game and self.game.data
  local audio = data and data.audio
  if audio and audio.runtime and audio.sfx and audio.sfx[name] then
    Sound.play(data, name)
  end
end

-- CrystalIntro_UnownFade (engine/movie/intro.asm:1231-1310): zero every BG
-- palette, then write the triangle-wave step of the three ramps into colours
-- 1-3 of palette `pal`.
local function unownFade(self, pal, t)
  local step = t % 64
  if step > 31 then step = 63 - step end
  self.bgPals = flatPals(BLACK)
  local target = self.bgPals[pal + 1]
  target[2] = BW_FADE[step + 1]
  target[3] = LBLUE_FADE[step + 1]
  target[4] = BLUE_FADE[step + 1]
  markDirty(self)
end

-- CrystalIntro_InitUnownAnim (engine/movie/intro.asm:1191-1229): four structs
-- at one spot, angles $08/$18/$28/$38, framesets 4/3/1/2.
local UNOWN_SWIRL = {
  { 0x08, "IntroUnown4" }, { 0x18, "IntroUnown3" },
  { 0x28, "IntroUnown1" }, { 0x38, "IntroUnown2" },
}

local function initUnownAnim(self, x, y)
  for _, spec in ipairs(UNOWN_SWIRL) do
    local st = self.anims:init("INTRO_UNOWN", x, y)
    if st then
      st.var1 = spec[1]
      reinit(st, spec[2])
    end
  end
end

-- Intro_ResetLYOverrides / Intro_PerspectiveScrollBG
-- (engine/movie/intro.asm:1630-1676): trees on lines 0-94 at half speed,
-- grass on lines 95-143 at double, hSCX following the tree band.
local function resetLYOverrides(self)
  self.treeScroll, self.grassScroll = 0, 0
  self.lyActive = true
end

local function perspectiveScroll(self)
  if self.counter % 2 == 1 then
    self.treeScroll = (self.treeScroll + 1) % 256
  end
  self.grassScroll = (self.grassScroll + 2) % 256
  self.scx = self.treeScroll
end

-- Intro_RustleGrass (engine/movie/intro.asm:1521-1547): the four tiles at
-- vTiles2 $09 cycle grass1/grass2/grass3/grass2 for the first 36 frames.
local RUSTLE = { 1, 2, 3, 2 }

local function rustleGrass(self)
  if self.counter >= 36 then return end
  local frame = RUSTLE[math.floor(self.counter / 4) % 4 + 1]
  if frame ~= self.grassFrame then
    self.grassFrame = frame
    self.mapDirty = true
  end
end

-- Intro_ColoredSuicuneFrameSwap (engine/movie/intro.asm:1500-1519): toggle
-- bit 3 of every non-zero id below $80 in the visible 20x18 window.
local function frameSwap(self)
  for row = 0, 17 do
    for col = 0, 19 do
      local index = row * BG_TILES + col + 1
      local id = self.map[index]
      if id ~= 0 and id < 0x80 then
        self.map[index] = bit.bxor(id, 8)
      end
    end
  end
  self.mapDirty = true
end

--------------------------------------------------------------------------
-- Scenes (engine/movie/intro.asm:96-1153)
--------------------------------------------------------------------------

local Scenes = {}

-- IntroScene1 (engine/movie/intro.asm:96-146).
Scenes[1] = function(self)
  setup(self, false, { 64, 128, 128, 64 }, function()
    loadAct(self, "unownA")
    clearAnims(self)
    self.scx, self.scy = 0, 0
    self.counter, self.timer = 0, 0
  end)
end

-- IntroScene2 (engine/movie/intro.asm:148-170).
Scenes[2] = function(self)
  local a = self.counter
  self.counter = (a + 1) % 256
  if a >= 0x80 then
    self.scene = 3
    return
  end
  if a == 0x60 then
    initUnownAnim(self, 11 * 8, 11 * 8)
    self:playSfx("Sfx_IntroUnown1")
  end
  self.timer = a
  unownFade(self, 0, a)
end

-- IntroScene3 (engine/movie/intro.asm:172-218).
Scenes[3] = function(self)
  setup(self, false, { 64, 128, 64 }, function()
    loadAct(self, "background")
    resetLYOverrides(self)
    self.scx, self.scy = 0, 0
    self.counter = 0
  end)
end

-- IntroScene4 (engine/movie/intro.asm:220-232).
Scenes[4] = function(self)
  perspectiveScroll(self)
  if self.counter == 0x80 then
    self.scene = 5
    return
  end
  self.counter = (self.counter + 1) % 256
end

-- IntroScene5 (engine/movie/intro.asm:234-285).
Scenes[5] = function(self)
  setup(self, false, { 64, 128, 128, 64 }, function()
    loadAct(self, "unownHI")
    self.lyActive = false
    clearAnims(self)
    self.scx, self.scy = 0, 0
    self.counter, self.timer = 0, 0
  end)
end

-- IntroScene6 (engine/movie/intro.asm:287-330).
Scenes[6] = function(self)
  local a = self.counter
  self.counter = (a + 1) % 256
  if a >= 0x80 then
    self.scene = 7
    return
  end
  if a == 0x60 then
    initUnownAnim(self, 6 * 8, 14 * 8)
    self:playSfx("Sfx_IntroUnown1")
    self.timer = a
    unownFade(self, 1, a)
    return
  end
  if a >= 0x40 then
    self.timer = a
    unownFade(self, 1, a)
    return
  end
  if a == 0x20 then
    initUnownAnim(self, 15 * 8, 7 * 8)
    self:playSfx("Sfx_IntroUnown2")
  end
  self.timer = a
  unownFade(self, 0, a)
end

-- IntroScene7 (engine/movie/intro.asm:332-401).
Scenes[7] = function(self)
  setup(self, false, { 64, 128, 255, 128, 64 }, function()
    loadAct(self, "background")
    resetLYOverrides(self)
    clearAnims(self)
    self.anims:init("INTRO_SUICUNE", 27 * 8, 13 * 8 + 4)
    self.anims.globalX = 0xf0
    self.scx, self.scy = 0, 0
    self.counter, self.timer = 0, 0
  end)
end

-- IntroScene8 (engine/movie/intro.asm:403-430).
Scenes[8] = function(self)
  local a = self.counter
  self.counter = (a + 1) % 256
  if a == 0x40 then
    self:playSfx("Sfx_IntroSuicune3")
  elseif a < 0x40 then
    perspectiveScroll(self)
    return
  end
  if self.anims.globalX == 0 then
    self:playSfx("Sfx_IntroSuicune2")
    self.anims:clear()
    self.scene = 9
    return
  end
  self.anims.globalX = (self.anims.globalX - 8) % 256
end

-- IntroScene9 (engine/movie/intro.asm:432-467): palette bands over the
-- whole map, six blocking frames.
Scenes[9] = function(self)
  self.lyActive = false
  for row = 0, 17 do
    local pal = (row < 12 and 1) or (row < 15 and 2) or 3
    for col = 0, BG_TILES - 1 do
      self.attr[row * BG_TILES + col + 1] = pal
    end
  end
  self.anims.globalX = 0
  self.counter = 0
  self.mapDirty = true
  self.hold = 6
  self.scene = 10
end

-- IntroScene10 (engine/movie/intro.asm:469-500).
Scenes[10] = function(self)
  rustleGrass(self)
  local a = self.counter
  self.counter = (a + 1) % 256
  if a == 0xc0 then
    self.scene = 11
    return
  end
  if a == 0x20 then
    self.anims:init("INTRO_WOOPER", 6 * 8, 22 * 8)
    self:playSfx("Sfx_IntroPichu")
  elseif a == 0x40 then
    self.anims:init("INTRO_PICHU", 16 * 8, 21 * 8 + 1)
    self:playSfx("Sfx_IntroPichu")
  end
end

-- IntroScene11 (engine/movie/intro.asm:502-550).
Scenes[11] = function(self)
  setup(self, false, { 64, 128, 64 }, function()
    loadAct(self, "unowns")
    self.lyActive = false
    clearAnims(self)
    self.scx, self.scy = 0, 0
    self.counter, self.timer = 0, 0
  end)
end

-- IntroScene12's .UnownSounds (engine/movie/intro.asm:615-624).
local UNOWN_SOUNDS = {
  [0x00] = "Sfx_IntroUnown3", [0x20] = "Sfx_IntroUnown2",
  [0x40] = "Sfx_IntroUnown1", [0x60] = "Sfx_IntroUnown2",
  [0x80] = "Sfx_IntroUnown3", [0x90] = "Sfx_IntroUnown2",
  [0xa0] = "Sfx_IntroUnown1", [0xb0] = "Sfx_IntroUnown2",
}

-- IntroScene12 (engine/movie/intro.asm:552-613).
Scenes[12] = function(self)
  local a = self.counter
  local sound = UNOWN_SOUNDS[a]
  if sound then
    Sound.sfxChannelsOff()
    self:playSfx(sound)
  end
  self.counter = (a + 1) % 256
  if a >= 0xc0 then
    self.scene = 13
    return
  end
  if a < 0x80 then
    self.timer = (a % 0x20) * 2
    unownFade(self, math.floor(a / 0x20), self.timer)
  else
    self.timer = (a % 0x10) * 4
    unownFade(self, 4 + math.floor((a - 0x80) / 0x10), self.timer)
  end
end

-- IntroScene13 (engine/movie/intro.asm:626-683).
Scenes[13] = function(self)
  setup(self, false, { 64, 255, 128, 64 }, function()
    loadAct(self, "background")
    clearAnims(self)
    self.anims:init("INTRO_SUICUNE", 11 * 8, 13 * 8 + 4)
    self:playMusic(INTRO_MUSIC)
    self.scx, self.scy = 0, 0
    self.counter, self.timer = 0, 0
  end)
end

-- IntroScene14 (engine/movie/intro.asm:685-728).
Scenes[14] = function(self)
  self.scx = (self.scx - 10) % 256
  local a = self.counter
  self.counter = (a + 1) % 256
  if a == 0x80 then
    self.scene = 15
    return
  end
  if a == 0x60 then
    self:playSfx("Sfx_IntroSuicune4")
  end
  if a >= 0x60 then
    self.timer = 1
    local gx = self.anims.globalX
    if gx < 0x88 then
      self.anims:clear()
    else
      self.anims.globalX = (gx - 8) % 256
    end
  elseif a >= 0x40 then
    self.anims.globalX = (self.anims.globalX - 2) % 256
  end
end

-- IntroScene15 (engine/movie/intro.asm:730-792).
Scenes[15] = function(self)
  setup(self, false, { 64, 128, 128, 1, 64 }, function()
    loadAct(self, "suicuneJump")
    clearAnims(self)
    self.anims:init("INTRO_UNOWN_F", 5 * 8, 8 * 8)
    self.anims:init("INTRO_SUICUNE_AWAY", 0, 12 * 8)
    self.scx, self.scy = 0, SCREEN_H
    self.counter, self.timer = 0, 0
  end)
end

-- IntroScene16 (engine/movie/intro.asm:794-810).
Scenes[16] = function(self)
  local a = self.counter
  self.counter = (a + 1) % 256
  if a >= 0x80 then
    self.scene = 17
    return
  end
  if a % 4 == 0 then frameSwap(self) end
  if self.scy ~= 0 then
    self.scy = (self.scy + 8) % 256
  end
end

-- IntroScene17 (engine/movie/intro.asm:812-859).
Scenes[17] = function(self)
  setup(self, false, { 64, 255, 64 }, function()
    loadAct(self, "suicuneClose")
    clearAnims(self)
    self.scx, self.scy = 0, 0
    self.counter, self.timer = 0, 0
  end)
end

-- IntroScene18 (engine/movie/intro.asm:861-876).
Scenes[18] = function(self)
  local a = self.counter
  self.counter = (a + 1) % 256
  if a >= 0x60 then
    self.scene = 19
    return
  end
  if self.scx ~= 0x60 then
    self.scx = (self.scx + 8) % 256
  end
end

-- IntroScene19 (engine/movie/intro.asm:878-941).
Scenes[19] = function(self)
  setup(self, false, { 64, 128, 128, 1, 64 }, function()
    loadAct(self, "suicuneBack")
    clearAnims(self)
    self.anims:init("INTRO_SUICUNE_AWAY", 0, 12 * 8)
    self.scx, self.scy = 0, (-5 * 8) % 256
    self.counter, self.timer = 0, 0
  end)
end

-- IntroScene20 (engine/movie/intro.asm:943-988).
Scenes[20] = function(self)
  local a = self.counter
  self.counter = (a + 1) % 256
  if a >= 0x98 then
    self.scene = 21
    return
  end
  if a >= 0x58 then return end
  if a >= 0x40 then
    local b = a - 0x18
    if b % 4 == 3 then
      local slot = math.floor(b % 0x20 / 4)
      self.timer = slot
      self.bgPals[slot + 1] = palCopy(fades(self).unownAppear)
      markDirty(self)
    end
    return
  end
  if a >= 0x28 then return end
  self.scy = (self.scy + 1) % 256
end

-- IntroScene21 (engine/movie/intro.asm:990-1000).
Scenes[21] = function(self)
  frameSwap(self)
  self.hold = 3
  self.counter, self.timer = 0, 0
  self.scene = 22
end

-- IntroScene22 (engine/movie/intro.asm:1002-1012).
Scenes[22] = function(self)
  local a = self.counter
  self.counter = (a + 1) % 256
  if a >= 0x8 then
    self.anims:clear()
    self.scene = 23
  end
end

-- IntroScene23 (engine/movie/intro.asm:1014-1018).
Scenes[23] = function(self)
  self.counter = 0
  self.scene = 24
end

-- IntroScene24 (engine/movie/intro.asm:1020-1042).
Scenes[24] = function(self)
  local a = self.counter
  self.counter = (a + 1) % 256
  if a >= 0x20 then
    self.counter = 0x40
    self.scene = 25
    return
  end
  if a % 4 ~= 0 then return end
  local toWhite = fades(self).toWhite
  local pal = toWhite and toWhite[math.floor(a % 0x20 / 4) + 1]
  if not pal then return end
  for slot = 1, 8 do
    self.bgPals[slot] = palCopy(pal)
  end
  markDirty(self)
end

-- IntroScene25 (engine/movie/intro.asm:1044-1054).
Scenes[25] = function(self)
  if self.counter - 1 == 0 then
    self.scene = 26
    return
  end
  self.counter = self.counter - 1
end

-- IntroScene26 (engine/movie/intro.asm:1056-1103).
Scenes[26] = function(self)
  setup(self, true, { 64, 128, 64 }, function()
    loadAct(self, "crystalUnowns")
    clearAnims(self)
    self.scx, self.scy = 0, 0
    self.counter, self.timer = 0, 0
  end)
end

-- IntroScene27 / Intro_FadeUnownWordPals
-- (engine/movie/intro.asm:1105-1128, :1390-1455).
Scenes[27] = function(self)
  local a = self.counter
  self.counter = (a + 1) % 256
  if a >= 0x80 then
    self.scene = 28
    self.counter = 0x80
    return
  end
  local t = a % 0x10
  local pal = math.floor(a % 0x80 / 0x10)
  local fade = fades(self)
  local target = self.bgPals[pal + 1]
  if fade.wordFast and fade.wordFast[t + 1] then
    target[3] = { unpack(fade.wordFast[t + 1]) }
  end
  if fade.wordSlow and fade.wordSlow[t + 1] then
    target[4] = { unpack(fade.wordSlow[t + 1]) }
  end
  markDirty(self)
end

-- IntroScene28 (engine/movie/intro.asm:1130-1153).
Scenes[28] = function(self)
  local a = self.counter
  if a == 0 then
    self.done = true
    return
  end
  self.counter = a - 1
  if a == 0x18 then
    self.bgPals = flatPals(WHITE)
    self.obPals = flatPals(WHITE)
    markDirty(self)
  elseif a == 0x8 then
    self:playSfx("Sfx_IntroWhoosh")
  end
end

--------------------------------------------------------------------------
-- Frame loop
--------------------------------------------------------------------------

-- CrystalIntro's .loop: the scene function, then PlaySpriteAnimations, then
-- DelayFrame (engine/movie/intro.asm:11-22); in-scene DelayFrames hold the
-- sprites still, so a pending `hold` skips the anim step.
function CrystalIntro:step()
  if self.done then return true end
  self.frames = self.frames + 1
  if self.hold > 0 then
    self.hold = self.hold - 1
    return false
  end
  local scene = Scenes[self.scene]
  if scene then scene(self) end
  if self.done then return true end
  if self.hold > 0 then return false end
  self.anims.timer = self.timer
  self.anims.counter = self.counter
  self.anims:playFrame()
  return self.done
end

function CrystalIntro:enter()
  if Runtime.wants("intro.boot.movie") then
    Runtime.emit("intro.boot.movie", { screen = self, game = self.game })
  end
end

function CrystalIntro:finish()
  if self.finished then return end
  self.finished = true
  self.done = true
  if Runtime.wants("intro.boot.movie_ended") then
    Runtime.emit("intro.boot.movie_ended", {
      screen = self, game = self.game,
      skipped = self.skipped and true or false,
      frames = self.frames,
    })
  end
  if self.onDone then self.onDone() end
end

-- .ShutOffMusic (engine/movie/intro.asm:24-26).
function CrystalIntro:skip()
  self.skipped = true
  Music.stop()
  self:finish()
end

function CrystalIntro:update(_dt)
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

function CrystalIntro:image(path)
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

function CrystalIntro:sheet(path)
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

-- The three layer canvases the CGB attribute byte splits the map into:
-- per-tile colour 0 (the backdrop), colours 1-3 of ordinary tiles, and
-- colours 1-3 of PRIORITY tiles, which beat every OBJ.
local function bakeLayers(self)
  if not (self.mapDirty or self.palsDirty) then
    return self.backdropCanvas ~= nil
  end
  local G = love.graphics
  if not self.backdropCanvas then
    local ok, a = pcall(G.newCanvas, BG_PIXELS, BG_PIXELS)
    local ok2, b = pcall(G.newCanvas, BG_PIXELS, BG_PIXELS)
    local ok3, c = pcall(G.newCanvas, BG_PIXELS, BG_PIXELS)
    if not (ok and ok2 and ok3) then return false end
    for _, canvas in ipairs({ a, b, c }) do
      canvas:setFilter("nearest", "nearest")
    end
    self.backdropCanvas, self.lowCanvas, self.highCanvas = a, b, c
  end
  local act = actData(self)
  local sheet = act and self:sheet(act.tiles)
  local grass = self.grassFrame
    and self:sheet(self.assets and self.assets.grassFrames)
  local previous = G.getCanvas()
  G.push()
  G.origin()

  G.setCanvas(self.backdropCanvas)
  G.clear(0, 0, 0, 1)
  for pal = 0, 7 do
    local color = GbcPalette.color(self.bgPals[pal + 1], 1) or BLACK
    G.setColor(color[1] / 255, color[2] / 255, color[3] / 255, 1)
    for row = 0, BG_TILES - 1 do
      for col = 0, BG_TILES - 1 do
        if self.attr[row * BG_TILES + col + 1] % 8 == pal then
          G.rectangle("fill", col * 8, row * 8, 8, 8)
        end
      end
    end
  end
  G.setColor(1, 1, 1, 1)

  local shader = GbcPalette.available()
  for _, layer in ipairs({
    { canvas = self.lowCanvas, prio = false },
    { canvas = self.highCanvas, prio = true },
  }) do
    G.setCanvas(layer.canvas)
    G.clear(0, 0, 0, 0)
    if sheet then
      for pal = 0, 7 do
        if shader then GbcPalette.use(self.bgPals[pal + 1]) end
        for row = 0, BG_TILES - 1 do
          for col = 0, BG_TILES - 1 do
            local index = row * BG_TILES + col + 1
            local attr = self.attr[index]
            if attr % 8 == pal and (attr >= 0x80) == layer.prio then
              local id = self.map[index]
              local quad
              local image = sheet.image
              if grass and id >= 0x09 and id <= 0x0c then
                quad = grass.quads[(self.grassFrame - 1) * 4 + id - 0x09]
                image = grass.image
              else
                quad = sheet.quads[id]
              end
              if quad then G.draw(image, quad, col * 8, row * 8) end
            end
          end
        end
      end
      if shader then GbcPalette.clear() end
    end
  end
  G.setCanvas(previous)
  G.pop()
  self.mapDirty, self.palsDirty = false, false
  return true
end

-- Present a layer at (hSCX, hSCY); with the perspective bands live each
-- scanline takes the tree or grass SCX (engine/movie/intro.asm:1647-1676).
function CrystalIntro:drawLayer(canvas)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  if not self.lyActive then
    local scx, scy = self.scx % BG_PIXELS, self.scy % BG_PIXELS
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
    local srcY = (self.scy + line) % BG_PIXELS
    local scx = (line < 0x5f and self.treeScroll or self.grassScroll)
      % BG_PIXELS
    self.lineQuad:setViewport(0, srcY, BG_PIXELS, 1, BG_PIXELS, BG_PIXELS)
    G.draw(canvas, self.lineQuad, -scx, line)
    G.draw(canvas, self.lineQuad, -scx + BG_PIXELS, line)
  end
end

function CrystalIntro:drawObjects(priority)
  local act = actData(self)
  local sheet0 = act and self:sheet(act.sprites)
  local sheet1 = act and act.sprites1 and self:sheet(act.sprites1)
  if not (sheet0 or sheet1) then return end
  local G = love.graphics
  local oam = self.anims.oam
  local shader = GbcPalette.available()
  local current = nil
  for index = #oam, 1, -1 do
    local entry = oam[index]
    local behind = bit.band(entry.attr, OAM_PRIO) ~= 0
    if behind == priority then
      local sheet = bit.band(entry.attr, OAM_BANK1) ~= 0 and sheet1 or sheet0
      local quad = sheet and sheet.quads[entry.tile]
      if quad then
        local slot = entry.attr % 8
        if shader and current ~= slot then
          GbcPalette.use(self.obPals[slot + 1])
          current = slot
        end
        local flipX = bit.band(entry.attr, OAM_XFLIP) ~= 0
        local flipY = bit.band(entry.attr, OAM_YFLIP) ~= 0
        G.setColor(1, 1, 1, 1)
        G.draw(sheet.image, quad,
          entry.x - 8 + (flipX and 8 or 0), entry.y - 16 + (flipY and 8 or 0),
          0, flipX and -1 or 1, flipY and -1 or 1)
      end
    end
  end
  if current then GbcPalette.clear() end
end

function CrystalIntro:renderFrame()
  local G = love.graphics
  local baked = bakeLayers(self)
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
  G.clear(0, 0, 0, 1)
  if baked then
    self:drawLayer(self.backdropCanvas)
    self:drawObjects(true)
    self:drawLayer(self.lowCanvas)
    self:drawObjects(false)
    self:drawLayer(self.highCanvas)
  end
  G.setCanvas(previous)
  G.pop()
  return self.frameCanvas
end

function CrystalIntro:drawPanel()
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

function CrystalIntro:draw()
  self:drawPanel()
end

-- The widescreen surround follows the backdrop: colour 0 of the palette the
-- top-left visible tile's attribute selects, live through the fades.
function CrystalIntro:surroundColor()
  local row = math.floor(self.scy / 8) % BG_TILES
  local col = math.floor(self.scx / 8) % BG_TILES
  local attr = self.attr[row * BG_TILES + col + 1] or 0
  return GbcPalette.color(self.bgPals[attr % 8 + 1], 1) or BLACK
end

function CrystalIntro:drawWidescreen(winW, winH)
  local G = love.graphics
  local fill = self:surroundColor()
  G.setColor(fill[1] / 255, fill[2] / 255, fill[3] / 255, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

CrystalIntro.Scenes = Scenes
CrystalIntro.OAMSETS = OAMSETS
CrystalIntro.FRAMESETS = FRAMESETS
CrystalIntro.OBJECTS = OBJECTS
CrystalIntro.SEQUENCES = SEQUENCES
CrystalIntro.unownFade = unownFade

return CrystalIntro
