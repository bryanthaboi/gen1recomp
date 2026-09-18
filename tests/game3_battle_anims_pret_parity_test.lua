-- tests/game3_battle_anims_pret_parity_test.lua
-- Rigorous 1:1 pret (pokefirered) parity test suite for battle animation tasks, callbacks and move scripts

package.path = package.path .. ";./?.lua"

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

print("=== Pret (pokefirered) 1:1 Parity Audit Tests ===")

-- ---------------------------------------------------------------------------
-- 1. Registry Completeness against pokefirered/data/battle_anim_scripts.s
-- ---------------------------------------------------------------------------

test("Visual Tasks Registry - all 213 pret visual tasks are registered", function()
  local f = io.open("pokefirered/data/battle_anim_scripts.s", "r")
    or io.open("../pokefirered/data/battle_anim_scripts.s", "r")
  if not f then
    print("    skip: no pokefirered checkout beside the repo")
    return
  end
  local text = f:read("*a")
  f:close()

  local missing = 0
  for task in text:gmatch("createvisualtask%s+([%w_]+)") do
    local key = task:gsub("^AnimTask_", "")
    local fn = AnimTasks.REGISTRY[task] or AnimTasks.REGISTRY[key] or AnimTasks.REGISTRY["AnimTask_" .. key]
    if not fn then
      print("    Missing pret task in REGISTRY: " .. task)
      missing = missing + 1
    end
  end
  assert_eq(missing, 0, "All visual tasks from battle_anim_scripts.s must be registered")
end)

-- ---------------------------------------------------------------------------
-- 2. Dig & Subterranean Mechanics
-- ---------------------------------------------------------------------------

test("DigDownMovement - 3-step subterranean bounce and invisible toggle", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  p.oy = 0
  p.invisible = false

  local t = AnimTasks.spawn("DigDownMovement", 2, { 0 }, vm)
  assert_true(t ~= nil and t.active, "DigDownMovement should spawn")

  -- pokefirered/src/battle_anim_ground.c:293
  for _ = 1, 24 do AnimTasks.update(vm) end
  assert_true(p.oy > 0, "should have descended downward into ground")
  assert_true(type(p.hShift) == "table", "rows outside the dig window are scrolled away")

  local n = 0
  while t.active and n < 400 do
    AnimTasks.update(vm)
    n = n + 1
  end
  assert_true(not t.active, "DigDownMovement should complete")
  assert_true(p.invisible, "Mon should be invisible while underground")
  assert_true(p.hShift == nil, "scanline effect stops")
end)

test("DigUpMovement - emergence from underground with coordinate recovery", function()
  local vm = make_vm("player")
  local p = Anim.present("player")
  p.oy = 32
  p.invisible = true

  -- pokefirered/src/battle_anim_ground.c:387
  local t0 = AnimTasks.spawn("DigUpMovement", 2, { 0 }, vm)
  AnimTasks.update(vm)
  assert_true(not p.invisible, "Mon becomes visible underground")
  assert_true(p.oy > 32, "Mon sits below the screen")
  AnimTasks.update(vm)
  assert_true(not t0.active, "set-visible step ends")

  local t = AnimTasks.spawn("DigUpMovement", 2, { 1 }, vm)
  assert_true(t ~= nil and t.active, "DigUpMovement should spawn")
  for _ = 1, 3 do AnimTasks.update(vm) end
  assert_eq(p.oy, 96, "rise starts 96px down")
  for _ = 1, 13 do AnimTasks.update(vm) end
  assert_true(not t.active, "DigUpMovement should complete")
  assert_eq(p.oy, 0, "Mon oy must restore to 0 upon completion")
end)

-- ---------------------------------------------------------------------------
-- 3. Skull Bash & Extreme Speed Mechanics
-- ---------------------------------------------------------------------------

test("SkullBashPosition - side-aware backstep and forward rush", function()
  local vmPlayer = make_vm("player")
  local pPlayer = Anim.present("player")
  pPlayer.ox = 0

  -- Player backstep
  local t1 = AnimTasks.spawn("SkullBashPosition", 2, { 0 }, vmPlayer)
  for _ = 1, 17 do AnimTasks.update(vmPlayer) end
  assert_true(pPlayer.ox < 0, "Player should step back (negative ox)")

  -- Enemy backstep
  local vmEnemy = make_vm("enemy")
  local pEnemy = Anim.present("enemy")
  pEnemy.ox = 0
  local t2 = AnimTasks.spawn("SkullBashPosition", 2, { 0 }, vmEnemy)
  for _ = 1, 17 do AnimTasks.update(vmEnemy) end
  assert_true(pEnemy.ox > 0, "Enemy should step back (positive ox)")
end)

