local FameChecker = require("src.core.game3.fame_checker")

local Fame = {}

-- pokefirered/include/constants/vars.h:319
local VAR_0x8004 = 0x8004
local VAR_0x8005 = 0x8005

-- pokefirered/data/specials.inc:382
local SPECIAL_SetFlavorTextFlagFromSpecialVars = 0x173
-- pokefirered/data/specials.inc:383
local SPECIAL_UpdatePickStateFromSpecialVar8005 = 0x174

Fame.SPECIAL = {
  SetFlavorTextFlagFromSpecialVars = SPECIAL_SetFlavorTextFlagFromSpecialVars,
  UpdatePickStateFromSpecialVar8005 = SPECIAL_UpdatePickStateFromSpecialVar8005,
}

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function scriptStore()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local rt = package.loaded["src.core.game3.runtime"]
  local session = rt and rt.getSession and rt.getSession()
  return (Space and Space.store) or (session and session.store) or nil
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(), ctx, id)) or 0
end

local function varSet(ctx, id, value)
  flagsMod().setVar(scriptStore(), ctx, id, tonumber(value) or 0)
end

Fame.HANDLERS = {
  -- pokefirered/src/fame_checker.c:1222
  [SPECIAL_SetFlavorTextFlagFromSpecialVars] = function(ctx)
    local person = varGet(ctx, VAR_0x8004)
    local slot = varGet(ctx, VAR_0x8005)
    if FameChecker.setFlavorText(person, slot) then
      varSet(ctx, VAR_0x8005, FameChecker.PICKSTATE.SILHOUETTE)
    end
    return false
  end,
  -- pokefirered/src/fame_checker.c:1232
  [SPECIAL_UpdatePickStateFromSpecialVar8005] = function(ctx)
    FameChecker.updatePickState(varGet(ctx, VAR_0x8004), varGet(ctx, VAR_0x8005))
    return false
  end,
}

return Fame
