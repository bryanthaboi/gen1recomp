-- Assertion driver: the three legendary beasts, in the running game.
--
--   POKEPORT_GAME=gold POKEPORT_IDENTITY=gold-dev \
--     POKEPORT_DRIVER=tests/drivers/gold_roamers.lua love .
--   POKEPORT_SHOT_DIR=/tmp/gold-roamers   (default)
--
-- The whole feature was a model with no callers: `special InitRoamMons` wrote
-- the three structs and nothing ever moved them, rolled for them or banked
-- them.  tests/gen2_roamers_test.lua pins the four call sites against fixtures;
-- this walks the real thing -- the real special, real map loads on real Johto
-- routes, and a real battle screen with a real beast on it.
local U = require("tests.drivers.util")

local Roamers = require("src.core.gen2.Roamers")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-roamers"

  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  local save = game.save
  save.roamers = nil

  -- ---- InitRoamMons, through the special the Burned Tower runs ------------
  -- Dispatched BY NAME through the cache's own specialOrder, so this is the
  -- same path BurnedTowerB1F's `special InitRoamMons` takes.
  local order = world.constants and world.constants.specialOrder
  assert(order, "no specialOrder in the cache")
  local id
  for index, name in ipairs(order) do
    if name == "InitRoamMons" then id = index - 1 break end
  end
  assert(id, "InitRoamMons is not in SpecialsPointers")
  world.vm:runSpecial(id)
  local beasts = Roamers.list(save)
  assert(beasts and #beasts == 3,
    "InitRoamMons did not put three beasts on the save")
  local starts = {}
  for i, slot in ipairs(beasts) do
    assert(Roamers.active(slot), "beast " .. i .. " came out inactive")
    assert(slot.hp == 0, "a fresh beast has no rolled stats yet")
    starts[i] = slot.map
    U.log(("beast %d: %s L%d on %s"):format(i, slot.species, slot.level, slot.map))
  end
  assert(starts[1] == "ROUTE_42" and starts[2] == "ROUTE_37"
    and starts[3] == "ROUTE_38",
    "the three starting routes are not Raikou 42 / Entei 37 / Suicune 38")

  -- ---- UpdateRoamMons, on a real door warp --------------------------------
  -- MapSetupScript_Fall drops into _Door drops into _Train, and UpdateRoamMons
  -- is _Train's tail -- so walking through a door nudges every beast one
  -- connection along.
  local before = { beasts[1].map, beasts[2].map, beasts[3].map }
  local moves = 0
  for _ = 1, 12 do
    local was = { beasts[1].map, beasts[2].map, beasts[3].map }
    world:runMapSetup(0xf5, function() -- MAPSETUP_DOOR
      return world:setMap("ROUTE_29", 20, 8, "down")
    end)
    for _ = 1, 60 do
      if not world.mapSetup then break end
      U.wait(1)
    end
    for i = 1, 3 do
      if beasts[i].map ~= was[i] then moves = moves + 1 end
    end
  end
  assert(moves > 0,
    "twelve door warps and not one beast moved: UpdateRoamMons is not wired")
  local anyMoved = false
  for i = 1, 3 do
    if beasts[i].map ~= before[i] then anyMoved = true end
    assert(Roamers.entryFor(beasts[i].map, world.encounters),
      ("beast %d walked off the roam map list onto %s")
        :format(i, tostring(beasts[i].map)))
  end
  assert(anyMoved, "the beasts ended exactly where they started")
  U.log(("UpdateRoamMons: %d moves over twelve door warps, now on %s / %s / %s")
    :format(moves, beasts[1].map, beasts[2].map, beasts[3].map))

  -- A plain warp names neither command, so nothing may move.
  local held = { beasts[1].map, beasts[2].map, beasts[3].map }
  world:runMapSetup(0xf1, function() -- MAPSETUP_WARP
    return world:setMap("ROUTE_30", 10, 10, "down")
  end)
  for _ = 1, 60 do
    if not world.mapSetup then break end
    U.wait(1)
  end
  for i = 1, 3 do
    assert(beasts[i].map == held[i],
      "a plain warp moved a beast; only _Connection / _Train / _Teleport may")
  end
  U.log("and a plain warp leaves them alone, the way MapSetupScript_Warp does")

  -- ---- JumpRoamMons, on a teleport ----------------------------------------
  -- Flying is MAPSETUP_TELEPORT, whose third row scatters every beast to a
  -- random roam map.  Over ten flights all three have to land somewhere new.
  local seen = { {}, {}, {} }
  for _ = 1, 10 do
    -- JumpRoamMons runs ABOVE the load, so "the player's map" it re-rolls off
    -- is the one being LEFT, not the destination.
    local leaving = world.map.id
    world:runMapSetup(0xf4, function() -- MAPSETUP_TELEPORT
      return world:setMap("ROUTE_29", 20, 8, "down")
    end)
    for _ = 1, 60 do
      if not world.mapSetup then break end
      U.wait(1)
    end
    for i = 1, 3 do
      seen[i][beasts[i].map] = true
      assert(beasts[i].map ~= leaving,
        ("JumpRoamMon dropped beast %d on %s, the map the player just left")
          :format(i, tostring(leaving)))
    end
  end
  for i = 1, 3 do
    local count = 0
    for _ in pairs(seen[i]) do count = count + 1 end
    assert(count > 1,
      ("beast %d sat on one map across ten teleports: JumpRoamMons is dead")
        :format(i))
  end
  U.log("JumpRoamMons: ten flights scattered all three, never onto the map left")

  -- ---- CheckEncounterRoamMon, into a real battle --------------------------
  -- Put Raikou under the player's feet and pin the roll to the one byte that
  -- gets past both of CheckEncounterRoamMon's gates and picks slot 1.
  local Mon = require("src.battle.gen2.Mon")
  save.party = { Mon.new(game.data, "CYNDAQUIL", 30) }
  assert(save.party[1], "could not build the player's mon")
  world:setMap("ROUTE_29", 20, 8, "down")
  U.wait(10)
  beasts[1].map = "ROUTE_29"
  world.roamerRandom = function() return 1 end
  world.player.cellX, world.player.cellY = 20, 8

  -- CanEncounterWildMon has to pass before ChooseWildEncounter is reached at
  -- all, so stand in real tall grass rather than wherever the warp landed.
  -- The cell is found in the map rather than remembered.
  local FieldMoves = require("src.world.gen2.FieldMoves")
  local grassX, grassY
  for cy = 0, world.map.heightCells - 1 do
    for cx = 0, world.map.widthCells - 1 do
      local coll = world.map:cellCollision(cx, cy)
      if FieldMoves.canEncounterWildMon(
          world.map.def.environment, coll, false) then
        grassX, grassY = cx, cy
        break
      end
    end
    if grassX then break end
  end
  assert(grassX, "no encounter tile anywhere on ROUTE_29")
  world.player.cellX, world.player.cellY = grassX, grassY
  world.player.px, world.player.py = grassX * 16, grassY * 16
  U.log(("standing in Route 29's grass at (%d,%d)"):format(grassX, grassY))

  -- TryWildEncounter runs `.EncounterRate` FIRST and only reaches
  -- ChooseWildEncounter -- CheckEncounterRoamMon included -- on a pass
  -- (engine/overworld/wildmons.asm), so the beast sits behind a random byte
  -- this driver does not own.  Pin THAT byte rather than the roamer roll: the
  -- map's own rate is still read and both arms of the gate are asserted, which
  -- is the cart order itself rather than a way around it.
  local Encounter = require("src.battle.gen2.Encounter")
  local realTriggers = Encounter.triggers
  local rate = Encounter.grassRate(world:wildTables(), world.map.id,
    world.daytime)
  assert(rate and rate > 0, "ROUTE_29 has no grass encounter rate to gate on")
  -- engine/overworld/events.asm:357
  world.wildCooldown = 0
  Encounter.triggers = function() return false end
  local gated = world:tryWildEncounter()
  Encounter.triggers = function(r) return realTriggers(r, function() return 0 end) end
  local ok, met = pcall(world.tryWildEncounter, world)
  Encounter.triggers = realTriggers
  assert(ok, met)
  assert(not gated,
    "a beast turned up with the encounter rate refusing: the roamer check is "
      .. "above `.EncounterRate` rather than inside ChooseWildEncounter")
  assert(met,
    "the wild roll met nothing with a beast on the player's own route")
  U.log(("ROUTE_29 grass rate %d/256; the beast is behind it, not beside it")
    :format(rate))

  local battle
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then battle = top break end
    U.wait(1)
  end
  assert(battle, "the roaming battle never reached the screen")
  U.wait(90)
  assert(battle.battle.roaming == 1,
    "the battle does not know it is BATTLETYPE_ROAMING")
  assert(battle.battle.enemy.species == "RAIKOU",
    "met " .. tostring(battle.battle.enemy.species) .. " rather than RAIKOU")
  assert(battle.battle.enemy.level == 40, "at the wrong level")
  assert(beasts[1].hp > 0,
    ".InitRoamHP banks the beast's full HP on the FIRST meeting")
  assert(beasts[1].dvs, "and rolls its DVs once, so it stays one individual")
  assert(U.shot(game, out .. "/00-raikou.png"), "no screenshot")
  U.log(("CheckEncounterRoamMon: met %s L%d, slot %d, %d HP banked, DVs kept")
    :format(battle.battle.enemy.species, battle.battle.enemy.level,
      battle.battle.roaming, beasts[1].hp))

  U.log("PASS gold_roamers in " .. out)
  love.event.quit(0)
end
