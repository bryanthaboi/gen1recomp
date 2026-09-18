local P = require("src.core.game3.battle.anim_port.g2_pret")

local CB = {}
local TASKS = {}

local band, bor, bxor = bit.band, bit.bor, bit.bxor

local function withdraw_step(t)
  local m = t.g2.mon
  local d = t.data
  local rotation
  if P.atk() == "player" then rotation = -d[0] else rotation = d[0] end
  P.setSpriteRotScale(m, 0x100, 0x100, rotation)
  if d[1] == 0 then
    d[0] = P.s16(d[0] + 0xB0)
    m.y2 = m.y2 + 1
  elseif d[1] == 1 then
    d[3] = d[3] + 1
    if d[3] == 30 then d[1] = 2 end
    return
  else
    d[0] = P.s16(d[0] - 0xB0)
    m.y2 = m.y2 - 1
  end
  P.setYOffsetFromRotation(m)
  if d[0] == 0xF20 or d[0] == 0 then
    if d[1] == 2 then
      P.resetSpriteRotScale(m)
      P.destroyTask(t)
    else
      d[1] = d[1] + 1
    end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:1377
TASKS.Withdraw = P.task(function(t)
  local m = P.mon(P.atk())
  if not m then return P.destroyTask(t) end
  t.g2.mon = m
  t.func = withdraw_step
end)

-- pokefirered/src/battle_anim_effects_2.c:1433
function CB.KinesisZapEnergy(s)
  P.SetSpriteCoordsToAnimAttackerCoords(s)
  if P.atk() ~= "player" then
    s.x = s.x - P.arg(0)
  else
    s.x = s.x + P.arg(0)
  end
  s.y = s.y + P.arg(1)
  if P.atk() ~= "player" then
    s.pHFlip = true
    if P.arg(2) ~= 0 then s.pVFlip = true end
  else
    if P.arg(2) ~= 0 then s.pVFlip = true end
  end
  s.pcb = P.RunStoredCallbackWhenAnimEnds
  P.storeCallback(s, P.DestroyAnimSprite)
end

local function swords_dance_step(s)
  s.data[0] = 6
  s.data[2] = s.x
  s.data[4] = s.y - 32
  s.pcb = P.StartAnimLinearTranslation
  P.storeCallback(s, P.DestroyAnimSprite)
end

-- pokefirered/src/battle_anim_effects_2.c:1461
function CB.SwordsDanceBlade(s)
  P.InitSpritePosToAnimAttacker(s, false)
  s.pcb = P.RunStoredCallbackWhenAffineAnimEnds
  P.storeCallback(s, swords_dance_step)
end

-- pokefirered/src/battle_anim_effects_2.c:1484
function CB.SonicBoomProjectile(s)
  if P.atk() ~= "player" then
    P.setArg(2, -P.arg(2))
    P.setArg(1, -P.arg(1))
    P.setArg(3, -P.arg(3))
  end
  P.InitSpritePosToAnimAttacker(s, true)
  local tx = P.s16(P.coord(P.tgt(), 2) + P.arg(2))
  local ty = P.s16(P.coord(P.tgt(), 3) + P.arg(3))
  local rotation = P.ArcTan2Neg(tx - s.x, ty - s.y)
  rotation = P.u16(rotation + 0xF000)
  P.trySetRotScale(s, false, 0x100, 0x100, rotation)
  s.data[0] = P.arg(4)
  s.data[2] = tx
  s.data[4] = ty
  s.pcb = P.StartAnimLinearTranslation
  P.storeCallback(s, P.DestroyAnimSprite)
end

local function air_wave_pos(s, task)
  if band(task.data[7], 1) ~= 0 then
    s.x2 = -math.floor(P.u16(s.data[1]) / 256)
  else
    s.x2 = math.floor(P.u16(s.data[1]) / 256)
  end
  if band(task.data[8], 1) ~= 0 then
    s.y2 = -math.floor(P.u16(s.data[2]) / 256)
  else
    s.y2 = math.floor(P.u16(s.data[2]) / 256)
  end
end

