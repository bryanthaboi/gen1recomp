local bit = require("bit")
local P = require("src.core.game3.battle.anim_port.g1_pret")
local S = require("src.core.game3.battle.anim_port.g1_sprite")
local AnimPal = require("src.core.game3.battle.anim_pal")

local band, bor, bxor, rshift, arshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.arshift, bit.lshift
local s16, u16, u8 = P.s16, P.u16, P.u8
local Sin, Cos = P.Sin, P.Cos
local cdiv = P.cdiv

local function random16()
  return math.random(0, 0xFFFF)
end

local function atk_opp(s)
  return P.isOpponent(P.atk(s._vm))
end

local function c8(r, g, b)
  return { r * 8 / 255, g * 8 / 255, b * 8 / 255 }
end

local function c555(c)
  return { band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31 }
end

-- pokefirered/graphics/battle_anims/sprites/protect.png
P.PAL_PROTECT = { c8(31, 31, 31), c8(23, 31, 27), c8(15, 31, 23), c8(7, 31, 19), c8(7, 26, 16), c8(7, 22, 14), c8(7, 17, 11) }
-- pokefirered/graphics/battle_anims/sprites/lock_on.png
P.PAL_LOCK_ON = { c8(0, 29, 0), c8(0, 19, 0), c8(0, 9, 0), false, false, false, false, c8(31, 0, 0), c8(20, 0, 0) }
-- pokefirered/graphics/battle_anims/sprites/music_notes.png
P.PAL_MUSIC_NOTES = { c8(31, 31, 31), c8(27, 25, 25), c8(27, 22, 23), c8(31, 13, 22), c8(31, 7, 19) }

-- pokefirered/src/battle_anim_effects_1.c:1999
P.PARTICLES_COLOR_BLEND = {
  [0] = { "MUSIC_NOTES", 0x7FFF, P.RGB(31, 26, 28), P.RGB(31, 22, 26), P.RGB(31, 17, 24), P.RGB(31, 13, 22) },
  [1] = { "BENT_SPOON", 0x7FFF, P.RGB(25, 31, 26), P.RGB(20, 31, 21), P.RGB(15, 31, 16), P.RGB(10, 31, 12) },
  [2] = { "SPHERE_TO_CUBE", 0x7FFF, P.RGB(31, 31, 24), P.RGB(31, 31, 17), P.RGB(31, 31, 10), P.RGB(31, 31, 3) },
  [3] = { "LARGE_FRESH_EGG", 0x7FFF, P.RGB(26, 28, 31), P.RGB(21, 26, 31), P.RGB(16, 24, 31), P.RGB(12, 22, 31) },
}

function P.musicNotesRemap(row)
  local src, dst = {}, {}
  for i = 1, 5 do
    src[i] = P.PAL_MUSIC_NOTES[i]
    dst[i] = c555(row[i + 1])
  end
  return { src = src, dst = dst }
end

-- pokefirered/src/battle_anim_effects_1.c:882
local TRICK_BAG_COORDS = {
  [0] = { 5, 24, 1 }, { 0, 4, 0 }, { 8, 16, -1 }, { 0, 2, 0 }, { 8, 16, 1 }, { 0, 2, 0 },
  { 8, 16, 1 }, { 0, 2, 0 }, { 8, 16, 1 }, { 0, 16, 0 }, { 0, 0, 127 },
}

-- pokefirered/src/battle_anim_effects_1.c:1571
local INCLINE_MON_COORDS = { [0] = { 64, 64 }, { 0, -64 }, { -64, 64 }, { 32, -32 } }

return function(C, F)

-- pokefirered/src/battle_anim_effects_1.c:3009
local function init_item_bag(s, c)
  local a = bor(lshift(s.x, 8), band(s.y, 0xFF))
  local b = bor(lshift(s.data[6], 8), band(s.data[7], 0xFF))
  s.data[5] = s16(a)
  s.data[6] = s16(b)
  s.data[7] = s16(lshift(c, 8))
end

-- pokefirered/src/battle_anim_effects_1.c:3019
function F.MoveAlongLinearPath(s)
  local d = s.data
  local xStart = u8(arshift(d[5], 8))
  local yStart = u8(d[5])
  local xEnd = u8(arshift(d[6], 8))
  local yEnd = u8(d[6])
  local total = arshift(d[7], 8)
  local cur = band(d[7], 0xFF)
  if xEnd == 0 then xEnd = -32 elseif xEnd == 255 then xEnd = P.DISPLAY_WIDTH + 32 end
  local dy = s16(yEnd - yStart)
  local r0 = s16(xEnd - xStart)
  s.x = cdiv(r0 * cur, total) + xStart
  s.y = cdiv(dy * cur, total) + yStart
  cur = cur + 1
  if cur == total then return true end
  d[7] = s16(bor(lshift(total, 8), cur))
  return false
end

-- pokefirered/src/battle_anim_effects_1.c:3050
function F.ItemStealStep2(s)
  if s.data[0] == 10 then S.startAffineAnim(s, 1) end
  s.data[0] = s.data[0] + 1
  if s.data[0] > 50 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:3060
function F.ItemStealStep1(s)
  local d = s.data
  d[0] = d[0] + cdiv(d[3] * 128, d[4])
  if d[0] >= 128 then
    d[1] = d[1] + 1
    d[0] = 0
  end
  s.oy = Sin(d[0] + 128, 30 - d[1] * 8)
  if F.MoveAlongLinearPath(s) then
    s.oy = 0
    d[0] = 0
    s._cb = F.ItemStealStep2
  end
end

