-- FRLG Latin variable-width font (pret latin_normal + sFontNormalLatinGlyphWidths).
-- Field dialogue must use this — Gen2 Font.lua is fixed 8px and overflows the 208px box.

local TextIR = require("src.core.game3.scripting.text_ir")

local FrlgFont = {}

FrlgFont.CELL = 16
FrlgFont.MAX_LETTER_WIDTH = 10
FrlgFont.GLYPH_HEIGHT = 14
FrlgFont.LINE_PITCH = 15 -- maxLetterHeight(14) + lineSpacing(1)

-- 1:1 Standard Text Palettes from pokefirered/graphics/text_window/stdpal_0.pal
-- GBA 15-bit BGR555 -> 8-bit RGB888 / normalized 0.0-1.0
FrlgFont.STDPAL = {
  [0] = { 0, 0, 0, 0 },                          -- 0: Transparent / Window Fill
  [1] = { 255 / 255, 255 / 255, 255 / 255, 1 },    -- 1: WHITE (#FFFFFF)
  [2] = { 98 / 255, 98 / 255, 98 / 255, 1 },       -- 2: DARK_GRAY (#626262)
  [3] = { 213 / 255, 213 / 255, 205 / 255, 1 },    -- 3: LIGHT_GRAY (#D5D5CD)
  [4] = { 230 / 255, 8 / 255, 8 / 255, 1 },         -- 4: RED (#E60808)
  [5] = { 255 / 255, 189 / 255, 115 / 255, 1 },    -- 5: LIGHT_RED (#FFBD73)
  [6] = { 32 / 255, 156 / 255, 8 / 255, 1 },        -- 6: GREEN (#209C08)
  [7] = { 148 / 255, 246 / 255, 148 / 255, 1 },    -- 7: LIGHT_GREEN (#94F694)
  [8] = { 49 / 255, 82 / 255, 205 / 255, 1 },      -- 8: BLUE (#3152CD)
  [9] = { 164 / 255, 197 / 255, 246 / 255, 1 },    -- 9: LIGHT_BLUE (#A4C5F6)
  [10] = { 255 / 255, 255 / 255, 255 / 255, 1 },   -- 10: DYNAMIC_COLOR1
  [11] = { 213 / 255, 230 / 255, 246 / 255, 1 },   -- 11: DYNAMIC_COLOR2
  [12] = { 164 / 255, 213 / 255, 230 / 255, 1 },   -- 12: DYNAMIC_COLOR3
  [13] = { 230 / 255, 246 / 255, 255 / 255, 1 },   -- 13: DYNAMIC_COLOR4
  [14] = { 115 / 255, 164 / 255, 197 / 255, 1 },   -- 14: DYNAMIC_COLOR5
  [15] = { 74 / 255, 115 / 255, 164 / 255, 1 },    -- 15: DYNAMIC_COLOR6
}

FrlgFont.COLOR_IDS = {
  TRANSPARENT = 0,
  WHITE = 1,
  DARK_GRAY = 2,
  LIGHT_GRAY = 3,
  RED = 4,
  LIGHT_RED = 5,
  GREEN = 6,
  LIGHT_GREEN = 7,
  BLUE = 8,
  LIGHT_BLUE = 9,
}

-- 3-Slot Color Architecture (Foreground, Shadow, Background/Highlight)
FrlgFont.COLOR = {
  -- Standard NPC / Field Dialogue
  NORMAL = { fg = FrlgFont.STDPAL[2], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] },
  -- Pokémon Gender Markers (Two tones: Light foreground + Dark shadow)
  MALE = { fg = FrlgFont.STDPAL[9], shadow = FrlgFont.STDPAL[8], bg = FrlgFont.STDPAL[0] },
  GENDER_MALE = { fg = FrlgFont.STDPAL[9], shadow = FrlgFont.STDPAL[8], bg = FrlgFont.STDPAL[0] },
  FEMALE = { fg = FrlgFont.STDPAL[5], shadow = FrlgFont.STDPAL[4], bg = FrlgFont.STDPAL[0] },
  GENDER_FEMALE = { fg = FrlgFont.STDPAL[5], shadow = FrlgFont.STDPAL[4], bg = FrlgFont.STDPAL[0] },
  -- Party Menu Specific Two-Tone Gender Markers (from gPartyMenuBg_Pal 59/60, 75/76)
  PARTY_MALE = {
    fg = { 65 / 255, 205 / 255, 255 / 255, 1 },
    shadow = { 0 / 255, 98 / 255, 148 / 255, 1 },
    bg = FrlgFont.STDPAL[0],
  },
  PARTY_FEMALE = {
    fg = { 255 / 255, 156 / 255, 148 / 255, 1 },
    shadow = { 156 / 255, 65 / 255, 57 / 255, 1 },
    bg = FrlgFont.STDPAL[0],
  },
  -- NPC Dialogue Text Colors (Dark Blue / Dark Red fg, Light Gray shadow)
  MALE_NPC = { fg = FrlgFont.STDPAL[8], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] },
  FEMALE_NPC = { fg = FrlgFont.STDPAL[4], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] },
  BLUE = { fg = FrlgFont.STDPAL[8], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] },
  RED = { fg = FrlgFont.STDPAL[4], shadow = FrlgFont.STDPAL[5], bg = FrlgFont.STDPAL[0] },
  GREEN = { fg = FrlgFont.STDPAL[6], shadow = FrlgFont.STDPAL[7], bg = FrlgFont.STDPAL[0] },
  -- Party slot printers & Battle text (White fg, Dark Gray shadow)
  WHITE = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] },
  LIGHT = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] },
  PARTY = { fg = FrlgFont.STDPAL[1], shadow = FrlgFont.STDPAL[2], bg = FrlgFont.STDPAL[0] },
  STAT = { fg = FrlgFont.STDPAL[4], shadow = FrlgFont.STDPAL[5], bg = FrlgFont.STDPAL[0] },
  DARK_GRAY = { fg = FrlgFont.STDPAL[2], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] },
  DARK = { fg = FrlgFont.STDPAL[2], shadow = FrlgFont.STDPAL[3], bg = FrlgFont.STDPAL[0] },
}