local function air_wave_step2(s)
  local v = s.data[0]
  s.data[0] = v - 1
  if v <= 0 then
    local task = s.g2.task
    if task and task.data then task.data[1] = task.data[1] - 1 end
    P.destroy(s)
  end
end

local function air_wave_step1(s)
  local task = s.g2.task
  local d = s.data
  if d[0] > task.data[5] then
    d[5] = P.s16(d[5] + d[3])
    d[6] = P.s16(d[6] + d[4])
  else
    d[5] = P.s16(d[5] - d[3])
    d[6] = P.s16(d[6] - d[4])
  end
  d[1] = P.s16(d[1] + d[5])
  d[2] = P.s16(d[2] + d[6])
  air_wave_pos(s, task)
  local v = d[0]
  d[0] = v - 1
  if v <= 0 then
    d[0] = 30
    s.pcb = air_wave_step2
  end
end

-- pokefirered/src/battle_anim_effects_2.c:1560
function CB.AirWaveProjectile(s)
  local task = s.g2.task
  local d = s.data
  d[1] = P.s16(d[1] + band(-2, task.data[7]))
  d[2] = P.s16(d[2] + band(-2, task.data[8]))
  air_wave_pos(s, task)
  local v = d[0]
  d[0] = v - 1
  if v <= 0 then
    d[0] = 8
    task.data[5] = 4
    local a = P.Q88inv(0x1000)
    s.x = s.x + s.x2
    s.y = s.y + s.y2
    s.y2 = 0
    s.x2 = 0
    local b, c
    if task.data[11] >= s.x then b = P.s16((task.data[11] - s.x) * 256) else b = P.s16((s.x - task.data[11]) * 256) end
    if task.data[12] >= s.y then c = P.s16((task.data[12] - s.y) * 256) else c = P.s16((s.y - task.data[12]) * 256) end
    d[2] = 0
    d[1] = 0
    d[6] = 0
    d[5] = 0
    d[3] = P.Q88mul(P.Q88mul(b, a), P.Q88inv(0x1C0))
    d[4] = P.Q88mul(P.Q88mul(c, a), P.Q88inv(0x1C0))
    s.pcb = air_wave_step1
  end
end

local function air_cutter_step2(t)
  if t.data[1] == 0 then P.destroyTask(t) end
end

local function air_cutter_step1(t)
  local d = t.data
  local v = d[0]
  d[0] = v - 1
  if v <= 0 then
    local s = P.createSprite("gAirWaveProjectileSpriteTemplate", d[9], d[10], d[2] - d[1], false, false, false)
    if s then
      if d[4] == 1 then
        s.pHFlip = true
        s.pVFlip = true
      elseif d[4] == 2 then
        s.pHFlip = true
        s.pVFlip = false
      end
      s.data[0] = d[5] - d[6]
      s.g2.task = t
      s.pcb = CB.AirWaveProjectile
    end
    d[0] = d[3]
    d[1] = d[1] + 1
    local vm = P.vm
    local pan = vm and vm.adjustPanning and vm:adjustPanning(-63) or -63
    P.playSE("SE_M_BLIZZARD2", pan)
    if d[1] > 2 then t.func = air_cutter_step2 end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:1644
TASKS.AirCutterProjectile = P.task(function(t)
  local d = t.data
  if P.tgt() == "player" then
    d[4] = 1
    P.setArg(0, -P.arg(0))
    P.setArg(1, -P.arg(1))
    if band(P.arg(2), 1) ~= 0 then
      P.setArg(2, band(P.arg(2), bit.bnot(1)))
    else
      P.setArg(2, bor(P.arg(2), 1))
    end
  end
  local ax = P.coord(P.atk(), 0)
  local ay = P.coord(P.atk(), 1)
  d[9] = ax
  d[10] = ay
  local tx = P.coord(P.tgt(), 0)
  local ty = P.coord(P.tgt(), 1)
  tx = P.s16(tx + P.arg(0))
  ty = P.s16(ty + P.arg(1))
  d[11] = tx
  d[12] = ty
  local xDiff
  if tx >= ax then xDiff = tx - ax else xDiff = ax - tx end
  d[5] = P.Q88mul(xDiff, P.Q88inv(band(P.arg(2), bit.bnot(1))))
  d[6] = P.Q88mul(d[5], 0x80)
  d[7] = P.arg(2)
  if ty >= ay then
    local yDiff = ty - ay
    d[8] = band(P.Q88mul(yDiff, P.Q88inv(d[5])), bit.bnot(1))
  else
    local yDiff = ay - ty
    d[8] = bor(P.Q88mul(yDiff, P.Q88inv(d[5])), 1)
  end
  d[3] = P.arg(3)
  local a4 = P.arg(4)
  if band(a4, 0x80) ~= 0 then
    a4 = bxor(a4, 0x80)
    P.setArg(4, a4)
  end
  if a4 >= 64 then
    d[2] = P.u16(P.subpriorityOf(P.tgt()) + (a4 - 64))
  else
    d[2] = P.u16(P.subpriorityOf(P.tgt()) - a4)
  end
  if d[2] < 3 then d[2] = 3 end
  t.func = air_cutter_step1
end)

