-- Battle state: battlers, sides, weather, result.

local Damage = require("src.core.game3.battle.damage")
local Pokemon = require("src.core.game3.pokemon")
local bit = require("bit")

local State = {}

local function species_id(mon)
  if not mon then return 1 end
  local s = mon.species or mon.id
  if type(s) == "number" then return s end
  if type(s) == "string" then
    local id = Pokemon.speciesFromName(s)
    if id then return id end
    return tonumber(s) or 1
  end
  return 1
end

local function types_for(species)
  if not Pokemon._types then
    local okI, errI = pcall(Pokemon.install, nil)
    if not okI and not Pokemon._installWarned then
      Pokemon._installWarned = true
      print("[game3/pokemon] install failed: " .. tostring(errI))
    end
  end
  local t = Pokemon.types(species)
  return t[1] or 0, t[2] or 0
end

local function held_item(mon)
  if not mon then return 0 end
  return tonumber(mon.item or mon.heldItem) or 0
end

function State.makeBattler(mon, side, opts)
  opts = opts or {}
  local id = tonumber(opts.id) or ((side == "enemy") and 1 or 0)
  mon = Damage.ensureStats(mon, mon and mon.level)
  local species = species_id(mon)
  local t1, t2 = types_for(species)
  local ability = mon.ability or mon.abilityId
  if not ability and Pokemon.abilityId then
    ability = Pokemon.abilityId(species, mon.personality or 0)
  end
  local b = {
    mon = mon,
    id = id,
    side = side, -- "player" | "enemy"
    flank = (id < 2) and "left" or "right",
    partyIndex = opts.partyIndex or 1,
    species = species,
    type1 = t1,
    type2 = (t2 ~= t1) and t2 or nil,
    ability = ability,
    item = held_item(mon),
    stages = {
      attack = 0, defense = 0, spAtk = 0, spDef = 0, speed = 0,
      accuracy = 0, evasion = 0,
    },
    status = mon.status,
    fainted = (tonumber(mon.hp) or 0) <= 0,
    -- pokefirered/src/battle_main.c:2228
    isFirstTurn = 2,
  }
  -- pokefirered/src/battle_script_commands.c:4489
  if opts.st and State.isKnockedOff(opts.st, b) then
    b.item = 0
    b.expKnockedOff = true
  end
  return b
end

-- pokefirered/src/battle_main.c:2565
function State.zeroBattler(b)
  if type(b) ~= "table" then return b end
  b.mon = { species = 0, level = 0, hp = 0, maxHp = 0, moves = {}, pp = {} }
  b.species = 0
  b.type1, b.type2 = 0, nil
  b.ability = nil
  b.item = 0
  b.status = nil
  b.partyIndex = nil
  b._partyMon = nil
  b.participants = nil
  b.stages = {
    attack = 0, defense = 0, spAtk = 0, spDef = 0, speed = 0,
    accuracy = 0, evasion = 0,
  }
  b.isFirstTurn = 0
  b.zeroed = true
  return b
end

function State.PARTNER(id) return (id + 2) % 4 end
function State.OPPOSITE(id) return (id % 2 == 0) and (id + 1) or (id - 1) end
function State.sideOf(id) return (id % 2 == 0) and "player" or "enemy" end
function State.flankOf(id) return (id < 2) and "left" or "right" end
function State.positionsOnSide(side) return (side == "player") and { 0, 2 } or { 1, 3 } end

function State.idOf(b)
  if type(b) == "number" then return b end
  if type(b) == "string" then return (b == "enemy") and 1 or 0 end
  if type(b) ~= "table" then return nil end
  if b.id then return b.id end
  if b.side == "enemy" then return 1 end
  if b.side == "player" then return 0 end
  return nil
end

function State.battler(st, id)
  if not st or id == nil then return nil end
  if st.battlers then return st.battlers[id] end
  if id == 0 then return st.player end
  if id == 1 then return st.enemy end
  return nil
end

function State.occupant(st, b)
  if b == nil or not st then return b end
  if type(b) == "string" then return st[b] end
  local id = State.idOf(b)
  if id == nil then return b end
  return State.battler(st, id) or b
end

function State.isAbsent(st, id)
  return st and st.absent and st.absent[id] and true or false
end

function State.isPresent(st, id)
  return State.battler(st, id) ~= nil and not State.isAbsent(st, id)
end

function State.isAlive(st, id)
  return State.isPresent(st, id) and not State.isFainted(State.battler(st, id))
end

function State.partner(st, b)
  local id = State.idOf(b)
  if id == nil or not (st and st.double) then return nil end
  local p = State.PARTNER(id)
  if not State.isPresent(st, p) then return nil end
  return State.battler(st, p)
