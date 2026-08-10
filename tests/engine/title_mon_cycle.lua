-- ..(engine/movie/title.asm ln 227)
-- ..(engine/movie/title2.asm ln 13)
--   luajit tests/engine/title_mon_cycle.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
local eq = T.eq

love = require("tests.love_stub")
love.math = love.math or {}
local nextPick = 1
love.math.random = function(lo, hi)
  nextPick = nextPick % hi + 1
  return math.max(lo, nextPick)
end

local TitleState = require("src.ui.TitleState")

local title = TitleState.new(
  { data = {}, input = { wasPressed = function() return false end } }, {})
title.sprites = setmetatable({}, { __index = function() return false end })

eq(title.phase, "drop", "Red/Blue boot into the logo drop, not the loop")
local ribbonSeen = {}
for _ = 1, 400 do
  if title.phase == "loop" then break end
  title:update(1 / 60)
  if title.phase == "ribbon" then
    ribbonSeen[#ribbonSeen + 1] = title.ribbonOffset
  end
end
eq(title.phase, "loop", "the cinematic lands within 400 frames")
eq(ribbonSeen[1], 112,
  "the ribbon is parked off the right edge on its first drawn frame")
eq(ribbonSeen[#ribbonSeen], 4, "and walks in 4px a frame to its rest")

title.cycleIndex = 1 -- CHARMANDER: a starter, so the ball juggle runs
title.scrollPhase, title.scrollFrame, title.timer = "hold", 1, 0
title.monOffset = 0

local frames = {}
for _ = 1, 260 do
  title:update(1 / 60)
  frames[#frames + 1] = {
    phase = title.scrollPhase, offset = title.monOffset,
    ball = title.ballY, mon = title.cycleSpecies[title.cycleIndex],
  }
end

local HOLD_FRAMES = 200

local function span(phase)
  local first, count = nil, 0
  for i, f in ipairs(frames) do
    if f.phase == phase then
      if not first then first = i end
      if first + count == i then count = count + 1 end
    end
  end
  return first, count
end

local holdAt, holdLen = span("hold")
local outAt, outLen = span("out")
local ballAt, ballLen = span("ball")
local inAt, inLen = span("in")
eq(holdAt, 1, "the cycle opens on the hold")
eq(holdLen, HOLD_FRAMES - 1, "ld c, 200 / CheckForUserInterruption")
eq(outAt, HOLD_FRAMES, "the scroll out begins as the 200th hold frame ends")
eq(outLen, 18, "TitleScroll_Out is 2+2+2+2+2+2+3+3 frames")
eq(ballLen, 10, "TitleScroll_WaitBall is two runs of 5")
eq(inLen, 17, "TitleScroll_In is 2+4+4+3+2+1+1 frames")
check(outAt < ballAt and ballAt < inAt, "out, then the ball, then in")

local OUT = { 0, -1, -2, -4, -6, -9, -12, -16, -20, -25, -30, -36, -42,
              -50, -58, -66, -75, -84 }
for i, want in ipairs(OUT) do
  eq(frames[outAt + i - 1].offset, want,
    "TitleScroll_Out offset at frame " .. i)
end

local IN = { 120, 110, 100, 91, 82, 73, 64, 56, 48, 40, 32, 26, 20, 14, 9,
             4, 1 }
for i, want in ipairs(IN) do
  eq(frames[inAt + i - 1].offset, want, "TitleScroll_In offset at frame " .. i)
end

local BALL = { 97, 95, 94, 93, 92, 93, 94, 95, 97, 100 }
for i, want in ipairs(BALL) do
  eq(frames[ballAt + i - 1].ball, want, "TitleBallYTable entry " .. i)
end

local outgoing = frames[outAt].mon
eq(outgoing, "CHARMANDER", "the starter is the one that scrolls out")
for i = outAt, inAt - 1 do
  eq(frames[i].mon, outgoing,
    "the pick does not change before the scroll in, at frame " .. i)
end
local incoming = frames[inAt].mon
check(incoming ~= outgoing, "TitleScreenPickNewMon never repeats the pick")
for i = inAt, inAt + inLen - 1 do
  check(frames[i].offset > 0,
    "the incoming mon is only ever drawn right of rest, at frame " .. i)
end
eq(frames[inAt + inLen].offset, 0, "and settles at its resting column")

T.finish("title_mon_cycle")