-- pokefirered/src/battle_anim_effects_2.c:1771
function CB.CoinThrow(s)
  P.InitSpritePosToAnimAttacker(s, true)
  local r6 = P.coord(P.tgt(), 2)
  local r7 = P.s16(P.coord(P.tgt(), 3) + P.arg(3))
  if P.atk() ~= "player" then P.setArg(2, -P.arg(2)) end
  r6 = P.s16(r6 + P.arg(2))
  local var = P.ArcTan2Neg(r6 - s.x, r7 - s.y)
  var = P.u16(var + 0xC000)
  P.trySetRotScale(s, false, 0x100, 0x100, var)
  s.data[0] = P.arg(4)
  s.data[2] = r6
  s.data[4] = r7
  s.pcb = P.InitAnimLinearTranslationWithSpeedAndPos
  P.storeCallback(s, P.DestroyAnimSprite)
end

local function falling_coin_step(s)
  s.data[0] = P.s16(s.data[0] + 0x80)
  s.x2 = P.asr(s.data[0], 8)
  if P.atk() == "player" then s.x2 = -s.x2 end
  s.y2 = P.Sin(s.data[1], s.data[2])
  s.data[1] = s.data[1] + 5
  if s.data[1] > 126 then
    s.data[1] = 0
    s.data[2] = P.div(s.data[2], 2)
    s.data[3] = s.data[3] + 1
    if s.data[3] == 2 then P.destroy(s) end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:1794
function CB.FallingCoin(s)
  s.data[2] = -16
  s.y = s.y + 8
  s.pcb = falling_coin_step
end

local function bullet_seed_step2(s)
  s.data[0] = P.s16(s.data[0] + s.data[7])
  s.x2 = P.asr(s.data[0], 8)
  if band(s.data[7], 1) ~= 0 then s.x2 = -s.x2 end
  s.y2 = P.Sin(s.data[1], s.data[6])
  s.data[1] = s.data[1] + 8
  if s.data[1] > 126 then
    s.data[1] = 0
    s.data[2] = P.div(s.data[2], 2)
    s.data[3] = s.data[3] + 1
    if s.data[3] == 1 then P.destroy(s) end
  end
end

local function bullet_seed_step1(s)
  local vm = P.vm
  local pan = vm and vm.adjustPanning and vm:adjustPanning(63) or 63
  P.playSE("SE_M_HORN_ATTACK", pan)
  s.x = s.x + s.x2
  s.y = s.y + s.y2
  s.y2 = 0
  s.x2 = 0
  for i = 0, 7 do s.data[i] = 0 end
  local rand = P.Random()
  s.data[6] = P.s16(0xFFF4 - band(rand, 7))
  rand = P.Random()
  s.data[7] = (rand % 0xA0) + 0xA0
  s.pcb = bullet_seed_step2
  s.affineAnimPaused = false
end

-- pokefirered/src/battle_anim_effects_2.c:1819
function CB.BulletSeed(s)
  P.InitSpritePosToAnimAttacker(s, true)
  s.data[0] = 20
  s.data[2] = P.coord(P.tgt(), 2)
  s.data[4] = P.coord(P.tgt(), 3)
  s.pcb = P.StartAnimLinearTranslation
  s.affineAnimPaused = true
  P.storeCallback(s, bullet_seed_step1)
