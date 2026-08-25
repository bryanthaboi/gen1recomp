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
assert_eq(mg.routine, 0, "Routine must be ROUTINE_START_GAME (0) after startFromTitle()")
assert_eq(mg.hp, 6000, "Initial HP must be 6000 (60.00s)")
assert_eq(mg.speed, 0.25, "Initial speed must be 0.25")
assert_eq(mg.distance, 0, "Initial distance must be 0")
assert_eq(mg.pikaState, 0, "Initial Pikachu state must be PIKA_STATE_RIDING (0)")
print("✓ Initial state & Title transition test passed")

-- Test 2: StartGame one-shot then RunGame; banner slides during play (pret-accurate)
mg:update()
assert_eq(mg.routine, 1, "First tick should advance to ROUTINE_RUN_GAME (1)")
assert_true(mg.startBannerX > 80, "START banner should begin off-screen")
for _ = 1, 36 do
  mg:update()
end
assert_eq(mg.routine, 1, "Routine should remain ROUTINE_RUN_GAME (1) while banner slides")
assert_eq(mg.startBannerX, 80, "START banner should finish centered after 36 frames")
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
mg.getWaveTileUnderPika = function() return 0x01 end -- force open water (flat branch)
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
-- TileInteraction keys off chr tile ids, not pattern metatile ids
mg.getWaveTileUnderPika = function() return 0x06 end
mg.frameSet = 6
assert_eq(mg:evaluateLanding(), "clean", "Frame 6 on chr tile $06 rising slope must be clean")
mg.getWaveTileUnderPika = function() return 0x0b end
mg.frameSet = 6
assert_eq(mg:evaluateLanding(), "hard", "Frame 6 on chr tile $0b open water must be hard")
mg.getWaveTileUnderPika = function() return 0x08 end
mg.frameSet = 6
assert_eq(mg:evaluateLanding(), "hard", "Frame 6 on chr tile $08 foam must use flat rules (hard)")
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
mg.showResultsCard = true
mg.routine = 7 -- ROUTINE_WRITE_TOTAL
mg.hp = 100
mg.radness = 200
mg.totalScore = 0
mg.routineTimer = 0
mg:update()
assert_eq(mg.routine, 8, "Routine should advance to ROUTINE_ADD_HP_TOTAL (8)")
mg.routineTimer = 0 -- pret waits 64 frames before tally; skip for unit test

while mg.routine == 8 do
  mg:update()
end
assert_eq(mg.hp, 0, "HP should be tallied down to 0")
assert_eq(mg.totalScore, 100, "Total score should include 100 from HP")
assert_eq(mg.routine, 9, "Routine should advance to ROUTINE_ADD_RAD_TOTAL (9)")
mg.routineTimer = 0

while mg.routine == 9 do
  mg:update()
end
assert_eq(mg.radness, 0, "Radness should be tallied down to 0")
assert_eq(mg.totalScore, 300, "Total score should be 300 (100 HP + 200 Radness)")
assert_eq(mg.routine, 10, "Routine should advance to ROUTINE_WAIT_LAST (10)")
-- Test 8: Crossing finish line while jumping upside-down crashes into water and rights Pikachu before results
local mg8 = SurfingMinigame.new(mockGame, nil, true)
mg8.routine = 1 -- ROUTINE_RUN_GAME
mg8.distanceSection = 24
mg8.distanceAcc = 0
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
mg9.distanceSection = 24
mg9.distanceAcc = 0
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
mg10.distanceSection = 24
mg10.distanceAcc = 0
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
mg12.bgMap[5] = mg12.cols[5]
mg12.waveHeight[8] = 110
mg12.waveHeight[9] = 100
mg12.bgMapReadTile = 0x06
mg12.advanceScx = function() end
mg12.generateBgMapIfNeeded = function() end
mg12.distanceFixed = (5 * 16 - 80) * 256
local startY = mg12.pikaY
mg12:update()
assert(mg12.pikaY ~= startY, "pikaY must continuously follow wave surface height while in PIKA_STATE_LANDING")
print("✓ Landing slope height tracking continuity test passed")

-- Test 12b: Clean flat landing preserves speed; rough/hard use pret penalties
local mg12b = SurfingMinigame.new(mockGame, nil, true)
mg12b.routine = 1
mg12b.frameSet = 4
mg12b.bgMapReadTile = 0x0b
mg12b.speedFixed = 320
local cleanSpeed = mg12b.speedFixed
mg12b:handleLanding()
assert_eq(mg12b.speedFixed, cleanSpeed, "Clean flat landing must not reduce speed")
mg12b.speedFixed = 320
mg12b.frameSet = 5
mg12b.bgMapReadTile = 0x0b
mg12b:handleLanding()
assert_eq(mg12b.speedFixed, 320 - 64, "Rough flat landing must reduce speed by 0.25")
mg12b.speedFixed = 96
mg12b.frameSet = 6
mg12b.bgMapReadTile = 0x0b
mg12b:handleLanding()
assert_eq(mg12b.speedFixed, 0, "Hard landing below 0.5 must zero speed (pret underflow guard)")
print("✓ Landing speed penalty test passed")

