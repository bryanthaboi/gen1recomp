-- Link protocol helpers: Pokémon serialization and the trade session
-- state machine (pure logic, headless-testable).
--
-- Message types exchanged after pairing:
--   {type="hello", ...}                 handshake v2 (src/link/Handshake.lua)
--   {type="records", pokemon=, moves=}  subset trade: per-record hashes
--   {type="party", mons=[...]}          party (both directions)
--   {type="pick", index}                trade: chosen slot in the sent list
--   {type="confirm", ok=bool}           trade: final yes/no
--   {type="action", ...}                battle: guest -> host choice
--   {type="event", ...}                 battle: host -> guest display event
--   {type="bye"}

local Fingerprint = require("src.link.Fingerprint")
local Handshake = require("src.link.Handshake")
local Runtime = require("src.mods.Runtime")

local Protocol = {}

local MAX_WIRE_NAME = 40

local function num(v, default)
  local n = tonumber(v)
  if n == nil or n ~= n or n == math.huge or n == -math.huge then
    return default
  end
  return n
end

local function tbl(v)
  return type(v) == "table" and v or {}
end

local function text(v)
  if type(v) ~= "string" then return nil end
  return v:sub(1, MAX_WIRE_NAME)
end

Protocol.hello = Handshake.hello
Protocol.checkCompat = Handshake.checkCompat

-- the extra bag is JSON-safe by contract, the same restriction the save
-- serializer enforces; anything else is dropped rather than trusted
local function plainCopy(value, depth)
  if type(value) ~= "table" then return nil end
  if (depth or 0) > 8 then return nil end
  local out = {}
  for k, v in pairs(value) do
    local kt, vt = type(k), type(v)
    if kt == "string" or kt == "number" then
      if vt == "string" or vt == "number" or vt == "boolean" then
        out[k] = v
      elseif vt == "table" then
        out[k] = plainCopy(v, (depth or 0) + 1)
      end
    end
  end
  return out
end

Protocol.plainCopy = plainCopy

