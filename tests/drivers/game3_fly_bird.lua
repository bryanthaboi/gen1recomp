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
  local Fade = require("src.ui.game3.fade")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  Map.load(nil, game, "FR_PALLET_TOWN", { x = 5, y = 8, facing = "down" })
  session.x, session.y, session.facing = 5, 8, "down"
  Player.cellX, Player.cellY = 5, 8
  Player.px, Player.py = 5 * 16, 8 * 16
  Player.targetX, Player.targetY = 5, 8
  Player.facing = "down"
  U.wait(60)
  local events = {}
  local realBegin, realLoad, realLanding = Fade.begin, Map.load, FieldEffects.startFlyIn
  Fade.begin = function(mode, ...)
    events[#events + 1] = "fade" .. tostring(mode)
    return realBegin(mode, ...)
  end
  Map.load = function(mod, g, mapId, ...)
    events[#events + 1] = "load:" .. tostring(mapId)
    return realLoad(mod, g, mapId, ...)
  end
  FieldEffects.startFlyIn = function(...)
    events[#events + 1] = Fade.active and "landing-during-fade" or "landing"
    return realLanding(...)
  end
  local function sequence(mapId)
    local want = { "fade0", "fade1", "load:" .. mapId, "fade0", "landing" }
    local got = table.concat(events, ",")
    local i = 1
    for _, e in ipairs(events) do
      if e == want[i] then i = i + 1 end
      if e == "landing-during-fade" then return false, got end
    end
    return i > #want, got
  end
  local function waitFor(pred, frames)
    for _ = 1, frames do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  local gender = tonumber(session.gender) or 0
  local function attachedTo(b)
    return Player.spriteXOffset == b.x + b.x2 - 120
      and Player.spriteYOffset == b.y + b.y2 - 8 - 72
  end

  result(Field.flyTo("MAPSEC_PEWTER_CITY") == true, "the fly map select took PEWTER CITY")
  -- pokefirered/src/field_effect.c:1073 FieldCallback_UseFly
  result(Fade.active and Fade.mode == Fade.MODE.FROM_BLACK and anim("fly_out") == nil,
    "the field fades in from black before the takeoff")
  waitFor(function() return anim("fly_out") ~= nil end, 600)
  local out = anim("fly_out")
  if not result(out ~= nil, "the ShowMon cut-in hands over to FldEff_FlyOut") then return finish() end

  local sheet = FieldEffects._sheets and FieldEffects._sheets["fly_bird"]
  if not result(type(sheet) == "table", "the fly_bird sheet loaded from the cache") then return finish() end
  local iw, ih = sheet.image:getDimensions()
  result(iw == 64 and ih == 320,
    string.format("fly_bird sheet is 64x320, got %dx%d", iw, ih))
  result(sheet.quads[4] ~= nil, "the sheet has all five frames")

  -- pokefirered/src/field_effect.c:3398 SpriteCB_FlyBirdLeaveBall
  waitFor(function() return out.bird and out.bird.d1 >= 96 end, 120)
  local b = out.bird
  result(b and b.cb == "leave" and b.anim == 0 and b.aff and b.aff.scale > 256,
    "the bird leaves the ball alone, growing on its arc (d1=" .. tostring(b and b.d1)
    .. " scale=" .. tostring(b and b.aff and b.aff.scale) .. ")")
  result(Player.isVisible() and (Player.fieldMoveAnim or 0) > 0,
    "the player holds the field-move pose while the bird leaves")
  U.still(game, DIR .. "/fly_bird_01_leave_ball.png")

  -- pokefirered/src/field_effect.c:3278 FlyOutFieldEffect_BirdSwoopDown
  waitFor(function() return out.state == "jump_on" and b.d2 >= 24 end, 200)
  result(out.state == "jump_on" and b.cb == "swoop" and b.anim == 0 and Player.facing == "left"
    and not Player.flyRide,
    "the bird swoops in from the right while the player faces left (state=" .. tostring(out.state) .. ")")
  U.still(game, DIR .. "/fly_bird_02_swoop_down.png")

  -- pokefirered/src/field_effect.c:3289 FlyOutFieldEffect_JumpOnBird
  waitFor(function() return out.state == "fly_off" and out.tTimer >= 4 end, 60)
  result(Player.flyRide and Player.spriteYOffset < 0,
    "the player jumps on in the ride sprite (y2=" .. tostring(Player.spriteYOffset) .. ")")
  U.still(game, DIR .. "/fly_bird_03_jump_on.png")

  -- pokefirered/src/field_effect.c:3677 SpriteCB_FlyBirdWithPlayer
  waitFor(function() return out.state == "wait_off" and b.d2 >= 86 end, 120)
  result(b.anim == gender * 2 + 1 and b.cb == "with_player" and attachedTo(b) and Player.isVisible(),
    "the bird flies off with the player riding, anim=" .. tostring(b.anim)
    .. " player at " .. tostring(Player.spriteXOffset) .. "," .. tostring(Player.spriteYOffset))
  U.still(game, DIR .. "/fly_bird_04_fly_off_ridden.png")

  waitFor(function() return anim("fly_out") == nil end, 300)
  result(anim("fly_out") == nil and not Player.flyRide, "the takeoff animation ends")

  -- pokefirered/src/field_effect.c:1104 FieldCallback_FlyIntoMap
  waitFor(function() return anim("fly_in") ~= nil end, 900)
  local okSeq, seq = sequence("FR_PEWTER_CITY")
  result(okSeq, "fade in, fade out, load PEWTER CITY, fade in from black, then land: " .. seq)
  local landing = anim("fly_in")
  if not result(landing ~= nil, "the landing at PEWTER CITY queued FldEff_FlyIn") then
    return finish()
  end
  result(session.map == "FR_PEWTER_CITY",
    "and it dropped the player in PEWTER CITY, map=" .. tostring(session.map))
  -- pokefirered/src/field_effect.c:3550
  waitFor(function() return landing.state == "with_bird" and landing.tTimer <= 18 end, 60)
  local lb = landing.bird
  result(lb and lb.anim == gender * 2 + 2 and lb.attached and attachedTo(lb) and Player.flyRide,
    "the landing bird carries the player and the player sprite rides it, anim="
    .. tostring(lb and lb.anim) .. " player at "
    .. tostring(Player.spriteXOffset) .. "," .. tostring(Player.spriteYOffset))
  U.still(game, DIR .. "/fly_bird_05_landing_carried.png")

  -- pokefirered/src/field_effect.c:3575 FlyInFieldEffect_JumpOffBird
  waitFor(function() return landing.state == "jump_off" and landing.tTimer >= 7 end, 80)
  result(landing.state == "jump_off" and not lb.attached and lb.anim == 0,
    "the player jumps off and the bird swoops on alone (anim=" .. tostring(lb.anim) .. ")")
  U.still(game, DIR .. "/fly_bird_06_jump_off.png")

  -- pokefirered/src/field_effect.c:3450 SpriteCB_FlyBirdReturnToBall
  waitFor(function() return landing.state == "wait_return" and lb.d3 >= 24 end, 200)
  result(landing.state == "wait_return" and lb.cb == "return" and Player.spriteXOffset == 0
    and Player.spriteYOffset == 0 and (Player.fieldMoveAnim or 0) > 0,
    "the bird returns to the ball while the player holds the pose on the landing cell")
  U.still(game, DIR .. "/fly_bird_07_bird_return.png")

  waitFor(function() return anim("fly_in") == nil end, 300)
  result(anim("fly_in") == nil and Player.facing == "down" and not Player.flyRide,
    "the landing animation ends facing south")
  waitFor(function() return not Field.locked end, 120)
  result(not Field.locked, "the field is unlocked after landing")

  local sevii = Field.flyDestination("MAPSEC_ONE_ISLAND")
  if not result(sevii ~= nil, "ONE ISLAND has a fly destination") then return finish() end
  events = {}
  result(Field.flyTo("MAPSEC_ONE_ISLAND") == true, "the fly map select took ONE ISLAND")
  waitFor(function()
    local l = anim("fly_in")
    return session.map == sevii.map and l and l.state == "jump_off"
  end, 1500)
  U.still(game, DIR .. "/fly_bird_08_one_island_landing.png")
  local okSevii, seqSevii = sequence(sevii.map)
  result(okSevii, "Kanto to ONE ISLAND fades in from black before the bird lands: " .. seqSevii)
  waitFor(function() return anim("fly_in") == nil and not Field.locked end, 900)
  result(session.map == sevii.map and not Field.locked,
    "the Sevii landing finishes on " .. tostring(session.map))
  Fade.begin, Map.load, FieldEffects.startFlyIn = realBegin, realLoad, realLanding

  finish()
end
