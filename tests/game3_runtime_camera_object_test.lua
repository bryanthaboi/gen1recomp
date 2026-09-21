#!/usr/bin/env luajit
-- pokefirered/src/field_specials.c:318

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

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local CameraObject = require("src.core.game3.camera_object")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Movement = require("src.core.game3.scripting.movement")
local FieldView = require("src.core.game3.field_view")

local drawCalls = {}
FieldView.draw = function(_game, canvasW, canvasH, _opts)
  drawCalls[#drawCalls + 1] = {
    w = canvasW,
    h = canvasH,
    panX = FieldView.cameraPanX or 0,
    panY = FieldView.cameraPanY or 0,
  }
end

local CELL = 16
local WALK_UP = Movement.CMD.WALK_UP
local WALK_RIGHT = Movement.CMD.WALK_RIGHT
local STEP_END = Movement.STEP_END

local function loadTestMap(mapId)
  Objects.loadMap(nil, mapId, {
    objects = {
      { localId = 1, index = 1, x = 6, y = 6, graphicsId = 18, sprite = "SPRITE_YOUNGSTER" },
    },
  })
end

local function settle(limit)
  for _ = 1, (limit or 240) do
    Objects.update(nil)
    if Objects.pollMovement(CameraObject.LOCALID) then return true end
  end
  return false
end

print("[test] 1. module shape (the names the specials chain pcalls)")
eq(CameraObject.LOCALID, 127, "LOCALID is pret LOCALID_CAMERA")
check(type(CameraObject.spawn) == "function", "CameraObject.spawn exists")
check(type(CameraObject.remove) == "function", "CameraObject.remove exists")
check(type(CameraObject.offset) == "function", "CameraObject.offset exists")

print("[test] 2. remove without a spawn is a safe no-op")
CameraObject.reset()
loadTestMap("CAMERA_TEST_A")
Player.reset(5, 9, "down")
local okRemove, removed = pcall(CameraObject.remove, nil)
check(okRemove, "remove with no camera object does not error")
eq(removed, false, "remove with no camera object reports nothing removed")
eq(CameraObject.isActive(), false, "still inactive")
local dx0, dy0 = CameraObject.offset()
eq(dx0, 0, "offset x is 0 with no camera object")
eq(dy0, 0, "offset y is 0 with no camera object")

print("[test] 3. spawn detaches the camera at the player's cell")
local eo = CameraObject.spawn(nil)
check(eo ~= nil, "spawn returned an event object")
eq(CameraObject.isActive(), true, "camera object is active")
eq(Objects._byId[127], eo, "registered at localId 127")
eq(Objects.find(127), eo, "Objects.find(127) resolves it")
eq(eo.cellX, 5, "spawned on the player's cell x")
eq(eo.cellY, 9, "spawned on the player's cell y")
eq(eo.visible, false, "invisible, as pret sets objEvent->invisible")
eq(eo.hidden, true, "hidden from the draw list")
local sx, sy = CameraObject.offset()
eq(sx, 0, "camera starts on the player, offset x 0")
eq(sy, 0, "camera starts on the player, offset y 0")
eq(Objects.at(5, 9), nil, "an invisible camera object is not interactable")
eq(Objects.blocks(5, 9, nil), false, "an invisible camera object does not block")
eq(CameraObject.spawn(nil), eo, "a second spawn is idempotent")

print("[test] 4. applymovement on the camera id moves the camera, not the player")
local playerPxBefore, playerPyBefore = Player.px, Player.py
local playerCellBefore = Player.cellX .. "," .. Player.cellY
local doneCalls = 0
Objects.applyMovement(127, { WALK_UP, WALK_UP, WALK_RIGHT, STEP_END }, function()
  doneCalls = doneCalls + 1
end)
eq(Objects.pollMovement(127), false, "the camera pan is pending")
check(settle(600), "the camera pan finished")
eq(doneCalls, 1, "waitmovement's onDone fired once")
eq(Player.px, playerPxBefore, "player px never moved")
eq(Player.py, playerPyBefore, "player py never moved")
eq(Player.cellX .. "," .. Player.cellY, playerCellBefore, "player cell never moved")
eq(eo.cellX, 6, "camera walked one cell right")
eq(eo.cellY, 7, "camera walked two cells up")
local mx, my = CameraObject.offset()
eq(mx, CELL, "camera offset x is one cell right")
eq(my, -2 * CELL, "camera offset y is two cells up")