-- include/constants/vars.h:340
FrlgFont.NPC_TEXT_COLOR = {
  MALE = 0,
  FEMALE = 1,
  MON = 2,
  NEUTRAL = 3,
  DEFAULT = 255,
}

-- 152-element sTextColorTable from pokefirered/src/dynamic_placeholder_text_util.c
-- Each byte holds 2 nybbles: (low_nybble | (high_nybble << 4))
local sTextColorTable = {
  [0]  = 0x00, -- OBJ_EVENT_GFX_RED_NORMAL / OBJ_EVENT_GFX_RED_BIKE
  [1]  = 0x00, -- OBJ_EVENT_GFX_RED_SURF / OBJ_EVENT_GFX_RED_FIELD_MOVE
  [2]  = 0x00, -- OBJ_EVENT_GFX_RED_FISH / OBJ_EVENT_GFX_RED_VS_SEEKER
  [3]  = 0x10, -- OBJ_EVENT_GFX_RED_VS_SEEKER_BIKE / OBJ_EVENT_GFX_GREEN_NORMAL
  [4]  = 0x11, -- OBJ_EVENT_GFX_GREEN_BIKE / OBJ_EVENT_GFX_GREEN_SURF
  [5]  = 0x11, -- OBJ_EVENT_GFX_GREEN_FIELD_MOVE / OBJ_EVENT_GFX_GREEN_FISH
  [6]  = 0x11, -- OBJ_EVENT_GFX_GREEN_VS_SEEKER / OBJ_EVENT_GFX_GREEN_VS_SEEKER_BIKE
  [7]  = 0x10, -- OBJ_EVENT_GFX_RS_BRENDAN / OBJ_EVENT_GFX_RS_MAY
  [8]  = 0x10, -- OBJ_EVENT_GFX_LITTLE_BOY / OBJ_EVENT_GFX_LITTLE_GIRL
  [9]  = 0x00, -- OBJ_EVENT_GFX_YOUNGSTER / OBJ_EVENT_GFX_BOY
  [10] = 0x00, -- OBJ_EVENT_GFX_BUG_CATCHER / OBJ_EVENT_GFX_SITTING_BOY
  [11] = 0x11, -- OBJ_EVENT_GFX_LASS / OBJ_EVENT_GFX_WOMAN_1
  [12] = 0x01, -- OBJ_EVENT_GFX_CRUSH_GIRL / OBJ_EVENT_GFX_MAN
  [13] = 0x00, -- OBJ_EVENT_GFX_ROCKER / OBJ_EVENT_GFX_FAT_MAN
  [14] = 0x11, -- OBJ_EVENT_GFX_WOMAN_2 / OBJ_EVENT_GFX_BEAUTY
  [15] = 0x10, -- OBJ_EVENT_GFX_BALDING_MAN / OBJ_EVENT_GFX_WOMAN_3
  [16] = 0x00, -- OBJ_EVENT_GFX_OLD_MAN_1 / OBJ_EVENT_GFX_OLD_MAN_2
  [17] = 0x10, -- OBJ_EVENT_GFX_OLD_MAN_LYING_DOWN / OBJ_EVENT_GFX_OLD_WOMAN
  [18] = 0x10, -- OBJ_EVENT_GFX_TUBER_M_WATER / OBJ_EVENT_GFX_TUBER_F
  [19] = 0x00, -- OBJ_EVENT_GFX_TUBER_M_LAND / OBJ_EVENT_GFX_CAMPER
  [20] = 0x01, -- OBJ_EVENT_GFX_PICNICKER / OBJ_EVENT_GFX_COOLTRAINER_M
  [21] = 0x01, -- OBJ_EVENT_GFX_COOLTRAINER_F / OBJ_EVENT_GFX_SWIMMER_M_WATER
  [22] = 0x01, -- OBJ_EVENT_GFX_SWIMMER_F_WATER / OBJ_EVENT_GFX_SWIMMER_M_LAND
  [23] = 0x01, -- OBJ_EVENT_GFX_SWIMMER_F_LAND / OBJ_EVENT_GFX_WORKER_M
  [24] = 0x01, -- OBJ_EVENT_GFX_WORKER_F / OBJ_EVENT_GFX_ROCKET_M
  [25] = 0x01, -- OBJ_EVENT_GFX_ROCKET_F / OBJ_EVENT_GFX_GBA_KID
  [26] = 0x00, -- OBJ_EVENT_GFX_POKE_MANIAC / OBJ_EVENT_GFX_BIKER
  [27] = 0x00, -- OBJ_EVENT_GFX_BLACK_BELT / OBJ_EVENT_GFX_SCIENTIST
  [28] = 0x00, -- OBJ_EVENT_GFX_HIKER / OBJ_EVENT_GFX_FISHER
  [29] = 0x01, -- OBJ_EVENT_GFX_CHANNELER / OBJ_EVENT_GFX_CHEF
  [30] = 0x00, -- OBJ_EVENT_GFX_POLICEMAN / OBJ_EVENT_GFX_GENTLEMAN
  [31] = 0x00, -- OBJ_EVENT_GFX_SAILOR / OBJ_EVENT_GFX_CAPTAIN
  [32] = 0x11, -- OBJ_EVENT_GFX_NURSE / OBJ_EVENT_GFX_CABLE_CLUB_RECEPTIONIST
  [33] = 0x01, -- OBJ_EVENT_GFX_UNION_ROOM_RECEPTIONIST / OBJ_EVENT_GFX_UNUSED_MALE_RECEPTIONIST
  [34] = 0x00, -- OBJ_EVENT_GFX_CLERK / OBJ_EVENT_GFX_MG_DELIVERYMAN
  [35] = 0x00, -- OBJ_EVENT_GFX_TRAINER_TOWER_DUDE / OBJ_EVENT_GFX_PROF_OAK
  [36] = 0x00, -- OBJ_EVENT_GFX_BLUE / OBJ_EVENT_GFX_BILL
  [37] = 0x10, -- OBJ_EVENT_GFX_LANCE / OBJ_EVENT_GFX_AGATHA
  [38] = 0x11, -- OBJ_EVENT_GFX_DAISY / OBJ_EVENT_GFX_LORELEI
  [39] = 0x00, -- OBJ_EVENT_GFX_MR_FUJI / OBJ_EVENT_GFX_BRUNO
  [40] = 0x10, -- OBJ_EVENT_GFX_BROCK / OBJ_EVENT_GFX_MISTY
  [41] = 0x10, -- OBJ_EVENT_GFX_LT_SURGE / OBJ_EVENT_GFX_ERIKA
  [42] = 0x10, -- OBJ_EVENT_GFX_KOGA / OBJ_EVENT_GFX_SABRINA
  [43] = 0x00, -- OBJ_EVENT_GFX_BLAINE / OBJ_EVENT_GFX_GIOVANNI
  [44] = 0x01, -- OBJ_EVENT_GFX_MOM / OBJ_EVENT_GFX_CELIO
  [45] = 0x00, -- OBJ_EVENT_GFX_TEACHY_TV_HOST / OBJ_EVENT_GFX_GYM_GUY
  [46] = 0x33, -- OBJ_EVENT_GFX_ITEM_BALL / OBJ_EVENT_GFX_TOWN_MAP
  [47] = 0x33, -- OBJ_EVENT_GFX_POKEDEX / OBJ_EVENT_GFX_CUT_TREE
  [48] = 0x33, -- OBJ_EVENT_GFX_ROCK_SMASH_ROCK / OBJ_EVENT_GFX_PUSHABLE_BOULDER
  [49] = 0x33, -- OBJ_EVENT_GFX_FOSSIL / OBJ_EVENT_GFX_RUBY
  [50] = 0x33, -- OBJ_EVENT_GFX_SAPPHIRE / OBJ_EVENT_GFX_OLD_AMBER
  [51] = 0x33, -- OBJ_EVENT_GFX_GYM_SIGN / OBJ_EVENT_GFX_SIGN
  [52] = 0x33, -- OBJ_EVENT_GFX_TRAINER_TIPS / OBJ_EVENT_GFX_CLIPBOARD
  [53] = 0x33, -- OBJ_EVENT_GFX_METEORITE / OBJ_EVENT_GFX_LAPRAS_DOLL
  [54] = 0x23, -- OBJ_EVENT_GFX_SEAGALLOP / OBJ_EVENT_GFX_SNORLAX
  [55] = 0x22, -- OBJ_EVENT_GFX_SPEAROW / OBJ_EVENT_GFX_CUBONE
  [56] = 0x22, -- OBJ_EVENT_GFX_POLIWRATH / OBJ_EVENT_GFX_CLEFAIRY
  [57] = 0x22, -- OBJ_EVENT_GFX_PIDGEOT / OBJ_EVENT_GFX_JIGGLYPUFF
  [58] = 0x22, -- OBJ_EVENT_GFX_PIDGEY / OBJ_EVENT_GFX_CHANSEY
  [59] = 0x22, -- OBJ_EVENT_GFX_OMANYTE / OBJ_EVENT_GFX_KANGASKHAN
  [60] = 0x22, -- OBJ_EVENT_GFX_PIKACHU / OBJ_EVENT_GFX_PSYDUCK
  [61] = 0x22, -- OBJ_EVENT_GFX_NIDORAN_F / OBJ_EVENT_GFX_NIDORAN_M
  [62] = 0x22, -- OBJ_EVENT_GFX_NIDORINO / OBJ_EVENT_GFX_MEOWTH
  [63] = 0x22, -- OBJ_EVENT_GFX_SEEL / OBJ_EVENT_GFX_VOLTORB
  [64] = 0x22, -- OBJ_EVENT_GFX_SLOWPOKE / OBJ_EVENT_GFX_SLOWBRO
  [65] = 0x22, -- OBJ_EVENT_GFX_MACHOP / OBJ_EVENT_GFX_WIGGLYTUFF
  [66] = 0x22, -- OBJ_EVENT_GFX_DODUO / OBJ_EVENT_GFX_FEAROW
  [67] = 0x22, -- OBJ_EVENT_GFX_MACHOKE / OBJ_EVENT_GFX_LAPRAS
  [68] = 0x22, -- OBJ_EVENT_GFX_ZAPDOS / OBJ_EVENT_GFX_MOLTRES
  [69] = 0x22, -- OBJ_EVENT_GFX_ARTICUNO / OBJ_EVENT_GFX_MEWTWO
  [70] = 0x22, -- OBJ_EVENT_GFX_MEW / OBJ_EVENT_GFX_ENTEI
  [71] = 0x22, -- OBJ_EVENT_GFX_SUICUNE / OBJ_EVENT_GFX_RAIKOU
  [72] = 0x22, -- OBJ_EVENT_GFX_LUGIA / OBJ_EVENT_GFX_HO_OH
  [73] = 0x22, -- OBJ_EVENT_GFX_CELEBI / OBJ_EVENT_GFX_KABUTO
  [74] = 0x22, -- OBJ_EVENT_GFX_DEOXYS_D / OBJ_EVENT_GFX_DEOXYS_A
  [75] = 0x32, -- OBJ_EVENT_GFX_DEOXYS_N / OBJ_EVENT_GFX_SS_ANNE
}

