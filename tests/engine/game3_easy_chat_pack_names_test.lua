#!/usr/bin/env luajit
-- The POKéMON, MOVE 1, MOVE 2 and POKéMON (NAT) groups are lists of species
-- and move ids: pret prints them through gSpeciesNames / gMoveNames, so the
-- picker resolves them against the dataset instead of the text the extractor
-- happened to copy into easy_chat_data.lua.

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

local speciesId, speciesGroup = groupNamed("POKéMON")
local moveId, moveGroup = groupNamed("MOVE 1")
local feelId, feelGroup = groupNamed("FEELINGS")
check(speciesGroup and moveGroup and feelGroup,
  "the extracted data still has the POKéMON, MOVE 1 and FEELINGS groups")

local speciesWord = speciesGroup.words[1]
local moveWord = moveGroup.words[1]
local feelWord = feelGroup.words[1]

-- A word's index inside its group is the species / move id it stands for.
local _, speciesIndex = EasyChatData.decodeWord(speciesWord.id)
local _, moveIndex = EasyChatData.decodeWord(moveWord.id)

-- A dataset that renamed both, the way a mod's patches do.
local realPokemon = package.loaded["src.core.game3.pokemon"]
local renamed = {
  name = function(id)
    if id == speciesIndex then return "RENOMMé" end
    return Strings("POKéMON %03d", id)
  end,
  moveName = function(id)
    if id == moveIndex then return "ATTAQUE" end
    return Strings("MOVE %d", id)
  end,
}
package.loaded["src.core.game3.pokemon"] = renamed

Strings.load({})
check(EasyChatText.word(speciesWord.id) == "RENOMMé", "a species word follows the dataset")
check(EasyChatText.word(moveWord.id) == "ATTAQUE", "so does a move word")
check(EasyChatText.wordInGroup(speciesWord, speciesGroup) == "RENOMMé",
  "the picker's own list resolves it the same way")
check(EasyChatText.wordInGroup(moveWord, moveGroup) == "ATTAQUE", "for a move too")
check(EasyChatText.phrase({ speciesWord.id, moveWord.id }, 2, 1) == "RENOMMé ATTAQUE",
  "and a saved profile reads back with them")
check(EasyChatData.getWord(speciesWord.id) == speciesWord.text,
  "while the extracted data itself is never rewritten")

-- A group that is not one of the four never consults the dataset.
check(EasyChatText.word(feelWord.id) == feelWord.text, "an ordinary word is untouched")

-- An entry written for the picker wins over the dataset's name.
Strings.load({ strings = { ["easyChat.POKéMON|" .. speciesWord.text] = "DU CATALOGUE" } })
check(EasyChatText.word(speciesWord.id) == "DU CATALOGUE",
  "a catalog entry aimed at the word beats the dataset")

-- A bare key is shared with the menu labels this engine already translates,
-- so it does not: the dataset stays in charge of a species or move name.
Strings.load({ strings = { [speciesWord.text] = "SANS-CONTEXTE", [feelWord.text] = "SANS-CONTEXTE" } })
check(EasyChatText.word(speciesWord.id) == "RENOMMé",
  "a bare key does not outrank the dataset for a species word")
check(EasyChatText.word(feelWord.id) == "SANS-CONTEXTE",
  "while an ordinary word still takes it")

-- A group-scoped entry is honoured for what it is, even when it happens to
-- match the bare key's value or keeps the English word on purpose.
Strings.load({ strings = {
  ["easyChat.POKéMON|" .. speciesWord.text] = "MEME VALEUR", [speciesWord.text] = "MEME VALEUR",
  ["easyChat.MOVE 1|" .. moveWord.text] = moveWord.text,
} })
check(EasyChatText.word(speciesWord.id) == "MEME VALEUR",
  "a group-scoped entry equal to the bare one still wins over the dataset")
check(EasyChatText.word(moveWord.id) == moveWord.text,
  "and one that keeps the English word keeps it, instead of the dataset's rename")
Strings.load({})

-- A pack with no entry for the id answers with a placeholder; the word the
-- cart shipped is better than "POKéMON 063".
package.loaded["src.core.game3.pokemon"] = {
  name = function(id) return Strings("POKéMON %03d", id) end,
  moveName = function() return "-------" end,
}
check(EasyChatText.word(speciesWord.id) == speciesWord.text,
  "a placeholder falls back to the extracted word")
check(EasyChatText.word(moveWord.id) == moveWord.text, "and so does an empty move name")

-- No dataset at all (the module missing, or answering nothing) is the same.
package.loaded["src.core.game3.pokemon"] = { }
check(EasyChatText.word(speciesWord.id) == speciesWord.text, "a dataset without names changes nothing")

package.loaded["src.core.game3.pokemon"] = realPokemon

T.finish("game3_easy_chat_pack_names_test")
