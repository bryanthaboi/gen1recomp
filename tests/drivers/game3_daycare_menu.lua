local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_daycare_menu"

-- pokefirered/data/maps/FourIsland_PokemonDayCare/scripts.inc:4
local DAYCARE = "FR_FOUR_ISLAND_POKEMON_DAY_CARE"
local WOMAN_X, WOMAN_Y = 2, 2
local ISLAND = "FR_FOUR_ISLAND"
local DAYCARE_MAN_ID = 1
local MAGIKARP = 129
local PIDGEY = 16
local VAR_MAP_SCENE_FOUR_ISLAND = 0x4086

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/daycare_menu.log", "a")
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
    say("PASS daycare_menu")
    love.event.quit(0)
  else
    say("FAIL daycare_menu failures=" .. failures)
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
  local Objects = require("src.core.game3.objects")
  local Party = require("src.core.game3.party")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Field = require("src.core.game3.field")
  local Flags = require("src.core.game3.scripting.flags")
  local Pokemon = require("src.core.game3.pokemon")
  local Daycare = require("src.core.game3.daycare")
  local DaycareMenu = require("src.ui.game3.daycare_menu")
  local StepEvents = require("src.core.game3.step_events")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  -- pokefirered/data/maps/FourIsland/scripts.inc:23 the rival has already left
  Flags.setVar(session.store or Space.store, nil, VAR_MAP_SCENE_FOUR_ISLAND, 1)

  session.party = {}
  Party.giveMon(session, MAGIKARP, 5)
  Party.giveMon(session, MAGIKARP, 5)
  Party.giveMon(session, PIDGEY, 9)
  session.money = 3000
  -- pokefirered/src/pokemon.c:2733 GetGenderFromSpeciesAndPersonality
  local mother, father = session.party[1], session.party[2]
  mother.personality = mother.personality - (mother.personality % 256)
  father.personality = father.personality - (father.personality % 256) + 254
  mother.gender = Pokemon.gender(MAGIKARP, mother.personality)
  father.gender = Pokemon.gender(MAGIKARP, father.personality)
  -- pokefirered/src/daycare.c:1321 different trainers score higher
  father.otId = (tonumber(mother.otId) or 0) + 1111
  result(mother.gender == "F" and father.gender == "M",
    "a MAGIKARP pair, one of each gender: " .. tostring(mother.gender) ..
    "/" .. tostring(father.gender))

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

  local function answer(which)
    for _ = 1, 10 do
      if Choice.cursor == which then break end
      U.tap(game, which == 1 and "up" or "down")
      U.wait(6)
    end
    U.tap(game, "a")
    U.wait(20)
  end

  local function waitIdle()
    for _ = 1, 600 do
      if Choice.active then return false end
      if not scriptRunning() and not (Message.isOpen and Message.isOpen()) then
        return true
      end
      if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
      U.wait(5)
    end
    return false
  end

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
  local function walkUntil(limit, done)
    local idx, walked, stuck = 1, 0, 0
    while walked < limit and stuck < 12 do
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
      if done and done(walked) then return walked end
      if StepEvents.busy() then
        for _ = 1, 600 do
          if not StepEvents.busy() then break end
          if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
          U.wait(5)
        end
      end
    end
    return walked
  end

  local function talkToWoman()
    goTo(DAYCARE, WOMAN_X, WOMAN_Y + 1, "up")
    U.tap(game, "a")
    U.wait(20)
  end

  local function boardOne(label, slot)
    result(pumpUntil(function() return Choice.active end, 90),
      "the day-care woman asked: " .. label)
    answer(1)
    if not result(pumpUntil(function() return PartyMenu.isOpen and PartyMenu.isOpen() end, 180),
      "ChooseSendDaycareMon opened the party picker for " .. label) then
      return false
    end
    for _ = 2, (slot or 1) do
      U.tap(game, "down")
      U.wait(8)
    end
    U.tap(game, "a")
    U.wait(30)
    return true
  end

  talkToWoman()
  say("[driver] boarding both MAGIKARP")
  boardOne("the first MAGIKARP")
  result(pumpUntil(function() return Choice.active end, 240),
    "and offered to raise one more")
  boardOne("the second MAGIKARP")
  waitIdle()

  local dc = Daycare.stateOf(session)
  if not result(Daycare.count(dc) == 2, "both MAGIKARP are boarded, got " ..
    tostring(Daycare.count(dc))) then
    return finish()
  end

  say("[driver] walking until both boarders gain a level")
  goTo(DAYCARE, WOMAN_X + 1, WOMAN_Y + 2, "down")
  Field.unlock()
  U.wait(20)
  local walked = walkUntil(400, function()
    return Daycare.levelsGained(Daycare.mon(dc, 1), dc.steps[1]) >= 1
      and Daycare.levelsGained(Daycare.mon(dc, 2), dc.steps[2]) >= 1
  end)
  say("[driver] walked " .. tostring(walked) .. " grid steps")
  result(Daycare.levelsGained(Daycare.mon(dc, 2), dc.steps[2]) >= 1,
    "slot 2 gained a level, now Lv" ..
    tostring(Daycare.levelAfterSteps(Daycare.mon(dc, 2), dc.steps[2])))

  say("[driver] asking for a mon back, which opens the level menu")
  talkToWoman()
  result(pumpUntil(function()
    return Choice.active and page():find("take your POKéMON back") ~= nil
  end, 300), "she asks: " .. page())
  answer(1)
  if not result(pumpUntil(function()
    return DaycareMenu.isOpen and DaycareMenu.isOpen()
  end, 240), "ShowDaycareLevelMenu put the level menu on screen") then
    return finish()
  end
  U.wait(30)
  U.shot(game, DIR .. "/daycare_menu_01_level_menu.png")
  local rows = DaycareMenu.rowList
  result(rows and #rows == 3, "the menu lists both mons plus EXIT")
  result(rows and rows[1].level == "Lv" ..
    tostring(Daycare.levelAfterSteps(Daycare.mon(dc, 1), dc.steps[1])),
    "row 1 shows the level the steps earned: " .. tostring(rows and rows[1].level))
  result(rows and rows[1].symbol == "♀" and rows[2].symbol == "♂",
    "the rows carry the gender symbols: " .. tostring(rows and rows[1].symbol) ..
    tostring(rows and rows[2].symbol))
  result(rows and rows[3].text == "EXIT", "and the third row is EXIT")

  U.tap(game, "down")
  U.wait(10)
  result(DaycareMenu.cursor == 2, "the cursor moved to the second mon")
  U.tap(game, "a")
  U.wait(20)
  result(pumpUntil(function()
    return Choice.active and page():find("it will cost") ~= nil
  end, 240), "the pick leads to the cost prompt: " .. page())
  U.shot(game, DIR .. "/daycare_menu_02_cost.png")
  local moneyBefore = tonumber(session.money) or 0
  answer(1)
  result(pumpUntil(function()
    return page():find("Here's your POKéMON") ~= nil
  end, 600), "she hands it over: " .. page())
  waitIdle()
  -- pokefirered/data/maps/FourIsland_PokemonDayCare/scripts.inc:132
  result(pumpUntil(function()
    return Choice.active and page():find("take back the other one") ~= nil
  end, 300), "she asks about the other one: " .. page())
  answer(2)
  waitIdle()

  local back, backSlot
  for i, mon in ipairs(session.party) do
    if mon == father then back, backSlot = mon, i end
  end
  result(back ~= nil, "the second MAGIKARP is back in the party")
  result(back and back.level == 6, "it came back at level 6, got " ..
    tostring(back and back.level))
  result((moneyBefore - (tonumber(session.money) or 0)) == 200,
    "200 was paid for the one level, paid " ..
    tostring(moneyBefore - (tonumber(session.money) or 0)))
  result(Daycare.count(dc) == 1, "one mon is left in the day care, got " ..
    tostring(Daycare.count(dc)))

  say("[driver] boarding it again so the pair can produce an egg")
  talkToWoman()
  result(pumpUntil(function()
    return Choice.active and page():find("more POKéMON for you") ~= nil
  end, 300), "she offers to raise one more: " .. page())
  boardOne("the returned MAGIKARP", backSlot)
  waitIdle()
  result(Daycare.mon(dc, 2) == back, "the MAGIKARP went back in, not the PIDGEY")
  if not result(Daycare.count(dc) == 2, "both are boarded again, got " ..
    tostring(Daycare.count(dc))) then
    return finish()
  end

  say("[driver] walking until the day care produces an egg")
  goTo(DAYCARE, WOMAN_X + 1, WOMAN_Y + 2, "down")
  Field.unlock()
  U.wait(20)
  walked = walkUntil(256 * 4, function()
    return Daycare.isEggPending(dc)
  end)
  say("[driver] walked " .. tostring(walked) .. " grid steps")
  if not result(Daycare.isEggPending(dc), "an egg is waiting at the day care") then
    return finish()
  end

  -- pokefirered/data/maps/FourIsland/scripts.inc:97 goto_if_ne VAR_RESULT, PARTY_SIZE
  while #session.party < 6 do
    Party.giveMon(session, PIDGEY, 9)
  end
  result(#session.party == 6, "the party is full, got " .. tostring(#session.party))

  local function talkToDaycareMan()
    goTo(ISLAND, 16, 17, "up")
    -- pokefirered/data/maps/FourIsland/scripts.inc:18 setobjectxyperm on transition
    for _ = 1, 3 do
      local man = Objects.find(DAYCARE_MAN_ID)
      if not man then return false end
      if man.cellX == Player.cellX and man.cellY == Player.cellY - 1 then return true end
      goTo(ISLAND, man.cellX, man.cellY + 1, "up")
    end
    return false
  end

  say("[driver] asking for the egg with no room for it")
  if not result(talkToDaycareMan(), "the day-care man moved out to meet the player") then
    return finish()
  end
  result(pumpUntil(function() return Choice.active end, 240),
    "he offers the egg: " .. page())
  answer(1)
  result(pumpUntil(function()
    return page():find("no room for it") ~= nil and Message.isWaiting and Message.isWaiting()
  end, 240), "he refuses to hand it over: " .. page())
  U.shot(game, DIR .. "/daycare_menu_03_no_room.png")
  waitIdle()
  local carried = 0
  for _, mon in ipairs(session.party) do
    if mon.isEgg then carried = carried + 1 end
  end
  result(carried == 0, "no egg entered the full party, got " .. tostring(carried))
  result(Daycare.isEggPending(dc), "and the egg is still waiting for the player")

  say("[driver] making room and collecting the egg")
  -- pokefirered/include/constants/songs.h:264 MUS_LEVEL_UP
  local MUS_LEVEL_UP = 257
  local Audio = require("src.core.game3.audio")
  local heard = {}
  local realFanfare = Audio.playFanfare
  Audio.playFanfare = function(id, ...)
    heard[#heard + 1] = tonumber(id) or id
    return realFanfare(id, ...)
  end
  table.remove(session.party)
  result(#session.party == 5, "one mon left behind, party is " .. tostring(#session.party))
  if not result(talkToDaycareMan(), "back to the day-care man") then return finish() end
  result(pumpUntil(function() return Choice.active end, 240),
    "he offers the egg again: " .. page())
  answer(1)
  result(pumpUntil(function()
    return page():find("received the EGG") ~= nil and Message.isWaiting and Message.isWaiting()
  end, 300), "the hand-off scene plays: " .. page())
  U.tap(game, "a")
  result(pumpUntil(function()
    return page():find("Take good care of it") ~= nil
      and Message.isWaiting and Message.isWaiting()
  end, 300), "and he asks: " .. page())
  U.wait(30)
  U.shot(game, DIR .. "/daycare_menu_04_take_care.png")
  local rangFanfare = false
  for _, id in ipairs(heard) do
    if id == MUS_LEVEL_UP then rangFanfare = true end
  end
  -- pokefirered/data/maps/FourIsland/scripts.inc:106 playfanfare MUS_LEVEL_UP
  result(rangFanfare, "the hand-off played MUS_LEVEL_UP, heard " ..
    tostring(#heard) .. " fanfares")
  Audio.playFanfare = realFanfare
  waitIdle()

  local egg
  for _, mon in ipairs(session.party) do
    if mon.isEgg then egg = mon end
  end
  result(egg ~= nil, "the EGG is in the party now")
  result(egg and egg.species == MAGIKARP,
    "two MAGIKARP made a MAGIKARP egg, got " .. tostring(egg and egg.species))
  result(not Daycare.isEggPending(dc), "the day care has nothing pending any more")

  finish()
end