end

function State.opposite(st, b)
  local id = State.idOf(b)
  if id == nil then return nil end
  return State.battler(st, State.OPPOSITE(id))
end

function State.presentIds(st)
  local out = {}
  for id = 0, 3 do
    if State.isPresent(st, id) then out[#out + 1] = id end
  end
  return out
end

function State.present(st)
  local out = {}
  for id = 0, 3 do
    if State.isPresent(st, id) then out[#out + 1] = State.battler(st, id) end
  end
  return out
end

function State.foes(st, b)
  local id = State.idOf(b)
  local out = {}
  if id == nil then return out end
  for i = 0, 3 do
    if i % 2 ~= id % 2 and State.isPresent(st, i) then out[#out + 1] = State.battler(st, i) end
  end
  return out
end

function State.allies(st, b)
  local id = State.idOf(b)
  local out = {}
  if id == nil then return out end
  for i = 0, 3 do
    if i % 2 == id % 2 and State.isPresent(st, i) then out[#out + 1] = State.battler(st, i) end
  end
  return out
end

-- pokefirered/src/pokemon.c:2651
function State.countPresentOnSide(st, side)
  local n = 0
  for _, id in ipairs(State.positionsOnSide(side)) do
    if State.isPresent(st, id) then n = n + 1 end
  end
  return n
end

-- pokefirered/src/battle_main.c:3400
function State.speedOrder(st, adapter, opts)
  opts = opts or {}
  local Engine = package.loaded["src.core.game3.battle.engine"]
  local ids = State.presentIds(st)
  local spe = {}
  for _, id in ipairs(ids) do
    local b = State.battler(st, id)
    if Engine and Engine.speedOf then
      spe[id] = Engine.speedOf(b, st, adapter)
    else
      spe[id] = tonumber(b.mon and (b.mon.speed or b.mon.spe)) or 50
    end
  end
  local function coin()
    if adapter and adapter.roll then return adapter:roll(0, 1) end
    return math.random(0, 1)
  end
  for i = 1, #ids - 1 do
    for j = i + 1, #ids do
      local a, b = ids[i], ids[j]
      local pa = opts.priority and opts.priority[a] or 0
      local pb = opts.priority and opts.priority[b] or 0
      local swap
      if pa ~= pb then
        swap = pa < pb
      elseif spe[a] == spe[b] then
        swap = coin() == 1
      else
        swap = spe[a] < spe[b]
      end
      if swap then ids[i], ids[j] = b, a end
    end
  end
  return ids
end

local function battler_slots(st)
  return setmetatable({}, {
    __index = function(_, k)
      if k == 0 then return st.player end
      if k == 1 then return st.enemy end
      return nil
    end,
    __newindex = function(t, k, v)
      if k == 0 then st.player = v
      elseif k == 1 then st.enemy = v
      else rawset(t, k, v) end
    end,
  })
end
State.newSlots = battler_slots

local function first_usable(party, exclude)
  for i = 1, #(party or {}) do
    local m = party[i]
    if i ~= exclude and m and not m.isEgg and (tonumber(m.hp) or 0) > 0
        and (tonumber(m.species or m.speciesId) or 0) ~= 0 then
      return i
    end
  end
  return nil
end
State.firstUsable = first_usable

function State.new(opts)
  opts = opts or {}
  local playerParty = opts.playerParty or {}
  local pi = opts.playerIndex or first_usable(playerParty) or 1
  local foeMon = opts.foeMon
  local foeParty = opts.foeParty or { foeMon }
  local ei = opts.foeIndex or first_usable(foeParty) or 1
  local eMon = foeMon or (foeParty and foeParty[ei]) or (foeParty and foeParty[1])
  local st = {
    kind = opts.wild and "wild" or "trainer",
    wild = opts.wild and true or false,
    playerParty = playerParty,
    foeParty = foeParty,
    player = nil,
    enemy = nil,
    playerSide = { hazards = {}, id = "player" },
    enemySide = { hazards = {}, id = "enemy" },
    weather = opts.weather,
    weatherTurns = 0,
    terrain = opts.terrain,
    turn = 0,
    over = false,
    result = nil,
    rng = opts.rng or require("src.core.game3.rng").compat,
    fleeAttempts = 0,
    log = {},
  }
  st.double = opts.double and true or false
  st.battlersCount = st.double and 4 or 2
  st.battlers = battler_slots(st)
  st.absent = {}
  st.chosen = {}
  st.turnOrder = {}
  st.monToSwitchInto = {}
  st.moveTarget = {}
  local pMon = playerParty[pi]
  st.player = State.makeBattler(pMon, "player", { partyIndex = pi, id = 0 })
  st.enemy = State.makeBattler(eMon, "enemy", { partyIndex = ei, id = 1 })
  if not st.double then
    State.trackParticipant(st, st.enemy, pi)
    return st
  end
  -- pokefirered/src/battle_controllers.c:290
  local p2 = opts.partnerIndex or first_usable(playerParty, pi)
  if p2 and playerParty[p2] then
    st.battlers[2] = State.makeBattler(playerParty[p2], "player", { partyIndex = p2, id = 2 })
  else
    st.absent[2] = true
  end
  local e2 = opts.foePartnerIndex or first_usable(st.foeParty, st.enemy.partyIndex)
  if e2 and st.foeParty[e2] then
    st.battlers[3] = State.makeBattler(st.foeParty[e2], "enemy", { partyIndex = e2, id = 3 })
  else
    st.absent[3] = true
  end
  State.resetSentPokes(st)
  return st
end

-- pokefirered/src/battle_util.c:239
function State.resetSentPokes(st)
  local sent = {}
  for _, id in ipairs({ 0, 2 }) do
    local b = State.battler(st, id)
    if b and b.partyIndex and not State.isAbsent(st, id) then sent[#sent + 1] = b.partyIndex end
  end
  for _, id in ipairs({ 1, 3 }) do
    local foe = State.battler(st, id)
    if foe then
      foe.participants = {}
      for _, pi in ipairs(sent) do foe.participants[pi] = true end
    end
  end
  if st.enemy and not st.enemy.participants then
    st.enemy.participants = {}
    if st.player and st.player.partyIndex and not State.isAbsent(st, 0) then
      st.enemy.participants[st.player.partyIndex] = true
    end
  end
end

-- pokefirered/src/battle_util.c:254
function State.opponentSwitchInResetSentPokes(st, foeBattler)
  if not foeBattler then return end
  foeBattler.participants = {}
  for _, id in ipairs({ 0, 2 }) do
    local b = State.battler(st, id)
    if b and not State.isAbsent(st, id) and b.partyIndex then
      foeBattler.participants[b.partyIndex] = true
    end
  end
  if not st.double and st.player and not State.isAbsent(st, 0) and st.player.partyIndex then
    foeBattler.participants[st.player.partyIndex] = true
  end
end

-- pokefirered/src/battle_util.c:273
function State.updateSentPokes(st, battler)
  if not battler then return end
  if battler.side == "enemy" then
    return State.opponentSwitchInResetSentPokes(st, battler)
  end
  for _, id in ipairs({ 1, 3 }) do
    local foe = State.battler(st, id)
    if foe then State.trackParticipant(st, foe, battler.partyIndex) end
  end
  if not st.double and st.enemy then
    State.trackParticipant(st, st.enemy, battler.partyIndex)
  end
end

function State.displayName(battler)
  if not battler then return "POKéMON" end
  local mon = battler.mon
  if mon and mon.nickname and mon.nickname ~= "" then return mon.nickname end
  pcall(function()
    if not Pokemon._names then Pokemon.install(nil) end
  end)
  return Pokemon.name(battler.species)
end

-- src/battle_message.c:1807
function State.text(st, id, fill)
  fill = require("src.core.game3.battle.adapter").fill(st, fill)
  return require("src.core.game3.battle.battle_text").get(id, fill)
end

function State.prefixedName(st, battler, name)
  name = name or State.displayName(battler)
  if battler and battler.side == "player" then return name end
  local RomText = require("src.core.game3.rom_text")
  local prefix = (st ~= nil and not st.wild) and "sText_FoePkmnPrefix" or "sText_WildPkmnPrefix"
  local ok, pre = pcall(RomText.plain, prefix)
  return (ok and pre or (st ~= nil and not st.wild and "Foe " or "Wild ")) .. name
end

function State.isFainted(battler)
  if not battler then return true end
  if type(battler) == "string" then return false end
  return battler.fainted or (tonumber(battler.mon and battler.mon.hp) or 0) <= 0
end

function State.applyHpLoss(battler, amount)
  if not battler or not battler.mon then return 0 end
  amount = math.floor(tonumber(amount) or 0)
  if amount < 0 then amount = 0 end
  local hp = tonumber(battler.mon.hp) or 0
  local lost = math.min(hp, amount)
  battler.mon.hp = hp - lost
  if battler.mon.hp <= 0 then
    battler.mon.hp = 0
    battler.fainted = true
  end
  return lost
end

function State.heal(battler, amount)
  if not battler or not battler.mon then return 0 end
  amount = math.floor(tonumber(amount) or 0)
  local hp = tonumber(battler.mon.hp) or 0
  local maxHp = tonumber(battler.mon.maxHp) or hp
  local nextHp = math.min(maxHp, hp + amount)
  local gained = nextHp - hp
  battler.mon.hp = nextHp
  if nextHp > 0 then battler.fainted = false end
  return gained
end

function State.ensureBattleMoves(battler)
  if not battler or not battler.mon then return nil end
  if battler._partyMon then return battler.mon end
  local base = battler.mon
  local moves, pp = {}, {}
  for i = 1, 4 do
    moves[i] = base.moves and base.moves[i] or nil
    pp[i] = base.pp and base.pp[i] or nil
  end
  local proxy = setmetatable({ moves = moves, pp = pp }, {
    __index = base,
    __newindex = base,
  })
  battler._partyMon = base
  battler.mon = proxy
  battler.permanentSlots = battler.permanentSlots or { true, true, true, true }
  return proxy
end

function State.partyMon(battler)
  if not battler then return nil end
  return battler._partyMon or battler.mon
end

-- pret pokefirered/src/battle_main.c gWishFutureKnock.knockedOffMons: one bit
-- per party index per side.  A mon whose item was knocked off stays marked for
-- the rest of the battle even after it switches out and back in -- the
-- per-battler `expKnockedOff` volatile dies with the battler, so Thief and
-- Trick would otherwise be allowed against it again.
local function knocked_off_key(b)
  local side = b and b.side
  if side ~= "player" and side ~= "enemy" then return nil end
  local idx = tonumber(b and b.partyIndex) or 1
  if idx < 1 or idx > 6 then return nil end
  return side, bit.lshift(1, idx - 1)
end

function State.markKnockedOff(st, b)
  if not st then return end
  local side, flag = knocked_off_key(b)
  if not side then return end
  st.knockedOff = st.knockedOff or { player = 0, enemy = 0 }
  st.knockedOff[side] = bit.bor(st.knockedOff[side] or 0, flag)
end

function State.isKnockedOff(st, b)
  if not st then return false end
  local side, flag = knocked_off_key(b)
  if not side then return false end
  return bit.band((st.knockedOff and st.knockedOff[side]) or 0, flag) ~= 0
end

function State.wipeVolatilesAndStages(battler, opts)
  opts = opts or {}
  if not battler then return end
  if not opts.batonPass then
    battler.stages = {
      attack = 0, defense = 0, spAtk = 0, spDef = 0, speed = 0,
      accuracy = 0, evasion = 0,
    }
  end
  -- Volatile status conditions
  battler.volatiles = opts.batonPass and battler.volatiles or {}
  battler.confusion = opts.batonPass and battler.confusion or nil
  battler.seeded = nil
  battler.trapped = nil
  battler.attracted = nil
  battler.substitute = opts.batonPass and battler.substitute or nil
  battler.focusEnergy = opts.batonPass and battler.focusEnergy or nil
  battler.toxicCounter = nil
  battler.disabled = nil
  battler.encore = nil
  battler.taunt = nil
  battler.bide = nil
  battler.rage = nil
  battler.endure = nil
  battler.protect = nil
  battler.destinyBond = nil
  battler.perishSong = opts.batonPass and battler.perishSong or nil
end

function State.syncBattlerToParty(battler, party)
  if not battler or not party then return end
  -- pokefirered/src/battle_main.c:2565
  if battler.zeroed then return end
  local idx = battler.partyIndex or 1
  local mon = party[idx]
  if not mon then return end
  local bMon = battler.mon
  if not bMon then return end
  mon.hp = tonumber(bMon.hp) or 0
  mon.maxHp = tonumber(bMon.maxHp) or mon.maxHp
  local status = battler.status or bMon.status
  if status == 0 then status = nil end
  mon.status = status
  mon.sleep = bMon.sleep
  mon.level = bMon.level or mon.level
  mon.exp = bMon.exp or mon.exp
  if battler._partyMon then
    -- pokefirered/include/battle.h:28
    local perm = battler.permanentSlots or {}
    mon.pp = mon.pp or {}
    mon.moves = mon.moves or {}
    for i = 1, 4 do
      if perm[i] and not battler.transformed then
        mon.pp[i] = bMon.pp and bMon.pp[i] or mon.pp[i]
        if battler.sketched and battler.sketched[i] then
          mon.moves[i] = bMon.moves[i]
        end
      end
    end
    return
  end
  if bMon.pp then mon.pp = bMon.pp end
  if bMon.moves then mon.moves = bMon.moves end
end

function State.trackParticipant(st, foeBattler, partyIndex)
  if not st or not foeBattler then return end
  foeBattler.participants = foeBattler.participants or {}
  partyIndex = partyIndex or (st.player and st.player.partyIndex) or 1
  foeBattler.participants[partyIndex] = true
end

return State
