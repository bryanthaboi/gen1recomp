local P = require("src.core.game3.battle.anim_port.g2_pret")

local CB = {}
local TASKS = {}

-- pokefirered/src/battle_anim_dragon.c:189
function CB.OutrageFlame(s)
  local atk = P.atk()
  s.x = P.coord(atk, 2)
  s.y = P.coord(atk, 3)
  if atk ~= "player" then
    s.x = s.x - P.arg(0)
    P.setArg(3, -P.arg(3))
    P.setArg(4, -P.arg(4))
  else
    s.x = s.x + P.arg(0)
  end
  s.y = s.y + P.arg(1)
  s.data[0] = P.arg(2)
  s.data[1] = P.arg(3)
  s.data[3] = P.arg(4)
  s.data[5] = P.arg(5)
  s.invisible = true
  P.storeCallback(s, P.DestroySpriteAndMatrix)
  s.pcb = P.TranslateSpriteLinearAndFlicker
end

-- pokefirered/src/battle_anim_dragon.c:213
local function start_dragon_fire_translation(s)
  P.SetSpriteCoordsToAnimAttackerCoords(s)
  s.data[2] = P.coord(P.tgt(), 2)
  s.data[4] = P.coord(P.tgt(), 3)
  if P.atk() ~= "player" then
    s.x = s.x - P.arg(1)
    s.y = s.y + P.arg(1)
    s.data[2] = s.data[2] - P.arg(2)
    s.data[4] = s.data[4] + P.arg(3)
  else
    s.x = s.x + P.arg(0)
    s.y = s.y + P.arg(1)
    s.data[2] = s.data[2] + P.arg(2)
    s.data[4] = s.data[4] + P.arg(3)
    P.startAnim(s, 1)
  end
  s.data[0] = P.arg(4)
  s.pcb = P.StartAnimLinearTranslation
  P.storeCallback(s, P.DestroySpriteAndMatrix)
end

-- pokefirered/src/battle_anim_dragon.c:238
function CB.DragonRageFirePlume(s)
  if P.arg(0) == 0 then
    s.x = P.coord(P.atk(), 0)
    s.y = P.coord(P.atk(), 1)
  else
    s.x = P.coord(P.tgt(), 0)
    s.y = P.coord(P.tgt(), 1)
  end
  P.SetAnimSpriteInitialXOffset(s, P.arg(1))
  s.y = s.y + P.arg(2)
  s.pcb = P.RunStoredCallbackWhenAnimEnds
  P.storeCallback(s, P.DestroySpriteAndMatrix)
end

-- pokefirered/src/battle_anim_dragon.c:257
function CB.DragonFireToTarget(s)
  if P.atk() ~= "player" then P.startAffineAnim(s, 1) end
  start_dragon_fire_translation(s)
end

local function dragon_dance_orb_step(s)
  local d = s.data
  if d[0] == 0 then
    d[6] = (d[6] - d[5]) % 256
    s.x2 = P.Cos(d[6], d[7])
    s.y2 = P.Sin(d[6], d[7])
    d[4] = d[4] + 1
    if d[4] > 5 then
      d[4] = 0
      if d[5] <= 15 then
        d[5] = d[5] + 1
        if d[5] > 15 then d[5] = 16 end
      end
    end
    d[3] = d[3] + 1
    if d[3] > 0x3C then
      d[3] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 1 then
    d[6] = (d[6] - d[5]) % 256
    if d[7] <= 0x95 then
      d[7] = d[7] + 8
      if d[7] > 0x95 then d[7] = 0x96 end
    end
    s.x2 = P.Cos(d[6], d[7])
    s.y2 = P.Sin(d[6], d[7])
    d[4] = d[4] + 1
    if d[4] > 5 then
      d[4] = 0
      if d[5] <= 15 then
        d[5] = d[5] + 1
        if d[5] > 15 then d[5] = 16 end
      end
    end
    d[3] = d[3] + 1
    if d[3] > 20 then P.destroy(s) end
  end
