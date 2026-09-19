-- Opaque host-shaped session party (H6). No DV↔IV / Stat Exp↔EV math.
-- Gen3-only moves live in move_overlay; host mon tables stay host-shaped.

local Party = {}

local function shallow_mon(mon)
  if type(mon) ~= "table" then return mon end
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

--- Snapshot host party by shallow-copying each mon table (opaque blob).
function Party.takeOpaque(hostParty)
  local out = {}
  if type(hostParty) ~= "table" then return out end
  for i, mon in ipairs(hostParty) do
    out[i] = shallow_mon(mon)
  end
  return out
end

--- Write opaque session party back onto host party slots (structure-preserving).
function Party.writeBack(hostParty, sessionParty)
  if type(hostParty) ~= "table" or type(sessionParty) ~= "table" then return end
  for i = #hostParty, 1, -1 do
    hostParty[i] = nil
  end
  for i, mon in ipairs(sessionParty) do
    hostParty[i] = shallow_mon(mon)
  end
end

--- Field-wise battle writeback onto an opaque mon (HP/status/exp/level/PP/moves).
--- Never touches dvs / ivs / evs / statexp.
function Party.applyBattleFields(opaqueMon, fields)
  if type(opaqueMon) ~= "table" or type(fields) ~= "table" then return end
  for _, key in ipairs({
    "hp", "maxHp", "status", "sleep", "level", "exp",
    "happiness", "item", "heldItem",
    "species", "speciesId", "name", "growthRate",
    "attack", "defense", "speed", "spAtk", "spDef",
    "atk", "def", "spe", "spa", "spd",
  }) do
    if fields[key] ~= nil then opaqueMon[key] = fields[key] end
  end
  if type(fields.pp) == "table" then
    opaqueMon.pp = opaqueMon.pp or {}
    for i, v in pairs(fields.pp) do
      opaqueMon.pp[i] = v
    end
  end
  if type(fields.maxPp) == "table" then
    opaqueMon.maxPp = opaqueMon.maxPp or {}
    for i, v in pairs(fields.maxPp) do
      opaqueMon.maxPp[i] = v
    end
  end
  if type(fields.moves) == "table" and fields._allowMoveRewrite then
    opaqueMon.moves = {}
    for i, v in pairs(fields.moves) do
      opaqueMon.moves[i] = v
    end
  end
end

--- Ensure sidecar move_overlay table exists.
function Party.ensureOverlay(sidecar)
  sidecar = sidecar or {}
  sidecar.move_overlay = sidecar.move_overlay or {}
  return sidecar.move_overlay
end

--- Set quarantined Gen3 move for partySlot/moveSlot (1-based).
function Party.setOverlayMove(sidecar, partySlot, moveSlot, frlgMoveId, pp)
  local overlay = Party.ensureOverlay(sidecar)
  overlay[partySlot] = overlay[partySlot] or {}
  overlay[partySlot][moveSlot] = {
    frlgMoveId = frlgMoveId,
    pp = tonumber(pp) or 0,
  }
end

function Party.getOverlayMove(sidecar, partySlot, moveSlot)
  local overlay = sidecar and sidecar.move_overlay
  local slot = overlay and overlay[partySlot]
  return slot and slot[moveSlot]
end

--- Heal all opaque mons (nurse).
function Party.healAll(sessionParty)
  if type(sessionParty) ~= "table" then return end
  local Pokemon = require("src.core.game3.pokemon")
  for _, mon in ipairs(sessionParty) do
    if type(mon) == "table" then
      if mon.maxHp then mon.hp = mon.maxHp end
      mon.status = nil
      mon.sleep = nil
      if type(mon.pp) == "table" and type(mon.moves) == "table" then
        for i = 1, 4 do
          if mon.moves[i] then
            local max = mon.maxPp and mon.maxPp[i]
            if not max then
              local row = Pokemon.battleMove and Pokemon.battleMove(mon.moves[i])
              max = (row and row.pp) or 5
            end
            mon.pp[i] = max
            mon.maxPp = mon.maxPp or {}
            mon.maxPp[i] = max
          end
        end
      end
    end
  end
end

function Party.size(sessionParty)
  if type(sessionParty) ~= "table" then return 0 end
  return #sessionParty
end

Party.PLAYER_HAS_TWO_USABLE_MONS = 0
Party.PLAYER_HAS_ONE_MON = 1
Party.PLAYER_HAS_ONE_USABLE_MON = 2

-- pokefirered/src/pokemon.c:3769
function Party.monsStateToDoubles(sessionParty)
  if type(sessionParty) ~= "table" then return Party.PLAYER_HAS_ONE_MON end
  local count = 0
  for _, mon in ipairs(sessionParty) do
    if (tonumber(mon.species or mon.speciesId) or 0) ~= 0 then count = count + 1 end
  end
  if count <= 1 then return Party.PLAYER_HAS_ONE_MON end
  local usable = 0
  for _, mon in ipairs(sessionParty) do
    local sp = tonumber(mon.species or mon.speciesId) or 0
    if (tonumber(mon.hp) or 0) ~= 0 and sp ~= 0 and sp ~= 412 and not mon.isEgg and not mon.egg then
      usable = usable + 1
    end
  end
  return (usable > 1) and Party.PLAYER_HAS_TWO_USABLE_MONS or Party.PLAYER_HAS_ONE_USABLE_MON
