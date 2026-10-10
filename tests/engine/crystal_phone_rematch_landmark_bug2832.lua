-- ../pokecrystal/engine/overworld/scripting.asm:1621
-- ../pokecrystal/engine/phone/scripts/erin.asm:17
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness").suite("Crystal phone rematch landmark #2832")
local World = require("src.world.gen2.World")
local Vm = require("src.script.gen2.Vm")

local order = {}
for i = 0, 0x2d do order[i + 1] = "LANDMARK_FILLER_" .. i end
order[0x10 + 1] = "LANDMARK_GOLDENROD_CITY"
order[0x2d + 1] = "LANDMARK_ROUTE_46"
local landmarks = {
  order = order,
  landmarks = {
    LANDMARK_GOLDENROD_CITY = { index = 0x10, name = "GOLDENROD\nCITY" },
    LANDMARK_ROUTE_46 = { index = 0x2d, name = "ROUTE 46" },
  },
}

local w = setmetatable({
  landmarks = landmarks,
  map = { def = { landmark = "LANDMARK_GOLDENROD_CITY" } },
}, { __index = World })

T.eq(w:landmarkName(), "GOLDENROD\nCITY", "no id still names the player's landmark")
T.eq(w:landmarkName(0x2d), "ROUTE 46", "a landmark id names that landmark, not the player's")
T.eq(w:landmarkName("LANDMARK_ROUTE_46"), "ROUTE 46", "a landmark key resolves too")

local f = io.open("src/world/gen2/World.lua", "r")
local src = f:read("*a")
f:close()
T.check(src:find("getLandmarkName = function%(id%) return self:landmarkName%(id%) end") ~= nil,
  "the VM hook forwards the getlandmarkname id")

local vm = Vm.new({
  ["s:erin"] = {
    { op = "getlandmarkname", args = { 0x2d, 2 } },
    { op = "end" },
  },
}, {}, {}, { getLandmarkName = function(id) return w:landmarkName(id) end })
vm:start("s:erin")
for _ = 1, 10 do vm:update() end
T.eq(vm.stringBuffer, "ROUTE 46", "Erin's call buffers ROUTE 46 while the player is in Goldenrod")

T.finish()
