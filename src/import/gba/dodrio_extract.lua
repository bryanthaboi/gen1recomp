-- src/dodrio_berry_picking.c:3323

local Versions = require("src.import.gba.versions")
local AssetPack = require("src.import.gba.asset_pack")

local DodrioExtract = {}

DodrioExtract.CACHE_SUB = "dodrio_berry_picking"
DodrioExtract.FORMAT_VERSION = 1

local NUM_PLAYERS = 5
local NUM_COLUMNS = 11

-- src/dodrio_berry_picking.c:4929-4938
local BG_BANKS = 2
local SCENERY_TILES = 128
local TREE_TILES = 208

-- src/dodrio_berry_picking.c:3088
local LAYERS = {
  { key = "bg", map = "DBP_BG_MAP", gfx = "scenery", bg = 3, screenSize = 0, w = 256, h = 160, alpha0 = false },
  { key = "tree_border_left", map = "DBP_TREE_LEFT_MAP", gfx = "tree", bg = 1, screenSize = 1, w = 256, h = 160, alpha0 = true },
  { key = "tree_border_right", map = "DBP_TREE_RIGHT_MAP", gfx = "tree", bg = 2, screenSize = 1, w = 256, h = 160, alpha0 = true },
}

-- src/dodrio_berry_picking.c:3555
local SHEETS = {
  { key = "dodrio", gfx = "DBP_DODRIO_GFX", pal = "DBP_DODRIO_PAL", bytes = 0x3000, fw = 64, fh = 64, frames = 6 },
  { key = "dodrio_shiny", gfx = "DBP_DODRIO_GFX", pal = "DBP_DODRIO_SHINY_PAL", bytes = 0x3000, fw = 64, fh = 64, frames = 6 },
  { key = "status", gfx = "DBP_STATUS_GFX", pal = "DBP_STATUS_PAL", bytes = 0x180, fw = 16, fh = 16, frames = 3 },
  { key = "berries", gfx = "DBP_BERRIES_GFX", pal = "DBP_BERRIES_PAL", bytes = 0x480, fw = 16, fh = 16, frames = 9 },
  { key = "cloud", gfx = "DBP_CLOUD_GFX", pal = "DBP_CLOUD_PAL", bytes = 0x400, fw = 64, fh = 32, frames = 1 },
}

local function need(buf, n, what)
  if AssetPack.len(buf) < n then
    error(string.format("dodrio: %s decompressed to %d bytes, want %d", what, AssetPack.len(buf), n))
  end
  return buf
end

local function winCoords(rom, off, n)
  return AssetPack.structs(rom, off, 4, n, { { "left", "u8", 0 }, { "top", "u8", 1 } })
end

local function tables(rom)
  local P = AssetPack
  return {
    active_column_map = P.grid(rom, Versions.DBP_ACTIVE_COLUMN_MAP, "u8", { NUM_PLAYERS, NUM_PLAYERS, NUM_COLUMNS }),
    head_to_column_map = P.grid(rom, Versions.DBP_HEAD_TO_COLUMN_MAP, "u8", { NUM_PLAYERS, NUM_PLAYERS, 3 }),
    neighbor_map = P.grid(rom, Versions.DBP_NEIGHBOR_MAP, "u8", { NUM_PLAYERS, NUM_PLAYERS, 3 }),
    player_id_at_column = P.grid(rom, Versions.DBP_PLAYER_ID_AT_COLUMN, "u8", { NUM_PLAYERS, NUM_COLUMNS }),
    unshared_columns = P.grid(rom, Versions.DBP_UNSHARED_COLUMNS, "u8", { NUM_PLAYERS, NUM_PLAYERS }),
    berry_fall_delays = P.grid(rom, Versions.DBP_BERRY_FALL_DELAYS, "u8", { 3, 3 }),
    tree_border_x = P.array(rom, Versions.DBP_TREE_BORDER_X, "u8", NUM_PLAYERS),
    difficulty_thresholds = P.array(rom, Versions.DBP_DIFFICULTY_THRESHOLDS, "u8", 7),
    prize_berry_ids = P.grid(rom, Versions.DBP_PRIZE_BERRY_IDS, "u8", { 3, 10 }),
    berry_score_multipliers = P.array(rom, Versions.DBP_BERRY_SCORE_MULT, "s16", 4),
    record_num_max_digits = P.array(rom, Versions.DBP_RECORD_MAX_DIGITS, "u8", 3),
    record_text_y = P.grid(rom, Versions.DBP_RECORD_TEXT_Y, "u8", { 3, 2 }),
    record_num_y = P.grid(rom, Versions.DBP_RECORD_NUM_Y, "u8", { 3, 2 }),
    berry_icon_x = P.array(rom, Versions.DBP_BERRY_ICON_X, "s16", 4),
    cloud_move_delays = P.array(rom, Versions.DBP_CLOUD_MOVE_DELAYS, "u8", 2),
    cloud_start = P.grid(rom, Versions.DBP_CLOUD_START, "s16", { 2, 2 }),
    text_colors = P.grid(rom, Versions.DBP_TEXT_COLORS, "u8", { 4, 3 }),
    name_window_coords = {
      winCoords(rom, Versions.DBP_NAME_WIN_1P, 1),
      winCoords(rom, Versions.DBP_NAME_WIN_2P, 2),
      winCoords(rom, Versions.DBP_NAME_WIN_3P, 3),
      winCoords(rom, Versions.DBP_NAME_WIN_4P, 4),
      winCoords(rom, Versions.DBP_NAME_WIN_5P, 5),
    },
    results_x = P.array(rom, Versions.DBP_RESULTS_X, "u16", 4),
    results_y = P.array(rom, Versions.DBP_RESULTS_Y, "u16", 5),
    ranking_y = P.array(rom, Versions.DBP_RANKING_Y, "u16", 5),
    bg_templates = P.bgTemplates(rom, Versions.DBP_BG_TEMPLATES, 4),
    win_records = P.windowTemplates(rom, Versions.DBP_WIN_RECORDS, 1)[1],
    win_results = P.windowTemplates(rom, Versions.DBP_WIN_RESULTS, 2),
    win_prize = P.windowTemplates(rom, Versions.DBP_WIN_PRIZE, 1)[1],
    win_play_again = P.windowTemplates(rom, Versions.DBP_WIN_PLAY_AGAIN, 2),
    win_dropped_out = P.windowTemplates(rom, Versions.DBP_WIN_DROPPED_OUT, 1)[1],
    win_comm_standby = P.windowTemplates(rom, Versions.DBP_WIN_COMM_STANDBY, 1)[1],
  }