--- Lookup NPC text color enum from graphicsId (0=Male, 1=Female, 2=Mon, 3=Neutral).
function FrlgFont.getNpcTextColor(graphicId)
  if not graphicId then return FrlgFont.NPC_TEXT_COLOR.NEUTRAL end
  graphicId = tonumber(graphicId)
  if not graphicId or graphicId < 0 then return FrlgFont.NPC_TEXT_COLOR.NEUTRAL end
  local idx = math.floor(graphicId / 2)
  if idx > 75 or not sTextColorTable[idx] then
    return FrlgFont.NPC_TEXT_COLOR.NEUTRAL
  end
  local shift = (graphicId % 2) * 4
  local val = math.floor(sTextColorTable[idx] / (2 ^ shift)) % 16
  return val
end

--- Get 3-slot color table for an NPC graphicsId.
function FrlgFont.colorForNpc(graphicId)
  local c = FrlgFont.getNpcTextColor(graphicId)
  if c == FrlgFont.NPC_TEXT_COLOR.MALE then
    return FrlgFont.COLOR.MALE_NPC
  elseif c == FrlgFont.NPC_TEXT_COLOR.FEMALE then
    return FrlgFont.COLOR.FEMALE_NPC
  else
    return FrlgFont.COLOR.NORMAL
  end