-- pokefirered/src/battle_anim_effects_1.c:3078
C.Present = S.wrap(function(s)
  local vm = s._vm
  S.initPosToAttacker(s, false)
  local tx = P.coord(vm, P.tgt(vm), P.X)
  local ty = P.coord(vm, P.tgt(vm), P.Y)
  s.data[6] = tx
  s.data[7] = ty + 10
  init_item_bag(s, 60)
  s.data[3] = 3
  s.data[4] = 60
  s._cb = F.ItemStealStep1
end)

-- pokefirered/src/battle_anim_effects_1.c:3105
function F.KnockOffOpponentsItem(s)
  local d = s.data
  d[0] = d[0] + cdiv(d[3] * 128, d[4])
  if d[0] > 0x7F then
    d[1] = d[1] + 1
    d[0] = 0
  end
  s.oy = Sin(d[0] + 0x80, 30 - d[1] * 8)
  if F.MoveAlongLinearPath(s) then
    s.oy = 0
    d[0] = 0
    S.destroy(s)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:3126
C.KnockOffItem = S.wrap(function(s)
  local vm = s._vm
  local ty = P.coord(vm, P.tgt(vm), P.Y)
  if not P.isOpponent(P.tgt(vm)) then
    s.data[6] = 0
    s.data[7] = ty + 10
    init_item_bag(s, 40)
    s.data[3] = 3
    s.data[4] = 60
    s._cb = F.ItemStealStep1
  else
    s.data[6] = 255
    s.data[7] = ty + 10
    init_item_bag(s, 40)
    s.data[3] = 3
    s.data[4] = 60
    s._cb = F.KnockOffOpponentsItem
  end
end)

-- pokefirered/src/battle_anim_effects_1.c:3158
C.PresentHealParticle = S.wrap(function(s)
  s._cb = function(sp)
    local d = sp.data
    if d[0] == 0 then
      S.initPosToTarget(sp, false)
      d[1] = sp._A[2]
    end
    d[0] = d[0] + 1
    sp.oy = d[1] * d[0]
    if sp.animEnded then S.destroy(sp) end
  end
  s._cb(s)
end)

-- pokefirered/src/battle_anim_effects_1.c:3199
function F.ItemStealStep3(s)
  local d, vm = s.data, s._vm
  d[0] = d[0] + cdiv(d[3] * 128, d[4])
  if d[0] > 127 then
    d[1] = d[1] + 1
    d[0] = 0
  end
  s.oy = Sin(d[0] + 0x80, 30 - d[1] * 8)
  if s.oy == 0 then P.playSe(P.seId("SE_M_BUBBLE2"), P.adjustPanning(vm, P.SOUND_PAN_TARGET)) end
  if F.MoveAlongLinearPath(s) then
    s.oy = 0
    d[0] = 0
    s._cb = F.ItemStealStep2
    P.playSe(P.seId("SE_M_BUBBLE2"), P.adjustPanning(vm, P.SOUND_PAN_ATTACKER))
  end
end

-- pokefirered/src/battle_anim_effects_1.c:3172
C.ItemSteal = S.wrap(function(s)
  local vm = s._vm
  S.initPosToTarget(s, false)
  local ax = P.coord(vm, P.atk(vm), P.X)
  local ay = P.coord(vm, P.atk(vm), P.Y)
  s.data[6] = ax
  s.data[7] = ay + 10
  init_item_bag(s, 60)
  s.data[3] = 3
  s.data[4] = 60
  s._cb = F.ItemStealStep3
end)

-- pokefirered/src/battle_anim_effects_1.c:3324
function F.TrickBagStep3(s)
  if s.data[0] > 20 then S.destroy(s) return end
  s.visible = (s.data[0] % 2) == 0
  s.data[0] = s.data[0] + 1
end

-- pokefirered/src/battle_anim_effects_1.c:3294
function F.TrickBagStep2(s)
  local d = s.data
  local row = TRICK_BAG_COORDS[d[0]]
  if not row then S.destroy(s) return end
  if d[2] == row[2] then
    if row[3] == 127 then
      d[0] = 0
      s._cb = F.TrickBagStep3
    end
    d[2] = 0
    d[0] = d[0] + 1
  else
    d[2] = d[2] + 1
    d[1] = band(row[1] * row[3] + d[1], 0xFF)
    if u16(d[1] - 1) < 191 then s.subpriority = 31 else s.subpriority = 29 end
    s.ox = Cos(d[1], 60)
    s.oy = Sin(d[1], 20)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:3264
function F.TrickBagStep1(s)
  local d = s.data
  if d[3] == 0 then
    if d[2] > 78 then
      d[3] = 1
      S.startAffineAnim(s, 1)
    else
      d[2] = d[2] + cdiv(d[4], 10)
      d[4] = d[4] + 3
      s.y = d[2]
    end
  elseif d[3] == 1 then
    if s.affineAnimEnded then
      d[0] = 0
      d[2] = 0
      s._cb = F.TrickBagStep2
    end
  end
end

-- pokefirered/src/battle_anim_effects_1.c:3227
C.TrickBag = S.wrap(function(s)
  local A, d = s._A, s.data
  if d[0] == 0 then
    d[1] = A[1]
    s.x = 120
    s.y = A[0]
    d[2] = A[0]
    d[4] = 20
    s.ox = Cos(d[1], 60)
    s.oy = Sin(d[1], 20)
    s._cb = F.TrickBagStep1
    if d[1] > 0 and d[1] < 192 then s.subpriority = 31 else s.subpriority = 29 end
  end
end)

-- pokefirered/src/battle_anim_effects_1.c:3646
function F.FlyingParticleStep(s)
  local d = s.data
  local a = d[7]
  d[7] = d[7] + 1
  s.oy = arshift(d[1] * P.gSine(d[0]), 8)
  s.ox = d[2] * a
  d[0] = band(d[3] * a, 0xFF)
  if d[4] == 0 then
    if s.ox + s.x <= 0xF7 then return end
  else
    if s.ox + s.x > -16 then return end
  end
  S.destroy(s)
