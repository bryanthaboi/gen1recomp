#!/usr/bin/env luajit
-- pokefirered/src/teachy_tv.c:450 TeachyTvMainCallback

package.path = "./?.lua;./?/init.lua;" .. package.path

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

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("items/pack.lua")
if not cacheRoot then
  print("[skip] game3_teachy_screen: " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local TeachyTv = require("src.core.game3.teachy_tv")
local Ui = require("src.ui.game3.teachy_tv")
local Bag = require("src.core.game3.bag")
local Stack = require("src.ui.game3.stack")
local BagMenu = require("src.ui.game3.bag_menu")

local S = TeachyTv.SCRIPT
local T = TeachyTv.TIMING

local function press(key)
  return {
    wasPressed = function(_, k) return k == key end,
    isDown = function() return false end,
  }
end

local function newSession()
  return { modData = {}, bag = Bag.new(), party = {}, name = "RED" }
end

local Fade = require("src.ui.game3.fade")
local Audio = require("src.core.game3.audio")

local function settleFade()
  for _ = 1, 40 do
    Fade.tick(1 / 60)
    Ui.update(1 / 60)
  end
end

local function openWith(session)
  Stack.clear()
  Ui.show(session, session.bag)
  settleFade()
end

local function ticks(n)
  for _ = 1, n do Ui.update(1 / 60) end
end

local function runUntil(name, budget)
  for _ = 1, budget or 4000 do
    if Ui.stepName() == name then return true end
    Ui.update(1 / 60)
  end
  return Ui.stepName() == name
end

print("[test] 1. pokefirered/src/teachy_tv.c:553 the list rows and the cursor")
do
  local s = newSession()
  openWith(s)
  check(Ui.isOpen(), "the TV screen is open")
  eq(Ui.state, "list", "it opens on the lesson list")
  eq(#Ui.rows(), 5, "five rows without a TM CASE")
  eq(Ui.cursor, 1, "the cursor starts on the battle lesson")

  Ui.handleInput(press("down"))
  Ui.handleInput(press("down"))
  eq(Ui.cursor, 3, "down twice walks to the matchups lesson")
  Ui.handleInput(press("up"))
  eq(Ui.cursor, 2, "up walks back")
  local res = TeachyTv.resources(s)
  -- pokefirered/src/teachy_tv.c:722 ListMenuGetScrollAndRow
  eq(res.selectedRow, 1, "the controller block tracks the row")

  for _ = 1, 10 do Ui.handleInput(press("down")) end
  eq(Ui.cursor, 5, "the cursor stops on CANCEL")
  -- pokefirered/src/teachy_tv.c:734 case -2
  Ui.handleInput(press("a"))
  -- pokefirered/src/teachy_tv.c:689 TeachyTvQuitBeginFade
  check(Ui.isOpen() and Ui.closing, "A on CANCEL starts the quit fade")
  settleFade()
  check(not Ui.isOpen(), "A on CANCEL closes the TV once the fade ends")

  openWith(s)
  Ui.handleInput(press("b"))
  settleFade()
  check(not Ui.isOpen(), "B closes the TV")

  Bag.add(s.bag, TeachyTv.ITEM_TM_CASE, 1)
  openWith(s)
  eq(#Ui.rows(), 7, "six lessons plus CANCEL with a TM CASE")
  Ui.handleInput(press("b"))
end

print("[test] 2. pokefirered/src/teachy_tv.c:272 the cluster runs the lesson")
do
  local s = newSession()
  openWith(s)
  for _ = 1, 3 do Ui.handleInput(press("down")) end
  eq(Ui.cursor, 4, "the cursor is on the catching lesson")
  Ui.handleInput(press("a"))
  eq(Ui.state, "lesson", "A starts the lesson")
  eq(TeachyTv.whichScript(s), S.CATCHING, "whichScript is TTVSCR_CATCHING")
  eq(Ui.stepName(), "transition_render_bg2", "the cluster starts on the transition")
  check(#Ui.pages() == 0, "nothing is printed yet")

  -- pokefirered/src/teachy_tv.c:759 data[2] > 63
  ticks(T.TITLE - 1)
  check(not Ui.title, "the title card is not up on frame 63")
  check(Ui.static ~= nil, "the static runs under the transition")
  ticks(1)
  check(Ui.title, "the title card is up on frame 64")
  -- pokefirered/src/teachy_tv.c:761 CopyToBgTilemapBufferRect_ChangePalette
  check(Ui.static == nil, "the title map replaces the static on BG2")
  eq(Ui.stepName(), "clear_bg2", "the cluster moved to the clear step")
  check(Ui.hostVisible, "the POKé DUDE is on screen")
  eq(Ui.hostX, T.DUDE_X_START, "he starts at x=8")

  -- pokefirered/src/teachy_tv.c:773 data[2] == 134
  ticks(T.CLEAR)
  check(not Ui.title, "the title card is cleared after 134 frames")
  eq(Ui.stepName(), "npc_move_and_setup_text_printer", "then the dude walks in")

  -- pokefirered/src/teachy_tv.c:786 data[2] != 35
  ticks(T.NPC_WAIT)
  eq(Ui.hostX, T.DUDE_X_START, "after 35 ticks he has not moved yet")
  ticks(1)
  eq(Ui.hostX, T.DUDE_X_START + 1, "tick 36 is his first step")

  -- pokefirered/src/teachy_tv.c:789 x2 == 0x78
  ticks(T.DUDE_X_END - T.DUDE_X_START)
  eq(Ui.hostX, T.DUDE_X_END, "he stops at x=0x78")
  eq(Ui.phase, "hello", "and says hello")
  eq(#Ui.pages(), #TeachyTv.pagesOf(TeachyTv.HELLO), "gTeachyTvText_PokedudeSaysHello is printing")
  check(Ui.waitingForKey(), "the prompt is up on a \\p page")

  for _ = 1, #Ui.pages() - 1 do Ui.handleInput(press("a")) end
  check(not Ui.printerActive(), "the hello printer is done")
  ticks(4)
  eq(Ui.phase, "intro", "the intro text printer took over")
  eq(#Ui.pages(), #TeachyTv.introPages(S.CATCHING), "CatchingScript1 is printing")
  eq(Ui.page, 1, "on page 1")

  Ui.handleInput(press("a"))
  eq(Ui.page, 2, "A pages the body")
  for _ = 1, #Ui.pages() - 2 do Ui.handleInput(press("a")) end
  ticks(2)
  -- pokefirered/src/teachy_tv.c:936 TTVcmd_EraseTextWindowIfKeyPressed
  eq(Ui.stepName(), "erase_text_window_if_key_pressed", "the cluster waits for a key press")
  check(Ui.waitingForKey(), "the prompt stays up while it waits")
  check(#Ui.pages() > 0, "the last page is still on screen")
  Ui.handleInput(press("a"))
  eq(#Ui.pages(), 0, "the key press erased the window")
  eq(Ui.stepName(), "start_anim_npc_walk_into_grass", "and the dude walks into the grass")

  ticks(1)
  eq(Ui.hostFacing, "up", "he faces up")
  eq(Ui.stepName(), "dude_move_up", "moving up")
  ticks(T.MOVE_UP)
  eq(Ui.stepName(), "dude_move_right", "then right")
  ticks(T.MOVE_RIGHT)
  -- pokefirered/src/teachy_tv.c:1069 TTVcmd_TaskBattleOrFadeByOptionChosen
  eq(Ui.stepName(), "battle_or_fade", "then the demonstration")
  check(TeachyTv.endsInBattle(S.CATCHING), "the catching lesson ends in a battle")

  local handed
  TeachyTv.onDemonstration = function(_, script, opts)
    handed = { script = script, transition = opts.transition }
    -- pokefirered/include/constants/songs.h:306 MUS_VS_WILD
    Audio.playSong(298)
    opts.onDone(1)
    return true
  end
  ticks(1)
  TeachyTv.onDemonstration = nil
  eq(handed and handed.script, S.CATCHING, "the catching battle was handed off")
  eq(handed and handed.transition, TeachyTv.TRANSITION.SLICE, "behind B_TRANSITION_SLICE")
  -- pokefirered/src/teachy_tv.c:1100 sWhereToReturnToFromBattle
  eq(Ui.stepName(), "text_printer_outro", "the battle resumes the cluster at step 12")
  -- pokefirered/src/teachy_tv.c:1214 PlayNewMapMusic(MUS_FOLLOW_ME)
  eq(Audio.currentSong() and Audio.currentSong().id, 272, "MUS_FOLLOW_ME plays again after the battle")
  -- pokefirered/src/teachy_tv.c:660 ChangeBgX(3, 0x3000, 1)
  eq(Ui.bg3X, 32, "BG3 X is reset then moved 48 px right")
  eq(Ui.bg3Y, -8, "BG3 Y is reset then moved 48 px up")
  eq(Ui.grassLo, 3, "grassAnimCounterLo is 0 + 3")
  eq(Ui.grassHi, 0, "grassAnimCounterHi is 3 - 3")
  ticks(2)
  eq(Ui.phase, "outro", "CatchingScript2 is printing")
  for _ = 1, #Ui.pages() - 1 do Ui.handleInput(press("a")) end
  ticks(2)
  eq(Ui.stepName(), "erase_text_window_if_key_pressed", "the outro waits for a key press too")
  Ui.handleInput(press("a"))
  eq(Ui.stepName(), "dude_turn_left", "then he turns left")
  ticks(1)
  eq(Ui.stepName(), "dude_move_left", "and walks off")
  ticks(T.DUDE_X_END - T.DUDE_X_START + 1)
  eq(Ui.stepName(), "render_and_remove_bg1_end_graphic", "the end graphic comes up")
  ticks(1)
  check(Ui.endCard, "the end card is showing")
  ticks(T.END_GRAPHIC - 1)
  check(not Ui.endCard, "the end card is gone after 127 frames")
  eq(Ui.stepName(), "end", "the cluster is on TTVcmd_End")
  check(Ui.static == nil, "no static while the lesson plays")
  ticks(T.END)
  eq(Ui.state, "list", "the lesson returns to the list")
  -- pokefirered/src/teachy_tv.c:1048 TeachyTvBg2AnimController
  check(Ui.static ~= nil, "TTVcmd_End brings the static back")
  check(Ui.isOpen(), "the TV is still open")
  check(TeachyTv.hasWatched(s, S.CATCHING), "the lesson is marked watched")
  Ui.handleInput(press("b"))
end

print("[test] 3. pokefirered/src/teachy_tv.c:808 B aborts back to the list")
do
  local s = newSession()
  openWith(s)
  Ui.handleInput(press("a"))
  eq(Ui.state, "lesson", "the battle lesson started")
  ticks(T.TITLE + 10)
  Ui.handleInput(press("b"))
  eq(Ui.state, "lesson", "B runs TTVcmd_End rather than snapping back")
  eq(Ui.stepName(), "end", "the cluster jumped to the end command")
  check(not Ui.hostVisible, "the dude is hidden")
  ticks(T.END)
  eq(Ui.state, "list", "and 64 frames later the list is back")
  check(not TeachyTv.hasWatched(s, S.BATTLE), "an aborted lesson is not watched")
  Ui.handleInput(press("b"))
end

print("[test] 4. pokefirered/src/teachy_tv.c:526 the art missing fallback")
do
  Ui.reloadAssets()
  local path = Ui.artPath("screen")
  check(path:match("teachy_tv/screen%.rgba$") ~= nil, "the border art path is " .. path)
  check(Ui.titleArt() == nil, "no title art without the importer key")
  check(Ui.chrome() == nil, "no border art means the plain chrome draws")
  check(Ui.bg3Art() == nil, "no BG3 map art either")
  -- pokefirered/src/teachy_tv.c:122
  check(Ui.chromeCutOut() == false, "an absent border is never treated as a cut out")
  local f = io.open(path, "rb")
  if f then
    local bytes = f:read("*a")
    f:close()
    local at = (80 * 240 + 120) * 4 + 4
    print(string.format("[info] the cache already carries %s, centre alpha %s",
      path, tostring(bytes and #bytes >= at and bytes:byte(at))))
  else
    print("[info] no " .. path .. " in this cache yet, the fallback path is the live one")
  end
end

print("[test] 5. pokefirered/src/item_menu.c:2162 the pokedude bag")
do
  local s = newSession()
  Bag.add(s.bag, TeachyTv.ITEM_TM_CASE, 1)
  Bag.add(s.bag, 13, 3)
  Bag.add(s.bag, 4, 2)
  s.registeredItem = nil
  openWith(s)
  for _ = 1, 5 do Ui.handleInput(press("down")) end
  local row = Ui.rows()[Ui.cursor]
  eq(row and row.index, S.REGISTER, "the cursor is on the register lesson")
  Ui.handleInput(press("a"))

  check(runUntil("idle_if_text_printer_active", 800), "the dude walked in and said hello")
  eq(Ui.phase, "hello", "gTeachyTvText_PokedudeSaysHello is printing")
  for _ = 1, #Ui.pages() - 1 do Ui.handleInput(press("a")) end
  ticks(4)
  eq(Ui.phase, "intro", "RegisterScript1 took over")
  for _ = 1, #Ui.pages() - 1 do Ui.handleInput(press("a")) end
  ticks(2)
  eq(Ui.stepName(), "erase_text_window_if_key_pressed", "the intro waits for a key press")
  Ui.handleInput(press("a"))
  -- pokefirered/src/teachy_tv.c:364 sTMsScript skips the grass walk
  eq(Ui.stepName(), "battle_or_fade", "the bag cluster goes straight to the hand off")
  ticks(1)

  -- pokefirered/src/item_menu.c:2166 AddBagItem
  check(Ui.suspended, "the TV waits while the bag runs")
  check(BagMenu.isOpen(), "the pokedude bag is open")
  eq(Stack.top() and Stack.top().id, "teachy_pokedude_bag", "the demo drives it")
  eq(Bag.get(s.bag, 13), 1, "one POTION, not the player's three")
  eq(Bag.get(s.bag, 14), 1, "one ANTIDOTE")
  eq(Bag.get(s.bag, 4), 5, "five POKé BALLS")
  eq(Bag.get(s.bag, 3), 1, "one GREAT BALL")
  eq(Bag.get(s.bag, 8), 1, "one NEST BALL")
  eq(Bag.get(s.bag, TeachyTv.ITEM_TEACHY_TV), 1, "the TEACHY TV")

  local demo = Ui.bagDemo
  for _ = 1, 500 do demo.update(1 / 60) end
  -- pokefirered/src/item_menu.c:2232 gSaveBlock1Ptr->registeredItem
  eq(s.registeredItem, TeachyTv.ITEM_TEACHY_TV, "the demo registered the TEACHY TV")
  for _ = 1, 400 do demo.update(1 / 60) end

  check(demo.finished, "the demo ran to its exit step")
  check(not BagMenu.isOpen(), "the pokedude bag closed")
  -- pokefirered/src/item_menu.c:2082 RestorePlayerBag
  eq(Bag.get(s.bag, 13), 3, "the player's three POTIONS came back")
  eq(Bag.get(s.bag, 4), 2, "the player's two POKé BALLS came back")
  eq(Bag.get(s.bag, 14), 0, "the fake ANTIDOTE is gone")
  eq(Bag.get(s.bag, 3), 0, "the fake GREAT BALL is gone")
  eq(s.registeredItem, nil, "the registration was a demonstration only")
  eq(Bag.get(s.bag, TeachyTv.ITEM_TM_CASE), 1, "the player's TM CASE is back")

  -- pokefirered/src/teachy_tv.c:1100 sWhereToReturnToFromBattle
  eq(Ui.state, "lesson", "the TV resumed the lesson")
  eq(Ui.stepName(), "text_printer_outro", "at step 9, the outro")
  check(not Ui.suspended, "and it is ticking again")
  ticks(2)
  eq(Ui.phase, "outro", "RegisterScript2 is printing")
  Stack.clear()
  Ui.open = false
end

print("[test] 6. pokefirered/src/item_menu.c:2061 BackUpPlayerBag keeps the bag intact")
do
  local s = newSession()
  Bag.add(s.bag, TeachyTv.ITEM_TEACHY_TV, 1)
  -- pokefirered/include/constants/items.h:300 ITEM_TM01
  Bag.add(s.bag, 289, 1)
  -- pokefirered/include/constants/items.h:143
  Bag.add(s.bag, 139, 2)
  Bag.add(s.bag, 13, 3)
  eq(Bag.get(s.bag, TeachyTv.ITEM_TM_CASE), 1, "the TM CASE rides the TM pocket")
  local pouch = require("src.core.game3.items_data").ITEM_BERRY_POUCH
  eq(Bag.get(s.bag, pouch), 1, "and the BERRY POUCH rides the berry pocket")

  TeachyTv.initPokedudeBag(s, S.REGISTER)
  -- pokefirered/src/item_menu.c:2167 AddBagItem(ITEM_TM_CASE, 1)
  eq(Bag.get(s.bag, TeachyTv.ITEM_TM_CASE), 1, "the pokedude bag holds exactly one TM CASE")
  eq(Bag.get(s.bag, pouch), 0, "and no BERRY POUCH")
  eq(Bag.get(s.bag, 13), 1, "one POTION, not the player's three")
  eq(Bag.get(s.bag, 289), 1, "the player's TM stays in the TM pocket")

  -- pokefirered/src/item_menu.c:2082 RestorePlayerBag
  TeachyTv.restorePlayerBag(s)
  eq(Bag.get(s.bag, TeachyTv.ITEM_TM_CASE), 1, "one TM CASE after the restore")
  eq(Bag.get(s.bag, pouch), 1, "one BERRY POUCH after the restore")
  eq(Bag.get(s.bag, 13), 3, "the player's three POTIONS")
  eq(Bag.get(s.bag, 14), 0, "and none of the pokedude's items")
end

print("[test] 7. pokefirered/src/item_menu.c:2069 the bag pocket and cursor survive the demo")
do
  local s = newSession()
  Bag.add(s.bag, TeachyTv.ITEM_TEACHY_TV, 1)
  Bag.add(s.bag, TeachyTv.ITEM_TM_CASE, 1)
  for id = 13, 22 do Bag.add(s.bag, id, 2) end
  Stack.clear()
  BagMenu.show(s.bag, { session = s, pocket = "ITEMS" })
  BagMenu.settle()
  for _ = 1, 4 do BagMenu.handleInput(press("down")) end
  local wantPocket, wantCursor = BagMenu.pocketIdx, BagMenu.cursor
  check(wantCursor > 1, "the player left the ITEMS cursor on row " .. tostring(wantCursor))
  BagMenu.close()

  openWith(s)
  for _ = 1, 5 do Ui.handleInput(press("down")) end
  eq(Ui.rows()[Ui.cursor].index, S.REGISTER, "the register lesson is selected")
  Ui.handleInput(press("a"))
  for _ = 1, 3000 do
    if Ui.suspended then break end
    Ui.update(1 / 60)
    Ui.handleInput(press("a"))
  end
  check(BagMenu.isOpen(), "the pokedude bag opened")
  -- pokefirered/src/item_menu.c:2079 ResetBagCursorPositions
  eq(BagMenu.cursor, 1, "the pokedude bag starts on row 1")
  for _ = 1, 900 do Ui.bagDemo.update(1 / 60) end
  check(Ui.bagDemo.finished, "the demo ran out")

  BagMenu.show(s.bag, { session = s })
  -- pokefirered/src/item_menu.c:2089 gBagMenuState.pocket = sBackupPlayerBag->pocket
  eq(BagMenu.pocketIdx, wantPocket, "the player's pocket came back")
  eq(BagMenu.cursor, wantCursor, "and the player's cursor")
  BagMenu.close()
  Stack.clear()
  Ui.open = false
end

print("[test] 8. pokefirered/src/teachy_tv.c:723 SELECT only quits when the bag is not under")
do
  local s = newSession()
  Bag.add(s.bag, TeachyTv.ITEM_TEACHY_TV, 1)
  Stack.clear()
  BagMenu.show(s.bag, { session = s })
  Ui.show(s, s.bag)
  settleFade()
  Ui.handleInput(press("select"))
  settleFade()
  check(Ui.isOpen(), "SELECT is ignored when CB2_BagMenuFromStartMenu is the callback")
  Ui.handleInput(press("b"))
  settleFade()
  BagMenu.close()

  Stack.clear()
  Ui.show(s, s.bag)
  settleFade()
  Ui.handleInput(press("select"))
  settleFade()
  check(not Ui.isOpen(), "SELECT quits when the TV came from the field")
  Stack.clear()
end

print("[test] 9. pokefirered/src/teachy_tv.c:957 the grass walk scrolls BG3")
do
  local s = newSession()
  openWith(s)
  Ui.handleInput(press("a"))
  for _ = 1, 4000 do
    if Ui.stepName() == "dude_move_up" then break end
    Ui.update(1 / 60)
    Ui.handleInput(press("a"))
  end
  eq(Ui.stepName(), "dude_move_up", "reached TTVcmd_DudeMoveUp")
  local y0, hi0 = Ui.bg3Y, Ui.grassHi
  ticks(16)
  -- pokefirered/src/teachy_tv.c:961 ChangeBgY(3, 0x100, 2)
  eq(Ui.bg3Y, y0 - 16, "BG3 scrolled up one pixel a frame")
  -- pokefirered/src/teachy_tv.c:963
  eq(Ui.grassHi, hi0 - 1, "the grass counter stepped once in 16 frames")
  ticks(T.MOVE_UP - 16)
  eq(Ui.stepName(), "dude_move_right", "48 frames later he turns right")
  local x0, lo0 = Ui.bg3X, Ui.grassLo
  ticks(16)
  -- pokefirered/src/teachy_tv.c:981 ChangeBgX(3, 0x100, 1)
  eq(Ui.bg3X, x0 + 16, "BG3 scrolled right one pixel a frame")
  eq(Ui.grassLo, lo0 + 1, "the low grass counter stepped once")
  check(#Ui.grass > 0, "tufts are out while he walks")
  Ui.handleInput(press("b"))
  -- pokefirered/src/teachy_tv.c:813 grassAnimDisabled = 1
  eq(#Ui.grass, 0, "B destroys the tufts at once")
  ticks(T.END + 2)
  -- pokefirered/src/teachy_tv.c:1059 ChangeBgX(3, 0x0, 0)
  eq(Ui.bg3X, -16, "TTVcmd_End puts BG3 back at its start offset")
  eq(Ui.bg3Y, 40, "on both axes")
  eq(#Ui.grass, 0, "and the grass objects are gone")
  Ui.handleInput(press("b"))
  Stack.clear()
end

print("[test] 10. pokefirered/src/tm_case.c:1322 the pokedude TM CASE")
do
  local TmCase = require("src.ui.game3.tm_case")
  local s = newSession()
  Bag.add(s.bag, TeachyTv.ITEM_TEACHY_TV, 1)
  Bag.add(s.bag, TeachyTv.ITEM_TM_CASE, 1)
  -- pokefirered/include/constants/items.h:301 ITEM_TM02
  Bag.add(s.bag, 290, 1)
  Stack.clear()
  Ui.show(s, s.bag)
  settleFade()
  for _ = 1, 4 do Ui.handleInput(press("down")) end
  eq(Ui.rows()[Ui.cursor].index, S.TMS, "the TM lesson is selected")
  Ui.handleInput(press("a"))
  for _ = 1, 3000 do
    if Ui.suspended then break end
    Ui.update(1 / 60)
    Ui.handleInput(press("a"))
  end
  check(BagMenu.isOpen(), "the pokedude bag opened for the TMs lesson")
  for _ = 1, 500 do Ui.bagDemo.update(1 / 60) end
  -- pokefirered/src/item_menu.c:2391
  check(TmCase.isOpen(), "the bag handed off to the pokedude TM CASE")
  check(not BagMenu.isOpen(), "and the bag closed")
  eq(Stack.top() and Stack.top().id, "teachy_pokedude_tm_case", "the TM demo drives it")
  -- pokefirered/src/tm_case.c:1334 AddBagItem(ITEM_TM01, 1)
  eq(#TmCase.list(), #TeachyTv.POKEDUDE_TMS, "it holds the pokedude's four TMs")
  eq(Bag.get(s.bag, 290), 0, "the player's own TM is put away")
  eq(Bag.get(s.bag, 289), 1, "TM01 is in the case")

  local demo = Ui.tmDemo
  for _ = 1, 720 do demo.update(1 / 60) end
  -- pokefirered/src/tm_case.c:1422
  eq(TmCase.mode, "message", "the POKé DUDE starts talking")
  eq(TmCase.messageText, TeachyTv.pagesOf(TeachyTv.TM_TYPES)[1], "gPokedudeText_TMTypes page 1")
  local pages = #TeachyTv.pagesOf(TeachyTv.TM_TYPES)
  for _ = 1, pages do demo.handleInput(press("a")) end
  eq(TmCase.mode, "list", "A pages through and hands the list back")

  for _ = 1, 720 do demo.update(1 / 60) end
  eq(TmCase.mode, "message", "the second lecture starts")
  eq(TmCase.messageText, TeachyTv.pagesOf(TeachyTv.TM_DESCRIPTION)[1],
    "gPokedudeText_ReadTMDescription page 1")
  for _ = 1, #TeachyTv.pagesOf(TeachyTv.TM_DESCRIPTION) do demo.handleInput(press("a")) end

  -- pokefirered/src/tm_case.c:1446 tPokedudeState 21
  check(demo.finished, "the TM CASE demo ran to its end")
  check(not TmCase.isOpen(), "the TM CASE closed")
  eq(Bag.get(s.bag, 290), 1, "the player's TM came back")
  eq(Bag.get(s.bag, 289), 0, "the pokedude's TMs are gone")
  eq(Bag.get(s.bag, TeachyTv.ITEM_TM_CASE), 1, "and still exactly one TM CASE")
  -- pokefirered/src/teachy_tv.c:1100 sWhereToReturnToFromBattle
  eq(Ui.state, "lesson", "the TV resumed the lesson")
  eq(Ui.stepName(), "text_printer_outro", "at step 9, the outro")
  Stack.clear()
  Ui.open = false
end

print("[test] 11. pokefirered/src/tm_case.c:1357 B aborts the TM CASE demo to the list")
do
  local TmCase = require("src.ui.game3.tm_case")
  local s = newSession()
  Bag.add(s.bag, TeachyTv.ITEM_TEACHY_TV, 1)
  Bag.add(s.bag, TeachyTv.ITEM_TM_CASE, 1)
  Bag.add(s.bag, 290, 1)
  Stack.clear()
  Ui.show(s, s.bag)
  settleFade()
  for _ = 1, 4 do Ui.handleInput(press("down")) end
  Ui.handleInput(press("a"))
  for _ = 1, 3000 do
    if Ui.suspended then break end
    Ui.update(1 / 60)
    Ui.handleInput(press("a"))
  end
  for _ = 1, 500 do Ui.bagDemo.update(1 / 60) end
  check(TmCase.isOpen(), "the TM CASE is up")
  Ui.tmDemo.handleInput(press("b"))
  check(not TmCase.isOpen(), "B closed it")
  eq(Bag.get(s.bag, 290), 1, "the player's TM came back on the abort path")
  -- pokefirered/src/tm_case.c:1361 SetTeachyTvControllerModeToResume
  eq(Ui.state, "list", "and the TV is back on its lesson list")
  Stack.clear()
  Ui.open = false
end

print("[test] 12. pokefirered/src/sound.c:129 PlayNewMapMusic leaves the location song alone")
do
  local s = newSession()
  -- pokefirered/include/constants/songs.h:308 MUS_PALLET
  Audio._mapSong = 300
  Audio.playSong(300)
  openWith(s)
  eq(Audio.currentSong() and Audio.currentSong().id, 346, "MUS_TEACHY_TV_MENU plays on the list")
  eq(Audio._mapSong, 300, "the location song is still MUS_PALLET")
  Ui.handleInput(press("a"))
  ticks(T.TITLE)
  eq(Audio.currentSong() and Audio.currentSong().id, 272, "MUS_FOLLOW_ME plays under the title")
  eq(Audio._mapSong, 300, "and the location song is untouched")
  Ui.handleInput(press("b"))
  ticks(T.END + 2)
  eq(Ui.state, "list", "back on the list")
  Ui.handleInput(press("b"))
  settleFade()
  check(not Ui.isOpen(), "B closed the TV")
  -- pokefirered/src/teachy_tv.c:705 Overworld_PlaySpecialMapMusic
  eq(Audio.currentSong() and Audio.currentSong().id, 300, "the field song comes back on close")
  eq(Audio._mapSong, 300, "the location song never changed")
  Audio._mapSong = nil
  Stack.clear()
end

print("[test] 13. pokefirered/src/data/field_effects/field_effect_objects.h:73 sAnim_TallGrass")
do
  local want = { 1, 2, 3, 4, 0 }
  for cmd = 0, 4 do
    eq(Ui.grassFrame({ frames = cmd * 10 }), want[cmd + 1], "anim command " .. cmd .. " shows sheet frame")
    eq(Ui.grassFrame({ frames = cmd * 10 + 9 }), want[cmd + 1], "for all ten frames of command " .. cmd)
  end
  eq(Ui.grassFrame({ frames = 400 }), 0, "an ended tuft holds the full frame 0")
  -- pokefirered/src/teachy_tv.c:1120 SeekSpriteAnim(obj, 4)
  local s = newSession()
  openWith(s)
  Ui.handleInput(press("a"))
  Ui.resumeFromDemonstration(1)
  local g = Ui.grass[1]
  check(g ~= nil, "the post-battle tuft spawned under the dude")
  eq(g and Ui.grassFrame(g), 0, "and it starts on the full tuft")
  eq(g and g.split, false, "drawn whole in front of him")
  Stack.clear()
  Ui.open = false
end

if failed > 0 then
  print(string.format("FAILED %d check(s)", failed))
  os.exit(1)
end
print("All teachy tv screen checks passed.")
