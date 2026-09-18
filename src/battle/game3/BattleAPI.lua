-- Read-only FireRed battle state with the same shape as mod.battle on Gen 1 / Gen 2.

local Gen3Compat = require("src.mods.Gen3Compat")

local BattleAPI = {}
BattleAPI.__index = BattleAPI

function BattleAPI.new(game)
  return setmetatable({ game = game, revision = 0, signature = nil }, BattleAPI)
end

local function battleModule()
  return package.loaded["src.core.game3.battle.init"]
    or package.loaded["src.core.game3.battle"]
end

local function ui()
  return package.loaded["src.core.game3.battle.ui"]
end

local function message()
  return package.loaded["src.ui.game3.message"]
end

local function activeBattle()
  local B = battleModule()
  if not (B and B.isActive and B.isActive()) then return nil end
  local st = B.getState and B.getState()
  if not st then return nil end
  return st, B
end

local function session()
  local R = package.loaded["src.core.game3.runtime"]
  return R and R.getSession and R.getSession() or nil
end

local function displayName(mon, species)
  if mon and mon.nickname and mon.nickname ~= "" then return mon.nickname end
  local P = package.loaded["src.core.game3.pokemon"]
  if P and P.name then return P.name(species) end
  return mon and mon.name or tostring(species)
end

local function monCopy(mon, active)
  if not mon then return nil end
  local P = package.loaded["src.core.game3.pokemon"]
  local species = P and P.speciesOf and P.speciesOf(mon) or mon.species
  return { species = Gen3Compat.speciesName(species) or species,
    gen3Species = species, name = displayName(mon, species),
    level = mon.level, hp = mon.hp,
    maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp,
    status = mon.status, active = active and true or false }
end

local function messageCopy()
  local M = message()
  if not (M and M.isOpen and M.isOpen() and M.currentPage) then return nil end
  local lines = {}
  for line in tostring(M.currentPage() or ""):gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end
  return #lines > 0 and lines or nil
end

local function ballCopies(catchable)
  local out = {}
  local s = session()
  local Bag = package.loaded["src.core.game3.bag"]
  if not (s and s.bag and Bag and Bag.listPocket) then return out end
  local ok, rows = pcall(Bag.listPocket, s.bag, "POKE_BALLS")
  if not ok or type(rows) ~= "table" then return out end
  for _, row in ipairs(rows) do
    out[#out + 1] = { id = row.id, name = row.name or tostring(row.id),
      count = row.qty, ball = true, needsTarget = false,
      catchable = catchable and true or false }
  end
  table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
  return out
end

local function slot(st, id)
  if id == 0 then return st.player end
  if id == 1 then return st.enemy end
  return st.battlers and st.battlers[id] or nil
end

local function activeId(st)
  if not st.double then return 0 end
  local U = ui()
  local id = (U and tonumber(U._active)) or tonumber(st.activeBattler) or 0
  if id ~= 0 and id ~= 2 then id = 0 end
  return id
end