end

-- pokefirered/src/battle_anim_effects_1.c:3597
C.FlyingParticle = S.wrap(function(s)
  local A, vm, d = s._A, s._vm, s.data
  local side = (A[6] == 0) and P.atk(vm) or P.tgt(vm)
  if P.isOpponent(side) then
    d[4] = 0
    d[2] = A[3]
    s.x = -16
  else
    d[4] = 1
    d[2] = -A[3]
    s.x = 0x100
  end
  d[1] = A[1]
  d[0] = A[2]
  d[3] = A[4]
  local sel = A[5]
  if sel == 0 then
    s.y = A[0]
    s._pri = P.bgPriorityOf(side)
  elseif sel == 1 then
    s.y = A[0]
    s._pri = P.bgPriorityOf(side) + 1
  elseif sel == 2 then
    s.y = P.coord(vm, side, P.Y_PIC_OFFSET) + A[0]
    s._pri = P.bgPriorityOf(side)
  elseif sel == 3 then
    s.y = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + A[0]
    s._pri = P.bgPriorityOf(side) + 1
  end
  s._cb = F.FlyingParticleStep
end)

-- pokefirered/src/battle_anim_effects_1.c:3755
function F.NeedleArmSpikeStep(s)
  local d = s.data
  if d[0] ~= 0 then
    d[1] = s16(d[1] + d[3])
    d[2] = s16(d[2] + d[4])
    s.x = arshift(d[1], 4)
    s.y = arshift(d[2], 4)
    d[0] = d[0] - 1
  else
    S.destroy(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:1281
local function arctan2neg(x, y)
  local a = math.atan2(y, x)
  local v = band(math.floor(a * 65536 / (2 * math.pi) + 0.5), 0xFFFF)
  return band(-v, 0xFFFF)
end
F.ArcTan2Neg = arctan2neg

-- pokefirered/src/battle_anim_effects_1.c:3699
C.NeedleArmSpike = S.wrap(function(s)
  local A, vm, d = s._A, s._vm, s.data
  if A[4] == 0 then
    S.destroy(s)
    return
  end
  local a, b
  if A[0] == 0 then
    a = u8(P.coord(vm, P.atk(vm), P.X_2))
    b = u8(P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET))
  else
    a = u8(P.coord(vm, P.tgt(vm), P.X_2))
    b = u8(P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET))
  end
  d[0] = A[4]
  if A[1] == 0 then
    s.x = A[2] + a
    s.y = A[3] + b
    d[5] = a
    d[6] = b
  else
    s.x = a
    s.y = b
    d[5] = A[2] + a
    d[6] = A[3] + b
  end
  local x = u16(s.x)
  d[1] = s16(x * 16)
  local y = u16(s.y)
  d[2] = s16(y * 16)
  d[3] = s16(cdiv((d[5] - s.x) * 16, A[4]))
  d[4] = s16(cdiv((d[6] - s.y) * 16, A[4]))
  local c = arctan2neg(s16(d[5] - x), s16(d[6] - y))
  S.trySetRotScale(s, false, 0x100, 0x100, c)
  s._cb = F.NeedleArmSpikeStep
end)

-- pokefirered/src/battle_anim_effects_1.c:3771
function F.WhipHitWaitEnd(s)
  if s.animEnded then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:3794
C.WhipHit = S.wrap(function(s)
  local A = s._A
  if not atk_opp(s) then S.startAnim(s, 1) end
  s._cb = F.WhipHitWaitEnd
  S.setInitialXOffset(s, A[0])
  s.y = s.y + A[1]
end)

-- pokefirered/src/battle_anim_effects_1.c:3899
function F.SliceStep(s)
  local d = s.data
  d[3] = s16(d[3] + d[1])
  d[4] = s16(d[4] + d[2])
  if d[5] == 0 then d[1] = s16(d[1] + 0x18) else d[1] = s16(d[1] - 0x18) end
  d[2] = s16(d[2] - 0x18)
  s.ox = arshift(d[3], 8)
  s.oy = arshift(d[4], 8)
  d[0] = d[0] + 1
  if d[0] == 20 then
    S.store(s, S.destroy)
    d[0] = 3
    s._cb = S.waitAnimForDuration
  end
end

local function slice_setup(s, a, b)
  local A, vm, d = s._A, s._vm, s.data
  s.x = a
  s.y = b
  if not P.isOpponent(P.tgt(vm)) then s.y = s.y + 8 end
  s._cb = F.SliceStep
  if A[2] == 0 then
    s.x = s.x + A[0]
  else
    s.x = s.x - A[0]
    s._hFlip = true
  end
  s.y = s.y + A[1]
  d[1] = s16(d[1] - 0x400)
  d[2] = s16(d[2] + 0x400)
  d[5] = A[2]
  if d[5] == 1 then d[1] = -d[1] end
end

-- pokefirered/src/battle_anim_effects_1.c:3822
C.CuttingSlice = S.wrap(function(s)
  local vm = s._vm
  slice_setup(s, P.coord(vm, P.tgt(vm), P.X), P.coord(vm, P.tgt(vm), P.Y))
end)

-- pokefirered/src/battle_anim_effects_1.c:3848
C.AirCutterSlice = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local tgt = P.tgt(vm)
  local a, b
  if A[3] == 1 then
    local partner = P.isOpponent(tgt) and { 112, 80 } or { 48, 40 }
    a, b = partner[1], partner[2]
  else
    a = u8(P.coord(vm, tgt, P.X))
    b = u8(P.coord(vm, tgt, P.Y))
  end
  slice_setup(s, a, b)
end)

