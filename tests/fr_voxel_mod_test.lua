-- The FireRed diorama mod (mods/fr_voxel) driven through the public mod
-- API: manifest validation, registration in the render_pipelines registry,
-- the map-scope ladder, and -- the contract the engine's 2D path rests on
-- -- that a scene with nothing to draw answers nil instead of throwing.
package.path = "./?.lua;./?/init.lua;" .. package.path

if not _G.love then _G.love = require("tests.love_stub") end

local Loader = require("src.mods.Loader")
local Pipelines = require("src.render.Pipelines")
local GameVersion = require("src.core.GameVersion")

local S = require("tests.harness").suite("fr_voxel diorama")
local check, eq = S.check, S.eq

-- The mod claims FireRed and LeafGreen, and the loader skips a mod that
-- did not claim THIS game -- so the boot this suite stands in for is a
-- FireRed boot, not the harness's default Red one.
local savedVersion = GameVersion.get()
GameVersion.set("firered")
local generation = GameVersion.generation()

-- The real mod on disk, but only fr_voxel is offered to discovery: the
-- suite must not depend on which other mods happen to sit in mods/.
local function diskfs()
  local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local src = f:read("*a")
    f:close()
    return src
  end
  return {
    read = read,
    getInfo = function(path)
      if path == "mods" or path == "mods/fr_voxel" then
        return { type = "directory" }
      end
      if read(path) then return { type = "file" } end
      return nil
    end,
    load = function(path)
      local src = read(path)
      if not src then return nil, "no file: " .. path end
      return load(src, "@" .. path)
    end,
    getDirectoryItems = function(path)
      if path == "mods" then return { "fr_voxel" } end
      return {}
    end,
  }
end

-- ------- manifest + entry point

local data = {}
local loader = Loader.new({ fs = diskfs(), generation = generation })
local okLoad = loader:load(data)
check(okLoad, "fr_voxel loads clean: "
  .. table.concat(loader.errors or {}, "; "))
check(loader.mods.fr_voxel ~= nil, "the mod is in the registry")

Pipelines.install(data)

eq(data.render_pipelines and data.render_pipelines._owners
  and data.render_pipelines._owners.fr_diorama, "fr_voxel",
  "the merge stamped fr_diorama as owned by fr_voxel")

-- ------- the record the engine will dispatch to

local rec
for _, p in ipairs(Pipelines.list()) do
  if p.id == "fr_diorama" then rec = p end
end
check(rec ~= nil, "fr_diorama is catalogued with the engine's pipelines")
local availableAnswer
if rec then
  eq(rec.def.label, "DIORAMA", "the mode has its display label")
  eq(rec.def.hotkey, "6", "the mode sits on a hotkey no engine branch claims")
  eq(#rec.def.levels, 4,
    "the ladder is OFF / Pallet / +Route 1 / every map")
  eq(rec.def.levels[1], "OFF", "rung 0 is the vanilla 2D field")
  check(type(rec.def.gate) == "function", "the mode declares when it can change")
  check(type(rec.def.update) == "function", "the mode ticks with the frame")
  check(type(rec.def.drawWorld) == "function", "the mode draws the world")
  check(type(rec.def.invalidate) == "function", "the mode drops stale geometry")

  check(rec.def.gate(false, false) == false,
    "the mode refuses to switch outside the overworld")
  check(rec.def.gate(false, true) == true,
    "the mode may switch on the overworld")

  local okAv, av = pcall(rec.def.available)
  check(okAv, "available() answers without throwing: " .. tostring(av))
  check(av == nil or av == true or av == false,
    "available() answers with a boolean")
  availableAnswer = av
end

-- ------- the map scope ladder

local scene = loader.exports.fr_voxel and loader.exports.fr_voxel.scene
check(scene ~= nil and type(scene.allowed) == "function",
  "the mod exports its scope table")
if scene then
  eq(scene.allowed("FR_PALLET_TOWN", 1), true,
    "rung 1 renders Pallet Town")
  eq(scene.allowed("FR_ROUTE_1", 1), false,
    "rung 1 leaves Route 1 on the flat field")
  eq(scene.allowed("FR_ROUTE_1", 2), true,
    "rung 2 adds Route 1")
  eq(scene.allowed("FR_CERULEAN_CITY", 2), false,
    "rung 2 still keeps the rest of Kanto flat")
  eq(scene.allowed("FR_CERULEAN_CITY", 3), true,
    "rung 3 renders every map")
  eq(scene.allowed("FR_PALLET_TOWN", 0), true,
    "an unset level clamps to the first rung rather than crashing")
  eq(scene.allowed(nil, 1), false,
    "no current map means nothing to render")

  local okDirty = pcall(scene.markDirty)
  check(okDirty, "markDirty survives a block swap")
  local okInv = pcall(scene.invalidate)
  check(okInv, "invalidate survives a mode change")
end

-- ------- the frame contract

Pipelines.setLevel("fr_diorama", 1)
eq(Pipelines.level("fr_diorama"), 1, "the ladder moves to its first rung")

if availableAnswer == true then
  eq(Pipelines.worldPipeline(), "fr_diorama",
    "the mode owns the world pass while the driver allows it")
else
  check(Pipelines.worldPipeline() == nil,
    "a driver that cannot render 3D keeps the vanilla 2D path")
end

local okTick, tickErr = pcall(Pipelines.update, 0.016)
check(okTick, "the mode's per-frame tick does not throw: "
  .. tostring(tickErr))

-- no context at all: the engine must still get an answer, not a crash
local okNil, nilErr = pcall(Pipelines.drawWorld, "fr_diorama", nil)
check(okNil, "drawWorld survives a nil context: " .. tostring(nilErr))

-- a bare context with no map loaded: the scene declines, which the engine
-- treats as "keep the vanilla 2D path for this frame"
local ctx = {
  state = {},
  cam = { x = 0, y = 0 },
  vw = 240,
  vh = 160,
  level = 1,
}
local okDraw, out = pcall(Pipelines.drawWorld, "fr_diorama", ctx)
check(okDraw, "drawWorld survives a bare context: " .. tostring(out))
check(out == nil,
  "the scene declines instead of drawing an empty frame")

Pipelines.setLevel("fr_diorama", 0)
Pipelines.install(nil)
GameVersion.set(savedVersion)
S.finish()

