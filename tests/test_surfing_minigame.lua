if not _G.love then
  _G.love = {
    audio = {
      newSource = function() return { stop = function() end, play = function() end, setVolume = function() end } end
    }
  }
end
local SurfingMinigame = require("src.ui.SurfingMinigame")

local function assert_eq(got, want, msg)
  if got ~= want then
    error(string.format("%s: got %s, want %s", msg or "assertion failed", tostring(got), tostring(want)))
  end
end

local function assert_true(cond, msg)
  if not cond then
    error(string.format("%s: expected true", msg or "assertion failed"))
  end
end

-- Mock game environment
local mockInput = {
  keysDown = {},
  keysPressed = {},
  isDown = function(self, k) return not not self.keysDown[k] end,
  wasPressed = function(self, k) return not not self.keysPressed[k] end,
}

local mockGame = {
  save = { surfingHighScore = 1000 },
  input = mockInput,
  stack = {
    items = {},
    pop = function(self) table.remove(self.items) end,
    push = function(self, item) table.insert(self.items, item) end,
  },
  data = { audio = { sfx = {} } },
}

print("Running SurfingMinigame unit tests...")

-- Test 1: Initialization & Title Screen transition
local mg = SurfingMinigame.new(mockGame)
assert_eq(mg.routine, -1, "Initial routine must be ROUTINE_TITLE (-1)")
mg:startFromTitle()
assert_eq(mg.routine, 0, "Routine must advance to ROUTINE_START_GAME (0) after startFromTitle()")
assert_eq(mg.hp, 6000, "Initial HP must be 6000 (60.00s)")
assert_eq(mg.speed, 0.25, "Initial speed must be 0.25")
assert_eq(mg.distance, 0, "Initial distance must be 0")
assert_eq(mg.pikaState, 0, "Initial Pikachu state must be PIKA_STATE_RIDING (0)")
print("✓ Initial state & Title transition test passed")

-- Test 2: Start banner transition to RunGame
for _ = 1, 40 do
  mg:update()
end
assert_eq(mg.routine, 1, "Routine should advance to ROUTINE_RUN_GAME (1)")
print("✓ Start banner transition test passed")

-- Test 3: Automatic acceleration and HP countdown
local initialSpeed = mg.speed
local initialHp = mg.hp
mg:update()
assert_true(mg.speed > initialSpeed, "Pikachu should automatically accelerate while riding")
assert_eq(mg.hp, initialHp - 1, "HP should decrease by 1 each frame")
print("✓ Auto acceleration and HP countdown test passed")

-- Test 4: Landing Evaluation Matrix
local old_getWaveTile = mg.getWaveTileUnderPika
mg.getWaveTileUnderPika = function() return 0x01 end -- force open water
mg.frameSet = 5
assert_eq(mg:evaluateLanding(), "rough", "Angle 5 on open water should be rough landing")
mg.frameSet = 6
assert_eq(mg:evaluateLanding(), "hard", "Angle 6 on open water should be hard landing")
mg.frameSet = 4
assert_eq(mg:evaluateLanding(), "clean", "Angle 4 (flat) on open water should be clean landing")
mg.frameSet = 1
assert_eq(mg:evaluateLanding(), "wipeout", "Angle 1 on open water should be wipeout")
for f = 8, 14 do
  mg.frameSet = f
  assert_eq(mg:evaluateLanding(), "wipeout", "Upside-down frame " .. f .. " must be wipeout")
end
mg.getWaveTileUnderPika = old_getWaveTile
print("✓ Landing evaluation matrix test passed (including upside-down frames 8..14)")

-- Test 5: Stunt Scoring
mg.radnessMeter = 1
mg.trickFlags = 1
mg.radness = 0
mg:calculateStuntPoints()
assert_eq(mg.radness, 50, "Single flip should award +50 radness points")

mg.radnessMeter = 2
mg.trickFlags = 1
mg.radness = 0
mg:calculateStuntPoints()
assert_eq(mg.radness, 150, "Double flip (same direction) should award +150 points")

mg.radnessMeter = 3
mg.trickFlags = 1
mg.radness = 0
mg:calculateStuntPoints()
assert_eq(mg.radness, 350, "Triple flip (same direction) should award +350 points")

