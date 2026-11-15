package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
if not cache:read("data/generated/gba/weather/manifest.lua") then
  print("emerald_weather_field_test: skipped (no Emerald cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d") .. ")")
  os.exit(0)
end
Dataset.mountExtractRoots()

local Weather = require("src.core.game3.weather")
local R = require("src.core.game3.field_weather_rse")
local CoordWeather = require("src.core.game3.coord_weather")
local FieldMoves = require("src.core.game3.field_moves")
local Flags = require("src.core.game3.scripting.flags")
local MB = require("src.core.game3.mb")
local C = require("src.core.game3.constants").of("emerald")

-- pokeemerald/src/field_weather.c:248 BuildColorMaps
eq(R.colorMaps.dark[2][31], 25, "dark contrast map 3 darkens 31 -> 25")
eq(R.colorMaps.contrast[2][31], 31, "contrast map 3 keeps 31")
eq(R.colorMaps.dark[18][31], 31, "map 19 saturates highlights")
eq(R.colorMaps.dark[18][0], 1, "map 19 lifts shadows")
local r, g, b = R.mapColor(31, 16, 0, 3, 1)
eq(r, 25, "ApplyColorMap r") eq(g, 13, "ApplyColorMap g") eq(b, 0, "ApplyColorMap b")
check(R.droughtTable(0) ~= nil and R.droughtTable(5) ~= nil, "6 drought color tables load from the cache")

