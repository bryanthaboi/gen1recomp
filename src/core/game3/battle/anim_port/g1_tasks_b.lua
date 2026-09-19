local bit = require("bit")
local P = require("src.core.game3.battle.anim_port.g1_pret")
local S = require("src.core.game3.battle.anim_port.g1_sprite")
local K = require("src.core.game3.battle.anim_port.g1_task_base")

local band, bxor, arshift, lshift, rshift = bit.band, bit.bxor, bit.arshift, bit.lshift, bit.rshift
local s16, u16, u8 = P.s16, P.u16, P.u8
local Sin, Cos = P.Sin, P.Cos
local cdiv = P.cdiv

return function(T, F)

local function mon_or_destroy(t, vm, animBattler)
  local side = K.battlerSide(vm, animBattler)
  local p = side and P.present(side)
  if not p then
    K.destroy(t)
    return nil
  end
  t._side = side
  t._p = p
  return p, side
end

-- pokefirered/src/battle_anim_mon_movement.c:115
local function shake_mon_step(t)
  local d, p = t.data, t._p
  if d[3] == 0 then
    if (p.ox or 0) == 0 then p.ox = d[4] else p.ox = 0 end
    if (p.oy or 0) == 0 then p.oy = d[5] else p.oy = 0 end
    d[3] = d[2]
    d[1] = d[1] - 1
    if d[1] <= 0 then
      p.ox = 0
      p.oy = 0
      K.destroy(t)
    end
  else
    d[3] = d[3] - 1
  end
end

-- pokefirered/src/battle_anim_mon_movement.c:94
T.ShakeMon = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, A[0])
  if not p then return end
  p.ox = A[1]
  p.oy = A[2]
  d[1] = A[3]
  d[2] = A[4]
  d[3] = A[4]
  d[4] = A[1]
  d[5] = A[2]
  t._fn = shake_mon_step
  t._fn(t)
end)

-- pokefirered/src/battle_anim_mon_movement.c:200
local function shake_mon2_step(t)
  local d, p = t.data, t._p
  if d[3] == 0 then
    if (p.ox or 0) == d[4] then p.ox = -d[4] else p.ox = d[4] end
    if (p.oy or 0) == d[5] then p.oy = -d[5] else p.oy = d[5] end
    d[3] = d[2]
    d[1] = d[1] - 1
    if d[1] <= 0 then
      p.ox = 0
      p.oy = 0
      K.destroy(t)
    end
  else
    d[3] = d[3] - 1
  end
end

-- pokefirered/src/battle_anim_mon_movement.c:146
T.ShakeMon2 = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local side
  if A[0] < 4 then
    side = K.battlerSide(vm, A[0])
  elseif A[0] ~= 8 then
    if A[0] == 4 then side = 0 elseif A[0] == 5 then side = 2 elseif A[0] == 6 then side = 1 else side = 3 end
    if side >= 2 and not P.spriteVisible(side) then side = nil end
  else
    side = P.atk(vm)
  end
  local p = side and P.present(side)
  if not p then return K.destroy(t) end
  t._p = p
  p.ox = A[1]
  p.oy = A[2]
  d[1] = A[3]
  d[2] = A[4]
  d[3] = A[4]
  d[4] = A[1]
  d[5] = A[2]
  t._fn = shake_mon2_step
  t._fn(t)
end)

-- pokefirered/src/battle_anim_mon_movement.c:254
local function shake_in_place_step(t)
  local d, p = t.data, t._p
  if d[3] == 0 then
    if band(d[1], 1) ~= 0 then
      p.ox = (p.ox or 0) + d[5]
      p.oy = (p.oy or 0) + d[6]
    else
      p.ox = (p.ox or 0) - d[5]
      p.oy = (p.oy or 0) - d[6]
    end
    d[3] = d[4]
    d[1] = d[1] + 1
    if d[1] >= d[2] then
      if band(d[1], 1) ~= 0 then
        p.ox = p.ox + cdiv(d[5], 2)
        p.oy = p.oy + cdiv(d[6], 2)
      else
        p.ox = p.ox - cdiv(d[5], 2)
        p.oy = p.oy - cdiv(d[6], 2)
      end
      K.destroy(t)
    end
  else
    d[3] = d[3] - 1
  end
end

-- pokefirered/src/battle_anim_mon_movement.c:232
T.ShakeMonInPlace = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, A[0])
  if not p then return end
  p.ox = (p.ox or 0) + A[1]
  p.oy = (p.oy or 0) + A[2]
  d[1] = 0
  d[2] = A[3]
  d[3] = 0
  d[4] = A[4]
  d[5] = A[1] * 2
  d[6] = A[2] * 2
  t._fn = shake_in_place_step
  t._fn(t)
end)

-- pokefirered/src/battle_anim_mon_movement.c:308
local function shake_and_sink_step(t)
  local d, p = t.data, t._p
  local x = d[1]
  local old = d[8]
  d[8] = d[8] + 1
  if d[2] == old then
    d[8] = 0
    if (p.ox or 0) == x then x = -x end
    p.ox = (p.ox or 0) + x
  end
  d[1] = x
  d[9] = s16(d[9] + d[3])
  p.oy = arshift(d[9], 8)
  d[4] = d[4] - 1
  if d[4] == 0 then K.destroy(t) end
