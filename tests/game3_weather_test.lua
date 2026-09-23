-- Tests for Weather constants, lifecycle, and FieldWeather atmospheric states

local Weather = require("src.core.game3.weather")
local FieldWeather = require("src.core.game3.field_weather")

local tests = {}

function tests.test_weather_constants()
  assert(Weather.NONE == 0, "WEATHER_NONE should be 0")
  assert(Weather.SUNNY == 2, "WEATHER_SUNNY should be 2")
  assert(Weather.RAIN == 3, "WEATHER_RAIN should be 3")
  assert(Weather.FOG_HORIZONTAL == 6, "WEATHER_FOG_HORIZONTAL should be 6")
  assert(Weather.SHADE == 11, "WEATHER_SHADE should be 11")
  assert(Weather.FOG == 6, "Weather.FOG alias should be 6")
end

function tests.test_weather_lifecycle()
  Weather.reset()
  assert(Weather.get() == Weather.NONE, "Weather should be NONE after reset")
  assert(not Weather.isActive(), "Weather should be inactive")

  -- Script opcode sequence: setweather -> doweather
  Weather.set(Weather.FOG_HORIZONTAL)
  assert(Weather.get() == Weather.NONE, "Weather should remain NONE until doweather is called")
  Weather.doWeather()
  assert(Weather.get() == Weather.FOG_HORIZONTAL, "Weather should be FOG_HORIZONTAL after doweather")
  assert(Weather.isActive(), "Weather should be active")
  assert(FieldWeather.getWeather() == Weather.FOG_HORIZONTAL, "FieldWeather should be synchronized")

  -- Test suspension (e.g. entering battle/menu)
  assert(not Weather.isSuspended(), "Weather should not be suspended initially")
  Weather.suspend()
  assert(Weather.isSuspended(), "Weather should be suspended during battle")
  Weather.resume()
  assert(not Weather.isSuspended(), "Weather should resume after battle")

  -- Test Shade
  Weather.apply(Weather.SHADE)
  assert(Weather.get() == Weather.SHADE, "Weather should be SHADE")
  assert(FieldWeather.getWeather() == Weather.SHADE, "FieldWeather should be SHADE")

  -- Reset back to NONE
  Weather.reset()
  assert(Weather.get() == Weather.NONE, "Weather should be reset to NONE")
end

function tests.test_fog_horizontal_scroll()
  FieldWeather.setWeather(Weather.FOG_HORIZONTAL)
  assert(FieldWeather._fogScrollOffset == 0, "Initial scroll offset should be 0")

  -- 4 ticks per pixel of scroll
  for i = 1, 4 do
    FieldWeather.update(1 / 60)
  end
  assert(FieldWeather._fogScrollOffset == 1, "Scroll offset should advance by 1 after 4 ticks")

  for i = 1, 4 do
    FieldWeather.update(1 / 60)
  end
  assert(FieldWeather._fogScrollOffset == 2, "Scroll offset should advance by 2 after 8 ticks")
end

return tests
