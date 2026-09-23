#!/usr/bin/env luajit
-- pokefirered/src/teachy_tv.c:420 InitTeachyTvController

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_teachy_model_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local okReq, TeachyTv = pcall(require, "src.core.game3.teachy_tv")
if not okReq then
  print("[FAIL] src/core/game3/teachy_tv.lua does not load: " .. tostring(TeachyTv))
  os.exit(1)
end

local Bag = require("src.core.game3.bag")
local Schema = require("src.core.game3.save_schema_firered")
local ItemUse = require("src.core.game3.item_use")
local ItemsData = require("src.core.game3.items_data")

local RomText = require("src.core.game3.rom_text")

local S = TeachyTv.SCRIPT

local function newSession()
  return { modData = {}, bag = Bag.new(), party = {} }
end

print("[test] 1. pokefirered/include/teachy_tv.h:4 enum TeachyTvScript")
eq(S.BATTLE, 0, "TTVSCR_BATTLE")
eq(S.STATUS, 1, "TTVSCR_STATUS")
eq(S.MATCHUPS, 2, "TTVSCR_MATCHUPS")
eq(S.CATCHING, 3, "TTVSCR_CATCHING")
eq(S.TMS, 4, "TTVSCR_TMS")
eq(S.REGISTER, 5, "TTVSCR_REGISTER")
eq(#TeachyTv.ORDER, 6, "six lessons")
do
  local want = { S.BATTLE, S.STATUS, S.MATCHUPS, S.CATCHING, S.TMS, S.REGISTER }
  local same = true
  for i = 1, #want do
    if TeachyTv.ORDER[i] ~= want[i] then same = false end
  end
  check(same, "sListMenuItems order is battle, status, matchups, catching, TMs, register")
end

print("[test] 2. pokefirered/src/data/text/teachy_tv.h:1 every lesson has both halves")
do
  local labels = {
    [S.BATTLE] = "Teach me how to battle.",
    [S.STATUS] = "What are status problems?",
    [S.MATCHUPS] = "What are type matchups?",
    [S.CATCHING] = "I want to catch POKéMON.",
    [S.TMS] = "Teach me about TMs.",
    [S.REGISTER] = "How do I register an item?",
  }
  for _, id in ipairs(TeachyTv.ORDER) do
    local lesson = TeachyTv.lesson(id)
    check(lesson ~= nil, "lesson " .. id .. " exists")
    eq(RomText.plain(lesson.labelKey), labels[id], "row label for lesson " .. id)
    check(RomText.has(lesson.introKey), lesson.key .. " has a Script1 string")
    check(RomText.has(lesson.outroKey), lesson.key .. " has a Script2 string")
  end
end

print("[test] 3. page sequences")
do
  for _, id in ipairs(TeachyTv.ORDER) do
    local intro = TeachyTv.introPages(id)
    local outro = TeachyTv.outroPages(id)
    check(#intro >= 2, TeachyTv.lesson(id).key .. " intro pages=" .. #intro)
    check(#outro >= 2, TeachyTv.lesson(id).key .. " outro pages=" .. #outro)
    local blank = 0
    for _, page in ipairs(intro) do
      if page == "" then blank = blank + 1 end
      if select(2, page:gsub("\n", "")) > 1 then blank = blank + 1 end
    end
    eq(blank, 0, TeachyTv.lesson(id).key .. " intro pages are non-empty and at most two lines")
  end
  local battle = TeachyTv.introPages(S.BATTLE)
  eq(battle[1], "Today, the POKé DUDE's here to\ntell you about how you can battle",
    "gTeachyTvText_BattleScript1 page 1")
  eq(battle[2], "POKéMON!", "the \\l line becomes page 2")
  local last = TeachyTv.outroPages(S.BATTLE)
  eq(last[#last], "Remember, TRAINERS, a good deed\na day brings happiness to stay!",
    "BattleScript2 ends on the sign-off")
  local tms = TeachyTv.outroPages(S.TMS)
  eq(tms[1], "Wow, I talked a lot today!\nAll righty, be seeing you!",
    "gTeachyTvText_TMsScript2 page 1")
end

print("[test] 4. pokefirered/src/data/text/teachy_tv.h:8 the Pokedude intros")
do
  local hello = TeachyTv.pagesOf(TeachyTv.HELLO)
  check(#hello >= 4, "PokedudeSaysHello pages=" .. #hello)
  eq(hello[1], "Hey, all you TRAINERS out there!\nHELLO, TRAINERS!", "hello page 1")
  local tmTypes = TeachyTv.pagesOf(TeachyTv.TM_TYPES)
  eq(tmTypes[#tmTypes], "There's one other thing!", "gPokedudeText_TMTypes last page")
  local tmDesc = TeachyTv.pagesOf(TeachyTv.TM_DESCRIPTION)
  check(#tmDesc >= 5, "gPokedudeText_ReadTMDescription pages=" .. #tmDesc)
end

print("[test] 5. pokefirered/src/teachy_tv.c:554 the TM CASE gate")
do
  local s = newSession()
  check(not TeachyTv.hasTmCase(s), "no TM CASE on a fresh bag")
  local rows = TeachyTv.menuItems(s)
  eq(#rows, 5, "sListMenuItems_NoTMCase is four lessons plus CANCEL")
  eq(rows[5].index, TeachyTv.CANCEL, "CANCEL is the last row")
  eq(rows[4].index, S.CATCHING, "the last lesson without a TM CASE is catching")
  eq(TeachyTv.maxShowed(s), 5, "maxShowed 5 without a TM CASE")

  Bag.add(s.bag, TeachyTv.ITEM_TM_CASE, 1)
  check(TeachyTv.hasTmCase(s), "CheckBagHasItem(ITEM_TM_CASE, 1)")
  rows = TeachyTv.menuItems(s)
  eq(#rows, 7, "sListMenuItems is six lessons plus CANCEL")
  eq(rows[5].index, S.TMS, "the TM lesson appears with a TM CASE")
  eq(rows[6].index, S.REGISTER, "the register lesson appears with a TM CASE")
  eq(rows[7].index, TeachyTv.CANCEL, "CANCEL stays last")
  eq(TeachyTv.maxShowed(s), 6, "maxShowed 6 with a TM CASE")
end

print("[test] 6. pokefirered/src/teachy_tv.c:272 the per-lesson step clusters")
do
  for _, id in ipairs({ S.BATTLE, S.STATUS, S.MATCHUPS, S.CATCHING }) do
    eq(#TeachyTv.STEPS[id], 19, TeachyTv.lesson(id).key .. " runs the 19-step grass cluster")
    eq(TeachyTv.STEPS[id][9], "start_anim_npc_walk_into_grass",
      TeachyTv.lesson(id).key .. " walks the dude into the grass")
    eq(TeachyTv.RESUME_STEP[id], 12, TeachyTv.lesson(id).key .. " resumes at step 12")
    check(TeachyTv.endsInBattle(id), TeachyTv.lesson(id).key .. " hands off to a battle")
    eq(TeachyTv.bagLocation(id), nil, TeachyTv.lesson(id).key .. " opens no bag")
  end
  for _, id in ipairs({ S.TMS, S.REGISTER }) do
    eq(#TeachyTv.STEPS[id], 16, TeachyTv.lesson(id).key .. " runs the 16-step bag cluster")
    eq(TeachyTv.STEPS[id][9], "battle_or_fade",
      TeachyTv.lesson(id).key .. " skips the grass walk")
    eq(TeachyTv.RESUME_STEP[id], 9, TeachyTv.lesson(id).key .. " resumes at step 9")
    check(not TeachyTv.endsInBattle(id), TeachyTv.lesson(id).key .. " runs no battle")
  end
  -- pokefirered/include/constants/item_menu.h:18
  eq(TeachyTv.bagLocation(S.TMS), 10, "ITEMMENULOCATION_TTVSCR_TMS")
  eq(TeachyTv.bagLocation(S.REGISTER), 9, "ITEMMENULOCATION_TTVSCR_REGISTER")
  -- pokefirered/src/teachy_tv.c:1181
  eq(TeachyTv.battleTransition(S.BATTLE), TeachyTv.TRANSITION.WHITE_BARS_FADE,
    "the battle lesson uses B_TRANSITION_WHITE_BARS_FADE")
  eq(TeachyTv.battleTransition(S.CATCHING), TeachyTv.TRANSITION.SLICE,
    "every other lesson uses B_TRANSITION_SLICE")
end

print("[test] 7. pokefirered/src/teachy_tv.c:420 the controller modes")
do
  local s = newSession()
  local res = TeachyTv.resources(s)
  eq(res.mode, TeachyTv.MODE.FRESH, "a fresh block is mode 0")
  eq(res.whichScript, S.BATTLE, "whichScript starts at TTVSCR_BATTLE")
  eq(res.scrollOffset, 0, "scrollOffset starts at 0")
  eq(res.selectedRow, 0, "selectedRow starts at 0")

  TeachyTv.selectLesson(s, S.REGISTER)
  res.scrollOffset, res.selectedRow = 1, 3
  TeachyTv.initController(s, TeachyTv.MODE.FRESH)
  eq(res.whichScript, S.BATTLE, "mode 0 resets whichScript")
  eq(res.scrollOffset, 0, "mode 0 resets scrollOffset")
  eq(res.selectedRow, 0, "mode 0 resets selectedRow")

  TeachyTv.selectLesson(s, S.MATCHUPS)
  res.selectedRow = 2
  -- pokefirered/src/teachy_tv.c:445
  TeachyTv.setModeToResume(s)
  eq(res.mode, TeachyTv.MODE.RESUME_LIST, "SetTeachyTvControllerModeToResume sets mode 1")
  -- pokefirered/src/teachy_tv.c:437
  TeachyTv.returnToTv(s)
  eq(res.mode, TeachyTv.MODE.FRESH, "mode 1 collapses to mode 0 in InitTeachyTvController")
  eq(res.whichScript, S.MATCHUPS, "but mode 1 does not run the mode 0 reset")

  TeachyTv.selectLesson(s, S.CATCHING)
  res.selectedRow = 3
  TeachyTv.returnToTv(s)
  eq(res.mode, TeachyTv.MODE.RESUME_SCRIPT, "a non-resume return comes back as mode 2")
  eq(res.whichScript, S.CATCHING, "mode 2 keeps the lesson that ran")
  eq(res.selectedRow, 3, "mode 2 keeps the list row")

  -- pokefirered/src/teachy_tv.c:1208
  eq(TeachyTv.modeAfterBattle(TeachyTv.B_OUTCOME_DREW), TeachyTv.MODE.RESUME_LIST,
    "B_OUTCOME_DREW drops back to the lesson list")
  eq(TeachyTv.modeAfterBattle(1), TeachyTv.MODE.RESUME_SCRIPT,
    "any other outcome resumes the lesson script")
end

print("[test] 8. watched state survives a save round trip")
do
  local s = newSession()
  eq(TeachyTv.watchedCount(s), 0, "nothing watched on a new game")
  check(TeachyTv.markWatched(s, S.CATCHING), "markWatched(CATCHING)")
  check(TeachyTv.markWatched(s, S.TMS), "markWatched(TMS)")
  TeachyTv.selectLesson(s, S.TMS)
  eq(TeachyTv.watchedCount(s), 2, "two lessons watched")

  local save = Schema.toSaveTable(s)
  local back = Schema.fromSaveTable(save)
  check(TeachyTv.hasWatched(back, S.CATCHING), "CATCHING survived the save")
  check(TeachyTv.hasWatched(back, S.TMS), "TMS survived the save")
  check(not TeachyTv.hasWatched(back, S.BATTLE), "BATTLE was never watched")
  eq(TeachyTv.watchedCount(back), 2, "the count survived the save")

  local res = TeachyTv.resources(back)
  eq(res.whichScript, S.TMS, "whichScript survived the save")
end

print("[test] 9. pokefirered/src/item_use.c:518 FieldUseFunc_TeachyTv")
do
  eq(TeachyTv.ITEM_TEACHY_TV, 366, "ITEM_TEACHY_TV")
  local info = ItemsData.info(TeachyTv.ITEM_TEACHY_TV)
  if not info then
    print("[skip] no cache for the item pack, bag entry point not exercised")
  else
    eq(info.pocket, "KEY_ITEMS", "TEACHY TV is a key item")
    local s = newSession()
    Bag.add(s.bag, TeachyTv.ITEM_TEACHY_TV, 1)
    local ok, kind, text = ItemUse.useField(s, s.bag, TeachyTv.ITEM_TEACHY_TV)
    check(ok, "USE on the TEACHY TV succeeds")
    eq(kind, "teachy_tv", "the key-item reject arm no longer swallows it")
    eq(text, nil, "no OAK refusal message")
    local res = TeachyTv.resources(s)
    eq(res.mode, TeachyTv.MODE.FRESH, "the bag opens the TV with InitTeachyTvController(0)")
    eq(res.whichScript, S.BATTLE, "and on the first lesson row")
    eq(Bag.get(s.bag, TeachyTv.ITEM_TEACHY_TV), 1, "a key item is not consumed")

    -- pokefirered/src/item_use.c:534 InitTeachyTvFromBag
    local Stack = require("src.ui.game3.stack")
    local Ui = require("src.ui.game3.teachy_tv")
    check(Ui.isOpen(), "USE put the TV screen on the stack")
    eq(Stack.top() and Stack.top().id, "teachy_tv", "the TV is the top layer")
    eq(Ui.state, "list", "and it is showing the lesson list")
    eq(#Ui.rows(), 5, "four lessons plus CANCEL in the screen's own rows")
    Ui.close()
    Stack.clear()
  end
end

print("[test] 9b. pokefirered/src/item_menu.c:2022 UseRegisteredKeyItemOnField")
do
  local info = ItemsData.info(TeachyTv.ITEM_TEACHY_TV)
  if not info then
    print("[skip] no cache for the item pack, the registered item path not exercised")
  else
    local Stack = require("src.ui.game3.stack")
    local Ui = require("src.ui.game3.teachy_tv")
    local Game3 = require("src.core.Game3")
    local selectInput = {
      wasPressed = function(_, key) return key == "select" end,
      isDown = function() return false end,
    }
    Stack.clear()
    local s = newSession()
    Bag.add(s.bag, TeachyTv.ITEM_TEACHY_TV, 1)
    -- pokefirered/src/data/text/teachy_tv.h:182 gTeachyTvText_RegisterScript2
    s.registeredItem = TeachyTv.ITEM_TEACHY_TV
    Game3._handleRegisteredItem({ input = selectInput, session = s })
    check(Ui.isOpen(), "SELECT on the registered TEACHY TV opened the TV")
    eq(TeachyTv.resources(s).mode, TeachyTv.MODE.FRESH, "through InitTeachyTvController(0)")
    Ui.close()
    Stack.clear()
  end
end

print("[test] 10. pokefirered/data/specials.inc carries no Teachy TV special")
do
  local Natives = require("src.core.game3.scripting.natives")
  local mod = Natives.MODULES and Natives.MODULES["natives_teachy"]
  check(mod == nil, "no natives_teachy module: the TV is reached from item_use.c, not a script")
end

if failed > 0 then
  print(string.format("FAILED %d check(s)", failed))
  os.exit(1)
end
print("All teachy tv model checks passed.")
