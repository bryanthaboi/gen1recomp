-- The curved-horizon world bend, disabled for the FireRed prototype.
--
-- With k() answering 0 the shader's curve term and Voxel3D.project's
-- matching drop both collapse to zero, so the world is a flat plane and
-- projected anchors land exactly where the vertex stage put them -- which
-- is what the terrain mesh (absolute world coordinates, no transform) and
-- the character anchoring both assume.
--
-- Turning it on is a FASE 3 item: it needs every mesh vertex and every
-- projected sprite to agree on the same bend, and the map is small enough
-- that the horizon does not need help.
--
-- Origin: DramaticShapeVoxelMod (lib/WorldCurve.lua), reduced to the
-- surface Voxel3D reads.

local WorldCurve = {}

function WorldCurve.k(vh) return 0 end
function WorldCurve.drop(k, cx, cz, x, z) return 0 end

return WorldCurve
