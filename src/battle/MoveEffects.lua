-- Move effect handlers for every effect constant used in
-- data/moves/moves.asm, ported from engine/battle/core.asm and
-- engine/battle/move_effects/*.  Handlers receive the battle plus user and
-- target battler tables and push messages through battle:sayNext.
--
-- Substitutes block status/stat effects and side effects aimed at their
-- owner, like Gen 1.
--
-- The primary/secondary tables keep their v1 signatures; MoveEffects.full
-- carries the stage callbacks the damaging pipeline consults, and RECORDS
-- is the registry view of all three -- the merged Data.move_effects a
-- battle dispatches on serves these same objects.

local Damage = require("src.battle.Damage")
local Logger = require("src.core.Logger")
local StatusRegistry = require("src.battle.StatusRegistry")
local TurnOrder = require("src.battle.TurnOrder")
local TypeChart = require("src.battle.TypeChart")
local romText = require("src.core.RomText")
local Strings = require("src.core.Strings")

local MoveEffects = {}

-- pokered's <USER>/<TARGET> text macros print "Enemy " before the
-- enemy mon's nickname (home/text.asm PlaceMoveUsersName)
local function displayName(b)
  return b.isPlayer and b.name or Strings("Enemy %s", b.name)  -- #779
end

-- Stat names as printed (data/battle/stat_mod_names.asm
-- StatModTextStrings).  Strings.source, not Strings: this table is built
-- at require time, before Strings.load has a catalog, so changeStage
-- looks each label up at use time (#811).
local STAT_LABEL = {
  attack = Strings.source("ATTACK"), defense = Strings.source("DEFENSE"),
  speed = Strings.source("SPEED"), special = Strings.source("SPECIAL"),
  accuracy = Strings.source("ACCURACY"), evasion = Strings.source("EVADE"),
}

-- ---------------------------------------------------------------------
-- stat stages
-- ---------------------------------------------------------------------

local function changeStage(battle, who, stat, delta, fromEnemy)
  if fromEnemy and (who.substituteHP or who.mist) then
    if who.mist then
      return { Strings("%s is\nprotected by MIST!", displayName(who)) }
    end
    return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
  end
  local cur = who.stages[stat] or 0
  local new = math.max(-6, math.min(6, cur + delta))
  if new == cur then
    return { romText(battle.data, "_NothingHappenedText", "Nothing happened!") }
  end
  who.stages[stat] = new
  -- effects.asm:505-506: after any stat-stage change, modified stats are
  -- recomputed and QuarterSpeedDueToParalysis/HalveAttackDueToBurn re-run,
  -- re-baking the burn/para penalty and ending Haze's temporary lift.
  who.hazeStatReset = nil
  if battle.ruleset and battle.ruleset.badgeBoostReapplyBug
     and battle.kind ~= "link" and who == battle.player then
    Damage.reapplyBadgeBoosts(who, stat)
  end
  -- _MonsStatsRoseText/_MonsStatsFellText: "X's / STAT rose!"; the
  -- two-stage variants scroll "greatly" onto a third line
  local label = Strings(STAT_LABEL[stat])  -- looked up here, not at require (#811)
  if delta >= 2 then
    return { Strings("%s's\n%s\ngreatly rose!", displayName(who), label) }
  elseif delta == 1 then
    return { Strings("%s's\n%s rose!", displayName(who), label) }
  elseif delta == -1 then
    return { Strings("%s's\n%s fell!", displayName(who), label) }
  end
  return { Strings("%s's\n%s\ngreatly fell!", displayName(who), label) }
end
MoveEffects.changeStage = changeStage

local function statUp(stat, delta)
  return function(battle, user, target)
    return changeStage(battle, user, stat, delta, false)
  end
end

local function statDown(stat, delta)
  return function(battle, user, target)
    return changeStage(battle, target, stat, -delta, true)
  end
end

-- ---------------------------------------------------------------------
-- status
-- ---------------------------------------------------------------------

-- kept as the module's inflict entry: the registry-backed rules live in
-- StatusRegistry (per-status canInflict/onInflict on the merged records)
local function inflictStatus(battle, target, status, opts)
  return StatusRegistry.inflict(battle, target, status, opts)
end

local function statusMove(status)
  return function(battle, user, target, move)
    if target.mon.status then
      return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
    end
    if status == "PSN" and target.substituteHP then
      return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
    end
    local msgs = inflictStatus(battle, target, status, {
      toxic = move and move.id == "TOXIC",
      moveType = move and move.type,
      source = move and move.id,
    })
    if #msgs == 0 then
      return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
    end
    return msgs
  end
end

local function statusSide(status, chance)
  return function(battle, user, target, move)
    -- CheckDefrost: a burn-chance Fire move that lands thaws a frozen
    -- target (regardless of the burn roll)
    if move and move.type == "FIRE" and target.mon.status == "FRZ" then
      target.mon.status = nil
      return { romText(battle.data, "_FireDefrostedText", "Fire defrosted\n%s!", displayName(target)) }
    end
    if battle.rng(0, 255) >= chance then return {} end
    return inflictStatus(battle, target, status, {
      moveType = move and move.type,
      secondary = true,
      source = move and move.id,
    })
  end
end

local function statDownSide(stat)
  return function(battle, user, target)
    -- engine/battle/effects.asm:552
    if not user.isPlayer and battle.kind ~= "link"
       and battle.rng(0, 255) < 64 then
      return {}
    end
    if target.substituteHP then return {} end
    if battle.rng(0, 255) >= 85 then return {} end -- 33 percent + 1 (85/256)
    -- StatModifierDownEffect's side-effect branch never runs MoveHitTest,
    -- so the drop pierces MIST (only primary stat-lowering moves check it)
    return changeStage(battle, target, stat, -1, false)
  end
end

local function flinchSide(chance)
  return function(battle, user, target)
    if target.substituteHP then return {} end
    if battle.rng(0, 255) < chance then
      target.flinched = true
    end
    return {}
  end
end

local function confuse(battle, target, pierceSub)
  if target.confusedTurns or (target.substituteHP and not pierceSub) then
    return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
  end
  target.confusedTurns = battle.rng(2, 5)
  return { romText(battle.data, "_BecameConfusedText", "%s\nbecame confused!", displayName(target)) }
end

-- ---------------------------------------------------------------------
-- primary (status-only move) handlers
-- ---------------------------------------------------------------------

MoveEffects.primary = {
  ATTACK_UP1_EFFECT = statUp("attack", 1),
  ATTACK_UP2_EFFECT = statUp("attack", 2),
  DEFENSE_UP1_EFFECT = statUp("defense", 1),
  DEFENSE_UP2_EFFECT = statUp("defense", 2),
  SPEED_UP2_EFFECT = statUp("speed", 2),
  SPECIAL_UP1_EFFECT = statUp("special", 1),
  SPECIAL_UP2_EFFECT = statUp("special", 2),
  EVASION_UP1_EFFECT = statUp("evasion", 1),

  ATTACK_DOWN1_EFFECT = statDown("attack", 1),
  DEFENSE_DOWN1_EFFECT = statDown("defense", 1),
  DEFENSE_DOWN2_EFFECT = statDown("defense", 2),
  SPEED_DOWN1_EFFECT = statDown("speed", 1),
  ACCURACY_DOWN1_EFFECT = statDown("accuracy", 1),

  SLEEP_EFFECT = statusMove("SLP"),
  POISON_EFFECT = statusMove("PSN"),
  PARALYZE_EFFECT = statusMove("PAR"),

  CONFUSION_EFFECT = function(battle, user, target)
    return confuse(battle, target)
  end,

  LEECH_SEED_EFFECT = function(battle, user, target)
    -- leech_seed.asm has no substitute check: seeding lands through one
    if target.leechSeeded then
      return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
    end
    for _, t in ipairs(target.curTypes) do
      if t == "GRASS" then return { romText(battle.data, "_ButItFailedText", "But, it failed!") } end
    end
    target.leechSeeded = true
    return { romText(battle.data, "_WasSeededText", "%s\nwas seeded!", displayName(target)) }
  end,

  HEAL_EFFECT = function(battle, user, target, move)
    local mon = user.mon
    if move.id == "REST" then
      if mon.hp == mon.stats.hp then return { romText(battle.data, "_ButItFailedText", "But, it failed!") } end
      mon.hp = mon.stats.hp
      mon.status = "SLP"
      user.sleepTurns = 2
      user.toxicCounter = nil
      return { romText(battle.data, "_StartedSleepingEffect", "%s\nstarted sleeping!", displayName(user)) }
    end
    if mon.hp == mon.stats.hp then return { romText(battle.data, "_ButItFailedText", "But, it failed!") } end
    mon.hp = math.min(mon.stats.hp, mon.hp + math.floor(mon.stats.hp / 2))
    return { romText(battle.data, "_RegainedHealthText", "%s\nregained health!", displayName(user)) }
  end,

  LIGHT_SCREEN_EFFECT = function(battle, user)
    if user.lightScreen then return { romText(battle.data, "_ButItFailedText", "But, it failed!") } end
    user.lightScreen = true
    return { romText(battle.data, "_LightScreenProtectedText", "%s's\nprotected against\nspecial attacks!", displayName(user)) }
  end,

  REFLECT_EFFECT = function(battle, user)
    if user.reflect then return { romText(battle.data, "_ButItFailedText", "But, it failed!") } end
    user.reflect = true
    return { romText(battle.data, "_ReflectGainedArmorText", "%s\ngained armor!", displayName(user)) }
  end,

  MIST_EFFECT = function(battle, user)
    if user.mist then return { romText(battle.data, "_ButItFailedText", "But, it failed!") } end
    user.mist = true
    -- _ShroudedInMistText (lowercase "mist")
    return { romText(battle.data, "_ShroudedInMistText", "%s's\nshrouded in mist!", displayName(user)) }
  end,

  FOCUS_ENERGY_EFFECT = function(battle, user)
    if user.focusEnergy then return { romText(battle.data, "_ButItFailedText", "But, it failed!") } end
    user.focusEnergy = true
    return { romText(battle.data, "_GettingPumpedText", "%s's\ngetting pumped!", displayName(user)) }
  end,

  HAZE_EFFECT = function(battle, user, target)
    for _, b in ipairs({ user, target }) do
      b.stages = {}
      b.confusedTurns = nil
      b.leechSeeded = nil
      b.toxicCounter = nil
      b.reflect, b.lightScreen, b.mist, b.focusEnergy = nil, nil, nil, nil
      -- haze.asm also zeroes both disabled-move slots and clears
      -- USING_X_ACCURACY on both sides
      b.disabledSlot, b.disabledTurns = nil, nil
      b.xAccuracy = nil
      -- haze.asm ResetStats copies each side's UNMODIFIED stats (8 bytes,
      -- not HP) over its battle stats, which temporarily lifts the burn
      -- Attack-halving and paralysis Speed-quartering on BOTH battlers
      -- until the next stat recompute (a stage change or switch-in).
      b.hazeStatReset = true
      b.badgeExtraBoosts = nil
    end
    -- Gen 1 also removes the enemy's major status; if that cured sleep
    -- or freeze, the target forfeits its move this turn (haze.asm
    -- writes $ff/CANNOT_MOVE to its selected move)
    if target.mon.status == "SLP" or target.mon.status == "FRZ" then
      target.skipMove = true
    end
    target.mon.status = nil
    return { romText(battle.data, "_StatusChangesEliminatedText", "All STATUS changes\nare eliminated!") }
  end,

  -- substitute.asm reaches its PlayCurrentMoveAnimation / AnimationSubstitute
  -- Bankswitch only inside the success branch, after `set HAS_SUBSTITUTE_UP`;
  -- .alreadyHasSubstitute and .notEnoughHP fall straight through to PrintText,
  -- so both failures print with no animation at all.  That is load bearing
  -- here: the SUBSTITUTE animation opens with SE_SLIDE_MON_OFF, which leaves
  -- the user's pic hidden (BattleState.lua slideOff end state) until the doll
  -- is drawn in its place -- and with no substituteHP raised there is no doll,
  -- so a failed Substitute used to erase the user's sprite for the rest of the
  -- battle (#644).  The failed flag rides the message list so performMove can
  -- peel the announcement-time anim row without matching on printed text.
  SUBSTITUTE_EFFECT = function(battle, user)
    if user.substituteHP then
      return { romText(battle.data, "_HasSubstituteText", "%s\nhas a SUBSTITUTE!", displayName(user)),
               failed = true }
    end
    local cost = math.floor(user.mon.stats.hp / 4)
    -- A Substitute costs one quarter of max HP, rounded down. Do not let
    -- the cost consume the user's last HP: the move must fail at the exact
    -- boundary as well as below it, or the next turn's HP guard can leave a
    -- trainer battle unable to progress.
    if user.mon.hp <= cost then
      return { romText(battle.data, "_TooWeakSubstituteText", "Too weak to make\na SUBSTITUTE!"),
               failed = true }
    end
    user.mon.hp = user.mon.hp - cost
    user.substituteHP = cost + 1
    -- _SubstituteText
    return { romText(battle.data, "_SubstituteText", "It created a\nSUBSTITUTE!") }
  end,

  CONVERSION_EFFECT = function(battle, user, target)
    -- conversion.asm fails against a mid-Fly/Dig target (INVULNERABLE)
    if target.invulnerable then
      return { romText(battle.data, "_ButItFailedText", "But, it failed!") }
    end
    user.curTypes = { target.curTypes[1], target.curTypes[2] }
    -- _ConvertedTypeText
    return { romText(battle.data, "_ConvertedTypeText", "Converted type to\n%s's!", displayName(target)) }
  end,

  -- MIMIC_EFFECT lives in BattleState:resolveMimic: MimicEffect
  -- (effects.asm:1203-1273) runs mid-move -- hit test first, then the
  -- player's copy menu pauses the message queue, which a table of
  -- returned strings can't express.

  TRANSFORM_EFFECT = function(battle, user, target)
    -- transform.asm:31-53 (AnimationTransformMon) morphs the user's
    -- on-screen pic into the target species; the port swaps user.sprite
    -- via the same getImage/monPalette path makeBattler uses so the
    -- change is visible (the renderer draws battler.sprite directly).
    user.sprite = battle:speciesSprite(target.mon.species, user.isPlayer)
                  or user.sprite
    user.curStats = {
      hp = user.mon.stats.hp, -- HP is kept
      attack = target.curStats.attack, defense = target.curStats.defense,
      speed = target.curStats.speed, special = target.curStats.special,
    }
    user.curTypes = { target.curTypes[1], target.curTypes[2] }
    -- transform.asm:130-132 copies the target's stat MODS into the user
    -- (wEnemyMonStatMods -> wPlayerMonStatMods), it does NOT clear them;
    -- deep copy so later stage changes on either mon stay independent
    user.stages = {}
    for stat, stage in pairs(target.stages) do user.stages[stat] = stage end
    user.curMoves = {}
    for _, mv in ipairs(target.curMoves) do
      table.insert(user.curMoves, { id = mv.id, pp = 5, mimic = true })
    end
    -- _TransformedText: the copied name prints bare (wNameBuffer)
    return { romText(battle.data, "_TransformedText", "%s\ntransformed into\n%s!", displayName(user), target.name) }
  end,

  DISABLE_EFFECT = function(battle, user, target)
    if target.disabledSlot then return { romText(battle.data, "_ButItFailedText", "But, it failed!") } end
    local usable = {}
    for i, mv in ipairs(target.curMoves) do
      if mv.pp > 0 then table.insert(usable, i) end
    end
    if #usable == 0 then return { romText(battle.data, "_ButItFailedText", "But, it failed!") } end
    local slot = usable[battle.rng(1, #usable)]
    target.disabledSlot = slot
    target.disabledTurns = battle.rng(1, 8)
    local id = target.curMoves[slot].id
    -- _MoveWasDisabledText: "X's / MOVE was / disabled!"
    return { romText(battle.data, "_MoveWasDisabledText", "%s's\n%s was\ndisabled!",
      { TARGET = displayName(target),
        ["RAM:wNameBuffer"] = battle.data.moves[id].name }) }
  end,

  SPLASH_EFFECT = function(battle)
    return { romText(battle.data, "_NoEffectText", "No effect!") }
  end,
}

-- ---------------------------------------------------------------------
-- secondary (after-damage) side effects
-- ---------------------------------------------------------------------

MoveEffects.secondary = {
  BURN_SIDE_EFFECT1 = statusSide("BRN", 26),
  BURN_SIDE_EFFECT2 = statusSide("BRN", 77),
  FREEZE_SIDE_EFFECT1 = statusSide("FRZ", 26),
  PARALYZE_SIDE_EFFECT1 = statusSide("PAR", 26),
  PARALYZE_SIDE_EFFECT2 = statusSide("PAR", 77),
  POISON_SIDE_EFFECT1 = statusSide("PSN", 52),
  POISON_SIDE_EFFECT2 = statusSide("PSN", 103),
  FLINCH_SIDE_EFFECT1 = flinchSide(26),
  FLINCH_SIDE_EFFECT2 = flinchSide(77),
  ATTACK_DOWN_SIDE_EFFECT = statDownSide("attack"),
  DEFENSE_DOWN_SIDE_EFFECT = statDownSide("defense"),
  SPEED_DOWN_SIDE_EFFECT = statDownSide("speed"),
  SPECIAL_DOWN_SIDE_EFFECT = statDownSide("special"),
  CONFUSION_SIDE_EFFECT = function(battle, user, target)
    if target.confusedTurns then return {} end
    -- cp 10 percent (no +1): 25/256; ConfusionSideEffect never calls
    -- CheckTargetSubstitute, so secondary confusion pierces a substitute
    if battle.rng(0, 255) >= 25 then return {} end
    return confuse(battle, target, true)
  end,
  TWINEEDLE_EFFECT = function(battle, user, target)
    -- the second hit reroutes to PoisonEffect with POISON_SIDE_EFFECT1:
    -- 20 percent + 1 (52/256)
    if battle.rng(0, 255) >= 52 then return {} end
    return inflictStatus(battle, target, "PSN",
                         { secondary = true, source = "TWINEEDLE" })
  end,
}

-- ---------------------------------------------------------------------
-- full records: the damaging pipeline's stage callbacks
-- ---------------------------------------------------------------------

-- Status-move effects whose pokered handlers call MoveHitTest (sleep/
-- poison/paralyze/confusion/leech seed/disable and the primary
-- stat-down moves).  Everything else in MoveEffects.primary is
-- self-targeting and never rolls accuracy.  Mimic also hit-tests but
-- runs its own mid-move flow (resolveMimic).
local ACC_CHECKED = {
  SLEEP_EFFECT = true, POISON_EFFECT = true, PARALYZE_EFFECT = true,
  CONFUSION_EFFECT = true, LEECH_SEED_EFFECT = true, DISABLE_EFFECT = true,
  ATTACK_DOWN1_EFFECT = true, DEFENSE_DOWN1_EFFECT = true,
  DEFENSE_DOWN2_EFFECT = true, SPEED_DOWN1_EFFECT = true,
  ACCURACY_DOWN1_EFFECT = true,
}

-- fixed-damage moves (engine/battle/core.asm SpecialDamage); the move
-- field wins, previously imported caches fall back to the id table
local FIXED_DAMAGE = {
  SONICBOOM = 20, DRAGON_RAGE = 40,
  SEISMIC_TOSS = "level", NIGHT_SHADE = "level", PSYWAVE = "half_level_rand",
}
MoveEffects.FIXED_DAMAGE = FIXED_DAMAGE

local function fixedDamageFor(ctx)
  local spec = ctx.move.fixedDamage
  if spec == nil then spec = FIXED_DAMAGE[ctx.move.id] end
  if type(spec) == "function" then return spec(ctx) end
  if spec == "level" then return ctx.user.mon.level end
  if spec == "half_level_rand" then
    -- PSYWAVE: rand(1, floor(level*3/2) - 1)
    local max = math.max(1, math.floor(ctx.user.mon.level * 3 / 2) - 1)
    return ctx.rng(1, max)
  end
  return spec
end

local function plainInfo()
  return { crit = false, typeMult = 10 }
end

-- multi-hit count: the move's multiHit field (a count or a distribution)
-- with the effect's classic distribution as the fallback
local function hitsFrom(dist, ctx)
  if type(dist) == "number" then return dist end
  local r = ctx.rng(0, #dist - 1)
  return dist[r + 1]
end

-- engine/battle/core.asm ApplyDamageToEnemyPokemon
local function drainHalf(label, text)
  return function(ctx)
    local heal = math.max(1, math.floor(ctx.totalDealt / 2))
    ctx.battle.lastDamage = heal
    local mon = ctx.user.mon
    mon.hp = math.min(mon.stats.hp, mon.hp + heal)
    ctx.drain()
    -- `text` arrives as a source string (Strings.source at the call
    -- site keeps it in the catalog); the ROM's own line wins when the
    -- import carries it, and both are resolved here, at use time
    ctx.say(romText(ctx.battle.data, label, text, displayName(ctx.target)))
  end
end

-- OHKO is the only "damage but not through normal calculations" family
-- that still runs the type chart.  CalculateDamage hands OHKO_EFFECT to
-- JumpToOHKOMoveEffect (engine/battle/core.asm:4329) and, when the effect
-- did not set wMoveMissed, execution falls through to
-- AdjustDamageForMoveType (core.asm:3147), which multiplies the 65535 by
-- the 0 matchup and flags the miss.  Fixed damage and Super Fang do not:
-- they are the SetDamageEffects table (data/battle/set_damage_effects.asm)
-- and core.asm:3139 jumps straight to MoveHitTest, skipping
-- CalculateDamage, AdjustDamageForMoveType and RandomizeDamage, while
-- ApplyAttackToEnemyPokemon (core.asm:4612) writes wDamage with no
-- effectiveness step.  So in Gen 1 NIGHT_SHADE hits Normal-types and
-- SUPER_FANG hits Ghosts, and only OHKO_EFFECT calls this (#616).
local function immuneMsg(ctx)
  if TypeChart.effectiveness(ctx.move.type, ctx.target.curTypes) == 0 then
    return romText(ctx.battle.data, "_DoesntAffectMonText", "It doesn't affect\n%s!", displayName(ctx.target))
  end
  return nil
end

MoveEffects.full = {
  NO_ADDITIONAL_EFFECT = {},

  TWO_TO_FIVE_ATTACKS_EFFECT = {
    hitCount = function(ctx)
      return hitsFrom(ctx.move.multiHit or { 2, 2, 2, 3, 3, 3, 4, 5 }, ctx)
    end,
  },
  ATTACK_TWICE_EFFECT = {
    hitCount = function(ctx)
      return hitsFrom(ctx.move.multiHit or 2, ctx)
    end,
  },
  -- hits twice AND keeps its secondary poison run (registered below)
  TWINEEDLE_EFFECT = {
    hitCount = function(ctx)
      return hitsFrom(ctx.move.multiHit or 2, ctx)
    end,
  },

  SPECIAL_DAMAGE_EFFECT = {
    chooseDamage = function(ctx)
      -- no immunity check: SetDamageEffects skips AdjustDamageForMoveType (#616)
      local dmg = fixedDamageFor(ctx)
      if not dmg then
        return nil, romText(ctx.battle.data, "_ButItFailedText", "But, it failed!")
      end
      return dmg, plainInfo()
    end,
  },
  SUPER_FANG_EFFECT = {
    chooseDamage = function(ctx)
      -- also SetDamageEffects: halves a Ghost's HP in Gen 1 (#616)
      return math.max(1, math.floor(ctx.target.mon.hp / 2)), plainInfo()
    end,
  },
  OHKO_EFFECT = {
    -- fails against faster opponents (Gen 1 rule) and immune types
    gate = function(ctx)
      local blocked = immuneMsg(ctx)
      if blocked then return false, blocked end
      if TurnOrder.effectiveSpeed(ctx.user) < TurnOrder.effectiveSpeed(ctx.target) then
        return false, romText(ctx.battle.data, "_ButItFailedText", "But, it failed!")
      end
      return true
    end,
    chooseDamage = function()
      return 65535, { crit = false, typeMult = 10, ohko = true }
    end,
  },

  RECOIL_EFFECT = {
    afterDamage = function(ctx)
      -- engine/battle/move_effects/recoil.asm
      local recoil = math.max(1, math.floor(ctx.totalDealt
                                            / (ctx.moveInst.struggle and 2 or 4)))
      ctx.say(romText(ctx.battle.data, "_HitWithRecoilText", "%s's\nhit with recoil!", displayName(ctx.user)))
      ctx.battle:applyDamage(ctx.user, recoil)
    end,
  },
  DRAIN_HP_EFFECT = {
    afterDamage = drainHalf("_SuckedHealthText", Strings.source("Sucked health from\n%s!")),
  },
  DREAM_EATER_EFFECT = {
    -- only works on sleeping targets (checked before damage)
    gate = function(ctx)
      if ctx.target.mon.status ~= "SLP" then
        return false, romText(ctx.battle.data, "_ButItFailedText", "But, it failed!")
      end
      return true
    end,
    afterDamage = drainHalf("_DreamWasEatenText", Strings.source("%s's\ndream was eaten!")),
  },

  -- charge moves: first turn just charges; Fly AND Dig go
  -- semi-invulnerable (ChargeEffect sets INVULNERABLE for both)
  CHARGE_EFFECT = { charge = { anim = "XSTATITEM_ANIM", enemyAnim = "XSTATITEM_DUPLICATE_ANIM" } },
  FLY_EFFECT = { charge = { invulnerable = true, anim = "TELEPORT" } },

  TRAPPING_EFFECT = {
    -- TrappingEffect runs BEFORE the hit test and clears the target's
    -- Hyper Beam recharge, even if the trapping move then misses
    -- (effects.asm:1091-1092 ClearHyperBeam)
    beforeAccuracy = function(ctx)
      if not ctx.user.trappingTurns then
        ctx.target.mustRecharge = nil
      end
    end,
    afterDamage = function(ctx)
      local user = ctx.user
      if not user.trappingTurns then
        -- TrappingEffect (effects.asm:1080-1103) rolls wNumAttacksLeft
        -- as 1-4 (weights 3/8 3/8 1/8 1/8): that many CONTINUATION
        -- attacks follow this first hit, 2-5 attacks total.  The victim
        -- is held while the counter runs (live mirror in lockedAction).
        local r = ctx.rng(0, 7)
        user.trappingTurns = ({ 1, 1, 1, 2, 2, 2, 3, 4 })[r + 1]
        user.trapDamage = ctx.rawDamage
        -- PlayApplyingAttackSound (animations.asm:2639) replays it each turn
        user.trapHitSfx = ctx.hitSfx
        -- remember the move so its animation can replay on each locked
        -- continuation (core.asm:3554-3566 -> GetPlayerAnimationType)
        user.trapMove = ctx.move.id
      end
    end,
  },
  THRASH_PETAL_DANCE_EFFECT = {
    -- ThrashPetalDanceEffect (effects.asm:791-808) runs before damage
    -- (data/battle/special_effects.asm:22, core.asm:3531-3552)
    beforeAccuracy = function(ctx)
      local user = ctx.user
      if ctx.thrashing or user.thrashTurns then return end
      user.thrashTurns = ctx.rng(2, 3) -- 3-4 attacks total, then confusion
      user.thrashMove = ctx.moveInst
      user.thrashAnnounced = true
      ctx.battle:animBeforeMove(
        user.isPlayer and "SHRINKING_SQUARE_ANIM" or "ANIM_B1", user.isPlayer)
    end,
  },
  JUMP_KICK_EFFECT = {
    onMiss = function(ctx, reason)
      if reason ~= "accuracy" then return end
      ctx.say(romText(ctx.battle.data, "_KeptGoingAndCrashedText", "%s\nkept going and\ncrashed!", displayName(ctx.user)))
      ctx.damage(ctx.user, 1)
    end,
  },
  EXPLODE_EFFECT = {
    explode = true, -- Damage.compute halves the defense
    onMiss = function(ctx)
      ctx.battle:selfDestruct(ctx.user)
    end,
    afterDamage = function(ctx)
      ctx.battle:selfDestruct(ctx.user)
    end,
  },
  HYPER_BEAM_EFFECT = {
    afterDamage = function(ctx)
      -- Gen 1: no recharge when the target faints OR its substitute breaks.
      -- Ruleset hyperBeamSkipRechargeOnKO=false forces Gen 2+ always-recharge.
      local ruleset = ctx.battle and ctx.battle.ruleset
      local skipOnKO = not ruleset or ruleset.hyperBeamSkipRechargeOnKO ~= false
      local targetDown = ctx.target.mon.hp <= 0 or ctx.brokeSub
      if not skipOnKO or not targetDown then
        ctx.user.mustRecharge = true
      end
    end,
  },
  PAY_DAY_EFFECT = {
    afterDamage = function(ctx)
      local battle = ctx.battle
      battle.payDay = (battle.payDay or 0) + 2 * ctx.user.mon.level
      ctx.say(romText(ctx.battle.data, "_CoinsScatteredText", "Coins scattered\neverywhere!"))
    end,
  },
  SWIFT_EFFECT = { neverMiss = true },
  RAGE_EFFECT = {
    afterDamage = function(ctx)
      ctx.user.rageMove = ctx.moveInst
    end,
  },

  BIDE_EFFECT = {
    -- BideEffect (effects.asm:764-789) is a ResidualEffects2 entry: the
    -- storing turn plays XSTATITEM_ANIM (XSTATITEM_DUPLICATE_ANIM on the
    -- enemy side) and never BIDE's own animation, which belongs to the
    -- release turn in .UnleashEnergy (#375)
    perform = function(ctx)
      local user = ctx.user
      user.bideTurns = ctx.rng(2, 3)
      user.bideDamage = 0
      ctx.battle:cancelMoveAnim()
      ctx.battle:animBeforeMove(
        user.isPlayer and "XSTATITEM_ANIM" or "XSTATITEM_DUPLICATE_ANIM",
        user.isPlayer)
      ctx.say(Strings("%s\nis storing energy!", displayName(user)))
    end,
  },
  SWITCH_AND_TELEPORT_EFFECT = {
    -- SwitchAndTeleportEffect (effects.asm:810-909): in a wild battle
    -- it auto-succeeds when the user's level >= the opponent's;
    -- otherwise roll rand[0, userLevel+enemyLevel] and FAIL when the
    -- roll is below opponentLevel/4.  Teleport's failure text is "But
    -- it failed!", Roar/Whirlwind's is DidntAffectText; in trainer
    -- battles Teleport fails and Roar/Whirlwind are "unaffected".
    -- Fail paths DelayFrames then print -- no PlayCurrentMoveAnimation.
    perform = function(ctx)
      local battle, user, target, move = ctx.battle, ctx.user, ctx.target, ctx.move
      if battle.kind == "wild" then
        local uLvl, tLvl = user.mon.level, target.mon.level
        local ok = uLvl >= tLvl
        if not ok then
          ok = ctx.rng(0, uLvl + tLvl) >= math.floor(tLvl / 4)
        end
        if ok then
          if move.id == "ROAR" then
            ctx.say(romText(ctx.battle.data, "_RanAwayScaredText", "%s\nran away scared!", displayName(target)))
          elseif move.id == "WHIRLWIND" then
            ctx.say(romText(ctx.battle.data, "_WasBlownAwayText", "%s\nwas blown away!", displayName(target)))
          else
            ctx.say(romText(ctx.battle.data, "_RanFromBattleText", "%s\nran from battle!", displayName(user)))
          end
          battle.result = "run"
          battle.afterQueue = "finish"
        elseif move.id == "TELEPORT" then
          battle:cancelMoveAnim()
          ctx.say(romText(ctx.battle.data, "_ButItFailedText", "But, it failed!"))
        else
          battle:cancelMoveAnim()
          ctx.say(romText(ctx.battle.data, "_DidntAffectText", "It didn't affect\n%s!", displayName(target)))
        end
      elseif move.id == "TELEPORT" then
        battle:cancelMoveAnim()
        ctx.say(romText(ctx.battle.data, "_ButItFailedText", "But, it failed!"))
      else
        battle:cancelMoveAnim()
        ctx.say(romText(ctx.battle.data, "_IsUnaffectedText", "%s\nis unaffected!", displayName(target)))
      end
    end,
  },
  METRONOME_EFFECT = {
    callsMove = function(ctx)
      local order = ctx.data.constants.moveOrder
      local pick
      repeat
        pick = order[ctx.rng(1, #order)]
      until pick ~= "METRONOME" and pick ~= "STRUGGLE" and ctx.data.moves[pick]
      return pick
    end,
  },
  MIRROR_MOVE_EFFECT = {
    callsMove = function(ctx)
      local last = ctx.target.lastMove
      if not last then
        ctx.say(romText(ctx.battle.data, "_MirrorMoveFailedText", "The MIRROR MOVE\nfailed!"))
        return nil
      end
      return last
    end,
  },
  -- Mimic runs its own mid-move flow: hit test, then the copy menu
  -- (player) or a random roll (enemy / link), all on the queue.
  -- PlayCurrentMoveAnimation runs only after a successful copy
  -- (effects.asm:1268), never on a miss -- so no announcement anim row.
  MIMIC_EFFECT = {
    announceAnim = false,
    perform = function(ctx)
      ctx.battle:resolveMimic(ctx.user, ctx.target, ctx.move, ctx.moveInst)
    end,
  },
}

-- ---------------------------------------------------------------------
-- the registry view
-- ---------------------------------------------------------------------

-- effects fully handled inside the damaging pipeline; kept as the v1
-- compat set (BattleState dispatched on it before the records existed)
MoveEffects.special = {
  NO_ADDITIONAL_EFFECT = true, TWO_TO_FIVE_ATTACKS_EFFECT = true,
  ATTACK_TWICE_EFFECT = true, SPECIAL_DAMAGE_EFFECT = true,
  SUPER_FANG_EFFECT = true, OHKO_EFFECT = true, RECOIL_EFFECT = true,
  DRAIN_HP_EFFECT = true, DREAM_EATER_EFFECT = true, CHARGE_EFFECT = true,
  FLY_EFFECT = true, TRAPPING_EFFECT = true, THRASH_PETAL_DANCE_EFFECT = true,
  JUMP_KICK_EFFECT = true, EXPLODE_EFFECT = true, HYPER_BEAM_EFFECT = true,
  PAY_DAY_EFFECT = true, SWIFT_EFFECT = true, RAGE_EFFECT = true,
  BIDE_EFFECT = true, SWITCH_AND_TELEPORT_EFFECT = true,
  METRONOME_EFFECT = true, MIRROR_MOVE_EFFECT = true,
  TWINEEDLE_EFFECT = true, MIMIC_EFFECT = true,
}

-- the (battle, user, target, move, moveInst) handlers adapted to the ctx
-- facade the registry records expose
local function shim(fn)
  return function(ctx)
    return fn(ctx.battle, ctx.user, ctx.target, ctx.move, ctx.moveInst)
  end
end

local RECORDS = {}
MoveEffects.RECORDS = RECORDS
for id, fn in pairs(MoveEffects.primary) do
  RECORDS[id] = { kind = "primary", run = shim(fn),
                  accuracyChecked = ACC_CHECKED[id] or nil }
end
for id, fn in pairs(MoveEffects.secondary) do
  RECORDS[id] = { kind = "secondary", run = shim(fn) }
end
for id, spec in pairs(MoveEffects.full) do
  local record = { kind = "full" }
  for key, value in pairs(spec) do record[key] = value end
  -- TWINEEDLE: full record with its secondary run honored post-damage
  local secondary = MoveEffects.secondary[id]
  if secondary then record.run = shim(secondary) end
  RECORDS[id] = record
end

-- One record per effect, the same objects performMove dispatches on: the
-- merged Data.move_effects and this table agree by construction.
function MoveEffects.registerInto(registry, _, owner)
  for id, record in pairs(RECORDS) do
    registry:register(id, record, owner)
  end
end

local warned = {}

function MoveEffects.warnUnknown(effect)
  if not warned[effect] then
    warned[effect] = true
    Logger.warn("move effect %s not implemented; treated as plain damage", effect)
  end
end

return MoveEffects