end

-- pret DecompressGlyph_Small: height 13; widths ~4–8 (party nick/HP).
FrlgFont.SMALL_GLYPH_HEIGHT = 13
FrlgFont.SMALL_LINE_PITCH = 14

FrlgFont._fg = nil
FrlgFont._sh = nil
FrlgFont._quads = nil
FrlgFont._widths = nil
FrlgFont._small = nil -- { fg, sh, quads, widths }
FrlgFont._rev = nil -- UTF-8 char → glyph id
FrlgFont._logged = false

local FG_PATHS = {
  { path = "chrome/fonts/latin_normal_fg.rgba", w = 256, h = 512 },
  { path = "data/generated/gba/chrome/fonts/latin_normal_fg.rgba", w = 256, h = 512 },
  { path = "chrome/fonts/latin_normal_fg.png", w = 256, h = 512 },
  { path = "data/generated/gba/chrome/fonts/latin_normal_fg.png", w = 256, h = 512 },
}
local SH_PATHS = {
  { path = "chrome/fonts/latin_normal_shadow.rgba", w = 256, h = 512 },
  { path = "data/generated/gba/chrome/fonts/latin_normal_shadow.rgba", w = 256, h = 512 },
  { path = "chrome/fonts/latin_normal_shadow.png", w = 256, h = 512 },
  { path = "data/generated/gba/chrome/fonts/latin_normal_shadow.png", w = 256, h = 512 },
}
local SMALL_FG_PATHS = {
  { path = "chrome/fonts/latin_small_fg.rgba", w = 256, h = 288 },
  { path = "data/generated/gba/chrome/fonts/latin_small_fg.rgba", w = 256, h = 288 },
  { path = "chrome/fonts/latin_small_fg.png", w = 256, h = 288 },
  { path = "data/generated/gba/chrome/fonts/latin_small_fg.png", w = 256, h = 288 },
}
local SMALL_SH_PATHS = {
  { path = "chrome/fonts/latin_small_shadow.rgba", w = 256, h = 288 },
  { path = "data/generated/gba/chrome/fonts/latin_small_shadow.rgba", w = 256, h = 288 },
  { path = "chrome/fonts/latin_small_shadow.png", w = 256, h = 288 },
  { path = "data/generated/gba/chrome/fonts/latin_small_shadow.png", w = 256, h = 288 },
}

local function log(msg)
  print("[game3/frlg_font] " .. tostring(msg))
end

local function loadImage(candidates)
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  for _, item in ipairs(candidates) do
    local path = type(item) == "table" and item.path or item
    local w = type(item) == "table" and item.w or 256
    local h = type(item) == "table" and item.h or 512
    local data = nil
    if okC and CacheFs then
      if CacheFs.readActive then
        data = CacheFs.readActive(path)
      end
      if not data and CacheFs.read then
        data = CacheFs.read(path)
      end
    end
    if not data and love and love.filesystem and love.filesystem.read then
      data = love.filesystem.read(path)
      if not data then
        data = love.filesystem.read("data/generated/gba/" .. (path:gsub("^data/generated/gba/", "")))
      end
    end
    if not data then
      local f = io.open(path, "rb") or io.open("data/generated/gba/" .. (path:gsub("^data/generated/gba/", "")), "rb")
      if f then
        data = f:read("*a")
        f:close()
      end
    end
    if data and type(data) == "string" and #data > 0 then
      if #data == w * h * 4 and love and love.image and love.graphics then
        local okId, id = pcall(love.image.newImageData, w, h, "rgba8", data)
        if okId and id then
          local img = love.graphics.newImage(id)
          if img and img.setFilter then img:setFilter("nearest", "nearest") end
          return img, path
        end
      elseif love and love.filesystem and love.image and love.graphics then
        local okFd, fd = pcall(love.filesystem.newFileData, data, path)
        if okFd and fd then
          local okId, id = pcall(love.image.newImageData, fd)
          if okId and id then
            local img = love.graphics.newImage(id)
            if img and img.setFilter then img:setFilter("nearest", "nearest") end
            return img, path
          end
        end
      end
    end
    if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(path) then
      local ok, img = pcall(love.graphics.newImage, path)
      if ok and img then
        if img.setFilter then img:setFilter("nearest", "nearest") end
        return img, path
      end
    end
  end
  return nil, nil
end

local function ensure()
  if FrlgFont._fg and FrlgFont._widths and FrlgFont._quads then
    return true
  end
  local widths = FrlgFont._widths
  if not widths then
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    local src
    if okC and CacheFs then
      if CacheFs.readActive then
        src = CacheFs.readActive("data/generated/gba/chrome/fonts/latin_widths.lua")
      end
      if not src and CacheFs.read then
        src = CacheFs.read("data/generated/gba/chrome/fonts/latin_widths.lua")
      end
    end
    if not src and love and love.filesystem and love.filesystem.read then
      src = love.filesystem.read("data/generated/gba/chrome/fonts/latin_widths.lua")
        or love.filesystem.read("chrome/fonts/latin_widths.lua")
    end
    if src and type(src) == "string" then
      local chunk = load(src, "@latin_widths.lua", "t", {}) or load(src)
      if chunk then widths = chunk() end
    end
  end
  if not widths then
    local ok, w = pcall(require, "src.import.gba.chrome.fonts.latin_widths")
    if ok and type(w) == "table" then
      widths = w
    else
      local path = "sevii/gba/chrome/fonts/latin_widths.lua"
      local chunk = loadfile(path)
      if chunk then widths = chunk() end
    end
  end
  FrlgFont._widths = widths or {}

  local fg, fgp = loadImage(FG_PATHS)
  local sh = loadImage(SH_PATHS)
  if not fg then
    if not FrlgFont._logged then
      log("latin_normal font missing")
      FrlgFont._logged = true
    end
    return false
  end
  FrlgFont._fg = fg
  FrlgFont._sh = sh
  local iw, ih = fg:getDimensions()
  local quads = {}
  for id = 0, 511 do
    local col = id % 16
    local row = math.floor(id / 16)
    quads[id] = love.graphics.newQuad(col * 16, row * 16, 16, 16, iw, ih)
  end
  FrlgFont._quads = quads
  if not FrlgFont._logged then
    log("latin_normal ready " .. tostring(fgp))
    FrlgFont._logged = true
  end
  return true
