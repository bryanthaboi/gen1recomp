
return function(K)
  local P, D = K.P, K.destroy
  local TK = {}

  local SE_BALL_THROW = 54

  local function audio()
    local ok, Audio = pcall(require, "src.core.game3.audio")
    return ok and Audio or nil
  end

  local function play_se12(se, pan)
    local A = audio()
    if A and A.playSe and se then pcall(A.playSe, se, { pan = pan }) end
  end

  local function play_cry(species, pan, mode)
    local A = audio()
    if A and A.playCry and species then pcall(A.playCry, species, mode, pan) end
  end

  local function cry_playing()
    local A = audio()
    if A and A.isReady and not A.isReady() then return false end
    if A and A.isCryFinished then
      local ok, v = pcall(A.isCryFinished)
      return ok and not v
    end
    return false
  end

  local function species_of(vm, side)
    return side and P.species(vm, side) or nil
  end

  -- pokefirered/src/battle_anim_special.c:530
  TK.LoadHealthboxPalsForLevelUp = function(t) D(t) end
  TK.FreeHealthboxPalsForLevelUp = function(t) D(t) end
  TK.LoadBallGfx = function(t) D(t) end
  TK.FreeBallGfx = function(t) D(t) end
  TK.LoadBaitGfx = function(t) D(t) end
  TK.FreeBaitGfx = function(t) D(t) end

  -- pokefirered/src/battle_anim_special.c:569
  local function flashHealthboxStep(t, vm)
    local d = t.data
    d[0] = d[0] + 1
    local v = d[0]
    d[0] = v + 1
    if v >= d[11] then
      d[0] = 0
      local colorOffset = (d[10] == 0) and 6 or 2
      local stage = P.stage()
      local hb = stage and stage.healthbox and stage.healthbox[P.atk(vm)]
      if d[1] == 0 then
        d[2] = d[2] + 2
        if d[2] > 16 then d[2] = 16 end
        if hb then hb.levelUpBlend = { coeff = d[2], color = P.rgb(20, 27, 31), colorIndex = colorOffset } end
        if d[2] == 16 then d[1] = d[1] + 1 end
      elseif d[1] == 1 then
        d[2] = d[2] - 2
        if d[2] < 0 then d[2] = 0 end
        if hb then hb.levelUpBlend = { coeff = d[2], color = P.rgb(20, 27, 31), colorIndex = colorOffset } end
        if d[2] == 0 then
          if hb then hb.levelUpBlend = nil end
          D(t)
        end
      end
    end
  end

  -- pokefirered/src/battle_anim_special.c:562
  TK.FlashHealthboxOnLevelUp = function(t, vm)
    t.data[10] = vm.args[0]
    t.data[11] = vm.args[1]
    t.func = flashHealthboxStep
  end

  -- pokefirered/src/battle_anim_special.c:606
  TK.SwitchOutShrinkMon = function(t, vm)
    local side = P.atk(vm)
    local p = P.present(side)
    local d = t.data
    if d[0] == 0 then
      if p then p.visible = true end
      d[10] = 0x100
      d[0] = d[0] + 1
    elseif d[0] == 1 then
      d[10] = d[10] + 0x30
      P.setMonRotScale(p, d[10], d[10], 0)
      P.monYOffsetFromYScale(p, side, vm)
      if d[10] >= 0x2D0 then d[0] = d[0] + 1 end
    elseif d[0] == 2 then
      P.resetMonRotScale(p)
      if p then
        p.oy = 0
        p.visible = false
      end
      D(t)
    end
  end

  local function ball_open()
    local ok, BallOpen = pcall(require, "src.core.game3.battle.ball_open")
    return ok and BallOpen or nil
  end

  -- pokefirered/src/battle_anim_special.c:633
  TK.SwitchOutBallEffect = function(t, vm)
    local d = t.data
    local side = P.atk(vm)
    local BallOpen = ball_open()
    if d[0] == 0 then
      local x = P.coord(vm, side, P.X)
      local y = P.coord(vm, side, P.Y)
      local id = vm.attackerId and vm:attackerId() or P.sideId(side)
      local item = vm.ctx and (vm.ctx.ballItem and vm.ctx.ballItem[side] or vm.ctx.pokeball)
      if not item then
        local b = require("src.core.game3.battle.anim_coords").battler(nil, id)
        item = b and b.mon and b.mon.pokeball
      end
      if BallOpen then BallOpen.start(id, x, y + 32 + 5, item, false) end
      d[0] = d[0] + 1
    elseif d[0] == 1 then
      if not BallOpen or #BallOpen._tasks == 0 then D(t) end
    end
  end

  -- pokefirered/src/battle_anim_special.c:684
  TK.IsBallBlockedByTrainerOrDodged = function(t, vm)
    local c = (vm.ctx or {}).ballThrowCaseId
    if c == 5 then vm.args[P.ARG_RET_ID] = -1
    elseif c == 6 then vm.args[P.ARG_RET_ID] = -2
    else vm.args[P.ARG_RET_ID] = 0 end
    D(t)
  end

  local function throw_wait(t, vm)
    local b = t._ball
    if not b or b.finished or b.dead then D(t) end
  end

  -- pokefirered/src/battle_anim_special.c:734
  TK.ThrowBall = function(t, vm)
    local ok, CatchSeq = pcall(require, "src.core.game3.battle.catch_seq")
    local ctx = vm.ctx or {}
    local p = P.present(P.tgt(vm))
    ctx.wildMonInvisible = p and p.visible == false
    if ok and CatchSeq and CatchSeq.startBall then
      t._ball = CatchSeq.startBall({ caseId = ctx.ballThrowCaseId or 0, itemId = ctx.lastUsedItem })
    end
    t.func = throw_wait
  end

  -- pokefirered/src/battle_anim_special.c:790
  local function throwSpecialPlaySfx(t, vm)
    local C = K.cb()
    if C and C.playerThrowIndex(vm) == 1 then
      play_se12(SE_BALL_THROW, 0)
      if t._ball then t._ball.cb = t._ballInit end
      t.func = throw_wait
    end
  end

  -- pokefirered/src/battle_anim_special.c:758
  TK.ThrowBallSpecial = function(t, vm)
    local ctx = vm.ctx or {}
    local x, y
    if ctx.oldManTutorial then
      x, y = 28, 11
    else
      x, y = 23, 11
      if ctx.playerGender == 1 then y = 13 end
    end
    local ok, CatchSeq = pcall(require, "src.core.game3.battle.catch_seq")
    if ok and CatchSeq and CatchSeq.startBall then
      local b = CatchSeq.startBall({ caseId = ctx.ballThrowCaseId or 0, itemId = ctx.lastUsedItem })
      if b then
        b.x = P.bor(x, 32)
        b.y = P.bor(y, 80)
        t._ballInit = b.cb
        b.cb = function() end
        t._ball = b
      end
    end
    local C = K.cb()
    if C then C.startPlayerThrow(vm) end
    t.func = throwSpecialPlaySfx
  end

  -- pokefirered/src/battle_anim_special.c:1936
  TK.SwapMonSpriteToFromSubstitute = function(t, vm)
    local side = P.atk(vm)
    local p = P.present(side)
    local d = t.data
    if not p then
      D(t)
      return
    end
    if d[10] == 0 then
      d[11] = vm.args[0]
      d[0] = d[0] + 0x500
      if side ~= "player" then
        p.ox = (p.ox or 0) + P.asr(d[0], 8)
      else
        p.ox = (p.ox or 0) - P.asr(d[0], 8)
      end
      d[0] = P.band(d[0], 0xFF)
      local x = P.COORDS[side].x + (p.ox or 0) + 32
      if x < 0 or x > 304 then d[10] = d[10] + 1 end
    elseif d[10] == 1 then
      p.substitute = (d[11] == 0)
      p.substituteY = p.substitute and P.substituteY(side) or nil
      p.alpha = 1
      d[10] = d[10] + 1
    elseif d[10] == 2 then
      d[0] = d[0] + 0x500
      if side ~= "player" then
        p.ox = (p.ox or 0) - P.asr(d[0], 8)
      else
        p.ox = (p.ox or 0) + P.asr(d[0], 8)
      end
      d[0] = P.band(d[0], 0xFF)
      local done = false
      if side ~= "player" then
        if (p.ox or 0) <= 0 then
          p.ox = 0
          done = true
        end
      elseif (p.ox or 0) >= 0 then
        p.ox = 0
        done = true
      end
      if done then D(t) end
    end
  end

  -- pokefirered/src/battle_anim_special.c:1994
  TK.SubstituteFadeToInvisible = function(t, vm)
    local d = t.data
    local p = P.present(P.atk(vm))
    if d[15] == 0 then
      if p then p.alpha = 1 end
      d[15] = d[15] + 1
    elseif d[15] == 1 then
      local v = d[1]
      d[1] = v + 1
      if v > 1 then
        d[1] = 0
        d[0] = d[0] + 1
        if p then p.alpha = (16 - d[0]) / 16 end
        if d[0] == 16 then d[15] = d[15] + 1 end
      end
    elseif d[15] == 2 then
      if p then p.alpha = 0 end
      local ctx = vm.ctx or {}
      if ctx.behindSubstitute then ctx.behindSubstitute[P.atk(vm)] = false end
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_special.c:2028
  TK.IsAttackerBehindSubstitute = function(t, vm)
    local ctx = vm.ctx or {}
    local b = ctx.behindSubstitute and ctx.behindSubstitute[P.atk(vm)]
    vm.args[P.ARG_RET_ID] = b and 1 or 0
    D(t)
  end

  -- pokefirered/src/battle_anim_special.c:2034
  TK.SetTargetToEffectBattler = function(t, vm)
    local ctx = vm.ctx or {}
    if ctx.effectBattler then P.setBattlers(vm, nil, ctx.effectBattler) end
    D(t)
  end

  -- pokefirered/src/battle_anim_special.c:2256
  TK.SafariOrGhost_DecideAnimSides = function(t, vm)
    local a = vm.args[0]
    if a == 0 then
      P.setBattlers(vm, "player", "enemy")
    elseif a == 1 then
      P.setBattlers(vm, "enemy", "player")
    end
    D(t)
  end

  -- pokefirered/src/battle_anim_special.c:2273
  TK.SafariGetReaction = function(t, vm)
    local r = tonumber((vm.ctx or {}).safariReaction) or 0
    if r >= 3 then vm.args[7] = 0 else vm.args[7] = r end
    D(t)
  end

  -- pokefirered/src/battle_anim_special.c:2283
  TK.GetTrappedMoveAnimId = function(t, vm)
    local m = tonumber(vm.animArg) or 0
    if m == 83 then vm.args[0] = 1
    elseif m == 250 then vm.args[0] = 2
    elseif m == 128 then vm.args[0] = 3
    elseif m == 328 then vm.args[0] = 4
    else vm.args[0] = 0 end
    D(t)
  end

  -- pokefirered/src/battle_anim_special.c:2299
  TK.GetBattlersFromArg = function(t, vm)
    local m = P.u16(vm.animArg or 0)
    P.setBattlers(vm, P.band(m, 3), P.band(P.rshift(m, 8), 3))
    D(t)
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:39
  local function fireBlastStep2(t, vm)
    local d = t.data
    d[10] = d[10] + 1
    if d[10] == 6 then
      d[10] = 0
      play_se12(d[1], vm:adjustPanning(P.SOUND_PAN_TARGET))
      d[11] = d[11] + 1
      if d[11] == 2 then D(t) end
    end
  end
  local function fireBlastStep1(t, vm)
    local d = t.data
    local pan = d[2]
    local inc = P.s8(d[4])
    d[11] = d[11] + 1
    if d[11] == 111 then
      d[10] = 5
      d[11] = 0
      t.func = fireBlastStep2
    else
      d[10] = d[10] + 1
      if d[10] == 11 then
        d[10] = 0
        play_se12(d[0], pan)
      end
      pan = pan + inc
      d[2] = K.keepPan(pan)
    end
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:23
  TK.SoundTask_FireBlast = function(t, vm)
    local d = t.data
    d[0] = vm.args[0]
    d[1] = vm.args[1]
    local pan1 = vm:adjustPanning(P.SOUND_PAN_ATTACKER)
    local pan2 = vm:adjustPanning(P.SOUND_PAN_TARGET)
    d[2] = pan1
    d[3] = pan2
    d[4] = K.panInc(pan1, pan2, 2)
    d[10] = 10
    t.func = fireBlastStep1
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:102
  local function loopSeAdjustStep(t, vm)
    local d = t.data
    local v12 = d[12]
    d[12] = v12 + 1
    if v12 == d[6] then
      d[12] = 0
      play_se12(d[0], d[11])
      d[4] = P.band(d[4] - 1, 0xFFFF)
      if d[4] == 0 then
        D(t)
        return
      end
    end
    local v10 = d[10]
    d[10] = v10 + 1
    if v10 == d[5] then
      d[10] = 0
      d[11] = K.keepPan(P.s16(d[3] + d[11]))
    end
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:76
  TK.SoundTask_LoopSEAdjustPanning = function(t, vm)
    local a = vm.args
    local songId = P.u16(a[0])
    local targetPan = P.s8(a[2])
    local inc = P.s8(a[3])
    local r10, r7, r9 = P.u8(a[4]), P.u8(a[5]), P.u8(a[6])
    local sourcePan = vm:adjustPanning(P.s8(a[1]))
    targetPan = vm:adjustPanning(targetPan)
    inc = K.panInc(sourcePan, targetPan, inc)
    local d = t.data
    d[0], d[1], d[2], d[3] = songId, sourcePan, targetPan, inc
    d[4], d[5], d[6] = r10, r7, r9
    d[10] = 0
    d[11] = sourcePan
    d[12] = r9
    t.func = loopSeAdjustStep
    t.func(t, vm)
  end

  local function cry_battler(vm)
    local a0 = vm.args[0]
    if a0 == P.ANIM_ATTACKER then return P.atk(vm) end
    if a0 == P.ANIM_TARGET then return P.tgt(vm) end
    return nil
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:126
  TK.SoundTask_PlayCryHighPitch = function(t, vm)
    local pan = vm:adjustPanning(P.SOUND_PAN_ATTACKER)
    local side = cry_battler(vm)
    local p = side and P.present(side)
    if vm.args[0] == P.ANIM_TARGET and p and p.visible == false then
      D(t)
      return
    end
    local sp = species_of(vm, side)
    if sp then play_cry(sp, pan, 3) end
    D(t)
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:201
  local function doubleCryStep(t, vm)
    local d = t.data
    if d[9] < 2 then
      d[9] = d[9] + 1
    elseif not cry_playing() then
      play_cry(t._species, d[2], (d[0] == 255 or d[0] == -1) and 10 or 8)
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:158
  TK.SoundTask_PlayDoubleCry = function(t, vm)
    local pan = vm:adjustPanning(P.SOUND_PAN_ATTACKER)
    local side = cry_battler(vm)
    local p = side and P.present(side)
    if vm.args[0] == P.ANIM_TARGET and p and p.visible == false then
      D(t)
      return
    end
    local sp = species_of(vm, side)
    t.data[0] = vm.args[1]
    t._species = sp
    t.data[2] = pan
    if sp then
      local growl = (vm.args[1] == 255 or vm.args[1] == -1)
      play_cry(sp, pan, growl and 9 or 7)
      t.func = doubleCryStep
    else
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:228
  TK.SoundTask_WaitForCry = function(t, vm)
    if t.data[9] < 2 then
      t.data[9] = t.data[9] + 1
    elseif not cry_playing() then
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:258
  local function echoStep(t, vm)
    local d = t.data
    if d[9] < 2 then
      d[9] = d[9] + 1
    elseif not cry_playing() then
      play_cry(t._species, d[2], 6)
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:240
  TK.SoundTask_PlayCryWithEcho = function(t, vm)
    local pan = vm:adjustPanning(P.SOUND_PAN_ATTACKER)
    local sp = species_of(vm, P.atk(vm))
    t._species = sp
    t.data[2] = pan
    if sp then
      play_cry(sp, pan, 4)
      t.func = echoStep
    else
      D(t)
    end
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:279
  TK.SoundTask_PlaySE1WithPanning = function(t, vm)
    play_se12(P.u16(vm.args[0]), vm:adjustPanning(P.s8(vm.args[1])))
    D(t)
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:288
  TK.SoundTask_PlaySE2WithPanning = function(t, vm)
    play_se12(P.u16(vm.args[0]), vm:adjustPanning(P.s8(vm.args[1])))
    D(t)
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:318
  local function adjustPanVarStep(t, vm)
    local d = t.data
    local v = d[10]
    d[10] = v + 1
    if v == d[5] then
      d[10] = 0
      d[11] = K.keepPan(P.s16(d[3] + d[11]))
    end
    vm.animCustomPanning = d[11]
    if d[11] == d[2] then D(t) end
  end

  -- pokefirered/src/battle_anim_sound_tasks.c:299
  TK.SoundTask_AdjustPanningVar = function(t, vm)
    local a = vm.args
    local targetPan = P.s8(a[1])
    local inc = P.s8(a[2])
    local r9 = P.u16(a[3])
    local sourcePan = vm:adjustPanning(P.s8(a[0]))
    targetPan = vm:adjustPanning(targetPan)
    inc = K.panInc(sourcePan, targetPan, inc)
    local d = t.data
    d[1], d[2], d[3], d[5] = sourcePan, targetPan, inc, r9
    d[10] = 0
    d[11] = sourcePan
    t.func = adjustPanVarStep
    t.func(t, vm)
  end

  return TK
end
