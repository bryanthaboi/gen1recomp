package.path = "./?.lua;" .. package.path

local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
local Anim = require("src.core.game3.battle.anim")
local P = require("src.core.game3.battle.anim_port.g1_pret")
local C = require("src.core.game3.battle.anim_port.g1_callbacks")
local T = require("src.core.game3.battle.anim_port.g1_tasks")

local passed, failed = 0, 0
local function check(ok, msg)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local CB_SCOPE = {
  "ConfusionDuck", "HitSplatOnMonEdge", "HornHit", "HyperBeamOrb", "ItemSteal", "KnockOffItem", "MimicOrb",
  "PresentHealParticle", "SpinningSparkle", "WavyMusicNotes", "WhipHit", "AirCutterSlice", "BellyDrumHand",
  "ConstrictBinding", "Conversion", "Conversion2", "CrossImpact", "EndureEnergy", "FalseSwipePositionedSlice",
  "FalseSwipeSlice", "FlashingHitSplat", "FlyingMusicNotes", "FollowMeFinger", "FrenzyPlantRoot",
  "HitSplatHandleInvert", "HitSplatPersistent", "IngrainOrb", "IngrainRoot", "LeechSeed", "LockOnMoveTarget",
  "LockOnTarget", "MilkBottle", "Moon", "MoonlightSparkle", "MoveTwisterParticle", "PetalDanceBigFlower",
  "PetalDanceSmallFlower", "PowerAbsorptionOrb", "Present", "Protect", "RazorLeafParticle", "SharpenSphere",
  "SlowFlyingMusicNotes", "SparklingStars", "SporeParticle", "SuperFang", "TauntFinger", "ThoughtBubble",
  "TranslateLinearSingleSineWave", "TravelDiagonally", "TrickBag", "WeatherBallUp",
  "AbsorptionOrb", "CuttingSlice", "FlyingParticle", "GrantingStars", "HitSplatBasic", "HitSplatRandom",
  "MetronomeFinger", "MovePowderParticle", "NeedleArmSpike", "SlashSlice", "SleepLetterZ", "SolarBeamBigOrb",
  "SpriteOnMonPos", "ThrowProjectile", "TranslateAnimSpriteToTargetMonLocation", "WeatherBallDown",
}

local TASK_SCOPE = {
  "AllocBackupPalBuffer", "CopyPalFadedToUnfaded", "CopyPalUnfadedFromBackup", "CopyPalUnfadedToBackup",
  "FreeBackupPalBuffer", "MoonlightEndFade", "SetAttackerInvisibleWaitForSignal", "BlendColorCycleByTag",
  "BlendColorCycleExclude", "BlendPalInAndOutByTag", "Conversion2AlphaBlend", "ConversionAlphaBlend",
  "CycleMagicalLeafPal", "GetBattleTerrain", "GetFrustrationPowerLevel", "IsContest", "IsTargetSameSide",
  "LeafBlade", "MusicNotesClearRainbowBlend", "MusicNotesRainbowBlend", "RotateMonToSideAndRestore",
  "SetAnimAttackerAndTargetForEffectAtk", "SetAnimAttackerAndTargetForEffectTgt", "SetAnimTargetToBattlerTarget",
  "ShakeBattleTerrain", "SporeDoubleBattle",
  "BlendColorCycle", "FlashAnimTagWithColor", "InvertScreenColor", "BlendBattleAnimPal", "BlendBattleAnimPalExclude",
  "SetCamouflageBlend", "BlendParticle", "BlendMonInAndOut", "HardwarePaletteFade", "CreateSmallSolarBeamOrbs",
  "ShakeMon", "ShakeMon2", "ShakeMonInPlace", "ShakeAndSinkMon", "TranslateMonElliptical",
  "TranslateMonEllipticalRespectSide", "WindUpLunge", "SlideOffScreen", "SwayMon", "ScaleMonAndRestore",
  "RotateMonSpriteToSide", "ShakeTargetBasedOnMovePowerOrDmg",
  "HorizontalLunge", "VerticalDip", "SlideMonToOriginalPos", "SlideMonToOffset", "SlideMonToOffsetAndBack",
  "BowMon", "ShakeMonOrBattleTerrain", "SimplePaletteBlend", "ComplexPaletteBlend",
  "AlphaFadeIn", "ShrinkTargetCopy", "AttackerPunchWithTrace", "TraceMonBlended", "DoubleTeam", "Flash",
  "StartSlidingBg", "BlendNonAttackerPalettes", "SetAllNonAttackersInvisiblity", "SkullBashPosition",
}

for _, n in ipairs(CB_SCOPE) do
  check(C[n] ~= nil and AnimCallbacks[n] == C[n], "callback ported and hooked: " .. n)
end
for _, n in ipairs(TASK_SCOPE) do
  check(T[n] ~= nil and AnimTasks.REGISTRY[n] == T[n], "task ported and hooked: " .. n)
end

