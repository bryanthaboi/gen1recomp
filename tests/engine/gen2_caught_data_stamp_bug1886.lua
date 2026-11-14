-- engine/pokemon/caught_data.asm:72-81, :163-233

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Breeding = require("src.core.gen2.Breeding")
local Catching = require("src.battle.gen2.Catching")
local Mon = require("src.battle.gen2.Mon")
local NpcTrade = require("src.core.gen2.NpcTrade")
local UI = require("src.ui.gen2.BattleState")
local World = require("src.world.gen2.World")

local NEW_BARK = 1
local ROUTE_29 = 2

local POKEMON = {
  growthRates = {
    GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
      linear = 0, constant = 0 },
  },
  RATTATA = {
    id = "RATTATA", index = 19, name = "RATTATA",
    baseStats = { hp = 30, attack = 56, defense = 35, speed = 72,
      specialAttack = 25, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 51,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  DODRIO = {
    id = "DODRIO", index = 85, name = "DODRIO",
    baseStats = { hp = 60, attack = 110, defense = 70, speed = 100,
      specialAttack = 60, specialDefense = 60 },
    types = { "NORMAL", "FLYING" }, catchRate = 45, baseExp = 158,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = { TACKLE = { id = "TACKLE", name = "TACKLE", power = 35,
    type = "NORMAL", accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" } },
  type_chart = { types = {}, matchups = {} },
  items = {},
  text = { _BallSentToPCText = "{STRBUF} was\nsent to BILL's PC.{PROMPT}" },
}

local function newSave(version, gender)
  return {
    version = version, party = {},
    player = { name = "KRIS", id = 4242, gender = gender or "female" },
    pokedex = { seen = {}, caught = {} },
  }
end

local function newWorld()
  return {
    tod = "NITE",
    maps = {
      ROUTE_29 = { id = "ROUTE_29", landmark = ROUTE_29 },
      NEW_BARK_TOWN = { id = "NEW_BARK_TOWN", landmark = NEW_BARK },
    },
    map = { def = { id = "ROUTE_29", landmark = ROUTE_29 } },
    timeOfDayId = World.timeOfDayId,
  }
end

local function newState(save, world, opts)
  opts = opts or {}
  return setmetatable({
    save = save, queue = {},
    battle = { timeOfDay = opts.timeOfDay },
    contest = opts.contest,
    game = { save = save, data = DATA, world = world },
  }, { __index = UI })
end

do
  local save = newSave("crystal", "female")
  local state = newState(save, newWorld(), { timeOfDay = 1 })
  local enemy = { species = "RATTATA", level = 4 }
  state:pushCaught(enemy, "POKE_BALL")
  T.eq(save.party[1], enemy, "the catch joins the party")
  T.eq(enemy.caughtTime, 2, "wTimeOfDay DAY stores as 2")
  T.eq(enemy.caughtLevel, 4, "the level rides the same byte")
  T.eq(enemy.caughtLocation, ROUTE_29, "the map header's landmark")
  T.eq(enemy.caughtByGender, "girl", "wPlayerGender bit 0 on bit 7")
end

do
  local save = newSave("crystal", "male")
  for i = 1, 6 do save.party[i] = { species = "RATTATA", level = 5 } end
  local state = newState(save, newWorld(), { timeOfDay = 0 })
  local enemy = { species = "RATTATA", level = 7 }
  state:pushCaught(enemy, "POKE_BALL")
  T.eq(#save.party, 6, "a full party sends the catch to the PC")
  T.eq(enemy.caughtTime, 1, "MORN stores as 1, so 0 stays 'unknown'")
  T.eq(enemy.caughtByGender, "boy", "a male player stamps CAUGHT_BY_BOY")
  T.eq(enemy.caughtLocation, ROUTE_29, "and the same landmark")
end

do
  local save = newSave("crystal", "female")
  local state = newState(save, newWorld())
  local enemy = { species = "RATTATA", level = 4 }
  state:pushCaught(enemy, "POKE_BALL")
  T.eq(enemy.caughtTime, 3, "NITE stores as 3")
end

do
  local save = newSave("gold", "male")
  local state = newState(save, newWorld(), { timeOfDay = 1 })
  local enemy = { species = "RATTATA", level = 4 }
  state:pushCaught(enemy, "POKE_BALL")
  T.eq(enemy.caughtTime, nil, "Gold stamps no caught time")
  T.eq(enemy.caughtByGender, nil, "and no OT gender")
  T.eq(enemy.caughtLocation, nil, "and no landmark")
end

do
  local save = newSave("crystal", "female")
  local state = newState(save, newWorld(), { timeOfDay = 1, contest = true })
  local enemy = { species = "RATTATA", level = 9 }
  state:pushCaught(enemy, "PARK_BALL")
  T.eq(save.bugContest.caught, enemy, "the contest only HOLDS the catch")
  T.eq(enemy.caughtLocation, Catching.LANDMARK_NATIONAL_PARK,
    "the location is rewritten to the park")
  T.eq(enemy.caughtByGender, "girl", "and the gender bit survives the rewrite")
  T.eq(enemy.caughtTime, 2, "the time byte is the plain SetCaughtData one")
end

do
  local world = newWorld()
  world.map = { def = { id = "POKECENTER_2F", landmark = 0x7f } }
  world.backupMapId = "NEW_BARK_TOWN"
  local save = newSave("crystal", "male")
  local state = newState(save, world, { timeOfDay = 1 })
  local enemy = { species = "RATTATA", level = 4 }
  state:pushCaught(enemy, "POKE_BALL")
  T.eq(enemy.caughtLocation, NEW_BARK, "the backup map's landmark is used")
end

do
  local world = newWorld()
  local save = newSave("crystal", "female")
  world.game = { save = save, data = DATA }
  local opts = World.caughtDataOpts(world)
  T.eq(opts.version, "crystal", "the save's version gates the stamp")
  T.eq(opts.timeOfDay, 2, "NITE is wTimeOfDay 2")
  T.eq(opts.landmark, ROUTE_29, "the landmark is resolved up front")
  T.eq(opts.playerGender, "female", "and wPlayerGender comes along")

  world.map = { def = { id = "POKECENTER_2F", landmark = 0x7f } }
  world.backupMapId = "NEW_BARK_TOWN"
  T.eq(World.caughtDataOpts(world).landmark, NEW_BARK,
    "with the POKECENTER_2F backup swap")
end

do
  local source = io.open("src/world/gen2/World.lua"):read("*a")
  T.check(source:find("Mon.setGiftCaughtData(mon, opts.caughtBy", 1, true)
    ~= nil, "the trainer arm stamps LANDMARK_GIFT")
  T.check(source:find("Catching.stampCaughtData(mon, self:caughtDataOpts())",
    1, true) ~= nil, "the wild arm runs SetCaughtData")
end

do
  local save = newSave("crystal", "female")
  local egg = Mon.new(DATA, "RATTATA", Breeding.EGG_LEVEL, {})
  egg.isEgg = true
  egg.eggSteps = 0
  save.party[1] = egg
  local world = newWorld()
  world.game = { save = save, data = DATA }
  local hatched = Breeding.hatch(DATA, save, 1, nil, World.caughtDataOpts(world))
  T.check(hatched ~= nil, "the egg hatches")
  T.eq(hatched.caughtLevel, Mon.CAUGHT_EGG_LEVEL, "CAUGHT_EGG_LEVEL")
  T.eq(hatched.caughtTime, 3, "NITE")
  T.eq(hatched.caughtLocation, ROUTE_29, "the hatch site's landmark")
  T.eq(hatched.caughtByGender, "girl", "and the player's gender")
end

do
  local save = newSave("crystal", "male")
  save.party[1] = Mon.new(DATA, "RATTATA", 20, {})
  local row = { id = 3, dialog = "TRADE_DIALOGSET_GIRL", give = "RATTATA",
    get = "DODRIO", nickname = "DORIS", dvs = { 0x77, 0x66 }, otName = "EMY",
    otId = 283 }
  local _, received = NpcTrade.perform(DATA, save, row, 1)
  T.check(received ~= nil, "the trade completes")
  T.eq(received.caughtTime, 0, "a gift has no caught time")
  T.eq(received.caughtLevel, 0, "and no caught level")
  T.eq(received.caughtLocation, Mon.LANDMARK_GIFT, "LANDMARK_GIFT")
  T.eq(received.caughtByGender, "girl", "TRADE_DIALOGSET_GIRL is CAUGHT_BY_GIRL")
end

do
  local save = newSave("crystal", "male")
  save.party[1] = Mon.new(DATA, "RATTATA", 20, {})
  local row = { id = 0, dialog = "TRADE_DIALOGSET_COLLECTOR", give = "RATTATA",
    get = "DODRIO", nickname = "MUSCLE", dvs = { 0x37, 0x66 }, otName = "MIKE",
    otId = 37460 }
  local _, received = NpcTrade.perform(DATA, save, row, 1)
  T.eq(received.caughtLocation, Mon.LANDMARK_GIFT, "still LANDMARK_GIFT")
  T.eq(received.caughtByGender, "boy",
    "CAUGHT_BY_UNKNOWN leaves the gender bit clear")
end

do
  local save = newSave("gold", "male")
  save.party[1] = Mon.new(DATA, "RATTATA", 20, {})
  local row = { id = 3, dialog = "TRADE_DIALOGSET_GIRL", give = "RATTATA",
    get = "DODRIO", nickname = "DORIS", dvs = { 0x77, 0x66 }, otName = "EMY",
    otId = 283 }
  local _, received = NpcTrade.perform(DATA, save, row, 1)
  T.eq(received.caughtLocation, nil, "Gold trades stamp nothing")
end

T.finish("gen2 caught data stamp bug 1886")