-- serialize a mon instance for the wire (plain data only).  ppUps rides
-- along because the real cable transmitted it and its absence silently
-- capped a PP-Upped move at base PP on the receiving side.  ot/otId ride
-- along too: pokered's trade sends the whole party block including each
-- mon's OT ID (party_struct MON_OTID) and the OT-names block (wPartyMonOT),
-- and the receiver keeps them verbatim -- a differing OT/ID is what marks a
-- mon as traded (boosted EXP, high-level disobedience).  Omitting them made
-- a received mon show the receiver as its OT (#215).
function Protocol.packMon(mon)
  local moves = {}
  for _, mv in ipairs(mon.moves) do
    table.insert(moves, { id = mv.id, pp = mv.pp, ppUps = mv.ppUps })
  end
  return {
    species = mon.species,
    level = mon.level,
    exp = mon.exp,
    hp = mon.hp,
    status = mon.status,
    nickname = mon.nickname,
    dvs = mon.dvs,
    statExp = mon.statExp,
    moves = moves,
    ot = mon.ot,
    otId = mon.otId,
    extra = plainCopy(mon.extra),
  }
end

-- rebuild a mon locally (recomputes stats from real species data so a
-- tampered packet can't invent stats).  opts.strict is set once two v2
-- peers have agreed on a verdict: a mon that cannot be rebuilt identically
-- is rejected by name instead of quietly mutated into something else.
function Protocol.unpackMon(data, packed, opts)
  local Stats = require("src.pokemon.Stats")
  local Growth = require("src.pokemon.Growth")
  local strict = opts and opts.strict
  if type(packed) ~= "table" then
    if strict then return nil, "unknown POKéMON" end
    return nil
  end
  -- forceLevel comes from an "auto-level" ruling.  The picker's ANY choice
  -- ("use each mon's real level", Gen1's only mode) is a string sentinel on
  -- the LinkState/Tournament side (see levelForWire) that must mean "no
  -- forced level" here.  Coerce once so a non-numeric level string -- the ANY
  -- sentinel, an old peer, or a mod (#204) -- can never reach math.floor
  -- below: tonumber("ANY") == nil, i.e. keep the packed real level, while
  -- tonumber(50)/tonumber("50") both give 50.
  local forceLevel = opts and tonumber(opts.forceLevel) or nil
  local def = data.pokemon[packed.species]
  if not def then
    if strict then return nil, "unknown POKéMON" end
    return nil
  end
  local level = math.max(2, math.min(100, math.floor(num(packed.level, 5))))
  -- "auto-level" tournaments/matches: every participant's real level is
  -- ignored and everyone rebuilds at the same fixed level instead, so a
  -- Lv12 and a Lv100 party can battle on equal footing. Both sides pass
  -- the identical forceLevel for a given match, so this stays symmetric.
  if forceLevel then
    level = math.max(2, math.min(100, math.floor(forceLevel)))
  end
  local packedDvs, packedStatExp = tbl(packed.dvs), tbl(packed.statExp)
  local dvs = {}
  for _, k in ipairs({ "hp", "attack", "defense", "speed", "special" }) do
    dvs[k] = math.max(0, math.min(15, math.floor(num(packedDvs[k], 0))))
  end
  local statExp = {}
  for _, k in ipairs({ "hp", "attack", "defense", "speed", "special" }) do
    statExp[k] = math.max(0, math.min(65535, math.floor(num(packedStatExp[k], 0))))
  end
  local stats = Stats.calc(def, level, dvs, statExp)
  local moves = {}
  for _, entry in ipairs(tbl(packed.moves)) do
    local mv = tbl(entry)
    local mdef = data.moves[mv.id]
    if mdef and #moves < 4 then
      local ppUps = math.max(0, math.min(3, math.floor(num(mv.ppUps, 0))))
      local maxPP = mdef.pp + ppUps * math.floor(mdef.pp / 5)
      local move = { id = mv.id,
                     pp = math.max(0, math.min(maxPP, math.floor(num(mv.pp, 0)))) }
      if mv.ppUps ~= nil then move.ppUps = ppUps end
      table.insert(moves, move)
    end
  end
  if #moves == 0 then
    -- the v1 path keeps the substitute verbatim for peers built against it;
    -- a negotiated v2 link says so out loud instead
    if strict then return nil, "no shared moves" end
    moves = { { id = "TACKLE", pp = 35 } }
  end
  -- a forced level scales every stat including max HP, so the real party's
  -- current HP/status (a different level's numbers, possibly mid-fight)
  -- isn't meaningful anymore -- auto-level starts everyone full and fresh,
  -- same as a standardized tournament format would
  local forced = forceLevel
  local hp = forced and stats.hp
    or math.max(0, math.min(stats.hp, math.floor(num(packed.hp, stats.hp))))
  local status = forced and nil or text(packed.status)
  -- preserve the sender's original-trainer identity (party_struct MON_OTID +
  -- wPartyMonOT on a real cable), clamped/typed like every other field so a
  -- tampered packet can't inject a bad ID or a huge name.  Left nil when the
  -- packet omits them (a v1/old peer) -- no worse than before for that legacy
  -- path, and once ot is set the load-time stampOT backfill (mon.ot or ...)
  -- becomes a no-op so the sender's identity survives save/reload (#215).
  local packedOtId = num(packed.otId)
  local otId = packedOtId
    and math.max(0, math.min(65535, math.floor(packedOtId))) or nil
  local ot = type(packed.ot) == "string" and packed.ot:sub(1, 10) or nil
  return {
    species = packed.species,
    level = level,
    exp = math.max(0, math.floor(num(packed.exp,
      Growth.expForLevel(def.growthRate, level)))),
    dvs = dvs,
    statExp = statExp,
    stats = stats,
    hp = hp,
    status = status,
    nickname = text(packed.nickname),
    ot = ot,
    otId = otId,
    moves = moves,
    -- a namespace whose mod this install lacks survives untouched, so the
    -- mon keeps it for the trip home
    extra = plainCopy(packed.extra),
  }
end

-- -------------------------------------------------------------------
-- The Gen 2 party struct on the wire
--
-- A SECOND codec rather than optional keys on the Gen 1 one, because every
-- field the two share is spelled differently or means something else --
-- docs/gen2-link-design.md section 3 has the table.  The sharpest of them is
-- `status`: Gen 1 writes "PSN"/"BRN"/"SLP" (src/battle/Status.lua:62) and
-- Gen 2 writes "poison"/"burn"/"sleep" (src/battle/gen2/Battle.lua:65), and a
-- shared codec would hand a Gold party a status string nothing in it
-- recognises -- a mon that arrives poisoned and never takes poison damage.
--
-- Nothing sends these yet.  They exist because the mapping is the part of a
-- Gen 2 trade that is decidable today and because a wrong guess here would
-- silently corrupt a traded mon later; the session, the UI and mail are listed
-- as not built in the design doc's section 7.
--
-- The cart's own party block is `Link_PrepPartyData_Gen2`
-- (pokegold engine/link/link.asm:810): player name, party count and species
-- list, trainer ID, six PARTYMON_STRUCT_LENGTH structs, six OT names, six
-- nicknames -- and, in the Trade Center only, mail as a SEPARATE block copied
-- out of sPartyMail.  Mail stays separate here for the same reason: it is not
-- a party-struct field (src/core/gen2/Mail.lua:84 keys it by party slot), and
-- packing it onto the mon would invent a shape the cart does not have.
-- -------------------------------------------------------------------

-- Gen 2 rolls four DVs and DERIVES the HP DV from their low bits
-- (Mon.hpDV, and pokegold's own GetMonDVs does the same shuffle), so the
-- hp entry never travels: sending it would let a tampered packet claim an HP
-- DV its four visible DVs cannot produce.
local GEN2_DVS = { "attack", "defense", "speed", "special" }
-- MON_STAT_EXP's five words, in struct order; src/battle/gen2/Mon.lua's
-- STAT_EXP_ORDER is the authority and there is no sixth (SpA and SpD share the
-- Special word, the way the Gen 1 struct left them)
local GEN2_STAT_EXP = { "hp", "attack", "defense", "speed", "special" }

function Protocol.packMon2(mon)
  local moves = {}
  for _, mv in ipairs(mon.moves or {}) do
    -- ppUps has no Gen 2 model yet (Mon.movesAtLevel writes id/pp/maxPp);
    -- carried when present so a mod that adds one is not silently capped, the
    -- same reasoning packMon gives for the Gen 1 field
    table.insert(moves, { id = mv.id, pp = mv.pp, ppUps = mv.ppUps })
  end
  local dvs = {}
  for _, k in ipairs(GEN2_DVS) do dvs[k] = (mon.dvs or {})[k] end
  local statExp = {}
  for _, k in ipairs(GEN2_STAT_EXP) do statExp[k] = (mon.statExp or {})[k] end
  return {
    species = mon.species,
    level = mon.level,
    -- MON_EXP, and the field is `experience` on a Gen 2 mon, not `exp`
    experience = mon.experience,
    hp = mon.hp,
    status = mon.status,
    nickname = mon.nickname,
    dvs = dvs,
    statExp = statExp,
    moves = moves,
    -- MON_ITEM.  The held item is battle math (Leftovers, King's Rock, the
    -- type boosters) and it travels with the mon, which is why held_items is
    -- link surface in the fingerprint.
    item = mon.item,
    -- MON_HAPPINESS / MON_PKRS, both of which the cart ships inside the party
    -- struct and both of which outlive a trade
    happiness = mon.happiness,
    pokerus = mon.pokerus,
    caughtLevel = mon.caughtLevel,
    ot = mon.ot or mon.otName,
    otId = mon.otId,
    -- an egg is a party slot the cart marks by writing EGG into wPartySpecies;
    -- the port marks it with isEgg instead (src/core/gen2/Breeding.lua:64)
    isEgg = mon.isEgg or nil,
    eggSteps = mon.isEgg and mon.eggSteps or nil,
    extra = plainCopy(mon.extra),
  }
end

-- Rebuild a Gen 2 mon locally.  Same contract as unpackMon: every number is
-- clamped and every derived value is RECOMPUTED from real species data, so a
-- tampered packet can invent neither stats nor a shiny.  opts.strict refuses by
-- name instead of substituting once two v2 peers have agreed on a verdict.
function Protocol.unpackMon2(data, packed, opts)
  local Mon = require("src.battle.gen2.Mon")
  local strict = opts and opts.strict
  if type(packed) ~= "table" then
    if strict then return nil, "unknown POKéMON" end
    return nil
  end
  local forceLevel = opts and tonumber(opts.forceLevel) or nil
  local def = data and data.pokemon and data.pokemon[packed.species]
  if not def then
    if strict then return nil, "unknown POKéMON" end
    return nil
  end
  local level = math.max(1, math.min(Mon.MAX_LEVEL,
    math.floor(num(packed.level, 5))))
  if forceLevel then
    level = math.max(1, math.min(Mon.MAX_LEVEL, math.floor(forceLevel)))
  end
  local packedDvs, packedStatExp = tbl(packed.dvs), tbl(packed.statExp)
  local dvs = {}
  for _, k in ipairs(GEN2_DVS) do
    dvs[k] = math.max(0, math.min(Mon.MAX_DV,
      math.floor(num(packedDvs[k], 0))))
  end
  -- derived, never taken from the packet (see GEN2_DVS above)
  dvs.hp = Mon.hpDV(dvs)
  local statExp = {}
  for _, k in ipairs(GEN2_STAT_EXP) do
    statExp[k] = math.max(0, math.min(65535,
      math.floor(num(packedStatExp[k], 0))))
  end
  local stats = Mon.stats(def.baseStats, dvs, level, statExp)
  local moves = {}
  for _, packedMove in ipairs(tbl(packed.moves)) do
    local mv = tbl(packedMove)
    local mdef = data.moves and data.moves[mv.id]
    if mdef and #moves < 4 then
      local ppUps = math.max(0, math.min(3, math.floor(num(mv.ppUps, 0))))
      local maxPp = (mdef.pp or 0) + ppUps * math.floor((mdef.pp or 0) / 5)
      local entry = { id = mv.id, maxPp = maxPp,
                      pp = math.max(0, math.min(maxPp, math.floor(num(mv.pp, 0)))) }
      if mv.ppUps ~= nil then entry.ppUps = ppUps end
      table.insert(moves, entry)
    end
  end
  if #moves == 0 then
    if strict then return nil, "no shared moves" end
    -- the Gen 1 substitute, in Gen 2's move-entry shape
    local tackle = data.moves and data.moves.TACKLE
    moves = { { id = "TACKLE", pp = (tackle and tackle.pp) or 35,
                maxPp = (tackle and tackle.pp) or 35 } }
  end
  -- An item the receiving game has never heard of cannot be held: the battle
  -- would read no heldEffect for it and the bag would show a blank row.  This
  -- is the same judgement CheckTimeCapsuleCompatibility makes from the other
  -- side (pokegold engine/link/link.asm:1970 refuses mail rather than shipping
  -- an item the peer cannot represent), and the Gen 2 arm of
  -- Protocol.eligibleParty is what keeps it from ever reaching here on a
  -- negotiated trade.
  local item = type(packed.item) == "string" and packed.item or nil
  if item ~= nil and not (data.items and data.items[item]) then
    if strict then return nil, "unknown item" end
    item = nil
  end
  local forced = forceLevel
  local hp = forced and stats.hp
    or math.max(0, math.min(stats.hp, math.floor(num(packed.hp, stats.hp))))
  local status = forced and nil or text(packed.status)
  local packedOtId = num(packed.otId)
  local otId = packedOtId
    and math.max(0, math.min(65535, math.floor(packedOtId))) or nil
  local ot = type(packed.ot) == "string" and packed.ot:sub(1, 10) or nil
  local growth = Mon.growthFor(data, def.growthRate)
  local mon = {
    species = packed.species,
    name = def.name or packed.species,
    nickname = text(packed.nickname),
    level = level,
    experience = math.max(0, math.floor(num(packed.experience,
      Mon.experienceForLevel(growth, level)))),
    dvs = dvs,
    statExp = statExp,
    stats = stats,
    hp = hp,
    maxHp = stats.hp,
    types = def.types,
    status = status,
    moves = moves,
    item = item,
    -- GiveEgg starts a hatched mon at 120 and a caught one at 70; a traded mon
    -- keeps what it arrived with, clamped to the byte the cart stores it in
    happiness = math.max(0, math.min(255,
      math.floor(num(packed.happiness, 70)))),
    pokerus = math.max(0, math.min(255, math.floor(num(packed.pokerus, 0)))),
    caughtLevel = math.max(1, math.min(Mon.MAX_LEVEL,
      math.floor(num(packed.caughtLevel, level)))),
    ot = ot,
    otName = ot,
    otId = otId,
    extra = plainCopy(packed.extra),
  }
  if packed.isEgg then
    mon.isEgg = true
    mon.eggSteps = math.max(0, math.floor(num(packed.eggSteps, 0)))
  end
  -- Derived from the DVs on the RECEIVING side, exactly as they were derived on
  -- the sending one: shininess, gender and an Unown's letter are all functions
  -- of the same four bytes (Mon.isShiny / Mon.gender / Unown.letterFromDVs), so
  -- sending them would only give a patched client a way to claim a shiny it
  -- never rolled.
  local ctx = { species = packed.species, def = def, level = level }
  mon.shiny = Mon.isShiny(dvs, ctx)
  mon.gender = Mon.gender(def, dvs, ctx)
  local Unown = require("src.core.gen2.Unown")
  if packed.species == Unown.SPECIES then
    mon.unownLetter = Unown.letterFromDVs(dvs)
  end
  return mon
end

function Protocol.packParty(party, indices)
  local mons = {}
  if indices then
    for _, i in ipairs(indices) do
      table.insert(mons, Protocol.packMon(party[i]))
    end
    return mons
  end
  for _, mon in ipairs(party) do
    table.insert(mons, Protocol.packMon(mon))
  end
  return mons
end

-- ------- subset negotiation

-- every record hash, not just this party's slice: the receiver filters
-- its OWN party against these (eligibleParty), so a message limited to the
-- sender's party read "not on the other game" for every species the two
-- parties did not happen to share, and a subset trade between different
-- games showed neither side (#511).  The full catalog is ~300 short hash
-- strings -- still one message.
function Protocol.recordsMessage(data, party)
  local generation = Fingerprint.generationOf(data)
  local msg = { type = "records",
                pokemon = Fingerprint.records(data, "pokemon", generation),
                moves = Fingerprint.records(data, "moves", generation) }
  -- One more map on Gen 2, and additive by the same rule the hello follows: a
  -- peer that never sends `heldItems` is one whose game has no held items, and
  -- eligibleParty treats an absent map as "nothing to check" so the Gen 1 path
  -- is byte-identical.  A held item is battle math AND it rides along on the
  -- traded mon, so a mon holding one the peer rebuilds differently is exactly
  -- as untradeable as a mon that knows a move it rebuilds differently.
  if generation == 2 then
    msg.heldItems = Fingerprint.records(data, "held_items", generation)
  end
  return msg
end

-- a mon may cross the wire only if both peers rebuild it identically: the
-- species and every move id has to exist on the other game with the same
-- record hash.  Filtering is symmetric, so the two sides always agree on
-- which slots are in play and a pick can never land on a different mon.
function Protocol.eligibleParty(party, myRecords, theirRecords)
  local eligible, reasons = {}, {}
  theirRecords = tbl(theirRecords)
  myRecords = tbl(myRecords)
  local theirSpecies = tbl(theirRecords.pokemon)
  local theirMoves = tbl(theirRecords.moves)
  local mySpecies = tbl(myRecords.pokemon)
  local myMoves = tbl(myRecords.moves)
  -- Gen 2 only, and absent on both sides of a Gen 1 trade, which is what keeps
  -- the loop below unchanged for Red: a mon with no `item` never reaches the
  -- held-item arm at all.
  local theirHeld = theirRecords.heldItems ~= nil
    and tbl(theirRecords.heldItems) or nil
  local myHeld = tbl(myRecords.heldItems)
  for i, mon in ipairs(tbl(party)) do
    local reason
    if not theirSpecies[mon.species] then
      reason = "not on the other game"
    elseif theirSpecies[mon.species] ~= mySpecies[mon.species] then
      reason = "different data"
    -- Absence before difference, because a missing row on their side reads as
    -- "different" to a naive comparison and the player would be told the wrong
    -- thing.  Both arms are guarded on myHeld[mon.item]: an item with no held
    -- behaviour on EITHER game (a POTION in the item slot) is just an id, and
    -- an id the peer already has by way of the species check.
    elseif mon.item and theirHeld and myHeld[mon.item]
        and not theirHeld[mon.item] then
      -- we hold it AS a held item and they have no such row: the mon would
      -- arrive holding something their battle cannot read
      reason = "unknown item"
    elseif mon.item and theirHeld and myHeld[mon.item]
        and theirHeld[mon.item] ~= myHeld[mon.item] then
      -- the item exists on both games but does something else on theirs
      reason = "different item"
    else
      for _, mv in ipairs(mon.moves or {}) do
        if not theirMoves[mv.id] then
          reason = "unknown move"
          break
        elseif theirMoves[mv.id] ~= myMoves[mv.id] then
          reason = "different move data"
          break
        end
      end
    end
    eligible[i] = reason == nil
    reasons[i] = reason
  end
  return eligible, reasons
end

-- -------------------------------------------------------------------
-- Trade session: symmetric state machine.  Feed it messages; read
-- .stage ("waitRecords" -> "waitParty" -> "picking" -> "waitPick" ->
-- "confirming" -> "done"/"cancelled").  When done, .result =
-- {give=idx, getMon=mon}.  A subset session negotiates the eligible
-- slots first, so both sides send and index the same filtered list.
-- -------------------------------------------------------------------

local TradeSession = {}
TradeSession.__index = TradeSession
Protocol.TradeSession = TradeSession

-- opts: { subset, strict, peerName } -- all absent on the v1 path
function TradeSession.new(data, party, opts)
  opts = opts or {}
  local self = setmetatable({
    data = data,
    party = party,
    subset = opts.subset or false,
    strict = opts.strict or false,
    peerName = opts.peerName,
    stage = opts.subset and "waitRecords" or "waitParty",
    sendIndices = nil,
    eligible = nil,
    reasons = {},
    theirParty = nil,
    myPick = nil,
    theirPick = nil,
    myConfirm = nil,
    theirConfirm = nil,
  }, TradeSession)
  if not self.subset then
    local all = {}
    for i = 1, #party do all[i] = i end
    self.sendIndices = all
  end
  return self
end

-- the first message on the wire: a subset trade has to agree on which mons
-- both games rebuild identically before either party can be sent
function TradeSession:opening()
  if self.subset then
    return Protocol.recordsMessage(self.data, self.party)
  end
  return self:partyMessage()
end

function TradeSession:partyMessage()
  return { type = "party",
           mons = Protocol.packParty(self.party, self.sendIndices) }
end

-- Our own side of the comparison is built by the SAME function that puts our
-- records on the wire, so the two can never drift: an open-coded pair of
-- Fingerprint.records calls here left `heldItems` off our side only, and
-- eligibleParty's held-item arms are both guarded on myHeld[mon.item] -- so on
-- Gen 2 they were unreachable from the only production caller and a mon
-- holding an item the peer rebuilds differently sailed through the filter.
-- The message's `type` field is inert to eligibleParty, which reads exactly
-- the three record maps.
function TradeSession:_negotiate(theirRecords)
  local mine = Protocol.recordsMessage(self.data, self.party)
  self.eligible, self.reasons =
    Protocol.eligibleParty(self.party, mine, theirRecords)
  local indices = {}
  for i = 1, #self.party do
    if self.eligible[i] then indices[#indices + 1] = i end
  end
  self.sendIndices = indices
end

-- the UI greys what the other game would rebuild differently
function TradeSession:canPick(index)
  return self.eligible == nil or self.eligible[index] == true
end

-- returns a message to put on the wire, or nil
function TradeSession:handle(msg)
  if msg.type == "records" then
    -- only once: re-filtering after our party went out would slide the
    -- indices the peer is already holding
    if self.stage ~= "waitRecords" then return nil end
    self:_negotiate(msg)
    self.stage = "waitParty"
    return self:partyMessage()
  elseif msg.type == "party" then
    self.theirParty = {}
    for _, packed in ipairs(msg.mons or {}) do
      local mon, why = Protocol.unpackMon(self.data, packed,
                                          { strict = self.strict })
      if mon then
        table.insert(self.theirParty, mon)
      elseif self.strict then
        -- dropping a row would slide every later index by one and the
        -- two sides would commit different mons; refuse the whole trade
        self.stage = "cancelled"
        self.error = why or "the other game sent an unknown POKéMON"
        return nil
      end
    end
    if self.stage == "waitParty" then self.stage = "picking" end
  elseif msg.type == "pick" then
    self.theirPick = num(msg.index)
    self:advance()
  elseif msg.type == "confirm" then
    self.theirConfirm = msg.ok
    self:advance()
  elseif msg.type == "bye" then
    self.stage = "cancelled"
  end
  return nil
end

-- index is a real party slot; the wire carries its position in the list
-- this side actually sent, which is the only space both peers share
function TradeSession:wireIndex(index)
  for pos, i in ipairs(self.sendIndices or {}) do
    if i == index then return pos end
  end
  return index
end

function TradeSession:pick(index)
  self.myPick = index
  self:advance()
  return { type = "pick", index = self:wireIndex(index) }
end

function TradeSession:confirm(ok)
  self.myConfirm = ok
  self:advance()
  return { type = "confirm", ok = ok }
end

function TradeSession:pickResolves()
  local index = self.theirPick
  if type(index) ~= "number" then return false end
  return self.theirParty ~= nil and self.theirParty[index] ~= nil
end

function TradeSession:advance()
  if self.theirPick ~= nil and self.theirParty and not self:pickResolves() then
    self.stage = "cancelled"
    self.error = "the other game picked a POKéMON that isn't there"
    return
  end
  if self.stage == "picking" and self.myPick then
    self.stage = self.theirPick and "confirming" or "waitPick"
  elseif self.stage == "waitPick" and self.theirPick then
    self.stage = "confirming"
  end
  if self.stage == "confirming" and self.myConfirm ~= nil and self.theirConfirm ~= nil then
    if self.myConfirm and self.theirConfirm then
      self.stage = "done"
    else
      self.stage = "cancelled"
    end
  end
end

-- apply the completed trade to the local party; returns the new mon
-- (trade evolutions like Kadabra -> Alakazam trigger on the receiving
-- side, as on a real link cable)
function TradeSession:apply(game)
  assert(self.stage == "done", "trade not complete")
  local received = self.theirParty[self.theirPick]
  local sent = self.party[self.myPick]
  received.traded = true -- boosted exp (different OT)
  -- a mod validates its own extra namespace here, before the mon is filed
  Runtime.emit("pokemon.received",
               { mon = received, from = "link", peerName = self.peerName })
  self.party[self.myPick] = received
  -- PIKAHAPPY_TRADE (engine/link/cable_club.asm:801): trading the
  -- companion away is the biggest happiness hit and zeroes the mood
  if game and sent then
    require("src.world.PikachuFollower")
      .modifyHappiness(game.save, "TRADE", sent)
  end
  if game and game.save.pokedex then
    game.save.pokedex.seen[received.species] = true
    game.save.pokedex.owned[received.species] = true
  end
  local def = self.data.pokemon[received.species]
  local evolveTo
  for _, evo in ipairs(def.evolutions or {}) do
    if evo.method == "TRADE" then
      evolveTo = evo.species
      break
    end
  end
  Runtime.emit("trade.completed",
               { sent = sent, received = received, evolveTo = evolveTo })
  return received, evolveTo
end

return Protocol
