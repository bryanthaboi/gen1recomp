-- Extract FRLG wild encounter tables from ROM (gWildMonHeaders).
-- FireRed USA 1.0: pret wild_encounter.h layout — not curated JSON.

local Versions = require("src.import.gba.versions")

local EncountersExtract = {}

EncountersExtract.FORMAT_VERSION = 1

local function log(msg)
  print("[gba/encounters] " .. tostring(msg))
end

local function gba_off(ptr)
  return Versions.gbaToFile(ptr)
end

local function read_info(rom, infoOff, slotCount)
  if not infoOff then return nil end
  local rate = rom:get(infoOff)
  local monsPtr = rom:u32(infoOff + 4)
  local monsOff = gba_off(monsPtr)
  if not monsOff then return nil end
  local slots = {}
  for i = 0, slotCount - 1 do
    local base = monsOff + i * 4
    local minLevel = rom:get(base)
    local maxLevel = rom:get(base + 1)
    local species = rom:u16(base + 2)
    slots[#slots + 1] = {
      species = species,
      minLevel = minLevel,
      maxLevel = maxLevel,
    }
  end
  return { rate = rate, slots = slots }
end

local function serialize_area(lines, name, area)
  if not area or not area.slots or #area.slots == 0 then return end
  lines[#lines + 1] = string.format("    %s = {\n", name)
  lines[#lines + 1] = string.format("      rate = %d,\n", area.rate or 0)
  lines[#lines + 1] = "      slots = {\n"
  for _, s in ipairs(area.slots) do
    lines[#lines + 1] = string.format(
      "        { species = %d, minLevel = %d, maxLevel = %d },\n",
      s.species or 0, s.minLevel or 1, s.maxLevel or s.minLevel or 1)
  end
  lines[#lines + 1] = "      },\n"
  lines[#lines + 1] = "    },\n"
end

local function serialize_entry(lines, key, entry)
  lines[#lines + 1] = string.format("  [%q] = {\n", key)
  lines[#lines + 1] = string.format("    mapGroup = %d,\n", entry.mapGroup or 0)
  lines[#lines + 1] = string.format("    mapNum = %d,\n", entry.mapNum or 0)
  serialize_area(lines, "land", entry.land)
  serialize_area(lines, "water", entry.water)
  serialize_area(lines, "rocks", entry.rocks)
  serialize_area(lines, "fishing", entry.fishing)
  lines[#lines + 1] = "  },\n"
end

--- Parse gWildMonHeaders from an open Rom handle.
-- @return list of { mapGroup, mapNum, land, water, rocks, fishing }
function EncountersExtract.parseRom(rom, version)
  version = version or {}
  local headersOff = version.wild_mon_headers or Versions.WILD_MON_HEADERS
  local hdrSize = version.wild_mon_header_size or Versions.WILD_MON_HEADER_SIZE
  local landN = version.land_wild_count or Versions.LAND_WILD_COUNT
  local waterN = version.water_wild_count or Versions.WATER_WILD_COUNT
  local rockN = version.rock_wild_count or Versions.ROCK_WILD_COUNT
  local fishN = version.fish_wild_count or Versions.FISH_WILD_COUNT

  local out = {}
  local off = headersOff
  local guard = 0
  while guard < 512 do
    guard = guard + 1
    local mapGroup = rom:get(off)
    local mapNum = rom:get(off + 1)
    if mapGroup == 0xFF and mapNum == 0xFF then
      break
    end
    local landPtr = rom:u32(off + 4)
    local waterPtr = rom:u32(off + 8)
    local rockPtr = rom:u32(off + 12)
    local fishPtr = rom:u32(off + 16)
    local entry = {
      mapGroup = mapGroup,
      mapNum = mapNum,
      land = read_info(rom, gba_off(landPtr), landN),
      water = read_info(rom, gba_off(waterPtr), waterN),
      rocks = read_info(rom, gba_off(rockPtr), rockN),
      fishing = read_info(rom, gba_off(fishPtr), fishN),
    }
    out[#out + 1] = entry
    off = off + hdrSize
  end
  return out
end

local function build_tables(entries)
  local tables = {}
  for _, e in ipairs(entries) do
    local gn = string.format("%d:%d", e.mapGroup, e.mapNum)
    local packed = {
      mapGroup = e.mapGroup,
      mapNum = e.mapNum,
      land = e.land,
      water = e.water,
      rocks = e.rocks,
      fishing = e.fishing,
    }
    -- Last header wins for duplicate map keys (Alterating Cave sets).
    tables[gn] = packed
    local alias = Versions.frMapFor(e.mapGroup, e.mapNum)
    if alias then
      tables[alias] = packed
    end
  end
  return tables
end

local function encode_lua(tables, headerCount)
  local lines = {
    "-- Auto-extracted from ROM gWildMonHeaders (FireRed).\n",
    string.format("-- format_version=%d headers=%d\n", EncountersExtract.FORMAT_VERSION, headerCount),
    "return {\n",
  }
  local keys = {}
  for k in pairs(tables) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    -- Prefer FR_/SEVII_ aliases after numeric keys for stable diffs.
    local an, bn = a:match("^(%d+):"), b:match("^(%d+):")
    if an and not bn then return true end
    if bn and not an then return false end
    return a < b
  end)
  for _, k in ipairs(keys) do
    serialize_entry(lines, k, tables[k])
  end
  lines[#lines + 1] = "}\n"
  return table.concat(lines)
end

--- Write data/generated/gba/encounters.lua from ROM.
function EncountersExtract.writeExtract(rom, cache, root, version)
  root = root or "data/generated/gba"
  if not rom or not cache then
    return nil, "rom and cache required"
  end
  local entries = EncountersExtract.parseRom(rom, version)
  local tables = build_tables(entries)
  local blob = encode_lua(tables, #entries)
  cache:write(root .. "/encounters.lua", blob)

  local aliased = 0
  for k in pairs(tables) do
    if k:sub(1, 3) == "FR_" or k:sub(1, 6) == "SEVII_" then
      aliased = aliased + 1
    end
  end
  log(string.format("extracted %d headers → %s/encounters.lua (%d game3 aliases)",
    #entries, root, aliased))
  return {
    headers = #entries,
    aliases = aliased,
    path = root .. "/encounters.lua",
  }
end

return EncountersExtract
