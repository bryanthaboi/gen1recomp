local P = require("src.core.game3.battle.anim_port.g3_pret")

local C, T = {}, {}
local H = {}
local band = P.band

function H.affineTable(name)
  return P.data().affine[name]
end

function H.PrepareAffineAnimInTaskData(t, side, cmds)
  local d = t.data
  d[7] = 0
  d[8] = 0
  d[9] = 0
  d[10] = 0x100
  d[11] = 0x100
  d[12] = 0
  t._affSide = side
  t._affCmds = cmds or {}
end

function H.RunAffineAnimFromTaskData(t, vm)
  local d = t.data
  local cmds = t._affCmds
  local side = t._affSide
  local p = P.monPresent(side)
  local c = cmds[d[7] + 1]
  if c == nil or c.e then
    if p then
      p.oy = 0
      P.monResetRotScale(p)
    end
    return false
  end
  if c.j then
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
        local q = cmds[d[7] + 1]
        if q and q.l then
          d[7] = d[7] + 1
          return true
        end
        if d[7] == 0 then return true end
      end
    end
    d[7] = d[7] + 1
  else
    if (c.d or 0) == 0 then
      d[10] = c.x or 0
      d[11] = c.y or 0
      d[12] = P.u8(c.r or 0)
      d[7] = d[7] + 1
      c = cmds[d[7] + 1] or c
    end
    d[10] = P.s16(d[10] + (c.x or 0))
    d[11] = P.s16(d[11] + (c.y or 0))
    d[12] = P.s16(d[12] + P.u8(c.r or 0))
    if p then
      P.monRotScale(p, d[10], d[11], P.u16(d[12]))
      P.monYOffsetFromYScale(vm, side)
    end
    d[8] = d[8] + 1
    if d[8] >= (c.d or 0) then
      d[8] = 0
      d[7] = d[7] + 1
    end
  end
  return true
end

function H.deformTask(tableName)
  return P.task(function(t, vm)
    if t.data[0] == 0 then
      H.PrepareAffineAnimInTaskData(t, P.atk(vm), H.affineTable(tableName))
      t.data[0] = t.data[0] + 1
    elseif not H.RunAffineAnimFromTaskData(t, vm) then
      P.DestroyAnimVisualTask(t)
    end
  end)
end

function H.blackSmokeStep(s)
  local d = s.data
  if d[1] > 0 then
    s.ox = P.shr(d[2], 8)
    d[2] = P.s16(d[2] + d[0])
    s.invisible = not s.invisible
    d[1] = d[1] - 1
  else
    P.DestroyAnimSprite(s)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1171
C.BlackSmoke = P.cb(function(s, vm)
  s.x = s.x + s.ga[0]
  s.y = s.y + s.ga[1]
  if s.ga[3] == 0 then
    s.data[0] = s.ga[2]
  else
    s.data[0] = -s.ga[2]
  end
  s.data[1] = s.ga[4]
  s.callbackFn = H.blackSmokeStep
end)

function H.smokescreenImpactPart(s)
  if s.animEnded then
    P.DestroyAnimSprite(s)
  end
end

function H.SmokescreenImpact(vm, x, y)
  local spots = { { x - 16, y - 16 }, { x, y - 16 }, { x - 16, y }, { x, y } }
  for i = 1, 4 do
    local s = P.CreateSprite(vm, "sSmokescreenImpactSpriteTemplate", spots[i][1], spots[i][2], 2, H.smokescreenImpactPart)
    if s then
      s._baseW, s._baseH, s.w, s.h = 16, 16, 16, 16
      s.pri = 1
      if i > 1 then P.StartSpriteAnim(s, i - 1) end
      P.animate(s)
      P.sync(s, vm)
    end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1199
T.SmokescreenImpact = P.task(function(t, vm)
  H.SmokescreenImpact(vm, P.coordTgt(vm, P.COORD_X_2) + 8, P.coordTgt(vm, P.COORD_Y_PIC) + 8)
  P.DestroyAnimVisualTask(t)
end)

