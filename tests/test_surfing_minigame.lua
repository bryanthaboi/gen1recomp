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

-- Test 1: Initialization
local mg = SurfingMinigame.new(mockGame)
assert_eq(mg.hp, 6000, "Initial HP must be 6000 (60.00s)")
assert_eq(mg.speed, 0.25, "Initial speed must be 0.25")
assert_eq(mg.distance, 0, "Initial distance must be 0")
assert_eq(mg.routine, 0, "Initial routine must be ROUTINE_START_GAME (0)")
assert_eq(mg.pikaState, 0, "Initial Pikachu state must be PIKA_STATE_RIDING (0)")
print("✓ Initial state test passed")

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
print("✓ Results tally countdown test passed")

print("All SurfingMinigame unit tests passed successfully!")
