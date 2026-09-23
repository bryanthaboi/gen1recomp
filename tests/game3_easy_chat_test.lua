-- Unit test for Game 3 Easy Chat system, Profile Screen, Specials 0x60/0x61,
-- and the Pewter City Pokemon Center MysteryEventClub woman script behavior.

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("[ok] " .. name)
  else
    print("[FAIL] " .. name .. ": " .. tostring(err))
    error(err)
  end
end

local haveWords = require("tests.game3_cache").mount("easy_chat/words.lua") ~= nil
local EasyChatText = require("src.core.game3.easy_chat_text")
local Schema = require("src.core.game3.save_schema_firered")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Adapters = require("src.core.game3.scripting.adapters")
local Flags = require("src.core.game3.scripting.flags")

test("decodes authentic word IDs and passphrases", function()
  if not haveWords then
    print("[skip] the word checks read easy_chat/words.lua from the ROM cache")
    return
  end
  -- Default profile
  local defText = EasyChatText.phrase(EasyChatText.DEFAULT_PROFILE, 2, 2)
  assert(defText:find("I AM A"), "Default profile line 1")
  assert(defText:find("POKéMON FRIEND"), "Default profile line 2")

  -- Mystery Event passphrase
  assert(EasyChatText.rawWord(EasyChatText.PASSPHRASE_MYSTERY_EVENT[1]) == "MYSTERY")
  assert(EasyChatText.rawWord(EasyChatText.PASSPHRASE_MYSTERY_EVENT[2]) == "EVENT")
  assert(EasyChatText.rawWord(EasyChatText.PASSPHRASE_MYSTERY_EVENT[3]) == "IS")
  assert(EasyChatText.rawWord(EasyChatText.PASSPHRASE_MYSTERY_EVENT[4]) == "EXCITING")

  -- Questionnaire passphrase
  assert(EasyChatText.rawWord(EasyChatText.PASSPHRASE_QUESTIONNAIRE[1]) == "LINK")
  assert(EasyChatText.rawWord(EasyChatText.PASSPHRASE_QUESTIONNAIRE[2]) == "TOGETHER")
  assert(EasyChatText.rawWord(EasyChatText.PASSPHRASE_QUESTIONNAIRE[3]) == "WITH")
  assert(EasyChatText.rawWord(EasyChatText.PASSPHRASE_QUESTIONNAIRE[4]) == "ALL")
end)

test("persists easyChatProfile in save schema", function()
  local session = Schema.newGame()
  assert(session.easyChatProfile ~= nil)
  assert(#session.easyChatProfile == 4)

  -- Modify profile
  session.easyChatProfile = { 5178, 6167, 4107, 8207 }
  local save = Schema.toSaveTable(session)
  assert(save.easyChatProfile ~= nil)
  assert(save.easyChatProfile[1] == 5178)

  -- Restore
  local loaded = Schema.fromSaveTable(save)
  assert(loaded.easyChatProfile ~= nil)
  assert(loaded.easyChatProfile[1] == 5178)
  assert(loaded.easyChatProfile[4] == 8207)
end)

test("handles ShowEasyChatScreen special with custom profile (VAR_RESULT=1, VAR_0x8004=1, flag 0x82D)", function()
  local session = Schema.newGame()
  local store = Flags.newStore()
  session.store = store
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return session end,
  }

  local ctx = {
    vars = {},
    specialVars = { [0x8004] = 0 }, -- EASY_CHAT_TYPE_PROFILE
  }

  local customWords = { 2601, 4128, 526, 2611 } -- standard "I AM A POKéMON FRIEND"
  local adapters = Adapters.stub({
    openEasyChat = function(opts, done)
      assert(opts.type == 0)
      done(true, customWords)
    end,
  })

  local yielded = Natives.ALLOW["special:" .. Std.SPECIAL.ShowEasyChatScreen](ctx, adapters)
  -- Poll until done
  if ctx.nativePoll then
    while not ctx.nativePoll() do end
  end

  -- Assertions:
  -- 1. VAR_RESULT (0x800D) = 1 (TRUE)
  assert(Flags.getVar(nil, ctx, 0x800D) == 1)
  -- 2. VAR_0x8004 = 1 (custom phrase, does not match MYSTERY EVENT IS EXCITING)
  assert(Flags.getVar(nil, ctx, 0x8004) == 1)
  -- 3. FLAG_SYS_SET_TRAINER_CARD_PROFILE (0x82D) is set
  assert(Flags.getFlag(store, ctx, 0x82D) == true)
  assert(session.flags[0x82D] == true)
  -- 4. session.easyChatProfile is updated
  assert(session.easyChatProfile[1] == customWords[1])
end)

