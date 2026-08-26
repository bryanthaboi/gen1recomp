-- Gen 2 friendship.
--
-- src/battle/gen2/Mon.lua has carried a `happiness` field since the party
-- struct was ported and src/core/gen2/Evolution.lua reads it, but until this
-- module existed nothing ever MOVED it: every mon sat on BASE_HAPPINESS
-- forever, which made EVOLVE_HAPPINESS unreachable and the Goldenrod
-- friendship rater a constant.
--
-- Two separate mechanisms, both from the cart:
--
--   ChangeHappiness (engine/events/happiness_egg.asm) applies one of the
--   eighteen HAPPINESS_* events to one party mon.  The step it applies is NOT
--   fixed: HappinessChanges (data/events/happiness_changes.asm) is a
--   `table_width 3` block whose three columns are "happiness < 100",
--   "happiness < 200", and "otherwise", so a mon that already likes you gains
--   less and (for the bitter herbs and a poison faint) loses MORE.  That tier
--   is read off the value BEFORE the change.
--
--   StepHappiness (engine/events/happiness_egg.asm) raises the whole party by
--   one point, and it is called only when wStepCount wraps -- and then only on
--   every OTHER call, because it keeps its own wHappinessStepCount toggle.
--   The visible period is therefore 512 footfalls, not 256.
--
-- Both routines refuse to touch an EGG: ChangeHappiness `cp EGG / ret z` on
-- wPartySpecies before it even finds the byte, and StepHappiness's loop skips
-- the slot.  An egg's "happiness" byte is its remaining hatch cycles
-- (engine/pokemon/move_mon.asm writes wBaseEggSteps there), so incrementing it
-- would hand the player a Togepi 512 steps early.  The port keeps the two
-- apart on `mon.eggSteps` (see src/core/gen2/Breeding.lua), and this module
-- still honours the egg gate so the ORDER of events matches the cart.

local Runtime = require("src.mods.Runtime")

local Happiness = {}

-- happiness.changed, one of the handful of names Gen 2 invents because Gen 1
-- has no friendship byte at all (docs/mod-api-gen2-compat.md, "New in Gen 2").
-- Raised from the two routines that MOVE the byte and from nowhere else, so a
-- mod that mirrors friendship into its own UI sees every point:
--
--   mon       the party record whose byte moved
--   event     the HAPPINESS_* name/index the caller passed, or nil for a step
--   reason    "event" for ChangeHappiness, "step" for StepHappiness
--   delta     the signed step actually applied, AFTER the byte's own clamps
--   from, to  the value either side of the change
--
-- `delta` is `to - from` rather than the table's column, because the $ff and 0
-- carry clamps are part of what the cart applied: a mon at 254 gaining "5"
-- gained 1.
local function emitChanged(mon, event, reason, from, to)
  if not Runtime.wants("happiness.changed") then return end
  Runtime.emit("happiness.changed", {
    mon = mon, event = event, reason = reason,
    delta = to - from, from = from, to = to,
  })
end

-- constants/pokemon_data_constants.asm, "significant happiness values".
Happiness.BASE = 70
Happiness.FRIEND_BALL = 200
Happiness.TO_EVOLVE = 220
Happiness.THRESHOLD_1 = 100
Happiness.THRESHOLD_2 = 200
-- The byte's own ceiling; the floor is 0.
Happiness.MAX = 255

-- The HAPPINESS_* enum.  Its `const_def 1` makes it ONE based, so these
-- indices line up with a 1-based Lua array without an offset -- the shift that
-- would otherwise drop the last row (HAPPINESS_GROOMING) to nil.
Happiness.EVENT = {
  GAINLEVEL = 1,          -- 01
  USEDITEM = 2,           -- 02  a vitamin
  USEDXITEM = 3,          -- 03  X ATTACK / X DEFEND / X SPEED / X SPECIAL
  GYMBATTLE = 4,          -- 04
  LEARNMOVE = 5,          -- 05  a TM, not an HM
  FAINTED = 6,            -- 06
  POISONFAINT = 7,        -- 07
  BEATENBYSTRONGFOE = 8,  -- 08
  OLDERCUT1 = 9,          -- 09
  OLDERCUT2 = 10,         -- 0a
  OLDERCUT3 = 11,         -- 0b
  YOUNGCUT1 = 12,         -- 0c
  YOUNGCUT2 = 13,         -- 0d
  YOUNGCUT3 = 14,         -- 0e
  BITTERPOWDER = 15,      -- 0f  HEAL POWDER / ENERGYPOWDER
  ENERGYROOT = 16,        -- 10
  REVIVALHERB = 17,       -- 11
  GROOMING = 18,          -- 12
  -- Crystal only; Gold's enum stops at GROOMING
  -- (pokegold constants/pokemon_data_constants.asm:205).
  GAINLEVELATHOME = 19,   -- 13
}
Happiness.NUM_EVENTS = 19

