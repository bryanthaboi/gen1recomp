-- FireRed battle AI command handlers (port of battle_ai_script_commands.c).

local Moves = require("src.core.game3.battle.moves")
local Types = require("src.core.game3.battle.types")
local Damage = require("src.core.game3.battle.damage")
local EffectIds = require("src.core.game3.battle.effect_ids")

local AiCmds = {}

local function bit_or_local(a, b)
  a = math.floor(a or 0)
  b = math.floor(b or 0)
  local r, bitv = 0, 1
  for _ = 1, 32 do
    if (a % 2) > 0 or (b % 2) > 0 then r = r + bitv end
    a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
  end
  return r
end

local function bit_and_local(a, b)
  a = math.floor(a or 0)
  b = math.floor(b or 0)
  local r, bitv = 0, 1
  for _ = 1, 32 do
    if (a % 2) > 0 and (b % 2) > 0 then r = r + bitv end
    a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
  end
  return r
end

-- pret STATUS1 bits
local STATUS1 = {
  SLEEP = 0x7,
  POISON = 0x8,
  BURN = 0x10,
  FREEZE = 0x20,
  PARALYSIS = 0x40,
  TOXIC_POISON = 0x80,
  PSN_ANY = 0x88,
  ANY = 0xFF,
}

local STATUS2 = {
  CONFUSION = 0x7,
  FLINCHED = 0x8,
  UPROAR = 0x70,
  BIDE = 0x300,
  MULTIPLETURNS = 0x1000,
  WRAPPED = 0xE000,
  FOCUS_ENERGY = 0x100000,
  TRANSFORMED = 0x200000,
  RECHARGE = 0x400000,
  RAGE = 0x800000,
  SUBSTITUTE = 0x1000000,
  DESTINY_BOND = 0x2000000,
  ESCAPE_PREVENTION = 0x4000000,
  NIGHTMARE = 0x8000000,
  CURSED = 0x10000000,
  FORESIGHT = 0x20000000,
  DEFENSE_CURL = 0x40000000,
  TORMENT = 0x80000000,
}

local STATUS3 = {
  LEECHSEED = 0x4,
  ALWAYS_HITS = 0x18,
  PERISH_SONG = 0x20,
  ON_AIR = 0x40,
  UNDERGROUND = 0x80,
  MINIMIZED = 0x100,
  CHARGED_UP = 0x200,
  ROOTED = 0x400,
  YAWN = 0x1800,
  IMPRISONED_OTHERS = 0x2000,
  MUDSPORT = 0x10000,
  WATERSPORT = 0x20000,
  UNDERWATER = 0x40000,
  SEMI_INVULNERABLE = 0x400C0,
}

local SIDE_STATUS = {
  REFLECT = 0x1,
  LIGHTSCREEN = 0x2,
  SPIKES = 0x10,
  SAFEGUARD = 0x20,
  FUTUREATTACK = 0x40,
  MIST = 0x100,
}

local DISCOURAGED = {
  [EffectIds.EXPLOSION or 7] = true,
  [EffectIds.DREAM_EATER or 8] = true,
  [EffectIds.RAZOR_WIND or 39] = true,
  [EffectIds.SKY_ATTACK or 75] = true,
  [EffectIds.RECHARGE or 80] = true,
  [EffectIds.SKULL_BASH or 145] = true,
  [EffectIds.SOLAR_BEAM or 151] = true,
  [EffectIds.SPIT_UP or 161] = true,
  [EffectIds.FOCUS_PUNCH or 170] = true,
  [EffectIds.SUPERPOWER or 186] = true,
  [EffectIds.ERUPTION or 187] = true,
  [EffectIds.OVERHEAT or 204] = true,
}

local STAT_KEY = {
  [1] = "attack",
  [2] = "defense",
  [3] = "speed",
  [4] = "spAtk",
  [5] = "spDef",
  [6] = "accuracy",
  [7] = "evasion",
}

local function rng(vm, lo, hi)
  local r = vm.rng
  if type(r) == "function" then
    local ok, v = pcall(r, lo, hi)
    if ok and type(v) == "number" then return v end
    ok, v = pcall(r)
    if ok and type(v) == "number" then
      if hi and lo then
        return lo + (math.floor(v) % (hi - lo + 1))
      end
      return v
    end
  end
  if hi and lo then return math.random(lo, hi) end
  return math.random(0, 255)
