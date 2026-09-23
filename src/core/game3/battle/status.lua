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
  local loss
  local id, anim
  if st == "PSN" or st == "POISON" then
    loss = math.floor(maxHp / 8)
    id, anim = "STRINGID_PKMNHURTBYPOISON", "POISON"
  elseif st == "TOX" or st == "TOXIC" then
    -- pokefirered/src/battle_util.c:823
    loss = math.floor(maxHp / 16)
    if loss == 0 then loss = 1 end
    local c = (battler.toxicCounter or 0)
    if c < 15 then c = c + 1 end
    battler.toxicCounter = c
    loss = loss * c
    id, anim = "STRINGID_PKMNHURTBYPOISON", "POISON"
  elseif st == "BRN" or st == "BURN" then
    loss = math.floor(maxHp / 8)
    id, anim = "STRINGID_PKMNHURTBYBURN", "BURN"
  else
    return msgs
  end
  if loss == 0 then loss = 1 end
  -- data/battle_scripts_1.s:3676
  msgs[#msgs + 1] = adapter:sayText(id, { atk = battler })
  if adapter.playAnim then adapter:playAnim("status", anim, battler, battler) end
  adapter:applyHpLoss(battler, loss)
  return msgs
end

return Status
