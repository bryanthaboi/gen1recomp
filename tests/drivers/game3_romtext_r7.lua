local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_romtext_r7"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS romtext_r7")
    love.event.quit(0)
  else
    print("FAIL romtext_r7 failures=" .. failures)
    love.event.quit(1)
  end
end

local function run(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Strings = require("src.core.Strings")
  local EasyChat = require("src.ui.game3.easy_chat")
  local EasyChatText = require("src.core.game3.easy_chat_text")
  local Records = require("src.ui.game3.minigame_records")
  local LinkMenu = require("src.ui.game3.link_menu")
  local UnionRoomScreen = require("src.ui.game3.union_room")
  local Union = require("src.core.game3.link.union_room")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  -- pokefirered/src/easy_chat_2.c:309 sEasyChatScreenTemplates[0]
  local st = EasyChat.open({ type = 0, words = EasyChatText.DEFAULT_PROFILE, session = session })
  U.wait(10)
  result(st.title == "PROFILE" and st.instr1 == "Combine four words or phrases",
    "easy chat profile title and instructions come from the ROM")
  result(EasyChatText.phrase(st.words, 2, 2) == "I AM A\nPOKéMON FRIEND",
    "the default profile reads I AM A / POKéMON FRIEND from easy_chat/words.lua")
  local footer = EasyChat.footerLabels()
  result(footer[1] == "DEL. ALL" and footer[2] == "CANCEL" and footer[3] == "OK",
    "the footer is gText_DelAllCancelOk split on its CLEAR_TO codes")
  U.shot(game, DIR .. "/r7_easy_chat_profile.png")

  st.mode = "GROUP"
  U.wait(4)
  local function names(list)
    local out = {}
    for i, g in ipairs(list) do out[i] = EasyChatText.groupName(g) end
    return table.concat(out, ",")
  end
  -- pokefirered/src/easy_chat.c:500 PopulateECGroups
  result(#st.groups == 16 and EasyChatText.groupName(st.groups[1]) == "TRAINER"
      and EasyChatText.groupName(st.groups[16]) == "ADJECTIVES",
    "a fresh save lists TRAINER..ADJECTIVES only (" .. names(st.groups) .. ")")
  U.shot(game, DIR .. "/r7_easy_chat_groups.png")

  local Dex = require("src.core.game3.dex")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local PIKACHU = 25
  Dex.registerEncounter(session.dex, PIKACHU, session)
  Flags.setFlag(Space.store, nil, Flags.IDS.SYS_GAME_CLEAR, true)
  Flags.setFlag(Space.store, nil, Flags.IDS.SYS_NATIONAL_DEX, true)
  local unlocked = EasyChat.populateGroups(session)
  local n = #unlocked
  result(n == 21 and EasyChatText.groupName(unlocked[1]) == "POKéMON"
      and EasyChatText.groupName(unlocked[18]) == "EVENTS"
      and EasyChatText.groupName(unlocked[n]) == "POKéMON2",
    "seen mons, game clear and the National Dex add POKéMON first, EVENTS/MOVE 1/MOVE 2, POKéMON2 last ("
      .. names(unlocked) .. ")")
  result(#unlocked[1].words == 1 and unlocked[1].words[1].text == "PIKACHU",
    "the POKéMON group holds only seen species (" .. tostring(#unlocked[1].words) .. ")")
  Flags.setFlag(Space.store, nil, Flags.IDS.SYS_GAME_CLEAR, false)
  Flags.setFlag(Space.store, nil, Flags.IDS.SYS_NATIONAL_DEX, false)

  local feelings
  for i, g in ipairs(st.groups) do
    if g.name == "FEELINGS" then feelings = i end
  end
  st.groupCursor = feelings or 1
  st.mode = "WORD"
  st.wordCursor, st.wordPage = 1, 0
  U.wait(4)
  U.shot(game, DIR .. "/r7_easy_chat_feelings_words.png")

  st.mode = "CANCEL_CONFIRM"
  U.wait(4)
  U.shot(game, DIR .. "/r7_easy_chat_quit_editing.png")

  Strings.load({ strings = {
    ["easyChat.group|FEELINGS"] = "SENTIMENTS",
    ["easyChat.FEELINGS|HAPPY"] = "HEUREUX",
    ["easyChat.group|POKéMON2"] = "POKéMON 2",
  } })
  st.mode = "GROUP"
  U.wait(4)
  result(EasyChatText.groupName(st.groups[feelings or 1]) == "SENTIMENTS",
    "an easyChat.group| catalog entry reaches the ROM group name")
  U.shot(game, DIR .. "/r7_easy_chat_groups_translated.png")
  st.mode = "WORD"
  U.wait(4)
  local happy
  for _, w in ipairs(st.groups[feelings or 1].words) do
    if w.text == "HAPPY" then happy = w end
  end
  result(happy ~= nil and EasyChatText.wordInGroup(happy, st.groups[feelings or 1]) == "HEUREUX",
    "an easyChat.FEELINGS| catalog entry reaches the ROM word")
  Strings.load({})
  EasyChat.close(false)
  U.wait(10)

  session.berryCrushPressingSpeeds = { 0x0580, 0x0312, 0, 0 }
  Records.show("berry_crush", session)
  U.wait(10)
  local lines = Records.lines()
  result(lines[1] and lines[1].text == "BERRY CRUSH" and lines[3] and lines[3].text == "2 PLAYERS",
    "berry crush rankings read gText_BerryCrush2 / gText_Var1Players")
  result(lines[4] and lines[4].text == "  5.50 Times/sec.", "and the speed is gText_XDotY3 + gText_TimesPerSec")
  U.shot(game, DIR .. "/r7_berry_crush_rankings.png")
  Records.close()
  Records.show("pokemon_jump", session)
  U.wait(10)
  result(Records.lines()[1].text == "POKéMON JUMP RECORDS", "pokemon jump records title is gText_PkmnJumpRecords")
  U.shot(game, DIR .. "/r7_pokemon_jump_records.png")
  Records.close()
  Records.show("dodrio", session)
  U.wait(10)
  result(Records.lines()[1].text == "DODRIO BERRY-PICKING RECORDS", "dodrio records title is gText_BerryPickingRecords")
  U.shot(game, DIR .. "/r7_dodrio_records.png")
  Records.close()
  U.wait(10)

  LinkMenu.show({})
  for _ = 1, 30 do LinkMenu.update(1 / 60) U.wait(1) end
  result(LinkMenu.rows[1] and LinkMenu.rows[1].label == "People trading:",
    "the wireless status rows are sHeaderTexts[1..4]")
  U.shot(game, DIR .. "/r7_wireless_status.png")
  LinkMenu.close()
  U.wait(10)

  result(UnionRoomScreen.labelFor({ key = "GREETINGS" }) == "GREETINGS"
    and UnionRoomScreen.activityLabel(Union.ACTIVITY.TRADE) == "POKéMON TRADES",
    "union room labels read sListMenuItems_InviteToActivity / sLinkGroupActivityNameTexts")
  Union.activity = Union.ACTIVITY.CHAT + Union.IN_UNION_ROOM
  Union._requestName = "BLUE"
  local prompt = Union.requestPrompt()
  result(prompt == "BLUE contacted you for\nCHAT. Accept?", "the contact prompt is gText_UR_PlayerContactedYouForXAccept")
  Union.activity, Union._requestName = nil, nil
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then result(false, "driver raised: " .. tostring(err)) end
  finish()
end
