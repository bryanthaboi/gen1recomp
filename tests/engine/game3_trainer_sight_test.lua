#!/usr/bin/env luajit
-- Comprehensive Game 3 Trainer Line of Sight Test Suite
-- Tests all 5 Game Freak overworld quirks:
-- 1. Elevation & Ledge Masking
-- 2. The Spinning Trainer Hook
-- 3. Menu Dismissal Frame Trap
-- 4. Zero-Distance Walk-Ups (dist = 1)
-- 5. Simultaneous Spot Prioritization

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local TrainerSight = require("src.core.game3.trainer_sight")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local FieldEffects = require("src.core.game3.field_effects")
local Collision = require("src.core.game3.collision")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local Vm = require("src.core.game3.scripting.vm")

local dummyGame = {
  data = {
    maps = {
      TEST_MAP = {
        width = 30,
        height = 30,
        midLayout = nil,
      }
    }
  }
}

-- Setup clean mock store & bundle
local store = Flags.newStore()
Space.store = store
local scripts = {
  ["trainer_battle_01"] = {
    { op = "trainerbattle", type = 0, trainer = 10, introText = "t1", defeatText = "t2" },
    { op = "end" },
  },
  ["trainer_battle_02"] = {
    { op = "trainerbattle", type = 0, trainer = 20, introText = "t1", defeatText = "t2" },
    { op = "end" },
  },
}
Space.bundle = {
  scripts = scripts,
  text = {},
  movements = {},
  events = {
    TEST_MAP = {
      objects = {},
    }
  }
}
Space.vm = Vm.new({
  store = store,
  scripts = scripts,
  adapters = { log = function() end },
})

print("[test] 1. Directional Line of Sight Raycasting (Down, Up, Left, Right)")
local eo = {
  localId = 1,
  cellX = 10,
  cellY = 10,
  px = 160,
  py = 160,
  facing = "down",
  sight = 4,
  trainerType = 1,
  elevation = 0,
  visible = true,
  hidden = false,
  moving = false,
  frozen = false,
  scriptBusy = false,
  scriptKey = "trainer_battle_01",
}

-- Mock Collision.canEnter to default true
Collision.canEnter = function(_g, _x, _y, _opts) return true end
Collision.isLedge = function(_x, _y) return false end
Collision.cell = function(_x, _y) return 0x00 end

Player.reset(10, 13, "up") -- 3 tiles down from eo (within sight 4)
local spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == true and dist == 3, "Spotted 3 tiles down")

Player.reset(10, 15, "up") -- 5 tiles down (out of sight 4)
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == false, "Not spotted out of range (5 tiles)")

Player.reset(11, 13, "up") -- Misaligned X
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == false, "Not spotted when misaligned")

-- Test other facings
eo.facing = "up"
Player.reset(10, 8, "down") -- 2 tiles up
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == true and dist == 2, "Spotted 2 tiles up")

eo.facing = "left"
Player.reset(6, 10, "right") -- 4 tiles left
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == true and dist == 4, "Spotted 4 tiles left")

eo.facing = "right"
Player.reset(14, 10, "left") -- 4 tiles right
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == true and dist == 4, "Spotted 4 tiles right")

print("[test] 2. Elevation and Ledge Masking")
eo.facing = "down"
Player.reset(10, 13, "up")

-- Different elevation (eo on bridge elevation 4 vs player on ground 3)
eo.elevation = 4
Player.elevation = 3
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == false, "Blocked by elevation mismatch (eo=4 bridge, player=3 ground)")
eo.elevation = 3
Player.elevation = 3
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == true, "Spotted when elevations match (eo=3, player=3)")
eo.elevation = 0
Player.elevation = 0
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == true, "Spotted when default ground elevations match (eo=0, player=0)")

-- Ledge masking: tile (10, 12) has a one-way ledge hop (MB_JUMP_SOUTH = 0x38)
Collision.cell = function(x, y)
  if x == 10 and y == 12 then return 0x38 end
  return 0x00
end
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == false, "Blocked by one-way ledge boundary byte (0x38)")

-- Solid obstacle (wall/tree) at (10, 11)
Collision.cell = function() return 0x00 end
Collision.canEnter = function(_g, x, y, _opts)
  if x == 10 and y == 11 then return false end
  return true
