-- Per-turn status/volatile condition handling (Gen 1 semantics).
--
-- The persistent conditions live in Status.RECORDS; a battle passes its
-- merged Data.statuses so mod statuses join the same beforeMove gauntlet
-- and residual sweep.  Callers without a battle (pure-module tests) fall
-- back to the vanilla records, which is bit-identical behavior.

local romText = require("src.core.RomText")

local Status = {}

local function romLine(data, label, ...)
  return romText(data, label, nil, ...)
end

-- pokered's <USER>/<TARGET> text macros print "Enemy " before the enemy
-- mon's nickname; these records only know the raw name -- BattleState
-- splices the prefix in (prefixEnemy), same as always
local function name(battler)
  return battler.name
end

-- statuses with beforeMovePriority above this run before the engine's
-- held/disable/confusion volatiles; at or below, after (sleep 40 and
-- freeze 30 come first, paralysis 10 comes last, like the original
-- CheckPlayerStatusConditions order)
local VOLATILE_PRIORITY = 20

local function hasType(battler, wanted)
  for _, t in ipairs(battler.curTypes or {}) do
    if t == wanted then return true end
  end
  return false
end

-- shared PSN/BRN residual: 1/16 max HP, multiplied (and advanced) by the
local function damageOverTime(label)
  return function(battler, _, battle)
    local mon = battler.mon
    local base = math.max(1, math.floor(mon.stats.hp / 16))
    local dmg = base
    if battler.toxicCounter then
      dmg = base * battler.toxicCounter
      battler.toxicCounter = battler.toxicCounter + 1
    end
    mon.hp = math.max(0, mon.hp - dmg)
    return { romLine(battle and battle.data, label, name(battler)) }
  end
end

-- Labels stay plain literals on purpose: this table is built at require
-- time, before Strings.load has a catalog, so a Strings() here would
-- freeze the English.  They are already translatable through the
-- statuses registry (mod.content.statuses:patch(id, { label = ... })).
--
-- Do not add a matching hudLabel = "..." below: Status.hudLabelFor reads
-- hudLabel before label, and Registry:patch only overrides the fields a
-- mod actually passes, so a label-only translation patch would be
-- shadowed by this hudLabel forever. Nothing in this codebase gives
-- hudLabel a value different from label -- setting it here only recreates
-- that trap for no observed benefit.
--
-- The five persistent conditions as records: the beforeMove gauntlet, the
-- residual sweep, the inflict text/immunities (StatusRegistry.inflict),
-- the catch/wobble bonuses (Catching.attempt), the HUD label, and the
-- burn/paralysis stat cut (Damage.compute, TurnOrder.effectiveSpeed) all
-- read these fields, so a mod's sixth status plugs into every consumer.
Status.RECORDS = {
  SLP = {
    id = "SLP", label = "SLP",
    catchBonus = 25, shakeBonus = 10,
    beforeMovePriority = 40,
    beforeMove = function(battler, _, battle)
      battler.sleepTurns = (battler.sleepTurns or 1) - 1
      battler.mon.sleepTurns = battler.sleepTurns > 0 and battler.sleepTurns or nil
      if battler.sleepTurns <= 0 then
        battler.mon.status = nil
        -- wakes, loses the turn
        return false, { romLine(battle and battle.data, "_WokeUpText", name(battler)) }
      end
      return false, { romLine(battle and battle.data, "_FastAsleepText", name(battler)) }, false, "sleep"
    end,
    onInflict = function(battle, target, opts, display)
      target.sleepTurns = battle.rng(1, 7)
      target.mon.sleepTurns = target.sleepTurns
      return { romLine(battle.data, "_FellAsleepText", display) }
    end,
  },
  FRZ = {
    id = "FRZ", label = "FRZ",
    catchBonus = 25, shakeBonus = 10,
    beforeMovePriority = 30,
    beforeMove = function(battler, _, battle)
      return false, { romLine(battle and battle.data, "_IsFrozenText", name(battler)) }
    end,
    canInflict = function(target) return not hasType(target, "ICE") end,
    onInflict = function(battle, _, _, display)
      return { romLine(battle and battle.data, "_FrozenText", display) }
    end,
  },
  PSN = {
    id = "PSN", label = "PSN",
    catchBonus = 12, shakeBonus = 5,
    residual = damageOverTime("_HurtByPoisonText"),
    canInflict = function(target) return not hasType(target, "POISON") end,
    onInflict = function(battle, target, opts, display)
      if opts.toxic then
        target.toxicCounter = 1
        return { romLine(battle and battle.data, "_BadlyPoisonedText", display) }
      end
      return { romLine(battle and battle.data, "_PoisonedText", display) }
    end,
  },
  BRN = {
    id = "BRN", label = "BRN",
    catchBonus = 12, shakeBonus = 5,
    statPenalty = { stat = "attack", div = 2 },
    residual = damageOverTime("_HurtByBurnText"),
    canInflict = function(target) return not hasType(target, "FIRE") end,
    onInflict = function(battle, _, _, display)
      return { romLine(battle and battle.data, "_BurnedText", display) }
    end,
  },
  PAR = {
    id = "PAR", label = "PAR",
    catchBonus = 12, shakeBonus = 5,
    statPenalty = { stat = "speed", div = 4 },
    beforeMovePriority = 10,
    beforeMove = function(battler, rng, battle)
      -- cp 25 percent / jr nc: fully paralyzed on rand < 63 (63/256)
      if rng(0, 255) < 63 then
        return false, { romLine(battle and battle.data, "_FullyParalyzedText", name(battler)) }
      end
      return true, {}
    end,
    canInflict = function(target, opts)
      -- ParalyzeEffect_: Electric-type moves can't paralyze Ground-types
      return not (opts.moveType == "ELECTRIC" and hasType(target, "GROUND"))
    end,
    onInflict = function(battle, _, _, display)
      -- primary and secondary paralysis share this line
      return { romLine(battle and battle.data, "_ParalyzedMayNotAttackText", display) }
    end,
  },
}

