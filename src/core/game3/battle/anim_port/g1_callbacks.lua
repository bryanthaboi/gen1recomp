local bit = require("bit")
local P = require("src.core.game3.battle.anim_port.g1_pret")
local S = require("src.core.game3.battle.anim_port.g1_sprite")

local band, bxor, rshift, arshift, lshift = bit.band, bit.bxor, bit.rshift, bit.arshift, bit.lshift
local s16, u16 = P.s16, P.u16
local Sin, Cos = P.Sin, P.Cos

local C = {}
local F = {}

local function random16()
  return math.random(0, 0xFFFF)
end

local function atk_opp(s)
  return P.isOpponent(P.atk(s._vm))
end

-- pokefirered/src/battle_anim_normal.c:283
function F.ConfusionDuckStep(s)
  local d = s.data
  s.ox = Cos(d[0], 30)
  s.oy = Sin(d[0], 10)
  if u16(d[0]) < 128 then s._pri = 1 else s._pri = 3 end
  d[0] = band(d[0] + d[1], 0xFF)
  d[2] = d[2] + 1
  if d[2] == d[3] then S.destroy(s) end
end

-- pokefirered/src/battle_anim_normal.c:262
C.ConfusionDuck = S.wrap(function(s)
  local A, d = s._A, s.data
  s.x = s.x + A[0]
  s.y = s.y + A[1]
  d[0] = A[2]
  if atk_opp(s) then
    d[1] = -A[3]
    d[4] = 1
  else
    d[1] = A[3]
    d[4] = 0
    S.startAnim(s, 1)
  end
  d[3] = A[4]
  s._cb = F.ConfusionDuckStep
  s._cb(s)
end)

-- pokefirered/src/battle_anim_normal.c:911
local function hit_splat_basic(s)
  local A = s._A
  S.startAffineAnim(s, A[3])
  if A[2] == 0 then S.initPosToAttacker(s, true) else S.initPosToTarget(s, true) end
  s._cb = S.runStoredWhenAffineEnds
  S.store(s, S.destroy)
end
C.HitSplatBasic = S.wrap(hit_splat_basic)

-- pokefirered/src/battle_anim_normal.c:923
C.HitSplatPersistent = S.wrap(function(s)
  local A = s._A
  S.startAffineAnim(s, A[3])
  if A[2] == 0 then S.initPosToAttacker(s, true) else S.initPosToTarget(s, true) end
  s.data[0] = A[4]
  s._cb = S.runStoredWhenAffineEnds
  S.store(s, F.DestroyAfterTimer)
end)

-- pokefirered/src/battle_anim_flying.c:533
function F.DestroyAfterTimer(s)
  local old = s.data[0]
  s.data[0] = old - 1
  if old <= 0 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_normal.c:937
C.HitSplatHandleInvert = S.wrap(function(s)
  if atk_opp(s) then s._A[1] = -s._A[1] end
  hit_splat_basic(s)
end)

-- pokefirered/src/battle_anim_normal.c:944
C.HitSplatRandom = S.wrap(function(s)
  local A = s._A
  if A[1] == -1 then A[1] = band(random16(), 3) end
  S.startAffineAnim(s, A[1])
  if A[0] == P.ANIM_ATTACKER then S.initPosToAttacker(s, false) else S.initPosToTarget(s, false) end
  s.ox = s.ox + (random16() % 48) - 24
  s.oy = s.oy + (random16() % 24) - 12
  S.store(s, S.destroy)
  s._cb = S.runStoredWhenAffineEnds
end)

-- pokefirered/src/battle_anim_normal.c:959
C.HitSplatOnMonEdge = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local side = P.sideOf(vm, A[0])
  local p = P.present(side)
  s.x = P.coord(vm, side, P.X_2) + (p and p.ox or 0)
  s.y = P.coord(vm, side, P.Y_PIC_OFFSET_DEFAULT) + (p and p.oy or 0)
  s.ox = A[1]
  s.oy = A[2]
  S.startAffineAnim(s, A[3])
  S.store(s, S.destroy)
  s._cb = S.runStoredWhenAffineEnds
end)

-- pokefirered/src/battle_anim_normal.c:971
C.CrossImpact = S.wrap(function(s)
  local A = s._A
  if A[2] == P.ANIM_ATTACKER then S.initPosToAttacker(s, true) else S.initPosToTarget(s, true) end
  s.data[0] = A[3]
  S.store(s, S.destroy)
  s._cb = S.waitAnimForDuration
end)

