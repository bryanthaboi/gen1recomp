local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import2_fame"

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
    print("PASS import2_fame")
    love.event.quit(0)
  else
    print("FAIL import2_fame failures=" .. failures)
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

  -- pokefirered/data/maps/PalletTown_ProfessorOaksLab/scripts.inc:662
  famechecker(PERSON.OAK, PICK.COLORED, 0x174)
  famechecker(PERSON.OAK, 0, 0x173)
  famechecker(PERSON.OAK, 1, 0x173)
  -- pokefirered/data/maps/PewterCity_Gym/scripts.inc:5
  famechecker(PERSON.BROCK, PICK.COLORED, 0x174)
  famechecker(PERSON.BROCK, 1, 0x173)
  result(FameChecker.pickState(session, PERSON.OAK) == PICK.COLORED, "OAK is unlocked")

  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_FAME_CHECKER, 1)
  local usedOk = ItemUse.useField(session, session.bag, ITEM_FAME_CHECKER)
  U.wait(30)
  if not result(usedOk == true and Ui.isOpen(), "the FAME CHECKER opened the screen") then
    return finish()
  end

  -- src/graphics.c:1230 gFameCheckerBgTiles composited with the two tilemaps
  local bg = Ui.background()
  result(bg ~= nil, "the baked page background loaded from the cache")
  if bg then
    result(bg:getWidth() == 240 and bg:getHeight() == 160,
      "the page is 240x160, got " .. bg:getWidth() .. "x" .. bg:getHeight())
  end

  local pack = Ui.pack()
  result(type(pack) == "table", "the baked fame_checker/pack.lua loaded from the cache")
  if pack then
    result(pack.names[0] == "PROF. OAK",
      "the pack carries the cart's names, got " .. tostring(pack.names[0]))
  end
  result(Ui.personName(PERSON.OAK) == "OAK",
    "the list row name came from the pack, got " .. tostring(Ui.personName(PERSON.OAK)))

  U.shot(game, DIR .. "/import2_fame_01_list.png")

  -- pokefirered/src/fame_checker.c:1342 CreatePersonPicSprite, OAK has his own art
  local img, source = Ui.portrait(PERSON.OAK)
  result(img ~= nil and source == "art",
    "the OAK portrait is the baked 64x64 sheet, source=" .. tostring(source))
  if img then
    result(img:getWidth() == 64 and img:getHeight() == 64,
      "the portrait is 64x64, got " .. img:getWidth() .. "x" .. img:getHeight())
  end

  U.tap(game, "start")
  U.wait(30)
  result(Ui.pickMode, "START opened pick mode on OAK")
  U.shot(game, DIR .. "/import2_fame_02_oak_portrait.png")

  U.tap(game, "start")
  U.wait(20)
  U.tap(game, "a")
  U.wait(30)
  result(Ui.mode == "flavor", "A opened OAK's flavour page")
  local text = Ui.flavorText(PERSON.OAK, 0)
  result(type(text) == "string" and #text > 20,
    "the flavour text came from the baked pack, " .. tostring(text and #text) .. " chars")
  local loc, obj = Ui.iconDescription(PERSON.OAK, 0)
  result(type(loc) == "string" and type(obj) == "string",
    "the icon description box has the origin location and object, "
      .. tostring(loc) .. " / " .. tostring(obj))
  U.shot(game, DIR .. "/import2_fame_03_flavor_page.png")

  U.tap(game, "b")
  U.wait(20)
  U.tap(game, "select")
  U.wait(30)
  result(not Ui.isOpen(), "SELECT closed the Fame Checker")

  finish()
end
