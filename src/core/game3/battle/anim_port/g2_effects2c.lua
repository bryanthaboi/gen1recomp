local P = require("src.core.game3.battle.anim_port.g2_pret")

local CB = {}
local TASKS = {}

local band = bit.band

local function red_heart_projectile_step(s)
  if not P.AnimTranslateLinear(s) then
    s.y2 = s.y2 + P.Sin(s.data[5], 14)
    s.data[5] = (s.data[5] + 4) % 256
  else
    P.destroy(s)
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3191
function CB.RedHeartProjectile(s)
  P.InitSpritePosToAnimAttacker(s, true)
  s.data[0] = 95
  s.data[1] = s.x
  s.data[2] = P.coord(P.tgt(), 2)
  s.data[3] = s.y
  s.data[4] = P.coord(P.tgt(), 3)
  P.InitAnimLinearTranslation(s)
  s.pcb = red_heart_projectile_step
end

local function particle_burst(s)
  local d = s.data
  if d[0] == 0 then
    d[1] = P.arg(0)
    d[2] = P.arg(1)
    d[0] = d[0] + 1
  else
    d[4] = P.s16(d[4] + d[1])
    s.x2 = P.asr(d[4], 8)
    s.y2 = P.Sin(d[3], d[2])
    d[3] = (d[3] + 3) % 256
    if d[3] > 100 then s.invisible = (d[3] % 2) == 1 end
    if d[3] > 120 then P.destroy(s) end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3216
function CB.ParticleBurst(s)
  particle_burst(s)
  s.pcb = particle_burst
end

local function red_heart_rising_step(s)
  s.data[2] = P.s16(s.data[2] + s.data[1])
  s.y2 = -math.floor(P.u16(s.data[2]) / 256)
  s.x2 = P.Sin(s.data[3], 4)
  s.data[3] = (s.data[3] + 3) % 256
  local y = s.y + s.y2
  if y <= 72 then
    s.invisible = (s.data[3] % 2) == 1
    if y <= 64 then P.destroy(s) end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3238
function CB.RedHeartRising(s)
  s.x = P.arg(0)
  s.y = P.DISPLAY_HEIGHT
  s.data[0] = P.arg(2)
  s.data[1] = P.arg(1)
  s.pcb = P.WaitAnimForDuration
  P.storeCallback(s, red_heart_rising_step)
end

local AnimPal = require("src.core.game3.battle.anim_pal")

-- pokefirered/src/battle_anim_mons.c:926
local function bg1_draw(t)
  local g2 = t.g2
  if not g2 or not (love and love.graphics) then return end
  local eva = g2.eva or 0
  if eva <= 0 then return end
  AnimPal.drawBg(g2.key, "bg1", g2.x or 0, g2.y or 0, { eva = eva, evb = 16 - eva })
end

local function hearts_step(t)
  local d = t.data
  local g2 = t.g2
  if d[12] == 0 then
    d[10] = d[10] + 1
    if d[10] == 4 then
      d[10] = 0
      d[11] = d[11] + 1
      g2.eva = d[11]
      if d[11] == 16 then
        d[12] = d[12] + 1
        d[11] = 0
      end
    end
  elseif d[12] == 1 then
    d[11] = d[11] + 1
    if d[11] == 141 then
      d[11] = 16
      d[12] = d[12] + 1
    end
  elseif d[12] == 2 then
    d[10] = d[10] + 1
    if d[10] == 4 then
      d[10] = 0
      d[11] = d[11] - 1
      g2.eva = d[11]
      if d[11] == 0 then
        d[12] = d[12] + 1
        d[11] = 0
      end
    end
  elseif d[12] == 3 then
    g2.eva = 0
    t.draw = nil
    d[12] = d[12] + 1
  elseif d[12] == 4 then
    P.destroyTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3265
TASKS.HeartsBackground = P.task(function(t)
  t.g2.key = "ATTRACT"
  AnimPal.bgLoad("bg1", "ATTRACT")
  t.g2.eva = 0
  t.z = 2
  t.draw = bg1_draw
  t.func = hearts_step
end)

