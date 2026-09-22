-- Bake FRLG battle interface chrome from ROM into data/generated/gba/pokemon/battle/.
-- Healthboxes are OAM-assembled (pret CreateBattlerHealthboxSprites): two side-by-side
-- sprites, not a flat 128-wide sheet blit.

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local BattleChromeExtract = {}

BattleChromeExtract.FORMAT_VERSION = 7
BattleChromeExtract.CACHE_SUB = "pokemon/battle"

-- src/battle_bg.c:439
BattleChromeExtract.TERRAIN_TABLE = 0x24EE34
BattleChromeExtract.TERRAIN_ENTRY_SIZE = 20
BattleChromeExtract.TERRAIN_KEYS = {
  [0] = "grass",
  [1] = "long_grass",
  [2] = "sand",
  [3] = "underwater",
  [4] = "water",
  [5] = "pond",
  [6] = "mountain",
  [7] = "cave",
  [8] = "building",
  [9] = "plain",
  [10] = "link",
  [11] = "gym",
  [12] = "leader",
  [13] = "indoor_2",
  [14] = "indoor_1",
  [15] = "lorelei",
  [16] = "bruno",
  [17] = "agatha",
  [18] = "lance",
  [19] = "champion",
}

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

local function byte_len(buf)
  if type(buf) == "string" then return #buf end
  if type(buf) ~= "table" then return 0 end
  return buf._len or #buf
end

local function bytes_to_array(tbl)
  if type(tbl) == "string" then
    local t = {}
    for i = 1, #tbl do t[i] = tbl:byte(i) end
    return t
  end
  if type(tbl) == "table" and tbl._ffi and tbl._len then
    local t = {}
    for i = 1, tbl._len do t[i] = tbl._ffi[i - 1] end
    return t
  end
  return tbl
end

local function load_pal(bytes, count)
  bytes = bytes_to_array(bytes)
  local pal = {}
  for c = 0, (count or 16) - 1 do
    local i = c * 2 + 1
    pal[c] = (bytes[i] or 0) + (bytes[i + 1] or 0) * 256
  end
  return pal
end

local function decode_tile_4bpp(tileBytes, out, baseX, baseY, stride, hflip, vflip)
  for row = 0, 7 do
    local srcRow = vflip and (7 - row) or row
    for bx = 0, 3 do
      local byte = tileBytes[srcRow * 4 + bx + 1] or 0
      local p0 = byte % 16
      local p1 = math.floor(byte / 16) % 16
      local x0 = bx * 2
      local x1 = x0 + 1
      if hflip then
        x0, x1 = 7 - x0, 7 - x1
      end
      out[(baseY + row) * stride + (baseX + x0) + 1] = p0
      out[(baseY + row) * stride + (baseX + x1) + 1] = p1
    end
  end
end

local function indices_to_rgba(indices, pal, w, h)
  local chunks = {}
  for i = 1, w * h do
    local idx = indices[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks)
end

--- GBA OAM multi-tile blit: tiles arranged row-major in an (tilesW × tilesH) grid.
local function blit_oam_rect(gfx, pal, tileStart, tilesW, tilesH, dest, destX, destY, destW)
  gfx = bytes_to_array(gfx)
  local tileCount = math.floor(byte_len(gfx) / 32)
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local ti = tileStart + ty * tilesW + tx
      if ti >= 0 and ti < tileCount then
        local tile = {}
        local base = ti * 32
        for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
        local tmp = {}
        for i = 1, 64 do tmp[i] = 0 end
        decode_tile_4bpp(tile, tmp, 0, 0, 8, false, false)
        for row = 0, 7 do
          for col = 0, 7 do
            local idx = tmp[row * 8 + col + 1] or 0
            if idx ~= 0 then
              local dx = destX + tx * 8 + col
              local dy = destY + ty * 8 + row
              dest[dy * destW + dx + 1] = idx
              -- stash palette via parallel not needed; single pal
            end
          end
        end
      end
    end
  end
