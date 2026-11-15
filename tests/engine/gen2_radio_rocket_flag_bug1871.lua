-- engine/pokegear/radio.asm:1 (#1871)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local EngineFlagsFixture = require("tests.fixture_data.gen2_engine_flags")
EngineFlagsFixture.bind("gold")
local check = T.check
love = love or require("tests.love_stub")

local EngineFlags = require("src.core.gen2.EngineFlags")
local Pokegear = require("src.ui.gen2.Pokegear")

local TOWER = EngineFlags.id("ENGINE_ROCKETS_IN_RADIO_TOWER")
local SIGNAL = EngineFlags.id("ENGINE_ROCKET_SIGNAL_ON_CH20")

local function newGear(save, world)
  local gear = setmetatable({
    save = save,
    game = { world = world },
    landmarks = { landmarks = {} },
  }, { __index = Pokegear })
  gear.region = function() return "johto" end
  gear.hiddenPeople = function() return {} end
  gear.radioWeekday = function() return 1 end
  gear.timeOfDayIndex = function() return 1 end
  return gear
end

check(TOWER == 18, "ENGINE_ROCKETS_IN_RADIO_TOWER is gold id 18")
check(SIGNAL == 14, "ENGINE_ROCKET_SIGNAL_ON_CH20 is gold id 14")

local armed = newGear({ engineFlags = { [TOWER] = true } })
check(armed:radioData().rocketsInRadioTower == true,
  "the takeover reads straight off save.engineFlags")

local quiet = newGear({ engineFlags = {} })
check(quiet:radioData().rocketsInRadioTower == false,
  "and stays off while the tower is clear")

local legacy = newGear({ flags = { ROCKETS_IN_RADIO_TOWER = true } })
check(legacy:radioData().rocketsInRadioTower == false,
  "save.flags is not the takeover's store")

EngineFlagsFixture.bind("crystal")
local crystal = newGear({ engineFlags = { [19] = true } })
check(crystal:radioData().rocketsInRadioTower == true,
  "and Crystal's ENGINE_ROCKETS_IN_RADIO_TOWER is flag 19")
EngineFlagsFixture.bind("gold")

local rage = newGear({ engineFlags = { [SIGNAL] = true } })
check(rage:radioContext().rocketSignal == true,
  "the Lake of Rage signal reads the same store")

T.finish("gen2 radio rocket flag bug 1871")
