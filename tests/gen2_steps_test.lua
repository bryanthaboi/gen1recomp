-- CountStep (engine/overworld/events.asm) -- the per-step event chain.
-- ROM-free: `luajit tests/gen2_steps_test.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 steps")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

local StepEvents = require("src.world.gen2.StepEvents")
local Breeding = require("src.core.gen2.Breeding")
local Happiness = require("src.core.gen2.Happiness")
local Phone = require("src.core.gen2.Phone")
require("tests.fixtures.gen2_phone_events").install()

local function mon(opts)
  opts = opts or {}
  return {
    species = opts.species or "CHIKORITA",
    name = opts.name or "CHIKORITA",
    hp = opts.hp or 20,
    maxHp = opts.maxHp or 20,
    status = opts.status,
    happiness = opts.happiness or 70,
    level = opts.level or 5,
  }
end

local function newSave(opts)
  opts = opts or {}
  return { party = opts.party or { mon() }, phone = {} }
end

-- ---- DoPoisonStep ---------------------------------------------------------
-- One HP off every poisoned mon that is still standing.  A mon that runs out
-- has its status CLEARED on the way down, so a party wiped by poison walks into
-- the Center with nothing left to cure.
do
  local party = {
    mon({ hp = 5, status = "psn" }),
    mon({ hp = 1, status = "psn" }),
    mon({ hp = 9 }),
    mon({ hp = 0, status = "psn" }),
  }
  local event = StepEvents.poisonStep(party)
  eq(party[1].hp, 4, "a poisoned mon loses one HP")
  eq(party[2].hp, 0, "and one on its last point drops")
  check(party[2].status == nil, "with its status cleared as it goes")
  eq(party[3].hp, 9, "an unpoisoned mon is untouched")
  eq(party[4].hp, 0, "and an already-fainted one is skipped, not decremented")
  eq(event.kind, "poisonFaint",
    "one faint anywhere outranks the rest (wPoisonStepFlagSum and %10 first)")
  eq(event.fainted[1], 2, "and names the slot that dropped")
  check(event.blocks, "the faint arm sets carry, so no wild roll that step")
end

do
  local party = { mon({ hp = 5, status = "psn" }) }
  local event = StepEvents.poisonStep(party)
  eq(event.kind, "poisonHurt", "damage with no faint is the .PlayPoisonSFX arm")
  check(not event.blocks,
    "which ends `xor a`: the step still counts and the grass still rolls")
  check(StepEvents.poisonStep({}) == nil, "an empty party is no event at all")
  check(StepEvents.poisonStep({ mon() }) == nil, "and a clean party is none")
end

-- CheckPlayerPartyForFitMon.  An egg is not a fit mon.
do
  check(StepEvents.whitedOut({ mon({ hp = 0 }) }), "no HP left is a whiteout")
  check(not StepEvents.whitedOut({ mon({ hp = 1 }) }), "one point is not")
  check(StepEvents.whitedOut({ mon({ hp = 0 }), { isEgg = true, hp = 0 } }),
    "and an egg does not count as a fighter")
end

-- ---- DoRepelStep ----------------------------------------------------------
-- `dec a / ret nz`: the wear-off lands on the step that reaches zero, and that
-- step is not counted.
do
  local save = newSave()
  save.repelSteps = 2
  check(not StepEvents.repelStep(save), "a repel with steps left is quiet")
  eq(save.repelSteps, 1, "and ticks down")
  check(StepEvents.repelStep(save), "the step that reaches zero wears off")
  check(not StepEvents.repelStep(save), "and it only fires once")
end

-- ---- DoBikeStep -----------------------------------------------------------
do
  local save = newSave()
  save.bikeShopCall = true
  save.bikeStep = 0
  check(not StepEvents.bikeStep(save, { playerState = "normal" }),
    "on foot the counter does not even move")
  eq(save.bikeStep, 0, "literally does not move")
  check(not StepEvents.bikeStep(save, { playerState = "bike",
    phoneService = false }), "and a map with no service is refused")
  save.bikeStep = StepEvents.BIKE_CALL_STEPS - 2
  check(not StepEvents.bikeStep(save, { playerState = "bike" }),
    "1022 steps is not yet 1024")
  check(StepEvents.bikeStep(save, { playerState = "bike" }),
    "the 1024th queues the call (`cp HIGH(1024)` on the counter's high byte)")
  eq(Phone.specialCallVar(save), Phone.SPECIALCALL.SPECIALCALL_BIKESHOP,
    "as SPECIALCALL_BIKESHOP")
  check(save.bikeShopCall == false, "and clears the flag that asked for it")

  -- "If a call has already been queued, don't overwrite that call."
  local busy = newSave()
  busy.bikeShopCall = true
  busy.bikeStep = StepEvents.BIKE_CALL_STEPS
  Phone.queueSpecialCall(busy, Phone.SPECIALCALL.SPECIALCALL_SSTICKET)
  check(not StepEvents.bikeStep(busy, { playerState = "bike" }),
    "a call already queued is not overwritten")
  eq(Phone.specialCallVar(busy), Phone.SPECIALCALL.SPECIALCALL_SSTICKET,
    "the S.S. Ticket call survives")

  -- The counter saturates rather than wrapping (`cp 255` on both bytes).
  local full = newSave()
  full.bikeShopCall = true
  full.bikeStep = StepEvents.BIKE_STEP_MAX
  StepEvents.bikeStep(full, { playerState = "bike" })
  eq(full.bikeStep, StepEvents.BIKE_STEP_MAX, "and stops at $ffff")

  -- The flag the Goldenrod clerk actually writes: `setflag
  -- ENGINE_BIKE_SHOP_CALL_ENABLED` lands on save.engineFlags, and DoBikeStep
  -- reads it there rather than waiting for a field nothing sets.
  local Bike = require("src.world.gen2.Bike")
  local clerk = newSave()
  clerk.engineFlags = {}
  clerk.bikeStep = StepEvents.BIKE_CALL_STEPS
  check(not StepEvents.bikeStep(clerk, { playerState = "bike" }),
    "with the clerk's flag clear there is no call to make")
  clerk.engineFlags[Bike.ENGINE_BIKE_SHOP_CALL_ENABLED] = true
  check(StepEvents.bikeStep(clerk, { playerState = "bike" }),
    "and once the clerk sets it, the call is queued")
  check(clerk.engineFlags[Bike.ENGINE_BIKE_SHOP_CALL_ENABLED] == nil,
    "`res STATUSFLAGS2_BIKE_SHOP_CALL_F`: one call, ever")
end

-- ---- CountStep, the whole block ------------------------------------------
do
  local save = newSave()
  local event, counted = StepEvents.count(save, {})
  check(event == nil, "an ordinary footfall produces no player event")
  check(counted, "and is counted")
  eq(save.stepCount, 1, "wStepCount moved")
  eq(save.poisonStepCount, 1, "and so did wPoisonStepCount")
end

-- Neither a special call nor a repel wearing off counts the step.
do
  local save = newSave()
  Phone.queueSpecialCall(save, Phone.SPECIALCALL.SPECIALCALL_SSTICKET)
  local event, counted = StepEvents.count(save, { phone = {} })
  eq(event.kind, "phoneCall", "a queued special call is the first thing checked")
  check(not counted, "and the step is NOT counted")
  eq(save.stepCount or 0, 0, "wStepCount is untouched")
  check(event.blocks, "it queues a player event, so no wild roll")
end

do
  local save = newSave()
  save.repelSteps = 1
  local event, counted = StepEvents.count(save, {})
  eq(event.kind, "repel", "a repel wearing off is the second")
  check(not counted, "and that step is not counted either")
  eq(save.stepCount or 0, 0, "so the last repel step never ticks an egg")
end

-- StepHappiness is the wStepCount WRAP, and its own toggle halves it again:
-- 512 footfalls a point, not 256.
do
  local save = newSave({ party = { mon({ happiness = 100 }) } })
  for _ = 1, 256 do StepEvents.count(save, {}) end
  eq(save.stepCount, 0, "256 steps wrap wStepCount")
  eq(save.party[1].happiness, 100,
    "and the first wrap only flips StepHappiness' own toggle")
  for _ = 1, 256 do StepEvents.count(save, {}) end
  eq(save.party[1].happiness, 101, "the SECOND wrap is what pays the point")
  eq(Happiness.stepsToGain(save), 512, "and the next one is 512 away again")
end

-- DoEggStep is 128 steps offset from the happiness wrap, and a hatch skips the
-- rest of the block.
do
  local egg = { isEgg = true, species = "TOGEPI", eggSteps = 1 }
  local save = newSave({ party = { mon(), egg } })
  local event
  for _ = 1, Breeding.EGG_STEP_PHASE do
    event = StepEvents.count(save, {})
  end
  eq(save.stepCount, Breeding.EGG_STEP_PHASE, "the tick lands at $80")
  eq(egg.eggSteps, 0, "which spends the last cycle")
  eq(event.kind, "hatch", "and answers PLAYEREVENT_HATCH")
  check(event.blocks, "which stops the step: no wild battle on a hatch")
end

do
  -- Nothing happens on any other step of the cycle.
  local egg = { isEgg = true, species = "TOGEPI", eggSteps = 2 }
  local save = newSave({ party = { egg } })
  for _ = 1, Breeding.EGG_STEP_PHASE - 1 do StepEvents.count(save, {}) end
  eq(egg.eggSteps, 2, "127 steps do not touch the counter")
end

-- Poison fires every fourth step, and the counter is reset rather than masked.
do
  local poisoned = mon({ hp = 10, status = "psn" })
  local save = newSave({ party = { poisoned } })
  for _ = 1, 3 do StepEvents.count(save, {}) end
  eq(poisoned.hp, 10, "three steps do no damage")
  local event = StepEvents.count(save, {})
  eq(poisoned.hp, 9, "the fourth does one point")
  eq(event.kind, "poisonHurt", "and reports it")
  eq(save.poisonStepCount, 0, "with the counter reset, not wrapped")
  for _ = 1, 4 do StepEvents.count(save, {}) end
  eq(poisoned.hp, 8, "and again four steps later")
end

-- The whiteout answer rides on the event so the caller does not have to ask.
do
  local dying = mon({ hp = 1, status = "psn" })
  local save = newSave({ party = { dying } })
  local event
  for _ = 1, 4 do event = StepEvents.count(save, {}) end
  eq(event.kind, "poisonFaint", "the last point is a faint")
  check(event.whiteout, "and with nothing else standing, a whiteout")
end

do
  local dying = mon({ hp = 1, status = "psn" })
  local save = newSave({ party = { dying, mon({ hp = 5 }) } })
  local event
  for _ = 1, 4 do event = StepEvents.count(save, {}) end
  eq(event.kind, "poisonFaint", "a faint with a healthy mon behind it")
  check(not event.whiteout, "is not a whiteout")
end

-- "Don't count steps in link communication rooms."
do
  local save = newSave()
  local event, counted = StepEvents.count(save, { linkMode = true })
  check(event == nil and not counted, "a link room counts nothing")
  eq(save.stepCount or 0, 0, "and moves no counter")
end

-- The battle writes "poison"/"toxic" (Battle.STATUS_EFFECTS); both spellings
-- must register as PSN out here or bad poison never hurts on the overworld.
do
  local party = {
    mon({ hp = 5, status = "toxic" }),
    mon({ hp = 5, status = "poison" }),
  }
  local event = StepEvents.poisonStep(party)
  eq(party[1].hp, 4, "a badly poisoned mon loses one HP on the step")
  eq(party[2].hp, 4, "alongside the plain poison spelling")
  eq(event.kind, "poisonHurt", "and the hurt arm fires for both")
end

S.finish()
