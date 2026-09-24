-- src/berry_crush.c:647, src/graphics.c:1378

local Versions = require("src.import.gba.versions")
local AssetPack = require("src.import.gba.asset_pack")

local BerryCrushExtract = {}

BerryCrushExtract.CACHE_SUB = "berry_crush"
BerryCrushExtract.FORMAT_VERSION = 1

-- src/berry_crush.c:2554
local BG_BANKS = 12
local BG_TILES = 256
local NUM_BERRIES = 43
local NUM_PLAYERS = 5
local TILE_SHEET_COLS = 16

-- src/berry_crush.c:745
local SHEETS = {
  { key = "crusher_base", gfx = "BC_CORE_GFX", pal = "BC_CORE_PAL", bytes = 0x800, fw = 64, fh = 64, frames = 1 },
  { key = "impact", gfx = "BC_IMPACT_GFX", pal = "BC_EFFECT_PAL", bytes = 0xE00, fw = 32, fh = 32, frames = 7 },
  { key = "sparkle", gfx = "BC_SPARKLE_GFX", pal = "BC_EFFECT_PAL", bytes = 0x700, fw = 16, fh = 16, frames = 14 },
  { key = "timer_digits", gfx = "BC_TIMER_GFX", pal = "BC_TIMER_PAL", bytes = 0x2C0, fw = 8, fh = 16, frames = 11 },
}

-- src/berry_crush.c:500
local LAYERS = {
  { key = "crusher_top", map = "BC_CRUSHER_TOP_MAP", bg = 1, screenSize = 2, w = 256, h = 80, alpha0 = true },
  { key = "container_cap", map = "BC_CONTAINER_CAP_MAP", bg = 2, screenSize = 0, w = 256, h = 160, alpha0 = true },
  { key = "bg", map = "BC_BG_MAP", bg = 3, screenSize = 0, w = 256, h = 256, alpha0 = false },
}

-- src/berry_crush.c:3277
local NAME_WIN_W, NAME_WIN_H = 10, 2

local function need(buf, n, what)
  if AssetPack.len(buf) < n then
    error(string.format("berry_crush: %s decompressed to %d bytes, want %d", what, AssetPack.len(buf), n))
  end
  return buf
end

local function tables(rom)
  local P = AssetPack
  return {
    berry_data = P.structs(rom, Versions.BC_BERRY_DATA, 4, NUM_BERRIES, {
      { "difficulty", "u8", 0 }, { "powder", "u16", 2 },
    }),
    sync_press_bonus = P.array(rom, Versions.BC_SYNC_PRESS_BONUS, "u8", NUM_PLAYERS),
    intro_outro_vibration = P.grid(rom, Versions.BC_INTRO_OUTRO_VIBRATION, "s8", { 5, 7 }),
    vibration = P.grid(rom, Versions.BC_VIBRATION, "u8", { NUM_PLAYERS, 4 }),
    sparkle_thresholds = P.grid(rom, Versions.BC_SPARKLE_THRESHOLDS, "u8", { NUM_PLAYERS - 1, 4 }),
    big_sparkle_thresholds = P.array(rom, Versions.BC_BIG_SPARKLE_THRESHOLDS, "u8", NUM_PLAYERS - 1),
    received_player_bitmasks = P.array(rom, Versions.BC_RECEIVED_PLAYER_BITMASKS, "u8", NUM_PLAYERS - 1),
    bg_templates = P.bgTemplates(rom, Versions.BC_BG_TEMPLATES, 4),
    text_colors = P.grid(rom, Versions.BC_TEXT_COLORS, "u8", { 6, 3 }),
    win_rankings = P.windowTemplates(rom, Versions.BC_WIN_RANKINGS, 1)[1],
    win_player_names = P.windowTemplates(rom, Versions.BC_WIN_PLAYER_NAMES, NUM_PLAYERS),
    win_results = P.windowTemplates(rom, Versions.BC_WIN_RESULTS, 3),
    results_window_heights = P.grid(rom, Versions.BC_RESULTS_WINDOW_HEIGHTS, "u8", { 2, NUM_PLAYERS - 1 }),
    pressing_speed_table = P.array(rom, Versions.BC_PRESSING_SPEED_TABLE, "u32", 8),
    player_id_to_pos_id = P.grid(rom, Versions.BC_PLAYER_ID_TO_POS_ID, "u8", { NUM_PLAYERS - 1, NUM_PLAYERS }),
    player_coords = P.structs(rom, Versions.BC_PLAYER_COORDS, 12, NUM_PLAYERS, {
      { "playerId", "u8", 0 }, { "windowGfxX", "u8", 1 }, { "windowGfxY", "u8", 2 },
      { "impactXOffset", "s16", 4 }, { "impactYOffset", "s16", 6 },
      { "berryXOffset", "s16", 8 }, { "berryXDest", "s16", 10 },
    }),
    impact_coords = P.grid(rom, Versions.BC_IMPACT_COORDS, "s8", { 3, 2 }),
    sparkle_coords = P.grid(rom, Versions.BC_SPARKLE_COORDS, "s8", { 11, 2 }),
    digit_templates = (function()
      local rows = P.structs(rom, Versions.BC_DIGIT_TEMPLATES, 16, 3, {
        { "flags", "u8", 0 }, { "oamCount", "u8", 1 }, { "xDelta", "u8", 2 },
        { "x", "s16", 4 }, { "y", "s16", 6 },
      })
      for _, r in ipairs(rows) do
        r.strConvMode = r.flags % 4
        r.shape = math.floor(r.flags / 4) % 4
        r.size = math.floor(r.flags / 16) % 4
        r.priority = math.floor(r.flags / 64) % 4
        r.flags = nil
      end
      return rows
    end)(),
  }