end

-- pokefirered/src/battle_anim_mon_movement.c:294
T.ShakeAndSinkMon = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, A[0])
  if not p then return end
  p.ox = A[1]
  d[1] = A[1]
  d[2] = A[2]
  d[3] = A[3]
  d[4] = A[4]
  t._fn = shake_and_sink_step
  t._fn(t)
end)

-- pokefirered/src/battle_anim_mon_movement.c:351
local function elliptical_step(t)
  local d, p = t.data, t._p
  p.ox = Sin(d[5], d[1])
  p.oy = -Cos(d[5], d[2]) + d[2]
  d[5] = band(d[5] + d[4], 0xFF)
  if d[5] == 0 then d[3] = d[3] - 1 end
  if d[3] == 0 then
    p.ox = 0
    p.oy = 0
    K.destroy(t)
  end
end

local function elliptical_init(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, A[0])
  if not p then return end
  if A[4] > 5 then A[4] = 5 end
  local wave = 1
  for _ = 1, A[4] do wave = wave * 2 end
  d[1] = A[1]
  d[2] = A[2]
  d[3] = A[3]
  d[4] = wave
  t._fn = elliptical_step
  t._fn(t)
end

-- pokefirered/src/battle_anim_mon_movement.c:333
T.TranslateMonElliptical = K.wrap(elliptical_init)

-- pokefirered/src/battle_anim_mon_movement.c:377
T.TranslateMonEllipticalRespectSide = K.wrap(function(t, vm)
  if P.isOpponent(P.atk(vm)) then t._A[1] = -t._A[1] end
  elliptical_init(t, vm)
end)

-- pokefirered/src/battle_anim_mon_movement.c:609
local function wind_up_step2(t)
  local d, p = t.data, t._p
  if d[4] > 0 then
    d[4] = d[4] - 1
  else
    d[12] = s16(d[12] + d[5])
    p.ox = arshift(d[12], 8) + arshift(d[11], 8)
    d[6] = d[6] - 1
    if d[6] == 0 then K.destroy(t) end
  end
end

-- pokefirered/src/battle_anim_mon_movement.c:598
local function wind_up_step1(t)
  local d, p = t.data, t._p
  d[11] = s16(d[11] + d[1])
  p.ox = arshift(d[11], 8)
  p.oy = Sin(u8(arshift(d[10], 8)), d[2])
  d[10] = s16(d[10] + d[7])
  d[3] = d[3] - 1
  if d[3] == 0 then t._fn = wind_up_step2 end
end

-- pokefirered/src/battle_anim_mon_movement.c:579
T.WindUpLunge = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local wave = u16(cdiv(0x8000, A[3]))
  if P.isOpponent(P.atk(vm)) then
    A[1] = -A[1]
    A[5] = -A[5]
  end
  local p = mon_or_destroy(t, vm, A[0])
  if not p then return end
  d[1] = s16(cdiv(A[1] * 256, A[3]))
  d[2] = A[2]
  d[3] = A[3]
  d[4] = A[4]
  d[5] = s16(cdiv(A[5] * 256, A[6]))
  d[6] = A[6]
  d[7] = s16(wave)
  t._fn = wind_up_step1
end)

-- pokefirered/src/battle_anim_mon_movement.c:664
local function slide_off_step(t, vm)
  local d, p = t.data, t._p
  p.ox = (p.ox or 0) + d[1]
  local x = P.coord(vm, t._side, P.X_2)
  if p.ox + x < -32 or p.ox + x > P.DISPLAY_WIDTH + 32 then K.destroy(t) end
end

-- pokefirered/src/battle_anim_mon_movement.c:626
T.SlideOffScreen = K.wrap(function(t, vm)
  local A = t._A
  if A[0] ~= 0 and A[0] ~= 1 then return K.destroy(t) end
  local p = mon_or_destroy(t, vm, A[0])
  if not p then return end
  if P.isOpponent(P.tgt(vm)) then t.data[1] = A[1] else t.data[1] = -A[1] end
  t._fn = slide_off_step
end)

-- pokefirered/src/battle_anim_mon_movement.c:699
local function sway_step(t)
  local d, p = t.data, t._p
  local sineIndex = u16(d[10] + d[2])
  d[10] = s16(sineIndex)
  local waveIndex = rshift(sineIndex, 8)
  local sine = Sin(waveIndex, d[1])
  if d[0] == 0 then
    p.ox = sine
  elseif not P.isOpponent(t._side) then
    p.oy = math.abs(sine)
  else
    p.oy = -math.abs(sine)
  end
  if (waveIndex > 0x7F and d[11] == 0 and d[12] == 1) or (waveIndex < 0x7F and d[11] == 1 and d[12] == 0) then
    d[11] = bxor(d[11], 1)
    d[12] = bxor(d[12], 1)
    d[3] = d[3] - 1
    if d[3] == 0 then
      p.ox = 0
      p.oy = 0
      K.destroy(t)
    end
  end
end

-- pokefirered/src/battle_anim_mon_movement.c:680
T.SwayMon = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  if P.isOpponent(P.atk(vm)) then A[1] = -A[1] end
  local p = mon_or_destroy(t, vm, A[4])
  if not p then return end
  d[0] = A[0]
  d[1] = A[1]
  d[2] = A[2]
  d[3] = A[3]
  d[12] = 1
  t._fn = sway_step
