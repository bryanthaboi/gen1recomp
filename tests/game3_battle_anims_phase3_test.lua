-- tests/game3_battle_anims_phase3_test.lua
-- Unit and integration tests for Phase 3: Elemental FX, Particle Generators & Wave Systems

package.path = package.path .. ";./?.lua"
require("tests.game3_cache").requireData("game3_battle_anims_phase3_test", "pokemon/battle_anims/pack.lua")

local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
local AnimVm = require("src.core.game3.battle.anim_vm")
local Anim = require("src.core.game3.battle.anim")

local passed = 0
local failed = 0

local function test(name, fn)
  AnimTasks.reset()
  AnimSprites.reset()
  Anim.reset({ headless = true })
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. " -> " .. tostring(err))
  end
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "assert_eq failed", tostring(b), tostring(a)), 2)
  end
end

local function make_vm(attackerSide)
  attackerSide = attackerSide or "player"
  local targetSide = (attackerSide == "player") and "enemy" or "player"
  local vm = AnimVm.new()
  vm._attackerSide = attackerSide
  vm._targetSide = targetSide
  return vm
end

print("=== Phase 3: Elemental FX & Particle Generators Tests ===")

-- 1. Water & Wave Callbacks
test("SmallDriftingBubbles - Q8.8 drift and 21-frame lifetime", function()
  local spr = AnimSprites.acquire({
    x = 100, y = 80, z = AnimSprites.Z.FRONT,
    callback = AnimCallbacks.SmallDriftingBubbles
  })
  assert_eq(AnimSprites.activeCount(), 1)
  -- pokefirered/src/battle_anim_water.c:1027
  for _ = 1, 21 do
    AnimSprites.update()
  end
  assert_eq(AnimSprites.activeCount(), 1)
  AnimSprites.update()
  assert_eq(AnimSprites.activeCount(), 0, "should destroy after the init frame + 21 steps")
end)

test("BubbleEffect - sine wave oscillation and burst", function()
  local spr = AnimSprites.acquire({
    x = 100, y = 80, z = AnimSprites.Z.FRONT, template = "gPoisonBubbleSpriteTemplate",
    callback = AnimCallbacks.BubbleEffect
  })
  -- pokefirered/src/battle_anim_poison.c:290
  for _ = 1, 10 do
    AnimSprites.update()
  end
  assert_eq(spr.oy < 0, true, "bubble rises upward")
  for _ = 11, 35 do
    AnimSprites.update()
  end
  assert_eq(AnimSprites.activeCount(), 0, "bubble bursts when its affine anim ends")
end)

test("CreateSurfWave - surging wave with scanline traversal and collision", function()
  local vm = make_vm("player")
  local pTgt = Anim.present("enemy")
  local t = AnimTasks.spawn("CreateSurfWave", 2, {}, vm)
  assert_eq(AnimTasks.activeCount(), 1)
  AnimTasks.update(vm)
  assert_eq(type(t.draw), "function", "CreateSurfWave must attach a draw function")
  -- pokefirered/src/battle_anim_water.c:877
  for f = 2, 25 do
    AnimTasks.update(vm)
    AnimSprites.update()
    assert_eq(t._bg1x < 0, true, "wave scrolls horizontally across arena")
  end
  assert_eq(bit.band(t._scan[1], 0x1F) > 0, true, "scanline blend band is active")
  assert_eq(AnimTasks.activeCount(), 1)
  for _ = 26, 200 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_eq(AnimTasks.activeCount(), 0, "wave task completes cleanly")
  assert_eq(pTgt.ox, 0, "target ox restored")
  assert_eq(pTgt.oy, 0, "target oy restored")
end)

