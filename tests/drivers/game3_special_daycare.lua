local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_special_daycare"

-- pokefirered/data/scripts/day_care.inc:1 Route5_PokemonDayCare_EventScript_DaycareMan
local DAYCARE = "FR_ROUTE_5_POKEMON_DAY_CARE"
local MAN_X, MAN_Y = 4, 4

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/special_daycare.log", "a")
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
    say("PASS special_daycare")
    love.event.quit(0)
  else
    say("FAIL special_daycare failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
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
  local Choice = require("src.ui.game3.choice")
  local Daycare = require("src.core.game3.scripting.natives_daycare")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, 19, 5)
  Party.giveMon(session, 16, 9)
  session.money = 3000
  result(#session.party == 2, "two mons in the party, so the daycare man will take one")

  local function ctx() return Space.vm and Space.vm.ctx end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(30)
    local Preview = package.loaded["src.ui.game3.map_preview_screen"]
    for _ = 1, 240 do
      if not (Preview and Preview.isActive and Preview.isActive()) then break end
      U.wait(5)
    end
    U.wait(60)
  end

  local function scriptRunning()
    return Space.vm and Space.vm.isRunning and Space.vm:isRunning() or false
  end

  local function pumpUntil(pred, frames)
    for _ = 1, frames do
      if pred() then return true end
      if Choice.active then
        return false
      elseif Message.isWaiting and Message.isWaiting() then
        U.tap(game, "a")
      elseif not scriptRunning() then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    return pred()
  end

  local function answerYes()
    for _ = 1, 10 do
      if Choice.cursor == 1 then break end
      U.tap(game, "up")
      U.wait(6)
    end
    U.tap(game, "a")
    U.wait(20)
  end

  local function waitIdle()
    for _ = 1, 400 do
      if not scriptRunning() and not Choice.active
        and not (Message.isOpen and Message.isOpen()) then
        return true
      end
      if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
      U.wait(5)
    end
    return false
  end

  goTo(DAYCARE, MAN_X, MAN_Y + 1, "up")

  say("[driver] talking to the Route 5 day-care man")
  result(pumpUntil(function() return Choice.active end, 60),
    "the day-care man asked whether to raise a POKeMON")
  U.shot(game, DIR .. "/special_daycare_01_offer.png")
  answerYes()

  result(pumpUntil(function() return PartyMenu.isOpen and PartyMenu.isOpen() end, 120),
    "ChooseSendDaycareMon opened the party picker")
  U.shot(game, DIR .. "/special_daycare_02_choose_mon.png")
  U.tap(game, "a")
  U.wait(30)
  waitIdle()

  local r5 = Daycare.route5Of(session)
  result(r5 and r5.mon ~= nil, "PutMonInRoute5Daycare stored the mon")
  result(#session.party == 1, "the party is down to one mon, got " .. tostring(#session.party))
  result(r5 and r5.mon and tonumber(r5.mon.level) == 5,
    "the stored mon is the level 5 RATTATA, got " .. tostring(r5 and r5.mon and r5.mon.level))
  result(Daycare.count(Daycare.stateOf(session)) == 0,
    "the Four Island daycare is untouched by a Route 5 deposit")

  say("[driver] coming back for it")
  local Field = require("src.core.game3.field")
  Field.unlock()
  U.wait(20)
  goTo(DAYCARE, MAN_X, MAN_Y + 1, "up")

  result(pumpUntil(function() return Choice.active end, 90),
    "the second visit goes down the CheckOnMon branch and quotes a price")
  U.shot(game, DIR .. "/special_daycare_03_price.png")
  local moneyBefore = tonumber(session.money) or 0
  answerYes()
  waitIdle()

  r5 = Daycare.route5Of(session)
  result(r5 and r5.mon == nil, "the Route 5 slot is empty again")
  result(#session.party == 2, "the mon is back in the party, got " .. tostring(#session.party))
  -- pokefirered/src/daycare.c:578 GetDaycareCostForSelectedMon
  result((moneyBefore - (tonumber(session.money) or 0)) == 100,
    "the flat 100 was paid for a stay that gained no levels, paid " ..
    tostring(moneyBefore - (tonumber(session.money) or 0)))
  U.log("daycare steps never accumulate yet: DaycareStep is round 2's step_events hunk")

  finish()
end
