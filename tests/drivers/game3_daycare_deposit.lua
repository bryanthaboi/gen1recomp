local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_daycare_deposit"

-- pokefirered/data/scripts/day_care.inc:1 Route5_PokemonDayCare_EventScript_DaycareMan
local DAYCARE = "FR_ROUTE_5_POKEMON_DAY_CARE"
local MAN_X, MAN_Y = 4, 4

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/daycare_deposit.log", "a")
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
    say("PASS daycare_deposit")
    love.event.quit(0)
  else
    say("FAIL daycare_deposit failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Party = require("src.core.game3.party")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Field = require("src.core.game3.field")
  local Daycare = require("src.core.game3.daycare")
  local SummaryData = require("src.core.game3.summary_data")
  local Experience = require("src.core.game3.battle.experience")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, 19, 5)
  Party.giveMon(session, 16, 9)
  session.money = 3000

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

  local function page()
    return tostring((Message.currentPage and Message.currentPage()) or "")
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

  say("[driver] handing the level 5 RATTATA to the day-care man")
  result(pumpUntil(function() return Choice.active end, 60),
    "the day-care man asked whether to raise a POKeMON")
  answerYes()
  result(pumpUntil(function() return PartyMenu.isOpen and PartyMenu.isOpen() end, 120),
    "ChooseSendDaycareMon opened the party picker")
  U.shot(game, DIR .. "/daycare_deposit_01_choose_mon.png")
  U.tap(game, "a")
  U.wait(30)
  waitIdle()

  local r5 = Daycare.route5Of(session)
  if not result(r5 and r5.mon ~= nil, "PutMonInRoute5Daycare stored the mon") then
    return finish()
  end
  result(r5.steps == 0, "it starts with no banked steps, got " .. tostring(r5.steps))

  Field.unlock()
  U.wait(20)

  -- pokefirered/src/daycare.c:551 GetLevelAfterDaycareSteps
  local growth = Experience.growthRate(r5.mon)
  local needed = SummaryData.expForLevel(growth, 6) - (tonumber(r5.mon.exp) or 0)
  say("[driver] walking the " .. tostring(needed) .. " steps that buy one level")

  local function tryStep(dir)
    local x, y = Player.cellX, Player.cellY
    U.hold(game, dir, 8)
    for _ = 1, 60 do
      if not Player.moving then break end
      U.wait(1)
    end
    U.wait(2)
    return Player.cellX ~= x or Player.cellY ~= y
  end
  local DIRS = { "left", "right", "up", "down" }
  local idx, walked, stuck = 1, 0, 0
  while walked < needed and stuck < 12 do
    if Collision.warpAt and Collision.warpAt(Player.cellX, Player.cellY) then
      break
    end
    if tryStep(DIRS[idx]) then
      walked = walked + 1
      stuck = 0
      idx = (idx % 2 == 1) and idx + 1 or idx - 1
    else
      stuck = stuck + 1
      idx = (idx <= 2) and 3 or 1
    end
  end
  say("[driver] walked " .. tostring(walked) .. " grid steps")
  result(walked == needed, "the room let the player walk all " .. tostring(needed) .. " steps")
  result(r5.steps == walked,
    "every step fed the day care: banked " .. tostring(r5.steps) .. " of " .. tostring(walked))
  result(Daycare.levelsGained(r5.mon, r5.steps) == 1,
    "GetNumLevelsGainedFromSteps is 1, got " .. tostring(Daycare.levelsGained(r5.mon, r5.steps)))

  say("[driver] coming back for it")
  goTo(DAYCARE, MAN_X, MAN_Y + 1, "up")
  result(pumpUntil(function()
    return page():find("grown by") ~= nil and Message.isWaiting and Message.isWaiting()
  end, 90), "the day-care man reports the level it gained")
  U.shot(game, DIR .. "/daycare_deposit_02_levels.png")
  result(page():find("by 1") ~= nil, "STR_VAR_2 in the message is 1: " .. page())

  result(pumpUntil(function() return Choice.active end, 120),
    "and then quotes the price")
  U.shot(game, DIR .. "/daycare_deposit_03_price.png")
  result(page():find("200") ~= nil,
    "the price is 100 + 100 * 1: " .. page())

  local moneyBefore = tonumber(session.money) or 0
  answerYes()
  waitIdle()

  r5 = Daycare.route5Of(session)
  result(r5.mon == nil, "the Route 5 slot is empty again")
  local back = session.party[#session.party]
  result(back and back.species == 19, "the RATTATA is back in the party")
  result(back and back.level == 6, "it came back at level 6, got " .. tostring(back and back.level))
  -- pokefirered/src/daycare.c:578 GetDaycareCostForSelectedMon
  result((moneyBefore - (tonumber(session.money) or 0)) == 200,
    "200 was paid for the one level, paid " ..
    tostring(moneyBefore - (tonumber(session.money) or 0)))

  finish()
end