local function find_pack()
  local env = os.getenv("POKEPORT_ANIM_PACK")
  local home = os.getenv("HOME") or ""
  local cands = {
    env,
    home .. "/Library/Application Support/LOVE/firered-sep18fx/firered/data/generated/gba/pokemon/battle_anims/pack.lua",
    home .. "/.local/share/love/firered-sep18fx/firered/data/generated/gba/pokemon/battle_anims/pack.lua",
  }
  for ci = 1, 3 do
    local p = cands[ci]
    if p then
      local f = io.open(p, "r")
      if f then
        f:close()
        local ok, pack = pcall(dofile, p)
        if ok and type(pack) == "table" then return pack end
      end
    end
  end
  return nil
end

local pack = find_pack()
if not pack then
  print("[skip] no extracted battle_anims pack (set POKEPORT_ANIM_PACK)")
  print(string.format("g1 anim port: %d passed, %d failed", passed, failed))
  os.exit(failed == 0 and 0 or 1)
end

Anim.loadPack(pack)

local function refs_of(script, seen, out)
  if type(script) ~= "table" or seen[script] then return end
  seen[script] = true
  for _, op in ipairs(script) do
    if op.op == "createsprite" and op.callback then out.cb[op.callback] = true end
    if (op.op == "createvisualtask" or op.op == "createsoundtask") and op.task then out.task[op.task] = true end
    for _, k in ipairs({ "label", "label1", "label2", "target" }) do
      local l = op[k]
      if l and pack.labels[l] then refs_of(pack.labels[l], seen, out) end
    end
  end
end

