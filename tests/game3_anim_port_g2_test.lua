package.path = "./?.lua;" .. package.path

local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
local Anim = require("src.core.game3.battle.anim")
local P = require("src.core.game3.battle.anim_port.g2_pret")
local G2 = require("src.core.game3.battle.anim_port.g2_modules")

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
  "Angel", "AngerMark", "BlendThinRing", "BreathPuff", "BulletSeed", "CoinThrow", "Devil", "EyeSparkle",
  "FallingCoin", "FurySwipes", "GuardRing", "GuillotinePincer", "HealBellMusicNote", "HyperVoiceRing",
  "JaggedMusicNote", "KinesisZapEnergy", "MagentaHeart", "MovementWaves", "OrbitFast", "OrbitScatter",
  "ParticleBurst", "Pencil", "PerishSongMusicNote", "PerishSongMusicNote2", "PinkHeart", "RazorWindTornado",
  "RedHeartProjectile", "RedHeartRising", "SoftBoiledEgg", "SonicBoomProjectile", "SpitUpOrb",
  "SwordsDanceBlade", "UproarRing", "ViceGripPincer", "ArmThrustHit", "BasicFistOrFoot", "BrickBreakWall",
  "BrickBreakWallShard", "CrossChopHand", "DizzyPunchDuck", "FistOrFootRandomPos", "FocusPunchFist",
  "JumpKick", "RevengeScratch", "SlideHandOrFootToTarget", "SlidingKick", "SpinningKickOrPunch", "StompFoot",
  "SuperpowerFireball", "SuperpowerOrb", "SuperpowerRock", "BurnFlame", "EmberFlare", "EruptionFallingRock",
  "FireCross", "FirePlume", "FireRing", "FireSpiralInward", "FireSpiralOutward", "FireSpread", "LargeFlame",
  "Sunlight", "WillOWispFire", "WillOWispOrb", "AirWaveCrescent", "BounceBallLand", "BounceBallShrink",
  "DiveBall", "DiveWaterSplash", "EllipticalGust", "FallingFeather", "FlyBallAttack", "FlyBallUp",
  "GustToTarget", "SkyAttackBird", "SprayWaterDroplet", "WhirlwindLine", "DragonDanceOrb",
  "DragonFireToTarget", "DragonRageFirePlume", "OutrageFlame", "OverheatFlame",
}

local TASK_SCOPE = {
  "AirCutterProjectile", "AttackerStretchAndDisappear", "ExtremeSpeedImpact", "ExtremeSpeedMonReappear",
  "FakeOut", "FreeMusicNotesPals", "GetFuryCutterHitCount", "GrowAndGrayscale", "GrowAndShrink",
  "HeartsBackground", "IsFuryCutterHitRight", "LoadMusicNotesPals", "Minimize", "ScaryFace", "SketchDrawMon",
  "SpeedDust", "Splash", "StretchAttackerUp", "StretchTargetUp", "ThrashMoveMonHorizontal",
  "ThrashMoveMonVertical", "UproarDistortion", "Withdraw", "MoveSkyUppercutBg", "BlendBackground",
  "EruptionLaunchRocks", "MoveHeatWaveTargets", "ShakeTargetInPattern", "AnimateGustTornadoPalette",
  "DrillPeckHitSplats", "DragonDanceWaver",
}

for _, n in ipairs(CB_SCOPE) do
  check(G2.cb[n] ~= nil and AnimCallbacks[n] == G2.cb[n], "callback ported and hooked: " .. n)
