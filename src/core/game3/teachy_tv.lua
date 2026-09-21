-- pokefirered/src/teachy_tv.c:420 InitTeachyTvController

local Strings = require("src.core.Strings")
local TextIR = require("src.core.game3.scripting.text_ir")

local TeachyTv = {}

-- pokefirered/include/constants/items.h:438
TeachyTv.ITEM_TEACHY_TV = 366
-- pokefirered/include/constants/items.h:436
TeachyTv.ITEM_TM_CASE = 364

-- pokefirered/include/teachy_tv.h:4
TeachyTv.SCRIPT = {
  BATTLE = 0,
  STATUS = 1,
  MATCHUPS = 2,
  CATCHING = 3,
  TMS = 4,
  REGISTER = 5,
}

-- pokefirered/src/teachy_tv.c:196 gTeachyTvString_Cancel
TeachyTv.CANCEL = -2
-- pokefirered/src/teachy_tv.c:713 TeachyTvOptionListController
TeachyTv.NO_INPUT = -1

-- pokefirered/src/teachy_tv.c:424
TeachyTv.MODE = { FRESH = 0, RESUME_LIST = 1, RESUME_SCRIPT = 2 }

-- pokefirered/include/constants/battle.h:78 B_OUTCOME_DREW
local B_OUTCOME_DREW = 3

-- pokefirered/src/teachy_tv.c:145 sWindowTemplates
local PAGE_WIDTH = 208