function Status.registerInto(registry, _, owner)
  for id, record in pairs(Status.RECORDS) do
    registry:register(id, record, owner)
  end
end

-- the merged view when a battle is on hand, the vanilla records otherwise
function Status.recordFor(statuses, id)
  if id == nil then return nil end
  return (statuses or Status.RECORDS)[id]
end

-- engine/battle/core.asm:6283
local function penaltyOf(battler)
  local record = Status.recordFor(battler.statuses, battler.mon.status)
  return record and record.statPenalty
end

local MAX_PENALTY_STACKS = 32

local function penaltyDiv(battler, stat)
  local p = penaltyOf(battler)
  if p and p.stat == stat then return p.div or 1 end
  local divs = battler.statusPenaltyStacks and battler.statusPenaltyDivs
  return divs and divs[stat]
end

local function addStack(battler, p, n)
  local t = battler.statusPenaltyStacks
  t[p.stat] = n or ((t[p.stat] or 0) + 1)
  local divs = battler.statusPenaltyDivs
  if not divs then divs = {} battler.statusPenaltyDivs = divs end
  divs[p.stat] = p.div or 1
end

function Status.penaltyStacks(battler, stat)
  local t = battler.statusPenaltyStacks
  local n
  if t then
    if not penaltyDiv(battler, stat) then return 0 end
    n = t[stat] or 0
  else
    local p = penaltyOf(battler)
    if not p or p.stat ~= stat then return 0 end
    n = battler.hazeStatReset and 0 or 1
  end
  if type(n) ~= "number" or n ~= n or n < 0 then return 0 end
  return math.min(n, MAX_PENALTY_STACKS)
end

function Status.applyPenalty(battler, stat, value)
  local div = penaltyDiv(battler, stat)
  if not div then return value end
  div = math.max(1, div)
  for _ = 1, Status.penaltyStacks(battler, stat) do
    value = math.max(1, math.floor(value / div))
  end
  return value
end

-- core.asm:1658
-- experience.asm:237
function Status.bakePenalty(battler)
  battler.statusPenaltyStacks = {}
  battler.statusPenaltyDivs = nil
  local p = penaltyOf(battler)
  if p then addStack(battler, p, 1) end
end

-- engine/battle/effects.asm:414-415
function Status.clearPenalty(battler, stat)
  local t = battler.statusPenaltyStacks
  if t then t[stat] = 0 end
end

