local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_moveteach_deleter"

local HOUSE = "FR_FUCHSIA_CITY_HOUSE3"
local DELETER_X, DELETER_Y = 4, 4
local BULBASAUR = 1

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/moveteach_deleter.log", "a")
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
    say("PASS moveteach_deleter")
    love.event.quit(0)
  else
    say("FAIL moveteach_deleter failures=" .. failures)
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
  local Pokemon = require("src.core.game3.pokemon")
  local PartyMenu = require("src.ui.game3.party_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  session.party = {}
  Party.giveMon(session, BULBASAUR, 50)
  local mon = session.party[1]
  if not result(mon ~= nil, "a level 50 BULBASAUR joined the party") then return end

  local before = {}
  for i = 1, 4 do before[i] = Pokemon.moveIdAt(mon, i) end
  say("[driver] starting moveset: " .. table.concat({
    tostring(Pokemon.moveName(before[1])), tostring(Pokemon.moveName(before[2])),
    tostring(Pokemon.moveName(before[3])), tostring(Pokemon.moveName(before[4])),
  }, ", "))
  result(Pokemon.moveSlotCount(mon) == 4, "it knows four moves")

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end

  Map.load(nil, game, HOUSE, { x = DELETER_X + 1, y = DELETER_Y, facing = "left" })
  Player.cellX, Player.cellY = DELETER_X + 1, DELETER_Y
  Player.px, Player.py = (DELETER_X + 1) * 16, DELETER_Y * 16
  Player.targetX, Player.targetY = DELETER_X + 1, DELETER_Y
  Player.facing = "left"
  if game.session then
    game.session.x, game.session.y, game.session.facing = DELETER_X + 1, DELETER_Y, "left"
  end
  U.wait(90)
  U.shot(game, DIR .. "/moveteach_deleter_01_move_deleter.png")

  local function pumpUntil(cond, frames)
    for _ = 1, (frames or 300) do
      if cond() then return true end
      if Choice.active or (Message.isWaiting and Message.isWaiting()) then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    return cond() and true or false
  end

  say("[driver] talking to the MOVE DELETER")
  U.tap(game, "a")
  U.wait(24)
  local picker = pumpUntil(function()
    return PartyMenu.isOpen and PartyMenu.isOpen()
  end, 400)
  result(picker, "ChoosePartyMon opened the party picker")
  if not picker then
    U.shot(game, DIR .. "/moveteach_deleter_02_no_picker.png")
    return
  end
  U.shot(game, DIR .. "/moveteach_deleter_02_party_picker.png")

  U.tap(game, "a")
  U.wait(40)
  result(getVar(0x8004) == 0, "VAR_0x8004 = 0 for the lead slot, got " .. tostring(getVar(0x8004)))
  result(getVar(0x800D) == 4,
    "GetNumMovesSelectedMonHas put 4 in VAR_RESULT, got " .. tostring(getVar(0x800D)))

  local summary = pumpUntil(function() return SummaryMenu.isOpen() end, 400)
  result(summary, "SelectMoveDeleterMove opened the summary screen")
  if not summary then
    U.shot(game, DIR .. "/moveteach_deleter_03_no_summary.png")
    return
  end
  U.wait(24)
  U.shot(game, DIR .. "/moveteach_deleter_03_move_list.png")

  local doomed = before[2]
  say("[driver] deleting " .. tostring(Pokemon.moveName(doomed)))
  U.tap(game, "down")
  U.wait(12)
  U.tap(game, "a")
  U.wait(30)
  result(not SummaryMenu.isOpen(), "the summary screen closed on the pick")
  result(getVar(0x8005) == 1,
    "VAR_0x8005 is the chosen move slot, got " .. tostring(getVar(0x8005)))

  local asked = false
  for _ = 1, 60 do
    if Choice.active then asked = true break end
    U.wait(6)
  end
  result(asked, "the script asks whether that move should be forgotten")
  U.wait(12)
  U.shot(game, DIR .. "/moveteach_deleter_04_confirm.png")

  pumpUntil(function()
    return not Pokemon.knowsMove(mon, doomed)
  end, 400)
  result(not Pokemon.knowsMove(mon, doomed),
    "the mon forgot " .. tostring(Pokemon.moveName(doomed)))
  result(Pokemon.moveSlotCount(mon) == 3,
    "three moves are left, got " .. tostring(Pokemon.moveSlotCount(mon)))
  result(Pokemon.moveIdAt(mon, 1) == before[1] and Pokemon.moveIdAt(mon, 2) == before[3]
    and Pokemon.moveIdAt(mon, 3) == before[4] and Pokemon.moveIdAt(mon, 4) == nil,
    "the remaining moves shifted up into slots 1 to 3")

  pumpUntil(function()
    return not (Space.vm and Space.vm:isRunning())
  end, 400)
  U.wait(30)

  SummaryMenu.openMenu(session.party, 1, { session = session, page = 2 })
  U.wait(60)
  U.shot(game, DIR .. "/moveteach_deleter_05_new_moveset.png")
  say("[driver] final moveset: " .. table.concat({
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 1))),
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 2))),
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 3))),
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 4))),
  }, ", "))
  SummaryMenu.close()
  U.wait(20)
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL moveteach_deleter driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
