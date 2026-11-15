-- ../pokecrystal/data/wild/treemons.asm:1 TreeMons
-- ../pokecrystal/data/wild/treemons_asleep.asm:3 AsleepTreeMonsNite

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Extractor = require("src.import.RomExtractorGen2")
local Encounter = require("src.battle.gen2.Encounter")

local SPEAROW, AIPOM, HERACROSS = 21, 190, 214
local KRABBY, SHUCKLE = 98, 213
local CATERPIE, HOOTHOOT = 10, 163

local SPECIES = {
  [SPEAROW] = "SPEAROW", [AIPOM] = "AIPOM", [HERACROSS] = "HERACROSS",
  [KRABBY] = "KRABBY", [SHUCKLE] = "SHUCKLE",
  [CATERPIE] = "CATERPIE", [HOOTHOOT] = "HOOTHOOT",
}

local function fakeRom(banks)
  local rom = {}
  function rom:byte(bank, address)
    return (banks[bank] or {})[address] or 0
  end
  function rom:word(bank, address)
    return self:byte(bank, address) + self:byte(bank, address + 1) * 0x100
  end
  return rom
end

local function put(bytes, at, ...)
  for index, b in ipairs({ ... }) do bytes[at + index - 1] = b end
  return at + select("#", ...)
end

