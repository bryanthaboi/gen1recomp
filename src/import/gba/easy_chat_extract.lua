-- Extract Easy Chat groups and word dictionaries directly from FireRed ROM.
-- Sources:
--   sEasyChatGroups at Versions.EASY_CHAT_GROUPS (0x3ECED4)
--   sEasyChatGroupNamePointers, gSpeciesNames, gMoveNames

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")

local EasyChatExtract = {}

EasyChatExtract.CACHE_SUB = "easy_chat"
EasyChatExtract.FORMAT_VERSION = 1

local GROUP_NAMES = {
  [0] = "POKéMON",
  [1] = "TRAINER",
  [2] = "STATUS",
  [3] = "BATTLE",
  [4] = "GREETINGS",
  [5] = "PEOPLE",
  [6] = "VOICES",
  [7] = "SPEECH",
  [8] = "ENDINGS",
  [9] = "FEELINGS",
  [10] = "CONDITIONS",
  [11] = "ACTIONS",
  [12] = "LIFESTYLE",
  [13] = "HOBBIES",
  [14] = "TIME",
  [15] = "MISC.",
  [16] = "ADJECTIVES",
  [17] = "EVENTS",
  [18] = "MOVE 1",
  [19] = "MOVE 2",
  [20] = "TRENDY SAYING",
  [21] = "POKéMON (NAT)",
}

local function get_byte(rom, off)
  if rom.get then return rom:get(off) end
  if rom.data then return rom.data:byte(off + 1) or 0 end
  return 0
end

local function get_u16(rom, off)
  if rom.u16 then return rom:u16(off) end
  return get_byte(rom, off) + get_byte(rom, off + 1) * 256
end

local function get_u32(rom, off)
  if rom.u32 then return rom:u32(off) end
  return get_byte(rom, off)
    + get_byte(rom, off + 1) * 256
    + get_byte(rom, off + 2) * 65536
    + get_byte(rom, off + 3) * 16777216
end

