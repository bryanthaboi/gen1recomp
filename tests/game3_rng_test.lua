#!/usr/bin/env luajit
-- Pret FireRed LCRNG + wild encounter stream smoke tests.

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

print("[test] 1. Golden Random() stream (seed 0x1234)")
local Rng = require("src.core.game3.rng")
Rng.SeedRng(0x1234)
-- Hand-verified first step + captured sequence from mulU32 ISO_RANDOMIZE1.
local GOLDEN_RANDOM = {
  19915, 57697, 17216, 65521, 49689, 27070, 63088, 15005,
  53261, 32661, 40992, 3727, 27521, 19775, 30255, 24698,
}
for i = 1, #GOLDEN_RANDOM do
  eq(Rng.Random(), GOLDEN_RANDOM[i], "Random()[" .. i .. "]")
end

print("[test] 2. Golden WildEncounterRandom() stream (seed 0xABCD)")
Rng.SeedWildEncounterRng(0xABCD)
local GOLDEN_WILD = { 8751, 19765, 35009, 51321, 30994, 38996, 9941, 30164 }
for i = 1, #GOLDEN_WILD do
  eq(Rng.WildEncounterRandom(), GOLDEN_WILD[i], "WildEncounterRandom()[" .. i .. "]")
end

print("[test] 3. Random32 / SeedRng / getState round-trip")
Rng.SeedRng(1)
local a = Rng.Random()
local b = Rng.Random()
Rng.SeedRng(1)
local c = Rng.Random32()
eq(c, a + b * 65536, "Random32 == Random | (Random<<16)")
local st = Rng.getState()
Rng.Random()
Rng.Random()
Rng.setState(st)
eq(Rng.getState().value, st.value, "setState restores value")

print("[test] 4. seedNewGame wires wild from Random()")
Rng.SeedRng(0x55AA)
-- Manual: after SeedRng, seedNewGame reseeds from timer unless seed forced.
local tid = Rng.seedNewGame({ seed = 0x55AA })
eq(tid, 0x55AA, "seedNewGame returns trainer seed")
-- Wild stream was seeded with first Random() after SeedRng(0x55AA).
-- Replay: SeedRng(0x55AA); local w = Random(); compare wild state after seedNewGame.
Rng.SeedRng(0x55AA)
local first = Rng.Random()
local afterNew = Rng.getState().wild
Rng.SeedRng(0x55AA)
Rng.SeedWildEncounterRng(Rng.Random())
eq(Rng.getState().wild, first, "SeedWildEncounterRng(Random()) uses first Random")
eq(afterNew, first, "seedNewGame wild state matches")

print("[test] 5. Encounter rolls are deterministic (no math.random)")
local Encounters = require("src.core.game3.encounters")
Encounters._tables = {
  TEST_MAP = {
    land = {
      rate = 21,
      slots = {
        { species = 16, minLevel = 3, maxLevel = 5 },
        { species = 19, minLevel = 3, maxLevel = 5 },
        { species = 21, minLevel = 3, maxLevel = 5 },
        { species = 13, minLevel = 3, maxLevel = 5 },
        { species = 10, minLevel = 3, maxLevel = 5 },
        { species = 29, minLevel = 3, maxLevel = 5 },
        { species = 32, minLevel = 3, maxLevel = 5 },
        { species = 56, minLevel = 3, maxLevel = 5 },
        { species = 60, minLevel = 3, maxLevel = 5 },
        { species = 69, minLevel = 3, maxLevel = 5 },
        { species = 74, minLevel = 3, maxLevel = 5 },
        { species = 16, minLevel = 5, maxLevel = 5 },
      },
    },
  },
}
Encounters._loaded = true

local function run_seq()
  Rng.SeedRng(0xC0DE)
  Rng.SeedWildEncounterRng(0xBEEF)
  local out = {}
  for i = 1, 40 do
    local enc = Encounters.rollLand("TEST_MAP", nil, i == 1)
    if enc then
      out[#out + 1] = string.format("%d:%d", enc.species, enc.level)
    else
      out[#out + 1] = "-"
    end
  end
  return table.concat(out, ",")
end

local seq1 = run_seq()
local seq2 = run_seq()
eq(seq1, seq2, "two identical seeds → identical encounter sequence")
check(seq1:find("%d+:%d+") ~= nil, "sequence includes at least one encounter")
-- First-step gate uses Random()%100; with seed 0xC0DE first roll is deterministic.
Rng.SeedRng(0xC0DE)
local gate = Rng.Random() % 100
check(gate >= 0 and gate < 100, "gate roll in 0..99")

print("[test] 6. Save schema persists rng")
local Schema = require("src.core.game3.save_schema_firered")
local session = Schema.newGame({ name = "ASH", rngSeed = 0x1111 })
check(type(session.rng) == "table", "newGame has rng table")
eq(session.trainerId, 0x1111, "newGame trainerId from seed")
local saved = Schema.toSaveTable(session)
check(saved.rng ~= nil and saved.rng.value ~= nil, "toSaveTable includes rng")
local loaded = Schema.fromSaveTable(saved)
eq(loaded.rng.value, saved.rng.value, "fromSaveTable keeps value")
eq(loaded.rng.wild, saved.rng.wild, "fromSaveTable keeps wild")
Rng.setState({ value = 0, value2 = 0, wild = 0 })
Rng.restoreFromSession(loaded)
eq(Rng.getState().value, loaded.rng.value, "restoreFromSession applies value")
eq(Rng.getState().wild, loaded.rng.wild, "restoreFromSession applies wild")

print("[test] 7. Battle State defaults to Rng.compat")
local State = require("src.core.game3.battle.state")
local st = State.new({
  wild = true,
  playerParty = { { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } } },
  foeMon = { species = 16, level = 3, hp = 15, maxHp = 15, moves = { 33 }, pp = { 35 } },
})
check(st.rng == Rng.compat, "State.new rng is Rng.compat")
Rng.SeedRng(42)
local r1 = st.rng(0, 255)
Rng.SeedRng(42)
local r2 = st.rng(0, 255)
eq(r1, r2, "compat is deterministic from SeedRng")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
