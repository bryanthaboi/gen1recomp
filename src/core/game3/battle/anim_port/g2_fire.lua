local P = require("src.core.game3.battle.anim_port.g2_pret")

local CB = {}
local TASKS = {}

-- pokefirered/src/battle_anim_fire.c:462
function CB.FireSpiralInward(s)
  s.data[0] = P.arg(0)
  s.data[1] = 0x3C
  s.data[2] = 0x9
  s.data[3] = 0x1E
  s.data[4] = P.s16(0xFE00)
  P.storeCallback(s, P.DestroyAnimSprite)
  s.pcb = P.TranslateSpriteInGrowingCircle
  s.pcb(s)
end

-- pokefirered/src/battle_anim_fire.c:475
function CB.FireSpread(s)
  P.SetAnimSpriteInitialXOffset(s, P.arg(0))
  s.y = s.y + P.arg(1)
  s.data[0] = P.arg(4)
  s.data[1] = P.arg(2)
  s.data[2] = P.arg(3)
  s.pcb = P.TranslateSpriteLinearFixedPoint
  P.storeCallback(s, P.DestroyAnimSprite)
end

local function large_flame_step(s)
  s.data[0] = s.data[0] + 1
  if s.data[0] < s.data[4] then
    s.x2 = s.x2 + s.data[2]
    s.y2 = s.y2 + s.data[3]
  end
  if s.data[0] == s.data[1] then P.destroy(s) end
end

-- pokefirered/src/battle_anim_fire.c:486
function CB.FirePlume(s)
  P.SetSpriteCoordsToAnimAttackerCoords(s)
  if P.atk() ~= "player" then
    s.x = s.x - P.arg(0)
    s.y = s.y + P.arg(1)
    s.data[2] = -P.arg(4)
  else
    s.x = s.x + P.arg(0)
    s.y = s.y + P.arg(1)
    s.data[2] = P.arg(4)
  end
  s.data[1] = P.arg(2)
  s.data[4] = P.arg(3)
  s.data[3] = P.arg(5)
  s.pcb = large_flame_step
end

-- pokefirered/src/battle_anim_fire.c:507
function CB.LargeFlame(s)
  if P.atk() ~= "player" then
    s.x = s.x - P.arg(0)
    s.y = s.y + P.arg(1)
    s.data[2] = P.arg(4)
  else
    s.x = s.x + P.arg(0)
    s.y = s.y + P.arg(1)
    s.data[2] = -P.arg(4)
  end
  s.data[1] = P.arg(2)
  s.data[4] = P.arg(3)
  s.data[3] = P.arg(5)
  s.pcb = large_flame_step
end

-- pokefirered/src/battle_anim_fire.c:583
function CB.Sunlight(s)
  s.x = 0
  s.y = 0
  s.data[0] = 60
  s.data[2] = 140
  s.data[4] = 80
  s.pcb = P.StartAnimLinearTranslation
  P.storeCallback(s, P.DestroyAnimSprite)
end

-- pokefirered/src/battle_anim_fire.c:603
function CB.EmberFlare(s)
  s.pcb = P.AnimTravelDiagonally
  s.pcb(s)
end

-- pokefirered/src/battle_anim_fire.c:613
function CB.BurnFlame(s)
  P.setArg(0, -P.arg(0))
  P.setArg(2, -P.arg(2))
  s.pcb = P.AnimTravelDiagonally
end

local function fire_ring_offset(s)
  s.x2 = P.Sin(s.data[7], 28)
  s.y2 = P.Cos(s.data[7], 28)
  s.data[7] = (s.data[7] + 20) % 256
end

local function fire_ring_step3(s)
  fire_ring_offset(s)
  s.data[0] = s.data[0] + 1
  if s.data[0] == 0x1F then P.destroy(s) end
end

local function fire_ring_step2(s)
  if P.AnimTranslateLinear(s) then
    s.data[0] = 0
    s.x = P.coord(P.tgt(), 2)
    s.y = P.coord(P.tgt(), 3)
    s.x2 = 0
    s.y2 = 0
    s.pcb = fire_ring_step3
    s.pcb(s)
  else
    s.x2 = s.x2 + P.Sin(s.data[7], 28)
    s.y2 = s.y2 + P.Cos(s.data[7], 28)
    s.data[7] = (s.data[7] + 20) % 256
  end
end

local function fire_ring_step1(s)
  fire_ring_offset(s)
  s.data[0] = s.data[0] + 1
  if s.data[0] == 0x12 then
    s.data[0] = 0x19
    s.data[1] = s.x
    s.data[2] = P.coord(P.tgt(), 2)
    s.data[3] = s.y
    s.data[4] = P.coord(P.tgt(), 3)
    P.InitAnimLinearTranslation(s)
    s.pcb = fire_ring_step2
  end
