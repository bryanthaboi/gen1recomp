package.path = "./?.lua;./?/init.lua;" .. package.path

local CALLBACKS = {
  "BlackSmoke", "WhiteHalo", "TealAlert", "MeanLookEye", "Spikes", "Leer", "LetterZ", "Fang",
  "Spotlight", "ClappingHand", "ClappingHand2", "RapidSpin", "TriAttackTriangle", "BatonPassPokeball",
  "WishStar", "SwallowBlueOrb", "GreenStar", "WeakFrustrationAngerMark", "SweetScentPetal",
  "PainSplitProjectile", "FlatterConfetti", "FlatterSpotlight", "ReversalOrb", "YawnCloud",
  "SmokeBallEscapeCloud", "RoarNoiseLine", "AssistPawprint", "SmellingSaltsHand",
  "SmellingSaltExclamation", "HelpingHandClap", "ForesightMagnifyingGlass", "MeteorMashStar", "BlockX",
  "KnockOffStrike", "Recycle",
  "Bite", "TearDrop", "ClawSlash",
  "ConfuseRayBallBounce", "ConfuseRayBallSpiral", "ShadowBall", "Lick", "CurseNail", "GhostStatusSprite",
  "DefensiveWall", "WallSparkle", "BentSpoon", "QuestionMark", "RedX", "PsychoBoost",
}

local TASKS = {
  "SmokescreenImpact", "IsTargetPlayerSide", "IsHealingMove",
  "CreateSpotlight", "RemoveSpotlight", "RapinSpinMonElevation", "TormentAttacker", "DefenseCurlDeformMon",
  "StockpileDeformMon", "SpitUpDeformMon", "SwallowDeformMon", "TransformMon", "IsMonInvisible",
  "CastformGfxChange", "MorningSunLightBeam", "DoomDesireLightBeam", "StrongFrustrationGrowAndShrink",
  "RockMonBackAndForth", "FlailMovement", "PainSplitMovement", "RolePlaySilhouette", "AcidArmor",
  "DeepInhale", "SlideMonForFocusBand", "SquishAndSweatDroplets", "FacadeColorBlend",
  "GlareEyeDots", "BarrageBall", "SmellingSaltsSquish",
  "HelpingHandAttackerMovement", "MonToSubstitute", "OdorSleuthMovement", "GetReturnPowerLevel",
  "SnatchOpposingMonMove", "SnatchPartnerMove", "TeeterDanceMovement", "GetWeather", "SlackOffSquish",
  "AttackerFadeToInvisible", "AttackerFadeFromInvisible", "InitAttackerFadeFromInvisible",
  "MoveAttackerMementoShadow", "MoveTargetMementoShadow", "InitMementoShadow", "MementoHandleBg",
  "SetGrayscaleOrOriginalPal", "GetIsDoomDesireHitTurn",
  "NightShadeClone", "NightmareClone", "SpiteTargetShadow", "DestinyBondWhiteShadow",
  "CurseStretchingBlackBg", "GrudgeFlames",
  "MeditateStretchAttacker", "Teleport", "ImprisonOrbs", "SkillSwap", "ExtrasensoryDistortion",
  "TransparentCloneGrowAndShrink",
}

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function find_pack()
  local home = os.getenv("HOME") or "."
  local cands = {
    os.getenv("G3_ANIM_PACK") or "",
    home .. "/Library/Application Support/LOVE/firered-sep18fx/firered/data/generated/gba/pokemon/battle_anims/pack.lua",
    home .. "/.local/share/love/firered-sep18fx/firered/data/generated/gba/pokemon/battle_anims/pack.lua",
    home .. "/.local/share/love/pokemon-love2d/firered/data/generated/gba/pokemon/battle_anims/pack.lua",
    "data/generated/gba/pokemon/battle_anims/pack.lua",
  }
  for _, p in ipairs(cands) do
    if p then
      local f = io.open(p, "r")
      if f then
        f:close()
        local ok, pack = pcall(dofile, p)
        if ok and type(pack) == "table" and pack.moves then return pack end
      end
    end
  end
  return nil
end