end

local function ensure_small()
  if FrlgFont._small and FrlgFont._small.fg and FrlgFont._small.quads then
    return true
  end
  local widths
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  local src
  if okC and CacheFs then
    if CacheFs.readActive then
      src = CacheFs.readActive("data/generated/gba/chrome/fonts/latin_small_widths.lua")
    end
    if not src and CacheFs.read then
      src = CacheFs.read("data/generated/gba/chrome/fonts/latin_small_widths.lua")
    end
  end
  if not src and love and love.filesystem and love.filesystem.read then
    src = love.filesystem.read("data/generated/gba/chrome/fonts/latin_small_widths.lua")
      or love.filesystem.read("chrome/fonts/latin_small_widths.lua")
  end
  if src and type(src) == "string" then
    local chunk = load(src, "@latin_small_widths.lua", "t", {}) or load(src)
    if chunk then widths = chunk() end
  end
  if not widths then
    local ok, w = pcall(require, "src.import.gba.chrome.fonts.latin_small_widths")
    if ok and type(w) == "table" then
      widths = w
    else
      local chunk = loadfile("sevii/gba/chrome/fonts/latin_small_widths.lua")
      if chunk then widths = chunk() end
    end
  end
  local fg, fgp = loadImage(SMALL_FG_PATHS)
  local sh = loadImage(SMALL_SH_PATHS)
  if not fg then return false end
  local iw, ih = fg:getDimensions()
  local quads = {}
  local maxId = math.floor(iw / 16) * math.floor(ih / 16) - 1
  for id = 0, math.max(255, maxId) do
    local col = id % 16
    local row = math.floor(id / 16)
    if row * 16 + 16 <= ih then
      quads[id] = love.graphics.newQuad(col * 16, row * 16, 16, 16, iw, ih)
    end
  end
  -- Sheets from extract_latin_small.py (ROM hwlat @ 0x1EAF00), CHARMAP-ordered.
  FrlgFont._small = {
    fg = fg, sh = sh, quads = quads, widths = widths or {}, _romBaked = true,
  }
  log("latin_small ready " .. tostring(fgp) .. " (ROM FONT_SMALL)")
  return true
end

-- The remaining single characters of the Latin block of pret
-- pokefirered/charmap.txt: glyphs the US ROM font draws (latin_normal and
-- latin_small, both charmap-ordered) that US text never prints, so
-- TextIR.CHARMAP (the decode table) leaves them out.  Named multi-glyph
-- entries (LV, POKEBLOCK, the SUPER_E/ER/RE superscripts) are not characters
-- and stay out.
-- Mod text in French, German, Spanish or Italian needs them; without an entry
-- glyphId falls back to 0x00 and the letter prints blank.  Render-only: the
-- ROM decode path is unchanged.
FrlgFont.LATIN_GLYPHS = {
  [0x01] = "À", [0x02] = "Á", [0x03] = "Â", [0x04] = "Ç", [0x05] = "È",
  [0x07] = "Ê", [0x08] = "Ë", [0x09] = "Ì", [0x0B] = "Î", [0x0C] = "Ï",
  [0x0D] = "Ò", [0x0E] = "Ó", [0x0F] = "Ô", [0x10] = "Œ", [0x11] = "Ù",
  [0x12] = "Ú", [0x13] = "Û", [0x14] = "Ñ", [0x15] = "ß", [0x16] = "à",
  [0x17] = "á", [0x19] = "ç", [0x1A] = "è", [0x1C] = "ê", [0x1D] = "ë",
  [0x1E] = "ì", [0x20] = "î", [0x21] = "ï", [0x22] = "ò", [0x23] = "ó",
  [0x24] = "ô", [0x25] = "œ", [0x26] = "ù", [0x27] = "ú", [0x28] = "û",
  [0x29] = "ñ", [0x2A] = "º", [0x2B] = "ª", [0x36] = ";", [0x51] = "¿",
  [0x52] = "¡", [0x5A] = "Í", [0x68] = "â", [0x6F] = "í",
  [0xEF] = "▶", [0xF1] = "Ä", [0xF2] = "Ö", [0xF3] = "Ü", [0xF4] = "ä",
  [0xF5] = "ö", [0xF6] = "ü",
}

local function buildRev()
  if FrlgFont._rev then return FrlgFont._rev end
  local rev = {
    [" "] = 0x00,
    ["\n"] = 0xFE,
    ["№"] = 0x108,
    ["↑"] = 0x100, ["↓"] = 0x101, ["←"] = 0x102, ["→"] = 0x103,
    ["①"] = 0x10A, ["②"] = 0x10B, ["③"] = 0x10C,
    ["④"] = 0x10D, ["⑤"] = 0x10E, ["⑥"] = 0x10F,
    ["⑦"] = 0x110, ["⑧"] = 0x111, ["⑨"] = 0x112,
    ["◎"] = 0x115, ["△"] = 0x116, ["✕"] = 0x117,
    ["No"] = 0x108,
    ["▶"] = 0xEF, -- gText_SelectorArrow2 / CHAR_SELECTOR_ARROW
    ["▲"] = 0x79, -- CHAR_UP_ARROW
    ["▼"] = 0x7A, -- CHAR_DOWN_ARROW
    ["◀"] = 0x7B, -- CHAR_LEFT_ARROW
    ["_"] = 0x109, -- CHAR_EXTRA_SYMBOL + CHAR_UNDERSCORE
    ['"'] = 0xB2,
    ["“"] = 0xB1,
    ["”"] = 0xB2,
    ["‘"] = 0xB3,
    ["’"] = 0xB4,
    ["'"] = 0xB4,
    ["$"] = 0xB7,
    ["¥"] = 0xB7,
    ["\xC2\xA5"] = 0xB7,
  }
  for code, ch in pairs(TextIR.CHARMAP or {}) do
    if type(ch) == "string" and #ch > 0 and not rev[ch] then
      rev[ch] = code
    end
  end
  for code, ch in pairs(FrlgFont.LATIN_GLYPHS) do
    if not rev[ch] then rev[ch] = code end
  end
  -- ASCII digits/letters already via CHARMAP; ensure common punctuation.
  FrlgFont._rev = rev
  return rev
