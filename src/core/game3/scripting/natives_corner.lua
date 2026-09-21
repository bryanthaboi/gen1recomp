local Corner = {}

-- pokefirered/include/constants/vars.h:321
local VAR_0x8006 = 0x8006
local VAR_RESULT = 0x800D

-- pokefirered/include/constants/coins.h:4
local MAX_COINS = 9999

-- pokefirered/data/specials.inc:361
local SPECIAL_CheckAddCoins = 0x15E

Corner.MAX_COINS = MAX_COINS

Corner.SPECIAL = {
  CheckAddCoins = SPECIAL_CheckAddCoins,
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

-- pokefirered/src/field_specials.c:719
function Corner.checkAddCoins(current, toAdd)
  current = math.floor(tonumber(current) or 0)
  toAdd = math.floor(tonumber(toAdd) or 0)
  if current + toAdd > MAX_COINS then return 0 end
  return 1
end

Corner.HANDLERS = {
  -- pokefirered/src/field_specials.c:719
  [SPECIAL_CheckAddCoins] = function(ctx)
    return false, Corner.checkAddCoins(varGet(ctx, VAR_RESULT), varGet(ctx, VAR_0x8006))
  end,
}

return Corner