do
  local bank = {}
  local TABLE, CANYON, ROCK = 0x42e8, 0x4300, 0x43de
  put(bank, TABLE,
    CANYON % 256, math.floor(CANYON / 256),
    CANYON % 256, math.floor(CANYON / 256),
    ROCK % 256, math.floor(ROCK / 256))
  local at = put(bank, CANYON, 50, SPEAROW, 10, 50, AIPOM, 10, 0xff)
  put(bank, at, 50, SPEAROW, 10, 50, HERACROSS, 10, 0xff)
  at = put(bank, ROCK, 90, KRABBY, 15, 10, SHUCKLE, 15, 0xff)
  -- ../pokecrystal/engine/events/treemons.asm:126 GetTreeMon
  put(bank, at, 0xe5, 0xcd, 0x99, 0x43, 0xe1, 0xa7, 0x28, 0x08, 0xfe, 0x01,
    0x28, 0x0e, 0xfe, 0x02, 0x28, 0x16, 0xc9, 0x3e, 0x0a, 0xcd)

  local extractor = setmetatable({
    rom = fakeRom({ [0x2e] = bank }),
    edition = "crystal",
    symbols = { TreeMons = { 0x2e, TABLE } },
    manifest = { constants = {
      treeMonSetOrder = { "TREEMON_SET_NONE", "TREEMON_SET_CANYON",
                          "TREEMON_SET_ROCK" },
      speciesOrder = SPECIES,
    } },
  }, Extractor)

  local sets = extractor:readTreeMons()
  local canyon = sets.TREEMON_SET_CANYON
  eq(#canyon.common, 2, "a headbutt set reads its common list")
  eq(canyon.common[1].species, "SPEAROW", "first common row")
  eq(canyon.common[2].level, 10, "with its level")
  eq(#canyon.rare, 2, "and its rare list")
  eq(canyon.rare[2].species, "HERACROSS", "the rare row past the -1")

  local rock = sets.TREEMON_SET_ROCK
  eq(#rock.common, 2, "TREEMON_SET_ROCK is the 90/10 list")
  eq(rock.common[1].species, "KRABBY", "KRABBY")
  eq(rock.common[1].chance, 90, "at 90")
  eq(rock.common[2].species, "SHUCKLE", "SHUCKLE")
  eq(rock.rare, nil,
    "and no second list: the bytes after its -1 are GetTreeMon's code")
end

do
  local encounters = {
    trees = { ROCKY = "TREEMON_SET_ROCK" },
    treeSets = { TREEMON_SET_ROCK = {
      common = { { chance = 100, species = "KRABBY", level = 15 } } } },
  }
  eq(Encounter.treeScore(0, 0, 4), Encounter.TREEMON_SCORE_RARE,
    "coords (0,0) with OT id 4 score RARE")
  eq(Encounter.treeSlot(encounters, "ROCKY", 0, 0, function() return 0 end,
      { otId = 4, engine = "crystal" }), nil,
    "a RARE roll against a one-list set answers nothing rather than erroring")
end

do
  local bank = {}
  local NITE, DAY, MORN = 0x6b5d, 0x6b69, 0x6b6f
  put(bank, NITE, CATERPIE, SPEAROW, 0xff)
  put(bank, DAY, HOOTHOOT, 0xff)
  put(bank, MORN, HOOTHOOT, HERACROSS, 0xff)
  local symbols = {
    AsleepTreeMonsNite = { 0x0f, NITE },
    AsleepTreeMonsDay = { 0x0f, DAY },
    AsleepTreeMonsMorn = { 0x0f, MORN },
  }
  local extractor = setmetatable({
    rom = fakeRom({ [0x0f] = bank }),
    edition = "crystal",
    symbols = symbols,
    manifest = { constants = { speciesOrder = SPECIES } },
  }, Extractor)
  local asleep = extractor:readAsleepTreeMons()
  eq(#asleep.NITE, 2, "Nite list length")
  eq(asleep.NITE[1], "CATERPIE", "Nite[1]")
  eq(asleep.NITE[2], "SPEAROW", "Nite[2]")
  eq(asleep.DAY[1], "HOOTHOOT", "Day[1]")
  eq(#asleep.DAY, 1, "Day list length")
  eq(asleep.MORN[2], "HERACROSS", "Morn[2]")

  local gold = setmetatable({
    rom = fakeRom({}), edition = "gold",
    symbols = { AsleepTreeMonsNite = { 0x0f, NITE } },
    manifest = { constants = { speciesOrder = SPECIES } },
  }, Extractor)
  check(not pcall(gold.readAsleepTreeMons, gold),
    "a manifest without all three labels is an error, not an empty list")
end

-- ../pokecrystal/engine/battle/core.asm:6422 CheckSleepingTreeMon
do
  local encounters = { treeMonsAsleep = {
    NITE = { "SPEAROW" }, DAY = { "HOOTHOOT" }, MORN = { "AIPOM" } } }
  eq(Encounter.treeMonAsleep("SPEAROW", "NITE", "crystal", encounters), true,
    "the extracted Nite list is read")
  eq(Encounter.treeMonAsleep("SPEAROW", "DARK", "crystal", encounters), true,
    "DARKNESS_F falls through to Nite")
  eq(Encounter.treeMonAsleep("SPEAROW", "DAY", "crystal", encounters), false,
    "and SPEAROW is awake by day")
  eq(Encounter.treeMonAsleep("AIPOM", "MORN", "crystal", encounters), true,
    "the Morn list is its own")
  eq(Encounter.treeMonAsleep("AIPOM", "DAY", "crystal", encounters), false,
    "and not the Day list")
  eq(Encounter.treeMonAsleep("HOOTHOOT", "DAY", "gs", encounters), false,
    "pokegold never sleeps a tree mon")

  local empty = { treeMonsAsleep = { NITE = {}, DAY = {}, MORN = {} } }
  eq(Encounter.treeMonAsleep("SPEAROW", "NITE", "crystal", empty), false,
    "only the extracted list is read")
  check(Encounter.ASLEEP_TREEMONS == nil, "no hand-typed asleep table")
  check(not pcall(Encounter.treeMonAsleep, "SPEAROW", "NITE", "crystal", nil),
    "a crystal cache without treeMonsAsleep is an error")
  check(not pcall(Encounter.treeMonAsleep, "SPEAROW", "NITE", "crystal", {}),
    "and so is an encounters table missing it")
  check(not pcall(Encounter.treeMonAsleep, "SPEAROW", "MORN", "crystal",
      { treeMonsAsleep = { NITE = {}, DAY = {} } }),
    "and a list missing one time of day")
end

do
  local encounters = { trees = { ROCKY = "TREEMON_SET_ROCK" } }
  check(not pcall(Encounter.treeSlot, encounters, "ROCKY", 0, 0,
      function() return 0 end, { otId = 4, engine = "crystal" }),
    "a tree map with no treeSets is an error, not a bite of nothing")
  encounters.treeSets = {}
  check(not pcall(Encounter.treeSlot, encounters, "ROCKY", 0, 0,
      function() return 0 end, { otId = 4, engine = "crystal" }),
    "and so is a usable set missing from treeSets")
end

do
  local encounters = {
    fishGroups = { POND = { old = { { chance = 255, timeGroup = 3 } } } },
  }
  check(not pcall(Encounter.fish, encounters, "POND", "old", "DAY",
      function() return 0 end),
    "a time_group row with no timeFishGroups is an error")
  encounters.timeFishGroups = {}
  check(not pcall(Encounter.fish, encounters, "POND", "old", "DAY",
      function() return 0 end),
    "and so is one whose group is missing")
  encounters.timeFishGroups[3] = { day = { species = "SHELLDER", level = 20 },
    nite = { species = "SHELLDER", level = 20 } }
  eq((Encounter.fish(encounters, "POND", "old", "NITE",
      function() return 0 end) or {}).species, "SHELLDER",
    "the extracted group is read")
  check(not pcall(Encounter.fishGroupFor, encounters, "FISHGROUP_QWILFISH",
      Encounter.FISHSWARM_QWILFISH),
    "a swarm with no swarm group in the cache is an error")
end

T.finish("gen2 treemon extract bug2043")