end

--- Player singles: two 64×64 sprites, other at x+64 (SpriteCB_HealthBoxOther).
local function bake_player_healthbox(gfx, pal)
  local w, h = 128, 64
  local indices = {}
  for i = 1, w * h do indices[i] = 0 end
  blit_oam_rect(gfx, pal, 0, 8, 8, indices, 0, 0, w)
  blit_oam_rect(gfx, pal, 64, 8, 8, indices, 64, 0, w)
  return indices_to_rgba(indices, pal, w, h), w, h
end

--- Enemy singles: two 64×32 sprites (default OAM), other at x+64, tileNum+=32.
local function bake_enemy_healthbox(gfx, pal)
  local w, h = 128, 32
  local indices = {}
  for i = 1, w * h do indices[i] = 0 end
  blit_oam_rect(gfx, pal, 0, 8, 4, indices, 0, 0, w)
  blit_oam_rect(gfx, pal, 32, 8, 4, indices, 64, 0, w)
  return indices_to_rgba(indices, pal, w, h), w, h
end

-- pokefirered/src/battle_interface.c:568
local function bake_doubles_healthbox(gfx, pal)
  return bake_enemy_healthbox(gfx, pal)
end

BattleChromeExtract.DOUBLES_FILES = {
  player = "healthbox_doubles_player.rgba",
  opponent = "healthbox_doubles_opponent.rgba",
}

function BattleChromeExtract.bakeDoubles(get, cfg)
  cfg = cfg or Versions.BATTLE_UI
  if not (cfg.healthbox_doubles_player and cfg.healthbox_doubles_opponent) then return nil end
  local raw = {}
  for i = 0, 31 do raw[i + 1] = get(cfg.healthbox_pal + i) end
  local hbPal = load_pal(raw, 16)
  local playerRgba = bake_doubles_healthbox(Lz77.decompress(get, cfg.healthbox_doubles_player), hbPal)
  local opponentRgba = bake_doubles_healthbox(Lz77.decompress(get, cfg.healthbox_doubles_opponent), hbPal)
  return playerRgba, opponentRgba
end

BattleChromeExtract.HP_BOLD_FILE = "hp_bold_digits.rgba"
BattleChromeExtract.HP_BOLD_CHARS = "0123456789/"
BattleChromeExtract.HP_BOLD_W = 88
BattleChromeExtract.HP_BOLD_H = 8

-- pokefirered/src/text_printer.c:187
local function decode_bold_half_rows(get, base, dest, destX, stride)
  local map = { [0] = 0, 1, 3, 0 }
  for row = 0, 7 do
    local lo = get(base + row * 2) or 0
    local hi = get(base + row * 2 + 1) or 0
    for half = 0, 1 do
      local b = half == 0 and hi or lo
      for k = 0, 3 do
        local v = math.floor(b / 4 ^ (3 - k)) % 4
        dest[row * stride + destX + half * 4 + k + 1] = map[v]
      end
    end
  end
end

-- pokefirered/src/text.c:1688
function BattleChromeExtract.bakeHpBoldDigits(get, cfg)
  cfg = cfg or Versions.BATTLE_UI
  if not cfg.font_bold_glyphs then return nil end
  local raw = {}
  for i = 0, 31 do raw[i + 1] = get(cfg.healthbar_pal + i) end
  local barPal = load_pal(raw, 16)
  local w, h = BattleChromeExtract.HP_BOLD_W, BattleChromeExtract.HP_BOLD_H
  local indices = {}
  for i = 1, w * h do indices[i] = 0 end
  local codes = { 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xBA }
  for n, id in ipairs(codes) do
    local glyph = cfg.font_bold_glyphs + 2 * (0x100 * math.floor(id / 16) + 8 * (id % 16))
    -- pokefirered/src/battle_interface.c:900
    decode_bold_half_rows(get, glyph + 2 * 0x80, indices, (n - 1) * 8, w)
  end
  return indices_to_rgba(indices, barPal, w, h)
