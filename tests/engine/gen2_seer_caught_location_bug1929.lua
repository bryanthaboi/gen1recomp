-- ../pokecrystal/engine/events/poke_seer.asm:103-104
-- ../pokecrystal/engine/events/shuckle.asm:18-19
-- ../pokecrystal/engine/pokemon/move_mon.asm:1761-1773
package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Events = require("src.world.gen2.Events")
local Mon = require("src.battle.gen2.Mon")
local COUNTERS = require("tests.fixture_data.gen2_prize_counters_s7_f2")
local Save = require("src.core.gen2.Save")
local Specials = require("src.script.gen2.Specials")
local Vm = require("src.script.gen2.Vm")
local World = require("src.world.gen2.World")

-- constants/landmark_constants.asm
local GOLDENROD = 12

local DATA = {
  text = require("tests.fixture_data.gen2_rom_text_s7_f1").text(),
  constants = { bagSize = 20 },
  items = { BERRY = { name = "BERRY", pocket = "ITEM" } },
  moves = {
    CONSTRICT = { name = "CONSTRICT", pp = 35 },
    TELEPORT = { name = "TELEPORT", pp = 20 },
  },
  pokemon = {
    growthRates = { MEDIUM_FAST = {} },
    SHUCKLE = { name = "SHUCKLE", index = 213, growthRate = "MEDIUM_FAST",
      types = { "BUG", "ROCK" },
      baseStats = { hp = 20, attack = 10, defense = 230, speed = 5,
        specialAttack = 10, specialDefense = 230 },
      levelMoves = { { level = 1, move = "CONSTRICT" } } },
    ABRA = { name = "ABRA", index = 63, growthRate = "MEDIUM_FAST",
      types = { "PSYCHIC", "PSYCHIC" },
      baseStats = { hp = 25, attack = 20, defense = 15, speed = 90,
        specialAttack = 105, specialDefense = 55 },
      levelMoves = { { level = 1, move = "TELEPORT" } } },
  },
}

local function newSave(version, coins)
  return {
    version = version, party = {}, inventory = {},
    player = { name = "KRIS", id = 4242, gender = "female",
      coins = coins or 0 },
    pokedex = { seen = {}, caught = {} },
  }
end


local function giftVm(record)
  return Vm.new({ generation = 2 }, {}, Events.new(), { specials = {
    party = function() return record.party end,
    save = function() return record end,
    data = function() return DATA end,
  } })
end

do
  local record = newSave("crystal")
  Specials.HANDLERS.GiveShuckle(giftVm(record))
  local mon = record.party[1]
  T.check(mon ~= nil, "SHUCKIE joins the party")
  T.eq(mon.caughtLocation, Mon.LANDMARK_GIFT,
    "SetGiftPartyMonCaughtData writes LANDMARK_GIFT")
  T.eq(mon.caughtLevel, 0, "byte 0 is xor'd, so no caught level")
  T.eq(mon.caughtTime, 0, "and no caught time")
  T.eq(mon.caughtByGender, "boy",
    "CAUGHT_BY_UNKNOWN leaves the gender bit clear")
  local byte0, byte1 = Mon.packCaughtData(mon)
  T.eq(byte0, 0, "byte 0 of MON_CAUGHTDATA")
  T.eq(byte1, Mon.LANDMARK_GIFT, "byte 1 is LANDMARK_GIFT alone")
end

do
  local record = newSave("gold")
  Specials.HANDLERS.GiveShuckle(giftVm(record))
  local mon = record.party[1]
  T.check(mon ~= nil, "Gold hands the same SHUCKIE over")
  T.eq(mon.caughtLocation, nil, "but Gold's struct has no caught data")
end


local abra = COUNTERS.prizes(COUNTERS.scripts, COUNTERS.keys.goldenrodMon)[1]

local function prizeWorld(save)
  return setmetatable({ game = { data = DATA, save = save },
    map = { def = { landmark = GOLDENROD } }, tod = "DAY" }, { __index = World })
end

do
  local save = newSave("crystal", 9999)
  T.check(prizeWorld(save):givePoke(abra.species, abra.level, 0) ~= nil,
    "the prize is handed over")
  local mon = save.party[1]
  T.eq(mon.caughtLocation, GOLDENROD,
    "the givepoke takes the .wildmon arm's SetCaughtData")
  T.eq(mon.caughtLevel, abra.level, "at the scripted level")
  T.eq(mon.caughtTime, 2, "wTimeOfDay DAY stores as 2")
  T.eq(mon.caughtByGender, "girl", "wPlayerGender bit 0 on bit 7")
end

do
  local save = newSave("gold", 9999)
  T.check(prizeWorld(save):givePoke(abra.species, abra.level, 0) ~= nil,
    "Gold buys it too")
  T.eq(save.party[1].caughtLocation, nil, "and stamps nothing")
end


local function stamped()
  return { species = "ABRA", level = 40, caughtLevel = 12, caughtTime = 1,
    caughtLocation = 2, caughtByGender = "girl" }
end

local function halfStamped(level)
  return { species = "ABRA", level = level, caughtLevel = level }
end

do
  local file = {
    format = 7, version = "crystal",
    party = { halfStamped(30), stamped(),
      { species = "ABRA", level = 5, isEgg = true, caughtLevel = 5 },
      { species = "ABRA", level = 15, caughtLevel = 15,
        caughtLocation = Mon.LANDMARK_GIFT } },
    boxes = { [1] = { halfStamped(9) }, [2] = {} },
    dayCare = { man = { mon = halfStamped(7) }, lady = {} },
  }
  Save.migrate(file)
  T.eq(file.format, Save.FORMAT, "the file reaches the current format")

  local byte0, byte1 = Mon.packCaughtData(file.party[1])
  T.eq(byte0, 0, "a half-stamped party mon loses byte 0")
  T.eq(byte1, 0, "and byte 1 stays clear, so ReadCaughtData takes .error")
  T.eq(file.party[2].caughtLevel, 12, "a fully stamped mon keeps its level")
  T.eq(file.party[2].caughtLocation, 2, "and its landmark")
  T.eq(file.party[3].caughtLevel, 5, "an egg is left alone")
  T.eq(file.party[4].caughtLevel, 15, "so is LANDMARK_GIFT")
  T.eq(file.boxes[1][1].caughtLevel, 0, "a box mon is cleared too")
  T.eq(file.dayCare.man.mon.caughtLevel, 0, "and a Day-Care deposit")
end

do
  local file = { format = 7, version = "gold", party = { halfStamped(30) } }
  Save.migrate(file)
  T.eq(file.party[1].caughtLevel, 30,
    "Gold has no MON_CAUGHTDATA, so the backfill skips it")
end

T.finish("gen2 seer caught location bug 1929")
