package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local FixedStep = require("src.core.FixedStep")
local GameSpeed = require("src.core.GameSpeed")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")
local Game = require("src.core.Game")
local Game2 = require("src.core.Game2")
local Game3 = require("src.core.Game3")

local function stack(...) return { states = { ... } } end
local unpack = table.unpack or unpack

local battle = { isBattle = true }
local overworld = { isOverworld = true }

local function gen1(states, opts)
  return setmetatable({
    save = { options = opts or { speedOverworld = 200, speedBattle = 200, speedMenu = 200 } },
    stack = stack(unpack(states)),
    writeOptions = function() end,
  }, { __index = Game })
end

do
  local g = gen1({ overworld })
  eq(g:logicSpeed(), 200, "gen1 overworld runs the saved 200X")
  check(not g:speedLocked(), "gen1 overworld is not locked")
  g = gen1({ overworld, battle })
  eq(g:logicSpeed(), 200, "gen1 local battle runs BATTLE SPEED")
  g.linkSession = true
  eq(g:logicSpeed(), 1, "gen1 link battle is 1X at speedBattle 200")
  g.speedOverride = 200
  eq(g:logicSpeed(), 1, "gen1 link battle ignores speedOverride (--speed, skin FF hold)")
  local bus = Hooks.new()
  local saved = Runtime.hooks
  Runtime.hooks = bus
  local ran = false
  local unsub = bus:wrap("core.logic_speed", function() ran = true; return 200 end)
  g.speedOverride = nil
  eq(g:logicSpeed(), 1, "gen1 link battle ignores a core.logic_speed hook returning 200")
  check(not ran, "the hook is never called while locked")
  local ow = gen1({ overworld })
  eq(ow:logicSpeed(), 200, "outside battle the hook still runs")
  check(ran, "...and was called")
  unsub()
  Runtime.hooks = saved
end

do
  GameSpeed.setAllowed({ 2, 4 })
  local g = gen1({ overworld, battle })
  g.linkSession = true
  eq(g:logicSpeed(), 1, "a cart ladder without 1 still locks to a literal 1")
  eq(gen1({ overworld }, { speedOverworld = 4 }):logicSpeed(), 4,
    "and outside battle the ladder applies")
  GameSpeed.setAllowed(nil)
end

do
  local g = gen1({ overworld, battle },
    { speedOverworld = 1, speedBattle = 1, speedMenu = 1 })
  g.linkSession = true
  g:_cycleSpeed(1)
  g:_cycleSpeed(-1)
  g:_cycleSpeed(1)
  eq(g.save.options.speedBattle, 1, "gen1 speed presses in a link battle leave speedBattle")
  eq(g.save.options.speedOverworld, 1, "and speedOverworld")
  g:touchSkinHotkey("fast_forward_toggle", true)
  eq(g.save.options.speedBattle, 1, "gen1 skin FF toggle in a link battle is ignored")
  g:touchSkinHotkey("fast_forward_hold", true)
  eq(g:logicSpeed(), 1, "gen1 skin FF hold in a link battle stays 1X")
  g:touchSkinHotkey("fast_forward_hold", false)
  eq(g.speedOverride, nil, "and releasing restores the pre-hold override")
  g.linkSession = nil
  g:_cycleSpeed(1)
  eq(g.save.options.speedBattle, 2, "gen1 speed press in a local battle cycles speedBattle")
end

do
  local g = gen1({ overworld })
  g.linkSession = true
  eq(g:logicSpeed(), 1, "gen1 link session is 1X")
  g.linkSession = nil
  g.linkNet = { closed = false }
  eq(g:logicSpeed(), 1, "gen1 open linkNet (arena, tournament, spectate) is 1X")
end

local function gen2(fields)
  fields.persistOptions = fields.persistOptions or function() end
  return setmetatable(fields, { __index = Game2 })
end

