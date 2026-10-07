-- Issue #2746: camera lifecycle used by Emerald's Sootopolis ON_FRAME scripts.
-- ROM-free fixture of pokeemerald/data/maps/SootopolisCity/scripts.inc:
-- PanToActionFromPokeCenter / PanBackToPokeCenter and their Dive counterparts.
-- Exercise real native handlers, movement tracks and scene completion; only the
-- movie UI and field renderer are replaced (no ROM/assets or LÖVE required).
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local eq, check = T.eq, T.check
local Version = require("src.core.GameVersion")
Version.set("emerald")
local Camera = require("src.core.game3.camera_object")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local FieldView = require("src.core.game3.field_view")
local Natives = require("src.core.game3.scripting.natives")
local Scenes = require("src.core.game3.scripting.natives_scenes_rse")
local Ctx = require("src.core.game3.scripting.ctx")
local Movement = require("src.core.game3.scripting.movement")
local Canon = require("src.import.gba.movement_emerald")
local mapId = "EM_SOOTOPOLIS_CITY"
local CELL = 16

local renderedX, renderedY
FieldView.draw = function()
  renderedX = Player.px + FieldView.cameraPanX
  renderedY = Player.py + FieldView.cameraPanY
end

local function loadMap(id)
  Objects.loadMap(nil, id or mapId, { objects = {} })
end
local function focus(x, y, label)
  FieldView.draw(nil, 240, 160)
  eq(renderedX, x * CELL, label .. " focus x")
  eq(renderedY, y * CELL, label .. " focus y")
end
local function special(name)
  local handler = assert(Natives.handlerFor(name), "missing native " .. name)
  handler(Ctx.new(), {})