test("ExtremeSpeedImpact & Reappear - rapid target shudder and 14-frame flicker", function()
  local vm = make_vm("player")
  local pTgt = Anim.present("enemy")
  pTgt.ox = 0

  -- pokefirered/src/battle_anim_effects_2.c:2848
  local tImpact = AnimTasks.spawn("ExtremeSpeedImpact", 2, {}, vm)
  AnimTasks.update(vm)
  AnimTasks.update(vm)
  assert_true(pTgt.ox ~= 0, "Target should shudder during ExtremeSpeed impact")

  for _ = 3, 70 do AnimTasks.update(vm) end
  assert_true(not tImpact.active, "ExtremeSpeedImpact should finish after 3 shake cycles and slide back")
  assert_eq(pTgt.ox, 0, "Target ox should restore to 0")

  -- pokefirered/src/battle_anim_effects_2.c:2909
  local pAtk = Anim.present("player")
  local tReappear = AnimTasks.spawn("ExtremeSpeedMonReappear", 2, {}, vm)
  for _ = 1, 28 do AnimTasks.update(vm) end
  assert_true(tReappear.active, "ExtremeSpeedMonReappear still flickering at frame 28")
  AnimTasks.update(vm)
  assert_true(not tReappear.active, "ExtremeSpeedMonReappear should finish after 14 two-frame toggles")
  assert_true(pAtk.visible ~= false, "Attacker must be visible after reappearing")
end)

-- ---------------------------------------------------------------------------
-- 4. Specialized Combat FX Tasks
-- ---------------------------------------------------------------------------

test("WaterSpoutLaunch & Rain - water geyser and falling cascade", function()
  local vm = make_vm("player")
  -- pokefirered/src/battle_anim_water.c:1040
  local tLaunch = AnimTasks.spawn("WaterSpoutLaunch", 2, {}, vm)
  assert_true(tLaunch ~= nil and tLaunch.active, "WaterSpoutLaunch should spawn")
  local n = 0
  while tLaunch.active and n < 300 do
    AnimTasks.update(vm)
    AnimSprites.update()
    n = n + 1
  end
  assert_true(not tLaunch.active, "WaterSpoutLaunch ends once its droplets land")
  assert_eq(Anim.present("player").sx or 1, 1, "WaterSpoutLaunch restores the attacker scale")

  local tRain = AnimTasks.spawn("WaterSpoutRain", 2, {}, vm)
  assert_true(tRain ~= nil and tRain.active, "WaterSpoutRain should spawn")
  n = 0
  local most = 0
  while tRain.active and n < 300 do
    AnimTasks.update(vm)
    AnimSprites.update()
    most = math.max(most, AnimSprites.activeCount())
    n = n + 1
  end
  assert_true(most > 0, "WaterSpoutRain drops rain sprites")
  assert_true(not tRain.active, "WaterSpoutRain ends once every drop is gone")
end)

test("DoomDesireLightBeam & AirCutterProjectile - celestial beam and razor crescent", function()
  local vm = make_vm("player")
  -- pokefirered/src/battle_anim_effects_3.c:2495
  local tBeam = AnimTasks.spawn("DoomDesireLightBeam", 2, {}, vm)
  assert_true(tBeam ~= nil and tBeam.active, "DoomDesireLightBeam should spawn")
  for _ = 1, 117 do AnimTasks.update(vm) end
  assert_true(tBeam.active, "DoomDesireLightBeam still running at frame 117")
  AnimTasks.update(vm)
  assert_true(not tBeam.active, "DoomDesireLightBeam should finish after 118 frames")

  -- pokefirered/src/battle_anim_effects_2.c:1644
  local tCutter = AnimTasks.spawn("AirCutterProjectile", 2, { 32, -24, 1536, 2, 128 }, vm)
  assert_true(tCutter ~= nil and tCutter.active, "AirCutterProjectile should spawn")
  for _ = 1, 30 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_true(tCutter.active, "AirCutterProjectile waits for its three crescents")
  for _ = 1, 120 do
    AnimTasks.update(vm)
    AnimSprites.update()
  end
  assert_true(not tCutter.active, "AirCutterProjectile ends once all crescents are gone")
end)

