package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Sound = require("src.core.Sound")
local Timing = require("src.core.Timing")
local IntroMovie = require("src.ui.IntroMovie")

local realPlay = Sound.play
Sound.play = function() end

local WAVES_START, SPLASH_FRAMES = 134, 318

local function newGame()
  local input = { pressed = {}, down = {} }
  function input:wasPressed(b) return self.pressed[b] or false end
  function input:isDown(b) return self.down[b] or false end
  return {
    input = input,
    data = { field = { intro = {
      fallingStar = { path = "tests/fixtures/missing_fallingstar_2385.png" },
      fallingStarBlink = { path = "tests/fixtures/missing_fallingstarblink_2385.png" },
    } } },
    stack = { pop = function() end },
  }
end

local function starDraws(m, t)
  m.phase, m.timer = 2, t
  local calls = {}
  local realDraw = love.graphics.draw
  love.graphics.draw = function(img, x, y, ...)
    if img == m.smallStar or img == m.smallStarBlink then
      calls[#calls + 1] = { img = img, x = x, y = y }
    end
  end
  local ok, err = pcall(m.drawSplash, m)
  love.graphics.draw = realDraw
  check(ok, "drawSplash runs headless" .. (ok and "" or (": " .. tostring(err))))
  return calls
end

local function at(calls, x)
  for _, c in ipairs(calls) do if c.x == x then return c end end
end

do
  local m = IntroMovie.new(newGame())
  check(m.smallStar and m.smallStarBlink and m.smallStar ~= m.smallStarBlink,
    "both falling-star looks load")
  local c = starDraws(m, WAVES_START)
  local s = at(c, 40)
  eq(s and s.y, 89, "wave 1 first shows one row below $68 (MoveDownSmallStars runs before the delay)")
  eq(s and s.img, m.smallStarBlink, "first substep shows rOBP1 $04 (toggled once before the delay)")
  s = at(starDraws(m, WAVES_START + 3), 40)
  eq(s and s.y, 90, "second substep moves one more row")
  eq(s and s.img, m.smallStar, "second substep is back on rOBP1 $A4")
  s = at(starDraws(m, WAVES_START + 24), 48)
  eq(s and s.y, 89, "wave 2 enters one row below $68 on its first substep")
  s = at(starDraws(m, SPLASH_FRAMES - 1), 52)
  eq(s and s.y, 88 + 48 - 24, "wave 4 rests after 24 moves")
  eq(s and s.img, m.smallStar, "the 40-frame tail holds rOBP1 $A4 after 48 toggles")
end

local function fightMovie()
  local game = newGame()
  local m = IntroMovie.new(game)
  m:startPhase(3)
  return m, game.input
end

local function tick(m, input, n, press)
  for i = 1, n or 1 do
    input.pressed = (i == 1 and press) or {}
    m:update(1 / 60)
  end
  input.pressed = {}
end

local function runToOp(m, input, idx)
  for _ = 1, 2000 do
    if m.opIndex >= idx then return true end
    tick(m, input, 1)
  end
  return false
end

local function fadeRun(m, input)
  local steps = {}
  for _ = 1, 40 do
    tick(m, input, 1)
    if m.phase == 4 then steps[#steps + 1] = 4 break end
    steps[#steps + 1] = m.fadeStep or 0
  end
  return steps
end

local function isStepped(steps)
  if #steps ~= 24 then return false end
  for i = 1, 23 do
    if steps[i] ~= math.floor((i - 1) / 8) + 1 then return false end
  end
  return steps[24] == 4
end

do
  local m, input = fightMovie()
  tick(m, input, Timing.DELAY3, { a = true })
  eq(m.opIndex, 1, "A during PlayShootingStar's Delay3 is not polled")
  eq(m.fadeStep, nil, "the deaf Delay3 starts no fade")
  tick(m, input, 1)
  local x = m.gengarX
  tick(m, input, 1, { a = true })
  eq(m.gengarX, x, "scroll-in odd frame moves nothing")
  local steps = fadeRun(m, input)
  check(isStepped(steps), "an interrupted scroll-in still runs GBFadeOutToWhite: 8 frames FadePal6, 8 FadePal7, then white ("
    .. table.concat(steps, ",") .. ")")
end

do
  local m, input = fightMovie()
  check(runToOp(m, input, 3), "reached the first hip animation")
  tick(m, input, 1, { a = true })
  tick(m, input, 3)
  eq(m.fadeStep, nil, "AnimateIntroNidorino's DelayFrames 5 is deaf")
  eq(m.phase, 3, "the fight goes on after a press inside an animation")
end

do
  local m, input = fightMovie()
  check(runToOp(m, input, 6), "reached the 10-frame wait")
  tick(m, input, 1, { start = true })
  check(isStepped(fadeRun(m, input)), "START inside a CheckForUserInterruption wait ends the scene into the stepped fade")
end

do
  local m, input = fightMovie()
  check(runToOp(m, input, 12), "reached the raise pose")
  local x = m.gengarX
  tick(m, input, 1)
  eq(m.opIndex, 14, "pose and SFX_INTRO_RAISE chain into the move on one frame")
  eq(m.gengarX, x - 2, "the raise's first SCX step lands on that frame")
  tick(m, input, 1, { a = true })
  eq(m.gengarX, x - 2, "a press on the step's second poll frame stops the move")
  eq(m.opIndex, 15, "IntroMoveMon returns early and the scene moves on to the next wait")
  eq(m.fadeStep, nil, "an interrupted Gengar move does not end the scene")
end

do
  local m, input = fightMovie()
  check(runToOp(m, input, 6), "reached the 10-frame wait again")
  input.down = { b = true }
  tick(m, input, 2)
  eq(m.fadeStep, nil, "B alone never interrupts")
  input.down = { up = true, select = true, b = true }
  tick(m, input, 1)
  input.down = {}
  check(isStepped(fadeRun(m, input)), "holding exactly UP+SELECT+B interrupts (home/overworld.asm:2404)")
end

do
  local m, input = fightMovie()
  m.lastPollHeld = { a = true }
  input.down = { up = true, select = true, b = true, a = true }
  check(runToOp(m, input, 6), "reached the wait with A held too")
  tick(m, input, 2)
  eq(m.fadeStep, nil, "UP+SELECT+B with another button held is not the combo")
end

do
  local m, input = fightMovie()
  check(runToOp(m, input, 3), "reached the first hip animation for the held press")
  input.down = { a = true }
  tick(m, input, 3)
  eq(m.fadeStep, nil, "A pressed and held inside a deaf animation is not seen there")
  check(runToOp(m, input, 6), "reached the next CheckForUserInterruption wait")
  tick(m, input, 1)
  input.down = {}
  check(isStepped(fadeRun(m, input)),
    "A still held at the next poll is new against hJoyLast and interrupts (home/joypad2.asm:16)")
end

do
  local m, input = fightMovie()
  m.lastPollHeld = { a = true }
  input.down = { a = true }
  check(runToOp(m, input, 7), "A held since the previous poll runs straight through the wait")
  eq(m.fadeStep, nil, "a button already held at the last poll is not a new press")
  input.down = {}
end

local function modMovie()
  local game = newGame()
  game.data.field.intro.gamefreakLogo = { path = "mods/demo/gamefreak_logo.png" }
  game.data.field.intro.gamefreakText = { path = "tests/fixtures/missing_gftext_2385.png" }
  return IntroMovie.new(game)
end

do
  local m = modMovie()
  eq(m.logoPath, nil, "mod-supplied logo art keeps the raw draw path")
  eq(m.gfTextPath, "tests/fixtures/missing_gftext_2385.png", "ROM text art still bakes through rOBP0")
end

Sound.play = realPlay
T.finish("intro_splash_fight_timing_bug2385")
