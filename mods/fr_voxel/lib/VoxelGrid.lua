-- The optional voxel wireframe overlay, disabled for the FireRed
-- prototype.
--
-- beginScene asks whether the grid is on before it decides which shader
-- variant to compile, so this only has to answer "no" honestly; the two
-- constants are still sent (gridDark/gridWidth) on the code path where a
-- grid build did succeed, so they stay defined.
--
-- Origin: DramaticShapeVoxelMod (lib/VoxelGrid.lua), reduced to the
-- surface Voxel3D reads.

local VoxelGrid = {}

VoxelGrid.DARK = 0.55
VoxelGrid.WIDTH = 0.035

function VoxelGrid.enabled() return false end

return VoxelGrid
