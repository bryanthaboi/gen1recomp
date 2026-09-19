-- FireRed wild encounter grace period (pret wild_encounter.c).
--
-- FireRed is the only generation with a step cooldown between wild battles:
-- HandleWildEncounterCooldown refuses the roll for a map-dependent number of
-- steps after the last encounter, then lets 5%/step through so the wait is
-- soft rather than a hard floor.  Without it a Route 1 tile (rate 21) rolls
-- 21% per step and the game reads as "a wild battle nearly every step".
--
-- DoWildEncounterRateTest carries the rest of the same function family: the
-- bike and banked-failure rate modifiers, plus the flute / Cleanse Tag /
-- ability modifiers the cooldown also honours.
--
-- Every expected value below is the literal pret constant, so a drift in the
-- port shows up here rather than as a frequency change in-game.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Rng = require("src.core.game3.rng")
local Encounters = require("src.core.game3.encounters")

local LAND_SLOT = { { species = 16, minLevel = 3, maxLevel = 5 } }
Encounters._tables = {
  ROUTE_1 = { land = { rate = 21, slots = LAND_SLOT } },
  RARE = { land = { rate = 5, slots = LAND_SLOT } },
  COMMON = { land = { rate = 80, slots = LAND_SLOT } },
  POND = { water = { rate = 21, slots = LAND_SLOT } },
}
Encounters._loaded = true

local function reset()
  Encounters.resetRateModifiers()
end

-- ---------------------------------------------------------------- base table

-- pret GetMapBaseEncounterCooldown: 0xFF when there is no encounter data,
-- 0 at rate >= 80, 8 at rate < 10, else 8 - rate/10.
local GOLDEN_BASE = {
  [0] = 8, [5] = 8, [9] = 8, [10] = 7, [19] = 7, [21] = 6, [25] = 6,
  [40] = 4, [79] = 1, [80] = 0, [100] = 0,
}
for rate, want in pairs(GOLDEN_BASE) do
  eq(Encounters.mapBaseCooldown("land", rate), want, "mapBaseCooldown(land, " .. rate .. ")")
  eq(Encounters.mapBaseCooldown("water", rate), want, "mapBaseCooldown(water, " .. rate .. ")")
end
eq(Encounters.mapBaseCooldown("land", nil), 0xFF, "no landMonsInfo -> 0xFF")
eq(Encounters.mapBaseCooldown("water", nil), 0xFF, "no waterMonsInfo -> 0xFF")
eq(Encounters.mapBaseCooldown("none", 21), 0xFF, "TILE_ENCOUNTER_NONE -> 0xFF")

-- ---------------------------------------------------------------- counter

print("[test] cooldown counter")
reset()
eq(Encounters._stepsSinceLastEncounter, 0, "reset zeroes the counter")

-- Route 1 is a 6-step cooldown: the first six steps must be denied even with
-- the rate test favouring an encounter.
Rng.SeedRng(0xC0DE)
local allowedEarly = 0
for i = 1, 6 do
  if Encounters.handleCooldown("land", 21) then allowedEarly = allowedEarly + 1 end
  eq(Encounters._stepsSinceLastEncounter, i, "denied step " .. i .. " advances the counter")
end
check(allowedEarly == 0, "pinned seed: no leak across the 6-step cooldown")

-- Once the counter has reached minSteps the step is allowed, and the check
-- stops touching the RNG or the counter (pret returns TRUE immediately).
local before = Rng.getState().value
check(Encounters.handleCooldown("land", 21), "counter at minSteps allows the roll")
eq(Rng.getState().value, before, "allowed step consumes no RNG")
eq(Encounters._stepsSinceLastEncounter, 6, "allowed step leaves the counter alone")

-- A map with no encounter data aborts before the counter moves at all.
reset()
check(not Encounters.handleCooldown("land", nil), "no encounter data denies the step")
eq(Encounters._stepsSinceLastEncounter, 0, "no encounter data leaves the counter alone")

-- ---------------------------------------------------------------- leak

print("[test] 5%/step leak")
Rng.SeedRng(0x1234)
local leaked = 0
local STEPS = 20000
for _ = 1, STEPS do
  reset()
  if Encounters.handleCooldown("land", 21) then leaked = leaked + 1 end
end
local pct = leaked / STEPS * 100
check(pct > 4.5 and pct < 5.5, ("leak is 5%%/step (%.2f%%)"):format(pct))

-- ---------------------------------------------------------------- modifiers

print("[test] rate modifiers (pret HandleWildEncounterCooldown)")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local Runtime = require("src.core.game3.runtime")

local prevStore, prevSession = Space.store, Runtime.session
Space.store = Flags.newStore()

local function mods()
  return Encounters.cooldownMinSteps("land", 21)
end
local function setMods(flute, party)
  Flags.setFlag(Space.store, nil, 0x803, flute == "white")
  Flags.setFlag(Space.store, nil, 0x804, flute == "black")
  Runtime.session = party and { party = party } or nil
end

