package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local player = { cellX = 4, cellY = 4, px = 64, py = 64, facing = "down", stepFrames = 4 }
local session = { map = "a" }
package.loaded["src.core.game3.player"] = player
package.loaded["src.core.game3.field"] = { running = true, getSession = function() return session end }
local F = require("src.world.game3.Follower")
F.update({})
T.eq(F.current(), nil, "vanilla has no follower")
local enabled = true
F.setShouldSpawn(function() return enabled end)
F.update({})
local npc = F.current()
T.eq(npc.cellX, 4, "fresh spawn starts under player")
T.check(npc.passable, "companion never blocks movement")
player.moving, player.targetX, player.targetY = true, 5, 4
F.update({})
T.eq(npc.cellX, 4, "first step leaves follower at vacated cell")
player.cellX, player.px, player.targetX = 5, 80, 6
F.update({})
T.check(npc.moving, "next committed step starts follower")
T.eq(npc.px, 68, "follower interpolates at player speed")
for _ = 1, 3 do F.update({}) end
T.eq(npc.cellX, 5, "follower reaches previous player cell")
T.eq(npc.facing, "right", "follower faces travel direction")
npc.sprite = {}
T.eq(F.actor().renderer, npc.sprite, "draw actor uses mod renderer")
F.setVisible(nil, false)
T.eq(F.actor(), nil, "hidden follower omitted from rendering")
session.map = "b"
player.cellX, player.cellY, player.px, player.py = 1, 2, 16, 32
player.moving = false
F.update({})
T.check(F.current() ~= npc, "map changes discard old trail")
T.eq(F.current().cellX, 1, "warp spawns at new player location")
player.cellX, player.px = 20, 320
F.update({})
T.eq(F.current().cellX, 20, "same-map teleport resets stale trail immediately")
enabled = false
F.update({})
T.eq(F.current(), nil, "removing eligibility removes follower")
T.finish("game3_follower")