test("LoadSandstormBackground - swirling sandstorm background and dust streaks", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("LoadSandstormBackground", 2, {}, vm)
  assert_eq(AnimTasks.activeCount(), 1)
  AnimTasks.update(vm)
  assert_eq(type(t.draw), "function", "LoadSandstormBackground must attach a draw function")
  -- pokefirered/src/battle_anim_rock.c:416
  for _ = 2, 40 do AnimTasks.update(vm) end
  assert_eq(vm.bldAlpha and vm.bldAlpha.eva, 7, "sandstorm fades BG1 in to eva 7")
  for _ = 41, 200 do
    AnimTasks.update(vm)
  end
  assert_eq(AnimTasks.activeCount(), 0, "sandstorm finishes cleanly")
end)

test("AnimTasks.draw - safely iterates and executes active task draw routines", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("CreateSurfWave", 2, {}, vm)
  AnimTasks.update(vm)
  -- Should execute without throw even if love.graphics is absent/headless
  AnimTasks.draw(0, 999, vm)
  assert_eq(t.active, true)
end)

-- 2. Fire & Volcano Callbacks
test("FirePlume - flame pillar with upward velocity", function()
  -- pokefirered/src/battle_anim_fire.c:486
  local spr = AnimSprites.acquire({
    x = 100, y = 100, z = AnimSprites.Z.FRONT,
    callback = AnimCallbacks.FirePlume
  })
  spr._args = { 0, 0, 20, 10, 0, -3 }
  AnimSprites.update()
  AnimSprites.update()
  assert_eq(spr.oy < 0, true, "flame moves upward")
  for _ = 3, 21 do
    AnimSprites.update()
  end
  assert_eq(AnimSprites.activeCount(), 0, "flame extinguishes")
end)

test("FireSpiralOutward - spiral vortex expanding trajectory", function()
  -- pokefirered/src/battle_anim_fire.c:703
  local spr = AnimSprites.acquire({
    x = 100, y = 100, z = AnimSprites.Z.FRONT,
    callback = AnimCallbacks.FireSpiralOutward
  })
  spr._args = { 0, 0, 24, 0, 0 }
  AnimSprites.update()
  assert_eq(spr.ox ~= nil and spr.oy ~= nil, true)
  for _ = 2, 27 do
    AnimSprites.update()
  end
  assert_eq(AnimSprites.activeCount(), 0, "spiral finishes")
end)

test("EruptionLaunchRocks - volcanic ballistic rock launch", function()
  local vm = make_vm("player")
  AnimTasks.spawn("EruptionLaunchRocks", 2, {}, vm)
  assert_eq(AnimTasks.activeCount(), 1)
  -- pokefirered/src/battle_anim_fire.c:770
  for _ = 1, 200 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_eq(AnimTasks.activeCount(), 0, "eruption completes")
end)

-- 3. Electric & Energy FX
test("VoltTackleBolt - stepped lightning path", function()
  local vm = make_vm("player")
  AnimTasks.spawn("VoltTackleBolt", 2, { 0 }, vm)
  assert_eq(AnimTasks.activeCount(), 1)
  for _ = 1, 30 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_eq(AnimTasks.activeCount(), 0, "volt tackle bolt reaches destination")
end)

test("ShockWaveProgressingBolt - progressing electrical arcs", function()
  local vm = make_vm("player")
  AnimTasks.spawn("ShockWaveProgressingBolt", 2, {}, vm)
  assert_eq(AnimTasks.activeCount(), 1)
  local sawBolts = false
  -- pokefirered/src/battle_anim_electric.c:1107
  for _ = 1, 200 do
    AnimTasks.update(vm)
    AnimSprites.update()
    if AnimSprites.activeCount() > 0 then sawBolts = true end
  end
  assert_eq(sawBolts, true, "bolt segments spawned")
  assert_eq(AnimTasks.activeCount(), 0, "shock wave progresses and finishes")
end)

test("SolarBeamBigOrb - expanding charge orb", function()
  local spr = AnimSprites.acquire({
    x = 100, y = 80, z = AnimSprites.Z.FRONT,
    callback = AnimCallbacks.SolarBeamBigOrb
  })
  AnimSprites.update()
  assert_eq(spr.w > 0, true)
  for _ = 2, 26 do
    AnimSprites.update()
  end
  assert_eq(AnimSprites.activeCount(), 0, "charge orb completes")
end)