do
  eq(gen2({ options = { speed = 200 }, stack = stack({}) }):logicSpeed(), 200,
    "gen2 overworld runs GAME SPEED")
  eq(gen2({ options = { speed = 200 }, stack = stack({}, battle) }):logicSpeed(), 200,
    "gen2 local battle runs GAME SPEED")
  eq(gen2({ options = { speed = 200 }, speedOverride = 200, linkNet = { closed = false },
            stack = stack({}, battle) }):logicSpeed(), 1,
    "gen2 link battle ignores speedOverride")
  eq(gen2({ options = { speed = 200 }, linkNet = { closed = false } }):logicSpeed(), 1,
    "gen2 online arena / LinkBattle2 linkNet is 1X")
  eq(gen2({ options = { speed = 200 }, linkSession = true }):logicSpeed(), 1,
    "gen2 tournament / spectate linkSession is 1X")
  local g = gen2({ options = { speed = 1 }, stack = stack({}, battle) })
  g:_cycleSpeed(1)
  eq(g.options.speed, 2, "gen2 pad speed press in a local battle cycles")
  g.stack = stack({})
  g.linkNet = { closed = false }
  g:_cycleSpeed(1)
  eq(g.options.speed, 2, "gen2 pad speed press over a link is ignored")
end

local battleActive, battleLink = false, false
package.loaded["src.core.game3.battle"] = {
  isActive = function() return battleActive end,
  getState = function() return { link = battleLink } end,
}

local function gen3()
  return setmetatable({
    phase = "field",
    options = { speedOverworld = 200, speedBattle = 200, speedMenu = 200 },
    writeOptions = function() end,
  }, { __index = Game3 })
end

do
  local g = gen3()
  eq(g:logicSpeed(), 200, "gen3 field runs OVERWORLD SPEED")
  battleActive = true
  eq(g:logicSpeed(), 200, "gen3 local battle runs BATTLE SPEED")
  battleLink = true
  eq(g:logicSpeed(), 1, "gen3 link battle is 1X")
  g.speedOverride = 200
  eq(g:logicSpeed(), 1, "gen3 link battle ignores speedOverride")
  g.speedOverride = nil
  g:_cycleSpeed(1)
  eq(g.options.speedBattle, 200, "gen3 speed press in a link battle is ignored")
  battleActive, battleLink = false, false
  package.loaded["src.core.game3.link.union_room"] = { isActive = function() return true end }
  eq(g:logicSpeed(), 1, "gen3 Union Room is 1X")
  package.loaded["src.core.game3.link.union_room"] = nil
  package.loaded["src.core.game3.map"] = { current = "FR_UNION_ROOM" }
  eq(g:logicSpeed(), 1, "gen3 Union Room map is 1X")
  package.loaded["src.core.game3.map"] = nil
  eq(g:logicSpeed(), 200, "and the field is back to 200X")
end

local function runFrame(g, lockAt)
  local steps = 0
  local savedInit = { accum = FixedStep.accum, callback = FixedStep.callback }
  FixedStep.clock = function() return 0 end
  FixedStep:init(function()
    steps = steps + 1
    if steps == lockAt then
      battleActive, battleLink = true, true
      g.linkSession = true
      g.stack = stack(overworld, battle)
    end
    g:_speedLockEdge()
  end)
  local speed = g:logicSpeed()
  g._frameSpeed = speed
  FixedStep.maxAccum = FixedStep.catchupLimit(speed, FixedStep.STEP)
  FixedStep:update(FixedStep.STEP, speed)
  FixedStep.clock = nil
  FixedStep.accum, FixedStep.callback = savedInit.accum, savedInit.callback
  return steps, speed
end

do
  battleActive = false
  local g = gen3()
  local steps, speed = runFrame(g, 3)
  eq(speed, 200, "the frame started unlocked at 200X")
  eq(steps, 3, "gen3: a link battle starting mid-frame ends the frame on that step")
  battleActive, battleLink = false, false

  local g1 = gen1({ overworld })
  steps = runFrame(g1, 5)
  eq(steps, 5, "gen1: a link battle push mid-frame ends the frame on that step")
  eq(g1:logicSpeed(), 1, "and the next frame samples 1X")

  local g2 = gen2({ options = { speed = 200 }, stack = stack({}) })
  steps = runFrame(g2, 2)
  eq(steps, 2, "gen2: a link battle push mid-frame ends the frame on that step")
  battleActive, battleLink = false, false

  local plain = gen1({ overworld })
  steps = runFrame(plain, -1)
  check(steps > 100, "without a lock flip the 200X frame runs its steps")
end

package.loaded["src.core.game3.battle"] = nil

T.finish("speed lock")
