-- CountStep (engine/overworld/events.asm), the block that runs on every
-- overworld footfall, and the four routines it calls that had no port at all.
--
-- This is the chain the world was missing entirely: `World` kept no step count,
-- so `Happiness.step` and `Breeding.step` were written and tested and nothing
-- ever called either.  Eggs never hatched and scripted phone calls never fired,
-- both main quest.
--
-- CheckTileEvent runs it between the coord events and the wild encounter roll,
-- and a CARRY out of it means a player event is queued -- which is why a step
-- that hatches an egg or drops a poisoned mon never also starts a battle.
--
--   CountStep:
--       ret if wLinkMode                    ; not modelled: no link overworld
--       CheckSpecialPhoneCall -> c: .doscript
--       DoRepelStep           -> c: .doscript
--       inc wPoisonStepCount
--       inc wStepCount        -> z (the wrap): StepHappiness
--       wStepCount == $80   : DoEggStep -> nz: .hatch
--       DayCareStep
--       wPoisonStepCount >= 4 : reset, DoPoisonStep -> c: .doscript
--       DoBikeStep
--
-- Everything here is love-free and takes its state as arguments so the whole
-- chain is testable without a world.
local FieldMoves = require("src.world.gen2.FieldMoves")
local Breeding = require("src.core.gen2.Breeding")
local Happiness = require("src.core.gen2.Happiness")
local Phone = require("src.core.gen2.Phone")

local StepEvents = {}

-- constants/pokemon_data_constants.asm: `1 << PSN`.  The port stores a status
-- as a lowercase name on the mon; the battle writes "poison"/"toxic"
-- (Battle.STATUS_EFFECTS), older saves may carry "psn"/"tox".
local function isPoisoned(mon)
  local status = mon and mon.status
  return status == "psn" or status == "tox" or status == "poison"
      or status == "toxic"
end

-- .DamageMonIfPoisoned's two answers, kept as the cart's own bit pair so the
-- "someone fainted beats someone hurt" test below reads like `and %10`.
StepEvents.POISON_HURT = 1
StepEvents.POISON_FAINTED = 2

-- Every 4 steps (wPoisonStepCount `cp 4 / jr c`).
StepEvents.POISON_PERIOD = 4

-- DoBikeStep's threshold is `cp HIGH(1024)` on the counter's HIGH byte, so it
-- is 1024 steps and the counter saturates at $ffff rather than wrapping.
StepEvents.BIKE_CALL_STEPS = 1024
StepEvents.BIKE_STEP_MAX = 0xffff