end

--- UTF-8 iterate: yield (char, byteFrom, byteTo)
local function utf8Chars(s)
  local i, n = 1, #s
  return function()
    if i > n then return nil end
    local b = s:byte(i)
    local len = 1
    if b >= 0xF0 then len = 4
    elseif b >= 0xE0 then len = 3
    elseif b >= 0xC0 then len = 2
    end
    if i + len - 1 > n then len = 1 end
    local ch = s:sub(i, i + len - 1)
    local from = i
    i = i + len
    return ch, from, i - 1
  end
end

local function resolveColorId(val)
  if not val then return nil end
  if type(val) == "number" then return FrlgFont.STDPAL[val] end
  local upper = tostring(val):upper()
  local id = FrlgFont.COLOR_IDS[upper]
  if id ~= nil then return FrlgFont.STDPAL[id] end
  local num = tonumber(val)
  if num ~= nil and FrlgFont.STDPAL[num] then return FrlgFont.STDPAL[num] end
  return nil
end

local colorScratchPool = {
  { fg = nil, shadow = nil, bg = nil },
  { fg = nil, shadow = nil, bg = nil },
  { fg = nil, shadow = nil, bg = nil },
  { fg = nil, shadow = nil, bg = nil },
}
local colorScratchIdx = 0

local function acquireColorScratch(c)
  colorScratchIdx = (colorScratchIdx % 4) + 1
  local cur = colorScratchPool[colorScratchIdx]
  if not c then
    cur.fg = FrlgFont.STDPAL[2]
    cur.shadow = FrlgFont.STDPAL[3]
    cur.bg = FrlgFont.STDPAL[0]
  else
    cur.fg = c.fg or FrlgFont.STDPAL[2]
    cur.shadow = c.shadow or FrlgFont.STDPAL[3]
    cur.bg = c.bg or FrlgFont.STDPAL[0]
  end
  return cur
end

--- Byte-by-byte token scanner for GBA FRLG text strings.
-- Handles \xFC bytecode sequences, {TAG} macros, and UTF-8 characters without choking on null bytes.
function FrlgFont.scanTokens(text, initialColors)
  local s = tostring(text or "")
  local curColors = acquireColorScratch(initialColors)
  local i, n = 1, #s

  return function()
    while i <= n do
      local b = s:byte(i)

      -- 1) 0xFC (EXT_CTRL_CODE)
      if b == 0xFC and i + 1 <= n then
        local cmd = s:byte(i + 1)
        if cmd == 0x01 and i + 2 <= n then -- EXT_CTRL_CODE_COLOR (3 bytes)
          local cid = s:byte(i + 2)
          curColors.fg = FrlgFont.STDPAL[cid] or curColors.fg
          i = i + 3
          return "ctrl", "COLOR", curColors
        elseif cmd == 0x02 and i + 2 <= n then -- EXT_CTRL_CODE_HIGHLIGHT (3 bytes)
          local cid = s:byte(i + 2)
          curColors.bg = FrlgFont.STDPAL[cid] or curColors.bg
          i = i + 3
          return "ctrl", "HIGHLIGHT", curColors
        elseif cmd == 0x03 and i + 2 <= n then -- EXT_CTRL_CODE_SHADOW (3 bytes)
          local cid = s:byte(i + 2)
          curColors.shadow = FrlgFont.STDPAL[cid] or curColors.shadow
          i = i + 3
          return "ctrl", "SHADOW", curColors
        elseif cmd == 0x04 and i + 4 <= n then -- EXT_CTRL_CODE_COLOR_HIGHLIGHT_SHADOW (5 bytes)
          local fgId = s:byte(i + 2)
          local bgId = s:byte(i + 3)
          local shId = s:byte(i + 4)
          curColors.fg = FrlgFont.STDPAL[fgId] or curColors.fg
          curColors.bg = FrlgFont.STDPAL[bgId] or curColors.bg
          curColors.shadow = FrlgFont.STDPAL[shId] or curColors.shadow
          i = i + 5
          return "ctrl", "COLOR_HIGHLIGHT_SHADOW", curColors
        elseif cmd == 0x06 and i + 2 <= n then -- EXT_CTRL_CODE_FONT (3 bytes)
          local fontId = s:byte(i + 2)
          if fontId == 0x04 then -- FONT_MALE
            curColors.fg = FrlgFont.STDPAL[8]
            curColors.shadow = FrlgFont.STDPAL[3]
            curColors.bg = FrlgFont.STDPAL[0]
          elseif fontId == 0x05 then -- FONT_FEMALE
            curColors.fg = FrlgFont.STDPAL[4]
            curColors.shadow = FrlgFont.STDPAL[3]
            curColors.bg = FrlgFont.STDPAL[0]
          elseif fontId == 0x02 then -- FONT_NORMAL
            curColors.fg = FrlgFont.STDPAL[2]
            curColors.shadow = FrlgFont.STDPAL[3]
            curColors.bg = FrlgFont.STDPAL[0]
          end
          i = i + 3
          return "ctrl", "FONT", curColors
        else
          -- Skip variable length commands according to pret text.c
          local skip = 2
          if cmd == 0x05 or cmd == 0x08 or cmd == 0x0C or cmd == 0x0D
              or cmd == 0x0E or cmd == 0x0F or cmd == 0x11 or cmd == 0x12
              or cmd == 0x13 or cmd == 0x14 then
            skip = 3
          elseif cmd == 0x0B or cmd == 0x10 then
            skip = 4
          end
          i = i + skip
          return "ctrl", "EXT", curColors
        end

      -- 2) Braced tag: {TAG}
      elseif b == 0x7B then -- '{'
        local closePos = s:find("}", i + 1, true)
        if closePos then
          local tag = s:sub(i + 1, closePos - 1)
          local upperTag = tag:upper()
          i = closePos + 1
          if upperTag == "FONT_MALE" then
            curColors.fg = FrlgFont.STDPAL[8]
            curColors.shadow = FrlgFont.STDPAL[3]
            curColors.bg = FrlgFont.STDPAL[0]
            return "ctrl", tag, curColors
          elseif upperTag == "FONT_FEMALE" then
            curColors.fg = FrlgFont.STDPAL[4]
            curColors.shadow = FrlgFont.STDPAL[3]
            curColors.bg = FrlgFont.STDPAL[0]
            return "ctrl", tag, curColors
          elseif upperTag == "FONT_NORMAL" then
            curColors.fg = FrlgFont.STDPAL[2]
            curColors.shadow = FrlgFont.STDPAL[3]
            curColors.bg = FrlgFont.STDPAL[0]
            return "ctrl", tag, curColors
          elseif upperTag:sub(1, 6) == "COLOR " then
            local val = tag:sub(7):match("^%s*(.-)%s*$")
            local col = resolveColorId(val)
            if col then curColors.fg = col end
            return "ctrl", tag, curColors
          elseif upperTag:sub(1, 7) == "SHADOW " then
            local val = tag:sub(8):match("^%s*(.-)%s*$")
            local col = resolveColorId(val)
            if col then curColors.shadow = col end
            return "ctrl", tag, curColors
          elseif upperTag:sub(1, 10) == "HIGHLIGHT " or upperTag:sub(1, 3) == "BG " then
            local val = tag:match("^%S+%s+(.-)%s*$")
            local col = resolveColorId(val)
            if col then curColors.bg = col end
            return "ctrl", tag, curColors
          else
            -- Non-color placeholder or tag
            return "ctrl", tag, curColors
          end
        else
          i = i + 1
          return "char", "{", curColors
        end

      -- 3) Newline
      elseif b == 0x0A then -- '\n'
        i = i + 1
        return "nl", "\n", curColors
      elseif b == 0x0C then -- '\f'
        i = i + 1
        return "page", "\f", curColors
      elseif b == 0x0D then -- '\r'
        i = i + 1

      -- 4) Regular UTF-8 char
      else
        local len = 1
        if b >= 0xF0 then len = 4
        elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2
        end
        if i + len - 1 > n then len = 1 end
        local ch = s:sub(i, i + len - 1)
        i = i + len
        return "char", ch, curColors
      end
    end
    return nil
  end