end

function BattleChromeExtract.runDoubles(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. BattleChromeExtract.CACHE_SUB
  local get = function(i) return rom:get(i) end
  local playerRgba, opponentRgba = BattleChromeExtract.bakeDoubles(get, opts.cfg)
  if not playerRgba then return false end
  cache:write(root .. "/" .. BattleChromeExtract.DOUBLES_FILES.player, playerRgba)
  cache:write(root .. "/" .. BattleChromeExtract.DOUBLES_FILES.opponent, opponentRgba)
  local boldRgba = BattleChromeExtract.bakeHpBoldDigits(get, opts.cfg)
  if boldRgba then
    cache:write(root .. "/" .. BattleChromeExtract.HP_BOLD_FILE, boldRgba)
  end
  return true
end

local function bake_sheet_rgba(gfx, pal, w, h)
  gfx = bytes_to_array(gfx)
  local tilesW, tilesH = math.floor(w / 8), math.floor(h / 8)
  local indices = {}
  for i = 1, w * h do indices[i] = 0 end
  local ti = 0
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local tile = {}
      local base = ti * 32
      for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
      decode_tile_4bpp(tile, indices, tx * 8, ty * 8, w, false, false)
      ti = ti + 1
    end
  end
  return indices_to_rgba(indices, pal, w, h)
end

local function bake_tilemap_rgba(gfx, palBytes, map, mapTilesW, mapTilesH, opts)
  opts = opts or {}
  gfx = bytes_to_array(gfx)
  map = bytes_to_array(map)
  palBytes = bytes_to_array(palBytes)
  local tileCount = math.floor(#gfx / 32)
  local bankCount = math.max(1, math.floor(#palBytes / 32))
  local banks = {}
  for b = 0, bankCount - 1 do
    local slice = {}
    for i = 1, 32 do slice[i] = palBytes[b * 32 + i] or 0 end
    banks[b] = load_pal(slice, 16)
  end

  local W, H = mapTilesW * 8, mapTilesH * 8
  local indices, pals = {}, {}
  for i = 1, W * H do indices[i] = 0; pals[i] = 0 end
  for ty = 0, mapTilesH - 1 do
    for tx = 0, mapTilesW - 1 do
      local mi = (ty * mapTilesW + tx) * 2 + 1
      local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local palNum = math.floor(entry / 4096) % 16
      if tileId >= tileCount then tileId = 0 end
      local tile = {}
      local base = tileId * 32
      for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
      local tmp = {}
      for i = 1, 64 do tmp[i] = 0 end
      decode_tile_4bpp(tile, tmp, 0, 0, 8, hflip, vflip)
      for row = 0, 7 do
        for col = 0, 7 do
          local di = (ty * 8 + row) * W + (tx * 8 + col) + 1
          indices[di] = tmp[row * 8 + col + 1] or 0
          pals[di] = palNum
        end
      end
    end
  end
  local transparent0 = opts.transparent0 ~= false
  -- Terrain pals load at BG_PLTT_ID(2); textbox at BG_PLTT_ID(0).
  local bgPalBase = opts.bgPalBase or 0
  local chunks = {}
  for i = 1, W * H do
    local idx = indices[i] or 0
    if idx == 0 and transparent0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local palNum = pals[i] or 0
      local bi = palNum - bgPalBase
      if bi < 0 or bi >= bankCount then
        bi = math.max(0, math.min(bankCount - 1, palNum))
      end
      local bank = banks[bi] or banks[0]
      local r, g, b = bgr555_to_rgb8(bank[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks), W, H
end

local function read_raw(rom, off, n)
  local t = {}
  for i = 0, n - 1 do t[i + 1] = rom:get(off + i) end
  return t
end

local function split_terrain_layers(fullRgba, mapBytes)
  mapBytes = bytes_to_array(mapBytes)
  local bgTilePerRow = {}
  for ty = 0, 19 do
    local counts = {}
    for tx = 0, 31 do
      local mi = (ty * 32 + tx) * 2 + 1
      local entry = (mapBytes[mi] or 0) + (mapBytes[mi + 1] or 0) * 256
      local tid = entry % 1024
      counts[tid] = (counts[tid] or 0) + 1
    end
    local maxCount, bestTid = -1, 0
    for tid, count in pairs(counts) do
      if count > maxCount then maxCount, bestTid = count, tid end
    end
    bgTilePerRow[ty] = bestTid
  end

  local bgBytes = {}
  local enemyBytes = {}
  local playerBytes = {}

  for ty = 0, 19 do
    local bgTid = bgTilePerRow[ty]
    local bgTx = 0
    for tx = 0, 31 do
      local mi = (ty * 32 + tx) * 2 + 1
      local entry = (mapBytes[mi] or 0) + (mapBytes[mi + 1] or 0) * 256
      if (entry % 1024) == bgTid then
        bgTx = tx
        break
      end
    end

    for row = 0, 7 do
      local srcY = ty * 8 + row
      local bgTileRow = {}
      for col = 0, 7 do
        local srcIdx = (srcY * 256 + (bgTx * 8 + col)) * 4 + 1
        bgTileRow[col] = fullRgba:sub(srcIdx, srcIdx + 3)
      end

      for tx = 0, 31 do
        local mi = (ty * 32 + tx) * 2 + 1
        local entry = (mapBytes[mi] or 0) + (mapBytes[mi + 1] or 0) * 256
        local tid = entry % 1024
        local isBg = (tid == bgTid)

        for col = 0, 7 do
          local srcIdx = (srcY * 256 + (tx * 8 + col)) * 4 + 1
          local pixel = fullRgba:sub(srcIdx, srcIdx + 3)

          table.insert(bgBytes, bgTileRow[col])

          if not isBg and tx >= 10 and ty <= 10 then
            table.insert(enemyBytes, pixel)
          else
            table.insert(enemyBytes, "\0\0\0\0")
          end

          if not isBg and tx <= 16 and ty >= 10 then
            table.insert(playerBytes, pixel)
          else
            table.insert(playerBytes, "\0\0\0\0")
          end
        end
      end
    end
  end

  return table.concat(bgBytes), table.concat(enemyBytes), table.concat(playerBytes)
end

local function ptr_offset(v)
  if type(v) ~= "number" or v < 0x08000000 or v >= 0x09000000 then return nil end
  return v - 0x08000000
end

-- src/battle_bg.c:439
function BattleChromeExtract.terrainTable(get, cfg)
  cfg = cfg or Versions.BATTLE_UI
  local base = cfg.terrain_table or Versions.address(BattleChromeExtract.TERRAIN_TABLE)
  local function u32(off)
    return (get(off) or 0) + (get(off + 1) or 0) * 256
      + (get(off + 2) or 0) * 65536 + (get(off + 3) or 0) * 16777216
  end
  local out = {}
  for id = 0, 19 do
    local key = BattleChromeExtract.TERRAIN_KEYS[id]
    local off = base + id * BattleChromeExtract.TERRAIN_ENTRY_SIZE
    local tiles = ptr_offset(u32(off))
    local tilemap = ptr_offset(u32(off + 4))
    local pal = ptr_offset(u32(off + 16))
    if not (key and tiles and tilemap and pal) then return nil end
    out[id + 1] = { key = key, id = id, cfg = { tiles = tiles, tilemap = tilemap, pal = pal } }
  end
  local grass = cfg.terrain_grass
  local first = out[1].cfg
  if grass and (first.tiles ~= grass.tiles or first.tilemap ~= grass.tilemap
    or first.pal ~= grass.pal) then
    return nil
  end
  return out
end

function BattleChromeExtract.requireTerrainTable(get, cfg)
  cfg = cfg or Versions.BATTLE_UI
  local terrains = BattleChromeExtract.terrainTable(get, cfg)
  if not terrains then
    error(string.format("battle_chrome_extract: sBattleTerrainTable at 0x%X did not decode",
      cfg.terrain_table or Versions.address(BattleChromeExtract.TERRAIN_TABLE)))
  end
  return terrains
end

function BattleChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. BattleChromeExtract.CACHE_SUB
  local cfg = Versions.BATTLE_UI
  local function get(i) return rom:get(i) end

  local tbGfx = Lz77.decompress(get, cfg.textbox_gfx)
  local tbPal = Lz77.decompress(get, cfg.textbox_pal)
  local tbMap = Lz77.decompress(get, cfg.textbox_tilemap)
  local textboxRgba, tw, th = bake_tilemap_rgba(tbGfx, tbPal, tbMap, 32, 64)
  cache:write(root .. "/textbox.rgba", textboxRgba)

  -- Healthbox pals are uncompressed INCBIN_U16 (not LZ).
  local hbPal = load_pal(read_raw(rom, cfg.healthbox_pal, 32), 16)
  local barPal = load_pal(read_raw(rom, cfg.healthbar_pal, 32), 16)
  local playerGfx = Lz77.decompress(get, cfg.healthbox_player)
  local enemyGfx = Lz77.decompress(get, cfg.healthbox_enemy)
  local playerRgba = bake_player_healthbox(playerGfx, hbPal)
  local enemyRgba = bake_enemy_healthbox(enemyGfx, hbPal)
  cache:write(root .. "/healthbox_player.rgba", playerRgba)
  cache:write(root .. "/healthbox_enemy.rgba", enemyRgba)
  if cfg.healthbox_safari then
    -- src/battle_interface.c:615 CreateSafariPlayerHealthboxSprites
    local safariGfx = Lz77.decompress(get, cfg.healthbox_safari)
    cache:write(root .. "/healthbox_safari.rgba", bake_player_healthbox(safariGfx, hbPal))
  end
  BattleChromeExtract.runDoubles(rom, cache, { cacheRoot = cacheRoot })

  local elGfx = read_raw(rom, cfg.healthbox_elements, 320 * 24 / 2)
  -- HP bar sprite uses TAG_HEALTHBAR_PAL; EXP is blitted into the healthbox
  -- which uses TAG_HEALTHBOX_PAL (cyan/blue fill). Bake both.
  cache:write(root .. "/elements.rgba", bake_sheet_rgba(elGfx, barPal, 320, 24))
  cache:write(root .. "/elements_exp.rgba", bake_sheet_rgba(elGfx, hbPal, 320, 24))

  -- Terrains (BG2). Palettes load at BG_PLTT_ID(2) → tilemap palNum 2/3/4.
  local terrains = BattleChromeExtract.requireTerrainTable(get, cfg)
  local terrainMeta = {}
  local terrainOrder = {}
  for _, t in ipairs(terrains) do
    local tr = t.cfg
    if tr then
      local tGfx = Lz77.decompress(get, tr.tiles)
      local tPal = Lz77.decompress(get, tr.pal)
      local tMap = Lz77.decompress(get, tr.tilemap)
      local rgba, trW, trH = bake_tilemap_rgba(tGfx, tPal, tMap, 32, 32, {
        transparent0 = false,
        bgPalBase = 2,
      })
      cache:write(root .. "/terrain_" .. t.key .. ".rgba", rgba)
      local bgRgba, enemyRgba, playerRgba = split_terrain_layers(rgba, tMap)
      cache:write(root .. "/terrain_bg_" .. t.key .. ".rgba", bgRgba)
      cache:write(root .. "/terrain_enemy_" .. t.key .. ".rgba", enemyRgba)
      cache:write(root .. "/terrain_player_" .. t.key .. ".rgba", playerRgba)
      terrainMeta[t.key] = { w = trW, h = trH }
      terrainOrder[#terrainOrder + 1] = t.key
    end
  end

  local grass = terrainMeta.grass or { w = 256, h = 256 }
  local terrainLines = {}
  for _, key in ipairs(terrainOrder) do
    local m = terrainMeta[key]
    terrainLines[#terrainLines + 1] = string.format(
      '    %s = { file = "terrain_%s.rgba", w = %d, h = %d },', key, key, m.w, m.h)
  end

  -- Party summary bar (128×8); balls use elements tiles 66..69.
  if cfg.party_summary_bar then
    local barGfx = Lz77.decompress(get, cfg.party_summary_bar)
    cache:write(root .. "/party_summary_bar.rgba", bake_sheet_rgba(barGfx, hbPal, 128, 8))
  end

  local manifest = string.format([[return {
  format = %d,
  textboxW = %d, textboxH = %d,
  terrainW = %d, terrainH = %d,
  terrains = {
%s
  },
  partySummaryBar = { file = "party_summary_bar.rgba", w = 128, h = 8 },
  partyBarPlayer = { x = 136, y = 96 },
  partyBarOpponent = { x = 104, y = 40 },
  -- pret InitBattlerHealthboxCoords / sBattlerCoords (singles)
  -- Player TL uses stale 64x32 centerToCorner (−32,−16) even though shape is 64x64
  playerBox = { w = 128, h = 64, x = 158, y = 88 },
  enemyBox = { w = 128, h = 32, x = 44, y = 30 },
  doublesPlayerBox = { w = 128, h = 32, file = "healthbox_doubles_player.rgba" },
  doublesOpponentBox = { w = 128, h = 32, file = "healthbox_doubles_opponent.rgba" },
  -- src/battle_interface.c:615, :735
  safariBox = { w = 128, h = 64, x = 158, y = 88, file = "healthbox_safari.rgba" },
  -- Sprite centers before pic y_offset; final Y = base + y_offset [+8 player]
  playerSprite = { x = 72, y = 80 },
  enemySprite = { x = 176, y = 40 },
  -- HP bar: subsprite origin (center−16, center) relative to box TL
  playerHpBar = { x = 32, y = 16, pixels = 48 },
  enemyHpBar = { x = 24, y = 16, pixels = 48 },
  playerExpBar = { x = 32, y = 32, pixels = 64 },
  hpBarPixels = 48,
  expBarPixels = 64,
  msgY = 120,
  panelH = 40,
}
]], BattleChromeExtract.FORMAT_VERSION, tw, th,
    grass.w, grass.h,
    table.concat(terrainLines, "\n"))
  cache:write(root .. "/manifest.lua", manifest)

  return { root = root, textboxW = tw, textboxH = th, terrains = terrainOrder }
end

function BattleChromeExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. BattleChromeExtract.CACHE_SUB
  local function valid_file(rel, minSize)
    minSize = minSize or 1
    if cache then
      if cache.read then
        local data = cache:read(rel)
        return (data and #data >= minSize) or false
      elseif cache.exists then
        return cache:exists(rel) or false
      end
      return false
    end
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.readActive then
      local data = CacheFs.readActive(rel)
      if data and #data >= minSize then return true end
    end
    if love and love.filesystem and love.filesystem.read then
      local ok, data = pcall(love.filesystem.read, rel)
      if ok and data and #data >= minSize then return true end
    end
    local f = io.open(rel, "rb")
    if f then
      local data = f:read(minSize)
      f:close()
      if data and #data >= minSize then return true end
    end
    return false
  end

  return valid_file(root .. "/manifest.lua", 20)
    and valid_file(root .. "/healthbox_player.rgba", 128 * 64 * 4)
    and valid_file(root .. "/terrain_building.rgba", 100)
end

return BattleChromeExtract
