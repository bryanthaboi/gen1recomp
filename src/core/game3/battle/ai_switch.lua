-- FireRed battle AI switch decision (port of battle_ai_switch_items.c).

local State = require("src.core.game3.battle.state")
local Moves = require("src.core.game3.battle.moves")
local Types = require("src.core.game3.battle.types")
local Pokemon = require("src.core.game3.pokemon")

local AiSwitch = {}

local AB = {
  VOLT_ABSORB = 10, WATER_ABSORB = 11, FLASH_FIRE = 18, SHADOW_TAG = 23,
  WONDER_GUARD = 25, LEVITATE = 26, NATURAL_CURE = 30, MAGNET_PULL = 42, ARENA_TRAP = 71,
}
local MOVE_STRUGGLE = 165
local LAST_HIT_NONE = 0xFF

local ABILITY_BY_NAME
local function ability_id(v)
  if v == nil then return 0 end
  local n = tonumber(v)
  if n then return n end
  if type(v) ~= "string" or v == "" then return 0 end
  if not ABILITY_BY_NAME then
    ABILITY_BY_NAME = {}
    local ok, Adapter = pcall(require, "src.core.game3.battle.adapter")
    if ok and Adapter and Adapter.ABILITY_BY_ID then
      for id, name in pairs(Adapter.ABILITY_BY_ID) do ABILITY_BY_NAME[name] = id end
    end
  end
  return ABILITY_BY_NAME[(v:upper():gsub("%s+", "_"))] or 0
end

local function battler_ability(b)
  if not b then return 0 end
  if b.expTracedAbility then return ability_id(b.expTracedAbility) end
  local a = b.ability
  if a == nil and b.mon then a = b.mon.ability or b.mon.abilityId end
  return ability_id(a)
end

local function move_num(mv)
  local n = tonumber(mv)
  if n then return n end
  if mv == nil or mv == "" then return 0 end
  return Moves.numForName and Moves.numForName(mv) or 0
end

local function move_def(mv)
  local n = move_num(mv)
  if n == 0 then return nil end
  return Moves.get(mv)
end

local function move_power(mv)
  local m = move_def(mv)
  return m and tonumber(m.power) or 0
end

local function move_type(mv)
  local m = move_def(mv)
  return m and tonumber(m.type) or 0
end

local function species_of(mon)
  if not mon then return 0 end
  local s = mon.species or mon.speciesId or mon.id
  if type(s) == "number" then return s end
  if type(s) == "string" then
    return (Pokemon.speciesFromName and Pokemon.speciesFromName(s)) or tonumber(s) or 0
  end
  return 0
end

local function mon_usable(mon)
  return mon ~= nil and (tonumber(mon.hp) or 0) ~= 0 and species_of(mon) ~= 0 and not mon.isEgg
end

-- src/battle_ai_switch_items.c:112
local function party_ability(mon)
  local explicit = mon and (mon.ability or mon.abilityId)
  if explicit ~= nil then return ability_id(explicit) end
  local pair = Pokemon.abilities(species_of(mon))
  local num = mon and mon.abilityNum
  if num == nil then
    num = ((pair[2] or 0) ~= 0) and ((tonumber(mon and mon.personality) or 0) % 2) or 0
  end
  if num ~= 0 then return pair[2] or 0 end
  return pair[1] or 0
end

-- src/battle_script_commands.c:1513
local function ai_type_calc(mv, species, ability)
  local f = { super = false, notVery = false, noEffect = false }
  if move_num(mv) == MOVE_STRUGGLE or move_num(mv) == 0 then return f end
  local mt = move_type(mv)
  local power = move_power(mv)
  if ability == AB.LEVITATE and mt == Types.ID.GROUND then
    f.noEffect = true
  else
    local ty = Pokemon.types(species)
    local t1, t2 = ty[1] or 0, ty[2] or 0
    local function modulate(mult)
      if mult == 0 then
        f.noEffect, f.notVery, f.super = true, false, false
      elseif mult == 5 then
        if power ~= 0 and not f.noEffect then
          if f.super then f.super = false else f.notVery = true end
        end
      elseif mult == 20 then
        if power ~= 0 and not f.noEffect then
          if f.notVery then f.notVery = false else f.super = true end
        end
      end
    end
    local t = Types.TABLE
    for i = 1, #t, 3 do
      local a, d, m = t[i], t[i + 1], t[i + 2]
      if a ~= -1 and a == mt then
        if d == t1 then modulate(m) end
        if d == t2 and t1 ~= t2 then modulate(m) end
      end
    end
  end
  if ability == AB.WONDER_GUARD and (not f.super or (f.super and f.notVery)) and power ~= 0 then
    f.noEffect = true
  end
  return f