end

function FrlgFont.glyphId(ch)
  if not ch or ch == "" then return 0x00 end
  local rev = buildRev()
  local id = rev[ch]
  if id then return id end
  local b = ch:byte(1)
  if b and b >= 0x20 and b < 0x7F and #ch == 1 then
    return 0x00
  end
  return 0x00
end

function FrlgFont.advance(glyphId, opts)
  opts = opts or {}
  if opts.small then
    ensure_small()
    local sw = FrlgFont._small and FrlgFont._small.widths
    local w = sw and sw[glyphId]
    if not w then
      if glyphId == 0x108 then return 8 end
      if glyphId == 0xB7 then return 6 end
      w = (sw and sw[0]) or 5
    end
    return w
  end
  ensure()
  local w = FrlgFont._widths[glyphId]
  if not w then
    if glyphId == 0x108 then return 9 end
    if glyphId == 0xB7 then return 7 end
    w = FrlgFont._widths[0] or 6
  end
  return w
end

function FrlgFont.measure(text, opts)
  opts = opts or {}
  local line, maxLine = 0, 0
  for ttype, val in FrlgFont.scanTokens(text) do
    if ttype == "nl" or ttype == "page" then
      if line > maxLine then maxLine = line end
      line = 0
    elseif ttype == "char" then
      line = line + FrlgFont.advance(FrlgFont.glyphId(val), opts)
    end
  end
  if line > maxLine then maxLine = line end
  return maxLine
end

