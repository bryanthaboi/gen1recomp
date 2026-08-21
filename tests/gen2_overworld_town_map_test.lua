-- OverworldTownMap is the wall-map / bedroom-poster viewer.  It is not a
-- POKeGEAR unlock check and not a hardware peripheral, so leaving it in the
-- Specials stub table made ordinary cartridge interactions do nothing.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen2 overworld town map")
local Pokegear = require("src.ui.gen2.Pokegear")
local Specials = require("src.script.gen2.Specials")

local pressed = {}
local closed = 0
local gear = Pokegear.new({
  save = { engineFlags = {} },
  data = { gen2Landmarks = { landmarks = {} } },
  input = {
    wasPressed = function(_, key) return pressed[key] or false end,
  },
}, {
  viewMap = true,
  onClose = function() closed = closed + 1 end,
})

S.eq(gear.mode, "card", "wall map opens directly in map mode")
S.eq(gear:card().id, "map", "wall map uses the existing cartridge map card")
S.check(not gear.fly, "wall map is not the FLY destination picker")
S.eq(#gear.cards, 1, "wall map does not expose POKeGEAR card navigation")

pressed.a = true
gear:update(0)
S.eq(closed, 0, "A does not close the view-only town map")
pressed.a, pressed.b = nil, true
gear:update(0)
S.eq(closed, 1, "B exits `_TownMap` directly")

S.check(Specials.HANDLERS.OverworldTownMap ~= nil,
  "OverworldTownMap is an implemented special")
S.eq(Specials.STUBS.OverworldTownMap, nil,
  "OverworldTownMap is no longer categorized as unavailable hardware")

local callback
local vm = {
  specials = {
    showTownMap = function(done) callback = done end,
  },
}
function vm:resume(value) return coroutine.resume(self.co, value) end
vm.co = coroutine.create(function()
  Specials.HANDLERS.OverworldTownMap(vm)
end)
local ok, wait = coroutine.resume(vm.co)
S.check(ok and wait and wait.kind == "specialwait",
  "script coroutine blocks while the map is visible")
S.check(type(callback) == "function", "special supplies the screen close callback")
callback()
S.eq(coroutine.status(vm.co), "dead", "closing the map resumes the script")

S.finish()