end

function DodrioExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or AssetPack.defaultRoot()) .. "/" .. DodrioExtract.CACHE_SUB
  local man = { format_version = DodrioExtract.FORMAT_VERSION, _palettes = {}, _tiles = {} }

  local banks = AssetPack.banks(rom, Versions.DBP_BG_PAL, BG_BANKS)
  cache:write(root .. "/bg.pal", AssetPack.palRgb(banks, 0, BG_BANKS))
  man._palettes.bg = { file = "bg.pal", banks = BG_BANKS }

  local gfx = {
    scenery = AssetPack.pad(need(AssetPack.lz(rom, Versions.DBP_BG_GFX), SCENERY_TILES * 32, "scenery tiles"), SCENERY_TILES * 32),
    tree = AssetPack.pad(need(AssetPack.lz(rom, Versions.DBP_TREE_BORDER_GFX), TREE_TILES * 32, "tree tiles"), TREE_TILES * 32),
  }
  cache:write(root .. "/scenery.4bpp", AssetPack.bytes(gfx.scenery))
  cache:write(root .. "/tree_border.4bpp", AssetPack.bytes(gfx.tree))
  man._tiles.scenery = { file = "scenery.4bpp", count = SCENERY_TILES }
  man._tiles.tree = { file = "tree_border.4bpp", count = TREE_TILES }

  for _, L in ipairs(LAYERS) do
    local raw = AssetPack.lz(rom, Versions[L.map])
    local map, mapW, mapH = AssetPack.linearize(raw, L.screenSize)
    cache:write(root .. "/" .. L.key .. ".bin", AssetPack.bytes(raw))
    cache:write(root .. "/" .. L.key .. ".rgba", AssetPack.bg(gfx[L.gfx], banks, map, mapW, L.w, L.h, {
      alpha0 = L.alpha0, backdrop = (not L.alpha0) and banks[0][0] or nil,
    }))
    man[L.key] = {
      file = L.key .. ".rgba", kind = "bg", width = L.w, height = L.h, bg = L.bg,
      tilemap = L.key .. ".bin", tilemap_bytes = AssetPack.len(raw),
      screen_size = L.screenSize, map_w = mapW, map_h = mapH,
      tiles = L.gfx == "tree" and "tree_border.4bpp" or "scenery.4bpp",
      palette = "bg.pal", transparent0 = L.alpha0,
    }
  end

  for _, S in ipairs(SHEETS) do
    local bank = AssetPack.banks(rom, Versions[S.pal], 1)[0]
    local sheet = need(AssetPack.lz(rom, Versions[S.gfx]), S.bytes, S.key)
    local tilesPer = (S.fw / 8) * (S.fh / 8)
    cache:write(root .. "/" .. S.key .. ".rgba",
      AssetPack.strip(sheet, bank, 0, tilesPer, S.fw, S.fh, S.frames))
    cache:write(root .. "/" .. S.key .. ".pal", AssetPack.palRgb({ [0] = bank }, 0, 1))
    man._palettes[S.key] = { file = S.key .. ".pal", banks = 1 }
    man[S.key] = {
      file = S.key .. ".rgba", kind = "sprite", width = S.fw, height = S.fh * S.frames,
      frame_w = S.fw, frame_h = S.fh, frames = S.frames, tiles_per_frame = tilesPer,
      palette = S.key .. ".pal",
    }
  end

  cache:write(root .. "/tables.lua", AssetPack.serialize(tables(rom)))
  man._tables = "tables.lua"
  cache:write(root .. "/manifest.lua", AssetPack.serialize(man))
  print(string.format("[dodrio_extract] %d layers, %d sprite sheets -> %s", #LAYERS, #SHEETS, root))
  return { root = root }
end

function DodrioExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or AssetPack.defaultRoot()) .. "/" .. DodrioExtract.CACHE_SUB
  local man = AssetPack.loadManifest(cache, root .. "/manifest.lua")
  if not man or man.format_version ~= DodrioExtract.FORMAT_VERSION then return false end
  if not AssetPack.sizedFile(cache, root .. "/bg.rgba", 256 * 160 * 4) then return false end
  if not AssetPack.sizedFile(cache, root .. "/dodrio.rgba", 64 * 64 * 6 * 4) then return false end
  return cache:exists(root .. "/tables.lua")
end

return DodrioExtract
