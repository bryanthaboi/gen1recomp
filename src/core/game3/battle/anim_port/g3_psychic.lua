local P = require("src.core.game3.battle.anim_port.g3_pret")

local C, T = {}, {}
local band = P.band

local function gSine(i)
  if i < 0 then return 0 end
  if i < 320 then return P.SINE[(i % 256) + 1] end
  return P.Sin2(i - 320)
end

local function wallRestoreEnemy(s, vm)
  local p = s._wallEnemy
  if not p then return end
  s._wallEnemy = nil
  if vm and vm._monbg and vm._monbg.enemy then return end
  if p.z == 10 then p.z = s._wallEnemyZ or 20 end
end

local function defensiveWallStep5(s, vm)
  wallRestoreEnemy(s, vm)
  s.callbackFn = P.DestroyAnimSprite
end

local function defensiveWallStep4(s, vm)
  P.setBld(vm, s.data[3], 16 - s.data[3])
  s.data[3] = s.data[3] - 1
  if s.data[3] == -1 then
    local p = s._wallEnemy
    if p then p.visible = true end
    s.invisible = true
    s.callbackFn = defensiveWallStep5
  end
end

local function defensiveWallStep3(s)
  local d = s.data
  d[1] = d[1] + 1
  if d[1] == 2 then
    d[1] = 0
    local AnimPal = require("src.core.game3.battle.anim_pal")
    local f = s._wallPal and AnimPal.writeFaded(s._wallPal)
    if f then
      local color = f[8]
      for i = 8, 1, -1 do f[i] = f[i - 1] end
      f[1] = color
    end
    d[2] = d[2] + 1
    if d[2] == 16 then s.callbackFn = defensiveWallStep4 end
  end
end

local function defensiveWallStep2(s, vm)
  P.setBld(vm, s.data[3], 16 - s.data[3])
  if s.data[3] == 13 then
    s.callbackFn = defensiveWallStep3
  else
    s.data[3] = s.data[3] + 1
  end
end

-- pokefirered/src/battle_anim_psychic.c:419
C.DefensiveWall = P.cb(function(s, vm)
  if P.atkIsPlayer(vm) then
    s.pri = 2
    s.sub = 200
    s.zOverride = 101
  end
  local p = P.monPresent("enemy")
  if p and p.visible ~= false then
    s._wallEnemy = p
    if p.z ~= 10 then
      s._wallEnemyZ = p.z
      p.z = 10
    else
      s._wallEnemyZ = p._g4OrigZ or 20
    end
  end
  if not P.atkIsPlayer(vm) then s.ga[0] = -s.ga[0] end
  s.x = P.coordAtk(vm, P.COORD_X) + s.ga[0]
  s.y = P.coordAtk(vm, P.COORD_Y) + s.ga[1]
  s.data[0] = s.ga[2]
  s._wallPal = require("src.core.game3.battle.anim_pal").tagName(s.ga[2])
  s.callbackFn = defensiveWallStep2
  defensiveWallStep2(s, vm)
end)

-- pokefirered/src/battle_anim_psychic.c:538
C.WallSparkle = P.cb(function(s, vm)
  if s.data[0] == 0 then
    local respect = s.ga[3] == 0
    if s.ga[2] == 0 then
      P.InitSpritePosToAnimAttacker(s, vm, respect)
    else
      P.InitSpritePosToAnimTarget(s, vm, respect)
    end
    s.data[0] = s.data[0] + 1
  elseif s.animEnded or s.affineAnimEnded then
    P.DestroySpriteAndMatrix(s)
  end
end)

