-- Screens (FRLG Reflect / Light Screen / Safeguard only).

local Capabilities = require("src.core.game3.battle.capabilities")
local H = require("src.core.game3.battle.effects._helpers")

local Screens = {}

-- pokefirered/src/battle_script_commands.c:6428
local function both_alive(ctx)
  local st = ctx.adapter._st
  return st ~= nil and st.double
    and require("src.core.game3.battle.state").countPresentOnSide(st, ctx.user.side) == 2
end

-- pokefirered/src/battle_script_commands.c:8266
function Screens.safeguard(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expSafeguardTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expSafeguardTurns = Capabilities.safeguardDefaultTurns
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNCOVEREDBYVEIL", { atk = ctx.user })
end

-- pokefirered/src/battle_script_commands.c:6415
function Screens.reflect(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expReflectTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expReflectTurns = Capabilities.screenDefaultTurns
  H.attackAnim(ctx)
  ctx.adapter:sayText(both_alive(ctx) and "STRINGID_PKMNRAISEDDEFALITTLE" or "STRINGID_PKMNRAISEDDEF",
    { atk = ctx.user, currentMove = H.moveNum(ctx.move or ctx.moveId) })
end

-- pokefirered/src/battle_script_commands.c:7082
function Screens.lightScreen(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expLightScreenTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expLightScreenTurns = Capabilities.screenDefaultTurns
  H.attackAnim(ctx)
  ctx.adapter:sayText(both_alive(ctx) and "STRINGID_PKMNRAISEDSPDEFALITTLE" or "STRINGID_PKMNRAISEDSPDEF",
    { atk = ctx.user, currentMove = H.moveNum(ctx.move or ctx.moveId) })
end

-- pokefirered/data/battle_scripts_1.s:873
function Screens.mist(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expMistTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expMistTurns = 5
  H.attackAnim(ctx)
  ctx.adapter:sayText("STRINGID_PKMNSHROUDEDINMIST", { atk = ctx.user })
end

return Screens