print("[test] 5. the field-view seam pans the camera, not the canvas")
local W, H = 240, 160
check(FieldView._game3CameraObjectSeam == true, "the spawn installed the field-view seam")
FieldView.setCameraPanning(0, 0)
FieldView.draw(nil, W, H, nil)
local call = drawCalls[#drawCalls]
eq(call.w, W, "the canvas width reaches the view untouched")
eq(call.h, H, "the canvas height reaches the view untouched")
eq(call.panX, mx, "the draw sees the camera offset as a camera pan x")
eq(call.panY, my, "the draw sees the camera offset as a camera pan y")
eq(FieldView.cameraPanX, 0, "the pan is released after the draw, x")
eq(FieldView.cameraPanY, 0, "the pan is released after the draw, y")
FieldView.setCameraPanning(4, 8)
FieldView.draw(nil, W, H, nil)
call = drawCalls[#drawCalls]
eq(call.panX, 4 + mx, "the camera object pan adds to a live camera pan x")
eq(call.panY, 8 + my, "the camera object pan adds to a live camera pan y")
eq(FieldView.cameraPanX, 4, "the live pan survives the draw, x")
eq(FieldView.cameraPanY, 8, "the live pan survives the draw, y")
FieldView.setCameraPanning(0, 0)

print("[test] 6. remove reattaches the camera to the player")
local removed2 = CameraObject.remove(nil)
eq(removed2, true, "remove reports the camera object gone")
eq(CameraObject.isActive(), false, "camera object no longer active")
eq(Objects._byId[127], nil, "unregistered from Objects")
local inOrder = false
for i = 1, #Objects._order do
  if Objects._order[i] == 127 then inOrder = true end
end
eq(inOrder, false, "dropped from the draw order")
local rx, ry = CameraObject.offset()
eq(rx, 0, "camera is back on the player, offset x 0")
eq(ry, 0, "camera is back on the player, offset y 0")
FieldView.draw(nil, W, H, nil)
local passthrough = drawCalls[#drawCalls]
eq(passthrough.panX, 0, "with the camera back the draw pans by nothing, x")
eq(passthrough.panY, 0, "with the camera back the draw pans by nothing, y")
eq(passthrough.w, W, "and the canvas width is still untouched")
eq(Player.px, playerPxBefore, "the player still never moved")
eq(Player.py, playerPyBefore, "the player still never moved")

print("[test] 7. remove finishes a pan that is still running")
CameraObject.spawn(nil)
local lateDone = 0
Objects.applyMovement(127, { WALK_UP, WALK_UP, WALK_UP, STEP_END }, function()
  lateDone = lateDone + 1
end)
Objects.update(nil)
eq(Objects.pollMovement(127), false, "the pan is still running")
CameraObject.remove(nil)
eq(lateDone, 1, "remove released the pending waitmovement")
eq(Objects.pollMovement(127), true, "waitmovement no longer blocks")
eq(CameraObject.isActive(), false, "camera object gone")

print("[test] 8. a map change drops the camera object, as pret's map reload does")
CameraObject.reset()
loadTestMap("CAMERA_TEST_A")
Player.reset(5, 9, "down")
local held = CameraObject.spawn(nil)
eq(CameraObject.isActive(), true, "active before the map change")
loadTestMap("CAMERA_TEST_A")
eq(CameraObject.isActive(), true, "a same-map rebind keeps the camera object")
eq(Objects._byId[127], held, "and re-registers the same object")
loadTestMap("CAMERA_TEST_B")
eq(CameraObject.isActive(), false, "inactive after the map change")
local ax, ay = CameraObject.offset()
eq(ax, 0, "offset x reset after the map change")
eq(ay, 0, "offset y reset after the map change")
eq(CameraObject.remove(nil), false, "remove after the map change is a no-op")

print("[test] 9. Runtime resets the camera object on stop")
local Runtime = require("src.core.game3.runtime")
loadTestMap("CAMERA_TEST_A")
Player.reset(5, 9, "down")
CameraObject.spawn(nil)
eq(CameraObject.isActive(), true, "active before Runtime.stop")
Runtime.active = true
Runtime.stop(nil, nil)
eq(CameraObject.isActive(), false, "Runtime.stop cleared the camera object")
eq(Objects._byId[127], nil, "Runtime.stop unregistered it")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