end

-- pokefirered/src/battle_anim_fire.c:628
function CB.FireRing(s)
  P.InitSpritePosToAnimAttacker(s, true)
  s.data[7] = P.arg(2)
  s.data[0] = 0
  s.pcb = fire_ring_step1
end

-- pokefirered/src/battle_anim_fire.c:692
function CB.FireCross(s)
  s.x = s.x + P.arg(0)
  s.y = s.y + P.arg(1)
  s.data[0] = P.arg(2)
  s.data[1] = P.arg(3)
  s.data[2] = P.arg(4)
  P.storeCallback(s, P.DestroyAnimSprite)
  s.pcb = P.TranslateSpriteLinear
end

local function spiral_out_step2(s)
  s.x2 = P.Sin(s.data[1], P.asr(s.data[2], 8))
  s.y2 = P.Cos(s.data[1], P.asr(s.data[2], 8))
  s.data[1] = (s.data[1] + 10) % 256
  s.data[2] = P.s16(s.data[2] + 0xD0)
  s.data[0] = s.data[0] - 1
  if s.data[0] == -1 then P.destroy(s) end
end

local function spiral_out_step1(s)
  s.invisible = false
  s.data[0] = s.data[1]
  s.data[1] = 0
  s.pcb = spiral_out_step2
  s.pcb(s)
end

-- pokefirered/src/battle_anim_fire.c:703
function CB.FireSpiralOutward(s)
  P.InitSpritePosToAnimAttacker(s, true)
  s.data[1] = P.arg(2)
  s.data[0] = P.arg(3)
  s.invisible = true
  s.pcb = P.WaitAnimForDuration
  P.storeCallback(s, spiral_out_step1)
end

local ROCK_SPEEDS = { { -2, -5 }, { -1, -1 }, { 3, -6 }, { 4, -2 }, { 2, -8 }, { -5, -5 }, { 4, -7 } }

local function update_launch_rock(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] > 2 then
    d[0] = 0
    d[1] = d[1] + 1
    local extra = P.u16(d[1]) * P.u16(d[1])
    d[3] = P.s16(d[3] + extra)
  end
  d[2] = P.s16(d[2] + d[4])
  s.x = P.asr(d[2], 3)
  d[3] = P.s16(d[3] + d[5])
  s.y = P.asr(d[3], 3)
  if s.x < -8 or s.x > P.DISPLAY_WIDTH + 8 or s.y < -8 or s.y > 120 then
    s.invisible = true
  end
end

-- pokefirered/src/battle_anim_fire.c:916
function CB.EruptionLaunchRock(s)
  update_launch_rock(s)
  if s.invisible then
    local t = s.g2.task
    if t and t.data then t.data[6] = t.data[6] - 1 end
    P.destroy(s)
  end
end

local function create_launch_rocks(t, m)
  local y = P.u16(m.y + m.y2 - 64 + ((P.atk() == "player") and 74 or 44))
  local x = P.u16(m.x)
  local sign
  if P.atk() == "player" then
    x = x - 12
    sign = 1
  else
    x = x + 16
    sign = -1
  end
  local j = 0
  for i = 0, 6 do
    local r = P.createSprite("gEruptionLaunchRockSpriteTemplate", P.s16(x), P.s16(y), 2)
    if r then
      r.tileBase = r.tileBase + j * 4 + 0x40
      j = j + 1
      if j >= 5 then j = 0 end
      r.data[0] = 0
      r.data[1] = 0
      r.data[2] = P.s16(P.u16(r.x) * 8)
      r.data[3] = P.s16(P.u16(r.y) * 8)
      r.data[4] = ROCK_SPEEDS[i + 1][1] * sign * 8
      r.data[5] = ROCK_SPEEDS[i + 1][2] * 8
      r.g2.task = t
      t.data[6] = t.data[6] + 1
    end
  end
end