end

-- pokefirered/src/battle_anim_dragon.c:264
function CB.DragonDanceOrb(s)
  local atk = P.atk()
  s.x = P.coord(atk, 2)
  s.y = P.coord(atk, 3)
  s.data[4] = 0
  s.data[5] = 1
  s.data[6] = P.arg(0)
  local r5 = P.coordAttr(atk, P.ATTR_HEIGHT)
  local r0 = P.coordAttr(atk, P.ATTR_WIDTH)
  if r5 > r0 then
    s.data[7] = P.div(r5, 2)
  else
    s.data[7] = P.div(r0, 2)
  end
  s.x2 = P.Cos(s.data[6], s.data[7])
  s.y2 = P.Sin(s.data[6], s.data[7])
  s.pcb = dragon_dance_orb_step
end

-- pokefirered/src/battle_anim_dragon.c:398
local function update_dragon_dance_scanline(t)
  local g2 = t.g2
  local r3 = t.data[5]
  local shift = g2.shift
  for i = t.data[3], t.data[4] do
    shift[i] = -(P.asr(P.sine(r3) * t.data[6], 7) + t.data[2])
    r3 = (r3 + 8) % 256
  end
  t.data[5] = (t.data[5] + 9) % 256
end

local function dragon_dance_waver_step(t)
  local d = t.data
  if d[0] == 0 then
    d[7] = d[7] + 1
    if d[7] > 1 then
      d[7] = 0
      d[6] = d[6] + 1
      if d[6] == 3 then d[0] = d[0] + 1 end
    end
    update_dragon_dance_scanline(t)
  elseif d[0] == 1 then
    d[1] = d[1] + 1
    if d[1] > 0x3C then d[0] = d[0] + 1 end
    update_dragon_dance_scanline(t)
  elseif d[0] == 2 then
    d[7] = d[7] + 1
    if d[7] > 1 then
      d[7] = 0
      d[6] = d[6] - 1
      if d[6] == 0 then d[0] = d[0] + 1 end
    end
    update_dragon_dance_scanline(t)
  elseif d[0] == 3 then
    local p = t.g2.p
    if p and p.hShift == t.g2.shift then p.hShift = nil end
    d[0] = d[0] + 1
  elseif d[0] == 4 then
    P.destroyTask(t)
  end
end

-- pokefirered/src/battle_anim_dragon.c:325
TASKS.DragonDanceWaver = P.task(function(t)
  local atk = P.atk()
  t.data[2] = 0
  local r1 = P.yWithElevation(atk)
  t.data[3] = r1 - 32
  t.data[4] = r1 + 32
  if t.data[3] < 0 then t.data[3] = 0 end
  local shift = {}
  for i = t.data[3], t.data[4] do shift[i] = t.data[2] end
  t.g2.shift = shift
  local p = P.present(atk)
  t.g2.p = p
  if p then p.hShift = shift end
  t.func = dragon_dance_waver_step
end)

local function overheat_flame_step(s)
  local d = s.data
  d[4] = d[4] + d[1]
  d[5] = d[5] + d[2]
  s.x2 = P.div(d[4], 10)
  s.y2 = P.div(d[5], 10)
  d[0] = d[0] + 1
  if d[0] > d[3] then P.destroy(s) end
end

-- pokefirered/src/battle_anim_dragon.c:410
function CB.OverheatFlame(s)
  local yAmplitude = P.div(P.arg(2) * 3, 5)
  local atk = P.atk()
  s.x = P.coord(atk, 2)
  s.y = P.coord(atk, 3) + P.arg(4)
  s.data[1] = P.Cos(P.arg(1), P.arg(2))
  s.data[2] = P.Sin(P.arg(1), yAmplitude)
  s.x = s.x + s.data[1] * P.arg(0)
  s.y = s.y + s.data[2] * P.arg(0)
  s.data[3] = P.arg(3)
  s.pcb = overheat_flame_step
end

return { cb = CB, tasks = TASKS }
