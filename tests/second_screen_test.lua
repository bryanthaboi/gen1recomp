package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness").suite("second screen")
local Growth = require("src.pokemon.Growth")
local SecondScreen = require("src.core.SecondScreen")

local Data = {
  pokemon = {
    BULBASAUR = { name = "BULBASAUR", growthRate = "MEDIUM_SLOW" },
    PIDGEY = { name = "PIDGEY", growthRate = "MEDIUM_SLOW" },
  },
  maps = { PALLET_TOWN = { label = "PalletTown" } },
  field = {
    townMap = { locations = { PALLET_TOWN = { name = "Pallet Town" } } },
  },
  constants = {
    badges = {
      { id = "BOULDERBADGE" }, { id = "CASCADEBADGE" },
      { id = "THUNDERBADGE" }, { id = "RAINBOWBADGE" },
      { id = "SOULBADGE" }, { id = "MARSHBADGE" },
      { id = "VOLCANOBADGE" }, { id = "EARTHBADGE" },
    },
  },
}
local bulbasaur = {
  species = "BULBASAUR", level = 10,
  exp = Growth.expForLevel("MEDIUM_SLOW", 10),
  stats = { hp = 30 }, hp = 15, status = "PSN",
}

local overworld = {}
local game = {
  data = Data,
  save = {
    version = "red",
    player = { name = "RED", map = "PALLET_TOWN", x = 5, y = 6 },
    inventory = { BOULDERBADGE = 1 },
    party = { bulbasaur },
    money = 1234,
  },
  overworld = overworld,
  stack = { states = { overworld } },
}

local snap = SecondScreen.snapshot(game)
T.eq(snap.playerName, "RED", "trainer name")
T.eq(snap.location, "Pallet Town", "friendly location name")
T.eq(snap.context, "exploring", "overworld context")
T.eq(#snap.party, 1, "party count")
T.eq(snap.party[1].name, "BULBASAUR", "species display name")
T.eq(snap.party[1].status, "PSN", "status")
T.eq(snap.party[1].hp, bulbasaur.hp, "live HP")
T.eq(snap.party[1].expToNext,
     Growth.expForLevel("MEDIUM_SLOW", 11) - bulbasaur.exp,
     "experience remaining")
T.check(snap.badges[1].earned, "earned badge")
T.check(not snap.badges[2].earned, "unearned badge")

game.stack.states = {}
snap = SecondScreen.snapshot(game)
T.eq(snap.context, "menu", "title/menu context")
T.eq(snap.location, "Main Menu", "menu has no stale map")

local enemy = {
  species = "PIDGEY", level = 4,
  exp = Growth.expForLevel("MEDIUM_SLOW", 4),
  stats = { hp = 18 }, hp = 18,
}
game.stack.states = {
  { player = { mon = bulbasaur }, enemy = { mon = enemy }, kind = "wild" },
}
snap = SecondScreen.snapshot(game)
T.eq(snap.context, "battle", "battle context")
T.eq(snap.battle.enemy.name, "PIDGEY", "battle opponent")
T.eq(snap.battle.enemy.level, 4, "opponent level")

T.finish()
