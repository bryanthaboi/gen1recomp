-- ../pokecrystal/engine/overworld/scripting.asm:2224
-- ../pokecrystal/engine/overworld/scripting.asm:528
-- ../pokecrystal/engine/overworld/scripting.asm:371
-- ../pokecrystal/engine/overworld/scripting.asm:374
-- ../pokecrystal/engine/overworld/scripting.asm:2208
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 stayed text hooks")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local Vm = require("src.script.gen2.Vm")
local World = require("src.world.gen2.World")
local PHONE = require("tests.fixtures.gen2_phone_events")
PHONE.install()

love.filesystem.write("data/generated/maps.lua", [[
return {
  PLAYERS_HOUSE_2F = { id = "PLAYERS_HOUSE_2F", group = 1, map = 1, width = 2,
    height = 2, blocks = { 1, 2, 3, 4 }, objects = {}, warps = {},
    tileset = "TEST" },
  TEST_MAP = { id = "TEST_MAP", group = 1, map = 2, width = 2, height = 2,
    blocks = { 1, 2, 3, 4 }, objects = {}, warps = {}, tileset = "TEST" },
}
]])
love.filesystem.write("data/generated/tilesets.lua", "return { TEST = {} }")
love.filesystem.write("data/generated/landmarks.lua", [[
return { spawns = { SPAWN_NEW_BARK = { map = "TEST_MAP", x = 1, y = 1 } } }
]])
love.filesystem.write("data/generated/marts.lua",
  "return { lists = {}, bargain = {} }")
love.filesystem.write("data/generated/initial_events.lua",
  "return { flags = {}, engineFlags = {}, sprites = {} }")
love.filesystem.write("data/generated/menu_gfx.lua", [[
return { emotes = { grassRustle = "r.png", jumpShadow = "j.png",
  cutGrass = "c.png", fishing = "f.png" },
  healMachine = { sheet = "h.png", palette = { 0, 0, 0, 0 } } }
]])

local top
local stack = {
  top = function() return top end,
  push = function(_, state) top = state end,
  pop = function() top = nil end,
}
local world = World.new({ data = { gen2EventTables = PHONE.events,
      gen2Constants = { engineFlagOrder = require("tests.fixture_data.gen2_engine_flags").order("gold") } }, save = { party = {}, inventory = {} },
  stack = stack })
world.setMap = function(_self, mapId)
  world.map = { id = mapId }
  return true
end
check(world:load(), "World:load builds the VM (" .. tostring(world.status) .. ")")
local vm = world.vm
check(vm and vm:canHoldStayed(), "the World wires hasStayedText and holdStayedText")

local function standingBox()
  local box = {}
  world.stayedTextBox = box
  top = box
  return box
end

do
  local box = standingBox()
  vm:start({ { op = "pause", frames = 45 }, { op = "end" } })
  eq(box.holdFrames, Vm.pauseLength(45),
    "writetext / pause 45: the World hook wrapper hands the frame count to World:holdStayedText")
  check(type(box.stay) == "table" and type(box.stay.onShown) == "function",
    "the standing box is re-armed with a stay hook")
  check(vm:running(), "the VM parks on the box while it holds")
  box.stay.onShown()
  check(not vm:running(), "and runs on once the box hands back")
  eq(top, nil, "a script that ends with a stayed box closes it")
end

do
  local box = standingBox()
  local resumed = false
  check(vm.holdStayedFn("sfx", function() resumed = true end),
    "holdStayedText(sfx) takes the standing box")
  eq(box.sfxWait, true, "WaitSFX: the box holds its press while the sfx rings")
  box.stay.onShown()
  check(resumed, "and resumes the caller when it is shown")
end

do
  local box = standingBox()
  check(vm.holdStayedFn("button", function() end),
    "holdStayedText(button) takes the standing box")
  eq(box.stay.press, true, "WaitButton: the box waits for A/B")
  check(not box.stay.prompt, "with no PromptButton arrow")
end

do
  local box = standingBox()
  box.waitButton = true
  check(vm.holdStayedFn("prompt", function() end),
    "holdStayedText(prompt) takes the standing box")
  eq(box.stay.prompt, true, "PromptButton: arrowed press")
  eq(box.waitButton, false, "and the arrow is allowed to show")
end

do
  standingBox()
  eq(vm.holdStayedFn("close"), false, "holdStayedText(close) answers false")
  eq(top, nil, "and pops the box")
  eq(world.stayedTextBox, nil, "forgetting it")
end

do
  top = nil
  world.stayedTextBox = nil
  eq(vm.holdStayedFn("frames", function() end, 90), false,
    "with no standing box every hold answers false so the VM falls back")
end

love.filesystem.remove("data/generated/maps.lua")
love.filesystem.remove("data/generated/tilesets.lua")
love.filesystem.remove("data/generated/landmarks.lua")

S.finish()
