-- Translation seam for the Easy Chat vocabulary.
--
-- src/core/game3/easy_chat_data.lua is written by the extractor
-- (src/import/gba/easy_chat_extract.lua) from the ROM's own word tables, so it
-- stays exactly what the cart holds: English words, keyed by the ids the save
-- file stores.  Everything that puts one of those words on screen goes through
-- here instead, the same "data stays raw, the display translates" split the
-- rest of game3 uses.
--
-- A word carries its group's context, because the same English word means
-- different things in different groups and the official translations do not
-- agree on one wording: SHINE is a MOVE in one group and a FEELING in another,
-- and words like ATTACK, BAG or CANCEL collide with menu labels this engine
-- already translates elsewhere.  Strings() falls back to the plain key when a
-- catalog has no context-specific entry, so a translation that does not care
-- about the distinction still lands with one entry.
local EasyChatData = require("src.core.game3.easy_chat_data")
local Strings = require("src.core.Strings")

local EasyChatText = {}

-- pret's four "value" groups do not carry text at all: their word data is a
-- list of ids, and easy_chat.c prints them through gSpeciesNames / gMoveNames
-- (EC_GROUP_POKEMON, EC_GROUP_MOVE_1, EC_GROUP_MOVE_2 and
-- EC_GROUP_POKEMON_NATIONAL).  src/import/gba/easy_chat_extract.lua reads them
-- the same way, so the text it wrote into the data module is a copy of a name
-- the dataset already holds -- and a copy that goes stale as soon as anything
-- renames a species or a move.  Resolve those two groups live instead, so a
-- mod's renames -- a translation's species_names / move_names catalog first
-- of all -- reach the picker like they reach every other screen.
local VALUE_GROUPS = { [0] = "species", [18] = "move", [19] = "move", [21] = "species" }

--- The dataset's own name for one of those ids, or nil when it has none.
local function packName(groupId, index)
  local kind = VALUE_GROUPS[groupId]
  if not kind or type(index) ~= "number" or index < 1 then return nil end
  local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not ok or type(Pokemon) ~= "table" then return nil end

  local name, placeholder
  if kind == "species" then
    if not Pokemon.name then return nil end
    name = Pokemon.name(index)
    placeholder = Strings("POKéMON %03d", index)
  else
    if not Pokemon.moveName then return nil end
    name = Pokemon.moveName(index)
    placeholder = Strings("MOVE %d", index)
  end

  -- Both answer with a placeholder when the pack has no entry for the id; the
  -- word the cart shipped beats "POKéMON 063".
  if type(name) ~= "string" or name == "" then return nil end
  if name == placeholder or name == "-------" or name == "?????" then return nil end
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

--- One word, given its group and its index within that group.
local function resolve(raw, groupId, index)
  if type(raw) ~= "string" or raw == "" then return raw or "" end
  -- getWord's marker for an id no group claims: nothing to resolve it to.
  if raw == "???" then return raw end
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
  local group = EasyChatData.GROUPS and EasyChatData.GROUPS[groupId]
  return "easyChat." .. tostring(group and group.name or groupId)
end

--- A group's name as the picker lists it down its left side.
function EasyChatText.groupName(group)
  if type(group) == "number" then
    group = EasyChatData.GROUPS and EasyChatData.GROUPS[group]
  end
  local name = group and group.name
  if type(name) ~= "string" or name == "" then return "" end
  return Strings(name, "easyChat.group")
end

--- One word, by the id the save file stores.
function EasyChatText.word(wordId)
  local raw = EasyChatData.getWord(wordId)
  if type(raw) ~= "string" or raw == "" then return raw or "" end
  local groupId, index = EasyChatData.decodeWord(wordId)
  return resolve(raw, groupId, index)
end

--- A word the picker draws from its own group list, where the group is known
--- without decoding the id.
function EasyChatText.wordInGroup(entry, group)
  local raw = entry and entry.text
  if type(raw) ~= "string" or raw == "" then return raw or "" end
  if type(group) == "table" then group = group.id end
  local _, index = EasyChatData.decodeWord(entry.id)
  return resolve(raw, group, index)
end

--- The profile as a message box shows it: the same rows EasyChatData builds,
--- with every word translated.
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
