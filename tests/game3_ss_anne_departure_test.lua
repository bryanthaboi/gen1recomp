-- Tests for Game 3 S.S. Anne departure animation cutscene (DoSSAnneDepartureCutscene).
-- Matches pret pokefirered (src/ss_anne.c, data/maps/SSAnne_Exterior/scripts.inc).

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local SSAnneCutscene = require("src.core.game3.ss_anne_cutscene")
local Objects = require("src.core.game3.objects")

local playedSEs = {}
local Audio = require("src.core.game3.audio")
Audio.playSe = function(id)
  table.insert(playedSEs, id)
end

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a)))
  end
end

local function assert_true(cond, msg)
  if not cond then
    error(msg or "expected true, got false")
  end
end

print("[test] 1. Special constant and registration")
assert_eq(Std.SPECIAL.DoSSAnneDepartureCutscene, 0x191, "DoSSAnneDepartureCutscene is 0x191 (401)")
assert_true(Natives.ALLOW["special:" .. 0x191] ~= nil, "special 0x191 handler registered")
print("[ok] special 0x191 correctly defined and registered")

print("[test] 2. S.S. Anne cutscene lifecycle and timing")
playedSEs = {}

-- Mock the S.S. Anne boat event object (localId 1)
Objects.clear()
local mockBoat = {
  localId = 1,
  graphicsId = 151,
  cellX = 30,
  cellY = 16,
  px = 30 * 16,
  py = 16 * 16,
  visible = true,
  hidden = false,
  raiseX = 0,
}
Objects._byId[1] = mockBoat
Objects._order = { 1 }

local task = SSAnneCutscene.start()
assert_true(SSAnneCutscene.isActive(), "cutscene is active")
assert_eq(SSAnneCutscene._phase, "init", "initial phase is init")
assert_eq(#playedSEs, 1, "initial horn SE played")
assert_eq(playedSEs[1], 249, "SE is SE_SS_ANNE_HORN (249)")

-- Init phase: 50 frames
for f = 1, 49 do
  local done = task()
  assert_eq(done, false, "init phase not done at frame " .. f)
  assert_eq(SSAnneCutscene._phase, "init", "still init phase at frame " .. f)
end

-- Frame 50 finishes init and enters run
local done50 = task()
assert_eq(done50, false, "not done at frame 50")
assert_eq(SSAnneCutscene._phase, "run", "switched to run phase")
assert_true(SSAnneCutscene._wake ~= nil, "wake sprite created")

print("[ok] init phase successfully executed 50 frames and spawned wake")

print("[test] 3. Run phase boat movement, smoke spawning, and wake animation")
-- Tick 70 frames: first smoke puff spawned at 70th run frame
for f = 1, 69 do
  task()
  assert_eq(#SSAnneCutscene._smokes, 0, "no smoke before 70 frames")
end
task() -- 70th run frame
assert_eq(#SSAnneCutscene._smokes, 1, "smoke puff spawned at 70 frames")
assert_eq(SSAnneCutscene._smokes[1].frame, 0, "smoke starts at frame 0")

-- Verify boat offset: at 70 run frames, offset = math.floor(70 / 5) = 14 px
assert_eq(SSAnneCutscene._boatOffset, 14, "boat offset is 14 px at frame 70")
assert_eq(mockBoat.raiseX, -14, "boat object raiseX is -14")

-- Verify wake animation
assert_true(SSAnneCutscene._wake.x2 > 0, "wake drifting right relative to boat")

-- Advance to near exit (travel distance 216 px = 216 * 5 = 1080 frames)
local prevSmokesCount = #SSAnneCutscene._smokes
for f = 71, 1079 do
  task()
end

assert_eq(SSAnneCutscene._phase, "run", "still run phase before distance reached")
assert_true(#playedSEs == 1, "only 1 horn so far")

-- Frame 1080 reaches 216 px offset and triggers exit horn
task()
assert_eq(SSAnneCutscene._phase, "finish", "switched to finish phase")
assert_eq(#playedSEs, 2, "second horn played on departure")
assert_eq(playedSEs[2], 249, "departure horn is SE_SS_ANNE_HORN (249)")

print("[ok] run phase motion, smoke puffs, and departure horn verified")

print("[test] 4. Finish phase delay and clean completion")
for f = 1, 39 do
  local done = task()
  assert_eq(done, false, "finish phase not done at frame " .. f)
end

local finalDone = task() -- 40th frame of finish
assert_eq(finalDone, true, "cutscene completed on 40th finish frame")
assert_eq(SSAnneCutscene.isActive(), false, "cutscene inactive after completion")
assert_eq(mockBoat.raiseX, 0, "boat raiseX reset")

print("[ok] finish phase completed after 40 frames and cleaned up state")

print("[PASS] game3 S.S. Anne departure cutscene tests")
