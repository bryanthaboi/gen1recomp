local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_fly_bird"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS fly_bird")
    love.event.quit(0)
  else
    print("FAIL fly_bird failures=" .. failures)
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
  local FieldEffects = require("src.core.game3.field_effects")
  local Field = require("src.core.game3.field")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function anim(kind)
    for _, a in ipairs(FieldEffects._anims or {}) do
      if a.kind == kind then return a end
    end
    return nil
  end

  -- pokefirered/src/field_effect.c:1065 ReturnToFieldFromFlyMapSelect
  result(Field.flyTo("MAPSEC_PEWTER_CITY") == true, "the fly map select took PEWTER CITY")
  U.wait(2)
  local takeoff = anim("fly_takeoff")
  if not result(takeoff ~= nil, "Field.flyTo queued the takeoff animation") then return finish() end

  local sheet = FieldEffects._sheets and FieldEffects._sheets["fly_bird"]
  if not result(type(sheet) == "table", "the fly_bird sheet loaded from the cache") then return finish() end
  local iw, ih = sheet.image:getDimensions()
  result(iw == 64 and ih == 320,
    string.format("fly_bird sheet is 64x320, got %dx%d", iw, ih))
  result(sheet.quads[4] ~= nil, "the sheet has all five frames")

  result(takeoff.frame == 0, "the bird arrives alone on frame 0, got " .. tostring(takeoff.frame))
  U.shot(game, DIR .. "/fly_bird_01_takeoff_alone.png")

  for _ = 1, 600 do
    if takeoff.state ~= "descend" then break end
    U.wait(1)
  end
  U.wait(2)
  -- pokefirered/src/field_effect.c:3312 StartSpriteAnim(bird, gender * 2 + 1)
  result(takeoff.frame == (tonumber(session.gender) or 0) * 2 + 1,
    "the ascending bird carries the player, frame=" .. tostring(takeoff.frame))
  U.shot(game, DIR .. "/fly_bird_02_takeoff_ridden.png")

  for _ = 1, 900 do
    if anim("fly_takeoff") == nil then break end
    U.wait(1)
  end
  result(anim("fly_takeoff") == nil, "the takeoff animation ends")

  -- pokefirered/src/field_effect.c:1104 FieldCallback_FlyIntoMap
  for _ = 1, 900 do
    if anim("fly_landing") ~= nil then break end
    U.wait(1)
  end
  local landing = anim("fly_landing")
  if not result(landing ~= nil, "the landing at PEWTER CITY queued its animation") then
    return finish()
  end
  result(session.map == "FR_PEWTER_CITY",
    "and it dropped the player in PEWTER CITY, map=" .. tostring(session.map))
  -- pokefirered/src/field_effect.c:3550 StartSpriteAnim(bird, gender * 2 + 2)
  result(landing.frame == (tonumber(session.gender) or 0) * 2 + 2,
    "the landing bird carries the player, frame=" .. tostring(landing.frame))
  U.shot(game, DIR .. "/fly_bird_03_landing.png")

  for _ = 1, 900 do
    if anim("fly_landing") == nil then break end
    U.wait(1)
  end
  result(anim("fly_landing") == nil, "the landing animation ends")

  finish()
end