end)

-- pokefirered/src/battle_anim_mon_movement.c:754
local function scale_restore_step(t)
  local d = t.data
  d[10] = s16(d[10] + d[0])
  d[11] = s16(d[11] + d[1])
  S.setMonRotScale(t._side, d[10], d[11], 0)
  d[2] = d[2] - 1
  if d[2] == 0 then
    if d[3] > 0 then
      d[0] = -d[0]
      d[1] = -d[1]
      d[2] = d[3]
      d[3] = 0
    else
      S.resetMonRotScale(t._side)
      K.destroy(t)
    end
  end
end

-- pokefirered/src/battle_anim_mon_movement.c:740
T.ScaleMonAndRestore = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, A[3])
  if not p then return end
  d[0] = A[0]
  d[1] = A[1]
  d[2] = A[2]
  d[3] = A[2]
  d[10] = 0x100
  d[11] = 0x100
  t._fn = scale_restore_step
end)

-- pokefirered/src/battle_anim_mon_movement.c:846
local function rotate_side_step(t)
  local d = t.data
  d[3] = s16(d[3] + d[4])
  S.setMonRotScale(t._side, 0x100, 0x100, d[3])
  if d[7] ~= 0 then S.monYOffsetFromRotation(t._side) end
  d[1] = d[1] + 1
  if d[1] >= d[2] then
    if d[6] == 1 then
      S.resetMonRotScale(t._side)
      local p = t._p
      if p and d[7] ~= 0 then p.oy = 0 end
      K.destroy(t)
    elseif d[6] == 2 then
      d[1] = 0
      d[4] = -d[4]
      d[6] = 1
    else
      K.destroy(t)
    end
  end
end

-- pokefirered/src/battle_anim_mon_movement.c:778
T.RotateMonSpriteToSide = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, A[2])
  if not p then return end
  d[1] = 0
  d[2] = A[0]
  if A[3] ~= 1 then d[3] = 0 else d[3] = s16(A[0] * A[1]) end
  d[4] = A[1]
  d[6] = A[3]
  if A[2] == 0 then
    d[7] = P.isOpponent(P.atk(vm)) and 0 or 1
  else
    d[7] = P.isOpponent(P.tgt(vm)) and 0 or 1
  end
  if d[7] ~= 0 then
    d[3] = -d[3]
    d[4] = -d[4]
  end
  t._fn = rotate_side_step
end)

-- pokefirered/src/battle_anim_mon_movement.c:812
T.RotateMonToSideAndRestore = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p, side = mon_or_destroy(t, vm, A[2])
  if not p then return end
  d[1] = 0
  d[2] = A[0]
  if P.isOpponent(side) then A[1] = -A[1] end
  if A[3] ~= 1 then d[3] = 0 else d[3] = s16(A[0] * A[1]) end
  d[4] = A[1]
  d[6] = A[3]
  d[7] = 1
  d[3] = -d[3]
  d[4] = -d[4]
  t._fn = rotate_side_step
end)

-- pokefirered/src/battle_anim_mon_movement.c:904
local function shake_power_step(t)
  local d, p = t.data, t._p
  d[0] = d[0] + 1
  if d[0] > d[1] then
    d[0] = 0
    d[12] = band(d[12] + 1, 1)
    if d[10] ~= 0 then
      if d[12] ~= 0 then p.ox = d[8] + d[13] else p.ox = d[8] - d[14] end
    end
    if d[11] ~= 0 then
      if d[12] ~= 0 then p.oy = d[15] else p.oy = 0 end
    end
    d[2] = d[2] - 1
    if d[2] == 0 then
      p.ox = 0
      p.oy = 0
      K.destroy(t)
    end
  end
end

-- pokefirered/src/battle_anim_mon_movement.c:872
T.ShakeTargetBasedOnMovePowerOrDmg = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local v
  if A[0] == 0 then
    v = tonumber(K.ctx(vm, "movePower", 0)) or 0
  else
    v = tonumber(K.ctx(vm, "moveDmg", 0)) or 0
  end
  d[15] = cdiv(v, 12)
  if d[15] < 1 then d[15] = 1 end
  if d[15] > 16 then d[15] = 16 end
  d[14] = cdiv(d[15], 2)
  d[13] = d[14] + band(d[15], 1)
  d[12] = 0
  d[10] = A[3]
  d[11] = A[4]
  local p = mon_or_destroy(t, vm, 1)
  if not p then return end
  d[8] = p.ox or 0
  d[9] = p.oy or 0
  d[0] = 0
  d[1] = A[1]
  d[2] = A[2]
  t._fn = shake_power_step
end)

-- pokefirered/src/battle_anim_mons.c:621
local function translate_by_id(t)
  local d, p = t.data, t._p
  if d[0] > 0 then
    d[0] = d[0] - 1
    p.ox = (p.ox or 0) + d[1]
    p.oy = (p.oy or 0) + d[2]
  else
    t._fn = t._stored or K.destroy
  end
end

