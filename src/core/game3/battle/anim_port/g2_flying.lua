local P = require("src.core.game3.battle.anim_port.g2_pret")

local CB = {}
local TASKS = {}

local band = bit.band

local function elliptical_gust_step(s)
  s.x2 = P.Sin(s.data[1], 32)
  s.y2 = P.Cos(s.data[1], 8)
  s.data[1] = (s.data[1] + 5) % 256
  s.data[0] = s.data[0] + 1
  if s.data[0] == 71 then P.destroy(s) end
end

-- pokefirered/src/battle_anim_flying.c:360
function CB.EllipticalGust(s)
  P.InitSpritePosToAnimTarget(s, false)
  s.y = s.y + 20
  s.data[1] = 191
  s.pcb = elliptical_gust_step
  s.pcb(s)
end

local function gust_palette_step(t)
  local d = t.data
  local old = d[10]
  d[10] = d[10] + 1
  if old == d[1] then
    d[10] = 0
    local f = require("src.core.game3.battle.anim_pal").writeFaded("GUST")
    if f then
      local temp = f[8]
      for i = 7, 1, -1 do f[i + 1] = f[i] end
      f[1] = temp
    end
  end
  d[0] = d[0] - 1
  if d[0] == 0 then P.destroyTask(t) end
end

-- pokefirered/src/battle_anim_flying.c:380
TASKS.AnimateGustTornadoPalette = P.task(function(t)
  t.data[0] = P.arg(1)
  t.data[1] = P.arg(0)
  t.func = gust_palette_step
end)

local function gust_to_target_step(s)
  if P.AnimTranslateLinear(s) then P.destroy(s) end
end

-- pokefirered/src/battle_anim_flying.c:412
function CB.GustToTarget(s)
  P.InitSpritePosToAnimAttacker(s, true)
  if P.atk() ~= "player" then P.setArg(2, -P.arg(2)) end
  s.data[0] = P.arg(4)
  s.data[1] = s.x
  s.data[2] = P.coord(P.tgt(), 2) + P.arg(2)
  s.data[3] = s.y
  s.data[4] = P.coord(P.tgt(), 3) + P.arg(3)
  P.InitAnimLinearTranslation(s)
  s.pcb = P.RunStoredCallbackWhenAffineAnimEnds
  P.storeCallback(s, gust_to_target_step)
end

-- pokefirered/src/battle_anim_flying.c:433
function CB.AirWaveCrescent(s)
  if P.atk() ~= "player" then
    for i = 0, 3 do P.setArg(i, -P.arg(i)) end
  end
  local atk = P.atk()
  s.x = P.coord(atk, 2)
  s.y = P.coord(atk, 3)
  s.x = s.x + P.arg(0)
  s.y = s.y + P.arg(1)
  s.data[0] = P.arg(4)
  if P.arg(6) == 0 then
    s.data[2] = P.coord(P.tgt(), 2)
    s.data[4] = P.coord(P.tgt(), 3)
  else
    s.data[2], s.data[4] = P.SetAverageBattlerPositions(P.tgt(), true)
  end
  s.data[2] = s.data[2] + P.arg(2)
  s.data[4] = s.data[4] + P.arg(3)
  s.pcb = P.StartAnimLinearTranslation
  P.storeCallback(s, P.DestroyAnimSprite)
  P.seekAnim(s, P.arg(5))
end

local function fly_ball_up_step(s)
  if s.data[0] > 0 then
    s.data[0] = s.data[0] - 1
  else
    s.data[2] = P.s16(s.data[2] + s.data[1])
    s.y2 = s.y2 - P.asr(s.data[2], 8)
  end
  if s.y + s.y2 < -32 then P.destroy(s) end
end

-- pokefirered/src/battle_anim_flying.c:468
function CB.FlyBallUp(s)
  P.InitSpritePosToAnimAttacker(s, true)
  s.data[0] = P.arg(2)
  s.data[1] = P.arg(3)
  s.pcb = fly_ball_up_step
  local m = P.monById(P.ANIM_ATTACKER)
  if m then m.invisible = true end
end

local function fly_ball_attack_step(s)
  s.data[0] = 1
  P.AnimTranslateLinear(s)
  if math.floor(P.u16(s.data[3]) / 256) > 200 then
    s.x = s.x + s.x2
    s.x2 = 0
    s.data[3] = s.data[3] % 256
  end
  if s.x + s.x2 < -32 or s.x + s.x2 > P.DISPLAY_WIDTH + 32 or s.y + s.y2 > P.DISPLAY_HEIGHT then
    local m = P.monById(P.ANIM_ATTACKER)
    if m then m.invisible = false end
    P.destroy(s)
  end
end

