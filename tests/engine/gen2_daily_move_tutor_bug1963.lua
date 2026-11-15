-- ../pokecrystal/engine/overworld/time.asm:102

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Apricorns = require("src.core.gen2.Apricorns")
local EngineFlagsFixture = require("tests.fixture_data.gen2_engine_flags")

-- ../pokecrystal/constants/engine_flags.asm:25
local CRYSTAL = {
  ENGINE_KURT_MAKING_BALLS = 80,
  ENGINE_DAILY_BUG_CONTEST = 81,
  ENGINE_QWILFISH_SWARM = 82,
  ENGINE_TIME_CAPSULE = 83,
  ENGINE_ALL_FRUIT_TREES = 84,
  ENGINE_GOT_SHUCKIE_TODAY = 85,
  ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED = 86,
  ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY = 87,
  ENGINE_MT_MOON_SQUARE_CLEFAIRY = 88,
  ENGINE_UNION_CAVE_LAPRAS = 89,
  ENGINE_GOLDENROD_UNDERGROUND_GOT_HAIRCUT = 90,
  ENGINE_GOLDENROD_DEPT_STORE_TM27_RETURN = 91,
  ENGINE_DAISYS_GROOMING = 92,
  ENGINE_INDIGO_PLATEAU_RIVAL_FIGHT = 93,
  ENGINE_DAILY_MOVE_TUTOR = 94,
  ENGINE_BUENAS_PASSWORD = 95,
}

local daily = {}
for _, name in ipairs(Apricorns.DAILY_ENGINE_FLAGS) do daily[name] = true end
check(daily.ENGINE_DAILY_MOVE_TUTOR, "ENGINE_DAILY_MOVE_TUTOR is a daily flag")
check(daily.ENGINE_BUENAS_PASSWORD, "ENGINE_BUENAS_PASSWORD is a daily flag")
check(daily.ENGINE_INDIGO_PLATEAU_RIVAL_FIGHT, "and so is the Indigo Plateau rival fight")

-- ../pokecrystal/maps/GoldenrodCity.asm:34
do
  EngineFlagsFixture.bind("crystal")
  local save = { engineFlags = {} }
  for _, id in pairs(CRYSTAL) do save.engineFlags[id] = true end
  Apricorns.startDailyResetTimer(save, { day = 10, hour = 9 })
  check(not Apricorns.checkDailyResetTimer(save, { day = 10, hour = 23 }),
    "the same day never rolls over")
  check(save.engineFlags[94], "so the tutor flag is still set")
  check(Apricorns.checkDailyResetTimer(save, { day = 11, hour = 0 }),
    "midnight rolls over")
  eq(save.engineFlags[94], nil, "and clears ENGINE_DAILY_MOVE_TUTOR")
  eq(save.engineFlags[95], nil, "and Buena's password with it")
  eq(save.engineFlags[93], nil, "and the Indigo Plateau rival fight")
  for name, id in pairs(CRYSTAL) do
    eq(save.engineFlags[id], nil, name .. " is cleared under Crystal")
  end
end

-- ../pokegold/engine/overworld/time.asm:89
do
  EngineFlagsFixture.bind("gold")
  local save = { engineFlags = {} }
  for id = 79, 92 do save.engineFlags[id] = true end
  save.engineFlags[26] = true
  Apricorns.startDailyResetTimer(save, { day = 3, hour = 9 })
  check(Apricorns.checkDailyResetTimer(save, { day = 4, hour = 0 }),
    "a Gold rollover")
  for id = 79, 92 do
    eq(save.engineFlags[id], nil, "gold daily flag " .. id .. " is cleared")
  end
  check(save.engineFlags[26], "and ENGINE_ZEPHYRBADGE is not a daily flag")
end

-- ../pokecrystal/constants/engine_flags.asm:98
do
  EngineFlagsFixture.bind("crystal")
  local save = { engineFlags = {} }
  save.engineFlags[Apricorns.ENGINE_KURT_MAKING_BALLS] = true
  save.engineFlags[Apricorns.ENGINE_ALL_FRUIT_TREES] = true
  Apricorns.startDailyResetTimer(save, { day = 3, hour = 9 })
  check(Apricorns.checkDailyResetTimer(save, { day = 4, hour = 0 }),
    "a Crystal rollover")
  eq(save.engineFlags[80], nil, "flag 80 is Crystal's KURT_MAKING_BALLS")
  eq(save.engineFlags[Apricorns.ENGINE_KURT_MAKING_BALLS], nil,
    "still finishes Kurt's ball")
  eq(save.engineFlags[Apricorns.ENGINE_ALL_FRUIT_TREES], nil,
    "and still refills the fruit trees")
end

T.finish("gen2 daily move tutor bug 1963")
