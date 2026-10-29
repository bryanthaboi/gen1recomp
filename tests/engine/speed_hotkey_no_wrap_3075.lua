package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local eq = T.eq

local Input = require("src.core.Input")
local GamepadMap = require("src.core.GamepadMap")
local GameSpeed = require("src.core.GameSpeed")
local Game = require("src.core.Game")
local Game2 = require("src.core.Game2")
local Game3 = require("src.core.Game3")

package.loaded["src.core.game3.battle"] = { isActive = function() return false end }

local TOP = GameSpeed.LEVELS[#GameSpeed.LEVELS]

eq(GameSpeed.step(1, -1), 1, "step down at NORMAL stays at NORMAL")
eq(GameSpeed.step(2, -1), 1, "step down from 2X reaches NORMAL")
eq(GameSpeed.step(1, 1), 2, "step up from NORMAL reaches 2X")
eq(GameSpeed.step(TOP, 1), 1, "step up at the top level wraps to NORMAL")
eq(GameSpeed.cycle(1, -1), TOP, "option rows keep the wrapping cycle")

GameSpeed.setAllowed({ 2, 10 })
eq(GameSpeed.step(2, -1), 2, "a narrowed ladder stops at its own bottom")
eq(GameSpeed.step(10, 1), 2, "and wraps up to its own bottom")
GameSpeed.setAllowed(nil)

local function gen1(speed)
  return setmetatable({
    save = { options = { speedOverworld = speed, speedBattle = speed, speedMenu = speed } },
    stack = { states = {}, top = function() return nil end },
    writeOptions = function() end,
  }, { __index = Game })
end

local function gen2(speed)
  return setmetatable({ options = { speed = speed }, persistOptions = function() end },
    { __index = Game2 })
end

local function gen3(speed)
  return setmetatable({
    phase = "field",
    options = { speedOverworld = speed, speedBattle = speed, speedMenu = speed },
    input = Input,
    writeOptions = function() end,
  }, { __index = Game3 })
end

local function run(label)
  Input:init()
  Input:applyBindings(nil)

  local g1 = gen1(1)
  g1:gamepadpressed(nil, "leftshoulder")
  eq(g1.save.options.speedOverworld, 1, label .. "Gen 1 L at NORMAL stays NORMAL")
  g1:gamepadreleased(nil, "leftshoulder")
  g1:gamepadaxis(nil, "triggerleft", 1)
  eq(g1.save.options.speedOverworld, 1, label .. "Gen 1 ZL at NORMAL stays NORMAL")
  g1:gamepadaxis(nil, "triggerleft", 0)
  g1:keypressed("0")
  eq(g1.save.options.speedMenu, 1, label .. "Gen 1 key 0 at NORMAL stays NORMAL")
  g1:gamepadpressed(nil, "rightshoulder")
  eq(g1.save.options.speedOverworld, 2, label .. "Gen 1 R from NORMAL rises to 2X")
  g1:gamepadreleased(nil, "rightshoulder")
  g1.save.options.speedOverworld, g1.save.options.speedMenu = TOP, TOP
  g1:touchSkinHotkey("fast_forward_toggle", true)
  eq(g1.save.options.speedOverworld, 1, label .. "Gen 1 skin fast-forward toggle wraps back to NORMAL")

  local g2 = gen2(1)
  g2:gamepadpressed(nil, "leftshoulder")
  eq(g2.options.speed, 1, label .. "Gen 2 L at NORMAL stays NORMAL")
  g2:gamepadreleased(nil, "leftshoulder")
  g2:gamepadaxis(nil, "triggerleft", 1)
  eq(g2.options.speed, 1, label .. "Gen 2 ZL at NORMAL stays NORMAL")
  g2:gamepadaxis(nil, "triggerleft", 0)
  g2:hotkey("0")
  eq(g2.options.speed, 1, label .. "Gen 2 key 0 at NORMAL stays NORMAL")
  g2:hotkey("1")
  eq(g2.options.speed, 2, label .. "Gen 2 key 1 from NORMAL rises to 2X")
  g2.options.speed = TOP
  g2:hotkey("1")
  eq(g2.options.speed, 1, label .. "Gen 2 key 1 at the top wraps to NORMAL")

  local g3 = gen3(1)
  g3:gamepadaxis(nil, "triggerleft", 1)
  eq(g3.options.speedOverworld, 1, label .. "Gen 3 ZL at NORMAL stays NORMAL")
  g3:gamepadaxis(nil, "triggerleft", 0)
  g3:keypressed("0")
  eq(g3.options.speedOverworld, 1, label .. "Gen 3 key 0 at NORMAL stays NORMAL")
  g3:gamepadaxis(nil, "triggerright", 1)
  eq(g3.options.speedOverworld, 2, label .. "Gen 3 ZR from NORMAL rises to 2X")
  g3:gamepadaxis(nil, "triggerright", 0)
  g3.options.speedOverworld = TOP
  g3:_cycleSpeed(1)
  eq(g3.options.speedOverworld, 1, label .. "Gen 3 speed up at the top wraps to NORMAL")
  Input:reset()
end

run("")
GamepadMap._setForceNXForTests(true)
run("NX: ")
GamepadMap._setForceNXForTests(false)

T.finish()
