local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_daycare_egg"

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
  local fh = io.open(DIR .. "/daycare_egg.log", "a")
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
    say("PASS daycare_egg")
    love.event.quit(0)
  else
    say("FAIL daycare_egg failures=" .. failures)
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
  local Breeding = require("src.core.game3.breeding")
  local StepEvents = require("src.core.game3.step_events")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  -- pokefirered/data/maps/FourIsland/scripts.inc:23 the rival has already left
  Flags.setVar(session.store or Space.store, nil, VAR_MAP_SCENE_FOUR_ISLAND, 1)

  session.party = {}
  Party.giveMon(session, MAGIKARP, 5)
  Party.giveMon(session, MAGIKARP, 5)
  Party.giveMon(session, PIDGEY, 9)
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
    for _ = 1, 600 do
      if not scriptRunning() and not Choice.active
        and not (Message.isOpen and Message.isOpen()) then
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

  local function boardOne(label)
    result(pumpUntil(function() return Choice.active end, 90),
      "the day-care woman asked: " .. label)
    answerYes()
    if not result(pumpUntil(function() return PartyMenu.isOpen and PartyMenu.isOpen() end, 180),
      "ChooseSendDaycareMon opened the party picker for " .. label) then
      return false
    end
    U.tap(game, "a")
    U.wait(30)
    return true
  end

  goTo(DAYCARE, WOMAN_X, WOMAN_Y + 1, "up")
  say("[driver] boarding the female MAGIKARP")
  boardOne("the first MAGIKARP")
  result(pumpUntil(function() return Choice.active end, 240),
    "and offered to raise one more")
  U.shot(game, DIR .. "/daycare_egg_01_one_more.png")
  say("[driver] boarding the male MAGIKARP")
  boardOne("the second MAGIKARP")
  waitIdle()

  local dc = Daycare.stateOf(session)
  if not result(Daycare.count(dc) == 2, "both MAGIKARP are boarded, got " ..
    tostring(Daycare.count(dc))) then
    return finish()
  end
  result(Breeding.compatibility(dc) == 70,
    "GetDaycareCompatibilityScore is PARENTS_MAX_COMPATIBILITY, got " ..
    tostring(Breeding.compatibility(dc)))

  -- pokefirered/data/maps/FourIsland/scripts.inc:121 FourIsland_EventScript_CheckOnTwoMons
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

  if result(talkToDaycareMan(), "the day-care man is on Four Island") then
    result(pumpUntil(function()
      return page():find("get along") ~= nil and Message.isWaiting and Message.isWaiting()
    end, 180), "he quotes the compatibility line: " .. page())
    U.shot(game, DIR .. "/daycare_egg_02_compatibility.png")
    waitIdle()
  end

  say("[driver] walking until the day care produces an egg")
  goTo(DAYCARE, WOMAN_X + 1, WOMAN_Y + 2, "down")
  Field.unlock()
  U.wait(20)
  local walked = walkUntil(256 * 5, function()
    return Daycare.isEggPending(dc)
  end)
  say("[driver] walked " .. tostring(walked) .. " grid steps")
  if not result(Daycare.isEggPending(dc),
    "TriggerPendingDaycareEgg fired, offspringPersonality=" ..
    tostring(dc.offspringPersonality)) then
    return finish()
  end
  result((walked % 256) == 255,
    "the egg came on a step where (mons[1].steps & 0xFF) == 0xFF, at " .. tostring(walked))
  result(Flags.getFlag(session.store or Space.store, nil,
    Breeding.FLAG_PENDING_DAYCARE_EGG) == true,
    "FLAG_PENDING_DAYCARE_EGG is set")

  say("[driver] collecting the egg from the day-care man")
  if not result(talkToDaycareMan(), "the day-care man moved out to meet the player") then
    return finish()
  end
  result(pumpUntil(function() return Choice.active end, 240),
    "he offers the egg: " .. page())
  U.shot(game, DIR .. "/daycare_egg_03_offer.png")
  answerYes()
  result(pumpUntil(function()
    return page():find("received the EGG") ~= nil
      and Message.isWaiting and Message.isWaiting()
  end, 240), "the egg hand-off scene plays: " .. page())
  U.shot(game, DIR .. "/daycare_egg_04_received.png")
  waitIdle()

  local egg
  for _, mon in ipairs(session.party) do
    if mon.isEgg then egg = mon end
  end
  if not result(egg ~= nil, "the EGG is in the party") then return finish() end
  result(egg.species == MAGIKARP,
    "two MAGIKARP made a MAGIKARP egg, got " .. tostring(egg.species))
  local cycles = tonumber(Pokemon.speciesMeta(MAGIKARP).eggCycles)
  result(egg.friendship == cycles,
    "its hatch counter is the ROM's " .. tostring(cycles) .. " egg cycles, got " ..
    tostring(egg.friendship))
  result(Daycare.isEggPending(dc) == false, "the day care has no egg waiting any more")

  say("[driver] walking the egg to its hatch (" .. tostring(cycles) .. " cycles)")
  goTo(DAYCARE, WOMAN_X + 1, WOMAN_Y + 2, "down")
  Field.unlock()
  U.wait(20)
  local EggHatch = require("src.ui.game3.egg_hatch")
  walked = walkUntil(256 * (cycles + 2), function()
    return StepEvents.busy()
  end)
  say("[driver] walked " .. tostring(walked) .. " more grid steps")
  -- pokefirered/data/scripts/day_care.inc:112 DayCare_Text_Huh
  result(pumpUntil(function() return page():find("Huh") ~= nil end, 120),
    "the field script prints Huh?: " .. page())
  -- pokefirered/data/scripts/day_care.inc:113 special EggHatch
  result(pumpUntil(function() return EggHatch.isOpen() end, 120),
    "dismissing Huh? opens the hatch scene")

  local function waitScene(name, frames)
    for _ = 1, frames do
      if EggHatch.isOpen() and EggHatch._state == name then return true end
      U.wait(2)
    end
    return EggHatch.isOpen() and EggHatch._state == name
  end

  -- pokefirered/src/daycare.c:1927 gText_HatchedFromEgg
  result(waitScene("hatched_msg", 300), "the egg-hatch scene reached the hatch line")
  U.wait(20)
  U.shot(game, DIR .. "/daycare_egg_05_hatch.png")
  result(page():find("hatched from the EGG") ~= nil,
    "the hatch line is on screen, not an evolution: " .. page())
  -- pokefirered/src/daycare.c:1944 gText_NickHatchPrompt
  result(waitScene("nickname_ask", 300), "and the nickname prompt follows")
  U.shot(game, DIR .. "/daycare_egg_06_nickname.png")
  -- pokefirered/src/daycare.c:1966 case 1 declines the naming screen
  for _ = 1, 10 do
    if Choice.cursor == 2 then break end
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  for _ = 1, 600 do
    if not EggHatch.isOpen() then break end
    U.wait(5)
  end
  result(not EggHatch.isOpen(), "the scene handed control back to the field")
  result(egg.isEgg == false, "the EGG hatched")
  result(egg.level == 5, "it hatched at level 5, got " .. tostring(egg.level))
  result(egg.friendship == 120, "with friendship 120, got " .. tostring(egg.friendship))
  result((egg.nickname == "" or egg.nickname == nil)
    and egg.name == Pokemon.name(MAGIKARP),
    "and it is called " .. tostring(egg.name) .. ", not EGG")
  -- pokefirered/src/daycare.c:1671 MonRestorePP
  result(egg.pp == nil or egg.maxPp == nil or egg.pp[1] == egg.maxPp[1],
    "its PP came back full, got " .. tostring(egg.pp and egg.pp[1]))

  for _ = 1, 600 do
    if not StepEvents.busy() then break end
    if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
    U.wait(5)
  end
  U.wait(60)
  U.shot(game, DIR .. "/daycare_egg_07_hatched.png")

  finish()
end