end
for _, n in ipairs(TASK_SCOPE) do
  check(G2.tasks[n] ~= nil and AnimTasks.REGISTRY[n] == G2.tasks[n], "task ported and hooked: " .. n)
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
  print(string.format("g2 anim port: %d passed, %d failed", passed, failed))
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
  if line:find("%[battle%.anim%]") then errors[#errors + 1] = line end
end

local function run_script(sc, attackerSide, turn, maxFrames)
  Anim.reset({ headless = false })
  Anim.loadPack(pack)
  local vm = Anim._vm
  vm.headless = false
  errors = {}
  print = capture_print
  local ok, err = pcall(function()
    vm:launch(sc, {
      isReversed = attackerSide == "enemy",
      attackerSide = attackerSide,
      targetSide = attackerSide == "player" and "enemy" or "player",
      attackerSpecies = 6,
      targetSpecies = 9,
    })
    vm._turn = turn
    local frames = 0
    while vm.active and frames < maxFrames do
      vm:update(1 / 60)
      frames = frames + 1
    end
    vm._g2frames = frames
  end)
  print = realPrint
  local p1, p2 = Anim.present("player"), Anim.present("enemy")
  return ok, err, vm, vm._g2frames or 0, p1, p2
end

local entered = {}
local realEnter = P.enter
P.enter = function(s, cb)
  entered["cb:" .. tostring(s._cbName or (s._op and s._op.callback))] = true
  return realEnter(s, cb)
end
local realTaskEnter = P.taskEnter
P.taskEnter = function(t, vm)
  entered["task:" .. tostring(t.name):gsub("^AnimTask_", "")] = true
  return realTaskEnter(t, vm)
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
        local ok, err, vm, frames, p1, p2 = run_script(entry.script, side, turn, 1500)
        ran = ran + 1
        local label = entry.name .. " atk=" .. side .. " turn=" .. turn
        check(ok, label .. " runs: " .. tostring(err))
        check(not vm.active, label .. " terminates (frames=" .. frames .. ")")
        check(#errors == 0, label .. " no runtime errors: " .. tostring(errors[1]))
        check(AnimSprites.activeCount() == 0 and AnimTasks.activeCount() == 0, label .. " leaves no live sprites/tasks")
      end
    end
  end
end

for k in pairs(inScope) do
  if not covered[k] then
    print("[info] not referenced by any pack script: " .. k)
  else
    check(entered[k], "ported function actually ran from a pack script: " .. k)
  end
end
P.enter = realEnter
P.taskEnter = realTaskEnter

local function fresh_vm(attackerSide)
  Anim.reset({ headless = false })
  Anim.loadPack(pack)
  local vm = Anim._vm
  vm:launch({ { op = "delay", frames = 200 }, { op = "end" } }, {
    isReversed = attackerSide == "enemy",
    attackerSide = attackerSide,
    targetSide = attackerSide == "player" and "enemy" or "player",
    attackerSpecies = 6,
    targetSpecies = 9,
  })
  P.setVm(vm)
  return vm
end

local function spawn(vm, template, cbName, args, animBattler)
  local s = AnimSprites.acquire({ template = template, tag = "IMPACT", w = 32, h = 32 })
  s._vm = vm
  s._args = args
  s._op = { op = "createsprite", template = template, callback = cbName, args = args, animBattler = animBattler or "attacker", subpriority = 2 }
  s.template = template
  s.callback = AnimCallbacks.get(cbName)
  s.callback(s)
  return s
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gFlyBallUpSpriteTemplate", "FlyBallUp", { 0, 0, 13, 336 })
  check(s.x == 72 and s.y == P.coord("player", 3), "FlyBallUp starts on attacker X_2/Y_PIC_OFFSET")
  check(Anim.present("player").visible == false, "FlyBallUp hides attacker")
  local frames = 1
  while s.active and s.callback == P.runner and frames < 400 do
    AnimSprites.update()
    frames = frames + 1
  end
  check(not P.alive(s), "FlyBallUp leaves the screen and is destroyed (" .. frames .. " frames)")
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gSkyAttackBirdSpriteTemplate", "SkyAttackBird", {})
  check(s.x == 72 and s.data[6] == P.div((176 - 72) * 16, 12), "SkyAttackBird velocity from attacker to target (pret /12 of <<4)")
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gEllipticalGustSpriteTemplate", "EllipticalGust", { 0, -16 })
  check(s.y == 40 - 16 + 20, "EllipticalGust y = target Y + arg1 + 20")
  local n = 1
  while P.alive(s) do AnimSprites.update(); n = n + 1 end
  check(n == 71, "EllipticalGust lives exactly 71 frames (" .. n .. ")")
end

do
  local vm = fresh_vm("enemy")
  local s = spawn(vm, "gOverheatFlameSpriteTemplate", "OverheatFlame", { 1, 0, 30, 25, -20 })
  check(s.data[1] == P.Cos(0, 30) and s.data[2] == P.Sin(0, 18), "OverheatFlame velocity from Cos/Sin with 3/5 y amplitude")
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gDragonDanceOrbSpriteTemplate", "DragonDanceOrb", { 0 })
  local w = P.coordAttr("player", P.ATTR_WIDTH)
  local h = P.coordAttr("player", P.ATTR_HEIGHT)
  check(s.data[7] == P.div(math.max(w, h), 2), "DragonDanceOrb radius is half the larger pic dimension")
  check(s.x2 == P.Cos(0, s.data[7]) and s.y2 == 0, "DragonDanceOrb starts at angle arg0")
end

do
  local vm = fresh_vm("player")
  local s = spawn(vm, "gFireBlastRingSpriteTemplate", "FireRing", { 0, 0, 0 })
  local n = 1
  while P.alive(s) and n < 200 do AnimSprites.update(); n = n + 1 end
  check(n == 1 + 0x12 + 26 + 30, "FireRing: 18 orbit frames, 25-step translate, 31-frame target orbit (" .. n .. ")")
end

do
  local vm = fresh_vm("player")
  local t = AnimTasks.spawn("Withdraw", 2, {}, vm)
  local n = 0
  while t.active and n < 200 do AnimTasks.update(vm); n = n + 1 end
  check(n == 1 + 22 + 30 + 22, "Withdraw rolls 22 frames, holds 30, rolls back 22 (" .. n .. ")")
  check(Anim.present("player").rotation == 0, "Withdraw restores rotation")
end

do
  local vm = fresh_vm("player")
  local t = AnimTasks.spawn("ShakeTargetInPattern", 2, { 10, 3, 0, 0 }, vm)
  local seen = {}
  local n = 0
  while t.active and n < 50 do
    AnimTasks.update(vm)
    seen[#seen + 1] = Anim.present("enemy").ox
    n = n + 1
  end
  check(n == 10 and seen[1] == -3 and seen[3] == 3 and Anim.present("enemy").ox == 0, "ShakeTargetInPattern follows sShakeDirsPattern0")
end

do
  local vm = fresh_vm("player")
  local t = AnimTasks.spawn("AirCutterProjectile", 2, { 32, -24, 1536, 2, 128 }, vm)
  local created = 0
  local n = 0
  while t.active and n < 400 do
    AnimTasks.update(vm)
    AnimSprites.update()
    n = n + 1
    if t.data and t.data[1] and t.data[1] > created then created = t.data[1] end
  end
  check(created == 3 and not t.active, "AirCutterProjectile throws three crescents then ends")
end

print(string.format("g2 anim port: %d passed, %d failed (%d script runs)", passed, failed, ran))
os.exit(failed == 0 and 0 or 1)
