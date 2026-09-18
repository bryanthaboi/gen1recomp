-- Test suite for Phase 2: Palette Blends & Affine Battler Transformations
-- Run: luajit tests/game3_battle_anims_phase2_test.lua

package.path = "?.lua;?/init.lua;" .. package.path

local Anim = require("src.core.game3.battle.anim")
local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")

local passed = 0
local failed = 0

local function test(name, fn)
  Anim.reset({ headless = true })
  AnimTasks.reset()
  AnimSprites.reset()
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print(string.format("  PASS: %s", name))
  else
    failed = failed + 1
    print(string.format("  FAIL: %s -> %s", name, tostring(err)))
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("%s (expected %s, got %s)", msg or "assert_eq failed", tostring(b), tostring(a)), 2)
  end
end

local function assert_near(a, b, eps, msg)
  eps = eps or 0.001
  if math.abs((a or 0) - (b or 0)) > eps then
    error(string.format("%s (expected ~%s, got %s)", msg or "assert_near failed", tostring(b), tostring(a)), 2)
  end
end

local function spawn_now(name, args, v)
  local t = AnimTasks.spawn(name, 2, args, v)
  if t and t.func then t.func(t, v) end
  return t
end

local function make_vm(atkSide)
  local vm = AnimVm.new()
  vm.headless = true
  vm.attacker = (atkSide == "enemy") and 1 or 0
  vm.target = (atkSide == "enemy") and 0 or 1
  return vm
end

print("=== Phase 2: Palette, Blend & Affine Transformations Tests ===")

-- 1. BlendBattleAnimPal
test("BlendBattleAnimPal - background fade_black and restore", function()
  local vm = make_vm("player")
  -- palMask=1 (BG), delay=0, startCoeff=0, targetCoeff=8, color=0 (black)
  AnimTasks.spawn("BlendBattleAnimPal", 2, { 1, 0, 0, 8, 0 }, vm)
  assert_eq(AnimTasks.activeCount(), 1)

  for _ = 1, 9 do
    AnimTasks.update(vm)
  end
  assert_eq(AnimTasks.activeCount(), 0, "task should finish after 9 steps (0..8)")
  local bb = Anim._bgBlend
  assert_eq(bb and bb.coeff, 8, "bg palette blended 8/16")
  assert_eq(bb and bb.color, 0, "bg blend color black")

  -- Fade back out to 0
  AnimTasks.spawn("BlendBattleAnimPal", 2, { 1, 0, 8, 0, 0 }, vm)
  for _ = 1, 9 do
    AnimTasks.update(vm)
  end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(Anim._bgBlend, nil, "bg blend restored")
end)

test("BlendBattleAnimPal - battler palette tinting", function()
  local vm = make_vm("player")
  local pAtk = Anim.present("player")
  local pTgt = Anim.present("enemy")
  -- palMask=2 (attacker), delay=0, start=0, target=16, color=RGB_WHITE (0x7FFF)
  AnimTasks.spawn("BlendBattleAnimPal", 2, { 2, 0, 0, 16, 0x7FFF }, vm)
  for _ = 1, 17 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_near(pAtk.blendCoeff, 1.0)
  assert_near(pAtk.blendColor[1], 1.0)
  assert_eq(pTgt.blendCoeff or 0, 0)
end)

-- 2. BlendBattleAnimPalExclude
test("BlendBattleAnimPalExclude - exclude target", function()
  local vm = make_vm("player")
  -- cmd 1: Not target -> blends attacker & BG (mask 3)
  AnimTasks.spawn("BlendBattleAnimPalExclude", 2, { 1, 0, 0, 4, 0 }, vm)
  for _ = 1, 5 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  local pAtk = Anim.present("player")
  local pTgt = Anim.present("enemy")
  assert_near(pAtk.blendCoeff, 0.25)
  assert_eq(pTgt.blendCoeff or 0, 0)
end)

