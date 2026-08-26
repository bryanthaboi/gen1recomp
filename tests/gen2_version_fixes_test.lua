-- The faithfulness convention: Gold and Silver keep their original cart bugs
-- wherever the bug is not hardware-dependent, and Crystal gets the fixes
-- Crystal shipped.  GameVersion.fixes(id) names the FIX, so an absent table
-- reads as "bugged like the cart".
--   luajit tests/gen2_version_fixes_test.lua
--
-- Four of pokegold's seven documented bugs are engine behaviour this port can
-- express.  This file pins the two that are reachable from Lua state:
--
--   luckyNumberBoxes  the Lucky Number Show's loop bound
--   halloffame        the first-save PC corruption, which is NOT reachable
--                     here and is pinned as such rather than emulated
--
-- surfOntoNpc lives with the field-move unit and reflectOverflow with the
-- battle unit; only the flag names are asserted here.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 version fixes")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local GameVersion = require("src.core.GameVersion")
local HallOfFame = require("src.core.gen2.HallOfFame")
local Save = require("src.core.gen2.Save")
local Specials = require("src.script.gen2.Specials")

local priorVersion = GameVersion.get()

-- ---- CT-10: the API shape -------------------------------------------------

eq(type(GameVersion.fixes), "function", "GameVersion.fixes is an accessor")
eq(type(GameVersion.fixes("crystal")), "table", "and it returns a table")

for _, id in ipairs({ "red", "blue", "yellow", "gold", "silver" }) do
  eq(next(GameVersion.fixes(id)), nil, id .. " fixes nothing")
end
eq(next(GameVersion.fixes("nonesuch")), nil, "an unknown id reads as {}")

for _, name in ipairs({ "luckyNumberBoxes", "surfOntoNpc", "reflectOverflow" }) do
  eq(GameVersion.fixes("crystal")[name], true, "crystal fixes " .. name)
end

do
  local count = 0
  for _ in pairs(GameVersion.fixes("crystal")) do count = count + 1 end
  eq(count, 3, "and carries no fix name a consumer was not told about")
end

GameVersion.set("gold")
eq(next(GameVersion.fixes()), nil, "the active version is the default subject")
GameVersion.set("crystal")
eq(GameVersion.fixes().luckyNumberBoxes, true, "which follows GameVersion.set")

-- Gold's row must stay bug-shaped even if someone later hangs data off it.
GameVersion.set("gold")
check(GameVersion.info("gold").fixes == nil, "the gold row has no fixes table")
check(GameVersion.info("silver").fixes == nil, "nor does silver")

-- ---- the Lucky Number Show, boxes 10-14 -----------------------------------
--
-- pokegold/engine/events/lucky_number.asm:100-102 bounds .BoxesLoop with
-- NUM_BOXES_JP (9, pokegold/constants/pokemon_data_constants.asm:123) where
-- pokecrystal/engine/events/lucky_number.asm:99 uses NUM_BOXES (14).  The OPEN
-- box is walked out of sBox before that loop starts and the loop then skips
-- it, so the current box is searched on both carts whatever its number.

local function boxSet(order)
  local seen = {}
  for _, index in ipairs(order) do seen[index] = true end
  return seen
end

