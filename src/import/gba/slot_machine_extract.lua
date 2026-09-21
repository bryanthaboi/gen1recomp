-- src/slot_machine.c:399, :739

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")
local BgBake = require("src.import.gba.bg_bake")

local SlotMachineExtract = {}

SlotMachineExtract.CACHE_SUB = "slot_machine"
SlotMachineExtract.FORMAT_VERSION = 1

local ICON_SIZE = 32
local ICON_FRAMES = 7
local CLEFAIRY_SIZE = 32
local CLEFAIRY_FRAMES = 6
local DIGIT_W, DIGIT_H = 8, 16
local DIGIT_FRAMES = 10
local SCREEN_W, SCREEN_H = 240, 160

-- src/slot_machine.c:2402
local LIGHTS_TILE_X, LIGHTS_TILE_Y, LIGHTS_TILES_W, LIGHTS_TILES_H = 1, 2, 28, 2
-- src/slot_machine.c:30
local LINES_TILE_X, LINES_TILE_Y, LINES_TILES_W, LINES_TILES_H = 4, 5, 22, 13
local BUTTON_W, BUTTON_H = 16, 16

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

-- src/slot_machine.c:429
local function icon_pal_banks(rom)
  local out = {}
  for i = 1, ICON_FRAMES do out[i] = rom:u16(Versions.SLOT_REEL_ICON_PAL_TAGS + (i - 1) * 2) end
  return out
end

-- src/slot_machine.c:857
local function button_tile_xy(rom)
  local out = {}
  for r = 1, Versions.SLOT_REELS do
    local idx = rom:u16(Versions.SLOT_REEL_BUTTON_MAP_IDXS
      + (r - 1) * Versions.SLOT_BUTTON_TILES * 2)
    out[r] = { idx % 32, math.floor(idx / 32) }
  end
  return out
end

local function frames_rgba(gfx, bankFor, tilesPerFrame, fw, fh, frames)
  local parts = {}
  for f = 0, frames - 1 do
    parts[#parts + 1] = BgBake.bakeSpriteRgba(gfx, bankFor(f), f * tilesPerFrame,
      fw, fh, false, false)
  end
  return table.concat(parts)
end

