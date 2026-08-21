-- ROCK SMASH's wild encounter (engine/events/treemons.asm RockMonEncounter).
--
--   luajit tests/gen2_rock_smash_test.lua
--
-- The smash itself already worked: an object carrying SPRITEMOVEDATA_SMASHABLE_
-- ROCK runs `jumpstd SmashRockScript`, which farsjumps AskRockSmashScript and
-- then RockSmashScript, and the rock disappears.  What never happened was the
-- BATTLE at the end of it, because RockMonEncounter was a deliberate stub and
-- RockMonMaps was not extracted -- so the `readmem wTempWildMonSpecies` two
-- rows later read the VM's own sparse store, saw 0, and the `iffalse` skipped
-- the `randomwildmon / startbattle` pair every single time.  No wild mon has
-- ever come out of a rock in this port, which also makes wild SHUCKLE
-- unobtainable.
--
-- The routine is TreeMonEncounter's twin over a different map table:
--
--   GetTreeMonSet RockMonMaps    CIANWOOD_CITY, ROUTE_40,
--                                DARK_CAVE_VIOLET_ENTRANCE, SLOWPOKE_WELL_B1F
--   GetTreeMons                  TREEMON_SET_ROCK
--   RandomRange 10 / cp 4        40 percent, BETWEEN the lookup and the pick
--   SelectTreeMon                the set's FIRST list: 90 KRABBY / 10 SHUCKLE
--
-- and it writes no wScriptVar at all, which is why the script reads its answer
-- out of WRAM instead.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 rock smash")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")
local CallAsm = require("src.script.gen2.CallAsm")

-- The site the cart's RockSmashScript carries, `bank:addr` out of
-- pokegold-symbols/pokegold.sym.
eq(CallAsm.SITES["2e:63a1"], "RockMonEncounter",
  "RockMonEncounter still sits at 2e:63a1")
check(CallAsm.HANDLERS.RockMonEncounter ~= nil,
  "and it is a handler now, not a stub")
check(CallAsm.STUBS.RockMonEncounter == nil, "with no stub left behind it")
eq(CallAsm.STUB_REASONS.RockMonEncounter, nil, "nor a stub reason")

local DATA = {
  items = {},
  moves = { TACKLE = { name = "TACKLE", pp = 35 } },
  pokemon = {
    KRABBY = { name = "KRABBY", index = 98, types = { "WATER", "WATER" },
      baseStats = { hp = 30, attack = 105, defense = 90, speed = 50,
        specialAttack = 25, specialDefense = 25 },
      growthRate = 0, levelMoves = { { level = 1, move = "TACKLE" } } },
    SHUCKLE = { name = "SHUCKLE", index = 213, types = { "BUG", "ROCK" },
      baseStats = { hp = 20, attack = 10, defense = 230, speed = 5,
        specialAttack = 10, specialDefense = 230 },
      growthRate = 0, levelMoves = { { level = 1, move = "TACKLE" } } },
    GEODUDE = { name = "GEODUDE", index = 74, types = { "ROCK", "GROUND" },
      baseStats = { hp = 40, attack = 80, defense = 100, speed = 20,
        specialAttack = 30, specialDefense = 30 },
      growthRate = 0, levelMoves = { { level = 1, move = "TACKLE" } } },
  },
}

-- data/wild/treemons.asm TreeMonSet_Rock, and one grass row for the same map so
-- a mis-wired `randomwildmon` would be visible as a GEODUDE rather than as
-- nothing.
local ENCOUNTERS = {
  rocks = { DARK_CAVE_VIOLET_ENTRANCE = "TREEMON_SET_ROCK" },
  treeSets = {
    TREEMON_SET_ROCK = {
      common = { { chance = 90, species = "KRABBY", level = 15 },
        { chance = 10, species = "SHUCKLE", level = 15 } },
      rare = { { chance = 100, species = "GEODUDE", level = 3 } },
    },
  },
  grass = {
    DARK_CAVE_VIOLET_ENTRANCE = { map = "DARK_CAVE_VIOLET_ENTRANCE",
      rates = { MORN = 256, DAY = 256, NITE = 256 },
      slots = { MORN = {}, DAY = {}, NITE = {} } },
  },
}