end

--- Append a Gen3-shaped opaque mon for script givemon (starter / gifts).
-- Returns true if added to party (slot available).
function Party.giveMon(session, species, level, nickname)
  if type(session) ~= "table" then return false end
  session.party = session.party or {}
  if #session.party >= 6 then return false end
  species = tonumber(species) or 1
  level = tonumber(level) or 5
  if level < 1 then level = 1 end
  local Pokemon = require("src.core.game3.pokemon")
  if not Pokemon._names then pcall(Pokemon.install, nil) end

  local Rng = require("src.core.game3.rng")
  local personality = Rng.Random32()
  local iv1 = Rng.Random()
  local iv2 = Rng.Random()
  local ivs = {
    hp  = iv1 % 32,
    atk = math.floor(iv1 / 32) % 32,
    def = math.floor(iv1 / 1024) % 32,
    spe = iv2 % 32,
    spa = math.floor(iv2 / 32) % 32,
    spd = math.floor(iv2 / 1024) % 32,
  }

  local meta = Pokemon.speciesMeta and Pokemon.speciesMeta(species)
  local friendship = (meta and meta.friendship) or 70
  local growthRate = (meta and tonumber(meta.growthRate)) or 0
  local ability = Pokemon.abilityId and Pokemon.abilityId(species, personality) or 0
  local gender = Pokemon.gender and Pokemon.gender(species, personality) or "U"
  local name = (Pokemon.name and Pokemon.name(species)) or "POKéMON"
  local moves, pp, maxPp = {}, {}, {}
  if Pokemon.movesAtLevel then
    moves, pp, maxPp = Pokemon.movesAtLevel(species, level)
  end
  if not moves or #moves == 0 then
    moves = { 33 }
    pp = { 35 }
    maxPp = { 35 }
  end

  local SummaryData = require("src.core.game3.summary_data")
  local mon = {
    species = species,
    speciesId = species,
    name = name,
    nickname = type(nickname) == "string" and nickname or "",
    level = level,
    metLevel = level,
    growthRate = growthRate,
    exp = SummaryData.expForLevel(growthRate, level),
    status = nil,
    moves = moves,
    pp = pp,
    maxPp = maxPp,
    personality = personality,
    nature = Pokemon.natureId and Pokemon.natureId(personality) or 0,
    ivs = ivs,
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    ability = ability,
    abilityId = ability,
    gender = gender,
    happiness = friendship,
    friendship = friendship,
    ot = session.name or session.playerName or "RED",
    otName = session.name or session.playerName or "RED",
    otId = session.trainerId or session.id or session.playerId or 12345,
    pokeball = 4, -- Poké Ball
  }
  Pokemon.applyStats(mon)

  session.party[#session.party + 1] = mon
  session.dex = session.dex or { seen = {}, owned = {} }
  session.dex.seen = session.dex.seen or {}
  session.dex.owned = session.dex.owned or {}
  session.dex.seen[species] = true
  session.dex.owned[species] = true
  return true
end

--- Give an egg for script giveegg.
function Party.giveEgg(session, species)
  if not session or not session.party then return false end
  if #session.party >= 6 then return false end
  species = tonumber(species) or 1
  local Pokemon = require("src.core.game3.pokemon")
  local ok = Party.giveMon(session, species, 5, "EGG")
  if ok then
    local egg = session.party[#session.party]
    if egg then
      egg.isEgg = true
      egg.name = "EGG"
      egg.nickname = "EGG"
    end
  end
  return ok
end

--- Prove DVs/Stat Exp bit-identical between two opaque snapshots.
function Party.dvsIdentical(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do
    local ma, mb = a[i], b[i]
    if type(ma) ~= "table" or type(mb) ~= "table" then return false end
    local da, db = ma.dvs or ma.DVs or ma.dv, mb.dvs or mb.DVs or mb.dv
    if type(da) == "table" and type(db) == "table" then
      for k, v in pairs(da) do
        if db[k] ~= v then return false end
      end
      for k, v in pairs(db) do
        if da[k] ~= v then return false end
      end
    elseif da ~= db then
      return false
    end
    local sa = ma.statExp or ma.statexp or ma.StatExp
    local sb = mb.statExp or mb.statexp or mb.StatExp
    if type(sa) == "table" and type(sb) == "table" then
      for k, v in pairs(sa) do
        if sb[k] ~= v then return false end
      end
    elseif sa ~= sb then
      return false
    end
  end
  return true
end

return Party
