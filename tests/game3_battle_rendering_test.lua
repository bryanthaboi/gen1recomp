local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
local AnimTasks = require("src.core.game3.battle.anim_tasks")

print("=== 1. Testing Slot Z Calculation ===")
assert(AnimSprites.slotZ("enemy", "behind") == 90, "Enemy behind Z should be 90")
assert(AnimSprites.slotZ("enemy", "mon") == 100, "Enemy mon Z should be 100")
assert(AnimSprites.slotZ("enemy", "front") == 110, "Enemy front Z should be 110")
assert(AnimSprites.slotZ("player", "behind") == 190, "Player behind Z should be 190")
assert(AnimSprites.slotZ("player", "mon") == 200, "Player mon Z should be 200")
assert(AnimSprites.slotZ("player", "front") == 210, "Player front Z should be 210")
print("[ok] Slot Z calculation verified for singles and doubles!")

print("=== 2. Testing Affine Orbit & Vortex Callbacks ===")
AnimSprites.reset()
do
  local Anim = require("src.core.game3.battle.anim")
  local vm = Anim.vm() or Anim.reset({ headless = true }) or Anim.vm()
  -- pokefirered/data/battle_anim_scripts.s
  local fireSpin = { 0, 28, 528, 30, 13, 50, 1 }
  for i, v in ipairs(fireSpin) do vm.args[i - 1] = v end
end
local s1 = AnimSprites.acquire({
  x = 100, y = 100, template = "gFireSpinSpriteTemplate",
  callback = AnimCallbacks.ParticleInVortex,
  data = { [1] = 0 }
})
assert(s1, "Failed to acquire sprite for vortex")
assert(s1.scaleX == 1 and s1.scaleY == 1, "Initial scale should be 1")

for _ = 1, 5 do
  AnimSprites.update()
end
-- pokefirered/src/battle_anim_rock.c:376
assert(s1.rotation == 0, "Vortex particle does not rotate")
assert(s1.ox ~= 0 and s1.oy < 0, "Vortex sprite translation should advance")
print(string.format("[ok] ParticleInVortex stepped: rot=%.3f, ox=%d, oy=%d", s1.rotation, s1.ox, s1.oy))

print("=== 3. Testing DragonDanceOrb Orbit ===")
-- pokefirered/src/battle_anim_dragon.c:264
AnimSprites.reset()
local s2 = AnimSprites.acquire({
  x = 50, y = 50,
  callback = AnimCallbacks.DragonDanceOrb
})
local ox0 = nil
for _ = 1, 6 do
  AnimSprites.update()
  ox0 = ox0 or s2.ox
end
assert(s2.ox ~= ox0 or s2.oy ~= 0, "DragonDanceOrb should orbit the attacker")
print(string.format("[ok] DragonDanceOrb stepped: ox=%d, oy=%d", s2.ox, s2.oy))

print("=== 4. Testing Semi-transparent Energy Shield (DefensiveWall) ===")
AnimSprites.reset()
local s3 = AnimSprites.acquire({
  x = 80, y = 80,
  callback = AnimCallbacks.DefensiveWall,
  z = AnimSprites.slotZ("player", "front")
})
AnimSprites.update()
-- pokefirered/src/battle_anim_psychic.c:419
assert(s3.blendMode == "alpha", "DefensiveWall is an ST_OAM_OBJ_BLEND sprite weighted by setalpha")
assert(s3.active == true, "DefensiveWall stays up until its own timer ends")
print("[ok] DefensiveWall blend mode verified!")

print("=== 5. Testing Host Lifecycle Sweep ===")
assert(s3.active == true, "s3 should be active")
s3.hostId = "player"
AnimSprites.clearHost("player")
assert(s3.active == false, "s3 should be cleared after host player faints/switches")
print("[ok] Host lifecycle sweep verified!")

print("=== 6. Testing Sorted Draw List Range Filtering ===")
AnimSprites.reset()
local spBehind = AnimSprites.acquire({ z = 50 })
local spMid = AnimSprites.acquire({ z = 150 })
local spFront = AnimSprites.acquire({ z = 250 })

local listBehind = AnimSprites.sortedDrawList({}, 0, 99)
assert(#listBehind == 1 and listBehind[1] == spBehind, "Draw list behind count mismatch")

local listMid = AnimSprites.sortedDrawList({}, 101, 199)
assert(#listMid == 1 and listMid[1] == spMid, "Draw list mid count mismatch")

local listFront = AnimSprites.sortedDrawList({}, 201, 999)
assert(#listFront == 1 and listFront[1] == spFront, "Draw list front count mismatch")
print("[ok] Multi-layer Z-range filtering verified!")

print("\n=== ALL RENDERING & KINEMATICS VERIFICATIONS PASSED! ===")