local function rockWorld(mapId)
  local game = {
    data = DATA,
    save = { player = { name = "GOLD", badges = {} },
      party = { { species = "GEODUDE", level = 20, hp = 30, maxHp = 30 } },
      inventory = {} },
  }
  local world = World.new(game)
  game.world = world
  world.maps = { [mapId] = { id = mapId, group = 3, map = 1, width = 2,
    height = 2, blocks = { 1, 2, 3, 4 }, objects = {}, warps = {},
    environment = "CAVE" } }
  world.map = { id = mapId, def = world.maps[mapId], width = 2, height = 2,
    cellCollision = function() return 0 end }
  world.encounters = ENCOUNTERS
  world.player = { cellX = 0, cellY = 0 }
  world.daytime = "DAY"
  return world
end

-- constants/pokemon_constants.asm, the indices `startbattle` fights by.
local KRABBY_INDEX, SHUCKLE_INDEX = 98, 213

-- ---- the 40 percent --------------------------------------------------------
--
-- `ld a, 10 / call RandomRange / cp 4 / jr nc, .no_battle`: 0..3 of ten.  The
-- roll is taken BEFORE SelectTreeMon, so a miss costs nothing else.
do
  local world = rockWorld("DARK_CAVE_VIOLET_ENTRANCE")
  local rolls = {}
  world.rockmonRandom = function(n) rolls[#rolls + 1] = n return 4 end
  eq(world:rockMonEncounter(), 0, "a 4 out of ten is no encounter")
  eq(#rolls, 1, "and the list is never even rolled on")
  check(world.tempWildMon == nil, "wTempWildMonSpecies is left at zero")

  world.rockmonRandom = function() return 9 end
  eq(world:rockMonEncounter(), 0, "and so is a 9")
end

do
  local world = rockWorld("DARK_CAVE_VIOLET_ENTRANCE")
  -- 3 passes `cp 4`, and 3 lands in the 90 percent KRABBY bracket.
  world.rockmonRandom = function() return 3 end
  eq(world:rockMonEncounter(), KRABBY_INDEX,
    "a 3 out of ten smashes a KRABBY out of the rock")
  eq(world.tempWildMon.level, 15, "at TreeMonSet_Rock's own level")

  -- SelectTreeMon walks the chance column as a running total, so only a roll
  -- of 90..99 reaches the SHUCKLE row.
  local calls = 0
  world.rockmonRandom = function()
    calls = calls + 1
    return calls == 1 and 0 or 95
  end
  eq(world:rockMonEncounter(), SHUCKLE_INDEX,
    "and a 95 out of a hundred reaches the 10 percent SHUCKLE")
end

-- GetTreeMonSet's `.not_in_table`: a map RockMonMaps does not name has no rock
-- mon however hard it is hit.
do
  local world = rockWorld("ROUTE_31")
  world.rockmonRandom = function() return 0 end
  eq(world:rockMonEncounter(), 0, "a map outside RockMonMaps yields nothing")
end

-- ---- the WRAM byte the script reads back -----------------------------------
--
-- RockSmashScript is `callasm RockMonEncounter / readmem wTempWildMonSpecies /
-- iffalse .done / randomwildmon / startbattle`.  The port's VM keeps its own
-- sparse store for the addresses a SCRIPT owns; $d117 is one the ENGINE owns,
-- so World answers for it and the `iffalse` sees the byte that was just
-- written.
do
  local world = rockWorld("DARK_CAVE_VIOLET_ENTRANCE")
  eq(world:scriptReadMem(0xd117), 0, "nothing smashed reads back as zero")
  eq(world:scriptReadMem(0xd6a8), nil,
    "and an address the World does not own stays the VM's own")
  world.rockmonRandom = function() return 3 end
  world:rockMonEncounter()
  eq(world:scriptReadMem(0xd117), KRABBY_INDEX,
    "a hit reads back as the species the iffalse branches on")

  -- Script_randomwildmon only clears wBattleScriptFlags; the pair `startbattle`
  -- fights is the one already staged.  Reading the map's grass list here
  -- instead would have fought whatever Dark Cave holds, not the rock's mon.
  local rolled = world:rollWild()
  eq(rolled and rolled.species, KRABBY_INDEX,
    "randomwildmon takes the staged pair rather than rolling the grass")
  eq(rolled and rolled.level, 15, "at the level the rock rolled")
  eq(world:scriptReadMem(0xd117), 0, "and the byte is consumed by the battle")
end

-- CallAsm.run is the entry point World:callAsm reaches, and the handler must
-- leave wScriptVar alone: the cart's routine writes none.
do
  local world = rockWorld("DARK_CAVE_VIOLET_ENTRANCE")
  world.rockmonRandom = function() return 3 end
  eq(CallAsm.run(world, "RockMonEncounter"), nil,
    "the handler returns no wScriptVar, exactly as the asm does not write one")
  eq(world:scriptReadMem(0xd117), KRABBY_INDEX,
    "but it did stage the mon")
  eq(CallAsm.dispatch(world, nil, 0x2e, 0x63a1), nil,
    "and dispatching by the script's own bank:addr reaches the same routine")
end

-- ---- the real script rows, out of the cache --------------------------------
do
  local cache = os.getenv("GOLD_CACHE")
  if not cache then
    local home = os.getenv("HOME") or ""
    cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local scriptChunk = loadfile(cache .. "/data/generated/scripts.lua")
  local encChunk = loadfile(cache .. "/data/generated/encounters.lua")
  if not (scriptChunk and encChunk) then
    check(true, "no gold cache: RockSmashScript rows (SKIP)")
  else
    local scripts = scriptChunk()
    local encounters = encChunk()
    local rows, scriptKey
    for key, list in pairs(scripts) do
      if type(list) == "table" then
        for _, cmd in ipairs(list) do
          local args = cmd.args or {}
          local addr = (args[2] or 0) + (args[3] or 0) * 256
          if cmd.op == "callasm"
              and CallAsm.nameFor(cmd.label, args[1], addr)
                == "RockMonEncounter" then
            rows, scriptKey = list, key
            break
          end
        end
      end
      if rows then break end
    end
    check(rows ~= nil,
      "RockSmashScript is found by its RockMonEncounter callasm target")
    check(scriptKey == "03:4f35" or scriptKey == "03:4f33",
      "the script key belongs to the Gold or Silver cartridge revision")
    eq(rows and rows[9] and rows[9].op, "callasm",
      "row 9 is the callasm this suite is about")
    eq(rows and rows[9] and rows[9].args and rows[9].args[1], 0x2e,
      "in bank $2e")
    eq(rows and rows[10] and rows[10].op, "readmem", "row 10 reads the byte")
    local args = rows and rows[10] and rows[10].args
    eq(args and (args[1] + args[2] * 256), 0xd117,
      "and the address it reads is wTempWildMonSpecies")
    eq(rows and rows[11] and rows[11].op, "iffalse", "row 11 branches on it")
    eq(rows and rows[12] and rows[12].op, "randomwildmon",
      "row 12 is the randomwildmon that takes the staged pair")
    eq(rows and rows[13] and rows[13].op, "startbattle", "row 13 fights it")

    -- RockMonMaps, straight off the cart now.
    local rocks = encounters.rocks or {}
    eq(rocks.CIANWOOD_CITY, "TREEMON_SET_ROCK", "RockMonMaps: Cianwood")
    eq(rocks.ROUTE_40, "TREEMON_SET_ROCK", "Route 40")
    eq(rocks.DARK_CAVE_VIOLET_ENTRANCE, "TREEMON_SET_ROCK",
      "Dark Cave Violet Entrance")
    eq(rocks.SLOWPOKE_WELL_B1F, "TREEMON_SET_ROCK", "and Slowpoke Well B1F")
    local rockSet = encounters.treeSets and encounters.treeSets.TREEMON_SET_ROCK
    eq(rockSet and rockSet.common[1].species, "KRABBY", "90 percent KRABBY")
    eq(rockSet and rockSet.common[2].species, "SHUCKLE",
      "and 10 percent SHUCKLE, the only wild SHUCKLE in the game")
  end
end

S.finish()