local function scary_step(t)
  local d = t.data
  local g2 = t.g2
  if d[12] == 0 then
    d[10] = d[10] + 1
    if d[10] == 2 then
      d[10] = 0
      d[11] = d[11] + 1
      g2.eva = d[11]
      if d[11] == 14 then
        d[12] = d[12] + 1
        d[11] = 0
      end
    end
  elseif d[12] == 1 then
    d[11] = d[11] + 1
    if d[11] == 21 then
      d[11] = 14
      d[12] = d[12] + 1
    end
  elseif d[12] == 2 then
    d[10] = d[10] + 1
    if d[10] == 2 then
      d[10] = 0
      d[11] = d[11] - 1
      g2.eva = d[11]
      if d[11] == 0 then
        d[12] = d[12] + 1
        d[11] = 0
      end
    end
  elseif d[12] == 3 then
    g2.eva = 0
    t.draw = nil
    d[12] = d[12] + 1
    P.destroyTask(t)
  elseif d[12] == 4 then
    P.destroyTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3346
TASKS.ScaryFace = P.task(function(t)
  if P.tgt() ~= "player" then
    t.g2.key = "SCARY_FACE_PLAYER"
  else
    t.g2.key = "SCARY_FACE_OPPONENT"
  end
  AnimPal.bgLoad("bg1", t.g2.key)
  t.g2.eva = 0
  t.z = 850
  t.draw = bg1_draw
  t.func = scary_step
end)

local function orbit_fast_step(s)
  local d = s.data
  if d[1] >= 64 and d[1] <= 191 then
    s.subpriority = d[7] + 1
  else
    s.subpriority = d[7] - 1
  end
  s.x2 = P.Sin(d[1], P.asr(d[2], 8))
  s.y2 = P.Cos(d[1], P.asr(d[3], 8))
  d[1] = (d[1] + 9) % 256
  if d[5] == 1 then
    d[2] = P.s16(d[2] - 0x400)
    d[3] = P.s16(d[3] - 0x100)
    d[4] = d[4] + 1
    if d[4] == d[0] then
      d[5] = 2
      return
    end
  elseif d[5] == 0 then
    d[2] = P.s16(d[2] + 0x400)
    d[3] = P.s16(d[3] + 0x100)
    d[4] = d[4] + 1
    if d[4] == d[0] then
      d[4] = 0
      d[5] = 1
    end
  end
  if P.u16(P.arg(7)) == 0xFFFF then P.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_2.c:3439
function CB.OrbitFast(s)
  local atk = P.atk()
  s.x = P.coord(atk, 2)
  s.y = P.coord(atk, 3)
  s.affineAnimPaused = true
  s.data[0] = P.arg(0)
  s.data[1] = P.arg(1)
  s.data[7] = P.subpriorityOf(atk)
  s.pcb = orbit_fast_step
  s.pcb(s)
end

local function orbit_scatter_step(s)
  s.x2 = s.x2 + s.data[0]
  s.y2 = s.y2 + s.data[1]
  if P.u16(s.x + s.x2 + 16) > P.DISPLAY_WIDTH + 32 or s.y + s.y2 > P.DISPLAY_HEIGHT or s.y + s.y2 < -16 then
    P.destroy(s)
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3490
function CB.OrbitScatter(s)
  local atk = P.atk()
  s.x = P.coord(atk, 2)
  s.y = P.coord(atk, 3)
  s.data[0] = P.Sin(P.arg(0), 10)
  s.data[1] = P.Cos(P.arg(0), 7)
  s.pcb = orbit_scatter_step
end

local function spit_up_step(s)
  s.x2 = s.x2 + s.data[0]
  s.y2 = s.y2 + s.data[1]
  local v = s.data[3]
  s.data[3] = v + 1
  if v >= s.data[2] then P.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_2.c:3516
function CB.SpitUpOrb(s)
  local atk = P.atk()
  s.x = P.coord(atk, 2)
  s.y = P.coord(atk, 3)
  s.data[0] = P.Sin(P.arg(0), 10)
  s.data[1] = P.Cos(P.arg(0), 7)
  s.data[2] = P.arg(1)
  s.pcb = spit_up_step
end

local function eye_sparkle_step(s)
  if s.animEnded then P.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_2.c:3532
function CB.EyeSparkle(s)
  P.InitSpritePosToAnimAttacker(s, true)
  s.pcb = eye_sparkle_step
end

local function angel(s)
  local d = s.data
  if d[0] == 0 then
    s.x = s.x + P.arg(0)
    s.y = s.y + P.arg(1)
  end
  d[0] = d[0] + 1
  local var0 = (d[0] * 10) % 256
  s.x2 = P.asr(P.Sin(var0, 80), 8)
  if d[0] < 80 then
    s.y2 = P.div(d[0], 2) + P.asr(P.Cos(var0, 80), 8)
  end
  if d[0] > 90 then
    d[2] = d[2] + 1
    s.x2 = s.x2 - P.div(d[2], 2)
  end
  if d[0] > 100 then P.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_2.c:3538
