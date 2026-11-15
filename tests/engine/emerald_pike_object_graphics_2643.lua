package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Pike spawned object graphics #2643")
local Cache = require("tests.game3_cache")
local root = Cache.root("emerald")
if not root then print("[skip] #2643 Pike: " .. tostring(Cache.reason)); T.finish(); return end
require("src.core.GameVersion").set("emerald")
require("src.import.gba.versions").select("emerald")
local Dataset = require("src.core.game3.dataset"); Dataset.cacheRootOverride = root
require("src.core.game3.profile").reset()
local candidate = os.getenv("PIKE_FIELDVIEW_CANDIDATE")
if candidate then package.preload["src.core.game3.field_view"] = assert(loadfile(candidate)) end
local Schema = require("src.core.game3.save_schema_firered")
local Runtime = require("src.core.game3.runtime")
local session = Schema.newGame({version = "emerald", name = "BRENDAN"})
local game = {session = session, save = Schema.toSaveTable(session)}
Dataset.hydrate(game)
Runtime.start(nil, game, session, {alreadyOnMap = true})
local Map = require("src.core.game3.map")
local Space = require("src.core.game3.scripting.space")
local Objects = require("src.core.game3.objects")
local Pike = require("src.core.game3.rse.frontier.pike")
local Rse = require("src.core.game3.rse.init")
local D = require("src.core.game3.rse.frontier.trainers")
local FieldView = require("src.core.game3.field_view")
local Ow = require("src.core.game3.ow_sprites")
local function up(fn, wanted)
  for i = 1, 100 do local name, value = debug.getupvalue(fn, i); if name == wanted then return value end end
  error("actual renderer missing " .. wanted)
end
local collect, drawActor = up(FieldView.draw, "collectGame3Actors"), up(FieldView.draw, "drawSingleActor")
local function actors()
  local under, over = collect(game, Map.currentDef(), 0, 0, 64, 128, "up", 0, false, 0, 0)
  local result = {}
  for _, rows in ipairs({under, over}) do for _, actor in ipairs(rows) do
    if actor.eventObject then result[actor.i] = actor end
  end end
  return result
end
local originalDraw, originalGpu = Ow.draw, love.graphics.draw
local calls, gpu = {}, 0
Ow.draw = function(id, ...)
  calls[#calls + 1] = id
  return originalDraw(id, ...)
end
love.graphics.draw = function(...) gpu = gpu + 1; return originalGpu(...) end
local target = "EM_BATTLE_FRONTIER_BATTLE_PIKE_ROOM_NORMAL"
for _, kind in ipairs({"STATUS", "DOUBLE_BATTLE"}) do
  Map.load(nil, game, "EM_INSIDE_OF_TRUCK", {x = 2, y = 2, facing = "down"})
  Pike.rt(session).roomType = Pike.ROOM[kind]
  Pike.rt(session).statusMon = Pike.STATUSMON.DUSCLOPS
  Map.load(nil, game, target, {x = 4, y = 8, facing = "up"})
  local expected = kind == "STATUS" and {48, 226} or {
    D.gfxId(session, session.frontierOpponentA, D.FACILITY.PIKE),
    D.gfxId(session, session.frontierOpponentB, D.FACILITY.PIKE)}
  T.eq(Map.current, target, kind .. " actual Map.load")
  T.eq(Space.mapId, target, kind .. " actual VM map")
  T.eq(Rse.var("VAR_TEMP_4", session), 1, kind .. " imported ON_WARP ran")
  T.eq(Rse.var("VAR_OBJ_GFX_ID_0", session), 28, kind .. " source resets template0 after spawn")
  T.eq(Rse.var("VAR_OBJ_GFX_ID_1", session), 28, kind .. " source resets template1 after spawn")
  local rows = actors()
  for id = 1, 2 do
    local object, actor = Objects._byId[id], assert(rows[id])
    T.eq(object.graphicsId, expected[id], kind .. " actual source spawned object" .. id)
    T.eq(Space.resolveObjectGraphicsId(object.def), 28, kind .. " postwarp template" .. id)
    T.eq(actor.graphicsId, expected[id], kind .. " collector retains spawned ID" .. id)
    local before = gpu
    drawActor(game, Map.currentDef(), actor, 0, 0)
    T.eq(calls[#calls], expected[id], kind .. " actual OwSprites.draw ID" .. id)
    T.check(gpu > before, kind .. " actual imported sprite reaches graphics.draw" .. id)
    T.check(Ow.getDraw(expected[id]) ~= Ow.getDraw(28), kind .. " distinct source sprite sheet" .. id)
  end
  local Ghosts = require("src.core.game3.ghosts")
  local neighbor = up(collect, "collectNeighborActors")
  local world = Map.world
  Map.world = {{id = target, def = Map.currentDef(), ox = 0, oy = 0}}
  Ghosts.capture(target)
  local adjacent = {}
  neighbor(adjacent, 10000, "control-host", {}, 0, 0)
  local ghostIds = {}
  for _, actor in ipairs(adjacent) do ghostIds[actor.graphicsId] = true end
  T.check(ghostIds[expected[1]] and ghostIds[expected[2]], kind .. " actual captured ghost pool retains IDs")
  T.check(adjacent[1] and adjacent[1].ghost == target, kind .. " neighbor ghost provenance retained")
  Ghosts.clear()
  local truck = "EM_INSIDE_OF_TRUCK"
  Map.world = {{id = truck, def = game.data.maps[truck], ox = 0, oy = 0}}
  adjacent = {}
  neighbor(adjacent, 10000, "control-host", {}, 0, 0)
  T.check(#adjacent > 0, kind .. " ordinary raw neighboring templates remain visible")
  for _, actor in ipairs(adjacent) do
    T.eq(actor.graphicsId, actor.obj.graphicsId or actor.obj.graphics, kind .. " ordinary uncaptured neighbor uses its static template")
    T.check(actor.eventObject == nil, kind .. " raw neighbor remains independent from live pool")
  end
  Map.world = world
  local custom = 0
  drawActor(game, Map.currentDef(), {x = 0, y = 0, kind = "mod", draw = function() custom = custom + 1 end}, 0, 0)
  T.eq(custom, 1, kind .. " public custom draw remains authoritative")
  local under, over = collect(game, Map.currentDef(), 0, 0, 64, 128, "up", 0, false, 0, 0)
  local player
  for _, list in ipairs({under, over}) do for _, actor in ipairs(list) do if actor.kind == "player" then player = actor end end end
  T.check(player and not player.eventObject, kind .. " player remains independent from event graphics")
  T.eq(Objects.refreshGraphics(), 2, kind .. " explicit refresh remains authoritative")
  rows = actors()
  for id = 1, 2 do
    T.eq(Objects._byId[id].graphicsId, 28, kind .. " explicit refresh changes cached ID" .. id)
    T.eq(rows[id].graphicsId, 28, kind .. " renderer consumes explicit refresh" .. id)
    local object = Objects._byId[id]
    object.graphicsId = nil
    T.eq(actors()[id].graphicsId, 28, kind .. " missing runtime cache uses template fallback" .. id)
    object.graphicsId = 28
  end
end
Ow.draw, love.graphics.draw = originalDraw, originalGpu
T.finish()
