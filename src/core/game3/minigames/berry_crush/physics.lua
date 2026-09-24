local R = require("src.core.game3.minigames.berry_crush.rules")

local Phys = {}

local floor = math.floor
local END = "end"

Phys.SINE = {}
for i = 0, 255 do
  Phys.SINE[i] = floor(math.sin(i * math.pi / 128) * 256 + 0.5)
end

-- pokefirered/src/trig.c:514
function Phys.sin(index, amplitude)
  return R.s16(floor(amplitude * Phys.SINE[index % 256] / 256))
end

-- pokefirered/src/berry_crush.c:765
Phys.IMPACT_ANIMS = {
  [0] = { { 0, 4 }, { 1, 4 }, { 2, 4 }, END },
  [1] = { { 3, 2 }, { 4, 2 }, { 5, 2 }, { 6, 2 }, END },
}
-- pokefirered/src/berry_crush.c:780
Phys.SPARKLE_ANIMS = {
  [0] = { { 0, 2 }, { 1, 2 }, { 2, 2 }, { 3, 2 }, { 4, 2 }, { 5, 2 }, { jump = 0 } },
  [1] = { { 6, 4 }, { 7, 4 }, { 8, 4 }, { 9, 4 }, { 10, 4 }, { 11, 4 }, { 12, 4 }, { 13, 4 }, { jump = 0 } },
}

function Phys.newAnim(set)
  return { set = set, num = 0, idx = 1, delay = 0, ended = false, beginning = false, paused = true, frame = 0 }
end

-- pokefirered/src/sprite.c:1336
function Phys.startAnim(a, num)
  a.num = num
  a.beginning = true
  a.ended = false
end

local function setFrame(a, cmd)
  a.frame = cmd[1]
  local d = cmd[2]
  if d > 0 then d = d - 1 end
  a.delay = d
end

-- pokefirered/src/sprite.c:905
function Phys.stepAnim(a)
  local cmds = a.set[a.num]
  if a.beginning then
    a.idx = 1
    a.ended = false
    a.beginning = false
    setFrame(a, cmds[1])
    return
  end
  if a.delay > 0 then
    if not a.paused then a.delay = a.delay - 1 end
    return
  end
  if a.paused then return end
  a.idx = a.idx + 1
  local cmd = cmds[a.idx]
  if cmd == END or cmd == nil then
    a.idx = a.idx - 1
    a.ended = true
  elseif cmd.jump then
    a.idx = cmd.jump + 1
    setFrame(a, cmds[a.idx])
  else
    setFrame(a, cmd)
  end
end

-- pokefirered/src/berry_crush.c:3312
function Phys.newImpact(coords)
  return {
    x = coords.impactXOffset + 120, y = coords.impactYOffset + 32,
    x2 = 0, y2 = 0, invisible = true, anim = Phys.newAnim(Phys.IMPACT_ANIMS),
  }
end

-- pokefirered/src/berry_crush.c:2796
function Phys.startImpact(sp, flags, T)
  Phys.startAnim(sp.anim, R.band(flags, R.F_INPUT_HIT_SYNC) ~= 0 and 1 or 0)
  sp.invisible = false
  sp.anim.paused = false
  local c = T.impact_coords[(flags % 4)]
  sp.x2 = c[1]
  sp.y2 = c[2]
end

-- pokefirered/src/berry_crush.c:3390
function Phys.stepImpact(sp)
  if sp.anim.ended then
    sp.invisible = true
    sp.anim.paused = true
  end
  Phys.stepAnim(sp.anim)
end

-- pokefirered/src/berry_crush.c:3329
function Phys.newSparkle(i, T)
  local c = T.sparkle_coords[i + 1]
  return {
    i = i, x = c[1] + 120, y = c[2] + 136, x2 = 0, y2 = 0,
    invisible = true, cb = nil, anim = Phys.newAnim(Phys.SPARKLE_ANIMS),
    sX = 0, ySpeed = 0, yAccel = 0, xSpeed = 0, sinIdx = 0, sinSpeed = 0, amp = 0,
    target = 0, horiz = false,
  }
end

-- pokefirered/src/berry_crush.c:2818
function Phys.spawnSparkles(sparkles, rec, timer, T)
  local ym = timer % 3
  local xm = ym
  for i = 0, rec.sa * 2 + 3 - 1 do
    local sp = sparkles[i + 1]
    if sp and sp.invisible then
      local c = T.sparkle_coords[i + 1]
      sp.cb = "init"
      sp.x = c[1] + 120
      sp.y = c[2] + 136 - ym * 4
      sp.x2 = c[1] + R.trunc(c[1], xm * 4)
      sp.y2 = c[2]
      Phys.startAnim(sp.anim, rec.big and 1 or 0)
      ym = ym + 1
      if ym > 3 then ym = 0 end
    end
  end
end

