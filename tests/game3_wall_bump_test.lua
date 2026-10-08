#!/usr/bin/env luajit
-- pokefirered/src/field_player_avatar.c:884 PlayerNotOnBikeCollide

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

require("src.core.GameVersion").set("firered")

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
_G.love = { graphics = gfx }

local played = {}
package.loaded["src.core.game3.audio"] = {
  install = function() return true end,
  playSe = function(id) played[#played + 1] = id end,
  playSong = function() end,
  playFanfare = function() end,
  stopAll = function() end,
  stopSurfMusic = function() end,
  waitSe = function(_, cb) if cb then cb() end end,
}

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_wall_bump_test: " .. tostring(Cache.reason))
  finish()
end

local Dataset = require("src.core.game3.dataset")
local game = { data = {} }
Dataset.hydrate(game)

local Map = require("src.core.game3.map")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local SE = require("src.core.game3.se_ids")

local mapId = "FR_FIVE_ISLAND_LOST_CAVE_ROOM1"
local def = game.data.maps[mapId]
check(def ~= nil, mapId .. " exists")
pcall(Map.ensureMidLayout, game, mapId, def)
Collision.bindMap(game, mapId, def)
game.currentMap = mapId

local function reset()
  Player.cellX, Player.cellY = 8, 2
  Player.facing = "up"
  Player.moving = false
  Player.turnTimer = 0
  Player.action = nil
  Player.walkInPlace = false
  Player.biking = false
  played = {}
end

reset()
check(Collision.canEnter(game, 8, 1, { fromX = 8, fromY = 2, dir = "up" }) == false,
  "(8,1) is a wall")
local res = Player.tryMove("up", game, false)
check(res == "blocked", "walking into the wall is blocked (got " .. tostring(res) .. ")")
check(played[1] == SE.SE_WALL_HIT, "the bump plays SE_WALL_HIT (got " .. tostring(played[1]) .. ")")
check(Player.walkInPlace == true, "the player walks in place against the wall")
check(Player.action and Player.action.frames == 32,
  "on foot the bump is the 32-frame slow walk in place")

for _ = 1, 31 do Player.tick(game) end
check(Player.action ~= nil, "the bump still holds the player on frame 31")
Player.tick(game)
check(Player.action == nil and Player.walkInPlace == false,
  "the walk in place ends after 32 frames")

reset()
Player.biking = true
Player.tryMove("up", game, true)
check(Player.action and Player.action.frames == 16,
  "on the bike the bump is the 16-frame normal walk in place")
reset()

finish()
