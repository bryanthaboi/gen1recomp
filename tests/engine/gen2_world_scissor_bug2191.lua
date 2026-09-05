package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local World = require("src.world.gen2.World")

local G = love.graphics
local realGet, realSet = G.getScissor, G.setScissor

local function runBlit(outer)
  local set = {}
  G.getScissor = function()
    if not outer then return nil end
    return outer[1], outer[2], outer[3], outer[4]
  end
  G.setScissor = function(x, y, w, h) set[#set + 1] = { x, y, w, h } end
  local stub = setmetatable({
    map = { id = 1, def = {} },
    atlasFor = function() return nil, nil end,
    mapCacheKey = function() return "k" end,
    bgSets = {},
  }, { __index = World })
  local ok, err = pcall(World.blitBgOverRegion, stub, stub.map.def,
    0, 0, 1, 0, 0, 16, 16, false, function() return true end)
  G.getScissor, G.setScissor = realGet, realSet
  return ok, err, set
end

local ok, err, set = runBlit({ 4, 6, 100, 80 })
check(ok, "blitBgOverRegion survives an active scissor: " .. tostring(err))
eq(#set, 2, "clip set then restored")
eq(set[1][1], 4, "clip intersects the outer scissor")
eq(set[1][2], 6, "clip intersects the outer scissor vertically")
eq(set[1][3], 12, "clip width is the intersection")
eq(set[2][1], 4, "restore splats four numbers")
eq(set[2][3], 100, "restore keeps the outer width")

local ok2, err2, set2 = runBlit({ 1000, 1000, 4, 4 })
check(ok2, "empty intersection does not error: " .. tostring(err2))
eq(#set2, 0, "empty intersection skips the blit entirely")

local ok3, err3, set3 = runBlit(nil)
check(ok3, "no outer scissor still blits: " .. tostring(err3))
eq(#set3, 2, "region clip set then cleared")
eq(set3[2][1], nil, "restore with no outer scissor clears it")