-- pokefirered/src/berry_crush.c:3450
local function sparkleInit(sp)
  local speed = R.qns(8, 2.5)
  sp.ySpeed = speed
  sp.yAccel = R.qns(8, 0.125)
  sp.target = 168
  local xMult = R.qns(7, sp.x2)
  local var = R.qnsDiv(7, R.qns(7, sp.target - R.u16(sp.y)), R.shr(speed + R.qns(8, 0.125), 1))
  sp.sX = R.qns(7, R.u16(sp.x))
  sp.xSpeed = R.qnsDiv(7, xMult, var)
  speed = R.qnsMul(7, var, R.qns(7, 0.666666667))
  sp.sinIdx = 0
  sp.sinSpeed = R.qnsDiv(7, R.qns(7, 127), speed)
  sp.amp = R.trunc(sp.x2, 4)
  sp.horiz = true
  sp.y2 = 0
  sp.x2 = 0
  sp.cb = "move"
  sp.anim.paused = false
  sp.invisible = false
end

-- pokefirered/src/berry_crush.c:3428
local function sparkleMove(sp)
  sp.ySpeed = R.s16(sp.ySpeed + sp.yAccel)
  sp.y2 = sp.y2 + R.shr(sp.ySpeed, 8)
  if sp.horiz then
    sp.sX = R.s16(sp.sX + sp.xSpeed)
    sp.sinIdx = R.s16(sp.sinIdx + sp.sinSpeed)
    sp.x2 = Phys.sin(R.shr(sp.sinIdx, 7), sp.amp)
    if R.shr(sp.sinIdx, 7) > 126 then
      sp.x2 = 0
      sp.horiz = false
    end
  end
  sp.x = R.shr(sp.sX, 7)
  if sp.y + sp.y2 > sp.target then sp.cb = "end" end
end

-- pokefirered/src/berry_crush.c:3399
local function sparkleEnd(sp)
  sp.sX, sp.ySpeed, sp.yAccel, sp.xSpeed, sp.sinIdx, sp.sinSpeed, sp.amp = 0, 0, 0, 0, 0, 0, 0
  sp.target, sp.horiz = 0, false
  sp.x2 = 0
  sp.y2 = 0
  sp.invisible = true
  sp.anim.paused = true
  sp.cb = nil
end

function Phys.stepSparkle(sp)
  if sp.cb == "init" then
    sparkleInit(sp)
  elseif sp.cb == "move" then
    sparkleMove(sp)
  elseif sp.cb == "end" then
    sparkleEnd(sp)
  end
  Phys.stepAnim(sp.anim)
end

-- pokefirered/src/berry_crush.c:2683
function Phys.newBerry(coords, berry)
  local b = {
    berry = berry, x = coords.berryXOffset + 120, y = -16, x2 = 0, y2 = 0,
    rot = 0, rotDir = coords.berryXOffset < 0 and -1 or 1, affinePaused = true,
    cb = nil, destroyed = false,
  }
  local speed = R.qns(8, 2.0)
  b.ySpeed = speed
  b.yAccel = R.qns(8, 0.125)
  b.target = 112
  local distance = coords.berryXDest - coords.berryXOffset
  local amplitude = distance
  if distance < 0 then amplitude = amplitude + 3 end
  b.amp = R.shr(amplitude, 2)
  distance = R.qns(7, distance)
  local var2 = floor((speed + R.qns(8, 0.125)) / 2)
  local var1 = R.qnsDiv(7, R.qns(7, 127), var2)
  b.sX = R.qns(7, R.u16(b.x))
  b.xSpeed = R.qnsDiv(7, distance, var1)
  var1 = R.qnsMul(7, var1, R.qns(7, 0.666666667))
  b.sinIdx = 0
  b.sinSpeed = R.qnsDiv(7, R.qns(7, 127), var1)
  b.horiz = true
  return b
end

function Phys.dropBerry(b)
  b.cb = "drop"
  b.affinePaused = false
end

-- pokefirered/src/berry_crush.c:2731
function Phys.stepBerry(b)
  if b.destroyed then return end
  if b.cb == "drop" then
    b.ySpeed = R.s16(b.ySpeed + b.yAccel)
    b.y2 = b.y2 + R.shr(b.ySpeed, 8)
    if b.horiz then
      b.sX = R.s16(b.sX + b.xSpeed)
      b.sinIdx = R.s16(b.sinIdx + b.sinSpeed)
      b.x2 = Phys.sin(R.shr(b.sinIdx, 7), b.amp)
      if R.shr(b.sinIdx, 7) > 126 then
        b.x2 = 0
        b.horiz = false
      end
    end
    b.x = R.shr(b.sX, 7)
    if b.y + b.y2 >= b.target then
      b.cb = nil
      b.destroyed = true
      return
    end
  end
  -- pokefirered/src/berry_crush.c:812
  if not b.affinePaused then b.rot = (b.rot + b.rotDir * 512) % 0x10000 end
end

function Phys.dropFrames(coords)
  local b = Phys.newBerry(coords, 0)
  Phys.dropBerry(b)
  local n = 0
  while not b.destroyed and n < 1000 do
    Phys.stepBerry(b)
    n = n + 1
  end
  return n
end

return Phys
