-- Test suite for Issue #2356: FireRed Viridian City Gym Door script & scripted jump movements

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Movement = require("src.core.game3.scripting.movement")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Flags = require("src.core.game3.scripting.flags")

print("=== Issue #2356: Viridian Gym Door & Jump Movement Tests ===")

-- -----------------------------------------------------------------------------
-- 1. Movement opcode decoding for jump commands
-- -----------------------------------------------------------------------------
print("[test] 1. Movement.decodeAction for jump opcodes")

local a14 = Movement.decodeAction(0x14)
assert(a14.kind == "jump" and a14.dir == "down" and a14.distance == 2, "0x14 decodes to jump 2 down")

local a15 = Movement.decodeAction(0x15)
assert(a15.kind == "jump" and a15.dir == "up" and a15.distance == 2, "0x15 decodes to jump 2 up")

local a16 = Movement.decodeAction(0x16)
assert(a16.kind == "jump" and a16.dir == "left" and a16.distance == 2, "0x16 decodes to jump 2 left")

local a17 = Movement.decodeAction(0x17)
assert(a17.kind == "jump" and a17.dir == "right" and a17.distance == 2, "0x17 decodes to jump 2 right")

local a4e = Movement.decodeAction(0x4E)
assert(a4e.kind == "jump" and a4e.dir == "down" and a4e.distance == 1, "0x4E decodes to jump 1 down")

local a5a = Movement.decodeAction(0x5A)
assert(a5a.kind == "face_original", "0x5A decodes to face_original")

local actions = Movement.actionsFromBytes({ 0x14, 0xFE })
assert(#actions == 1 and actions[1].kind == "jump" and actions[1].distance == 2, "ViridianCity_Movement_JumpDownLedge decodes to 1 jump action")
print("[ok] Movement decoding for jump opcodes passed")

-- -----------------------------------------------------------------------------
-- 2. Objects.isPlayer checks
-- -----------------------------------------------------------------------------
print("[test] 2. Objects.isPlayer recognizes player IDs")
assert(Objects.isPlayer(Objects.PLAYER_LOCAL_ID), "Objects.PLAYER_LOCAL_ID is player")
assert(Objects.isPlayer(0xFF), "0xFF (LOCALID_PLAYER) is player")
assert(Objects.isPlayer(0x800F), "0x800F (SPECIAL_VAR_PLAYER) is player")
assert(not Objects.isPlayer(1), "NPC id 1 is not player")
print("[ok] Objects.isPlayer passed")

-- -----------------------------------------------------------------------------
-- 3. Player.scriptJump execution
-- -----------------------------------------------------------------------------
print("[test] 3. Player.scriptJump updates cell position by distance")
Player.reset(36, 11, "up")
assert(Player.cellX == 36 and Player.cellY == 11, "Player starting at (36, 11)")

local ok = Player.scriptJump("down", 2)
assert(ok == true, "Player.scriptJump returned true")
assert(Player.jumping == true, "Player is in jumping state")
assert(Player.targetX == 36 and Player.targetY == 13, "Target cell is (36, 13)")
assert(Player.moving == true, "Player is moving")

-- Step through jump animation frames
local safety = 0
while Player.moving and safety < 100 do
  safety = safety + 1
  Player.update(nil)
end

assert(Player.cellX == 36 and Player.cellY == 13, "Player completed jump landing at (36, 13)")
assert(Player.jumping == false, "Player jumping state cleared")
print("[ok] Player.scriptJump passed")

-- -----------------------------------------------------------------------------
-- 4. Objects.applyMovement with 0xFF (player) and 0x14 (jump_2_down)
-- -----------------------------------------------------------------------------
print("[test] 4. Objects.applyMovement on player with jump_2_down")
Player.reset(36, 11, "up")
local movementDone = false

Objects.applyMovement(0xFF, { 0x14, 0xFE }, function()
  movementDone = true
end)

assert(Objects.pollMovement(0xFF) == false, "Movement pending initially")

local maxSteps = 100
local steps = 0
while not movementDone and steps < maxSteps do
  steps = steps + 1
  Player.update(nil)
  Objects.update(nil)
end

assert(movementDone == true, "Movement onDone callback fired")
assert(Objects.pollMovement(0xFF) == true, "pollMovement reports completed")
assert(Player.cellX == 36 and Player.cellY == 13, "Player landed at (36, 13)")
print("[ok] Objects.applyMovement on player jump passed")

-- -----------------------------------------------------------------------------
-- 5. NPC Objects.scriptJump
-- -----------------------------------------------------------------------------
print("[test] 5. NPC Objects.scriptJump")
local npcDef = {
  localId = 1,
  index = 1,
  x = 10,
  y = 10,
  graphicsId = 1,
  sprite = "SPRITE_BOY",
}
Objects.loadMap(nil, "VIRIDIAN_CITY", { objects = { npcDef } })
local npc = Objects.find(1)
assert(npc ~= nil, "NPC found")

local npcDone = false
Objects.applyMovement(1, { 0x14, 0xFE }, function()
  npcDone = true
end)

steps = 0
while not npcDone and steps < maxSteps do
  steps = steps + 1
  Objects.update(nil)
end

assert(npcDone == true, "NPC movement completed")
assert(npc.cellX == 10 and npc.cellY == 12, "NPC jumped 2 cells down to (10, 12)")
print("[ok] NPC scriptJump passed")

-- -----------------------------------------------------------------------------
-- 6. Viridian City Gym Sliding Door (SE_SLIDING_DOOR, SlidingDouble)
-- -----------------------------------------------------------------------------
print("[test] 6. Viridian City Gym door uses SE_SLIDING_DOOR and SlidingDouble animation")
local Doors = require("src.core.game3.doors")

local snd, kind = Doors.getSoundForWarp("VIRIDIAN_CITY", 36, 10, "MAP_VIRIDIAN_CITY_GYM", true)
assert(snd == Doors.SOUND_SLIDING, "Sound is SE_SLIDING_DOOR (18)")
assert(kind == "SlidingDouble" or kind == "sliding_double", "Kind is SlidingDouble")

local openAnim = Doors.open("VIRIDIAN_CITY", 36, 10, { destMap = "MAP_VIRIDIAN_CITY_GYM" })
assert(openAnim ~= nil, "openAnim created")
assert(openAnim.tile == "SlidingDouble", "Door tile is SlidingDouble")
assert(openAnim.kind == "SlidingDouble" or openAnim.kind == "sliding", "Door kind is sliding")
assert(openAnim.size == "1x1", "Door size is 1x1")

print("[ok] Viridian City Gym door verified as sliding door")

print("=== ALL VIRIDIAN GYM DOOR & JUMP TESTS PASSED ===")
