-- Field weather session state (H5). Ops setweather / doweather / resetweather.
-- pokefirered/include/constants/weather.h
-- pokefirered/src/field_weather.c

local Weather = {}

Weather.NONE = 0
Weather.SUNNY_CLOUDS = 1
Weather.SUNNY = 2
Weather.RAIN = 3
Weather.SNOW = 4
Weather.RAIN_THUNDERSTORM = 5
Weather.FOG_HORIZONTAL = 6
Weather.VOLCANIC_ASH = 7
Weather.SANDSTORM = 8
Weather.FOG_DIAGONAL = 9
Weather.UNDERWATER = 10
Weather.SHADE = 11
Weather.DROUGHT = 12
Weather.DOWNPOUR = 13
Weather.UNDERWATER_BUBBLES = 14
Weather.ABNORMAL = 15

-- Aliases
Weather.FOG = Weather.FOG_HORIZONTAL
Weather.ASH = Weather.VOLCANIC_ASH

Weather.current = Weather.NONE
Weather._pending = nil
Weather._active = false
Weather._suspended = false

function Weather.set(id)
  Weather._pending = tonumber(id) or Weather.NONE
end

function Weather.doWeather()
  Weather.current = Weather._pending or Weather.current
  Weather._active = Weather.current ~= Weather.NONE and Weather.current ~= Weather.SUNNY
  Weather.apply(Weather.current)
end

function Weather.reset()
  Weather._pending = Weather.NONE
  Weather.current = Weather.NONE
  Weather._active = false
  Weather.apply(Weather.NONE)
end

function Weather.apply(id)
  Weather.current = tonumber(id) or Weather.NONE
  Weather._active = Weather.current ~= Weather.NONE and Weather.current ~= Weather.SUNNY

  local okFw, FieldWeather = pcall(require, "src.core.game3.field_weather")
  if okFw and FieldWeather and FieldWeather.setWeather then
    FieldWeather.setWeather(Weather.current)
  end

  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local world = game and (game.overworld or game.world)
  if world and world.setWeather then
    pcall(function() world:setWeather(Weather.current) end)
  end
end

function Weather.get()
  return Weather.current
end

function Weather.isActive()
  return Weather._active
end

function Weather.suspend()
  Weather._suspended = true
end

function Weather.resume()
  Weather._suspended = false
end

function Weather.isSuspended()
  return Weather._suspended
end

return Weather