end
local function stream(groups)
  local bytes = {}
  for _, group in ipairs(groups) do
    local cmd = assert(Canon.canonOf("MOVEMENT_ACTION_" .. group[1]))
    for _ = 1, group[2] do bytes[#bytes + 1] = cmd end
  end
  bytes[#bytes + 1] = Movement.STEP_END
  return bytes
end
local function pan(bytes, bounds, label)
  local done = 0
  Objects.applyMovement(Camera.LOCALID, bytes, function() done = done + 1 end)
  local inBounds = true
  for _ = 1, 1600 do
    Objects.update(nil)
    FieldView.draw(nil, 240, 160)
    if bounds then
      inBounds = inBounds and renderedX >= bounds[1] * CELL and renderedX <= bounds[2] * CELL
        and renderedY >= bounds[3] * CELL and renderedY <= bounds[4] * CELL
    end
    if Objects.pollMovement(Camera.LOCALID) then break end
  end
  eq(done, 1, label .. " releases waitmovement once")
  check(Objects.pollMovement(Camera.LOCALID), label .. " finishes")
  check(inBounds, label .. " stays between fight and arrival focus on every frame")
end

local arrivals = {
  { name = "Fly/PokeCenter", x = 43, y = 32,
    outward = { { "WALK_SLOW_DIAGONAL_DOWN_LEFT", 12 } },
    inward = { { "WALK_SLOW_DIAGONAL_UP_RIGHT", 12 } }, bounds = { 31, 43, 32, 44 } },
  { name = "Dive", x = 29, y = 53,
    outward = { { "WALK_SLOW_DIAGONAL_UP_RIGHT", 2 }, { "WALK_NORMAL_UP", 7 } },
    inward = { { "WALK_NORMAL_DOWN", 7 }, { "WALK_SLOW_DIAGONAL_DOWN_LEFT", 2 } },
    bounds = { 29, 31, 44, 53 } },
}
for _, a in ipairs(arrivals) do
  print("[test] " .. a.name .. " Sootopolis camera sequence")
  Camera.reset()
  loadMap()
  Player.reset(a.x, a.y, "down")
  FieldView.setCameraPanning(0, 0)
  special("SpawnCameraObject")
  check(Camera.isActive(), a.name .. " native spawns camera")
  pan(stream(a.outward), a.bounds, a.name .. " outward pan")
  focus(31, 44, a.name .. " fight before removal")
  special("RemoveCameraObject")
  check(not Camera.isActive(), a.name .. " native removes camera object")
  eq(Objects.find(Camera.LOCALID), nil, a.name .. " no invisible object left")
  focus(31, 44, a.name .. " fight after removal")

  -- Real Script_DoRayquazaScene callback, with its movie UI replaced only.
  local ctx = Ctx.new()
  ctx.specialVars[0x8004] = 0
  local movie
  Scenes.doRayquazaScene(ctx, {}, { open = function(opts) movie = opts; return opts end })
  eq(movie.animId, 0, a.name .. " fight-only movie selected")
  eq(movie.endEarly, true, a.name .. " fight-only movie ends early")
  eq(ctx.stateWait(), false, a.name .. " script waits during movie")
  movie.onDone()
  eq(ctx.stateWait(), true, a.name .. " script resumes after movie")
  focus(31, 44, a.name .. " post-movie fight")
  FieldView.setCameraPanning(2, -1)
  FieldView.draw(nil, 240, 160)
  eq(renderedX, 31 * CELL + 2, a.name .. " shake adds to retained focus x")
  eq(renderedY, 44 * CELL - 1, a.name .. " shake adds to retained focus y")
  eq(FieldView.cameraPanX, 2, a.name .. " draw preserves shake x")
  eq(FieldView.cameraPanY, -1, a.name .. " draw preserves shake y")
  FieldView.setCameraPanning(0, 0)

  special("SpawnCameraObject")
  local eo = assert(Camera.object())
  eq(eo.cellX, 31, a.name .. " return camera starts at fight x")
  eq(eo.cellY, 44, a.name .. " return camera starts at fight y")
  pan(stream(a.inward), a.bounds, a.name .. " return pan")
  focus(a.x, a.y, a.name .. " returned to player")
  special("RemoveCameraObject")
  focus(a.x, a.y, a.name .. " final removal")
  eq(Player.cellX, a.x, a.name .. " player cell x unchanged")
  eq(Player.cellY, a.y, a.name .. " player cell y unchanged")
  eq(Player.px, a.x * CELL, a.name .. " player pixel x unchanged")
  eq(Player.py, a.y * CELL, a.name .. " player pixel y unchanged")
end

-- Nonzero retained focus must not leak across map/session lifecycles.
local function detach()
  Camera.reset()
  loadMap()
  Player.reset(43, 32, "down")
  special("SpawnCameraObject")
  pan(stream(arrivals[1].outward), arrivals[1].bounds, "lifecycle outward pan")
  special("RemoveCameraObject")
  focus(31, 44, "lifecycle retained focus")
end
detach()
loadMap()
focus(31, 44, "same-map object rebind retains focus")
Player.px, Player.py = Player.px + CELL, Player.py + CELL
focus(32, 45, "reattached camera follows player deltas without snapping")
Camera.reset()
focus(44, 33, "reset releases retained focus without an active object")
detach()
loadMap("EM_ROUTE126")
Player.reset(5, 6, "down")
focus(5, 6, "different map discards retained focus")
special("SpawnCameraObject")
eq(Camera.object().cellX, 5, "new map spawn x uses new player")
eq(Camera.object().cellY, 6, "new map spawn y uses new player")
detach()
local Runtime = require("src.core.game3.runtime")
Runtime.active = true
Runtime.stop(nil, nil)
focus(43, 32, "Runtime.stop releases retained focus")

-- Exercise the actual Map.load warp boundary, with unrelated asset/script
-- services replaced. Keep the real player, objects, camera and map loader.
local saved = {}
local function stub(name, value)
  saved[name] = { value = package.loaded[name] }
  package.loaded[name] = value
end
stub("src.core.game3.scripting.space", {
  bundle = {}, ensureBundle = function() end, attachEventsToMaps = function() end,
  activate = function() end, runEnterScripts = function() end,
})
stub("src.core.game3.ghosts", { capture = function() end, adopt = function() end })
stub("src.core.game3.field", { lock = function() end, unlock = function() end,
  clearMetatiles = function() end, metatileOverrides = {} })
stub("src.core.game3.runtime", { isActive = function() return true end, getSession = function() end })
stub("src.core.game3.collision", { bindMap = function() end, clear = function() end })
stub("src.core.game3.audio", { setSavedSong = function() end })
stub("src.core.game3.encounters", { resetRateModifiers = function() end })
stub("src.core.game3.field_effects", {})
stub("src.core.game3.field_modules", { enabled = function() return false end })
stub("src.core.game3.dataset", { isOutdoorMapType = function() return false end })
stub("src.core.game3.map", nil)
local Map = require("src.core.game3.map")
local game = { data = { maps = { [mapId] = {
  objects = {}, midLayout = { width = 64, height = 64, collAt = function() return 0 end },
} } } }
detach()
local result = Map.load({}, game, mapId, { x = 43, y = 32, depth1Connections = false })
check(result and result.mapId == mapId, "real same-map warp completes")
focus(43, 32, "same-map warp recenters retained focus")
eq(Camera.isActive(), false, "same-map warp leaves no old camera object")
-- A warp must also clear an active camera, not just a retained offset.
special("SpawnCameraObject")
pan(stream(arrivals[1].outward), arrivals[1].bounds, "active warp outward pan")
result = Map.load({}, game, mapId, { x = 43, y = 32, depth1Connections = false })
check(result and result.mapId == mapId, "warp with active camera completes")
eq(Camera.isActive(), false, "warp clears active camera")
focus(43, 32, "warp cannot re-register stale same-map camera")
for name, entry in pairs(saved) do package.loaded[name] = entry.value end
Camera.reset()
T.finish()