-- data/events/happiness_changes.asm, transcribed row for row.  The three
-- columns are the three tiers below, in order.
Happiness.CHANGES = {
  {  5,  3,  2 }, -- 01 Gained a level
  {  5,  3,  2 }, -- 02 Vitamin
  {  1,  1,  0 }, -- 03 X Item
  {  3,  2,  1 }, -- 04 Battled a Gym Leader
  {  1,  1,  0 }, -- 05 Learned a move
  { -1, -1, -1 }, -- 06 Lost to an enemy
  { -5, -5, -10 }, -- 07 Fainted due to poison
  { -5, -5, -10 }, -- 08 Lost to a much stronger enemy
  {  1,  1,  1 }, -- 09 Haircut (older brother) 1
  {  3,  3,  1 }, -- 0a Haircut (older brother) 2
  {  5,  5,  2 }, -- 0b Haircut (older brother) 3
  {  1,  1,  1 }, -- 0c Haircut (younger brother) 1
  {  3,  3,  1 }, -- 0d Haircut (younger brother) 2
  { 10, 10,  4 }, -- 0e Haircut (younger brother) 3
  { -5, -5, -10 }, -- 0f Used Heal Powder or Energypowder (bitter)
  { -10, -10, -15 }, -- 10 Used Energy Root (bitter)
  { -15, -15, -20 }, -- 11 Used Revival Herb (bitter)
  {  3,  3,  1 }, -- 12 Grooming
  { 10,  6,  4 }, -- 13 Gained a level where it was caught (Crystal)
}

-- Which of HappinessChanges' three columns a CURRENT value reads.  The cart
-- builds this as `e`: 0, then +1 once the value is >= 100, then +1 again once
-- it is >= 200.  Returned 1-based to index the rows above.
function Happiness.tier(value)
  value = value or 0
  if value < Happiness.THRESHOLD_1 then return 1 end
  if value < Happiness.THRESHOLD_2 then return 2 end
  return 3
end

-- Resolve an event to its index.  Callers may pass the name ("GAINLEVEL"),
-- the full constant ("HAPPINESS_GAINLEVEL") or the raw number, so a hand
-- ported script and an extracted one can both say what they mean.
function Happiness.eventIndex(event)
  if type(event) == "number" then
    if event >= 1 and event <= Happiness.NUM_EVENTS then return event end
    return nil
  end
  if type(event) ~= "string" then return nil end
  local name = event:match("^HAPPINESS_(.+)$") or event
  return Happiness.EVENT[name]
end

-- The signed step an event applies at a current value, or nil for an event
-- this table does not know.  Split out so a test can assert the tier
-- boundaries without going through a mon.
function Happiness.delta(event, current)
  local index = Happiness.eventIndex(event)
  if not index then return nil end
  local row = Happiness.CHANGES[index]
  if not row then return nil end
  return row[Happiness.tier(current)]
end

-- An egg is skipped, exactly as ChangeHappiness's `cp EGG / ret z` does.
-- Matches src/core/gen2/Breeding.lua's isEgg without requiring it, so this
-- module stays loadable on its own.
local function isEgg(mon)
  return type(mon) == "table" and mon.isEgg == true
end

-- ChangeHappiness itself.  Returns the new value, or nil when nothing moved
-- (no mon, an egg, or an event the table does not carry).
--
-- The clamps are the cart's carry checks, not a max/min bolted on: a positive
-- step that overflows the byte lands on $ff (`ld a, -1`), and a negative one
-- that underflows lands on 0 (`xor a`).  Both edges are reachable in normal
-- play -- 255 from walking, 0 from a poison faint at low friendship -- so they
-- are load bearing rather than defensive.
function Happiness.change(mon, event)
  if type(mon) ~= "table" or isEgg(mon) then return nil end
  local current = mon.happiness or 0
  local delta = Happiness.delta(event, current)
  if not delta then return nil end
  local value = current + delta
  if value > Happiness.MAX then value = Happiness.MAX end
  if value < 0 then value = 0 end
  mon.happiness = value
  emitChanged(mon, event, "event", current, value)
  return value
end

-- LevelUpHappinessMod: the caught location masked with CAUGHT_LOCATION_MASK
-- against the current landmark -- engine/pokemon/level_up_happiness.asm:1-20.
function Happiness.levelUpEvent(mon, landmark)
  local caught = type(mon) == "table" and tonumber(mon.caughtLocation) or nil
  landmark = tonumber(landmark)
  if not (caught and landmark) then return "GAINLEVEL" end
  if math.floor(caught) % 0x80 ~= math.floor(landmark) % 0x80 then
    return "GAINLEVEL"
  end
  return "GAINLEVELATHOME"
end

-- The `callfar ChangeHappiness` that follows -- level_up_happiness.asm:19.
function Happiness.levelUp(mon, landmark)
  return Happiness.change(mon, Happiness.levelUpEvent(mon, landmark))
end