GameVersion.set("gold")
do
  local order = Specials.luckyNumberBoxOrder({ currentBox = 1 })
  eq(#order, 9, "Gold walks nine boxes")
  eq(order[1], 1, "starting with the open one")
  local seen = boxSet(order)
  for index = 1, 9 do check(seen[index], "gold searches box " .. index) end
  for index = 10, 14 do
    check(not seen[index], "gold skips box " .. index .. " (the cart bug)")
  end
end

do
  local order = Specials.luckyNumberBoxOrder({ currentBox = 12 })
  eq(order[1], 12, "the open box is searched first even at 12")
  eq(#order, 10, "on top of the nine .BoxesLoop reaches")
  check(boxSet(order)[12], "so box 12 is not skipped while it is open")
end

GameVersion.set("crystal")
do
  local order = Specials.luckyNumberBoxOrder({ currentBox = 1 })
  eq(#order, 14, "Crystal walks all fourteen")
  local seen = boxSet(order)
  for index = 1, 14 do check(seen[index], "crystal searches box " .. index) end
end

do
  local order = Specials.luckyNumberBoxOrder({})
  eq(order[1], 1, "a save with no currentBox opens box 1")
  eq(#order, 14, "and still walks the full set")
end

-- The handler itself, over the same fixture on both editions.  The party mon
-- shares three trailing digits (second prize, wScriptVar 2); the mon in box 12
-- is an exact match (first prize, wScriptVar 1), and the BEST match wins.
local function luckyVm(record)
  return {
    specials = {
      save = function() return record end,
      party = function() return record.party end,
      monName = function(species) return species end,
    },
    setStringBuffer = function(self, value) self.stringBuffer = value end,
  }
end

local function luckyFixture(boxIndex, currentBox)
  local record = {
    luckyNumber = 12345,
    currentBox = currentBox or 1,
    party = { { species = "CHIKORITA", otId = 99345 } },
    boxes = {},
  }
  record.boxes[boxIndex] = { { species = "MAGIKARP", otId = 12345 } }
  return record
end

GameVersion.set("gold")
do
  local vm = luckyVm(luckyFixture(3))
  Specials.HANDLERS.CheckForLuckyNumberWinners(vm)
  eq(vm.scriptVar, 1, "Gold finds an exact match in box 3")
  check(vm.luckyNumberInBox, "and reports it came from a box")
end

do
  local vm = luckyVm(luckyFixture(12))
  Specials.HANDLERS.CheckForLuckyNumberWinners(vm)
  eq(vm.scriptVar, 2, "Gold never sees the same mon in box 12")
  check(not vm.luckyNumberInBox, "so the party's partial match wins instead")
end

do
  local vm = luckyVm(luckyFixture(12, 12))
  Specials.HANDLERS.CheckForLuckyNumberWinners(vm)
  eq(vm.scriptVar, 1, "unless box 12 is the box the PC has open")
end

GameVersion.set("crystal")
do
  local vm = luckyVm(luckyFixture(12))
  Specials.HANDLERS.CheckForLuckyNumberWinners(vm)
  eq(vm.scriptVar, 1, "Crystal finds box 12 without opening it")
  check(vm.luckyNumberInBox, "and reports it came from a box")
end

do
  local vm = luckyVm(luckyFixture(14))
  Specials.HANDLERS.CheckForLuckyNumberWinners(vm)
  eq(vm.scriptVar, 1, "and box 14, the last one")
end

-- ---- the Hall of Fame, first-save PC corruption ---------------------------
--
-- pokegold/engine/events/halloffame.asm:17 is the bug marker; Crystal farcalls
-- HallOfFame_InitSaveIfNeeded there (pokecrystal/engine/menus/save.asm:470-475)
-- to run ErasePreviousSave over uninitialised SRAM.  This port has no SRAM, so
-- the induction is pinned as harmless here rather than emulated.

GameVersion.set("gold")
do
  local save = Save.newGame({ name = "GOLD", gender = "male" })
  save.boxes[7] = { { species = "SUDOWOODO", level = 20, otId = 111 } }
  save.boxNames[7] = "TREES"
  save.currentBox = 7
  eq(HallOfFame.count(save), 0, "a fresh save has never been inducted")
  check(not HallOfFame.hasEntered(save), "and carries no status flag")

  local party = { { species = "TYPHLOSION", level = 55, otId = 222,
    nickname = "TYPHLO" } }
  local entry, wasEntered = HallOfFame.induct(save, party)
  check(entry ~= nil, "induction on a never-saved file returns a row")
  check(not wasEntered, "and reports the player was not already a champion")
  eq(HallOfFame.count(save), 1, "the win counter reaches one")
  eq(#save.boxes[7], 1, "box 7 still holds its mon")
  eq(save.boxes[7][1].species, "SUDOWOODO", "unchanged")
  eq(save.boxNames[7], "TREES", "its name survives too")
  eq(save.currentBox, 7, "and the open box is still open")
  for index = 1, Save.NUM_BOXES do
    local box = save.boxes[index]
    check(box == nil or type(box) == "table",
      "box " .. index .. " is a table or absent, never garbage")
  end
end

-- ---- the Coin Case terminator ---------------------------------------------
--
-- pokegold/data/text/common_3.asm:341 ends _CoinCaseCountText with `done` ($57)
-- where pokecrystal/data/text/common_3.asm:1308 uses `text_end`, and
-- pokegold/home/text.asm:590-593 stops only on TX_END.  The port decodes the
-- stream once at import (decodeGen2Text breaks on $57), so the cache is the
-- evidence that nothing runs past the string.

local cache = os.getenv("GOLD_CACHE")
if not cache then
  local home = os.getenv("HOME") or ""
  cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
end
local textPath = cache .. "/data/generated/rom_text.lua"
local tf = io.open(textPath, "r")
if not tf then
  check(true, "rom_text.lua absent : no gold cache (SKIP cache facts)")
else
  tf:close()
  local romText = assert(loadfile(textPath))()
  eq(romText._CoinCaseCountText, "Coins:\n{NUM}",
    "the `done` terminator still ends the decoded string")
  check(not tostring(romText._CoinCaseCountText or ""):find("Raise the PP"),
    "and nothing from the next label runs into it")
end

GameVersion.set(priorVersion)

S.finish()
