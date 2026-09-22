-- Visual-task registry + fixed task pool (pret gTasks for battle anims).
-- Default stub finishes in 1 frame so unknown createvisualtask still ends scripts.

local AnimSprites = require("src.core.game3.battle.anim_sprites")
local Trig = require("src.core.game3.trig")

local AnimTasks = {}

AnimTasks.MAX = 48



local function Sin(index, amp)
  index = math.floor(tonumber(index) or 0) % 256
  local val = Trig.SINE[index + 1] or 0
  return math.floor((val * (amp or 0)) / 256)
end

local function Cos(index, amp)
  return Sin((tonumber(index) or 0) + 64, amp)
end

local function clear_task(t)
  for k in pairs(t) do
    if k ~= "data" then t[k] = nil end
  end
  t.active = false
  t.priority = 0
  for i = 0, 15 do
    t.data[i] = 0
  end
end

function AnimTasks.init()
  if AnimTasks._pool then return end
  AnimTasks._pool = {}
  for i = 1, AnimTasks.MAX do
    local t = { data = {} }
    for j = 0, 15 do t.data[j] = 0 end
    clear_task(t)
    AnimTasks._pool[i] = t
  end
end

function AnimTasks.reset()
  AnimTasks.init()
  for i = 1, AnimTasks.MAX do
    clear_task(AnimTasks._pool[i])
  end
end

function AnimTasks.activeCount()
  AnimTasks.init()
  local n = 0
  for i = 1, AnimTasks.MAX do
    if AnimTasks._pool[i].active and not AnimTasks._pool[i]._uncounted then n = n + 1 end
  end
  return n
end

local function destroy_task(t)
  clear_task(t)
end

--- Stub: lasts 1 frame then finishes (keeps waitforvisualfinish moving).
local function stub_task(t)
  t.data[15] = (t.data[15] or 0) + 1
  if t.data[15] >= 1 then
    destroy_task(t)
  end
end

-- Registry: name → function(task, vm)
AnimTasks.REGISTRY = {}

--- pret AnimTask_ShakeMon (pokefirered/src/battle_anim_mon_movement.c:94)
-- arg 0: battler, arg 1: x offset, arg 2: y offset, arg 3: num shakes, arg 4: delay
function AnimTasks.ShakeMon(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[0])
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._xOff = tonumber(t.data[1]) or 0
    t._yOff = tonumber(t.data[2]) or 0
    t._numShakes = math.max(1, tonumber(t.data[3]) or 1)
    t._delay = math.max(0, tonumber(t.data[4]) or 1)
    t._timer = t._delay
    t._p.ox = t._xOff
    t._p.oy = t._yOff
    return
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  if (t._timer or 0) <= 0 then
    p.ox = (p.ox == 0) and t._xOff or 0
    p.oy = (p.oy == 0) and t._yOff or 0
    t._timer = t._delay
    t._numShakes = t._numShakes - 1
    if t._numShakes <= 0 then
      p.ox = 0
      p.oy = 0
      destroy_task(t)
    end
  else
    t._timer = t._timer - 1
  end
end

AnimTasks.REGISTRY.ShakeMon = AnimTasks.ShakeMon
AnimTasks.REGISTRY.AnimTask_ShakeMon = AnimTasks.ShakeMon

--- pret AnimTask_ShakeMon2 (pokefirered/src/battle_anim_mon_movement.c:146)
-- arg 0: battler, arg 1: x offset, arg 2: y offset, arg 3: num shakes, arg 4: delay
function AnimTasks.ShakeMon2(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[0])
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._xOff = tonumber(t.data[1]) or 0
    t._yOff = tonumber(t.data[2]) or 0
    t._numShakes = math.max(1, tonumber(t.data[3]) or 1)
    t._delay = math.max(0, tonumber(t.data[4]) or 1)
    t._timer = t._delay
    t._p.ox = t._xOff
    t._p.oy = t._yOff
    return
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  if (t._timer or 0) <= 0 then
    p.ox = (p.ox == t._xOff) and -t._xOff or t._xOff
    p.oy = (p.oy == t._yOff) and -t._yOff or t._yOff
    t._timer = t._delay
    t._numShakes = t._numShakes - 1
    if t._numShakes <= 0 then
      p.ox = 0
      p.oy = 0
      destroy_task(t)
    end
  else
    t._timer = t._timer - 1
  end
end

AnimTasks.REGISTRY.ShakeMon2 = AnimTasks.ShakeMon2
AnimTasks.REGISTRY.AnimTask_ShakeMon2 = AnimTasks.ShakeMon2

--- pret AnimTask_ShakeMonInPlace (pokefirered/src/battle_anim_mon_movement.c:232)
-- arg 0: battler, arg 1: x offset, arg 2: y offset, arg 3: num shakes, arg 4: delay
function AnimTasks.ShakeMonInPlace(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[0])
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    local xOff = tonumber(t.data[1]) or 0
    local yOff = tonumber(t.data[2]) or 0
    t._p.ox = (t._p.ox or 0) + xOff
    t._p.oy = (t._p.oy or 0) + yOff
    t._step = 0
    t._numShakes = math.max(1, tonumber(t.data[3]) or 1)
    t._timer = 0
    t._delay = math.max(0, tonumber(t.data[4]) or 1)
    t._dx = xOff * 2
    t._dy = yOff * 2
    return
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  if (t._timer or 0) <= 0 then
    if (t._step % 2) == 1 then
      p.ox = (p.ox or 0) + t._dx
      p.oy = (p.oy or 0) + t._dy
    else
      p.ox = (p.ox or 0) - t._dx
      p.oy = (p.oy or 0) - t._dy
    end
    t._timer = t._delay
    t._step = t._step + 1
    if t._step >= t._numShakes then
      if (t._step % 2) == 1 then
        p.ox = (p.ox or 0) + math.floor(t._dx / 2)
        p.oy = (p.oy or 0) + math.floor(t._dy / 2)
      else
        p.ox = (p.ox or 0) - math.floor(t._dx / 2)
        p.oy = (p.oy or 0) - math.floor(t._dy / 2)
      end
      destroy_task(t)
    end
  else
    t._timer = t._timer - 1
  end
end

AnimTasks.REGISTRY.ShakeMonInPlace = AnimTasks.ShakeMonInPlace
AnimTasks.REGISTRY.AnimTask_ShakeMonInPlace = AnimTasks.ShakeMonInPlace

--- pret AnimTask_ShakeAndSinkMon (pokefirered/src/battle_anim_mon_movement.c:294)
-- arg 0: battler, arg 1: x offset, arg 2: frame delay, arg 3: downward speed (subpixel Q8.8), arg 4: duration
function AnimTasks.ShakeAndSinkMon(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[0])
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._xOff = tonumber(t.data[1]) or 0
    t._delay = math.max(1, tonumber(t.data[2]) or 1)
    t._downSpeed = tonumber(t.data[3]) or 0
    t._duration = math.max(1, tonumber(t.data[4]) or 1)
    t._delayCounter = 0
    t._subY = 0
    t._p.ox = t._xOff
    return
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  t._delayCounter = t._delayCounter + 1
  if t._delayCounter >= t._delay then
    t._delayCounter = 0
    if p.ox == t._xOff then
      t._xOff = -t._xOff
    end
    p.ox = p.ox + t._xOff
  end
  t._subY = t._subY + t._downSpeed
  p.oy = math.floor(t._subY / 256)
  t._duration = t._duration - 1
  if t._duration <= 0 then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.ShakeAndSinkMon = AnimTasks.ShakeAndSinkMon
AnimTasks.REGISTRY.AnimTask_ShakeAndSinkMon = AnimTasks.ShakeAndSinkMon

