#!/usr/bin/env luajit
-- pokefirered/src/wild_encounter.c:117, :269, :309, :446, :509, :519

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Rng = require("src.core.game3.rng")
local Encounters = require("src.core.game3.encounters")
local Runtime = require("src.core.game3.runtime")

print("[test] 1. the Rock Smash and fishing entry points exist")
check(type(Encounters.rollRocks) == "function", "Encounters.rollRocks exists")
check(type(Encounters.rollFishing) == "function", "Encounters.rollFishing exists")
check(type(Encounters.hasFishingMons) == "function", "Encounters.hasFishingMons exists")
if type(Encounters.rollRocks) ~= "function" or type(Encounters.rollFishing) ~= "function" then
  print("[test] no Rock Smash / fishing area path at all; the rest cannot run")
  finish()
end

local ROCK_SLOTS = {
  { species = 74, minLevel = 5, maxLevel = 20 },
  { species = 74, minLevel = 10, maxLevel = 20 },
  { species = 74, minLevel = 15, maxLevel = 30 },
  { species = 75, minLevel = 25, maxLevel = 40 },
  { species = 75, minLevel = 30, maxLevel = 40 },
}
local FISH_SLOTS = {}
for i = 1, 10 do
  FISH_SLOTS[i] = { species = 1000 + i, minLevel = 10, maxLevel = 10 }
end
local FLAT_ROCKS = {}
for i = 1, 5 do
  FLAT_ROCKS[i] = { species = 2000 + i, minLevel = 12, maxLevel = 12 }
end

Encounters._tables = {
  SMASHABLE = { land = { rate = 7, slots = ROCK_SLOTS }, rocks = { rate = 50, slots = ROCK_SLOTS } },
  ALWAYS = { rocks = { rate = 100, slots = FLAT_ROCKS } },
  NEVER = { rocks = { rate = 0, slots = ROCK_SLOTS } },
  DRY = { land = { rate = 21, slots = ROCK_SLOTS } },
  POND = { fishing = { rate = 0, slots = FISH_SLOTS } },
}
Encounters._loaded = true

local prevSession = Runtime.session
local function setLead(ability)
  Runtime.session = {
    map = "SMASHABLE",
    party = { { species = 74, level = 50, hp = 20, abilityId = ability } },
  }
end
setLead(0)

local function reseed(n)
  Rng.SeedRng(n)
  Rng.SeedWildEncounterRng(n)
  Encounters.resetRateModifiers()
end

print("[test] 2. a map with no rockSmashMonsInfo denies without touching the RNG")
reseed(0x51A5)
local before = Rng.getState()
eq(Encounters.rollRocks("DRY"), nil, "a land-only map has no Rock Smash encounter")
eq(Encounters.rollRocks("NO_SUCH_MAP"), nil, "an unknown map has no Rock Smash encounter")
eq(Rng.getState().value, before.value, "the denial consumes no Random()")
eq(Rng.getState().wild, before.wild, "the denial consumes no WildEncounterRandom()")

print("[test] 3. rate 100 always rolls, rate 0 never does")
reseed(0x0B0B)
local hits, species = 0, {}
for _ = 1, 200 do
  local enc = Encounters.rollRocks("ALWAYS")
  if enc then
    hits = hits + 1
    species[enc.species] = (species[enc.species] or 0) + 1
    if enc.level ~= 12 then check(false, "flat slot returned level " .. tostring(enc.level)) end
  end
end
eq(hits, 200, "rate 100 clears MAX_ENCOUNTER_RATE every time")
reseed(0x0B0B)
local zero = 0
for _ = 1, 200 do
  if Encounters.rollRocks("NEVER") then zero = zero + 1 end
end
eq(zero, 0, "rate 0 never rolls")

print("[test] 4. Rock Smash picks slots on the water/rock weights (60/30/5/4/1)")
-- pokefirered/src/wild_encounter.c:101
reseed(0x7777)
local counts = {}
local N = 20000
for _ = 1, N do
  local enc = Encounters.rollRocks("ALWAYS")
  if enc then counts[enc.species] = (counts[enc.species] or 0) + 1 end