-- pokefirered/src/battle_anim_psychic.c:575
C.BentSpoon = P.cb(function(s, vm)
  s.x = P.coordAtk(vm, P.COORD_X_2)
  s.y = P.coordAtk(vm, P.COORD_Y_PIC)
  if not P.atkIsPlayer(vm) then
    P.StartSpriteAnim(s, 1)
    s.x = s.x - 40
    s.y = s.y + 10
    s.data[1] = -1
  else
    s.x = s.x + 40
    s.y = s.y - 10
    s.data[1] = 1
  end
  P.StoreSpriteCallbackInData6(s, P.DestroyAnimSprite)
  s.callbackFn = P.RunStoredCallbackWhenAnimEnds
end)

local function questionMarkStep2(s)
  local d = s.data
  if d[0] == 0 then
    if s.affineAnimEnded then
      s._aff = 0
      s._mat = nil
      d[1] = 18
      d[0] = d[0] + 1
    end
  elseif d[0] == 1 then
    d[1] = d[1] - 1
    if d[1] == -1 then P.DestroyAnimSprite(s) end
  end
end

local function questionMarkStep1(s)
  s._aff = 1
  s._affine = { P.data().affine.sAffineAnim_QuestionMark }
  s.data[0] = 0
  P.StartSpriteAffineAnim(s, 0)
  s.callbackFn = questionMarkStep2
end

-- pokefirered/src/battle_anim_psychic.c:597
C.QuestionMark = P.cb(function(s, vm)
  local atk = P.atk(vm)
  local x = P.s16(P.div(P.coordAttr(vm, atk, P.ATTR_WIDTH), 2))
  local y = P.s16(P.div(P.coordAttr(vm, atk, P.ATTR_HEIGHT), -2))
  if not P.isPlayer(atk) then x = -x end
  s.x = P.coord(vm, atk, P.COORD_X_2) + x
  s.y = P.coord(vm, atk, P.COORD_Y_PIC) + y
  if s.y < 16 then s.y = 16 end
  P.StoreSpriteCallbackInData6(s, questionMarkStep1)
  s.callbackFn = P.RunStoredCallbackWhenAnimEnds
end)

local function prepareAffineAnimInTaskData(t, vm, side, cmds)
  local d = t.data
  d[7] = 0
  d[8] = 0
  d[9] = 0
  d[15] = 0
  d[10] = 0x100
  d[11] = 0x100
  d[12] = 0
  t._affSide = side
  t._affP = P.monPresent(side)
  t._affCmds = cmds
end

local function runAffineAnimFromTaskData(t, vm)
  local d = t.data
  local cmds = t._affCmds
  local p = t._affP
  local idx = d[7]
  local c = cmds[idx + 1]
  if not c or c.e then
    if p then p.oy = 0 end
    P.monResetRotScale(p)
    return false
  elseif c.j then
    d[7] = c.j
  elseif c.l then
    if c.l ~= 0 then
      if d[9] ~= 0 then
        d[9] = d[9] - 1
        if d[9] == 0 then
          d[7] = d[7] + 1
          return true
        end
      else
        d[9] = c.l
      end
      if d[7] == 0 then return true end
      while true do
        d[7] = d[7] - 1
        idx = idx - 1
        local prev = cmds[idx + 1]
        if prev and prev.l then
          d[7] = d[7] + 1
          return true
        end
        if d[7] == 0 then return true end
      end
    end
    d[7] = d[7] + 1
  else
    if P.u8(c.d or 0) == 0 then
      d[10] = c.x
      d[11] = c.y
      d[12] = P.u8(c.r or 0)
      d[7] = d[7] + 1
      idx = idx + 1
      c = cmds[idx + 1] or c
    end
    d[10] = P.s16(d[10] + (c.x or 0))
    d[11] = P.s16(d[11] + (c.y or 0))
    d[12] = P.s16(d[12] + P.u8(c.r or 0))
    P.monRotScale(p, d[10], d[11], P.u16(d[12]))
    P.monYOffsetFromYScale(vm, t._affSide)
    d[8] = d[8] + 1
    if d[8] >= P.u8(c.d or 0) then
      d[8] = 0
      d[7] = d[7] + 1
    end
  end
  return true
