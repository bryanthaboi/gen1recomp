local P = require("src.core.game3.battle.anim_port.g3_pret")

local C, T = {}, {}
local band = P.band

local function updateConfuseRayBallBlend(s, vm)
  local d = s.data
  if d[6] > 0xFF then
    d[6] = d[6] + 1
    if d[6] == 0x10d then d[6] = 0 end
    return
  end
  local r0 = d[7]
  d[7] = d[7] + 1
  if band(r0, 0xFF) == 0 then
    d[7] = band(d[7], 0xff00)
    if band(d[7], 0x100) ~= 0 then
      d[6] = d[6] + 1
    else
      d[6] = d[6] - 1
    end
    P.setBld(vm, d[6], 16 - d[6])
    if d[6] == 0 or d[6] == 16 then d[7] = P.bxor(d[7], 0x100) end
    if d[6] == 0 then d[6] = 0x100 end
  end
end

local function confuseRayStep2(s, vm)
  local d = s.data
  d[0] = 1
  P.AnimTranslateLinear(s)
  s.ox = s.ox + P.Sin(d[5], 10)
  s.oy = s.oy + P.Cos(d[5], 15)
  local r2 = d[5]
  d[5] = band(d[5] + 5, 0xFF)
  local r0 = d[5]
  if (r2 == 0 or r2 > 196) and r0 > 0 then
    P.playSE(vm, "SE_M_CONFUSE_RAY")
  end
  if d[6] == 0 then
    s.invisible = true
    s.callbackFn = P.DestroyAnimSpriteAndDisableBlend
  else
    updateConfuseRayBallBlend(s, vm)
  end
end

local function confuseRayStep1(s, vm)
  local d = s.data
  updateConfuseRayBallBlend(s, vm)
  if P.AnimTranslateLinear(s) then
    s.callbackFn = confuseRayStep2
    return
  end
  s.ox = s.ox + P.Sin(d[5], 10)
  s.oy = s.oy + P.Cos(d[5], 15)
  local r2 = d[5]
  d[5] = band(d[5] + 5, 0xFF)
  local r0 = d[5]
  if r2 ~= 0 and r2 <= 196 then return end
  if r0 <= 0 then return end
  P.playSE(vm, "SE_M_CONFUSE_RAY", vm.animCustomPanning or 0)
end

-- pokefirered/src/battle_anim_ghost.c:220
C.ConfuseRayBallBounce = P.cb(function(s, vm)
  local d = s.data
  P.InitSpritePosToAnimAttacker(s, vm, true)
  d[0] = s.ga[2]
  d[1] = s.x
  d[2] = P.coordTgt(vm, P.COORD_X_2)
  d[3] = s.y
  d[4] = P.coordTgt(vm, P.COORD_Y_PIC)
  P.InitAnimLinearTranslationWithSpeed(s)
  s.callbackFn = confuseRayStep1
  d[6] = 16
  P.setBld(vm, 16, 0)
end)

local function confuseRaySpiralStep(s)
  local d = s.data
  s.ox = P.Sin(d[0], 32)
  s.oy = P.Cos(d[0], 8)
  local temp1 = P.u16(d[0] - 65)
  if temp1 <= 130 then s.pri = 2 else s.pri = 1 end
  d[0] = band(d[0] + 19, 0xFF)
  d[2] = P.s16(d[2] + 80)
  s.oy = s.oy + P.shr(d[2], 8)
  d[7] = d[7] + 1
  if d[7] == 61 then P.DestroyAnimSprite(s) end
end

-- pokefirered/src/battle_anim_ghost.c:308
C.ConfuseRayBallSpiral = P.cb(function(s, vm)
  P.InitSpritePosToAnimTarget(s, vm, true)
  s.callbackFn = confuseRaySpiralStep
  confuseRaySpiralStep(s, vm)
end)

