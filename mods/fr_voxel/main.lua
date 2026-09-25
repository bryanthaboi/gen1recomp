-- FireRed Diorama: a 3D diorama overworld for the FireRed / LeafGreen
-- engine (src/core/game3), shipped as a render pipeline mod.
--
-- The engine's render_pipelines registry (src/mods/Schemas.lua) lets a mod
-- own part of the frame.  This one registers a single drawWorld pipeline:
-- instead of the flat metatile blit, the map's cells are extruded into
-- real geometry, walked by a depth-buffered 3D camera, with the
-- characters re-projected onto it.  Occlusion is the depth buffer, not a
-- y-sort: walk behind a house and the house is simply in front.
--
-- Everything a display mode needs beyond the draw function -- the ladder,
-- the options row, the hotkey, persistence in options.pipelines, the
-- free-roam gate, the mutual exclusion with the engine's TILT mode, and
-- the pcall fence that keeps a mod's error from taking the frame down --
-- is engine plumbing driven by the record below.  This file declares;
-- lib/ draws.
--
-- The ladder selects the map SCOPE rather than a camera angle: rung 1 is
-- Pallet Town, rung 2 adds Route 1, rung 3 is every map.  Nothing here
-- reaches collision, movement, triggers or scripts -- the mode changes
-- what the world LOOKS like and nothing about what it IS.

local mod = ...

-- ------- the mod namespace
--
-- lib/ modules require each other through V rather than package.path: a
-- mod directory is not on it, and may live inside a mounted .love archive
-- that plain require cannot reach.  Each module is loaded once, with V
-- passed in as its vararg (`local V = ...`).

local V = { mod = mod, path = mod.path }

local function chunkFor(rel)
  local source
  if type(mod.read) == "function" then
    local ok, got = pcall(mod.read, mod, rel)
    if ok then source = got end
  end
  if not source and love and love.filesystem then
    local ok, got = pcall(love.filesystem.read, mod.path .. "/" .. rel)
    if ok then source = got end
  end
  if not source then
    error(("fr_voxel: %s is missing -- reinstall the mod"):format(rel), 0)
  end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
  if not chunk then
    error(("fr_voxel: %s did not compile: %s"):format(rel, tostring(err)), 0)
  end
  return chunk
end

local modules = {}
function V.require(name)
  local hit = modules[name]
  if hit ~= nil then return hit end
  local value = chunkFor("lib/" .. name .. ".lua")(V)
  modules[name] = value
  return value
end

local Voxel = V.require("VoxelState")
local Voxel3D = V.require("Voxel3D")
local FrTerrain = V.require("FrTerrain")
local FrScene = V.require("FrScene")

-- 35 degrees: low enough to read as a diorama, high enough that the map
-- still reads as a map.  The ladder gives up the angle so it can carry
-- the map scope instead; VoxelState eases into and out of this rung so
-- switching the mode on is a camera move rather than a cut.
local ANGLE_LEVEL = 2

mod.content.render_pipelines:register("fr_diorama", {
  label = "DIORAMA",
  levels = { "OFF", "PALLET", "+ROUTE 1", "ALL" },

  -- 6 is free: no engine branch claims it, so this one alone reaches the
  -- registry by the documented route ("3" is the engine's TILT cycle).
  hotkey = "6",

  -- higher than a post-process would be, so if a world pipeline ever
  -- shares the registry this one owns the world pass
  priority = 100,

  -- headless runs and drivers without a depth canvas answer false here,
  -- and the engine keeps the vanilla 2D path -- which is why no caller
  -- ever has to guard for a missing 3D pass
  available = function()
    return Voxel3D.available()
  end,

  -- input only: whether the player may CHANGE the mode right now.  An
  -- already-on mode keeps drawing through a warp or a cutscene.
  gate = function(top, overworld)
    return overworld == true
  end,

  -- the engine hands over the live level; ease the camera toward the
  -- angle the mode draws at
  update = function(dt, level)
    Voxel.ready = FrTerrain.ready()
    Voxel.update(dt, (tonumber(level) or 0) > 0 and ANGLE_LEVEL or 0)
  end,

  drawWorld = function(ctx)
    return FrScene.render(ctx)
  end,

  invalidate = function()
    FrScene.invalidate()
  end,
})

-- Cut, Rock Smash and scripts replace metatiles in place; the collision
-- byte under that cell changes, so the extrusion has to follow.
pcall(function()
  mod.hooks:wrap("world.block_replaced", function(next, ctx)
    FrTerrain.markDirty()
    return next(ctx)
  end)
end)

-- Public handle: the scope table and the dirty flag are the parts another
-- mod (and this mod's tests) can meaningfully ask about without owning the
-- frame.  Nothing here draws.
mod.exports.scene = {
  allowed = FrScene.allowed,
  markDirty = FrTerrain.markDirty,
  invalidate = FrScene.invalidate,
}
