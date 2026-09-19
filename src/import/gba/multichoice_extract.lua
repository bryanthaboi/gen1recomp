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

function MultichoiceExtract.run(rom, cache, opts)
  opts = opts or {}
  local lists = MultichoiceExtract.extract(rom)
  local content = MultichoiceExtract.formatLua(lists)

  local cacheRoot = opts.cacheRoot or "data/generated/gba"
  local rel = cacheRoot .. "/scripts/multichoice.lua"

  if cache and cache.write then
    cache:write(rel, content)
  end

  local f = io.open(rel, "wb") or io.open("data/generated/gba/scripts/multichoice.lua", "wb")
  if f then
    f:write(content)
    f:close()
  end

  local fStub = io.open("src/import/gba/multichoice_data_stub.lua", "wb")
  if fStub then
    fStub:write(content)
    fStub:close()
  end

  return true
end

return MultichoiceExtract