-- pokefirered/src/battle_anim_mons.c:635
local function translate_by_id_fixed(t)
  local d, p = t.data, t._p
  if d[0] > 0 then
    d[0] = d[0] - 1
    d[3] = s16(d[3] + d[1])
    d[4] = s16(d[4] + d[2])
    p.ox = arshift(d[3], 8)
    p.oy = arshift(d[4], 8)
  else
    t._fn = t._stored or K.destroy
  end
end

-- pokefirered/src/battle_anim_mons.c:977
local function init_linear_data(d)
  if d[0] == 0 then d[0] = 1 end
  local x = s16(lshift(d[2] - d[1], 8))
  local y = s16(lshift(d[4] - d[3], 8))
  d[1] = cdiv(x, d[0])
  d[2] = cdiv(y, d[0])
  d[4] = 0
  d[3] = 0
end

-- pokefirered/src/battle_anim_mon_movement.c:403
local function reverse_lunge(t)
  local d = t.data
  d[0] = d[4]
  d[1] = -d[1]
  t._fn = translate_by_id
  t._stored = K.destroy
end

-- pokefirered/src/battle_anim_mon_movement.c:388
T.HorizontalLunge = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, 0)
  if not p then return end
  if P.isOpponent(P.atk(vm)) then d[1] = -A[1] else d[1] = A[1] end
  d[0] = A[0]
  d[2] = 0
  d[4] = A[0]
  t._stored = reverse_lunge
  t._fn = translate_by_id
end)
T.DoHorizontalLunge = T.HorizontalLunge

-- pokefirered/src/battle_anim_mon_movement.c:430
local function reverse_dip(t)
  local d = t.data
  d[0] = d[4]
  d[2] = -d[2]
  t._fn = translate_by_id
  t._stored = K.destroy
end

-- pokefirered/src/battle_anim_mon_movement.c:416
T.VerticalDip = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, A[2])
  if not p then return end
  d[0] = A[0]
  d[1] = 0
  d[2] = A[1]
  d[4] = A[0]
  t._stored = reverse_dip
  t._fn = translate_by_id
end)
T.DoVerticalDip = T.VerticalDip

-- pokefirered/src/battle_anim_mon_movement.c:470
local function slide_original_step(t)
  local d, p = t.data, t._p
  local mode = t._mode
  if d[0] == 0 then
    if mode == 1 or mode == 0 then p.ox = 0 end
    if mode == 2 or mode == 0 then p.oy = 0 end
    K.destroy(t)
  else
    d[0] = d[0] - 1
    d[3] = s16(d[3] + d[1])
    d[4] = s16(d[4] + d[2])
    p.ox = arshift(d[3], 8) + d[5]
    p.oy = arshift(d[4], 8) + d[6]
  end
end

-- pokefirered/src/battle_anim_mon_movement.c:443
T.SlideMonToOriginalPos = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local side = (A[0] == 0) and P.atk(vm) or P.tgt(vm)
  local p = P.present(side)
  if not p then return K.destroy(t) end
  t._p = p
  t._side = side
  local x, y = K.monX(vm, side), K.monY(vm, side)
  d[0] = A[2]
  d[1] = x + (p.ox or 0)
  d[2] = x
  d[3] = y + (p.oy or 0)
  d[4] = y
  init_linear_data(d)
  d[3] = 0
  d[4] = 0
  d[5] = p.ox or 0
  d[6] = p.oy or 0
  if A[1] == 1 then d[2] = 0 elseif A[1] == 2 then d[1] = 0 end
  t._mode = A[1]
  t._fn = slide_original_step
end)

-- pokefirered/src/battle_anim_mon_movement.c:500
T.SlideMonToOffset = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local side = (A[0] == 0) and P.atk(vm) or P.tgt(vm)
  local p = P.present(side)
  if not p then return K.destroy(t) end
  t._p = p
  t._side = side
  if P.isOpponent(side) then
    A[1] = -A[1]
    if A[3] == 1 then A[2] = -A[2] end
  end
  local x, y = K.monX(vm, side), K.monY(vm, side)
  d[0] = A[4]
  d[1] = x
  d[2] = x + A[1]
  d[3] = y
  d[4] = y + A[2]
  init_linear_data(d)
  d[3] = 0
  d[4] = 0
  t._stored = K.destroy
  t._fn = translate_by_id_fixed
end)

-- pokefirered/src/battle_anim_mon_movement.c:562
local function slide_offset_back_end(t)
  local p = t._p
  p.ox = 0
  p.oy = 0
  K.destroy(t)
end

-- pokefirered/src/battle_anim_mon_movement.c:529
T.SlideMonToOffsetAndBack = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local side = (A[0] == 0) and P.atk(vm) or P.tgt(vm)
  local p = P.present(side)
  if not p then return K.destroy(t) end
  t._p = p
  t._side = side
  if P.isOpponent(side) then
    A[1] = -A[1]
    if A[3] == 1 then A[2] = -A[2] end
  end
  local x, y = K.monX(vm, side), K.monY(vm, side)
  d[0] = A[4]
  d[1] = x + (p.ox or 0)
  d[2] = d[1] + A[1]
  d[3] = y + (p.oy or 0)
  d[4] = d[3] + A[2]
  init_linear_data(d)
  d[3] = s16(lshift(p.ox or 0, 8))
  d[4] = s16(lshift(p.oy or 0, 8))
  d[6] = A[5]
  if A[5] == 0 then t._stored = K.destroy else t._stored = slide_offset_back_end end
  t._fn = translate_by_id_fixed