test("WeatherBallDown - descending atmospheric projectile", function()
  local spr = AnimSprites.acquire({
    x = 100, y = 20, z = AnimSprites.Z.FRONT,
    callback = AnimCallbacks.WeatherBallDown
  })
  AnimSprites.update()
  assert_eq(spr.oy >= 0, true)
  for _ = 2, 22 do
    AnimSprites.update()
  end
  assert_eq(AnimSprites.activeCount(), 0, "weather ball impacts")
end)

-- 4. Ice, Ground & Acoustic FX
test("IceEffectParticle - falling crystals and shatter", function()
  local spr = AnimSprites.acquire({
    x = 100, y = 20, z = AnimSprites.Z.FRONT, template = "gIceCrystalHitLargeSpriteTemplate",
    callback = AnimCallbacks.IceEffectParticle
  })
  -- pokefirered/src/battle_anim_ice.c:615
  for _ = 1, 10 do
    AnimSprites.update()
  end
  assert_eq(spr.active and spr.visible ~= false, true, "crystal holds while its affine anim grows")
  local flicker = false
  for _ = 11, 45 do
    AnimSprites.update()
    if spr.active and spr.visible == false then flicker = true end
  end
  assert_eq(flicker, true, "crystal flickers after the affine anim ends")
  assert_eq(AnimSprites.activeCount(), 0, "ice crystal shatters")
end)

test("FrozenIceCube - encasement in ice matrix", function()
  local vm = make_vm("player")
  local pTgt = Anim.present("enemy")
  local t = AnimTasks.spawn("FrozenIceCube", 2, {}, vm)
  AnimTasks.update(vm)
  assert_eq(type(t.draw), "function", "ice cube sprite drawn")
  -- pokefirered/src/battle_anim_status_effects.c:372
  for _ = 2, 11 do AnimTasks.update(vm) end
  assert_eq(t._cube.eva, 9, "ice cube fades in")
  for _ = 12, 120 do
    AnimTasks.update(vm)
  end
  assert_eq(AnimTasks.activeCount(), 0, "ice cube thaws")
  assert_eq(pTgt.blendCoeff or 0, 0, "target palette untouched")
end)

test("Hail - falling hailstorm", function()
  local vm = make_vm("player")
  AnimTasks.spawn("Hail", 2, {}, vm)
  assert_eq(AnimTasks.activeCount(), 1)
  -- pokefirered/src/battle_anim_ice.c:1260
  for _ = 1, 400 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_eq(AnimTasks.activeCount(), 0, "hailstorm finishes")
end)

test("DirtPlumeParticle - ground explosion with gravity", function()
  local vm = Anim.vm()
  -- pokefirered/data/battle_anim_scripts.s
  vm.args[0], vm.args[1], vm.args[2], vm.args[3], vm.args[4], vm.args[5] = 0, 0, 12, 4, -16, 18
  local spr = AnimSprites.acquire({
    x = 100, y = 100, z = AnimSprites.Z.FRONT, template = "gDirtPlumeSpriteTemplate",
    callback = AnimCallbacks.DirtPlumeParticle
  })
  spr._vm = vm
  for _ = 1, 6 do
    AnimSprites.update()
  end
  assert_eq(spr.oy < 0, true, "initial upward blast")
  for _ = 7, 25 do
    AnimSprites.update()
  end
  assert_eq(AnimSprites.activeCount(), 0, "dirt falls back and clears")
end)

test("WaveFromCenterOfTarget - expanding acoustic shockwave", function()
  local spr = AnimSprites.acquire({
    x = 120, y = 80, z = AnimSprites.Z.FRONT, template = "gIceGroundSpikeSpriteTemplate",
    callback = AnimCallbacks.WaveFromCenterOfTarget
  })
  AnimSprites.update()
  assert_eq(spr.w > 0, true)
  -- pokefirered/src/battle_anim_ice.c:272
  for _ = 2, 34 do
    AnimSprites.update()
  end
  assert_eq(AnimSprites.activeCount(), 1, "ice spike still animating")
  for _ = 35, 40 do
    AnimSprites.update()
  end
  assert_eq(AnimSprites.activeCount(), 0, "sound wave expands and dissipates")
end)