function H.whiteHaloStep2(s, vm)
  P.setBld(vm, nil)
  P.DestroyAnimSprite(s)
end

function H.whiteHaloStep1(s, vm)
  P.setBld(vm, s.data[1], 16 - s.data[1])
  s.data[1] = s.data[1] - 1
  if s.data[1] < 0 then
    s.invisible = true
    s.callbackFn = H.whiteHaloStep2
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1208
C.WhiteHalo = P.cb(function(s, vm)
  s.data[0] = 90
  s.callbackFn = P.WaitAnimForDuration
  s.data[1] = 7
  P.StoreSpriteCallbackInData6(s, H.whiteHaloStep1)
  P.setBld(vm, s.data[1], 16 - s.data[1])
end)

-- pokefirered/src/battle_anim_effects_3.c:1235
C.TealAlert = P.cb(function(s, vm)
  local x = P.u8(P.coordTgt(vm, P.COORD_X_2))
  local y = P.u8(P.coordTgt(vm, P.COORD_Y_PIC))
  P.InitSpritePosToAnimTarget(s, vm, true)
  local rotation = P.ArcTan2Neg(P.s16(s.x - x), P.s16(s.y - y))
  rotation = P.u16(rotation + 0x6000)
  P.TrySetSpriteRotScale(s, false, 0x100, 0x100, rotation)
  s.data[0] = s.ga[2]
  s.data[2] = x
  s.data[4] = y
  s.callbackFn = P.StartAnimLinearTranslation
  P.StoreSpriteCallbackInData6(s, P.DestroyAnimSprite)
end)

function H.meanLookStep4(s, vm)
  local d = s.data
  P.setBld(vm, d[0], 16 - d[0])
  local r = d[1]
  d[1] = d[1] + 1
  if r > 1 then
    d[0] = d[0] - 1
    d[1] = 0
  end
  if d[0] == 0 then s.invisible = true end
  if d[0] < 0 then
    P.setBld(vm, nil)
    P.DestroyAnimSprite(s)
  end
end

function H.meanLookStep3(s, vm)
  local d = s.data
  local k = d[3]
  if k == 0 or k == 1 then
    s.ox, s.oy = 1, 0
  elseif k == 2 or k == 3 then
    s.ox, s.oy = -1, 0
  elseif k == 4 or k == 5 then
    s.ox, s.oy = 0, 1
  else
    s.ox, s.oy = 0, -1
  end
  d[3] = d[3] + 1
  if d[3] > 7 then d[3] = 0 end
  local r = d[4]
  d[4] = d[4] + 1
  if r > 15 then
    d[0] = 16
    d[1] = 0
    P.setBld(vm, d[0], 0)
    s.callbackFn = H.meanLookStep4
  end
end

function H.meanLookStep2(s)
  local r = s.data[2]
  s.data[2] = s.data[2] + 1
  if r > 9 then
    s.invisible = false
    s.affineAnimPaused = false
    if s.affineAnimEnded then s.callbackFn = H.meanLookStep3 end
  end
end

function H.meanLookStep1(s, vm)
  local d = s.data
  P.setBld(vm, d[0], 16 - d[0])
  if d[1] ~= 0 then d[0] = d[0] - 1 else d[0] = d[0] + 1 end
  if d[0] == 15 or d[0] == 4 then d[1] = P.bxor(d[1], 1) end
  local r = d[2]
  d[2] = d[2] + 1
  if r > 70 then
    P.setBld(vm, nil)
    P.StartSpriteAffineAnim(s, 1)
    d[2] = 0
    s.invisible = true
    s.affineAnimPaused = true
    s.callbackFn = H.meanLookStep2
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1255
C.MeanLookEye = P.cb(function(s, vm)
  P.setBld(vm, 0, 16)
  s.data[0] = 4
  s.callbackFn = H.meanLookStep1
end)

function H.spikesStep2(s)
  if band(s.data[1], 1) ~= 0 then s.invisible = not s.invisible end
  s.data[1] = s.data[1] + 1
  if s.data[1] == 16 then P.DestroyAnimSprite(s) end
