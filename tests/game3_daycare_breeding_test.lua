#!/usr/bin/env luajit
-- pokefirered/src/daycare.c:1271

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

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local store = { flags = {}, vars = {} }
local session = {
  store = store, map = "FR_FOUR_ISLAND_POKEMON_DAY_CARE", party = {},
  name = "RED", trainerId = 4242, vars = {}, flags = {},
  dex = { seen = {}, owned = {} },
}
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local Daycare = require("src.core.game3.daycare")
local Breeding = require("src.core.game3.breeding")
local Natives = require("src.core.game3.scripting.natives")
local Std = require("src.core.game3.scripting.stdscripts")
local Flags = require("src.core.game3.scripting.flags")
local StepEvents = require("src.core.game3.step_events")

print("[test] 1. the compatibility tiers are the cart's")
eq(Breeding.PARENTS_INCOMPATIBLE, 0, "PARENTS_INCOMPATIBLE")
eq(Breeding.PARENTS_LOW_COMPATIBILITY, 20, "PARENTS_LOW_COMPATIBILITY")
eq(Breeding.PARENTS_MED_COMPATIBILITY, 50, "PARENTS_MED_COMPATIBILITY")
eq(Breeding.PARENTS_MAX_COMPATIBILITY, 70, "PARENTS_MAX_COMPATIBILITY")
eq(Breeding.EGG_HATCH_LEVEL, 5, "EGG_HATCH_LEVEL")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("meta.json")
if not cacheRoot then
  print("[skip] game3_daycare_breeding_test needs species data: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Party = require("src.core.game3.party")
local Rng = require("src.core.game3.rng")

local MAGIKARP, GYARADOS, DITTO, MEWTWO = 129, 130, 132, 150
local MAGNEMITE, GEODUDE, BULBASAUR, PIDGEY, PIDGEOT = 81, 74, 1, 16, 18

local function makeMon(species, level, opts)
  local scratch = { party = {}, name = "RED", trainerId = 4242, map = session.map }
  local ok, _, mon = Party.giveMon(scratch, species, level or 5, "")
  check(ok, "built a species " .. species)
  opts = opts or {}
  if opts.female ~= nil then
    -- pokefirered/src/pokemon.c:2733 GetGenderFromSpeciesAndPersonality
    local base = mon.personality - (mon.personality % 256)
    mon.personality = base + (opts.female and 0 or 254)
    mon.gender = Pokemon.gender(species, mon.personality)
  end
  if opts.otId then mon.otId = opts.otId end
  return mon
end

local function pair(a, b)
  return { a, b, steps = { 0, 0 }, stepCounter = 0 }
end

print("[test] 2. GetDaycareCompatibilityScore, every tier")
local karpF = makeMon(MAGIKARP, 5, { female = true, otId = 4242 })
local karpM = makeMon(MAGIKARP, 5, { female = false, otId = 4242 })
local karpMOther = makeMon(MAGIKARP, 5, { female = false, otId = 777 })
eq(Pokemon.gender(MAGIKARP, karpF.personality), "F", "the first MAGIKARP is female")
eq(Pokemon.gender(MAGIKARP, karpM.personality), "M", "the second is male")
eq(Breeding.compatibility(pair(karpF, karpMOther)), 70,
  "same species, different trainers is PARENTS_MAX_COMPATIBILITY")
eq(Breeding.compatibility(pair(karpF, karpM)), 50,
  "same species, same trainer is PARENTS_MED_COMPATIBILITY")
local gyaraM = makeMon(GYARADOS, 25, { female = false, otId = 777 })
local gyaraMSame = makeMon(GYARADOS, 25, { female = false, otId = 4242 })
eq(Breeding.compatibility(pair(karpF, gyaraM)), 50,
  "different species, different trainers is PARENTS_MED_COMPATIBILITY")
eq(Breeding.compatibility(pair(karpF, gyaraMSame)), 20,
  "different species, same trainer is PARENTS_LOW_COMPATIBILITY")
eq(Breeding.compatibility(pair(karpM, gyaraMSame)), 0,
  "two males never breed")
local ditto = makeMon(DITTO, 20, { otId = 4242 })
local dittoOther = makeMon(DITTO, 20, { otId = 777 })
eq(Breeding.compatibility(pair(ditto, karpM)), 20,
  "DITTO with the same trainer's mon is PARENTS_LOW_COMPATIBILITY")
eq(Breeding.compatibility(pair(dittoOther, karpM)), 50,
  "DITTO with another trainer's mon is PARENTS_MED_COMPATIBILITY")
eq(Breeding.compatibility(pair(ditto, dittoOther)), 0, "two DITTO cannot breed")
local mewtwo = makeMon(MEWTWO, 70, { otId = 4242 })
eq(Breeding.compatibility(pair(mewtwo, karpF)), 0,
  "EGG_GROUP_UNDISCOVERED cannot breed")
local magnemite = makeMon(MAGNEMITE, 20, { otId = 777 })
local geodude = makeMon(GEODUDE, 20, { female = true, otId = 4242 })
eq(Pokemon.gender(MAGNEMITE, magnemite.personality), "U", "MAGNEMITE is genderless")
eq(Breeding.eggGroups(MAGNEMITE)[1], Breeding.eggGroups(GEODUDE)[1],
  "MAGNEMITE and GEODUDE share an egg group")
eq(Breeding.compatibility(pair(magnemite, geodude)), 0,
  "a genderless parent cannot breed even with a shared egg group")
eq(Breeding.compatibility(pair(karpF, makeMon(PIDGEY, 5, { female = false, otId = 777 }))), 0,
  "no shared egg group is PARENTS_INCOMPATIBLE")

print("[test] 3. GetEggSpecies walks back up the evolution chain")
eq(Breeding.eggSpecies(GYARADOS), MAGIKARP, "a GYARADOS lays a MAGIKARP")
eq(Breeding.eggSpecies(PIDGEOT), PIDGEY, "a PIDGEOT lays a PIDGEY")
eq(Breeding.eggSpecies(MAGIKARP), MAGIKARP, "a base form lays itself")
eq(Breeding.eggSpecies(3), BULBASAUR, "a VENUSAUR lays a BULBASAUR")

print("[test] 4. InheritIVs takes three IVs from the two parents")
local function allIvs(value)
  return { hp = value, atk = value, def = value, spe = value, spa = value, spd = value }
end
Rng.SeedRng(0x1234)
for round = 1, 25 do
  local mom = { species = MAGIKARP, ivs = allIvs(31) }
  local dad = { species = MAGIKARP, ivs = allIvs(30) }
  local egg = { species = MAGIKARP, ivs = allIvs(0) }
  local selected, whichParent = Breeding.inheritIVs(egg, pair(mom, dad))
  local inherited, seen = 0, {}
  for _, key in ipairs(Breeding.IV_KEYS) do
    if egg.ivs[key] ~= 0 then
      inherited = inherited + 1
      check(egg.ivs[key] == 30 or egg.ivs[key] == 31,
        "round " .. round .. ": " .. key .. " came from a parent")
    end
  end
  if inherited ~= 3 then
    check(false, "round " .. round .. ": exactly three IVs inherited, got " .. inherited)
  end
  for _, index in ipairs(selected) do
    check(not seen[index], "round " .. round .. ": no stat is picked twice")
    seen[index] = true
  end
  for _, slot in ipairs(whichParent) do
    check(slot == 1 or slot == 2, "round " .. round .. ": the parent slot is one of the two")
  end
end
check(true, "25 rounds of InheritIVs each took three distinct stats from a parent")

print("[test] 5. BuildEggMoveset: the father's egg moves, TMs and shared level-up moves")
local bulbaEggMoves = Pokemon.eggMoves(BULBASAUR) or {}
check(#bulbaEggMoves > 0, "BULBASAUR has egg moves in the cache")
local eggMove = bulbaEggMoves[1]
local mother = makeMon(BULBASAUR, 20, { female = true, otId = 4242 })
local father = makeMon(BULBASAUR, 20, { female = false, otId = 777 })
father.moves = { eggMove, 33, 45, 22 }
father.pp = { 10, 35, 40, 15 }
father.maxPp = { 10, 35, 40, 15 }
local hatchling = makeMon(BULBASAUR, 5)
Breeding.buildEggMoveset(hatchling, father, mother)
check(Pokemon.knowsMove(hatchling, eggMove),
  "the egg learned the father's egg move " .. tostring(eggMove))

local tmMove = nil
for machine = 0, 57 do
  local move = Pokemon.moveFromTmItem(289 + machine)
  if move and Pokemon.canLearnTmIndex(BULBASAUR, machine) and move ~= eggMove then
    tmMove = move
    break
  end
end
check(tmMove ~= nil, "BULBASAUR can learn at least one TM move")
local tmChild = makeMon(BULBASAUR, 5)
local tmFather = makeMon(BULBASAUR, 20, { female = false })
tmFather.moves = { tmMove }
tmFather.pp = { 10 }
tmFather.maxPp = { 10 }
Breeding.buildEggMoveset(tmChild, tmFather, mother)
check(Pokemon.knowsMove(tmChild, tmMove),
  "the egg learned the father's TM move " .. tostring(tmMove))

local levelUpMove = nil
for _, entry in ipairs(Pokemon.learnset(BULBASAUR)) do
  local level = entry[1] or entry.level or 0
  local move = tonumber(entry[2] or entry.move) or 0
  if level > 5 and move > 0 then
    levelUpMove = move
    break
  end
end
check(levelUpMove ~= nil, "BULBASAUR learns something above level 5")
local sharedChild = makeMon(BULBASAUR, 5)
local sharedFather = makeMon(BULBASAUR, 20, { female = false })
local sharedMother = makeMon(BULBASAUR, 20, { female = true })
sharedFather.moves = { levelUpMove }
sharedFather.pp = { 10 }
sharedFather.maxPp = { 10 }
sharedMother.moves = { levelUpMove }
sharedMother.pp = { 10 }
sharedMother.maxPp = { 10 }
check(not Pokemon.knowsMove(sharedChild, levelUpMove),
  "a level 5 BULBASAUR does not know it yet")
Breeding.buildEggMoveset(sharedChild, sharedFather, sharedMother)
check(Pokemon.knowsMove(sharedChild, levelUpMove),
  "both parents knowing a level-up move passes it down")
local loneChild = makeMon(BULBASAUR, 5)
Breeding.buildEggMoveset(loneChild, sharedFather, mother)
check(not Pokemon.knowsMove(loneChild, levelUpMove),
  "the father alone does not pass a plain level-up move down")

print("[test] 6. the egg trigger fires on the 255th banked step, and only when compatible")
local function boardPair(a, b)
  session.modData = nil
  session.daycare = nil
  session.route5Daycare = nil
  session.party = { a, b }
  local dc = Daycare.stateOf(session)
  Daycare.deposit(session, 1)
  Daycare.deposit(session, 1)
  return dc
end

local incompatible = boardPair(makeMon(MAGIKARP, 5, { female = false, otId = 4242 }),
  makeMon(MAGIKARP, 5, { female = false, otId = 777 }))
eq(Breeding.compatibility(incompatible), 0, "two male MAGIKARP were boarded")
for _ = 1, 256 * 3 do StepEvents.onStepTaken(session, nil) end
check(not Daycare.isEggPending(incompatible),
  "three full step counters produced no egg from an incompatible pair")

local dc = boardPair(makeMon(MAGIKARP, 5, { female = true, otId = 4242 }),
  makeMon(MAGIKARP, 5, { female = false, otId = 777 }))
eq(Breeding.compatibility(dc), 70, "a MAGIKARP pair from two trainers was boarded")
Rng.SeedRng(0x2468)
local walked, flipped = 0, nil
while walked < 256 * 12 and not flipped do
  StepEvents.onStepTaken(session, nil)
  walked = walked + 1
  if Daycare.isEggPending(dc) then flipped = walked end
end
check(flipped ~= nil, "the pair produced an egg within twelve step counters")
eq(flipped and (flipped % 256), 255,
  "the egg was triggered on a step where (mons[1].steps & 0xFF) == 0xFF")
check((tonumber(dc.offspringPersonality) or 0) >= 1
  and dc.offspringPersonality <= 0xFFFE,
  "offspringPersonality is Random() % 0xFFFE + 1, got " .. tostring(dc.offspringPersonality))
check(Flags.getFlag(store, nil, Breeding.FLAG_PENDING_DAYCARE_EGG),
  "FLAG_PENDING_DAYCARE_EGG is set")
local _, state = Natives.special({ specialVars = {} }, Std.SPECIAL.GetDaycareState, nil)
eq(state, 1, "GetDaycareState is DAYCARE_EGG_WAITING")

print("[test] 7. the pending egg rides the save")
local Schema = require("src.core.game3.save_schema_firered")
local pending = dc.offspringPersonality
local saved = Schema.toSaveTable(session)
local reloaded = Schema.fromSaveTable(saved)
eq(Daycare.stateOf(reloaded).offspringPersonality, pending,
  "offspringPersonality came back from the save")

print("[test] 8. GiveEggFromDaycare hands over a real egg")
session.party = {}
session.dex = { seen = {}, owned = {} }
local ctx = { specialVars = {}, stringVars = {} }
Natives.special(ctx, Std.SPECIAL.GiveEggFromDaycare, nil)
local egg = session.party[1]
check(egg ~= nil, "the egg landed in the party")
eq(egg and egg.species, MAGIKARP, "two MAGIKARP make a MAGIKARP egg")
check(egg and egg.isEgg == true, "it is flagged as an egg")
eq(egg and egg.level, 5, "eggs are created at EGG_HATCH_LEVEL")
eq(egg and egg.metLevel, 0, "met level 0")
local karpCycles = tonumber(Pokemon.speciesMeta(MAGIKARP).eggCycles)
eq(karpCycles, 5, "MAGIKARP hatches in five cycles per the ROM")
eq(egg and egg.friendship, karpCycles,
  "the hatch counter is the species' eggCycles, not its base friendship")
check(egg and egg.friendship ~= tonumber(Pokemon.speciesMeta(MAGIKARP).friendship),
  "and that is not the base friendship value")
eq(Daycare.isEggPending(dc), false, "RemoveEggFromDayCare cleared the pending egg")
eq(dc.stepCounter, 0, "and reset the step counter")
eq(Daycare.count(dc), 2, "both parents are still boarded")
-- pokefirered/src/daycare.c:1657 GetSetPokedexFlag belongs to AddHatchedMonToParty
check(not session.dex.seen[MAGIKARP], "the unhatched EGG did not mark its species seen")
check(not session.dex.owned[MAGIKARP], "nor caught")

print("[test] 9. the egg counts down its cycles and hatches through the step path")
StepEvents.flush()
local before = egg.friendship
-- pokefirered/src/daycare.c:1157 ++daycare->stepCounter == 255
for _ = 1, 254 do StepEvents.onStepTaken(session, nil) end
eq(egg.friendship, before, "254 steps after the hand-off spend no cycle")
StepEvents.onStepTaken(session, nil)
eq(dc.stepCounter, 255, "the 255th step is the check step")
eq(egg.friendship, before - 1, "and it burns one egg cycle")
local walkedToHatch, hatched = 255, false
for _ = 1, 256 * (karpCycles + 1) do
  StepEvents.onStepTaken(session, nil)
  walkedToHatch = walkedToHatch + 1
  for _, event in ipairs(StepEvents._queue) do
    if event.type == "egg_hatch" and event.mon == egg then hatched = true end
  end
  if hatched then break end
end
check(hatched, "the egg queued its hatch event")
eq(egg.friendship, 0, "with its cycles spent")
-- pokefirered/src/daycare.c:976 RemoveEggFromDayCare zeroes stepCounter
eq(walkedToHatch, 255 + karpCycles * 256,
  "the hand-off reset the cadence, so the cart's 255 + cycles * 256 steps hatch it")

print("[test] 10. AddHatchedMonToParty makes it a real POKeMON")
Breeding.hatchMon(session, egg)
eq(egg.isEgg, false, "it is no longer an egg")
eq(egg.level, 5, "it hatches at level 5")
eq(egg.friendship, 120, "with friendship 120")
eq(egg.nickname, "", "the EGG nickname is gone")
eq(egg.name, Pokemon.name(MAGIKARP), "and it is called by its species name")
check(session.dex.seen[MAGIKARP], "the hatch registered it as seen")
check(session.dex.owned[MAGIKARP], "and as caught")
check((tonumber(egg.maxHp) or 0) > 0, "its stats were calculated")

finish()