test("AtmosphericFog - mist and spore clouds", function()
  local vm = make_vm("player")
  AnimTasks.spawn("MistBallFog", 2, { 20 }, vm)
  assert_eq(AnimTasks.activeCount(), 1)
  -- pokefirered/src/battle_anim_ice.c:1053
  for _ = 1, 200 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_eq(AnimTasks.activeCount(), 0, "fog dissipates")
end)

-- 5. Full Elemental Move Script Executions
local phase3Moves = {
  { id = 57,  name = "MOVE_SURF" },
  { id = 330, name = "MOVE_MUDDY_WATER" },
  { id = 56,  name = "MOVE_HYDRO_PUMP" },
  { id = 61,  name = "MOVE_BUBBLE_BEAM" },
  { id = 55,  name = "MOVE_WATER_GUN" },
  { id = 352, name = "MOVE_WATER_PULSE" },
  { id = 126, name = "MOVE_FIRE_BLAST" },
  { id = 53,  name = "MOVE_FLAMETHROWER" },
  { id = 83,  name = "MOVE_FIRE_SPIN" },
  { id = 284, name = "MOVE_ERUPTION" },
  { id = 315, name = "MOVE_OVERHEAT" },
  { id = 87,  name = "MOVE_THUNDER" },
  { id = 85,  name = "MOVE_THUNDERBOLT" },
  { id = 351, name = "MOVE_SHOCK_WAVE" },
  { id = 342, name = "MOVE_VOLT_TACKLE" },
  { id = 76,  name = "MOVE_SOLAR_BEAM" },
  { id = 311, name = "MOVE_WEATHER_BALL" },
  { id = 192, name = "MOVE_ZAP_CANNON" },
  { id = 59,  name = "MOVE_BLIZZARD" },
  { id = 58,  name = "MOVE_ICE_BEAM" },
  { id = 258, name = "MOVE_HAIL" },
  { id = 89,  name = "MOVE_EARTHQUAKE" },
  { id = 157, name = "MOVE_ROCK_SLIDE" },
  { id = 47,  name = "MOVE_SING" },
  { id = 304, name = "MOVE_HYPER_VOICE" },
  { id = 54,  name = "MOVE_MIST" },
  { id = 114, name = "MOVE_HAZE" },
  { id = 147, name = "MOVE_SPORE" },
}

local okDs, Dataset = pcall(require, "src.core.game3.dataset")
local cache = okDs and Dataset.cache and Dataset.cache() or nil
local packSrc = cache and cache.read and cache:read("data/generated/gba/pokemon/battle_anims/pack.lua")
if not packSrc then
  local f = io.open("data/generated/gba/pokemon/battle_anims/pack.lua", "r")
  if f then packSrc = f:read("*a"); f:close() end
end

local pack = (loadstring or load)(packSrc)()
local vm = AnimVm.new()
vm:setPack(pack)

for _, m in ipairs(phase3Moves) do
  if pack.moves[m.id] then
    test("Full Move Execution: " .. m.name, function()
      AnimTasks.reset()
      AnimSprites.reset()
      Anim.reset({ headless = true })
      vm:launch(pack.moves[m.id], { attackerSide = "player", isReversed = false })
      local maxFrames = 1200
      local frames = 0
      while vm:busy() and frames < maxFrames do
        frames = frames + 1
        vm:update()
      end
      assert_eq(vm:busy(), false, string.format("Move %s timed out after %d frames", m.name, frames))
    end)
  end
end

print(string.format("\nPhase 3 Summary: %d passed, %d failed\n", passed, failed))
if failed > 0 then
  os.exit(1)
end