local function eruption_step(t)
  local d = t.data
  local m = t.g2.mon
  if d[0] == 0 then
    P.SetSpriteSquashParams(t, m, 0x100, 0x100, 0xE0, 0x200, 32)
    d[0] = d[0] + 1
  end
  if d[0] == 1 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[2] = d[2] + 1
      if d[2] % 2 == 1 then m.x2 = 3 else m.x2 = -3 end
    end
    if d[5] ~= 0 then
      d[3] = d[3] + 1
      if d[3] > 4 then
        d[3] = 0
        m.y = m.y + 1
      end
    end
    if P.RunSpriteSquash(t) == 0 then
      P.setYOffsetFromYScale(m)
      m.x2 = 0
      d[1] = 0
      d[2] = 0
      d[3] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 2 then
    d[1] = d[1] + 1
    if d[1] > 4 then
      if d[5] ~= 0 then
        P.SetSpriteSquashParams(t, m, 0xE0, 0x200, 0x180, 0xF0, 6)
      else
        P.SetSpriteSquashParams(t, m, 0xE0, 0x200, 0x180, 0xC0, 6)
      end
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 3 then
    if P.RunSpriteSquash(t) == 0 then
      create_launch_rocks(t, m)
      d[0] = d[0] + 1
    end
  elseif d[0] == 4 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[2] = d[2] + 1
      if d[2] % 2 == 1 then m.y2 = m.y2 + 3 else m.y2 = m.y2 - 3 end
    end
    d[3] = d[3] + 1
    if d[3] > 24 then
      if d[5] ~= 0 then
        P.SetSpriteSquashParams(t, m, 0x180, 0xF0, 0x100, 0x100, 8)
      else
        P.SetSpriteSquashParams(t, m, 0x180, 0xC0, 0x100, 0x100, 8)
      end
      if d[2] % 2 == 1 then m.y2 = m.y2 - 3 end
      d[1] = 0
      d[2] = 0
      d[3] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 5 then
    if d[5] ~= 0 then m.y = m.y - 1 end
    if P.RunSpriteSquash(t) == 0 then
      m.y = d[4]
      P.resetSpriteRotScale(m)
      d[2] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 6 then
    if d[6] == 0 then P.destroyTask(t) end
  end
end

-- pokefirered/src/battle_anim_fire.c:754
TASKS.EruptionLaunchRocks = P.task(function(t)
  local m = P.monById(P.ANIM_ATTACKER)
  if not m then
    P.destroyTask(t)
    return
  end
  t.g2.mon = m
  t.data[0] = 0
  t.data[1] = 0
  t.data[2] = 0
  t.data[3] = 0
  t.data[4] = m.y
  t.data[5] = P.side(P.atk())
  t.data[6] = 0
  t.func = eruption_step
end)

local function falling_rock_step(s)
  local d = s.data
  if d[0] == 0 then
    if d[6] ~= 0 then
      d[6] = d[6] - 1
      return
    end
    d[0] = d[0] + 1
  end
  if d[0] == 1 then
    s.y = s.y + 8
    if s.y >= d[7] then
      s.y = d[7]
      d[0] = d[0] + 1
    end
  elseif d[0] == 2 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[2] = d[2] + 1
      if d[2] % 2 ~= 0 then s.y2 = -3 else s.y2 = 3 end
    end
    d[3] = d[3] + 1
    if d[3] > 16 then P.destroy(s) end
  end
end

-- pokefirered/src/battle_anim_fire.c:994
function CB.EruptionFallingRock(s)
  s.x = P.arg(0)
  s.y = P.arg(1)
  s.data[0] = 0
  s.data[1] = 0
  s.data[2] = 0
  s.data[6] = P.arg(2)
  s.data[7] = P.arg(3)
  s.tileBase = s.tileBase + P.arg(4) * 16
  s.pcb = falling_rock_step
end

local function wisp_orb_step(s)
  if not P.AnimTranslateLinear(s) then
    s.x2 = s.x2 + P.Sin(s.data[5], 16)
    local initial = s.data[5]
    s.data[5] = (s.data[5] + 4) % 256
    local new = s.data[5]
    if (initial == 0 or initial > 196) and new > 0 and s.data[7] == 0 then
      P.playSE("SE_M_FLAME_WHEEL", P.customPanning())
    end
  else
    P.destroy(s)
  end
end

local function wisp_orb(s)
  local d = s.data
  if d[0] == 0 then
    P.InitSpritePosToAnimAttacker(s, false)
    P.startAnim(s, P.arg(2))
    d[7] = P.arg(2)
    if P.atk() ~= "player" then d[4] = 4 else d[4] = -4 end
    s.oamPriority = P.bgPriority(P.tgt())
    d[0] = d[0] + 1
  elseif d[0] == 1 then
    d[1] = P.s16(d[1] + 192)
    if P.atk() ~= "player" then
      s.y2 = -P.asr(d[1], 8)
    else
      s.y2 = P.asr(d[1], 8)
    end
    s.x2 = P.Sin(d[2], d[4])
    d[2] = (d[2] + 4) % 256
    d[3] = d[3] + 1
    if d[3] == 1 then
      d[3] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 2 then
    s.x2 = P.Sin(d[2], d[4])
    d[2] = (d[2] + 4) % 256
    d[3] = d[3] + 1
    if d[3] == 31 then
      s.x = s.x + s.x2
      s.y = s.y + s.y2
      s.x2 = 0
      s.y2 = 0
      d[0] = 256
      d[1] = s.x
      d[2] = P.coord(P.tgt(), 2)
      d[3] = s.y
      d[4] = P.coord(P.tgt(), 3)
      P.InitAnimLinearTranslationWithSpeed(s)
      s.pcb = wisp_orb_step
    end
  end