function CB.Angel(s)
  angel(s)
  s.pcb = angel
end

local function pink_heart_step(s)
  local d = s.data
  d[5] = d[5] + 1
  s.x2 = P.Sin(d[3], 5)
  s.y2 = P.div(d[5], 2)
  d[3] = (d[3] + 3) % 256
  if d[5] > 20 then s.invisible = (d[5] % 2) == 1 end
  if d[5] > 30 then P.destroy(s) end
end

local function pink_heart(s)
  local d = s.data
  if d[0] == 0 then
    d[1] = P.arg(0)
    d[2] = P.arg(1)
    d[0] = d[0] + 1
  else
    d[4] = P.s16(d[4] + d[1])
    s.x2 = P.asr(d[4], 8)
    s.y2 = P.Sin(d[3], d[2])
    d[3] = (d[3] + 3) % 256
    if d[3] > 70 then
      s.pcb = pink_heart_step
      s.x = s.x + s.x2
      s.y = s.y + s.y2
      s.x2 = 0
      s.y2 = 0
      d[3] = P.Random() % 180
    end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3577
function CB.PinkHeart(s)
  s.pcb = pink_heart
  pink_heart(s)
end

local function devil(s)
  local d = s.data
  if d[3] == 0 then
    s.x = s.x + P.arg(0)
    s.y = s.y + P.arg(1)
    P.startAnim(s, 0)
    s.subpriority = P.subpriorityOf(P.tgt()) - 1
    d[2] = 1
  end
  d[0] = d[0] + d[2]
  d[1] = P.mod(d[0] * 4, 256)
  if d[1] < 0 then d[1] = 0 end
  s.x2 = P.Cos(d[1], 30 - P.div(d[0], 4))
  s.y2 = P.Sin(d[1], 10 - P.div(d[0], 8))
  if d[1] > 128 and d[2] > 0 then d[2] = -1 end
  if d[1] == 0 and d[2] < 0 then d[2] = 1 end
  d[3] = d[3] + 1
  if d[3] < 10 or d[3] > 80 then
    s.invisible = (P.mod(d[0], 2) ~= 0)
  else
    s.invisible = false
  end
  if d[3] > 90 then P.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_2.c:3603
function CB.Devil(s)
  devil(s)
  s.pcb = devil
end

local function fury_swipes(s)
  if s.data[0] == 0 then
    s.x = s.x + P.arg(0)
    s.y = s.y + P.arg(1)
    P.startAnim(s, P.arg(2))
    s.data[0] = s.data[0] + 1
  elseif s.animEnded then
    P.destroy(s)
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3632
function CB.FurySwipes(s)
  fury_swipes(s)
  s.pcb = fury_swipes
end

local function movement_waves_step(s)
  if s.animEnded then
    s.data[0] = s.data[0] - 1
    if s.data[0] ~= 0 then
      P.startAnim(s, s.data[1])
    else
      P.destroy(s)
    end
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3647
function CB.MovementWaves(s)
  if P.arg(2) == 0 then
    P.destroy(s)
    return
  end
  local b = (P.arg(0) == 0) and P.atk() or P.tgt()
  s.x = P.coord(b, 2)
  s.y = P.coord(b, 3)
  if P.arg(1) == 0 then s.x = s.x + 32 else s.x = s.x - 32 end
  s.data[0] = P.arg(2)
  s.data[1] = P.arg(1)
  P.startAnim(s, s.data[1])
  s.pcb = movement_waves_step
end

local function affine_until_done(t)
  if not P.RunAffineAnimFromTaskData(t) then P.destroyTask(t) end
end

-- pokefirered/src/battle_anim_effects_2.c:3689
TASKS.UproarDistortion = P.task(function(t)
  local m = P.monById(P.arg(0))
  if not m then return P.destroyTask(t) end
  P.PrepareAffineAnimInTaskData(t, m, P.affineCmds("sUproarAffineAnimCmds"))
  t.func = affine_until_done
end)

local function jagged_step(s)
  s.data[1] = P.s16(s.data[1] + s.data[3])
  s.data[2] = P.s16(s.data[2] + s.data[4])
  s.x = P.asr(s.data[1], 3)
  s.y = P.asr(s.data[2], 3)
  s.data[0] = s.data[0] + 1
  if s.data[0] > 16 then P.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_2.c:3703