-- The same event across a party, which is how the Gym Leader award is written
-- out longhand in engine/battle/core.asm InitEnemyTrainer:
--
--   ld a, MON_HP / call GetPartyParamLocation
--   ld a, [hli] / or [hl] / jr z, .skipfaintedmon
--
-- so a mon that is already down does not earn the leader's approval.
--
-- The OTHER party-wide site is not this loop and must not use it:
-- engine/events/poisonstep.asm walks wPoisonStepPartyFlags and awards
-- HAPPINESS_POISONFAINT to exactly the mons that just dropped, every one of
-- which is at zero HP.  That caller wants Happiness.change per flagged slot,
-- or this with opts.includeFainted.
function Happiness.changeParty(party, event, opts)
  opts = opts or {}
  local touched = 0
  for _, mon in ipairs(party or {}) do
    local alive = (mon.hp or 0) > 0 or opts.includeFainted
    if alive and Happiness.change(mon, event) then touched = touched + 1 end
  end
  return touched
end

-- StepHappiness.  Its own toggle: `inc a / and 1 / ld [hl], a / ret nz` alternates
-- 1, 0, 1, 0 and only falls through on the 0, so the party gains a point every
-- SECOND time this is called.  The `inc [hl] / jr nz / ld [hl], $ff` on each
-- mon is why 255 sticks rather than wrapping to 0.
--
-- Returns true on the calls that actually raised the party.
function Happiness.stepCycle(save)
  if type(save) ~= "table" then return false end
  save.happinessStepCount = ((save.happinessStepCount or 0) + 1) % 2
  if save.happinessStepCount ~= 0 then return false end
  for _, mon in ipairs(save.party or {}) do
    if not isEgg(mon) then
      local from = mon.happiness or 0
      mon.happiness = math.min(Happiness.MAX, from + 1)
      -- A mon already sitting on $ff is walked over by `inc [hl] / jr nz`
      -- writing $ff back, so nothing moved and there is nothing to report.
      if mon.happiness ~= from then
        emitChanged(mon, nil, "step", from, mon.happiness)
      end
    end
  end
  return true
end

-- One overworld footfall, from engine/overworld/events.asm's step block:
--
--   ld hl, wStepCount / inc [hl] / jr nz, .skip_happiness / farcall StepHappiness
--
-- `inc [hl]` sets z only on the wrap, so StepHappiness runs on the step that
-- takes wStepCount from 255 back to 0 -- one call every 256 steps, and a
-- party point every 512.  src/core/gen2/Breeding.lua owns that same counter
-- (`save.stepCount`, advanced by Breeding.step), so this must be called AFTER
-- Breeding.step on the same footfall or it will read the previous step's
-- value.
function Happiness.step(save)
  if type(save) ~= "table" then return false end
  if (save.stepCount or 0) ~= 0 then return false end
  return Happiness.stepCycle(save)
end

-- How many footfalls are still owed before the party next gains a point.  For
-- a driver or a test that wants to walk exactly far enough rather than 512
-- times blind.
function Happiness.stepsToGain(save)
  if type(save) ~= "table" then return nil end
  local cycle = 256
  local toWrap = (cycle - (save.stepCount or 0)) % cycle
  if toWrap == 0 then toWrap = cycle end
  -- A toggle sitting at 1 means the NEXT wrap is the one that pays out.
  if (save.happinessStepCount or 0) == 1 then return toWrap end
  return toWrap + cycle
end

-- The three answers HappinessCheckScript (engine/events/std_scripts.asm) picks
-- between off GetFirstPokemonHappiness: `ifless 50` and `ifless 150`, so the
-- boundaries are inclusive at the top of each band.
Happiness.RATER_UNHAPPY = 50
Happiness.RATER_KINDA = 150

function Happiness.raterBand(value)
  value = value or 0
  if value < Happiness.RATER_UNHAPPY then return "unhappy" end
  if value < Happiness.RATER_KINDA then return "kinda" end
  return "happy" -- HappinessText3, the one that means "it adores you"
end

-- GetFirstPokemonHappiness: the first party slot that is NOT an egg, which is
-- what the rater and the Goldenrod NPCs read.  Returns the mon and its slot.
function Happiness.firstMon(party)
  for index, mon in ipairs(party or {}) do
    if not isEgg(mon) then return mon, index end
  end
  return nil, nil
end

-- What a mon starts life on.  There is no ChangeHappiness event for a TRADE in
-- Gen 2 (that arrives in Gen 3): a traded or gifted mon simply comes in
-- through the struct initialisers in engine/pokemon/move_mon.asm, every one of
-- which writes BASE_HAPPINESS.  The two exceptions are a FRIEND_BALL capture
-- (engine/items/item_effects.asm writes FRIEND_BALL_HAPPINESS over it, for the
-- party AND the box copy) and a hatchling, which
-- src/core/gen2/Breeding.lua sets to its own $78.
function Happiness.forNewMon(opts)
  opts = opts or {}
  if opts.ball == "FRIEND_BALL" then return Happiness.FRIEND_BALL end
  return Happiness.BASE
end

return Happiness