-- 3. BlendMonInAndOut
test("BlendMonInAndOut - pulse in and out", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  -- whichMon=0 (atk), color=0x7FFF (white), targetCoeff=4, delay=0, repeats=2
  AnimTasks.spawn("BlendMonInAndOut", 2, { 0, 0x7FFF, 4, 0, 2 }, vm)
  assert_eq(AnimTasks.activeCount(), 1)
  -- 2 repeats of 4 steps in + 4 steps out = 16 updates
  for _ = 1, 20 do
    AnimTasks.update(vm)
  end
  assert_eq(AnimTasks.activeCount(), 0, "task should finish after repeat cycles")
  assert_eq(p.blendCoeff, 0)
  assert_eq(p.flash, 0)
end)

-- 4. TraceMonBlended
test("TraceMonBlended - spawn afterimages and lifetime cleanup", function()
  local vm = make_vm("player")
  -- whichMon=0, interval=2, lifetime=4, count=3
  AnimTasks.spawn("TraceMonBlended", 2, { 0, 2, 4, 3 }, vm)
  assert_eq(AnimTasks.activeCount(), 1)
  for _ = 1, 20 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_eq(AnimTasks.activeCount(), 0, "task finishes after all afterimages expire")
  assert_eq(AnimSprites.activeCount(), 0, "all afterimages should be released")
end)

-- 5. AttackerFadeToInvisible & AttackerFadeFromInvisible
test("AttackerFadeToInvisible & FromInvisible", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  AnimTasks.spawn("AttackerFadeToInvisible", 2, { 0 }, vm)
  -- pokefirered/src/battle_anim_dark.c:187
  for _ = 1, 17 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.visible, false)

  AnimTasks.spawn("AttackerFadeFromInvisible", 2, { 0 }, vm)
  AnimTasks.update(vm)
  assert_eq(p.visible, true)
  for _ = 2, 17 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.alpha, 1)
end)

-- 6. RotateMonSpriteToSide
test("RotateMonSpriteToSide - rotate and restore", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  -- duration=10, rotDelta=0x100, whichMon=0, returnMode=1 (reset on end)
  spawn_now("RotateMonSpriteToSide", { 10, 0x100, 0, 1 }, vm)
  AnimTasks.update(vm)
  assert_eq(p.rotation ~= 0, true, "rotation should change")
  for _ = 2, 10 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.rotation, 0, "rotation should be reset")
  assert_eq(p.oy, 0, "vertical offset should be reset")
end)

-- 7. ScaleMonAndRestore
test("ScaleMonAndRestore - scale and bounce back", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  -- dx=8, dy=8, duration=8, whichMon=0
  spawn_now("ScaleMonAndRestore", { 8, 8, 8, 0 }, vm)
  AnimTasks.update(vm)
  assert_eq(p.sx ~= 1, true, "sx should change")
  assert_eq(p.sy ~= 1, true, "sy should change")
  -- 8 frames forward + 8 frames reverse = 16 frames
  for _ = 2, 16 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.sx, 1, "sx restored")
  assert_eq(p.sy, 1, "sy restored")
  assert_eq(p.oy, 0, "oy restored")
end)

-- 8. Minimize
test("Minimize - 3 cycles and recover", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  AnimTasks.spawn("Minimize", 2, {}, vm)
  -- pokefirered/src/battle_anim_effects_2.c:2050
  for _ = 1, 200 do
    AnimSprites.update()
    AnimTasks.update(vm)
  end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.sx, 1)
  assert_eq(p.sy, 1)
  assert_eq(p.oy, 0)
end)

-- 9. Withdraw
test("Withdraw - downward roll, pause, and roll back", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  AnimTasks.spawn("Withdraw", 2, {}, vm)
  -- 22 roll + 30 pause + 22 back = 74 frames
  for _ = 1, 80 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.rotation, 0)
  assert_eq(p.oy, 0)
end)

