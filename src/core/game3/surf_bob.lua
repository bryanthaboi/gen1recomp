-- pokeemerald/src/field_effect_helpers.c:1052 UpdateSurfBlobFieldEffect

local SurfBob = {}

-- pokeemerald/include/field_effect_helpers.h:7
SurfBob.BOB_NONE = 0
SurfBob.BOB_PLAYER_AND_MON = 1
SurfBob.BOB_JUST_MON = 2

SurfBob.FAMILY = {
  -- pokeemerald/src/field_effect_helpers.c:1111
  rse = { velocity = -1, intervals = { 3, 7 }, flipMask = 15, animBump = false },
  -- pokefirered/src/field_effect_helpers.c:1049
  frlg = { velocity = 0, intervals = { 7, 15 }, flipMask = 31, animBump = true },
}

-- pokeemerald/include/global.fieldmap.h:18
local ELEVATION_DEFAULT = 3

-- pokefirered/src/data/field_effects/field_effect_objects.h:184
SurfBob.FRLG_FRAME_DURATION = 48

local DIRS = { { 0, 1 }, { 0, -1 }, { -1, 0 }, { 1, 0 } }

-- pokeemerald/src/field_effect_helpers.c:999 FldEff_SurfBlob
function SurfBob.newBlob(family)
  local p = SurfBob.FAMILY[family] or SurfBob.FAMILY.frlg
  return {
    p = p, velocity = p.velocity, timer = 0, y2 = 0, intervalIdx = 1,
    prevX = -1, prevY = -1, dir = nil, animClock = 0, state = SurfBob.BOB_NONE,
  }
end

-- pokefirered/src/field_effect_helpers.c:1009 SynchroniseSurfAnim
function SurfBob.syncAnim(b, dir)
  if b.dir ~= dir then
    b.dir = dir
    b.animClock = 0
  else
    b.animClock = b.animClock + 1
  end
end

function SurfBob.animCmdIndex(b)
  return math.floor(b.animClock / SurfBob.FRLG_FRAME_DURATION) % 2
end

-- pokeemerald/src/field_effect_helpers.c:1081 SynchronizeSurfPosition
function SurfBob.syncPosition(b, x, y, elevAt)
  if b.y2 ~= 0 or (x == b.prevX and y == b.prevY) then return end
  b.intervalIdx = 1
  b.prevX, b.prevY = x, y
  if not elevAt then return end
  for _, d in ipairs(DIRS) do
    if elevAt(x + d[1], y + d[2]) == ELEVATION_DEFAULT then
      b.intervalIdx = 2
      return
    end
  end
end

-- pokeemerald/src/field_effect_helpers.c:1107 UpdateBobbingEffect
function SurfBob.tick(b, state)
  b.state = state
  if state == SurfBob.BOB_NONE then return end
  b.timer = (b.timer + 1) % 65536
  if b.timer % (b.p.intervals[b.intervalIdx] + 1) == 0 then
    b.y2 = b.y2 + b.velocity
  end
  if b.timer % (b.p.flipMask + 1) == 0 then
    b.velocity = -b.velocity
  end
end

-- pokefirered/src/field_effect_helpers.c:1061
function SurfBob.playerY2(b)
  if not b or b.state ~= SurfBob.BOB_PLAYER_AND_MON then return 0 end
  local y2 = b.y2
  if b.p.animBump and SurfBob.animCmdIndex(b) ~= 0 then y2 = y2 + 1 end
  return y2
end

-- pokeemerald/src/field_effect_helpers.c:1150 StartUnderwaterSurfBlobBobbing
function SurfBob.newUnderwater()
  return { bobY = 1, timer = 0, y2 = 0 }
end

-- pokeemerald/src/field_effect_helpers.c:1164 SpriteCB_UnderwaterSurfBlob
function SurfBob.tickUnderwater(u)
  local t = u.timer
  u.timer = (t + 1) % 65536
  if t % 4 == 0 then u.y2 = u.y2 + u.bobY end
  if u.timer % 16 == 0 then u.bobY = -u.bobY end
end

return SurfBob
