-- Pokédex Chrome & Data Extractor from FRLG ROM.
-- 100% pure Lua ROM reader: 0 external pret / python dependencies.
-- Extracts:
-- 1. Full species Dex entries from gPokedexEntries (Category, Height, Weight, flavor text, scales/offsets).
-- 2. 9 Habitat category pages from gDexCategories (Grassland, Forest, Waters-edge, Sea, Cave, Mountain, Rough-terrain, Urban, Rare).
-- 3. 6 Sorting Orders from gPokedexOrder_* and sSpeciesTo* tables (Numerical Kanto/National, A-Z, Type, Weight, Height).

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")
local Lz77 = require("src.import.gba.lz77")

local PokedexChromeExtract = {}

PokedexChromeExtract.CACHE_SUB = "pokemon/pokedex"
PokedexChromeExtract.FORMAT_VERSION = 5
PokedexChromeExtract.TILE_SHEET_COLS = 8
PokedexChromeExtract.TILE_SHEETS = {
  kanto = "dex_tiles_kanto.rgba",
  national = "dex_tiles_national.rgba",
}
PokedexChromeExtract.CHROME_FILE = "chrome.lua"
PokedexChromeExtract.PAPER_BG_FILE = "paper_bg.rgba"
PokedexChromeExtract.PAPER_BG_W = 240
PokedexChromeExtract.PAPER_BG_H = 160
-- src/pokedex_screen.c:930
PokedexChromeExtract.PAPER_TILE = 0x001
-- src/pokedex_screen.c:933
PokedexChromeExtract.PAPER_BAR_PAL = 15
PokedexChromeExtract.PAPER_BAR_COLOR = 15
PokedexChromeExtract.PAPER_BAR_ROWS = 2
PokedexChromeExtract.FOOTPRINT_TABLE = 0x43FAB0
PokedexChromeExtract.FOOTPRINT_SUB = "footprints"
PokedexChromeExtract.FOOTPRINT_BYTES = 32
PokedexChromeExtract.FOOTPRINT_W = 16
PokedexChromeExtract.FOOTPRINT_H = 16
-- src/data/pokemon_graphics/footprint_table.h:255
PokedexChromeExtract.FOOTPRINT_QUESTION_MARK_SPECIES = 252
PokedexChromeExtract.FOOTPRINT_QUESTION_MARK_FILE = "question_mark.rgba"

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function get_byte(rom, off)
  if rom.get then return rom:get(off) end
  if rom.data then return rom.data:byte(off + 1) end
  return 0
end

local function get_u16(rom, off)
  if rom.u16 then return rom:u16(off) end
  return get_byte(rom, off) + get_byte(rom, off + 1) * 256
end

local function get_s16(rom, off)
  local v = get_u16(rom, off)
  if v >= 32768 then return v - 65536 end
  return v
end

local function get_u32(rom, off)
  if rom.u32 then return rom:u32(off) end
  return get_byte(rom, off)
    + get_byte(rom, off + 1) * 256
    + get_byte(rom, off + 2) * 65536
    + get_byte(rom, off + 3) * 16777216
end

