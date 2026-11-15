package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("world.block_replaced fires once per write")
local check, eq = S.check, S.eq

local Runtime = require("src.mods.Runtime")
local emits = {}
local realEmit, realWants = Runtime.emit, Runtime.wants
Runtime.emit = function(name, payload, ...)
  if name == "world.block_replaced" then emits[#emits + 1] = payload end
  return realEmit(name, payload, ...)
end
Runtime.wants = function(name)
  if name == "world.block_replaced" then return true end
  return realWants(name)
end

local function count(fn)
  emits = {}
  local ok, a = pcall(fn)
  return #emits, ok, a
end

local PAIR = "probe_pair"
require("src.core.game3.scripting.interaction_scripts").behaviors = { [PAIR] = { [0] = 0, [5] = 0x02 } }

local MAP = "FR_PROBE"
local layout = { width = 4, height = 4, pair = PAIR, midAt = function() return 0 end }
function layout:applyOverride(x, y, mid, coll) self.last = { x = x, y = y, mid = mid, coll = coll } end
function layout:elevAt() return 0 end
local def = { id = MAP, width = 4, height = 4, pair = PAIR, midLayout = layout, warps = {}, objects = {} }
local session = { map = MAP, x = 1, y = 1, facing = "down", party = {}, flags = {}, vars = {} }
local game3 = { data = { maps = { [MAP] = def } }, session = session, phase = "field" }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  uiBusy = function() return false end,
}
local MapStub = { current = MAP }
function MapStub.currentDef() return def end
package.loaded["src.core.game3.map"] = MapStub
package.loaded["src.core.game3.player"] = { cellX = 1, cellY = 1, facing = "down", moving = false }

local Field = require("src.core.game3.field")
Field.running, Field._game, Field._session, Field._locks = true, game3, session, {}
Field.metatileOverrides = {}
local Collision = require("src.core.game3.collision")
local realPatchCell = Collision.patchCell
Collision.patchCell = function() return true end

local Gen3Compat = require("src.mods.Gen3Compat")
Gen3Compat.bind(function() return game3 end)
local api3 = require("src.world.game3.WorldAPI").new(game3, "probe")
local OW3 = Gen3Compat.resolve("src.world.OverworldController", "probe")
local world3 = require("src.mods.UnifiedWorld").new(function() return game3 end, 3, "firered", "probe")

local n, ok = count(function() return Field.setMetatile(1, 1, 5) end)
eq(n, 1, "gen3 script setmetatile emits once")
check(ok, "gen3 script setmetatile runs")
eq(emits[1] and emits[1].mapId, MAP, "the emit carries the session map")
eq(emits[1] and emits[1].block, 5, "the emit carries the metatile")
n, ok = count(function() return api3:replaceBlock(1, 1, 5) end)
eq(n, 1, "gen3 WorldAPI:replaceBlock emits once")
check(ok, "gen3 WorldAPI:replaceBlock runs")
n, ok = count(function() return OW3.replaceBlock(1, 1, 5) end)
eq(n, 1, "gen3 OverworldState.replaceBlock emits once")
check(ok, "gen3 OverworldState.replaceBlock runs")
n, ok = count(function() return world3:replaceBlock(1, 1, 5) end)
eq(n, 1, "gen3 mod.world:replaceBlock emits once")
check(ok, "gen3 mod.world:replaceBlock runs")
n = count(function() return api3:replaceBlock(1, 1, 7) end)
eq(n, 0, "gen3 a refused replaceBlock emits nothing")

n = count(function() return Field.setMetatile(2, 2, 5 + 0x400, false) end)
eq(n, 1, "a collision-bit write emits once")
eq(layout.last and layout.last.mid, 5, "setMetatile keeps only the low 10 bits of the metatile")
eq(layout.last and layout.last.coll, 0x07, "a collision bit in the metatile makes the cell impassable")
eq(emits[1] and emits[1].block, 5, "the emit carries the masked metatile")
Field.setMetatile(2, 2, 5 + 0x1000, false)
eq(layout.last and layout.last.coll ~= 0x07, true, "elevation bits are not collision")

layout.last = nil
Field.metatileOverrides = {}
local okLand, landErr
n, okLand, landErr = count(function() return Field.setMetatile(3, 3, 7) end)
check(not okLand and tostring(landErr):find("metatile 7", 1, true) ~= nil,
  "a passable write of an undefined metatile raises: " .. tostring(landErr))
eq(n, 0, "the refused write emits nothing")
eq(layout.last, nil, "the refused write never reaches the layout")
eq(Field.metatileOverrideAt(MAP, 3, 3), nil, "the refused write leaves no override")
Collision.patchCell = realPatchCell

local World2 = require("src.world.gen2.World")
local world2 = setmetatable({
  map = { id = "M", width = 2, height = 2, def = { blocks = { 1, 2, 3, 4 } } },
  blockEdits = {}, refreshMapImages = function() end,
}, { __index = World2 })
local game2 = { world = world2, phase = "overworld" }
local Gen2Compat = require("src.mods.Gen2Compat")
Gen2Compat.bind(function() return game2 end)
local OW2 = Gen2Compat.resolve("src.world.OverworldController", "probe")
local api2 = require("src.world.gen2.WorldAPI").new(game2, "probe")

local ret
n, ok, ret = count(function() return OW2.replaceBlock(1, 0, 9) end)
eq(n, 1, "gen2 OverworldState.replaceBlock emits once")
eq(ok and ret, true, "gen2 OverworldState.replaceBlock answers true")
eq(emits[1] and emits[1].bx, 1, "gen2 emit carries bx")
eq(emits[1] and emits[1].block, 9, "gen2 emit carries the block")
eq(world2.map.def.blocks[2], 9, "gen2 facade wrote the block")
n, ok, ret = count(function() return OW2.replaceBlock(5, 5, 9) end)
eq(n, 0, "gen2 an out-of-bounds facade write emits nothing")
eq(ok and ret, false, "gen2 an out-of-bounds facade write answers false")
n = count(function() return api2:replaceBlock(0, 1, 8) end)
eq(n, 1, "gen2 WorldAPI:replaceBlock emits once")

Runtime.emit, Runtime.wants = realEmit, realWants
S.finish()