local function shadowBallStep(s, vm)
  local d = s.data
  if d[0] == 0 then
    d[4] = P.s16(d[4] + d[6])
    d[5] = P.s16(d[5] + d[7])
    s.x = P.shr(d[4], 4)
    s.y = P.shr(d[5], 4)
    d[1] = d[1] - 1
    if d[1] > 0 then return end
    d[0] = d[0] + 1
  elseif d[0] == 1 then
    d[2] = d[2] - 1
    if d[2] > 0 then return end
    d[1] = P.coordTgt(vm, P.COORD_X_2)
    d[2] = P.coordTgt(vm, P.COORD_Y_PIC)
    d[4] = P.s16(s.x * 16)
    d[5] = P.s16(s.y * 16)
    d[6] = P.s16(P.div((d[1] - s.x) * 16, d[3]))
    d[7] = P.s16(P.div((d[2] - s.y) * 16, d[3]))
    d[0] = d[0] + 1
  elseif d[0] == 2 then
    d[4] = P.s16(d[4] + d[6])
    d[5] = P.s16(d[5] + d[7])
    s.x = P.shr(d[4], 4)
    s.y = P.shr(d[5], 4)
    d[3] = d[3] - 1
    if d[3] > 0 then return end
    s.x = P.coordTgt(vm, P.COORD_X_2)
    s.y = P.coordTgt(vm, P.COORD_Y_PIC)
    d[0] = d[0] + 1
  elseif d[0] == 3 then
    P.DestroySpriteAndMatrix(s)
  end
end

-- pokefirered/src/battle_anim_ghost.c:396
C.ShadowBall = P.cb(function(s, vm)
  local d = s.data
  local oldX, oldY = s.x, s.y
  s.x = P.coordAtk(vm, P.COORD_X_2)
  s.y = P.coordAtk(vm, P.COORD_Y_PIC)
  d[0] = 0
  d[1] = s.ga[0]
  d[2] = s.ga[1]
  d[3] = s.ga[2]
  d[4] = P.s16(s.x * 16)
  d[5] = P.s16(s.y * 16)
  d[6] = P.s16(P.div((oldX - s.x) * 16, s.ga[0] * 2))
  d[7] = P.s16(P.div((oldY - s.y) * 16, s.ga[0] * 2))
  s.callbackFn = shadowBallStep
end)

local function lickStep(s)
  local d = s.data
  local r5, r6 = false, false
  if s.animEnded then
    if not s.invisible then s.invisible = true end
    if d[0] == 0 then
      if d[1] == 2 then r5 = true end
    elseif d[0] == 1 then
      if d[1] == 4 then r5 = true end
    else
      r6 = true
    end
    if r5 then
      s.invisible = not s.invisible
      d[2] = d[2] + 1
      d[1] = 0
      if d[2] == 5 then
        d[2] = 0
        d[0] = d[0] + 1
      end
    elseif r6 then
      P.DestroyAnimSprite(s)
    else
      d[1] = d[1] + 1
    end
  end
end

-- pokefirered/src/battle_anim_ghost.c:458
C.Lick = P.cb(function(s, vm)
  P.InitSpritePosToAnimTarget(s, vm, true)
  s.callbackFn = lickStep
end)

local function destinyBondShadowStep(s)
  local d = s.data
  if d[4] ~= 0 then
    d[0] = P.s16(d[0] + d[2])
    d[1] = P.s16(d[1] + d[3])
    s.x = P.shr(d[0], 4)
    s.y = P.shr(d[1], 4)
    d[4] = d[4] - 1
    if d[4] == 0 then d[0] = 0 end
  end
end