end
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == false, "Blocked by solid obstacle tile at (10, 11)")
Collision.canEnter = function() return true end

print("[test] 3. Defeated Trainer Flag Check")
eo.facing = "down"
Player.reset(10, 12, "up")
check(TrainerSight.isDefeated(eo, store, Space.vm.ctx) == false, "Trainer not defeated yet")

-- Mark trainer 10 as defeated
local flagId = Flags.trainerFlagId(10)
Flags.setFlag(store, nil, flagId, true)
check(TrainerSight.isDefeated(eo, store, Space.vm.ctx) == true, "Trainer is defeated after flag set")

-- Clear flag for subsequent tests
Flags.setFlag(store, nil, flagId, false)
check(TrainerSight.isDefeated(eo, store, Space.vm.ctx) == false, "Trainer flag cleared")

print("[test] 4. Zero-Distance Walk-Ups (dist = 1)")
Player.reset(10, 11, "left") -- Player directly in front of trainer (dist = 1)
spotted, dist = TrainerSight.checkLineOfSight(eo, Player, dummyGame)
check(spotted == true and dist == 1, "Spotted at dist = 1")

Field.locked = false
Objects.clear()
Objects._byId[1] = eo
Objects._order = { 1 }

local scriptFired = false
Space.startScript = function(key, localId)
  scriptFired = true
  check(key == "trainer_battle_01", "Script key matches")
  check(localId == 1, "Local ID matches")
end

check(TrainerSight.check(dummyGame) == true, "TrainerSight.check engaged")
check(Field.locked == true, "Field locked on engagement")
-- Drain field effect anim
for _ = 1, 65 do
  FieldEffects.step()
end
check(scriptFired == true, "Battle script fired instantly without walk hang")
check(Player.facing == "up", "Player turned to face trainer (up)")

print("[test] 5. Simultaneous Spot Prioritization")
-- Place two trainers both spotting the player on the same frame:
-- Trainer 1 (localId = 1) at (10, 8) facing DOWN (dist = 3)
-- Trainer 2 (localId = 2) at (12, 11) facing LEFT (dist = 2)
Field.locked = false
scriptFired = false
FieldEffects.invalidate()
Objects.clearMovements()
local trainer1 = {
  localId = 1, cellX = 10, cellY = 8, px = 160, py = 128, facing = "down", sight = 4, trainerType = 1,
  elevation = 0, visible = true, hidden = false, moving = false, frozen = false, scriptBusy = false,
  scriptKey = "trainer_battle_01",
}
local trainer2 = {
  localId = 2, cellX = 12, cellY = 11, px = 192, py = 176, facing = "left", sight = 4, trainerType = 1,
  elevation = 0, visible = true, hidden = false, moving = false, frozen = false, scriptBusy = false,
  scriptKey = "trainer_battle_02",
}
Objects.clear()
Objects._byId[1] = trainer1
Objects._byId[2] = trainer2
Objects._order = { 1, 2 }

Player.reset(10, 11, "down")
local engaged = TrainerSight.check(dummyGame)
check(engaged == true, "Sight check engaged")
check(Field.locked == true, "Field locked")
check(trainer1.scriptBusy == true, "Trainer 1 (lower localId) claimed engagement")
check(trainer2.scriptBusy == false, "Trainer 2 suppressed")

print("[test] 6. The Spinning Trainer Hook")
Field.locked = false
FieldEffects.invalidate()
Objects.clearMovements()
trainer1.scriptBusy = false
trainer1.frozen = false
trainer1.moving = false
trainer1.cellX = 10
trainer1.cellY = 8
trainer1.facing = "left" -- Currently looking away from player at (10, 11)
trainer1.movement = "LOOK"
trainer1.range = "ANY_DIR"
trainer1.idleTimer = 1
Objects._byId[1] = trainer1
Objects._order = { 1 }
Player.reset(10, 11, "down")

local spottedFromSpin = false
Space.startScript = function(key, localId)
  spottedFromSpin = true
end