end

local function meditateStep(t, vm)
  if not runAffineAnimFromTaskData(t, vm) then P.DestroyAnimVisualTask(t) end
end

-- pokefirered/src/battle_anim_psychic.c:641
T.MeditateStretchAttacker = P.task(function(t, vm)
  t.data[0] = 0
  prepareAffineAnimInTaskData(t, vm, P.atk(vm), P.data().affine.sAffineAnim_MeditateStretchAttacker)
  t.fn = meditateStep
end)

local function teleportStep(t, vm)
  local d = t.data
  if d[1] == 0 then
    runAffineAnimFromTaskData(t, vm)
    d[2] = d[2] + 1
    if d[2] > 19 then d[1] = d[1] + 1 end
  elseif d[1] == 1 then
    local p = t._affP
    if d[3] ~= 0 then
      if p then p.oy = p.oy - 8 end
      d[3] = d[3] - 1
    else
      if p then
        p.visible = false
        p.ox = (240 + 32) - P.coord(vm, t._affSide, P.COORD_X_2)
      end
      P.monResetRotScale(p)
      P.DestroyAnimVisualTask(t)
    end
  end
end

-- pokefirered/src/battle_anim_psychic.c:657
T.Teleport = P.task(function(t, vm)
  local d = t.data
  d[0] = 0
  d[1] = 0
  d[2] = 0
  d[3] = P.atkIsPlayer(vm) and 8 or 4
  prepareAffineAnimInTaskData(t, vm, P.atk(vm), P.data().affine.sAffineAnim_Teleport)
  t.fn = teleportStep
end)

local function imprisonOrbsStep(t, vm)
  local d = t.data
  local k = d[0]
  if k == 0 then
    d[1] = d[1] + 1
    if d[1] > 8 then
      d[1] = 0
      local s = P.CreateSprite(vm, "sImprisonOrbSpriteTemplate", d[13], d[14], 0, nil)
      t._orbs[d[2]] = s
      if s then
        local r = d[12]
        if d[2] == 0 then
          s.ox, s.oy = r, -r
        elseif d[2] == 1 then
          s.ox, s.oy = -r, r
        elseif d[2] == 2 then
          s.ox, s.oy = r, r
        elseif d[2] == 3 then
          s.ox, s.oy = -r, -r
        end
      end
      d[2] = d[2] + 1
      if d[2] == 5 then d[0] = d[0] + 1 end
    end
  elseif k == 1 then
    if band(d[1], 1) ~= 0 then
      d[3] = d[3] - 1
    else
      d[4] = d[4] + 1
    end
    P.setBld(vm, d[3], d[4])
    d[1] = d[1] + 1
    if d[1] == 32 then
      for i = 0, 4 do
        local s = t._orbs[i]
        if s and s.active then P.DestroyAnimSprite(s) end
      end
      d[0] = d[0] + 1
    end
  elseif k == 2 then
    d[0] = d[0] + 1
  elseif k == 3 then
    P.setBld(vm, nil)
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_psychic.c:698
T.ImprisonOrbs = P.task(function(t, vm)
  local d = t.data
  local atk = P.atk(vm)
  d[3] = 16
  d[4] = 0
  d[13] = P.coord(vm, atk, P.COORD_X_2)
  d[14] = P.coord(vm, atk, P.COORD_Y_PIC)
  local var0 = P.u16(P.div(P.coordAttr(vm, atk, P.ATTR_WIDTH), 3))
  local var1 = P.u16(P.div(P.coordAttr(vm, atk, P.ATTR_HEIGHT), 3))
  d[12] = var0 > var1 and var0 or var1
  P.setBld(vm, 16, 0)
  t._orbs = {}
  t.fn = imprisonOrbsStep
end)

