-- Deterministic digest of the link surface: the slice of merged data whose
-- value decides whether two lockstep simulations stay identical and whether a
-- traded mon is rebuilt the same way on both machines (D8).  Peers whose
-- digests agree may battle; peers whose digests differ negotiate a trade
-- subset instead of desyncing three turns in.
--
-- Everything is serialized through an explicit sorted key order.  pairs()
-- order differs between two runs of the same build, so a digest that
-- inherited it would reject identical peers at random -- that is the whole
-- reason this file exists instead of a hash over tostring(data).
--
-- Deliberately excluded: sprite paths and `source` (install-specific
-- generated paths that differ between two otherwise identical machines),
-- names, dex entries, learnsets and TM/HM lists (they change no battle math
-- and no trade rebuild).
--
-- Two generations, two surfaces.  Gold's link surface is the same IDEA over
-- different tables -- statuses live at data.gen2Statuses, the special stat is
-- two stats, the exp curves are data rather than code, and held items exist at
-- all -- so the Gen 2 arm below is a second surface writer, not a widened Gen 1
-- one.  Widening would have moved the Gen 1 digest, which is pinned by
-- tests/engine/gate_fingerprint.lua and by every installed build in the wild.
-- docs/gen2-link-design.md section 5 is the field-by-field reasoning for what
-- the Gen 2 surface covers and what it deliberately leaves out.

local Runtime = require("src.mods.Runtime")

local Fingerprint = {}

-- ------- FNV-1a, two lanes

-- Two 32-bit lanes with different offset bases, concatenated into a 64-bit
-- hex digest.  Pure arithmetic: the 32-bit product is split so every
-- intermediate stays inside a double's exact integer range, and the low-byte
-- xor runs off a nibble table -- LuaJIT has bit ops, plain 5.1 does not, and
-- tools load this file outside the game.
local PRIME = 16777619
local LANE_A, LANE_B = 2166136261, 2654435769

local XOR4 = {}
for a = 0, 15 do
  XOR4[a] = {}
  for b = 0, 15 do
    local x, y, r = a, b, 0
    for place = 0, 3 do
      if x % 2 ~= y % 2 then r = r + 2 ^ place end
      x, y = math.floor(x / 2), math.floor(y / 2)
    end
    XOR4[a][b] = r
  end
end

local function xor8(a, b)
  return XOR4[math.floor(a / 16)][math.floor(b / 16)] * 16 + XOR4[a % 16][b % 16]
end

local function step(h, byte)
  local lo = h % 65536
  local hi = (h - lo) / 65536
  lo = lo - lo % 256 + xor8(lo % 256, byte)
  return (lo * PRIME + (hi * PRIME % 65536) * 65536) % 4294967296
end

local function digest(text)
  local a, b = LANE_A, LANE_B
  for i = 1, #text do
    local byte = text:byte(i)
    a = step(a, byte)
    b = step(b, byte)
  end
  return ("%08x%08x"):format(a, b)
end

Fingerprint.digest = digest

-- ------- canonical serialization

-- %.17g is exact for every integer stat involved and is the same format the
-- wire encoder uses, so a value that survives JSON hashes the same
local function number(v)
  return ("%.17g"):format(v)
end

local writeValue