-- engine/battle/effects.asm:505-506
function Status.stackPenalty(battler)
  if not battler.statusPenaltyStacks then return end
  local p = penaltyOf(battler)
  if p then addStack(battler, p) end
end

-- pokered engine/battle/core.asm:6283
function Status.rulesetBakes(ruleset)
  return ruleset ~= nil and ruleset.statusPenaltyIsBaked ~= false
end

local function ensureStacks(battle, battler)
  if battler.statusPenaltyStacks then return true end
  if not Status.rulesetBakes(battle and battle.ruleset) then return false end
  Status.bakePenalty(battler)
  if battler.hazeStatReset then
    battler.statusPenaltyStacks, battler.statusPenaltyDivs = {}, nil
  end
  return true
end

local function bakes(battle, battler)
  return battler.statusPenaltyStacks ~= nil
    or Status.rulesetBakes(battle and battle.ruleset)
end

-- move_effects/paralyze.asm:35
function Status.bakeOnInflict(battle, battler)
  if not bakes(battle, battler) then return end
  if not battler.statusPenaltyStacks then return Status.bakePenalty(battler) end
  local p = penaltyOf(battler)
  if p then addStack(battler, p) end
end

-- engine/battle/experience.asm:236
function Status.bakeOnRecalc(battle, battler)
  if not bakes(battle, battler) then return end
  Status.bakePenalty(battler)
end

-- engine/battle/move_effects/heal.asm:35
-- engine/battle/trainer_ai.asm:625
function Status.keepPenaltyOnCure(battle, battler)
  if battler then ensureStacks(battle, battler) end
end

-- engine/items/item_effects.asm:907
function Status.dropPenaltyOnCure(battle, battler)
  if not battler then return end
  if battler.statusPenaltyStacks then
    battler.statusPenaltyStacks, battler.statusPenaltyDivs = {}, nil
  end
  if not Status.rulesetBakes(battle and battle.ruleset) then return end
  battler.curStats = battler.mon.stats
  battler.rawStats = { attack = true, defense = true, speed = true, special = true }
  battler.hazeStatReset = true
  battler.badgeExtraBoosts = nil
end

-- engine/battle/move_effects/heal.asm:29
-- engine/items/item_effects.asm:1172
function Status.toxicSurvivesCure(battle)
  local ruleset = battle and battle.ruleset
  return not ruleset or ruleset.toxicFlagSurvivesCure ~= false
end

-- effects.asm:414-415
function Status.afterStatChange(battle, who, stat, nonUser)
  if who.rawStats then who.rawStats[stat] = nil end
  if not ensureStacks(battle, who) then return end
  if stat ~= "accuracy" and stat ~= "evasion" then
    Status.clearPenalty(who, stat)
  end
  if nonUser and ensureStacks(battle, nonUser) then
    Status.stackPenalty(nonUser)
  end
end

-- the HUD label for a status id: a mod's patched hudLabel/label if the
-- merged registry has one, the raw id otherwise (BattleState.statusLabel,
-- SummaryMenu.draw and PartyMenu.draw all read this the same way)
function Status.hudLabelFor(statuses, id)
  local record = Status.recordFor(statuses, id)
  return record and (record.hudLabel or record.label) or id
end

-- Gen 2's own statuses registry (src/battle/gen2/Battle.lua) uses the full
-- names (poison/burn/freeze/paralyze/sleep) as ids; PartyMenu and SummaryMenu
-- both read a mon's status byte as the three/four-letter cart abbreviation
-- first (psn/brn/frz/par/paralysis/slp) and need this to look the record up.
-- `paralysis` mirrors the same three-way spelling (par/paralysis/paralyze)
-- src/core/gen2/ItemEffects.lua's STATUS_CLASS already recognizes for status
-- cures; battle itself only ever sets mon.status to the full Gen 2 spelling
-- ("paralyze"), so no live path produces "paralysis" today, but nothing
-- guarantees a save-compat or Gen 1-side path never will, and the two
-- tables should stay in sync either way.
Status.GEN2_ID_ALIASES = {
  psn = "poison", brn = "burn", frz = "freeze",
  par = "paralyze", paralysis = "paralyze", slp = "sleep",
}

local function battleStatuses(battle)
  return battle and battle.data and battle.data.statuses
end

