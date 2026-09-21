#!/usr/bin/env luajit
-- pokefirered/src/field_effect.c:1249 FallWarpEffect_5
-- pokefirered/src/field_effect.c:1274 FallWarpEffect_7

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local FieldEffects = require("src.core.game3.field_effects")
local FieldView = require("src.core.game3.field_view")

print("[test] 1. the landing shake is pret's 12 frame camera pan")

FieldEffects._anims = {}
FieldView.setCameraPanning(0, 0)
local shakeDone = 0
FieldEffects.startLandingShake(function() shakeDone = shakeDone + 1 end)
local pans = {}
local doneAt = nil
for i = 1, 20 do
  FieldEffects.step()
  pans[i] = FieldView.cameraPanY
  if shakeDone > 0 and not doneAt then doneAt = i end
end
eq(table.concat(pans, ",", 1, 13), "4,-4,4,-4,2,-2,2,-2,1,-1,1,-1,0",
  "the pan halves every four frames and settles back on zero")
eq(doneAt, 13, "the callback runs on the frame the pan reaches zero")
eq(shakeDone, 1, "and it runs exactly once")

print("[test] 2. the real fall warp shakes the screen before it gives control back")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchcoll_fall_shake_test map checks: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")
local Runtime = require("src.core.game3.runtime")
local Warp = require("src.core.game3.warp")
local Task = require("src.core.game3.task")
local Fade = require("src.ui.game3.fade")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = nil, flags = {}, vars = {} }
game.session = session
Runtime.session = session

local CAVE_1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_1F"
local CAVE_B1F = "FR_FOUR_ISLAND_ICEFALL_CAVE_B1F"
local HOLE_X, HOLE_Y = 8, 14

local def = game.data.maps[CAVE_1F]
check(def ~= nil, CAVE_1F .. " is in the cache")
if not def then finish() end
check(game.data.maps[CAVE_B1F] ~= nil, CAVE_B1F .. " is in the cache")

Field._game = game
session.map = CAVE_1F
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
check(Warp.startFall(nil, game, CAVE_B1F, HOLE_X, HOLE_Y) == true,
  "the fall warp starts")

local landedAt, unlockedAt, panFrames = nil, nil, 0
local wasFalling = false
for frame = 1, 600 do
  Task.update(1 / 60)
  Fade.tick(1 / 60)
  FieldEffects.step()
  if (Player.spriteYOffset or 0) < 0 then wasFalling = true end
  if wasFalling and not landedAt and (Player.spriteYOffset or 0) == 0 then
    landedAt = frame
  end
  if landedAt and (FieldView.cameraPanY or 0) ~= 0 then panFrames = panFrames + 1 end
  if not Warp.isBusy() and not unlockedAt then
    unlockedAt = frame
    break
  end
end

check(landedAt ~= nil, "the player fell and landed")
eq(session.map, CAVE_B1F, "the fall landed on " .. CAVE_B1F)
check(unlockedAt ~= nil, "the fall sequence finished")
if not (landedAt and unlockedAt) then finish() end
eq(panFrames, 12, "the screen shook for 12 frames after the landing")
eq(unlockedAt - landedAt, 12,
  "control comes back 12 frames after the landing, not on the landing frame")
eq(Warp.isBusy(), false, "the warp is no longer busy")
eq(Field.locked, false, "the field is unlocked again")
eq(FieldView.cameraPanY, 0, "the camera pan is back to zero")
eq(#FieldEffects._anims, 0, "no field effect is left running")

finish()
