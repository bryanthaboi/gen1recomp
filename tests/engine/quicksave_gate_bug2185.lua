package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

local Game = require("src.core.Game")
local Game2 = require("src.core.Game2")

local function gen2(busy)
  return { world = { map = {}, player = {},
    acceptsMenuInput = function() return not busy end } }
end

check(Game2.quickSaveAllowed(gen2(false)) == true,
  "gen 2 quick save is allowed on a resting overworld")
check(Game2.quickSaveAllowed(gen2(true)) == false,
  "and refused while the world is busy with a scene script")
check(Game2.quickSaveAllowed({}) == true,
  "with no world at all (title, intro) it stays allowed")

local function gen1(running, moving, moves, extra)
  local ow = { player = { moving = moving },
    scriptMoves = moves or {},
    runner = { isRunning = function() return running end } }
  for k, v in pairs(extra or {}) do ow[k] = v end
  local states = { ow }
  if extra and extra.top then states[2] = extra.top end
  if extra and extra.title then states = { { screenId = "TitleScreen" } } end
  ow.top, ow.title = nil, nil
  return { overworld = ow, stack = { states = states } }
end

check(Game.quickSaveAllowed(gen1(false, false)) == true,
  "gen 1 quick save is allowed on a resting overworld")
check(Game.quickSaveAllowed(gen1(true, false)) == false,
  "and refused while a ScriptRunner coroutine is live")
check(Game.quickSaveAllowed(gen1(false, false, { {} })) == false,
  "and refused while a scripted move is queued")
check(Game.quickSaveAllowed(gen1(false, true)) == false,
  "and refused mid-step, so the cell it writes is a real one")
check(Game.quickSaveAllowed(gen1(false, false, nil, { transitioning = true })) == false,
  "and refused during a warp fade, so no save lands on the door cell")
check(Game.quickSaveAllowed(gen1(false, false, nil, { engaging = true })) == false,
  "and refused while a trainer is engaging")
check(Game.quickSaveAllowed(gen1(false, false, nil, { emote = {} })) == false,
  "and refused while an emote bubble is up")
check(Game.quickSaveAllowed(gen1(false, false, nil,
    { top = { screenId = "BattleState" } })) == false,
  "and refused while a battle or menu sits on top of the overworld")
check(Game.quickSaveAllowed(gen1(false, false, nil, { title = true })) == true,
  "but allowed at the title screen, where the overworld is not on the stack")
check(Game.quickSaveAllowed({}) == true,
  "with no overworld it stays allowed")

local hotkeyed = { refused = 0 }
local stub = setmetatable({
  world = { map = {}, player = {}, acceptsMenuInput = function() return false end },
  options = {},
  persistOptions = function() end,
  writeSave = function() hotkeyed.refused = hotkeyed.refused + 1 end,
}, { __index = Game2 })
check(stub:hotkey("f1") == true, "F1 is still swallowed rather than leaking to Input")
check(hotkeyed.refused == 0, "but nothing was written mid-cutscene")