end

function H.spikesStep1(s)
  if P.TranslateAnimHorizontalArc(s) then
    s.data[0] = 30
    s.data[1] = 0
    s.callbackFn = P.WaitAnimForDuration
    P.StoreSpriteCallbackInData6(s, H.spikesStep2)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1413
C.Spikes = P.cb(function(s, vm)
  P.InitSpritePosToAnimAttacker(s, vm, true)
  local tx = P.coordTgt(vm, P.COORD_X)
  local ty = P.coordTgt(vm, P.COORD_Y)
  local x = P.u16(P.div(tx + tx, 2))
  local y = P.u16(P.div(ty + ty, 2))
  if not P.atkIsPlayer(vm) then s.ga[2] = -s.ga[2] end
  s.data[0] = s.ga[4]
  s.data[2] = x + s.ga[2]
  s.data[4] = y + s.ga[3]
  s.data[5] = -50
  P.InitAnimArcTranslation(s)
  s.callbackFn = H.spikesStep1
end)

-- pokefirered/src/battle_anim_effects_3.c:1451
C.Leer = P.cb(function(s, vm)
  P.SetSpriteCoordsToAnimAttackerCoords(s, vm)
  P.SetAnimSpriteInitialXOffset(s, vm, s.ga[0])
  s.y = s.y + s.ga[1]
  s.callbackFn = P.RunStoredCallbackWhenAnimEnds
  P.StoreSpriteCallbackInData6(s, P.DestroyAnimSprite)
end)

function H.letterZ(s, vm)
  local d = s.data
  if d[0] == 0 then
    P.SetSpriteCoordsToAnimAttackerCoords(s, vm)
    P.SetAnimSpriteInitialXOffset(s, vm, s.ga[0])
    if P.atkIsPlayer(vm) then
      d[1] = s.ga[2]
      d[2] = s.ga[3]
    else
      d[1] = P.s16(-1 * s.ga[2])
      d[2] = P.s16(-1 * s.ga[3])
    end
  end
  d[0] = P.s16(d[0] + 1)
  local var0 = band(d[0] * 20, 0xFF)
  d[3] = P.s16(d[3] + d[1])
  d[4] = P.s16(d[4] + d[2])
  s.ox = P.s16(P.div(d[3], 2))
  s.oy = P.s16(P.Sin(band(var0, 0xFF), 5) + P.div(d[4], 2))
  if P.u16(s.x + s.ox) > 240 then P.DestroyAnimSprite(s) end
end

-- pokefirered/src/battle_anim_effects_3.c:1460
C.LetterZ = P.cb(H.letterZ)

-- pokefirered/src/battle_anim_effects_3.c:1498
C.Fang = P.cb(function(s)
  if s.animEnded then P.DestroyAnimSprite(s) end
end)

-- pokefirered/src/battle_anim_effects_3.c:1504
T.IsTargetPlayerSide = P.task(function(t, vm)
  if P.tgtIsPlayer(vm) then P.setRet(vm, 1) else P.setRet(vm, 0) end
  P.DestroyAnimVisualTask(t)
end)

function H.animMoveDmg(vm)
  local v = vm and vm.moveDmg
  if v == nil and vm and vm.ctx then v = vm.ctx.moveDmg or vm.ctx.animMoveDmg or vm.ctx.damage end
  if v == nil then return 1 end
  return tonumber(v) or 1
end

-- pokefirered/src/battle_anim_effects_3.c:1514
T.IsHealingMove = P.task(function(t, vm)
  if H.animMoveDmg(vm) > 0 then P.setRet(vm, 0) else P.setRet(vm, 1) end
  P.DestroyAnimVisualTask(t)
end)

function H.spotlightStep2(s, vm)
  local w = P.win(vm)
  w.winout = 0x3F3F
  w.objwin = not w.objwin
  P.DestroyAnimSprite(s)
end