-- pokefirered/src/data/text/teachy_tv.h:1
TeachyTv.LESSONS = {
  [TeachyTv.SCRIPT.BATTLE] = {
    index = TeachyTv.SCRIPT.BATTLE,
    key = "BATTLE",
    label = Strings("Teach me how to battle."),
    intro = Strings(
      "Today, the POKé DUDE's here to\\n" ..
      "tell you about how you can battle\\l" ..
      "POKéMON!\\p" ..
      "Say you're out for a stroll when,\\n" ..
      "suddenly, a wild POKéMON appears!\\p" ..
      "It's up to you to smartly use your\\n" ..
      "POKéMON and their moves to reduce\\l" ..
      "the opponent's HP to nothing, and\\l" ..
      "claim victory!\\p" ..
      "I'll show you how to do that in\\n" ..
      "person and for sure!\\p" ..
      "All righty, here goes!\\p" ..
      "Keep your eyes glued to the super\\n" ..
      "POKé DUDE SHOW!"),
    outro = Strings(
      "Well, did you get that?\\p" ..
      "Even if your own POKéMON's HP\\n" ..
      "falls to zero, and it becomes\\l" ..
      "unable to battle, not to worry!\\p" ..
      "Just take it to any POKéMON\\n" ..
      "CENTER and heal it!\\p" ..
      "All righty, be seeing you!\\p" ..
      "Remember, TRAINERS, a good deed\\n" ..
      "a day brings happiness to stay!"),
  },
  [TeachyTv.SCRIPT.STATUS] = {
    index = TeachyTv.SCRIPT.STATUS,
    key = "STATUS",
    label = Strings("What are status problems?"),
    intro = Strings(
      "Today, the POKé DUDE's here to\\n" ..
      "tell you about status problems!\\p" ..
      "Status problems include poisoning,\\n" ..
      "paralysis, sleep, burn…\\p" ..
      "There are a couple others, but\\n" ..
      "they really are trouble.\\p" ..
      "Get any one, and your POKéMON\\n" ..
      "may become useless in battle.\\p" ..
      "You know, it hurts the POKé DUDE\\n" ..
      "to see a POKéMON suffer…\\p" ..
      "So, what should you do if your\\n" ..
      "POKéMON gets a status problem?\\p" ..
      "Well, you've got me to show you!\\p" ..
      "All righty, here goes!\\p" ..
      "Keep your eyes glued to the super\\n" ..
      "POKé DUDE SHOW!"),
    outro = Strings(
      "Poisoning or paralysis don't go\\n" ..
      "away after a battle.\\p" ..
      "If a POKéMON is poisoned, it loses\\n" ..
      "HP even while you're walking.\\p" ..
      "You should heal POKéMON of these\\n" ..
      "kinds of problems right away.\\p" ..
      "Use an item, or try to get to a\\n" ..
      "POKéMON CENTER for healing.\\p" ..
      "That wasn't hard, was it?\\n" ..
      "All righty, be seeing you!\\p" ..
      "Remember, TRAINERS, a good deed\\n" ..
      "a day brings happiness to stay!"),
  },
  [TeachyTv.SCRIPT.MATCHUPS] = {
    index = TeachyTv.SCRIPT.MATCHUPS,
    key = "MATCHUPS",
    label = Strings("What are type matchups?"),
    intro = Strings(
      "Does everyone know about type\\n" ..
      "matchups?\\p" ..
      "POKéMON and their moves all\\n" ..
      "belong to certain types.\\p" ..
      "For example, there are such types\\n" ..
      "as GRASS and WATER.\\p" ..
      "You need to consider the type of\\n" ..
      "the move used to attack…\\p" ..
      "And, the type of the POKéMON that\\n" ..
      "is hit by that attack.\\p" ..
      "Depending on how those two types\\n" ..
      "match up, the damage can change.\\p" ..
      "You see, it depends on whether\\n" ..
      "the type matchup is good or bad.\\p" ..
      "If you don't know how matchups\\n" ..
      "work, battles will be tough.\\p" ..
      "So, let me demonstrate exactly\\n" ..
      "what I mean.\\p" ..
      "All righty, here goes!\\p" ..
      "Keep your eyes glued to the super\\n" ..
      "POKé DUDE SHOW!"),
    outro = Strings(
      "Is it possible to launch an attack\\n" ..
      "that will inflict heavy damage?\\p" ..
      "Does the opposing POKéMON pose\\n" ..
      "a threat to your POKéMON?\\p" ..
      "Is there any chance that it may\\n" ..
      "have disastrously tough moves?\\p" ..
      "Watch the type matchups to gain\\n" ..
      "the upper hand!\\p" ..
      "All righty, be seeing you!\\p" ..
      "Oh, for the COOL-type POKé DUDE,\\n" ..
      "AWESOME-type kids like you match\\l" ..
      "up perfectly!\\p" ..
      "Remember, a good deed a day\\n" ..
      "brings happiness to stay!"),
  },
  [TeachyTv.SCRIPT.CATCHING] = {
    index = TeachyTv.SCRIPT.CATCHING,
    key = "CATCHING",
    label = Strings("I want to catch POKéMON."),
    intro = Strings(
      "Today, the POKé DUDE's going to\\n" ..
      "show you how to catch POKéMON!\\p" ..
      "Just imagine… A groovy POKéMON\\n" ..
      "suddenly appearing in the wild!\\p" ..
      "Oh, you want it!\\n" ..
      "You just can't help it!\\p" ..
      "Oh, you have to catch it!\\n" ..
      "You gotta have it!\\p" ..
      "Let me show you how you can make\\n" ..
      "it happen!\\p" ..
      "All righty, here goes!\\p" ..
      "Keep your eyes glued to the super\\n" ..
      "POKé DUDE SHOW!"),
    outro = Strings(
      "If your first POKé BALL fails to\\n" ..
      "catch the POKéMON, don't give up!\\p" ..
      "Keep throwing POKé BALLS…\\n" ..
      "It's bound to work sometime!\\p" ..
      "All righty, be seeing you!\\p" ..
      "Remember, TRAINERS, a good deed\\n" ..
      "a day brings happiness to stay!"),
  },
  [TeachyTv.SCRIPT.TMS] = {
    index = TeachyTv.SCRIPT.TMS,
    key = "TMS",
    label = Strings("Teach me about TMs."),
    intro = Strings(
      "Hey, everyone!\\n" ..
      "Do you all have TMs?\\p" ..
      "A TM, Technical Machine, is an\\n" ..
      "amazingly great item!\\p" ..
      "It teaches POKéMON a move that\\n" ..
      "it may not learn when leveling up!\\p" ..
      "Isn't that just great? What a\\n" ..
      "convenient world we live in!\\p" ..
      "Open the TM CASE and check out\\n" ..
      "the TMs you have.\\p" ..
      "You can check them out in detail,\\n" ..
      "too."),
    outro = Strings(
      "Wow, I talked a lot today!\\n" ..
      "All righty, be seeing you!\\p" ..
      "Remember, TRAINERS, a good deed\\n" ..
      "a day brings happiness to stay!"),
  },
  [TeachyTv.SCRIPT.REGISTER] = {
    index = TeachyTv.SCRIPT.REGISTER,
    key = "REGISTER",
    label = Strings("How do I register an item?"),
    intro = Strings(
      "A TRAINER's BAG has a bunch of\\n" ..
      "nifty, convenient features!\\p" ..
      "Take stuff in the KEY ITEMS\\n" ..
      "POCKET, for instance.\\p" ..
      "You can use a key item without\\n" ..
      "opening the BAG every time.\\p" ..
      "For example, let's pretend I have\\n" ..
      "a TEACHY TV in my BAG.\\p" ..
      "I can register it for instant use,\\n" ..
      "and I'll show you how!\\p" ..
      "All righty, here goes!\\p" ..
      "Keep your eyes glued to the sorta\\n" ..
      "super POKé DUDE SHOW!"),
    outro = Strings(
      "And now, your TEACHY TV is\\n" ..
      "registered.\\p" ..
      "How do you use it?\\n" ..
      "Well, here's how it works.\\p" ..
      "Once an item in the KEY ITEMS\\n" ..
      "POKCET is registered, you can use\\l" ..
      "it by pressing SELECT.\\p" ..
      "So, you've given yourself\\n" ..
      "one-touch access to TEACHY TV.\\p" ..
      "All it takes for you to see me is\\n" ..
      "pressing one button!\\p" ..
      "That kind of attention is a little\\n" ..
      "embarrassing!\\p" ..
      "All righty, be seeing you!\\p" ..
      "Remember, TRAINERS, a good deed\\n" ..
      "a day brings happiness to stay!"),
  },
}