end
AiSwitch.aiTypeCalc = ai_type_calc

local function roll(rng, lo, hi)
  local ok, v = pcall(rng, lo, hi)
  if ok and type(v) == "number" then return v end
  return require("src.core.game3.battle.link_guard").fallback("ai_switch.roll", lo, hi)
end

local function status_bits(b)
  local s = b and (b.status or (b.mon and b.mon.status))
  if type(s) == "number" then return s end
  s = s and tostring(s):upper() or ""
  if s == "SLP" or s == "SLEEP" then return 0x7 end
  return 0
end

local function moves_of(b)
  return (b and b.mon and b.mon.moves) or {}
end

local function last_landed(b)
  return move_num(b and b.expLastLandedMove)
end

local function last_hit_by(b)
  local id = b and b.expLastHitById
  if id == nil then return LAST_HIT_NONE end
  return id
end

local function battlers_in(st, id)
  local in2 = id
  if st.double then
    local pid = State.PARTNER(id)
    if not State.isAbsent(st, pid) and State.battler(st, pid) then in2 = pid end
  end
  return id, in2
end

local function excluded(st, i, in1, in2)
  local b1, b2 = State.battler(st, in1), State.battler(st, in2)
  local pend = st.monToSwitchInto or {}
  return (b1 and b1.partyIndex == i) or (b2 and b2.partyIndex == i)
    or pend[in1] == i or pend[in2] == i
end

local function num_battlers(st)
  return st.double and 4 or 2
end

-- src/battle_ai_switch_items.c:17
local function if_perish_song(st, b)
  if b.perishSong and tonumber(b.expPerishTurns) == 0 then return true, nil end
  return false
end

-- src/battle_ai_switch_items.c:32
local function if_wonder_guard(st, b, id, rng)
  if st.double then return false end
  local opp = State.battler(st, 0)
  if not opp or battler_ability(opp) ~= AB.WONDER_GUARD then return false end
  for i = 1, 4 do
    local mv = moves_of(b)[i]
    if move_num(mv) ~= 0 and ai_type_calc(mv, opp.species, battler_ability(opp)).super then return false end
  end
  for i = 1, 6 do
    local mon = st.foeParty and st.foeParty[i]
    if mon_usable(mon) and i ~= b.partyIndex then
      for j = 1, 4 do
        local mv = mon.moves and mon.moves[j]
        if move_num(mv) ~= 0 and ai_type_calc(mv, opp.species, battler_ability(opp)).super
            and roll(rng, 0, 2) < 2 then
          return true, i
        end
      end
    end
  end
  return false
end

-- src/battle_ai_switch_items.c:176
local function has_super_effective(st, b, noRng, rng)
  local function scan(oid)
    local opp = State.battler(st, oid)
    if State.isAbsent(st, oid) or not opp then return false end
    for i = 1, 4 do
      local mv = moves_of(b)[i]
      if move_num(mv) ~= 0 and ai_type_calc(mv, opp.species, battler_ability(opp)).super then
        if noRng or roll(rng, 0, 9) ~= 0 then return true end
      end
    end
    return false
  end
  if scan(0) then return true end
  if not st.double then return false end
  return scan(2)
end

-- src/battle_ai_switch_items.c:82
local function absorbs_opponents_move(st, b, id, rng)
  if (has_super_effective(st, b, true, rng) and roll(rng, 0, 2) ~= 0) or last_landed(b) == 0 then
    return false
  end
  local last = b.expLastLandedMove
  if last_landed(b) == 0xFFFF or move_power(last) == 0 then return false end
  local mt = move_type(last)
  local absorb
  if mt == Types.ID.FIRE then absorb = AB.FLASH_FIRE
  elseif mt == Types.ID.WATER then absorb = AB.WATER_ABSORB
  elseif mt == Types.ID.ELECTRIC then absorb = AB.VOLT_ABSORB
  else return false end
  if battler_ability(b) == absorb then return false end
  local in1, in2 = battlers_in(st, id)
  for i = 1, 6 do
    local mon = st.foeParty and st.foeParty[i]
    if mon_usable(mon) and not excluded(st, i, in1, in2) then
      if absorb == party_ability(mon) and roll(rng, 0, 1) == 1 then return true, i end
    end
  end
  return false
end