local scripts = {}
local function add_group(group, names)
  for i, sc in pairs(pack[group] or {}) do
    local out = { cb = {}, task = {} }
    refs_of(sc, {}, out)
    scripts[#scripts + 1] = { name = group .. ":" .. tostring((names and names[i]) or i), script = sc, refs = out }
  end
end
add_group("moves")
add_group("general", pack.generalNames)
add_group("status", pack.statusNames)
add_group("special", pack.specialNames)

local errors = {}
local realPrint = print
local function capture_print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  local line = table.concat(parts, " ")
  if line:find("%[battle%.anim%]") or line:find("%[g1%]") then errors[#errors + 1] = line end
end

local function run_script(sc, attackerSide, turn, maxFrames)
  Anim.reset({ headless = false })
  Anim.loadPack(pack)
  P.Pal.reset()
  P.Fade.active = false
  local vm = Anim._vm
  vm.headless = false
  errors = {}
  print = capture_print
  local frames = 0
  local ok, err = pcall(function()
    vm:launch(sc, {
      isReversed = attackerSide == "enemy",
      attackerSide = attackerSide,
      targetSide = attackerSide == "player" and "enemy" or "player",
      attackerSpecies = 6,
      targetSpecies = 9,
    })
    vm._turn = turn
    while vm.active and frames < maxFrames do
      vm:update(1 / 60)
      frames = frames + 1
    end
  end)
  print = realPrint
  local g1Alive, others = false, {}
  for i = 1, AnimTasks.MAX do
    local t = AnimTasks._pool[i]
    if t.active then
      if t._g1 or t._g1FadeTicker then g1Alive = true else others[#others + 1] = tostring(t.name) end
    end
  end
  AnimSprites.forEachActive(function(sp)
    if sp._g1 then g1Alive = true else others[#others + 1] = tostring(sp.template) end
  end)
  return ok, err, vm, frames, g1Alive, others
end

local inScope = {}
for _, n in ipairs(CB_SCOPE) do inScope["cb:" .. n] = true end
for _, n in ipairs(TASK_SCOPE) do inScope["task:" .. n] = true end

local covered = {}
local ran = 0
for _, entry in ipairs(scripts) do
  local uses = false
  for n in pairs(entry.refs.cb) do if inScope["cb:" .. n] then uses = true; covered["cb:" .. n] = true end end
  for n in pairs(entry.refs.task) do if inScope["task:" .. n] then uses = true; covered["task:" .. n] = true end end
  if uses then
    for _, side in ipairs({ "player", "enemy" }) do
      for _, turn in ipairs({ 0, 1 }) do
        local ok, err, vm, frames, g1Alive, others = run_script(entry.script, side, turn, 1500)
        ran = ran + 1
        local label = entry.name .. " atk=" .. side .. " turn=" .. turn
        check(ok, label .. " runs: " .. tostring(err))
        if vm.active and not g1Alive then
          print("[info] " .. label .. " hangs on non-g1 work: " .. table.concat(others, ","))
        else
          check(not vm.active, label .. " terminates (frames=" .. frames .. ")")
          local g1err = nil
          for _, e in ipairs(errors) do
            if not e:find("waitforvisualfinish cap") then g1err = g1err or e end
          end
          check(g1err == nil, label .. " no runtime errors: " .. tostring(g1err))
          check(AnimSprites.activeCount() == 0, label .. " leaves no live sprites")
        end
      end
    end
  end
end

for k in pairs(inScope) do
  if not covered[k] then print("[info] not referenced by any pack script: " .. k) end
end

local function fresh_vm(attackerSide)
  Anim.reset({ headless = false })
  Anim.loadPack(pack)
  P.Pal.reset()
  P.Fade.active = false
  local vm = Anim._vm
  vm:launch({ { op = "delay", frames = 400 }, { op = "end" } }, {
    isReversed = attackerSide == "enemy",
    attackerSide = attackerSide,
    targetSide = attackerSide == "player" and "enemy" or "player",
    attackerSpecies = 6,
    targetSpecies = 9,
  })
  return vm
end

local function spawn(vm, template, cbName, args, animBattler, subpri)
  local s = AnimSprites.acquire({ template = template, tag = "IMPACT", w = 32, h = 32 })
  s._vm = vm
  s._args = args
  s._op = { op = "createsprite", template = template, callback = cbName, args = args, animBattler = animBattler or "attacker", subpriority = subpri or 2 }
  s.template = template
  s.callback = AnimCallbacks.get(cbName)
  s.callback(s)
  return s
end

local function lifetime(s, cap)
  local n = 1
  while s.active and n < (cap or 1000) do
    AnimSprites.update()
    n = n + 1
  end
  return n
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gHornHitSpriteTemplate", "HornHit", { 0, 0, 10 }, "target", 4)
  check(s.x == 176 - 40 and s.data[3] == 512, "HornHit player: x-40 start, 0x1400/d1 velocity")
  check(s.data[6] == 176, "HornHit remembers target X_2")
  check(lifetime(s) == 11, "HornHit destroyed on the arg2-th frame after creation")
end

do
  local vm = fresh_vm("enemy")
  local s = spawn(vm, "gHornHitSpriteTemplate", "HornHit", { 0, 0, 10 }, "target", 4)
  check(s._oamH and s._oamV, "HornHit enemy attacker flips H+V")
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gConfusionDuckSpriteTemplate", "ConfusionDuck", { 0, -15, 0, 3, 90 }, "attacker")
  check(s.ox == P.Cos(0, 30) and s.oy == P.Sin(0, 10), "ConfusionDuck starts on Cos(0,30)/Sin(0,10)")
  check(lifetime(s) == 90, "ConfusionDuck lives arg4 frames")
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gBasicHitSplatSpriteTemplate", "HitSplatBasic", { 0, 0, 1, 1 }, "target")
  check(s.x == 176, "HitSplatBasic on target X_2")
  check(s._aff and s._aff.xScale == 0xD8, "HitSplatBasic affine anim 1 starts at 0xD8 scale")
  check(lifetime(s) == 12, "HitSplatBasic: 0-dur frame, 8-frame hold, END, stored cb, destroy")
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gSleepLetterZSpriteTemplate", "SleepLetterZ", { 4, -20, 30 }, "attacker")
  check(s.x == 72 + 4, "SleepLetterZ player offset +x")
  check(lifetime(s) == 62, "SleepLetterZ destroyed when ++data[1] > 60")
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gMovePowderParticleSpriteTemplate", "MovePowderParticle", { 0, -20, 84, 70, 10, 5 }, "target")
  check(lifetime(s) == 86, "MovePowderParticle counts down arg2 then destroys")
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gTrickBagSpriteTemplate", "TrickBag", { -40, 80 }, "attacker")
  check(s.x == 120 and s.y == -40, "TrickBag starts at x=120, y=arg0")
  check(s.ox == P.Cos(80, 60) and s.oy == P.Sin(80, 20), "TrickBag circle offset")
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gLockOnTargetSpriteTemplate", "LockOnTarget", {}, "attacker", 40)
  check(s.x == 176 - 32, "LockOnTarget starts 32px up-left of target")
end

do
  local vm = fresh_vm("player")
  local t = AnimTasks.spawn("ShakeMon", 2, { 1, 3, 0, 6, 1 }, vm)
  t.func(t, vm)
  local p = Anim.present("enemy")
  check(p.ox == 3, "ShakeMon applies x offset immediately")
  local n = 1
  while t.active and n < 100 do AnimTasks.update(vm); n = n + 1 end
  check(p.ox == 0 and n == 12, "ShakeMon ends centred after numShakes*(delay+1) frames (" .. n .. ")")
end

do
  local vm = fresh_vm("player")
  P.beginNormalPaletteFade({ "enemy" }, 0, 0, 16, 0x7FFF)
  local n = 1
  while P.fadeActive() and n < 100 do
    P.updatePaletteFade()
    n = n + 1
  end
  local st = P.Pal.get("enemy")
  check(st.m == 0 and math.abs(st.r - 1) < 1e-6, "palette fade reaches full white")
  check(n == 23, "normal palette fade 0->16 takes 9 steps x2 frames + 5 finishing (" .. n .. ")")
end

print(string.format("g1 anim port: %d passed, %d failed (%d script runs)", passed, failed, ran))
os.exit(failed == 0 and 0 or 1)