mg.radnessMeter = 2
mg.trickFlags = 3
mg.radness = 0
mg:calculateStuntPoints()
assert_eq(mg.radness, 180, "Double flip (mixed) should award +180 points")

mg.radnessMeter = 3
mg.trickFlags = 3
mg.radness = 0
mg:calculateStuntPoints()
assert_eq(mg.radness, 500, "Triple flip (mixed) should award +500 points")
print("✓ Stunt scoring calculation test passed")

-- Test 6: Non-fatal wipeout crash recovery
mg.pikaState = 3 -- PIKA_STATE_CRASHED
mg.crashTimer = 96
mg.speed = 0.25
for _ = 1, 95 do
  mg:update()
  assert_eq(mg.pikaState, 3, "Pikachu should remain in crashed state during timer")
end
mg:update()
assert_eq(mg.pikaState, 0, "Pikachu should recover and return to PIKA_STATE_RIDING after 96 frames")
print("✓ Wipeout crash recovery test passed")

-- Test 7: Results tally countdown sequence
mg.routine = 7 -- ROUTINE_WRITE_TOTAL
mg.hp = 100
mg.radness = 200
mg.totalScore = 0
mg.routineTimer = 1
mg:update()
assert_eq(mg.routine, 8, "Routine should advance to ROUTINE_ADD_HP_TOTAL (8)")

while mg.routine == 8 do
  mg:update()
end
assert_eq(mg.hp, 0, "HP should be tallied down to 0")
assert_eq(mg.totalScore, 100, "Total score should include 100 from HP")
assert_eq(mg.routine, 9, "Routine should advance to ROUTINE_ADD_RAD_TOTAL (9)")

while mg.routine == 9 do
  mg:update()
end
assert_eq(mg.radness, 0, "Radness should be tallied down to 0")
assert_eq(mg.totalScore, 300, "Total score should be 300 (100 HP + 200 Radness)")
assert_eq(mg.routine, 10, "Routine should advance to ROUTINE_WAIT_LAST (10)")
-- Test 8: Crossing finish line while jumping upside-down crashes into water and rights Pikachu before results
local mg8 = SurfingMinigame.new(mockGame, nil, true)
mg8.routine = 1 -- ROUTINE_RUN_GAME
mg8.distanceFixed = (24 * 128 - 2) * 256
mg8.speedFixed = 512
mg8.pikaState = 1 -- PIKA_STATE_JUMPING
mg8.frameSet = 11 -- Upside down
mg8.pikaY = 60
mg8.jumpDescending = true
mg8.jumpArcMagnitude = 4
mg8.radness = 150
local preScore = mg8.radness

-- Update to cross the finish line
mg8:update()
assert_eq(mg8.routine, 2, "Routine should advance to ROUTINE_WAIT_RESULTS (2) upon crossing finish")
assert_eq(mg8.pikaState, 1, "Pikachu should remain mid-air immediately after crossing line")

-- Update until Pikachu lands in water
while mg8.pikaState == 1 do
  mg8:update()
end
assert_eq(mg8.pikaState, 3, "Upside-down landing post-finish line must trigger PIKA_STATE_CRASHED (3)")
assert_eq(mg8.radness, preScore, "Radness score must NOT change after crossing finish line")
assert_eq(mg8.crashTimer, 96, "Crash timer must be initialized to 96 frames")

-- Update while crashed to verify recovery
while mg8.pikaState == 3 do
  mg8:update()
end
assert_eq(mg8.pikaState, 0, "Pikachu must recover back to PIKA_STATE_RIDING (0) and right itself on the board")
assert_eq(mg8.frameSet, 4, "Pikachu frameSet must be reset to upright (4)")

-- Let coasting finish and verify transition to results
while mg8.routine == 2 do
  mg8:update()
end
assert_eq(mg8.routine, 3, "Routine should advance to ROUTINE_SCROLL_RESULTS (3) only after Pikachu is upright")
print("✓ Mid-air upside-down finish line crossing crash & recovery test passed")