-- pokeemerald/src/field_weather_effect.c:2575
local sess = { weatherCycleStage = 0 }
local cyc = {}
for stage = 0, 3 do
  sess.weatherCycleStage = stage
  cyc[#cyc + 1] = Weather.translate(Weather.ROUTE119_CYCLE, sess)
end
eq(table.concat(cyc, ","), "2,3,5,3", "Route 119 cycle SUNNY, RAIN, THUNDERSTORM, RAIN")
cyc = {}
for stage = 0, 3 do
  sess.weatherCycleStage = stage
  cyc[#cyc + 1] = Weather.translate(Weather.ROUTE123_CYCLE, sess)
end
eq(table.concat(cyc, ","), "2,2,3,2", "Route 123 cycle SUNNY, SUNNY, RAIN, SUNNY")
eq(Weather.translate(Weather.ABNORMAL, sess), Weather.ABNORMAL, "ABNORMAL passes through")
eq(Weather.translate(17, sess), Weather.NONE, "unknown weather translates to NONE")
sess.weatherCycleStage = 3
Weather.updatePerDay(2, sess)
eq(sess.weatherCycleStage, 1, "UpdateWeatherPerDay wraps mod 4")
local saved = { savedWeather = Weather.NONE }
Weather.setSaved(Weather.RAIN, saved)
eq(saved.gameStats and saved.gameStats[40], 1, "GAME_STAT_GOT_RAINED_ON counts a new rain")
Weather.setSaved(Weather.RAIN, saved)
eq(saved.gameStats[40], 1, "same rain again does not count")

-- pokeemerald/src/coord_event_weather.c:26
eq(CoordWeather.BY_TRIGGER[8], Weather.VOLCANIC_ASH, "COORD_EVENT_WEATHER_VOLCANIC_ASH")
eq(CoordWeather.BY_TRIGGER[20], Weather.ROUTE119_CYCLE, "COORD_EVENT_WEATHER_ROUTE119_CYCLE")
check(CoordWeather.isWeatherEvent({ x = 1, y = 1, var = 3, scriptPtr = 0 }), "NULL-script coord event is weather")
check(not CoordWeather.isWeatherEvent({ x = 1, y = 1, scriptKey = "g3:0", scriptPtr = 1 }), "script coord event is not")

R.stop()
R.setCurrentAndNextWeatherNoDelay(Weather.RAIN)
R.update()
local s = R.snapshot()
eq(s.curr, Weather.RAIN, "rain initialized")
eq(s.colorMapIndex, 3, "rain fade-in lands on color map 3")
eq(s.rain, 24, "24 rain sprites")
eq(s.rainVisible, 10, "10 visible")
R.setNextWeather(Weather.SUNNY)
local frames = 0
repeat R.update(); frames = frames + 1 until R.snapshot().curr == Weather.SUNNY or frames > 2000
eq(R.snapshot().curr, Weather.SUNNY, "rain finishes into sunny")
repeat R.update(); frames = frames + 1 until R.snapshot().colorMapIndex == 0 or frames > 4000
eq(R.snapshot().colorMapIndex, 0, "color map steps back to 0")
check(frames > 60, "the rain -> sunny change is gradual (" .. frames .. " frames)")
R.stop()
R.setCurrentAndNextWeatherNoDelay(Weather.VOLCANIC_ASH)
R.update()
s = R.snapshot()
check(s.ash and s.eva == 16 and s.evb == 0, "ash InitAll ends at blend 16/0")
R.stop()

-- pokeemerald/src/party_menu.c:119
local IDS = Flags.forVersion("emerald").IDS
for i, name in ipairs({ "CUT", "FLASH", "ROCK_SMASH", "STRENGTH", "SURF", "FLY", "DIVE", "WATERFALL" }) do
  eq(FieldMoves.badgeFlag(name), IDS[string.format("FLAG_BADGE0%d_GET", i)], name .. " needs badge " .. i)
end
eq(FieldMoves.SYS_FLAGS.USE_STRENGTH, IDS.FLAG_SYS_USE_STRENGTH, "USE_STRENGTH by name")
eq(FieldMoves.SYS_FLAGS.FLASH_ACTIVE, IDS.FLAG_SYS_USE_FLASH, "FLASH_ACTIVE by name")
require("src.core.game3.se_ids").select("emerald")
eq(FieldMoves.SE.CUT, C.songs.byName.SE_M_CUT, "SE_M_CUT by name")
eq(FieldMoves.textKey("ASK_CUT_TREE"), "Text_WantToCut", "Emerald cut prompt text")
eq(FieldMoves.MENU_HANDLERS[FieldMoves.MOVES.DIVE], FieldMoves.diveFromMenu, "DIVE has a menu handler")

-- pokeemerald/src/fldeff_cut.c:138
local grid = {}
local TALL = MB.id("TALL_GRASS")
grid["11,10"] = TALL
grid["9,9"] = TALL
grid["12,10"] = TALL
local q = {
  x = 10, y = 10, elevation = 3,
  behavior = function(x, y) return grid[x .. "," .. y] or 0 end,
  elevationAt = function() return 3 end,
  impassable = function() return false end,
}
local plan = FieldMoves.cutGrassPlan(q, false)
check(plan and plan.side == 3 and #plan.cells == 2, "3x3 cut finds the two grass tiles inside the square")
local hyper = FieldMoves.cutGrassPlan(q, true)
check(hyper and hyper.side == 5 and #hyper.cells == 3, "Hyper Cutter reaches the 5x5 ring")
grid = {}
check(FieldMoves.cutGrassPlan(q, false) == nil, "no grass -> nothing to cut")
local L = C.metatile_labels.byName
eq(FieldMoves.cutGrassMetatile(L.METATILE_General_TallGrass), L.METATILE_General_Grass, "tall grass mows to grass")
eq(FieldMoves.cutGrassMetatile(L.METATILE_Fallarbor_AshGrass), L.METATILE_Fallarbor_AshField, "ash grass mows to ash field")

local Dive = require("src.core.game3.dive")
check(Dive.isDiveable(MB.id("DEEP_WATER")), "MB_DEEP_WATER is diveable")
check(Dive.isUnableToEmerge(MB.id("SEAWEED_NO_SURFACING")), "seaweed no-surfacing blocks emerging")
check(not Dive.isUnableToEmerge(MB.id("NORMAL")), "normal underwater tile can emerge")

T.finish()
