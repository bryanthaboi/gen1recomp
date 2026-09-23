#!/usr/bin/env luajit
-- The Easy Chat vocabulary is read from the ROM (easy_chat/words.lua), so it
-- stays English in the cache and is translated where it is drawn
-- (src/core/game3/easy_chat_text.lua).  Each word carries its group's context,
-- because the same English word means different things in different groups --
-- and collides with menu labels this engine already translates elsewhere.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
require("tests.game3_cache").mountOrSkip("game3_easy_chat_text_test")

local T = require("tests.harness")
local check = T.check

local Strings = require("src.core.Strings")
local EasyChatText = require("src.core.game3.easy_chat_text")

EasyChatText.install({ groups = {
  [9] = { id = 9, name = "FEELINGS", words = {
    { id = 9 * 512 + 0, text = "MEET" }, { id = 9 * 512 + 1, text = "PLAY" } } },
  [18] = { id = 18, name = "MOVE 1", words = {
    { id = 18 * 512 + 71, text = "ABSORB", value = 71 }, { id = 18 * 512 + 51, text = "ACID", value = 51 } } },
  [21] = { id = 21, name = "POKéMON", words = {
    { id = 21 * 512 + 63, text = "ABRA", value = 63 }, { id = 21 * 512 + 142, text = "AERODACTYL", value = 142 } } },
} })

local function groupNamed(name)
  for id, group in pairs(EasyChatText.groups()) do
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
check(EasyChatText.rawWord(moveWord.id) == moveWord.text,
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
check(EasyChatText.word(EasyChatText.EC_WORD_UNDEFINED) == "", "an unset slot stays empty")

Strings.load({})

T.finish("game3_easy_chat_text_test")
