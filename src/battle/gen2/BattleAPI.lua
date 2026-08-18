-- Read-only Gen 2 battle state with the same shape as mod.battle on Gen 1.

local BattleAPI = {}
BattleAPI.__index = BattleAPI

function BattleAPI.new(game)
  return setmetatable({ game = game, revision = 0, signature = nil }, BattleAPI)
end

local function activeBattle(game)
  local states = game and game.stack and game.stack.states or {}
  local battle
  for i = #states, 1, -1 do
    local state = states[i]
    if state.screenId == "Gen2BattleState" or state.isGen2BattleState then
      battle = state
      break
    end
  end
  return battle, states[#states]
end

local function monCopy(data, mon, active)
  if not mon then return nil end
  local def = data and data.pokemon and data.pokemon[mon.species]
  return { species = mon.species,
    name = mon.nickname or (def and def.name) or mon.species,
    level = mon.level, hp = mon.hp,
    maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp,
    status = mon.status, active = active and true or false }
end

local function messageCopy(screen)
  if not screen.message then return nil end
  local lines = {}
  for line in tostring(screen.message):gmatch("[^\n]+") do
    lines[#lines + 1] = line
  end
  return #lines > 0 and lines or nil
end

local function itemCopies(game, screen, catchable)
  local out = {}
  for id, count in pairs((game.save and game.save.inventory) or {}) do
    local def = game.data.items and game.data.items[id]
    if count > 0 and def and def.pocket == "BALL" then
      out[#out + 1] = { id = id, name = def.name or id, count = count,
        ball = true, needsTarget = false,
        catchChance = catchable and screen.catchChance
          and screen:catchChance(id) or nil }
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function signature(game, screen, top)
  if not screen then return "none" end
  local battle = screen.battle or {}
  local parts = { tostring(screen), tostring(top), tostring(screen.phase),
    tostring(screen.message), tostring(screen.messageTimer),
    tostring(screen.menuIndex), tostring(screen.moveIndex),
    tostring(battle.turn), tostring(battle.over), tostring(battle.outcome) }
  for _, mon in ipairs({ battle.player, battle.enemy }) do
    parts[#parts + 1] = tostring(mon)
    parts[#parts + 1] = tostring(mon and mon.hp)
    parts[#parts + 1] = tostring(mon and mon.status)
  end
  for _, mon in ipairs((game.save and game.save.party) or battle.party or {}) do
    parts[#parts + 1] = tostring(mon)
    parts[#parts + 1] = tostring(mon.hp)
    parts[#parts + 1] = tostring(mon.status)
  end
  for _, item in ipairs(itemCopies(game, screen, false)) do
    parts[#parts + 1] = item.id .. "=" .. tostring(item.count)
  end
  return table.concat(parts, "|")
end

function BattleAPI:_revision(screen, top)
  local nextSignature = signature(self.game, screen, top)
  if nextSignature ~= self.signature then
    self.signature = nextSignature
    self.revision = self.revision + 1
  end
  return self.revision
end

local function moveCopies(game, battle)
  local out = {}
  for slot, move in ipairs((battle.player and battle.player.moves) or {}) do
    local def = (game.data.moves or {})[move.id] or {}
    out[slot] = { slot = slot, id = move.id, name = def.name or move.id,
      pp = move.pp, maxPp = move.maxPp or def.pp or move.pp,
      type = def.type, power = def.power, accuracy = def.accuracy,
      disabled = battle:moveDisabled(battle.player, move.id) }
  end
  return out
end

local function battleKind(screen)
  if screen.tutorial then return "oldman" end
  return screen.battle and screen.battle.wild and "wild" or "trainer"
end

function BattleAPI:snapshot()
  local game = self.game
  local screen, top = activeBattle(game)
  if not screen or not screen.battle then return nil end
  local battle = screen.battle
  local prompt = "locked"
  if top == screen and screen.phase == "menu" then
    prompt = "menu"
  elseif top == screen and screen.phase == "moves" then
    prompt = "moves"
  elseif top == screen and screen.message then
    prompt = "advance"
  elseif top and top.screenId == "Gen2PartyMenu" then
    prompt = "party"
  end
  local party = {}
  for i, mon in ipairs((game.save and game.save.party) or battle.party or {}) do
    party[i] = monCopy(game.data, mon, mon == battle.player)
    party[i].slot = i
  end
  return { revision = self:_revision(screen, top), kind = battleKind(screen),
    catchable = battle.wild and not screen.tutorial, prompt = prompt,
    message = messageCopy(screen), turn = battle.turn or 0,
    player = monCopy(game.data, battle.player, true),
    enemy = monCopy(game.data, battle.enemy, true),
    party = party, moves = moveCopies(game, battle),
    -- Targeted medicine remains screen-owned, but balls are complete semantic
    -- records and can safely expose the same read-only preview as Gen 1.
    items = itemCopies(game, screen, battle.wild and not screen.tutorial) }
end

local MENU_CHOICES = { fight = true, party = true, item = true, run = true }

local function validSlot(slot)
  return type(slot) == "number" and slot % 1 == 0 and slot >= 1
end

function BattleAPI:submit(intent)
  if type(intent) ~= "table" then return nil, "intent must be a table" end
  if type(intent.id) ~= "number" or intent.id % 1 ~= 0 or intent.id < 1 then
    return nil, "intent id must be a positive integer"
  end
  if self.lastIntentId and intent.id <= self.lastIntentId then
    return nil, "replayed intent"
  end

  local screen, top = activeBattle(self.game)
  if not screen or not screen.battle then return nil, "no battle" end
  if intent.revision ~= self:_revision(screen, top) then
    return nil, "stale battle context"
  end
  if screen.tutorial then return nil, "battle kind is not controllable" end
  if top ~= screen then return nil, "battle menu is covered" end

  local battle = screen.battle
  local ok, err
  if intent.kind == "menu" then
    if screen.phase ~= "menu" then return nil, "battle menu is not active" end
    if not MENU_CHOICES[intent.choice] then
      return nil, "unknown battle menu choice"
    end
    ok, err = screen:chooseMenu(intent.choice)
  elseif intent.kind == "move" then
    if screen.phase ~= "moves" then return nil, "move menu is not active" end
    if screen.moveSwapIndex then return nil, "move reorder is active" end
    local move = validSlot(intent.slot) and battle.player
      and battle.player.moves and battle.player.moves[intent.slot]
    if not move then return nil, "invalid move slot" end
    if (move.pp or 0) <= 0 then return nil, "move has no PP" end
    if battle:moveDisabled(battle.player, move.id) then
      return nil, "move is disabled"
    end
    ok, err = screen:chooseMove(intent.slot)
  elseif intent.kind == "back" then
    ok, err = screen:cancelMove()
  else
    return nil, "unknown battle intent"
  end
  if not ok then return nil, err end
  self.lastIntentId = intent.id
  self.signature = nil
  return true
end

return BattleAPI