end
local WANT = { [2001] = 60, [2002] = 30, [2003] = 5, [2004] = 4, [2005] = 1 }
for sp, pct in pairs(WANT) do
  local got = (counts[sp] or 0) * 100 / N
  check(math.abs(got - pct) < 1.5,
    string.format("slot for species %d is %.2f%% of rolls, pret says %d%%", sp, got, pct))
end

print("[test] 5. Rock Smash passes ignoreAbility, so Stench and Illuminate do nothing")
-- pokefirered/src/wild_encounter.c:453
local ABILITY_STENCH, ABILITY_ILLUMINATE = 1, 35
setLead(0)
eq(Encounters.encounterRate(21), 336, "neutral lead: rate 21 is 336/1600")
setLead(ABILITY_STENCH)
eq(Encounters.encounterRate(21), 168, "Stench halves the ordinary threshold")
eq(Encounters.encounterRate(21, { ignoreAbility = true }), 336, "ignoreAbility skips Stench")
setLead(ABILITY_ILLUMINATE)
eq(Encounters.encounterRate(21), 672, "Illuminate doubles the ordinary threshold")
eq(Encounters.encounterRate(21, { ignoreAbility = true }), 336, "ignoreAbility skips Illuminate")

local function smashRun(ability)
  setLead(ability)
  reseed(0x2468)
  local out = {}
  for i = 1, 400 do
    local enc = Encounters.rollRocks("SMASHABLE")
    out[i] = enc and (enc.species * 1000 + enc.level) or 0
  end
  return table.concat(out, ",")
end
local function landRun(ability)
  setLead(ability)
  reseed(0x2468)
  local out = {}
  for i = 1, 400 do
    local enc = Encounters.rollLand("DRY", nil, false)
    out[i] = enc and (enc.species * 1000 + enc.level) or 0
  end
  return table.concat(out, ",")
end

local neutralSmash = smashRun(0)
check(neutralSmash == smashRun(ABILITY_STENCH), "a Stench lead changes no Rock Smash roll")
check(neutralSmash == smashRun(ABILITY_ILLUMINATE), "an Illuminate lead changes no Rock Smash roll")
local neutralLand = landRun(0)
check(neutralLand ~= landRun(ABILITY_STENCH),
  "the same Stench lead does move the ordinary land roll (the test can see the difference)")
setLead(0)

print("[test] 6. fishing area presence")
check(Encounters.hasFishingMons("POND"), "POND has fishingMonsInfo")
check(not Encounters.hasFishingMons("DRY"), "DRY has none")
check(not Encounters.hasFishingMons("NO_SUCH_MAP"), "an unknown map has none")
reseed(0x9999)
local fb = Rng.getState()
eq(Encounters.rollFishing("DRY", "old"), nil, "no fishing table means no encounter")
eq(Rng.getState().value, fb.value, "the fishing denial consumes no Random()")

print("[test] 7. every rod's slot window, at the exact pret boundaries")
-- pokefirered/src/wild_encounter.c:117
local function seedForDraw(target)
  for s = 1, 500000 do
    Rng.SeedRng(s)
    if Rng.Random() % 100 == target then return s end
  end
  return nil
end

local BOUNDARIES = {
  { "old", 0, 1 }, { "old", 69, 1 }, { "old", 70, 2 }, { "old", 99, 2 },
  { "good", 0, 3 }, { "good", 59, 3 }, { "good", 60, 4 }, { "good", 79, 4 },
  { "good", 80, 5 }, { "good", 99, 5 },
  { "super", 0, 6 }, { "super", 39, 6 }, { "super", 40, 7 }, { "super", 79, 7 },
  { "super", 80, 8 }, { "super", 94, 8 }, { "super", 95, 9 }, { "super", 98, 9 },
  { "super", 99, 10 },
}
for _, row in ipairs(BOUNDARIES) do
  local rod, draw, slot = row[1], row[2], row[3]
  local s = seedForDraw(draw)
  if not s then
    check(false, "no seed produces Random() % 100 == " .. draw)
  else
    Rng.SeedRng(s)
    local enc = Encounters.rollFishing("POND", rod)
    eq(enc and enc.species, 1000 + slot,
      string.format("%s rod, draw %d -> slot %d", rod, draw, slot))
  end