-- pokefirered/src/battle_anim_flying.c:492
function CB.FlyBallAttack(s)
  if P.atk() ~= "player" then
    s.x = P.DISPLAY_WIDTH + 32
    s.y = -32
    P.startAffineAnim(s, 1)
  else
    s.x = -32
    s.y = -32
  end
  s.data[0] = P.arg(0)
  s.data[1] = s.x
  s.data[2] = P.coord(P.tgt(), 2)
  s.data[3] = s.y
  s.data[4] = P.coord(P.tgt(), 3)
  P.InitAnimLinearTranslation(s)
  s.pcb = fly_ball_attack_step
end

-- pokefirered/src/battle_anim_flying.c:533
local function destroy_after_timer(s)
  local v = s.data[0]
  s.data[0] = v - 1
  if v <= 0 then P.destroy(s) end
end

local function feather_matrix(s, f)
  local sinIndex = P.u8(P.asr(-s.x2, 1) + f.unkA)
  local sinVal = P.sine(sinIndex)
  local c = P.sine(sinIndex + 64)
  P.setMatrix(s, c, sinVal, -sinVal, c)
end

local function feather_flip(s, f)
  s.pHFlip = not s.pHFlip
  P.startAnim(s, s.pHFlip and 1 or 0)
  if f.unk0_0c ~= 0 then
    if f.unkE_0 == 0 then
      s.oamPriority = s.oamPriority - 1
    else
      s.oamPriority = s.oamPriority + 1
    end
    f.unkE_0 = 1 - f.unkE_0
  end
  f.unk0_0d = 0
end

local function falling_feather_step(s)
  local f = s.g2.f
  if f.unk0_0a ~= 0 then
    local old = f.unk1
    f.unk1 = (old - 1) % 256
    if old % 256 == 0 then
      f.unk0_0a = 0
      f.unk1 = 0
    end
    return
  end
  local q = math.floor(f.unk2 / 64)
  local u = f.unk0_1 % 256
  if q == 0 then
    if u == 1 then
      f.unk0_0d = 1; f.unk0_0a = 1; f.unk1 = 0
    elseif u == 3 then
      f.unk0_0b = 1 - f.unk0_0b; f.unk0_0a = 1; f.unk1 = 0
    elseif f.unk0_0d ~= 0 then
      feather_flip(s, f)
    end
    f.unk0_1 = 0
  elseif q == 1 then
    if u == 0 then
      f.unk0_0d = 1; f.unk0_0a = 1; f.unk1 = 0
    elseif u == 2 then
      f.unk0_0a = 1; f.unk1 = 0
    elseif f.unk0_0d ~= 0 then
      feather_flip(s, f)
    end
    f.unk0_1 = 1
  elseif q == 2 then
    if u == 3 then
      f.unk0_0d = 1; f.unk0_0a = 1; f.unk1 = 0
    elseif u == 1 then
      f.unk0_0a = 1; f.unk1 = 0
    elseif f.unk0_0d ~= 0 then
      feather_flip(s, f)
    end
    f.unk0_1 = 2
  elseif q == 3 then
    if u == 2 then
      f.unk0_0d = 1
    elseif u == 0 then
      f.unk0_0b = 1 - f.unk0_0b; f.unk0_0a = 1; f.unk1 = 0
    elseif f.unk0_0d ~= 0 then
      feather_flip(s, f)
    end
    f.unk0_1 = 3
  end
  s.x2 = P.asr(f.unkC[f.unk0_0b] * P.sine(f.unk2), 8)
  feather_matrix(s, f)
  f.unk8 = P.u16(f.unk8 + f.unk6)
  s.y = math.floor(f.unk8 / 256)
  if band(f.unk4, 0x8000) ~= 0 then
    f.unk2 = (f.unk2 - band(f.unk4, 0x7FFF)) % 256
  else
    f.unk2 = (f.unk2 + band(f.unk4, 0x7FFF)) % 256
  end
  if s.y + s.y2 >= f.unkE_1 then
    s.data[0] = 0
    s.pcb = destroy_after_timer
  end
end

