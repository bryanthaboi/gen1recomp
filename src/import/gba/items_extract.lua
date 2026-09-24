-- Extract FRLG item table from ROM (gItems) into data/generated/gba/items/pack.lua.
-- Pure Lua ROM reader: 0 external pret / python dependencies.

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")

local ItemsExtract = {}

ItemsExtract.CACHE_SUB = "items"
ItemsExtract.FORMAT_VERSION = 1

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local POCKET_NAMES = {
  [1] = "ITEMS",
  [2] = "KEY_ITEMS",
  [3] = "POKE_BALLS",
  [4] = "TM_CASE",
  [5] = "BERRY_POUCH",
}

local function get_byte(rom, off)
  if rom.get then
    return rom:get(off)
  elseif rom.data then
    return rom.data:byte(off + 1)
  end
  return 0
end

local function get_u16(rom, off)
  if rom.u16 then
    return rom:u16(off)
  end
  return get_byte(rom, off) + get_byte(rom, off + 1) * 256
end

local function get_u32(rom, off)
  if rom.u32 then
    return rom:u32(off)
  end
  return get_byte(rom, off)
    + get_byte(rom, off + 1) * 256
    + get_byte(rom, off + 2) * 65536
    + get_byte(rom, off + 3) * 16777216
end

local function decode_name(rom, off, maxLen)
  maxLen = maxLen or 14
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
  if not gbaPtr or gbaPtr < 0x08000000 or gbaPtr >= 0x0A000000 then
    return ""
  end
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

local function popcount(v)
  local n = 0
  while v > 0 do
    n = n + v % 2
    v = math.floor(v / 2)
  end
  return n
end

-- src/data/pokemon/item_effects.h:338, src/pokemon.c:4202
local function read_effect(rom, id)
  if id < Versions.ITEM_EFFECT_FIRST or id > Versions.ITEM_EFFECT_LAST then return nil end
  local ptr = get_u32(rom, Versions.ITEM_EFFECT_TABLE + (id - Versions.ITEM_EFFECT_FIRST) * 4)
  if ptr < 0x08000000 or ptr >= 0x0A000000 then return nil end
  local off = ptr - 0x08000000
  local e4, e5 = get_byte(rom, off + 4), get_byte(rom, off + 5)
  local len = 6 + popcount(e4 % 8) + ((math.floor(e4 / 8) % 4 ~= 0) and 1 or 0)
    + popcount(e5 % 16) + popcount(math.floor(e5 / 32))
  local out = {}
  for i = 1, len do out[i] = get_byte(rom, off + i - 1) end
  return out
end

-- src/item_use.c:409
local function medicine_kind(effect)
  if not effect then return "heal" end
  local e3, e4, e5 = effect[4], effect[5], effect[6]
  if math.floor(e4 / 64) % 2 == 1 then return "revive" end
  if e4 % 4 ~= 0 or e5 % 16 ~= 0 then return "vitamin" end
  if math.floor(e4 / 4) % 2 == 1 then return "heal" end
  if e3 % 64 ~= 0 or effect[1] >= 0x80 then return "status" end
  return "heal"
end

local function determine_field_use(pocket, battleUsage, fieldUseFunc, effect)
  if pocket == "KEY_ITEMS" then return "key" end
  if pocket == "TM_CASE" then return "tm" end
  if pocket == "POKE_BALLS" then return "battle" end
  local F = Versions.FIELD_USE_FUNCS
  local fn = fieldUseFunc - 0x08000001
  if fn == F.medicine then return medicine_kind(effect) end
  if fn == F.ether or fn == F.pp_up then return "pp" end
  if fn == F.rare_candy then return "level" end
  if fn == F.evo_item then return "evo" end
  if fn == F.sacred_ash then return "revive" end
  if fn == F.repel then return "repel" end
  if fn == F.escape_rope then return "escape" end
  if fn == F.black_white_flute then return "black_white_flute" end
  if (battleUsage or 0) > 0 then return "battle" end
  return "none"
end

function ItemsExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. ItemsExtract.CACHE_SUB
  local need = root .. "/pack.lua"
  if cache and cache.exists and cache:exists(need) then
    return true
  end
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.exists and CacheFs.exists(need) then
    return true
  end
  if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(need) then
    return true
  end
  local f = io.open(need, "rb") or io.open("data/generated/gba/" .. ItemsExtract.CACHE_SUB .. "/pack.lua", "rb")
  if f then
    f:close()
    return true
  end
  return false
end

function ItemsExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local outRel = cacheRoot .. "/" .. ItemsExtract.CACHE_SUB .. "/pack.lua"

  if not opts.force and ItemsExtract.ready(cache, cacheRoot) then
    return { ok = true, count = Versions.ITEMS_COUNT or 375, path = outRel, skipped = true }
  end

  local itemBase = Versions.ITEMS or 0x3DB028
  local itemCount = Versions.ITEMS_COUNT or 375
  local itemStride = Versions.ITEM_STRIDE or 44

  local lines = {
    "-- Auto-generated from GBA ROM gItems table. DO NOT EDIT DIRECTLY.",
    "return {",
    "  version = 1,",
    string.format("  count = %d,", itemCount),
    "  items = {",
  }

  for id = 0, itemCount - 1 do
    local off = itemBase + id * itemStride
    local name = decode_name(rom, off, 14)
    local itemId = get_u16(rom, off + 14)
    local price = get_u16(rom, off + 16)
    local holdEffect = get_byte(rom, off + 18)
    local holdEffectParam = get_byte(rom, off + 19)
    local descPtr = get_u32(rom, off + 20)
    local importance = get_byte(rom, off + 24)
    local registrability = get_byte(rom, off + 25)
    local pocketId = get_byte(rom, off + 26)
    local itemType = get_byte(rom, off + 27)
    local fieldUseFunc = get_u32(rom, off + 28)
    local battleUsage = get_byte(rom, off + 32)
    local battleUseFunc = get_u32(rom, off + 36)
    local secondaryId = get_byte(rom, off + 40)

    local desc = decode_text(rom, descPtr, 256)
    local pocket = POCKET_NAMES[pocketId] or "ITEMS"
    local effect = read_effect(rom, id)
    local fieldUse = determine_field_use(pocket, battleUsage, fieldUseFunc, effect)

    lines[#lines + 1] = string.format(
      '    [%d] = { name="%s", pocket="%s", fieldUse="%s", price=%d, ' ..
      'holdEffect=%d, holdEffectParam=%d, importance=%d, registrability=%d, ' ..
      'battleUsage=%d, secondaryId=%d, itemId=%d, itemType=%d, ' ..
      'fieldUseFunc=%d, battleUseFunc=%d, effect=%s, description="%s" },',
      id,
      escape_lua(name ~= "" and name or "????????"),
      pocket,
      fieldUse,
      price,
      holdEffect,
      holdEffectParam,
      importance,
      registrability,
      battleUsage,
      secondaryId,
      itemId,
      itemType,
      fieldUseFunc,
      battleUseFunc,
      effect and ("{" .. table.concat(effect, ",") .. "}") or "nil",
      escape_lua(desc)
    )
  end

  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  local outputText = table.concat(lines, "\n")

  local wrote = false
  if cache and cache.write then
    cache:write(outRel, outputText)
    wrote = true
  end
  if not wrote then
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.write then
      local ok = pcall(CacheFs.write, outRel, outputText)
      if ok then wrote = true end
    end
  end
  if not wrote and love and love.filesystem and love.filesystem.write then
    pcall(love.filesystem.write, outRel, outputText)
  end

  return {
    ok = true,
    count = itemCount,
    path = outRel,
  }
end

return ItemsExtract
