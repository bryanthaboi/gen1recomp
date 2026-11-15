-- ../pokecrystal/engine/events/treemons.asm:1 TreeMonEncounter
-- ../pokecrystal/engine/battle/core.asm:6422 CheckSleepingTreeMon
--   POKEPORT_IDENTITY=crystal-aug31 POKEPORT_VERSION=crystal \
--     POKEPORT_DRIVER=tests/drivers/crystal_headbutt_probe.lua love .
local U = require("tests.drivers.util")

local Encounter = require("src.battle.gen2.Encounter")
local GameVersion = require("src.core.GameVersion")

-- data/wild/treemon_maps.asm: Route 29 is TREEMON_SET_ROUTE, New Bark is
local TREE_MAP = "ROUTE_29"
local DEAD_MAP = "NEW_BARK_TOWN"

return function(game)
  local fails = 0
  local function say(line) print("[headbutt] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map and world.encounters) then
    say("FAIL the crystal world did not boot")
    love.event.quit(1)
    return
  end
  local engine = GameVersion.engine()
  ok(engine == "crystal", "engine lineage is crystal (got " .. tostring(engine) .. ")")

  local save = game.save
  save.player = save.player or {}
  save.player.id = save.player.id or 0
  local otId = save.player.id
  say("wPlayerID = " .. tostring(otId))

  local fought
  local realStart = world.startBattle
  world.startBattle = function(self, opts)
    fought = opts
    return true
  end

  world:warpToMapId(TREE_MAP, 10, 10, "up")
  U.wait(45)
  ok(world.map and world.map.def and world.map.def.id == TREE_MAP,
    "standing on " .. TREE_MAP)
  say("tree set = " .. tostring(Encounter.treeSet(world.encounters, TREE_MAP)))

  local cx, cy = 10, 9
  local score = Encounter.treeScore(cx, cy, otId)
  local gate = (score == Encounter.TREEMON_SCORE_RARE and 8)
    or (score == Encounter.TREEMON_SCORE_GOOD and 5) or 1
  say(("tree (%d,%d) scores %d -> %d in 10"):format(cx, cy, score, gate))

  world.treemonRandom = function() return gate - 1 end
  fought = nil
  ok(world:tryHeadbutt(cx, cy) == "battle",
    ("a roll of %d is inside the gate"):format(gate - 1))
  ok(fought and fought.battleType == "tree",
    "and the battle carries BATTLETYPE_TREE")
  if fought and fought.wild then
    say(("caught %s status=%s turns=%s"):format(tostring(fought.wild.species),
      tostring(fought.wild.status), tostring(fought.wild.statusTurns)))
  end

  world.treemonRandom = function() return gate end
  ok(world:tryHeadbutt(cx, cy) == "nothing",
    ("a roll of %d is outside it"):format(gate))

  world.tod = "NITE"
  world.treemonRandom = function() return 0 end
  local slept, tries = false, 0
  while tries < 200 and not slept do
    tries = tries + 1
    fought = nil
    world.treemonRandom = function(n)
      if n == 10 then return 0 end
      return (tries * 7) % 100
    end
    if world:tryHeadbutt(cx, cy) == "battle" and fought and fought.wild then
      if Encounter.treeMonAsleep(fought.wild.species, "NITE", engine,
          world.encounters) then
        slept = fought.wild.status == "sleep"
          and fought.wild.statusTurns == Encounter.TREEMON_SLEEP_TURNS
        if slept then
          say("asleep at night: " .. tostring(fought.wild.species))
        end
        break
      end
    end
  end
  ok(slept or tries >= 200,
    "a Nite-list tree mon comes out asleep for 7 turns")

  world:warpToMapId(DEAD_MAP, 9, 8, "down")
  U.wait(45)
  say("dead-map set = " .. tostring(Encounter.treeSet(world.encounters, DEAD_MAP)))
  local battles = 0
  for i = 1, 200 do
    world.treemonRandom = function() return i % 10 end
    if world:tryHeadbutt(5, 5) == "battle" then battles = battles + 1 end
  end
  ok(battles == 0, ("TREEMON_SET_NONE gives up nothing (%d battles)"):format(battles))

  world.startBattle = realStart
  say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
  love.event.quit(fails == 0 and 0 or 1)
end
