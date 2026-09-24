-- src/pokemon_jump.c:2901

local Versions = require("src.import.gba.versions")
local AssetPack = require("src.import.gba.asset_pack")

local PokemonJumpExtract = {}

PokemonJumpExtract.CACHE_SUB = "pokemon_jump"
PokemonJumpExtract.FORMAT_VERSION = 1

local NUM_PLAYERS = 5
local NUM_JUMP_MONS = 100

-- src/pokemon_jump.c:3042-3051
local BANK_SLOTS = {
  { slot = 0, pal = "PJ_BG_PAL", key = "bg" },
  { slot = 1, pal = "PJ_BONUSES_PAL", key = "bonuses" },
  { slot = 2, pal = "PJ_INTERFACE_PAL", key = "interface" },
  { slot = 3, pal = "PJ_VENUSAUR_PAL", key = "venusaur" },
}

-- src/pokemon_jump.c:2915
local LAYERS = {
  { key = "bg", gfx = "PJ_BG_GFX", map = "PJ_BG_MAP", tiles = 63, bg = 3, screenSize = 0, w = 256, h = 160, alpha0 = false },
  { key = "venusaur", gfx = "PJ_VENUSAUR_GFX", map = "PJ_VENUSAUR_MAP", tiles = 128, bg = 2, screenSize = 2, w = 256, h = 512, alpha0 = true },
  { key = "bonuses", gfx = "PJ_BONUSES_GFX", map = "PJ_BONUSES_MAP", tiles = 170, bg = 1, screenSize = 3, w = 512, h = 512, alpha0 = true },
}

-- src/pokemon_jump.c:3807
local SHEETS = {
  { key = "vine1", gfx = "PJ_VINE1_GFX", bytes = 0x600, fw = 16, fh = 32, frames = 6 },
  { key = "vine2", gfx = "PJ_VINE2_GFX", bytes = 0xC00, fw = 32, fh = 32, frames = 6 },
  { key = "vine3", gfx = "PJ_VINE3_GFX", bytes = 0x600, fw = 32, fh = 16, frames = 6 },
  { key = "vine4", gfx = "PJ_VINE4_GFX", bytes = 0x600, fw = 32, fh = 16, frames = 6 },
  { key = "star", gfx = "PJ_STAR_GFX", bytes = 0x200, fw = 16, fh = 16, frames = 4, palOnly = "pal1" },
}

local function need(buf, n, what)
  if AssetPack.len(buf) < n then
    error(string.format("pokemon_jump: %s decompressed to %d bytes, want %d", what, AssetPack.len(buf), n))
  end
  return buf
end

local function coordPairs(rom, off, n, kind)
  return AssetPack.grid(rom, off, kind, { n, 2 })
end

local function tables(rom)
  local P = AssetPack
  return {
    jump_mons = P.structs(rom, Versions.PJ_MONS, 4, NUM_JUMP_MONS, {
      { "species", "u16", 0 }, { "jumpType", "u16", 2 },
    }),
    vine_base_speeds = P.array(rom, Versions.PJ_VINE_BASE_SPEEDS, "u16", 8),
    vine_speed_delays = P.array(rom, Versions.PJ_VINE_SPEED_DELAYS, "u16", 4),
    sound_effects = P.array(rom, Versions.PJ_SOUND_EFFECTS, "u16", NUM_PLAYERS - 1),
    jump_offsets = P.grid(rom, Versions.PJ_JUMP_OFFSETS, "s8", { 3, 48 }),
    score_bonuses = P.array(rom, Versions.PJ_SCORE_BONUSES, "s32", NUM_PLAYERS + 1),
    prize_items = P.array(rom, Versions.PJ_PRIZE_ITEMS, "u16", 8),
    prize_quantity = P.structs(rom, Versions.PJ_PRIZE_QUANTITY, 8, 5, {
      { "score", "u32", 0 }, { "quantity", "u32", 4 },
    }),
    bg_templates = P.bgTemplates(rom, Versions.PJ_BG_TEMPLATES, 4),
    window_templates = P.windowTemplates(rom, Versions.PJ_WINDOW_TEMPLATES, 2),
    win_records = P.windowTemplates(rom, Versions.PJ_WIN_RECORDS, 1)[1],
    venusaur_states = P.array(rom, Versions.PJ_VENUSAUR_STATES, "u8", 10),
    player_name_window_coords = {
      [2] = coordPairs(rom, Versions.PJ_NAME_WIN_2P, 2, "u16"),
      [3] = coordPairs(rom, Versions.PJ_NAME_WIN_3P, 3, "u16"),
      [4] = coordPairs(rom, Versions.PJ_NAME_WIN_4P, 4, "u16"),
      [5] = coordPairs(rom, Versions.PJ_NAME_WIN_5P, 5, "u16"),
    },
    mon_x_coords = {
      [2] = P.array(rom, Versions.PJ_MON_X_2P, "s16", 2),
      [3] = P.array(rom, Versions.PJ_MON_X_3P, "s16", 3),
      [4] = P.array(rom, Versions.PJ_MON_X_4P, "s16", 4),
      [5] = P.array(rom, Versions.PJ_MON_X_5P, "s16", 5),
    },
    vine_y = P.grid(rom, Versions.PJ_VINE_Y, "s16", { 4, 10 }),
    vine_x = P.array(rom, Versions.PJ_VINE_X, "s16", 8),
  }