local function pal_bytes(banks)
  local parts = {}
  for b = 0, #banks do
    local bank = banks[b]
    if bank then
      for c = 0, 15 do
        local r, g, bl = BgBake.bgr555ToRgb8(bank[c] or 0)
        parts[#parts + 1] = string.char(r, g, bl)
      end
    end
  end
  return table.concat(parts)
end

function SlotMachineExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. SlotMachineExtract.CACHE_SUB
  local function get(i) return rom:get(i) end

  local iconGfx = Lz77.decompress(get, Versions.SLOT_REEL_ICONS_GFX)
  local iconBanks = pal_banks(rom, Versions.SLOT_REEL_ICONS_PAL, 5)
  local iconPalBank = icon_pal_banks(rom)
  cache:write(root .. "/reel_icons.rgba", frames_rgba(iconGfx, function(f)
    return iconBanks[iconPalBank[f + 1] or 0]
  end, 16, ICON_SIZE, ICON_SIZE, ICON_FRAMES))

  local clefGfx = Lz77.decompress(get, Versions.SLOT_CLEFAIRY_GFX)
  local clefBank = pal_banks(rom, Versions.SLOT_CLEFAIRY_PAL, 1)[0]
  cache:write(root .. "/clefairy.rgba", frames_rgba(clefGfx, function()
    return clefBank
  end, 16, CLEFAIRY_SIZE, CLEFAIRY_SIZE, CLEFAIRY_FRAMES))

  local digitGfx = Lz77.decompress(get, Versions.SLOT_DIGITS_GFX)
  local digitBank = pal_banks(rom, Versions.SLOT_DIGITS_PAL, 1)[0]
  cache:write(root .. "/digits.rgba", frames_rgba(digitGfx, function()
    return digitBank
  end, 2, DIGIT_W, DIGIT_H, DIGIT_FRAMES))

  local bgGfx = Lz77.decompress(get, Versions.SLOT_BG_GFX)
  local bgMap = Lz77.decompress(get, Versions.SLOT_BG_TILEMAP)
  local bgBanks = pal_banks(rom, Versions.SLOT_BG_PAL, 5)
  cache:write(root .. "/bg.rgba",
    BgBake.bakeBgRgba(bgGfx, bgBanks, bgMap, SCREEN_W, SCREEN_H))

  local lightBanks = pal_banks(rom, Versions.SLOT_PAYOUT_LIGHTS_PAL, 3)
  local lightsW, lightsH = LIGHTS_TILES_W * 8, LIGHTS_TILES_H * 8
  local lightParts = {}
  for b = 0, 2 do
    local banks = {}
    for i = 0, 4 do banks[i] = bgBanks[i] end
    banks[1] = lightBanks[b]
    lightParts[#lightParts + 1] = BgBake.bakeRegionRgba(bgGfx, banks, bgMap,
      lightsW, lightsH,
      { x0 = LIGHTS_TILE_X * 8, y0 = LIGHTS_TILE_Y * 8, alpha0 = true })
  end
  cache:write(root .. "/payout_lights.rgba", table.concat(lightParts))

  local matchBank = pal_banks(rom, Versions.SLOT_MATCH_LINES_PAL, 1)[0]
  local lineBanks = {}
  for i = 0, 4 do lineBanks[i] = bgBanks[i] end
  lineBanks[4] = matchBank
  cache:write(root .. "/match_lines.rgba", BgBake.bakeRegionRgba(bgGfx, lineBanks, bgMap,
    LINES_TILES_W * 8, LINES_TILES_H * 8,
    { x0 = LINES_TILE_X * 8, y0 = LINES_TILE_Y * 8, alpha0 = true }))

  local buttonGfx = Lz77.decompress(get, Versions.SLOT_BUTTON_PRESSED_GFX)
  cache:write(root .. "/button_pressed.rgba",
    BgBake.bakeSpriteRgba(buttonGfx, bgBanks[0], 0, BUTTON_W, BUTTON_H, false, false))

  local combosGfx = Lz77.decompress(get, Versions.SLOT_COMBOS_WINDOW_GFX)
  local combosMap = Lz77.decompress(get, Versions.SLOT_COMBOS_WINDOW_TILEMAP)
  local combosBanks = pal_banks(rom, Versions.SLOT_COMBOS_WINDOW_PAL, 3)
  cache:write(root .. "/combos_window.rgba", BgBake.bakeRegionRgba(combosGfx, combosBanks,
    combosMap, SCREEN_W, SCREEN_H, { bankOffset = 7, alpha0 = true }))

  cache:write(root .. "/payout_lights.pal", pal_bytes(lightBanks))
  cache:write(root .. "/match_lines.pal", pal_bytes({ [0] = matchBank }))

  local buttons = {}
  for i, xy in ipairs(button_tile_xy(rom)) do
    buttons[i] = string.format("{ x = %d, y = %d }", xy[1] * 8, xy[2] * 8)
  end

  local manifest = string.format([[
return {
  format_version = %d,
  reel_icons = { width = %d, height = %d, frames = %d, frame_h = %d },
  clefairy = { width = %d, height = %d, frames = %d, frame_h = %d },
  digits = { width = %d, height = %d, frames = %d, frame_h = %d },
  bg = { width = %d, height = %d },
  combos_window = { width = %d, height = %d },
  payout_lights = { width = %d, height = %d, frames = %d, frame_h = %d, x = %d, y = %d },
  match_lines = { width = %d, height = %d, x = %d, y = %d },
  button_pressed = { width = %d, height = %d, at = { %s } },
}
]],
    SlotMachineExtract.FORMAT_VERSION,
    ICON_SIZE, ICON_SIZE * ICON_FRAMES, ICON_FRAMES, ICON_SIZE,
    CLEFAIRY_SIZE, CLEFAIRY_SIZE * CLEFAIRY_FRAMES, CLEFAIRY_FRAMES, CLEFAIRY_SIZE,
    DIGIT_W, DIGIT_H * DIGIT_FRAMES, DIGIT_FRAMES, DIGIT_H,
    SCREEN_W, SCREEN_H,
    SCREEN_W, SCREEN_H,
    lightsW, lightsH * 3, 3, lightsH, LIGHTS_TILE_X * 8, LIGHTS_TILE_Y * 8,
    LINES_TILES_W * 8, LINES_TILES_H * 8, LINES_TILE_X * 8, LINES_TILE_Y * 8,
    BUTTON_W, BUTTON_H, table.concat(buttons, ", "))
  cache:write(root .. "/manifest.lua", manifest)

  print(string.format(
    "[slot_machine_extract] %d reel icons, %d clefairy frames, %d digits, bg %dx%d -> %s",
    ICON_FRAMES, CLEFAIRY_FRAMES, DIGIT_FRAMES, SCREEN_W, SCREEN_H, root))
  return { root = root, icons = ICON_FRAMES, digits = DIGIT_FRAMES }
end

function SlotMachineExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. SlotMachineExtract.CACHE_SUB
  if not (cache and cache.exists and cache.read) then return false end
  if not cache:exists(root .. "/manifest.lua") then return false end
  local body = cache:read(root .. "/manifest.lua")
  if type(body) ~= "string" then return false end
  local chunk = load(body, "@" .. root .. "/manifest.lua", "t", {})
  if not chunk then return false end
  local ok, man = pcall(chunk)
  if not ok or type(man) ~= "table" then return false end
  if man.format_version ~= SlotMachineExtract.FORMAT_VERSION then return false end
  local icons = cache:read(root .. "/reel_icons.rgba")
  if type(icons) ~= "string" or #icons ~= ICON_SIZE * ICON_SIZE * 4 * ICON_FRAMES then
    return false
  end
  local bg = cache:read(root .. "/bg.rgba")
  return type(bg) == "string" and #bg == SCREEN_W * SCREEN_H * 4
end

return SlotMachineExtract
