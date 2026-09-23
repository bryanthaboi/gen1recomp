-- src/region_map.c:393-427

local RegionMapExtract = {}

RegionMapExtract.CACHE_SUB = "region_map"
RegionMapExtract.FORMAT_VERSION = 2

RegionMapExtract.FILES = {
  "kanto_map.png",
  "sevii123_map.png",
  "sevii45_map.png",
  "sevii67_map.png",
  "switch_button.png",
  "navel_rock_patch.png",
  "birth_island_patch.png",
  "frame_normal.png",
  "frame_fly.png",
  "switch_menu_123.png",
  "switch_menu_all.png",
  "switch_cursor_left.png",
  "switch_cursor_right.png",
  "edge_top_left.png",
  "edge_top_right.png",
  "edge_mid_left.png",
  "edge_mid_right.png",
  "edge_bottom_left.png",
  "edge_bottom_right.png",
  "cursor.png",
  "fly_icon.png",
  "dungeon_icon.png",
  "dungeon_icon_visited.png",
  "player_red.png",
  "player_leaf.png",
  "layouts.lua",
  "section_geometry.lua",
  "manifest.lua",
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

-- src/region_map.c:3354-3369
RegionMapExtract.MAP_WIDTH = 22
RegionMapExtract.MAP_HEIGHT = 15
RegionMapExtract.MAPSEC_NONE = 197
RegionMapExtract.REGIONS = { "kanto", "sevii123", "sevii45", "sevii67" }

RegionMapExtract.SECTION_NAMES = {}
RegionMapExtract.DUNGEON_DESCRIPTIONS = {}
RegionMapExtract.KANTO_GRID = {}
RegionMapExtract.DUNGEON_GRID = {}
RegionMapExtract.LAYOUTS = nil
RegionMapExtract.GEOMETRY = nil

local generatedLoaded = false

function RegionMapExtract.applyGeneratedText(names, dungeonInfo, sections)
  local updated = 0
  for secId, name in pairs(names) do
    local info = assert(sections[secId], "no map section " .. tostring(secId))
    RegionMapExtract.SECTION_NAMES[info.id] = name
    updated = updated + 1
  end
  for secId, entry in pairs(dungeonInfo) do
    local info = sections[secId]
    if info then
      RegionMapExtract.SECTION_NAMES[info.id] = entry.name
      RegionMapExtract.DUNGEON_DESCRIPTIONS[info.id] = entry.desc
      updated = updated + 1
    end
  end
  return updated
end

local function read_lua(cache, rel)
  local src = assert(cache:read(rel), rel .. " is not in the cache")
  return assert(load(src, "@" .. rel, "t", {}))()
end

function RegionMapExtract.loadLayouts(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. RegionMapExtract.CACHE_SUB
  return read_lua(cache, root .. "/layouts.lua")
end

function RegionMapExtract.loadGeometry(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. RegionMapExtract.CACHE_SUB
  return read_lua(cache, root .. "/section_geometry.lua")
end

local function symbolic_grid(layer, sections)
  local grid = {}
  for y = 0, RegionMapExtract.MAP_HEIGHT - 1 do
    local row = {}
    for x = 0, RegionMapExtract.MAP_WIDTH - 1 do
      local mapsec = layer[y][x]
      if mapsec ~= RegionMapExtract.MAPSEC_NONE then
        row[x] = assert(sections[mapsec], "no map section " .. mapsec).id
      end
    end
    grid[y] = row
  end
  return grid
end

function RegionMapExtract.ensureGenerated()
  if generatedLoaded then return true end
  local cache = require("src.core.game3.dataset").cache()
  local MapPreviewExtract = require("src.import.gba.map_preview_extract")
  local MapSectionsExtract = require("src.import.gba.map_sections_extract")
  local names = assert(MapPreviewExtract.loadNames(cache), "region_map/names.lua is not in the cache")
  local dungeonInfo = assert(MapPreviewExtract.loadDungeonInfo(cache),
    "region_map/dungeon_info.lua is not in the cache")
  local sections = MapSectionsExtract.SECTIONS
  RegionMapExtract.applyGeneratedText(names, dungeonInfo, sections)
  RegionMapExtract.LAYOUTS = RegionMapExtract.loadLayouts(cache)
  RegionMapExtract.GEOMETRY = RegionMapExtract.loadGeometry(cache)
  local kanto = RegionMapExtract.LAYOUTS[0]
  RegionMapExtract.KANTO_GRID = symbolic_grid(kanto.map, sections)
  RegionMapExtract.DUNGEON_GRID = symbolic_grid(kanto.dungeon, sections)
  generatedLoaded = true
  return true
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
      if hflip then x0, x1 = 7 - x0, 7 - x1 end
      out[(baseY + row) * stride + (baseX + x0) + 1] = p0
      out[(baseY + row) * stride + (baseX + x1) + 1] = p1
    end
  end
end

local function load_pal_banks(bytes, count)
  local banks = {}
  local n = count or math.floor(#bytes / 32)
  for b = 0, n - 1 do
    local colors = {}
    local off = b * 32
    for c = 0, 15 do
      local i = off + c * 2 + 1
      colors[c] = (bytes[i] or 0) + (bytes[i + 1] or 0) * 256
    end
    banks[b] = colors
  end
  return banks
end

local function bake_sprite_16x16(gfx, palBytes, tileOffset)
  local BattleAnimExtract = require("src.import.gba.battle_anim_extract")
  tileOffset = tileOffset or 0
  local W, H = 16, 16
  local pal = {}
  for c = 0, 15 do
    local i = c * 2 + 1
    pal[c] = (palBytes[i] or 0) + (palBytes[i + 1] or 0) * 256
  end
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end
  local tiles = {
    { tileOffset + 0, 0, 0 },
    { tileOffset + 1, 8, 0 },
    { tileOffset + 2, 0, 8 },
    { tileOffset + 3, 8, 8 },
  }
  for _, t in ipairs(tiles) do
    local tileNum, ox, oy = t[1], t[2], t[3]
    local base = tileNum * 32
    local tile = {}
    for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
    decode_tile_4bpp(tile, pixels, ox, oy, W, false, false)
  end
  local px = {}
  local chunks = {}
  for i = 1, W * H do
    local idx = pixels[i] or 0
    local o = (i - 1) * 4 + 1
    if idx == 0 then
      px[o], px[o + 1], px[o + 2], px[o + 3] = 0, 0, 0, 0
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      px[o], px[o + 1], px[o + 2], px[o + 3] = r, g, b, 255
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  local rgbaStr = table.concat(chunks)
  local pngStr = BattleAnimExtract.encodePng and BattleAnimExtract.encodePng(px, W, H)
  return rgbaStr, pngStr, W, H
end

local function bake_sprite_8x8(gfx, palBytes, tileOffset)
  local BattleAnimExtract = require("src.import.gba.battle_anim_extract")
  tileOffset = tileOffset or 0
  local W, H = 8, 8
  local pal = {}
  for c = 0, 15 do
    local i = c * 2 + 1
    pal[c] = (palBytes[i] or 0) + (palBytes[i + 1] or 0) * 256
  end
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end
  local base = tileOffset * 32
  local tile = {}
  for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
  decode_tile_4bpp(tile, pixels, 0, 0, W, false, false)
  local px = {}
  local chunks = {}
  for i = 1, W * H do
    local idx = pixels[i] or 0
    local o = (i - 1) * 4 + 1
    if idx == 0 then
      px[o], px[o + 1], px[o + 2], px[o + 3] = 0, 0, 0, 0
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      px[o], px[o + 1], px[o + 2], px[o + 3] = r, g, b, 255
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  local rgbaStr = table.concat(chunks)
  local pngStr = BattleAnimExtract.encodePng and BattleAnimExtract.encodePng(px, W, H)
  return rgbaStr, pngStr, W, H
end

local function write_file(cache, path, bytes)
  if not (bytes and #bytes > 0) then return false end
  if cache and cache.write then
    return cache:write(path, bytes)
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.write then
    local ok = pcall(CacheFs.write, path, bytes)
    if ok then return true end
  end
  if love and love.filesystem and love.filesystem.write then
    local ok = pcall(love.filesystem.write, path, bytes)
    if ok then return true end
  end
  local f = io.open(path, "wb")
  if f then
    f:write(bytes)
    f:close()
    return true
  end
  return false
end

-- src/region_map.c:939
local function darken(c, tint)
  local r, g, b = c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
  local function ch(v) return math.floor(math.floor(math.floor(v * 256 / 100) * tint) / 256) end
  return ch(r) + ch(g) * 32 + ch(b) * 1024
end

-- src/region_map.c:959, :1108
local function build_banks(mapPalBytes, topBarBytes)
  local banks = load_pal_banks(mapPalBytes, 5)
  local edge, tinted = banks[2], {}
  for c = 0, 15 do tinted[c] = darken(edge[c], 95) end
  tinted[15] = edge[15]
  banks[2] = tinted
  banks[12] = load_pal_banks(topBarBytes, 1)[0]
  return banks
end

local function encode(px, W, H)
  local chunks = {}
  for i = 1, W * H * 4 do chunks[i] = string.char(px[i]) end
  local BattleAnimExtract = require("src.import.gba.battle_anim_extract")
  return table.concat(chunks), assert(BattleAnimExtract.encodePng(px, W, H))
end

local function bake_bg(gfx, banks, map, mapW, cols, rows)
  local W, H = cols * 8, rows * 8
  local tileCount = math.floor(#gfx / 32)
  local px, tmp = {}, {}
  for i = 1, W * H * 4 do px[i] = 0 end
  for ty = 0, rows - 1 do
    for tx = 0, cols - 1 do
      local mi = (ty * mapW + tx) * 2 + 1
      local entry = map[mi] + map[mi + 1] * 256
      local tileId = entry % 1024
      local bank = assert(banks[math.floor(entry / 4096) % 16], "tilemap names a palette bank the ROM does not load")
      if tileId < tileCount then
        local tile = {}
        for i = 1, 32 do tile[i] = gfx[tileId * 32 + i] end
        decode_tile_4bpp(tile, tmp, 0, 0, 8, math.floor(entry / 1024) % 2 == 1, math.floor(entry / 2048) % 2 == 1)
        for row = 0, 7 do
          for col = 0, 7 do
            local idx = tmp[row * 8 + col + 1]
            if idx ~= 0 then
              local r, g, b = bgr555_to_rgb8(bank[idx])
              local o = ((ty * 8 + row) * W + (tx * 8 + col)) * 4 + 1
              px[o], px[o + 1], px[o + 2], px[o + 3] = r, g, b, 255
            end
          end
        end
      end
    end
  end
  return encode(px, W, H)
end

local function entries(list, cols)
  local map = {}
  for i, entry in ipairs(list) do
    map[i * 2 - 1] = entry % 256
    map[i * 2] = math.floor(entry / 256)
  end
  return map, cols
end

local function bake_strip(gfx, palBytes, widthPx)
  local pal = load_pal_banks(palBytes, 1)[0]
  local tilesPerRow = widthPx / 8
  local tileCount = math.floor(#gfx / 32)
  local H = math.ceil(tileCount / tilesPerRow) * 8
  local pixels, px = {}, {}
  for i = 1, widthPx * H do pixels[i] = 0 end
  for t = 0, tileCount - 1 do
    local tile = {}
    for i = 1, 32 do tile[i] = gfx[t * 32 + i] end
    decode_tile_4bpp(tile, pixels, (t % tilesPerRow) * 8, math.floor(t / tilesPerRow) * 8, widthPx, false, false)
  end
  for i = 1, widthPx * H do
    local idx = pixels[i]
    local o = (i - 1) * 4 + 1
    if idx == 0 then
      px[o], px[o + 1], px[o + 2], px[o + 3] = 0, 0, 0, 0
    else
      local r, g, b = bgr555_to_rgb8(pal[idx])
      px[o], px[o + 1], px[o + 2], px[o + 3] = r, g, b, 255
    end
  end
  local rgba, png = encode(px, widthPx, H)
  return rgba, png, H
end

local function u8_grid(rom, off, layers, rows, cols)
  local out = {}
  for l = 0, layers - 1 do
    local layer = {}
    for y = 0, rows - 1 do
      local row = {}
      for x = 0, cols - 1 do row[x] = rom:get(off + (l * rows + y) * cols + x) end
      layer[y] = row
    end
    out[l] = layer
  end
  return out
end

function RegionMapExtract.run(rom, cache, opts)
  opts = opts or {}
  local Versions = require("src.import.gba.versions")
  local Lz77 = require("src.import.gba.lz77")
  local serialize = require("src.import.gba.extract_scripts").serialize_lua
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. RegionMapExtract.CACHE_SUB
  assert(rom, "region map extract needs a ROM")

  local function get(i) return rom:get(i) end
  local function read_bytes(off, len)
    local t = {}
    for i = 1, len do t[i] = get(off + i - 1) end
    return t
  end
  local function lz(off, what)
    return assert(Lz77.decompress(get, off), what .. " did not decompress")
  end
  local function put(name, bytes)
    assert(write_file(cache, root .. "/" .. name, bytes), "could not write region_map/" .. name)
  end
  local function put_image(base, rgba, png)
    put(base .. ".rgba", rgba)
    put(base .. ".png", png)
  end
  local function map_width(map)
    if #map >= 32 * 20 * 2 then return 32 end
    assert(#map >= 30 * 20 * 2, "region map tilemap is shorter than one screen")
    return 30
  end

  local topBarBytes = read_bytes(Versions.REGION_MAP_TOP_BAR_PAL, 32)
  local banks = build_banks(read_bytes(Versions.REGION_MAP_BG_PAL, 160), topBarBytes)
  local mapGfx = lz(Versions.REGION_MAP_BG_GFX, "sRegionMap_Gfx")

  -- src/region_map.c:1127-1147, :1505-1524
  local tilemaps = {
    kanto = Versions.REGION_MAP_KANTO_TILEMAP,
    sevii123 = Versions.REGION_MAP_SEVII123_TILEMAP,
    sevii45 = Versions.REGION_MAP_SEVII45_TILEMAP,
    sevii67 = Versions.REGION_MAP_SEVII67_TILEMAP,
  }
  for _, name in ipairs(RegionMapExtract.REGIONS) do
    local map = lz(tilemaps[name], name .. " tilemap")
    put_image(name .. "_map", bake_bg(mapGfx, banks, map, map_width(map), 30, 20))
  end
  do
    local list = {}
    for i = 0, 2 do
      for j = 0, 2 do list[#list + 1] = (0xF0 + 16 * i + j) + 3 * 4096 end
    end
    put_image("switch_button", bake_bg(mapGfx, banks, entries(list, 3), 3, 3, 3))
    local navel, birth = {}, {}
    for i = 1, 6 do navel[i] = 0x003 end
    for i = 1, 9 do birth[i] = 0x003 end
    put_image("navel_rock_patch", bake_bg(mapGfx, banks, entries(navel, 3), 3, 3, 2))
    put_image("birth_island_patch", bake_bg(mapGfx, banks, entries(birth, 3), 3, 3, 3))
  end

  -- src/region_map.c:2281-2284, :2419-2431
  do
    local gfx = lz(Versions.REGION_MAP_EDGE_GFX, "sMapEdge_Gfx")
    local map = lz(Versions.REGION_MAP_EDGE_TILEMAP, "sMapEdge_Tilemap")
    local w = map_width(map)
    local bar = { 0x002, 0x003 }
    for _ = 1, 26 do bar[#bar + 1] = 0x03D end
    bar[#bar + 1] = 0x03E
    bar[#bar + 1] = 0x03F
    for x = 0, 29 do
      local entry = bar[x + 1] + 2 * 4096
      local mi = (1 * w + x) * 2 + 1
      map[mi], map[mi + 1] = entry % 256, math.floor(entry / 256)
    end
    put_image("frame_normal", bake_bg(gfx, banks, map, w, 30, 20))
  end
  do
    local gfx = lz(Versions.REGION_MAP_BG_SECONDARY_GFX, "sBackground_Gfx")
    local map = lz(Versions.REGION_MAP_BG_SECONDARY_TILEMAP, "sBackground_Tilemap")
    put_image("frame_fly", bake_bg(gfx, banks, map, map_width(map), 30, 20))
  end

  -- src/region_map.c:1566-1581, :1740
  do
    local gfx = lz(Versions.REGION_MAP_SWITCH_MENU_GFX, "sSwitchMapMenu_Gfx")
    local m123 = lz(Versions.REGION_MAP_SWITCH_123_TILEMAP, "sSwitchMap_KantoSevii123_Tilemap")
    local mAll = lz(Versions.REGION_MAP_SWITCH_ALL_TILEMAP, "sSwitchMap_KantoSeviiAll_Tilemap")
    put_image("switch_menu_123", bake_bg(gfx, banks, m123, 30, 30, 20))
    put_image("switch_menu_all", bake_bg(gfx, banks, mAll, 30, 30, 20))
  end

  local sizes = {}
  local function sprite(name, off, palOff, width)
    local rgba, png, h = bake_strip(lz(off, name), read_bytes(palOff, 32), width)
    put_image(name, rgba, png)
    sizes[name] = { width, h }
  end
  -- src/region_map.c:747, :784, :1850-1881, :2195, :2257-2277
  sprite("cursor", Versions.REGION_MAP_CURSOR_GFX, Versions.REGION_MAP_CURSOR_PAL, 16)
  sprite("fly_icon", Versions.REGION_MAP_FLY_ICON_GFX, Versions.REGION_MAP_MISC_ICON_PAL, 16)
  sprite("switch_cursor_left", Versions.REGION_MAP_SWITCH_CURSOR_LEFT_GFX, Versions.REGION_MAP_SWITCH_CURSOR_PAL, 32)
  sprite("switch_cursor_right", Versions.REGION_MAP_SWITCH_CURSOR_RIGHT_GFX, Versions.REGION_MAP_SWITCH_CURSOR_PAL, 32)
  for key, off in pairs(Versions.REGION_MAP_EDGE_SPRITES) do
    sprite("edge_" .. key, off, Versions.REGION_MAP_EDGE_PAL, 32)
  end

  do
    local redGfx = lz(Versions.REGION_MAP_PLAYER_RED_GFX, "sPlayerIcon_Red")
    put_image("player_red", bake_sprite_16x16(redGfx, read_bytes(Versions.REGION_MAP_PLAYER_RED_PAL, 32), 0))
    local leafGfx = lz(Versions.REGION_MAP_PLAYER_LEAF_GFX, "sPlayerIcon_Leaf")
    put_image("player_leaf", bake_sprite_16x16(leafGfx, read_bytes(Versions.REGION_MAP_PLAYER_LEAF_PAL, 32), 0))
    local dungGfx = lz(Versions.REGION_MAP_DUNGEON_ICON_GFX, "sDungeonIcon")
    local miscPal = read_bytes(Versions.REGION_MAP_MISC_ICON_PAL, 32)
    -- src/region_map.c:795 sAnim_DungeonIconNotVisited, :790 sAnim_DungeonIconVisited
    put_image("dungeon_icon", bake_sprite_8x8(dungGfx, miscPal, 0))
    put_image("dungeon_icon_visited", bake_sprite_8x8(dungGfx, miscPal, 1))
  end

  -- src/region_map.c:527, :3158-3171, :3359
  local layouts = { seviiMapsecs = {} }
  for i, off in ipairs(Versions.REGION_MAP_LAYOUTS) do
    local grid = u8_grid(rom, off, 2, RegionMapExtract.MAP_HEIGHT, RegionMapExtract.MAP_WIDTH)
    layouts[i - 1] = { name = RegionMapExtract.REGIONS[i], map = grid[0], dungeon = grid[1] }
  end
  do
    local sevii = u8_grid(rom, Versions.REGION_MAP_SEVII_MAPSECS, 1, 3, 30)[0]
    for r = 0, 2 do
      local list = {}
      for i = 0, 29 do
        if sevii[r][i] == RegionMapExtract.MAPSEC_NONE then break end
        list[#list + 1] = sevii[r][i]
      end
      layouts.seviiMapsecs[r] = list
    end
  end
  put("layouts.lua", "return " .. serialize(layouts) .. "\n")
  local geometry = { topLeft = {}, dimensions = {} }
  for i = 0, Versions.MAPSEC_COUNT - 1 do
    local m = Versions.MAPSEC_FIRST + i
    geometry.topLeft[m] = { rom:u16(Versions.REGION_MAP_SECTION_TOP_LEFT + i * 4),
      rom:u16(Versions.REGION_MAP_SECTION_TOP_LEFT + i * 4 + 2) }
    geometry.dimensions[m] = { rom:u16(Versions.REGION_MAP_SECTION_DIMENSIONS + i * 4),
      rom:u16(Versions.REGION_MAP_SECTION_DIMENSIONS + i * 4 + 2) }
  end
  put("section_geometry.lua", "return " .. serialize(geometry) .. "\n")

  local topBar = load_pal_banks(topBarBytes, 1)[0]
  put("manifest.lua", "return " .. serialize({
    version = RegionMapExtract.FORMAT_VERSION,
    width = 240,
    height = 160,
    backdrop = topBar[15],
    topBarPal = topBar,
    sprites = sizes,
    playerIconSize = 16,
    dungeonIconSize = 8,
  }) .. "\n")

  return { ok = true, root = root }
end

local function baked(cache, rel)
  if cache then
    if cache.read then
      local d = cache:read(rel)
      return (d ~= nil and #d > 8)
    elseif cache.exists then
      return cache:exists(rel) and true or false
    end
    return false
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(rel)
    if d and #d > 8 then return true end
  end
  if love and love.filesystem and love.filesystem.read then
    local d = love.filesystem.read(rel)
    if d and #d > 8 then return true end
  end
  local f = io.open(rel, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 8 then return true end
  end
  return false
end

function RegionMapExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. RegionMapExtract.CACHE_SUB
  for _, name in ipairs(RegionMapExtract.FILES) do
    if not baked(cache, root .. "/" .. name) then return false end
  end
  return true
end

function RegionMapExtract.extract(rom, opts)
  return RegionMapExtract.run(rom, opts and opts.cache, opts)
end

return RegionMapExtract
