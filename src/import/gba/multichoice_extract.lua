-- Extractor for GBA FireRed Multichoice list strings and tables (gMultichoiceLists).

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")

local MultichoiceExtract = {}

local function u32(rom, off)
  if rom.u32 then return rom:u32(off) end
  return rom:get(off) + rom:get(off + 1) * 256 + rom:get(off + 2) * 65536 + rom:get(off + 3) * 16777216
end

local function get_byte(rom, off)
  if rom.get then return rom:get(off) end
  if rom.data then return rom.data:byte(off + 1) end
  return 0
end

local function decode_gba_string(rom, off)
  local chars = {}
  local maxLen = 64
  for _ = 1, maxLen do
    local b = get_byte(rom, off)
    if b == 0xFF then break end
    if b == 0xFC then
      local sub = get_byte(rom, off + 1)
      if sub == 0x13 then
        off = off + 2
        chars[#chars + 1] = "  "
      else
        off = off + 1
      end
    elseif b == 0xFD then
      off = off + 1
    elseif b == 0xFE or b == 0xFA or b == 0xFB then
      chars[#chars + 1] = " "
    elseif TextIR.CHARMAP[b] then
      chars[#chars + 1] = TextIR.CHARMAP[b]
    elseif b >= 0xBB and b <= 0xD4 then
      chars[#chars + 1] = string.char(string.byte("A") + (b - 0xBB))
    elseif b >= 0xD5 and b <= 0xEE then
      chars[#chars + 1] = string.char(string.byte("a") + (b - 0xD5))
    elseif b >= 0xA1 and b <= 0xAA then
      chars[#chars + 1] = tostring(b - 0xA1)
    end
    off = off + 1
  end
  local s = table.concat(chars):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

function MultichoiceExtract.extract(rom)
  local base = Versions.MULTICHOICE_LISTS or 0x3E04B0
  local totalCount = Versions.MULTICHOICE_COUNT or 65

  local lists = {}
  for i = 0, totalCount - 1 do
    local off = base + i * 8
    local listPtr = u32(rom, off)
    local count = get_byte(rom, off + 4)
    local labels = {}
    if listPtr >= 0x08000000 and listPtr < 0x09000000 and count > 0 and count <= 30 then
      for a = 0, count - 1 do
        local actOff = listPtr - 0x08000000 + a * 8
        local textPtr = u32(rom, actOff)
        local s = ""
        if textPtr >= 0x08000000 and textPtr < 0x09000000 then
          s = decode_gba_string(rom, textPtr - 0x08000000)
        end
        table.insert(labels, s)
      end
    end
    lists[i] = { count = #labels, labels = labels }
  end
  return lists
end

function MultichoiceExtract.formatLua(lists)
  local lines = {
    "-- Auto-generated FRLG Multichoice Lists from ROM gMultichoiceLists. DO NOT EDIT DIRECTLY.",
    "return {",
  }
  for i = 0, #lists do
    local item = lists[i]
    if item and item.labels then
      local quoted = {}
      for _, s in ipairs(item.labels) do
        table.insert(quoted, string.format("%q", s))
      end
      lines[#lines + 1] = string.format("  [%d] = { count = %d, labels = { %s } },", i, #item.labels, table.concat(quoted, ", "))
    end
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

MultichoiceExtract.CACHE_REL = "scripts/multichoice.lua"

local function multichoice_path(cacheRoot)
  return (cacheRoot or "data/generated/gba") .. "/" .. MultichoiceExtract.CACHE_REL
end

function MultichoiceExtract.ready(cache, cacheRoot)
  local rel = multichoice_path(cacheRoot)
  if cache and cache.read then
    local data = cache:read(rel)
    return (data ~= nil and #data > 40 and data:find("labels", 1, true) ~= nil)
  end
  if cache and cache.exists then
    return cache:exists(rel) and true or false
  end
  return false
end

function MultichoiceExtract.run(rom, cache, opts)
  opts = opts or {}
  local lists = MultichoiceExtract.extract(rom)
  local content = MultichoiceExtract.formatLua(lists)
  local rel = multichoice_path(opts.cacheRoot)

  local wrote, err = false, nil
  if cache and cache.write then
    local ok, werr = cache:write(rel, content)
    if ok == false then err = werr else wrote = true end
  end
  if not wrote then
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.write then
      local ok, werr = pcall(CacheFs.write, rel, content)
      if ok then wrote = true else err = err or werr end
    end
  end
  if not wrote and love and love.filesystem and love.filesystem.write then
    local ok, werr = pcall(love.filesystem.write, rel, content)
    if ok then wrote = true else err = err or werr end
  end
  if not wrote then
    error("multichoice: could not write " .. rel .. ": " .. tostring(err))
  end

  local n = 0
  for _, entry in pairs(lists) do
    if entry and entry.count and entry.count > 0 then n = n + 1 end
  end
  return { path = rel, listCount = n }
end

return MultichoiceExtract