end)

-- pokefirered/src/battle_anim_effects_1.c:4549
local function bow_step4(t)
  K.destroy(t)
end

-- pokefirered/src/battle_anim_effects_1.c:4482
local function bow_step1_cb(t)
  local d = t.data
  if d[0] == 0 then
    d[6] = P.isOpponent(t._side) and 1 or 0
    if d[6] ~= 0 then d[4] = 0x300 else d[4] = -0x300 end
    d[5] = 0
  end
  d[5] = s16(d[5] + d[4])
  S.setMonRotScale(t._side, 0x100, 0x100, d[5])
  S.monYOffsetFromRotation(t._side)
  d[0] = d[0] + 1
  if d[0] > 3 then
    d[0] = 0
    t._fn = bow_step4
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4521
local function bow_step3_cb(t)
  local d = t.data
  if d[0] == 0 then
    d[6] = P.isOpponent(t._side) and 1 or 0
    if d[6] ~= 0 then
      d[4] = s16(0xFC00)
      d[5] = 0xC00
    else
      d[4] = 0x400
      d[5] = s16(0xF400)
    end
  end
  d[5] = s16(d[5] + d[4])
  S.setMonRotScale(t._side, 0x100, 0x100, d[5])
  S.monYOffsetFromRotation(t._side)
  d[0] = d[0] + 1
  if d[0] > 2 then
    S.resetMonRotScale(t._side)
    t._fn = bow_step4
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4451
T.BowMon = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, 0)
  if not p then return end
  d[0] = 0
  local mode = A[0]
  if mode == 0 then
    d[0] = 6
    d[1] = P.isOpponent(P.atk(vm)) and 2 or -2
    d[2] = 0
    t._stored = bow_step1_cb
    t._fn = translate_by_id
  elseif mode == 1 then
    d[0] = 4
    d[1] = P.isOpponent(P.atk(vm)) and -3 or 3
    d[2] = 0
    t._stored = bow_step4
    t._fn = translate_by_id
  elseif mode == 2 then
    t._fn = function(tt)
      tt.data[0] = tt.data[0] + 1
      if tt.data[0] > 8 then
        tt.data[0] = 0
        tt._fn = bow_step3_cb
      end
    end
  else
    t._fn = bow_step4
  end
end)

-- pokefirered/src/battle_anim_normal.c:834
local function coord_offset_apply(t, delta)
  local var = t._var
  if var == 0 or var == 1 then
    local x, y = F.bg3Get(t._vm)
    if var == 0 then x = x + delta else y = y + delta end
    F.bg3Set(t._vm, x, y)
    return
  end
  for side in pairs(t._offMons or {}) do
    local p = P.present(side)
    if p then
      if var == 2 then p.ox = (p.ox or 0) + delta else p.oy = (p.oy or 0) + delta end
    end
  end
  t._offAccum = (t._offAccum or 0) + delta
end

-- pokefirered/src/battle_anim_normal.c:804
local function shake_mon_or_terrain_step(t)
  local d = t.data
  if d[3] > 0 then
    d[3] = d[3] - 1
    if d[1] > 0 then
      d[1] = d[1] - 1
    else
      d[1] = d[2]
      coord_offset_apply(t, d[0])
      d[0] = -d[0]
    end
  else
    if t._var == 0 or t._var == 1 then
      F.bg3Set(t._vm, t._origX or 0, t._origY or 0)
    else
      coord_offset_apply(t, -(t._offAccum or 0))
    end
    K.destroy(t)
  end
end

-- pokefirered/src/battle_anim_normal.c:771
T.ShakeMonOrBattleTerrain = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  d[0] = -A[0]
  d[1] = A[1]
  d[2] = A[1]
  d[3] = A[2]
  local var = A[3]
  if var > 3 or var < 0 then var = 3 end
  t._var = var
  t._origX, t._origY = F.bg3Get(vm)
  d[5] = A[3]
  if var == 2 or var == 3 then
    local mons = {}
    if A[4] == 2 then
      mons[P.atk(vm)] = true
      mons[P.tgt(vm)] = true
    elseif A[4] == 0 then
      mons[P.atk(vm)] = true
    else
      mons[P.tgt(vm)] = true
    end
    t._offMons = mons
  end
  t._fn = shake_mon_or_terrain_step
end)

local function blend_state(color, coeff)
  local k = math.max(0, math.min(16, coeff)) / 16
  local r, g, b = P.rgb555(color)
  return { m = 1 - k, r = r * k, g = g * k, b = b * k }
end

-- pokefirered/src/battle_anim_mons.c:2294
local function battler_trace_cb(s)
  s.data[0] = s.data[0] - 1
  if s.data[0] == 0 then
    local t = s._owner
    if t and t.active and t._g1Token == s._ownerToken then t.data[5] = t.data[5] - 1 end
    S.destroy(s)
  end
end

local traceSerial = 0

