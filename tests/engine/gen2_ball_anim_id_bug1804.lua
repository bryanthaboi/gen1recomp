-- data/moves/animations.asm:401-403

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local UI = require("src.ui.gen2.BattleState")
local AnimRunner = require("src.battle.gen2.AnimRunner")

local runner = AnimRunner.new({ animId = "ANIM_THROW_POKE_BALL", battleTurn = 0 })
T.eq(runner.animId, "ANIM_THROW_POKE_BALL",
  "the runner exposes the anim id BattleState latches on")
T.eq(runner.env.animId, "ANIM_THROW_POKE_BALL",
  "the object/bg env still sees the same id")

local THROW = { scripts = { ANIM_THROW_POKE_BALL = { { "wait", 30 }, { "ret" } } } }

local function throwRunner()
  return AnimRunner.new({ data = THROW, animId = "ANIM_THROW_POKE_BALL", battleTurn = 0 })
    :start("ANIM_THROW_POKE_BALL")
end

local function runToEnd(s, input)
  local frames = 0
  while s.anim and frames < 5000 do
    s:stepAnim(input)
    frames = frames + 1
  end
  return frames
end

local function newSelf(anim, caught)
  local s = setmetatable({
    anim = anim,
    ballThrow = { caught = caught },
    picHidden = { player = false, enemy = false },
    vanishReveal = {},
  }, { __index = UI })
  s.revealSentOut = function() end
  s.revealVanished = function() end
  return s
end

local mash = { wasPressed = function(_, key) return key == "b" or key == "start" end }

-- engine/battle_anims/anim_commands.asm:100-139
do
  local thrown = throwRunner()
  local s = newSelf(thrown, true)
  s:stepAnim(mash)
  T.eq(s.anim, thrown, "B or START on the first frame leaves a real runner running")
  T.eq(s.picHidden.enemy, false, "the caught mon is still on screen mid-throw")
end

do
  local s = newSelf(throwRunner(), true)
  T.check(runToEnd(s, mash) > 30, "a mashed throw still runs every frame of its script")
  T.eq(s.picHidden.enemy, true, "a catch latches at the end of a real runner")
end

do
  local s = newSelf(throwRunner(), false)
  runToEnd(s, mash)
  T.eq(s.picHidden.enemy, false, "a break-free still does not latch")
end

-- engine/battle_anims/pokeball_wobble.asm:14-20
do
  local s = setmetatable({}, { __index = UI })
  local answer, calls = 0, 0
  while answer == 0 and calls < 300 do
    calls = calls + 1
    answer = s:pokeballWobble()
  end
  T.eq(calls, 4, "a wobble check with no throw state still ends on its fourth call")
  T.eq(answer, 2, "a wobble check with no throw state breaks free")
end

T.finish("gen2 ball anim id bug 1804")
