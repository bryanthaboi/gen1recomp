-- src/trade_scene.c:151

local Versions = require("src.import.gba.versions")
local BgBake = require("src.import.gba.bg_bake")

local TradeExtract = {}

TradeExtract.CACHE_SUB = "trade"
TradeExtract.FORMAT_VERSION = 3

local GBA_W = 240
-- src/trade_scene.c:1128
local GBA_CENTER_Y = 0x15C + 80
-- src/trade_scene.c:1465
local GBA_MIN_VOFS = 166
local GBA_H = (GBA_CENTER_Y - GBA_MIN_VOFS) * 2
local SCREEN_W, SCREEN_H = 240, 160
local FLASH_W, FLASH_H = 64, 32
local CABLE_END_W, CABLE_END_H = 16, 32
local GLOW_SIZE = 32
local SHADOW_W, SHADOW_H = 16, 32
-- src/trade_scene.c:1121 BGCNT_TXT512x256
local MON_SHADOW_BG_W = 256
local BALL_SIZE = 16
local BALL_FRAMES = 12
-- src/trade.c:1376
local MENU_TILES = 0x1280 / 32
local STRIPES_W = 256
-- src/trade.c:2281
local BOX_COLS, BOX_ROWS = 15, 17
-- src/trade.c:2404
local MON_BOX_COLS, MON_BOX_ROWS = 6, 3
-- src/trade.c:236, :246
local CURSOR_W, CURSOR_H, CURSOR_FRAMES = 64, 32, 2
local TILE_SHEET_COLS = 16
local TILE_SHEET_ROWS = math.ceil(MENU_TILES / TILE_SHEET_COLS)

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function raw_bytes(rom, off, n)
  local out = {}
  for i = 1, n do out[i] = rom:get(off + i - 1) end
  return out
end

local function pal_banks(rom, off, count)
  return BgBake.loadPalBanks(raw_bytes(rom, off, count * 32), count)
end

