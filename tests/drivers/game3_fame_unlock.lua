local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_fame_unlock"

local GYM = "FR_PEWTER_CITY_GYM"
-- pokefirered/data/maps/PewterCity_Gym/map.json:20 BROCK is the first object event
local BROCK_LOCAL_ID = 1
-- pokefirered/include/constants/flags.h:1364
local FLAG_BADGE01_GET = 0x820
-- pokefirered/include/constants/opponents.h:420
local TRAINER_LEADER_BROCK = 414
-- pokefirered/include/constants/moves.h:61
local MOVE_SURF = 57
-- pokefirered/include/constants/items.h:435
local ITEM_FAME_CHECKER = 363

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    if fails == 0 then
      print("PASS fame_unlock")
      love.event.quit(0)
    else
      print("FAIL fame_unlock failures=" .. fails)
      love.event.quit(1)
    end
  end

  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Objects = require("src.core.game3.objects")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local FameChecker = require("src.core.game3.fame_checker")

  local PERSON, PICK = FameChecker.PERSON, FameChecker.PICKSTATE

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getFlag(id)
    return Flags.getFlag(Space.store, ctx(), id) and true or false
  end

  session.party = {}
  Party.giveMon(session, 9, 60)
  Party.giveMon(session, 3, 60)
  for _, mon in ipairs(session.party) do
    mon.moves = { MOVE_SURF, 0, 0, 0 }
    mon.pp = { 30, 0, 0, 0 }
  end

  local function placeAt(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(90)
  end

  result(FameChecker.pickState(session, PERSON.BROCK) == PICK.NO_DRAW,
    "BROCK is not drawn in the Fame Checker on a new game")
  result(FameChecker.pickState(session, PERSON.OAK) == PICK.COLORED,
    "OAK starts coloured, as ResetFameChecker leaves him")
  result(FameChecker.flavorTextFlags(session, PERSON.BROCK) == 0,
    "BROCK has no flavour text on a new game")

  placeAt(GYM, 5, 12, "up")
  local brock = Objects.find(BROCK_LOCAL_ID)
  if not result(brock ~= nil, "BROCK is on the Pewter Gym map") then return finish() end
  print(string.format("[driver] BROCK at (%d,%d)", brock.cellX, brock.cellY))

  placeAt(GYM, brock.cellX, brock.cellY + 1, "up")
  U.shot(game, DIR .. "/fame_unlock_01_facing_brock.png")

  local lastTap = 0
  local f = 0
  local function pumpText()
    f = f + 1
    if Ui and Ui.dialogPending and Ui.dialogPending() and not (Anim and Anim.busy and Anim.busy())
        and f - lastTap >= 14 then
      lastTap = f
      U.tap(game, "a")
      return true
    end
    return false
  end

  U.tap(game, "a")
  U.wait(10)
  for _ = 1, 1200 do
    if Battle.isActive() then break end
    if Message and Message.isOpen and Message.isOpen() then
      U.tap(game, "a")
      U.wait(6)
    else
      U.wait(2)
    end
  end

  -- pokefirered/data/maps/PewterCity_Gym/scripts.inc:5
  result(FameChecker.pickState(session, PERSON.BROCK) == PICK.COLORED,
    "talking to BROCK ran famechecker FCPICKSTATE_COLORED, pickState="
      .. tostring(FameChecker.pickState(session, PERSON.BROCK)))
  result(FameChecker.flavorTextFlags(session, PERSON.BROCK) == 0,
    "no flavour text yet, only the picture is unlocked")

  if not result(Battle.isActive(), "Brock's trainerbattle_single started") then
    U.shot(game, DIR .. "/fame_unlock_02_no_battle.png")
    return finish()
  end
  local st = Battle.getState()
  result(st ~= nil and st.trainerId == TRAINER_LEADER_BROCK,
    "fighting TRAINER_LEADER_BROCK (" .. tostring(st and st.trainerId) .. ")")

  local function atCommand()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local turns, spun = 0, 0
  for _ = 1, 30000 do
    if not Battle.isActive() then break end
    spun = spun + 1
    if spun % 900 == 0 then
      print(string.format("[driver] battle wait phase=%s mode=%s turns=%d",
        tostring(Battle._phase), tostring(Ui._mode), turns))
    end
    if atCommand() then
      turns = turns + 1
      U.tap(game, "a")
      U.wait(14)
      U.tap(game, "a")
      U.wait(14)
    elseif Ui.choiceActive and Ui.choiceActive() then
      -- pokefirered/src/battle_message.c:371 sText_EnemyAboutToSwitchPkmn
      U.tap(game, "b")
      U.wait(14)
    elseif Message and Message.isOpen and Message.isOpen() and not Anim.busy() then
      U.tap(game, "a")
      U.wait(10)
    elseif not pumpText() then
      U.wait(1)
    end
  end
  print("[driver] battle turns issued: " .. tostring(turns))
  result(not Battle.isActive(), "the gym battle ended")

  local textShot = false
  for _ = 1, 3000 do
    local running = Space.vm and Space.vm:isRunning()
    local open = Message and Message.isOpen and Message.isOpen()
    if not running and not open then break end
    if open and not textShot and getFlag(FLAG_BADGE01_GET)
        and FameChecker.hasFlavorText(session, PERSON.BROCK, 1) then
      textShot = true
      U.wait(30)
      U.shot(game, DIR .. "/fame_unlock_02_brock_unlocked.png")
    end
    if open then U.tap(game, "a") end
    U.wait(6)
  end
  U.wait(60)
  result(textShot, "shot the post-battle page that carries famechecker FAMECHECKER_BROCK, 1")

  if not result(getFlag(FLAG_BADGE01_GET), "the BOULDERBADGE branch ran, so BROCK was beaten") then
    U.shot(game, DIR .. "/fame_unlock_03_lost.png")
    return finish()
  end

  -- pokefirered/data/maps/PewterCity_Gym/scripts.inc:13
  result(FameChecker.hasFlavorText(session, PERSON.BROCK, 1),
    "famechecker FAMECHECKER_BROCK, 1 unlocked flavour text slot 1")
  result(FameChecker.flavorTextFlags(session, PERSON.BROCK) == 2,
    "only slot 1 is unlocked, flags="
      .. tostring(FameChecker.flavorTextFlags(session, PERSON.BROCK)))
  -- pokefirered/src/fame_checker.c:1238
  result(FameChecker.pickState(session, PERSON.BROCK) == PICK.COLORED,
    "the SILHOUETTE write inside the special did not demote a coloured BROCK")
  result(FameChecker.hasUnlockedAllFlavorTexts(session, PERSON.BROCK) == false,
    "BROCK is not fully unlocked from one gym win")

  local list = FameChecker.unlockedPersons(session)
  local names = {}
  for i, p in ipairs(list) do names[i] = tostring(p) end
  print("[driver] unlocked persons: " .. table.concat(names, ","))
  result(#list == 2 and list[1] == PERSON.OAK and list[2] == PERSON.BROCK,
    "the Fame Checker list is OAK then BROCK")

  -- pokefirered/src/item_use.c:680 FieldUseFunc_FameChecker
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local Ui = require("src.ui.game3.fame_checker")
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_FAME_CHECKER, 1)
  local usedOk, usedKind = ItemUse.useField(session, session.bag, ITEM_FAME_CHECKER)
  U.wait(30)
  if not result(usedOk == true and usedKind == "fame_checker" and Ui.isOpen(),
    "the FAME CHECKER opened the screen, kind=" .. tostring(usedKind)) then
    return finish()
  end
  U.tap(game, "down")
  U.wait(20)
  result(Ui.selectedPerson() == PERSON.BROCK, "the cursor is on BROCK's entry")
  local icons = Ui.icons(PERSON.BROCK)
  result(icons[1].unlocked and not icons[0].unlocked,
    "BROCK's entry shows panel 1 unlocked and the rest locked")
  U.tap(game, "start")
  U.wait(30)
  result(Ui.pickMode, "START shows BROCK's coloured picture")
  U.shot(game, DIR .. "/fame_unlock_03_brock_entry.png")
  U.tap(game, "b")
  U.wait(20)
  U.tap(game, "select")
  U.wait(30)
  result(not Ui.isOpen(), "SELECT closed the Fame Checker")

  finish()
end