local function decode_gba_string(rom, fileOff, maxLen)
  maxLen = maxLen or 32
  local chars = {}
  for i = 0, maxLen - 1 do
    local b = get_byte(rom, fileOff + i)
    if b == 0xFF then break end
    chars[#chars + 1] = b
  end
  return TextIR.fromGbaChars(chars)
end

function EasyChatExtract.extractFromRom(rom)
  local baseOff = Versions.EASY_CHAT_GROUPS or 0x3ECED4
  local numGroups = Versions.EASY_CHAT_GROUP_COUNT or 22
  local groups = {}

  local speciesNamesOff = Versions.SPECIES_NAMES or 0x245EE0
  local speciesStride = Versions.SPECIES_NAME_LENGTH or 11
  local moveNamesOff = Versions.MOVE_NAMES or 0x247094
  local moveStride = (Versions.MOVE_NAME_LENGTH or 12) + 1

  local function readSpeciesName(spId)
    local off = speciesNamesOff + spId * speciesStride
    return decode_gba_string(rom, off, 11)
  end

  local function readMoveName(mvId)
    local off = moveNamesOff + mvId * moveStride
    return decode_gba_string(rom, off, 13)
  end

  for gid = 0, numGroups - 1 do
    local gOff = baseOff + gid * 8
    local wordDataPtr = get_u32(rom, gOff)
    local numWords = get_u16(rom, gOff + 4)
    local numEnabled = get_u16(rom, gOff + 6)
    local dataFileOff = Versions.gbaToFile(wordDataPtr) or (wordDataPtr - 0x08000000)

    local words = {}
    local isValues = (gid == 0 or gid == 18 or gid == 19 or gid == 21)

    if isValues then
      for i = 0, numWords - 1 do
        local val = get_u16(rom, dataFileOff + i * 2)
        local wid = (gid * 512) + val
        local txt = ""
        if gid == 0 or gid == 21 then
          txt = readSpeciesName(val)
        else
          txt = readMoveName(val)
        end
        words[#words + 1] = { id = wid, val = val, text = txt }
      end
    else
      for i = 0, numWords - 1 do
        local entryOff = dataFileOff + i * 12
        local textPtr = get_u32(rom, entryOff)
        local textFileOff = Versions.gbaToFile(textPtr) or (textPtr - 0x08000000)
        local txt = decode_gba_string(rom, textFileOff, 32)
        local wid = (gid * 512) + i
        words[#words + 1] = { id = wid, text = txt }
      end
    end

    groups[gid] = {
      id = gid,
      name = GROUP_NAMES[gid] or string.format("GROUP %d", gid),
      numWords = numWords,
      numEnabled = numEnabled,
      words = words,
    }
  end

  return groups
end

function EasyChatExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or "data/generated/gba"
  local groups = EasyChatExtract.extractFromRom(rom)

  local lines = {
    "-- Auto-generated Easy Chat word definitions extracted from FireRed ROM.",
    "local EasyChatData = {}",
    "",
    "EasyChatData.EC_WORD_UNDEFINED = 0xFFFF",
    "EasyChatData.PASSPHRASE_MYSTERY_EVENT = { 5178, 6167, 4107, 8207 } -- MYSTERY EVENT IS EXCITING",
    "EasyChatData.PASSPHRASE_QUESTIONNAIRE = { 521, 5131, 4144, 4138 } -- LINK TOGETHER WITH ALL",
    "EasyChatData.DEFAULT_PROFILE = { 2601, 4128, 526, 2611 } -- I AM A POKéMON FRIEND",
    "",
    "EasyChatData.GROUPS = {",
  }

  for gid = 0, #groups do
    local g = groups[gid]
    if g then
      lines[#lines + 1] = string.format("  [%d] = {", gid)
      lines[#lines + 1] = string.format("    id = %d,", gid)
      lines[#lines + 1] = string.format("    name = %q,", g.name)
      lines[#lines + 1] = "    words = {"
      for _, w in ipairs(g.words) do
        lines[#lines + 1] = string.format("      { id = %d, text = %q },", w.id, w.text)
      end
      lines[#lines + 1] = "    },"
      lines[#lines + 1] = "  },"
    end
  end

  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "local _wordMap = nil"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "local function buildWordMap()"
  lines[#lines + 1] = "  if _wordMap then return end"
  lines[#lines + 1] = "  _wordMap = {}"
  lines[#lines + 1] = "  for _, group in pairs(EasyChatData.GROUPS) do"
  lines[#lines + 1] = "    for _, w in ipairs(group.words) do"
  lines[#lines + 1] = "      _wordMap[w.id] = w.text"
  lines[#lines + 1] = "    end"
  lines[#lines + 1] = "  end"
  lines[#lines + 1] = "end"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "function EasyChatData.getWord(wordId)"
  lines[#lines + 1] = "  if not wordId or wordId == EasyChatData.EC_WORD_UNDEFINED then return \"\" end"
  lines[#lines + 1] = "  buildWordMap()"
  lines[#lines + 1] = "  return _wordMap[wordId] or \"???\""
  lines[#lines + 1] = "end"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "function EasyChatData.decodeWord(wordId)"
  lines[#lines + 1] = "  if not wordId then return 0, 0 end"
  lines[#lines + 1] = "  local gid = math.floor(wordId / 512) % 128"
  lines[#lines + 1] = "  local idx = wordId % 512"
  lines[#lines + 1] = "  return gid, idx"
  lines[#lines + 1] = "end"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "function EasyChatData.encodeWord(groupId, index)"
  lines[#lines + 1] = "  return ((groupId or 0) % 128) * 512 + ((index or 0) % 512)"
  lines[#lines + 1] = "end"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "function EasyChatData.formatPhrase(words, columns, rows)"
  lines[#lines + 1] = "  words = words or {}"
  lines[#lines + 1] = "  columns = columns or 2"
  lines[#lines + 1] = "  rows = rows or 2"
  lines[#lines + 1] = "  local lines = {}"
  lines[#lines + 1] = "  local idx = 1"
  lines[#lines + 1] = "  for r = 1, rows do"
  lines[#lines + 1] = "    local lineWords = {}"
  lines[#lines + 1] = "    for c = 1, columns do"
  lines[#lines + 1] = "      local w = EasyChatData.getWord(words[idx])"
  lines[#lines + 1] = "      if w and #w > 0 then table.insert(lineWords, w) end"
  lines[#lines + 1] = "      idx = idx + 1"
  lines[#lines + 1] = "    end"
  lines[#lines + 1] = "    table.insert(lines, table.concat(lineWords, \" \"))"
  lines[#lines + 1] = "  end"
  lines[#lines + 1] = "  return table.concat(lines, \"\\n\")"
  lines[#lines + 1] = "end"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "return EasyChatData"
  lines[#lines + 1] = ""

  local text = table.concat(lines, "\n")
  local outRel = cacheRoot .. "/easy_chat/easy_chat_data.lua"
  if cache and cache.write then
    cache:write(outRel, text)
  end

  local f = io.open(outRel, "wb")
  if f then
    f:write(text)
    f:close()
  end

  return {
    ok = true,
    groupCount = #groups + 1,
    path = outRel,
  }
end

return EasyChatExtract