--- pret DoHorizontalLunge / ReverseHorizontalLungeDirection (pokefirered/src/battle_anim_mon_movement.c:388)
-- arg 0: duration of single lunge direction, arg 1: x pixel delta per frame
function AnimTasks.HorizontalLunge(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  local AnimVm = require("src.core.game3.battle.anim_vm")
  if not t._inited then
    t._inited = true
    local side = vm:attackerSide()
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._dur = math.max(1, tonumber(t.data[0]) or 4)
    local delta = tonumber(t.data[1]) or 4
    if side ~= "player" then
      delta = -delta
    end
    t._delta = delta
    t._frame = 0
    t._origZ = t._p.z
    -- Dynamic Z-indexing: elevate attacker above target and healthbox during lunge
    t._p.z = AnimVm.Z.FRONT
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  t._frame = t._frame + 1
  if t._frame <= t._dur then
    p.ox = (p.ox or 0) + t._delta
  elseif t._frame <= t._dur * 2 then
    p.ox = (p.ox or 0) - t._delta
  else
    p.ox = 0
    if t._origZ then p.z = t._origZ end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.HorizontalLunge = AnimTasks.HorizontalLunge
AnimTasks.REGISTRY.DoHorizontalLunge = AnimTasks.HorizontalLunge
AnimTasks.REGISTRY.ReverseHorizontalLungeDirection = AnimTasks.HorizontalLunge

--- pret DoVerticalDip / ReverseVerticalDipDirection (pokefirered/src/battle_anim_mon_movement.c:416)
-- arg 0: duration of single dip direction, arg 1: y pixel delta per frame, arg 2: battler
function AnimTasks.VerticalDip(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[2] or 0)
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._dur = math.max(1, tonumber(t.data[0]) or 4)
    t._delta = tonumber(t.data[1]) or 4
    t._frame = 0
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  t._frame = t._frame + 1
  if t._frame <= t._dur then
    p.oy = (p.oy or 0) + t._delta
  elseif t._frame <= t._dur * 2 then
    p.oy = (p.oy or 0) - t._delta
  else
    p.oy = 0
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.VerticalDip = AnimTasks.VerticalDip
AnimTasks.REGISTRY.DoVerticalDip = AnimTasks.VerticalDip
AnimTasks.REGISTRY.ReverseVerticalDipDirection = AnimTasks.VerticalDip

--- pret SlideMonToOriginalPos (pokefirered/src/battle_anim_mon_movement.c:443)
-- arg 0: 0=attacker, 1=target; arg 1: dir (0=both, 1=horiz, 2=vert); arg 2: duration
function AnimTasks.SlideMonToOriginalPos(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  local AnimVm = require("src.core.game3.battle.anim_vm")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[0] or 0)
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._dir = tonumber(t.data[1]) or 0
    t._dur = math.max(1, tonumber(t.data[2]) or 10)
    t._startX = t._p.ox or 0
    t._startY = t._p.oy or 0
    t._deltaX_fp = math.floor((-t._startX * 256) / t._dur)
    t._deltaY_fp = math.floor((-t._startY * 256) / t._dur)
    t._accumX = 0
    t._accumY = 0
    t._ticks = t._dur
    t._p.z = (side == "player") and AnimVm.Z.PLAYER or AnimVm.Z.ENEMY
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  if t._ticks <= 0 then
    if t._dir == 0 or t._dir == 1 then p.ox = 0 end
    if t._dir == 0 or t._dir == 2 then p.oy = 0 end
    p.z = (t._side == "player") and AnimVm.Z.PLAYER or AnimVm.Z.ENEMY
    destroy_task(t)
    return
  end
  t._ticks = t._ticks - 1
  t._accumX = t._accumX + t._deltaX_fp
  t._accumY = t._accumY + t._deltaY_fp
  if t._dir == 0 or t._dir == 1 then
    p.ox = t._startX + math.floor(t._accumX / 256)
  end
  if t._dir == 0 or t._dir == 2 then
    p.oy = t._startY + math.floor(t._accumY / 256)
  end
  if t._ticks <= 0 then
    if t._dir == 0 or t._dir == 1 then p.ox = 0 end
    if t._dir == 0 or t._dir == 2 then p.oy = 0 end
    p.z = (t._side == "player") and AnimVm.Z.PLAYER or AnimVm.Z.ENEMY
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.SlideMonToOriginalPos = AnimTasks.SlideMonToOriginalPos
AnimTasks.REGISTRY.AnimTask_SlideMonToOriginalPos = AnimTasks.SlideMonToOriginalPos

--- pret SlideMonToOffset (pokefirered/src/battle_anim_mon_movement.c:500)
-- arg 0: 0=attacker, 1=target; arg 1: targetX; arg 2: targetY; arg 3: mirrorY; arg 4: duration
function AnimTasks.SlideMonToOffset(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[0] or 0)
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    local targetX = tonumber(t.data[1]) or 0
    local targetY = tonumber(t.data[2]) or 0
    local mirrorY = tonumber(t.data[3]) or 0
    if side ~= "player" then
      targetX = -targetX
      if mirrorY == 1 then targetY = -targetY end
    end
    t._dur = math.max(1, tonumber(t.data[4]) or 10)
    t._startX = t._p.ox or 0
    t._startY = t._p.oy or 0
    t._targetX = targetX
    t._targetY = targetY
    t._deltaX_fp = math.floor(((targetX - t._startX) * 256) / t._dur)
    t._deltaY_fp = math.floor(((targetY - t._startY) * 256) / t._dur)
    t._accumX = 0
    t._accumY = 0
    t._ticks = t._dur
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  if t._ticks <= 0 then
    p.ox = t._targetX
    p.oy = t._targetY
    destroy_task(t)
    return
  end
  t._ticks = t._ticks - 1
  t._accumX = t._accumX + t._deltaX_fp
  t._accumY = t._accumY + t._deltaY_fp
  p.ox = t._startX + math.floor(t._accumX / 256)
  p.oy = t._startY + math.floor(t._accumY / 256)
  if t._ticks <= 0 then
    p.ox = t._targetX
    p.oy = t._targetY
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.SlideMonToOffset = AnimTasks.SlideMonToOffset
AnimTasks.REGISTRY.AnimTask_SlideMonToOffset = AnimTasks.SlideMonToOffset

--- pret SlideMonToOffsetAndBack (pokefirered/src/battle_anim_mon_movement.c:529)
-- arg 0: battler; arg 1: targetX; arg 2: targetY; arg 3: mirrorY; arg 4: duration; arg 5: resetAtEnd
function AnimTasks.SlideMonToOffsetAndBack(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[0] or 0)
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    local targetX = tonumber(t.data[1]) or 0
    local targetY = tonumber(t.data[2]) or 0
    local mirrorY = tonumber(t.data[3]) or 0
    if side ~= "player" then
      targetX = -targetX
      if mirrorY == 1 then targetY = -targetY end
    end
    t._dur = math.max(1, tonumber(t.data[4]) or 10)
    t._resetAtEnd = (tonumber(t.data[5]) or 0) == 1
    t._startX = t._p.ox or 0
    t._startY = t._p.oy or 0
    t._targetX = targetX
    t._targetY = targetY
    t._deltaX_fp = math.floor(((targetX - t._startX) * 256) / t._dur)
    t._deltaY_fp = math.floor(((targetY - t._startY) * 256) / t._dur)
    t._accumX = 0
    t._accumY = 0
    t._ticks = t._dur
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  if t._ticks <= 0 then
    if t._resetAtEnd then
      p.ox = 0
      p.oy = 0
    else
      p.ox = t._targetX
      p.oy = t._targetY
    end
    destroy_task(t)
    return
  end
  t._ticks = t._ticks - 1
  t._accumX = t._accumX + t._deltaX_fp
  t._accumY = t._accumY + t._deltaY_fp
  p.ox = t._startX + math.floor(t._accumX / 256)
  p.oy = t._startY + math.floor(t._accumY / 256)
  if t._ticks <= 0 then
    if t._resetAtEnd then
      p.ox = 0
      p.oy = 0
    else
      p.ox = t._targetX
      p.oy = t._targetY
    end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.SlideMonToOffsetAndBack = AnimTasks.SlideMonToOffsetAndBack
AnimTasks.REGISTRY.AnimTask_SlideMonToOffsetAndBack = AnimTasks.SlideMonToOffsetAndBack
AnimTasks.REGISTRY.SlideMon = AnimTasks.SlideMonToOffsetAndBack

--- Sound tasks: finish on a short timer (cry audio optional later).
function AnimTasks.SoundTaskWait(t, _vm)
  t.data[14] = (t.data[14] or 0) + 1
  if t.data[14] >= 18 then
    destroy_task(t)
  end
end

-- pokefirered/include/constants/sound.h:20-31
local CRY_MODE_HIGH_PITCH = 3
local CRY_MODE_ROAR_1 = 7
local CRY_MODE_ROAR_2 = 8
local CRY_MODE_GROWL_1 = 9
local CRY_MODE_GROWL_2 = 10
-- pokefirered/include/constants/sound.h:35
local DOUBLE_CRY_GROWL = 255
-- pokefirered/include/constants/battle_anim.h
local SOUND_PAN_ATTACKER = -64

local function cry_species(vm, battler)
  if not (vm and vm.resolveBattlerSide and vm.speciesForSide) then return nil end
  return vm:speciesForSide(vm:resolveBattlerSide(battler))
end

local function cry_pan(vm)
  if vm and vm.adjustPanning then return vm:adjustPanning(SOUND_PAN_ATTACKER) end
  return SOUND_PAN_ATTACKER
end

--- pokefirered/src/battle_anim_sound_tasks.c:158
function AnimTasks.SoundTask_PlayDoubleCry(t, vm)
  local Audio = require("src.core.game3.audio")
  if not t._inited then
    t._inited = true
    t._species = cry_species(vm, t.data[0])
    if not t._species then
      destroy_task(t)
      return
    end
    t._pan = cry_pan(vm)
    local growl = (t.data[1] == DOUBLE_CRY_GROWL or t.data[1] == -1)
    t._mode2 = growl and CRY_MODE_GROWL_2 or CRY_MODE_ROAR_2
    t._frames = 0
    Audio.playCry(t._species, {
      pan = t._pan,
      mode = growl and CRY_MODE_GROWL_1 or CRY_MODE_ROAR_1,
    })
    return
  end
  -- pokefirered/src/battle_anim_sound_tasks.c:201
  t._frames = (t._frames or 0) + 1
  if t._frames < 2 then return end
  if (not Audio.isCryFinished) or Audio.isCryFinished() then
    Audio.playCry(t._species, { pan = t._pan, mode = t._mode2 })
    destroy_task(t)
    return
  end
  if t._frames >= 150 then
    destroy_task(t)
  end
end

--- pokefirered/src/battle_anim_sound_tasks.c:228
function AnimTasks.SoundTask_WaitForCry(t, _vm)
  local Audio = require("src.core.game3.audio")
  t.data[14] = (t.data[14] or 0) + 1
  if t.data[14] < 2 then return end
  if (not Audio.isCryFinished) or Audio.isCryFinished() then
    destroy_task(t)
    return
  end
  if t.data[14] >= 300 then
    destroy_task(t)
  end
end

--- pokefirered/src/battle_anim_sound_tasks.c:140
function AnimTasks.SoundTask_PlayCryHighPitch(t, vm)
  local Audio = require("src.core.game3.audio")
  local species = cry_species(vm, t.data[0])
  if species then
    Audio.playCry(species, { pan = cry_pan(vm), mode = CRY_MODE_HIGH_PITCH })
  end
  destroy_task(t)
end

AnimTasks.REGISTRY.SoundTask_PlayDoubleCry = AnimTasks.SoundTask_PlayDoubleCry
AnimTasks.REGISTRY.SoundTask_WaitForCry = AnimTasks.SoundTask_WaitForCry
AnimTasks.REGISTRY.PlayDoubleCry = AnimTasks.SoundTask_PlayDoubleCry
AnimTasks.REGISTRY.SoundTask_PlayCryHighPitch = AnimTasks.SoundTask_PlayCryHighPitch

--- BlendColorCycle stub: nudge pal toward a tint for a few frames then restore.
function AnimTasks.BlendColorCycle(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local pal = vm.pals[0]
  if pal and frame == 0 then
    t.data[10] = 1 -- marked
    for i = 1, 15 do
      local c = pal[i]
      if c then
        c[1] = math.min(1, (c[1] or 0) + 0.15)
      end
    end
  end
  if frame >= 8 then
    if pal then
      pal[1] = { 1, 1, 1, 1 }
      pal[2] = { 1, 0.9, 0.2, 1 }
      pal[3] = { 1, 0.4, 0.1, 1 }
    end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.BlendColorCycle = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.AnimTask_BlendColorCycle = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.AnimTask_BlendColorCycleByTag = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.AnimTask_BlendColorCycleExclude = AnimTasks.BlendColorCycle

--- pret AnimTask_DefenseCurlDeformMon: squishes mon vertically/horizontally (2 cycles of 16 ticks = 32 ticks).
function AnimTasks.DefenseCurlDeformMon(t, vm)
  local side = vm:attackerSide()
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(side)
  if not p then
    destroy_task(t)
    return
  end
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  if frame < 32 then
    local phase = (frame % 16) / 16 * math.pi * 2
    local deform = math.sin(phase) * 0.22
    p.sx = 1.0 - deform * 0.8
    p.sy = 1.0 + deform
  else
    p.sx = 1.0
    p.sy = 1.0
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.DefenseCurlDeformMon = AnimTasks.DefenseCurlDeformMon
AnimTasks.REGISTRY.AnimTask_DefenseCurlDeformMon = AnimTasks.DefenseCurlDeformMon
AnimTasks.REGISTRY.StockpileDeformMon = AnimTasks.DefenseCurlDeformMon
AnimTasks.REGISTRY.AnimTask_StockpileDeformMon = AnimTasks.DefenseCurlDeformMon
AnimTasks.REGISTRY.SwallowDeformMon = AnimTasks.DefenseCurlDeformMon
AnimTasks.REGISTRY.AnimTask_SwallowDeformMon = AnimTasks.DefenseCurlDeformMon
AnimTasks.REGISTRY.SpitUpDeformMon = AnimTasks.DefenseCurlDeformMon
AnimTasks.REGISTRY.AnimTask_SpitUpDeformMon = AnimTasks.DefenseCurlDeformMon

--- pret AnimTask_DarkenBattleAnimBg: dims background during signature VFX.
function AnimTasks.DarkenBattleAnimBg(t, _vm)
  local Anim = require("src.core.game3.battle.anim")
  local stage = Anim.stage and Anim.stage()
  if not stage then
    destroy_task(t)
    return
  end
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  if frame < 8 then
    stage.bgDim = (frame / 8) * 0.85
  elseif frame < 24 then
    stage.bgDim = 0.85
  elseif frame < dur then
    stage.bgDim = (1.0 - (frame - 24) / 8) * 0.85
  else
    stage.bgDim = 0
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.DarkenBattleAnimBg = AnimTasks.DarkenBattleAnimBg
AnimTasks.REGISTRY.AnimTask_DarkenBattleAnimBg = AnimTasks.DarkenBattleAnimBg

--- pret AnimBowMon (pokefirered/src/battle_anim_effects_1.c:4451)
-- arg 0: step mode (0=bow start, 1=return slide, 2=hold & unbow, 3=end)
function AnimTasks.BowMon(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local stepMode = tonumber(t.data[0]) or 0
    local side = vm:attackerSide()
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._mode = stepMode
    t._frame = 0
    local dir = (side == "player") and -1 or 1
    if stepMode == 0 then
      t._dx = dir * 2
      t._dur = 6
    elseif stepMode == 1 then
      t._dx = -dir * 3
      t._dur = 4
    elseif stepMode == 2 then
      t._dur = 8
    else
      t._dur = 1
    end
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  t._frame = t._frame + 1
  if t._mode == 0 then
    if t._frame <= t._dur then
      p.ox = (p.ox or 0) + t._dx
    else
      p.rotation = (t._side == "player") and -0.05 or 0.05
      if t._frame > t._dur + 3 then
        destroy_task(t)
      end
    end
  elseif t._mode == 1 then
    if t._frame <= t._dur then
      p.ox = (p.ox or 0) + t._dx
    else
      destroy_task(t)
    end
  elseif t._mode == 2 then
    if t._frame > t._dur then
      p.rotation = 0
      destroy_task(t)
    end
  else
    p.rotation = 0
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.BowMon = AnimTasks.BowMon
AnimTasks.REGISTRY.AnimBowMon = AnimTasks.BowMon
AnimTasks.REGISTRY.AnimTask_BowMon = AnimTasks.BowMon

--- pret AnimShakeMonOrBattleTerrain (pokefirered/src/battle_anim_normal.c:771)
-- arg 0: offset, arg 1: frame delay, arg 2: duration, arg 3: target type (0=BG3_X, 1=BG3_Y, 2=spriteX, 3=spriteY)
function AnimTasks.ShakeMonOrBattleTerrain(t, _vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    t._offset = tonumber(t.data[0]) or 4
    t._delay = math.max(1, tonumber(t.data[1]) or 2)
    t._duration = math.max(1, tonumber(t.data[2]) or 16)
    t._targetType = tonumber(t.data[3]) or 0
    t._timer = t._delay
    t._stage = Anim.stage()
    t._curOff = t._offset
  end
  local st = t._stage
  if t._duration > 0 then
    t._duration = t._duration - 1
    if t._timer > 0 then
      t._timer = t._timer - 1
    else
      t._timer = t._delay
      t._curOff = -t._curOff
      if t._targetType == 0 or t._targetType == 2 then
        if st and st.bgSlide then
          st.bgSlide.playerOx = t._curOff
          st.bgSlide.enemyOx = t._curOff
        end
      end
    end
  else
    if st and st.bgSlide then
      st.bgSlide.playerOx = 0
      st.bgSlide.enemyOx = 0
    end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.ShakeMonOrBattleTerrain = AnimTasks.ShakeMonOrBattleTerrain
AnimTasks.REGISTRY.AnimShakeMonOrBattleTerrain = AnimTasks.ShakeMonOrBattleTerrain
AnimTasks.REGISTRY.AnimTask_ShakeMonOrBattleTerrain = AnimTasks.ShakeMonOrBattleTerrain

--- pret AnimTask_CreateSurfWave (pokefirered/src/battle_anim_water.c:799):
-- Authentic multi-phase surging tidal wave with GBA scanline displacement, dynamic sine foam crests, and collision impact.
function AnimTasks.CreateSurfWave(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local totalDur = 46

  local atkSide = vm:attackerSide()
  local tgtSide = vm:resolveBattlerSide("target")
  local Anim = require("src.core.game3.battle.anim")
  local pTgt = Anim.present(tgtSide)
  local pAtk = Anim.present(atkSide)

  local isMuddy = (t.data[0] == 1 or t.data[8] == 1 or (t.name and t.name:find("Muddy")))
  t.data[8] = isMuddy and 1 or 0
  t.z = AnimSprites.Z.GLOBAL_FRONT

  -- Initial setup matching GBA AnimTask_CreateSurfWave
  if frame == 1 then
    if atkSide == "player" then
      t.data[0] = -2   -- dx
      t.data[1] = 1    -- dy
      t.data[10] = 0   -- scrollX
      t.data[11] = -48 -- scrollY
    else
      t.data[0] = 2
      t.data[1] = -1
      t.data[10] = -224
      t.data[11] = 256
    end
    t._particles = {}
  end

  -- Update scroll offsets
  t.data[10] = (t.data[10] or 0) + (t.data[0] or -2)
  t.data[11] = (t.data[11] or 0) + (t.data[1] or 1)

  -- GBA Alpha Blending Curve (0 -> 14/16 -> 0)
  local alpha = 0
  if frame <= 14 then
    alpha = (frame / 14) * (14 / 16)
  elseif frame <= 34 then
    alpha = 14 / 16
  else
    alpha = math.max(0, (14 / 16) * (1 - (frame - 34) / 12))
  end
  t._alpha = alpha

  -- 1. Attacker lunges slightly forward on wave launch (frames 1..12)
  if frame < 12 and pAtk then
    local u = frame / 12
    local dir = (atkSide == "player") and 1 or -1
    pAtk.ox = math.floor(math.sin(u * math.pi) * 8 * dir)
  elseif frame >= 12 and pAtk and pAtk.ox ~= 0 then
    pAtk.ox = 0
  end

  -- 2. Wave impact & collision shudder on target (frames 16..38)
  if frame >= 16 and frame < 38 and pTgt then
    local phase = frame % 4
    local amp = math.max(1, math.floor(5 * (1 - (frame - 16) / 22)))
    pTgt.ox = (phase == 0 or phase == 3) and amp or -amp
    pTgt.oy = (phase == 1 or phase == 2) and amp or -amp
    pTgt.flash = frame
  elseif frame >= 38 and pTgt then
    pTgt.ox = 0
    pTgt.oy = 0
    pTgt.flash = 0
  end

  -- 3. Procedural water splash & droplet particles around target on impact
  if frame >= 16 and frame <= 34 and frame % 2 == 0 then
    local tx, ty = vm:battlerCenter(tgtSide)
    t._particles = t._particles or {}
    for _ = 1, 3 do
      t._particles[#t._particles + 1] = {
        x = tx + math.random(-24, 24),
        y = ty + math.random(-16, 16),
        vx = (math.random() - 0.5) * 3,
        vy = -(math.random() * 2.5 + 1.5),
        life = 0,
        maxLife = math.random(10, 18),
        size = math.random(2, 4),
      }
    end
  end

  -- Update active particles
  if t._particles then
    local alive = {}
    for _, p in ipairs(t._particles) do
      p.life = p.life + 1
      p.x = p.x + p.vx
      p.y = p.y + p.vy
      p.vy = p.vy + 0.15 -- gravity
      if p.life < p.maxLife then
        alive[#alive + 1] = p
      end
    end
    t._particles = alive
  end

  -- 4. Draw callback attached directly to task
  t.draw = function(task, _vm)
    local a = task._alpha or 0
    if a <= 0.01 then return end
    if not (love and love.graphics) then return end

    local isMud = (task.data[8] == 1)
    local rFill, gFill, bFill = 0.12, 0.52, 0.90
    local rDeep, gDeep, bDeep = 0.05, 0.30, 0.65
    local rCrest, gCrest, bCrest = 0.94, 0.97, 1.00
    local rShimmer, gShimmer, bShimmer = 0.40, 0.75, 1.00
    if isMud then
      rFill, gFill, bFill = 0.56, 0.40, 0.22
      rDeep, gDeep, bDeep = 0.36, 0.24, 0.12
      rCrest, gCrest, bCrest = 0.86, 0.78, 0.62
      rShimmer, gShimmer, bShimmer = 0.70, 0.55, 0.35
    end

    local scrollX = task.data[10] or 0
    local isPlr = (atkSide == "player")
    local f = task.data[14] or 1

    -- GBA Scanline Swelling & Full-Screen Tidal Wave Engulfment
    -- Wave crest swells and rises to engulf the whole screen (0..112)
    local surgeProgress = 0
    if f <= 20 then
      surgeProgress = f / 20 -- rising surge (0 -> 1)
    elseif f <= 34 then
      surgeProgress = 1.0    -- full screen engulfment peak
    else
      surgeProgress = math.max(0, 1.0 - (f - 34) / 12) -- receding drain (1 -> 0)
    end

    -- Swell baseline: Player surge rises from 95 up to -10 (engulfs entire arena); Opponent crashes from 0 down to 112
    local baselineY = 0
    if isPlr then
      baselineY = 95 - (surgeProgress * 105) + math.floor(Sin((scrollX * 2) % 256, 4))
    else
      baselineY = 15 + (surgeProgress * 85) + math.floor(Sin((scrollX * 2) % 256, 4))
    end

    -- Build smooth wave crest polygon across the full screen width (0..240)
    local numSegs = 32
    local stepX = 240 / numSegs
    local pts = {}
    for i = 0, numSegs do
      local sx = i * stepX
      local wavePhase1 = (sx * 3 + scrollX * 4) % 256
      local wavePhase2 = (sx * 6 - scrollX * 5) % 256
      local waveAmp = (6 + math.floor(surgeProgress * 8)) + Sin((f * 6) % 256, 3)
      local waveH = Sin(wavePhase1, waveAmp) + Sin(wavePhase2, 3)
      -- Dynamic surge slope from attacker side across to target
      local slopeProgress = math.min(1.0, f / 18)
      local slope = isPlr and (((sx / 240) * 20 - 10) * (1 - slopeProgress * 0.5))
                           or ((((240 - sx) / 240) * 20 - 10) * (1 - slopeProgress * 0.5))
      local sy = baselineY + waveH - slope
      pts[#pts + 1] = { x = sx, y = math.min(112, sy) }
    end

    -- 1. Fill deep water body across the entire battle arena (y = 0..112)
    local poly = {}
    for _, pt in ipairs(pts) do
      poly[#poly + 1] = pt.x
      poly[#poly + 1] = pt.y
    end
    poly[#poly + 1] = 240
    poly[#poly + 1] = 112
    poly[#poly + 1] = 0
    poly[#poly + 1] = 112

    if #poly >= 6 then
      love.graphics.setColor(rDeep, gDeep, bDeep, a * 0.75)
      love.graphics.polygon("fill", poly)

      -- 2. Mid water surge layer with offset
      local midPoly = {}
      for _, pt in ipairs(pts) do
        midPoly[#midPoly + 1] = pt.x
        midPoly[#midPoly + 1] = pt.y + 4
      end
      midPoly[#midPoly + 1] = 240
      midPoly[#midPoly + 1] = 112
      midPoly[#midPoly + 1] = 0
      midPoly[#midPoly + 1] = 112
      if #midPoly >= 6 then
        love.graphics.setColor(rFill, gFill, bFill, a * 0.85)
        love.graphics.polygon("fill", midPoly)
      end
    end

    -- 3. Shimmering horizontal wave scanline bands
    love.graphics.setColor(rShimmer, gShimmer, bShimmer, a * 0.55)
    for _, pt in ipairs(pts) do
      if pt.x % 16 < stepX then
        love.graphics.line(pt.x, pt.y + 8, pt.x + 10, pt.y + 8)
        love.graphics.line(pt.x + 4, pt.y + 16, pt.x + 14, pt.y + 16)
        love.graphics.line(pt.x + 2, pt.y + 24, pt.x + 12, pt.y + 24)
        love.graphics.line(pt.x + 6, pt.y + 36, pt.x + 18, pt.y + 36)
      end
    end

    -- 4. White foam crest along the leading wave ridge
    love.graphics.setColor(rCrest, gCrest, bCrest, a * 0.95)
    love.graphics.setLineWidth(2.5)
    for i = 1, #pts - 1 do
      love.graphics.line(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y)
      if i % 3 == 0 then
        love.graphics.circle("fill", pts[i].x, pts[i].y - 1, 2.0)
      end
    end
    love.graphics.setLineWidth(1)

    -- 5. Splashing spray droplets
    if task._particles then
      for _, p in ipairs(task._particles) do
        local pAlpha = a * (1 - p.life / p.maxLife)
        love.graphics.setColor(rCrest, gCrest, bCrest, pAlpha)
        love.graphics.circle("fill", p.x, p.y, p.size)
      end
    end

    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= totalDur then
    if pTgt then pTgt.ox = 0; pTgt.oy = 0; pTgt.flash = 0 end
    if pAtk then pAtk.ox = 0 end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.CreateSurfWave = AnimTasks.CreateSurfWave
AnimTasks.REGISTRY.AnimTask_CreateSurfWave = AnimTasks.CreateSurfWave

--- pret AnimTask_WaterSport / AnimTask_Splash: water droplets and splashing fountain.
function AnimTasks.WaterSport(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  local side = vm:attackerSide()
  local cx, cy = vm:battlerCenter(side)
  local pack = vm._pack

  if frame < 16 and frame % 3 == 0 then
    local imgMeta = pack and pack.tags and (pack.tags["WATER_DROPLET"] or pack.tags["BUBBLE"] or pack.tags["WATER_ORB"])
    if imgMeta and imgMeta.image then
      for _ = 1, 3 do
        local vx = math.random(-25, 25) / 10
        local vy = -math.random(30, 50) / 10
        local spr = AnimSprites.acquire({
          x = cx + math.random(-12, 12),
          y = cy + math.random(-8, 8),
          z = AnimSprites.Z.FRONT,
          image = imgMeta.image,
          w = imgMeta.frameW or 16,
          h = imgMeta.frameH or 16,
          tag = "WATER_DROPLET",
          callback = function(s)
            s.data[0] = (s.data[0] or 0) + 1
            local step = s.data[0]
            s.ox = math.floor(vx * step)
            s.oy = math.floor(vy * step + 0.5 * 0.35 * step^2)
            s.alpha = math.max(0, 1 - step / 20)
            if step >= 20 then AnimSprites.release(s) end
          end,
        })
        if spr then
          spr._baseW = imgMeta.frameW or 16
          spr._baseH = imgMeta.frameH or 16
        end
      end
    end
  end

  if frame >= dur then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.WaterSport = AnimTasks.WaterSport
AnimTasks.REGISTRY.AnimTask_WaterSport = AnimTasks.WaterSport
AnimTasks.REGISTRY.Splash = AnimTasks.WaterSport
AnimTasks.REGISTRY.AnimTask_Splash = AnimTasks.WaterSport

--- pret AnimTask_InvertScreenColor / AnimTask_HardwarePaletteFade / AnimTask_FadeScreenToWhite: GLSL screen effect shaders.
function AnimTasks.InvertScreenColor(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = math.max(8, tonumber(t.data[0]) or 16)
  local Anim = require("src.core.game3.battle.anim")

  -- Flash screen negative every 4 frames (2 frames on, 2 frames off)
  if (frame % 4 < 2) and frame < dur then
    Anim.setScreenEffect({ type = "invert", coeff = 1.0 })
  else
    Anim.setScreenEffect(nil)
  end

  if frame >= dur then
    Anim.setScreenEffect(nil)
    destroy_task(t)
  end
end

function AnimTasks.FlashAnimTagWithColor(t, _vm)
  if not t._inited then
    t._inited = true
    local tag = t.data[0] or 0
    local delay = math.max(1, tonumber(t.data[1]) or 2)
    local numFlashes = math.max(1, tonumber(t.data[2]) or 1)
    local color = t.data[3] or 0
    local coeff = tonumber(t.data[4]) or 16
    t._tag = tag
    t._delay = delay
    t._flashesLeft = numFlashes
    t._color = color
    t._coeff = coeff
    t._timer = delay
  end

  t._timer = t._timer - 1
  if t._timer <= 0 then
    t._timer = t._delay
    t._flashesLeft = t._flashesLeft - 1
    if t._flashesLeft <= 0 then
      destroy_task(t)
    end
  end
end

AnimTasks.REGISTRY.InvertScreenColor = AnimTasks.InvertScreenColor
AnimTasks.REGISTRY.AnimTask_InvertScreenColor = AnimTasks.InvertScreenColor
AnimTasks.REGISTRY.FlashAnimTagWithColor = AnimTasks.FlashAnimTagWithColor
AnimTasks.REGISTRY.AnimTask_FlashAnimTagWithColor = AnimTasks.FlashAnimTagWithColor

function AnimTasks.FadeScreenToWhite(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = math.max(10, tonumber(t.data[0]) or 20)
  local Anim = require("src.core.game3.battle.anim")

  local u = math.sin((frame / dur) * math.pi)
  Anim.setScreenEffect({ type = "fade_white", coeff = u })

  if frame >= dur then
    Anim.setScreenEffect(nil)
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.FadeScreenToWhite = AnimTasks.FadeScreenToWhite
AnimTasks.REGISTRY.AnimTask_FadeScreenToWhite = AnimTasks.FadeScreenToWhite

function AnimTasks.HardwarePaletteFade(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local delay = math.max(1, tonumber(t.data[1]) or 2)
  local startCoeff = tonumber(t.data[2]) or 0
  local targetCoeff = tonumber(t.data[3]) or 10
  local totalSteps = math.max(1, math.abs(targetCoeff - startCoeff))
  local dur = math.max(6, delay * totalSteps)
  local Anim = require("src.core.game3.battle.anim")

  local progress = math.min(1.0, frame / dur)
  local curCoeff = (startCoeff + (targetCoeff - startCoeff) * progress) / 16
  Anim.setScreenEffect({ type = "fade_black", coeff = curCoeff })

  if frame >= dur then
    if targetCoeff == 0 then
      Anim.setScreenEffect(nil)
    end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.HardwarePaletteFade = AnimTasks.HardwarePaletteFade
AnimTasks.REGISTRY.AnimTask_HardwarePaletteFade = AnimTasks.HardwarePaletteFade

--- pret AnimTask_HorizontalShake / AnimTask_ShakeBattleTerrain (pokefirered/src/battle_anim_ground.c:555)
-- arg 0: what to shake (0-3 battler, 4 all battlers, 5 terrain); arg 1: shake intensity; arg 2: length of time
function AnimTasks.HorizontalShake(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local intensity = tonumber(t.data[1]) or 0
    if intensity == 0 then
      intensity = math.floor((vm.movePower or 80) / 10) + 3
    else
      intensity = intensity + 3
    end
    t._intensity = intensity
    t._curOffset = intensity
    t._maxTime = math.max(1, tonumber(t.data[2]) or 16)
    t._which = t.data[0]
    t._state = 0
    t._delay = 0
    t._timer = 0
    t._stage = Anim.stage()
  end
  local st = t._stage
  if t._state == 0 then
    t._delay = t._delay + 1
    if t._delay > 1 then
      t._delay = 0
      local off = (t._timer % 2 == 0) and t._intensity or -t._intensity
      if st and st.bgSlide then
        st.bgSlide.playerOx = off
        st.bgSlide.enemyOx = off
      end
      t._timer = t._timer + 1
      if t._timer >= t._maxTime then
        t._timer = 0
        t._curOffset = t._curOffset - 1
        t._state = 1
      end
    end
  elseif t._state == 1 then
    t._delay = t._delay + 1
    if t._delay > 1 then
      t._delay = 0
      local off = (t._timer % 2 == 0) and t._curOffset or -t._curOffset
      if st and st.bgSlide then
        st.bgSlide.playerOx = off
        st.bgSlide.enemyOx = off
      end
      t._timer = t._timer + 1
      if t._timer >= 4 then
        t._timer = 0
        t._curOffset = t._curOffset - 1
        if t._curOffset <= 0 then
          t._state = 2
        end
      end
    end
  elseif t._state == 2 then
    if st and st.bgSlide then
      st.bgSlide.playerOx = 0
      st.bgSlide.enemyOx = 0
    end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.HorizontalShake = AnimTasks.HorizontalShake
AnimTasks.REGISTRY.AnimTask_HorizontalShake = AnimTasks.HorizontalShake
AnimTasks.REGISTRY.ShakeBattleTerrain = AnimTasks.HorizontalShake
AnimTasks.REGISTRY.AnimTask_ShakeBattleTerrain = AnimTasks.HorizontalShake
AnimTasks.REGISTRY.ShakeBattlers = AnimTasks.HorizontalShake
AnimTasks.REGISTRY.ShakeTerrain = AnimTasks.HorizontalShake

--- pret AnimTask_ShakeTargetBasedOnMovePowerOrDmg (pokefirered/src/battle_anim_mon_movement.c:872)
-- arg 0: 0=power, 1=dmg; arg 1: frame delay; arg 2: num shakes; arg 3: shakeX; arg 4: shakeY
function AnimTasks.ShakeTargetBasedOnMovePowerOrDmg(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local mode = tonumber(t.data[0]) or 0
    local val = (mode == 0) and (vm.movePower or 60) or (vm.moveDmg or 60)
    local intensity = math.max(1, math.min(16, math.floor(val / 12)))
    t._half = math.floor(intensity / 2)
    t._plusOdd = t._half + (intensity % 2)
    t._intensity = intensity
    t._delay = math.max(1, tonumber(t.data[1]) or 2)
    t._numShakes = math.max(1, tonumber(t.data[2]) or 4)
    t._shakeX = (tonumber(t.data[3]) or 0) ~= 0
    t._shakeY = (tonumber(t.data[4]) or 0) ~= 0
    t._side = vm:targetSide()
    t._p = Anim.present(t._side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._origX = t._p.ox or 0
    t._origY = t._p.oy or 0
    t._phase = 0
    t._timer = 0
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  t._timer = t._timer + 1
  if t._timer > t._delay then
    t._timer = 0
    t._phase = (t._phase + 1) % 2
    if t._shakeX then
      if t._phase == 1 then
        p.ox = t._origX + t._plusOdd
      else
        p.ox = t._origX - t._half
      end
    end
    if t._shakeY then
      if t._phase == 1 then
        p.oy = t._intensity
      else
        p.oy = 0
      end
    end
    t._numShakes = t._numShakes - 1
    if t._numShakes <= 0 then
      p.ox = 0
      p.oy = 0
      destroy_task(t)
    end
  end
end

AnimTasks.REGISTRY.ShakeTargetBasedOnMovePowerOrDmg = AnimTasks.ShakeTargetBasedOnMovePowerOrDmg
AnimTasks.REGISTRY.AnimTask_ShakeTargetBasedOnMovePowerOrDmg = AnimTasks.ShakeTargetBasedOnMovePowerOrDmg

-- pokefirered/src/battle_anim_fire.c:1254

--- RGB555 unpacker helper (pokefirered RGB_*)
local function unpackRgb555(col)
  if type(col) == "table" then
    local r = (col[1] or 0) > 1 and (col[1] / 31) or (col[1] or 0)
    local g = (col[2] or 0) > 1 and (col[2] / 31) or (col[2] or 0)
    local b = (col[3] or 0) > 1 and (col[3] / 31) or (col[3] or 0)
    return r, g, b
  end
  local c = tonumber(col) or 0
  local r = (c % 32) / 31
  local g = (math.floor(c / 32) % 32) / 31
  local b = (math.floor(c / 1024) % 32) / 31
  return r, g, b
end

--- pret AnimTask_BlendBattleAnimPal (pokefirered/src/battle_anim_utility_funcs.c:53)
-- arg 0: pal selector bitfield, arg 1: delay, arg 2: startCoeff, arg 3: targetCoeff, arg 4: color
function AnimTasks.BlendBattleAnimPal(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local palMask = tonumber(t.data[0]) or 0
    local delay = math.max(0, tonumber(t.data[1]) or 0)
    local startCoeff = math.max(0, math.min(16, tonumber(t.data[2]) or 0))
    local targetCoeff = math.max(0, math.min(16, tonumber(t.data[3]) or 0))
    local color = t.data[4] or 0
    local r, g, b = unpackRgb555(color)
    t._palMask = palMask
    t._delay = delay
    t._currCoeff = startCoeff
    t._targetCoeff = targetCoeff
    t._color = { r, g, b }
    t._timer = 0
  end

  if (t._timer or 0) <= 0 then
    t._timer = t._delay
    local coeff = t._currCoeff / 16
    local r, g, b = t._color[1], t._color[2], t._color[3]
    local palMask = t._palMask

    -- Bit 0: Background
    if (palMask % 2) == 1 then
      local fxType = "custom_blend"
      if r == 1 and g == 1 and b == 1 then fxType = "fade_white"
      elseif r == 0 and g == 0 and b == 0 then fxType = "fade_black" end
      if coeff > 0 then
        Anim.setScreenEffect({ type = fxType, coeff = coeff, targetColor = { r, g, b } })
      else
        Anim.setScreenEffect(nil)
      end
    end

    -- Battler palettes: bit 1 (atk), bit 2 (tgt), bit 7 (player), bit 9 (enemy)
    local atkPresent = Anim.present(vm:attackerSide())
    local tgtPresent = Anim.present(vm:targetSide())
    local isAtkSelected = (math.floor(palMask / 2) % 2 == 1)
    local isTgtSelected = (math.floor(palMask / 4) % 2 == 1)
    if (math.floor(palMask / 128) % 2 == 1) then -- player
      if vm:attackerSide() == "player" then isAtkSelected = true else isTgtSelected = true end
    end
    if (math.floor(palMask / 512) % 2 == 1) then -- enemy
      if vm:attackerSide() == "enemy" then isAtkSelected = true else isTgtSelected = true end
    end

    if isAtkSelected and atkPresent then
      atkPresent.blendColor = { r, g, b }
      atkPresent.blendCoeff = coeff
      atkPresent.darken = (r == 0 and g == 0 and b == 0) and coeff or 0
      atkPresent.flash = (r == 1 and g == 1 and b == 1) and (coeff > 0 and 1 or 0) or 0
    end
    if isTgtSelected and tgtPresent then
      tgtPresent.blendColor = { r, g, b }
      tgtPresent.blendCoeff = coeff
      tgtPresent.darken = (r == 0 and g == 0 and b == 0) and coeff or 0
      tgtPresent.flash = (r == 1 and g == 1 and b == 1) and (coeff > 0 and 1 or 0) or 0
    end

    local finished = (t._currCoeff == t._targetCoeff)
    if t._currCoeff < t._targetCoeff then
      t._currCoeff = t._currCoeff + 1
    elseif t._currCoeff > t._targetCoeff then
      t._currCoeff = t._currCoeff - 1
    end

    if finished then
      if t._targetCoeff == 0 then
        if (palMask % 2) == 1 then Anim.setScreenEffect(nil) end
        if isAtkSelected and atkPresent then
          atkPresent.blendCoeff = 0
          atkPresent.darken = 0
          atkPresent.flash = 0
        end
        if isTgtSelected and tgtPresent then
          tgtPresent.blendCoeff = 0
          tgtPresent.darken = 0
          tgtPresent.flash = 0
        end
      end
      destroy_task(t)
    end
  else
    t._timer = t._timer - 1
  end
end

AnimTasks.REGISTRY.BlendBattleAnimPal = AnimTasks.BlendBattleAnimPal
AnimTasks.REGISTRY.AnimTask_BlendBattleAnimPal = AnimTasks.BlendBattleAnimPal

--- pret AnimTask_BlendColorCycle / BlendColorCycleExclude / BlendColorCycleByTag (pokefirered/src/battle_anim_normal.c:424, 484, 559)
-- arg 0: pal selector, arg 1: delay, arg 2: numBlends, arg 3: initialBlend, arg 4: targetBlend, arg 5: color
function AnimTasks.BlendColorCycle(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local palMask = tonumber(t.data[0]) or 0
    local delay = math.max(0, tonumber(t.data[1]) or 0)
    local numBlends = math.max(1, tonumber(t.data[2]) or 1)
    local initialBlend = tonumber(t.data[3]) or 0
    local targetBlend = tonumber(t.data[4]) or 16
    local color = t.data[5] or 0
    local r, g, b = unpackRgb555(color)
    t._palMask = palMask
    t._delay = delay
    t._numBlends = numBlends
    t._initialBlend = initialBlend
    t._targetBlend = targetBlend
    t._color = { r, g, b }
    t._currCoeff = initialBlend
    t._targetCoeff = targetBlend
    t._timer = 0
    t._restore = false
  end

  if (t._timer or 0) <= 0 then
    t._timer = t._delay
    local coeff = t._currCoeff / 16
    local r, g, b = t._color[1], t._color[2], t._color[3]
    local palMask = t._palMask

    -- Screen / BG
    if (palMask % 2) == 1 then
      local fxType = "custom_blend"
      if r == 1 and g == 1 and b == 1 then fxType = "fade_white"
      elseif r == 0 and g == 0 and b == 0 then fxType = "fade_black" end
      if coeff > 0 then
        Anim.setScreenEffect({ type = fxType, coeff = coeff, targetColor = { r, g, b } })
      else
        Anim.setScreenEffect(nil)
      end
    end

    -- Battlers
    local atkPresent = Anim.present(vm:attackerSide())
    local tgtPresent = Anim.present(vm:targetSide())
    local isAtkSelected = (math.floor(palMask / 2) % 2 == 1)
    local isTgtSelected = (math.floor(palMask / 4) % 2 == 1)
    if isAtkSelected and atkPresent then
      atkPresent.blendColor = { r, g, b }
      atkPresent.blendCoeff = coeff
      atkPresent.darken = (r == 0 and g == 0 and b == 0) and coeff or 0
      atkPresent.flash = (r == 1 and g == 1 and b == 1) and (coeff > 0 and 1 or 0) or 0
    end
    if isTgtSelected and tgtPresent then
      tgtPresent.blendColor = { r, g, b }
      tgtPresent.blendCoeff = coeff
      tgtPresent.darken = (r == 0 and g == 0 and b == 0) and coeff or 0
      tgtPresent.flash = (r == 1 and g == 1 and b == 1) and (coeff > 0 and 1 or 0) or 0
    end

    if t._currCoeff < t._targetCoeff then
      t._currCoeff = t._currCoeff + 1
    elseif t._currCoeff > t._targetCoeff then
      t._currCoeff = t._currCoeff - 1
    else
      t._numBlends = t._numBlends - 1
      if t._numBlends > 0 then
        t._restore = not t._restore
        if t._restore then
          t._targetCoeff = (t._numBlends == 1) and 0 or t._initialBlend
        else
          t._targetCoeff = t._targetBlend
        end
      else
        if (palMask % 2) == 1 then Anim.setScreenEffect(nil) end
        if isAtkSelected and atkPresent then
          atkPresent.blendCoeff = 0
          atkPresent.darken = 0
          atkPresent.flash = 0
        end
        if isTgtSelected and tgtPresent then
          tgtPresent.blendCoeff = 0
          tgtPresent.darken = 0
          tgtPresent.flash = 0
        end
        destroy_task(t)
      end
    end
  else
    t._timer = t._timer - 1
  end
end

AnimTasks.REGISTRY.BlendColorCycle = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.AnimTask_BlendColorCycle = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.BlendColorCycleExclude = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.AnimTask_BlendColorCycleExclude = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.BlendColorCycleByTag = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.AnimTask_BlendColorCycleByTag = AnimTasks.BlendColorCycle

--- pret AnimComplexPaletteBlend (pokefirered/src/battle_anim_normal.c:339)
-- arg 0: palMask, arg 1: delay, arg 2: numCycles, arg 3: color1, arg 4: coeff1, arg 5: color2, arg 6: coeff2
function AnimTasks.ComplexPaletteBlend(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local palMask = tonumber(t.data[0]) or 0
    local delay = math.max(1, tonumber(t.data[1]) or 1)
    local numCycles = math.max(1, tonumber(t.data[2]) or 1)
    local color1 = t.data[3] or 0
    local coeff1 = (tonumber(t.data[4]) or 16) / 16
    local color2 = t.data[5] or 0
    local coeff2 = (tonumber(t.data[6]) or 0) / 16
    local r1, g1, b1 = unpackRgb555(color1)
    local r2, g2, b2 = unpackRgb555(color2)
    t._palMask = palMask
    t._delay = delay
    t._cyclesLeft = numCycles
    t._c1 = { r1, g1, b1 }
    t._k1 = coeff1
    t._c2 = { r2, g2, b2 }
    t._k2 = coeff2
    t._phase = 0
    t._timer = delay

    -- Initial blend 1
    local isAtk = (math.floor(palMask / 2) % 2 == 1)
    local isTgt = (math.floor(palMask / 4) % 2 == 1)
    local atkP = Anim.present(vm:attackerSide())
    local tgtP = Anim.present(vm:targetSide())
    if isAtk and atkP then
      atkP.blendColor = t._c1
      atkP.blendCoeff = t._k1
      atkP.darken = (r1 == 0 and g1 == 0 and b1 == 0) and t._k1 or 0
      atkP.flash = (r1 == 1 and g1 == 1 and b1 == 1) and (t._k1 > 0 and 1 or 0) or 0
    end
    if isTgt and tgtP then
      tgtP.blendColor = t._c1
      tgtP.blendCoeff = t._k1
      tgtP.darken = (r1 == 0 and g1 == 0 and b1 == 0) and t._k1 or 0
      tgtP.flash = (r1 == 1 and g1 == 1 and b1 == 1) and (t._k1 > 0 and 1 or 0) or 0
    end
  end

  t._timer = t._timer - 1
  if t._timer <= 0 then
    t._timer = t._delay
    if t._cyclesLeft <= 0 then
      local palMask = t._palMask
      local isAtk = (math.floor(palMask / 2) % 2 == 1)
      local isTgt = (math.floor(palMask / 4) % 2 == 1)
      local atkP = Anim.present(vm:attackerSide())
      local tgtP = Anim.present(vm:targetSide())
      if (palMask % 2) == 1 then Anim.setScreenEffect(nil) end
      if isAtk and atkP then atkP.blendCoeff = 0; atkP.darken = 0; atkP.flash = 0 end
      if isTgt and tgtP then tgtP.blendCoeff = 0; tgtP.darken = 0; tgtP.flash = 0 end
      destroy_task(t)
    else
      t._phase = 1 - t._phase
      local c = (t._phase == 0) and t._c1 or t._c2
      local k = (t._phase == 0) and t._k1 or t._k2
      local palMask = t._palMask
      local isAtk = (math.floor(palMask / 2) % 2 == 1)
      local isTgt = (math.floor(palMask / 4) % 2 == 1)
      local atkP = Anim.present(vm:attackerSide())
      local tgtP = Anim.present(vm:targetSide())
      if isAtk and atkP then
        atkP.blendColor = c
        atkP.blendCoeff = k
        atkP.darken = (c[1] == 0 and c[2] == 0 and c[3] == 0) and k or 0
        atkP.flash = (c[1] == 1 and c[2] == 1 and c[3] == 1) and (k > 0 and 1 or 0) or 0
      end
      if isTgt and tgtP then
        tgtP.blendColor = c
        tgtP.blendCoeff = k
        tgtP.darken = (c[1] == 0 and c[2] == 0 and c[3] == 0) and k or 0
        tgtP.flash = (c[1] == 1 and c[2] == 1 and c[3] == 1) and (k > 0 and 1 or 0) or 0
      end
      t._cyclesLeft = t._cyclesLeft - 1
    end
  end
end

AnimTasks.REGISTRY.ComplexPaletteBlend = AnimTasks.ComplexPaletteBlend
AnimTasks.REGISTRY.AnimComplexPaletteBlend = AnimTasks.ComplexPaletteBlend

--- pret AnimTask_BlendBattleAnimPalExclude (pokefirered/src/battle_anim_utility_funcs.c:75)
function AnimTasks.BlendBattleAnimPalExclude(t, vm)
  local cmd = tonumber(t.data[0]) or 0
  -- Map exclude cmd to palMask:
  -- 0: Not attacker (blend target and BG -> bit 0 | bit 2 = 5)
  -- 1: Not target (blend attacker and BG -> bit 0 | bit 1 = 3)
  -- 2: Not attacker nor BG (blend target only -> bit 2 = 4)
  -- 3: Not target nor BG (blend attacker only -> bit 1 = 2)
  -- 4: Neither attacker nor target (blend BG only -> bit 0 = 1)
  -- 5: Blend all (bit 0 | bit 1 | bit 2 = 7)
  -- 6: Neither bg nor attacker partner (blend target = 4)
  -- 7: Neither bg nor target partner (blend attacker = 2)
  local maskMap = { [0] = 5, [1] = 3, [2] = 4, [3] = 2, [4] = 1, [5] = 7, [6] = 4, [7] = 2 }
  local palMask = maskMap[cmd] or 7
  t.data[0] = palMask
  AnimTasks.BlendBattleAnimPal(t, vm)
end

AnimTasks.REGISTRY.BlendBattleAnimPalExclude = AnimTasks.BlendBattleAnimPalExclude
AnimTasks.REGISTRY.AnimTask_BlendBattleAnimPalExclude = AnimTasks.BlendBattleAnimPalExclude

--- pret AnimTask_SetCamouflageBlend (pokefirered/src/battle_anim_utility_funcs.c:123)
function AnimTasks.SetCamouflageBlend(t, vm)
  local TERRAIN_COLORS = {
    grass = 0x0718,       -- RGB(12, 24, 2)
    long_grass = 0x05E0,  -- RGB(0, 15, 2)
    sand = 0x2F1E,        -- RGB(30, 24, 11)
    water = 0x7ECA,       -- RGB(11, 22, 31)
    cave = 0x0D2E,        -- RGB(14, 9, 3)
    building = 0x7FFF,    -- RGB(31, 31, 31)
    plain = 0x7FFF,       -- RGB(31, 31, 31)
  }
  t.data[4] = TERRAIN_COLORS.plain
  AnimTasks.BlendBattleAnimPal(t, vm)
end

AnimTasks.REGISTRY.SetCamouflageBlend = AnimTasks.SetCamouflageBlend
AnimTasks.REGISTRY.AnimTask_SetCamouflageBlend = AnimTasks.SetCamouflageBlend

--- pret AnimTask_BlendParticle (pokefirered/src/battle_anim_utility_funcs.c:163)
function AnimTasks.BlendParticle(t, vm)
  t.data[0] = 1 -- BG / particle palette
  AnimTasks.BlendBattleAnimPal(t, vm)
end

AnimTasks.REGISTRY.BlendParticle = AnimTasks.BlendParticle
AnimTasks.REGISTRY.AnimTask_BlendParticle = AnimTasks.BlendParticle

--- pret AnimTask_BlendMonInAndOut (pokefirered/src/battle_anim_mons.c:1603)
-- arg 0: battler, arg 1: color, arg 2: targetCoeff, arg 3: delay, arg 4: repeats
function AnimTasks.BlendMonInAndOut(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local whichMon = t.data[0] or 0
    local color = t.data[1] or 0
    local targetCoeff = tonumber(t.data[2]) or 16
    local delay = math.max(0, tonumber(t.data[3]) or 0)
    local repeats = math.max(1, tonumber(t.data[4]) or 1)
    local r, g, b = unpackRgb555(color)
    local side = vm:resolveBattlerSide(whichMon)
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._targetCoeff = targetCoeff
    t._delay = delay
    t._repeats = repeats
    t._color = { r, g, b }
    t._currCoeff = 0
    t._dir = 0 -- 0=in, 1=out
    t._timer = 0
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  if (t._timer or 0) <= 0 then
    t._timer = t._delay
    local r, g, b = t._color[1], t._color[2], t._color[3]
    local coeff = t._currCoeff / 16
    p.blendColor = { r, g, b }
    p.blendCoeff = coeff
    p.darken = (r == 0 and g == 0 and b == 0) and coeff or 0
    p.flash = (r == 1 and g == 1 and b == 1) and (coeff > 0 and 1 or 0) or 0

    if t._dir == 0 then
      t._currCoeff = t._currCoeff + 1
      if t._currCoeff >= t._targetCoeff then
        t._dir = 1
      end
    else
      t._currCoeff = t._currCoeff - 1
      if t._currCoeff <= 0 then
        t._repeats = t._repeats - 1
        if t._repeats > 0 then
          t._dir = 0
        else
          p.blendCoeff = 0
          p.darken = 0
          p.flash = 0
          destroy_task(t)
        end
      end
    end
  else
    t._timer = t._timer - 1
  end
end

AnimTasks.REGISTRY.BlendMonInAndOut = AnimTasks.BlendMonInAndOut
AnimTasks.REGISTRY.AnimTask_BlendMonInAndOut = AnimTasks.BlendMonInAndOut
AnimTasks.REGISTRY.BlendPalInAndOutByTag = AnimTasks.BlendMonInAndOut
AnimTasks.REGISTRY.AnimTask_BlendPalInAndOutByTag = AnimTasks.BlendMonInAndOut
AnimTasks.REGISTRY.MetallicShine = AnimTasks.BlendMonInAndOut
AnimTasks.REGISTRY.AnimTask_MetallicShine = AnimTasks.BlendMonInAndOut

--- pret AnimTask_TraceMonBlended (pokefirered/src/battle_anim_utility_funcs.c:230)
-- arg 0: battler, arg 1: interval, arg 2: lifetime, arg 3: count
function AnimTasks.TraceMonBlended(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  local AnimSprites = require("src.core.game3.battle.anim_sprites")
  if not t._inited then
    t._inited = true
    local whichMon = t.data[0] or 0
    local interval = math.max(1, tonumber(t.data[1]) or 1)
    local lifetime = math.max(1, tonumber(t.data[2]) or 5)
    local count = math.max(1, tonumber(t.data[3]) or 3)
    local side = vm:resolveBattlerSide(whichMon)
    t._side = side
    t._interval = interval
    t._lifetime = lifetime
    t._count = count
    t._timer = 0
    t._activeAfterimages = 0
  end

  if t._count > 0 then
    if (t._timer or 0) <= 0 then
      t._timer = t._interval
      t._count = t._count - 1
      local cx, cy = Anim.battlerCenter(t._side)
      local pres = Anim.present(t._side)
      local s = AnimSprites.acquire({
        x = cx,
        y = cy,
        z = (pres and pres.z or 100) - 5,
        alpha = 0.5,
        priority = 1,
        callback = function(sprite)
          sprite.data[0] = (sprite.data[0] or 0) + 1
          if sprite.data[0] >= t._lifetime then
            t._activeAfterimages = math.max(0, t._activeAfterimages - 1)
            AnimSprites.release(sprite)
          end
        end,
      })
      if s then
        t._activeAfterimages = t._activeAfterimages + 1
      end
    else
      t._timer = t._timer - 1
    end
  elseif t._activeAfterimages <= 0 then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.TraceMonBlended = AnimTasks.TraceMonBlended
AnimTasks.REGISTRY.AnimTask_TraceMonBlended = AnimTasks.TraceMonBlended

--- pret AnimTask_AttackerFadeToInvisible / AttackerFadeFromInvisible (pokefirered/src/battle_anim_dark.c:187, 226)
function AnimTasks.AttackerFadeToInvisible(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local delay = math.max(0, tonumber(t.data[0]) or 0)
    local side = vm:attackerSide()
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._delay = delay
    t._timer = delay
    t._step = 0
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  if (t._timer or 0) <= 0 then
    t._timer = t._delay
    t._step = t._step + 1
    p.alpha = math.max(0, 1 - (t._step / 16))
    if t._step >= 16 then
      p.alpha = 0
      p.visible = false
      destroy_task(t)
    end
  else
    t._timer = t._timer - 1
  end
end

AnimTasks.REGISTRY.AttackerFadeToInvisible = AnimTasks.AttackerFadeToInvisible
AnimTasks.REGISTRY.AnimTask_AttackerFadeToInvisible = AnimTasks.AttackerFadeToInvisible

function AnimTasks.AttackerFadeFromInvisible(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local delay = math.max(0, tonumber(t.data[0]) or 0)
    local side = vm:attackerSide()
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    local p = t._p
    p.visible = true
    t._delay = delay
    t._timer = delay
    t._step = 0
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  if (t._timer or 0) <= 0 then
    t._timer = t._delay
    t._step = t._step + 1
    p.alpha = math.min(1, t._step / 16)
    if t._step >= 16 then
      p.alpha = 1
      destroy_task(t)
    end
  else
    t._timer = t._timer - 1
  end
end

AnimTasks.REGISTRY.AttackerFadeFromInvisible = AnimTasks.AttackerFadeFromInvisible
AnimTasks.REGISTRY.AnimTask_AttackerFadeFromInvisible = AnimTasks.AttackerFadeFromInvisible

--- pret AnimTask_HardwarePaletteFade (pokefirered/src/battle_anim_utility_funcs.c:213)
function AnimTasks.HardwarePaletteFade(t, vm)
  -- arg 0: selectedPalettes, arg 1: delay, arg 2: startCoeff, arg 3: endCoeff, arg 4: color
  AnimTasks.BlendBattleAnimPal(t, vm)
end

AnimTasks.REGISTRY.HardwarePaletteFade = AnimTasks.HardwarePaletteFade
AnimTasks.REGISTRY.AnimTask_HardwarePaletteFade = AnimTasks.HardwarePaletteFade

--- pret AnimSimplePaletteBlend (pokefirered/src/battle_anim_normal.c:302)
-- arg 0: selectedPalettes, arg 1: delay, arg 2: startCoeff, arg 3: endCoeff, arg 4: color
AnimTasks.REGISTRY.SimplePaletteBlend = AnimTasks.BlendBattleAnimPal
AnimTasks.REGISTRY.AnimSimplePaletteBlend = AnimTasks.BlendBattleAnimPal
AnimTasks.REGISTRY.ComplexPaletteBlend = AnimTasks.ComplexPaletteBlend
AnimTasks.REGISTRY.AnimComplexPaletteBlend = AnimTasks.ComplexPaletteBlend

--- pret AnimTask_Flash (pokefirered/src/battle_anim_utility_funcs.c:583)
function AnimTasks.Flash(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local palMask = tonumber(t.data[0]) or 1
    local delay = math.max(0, tonumber(t.data[1]) or 1)
    local numFlashes = math.max(1, tonumber(t.data[2]) or 1)
    local color = t.data[3] or 0x7FFF
    local r, g, b = unpackRgb555(color)
    t._palMask = palMask
    t._delay = delay
    t._numFlashes = numFlashes
    t._color = { r, g, b }
    t._timer = 0
    t._state = 0
  end

  if (t._timer or 0) <= 0 then
    t._timer = t._delay
    t._state = 1 - t._state
    local coeff = (t._state == 1) and 1 or 0
    local r, g, b = t._color[1], t._color[2], t._color[3]
    if (t._palMask % 2) == 1 then
      if coeff > 0 then
        Anim.setScreenEffect({ type = (r==1 and g==1 and b==1) and "fade_white" or "fade_black", coeff = coeff, targetColor = { r, g, b } })
      else
        Anim.setScreenEffect(nil)
      end
    end
    if t._state == 0 then
      t._numFlashes = t._numFlashes - 1
      if t._numFlashes <= 0 then
        Anim.setScreenEffect(nil)
        destroy_task(t)
      end
    end
  else
    t._timer = t._timer - 1
  end
end

AnimTasks.REGISTRY.Flash = AnimTasks.Flash
AnimTasks.REGISTRY.AnimTask_Flash = AnimTasks.Flash

--- pret AnimTask_BlendNonAttackerPalettes (pokefirered/src/battle_anim_utility_funcs.c:652)
function AnimTasks.BlendNonAttackerPalettes(t, vm)
  t.data[0] = 5 -- target & BG
  AnimTasks.BlendBattleAnimPal(t, vm)
end

AnimTasks.REGISTRY.BlendNonAttackerPalettes = AnimTasks.BlendNonAttackerPalettes
AnimTasks.REGISTRY.AnimTask_BlendNonAttackerPalettes = AnimTasks.BlendNonAttackerPalettes

--- pret AnimTask_FacadeColorBlend (pokefirered/src/battle_anim_effects_3.c:3802)
local FACADE_COLORS = {
  0x76FF, 0x6EBE, 0x667D, 0x5E3C, 0x55FB, 0x4D9A, 0x4559, 0x3D18,
  0x34D7, 0x2C96, 0x2455, 0x1C14, 0x13D3, 0x0B92, 0x0351, 0x0BD2,
  0x1433, 0x1C94, 0x24F5, 0x2D56, 0x35B7, 0x3E18, 0x4679, 0x4ED9
}

function AnimTasks.FacadeColorBlend(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local whichMon = t.data[0] or 0
    local duration = math.max(1, tonumber(t.data[1]) or 24)
    local side = vm:resolveBattlerSide(whichMon)
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._duration = duration
    t._colorIdx = 1
    t._timer = duration
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  if t._timer > 0 then
    local c = FACADE_COLORS[t._colorIdx] or 0
    local r, g, b = unpackRgb555(c)
    p.blendColor = { r, g, b }
    p.blendCoeff = 0.5
    t._colorIdx = (t._colorIdx % #FACADE_COLORS) + 1
    t._timer = t._timer - 1
  else
    p.blendCoeff = 0
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.FacadeColorBlend = AnimTasks.FacadeColorBlend
AnimTasks.REGISTRY.AnimTask_FacadeColorBlend = AnimTasks.FacadeColorBlend

--- pret AnimTask_CycleMagicalLeafPal (pokefirered/src/battle_anim_effects_1.c:3668)
local MAGICAL_LEAF_COLORS = {
  0x001F, 0x03E0, 0x7C00, 0x03FF, 0x7C1F, 0x7FE0, 0x7FFF
}

function AnimTasks.CycleMagicalLeafPal(t, vm)
  if not t._inited then
    t._inited = true
    t._colorIdx = 1
    t._coeff = 0
    t._timer = 0
  end

  t._coeff = t._coeff + 1
  if t._coeff >= 17 then
    t._coeff = 0
    t._colorIdx = (t._colorIdx % #MAGICAL_LEAF_COLORS) + 1
  end

  if tonumber(t.data[7]) == -1 then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.CycleMagicalLeafPal = AnimTasks.CycleMagicalLeafPal
AnimTasks.REGISTRY.AnimTask_CycleMagicalLeafPal = AnimTasks.CycleMagicalLeafPal

--- pret AnimTask_AcidArmor (pokefirered/src/battle_anim_effects_3.c:3222)
function AnimTasks.AcidArmor(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local whichMon = t.data[0] or 0
    local side = vm:resolveBattlerSide(whichMon)
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._step = 0
    t._timer = 0
    t._wave = 0
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  t._wave = (t._wave + 16) % 256
  p.ox = Sin(t._wave, 4)

  if t._step == 0 then
    t._timer = t._timer + 1
    p.alpha = math.max(0, 1 - (t._timer / 32))
    if t._timer >= 32 then
      t._step = 1
      t._timer = 0
    end
  elseif t._step == 1 then
    t._timer = t._timer + 1
    if t._timer >= 16 then
      t._step = 2
      t._timer = 0
    end
  elseif t._step == 2 then
    t._timer = t._timer + 1
    p.alpha = math.min(1, t._timer / 32)
    if t._timer >= 32 then
      p.ox = 0
      p.alpha = 1
      destroy_task(t)
    end
  end
end

AnimTasks.REGISTRY.AcidArmor = AnimTasks.AcidArmor
AnimTasks.REGISTRY.AnimTask_AcidArmor = AnimTasks.AcidArmor

--- pret AnimTask_TransformMon (pokefirered/src/battle_anim_effects_3.c:2223)
function AnimTasks.TransformMon(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:attackerSide()
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._timer = 0
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  t._timer = t._timer + 1
  if t._timer < 20 then
    p.flash = (t._timer % 4 < 2) and 1 or 0
    p.sx = 1 + Sin(t._timer * 12, 32) / 256
    p.sy = 1 - Sin(t._timer * 12, 32) / 256
  else
    p.flash = 0
    p.sx = 1
    p.sy = 1
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.TransformMon = AnimTasks.TransformMon
AnimTasks.REGISTRY.AnimTask_TransformMon = AnimTasks.TransformMon

--- General Battler Affine Animation Tables & Engine (pokefirered/src/battle_anim_mons.c:1677, 1690)
local AFFINE_COMMANDS = {
  DefenseCurl = {
    { dx = -12, dy = 20, dr = 0, dur = 8 },
    { dx = 12, dy = -20, dr = 0, dur = 8 },
    loop = 2,
  },
  Stockpile = {
    { dx = 8, dy = -8, dr = 0, dur = 12 },
    { dx = -16, dy = 16, dr = 0, dur = 12 },
    { dx = 8, dy = -8, dr = 0, dur = 12 },
    loop = 1,
  },
  SpitUp = {
    { dx = 0, dy = 6, dr = 0, dur = 20 },
    { dx = 0, dy = 0, dr = 0, dur = 20 },
    { dx = 0, dy = -18, dr = 0, dur = 6 },
    { dx = -18, dy = -18, dr = 0, dur = 3 },
    { dx = 0, dy = 0, dr = 0, dur = 15 },
    { dx = 4, dy = 4, dr = 0, dur = 13 },
  },
  Swallow = {
    { dx = 0, dy = 6, dr = 0, dur = 20 },
    { dx = 0, dy = 0, dr = 0, dur = 20 },
    { dx = 7, dy = -30, dr = 0, dur = 6 },
    { dx = 0, dy = 0, dr = 0, dur = 20 },
    { dx = -2, dy = 3, dr = 0, dur = 20 },
  },
  StretchBattlerUp = {
    { dx = 10, dy = -13, dr = 0, dur = 10 },
    { dx = -10, dy = 13, dr = 0, dur = 10 },
  },
  GrowAndShrink = {
    { dx = 4, dy = 4, dr = 0, dur = 16 },
    { dx = 0, dy = 0, dr = 0, dur = 32 },
    { dx = -4, dy = -4, dr = 0, dur = 16 },
  },
  ThrashMoveMon = {
    { dx = 8, dy = -8, dr = 0, dur = 4 },
    { dx = -16, dy = 16, dr = 0, dur = 8 },
    { dx = 8, dy = -8, dr = 0, dur = 4 },
    loop = 2,
  },
  MeditateStretch = {
    { dx = 0, dy = 6, dr = 0, dur = 16 },
    { dx = 0, dy = -6, dr = 0, dur = 16 },
    loop = 2,
  },
  SlackOffSquish = {
    { dx = -4, dy = 8, dr = 0, dur = 8 },
    { dx = 4, dy = -8, dr = 0, dur = 8 },
  },
  SmellingSaltsSquish = {
    { dx = 10, dy = -10, dr = 0, dur = 6 },
    { dx = -10, dy = 10, dr = 0, dur = 6 },
  },
  FacadeSquish = {
    { dx = 8, dy = -8, dr = 0, dur = 4 },
    { dx = -16, dy = 16, dr = 0, dur = 8 },
    { dx = 8, dy = -8, dr = 0, dur = 4 },
  },
  Uproar = {
    { dx = 12, dy = -12, dr = 0, dur = 4 },
    { dx = -24, dy = 24, dr = 0, dur = 8 },
    { dx = 12, dy = -12, dr = 0, dur = 4 },
    loop = 3,
  },
}

local function stepAffineAnim(task, p, cmds)
  if not task._affineInited then
    task._affineInited = true
    task._affineCmdIdx = 1
    task._affineFrameTimer = 0
    task._affineLoopCount = cmds.loop or 0
    task._affineScaleX = 256
    task._affineScaleY = 256
    task._affineRot = 0
  end

  local cmd = cmds[task._affineCmdIdx]
  if not cmd then
    p.sx = 1
    p.sy = 1
    p.rotation = 0
    p.oy = 0
    return false
  end

  task._affineScaleX = task._affineScaleX + (cmd.dx or 0)
  task._affineScaleY = task._affineScaleY + (cmd.dy or 0)
  task._affineRot = (task._affineRot + (cmd.dr or 0)) % 65536

  p.sx = 256 / math.max(1, task._affineScaleX)
  p.sy = 256 / math.max(1, task._affineScaleY)
  p.rotation = (task._affineRot / 256) * (2 * math.pi)
  p.oy = math.floor((64 - (64 * 256 / math.max(1, task._affineScaleY))) / 2)

  task._affineFrameTimer = task._affineFrameTimer + 1
  if task._affineFrameTimer >= (cmd.dur or 1) then
    task._affineFrameTimer = 0
    task._affineCmdIdx = task._affineCmdIdx + 1
    if task._affineCmdIdx > #cmds then
      if task._affineLoopCount > 0 then
        task._affineLoopCount = task._affineLoopCount - 1
        task._affineCmdIdx = 1
      else
        p.sx = 1
        p.sy = 1
        p.rotation = 0
        p.oy = 0
        return false
      end
    end
  end
  return true
end

local function runBattlerAffineTask(t, vm, side, cmds)
  local Anim = require("src.core.game3.battle.anim")
  if not t._p then
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
  end
  if not stepAffineAnim(t, t._p, cmds) then
    destroy_task(t)
  end
end

--- Affine Command Task Handlers
function AnimTasks.DefenseCurlDeformMon(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.DefenseCurl) end
AnimTasks.REGISTRY.DefenseCurlDeformMon = AnimTasks.DefenseCurlDeformMon
AnimTasks.REGISTRY.AnimTask_DefenseCurlDeformMon = AnimTasks.DefenseCurlDeformMon

function AnimTasks.StockpileDeformMon(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.Stockpile) end
AnimTasks.REGISTRY.StockpileDeformMon = AnimTasks.StockpileDeformMon
AnimTasks.REGISTRY.AnimTask_StockpileDeformMon = AnimTasks.StockpileDeformMon

function AnimTasks.SpitUpDeformMon(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.SpitUp) end
AnimTasks.REGISTRY.SpitUpDeformMon = AnimTasks.SpitUpDeformMon
AnimTasks.REGISTRY.AnimTask_SpitUpDeformMon = AnimTasks.SpitUpDeformMon

function AnimTasks.SwallowDeformMon(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.Swallow) end
AnimTasks.REGISTRY.SwallowDeformMon = AnimTasks.SwallowDeformMon
AnimTasks.REGISTRY.AnimTask_SwallowDeformMon = AnimTasks.SwallowDeformMon

function AnimTasks.StretchTargetUp(t, vm) runBattlerAffineTask(t, vm, vm:targetSide(), AFFINE_COMMANDS.StretchBattlerUp) end
AnimTasks.REGISTRY.StretchTargetUp = AnimTasks.StretchTargetUp
AnimTasks.REGISTRY.AnimTask_StretchTargetUp = AnimTasks.StretchTargetUp

function AnimTasks.StretchAttackerUp(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.StretchBattlerUp) end
AnimTasks.REGISTRY.StretchAttackerUp = AnimTasks.StretchAttackerUp
AnimTasks.REGISTRY.AnimTask_StretchAttackerUp = AnimTasks.StretchAttackerUp

function AnimTasks.GrowAndShrink(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.GrowAndShrink) end
AnimTasks.REGISTRY.GrowAndShrink = AnimTasks.GrowAndShrink
AnimTasks.REGISTRY.AnimTask_GrowAndShrink = AnimTasks.GrowAndShrink

function AnimTasks.ThrashMoveMon(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.ThrashMoveMon) end
AnimTasks.REGISTRY.ThrashMoveMon = AnimTasks.ThrashMoveMon
AnimTasks.REGISTRY.AnimTask_ThrashMoveMon = AnimTasks.ThrashMoveMon

function AnimTasks.MeditateStretchAttacker(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.MeditateStretch) end
AnimTasks.REGISTRY.MeditateStretchAttacker = AnimTasks.MeditateStretchAttacker
AnimTasks.REGISTRY.AnimTask_MeditateStretchAttacker = AnimTasks.MeditateStretchAttacker

function AnimTasks.SlackOffSquish(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.SlackOffSquish) end
AnimTasks.REGISTRY.SlackOffSquish = AnimTasks.SlackOffSquish
AnimTasks.REGISTRY.AnimTask_SlackOffSquish = AnimTasks.SlackOffSquish

function AnimTasks.SmellingSaltsSquish(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.SmellingSaltsSquish) end
AnimTasks.REGISTRY.SmellingSaltsSquish = AnimTasks.SmellingSaltsSquish
AnimTasks.REGISTRY.AnimTask_SmellingSaltsSquish = AnimTasks.SmellingSaltsSquish

function AnimTasks.Uproar(t, vm) runBattlerAffineTask(t, vm, vm:attackerSide(), AFFINE_COMMANDS.Uproar) end
AnimTasks.REGISTRY.Uproar = AnimTasks.Uproar
AnimTasks.REGISTRY.AnimTask_Uproar = AnimTasks.Uproar

--- pret AnimTask_RotateMonSpriteToSide / RotateMonToSideAndRestore (pokefirered/src/battle_anim_mon_movement.c:778, 812)
-- arg 0: duration, arg 1: rotDelta, arg 2: whichMon, arg 3: returnMode (0=stay, 1=reset, 2=rotate back)
function AnimTasks.RotateMonSpriteToSide(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local duration = tonumber(t.data[0]) or 1
    local speed = tonumber(t.data[1]) or 0
    local whichMon = t.data[2] or 0
    local returnMode = tonumber(t.data[3]) or 0
    local side = vm:resolveBattlerSide(whichMon)
    local isPlayer = (side == "player")
    if isPlayer then
      speed = -speed
    end
    t._duration = duration
    t._speed = speed
    t._whichMon = whichMon
    t._returnMode = returnMode
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._rot = 0
    t._timer = 0
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  t._rot = t._rot + t._speed
  p.rotation = (t._rot / 256) * (2 * math.pi)
  p.oy = math.floor(Sin(math.floor(math.abs(t._rot) / 256) % 256, 16))

  t._timer = t._timer + 1
  if t._timer >= t._duration then
    if t._returnMode == 1 then
      p.rotation = 0
      p.oy = 0
      destroy_task(t)
    elseif t._returnMode == 2 then
      t._timer = 0
      t._speed = -t._speed
      t._returnMode = 1
    else
      destroy_task(t)
    end
  end
end

AnimTasks.REGISTRY.RotateMonSpriteToSide = AnimTasks.RotateMonSpriteToSide
AnimTasks.REGISTRY.AnimTask_RotateMonSpriteToSide = AnimTasks.RotateMonSpriteToSide
AnimTasks.REGISTRY.RotateMonToSideAndRestore = AnimTasks.RotateMonSpriteToSide
AnimTasks.REGISTRY.AnimTask_RotateMonToSideAndRestore = AnimTasks.RotateMonSpriteToSide

--- pret AnimTask_RockMonBackAndForth (pokefirered/src/battle_anim_effects_3.c:2643)
-- arg 0: whichBattler, arg 1: numRocks, arg 2: speedIncrease
function AnimTasks.RockMonBackAndForth(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local whichMon = t.data[0] or 0
    local numRocks = tonumber(t.data[1]) or 2
    local speedInc = math.max(0, math.min(2, tonumber(t.data[2]) or 0))
    if numRocks <= 0 then
      destroy_task(t)
      return
    end
    local side = vm:resolveBattlerSide(whichMon)
    local p = Anim.present(side)
    if not p then
      destroy_task(t)
      return
    end
    t._p = p
    t._side = side
    t._step = 0
    t._timer = 0
    t._rot = 0
    t._halfDur = 8 - (2 * speedInc)
    t._rotSpeed = 0x100 + (speedInc * 128)
    t._xSpeed = speedInc + 2
    t._repeats = numRocks - 1
    if side == "enemy" or (side ~= "player" and not vm.isReversed) then
      t._rotSpeed = -t._rotSpeed
      t._xSpeed = -t._xSpeed
    end
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  if t._step == 0 then
    p.ox = (p.ox or 0) + t._xSpeed
    t._rot = t._rot - t._rotSpeed
    p.rotation = (t._rot / 65536) * (2 * math.pi)
    p.oy = math.floor(Sin(math.floor(math.abs(t._rot) / 256) % 256, 16))
    t._timer = t._timer + 1
    if t._timer >= t._halfDur then
      t._timer = 0
      t._step = 1
    end
  elseif t._step == 1 then
    p.ox = (p.ox or 0) - t._xSpeed
    t._rot = t._rot + t._rotSpeed
    p.rotation = (t._rot / 65536) * (2 * math.pi)
    p.oy = math.floor(Sin(math.floor(math.abs(t._rot) / 256) % 256, 16))
    t._timer = t._timer + 1
    if t._timer >= (t._halfDur * 2) then
      t._timer = 0
      t._step = 2
    end
  elseif t._step == 2 then
    p.ox = (p.ox or 0) + t._xSpeed
    t._rot = t._rot - t._rotSpeed
    p.rotation = (t._rot / 65536) * (2 * math.pi)
    p.oy = math.floor(Sin(math.floor(math.abs(t._rot) / 256) % 256, 16))
    t._timer = t._timer + 1
    if t._timer >= t._halfDur then
      if t._repeats > 0 then
        t._repeats = t._repeats - 1
        t._timer = 0
        t._step = 0
      else
        t._step = 3
      end
    end
  elseif t._step >= 3 then
    p.ox = 0
    p.oy = 0
    p.rotation = 0
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.RockMonBackAndForth = AnimTasks.RockMonBackAndForth
AnimTasks.REGISTRY.AnimTask_RockMonBackAndForth = AnimTasks.RockMonBackAndForth
AnimTasks.REGISTRY.CycleMagicalLeafPal = AnimTasks.RockMonBackAndForth
AnimTasks.REGISTRY.AnimTask_CycleMagicalLeafPal = AnimTasks.RockMonBackAndForth

--- pret AnimTask_ScaleMonAndRestore (pokefirered/src/battle_anim_mon_movement.c:740)
-- arg 0: dx, arg 1: dy, arg 2: duration, arg 3: whichMon
function AnimTasks.ScaleMonAndRestore(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local dx = tonumber(t.data[0]) or 0
    local dy = tonumber(t.data[1]) or 0
    local duration = math.max(1, tonumber(t.data[2]) or 1)
    local whichMon = t.data[3] or 0
    local side = vm:resolveBattlerSide(whichMon)
    t._dx = dx
    t._dy = dy
    t._duration = duration
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._scaleX = 256
    t._scaleY = 256
    t._timer = 0
    t._phase = 0
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  t._scaleX = t._scaleX + t._dx
  t._scaleY = t._scaleY + t._dy
  p.sx = 256 / math.max(1, t._scaleX)
  p.sy = 256 / math.max(1, t._scaleY)
  p.oy = math.floor((64 - (64 * 256 / math.max(1, t._scaleY))) / 2)

  t._timer = t._timer + 1
  if t._timer >= t._duration then
    if t._phase == 0 then
      t._phase = 1
      t._timer = 0
      t._dx = -t._dx
      t._dy = -t._dy
    else
      p.sx = 1
      p.sy = 1
      p.oy = 0
      destroy_task(t)
    end
  end
end

AnimTasks.REGISTRY.ScaleMonAndRestore = AnimTasks.ScaleMonAndRestore
AnimTasks.REGISTRY.AnimTask_ScaleMonAndRestore = AnimTasks.ScaleMonAndRestore

--- pret AnimTask_Minimize (pokefirered/src/battle_anim_effects_2.c:2033)
function AnimTasks.Minimize(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:attackerSide()
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._step = 0
    t._frame = 0
    t._cycle = 0
    t._scale = 256
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  if t._step == 0 then
    t._scale = t._scale + 0x28
    p.sx = 256 / t._scale
    p.sy = 256 / t._scale
    p.oy = math.floor((64 - (64 * 256 / t._scale)) / 2)
    t._frame = t._frame + 1
    if t._frame >= 32 then
      t._frame = 0
      t._cycle = t._cycle + 1
      if t._cycle >= 3 then
        t._step = 2
      else
        t._scale = 256
        t._step = 0
      end
    end
  elseif t._step == 2 then
    t._frame = t._frame + 1
    if t._frame >= 32 then
      t._frame = 0
      t._step = 3
    end
  elseif t._step == 3 then
    t._scale = t._scale - 0x50
    p.sx = 256 / math.max(1, t._scale)
    p.sy = 256 / math.max(1, t._scale)
    p.oy = math.floor((64 - (64 * 256 / math.max(1, t._scale))) / 2)
    t._frame = t._frame + 1
    if t._frame >= 16 or t._scale <= 256 then
      p.sx = 1
      p.sy = 1
      p.oy = 0
      destroy_task(t)
    end
  end
end

AnimTasks.REGISTRY.Minimize = AnimTasks.Minimize
AnimTasks.REGISTRY.AnimTask_Minimize = AnimTasks.Minimize

--- pret AnimTask_Withdraw (pokefirered/src/battle_anim_effects_2.c:1377)
function AnimTasks.Withdraw(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:attackerSide()
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._rot = 0
    t._step = 0
    t._pause = 0
  end

  local p = t._p
  if not p then
    destroy_task(t)
    return
  end

  if t._step == 0 then
    t._rot = t._rot + 0xB0
    local r = t._rot
    if t._side == "player" then r = -r end
    p.rotation = (r / 256) * (2 * math.pi / 256)
    p.oy = math.floor(Sin(math.floor(math.abs(r) / 256) % 256, 16))
    if t._rot >= 0xF20 then
      t._step = 1
    end
  elseif t._step == 1 then
    t._pause = t._pause + 1
    if t._pause >= 30 then
      t._step = 2
    end
  elseif t._step == 2 then
    t._rot = t._rot - 0xB0
    local r = t._rot
    if t._side == "player" then r = -r end
    p.rotation = (r / 256) * (2 * math.pi / 256)
    p.oy = math.floor(Sin(math.floor(math.abs(r) / 256) % 256, 16))
    if t._rot <= 0 then
      p.rotation = 0
      p.oy = 0
      destroy_task(t)
    end
  end
end

AnimTasks.REGISTRY.Withdraw = AnimTasks.Withdraw
AnimTasks.REGISTRY.AnimTask_Withdraw = AnimTasks.Withdraw

--- pret AnimTask_SwayMon (pokefirered/src/battle_anim_mon_movement.c:680)
-- arg 0: dir (0=horiz, 1=vert); arg 1: amp; arg 2: period; arg 3: num sways; arg 4: which mon (0=atk, 1=tgt)
function AnimTasks.SwayMon(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local dir = tonumber(t.data[0]) or 0
    local amp = tonumber(t.data[1]) or 8
    local period = tonumber(t.data[2]) or 0x100
    local numSways = math.max(1, tonumber(t.data[3]) or 1)
    local which = t.data[4] or 0
    local side = vm:resolveBattlerSide(which)
    if vm:attackerSide() ~= "player" then
      amp = -amp
    end
    t._dir = dir
    t._amp = amp
    t._period = period
    t._numSways = numSways
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._sineIndex = 0
    t._flag11 = 0
    t._flag12 = 1
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  t._sineIndex = (t._sineIndex + t._period) % 65536
  local waveIdx = math.floor(t._sineIndex / 256) % 256
  local sineVal = Sin(waveIdx, t._amp)
  if t._dir == 0 then
    p.ox = sineVal
  else
    if t._side == "player" then
      p.oy = math.abs(sineVal)
    else
      p.oy = -math.abs(sineVal)
    end
  end
  if (waveIdx > 0x7F and t._flag11 == 0 and t._flag12 == 1)
      or (waveIdx < 0x7F and t._flag11 == 1 and t._flag12 == 0) then
    t._flag11 = 1 - t._flag11
    t._flag12 = 1 - t._flag12
    t._numSways = t._numSways - 1
    if t._numSways <= 0 then
      p.ox = 0
      p.oy = 0
      destroy_task(t)
    end
  end
end

AnimTasks.REGISTRY.SwayMon = AnimTasks.SwayMon
AnimTasks.REGISTRY.AnimTask_SwayMon = AnimTasks.SwayMon

--- pret AnimTask_WindUpLunge (pokefirered/src/battle_anim_mon_movement.c:579)
-- arg 0: anim battler; arg 1: hspeed; arg 2: wave amp; arg 3: dur1; arg 4: delay; arg 5: target x; arg 6: lunge dur
function AnimTasks.WindUpLunge(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  local AnimVm = require("src.core.game3.battle.anim_vm")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[0] or 0)
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    local speed1 = tonumber(t.data[1]) or 0
    local targetX2 = tonumber(t.data[5]) or 0
    if side ~= "player" then
      speed1 = -speed1
      targetX2 = -targetX2
    end
    t._amp = tonumber(t.data[2]) or 0
    t._dur1 = math.max(1, tonumber(t.data[3]) or 10)
    t._delay = tonumber(t.data[4]) or 0
    t._dur2 = math.max(1, tonumber(t.data[6]) or 4)
    t._speed1_fp = math.floor((speed1 * 256) / t._dur1)
    t._speed2_fp = math.floor((targetX2 * 256) / t._dur2)
    t._wavePeriod = math.floor(0x8000 / t._dur1)
    t._waveAngle = 0
    t._subX1 = 0
    t._subX2 = 0
    t._step = 1
    t._origZ = t._p.z
    t._p.z = AnimVm.Z.FRONT
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  if t._step == 1 then
    t._subX1 = t._subX1 + t._speed1_fp
    p.ox = math.floor(t._subX1 / 256)
    p.oy = Sin(math.floor(t._waveAngle / 256), t._amp)
    t._waveAngle = t._waveAngle + t._wavePeriod
    t._dur1 = t._dur1 - 1
    if t._dur1 <= 0 then
      t._step = 2
    end
  elseif t._step == 2 then
    if t._delay > 0 then
      t._delay = t._delay - 1
    else
      t._subX2 = t._subX2 + t._speed2_fp
      p.ox = math.floor(t._subX2 / 256) + math.floor(t._subX1 / 256)
      t._dur2 = t._dur2 - 1
      if t._dur2 <= 0 then
        if t._origZ then p.z = t._origZ end
        destroy_task(t)
      end
    end
  end
end

AnimTasks.REGISTRY.WindUpLunge = AnimTasks.WindUpLunge
AnimTasks.REGISTRY.AnimTask_WindUpLunge = AnimTasks.WindUpLunge

--- pret AnimTask_DragonDanceWaver: wave distortion & sway.
function AnimTasks.DragonDanceWaver(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = math.max(16, tonumber(t.data[0]) or 28)
  local side = vm:attackerSide()
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(side)

  if p then
    p.ox = math.floor(math.sin(frame * 0.45) * 6)
    p.rotation = math.sin(frame * 0.3) * 0.12
  end

  if frame >= dur then
    if p then p.ox = 0; p.rotation = 0 end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.DragonDanceWaver = AnimTasks.DragonDanceWaver
AnimTasks.REGISTRY.AnimTask_DragonDanceWaver = AnimTasks.DragonDanceWaver

--- Utility Side Query Tasks (pokefirered/src/battle_anim_utility_funcs.c:700)
function AnimTasks.GetAttackerSide(t, vm)
  local side = vm:attackerSide()
  vm.args[7] = (side == "player") and 0 or 1
  destroy_task(t)
end

AnimTasks.REGISTRY.GetAttackerSide = AnimTasks.GetAttackerSide
AnimTasks.REGISTRY.AnimTask_GetAttackerSide = AnimTasks.GetAttackerSide

function AnimTasks.GetTargetSide(t, vm)
  local side = vm:targetSide()
  vm.args[7] = (side == "player") and 0 or 1
  destroy_task(t)
end

AnimTasks.REGISTRY.GetTargetSide = AnimTasks.GetTargetSide
AnimTasks.REGISTRY.AnimTask_GetTargetSide = AnimTasks.GetTargetSide

-- pokefirered/src/battle_anim_utility_funcs.c:712
function AnimTasks.GetTargetIsAttackerPartner(t, vm)
  local atk = vm.attackerId and vm:attackerId() or 0
  local tgt = vm.targetId and vm:targetId() or 1
  vm.args[7] = (require("bit").bxor(atk, 2) == tgt) and 1 or 0
  destroy_task(t)
end

AnimTasks.REGISTRY.GetTargetIsAttackerPartner = AnimTasks.GetTargetIsAttackerPartner
AnimTasks.REGISTRY.AnimTask_GetTargetIsAttackerPartner = AnimTasks.GetTargetIsAttackerPartner

function AnimTasks.SetAllNonAttackersInvisiblity(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  local invis = (tonumber(t.data[0]) or 0) ~= 0
  local atkSide = vm:attackerSide()
  local otherSide = (atkSide == "player") and "enemy" or "player"
  local p = Anim.present(otherSide)
  if p then p.visible = not invis end
  destroy_task(t)
end

AnimTasks.REGISTRY.SetAllNonAttackersInvisiblity = AnimTasks.SetAllNonAttackersInvisiblity
AnimTasks.REGISTRY.AnimTask_SetAllNonAttackersInvisiblity = AnimTasks.SetAllNonAttackersInvisiblity

--- pret AnimTask_TranslateMonElliptical / AnimTask_TranslateMonEllipticalRespectSide (pokefirered/src/battle_anim_mon_movement.c:334, 377)
-- arg 0: battler; arg 1: ellipse width; arg 2: ellipse height; arg 3: num loops; arg 4: speed (0-5)
function AnimTasks.TranslateMonElliptical(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  local AnimVm = require("src.core.game3.battle.anim_vm")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[0])
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    t._radiusX = tonumber(t.data[1]) or 0
    t._radiusY = tonumber(t.data[2]) or 0
    t._numLoops = math.max(1, tonumber(t.data[3]) or 1)
    local spd = math.min(5, math.max(0, tonumber(t.data[4]) or 0))
    t._wavePeriod = 2 ^ spd
    t._angle = 0
    t._origZ = t._p.z
    t._p.z = AnimVm.Z.FRONT
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  p.ox = Sin(t._angle, t._radiusX)
  p.oy = -Cos(t._angle, t._radiusY) + t._radiusY
  t._angle = (t._angle + t._wavePeriod) % 256
  if t._angle == 0 then
    t._numLoops = t._numLoops - 1
  end
  if t._numLoops <= 0 then
    p.ox = 0
    p.oy = 0
    if t._origZ then p.z = t._origZ end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.TranslateMonElliptical = AnimTasks.TranslateMonElliptical
AnimTasks.REGISTRY.AnimTask_TranslateMonElliptical = AnimTasks.TranslateMonElliptical

function AnimTasks.TranslateMonEllipticalRespectSide(t, vm)
  local atkSide = vm:attackerSide()
  if atkSide ~= "player" then
    t.data[1] = -(tonumber(t.data[1]) or 0)
  end
  AnimTasks.TranslateMonElliptical(t, vm)
end

AnimTasks.REGISTRY.TranslateMonEllipticalRespectSide = AnimTasks.TranslateMonEllipticalRespectSide
AnimTasks.REGISTRY.AnimTask_TranslateMonEllipticalRespectSide = AnimTasks.TranslateMonEllipticalRespectSide

--- pret AnimTask_SlideOffScreen (pokefirered/src/battle_anim_mon_movement.c:626)
-- arg 0: battler; arg 1: speed
function AnimTasks.SlideOffScreen(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  if not t._inited then
    t._inited = true
    local side = vm:resolveBattlerSide(t.data[0] or 0)
    t._side = side
    t._p = Anim.present(side)
    if not t._p then
      destroy_task(t)
      return
    end
    local speed = tonumber(t.data[1]) or 8
    local tgtSide = vm:targetSide()
    if tgtSide == "player" then
      speed = -speed
    end
    t._speed = speed
  end
  local p = t._p
  if not p then
    destroy_task(t)
    return
  end
  p.ox = (p.ox or 0) + t._speed
  local cx, _ = vm:battlerCenter(t._side)
  if cx < -40 or cx > 280 then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.SlideOffScreen = AnimTasks.SlideOffScreen
AnimTasks.REGISTRY.AnimTask_SlideOffScreen = AnimTasks.SlideOffScreen

--- pret AnimTask_VoltTackleBolt (pokefirered/src/battle_anim_electric.c:985)
-- arg 0: bolt step index (0=start, 1..3=mid, 4=impact)
function AnimTasks.VoltTackleBolt(t, vm)
  if not t._inited then
    t._inited = true
    local stepIdx = tonumber(t.data[0]) or 0
    local isPlayer = (vm:attackerSide() == "player")
    local dir = isPlayer and 1 or -1
    local ax, ay = vm:battlerCenter("attacker")
    local tx, ty = vm:battlerCenter("target")
    local startX, startY, endX
    if stepIdx == 0 then
      startX, startY = ax, ay
      endX = (dir * 128) + 120
    elseif stepIdx == 4 then
      startX = 120 - (dir * 128)
      startY = ty
      endX = tx - (dir * 32)
    else
      startX = ((stepIdx % 2) == 1) and 256 or -16
      endX = ((stepIdx % 2) == 1) and -16 or 256
      startY = isPlayer and (80 - stepIdx * 10) or (stepIdx * 10 + 40)
    end
    t._currX = startX
    t._startY = startY
    t._endX = endX
    t._dir = (startX < endX) and 1 or -1
    t._timer = 0
    t._activeBolts = 0
  end

  local pack = vm._pack
  local imgMeta = pack and pack.tags and (pack.tags["ELECTRICITY"] or pack.tags["SPARK"] or pack.tags["LIGHTNING"])
  if imgMeta and imgMeta.image then
    local spr = AnimSprites.acquire({
      x = t._currX,
      y = t._startY + math.random(-8, 8),
      z = AnimSprites.Z.GLOBAL_FRONT,
      image = imgMeta.image,
      w = imgMeta.frameW or 16,
      h = imgMeta.frameH or 16,
      hFlip = (t._dir < 0),
      tag = "ELECTRICITY",
      callback = function(s)
        s.data[0] = (s.data[0] or 0) + 1
        if s.data[0] >= 6 then AnimSprites.release(s) end
      end,
    })
    if spr then
      spr._baseW = imgMeta.frameW or 16
      spr._baseH = imgMeta.frameH or 16
    end
  end

  t._currX = t._currX + t._dir * 16
  local reached = (t._dir == 1 and t._currX >= t._endX) or (t._dir == -1 and t._currX <= t._endX)
  if reached then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.VoltTackleBolt = AnimTasks.VoltTackleBolt
AnimTasks.REGISTRY.AnimTask_VoltTackleBolt = AnimTasks.VoltTackleBolt

--- pret AnimTask_ShockWaveProgressingBolt / AnimTask_ShockWaveLightning (pokefirered/src/battle_anim_electric.c:1107, 1226)
function AnimTasks.ShockWaveProgressingBolt(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 20
  local ax, ay = vm:battlerCenter("attacker")
  local tx, ty = vm:battlerCenter("target")
  local pack = vm._pack

  if frame < 16 and frame % 2 == 0 then
    local u = frame / 16
    local bx = ax + (tx - ax) * u
    local by = ay + (ty - ay) * u + math.random(-12, 12)
    local imgMeta = pack and pack.tags and (pack.tags["LIGHTNING"] or pack.tags["ELECTRICITY"] or pack.tags["SPARK"])
    if imgMeta and imgMeta.image then
      local spr = AnimSprites.acquire({
        x = bx,
        y = by,
        z = AnimSprites.Z.GLOBAL_FRONT,
        image = imgMeta.image,
        w = imgMeta.frameW or 32,
        h = imgMeta.frameH or 32,
        tag = "LIGHTNING",
        callback = function(s)
          s.data[0] = (s.data[0] or 0) + 1
          if s.data[0] >= 8 then AnimSprites.release(s) end
        end,
      })
      if spr then
        spr._baseW = imgMeta.frameW or 32
        spr._baseH = imgMeta.frameH or 32
      end
    end
  end

  if frame >= dur then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.ShockWaveProgressingBolt = AnimTasks.ShockWaveProgressingBolt
AnimTasks.REGISTRY.AnimTask_ShockWaveProgressingBolt = AnimTasks.ShockWaveProgressingBolt
AnimTasks.REGISTRY.ShockWaveLightning = AnimTasks.ShockWaveProgressingBolt
AnimTasks.REGISTRY.AnimTask_ShockWaveLightning = AnimTasks.ShockWaveProgressingBolt
AnimTasks.REGISTRY.ElectricBolt = AnimTasks.ShockWaveProgressingBolt
AnimTasks.REGISTRY.AnimTask_ElectricBolt = AnimTasks.ShockWaveProgressingBolt

--- pret AnimTask_EruptionLaunchRocks (pokefirered/src/battle_anim_fire.c:754)
function AnimTasks.EruptionLaunchRocks(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 36
  local ax, ay = vm:battlerCenter("attacker")
  local pack = vm._pack

  if frame < 20 and frame % 4 == 0 then
    local imgMeta = pack and pack.tags and (pack.tags["ROCKS"] or pack.tags["SMALL_ROCK"] or pack.tags["IMPACT"])
    if imgMeta and imgMeta.image then
      for _ = 1, 2 do
        local spr = AnimSprites.acquire({
          x = ax + math.random(-16, 16),
          y = ay,
          z = AnimSprites.Z.GLOBAL_FRONT,
          image = imgMeta.image,
          w = imgMeta.frameW or 16,
          h = imgMeta.frameH or 16,
          tag = "ROCKS",
          callback = function(s)
            s.data[0] = (s.data[0] or 0) + 1
            if not s._vx then
              s._vx = (math.random() - 0.5) * 3.5
              s._vy = -4.5 - math.random() * 2.0
            end
            s._vy = s._vy + 0.3 -- gravity
            s.ox = (s.ox or 0) + s._vx
            s.oy = (s.oy or 0) + s._vy
            s.rotation = (s.rotation or 0) + 0.2
            if s.data[0] >= 24 then AnimSprites.release(s) end
          end,
        })
        if spr then
          spr._baseW = imgMeta.frameW or 16
          spr._baseH = imgMeta.frameH or 16
        end
      end
    end
  end

  if frame >= dur then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.EruptionLaunchRocks = AnimTasks.EruptionLaunchRocks
AnimTasks.REGISTRY.AnimTask_EruptionLaunchRocks = AnimTasks.EruptionLaunchRocks

--- pret AnimTask_FrozenIceCube (pokefirered/src/battle_anim_status_effects.c:350)
function AnimTasks.FrozenIceCube(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  local Anim = require("src.core.game3.battle.anim")
  local tgtSide = vm:resolveBattlerSide("target")
  local pTgt = Anim.present(tgtSide)
  t.z = AnimSprites.Z.GLOBAL_FRONT

  if frame < dur and pTgt then
    pTgt.blendColor = { 0.4, 0.8, 1.0 }
    pTgt.blendCoeff = 0.5 + 0.2 * math.sin((frame / 8) * math.pi)
  elseif frame >= dur and pTgt then
    pTgt.blendCoeff = 0
  end

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local tx, ty = vm:battlerCenter(tgtSide)
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    -- Crystalline faceted ice block overlay
    love.graphics.setColor(0.60, 0.88, 1.00, a * 0.55)
    love.graphics.rectangle("fill", tx - 28, ty - 28, 56, 56, 4, 4)
    love.graphics.setColor(0.90, 0.98, 1.00, a * 0.85)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", tx - 28, ty - 28, 56, 56, 4, 4)
    -- Shimmering internal prism facet lines
    love.graphics.line(tx - 28, ty - 12, tx + 28, ty - 20)
    love.graphics.line(tx - 12, ty + 28, tx + 18, ty - 28)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    if pTgt then pTgt.blendCoeff = 0 end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.FrozenIceCube = AnimTasks.FrozenIceCube
AnimTasks.REGISTRY.AnimTask_FrozenIceCube = AnimTasks.FrozenIceCube

--- pret AnimTask_Hail (pokefirered/src/battle_anim_ice.c:1253)
function AnimTasks.Hail(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.GLOBAL_FRONT

  if frame == 1 then
    t._particles = {}
  end

  -- Spawn falling hail shards
  if frame < 26 and frame % 2 == 0 then
    t._particles = t._particles or {}
    for _ = 1, 4 do
      t._particles[#t._particles + 1] = {
        x = math.random(10, 240),
        y = -10,
        vx = -3.5,
        vy = 6.0 + math.random() * 2.0,
        life = 0,
        maxLife = 20,
      }
    end
  end

  if t._particles then
    local alive = {}
    for _, p in ipairs(t._particles) do
      p.life = p.life + 1
      p.x = p.x + p.vx
      p.y = p.y + p.vy
      if p.life < p.maxLife and p.y < 120 then
        alive[#alive + 1] = p
      end
    end
    t._particles = alive
  end

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    if not task._particles then return end
    love.graphics.setLineWidth(1.5)
    for _, p in ipairs(task._particles) do
      local a = 1.0 - (p.life / p.maxLife)
      love.graphics.setColor(0.85, 0.95, 1.0, a * 0.9)
      love.graphics.line(p.x, p.y, p.x + p.vx * 1.5, p.y + p.vy * 1.5)
      love.graphics.setColor(1, 1, 1, a)
      love.graphics.circle("fill", p.x, p.y, 1.5)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.Hail = AnimTasks.Hail
AnimTasks.REGISTRY.AnimTask_Hail = AnimTasks.Hail

--- pret Atmospheric Fog & Spore Tasks (Mist, Haze, Spore, Smokescreen)
function AnimTasks.AtmosphericFog(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = math.max(16, tonumber(t.data[0]) or 28)
  t.z = AnimSprites.Z.MID_FIELD

  if frame == 1 then
    t._particles = {}
    for _ = 1, 8 do
      t._particles[#t._particles + 1] = {
        x = math.random(10, 230),
        y = math.random(35, 100),
        vx = (math.random() > 0.5 and 0.4 or -0.4),
        radius = math.random(18, 32),
        life = 0,
        maxLife = dur,
      }
    end
  end

  if t._particles then
    for _, p in ipairs(t._particles) do
      p.life = p.life + 1
      p.x = p.x + p.vx
    end
  end

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    if not task._particles then return end
    local f = task.data[14] or 0
    local globalAlpha = (f <= 8) and (f / 8) or ((f >= dur - 8) and ((dur - f) / 8) or 1.0)
    for _, p in ipairs(task._particles) do
      love.graphics.setColor(0.92, 0.94, 0.98, globalAlpha * 0.35)
      love.graphics.circle("fill", p.x, p.y, p.radius)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.MistBallFog = AnimTasks.AtmosphericFog
AnimTasks.REGISTRY.AnimTask_MistBallFog = AnimTasks.AtmosphericFog
AnimTasks.REGISTRY.HazeScrollingFog = AnimTasks.AtmosphericFog
AnimTasks.REGISTRY.AnimTask_HazeScrollingFog = AnimTasks.AtmosphericFog
AnimTasks.REGISTRY.SporeDoubleBattle = AnimTasks.AtmosphericFog
AnimTasks.REGISTRY.AnimTask_SporeDoubleBattle = AnimTasks.AtmosphericFog
AnimTasks.REGISTRY.SmokescreenImpact = AnimTasks.AtmosphericFog
AnimTasks.REGISTRY.AnimTask_SmokescreenImpact = AnimTasks.AtmosphericFog

--- pret AnimTask_LoadSandstormBackground (pokefirered/src/battle_anim_rock.c:405)
function AnimTasks.LoadSandstormBackground(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.MID_FIELD

  if frame == 1 then
    t._particles = {}
    for _ = 1, 14 do
      t._particles[#t._particles + 1] = {
        x = math.random(0, 240),
        y = math.random(20, 110),
        vx = -(4.0 + math.random() * 3.0),
        vy = (math.random() - 0.5) * 1.5,
        len = math.random(8, 20),
        life = 0,
        maxLife = dur,
      }
    end
  end

  if t._particles then
    for _, p in ipairs(t._particles) do
      p.life = p.life + 1
      p.x = p.x + p.vx
      p.y = p.y + p.vy
      if p.x < -20 then p.x = 260; p.y = math.random(20, 110) end
    end
  end

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    if not task._particles then return end
    local f = task.data[14] or 0
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    -- Ambient sandstorm tint
    love.graphics.setColor(0.78, 0.65, 0.40, a * 0.30)
    love.graphics.rectangle("fill", 0, 0, 240, 112)
    -- Swirling wind and dust streaks
    love.graphics.setColor(0.90, 0.80, 0.55, a * 0.70)
    love.graphics.setLineWidth(1.5)
    for _, p in ipairs(task._particles) do
      love.graphics.line(p.x, p.y, p.x + p.len, p.y - 2)
      love.graphics.circle("fill", p.x, p.y, 1.2)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.LoadSandstormBackground = AnimTasks.LoadSandstormBackground
AnimTasks.REGISTRY.AnimTask_LoadSandstormBackground = AnimTasks.LoadSandstormBackground

--- Sound Tasks with spatial panning
function AnimTasks.SoundTask_PlaySE1WithPanning(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local songId = t.data[0]
  local initPan = tonumber(t.data[1]) or -64
  local targetPan = tonumber(t.data[2]) or 63
  local dur = math.max(1, tonumber(t.data[3]) or 16)

  if frame == 1 then
    t.data[10] = initPan
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio and Audio.playSe then
      Audio.playSe(songId, { pan = initPan })
    end
  end

  local u = math.min(1, frame / dur)
  local currentPan = math.floor(initPan + (targetPan - initPan) * u)
  t.data[10] = currentPan

  if frame >= dur then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.SoundTask_PlaySE1WithPanning = AnimTasks.SoundTask_PlaySE1WithPanning

function AnimTasks.SoundTask_AdjustPanningVar(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = math.max(1, tonumber(t.data[1]) or 16)
  if frame >= dur then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.SoundTask_AdjustPanningVar = AnimTasks.SoundTask_AdjustPanningVar

function AnimTasks.SetGrayscaleOrOriginalPal(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = math.max(12, tonumber(t.data[0]) or 24)
  local Anim = require("src.core.game3.battle.anim")

  local u = math.sin((frame / dur) * math.pi)
  Anim.setScreenEffect({ type = "grayscale", coeff = u })

  if frame >= dur then
    Anim.setScreenEffect(nil)
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.SetGrayscaleOrOriginalPal = AnimTasks.SetGrayscaleOrOriginalPal
AnimTasks.REGISTRY.AnimTask_SetGrayscaleOrOriginalPal = AnimTasks.SetGrayscaleOrOriginalPal

--- pret AnimTask_PainSplitMovement: visual energy transfer pulse
function AnimTasks.PainSplitMovement(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  local Anim = require("src.core.game3.battle.anim")
  local pAtk = Anim.present(vm:attackerSide())
  local pTgt = Anim.present(vm:resolveBattlerSide("target"))
  if frame < 12 then
    if pTgt then pTgt.flash = (frame % 2 == 0) and 1 or 0 end
  elseif frame < 24 then
    if pTgt then pTgt.flash = 0 end
    if pAtk then pAtk.flash = (frame % 2 == 0) and 1 or 0 end
  end
  if frame >= dur then
    if pAtk then pAtk.flash = 0 end
    if pTgt then pTgt.flash = 0 end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.PainSplitMovement = AnimTasks.PainSplitMovement
AnimTasks.REGISTRY.AnimTask_PainSplitMovement = AnimTasks.PainSplitMovement

--- pret AnimTask_DoubleTeam / AnimTask_MonToSubstitute
function AnimTasks.DoubleTeam(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = math.max(20, tonumber(t.data[0]) or 30)
  local side = vm:attackerSide()
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(side)
  if p then
    local phase = frame % 6
    p.ox = (phase < 3) and 12 or -12
    p.alpha = 0.65 + 0.35 * math.sin(frame * 0.5)
  end
  if frame >= dur then
    if p then p.ox = 0; p.alpha = 1.0 end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.DoubleTeam = AnimTasks.DoubleTeam
AnimTasks.REGISTRY.AnimTask_DoubleTeam = AnimTasks.DoubleTeam

function AnimTasks.MonToSubstitute(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 16
  local side = vm:attackerSide()
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(side)
  if p then
    local u = math.sin((frame / dur) * math.pi)
    p.sy = 1.0 - u * 0.3
    p.sx = 1.0 + u * 0.2
  end
  if frame >= dur then
    if p then p.sx = 1.0; p.sy = 1.0 end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.MonToSubstitute = AnimTasks.MonToSubstitute
AnimTasks.REGISTRY.AnimTask_MonToSubstitute = AnimTasks.MonToSubstitute


-- =========================================================================
-- Phase 4: Dynamic Backgrounds, Clones, Distortions & Specialized Subsystems
-- =========================================================================

--- Subsystem A: Dynamic Scrolling Backgrounds & High-Altitude Environments

--- pret AnimTask_MoveSkyUppercutBg (pokefirered/src/battle_anim_fight.c:280)
function AnimTasks.MoveSkyUppercutBg(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 36
  t.z = AnimSprites.Z.GLOBAL_BEHIND
  t.data[10] = (t.data[10] or 0) + 14 -- vertical scroll speed upward

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    local scrollY = (task.data[10] or 0) % 112
    -- Sky gradient background
    love.graphics.setColor(0.20, 0.50, 0.90, a * 0.85)
    love.graphics.rectangle("fill", 0, 0, 240, 112)
    -- Fast ascending high-altitude cloud speed lines
    love.graphics.setColor(0.90, 0.95, 1.00, a * 0.70)
    love.graphics.setLineWidth(2)
    for i = 0, 8 do
      local x = (i * 28 + 14) % 240
      local y = (i * 32 - scrollY * 2) % 128 - 16
      love.graphics.line(x, y, x, y + 24)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.MoveSkyUppercutBg = AnimTasks.MoveSkyUppercutBg
AnimTasks.REGISTRY.AnimTask_MoveSkyUppercutBg = AnimTasks.MoveSkyUppercutBg

--- pret AnimTask_MoveSeismicTossBg & SeismicTossBgAccelerateDownAtEnd (pokefirered/src/battle_anim_fight.c:320)
function AnimTasks.MoveSeismicTossBg(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 40
  t.z = AnimSprites.Z.GLOBAL_BEHIND
  local speed = 2 + (frame * 0.4)
  t.data[10] = (t.data[10] or 0) + speed -- accelerating descent

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    local scrollY = (task.data[10] or 0) % 112
    -- Space / upper atmosphere deep navy background
    love.graphics.setColor(0.04, 0.08, 0.22, a * 0.90)
    love.graphics.rectangle("fill", 0, 0, 240, 112)
    -- Earth curve horizon glow
    love.graphics.setColor(0.18, 0.55, 0.85, a * 0.65)
    love.graphics.arc("fill", 120, 180 - scrollY * 0.5, 140, math.pi, math.pi * 2)
    -- Re-entry meteor friction streaks
    love.graphics.setColor(1.00, 0.65, 0.20, a * 0.80)
    love.graphics.setLineWidth(2)
    for i = 0, 6 do
      local x = (i * 36 + 18) % 240
      local y = (i * 24 + scrollY * 2) % 128 - 16
      love.graphics.line(x, y, x, y + 18)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.MoveSeismicTossBg = AnimTasks.MoveSeismicTossBg
AnimTasks.REGISTRY.AnimTask_MoveSeismicTossBg = AnimTasks.MoveSeismicTossBg
AnimTasks.REGISTRY.SeismicTossBgAccelerateDownAtEnd = AnimTasks.MoveSeismicTossBg
AnimTasks.REGISTRY.AnimTask_SeismicTossBgAccelerateDownAtEnd = AnimTasks.MoveSeismicTossBg

--- pret AnimTask_PositionFissureBgOnBattler (pokefirered/src/battle_anim_ground.c:450)
function AnimTasks.PositionFissureBgOnBattler(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 40
  t.z = AnimSprites.Z.GLOBAL_BEHIND
  local tx, ty = vm:battlerCenter("target")

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    local width = math.min(36, f * 1.5)
    -- Ground abyss fissure opening beneath target
    love.graphics.setColor(0.08, 0.05, 0.02, a * 0.95)
    love.graphics.polygon("fill", tx - width, ty + 20, tx + width, ty + 20, tx + width * 0.7, 112, tx - width * 0.7, 112)
    -- Glowing molten/rock core crack lines
    love.graphics.setColor(0.85, 0.35, 0.10, a * 0.80)
    love.graphics.setLineWidth(2)
    love.graphics.line(tx - width, ty + 20, tx, ty + 35, tx + width, ty + 20)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.PositionFissureBgOnBattler = AnimTasks.PositionFissureBgOnBattler
AnimTasks.REGISTRY.AnimTask_PositionFissureBgOnBattler = AnimTasks.PositionFissureBgOnBattler

--- pret SetPsychicBackground (Psychic, Psybeam, Teleport, Skill Swap, Extrasensory)
function AnimTasks.SetPsychicBackground(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.GLOBAL_BEHIND

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    -- Cosmic psychic distortion background
    love.graphics.setColor(0.35, 0.05, 0.45, a * 0.50)
    love.graphics.rectangle("fill", 0, 0, 240, 112)
    -- Warping psychic concentric rings
    love.graphics.setColor(0.85, 0.35, 0.95, a * 0.40)
    love.graphics.setLineWidth(1.5)
    local cx, cy = vm:battlerCenter("target")
    for r = 16, 80, 16 do
      local rad = (r + f * 2) % 80
      love.graphics.circle("line", cx, cy, rad)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.SetPsychicBackground = AnimTasks.SetPsychicBackground
AnimTasks.REGISTRY.UnsetPsychicBackground = stub_task

--- pret AnimTask_HeartsBackground (Attract)
function AnimTasks.HeartsBackground(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 36
  t.z = AnimSprites.Z.GLOBAL_BEHIND

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    -- Pink ambient glow
    love.graphics.setColor(0.95, 0.40, 0.65, a * 0.30)
    love.graphics.rectangle("fill", 0, 0, 240, 112)
    -- Floating background hearts
    love.graphics.setColor(1.00, 0.45, 0.70, a * 0.75)
    for i = 0, 6 do
      local hx = (i * 40 + f * 2) % 250 - 10
      local hy = (i * 20 + math.floor(Sin((hx + f * 4) % 256, 8))) % 100 + 10
      love.graphics.circle("fill", hx - 3, hy, 4)
      love.graphics.circle("fill", hx + 3, hy, 4)
      love.graphics.polygon("fill", hx - 6, hy + 2, hx + 6, hy + 2, hx, hy + 8)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.HeartsBackground = AnimTasks.HeartsBackground
AnimTasks.REGISTRY.AnimTask_HeartsBackground = AnimTasks.HeartsBackground

--- pret AnimTask_ScaryFace (pokefirered/src/battle_anim_effects_2.c:3360)
function AnimTasks.ScaryFace(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.MID_FIELD
  local tx, ty = vm:battlerCenter("target")

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    local scale = 0.6 + (f / dur) * 0.8
    -- Looming dark shadowy phantom mask zooming behind target
    love.graphics.setColor(0.10, 0.02, 0.15, a * 0.70)
    love.graphics.circle("fill", tx, ty, 32 * scale)
    -- Glowing demonic red eyes
    love.graphics.setColor(0.95, 0.15, 0.10, a * 0.95)
    love.graphics.circle("fill", tx - 12 * scale, ty - 6 * scale, 4 * scale)
    love.graphics.circle("fill", tx + 12 * scale, ty - 6 * scale, 4 * scale)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.ScaryFace = AnimTasks.ScaryFace
AnimTasks.REGISTRY.AnimTask_ScaryFace = AnimTasks.ScaryFace

--- pret AnimTask_CreateRaindrops (Rain Dance)
function AnimTasks.CreateRaindrops(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 36
  t.z = AnimSprites.Z.GLOBAL_FRONT

  if not t._particles then
    t._particles = {}
    for _ = 1, 18 do
      t._particles[#t._particles + 1] = {
        x = math.random(-20, 240),
        y = math.random(-20, 100),
        vx = -4.0,
        vy = 7.0,
        len = math.random(10, 18),
      }
    end
  end

  if t._particles then
    for _, p in ipairs(t._particles) do
      p.x = p.x + p.vx
      p.y = p.y + p.vy
      if p.y > 115 or p.x < -20 then
        p.x = math.random(60, 260)
        p.y = -15
      end
    end
  end

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    if not task._particles then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    love.graphics.setColor(0.60, 0.80, 1.00, a * 0.70)
    love.graphics.setLineWidth(1.5)
    for _, p in ipairs(task._particles) do
      love.graphics.line(p.x, p.y, p.x + p.vx * 1.5, p.y + p.vy * 1.5)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.CreateRaindrops = AnimTasks.CreateRaindrops
AnimTasks.REGISTRY.AnimTask_CreateRaindrops = AnimTasks.CreateRaindrops


--- Subsystem B: Shadow Clones, Afterimages & Silhouette Transfers

--- pret AnimTask_NightShadeClone & NightmareClone (pokefirered/src/battle_anim_ghost.c:280)
function AnimTasks.NightShadeClone(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.MID_FIELD
  local Anim = require("src.core.game3.battle.anim")
  local atkSide = vm:attackerSide()
  local ax, ay = vm:battlerCenter(atkSide)

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    local scale = 1.0 + (f / dur) * 0.5
    -- Dark rising shadow silhouette clone
    love.graphics.setColor(0.08, 0.04, 0.12, a * 0.80)
    love.graphics.circle("fill", ax + 6, ay - 8, 28 * scale)
    love.graphics.setColor(0.85, 0.10, 0.10, a * 0.90)
    love.graphics.circle("fill", ax - 4, ay - 14, 3)
    love.graphics.circle("fill", ax + 14, ay - 14, 3)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.NightShadeClone = AnimTasks.NightShadeClone
AnimTasks.REGISTRY.AnimTask_NightShadeClone = AnimTasks.NightShadeClone
AnimTasks.REGISTRY.NightmareClone = AnimTasks.NightShadeClone
AnimTasks.REGISTRY.AnimTask_NightmareClone = AnimTasks.NightShadeClone

--- pret AnimTask_DestinyBondWhiteShadow
function AnimTasks.DestinyBondWhiteShadow(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 30
  t.z = AnimSprites.Z.GLOBAL_BEHIND
  local ax, ay = vm:battlerCenter(vm:attackerSide())

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    local rad = math.min(32, f * 1.5)
    love.graphics.setColor(0.95, 0.98, 1.00, a * 0.65)
    love.graphics.ellipse("fill", ax, ay + 24, rad, rad * 0.4)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.DestinyBondWhiteShadow = AnimTasks.DestinyBondWhiteShadow
AnimTasks.REGISTRY.AnimTask_DestinyBondWhiteShadow = AnimTasks.DestinyBondWhiteShadow

--- pret Memento Tasks (InitMementoShadow, MoveAttackerMementoShadow, MementoHandleBg, MoveTargetMementoShadow)
function AnimTasks.MementoShadow(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.MID_FIELD
  local ax, ay = vm:battlerCenter(vm:attackerSide())
  local tx, ty = vm:battlerCenter("target")

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local u = math.min(1.0, f / 24)
    local curX = ax + (tx - ax) * u
    local curY = ay + (ty - ay) * u
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    love.graphics.setColor(0.06, 0.02, 0.08, a * 0.85)
    love.graphics.ellipse("fill", curX, curY + 20, 24, 10)
    love.graphics.circle("fill", curX, curY, 16)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.InitMementoShadow = AnimTasks.MementoShadow
AnimTasks.REGISTRY.MoveAttackerMementoShadow = AnimTasks.MementoShadow
AnimTasks.REGISTRY.MementoHandleBg = AnimTasks.MementoShadow
AnimTasks.REGISTRY.MoveTargetMementoShadow = AnimTasks.MementoShadow
AnimTasks.REGISTRY.SpiteTargetShadow = AnimTasks.MementoShadow

--- pret RolePlaySilhouette
function AnimTasks.RolePlaySilhouette(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 28
  t.z = AnimSprites.Z.MID_FIELD
  local ax, ay = vm:battlerCenter(vm:attackerSide())
  local tx, ty = vm:battlerCenter("target")

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local u = math.min(1.0, f / 20)
    local curX = tx + (ax - tx) * u
    local curY = ty + (ay - ty) * u
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    love.graphics.setColor(0.40, 0.85, 0.95, a * 0.50)
    love.graphics.circle("fill", curX, curY, 24)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.RolePlaySilhouette = AnimTasks.RolePlaySilhouette
AnimTasks.REGISTRY.AnimTask_RolePlaySilhouette = AnimTasks.RolePlaySilhouette
AnimTasks.REGISTRY.TransparentCloneGrowAndShrink = AnimTasks.RolePlaySilhouette


--- Subsystem C: Screen Distortions, Spotlights & Lighting

--- pret ExtrasensoryDistortion & UproarDistortion
function AnimTasks.ScreenDistortionWobble(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  local Anim = require("src.core.game3.battle.anim")
  local u = math.sin((frame / dur) * math.pi)
  Anim.setScreenEffect({ type = "custom_blend", coeff = u * 0.35, targetColor = { 0.7, 0.3, 0.9 } })

  if frame >= dur then
    Anim.setScreenEffect(nil)
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.ExtrasensoryDistortion = AnimTasks.ScreenDistortionWobble
AnimTasks.REGISTRY.AnimTask_ExtrasensoryDistortion = AnimTasks.ScreenDistortionWobble
AnimTasks.REGISTRY.UproarDistortion = AnimTasks.ScreenDistortionWobble
AnimTasks.REGISTRY.AnimTask_UproarDistortion = AnimTasks.ScreenDistortionWobble

--- pret CreateSpotlight & RemoveSpotlight (Spotlight, Follow Me)
function AnimTasks.Spotlight(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.GLOBAL_FRONT
  local tx, ty = vm:battlerCenter(vm:resolveBattlerSide("target"))

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    -- Elliptical yellow spotlight cone shining down from top
    love.graphics.setColor(1.00, 0.95, 0.60, a * 0.45)
    love.graphics.polygon("fill", 120, -10, tx - 32, ty + 24, tx + 32, ty + 24)
    love.graphics.ellipse("fill", tx, ty + 24, 32, 12)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.CreateSpotlight = AnimTasks.Spotlight
AnimTasks.REGISTRY.AnimTask_CreateSpotlight = AnimTasks.Spotlight
AnimTasks.REGISTRY.RemoveSpotlight = stub_task
AnimTasks.REGISTRY.AnimTask_RemoveSpotlight = stub_task

--- pret MorningSunLightBeam & MoonlightEndFade
function AnimTasks.MorningSunLightBeam(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.GLOBAL_FRONT
  local ax, ay = vm:battlerCenter(vm:attackerSide())

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    -- Divine descending sunbeams
    love.graphics.setColor(1.00, 0.98, 0.70, a * 0.50)
    love.graphics.polygon("fill", ax - 10, -10, ax + 10, -10, ax + 36, ay + 30, ax - 36, ay + 30)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.MorningSunLightBeam = AnimTasks.MorningSunLightBeam
AnimTasks.REGISTRY.AnimTask_MorningSunLightBeam = AnimTasks.MorningSunLightBeam
AnimTasks.REGISTRY.MoonlightEndFade = stub_task

--- pret GlareEyeDots (Glare)
function AnimTasks.GlareEyeDots(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 28
  t.z = AnimSprites.Z.GLOBAL_FRONT
  local ax, ay = vm:battlerCenter(vm:attackerSide())

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 4) and (f / 4) or ((f >= dur - 4) and ((dur - f) / 4) or 1.0)
    -- Piercing glowing crimson eyes
    love.graphics.setColor(1.00, 0.15, 0.15, a * 0.95)
    love.graphics.circle("fill", ax - 6, ay - 10, 3)
    love.graphics.circle("fill", ax + 6, ay - 10, 3)
    love.graphics.setColor(1.00, 0.85, 0.85, a * 0.90)
    love.graphics.circle("fill", ax - 6, ay - 10, 1.2)
    love.graphics.circle("fill", ax + 6, ay - 10, 1.2)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.GlareEyeDots = AnimTasks.GlareEyeDots
AnimTasks.REGISTRY.AnimTask_GlareEyeDots = AnimTasks.GlareEyeDots

--- pret ElectricChargingParticles, DrillPeckHitSplats, GrudgeFlames, BarrageBall
function AnimTasks.GenericCombatFX(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.ElectricChargingParticles = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.DrillPeckHitSplats = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.GrudgeFlames = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.BarrageBall = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.StatusClearedEffect = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.RapinSpinMonElevation = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.ImprisonOrbs = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.SketchDrawMon = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.SkillSwap = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.Teleport = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.ConversionAlphaBlend = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.Conversion2AlphaBlend = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.RotateAuroraRingColors = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.AnimateGustTornadoPalette = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.MusicNotesClearRainbowBlend = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.LoadMusicNotesPals = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.FreeMusicNotesPals = AnimTasks.GenericCombatFX
AnimTasks.REGISTRY.AllocBackupPalBuffer = stub_task
AnimTasks.REGISTRY.FreeBackupPalBuffer = stub_task
AnimTasks.REGISTRY.CopyPalUnfadedFromBackup = stub_task
AnimTasks.REGISTRY.BlendBackground = stub_task
AnimTasks.REGISTRY.StartSinAnimTimer = stub_task
AnimTasks.REGISTRY.SetAttackerInvisibleWaitForSignal = stub_task
AnimTasks.REGISTRY.InitAttackerFadeFromInvisible = stub_task
AnimTasks.REGISTRY.VoltTackleAttackerReappear = stub_task


--- Subsystem D: Battler Movement & Metadata Evaluators

function AnimTasks.AttackerPunchWithTrace(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 20
  local Anim = require("src.core.game3.battle.anim")
  local pAtk = Anim.present(vm:attackerSide())
  if frame < 10 and pAtk then
    pAtk.ox = math.floor(math.sin((frame / 10) * math.pi) * 12)
  elseif frame >= 10 and pAtk then
    pAtk.ox = 0
  end
  if frame >= dur then
    if pAtk then pAtk.ox = 0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.AttackerPunchWithTrace = AnimTasks.AttackerPunchWithTrace
AnimTasks.REGISTRY.HelpingHandAttackerMovement = AnimTasks.AttackerPunchWithTrace
AnimTasks.REGISTRY.TeeterDanceMovement = AnimTasks.AttackerPunchWithTrace
AnimTasks.REGISTRY.FlailMovement = AnimTasks.AttackerPunchWithTrace
AnimTasks.REGISTRY.OdorSleuthMovement = AnimTasks.AttackerPunchWithTrace
AnimTasks.REGISTRY.TormentAttacker = AnimTasks.AttackerPunchWithTrace
AnimTasks.REGISTRY.Rollout = AnimTasks.AttackerPunchWithTrace
AnimTasks.REGISTRY.LeafBlade = AnimTasks.AttackerPunchWithTrace

--- Dynamic Metadata and Query Evaluators
function AnimTasks.QueryStateTask(t, vm)
  destroy_task(t)
end
AnimTasks.REGISTRY.GetRolloutCounter = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.GetFuryCutterHitCount = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.IsFuryCutterHitRight = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.GetReturnPowerLevel = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.GetFrustrationPowerLevel = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.GetSeismicTossDamageLevel = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.IsPowerOver99 = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.GetBattleTerrain = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.GetWeather = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.IsContest = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.IsTargetPlayerSide = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.GetIsDoomDesireHitTurn = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.IsHealingMove = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.IsAttackerBehindSubstitute = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.IsBallBlockedByTrainerOrDodged = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.IsMonInvisible = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.IsTargetSameSide = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.GetBattlersFromArg = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.GetTrappedMoveAnimId = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.SnatchOpposingMonMove = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.SnatchPartnerMove = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.SetAnimAttackerAndTargetForEffectAtk = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.SetAnimAttackerAndTargetForEffectTgt = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.SetAnimTargetToBattlerTarget = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.SetTargetToEffectBattler = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.SafariGetReaction = AnimTasks.QueryStateTask
AnimTasks.REGISTRY.SafariOrGhost_DecideAnimSides = AnimTasks.QueryStateTask

-- =========================================================================
-- Pret Alignment: Movement, Special Combat, Buffers & System Subroutines
-- =========================================================================

--- pret AnimTask_DigDownMovement & AnimTask_DigUpMovement (battle_anim_ground.c)
function AnimTasks.DigDownMovement(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  local isDisappear = (tonumber(t.data[0]) or 0) ~= 0
  if p then
    if not isDisappear then
      -- Bounce down into hole
      local u = frame / dur
      p.oy = math.floor(u * 32)
      p.alpha = math.max(0, 1.0 - u * 1.2)
    else
      p.oy = 40
      p.invisible = true
    end
  end
  if frame >= dur then
    if p then p.invisible = true end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.DigDownMovement = AnimTasks.DigDownMovement
AnimTasks.REGISTRY.AnimTask_DigDownMovement = AnimTasks.DigDownMovement

function AnimTasks.DigUpMovement(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 20
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  local isRise = (tonumber(t.data[0]) or 0) ~= 0
  if p then
    p.invisible = false
    if isRise then
      local u = 1.0 - (frame / dur)
      p.oy = math.floor(u * 32)
      p.alpha = math.min(1.0, (frame / dur) * 1.5)
    else
      p.oy = 0
      p.alpha = 1.0
    end
  end
  if frame >= dur then
    if p then p.oy = 0; p.alpha = 1.0; p.invisible = false end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.DigUpMovement = AnimTasks.DigUpMovement
AnimTasks.REGISTRY.AnimTask_DigUpMovement = AnimTasks.DigUpMovement

--- pret AnimTask_SkullBashPosition (battle_anim_effects_1.c)
function AnimTasks.SkullBashPosition(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 16
  local Anim = require("src.core.game3.battle.anim")
  local side = vm:attackerSide()
  local p = Anim.present(side)
  local mode = tonumber(t.data[0]) or 0
  local dir = (side == "player") and -1 or 1
  if p then
    if mode == 0 then
      -- Step back to charge
      local u = math.min(1.0, frame / dur)
      p.ox = math.floor(dir * 10 * u)
    else
      -- Rush forward
      local u = math.min(1.0, frame / dur)
      p.ox = math.floor(-dir * 16 * (1.0 - u))
    end
  end
  if frame >= dur then
    if p and mode ~= 0 then p.ox = 0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.SkullBashPosition = AnimTasks.SkullBashPosition
AnimTasks.REGISTRY.AnimTask_SkullBashPosition = AnimTasks.SkullBashPosition

--- pret AnimTask_ExtremeSpeedImpact & AnimTask_ExtremeSpeedMonReappear (battle_anim_effects_2.c)
function AnimTasks.ExtremeSpeedImpact(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 18
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:targetSide())
  if p then
    local phase = frame % 4
    local amp = math.max(1, 8 - math.floor(frame / 2))
    p.ox = (phase < 2) and amp or -amp
  end
  if frame >= dur then
    if p then p.ox = 0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.ExtremeSpeedImpact = AnimTasks.ExtremeSpeedImpact
AnimTasks.REGISTRY.AnimTask_ExtremeSpeedImpact = AnimTasks.ExtremeSpeedImpact

function AnimTasks.ExtremeSpeedMonReappear(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 14
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  if p then
    p.invisible = (frame % 2 == 1)
  end
  if frame >= dur then
    if p then p.invisible = false end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.ExtremeSpeedMonReappear = AnimTasks.ExtremeSpeedMonReappear
AnimTasks.REGISTRY.AnimTask_ExtremeSpeedMonReappear = AnimTasks.ExtremeSpeedMonReappear

--- pret AnimTask_AttackerStretchAndDisappear (battle_anim_effects_2.c)
function AnimTasks.AttackerStretchAndDisappear(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 18
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  if p then
    local u = frame / dur
    p.sy = 1.0 + u * 0.8
    p.sx = math.max(0.1, 1.0 - u * 0.8)
    p.alpha = math.max(0, 1.0 - u)
  end
  if frame >= dur then
    if p then p.sx = 1.0; p.sy = 1.0; p.invisible = true end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.AttackerStretchAndDisappear = AnimTasks.AttackerStretchAndDisappear
AnimTasks.REGISTRY.AnimTask_AttackerStretchAndDisappear = AnimTasks.AttackerStretchAndDisappear

--- pret AnimTask_SlideMonForFocusBand (battle_anim_effects_3.c)
function AnimTasks.SlideMonForFocusBand(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 16
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  local dir = (vm:attackerSide() == "player") and -1 or 1
  if p then
    local u = math.sin((frame / dur) * math.pi)
    p.ox = math.floor(dir * 10 * u)
  end
  if frame >= dur then
    if p then p.ox = 0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.SlideMonForFocusBand = AnimTasks.SlideMonForFocusBand
AnimTasks.REGISTRY.AnimTask_SlideMonForFocusBand = AnimTasks.SlideMonForFocusBand

--- pret AnimTask_SpeedDust (battle_anim_effects_2.c)
function AnimTasks.SpeedDust(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 20
  t.z = AnimSprites.Z.GLOBAL_FRONT
  local ax, ay = vm:battlerCenter(vm:attackerSide())

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = math.max(0, 1.0 - (f / dur))
    love.graphics.setColor(0.85, 0.80, 0.70, a * 0.75)
    for i = 0, 3 do
      local dx = (i * 12 - f * 1.5)
      love.graphics.circle("fill", ax + dx, ay + 22, 3 + (f * 0.2))
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.SpeedDust = AnimTasks.SpeedDust
AnimTasks.REGISTRY.AnimTask_SpeedDust = AnimTasks.SpeedDust

--- pret AnimTask_ThrashMoveMonHorizontal & AnimTask_ThrashMoveMonVertical (battle_anim_effects_2.c)
function AnimTasks.ThrashMoveMonHorizontal(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  if p then
    p.ox = math.floor(math.sin(frame * 0.8) * 12)
  end
  if frame >= dur then
    if p then p.ox = 0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.ThrashMoveMonHorizontal = AnimTasks.ThrashMoveMonHorizontal
AnimTasks.REGISTRY.AnimTask_ThrashMoveMonHorizontal = AnimTasks.ThrashMoveMonHorizontal

function AnimTasks.ThrashMoveMonVertical(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  if p then
    p.oy = math.floor(math.sin(frame * 0.8) * 8)
  end
  if frame >= dur then
    if p then p.oy = 0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.ThrashMoveMonVertical = AnimTasks.ThrashMoveMonVertical
AnimTasks.REGISTRY.AnimTask_ThrashMoveMonVertical = AnimTasks.ThrashMoveMonVertical

--- pret AnimTask_MoveHeatWaveTargets (battle_anim_fire.c)
function AnimTasks.MoveHeatWaveTargets(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:targetSide())
  if p then
    p.ox = math.floor(math.sin(frame * 0.6) * 6)
  end
  if frame >= dur then
    if p then p.ox = 0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.MoveHeatWaveTargets = AnimTasks.MoveHeatWaveTargets
AnimTasks.REGISTRY.AnimTask_MoveHeatWaveTargets = AnimTasks.MoveHeatWaveTargets

--- pret AnimTask_DeepInhale (battle_anim_effects_3.c)
function AnimTasks.DeepInhale(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  if p then
    local u = math.sin((frame / dur) * math.pi)
    p.sx = 1.0 + u * 0.25
    p.sy = 1.0 + u * 0.15
  end
  if frame >= dur then
    if p then p.sx = 1.0; p.sy = 1.0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.DeepInhale = AnimTasks.DeepInhale
AnimTasks.REGISTRY.AnimTask_DeepInhale = AnimTasks.DeepInhale

--- pret AnimTask_WaterSpoutLaunch & AnimTask_WaterSpoutRain (battle_anim_water.c)
function AnimTasks.WaterSpoutLaunch(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.MID_FIELD
  local ax, ay = vm:battlerCenter(vm:attackerSide())

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    local height = math.min(112, f * 6)
    love.graphics.setColor(0.20, 0.55, 0.95, a * 0.80)
    love.graphics.rectangle("fill", ax - 24, ay + 20 - height, 48, height)
    love.graphics.setColor(0.70, 0.90, 1.00, a * 0.90)
    love.graphics.rectangle("fill", ax - 16, ay + 20 - height, 32, height)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.WaterSpoutLaunch = AnimTasks.WaterSpoutLaunch
AnimTasks.REGISTRY.AnimTask_WaterSpoutLaunch = AnimTasks.WaterSpoutLaunch

function AnimTasks.WaterSpoutRain(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 36
  t.z = AnimSprites.Z.GLOBAL_FRONT

  if not t._particles then
    t._particles = {}
    for _ = 1, 24 do
      t._particles[#t._particles + 1] = {
        x = math.random(10, 230),
        y = math.random(-30, 20),
        vy = math.random(5, 9),
      }
    end
  end

  for _, p in ipairs(t._particles) do
    p.y = p.y + p.vy
    if p.y > 115 then p.y = -15; p.x = math.random(10, 230) end
  end

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    if not task._particles then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    love.graphics.setColor(0.35, 0.70, 1.00, a * 0.85)
    love.graphics.setLineWidth(2)
    for _, p in ipairs(task._particles) do
      love.graphics.line(p.x, p.y, p.x, p.y + 12)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.WaterSpoutRain = AnimTasks.WaterSpoutRain
AnimTasks.REGISTRY.AnimTask_WaterSpoutRain = AnimTasks.WaterSpoutRain

--- pret AnimTask_DoomDesireLightBeam (battle_anim_effects_3.c)
function AnimTasks.DoomDesireLightBeam(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 36
  t.z = AnimSprites.Z.GLOBAL_FRONT
  local tx, ty = vm:battlerCenter("target")

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    love.graphics.setColor(1.00, 0.95, 0.40, a * 0.75)
    love.graphics.polygon("fill", tx - 8, -10, tx + 8, -10, tx + 24, ty + 24, tx - 24, ty + 24)
    love.graphics.setColor(1.00, 1.00, 0.90, a * 0.90)
    love.graphics.polygon("fill", tx - 3, -10, tx + 3, -10, tx + 10, ty + 24, tx - 10, ty + 24)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.DoomDesireLightBeam = AnimTasks.DoomDesireLightBeam
AnimTasks.REGISTRY.AnimTask_DoomDesireLightBeam = AnimTasks.DoomDesireLightBeam

--- pret AnimTask_AirCutterProjectile (battle_anim_effects_2.c)
function AnimTasks.AirCutterProjectile(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 20
  t.z = AnimSprites.Z.GLOBAL_FRONT
  local ax, ay = vm:battlerCenter(vm:attackerSide())
  local tx, ty = vm:battlerCenter("target")

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local u = math.min(1.0, f / dur)
    local cx = ax + (tx - ax) * u
    local cy = ay + (ty - ay) * u
    local a = (f <= 4) and (f / 4) or ((f >= dur - 4) and ((dur - f) / 4) or 1.0)
    love.graphics.setColor(0.70, 0.95, 0.90, a * 0.90)
    love.graphics.setLineWidth(2)
    love.graphics.arc("line", cx, cy, 18, -math.pi * 0.4, math.pi * 0.4)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.AirCutterProjectile = AnimTasks.AirCutterProjectile
AnimTasks.REGISTRY.AnimTask_AirCutterProjectile = AnimTasks.AirCutterProjectile

--- pret AnimTask_CreateSmallSolarBeamOrbs (battle_anim_effects_1.c)
function AnimTasks.CreateSmallSolarBeamOrbs(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.GLOBAL_FRONT
  local ax, ay = vm:battlerCenter(vm:attackerSide())

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    love.graphics.setColor(1.00, 0.90, 0.30, a * 0.85)
    for i = 0, 7 do
      local angle = (i / 8) * math.pi * 2 + (f * 0.1)
      local r = math.max(4, 36 - (f * 1.0))
      local px = ax + math.cos(angle) * r
      local py = ay + math.sin(angle) * r
      love.graphics.circle("fill", px, py, 2.5)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.CreateSmallSolarBeamOrbs = AnimTasks.CreateSmallSolarBeamOrbs
AnimTasks.REGISTRY.AnimTask_CreateSmallSolarBeamOrbs = AnimTasks.CreateSmallSolarBeamOrbs

--- pret AnimTask_CurseStretchingBlackBg (battle_anim_ghost.c)
function AnimTasks.CurseStretchingBlackBg(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  t.z = AnimSprites.Z.GLOBAL_BEHIND

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 6) and (f / 6) or ((f >= dur - 6) and ((dur - f) / 6) or 1.0)
    local height = math.min(112, f * 4)
    love.graphics.setColor(0.05, 0.02, 0.08, a * 0.75)
    love.graphics.rectangle("fill", 0, 56 - height / 2, 240, height)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.CurseStretchingBlackBg = AnimTasks.CurseStretchingBlackBg
AnimTasks.REGISTRY.AnimTask_CurseStretchingBlackBg = AnimTasks.CurseStretchingBlackBg

--- pret AnimTask_CastformGfxChange & AnimTask_MusicNotesRainbowBlend (battle_anim_effects_3.c & 1.c)
function AnimTasks.CastformGfxChange(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 20
  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.CastformGfxChange = AnimTasks.CastformGfxChange
AnimTasks.REGISTRY.AnimTask_CastformGfxChange = AnimTasks.CastformGfxChange
AnimTasks.REGISTRY.MusicNotesRainbowBlend = AnimTasks.CastformGfxChange
AnimTasks.REGISTRY.AnimTask_MusicNotesRainbowBlend = AnimTasks.CastformGfxChange

--- pret AnimTask_AlphaFadeIn (battle_anim_mons.c)
function AnimTasks.AlphaFadeIn(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = math.max(8, tonumber(t.data[0]) or 16)
  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.AlphaFadeIn = AnimTasks.AlphaFadeIn
AnimTasks.REGISTRY.AnimTask_AlphaFadeIn = AnimTasks.AlphaFadeIn

--- pret AnimTask_DrawFallingWhiteLinesOnAttacker (battle_anim_utility_funcs.c)
function AnimTasks.DrawFallingWhiteLinesOnAttacker(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  t.z = AnimSprites.Z.GLOBAL_FRONT
  local ax, ay = vm:battlerCenter(vm:attackerSide())

  t.draw = function(task, _vm)
    if not (love and love.graphics) then return end
    local f = task.data[14] or 1
    local a = (f <= 4) and (f / 4) or ((f >= dur - 4) and ((dur - f) / 4) or 1.0)
    love.graphics.setColor(1, 1, 1, a * 0.85)
    love.graphics.setLineWidth(1.5)
    for i = -2, 2 do
      local lx = ax + (i * 10)
      local ly = (ay - 24 + f * 3 + i * 4) % 64 + (ay - 32)
      love.graphics.line(lx, ly, lx, ly + 14)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end

  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.DrawFallingWhiteLinesOnAttacker = AnimTasks.DrawFallingWhiteLinesOnAttacker
AnimTasks.REGISTRY.AnimTask_DrawFallingWhiteLinesOnAttacker = AnimTasks.DrawFallingWhiteLinesOnAttacker

--- pret AnimTask_GrowAndGrayscale & AnimTask_ShrinkTargetCopy (battle_anim_effects_2.c & 1.c)
function AnimTasks.GrowAndGrayscale(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  if p then
    local u = frame / dur
    p.sx = 1.0 + u * 0.3
    p.sy = 1.0 + u * 0.3
    p.grayscale = u
  end
  if frame >= dur then
    if p then p.sx = 1.0; p.sy = 1.0; p.grayscale = 0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.GrowAndGrayscale = AnimTasks.GrowAndGrayscale
AnimTasks.REGISTRY.AnimTask_GrowAndGrayscale = AnimTasks.GrowAndGrayscale

function AnimTasks.ShrinkTargetCopy(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 20
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:targetSide())
  if p then
    local u = 1.0 - (frame / dur)
    p.sx = math.max(0.1, u)
    p.sy = math.max(0.1, u)
    p.alpha = math.max(0, u)
  end
  if frame >= dur then
    if p then p.sx = 1.0; p.sy = 1.0; p.alpha = 1.0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.ShrinkTargetCopy = AnimTasks.ShrinkTargetCopy
AnimTasks.REGISTRY.AnimTask_ShrinkTargetCopy = AnimTasks.ShrinkTargetCopy

--- pret AnimTask_StrongFrustrationGrowAndShrink & AnimTask_SquishAndSweatDroplets (battle_anim_effects_3.c)
function AnimTasks.StrongFrustrationGrowAndShrink(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 24
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  if p then
    local u = math.sin((frame / dur) * math.pi)
    p.sx = 1.0 + u * 0.35
    p.sy = 1.0 + u * 0.35
    p.blendColor = { 1.0, 0.2, 0.2 }
    p.blendCoeff = u * 0.6
  end
  if frame >= dur then
    if p then p.sx = 1.0; p.sy = 1.0; p.blendCoeff = 0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.StrongFrustrationGrowAndShrink = AnimTasks.StrongFrustrationGrowAndShrink
AnimTasks.REGISTRY.AnimTask_StrongFrustrationGrowAndShrink = AnimTasks.StrongFrustrationGrowAndShrink

function AnimTasks.SquishAndSweatDroplets(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 20
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(vm:attackerSide())
  if p then
    local u = math.sin((frame / dur) * math.pi)
    p.sy = 1.0 - u * 0.3
    p.sx = 1.0 + u * 0.2
  end
  if frame >= dur then
    if p then p.sx = 1.0; p.sy = 1.0 end
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.SquishAndSweatDroplets = AnimTasks.SquishAndSweatDroplets
AnimTasks.REGISTRY.AnimTask_SquishAndSweatDroplets = AnimTasks.SquishAndSweatDroplets

--- pret AnimTask_StartSlidingBg & AnimTask_StatsChange
function AnimTasks.StartSlidingBg(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 32
  if frame >= dur then destroy_task(t) end
end
AnimTasks.REGISTRY.StartSlidingBg = AnimTasks.StartSlidingBg
AnimTasks.REGISTRY.AnimTask_StartSlidingBg = AnimTasks.StartSlidingBg

local STAT_ANIM_ID = { [1] = 0, [2] = 1, [3] = 3, [4] = 5, [5] = 6, [6] = 2, [7] = 4 }

-- pokefirered/src/battle_anim_status_effects.c:455
local function stats_change_params(arg)
  arg = tonumber(arg) or 0
  if arg >= 55 and arg <= 58 then
    return arg >= 57, 0xFF, (arg == 56 or arg == 58)
  end
  for _, row in ipairs({ { 15, false, false }, { 22, true, false }, { 39, false, true }, { 46, true, true } }) do
    local stat = arg - row[1] + 1
    if stat >= 1 and stat <= 7 then return row[2], STAT_ANIM_ID[stat], row[3] end
  end
  return nil
end

-- pokefirered/src/battle_anim_utility_funcs.c:444
local STAT_MASK_PAL = { [0] = 2, [1] = 1, [2] = 3, [3] = 4, [4] = 6, [5] = 7, [6] = 8 }

-- pokefirered/src/battle_anim_utility_funcs.c:526
function AnimTasks.StatsChange(t, vm)
  local d = t.data
  local Anim = require("src.core.game3.battle.anim")
  if not t._sc then
    local goesDown, statId, sharply = stats_change_params(vm and vm.animArg)
    if goesDown == nil then
      destroy_task(t)
      return
    end
    local side = vm:attackerSide()
    local mask = {
      tilemap = goesDown and 2 or 1,
      pal = STAT_MASK_PAL[statId] or 5,
      x = goesDown and 64 or 0,
      y = 0,
      eva = 0,
    }
    t._sc = { side = side, mask = mask, dy = goesDown and -3 or 3, wait = 2, down = goesDown }
    d[4] = sharply and 13 or 10
    d[5] = sharply and 30 or 20
    d[10], d[11], d[12], d[15] = 0, 0, 0, 0
    return
  end
  local sc = t._sc
  if sc.wait > 0 then
    sc.wait = sc.wait - 1
    if sc.wait == 0 then
      local p = Anim.present(sc.side)
      if p then p.statMask = sc.mask end
      local SE = require("src.core.game3.se_ids")
      vm:playSe12(sc.down and SE.SE_M_STAT_DECREASE or SE.SE_M_STAT_INCREASE, vm:adjustPanning2(-64))
    end
    return
  end
  local mask = sc.mask
  mask.y = (mask.y + sc.dy) % 256
  if d[15] == 0 then
    d[11] = d[11] + 1
    if d[11] > 1 then
      d[11] = 0
      d[12] = d[12] + 1
      mask.eva = d[12]
      if d[12] == d[4] then d[15] = d[15] + 1 end
    end
  elseif d[15] == 1 then
    d[10] = d[10] + 1
    if d[10] == d[5] then d[15] = d[15] + 1 end
  elseif d[15] == 2 then
    d[11] = d[11] + 1
    if d[11] > 1 then
      d[11] = 0
      d[12] = d[12] - 1
      mask.eva = d[12]
      if d[12] == 0 then d[15] = d[15] + 1 end
    end
  else
    local p = Anim.present(sc.side)
    if p and p.statMask == mask then p.statMask = nil end
    t._sc = nil
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.StatsChange = AnimTasks.StatsChange
AnimTasks.REGISTRY.AnimTask_StatsChange = AnimTasks.StatsChange

function AnimTasks.FakeOut(t, _vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dur = 16
  local Anim = require("src.core.game3.battle.anim")
  if frame < 8 then
    Anim.setScreenEffect({ type = "fade_black", coeff = 0.5 })
  else
    Anim.setScreenEffect(nil)
  end
  if frame >= dur then
    Anim.setScreenEffect(nil)
    destroy_task(t)
  end
end
AnimTasks.REGISTRY.FakeOut = AnimTasks.FakeOut
AnimTasks.REGISTRY.AnimTask_FakeOut = AnimTasks.FakeOut

--- pret Palette Buffers & Generic System Tasks
AnimTasks.REGISTRY.CopyPalFadedToUnfaded = stub_task
AnimTasks.REGISTRY.AnimTask_CopyPalFadedToUnfaded = stub_task
AnimTasks.REGISTRY.CopyPalUnfadedToBackup = stub_task
AnimTasks.REGISTRY.AnimTask_CopyPalUnfadedToBackup = stub_task
AnimTasks.REGISTRY.SubstituteFadeToInvisible = stub_task
AnimTasks.REGISTRY.AnimTask_SubstituteFadeToInvisible = stub_task
AnimTasks.REGISTRY.SwapMonSpriteToFromSubstitute = stub_task
AnimTasks.REGISTRY.AnimTask_SwapMonSpriteToFromSubstitute = stub_task
AnimTasks.REGISTRY.SwitchOutBallEffect = stub_task
AnimTasks.REGISTRY.AnimTask_SwitchOutBallEffect = stub_task
AnimTasks.REGISTRY.SwitchOutShrinkMon = stub_task
AnimTasks.REGISTRY.AnimTask_SwitchOutShrinkMon = stub_task
AnimTasks.REGISTRY.ThrowBall = stub_task
AnimTasks.REGISTRY.AnimTask_ThrowBall = stub_task
AnimTasks.REGISTRY.ThrowBallSpecial = stub_task
AnimTasks.REGISTRY.AnimTask_ThrowBallSpecial = stub_task
AnimTasks.REGISTRY.LoadBallGfx = stub_task
AnimTasks.REGISTRY.AnimTask_LoadBallGfx = stub_task
AnimTasks.REGISTRY.FreeBallGfx = stub_task
AnimTasks.REGISTRY.AnimTask_FreeBallGfx = stub_task
AnimTasks.REGISTRY.LoadBaitGfx = stub_task
AnimTasks.REGISTRY.AnimTask_LoadBaitGfx = stub_task
AnimTasks.REGISTRY.FreeBaitGfx = stub_task
AnimTasks.REGISTRY.AnimTask_FreeBaitGfx = stub_task
AnimTasks.REGISTRY.GhostGetOut = stub_task
AnimTasks.REGISTRY.AnimTask_GhostGetOut = stub_task
AnimTasks.REGISTRY.FlashHealthboxOnLevelUp = stub_task
AnimTasks.REGISTRY.AnimTask_FlashHealthboxOnLevelUp = stub_task
AnimTasks.REGISTRY.LoadHealthboxPalsForLevelUp = stub_task
AnimTasks.REGISTRY.AnimTask_LoadHealthboxPalsForLevelUp = stub_task
AnimTasks.REGISTRY.FreeHealthboxPalsForLevelUp = stub_task
AnimTasks.REGISTRY.AnimTask_FreeHealthboxPalsForLevelUp = stub_task
AnimTasks.REGISTRY.SoundTask_PlayCryWithEcho = stub_task
AnimTasks.REGISTRY.SoundTask_PlaySE2WithPanning = stub_task


AnimTasks._destroy = destroy_task
AnimTasks._clear = clear_task
AnimTasks._stub = stub_task
AnimTasks._Sin = Sin
AnimTasks._Cos = Cos
for _, group in ipairs({ "g1", "g2", "g3", "g4", "g5" }) do
  local ok, mod = pcall(require, "src.core.game3.battle.anim_port." .. group .. "_tasks")
  if ok and type(mod) == "function" then mod = mod(AnimTasks) end
  if ok and type(mod) == "table" then
    for k, fn in pairs(mod) do
      local short = tostring(k):gsub("^AnimTask_", "")
      AnimTasks.REGISTRY[short] = fn
      AnimTasks.REGISTRY["AnimTask_" .. short] = fn
    end
  elseif not ok and not tostring(mod):find("not found") then
    print("[battle.anim] " .. group .. "_tasks: " .. tostring(mod))
  end
end

function AnimTasks.spawn(name, priority, args, vm)
  AnimTasks.init()
  name = tostring(name or "stub")
  -- Strip g prefix / AnimTask_ variants for lookup
  local key = name
  key = key:gsub("^g", "")
  local fn = AnimTasks.REGISTRY[name]
    or AnimTasks.REGISTRY[key]
    or AnimTasks.REGISTRY["AnimTask_" .. key]
  if not fn then
    fn = stub_task
  end
  local t
  for i = 1, AnimTasks.MAX do
    local cand = AnimTasks._pool[i]
    if not cand.active then
      t = cand
      break
    end
  end
  if not t then
    AnimTasks.MAX = AnimTasks.MAX + 1
    t = AnimTasks._pool[AnimTasks.MAX]
    if not t then
      t = { data = {} }
      for j = 0, 15 do t.data[j] = 0 end
      AnimTasks._pool[AnimTasks.MAX] = t
    end
  end
  clear_task(t)
  t.active = true
  t.name = name
  t.priority = tonumber(priority) or 2
  t.func = fn
  if type(args) == "table" then
    for ai, av in ipairs(args) do
      local v = av
      if type(v) == "string" then
        t.data[ai - 1] = v
      else
        t.data[ai - 1] = tonumber(v) or 0
      end
    end
    for ai, av in ipairs(args) do
      if type(av) == "string" then
        t.data[ai - 1] = av
      end
    end
  end
  return t
end

function AnimTasks.update(vm)
  AnimTasks.init()
  for i = 1, AnimTasks.MAX do
    local t = AnimTasks._pool[i]
    if t.active and t.func then
      local ok, err = pcall(t.func, t, vm)
      if not ok then
        print("[battle.anim] task " .. tostring(t.name) .. ": " .. tostring(err))
        destroy_task(t)
      end
    end
  end
end

function AnimTasks.draw(minZ, maxZ, vm)
  if not (love and love.graphics) then return end
  AnimTasks.init()
  for i = 1, AnimTasks.MAX do
    local t = AnimTasks._pool[i]
    if t.active and t.draw then
      local z = t.z or AnimSprites.Z.MID_FIELD
      if (not minZ or z >= minZ) and (not maxZ or z <= maxZ) then
        local ok, err = pcall(t.draw, t, vm)
        if not ok then
          print("[battle.anim] task draw " .. tostring(t.name) .. ": " .. tostring(err))
          clear_task(t)
        end
      end
    end
  end
end

--- Destroy helper for sprite callbacks / tasks that finish themselves.
AnimTasks.destroy = destroy_task

return AnimTasks