-- Force idleTick turn to "down"
trainer1.facing = "down"
TrainerSight.check(dummyGame, trainer1)
check(Field.locked == true, "Field locked from spinning trainer turn")
for _ = 1, 65 do FieldEffects.step() end
for _ = 1, 60 do Objects.update(dummyGame) end
check(spottedFromSpin == true, "Script started from spinning trainer spot")

print("[test] 7. Menu Dismissal Frame Trap")
Field.locked = false
FieldEffects.invalidate()
Objects.clearMovements()
trainer1.scriptBusy = false
trainer1.frozen = false
trainer1.moving = false
trainer1.facing = "down"
Player.reset(10, 12, "right") -- 4 tiles down (within sight 4)

local mockInput = {
  wasPressed = function(_, k) return k == "up" end,
  isDown = function(_, k) return k == "up" end,
}

-- Player.update runs when menu dismisses
Player.update(dummyGame, mockInput)
check(Field.locked == true, "Player.update trapped by trainer sight before D-pad step")
check(Player.moving == false, "Player prevented from moving away")

print("[test] 8. Trainer Spot Audio & SFX Choreography (SE_PIN + Encounter Music)")
Field.locked = false
FieldEffects.invalidate()
Objects.clearMovements()

local playedSeId = nil
local playedSongId = nil
local Audio = require("src.core.game3.audio")
Audio.playSe = function(id)
  playedSeId = id
  return true
end
Audio.playSong = function(id)
  playedSongId = id
  return true
end

local sightTrainer = {
  localId = 5,
  cellX = 10,
  cellY = 10,
  px = 160,
  py = 160,
  facing = "down",
  sight = 4,
  trainerType = 1,
  elevation = 0,
  visible = true,
  hidden = false,
  moving = false,
  frozen = false,
  scriptBusy = false,
  trainerId = 10,
  scriptKey = "trainer_battle_01",
}
Objects._byId[5] = sightTrainer
Objects._order = { 5 }
Player.reset(10, 14, "up") -- 4 tiles down

-- Spot trainer
TrainerSight.check(dummyGame)
check(playedSeId == 21, "SE_PIN (21) played immediately on spot")
check(playedSongId == 284 or playedSongId == 285 or playedSongId == 283, "Encounter theme started immediately on spot (song=" .. tostring(playedSongId) .. ")")

print("[test] 9. TRAINER_TYPE_NONE with leftover sight never engages (SSAnne_1F_Room2 Woman)")
scripts["ssanne_woman_msgbox"] = {
  { op = "msgbox", text = "cruising" },
  { op = "end" },
}
local function resetField()
  Field.locked = false
  FieldEffects.invalidate()
  Objects.clearMovements()
  playedSeId = nil
  playedSongId = nil
end
local startedKey = nil
Space.startScript = function(key) startedKey = key end

resetField()
local woman = {
  localId = 3, cellX = 2, cellY = 6, px = 32, py = 96, facing = "up",
  sight = 1, trainerType = 0,
  elevation = 0, visible = true, hidden = false, moving = false, frozen = false, scriptBusy = false,
  scriptKey = "ssanne_woman_msgbox",
}
Objects.clear()
Objects._byId[3] = woman
Objects._order = { 3 }
Player.reset(2, 5, "down")
check(TrainerSight.checkLineOfSight(woman, Player, dummyGame) == true,
  "Woman's leftover range-1 cone covers the player")
check(TrainerSight.isTrainerType ~= nil and TrainerSight.isTrainerType(woman) == false,
  "trainerType 0 is not a trainer")
check(TrainerSight.check(dummyGame) == false, "Idle sight check does not engage the Woman")
check(Field.locked == false, "Field stays unlocked")
check(woman.scriptBusy == false, "Woman not claimed")
check(playedSeId == nil and playedSongId == nil, "No SE_PIN / encounter music")
resetField()
woman.scriptBusy = false
woman.frozen = false
woman.moving = false
woman.facing = "up"
startedKey = nil
Player.reset(2, 5, "down")
check(TrainerSight.check(dummyGame, woman) == false, "Spinning-hook path does not engage the Woman")
check(Field.locked == false and woman.scriptBusy == false and playedSeId == nil,
  "Spinning-hook path leaves the field alone")
