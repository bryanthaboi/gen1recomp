-- The move-effect execution surface: the ctx facade handed to every
-- move_effects record callback, and the staged damaging pipeline that
-- performMove drives through the record's stage fields
-- (gate/neverMiss/hitCount/beforeAccuracy/chooseDamage/onMiss/afterDamage
-- plus the post-damage secondary run).  The ctx is the only supported
-- surface handlers receive; everything else is engine-internal.

local MoveEffects = require("src.battle.MoveEffects")
local Runtime = require("src.mods.Runtime")
local StatusRegistry = require("src.battle.StatusRegistry")
local romText = require("src.core.RomText")
local Strings = require("src.core.Strings")
local Timing = require("src.core.Timing")

local EffectRegistry = {}

-- A move that misses -- or that registers as missed, which in Gen 1 includes
-- a type immunity and damage floored to zero -- skips its animation and
-- falls into PlayerCheckIfFlyOrChargeEffect's `ld c, 30 / call DelayFrames`
-- (engine/battle/core.asm:3155-3158 and :3185; enemy twin at :5588) before
-- anything is printed.  EXPLODE_EFFECT is the exception: core.asm:3157
-- branches it to PlayPlayerMoveAnimation instead, so it pays the animation
-- rather than the hold -- the same condition that gates cancelMoveAnim.
local function missBeat(battle, record)
  if record and record.explode then return end
  battle:waitNext(Timing.MOVE_STATUS_OR_MISS)
end

-- pokered's <USER>/<TARGET> text macros print "Enemy " before the enemy
-- mon's nickname (home/text.asm PlaceMoveUsersName)
local function displayName(b)
  return b.isPlayer and b.name or Strings("Enemy %s", b.name)  -- #779
end
EffectRegistry.displayName = displayName

-- built once per performMove call; closes over the battle
function EffectRegistry.makeCtx(battle, user, target, move, moveInst, isCalled)
  local ctx
  ctx = {
    battle = battle, data = battle.data, rng = battle.rng,
    ruleset = battle.ruleset,
    user = user, target = target, move = move, moveInst = moveInst,
    isCalled = isCalled or false,
    field = battle.field,
    displayName = displayName,
    say = function(text) battle:sayNext(text) end,
    sayNext = function(text) battle:sayNext(text) end,
    anim = function(animName, isPlayer)
      battle:animNext(animName, isPlayer == nil and user.isPlayer or isPlayer)
    end,
    drain = function() battle:drainNext() end,
    -- applyDamage plus the faint queue, like the crash/self-hit paths
    damage = function(who, amount)
      local dealt = battle:applyDamage(who, amount)
      if who.mon.hp <= 0 then battle:onFaint(who) end
      return dealt
    end,
    inflict = function(who, statusId, opts)
      return StatusRegistry.inflict(battle, who, statusId, opts)
    end,
    cure = function(who)
      who.mon.status = nil
      who.toxicCounter = nil
    end,
    changeStage = function(who, stat, delta, fromEnemy)
      return MoveEffects.changeStage(battle, who, stat, delta, fromEnemy)
    end,
    computeDamage = function(opts)
      return battle:computeDamage(user, target, move, opts)
    end,
    accuracyRoll = function()
      return battle:accuracyRoll(move, user, target)
    end,
    callMove = function(moveId)
      return battle:performMove(user, target, { id = moveId, pp = 1 }, true)
    end,
    side = function(who) return battle:sideOf(who) end,
  }
  return ctx
end

