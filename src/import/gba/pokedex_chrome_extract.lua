-- Pokédex Chrome & Data Extractor from FRLG ROM.
-- 100% pure Lua ROM reader: 0 external pret / python dependencies.
-- Extracts:
-- 1. Full species Dex entries from gPokedexEntries (Category, Height, Weight, flavor text, scales/offsets).
-- 2. 9 Habitat category pages from gDexCategories (Grassland, Forest, Waters-edge, Sea, Cave, Mountain, Rough-terrain, Urban, Rare).
-- 3. 6 Sorting Orders from gPokedexOrder_* and sSpeciesTo* tables (Numerical Kanto/National, A-Z, Type, Weight, Height).

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")

local PokedexChromeExtract = {}

PokedexChromeExtract.CACHE_SUB = "pokemon/pokedex"
PokedexChromeExtract.FORMAT_VERSION = 2

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
  if cache and cache.write then
    cache:write(relPath, content)
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
  for nat = 1, natDexCount do
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
end

return PokedexChromeExtract