end

local function random_u16(vm)
  -- pret Random() returns u16; scripts use % 256 / % 16 / % num
  return rng(vm, 0, 65535)
end

function AiCmds.battler(vm, id)
  -- AI_USER=1 → attacker (enemy), AI_TARGET=0 → target (player)
  if id == 1 or id == "AI_USER" then return vm.user end
  return vm.target
end

function AiCmds.side_of(vm, battler)
  if battler == vm.user then return vm.userSide end
  return vm.targetSide
end

local function status1_bits(battler)
  local st = battler and (battler.status or (battler.mon and battler.mon.status))
  if not st then return 0 end
  if type(st) == "number" then return st end
  local s = tostring(st):upper()
  if s == "SLP" or s == "SLEEP" then return STATUS1.SLEEP end
  if s == "PSN" or s == "POISON" then return STATUS1.POISON end
  if s == "BRN" or s == "BURN" then return STATUS1.BURN end
  if s == "FRZ" or s == "FREEZE" then return STATUS1.FREEZE end
  if s == "PAR" or s == "PARALYSIS" then return STATUS1.PARALYSIS end
  if s == "TOX" or s == "TOXIC" then return STATUS1.TOXIC_POISON end
  return 0
end

local function status2_bits(battler)
  if not battler then return 0 end
  local b = 0
  if battler.confusionTurns and battler.confusionTurns > 0 then b = bit_or_local(b, STATUS2.CONFUSION) end
  if battler.focusEnergy or battler.expFocusEnergy then b = bit_or_local(b, STATUS2.FOCUS_ENERGY) end
  if (battler.substituteHP or 0) > 0 then b = bit_or_local(b, STATUS2.SUBSTITUTE) end
  if battler.wrapped or battler.trapped then b = bit_or_local(b, STATUS2.WRAPPED) end
  if battler.meanLook or battler.escapePrevention then b = bit_or_local(b, STATUS2.ESCAPE_PREVENTION) end
  if battler.bideTurns then b = bit_or_local(b, STATUS2.BIDE) end
  if battler.recharge then b = bit_or_local(b, STATUS2.RECHARGE) end
  if battler.rage then b = bit_or_local(b, STATUS2.RAGE) end
  if battler.torment then b = bit_or_local(b, STATUS2.TORMENT) end
  if battler.destinyBond then b = bit_or_local(b, STATUS2.DESTINY_BOND) end
  if battler.cursed then b = bit_or_local(b, STATUS2.CURSED) end
  if battler.foresight then b = bit_or_local(b, STATUS2.FORESIGHT) end
  if battler.defenseCurl then b = bit_or_local(b, STATUS2.DEFENSE_CURL) end
  if battler.transformed then b = bit_or_local(b, STATUS2.TRANSFORMED) end
  return b
end

local function status3_bits(battler)
  if not battler then return 0 end
  local b = 0
  if battler.leechSeed or battler.expLeechSeed then b = bit_or_local(b, STATUS3.LEECHSEED) end
  if battler.rooted or battler.ingrain then b = bit_or_local(b, STATUS3.ROOTED) end
  if battler.yawnTurns then b = bit_or_local(b, STATUS3.YAWN) end
  if battler.minimized then b = bit_or_local(b, STATUS3.MINIMIZED) end
  if battler.chargedUp then b = bit_or_local(b, STATUS3.CHARGED_UP) end
  if battler.mudSport then b = bit_or_local(b, STATUS3.MUDSPORT) end
  if battler.waterSport then b = bit_or_local(b, STATUS3.WATERSPORT) end
  if battler.perishSong then b = bit_or_local(b, STATUS3.PERISH_SONG) end
  if battler.underground then b = bit_or_local(b, STATUS3.UNDERGROUND) end
  if battler.onAir or battler.fly then b = bit_or_local(b, STATUS3.ON_AIR) end
  if battler.underwater then b = bit_or_local(b, STATUS3.UNDERWATER) end
  return b
end