-- multi-hit count: the record's hitCount wins, then the move's multiHit
-- field, then a single hit
local function hitCount(ctx, record)
  if record and record.hitCount then
    return record.hitCount(ctx) or 1
  end
  local dist = ctx.move.multiHit
  if dist == nil then return 1 end
  if type(dist) == "number" then return dist end
  local r = ctx.rng(0, #dist - 1)
  return dist[r + 1]
end

-- engine/battle/effects.asm:119-151 (poison), :194-255 (burn/freeze/paralyze)
local FBP_SIDE_STATUS = { BRN = true, FRZ = true, PAR = true }

local function secondaryStatusFx(battle, user, status)
  if status == "PSN" then
    local row = battle:animNext(user.isPlayer and "ENEMY_HUD_SHAKE_ANIM"
                                or "SHAKE_SCREEN_ANIM", user.isPlayer)
    row.animDelayed = true
    row.hit = { animType = user.isPlayer and 6 or 3 }
  elseif FBP_SIDE_STATUS[status] and user.isPlayer then
    battle:animNext("ENEMY_HUD_SHAKE_ANIM", true).animDelayed = true
  end
end

-- The damaging pipeline, extracted from the performMove monolith: every
-- stage keeps the original's exact check order and rng consumption
-- (pre-accuracy -> invulnerability -> gate -> hit count -> accuracy ->
-- damage choice -> hits -> messages -> after-damage -> secondary run).
function EffectRegistry.runDamaging(battle, ctx, record)
  local user, target = ctx.user, ctx.target
  local move, moveInst = ctx.move, ctx.moveInst
  local neverMiss = record and record.neverMiss

  -- SpecialEffectsCont's JumpMoveEffect (core.asm:3129-3133) runs before
  -- MoveHitTest's INVULNERABLE test (:3150), mid-Fly/Dig included (#1565)
  if record and record.beforeAccuracy then record.beforeAccuracy(ctx) end

  -- Swift ignores semi-invulnerability (MoveHitTest returns hit for
  -- SWIFT_EFFECT before the INVULNERABLE check)
  if target.invulnerable and not neverMiss then
    -- Explosion/Selfdestruct still animate on a miss (HandleIfPlayerMoveMissed)
    if not (record and record.explode) then battle:cancelMoveAnim() end
    missBeat(battle, record)
    battle:sayNext(romText(battle.data, "_AttackMissedText", "%s's\nattack missed!", displayName(user)))
    -- MoveHitTest's INVULNERABLE branch sets the same wMoveMissed as a
    -- failed accuracy roll (core.asm:5260), and the miss handler still
    -- runs the explode effect ("even if Explosion or Selfdestruct
    -- missed, its effect still needs to be activated", core.asm:3223),
    -- so the user faints against a mid-Fly/Dig target too (#528)
    if record and record.onMiss then record.onMiss(ctx, "invulnerable") end
    return
  end

  -- OHKO speed gate, Dream Eater sleep gate
  if record and record.gate then
    local ok, failMsg = record.gate(ctx)
    if not ok then
      battle:cancelMoveAnim()
      if failMsg then battle:sayNext(failMsg) end
      return
    end
  end

  local hits = hitCount(ctx, record)

  if not neverMiss then
    if not battle:accuracyRoll(move, user, target) then
      -- Explosion/Selfdestruct still animate on a miss (HandleIfPlayerMoveMissed)
      if not (record and record.explode) then battle:cancelMoveAnim() end
      missBeat(battle, record)
      battle:sayNext(romText(battle.data, "_AttackMissedText", "%s's\nattack missed!", displayName(user)))
      -- Jump Kick crash, Explode self-destruct
      if record and record.onMiss then record.onMiss(ctx, "accuracy") end
      user.trappingTurns = nil
      return
    end
  end

  -- damage per hit
  local dmg, info
  if move.id == "COUNTER" then
    -- HandleCounterMove: 2x the last damage dealt in battle, only if
    -- the opponent's last move was counterable with >0 power (and not
    -- Counter itself); wDamage is shared, so any last damage counts.
    -- counterable defaults to the Normal/Fighting whitelist.
    local lastId = target.lastMove
    local lm = lastId and lastId ~= "COUNTER" and battle.data.moves[lastId]
    local counterable = false
    if lm and (lm.power or 0) > 0 then
      if lm.counterable ~= nil then
        counterable = lm.counterable
      else
        counterable = lm.type == "NORMAL" or lm.type == "FIGHTING"
      end
    end
    if not counterable or (battle.lastDamage or 0) == 0 then
      battle:cancelMoveAnim()
      missBeat(battle, record)
      battle:sayNext(romText(battle.data, "_AttackMissedText", "%s's\nattack missed!", displayName(user)))
      return
    end
    dmg = math.min(65535, battle.lastDamage * 2)
    info = { crit = false, typeMult = 10 }
  elseif record and record.chooseDamage then
    -- Counter/Super Fang/OHKO/fixed damage; (nil, msg) means the move
    -- failed with that text already chosen
    local chosen, extra = record.chooseDamage(ctx)
    if not chosen then
      battle:cancelMoveAnim()
      if extra then battle:sayNext(extra) end
      return
    end
    dmg, info = chosen, extra or { crit = false, typeMult = 10 }
  else
    dmg, info = battle:computeDamage(user, target, move,
      { rng = battle.rng, explode = (record and record.explode) or nil })
  end

  if info.typeMult == 0 then
    -- type immunity zeros damage and sets wMoveMissed in Gen 1, so no anim
    if not (record and record.explode) then battle:cancelMoveAnim() end
    missBeat(battle, record)
    battle:sayNext(romText(battle.data, "_DoesntAffectMonText", "It doesn't affect\n%s!", displayName(target)))
    if record and record.onMiss then record.onMiss(ctx, "immune") end
    return
  end
  if info.missed then
    -- 0.25x floored the damage to zero: the original registers a miss
    if not (record and record.explode) then battle:cancelMoveAnim() end
    missBeat(battle, record)
    battle:sayNext(romText(battle.data, "_AttackMissedText", "%s's\nattack missed!", displayName(user)))
    if record and record.onMiss then record.onMiss(ctx, "floored") end
    return
  end
  battle.lastDamage = dmg -- wDamage (shared by both sides, read by Counter)

  -- the hit blink + damage sound ride each animation row, placed BEFORE
  -- that hit's drain so the blink precedes the bar.  Multi-hit moves
  -- replay PlayMoveAnimation per strike (pokered: GetPlayerAnimationType
  -- / GetEnemyAnimationType loop on wNumAttacksLeft); hit 1 reuses the
  -- announcement-time moveAnimRow, later hits queue fresh anim rows.
  -- Mimic queues no announcement anim (announceAnim = false) -- a bare
  -- hitRow carries the blink instead.
  -- PlayApplyingAttackSound (engine/battle/animations.asm, the routine after
  -- PlayApplyingAttackAnimation) picks the sound off wDamageMultipliers -- 10
  -- is neutral, above it super effective, below it not very -- and sets
  -- wFrequencyModifier/wTempoModifier alongside it: $20/$30 damage, $e0/$ff
  -- super effective, $50/$01 not very.  All three programs live on the noise
  -- channel (audio/sfx/{damage,super_effective,not_very_effective}.asm,
  -- `channel 8`), where the frequency modifier is added to the polynomial
  -- counter and so IS the pitch of the hit, while the tempo modifier is
  -- skipped outright (audio/engine_2.asm Audio2_note_length: `cp CHAN8 /
  -- jr z, .skip` keeps the noise channel at the default $100).  Playing them
  -- bare made the super effective hit a dull thud and the not very effective
  -- one a bright crack, which is why they sounded swapped (#826); the tempo
  -- byte is deliberately not carried, since applying it would stretch notes
  -- the hardware never stretches.
  local hitSfx
  if info.typeMult > 10 then
    hitSfx = { sound = "Super_Effective", pitch = 0xe0 }
  elseif info.typeMult < 10 then
    hitSfx = { sound = "Not_Very_Effective", pitch = 0x50 }
  else
    hitSfx = { sound = "Damage", pitch = 0x20 }
  end
  -- GetPlayerAnimationType / GetEnemyAnimationType (engine/battle/core.asm
  -- :3159 / :5555): 4 blinks the enemy pic, 1 shakes vertically, 5 / 2 once
  -- the move has an added effect (#354)
  local added = move.effect ~= nil and move.effect ~= "NO_ADDITIONAL_EFFECT"
  -- PlayApplyingAttackAnimation runs on both arms of the wOptions check
  -- (engine/battle/animations.asm:424-437), so the blink is not gated (#1384)
  local hitFx = { sfx = hitSfx,
                  animType = user.isPlayer and (added and 5 or 4)
                             or (added and 2 or 1),
                  blink = target }

  local totalDealt = 0
  local landed, brokeSub = 0, false
  for h = 1, hits do
    if target.mon.hp <= 0 then break end
    local hitRow
    if h == 1 then
      hitRow = battle.moveAnimRow
      if not hitRow then
        battle.nextInsert = (battle.nextInsert or 0) + 1
        hitRow = { hitRow = true }
        table.insert(battle.queue, battle.nextInsert, hitRow)
      end
    else
      battle.nextInsert = (battle.nextInsert or 0) + 1
      hitRow = { anim = move.id, attackerIsPlayer = user.isPlayer }
      table.insert(battle.queue, battle.nextInsert, hitRow)
    end
    local hadSub = target.substituteHP ~= nil
    local dealt = battle:applyDamage(target, dmg)
    totalDealt = totalDealt + dealt
    landed = h
    if dealt > 0 then hitRow.hit = hitFx end
    -- PrintCriticalOHKOText + DisplayEffectiveness run inside the
    -- multi-hit loop (core.asm .moveDidNotMiss before the jump back
    -- to GetPlayerAnimationType), so crit/effectiveness reprint on
    -- every strike -- damage was only rolled once
    if info.crit then battle:sayNext(romText(battle.data, "_CriticalHitText", "Critical hit!")) end
    if info.ohko then battle:sayNext(romText(battle.data, "_OHKOText", "One-hit KO!")) end
    -- PrintCriticalOHKOText closes with `ld c, 20 / jp DelayFrames` at its
    -- .done label (core.asm:3812-3814) -- and the no-crit path jumps to that
    -- same label (:3799), so this hold is paid on EVERY landed hit, not just
    -- critical ones.  It sits between the crit text and DisplayEffectiveness
    -- (:3228-3229), which is where the beat before "It's super effective!"
    -- comes from.
    battle:waitNext(Timing.CRIT_OHKO_TEXT)
    if info.typeMult > 10 then
      battle:sayNext(romText(battle.data, "_SuperEffectiveText", "It's super\neffective!"))
    elseif info.typeMult < 10 then
      battle:sayNext(romText(battle.data, "_NotVeryEffectiveText", "It's not very\neffective..."))
    end
    if Runtime.wants("battle.damage_dealt") then
      Runtime.emit("battle.damage_dealt", {
        battle = battle, user = user, target = target, move = move,
        damage = dealt, crit = info.crit, typeMult = info.typeMult,
      })
    end
    if hadSub and not target.substituteHP then
      -- AttackSubstitute: breaking the substitute ends a multi-hit move
      brokeSub = true
      break
    end
  end
  hits = landed > 0 and landed or hits
  if hits > 1 then
    -- player: _MultiHitText; enemy: _HitXTimesText (always plural)
    if user.isPlayer then
      battle:sayNext(romText(battle.data, "_MultiHitText", "Hit the enemy\n%d times!", hits))
    else
      battle:sayNext(romText(battle.data, "_HitXTimesText", "Hit %d times!", hits))
    end
  end

  -- post-damage effect bookkeeping (recoil/drain/trap/thrash/...)
  ctx.rawDamage, ctx.totalDealt = dmg, totalDealt
  ctx.brokeSub, ctx.hits = brokeSub, hits
  if record and record.afterDamage then
    record.afterDamage(ctx, totalDealt)
  elseif moveInst.struggle then
    local recoil = math.max(1, math.floor(totalDealt / 2))
    battle:sayNext(romText(battle.data, "_HitWithRecoilText", "%s's\nhit with recoil!", displayName(user)))
    battle:applyDamage(user, recoil)
  end

  -- secondary side effects (blocked by fainting)
  if record and record.run and record.kind ~= "primary"
     and target.mon.hp > 0 and totalDealt > 0 then
    local hadStatus = target.mon.status
    local msgs = record.run(ctx)
    if target.mon.status and target.mon.status ~= hadStatus then
      secondaryStatusFx(battle, user, target.mon.status)
    end
    for _, m in ipairs(msgs) do
      battle:sayNext(m)
    end
  end
  if record == nil then
    MoveEffects.warnUnknown(move.effect)
  end

  if target.mon.hp <= 0 then
    battle:onFaint(target)
  end
  if user.mon.hp <= 0 then
    battle:onFaint(user)
  end
end

return EffectRegistry
