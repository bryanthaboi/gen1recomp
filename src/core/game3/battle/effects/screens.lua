-- Screens (FRLG Reflect / Light Screen / Safeguard only).

local Capabilities = require("src.core.game3.battle.capabilities")
local H = require("src.core.game3.battle.effects._helpers")

local Screens = {}

-- pokefirered/src/battle_message.c:2144
function Screens.prefix(battler)
  return (battler and battler.side == "player") and "Ally" or "Foe"
end

local function move_name(ctx, fallback)
  local M = H.move(ctx)
  return (M and M.moveName) or fallback
end

-- pokefirered/src/battle_script_commands.c:8266
function Screens.safeguard(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expSafeguardTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expSafeguardTurns = Capabilities.safeguardDefaultTurns
  H.attackAnim(ctx)
  ctx.adapter:say(Screens.prefix(ctx.user) .. "'s party is covered\nby a veil!")
end

-- pokefirered/src/battle_script_commands.c:6415
function Screens.reflect(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expReflectTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expReflectTurns = Capabilities.screenDefaultTurns
  H.attackAnim(ctx)
  ctx.adapter:say(Screens.prefix(ctx.user) .. "'s " .. move_name(ctx, "REFLECT") .. "\nraised DEFENSE!")
end

-- pokefirered/src/battle_script_commands.c:7082
function Screens.lightScreen(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expLightScreenTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expLightScreenTurns = Capabilities.screenDefaultTurns
  H.attackAnim(ctx)
  ctx.adapter:say(Screens.prefix(ctx.user) .. "'s " .. move_name(ctx, "LIGHT SCREEN") .. "\nraised SP. DEF!")
end

-- pokefirered/data/battle_scripts_1.s:873
function Screens.mist(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expMistTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expMistTurns = 5
  H.attackAnim(ctx)
  ctx.adapter:say(Screens.prefix(ctx.user) .. " became\nshrouded in MIST!")
end

return Screens
