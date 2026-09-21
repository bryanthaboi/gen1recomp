#!/usr/bin/env luajit
-- pokefirered/src/daycare.c:1531

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local store = { flags = {}, vars = {} }
local session = {
  store = store, map = "FR_FOUR_ISLAND_POKEMON_DAY_CARE", party = {},
  name = "RED", trainerId = 4242, vars = {}, flags = {},
}
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local Daycare = require("src.core.game3.daycare")
local DaycareMenu = require("src.ui.game3.daycare_menu")
local Natives = require("src.core.game3.scripting.natives")
local NativesDaycare = require("src.core.game3.scripting.natives_daycare")
local Std = require("src.core.game3.scripting.stdscripts")
local Flags = require("src.core.game3.scripting.flags")
local Stack = require("src.ui.game3.stack")
local StepEvents = require("src.core.game3.step_events")

local VAR_RESULT = 0x800D
local VAR_0x8004 = 0x8004
local VAR_0x8005 = 0x8005

local function newCtx()
  return { specialVars = {}, stringVars = { [1] = "", [2] = "", [3] = "", [4] = "" } }
end

local function getVar(ctx, id) return tonumber(Flags.getVar(store, ctx, id)) or 0 end
local function setVar(ctx, id, v) Flags.setVar(store, ctx, id, v) end

local function press(key)
  return { wasPressed = function(_, name) return name == key end }
end

print("[test] 1. the window is pret's sDaycareLevelMenuWindowTemplate")
eq(DaycareMenu.WINDOW.left, 12, "tilemapLeft 12")
eq(DaycareMenu.WINDOW.top, 1, "tilemapTop 1")
eq(DaycareMenu.WINDOW.width, 17, "17 tiles wide")
eq(DaycareMenu.WINDOW.height, 5, "5 tiles tall")
eq(DaycareMenu.ROW_PITCH, 14, "rows advance by FONT_NORMAL_COPY_2's letter height")
eq(DaycareMenu.TEXT_X, 8, "item_X is 8")
eq(DaycareMenu.LEVEL_RIGHT, 132, "the level is right aligned at 132")
eq(DaycareMenu.ROW_COUNT, 3, "three list items")

print("[test] 2. the gender symbol follows AppendGenderSymbol")
eq(DaycareMenu.genderSymbol("PIDGEY", "M"), "♂", "a male mon gets the male symbol")
eq(DaycareMenu.genderSymbol("PIDGEY", "F"), "♀", "a female mon gets the female symbol")
eq(DaycareMenu.genderSymbol("MAGNEMITE", "U"), "", "a genderless mon gets nothing")
eq(DaycareMenu.genderSymbol("NIDORAN♀", "F"), "",
  "a name that already carries its symbol gets no second one")
eq(DaycareMenu.genderSymbol("NIDORAN♀", "M"), "♂",
  "a male mon nicknamed with a female symbol still gets the male one")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("meta.json")
