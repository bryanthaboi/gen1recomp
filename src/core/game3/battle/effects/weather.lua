local Capabilities = require("src.core.game3.battle.capabilities")
local H = require("src.core.game3.battle.effects._helpers")
local Rules = require("src.core.game3.battle.rules")

local Weather = {}

-- pokefirered/src/battle_script_commands.c:6399
local function set(ctx, kind, id)
  local cur = Rules.weather.kind(ctx.adapter._st.weather)
  if cur == Rules.weather.kind(kind) then return H.sayFail(ctx) end
  ctx.adapter:setWeather(kind, Capabilities.weatherDefaultTurns)
  H.attackAnim(ctx)
  ctx.adapter:sayText(id)
end

-- src/battle_message.c:912
function Weather.sunny(ctx) set(ctx, "SUNNY", "STRINGID_SUNLIGHTGOTBRIGHT") end
function Weather.rainy(ctx) set(ctx, "RAINY", "STRINGID_STARTEDTORAIN") end
function Weather.sandstorm(ctx) set(ctx, "SANDSTORM", "STRINGID_SANDSTORMBREWED") end
function Weather.hail(ctx) set(ctx, "HAIL", "STRINGID_STARTEDHAIL") end

return Weather