function H.spotlightStep1(s)
  local d = s.data
  local k = d[0]
  if k == 0 then
    s.invisible = false
    if s.affineAnimEnded then d[0] = d[0] + 1 end
  elseif k == 1 or k == 3 then
    d[1] = P.s16(d[1] + 117)
    s.ox = P.shr(d[1], 8)
    d[2] = d[2] + 1
    if d[2] == 21 then
      d[2] = 0
      d[0] = d[0] + 1
    end
  elseif k == 2 then
    d[1] = P.s16(d[1] - 117)
    s.ox = P.shr(d[1], 8)
    d[2] = d[2] + 1
    if d[2] == 41 then
      d[2] = 0
      d[0] = d[0] + 1
    end
  elseif k == 4 then
    P.ChangeSpriteAffineAnim(s, 1)
    d[0] = d[0] + 1
  elseif k == 5 then
    if s.affineAnimEnded then
      s.invisible = true
      s.callbackFn = H.spotlightStep2
    end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1524
C.Spotlight = P.cb(function(s, vm)
  local w = P.win(vm)
  w.winout = 0x1F3F
  w.objwin = true
  w.win0 = nil
  P.InitSpritePosToAnimTarget(s, vm, false)
  P.registerObjWindow(vm, s)
  P.ensureColorOverlay(vm)
  s.invisible = true
  s.callbackFn = H.spotlightStep1
end)

function H.clappingHandStep(s, vm)
  local d = s.data
  if d[2] == 0 then
    s.ox = s.ox + d[1]
    if s.ox == 0 then
      d[2] = d[2] + 1
      if d[3] == 0 then P.playSEPan(vm, "SE_M_ENCORE", -64) end
    end
  else
    s.ox = s.ox - d[1]
    if P.abs(s.ox) == 12 then
      d[0] = d[0] - 1
      d[2] = d[2] - 1
    end
  end
  if d[0] == 0 then P.DestroyAnimSprite(s) end
end

function H.clappingHand(s, vm)
  if s.ga[3] == 0 then
    s.x = P.coordAtk(vm, P.COORD_X)
    s.y = P.coordAtk(vm, P.COORD_Y)
  end
  s.x = s.x + s.ga[0]
  s.y = s.y + s.ga[1]
  s.imageValue = s.imageValue + 16
  if s.ga[2] == 0 then
    s._hFlipBase = true
    s.ox = -12
    s.data[1] = 2
  else
    s.ox = 12
    s.data[1] = -2
  end
  s.data[0] = s.ga[4]
  if s.data[3] ~= 255 then s.data[3] = s.ga[2] end
  s.callbackFn = H.clappingHandStep
end

-- pokefirered/src/battle_anim_effects_3.c:1587
C.ClappingHand = P.cb(H.clappingHand)

-- pokefirered/src/battle_anim_effects_3.c:1646
C.ClappingHand2 = P.cb(function(s, vm)
  P.registerObjWindow(vm, s)
  s.data[3] = 255
  H.clappingHand(s, vm)
end)

-- pokefirered/src/battle_anim_effects_3.c:1653
T.CreateSpotlight = P.task(function(t, vm)
  local w = P.win(vm)
  w.winin = 0x1F3F
  w.win1 = { 0, 240, 120, 160 }
  P.ensureColorOverlay(vm)
  P.DestroyAnimVisualTask(t)
end)

-- pokefirered/src/battle_anim_effects_3.c:1676
T.RemoveSpotlight = P.task(function(t, vm)
  local w = P.win(vm)
  w.winin = 0x3F3F
  w.win1 = nil
  P.DestroyAnimVisualTask(t)
end)

function H.rapidSpinStep(s)
  local d = s.data
  d[1] = band(d[1] + d[2], 0xFF)
  s.ox = P.shr(P.SINE[d[1] + 1], 4)
  s.oy = s.oy + d[3]
  if d[0] ~= 0 then
    if s.oy < d[4] then P.DestroyAnimSprite(s) end
  elseif s.oy > d[4] then
    P.DestroyAnimSprite(s)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1687
