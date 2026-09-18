-- Effect helpers (owned; no src.core.Strings / no KR).

local H = {}

function H.displayName(ctx, battler)
  return ctx.adapter:displayName(battler)
end

function H.sayFail(ctx)
  local M = H.move(ctx)
  if M then M.failed = true end
  ctx.adapter:sayFail()
end

function H.ownSide(ctx)
  return ctx.adapter:ownSide(ctx.user)
end

function H.foeSide(ctx)
  return ctx.adapter:foeSide(ctx.user)
end

function H.move(ctx)
  local o = ctx and ctx.opts
  if type(o) == "table" and o.isMoveContext then return o end
  return nil
end

function H.attackAnim(ctx)
  local M = H.move(ctx)
  if M and M.attackAnimation then M:attackAnimation() end
end

function H.accuracy(ctx, mode)
  local M = H.move(ctx)
  if not M or not M.accuracyCheck then return true end
  return M:accuracyCheck(mode or "normal", true)
end

function H.findHazard(adapter, side, id)
  if adapter.findHazard then return adapter:findHazard(side, id) end
  if not side or not side.hazards then return nil end
  for _, h in ipairs(side.hazards) do
    if h.id == id then return h end
  end
  return nil
end

function H.hasType(ctx, battler, typeId)
  if not battler then return false end
  local Types = require("src.core.game3.battle.types")
  local id = typeId
  if type(typeId) == "string" then id = Types.ID[typeId:upper()] end
  local t1, t2 = battler.type1, battler.type2
  if battler.expTransform then
    t1 = battler.expTransform.type1 or t1
    t2 = battler.expTransform.type2 or t2
  end
  return t1 == id or t2 == id
end

function H.lastMove(ctx, battler)
  if not battler then return nil end
  if ctx.adapter.lastMoveOf then
    return ctx.adapter:lastMoveOf(battler)
  end
  return battler.lastMoveId or battler.lastMove
end

function H.preparedMoves(ctx, battler)
  local mon = ctx.adapter:mon(battler)
  if not mon then return {} end
  local out = {}
  for i = 1, 4 do
    local id = mon.moves and mon.moves[i]
    if id then
      out[#out + 1] = { id = id, pp = mon.pp and mon.pp[i] or 0, slot = i }
    end
  end
  return out
end

function H.moveNum(ref)
  if ref == nil then return nil end
  if type(ref) == "table" then ref = ref.numId or ref.id or ref.move end
  local n = tonumber(ref)
  if n then return n end
  local Moves = require("src.core.game3.battle.moves")
  local m = Moves.get(ref)
  return tonumber(m and m.numId) or Moves.numForName(ref)
end

function H.slotOf(battler, moveRef)
  local mon = battler and battler.mon
  local want = H.moveNum(moveRef)
  if not mon or not mon.moves or not want then return nil end
  for i = 1, 4 do
    if H.moveNum(mon.moves[i]) == want then return i end
  end
  return nil
end

return H