-- Test 13: Fixed speed enforcement (minigames must always run at 1X speed)
assert(mg12.isFixedSpeed == true, "SurfingMinigame must have isFixedSpeed flag enabled")
assert(mg12.isMinigame == true, "SurfingMinigame must have isMinigame flag enabled")
local mockStack = { states = { mg12 } }
local Game = require("src.core.Game")
assert(Game.isFixedSpeedInStack(mockStack) == true, "Game.isFixedSpeedInStack must return true for SurfingMinigame")
print("✓ Minigame fixed speed enforcement test passed")

-- Test 14: Course duration matches pret distance model (~24 sections, 6000 HP cap)
local mg14 = SurfingMinigame.new(mockGame, nil, true)
mg14.routine = 1
local runFrames = 0
for _ = 1, 7000 do
  mg14:update()
  runFrames = runFrames + 1
  if mg14.distanceSection >= 24 then break end
end
assert(runFrames >= 2500 and runFrames <= 5500,
  "Full course should finish in pret-like frame window (got " .. runFrames .. ")")
assert(mg14.hp > 0, "Typical run should reach shore before HP timer expires")
print("✓ Course duration window test passed (" .. runFrames .. " frames)")

-- Test 15: Pret 2-frame joy sampling allows triple flips at max jump arc
mockInput.keysDown = { left = true }
local mg15 = SurfingMinigame.new(mockGame, nil, true)
mg15.routine = 1
mg15.speedFixed = 512
mg15.pikaState = 1
mg15.jumpArcMagnitude = 16
mg15.jumpArcFraction = 0
mg15.jumpDescending = false
mg15.pikaY = 84
mg15.frameSet = 4
mg15.radnessMeter = 0
mg15.trickFlags = 0
local airFrames = 0
while mg15.pikaState == 1 and airFrames < 200 do
  mg15:update()
  airFrames = airFrames + 1
end
assert_true(mg15.radnessMeter >= 3,
  "Max-arc jump with held left must register at least 3 flips (got " .. tostring(mg15.radnessMeter) .. ")")
assert_true(airFrames >= 60, "Max-arc jump should stay airborne long enough for triple flips")
print("✓ Triple flip airtime and joy sampling test passed")

-- Test 16: Pret music tempo tiers (index = high byte of ((speed & $3ff) << 1))
local mg16 = SurfingMinigame.new(mockGame, nil, true)
mg16.routine = 1
local tempoCases = {
  { speed = 64,  tier = 1 },
  { speed = 127, tier = 1 },
  { speed = 128, tier = 2 },
  { speed = 255, tier = 2 },
  { speed = 256, tier = 3 },
  { speed = 383, tier = 3 },
  { speed = 384, tier = 4 },
  { speed = 511, tier = 4 },
  { speed = 512, tier = 5 },
}
for _, c in ipairs(tempoCases) do
  mg16.speedFixed = c.speed
  mg16:updateTempo()
  local wantPitch = ({ 1.0, 117 / 109, 117 / 101, 117 / 93, 117 / 85 })[c.tier]
  assert_eq(mg16.currentPitch, wantPitch,
    string.format("Tempo tier %d at speed %d/256", c.tier, c.speed))
end
print("✓ Pret music tempo tier boundaries test passed")

-- Test 17: GetJoypad_3FrameBuffer duty cycle (hFrameCounter reload $2 → sample when counter hits 0)
mockInput.keysDown = { left = true }
local mg17 = SurfingMinigame.new(mockGame, nil, true)
mg17.routine = 1
local samples = 0
for _ = 1, 9 do
  mg17:update()
  if mg17.joy5Left then samples = samples + 1 end
end
-- Counter reloads to 2 then VBlank decrements twice → active on frames 1,3,5,7,9 of each 9-frame window
assert_eq(samples, 5, "Held input must register 5 sample frames per 9 ticks (got " .. samples .. ")")
print("✓ Pret joypad 3-frame buffer duty cycle test passed")

-- Test 18: Results card keeps Pikachu on the beach (pret DrawResultsScreen + UpdateResultsPikachu)
local mg18 = SurfingMinigame.new(mockGame, nil, true)
mg18:beginResultsCard()
assert_eq(mg18.pikaY, 116 - 16, "Results Pikachu Y must anchor at flat waterline")
assert_eq(mg18.frameSet, 4, "Results pose must use flat ride frameset")
assert_true(mg18.showResultsCard, "Results card must be active")
assert_eq(mg18.cloudSpriteX, nil, "Cloud OAM must be cleared on results screen")
mg18.pikaState = 6 -- PIKA_STATE_RESULTS (pret sets this on hi-score)
mg18.resultsBobTimer = 62
mg18:updateResultsPikachu()
assert_true(mg18.pikaYOffset ~= 0 or mg18.resultsBobTimer >= 64,
  "Results bob must run once PIKA_STATE_RESULTS is active")
print("✓ Results beach Pikachu visibility test passed")

print("All SurfingMinigame unit tests passed successfully!")