end

-- pokefirered/src/battle_anim_fire.c:1057
function CB.WillOWispOrb(s)
  wisp_orb(s)
  if s.pcb == nil or s.pcb == CB.WillOWispOrb then s.pcb = wisp_orb end
end

local function wisp_fire(s)
  local d = s.data
  if d[0] == 0 then
    d[1] = P.arg(0)
    d[0] = d[0] + 1
  end
  d[3] = P.s16(d[3] + 0xC0 * 2)
  d[4] = P.s16(d[4] + 0xA0)
  s.x2 = P.Sin(d[1], P.asr(d[3], 8))
  s.y2 = P.Cos(d[1], P.asr(d[4], 8))
  d[1] = (d[1] + 7) % 256
  if d[1] < 64 or d[1] > 195 then
    s.oamPriority = P.bgPriority(P.tgt())
  else
    s.oamPriority = P.bgPriority(P.tgt()) + 1
  end
  d[2] = d[2] + 1
  if d[2] > 0x14 then s.invisible = not s.invisible end
  if d[2] == 0x1E then P.destroy(s) end
end

-- pokefirered/src/battle_anim_fire.c:1125
function CB.WillOWispFire(s)
  wisp_fire(s)
  s.pcb = wisp_fire
end

local function heat_wave_apply(t)
  local m = t.g2.mon
  if m and t.data[13] >= 1 then m.x2 = t.data[10] + t.data[11] end
end

local function heat_wave_toggle(t)
  t.data[1] = 0
  t.data[2] = t.data[2] + 1
  if t.data[2] % 2 == 1 then t.data[11] = 2 else t.data[11] = -2 end
end

local function heat_wave_step(t)
  local d = t.data
  if d[0] == 0 then
    d[10] = d[10] + d[12] * 2
    d[1] = d[1] + 1
    if d[1] >= 2 then heat_wave_toggle(t) end
    heat_wave_apply(t)
    d[9] = d[9] + 1
    if d[9] == 16 then
      d[9] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 1 then
    d[1] = d[1] + 1
    if d[1] >= 5 then heat_wave_toggle(t) end
    heat_wave_apply(t)
    d[9] = d[9] + 1
    if d[9] == 96 then
      d[9] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 2 then
    d[10] = d[10] - d[12] * 2
    d[1] = d[1] + 1
    if d[1] >= 2 then heat_wave_toggle(t) end
    heat_wave_apply(t)
    d[9] = d[9] + 1
    if d[9] == 16 then d[0] = d[0] + 1 end
  elseif d[0] == 3 then
    local m = t.g2.mon
    if m then m.x2 = 0 end
    P.destroyTask(t)
  end
end

-- pokefirered/src/battle_anim_fire.c:1157
TASKS.MoveHeatWaveTargets = P.task(function(t)
  t.data[12] = (P.atk() == "player") and 1 or -1
  t.data[13] = 1
  t.g2.mon = P.monById(P.ANIM_TARGET)
  t.func = heat_wave_step
end)

-- pokefirered/src/battle_anim_fire.c:1238
TASKS.BlendBackground = P.task(function(t)
  local vm = P.vm
  if vm then
    vm._animBgBlend = { coeff = P.arg(0), color = P.u16(P.arg(1)) }
  end
  P.destroyTask(t)
end)

local SHAKE_DIRS = {
  [0] = { [0] = -1, -1, 0, 1, 1, 0, 0, -1, -1, 1, 1, 0, 0, -1, 0, 1 },
  [1] = { [0] = -1, 0, 1, 0, -1, 1, 0, -1, 0, 1, 0, -1, 0, 1, 0, 1 },
}

local function shake_pattern(t)
  local d = t.data
  if d[0] == 0 then
    d[1] = P.arg(0)
    d[2] = P.arg(1)
    d[3] = P.arg(2)
    d[4] = P.arg(3)
  end
  d[0] = d[0] + 1
  local m = t.g2.mon
  local dir
  if d[4] == 0 then dir = SHAKE_DIRS[0][d[0] % 10] else dir = SHAKE_DIRS[1][d[0] % 10] end
  if m then
    if d[3] == 1 then
      local v = P.arg(1) * dir
      m.y2 = v < 0 and -v or v
    else
      m.x2 = P.arg(1) * dir
    end
  end
  if d[0] == d[1] then
    if m then
      m.x2 = 0
      m.y2 = 0
    end
    P.destroyTask(t)
  end
end

-- pokefirered/src/battle_anim_fire.c:1254
TASKS.ShakeTargetInPattern = P.task(function(t)
  t.g2.mon = P.mon(P.tgt())
  t.func = shake_pattern
  shake_pattern(t)
end)

return { cb = CB, tasks = TASKS }