-- pokefirered/src/teachy_tv.c:168 sListMenuItems
TeachyTv.ORDER = {
  TeachyTv.SCRIPT.BATTLE,
  TeachyTv.SCRIPT.STATUS,
  TeachyTv.SCRIPT.MATCHUPS,
  TeachyTv.SCRIPT.CATCHING,
  TeachyTv.SCRIPT.TMS,
  TeachyTv.SCRIPT.REGISTER,
}

-- pokefirered/src/teachy_tv.c:201 sListMenuItems_NoTMCase
TeachyTv.ORDER_NO_TM_CASE = {
  TeachyTv.SCRIPT.BATTLE,
  TeachyTv.SCRIPT.STATUS,
  TeachyTv.SCRIPT.MATCHUPS,
  TeachyTv.SCRIPT.CATCHING,
}

-- pokefirered/src/data/text/teachy_tv.h:8 gTeachyTvText_PokedudeSaysHello
TeachyTv.HELLO = Strings(
  "Hey, all you TRAINERS out there!\\n" ..
  "HELLO, TRAINERS!\\p" ..
  "……… ……… ………\\p" ..
  "Come on, let me hear you!\\n" ..
  "HELLO, TRAINERS!\\l" ..
  "It's me, the POKé DUDE!\\p")

-- pokefirered/src/data/text/teachy_tv.h:142 gPokedudeText_TMTypes
TeachyTv.TM_TYPES = Strings(
  "POKé DUDE: NORMAL, WATER, GRASS…\\n" ..
  "TMs also come in types.\\p" ..
  "Check the type and teach it to\\n" ..
  "a POKéMON that matches up well.\\p" ..
  "For example, WATER PULSE is\\n" ..
  "suitable for WATER-type POKéMON.\\p" ..
  "BULLET SEED is a move that most\\n" ..
  "GRASS-type POKéMON can learn.\\p" ..
  "There's one other thing!")