local function decode_category(rom, off, maxLen)
  maxLen = maxLen or 12
  local chars = {}
  for i = 0, maxLen - 1 do
    local b = get_byte(rom, off + i)
    if b == 0xFF then break end
    if TextIR.CHARMAP[b] then
      chars[#chars + 1] = TextIR.CHARMAP[b]
    elseif b >= 0xBB and b <= 0xD4 then
      chars[#chars + 1] = string.char(string.byte("A") + (b - 0xBB))
    elseif b >= 0xD5 and b <= 0xEE then
      chars[#chars + 1] = string.char(string.byte("a") + (b - 0xD5))
    end
  end
  return table.concat(chars)
end

local function decode_text(rom, gbaPtr, maxLen)
  if not gbaPtr or gbaPtr < 0x08000000 or gbaPtr >= 0x0A000000 then return "" end
  local off = gbaPtr - 0x08000000
  maxLen = maxLen or 256
  local chars = {}
  for i = 0, maxLen - 1 do
    local b = get_byte(rom, off + i)
    if b == 0xFF then break end
    if b == 0xFE or b == 0xFA or b == 0xFB then
      chars[#chars + 1] = "\n"
    elseif TextIR.CHARMAP[b] then
      chars[#chars + 1] = TextIR.CHARMAP[b]
    elseif b >= 0xBB and b <= 0xD4 then
      chars[#chars + 1] = string.char(string.byte("A") + (b - 0xBB))
    elseif b >= 0xD5 and b <= 0xEE then
      chars[#chars + 1] = string.char(string.byte("a") + (b - 0xD5))
    end
  end
  return table.concat(chars)
end

local function escape_lua(s)
  return (tostring(s or ""):gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"))
end

local function write_file(cache, relPath, content)
  local wrote = false
  if cache and cache.write then
    cache:write(relPath, content)
    wrote = true
  end
  if not wrote then
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.write then
      local ok = pcall(CacheFs.write, relPath, content)
      if ok then wrote = true end
    end
  end
  if not wrote and love and love.filesystem and love.filesystem.write then
    pcall(love.filesystem.write, relPath, content)
  end
  local f = io.open(relPath, "wb") or io.open("data/generated/gba/" .. relPath:gsub("^data/generated/gba/", ""), "wb")
  if f then
    f:write(content)
    f:close()
  end
end

--- Extract entries.lua from ROM gPokedexEntries table
function PokedexChromeExtract.extractEntries(rom, cache, root)
  local entriesBase = Versions.POKEDEX_ENTRIES or 0x44E850
  local spToNatBase = Versions.SPECIES_TO_NATIONAL or 0x251FEE
  local numSpecies = Versions.NUM_SPECIES or 412
  local natDexCount = Versions.NATIONAL_DEX_COUNT or 386

  local natToSpecies = {}
  for sp = 1, numSpecies - 1 do
    local nat = get_u16(rom, spToNatBase + (sp - 1) * 2)
    if nat >= 1 and nat <= natDexCount and not natToSpecies[nat] then
      natToSpecies[nat] = sp
    end
  end

  local entries = {}
  -- src/data/pokemon/pokedex_entries.h:3
  for nat = 0, natDexCount do
    local sp = natToSpecies[nat] or nat
    local off = entriesBase + nat * (Versions.POKEDEX_ENTRY_SIZE or 36)
    local category = decode_category(rom, off, 12)
    local height = get_u16(rom, off + 12)
    local weight = get_u16(rom, off + 14)
    local descPtr1 = get_u32(rom, off + 16)
    local descPtr2 = get_u32(rom, off + 20)
    local pokemonScale = get_u16(rom, off + 26)
    local pokemonOffset = get_s16(rom, off + 28)
    local trainerScale = get_u16(rom, off + 30)
    local trainerOffset = get_s16(rom, off + 32)

    local desc1 = decode_text(rom, descPtr1, 256)
    local desc2 = (descPtr2 >= 0x08000000 and descPtr2 < 0x0A000000) and decode_text(rom, descPtr2, 256) or desc1

    entries[sp] = {
      category = category ~= "" and category or "UNKNOWN",
      height = height,
      weight = weight,
      description = desc1,
      description2 = desc2,
      pokemonScale = pokemonScale,
      pokemonOffset = pokemonOffset,
      trainerScale = trainerScale,
      trainerOffset = trainerOffset,
    }
  end

  local lines = {
    "-- Auto-generated FRLG Pokédex Entries from ROM gPokedexEntries. DO NOT EDIT DIRECTLY.",
    "return {",
  }
  local ids = {}
  for id in pairs(entries) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local e = entries[id]
    lines[#lines + 1] = string.format(
      "  [%d] = { category = \"%s\", height = %d, weight = %d, description = \"%s\", description2 = \"%s\", pokemonScale = %d, pokemonOffset = %d, trainerScale = %d, trainerOffset = %d },",
      id,
      escape_lua(e.category),
      e.height or 0,
      e.weight or 0,
      escape_lua(e.description),
      escape_lua(e.description2),
      e.pokemonScale or 256,
      e.pokemonOffset or 0,
      e.trainerScale or 256,
      e.trainerOffset or 0
    )
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  local text = table.concat(lines, "\n")
  write_file(cache, root .. "/entries.lua", text)
  return true
end

--- Extract categories.lua from ROM gDexCategories table
function PokedexChromeExtract.extractCategories(rom, cache, root)
  local gDexBase = Versions.DEX_CATEGORIES or 0x452C4C
  local catKeys = { "grassland", "forest", "waters_edge", "sea", "cave", "mountain", "rough_terrain", "urban", "rare" }
  local numSpecies = Versions.NUM_SPECIES or 412

  local categories = {}
  for catIdx = 1, 9 do
    local k = catKeys[catIdx]
    categories[k] = {}
    local catOff = gDexBase + (catIdx - 1) * 8
    local pagesPtr = get_u32(rom, catOff)
    local pageCount = get_byte(rom, catOff + 4)
    if pagesPtr >= 0x08000000 and pagesPtr < 0x0A000000 then
      local pagesOff = pagesPtr - 0x08000000
      for p = 0, pageCount - 1 do
        local pEntryOff = pagesOff + p * 8
        local monListPtr = get_u32(rom, pEntryOff)
        local monCount = get_byte(rom, pEntryOff + 4)
        if monListPtr >= 0x08000000 and monListPtr < 0x0A000000 then
          local monListOff = monListPtr - 0x08000000
          local mons = {}
          for m = 0, monCount - 1 do
            local sp = get_u16(rom, monListOff + m * 2)
            if sp >= 1 and sp <= numSpecies - 1 then
              mons[#mons + 1] = sp
            end
          end
          categories[k][p + 1] = mons
        end
      end
    end
  end

  local lines = {
    "-- Auto-generated FRLG Habitat Categories from ROM gDexCategories. DO NOT EDIT DIRECTLY.",
    "return {",
  }
  for _, k in ipairs(catKeys) do
    local pages = categories[k] or {}
    lines[#lines + 1] = string.format("  [\"%s\"] = {", k)
    for pIdx = 1, #pages do
      local p = pages[pIdx] or {}
      local monList = table.concat(p, ", ")
      lines[#lines + 1] = string.format("    [%d] = { %s },", pIdx, monList)
    end
    lines[#lines + 1] = "  },"
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  local text = table.concat(lines, "\n")
  write_file(cache, root .. "/categories.lua", text)
  return true
end

--- Extract orders.lua from ROM gPokedexOrder_* tables
function PokedexChromeExtract.extractOrders(rom, cache, root)
  local natDexCount = Versions.NATIONAL_DEX_COUNT or 386
  local numSpecies = Versions.NUM_SPECIES or 412
  local orders = {
    numerical_kanto = {},
    numerical_national = {},
    atoz = {},
    type = {},
    lightest = {},
    smallest = {},
  }

  for i = 1, 151 do orders.numerical_kanto[i] = i end
  for i = 1, natDexCount do orders.numerical_national[i] = i end

  local ordersBase = Versions.POKEDEX_ORDERS or {
    alphabetical = 0x443FF2,
    weight = 0x4442F6,
    height = 0x4445FA,
    type = 0x4448FE,
  }

  for i = 0, natDexCount - 1 do
    local idA = get_u16(rom, ordersBase.alphabetical + i * 2)
    if idA >= 1 and idA <= natDexCount then orders.atoz[#orders.atoz + 1] = idA end
    local idW = get_u16(rom, ordersBase.weight + i * 2)
    if idW >= 1 and idW <= natDexCount then orders.lightest[#orders.lightest + 1] = idW end
    local idH = get_u16(rom, ordersBase.height + i * 2)
    if idH >= 1 and idH <= natDexCount then orders.smallest[#orders.smallest + 1] = idH end
    local idT = get_u16(rom, ordersBase.type + i * 2)
    if idT >= 1 and idT <= numSpecies - 1 then orders.type[#orders.type + 1] = idT end
  end

  local lines = {
    "-- Auto-generated FRLG Pokédex Sorting Orders from ROM. DO NOT EDIT DIRECTLY.",
    "return {",
  }
  for _, k in ipairs({ "numerical_kanto", "numerical_national", "atoz", "type", "lightest", "smallest" }) do
    local list = orders[k] or {}
    lines[#lines + 1] = string.format("  [\"%s\"] = {", k)
    lines[#lines + 1] = "    " .. table.concat(list, ", ")
    lines[#lines + 1] = "  },"
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  local text = table.concat(lines, "\n")
  write_file(cache, root .. "/orders.lua", text)
  return true
end

-- include/pokedex.h:19
PokedexChromeExtract.DEX_AREA_NAMES = {
  [0] = "DEX_AREA_NONE",
  "DEX_AREA_PALLET_TOWN", "DEX_AREA_VIRIDIAN_CITY", "DEX_AREA_PEWTER_CITY",
  "DEX_AREA_CERULEAN_CITY", "DEX_AREA_LAVENDER_TOWN", "DEX_AREA_VERMILION_CITY",
  "DEX_AREA_CELADON_CITY", "DEX_AREA_FUCHSIA_CITY", "DEX_AREA_CINNABAR_ISLAND",
  "DEX_AREA_INDIGO_PLATEAU", "DEX_AREA_SAFFRON_CITY",
  "DEX_AREA_ROUTE_1", "DEX_AREA_ROUTE_2", "DEX_AREA_ROUTE_3", "DEX_AREA_ROUTE_4",
  "DEX_AREA_ROUTE_5", "DEX_AREA_ROUTE_6", "DEX_AREA_ROUTE_7", "DEX_AREA_ROUTE_8",
  "DEX_AREA_ROUTE_9", "DEX_AREA_ROUTE_10", "DEX_AREA_ROUTE_11", "DEX_AREA_ROUTE_12",
  "DEX_AREA_ROUTE_13", "DEX_AREA_ROUTE_14", "DEX_AREA_ROUTE_15", "DEX_AREA_ROUTE_16",
  "DEX_AREA_ROUTE_17", "DEX_AREA_ROUTE_18", "DEX_AREA_ROUTE_19", "DEX_AREA_ROUTE_20",
  "DEX_AREA_ROUTE_21", "DEX_AREA_ROUTE_22", "DEX_AREA_ROUTE_23", "DEX_AREA_ROUTE_24",
  "DEX_AREA_ROUTE_25",
  "DEX_AREA_VIRIDIAN_FOREST", "DEX_AREA_DIGLETTS_CAVE", "DEX_AREA_MT_MOON",
  "DEX_AREA_CERULEAN_CAVE", "DEX_AREA_ROCK_TUNNEL", "DEX_AREA_POWER_PLANT",
  "DEX_AREA_POKEMON_TOWER", "DEX_AREA_SAFARI_ZONE", "DEX_AREA_SEAFOAM_ISLANDS",
  "DEX_AREA_POKEMON_MANSION", "DEX_AREA_VICTORY_ROAD",
  "DEX_AREA_ONE_ISLAND", "DEX_AREA_TWO_ISLAND", "DEX_AREA_THREE_ISLAND",
  "DEX_AREA_FOUR_ISLAND", "DEX_AREA_FIVE_ISLAND", "DEX_AREA_SIX_ISLAND",
  "DEX_AREA_SEVEN_ISLAND",
  "DEX_AREA_KINDLE_ROAD", "DEX_AREA_TREASURE_BEACH", "DEX_AREA_CAPE_BRINK",
  "DEX_AREA_BOND_BRIDGE", "DEX_AREA_THREE_ISLE_PATH", "DEX_AREA_RESORT_GORGEOUS",
  "DEX_AREA_WATER_LABYRINTH", "DEX_AREA_FIVE_ISLE_MEADOW", "DEX_AREA_MEMORIAL_PILLAR",
  "DEX_AREA_OUTCAST_ISLAND", "DEX_AREA_GREEN_PATH", "DEX_AREA_WATER_PATH",
  "DEX_AREA_RUIN_VALLEY", "DEX_AREA_TRAINER_TOWER", "DEX_AREA_CANYON_ENTRANCE",
  "DEX_AREA_SEVAULT_CANYON", "DEX_AREA_TANOBY_RUINS", "DEX_AREA_MT_EMBER",
  "DEX_AREA_BERRY_FOREST", "DEX_AREA_ICEFALL_CAVE", "DEX_AREA_LOST_CAVE",
  "DEX_AREA_ALTERING_CAVE", "DEX_AREA_PATTERN_BUSH", "DEX_AREA_DOTTED_HOLE",
  "DEX_AREA_TANOBY_CHAMBER",
}

-- src/pokedex_area_markers.c:28
PokedexChromeExtract.MARKER_SHAPES = {
  [0] = "MARKER_CIRCULAR",
  [1] = "MARKER_SMALL_H",
  [2] = "MARKER_SMALL_V",
  [3] = "MARKER_MED_H",
  [4] = "MARKER_MED_V",
  [5] = "MARKER_LARGE_H",
  [6] = "MARKER_LARGE_V",
}

-- src/pokedex_area_markers.c:101, src/wild_pokemon_area.c:25
function PokedexChromeExtract.extractAreaMarkers(rom, cache, root)
  local MapSections = require("src.import.gba.map_sections_extract")
  local base = Versions.DEX_AREA_MARKERS
  local stride = Versions.DEX_AREA_MARKER_ENTRY_SIZE or 4
  local count = Versions.DEX_AREA_COUNT or 80
  if not base then return false end

  local names = PokedexChromeExtract.DEX_AREA_NAMES
  local shapes = PokedexChromeExtract.MARKER_SHAPES

  local markers, order = {}, {}
  for id = 1, count - 1 do
    local key = names[id]
    if key then
      local off = base + id * stride
      local shapeId = get_byte(rom, off)
      local x = get_byte(rom, off + 1)
      local y = get_byte(rom, off + 2)
      if x >= 128 then x = x - 256 end
      if y >= 128 then y = y - 256 end
      local shape = shapes[shapeId]
      if shape and not (x == 0 and y == 0 and shapeId == 0) then
        markers[key] = { x = x, y = y, shape = shape }
        order[#order + 1] = key
      end
    end
  end

  local mapsecToArea, secOrder = {}, {}
  for _, tbl in ipairs(Versions.DEX_AREA_MAPSEC_TABLES or {}) do
    for i = 0, (tbl.count or 0) - 1 do
      local secId = get_u16(rom, tbl.off + i * 4)
      local areaId = get_u16(rom, tbl.off + i * 4 + 2)
      local section = MapSections.SECTIONS and MapSections.SECTIONS[secId]
      local areaKey = names[areaId]
      if section and section.id and areaKey and markers[areaKey] and not mapsecToArea[section.id] then
        mapsecToArea[section.id] = areaKey
        secOrder[#secOrder + 1] = section.id
      end
    end
  end

  table.sort(order)
  table.sort(secOrder)
  local lines = {
    "-- Auto-generated FRLG Pokédex area markers from ROM. DO NOT EDIT DIRECTLY.",
    "return {",
    "  markers = {",
  }
  for _, key in ipairs(order) do
    local m = markers[key]
    lines[#lines + 1] = string.format("    [\"%s\"] = { x = %d, y = %d, shape = \"%s\" },",
      key, m.x, m.y, m.shape)
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  mapsecToArea = {"
  for _, secId in ipairs(secOrder) do
    lines[#lines + 1] = string.format("    [\"%s\"] = \"%s\",", secId, mapsecToArea[secId])
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  write_file(cache, root .. "/area_markers.lua", table.concat(lines, "\n"))
  return true
end

function PokedexChromeExtract.bakeTileSheet(gfx, palette)
  local cols = PokedexChromeExtract.TILE_SHEET_COLS
  local tileCount = math.floor(Lz77.len(gfx) / 32)
  local rows = math.ceil(tileCount / cols)
  local w, h = cols * 8, rows * 8
  local rgb = {}
  for i = 0, 15 do
    local c = (palette[i] or 0) % 32768
    rgb[i] = string.char(
      math.floor((c % 32) * 255 / 31 + 0.5),
      math.floor((math.floor(c / 32) % 32) * 255 / 31 + 0.5),
      math.floor((math.floor(c / 1024) % 32) * 255 / 31 + 0.5),
      255)
  end
  local chunks = {}
  for i = 1, w * h do chunks[i] = rgb[0] end
  for t = 0, tileCount - 1 do
    local baseX = (t % cols) * 8
    local baseY = math.floor(t / cols) * 8
    for row = 0, 7 do
      for bx = 0, 3 do
        local byte = gfx[t * 32 + row * 4 + bx + 1] or 0
        local o = (baseY + row) * w + baseX + bx * 2 + 1
        chunks[o] = rgb[byte % 16]
        chunks[o + 1] = rgb[math.floor(byte / 16) % 16]
      end
    end
  end
  return table.concat(chunks), w, h
end

-- src/pokedex_screen.c:897
function PokedexChromeExtract.extractTileSheets(rom, cache, root)
  local function get(i) return get_byte(rom, i) end
  for variant, file in pairs(PokedexChromeExtract.TILE_SHEETS) do
    local src = Versions.POKEDEX_BG_TILES and Versions.POKEDEX_BG_TILES[variant]
    if src then
      local gfx = Lz77.decompress(get, src.gfx)
      local palette = {}
      for i = 0, 15 do
        palette[i] = get_u16(rom, src.pal + i * 2)
      end
      write_file(cache, root .. "/" .. file, (PokedexChromeExtract.bakeTileSheet(gfx, palette)))
    end
  end
  return true
end

local function gba_rgb(c)
  c = (c or 0) % 32768
  return math.floor((c % 32) * 255 / 31 + 0.5),
    math.floor((math.floor(c / 32) % 32) * 255 / 31 + 0.5),
    math.floor((math.floor(c / 1024) % 32) * 255 / 31 + 0.5)
end

local function read_palette(rom, off)
  local pal = {}
  for i = 0, 15 do pal[i] = get_u16(rom, off + i * 2) end
  return pal
end

local function raw_tiles(rom, off, byteCount)
  local out = {}
  for i = 1, byteCount do out[i] = get_byte(rom, off + i - 1) end
  return out
end

local function tile_source(rom, src)
  if src.lz then
    return Lz77.decompress(function(i) return get_byte(rom, i) end, src.gfx)
  end
  return raw_tiles(rom, src.gfx, math.floor(src.w * src.h / 2))
end

function PokedexChromeExtract.bakeImage(gfx, palette, w, h, opts)
  opts = opts or {}
  local cols = math.floor(w / 8)
  local rows = math.floor(h / 8)
  local tile0 = opts.tile0 or 0
  local rgb = {}
  for i = 0, 15 do
    local r, g, b = gba_rgb(palette and palette[i])
    local a = 255
    if i == 0 and not opts.opaqueZero then a = 0; r, g, b = 0, 0, 0 end
    if opts.mask then
      if i == 0 then r, g, b, a = 0, 0, 0, 0 else r, g, b, a = 255, 255, 255, 255 end
    end
    rgb[i] = string.char(r, g, b, a)
  end
  local chunks = {}
  for i = 1, w * h do chunks[i] = rgb[0] end
  for t = 0, cols * rows - 1 do
    local baseX = (t % cols) * 8
    local baseY = math.floor(t / cols) * 8
    for row = 0, 7 do
      for bx = 0, 3 do
        local byte = gfx[(tile0 + t) * 32 + row * 4 + bx + 1] or 0
        local o = (baseY + row) * w + baseX + bx * 2 + 1
        chunks[o] = rgb[byte % 16]
        chunks[o + 1] = rgb[math.floor(byte / 16) % 16]
      end
    end
  end
  return table.concat(chunks)
end

-- src/pokedex_screen.c:143
function PokedexChromeExtract.extractChromeGfx(rom, cache, root)
  local src = Versions.POKEDEX_BG_TILES and Versions.POKEDEX_BG_TILES.kanto
  if not src then return false end
  local palette = read_palette(rom, src.pal)
  for _, g in ipairs(Versions.POKEDEX_CHROME_GFX or {}) do
    local gfx = tile_source(rom, g)
    write_file(cache, root .. "/" .. g.file,
      PokedexChromeExtract.bakeImage(gfx, palette, g.w, g.h))
  end
  return true
end

-- src/pokedex_screen.c:158
function PokedexChromeExtract.extractCategoryIcons(rom, cache, root)
  local w = Versions.POKEDEX_CATEGORY_ICON_W or 64
  local h = Versions.POKEDEX_CATEGORY_ICON_H or 48
  for _, icon in ipairs(Versions.POKEDEX_CATEGORY_ICONS or {}) do
    local gfx = Lz77.decompress(function(i) return get_byte(rom, i) end, icon.gfx)
    local palette = read_palette(rom, icon.pal)
    write_file(cache, root .. "/" .. icon.file,
      PokedexChromeExtract.bakeImage(gfx, palette, w, h))
  end
  return true
end

-- src/pokedex_area_markers.c:203
function PokedexChromeExtract.extractAreaMarkerGfx(rom, cache, root)
  local base = Versions.POKEDEX_AREA_MARKER_GFX
  if not base then return false end
  local gfx = Lz77.decompress(function(i) return get_byte(rom, i) end, base)
  for _, shape in ipairs(Versions.POKEDEX_AREA_MARKER_SHAPES or {}) do
    write_file(cache, root .. "/" .. shape.file,
      PokedexChromeExtract.bakeImage(gfx, nil, shape.w, shape.h, { tile0 = shape.tile, mask = true }))
  end
  return true
end

-- src/pokedex_area_markers.c:237, src/pokedex_screen.c:3103
function PokedexChromeExtract.extractChromeColors(rom, cache, root)
  local src = Versions.POKEDEX_BG_TILES and Versions.POKEDEX_BG_TILES.kanto
  if not src then return false end
  local palette = read_palette(rom, src.pal)
  local gfx = Lz77.decompress(function(i) return get_byte(rom, i) end, src.gfx)
  local blendTile = Versions.POKEDEX_MARKER_BLEND_TILE or 15
  local eva = Versions.POKEDEX_MARKER_BLEND_EVA or 12
  local evb = Versions.POKEDEX_MARKER_BLEND_EVB or 8
  local mr, mg, mb = gba_rgb(palette[(gfx[blendTile * 32 + 1] or 0) % 16])
  local sr, sg, sb = gba_rgb(get_u16(rom, (Versions.POKEDEX_SILHOUETTE_PAL or 0) + 2))
  -- src/pokedex_screen.c:245 sWindowTemplates[0..1], :1161 FillWindowPixelBuffer(0, PIXEL_FILL(15))
  local barIndex = PokedexChromeExtract.PAPER_BAR_PAL * 16 + PokedexChromeExtract.PAPER_BAR_COLOR
  local kr, kg, kb = gba_rgb(get_u16(rom, src.pal + barIndex * 2))
  local nat = Versions.POKEDEX_BG_TILES.national
  local nr, ng, nb = gba_rgb(get_u16(rom, nat.pal + barIndex * 2))
  local text = string.format(
    "-- Auto-generated FRLG Pokédex chrome colors from ROM. DO NOT EDIT DIRECTLY.\nreturn {\n"
      .. "  marker = { %d, %d, %d, %d },\n  marker_blend = { %d, %d },\n"
      .. "  silhouette = { %d, %d, %d },\n"
      .. "  bar_kanto = { %d, %d, %d },\n  bar_national = { %d, %d, %d },\n}\n",
    mr, mg, mb, math.floor(eva * 255 / 16 + 0.5), eva, evb, sr, sg, sb, kr, kg, kb, nr, ng, nb)
  write_file(cache, root .. "/" .. PokedexChromeExtract.CHROME_FILE, text)
  return true
end

local function read_palette_block(rom, off, count)
  local pal = {}
  for i = 0, count - 1 do pal[i] = get_u16(rom, off + i * 2) end
  return pal
end

local function palette_colors(pal, base)
  local out = {}
  for i = 0, 15 do
    local r, g, b = gba_rgb(pal and pal[base + i])
    out[i] = string.char(r, g, b, 255)
  end
  return out
end

-- src/pokedex_screen.c:930
function PokedexChromeExtract.bakePaperBg(gfx, pal)
  local w, h = PokedexChromeExtract.PAPER_BG_W, PokedexChromeExtract.PAPER_BG_H
  local cols, rows = math.floor(w / 8), math.floor(h / 8)
  local bars = PokedexChromeExtract.PAPER_BAR_ROWS
  local pagePal = palette_colors(pal, 0)
  local barColor = palette_colors(pal, PokedexChromeExtract.PAPER_BAR_PAL * 16)[PokedexChromeExtract.PAPER_BAR_COLOR]
  local px = {}
  for i = 1, w * h do px[i] = pagePal[0] end
  local function blit(tile, colors, tx, ty, keepZero)
    for row = 0, 7 do
      for bx = 0, 3 do
        local byte = gfx[tile * 32 + row * 4 + bx + 1] or 0
        local o = (ty * 8 + row) * w + tx * 8 + bx * 2 + 1
        local lo, hi = byte % 16, math.floor(byte / 16) % 16
        if keepZero or lo ~= 0 then px[o] = colors[lo] end
        if keepZero or hi ~= 0 then px[o + 1] = colors[hi] end
      end
    end
  end
  for ty = 0, rows - 1 do
    for tx = 0, cols - 1 do
      blit(PokedexChromeExtract.PAPER_TILE, pagePal, tx, ty, true)
    end
  end
  for py = 0, h - 1 do
    if py < bars * 8 or py >= h - bars * 8 then
      for x = 0, w - 1 do px[py * w + x + 1] = barColor end
    end
  end
  return table.concat(px)
end

-- src/pokedex_screen.c:896, src/pokedex_screen.c:930
function PokedexChromeExtract.extractPaperBg(rom, cache, root)
  local src = Versions.POKEDEX_BG_TILES and Versions.POKEDEX_BG_TILES.kanto
  if not src then return false end
  local gfx = Lz77.decompress(function(i) return get_byte(rom, i) end, src.gfx)
  local pal = read_palette_block(rom, src.pal, 256)
  write_file(cache, root .. "/" .. PokedexChromeExtract.PAPER_BG_FILE,
    PokedexChromeExtract.bakePaperBg(gfx, pal))
  return true
end

-- src/pokedex_screen.c:2901
function PokedexChromeExtract.bakeFootprint(bytes, r, g, b)
  local w, h = PokedexChromeExtract.FOOTPRINT_W, PokedexChromeExtract.FOOTPRINT_H
  local on = string.char(r or 0, g or 0, b or 0, 255)
  local off = string.char(0, 0, 0, 0)
  local px = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local tile = math.floor(x / 8) + 2 * math.floor(y / 8)
      local byte = bytes:byte(tile * 8 + (y % 8) + 1) or 0
      px[#px + 1] = (math.floor(byte / 2 ^ (x % 8)) % 2 == 1) and on or off
    end
  end
  return table.concat(px)
end

-- src/data/pokemon_graphics/footprint_table.h:3
function PokedexChromeExtract.footprintTable(rom, cfg)
  local base = (cfg and cfg.footprint_table)
    or Versions.MON_FOOTPRINT_TABLE
    or Versions.address(PokedexChromeExtract.FOOTPRINT_TABLE)
  local count = Versions.NUM_SPECIES or 412
  local function entry(sp)
    local ptr = get_u32(rom, base + sp * 4)
    if ptr < 0x08000000 or ptr >= 0x0A000000 then return nil end
    return ptr - 0x08000000
  end
  local none, bulbasaur = entry(0), entry(1)
  if not none or none ~= bulbasaur then return nil, base end
  local out = {}
  for sp = 0, count - 1 do out[sp] = entry(sp) end
  return out, base
end

local function footprint_name_keys(rom)
  local base = Versions.SPECIES_NAMES
  local stride = Versions.SPECIES_NAME_LENGTH or 11
  local count = Versions.NUM_SPECIES or 412
  if not base then return {} end
  local lowered, seen = {}, {}
  for sp = 0, count - 1 do
    local name = decode_category(rom, base + sp * stride, stride - 1)
    if name ~= "" and not name:match("^%?+$") and not name:find("[/\\]") then
      local lower = name:lower()
      lowered[sp] = lower
      local stripped = lower:gsub("[^%w_]", "")
      seen[stripped] = (seen[stripped] or 0) + 1
    end
  end
  local keys = {}
  for sp, lower in pairs(lowered) do
    local stripped = lower:gsub("[^%w_]", "")
    if stripped ~= "" and seen[stripped] == 1 then
      keys[sp] = stripped
    else
      keys[sp] = lower
    end
  end
  return keys
end

local function footprint_bytes(rom, off)
  local out = {}
  for i = 1, PokedexChromeExtract.FOOTPRINT_BYTES do
    out[i] = string.char(get_byte(rom, off + i - 1))
  end
  return table.concat(out)
end

-- src/pokedex_screen.c:2901, src/pokedex_screen.c:608
function PokedexChromeExtract.extractFootprints(rom, cache, root, cfg)
  local offsets = PokedexChromeExtract.footprintTable(rom, cfg)
  if not offsets then return false end
  local src = Versions.POKEDEX_BG_TILES and Versions.POKEDEX_BG_TILES.kanto
  local palette = src and read_palette(rom, src.pal)
  local r, g, b = gba_rgb(palette and palette[1])
  local dir = root .. "/" .. PokedexChromeExtract.FOOTPRINT_SUB
  local keys = footprint_name_keys(rom)
  local count = Versions.NUM_SPECIES or 412
  local written = 0
  for sp = 0, count - 1 do
    local off = offsets[sp]
    if off then
      local rgba = PokedexChromeExtract.bakeFootprint(footprint_bytes(rom, off), r, g, b)
      write_file(cache, dir .. "/" .. sp .. ".rgba", rgba)
      if keys[sp] then write_file(cache, dir .. "/" .. keys[sp] .. ".rgba", rgba) end
      written = written + 1
    end
  end
  local qm = offsets[PokedexChromeExtract.FOOTPRINT_QUESTION_MARK_SPECIES]
  if qm then
    write_file(cache, dir .. "/" .. PokedexChromeExtract.FOOTPRINT_QUESTION_MARK_FILE,
      PokedexChromeExtract.bakeFootprint(footprint_bytes(rom, qm), r, g, b))
  end
  return written > 0
end

function PokedexChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. PokedexChromeExtract.CACHE_SUB

  if not opts.force and PokedexChromeExtract.ready(cache, cacheRoot) then
    return true
  end

  if opts.progress then opts.progress("pokedex_entries", 0, 3) end
  PokedexChromeExtract.extractEntries(rom, cache, root)

  if opts.progress then opts.progress("pokedex_categories", 1, 3) end
  PokedexChromeExtract.extractCategories(rom, cache, root)

  if opts.progress then opts.progress("pokedex_orders", 2, 3) end
  PokedexChromeExtract.extractOrders(rom, cache, root)
  PokedexChromeExtract.extractAreaMarkers(rom, cache, root)
  PokedexChromeExtract.extractTileSheets(rom, cache, root)
  PokedexChromeExtract.extractChromeGfx(rom, cache, root)
  PokedexChromeExtract.extractCategoryIcons(rom, cache, root)
  PokedexChromeExtract.extractAreaMarkerGfx(rom, cache, root)
  PokedexChromeExtract.extractChromeColors(rom, cache, root)
  PokedexChromeExtract.extractPaperBg(rom, cache, root)
  PokedexChromeExtract.extractFootprints(rom, cache, root, opts)

  local manifest = string.format(
    "return { format = %d, count = %d, version = 2 }\n",
    PokedexChromeExtract.FORMAT_VERSION,
    Versions.NATIONAL_DEX_COUNT or 386
  )
  write_file(cache, root .. "/manifest.lua", manifest)
  write_file(cache, cacheRoot .. "/pokedex/manifest.lua", manifest)

  if opts.progress then opts.progress("pokedex_done", 3, 3) end
  return true
end

function PokedexChromeExtract.ready(cache, cacheRoot)
  cacheRoot = cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. PokedexChromeExtract.CACHE_SUB
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
    and valid_file(root .. "/entries.lua", 20)
    and valid_file(root .. "/categories.lua", 20)
    and valid_file(root .. "/orders.lua", 20)
    and valid_file(root .. "/area_markers.lua", 20)
    and valid_file(root .. "/" .. PokedexChromeExtract.TILE_SHEETS.kanto, 64)
    and valid_file(root .. "/" .. PokedexChromeExtract.TILE_SHEETS.national, 64)
    and valid_file(root .. "/" .. PokedexChromeExtract.CHROME_FILE, 20)
    and valid_file(root .. "/map_kanto.rgba", 64)
    and valid_file(root .. "/mini_page.rgba", 64)
    and valid_file(root .. "/blit_wide_ellipse.rgba", 64)
    and valid_file(root .. "/marker_0.rgba", 64)
    and valid_file(root .. "/cat_icon_grassland.rgba", 64)
    and valid_file(root .. "/" .. PokedexChromeExtract.PAPER_BG_FILE,
      PokedexChromeExtract.PAPER_BG_W * PokedexChromeExtract.PAPER_BG_H * 4)
    and valid_file(root .. "/" .. PokedexChromeExtract.FOOTPRINT_SUB .. "/1.rgba",
      PokedexChromeExtract.FOOTPRINT_W * PokedexChromeExtract.FOOTPRINT_H * 4)
    and valid_file(root .. "/" .. PokedexChromeExtract.FOOTPRINT_SUB .. "/bulbasaur.rgba", 64)
    and valid_file(root .. "/" .. PokedexChromeExtract.FOOTPRINT_SUB .. "/"
      .. PokedexChromeExtract.FOOTPRINT_QUESTION_MARK_FILE, 64)
end

return PokedexChromeExtract
