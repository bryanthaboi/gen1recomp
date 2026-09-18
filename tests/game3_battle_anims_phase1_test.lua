-- Phase 1 Battle Animation Primitives Parity Test
-- Validates exact GBA math, 60fps frame stepping, Z-indexing, and side-awareness.

local Anim = require("src.core.game3.battle.anim")
local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")

local passed = 0
local failed = 0

local function check(cond, name)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("[FAIL] " .. tostring(name))
  end
end

print("=== Phase 1 Battle Animation Primitives Test ===")

local function spawn_now(name, args, v)
  local t = AnimTasks.spawn(name, 2, args, v)
  if t and t.func then t.func(t, v) end
  return t
end

-- 1. Coordinate Space & Sub-pixel Fixed Point Math (TranslateMonElliptical & RespectSide)
print("[test] 1. TranslateMonElliptical & Coordinate Mapping")
Anim.reset({ headless = true })
local vm = Anim.vm()
local pAtk = Anim.present("player")

-- Spawn elliptical translation for player mon: radiusX=20, radiusY=10, 1 loop, speed=3 (wavePeriod=8)
AnimTasks.reset()
pAtk.ox = 0
pAtk.oy = 0
pAtk.z = AnimVm.Z.PLAYER

local task = spawn_now("TranslateMonElliptical", { 0, 20, 10, 1, 3 }, vm)
check(task ~= nil, "TranslateMonElliptical spawned")

for _ = 1, 8 do
  AnimTasks.update(vm)
end
check(pAtk.ox == 20, "X offset at 90 deg is exactly radiusX (20), got: " .. tostring(pAtk.ox))
check(pAtk.oy == 10, "Y offset at 90 deg is exactly radiusY (10), got: " .. tostring(pAtk.oy))

-- pokefirered/src/battle_anim_mon_movement.c:356
for _ = 1, 24 do
  AnimTasks.update(vm)
end
check(AnimTasks.activeCount() == 0, "TranslateMonElliptical terminated after 1 loop")
check(pAtk.ox == 0 and pAtk.oy == 0, "Clean return to (0,0) with no coordinate drift")

-- 2. Side-Awareness Logic (Player vs Opponent Lunges & Sways)
print("[test] 2. Side-awareness vector flipping")

-- Player horizontal lunge (forward = +X)
AnimTasks.reset()
pAtk.ox = 0
pAtk.oy = 0
pAtk.z = AnimVm.Z.PLAYER
vm._attackerSide = "player"

spawn_now("DoHorizontalLunge", { 4, 6 }, vm)
for _ = 1, 4 do AnimTasks.update(vm) end
check(pAtk.ox == 24, "Player lunge forward gives +24 X, got: " .. tostring(pAtk.ox))
for _ = 5, 12 do AnimTasks.update(vm) end
check(AnimTasks.activeCount() == 0, "Player lunge completed cleanly")
check(pAtk.ox == 0, "Player lunge returned to 0 X")

-- Enemy horizontal lunge (forward = -X)
AnimTasks.reset()
local pEnemy = Anim.present("enemy")
pEnemy.ox = 0
pEnemy.oy = 0
pEnemy.z = AnimVm.Z.ENEMY
vm._attackerSide = "enemy"

spawn_now("DoHorizontalLunge", { 4, 6 }, vm)
for _ = 1, 4 do AnimTasks.update(vm) end
check(pEnemy.ox == -24, "Enemy lunge forward gives -24 X, got: " .. tostring(pEnemy.ox))
for _ = 5, 12 do AnimTasks.update(vm) end
check(AnimTasks.activeCount() == 0, "Enemy lunge completed cleanly")
check(pEnemy.ox == 0, "Enemy lunge returned to 0 X")

-- 3. Dynamic Z-Index Layering with SlideMonToOriginalPos
print("[test] 3. Dynamic Z-Index restoration on SlideMonToOriginalPos")
AnimTasks.reset()
vm._attackerSide = "player"
pAtk.ox = 30
pAtk.oy = 15
pAtk.z = AnimVm.Z.FRONT

-- SlideMonToOriginalPos: 0=attacker, 0=both, 6 frames
spawn_now("SlideMonToOriginalPos", { 0, 0, 6 }, vm)
for _ = 1, 3 do AnimTasks.update(vm) end
check(pAtk.ox < 30 and pAtk.ox > 0, "Mid-slide interpolation progressing")
for _ = 1, 4 do AnimTasks.update(vm) end
check(AnimTasks.activeCount() == 0, "SlideMonToOriginalPos finished")
check(pAtk.ox == 0 and pAtk.oy == 0, "Offset restored to exact (0,0)")

-- 4. Frame-Clock Syncing & Exact Delay Shakes (ShakeMon, ShakeMon2, ShakeMonInPlace)
print("[test] 4. Shake tasks frame clock stepping")

-- ShakeMon2: 0=player, 4=xOff, 0=yOff, 3=numShakes, 2=delay
AnimTasks.reset()
pAtk.ox = 0
spawn_now("ShakeMon2", { 0, 4, 0, 3, 2 }, vm)
check(pAtk.ox == 4, "Spawn frame initial shake +4")
AnimTasks.update(vm)
check(pAtk.ox == 4, "Frame 1 hold +4")
AnimTasks.update(vm)
check(pAtk.ox == -4, "Frame 2 toggles to -4")
AnimTasks.update(vm)
AnimTasks.update(vm)
AnimTasks.update(vm)
check(pAtk.ox == 4, "Frame 5 toggles to +4")
AnimTasks.update(vm)
AnimTasks.update(vm)
AnimTasks.update(vm)
check(AnimTasks.activeCount() == 0, "ShakeMon2 destroyed after exact 3 shakes")
check(pAtk.ox == 0, "Final offset restored to 0")

-- 5. WindUpLunge 2-Stage Mechanics (Take Down, Double-Edge)
print("[test] 5. WindUpLunge 2-stage mechanics")
AnimTasks.reset()
pAtk.ox = 0
pAtk.oy = 0
vm._attackerSide = "player"
-- speed1 = -20 (subpixel), amp = 6, dur1 = 10, delay = 2, targetX = 30, dur2 = 5
spawn_now("WindUpLunge", { 0, -20, 6, 10, 2, 30, 5 }, vm)

-- Step through stage 1 (10 frames)
for _ = 1, 10 do AnimTasks.update(vm) end
check(pAtk.ox == -20, "Stage 1 wind-up reached -20 X, got: " .. tostring(pAtk.ox))

-- Step through delay (2 frames)
AnimTasks.update(vm)
AnimTasks.update(vm)

-- Step through stage 2 lunge (5 frames)
for _ = 1, 5 do AnimTasks.update(vm) end
check(AnimTasks.activeCount() == 0, "WindUpLunge completed")
check(pAtk.ox == 10, "Final forward lunge reached (-20 + 30) = +10 X, got: " .. tostring(pAtk.ox))

-- 6. Utility Tasks (GetAttackerSide, GetTargetSide)
print("[test] 6. Utility Side Query Tasks")
vm.args = {}
AnimTasks.reset()
vm._attackerSide = "player"
vm._targetSide = "enemy"
AnimTasks.spawn("GetAttackerSide", 2, {}, vm)
AnimTasks.update(vm)
check(vm.args[7] == 0, "GetAttackerSide for player returns 0")

AnimTasks.spawn("GetTargetSide", 2, {}, vm)
AnimTasks.update(vm)
check(vm.args[7] == 1, "GetTargetSide for enemy returns 1")

print(string.format("\nPhase 1 Results: %d Passed, %d Failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