end

function BerryCrushExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or AssetPack.defaultRoot()) .. "/" .. BerryCrushExtract.CACHE_SUB
  local man = { format_version = BerryCrushExtract.FORMAT_VERSION, _palettes = {}, _tiles = {} }

  local bgBanks = AssetPack.banks(rom, Versions.BC_CRUSHER_PAL, BG_BANKS)
  local bgGfx = AssetPack.pad(need(AssetPack.lz(rom, Versions.BC_CRUSHER_GFX), BG_TILES * 32, "crusher tiles"), BG_TILES * 32)
  cache:write(root .. "/crusher.4bpp", AssetPack.bytes(bgGfx))
  cache:write(root .. "/crusher.pal", AssetPack.palRgb(bgBanks, 0, BG_BANKS))
  man._palettes.crusher = { file = "crusher.pal", banks = BG_BANKS }
  man._tiles.crusher = { file = "crusher.4bpp", count = BG_TILES }
  local sheetRgba, sheetW, sheetH = AssetPack.tileSheet(bgGfx, bgBanks[0], BG_TILES, TILE_SHEET_COLS)
  cache:write(root .. "/crusher.rgba", sheetRgba)
  man.crusher = {
    file = "crusher.rgba", kind = "tiles", width = sheetW, height = sheetH,
    tile_count = BG_TILES, columns = TILE_SHEET_COLS, palette = "crusher.pal", bank = 0,
  }

  for _, L in ipairs(LAYERS) do
    local raw = AssetPack.lz(rom, Versions[L.map])
    local map, mapW, mapH = AssetPack.linearize(raw, L.screenSize)
    cache:write(root .. "/" .. L.key .. ".bin", AssetPack.bytes(raw))
    cache:write(root .. "/" .. L.key .. ".rgba", AssetPack.bg(bgGfx, bgBanks, map, mapW, L.w, L.h, {
      alpha0 = L.alpha0, backdrop = (not L.alpha0) and bgBanks[0][0] or nil,
    }))
    man[L.key] = {
      file = L.key .. ".rgba", kind = "bg", width = L.w, height = L.h, bg = L.bg,
      tilemap = L.key .. ".bin", tilemap_bytes = AssetPack.len(raw),
      screen_size = L.screenSize, map_w = mapW, map_h = mapH,
      tiles = "crusher.4bpp", palette = "crusher.pal", transparent0 = L.alpha0,
    }
  end

  local winMap = AssetPack.lz(rom, Versions.BC_TEXT_WINDOWS_MAP)
  cache:write(root .. "/text_windows.bin", AssetPack.bytes(winMap))
  cache:write(root .. "/text_windows.rgba", AssetPack.bg(bgGfx, bgBanks, winMap, NAME_WIN_W,
    NAME_WIN_W * 8, NAME_WIN_H * 8 * NUM_PLAYERS, {}))
  man.text_windows = {
    file = "text_windows.rgba", kind = "bg", width = NAME_WIN_W * 8, height = NAME_WIN_H * 8 * NUM_PLAYERS,
    frames = NUM_PLAYERS, frame_w = NAME_WIN_W * 8, frame_h = NAME_WIN_H * 8, bg = 3,
    tilemap = "text_windows.bin", map_w = NAME_WIN_W, map_h = NAME_WIN_H * NUM_PLAYERS,
    tiles = "crusher.4bpp", palette = "crusher.pal",
  }

  for _, S in ipairs(SHEETS) do
    local bank = AssetPack.banks(rom, Versions[S.pal], 1)[0]
    local gfx = need(AssetPack.lz(rom, Versions[S.gfx]), S.bytes, S.key)
    local tilesPer = (S.fw / 8) * (S.fh / 8)
    cache:write(root .. "/" .. S.key .. ".rgba",
      AssetPack.strip(gfx, bank, 0, tilesPer, S.fw, S.fh, S.frames))
    local palKey = S.pal:lower():gsub("^bc_", ""):gsub("_pal$", "")
    if not man._palettes[palKey] then
      cache:write(root .. "/" .. palKey .. ".pal", AssetPack.palRgb({ [0] = bank }, 0, 1))
      man._palettes[palKey] = { file = palKey .. ".pal", banks = 1 }
    end
    man[S.key] = {
      file = S.key .. ".rgba", kind = "sprite", width = S.fw, height = S.fh * S.frames,
      frame_w = S.fw, frame_h = S.fh, frames = S.frames, tiles_per_frame = tilesPer,
      palette = palKey .. ".pal",
    }
  end

  cache:write(root .. "/tables.lua", AssetPack.serialize(tables(rom)))
  man._tables = "tables.lua"
  cache:write(root .. "/manifest.lua", AssetPack.serialize(man))
  print(string.format("[berry_crush_extract] %d layers, %d sprite sheets -> %s", #LAYERS + 1, #SHEETS, root))
  return { root = root }
end

function BerryCrushExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or AssetPack.defaultRoot()) .. "/" .. BerryCrushExtract.CACHE_SUB
  local man = AssetPack.loadManifest(cache, root .. "/manifest.lua")
  if not man or man.format_version ~= BerryCrushExtract.FORMAT_VERSION then return false end
  if not AssetPack.sizedFile(cache, root .. "/bg.rgba", 256 * 256 * 4) then return false end
  if not AssetPack.sizedFile(cache, root .. "/crusher_base.rgba", 64 * 64 * 4) then return false end
  return cache:exists(root .. "/tables.lua")
end

return BerryCrushExtract