C.RapidSpin = P.cb(function(s, vm)
  if s.ga[0] == 0 then
    s.x = P.coordAtk(vm, P.COORD_X) + s.ga[1]
    s.y = P.coordAtk(vm, P.COORD_Y)
  else
    s.x = P.coordTgt(vm, P.COORD_X) + s.ga[1]
    s.y = P.coordTgt(vm, P.COORD_Y)
  end
  s.oy = s.ga[2]
  s.data[0] = (s.oy > s.ga[3]) and 1 or 0
  s.data[1] = 0
  s.data[2] = s.ga[4]
  s.data[3] = s.ga[5]
  s.data[4] = s.ga[3]
  s.callbackFn = H.rapidSpinStep
end)

function H.rapidSpinApply(t)
  local p = P.monPresent(t._side)
  if not p then return end
  if P.isMonBg(t._side) then
    local out = {}
    for row, v in pairs(t._buf) do out[row] = -(v - t.data[8]) end
    p.hShift = out
  end
end

function H.rapidSpinElevStep(t, vm)
  local d = t.data
  d[0] = d[0] - d[5]
  if d[0] < d[2] then d[0] = d[2] end
  if d[4] == 0 then
    d[1] = d[1] - d[5]
    if d[1] < d[2] then
      d[1] = d[2]
      d[15] = 1
    end
  else
    d[4] = d[4] - 1
  end
  d[6] = d[6] + 1
  if d[6] > 1 then
    d[6] = 0
    d[7] = (d[7] == 0) and 1 or 0
    if d[7] ~= 0 then d[12] = d[8] else d[12] = d[9] end
  end
  local buf = t._buf
  for i = d[0], d[1] - 1 do buf[i] = d[12] end
  for i = d[1], d[3] do buf[i] = d[11] end
  H.rapidSpinApply(t)
  if d[15] ~= 0 then
    if d[10] ~= 0 then
      local p = P.monPresent(t._side)
      if p then p.hShift = nil end
    end
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1726
T.RapinSpinMonElevation = P.task(function(t, vm)
  local d = t.data
  local side = (t.ga[0] == 0) and P.atk(vm) or P.tgt(vm)
  t._side = side
  local var0 = P.s16(P.yWithElevation(vm, side))
  d[0] = var0 + 36
  d[1] = d[0]
  d[2] = var0 - 33
  if d[2] < 0 then d[2] = 0 end
  d[3] = d[0]
  d[4] = 8
  d[5] = t.ga[1]
  d[6] = 0
  d[7] = 0
  local var3 = 0
  local var4 = var3 + 240
  d[8] = var3
  d[9] = var4
  d[10] = t.ga[2]
  local var2
  if t.ga[2] == 0 then
    d[11] = var4
    var2 = d[8]
  else
    d[11] = var3
    var2 = d[9]
  end
  d[15] = 0
  t._buf = {}
  for i = d[2], d[3] do t._buf[i] = var2 end
  H.rapidSpinApply(t)
  t.fn = H.rapidSpinElevStep
end)

function H.tormentBubble(s)
  if s.animEnded then
    local task = s.task
    if task and task.active then
      local i = s.data[1]
      task.data[i] = task.data[i] - 1
    end
    P.DestroyAnimSprite(s)
  end
end

function H.noop() end