end

-- pokefirered/src/battle_anim_effects_2.c:1879
function CB.RazorWindTornado(s)
  P.InitSpritePosToAnimAttacker(s, false)
  if P.atk() == "player" then s.y = s.y + 16 end
  s.data[0] = P.arg(4)
  s.data[1] = P.arg(2)
  s.data[2] = P.arg(5)
  s.data[3] = P.arg(6)
  s.data[4] = P.arg(3)
  s.pcb = P.TranslateSpriteInCircle
  P.storeCallback(s, P.DestroyAnimSprite)
  s.pcb(s)
end

local function vice_grip_step(s)
  if s.animEnded then P.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_2.c:1897
function CB.ViceGripPincer(s)
  local sx, sy, ex, ey = 32, -32, 16, -16
  if P.arg(0) ~= 0 then
    sx, sy, ex, ey = -32, 32, -16, 16
    P.startAnim(s, 1)
  end
  s.x = s.x + sx
  s.y = s.y + sy
  s.data[0] = 6
  s.data[2] = P.coord(P.tgt(), 2) + ex
  s.data[4] = P.coord(P.tgt(), 3) + ey
  s.pcb = P.StartAnimLinearTranslation
  P.storeCallback(s, vice_grip_step)
end

local function guillotine_step3(s)
  if P.AnimTranslateLinear(s) then P.destroy(s) end
end

local function guillotine_step2(s)
  if s.data[3] ~= 0 then
    s.x2 = -s.x2
    s.y2 = -s.y2
  end
  s.data[3] = bxor(s.data[3], 1)
  s.data[4] = s.data[4] + 1
  if s.data[4] == 51 then
    s.y2 = 0
    s.x2 = 0
    s.data[4] = 0
    s.data[3] = 0
    s.animPaused = false
    P.startAnim(s, bxor(s.data[5], 1))
    s.pcb = guillotine_step3
  end
end

local function guillotine_step1(s)
  if P.AnimTranslateLinear(s) and s.animEnded then
    P.seekAnim(s, 0)
    s.animPaused = true
    s.x = s.x + s.x2
    s.y = s.y + s.y2
    s.x2 = 2
    s.y2 = -2
    s.data[0] = s.data[6]
    s.data[1] = bxor(s.data[1], 1)
    s.data[2] = bxor(s.data[2], 1)
    s.data[4] = 0
    s.data[3] = 0
    s.pcb = guillotine_step2
  end
end

-- pokefirered/src/battle_anim_effects_2.c:1930
function CB.GuillotinePincer(s)
  local sx, sy, ex, ey = 32, -32, 16, -16
  if P.arg(0) ~= 0 then
    sx, sy, ex, ey = -32, 32, -16, 16
    P.startAnim(s, P.arg(0))
  end
  s.x = s.x + sx
  s.y = s.y + sy
  s.data[0] = 6
  s.data[1] = s.x
  s.data[2] = P.coord(P.tgt(), 2) + ex
  s.data[3] = s.y
  s.data[4] = P.coord(P.tgt(), 3) + ey
  P.InitAnimLinearTranslation(s)
  s.data[5] = P.arg(0)
  s.data[6] = s.data[0]
  s.pcb = guillotine_step1
end

local function grow_gray_step(t)
  t.data[0] = t.data[0] - 1
  if t.data[0] == -1 then
    local c = t.g2.clone
    if c and P.alive(c) then P.destroy(c) end
    P.destroyTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2008
TASKS.GrowAndGrayscale = P.task(function(t)
  local c = P.cloneMon(P.ANIM_TARGET, P.subpriorityOf(P.tgt()))
  if c then
    c.affineMode = 3
    c.affineAnimPaused = true
    c.gray = true
    c.objBlend = true
    P.trySetRotScale(c, false, 0xD0, 0xD0, 0)
    t.g2.clone = c
  end
  t.data[0] = 80
  t.func = grow_gray_step
end)