-- pokefirered/src/battle_anim_effects_1.c:4006
function F.ProtectStep(s)
  local d, vm = s.data, s._vm
  d[5] = s16(d[5] + 96)
  s.ox = -arshift(d[5], 8)
  d[1] = d[1] + 1
  if d[1] > 1 then
    d[1] = 0
    local f = AnimPal.writeFaded("PROTECT")
    if f then
      local saved = f[1]
      for i = 1, 6 do f[i] = f[i + 1] end
      f[7] = saved
    end
  end
  if d[7] > 6 and d[0] > 0 then
    d[6] = d[6] + 1
    if d[6] > 1 then
      d[6] = 0
      d[7] = d[7] - 1
      P.setBldAlpha(vm, 16 - d[7], d[7])
    end
  end
  if d[0] > 0 then
    d[0] = d[0] - 1
  else
    d[6] = d[6] + 1
    if d[6] > 1 then
      d[6] = 0
      d[7] = d[7] + 1
      P.setBldAlpha(vm, 16 - d[7], d[7])
      if d[7] == 16 then
        s.visible = false
        s._cb = function(sp)
          P.clearBld(sp._vm)
          S.destroy(sp)
        end
      end
    end
  end
end

-- pokefirered/src/battle_anim_effects_1.c:3986
C.Protect = S.wrap(function(s)
  local A, vm = s._A, s._vm
  s.x = P.coord(vm, P.atk(vm), P.X) + A[0]
  s.y = P.coord(vm, P.atk(vm), P.Y) + A[1]
  if not atk_opp(s) then
    s._pri = P.bgPriorityOf(P.atk(vm)) + 1
  else
    s._pri = P.bgPriorityOf(P.atk(vm))
  end
  s.data[0] = A[2]
  s.data[7] = 16
  P.setBldAlpha(vm, 16 - s.data[7], s.data[7])
  s._cb = F.ProtectStep
end)

-- pokefirered/src/battle_anim_effects_1.c:4138
function F.MilkBottleStep2(s)
  local d = s.data
  if d[3] <= 11 then d[4] = d[4] + 2 end
  if u16(d[3] - 0x12) <= 0x17 then d[4] = d[4] - 2 end
  if d[3] > 0x2F then d[4] = d[4] + 2 end
  s.ox = cdiv(d[4], 9)
  s.oy = cdiv(d[4], 14)
  if s.oy < 0 then s.oy = -s.oy end
  d[3] = d[3] + 1
  if d[3] > 0x3B then d[3] = 0 end
end

-- pokefirered/src/battle_anim_effects_1.c:4065
function F.MilkBottleStep1(s)
  local d, vm = s.data, s._vm
  local st = d[0]
  if st == 0 then
    d[2] = d[2] + 1
    if d[2] > 0 then
      d[2] = 0
      d[1] = d[1] + 1
      if band(d[1], 1) ~= 0 then
        if d[6] <= 15 then d[6] = d[6] + 1 end
      elseif d[7] > 0 then
        d[7] = d[7] - 1
      end
      P.setBldAlpha(vm, d[6], d[7])
      if d[6] == 16 and d[7] == 0 then
        d[1] = 0
        d[0] = d[0] + 1
      end
    end
  elseif st == 1 then
    d[1] = d[1] + 1
    if d[1] > 8 then
      d[1] = 0
      S.startAffineAnim(s, 1)
      d[0] = d[0] + 1
    end
  elseif st == 2 then
    F.MilkBottleStep2(s)
    d[1] = d[1] + 1
    if d[1] > 2 then
      d[1] = 0
      s.y = s.y + 1
    end
    d[2] = d[2] + 1
    if d[2] <= 29 then return end
    if band(d[2], 1) ~= 0 then
      if d[6] > 0 then d[6] = d[6] - 1 end
    elseif d[7] <= 15 then
      d[7] = d[7] + 1
    end
    P.setBldAlpha(vm, d[6], d[7])
    if d[6] == 0 and d[7] == 16 then
      d[1] = 0
      d[2] = 0
      d[0] = d[0] + 1
    end
  elseif st == 3 then
    s.visible = false
    d[0] = d[0] + 1
  elseif st == 4 then
    P.clearBld(vm)
    S.destroy(s)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4049
C.MilkBottle = S.wrap(function(s)
  local vm = s._vm
  s.x = P.coord(vm, P.tgt(vm), P.X_2)
  s.y = s16(P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + 0xFFE8)
  for i = 0, 7 do s.data[i] = 0 end
  s.data[7] = 16
  P.setBldAlpha(vm, s.data[6], s.data[7])
  s._cb = F.MilkBottleStep1
end)

-- pokefirered/src/battle_anim_effects_1.c:4159
C.GrantingStars = S.wrap(function(s)
  local A = s._A
  if A[2] == 0 then S.setToAttackerCoords(s) end
  S.setInitialXOffset(s, A[0])
  s.y = s.y + A[1]
  s.data[0] = A[5]
  s.data[1] = A[3]
  s.data[2] = A[4]
  S.store(s, S.destroy)
  s._cb = S.translateSpriteLinearFixedPoint
end)

-- pokefirered/src/battle_anim_effects_1.c:4173
C.SparklingStars = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local side = (A[2] == 0) and P.atk(vm) or P.tgt(vm)
  if A[6] == 0 then
    s.x = P.coord(vm, side, P.X)
    s.y = P.coord(vm, side, P.Y) + A[1]
  else
    s.x = P.coord(vm, side, P.X_2)
    s.y = P.coord(vm, side, P.Y_PIC_OFFSET) + A[1]
  end
  S.setInitialXOffset(s, A[0])
  s.data[0] = A[5]
  s.data[1] = A[3]
  s.data[2] = A[4]
  S.store(s, S.destroy)
  s._cb = S.translateSpriteLinearFixedPoint
end)

