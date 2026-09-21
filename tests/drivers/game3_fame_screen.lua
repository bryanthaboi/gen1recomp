local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_fame_screen"

-- pokefirered/include/constants/items.h:435
local ITEM_FAME_CHECKER = 363
local VAR_0x8004, VAR_0x8005 = 0x8004, 0x8005

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS fame_screen")
    love.event.quit(0)
  else
    print("FAIL fame_screen failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Natives = require("src.core.game3.scripting.natives")
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local FameChecker = require("src.core.game3.fame_checker")
  local Ui = require("src.ui.game3.fame_checker")

  local PERSON, PICK = FameChecker.PERSON, FameChecker.PICKSTATE

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end

  -- pokefirered/asm/macros/event.inc:1825 famechecker
  local function famechecker(person, index, special)
    Flags.setVar(Space.store, ctx(), VAR_0x8004, person)
    Flags.setVar(Space.store, ctx(), VAR_0x8005, index)
    local _, _, handled = Natives.special(ctx(), special, nil)
    return handled
  end

  -- pokefirered/data/maps/PewterCity_Gym/scripts.inc:5
  result(famechecker(PERSON.BROCK, PICK.COLORED, 0x174) == true,
    "famechecker FAMECHECKER_BROCK, FCPICKSTATE_COLORED ran")
  -- pokefirered/data/maps/PewterCity_Gym/scripts.inc:13
  result(famechecker(PERSON.BROCK, 1, 0x173) == true,
    "famechecker FAMECHECKER_BROCK, 1 ran")
  famechecker(PERSON.BROCK, 3, 0x173)
  -- pokefirered/data/maps/CeruleanCity_Gym/scripts.inc:43
  famechecker(PERSON.MISTY, 2, 0x173)
  -- pokefirered/data/maps/PalletTown_ProfessorOaksLab/scripts.inc:662
  famechecker(PERSON.OAK, 1, 0x173)

  result(FameChecker.pickState(session, PERSON.BROCK) == PICK.COLORED, "BROCK is coloured")
  result(FameChecker.pickState(session, PERSON.MISTY) == PICK.SILHOUETTE,
    "MISTY is a silhouette")
  result(FameChecker.pickState(session, PERSON.KOGA) == PICK.NO_DRAW, "KOGA is not drawn")

  -- pokefirered/src/item_use.c:680 FieldUseFunc_FameChecker
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_FAME_CHECKER, 1)
  result(Bag.has(session.bag, ITEM_FAME_CHECKER, 1), "the FAME CHECKER is in the bag")
  local usedOk, usedKind = ItemUse.useField(session, session.bag, ITEM_FAME_CHECKER)
  result(usedOk == true and usedKind == "fame_checker" and Ui.isOpen(),
    "using the FAME CHECKER from the field opened the screen, kind=" .. tostring(usedKind))
  U.wait(30)
  if not result(Ui.isOpen(), "the Fame Checker screen is open") then return finish() end

  local rows = Ui.rows()
  local labels = {}
  for i, row in ipairs(rows) do labels[i] = row.label end
  print("[driver] list rows: " .. table.concat(labels, ","))
  result(#rows == 4, "three unlocked people plus CANCEL")
  result(rows[1].person == PERSON.OAK and rows[2].person == PERSON.BROCK
    and rows[3].person == PERSON.MISTY, "the list is OAK, BROCK, MISTY")
  result(rows[4].cancel == true, "CANCEL is the last row")
  U.shot(game, DIR .. "/fame_screen_01_list.png")

  U.tap(game, "down")
  U.wait(20)
  result(Ui.selectedPerson() == PERSON.BROCK, "the cursor moved to BROCK")
  local icons = Ui.icons(PERSON.BROCK)
  result(icons[1].unlocked and icons[3].unlocked and not icons[0].unlocked,
    "BROCK shows two unlocked panels and four question marks")

  U.tap(game, "start")
  U.wait(30)
  result(Ui.pickMode, "START opened pick mode")
  local source = select(2, Ui.portraitSource(PERSON.BROCK))
  print("[driver] BROCK portrait from " .. tostring(source))
  U.shot(game, DIR .. "/fame_screen_02_pick_brock.png")

  U.tap(game, "start")
  U.wait(20)
  result(not Ui.pickMode, "START closed pick mode")

  U.tap(game, "a")
  U.wait(20)
  result(Ui.mode == "flavor", "A opened the flavour text page")
  U.tap(game, "right")
  U.wait(20)
  result(Ui.iconCursor == 1, "the selector cursor is on BROCK's unlocked panel 1")
  U.shot(game, DIR .. "/fame_screen_03_flavor_page.png")

  U.tap(game, "b")
  U.wait(20)
  result(Ui.mode == "top", "B returned to the list")

  U.tap(game, "down")
  U.wait(15)
  U.tap(game, "down")
  U.wait(15)
  result(Ui.selectedRow().cancel == true, "the cursor reached CANCEL")
  U.tap(game, "a")
  U.wait(30)
  result(not Ui.isOpen(), "CANCEL closed the Fame Checker")

  -- pokefirered/src/fame_checker.c:741
  local reOk, reKind = ItemUse.useField(session, session.bag, ITEM_FAME_CHECKER)
  U.wait(30)
  result(reOk == true and reKind == "fame_checker" and Ui.isOpen(),
    "the FAME CHECKER opens again from the field")
  U.tap(game, "select")
  U.wait(30)
  result(not Ui.isOpen(), "SELECT closes a checker opened from the field")

  finish()
end
