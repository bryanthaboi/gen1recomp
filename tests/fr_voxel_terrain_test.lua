-- The diorama's terrain mesh over the REAL FireRed cache: Pallet Town
-- extrudes into geometry, the heights follow the collision bytes, and the
-- 3D scene answers without taking the frame down.
--
-- love's 3D surface is stubbed to CAPTURE what the mod builds -- the
-- headless stub has no depth buffer, no shaders and no meshes, and every
-- one of those is a precondition the real driver answers for.  The mod's
-- own loading through the sandboxed mod API is covered by
-- tests/fr_voxel_mod_test.lua; this suite loads the same library files
-- directly so it can assert on what they build.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] fr_voxel_terrain_test: " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Map = require("src.core.game3.map")

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

-- ------- the 3D surface the driver would provide
love.graphics.setDepthMode = function() end
love.graphics.setMeshCullMode = function() end
love.graphics.newShader = function()
  return { send = function() end }
end

local built = {}
love.graphics.newMesh = function(_, verts)
  built[#built + 1] = verts
  return {
    setVertexMap = function() end,
    setTexture = function() end,
  }
end

-- ------- the mod's library, as main.lua loads it
local V = {}
local modules = {}
function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  local path = "mods/fr_voxel/lib/" .. name .. ".lua"
  local f = assert(io.open(path, "rb"))
  local src = f:read("*a")
  f:close()
  local value = assert(load(src, "@" .. path))(V)
  modules[name] = value
  return value
end
local FrTerrain = V.require("FrTerrain")
local FrScene = V.require("FrScene")
local Voxel3D = V.require("Voxel3D")

check(Voxel3D.available() == true,
  "with the stub driver's3D surface, the 3D path reports available")

-- ------- a real Pallet Town
local game = { data = {} }
Dataset.hydrate(game)
check(type(game.data.maps) == "table"
  and game.data.maps.FR_PALLET_TOWN ~= nil,
  "the cache carries FR_PALLET_TOWN")

local def = Map.load(nil, game, "FR_PALLET_TOWN")
check(def ~= nil, "Map.load enters Pallet Town")
if not def then finish() end
check(Map.current == "FR_PALLET_TOWN", "Map.current is the loaded map")

print("[test] 1. the mesh builds")
local t0 = os.clock()
local okBuild = FrTerrain.ensure(game, 240, 160)
local buildMs = (os.clock() - t0) * 1000
check(okBuild == true, "FrTerrain.ensure builds the Pallet Town mesh")
check(FrTerrain.ready() == true, "the terrain reports ready")
check(#built > 0, #built .. " tileset chunk(s) produced a mesh")

local verts = 0
for _, v in ipairs(built) do verts = verts + #v / 6 end
check(verts > 4000,
  ("the mesh carries %d vertices over %d quads"):format(verts, verts / 4))

-- a rebuild with nothing changed must not touch the GPU objects
local before = #built
t0 = os.clock()
check(FrTerrain.ensure(game, 240, 160) == true,
  "a second ensure answers true")
local cachedMs = (os.clock() - t0) * 1000
check(#built == before, "and reuses the mesh it already built")

-- what a block swap costs: markDirty is what the engine's world.block_replaced
-- hook calls, so this is the hitch a Cut or a Rock Smash would pay
FrTerrain.markDirty()
t0 = os.clock()
check(FrTerrain.ensure(game, 240, 160) == true, "a dirty rebuild rebuilds")
local rebuildMs = (os.clock() - t0) * 1000
print(("[perf] mesh build %.1f ms, dirty rebuild %.1f ms, cached check %.3f ms")
  :format(buildMs, rebuildMs, cachedMs))

print("[test] 2. heights follow the collision bytes")
local rootDef = game.data.maps[Map.current]
local layout = rootDef and rootDef.midLayout
check(layout ~= nil, "the loaded map exposes its metatile layout")
if not layout then finish() end
local raised, flat, sunk = 0, 0, 0
for cy = 0, layout.height - 1 do
  for cx = 0, layout.width - 1 do
    local h = FrTerrain.heightAtWorld(cx * 16 + 8, cy * 16 + 8)
    if h > 0 then raised = raised + 1
    elseif h < 0 then sunk = sunk + 1
    else flat = flat + 1 end
  end
end
check(flat > 0, "walkable cells sit at ground level (" .. flat .. " cells)")
check(raised > 0, "solid cells extrude one tile (" .. raised .. " cells)")
print(("[info] heights: %d flat, %d raised, %d sunk"):format(flat, raised, sunk))

-- outside the built apron the answer is the ground plane, not a hole
check(FrTerrain.heightAtWorld(-4096, -4096) == 0,
  "a point outside the apron answers 0")

print("[test] 3. the scene renders a frame")
local ctx = {
  state = game,
  cam = { x = 0, y = 0 },
  vw = 240,
  vh = 160,
  level = 1,
  actors = {
    mapId = Map.current,
    mapDef = def,
    camX = 0,
    camY = 0,
    px = 100,
    py = 100,
    under = {},
    over = {},
  },
}
local okScene, scene = pcall(FrScene.render, ctx)
check(okScene, "FrScene.render does not throw: " .. tostring(scene))
check(scene ~= nil, "the scene hands back a canvas to composite")

-- CPU-side cost of a frame once the mesh exists. The stub does no GPU work,
-- so this is the lower bound: everything the driver would add on top.
local t1 = os.clock()
for _ = 1, 10 do pcall(FrScene.render, ctx) end
print(("[perf] FrScene.render %.2f ms/frame (headless stub, CPU only)")
  :format((os.clock() - t1) * 100))

local okDraw, drew = pcall(FrTerrain.draw)
check(okDraw, "the terrain draws under the 3D camera: " .. tostring(drew))

-- the scope ladder is what keeps the mode off every other map
check(FrScene.allowed("FR_PALLET_TOWN", 1) == true,
  "rung 1 renders this map")
check(FrScene.allowed("FR_CERULEAN_CITY", 1) == false,
  "rung 1 leaves every other map on the flat field")

print("[test] 4. the cast the engine hands the pipeline")
-- src/core/game3/display.lua builds this before it calls drawWorld, so it
-- is the seam between the vanilla field and the mod's own draw.  It reads
-- the current map off the session, the way a boot with a save does.
local Runtime = require("src.core.game3.runtime")
local session = Runtime.getSession and Runtime.getSession()
if not session then
  session = { map = "FR_PALLET_TOWN", flags = {}, vars = {}, party = {},
              name = "RED" }
  Runtime.session = session
end
session.map = "FR_PALLET_TOWN"

local FieldView = require("src.core.game3.field_view")
local okCast, cast = pcall(FieldView.pipelineActors, game, 240, 160)
check(okCast, "pipelineActors does not throw: " .. tostring(cast))
check(type(cast) == "table", "pipelineActors returns a cast")
if type(cast) == "table" then
  check(cast.mapId == "FR_PALLET_TOWN",
    "the cast is stamped with the current map")
  check(cast.mapDef ~= nil, "the cast carries the map definition")
  check(type(cast.camX) == "number" and type(cast.camY) == "number",
    "the camera anchor is a pair of numbers")
  check(type(cast.under) == "table" and type(cast.over) == "table",
    "actors are split under and over the player")
  check(#cast.under + #cast.over >= 1,
    "the cast carries the player (" .. (#cast.under + #cast.over) .. " actors)")
  check(cast.px ~= nil and cast.py ~= nil,
    "the player's pixel position rides along")
end

finish()