-- pokefirered/src/battle_anim_effects_1.c:4262
function F.SleepLetterZStep(s)
  local d = s.data
  s.oy = -cdiv(d[0], 0x28)
  s.ox = cdiv(d[4], 10)
  d[4] = s16(d[4] + d[3] * 2)
  d[0] = s16(d[0] + d[1])
  d[1] = d[1] + 1
  if d[1] > 60 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:4242
C.SleepLetterZ = S.wrap(function(s)
  local A = s._A
  S.setToAttackerCoords(s)
  if not atk_opp(s) then
    s.x = s.x + A[0]
    s.y = s.y + A[1]
    s.data[3] = 1
  else
    s.x = s.x - A[0]
    s.y = s.y + A[1]
    s.data[3] = -1
    S.startAffineAnim(s, 1)
  end
  s._cb = F.SleepLetterZStep
end)

-- pokefirered/src/battle_anim_effects_1.c:4406
function F.LockOnStep6(s)
  local d = s.data
  if d[0] % 3 == 0 then
    d[1] = d[1] + 1
    s.visible = not s.visible
  end
  d[0] = d[0] + 1
  if d[1] == 8 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:4396
function F.LockOnStep5(s)
  local vm = s._vm
  if vm and vm.args and u16(vm.args[7] or 0) == 0xFFFF then
    s.data[1] = 0
    s.data[0] = 0
    s._cb = F.LockOnStep6
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4369
function F.LockOnStep4(s)
  local d, vm = s.data, s._vm
  if d[2] == 0 then
    d[1] = d[1] + 3
    if d[1] > 16 then d[1] = 16 end
  else
    d[1] = d[1] - 3
    if d[1] < 0 then d[1] = 0 end
  end
  P.blendPalettes(P.palettesMask(vm, true, true, true, true, true, false, false), d[1], 0x7FFF)
  if d[1] == 16 then
    d[2] = d[2] + 1
    local ptag = AnimPal.spriteTag(s, "LOCK_ON")
    local u = AnimPal.unfadedOf(ptag)
    if u then AnimPal.load(ptag, { [0] = u[8], [1] = u[9] }, 1, 2) end
    P.playSe(P.seId("SE_M_LEER"), P.adjustPanning(vm, P.SOUND_PAN_TARGET))
  elseif d[1] == 0 then
    s._cb = F.LockOnStep5
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4322
function F.LockOnStep3(s)
  local vm = s._vm
  local ap = s._affParam or 0
  if ap == 0 then
    s.data[0] = 3
    s.data[1] = 0
    s.data[2] = 0
    s._cb = S.waitAnimForDuration
    S.store(s, F.LockOnStep4)
  else
    local a, b
    if ap == 1 then a, b = -8, -8
    elseif ap == 2 then a, b = -8, 8
    elseif ap == 3 then a, b = 8, -8
    else a, b = 8, 8 end
    s.x = s.x + s.ox
    s.y = s.y + s.oy
    s.oy = 0
    s.ox = 0
    s.data[0] = 6
    s.data[2] = P.coord(vm, P.tgt(vm), P.X_2) + a
    s.data[4] = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + b
    s._cb = S.startLinear
    S.store(s, F.LockOnStep5)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4308
function F.LockOnStep2(s)
  if arshift(s.data[5], 8) == 4 then
    s.data[0] = 10
    s._cb = S.waitAnimForDuration
    S.store(s, F.LockOnStep3)
  else
    s._cb = F.LockOnStep1
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4281
function F.LockOnStep1(s)
  local d, vm = s.data, s._vm
  if band(d[5], 1) == 0 then
    d[0] = 1
    s._cb = S.waitAnimForDuration
    S.store(s, F.LockOnStep1)
  else
    s.x = s.x + s.ox
    s.y = s.y + s.oy
    s.oy = 0
    s.ox = 0
    d[0] = 8
    local row = INCLINE_MON_COORDS[arshift(d[5], 8)] or INCLINE_MON_COORDS[0]
    d[2] = s.x + row[1]
    d[4] = s.y + row[2]
    s._cb = S.startLinear
    S.store(s, F.LockOnStep2)
    d[5] = d[5] + 0x100
    P.playSe(P.seId("SE_M_LOCK_ON"), P.adjustPanning(vm, P.SOUND_PAN_TARGET))
  end
  d[5] = bxor(d[5], 1)
end

-- pokefirered/src/battle_anim_effects_1.c:4272
local function lock_on_target(s)
  s.x = s.x - 32
  s.y = s.y - 32
  s.data[0] = 20
  s._cb = S.waitAnimForDuration
  S.store(s, F.LockOnStep1)
end
C.LockOnTarget = S.wrap(lock_on_target)

-- pokefirered/src/battle_anim_effects_1.c:4419
C.LockOnMoveTarget = S.wrap(function(s)
  local ap = s._A[0]
  s._affParam = ap
  if ap == 1 then
    s.x = s.x - 0x18
    s.y = s.y - 0x18
  elseif ap == 2 then
    s.x = s.x - 0x18
    s.y = s.y + 0x18
    S.setOamFlip(s, false, true)
  elseif ap == 3 then
    s.x = s.x + 0x18
    s.y = s.y - 0x18
    S.setOamFlip(s, true, false)
  else
    s.x = s.x + 0x18
    s.y = s.y + 0x18
    S.setOamFlip(s, true, true)
  end
  s._tile = (s._tile or 0) + 16
  s._cb = lock_on_target
  s._cb(s)
end)

-- pokefirered/src/battle_anim_effects_1.c:4801
function F.FalseSwipeSliceStep3(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] > 1 then
    d[0] = 0
    s.visible = not s.visible
    d[1] = d[1] + 1
    if d[1] > 8 then S.destroy(s) end
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4794
function F.FalseSwipeSliceStep2(s)
  s.data[0] = 0
  s.data[1] = 0
  s._cb = F.FalseSwipeSliceStep3
end