-- Test 9: Crossing finish line while upright jumping lands cleanly and proceeds
local mg9 = SurfingMinigame.new(mockGame, nil, true)
mg9.routine = 1
mg9.distanceFixed = (24 * 128 - 2) * 256
mg9.speedFixed = 512
mg9.pikaState = 1
mg9.frameSet = 4 -- Clean flat
mg9.pikaY = 60
mg9.jumpDescending = true
mg9.jumpArcMagnitude = 4
mg9.radness = 200
preScore = mg9.radness

mg9:update()
assert_eq(mg9.routine, 2, "Routine should advance to ROUTINE_WAIT_RESULTS (2)")

while mg9.pikaState == 1 do
  mg9:update()
end
assert_eq(mg9.pikaState, 2, "Upright landing post-finish line must trigger PIKA_STATE_LANDING (2)")
assert_eq(mg9.radness, preScore, "Radness score must NOT change post-finish")

while mg9.pikaState == 2 do
  mg9:update()
end
assert_eq(mg9.pikaState, 0, "Pikachu must return to PIKA_STATE_RIDING (0)")
print("✓ Mid-air upright finish line crossing test passed")

-- Test 10: Crossing finish line while already crashed recovers before results
local mg10 = SurfingMinigame.new(mockGame, nil, true)
mg10.routine = 1
mg10.distanceFixed = (24 * 128 - 2) * 256
mg10.speedFixed = 512
mg10.pikaState = 3 -- PIKA_STATE_CRASHED
mg10.crashTimer = 50

mg10:update()
assert_eq(mg10.routine, 2, "Routine should advance to ROUTINE_WAIT_RESULTS (2)")
assert_eq(mg10.pikaState, 3, "Pikachu should still be crashed")

while mg10.pikaState == 3 do
  mg10:update()
end
assert_eq(mg10.pikaState, 0, "Pikachu must recover upright before proceeding to results")
print("✓ Pre-crashed finish line crossing recovery test passed")

-- Test 11: Decoupled timestep accumulator (60Hz and 144Hz framerate consistency)
local mg11_60 = SurfingMinigame.new(mockGame, nil, true)
mg11_60.routine = 1 -- ROUTINE_RUN_GAME
for _ = 1, 60 do
  mg11_60:update(1 / 60)
end
assert(mg11_60.t == 59 or mg11_60.t == 60, "60Hz update over 1s must produce approx 60 ticks (got " .. mg11_60.t .. ")")

local mg11_144 = SurfingMinigame.new(mockGame, nil, true)
mg11_144.routine = 1 -- ROUTINE_RUN_GAME
for _ = 1, 144 do
  mg11_144:update(1 / 144)
end
assert(mg11_144.t == 59 or mg11_144.t == 60, "144Hz update over 1s must produce approx 60 ticks (got " .. mg11_144.t .. ")")
print("✓ Decoupled 59.7275Hz timestep accumulator test passed")

-- Test 12: Landing continuity on slopes (no position jumps while landing)
local mg12 = SurfingMinigame.new(mockGame, nil, true)
mg12.routine = 1
mg12.pikaState = 2 -- PIKA_STATE_LANDING
mg12.landingTimer = 20
mg12.speedFixed = 256
-- Place on a rising wave pattern
mg12.cols[5] = { pat = SurfingMinigame.WAVE_PATTERNS[0x06], hl = 110, hr = 100 }
mg12.distanceFixed = (5 * 16 - 80) * 256
local startY = mg12.pikaY
mg12:update()
assert(mg12.pikaY ~= startY, "pikaY must continuously follow wave surface height while in PIKA_STATE_LANDING")
print("✓ Landing slope height tracking continuity test passed")

-- Test 13: Fixed speed enforcement (minigames must always run at 1X speed)
assert(mg12.isFixedSpeed == true, "SurfingMinigame must have isFixedSpeed flag enabled")
assert(mg12.isMinigame == true, "SurfingMinigame must have isMinigame flag enabled")
local mockStack = { states = { mg12 } }
local Game = require("src.core.Game")
assert(Game.isFixedSpeedInStack(mockStack) == true, "Game.isFixedSpeedInStack must return true for SurfingMinigame")
print("✓ Minigame fixed speed enforcement test passed")

print("All SurfingMinigame unit tests passed successfully!")