-- pokefirered/src/battle_anim_mons.c:2277
local function create_battler_trace(t)
  local s = S.cloneMon(t._vm, t._side, t._blend)
  if s then
    s._pri = t.data[6]
    s.data[0] = 8
    s._owner = t
    s._ownerToken = t._g1Token
    s._cb = battler_trace_cb
    t.data[5] = t.data[5] + 1
  end
end

-- pokefirered/src/battle_anim_mons.c:2242
local function punch_trace_step(t)
  local d, p = t.data, t._p
  if d[2] == 0 then
    create_battler_trace(t)
    p.ox = (p.ox or 0) + d[1]
    d[3] = d[3] + 1
    if d[3] == 5 then
      d[3] = d[3] - 1
      d[2] = d[2] + 1
    end
  elseif d[2] == 1 then
    create_battler_trace(t)
    p.ox = (p.ox or 0) - d[1]
    d[3] = d[3] - 1
    if d[3] == 0 then
      p.ox = 0
      d[2] = d[2] + 1
    end
  elseif d[2] == 2 then
    if d[5] == 0 then K.destroy(t) end
  end
end

-- pokefirered/src/battle_anim_mons.c:2213
T.AttackerPunchWithTrace = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, 0)
  if not p then return end
  traceSerial = traceSerial + 1
  t._g1Token = traceSerial
  d[1] = P.isOpponent(t._side) and -8 or 8
  d[2] = 0
  d[3] = 0
  d[5] = 0
  local sub = P.subpriorityOf(t._side)
  d[6] = (sub == 20 or sub == 40) and 2 or 3
  t._blend = blend_state(u16(A[0]), A[1])
  t._fn = punch_trace_step
end)

-- pokefirered/src/battle_anim_utility_funcs.c:274
local function mon_trace_cb(s)
  if s.data[0] ~= 0 then
    s.data[0] = s.data[0] - 1
  else
    local t = s._owner
    if t and t.active and t._g1Token == s._ownerToken then t.data[5] = t.data[5] - 1 end
    S.destroy(s)
  end
end

-- pokefirered/src/battle_anim_utility_funcs.c:242
local function trace_blended_step(t)
  local d = t.data
  if d[4] ~= 0 then
    if d[1] ~= 0 then
      d[1] = d[1] - 1
    else
      local s = S.cloneMon(t._vm, t._side, nil)
      if s then
        s._pri = (d[0] ~= 0) and 1 or 2
        s.data[0] = d[3]
        s._owner = t
        s._ownerToken = t._g1Token
        s._cb = mon_trace_cb
        d[5] = d[5] + 1
      end
      d[4] = d[4] - 1
      d[1] = d[2]
    end
  elseif d[5] == 0 then
    K.destroy(t)
  end
end

-- pokefirered/src/battle_anim_utility_funcs.c:230
T.TraceMonBlended = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, A[0])
  if not p then return end
  traceSerial = traceSerial + 1
  t._g1Token = traceSerial
  d[0] = A[0]
  d[1] = 0
  d[2] = A[1]
  d[3] = A[2]
  d[4] = A[3]
  d[5] = 0
  t._fn = trace_blended_step
end)

-- pokefirered/src/battle_anim_effects_1.c:5261
local function double_team_cb(s)
  local d = s.data
  d[3] = d[3] + 1
  if d[3] > 1 then
    d[3] = 0
    d[0] = d[0] + 1
  end
  if d[0] > 64 then
    local t = s._owner
    if t and t.active and t._g1Token == s._ownerToken then t.data[3] = t.data[3] - 1 end
    S.destroy(s)
  else
    d[4] = cdiv(P.gSine(d[0]), 6)
    d[5] = cdiv(P.gSine(d[0]), 13)
    d[1] = band(d[1] + d[5], 0xFF)
    s.ox = Sin(d[1], d[4])
  end
end

-- pokefirered/src/battle_anim_effects_1.c:5209
T.DoubleTeam = K.wrap(function(t, vm)
  local d = t.data
  local p = mon_or_destroy(t, vm, 0)
  if not p then return end
  traceSerial = traceSerial + 1
  t._g1Token = traceSerial
  d[3] = 0
  local st = blend_state(0, 11)
  for i = 0, 1 do
    local s = S.cloneMon(vm, t._side, st)
    if not s then break end
    s.data[0] = 0
    s.data[1] = lshift(i, 7)
    s._owner = t
    s._ownerToken = t._g1Token
    s._cb = double_team_cb
    d[3] = d[3] + 1
  end
  t._fn = function(tt)
    if tt.data[3] == 0 then K.destroy(tt) end
  end
end)

-- pokefirered/src/battle_anim_utility_funcs.c:583
local function flash_step(t)
  local d = t.data
  if d[0] == 0 then
    d[1] = d[1] + 1
    if d[1] > 6 then
      d[1] = 0
      d[2] = 16
      d[0] = d[0] + 1
    end
  elseif d[0] == 1 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[2] = d[2] - 1
      P.Pal.blend("bg", d[2], 0x7FFF)
      for _, id in ipairs(P.visibleIds()) do P.Pal.blend(id, d[2], 0) end
      P.Pal.flush()
      if d[2] == 0 then d[0] = d[0] + 1 end
    end
  elseif d[0] == 2 then
    K.destroy(t)
  end
end