-- pokefirered/src/battle_anim_effects_1.c:4782
function F.FalseSwipeSliceStep1(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] > 8 then
    d[0] = 12
    d[1] = 8
    d[2] = 0
    S.store(s, F.FalseSwipeSliceStep2)
    s._cb = S.translateSpriteLinear
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4745
C.SlashSlice = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local side = (A[0] == 0) and P.atk(vm) or P.tgt(vm)
  s.x = P.coord(vm, side, P.X_2) + A[1]
  s.y = P.coord(vm, side, P.Y_PIC_OFFSET) + A[2]
  s.data[0] = 0
  s.data[1] = 0
  S.store(s, F.FalseSwipeSliceStep3)
  s._cb = S.runStoredWhenAnimEnds
end)

-- pokefirered/src/battle_anim_effects_1.c:4764
C.FalseSwipeSlice = S.wrap(function(s)
  local vm = s._vm
  s.x = P.coord(vm, P.tgt(vm), P.X_2) - 48
  s.y = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
  S.store(s, F.FalseSwipeSliceStep1)
  s._cb = S.runStoredWhenAnimEnds
end)

-- pokefirered/src/battle_anim_effects_1.c:4772
C.FalseSwipePositionedSlice = S.wrap(function(s)
  local vm = s._vm
  s.x = P.coord(vm, P.tgt(vm), P.X_2) - 48 + s._A[0]
  s.y = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET)
  S.startAnim(s, 1)
  s.data[0] = 0
  s.data[1] = 0
  s._cb = F.FalseSwipeSliceStep3
end)

-- pokefirered/src/battle_anim_effects_1.c:4830
function F.EndureEnergyStep(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] > d[1] then
    d[0] = 0
    s.y = s.y - 1
  end
  s.y = s.y - d[0]
  if s.animEnded then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:4812
C.EndureEnergy = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local side = (A[0] == 0) and P.atk(vm) or P.tgt(vm)
  s.x = P.coord(vm, side, P.X) + A[1]
  s.y = P.coord(vm, side, P.Y) + A[2]
  s.data[0] = 0
  s.data[1] = A[3]
  s._cb = F.EndureEnergyStep
end)

-- pokefirered/src/battle_anim_effects_1.c:4856
function F.SharpenSphereStep(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] >= d[1] then
    s.visible = not s.visible
    if s.visible then
      d[4] = d[4] + 1
      if band(d[4], 1) == 0 then P.playSe(P.seId("SE_M_SWAGGER2"), d[5]) end
    end
    d[0] = 0
    d[2] = d[2] + 1
    if d[2] > 1 then
      d[2] = 0
      d[1] = d[1] + 1
    end
  end
  if s.animEnded and d[1] > 16 and not s.visible then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:4843
C.SharpenSphere = S.wrap(function(s)
  local vm = s._vm
  s.x = P.coord(vm, P.atk(vm), P.X_2)
  s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET) - 12
  s.data[0] = 0
  s.data[1] = 2
  s.data[2] = 0
  s.data[3] = 0
  s.data[4] = 0
  s.data[5] = P.adjustPanning(vm, P.SOUND_PAN_ATTACKER)
  s._cb = F.SharpenSphereStep
end)

-- pokefirered/src/battle_anim_effects_1.c:4880
C.Conversion = S.wrap(function(s)
  s._cb = function(sp)
    local vm = sp._vm
    if sp.data[0] == 0 then
      sp.x = P.coord(vm, P.atk(vm), P.X) + sp._A[0]
      sp.y = P.coord(vm, P.atk(vm), P.Y) + sp._A[1]
      sp.data[0] = sp.data[0] + 1
    end
    if vm and vm.args and u16(vm.args[7] or 0) == 0xFFFF then S.destroy(sp) end
  end
  s._cb(s)
end)

-- pokefirered/src/battle_anim_effects_1.c:4928
function F.Conversion2Step(s)
  local vm = s._vm
  if s.data[0] ~= 0 then
    s.data[0] = s.data[0] - 1
  else
    s.animPaused = false
    s.data[0] = 30
    s.data[2] = P.coord(vm, P.atk(vm), P.X_2)
    s.data[4] = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
    s._cb = S.startLinear
    S.store(s, S.destroy)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:4920
C.Conversion2 = S.wrap(function(s)
  S.initPosToTarget(s, false)
  s.animPaused = true
  s.data[0] = s._A[2]
  s._cb = F.Conversion2Step
end)

-- pokefirered/src/battle_anim_effects_1.c:4984
C.Moon = S.wrap(function(s)
  s.x = s._A[0]
  s.y = s._A[1]
  s._w, s._h = 64, 64
  s.data[0] = 0
  s._cb = function(sp)
    if sp.data[0] ~= 0 then S.destroy(sp) end
  end
end)

-- pokefirered/src/battle_anim_effects_1.c:5021
function F.MoonlightSparkleStep(s)
  local d = s.data
  d[1] = d[1] + 1
  if d[1] > 1 then
    d[1] = 0
    if d[2] < 120 then
      s.y = s.y + 1
      d[2] = d[2] + 1
    end
  end
  if d[0] ~= 0 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:5009
C.MoonlightSparkle = S.wrap(function(s)
  local vm = s._vm
  s.x = P.coord(vm, P.atk(vm), P.X_2) + s._A[0]
  s.y = s._A[1]
  for i = 0, 3 do s.data[i] = 0 end
  s.data[4] = 1
  s._cb = F.MoonlightSparkleStep
end)

-- pokefirered/src/battle_anim_effects_1.c:5193
function F.HornHitStep(s)
  local d = s.data
  d[2] = s16(d[2] + d[3])
  d[4] = s16(d[4] + d[5])
  s.x = arshift(d[2], 7)
  s.y = arshift(d[4], 7)
  d[1] = d[1] - 1
  if d[1] == 1 then
    s.x = d[6]
    s.y = d[7]
  end
  if d[1] == 0 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:5146
