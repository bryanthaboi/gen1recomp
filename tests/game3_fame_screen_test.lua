#!/usr/bin/env luajit
-- pokefirered/src/fame_checker.c:729

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
local cacheRoot = Cache.mount("trainers.lua")
if not cacheRoot then
  print("[skip] game3_fame_screen: " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local FameChecker = require("src.core.game3.fame_checker")
local Ui = require("src.ui.game3.fame_checker")
local Stack = require("src.ui.game3.stack")

local PERSON = FameChecker.PERSON
local PICK = FameChecker.PICKSTATE
local NSLOT = FameChecker.NUM_FLAVOR_TEXTS

local function press(key)
  return { wasPressed = function(_, k) return k == key end }
end

local function newSession()
  return { modData = {}, name = "RED", rivalName = "BLUE" }
end

local function openWith(session, opts)
  Stack.clear()
  Ui.show(session, opts)
end

local function labels()
  local out = {}
  for i, row in ipairs(Ui.rows()) do out[i] = row.label end
  return out
end

print("[test] 1. the list carries the drawn people and CANCEL")
do
  local s = newSession()
  openWith(s)
  local rows = Ui.rows()
  eq(#rows, 2, "a new game lists OAK and CANCEL")
  eq(rows[1].person, PERSON.OAK, "OAK is the first row")
  check(rows[2].cancel == true, "the last row is CANCEL")
  -- pokefirered/src/strings.c:128 gFameCheckerText_Cancel
  eq(rows[2].label, "CANCEL", "the CANCEL label")

  FameChecker.updatePickState(PERSON.BROCK, PICK.COLORED, s)
  FameChecker.updatePickState(PERSON.MISTY, PICK.SILHOUETTE, s)
  rows = Ui.rows()
  eq(#rows, 4, "two more people join the list")
  eq(rows[2].person, PERSON.BROCK, "BROCK is row 2")
  eq(rows[3].person, PERSON.MISTY, "MISTY is row 3")
  eq(rows[2].label, "BROCK", "BROCK's list label comes from gTrainers")
  eq(rows[3].label, "MISTY", "MISTY's list label comes from gTrainers")
  check(rows[4].cancel == true, "CANCEL stays last")

  local names = table.concat(labels(), ",")
  check(not names:find("KOGA"), "an undrawn person is not listed (" .. names .. ")")
end

print("[test] 2. the non-trainer names")
do
  local s = newSession()
  FameChecker.fullyUnlock(s)
  openWith(s)
  -- pokefirered/src/strings.c:1272
  eq(Ui.personName(PERSON.OAK), "OAK", "OAK")
  eq(Ui.personName(PERSON.DAISY), "DAISY", "DAISY")
  eq(Ui.personName(PERSON.BILL), "BILL", "BILL")
  eq(Ui.personName(PERSON.MRFUJI), "FUJI", "FUJI")
  eq(Ui.personName(PERSON.GIOVANNI), "GIOVANNI", "GIOVANNI comes from gTrainers")
  eq(#Ui.rows(), FameChecker.NUM_PERSONS + 1, "a fully unlocked checker lists all 16 plus CANCEL")
end

print("[test] 3. the per-person page shows only the unlocked slots")
do
  local s = newSession()
  FameChecker.updatePickState(PERSON.BROCK, PICK.COLORED, s)
  FameChecker.setFlavorText(PERSON.BROCK, 1, s)
  FameChecker.setFlavorText(PERSON.BROCK, 4, s)
  openWith(s)
  Ui.handleInput(press("down"))
  eq(Ui.selectedPerson(), PERSON.BROCK, "the cursor is on BROCK")
  local icons = Ui.icons(PERSON.BROCK)
  local unlocked = {}
  for slot = 0, NSLOT - 1 do
    if icons[slot].unlocked then unlocked[#unlocked + 1] = slot end
  end
  eq(#unlocked, 2, "two of the six panels are unlocked")
  eq(unlocked[1], 1, "slot 1 is unlocked")
  eq(unlocked[2], 4, "slot 4 is unlocked")
  -- pokefirered/src/fame_checker.c:265 sFameCheckerArrayNpcGraphicsIds
  eq(icons[1].graphicsId, 80, "slot 1 draws OBJ_EVENT_GFX_BROCK")
  eq(icons[4].graphicsId, 30, "slot 4 draws OBJ_EVENT_GFX_BALDING_MAN")
  eq(icons[0].graphicsId, nil, "a locked slot has no icon graphic")
  eq(icons[2].graphicsId, nil, "a locked slot has no icon graphic")
  check(Ui.personHasUnlockedPanels(PERSON.BROCK), "BROCK has unlocked panels")
  check(not Ui.personHasUnlockedPanels(PERSON.KOGA), "KOGA has none")
end

print("[test] 4. the pick mode picture")
do
  local s = newSession()
  FameChecker.updatePickState(PERSON.BROCK, PICK.COLORED, s)
  FameChecker.updatePickState(PERSON.MISTY, PICK.SILHOUETTE, s)
  openWith(s)
  -- pokefirered/src/fame_checker.c:171 sFameCheckerTrainerPicIdxs
  local source, path = Ui.portraitSource(PERSON.BROCK)
  eq(source, "trainer", "BROCK uses CreateTrainerPicSprite")
  check(path:find("/trainers/front/116%.rgba$") ~= nil,
    "TRAINER_PIC_LEADER_BROCK is pic 116 (" .. tostring(path) .. ")")
  local f = io.open(path, "rb")
  check(f ~= nil, "the trainer pic is in the cache today")
  if f then
    local bytes = f:read("*a")
    f:close()
    eq(#bytes, 64 * 64 * 4, "it is a 64x64 RGBA sprite")
  end

  -- pokefirered/src/fame_checker.c:1344 sDaisySpriteTemplate
  for _, p in ipairs({ PERSON.OAK, PERSON.DAISY, PERSON.BILL, PERSON.MRFUJI }) do
    local src2, path2 = Ui.portraitSource(p)
    eq(src2, "art", "person " .. p .. " uses the Fame Checker's own art")
    check(path2:find("/fame_checker/" .. p .. "%.rgba$") ~= nil,
      "person " .. p .. " reads " .. tostring(path2))
  end
  eq(Ui.portraitSource(FameChecker.NUM_PERSONS), nil, "person 16 has no picture")

  -- pokefirered/src/fame_checker.c:1374 sSilhouettePalette
  eq(FameChecker.pickState(s, PERSON.MISTY), PICK.SILHOUETTE,
    "MISTY is drawn as a silhouette")
  eq(FameChecker.pickState(s, PERSON.BROCK), PICK.COLORED, "BROCK is drawn coloured")
end

print("[test] 5. the art and text missing fallback")
do
  local s = newSession()
  FameChecker.updatePickState(PERSON.BROCK, PICK.COLORED, s)
  FameChecker.setFlavorText(PERSON.BROCK, 1, s)
  openWith(s)
  Ui.handleInput(press("down"))
  Ui.handleInput(press("start"))
  check(Ui.pickMode, "START put BROCK in pick mode")
  local pack = Ui.pack()
  if pack == nil then
    print("[info] no fame_checker pack in this cache; checking the fallback")
    eq(Ui.flavorText(PERSON.BROCK, 1), nil, "no flavour text without the pack")
    eq(Ui.pickModeText(PERSON.BROCK), nil, "no name or quote text without the pack")
    eq(Ui.messageText(), "BROCK", "pick mode falls back to the name-only list entry")
    Ui.handleInput(press("start"))
    check(not Ui.pickMode, "START left pick mode again")
    Ui.handleInput(press("a"))
    eq(Ui.mode, "flavor", "the page still opens")
    -- pokefirered/src/fame_checker.c:944
    eq(Ui.messageText(), nil, "a locked icon leaves the message box empty")
    Ui.handleInput(press("right"))
    eq(Ui.iconCursor, 1, "the cursor is on the unlocked icon")
    eq(Ui.messageText(), "BROCK", "the page falls back to the name-only entry")
  else
    print("[info] fame_checker pack present; checking the real text")
    local text = Ui.flavorText(PERSON.BROCK, 1)
    check(type(text) == "string" and #text > 0, "BROCK slot 1 has flavour text")
    check(type(Ui.pickModeText(PERSON.BROCK)) == "string", "BROCK has a name string")
    local msg = Ui.messageText()
    check(type(msg) == "string" and #msg > 0, "pick mode prints it")
  end
end

print("[test] 6. START enters and leaves pick mode")
do
  local s = newSession()
  FameChecker.updatePickState(PERSON.BROCK, PICK.COLORED, s)
  openWith(s)
  Ui.handleInput(press("down"))
  check(not Ui.pickMode, "pick mode starts off")
  Ui.handleInput(press("start"))
  check(Ui.pickMode, "START enters pick mode")
  Ui.handleInput(press("start"))
  check(not Ui.pickMode, "START leaves it again")
  Ui.handleInput(press("start"))
  check(Ui.pickMode, "START enters it once more")
  Ui.handleInput(press("b"))
  check(not Ui.pickMode, "B leaves pick mode instead of closing")
  check(Ui.isOpen(), "the screen is still open")

  Ui.handleInput(press("down"))
  check(Ui.selectedRow().cancel == true, "the cursor walked down to CANCEL")
  Ui.handleInput(press("start"))
  check(not Ui.pickMode, "START over CANCEL does nothing")
end

print("[test] 7. A opens the flavour text page, B backs out, CANCEL closes")
do
  local s = newSession()
  FameChecker.updatePickState(PERSON.KOGA, PICK.SILHOUETTE, s)
  openWith(s)
  Ui.handleInput(press("down"))
  eq(Ui.selectedPerson(), PERSON.KOGA, "KOGA is row 2")
  Ui.handleInput(press("a"))
  eq(Ui.mode, "top", "A does nothing for a person with no unlocked panels")

  FameChecker.setFlavorText(PERSON.KOGA, 0, s)
  Ui.handleInput(press("a"))
  eq(Ui.mode, "flavor", "A opens the page once a panel is unlocked")
  Ui.handleInput(press("b"))
  eq(Ui.mode, "top", "B returns to the list")
  check(Ui.isOpen(), "and leaves the screen open")

  Ui.handleInput(press("down"))
  check(Ui.selectedRow().cancel == true, "the cursor is on CANCEL")
  Ui.handleInput(press("a"))
  check(not Ui.isOpen(), "A on CANCEL closes the Fame Checker")
  check(not Stack.has("fame_checker"), "and pops the UI stack layer")
end

print("[test] 8. B and SELECT close from the top menu")
do
  local s = newSession()
  openWith(s)
  Ui.handleInput(press("b"))
  check(not Ui.isOpen(), "B closes from the top menu")

  -- pokefirered/src/fame_checker.c:741
  openWith(s)
  Ui.handleInput(press("select"))
  check(not Ui.isOpen(), "SELECT closes when opened from the field")

  openWith(s, { fromBag = true })
  Ui.handleInput(press("select"))
  check(Ui.isOpen(), "SELECT does nothing when opened from the bag")
  Ui.close()
end

print("[test] 9. the icon cursor wraps the way pret wraps it")
do
  local s = newSession()
  FameChecker.updatePickState(PERSON.BROCK, PICK.COLORED, s)
  for slot = 0, NSLOT - 1 do FameChecker.setFlavorText(PERSON.BROCK, slot, s) end
  openWith(s)
  Ui.handleInput(press("down"))
  Ui.handleInput(press("a"))
  eq(Ui.mode, "flavor", "the page is open")
  eq(Ui.iconCursor, 0, "it starts on slot 0")

  -- pokefirered/src/fame_checker.c:889
  Ui.handleInput(press("right"))
  eq(Ui.iconCursor, 1, "right moves along the row")
  Ui.handleInput(press("right"))
  eq(Ui.iconCursor, 2, "right again")
  Ui.handleInput(press("right"))
  eq(Ui.iconCursor, 0, "right off the end of the row wraps back to its start")
  Ui.handleInput(press("left"))
  eq(Ui.iconCursor, 2, "left off the start wraps to the end of the row")
  Ui.handleInput(press("down"))
  eq(Ui.iconCursor, 5, "down moves to the second row")
  Ui.handleInput(press("down"))
  eq(Ui.iconCursor, 2, "down again comes back to the first row")
  Ui.handleInput(press("up"))
  eq(Ui.iconCursor, 5, "up is the same move as down")
  Ui.handleInput(press("left"))
  eq(Ui.iconCursor, 4, "left on the second row")
  Ui.handleInput(press("right"))
  eq(Ui.iconCursor, 5, "right back")

  Ui.handleInput(press("b"))
  Ui.handleInput(press("down"))
  eq(Ui.iconCursor, 0, "moving the list cursor resets the icon cursor")
  Ui.close()
end

print("[test] 10. the UI help line tracks pret's three states")
do
  local s = newSession()
  FameChecker.updatePickState(PERSON.BROCK, PICK.COLORED, s)
  openWith(s)
  Ui.handleInput(press("down"))
  -- pokefirered/src/strings.c:1270 gFameCheckerText_PickScreenUI
  eq(Ui.helpText(), "{START_BUTTON}PICK {DPAD_UPDOWN}SELECT {B_BUTTON}CANCEL",
    "a person with no unlocked panels shows PrintUIHelp(1)")
  FameChecker.setFlavorText(PERSON.BROCK, 0, s)
  -- pokefirered/src/strings.c:1269 gFameCheckerText_MainScreenUI
  eq(Ui.helpText(), "{START_BUTTON}PICK {DPAD_UPDOWN}SELECT {A_BUTTON}OK",
    "once a panel is unlocked it shows PrintUIHelp(0)")
  Ui.handleInput(press("start"))
  eq(Ui.helpText(), "{START_BUTTON}PICK {DPAD_UPDOWN}SELECT {B_BUTTON}CANCEL",
    "pick mode shows PrintUIHelp(1)")
  Ui.handleInput(press("start"))
  Ui.handleInput(press("a"))
  -- pokefirered/src/strings.c:1271 gFameCheckerText_FlavorTextUI
  eq(Ui.helpText(), "{DPAD_ANY}PICK {A_BUTTON}READ {B_BUTTON}CANCEL",
    "the flavour text page shows PrintUIHelp(2)")
  Ui.close()
end

print("[test] 11. the CANCEL row describes itself")
do
  local s = newSession()
  openWith(s)
  Ui.handleInput(press("down"))
  -- pokefirered/src/strings.c:601 gFameCheckerText_FameCheckerWillBeClosed
  eq(Ui.messageText(), "The FAME CHECKER will be closed.",
    "PrintCancelDescription runs on the CANCEL row")
  Ui.handleInput(press("up"))
  eq(Ui.messageText(), nil, "a person row leaves the message box empty")
  Ui.close()
end

print("[test] 12. the list scrolls the way pret's ListMenu scrolls")
do
  local s = newSession()
  for p = PERSON.BROCK, PERSON.BLAINE do
    FameChecker.updatePickState(p, PICK.COLORED, s)
  end
  openWith(s)
  eq(#Ui.rows(), 9, "eight drawn people plus CANCEL")
  local function row() return Ui.cursor - 1 - Ui.scroll end
  eq(Ui.scroll, 0, "the list starts unscrolled")
  eq(row(), 0, "and on its first row")

  -- pokefirered/src/list_menu.c:438 ListMenuUpdateSelectedRowIndexAndScrollOffset
  for i = 1, 3 do
    Ui.handleInput(press("down"))
    eq(Ui.scroll, 0, "down " .. i .. " does not scroll yet")
    eq(row(), i, "down " .. i .. " walks the cursor to row " .. i)
  end
  Ui.handleInput(press("down"))
  eq(Ui.cursor, 5, "the fourth down selects the fifth entry")
  eq(Ui.scroll, 1, "and scrolls the list instead of the cursor")
  eq(row(), 3, "the cursor holds on row 3 going down")

  for _ = 1, 4 do Ui.handleInput(press("down")) end
  eq(Ui.cursor, 9, "eight downs reach CANCEL")
  eq(Ui.scroll, 4, "the list is scrolled to its end")
  eq(row(), 4, "and the cursor drops to the last visible row")
  Ui.handleInput(press("down"))
  eq(Ui.cursor, 9, "down on the last row does not wrap")

  for _ = 1, 3 do Ui.handleInput(press("up")) end
  eq(Ui.cursor, 6, "three ups walk back up the window")
  eq(Ui.scroll, 4, "without scrolling")
  eq(row(), 1, "the cursor holds on row 1 going up")
  Ui.handleInput(press("up"))
  eq(Ui.cursor, 5, "the fourth up selects the fifth entry")
  eq(Ui.scroll, 3, "and scrolls the list back")
  eq(row(), 1, "the cursor stays on row 1")

  for _ = 1, 8 do Ui.handleInput(press("up")) end
  eq(Ui.cursor, 1, "eight more ups reach the top")
  eq(Ui.scroll, 0, "with the list unscrolled")
  Ui.handleInput(press("up"))
  eq(Ui.cursor, 1, "up on the first row does not wrap")
  Ui.close()
end

if failed == 0 then
  print("PASS game3_fame_screen")
  os.exit(0)
end
print("FAIL game3_fame_screen failures=" .. failed)
os.exit(1)