function CB.JaggedMusicNote(s)
  local b = (P.arg(0) == 0) and P.atk() or P.tgt()
  if b ~= "player" then P.setArg(1, -P.arg(1)) end
  s.x = P.coord(b, 2) + P.arg(1)
  s.y = P.coord(b, 3) + P.arg(2)
  s.data[0] = 0
  s.data[1] = P.s16(P.u16(s.x) * 8)
  s.data[2] = P.s16(P.u16(s.y) * 8)
  local var1 = P.arg(1) * 8
  if var1 < 0 then var1 = var1 + 7 end
  s.data[3] = P.asr(var1, 3)
  var1 = P.arg(2) * 8
  if var1 < 0 then var1 = var1 + 7 end
  s.data[4] = P.asr(var1, 3)
  s.tileBase = s.tileBase + P.arg(3) * 16
  s.pcb = jagged_step
end

local function perish_note2(s)
  local d = s.data
  if d[0] == 0 then
    d[1] = 120 - P.arg(0)
    s.invisible = true
  end
  d[0] = d[0] + 1
  if d[0] == d[1] then
    local AnimPal = require("src.core.game3.battle.anim_pal")
    AnimPal.greyscale(AnimPal.spriteTag(s, "MUSIC_NOTES_2"), false)
  end
  if d[0] == d[1] + 80 then P.destroy(s) end
end

-- pokefirered/src/battle_anim_effects_2.c:3741
function CB.PerishSongMusicNote2(s)
  perish_note2(s)
  s.pcb = perish_note2
end

local function perish_note_step2(s)
  local d = s.data
  d[3] = d[3] + d[2]
  s.y2 = d[3]
  d[2] = d[2] + 1
  if d[3] > 48 and d[2] > 0 then
    d[2] = d[4] - 5
    d[4] = d[4] + 1
  end
  if d[4] > 3 then
    s.invisible = (P.mod(d[2], 2) ~= 0)
    P.destroy(s)
    return
  end
  if d[4] == 4 then P.destroy(s) end
end

local function perish_note_step1(s)
  s.data[0] = s.data[0] + 1
  if s.data[0] > 10 then
    s.data[0] = 0
    s.pcb = perish_note_step2
  end
end

local function perish_note(s)
  local d = s.data
  if d[0] == 0 then
    s.x = 120
    s.y = P.div(P.arg(0), 2) - 15
    P.startAnim(s, P.arg(1))
    d[5] = 120
    d[3] = P.arg(2)
  end
  d[0] = d[0] + 1
  d[1] = P.div(d[0], 2)
  local index = d[0] * 3 + P.u16(d[3])
  d[6] = (d[6] + 10) % 256
  index = band(index, 0xFF)
  s.x2 = P.Cos(index, 100)
  s.y2 = d[1] + P.Sin(index, 10) + P.Cos(d[6], 4)
  if d[0] > d[5] then
    s.pcb = perish_note_step1
    d[0] = 0
    s.x = s.x + s.x2
    s.y = s.y + s.y2
    s.x2 = 0
    s.y2 = 0
    d[2] = 5
    d[4] = 0
    d[3] = 0
    P.startAffineAnim(s, 1)
  end
end

-- pokefirered/src/battle_anim_effects_2.c:3756
function CB.PerishSongMusicNote(s)
  perish_note(s)
  if s.pcb ~= perish_note_step1 then s.pcb = perish_note end
end

-- pokefirered/src/battle_anim_effects_2.c:3832
function CB.GuardRing(s)
  s.x = P.coord(P.atk(), 0)
  s.y = P.coord(P.atk(), 1) + 40
  s.data[0] = 13
  s.data[2] = s.x
  s.data[4] = s.y - 72
  s.pcb = P.StartAnimLinearTranslation
  P.storeCallback(s, P.DestroyAnimSprite)
end

local function fury_counter()
  local vm = P.vm
  local ctx = vm and vm.ctx
  return tonumber(ctx and (ctx.furyCutterCounter or ctx.furyCutter)) or 0
end

-- pokefirered/src/battle_anim_effects_2.c:3855
TASKS.IsFuryCutterHitRight = P.task(function(t)
  P.setArg(7, band(fury_counter(), 1))
  P.destroyTask(t)
end)

-- pokefirered/src/battle_anim_effects_2.c:3861
TASKS.GetFuryCutterHitCount = P.task(function(t)
  P.setArg(7, fury_counter())
  P.destroyTask(t)
end)

return { cb = CB, tasks = TASKS }
