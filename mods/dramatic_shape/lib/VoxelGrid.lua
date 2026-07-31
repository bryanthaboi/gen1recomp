-- Voxel world mode: the voxel wireframe, 3D Dot Game Heroes style.
--
-- Every mesh in this mode is built on a one-unit-per-voxel grid in its OWN
-- model space -- terrain in world pixels, a character card in the sprite's
-- own pixels. So the seams are simply the
-- integer planes of that space, and drawing them is a pixel-shader job:
-- measure how far the fragment is from the nearest integer plane, in
-- DISPLAY pixels, and darken the ones within half a pixel of it. Sitting in
-- model space is what keeps the wireframe glued to a thing however it is
-- posed -- a character's card leans back by the camera's pitch and its
-- seams lean with it, instead of the world's grid sliding across the
-- sprite.
--
-- Deriving "in display pixels" needs shader derivatives (fwidth), which is
-- the one part of this that a driver can refuse. So the grid is a SECOND
-- COMPILATION of the scene shader rather than a branch inside the first
-- one: if it will not build, the mod loses the wireframe and nothing else
-- (see Voxel3D.shader).
--
-- This file owns the toggle rather than the drawing: the level, where it
-- persists, and the row the player finds it on.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local VoxelGrid = {}

-- the key under options.modOptions.DRAMATIC_SHAPE, shared by the row in
-- OPTIONS and the mod manager's own settings page for this mod
VoxelGrid.KEY = "grid"
VoxelGrid.LABEL = "V-GRID"

-- How far toward black a seam pulls the surface it cuts across. The
-- wireframe reads as a shading of the model rather than an overlay drawn
-- on top of it, so it darkens what is already there instead of painting a
-- colour -- a seam across dark grass and one across a white roof both stay
-- in the palette they belong to.
VoxelGrid.DARK = 0.45

-- Line width, in display pixels. The scene canvas renders at window
-- resolution and composites 1:1, so a canvas pixel IS a display pixel and
-- 1.0 here is the one-pixel wireframe.
VoxelGrid.WIDTH = 1.0

-- where it persists and the rows that cycle it (see ModSetting)
VoxelGrid.setting = ModSetting.new(VoxelGrid.KEY, VoxelGrid.LABEL,
                                   { false, true }, { "OFF", "ON" })

-- A pass that needs the wireframe whatever the player left the row on sets
-- this for the length of its own draw and puts it back after. nil means
-- "follow the setting", which is every frame outside such a pass.
--
-- The overworld battle is the one user: a fight is a STAGED shot, not the
-- world being walked around in, and the seams are what make it read as
-- constructed rather than as a photograph of somewhere. The row still owns
-- what free-roam looks like, and is not written to -- switching the mode off
-- mid-battle would silently rewrite the player's own setting.
VoxelGrid.override = nil

function VoxelGrid.enabled()
  if VoxelGrid.override ~= nil then return VoxelGrid.override end
  return VoxelGrid.setting:get() and true or false
end

function VoxelGrid.set(enabled, game)
  return VoxelGrid.setting:setIndex(enabled and 2 or 1, game)
end

function VoxelGrid.toggle(game)
  return VoxelGrid.setting:cycle(game)
end

function VoxelGrid.sync(value)
  VoxelGrid.setting:sync(value and true or false)
end

function VoxelGrid.row()
  return VoxelGrid.setting:row()
end

return VoxelGrid