local function redXStep(s)
  local d = s.data
  if d[1] > d[0] - 10 then s.invisible = band(d[1], 1) ~= 0 end
  if d[1] == d[0] then
    P.DestroyAnimSprite(s)
    return
  end
  d[1] = d[1] + 1
end

-- pokefirered/src/battle_anim_psychic.c:790
C.RedX = P.cb(function(s, vm)
  if s.ga[0] == 0 then
    s.x = P.coordAtk(vm, P.COORD_X_2)
    s.y = P.coordAtk(vm, P.COORD_Y_PIC)
  end
  s.data[0] = s.ga[1]
  s.callbackFn = redXStep
end)

local function skillSwapOrb(s)
  if P.TranslateAnimHorizontalArc(s) then P.DestroyAnimSprite(s) end
end

local function skillSwapStep(t, vm)
  local d = t.data
  if d[0] == 0 then
    d[1] = d[1] + 1
    if d[1] > 6 then
      d[1] = 0
      local s = P.CreateSprite(vm, "sSkillSwapOrbSpriteTemplate", d[11], d[12], 0, skillSwapOrb)
      if s then
        s.data[0] = 16
        s.data[2] = d[13]
        s.data[4] = d[14]
        s.data[5] = d[10]
        P.InitAnimArcTranslation(s)
        P.StartSpriteAffineAnim(s, band(d[2], 3))
      end
      d[2] = d[2] + 1
      if d[2] == 12 then d[0] = d[0] + 1 end
    end
  elseif d[0] == 1 then
    d[1] = d[1] + 1
    if d[1] > 17 then P.DestroyAnimVisualTask(t) end
  end
end

-- pokefirered/src/battle_anim_psychic.c:801
T.SkillSwap = P.task(function(t, vm)
  local d = t.data
  local atk, tgt = P.atk(vm), P.tgt(vm)
  if t.ga[0] == 1 then
    d[10] = -10
    d[11] = P.coordAttr(vm, tgt, P.ATTR_LEFT) + 8
    d[12] = P.coordAttr(vm, tgt, P.ATTR_TOP) + 8
    d[13] = P.coordAttr(vm, atk, P.ATTR_LEFT) + 8
    d[14] = P.coordAttr(vm, atk, P.ATTR_TOP) + 8
  else
    d[10] = 10
    d[11] = P.coordAttr(vm, atk, P.ATTR_RIGHT) - 8
    d[12] = P.coordAttr(vm, atk, P.ATTR_BOTTOM) - 8
    d[13] = P.coordAttr(vm, tgt, P.ATTR_RIGHT) - 8
    d[14] = P.coordAttr(vm, tgt, P.ATTR_BOTTOM) - 8
  end
  d[1] = 6
  t.fn = skillSwapStep
end)

local function extrasensoryApply(t)
  local p = t._p
  if not p then return end
  if t._rows and P.isMonBg(t._side) then
    p.hShift = P.hShiftFromHofs(t._rows)
  elseif p.hShift == t._shift then
    p.hShift = nil
  end
  t._shift = p.hShift
end

local function extrasensoryStep(t, vm)
  local d = t.data
  if d[0] == 0 then
    local sineIndex = d[13]
    for i = d[14], d[15] do
      local var2 = P.s16(P.shr(gSine(sineIndex), d[12]))
      if var2 > 0 then
        var2 = var2 + band(d[1], 3)
      elseif var2 < 0 then
        var2 = var2 - band(d[1], 3)
      end
      t._rows[i] = var2
      sineIndex = P.s16(sineIndex + d[11])
    end
    extrasensoryApply(t)
    d[1] = d[1] + 1
    if d[1] > 23 then d[0] = d[0] + 1 end
  elseif d[0] == 1 then
    t._rows = nil
    extrasensoryApply(t)
    d[0] = d[0] + 1
  elseif d[0] == 2 then
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_psychic.c:891
T.ExtrasensoryDistortion = P.task(function(t, vm)
  local d = t.data
  local side = P.tgt(vm)
  local yOffset = P.u8(P.yWithElevation(vm, side))
  d[14] = yOffset - 32
  local a = t.ga[0]
  if a == 0 then
    d[11], d[12], d[13], d[15] = 2, 5, 64, yOffset + 32
  elseif a == 1 then
    d[11], d[12], d[13], d[15] = 2, 5, 192, yOffset + 32
  elseif a == 2 then
    d[11], d[12], d[13], d[15] = 4, 4, 0, yOffset + 32
  end
  if d[14] < 0 then d[14] = 0 end
  d[10] = 0
  t._side = side
  t._p = P.monPresent(side)
  t._rows = {}
  for i = d[14], d[14] + 64 do t._rows[i] = 0 end
  extrasensoryApply(t)
  t.fn = extrasensoryStep
end)