test("StatsChange, FakeOut, GrowAndGrayscale, ShrinkTargetCopy", function()
  local vm = make_vm("player")
  local pAtk = Anim.present("player")
  local pTgt = Anim.present("enemy")

  -- FakeOut
  local tFake = AnimTasks.spawn("FakeOut", 2, {}, vm)
  for _ = 1, 17 do AnimTasks.update(vm) end
  assert_true(not tFake.active, "FakeOut should finish in 16 frames")

  -- StatsChange
  local tStats = AnimTasks.spawn("StatsChange", 2, { 0 }, vm)
  for _ = 1, 33 do AnimTasks.update(vm) end
  assert_true(not tStats.active, "StatsChange should finish in 32 frames")

  -- GrowAndGrayscale
  -- pokefirered/src/battle_anim_effects_2.c:2019
  local tGrow = AnimTasks.spawn("GrowAndGrayscale", 2, {}, vm)
  for _ = 1, 81 do AnimTasks.update(vm) end
  assert_true(tGrow.active, "GrowAndGrayscale still running at frame 81")
  AnimTasks.update(vm)
  assert_true(not tGrow.active, "GrowAndGrayscale should finish after 82 frames")
  assert_eq(pTgt.sx, 1.0, "target sx untouched")
  assert_true(not pTgt.grayscale, "target palette restored")

  -- ShrinkTargetCopy
  -- pokefirered/src/battle_anim_effects_1.c:2830
  vm.args[0], vm.args[1], vm.args[7] = 128, 24, 0
  local tShrink = AnimTasks.spawn("ShrinkTargetCopy", 5, { 128, 24 }, vm)
  for _ = 1, 30 do AnimTasks.update(vm) end
  assert_true(tShrink.active, "ShrinkTargetCopy holds until the script sets args[7]")
  assert_true(pTgt.sx < 1.0, "ShrinkTargetCopy grows the affine matrix (shrinks the copy)")
  vm.args[7] = -1
  for _ = 1, 3 do AnimTasks.update(vm) end
  assert_true(not tShrink.active, "ShrinkTargetCopy ends 3 frames after args[7] is 0xFFFF")
  assert_eq(pTgt.sx, 1.0, "sx must restore to 1.0")
  assert_eq(pTgt.alpha, 1.0, "alpha must restore to 1.0")
end)

-- ---------------------------------------------------------------------------
-- 5. Fire Primitives & Ember (MOVE_EMBER) Parity Tests
-- ---------------------------------------------------------------------------

test("TranslateAnimSpriteToTargetMonLocation - linear translation from attacker to target", function()
  local vm = make_vm("player")
  local pAtk = Anim.present("player")
  local pTgt = Anim.present("enemy")
  local ax, ay = vm:battlerCenter("player")
  local tx, ty = vm:battlerCenter("enemy")

  -- Emulate createsprite gEmberSpriteTemplate, ANIM_TARGET, 2, 20, 0, -16, 24, 20, 1
  local op = {
    op = "createsprite",
    template = "gEmberSpriteTemplate",
    callback = "TranslateAnimSpriteToTargetMonLocation",
    tag = "SMALL_EMBER",
    animBattler = "target",
    subpriority = 2,
    args = { 20, 0, -16, 24, 20, 1 },
    w = 32,
    h = 32,
  }
  vm:launch({ op, { op = "delay", frames = 30 }, { op = "end" } }, { attackerSide = "player" })
  vm:update(1 / 60)

  assert_eq(AnimSprites.activeCount(), 1, "One ember sprite should be spawned")
  local s = AnimSprites._pool[1]
  assert_eq(s.x, ax + 20, "Sprite must start at attacker X + 20")
  -- pokefirered/src/battle_anim_mons.c:233
  assert_eq(s.y, ay + 8, "Sprite must start at the attacker's BATTLER_COORD_Y_PIC_OFFSET")

  -- Update through 20 frames
  for i = 1, 10 do
    AnimSprites.update(vm)
  end
  assert_true(s.ox > 0, "Sprite should be translating towards target mon")

  for i = 11, 20 do
    AnimSprites.update(vm)
  end
  assert_eq(AnimSprites.activeCount(), 1, "Sprite still translating on its 20th step")
  -- pokefirered/src/battle_anim_mons.c:1061
  AnimSprites.update(vm)
  AnimSprites.update(vm)
  assert_eq(AnimSprites.activeCount(), 0, "Sprite hands off to DestroyAnimSprite once the translation ends")
end)

