-- Build in-memory battle party from opaque session party + move_overlay.
-- Preserves Gen3 move ids (no host downgrade). Tracks overlay slots for PP writeback.

local PartyView = {}

local function shallow(mon)
  local copy = {}
  for k, v in pairs(mon) do
    if type(v) == "table" then
      local inner = {}
      for ik, iv in pairs(v) do inner[ik] = iv end
      copy[k] = inner
    else
      copy[k] = v
    end
  end
  return copy
end

--- Returns battleParty, remap[{partySlot,moveSlot,frlgMoveId}]
function PartyView.fromSession(sessionParty, moveOverlay)
  local battleParty = {}
  local remap = {}
  if type(sessionParty) ~= "table" then return battleParty, remap end
  for pi, mon in ipairs(sessionParty) do
    local copy = shallow(mon)
    copy.moves = {}
    copy.pp = {}
    local overlaySlot = moveOverlay and moveOverlay[pi]
    for mi = 1, 4 do
      local ov = overlaySlot and overlaySlot[mi]
      if ov and ov.frlgMoveId then
        copy.moves[mi] = ov.frlgMoveId
        copy.pp[mi] = ov.pp or (mon.pp and mon.pp[mi]) or 5
        remap[#remap + 1] = {
          partySlot = pi,
          moveSlot = mi,
          frlgMoveId = ov.frlgMoveId,
          hostFallbackId = ov.frlgMoveId, -- identity; writeback keeps Gen3 id
        }
      else
        local rawM = mon.moves and mon.moves[mi]
        if type(rawM) == "table" then
          copy.moves[mi] = rawM.id or rawM.move or rawM.num or rawM.moveId or rawM.name or rawM[1]
          copy.pp[mi] = rawM.pp or (mon.pp and mon.pp[mi])
        else
          copy.moves[mi] = rawM
          copy.pp[mi] = mon.pp and mon.pp[mi]
        end
      end
    end
    battleParty[pi] = copy
  end
  return battleParty, remap
end

--- The party an item UI must read while it is open.
---
--- The battle runs on the copy built by fromSession, and battle_bridge only
--- writes it back into session.party when the battle ends.  Anything that
--- opens mid-battle and shows HP (the bag's party-select screen, the Berry
--- Pouch) has to read the copy or it shows pre-battle HP and refuses heals
--- that would in fact work.
function PartyView.live(session)
  local Battle = package.loaded["src.core.game3.battle"]
  local st = Battle and Battle._st
  if not (st and st.playerParty) then
    return (session and session.party) or {}
  end
  local State = require("src.core.game3.battle.state")
  -- Flush the active battlers' HP/status first, exactly as the switch path
  -- does (battle/ui.lua open_battle_party).  battlers[2] is the second player
  -- battler in doubles and nil in singles, so this is safe either way.
  for _, id in ipairs({ 0, 2 }) do
    local b = State.battler(st, id)
    if b and b.side == "player" then
      State.syncBattlerToParty(b, st.playerParty)
    end
  end
  return st.playerParty
end

function PartyView.firstAliveIndex(party)
  if type(party) ~= "table" then return nil end
  for i, mon in ipairs(party) do
    if mon and (tonumber(mon.hp) or 0) > 0 then return i end
  end
  return nil
end

-- pokefirered/src/battle_setup.c:542
function PartyView.doubleTransitionLevels(playerParty, foeParty)
  local pSum, need = 0, 2
  for _, mon in ipairs(playerParty or {}) do
    local sp = tonumber(mon.species or mon.speciesId) or 0
    if sp ~= 0 and sp ~= 412 and not mon.isEgg and (tonumber(mon.hp) or 0) ~= 0 then
      pSum = (pSum + (tonumber(mon.level or mon.lvl) or 0)) % 256
      need = need - 1
      if need == 0 then break end
    end
  end
  -- pokefirered/src/battle_setup.c:561
  local eSum = 0
  for i = 1, math.min(2, #(foeParty or {})) do
    eSum = (eSum + (tonumber(foeParty[i].level or foeParty[i].lvl) or 0)) % 256
  end
  return pSum, eSum
end

return PartyView