local function side_status_bits(side)
  if not side then return 0 end
  local b = 0
  if (side.expReflectTurns or 0) > 0 or side.reflect then b = bit_or_local(b, SIDE_STATUS.REFLECT) end
  if (side.expLightScreenTurns or 0) > 0 or side.lightScreen then b = bit_or_local(b, SIDE_STATUS.LIGHTSCREEN) end
  if (side.expSafeguardTurns or 0) > 0 or side.safeguard then b = bit_or_local(b, SIDE_STATUS.SAFEGUARD) end
  if side.mist or (side.expMistTurns or 0) > 0 then b = bit_or_local(b, SIDE_STATUS.MIST) end
  if side.hazards then
    for _, h in ipairs(side.hazards) do
      if h == "spikes" or (type(h) == "table" and h.kind == "spikes") then
        b = bit_or_local(b, SIDE_STATUS.SPIKES)
      end
    end
  end
  if side.tokens then
    for _, tok in ipairs(side.tokens) do
      local k = tok.kind or tok.id
      if k == "reflect" then b = bit_or_local(b, SIDE_STATUS.REFLECT) end
      if k == "light_screen" or k == "lightScreen" then b = bit_or_local(b, SIDE_STATUS.LIGHTSCREEN) end
      if k == "safeguard" then b = bit_or_local(b, SIDE_STATUS.SAFEGUARD) end
      if k == "mist" then b = bit_or_local(b, SIDE_STATUS.MIST) end
    end
  end
  return b
end

local function move_effect(moveId)
  local m = Moves.get(moveId)
  if not m then return 0 end
  local e = m.effect
  if type(e) == "number" then return e end
  return 0
end

local function move_power(moveId)
  local m = Moves.get(moveId)
  return m and tonumber(m.power) or 0
end

local function move_type(moveId)
  local m = Moves.get(moveId)
  return m and tonumber(m.type) or 0
end

local function mon_types(battler)
  local t1 = battler and (battler.type1 or 0) or 0
  local t2 = battler and battler.type2 or t1
  return t1, t2
end

local function ability_of(battler)
  if not battler then return 0 end
  local a = battler.ability or battler.abilityId
  if battler.mon then
    a = a or battler.mon.ability or battler.mon.abilityId
  end
  return tonumber(a) or 0
end

local function hp_percent(battler)
  if not battler or not battler.mon then return 0 end
  local hp = tonumber(battler.mon.hp) or 0
  local maxHp = tonumber(battler.mon.maxHp) or 1
  if maxHp < 1 then maxHp = 1 end
  return math.floor(100 * hp / maxHp)
end

local function pret_stat_level(battler, statId)
  local key = STAT_KEY[statId]
  if not key then return 6 end
  local stages = battler and battler.stages or {}
  local s = tonumber(stages[key]) or 0
  return s + 6 -- pret 0..12 with 6 neutral
end

-- src/pokemon.c:2552
local function spread_hit(vm, moveId)
  local st = vm.st
  if not (st and st.double) then return nil end
  local m = Moves.get(moveId)
  if bit_and_local(tonumber(m and m.target) or 0, 0x08) == 0 then return nil end
  local State = require("src.core.game3.battle.state")
  local id = State.idOf(vm.target)
  if id == nil then return nil end
  return State.countPresentOnSide(st, State.sideOf(id)) == 2 or nil
end

local function ai_damage(vm, moveId, movesetIndex)
  local dmg = Damage.calc(vm.user, vm.target, moveId, {
    forceCrit = false,
    forceRoll = 100,
    weather = vm.st and vm.st.weather,
    rng = function() return 100 end,
    spread = spread_hit(vm, moveId),
  })
  local sim = vm.simulatedRNG and vm.simulatedRNG[movesetIndex] or 100
  dmg = math.floor(dmg * sim / 100)
  if dmg == 0 then dmg = 1 end
  return dmg
end

local function branch(vm, target)
  if type(target) == "string" then
    vm:jump(target)
  end
end

local function next_ip(vm)
  vm.ip = vm.ip + 1
end

-- Command dispatch table
local CMD = {}

function CMD.score(vm, op)
  local idx = vm.movesetIndex
  local s = (vm.scores[idx] or 100) + (op.delta or 0)
  if s < 0 then s = 0 end
  if s > 127 then s = 127 end -- s8 clamp (pret stores s8)
  vm.scores[idx] = s
  next_ip(vm)