C.HornHit = S.wrap(function(s)
  local A, vm, d = s._A, s._vm, s.data
  if A[2] < 2 then A[2] = 2 end
  if A[2] > 0x7F then A[2] = 0x7F end
  d[0] = 0
  d[1] = A[2]
  s.x = P.coord(vm, P.tgt(vm), P.X_2) + A[0]
  s.y = P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET) + A[1]
  d[6] = s.x
  d[7] = s.y
  if not atk_opp(s) then
    s.x = s.x - 40
    s.y = s.y + 20
    d[2] = s16(lshift(s.x, 7))
    d[3] = cdiv(0x1400, d[1])
    d[4] = s16(lshift(s.y, 7))
    d[5] = cdiv(-0xA00, d[1])
  else
    s.x = s.x + 40
    s.y = s.y - 20
    d[2] = s16(lshift(s.x, 7))
    d[3] = cdiv(-0x1400, d[1])
    d[4] = s16(lshift(s.y, 7))
    d[5] = cdiv(0xA00, d[1])
    S.setOamFlip(s, true, true)
  end
  s._cb = F.HornHitStep
end)

-- pokefirered/src/battle_anim_effects_1.c:5283
C.SuperFang = S.wrap(function(s)
  S.store(s, S.destroy)
  s._cb = S.runStoredWhenAnimEnds
end)

-- pokefirered/src/battle_anim_effects_1.c:5365
local function wavy_velocity(x, y, f)
  if x < 0 then f = -f end
  local x2 = x * 256
  local time = cdiv(x2, f)
  if time == 0 then time = 1 end
  return s16(cdiv(x2, time)), s16(cdiv(y * 256, time))
end

local function palette_tag_loaded(tag)
  return AnimPal.isLoaded(tag)
end

-- pokefirered/src/battle_anim_effects_1.c:5381
function F.WavyMusicNotesStep(s)
  local d = s.data
  d[0] = d[0] + 1
  local trig = d[0] * 5 - lshift(cdiv(d[0] * 5, 256), 8)
  d[4] = s16(d[4] + d[6])
  d[5] = s16(d[5] + d[7])
  s.x = arshift(d[4], 4)
  s.y = arshift(d[5], 4)
  s.oy = Sin(trig, 15)
  local y = s.y
  if s.x < -16 or s.x > P.DISPLAY_WIDTH + 16 or y < -16 or y > P.DISPLAY_HEIGHT - 32 then
    S.destroy(s)
  elseif d[3] ~= 0 then
    d[2] = d[2] + 1
    if d[2] > d[3] then
      d[2] = 0
      d[1] = d[1] + 1
      if d[1] > 3 then d[1] = 0 end
      local tag = P.PARTICLES_COLOR_BLEND[d[1]][1]
      if palette_tag_loaded(tag) then s._palTag = tag end
    end
  end
end

-- pokefirered/src/battle_anim_effects_1.c:5336
C.WavyMusicNotes = S.wrap(function(s)
  local A, vm, d = s._A, s._vm, s.data
  S.setToAttackerCoords(s)
  S.startAnim(s, A[0])
  local row = P.PARTICLES_COLOR_BLEND[A[1]]
  if row and palette_tag_loaded(row[1]) then s._palTag = row[1] end
  d[1] = A[1]
  d[2] = 0
  d[3] = A[2]
  local x = u8(P.coord(vm, P.tgt(vm), P.X_2))
  local y = u8(P.coord(vm, P.tgt(vm), P.Y_PIC_OFFSET))
  d[4] = s16(lshift(s.x, 4))
  d[5] = s16(lshift(s.y, 4))
  d[6], d[7] = wavy_velocity(x - s.x, y - s.y, 40)
  s._cb = F.WavyMusicNotesStep
end)

-- pokefirered/src/battle_anim_effects_1.c:5431
function F.FlyingMusicNotesStep(s)
  local d = s.data
  d[4] = s16(d[4] + d[6])
  d[5] = s16(d[5] + d[7])
  s.x = arshift(d[4], 4)
  s.y = arshift(d[5], 4)
  if d[0] > 5 and d[3] == 0 then
    d[2] = band(d[2] + 16, 0xFF)
    s.ox = Cos(d[2], 18)
    s.oy = Sin(d[2], 18)
    if d[2] == 0 then d[3] = 1 end
  end
  d[0] = d[0] + 1
  if d[0] == 48 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:5414
C.FlyingMusicNotes = S.wrap(function(s)
  local A, vm, d = s._A, s._vm, s.data
  if atk_opp(s) then A[1] = -A[1] end
  s.x = P.coord(vm, P.atk(vm), P.X_2) + A[1]
  s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET) + A[2]
  S.startAnim(s, A[0])
  d[2] = 0
  d[3] = 0
  d[4] = s16(lshift(s.x, 4))
  d[5] = s16(lshift(s.y, 4))
  d[6] = cdiv(lshift(A[1], 4), 5)
  d[7] = cdiv(lshift(A[2], 7), 5)
  s._cb = F.FlyingMusicNotesStep
end)

-- pokefirered/src/battle_anim_effects_1.c:5450
C.BellyDrumHand = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local a
  if A[0] == 1 then
    S.setOamFlip(s, true, false)
    a = 16
  else
    a = -16
  end
  s.x = P.coord(vm, P.atk(vm), P.X_2) + a
  s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET) + 8
  s.data[0] = 8
  s._cb = S.waitAnimForDuration
  S.store(s, S.destroy)
end)