-- pokefirered/src/battle_anim_ghost.c:737
C.DestinyBondWhiteShadow = P.cb(function(s, vm)
  local d = s.data
  local b1x, b1y, b2x, b2y
  if s.ga[0] == 0 then
    b1x = P.coordAtk(vm, P.COORD_X)
    b1y = P.coordAtk(vm, P.COORD_Y) + 28
    b2x = P.coordTgt(vm, P.COORD_X)
    b2y = P.coordTgt(vm, P.COORD_Y) + 28
  else
    b1x = P.coordTgt(vm, P.COORD_X)
    b1y = P.coordTgt(vm, P.COORD_Y) + 28
    b2x = P.coordAtk(vm, P.COORD_X)
    b2y = P.coordAtk(vm, P.COORD_Y) + 28
  end
  local yDiff = b2y - b1y
  d[0] = b1x * 16
  d[1] = b1y * 16
  d[2] = P.s16(P.div((b2x - b1x) * 16, s.ga[1]))
  d[3] = P.s16(P.div(yDiff * 16, s.ga[1]))
  d[4] = s.ga[1]
  d[5] = b2x
  d[6] = b2y
  d[7] = P.div(d[4], 2)
  s.pri = 2
  s.x = b1x
  s.y = b1y
  s.callbackFn = destinyBondShadowStep
  s.invisible = true
end)

local function curseNailEnd(s, vm)
  P.setBld(vm, nil)
  P.DestroyAnimSprite(s)
end

local function curseNailStep2(s, vm)
  local d = s.data
  if d[0] == 0 then
    P.setBld(vm, 16, 0)
    d[0] = d[0] + 1
    d[1] = 0
    d[2] = 0
  elseif d[1] < 2 then
    d[1] = d[1] + 1
  else
    d[1] = 0
    d[2] = d[2] + 1
    P.setBld(vm, 16 - d[2], d[2])
    if d[2] == 16 then
      s.invisible = true
      s.callbackFn = curseNailEnd
    end
  end
end

