-- tests/game3_battle_anims_phase4_test.lua
-- Unit and integration tests for Phase 4: Dynamic Backgrounds, Clones, Distortions, Spotlights, Substitute & Evaluators

package.path = package.path .. ";./?.lua"
require("tests.game3_cache").requireData("game3_battle_anims_phase4_test", "pokemon/battle_anims/pack.lua")

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

local function assert_true(val, msg)
  if not val then
    error(msg or "assert_true failed", 2)
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

print("=== Phase 4: Dynamic Backgrounds, Clones, Distortions & Specialized Systems Tests ===")

-- ---------------------------------------------------------------------------
-- 1. Dynamic Scrolling Backgrounds & High-Altitude Environments
-- ---------------------------------------------------------------------------

test("MoveSkyUppercutBg - vertical ascending clouds background lifetime and draw hook", function()
  local vm = make_vm("player")
  -- pokefirered/src/battle_anim_fight.c:934
  local t = AnimTasks.spawn("MoveSkyUppercutBg", 2, { 55 }, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")
  for f = 1, 36 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  assert_true(vm.bg3 and vm.bg3.y ~= 0, "BG3 scrolls vertically")
  vm.args[7] = -1
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy once args[7] is -1")
  assert_eq(vm.bg3.x, 0, "BG3 x reset")
end)

test("MoveSeismicTossBg - accelerating descent space background", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("MoveSeismicTossBg", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")
  AnimTasks.update(vm)
  -- pokefirered/src/battle_anim_rock.c:788
  assert_eq(vm.bg3.y, 20, "BG3 scrolls by data[1] / 10")

  for f = 2, 120 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("PositionFissureBgOnBattler - ground abyss fissure", function()
  local vm = make_vm("player")
  vm.args[0], vm.args[1], vm.args[2] = 1, 5, -1
  local t = AnimTasks.spawn("PositionFissureBgOnBattler", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")
  AnimTasks.update(vm)
  -- pokefirered/src/battle_anim_ground.c:719
  assert_true(not t.active, "task hands off to WaitForFissureCompletion at once")
  assert_eq(vm.bg3.x, (32 - 176) % 512, "BG3 x centred on the target")
  for _ = 1, 40 do
    AnimTasks.update(vm)
  end
  assert_eq(vm.bg3.x, (32 - 176) % 512, "BG3 held until args[7] terminator")
  vm.args[7] = -1
  AnimTasks.update(vm)
  assert_eq(vm.bg3.x, 0, "BG3 released")
  assert_eq(AnimTasks.activeCount(), 0, "fissure helper finished")
end)

-- pokefirered/src/battle_anim_effects_3.c:1356
test("SetPsychicBackground - runs until gBattleAnimArgs[7] == 0xFFFF", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("SetPsychicBackground", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")

  for f = 1, 32 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  vm.args[7] = -1
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy once args[7] is 0xFFFF")
end)

test("HeartsBackground - floating hearts background for Attract", function()
  local vm = make_vm("player")
  -- pokefirered/src/battle_anim_effects_2.c:3290
  local t = AnimTasks.spawn("HeartsBackground", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")

  for f = 1, 271 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("ScaryFace - looming demonic phantom mask", function()
  local vm = make_vm("player")
  -- pokefirered/src/battle_anim_effects_2.c:3378
  local t = AnimTasks.spawn("ScaryFace", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")
  AnimTasks.update(vm)
  assert_true(t.z > AnimSprites.Z.PLAYER_MON, "BG1 priority 1 layers over battler sprites")

  for f = 2, 78 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

test("CreateRaindrops - diagonal falling raindrop particles", function()
  local vm = make_vm("player")
  vm.args[0], vm.args[1], vm.args[2] = 0, 3, 60
  local t = AnimTasks.spawn("CreateRaindrops", 2, {}, vm)
  assert_true(t ~= nil and t.active, "task should be spawned")

  -- pokefirered/src/battle_anim_water.c:475
  AnimTasks.update(vm)
  assert_eq(AnimSprites.activeCount(), 1, "first raindrop on frame 1")
  local drop
  for i = 1, AnimSprites.MAX do
    if AnimSprites._pool[i].active then drop = AnimSprites._pool[i] end
  end
  assert_true(drop and drop.z > 200, "raindrop subpriority 4 draws in front of both mons")

  for f = 2, 59 do
    AnimTasks.update(vm)
    AnimSprites.update()
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after duration")
end)

-- ---------------------------------------------------------------------------
-- 2. Shadow Clones, Afterimages & Silhouette Transfers
-- ---------------------------------------------------------------------------

-- pokefirered/src/battle_anim_ghost.c:335
test("NightShadeClone & NightmareClone - pret blend/scale timing", function()
  local vm = make_vm("player")
  local t1 = AnimTasks.spawn("NightShadeClone", 2, {}, vm)
  assert_true(t1 ~= nil and t1.active, "NightShadeClone should spawn")

  for f = 1, 43 do
    AnimTasks.update(vm)
    assert_true(t1.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t1.active, "should destroy after 1 + 27 blend + 16 scale frames")
  local p = Anim.present("player")
  assert_eq(p.sx, 1, "attacker scale restored")

  local t2 = AnimTasks.spawn("NightmareClone", 2, {}, vm)
  assert_true(t2 ~= nil and t2.active, "NightmareClone should spawn")
  for _ = 1, 84 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_true(t2.active, "NightmareClone still fading at frame 84")
  AnimTasks.update(vm)
  assert_true(not t2.active, "NightmareClone done after 85 frames")
end)

-- pokefirered/src/battle_anim_ghost.c:786
test("DestinyBondWhiteShadow - pret blend in/out timing", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("DestinyBondWhiteShadow", 2, {}, vm)
  assert_true(t ~= nil and t.active, "DestinyBondWhiteShadow should spawn")

  for f = 1, 98 do
    AnimTasks.update(vm)
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after 99 frames")
end)

-- pokefirered/src/battle_anim_dark.c:729
test("InitMementoShadow - one-shot setup task", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("InitMementoShadow", 2, {}, vm)
  assert_true(t ~= nil and t.active, "InitMementoShadow should spawn")
  AnimTasks.update(vm)
  assert_true(not t.active, "InitMementoShadow finishes on its first call")
end)

-- pokefirered/src/battle_anim_effects_3.c:3122
test("RolePlaySilhouette - 30 frame fade then 9 frame squash", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("RolePlaySilhouette", 2, {}, vm)
  assert_true(t ~= nil and t.active, "RolePlaySilhouette should spawn")

  for f = 1, 40 do
    AnimTasks.update(vm)
    AnimSprites.update()
    assert_true(t.active, "should remain active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after 41 frames")
end)

-- ---------------------------------------------------------------------------
-- 3. Screen Distortions, Spotlights & Combat FX
-- ---------------------------------------------------------------------------

-- pokefirered/src/battle_anim_psychic.c:891
test("ExtrasensoryDistortion - scanline HOFS on the monbg target, no screen tint", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("ExtrasensoryDistortion", 2, {}, vm)
  assert_true(t ~= nil and t.active, "ExtrasensoryDistortion should spawn")

  for _ = 1, 26 do AnimTasks.update(vm) end
  assert_true(t.active, "still distorting at frame 26")
  AnimTasks.update(vm)
  assert_true(not t.active, "should destroy after 27 frames")
  assert_eq(Anim.screenEffect().type, "none", "never tints the whole screen")
  assert_eq(Anim.present("enemy").hShift, nil, "scanline shift cleared")
end)

-- pokefirered/src/battle_anim_effects_3.c:1653
test("CreateSpotlight / RemoveSpotlight - WIN1 text-area window on, then off", function()
  local vm = make_vm("player")
  local t = AnimTasks.spawn("CreateSpotlight", 2, {}, vm)
  assert_true(t ~= nil and t.active, "CreateSpotlight should spawn")
  AnimTasks.update(vm)
  assert_true(not t.active, "CreateSpotlight is a one-shot register task")
  assert_true(vm._g3win and vm._g3win.win1 ~= nil, "WIN1 covers the text area")
  local r = AnimTasks.spawn("RemoveSpotlight", 2, {}, vm)
  AnimTasks.update(vm)
  assert_true(not r.active, "RemoveSpotlight is a one-shot register task")
  assert_eq(vm._g3win.win1, nil, "WIN1 removed")
end)

test("MorningSunLightBeam & GlareEyeDots - descending sunbeams and crimson eyes", function()
  local vm = make_vm("player")
  -- pokefirered/src/battle_anim_effects_3.c:2315
  local tSun = AnimTasks.spawn("MorningSunLightBeam", 2, {}, vm)
  assert_true(tSun ~= nil and tSun.active, "MorningSunLightBeam should spawn")
  for _ = 1, 157 do AnimTasks.update(vm) end
  assert_true(tSun.active, "MorningSunLightBeam still running at 157")
  AnimTasks.update(vm)
  assert_true(not tSun.active, "MorningSunLightBeam should destroy after 158 frames")

  -- pokefirered/src/battle_anim_effects_3.c:3904
  local tGlare = AnimTasks.spawn("GlareEyeDots", 2, {}, vm)
  assert_true(tGlare ~= nil and tGlare.active, "GlareEyeDots should spawn")
  for _ = 1, 90 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_true(not tGlare.active, "GlareEyeDots should destroy once all 26 dots expired")
end)

test("Generic combat FX tasks - ElectricCharging, DrillPeck, GrudgeFlames, BarrageBall", function()
  local vm = make_vm("player")
  local list = {
    "ElectricChargingParticles", "RotateAuroraRingColors"
  }
  for _, name in ipairs(list) do
    vm.args[0] = (name == "RotateAuroraRingColors") and 20 or 0
    local t = AnimTasks.spawn(name, 2, {}, vm)
    assert_true(t ~= nil and t.active, "Task " .. name .. " should spawn")
    for _ = 1, 25 do AnimTasks.update(vm) end
    assert_true(not t.active, "Task " .. name .. " should finish cleanly in duration")
  end
  -- pokefirered/src/battle_anim_effects_1.c:4896
  vm.args[7] = 0
  local tc = AnimTasks.spawn("ConversionAlphaBlend", 2, {}, vm)
  for _ = 1, 65 do AnimTasks.update(vm) end
  assert_true(tc.active, "ConversionAlphaBlend still fading at frame 65")
  assert_eq(vm.args[7], -1, "ConversionAlphaBlend signals the script via args[7] once the blend is full")
  AnimTasks.update(vm)
  assert_true(not tc.active, "ConversionAlphaBlend ends after 16 steps of 4 frames plus 2")
end)

-- pokefirered/src/battle_anim_flying.c:1025
test("G2 combat FX tasks - pret frame counts", function()
  local vm = make_vm("player")
  local tPeck = AnimTasks.spawn("DrillPeckHitSplats", 2, {}, vm)
  for f = 1, 31 do
    AnimTasks.update(vm)
    AnimSprites.update()
    assert_true(tPeck.active, "DrillPeckHitSplats active at frame " .. f)
  end
  AnimTasks.update(vm)
  assert_true(not tPeck.active, "DrillPeckHitSplats ends after 32 frames")
  local tSketch = AnimTasks.spawn("SketchDrawMon", 2, {}, vm)
  for _ = 1, 21 + 4 * 64 do AnimTasks.update(vm) end
  assert_true(not tSketch.active, "SketchDrawMon ends after 21 + 4 * height frames")
end)

-- pokefirered/src/battle_anim_ghost.c:1142
test("G3 combat FX tasks - pret frame counts", function()
  local vm = make_vm("player")
  local pretFrames = {
    GrudgeFlames = 89, BarrageBall = 59, StatusClearedEffect = 91,
    ImprisonOrbs = 80, SkillSwap = 97, Teleport = 30,
  }
  for name, frames in pairs(pretFrames) do
    AnimTasks.reset()
    AnimSprites.reset()
    local t = AnimTasks.spawn(name, 2, {}, vm)
    assert_true(t ~= nil and t.active, "Task " .. name .. " should spawn")
    for _ = 1, frames - 1 do
      AnimTasks.update(vm)
      AnimSprites.update()
    end
    assert_true(t.active, "Task " .. name .. " still running at frame " .. (frames - 1))
    AnimTasks.update(vm)
    AnimSprites.update()
    assert_true(not t.active, "Task " .. name .. " finishes at pret frame " .. frames)
  end
end)

-- ---------------------------------------------------------------------------
-- 4. Battler Movement & Substitute Doll Swap
-- ---------------------------------------------------------------------------

test("DoubleTeam - horizontal jitter, alpha pulse and clean restoration", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  p.ox = 0
  p.alpha = 1.0

  -- pokefirered/src/battle_anim_effects_1.c:5209
  AnimSprites.reset()
  local t = AnimTasks.spawn("DoubleTeam", 2, { 30 }, vm)
  assert_true(t ~= nil and t.active, "DoubleTeam should spawn")

  local cloneOx = 0
  for _ = 1, 130 do
    AnimTasks.update(vm)
    AnimSprites.update()
    for i = 1, AnimSprites.MAX do
      local s = AnimSprites._pool[i]
      if s.active then cloneOx = math.max(cloneOx, math.abs(s.ox or 0)) end
    end
  end
  assert_true(cloneOx > 0, "DoubleTeam clones sway around the battler")
  assert_true(t.active, "DoubleTeam still running while its two clones live")
  AnimTasks.update(vm)
  AnimSprites.update()
  assert_true(not t.active, "DoubleTeam ends when both clones expire (65 steps of 2 frames)")
  assert_eq(p.ox, 0, "DoubleTeam leaves the battler in place")
  assert_eq(p.alpha, 1.0, "DoubleTeam leaves the battler opaque")
end)

test("MonToSubstitute - squash and stretch scaling and clean restoration", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  p.sx = 1.0
  p.sy = 1.0

  -- pokefirered/src/battle_anim_effects_3.c:4681
  local t = AnimTasks.spawn("MonToSubstitute", 2, {}, vm)
  assert_true(t ~= nil and t.active, "MonToSubstitute should spawn")

  for _ = 1, 8 do AnimTasks.update(vm) end
  assert_true(p.sx < 1.0 and p.sy > 1.0, "matrix x grows by 0x60 and y shrinks by 0xD: narrower and taller")

  for _ = 9, 67 do AnimTasks.update(vm) end
  assert_true(t.active, "doll still dropping at frame 67")
  AnimTasks.update(vm)
  assert_true(not t.active, "MonToSubstitute finishes after the doll drop and bounce (68 frames)")
  assert_eq(p.sx, 1.0, "sx must restore to 1.0")
  assert_eq(p.sy, 1.0, "sy must restore to 1.0")
end)

test("AttackerPunchWithTrace - forward lunge and reset", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  p.ox = 0

  local t = AnimTasks.spawn("AttackerPunchWithTrace", 2, {}, vm)
  assert_true(t ~= nil and t.active, "AttackerPunchWithTrace should spawn")

  -- pokefirered/src/battle_anim_mons.c:2213
  for _ = 1, 17 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_true(t.active, "still waiting on the last trace at frame 17")
  AnimTasks.update(vm)
  AnimSprites.update()
  assert_true(not t.active, "ends once the lunge and its 8-frame traces finish")
  assert_eq(p.ox, 0, "ox must reset to 0")
end)

-- ---------------------------------------------------------------------------
-- 5. Metadata Evaluators (Immediate Query Tasks)
-- ---------------------------------------------------------------------------

test("QueryStateTask evaluators - immediate resolution without blocking VM", function()
  local vm = make_vm("player")
  local evaluators = {
    "GetRolloutCounter", "GetFuryCutterHitCount", "IsFuryCutterHitRight",
    "GetReturnPowerLevel", "GetFrustrationPowerLevel", "GetSeismicTossDamageLevel",
    "IsPowerOver99", "GetBattleTerrain", "GetWeather", "IsContest",
    "IsTargetPlayerSide", "GetIsDoomDesireHitTurn", "IsHealingMove"
  }
  for _, ev in ipairs(evaluators) do
    local t = AnimTasks.spawn(ev, 2, {}, vm)
    assert_true(t ~= nil, "Evaluator " .. ev .. " should spawn")
    AnimTasks.update(vm)
    assert_true(not t.active, "Evaluator " .. ev .. " should immediately resolve")
  end
end)

-- ---------------------------------------------------------------------------
-- 6. Complex Script Execution & Integration
-- ---------------------------------------------------------------------------

local f = io.open("data/generated/gba/pokemon/battle_anims/pack.lua", "r")
local packSrc = f and f:read("*a")
if f then f:close() end
if not packSrc then
  local okDs, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = okDs and Dataset.cache and Dataset.cache() or nil
  packSrc = cache and cache.read and cache:read("data/generated/gba/pokemon/battle_anims/pack.lua")
end
local chunk = loadstring and loadstring(packSrc) or load(packSrc)
local pack = chunk()

local function run_move_script(moveId, moveName)
  test(string.format("%s (Move #%d) - bytecode script execution", moveName, moveId), function()
    local script = pack.moves[moveId]
    assert_true(script ~= nil, "move script must exist for ID " .. tostring(moveId))
    local vm = AnimVm.new()
    vm:setPack(pack)
    vm:launch(script, { attackerSide = "player", isReversed = false })
    assert_true(vm:busy(), "VM should start busy")

    local maxTicks = 900
    local ticks = 0
    while vm:busy() and ticks < maxTicks do
      ticks = ticks + 1
      vm:update(1 / 60)
    end
    assert_true(not vm:busy(), string.format("move %d timed out after %d ticks", moveId, maxTicks))
  end)
end

run_move_script(164, "Substitute")
run_move_script(104, "Double Team")
run_move_script(327, "Sky Uppercut")
run_move_script(69, "Seismic Toss")
run_move_script(90, "Fissure")
run_move_script(213, "Attract")
run_move_script(262, "Memento")
run_move_script(272, "Role Play")
run_move_script(326, "Extrasensory")
run_move_script(266, "Follow Me")

print(string.format("\nPhase 4 Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
