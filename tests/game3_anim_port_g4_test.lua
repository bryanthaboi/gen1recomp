
package.path = "./?.lua;./?/init.lua;" .. package.path

local passed, failed = 0, 0
local function check(cond, name)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("[FAIL] " .. tostring(name))
  end
end

local function find_pack()
  local cands = {
    os.getenv("G4_ANIM_PACK") or "",
    (os.getenv("HOME") or "") .. "/Library/Application Support/LOVE/firered-sep18fx/firered/data/generated/gba/pokemon/battle_anims/pack.lua",
    "data/generated/gba/pokemon/battle_anims/pack.lua",
  }
  for _, p in ipairs(cands) do
    if p and p ~= "" then
      local f = io.open(p, "rb")
      if f then
        f:close()
        local ok, pack = pcall(dofile, p)
        if ok and type(pack) == "table" then return pack end
      end
    end
  end
  return nil
end

local errs = {}
local rawPrint = print
print = function(...)
  local s = table.concat({ ... }, " ")
  if s:find("%[battle%.anim%]") then errs[#errs + 1] = s end
  rawPrint(...)
end

local Anim = require("src.core.game3.battle.anim")
local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
local P = require("src.core.game3.battle.anim_port.g4_pret")

rawPrint("=== G4 anim port ===")

local function fresh_vm(pack)
  Anim.reset({ headless = false })
  if pack then Anim.loadPack(pack) end
  Anim.present("player").visible = true
  Anim.present("enemy").visible = true
  return Anim.vm()
end

local function run_to_end(vm, cap)
  local frames = 0
  while vm.active and frames < (cap or 3000) do
    Anim.update(1 / 60)
    frames = frames + 1
  end
  return frames
end

rawPrint("[test] 1. pret trig / panning")
check(P.Sin(64, 256) == 256, "Sin(64,256) == 256")
check(P.Cos(0, 40) == 40, "Cos(0,40) == 40")
check(P.Sin(192, 10) == -10, "Sin(192,10) == -10")
check(P.Sin(-2, 100) == P.Sin(254, 100), "Sin masks to u8")
do
  local vm = fresh_vm(nil)
  vm:setBattlers("enemy", "player")
  check(vm:adjustPanning(-64) == 63, "enemy attacker pans SOUND_PAN_ATTACKER to 63")
  check(vm:adjustPanning(63) == -63, "enemy attacker negates SOUND_PAN_TARGET to -63")
  vm:setBattlers("player", "enemy")
  check(vm:adjustPanning(-64) == -64, "player attacker keeps pan")
  vm:setBattlers("player", "player")
  check(vm:adjustPanning(63) == -64, "self-target maps TARGET to ATTACKER")
end

rawPrint("[test] 2. VM opcode semantics")
do
  local vm = fresh_vm(nil)
  vm:launch({ { op = "delay", frames = 5 }, { op = "end" } }, { attackerSide = "player", targetSide = "enemy" })
  local n = 0
  while vm.active and n < 100 do vm:update(); n = n + 1 end
  check(n == 8, "delay 5 resumes on the 8th callback frame like WaitAnimFrameCount (got " .. n .. ")")

  vm:launch({ { op = "delay", frames = 0 }, { op = "end" } }, {})
  n = 0
  while vm.active and n < 100 do vm:update(); n = n + 1 end
  check(n == 3, "delay 0 is -1 and resumes 2 frames later (got " .. n .. ")")

  vm:launch({ { op = "setarg", argId = 7, value = -1 }, { op = "jumpargeq", argId = 7, value = -1, label = "X" }, { op = "delay", frames = 50 }, { op = "end" } }, {})
  vm._pack = { labels = { X = { { op = "end" } } } }
  n = 0
  while vm.active and n < 100 do vm:update(); n = n + 1 end
  check(n == 1, "setarg + jumpargeq take the branch (got " .. n .. ")")

  local tick = 0
  AnimTasks.REGISTRY._G4TestVisual = function(t)
    tick = tick + 1
    if tick >= 10 then AnimTasks.destroy(t) end
  end
  vm:launch({ { op = "createvisualtask", task = "_G4TestVisual", priority = 2, args = { 3, 4 } }, { op = "waitforvisualfinish" }, { op = "end" } }, {})
  vm:update()
  check(tick == 2, "createvisualtask runs the task immediately, then again in RunTasks the same frame")
  check(vm.args[0] == 3 and vm.args[1] == 4, "createvisualtask writes gBattleAnimArgs")
  n = 1
  while vm.active and n < 100 do vm:update(); n = n + 1 end
  check(tick == 10 and n == 10, "waitforvisualfinish waits for the visual task (frames " .. n .. ")")
end

local pack = find_pack()
if not pack then
  rawPrint("[skip] no battle anim pack found (set G4_ANIM_PACK); pack-driven checks skipped")
  print = rawPrint
  rawPrint(string.format("G4 anim port: %d passed, %d failed", passed, failed))
  os.exit(failed == 0 and 0 or 1)
end

rawPrint("[test] 3. createsoundtask spawns SoundTask_*")
do
  local vm = fresh_vm(pack)
  vm:launchTable("moves", 126, { attackerSide = "player", targetSide = "enemy", attackerSpecies = 6, targetSpecies = 9 })
  local seen = false
  for _ = 1, 30 do
    Anim.update(1 / 60)
    for i = 1, AnimTasks.MAX do
      local t = AnimTasks._pool[i]
      if t.active and t._g4kind == "sound" and tostring(t.name):find("SoundTask_FireBlast") then seen = true end
    end
    if seen then break end
  end
  check(seen, "FIRE_BLAST createsoundtask spawns SoundTask_FireBlast as a sound task")
  check(vm:soundCount() >= 1, "sound task counted by gAnimSoundTaskCount")
  run_to_end(vm)
  check(not vm.active, "FIRE_BLAST runs to end")
end

rawPrint("[test] 4. every general/special/status script runs to end")
local function run_table(vm, kind, idx, opts)
  errs = {}
  opts = opts or {}
  local o = { attackerSide = opts.a or "player", targetSide = opts.t or "enemy", attackerSpecies = 6, targetSpecies = 9,
    ctx = opts.ctx or { ballThrowCaseId = 0, lastUsedItem = 4 }, animArg = opts.animArg }
  vm:launchTable(kind, idx, o)
  local frames = run_to_end(vm, 2000)
  local capped = false
  for _, e in ipairs(errs) do if e:find("cap") then capped = true end end
  return frames, (not vm.active) and not capped, errs
end
do
  local vm = fresh_vm(pack)
  for _, kind in ipairs({ "general", "special", "status" }) do
    for i = 0, 40 do
      if pack[kind][i] then
        for _, sides in ipairs({ { "player", "enemy" }, { "enemy", "player" } }) do
          Anim.present("player").visible = true
          Anim.present("enemy").visible = true
          local frames, ok, e = run_table(vm, kind, i, { a = sides[1], t = sides[2] })
          local name = (pack[kind .. "Names"] and pack[kind .. "Names"][i]) or i
          check(ok and #e == 0, string.format("%s[%d] %s (%s) ends cleanly in %d frames %s", kind, i, tostring(name), sides[1], frames, table.concat(e, " | ")))
        end
      end
    end
  end
end

rawPrint("[test] 5. every move using a G4-scope function runs to end")
local SCOPE = {}
for _, n in ipairs({
  "SpriteCB_SafariBaitOrRock_Init", "MegahornHorn", "LeechLifeNeedle", "TranslateWebThread", "StringWrap", "SpiderWeb",
  "TranslateStinger", "MissileArc", "TailGlowOrb", "Lightning", "SparkElectricity", "ZapCannonSpark", "ThunderboltOrb",
  "SparkElectricityFlashing", "Electricity", "ThunderWave", "GrowingChargeOrb", "ElectricPuff", "VoltTackleOrbSlide",
  "GrowingShockWaveOrb", "BonemerangProjectile", "BoneHitProjectile", "DirtScatter", "MudSportDirt", "DirtPlumeParticle",
  "DigDirtMound", "SludgeProjectile", "AcidPoisonBubble", "SludgeBombHitParticle", "AcidPoisonDroplet", "BubbleEffect",
  "IcePunchSwirlingParticle", "IceBeamParticle", "IceEffectParticle", "SwirlingSnowball", "MoveParticleBeyondTarget",
  "WaveFromCenterOfTarget", "InitSwirlingFogAnim", "ThrowMistBall", "InitPoisonGasCloudAnim", "InitIceBallAnim",
  "InitIceBallParticle", "FallingRock", "RockFragment", "ParticleInVortex", "FlyingSandCrescent", "RaiseSprite",
  "RockTomb", "RockBlastRock", "RockScatter", "WaterBubbleProjectile", "AuroraBeamRings", "ToTargetInSinWave",
  "HydroCannonCharge", "HydroCannonBeam", "WaterGunDroplet", "SmallBubblePair", "SmallDriftingBubbles",
  "WaterPulseBubble", "WaterPulseRing",
  "ElectricBolt", "ElectricChargingParticles", "ShockWaveLightning", "VoltTackleAttackerReappear", "VoltTackleBolt",
  "ShockWaveProgressingBolt", "HorizontalShake", "IsPowerOver99", "PositionFissureBgOnBattler", "GetRolloutCounter",
  "HazeScrollingFog", "MistBallFog", "Hail", "Rollout", "GetSeismicTossDamageLevel", "MoveSeismicTossBg",
  "SeismicTossBgAccelerateDownAtEnd", "CreateRaindrops", "RotateAuroraRingColors", "StartSinAnimTimer",
  "WaterSport", "WaterSpoutLaunch", "WaterSpoutRain",
  "SoundTask_FireBlast", "SoundTask_LoopSEAdjustPanning", "SoundTask_PlayCryWithEcho", "SoundTask_PlaySE2WithPanning",
  "SoundTask_PlaySE1WithPanning", "SoundTask_AdjustPanningVar", "SoundTask_PlayCryHighPitch", "SoundTask_PlayDoubleCry",
  "SoundTask_WaitForCry",
}) do SCOPE[n] = true end

local function uses_scope(ops, seen)
  seen = seen or {}
  if seen[ops] then return false end
  seen[ops] = true
  for _, op in ipairs(ops) do
    local n = op.callback or op.task
    if n and SCOPE[n] then return true end
    for _, l in ipairs({ op.label, op.label1, op.label2 }) do
      if l and pack.labels[l] and uses_scope(pack.labels[l], seen) then return true end
    end
  end
  return false
end

do
  local vm = fresh_vm(pack)
  local count = 0
  for id = 1, 354 do
    local s = pack.moves[id]
    if s and uses_scope(s) then
      count = count + 1
      for _, sides in ipairs({ { "player", "enemy" }, { "enemy", "player" } }) do
        Anim.present("player").visible = true
        Anim.present("enemy").visible = true
        local frames, ok, e = run_table(vm, "moves", id, { a = sides[1], t = sides[2], ctx = { movePower = 120, moveDamage = 50, rolloutTimerStartValue = 5, rolloutTimer = 3 } })
        check(ok and #e == 0, string.format("move %d (%s) ends cleanly in %d frames %s", id, sides[1], frames, table.concat(e, " | ")))
      end
    end
  end
  check(count >= 60, "scope covers the expected move scripts (" .. count .. ")")
end

rawPrint("[test] 6. pret-derived values")
do
  local vm = fresh_vm(pack)
  vm:launch({ { op = "createsprite", template = "gThunderWaveSpriteTemplate", callback = "ThunderWave", tag = "SPARK_H", w = 32, h = 16, animBattler = "target", subpriority = 2, args = { -16, -16 } }, { op = "waitforvisualfinish" }, { op = "end" } },
    { attackerSide = "player", targetSide = "enemy", attackerSpecies = 6, targetSpecies = 9 })
  vm:update()
  local counted = 0
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active and s._g4counted then counted = counted + 1 end
  end
  check(counted == 2, "ThunderWave creates a second counted sprite (gAnimVisualTaskCount++)")
  local frames = run_to_end(vm)
  check(frames >= 51 and frames <= 55, "ThunderWave bands live 51 frames (script ended at " .. frames .. ")")

  vm = fresh_vm(pack)
  vm:launch({ { op = "createsprite", template = "gLinearStingerSpriteTemplate", callback = "TranslateStinger", tag = "NEEDLE", w = 16, h = 16, animBattler = "attacker", subpriority = 2, args = { 20, 0, 0, 0, 20 } }, { op = "end" } },
    { attackerSide = "player", targetSide = "enemy", attackerSpecies = 6, targetSpecies = 9 })
  vm:update()
  local st
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active and s._cbName == "TranslateStinger" then st = s end
  end
  check(st and st.x == 72 + 20, "TranslateStinger starts at attacker X_2 + arg0")
  check(st and st._mat and st._mat.rot > 0xC000 - 0x1000 and st._mat.rot < 0xFFFF, "TranslateStinger rotation = ArcTan2Neg + 0xC000")
  run_to_end(vm)

  vm = fresh_vm(pack)
  vm:launch({ { op = "createvisualtask", task = "SwitchOutShrinkMon", priority = 2, args = {} }, { op = "waitforvisualfinish" }, { op = "end" } },
    { attackerSide = "player", targetSide = "enemy" })
  local p = Anim.present("player")
  local n = 0
  while vm.active and n < 200 do
    Anim.update(1 / 60)
    n = n + 1
  end
  check(p.visible == false and p.sx == 1, "SwitchOutShrinkMon hides the mon and resets rot/scale")
  check(n >= 12 and n <= 16, "SwitchOutShrinkMon: 0x100 -> 0x2D0 step 0x30 (" .. n .. " frames)")

  vm = fresh_vm(pack)
  vm:launch({ { op = "createvisualtask", task = "GetTrappedMoveAnimId", priority = 2, args = {} }, { op = "end" } }, { animArg = 83 })
  vm:update()
  check(vm.args[0] == 1, "GetTrappedMoveAnimId: Fire Spin -> TRAP_ANIM_FIRE_SPIN")
  run_to_end(vm)

  vm = fresh_vm(pack)
  vm:launch({ { op = "createvisualtask", task = "IsBallBlockedByTrainerOrDodged", priority = 2, args = {} }, { op = "end" } }, { ctx = { ballThrowCaseId = 5 } })
  vm:update()
  check(vm.args[7] == -1, "IsBallBlockedByTrainerOrDodged: trainer block -> -1")
  run_to_end(vm)

  vm = fresh_vm(pack)
  vm:launch({ { op = "createvisualtask", task = "SafariOrGhost_DecideAnimSides", priority = 2, args = { 1 } }, { op = "delay", frames = 3 }, { op = "end" } }, { attackerSide = "player", targetSide = "enemy" })
  vm:update()
  check(vm:attackerSide() == "enemy" and vm:targetSide() == "player", "SafariOrGhost_DecideAnimSides(1) swaps attacker/target")
  run_to_end(vm)

  vm = fresh_vm(pack)
  vm:launch({ { op = "createvisualtask", task = "GetSeismicTossDamageLevel", priority = 2, args = {} }, { op = "end" } }, { ctx = { moveDamage = 40 } })
  vm:update()
  check(vm.args[7] == 1, "GetSeismicTossDamageLevel: 33..65 -> 1")
  run_to_end(vm)

  vm = fresh_vm(pack)
  local played = {}
  local Audio = require("src.core.game3.audio")
  local realPlay = Audio.playSe
  Audio.playSe = function(id, o) played[#played + 1] = { id = id, pan = o and o.pan } return true end
  vm:launch({ { op = "loopsewithpan", se = 120, pan = -64, wait = 4, times = 3 }, { op = "end" } }, { attackerSide = "enemy", targetSide = "player" })
  vm:update()
  check(#played == 1 and played[1].pan == 63, "loopsewithpan plays immediately with adjusted pan")
  run_to_end(vm)
  check(#played == 3, "loopsewithpan plays 'times' sounds (" .. #played .. ")")
  played = {}
  vm:launch({ { op = "createsoundtask", task = "SoundTask_LoopSEAdjustPanning", args = { 130, -64, 63, 16, 4, 0, 5 } }, { op = "end" } }, { attackerSide = "player", targetSide = "enemy" })
  local frames = run_to_end(vm)
  check(#played == 4, "LoopSEAdjustPanning plays arg4 times (" .. #played .. ")")
  check(played[1] and played[1].pan == -64 and played[2] and played[2].pan > played[1].pan, "LoopSEAdjustPanning pans attacker -> target")
  Audio.playSe = realPlay
end

print = rawPrint
rawPrint(string.format("G4 anim port: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