local function curseNailStep1(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
  else
    s.ox = s.ox + d[1]
    local var0 = P.u16(s.ox + 7)
    if var0 > 14 then
      s.x = s.x + s.ox
      s.ox = 0
      s.imageValue = s.imageValue + 8
      d[2] = d[2] + 1
      if d[2] == 3 then
        d[0] = 30
        s.callbackFn = P.WaitAnimForDuration
        P.StoreSpriteCallbackInData6(s, curseNailStep2)
      else
        d[0] = 40
      end
    end
  end
end

-- pokefirered/src/battle_anim_ghost.c:1009
C.CurseNail = P.cb(function(s, vm)
  local xDelta, xDelta2
  P.InitSpritePosToAnimAttacker(s, vm, true)
  if P.atkIsPlayer(vm) then
    xDelta = 24
    xDelta2 = -2
    s._hFlipBase = true
  else
    xDelta = -24
    xDelta2 = 2
  end
  s.x = s.x + xDelta
  s.data[1] = xDelta2
  s.data[0] = 60
  s.callbackFn = curseNailStep1
end)

local function ghostStatusEnd(s, vm)
  P.setBld(vm, nil)
  P.DestroyAnimSprite(s)
end

local function ghostStatusStep(s, vm)
  local d = s.data
  s.ox = P.Sin(d[0], 12)
  if not P.atkIsPlayer(vm) then s.ox = -s.ox end
  d[0] = band(d[0] + 6, 0xFF)
  d[1] = P.s16(d[1] + 0x100)
  s.oy = -P.shr(d[1], 8)
  d[7] = d[7] + 1
  if d[7] == 1 then
    d[6] = 0x050B
    P.setBld(vm, 0x0B, 0x05)
  elseif d[7] > 30 then
    d[2] = d[2] + 1
    local coeffB = P.rshift(P.u16(d[6]), 8)
    local coeffA = band(d[6], 0xFF)
    coeffB = coeffB + 1
    if coeffB > 16 then coeffB = 16 end
    coeffA = P.u16(coeffA - 1)
    if P.s16(coeffA) < 0 then coeffA = 0 end
    P.setBld(vm, coeffA, coeffB)
    d[6] = P.s16(coeffA + coeffB * 256)
    if coeffB == 16 and coeffA == 0 then
      s.invisible = true
      s.callbackFn = ghostStatusEnd
    end
  end
end

-- pokefirered/src/battle_anim_ghost.c:1098
C.GhostStatusSprite = P.cb(ghostStatusStep)

local function grudgeFlame(s)
  local d = s.data
  local task = s.task
  if d[1] == 0 then d[2] = d[2] + 2 else d[2] = d[2] - 2 end
  d[2] = band(d[2], 0xFF)
  s.ox = P.Sin(d[2], d[3])
  local index = P.u16(d[2] - 65)
  local tp = task and task.data[5] or 1
  if index < 127 then s.pri = tp + 1 else s.pri = tp end
  d[5] = d[5] + 1
  d[6] = band(d[5] * 8, 0xFF)
  s.oy = P.Sin(d[6], 7)
  if task and task.data[8] ~= 0 then
    task.data[7] = task.data[7] - 1
    P.DestroyAnimSprite(s)
  end
end

local function grudgeStep(t, vm)
  local d = t.data
  if d[0] == 0 then
    for i = 0, 5 do
      local s = P.CreateSprite(vm, "gGrudgeFlameSpriteTemplate", d[9], d[10], d[6], grudgeFlame)
      if s then
        s.task = t
        s.data[0] = 0
        s.data[1] = P.atkIsPlayer(vm) and 1 or 0
        s.data[2] = band(i * 42, 0xFF)
        s.data[3] = d[11]
        s.data[5] = i * 6
        d[7] = d[7] + 1
      end
    end
    d[0] = d[0] + 1
  elseif d[0] == 1 then
    d[1] = d[1] + 1
    if band(d[1], 1) ~= 0 then
      if d[3] < 14 then d[3] = d[3] + 1 end
    elseif d[4] > 4 then
      d[4] = d[4] - 1
    end
    if d[3] == 14 and d[4] == 4 then
      d[1] = 0
      d[0] = d[0] + 1
    end
    P.setBld(vm, d[3], d[4])
  elseif d[0] == 2 then
    d[1] = d[1] + 1
    if d[1] > 30 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 3 then
    d[1] = d[1] + 1
    if band(d[1], 1) ~= 0 then
      if d[3] > 0 then d[3] = d[3] - 1 end
    elseif d[4] < 16 then
      d[4] = d[4] + 1
    end
    if d[3] == 0 and d[4] == 16 then
      d[8] = 1
      d[0] = d[0] + 1
    end
    P.setBld(vm, d[3], d[4])
  elseif d[0] == 4 then
    if d[7] <= 0 then d[0] = d[0] + 1 end
  elseif d[0] == 5 then
    P.setBld(vm, nil)
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_ghost.c:1142
T.GrudgeFlames = P.task(function(t, vm)
  local d = t.data
  local atk = P.atk(vm)
  d[0] = 0
  d[1] = 16
  d[9] = P.coord(vm, atk, P.COORD_X_2)
  d[10] = P.yWithElevation(vm, atk)
  d[11] = P.div(P.coordAttr(vm, atk, P.ATTR_WIDTH), 2) + 8
  d[7] = 0
  local bp = vm._bgPrio
  d[5] = (bp and bp[require("src.core.game3.battle.anim_coords").bgPriorityRank(atk)]) or 2
  d[6] = P.subpriorityOf(atk) - 2
  d[3] = 0
  d[4] = 16
  P.setBld(vm, 0, 16)
  d[8] = 0
  t.fn = grudgeStep
end)

local function nightShadeTarget(t)
  return t._clone or t._p
end

local function nightShadeApplyAlpha(t)
  local obj = nightShadeTarget(t)
  if not obj then return end
  local a = t.data[2] / 16
  if a > 1 then a = 1 end
  if t._clone then t._clone.alphaMul = nil else t._p.alpha = a end
end

local function nightShadeRotScale(t, v)
  if t._clone then
    t._clone._mat = { v, v, 0 }
    P.sync(t._clone, t._vm)
  else
    P.monRotScale(t._p, v, v, 0)
  end
end

local function nightShadeStep2(t, vm)
  local d = t.data
  if d[1] > 0 then
    d[1] = d[1] - 1
    return
  end
  d[0] = d[0] + 8
  if d[0] <= 0xFF then
    nightShadeRotScale(t, d[0])
  else
    if t._clone then
      P.DestroyAnimSprite(t._clone)
    else
      P.monResetRotScale(t._p)
      t._p.alpha = 1
    end
    P.DestroyAnimVisualTask(t)
    P.setBld(vm, nil)
  end
end

local function nightShadeStep1(t, vm)
  local d = t.data
  d[10] = d[10] + 1
  if d[10] == 3 then
    d[10] = 0
    d[2] = d[2] + 1
    d[3] = d[3] - 1
    P.setBld(vm, d[2], d[3])
    nightShadeApplyAlpha(t)
    if d[2] ~= 9 then return end
    t.fn = nightShadeStep2
  end
end

-- pokefirered/src/battle_anim_ghost.c:335
T.NightShadeClone = P.task(function(t, vm)
  local d = t.data
  local side = P.atk(vm)
  P.setBld(vm, 0, 16)
  t._vm = vm
  t._p = P.monPresent(side)
  if not t._p then
    P.DestroyAnimVisualTask(t)
    return
  end
  if P.isMonBg(side) then
    t._clone = P.CloneMon(vm, side)
    if t._clone then
      t._clone.zOverride = (side == "player") and 195 or 105
    end
  end
  nightShadeRotScale(t, 128)
  if not t._clone then
    t._p.visible = true
    t._p.alpha = 0
  end
  d[0] = 128
  d[1] = t.ga[0]
  d[2] = 0
  d[3] = 16
  t.fn = nightShadeStep1
end)

local function nightmareStep(t, vm)
  local d = t.data
  if d[4] == 0 then
    d[1] = d[1] + 1
    d[5] = band(d[1], 3)
    if d[5] == 1 and d[2] > 0 then d[2] = d[2] - 1 end
    if d[5] == 3 and d[3] <= 15 then d[3] = d[3] + 1 end
    P.setBld(vm, d[2], d[3])
    if d[3] ~= 16 or d[2] ~= 0 then return end
    if d[1] <= 80 then return end
    if t._clone then P.DestroyAnimSprite(t._clone) end
    t._clone = nil
    d[4] = 1
  elseif d[4] == 1 then
    d[6] = d[6] + 1
    if d[6] <= 1 then return end
    P.setBld(vm, nil)
    d[4] = d[4] + 1
  elseif d[4] == 2 then
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_ghost.c:511
T.NightmareClone = P.task(function(t, vm)
  local d = t.data
  local side = P.tgt(vm)
  local c = P.CloneMon(vm, side)
  if not c then
    P.DestroyAnimVisualTask(t)
    return
  end
  t._clone = c
  d[1] = 0
  d[2] = 15
  d[3] = 2
  d[4] = 0
  P.setBld(vm, d[2], d[3])
  c.data[0] = 80
  if side == "player" then
    c.data[1] = -144
    c.data[2] = 112
  else
    c.data[1] = 144
    c.data[2] = -112
  end
  c.data[3] = 0
  c.data[4] = 0
  P.StoreSpriteCallbackInData6(c, function() end)
  c.callbackFn = P.TranslateSpriteLinearFixedPoint
  t.fn = nightmareStep
end)

local function spiteStep3(t, vm)
  local d = t.data
  local k = d[15]
  if k == 0 then
    t._wave = nil
    if t._p then t._p.hShift = nil end
  elseif k == 1 then
    if not P.isMonBg(t._side) then P.monBlend(t._p, 0, 0) end
  elseif k == 2 then
    if t._clone then P.DestroyAnimSprite(t._clone) end
    t._clone = nil
    if t._p then t._p.alpha = 1 end
    P.setBld(vm, nil)
    P.DestroyAnimVisualTask(t)
  end
  d[15] = d[15] + 1
end

local function spiteApplyWave(t)
  if t._wave and t._p and P.isMonBg(t._side) then
    t._p.hShift = P.hShiftFromHofs(t._wave:step(0))
  elseif t._wave then
    t._wave:step(0)
  end
end

local function spiteApplyAlpha(t, vm)
  if t._p and P.isMonBg(t._side) then
    t._p.alpha = P.bldAlphaValue(vm)
  end
end

local function spiteStep2(t, vm)
  local d = t.data
  d[1] = d[1] + 1
  d[5] = band(d[1], 1)
  local sine = P.SINE[(d[1] % 256) + 1]
  if d[5] == 0 then d[2] = P.div(sine, 18) end
  if d[5] == 1 then d[3] = 16 - P.div(sine, 18) end
  P.setBld(vm, d[2], d[3])
  spiteApplyAlpha(t, vm)
  spiteApplyWave(t)
  if d[1] == 128 then
    d[15] = 0
    t.fn = spiteStep3
    spiteStep3(t, vm)
  end
end

local function spiteStep1(t, vm)
  local d = t.data
  local k = d[15]
  if k == 0 then
    local c = P.CloneMon(vm, t._side)
    if not c then
      P.DestroyAnimVisualTask(t)
      return
    end
    t._clone = c
    c.objBlend = nil
    c._objBlend = false
    c.zOverride = 2
    c.invisible = P.monHidden(vm, t._side)
    d[1] = 0
    d[2] = 0
    d[3] = 16
    d[15] = d[15] + 1
  elseif k == 1 then
    if not P.isMonBg(t._side) then P.monBlend(t._p, 10, 13 + 15 * 1024) end
    d[15] = d[15] + 1
  elseif k == 2 then
    local mc, my = P.monCenter(vm, t._side)
    local startLine = math.floor(my) - 32
    if startLine < 0 then startLine = 0 end
    t._wave = P.Wave(startLine, startLine + 64, 2, 6, 0)
    d[15] = d[15] + 1
  elseif k == 3 then
    P.setBld(vm, 0, 16)
    spiteApplyAlpha(t, vm)
    d[15] = d[15] + 1
  elseif k == 4 then
    t.fn = spiteStep2
    d[15] = d[15] + 1
  else
    d[15] = d[15] + 1
  end
  spiteApplyWave(t)
end

-- pokefirered/src/battle_anim_ghost.c:584
T.SpiteTargetShadow = P.task(function(t, vm)
  t._side = P.tgt(vm)
  t._p = P.monPresent(t._side)
  t.data[15] = 0
  t.fn = spiteStep1
  spiteStep1(t, vm)
end)

local function dbwsTaskStep(t, vm)
  local d = t.data
  if d[0] == 0 then
    if d[6] == 0 then
      d[5] = d[5] + 1
      if d[5] > 1 then
        d[5] = 0
        d[7] = d[7] + 1
        if band(d[7], 1) ~= 0 then
          if d[8] < 16 then d[8] = d[8] + 1 end
        else
          if d[9] ~= 0 then d[9] = d[9] - 1 end
        end
        P.setBld(vm, d[8], d[9])
        if d[7] >= 24 then
          d[7] = 0
          d[6] = 1
        end
      end
    end
    if d[10] ~= 0 then
      d[10] = d[10] - 1
    elseif d[6] ~= 0 then
      d[0] = d[0] + 1
    end
  elseif d[0] == 1 then
    d[5] = d[5] + 1
    if d[5] > 1 then
      d[5] = 0
      d[7] = d[7] + 1
      if band(d[7], 1) ~= 0 then
        if d[8] ~= 0 then d[8] = d[8] - 1 end
      elseif d[9] < 16 then
        d[9] = d[9] + 1
      end
      P.setBld(vm, d[8], d[9])
      if d[8] == 0 and d[9] == 16 then
        for _, s in ipairs(t._sprites or {}) do
          if s.active then P.DestroyAnimSprite(s) end
        end
        d[0] = d[0] + 1
      end
    end
  elseif d[0] == 2 then
    d[5] = d[5] + 1
    if d[5] > 0 then d[0] = d[0] + 1 end
  elseif d[0] == 3 then
    P.setBld(vm, nil)
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_ghost.c:786
T.DestinyBondWhiteShadow = P.task(function(t, vm)
  local d = t.data
  P.setBld(vm, 0, 16)
  d[5], d[6], d[7], d[8] = 0, 0, 0, 0
  d[9] = 16
  d[10] = t.ga[0]
  local atk = P.atkId(vm)
  local baseX = P.coord(vm, atk, P.COORD_X_2)
  local baseY = P.coordAttr(vm, atk, P.ATTR_BOTTOM)
  t._sprites = {}
  for other = 0, 3 do
    if other ~= atk and other ~= P.bxor(atk, 2) and not P.monHidden(vm, other) then
      local s = P.CreateSprite(vm, "gDestinyBondWhiteShadowSpriteTemplate", baseX, baseY, 55, destinyBondShadowStep)
      if s then
        local x = P.coord(vm, other, P.COORD_X_2)
        local y = P.coordAttr(vm, other, P.ATTR_BOTTOM)
        s.data[0] = P.s16(baseX * 16)
        s.data[1] = P.s16(baseY * 16)
        s.data[2] = P.s16(P.div((x - baseX) * 16, t.ga[1]))
        s.data[3] = P.s16(P.div((y - baseY) * 16, t.ga[1]))
        s.data[4] = t.ga[1]
        s.data[5] = x
        s.data[6] = y
        t._sprites[#t._sprites + 1] = s
        d[12] = d[12] + 1
      end
    end
  end
  t.fn = dbwsTaskStep
end)

local function curseDraw(t)
  if not (love and love.graphics) then return end
  local w = t._win
  if not w then return end
  local l, r, tp, b = w[1], w[2], w[3], w[4]
  if r > l and b > tp then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", l, tp, r - l, b - tp)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

local function curseStep2(t, vm)
  t._win = nil
  t.draw = nil
  P.DestroyAnimVisualTask(t)
end

local function trunc(v)
  if v >= 0 then return math.floor(v) end
  return -math.floor(-v)
end

local function curseStep1(t, vm)
  local d = t.data
  local step = d[0]
  d[0] = d[0] + 1
  local left, right, top, bottom
  if step < 16 then
    left = P.u16(trunc(d[5] - (d[1] * 0.0625) * step))
    right = P.u16(trunc(d[5] + (d[2] * 0.0625) * step))
    top = P.u16(trunc(d[6] - (d[3] * 0.0625) * step))
    bottom = P.u16(trunc(d[6] + (d[4] * 0.0625) * step))
  else
    left, right, top, bottom = 0, 240, 0, 112
    P.bgBlend(16, 0)
    t.fn = curseStep2
  end
  t._win = { left, math.min(right, 240), top, math.min(bottom, 160) }
end

-- pokefirered/src/battle_anim_ghost.c:926
T.CurseStretchingBlackBg = P.task(function(t, vm)
  local d = t.data
  local startX
  if not P.atkIsPlayer(vm) then startX = 40 else startX = 200 end
  local startY = 40
  d[1] = startX
  d[2] = 240 - startX
  d[3] = startY
  d[4] = 72
  d[5] = startX
  d[6] = startY
  t._win = { startX, startX, startY, startY }
  t.z = 1
  t.draw = curseDraw
  t.fn = curseStep1
end)

return { callbacks = C, tasks = T }