-- tables are written array part first (order is meaning there: type chart
-- rows, evolution lists), then named keys in sorted order
writeValue = function(out, v)
  local t = type(v)
  if t == "number" then
    out[#out + 1] = "#" .. number(v)
  elseif t == "string" then
    out[#out + 1] = "$" .. v
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif t == "table" then
    out[#out + 1] = "("
    local n = #v
    for i = 1, n do writeValue(out, v[i]) end
    local keys = {}
    for k in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      out[#out + 1] = "." .. tostring(k)
      writeValue(out, v[k])
    end
    out[#out + 1] = ")"
  else
    -- a handler's bytes are not portably hashable; mods bump the record's
    -- rev instead, and the mod version is the backstop when they forget
    out[#out + 1] = "?"
  end
end

-- an absent field is skipped identically on both sides, so a record that
-- never had the key and one whose mod removed it agree
local function writeFields(out, record, fields)
  for _, field in ipairs(fields) do
    local v = record[field]
    if v ~= nil then
      out[#out + 1] = "." .. field
      writeValue(out, v)
    end
  end
end

local function sortedIds(map)
  local ids = {}
  for id in pairs(map or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- ------- the link surface

-- catchRate stays out (#511): no link mode ever reads it -- a ball thrown
-- in a link battle is a trainer-battle throw and always refused (pokered
-- engine/items/item_effects.asm ItemUseBall), and the trade rebuild never
-- touches it.  Hashing it split Red/Blue from Yellow, whose only link
-- surface delta is the Dragonair/Dragonite catch-rate bytes
-- (data/pokemon/base_stats/dragonair.asm db 45 vs 27, dragonite.asm 45
-- vs 9), when the real cable links R/B/Y freely.
local SPECIES_FIELDS = { "baseStats", "types", "baseExp",
                         "growthRate", "evolutions" }
local MOVE_FIELDS = { "power", "type", "accuracy", "pp", "effect", "category",
                      "priority", "highCrit", "fixedDamage", "multiHit",
                      "counterable", "semiInvulnerable" }
-- catchBonus/shakeBonus are this engine's names for the plan's catchModifier
local STATUS_FIELDS = { "rev", "catchBonus", "shakeBonus", "statPenalty",
                        "cureOnSwitch", "beforeMovePriority" }
local EFFECT_FIELDS = { "rev", "kind", "accuracyChecked" }
local CONSTANT_FIELDS = { "partyMax", "moveMax", "levelCap", "dexSize",
                          "badgeBoosts" }

local RECORD_FIELDS = { pokemon = SPECIES_FIELDS, moves = MOVE_FIELDS,
                        statuses = STATUS_FIELDS, move_effects = EFFECT_FIELDS }

Fingerprint.FIELDS = RECORD_FIELDS

-- ------- the Gen 2 link surface
--
-- Same doctrine, applied to Gold's records.  Every difference from the Gen 1
-- lists above is a real Gen 2 change rather than an extractor spelling:
--
--   baseStats     carries specialAttack/specialDefense instead of special
--                 (pokegold data/pokemon/base_stats/), which writeValue hashes
--                 by sorted key without needing to know either name
--   genderRatio   Gen 2 has ATTRACT, so two peers that disagree on a species'
--                 gender split disagree on whether a move lands.  Nothing else
--                 out of the breeding block is here: the Day-Care is local,
--                 there is no link breeding, and an egg's contents are decided
--                 before it can be traded.
--   evolutions    points at `into` rather than `species` and carries the
--                 happiness window / stat comparison; it decides what a traded
--                 mon becomes, exactly as on Gen 1
--
-- catchRate stays out for the reason #511 gives, and so does the whole
-- eggGroups/eggMoves/eggSteps block, `items` (the wild held-item slots, rolled
-- before a link session can see them) and tmhm.
local GEN2_SPECIES_FIELDS = { "baseStats", "types", "baseExp",
                              "growthRate", "evolutions", "genderRatio" }
-- effectChance is the one addition: Gen 1 encodes a secondary effect's odds in
-- the effect itself, Gen 2 stores them per move (pokegold data/moves/moves.asm
-- `move` macro, the effect chance byte), so two peers that disagree about
-- BODY SLAM's 30 percent disagree about the battle.  The rest of the Gen 1
-- list rides along unchanged: those keys are absent from an extracted Gold
-- record, and writeFields skips an absent field, so they cost nothing and
-- cover a mod that sets one.
local GEN2_MOVE_FIELDS = { "power", "type", "accuracy", "pp", "effect",
                           "effectChance", "category", "priority", "highCrit",
                           "fixedDamage", "multiHit", "counterable",
                           "semiInvulnerable" }
-- the same six the Gen 1 statuses carry: src/mods/Schemas.lua R.statuses is one
-- spec for both games, and Gold's own records (src/battle/gen2/Battle.lua
-- STATUS_RECORDS) fill exactly these
local GEN2_STATUS_FIELDS = STATUS_FIELDS
-- `status` beside kind: a Gen 2 move_effects record is
-- { kind = "primary"/"secondary", status = "burn" } for every status-inflicting
-- effect (src/battle/gen2/Battle.lua MOVE_EFFECT_RECORDS), so the status a
-- given effect inflicts is part of the surface rather than part of the handler
local GEN2_EFFECT_FIELDS = { "rev", "kind", "accuracyChecked", "status" }
-- ItemAttributes' last two columns.  Pure battle math (Leftovers' heal, King's
-- Rock's odds, a type booster's percentage) and the item rides along with a
-- traded mon, which makes it trade surface too.
local GEN2_HELD_FIELDS = { "rev", "heldEffect", "heldParameter" }
-- The exp curve coefficients, straight off pokegold data/growth_rates.asm.  On
-- Gen 1 this is code (src/pokemon/Growth.lua) and cannot be hashed at all; on
-- Gold it is data the extractor writes, and it decides what level a traded
-- mon's experience buys, so it is surface.
local GEN2_GROWTH_FIELDS = { "numerator", "denominator", "squared", "linear",
                             "constant" }

local GEN2_RECORD_FIELDS = { pokemon = GEN2_SPECIES_FIELDS,
                             moves = GEN2_MOVE_FIELDS,
                             statuses = GEN2_STATUS_FIELDS,
                             move_effects = GEN2_EFFECT_FIELDS,
                             held_items = GEN2_HELD_FIELDS,
                             growth_rates = GEN2_GROWTH_FIELDS }

Fingerprint.GEN2_FIELDS = GEN2_RECORD_FIELDS

-- the allowlist table for a generation; unknown generations read as Gen 1, the
-- same default GameVersion.generation() carries
local function fieldsFor(generation)
  if generation == 2 then return GEN2_RECORD_FIELDS end
  return RECORD_FIELDS
end

-- ------- which generation a merged dataset belongs to
--
-- Read off the data rather than off GameVersion, for two reasons: this file is
-- loaded by tools and headless tests that never boot a game (see the FNV
-- comment above), and a caller that hands over a fixture dataset should get a
-- digest for THAT dataset rather than for whatever the process last booted.
--
-- data.type_chart.generation is written by the Gen 2 extractor and is the
-- cheapest honest answer.  The namespace check behind it covers a dataset
-- assembled without a type chart: gen2Statuses/gen2MoveEffects/gen2Constants
-- are Data keys only a Gen 2 boot ever creates (src/core/Game2.lua:load and
-- src/mods/Builtins.lua's Gen 2 registrants), and Schemas.GEN1 gates every one
-- of the Gen 2-only registries to false, so a Red boot cannot grow one.
function Fingerprint.generationOf(data)
  if type(data) ~= "table" then return 1 end
  local chart = data.type_chart
  if type(chart) == "table" and tonumber(chart.generation) then
    return tonumber(chart.generation)
  end
  if data.gen2Statuses or data.gen2MoveEffects or data.gen2Constants then
    return 2
  end
  return 1
end

-- data.pokemon on Gold carries one sibling that is not a species: the
-- extractor's `growthRates` coefficient rows, which src/battle/gen2/Mon.lua
-- reads through growthFor.  It gets its own section in the surface, and it is
-- skipped here so the species id space -- which Fingerprint.records hands to
-- Protocol.eligibleParty as "the mons the peer can rebuild" -- never carries an
-- id no party slot could hold.
local NON_SPECIES = { growthRates = true, tmhmMoves = true, tutorMoves = true }

local function writeRecords(out, map, label, fields, skip)
  if map == nil then return end
  out[#out + 1] = "[" .. label .. "]"
  for _, id in ipairs(sortedIds(map)) do
    local record = map[id]
    if type(record) == "table" and not (skip and skip[id]) then
      out[#out + 1] = "@" .. id
      writeFields(out, record, fields)
    end
  end
end

-- data/items/attributes.asm:149
local function writeHeldRecords(out, map)
  if map == nil then return end
  out[#out + 1] = "[held_items]"
  for _, id in ipairs(sortedIds(map)) do
    local record = map[id]
    if type(record) == "table" and record.heldEffect ~= "HELD_NONE" then
      out[#out + 1] = "@" .. id
      writeFields(out, record, GEN2_HELD_FIELDS)
    end
  end
end

local function writeSection(out, data, kind)
  writeRecords(out, data[kind], kind, RECORD_FIELDS[kind])
end

-- the chart rows are an ordered array whose order the merge rebuilds from
-- registration history, so they hash in place; the type records ride along
-- because `category` decides the physical/special split
local function writeTypeChart(out, data)
  local chart = data.type_chart
  if not chart then return end
  out[#out + 1] = "[type_chart]"
  for _, row in ipairs(chart.matchups or {}) do
    out[#out + 1] = ("@%s>%s"):format(tostring(row.attacker), tostring(row.defender))
    writeValue(out, row.multiplier)
  end
  for _, id in ipairs(sortedIds(chart.types)) do
    local record = chart.types[id]
    if type(record) == "table" then
      out[#out + 1] = "@" .. id
      writeFields(out, record, { "category", "index" })
    end
  end
end

-- Gold's chart carries one extra ordered array: the matchups FORESIGHT
-- rewrites, which is how a Normal or Fighting move reaches a Ghost at all
-- (pokegold data/types/foresight_matchups.asm, read through
-- BattleCheckTypeMatchup's `.foresight` arm in engine/battle/effect_commands.asm).
-- Two peers that disagree about it disagree about a turn, so it is surface.
local function writeGen2TypeChart(out, data)
  writeTypeChart(out, data)
  local chart = data.type_chart
  if not chart or not chart.foresightMatchups then return end
  out[#out + 1] = "[foresight]"
  for _, row in ipairs(chart.foresightMatchups) do
    out[#out + 1] = ("@%s>%s"):format(tostring(row.attacker), tostring(row.defender))
    writeValue(out, row.multiplier)
  end
end

local function writeRulesets(out, data)
  local rulesets = data.rulesets
  if not rulesets then return end
  out[#out + 1] = "[rulesets]"
  for _, id in ipairs(sortedIds(rulesets)) do
    local record = rulesets[id]
    if type(record) == "table" then
      out[#out + 1] = "@" .. id
      writeValue(out, record)
    end
  end
end

local function writeConstants(out, data)
  if not data.constants then return end
  out[#out + 1] = "[constants]"
  writeFields(out, data.constants, CONSTANT_FIELDS)
end

-- a mod that wants an extra mon field to force agreement declares it here;
-- only the author revision is hashable, the pack/unpack pair is not
local function writeLinkFields(out, data)
  local fields = data.link_fields
  if not fields then return end
  out[#out + 1] = "[link_fields]"
  for _, id in ipairs(sortedIds(fields)) do
    local record = fields[id]
    if type(record) == "table" then
      out[#out + 1] = "@" .. id
      writeFields(out, record, { "rev" })
    end
  end
end

-- id@version of every enabled mod that touches the link surface: the
-- backstop for a logic-only change whose author forgot to bump a rev
local function modKey(mods)
  local parts = {}
  for _, mod in ipairs(mods or {}) do
    if mod.affectsLink ~= false then
      parts[#parts + 1] = ("%s@%s"):format(tostring(mod.id),
                                           tostring(mod.version or "?"))
    end
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

Fingerprint.modKey = modKey

-- ------- public API

-- memoized per merged-data identity: the digest is only ever asked for on
-- entry to link play, and vanilla single-player must not pay for it at all
local cache = setmetatable({}, { __mode = "k" })

local function surfaceGen1(data, mods)
  local out = {}
  writeSection(out, data, "pokemon")
  writeSection(out, data, "moves")
  writeTypeChart(out, data)
  writeSection(out, data, "statuses")
  writeSection(out, data, "move_effects")
  writeRulesets(out, data)
  writeConstants(out, data)
  writeLinkFields(out, data)
  out[#out + 1] = "[mods]" .. modKey(mods)
  return table.concat(out)
end

-- The Gen 2 surface.  Opens with a "[gen2]" tag so a Gen 2 digest can never
-- collide with a Gen 1 one even over degenerate data -- checkCompat refuses a
-- cross-generation pairing by the hello's `generation` field long before the
-- digests are compared, and this makes the digest agree with that refusal
-- instead of leaving it to luck.
--
-- data.gen2Constants is deliberately absent, and it is the one omission worth
-- spelling out: it is the ROM's ordered NAME lists (speciesOrder, itemOrder,
-- heldEffectOrder, mapOrder...), an index space the extractor uses, and every
-- dispatch in the Gen 2 simulation goes by name -- Battle.heldEffect compares
-- record.heldEffect strings, moveEffectRecordFor keys by EFFECT_*.  Reordering
-- one moves no battle math, so hashing it would split two peers over a table
-- neither of them dispatches on, which is the #511 mistake in a new place.
-- Balls and item_effects stay out for the reason the Gen 1 surface leaves them
-- out: no link mode lets a bag item be thrown.
local function surfaceGen2(data, mods)
  local out = { "[gen2]" }
  writeRecords(out, data.pokemon, "pokemon", GEN2_SPECIES_FIELDS, NON_SPECIES)
  -- the growth curves live on the species map as a sibling of the species
  -- records (data.pokemon.growthRates, written by the extractor and read by
  -- src/battle/gen2/Mon.lua:growthFor), so they hash as their own section
  -- rather than as a species with no fields
  writeRecords(out, data.pokemon and data.pokemon.growthRates,
               "growth_rates", GEN2_GROWTH_FIELDS)
  writeRecords(out, data.moves, "moves", GEN2_MOVE_FIELDS)
  writeGen2TypeChart(out, data)
  writeRecords(out, data.gen2Statuses, "statuses", GEN2_STATUS_FIELDS)
  writeRecords(out, data.gen2MoveEffects, "move_effects", GEN2_EFFECT_FIELDS)
  writeHeldRecords(out, data.gen2HeldItems)
  out[#out + 1] = "[mods]" .. modKey(mods)
  return table.concat(out)
end

-- `generation` is optional everywhere: absent means "ask the data"
-- (Fingerprint.generationOf), which is what every caller but a test does.
local function surface(data, mods, generation)
  if (generation or Fingerprint.generationOf(data)) == 2 then
    return surfaceGen2(data, mods)
  end
  return surfaceGen1(data, mods)
end

Fingerprint.surface = surface

-- mods: { { id, version, affectsLink } } -- the hello's mod array
function Fingerprint.compute(data, mods, generation)
  if not data then return digest("") end
  generation = generation or Fingerprint.generationOf(data)
  -- the generation rides in the memo key: one dataset asked for both digests
  -- (a test, a tool) must not be handed the other one back
  local key = modKey(mods) .. "|" .. tostring(generation)
  local hit = cache[data]
  if hit and hit.key == key then return hit.value end
  -- The hook keeps its Gen 1 name AND its Gen 1 arity.  `generation` is
  -- captured by the closure rather than passed as a third argument, so a mod
  -- that wraps link.fingerprint and forwards nxt(data, mods) -- the shape
  -- docs/modding.md documents and tests/mod_link_tests.lua exercises -- keeps
  -- working verbatim on Gold instead of silently dropping the argument and
  -- computing a Gen 1 digest over Gen 2 data.
  local value = Runtime.call("link.fingerprint", function(d, m)
    return digest(surface(d, m, generation))
  end, data, mods)
  cache[data] = { key = key, value = value }
  return value
end

-- per-record digests over the same allowlist, so two peers can agree on
-- exactly which species and moves they rebuild identically
local recordCache = setmetatable({}, { __mode = "k" })

-- The Data path a record kind reads from for a generation.  Only the Gen 2
-- side ever differs, and only for the registries Schemas.GEN2 namespaces.
local GEN2_PATHS = { statuses = "gen2Statuses", move_effects = "gen2MoveEffects",
                     held_items = "gen2HeldItems" }

local function recordMap(data, kind, generation)
  if generation == 2 then
    local path = GEN2_PATHS[kind]
    if path then return data[path] end
  end
  return data[kind]
end

function Fingerprint.records(data, kind, generation)
  generation = generation or Fingerprint.generationOf(data)
  local fields = fieldsFor(generation)[kind]
  assert(fields, ("no record allowlist for %s (generation %s)")
    :format(tostring(kind), tostring(generation)))
  local perData = recordCache[data]
  if not perData then
    perData = {}
    recordCache[data] = perData
  end
  local slot = kind .. "|" .. tostring(generation)
  if perData[slot] then return perData[slot] end
  local map = recordMap(data, kind, generation) or {}
  local skip = (generation == 2 and kind == "pokemon") and NON_SPECIES or nil
  local out = {}
  for id, record in pairs(map) do
    if type(record) == "table" and not (skip and skip[id]) then
      local buf = { "@" .. id }
      writeFields(buf, record, fields)
      out[id] = digest(table.concat(buf))
    end
  end
  perData[slot] = out
  return out
end

function Fingerprint.forget(data)
  cache[data] = nil
  recordCache[data] = nil
end

return Fingerprint