local function battlerCopies(st)
  local out = {}
  for id = 0, (st.double and 3 or 1) do
    local b = slot(st, id)
    local absent = st.absent and st.absent[id] or false
    if b then
      local copy = monCopy(b.mon, not absent) or {}
      copy.id, copy.side = id, b.side or (id % 2 == 0 and "player" or "enemy")
      copy.absent = absent and true or false
      copy.partyIndex = b.partyIndex
      out[#out + 1] = copy
    end
  end
  return out
end

local function moveCopies(st)
  local out = {}
  local b = slot(st, activeId(st))
  local mon = b and b.mon
  if not mon then return out end
  local Moves = package.loaded["src.core.game3.battle.moves"]
  for slot = 1, 4 do
    local id = mon.moves and mon.moves[slot]
    if id and id ~= 0 and id ~= "" then
      local def = Moves and Moves.get and Moves.get(id) or {}
      out[#out + 1] = { slot = slot, id = id,
        name = Moves and Moves.displayName and Moves.displayName(id) or tostring(id),
        pp = mon.pp and mon.pp[slot],
        maxPp = (mon.maxPp and mon.maxPp[slot]) or def.pp,
        type = def.type, power = def.power, accuracy = def.accuracy }
    end
  end
  return out
end

local function prompt(B)
  local U = ui()
  if B._phase == "command" and U then
    if U._mode == "menu" then return "menu" end
    if U._mode == "moves" then return "moves" end
    if U._mode == "target" then return "target" end
    if U._mode == "party" then return "party" end
  end
  local M = message()
  if M and M.isWaiting and M.isWaiting() then return "advance" end
  return "locked"
end

local function signature(st, B)
  if not st then return "none" end
  local U = ui() or {}
  local parts = { tostring(st), tostring(B._phase), tostring(U._mode),
    tostring(U._menuIndex), tostring(U._moveIndex), tostring(st.turn),
    tostring(st.over), tostring(st.result), tostring(U._active),
    tostring(U._target and U._target.cursor),
    table.concat(messageCopy() or {}, "\n") }
  for id = 0, (st.double and 3 or 1) do
    local battler = slot(st, id)
    local mon = battler and battler.mon
    parts[#parts + 1] = tostring(mon)
    parts[#parts + 1] = tostring(mon and mon.hp)
    parts[#parts + 1] = tostring(mon and mon.status)
    parts[#parts + 1] = tostring(st.absent and st.absent[id])
  end
  for _, mon in ipairs(st.playerParty or {}) do
    parts[#parts + 1] = tostring(mon)
    parts[#parts + 1] = tostring(mon.hp)
    parts[#parts + 1] = tostring(mon.status)
  end
  for _, item in ipairs(ballCopies(false)) do
    parts[#parts + 1] = tostring(item.id) .. "=" .. tostring(item.count)
  end
  return table.concat(parts, "|")
end

function BattleAPI:_revision(st, B)
  local nextSignature = signature(st, B)
  if nextSignature ~= self.signature then
    self.signature = nextSignature
    self.revision = self.revision + 1
  end
  return self.revision
end

function BattleAPI:snapshot()
  local st, B = activeBattle()
  if not st then return nil end
  local catchable = st.wild and not st.ghost and not st.noCatch
  local party = {}
  local b2 = st.double and slot(st, 2) or nil
  for i, mon in ipairs(st.playerParty or {}) do
    party[i] = monCopy(mon, (st.player and st.player.mon == mon) or (b2 and b2.mon == mon))
    party[i].slot = i
  end
  local active = activeId(st)
  local U = ui()
  local targets
  if U and U._mode == "target" then
    targets = {}
    for id = 0, 3 do
      local b = slot(st, id)
      if b and not (st.absent and st.absent[id]) then targets[#targets + 1] = id end
    end
  end
  local snap = { revision = self:_revision(st, B), kind = st.kind or (st.wild and "wild" or "trainer"),
    catchable = catchable and true or false, prompt = prompt(B),
    message = messageCopy(), turn = st.turn or 0,
    double = st.double and true or false, active = active,
    player = monCopy(slot(st, active) and slot(st, active).mon, true),
    enemy = monCopy(st.enemy and st.enemy.mon, true),
    battlers = battlerCopies(st), targets = targets,
    target = U and U._target and U._target.cursor or nil,
    party = party, moves = moveCopies(st), items = ballCopies(catchable) }
  return snap
end

local MENU_INDEX = { fight = 1, item = 2, party = 3, run = 4 }

local function validSlot(slot)
  return type(slot) == "number" and slot % 1 == 0 and slot >= 1
end

local function press(key)
  return { wasPressed = function(_, k) return k == key end,
           isDown = function() return false end }
end

function BattleAPI:submit(intent)
  if type(intent) ~= "table" then return nil, "intent must be a table" end
  if type(intent.id) ~= "number" or intent.id % 1 ~= 0 or intent.id < 1 then
    return nil, "intent id must be a positive integer"
  end
  if self.lastIntentId and intent.id <= self.lastIntentId then
    return nil, "replayed intent"
  end
  local st, B = activeBattle()
  if not st then return nil, "no battle" end
  if intent.revision ~= self:_revision(st, B) then
    return nil, "stale battle context"
  end
  if B._auto then return nil, "battle kind is not controllable" end
  local U = ui()
  if not (U and U.handleInput) or B._phase ~= "command" then
    return nil, "battle menu is covered"
  end
  if intent.kind == "menu" then
    if U._mode ~= "menu" then return nil, "battle menu is not active" end
    local index = MENU_INDEX[intent.choice]
    if not index then return nil, "unknown battle menu choice" end
    U._menuIndex = index
    U.handleInput(press("a"))
  elseif intent.kind == "move" then
    if U._mode ~= "moves" then return nil, "move menu is not active" end
    local user = slot(st, activeId(st))
    local mon = user and user.mon
    local move = validSlot(intent.slot) and mon and mon.moves
      and mon.moves[intent.slot]
    if not move or move == 0 or move == "" then return nil, "invalid move slot" end
    local pp = mon.pp and tonumber(mon.pp[intent.slot])
    if pp and pp <= 0 then return nil, "move has no PP" end
    U._moveIndex = intent.slot
    U.handleInput(press("a"))
  elseif intent.kind == "target" then
    if U._mode ~= "target" or not U._target then return nil, "target cursor is not active" end
    local id = intent.target
    if type(id) ~= "number" or id % 1 ~= 0 or id < 0 or id > 3 then
      return nil, "target must be a battler id 0-3"
    end
    if not slot(st, id) or (st.absent and st.absent[id]) then
      return nil, "no battler in that slot"
    end
    if id == U._target.battler then
      local mon = slot(st, id).mon
      local mv = mon and mon.moves and mon.moves[U._target.slot]
      local Moves = package.loaded["src.core.game3.battle.moves"]
      local def = Moves and mv and Moves.get(mv)
      if math.floor((tonumber(def and def.target) or 0) / 2) % 2 ~= 1 then
        return nil, "that move cannot target its user"
      end
    end
    U._target.cursor = id
    U.handleInput(press("a"))
  elseif intent.kind == "back" then
    if U._mode ~= "moves" and U._mode ~= "target" then return nil, "move menu is not active" end
    U.handleInput(press("b"))
  else
    return nil, "unknown battle intent"
  end
  self.lastIntentId = intent.id
  self.signature = nil
  return true
end

return BattleAPI
