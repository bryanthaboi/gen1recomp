#!/usr/bin/env luajit
-- Tests ladder warp behaviors, arrival facing, and prevention of bump-warp loops.

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

package.loaded["src.core.game3.audio"] = {
  install = function() return true end,
  playSe = function() end,
  playSong = function() end,
  playFanfare = function() end,
  stopAll = function() end,
  stopSurfMusic = function() end,
  waitSe = function(_, cb) if cb then cb() end end,
}

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_ladder_warp_test: " .. tostring(Cache.reason))
  finish()
end

local Dataset = require("src.core.game3.dataset")
local game = { data = {} }
Dataset.hydrate(game)

local Map = require("src.core.game3.map")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local Warp = require("src.core.game3.warp")

local mapId = "FR_FIVE_ISLAND_LOST_CAVE_ROOM1"
local def = game.data.maps[mapId]
check(def ~= nil, "FR_FIVE_ISLAND_LOST_CAVE_ROOM1 exists")

pcall(Map.ensureMidLayout, game, mapId, def)
Collision.bindMap(game, mapId, def)
game.currentMap = mapId

-- Ladder is at (8, 2) with MB_LADDER (0x61)
local beh = Collision.behavior(8, 2)
check(beh == 0x61, "tile (8,2) is MB_LADDER")
check(Collision.isLadder(beh) == true, "tile (8,2) is ladder")
check(Collision.warpAt(8, 2) ~= nil, "tile (8,2) has a warp defined")

-- Wall above ladder is at (8, 1) and is solid tile (coll = 7)
local okUp, whyUp = Collision.canEnter(game, 8, 1, { fromX = 8, fromY = 2, dir = "up" })
check(okUp == false, "(8,1) above ladder is solid wall")

-- 1. Arrival facing on ladder
local arrivalFace = Collision.destArrivalFacing(game, mapId, 8, 2, "up")
check(arrivalFace == "up", "arrival facing on ladder keeps the stored direction (was " .. tostring(arrivalFace) .. ")")
local scriptedFace = Collision.destArrivalFacing(game, mapId, 8, 2, "down")
check(scriptedFace == "down", "a scripted warp onto a ladder faces south after ResetInitialPlayerAvatarState (was " .. tostring(scriptedFace) .. ")")

-- 2. Standing on ladder at (8, 2) facing down
Player.cellX = 8
Player.cellY = 2
Player.facing = "up"
Player.moving = false
Player.turnTimer = 0

-- 3. Bumping solid wall (pressing UP) while on ladder tile MUST NOT warp!
local moveRes, moveWhy = Player.tryMove("up", game, false)
check(moveRes == "blocked",
  "pressing UP into cave wall while on ladder returns blocked (got " .. tostring(moveRes) .. ", why=" .. tostring(moveWhy) .. ")")

-- 4. Stepping DOWN off the ladder into the open cave floor at (8, 3)
Player.facing = "down"
local okDown = Collision.canEnter(game, 8, 3, { fromX = 8, fromY = 2, dir = "down" })
check(okDown == true, "(8,3) below ladder is walkable")

local moveDown = Player.tryMove("down", game, false)
check(moveDown == "step", "pressing DOWN on ladder steps off the ladder (got " .. tostring(moveDown) .. ")")

finish()
