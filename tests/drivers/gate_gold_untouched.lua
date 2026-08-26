-- Gate check: the Crystal wave left Gold alone.  No Battle Tower, no Buena's
-- Blue Card, no Ruins of Alph secret chambers, and the three beasts roam.
--
--   POKEPORT_GAME=gold POKEPORT_VERSION=gold \
--     POKEPORT_DRIVER=tests/drivers/gate_gold_untouched.lua love .
local U = require("tests.drivers.util")

local Battle = require("src.battle.gen2.Battle")
local Roamers = require("src.core.gen2.Roamers")

return function(game)
  local fails = 0
  local function say(line) print("[driver] " .. line); io.stdout:flush() end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "OK   " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "gold world did not boot")
  say("version=" .. tostring(game.version) .. " map=" .. tostring(world.map.id))

  local order = {}
  for _, name in ipairs((world.constants or {}).specialOrder or {}) do
    order[name] = true
  end
  ok(next(order) ~= nil, "the Gold cache names its specials")
  for _, name in ipairs({ "BattleTowerBattle", "BattleTowerAction",
      "BattleTowerRoomMenu", "LoadOpponentTrainerAndPokemonWithOTSprite",
      "BuenasPassword", "BuenaPrize", "AskRememberPassword",
      "OmanyteChamber", "HoOhChamber", "CelebiShrineEvent",
      "SampleKenjiBreakCountdown", "MoveTutor", "PokeSeer" }) do
    ok(not order[name], "Gold has no " .. name .. " special")
  end

  ok(world.maps.BATTLE_TOWER_1F == nil, "no BATTLE_TOWER_1F map")
  ok(world.maps.BATTLE_TOWER_BATTLE_ROOM == nil, "no tower battle room")
  ok((world.trainers or {}).battleTower == nil,
    "trainers.lua carries no battleTower roster")
  ok((world.eventTables or {}).unownWalls == nil,
    "events.lua carries no unownWalls table")

  -- ../pokecrystal/constants/event_flags.asm:486-489 are Crystal-only.
  for _, flag in ipairs({ 806, 807, 808, 809 }) do
    ok(not world.events:get(flag), "wall-opened flag " .. flag .. " is clear")
  end

  -- ../pokecrystal/constants/script_constants.asm:69-74, Crystal-only VARs.
  for _, id in ipairs({ 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a }) do
    ok(world:readVar(id) == 0,
      ("VAR $%02x reads 0 on Gold"):format(id))
  end

  -- data/wild/roammon_maps.asm: RAIKOU, ENTEI and SUICUNE, all three.
  local roster = Roamers.roster(world.encounters)
  say("roamer roster: " .. #roster .. " rows")
  for _, row in ipairs(roster) do
    say(("  %s L%s start=%s"):format(tostring(row.species),
      tostring(row.level), tostring(row.map)))
  end
  ok(#roster == 3, "three beasts in the roster")
  local list = Roamers.init(game.save, { encounters = world.encounters, force = true })
  local live = 0
  for _, slot in ipairs(list or {}) do
    if Roamers.active(slot) then live = live + 1 end
  end
  ok(live == 3, "all three are active after InitRoamMons")

  -- pokegold/engine/battle/core.asm:3476-3479: TRAP and FORCESHINY only.
  ok(Battle.noEscapeBattleType({ battleType = 9 }) == true, "TRAP: no escape")
  ok(Battle.noEscapeBattleType({ battleType = 7 }) == true,
    "FORCESHINY: no escape")
  ok(Battle.noEscapeBattleType({ battleType = 10 }) == false,
    "FORCEITEM: Lugia and Ho-Oh can still be run from on Gold")
  ok(Battle.noEscapeBattleType({ battleType = 8 }) == false, "TREE: escapable")

  say(fails == 0 and "PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