-- Returns canMove, messages, selfHit (true -> hurt itself in confusion),
-- onomatopoeiaKind ("sleep" | "confused" | nil), onomatopoeiaIndex: which
-- SFX, if any, BattleState:sayStatusMsg should play, and which entry of
-- `messages` it belongs to -- NOT necessarily the last one. Confusion not
-- self-hitting can fall through into the disabled-move check or the
-- paralysis roll below, either of which may append one more, unrelated
-- message ("<move> is disabled!"/"fully paralyzed!") after the confusion
-- line; onomatopoeiaIndex keeps that later message reaching the screen as
-- plain text instead of being silently replaced by the SFX's own
-- regenerated display.
--
-- A record's beforeMove may return the kind as its own 4th value (only
-- SLP's still-asleep branch does, not its textually-identical wake-up
-- branch); the confusion block below sets it directly, since it is not a
-- status record. Never derive this from the message text instead: it is
-- real (potentially translated) ROM text by the time it reaches
-- BattleState, and a translation does not carry the English "is fast
-- asleep!"/"is confused!" substrings a naive search would look for.
--
-- The active status record's beforeMove runs at its priority slot: above
-- VOLATILE_PRIORITY before the held/disable/confusion block (sleep,
-- freeze), at or below after it (paralysis) -- the original's order.
function Status.beforeMove(battler, rng, battle, selectedMoveId)
  local mon = battler.mon
  -- Haze curing this mon's sleep/freeze forfeits its pending move for
  -- the turn, silently (haze.asm writes $ff/CANNOT_MOVE to the selected
  -- move; ExecuteMove returns immediately without a message)
  if battler.skipMove then
    battler.skipMove = nil
    return false, {}
  end
  if battler.flinched then
    battler.flinched = false
    return false, { romLine(battle and battle.data, "_FlinchedText", name(battler)) }
  end
  local record = Status.recordFor(battleStatuses(battle), mon.status)
  local handler = record and record.beforeMove
  local priority = handler and (record.beforeMovePriority or 0)
  local msgs = {}
  local onomatopoeiaKind, onomatopoeiaIndex
  -- statusBlockedId names the status record whose OWN beforeMove roll
  -- stopped this move (PAR's 63/256 full-paralysis check today) -- not
  -- mon.status, which a paralyzed-and-flinched battler also carries even
  -- though the flinch above is what actually blocked it, not this; and
  -- not msgs[#msgs] text-matched against "fully paralyzed" either
  -- (#644-class bug): that substring does not survive translation, while
  -- this structured id keeps working under any catalog.
  local statusBlockedId
  local function runStatus()
    local canMove, statusMsgs, selfHit, kind = handler(battler, rng, battle)
    for _, m in ipairs(statusMsgs or {}) do msgs[#msgs + 1] = m end
    if kind then onomatopoeiaKind, onomatopoeiaIndex = kind, #msgs end
    -- `record.id` is optional in the statuses registry (src/mods/Schemas.lua),
    -- and a mod's `override` replaces the record outright rather than merging,
    -- so fall back on the key the record was looked up under.
    if not canMove then statusBlockedId = record.id or mon.status end
    return canMove, selfHit
  end
  if handler and priority > VOLATILE_PRIORITY then
    local canMove, selfHit = runStatus()
    if not canMove or selfHit then
      return canMove, msgs, selfHit, onomatopoeiaKind, onomatopoeiaIndex, statusBlockedId
    end
    handler = nil
  end
  if battler.boundTurns and battler.boundTurns > 0 then
    battler.boundTurns = battler.boundTurns - 1
    msgs[#msgs + 1] = romLine(battle and battle.data, "_CantMoveText", name(battler))
    return false, msgs, nil, onomatopoeiaKind, onomatopoeiaIndex
  end
  if battler.disabledTurns then
    battler.disabledTurns = battler.disabledTurns - 1
    if battler.disabledTurns <= 0 then
      battler.disabledTurns, battler.disabledSlot = nil, nil
      table.insert(msgs, romLine(battle and battle.data, "_DisabledNoMoreText", name(battler)))
    end
  end
  if battler.confusedTurns then
    battler.confusedTurns = battler.confusedTurns - 1
    if battler.confusedTurns <= 0 then
      battler.confusedTurns = nil
      table.insert(msgs, romLine(battle and battle.data, "_ConfusedNoMoreText", name(battler)))
    else
      table.insert(msgs, romLine(battle and battle.data, "_IsConfusedText", name(battler)))
      onomatopoeiaKind, onomatopoeiaIndex = "confused", #msgs
      -- cp 50 percent + 1 / jr c: hurt itself on rand >= 128 (128/256)
      if rng(0, 255) < 128 then
        return false, msgs, true, onomatopoeiaKind, onomatopoeiaIndex -- hurt itself
      end
    end
  end
  -- .TriedToUseDisabledMoveCheck (engine/battle/core.asm, and the enemy
  -- copy .checkIfTriedToUseDisabledMove): the disabled-move test runs at
  -- EXECUTION time, comparing wPlayerDisabledMoveNumber against the
  -- already SELECTED move, so a Disable that lands earlier in the same
  -- turn still blocks the slower mon's move (#860).  It sits after the
  -- confusion block and before the paralysis roll, so a confusion self-hit
  -- still pre-empts it and the paralysis roll is never spent on a turn the
  -- disable eats.  PrintMoveIsDisabledText clears CHARGING_UP before
  -- printing, so a disabled charge move drops its stored turn instead of
  -- releasing later.
  if selectedMoveId and battler.disabledSlot then
    local disabled = (battler.curMoves or {})[battler.disabledSlot]
    if disabled and disabled.id == selectedMoveId then
      battler.charging, battler.chargeReady = nil, nil
      local moves = battle and battle.data and battle.data.moves
      local shown = moves and moves[selectedMoveId] and moves[selectedMoveId].name
                    or tostring(selectedMoveId)
      table.insert(msgs, romLine(battle and battle.data, "_MoveIsDisabledText", {
          USER = name(battler), ["RAM:wNameBuffer"] = shown,
        }))
      return false, msgs, nil, onomatopoeiaKind, onomatopoeiaIndex
    end
  end
  if handler then
    local canMove, selfHit = runStatus()
    if not canMove or selfHit then
      return canMove, msgs, selfHit, onomatopoeiaKind, onomatopoeiaIndex, statusBlockedId
    end
  end
  return true, msgs, nil, onomatopoeiaKind, onomatopoeiaIndex
end

-- End-of-turn residual damage; opponent is needed for Leech Seed.
-- Returns messages.
function Status.residual(battler, opponent, battle)
  local msgs = Status.residualStatus(battler, opponent, battle)
  for _, m in ipairs(Status.residualSeed(battler, opponent, battle)) do
    msgs[#msgs + 1] = m
  end
  return msgs
end

-- engine/battle/core.asm:482-495
function Status.residualStatus(battler, opponent, battle)
  local msgs = {}
  local mon = battler.mon
  -- the Haze move-forfeit only covers the turn Haze was used; if this
  -- mon had already moved, drop the flag before it leaks into next turn
  battler.skipMove = nil
  local record = Status.recordFor(battleStatuses(battle), mon.status)
  if record and record.residual then
    for _, m in ipairs(record.residual(battler, opponent, battle) or {}) do
      msgs[#msgs + 1] = m
    end
  end
  return msgs
end

-- engine/battle/core.asm:497-523
function Status.residualSeed(battler, opponent, battle)
  local msgs = {}
  local mon = battler.mon
  if battler.leechSeeded and mon.hp > 0 and opponent.mon.hp > 0 then
    -- the shared Toxic counter multiplies (and advances on) the seed
    -- drain too -- the Gen 1 Leech Seed glitch
    -- (HandlePoisonBurnLeechSeed_DecreaseOwnHP)
    local dmg = math.max(1, math.floor(mon.stats.hp / 16))
    if battler.toxicCounter then
      dmg = dmg * battler.toxicCounter
      battler.toxicCounter = battler.toxicCounter + 1
    end
    dmg = math.min(dmg, mon.hp)
    mon.hp = mon.hp - dmg
    opponent.mon.hp = math.min(opponent.mon.stats.hp, opponent.mon.hp + dmg)
    table.insert(msgs, romLine(battle and battle.data, "_HurtByLeechSeedText", name(battler)))
  end
  return msgs
end

return Status