-- src/battle_ai_switch_items.c:236
local function find_mon_with_flags(st, b, id, flag, modulo, rng)
  local last = last_landed(b)
  if last == 0 then return false end
  if last == 0xFFFF or last_hit_by(b) == LAST_HIT_NONE or move_power(b.expLastLandedMove) == 0 then
    return false
  end
  local in1, in2 = battlers_in(st, id)
  for i = 1, 6 do
    local mon = st.foeParty and st.foeParty[i]
    if mon_usable(mon) and not excluded(st, i, in1, in2) then
      local f = ai_type_calc(b.expLastLandedMove, species_of(mon), party_ability(mon))
      if f[flag] then
        local opp = State.battler(st, last_hit_by(b))
        for j = 1, 4 do
          local mv = mon.moves and mon.moves[j]
          if move_num(mv) ~= 0 and opp
              and ai_type_calc(mv, opp.species, battler_ability(opp)).super
              and roll(rng, 0, modulo - 1) == 0 then
            return true, i
          end
        end
      end
    end
  end
  return false
end

-- src/battle_ai_switch_items.c:146
local function if_natural_cure(st, b, id, rng)
  local hp = tonumber(b.mon and b.mon.hp) or 0
  local maxHp = tonumber(b.mon and b.mon.maxHp) or 1
  if status_bits(b) % 8 == 0 or battler_ability(b) ~= AB.NATURAL_CURE or hp < math.floor(maxHp / 2) then
    return false
  end
  local last = last_landed(b)
  if (last == 0 or last == 0xFFFF) and roll(rng, 0, 1) == 1 then
    return true, nil
  elseif move_power(last) == 0 and roll(rng, 0, 1) == 1 then
    return true, nil
  end
  local ok, pick = find_mon_with_flags(st, b, id, "noEffect", 1, rng)
  if ok then return true, pick end
  ok, pick = find_mon_with_flags(st, b, id, "notVery", 1, rng)
  if ok then return true, pick end
  if roll(rng, 0, 1) == 1 then return true, nil end
  return false
end

-- src/battle_ai_switch_items.c:223
local function stats_raised(b)
  local total = 0
  for _, v in pairs(b.stages or {}) do
    v = tonumber(v) or 0
    if v > 0 then total = total + v end
  end
  return total > 3
end

local function is_steel(b)
  return b.type1 == Types.ID.STEEL or b.type2 == Types.ID.STEEL
end

-- src/battle_ai_switch_items.c:302
function AiSwitch.shouldSwitch(st, id, rng)
  local b = State.battler(st, id)
  if not b or not b.mon then return false end
  if b.expTrapped or b.escapePrevention or (tonumber(b.expTrapTurns) or 0) > 0 or b.expIngrain then
    return false
  end
  for oid = 0, num_battlers(st) - 1 do
    local o = State.battler(st, oid)
    if o and State.sideOf(oid) ~= State.sideOf(id) then
      local a = battler_ability(o)
      if a == AB.SHADOW_TAG or a == AB.ARENA_TRAP then return false end
    end
  end
  for oid = 0, num_battlers(st) - 1 do
    local o = State.battler(st, oid)
    if o and battler_ability(o) == AB.MAGNET_PULL and is_steel(b) then return false end
  end
  local in1, in2 = battlers_in(st, id)
  local available = 0
  for i = 1, 6 do
    local mon = st.foeParty and st.foeParty[i]
    if mon_usable(mon) and not excluded(st, i, in1, in2) then available = available + 1 end
  end
  if available == 0 then return false end

  local ok, pick = if_perish_song(st, b)
  if ok then return true, pick end
  ok, pick = if_wonder_guard(st, b, id, rng)
  if ok then return true, pick end
  ok, pick = absorbs_opponents_move(st, b, id, rng)
  if ok then return true, pick end
  ok, pick = if_natural_cure(st, b, id, rng)
  if ok then return true, pick end
  if has_super_effective(st, b, false, rng) or stats_raised(b) then return false end
  ok, pick = find_mon_with_flags(st, b, id, "noEffect", 2, rng)
  if ok then return true, pick end
  ok, pick = find_mon_with_flags(st, b, id, "notVery", 3, rng)
  if ok then return true, pick end
  return false
end

-- src/battle_ai_switch_items.c:358
function AiSwitch.trySwitch(st, ad, id, rng)
  local ok, pick = AiSwitch.shouldSwitch(st, id, rng)
  if not ok then return nil end
  if pick == nil then
    local Engine = require("src.core.game3.battle.engine")
    if Engine.mostSuitableMon then pick = Engine.mostSuitableMon(st, ad, id) end
    if pick == nil then
      local in1, in2 = 1, st.double and 3 or 1
      for i = 1, 6 do
        local mon = st.foeParty and st.foeParty[i]
        if mon and (tonumber(mon.hp) or 0) ~= 0 and not excluded(st, i, in1, in2) then
          pick = i
          break
        end
      end
    end
  end
  return pick
end

return AiSwitch
