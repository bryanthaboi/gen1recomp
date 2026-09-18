
return function(C)
  local P, T = C.P, C.T
  local CB = {}

  local function args(s) return s._vm.args end
  local function isOpp(side) return side ~= "player" end

  -- pokefirered/src/battle_anim_mons.c:1440
  function C.translateToTargetMonLocation(s)
    local vm = s._vm
    local a = args(s)
    local respect = P.band(P.u16(a[5]), 0xFF00) == 0
    local coordType = (P.band(P.u16(a[5]), 0xFF) == 0) and P.Y_PIC_OFFSET or P.Y
    P.initPosToAttacker(vm, s, respect)
    if isOpp(P.atk(vm)) then a[2] = -a[2] end
    s.data[0] = a[4]
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + a[2]
    s.data[4] = P.coord(vm, P.tgt(vm), coordType) + a[3]
    s.callback = P.startLinear
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_special.c:2216
  local safariWait, safariArc, safariFinish
  CB.SpriteCB_SafariBaitOrRock_Init = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, false)
    s.data[0] = 30
    s.data[2] = P.coord(vm, "enemy", P.X) + a[2]
    s.data[4] = P.coord(vm, "enemy", P.Y) + a[3]
    s.data[5] = -32
    P.initArc(s)
    C.startPlayerThrow(vm)
    s.callback = safariWait
  end
  safariWait = function(s)
    if C.playerThrowIndex(s._vm) == 1 then s.callback = safariArc end
  end
  safariArc = function(s)
    if P.translateHArc(s) then
      s.data[0] = 0
      P.setInvisible(s, true)
      s.callback = safariFinish
    end
  end
  safariFinish = function(s)
    if C.playerThrowEnded(s._vm) then
      s.data[0] = s.data[0] + 1
      if s.data[0] > 0 then
        C.resetPlayerThrow(s._vm)
        P.destroy(s)
      end
    end
  end

  -- pokefirered/src/battle_anim_bug.c:197
  CB.MegahornHorn = function(s)
    local vm = s._vm
    local a = args(s)
    if P.tgt(vm) == "player" then
      P.startAffineAnim(s, 1)
      a[1], a[2], a[3], a[0] = -a[1], -a[2], -a[3], -a[0]
    end
    s.x = P.coord(vm, P.tgt(vm), P.X_2) + a[0]
    s.y = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[1]
    s.data[0] = a[4]
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + a[2]
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[3]
    s.callback = P.startLinear
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_bug.c:222
  CB.LeechLifeNeedle = function(s)
    local vm = s._vm
    local a = args(s)
    if P.tgt(vm) == "player" then
      a[1], a[0] = -a[1], -a[0]
    end
    s.x = P.coord(vm, P.tgt(vm), P.X_2) + a[0]
    s.y = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[1]
    s.data[0] = a[2]
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
    s.callback = P.startLinear
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_bug.c:250
  local webThreadStep
  CB.TranslateWebThread = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, true)
    s.data[0] = a[2]
    s.data[1] = s.x
    s.data[3] = s.y
    if a[4] == 0 then
      s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
      s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
    else
      s.data[2], s.data[4] = P.averagePositions(vm, P.tgt(vm), true)
    end
    P.initLinearWithSpeed(s)
    s.data[5] = a[3]
    s.callback = webThreadStep
  end
  webThreadStep = function(s)
    if P.translateLinear(s) then
      P.destroy(s)
      return
    end
    s.ox = s.ox + P.Sin(s.data[6], s.data[5])
    s.data[6] = P.band(s.data[6] + 13, 0xFF)
  end

  -- pokefirered/src/battle_anim_bug.c:283
  local stringWrapStep
  CB.StringWrap = function(s)
    local vm = s._vm
    local a = args(s)
    s.x, s.y = P.averagePositions(vm, P.tgt(vm), false)
    if isOpp(P.atk(vm)) then s.x = s.x - a[0] else s.x = s.x + a[0] end
    s.y = s.y + a[1]
    if P.tgt(vm) == "player" then s.y = s.y + 8 end
    s.callback = stringWrapStep
  end
  stringWrapStep = function(s)
    s.data[0] = s.data[0] + 1
    if s.data[0] == 3 then
      s.data[0] = 0
      P.setInvisible(s, not P.isInvisible(s))
    end
    s.data[1] = s.data[1] + 1
    if s.data[1] == 51 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_bug.c:309
  local spiderWebStep, spiderWebEnd
  CB.SpiderWeb = function(s)
    s._vm.bldAlpha = { eva = 16, evb = 0 }
    s.data[0] = 16
    s.callback = spiderWebStep
  end
  spiderWebStep = function(s)
    if s.data[2] < 20 then
      s.data[2] = s.data[2] + 1
    else
      local v = s.data[1]
      s.data[1] = v + 1
      if P.band(v, 1) ~= 0 then
        s.data[0] = s.data[0] - 1
        s._vm.bldAlpha = { eva = s.data[0], evb = 16 - s.data[0] }
        if s.data[0] == 0 then
          P.setInvisible(s, true)
          s.callback = spiderWebEnd
        end
      end
    end
  end
  spiderWebEnd = function(s)
    s._vm.bldAlpha = nil
    P.destroy(s)
  end

  -- pokefirered/src/battle_anim_bug.c:350
  CB.TranslateStinger = function(s)
    local vm = s._vm
    local a = args(s)
    if isOpp(P.atk(vm)) then
      a[2], a[1], a[3] = -a[2], -a[1], -a[3]
    end
    if P.atk(vm) == P.tgt(vm) then
      a[2], a[0] = -a[2], -a[0]
    end
    P.initPosToAttacker(vm, s, true)
    local lx = P.s16(P.coord(vm, P.tgt(vm), P.X_2) + a[2])
    local ly = P.s16(P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[3])
    local rot = P.u16(P.ArcTan2Neg(lx - s.x, ly - s.y) + 0xC000)
    P.trySetRotScale(s, 0x100, 0x100, rot)
    s.data[0] = a[4]
    s.data[2] = lx
    s.data[4] = ly
    s.callback = P.startLinear
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_bug.c:399
  local missileArcStep
  CB.MissileArc = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, true)
    if isOpp(P.atk(vm)) then a[2] = -a[2] end
    s.data[0] = a[4]
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + a[2]
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[3]
    s.data[5] = a[5]
    P.initArc(s)
    s.callback = missileArcStep
    P.setInvisible(s, true)
  end
  missileArcStep = function(s)
    P.setInvisible(s, false)
    if P.translateHArc(s) then
      P.destroy(s)
      return
    end
    local temp = {}
    for i = 0, 7 do temp[i] = s.data[i] end
    local px = s.x + s.ox
    local py = s.y + s.oy
    if not P.translateHArc(s) then
      local rot = P.u16(P.ArcTan2Neg(s.x + s.ox - px, s.y + s.oy - py) + 0xC000)
      P.trySetRotScale(s, 0x100, 0x100, rot)
      for i = 0, 7 do s.data[i] = temp[i] end
    end
  end

  -- pokefirered/src/battle_anim_bug.c:448
  CB.TailGlowOrb = function(s)
    local vm = s._vm
    local a = args(s)
    local side = (a[0] == P.ANIM_ATTACKER) and P.atk(vm) or P.tgt(vm)
    s.x = P.coord(vm, side, P.X_2)
    s.y = P.coord(vm, side, P.Y_PIC_OFFSET) + 18
    P.storeCb(s, P.destroy)
    s.callback = P.runStoredWhenAffineEnds
  end

  -- pokefirered/src/battle_anim_electric.c:454
  local lightningStep
  CB.Lightning = function(s)
    local vm = s._vm
    local a = args(s)
    if isOpp(P.atk(vm)) then s.x = s.x - a[0] else s.x = s.x + a[0] end
    s.y = s.y + a[1]
    s.callback = lightningStep
  end
  lightningStep = function(s)
    if s.animEnded then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_flying.c:533
  function C.destroyAfterTimer(s)
    local v = s.data[0]
    s.data[0] = v - 1
    if v <= 0 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_electric.c:507
  CB.SparkElectricity = function(s)
    local vm = s._vm
    local a = args(s)
    local side
    if a[4] == P.ANIM_ATTACKER then side = P.atk(vm) else side = P.tgt(vm) end
    if a[5] == 0 then
      s.x = P.coord(vm, side, P.X)
      s.y = P.coord(vm, side, P.Y)
    else
      s.x = P.coord(vm, side, P.X_2)
      s.y = P.coord(vm, side, P.Y_PIC_OFFSET)
    end
    s.ox = P.asr(P.gSine(a[0]) * a[1], 8)
    s.oy = P.asr(P.gSine(a[0] + 64) * a[1], 8)
    if P.band(a[6], 1) ~= 0 then P.setPriority(s, 3, s.subpriority) end
    P.setMatrix(s, 0x100, 0x100, P.u16(-a[2] * 256))
    s.affineAnimPaused = true
    s.data[0] = a[3]
    s.callback = C.destroyAfterTimer
  end

  -- pokefirered/src/battle_anim_electric.c:558
  local zapStep
  CB.ZapCannonSpark = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, true)
    s.data[0] = a[3]
    s.data[1] = s.x
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
    s.data[3] = s.y
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
    P.initLinear(s)
    s.data[5] = a[2]
    s.data[6] = a[5]
    s.data[7] = a[4]
    P.addTile(s, a[6] * 4)
    s.callback = zapStep
    s.callback(s)
  end
  zapStep = function(s)
    if not P.translateLinear(s) then
      s.ox = s.ox + P.Sin(s.data[7], s.data[5])
      s.oy = s.oy + P.Cos(s.data[7], s.data[5])
      s.data[7] = P.band(s.data[7] + s.data[6], 0xFF)
      if s.data[7] % 3 == 0 then P.setInvisible(s, not P.isInvisible(s)) end
    else
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_electric.c:591
  local tboltStep
  CB.ThunderboltOrb = function(s)
    local vm = s._vm
    local a = args(s)
    if P.tgt(vm) == "player" then a[1] = -a[1] end
    s.x = P.coord(vm, P.tgt(vm), P.X_2) + a[1]
    s.y = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[2]
    s.data[3] = a[0]
    s.data[4] = a[3]
    s.data[5] = a[3]
    s.callback = tboltStep
  end
  tboltStep = function(s)
    s.data[5] = s.data[5] - 1
    if s.data[5] == -1 then
      P.setInvisible(s, not P.isInvisible(s))
      s.data[5] = s.data[4]
    end
    local v = s.data[3]
    s.data[3] = v - 1
    if v <= 0 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_electric.c:614
  local flashingStep
  CB.SparkElectricityFlashing = function(s)
    local vm = s._vm
    local a = args(s)
    s.data[0] = a[3]
    local side = (P.band(P.u16(a[7]), 0x8000) ~= 0) and P.tgt(vm) or P.atk(vm)
    if side == "player" then a[0] = -a[0] end
    s.x = P.coord(vm, side, P.X_2) + a[0]
    s.y = P.coord(vm, side, P.Y_PIC_OFFSET) + a[1]
    s.data[4] = P.band(P.u16(a[7]), 0x7FFF)
    s.data[5] = a[2]
    s.data[6] = a[5]
    s.data[7] = a[4]
    P.addTile(s, a[6] * 4)
    s.callback = flashingStep
    s.callback(s)
  end
  flashingStep = function(s)
    s.ox = P.Sin(s.data[7], s.data[5])
    s.oy = P.Cos(s.data[7], s.data[5])
    s.data[7] = P.band(s.data[7] + s.data[6], 0xFF)
    if s.data[4] ~= 0 and s.data[7] % s.data[4] == 0 then P.setInvisible(s, not P.isInvisible(s)) end
    local v = s.data[0]
    s.data[0] = v - 1
    if v <= 0 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_electric.c:648
  CB.Electricity = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToTarget(vm, s, false)
    P.addTile(s, a[3] * 4)
    if a[3] == 1 then P.setHFlip(s, true) elseif a[3] == 2 then P.setVFlip(s, true) end
    s.data[0] = a[2]
    s.callback = P.waitAnimForDuration
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_electric.c:753
  local thunderWaveStep
  CB.ThunderWave = function(s)
    local vm = s._vm
    local a = args(s)
    s.x = s.x + a[0]
    s.y = s.y + a[1]
    local s2 = P.createSprite(vm, s.tag or "SPARK_H", T.gThunderWaveSpriteTemplate, s.x + 32, s.y, s.subpriority, thunderWaveStep, s._baseW, s._baseH)
    if s2 then
      P.addTile(s2, 8)
      s2._g4counted = true
    end
    s.callback = thunderWaveStep
  end
  thunderWaveStep = function(s)
    s.data[0] = s.data[0] + 1
    if s.data[0] == 3 then
      s.data[0] = 0
      P.setInvisible(s, not P.isInvisible(s))
    end
    s.data[1] = s.data[1] + 1
    if s.data[1] == 51 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_electric.c:864
  local function orb_on(s)
    local vm = s._vm
    local side = (args(s)[0] == P.ANIM_ATTACKER) and P.atk(vm) or P.tgt(vm)
    s.x = P.coord(vm, side, P.X_2)
    s.y = P.coord(vm, side, P.Y_PIC_OFFSET)
  end
  CB.GrowingChargeOrb = function(s)
    orb_on(s)
    P.storeCb(s, P.destroy)
    s.callback = P.runStoredWhenAffineEnds
  end

  -- pokefirered/src/battle_anim_electric.c:881
  CB.ElectricPuff = function(s)
    orb_on(s)
    local a = args(s)
    s.ox = a[1]
    s.oy = a[2]
    P.storeCb(s, P.destroy)
    s.callback = P.runStoredWhenAnimEnds
  end

  -- pokefirered/src/battle_anim_electric.c:900
  local orbSlideStep
  CB.VoltTackleOrbSlide = function(s)
    local vm = s._vm
    P.startAffineAnim(s, 1)
    s.x = P.coord(vm, P.atk(vm), P.X_2)
    s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
    s._mon = P.present(P.atk(vm))
    s.data[7] = 16
    if P.atk(vm) == "enemy" then s.data[7] = -16 end
    s.callback = orbSlideStep
  end
  orbSlideStep = function(s)
    if s.data[0] == 0 then
      s.data[1] = s.data[1] + 1
      if s.data[1] > 40 then s.data[0] = s.data[0] + 1 end
    elseif s.data[0] == 1 then
      s.x = s.x + s.data[7]
      if s._mon then s._mon.ox = (s._mon.ox or 0) + s.data[7] end
      if P.u16(s.x + 80) > 400 then P.destroy(s) end
    end
  end

  -- pokefirered/src/battle_anim_electric.c:1090
  CB.GrowingShockWaveOrb = function(s)
    local vm = s._vm
    if s.data[0] == 0 then
      s.x = P.coord(vm, P.atk(vm), P.X_2)
      s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
      P.startAffineAnim(s, 2)
      s.data[0] = s.data[0] + 1
    elseif s.affineAnimEnded then
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_ground.c:141
  local bonemerangStep, bonemerangEnd
  CB.BonemerangProjectile = function(s)
    local vm = s._vm
    s.x = P.coord(vm, P.atk(vm), P.X_2)
    s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
    s.data[0] = 20
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
    s.data[5] = -40
    P.initArc(s)
    s.callback = bonemerangStep
  end
  bonemerangStep = function(s)
    if P.translateHArc(s) then
      local vm = s._vm
      s.x = s.x + s.ox
      s.y = s.y + s.oy
      s.oy, s.ox = 0, 0
      s.data[0] = 20
      s.data[2] = P.coord(vm, P.atk(vm), P.X_2)
      s.data[4] = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
      s.data[5] = 40
      P.initArc(s)
      s.callback = bonemerangEnd
    end
  end
  bonemerangEnd = function(s)
    if P.translateHArc(s) then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_ground.c:183
  CB.BoneHitProjectile = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToTarget(vm, s, true)
    if isOpp(P.atk(vm)) then a[2] = -a[2] end
    s.data[0] = a[4]
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + a[2]
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[3]
    s.callback = P.startLinear
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_ground.c:201
  CB.DirtScatter = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, true)
    local tx = P.coord(vm, P.tgt(vm), P.X_2)
    local ty = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
    local xo = P.band(P.Random(), 0x1F)
    local yo = P.band(P.Random(), 0x1F)
    if xo > 16 then xo = 16 - xo end
    if yo > 16 then yo = 16 - yo end
    s.data[0] = a[2]
    s.data[2] = tx + xo
    s.data[4] = ty + yo
    s.callback = P.startLinear
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_ground.c:227
  local mudRising, mudFalling
  CB.MudSportDirt = function(s)
    local vm = s._vm
    local a = args(s)
    P.addTile(s, 1)
    if a[0] == 0 then
      s.x = P.coord(vm, P.atk(vm), P.X_2) + a[1]
      s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET) + a[2]
      s.data[0] = a[1] > 0 and 1 or -1
      s.callback = mudRising
    else
      s.x = a[1]
      s.y = a[2]
      s.oy = -a[2]
      s.callback = mudFalling
    end
  end
  mudRising = function(s)
    s.data[1] = s.data[1] + 1
    if s.data[1] > 1 then
      s.data[1] = 0
      s.x = s.x + s.data[0]
    end
    s.y = s.y - 4
    if s.y < -4 then P.destroy(s) end
  end
  mudFalling = function(s)
    if s.data[0] == 0 then
      s.oy = s.oy + 4
      if s.oy >= 0 then
        s.oy = 0
        s.data[0] = s.data[0] + 1
      end
    elseif s.data[0] == 1 then
      s.data[1] = s.data[1] + 1
      if s.data[1] > 0 then
        s.data[1] = 0
        P.setInvisible(s, not P.isInvisible(s))
        s.data[2] = s.data[2] + 1
        if s.data[2] == 10 then P.destroy(s) end
      end
    end
  end

  -- pokefirered/src/battle_anim_ground.c:488
  local plumeStep
  CB.DirtPlumeParticle = function(s)
    local vm = s._vm
    local a = args(s)
    local side = (a[0] == 0) and P.atk(vm) or P.tgt(vm)
    local xo = 24
    if a[1] == 1 then
      xo = -24
      a[2] = -a[2]
    end
    s.x = P.coord(vm, side, P.X_2) + xo
    s.y = P.yWithElevation(vm, side) + 30
    s.data[0] = a[5]
    s.data[2] = s.x + a[2]
    s.data[4] = s.y + a[3]
    s.data[5] = a[4]
    P.initArc(s)
    s.callback = plumeStep
  end
  plumeStep = function(s)
    if P.translateHArc(s) then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_ground.c:525
  CB.DigDirtMound = function(s)
    local vm = s._vm
    local a = args(s)
    local side = (a[0] == 0) and P.atk(vm) or P.tgt(vm)
    s.x = P.coord(vm, side, P.X) - 16 + a[1] * 32
    s.y = P.yWithElevation(vm, side) + 32
    P.addTile(s, a[1] * 8)
    P.storeCb(s, P.destroy)
    s.data[0] = a[2]
    s.callback = P.waitAnimForDuration
  end

  -- pokefirered/src/battle_anim_poison.c:187
  local sludgeStep
  CB.SludgeProjectile = function(s)
    local vm = s._vm
    local a = args(s)
    if a[3] == 0 then P.startAnim(s, 2) end
    P.initPosToAttacker(vm, s, true)
    s.data[0] = a[2]
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
    s.data[5] = -30
    P.initArc(s)
    s.callback = sludgeStep
  end
  sludgeStep = function(s)
    if P.translateHArc(s) then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_poison.c:206
  CB.AcidPoisonBubble = function(s)
    local vm = s._vm
    local a = args(s)
    if a[3] == 0 then P.startAnim(s, 2) end
    P.initPosToAttacker(vm, s, true)
    local l1, l2 = P.averagePositions(vm, P.tgt(vm), true)
    if P.atk(vm) ~= "player" then a[4] = -a[4] end
    s.data[0] = a[2]
    s.data[2] = l1 + a[4]
    s.data[4] = l2 + a[5]
    s.data[5] = -30
    P.initArc(s)
    s.callback = sludgeStep
  end

  -- pokefirered/src/battle_anim_mons.c:977
  function C.initSpriteDataForLinearTranslation(s)
    local d = s.data
    local x = P.s16(P.lshift(d[2] - d[1], 8))
    local y = P.s16(P.lshift(d[4] - d[3], 8))
    d[1] = P.s16(P.cdiv(x, d[0]))
    d[2] = P.s16(P.cdiv(y, d[0]))
    d[4] = 0
    d[3] = 0
  end

  -- pokefirered/src/battle_anim_poison.c:230
  local sludgeHitStep
  CB.SludgeBombHitParticle = function(s)
    local a = args(s)
    s.data[0] = a[2]
    s.data[1] = s.x
    s.data[2] = s.x + a[0]
    s.data[3] = s.y
    s.data[4] = s.y + a[1]
    C.initSpriteDataForLinearTranslation(s)
    s.data[5] = P.s16(P.cdiv(s.data[1], a[2]))
    s.data[6] = P.s16(P.cdiv(s.data[2], a[2]))
    s.callback = sludgeHitStep
  end
  sludgeHitStep = function(s)
    P.translateSpriteLinearFixedPoint(s)
    if not s.active then return end
    s.data[1] = P.s16(s.data[1] - s.data[5])
    s.data[2] = P.s16(s.data[2] - s.data[6])
    if s.data[0] == 0 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_poison.c:252
  CB.AcidPoisonDroplet = function(s)
    local vm = s._vm
    local a = args(s)
    s.x, s.y = P.averagePositions(vm, P.tgt(vm), true)
    if isOpp(P.atk(vm)) then a[0] = -a[0] end
    s.x = s.x + a[0]
    s.y = s.y + a[1]
    s.data[0] = a[4]
    s.data[2] = s.x + a[2]
    s.data[4] = s.y + s.data[0]
    s.callback = P.startLinear
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_poison.c:272
  local bubbleStep
  CB.BubbleEffect = function(s)
    local vm = s._vm
    local a = args(s)
    if a[2] == 0 then
      P.initPosToTarget(vm, s, true)
    else
      s.x, s.y = P.averagePositions(vm, P.tgt(vm), true)
      if isOpp(P.atk(vm)) then a[0] = -a[0] end
      s.x = s.x + a[0]
      s.y = s.y + a[1]
    end
    s.callback = bubbleStep
  end
  bubbleStep = function(s)
    s.data[0] = P.band(s.data[0] + 0xB, 0xFF)
    s.ox = P.Sin(s.data[0], 4)
    s.data[1] = s.data[1] + 0x30
    s.oy = -P.asr(s.data[1], 8)
    if s.affineAnimEnded then P.destroy(s) end
  end

  return CB
end
