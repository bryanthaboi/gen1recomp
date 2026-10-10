-- pokeemerald/src/field_control_avatar.c:159
-- pokeemerald/src/field_control_avatar.c:604 TryStartMatchCall
local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_match_call_blocks_wild_2826", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_match_call_blocks_wild_2826")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Battle = require("src.core.game3.battle")
  local Encounters = require("src.core.game3.encounters")
  local Party = require("src.core.game3.party")
  local Rematch = require("src.core.game3.rse.rematch")
  local MatchCall = require("src.core.game3.rse.match_call")
  local CallWindow = require("src.ui.game3.rse.pokenav.call_window")
  local StepEvents = require("src.core.game3.step_events")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not S.check(session.version == "emerald", "driver runs Emerald") then return S.finish() end
  F.noTrainerSight()

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_MARSHTOMP, 20, "MARSHTOMP")
  for _, f in ipairs({ "FLAG_SYS_POKENAV_GET", "FLAG_RECEIVED_POKENAV", "FLAG_HAS_MATCH_CALL",
      "FLAG_ADDED_MATCH_CALL_TO_POKENAV" }) do
    F.setFlag(f, true)
  end
  local idx = Rematch.firstBattleTableId(C.trainers.byName.TRAINER_CINDY_1)
  Rematch.setFlag(session, Rematch.registeredFlagId(session, idx), true)
  S.check(MatchCall.numRegisteredTrainers(session) >= 1, "a match call trainer is registered")

  S.check(F.goTo(game, "EM_ROUTE102", 10, 10, "left"), "Route 102 reached")
  local function grass(x, y) return Collision.isGrass(x, y) and true or false end
  local function can(fx, fy, tx, ty, dir)
    return Collision.canEnter(game, tx, ty, { fromX = fx, fromY = fy, dir = dir }) == true
      and not Collision.warpAt(tx, ty)
  end
  local spot
  for y = 2, 30 do
    for x = 2, 60 do
      if not spot and grass(x, y) and grass(x - 1, y) and can(x, y, x - 1, y, "left")
          and can(x - 1, y, x, y, "right") then
        spot = { x = x, y = y }
      end
    end
  end
  if not S.check(spot ~= nil, "found two side by side grass cells") then return S.finish() end
  F.goTo(game, "EM_ROUTE102", spot.x, spot.y, "left")
  S.note(("grass step from (%d,%d) to (%d,%d)"):format(spot.x, spot.y, spot.x - 1, spot.y))

  local rolls = 0
  Encounters.onStep = function()
    rolls = rolls + 1
    return { species = C.species.byName.SPECIES_TENTACOOL, level = 15 }
  end
  MatchCall.rng = function() return 0 end
  local s = MatchCall.initCounters(session)
  s.stepCounter = 9
  s.minutes = MatchCall.totalMinutes(session) - 20
  S.check(MatchCall.mapAllowsMatchCall(session), "Route 102 allows match calls")

  local function step(dir, x)
    F.holdKeys(game, { dir }, 20, function() return Player.moving end)
    for _ = 1, 40 do
      if not Player.moving then break end
      U.wait(1)
    end
    return Player.cellX == x
  end

  S.check(step("left", spot.x - 1), "the call step lands on the next grass cell")
  local opened = false
  for _ = 1, 60 do
    if CallWindow.isOpen() then opened = true break end
    U.wait(1)
  end
  S.check(opened, "the match call window opens on the call step")
  S.check(rolls == 0, "no wild roll on the call step (rolls=" .. rolls .. ")")
  S.check(not Battle.isActive(), "no wild battle on the call step")
  U.wait(30)
  S.still(game, "2826_01_match_call_no_battle.png")
  S.check(not Battle.isActive(), "still no battle while the call is up")

  for i = 1, 1200 do
    if not CallWindow.isOpen() and not StepEvents.busy() then break end
    if i % 6 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  S.check(not CallWindow.isOpen(), "the call hangs up")
  S.check(not Battle.isActive(), "hanging up does not start a battle")
  U.wait(10)

  S.check(step("right", spot.x), "the next grass step completes")
  local battle = false
  for _ = 1, 120 do
    if Battle.isActive() then battle = true break end
    U.wait(1)
  end
  S.check(rolls == 1, "the next grass step rolls (rolls=" .. rolls .. ")")
  S.check(battle, "the next grass step starts the wild battle")
  S.check(not CallWindow.isOpen(), "no call window over the battle")
  U.wait(150)
  S.still(game, "2826_02_next_step_wild_battle.png")
  S.finish()
end