-- 10. General Affine Tasks: DefenseCurl, Stockpile, SpitUp, Swallow, StretchTargetUp, GrowAndShrink
test("Affine Animations - DefenseCurl", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  AnimTasks.spawn("DefenseCurlDeformMon", 2, {}, vm)
  -- pokefirered/src/battle_anim_effects_3.c:2019
  for _ = 1, 53 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.sx, 1)
  assert_eq(p.sy, 1)
  assert_eq(p.oy, 0)
end)

test("Affine Animations - StockpileDeformMon", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  AnimTasks.spawn("StockpileDeformMon", 2, {}, vm)
  -- pokefirered/src/battle_anim_effects_3.c:2162
  for _ = 1, 76 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.sx, 1)
  assert_eq(p.sy, 1)
  assert_eq(p.oy, 0)
end)

test("Affine Animations - StretchTargetUp", function()
  local vm = make_vm("player")
  local p = Anim.present("enemy")
  AnimTasks.spawn("StretchTargetUp", 2, {}, vm)
  for _ = 1, 25 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.sx, 1)
  assert_eq(p.sy, 1)
  assert_eq(p.oy, 0)
end)

test("Affine Animations - GrowAndShrink (Bulk Up / Swagger)", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  AnimTasks.spawn("GrowAndShrink", 2, {}, vm)
  for _ = 1, 70 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.sx, 1)
  assert_eq(p.sy, 1)
  assert_eq(p.oy, 0)
end)

test("AcidArmor - wave and fade cycle", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  AnimTasks.spawn("AcidArmor", 2, { 0 }, vm)
  -- pokefirered/src/battle_anim_effects_3.c:3222
  for _ = 1, 110 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.alpha, 1)
  assert_eq(p.ox, 0)
end)

test("FacadeColorBlend - color cycle", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  AnimTasks.spawn("FacadeColorBlend", 2, { 0, 24 }, vm)
  -- pokefirered/src/battle_anim_effects_3.c:3802
  AnimTasks.update(vm)
  AnimTasks.update(vm)
  assert_eq(p.blendCoeff, 0.5)
  for _ = 3, 26 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0)
  assert_eq(p.blendCoeff, 0)
end)

test("RockMonBackAndForth - rocking and rotation with side-awareness", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  -- whichMon=0, numRocks=2, speedInc=0
  AnimTasks.spawn("RockMonBackAndForth", 2, { 0, 2, 0 }, vm)
  -- pokefirered/src/battle_anim_effects_3.c:2643
  AnimTasks.update(vm)
  AnimTasks.update(vm)
  assert_eq(AnimTasks.activeCount(), 1)
  assert_eq(p.ox ~= 0, true, "mon should move horizontally while rocking")
  -- Step through all rocking cycles (halfDur=8: 8 + 16 + 8 = 32 frames per rock * 2 = 64 frames)
  for _ = 2, 70 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0, "rocking task should complete")
  assert_eq(p.ox, 0, "ox restored")
  assert_eq(p.oy, 0, "oy restored")
  assert_eq(p.rotation, 0, "rotation restored")
end)

test("ComplexPaletteBlend - alternate tint cycling", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  -- palMask=2 (attacker), delay=2, numCycles=2, color1=32767 (white), coeff1=16, color2=0 (black), coeff2=0
  AnimTasks.spawn("ComplexPaletteBlend", 2, { 2, 2, 2, 32767, 16, 0, 0 }, vm)
  AnimTasks.update(vm)
  assert_eq(AnimTasks.activeCount(), 1)
  assert_eq(p.blendCoeff > 0, true, "initial tint active")
  for _ = 2, 20 do AnimTasks.update(vm) end
  assert_eq(AnimTasks.activeCount(), 0, "complex blend finishes")
  assert_eq(p.blendCoeff, 0, "blend restored")
end)

