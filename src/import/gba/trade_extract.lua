-- src/trade_scene.c:151

local Versions = require("src.import.gba.versions")
local BgBake = require("src.import.gba.bg_bake")

local TradeExtract = {}

TradeExtract.CACHE_SUB = "trade"
TradeExtract.FORMAT_VERSION = 1

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
local BALL_SIZE = 16
local BALL_FRAMES = 12

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
    if v >= 0xFFFD then break end
    out[#out + 1] = v
  end
  return out
end

local function bake_console(gfx, banks, map)
  return BgBake.bakeRegionRgba(gfx, banks, map, GBA_W, GBA_H,
    { x0 = 0, y0 = GBA_CENTER_Y - GBA_H / 2, bankOffset = 1, alpha0 = true })
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
  ball = { width = %d, height = %d },
  ball_spin = { width = %d, height = %d, frames = %d, frame_h = %d },
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
    BALL_SIZE, BALL_SIZE,
    BALL_SIZE, BALL_SIZE * BALL_FRAMES, BALL_FRAMES, BALL_SIZE)
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
  return type(ball) == "string" and #ball == BALL_SIZE * BALL_SIZE * 4
end

return TradeExtract
