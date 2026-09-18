-- FireRed battle AI trainer item use (port of battle_ai_switch_items.c ShouldUseItem).

local State = require("src.core.game3.battle.state")

local AiItems = {}

AiItems.TYPE = {
  FULL_RESTORE = 1, HEAL_HP = 2, CURE_CONDITION = 3, X_STAT = 4, GUARD_SPECS = 5, NOT_RECOGNIZABLE = 6,
}
local T = AiItems.TYPE

AiItems.ITEM_FULL_RESTORE = 19
AiItems.HEAL_HP_FULL = 0xFF
AiItems.HEAL_HP_HALF = 0xFE
AiItems.HEAL_HP_LVL_UP = 0xFD

-- src/data/pokemon/item_effects.h:338
local EFFECTS = {
  [13] = { 0, 0, 0, 0, 0x04, 20 },
  [14] = { 0, 0, 0, 0x10, 0 },
  [15] = { 0, 0, 0, 0x08, 0 },
  [16] = { 0, 0, 0, 0x04, 0 },
  [17] = { 0, 0, 0, 0x20, 0 },
  [18] = { 0, 0, 0, 0x02, 0 },
  [19] = { 0, 0, 0, 0x3F, 0x04, 0xFF },
  [20] = { 0, 0, 0, 0, 0x04, 0xFF },
  [21] = { 0, 0, 0, 0, 0x04, 200 },
  [22] = { 0, 0, 0, 0, 0x04, 50 },
  [23] = { 0, 0, 0, 0x3F, 0 },
  [24] = { 0, 0, 0, 0, 0x44, 0xFE },
  [25] = { 0, 0, 0, 0, 0x44, 0xFF },
  [26] = { 0, 0, 0, 0, 0x04, 50 },
  [27] = { 0, 0, 0, 0, 0x04, 60 },
  [28] = { 0, 0, 0, 0, 0x04, 80 },
  [29] = { 0, 0, 0, 0, 0x04, 100 },
  [30] = { 0, 0, 0, 0, 0x04, 50 },
  [31] = { 0, 0, 0, 0, 0x04, 200 },
  [32] = { 0, 0, 0, 0x3F, 0 },
  [33] = { 0, 0, 0, 0, 0x44, 0xFF },
  [34] = { 0, 0, 0, 0, 0x18, 10 },
  [35] = { 0, 0, 0, 0, 0x18, 0x7F },
  [36] = { 0, 0, 0, 0, 0x08, 10 },
  [37] = { 0, 0, 0, 0, 0x08, 0x7F },
  [38] = { 0, 0, 0, 0x3F, 0 },
  [39] = { 0, 0, 0, 0x20, 0 },
  [40] = { 0, 0, 0, 0x01, 0 },
  [41] = { 0x80, 0, 0, 0, 0 },
  [44] = { 0, 0, 0, 0, 0x04, 20 },
  [45] = { 0x40, 0, 0, 0, 0x44, 0xFF },
  [63] = { 0, 0, 0, 0, 0x01 },
  [64] = { 0, 0, 0, 0, 0x02 },
  [65] = { 0, 0, 0, 0, 0 },
  [66] = { 0, 0, 0, 0, 0 },
  [67] = { 0, 0, 0, 0, 0 },
  [68] = { 0, 0, 0, 0x40, 0x44, 0xFD },
  [69] = { 0, 0, 0, 0, 0x20 },
  [70] = { 0, 0, 0, 0, 0 },
  [71] = { 0, 0, 0, 0, 0 },
  [73] = { 0, 0, 0, 0x80, 0 },
  [74] = { 0x20, 0, 0, 0, 0 },
  [75] = { 0x01, 0, 0, 0, 0 },
  [76] = { 0, 0x10, 0, 0, 0 },
  [77] = { 0, 0x01, 0, 0, 0 },
  [78] = { 0, 0, 0x10, 0, 0 },
  [79] = { 0, 0, 0x01, 0, 0 },
  [93] = { 0, 0, 0, 0, 0x80 },
  [94] = { 0, 0, 0, 0, 0x80 },
  [95] = { 0, 0, 0, 0, 0x80 },
  [96] = { 0, 0, 0, 0, 0x80 },
  [97] = { 0, 0, 0, 0, 0x80 },
  [98] = { 0, 0, 0, 0, 0x80 },
  [133] = { 0, 0, 0, 0x02, 0 },
  [134] = { 0, 0, 0, 0x20, 0 },
  [135] = { 0, 0, 0, 0x10, 0 },
  [136] = { 0, 0, 0, 0x08, 0 },
  [137] = { 0, 0, 0, 0x04, 0 },
  [138] = { 0, 0, 0, 0, 0x18, 10 },
  [139] = { 0, 0, 0, 0, 0x04, 10 },
  [140] = { 0, 0, 0, 0x01, 0 },
  [141] = { 0, 0, 0, 0x3F, 0 },
  [142] = { 0, 0, 0, 0, 0x04, 30 },
}

local function band(a, b)
  a, b = math.floor(tonumber(a) or 0), math.floor(tonumber(b) or 0)
  local r, bit = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return r
end
AiItems.band = band

local function item_num(item)
  local n = tonumber(item)
  if n then return n end
  if item == nil or item == "" then return 0 end
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  if ok and ItemsData.toNumericId then return ItemsData.toNumericId(item) or 0 end
  return 0
end
AiItems.itemNum = item_num

function AiItems.effect(item)
  local e = EFFECTS[item_num(item)]
  if not e then return nil end
  return { e[1], e[2], e[3], e[4], e[5], hp = e[6] }