test("FlashAnimTagWithColor - flash cycle count and termination", function()
  local vm = make_vm("player")
  -- tag=10005, delay=2, numFlashes=3, color=32767, coeff=16
  spawn_now("FlashAnimTagWithColor", { 10005, 2, 3, 32767, 16 }, vm)
  assert_eq(AnimTasks.activeCount(), 1)
  local n = 0
  while AnimTasks.activeCount() > 0 and n < 200 do AnimTasks.update(vm) n = n + 1 end
  assert_eq(AnimTasks.activeCount(), 0, "flash task terminates after 3 palette-fade cycles")
end)

-- 11. Full Move Execution Verification for Phase 2 Moves
local phase2Moves = {
  { id = 111, name = "MOVE_DEFENSE_CURL" },
  { id = 107, name = "MOVE_MINIMIZE" },
  { id = 110, name = "MOVE_WITHDRAW" },
  { id = 339, name = "MOVE_BULK_UP" },
  { id = 207, name = "MOVE_SWAGGER" },
  { id = 263, name = "MOVE_FACADE" },
  { id = 97,  name = "MOVE_AGILITY" },
  { id = 151, name = "MOVE_ACID_ARMOR" },
  { id = 144, name = "MOVE_TRANSFORM" },
  { id = 254, name = "MOVE_STOCKPILE" },
  { id = 255, name = "MOVE_SPIT_UP" },
  { id = 256, name = "MOVE_SWALLOW" },
  { id = 96,  name = "MOVE_MEDITATE" },
  { id = 37,  name = "MOVE_THRASH" },
  { id = 148, name = "MOVE_FLASH" },
  { id = 267, name = "MOVE_CAMOUFLAGE" },
  { id = 345, name = "MOVE_MAGICAL_LEAF" },
  { id = 174, name = "MOVE_CURSE" },
  { id = 204, name = "MOVE_CHARM" },
  { id = 321, name = "MOVE_TICKLE" },
  { id = 343, name = "MOVE_COVET" },
  { id = 38,  name = "MOVE_DOUBLE_EDGE" },
  { id = 63,  name = "MOVE_HYPER_BEAM" },
  { id = 14,  name = "MOVE_SWORDS_DANCE" },
  { id = 160, name = "MOVE_CONVERSION" },
  { id = 153, name = "MOVE_EXPLOSION" },
}

local okDs, Dataset = pcall(require, "src.core.game3.dataset")
local cache = okDs and Dataset.cache and Dataset.cache() or nil
local packSrc = cache and cache.read and cache:read("data/generated/gba/pokemon/battle_anims/pack.lua")
if not packSrc then
  local f = io.open("data/generated/gba/pokemon/battle_anims/pack.lua", "r")
  if f then packSrc = f:read("*a"); f:close() end
end

if packSrc then
  local chunk = loadstring and loadstring(packSrc) or load(packSrc)
  local pack = chunk()
  for _, m in ipairs(phase2Moves) do
    test("Full Move Execution: " .. m.name, function()
      local script = pack.moves[m.id]
      if not script then
        error("Move " .. m.name .. " (id " .. m.id .. ") not found in pack")
      end
      Anim.reset({ headless = true })
      AnimTasks.reset()
      AnimSprites.reset()
      local vm = AnimVm.new()
      vm:setPack(pack)
      vm:launch(script, { attackerSide = "player", isReversed = false })
      local maxTicks = 360
      local ticks = 0
      while vm:busy() and ticks < maxTicks do
        ticks = ticks + 1
        vm:update(1 / 60)
      end
      assert_eq(vm:busy(), false, m.name .. " should finish cleanly")
      -- Present state restored
      local p = Anim.present("player")
      assert_eq(p.sx, 1, m.name .. " sx restored")
      assert_eq(p.sy, 1, m.name .. " sy restored")
      assert_eq(p.rotation, 0, m.name .. " rotation restored")
      assert_eq(p.oy, 0, m.name .. " oy restored")
    end)
  end
end

print(string.format("\nPhase 2 Summary: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
