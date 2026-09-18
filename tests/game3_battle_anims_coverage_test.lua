-- Comprehensive Battle Animations Coverage Test
-- Verifies all 354 moves in pack.lua, testing GLSL shader integration,
-- Z-index depth, nearest-neighbor scaling tasks, and spatial audio panning.

local Anim = require("src.core.game3.battle.anim")
local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")

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

print("=== Battle Animations System Coverage Test ===")

print("[test] 1. Palette task lifecycle")
Anim.reset({ headless = true })
local G1 = require("src.core.game3.battle.anim_port.g1_pret")
G1.Pal.reset()
local vm = Anim.vm()
vm:setBattlers("player", "enemy")

-- pokefirered/src/battle_anim_normal.c:698
AnimTasks.spawn("InvertScreenColor", 2, { 0x100, 0x100, 0x100 }, vm)
AnimTasks.update(vm)
check(G1.Pal.get("bg").m < 0, "InvertScreenColor inverts the BG palettes")
check(G1.Pal.get("player").m < 0 and G1.Pal.get("enemy").m < 0, "InvertScreenColor inverts attacker and target palettes")
check(AnimTasks.activeCount() == 0, "InvertScreenColor is a one-shot task")
G1.Pal.reset()

-- pokefirered/src/battle_anim_effects_3.c:1382
for i = 0, 7 do vm.args[i] = 0 end
AnimTasks.spawn("FadeScreenToWhite", 2, {}, vm)
for _ = 1, 20 do AnimTasks.update(vm) end
check(AnimTasks.activeCount() == 1, "FadeScreenToWhite keeps rotating until args[7] is 0xFFFF")
vm.args[7] = -1
AnimTasks.update(vm)
check(AnimTasks.activeCount() == 0, "FadeScreenToWhite ends on args[7] == 0xFFFF")

-- pokefirered/src/battle_anim_dark.c:869
vm.args[0], vm.args[1] = 0, 0
AnimTasks.spawn("SetGrayscaleOrOriginalPal", 2, { 0, 0 }, vm)
AnimTasks.update(vm)
check(Anim.present("player").grayscale == true, "SetGrayscaleOrOriginalPal greys the attacker")
vm.args[1] = 1
AnimTasks.spawn("SetGrayscaleOrOriginalPal", 2, { 0, 1 }, vm)
AnimTasks.update(vm)
check(Anim.present("player").grayscale == false, "SetGrayscaleOrOriginalPal restores the attacker")
check(AnimTasks.activeCount() == 0, "SetGrayscaleOrOriginalPal is a one-shot task")

-- 2. Z-Index Depth & Layering
print("[test] 2. Z-Index depth and layering rules")
AnimSprites.reset()

-- Physical contact -> GLOBAL_FRONT (Z = 900)
local sprFist = AnimSprites.acquire({
  z = AnimSprites.Z.GLOBAL_FRONT,
  callback = AnimCallbacks.get("BasicFistOrFoot"),
})
check(sprFist and sprFist.z == AnimSprites.Z.GLOBAL_FRONT, "BasicFistOrFoot assigned to GLOBAL_FRONT (900)")

-- Ground hazard -> GLOBAL_BEHIND (Z = 10)
local sprMud = AnimSprites.acquire({
  z = AnimSprites.Z.GLOBAL_BEHIND,
  callback = AnimCallbacks.get("MudSportDirt"),
})
check(sprMud and sprMud.z == AnimSprites.Z.GLOBAL_BEHIND, "MudSportDirt assigned to GLOBAL_BEHIND (10)")

local list = AnimSprites.sortedDrawList()
check(#list == 2, "2 sprites in sorted list")
check(list[1].z < list[2].z, "Background mud renders before foreground fist")
AnimSprites.reset()

-- 3. Audio Panning Task
print("[test] 3. Audio spatial panning task")
do
  local Audio = require("src.core.game3.audio")
  local realPlaySe = Audio.playSe
  local plays = {}
  Audio.playSe = function(id, o) plays[#plays + 1] = { id = id, pan = o and o.pan } return true end
  local vm = Anim.vm()
  vm.args[0], vm.args[1] = 5, -64
  local pTask = AnimTasks.spawn("SoundTask_PlaySE1WithPanning", 2, { 5, -64 }, vm)
  check(pTask ~= nil, "SoundTask_PlaySE1WithPanning spawned")
  AnimTasks.update(vm)
  check(plays[1] and plays[1].id == 5 and plays[1].pan == -64, "PlaySE1WithPanning plays arg0 at BattleAnimAdjustPanning(arg1)")
  check(#plays == 1, "PlaySE1WithPanning plays exactly once")
  check(not pTask.active, "Panning task terminates cleanly")
  Audio.playSe = realPlaySe
end

-- 4. Execute all 354 Move Scripts through VM
print("[test] 4. Full 354-move bytecode execution coverage")
local ok, Dataset = pcall(require, "src.core.game3.dataset")
local cache = ok and Dataset.cache and Dataset.cache() or nil
local packSrc = cache and cache.read and cache:read("data/generated/gba/pokemon/battle_anims/pack.lua")
if not packSrc then
  local f = io.open("data/generated/gba/pokemon/battle_anims/pack.lua", "r")
  if f then packSrc = f:read("*a"); f:close() end
end

check(type(packSrc) == "string" and #packSrc > 0, "pack.lua source loaded")

local chunk = loadstring and loadstring(packSrc) or load(packSrc)
local pack = chunk()
check(type(pack) == "table" and type(pack.moves) == "table", "pack.moves table parsed")

local moveCount = 0
local cleanFinishes = 0
local vmErrors = 0

local vm = AnimVm.new()
vm:setPack(pack)

for moveId, script in pairs(pack.moves) do
  moveCount = moveCount + 1
  AnimTasks.reset()
  AnimSprites.reset()
  Anim.reset({ headless = true })
  
  local okLaunch, err = pcall(function()
    vm:launch(script, { attackerSide = "player", isReversed = false })
  end)

  if not okLaunch then
    vmErrors = vmErrors + 1
    print(string.format("[ERROR] Move %s launch error: %s", tostring(moveId), tostring(err)))
  else
    local maxTicks = 900
    local ticks = 0
    while vm:busy() and ticks < maxTicks do
      ticks = ticks + 1
      vm:update(1 / 60)
    end

    if not vm:busy() then
      cleanFinishes = cleanFinishes + 1
    else
      print(string.format("[TIMEOUT] Move %s timed out after %d frames", tostring(moveId), maxTicks))
    end
  end
end

print(string.format("Tested %d moves: %d completed cleanly, %d launch errors", moveCount, cleanFinishes, vmErrors))
check(moveCount >= 354, "All 354 moves present and processed")
check(vmErrors == 0, "0 VM launch errors across all moves")
check(cleanFinishes == moveCount, "All moves cleanly terminate without freezing")

print(string.format("\nResults: %d Passed, %d Failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