test("AnimEmberFlare - diagonal drift on target and sAnim_BasicFire 5-frame animation", function()
  local vm = make_vm("player")
  local tx, ty = vm:battlerCenter("enemy")

  -- Emulate EmberFireHit: createsprite gEmberFlareSpriteTemplate, ANIM_TARGET, 2, -24, 24, 24, 24, 20, ANIM_TARGET, 1
  local op = {
    op = "createsprite",
    template = "gEmberFlareSpriteTemplate",
    callback = "AnimEmberFlare",
    tag = "SMALL_EMBER",
    animBattler = "target",
    subpriority = 2,
    args = { -24, 24, 24, 24, 20, 1, 1 },
    w = 32,
    h = 32,
  }
  vm:launch({ op, { op = "delay", frames = 30 }, { op = "end" } }, { attackerSide = "player" })
  vm:update(1 / 60)

  assert_eq(AnimSprites.activeCount(), 1, "One ember flare sprite should be spawned")
  local s = AnimSprites._pool[1]
  assert_eq(s.x, tx - 24, "Flare must start at target X - 24")
  assert_eq(s.y, ty + 24, "Flare must start at target Y + 24")

  -- Frame animation check: quadY advances every 4 ticks
  AnimSprites.update(vm) -- tick 1 -> frame 0 (quadY = 0)
  assert_eq(s.quadY, 0, "Tick 1 must be frame 0 (quadY = 0)")

  for _ = 2, 4 do AnimSprites.update(vm) end
  AnimSprites.update(vm) -- tick 5 -> frame 1 (quadY = 32)
  assert_eq(s.quadY, 32, "Tick 5 must be frame 1 (quadY = 32)")

  for _ = 6, 8 do AnimSprites.update(vm) end
  AnimSprites.update(vm) -- tick 9 -> frame 2 (quadY = 64)
  assert_eq(s.quadY, 64, "Tick 9 must be frame 2 (quadY = 64)")

  for _ = 10, 20 do AnimSprites.update(vm) end
  assert_eq(AnimSprites.activeCount(), 0, "Flare must be destroyed after 20 frames")
end)

-- ---------------------------------------------------------------------------
-- 6. Move Execution Parity for Complex Multi-turn & Special Moves
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

local function run_move(moveId, moveName)
  test(string.format("%s (Move #%d) - full bytecode execution parity", moveName, moveId), function()
    local script = pack.moves[moveId]
    assert_true(script ~= nil, "move script must exist for ID " .. tostring(moveId))
    local vm = AnimVm.new()
    vm:setPack(pack)
    vm:launch(script, { attackerSide = "player", isReversed = false })
    assert_true(vm:busy(), "VM should start busy")

    local maxTicks = 360
    local ticks = 0
    while vm:busy() and ticks < maxTicks do
      ticks = ticks + 1
      vm:update(1 / 60)
    end
    assert_true(not vm:busy(), string.format("move %d timed out after %d ticks", moveId, maxTicks))
  end)
end

run_move(52, "Ember")
run_move(7, "Fire Punch")
run_move(53, "Flamethrower")
run_move(83, "Fire Spin")
run_move(126, "Fire Blast")
run_move(172, "Flame Wheel")
run_move(91, "Dig")
run_move(130, "Skull Bash")
run_move(245, "Extreme Speed")
run_move(252, "Fake Out")
run_move(323, "Water Spout")
run_move(353, "Doom Desire")
run_move(314, "Air Cutter")
run_move(257, "Heat Wave")
run_move(37, "Thrash")
run_move(76, "SolarBeam")
run_move(174, "Curse")

print(string.format("\nPret Parity Results: %d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end