end

function PokemonJumpExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or AssetPack.defaultRoot()) .. "/" .. PokemonJumpExtract.CACHE_SUB
  local man = { format_version = PokemonJumpExtract.FORMAT_VERSION, _palettes = {}, _tiles = {} }

  local banks = {}
  for _, B in ipairs(BANK_SLOTS) do
    banks[B.slot] = AssetPack.banks(rom, Versions[B.pal], 1)[0]
  end
  cache:write(root .. "/bg.pal", AssetPack.palRgb(banks, 0, #BANK_SLOTS))
  man._palettes.bg = { file = "bg.pal", banks = #BANK_SLOTS, slots = { bg = 0, bonuses = 1, interface = 2, venusaur = 3 } }

  for _, L in ipairs(LAYERS) do
    local gfx = AssetPack.pad(need(AssetPack.lz(rom, Versions[L.gfx]), L.tiles * 32, L.key .. " tiles"), L.tiles * 32)
    local raw = AssetPack.lz(rom, Versions[L.map])
    local map, mapW, mapH = AssetPack.linearize(raw, L.screenSize)
    cache:write(root .. "/" .. L.key .. ".4bpp", AssetPack.bytes(gfx))
    cache:write(root .. "/" .. L.key .. ".bin", AssetPack.bytes(raw))
    cache:write(root .. "/" .. L.key .. ".rgba", AssetPack.bg(gfx, banks, map, mapW, L.w, L.h, {
      alpha0 = L.alpha0, backdrop = (not L.alpha0) and banks[0][0] or nil,
    }))
    man._tiles[L.key] = { file = L.key .. ".4bpp", count = L.tiles }
    man[L.key] = {
      file = L.key .. ".rgba", kind = "bg", width = L.w, height = L.h, bg = L.bg,
      tilemap = L.key .. ".bin", tilemap_bytes = AssetPack.len(raw),
      screen_size = L.screenSize, map_w = mapW, map_h = mapH,
      tiles = L.key .. ".4bpp", palette = "bg.pal", transparent0 = L.alpha0,
    }
  end

  local spritePals = {
    pal1 = AssetPack.banks(rom, Versions.PJ_PAL1, 1)[0],
    pal2 = AssetPack.banks(rom, Versions.PJ_PAL2, 1)[0],
  }
  for key, bank in pairs(spritePals) do
    cache:write(root .. "/" .. key .. ".pal", AssetPack.palRgb({ [0] = bank }, 0, 1))
    man._palettes[key] = { file = key .. ".pal", banks = 1 }
  end

  for _, S in ipairs(SHEETS) do
    local sheet = need(AssetPack.lz(rom, Versions[S.gfx]), S.bytes, S.key)
    local tilesPer = (S.fw / 8) * (S.fh / 8)
    local variants = S.palOnly and { { S.key, S.palOnly } }
      or { { S.key, "pal1" }, { S.key .. "_pal2", "pal2" } }
    for _, v in ipairs(variants) do
      cache:write(root .. "/" .. v[1] .. ".rgba",
        AssetPack.strip(sheet, spritePals[v[2]], 0, tilesPer, S.fw, S.fh, S.frames))
      man[v[1]] = {
        file = v[1] .. ".rgba", kind = "sprite", width = S.fw, height = S.fh * S.frames,
        frame_w = S.fw, frame_h = S.fh, frames = S.frames, tiles_per_frame = tilesPer,
        palette = v[2] .. ".pal",
      }
    end
  end

  cache:write(root .. "/tables.lua", AssetPack.serialize(tables(rom)))
  man._tables = "tables.lua"
  cache:write(root .. "/manifest.lua", AssetPack.serialize(man))
  print(string.format("[pokemon_jump_extract] %d layers, %d sprite sheets -> %s", #LAYERS, #SHEETS, root))
  return { root = root }
end

function PokemonJumpExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or AssetPack.defaultRoot()) .. "/" .. PokemonJumpExtract.CACHE_SUB
  local man = AssetPack.loadManifest(cache, root .. "/manifest.lua")
  if not man or man.format_version ~= PokemonJumpExtract.FORMAT_VERSION then return false end
  if not AssetPack.sizedFile(cache, root .. "/bonuses.rgba", 512 * 512 * 4) then return false end
  if not AssetPack.sizedFile(cache, root .. "/vine2_pal2.rgba", 32 * 32 * 6 * 4) then return false end
  return cache:exists(root .. "/tables.lua")
end

return PokemonJumpExtract