if not cacheRoot then
  print("[skip] game3_daycare_menu_test needs species data: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Experience = require("src.core.game3.battle.experience")
local SummaryData = require("src.core.game3.summary_data")
local Party = require("src.core.game3.party")

local PIDGEY, RATTATA, MAGIKARP, MAGNEMITE = 16, 19, 129, 81

local function makeMon(species, level, gender)
  local scratch = { party = {}, name = "RED", trainerId = 4242 }
  local ok, _, mon = Party.giveMon(scratch, species, level, "")
  check(ok, "built a level " .. level .. " species " .. species)
  if gender then
    mon.personality = mon.personality - (mon.personality % 256) + (gender == "F" and 0 or 254)
    mon.gender = Pokemon.gender(species, mon.personality)
  end
  return mon
end

local function stepsForLevels(mon, toLevel)
  local growth = Experience.growthRate(mon)
  return SummaryData.expForLevel(growth, toLevel)
    - SummaryData.expForLevel(growth, tonumber(mon.level) or 1)
end

local function walk(n)
  for _ = 1, n do StepEvents.onStepTaken(session, nil) end
end

local function board(mon)
  session.party[#session.party + 1] = mon
  local ctx = newCtx()
  setVar(ctx, VAR_0x8004, #session.party - 1)
  Natives.special(ctx, Std.SPECIAL.StoreSelectedPokemonInDaycare, nil)
end

print("[test] 3. the rows name both boarded mons with their level after steps")
local hen, cock = makeMon(PIDGEY, 5, "F"), makeMon(RATTATA, 5, "M")
eq(hen.gender, "F", "the PIDGEY is female")
eq(cock.gender, "M", "the RATTATA is male")
board(hen)
board(cock)
local dc = Daycare.stateOf(session)
eq(Daycare.count(dc), 2, "both mons are in the Four Island day care")
walk(stepsForLevels(hen, 9))
local rows = DaycareMenu.rows(dc)
eq(#rows, 3, "three rows")
eq(rows[1].text, Pokemon.name(PIDGEY), "row 1 is the first slot's nickname")
eq(rows[1].symbol, "♀", "with the female symbol after it")
eq(DaycareMenu.label(rows[1]), Pokemon.name(PIDGEY) .. "♀", "printed as one string, as pret does")
eq(rows[1].level, "Lv9", "row 1 shows the level the banked steps have earned")
eq(rows[1].value, 0, "row 1 is list item 0")
eq(rows[2].text, Pokemon.name(RATTATA), "row 2 is the second slot's nickname")
eq(rows[2].symbol, "♂", "with the male symbol")
eq(rows[2].value, 1, "row 2 is list item 1")
eq(rows[3].text, "EXIT", "row 3 is EXIT")
eq(rows[3].value, 5, "EXIT is DAYCARE_LEVEL_MENU_EXIT")
eq(rows[3].level, "", "and carries no level")
eq(DaycareMenu.levelX(rows[1]) + DaycareMenu.textWidth(rows[1].level), 132,
  "the level text ends at x 132")
eq(DaycareMenu.levelX(rows[3]), nil, "EXIT prints no level at all")

print("[test] 4. ShowDaycareLevelMenu returns pret's three results")
local function openMenu()
  local ctx = newCtx()
  setVar(ctx, VAR_RESULT, 99)
  Natives.special(ctx, Std.SPECIAL.ShowDaycareLevelMenu, nil)
  return ctx
end
local ctx = openMenu()
check(DaycareMenu.isOpen(), "the level menu is on the UI stack")
check(Stack.has("daycare_level_menu"), "and the stack knows it")
check(ctx.stateWait ~= nil and ctx.stateWait() == false,
  "waitstate blocks the script while the menu is up")
DaycareMenu.handleInput(press("a"))
eq(getVar(ctx, VAR_RESULT), 0, "A on the first row returns 0")
check(ctx.stateWait(), "and the script resumes")
check(not DaycareMenu.isOpen(), "the menu closed itself")
check(not Stack.has("daycare_level_menu"), "and left the stack")

ctx = openMenu()
DaycareMenu.handleInput(press("down"))
eq(DaycareMenu.cursor, 2, "DOWN moves to the second mon")
DaycareMenu.handleInput(press("a"))
eq(getVar(ctx, VAR_RESULT), 1, "A on the second row returns 1")

ctx = openMenu()
DaycareMenu.handleInput(press("down"))
DaycareMenu.handleInput(press("down"))
eq(DaycareMenu.cursor, 3, "DOWN again lands on EXIT")
DaycareMenu.handleInput(press("down"))
eq(DaycareMenu.cursor, 3, "and the list does not wrap")
DaycareMenu.handleInput(press("a"))
eq(getVar(ctx, VAR_RESULT), 2, "A on EXIT returns DAYCARE_EXITED_LEVEL_MENU")

ctx = openMenu()
DaycareMenu.handleInput(press("b"))
eq(getVar(ctx, VAR_RESULT), 2, "B returns DAYCARE_EXITED_LEVEL_MENU too")

print("[test] 5. the cost prompt prices the stay at 100 + 100 per level")
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.GetDaycareCost, nil)
eq(ctx.stringVars[1], Pokemon.name(PIDGEY), "STR_VAR_1 is the mon the player picked")
eq(getVar(ctx, VAR_0x8005), 500, "four levels gained costs 500")
eq(ctx.stringVars[2], "500", "STR_VAR_2 carries the same figure for the text box")
ctx = newCtx()
setVar(ctx, VAR_0x8004, 1)
Natives.special(ctx, Std.SPECIAL.GetDaycareCost, nil)
eq(getVar(ctx, VAR_0x8005), 100 + 100 * Daycare.levelsGained(cock, dc.steps[2]),
  "the other slot is priced from its own banked steps")

print("[test] 6. SetDaycareCompatibilityString picks pret's four lines")
local LINES = {
  [NativesDaycare.PARENTS_MAX_COMPATIBILITY] = "The two seem to get along\nvery well.",
  [NativesDaycare.PARENTS_MED_COMPATIBILITY] = "The two seem to get along.",
  [NativesDaycare.PARENTS_LOW_COMPATIBILITY] = "The two don't seem to like\neach other much.",
  [NativesDaycare.PARENTS_INCOMPATIBLE] =
    "The two prefer to play with other\nPOKéMON than each other.",
}
for score, line in pairs(LINES) do
  eq(NativesDaycare.compatibilityText(score), line, "score " .. score .. " picks its line")
end
ctx = newCtx()
Natives.special(ctx, Std.SPECIAL.SetDaycareCompatibilityString, nil)
eq(ctx.stringVars[4], LINES[NativesDaycare.compatibility(dc)],
  "STR_VAR_4 carries the line for the pair actually boarded")

print("[test] 7. the egg is refused while the party is full")
session.party = {}
for _ = 1, 6 do session.party[#session.party + 1] = makeMon(MAGNEMITE, 5) end
session.modData[Daycare.SAVE_KEY].daycare = nil
session.daycare = nil
dc = Daycare.stateOf(session)
local mother, father = makeMon(MAGIKARP, 5, "F"), makeMon(MAGIKARP, 5, "M")
father.otId = (tonumber(mother.otId) or 0) + 1111
Daycare.setMon(dc, 1, mother)
Daycare.setMon(dc, 2, father)
local Breeding = require("src.core.game3.breeding")
eq(Breeding.compatibility(dc), NativesDaycare.PARENTS_MAX_COMPATIBILITY,
  "the boarded pair is a breeding pair")
local function walkUntilEgg()
  for _ = 1, 256 * 12 do
    if Daycare.isEggPending(dc) then return true end
    StepEvents.onStepTaken(session, nil)
  end
  return Daycare.isEggPending(dc)
end
check(walkUntilEgg(), "walking produced an egg to collect")
local _, full = Natives.special(newCtx(), Std.SPECIAL.CalculatePlayerPartyCount, nil)
eq(full, 6, "CalculatePlayerPartyCount is PARTY_SIZE, so the script never offers")
local sixth = session.party[6]
Natives.special(newCtx(), Std.SPECIAL.GiveEggFromDaycare, nil)
eq(#session.party, 6, "the party is still six mons")
eq(session.party[6], sixth, "the last party slot was not overwritten")
check(Daycare.isEggPending(dc), "and the egg is still waiting at the day care")

print("[test] 8. with room, the hand-off puts the egg in the party")
session.party[6] = nil
Natives.special(newCtx(), Std.SPECIAL.GiveEggFromDaycare, nil)
eq(#session.party, 6, "the egg took the free slot")
local egg = session.party[6]
check(egg ~= nil and egg.isEgg == true, "the sixth slot holds an EGG")
eq(egg and egg.species, MAGIKARP, "two MAGIKARP handed over a MAGIKARP egg")
check(not Daycare.isEggPending(dc), "the day care has nothing pending any more")
eq(Daycare.count(dc), 2, "and the parents stay boarded, as pret leaves them")

print("[test] 9. RejectEggFromDayCare throws the egg away")
check(walkUntilEgg(), "a second egg is waiting")
Natives.special(newCtx(), Std.SPECIAL.RejectEggFromDayCare, nil)
check(not Daycare.isEggPending(dc), "it is gone after RejectEggFromDayCare")
eq(dc.stepCounter, 0, "RemoveEggFromDayCare zeroes the step counter too")

finish()
