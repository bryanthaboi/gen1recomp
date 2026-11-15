-- The three roaming beasts, WIRED.  `luajit tests/gen2_roamers_test.lua`; also
-- dofile'd by tests/run_tests.lua.  ROM-free.
--
-- src/core/gen2/Roamers.lua has been complete and unit tested for a while; what
-- it did not have was a single caller outside its own test, so `special
-- InitRoamMons` put three structs on the save when the Burned Tower floor gave
-- way and then nothing ever moved them, rolled for them or banked them.  A
-- beast sat on its starting route forever and could not be met even there.
--
-- So this suite is about the four CALL SITES, and each is a place the cart
-- names explicitly:
--
--   MapSetupCommands $26 UpdateRoamMons   the tail of MapSetupScript_Train,
--                                         which _Door and _Fall fall into, and
--                                         a row of _Connection
--   MapSetupCommands $27 JumpRoamMons     the third row of _Teleport, ABOVE
--                                         the load
--   ChooseWildEncounter                   CheckEncounterRoamMon, before the
--                                         map's own slot list
--   BattleEnd_HandleRoamMons              on the way out of every wild battle
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 roamers")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")
local Roamers = require("src.core.gen2.Roamers")
local FieldMoves = require("src.world.gen2.FieldMoves")
local RoamFixture = require("tests.fixtures.gen2_roamers")

-- MAPSETUP_* (constants/map_setup_constants.asm), as World names them.
local WARP, RELOADMAP = 0xf1, 0xf3
local TELEPORT, DOOR, FALL = 0xf4, 0xf5, 0xf6
local CONNECTION, TRAIN = 0xf7, 0xf9

local function roamWorld(opts)
  opts = opts or {}
  local game = {
    data = {
      pokemon = {
        RAIKOU = { name = "RAIKOU", index = 243, types = { "ELECTRIC" },
          baseStats = { hp = 90, attack = 85, defense = 75, speed = 115,
            specialAttack = 115, specialDefense = 100 },
          growthRate = 0, levelMoves = { { level = 1, move = "QUICK_ATTACK" } } },
      },
      moves = { QUICK_ATTACK = { name = "QUICK ATTACK", pp = 30 } },
    },
    save = { player = { name = "GOLD", badges = {} }, party = {}, inventory = {} },
  }
  local world = World.new(game)
  world.maps = {
    ROUTE_29 = { id = "ROUTE_29", group = 1, map = 1, width = 2, height = 2,
      blocks = { 1, 2, 3, 4 }, objects = {}, warps = {} },
    ROUTE_30 = { id = "ROUTE_30", group = 1, map = 2, width = 2, height = 2,
      blocks = { 1, 2, 3, 4 }, objects = {}, warps = {} },
  }
  world.map = { id = opts.map or "ROUTE_29", def = world.maps.ROUTE_29,
    width = 2, height = 2 }
  world.encounters = RoamFixture.encounters("gold", opts.encounters)
  -- The load itself is not the subject here; the roam step around it is.
  world.setMap = function(self, id)
    self.map = { id = id, def = self.maps[id] or self.maps.ROUTE_29,
      width = 2, height = 2 }
    return true
  end
  Roamers.init(game.save, { force = true, encounters = world.encounters })
  return world, game
end

-- ---------------------------------------------------------------------------
-- The two map setup commands
-- ---------------------------------------------------------------------------