local function clone_minimize_step(s)
  s.data[0] = s.data[0] - 1
  if s.data[0] == 0 then
    local t = s.g2.task
    if t and t.data then t.data[s.data[2]] = t.data[s.data[2]] - 1 end
    P.destroy(s)
  end
end

local function create_minimize_sprite(t)
  local c = P.cloneMon(P.ANIM_ATTACKER, t.data[7] - t.data[3])
  if c then
    c.objBlend = true
    c.affineMode = 1
    c.affineAnimPaused = true
    t.data[3] = t.data[3] + 1
    t.data[6] = t.data[6] + 1
    c.data[0] = 16
    c.g2.task = t
    c.data[2] = 6
    P.trySetRotScale(c, false, t.data[4], t.data[4], 0)
    c.pcb = clone_minimize_step
  end
end

local function minimize_step(t)
  local d = t.data
  local m = t.g2.mon
  if d[1] == 0 then
    if d[2] == 0 or d[2] == 3 or d[2] == 6 then create_minimize_sprite(t) end
    d[2] = d[2] + 1
    d[4] = d[4] + 0x28
    P.setSpriteRotScale(m, d[4], d[4], 0)
    P.setYOffsetFromYScale(m)
    if d[2] == 32 then
      d[5] = d[5] + 1
      d[1] = d[1] + 1
    end
  elseif d[1] == 1 then
    if d[6] == 0 then
      if d[5] == 3 then
        d[2] = 0
        d[1] = 3
      else
        d[2] = 0
        d[3] = 0
        d[4] = 0x100
        P.setSpriteRotScale(m, d[4], d[4], 0)
        P.setYOffsetFromYScale(m)
        d[1] = 2
      end
    end
  elseif d[1] == 2 then
    d[1] = 0
  elseif d[1] == 3 then
    d[2] = d[2] + 1
    if d[2] > 32 then
      d[2] = 0
      d[1] = d[1] + 1
    end
  elseif d[1] == 4 then
    d[2] = d[2] + 2
    d[4] = d[4] - 0x50
    P.setSpriteRotScale(m, d[4], d[4], 0)
    P.setYOffsetFromYScale(m)
    if d[2] == 32 then
      d[2] = 0
      d[1] = d[1] + 1
    end
  elseif d[1] == 5 then
    P.resetSpriteRotScale(m)
    m.y2 = 0
    P.destroyTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2033
TASKS.Minimize = P.task(function(t)
  local m = P.mon(P.atk())
  if not m then return P.destroyTask(t) end
  t.g2.mon = m
  t.data[1] = 0
  t.data[2] = 0
  t.data[3] = 0
  t.data[4] = 0x100
  t.data[5] = 0
  t.data[6] = 0
  t.data[7] = P.subpriorityOf(P.atk())
  t.func = minimize_step
end)

local function splash_step(t)
  local d = t.data
  local m = t.g2.affMon
  if d[1] == 0 then
    P.RunAffineAnimFromTaskData(t)
    d[4] = d[4] + 3
    m.y2 = m.y2 + d[4]
    d[3] = d[3] + 1
    if d[3] > 7 then
      d[3] = 0
      d[1] = d[1] + 1
    end
  elseif d[1] == 1 then
    P.RunAffineAnimFromTaskData(t)
    m.y2 = m.y2 + d[4]
    d[3] = d[3] + 1
    if d[3] > 7 then
      d[3] = 0
      d[1] = d[1] + 1
    end
  elseif d[1] == 2 then
    if d[4] ~= 0 then
      m.y2 = m.y2 - 2
      d[4] = d[4] - 2
    else
      d[1] = d[1] + 1
    end
  elseif d[1] == 3 then
    if not P.RunAffineAnimFromTaskData(t) then
      d[2] = d[2] - 1
      if d[2] == 0 then
        m.y2 = 0
        P.destroyTask(t)
      else
        P.PrepareAffineAnimInTaskData(t, m, P.affineCmds("sSplashEffectAffineAnimCmds"))
        d[1] = 0
      end
    end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2161