setMods(nil, nil)
local baseSteps, baseLeak = mods()
eq(baseSteps, 6, "base minSteps")
eq(baseLeak, 5, "base leak")

setMods("white", nil)
local ws, wl = mods()
eq(ws, 3, "White Flute halves minSteps")
eq(wl, 7, "White Flute raises the leak")

setMods("black", nil)
local bs, bl = mods()
eq(bs, 12, "Black Flute doubles minSteps")
eq(bl, 2, "Black Flute halves the leak")

setMods(nil, { { species = 1, level = 5, item = 190 } })
local cs, cl = mods()
eq(cs, 8, "Cleanse Tag raises minSteps by a third")
eq(cl, 3, "Cleanse Tag lowers the leak")

setMods(nil, { { species = 1, level = 5, abilityId = 1 } })
local ss, sl = mods()
eq(ss, 12, "Stench doubles minSteps")
eq(sl, 2, "Stench halves the leak")

setMods(nil, { { species = 1, level = 5, abilityId = 35 } })
local is, il = mods()
eq(is, 3, "Illuminate halves minSteps")
eq(il, 10, "Illuminate doubles the leak")

-- pret GetLeadMonIndex skips eggs, so an egg lead applies nothing.
setMods(nil, { { species = 1, level = 5, isEgg = true, abilityId = 35 } })
eq(mods(), 6, "egg lead applies no ability modifier")

-- ------------------------------------------------- rate test modifiers

-- pret DoWildEncounterRateTest applies the same modifiers to the roll's
-- threshold, in 1/1600ths, so they have to be pinned separately from the
-- cooldown's minSteps.
print("[test] rate test modifiers (pret DoWildEncounterRateTest)")
local function rateOf(r) return Encounters.encounterRate(r) end

setMods(nil, nil)
eq(rateOf(21), 336, "rate 21 -> 21*16")
eq(rateOf(0), 0, "rate 0 -> no threshold")
eq(rateOf(100), 1600, "rate 100 saturates at MAX_ENCOUNTER_RATE")

setMods("white", nil)
eq(rateOf(21), 504, "White Flute raises the threshold by half")
setMods("black", nil)
eq(rateOf(21), 168, "Black Flute halves the threshold")

setMods(nil, { { species = 1, level = 5, item = 190 } })
eq(rateOf(21), 224, "Cleanse Tag cuts the threshold to two thirds")

setMods(nil, { { species = 1, level = 5, abilityId = 1 } })
eq(rateOf(21), 168, "Stench halves the threshold")
setMods(nil, { { species = 1, level = 5, abilityId = 35 } })
eq(rateOf(21), 672, "Illuminate doubles the threshold")

-- pret clamps after the ability mod, so Illuminate on a saturated rate stays
-- at MAX_ENCOUNTER_RATE instead of overflowing.
setMods(nil, { { species = 1, level = 5, abilityId = 35 } })
eq(rateOf(100), 1600, "the clamp runs after the ability modifier")

-- Modifier order is observable through the integer divisions: pret applies
-- flute -> Cleanse Tag -> ability, and reordering changes the result.
setMods("white", { { species = 1, level = 5, item = 190 } })
eq(rateOf(5), 80, "flute before Cleanse Tag (reversed order gives 79)")
setMods(nil, { { species = 1, level = 5, item = 190, abilityId = 35 } })
eq(rateOf(7), 148, "Cleanse Tag before ability (reversed order gives 149)")

Space.store, Runtime.session = prevStore, prevSession

-- ------------------------------------------------- rate buff / bike

-- pret AddToWildEncounterRateBuff banks the rate of a failed roll, and the
-- Mach/Acro bike scales the threshold down by 20%.
print("[test] banked failure rate + bike")
local function rollLand()
  return Encounters.rollLand("ROUTE_1", nil, false)
end

Rng.SeedRng(0xC0DE)
Rng.SeedWildEncounterRng(1)
reset()
eq(Encounters._encounterRateBuff, 0, "buff starts empty")
eq(rollLand(), nil, "seed 1: the roll fails")
eq(Encounters._encounterRateBuff, 21, "a failed roll banks the area rate")
eq(Encounters.encounterRate(21), 337, "the banked rate lifts the threshold")

-- A cooldown denial returns before the rate test, so it banks nothing.
reset()
Encounters.handleCooldown("land", 21)
eq(Encounters._encounterRateBuff, 0, "a cooldown denial banks nothing")

-- So does the first-step-into-grass behaviour gate (pret returns before
-- DoWildEncounterRateTest there too).
Rng.SeedRng(2)
Rng.SeedWildEncounterRng(0xBEEF)
reset()
eq(Encounters.rollLand("ROUTE_1", nil, true), nil, "the behaviour gate denies")
eq(Encounters._encounterRateBuff, 0, "the behaviour gate banks nothing")