-- Which of the eleven setup scripts carries which command, fallthroughs
-- honoured.  Getting this table wrong is invisible in play -- the beasts just
-- move at the wrong times -- so it is pinned rather than trusted.
do
  local moved = { UPDATE = {}, JUMP = {} }
  local realUpdate, realJump = Roamers.update, Roamers.jumpAll
  Roamers.update = function(...) moved.UPDATE[#moved.UPDATE + 1] = true
    return realUpdate(...) end
  Roamers.jumpAll = function(...) moved.JUMP[#moved.JUMP + 1] = true
    return realJump(...) end

  local function ran(method)
    moved.UPDATE, moved.JUMP = {}, {}
    local world = roamWorld()
    world:runMapSetup(method, function() return world:setMap("ROUTE_30") end)
    -- A fading script parks its load; run the chain out so the tail lands.
    for _ = 1, 40 do
      if not world.mapSetup then break end
      world:updateMapSetup()
    end
    return #moved.UPDATE > 0, #moved.JUMP > 0
  end

  local up, jump = ran(CONNECTION)
  check(up and not jump, "MAPSETUP_CONNECTION names UpdateRoamMons")
  up, jump = ran(TRAIN)
  check(up and not jump, "and so does _Train")
  up, jump = ran(DOOR)
  check(up and not jump, "_Door by falling into _Train")
  up, jump = ran(FALL)
  check(up and not jump, "and _Fall by falling into _Door first")
  up, jump = ran(TELEPORT)
  check(jump and not up,
    "MAPSETUP_TELEPORT names JumpRoamMons, and _Warp below it names neither")
  up, jump = ran(WARP)
  check(not up and not jump, "a plain warp moves nothing")
  up, jump = ran(RELOADMAP)
  check(not up and not jump, "and neither does a reload")

  Roamers.update, Roamers.jumpAll = realUpdate, realJump
end

-- JumpRoamMons runs ABOVE the load and UpdateRoamMons below it, so each sees a
-- different "player's map".  _BackUpMapIndices records whichever it saw, and
-- that is the map the next walk avoids.
do
  local world, game = roamWorld()
  world:runMapSetup(TELEPORT, function() return world:setMap("ROUTE_30") end)
  for _ = 1, 40 do
    if not world.mapSetup then break end
    world:updateMapSetup()
  end
  eq(game.save.roamerMaps.current, "ROUTE_29",
    "JumpRoamMons banked the map being LEFT, because it runs before the load")

  local world2, game2 = roamWorld()
  world2:runMapSetup(CONNECTION, function() return world2:setMap("ROUTE_30") end)
  eq(game2.save.roamerMaps.current, "ROUTE_30",
    "UpdateRoamMons banked the map ARRIVED on, because it is the script's tail")
end

-- No beasts on the save -> nothing to do, and no crash.  This is every game
-- before the Burned Tower.
do
  local world, game = roamWorld()
  game.save.roamers = nil
  check(not world:roamMonsAfterLoad(CONNECTION), "no roamers, no walk")
  check(not world:roamMonsBeforeLoad(TELEPORT), "no roamers, no jump")
  check(not world:roamMonsAfterBattle(nil, "win", 0), "and no battle tail")
  check(not world:roamMonsOnContinue("ROUTE_29"), "and no scatter on CONTINUE")
end

-- ---------------------------------------------------------------------------
-- The third call site: CONTINUE
-- ---------------------------------------------------------------------------
--
-- `farcall JumpRoamMons` sits in the continue path itself
-- (engine/menus/intro_menu.asm, three lines above the wSpawnAfterChampion
-- read), not in any map setup script -- so EVERY load of a save scatters the
-- three beasts before the map comes back.  That is what makes re-finding one
-- the price of reloading after a failed catch; without it a save-scum loop was
-- strictly easier than the cart's.
do
  local world, game = roamWorld()
  for _, slot in ipairs(game.save.roamers) do slot.map = "ROUTE_29" end
  -- JumpRoamMon re-rolls while the entry it lands on is the PLAYER's map, so
  -- a scatter can never drop a beast on top of the file being loaded.
  local calls = 0
  world.roamerRandom = function(n)
    calls = calls + 1
    return (calls * 5) % n
  end
  check(world:roamMonsOnContinue("ROUTE_29"), "loading a save scatters them")
  for index, slot in ipairs(game.save.roamers) do
    check(slot.map ~= "ROUTE_29",
      "beast " .. index .. " is no longer where the file was saved")
  end
  eq(game.save.roamerMaps.current, "ROUTE_29",
    "_BackUpMapIndices banks the saved map, which is what the next walk avoids")
end

-- ---------------------------------------------------------------------------
-- RoamMaps off the cart
-- ---------------------------------------------------------------------------
--
-- data/wild/roammon_maps.asm, which RomExtractorGen2 emits as
-- encounters.roamMaps.  The test fixture has to agree with it row for row --
-- ORDER included, since `.Update` picks a connection by a two-bit index and
-- JumpRoamMon picks an entry by a four-bit one.
do
  local cache = os.getenv("GOLD_CACHE")
  if not cache then
    local home = os.getenv("HOME") or ""
    cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local chunk = loadfile(cache .. "/data/generated/encounters.lua")
  local encounters = chunk and chunk()
  if not (encounters and encounters.roamMaps) then
    check(true, "no gold cache: extracted RoamMaps (SKIP)")
  else
    local extracted = encounters.roamMaps
    eq(#extracted, Roamers.NUM_MAPS, "RoamMaps has NUM_ROAMMON_MAPS entries")
    check(Roamers.mapTable(encounters) == extracted,
      "and Roamers.mapTable reads it")
    local same = true
    for index, row in ipairs(RoamFixture.ROAM_MAPS) do
      local got = extracted[index]
      if not got or got.map ~= row.map or #got.to ~= #row.to then
        same = false
      else
        for i, to in ipairs(row.to) do
          if got.to[i] ~= to then same = false end
        end
      end
    end
    check(same, "every row matches the fixture, in order")
    local roster = Roamers.roster(encounters)
    eq(#roster, 3, "Gold's InitRoamMons seeds three beasts")
    for index, row in ipairs(RoamFixture.ROAM_MONS_GOLD) do
      eq(roster[index] and roster[index].species, row.species,
        ("roamer %d is %s"):format(index, row.species))
      eq(roster[index] and roster[index].map, row.map,
        ("starting on %s"):format(row.map))
      eq(roster[index] and roster[index].level, row.level, "at level 40")
    end
    -- Routes 40 and 41 are water routes and deliberately absent.
    local seen = {}
    for _, row in ipairs(extracted) do seen[row.map] = true end
    check(not seen.ROUTE_40, "Route 40 is not a roam map")
    check(not seen.ROUTE_41, "and neither is Route 41")
  end
end

-- ---------------------------------------------------------------------------
-- CheckEncounterRoamMon at the top of the wild roll
-- ---------------------------------------------------------------------------

-- WHERE the gate sits matters as much as what it tests.  CheckEncounterRoamMon
-- is the first thing ChooseWildEncounter does, and ChooseWildEncounter is only
-- reached once TryWildEncounter's own `.EncounterRate` roll has passed
-- (engine/overworld/wildmons.asm) -- so a beast needs the map's percentage AND
-- 75/256 AND its own route.  A table with an always-passing rate and no slots
-- is what isolates the beast from the map's own list below.
local ALWAYS = {
  grass = {
    ROUTE_29 = {
      map = "ROUTE_29",
      rates = { MORN = 256, DAY = 256, NITE = 256 },
      slots = { MORN = {}, DAY = {}, NITE = {} },
    },
  },
  water = {
    ROUTE_29 = { map = "ROUTE_29", rate = 256, slots = {} },
  },
}

-- The gate is three tests on ONE random byte: < 100, then `and %11` non-zero,
-- then that value is the slot.  1 picks slot 1, which is Raikou -- and Raikou
-- starts on ROUTE_42, so it only fires on the map the beast is actually on.
do
  local world, game = roamWorld({ encounters = ALWAYS })
  world.roamerRandom = function() return 1 end -- slot 1, past both gates
  game.save.party = { { species = "RAIKOU", level = 5, hp = 10, maxHp = 10 } }
  world.player = { cellX = 0, cellY = 0 }
  world.map.cellCollision = function() return 0x18 end -- COLL_TALL_GRASS
  world.map.def.environment = "ROUTE"

  local started
  world.startBattle = function(_, opts) started = opts return true end

  -- Raikou is on ROUTE_42 and the player is on ROUTE_29: no beast.
  check(not world:tryWildEncounter() or started == nil,
    "a beast on another route does not fire")
  check(started == nil, "and no battle started off it")

  -- Move it under the player's feet.
  game.save.roamers[1].map = "ROUTE_29"
  check(world:tryWildEncounter(), "the beast on this route fires")
  check(started ~= nil, "and it started a battle")
  eq(started.roaming, 1, "carrying the SLOT, which is what banks its HP")
  eq(started.wild.species, "RAIKOU", "with the right beast")
  eq(started.wild.level, 40, "at the roam level")
  check(game.save.pokedex.seen.RAIKOU, "and the #DEX saw it")
  check(game.save.roamers[1].hp > 0,
    ".InitRoamHP banks the full HP on the FIRST meeting, not at the end")
end

-- The outer gate, pinned on its own: the SAME roamer roll that fires above
-- produces nothing at all on a map whose encounter rate is zero, because
-- ChooseWildEncounter is never reached.  Reading these two in the other order
-- (roamer first, rate second) is what made a beast turn up roughly ten times
-- as often per grass step as the cart allows on a 10 percent route.
do
  local world, game = roamWorld({
    encounters = {
      grass = { ROUTE_29 = { map = "ROUTE_29",
        rates = { MORN = 0, DAY = 0, NITE = 0 },
        slots = { MORN = {}, DAY = {}, NITE = {} } } },
    },
  })
  world.roamerRandom = function() return 1 end
  game.save.roamers[1].map = "ROUTE_29"
  game.save.party = { { species = "RAIKOU", level = 5, hp = 10, maxHp = 10 } }
  world.player = { cellX = 0, cellY = 0 }
  world.map.cellCollision = function() return 0x18 end
  world.map.def.environment = "ROUTE"
  local started
  world.startBattle = function(_, opts) started = opts return true end
  check(not world:tryWildEncounter(),
    "a zero encounter rate stops the step before ChooseWildEncounter")
  check(started == nil, "so the beast standing right there never rolls")
end

-- Surfing refuses before anything else, which is what keeps Suicune out of the
-- water on the routes it shares with the sea.
do
  local world, game = roamWorld({ encounters = ALWAYS })
  world.roamerRandom = function() return 1 end
  game.save.roamers[1].map = "ROUTE_29"
  game.save.party = { { species = "RAIKOU", level = 5, hp = 10, maxHp = 10 } }
  world.player = { cellX = 0, cellY = 0 }
  world.map.cellCollision = function() return 0x29 end -- COLL_WATER
  world.map.def.environment = "ROUTE"
  world.playerState = FieldMoves.PLAYER_SURF
  local started
  world.startBattle = function(_, opts) started = opts return true end
  world:tryWildEncounter()
  check(started == nil or not started.roaming,
    "a surfing step never meets a beast")
end

-- ---------------------------------------------------------------------------
-- BattleEnd_HandleRoamMons
-- ---------------------------------------------------------------------------

do
  -- Beating one clears its slot for good: no species, no map.
  local world, game = roamWorld()
  game.save.roamers[1].hp = 90
  check(world:roamMonsAfterBattle(1, "win", 0), "a won roam battle is handled")
  check(not Roamers.active(game.save.roamers[1]), "and the beast is gone")

  -- Catching one is the same clear.
  local w2, g2 = roamWorld()
  g2.save.roamers[2].hp = 90
  w2:roamMonsAfterBattle(2, "caught", 40)
  check(not Roamers.active(g2.save.roamers[2]), "a caught beast is gone too")

  -- Anything else -- it fled, you ran -- banks the HP and moves it.
  local w3, g3 = roamWorld()
  g3.save.roamers[1].map = "ROUTE_29"
  g3.save.roamers[1].hp = 90
  -- 1: `% 32` is non-zero so .Update takes a CONNECTION rather than the
  -- 1-in-32 jump, and `% 4` is 1, which is Route 29's second exit.
  w3.roamerRandom = function() return 1 end
  check(w3:roamMonsAfterBattle(1, "run", 37), "a flee is handled")
  eq(g3.save.roamers[1].hp, 37, "and the damage is banked")
  check(Roamers.active(g3.save.roamers[1]), "with the beast still out there")
  check(g3.save.roamers[1].map ~= "ROUTE_29", "and moved off the player's route")
end

-- The `.not_roaming` tail: ANY other wild battle gives one chance in sixteen
-- that they all move, which is why they drift while you grind.
do
  local world, game = roamWorld()
  local rolls = { 0 } -- 0 % 16 == 0, the one case in sixteen
  world.roamerRandom = function() return table.remove(rolls, 1) or 5 end
  local before = game.save.roamers[1].map
  check(world:roamMonsAfterBattle(nil, "win", 0), "the 1-in-16 roll can move them")
  check(game.save.roamerMaps ~= nil, "and it backs the map indices up")
  local _ = before

  local w2, g2 = roamWorld()
  w2.roamerRandom = function() return 5 end -- 5 % 16 ~= 0
  local was = g2.save.roamers[1].map
  check(not w2:roamMonsAfterBattle(nil, "win", 0), "fifteen times in sixteen it does not")
  eq(g2.save.roamers[1].map, was, "and nothing moved")
end

S.finish()