-- src/trade_scene.c:398, include/sprite.h:82
local function anim_frame_tiles(rom, off)
  local out = {}
  for i = 0, 63 do
    local v = rom:u16(off + i * 4)
    -- include/sprite.h:84-88
    if v == 0xFFFF then break end
    if v ~= 0xFFFE and v ~= 0xFFFD then
      out[#out + 1] = v
    end
  end
  return out
end

local function bake_console(gfx, banks, map)
  return BgBake.bakeRegionRgba(gfx, banks, map, GBA_W, GBA_H,
    { x0 = 0, y0 = GBA_CENTER_Y - GBA_H / 2, bankOffset = 1, alpha0 = true })
end

local function over_backdrop(rgba, color)
  local r, g, b = BgBake.bgr555ToRgb8(color or 0)
  local solid = string.char(r, g, b, 255)
  return (rgba:gsub("....", function(px)
    if px:byte(4) == 0 then return solid end
    return px
  end))
end

-- src/trade.c:1368 LoadTradeBgGfx
local function bake_menu(rom, cache, root)
  local banks = pal_banks(rom, Versions.TRADE_MENU_PAL, 3)
  local gfx = raw_bytes(rom, Versions.TRADE_MENU_GFX, MENU_TILES * 32)

  local menuMap = raw_bytes(rom, Versions.TRADE_MENU_MAP, 32 * 32 * 2)
  cache:write(root .. "/menu_bg1.rgba",
    BgBake.bakeRegionRgba(gfx, banks, menuMap, SCREEN_W, SCREEN_H, { alpha0 = true }))

  local bg2Map = raw_bytes(rom, Versions.TRADE_STRIPES_BG2_MAP, 32 * 32 * 2)
  cache:write(root .. "/stripes_bg2.rgba",
    BgBake.bakeRegionRgba(gfx, banks, bg2Map, STRIPES_W, SCREEN_H, { alpha0 = true }))
  local bg3Map = raw_bytes(rom, Versions.TRADE_STRIPES_BG3_MAP, 32 * 32 * 2)
  cache:write(root .. "/stripes_bg3.rgba", over_backdrop(
    BgBake.bakeRegionRgba(gfx, banks, bg3Map, STRIPES_W, SCREEN_H, { alpha0 = true }),
    banks[0][0]))

  local boxBytes = BOX_COLS * BOX_ROWS * 2
  local partyMap = raw_bytes(rom, Versions.TRADE_PARTY_BOX_MAP, boxBytes)
  cache:write(root .. "/party_box.rgba", BgBake.bakeRegionRgba(gfx, banks, partyMap,
    BOX_COLS * 8, BOX_ROWS * 8, { mapW = BOX_COLS, alpha0 = true }))
  local movesMap = raw_bytes(rom, Versions.TRADE_MOVES_BOX_MAP, boxBytes)
  cache:write(root .. "/moves_box.rgba", BgBake.bakeRegionRgba(gfx, banks, movesMap,
    BOX_COLS * 8, BOX_ROWS * 8, { mapW = BOX_COLS, alpha0 = true }))

  local monBoxMap = raw_bytes(rom, Versions.TRADE_MENU_MON_BOX_MAP, MON_BOX_COLS * MON_BOX_ROWS * 2)
  cache:write(root .. "/mon_box.rgba", BgBake.bakeRegionRgba(gfx, banks, monBoxMap,
    MON_BOX_COLS * 8, MON_BOX_ROWS * 8, { mapW = MON_BOX_COLS, alpha0 = true }))

  local sheetMap = {}
  for i = 0, TILE_SHEET_COLS * TILE_SHEET_ROWS - 1 do
    local entry = i < MENU_TILES and i or 0x3FF
    sheetMap[i * 2 + 1] = entry % 256
    sheetMap[i * 2 + 2] = math.floor(entry / 256)
  end
  cache:write(root .. "/menu_tiles.rgba", BgBake.bakeRegionRgba(gfx, banks, sheetMap,
    TILE_SHEET_COLS * 8, TILE_SHEET_ROWS * 8, { mapW = TILE_SHEET_COLS, alpha0 = true }))

  local cursorBank = pal_banks(rom, Versions.TRADE_CURSOR_PAL, 1)[0]
  local cursorGfx = raw_bytes(rom, Versions.TRADE_CURSOR_GFX, 0x800)
  local frames = {}
  for f = 0, CURSOR_FRAMES - 1 do
    frames[#frames + 1] = BgBake.bakeSpriteRgba(cursorGfx, cursorBank,
      f * (CURSOR_W / 8) * (CURSOR_H / 8), CURSOR_W, CURSOR_H, false, false)
  end
  cache:write(root .. "/cursor.rgba", table.concat(frames))
end

function TradeExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. TradeExtract.CACHE_SUB

  local gbaGfx = raw_bytes(rom, Versions.TRADE_GBA_GFX, 160 * 32)
  local gbaBanks = pal_banks(rom, Versions.TRADE_GBA_PAL2, 3)
  local cableMap = raw_bytes(rom, Versions.TRADE_GBA_MAP_CABLE, 32 * 64 * 2)
  local wirelessMap = raw_bytes(rom, Versions.TRADE_GBA_MAP_WIRELESS, 32 * 64 * 2)
  cache:write(root .. "/gba_screen.rgba", bake_console(gbaGfx, gbaBanks, cableMap))
  cache:write(root .. "/gba_screen_wireless.rgba", bake_console(gbaGfx, gbaBanks, wirelessMap))

  -- src/trade_scene.c:1121
  local monShadowMap = raw_bytes(rom, Versions.TRADE_MON_SHADOW_MAP, 32 * 32 * 2)
  cache:write(root .. "/mon_shadow_bg.rgba", BgBake.bakeRegionRgba(gbaGfx, gbaBanks,
    monShadowMap, MON_SHADOW_BG_W, SCREEN_H, { bankOffset = 1, alpha0 = true }))

  local closeupMap = raw_bytes(rom, Versions.TRADE_CABLE_CLOSEUP_MAP, 32 * 32 * 2)
  cache:write(root .. "/cable_closeup.rgba", BgBake.bakeRegionRgba(gbaGfx, gbaBanks,
    closeupMap, SCREEN_W, SCREEN_H, { bankOffset = 1, alpha0 = true }))

  local objBank = pal_banks(rom, Versions.TRADE_GBA_PAL, 1)[0]
  local flashGfx = raw_bytes(rom, Versions.TRADE_GBA_SCREEN_GFX, 128 * 32)
  local flashFrameTiles = anim_frame_tiles(rom, Versions.TRADE_GBA_SCREEN_ANIM)
  local flashRows = {}
  for row = 0, FLASH_H - 1 do flashRows[row] = {} end
  for i, tile in ipairs(flashFrameTiles) do
    local frame = BgBake.bakeSpriteRgba(flashGfx, objBank, tile, FLASH_W, FLASH_H, true, true)
    for row = 0, FLASH_H - 1 do
      flashRows[row][i] = frame:sub(row * FLASH_W * 4 + 1, (row + 1) * FLASH_W * 4)
    end
  end
  local flashParts = {}
  for row = 0, FLASH_H - 1 do
    flashParts[#flashParts + 1] = table.concat(flashRows[row])
  end
  cache:write(root .. "/gba_screen_flash.rgba", table.concat(flashParts))

  local cableEndGfx = raw_bytes(rom, Versions.TRADE_CABLE_END_GFX, 16 * 32)
  cache:write(root .. "/cable_end.rgba",
    BgBake.bakeSpriteRgba(cableEndGfx, objBank, 0, CABLE_END_W, CABLE_END_H, false, false))

  local monBank = pal_banks(rom, Versions.TRADE_LINK_MON_PAL, 1)[0]
  local glowGfx = raw_bytes(rom, Versions.TRADE_LINK_MON_GLOW_GFX, 16 * 32)
  cache:write(root .. "/link_mon_glow.rgba",
    BgBake.bakeSpriteRgba(glowGfx, monBank, 0, GLOW_SIZE, GLOW_SIZE, true, true))

  local shadowGfx = raw_bytes(rom, Versions.TRADE_LINK_MON_SHADOW_GFX, 16 * 32)
  cache:write(root .. "/link_mon_shadow.rgba",
    BgBake.bakeSpriteRgba(shadowGfx, monBank, 0, SHADOW_W, SHADOW_H, true, true))
  cache:write(root .. "/link_mon_shadow_small.rgba",
    BgBake.bakeSpriteRgba(shadowGfx, monBank, 8, SHADOW_W, SHADOW_H, true, true))

  local ballBank = pal_banks(rom, Versions.TRADE_POKEBALL_PAL, 1)[0]
  local ballGfx = raw_bytes(rom, Versions.TRADE_POKEBALL_GFX, 48 * 32)
  cache:write(root .. "/ball.rgba",
    BgBake.bakeSpriteRgba(ballGfx, ballBank, 0, BALL_SIZE, BALL_SIZE, false, false))
  local spin = {}
  for f = 0, BALL_FRAMES - 1 do
    spin[#spin + 1] = BgBake.bakeSpriteRgba(ballGfx, ballBank, f * 4,
      BALL_SIZE, BALL_SIZE, false, false)
  end
  cache:write(root .. "/ball_spin.rgba", table.concat(spin))

  bake_menu(rom, cache, root)

  local manifest = string.format([[
return {
  format_version = %d,
  gba_screen = { width = %d, height = %d, center_y = %d },
  gba_screen_wireless = { width = %d, height = %d, center_y = %d },
  cable_closeup = { width = %d, height = %d },
  gba_screen_flash = { width = %d, height = %d, frames = %d, frame_w = %d },
  cable_end = { width = %d, height = %d },
  link_mon_glow = { width = %d, height = %d },
  link_mon_shadow = { width = %d, height = %d },
  link_mon_shadow_small = { width = %d, height = %d },
  mon_shadow_bg = { width = %d, height = %d },
  ball ={ width = %d, height = %d },
  ball_spin = { width = %d, height = %d, frames = %d, frame_h = %d },
  menu_bg1 = { width = %d, height = %d },
  stripes_bg2 = { width = %d, height = %d },
  stripes_bg3 = { width = %d, height = %d },
  party_box = { width = %d, height = %d },
  moves_box = { width = %d, height = %d },
  mon_box = { width = %d, height = %d },
  menu_tiles = { width = %d, height = %d, tiles = %d, columns = %d,
    level_tens = %d, level_ones = %d, gender_none = %d, gender_male = %d,
    gender_female = %d, egg_symbol = %d, egg_symbol_hflip = true },
  cursor = { width = %d, height = %d, frames = %d, frame_h = %d },
}
]],
    TradeExtract.FORMAT_VERSION,
    GBA_W, GBA_H, GBA_CENTER_Y,
    GBA_W, GBA_H, GBA_CENTER_Y,
    SCREEN_W, SCREEN_H,
    FLASH_W * #flashFrameTiles, FLASH_H, #flashFrameTiles, FLASH_W,
    CABLE_END_W, CABLE_END_H,
    GLOW_SIZE, GLOW_SIZE,
    SHADOW_W, SHADOW_H,
    SHADOW_W, SHADOW_H,
    MON_SHADOW_BG_W, SCREEN_H,
    BALL_SIZE, BALL_SIZE,
    BALL_SIZE, BALL_SIZE * BALL_FRAMES, BALL_FRAMES, BALL_SIZE,
    SCREEN_W, SCREEN_H,
    STRIPES_W, SCREEN_H,
    STRIPES_W, SCREEN_H,
    BOX_COLS * 8, BOX_ROWS * 8,
    BOX_COLS * 8, BOX_ROWS * 8,
    MON_BOX_COLS * 8, MON_BOX_ROWS * 8,
    TILE_SHEET_COLS * 8, TILE_SHEET_ROWS * 8, MENU_TILES, TILE_SHEET_COLS,
    -- src/trade.c:2415, :2427, :2445
    0x60, 0x70, 0x83, 0x84, 0x85, 0x80,
    CURSOR_W, CURSOR_H * CURSOR_FRAMES, CURSOR_FRAMES, CURSOR_H)
  cache:write(root .. "/manifest.lua", manifest)

  print(string.format("[trade_extract] console %dx%d, %d flash frames, %d ball frames -> %s",
    GBA_W, GBA_H, #flashFrameTiles, BALL_FRAMES, root))
  return { root = root, width = GBA_W, height = GBA_H }
end

function TradeExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. TradeExtract.CACHE_SUB
  if not (cache and cache.exists and cache.read) then return false end
  local body = cache:exists(root .. "/manifest.lua") and cache:read(root .. "/manifest.lua")
  if type(body) ~= "string" then return false end
  local chunk = load(body, "@" .. root .. "/manifest.lua", "t", {})
  if not chunk then return false end
  local ok, man = pcall(chunk)
  if not ok or type(man) ~= "table" then return false end
  if man.format_version ~= TradeExtract.FORMAT_VERSION then return false end
  local screen = cache:read(root .. "/gba_screen.rgba")
  if type(screen) ~= "string" or #screen ~= GBA_W * GBA_H * 4 then return false end
  local ball = cache:read(root .. "/ball.rgba")
  if type(ball) ~= "string" or #ball ~= BALL_SIZE * BALL_SIZE * 4 then return false end
  local menu = cache:exists(root .. "/menu_bg1.rgba") and cache:read(root .. "/menu_bg1.rgba")
  if type(menu) ~= "string" or #menu ~= SCREEN_W * SCREEN_H * 4 then return false end
  local shadowBg = cache:exists(root .. "/mon_shadow_bg.rgba") and cache:read(root .. "/mon_shadow_bg.rgba")
  if type(shadowBg) ~= "string" or #shadowBg ~= MON_SHADOW_BG_W * SCREEN_H * 4 then return false end
  local cursor = cache:exists(root .. "/cursor.rgba") and cache:read(root .. "/cursor.rgba")
  return type(cursor) == "string" and #cursor == CURSOR_W * CURSOR_H * CURSOR_FRAMES * 4
end

return TradeExtract