-- pokefirered/src/data/text/teachy_tv.h:152 gPokedudeText_ReadTMDescription
TeachyTv.TM_DESCRIPTION = Strings(
  "Don't just look at the type, read\\n" ..
  "the description, too.\\p" ..
  "It will contain hints about what\\n" ..
  "POKéMON might learn the move.\\p" ..
  "For example, take a move like\\n" ..
  "FOCUS PUNCH.\\p" ..
  "It doesn't sound like anything a\\n" ..
  "bird or fish POKéMON can learn.\\p" ..
  "So, try using it on POKéMON with\\n" ..
  "arms that can throw punches!")

-- pokefirered/src/teachy_tv.c:272 sBattleScript
local GRASS_SCRIPT = {
  "transition_render_bg2",
  "clear_bg2",
  "npc_move_and_setup_text_printer",
  "idle_if_text_printer_active",
  "idle_if_text_printer_active2",
  "text_printer_intro",
  "idle_if_text_printer_active2",
  "erase_text_window_if_key_pressed",
  "start_anim_npc_walk_into_grass",
  "dude_move_up",
  "dude_move_right",
  "battle_or_fade",
  "text_printer_outro",
  "idle_if_text_printer_active2",
  "erase_text_window_if_key_pressed",
  "dude_turn_left",
  "dude_move_left",
  "render_and_remove_bg1_end_graphic",
  "end",
}

-- pokefirered/src/teachy_tv.c:364 sTMsScript
local BAG_SCRIPT = {
  "transition_render_bg2",
  "clear_bg2",
  "npc_move_and_setup_text_printer",
  "idle_if_text_printer_active",
  "idle_if_text_printer_active2",
  "text_printer_intro",
  "idle_if_text_printer_active2",
  "erase_text_window_if_key_pressed",
  "battle_or_fade",
  "text_printer_outro",
  "idle_if_text_printer_active2",
  "erase_text_window_if_key_pressed",
  "dude_turn_left",
  "dude_move_left",
  "render_and_remove_bg1_end_graphic",
  "end",
}

TeachyTv.STEPS = {
  [TeachyTv.SCRIPT.BATTLE] = GRASS_SCRIPT,
  [TeachyTv.SCRIPT.STATUS] = GRASS_SCRIPT,
  [TeachyTv.SCRIPT.MATCHUPS] = GRASS_SCRIPT,
  [TeachyTv.SCRIPT.CATCHING] = GRASS_SCRIPT,
  [TeachyTv.SCRIPT.TMS] = BAG_SCRIPT,
  [TeachyTv.SCRIPT.REGISTER] = BAG_SCRIPT,
}

-- pokefirered/src/teachy_tv.c:262 sWhereToReturnToFromBattle
TeachyTv.RESUME_STEP = {
  [TeachyTv.SCRIPT.BATTLE] = 12,
  [TeachyTv.SCRIPT.STATUS] = 12,
  [TeachyTv.SCRIPT.MATCHUPS] = 12,
  [TeachyTv.SCRIPT.CATCHING] = 12,
  [TeachyTv.SCRIPT.TMS] = 9,
  [TeachyTv.SCRIPT.REGISTER] = 9,
}

-- pokefirered/include/battle_transition.h:25
TeachyTv.TRANSITION = { SLICE = 8, WHITE_BARS_FADE = 9 }

-- pokefirered/include/constants/item_menu.h:18
TeachyTv.BAG_LOCATION = { REGISTER = 9, TMS = 10 }

function TeachyTv.lesson(scriptId)
  return TeachyTv.LESSONS[tonumber(scriptId) or -1]
end

-- pokefirered/src/teachy_tv.c:549 TeachyTvSetupWindow
function TeachyTv.hasTmCase(session, bag)
  local Bag = require("src.core.game3.bag")
  bag = bag or (type(session) == "table" and session.bag) or nil
  if type(bag) ~= "table" then return false end
  return Bag.has(bag, TeachyTv.ITEM_TM_CASE, 1) and true or false
end