test("handles ShowEasyChatScreen special with mystery event passphrase (VAR_0x8004=0)", function()
  local session = Schema.newGame()
  local store = Flags.newStore()
  session.store = store
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return session end,
  }

  local ctx = {
    vars = {},
    specialVars = { [0x8004] = 0 }, -- EASY_CHAT_TYPE_PROFILE
  }

  local mysteryWords = EasyChatText.PASSPHRASE_MYSTERY_EVENT
  local adapters = Adapters.stub({
    openEasyChat = function(opts, done)
      done(true, mysteryWords)
    end,
  })

  Natives.ALLOW["special:" .. Std.SPECIAL.ShowEasyChatScreen](ctx, adapters)
  if ctx.nativePoll then
    while not ctx.nativePoll() do end
  end

  -- VAR_RESULT = 1 (TRUE)
  assert(Flags.getVar(nil, ctx, 0x800D) == 1)
  -- VAR_0x8004 = 0 (matches special passphrase!)
  assert(Flags.getVar(nil, ctx, 0x8004) == 0)
  assert(Flags.getFlag(store, ctx, 0x82D) == true)
end)

test("handles ShowEasyChatScreen special when cancelled (VAR_RESULT=0)", function()
  local session = Schema.newGame()
  local store = Flags.newStore()
  session.store = store
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return session end,
  }

  local ctx = {
    vars = {},
    specialVars = { [0x8004] = 0 },
  }

  local adapters = Adapters.stub({
    openEasyChat = function(opts, done)
      done(false, opts.words)
    end,
  })

  Natives.ALLOW["special:" .. Std.SPECIAL.ShowEasyChatScreen](ctx, adapters)
  if ctx.nativePoll then
    while not ctx.nativePoll() do end
  end

  -- VAR_RESULT = 0 (FALSE)
  assert(Flags.getVar(nil, ctx, 0x800D) == 0)
  -- VAR_0x8004 = 1 (not 0, so doesn't take special phrase branch)
  assert(Flags.getVar(nil, ctx, 0x8004) == 1)
  -- FLAG_SYS_SET_TRAINER_CARD_PROFILE not set
  assert(not Flags.getFlag(store, ctx, 0x82D))
end)

test("formats and displays phrase with ShowEasyChatMessage", function()
  if not haveWords then
    print("[skip] the phrase check reads easy_chat/words.lua from the ROM cache")
    return
  end
  local session = Schema.newGame()
  session.easyChatProfile = { 5178, 6167, 4107, 8207 }
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return session end,
  }

  local openedMsg = nil
  local adapters = Adapters.stub({
    openMessage = function(text)
      openedMsg = text
    end,
  })

  Natives.ALLOW["special:" .. Std.SPECIAL.ShowEasyChatMessage]({}, adapters)
  assert(openedMsg ~= nil)
  assert(openedMsg:find("MYSTERY EVENT"), "Contains line 1 words")
  assert(openedMsg:find("IS EXCITING"), "Contains line 2 words")
end)

test("extracts easy chat data from ROM via EasyChatExtract", function()
  local EasyChatExtract = require("src.import.gba.easy_chat_extract")
  assert(EasyChatExtract.extractFromRom ~= nil)
  assert(EasyChatExtract.run ~= nil)
end)

print("[test] All Easy Chat tests passed!")