-- Starting a battle zeroes it again (pret sets encounterRateBuff = 0).
Rng.SeedRng(0xC0DE)
Rng.SeedWildEncounterRng(2)
reset()
check(rollLand() ~= nil, "seed 2: the roll lands")
eq(Encounters._encounterRateBuff, 0, "a landed encounter clears the buff")

-- A Repel zeroes the bank instead of growing it.
reset()
Rng.SeedWildEncounterRng(1)
Runtime.session = { repelSteps = 100 }
eq(rollLand(), nil, "the roll still fails under a Repel")
eq(Encounters._encounterRateBuff, 0, "an active Repel clears the bank")
Runtime.session = prevSession

-- The bank is what makes a long dry spell slowly likelier, so a big bank has
-- to move the threshold materially (pret: buff * 16 / 200).
reset()
Encounters._encounterRateBuff = 2500
eq(Encounters.encounterRate(21), 536, "banked 2500 adds 200 to the threshold")
reset()

-- pret TestPlayerAvatarFlags(PLAYER_AVATAR_FLAG_MACH_BIKE | ACRO_BIKE).
local Player = require("src.core.game3.player")
local prevBiking = Player.biking
Player.biking = true
eq(Encounters.encounterRate(21), 268, "the bike cuts the threshold to 80%")
Player.biking = false
eq(Encounters.encounterRate(21), 336, "on foot the threshold is unscaled")
Player.biking = prevBiking

-- ---------------------------------------------------------------- end to end

print("[test] step rolls (Route 1, rate 21)")
-- Steady state in tall grass: enterFromOther is only set on the first step in,
-- so every later step is a bare rate test.  That is the 21%/step baseline.
local function roll(steps, useCooldown)
  Rng.SeedRng(0xC0DE)
  Rng.SeedWildEncounterRng(0xBEEF)
  reset()
  local n, firstAt = 0, nil
  for i = 1, steps do
    local enc
    if useCooldown then
      enc = Encounters.onStep("ROUTE_1", "land", { enterFromOther = false })
    else
      enc = Encounters.rollLand("ROUTE_1", nil, false)
    end
    if enc then
      n = n + 1
      firstAt = firstAt or i
      reset()
    end
  end
  return n, firstAt
end

local withCooldown = roll(4000, true)
local withoutCooldown = roll(4000, false)
eq(withCooldown, 401, "4000 steps with the cooldown -> 401 encounters")
eq(withoutCooldown, 858, "4000 steps without it -> 858 encounters")
check(withCooldown < withoutCooldown / 2,
  ("cooldown more than halves the encounter count (%d vs %d)"):format(withCooldown, withoutCooldown))

-- The first encounter after a reset cannot land before the cooldown expires.
Rng.SeedRng(0xC0DE)
Rng.SeedWildEncounterRng(0xBEEF)
reset()
local pattern = {}
for i = 1, 10 do
  pattern[i] = Encounters.onStep("ROUTE_1", "land", { enterFromOther = false }) and "E" or "-"
end
eq(table.concat(pattern), "------E---", "first encounter lands on step 7 of a 6-step cooldown")

-- A rate-80 area gets no grace period, exactly as pret.
reset()
check(Encounters.cooldownMinSteps("land", 80) == 0, "rate 80 has no cooldown")
Rng.SeedRng(1)
check(Encounters.handleCooldown("land", 80), "rate 80 allows the first step")

-- Water uses its own area's rate.
reset()
eq(Encounters.cooldownMinSteps("water", 21), 6, "water area cooldown")

-- ---------------------------------------------------------------- re-arm

print("[test] the cooldown re-arms when a battle starts")
-- Regression for the Gen 2 bug #1229 class: a wild battle that no step rolled
-- (script, fishing) still has to restart the immunity steps, or the next step
-- in grass is a fresh encounter.
local BattleBridge = require("src.core.game3.battle_bridge")
Encounters._stepsSinceLastEncounter = 5
pcall(BattleBridge.startWild, nil, nil, { species = 16, level = 3 }, {})
eq(Encounters._stepsSinceLastEncounter, 0, "startWild restarts the immunity steps")

-- pret also restarts them on every map load (overworld.c LoadMap /
-- LoadMapFromWarp), which is what makes walking out of a route and back in
-- give a fresh grace period -- including the seamless connection crossing
-- between two routes.
print("[test] the cooldown re-arms on map load")
local Map = require("src.core.game3.map")
Encounters._stepsSinceLastEncounter = 5
pcall(Map.load, nil, nil, "FR_ROUTE1", {})
eq(Encounters._stepsSinceLastEncounter, 0, "map load restarts the immunity steps")

Encounters._stepsSinceLastEncounter = 5
pcall(Map.load, nil, nil, "FR_ROUTE1", { seamless = true })
eq(Encounters._stepsSinceLastEncounter, 0, "seamless connection load restarts them too")

Encounters._stepsSinceLastEncounter = 5
pcall(Map.load, nil, nil, "PALLET_TOWN", {})
eq(Encounters._stepsSinceLastEncounter, 5, "a non-game3 map id is not a load")

T.finish("wild_encounter_cooldown")