-- pokefirered/src/battle_anim_normal.c:992
function F.FlashingHitSplatStep(s)
  s.visible = not s.visible
  local old = s.data[0]
  s.data[0] = old + 1
  if old > 12 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_normal.c:982
C.FlashingHitSplat = S.wrap(function(s)
  local A = s._A
  S.startAffineAnim(s, A[3])
  if A[2] == P.ANIM_ATTACKER then S.initPosToAttacker(s, true) else S.initPosToTarget(s, true) end
  s._cb = F.FlashingHitSplatStep
end)

-- pokefirered/src/battle_anim_mons.c:1409
C.SpriteOnMonPos = S.wrap(function(s)
  s._cb = function(sp)
    if sp.data[0] == 0 then
      local var = sp._A[3] == 0
      if sp._A[2] == 0 then S.initPosToAttacker(sp, var) else S.initPosToTarget(sp, var) end
      sp.data[0] = sp.data[0] + 1
    elseif sp.animEnded or sp.affineAnimEnded then
      S.destroy(sp)
    end
  end
  s._cb(s)
end)

-- pokefirered/src/battle_anim_mons.c:1440
C.TranslateAnimSpriteToTargetMonLocation = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local respect = band(u16(A[5]), 0xFF00) == 0
  local coordType = band(u16(A[5]), 0xFF) == 0 and P.Y_PIC_OFFSET or P.Y
  S.initPosToAttacker(s, respect)
  if atk_opp(s) then A[2] = -A[2] end
  s.data[0] = A[4]
  s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + A[2]
  s.data[4] = P.coord(vm, P.tgt(vm), coordType) + A[3]
  s._cb = S.startLinear
  S.store(s, S.destroy)
end)

-- pokefirered/src/battle_anim_mons.c:1463
C.ThrowProjectile = S.wrap(function(s)
  local A, vm = s._A, s._vm
  S.initPosToAttacker(s, true)
  if atk_opp(s) then A[2] = -A[2] end
  s.data[0] = A[4]
  s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + A[2]
  s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + A[3]
  s.data[5] = A[5]
  S.initArc(s)
  s._cb = function(sp)
    if S.translateHArc(sp) then S.destroy(sp) end
  end
end)

-- pokefirered/src/battle_anim_mons.c:1482
C.TravelDiagonally = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local r4, coordType, side
  if A[6] == 0 then
    r4 = true
    coordType = P.Y_PIC_OFFSET
  else
    r4 = false
    coordType = P.Y
  end
  if A[5] == 0 then
    S.initPosToAttacker(s, r4)
    side = P.atk(vm)
  else
    S.initPosToTarget(s, r4)
    side = P.tgt(vm)
  end
  if atk_opp(s) then A[2] = -A[2] end
  S.initPosToTarget(s, r4)
  s.data[0] = A[4]
  s.data[2] = P.coord(vm, side, P.X_2) + A[2]
  s.data[4] = P.coord(vm, side, coordType) + A[3]
  s._cb = S.startLinear
  S.store(s, S.destroy)
end)

-- pokefirered/src/battle_anim_mons.c:2188
C.SpinningSparkle = S.wrap(function(s)
  local A = s._A
  S.setToAttackerCoords(s)
  if atk_opp(s) then s.x = s.x - A[0] else s.x = s.x + A[0] end
  s.y = s.y + A[1]
  s._cb = S.runStoredWhenAnimEnds
  S.store(s, S.destroy)
end)

-- pokefirered/src/battle_anim_mons.c:2327
function F.WeatherBallUpStep(s)
  local d = s.data
  d[2] = s16(d[2] + d[0])
  d[3] = s16(d[3] + d[1])
  s.ox = P.cdiv(d[2], 10)
  s.oy = P.cdiv(d[3], 10)
  if d[1] < -20 then d[1] = d[1] + 1 end
  if s.y + s.oy < -32 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_mons.c:2315
C.WeatherBallUp = S.wrap(function(s)
  local vm = s._vm
  s.x = P.coord(vm, P.atk(vm), P.X_2)
  s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
  if not atk_opp(s) then s.data[0] = 5 else s.data[0] = -10 end
  s.data[1] = -40
  s._cb = F.WeatherBallUpStep
end)

