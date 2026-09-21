-- src/link_rfu_3.c:34, src/union_room_chat_objects.c:30
-- src/wireless_communication_status_screen.c:50

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")
local BgBake = require("src.import.gba.bg_bake")

local LinkArtExtract = {}

LinkArtExtract.UNION_SUB = "union_room"
LinkArtExtract.STATUS_SUB = "wireless_status"
LinkArtExtract.FORMAT_VERSION = 1

local SCREEN_W, SCREEN_H = 240, 160
-- src/link_rfu_3.c:434
local ICON_SIZE, ICON_FRAMES = 16, 7
-- src/union_room_chat_objects.c:68
local SELECTOR_W, SELECTOR_H, SELECTOR_FRAMES = 64, 32, 4
-- src/union_room_chat_objects.c:140
local ICONS_W, ICONS_H, ICONS_FRAMES = 32, 16, 4
-- src/union_room_chat_objects.c:110
local CURSOR_W, CURSOR_H = 8, 16
-- src/union_room_chat_objects.c:172
local RBUTTON_SIZE = 16
-- src/wireless_communication_status_screen.c:50
local STATUS_PAL_BANKS = 16

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

local function frames_rgba(gfx, bank, tileStep, fw, fh, frames)
  local parts = {}
  for f = 0, frames - 1 do
    parts[#parts + 1] = BgBake.bakeSpriteRgba(gfx, bank, f * tileStep, fw, fh, false, false)
  end
  return table.concat(parts)
end

function LinkArtExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local union = cacheRoot .. "/" .. LinkArtExtract.UNION_SUB
  local status = cacheRoot .. "/" .. LinkArtExtract.STATUS_SUB
  local function get(i) return rom:get(i) end

  local iconGfx = Lz77.decompress(get, Versions.WIRELESS_ICON_GFX)
  local iconBank = pal_banks(rom, Versions.WIRELESS_ICON_PAL, 1)[0]
  cache:write(union .. "/wireless_icon.rgba",
    frames_rgba(iconGfx, iconBank, 4, ICON_SIZE, ICON_SIZE, ICON_FRAMES))

  local bgGfx = Lz77.decompress(get, Versions.UR_CHAT_BG_GFX)
  local bgMap = Lz77.decompress(get, Versions.UR_CHAT_BG_TILEMAP)
  local bgBank = pal_banks(rom, Versions.UR_CHAT_BG_PAL, 1)
  cache:write(union .. "/chat_bg.rgba",
    BgBake.bakeRegionRgba(bgGfx, bgBank, bgMap, SCREEN_W, SCREEN_H, {}))

  local panelGfx = Lz77.decompress(get, Versions.UR_CHAT_PANEL_GFX)
  local panelMap = Lz77.decompress(get, Versions.UR_CHAT_PANEL_TILEMAP)
  local panelBank = pal_banks(rom, Versions.UR_CHAT_PANEL_PAL, 1)
  cache:write(union .. "/chat_panel.rgba", BgBake.bakeRegionRgba(panelGfx, panelBank,
    panelMap, SCREEN_W, SCREEN_H, { bankOffset = 7, alpha0 = true }))

  local objBank = pal_banks(rom, Versions.UR_CHAT_OBJECTS_PAL, 1)[0]
  cache:write(union .. "/chat_icons.rgba",
    frames_rgba(Lz77.decompress(get, Versions.UR_CHAT_ICONS_GFX), objBank, 8,
      ICONS_W, ICONS_H, ICONS_FRAMES))
  cache:write(union .. "/chat_selector_cursor.rgba",
    frames_rgba(Lz77.decompress(get, Versions.UR_CHAT_SELECTOR_GFX), objBank, 32,
      SELECTOR_W, SELECTOR_H, SELECTOR_FRAMES))
  cache:write(union .. "/chat_text_entry_cursor.rgba",
    frames_rgba(Lz77.decompress(get, Versions.UR_CHAT_TEXT_CURSOR_GFX), objBank, 2,
      CURSOR_W, CURSOR_H, 1))
  cache:write(union .. "/chat_char_select_cursor.rgba",
    frames_rgba(Lz77.decompress(get, Versions.UR_CHAT_CHAR_CURSOR_GFX), objBank, 2,
      CURSOR_W, CURSOR_H, 1))
  cache:write(union .. "/chat_r_button.rgba",
    frames_rgba(Lz77.decompress(get, Versions.UR_CHAT_R_BUTTON_GFX), objBank, 4,
      RBUTTON_SIZE, RBUTTON_SIZE, 1))

  cache:write(union .. "/manifest.lua", string.format([[
return {
  format_version = %d,
  wireless_icon = { width = %d, height = %d, frames = %d, frame_h = %d },
  chat_bg = { width = %d, height = %d },
  chat_panel = { width = %d, height = %d },
  chat_icons = { width = %d, height = %d, frames = %d, frame_h = %d },
  chat_selector_cursor = { width = %d, height = %d, frames = %d, frame_h = %d },
  chat_text_entry_cursor = { width = %d, height = %d },
  chat_char_select_cursor = { width = %d, height = %d },
  chat_r_button = { width = %d, height = %d },
}
]],
    LinkArtExtract.FORMAT_VERSION,
    ICON_SIZE, ICON_SIZE * ICON_FRAMES, ICON_FRAMES, ICON_SIZE,
    SCREEN_W, SCREEN_H,
    SCREEN_W, SCREEN_H,
    ICONS_W, ICONS_H * ICONS_FRAMES, ICONS_FRAMES, ICONS_H,
    SELECTOR_W, SELECTOR_H * SELECTOR_FRAMES, SELECTOR_FRAMES, SELECTOR_H,
    CURSOR_W, CURSOR_H,
    CURSOR_W, CURSOR_H,
    RBUTTON_SIZE, RBUTTON_SIZE))

  local statusGfx = Lz77.decompress(get, Versions.WIRELESS_STATUS_GFX)
  local statusMap = Lz77.decompress(get, Versions.WIRELESS_STATUS_TILEMAP)
  local statusBanks = pal_banks(rom, Versions.WIRELESS_STATUS_PALS, STATUS_PAL_BANKS)
  -- src/wireless_communication_status_screen.c:226
  cache:write(status .. "/bg.rgba", BgBake.bakeRegionRgba(statusGfx,
    { [0] = statusBanks[0] }, statusMap, SCREEN_W, SCREEN_H, {}))

  local palParts = {}
  for b = 0, STATUS_PAL_BANKS - 1 do
    local bank = statusBanks[b] or {}
    for c = 0, 15 do
      local r, g, bl = BgBake.bgr555ToRgb8(bank[c] or 0)
      palParts[#palParts + 1] = string.char(r, g, bl)
    end
  end
  cache:write(status .. "/palettes.pal", table.concat(palParts))

  cache:write(status .. "/manifest.lua", string.format([[
return {
  format_version = %d,
  bg = { width = %d, height = %d },
  palettes = { banks = %d, colors = 16, bytes_per_color = 3, anim_first = 2, anim_count = 14 },
}
]], LinkArtExtract.FORMAT_VERSION, SCREEN_W, SCREEN_H, STATUS_PAL_BANKS))

  print(string.format(
    "[link_art_extract] %d wireless icon frames, chat screen %dx%d, status screen %dx%d -> %s",
    ICON_FRAMES, SCREEN_W, SCREEN_H, SCREEN_W, SCREEN_H, cacheRoot))
  return { union = union, status = status }
end

function LinkArtExtract.ready(cache, cacheRoot)
  local root = cacheRoot or default_cache_root()
  if not (cache and cache.exists and cache.read) then return false end
  local union = root .. "/" .. LinkArtExtract.UNION_SUB
  local status = root .. "/" .. LinkArtExtract.STATUS_SUB
  local body = cache:exists(union .. "/manifest.lua") and cache:read(union .. "/manifest.lua")
  if type(body) ~= "string" then return false end
  local chunk = load(body, "@" .. union .. "/manifest.lua", "t", {})
  if not chunk then return false end
  local ok, man = pcall(chunk)
  if not ok or type(man) ~= "table" then return false end
  if man.format_version ~= LinkArtExtract.FORMAT_VERSION then return false end
  local icon = cache:read(union .. "/wireless_icon.rgba")
  if type(icon) ~= "string" or #icon ~= ICON_SIZE * ICON_SIZE * 4 * ICON_FRAMES then
    return false
  end
  local bg = cache:read(status .. "/bg.rgba")
  return type(bg) == "string" and #bg == SCREEN_W * SCREEN_H * 4
end

return LinkArtExtract
