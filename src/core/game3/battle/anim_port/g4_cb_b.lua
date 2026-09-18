
return function(C)
  local P, T = C.P, C.T
  local CB = {}

  local function args(s) return s._vm.args end
  local function isOpp(side) return side ~= "player" end
  local function offscreen(s)
    local x, y = s.x + s.ox, s.y + s.oy
    return x > 240 + 16 or x < -16 or y > 160 or y < -16
  end

  -- pokefirered/src/battle_anim_mons.c:433
  local function growingCircle(s)
    local d = s.data
    if d[3] ~= 0 then
      local amp = P.asr(d[5], 8) + d[1]
      s.ox = P.Sin(d[0], amp)
      s.oy = P.Cos(d[0], amp)
      d[0] = d[0] + d[2]
      d[5] = P.s16(d[5] + d[4])
      if d[0] >= 0x100 then d[0] = d[0] - 0x100 elseif d[0] < 0 then d[0] = d[0] + 0x100 end
      d[3] = d[3] - 1
    else
      P.runStored(s)
    end
  end

  -- pokefirered/src/battle_anim_ice.c:578
  CB.IcePunchSwirlingParticle = function(s)
    local a = args(s)
    s.data[0] = a[0]
    s.data[1] = 60
    s.data[2] = 9
    s.data[3] = 30
    s.data[4] = -512
    P.storeCb(s, P.destroy)
    s.callback = growingCircle
    s.callback(s)
  end

  -- pokefirered/src/battle_anim_ice.c:596
  CB.IceBeamParticle = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, true)
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
    if isOpp(P.atk(vm)) then s.data[2] = s.data[2] - a[2] else s.data[2] = s.data[2] + a[2] end
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[3]
    s.data[0] = a[4]
    P.storeCb(s, P.destroy)
    s.callback = P.startLinear
  end

  -- pokefirered/src/battle_anim_ice.c:633
  local function flickerIce(s)
    P.setInvisible(s, not P.isInvisible(s))
    s.data[0] = s.data[0] + 1
    if s.data[0] == 20 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_ice.c:615
  CB.IceEffectParticle = function(s)
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
    P.storeCb(s, flickerIce)
    s.callback = P.runStoredWhenAffineEnds
  end

  -- pokefirered/src/battle_anim_mons.c:1157
  local function initFastWithSpeed(s)
    local d = s.data
    local xDiff = P.lshift(math.abs(d[2] - d[1]), 4)
    if d[0] ~= 0 then d[0] = P.s16(P.cdiv(xDiff, d[0])) end
    P.initFastLinear(s)
  end

  local function initFastWithSpeedAndPos(s)
    s.data[1] = s.x
    s.data[3] = s.y
    initFastWithSpeed(s)
    s.callback = function(sp)
      if P.fastTranslateLinear(sp) then P.runStored(sp) end
    end
    s.callback(s)
  end

  local function rewind_offscreen(s)
    local temp = {}
    for i = 0, 7 do temp[i] = s.data[i] end
    s.data[1] = P.bxor(P.u16(s.data[1]), 1)
    s.data[2] = P.bxor(P.u16(s.data[2]), 1)
    s.data[1], s.data[2] = P.s16(s.data[1]), P.s16(s.data[2])
    local guard = 0
    while guard < 4096 do
      guard = guard + 1
      s.data[0] = 1
      P.fastTranslateLinear(s)
      if offscreen(s) then break end
    end
    s.x = s.x + s.ox
    s.y = s.y + s.oy
    s.ox, s.oy = 0, 0
    return temp
  end

  -- pokefirered/src/battle_anim_ice.c:647
  local snowStep1, snowStep2, snowEnd
  CB.SwirlingSnowball = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, true)
    s.data[0] = a[4]
    s.data[1] = s.x
    s.data[3] = s.y
    if a[5] == 0 then
      s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
      s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[3]
    else
      s.data[2], s.data[4] = P.averagePositions(vm, P.tgt(vm), true)
    end
    if isOpp(P.atk(vm)) then s.data[2] = s.data[2] - a[2] else s.data[2] = s.data[2] + a[2] end
    local temp = {}
    for i = 0, 7 do temp[i] = s.data[i] end
    initFastWithSpeed(s)
    rewind_offscreen(s)
    for i = 0, 7 do s.data[i] = temp[i] end
    s.callback = initFastWithSpeedAndPos
    P.storeCb(s, snowStep1)
  end
  snowStep1 = function(s)
    s.x = s.x + s.ox
    s.y = s.y + s.oy
    s.oy, s.ox = 0, 0
    s.data[0] = 128
    local tv = isOpp(P.atk(s._vm)) and 20 or -20
    s.data[3] = P.Sin(s.data[0], tv)
    s.data[4] = P.Cos(s.data[0], 0xF)
    s.data[5] = 0
    s.callback = snowStep2
    s.callback(s)
  end
  snowStep2 = function(s)
    local tv = isOpp(P.atk(s._vm)) and 20 or -20
    if s.data[5] <= 31 then
      s.ox = P.Sin(s.data[0], tv) - s.data[3]
      s.oy = P.Cos(s.data[0], 15) - s.data[4]
      s.data[0] = P.band(s.data[0] + 16, 0xFF)
      s.data[5] = s.data[5] + 1
    else
      s.x = s.x + s.ox
      s.y = s.y + s.oy
      s.ox, s.oy = 0, 0
      s.data[3], s.data[4] = 0, 0
      s.callback = snowEnd
    end
  end
  snowEnd = function(s)
    s.data[0] = 1
    P.fastTranslateLinear(s)
    if P.u16(s.x + s.ox + 16) > 272 or s.y + s.oy > 256 or s.y + s.oy < -16 then
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_ice.c:751
  local wiggleStep
  CB.MoveParticleBeyondTarget = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, true)
    s.data[0] = a[4]
    s.data[1] = s.x
    s.data[3] = s.y
    if a[7] == 0 then
      s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
      s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
    else
      s.data[2], s.data[4] = P.averagePositions(vm, P.tgt(vm), true)
    end
    if isOpp(P.atk(vm)) then s.data[2] = s.data[2] - a[2] else s.data[2] = s.data[2] + a[2] end
    s.data[4] = s.data[4] + a[3]
    initFastWithSpeed(s)
    local temp = rewind_offscreen(s)
    for i = 0, 7 do s.data[i] = temp[i] end
    s.data[5] = a[5]
    s.data[6] = a[6]
    s.callback = wiggleStep
  end
  wiggleStep = function(s)
    P.fastTranslateLinear(s)
    if s.data[0] == 0 then s.data[0] = 1 end
    s.oy = s.oy + P.Sin(s.data[7], s.data[5])
    s.data[7] = P.band(s.data[7] + s.data[6], 0xFF)
    if s.data[0] == 1 and offscreen(s) then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_ice.c:822
  CB.WaveFromCenterOfTarget = function(s)
    local vm = s._vm
    local a = args(s)
    if s.data[0] == 0 then
      if a[2] == 0 then
        P.initPosToTarget(vm, s, false)
      else
        s.x, s.y = P.averagePositions(vm, P.tgt(vm), false)
        if isOpp(P.atk(vm)) then a[0] = -a[0] end
        s.x = s.x + a[0]
        s.y = s.y + a[1]
      end
      s.data[0] = s.data[0] + 1
    elseif s.animEnded then
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_ice.c:913
  local function swirlingFog(s)
    if not P.translateLinear(s) then
      s.ox = s.ox + P.Sin(s.data[5], s.data[6])
      s.oy = s.oy + P.Cos(s.data[5], -6)
      local side = s._fogSide
      local bgp = (s._vm and s._vm._bgPrio and s._vm._bgPrio[require("src.core.game3.battle.anim_coords").bgPriorityRank(side)]) or 2
      if P.u16(s.data[5] - 64) <= 0x7F then
        P.setPriority(s, bgp, s.subpriority)
      else
        P.setPriority(s, bgp + 1, s.subpriority)
      end
      s.data[5] = P.band(s.data[5] + 3, 0xFF)
    else
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_ice.c:854
  CB.InitSwirlingFogAnim = function(s)
    local vm = s._vm
    local a = args(s)
    local side
    if a[4] == 0 then
      if a[5] == 0 then
        P.initPosToAttacker(vm, s, false)
      else
        s.x, s.y = P.averagePositions(vm, P.atk(vm), false)
        if isOpp(P.atk(vm)) then s.x = s.x - a[0] else s.x = s.x + a[0] end
        s.y = s.y + a[1]
      end
      side = P.atk(vm)
    else
      if a[5] == 0 then
        P.initPosToTarget(vm, s, false)
      else
        s.x, s.y = P.averagePositions(vm, P.tgt(vm), false)
        if isOpp(P.tgt(vm)) then s.x = s.x - a[0] else s.x = s.x + a[0] end
        s.y = s.y + a[1]
      end
      side = P.tgt(vm)
    end
    s._fogSide = side
    s.data[7] = P.sideId(side)
    s.data[6] = 0x20
    if P.tgt(vm) == "player" then s.y = s.y + 8 end
    s.data[0] = a[3]
    s.data[1] = s.x
    s.data[2] = s.x
    s.data[3] = s.y
    s.data[4] = s.y + a[2]
    P.initLinear(s)
    s.data[5] = 64
    s.callback = swirlingFog
    s.callback(s)
  end

  -- pokefirered/src/battle_anim_ice.c:1022
  CB.ThrowMistBall = function(s)
    local vm = s._vm
    s.x = P.coord(vm, P.atk(vm), P.X_2)
    s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
    s.callback = C.translateToTargetMonLocation
  end

  -- pokefirered/src/battle_anim_ice.c:1158
  local function movePoisonGas(s)
    local vm = s._vm
    local d = s.data
    local st = P.band(d[7], 0xFF)
    if st == 0 then
      P.translateLinear(s)
      s.ox = s.ox + P.asr(P.gSine(d[5]), 4)
      if d[6] ~= 0 then d[5] = P.band(d[5] - 8, 0xFF) else d[5] = P.band(d[5] + 8, 0xFF) end
      if d[0] <= 0 then
        d[0] = 80
        s.x = P.coord(vm, P.tgt(vm), P.X)
        d[1] = s.x
        d[2] = s.x
        s.y = s.y + s.oy
        d[3] = s.y
        d[4] = s.y + 29
        d[7] = d[7] + 1
        d[5] = isOpp(P.tgt(vm)) and 204 or 80
        s.oy = 0
        s.ox = P.asr(P.gSine(d[5]), 3)
        d[5] = P.band(d[5] + 2, 0xFF)
        P.initLinear(s)
      end
    elseif st == 1 then
      P.translateLinear(s)
      s.ox = s.ox + P.asr(P.gSine(d[5]), 3)
      s.oy = s.oy + P.asr(P.gSine(d[5] + 0x40) * -3, 8)
      local pr = P.rshift(P.u16(d[7]), 8)
      if P.u16(d[5] - 0x40) <= 0x7F then
        P.setPriority(s, pr, s.subpriority)
      else
        P.setPriority(s, pr + 1, s.subpriority)
      end
      d[5] = P.band(d[5] + 4, 0xFF)
      if d[0] <= 0 then
        d[0] = 0x300
        s.x = s.x + s.ox
        d[1] = s.x
        s.y = s.y + s.oy
        d[3] = s.y
        d[4] = s.y + 4
        d[2] = isOpp(P.tgt(vm)) and 0x100 or -0x10
        d[7] = d[7] + 1
        s.ox, s.oy = 0, 0
        P.initLinearWithSpeed(s)
      end
    elseif st == 2 then
      if P.translateLinear(s) then P.destroy(s) end
    end
  end

  -- pokefirered/src/battle_anim_ice.c:1118
  CB.InitPoisonGasCloudAnim = function(s)
    local vm = s._vm
    local a = args(s)
    s.data[0] = a[0]
    if P.coord(vm, P.atk(vm), P.X_2) < P.coord(vm, P.tgt(vm), P.X_2) then s.data[7] = P.s16(0x8000) end
    if P.tgt(vm) == "player" then
      a[1] = -a[1]
      a[3] = -a[3]
      if P.band(P.u16(s.data[7]), 0x8000) ~= 0 and P.atk(vm) == "player" then
        s.subpriority = P.subpriorityOf(P.tgt(vm)) + 1
      end
      s.data[6] = 1
    end
    s.x = P.coord(vm, P.atk(vm), P.X_2)
    s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
    local bgp = (vm._bgPrio and vm._bgPrio[require("src.core.game3.battle.anim_coords").bgPriorityRank(P.tgt(vm))]) or 2
    if a[7] ~= 0 then
      s.data[1] = s.x + a[1]
      s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + a[3]
      s.data[3] = s.y + a[2]
      s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[4]
    else
      s.data[1] = s.x + a[1]
      s.data[2] = P.coord(vm, P.tgt(vm), P.X) + a[3]
      s.data[3] = s.y + a[2]
      s.data[4] = P.coord(vm, P.tgt(vm), P.Y) + a[4]
    end
    s.data[7] = P.s16(P.bor(P.u16(s.data[7]), P.lshift(bgp, 8)))
    P.initLinear(s)
    P.setPriority(s, s.oamPriority or 2, s.subpriority)
    s.callback = movePoisonGas
  end

  -- pokefirered/src/battle_anim_ice.c:1427
  local function throwIceBall(s)
    if P.translateHArc(s) then
      P.startAnim(s, 1)
      s.callback = P.runStoredWhenAnimEnds
      P.storeCb(s, P.destroy)
    end
  end

  -- pokefirered/src/battle_anim_ice.c:1408
  CB.InitIceBallAnim = function(s)
    local vm = s._vm
    local a = args(s)
    local ctx = vm.ctx or {}
    local animNum = P.u8((ctx.rolloutTimerStartValue or 0) - (ctx.rolloutTimer or 0) - 1)
    if animNum > 4 then animNum = 4 end
    P.startAffineAnim(s, animNum)
    P.initPosToAttacker(vm, s, true)
    s.data[0] = a[4]
    if isOpp(P.atk(vm)) then a[2] = -a[2] end
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + a[2]
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[3]
    s.data[5] = a[5]
    P.initArc(s)
    s.callback = throwIceBall
  end

  -- pokefirered/src/battle_anim_ice.c:1454
  local function iceBallParticle(s)
    s.data[3] = P.s16(s.data[3] + s.data[1])
    s.data[4] = P.s16(s.data[4] + s.data[2])
    if P.band(s.data[1], 1) ~= 0 then
      s.ox = -P.asr(s.data[3], 8)
    else
      s.ox = P.asr(s.data[3], 8)
    end
    s.oy = P.asr(s.data[4], 8)
    s.data[0] = s.data[0] + 1
    if s.data[0] == 21 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_ice.c:1438
  CB.InitIceBallParticle = function(s)
    local vm = s._vm
    P.addTile(s, 8)
    P.initPosToTarget(vm, s, true)
    local randA = P.band(P.Random(), 0xFF) + 256
    local randB = P.band(P.Random(), 0x1FF)
    if randB > 0xFF then randB = 256 - randB end
    s.data[1] = randA
    s.data[2] = randB
    s.callback = iceBallParticle
  end

  -- pokefirered/src/battle_anim_rock.c:327
  local function fallingRockStep(s)
    s.x = s.x + s.data[5]
    s.data[0] = 192
    s.data[1] = s.data[5]
    s.data[2] = 4
    s.data[3] = 32
    s.data[4] = -24
    P.storeCb(s, P.destroy)
    s.callback = P.translateInEllipse
    s.callback(s)
  end

  -- pokefirered/src/battle_anim_rock.c:308
  CB.FallingRock = function(s)
    local vm = s._vm
    local a = args(s)
    if a[3] ~= 0 then s.x, s.y = P.averagePositions(vm, P.tgt(vm), false) end
    s.x = s.x + a[0]
    s.y = s.y + 14
    P.startAnim(s, a[1])
    P.animate(s)
    s.data[0] = 0
    s.data[1] = 0
    s.data[2] = 4
    s.data[3] = 16
    s.data[4] = -70
    s.data[5] = a[2]
    P.storeCb(s, fallingRockStep)
    s.callback = P.translateInEllipse
    s.callback(s)
  end

  -- pokefirered/src/battle_anim_rock.c:341
  CB.RockFragment = function(s)
    local vm = s._vm
    local a = args(s)
    P.startAnim(s, a[5])
    P.animate(s)
    if isOpp(P.atk(vm)) then s.x = s.x - a[0] else s.x = s.x + a[0] end
    s.y = s.y + a[1]
    s.data[0] = a[4]
    s.data[1] = s.x
    s.data[2] = s.x + a[2]
    s.data[3] = s.y
    s.data[4] = s.y + a[3]
    C.initSpriteDataForLinearTranslation(s)
    s.data[3] = 0
    s.data[4] = 0
    s.callback = P.translateSpriteLinearFixedPoint
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_rock.c:376
  local function vortexStep(s)
    s.data[4] = P.s16(s.data[4] + s.data[1])
    s.oy = -P.asr(s.data[4], 8)
    s.ox = P.Sin(s.data[5], s.data[3])
    s.data[5] = P.band(s.data[5] + s.data[2], 0xFF)
    s.data[0] = s.data[0] - 1
    if s.data[0] == -1 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_rock.c:363
  CB.ParticleInVortex = function(s)
    local vm = s._vm
    local a = args(s)
    if a[6] == 0 then P.initPosToAttacker(vm, s, false) else P.initPosToTarget(vm, s, false) end
    s.data[0] = a[3]
    s.data[1] = a[2]
    s.data[2] = a[4]
    s.data[3] = a[5]
    s.callback = vortexStep
  end

  -- pokefirered/src/battle_anim_rock.c:131
  local function drawSandCrescent(s, vm)
    local img = s.image
    if not img or s.visible == false then return end
    local iw, ih = img:getDimensions()
    s._crescentQuads = s._crescentQuads or {
      love.graphics.newQuad(0, 0, 32, 16, iw, ih),
      love.graphics.newQuad(0, 16, 32, 16, iw, ih),
    }
    local cx = math.floor(s.x + s.ox + 0.5)
    local cy = math.floor(s.y + s.oy + 0.5)
    local flip = s.hFlip and -1 or 1
    love.graphics.setColor(1, 1, 1, s._drawAlpha or 1)
    local AnimPal = require("src.core.game3.battle.anim_pal")
    local pimg = AnimPal.beginSprite(s, img, vm)
    love.graphics.draw(pimg or img, s._crescentQuads[1], cx + (-16 * flip), cy, 0, flip, 1, 16, 8)
    love.graphics.draw(pimg or img, s._crescentQuads[2], cx + (16 * flip), cy, 0, flip, 1, 16, 8)
    if pimg then AnimPal.finish() end
  end

  -- pokefirered/src/battle_anim_rock.c:484
  CB.FlyingSandCrescent = function(s)
    local vm = s._vm
    local a = args(s)
    if s.data[0] == 0 then
      if a[3] ~= 0 and isOpp(P.atk(vm)) then
        s.x = 304
        a[1] = -a[1]
        s.data[5] = 1
        P.setHFlip(s, true)
      else
        s.x = -64
      end
      s.y = a[0]
      s.customDraw = drawSandCrescent
      P.setPriority(s, 1, s.subpriority)
      s.data[1] = a[1]
      s.data[2] = a[2]
      s.data[0] = s.data[0] + 1
    else
      s.data[3] = s.data[3] + s.data[1]
      s.data[4] = s.data[4] + s.data[2]
      s.ox = s.ox + P.asr(s.data[3], 8)
      s.oy = s.oy + P.asr(s.data[4], 8)
      s.data[3] = P.band(s.data[3], 0xFF)
      s.data[4] = P.band(s.data[4], 0xFF)
      if s.data[5] == 0 then
        if s.x + s.ox > 240 + 32 then s.callback = P.destroy end
      elseif s.x + s.ox < -32 then
        s.callback = P.destroy
      end
    end
  end

  -- pokefirered/src/battle_anim_rock.c:533
  CB.RaiseSprite = function(s)
    local vm = s._vm
    local a = args(s)
    P.startAnim(s, a[4])
    P.initPosToAttacker(vm, s, false)
    s.data[0] = a[3]
    s.data[2] = s.x
    s.data[4] = s.y + a[2]
    s.callback = P.startLinear
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_rock.c:727
  local function rockTombStep(s)
    P.setInvisible(s, false)
    if s.data[3] ~= 0 then
      s.oy = s.data[2] + s.data[3]
      s.data[3] = s.data[3] + s.data[0]
      s.data[0] = s.data[0] + 1
      if s.data[3] > 0 then s.data[3] = 0 end
    else
      s.data[1] = s.data[1] - 1
      if s.data[1] == 0 then P.destroy(s) end
    end
  end

  -- pokefirered/src/battle_anim_rock.c:715
  CB.RockTomb = function(s)
    local a = args(s)
    P.startAnim(s, a[4])
    s.ox = a[0]
    s.data[2] = a[1]
    s.data[3] = s.data[3] - a[2]
    s.data[0] = 3
    s.data[1] = a[3]
    s.callback = rockTombStep
    P.setInvisible(s, true)
  end

  -- pokefirered/src/battle_anim_rock.c:746
  CB.RockBlastRock = function(s)
    if P.atk(s._vm) == "enemy" then P.startAffineAnim(s, 1) end
    C.translateToTargetMonLocation(s)
  end

  -- pokefirered/src/battle_anim_rock.c:766
  local function rockScatterStep(s)
    s.data[0] = s.data[0] + 8
    s.data[3] = s.data[3] + s.data[1]
    s.data[4] = s.data[4] + s.data[2]
    s.ox = s.ox + P.cdiv(s.data[3], 40)
    s.oy = s.oy - P.Sin(s.data[0], s.data[5])
    if s.data[0] > 140 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_rock.c:753
  CB.RockScatter = function(s)
    local vm = s._vm
    local a = args(s)
    s.x = P.coord(vm, P.tgt(vm), P.X)
    s.y = P.coord(vm, P.tgt(vm), P.Y)
    s.x = s.x + a[0]
    s.y = s.y + a[1]
    s.data[1] = a[0]
    s.data[2] = a[1]
    s.data[5] = a[2]
    P.startAnim(s, a[3])
    s.callback = rockScatterStep
  end

  -- pokefirered/src/battle_anim_rock.c:693
  function C.rolloutParticle(s)
    if P.translateHArc(s) then
      local t = s._task
      if t and t.active and t._g4rollout then t.data[11] = t.data[11] - 1 end
      P.destroy(s)
    end
  end

  -- pokefirered/src/battle_anim_water.c:496
  local function rainDropStep(s)
    s.data[0] = s.data[0] + 1
    if s.data[0] < 14 then
      s.ox = s.ox + 1
      s.oy = s.oy + 4
    end
    if s.animEnded then P.destroy(s) end
  end
  function C.rainDrop(s)
    s.callback = rainDropStep
  end

  -- pokefirered/src/battle_anim_water.c:515
  local bubbleProjStep1, bubbleProjStep2, bubbleProjStep3
  CB.WaterBubbleProjectile = function(s)
    local vm = s._vm
    local a = args(s)
    if isOpp(P.atk(vm)) then
      s.x = P.coord(vm, P.atk(vm), P.X_2) - a[0]
    else
      s.x = P.coord(vm, P.atk(vm), P.X_2) + a[0]
    end
    s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET) + a[1]
    s.animPaused = true
    if isOpp(P.atk(vm)) then a[2] = -a[2] end
    s.data[0] = a[6]
    s.data[1] = s.x
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
    s.data[3] = s.y
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
    P.initLinear(s)
    local o = { data = { [0] = a[2], [1] = a[3], [2] = a[5], [3] = P.s16(P.u8(a[4]) * 256), [4] = a[6] } }
    s._other = o
    s.x = s.x - P.Sin(P.u8(a[4]), a[2])
    s.y = s.y - P.Cos(P.u8(a[4]), a[3])
    s.callback = bubbleProjStep1
    s.callback(s)
  end
  bubbleProjStep1 = function(s)
    local o = s._other
    local timer = P.u8(o.data[4])
    local trig = P.u16(o.data[3])
    s.data[0] = 1
    P.translateLinear(s)
    s.ox = s.ox + P.Sin(P.rshift(trig, 8), o.data[0])
    s.oy = s.oy + P.Cos(P.rshift(trig, 8), o.data[1])
    o.data[3] = P.s16(trig + o.data[2])
    timer = P.u8(timer - 1)
    if timer ~= 0 then
      o.data[4] = timer
    else
      s.callback = bubbleProjStep2
    end
  end
  bubbleProjStep2 = function(s)
    s.animPaused = false
    s.callback = P.runStoredWhenAnimEnds
    P.storeCb(s, bubbleProjStep3)
  end
  bubbleProjStep3 = function(s)
    s.data[0] = 10
    s.callback = P.waitAnimForDuration
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_water.c:588
  local auroraStep
  CB.AuroraBeamRings = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, true)
    local unk = isOpp(P.atk(vm)) and -a[2] or a[2]
    s.data[0] = a[4]
    s.data[1] = s.x
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + unk
    s.data[3] = s.y
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + a[3]
    P.initLinear(s)
    s.callback = auroraStep
    s.affineAnimPaused = true
    s.callback(s)
  end
  auroraStep = function(s)
    if P.u16(s._vm.args[7]) == 0xFFFF then
      P.startAnim(s, 1)
      s.affineAnimPaused = false
    end
    if P.translateLinear(s) then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_water.c:646
  local sinWaveStep
  CB.ToTargetInSinWave = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, true)
    s.data[0] = 30
    s.data[1] = s.x
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
    s.data[3] = s.y
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
    P.initLinear(s)
    s.data[5] = P.cdiv(0xD200, s.data[0])
    s.data[7] = a[3]
    local retArg = P.u16(a[7])
    if a[7] > 127 then
      s.data[6] = P.s16((retArg - 127) * 256)
      s.data[7] = -s.data[7]
    else
      s.data[6] = P.s16(retArg * 256)
    end
    s.callback = sinWaveStep
    s.callback(s)
  end
  sinWaveStep = function(s)
    if P.translateLinear(s) then P.destroy(s) end
    s.oy = s.oy + P.Sin(P.asr(s.data[6], 8), s.data[7])
    if P.asr(s.data[6] + s.data[5], 8) > 127 then
      s.data[6] = 0
      s.data[7] = -s.data[7]
    else
      s.data[6] = P.s16(s.data[6] + s.data[5])
    end
  end

  -- pokefirered/src/battle_anim_water.c:704
  CB.HydroCannonCharge = function(s)
    local vm = s._vm
    s.x = P.coord(vm, P.atk(vm), P.X)
    s.y = P.coord(vm, P.atk(vm), P.Y)
    s.oy = -10
    local pr = P.subpriorityOf(P.atk(vm))
    if P.atk(vm) == "player" then
      s.ox = 10
      P.setPriority(s, s.oamPriority, pr + 2)
    else
      s.ox = -10
      P.setPriority(s, s.oamPriority, pr - 2)
    end
    s.callback = function(sp)
      if sp.affineAnimEnded then P.destroy(sp) end
    end
  end

  -- pokefirered/src/battle_anim_water.c:740
  CB.HydroCannonBeam = function(s)
    local vm = s._vm
    local a = args(s)
    if P.atk(vm) == P.tgt(vm) then
      a[0] = -a[0]
      a[0] = -a[0]
    end
    local animType = P.band(P.u16(a[5]), 0xFF00) == 0
    local coordType = (P.u8(a[5]) == 0) and P.Y_PIC_OFFSET or P.Y
    P.initPosToAttacker(vm, s, animType)
    if isOpp(P.atk(vm)) then a[2] = -a[2] end
    s.data[0] = a[4]
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + a[2]
    s.data[4] = P.coord(vm, P.tgt(vm), coordType) + a[3]
    s.callback = P.startLinear
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_water.c:769
  CB.WaterGunDroplet = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToTarget(vm, s, true)
    s.data[0] = a[4]
    s.data[2] = s.x + a[2]
    s.data[4] = s.y + a[4]
    s.callback = P.startLinear
    P.storeCb(s, P.destroy)
  end

  -- pokefirered/src/battle_anim_water.c:779
  local bubblePairStep
  CB.SmallBubblePair = function(s)
    local vm = s._vm
    local a = args(s)
    if a[3] ~= P.ANIM_ATTACKER then P.initPosToTarget(vm, s, true) else P.initPosToAttacker(vm, s, true) end
    s.data[7] = a[2]
    s.callback = bubblePairStep
  end
  bubblePairStep = function(s)
    s.data[0] = P.band(s.data[0] + 11, 0xFF)
    s.ox = P.Sin(s.data[0], 4)
    s.data[1] = s.data[1] + 48
    s.oy = -P.asr(s.data[1], 8)
    local v = s.data[7]
    s.data[7] = v - 1
    if v == 0 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_water.c:1011
  local driftStep
  CB.SmallDriftingBubbles = function(s)
    local vm = s._vm
    P.addTile(s, 8)
    P.initPosToTarget(vm, s, true)
    local randData = P.bor(P.band(P.Random(), 0xFF), 256)
    local randData2 = P.band(P.Random(), 0x1FF)
    if randData2 > 255 then randData2 = 256 - randData2 end
    s.data[1] = randData
    s.data[2] = randData2
    s.callback = driftStep
  end
  driftStep = function(s)
    s.data[3] = P.s16(s.data[3] + s.data[1])
    s.data[4] = P.s16(s.data[4] + s.data[2])
    if P.band(s.data[1], 1) ~= 0 then s.ox = -P.asr(s.data[3], 8) else s.ox = P.asr(s.data[3], 8) end
    s.oy = P.asr(s.data[4], 8)
    s.data[0] = s.data[0] + 1
    if s.data[0] == 21 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_water.c:1483
  local pulseBubbleStep
  CB.WaterPulseBubble = function(s)
    local a = args(s)
    s.x = a[0]
    s.y = a[1]
    s.data[0] = a[2]
    s.data[1] = a[3]
    s.data[2] = a[4]
    s.data[3] = a[5]
    s.callback = pulseBubbleStep
  end
  pulseBubbleStep = function(s)
    s.data[4] = P.s16(s.data[4] - s.data[0])
    s.oy = P.cdiv(s.data[4], 10)
    s.data[5] = P.band(s.data[5] + s.data[1], 0xFF)
    s.ox = P.Sin(s.data[5], s.data[2])
    s.data[3] = s.data[3] - 1
    if s.data[3] == 0 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_water.c:1504
  local function pulseRingBubble(s)
    s.data[3] = P.s16(s.data[3] + s.data[1])
    s.data[4] = P.s16(s.data[4] + s.data[2])
    s.ox = P.asr(s.data[3], 7)
    s.oy = P.asr(s.data[4], 7)
    s.data[0] = s.data[0] - 1
    if s.data[0] == 0 then P.destroy(s) end
  end

  -- pokefirered/src/battle_anim_water.c:1544
  local function createPulseRingBubbles(s, xDiff, yDiff)
    local vm = s._vm
    local something = P.cdiv(s.data[0], 2)
    local cx = s.x + s.ox
    local cy = s.y + s.oy
    local ry = P.s16(yDiff + (P.Random() % 10) - 5)
    local rx = P.s16(-xDiff + (P.Random() % 10) - 5)
    local sub = P.subpriorityOf(P.atk(vm)) - 1
    local tpl = T.gWaterPulseRingBubbleSpriteTemplate
    local b1 = P.createSprite(vm, "SMALL_BUBBLES", tpl, cx, cy + something, sub, pulseRingBubble, 8, 8)
    if b1 then
      b1.data[0] = 20
      b1.data[1] = ry
      b1.data[2] = (rx < 0) and -rx or rx
    end
    local b2 = P.createSprite(vm, "SMALL_BUBBLES", tpl, cx, cy - something, sub, pulseRingBubble, 8, 8)
    if b2 then
      b2.data[0] = 20
      b2.data[1] = ry
      b2.data[2] = (rx > 0) and -rx or rx
    end
  end

  -- pokefirered/src/battle_anim_water.c:1517
  local pulseRingStep
  CB.WaterPulseRing = function(s)
    local vm = s._vm
    local a = args(s)
    P.initPosToAttacker(vm, s, true)
    s.data[1] = P.coord(vm, P.tgt(vm), P.X_2)
    s.data[2] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
    s.data[3] = a[2]
    s.data[4] = a[3]
    s.callback = pulseRingStep
  end
  pulseRingStep = function(s)
    local xDiff = s.data[1] - s.x
    local yDiff = s.data[2] - s.y
    if s.data[3] ~= 0 then
      s.ox = P.cdiv(s.data[0] * xDiff, s.data[3])
      s.oy = P.cdiv(s.data[0] * yDiff, s.data[3])
    end
    s.data[5] = s.data[5] + 1
    if s.data[5] == s.data[4] then
      s.data[5] = 0
      createPulseRingBubbles(s, xDiff, yDiff)
    end
    if s.data[3] == s.data[0] then P.destroy(s) end
    s.data[0] = s.data[0] + 1
  end

  return CB
end