resetField()
woman.scriptBusy = false
woman.frozen = false
woman.moving = false
woman.facing = "up"
startedKey = nil
Player.reset(2, 5, "down")
for _ = 1, 3 do TrainerSight.check(dummyGame) end
check(Field.locked == false and startedKey == nil, "Repeated idle checks never loop the msgbox")

resetField()
local seeAll = {
  localId = 4, cellX = 2, cellY = 6, px = 32, py = 96, facing = "up",
  sight = 1, trainerType = 2,
  elevation = 0, visible = true, hidden = false, moving = false, frozen = false, scriptBusy = false,
  scriptKey = "trainer_battle_02",
}
Objects.clear()
Objects._byId[4] = seeAll
Objects._order = { 4 }
Player.reset(2, 5, "down")
check(TrainerSight.check(dummyGame) == false, "TRAINER_TYPE_SEE_ALL_DIRECTIONS (2) is not scanned")

resetField()
local buried = {
  localId = 6, cellX = 2, cellY = 6, px = 32, py = 96, facing = "up",
  sight = 1, trainerType = 3,
  elevation = 0, visible = true, hidden = false, moving = false, frozen = false, scriptBusy = false,
  scriptKey = "trainer_battle_02",
}
Objects.clear()
Objects._byId[6] = buried
Objects._order = { 6 }
Player.reset(2, 5, "down")
check(TrainerSight.check(dummyGame) == true, "TRAINER_TYPE_BURIED (3) still engages")
check(Field.locked == true and buried.scriptBusy == true, "Buried trainer claims the field")

resetField()
local normal = {
  localId = 7, cellX = 2, cellY = 6, px = 32, py = 96, facing = "up",
  sight = 1, def = { trainerType = 1 },
  elevation = 0, visible = true, hidden = false, moving = false, frozen = false, scriptBusy = false,
  scriptKey = "trainer_battle_01",
}
Objects.clear()
Objects._byId[7] = normal
Objects._order = { 7 }
Player.reset(2, 5, "down")
check(TrainerSight.check(dummyGame) == true, "TRAINER_TYPE_NORMAL (1) from def engages")
resetField()

print("[test] 10. Wandering/Pacing Trainer (e.g. Route 3 Lass) Walk-Up and Permanent Stay Conversion")
local pacer = {
  localId = 2, cellX = 40, cellY = 11, px = 640, py = 176, homeX = 40, homeY = 11,
  facing = "down", sight = 3, trainerType = 1,
  movement = "WALK", movementType = 0x03, range = "UP_DOWN", radius = { x = 1, y = 1 },
  elevation = 0, visible = true, hidden = false, moving = false, frozen = false, scriptBusy = false,
  scriptKey = "trainer_battle_01",
  def = { localId = 2, x = 40, y = 11, movementType = 0x03, movement = "WALK", range = "UP_DOWN" },
}
Objects.clear()
Objects._byId[2] = pacer
Objects._order = { 2 }
-- Player stands 3 tiles below pacer at (40, 14)
Player.reset(40, 14, "up")
check(TrainerSight.check(dummyGame) == true, "Pacing trainer spots player 3 tiles away")
check(Field.locked == true, "Field locked during exclamation and walk-up")

-- Simulate frames for exclamation effect and approach walk track
for _ = 1, 100 do
  FieldEffects.step()
  Objects.update(dummyGame)
end

check(pacer.cellX == 40 and pacer.cellY == 13, "Pacer walked 2 steps down to tile adjacent to player (40, 13)")
check(pacer.movement == "STAY", "Pacer movement changed to STAY")
check(pacer.movementType == 0x08, "Pacer movementType changed to MOVEMENT_TYPE_FACE_DOWN (0x08)")
check(pacer.homeX == 40 and pacer.homeY == 13, "Pacer home coordinates updated to post-approach location (40, 13)")

-- Verify that subsequent idle updates do not cause the trainer to resume pacing
pacer.idleTimer = 0
for _ = 1, 10 do
  Objects.update(dummyGame)
end
check(pacer.moving == false and pacer.cellX == 40 and pacer.cellY == 13, "Trainer remains stationary and does not resume wander cycle")

resetField()

if failed > 0 then
  print(string.format("\n%d FAILURE(S)", failed))
  os.exit(1)
end
print("\nAll trainer sight checks passed successfully!")
