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
  local groupId = EasyChatData.decodeWord(wordId)
  return Strings(raw, EasyChatText.context(groupId))
end

--- A word the picker draws from its own group list, where the group is known
--- without decoding the id.
function EasyChatText.wordInGroup(entry, group)
  local raw = entry and entry.text
  if type(raw) ~= "string" or raw == "" then return raw or "" end
  if type(group) == "table" then group = group.id end
  return Strings(raw, EasyChatText.context(group))
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
