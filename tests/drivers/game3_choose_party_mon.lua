local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_choose_party_mon"

-- pokefirered/data/maps/LavenderTown_House2/scripts.inc:1
local HOUSE = "FR_LAVENDER_TOWN_HOUSE2"
local RATER_X, RATER_Y = 4, 4

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/choose_party_mon.log", "a")
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
    say("PASS choose_party_mon")
    love.event.quit(0)
  else
    say("FAIL choose_party_mon failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Message = require("src.ui.game3.message")
  local Std = require("src.core.game3.scripting.stdscripts")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  session.party = {}
  Party.giveMon(session, 1, 12)
  Party.giveMon(session, 4, 12)
  session.party[1].otId = session.trainerId
  session.party[2].otId = (tonumber(session.trainerId) or 0) + 1
  result(#session.party == 2, "party has two mons")

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end

  local function goTo(mapId, x, y, facing)
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

  local Choice = require("src.ui.game3.choice")

  local function pumpMessage(frames)
    for _ = 1, frames do
      if PartyMenu.isOpen and PartyMenu.isOpen() then return true end
      if Choice.active or (Message.isWaiting and Message.isWaiting()) then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    return PartyMenu.isOpen and PartyMenu.isOpen() or false
  end

  goTo(HOUSE, RATER_X, RATER_Y + 1, "up")
  U.shot(game, DIR .. "/choose_party_mon_01_name_rater.png")

  say("[driver] talking to the Name Rater")
  U.tap(game, "a")
  U.wait(30)
  local opened = pumpMessage(90)
  result(opened, "ChoosePartyMon opened the party picker")
  result(not require("src.ui.game3.naming").isOpen(),
    "ChoosePartyMon did not open the naming keyboard")
  if not opened then
    U.shot(game, DIR .. "/choose_party_mon_02_no_picker.png")
    return
  end
  U.shot(game, DIR .. "/choose_party_mon_02_picker.png")

  say("[driver] choosing the traded mon in slot 2")
  U.tap(game, "down")
  U.wait(12)
  U.tap(game, "a")
  U.wait(40)
  result(getVar(0x8004) == 1,
    "VAR_0x8004 = 1 for slot 2, got " .. tostring(getVar(0x8004)))
  result(not PartyMenu.isOpen(), "the picker closed on A")

  for _ = 1, 40 do
    if Message.isOpen() then break end
    U.wait(6)
  end
  local tradedText = Message.currentPage() or ""
  say("[driver] traded-mon page: " .. tostring(tradedText))
  result(Message.isOpen(), "the Name Rater answered after the pick")
  U.shot(game, DIR .. "/choose_party_mon_03_traded_mon.png")

  -- pokefirered/data/maps/LavenderTown_House2/scripts.inc:29
  local rslt = getVar(0x800D)
  result(rslt == 1, "IsMonOTIDNotPlayers set VAR_RESULT = TRUE for the traded mon, got "
    .. tostring(rslt))

  for _ = 1, 60 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
    U.wait(8)
  end
  U.wait(30)

  say("[driver] second pass: choosing the player's own mon in slot 1")
  U.tap(game, "a")
  U.wait(30)
  local opened2 = pumpMessage(90)
  result(opened2, "the picker opened again on a second visit")
  if opened2 then
    U.tap(game, "a")
    U.wait(40)
    result(getVar(0x8004) == 0,
      "VAR_0x8004 = 0 for slot 1, got " .. tostring(getVar(0x8004)))
    for _ = 1, 40 do
      if Message.isOpen() then break end
      U.wait(6)
    end
    U.shot(game, DIR .. "/choose_party_mon_04_own_mon.png")
    result(getVar(0x800D) ~= nil, "the script kept running past the OT check")
  end

  say(string.format("[driver] ChoosePartyMon id = 0x%X, ChangePokemonNickname id = 0x%X",
    Std.SPECIAL.ChoosePartyMon, Std.SPECIAL.ChangePokemonNickname))
  result(Std.SPECIAL.ChoosePartyMon == 0x9F, "ChoosePartyMon is special 0x9F")
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL choose_party_mon driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