-- DoPoisonStep.  One HP off every poisoned mon that is still standing, and the
-- mon that runs out has its status CLEARED on the way down -- so a party wiped
-- by poison walks into the Pokemon Center with no status left to cure.
--
-- The two flags are collected across the WHOLE party before either branch is
-- taken (wPoisonStepFlagSum), which is why one faint anywhere in the party
-- outranks five mons merely taking damage.
function StepEvents.poisonStep(party)
  party = party or {}
  local hurt, fainted = {}, {}
  for index, mon in ipairs(party) do
    if isPoisoned(mon) and (mon.hp or 0) > 0 then
      mon.hp = mon.hp - 1
      if mon.hp <= 0 then
        mon.hp = 0
        mon.status = nil
        fainted[#fainted + 1] = index
      else
        hurt[#hurt + 1] = index
      end
    end
  end
  if #fainted > 0 then
    return { kind = "poisonFaint", fainted = fainted, hurt = hurt, blocks = true }
  end
  if #hurt > 0 then
    -- .PlayPoisonSFX and the four-frame BG flash, then `xor a`: no carry, so
    -- the step still counts and the wild roll still happens.
    return { kind = "poisonHurt", hurt = hurt, blocks = false }
  end
  return nil
end

-- .CheckWhitedOut's tail: `predef CheckPlayerPartyForFitMon`, whose answer is
-- what decides between closing the text box and jumping to
-- OverworldWhiteoutScript.  An egg is not a fit mon (DayCare_GiveEgg zeroes its
-- HP), which Breeding.healthyCount already says out loud.
function StepEvents.whitedOut(party)
  return Breeding.healthyCount(party) == 0
end

-- DoRepelStep.  `dec a / ret nz`: the wear-off lands on the step that takes the
-- counter to zero, and that step is NOT counted -- so the last repel step never
-- ticks the egg or the day care.
function StepEvents.repelStep(save)
  local left = save.repelSteps or 0
  if left <= 0 then return false end
  save.repelSteps = left - 1
  return save.repelSteps == 0
end

-- DoBikeStep.  Four gates before the counter even moves, and then a quirk worth
-- keeping: `scf` at the end is thrown away by CountStep's `.done`, which does
-- `xor a / ret`.  So queueing the bike shop's call does NOT stop the step being
-- counted and does NOT produce a player event -- the call goes out on the NEXT
-- footfall, through CheckSpecialPhoneCall at the top of this same block.
--
-- wStatusFlags2's BIKE_SHOP_CALL bit is not a byte nobody else reads: the
-- Goldenrod bike shop clerk's own `setflag ENGINE_BIKE_SHOP_CALL_ENABLED`
-- (maps/GoldenrodBikeShop.asm) is what turns it on, and Vm's setflag lands
-- that on save.engineFlags under the ENGINE_* id.  save.bikeShopCall is kept
-- as the fallback for a save written before that was wired up, and is cleared
-- alongside the flag so the two can never disagree.
local function bikeShopCallEnabled(save)
  local flags = save.engineFlags
  if type(flags) == "table" then
    local set = flags[FieldMoves.BIKE_SHOP_CALL_FLAG]
    if set ~= nil then return set == true end
  end
  return save.bikeShopCall == true
end

function StepEvents.bikeStep(save, opts)
  opts = opts or {}
  if not bikeShopCallEnabled(save) then return false end
  if opts.playerState ~= "bike" then return false end
  if opts.phoneService == false then return false end
  local steps = math.min((save.bikeStep or 0) + 1, StepEvents.BIKE_STEP_MAX)
  save.bikeStep = steps
  if steps < StepEvents.BIKE_CALL_STEPS then return false end
  -- "If a call has already been queued, don't overwrite that call."
  if Phone.hasSpecialCall(save) then return false end
  Phone.queueSpecialCall(save, Phone.SPECIALCALL.SPECIALCALL_BIKESHOP)
  -- `res STATUSFLAGS2_BIKE_SHOP_CALL_F`: one call, ever.
  if type(save.engineFlags) == "table" then
    save.engineFlags[FieldMoves.BIKE_SHOP_CALL_FLAG] = nil
  end
  save.bikeShopCall = false
  return true
end

-- The whole block, in the cart's order.
--
-- `ctx` carries what the routines need from outside the save: `data` for the
-- day care's species lookups, `rng` for its egg roll, `phone` for
-- CheckSpecialPhoneCall's map/time context, `playerState` and `phoneService`
-- for DoBikeStep.
--
-- Returns an event table or nil, plus whether the step was COUNTED.  The
-- event's `blocks` field is CountStep's CARRY: the caller owes the matching
-- player-event script and must not roll a wild encounter on that step.  Only
-- `poisonHurt` reports an event without one -- DoPoisonStep's .PlayPoisonSFX
-- arm ends `xor a`, so a party that merely takes damage still walks into grass.
function StepEvents.count(save, ctx)
  ctx = ctx or {}
  if type(save) ~= "table" then return nil, false end
  if ctx.linkMode then return nil, false end

  -- Neither of the next two counts the step.
  local call = Phone.checkSpecialCall(save, ctx.phone)
  if call then return { kind = "phoneCall", call = call, blocks = true }, false end
  if StepEvents.repelStep(save) then
    return { kind = "repel", blocks = true }, false
  end

  save.poisonStepCount = ((save.poisonStepCount or 0) + 1) % 256

  -- Breeding.step owns wStepCount: it increments, ticks the eggs at $80 and
  -- runs DayCareStep, all in the cart's order.  StepHappiness sits between the
  -- increment and the egg tick on the cart and is called after both here, which
  -- is safe rather than sloppy: the wrap ($00) and the egg phase ($80) can
  -- never be the same step, so the two never run on the same footfall at all.
  local bred = Breeding.step(ctx.data, save, ctx.rng)
  Happiness.step(save)
  if bred == "hatch" then return { kind = "hatch", blocks = true }, true end

  if save.poisonStepCount >= StepEvents.POISON_PERIOD then
    save.poisonStepCount = 0
    local poison = StepEvents.poisonStep(save.party)
    if poison and poison.kind == "poisonFaint" then
      poison.whiteout = StepEvents.whitedOut(save.party)
      return poison, true
    end
    if poison then
      -- .PlayPoisonSFX only: no carry, so the caller plays the sound and the
      -- step carries on into the wild roll.
      StepEvents.bikeStep(save, ctx)
      return poison, true
    end
  end

  StepEvents.bikeStep(save, ctx)
  return nil, true
end

return StepEvents
