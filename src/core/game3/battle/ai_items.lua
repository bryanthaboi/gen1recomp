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

-- src/pokemon.c:4843 GetItemEffectParamOffset
local function param_offset(e, effectByte, effectBit)
  local offset = 6
  for i = 0, 5 do
    if i <= 3 then
      if i == effectByte then return 0 end
    elseif i == 4 then
      local val = tonumber(e[5]) or 0
      if band(val, 0x20) ~= 0 then val = val - 0x20 end
      local j = 0
      while val > 0 do
        if val % 2 == 1 then
          if j == 2 and band(val, 0x10) ~= 0 then val = val - 0x10 end
          if j == 0 or j == 1 or j == 2 or j == 3 then
            if i == effectByte and band(val, effectBit) ~= 0 then return offset end
            offset = offset + 1
          elseif j == 7 then
            if i == effectByte then return 0 end
          end
        end
        j = j + 1
        val = math.floor(val / 2)
        if i == effectByte then effectBit = math.floor(effectBit / 2) end
      end
    else
      local val = tonumber(e[6]) or 0
      local j = 0
      while val > 0 do
        if val % 2 == 1 then
          if j <= 6 then
            if i == effectByte and band(val, effectBit) ~= 0 then return offset end
            offset = offset + 1
          elseif i == effectByte then
            return 0
          end
        end
        j = j + 1
        val = math.floor(val / 2)
        if i == effectByte then effectBit = math.floor(effectBit / 2) end
      end
    end
  end
  return offset
end

function AiItems.effect(item)
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  local info = ok and ItemsData.info(item_num(item)) or nil
  local e = info and info.effect
  if type(e) ~= "table" or #e < 6 then return nil end
  local off = band(e[5], 0x04) ~= 0 and param_offset(e, 4, 0x04) or 0
  return { tonumber(e[1]) or 0, tonumber(e[2]) or 0, tonumber(e[3]) or 0, tonumber(e[4]) or 0, tonumber(e[5]) or 0,
    tonumber(e[6]) or 0, hp = off ~= 0 and tonumber(e[off + 1]) or nil }
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
