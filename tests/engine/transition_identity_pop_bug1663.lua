-- home/overworld.asm:690-703 (PlayMapChangeSound tail-calls GBFadeOutToBlack)
-- and home/fade.asm:43-46: the map-change fade has no matching fade in, so the
-- warp shape ends in the same frame its midpoint runs.  The midpoint is where
-- setMap opens things (the Cycling Road refusal box, a map script's onEnter),
-- and a fade that popped the top of the stack after that ate them and then
-- finished a second time (#1663).
--   luajit tests/engine/transition_identity_pop_bug1663.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local StateStack = require("src.core.StateStack")
local Transition = require("src.render.Transition")
local Timing = require("src.core.Timing")

local function overworld() return { name = "overworld", isOpaque = true } end

-- ------------------------------------------------ the warp shape (#1663)

do
  StateStack:init()
  local ow = overworld()
  StateStack:push(ow)

  local box = { name = "refusal" }
  local entered, depthAtMidpoint, topAtMidpoint = 0, nil, nil
  function box:enter() entered = entered + 1 end
  local dones = 0
  local fade
  fade = Transition.new({ stack = StateStack }, function()
    depthAtMidpoint = #StateStack.states
    topAtMidpoint = StateStack:top()
    StateStack:push(box)
  end, function() dones = dones + 1 end, true)
  StateStack:push(fade)

  local finishedOn
  for frame = 1, 120 do
    StateStack:update(1 / 60)
    if dones > 0 and not finishedOn then finishedOn = frame end
  end

  eq(finishedOn, Timing.WARP_FADE_OUT, "the warp hands back at the end of the fade")
  eq(dones, 1, "and hands back exactly once")
  eq(depthAtMidpoint, 1, "the fade is off the stack before the midpoint runs")
  check(topAtMidpoint == ow, "so the map switch sees the overworld on top")
  eq(entered, 1, "the state the midpoint pushed entered once")
  eq(#StateStack.states, 2, "the fade is gone and the pushed state is not")
  check(StateStack.states[1] == ow, "the overworld is still the base")
  check(StateStack:top() == box, "the box the midpoint opened owns the screen")
end

-- a midpoint that pushes nothing still leaves exactly the overworld behind
do
  StateStack:init()
  local ow = overworld()
  StateStack:push(ow)
  local mids, dones = 0, 0
  local fade = Transition.new({ stack = StateStack },
                              function() mids = mids + 1 end,
                              function() dones = dones + 1 end, true)
  StateStack:push(fade)
  for _ = 1, 120 do StateStack:update(1 / 60) end
  eq(mids, 1, "the map switched once")
  eq(dones, 1, "the plain warp still hands back exactly once")
  eq(#StateStack.states, 1, "and pops nothing but itself")
  check(StateStack:top() == ow, "leaving the overworld on top")
end

-- ------------------------------------------ the script fade is unchanged

-- ViridianGym.asm .afterBeat / RocketHideoutB4F BeatGiovanniScript bracket
-- their HideObject with GBFadeOutToBlack -> GBFadeInFromBlack, so those keep
-- a real fade in and wait under whatever the midpoint opened.
do
  StateStack:init()
  local ow = overworld()
  StateStack:push(ow)

  local box = { name = "script box" }
  local dones = 0
  local fade = Transition.new({ stack = StateStack },
                              function() StateStack:push(box) end,
                              function() dones = dones + 1 end, false)
  StateStack:push(fade)

  for _ = 1, Timing.WARP_FADE_OUT + 8 do StateStack:update(1 / 60) end
  eq(dones, 0, "a fade with a fade-in waits under what its midpoint opened")
  check(StateStack:top() == box, "the pushed state is on top")
  check(StateStack.states[2] == fade, "with the fade still underneath it")

  StateStack:pop()
  for _ = 1, Timing.FADE_IN_FROM_BLACK + 8 do StateStack:update(1 / 60) end
  eq(dones, 1, "and finishes once the box is gone")
  eq(#StateStack.states, 1, "leaving the overworld alone on the stack")
  check(StateStack:top() == ow, "and nothing else came off with it")
end

-- ------------------------------------------------- finish is idempotent

do
  StateStack:init()
  local ow = overworld()
  StateStack:push(ow)
  local dones = 0
  local fade = Transition.new({ stack = StateStack }, nil,
                              function() dones = dones + 1 end, true)
  StateStack:push(fade)
  fade:finish()
  fade:finish()
  eq(dones, 1, "a second finish does not hand back a second time")
  eq(#StateStack.states, 1, "and takes nothing else off the stack")
  check(StateStack:top() == ow, "the overworld survives the second call")
end

-- a mod record may still ask a warp for a fade in; framesIn 0 is truthy in
-- Lua, so the built-in warp keeps its 0 and the retimed one keeps its own
do
  local retimed = { transitions = { warp_fade = { kind = "fade", frames = 32,
                                                  framesIn = 16 } } }
  local fade = Transition.new({ data = retimed, stack = StateStack }, nil,
                              nil, true)
  eq(fade.framesIn, 16, "a retimed warp record keeps its fade in")
  local vanilla = Transition.new({ stack = StateStack }, nil, nil, true)
  eq(vanilla.framesIn, Timing.WARP_FADE_IN, "the built-in warp has none")
end

StateStack:clear()

T.finish("transition_identity_pop_bug1663")
