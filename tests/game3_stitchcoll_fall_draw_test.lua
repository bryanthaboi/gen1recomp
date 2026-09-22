#!/usr/bin/env luajit
-- pokefirered/src/field_effect.c:1215 FallWarpEffect_4

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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

require("src.core.GameVersion").set("firered")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchcoll_fall_draw_test: " .. tostring(Cache.reason))
  done()
end

local Dataset = require("src.core.game3.dataset")
local MapCatalog = require("src.import.gba.map_catalog")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local FieldEffects = require("src.core.game3.field_effects")
local FieldView = require("src.core.game3.field_view")
local Space = require("src.core.game3.scripting.space")
local Runtime = require("src.core.game3.runtime")
local Warp = require("src.core.game3.warp")
local Task = require("src.core.game3.task")
local Fade = require("src.ui.game3.fade")

local CAVE_1F = MapCatalog.pretToEngine("FourIsland_IcefallCave_1F")
local CAVE_B1F = MapCatalog.pretToEngine("FourIsland_IcefallCave_B1F")
local HOLE_X, HOLE_Y = 8, 14

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = CAVE_1F, flags = {}, vars = {}, party = {} }
game.session = session
Runtime.session = session

local def = game.data.maps[CAVE_1F]
check(def ~= nil, tostring(CAVE_1F) .. " is in the cache")
check(game.data.maps[CAVE_B1F] ~= nil, tostring(CAVE_B1F) .. " is in the cache")
if not (def and game.data.maps[CAVE_B1F]) then done() end

Field._game = game
Field._session = session
Field.running = true
Field.locked = false
Space.activate(nil, CAVE_1F, game, nil)
Collision.bindMap(game, CAVE_1F, def)
Objects.loadMap(game, CAVE_1F, def)
Player.reset(HOLE_X, HOLE_Y, "down")

FieldEffects._anims = {}
FieldView.setCameraPanning(0, 0)
Task.clear()

print("[test] 1. the avatar is drawn above the floor for the whole drop")
check(Warp.startFall(nil, game, CAVE_B1F, HOLE_X, HOLE_Y) == true, "the fall warp starts")

local lowest, offsetFrames, landed = 0, 0, false
for _ = 1, 600 do
  -- pokefirered/src/field_effect.c:1166
  Fade.tick(1 / 60)
  Task.update(1 / 60)
  FieldEffects.step()
  Player.update(game, nil)
  local y2 = Player.spriteYOffset or 0
  if y2 < 0 then
    offsetFrames = offsetFrames + 1
    if y2 < lowest then lowest = y2 end
  end
  if session.map == CAVE_B1F then landed = true end
  if landed and not Warp.isBusy() then break end
end

check(landed, "the player fell through to " .. tostring(CAVE_B1F))
check(lowest < 0,
  "the drop reaches the top of the screen, lowest y2=" .. tostring(lowest))
-- pokefirered/src/field_effect.c:1223
check(offsetFrames >= 8,
  "and it is visible for the whole fall, " .. offsetFrames .. " frames off the floor")
eq(Player.spriteYOffset, 0, "the avatar is back on the floor when the fall ends")
eq(Warp.isBusy(), false, "and the fall sequence gave the player back")

print("[test] 2. an ordinary idle frame still zeroes the offset")
Player.spriteYOffset = -32
Player.update(game, nil)
eq(Player.spriteYOffset, 0, "nothing owns the sprite, so Player.tick clears it")

done()