local P = require("src.core.game3.battle.anim_port.g3_pret")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local Anim = require("src.core.game3.battle.anim")
local G3C = require("src.core.game3.battle.anim_port.g3_callbacks")
local G3T = require("src.core.game3.battle.anim_port.g3_tasks")

-- pokefirered/src/trig.c:514
check(P.Sin(64, 256) == 256 and P.Sin(192, 10) == -10 and P.Cos(0, 15) == 15, "Sin/Cos gSineTable")
check(P.Sin(5, 10) == 1 and P.Cos(5, 15) == 14, "Sin/Cos truncation")
check(P.Sin2(30) == 2048 and P.Cos2(180) == -4096, "Sin2/Cos2 degree table")
check(P.s16(40000) == -25536 and P.u16(-1) == 65535 and P.div(-7, 2) == -3, "C integer semantics")

for _, n in ipairs(CALLBACKS) do
  check(type(G3C[n]) == "function", "g3 callback registered: " .. n)
  check(AnimCallbacks.get(n) == G3C[n], "AnimCallbacks resolves to g3 port: " .. n)
end
for _, n in ipairs(TASKS) do
  check(type(G3T[n]) == "function", "g3 task registered: " .. n)
  check(AnimTasks.REGISTRY[n] == G3T[n] and AnimTasks.REGISTRY["AnimTask_" .. n] == G3T[n], "task registry resolves to g3 port: " .. n)
end

local pack = find_pack()
if not pack then
  print("[skip] no FireRed battle_anims pack found (set G3_ANIM_PACK); content checks skipped")
  print(string.format("game3_anim_port_g3: %d passed, %d failed", passed, failed))
  os.exit(failed == 0 and 0 or 1)
end

Anim.reset({ headless = false })
Anim.loadPack(pack)

local wantCb, wantTask = {}, {}
for _, n in ipairs(CALLBACKS) do wantCb[n] = true end
for _, n in ipairs(TASKS) do wantTask[n] = true end

local function scan(ops, seen, hits)
  for _, op in ipairs(ops or {}) do
    if op.op == "createsprite" and op.callback then
      local n = tostring(op.callback):gsub("^Anim", "")
      if wantCb[n] then hits[n] = true end
    elseif op.op == "createvisualtask" and op.task then
      local n = tostring(op.task):gsub("^AnimTask_", "")
      if wantTask[n] then hits[n] = true end
    end
    for _, k in ipairs({ "label", "label1", "label2" }) do
      local l = op[k]
      if l and pack.labels[l] and not seen[l] then
        seen[l] = true
        scan(pack.labels[l], seen, hits)
      end
    end
  end
end

