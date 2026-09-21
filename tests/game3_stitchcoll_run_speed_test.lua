#!/usr/bin/env luajit
-- pokefirered/src/event_object_movement.c:9029 UpdateRunSlowAnim

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
  print("[skip] game3_stitchcoll_run_speed_test: " .. tostring(Cache.reason))
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
local START_X, START_Y = 12, 20

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

-- pokefirered/include/constants/event_object_movement.h:104
local function timeStream(bytes)
  Player.reset(START_X, START_Y, "down")
  Objects.clearMovements()
  local finished = false
  Objects.applyMovement(Objects.PLAYER_LOCAL_ID, bytes, function() finished = true end)
  local frames = 0
  while not finished and frames < 600 do
    Objects.update(game)
    Player.update(game, nil)
    frames = frames + 1
  end
  return frames, Player.cellY - START_Y, finished
end

print("[test] 1. walk_down x2 is the 16-frame baseline")
local walkFrames, walkCells, walkDone = timeStream({ 0x10, 0x10, 0xFE })
check(walkDone, "the walk stream finished")
eq(walkCells, 2, "it walked two cells")
eq(walkFrames, 33, "two 16-frame steps plus the track's finish frame")

print("[test] 2. player_run_down x2 runs at 8 frames a cell")
-- pokefirered/src/event_object_movement.c:5333 StartRunningAnim
local runFrames, runCells, runDone = timeStream({ 0x3D, 0x3D, 0xFE })
check(runDone, "the run stream finished")
eq(runCells, 2, "it ran two cells")
eq(runFrames, 17, "two 8-frame steps plus the track's finish frame")
check(runFrames < walkFrames,
  "a run is faster than a walk (" .. runFrames .. " < " .. walkFrames .. ")")

print("[test] 3. player_run_down_slow x2 closes each cell on frame 11")
-- pokefirered/include/constants/event_object_movement.h:153
local slowFrames, slowCells, slowDone = timeStream({ 0x41, 0x41, 0xFE })
check(slowDone, "the slow-run stream finished")
eq(slowCells, 2, "it ran two cells")
eq(slowFrames, 23, "two 11-frame steps plus the track's finish frame")
check(slowFrames > runFrames and slowFrames < walkFrames,
  "run_slow sits between a run and a walk (" .. slowFrames .. ")")

print("[test] 4. an NPC's own run stream uses the same two speeds")
local npc
for lid = 1, 16 do
  local o = Objects.find(lid)
  if o and o.cellX and not Objects.isPlayer(lid) then npc = o; npc._lid = lid; break end
end
check(npc ~= nil, "Pallet Town has an object to move")
if npc then
  local function npcSteps(bytes)
    Objects.clearMovements()
    npc.moving = false
    local finished = false
    Objects.applyMovement(npc._lid, bytes, function() finished = true end)
    local first = nil
    local frames = 0
    while not finished and frames < 600 do
      Objects.update(game)
      frames = frames + 1
      if first == nil and not npc.moving then first = frames end
    end
    return first, finished
  end
  local walkOne = npcSteps({ 0x10, 0xFE })
  local runOne = npcSteps({ 0x3D, 0xFE })
  local slowOne = npcSteps({ 0x41, 0xFE })
  eq(walkOne, 16, "the NPC walk step is 16 frames")
  eq(runOne, 8, "the NPC run step is 8 frames")
  eq(slowOne, 11, "the NPC run_slow step is 11 frames")
end

done()
