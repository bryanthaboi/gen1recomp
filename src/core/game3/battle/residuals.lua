-- End-of-turn residual scheduler (owned game3).

local Rules = require("src.core.game3.battle.rules")
local EffectCtx = require("src.core.game3.battle.effect_ctx")
local Strings = require("src.core.Strings")

local Residuals = {}

local handlers = {}

function Residuals.register(phase, fn)
  handlers[phase] = handlers[phase] or {}
  handlers[phase][#handlers[phase] + 1] = fn
end

function Residuals.clear()
  handlers = {}
end

local function battlerSpeed(battler, adapter)
  if not battler then return 0 end
  local Engine = package.loaded["src.core.game3.battle.engine"]
  if Engine and Engine.speedOf then
    return Engine.speedOf(battler, adapter and adapter._st, adapter)
  end
  local mon = battler.mon
  return tonumber(mon and (mon.speed or mon.spe)) or 50
end

-- pokefirered/src/battle_util.c:494
local function sortedBattlers(adapter)
  local st = adapter and adapter._st
  if st and st.double then
    local State = require("src.core.game3.battle.state")
    local ids = st._endTurnOrder
    if not ids then
      local pri
      if st.turnActions then
        local Moves = require("src.core.game3.battle.moves")
        pri = {}
        for _, act in ipairs(st.turnActions) do
          if act.battler ~= nil and act.kind == "move" then pri[act.battler] = Moves.priority(act.move) end
        end
      end
      ids = State.speedOrder(st, adapter, { priority = pri })
    end
    local out = {}
    for _, id in ipairs(ids) do
      if State.isPresent(st, id) then out[#out + 1] = State.battler(st, id) end
    end
    return out
  end
  local list = adapter:activeBattlers() or {}
  local a, b = list[1], list[2]
  if a and b then
    local sa, sb = battlerSpeed(a, adapter), battlerSpeed(b, adapter)
    if sb > sa or (sb == sa and adapter:roll(0, 1) == 1) then
      list[1], list[2] = b, a
    end
  end
  return list
end
Residuals.sortedBattlers = sortedBattlers

local function runStepAndRecord(adapter, battler, phase, fn, events)
  if battler and adapter:isFainted(battler) then return false end
  if adapter:isBattleDecided() then return false end

  local active = adapter:activeBattlers() or {}
  local hpBefore = {}
  for _, b in ipairs(active) do
    if b and b.side then
      hpBefore[b] = adapter:hp(b)
    end
  end

  local capturedMsgs = {}
  local prevSay = adapter._say
  adapter._say = function(text)
    capturedMsgs[#capturedMsgs + 1] = tostring(text or "")
  end
  local mark = adapter.eventMark and adapter:eventMark() or 0

  local opts = EffectCtx.borrowOpts(phase)
  local ctx = EffectCtx.push(adapter, nil, battler, nil, nil, adapter:rng(), opts)
  local ok, err = pcall(fn, ctx)
  EffectCtx.pop()

  local hpChanges = {}
  local faints = {}
  for _, b in ipairs(active) do
    if b and b.side then
      local before = hpBefore[b] or 0
      local after = adapter:hp(b)
      if before ~= after then
        hpChanges[#hpChanges + 1] = {
          side = b.side,
          battler = b.id,
          from = before,
          to = after,
          maxHp = adapter:maxHp(b),
        }
      end
      if adapter:isFainted(b) and before > 0 then
        faints[#faints + 1] = { side = b.side, battler = b.id }
        if not b._faintAnnounced then
          b._faintAnnounced = true
          if adapter.pushEvent then adapter:pushEvent({ kind = "faint", side = b.side, battler = b.id }) end
          adapter:say(Strings("%s fainted!", adapter:displayName(b)))
        end
        adapter:emitFaint(b)
      end
    end
  end

  adapter._say = prevSay
  if not ok then error(err, 0) end

  if #capturedMsgs > 0 or #hpChanges > 0 or #faints > 0 then
    events[#events + 1] = {
      phase = phase,
      target = battler,
      msgs = capturedMsgs,
      hpChanges = hpChanges,
      faints = faints,
      events = adapter.eventsSince and adapter:eventsSince(mark) or {},
    }
  end

  if battler and adapter:isFainted(battler) then
    if Rules.shouldHaltBattlerOnFaint(phase) then
      return true
    end
  end
  return false
end

local function run_phase(adapter, phase, battler, events)
  local list = handlers[phase]
  if not list then return false end
  for _, fn in ipairs(list) do
    if adapter:isBattleDecided() then return true end
    if runStepAndRecord(adapter, battler, phase, fn, events) then return true end
  end
  return false
end

function Residuals.collectEvents(adapter)
  local events = {}
  if not adapter or adapter:isBattleDecided() then return events end

  local Engine = package.loaded["src.core.game3.battle.engine"]
  if Engine and Engine.refreshLinks then Engine.refreshLinks(adapter._st) end
  -- pokefirered/src/battle_main.c:2957
  for _, b in ipairs(adapter:activeBattlers()) do
    b.expProtected = nil
    b.expEnduring = nil
  end

  local st = adapter._st
  if st and st.double then
    st._endTurnOrder = nil
    -- pokefirered/src/battle_util.c:484
    local order = {}
    for _, b in ipairs(sortedBattlers(adapter)) do order[#order + 1] = b.id end
    st._endTurnOrder = order
    st.turnOrder = order
  end

  for _, phase in ipairs(Rules.FIELD_PHASES_ORDER) do
    if adapter:isBattleDecided() then break end
    run_phase(adapter, phase, nil, events)
  end

  if not adapter:isBattleDecided() then
    for _, battler in ipairs(sortedBattlers(adapter)) do
      for _, phase in ipairs(Rules.BATTLER_PHASES_ORDER) do
        if adapter:isBattleDecided() or adapter:isFainted(battler) then break end
        if run_phase(adapter, phase, battler, events) then break end
      end
    end
  end

  for _, phase in ipairs(Rules.POST_PHASES_ORDER) do
    if adapter:isBattleDecided() then break end
    run_phase(adapter, phase, nil, events)
  end

  if st then st._endTurnOrder = nil end
  return events
end

function Residuals.runTurn(adapter)
  return Residuals.collectEvents(adapter)
end

return Residuals
