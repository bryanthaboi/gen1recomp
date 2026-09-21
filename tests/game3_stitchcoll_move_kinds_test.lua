#!/usr/bin/env luajit
-- pokefirered/src/event_object_movement.c:6772 MovementAction_FacePlayer_Step0

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
  print("[skip] game3_stitchcoll_move_kinds_test: " .. tostring(Cache.reason))
  done()
end

local Dataset = require("src.core.game3.dataset")
local MapCatalog = require("src.import.gba.map_catalog")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")

local MAP = MapCatalog.pretToEngine("PalletTown")
local PX, PY = 12, 20

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = MAP, flags = {}, vars = {}, party = {} }
game.session = session

local def = game.data.maps[MAP]
check(def ~= nil, tostring(MAP) .. " is in the cache")
if not def then done() end

Field._game = game
Field._session = session
Field.running = true
Field.locked = false
Space.activate(nil, MAP, game, nil)
Collision.bindMap(game, MAP, def)
Objects.loadMap(game, MAP, def)
Player.reset(PX, PY, "down")

local eo, lid
for i = 1, 16 do
  local o = Objects.find(i)
  if o and o.cellX and not Objects.isPlayer(i) then eo, lid = o, i break end
end
check(eo ~= nil, "Pallet Town has an object to drive")
if not eo then done() end

local function run(bytes, maxFrames)
  Objects.clearMovements()
  eo.moving = false
  local finished = false
  Objects.applyMovement(lid, bytes, function() finished = true end)
  local frames = 0
  while not finished and frames < (maxFrames or 300) do
    Objects.update(game)
    frames = frames + 1
  end
  return frames, finished
end

local function place(x, y, facing)
  Objects.setObjectXY(lid, x, y)
  eo.facingLocked = false
  eo.inanimate = false
  eo.facing = facing
end

print("[test] 1. face_player (0x4A) turns the object toward the player")
place(PX + 1, PY, "down")
local _, finished = run({ 0x4A, 0xFE })
check(finished, "the face_player stream finished")
eq(eo.facing, "left", "an object east of the player faces west")
place(PX - 1, PY, "down")
run({ 0x4A, 0xFE })
eq(eo.facing, "right", "an object west of the player faces east")
place(PX, PY + 1, "left")
run({ 0x4A, 0xFE })
eq(eo.facing, "up", "an object south of the player, same column, faces north")
place(PX, PY - 1, "left")
run({ 0x4A, 0xFE })
eq(eo.facing, "down", "an object north of the player, same column, faces south")

print("[test] 2. GetDirectionToFace is x first, not the largest delta")
-- pokefirered/src/event_object_movement.c:4789 GetDirectionToFace
place(PX + 1, PY - 9, "down")
run({ 0x4A, 0xFE })
eq(eo.facing, "left", "one cell east and nine cells north still faces west")
place(PX - 1, PY + 9, "down")
run({ 0x4A, 0xFE })
eq(eo.facing, "right", "one cell west and nine cells south still faces east")

print("[test] 3. face_away_player (0x4B) takes the opposite direction")
-- pokefirered/src/event_object_movement.c:6784 MovementAction_FaceAwayPlayer_Step0
place(PX + 1, PY, "down")
run({ 0x4B, 0xFE })
eq(eo.facing, "right", "an object east of the player faces further east")
place(PX, PY - 1, "left")
run({ 0x4B, 0xFE })
eq(eo.facing, "up", "an object north of the player faces further north")

print("[test] 4. lock_facing (0x4C / 0x4D) walks the object without turning it")
place(PX + 4, PY, "down")
local startX = eo.cellX
run({ 0x4C, 0x12, 0xFE }, 120)
eq(eo.facing, "down", "the locked object still faces the way it started")
eq(eo.cellX, startX - 1, "and it still moved one cell west")
check(eo.facingLocked == true, "the lock is still on after the stream")
run({ 0x4D, 0x12, 0xFE }, 120)
eq(eo.facingLocked, false, "0x4D unlocks it")
eq(eo.facing, "left", "and the next walk turns it again")

print("[test] 5. disable / restore animation (0x5E / 0x5F)")
place(PX + 4, PY, "down")
Objects.clearMovements()
local fin = false
Objects.applyMovement(lid, { 0x5E, 0x12, 0x5F, 0x12, 0xFE }, function() fin = true end)
local phaseWhileOff, phaseWhileOn = 0, 0
local walks, wasMoving, disabledDuringFirstWalk = 0, false, false
for _ = 1, 200 do
  if fin then break end
  Objects.update(game)
  if eo.moving and not wasMoving then walks = walks + 1 end
  wasMoving = eo.moving and true or false
  if eo.moving then
    local p = Objects.walkPhase(eo)
    if walks == 1 then
      if eo.inanimate then disabledDuringFirstWalk = true end
      if p == 1 then phaseWhileOff = phaseWhileOff + 1 end
    elseif walks == 2 and p == 1 then
      phaseWhileOn = phaseWhileOn + 1
    end
  end
end
check(fin, "the animation stream finished")
eq(walks, 2, "the stream walked twice")
check(disabledDuringFirstWalk, "0x5E marks the object inanimate for the first walk")
eq(phaseWhileOff, 0, "the walk frame never advances while the animation is disabled")
check(phaseWhileOn > 0,
  "and it advances again once restored (" .. phaseWhileOn .. " frames on phase 1)")
eq(eo.inanimate, false, "0x5F restores the object's own animation")

print("[test] 6. remove_obstacle (0x68 / 0x69) burns its animation frames")
-- pokefirered/src/event_object_movement.c:7135 MovementAction_RockSmashBreak_Step0
place(PX + 4, PY, "down")
local smashFrames = run({ 0x68, 0xFE }, 300)
eq(smashFrames, 64, "rock_smash_break holds the track for its 64 frames")
-- pokefirered/src/event_object_movement.c:7163 MovementAction_CutTree_Step0
local cutFrames = run({ 0x69, 0xFE }, 300)
eq(cutFrames, 56, "cut_tree holds the track for its 56 frames")

done()