local function cloneYOffset(t, vm)
  local c = t._clone
  local var = 64 - P.yDelta(vm, t._side) * 2
  local dd = t.data[2]
  local var2 = (dd == 0) and 0 or P.div(var * 256, dd)
  if var2 > 128 then var2 = 128 end
  c.oy = P.div(var - var2, 2)
end

local function transparentCloneStep(t, vm)
  local d = t.data
  local c = t._clone
  if d[0] == 0 then
    d[1] = d[1] + 4
    d[2] = 256 - P.shr(gSine(d[1]), 1)
    c._mat = { d[2], d[2], 0 }
    cloneYOffset(t, vm)
    if d[1] == 48 then d[0] = d[0] + 1 end
  elseif d[0] == 1 then
    d[1] = d[1] - 4
    d[2] = 256 - P.shr(gSine(d[1]), 1)
    c._mat = { d[2], d[2], 0 }
    cloneYOffset(t, vm)
    if d[1] == 0 then d[0] = d[0] + 1 end
  elseif d[0] == 2 then
    if c and c.active then P.DestroyAnimSprite(c) end
    t._clone = nil
    d[0] = d[0] + 1
  elseif d[0] == 3 then
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_psychic.c:981
T.TransparentCloneGrowAndShrink = P.task(function(t, vm)
  local side = P.side(vm, t.ga[0])
  local c = side and P.CloneMon(vm, side)
  if not c then
    P.DestroyAnimVisualTask(t)
    return
  end
  c.callbackFn = nil
  c._aff = 3
  c.affineAnimPaused = true
  c._mat = { 256, 256, 0 }
  t._clone = c
  t._side = side
  t.data[13] = 0
  t.data[14] = 0
  t.data[15] = 0
  t.fn = transparentCloneStep
end)

-- pokefirered/src/battle_anim_psychic.c:1046
C.PsychoBoost = P.cb(function(s, vm)
  local d = s.data
  local k = d[0]
  if k == 0 then
    s.x = P.coordAtk(vm, P.COORD_X)
    s.y = P.coordAtk(vm, P.COORD_Y)
    d[1] = 8
    P.setBld(vm, d[1], 16 - d[1])
    d[0] = d[0] + 1
  elseif k == 1 then
    if s.affineAnimEnded then
      P.playSEPan(vm, "SE_M_TELEPORT", -64)
      P.ChangeSpriteAffineAnim(s, 1)
      d[0] = d[0] + 1
    end
  elseif k == 2 then
    local old = d[2]
    d[2] = d[2] + 1
    if old > 1 then
      d[2] = 0
      d[1] = d[1] - 1
      P.setBld(vm, d[1], 16 - d[1])
      if d[1] == 0 then
        d[0] = d[0] + 1
        s.invisible = true
      end
    end
    d[3] = d[3] + 0x380
    s.oy = s.oy - P.shr(d[3], 8)
    d[3] = band(d[3], 0xFF)
  elseif k == 3 then
    P.setBld(vm, nil)
    P.DestroyAnimSprite(s)
  end
end)

return { callbacks = C, tasks = T }
