-- engine/overworld/player_movement.asm:93-110
-- engine/overworld/movement.asm:315-327
-- map_object_action.asm:71-94

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local Player = require("src.world.gen2.Player")

local MAP = {
  inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 20 and y < 20 end,
  isWalkable = function(_, x, y) return x == 5 and y == 5 end,
}

local OPEN = {
  inBounds = function() return true end,
  isWalkable = function() return true end,
}

local function newPlayer()
  local p = Player.new(5, 5, "right", nil)
  p.turnArmed = false
  return p
end

local p = newPlayer()
eq(p:tryMove("right", MAP, nil), "blocked", "the wall refuses the step")
eq(p.moving, false, "a bump never starts a step")
check((p.bumpFrames or 0) > 0, "the refusal armed the in-place bump")

local seen = {}
for _ = 1, 40 do
  p:tryMove("right", MAP, nil)
  seen[p:walkPhase()] = true
  p:update()
  eq(p.moving, false, "still standing on the same cell")
end
check(seen[0] and seen[1], "the legs cycle in place while held into the wall")
eq(p.cellX, 5, "and the player never left the cell")

p = newPlayer()
p.animClock = 0
local phases, flips = {}, {}
for i = 0, 63 do
  p:tryMove("right", MAP, nil)
  phases[i] = p:walkPhase()
  flips[i] = p:drawFlip()
  p:update()
end
-- map_object_action.asm:98-119
eq(phases[0], 0, "the first pose is the standing one")
eq(phases[6], 0, "still standing seven frames in")
eq(phases[14], 0, "and still standing at fifteen frames")
eq(phases[16], 1, "the walking pose lands on the sixteenth frame")
eq(phases[30], 1, "and holds for sixteen frames")
eq(phases[32], 0, "back to standing")
eq(phases[48], 1, "the second walking pose is the mirrored one")
check(flips[48] ~= flips[16], "which draws with the other leg forward")

local function firstRunOfWalk(seq)
  local start
  for i = 0, #seq do
    if seq[i] == 1 then
      if not start then start = i end
    elseif start then
      return i - start
    end
  end
end

local walkPhases = {}
local w = newPlayer()
for i = 0, 63 do
  if not w.moving then w:tryMove("right", OPEN, nil) end
  walkPhases[i] = w:walkPhase()
  w:update()
end
local bumpRun = firstRunOfWalk(phases)
local walkRun = firstRunOfWalk(walkPhases)
eq(walkRun, 8, "a walked step holds each pose eight frames")
eq(bumpRun, walkRun * 2, "a bump holds each pose twice as long as a step")

p = newPlayer()
p.animClock = 16
p:tryMove("right", MAP, nil)
-- engine/overworld/movement.asm:315
eq(p.bumpFrames, 1, "the bump lasts one OBJECT_STEP_DURATION frame")
eq(p:walkPhase(), 1, "which draws the walking pose")
p:update()
-- engine/overworld/player_movement.asm:108
eq(p:walkPhase(), 0, "and .Standing drops to the standing pose on release")
eq(p:drawFlip(), p.stepFlip, "with the sprite unmirrored again")

p = newPlayer()
p.animClock = 16
p:tryMove("right", MAP, nil)
-- engine/overworld/player_movement.asm:807
p:stopForEvent()
eq(p.bumpFrames, nil, "an event cancels the queued bump")
eq(p:walkPhase(), 0, "and the talk starts on the standing pose")
eq(p:drawFlip(), p.stepFlip, "unmirrored, whatever the clock read")

p = newPlayer()
p:tryMove("right", MAP, nil)
eq(p:tryMove("right", OPEN, nil), "moved", "an open tile steps")
eq(p.bumpFrames, nil, "a step clears the bump")

p = newPlayer()
p.turnArmed = true
p:tryMove("right", MAP, nil)
eq(p:tryMove("down", MAP, nil), "turned", "a new direction turns first")
eq(p.bumpFrames, nil, "and the turn frames are not a bump")

p = newPlayer()
p:tryMove("right", MAP, nil)
p:scriptStep("right")
eq(p.bumpFrames, nil, "a cutscene step clears the bump")

T.finish("gen2_bump_walk_in_place_bug1978")