end

-- src/battle_ai_switch_items.c:546
function AiItems.itemType(item, e)
  if item_num(item) == AiItems.ITEM_FULL_RESTORE then return T.FULL_RESTORE end
  if band(e[5], 0x04) ~= 0 then return T.HEAL_HP end
  if band(e[4], 0x3F) ~= 0 then return T.CURE_CONDITION end
  if band(e[1], 0x3F) ~= 0 or e[2] ~= 0 or e[3] ~= 0 then return T.X_STAT end
  if band(e[4], 0x80) ~= 0 then return T.GUARD_SPECS end
  return T.NOT_RECOGNIZABLE
end

-- src/pokemon.c:4843
function AiItems.hpParam(e)
  if band(e[5], 0x04) == 0 then return 0 end
  return e.hp or 0
end

-- src/battle_ai_script_commands.c:262
function AiItems.history(st)
  if st._aiHistory then return st._aiHistory end
  local h = { items = {}, itemsNo = 0 }
  if st and not st.wild and not st.safari then
    for i = 1, 4 do
      local it = item_num(st.trainerItems and st.trainerItems[i])
      if it ~= 0 then
        h.itemsNo = h.itemsNo + 1
        h.items[h.itemsNo] = it
      end
    end
  end
  for i = h.itemsNo + 1, 4 do h.items[i] = 0 end
  st._aiHistory = h
  return h
end

local function status_name(b)
  local s = b and (b.status or (b.mon and b.mon.status))
  if not s or s == 0 then return nil end
  s = tostring(s):upper()
  if s == "SLEEP" then return "SLP" end
  if s == "POISON" then return "PSN" end
  if s == "TOXIC" then return "TOX" end
  if s == "BURN" then return "BRN" end
  if s == "FREEZE" then return "FRZ" end
  if s == "PARALYSIS" then return "PAR" end
  return s
end
AiItems.statusName = status_name

local function mon_valid(mon)
  if not mon or mon.isEgg then return false end
  local sp = mon.species or mon.speciesId or mon.id
  return (tonumber(mon.hp) or 0) ~= 0 and sp ~= nil and sp ~= 0
end

-- src/battle_ai_switch_items.c:562
function AiItems.shouldUseItem(st, id)
  local b = State.battler(st, id)
  if not b or not b.mon then return nil end
  local h = AiItems.history(st)
  local validMons = 0
  for i = 1, 6 do
    if mon_valid(st.foeParty and st.foeParty[i]) then validMons = validMons + 1 end
  end
  local hp = tonumber(b.mon.hp) or 0
  local maxHp = tonumber(b.mon.maxHp) or 0
  for i = 0, 3 do
    if not (i > 0 and validMons > (h.itemsNo - i) + 1) then
      local item = h.items[i + 1] or 0
      local e = item ~= 0 and AiItems.effect(item) or nil
      if e then
        local kind = AiItems.itemType(item, e)
        st.aiItemType = st.aiItemType or {}
        st.aiItemType[id] = kind
        local flags = 0
        local shouldUse = false
        if kind == T.FULL_RESTORE then
          if hp < math.floor(maxHp / 4) and hp ~= 0 then shouldUse = true end
        elseif kind == T.HEAL_HP then
          local param = AiItems.hpParam(e)
          if param ~= 0 and hp ~= 0 then
            if hp < math.floor(maxHp / 4) or maxHp - hp > param then shouldUse = true end
          end
        elseif kind == T.CURE_CONDITION then
          local s = status_name(b)
          if band(e[4], 0x20) ~= 0 and s == "SLP" then flags = flags + 0x20; shouldUse = true end
          if band(e[4], 0x10) ~= 0 and (s == "PSN" or s == "TOX") then flags = flags + 0x10; shouldUse = true end
          if band(e[4], 0x08) ~= 0 and s == "BRN" then flags = flags + 0x08; shouldUse = true end
          if band(e[4], 0x04) ~= 0 and s == "FRZ" then flags = flags + 0x04; shouldUse = true end
          if band(e[4], 0x02) ~= 0 and s == "PAR" then flags = flags + 0x02; shouldUse = true end
          if band(e[4], 0x01) ~= 0 and (tonumber(b.confusionTurns) or 0) > 0 then flags = flags + 0x01; shouldUse = true end
        elseif kind == T.X_STAT then
          if (tonumber(b.isFirstTurn) or 0) ~= 0 then
            if band(e[1], 0x0F) ~= 0 then flags = flags + 0x01 end
            if band(e[2], 0xF0) ~= 0 then flags = flags + 0x02 end
            if band(e[2], 0x0F) ~= 0 then flags = flags + 0x04 end
            if band(e[3], 0x0F) ~= 0 then flags = flags + 0x08 end
            if band(e[3], 0xF0) ~= 0 then flags = flags + 0x20 end
            if band(e[1], 0x30) ~= 0 then flags = flags + 0x80 end
            shouldUse = true
          end
        elseif kind == T.GUARD_SPECS then
          local side = (b.side == "player") and st.playerSide or st.enemySide
          if (tonumber(b.isFirstTurn) or 0) ~= 0 and (tonumber(side and side.expMistTurns) or 0) == 0 then
            shouldUse = true
          end
        else
          return nil
        end
        if shouldUse then
          st.aiItemFlags = st.aiItemFlags or {}
          st.aiItemFlags[id] = flags
          h.items[i + 1] = 0
          return { item = item, aiItemType = kind, aiItemFlags = flags }
        end
      end
    end
  end
  return nil
end

return AiItems