--- Word-wrap text to fit within maxWidth pixels.
function FrlgFont.wrap(text, maxWidth, opts)
  opts = opts or {}
  maxWidth = maxWidth or 200
  local spaceW = FrlgFont.measure(" ", opts)
  local outLines = {}
  local rawLines = {}
  local clean = tostring(text or ""):gsub("\\n", "\n"):gsub("\\p", "\n"):gsub("\\l", "\n")
  for line in (clean .. "\n"):gmatch("(.-)\r?\n") do
    rawLines[#rawLines + 1] = line
  end
  for _, rawLine in ipairs(rawLines) do
    local words = {}
    for word in rawLine:gmatch("%S+") do
      words[#words + 1] = word
    end
    if #words == 0 then
      outLines[#outLines + 1] = ""
    else
      local curLine = words[1]
      local curW = FrlgFont.measure(curLine, opts)
      for i = 2, #words do
        local w = words[i]
        local wW = FrlgFont.measure(w, opts)
        if curW + spaceW + wW <= maxWidth then
          curLine = curLine .. " " .. w
          curW = curW + spaceW + wW
        else
          outLines[#outLines + 1] = curLine
          curLine = w
          curW = wW
        end
      end
      outLines[#outLines + 1] = curLine
    end
  end
  return table.concat(outLines, "\n")
end

local ADVANCE_SMALL = { small = true }
local ADVANCE_NORMAL = {}

--- Draw full string at pixel (x,y).
-- opts.maxWidth clips (CopyGlyphToWindow). opts.colors = COLOR.NORMAL etc.
-- opts.limitChars: only draw first N printable characters (typewriter).
-- opts.small: use FONT_SMALL (party menu).
function FrlgFont.draw(text, x, y, opts)
  opts = opts or {}
  local useSmall = false
  if opts.small then
    useSmall = ensure_small() and FrlgFont._small and FrlgFont._small._romBaked
  end
  if not useSmall and not ensure() then return 0 end

  local baseColors = opts.colors
  if not baseColors then
    if opts.color then
      baseColors = {
        fg = opts.color,
        shadow = opts.shadow or (opts.color == FrlgFont.COLOR.WHITE.fg and FrlgFont.COLOR.WHITE.shadow or FrlgFont.COLOR.NORMAL.shadow),
        bg = opts.bg or FrlgFont.STDPAL[0],
      }
    elseif opts.gfxId then
      baseColors = FrlgFont.colorForNpc(opts.gfxId)
    elseif opts.npcColor then
      if opts.npcColor == FrlgFont.NPC_TEXT_COLOR.MALE then
        baseColors = FrlgFont.COLOR.MALE
      elseif opts.npcColor == FrlgFont.NPC_TEXT_COLOR.FEMALE then
        baseColors = FrlgFont.COLOR.FEMALE
      else
        baseColors = FrlgFont.COLOR.NORMAL
      end
    else
      baseColors = (useSmall and FrlgFont.COLOR.PARTY) or FrlgFont.COLOR.NORMAL
    end
  end

  local maxW = opts.maxWidth or 240
  local limit = opts.limitChars
  local penX, penY = 0, 0
  local drawn = 0
  local pitch = opts.linePitch
    or (useSmall and FrlgFont.SMALL_LINE_PITCH or FrlgFont.LINE_PITCH)
  local fg, sh, quads
  if useSmall then
    fg, sh, quads = FrlgFont._small.fg, FrlgFont._small.sh, FrlgFont._small.quads
  else
    fg, sh, quads = FrlgFont._fg, FrlgFont._sh, FrlgFont._quads
  end

  local function set_col(c)
    if type(c) == "table" then
      love.graphics.setColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  for ttype, val, curCol in FrlgFont.scanTokens(text, baseColors) do
    if limit and drawn >= limit then break end
    if ttype == "nl" then
      penX = 0
      penY = penY + pitch
      drawn = drawn + 1
    elseif ttype == "char" then
      local id = FrlgFont.glyphId(val)
      local adv = FrlgFont.advance(id, useSmall and ADVANCE_SMALL or ADVANCE_NORMAL)
      if penX + adv <= maxW or penX == 0 then
        local dx, dy = x + penX, y + penY
        local q = quads[id]
        if q then
          -- Draw background / highlight fill if bg is not transparent
          if curCol.bg and curCol.bg[4] and curCol.bg[4] > 0 then
            set_col(curCol.bg)
            love.graphics.rectangle("fill", dx, dy, adv, pitch)
          end
          -- Draw shadow
          if sh and curCol.shadow and (not curCol.shadow[4] or curCol.shadow[4] > 0) then
            set_col(curCol.shadow)
            love.graphics.draw(sh, q, dx, dy)
          end
          -- Draw foreground
          if curCol.fg and (not curCol.fg[4] or curCol.fg[4] > 0) then
            set_col(curCol.fg)
            love.graphics.draw(fg, q, dx, dy)
          end
        end
        penX = penX + adv
      end
      drawn = drawn + 1
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return drawn, x + penX, y + penY
end

--- Draw a single glyph by FRLG charset id (e.g. 0x7C = CHAR_RIGHT_ARROW).
-- opts.small: FONT_SMALL sheet (supports EXTRA ids like CHAR_LV_2 = 0x105).
function FrlgFont.drawGlyph(glyphId, x, y, opts)
  opts = opts or {}
  glyphId = tonumber(glyphId) or 0
  local useSmall = opts.small and ensure_small() and FrlgFont._small and FrlgFont._small._romBaked
  if useSmall then
    -- ok
  elseif not ensure() then
    return 0
  end
  local colors = opts.colors or (useSmall and FrlgFont.COLOR.PARTY) or FrlgFont.COLOR.NORMAL
  local fg, sh, quads
  if useSmall then
    fg, sh, quads = FrlgFont._small.fg, FrlgFont._small.sh, FrlgFont._small.quads
  else
    fg, sh, quads = FrlgFont._fg, FrlgFont._sh, FrlgFont._quads
  end
  local q = quads[glyphId]
  if not q then return 0 end
  if colors.bg and colors.bg[4] and colors.bg[4] > 0 then
    love.graphics.setColor(colors.bg)
    love.graphics.rectangle("fill", x, y, FrlgFont.advance(glyphId, useSmall and ADVANCE_SMALL or ADVANCE_NORMAL), useSmall and FrlgFont.SMALL_LINE_PITCH or FrlgFont.LINE_PITCH)
  end
  if sh and colors.shadow and (not colors.shadow[4] or colors.shadow[4] > 0) then
    love.graphics.setColor(colors.shadow)
    love.graphics.draw(sh, q, x, y)
  end
  if colors.fg and (not colors.fg[4] or colors.fg[4] > 0) then
    love.graphics.setColor(colors.fg)
  else
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.draw(fg, q, x, y)
  love.graphics.setColor(1, 1, 1, 1)
  return FrlgFont.advance(glyphId, useSmall and ADVANCE_SMALL or ADVANCE_NORMAL)
end

-- pret CHAR_RIGHT_ARROW = 0x7C, but gText_SelectorArrow2 ("▶") is charmap 0xEF.
-- Menu_InitCursor / RedrawMenuCursor print SelectorArrow2 — use 0xEF for the pip.
FrlgFont.CHAR_RIGHT_ARROW = 0x7C
FrlgFont.CHAR_SELECTOR_ARROW = 0xEF -- gText_SelectorArrow2
FrlgFont.CHAR_LEFT_ARROW = 0x7B
FrlgFont.CHAR_UP_ARROW = 0x79
FrlgFont.CHAR_DOWN_ARROW = 0x7A
-- CHAR_EXTRA_SYMBOL|CHAR_LV_2 → glyph 0x105 in latin_small (UpdateLvlInHealthbox).
FrlgFont.CHAR_LV_2 = 0x105
FrlgFont.CHAR_MALE = 0xB5
FrlgFont.CHAR_FEMALE = 0xB6
FrlgFont.CHAR_SLASH = 0xBA

--- Count printable UTF-8 characters in text (including newlines, skipping control codes).
function FrlgFont.countChars(text)
  local n = 0
  for ttype in FrlgFont.scanTokens(text) do
    if ttype == "char" or ttype == "nl" then
      n = n + 1
    end
  end
  return n
end

function FrlgFont.invalidate()
  FrlgFont._fg = nil
  FrlgFont._sh = nil
  FrlgFont._quads = nil
  FrlgFont._small = nil
  FrlgFont._logged = false
end

FrlgFont.utf8Chars = utf8Chars

return FrlgFont