-- pokefirered/src/battle_anim_mons.c:2339
C.WeatherBallDown = S.wrap(function(s)
  local A, vm = s._A, s._vm
  s.data[0] = A[2]
  s.data[2] = s.x + A[4]
  s.data[4] = s.y + A[5]
  if not P.isOpponent(P.tgt(vm)) then
    s.x = s16(s.x + u16(A[4]) + 30)
    s.y = A[5] - 20
  else
    s.x = s16(s.x + u16(A[4]) - 30)
    s.y = A[5] - 80
  end
  s._cb = S.startLinear
  S.store(s, S.destroy)
end)

-- pokefirered/src/battle_anim_effects_1.c:2247
function F.MovePowderParticleStep(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    s.oy = arshift(d[2], 8)
    d[2] = s16(d[2] + d[1])
    s.ox = Sin(d[5], d[3])
    d[5] = band(d[5] + d[4], 0xFF)
  else
    S.destroy(s)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:2227
C.MovePowderParticle = S.wrap(function(s)
  local A, d = s._A, s.data
  s.x = s.x + A[0]
  s.y = s.y + A[1]
  d[0] = A[2]
  d[1] = A[3]
  if atk_opp(s) then d[3] = -A[4] else d[3] = A[4] end
  d[4] = A[5]
  s._cb = F.MovePowderParticleStep
end)

-- pokefirered/src/battle_anim_effects_1.c:2267
C.PowerAbsorptionOrb = S.wrap(function(s)
  local A, vm = s._A, s._vm
  S.initPosToAttacker(s, true)
  s.data[0] = A[2]
  s.data[2] = P.coord(vm, P.atk(vm), P.X_2)
  s.data[4] = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
  s._cb = S.startLinear
  S.store(s, S.destroy)
end)

-- pokefirered/src/battle_anim_effects_1.c:2282
C.SolarBeamBigOrb = S.wrap(function(s)
  local A, vm = s._A, s._vm
  S.initPosToAttacker(s, true)
  S.startAnim(s, A[3])
  s.data[0] = A[2]
  s.data[2] = P.coord(vm, P.tgt(vm), P.X_2)
  s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
  s._cb = S.startLinear
  S.store(s, S.destroy)
end)

-- pokefirered/src/battle_anim_effects_1.c:2313
function F.SolarBeamSmallOrbStep(s)
  local vm = s._vm
  if S.translateLinear(s) then
    S.destroy(s)
  else
    if s.data[5] > 0x7F then
      s.subpriority = P.subpriorityOf(P.tgt(vm)) + 1
    else
      s.subpriority = P.subpriorityOf(P.tgt(vm)) + 6
    end
    s.ox = s.ox + Sin(s.data[5], 5)
    s.oy = s.oy + Cos(s.data[5], 14)
    s.data[5] = band(s.data[5] + 15, 0xFF)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:2299
C.SolarBeamSmallOrb = S.wrap(function(s)
  local A, vm, d = s._A, s._vm, s.data
  S.initPosToAttacker(s, true)
  d[0] = A[2]
  d[1] = s.x
  d[2] = P.coord(vm, P.tgt(vm), P.X_2)
  d[3] = s.y
  d[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
  S.initLinear(s)
  d[5] = A[3]
  s._cb = F.SolarBeamSmallOrbStep
  s._cb(s)
end)

-- pokefirered/src/battle_anim_effects_1.c:2357
C.AbsorptionOrb = S.wrap(function(s)
  local A, vm = s._A, s._vm
  S.initPosToTarget(s, true)
  s.data[0] = A[3]
  s.data[2] = P.coord(vm, P.atk(vm), P.X_2)
  s.data[4] = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
  s.data[5] = A[2]
  S.initArc(s)
  s._cb = function(sp)
    if S.translateHArc(sp) then S.destroy(sp) end
  end
end)

-- pokefirered/src/battle_anim_effects_1.c:2402
function F.HyperBeamOrbStep(s)
  local d = s.data
  if S.fastTranslateLinear(s) then
    S.destroy(s)
  else
    s.oy = s.oy + Cos(d[5], 12)
    if d[5] < 0x7F then s.subpriority = d[6] else s.subpriority = d[6] + 1 end
    d[5] = band(d[5] + 24, 0xFF)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:2376
C.HyperBeamOrb = S.wrap(function(s)
  local vm, d = s._vm, s.data
  S.startAnim(s, random16() % 8)
  s.x = P.coord(vm, P.atk(vm), P.X_2)
  s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
  if atk_opp(s) then s.x = s.x - 20 else s.x = s.x + 20 end
  d[0] = band(random16(), 31) + 64
  d[1] = s.x
  d[2] = P.coord(vm, P.tgt(vm), P.X_2)
  d[3] = s.y
  d[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
  S.initFastLinearWithSpeed(s)
  d[5] = band(random16(), 0xFF)
  d[6] = s.subpriority
  s._cb = F.HyperBeamOrbStep
  s._cb(s)
end)

-- pokefirered/src/battle_anim_effects_1.c:2454
function F.LeechSeedSprouts(s)
  s.visible = true
  S.startAnim(s, 1)
  s.data[0] = 60
  s._cb = S.waitAnimForDuration
  S.store(s, S.destroy)
end

-- pokefirered/src/battle_anim_effects_1.c:2443
function F.LeechSeedStep(s)
  if S.translateHArc(s) then
    s.visible = false
    s.data[0] = 10
    s._cb = S.waitAnimForDuration
    S.store(s, F.LeechSeedSprouts)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:2429
C.LeechSeed = S.wrap(function(s)
  local A, vm = s._A, s._vm
  S.initPosToAttacker(s, true)
  if atk_opp(s) then A[2] = -A[2] end
  s.data[0] = A[4]
  s.data[2] = P.coord(vm, P.tgt(vm), P.X) + A[2]
  s.data[4] = P.coord(vm, P.tgt(vm), P.Y) + A[3]
  s.data[5] = A[5]
  S.initArc(s)
  s._cb = F.LeechSeedStep
end)

-- pokefirered/src/battle_anim_effects_1.c:2484
function F.SporeParticleStep(s)
  local d, vm = s.data, s._vm
  s.ox = Sin(d[1], 32)
  d[2] = s16(d[2] + 24)
  s.oy = Cos(d[1], -3) + arshift(d[2], 8)
  if u16(d[1] - 0x40) < 0x80 then
    s._pri = P.bgPriorityOf(P.tgt(vm))
  else
    local pri = P.bgPriorityOf(P.tgt(vm)) + 1
    if pri > 3 then pri = 3 end
    s._pri = pri
  end
  d[1] = band(d[1] + 2, 0xFF)
  d[0] = d[0] - 1
  if d[0] == -1 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:2471
C.SporeParticle = S.wrap(function(s)
  local A = s._A
  S.initPosToTarget(s, true)
  S.startAnim(s, A[4])
  if A[4] == 1 then s.objBlend = true end
  s.data[0] = A[3]
  s.data[1] = A[2]
  s._cb = F.SporeParticleStep
  s._cb(s)
end)

-- pokefirered/src/battle_anim_effects_1.c:2547
function F.PetalDanceBigFlowerStep(s)
  local vm, d = s._vm, s.data
  if not S.translateLinear(s) then
    s.ox = s.ox + Sin(d[5], 32)
    s.oy = s.oy + Cos(d[5], -5)
    if u16(d[5] - 0x40) < 0x80 then
      s.subpriority = P.subpriorityOf(P.atk(vm)) - 1
    else
      s.subpriority = P.subpriorityOf(P.atk(vm)) + 1
    end
    d[5] = band(d[5] + 5, 0xFF)
  else
    S.destroy(s)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:2533
C.PetalDanceBigFlower = S.wrap(function(s)
  local A, vm, d = s._A, s._vm, s.data
  S.initPosToAttacker(s, false)
  d[0] = A[3]
  d[1] = s.x
  d[2] = s.x
  d[3] = s.y
  d[4] = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET) + A[2]
  S.initLinear(s)
  d[5] = 0x40
  s._cb = F.PetalDanceBigFlowerStep
  s._cb(s)
end)

-- pokefirered/src/battle_anim_effects_1.c:2585
function F.PetalDanceSmallFlowerStep(s)
  local d = s.data
  if not S.translateLinear(s) then
    s.ox = s.ox + Sin(d[5], 8)
    if u16(d[5] - 59) < 5 or u16(d[5] - 187) < 5 then s._oamH = not s._oamH end
    d[5] = band(d[5] + 5, 0xFF)
  else
    S.destroy(s)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:2571
C.PetalDanceSmallFlower = S.wrap(function(s)
  local A, vm, d = s._A, s._vm, s.data
  S.initPosToAttacker(s, true)
  d[0] = A[3]
  d[1] = s.x
  d[2] = s.x
  d[3] = s.y
  d[4] = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET) + A[2]
  S.initLinear(s)
  d[5] = 0x40
  s._cb = F.PetalDanceSmallFlowerStep
  s._cb(s)
end)

-- pokefirered/src/battle_anim_effects_1.c:2642
function F.RazorLeafParticleStep2(s)
  local d = s.data
  if atk_opp(s) then s.ox = -Sin(d[0], 25) else s.ox = Sin(d[0], 25) end
  d[0] = band(d[0] + 2, 0xFF)
  d[1] = d[1] + 1
  if band(d[1], 1) == 0 then s.oy = s.oy + 1 end
  if d[1] > 80 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:2616
function F.RazorLeafParticleStep1(s)
  local d = s.data
  if d[2] == 0 then
    if band(d[1], 1) ~= 0 then
      d[0] = 0x80
    else
      d[0] = 0
    end
    d[1] = 0
    d[2] = 0
    s._cb = F.RazorLeafParticleStep2
  else
    d[2] = d[2] - 1
    s.x = s.x + d[0]
    s.y = s.y + d[1]
  end
end

-- pokefirered/src/battle_anim_effects_1.c:2606
C.RazorLeafParticle = S.wrap(function(s)
  local A, vm = s._A, s._vm
  s.x = P.coord(vm, P.atk(vm), P.X_2)
  s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
  s.data[0] = A[0]
  s.data[1] = A[1]
  s.data[2] = A[2]
  s._cb = F.RazorLeafParticleStep1
end)

-- pokefirered/src/battle_anim_effects_1.c:2698
function F.TranslateLinearSingleSineWaveStep(s)
  local d = s.data
  local destroy = false
  local a = d[0]
  local b = d[7]
  d[0] = 1
  S.translateHArc(s)
  local r0 = d[7]
  d[0] = a
  s._affParam = s._affParam or 0
  if b > 200 and r0 < 56 and s._affParam == 0 then s._affParam = s._affParam + 1 end
  if s._affParam ~= 0 and d[0] ~= 0 then
    s.visible = not s.visible
    s._affParam = s._affParam + 1
    if s._affParam == 30 then destroy = true end
  end
  local x, y = s.x + s.ox, s.y + s.oy
  if x > P.DISPLAY_WIDTH + 16 or x < -16 or y > P.DISPLAY_HEIGHT or y < -16 then destroy = true end
  if destroy then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:2669
C.TranslateLinearSingleSineWave = S.wrap(function(s)
  local A, vm = s._A, s._vm
  S.initPosToAttacker(s, true)
  if atk_opp(s) then A[2] = -A[2] end
  s.data[0] = A[4]
  if A[6] == 0 then
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + A[2]
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + A[3]
  else
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + A[2]
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + A[3]
  end
  s.data[5] = A[5]
  S.initArc(s)
  if P.isOpponent(P.atk(vm)) == P.isOpponent(P.tgt(vm)) then s.data[0] = 1 else s.data[0] = 0 end
  s._affParam = 0
  s._cb = F.TranslateLinearSingleSineWaveStep
end)

-- pokefirered/src/battle_anim_effects_1.c:2750
function F.MoveTwisterParticleStep(s)
  local d, vm = s.data, s._vm
  if d[1] == 0xFF then
    s.y = s.y - 2
  elseif d[1] > 0 then
    s.y = s.y - 2
    d[1] = d[1] - 2
  end
  d[5] = d[5] + d[2]
  if d[0] < d[4] then d[5] = d[5] + d[2] end
  d[5] = band(d[5], 0xFF)
  s.ox = Cos(d[5], d[3])
  s.oy = Sin(d[5], 5)
  if d[5] < 0x80 then
    s._pri = P.bgPriorityOf(P.tgt(vm)) - 1
  else
    s._pri = P.bgPriorityOf(P.tgt(vm)) + 1
  end
  d[0] = d[0] - 1
  if d[0] == 0 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:2736
C.MoveTwisterParticle = S.wrap(function(s)
  local A, d = s._A, s.data
  s.y = s.y + 32
  d[0] = A[0]
  d[1] = A[1]
  d[2] = A[2]
  d[3] = A[3]
  d[4] = A[4]
  s._cb = F.MoveTwisterParticleStep
end)

-- pokefirered/src/battle_anim_effects_1.c:2806
function F.ConstrictBindingStep2(s)
  local d = s.data
  if d[2] == 0 then d[0] = d[0] + 11 else d[0] = d[0] - 11 end
  d[1] = d[1] + 1
  if d[1] == 6 then
    d[1] = 0
    d[2] = bxor(d[2], 1)
  end
  if s.affineAnimEnded then
    d[7] = d[7] - 1
    if d[7] > 0 then S.startAffineAnim(s, d[6]) else S.destroy(s) end
  end
end

-- pokefirered/src/battle_anim_effects_1.c:2793
function F.ConstrictBindingStep1(s)
  local vm = s._vm
  if vm and vm.args and u16(vm.args[7] or 0) == 0xFFFF then
    s.affineAnimPaused = false
    s.data[0] = 0x100
    s._cb = F.ConstrictBindingStep2
  end
end

-- pokefirered/src/battle_anim_effects_1.c:2783
C.ConstrictBinding = S.wrap(function(s)
  local A = s._A
  S.initPosToTarget(s, false)
  s.affineAnimPaused = true
  S.startAffineAnim(s, A[2])
  s.data[6] = A[2]
  s.data[7] = A[3]
  s._cb = F.ConstrictBindingStep1
end)

-- pokefirered/src/battle_anim_effects_1.c:2894
C.MimicOrb = S.wrap(function(s)
  s._cb = function(sp)
    local vm, d = sp._vm, sp.data
    if d[0] == 0 then
      local A = sp._A
      if not P.isOpponent(P.tgt(vm)) then A[0] = -A[0] end
      sp.x = P.coord(vm, P.tgt(vm), P.X) + A[0]
      sp.y = P.coord(vm, P.tgt(vm), P.Y) + A[1]
      sp.visible = false
      d[0] = d[0] + 1
    elseif d[0] == 1 then
      sp.visible = true
      if sp.affineAnimEnded then
        S.changeAffineAnim(sp, 1)
        d[0] = 25
        d[2] = P.coord(vm, P.atk(vm), P.X_2)
        d[4] = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
        sp._cb = S.initAndRunFastLinear
        S.store(sp, S.destroy)
      end
    end
  end
  s._cb(s)
end)

-- pokefirered/src/battle_anim_effects_1.c:2976
function F.RootFlickerOut(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] > d[2] - 10 then s.visible = (d[0] % 2) == 0 end
  if d[0] > d[2] then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:2928
C.IngrainRoot = S.wrap(function(s)
  local A, vm, d = s._A, s._vm, s.data
  if d[0] == 0 then
    s.x = P.coord(vm, P.atk(vm), P.X_2)
    s.y = P.coord(vm, P.atk(vm), P.Y)
    s.ox = A[0]
    s.oy = A[1]
    s.subpriority = A[2] + 30
    S.startAnim(s, A[3])
    d[2] = A[4]
    d[0] = d[0] + 1
    if s.y + s.oy > 120 then s.y = s.y + s.oy + s.y - 120 end
  end
  s._cb = F.RootFlickerOut
end)

-- pokefirered/src/battle_anim_effects_1.c:2953
C.FrenzyPlantRoot = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local ax = P.coord(vm, P.atk(vm), P.X_2)
  local ay = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
  local tx = P.coord(vm, P.tgt(vm), P.X_2) - ax
  local ty = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) - ay
  s.x = ax + P.cdiv(tx * A[0], 100)
  s.y = ay + P.cdiv(ty * A[0], 100)
  s.ox = A[1]
  s.oy = A[2]
  s.subpriority = A[3] + 30
  S.startAnim(s, A[4])
  s.data[2] = A[5]
  s._cb = F.RootFlickerOut
end)

-- pokefirered/src/battle_anim_effects_1.c:2991
C.IngrainOrb = S.wrap(function(s)
  s._cb = function(sp)
    local A, vm, d = sp._A, sp._vm, sp.data
    if d[0] == 0 then
      sp.x = P.coord(vm, P.atk(vm), P.X_2) + A[0]
      sp.y = P.coord(vm, P.atk(vm), P.Y) + A[1]
      d[1] = A[2]
      d[2] = A[3]
      d[3] = A[4]
    end
    d[0] = d[0] + 1
    sp.ox = d[1] * d[0]
    sp.oy = Sin(band(d[0] * 20, 0xFF), d[2])
    if d[0] > d[3] then S.destroy(sp) end
  end
  s._cb(s)
end)

C._F = F
local B = require("src.core.game3.battle.anim_port.g1_callbacks_b")
B(C, F)
return C
