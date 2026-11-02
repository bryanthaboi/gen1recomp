package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("gen2 script ctx map label")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local Events = require("src.mods.Events")
require("src.core.Logger").warn = function() end
local World = require("src.world.gen2.World")

love.filesystem.write("data/generated/maps.lua", [[
return {
  PLAYERS_HOUSE_2F = { id = "PLAYERS_HOUSE_2F", group = 24, map = 7, width = 2,
    height = 2, blocks = { 1, 2, 3, 4 }, objects = {}, warps = {},
    tileset = "TEST" },
  ELMS_LAB = { id = "ELMS_LAB", group = 24, map = 5, width = 2, height = 2,
    blocks = { 1, 2, 3, 4 }, objects = {}, warps = {}, tileset = "TEST" },
}
]])
love.filesystem.write("data/generated/tilesets.lua", "return { TEST = {} }")
love.filesystem.write("data/generated/landmarks.lua", [[
return { spawns = { SPAWN_NEW_BARK = { map = "ELMS_LAB", x = 1, y = 1 } } }
]])

local saved = { Runtime.events, Runtime.hooks, Runtime.errors }
Runtime.install(Events.new(), Hooks.new(), {})

local world = World.new({ data = {}, save = { party = {}, inventory = {} },
  stack = { top = function() end, push = function() end, pop = function() end } })
world.setMap = function(self, mapId)
  self.map = { id = mapId, def = self.maps[mapId] }
  return true
end
T.check(world:load(), "World:load builds the VM (" .. tostring(world.status) .. ")")
world:setMap("ELMS_LAB")

local seen = {}
Runtime.hooks:wrap("script.command", function(nextFn, ctx, name, args, cmd)
  seen[#seen + 1] = ctx
  return nextFn(ctx, name, args, cmd)
end)
local started
Runtime.events:on("script.started", function(p) started = p.ctx end, 0, "ctx-map")

world.vm:start({ { op = "end" } })

T.check(#seen > 0, "script.command fired")
local ctx = seen[1] or {}
T.eq(ctx.mapId, "ELMS_LAB", "script.command ctx.mapId is the World's map label")
T.eq(ctx.mapGroup, 24, "ctx.mapGroup stays the cart group")
T.eq(ctx.mapNumber, 5, "ctx.mapNumber stays the cart number")
T.eq(started and started.mapId, "ELMS_LAB", "script.started ctx.mapId is the World's map label")

Runtime.events, Runtime.hooks, Runtime.errors = saved[1], saved[2], saved[3]
T.finish()
