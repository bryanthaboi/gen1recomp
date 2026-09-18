-- Field weather session state (H5). Ops setweather / doweather / resetweather.

local Weather = {}

Weather.NONE = 0
Weather.RAIN = 1
Weather.ASH = 2
Weather.FOG = 3
Weather.SANDSTORM = 4
Weather.SUNNY = 5

Weather.current = 0
Weather._pending = nil
Weather._active = false

function Weather.set(id)
  Weather._pending = tonumber(id) or 0
end

function Weather.doWeather()
  Weather.current = Weather._pending or Weather.current
  Weather._active = Weather.current ~= Weather.NONE
  Weather.apply(Weather.current)
end

function Weather.reset()
  Weather._pending = Weather.NONE
  Weather.current = Weather.NONE
  Weather._active = false
  Weather.apply(Weather.NONE)
end

function Weather.apply(id)
  Weather.current = tonumber(id) or 0
  Weather._active = Weather.current ~= Weather.NONE
  -- Overlay hook: host World may expose weather palette; optional.
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

return Weather
