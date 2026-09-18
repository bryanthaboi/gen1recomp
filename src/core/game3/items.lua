-- FRLG item identity + host mapping (H2).
-- hostId = nil means quarantine-only (never write to host bag).
-- Numeric ids match pret include/constants/items.h.

local ItemsData = require("src.core.game3.items_data")

local Items = {}

Items.GAME3_MAX_QTY = 999
Items.HOST_MAX_QTY = 99

-- FRLG numeric id → host string id (or false = quarantined / no host counterpart).
Items.FRLG_TO_HOST = {
  [1] = "MASTER_BALL",
  [2] = "ULTRA_BALL",
  [3] = "GREAT_BALL",
  [4] = "POKE_BALL",
  [13] = "POTION",
  [14] = "ANTIDOTE",
  [15] = "BURN_HEAL",
  [16] = "ICE_HEAL",
  [17] = "AWAKENING",
  [18] = "PARLYZ_HEAL",
  [19] = "FULL_RESTORE",
  [20] = "MAX_POTION",
  [21] = "HYPER_POTION",
  [22] = "SUPER_POTION",
  [23] = "FULL_HEAL",
  [24] = "REVIVE",
  [25] = "MAX_REVIVE",
  [26] = "FRESH_WATER",
  [27] = "SODA_POP",
  [28] = "LEMONADE",
  [75] = "X_ATTACK",
  [76] = "X_DEFEND",
  [77] = "X_SPEED",
  [78] = "X_ACCURACY",
  [79] = "X_SPECIAL",
  [80] = "POKE_DOLL",
  [83] = "SUPER_REPEL",
  [84] = "MAX_REPEL",
  [85] = "ESCAPE_ROPE",
  [86] = "REPEL",
  [110] = "NUGGET",
  [280] = "METEORITE",
  [360] = "BICYCLE",
  [361] = "TOWN_MAP",
  [367] = "TRI_PASS",
  [368] = "RAINBOW_PASS",
}

-- Host ids that must stay in sidecar (even if registered for name display).
Items.FORCE_QUARANTINE = {
  METEORITE = true,
}

-- Host-safe string ids (1:1 Gen1/Gen2 inventory).
Items.HOST_SAFE = {
  MASTER_BALL = true, ULTRA_BALL = true, GREAT_BALL = true, POKE_BALL = true,
  POTION = true, ANTIDOTE = true, BURN_HEAL = true, ICE_HEAL = true,
  AWAKENING = true, PARLYZ_HEAL = true, FULL_RESTORE = true, MAX_POTION = true,
  HYPER_POTION = true, SUPER_POTION = true, FULL_HEAL = true, REVIVE = true,
  MAX_REVIVE = true, FRESH_WATER = true, SODA_POP = true, LEMONADE = true,
  SUPER_REPEL = true, MAX_REPEL = true, ESCAPE_ROPE = true, REPEL = true,
  X_ATTACK = true, X_DEFEND = true, X_SPEED = true, X_ACCURACY = true,
  X_SPECIAL = true, POKE_DOLL = true, NUGGET = true, TOWN_MAP = true,
  TRI_PASS = true, RAINBOW_PASS = true, BICYCLE = true,
}

function Items.resolveHostId(itemId)
  if itemId == nil then return nil end
  local num = tonumber(itemId)
  if num then
    return Items.FRLG_TO_HOST[num]
  end
  local s = tostring(itemId)
  if Items.HOST_SAFE[s] or Items.FORCE_QUARANTINE[s] then return s end
  if s:match("^%d+$") then return nil end
  return s
end

function Items.isHostSafe(itemId)
  local host = Items.resolveHostId(itemId)
  if not host then return false end
  if Items.FORCE_QUARANTINE[host] then return false end
  return Items.HOST_SAFE[host] == true
end

function Items.clampGame3(qty)
  qty = math.floor(tonumber(qty) or 0)
  if qty < 0 then qty = 0 end
  if qty > Items.GAME3_MAX_QTY then qty = Items.GAME3_MAX_QTY end
  return qty
end

function Items.displayName(itemId)
  return ItemsData.displayName(itemId)
end

function Items.pocket(itemId)
  return ItemsData.pocketOf(itemId)
end

return Items
