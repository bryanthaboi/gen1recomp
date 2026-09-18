-- Status inflict + EOT chip (owned; KR left this to host engines).

local Status = {}

local function status_of(battler)
  local s = battler and (battler.status or (battler.mon and battler.mon.status))
  if s == 0 then return nil end
  return s
end

function Status.set(battler, status)
  if not battler then return end
  battler.status = status
  if battler.mon then battler.mon.status = status end
end

function Status.clear(battler)
  Status.set(battler, nil)
end

--- End-of-turn burn / poison / toxic chip. Returns list of message strings.
-- pokefirered/src/battle_util.c:805
function Status.tickChip(battler, adapter)
  local msgs = {}
  if not battler or adapter:isFainted(battler) then return msgs end
  local st = status_of(battler)
  if not st then return msgs end
  st = tostring(st):upper()
  local maxHp = adapter:maxHp(battler)
  local name = adapter:displayName(battler)
  local loss
  local text, anim
  if st == "PSN" or st == "POISON" then
    loss = math.floor(maxHp / 8)
    text, anim = name .. " is hurt\nby poison!", "POISON"
  elseif st == "TOX" or st == "TOXIC" then
    -- pokefirered/src/battle_util.c:823
    loss = math.floor(maxHp / 16)
    if loss == 0 then loss = 1 end
    local c = (battler.toxicCounter or 0)
    if c < 15 then c = c + 1 end
    battler.toxicCounter = c
    loss = loss * c
    text, anim = name .. " is hurt\nby poison!", "POISON"
  elseif st == "BRN" or st == "BURN" then
    loss = math.floor(maxHp / 8)
    text, anim = name .. " is hurt\nby its burn!", "BURN"
  else
    return msgs
  end
  if loss == 0 then loss = 1 end
  adapter:say(text)
  msgs[#msgs + 1] = text
  if adapter.playAnim then adapter:playAnim("status", anim, battler, battler) end
  adapter:applyHpLoss(battler, loss)
  return msgs
end

--- Simple status-move stage changes for MVP. Returns message or nil.
function Status.applySetupMove(user, target, moveId, adapter)
  local Moves = require("src.core.game3.battle.moves")
  local id = Moves.normalizeId(moveId)
  if id == "GROWL" then
    adapter:changeStages(target, { attack = -1 })
    return adapter:displayName(target) .. "'s ATTACK\nfell!"
  elseif id == "TAIL_WHIP" or id == "LEER" then
    adapter:changeStages(target, { defense = -1 })
    return adapter:displayName(target) .. "'s DEFENSE\nfell!"
  elseif id == "HARDEN" then
    adapter:changeStages(user, { defense = 1 })
    return adapter:displayName(user) .. "'s DEFENSE\nrose!"
  end
  return nil
end

return Status