-- pokefirered/src/battle_anim_effects_1.c:5494
function F.SlowFlyingMusicNotesStep(s)
  local d = s.data
  if not S.translateLinear(s) then
    local xDiff = Sin(d[5], 8)
    if s.ox < 0 then xDiff = -xDiff end
    s.ox = s.ox + xDiff
    s.oy = s.oy + Sin(d[5], 4)
    d[5] = band(d[5] + 8, 0xFF)
  else
    S.destroy(s)
  end
end

-- pokefirered/src/battle_anim_effects_1.c:5471
C.SlowFlyingMusicNotes = S.wrap(function(s)
  local A, d = s._A, s.data
  S.setToAttackerCoords(s)
  s.y = s.y + 8
  S.startAnim(s, A[1])
  local row = P.PARTICLES_COLOR_BLEND[A[2]]
  if row and palette_tag_loaded(row[1]) then s._palTag = row[1] end
  local xDiff = (A[0] == 0) and -32 or 32
  d[0] = 40
  d[1] = s.x
  d[2] = xDiff + d[1]
  d[3] = s.y
  d[4] = d[3] - 40
  S.initLinear(s)
  d[5] = A[3]
  s._cb = F.SlowFlyingMusicNotesStep
end)

-- pokefirered/src/battle_anim_effects_1.c:5514
local function next_to_mon_head(s, side)
  local vm = s._vm
  if not P.isOpponent(side) then
    s.x = P.attr(vm, side, P.ATTR_RIGHT) + 8
  else
    s.x = P.attr(vm, side, P.ATTR_LEFT) - 8
  end
  s.y = P.coord(vm, side, P.Y_PIC_OFFSET) - cdiv(P.attr(vm, side, P.ATTR_HEIGHT), 4)
end
F.SetSpriteNextToMonHead = next_to_mon_head

-- pokefirered/src/battle_anim_effects_1.c:5543
function F.ThoughtBubbleStep(s)
  s.data[0] = s.data[0] - 1
  if s.data[0] == 0 then
    S.store(s, S.destroy)
    S.startAnim(s, s.data[1])
    s._cb = S.runStoredWhenAnimEnds
  end
end

-- pokefirered/src/battle_anim_effects_1.c:5524
C.ThoughtBubble = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local side = (A[0] == 0) and P.atk(vm) or P.tgt(vm)
  next_to_mon_head(s, side)
  local animNum = P.isOpponent(side) and 1 or 0
  s.data[0] = A[1]
  s.data[1] = animNum + 2
  S.startAnim(s, animNum)
  S.store(s, F.ThoughtBubbleStep)
  s._cb = S.runStoredWhenAnimEnds
end)

-- pokefirered/src/battle_anim_effects_1.c:5568
function F.MetronomeFingerStep(s)
  s.data[0] = s.data[0] + 1
  if s.data[0] > 16 then
    S.startAffineAnim(s, 1)
    S.store(s, S.destroy)
    s._cb = S.runStoredWhenAffineEnds
  end
end

-- pokefirered/src/battle_anim_effects_1.c:5553
C.MetronomeFinger = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local side = (A[0] == 0) and P.atk(vm) or P.tgt(vm)
  next_to_mon_head(s, side)
  s.data[0] = 0
  S.store(s, F.MetronomeFingerStep)
  s._cb = S.runStoredWhenAffineEnds
end)

-- pokefirered/src/battle_anim_effects_1.c:5607
function F.FollowMeFingerStep2(s)
  local d = s.data
  d[1] = d[1] + 4
  if d[1] > 254 then
    d[0] = d[0] - 1
    if d[0] == 0 then
      s.ox = 0
      s._cb = F.MetronomeFingerStep
      return
    else
      d[1] = band(d[1], 0xFF)
    end
  end
  if d[1] > 0x4F then s.subpriority = d[3] end
  if d[1] > 0x9F then s.subpriority = d[2] end
  local x1 = P.gSine(d[1])
  local x2 = arshift(x1, 3)
  s.ox = arshift(x1, 3) + arshift(x2, 1)
end

-- pokefirered/src/battle_anim_effects_1.c:5601
function F.FollowMeFingerStep1(s)
  s.data[4] = s.data[4] + 1
  if s.data[4] > 12 then s._cb = F.FollowMeFingerStep2 end
end

-- pokefirered/src/battle_anim_effects_1.c:5578
C.FollowMeFinger = S.wrap(function(s)
  local A, vm, d = s._A, s._vm, s.data
  local side = (A[0] == 0) and P.atk(vm) or P.tgt(vm)
  s.x = P.coord(vm, side, P.X)
  s.y = P.attr(vm, side, P.ATTR_TOP)
  if s.y <= 9 then s.y = 10 end
  d[0] = 1
  d[1] = 0
  d[2] = s.subpriority
  d[3] = s.subpriority + 4
  d[4] = 0
  S.store(s, F.FollowMeFingerStep1)
  s._cb = S.runStoredWhenAffineEnds
end)

-- pokefirered/src/battle_anim_effects_1.c:5672
function F.TauntFingerStep2(s)
  s.data[1] = s.data[1] + 1
  if s.data[1] > 5 then S.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_1.c:5661
function F.TauntFingerStep1(s)
  s.data[1] = s.data[1] + 1
  if s.data[1] > 10 then
    s.data[1] = 0
    S.startAnim(s, s.data[0])
    S.store(s, F.TauntFingerStep2)
    s._cb = S.runStoredWhenAnimEnds
  end
end

-- pokefirered/src/battle_anim_effects_1.c:5637
C.TauntFinger = S.wrap(function(s)
  local A, vm = s._A, s._vm
  local side = (A[0] == 0) and P.atk(vm) or P.tgt(vm)
  next_to_mon_head(s, side)
  if not P.isOpponent(side) then
    S.startAnim(s, 0)
    s.data[0] = 2
  else
    S.startAnim(s, 1)
    s.data[0] = 3
  end
  s._cb = F.TauntFingerStep1
end)

end
