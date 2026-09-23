-- A word carries its group's context, because the same English word means
-- different things in different groups and the official translations do not
-- agree on one wording: SHINE is a MOVE in one group and a FEELING in another,
-- and words like ATTACK, BAG or CANCEL collide with menu labels this engine
-- already translates elsewhere.  Strings() falls back to the plain key when a
-- catalog has no context-specific entry, so a translation that does not care
-- about the distinction still lands with one entry.
local Strings = require("src.core.Strings")

local EasyChatText = {}

EasyChatText.FILE = "data/generated/gba/easy_chat/words.lua"

-- include/constants/easy_chat.h:1091
EasyChatText.EC_WORD_UNDEFINED = 0xFFFF
-- src/easy_chat_2.c:285
EasyChatText.PASSPHRASE_MYSTERY_EVENT = { 5178, 6167, 4107, 8207 }
-- src/easy_chat_2.c:297
EasyChatText.PASSPHRASE_QUESTIONNAIRE = { 521, 5131, 4144, 4138 }
-- src/easy_chat.c:66
EasyChatText.DEFAULT_PROFILE = { 2601, 4128, 526, 2611 }

local groups, wordMap

function EasyChatText.install(words)
  groups, wordMap = assert(words and words.groups, "easy chat words have no groups"), {}
  for _, group in pairs(groups) do
    for _, w in ipairs(group.words) do
      wordMap[w.id] = w.text
    end
  end
end

local function ensureLoaded()
  if groups then return end
  local rel = EasyChatText.FILE
  local src = assert(require("src.core.game3.dataset").cache():read(rel), rel .. " is not in the cache")
  EasyChatText.install(assert(load(src, "@" .. rel, "t", {}))())
end

function EasyChatText.groups()
  ensureLoaded()
  return groups
end

function EasyChatText.group(groupId)
  return EasyChatText.groups()[groupId]
end

function EasyChatText.rawWord(wordId)
  if not wordId or wordId == EasyChatText.EC_WORD_UNDEFINED then return "" end
  ensureLoaded()
  return wordMap[wordId] or "???"
end

-- include/constants/easy_chat.h:1087
function EasyChatText.decodeWord(wordId)
  if not wordId then return 0, 0 end
  return math.floor(wordId / 512) % 128, wordId % 512
end

function EasyChatText.encodeWord(groupId, index)
  return ((groupId or 0) % 128) * 512 + ((index or 0) % 512)
end

-- src/easy_chat.c:151
local VALUE_GROUPS = { [0] = "species", [18] = "move", [19] = "move", [21] = "species" }

--- The dataset's own name for one of those ids, or nil when it has none.
local function packName(groupId, index)
  local kind = VALUE_GROUPS[groupId]
  if not kind or type(index) ~= "number" or index < 1 then return nil end
  local Pokemon = require("src.core.game3.pokemon")

  local name
  if kind == "species" then
    name = Pokemon.name(index)
  else
    name = Pokemon.moveName(index)
  end

  if type(name) ~= "string" or name == "" then return nil end
  if name == "-------" or name == "?????" then return nil end
  return name
end

--- The catalog's answer for the "group|word" key alone, or nil.  Strings()
--- falls back to the plain key, which is the right default for the vocabulary
--- but not for a name the dataset owns, so look the full key up as a source
--- of its own: that is exactly the entry Strings(raw, context) tries first.
local function contextEntry(raw, context)
  local key = context .. "|" .. raw
  local hit = Strings.lookup(key)
  if hit ~= key then return hit end
  return nil
end

local function labelEntry(key)
  local hit = Strings.lookup(key)
  if hit ~= key and hit ~= "" then return hit end
  return nil
end

function EasyChatText.wordLabel(wordId)
  return ("easyChat.word[%d]"):format(wordId)
end

function EasyChatText.groupLabel(groupId)
  return ("easyChat.group[%d]"):format(groupId)
end

--- One word, given its group and its index within that group.
local function resolve(raw, groupId, index)
  if type(raw) ~= "string" or raw == "" then return raw or "" end
  if raw == "???" then return raw end
  local label = labelEntry(EasyChatText.wordLabel(EasyChatText.encodeWord(groupId, index)))
  if label then return label end
  local context = EasyChatText.context(groupId)
  if VALUE_GROUPS[groupId] then
    -- A species or move name belongs to the dataset, so only an entry that
    -- names the group -- written for this picker on purpose -- comes before
    -- it.  The plain key does not: it is shared with menu labels like CUT or
    -- FLASH, and one of those should not decide what a move is called here.
    local entry = contextEntry(raw, context)
    if entry then return entry end
    return packName(groupId, index) or Strings(raw, context)
  end
  return Strings(raw, context)
end

--- The catalog context for a group id ("easyChat.FEELINGS").
function EasyChatText.context(groupId)
  local group = EasyChatText.group(groupId)
  return "easyChat." .. tostring(group and group.name or groupId)
end

--- A group's name as the picker lists it down its left side.
function EasyChatText.groupName(group)
  if type(group) == "number" then
    group = EasyChatText.group(group)
  end
  local name = group and group.name
  if type(name) ~= "string" or name == "" then return "" end
  return labelEntry(EasyChatText.groupLabel(group.id)) or Strings(name, "easyChat.group")
end

--- One word, by the id the save file stores.
function EasyChatText.word(wordId)
  local raw = EasyChatText.rawWord(wordId)
  if type(raw) ~= "string" or raw == "" then return raw or "" end
  local groupId, index = EasyChatText.decodeWord(wordId)
  return resolve(raw, groupId, index)
end

--- A word the picker draws from its own group list, where the group is known
--- without decoding the id.
function EasyChatText.wordInGroup(entry, group)
  local raw = entry and entry.text
  if type(raw) ~= "string" or raw == "" then return raw or "" end
  if type(group) == "table" then group = group.id end
  local _, index = EasyChatText.decodeWord(entry.id)
  return resolve(raw, group, index)
end

-- src/easy_chat.c:188
function EasyChatText.phrase(words, columns, rows)
  words = words or {}
  columns, rows = columns or 2, rows or 2
  local out, index = {}, 1
  for _ = 1, rows do
    local line = {}
    for _ = 1, columns do
      local word = EasyChatText.word(words[index])
      if word ~= "" then line[#line + 1] = word end
      index = index + 1
    end
    out[#out + 1] = table.concat(line, " ")
  end
  return table.concat(out, "\n")
end

return EasyChatText
