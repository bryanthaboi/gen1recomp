#!/usr/bin/env luajit
-- pokefirered/src/overworld.c:639 UpdateEscapeWarp

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
  print("[skip] game3_stitchcoll_escape_warp_test: " .. tostring(Cache.reason))
  done()
end

local Dataset = require("src.core.game3.dataset")
local MapCatalog = require("src.import.gba.map_catalog")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Player = require("src.core.game3.player")
local Warp = require("src.core.game3.warp")
local Schema = require("src.core.game3.save_schema_firered")

local TOWN = MapCatalog.pretToEngine("PalletTown")
local HOUSE = MapCatalog.pretToEngine("PalletTown_PlayersHouse_1F")
local HOUSE_2F = MapCatalog.pretToEngine("PalletTown_PlayersHouse_2F")
local FOREST = MapCatalog.pretToEngine("ViridianForest")
local FOREST_GATE = MapCatalog.pretToEngine("Route2_ViridianForest_SouthEntrance")

local game = { data = {} }
Dataset.hydrate(game)
local session = Schema.newGame({ rngSeed = 0x3131 })
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })

local function defOf(id) return id and game.data.maps[id] end
for _, id in ipairs({ TOWN, HOUSE, HOUSE_2F, FOREST, FOREST_GATE }) do
  check(defOf(id) ~= nil, tostring(id) .. " is in the cache")
end
if not (defOf(TOWN) and defOf(HOUSE) and defOf(HOUSE_2F) and defOf(FOREST) and defOf(FOREST_GATE)) then
  done()
end

local function warpTo(def, destId)
  for _, w in ipairs((def and def.warps) or {}) do
    if (w.destMap or w.map) == destId then return w end
  end
  return nil
end

local function goTo(mapId, x, y, facing)
  Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
  Player.reset(x, y, facing or "down")
end

local function walkThrough(fromMap, toMap, facing)
  local w = warpTo(defOf(fromMap), toMap)
  if not w then return nil end
  goTo(fromMap, tonumber(w.x), tonumber(w.y), facing)
  Warp.request(nil, game, toMap, 1, 1, "down", {
    fade = false, se = false, doorX = tonumber(w.x), doorY = tonumber(w.y),
  })
  return w
end

print("[test] 1. walking off a town into a house records the doorstep")
-- pokefirered/src/overworld.c:647 SetEscapeWarp
session.escapeWarp = nil
local door = walkThrough(TOWN, HOUSE, "up")
check(door ~= nil, "Pallet Town has a warp into the player's house")
if not door then done() end
local esc = session.escapeWarp
check(type(esc) == "table", "the warp wrote an escape warp")
if type(esc) ~= "table" then done() end
eq(esc.map, TOWN, "it points back at the outdoor map")
eq(esc.x, tonumber(door.x), "at the door's own column")
-- pokefirered/src/overworld.c:646 delta = GetPlayerFacingDirection() != DIR_SOUTH
eq(esc.y, tonumber(door.y) + 1, "one row below the door, because the player walked north")
eq(esc.warpId, 255, "with WARP_ID_NONE, so the coords decide")

print("[test] 2. an indoor to indoor warp leaves it alone")
local kept = { map = esc.map, x = esc.x, y = esc.y }
local up = walkThrough(HOUSE, HOUSE_2F, "up")
check(up ~= nil, "the house has stairs to 2F")
eq(session.escapeWarp.map, kept.map, "the escape warp still names the town")
eq(session.escapeWarp.x, kept.x, "same column")
eq(session.escapeWarp.y, kept.y, "same row")

print("[test] 3. Viridian Forest is the map pret excludes by hand")
-- pokefirered/src/overworld.c:644 MAP_VIRIDIAN_FOREST
local gate = walkThrough(FOREST, FOREST_GATE, "down")
check(gate ~= nil, "the forest has a warp into the south entrance")
eq(session.escapeWarp.map, kept.map, "the forest did not overwrite the escape warp")
eq(session.escapeWarp.y, kept.y, "not even the row")

print("[test] 4. a warp tile stepped onto while walking south keeps that tile")
session.escapeWarp = nil
local lab = walkThrough(TOWN, MapCatalog.pretToEngine("PalletTown_ProfessorOaksLab"), "down")
check(lab ~= nil, "Pallet Town has a warp into Oak's lab")
if lab then
  eq(session.escapeWarp.y, tonumber(lab.y), "delta is 0 for DIR_SOUTH")
  eq(session.escapeWarp.x, tonumber(lab.x), "and the column is the warp tile's own")
end

print("[test] 5. a warp with no warp event behind it leaves the slot alone")
-- pokefirered/src/field_control_avatar.c:965 SetupWarp
local before = session.escapeWarp
goTo(TOWN, 5, 5, "up")
Warp.request(nil, game, HOUSE, 1, 1, "down", { fade = false, se = false })
eq(session.escapeWarp, before, "a scripted warp is not a warp event")

print("[test] 6. walking up into a real door records the tile below it")
-- pokefirered/src/field_control_avatar.c:987 TryDoorWarp
session.escapeWarp = nil
local Task = require("src.core.game3.task")
local Fade = require("src.ui.game3.fade")
local doorWarp = warpTo(defOf(TOWN), HOUSE)
goTo(TOWN, tonumber(doorWarp.x), tonumber(doorWarp.y) + 1, "up")
check(Warp.startDoorEntrance(nil, game, HOUSE, 1, 1,
  tonumber(doorWarp.x), tonumber(doorWarp.y)) ~= false, "the door sequence starts")
local Doors = require("src.core.game3.doors")
for _ = 1, 900 do
  Task.update(1 / 60)
  Doors.update(1 / 60)
  Player.tick(game)
  Fade.tick(1 / 60)
  if not Warp.isBusy() then break end
end
eq(session.map, HOUSE, "the door sequence finished inside the house")
eq((session.escapeWarp or {}).map, TOWN, "and the escape warp names the town")
eq((session.escapeWarp or {}).y, tonumber(doorWarp.y) + 1, "on the doorstep the player left")

print("[test] 7. the recorded warp rides the save")
local save = Schema.toSaveTable(session)
eq((save.escapeWarp or {}).map, TOWN, "toSaveTable carries it")
eq(Schema.fromSaveTable(save).escapeWarp.y, session.escapeWarp.y, "and it comes back whole")

done()