T.Flash = K.wrap(function(t, vm)
  for _, id in ipairs(P.visibleIds()) do P.Pal.setFaded(id, { m = 0, r = 0, g = 0, b = 0 }) end
  P.Pal.setFaded("bg", { m = 0, r = 1, g = 1, b = 1 })
  P.Pal.flush()
  t.data[0] = 0
  t.data[1] = 0
  t._fn = flash_step
end)

-- pokefirered/src/battle_anim_utility_funcs.c:683
local function update_sliding_bg(t, vm)
  local d = t.data
  d[10] = d[10] + d[1]
  d[11] = d[11] + d[2]
  local x, y = F.bg3Get(vm)
  F.bg3Set(vm, x + arshift(d[10], 8), y + arshift(d[11], 8))
  d[10] = band(d[10], 0xFF)
  d[11] = band(d[11], 0xFF)
  if vm and vm.args and s16(vm.args[7] or 0) == d[3] then
    F.bg3Set(vm, 0, 0)
    K.destroy(t)
  end
end

-- pokefirered/src/battle_anim_utility_funcs.c:665
T.StartSlidingBg = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  if A[2] ~= 0 and P.isOpponent(P.atk(vm)) then
    A[0] = -A[0]
    A[1] = -A[1]
  end
  d[1] = A[0]
  d[2] = A[1]
  d[3] = A[3]
  d[0] = 1
  t._uncounted = true
  t._fn = update_sliding_bg
end)

-- pokefirered/src/battle_anim_utility_funcs.c:652
T.BlendNonAttackerPalettes = K.wrap(function(t, vm)
  local A = t._A
  for j = 5, 1, -1 do A[j] = A[j - 1] end
  local keys = {}
  for id = 0, 3 do
    if id ~= P.atkId(vm) and (id < 2 or P.spriteVisible(id)) then keys[#keys + 1] = id end
  end
  t._keys = keys
  local d = t.data
  d[2] = A[1]
  d[3] = A[2]
  d[4] = A[3]
  d[5] = A[4]
  d[10] = A[2]
  t._fn = function(tt)
    local dd = tt.data
    if dd[9] == dd[2] then
      dd[9] = 0
      for _, key in ipairs(tt._keys) do P.Pal.blend(key, dd[10], u16(dd[5])) end
      P.Pal.flush()
      if dd[10] < dd[4] then dd[10] = dd[10] + 1
      elseif dd[10] > dd[4] then dd[10] = dd[10] - 1
      else K.destroy(tt) end
    else
      dd[9] = dd[9] + 1
    end
  end
  t._fn(t)
end)

-- pokefirered/src/battle_anim_utility_funcs.c:719
T.SetAllNonAttackersInvisiblity = K.wrap(function(t, vm)
  for _, id in ipairs(P.visibleIds(P.atkId(vm))) do
    local p = P.present(id)
    if p then p.visible = (t._A[0] == 0) end
  end
  K.destroy(t)
end)

-- pokefirered/src/battle_anim_effects_1.c:4635
local function skull_bash_set(t)
  local d, p, side = t.data, t._p, t._side
  local st = d[2]
  if st == 0 then
    if d[3] ~= 0 then
      d[4] = d[4] + d[5]
      p.ox = d[4]
      d[3] = d[3] - 1
    else
      d[3] = 8
      d[4] = 0
      d[5] = (d[1] == 0) and -0xC0 or 0xC0
      d[2] = d[2] + 1
    end
  elseif st == 1 then
    if d[3] ~= 0 then
      d[4] = s16(d[4] + d[5])
      S.setMonRotScale(side, 0x100, 0x100, d[4])
      S.monYOffsetFromRotation(side)
      d[3] = d[3] - 1
    else
      d[3] = 8
      d[4] = p.ox or 0
      d[5] = (d[1] == 0) and 2 or -2
      d[6] = 1
      d[2] = d[2] + 1
    end
  elseif st == 2 then
    if d[3] ~= 0 then
      if d[6] ~= 0 then
        d[6] = d[6] - 1
      else
        if band(d[3], 1) ~= 0 then p.ox = d[4] + d[5] else p.ox = d[4] - d[5] end
        d[6] = 1
        d[3] = d[3] - 1
      end
    else
      p.ox = d[4]
      d[3] = 12
      d[2] = d[2] + 1
    end
  elseif st == 3 then
    if d[3] ~= 0 then
      d[3] = d[3] - 1
    else
      d[3] = 3
      d[4] = p.ox or 0
      d[5] = (d[1] == 0) and 8 or -8
      d[2] = d[2] + 1
    end
  elseif st == 4 then
    if d[3] ~= 0 then
      d[4] = d[4] + d[5]
      p.ox = d[4]
      d[3] = d[3] - 1
    else
      K.destroy(t)
    end
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4727
local function skull_bash_reset(t)
  local d = t.data
  if d[3] ~= 0 then
    d[4] = s16(d[4] - d[5])
    S.setMonRotScale(t._side, 0x100, 0x100, d[4])
    S.monYOffsetFromRotation(t._side)
    d[3] = d[3] - 1
  else
    S.resetMonRotScale(t._side)
    K.destroy(t)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4597
T.SkullBashPosition = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local p = mon_or_destroy(t, vm, 0)
  if not p then return end
  d[1] = P.isOpponent(t._side) and 1 or 0
  d[2] = 0
  if A[0] == 0 then
    d[3] = 8
    d[4] = 0
    d[5] = (d[1] == 0) and -3 or 3
    t._fn = skull_bash_set
  elseif A[0] == 1 then
    d[3] = 8
    d[4] = 0x600
    d[5] = 0xC0
    if d[1] == 0 then
      d[4] = -d[4]
      d[5] = -d[5]
    end
    t._fn = skull_bash_reset
  else
    K.destroy(t)
  end
end)

