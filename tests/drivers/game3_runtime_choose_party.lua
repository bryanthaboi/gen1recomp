local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_runtime_choose_party"

-- pokefirered/data/maps/LavenderTown_House2/scripts.inc:12
local HOUSE = "FR_LAVENDER_TOWN_HOUSE2"
local RATER_X, RATER_Y = 4, 4
-- pokefirered/data/maps/TrainerTower_Lobby/scripts.inc:1
local LOBBY = "FR_TRAINER_TOWER_LOBBY"

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/runtime_choose_party.log", "a")
  if fh then
    fh:write(line, "\n")
    fh:close()
  end
end

local function result(ok, label)
  say((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    say("PASS runtime_choose_party")
    love.event.quit(0)
  else
    say("FAIL runtime_choose_party failures=" .. failures)
    love.event.quit(1)
  end
end

local function run(game)
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
  local Party = require("src.core.game3.party")
  local Objects = require("src.core.game3.objects")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Naming = require("src.ui.game3.naming")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  session.party = {}
  Party.giveMon(session, 1, 12)
  Party.giveMon(session, 4, 12)
  session.party[1].otId = session.trainerId
  session.party[2].otId = (tonumber(session.trainerId) or 0) + 1

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    U.wait(90)
  end

  local function pumpToPicker(frames)
    for _ = 1, frames do
      if PartyMenu.isOpen() then return true end
      if Choice.active or (Message.isWaiting and Message.isWaiting()) then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    return PartyMenu.isOpen()
  end

  goTo(HOUSE, RATER_X, RATER_Y + 1, "up")
  U.shot(game, DIR .. "/runtime_choose_party_01_name_rater.png")

  local seam = Space.vm and Space.vm.adapters and Space.vm.adapters.chooseParty
  result(type(seam) == "function",
    "the live field adapter carries the chooseParty seam")

  say("[driver] talking to the Name Rater")
  U.tap(game, "a")
  U.wait(30)
  local opened = pumpToPicker(90)
  result(opened, "ChoosePartyMon opened the party picker")
  result(not Naming.isOpen(), "and not the naming keyboard")
  if not opened then
    U.shot(game, DIR .. "/runtime_choose_party_02_no_picker.png")
    return
  end
  result(PartyMenu.mode == "choose",
    "the picker is in choose mode, got " .. tostring(PartyMenu.mode))
  U.shot(game, DIR .. "/runtime_choose_party_02_picker.png")

  say("[driver] picking slot 2")
  U.tap(game, "down")
  U.wait(12)
  U.tap(game, "a")
  U.wait(60)
  result(not PartyMenu.isOpen(), "the picker closed on A")
  result(getVar(0x8004) == 1,
    "VAR_0x8004 = 1 for slot 2, got " .. tostring(getVar(0x8004)))
  for _ = 1, 40 do
    if Message.isOpen() then break end
    U.wait(6)
  end
  result(Message.isOpen(), "the Name Rater answered the pick")
  U.shot(game, DIR .. "/runtime_choose_party_03_after_pick.png")

  local function clearDialogs(frames)
    for _ = 1, frames do
      local busy = Message.isOpen() or Choice.active
        or (Space.vm and Space.vm:isRunning())
      if not busy then return true end
      U.tap(game, "a")
      U.wait(8)
    end
    return false
  end
  clearDialogs(120)
  U.wait(20)

  say("[driver] Trainer Tower lobby: ON_RETURN_TO_FIELD on a menu close")
  goTo(LOBBY, 9, 10, "down")
  local idle = clearDialogs(120)
  say(string.format("[driver] lobby idle=%s message=%s locked=%s",
    tostring(idle), tostring(Message.isOpen()),
    tostring(require("src.core.game3.field").locked)))
  local staff = Objects.find(3)
  result(staff ~= nil and staff.visible == true, "the lobby receptionist is on the map")
  -- pokefirered/data/maps/TrainerTower_Lobby/scripts.inc:21
  Objects.removeObject(3)
  U.wait(20)
  local gone = Objects.find(3)
  result(gone == nil or gone.visible == false, "removeobject cleared her desk")
  U.shot(game, DIR .. "/runtime_choose_party_04_desk_empty.png")

  U.tap(game, "start")
  U.wait(30)
  result(StartMenu.isOpen(), "the START menu opened")
  local duringMenu = Objects.find(3)
  result(duringMenu == nil or duringMenu.visible == false,
    "opening the menu did not run the map scripts")
  -- pokefirered/src/start_menu.c:1003
  U.tap(game, "b")
  U.wait(60)
  result(not StartMenu.isOpen(), "the START menu closed")
  local afterStart = Objects.find(3)
  result(afterStart == nil or afterStart.visible == false,
    "the START menu is an overlay: closing it alone left the desk empty")
  U.shot(game, DIR .. "/runtime_choose_party_05_start_menu_only.png")

  U.tap(game, "start")
  U.wait(30)
  local bagAt = nil
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "bag" then bagAt = i end
  end
  result(bagAt ~= nil, "the START menu lists BAG")
  for _ = 2, (bagAt or 1) do
    U.tap(game, "down")
    U.wait(8)
  end
  U.tap(game, "a")
  U.wait(60)
  local BagMenu = require("src.ui.game3.bag_menu")
  result(BagMenu.isOpen(), "the BAG opened over the START menu")
  U.shot(game, DIR .. "/runtime_choose_party_06_bag.png")
  local duringBag = Objects.find(3)
  result(duringBag == nil or duringBag.visible == false,
    "the desk is still empty while the BAG is up")

  -- pokefirered/src/start_menu.c:492
  U.tap(game, "b")
  U.wait(60)
  result(not BagMenu.isOpen(), "the BAG closed")
  local back = Objects.find(3)
  result(back ~= nil and back.visible == true,
    "closing it re-ran ON_RETURN_TO_FIELD and the receptionist is back")
  U.tap(game, "b")
  U.wait(30)
  U.shot(game, DIR .. "/runtime_choose_party_07_desk_restored.png")

  result(not (Space.vm and Space.vm:isRunning()),
    "the field is idle again, no script left running")
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL runtime_choose_party driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