end

print("[test] 8. rod aliases resolve the same way")
local ALIASES = { old = { 0, 262, "OLD_ROD", "ITEM_OLD_ROD" },
  good = { 1, 263, "GOOD_ROD", "ITEM_GOOD_ROD" },
  super = { 2, 264, "SUPER_ROD", "ITEM_SUPER_ROD" } }
local WINDOW = { old = { 1, 2 }, good = { 3, 5 }, super = { 6, 10 } }
for rod, list in pairs(ALIASES) do
  for _, alias in ipairs(list) do
    reseed(0x1357)
    local enc = Encounters.rollFishing("POND", alias)
    local slot = enc and (enc.species - 1000) or -1
    check(slot >= WINDOW[rod][1] and slot <= WINDOW[rod][2],
      string.format("%s as %s lands in slots %d-%d (got %s)",
        rod, tostring(alias), WINDOW[rod][1], WINDOW[rod][2], tostring(slot)))
  end
end

print("[test] 9. fishing takes no rate test, no behaviour gate and no Repel check")
Runtime.session = {
  map = "POND",
  repelSteps = 250,
  party = { { species = 74, level = 100, hp = 20 } },
}
reseed(0x4242)
local bites = 0
for _ = 1, 300 do
  if Encounters.rollFishing("POND", "super") then bites = bites + 1 end
end
eq(bites, 300, "a level-100 lead under Repel still lands every cast (rate 0 table)")
setLead(0)

print("[test] 10. ChooseWildMonLevel draws even when min == max")
-- pokefirered/src/wild_encounter.c:155
reseed(0x8642)
local enc = Encounters.rollFishing("POND", "old")
check(enc ~= nil, "flat-level cast produced an encounter")
eq(enc and enc.level, 10, "flat slot still reports its level")
local after = Rng.getState().value
Rng.SeedRng(0x8642)
Rng.Random()
Rng.Random()
eq(Rng.getState().value, after, "one draw for the slot and one for the flat level")

print("[test] 11. an inverted slot range swaps rather than collapsing")
Encounters._tables.INVERTED = {
  fishing = { rate = 0, slots = { { species = 129, minLevel = 20, maxLevel = 10 } } },
}
reseed(0xAAAA)
local lo, hi = 99, 0
for _ = 1, 400 do
  local e = Encounters.rollFishing("INVERTED", "old")
  if e then
    if e.level < lo then lo = e.level end
    if e.level > hi then hi = e.level end
  end
end
eq(lo, 10, "inverted range floors at maxLevel")
eq(hi, 20, "inverted range ceils at minLevel")

print("[test] 12. a landed Rock Smash or cast re-arms the immunity steps")
setLead(0)
reseed(0x1111)
Encounters._stepsSinceLastEncounter = 4
Encounters._encounterRateBuff = 900
check(Encounters.rollRocks("ALWAYS") ~= nil, "rate 100 Rock Smash lands")
eq(Encounters._stepsSinceLastEncounter, 0, "Rock Smash resets stepsSinceLastEncounter")
eq(Encounters._encounterRateBuff, 0, "Rock Smash clears the rate bank")
Encounters._stepsSinceLastEncounter = 4
Encounters._encounterRateBuff = 900
check(Encounters.rollFishing("POND", "good") ~= nil, "a cast lands")
eq(Encounters._stepsSinceLastEncounter, 0, "fishing resets stepsSinceLastEncounter")
eq(Encounters._encounterRateBuff, 0, "fishing clears the rate bank")

print("[test] 13. a missed Rock Smash banks nothing")
setLead(0)
reseed(0x3333)
Encounters._encounterRateBuff = 0
local misses = 0
for _ = 1, 200 do
  if not Encounters.rollRocks("SMASHABLE") then misses = misses + 1 end
end
check(misses > 0, "rate 50 misses sometimes (" .. misses .. " of 200)")
eq(Encounters._encounterRateBuff, 0, "RockSmashWildEncounter never calls AddToWildEncounterRateBuff")

Runtime.session = prevSession
finish()
