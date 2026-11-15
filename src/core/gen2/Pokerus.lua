-- Pokerus: engine/events/pokerus/pokerus.asm, check_pokerus.asm and
-- apply_pokerus_tick.asm.
--
-- One byte per party slot (box_struct's PokerusStatus, macros/ram.asm), and
-- both nybbles matter:
--
--   high nybble  the strain, 0..8.  Never cleared once set.
--   low nybble   days remaining, 1..4.  Counted down by the daily tick.
--
-- So a byte reads three ways, and every routine here picks a different one:
--
--   $00        never infected.  Can catch it.
--   $34        infected: strain 3, three days left.  Spreads, doubles stat exp.
--   $30        cured: the strain stays behind as the immune marker.  Does NOT
--              spread and cannot be reinfected, but STILL doubles stat exp --
--              GiveExperiencePoints tests the whole byte (`ld a, [hl] / and a`)
--              rather than the day count, which is why a cured mon is the one
--              people train on.
--
-- Two quirks below are the cart's and are ported deliberately:
--
--   * .randomPokerusLoop can roll strain 0 (a byte whose high nybble came up
--     zero takes the `jr z, .load_pkrs` arm with a = 0), producing $01.  That
--     mon cures to $00 and is therefore infectable again.
--   * the spread walk stops on a neighbour whose byte has its low two bits
--     clear (`and $3 / ret z`).  That is meant to be "stop at a cured mon", but
--     it also stops at a four-day infection, because 4 and 8 and 12 are all
--     $3-clear.
--
-- The de novo roll is gated on ENGINE_REACHED_GOLDENROD, so a save that has not
-- walked into Goldenrod City cannot catch it at all -- the flag is set by
-- GoldenrodCity's map callback (maps/GoldenrodCity.asm), which the port runs
-- like any other.

local BugContest = require("src.core.gen2.BugContest")
local Runtime = require("src.mods.Runtime")

local EngineFlags = require("src.core.gen2.EngineFlags")
local Pokerus = EngineFlags.expose({}, { "ENGINE_REACHED_GOLDENROD" })

-- pokerus.infected, a Gen 2 invention: Gen 1 has no Pokerus byte, so there is
-- no name to share.  Raised from the two -- and only two -- writes that turn a
-- clean byte into an infected one, so a mod that wants to notice the virus
-- does not have to poll the party:
--
--   party    the party the write landed in
--   slot     the 1-based party index that caught it
--   mon      that party record, already carrying the new byte
--   strain   the high nybble, 1..8 (0 is the "cured, immune" strain)
--   days     the low nybble's countdown, 1..4 days
--   source   "spread" for .TrySpreadPokerus walking off an infected
--            neighbour, "contracted" for the 3-in-65536 de novo roll
local function emitInfected(party, slot, source)
  if not Runtime.wants("pokerus.infected") then return end
  local mon = party and party[slot]
  Runtime.emit("pokerus.infected", {
    party = party, slot = slot, mon = mon,
    strain = Pokerus.strain(mon), days = Pokerus.days(mon),
    source = source,
  })
end

-- `percent` is `* $ff / 100` (macros/data.asm), so these are 85 and 128 out of
-- 256 rather than 33 and 50 out of 100.
Pokerus.SPREAD_CHANCE = math.floor(33 * 0xff / 100) + 1
Pokerus.BACKWARD_CHANCE = math.floor(50 * 0xff / 100) + 1

-- `call Random` gives one byte; the convention is the same as
-- BugContest.random's, a function of no arguments returning 0..255, so a test
-- can pin every roll.
function Pokerus.random()
  if love and love.math and love.math.random then
    return love.math.random(0, 255)
  end
  return math.random(0, 255)
end

local function byte(random)
  return (random or Pokerus.random)()
end

-- ------------------------------------------------------------- reading a mon

function Pokerus.byteOf(mon)
  local value = tonumber(mon and mon.pokerus) or 0
  if value < 0 then return 0 end
  return math.floor(value) % 256
end

function Pokerus.strain(mon)
  return math.floor(Pokerus.byteOf(mon) / 16)
end

function Pokerus.days(mon)
  return Pokerus.byteOf(mon) % 16
end

-- An active infection: the low nybble is what _CheckPokerus and the party scan
-- in GivePokerusAndConvertBerries both test.
function Pokerus.isInfected(mon)
  return Pokerus.days(mon) ~= 0
end

-- Cured, and carrying the strain as the immune marker.  This is the dot the
-- stats screen prints beside the level (src/ui/gen2/SummaryMenu.lua).
function Pokerus.isImmune(mon)
  local value = Pokerus.byteOf(mon)
  return value ~= 0 and value % 16 == 0
end

-- GiveExperiencePoints' `ld a, MON_POKERUS / call GetPartyParamLocation /
-- ld a, [hl] / and a`: the WHOLE byte, so immune counts.
function Pokerus.doublesStatExp(mon)
  return Pokerus.byteOf(mon) ~= 0
end

-- _CheckPokerus: carry when any party member has an active infection.  The
-- CheckPokerus special and the Pokemon Center nurse both go through this.
function Pokerus.inParty(party)
  for _, mon in ipairs(party or {}) do
    if Pokerus.isInfected(mon) then return true end
  end
  return false
end

-- ------------------------------------------------------------- the daily tick

-- ApplyPokerusTick: subtract `days` from every active counter, clamped at zero,
-- leaving the strain nybble alone.  That clamp is the whole immunity mechanic:
-- a counter that reaches zero keeps its strain, and every routine that could
-- reinfect the mon tests the strain first.  Returns the slots that cured on
-- this tick.
function Pokerus.applyTick(party, days)
  local cured = {}
  days = math.max(0, math.floor(tonumber(days) or 0))
  for index, mon in ipairs(party or {}) do
    local value = Pokerus.byteOf(mon)
    local left = value % 16
    if left ~= 0 then
      left = left - days
      if left < 0 then left = 0 end
      mon.pokerus = (value - value % 16) + left
      if left == 0 then cured[#cured + 1] = index end
    end
  end
  return cured
end

-- CheckPokerusTick (engine/overworld/time.asm), the `.do_daily` arm of the
-- player-event chain.  CalcDaysSince ADVANCES the stored day to today as it
-- reads it (`ld [hl], c ; current days`), so the tick subtracts "days since the
-- last poll" and not "days since the timer started" -- and a clock wound
-- backwards wraps into a large jump forward rather than going negative, which
-- cures a party outright.
--
-- wTimerEventStartDay is written once at new game (_InitializeStartDay) and
-- only ever by this routine after that; a save from before this landed has no
-- day stamped, so the first poll stamps today and ticks nothing.
function Pokerus.checkTick(save, now)
  if type(save) ~= "table" then return false end
  if save.pokerusStartDay == nil then
    save.pokerusStartDay = (now or BugContest.now()).day
    return false
  end
  local stamp = { day = save.pokerusStartDay }
  local since = BugContest.elapsedSince(stamp, now, "day")
  save.pokerusStartDay = stamp.day
  if since.days == 0 then return false end
  Pokerus.applyTick(save.party or {}, since.days)
  return true
end

-- ----------------------------------------------------------- catching it

-- .infectMon: the new slot takes the strain of the byte the walk last looked at
-- (register c, which is the carrier on the first step and the neighbour walked
-- over after that) and a fresh counter from that strain's low two bits:
-- `swap a / and $3 / inc a`, so 1..4 days.
local function infect(party, slot, carrier)
  local mon = party[slot]
  if not mon then return nil end
  local strainBits = carrier - carrier % 16
  local days = (math.floor(carrier / 16) % 4) + 1
  mon.pokerus = strainBits + days
  emitInfected(party, slot, "spread")
  return slot
end

-- .TrySpreadPokerus, entered with `index` at the first infected slot.  Register
-- b is the number of slots from that one to the end of the party inclusive,
-- which is how the cart knows whether there is anything left to walk to; both
-- loops keep it in that shape rather than counting slots directly.
local function spread(party, index, random)
  local count = #party
  if byte(random) >= Pokerus.SPREAD_CHANCE then return nil end
  if count == 1 then return nil end
  local b = count - index + 1
  local carrier = Pokerus.byteOf(party[index])
  local slot = index
  -- `ld a, b / cp 2 / jr c` : the last slot has nothing after it, so it always
  -- walks backwards.  Otherwise it is a coin flip.
  local forward = b >= 2 and byte(random) >= Pokerus.BACKWARD_CHANCE
  if forward then
    while true do
      slot = slot + 1
      local value = Pokerus.byteOf(party[slot])
      if value == 0 then return infect(party, slot, carrier) end
      carrier = value
      if value % 4 == 0 then return nil end
      b = b - 1
      if b == 1 then return nil end
    end
  end
  while true do
    -- `ld a, [wPartyCount] / cp b / ret z`: b back up at the party count means
    -- the walk is at slot one and there is nothing before it.
    if b == count then return nil end
    slot = slot - 1
    local value = Pokerus.byteOf(party[slot])
    if value == 0 then return infect(party, slot, carrier) end
    carrier = value
    if value % 4 == 0 then return nil end
    b = b + 1
  end
end

-- GivePokerusAndConvertBerries, the Pokerus half (the Shuckle berry half is a
-- separate routine and is not this module's).  Runs on a battle WIN, once.
--
-- The party scan comes first and it is not a formality: while ANY slot is
-- infected the whole routine becomes a spread roll, so a party with an active
-- infection can never contract a second one.  Returns the slot that changed, or
-- nil when nothing did.
--
-- opts.random pins the rolls, opts.reachedGoldenrod is
-- ENGINE_REACHED_GOLDENROD.
function Pokerus.give(party, opts)
  opts = opts or {}
  local random = opts.random
  local count = #(party or {})
  if count == 0 then return nil end
  for index, mon in ipairs(party) do
    if Pokerus.isInfected(mon) then
      return spread(party, index, random)
    end
  end
  if not opts.reachedGoldenrod then return nil end
  -- 3 in 65536: hRandomAdd must be zero and hRandomSub under 3.  One `call
  -- Random` fills both, which is two bytes off this module's roller.
  if byte(random) ~= 0 then return nil end
  if byte(random) >= 3 then return nil end
  -- `and $7 / cp b / jr nc`: reroll until the slot is inside the party.
  local slot
  repeat
    slot = byte(random) % 8
  until slot < count
  local mon = party[slot + 1]
  local value = Pokerus.byteOf(mon)
  -- `and $f0 / ret nz`: a strain in the high nybble means infected or immune,
  -- and either way this mon is done catching it.
  if value - value % 16 ~= 0 then return nil end
  -- .randomPokerusLoop samples strain and duration from ONE non-zero byte.
  local roll
  repeat
    roll = byte(random)
  until roll ~= 0
  local strain = 0
  if roll >= 16 then strain = (roll % 8) + 1 end
  mon.pokerus = strain * 16 + (strain % 4) + 1
  emitInfected(party, slot + 1, "contracted")
  return slot + 1
end

-- The call-site shape: ExitBattle runs this off the save, so the Goldenrod
-- flag comes out of the engine-flag table the scripts write
-- (src/world/gen2/World.lua setEngineFlag) rather than being passed in.
function Pokerus.giveAfterBattle(save, party, opts)
  if type(save) ~= "table" then return nil end
  opts = opts or {}
  local flags = save.engineFlags or {}
  return Pokerus.give(party or save.party or {}, {
    random = opts.random,
    reachedGoldenrod = flags[Pokerus.ENGINE_REACHED_GOLDENROD] == true,
  })
end

return Pokerus