-- pokefirered/src/battle_anim_effects_1.c:2867
local function shrink_copy_step2(t, vm)
  local d = t.data
  if vm and vm.args and u16(vm.args[7] or 0) == 0xFFFF then
    if d[0] == 0 then
      S.resetMonRotScale(t._side)
      t._p.ox = 0
      t._p.oy = 0
      d[0] = d[0] + 1
      return
    end
  else
    if d[0] == 0 then return end
  end
  d[0] = d[0] + 1
  if d[0] == 3 then K.destroy(t) end
end

-- pokefirered/src/battle_anim_effects_1.c:2848
local function shrink_copy_step1(t, vm)
  local d, p = t.data, t._p
  d[10] = s16(d[10] + d[0])
  p.ox = arshift(d[10], 8)
  if P.isOpponent(t._side) then p.ox = -p.ox end
  d[11] = s16(d[11] + 16)
  S.setMonRotScale(t._side, d[11], d[11], 0)
  S.monYOffsetFromYScale(vm, t._side)
  d[1] = d[1] - 1
  if d[1] == 0 then
    d[0] = 0
    t._fn = shrink_copy_step2
  end
end

-- pokefirered/src/battle_anim_effects_1.c:2830
T.ShrinkTargetCopy = K.wrap(function(t, vm)
  local p = mon_or_destroy(t, vm, 1)
  if not p then return end
  if p.visible == false then return K.destroy(t) end
  t.data[0] = t._A[0]
  t.data[1] = t._A[1]
  t.data[11] = 0x100
  t._fn = shrink_copy_step1
end)

-- pokefirered/src/battle_anim_mons.c:1570
local function alpha_fade_in_step(t, vm)
  local d = t.data
  d[0] = d[0] + 1
  if d[0] > d[1] then
    d[0] = 0
    d[2] = d[2] + 1
    if band(d[2], 1) ~= 0 then
      if d[3] ~= d[7] then d[3] = d[3] + d[5] end
    else
      if d[4] ~= d[8] then d[4] = d[4] + d[6] end
    end
    P.setBldAlpha(vm, d[3], d[4])
    if d[3] == d[7] and d[4] == d[8] then K.destroy(t) end
  end
end

-- pokefirered/src/battle_anim_mons.c:1545
T.AlphaFadeIn = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  local v1, v2 = 0, 0
  if A[2] > A[0] then v2 = 1 elseif A[2] < A[0] then v2 = -1 end
  if A[3] > A[1] then v1 = 1 elseif A[3] < A[1] then v1 = -1 end
  d[0] = 0
  d[1] = A[4]
  d[2] = 0
  d[3] = A[0]
  d[4] = A[1]
  d[5] = v2
  d[6] = v1
  d[7] = A[2]
  d[8] = A[3]
  P.setBldAlpha(vm, A[0], A[1])
  t._fn = alpha_fade_in_step
end)

-- pokefirered/src/battle_anim_normal.c:302
T.SimplePaletteBlend = K.wrap(function(t, vm)
  local A = t._A
  P.beginNormalPaletteFade(P.unpackSelected(vm, A[0]), A[1], A[2], A[3], u16(A[4]))
  t._fn = function(tt)
    if not P.fadeActive() then K.destroy(tt) end
  end
end)

-- pokefirered/src/battle_anim_normal.c:383
local function complex_blend_step2(t)
  if not P.fadeActive() then
    P.blendPalettes(t._keys, 0, 0)
    K.destroy(t)
  end
end

-- pokefirered/src/battle_anim_normal.c:357
local function complex_blend_step1(t)
  local d = t.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    return
  end
  if P.fadeActive() then return end
  if d[2] == 0 then
    t._fn = complex_blend_step2
    return
  end
  if band(d[1], 0x100) ~= 0 then
    P.blendPalettes(t._keys, d[4], u16(d[3]))
  else
    P.blendPalettes(t._keys, d[6], u16(d[5]))
  end
  d[1] = bxor(d[1], 0x100)
  d[0] = band(d[1], 0xFF)
  d[2] = d[2] - 1
end

-- pokefirered/src/battle_anim_normal.c:339
T.ComplexPaletteBlend = K.wrap(function(t, vm)
  local A, d = t._A, t.data
  d[0] = A[1]
  d[1] = A[1]
  d[2] = A[2]
  d[3] = A[3]
  d[4] = A[4]
  d[5] = A[5]
  d[6] = A[6]
  d[7] = A[0]
  t._keys = P.unpackSelected(vm, d[7])
  P.blendPalettes(t._keys, A[4], u16(A[3]))
  t._fn = complex_blend_step1
end)

end