-- pokefirered/src/battle_anim_flying.c:565
function CB.FallingFeather(s)
  local b
  if band(P.arg(7), 0x100) ~= 0 then b = P.atk() else b = P.tgt() end
  if b == "player" then P.setArg(0, -P.arg(0)) end
  s.x = P.coord(b, 0) + P.arg(0)
  local spriteCoord = P.coord(b, 1)
  s.y = spriteCoord + P.arg(1)
  local f = {
    unk0_0a = 0, unk0_0b = 0, unk0_0c = 1, unk0_0d = 0, unk0_1 = 0, unk1 = 0,
    unk8 = P.u16(s.y * 256),
    unkE_1 = band(spriteCoord + P.arg(6), 0x7FFF),
    unk2 = band(P.arg(2), 0xFF),
    unkA = band(P.asr(P.arg(2), 8), 0xFF),
    unk4 = P.u16(P.arg(3)),
    unk6 = P.u16(P.arg(4)),
    unkC = { [0] = band(P.arg(5), 0xFF), [1] = band(P.asr(P.arg(5), 8), 0xFF) },
    unkE_0 = 0,
  }
  s.g2.f = f
  if f.unk2 >= 64 and f.unk2 <= 191 then
    s.oamPriority = P.bgPriority(b) + 1
    f.unkE_0 = 0
    if band(f.unk4, 0x8000) == 0 then
      s.pHFlip = not s.pHFlip
      P.startAnim(s, s.pHFlip and 1 or 0)
    end
  else
    s.oamPriority = P.bgPriority(b)
    f.unkE_0 = 1
    if band(f.unk4, 0x8000) ~= 0 then
      s.pHFlip = not s.pHFlip
      P.startAnim(s, s.pHFlip and 1 or 0)
    end
  end
  f.unk0_1 = math.floor(f.unk2 / 64)
  s.x2 = P.asr(P.sine(f.unk2) * f.unkC[0], 8)
  feather_matrix(s, f)
  s.pcb = falling_feather_step
end

local function whirlwind_line_step(s)
  s.x2 = s.x2 + P.asr(s.data[1], 8)
  s.data[0] = s.data[0] + 1
  if s.data[0] == 6 then
    s.data[0] = 0
    s.x2 = 0
    P.startAnim(s, 0)
  end
  s.data[7] = s.data[7] - 1
  if s.data[7] == -1 then P.destroy(s) end
end

-- pokefirered/src/battle_anim_flying.c:988
function CB.WhirlwindLine(s)
  if P.arg(2) == P.ANIM_ATTACKER then
    P.InitSpritePosToAnimAttacker(s, false)
  else
    P.InitSpritePosToAnimTarget(s, false)
  end
  if (P.arg(2) == P.ANIM_ATTACKER and P.atk() == "player") or (P.arg(2) == P.ANIM_TARGET and P.tgt() == "player") then
    s.x = s.x + 8
  end
  P.seekAnim(s, P.arg(4))
  s.x = s.x - 32
  s.data[1] = 0x0ccc
  local arg = P.u16(P.arg(4))
  s.x2 = s.x2 + 12 * arg
  s.data[0] = P.s16(arg)
  s.data[7] = P.arg(3)
  s.pcb = whirlwind_line_step
end

local function drill_peck_step(t)
  if t.data[0] % 32 == 0 then
    P.setArg(0, P.Sin(t.data[0], -13))
    P.setArg(1, P.Cos(t.data[0], -13))
    P.setArg(2, 1)
    P.setArg(3, 3)
    local tb = P.tgt()
    P.createSprite("gFlashingHitSplatSpriteTemplate", P.coord(tb, 2), P.coord(tb, 3), 3, true, true)
  end
  t.data[0] = t.data[0] + 8
  if t.data[0] > 255 then P.destroyTask(t) end
end

-- pokefirered/src/battle_anim_flying.c:1025
TASKS.DrillPeckHitSplats = P.task(function(t, vm)
  t.func = drill_peck_step
  drill_peck_step(t)
end)

local function bounce_ball_shrink(s)
  if s.data[0] == 0 then
    P.InitSpritePosToAnimAttacker(s, true)
    local m = P.monById(P.ANIM_ATTACKER)
    if m then m.invisible = true end
    s.data[0] = s.data[0] + 1
  elseif s.data[0] == 1 then
    if s.affineAnimEnded then P.destroy(s) end
  end
end

-- pokefirered/src/battle_anim_flying.c:1044
function CB.BounceBallShrink(s)
  bounce_ball_shrink(s)
  s.pcb = bounce_ball_shrink
end

local function bounce_ball_land(s)
  if s.data[0] == 0 then
    s.y = P.coord(P.tgt(), 1)
    s.y2 = -s.y - 32
    s.data[0] = s.data[0] + 1
  elseif s.data[0] == 1 then
    s.y2 = s.y2 + 10
    if s.y2 >= 0 then s.data[0] = s.data[0] + 1 end
  elseif s.data[0] == 2 then
    s.y2 = s.y2 - 10
    if s.y + s.y2 < -32 then
      local m = P.monById(P.ANIM_ATTACKER)
      if m then m.invisible = false end
      P.destroy(s)
    end
  end
end

-- pokefirered/src/battle_anim_flying.c:1060
function CB.BounceBallLand(s)
  bounce_ball_land(s)
  s.pcb = bounce_ball_land
end

