#!/usr/bin/env luajit
-- The Easy Chat vocabulary is engine data extracted from the ROM, so it stays
-- English in easy_chat_data.lua and is translated where it is drawn
-- (src/core/game3/easy_chat_text.lua).  Each word carries its group's context,
-- because the same English word means different things in different groups --
-- and collides with menu labels this engine already translates elsewhere.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

local Strings = require("src.core.Strings")
local EasyChatData = require("src.core.game3.easy_chat_data")
local EasyChatText = require("src.core.game3.easy_chat_text")

local function groupNamed(name)
  for id, group in pairs(EasyChatData.GROUPS) do
    if group.name == name then return id, group end
  end
end

local moveId, moveGroup = groupNamed("MOVE 1")
local feelId, feelGroup = groupNamed("FEELINGS")
check(moveGroup and feelGroup, "the extracted data still has the MOVE 1 and FEELINGS groups")

local moveWord = moveGroup.words[1]
local feelWord = feelGroup.words[1]

-- ------------------------------------------------------ no catalog loaded
Strings.load({})
check(EasyChatText.word(moveWord.id) == moveWord.text, "a word is its English self with no catalog")
check(EasyChatText.groupName(feelGroup) == "FEELINGS", "so is a group name")
check(EasyChatData.getWord(moveWord.id) == moveWord.text,
  "and the extracted data itself is never rewritten")

-- ------------------------------------------------------- a mod's catalog
Strings.load({ strings = {
  ["easyChat.group|FEELINGS"] = "SENTIMENTS",
  ["easyChat.MOVE 1|" .. moveWord.text] = "ATTAQUE-FR",
  [feelWord.text] = "SANS-CONTEXTE",
} })

check(EasyChatText.groupName(feelGroup) == "SENTIMENTS", "a group name translates under its own context")
check(EasyChatText.word(moveWord.id) == "ATTAQUE-FR", "a word translates under its group's context")
check(EasyChatText.wordInGroup(moveWord, moveGroup) == "ATTAQUE-FR",
  "the picker's own list resolves the same key without decoding the id")
check(EasyChatText.word(feelWord.id) == "SANS-CONTEXTE",
  "a catalog that does not care about the group still lands through the plain key")

local phrase = EasyChatText.phrase({ moveWord.id, feelWord.id }, 2, 1)
check(phrase == "ATTAQUE-FR SANS-CONTEXTE", "a saved profile prints its words translated")
check(EasyChatText.phrase({}, 2, 2) == "\n", "an empty profile still yields its rows")

-- A word id that is not in the table keeps the data module's own placeholder.
check(EasyChatText.word(EasyChatData.EC_WORD_UNDEFINED) == "", "an unset slot stays empty")

Strings.load({})

T.finish("game3_easy_chat_text_test")