TASKS.Splash = P.task(function(t)
  if P.arg(1) == 0 then return P.destroyTask(t) end
  local m = P.monById(P.arg(0))
  if not m then return P.destroyTask(t) end
  t.data[1] = 0
  t.data[2] = P.arg(1)
  t.data[3] = 0
  t.data[4] = 0
  P.PrepareAffineAnimInTaskData(t, m, P.affineCmds("sSplashEffectAffineAnimCmds"))
  t.func = splash_step
end)

local function affine_until_done(t)
  if not P.RunAffineAnimFromTaskData(t) then P.destroyTask(t) end
end

-- pokefirered/src/battle_anim_effects_2.c:2237
TASKS.GrowAndShrink = P.task(function(t)
  local m = P.mon(P.atk())
  if not m then return P.destroyTask(t) end
  P.PrepareAffineAnimInTaskData(t, m, P.affineCmds("sGrowAndShrinkAffineAnimCmds"))
  t.func = affine_until_done
end)

-- pokefirered/src/battle_anim_effects_2.c:2257
function CB.BreathPuff(s)
  local atk = P.atk()
  if atk == "player" then
    P.startAnim(s, 0)
    s.x = P.coord(atk, 2) + 32
    s.data[1] = 64
  else
    P.startAnim(s, 1)
    s.x = P.coord(atk, 2) - 32
    s.data[1] = -64
  end
  s.y = P.coord(atk, 3)
  s.data[0] = 52
  s.data[2] = 0
  s.data[3] = 0
  s.data[4] = 0
  P.storeCallback(s, P.DestroyAnimSprite)
  s.pcb = P.TranslateSpriteLinearFixedPoint
end

-- pokefirered/src/battle_anim_effects_2.c:2285
function CB.AngerMark(s)
  local b = (P.arg(0) == 0) and P.atk() or P.tgt()
  if b ~= "player" then P.setArg(1, -P.arg(1)) end
  s.x = P.coord(b, 2) + P.arg(1)
  s.y = P.coord(b, 3) + P.arg(2)
  if s.y < 8 then s.y = 8 end
  P.storeCallback(s, P.DestroySpriteAndMatrix)
  s.pcb = P.RunStoredCallbackWhenAffineAnimEnds
end

-- pokefirered/src/battle_anim_effects_2.c:2307
TASKS.ThrashMoveMonHorizontal = P.task(function(t)
  local m = P.mon(P.atk())
  if not m then return P.destroyTask(t) end
  t.data[1] = 0
  P.PrepareAffineAnimInTaskData(t, m, P.affineCmds("sThrashMoveMonAffineAnimCmds"))
  t.func = affine_until_done
end)

local function thrash_vertical_step(t)
  local d = t.data
  local m = t.g2.mon
  d[7] = d[7] + 1
  if d[7] > 2 then
    d[7] = 0
    d[8] = d[8] + 1
    if band(d[8], 1) ~= 0 then m.y = m.y + d[9] else m.y = m.y - d[9] end
  end
  if d[1] == 0 then
    m.x = m.x + d[2]
    d[3] = d[3] - 1
    if d[3] == 0 then
      d[3] = 14
      d[1] = 1
    end
  elseif d[1] == 1 then
    m.x = m.x - d[2]
    d[3] = d[3] - 1
    if d[3] == 0 then
      d[3] = 7
      d[1] = 2
    end
  elseif d[1] == 2 then
    m.x = m.x + d[2]
    d[3] = d[3] - 1
    if d[3] == 0 then
      d[4] = d[4] - 1
      if d[4] ~= 0 then
        d[3] = 7
        d[1] = 0
      else
        if band(d[8], 1) ~= 0 then m.y = m.y - d[9] end
        P.destroyTask(t)
      end
    end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:2327
TASKS.ThrashMoveMonVertical = P.task(function(t)
  local m = P.mon(P.atk())
  if not m then return P.destroyTask(t) end
  t.g2.mon = m
  local d = t.data
  d[1] = 0
  d[2] = 4
  d[3] = 7
  d[4] = 3
  d[5] = m.x
  d[6] = m.y
  d[7] = 0
  d[8] = 0
  d[9] = 2
  if P.atk() ~= "player" then d[2] = -d[2] end
  t.func = thrash_vertical_step
end)

return { cb = CB, tasks = TASKS }