end

CMD["goto"] = function(vm, op)
  branch(vm, op.target)
end

function CMD.call(vm, op)
  vm.stack[#vm.stack + 1] = { script = vm.scriptName, ip = vm.ip + 1 }
  branch(vm, op.target)
end

CMD["end"] = function(vm, op)
  if #vm.stack > 0 then
    local frame = table.remove(vm.stack)
    vm:jump(frame.script, frame.ip)
  else
    vm.done = true
  end
end

function CMD.flee(vm, op)
  vm.aiAction = bit_or_local(vm.aiAction or 0, 0x2 + 0x1 + 0x8) -- FLEE|DONE|DO_NOT_ATTACK
  vm.done = true
end

function CMD.watch(vm, op)
  vm.aiAction = bit_or_local(vm.aiAction or 0, 0x4 + 0x1 + 0x8)
  vm.done = true
end

local function cmd_null(vm, op)
  next_ip(vm)
end

CMD.ai_2a = cmd_null
CMD.ai_2b = cmd_null
CMD.ai_32 = cmd_null
CMD.ai_33 = cmd_null
CMD.ai_52 = cmd_null
CMD.ai_53 = cmd_null
CMD.ai_54 = cmd_null
CMD.ai_55 = cmd_null
CMD.ai_56 = cmd_null
CMD.ai_57 = cmd_null

function CMD.if_random_less_than(vm, op)
  if (random_u16(vm) % 256) < (op.value or 0) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_random_greater_than(vm, op)
  if (random_u16(vm) % 256) > (op.value or 0) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_random_equal(vm, op)
  if (random_u16(vm) % 256) == (op.value or 0) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_random_not_equal(vm, op)
  if (random_u16(vm) % 256) ~= (op.value or 0) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

local function hp_cmp(vm, op, pred)
  local b = AiCmds.battler(vm, op.battler)
  local pct = hp_percent(b)
  if pred(pct, op.percent or 0) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_hp_less_than(vm, op) hp_cmp(vm, op, function(a, b) return a < b end) end
function CMD.if_hp_more_than(vm, op) hp_cmp(vm, op, function(a, b) return a > b end) end
function CMD.if_hp_equal(vm, op) hp_cmp(vm, op, function(a, b) return a == b end) end
function CMD.if_hp_not_equal(vm, op) hp_cmp(vm, op, function(a, b) return a ~= b end) end

local function status_cmp(vm, op, getBits, wantSet)
  local b = AiCmds.battler(vm, op.battler)
  local bits = getBits(b)
  local mask = op.status or 0
  local hit = bit_and_local(bits, mask) ~= 0
  if (wantSet and hit) or ((not wantSet) and (not hit)) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_status(vm, op) status_cmp(vm, op, status1_bits, true) end
function CMD.if_not_status(vm, op) status_cmp(vm, op, status1_bits, false) end
function CMD.if_status2(vm, op) status_cmp(vm, op, status2_bits, true) end
function CMD.if_not_status2(vm, op) status_cmp(vm, op, status2_bits, false) end
function CMD.if_status3(vm, op) status_cmp(vm, op, status3_bits, true) end
function CMD.if_not_status3(vm, op) status_cmp(vm, op, status3_bits, false) end

local function side_cmp(vm, op, wantSet)
  local b = AiCmds.battler(vm, op.battler)
  local side = AiCmds.side_of(vm, b)
  local bits = side_status_bits(side)
  local hit = bit_and_local(bits, op.status or 0) ~= 0
  if (wantSet and hit) or ((not wantSet) and (not hit)) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_side_affecting(vm, op) side_cmp(vm, op, true) end
function CMD.if_not_side_affecting(vm, op) side_cmp(vm, op, false) end

local function result_cmp(vm, op, pred)
  if pred(vm.funcResult or 0, op.value or 0) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_less_than(vm, op) result_cmp(vm, op, function(a, b) return a < b end) end
function CMD.if_more_than(vm, op) result_cmp(vm, op, function(a, b) return a > b end) end
function CMD.if_equal(vm, op) result_cmp(vm, op, function(a, b) return a == b end) end
function CMD.if_not_equal(vm, op) result_cmp(vm, op, function(a, b) return a ~= b end) end
CMD.if_equal_ = CMD.if_equal
CMD.if_not_equal_ = CMD.if_not_equal

function CMD.if_less_than_ptr(vm, op) next_ip(vm) end -- unused / ptr stubs
function CMD.if_more_than_ptr(vm, op) next_ip(vm) end
function CMD.if_equal_ptr(vm, op) next_ip(vm) end
function CMD.if_not_equal_ptr(vm, op) next_ip(vm) end

function CMD.if_move(vm, op)
  if vm.moveConsidered == (op.move or -1) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_not_move(vm, op)
  if vm.moveConsidered ~= (op.move or -1) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

local function in_list(vm, listName, isHword)
  local list = vm.pack and vm.pack.data and vm.pack.data[listName]
  if not list then return false end
  local term = isHword and 0xFFFF or 0xFF
  local fr = vm.funcResult or 0
  for _, v in ipairs(list) do
    if v == term then break end
    if v == fr then return true end
  end
  return false
end

function CMD.if_in_bytes(vm, op)
  if in_list(vm, op.list, false) then branch(vm, op.target) else next_ip(vm) end
end
function CMD.if_not_in_bytes(vm, op)
  if not in_list(vm, op.list, false) then branch(vm, op.target) else next_ip(vm) end
end
function CMD.if_in_hwords(vm, op)
  if in_list(vm, op.list, true) then branch(vm, op.target) else next_ip(vm) end
end
function CMD.if_not_in_hwords(vm, op)
  if not in_list(vm, op.list, true) then branch(vm, op.target) else next_ip(vm) end
end

local function has_attacking(vm)
  local mon = vm.user and vm.user.mon
  if not mon or not mon.moves then return false end
  for i = 1, 4 do
    local mv = mon.moves[i]
    if mv and mv ~= 0 and mv ~= "" and move_power(mv) ~= 0 then return true end
  end
  return false
end

function CMD.if_user_has_attacking_move(vm, op)
  if has_attacking(vm) then branch(vm, op.target) else next_ip(vm) end
end
function CMD.if_user_has_no_attacking_moves(vm, op)
  if not has_attacking(vm) then branch(vm, op.target) else next_ip(vm) end
end

function CMD.get_turn_count(vm, op)
  vm.funcResult = (vm.st and vm.st.turn) or 0
  next_ip(vm)
end

function CMD.get_type(vm, op)
  local which = op.which or 0
  local t1u, t2u = mon_types(vm.user)
  local t1t, t2t = mon_types(vm.target)
  if which == 0 then vm.funcResult = t1t -- AI_TYPE1_TARGET
  elseif which == 1 then vm.funcResult = t1u
  elseif which == 2 then vm.funcResult = t2t
  elseif which == 3 then vm.funcResult = t2u
  elseif which == 4 then vm.funcResult = move_type(vm.moveConsidered)
  else vm.funcResult = 0 end
  next_ip(vm)
end

function CMD.get_considered_move_power(vm, op)
  vm.funcResult = move_power(vm.moveConsidered)
  next_ip(vm)
end

function CMD.get_how_powerful_move_is(vm, op)
  local considered = vm.moveConsidered
  local eff = move_effect(considered)
  local pow = move_power(considered)
  if DISCOURAGED[eff] or pow <= 1 then
    vm.funcResult = 0 -- MOVE_POWER_DISCOURAGED
    next_ip(vm)
    return
  end
  local moveDmgs = {}
  local mon = vm.user.mon
  for i = 1, 4 do
    local mv = mon and mon.moves and mon.moves[i]
    local e = mv and move_effect(mv) or 0
    local p = mv and move_power(mv) or 0
    if mv and mv ~= 0 and mv ~= "" and not DISCOURAGED[e] and p > 1 then
      moveDmgs[i] = ai_damage(vm, mv, i)
    else
      moveDmgs[i] = 0
    end
  end
  local best = true
  local mine = moveDmgs[vm.movesetIndex] or 0
  for i = 1, 4 do
    if (moveDmgs[i] or 0) > mine then
      best = false
      break
    end
  end
  vm.funcResult = best and 2 or 1 -- MOST / NOT_MOST
  next_ip(vm)
end

function CMD.get_last_used_move(vm, op)
  local b = AiCmds.battler(vm, op.battler)
  vm.funcResult = (b and b.lastMove) or 0
  next_ip(vm)
end

function CMD.if_would_go_first(vm, op)
  -- 0 = user(attacker) first, 1 = target first
  local userSpe = tonumber(vm.user.mon and (vm.user.mon.speed or vm.user.mon.spe)) or 0
  local tgtSpe = tonumber(vm.target.mon and (vm.target.mon.speed or vm.target.mon.spe)) or 0
  local us = pret_stat_level(vm.user, 3) -- speed stage already in Damage; use stages
  local ts = pret_stat_level(vm.target, 3)
  -- Approximate with stage mul via Damage
  userSpe = userSpe * (Damage.stageMul((vm.user.stages and vm.user.stages.speed) or 0))
  tgtSpe = tgtSpe * (Damage.stageMul((vm.target.stages and vm.target.stages.speed) or 0))
  local first = (userSpe >= tgtSpe) and 0 or 1
  if first == (op.battler or 0) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_would_not_go_first(vm, op)
  local userSpe = tonumber(vm.user.mon and (vm.user.mon.speed or vm.user.mon.spe)) or 0
  local tgtSpe = tonumber(vm.target.mon and (vm.target.mon.speed or vm.target.mon.spe)) or 0
  userSpe = userSpe * (Damage.stageMul((vm.user.stages and vm.user.stages.speed) or 0))
  tgtSpe = tgtSpe * (Damage.stageMul((vm.target.stages and vm.target.stages.speed) or 0))
  local first = (userSpe >= tgtSpe) and 0 or 1
  if first ~= (op.battler or 0) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.count_alive_pokemon(vm, op)
  local b = AiCmds.battler(vm, op.battler)
  local party = (b == vm.user) and (vm.st and vm.st.foeParty) or (vm.st and vm.st.playerParty)
  local onField = b and b.partyIndex or 1
  local onField2 = onField
  local n = 0
  -- src/battle_ai_script_commands.c:1099
  if vm.st and vm.st.double then
    local State = require("src.core.game3.battle.state")
    local id = State.idOf(b)
    local partner = id and State.battler(vm.st, State.PARTNER(id))
    onField2 = partner and partner.partyIndex or onField
  end
  for i = 1, 6 do
    local mon = party and party[i]
    local sp = mon and (mon.species or mon.id)
    if i ~= onField and i ~= onField2 and (tonumber(mon and mon.hp) or 0) ~= 0
        and sp and sp ~= 0 and not mon.isEgg then
      n = n + 1
    end
  end
  vm.funcResult = n
  next_ip(vm)
end

function CMD.get_considered_move(vm, op)
  vm.funcResult = vm.moveConsidered or 0
  next_ip(vm)
end

function CMD.get_considered_move_effect(vm, op)
  vm.funcResult = move_effect(vm.moveConsidered)
  next_ip(vm)
end

function CMD.get_ability(vm, op)
  local b = AiCmds.battler(vm, op.battler)
  -- Player (target) side: use known ability or guess; enemy (user): known
  if b == vm.target then
    vm.funcResult = ability_of(b)
  else
    vm.funcResult = ability_of(b)
  end
  next_ip(vm)
end

function CMD.get_highest_type_effectiveness(vm, op)
  local best = 0
  local mon = vm.user.mon
  local t1, t2 = mon_types(vm.target)
  for i = 1, 4 do
    local mv = mon and mon.moves and mon.moves[i]
    if mv and mv ~= 0 and mv ~= "" then
      local mt = move_type(mv)
      local u1, u2 = mon_types(vm.user)
      local hasStab = (mt == u1 or mt == u2)
      local units = Types.aiTypeCalcUnits(mt, t1, t2, hasStab)
      if units > best then best = units end
    end
  end
  vm.funcResult = best
  next_ip(vm)
end

function CMD.if_type_effectiveness(vm, op)
  local mt = move_type(vm.moveConsidered)
  local t1, t2 = mon_types(vm.target)
  local u1, u2 = mon_types(vm.user)
  local hasStab = (mt == u1 or mt == u2)
  local units = Types.aiTypeCalcUnits(mt, t1, t2, hasStab)
  if units == (op.effectiveness or -1) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_status_in_party(vm, op)
  -- Best-effort: scan party for matching status1 bits
  local party = (op.battler == 1) and (vm.st and vm.st.foeParty) or (vm.st and vm.st.playerParty)
  local mask = op.status or 0
  if party then
    for _, mon in ipairs(party) do
      if mon and (tonumber(mon.hp) or 0) > 0 then
        local fake = { status = mon.status, mon = mon }
        if bit_and_local(status1_bits(fake), mask) ~= 0 or status1_bits(fake) == mask then
          -- pret compares status == statusToCompareTo exactly for in_party
          local bits = status1_bits(fake)
          if bits == mask or (mask ~= 0 and bit_and_local(bits, mask) == mask) then
            branch(vm, op.target)
            return
          end
        end
      end
    end
  end
  next_ip(vm)
end

function CMD.if_status_not_in_party(vm, op)
  -- Bugged in pret; treat as no-op branch skip
  next_ip(vm)
end

function CMD.get_weather(vm, op)
  local w = vm.st and vm.st.weather
  -- AI_WEATHER_SUN=0 RAIN=1 SAND=2 HAIL=3; no weather leaves 0 (pret zero-init)
  if w == "rain" or w == "RAIN" then vm.funcResult = 1
  elseif w == "sandstorm" or w == "SANDSTORM" or w == "sand" then vm.funcResult = 2
  elseif w == "sun" or w == "SUN" or w == "sunny" then vm.funcResult = 0
  elseif w == "hail" or w == "HAIL" then vm.funcResult = 3
  else vm.funcResult = 0
  end
  next_ip(vm)
end

function CMD.if_effect(vm, op)
  if move_effect(vm.moveConsidered) == (op.effect or -1) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_not_effect(vm, op)
  if move_effect(vm.moveConsidered) ~= (op.effect or -1) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

local function stat_cmp(vm, op, pred)
  local b = AiCmds.battler(vm, op.battler)
  local lvl = pret_stat_level(b, op.stat)
  if pred(lvl, op.level or 0) then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_stat_level_less_than(vm, op) stat_cmp(vm, op, function(a, b) return a < b end) end
function CMD.if_stat_level_more_than(vm, op) stat_cmp(vm, op, function(a, b) return a > b end) end
function CMD.if_stat_level_equal(vm, op) stat_cmp(vm, op, function(a, b) return a == b end) end
function CMD.if_stat_level_not_equal(vm, op) stat_cmp(vm, op, function(a, b) return a ~= b end) end

function CMD.if_can_faint(vm, op)
  if move_power(vm.moveConsidered) < 2 then
    next_ip(vm)
    return
  end
  local dmg = ai_damage(vm, vm.moveConsidered, vm.movesetIndex)
  local hp = tonumber(vm.target.mon and vm.target.mon.hp) or 0
  if hp <= dmg then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.if_cant_faint(vm, op)
  if move_power(vm.moveConsidered) < 2 then
    next_ip(vm)
    return
  end
  local dmg = ai_damage(vm, vm.moveConsidered, vm.movesetIndex)
  local hp = tonumber(vm.target.mon and vm.target.mon.hp) or 0
  if hp > dmg then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

local function mon_has_move(battler, moveId)
  local mon = battler and battler.mon
  if not mon or not mon.moves then return false end
  for i = 1, 4 do
    local mv = mon.moves[i]
    if mv == moveId then return true end
    if type(mv) == "string" and Moves.BY_NUM[moveId] == mv then return true end
  end
  return false
end

function CMD.if_has_move(vm, op)
  local b = AiCmds.battler(vm, op.battler)
  if mon_has_move(b, op.move) then branch(vm, op.target) else next_ip(vm) end
end
function CMD.if_doesnt_have_move(vm, op)
  local b = AiCmds.battler(vm, op.battler)
  if not mon_has_move(b, op.move) then branch(vm, op.target) else next_ip(vm) end
end

local function mon_has_effect(battler, effect)
  local mon = battler and battler.mon
  if not mon or not mon.moves then return false end
  for i = 1, 4 do
    local mv = mon.moves[i]
    if mv and mv ~= 0 and mv ~= "" and move_effect(mv) == effect then return true end
  end
  return false
end

function CMD.if_has_move_with_effect(vm, op)
  local b = AiCmds.battler(vm, op.battler)
  if b == vm.target then
    -- pret history path — best-effort use known moves
    if mon_has_effect(b, op.effect) then branch(vm, op.target) else next_ip(vm) end
  else
    if mon_has_effect(b, op.effect) then branch(vm, op.target) else next_ip(vm) end
  end
end

function CMD.if_doesnt_have_move_with_effect(vm, op)
  local b = AiCmds.battler(vm, op.battler)
  if not mon_has_effect(b, op.effect) then branch(vm, op.target) else next_ip(vm) end
end

function CMD.if_any_move_disabled_or_encored(vm, op)
  -- best-effort false
  next_ip(vm)
end

function CMD.if_curr_move_disabled_or_encored(vm, op)
  next_ip(vm)
end

-- pokefirered/src/battle_ai_script_commands.c:1713
function CMD.if_random_safari_flee(vm, op)
  local Rules = require("src.core.game3.battle.rules")
  local rate = Rules.safari.fleeRate(vm.st and vm.st.safariState)
  if (random_u16(vm) % 100) < rate then
    branch(vm, op.target)
  else
    next_ip(vm)
  end
end

function CMD.get_hold_effect(vm, op)
  vm.funcResult = 0 -- HOLD_EFFECT_NONE / ITEM_NONE
  next_ip(vm)
end

function CMD.get_gender(vm, op)
  vm.funcResult = 0
  next_ip(vm)
end

function CMD.is_first_turn_for(vm, op)
  local b = AiCmds.battler(vm, op.battler)
  vm.funcResult = (b and b.isFirstTurn) and 1 or 0
  if b and b.isFirstTurn == nil and vm.st and (vm.st.turn or 0) <= 1 then
    vm.funcResult = 1
  end
  next_ip(vm)
end

function CMD.get_stockpile_count(vm, op)
  local b = AiCmds.battler(vm, op.battler)
  vm.funcResult = (b and b.stockpile) or 0
  next_ip(vm)
end

-- src/battle_ai_script_commands.c:1806
function CMD.is_double_battle(vm, op)
  vm.funcResult = (vm.st and vm.st.double) and 1 or 0
  next_ip(vm)
end

function CMD.get_used_held_item(vm, op)
  vm.funcResult = 0
  next_ip(vm)
end

function CMD.get_move_type_from_result(vm, op)
  vm.funcResult = move_type(vm.funcResult)
  next_ip(vm)
end

function CMD.get_move_power_from_result(vm, op)
  vm.funcResult = move_power(vm.funcResult)
  next_ip(vm)
end

function CMD.get_move_effect_from_result(vm, op)
  vm.funcResult = move_effect(vm.funcResult)
  next_ip(vm)
end

function CMD.get_protect_count(vm, op)
  local b = AiCmds.battler(vm, op.battler)
  -- pokefirered/src/battle_ai_script_commands.c:1847-1856
  vm.funcResult = (b and b.expProtectStreak) or 0
  next_ip(vm)
end

function CMD.if_level_cond(vm, op)
  local ul = tonumber(vm.user.mon and vm.user.mon.level) or 1
  local tl = tonumber(vm.target.mon and vm.target.mon.level) or 1
  local cond = op.cond or 0
  local ok = false
  if cond == 0 then ok = ul > tl
  elseif cond == 1 then ok = ul < tl
  elseif cond == 2 then ok = ul == tl
  end
  if ok then branch(vm, op.target) else next_ip(vm) end
end

function CMD.if_target_taunted(vm, op)
  next_ip(vm) -- false
end

function CMD.if_target_not_taunted(vm, op)
  branch(vm, op.target) -- always true (taunt unsupported)
end

function AiCmds.dispatch(vm, op)
  if not op or not op.op then
    vm.done = true
    return
  end
  local fn = CMD[op.op]
  if fn then
    fn(vm, op)
  else
    -- unknown: skip safely
    next_ip(vm)
  end
end

AiCmds.CMD = CMD
AiCmds.STATUS1 = STATUS1
AiCmds.move_effect = move_effect
AiCmds.move_power = move_power
AiCmds.ai_damage = ai_damage

return AiCmds