local function dive_ball_step2(s)
  s.y2 = s.y2 + P.asr(s.data[2], 8)
  if s.y + s.y2 > -32 then s.invisible = false end
  if s.y2 > 0 then P.destroy(s) end
end

local function dive_ball_step1(s)
  if s.data[0] > 0 then
    s.data[0] = s.data[0] - 1
  elseif s.y + s.y2 > -32 then
    s.data[2] = P.s16(s.data[2] + s.data[1])
    s.y2 = s.y2 - P.asr(s.data[2], 8)
  else
    s.invisible = true
    local v = s.data[3]
    s.data[3] = v + 1
    if v > 20 then s.pcb = dive_ball_step2 end
  end
end

-- pokefirered/src/battle_anim_flying.c:1085
function CB.DiveBall(s)
  P.InitSpritePosToAnimAttacker(s, true)
  s.data[0] = P.arg(2)
  s.data[1] = P.arg(3)
  s.pcb = dive_ball_step1
  local m = P.monById(P.ANIM_ATTACKER)
  if m then m.invisible = true end
end

local function dive_water_splash(s)
  if s.data[0] == 0 then
    local b = (P.arg(0) == 0) and P.atk() or P.tgt()
    s.x = P.coord(b, 0)
    s.y = P.coord(b, 1)
    s.data[1] = 512
    P.trySetRotScale(s, false, 256, s.data[1], 0)
    s.data[0] = s.data[0] + 1
  elseif s.data[0] == 1 then
    if s.data[2] <= 11 then
      s.data[1] = s.data[1] - 40
    else
      s.data[1] = s.data[1] + 40
    end
    s.data[2] = s.data[2] + 1
    P.trySetRotScale(s, false, 256, s.data[1], 0)
    local t2 = P.div(15616, s.matD) + 1
    if t2 > 128 then t2 = 128 end
    t2 = P.div(64 - t2, 2)
    s.y2 = t2
    if s.data[2] == 24 then
      P.tryResetAffine(s)
      P.destroy(s)
    end
  end
end

-- pokefirered/src/battle_anim_flying.c:1122
function CB.DiveWaterSplash(s)
  dive_water_splash(s)
  s.pcb = dive_water_splash
end

local function spray_droplet_step(s)
  if s.data[2] == 0 then
    s.x2 = s.x2 + P.asr(s.data[0], 8)
    s.y2 = s.y2 - P.asr(s.data[1], 8)
  else
    s.x2 = s.x2 - P.asr(s.data[0], 8)
    s.y2 = s.y2 - P.asr(s.data[1], 8)
  end
  s.data[1] = s.data[1] - 32
  if s.data[0] < 0 then s.data[0] = 0 end
  s.data[3] = s.data[3] + 1
  if s.data[3] == 31 then P.destroy(s) end
end

-- pokefirered/src/battle_anim_flying.c:1168
function CB.SprayWaterDroplet(s)
  local v1 = band(0x1FF, P.Random())
  local v2 = band(0x7F, P.Random())
  if v1 % 2 == 1 then s.data[0] = 736 + v1 else s.data[0] = 736 - v1 end
  if v2 % 2 == 1 then s.data[1] = 896 + v2 else s.data[1] = 896 - v2 end
  s.data[2] = P.arg(0)
  if s.data[2] ~= 0 then
    s.pHFlip = true
    s.pVFlip = false
  end
  local b = (P.arg(1) == 0) and P.atk() or P.tgt()
  s.x = P.coord(b, 0)
  s.y = P.coord(b, 1) + 32
  s.pcb = spray_droplet_step
end

local function sky_attack_bird_step(s)
  s.data[4] = P.s16(s.data[4] + s.data[6])
  s.data[5] = P.s16(s.data[5] + s.data[7])
  s.x = P.asr(s.data[4], 4)
  s.y = P.asr(s.data[5], 4)
  if s.x > P.DISPLAY_WIDTH + 45 or s.x < -45 or s.y > 157 or s.y < -45 then
    P.destroy(s)
  end
end

-- pokefirered/src/battle_anim_flying.c:1244
function CB.SkyAttackBird(s)
  local posx, posy = s.x, s.y
  local atk = P.atk()
  s.x = P.coord(atk, 2)
  s.y = P.coord(atk, 3)
  s.data[4] = P.s16(s.x * 16)
  s.data[5] = P.s16(s.y * 16)
  s.data[6] = P.div((posx - s.x) * 16, 12)
  s.data[7] = P.div((posy - s.y) * 16, 12)
  local rotation = P.ArcTan2Neg(posx - s.x, posy - s.y)
  rotation = P.u16(rotation + 49152)
  P.trySetRotScale(s, true, 0x100, 0x100, rotation)
  s.pcb = sky_attack_bird_step
end

return { cb = CB, tasks = TASKS }
