local Capabilities = require("src.core.game3.battle.capabilities")
local H = require("src.core.game3.battle.effects._helpers")
local Rules = require("src.core.game3.battle.rules")
local Strings = require("src.core.Strings")

local Weather = {}

-- pokefirered/src/battle_script_commands.c:6399
local function set(ctx, kind, text)
  local cur = Rules.weather.kind(ctx.adapter._st.weather)
  if cur == Rules.weather.kind(kind) then return H.sayFail(ctx) end
  ctx.adapter:setWeather(kind, Capabilities.weatherDefaultTurns)
  H.attackAnim(ctx)
  ctx.adapter:say(text)
end

function Weather.sunny(ctx) set(ctx, "SUNNY", Strings("The sunlight got bright!")) end
function Weather.rainy(ctx) set(ctx, "RAINY", Strings("It started to rain!")) end
function Weather.sandstorm(ctx) set(ctx, "SANDSTORM", Strings("A sandstorm brewed!")) end
function Weather.hail(ctx) set(ctx, "HAIL", Strings("It started to hail!")) end

return Weather