-- pokefirered/src/teachy_tv.c:168 sListMenuItems
function TeachyTv.menuItems(session, bag)
  local order = TeachyTv.hasTmCase(session, bag) and TeachyTv.ORDER or TeachyTv.ORDER_NO_TM_CASE
  local rows = {}
  for i = 1, #order do
    local lesson = TeachyTv.LESSONS[order[i]]
    rows[i] = { index = lesson.index, label = lesson.label, key = lesson.key }
  end
  -- pokefirered/src/teachy_tv.c:196
  rows[#rows + 1] = { index = TeachyTv.CANCEL, label = Strings("CANCEL"), key = "CANCEL" }
  return rows
end

-- pokefirered/src/teachy_tv.c:557 gMultiuseListMenuTemplate
function TeachyTv.maxShowed(session, bag)
  return TeachyTv.hasTmCase(session, bag) and 6 or 5
end

local function pages_of(raw)
  local box = TextIR.toTextBox(TextIR.fromAscii(raw or ""), { maxWidth = PAGE_WIDTH })
  local out = {}
  for page in (box .. "\f"):gmatch("(.-)\f") do
    if page ~= "" then out[#out + 1] = page end
  end
  if #out == 0 then out[1] = "" end
  return out
end

-- pokefirered/src/teachy_tv.c:838 TTVcmd_TextPrinterSwitchStringByOptionChosen
function TeachyTv.introPages(scriptId)
  local lesson = TeachyTv.lesson(scriptId)
  if not lesson then return {} end
  lesson._introPages = lesson._introPages or pages_of(lesson.intro)
  return lesson._introPages
end

-- pokefirered/src/teachy_tv.c:853 TTVcmd_TextPrinterSwitchStringByOptionChosen2
function TeachyTv.outroPages(scriptId)
  local lesson = TeachyTv.lesson(scriptId)
  if not lesson then return {} end
  lesson._outroPages = lesson._outroPages or pages_of(lesson.outro)
  return lesson._outroPages
end

TeachyTv.pagesOf = pages_of

-- pokefirered/src/teachy_tv.c:1069 TTVcmd_TaskBattleOrFadeByOptionChosen
function TeachyTv.endsInBattle(scriptId)
  local id = tonumber(scriptId)
  return id == TeachyTv.SCRIPT.BATTLE or id == TeachyTv.SCRIPT.STATUS
    or id == TeachyTv.SCRIPT.MATCHUPS or id == TeachyTv.SCRIPT.CATCHING
end

-- pokefirered/src/teachy_tv.c:1087 TeachyTvSetupBagItemsByOptionChosen
function TeachyTv.bagLocation(scriptId)
  local id = tonumber(scriptId)
  if id == TeachyTv.SCRIPT.TMS then return TeachyTv.BAG_LOCATION.TMS end
  if id == TeachyTv.SCRIPT.REGISTER then return TeachyTv.BAG_LOCATION.REGISTER end
  return nil
end

-- pokefirered/src/teachy_tv.c:1172 TeachyTvPrepBattle
function TeachyTv.battleTransition(scriptId)
  if tonumber(scriptId) == TeachyTv.SCRIPT.BATTLE then
    return TeachyTv.TRANSITION.WHITE_BARS_FADE
  end
  return TeachyTv.TRANSITION.SLICE
end

-- pokefirered/src/teachy_tv.c:1208 TeachyTvRestorePlayerPartyCallback
function TeachyTv.modeAfterBattle(outcome)
  if tonumber(outcome) == B_OUTCOME_DREW then return TeachyTv.MODE.RESUME_LIST end
  return TeachyTv.MODE.RESUME_SCRIPT
end
TeachyTv.B_OUTCOME_DREW = B_OUTCOME_DREW

local function sessionOf(session)
  if type(session) == "table" then return session end
  local rt = package.loaded["src.core.game3.runtime"]
  local got = rt and rt.getSession and rt.getSession()
  if type(got) == "table" then return got end
  return nil
end

-- pokefirered/src/teachy_tv.c:31 struct TeachyTvCtrlBlk
function TeachyTv.resources(session)
  session = sessionOf(session)
  if type(session) ~= "table" then return nil end
  local md = session.modData
  if type(md) ~= "table" then
    md = {}
    session.modData = md
  end
  local res = session.teachyTv
  if type(res) ~= "table" then res = md.teachyTv end
  if type(res) ~= "table" then res = {} end
  res.mode = tonumber(res.mode) or TeachyTv.MODE.FRESH
  res.whichScript = tonumber(res.whichScript) or TeachyTv.SCRIPT.BATTLE
  res.scrollOffset = tonumber(res.scrollOffset) or 0
  res.selectedRow = tonumber(res.selectedRow) or 0
  if type(res.watched) ~= "table" then res.watched = {} end
  session.teachyTv = res
  md.teachyTv = res
  return res
end

-- pokefirered/src/teachy_tv.c:420 InitTeachyTvController
function TeachyTv.initController(session, mode)
  local res = TeachyTv.resources(session)
  if not res then return nil end
  local m = tonumber(mode) or TeachyTv.MODE.FRESH
  res.mode = m
  if m == TeachyTv.MODE.FRESH then
    res.scrollOffset = 0
    res.selectedRow = 0
    res.whichScript = TeachyTv.SCRIPT.BATTLE
  end
  if m == TeachyTv.MODE.RESUME_LIST then
    res.mode = TeachyTv.MODE.FRESH
  end
  return res
end

-- pokefirered/src/teachy_tv.c:445 SetTeachyTvControllerModeToResume
function TeachyTv.setModeToResume(session)
  local res = TeachyTv.resources(session)
  if not res then return nil end
  res.mode = TeachyTv.MODE.RESUME_LIST
  return res
end

-- pokefirered/src/teachy_tv.c:437 CB2_ReturnToTeachyTV
function TeachyTv.returnToTv(session)
  local res = TeachyTv.resources(session)
  if not res then return nil end
  if res.mode == TeachyTv.MODE.RESUME_LIST then
    return TeachyTv.initController(session, TeachyTv.MODE.RESUME_LIST)
  end
  return TeachyTv.initController(session, TeachyTv.MODE.RESUME_SCRIPT)
end

function TeachyTv.selectLesson(session, scriptId)
  local res = TeachyTv.resources(session)
  if not res then return nil end
  local id = tonumber(scriptId)
  if not TeachyTv.LESSONS[id or -1] then return nil end
  res.whichScript = id
  return id
end

function TeachyTv.whichScript(session)
  local res = TeachyTv.resources(session)
  return res and res.whichScript or TeachyTv.SCRIPT.BATTLE
end

function TeachyTv.markWatched(session, scriptId)
  local res = TeachyTv.resources(session)
  local lesson = TeachyTv.lesson(scriptId)
  if not (res and lesson) then return false end
  res.watched[lesson.key] = true
  return true
end

function TeachyTv.hasWatched(session, scriptId)
  local res = TeachyTv.resources(session)
  local lesson = TeachyTv.lesson(scriptId)
  if not (res and lesson) then return false end
  return res.watched[lesson.key] == true
end

function TeachyTv.watchedCount(session)
  local res = TeachyTv.resources(session)
  if not res then return 0 end
  local n = 0
  for _, id in ipairs(TeachyTv.ORDER) do
    if res.watched[TeachyTv.LESSONS[id].key] then n = n + 1 end
  end
  return n
end

-- pokefirered/src/teachy_tv.c:755 TTVcmd_TransitionRenderBg2TeachyTvGraphicInitNpcPos
TeachyTv.TIMING = {
  TITLE = 64,
  CLEAR = 134,
  NPC_WAIT = 35,
  DUDE_X_START = 8,
  DUDE_X_END = 0x78,
  DUDE_Y = 0x38,
  MOVE_UP = 48,
  MOVE_RIGHT = 0x30,
  END_GRAPHIC = 127,
  END = 64,
}

-- pokefirered/include/constants/event_objects.h:96 OBJ_EVENT_GFX_TEACHY_TV_HOST
TeachyTv.HOST_GFX = 90

-- pokefirered/include/constants/items.h:7
local ITEM_GREAT_BALL = 3
local ITEM_POKE_BALL = 4
local ITEM_NEST_BALL = 8
local ITEM_POTION = 13
local ITEM_ANTIDOTE = 14

-- pokefirered/src/item_menu.c:2167 AddBagItem
TeachyTv.POKEDUDE_BAG = {
  { id = ITEM_POTION, qty = 1 },
  { id = ITEM_ANTIDOTE, qty = 1 },
  { id = TeachyTv.ITEM_TEACHY_TV, qty = 1 },
  { id = TeachyTv.ITEM_TM_CASE, qty = 1 },
  { id = ITEM_POKE_BALL, qty = 5 },
  { id = ITEM_GREAT_BALL, qty = 1 },
  { id = ITEM_NEST_BALL, qty = 1 },
}

-- pokefirered/src/item_menu.c:2061 BackUpPlayerBag
local BACKUP_POCKETS = { "ITEMS", "KEY_ITEMS", "POKE_BALLS", "BERRY_POUCH" }

-- pokefirered/include/constants/items.h:300 ITEM_TM01
TeachyTv.POKEDUDE_TMS = { 289, 291, 297, 323 }

-- pokefirered/src/tm_case.c:1322 Pokedude_InitTMCase
local TM_CASE_POCKETS = { "TM_CASE", "KEY_ITEMS" }

-- pokefirered/src/tm_case.c:1351 POKEDUDE_INPUT_DELAY
TeachyTv.POKEDUDE_INPUT_DELAY = 102

-- pokefirered/src/tm_case.c:1353 Task_Pokedude_Run
TeachyTv.TM_CASE_DEMO = {
  { wait = true },
  { key = "down" }, { key = "down" }, { key = "down" },
  { key = "up" }, { key = "up" }, { key = "up" },
  { text = "TM_TYPES" },
  { wait = true },
  { key = "down" }, { key = "down" }, { key = "down" },
  { key = "up" }, { key = "up" }, { key = "up" },
  { text = "TM_DESCRIPTION" },
  { exit = true },
}

-- pokefirered/src/item_menu.c:2208 Task_Bag_TeachyTvRegister
local REGISTER_DEMO = {
  { at = 102, key = "right" },
  { at = 204, key = "a", item = TeachyTv.ITEM_TEACHY_TV },
  { at = 306, key = "down" },
  { at = 408, key = "a" },
  { at = 510, key = "down" },
  { at = 612, key = "down" },
  { at = 714, exit = true },
}

-- pokefirered/src/item_menu.c:2359 Task_Bag_TeachyTvTMs
local TMS_DEMO = {
  { at = 102, key = "right" },
  { at = 204, key = "down" },
  { at = 306, key = "a", item = TeachyTv.ITEM_TM_CASE },
  -- pokefirered/src/item_menu.c:2385 exitCB = Pokedude_InitTMCase
  { at = 408, exit = true, tmCase = true },
}

function TeachyTv.bagDemoPlan(scriptId)
  local id = tonumber(scriptId)
  if id == TeachyTv.SCRIPT.REGISTER then return REGISTER_DEMO end
  if id == TeachyTv.SCRIPT.TMS then return TMS_DEMO end
  return nil
end

local function pocket_slots(bag, key)
  local slots = (type(bag) == "table" and type(bag.pockets) == "table" and bag.pockets[key]) or {}
  local out = {}
  for i, slot in ipairs(slots) do
    out[i] = { id = slot.id, qty = tonumber(slot.qty) or 0 }
  end
  return out
end

-- pokefirered/src/item_menu.c:2065 memcpy(sBackupPlayerBag->bagPocket_Items, ...)
local function set_pocket(bag, key, slots)
  local out = {}
  for i, slot in ipairs(slots or {}) do
    out[i] = { id = slot.id, qty = tonumber(slot.qty) or 0 }
  end
  bag.pockets[key] = out
end

local function swap_pockets(bag, keys, into)
  local Bag = require("src.core.game3.bag")
  Bag.migrate(bag)
  local taken = {}
  for _, key in ipairs(keys) do
    taken[key] = pocket_slots(bag, key)
    set_pocket(bag, key, into and into[key] or nil)
  end
  Bag.migrate(bag)
  return taken
end

local function by_pocket(entries)
  local ItemsData = require("src.core.game3.items_data")
  local out = {}
  for _, entry in ipairs(entries) do
    local pocket = ItemsData.pocketOf(entry.id) or "ITEMS"
    out[pocket] = out[pocket] or {}
    out[pocket][#out[pocket] + 1] = { id = entry.id, qty = entry.qty }
  end
  return out
end

-- pokefirered/src/item_menu.c:2061 BackUpPlayerBag
function TeachyTv.backUpPlayerBag(session, pokedude)
  session = sessionOf(session)
  local bag = session and session.bag
  if type(bag) ~= "table" then return nil end
  local backup = {
    pockets = swap_pockets(bag, BACKUP_POCKETS, pokedude),
    registeredItem = session.registeredItem,
  }
  session.registeredItem = nil
  session.teachyBagBackup = backup
  return backup
end

-- pokefirered/src/item_menu.c:2082 RestorePlayerBag
function TeachyTv.restorePlayerBag(session)
  session = sessionOf(session)
  local backup = session and session.teachyBagBackup
  local bag = session and session.bag
  if not (backup and type(bag) == "table") then return false end
  swap_pockets(bag, BACKUP_POCKETS, backup.pockets)
  session.registeredItem = backup.registeredItem
  session.teachyBagBackup = nil
  return true
end

-- pokefirered/src/item_menu.c:2162 InitPokedudeBag
function TeachyTv.initPokedudeBag(session, scriptId)
  session = sessionOf(session)
  TeachyTv.backUpPlayerBag(session, by_pocket(TeachyTv.POKEDUDE_BAG))
  return TeachyTv.bagLocation(scriptId)
end

-- pokefirered/src/tm_case.c:1322 Pokedude_InitTMCase
function TeachyTv.initPokedudeTmCase(session)
  session = sessionOf(session)
  local bag = session and session.bag
  if type(bag) ~= "table" then return nil end
  local tms = {}
  for i, id in ipairs(TeachyTv.POKEDUDE_TMS) do tms[i] = { id = id, qty = 1 } end
  local backup = { pockets = swap_pockets(bag, TM_CASE_POCKETS, by_pocket(tms)) }
  session.teachyTmCaseBackup = backup
  return backup
end

-- pokefirered/src/tm_case.c:1450 memcpy(gSaveBlock1Ptr->bagPocket_TMHM, ...)
function TeachyTv.restorePokedudeTmCase(session)
  session = sessionOf(session)
  local backup = session and session.teachyTmCaseBackup
  local bag = session and session.bag
  if not (backup and type(bag) == "table") then return false end
  swap_pockets(bag, TM_CASE_POCKETS, backup.pockets)
  session.teachyTmCaseBackup = nil
  return true
end

-- pokefirered/src/teachy_tv.c:1172 TeachyTvPrepBattle
function TeachyTv.startDemonstration(session, scriptId, opts)
  local hook = TeachyTv.onDemonstration
  if type(hook) == "function" then
    local ok, started = pcall(hook, session, scriptId, opts)
    if ok and started ~= false then return true end
  end
  local okP, Pokedude = pcall(require, "src.core.game3.battle.pokedude")
  if okP and type(Pokedude) == "table" and type(Pokedude.startTeachyTvBattle) == "function" then
    local ok, started = pcall(Pokedude.startTeachyTvBattle, session, scriptId, opts)
    if ok and started ~= false then return true end
  end
  return false
end

-- pokefirered/src/item_use.c:534 InitTeachyTvFromBag
function TeachyTv.show(session, bag, opts)
  session = sessionOf(session)
  TeachyTv.initController(session, TeachyTv.MODE.FRESH)
  local okUi, Ui = pcall(require, "src.ui.game3.teachy_tv")
  if okUi and type(Ui) == "table" and Ui.show then
    Ui.show(session, bag, opts)
    return true
  end
  return false
end

return TeachyTv
