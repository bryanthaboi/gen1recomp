local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import2_egg_hatch"

local MAGIKARP = 129

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS import2_egg_hatch")
    love.event.quit(0)
  else
    print("FAIL import2_egg_hatch failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local Field = require("src.core.game3.field")
  local Message = require("src.ui.game3.message")
  local EggHatch = require("src.ui.game3.egg_hatch")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  -- pokefirered/src/daycare.c:1081 the day care hands the egg to the party
  local ok = Party.giveEgg(session, MAGIKARP)
  local egg = session.party and session.party[#session.party]
  if not result(ok and egg and egg.isEgg == true, "an EGG is in the party") then
    return finish()
  end

  local pic = Pokemon.frontPic(Pokemon.SPECIES_EGG)
  result(pic ~= nil and pic.image ~= nil, "the baked EGG front pic loaded from the cache")
  if pic and pic.image then
    result(pic.image:getWidth() == 64 and pic.image:getHeight() == 64,
      string.format("the EGG pic is %dx%d", pic.image:getWidth(), pic.image:getHeight()))
  end

  -- pokefirered/src/daycare.c:1101 the egg cycle counter rides in friendship
  egg.friendship = 0
  egg.eggCycles = 0
  -- pokefirered/src/daycare.c:1157 the cycles only tick on the 256th step
  local Daycare = require("src.core.game3.daycare")
  local dc = Daycare.stateOf(session)
  if not result(dc ~= nil, "the save carries a day care record to step") then return finish() end
  dc.stepCounter = 254
  Field.unlock()
  U.wait(20)

  local function page()
    return (Message.currentPage and Message.currentPage()) or ""
  end

  local StepEvents = require("src.core.game3.step_events")
  local walked = 0
  for _ = 1, 60 do
    U.hold(game, walked % 2 == 0 and "left" or "right", 16)
    walked = walked + 1
    if page():find("Huh") or EggHatch.isOpen() then break end
  end
  print(string.format("[driver] %d holds, %s grid steps, day care counter %s",
    walked, tostring(StepEvents._totalSteps), tostring(dc.stepCounter)))
  -- pokefirered/data/scripts/day_care.inc:112 DayCare_Text_Huh
  result(page():find("Huh") ~= nil or EggHatch.isOpen(),
    "walking ran ShouldEggHatch and the field asked Huh?: " .. page())
  U.tap(game, "a")

  local function waitScene(name, frames)
    for _ = 1, frames do
      if EggHatch.isOpen() and EggHatch._state == name then return true end
      U.wait(2)
    end
    return EggHatch.isOpen() and EggHatch._state == name
  end

  -- pokefirered/src/daycare.c:1893 the egg shakes before it opens
  if not result(waitScene("shake", 300), "the hatch scene put the egg on screen") then
    return finish()
  end
  result(EggHatch._eggShown == true, "the scene is drawing the EGG, not the hatchling")
  U.shot(game, DIR .. "/import2_egg_hatch_01_egg_on_screen.png")

  result(waitScene("hatched_msg", 600), "and the egg hatched")
  U.shot(game, DIR .. "/import2_egg_hatch_02_hatched.png")
  finish()
end