local scripts = {}
local function add(kind, id, ops)
  local hits = {}
  scan(ops, {}, hits)
  if next(hits) then scripts[#scripts + 1] = { name = kind .. ":" .. tostring(id), ops = ops, hits = hits } end
end
for id = 0, 354 do if pack.moves[id] then add("move", id, pack.moves[id]) end end
for _, kind in ipairs({ "general", "special", "status" }) do
  for id, ops in pairs(pack[kind] or {}) do add(kind, id, ops) end
end

local covered = {}
local errors = {}
local oldPrint = print
local function capture(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  local line = table.concat(parts, "\t")
  if line:find("%[battle%.anim%]") then errors[#errors + 1] = line end
end

local function run(ops, atk)
  local vm = Anim._vm
  vm.headless = false
  Anim._present.player = nil
  Anim._present.enemy = nil
  Anim._bgBlend = nil
  vm:launch(ops, {
    attackerSide = atk, targetSide = (atk == "player") and "enemy" or "player",
    isReversed = atk == "enemy", attackerSpecies = 25, targetSpecies = 4,
  })
  local frames, timeout = 0, false
  while vm.active and frames < 3000 do
    frames = frames + 1
    vm:update(1 / 60)
    if (vm._visualWaitFrames or 0) >= 590 or (vm._spriteWaitFrames or 0) >= 590 then timeout = true end
  end
  return frames, timeout, vm.active
end

print = capture
for _, sc in ipairs(scripts) do
  for _, atk in ipairs({ "player", "enemy" }) do
    local before = #errors
    local frames, timeout, active = run(sc.ops, atk)
    local names = {}
    for n in pairs(sc.hits) do names[#names + 1] = n; covered[n] = true end
    local tag = sc.name .. " (" .. atk .. ") [" .. table.concat(names, ",") .. "]"
    check(not timeout, "no wait timeout: " .. tag)
    check(not active and frames < 3000, "script terminates: " .. tag)
    check(#errors == before, "no runtime errors: " .. tag .. " " .. tostring(errors[before + 1]))
  end
end
print = oldPrint

for _, n in ipairs(CALLBACKS) do
  if not covered[n] then print("[info] callback not referenced by any pack script: " .. n) end
end
for _, n in ipairs(TASKS) do
  if not covered[n] then print("[info] task not referenced by any pack script: " .. n) end
end

local function spawn_sprite(cbName, tmpl, args, atk)
  local vm = Anim._vm
  vm:reset()
  vm._attackerSide = atk or "player"
  vm._targetSide = (atk == "enemy") and "player" or "enemy"
  vm._attackerSpecies, vm._targetSpecies = 25, 4
  vm.isReversed = atk == "enemy"
  local s = AnimSprites.acquire({ x = 0, y = 0, template = tmpl, callback = AnimCallbacks.get(cbName), w = 32, h = 32 })
  s._args = args
  s._vm = vm
  s._op = { animBattler = "target", subpriority = 2 }
  return s, vm
end

local function lifetime(s)
  local n = 0
  while s.active and n < 2000 do
    n = n + 1
    AnimSprites.update()
  end
  return n
end

-- pokefirered/src/battle_anim_ghost.c:308
do
  local s = spawn_sprite("ConfuseRayBallSpiral", "gConfuseRayBallSpiralSpriteTemplate", { 0, -16 })
  AnimSprites.update()
  check(s.ox == 0 and s.oy == 8, "ConfuseRayBallSpiral first step x2=Sin(0,32) y2=Cos(0,8)")
  check(lifetime(s) == 60, "ConfuseRayBallSpiral lives 61 steps")
end

-- pokefirered/src/battle_anim_ghost.c:396
do
  local s, vm = spawn_sprite("ShadowBall", "gShadowBallSpriteTemplate", { 16, 16, 8 })
  AnimSprites.update()
  local ax, ay = P.coordAtk(vm, P.COORD_X_2), P.coordAtk(vm, P.COORD_Y_PIC)
  check(s.x == ax and s.y == ay, "ShadowBall starts at attacker")
  for _ = 1, 16 do AnimSprites.update() end
  local tx = P.coordTgt(vm, P.COORD_X_2)
  check(math.abs(s.x - math.floor((ax + tx) / 2)) <= 1, "ShadowBall reaches midpoint after arg0 frames")
  for _ = 1, 30 do AnimSprites.update() end
  check(not s.active, "ShadowBall destroyed after 16+16+8 frames")
end

-- pokefirered/src/battle_anim_ghost.c:458
do
  local s = spawn_sprite("Lick", "gLickSpriteTemplate", { 0, 0 })
  check(lifetime(s) == 52, "Lick: 5x2 anim frames, end, then 5x3 + 5x5 flicker")
end

-- pokefirered/src/battle_anim_mons.c:105
do
  local vm = Anim._vm
  vm._attackerSide, vm._targetSide = "player", "enemy"
  vm._attackerSpecies, vm._targetSpecies = 25, 4
  local pc = require("src.core.game3.battle.pic_coords")
  local y = 80 + (pc.back[25] or 0) + 8
  if y > 104 then y = 104 end
  check(P.coord(vm, "player", P.COORD_Y_PIC) == y, "player Y_PIC_OFFSET = 80 + back y_offset + 8 (cap 104)")
  check(P.coord(vm, "enemy", P.COORD_Y_PIC) == 40 + (pc.front[4] or 0) - (pc.elev[4] or 0), "enemy Y_PIC_OFFSET = 40 + front y_offset - elevation")
end

print(string.format("game3_anim_port_g3: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
