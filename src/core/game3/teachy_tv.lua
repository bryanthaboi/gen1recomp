-- pokefirered/src/teachy_tv.c:420 InitTeachyTvController

local RomText = require("src.core.game3.rom_text")

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

TeachyTv.LESSONS = {
  [TeachyTv.SCRIPT.BATTLE] = {
    index = TeachyTv.SCRIPT.BATTLE,
    key = "BATTLE",
    -- pokefirered/src/data/text/teachy_tv.h:1
    labelKey = "gTeachyTvString_TeachBattle",
    -- pokefirered/src/data/text/teachy_tv.h:15
    introKey = "gTeachyTvText_BattleScript1",
    -- pokefirered/src/data/text/teachy_tv.h:30
    outroKey = "gTeachyTvText_BattleScript2",
  },
  [TeachyTv.SCRIPT.STATUS] = {
    index = TeachyTv.SCRIPT.STATUS,
    key = "STATUS",
    -- pokefirered/src/data/text/teachy_tv.h:2
    labelKey = "gTeachyTvString_StatusProblems",
    -- pokefirered/src/data/text/teachy_tv.h:40
    introKey = "gTeachyTvText_StatusScript1",
    -- pokefirered/src/data/text/teachy_tv.h:57
    outroKey = "gTeachyTvText_StatusScript2",
  },
  [TeachyTv.SCRIPT.MATCHUPS] = {
    index = TeachyTv.SCRIPT.MATCHUPS,
    key = "MATCHUPS",
    -- pokefirered/src/data/text/teachy_tv.h:3
    labelKey = "gTeachyTvString_TypeMatchups",
    -- pokefirered/src/data/text/teachy_tv.h:70
    introKey = "gTeachyTvText_MatchupsScript1",
    -- pokefirered/src/data/text/teachy_tv.h:92
    outroKey = "gTeachyTvText_MatchupsScript2",
  },
  [TeachyTv.SCRIPT.CATCHING] = {
    index = TeachyTv.SCRIPT.CATCHING,
    key = "CATCHING",
    -- pokefirered/src/data/text/teachy_tv.h:4
    labelKey = "gTeachyTvString_CatchPkmn",
    -- pokefirered/src/data/text/teachy_tv.h:107
    introKey = "gTeachyTvText_CatchingScript1",
    -- pokefirered/src/data/text/teachy_tv.h:121
    outroKey = "gTeachyTvText_CatchingScript2",
  },
  [TeachyTv.SCRIPT.TMS] = {
    index = TeachyTv.SCRIPT.TMS,
    key = "TMS",
    -- pokefirered/src/data/text/teachy_tv.h:5
    labelKey = "gTeachyTvString_AboutTMs",
    -- pokefirered/src/data/text/teachy_tv.h:129
    introKey = "gTeachyTvText_TMsScript1",
    -- pokefirered/src/data/text/teachy_tv.h:163
    outroKey = "gTeachyTvText_TMsScript2",
  },
  [TeachyTv.SCRIPT.REGISTER] = {
    index = TeachyTv.SCRIPT.REGISTER,
    key = "REGISTER",
    -- pokefirered/src/data/text/teachy_tv.h:6
    labelKey = "gTeachyTvString_RegisterItem",
    -- pokefirered/src/data/text/teachy_tv.h:168
    introKey = "gTeachyTvText_RegisterScript1",
    -- pokefirered/src/data/text/teachy_tv.h:182
    outroKey = "gTeachyTvText_RegisterScript2",
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

-- pokefirered/src/data/text/teachy_tv.h:8
TeachyTv.HELLO = "gTeachyTvText_PokedudeSaysHello"

-- pokefirered/src/data/text/teachy_tv.h:142
TeachyTv.TM_TYPES = "gPokedudeText_TMTypes"

-- pokefirered/src/data/text/teachy_tv.h:152
TeachyTv.TM_DESCRIPTION = "gPokedudeText_ReadTMDescription"

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
    rows[i] = { index = lesson.index, label = RomText.plain(lesson.labelKey), key = lesson.key }
  end
  -- pokefirered/src/teachy_tv.c:196
  rows[#rows + 1] = { index = TeachyTv.CANCEL, label = RomText.plain("gTeachyTvString_Cancel"), key = "CANCEL" }
  return rows
end

-- pokefirered/src/teachy_tv.c:557 gMultiuseListMenuTemplate
function TeachyTv.maxShowed(session, bag)
  return TeachyTv.hasTmCase(session, bag) and 6 or 5
end

local function pages_of(key)
  local box = RomText.box(key, { maxWidth = PAGE_WIDTH })
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
  return pages_of(lesson.introKey)
end

-- pokefirered/src/teachy_tv.c:853 TTVcmd_TextPrinterSwitchStringByOptionChosen2
function TeachyTv.outroPages(scriptId)
  local lesson = TeachyTv.lesson(scriptId)
  if not lesson then return {} end
  return pages_of(lesson.outroKey)
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