function H.tormentStep(t, vm)
  local d = t.data
  local k = d[0]
  if k == 0 then
    local x
    if band(d[1], 1) ~= 0 then x = d[2] - d[4] else x = d[2] + d[4] end
    local y = d[3] + d[5]
    local s = P.CreateSprite(vm, "gThoughtBubbleSpriteTemplate", P.s16(x), P.s16(y), 6 - d[1], H.noop)
    P.playSEPan(vm, "SE_M_METRONOME", -64)
    if s then
      s._hFlipBase = band(d[1], 1) ~= 0
      t._bubbles[#t._bubbles + 1] = s
      P.sync(s, vm)
    end
    if band(d[1], 1) ~= 0 then
      d[4] = d[4] - 6
      d[5] = d[5] - 6
    end
    H.PrepareAffineAnimInTaskData(t, t._side, H.affineTable("sAffineAnims_Torment"))
    d[1] = d[1] + 1
    d[0] = 1
  elseif k == 1 then
    if not H.RunAffineAnimFromTaskData(t, vm) then
      if d[1] == 6 then
        d[6] = 8
        d[0] = 3
      else
        if d[1] <= 2 then d[6] = 10 else d[6] = 0 end
        d[0] = 2
      end
    end
  elseif k == 2 then
    if d[6] ~= 0 then d[6] = d[6] - 1 else d[0] = 0 end
  elseif k == 3 then
    if d[6] ~= 0 then d[6] = d[6] - 1 else d[0] = 4 end
  elseif k == 4 then
    local j = 0
    for _, s in ipairs(t._bubbles) do
      if s.active and s.template == "gThoughtBubbleSpriteTemplate" then
        s.task = t
        s.data[0] = 0
        s.data[1] = 6
        P.StartSpriteAnim(s, 2)
        s.callbackFn = H.tormentBubble
        j = j + 1
        if j == 6 then break end
      end
    end
    d[6] = j
    d[0] = 5
  elseif k == 5 then
    if d[6] == 0 then P.DestroyAnimVisualTask(t) end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1866
T.TormentAttacker = P.task(function(t, vm)
  local d = t.data
  d[0] = 0
  d[1] = 0
  d[2] = P.coordAtk(vm, P.COORD_X_2)
  d[3] = P.coordAtk(vm, P.COORD_Y_PIC)
  d[4] = 32
  d[5] = -20
  d[6] = 0
  t._side = P.atk(vm)
  t._bubbles = {}
  t.fn = H.tormentStep
end)

function H.triAttackTriangle(s, vm)
  local d = s.data
  if d[0] == 0 then P.InitSpritePosToAnimAttacker(s, vm, false) end
  d[0] = d[0] + 1
  if d[0] < 40 then
    s.invisible = band(P.u16(d[0]), 1) == 0
  end
  if d[0] > 30 then s.invisible = false end
  if d[0] == 61 then
    P.StoreSpriteCallbackInData6(s, P.DestroyAnimSprite)
    s.x = s.x + s.ox
    s.y = s.y + s.oy
    s.ox = 0
    s.oy = 0
    d[0] = 20
    d[2] = P.coordTgt(vm, P.COORD_X_2)
    d[4] = P.coordTgt(vm, P.COORD_Y_PIC)
    s.callbackFn = P.StartAnimLinearTranslation
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1988
C.TriAttackTriangle = P.cb(H.triAttackTriangle)

-- pokefirered/src/battle_anim_effects_3.c:2019
T.DefenseCurlDeformMon = H.deformTask("DefenseCurlDeformMonAffineAnimCmds")

function H.batonPass(s, vm)
  local d = s.data
  local side = P.atk(vm)
  local p = P.monPresent(side)
  local k = d[0]
  if k == 0 then
    s.x = P.coordAtk(vm, P.COORD_X_2)
    s.y = P.coordAtk(vm, P.COORD_Y_PIC)
    d[1] = 256
    d[2] = 256
    d[0] = d[0] + 1
  elseif k == 1 or k == 2 then
    if k == 1 then
      d[1] = P.s16(d[1] + 96)
      d[2] = P.s16(d[2] - 26)
      P.monRotScale(p, d[1], d[2], 0)
      d[3] = d[3] + 1
      if d[3] == 5 then d[0] = d[0] + 1 end
    end
    d[1] = P.s16(d[1] + 96)
    d[2] = P.s16(d[2] + 48)
    P.monRotScale(p, d[1], d[2], 0)
    d[3] = d[3] + 1
    if d[3] == 9 then
      d[3] = 0
      if p then p.visible = false end
      P.monResetRotScale(p)
      d[0] = d[0] + 1
    end
  elseif k == 3 then
    s.oy = s.oy - 6
    if s.y + s.oy < -32 then P.DestroyAnimSprite(s) end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:2034
C.BatonPassPokeball = P.cb(H.batonPass)

function H.miniStarStep(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] < 30 then
    d[1] = d[1] + 1
    if d[1] == 2 then
      s.invisible = not s.invisible
      d[1] = 0
    end
  else
    if d[1] == 2 then s.invisible = false end
    if d[1] == 3 then
      s.invisible = true
      d[1] = -1
    end
    d[1] = d[1] + 1
  end
  if d[0] > 60 then P.DestroyAnimSprite(s) end
end

function H.miniStar(s)
  local rand = band(P.Random(), 3)
  if rand == 0 then
    s.imageValue = s.imageValue + 4
  else
    s.imageValue = s.imageValue + 5
  end
  local y = P.s8(band(P.Random(), 7))
  if y > 3 then y = -y end
  s.oy = y
  s.callbackFn = H.miniStarStep
end

function H.wishStarStep(s, vm)
  local d = s.data
  d[0] = P.s16(d[0] + 72)
  if not P.atkIsPlayer(vm) then
    s.ox = P.shr(d[0], 4)
  else
    s.ox = -P.shr(d[0], 4)
  end
  d[1] = P.s16(d[1] + 16)
  s.oy = s.oy + P.shr(d[1], 8)
  d[2] = d[2] + 1
  if P.mod(d[2], 3) == 0 then
    P.CreateSprite(vm, "gMiniTwinklingStarSpriteTemplate", s.x + s.ox, s.y + s.oy, s.sub + 1, H.miniStar, { animate = true })
  end
  local newX = s.x + s.ox + 32
  if newX < 0 or newX > 240 + 64 then P.DestroyAnimSprite(s) end
end

-- pokefirered/src/battle_anim_effects_3.c:2077
C.WishStar = P.cb(function(s, vm)
  if not P.atkIsPlayer(vm) then
    s.x = -16
  else
    s.x = 240 + 16
  end
  s.y = 0
  s.callbackFn = H.wishStarStep
end)

-- pokefirered/src/battle_anim_effects_3.c:2162
T.StockpileDeformMon = H.deformTask("sStockpileDeformMonAffineAnimCmds")

-- pokefirered/src/battle_anim_effects_3.c:2176
T.SpitUpDeformMon = H.deformTask("sSpitUpDeformMonAffineAnimCmds")

-- pokefirered/src/battle_anim_effects_3.c:2190
C.SwallowBlueOrb = P.cb(function(s, vm)
  local d = s.data
  if d[0] == 0 then
    P.InitSpritePosToAnimAttacker(s, vm, false)
    d[1] = 0x900
    d[2] = P.coordAtk(vm, P.COORD_Y_PIC)
    d[0] = d[0] + 1
  elseif d[0] == 1 then
    s.oy = s.oy - P.shr(d[1], 8)
    d[1] = P.s16(d[1] - 96)
    if s.y + s.oy > d[2] then P.DestroyAnimSprite(s) end
  end
end)

-- pokefirered/src/battle_anim_effects_3.c:2209
T.SwallowDeformMon = H.deformTask("sSwallowDeformMonAffineAnimCmds")

-- pokefirered/src/battle_gfx_sfx_util.c:653
-- pokefirered/src/battle_gfx_sfx_util.c:653
function H.HandleSpeciesGfxDataChange(vm, transformType)
  local p = P.monPresent(P.atk(vm))
  local kind = P.u8(tonumber(transformType) or (transformType and 1 or 0))
  if kind == 255 then
    if p then p.ghostUnveiled = true end
    return
  end
  if kind ~= 0 then
    if p then
      p.castformForm = tonumber(vm and vm.animArg) or 0
      p.pendingCastform = nil
    end
    return
  end
  local tsp = P.species(vm, P.tgt(vm))
  if not tsp then return end
  vm._speciesBySide = vm._speciesBySide or {}
  vm._speciesBySide[P.atk(vm)] = tsp
  if p then
    local tp = P.monPresent(P.tgt(vm))
    p.transformSpecies = tsp
    p.pendingTransform = nil
    p.castformForm = tp and tp.castformForm or nil
    p.castformMon = nil
  end
end

function H.transformStep(t, vm)
  local d = t.data
  local k = d[0]
  if k == 0 then
    t._mosaic = 0
    d[10] = t.ga[0]
    d[0] = d[0] + 1
  elseif k == 1 then
    local r = d[2]
    d[2] = d[2] + 1
    if r > 1 then
      d[2] = 0
      d[1] = d[1] + 1
      t._mosaic = d[1]
      local p = P.monPresent(P.atk(vm))
      if p then p.mosaic = d[1] end
      if d[1] == 15 then d[0] = d[0] + 1 end
    end
  elseif k == 2 then
    H.HandleSpeciesGfxDataChange(vm, d[10])
    d[0] = d[0] + 1
  elseif k == 3 then
    local r = d[2]
    d[2] = d[2] + 1
    if r > 1 then
      d[2] = 0
      d[1] = d[1] - 1
      t._mosaic = d[1]
      local p = P.monPresent(P.atk(vm))
      if p then p.mosaic = d[1] end
      if d[1] == 0 then d[0] = d[0] + 1 end
    end
  elseif k == 4 then
    t._mosaic = 0
    local p = P.monPresent(P.atk(vm))
    if p then p.mosaic = nil end
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:2223
T.TransformMon = P.task(H.transformStep)

-- pokefirered/src/battle_anim_effects_3.c:2303
T.IsMonInvisible = P.task(function(t, vm)
  local p = P.monPresent(P.atk(vm))
  if p and p.visible == false then P.setRet(vm, 1) else P.setRet(vm, 0) end
  P.DestroyAnimVisualTask(t)
end)

-- pokefirered/src/battle_anim_effects_3.c:2309
T.CastformGfxChange = P.task(function(t, vm)
  H.HandleSpeciesGfxDataChange(vm, 1)
  P.DestroyAnimVisualTask(t)
end)

H.MORNING_SUN_COORDS = { [0] = -24, 24, -4, 0 }

function H.morningSunStep(t, vm)
  local d = t.data
  local k = d[0]
  if k == 0 then
    P.setBld(vm, 0, 16)
    P.bg1Layer(t, vm, "MORNING_SUN", 1)
    if not P.atkIsPlayer(vm) then t._bg1x = -135 else t._bg1x = -10 end
    t._bg1y = 0
    d[10] = t._bg1x
    d[11] = t._bg1y
    d[0] = d[0] + 1
    P.playSEPan(vm, "SE_M_MORNING_SUN", -64)
  elseif k == 1 then
    local r = d[4]
    d[4] = d[4] + 1
    if r > 0 then
      d[4] = 0
      d[1] = d[1] + 1
      if d[1] > 12 then d[1] = 12 end
      P.setBld(vm, d[1], 16 - d[1])
      if d[1] == 12 then d[0] = d[0] + 1 end
    end
  elseif k == 2 then
    d[1] = d[1] - 1
    if d[1] < 0 then d[1] = 0 end
    P.setBld(vm, d[1], 16 - d[1])
    if d[1] == 0 then
      t._bg1x = H.MORNING_SUN_COORDS[d[2]] + d[10]
      d[2] = d[2] + 1
      if d[2] == 4 then d[0] = 4 else d[0] = 3 end
    end
  elseif k == 3 then
    d[3] = d[3] + 1
    if d[3] == 4 then
      d[3] = 0
      d[0] = 1
      P.playSEPan(vm, "SE_M_MORNING_SUN", -64)
    end
  elseif k == 4 then
    P.bg1Clear(t)
    t._bg1x = 0
    t._bg1y = 0
    P.setBld(vm, nil)
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:2315
T.MorningSunLightBeam = P.task(H.morningSunStep)

return { callbacks = C, tasks = T }
