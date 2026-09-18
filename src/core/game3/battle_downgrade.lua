-- Gen3 → Gen2 battle view downgrade (H4) + player move remap table (H4∩H6).

local Downgrade = {}

-- Unsupported FRLG moves → Gen2 fallback (or STRUGGLE).
Downgrade.MOVE_FALLBACK = {
  -- Common Gen3-only examples; extend as extract surfaces them.
  [291] = "DIVE",          -- if missing on host → Struggle below
  [338] = "FRENZY_PLANT",
  [339] = "BULK_UP",
  [340] = "BOUNCE",
  [341] = "MUD_SHOT",
  [342] = "POISON_TAIL",
  [344] = "VOLT_TACKLE",
  [345] = "MAGICAL_LEAF",
  [347] = "CALM_MIND",
  [348] = "LEAF_BLADE",
  [349] = "DRAGON_DANCE",
  [350] = "ROCK_BLAST",
  [351] = "SHOCK_WAVE",
  [352] = "WATER_PULSE",
  [353] = "DOOM_DESIRE",
  [354] = "PSYCHO_BOOST",
}

Downgrade.DEFAULT_MOVE = "STRUGGLE"

-- Species FRLG national → host id when names differ; nil = use same number/name.
Downgrade.SPECIES_MAP = {
  -- Fill as needed; missing → log + skip encounter at bridge.
}

function Downgrade.moveToHost(moveId, hostMoves)
  if moveId == nil or moveId == 0 then return nil end
  if type(moveId) == "string" then
    if hostMoves and hostMoves[moveId] then return moveId end
    local fb = Downgrade.MOVE_FALLBACK[moveId]
    if fb then return fb end
    -- Named Gen2-legal moves pass through; only explicit fallbacks remap.
    return moveId
  end
  local num = tonumber(moveId)
  if not num then return Downgrade.DEFAULT_MOVE end
  -- If numeric and host uses string names, map via fallback table.
  if Downgrade.MOVE_FALLBACK[num] then
    return Downgrade.MOVE_FALLBACK[num]
  end
  -- Assume host accepts same numeric id within Gen2 range.
  if num >= 1 and num <= 251 then
    return num
  end
  return Downgrade.DEFAULT_MOVE
end

function Downgrade.stripAbility(_ability)
  return nil -- NO_ABILITY for host
end

function Downgrade.speciesToHost(species)
  local mapped = Downgrade.SPECIES_MAP[species]
  if mapped ~= nil then return mapped end
  local n = tonumber(species)
  if n and n >= 1 and n <= 251 then return n end
  if type(species) == "string" then return species end
  return nil -- caller should skip
end

--- Build foe payload safe for host BattleState.
function Downgrade.foePayload(foe)
  if type(foe) ~= "table" then return nil end
  local species = Downgrade.speciesToHost(foe.species or foe.id)
  if not species then return nil end
  local moves = {}
  local srcMoves = foe.moves or {}
  for i = 1, 4 do
    local m = srcMoves[i]
    if m then
      moves[i] = Downgrade.moveToHost(m)
    end
  end
  return {
    species = species,
    level = foe.level or 5,
    moves = moves,
    item = foe.item,
    ability = Downgrade.stripAbility(foe.ability),
    dvs = foe.dvs, -- wilds may still carry host-shaped stats
    gender = foe.gender,
  }
end

--- Build temporary player battle view + remap table for Gen3-only moves.
--- Returns battleParty (host-legal move ids), remap[{partySlot,moveSlot,frlgMoveId,hostFallbackId}].
function Downgrade.playerBattleView(sessionParty, moveOverlay, hostMoveSet)
  local battleParty = {}
  local remap = {}
  if type(sessionParty) ~= "table" then
    return battleParty, remap
  end
  for pi, mon in ipairs(sessionParty) do
    local copy = {}
    for k, v in pairs(mon) do
      if k ~= "moves" and k ~= "pp" then copy[k] = v end
    end
    copy.moves = {}
    copy.pp = {}
    local overlaySlot = moveOverlay and moveOverlay[pi]
    for mi = 1, 4 do
      local ov = overlaySlot and overlaySlot[mi]
      local moveId = mon.moves and mon.moves[mi]
      local pp = mon.pp and mon.pp[mi]
      if ov and ov.frlgMoveId then
        local fallback = Downgrade.moveToHost(ov.frlgMoveId, hostMoveSet)
        copy.moves[mi] = fallback
        copy.pp[mi] = ov.pp or pp or 5
        remap[#remap + 1] = {
          partySlot = pi,
          moveSlot = mi,
          frlgMoveId = ov.frlgMoveId,
          hostFallbackId = fallback,
        }
      else
        local hostMove = Downgrade.moveToHost(moveId, hostMoveSet)
        -- If remapped away from original string/number, track as overlay-less remap
        if moveId and hostMove and hostMove ~= moveId and type(moveId) ~= "number" then
          -- Gen3 string id on opaque mon without overlay entry
          remap[#remap + 1] = {
            partySlot = pi,
            moveSlot = mi,
            frlgMoveId = moveId,
            hostFallbackId = hostMove,
          }
          copy.moves[mi] = hostMove
        else
          copy.moves[mi] = hostMove or moveId
        end
        copy.pp[mi] = pp
      end
    end
    battleParty[pi] = copy
  end
  return battleParty, remap
end

--- After battle: map fallback PP back onto overlay / opaque mon. Never write fallback id into move slot.
function Downgrade.writebackPlayerPp(sessionParty, moveOverlay, remap, battleParty)
  if type(remap) ~= "table" then return end
  moveOverlay = moveOverlay or {}
  for _, row in ipairs(remap) do
    local pi, mi = row.partySlot, row.moveSlot
    local battleMon = battleParty and battleParty[pi]
    local newPp = battleMon and battleMon.pp and battleMon.pp[mi]
    if newPp ~= nil then
      moveOverlay[pi] = moveOverlay[pi] or {}
      local ov = moveOverlay[pi][mi] or { frlgMoveId = row.frlgMoveId }
      ov.frlgMoveId = row.frlgMoveId -- never fallback
      ov.pp = newPp
      moveOverlay[pi][mi] = ov
      -- Also keep opaque mon PP in sync if slot still holds a host-legal move id;
      -- do not replace moves[mi] with hostFallbackId.
      local mon = sessionParty and sessionParty[pi]
      if mon then
        mon.pp = mon.pp or {}
        mon.pp[mi] = newPp
        -- If mon.moves[mi] was already the Gen3 id, leave it; if host id, leave it.
        if mon.moves and mon.moves[mi] == row.hostFallbackId then
          mon.moves[mi] = row.frlgMoveId
        end
      end
    end
  end
  return moveOverlay
end

return Downgrade
