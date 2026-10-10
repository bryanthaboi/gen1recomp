package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity Yellow Pikachu under player")
local check, eq = S.check, S.eq
local Data = require("src.core.Data")
Data:load()
local NPC = require("src.world.NPC")
local Follower = require("src.world.PikachuFollower")

local spriteDef = Data.sprites and (Data.sprites.SPRITE_PIKACHU or Data.sprites.SPRITE_RED)
if not spriteDef then
  for _, def in pairs(Data.sprites or {}) do spriteDef = def break end
end
if not spriteDef then
  print("[skip] parity Yellow Pikachu under player: no sprite table")
  S.finish()
  return
end

local game = { data = { sprites = { SPRITE_PIKACHU = spriteDef }, field = {} },
               save = { party = {} } }
local walkable = function() return true end
local ow = {
  map = { id = "ROUTE_1", inBounds = walkable, isWalkableCell = walkable },
  player = { cellX = 5, cellY = 9, facing = "down" },
  npcs = {}, entities = {},
}

local restore = Follower.setShouldSpawn(function() return true end)
local draws = 0
local realDraw = NPC.draw
NPC.draw = function() draws = draws + 1 end

Follower.onMapEntered(game, ow, nil, true)
local pika = Follower.current(ow)
check(pika, "a map load spawns the follower")
eq(pika and pika.cellX, 5, "spawn state 0 puts Pikachu on the player's column")
eq(pika and pika.cellY, 9, "spawn state 0 puts Pikachu on the player's row")
check(pika and Follower.underPlayer(ow, pika), "the follower counts as under the player")
pika:draw(0, 0)
eq(draws, 0, "Pikachu on the player's cell draws nothing before the first step")

ow.player.targetX, ow.player.targetY = 5, 10
pika:draw(0, 0)
eq(draws, 1, "once the player commits a step off the cell Pikachu is drawn")
ow.player.cellX, ow.player.cellY = 5, 10
ow.player.targetX, ow.player.targetY = nil, nil
pika:draw(0, 0)
eq(draws, 2, "and stays drawn one cell behind")

Follower.onMapEntered(game, ow, { pikachuSpawn = 1 }, true)
pika = Follower.current(ow)
check(pika and not Follower.underPlayer(ow, pika), "a warp spawn beside the player is not hidden")
pika:draw(0, 0)
eq(draws, 3, "and draws")

NPC.draw = realDraw
Follower.setShouldSpawn(restore)
S.finish()
