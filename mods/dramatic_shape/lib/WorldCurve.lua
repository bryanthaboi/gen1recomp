-- Voxel world mode: the curved world -- the Animal Crossing horizon.
--
-- Every vertex is pushed DOWN by the square of its horizontal distance from
-- the camera's focus:
--
--     y' = y - k * ((x - cx)^2 + (z - cz)^2)
--
-- and that is the whole effect. The ground you are standing on stays flat
-- (a quadratic is nearly zero near its vertex -- at half a tile out the drop
-- is a hundredth of a pixel), and the falloff accelerates with distance, so
-- the far edge of the map bends away and rolls over a near horizon. The
-- town reads as sitting on top of a small sphere.
--
-- WHAT IT IS NOT is a fisheye. A fisheye is a LENS -- a screen-space
-- warp -- and it bends straight lines everywhere, including right in front
-- of the player, and resamples every pixel to do it. On pixel art that
-- means a blurred, crawling image and a bent HUD. This bends the WORLD
-- instead: one line in the vertex shader, straight lines near the camera
-- stay straight, and not a single pixel is resampled, so the art stays as
-- crisp as it was.
--
-- Two properties are what keep it readable rather than nauseating, and both
-- fall out of displacing along Y only:
--
--   Things stay UPRIGHT. The drop depends on where a column stands, not on
--   how tall it is, so a building's whole column moves together -- the
--   world tips away, the buildings on it do not lean.
--   Shadows and the voxel grid RIDE ALONG. Both are worked out before the
--   bend -- the shadow map in flat world space, the wireframe in model
--   space -- so the bend carries them with it exactly as if it had been
--   painted on. Nothing has to be recomputed and the light frustum never
--   moves.
--
-- The strength is scaled by the VIEW HEIGHT, so a rung looks the same at
-- every zoom: `amount` is the drop, in view-heights, one view-height out.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")

local WorldCurve = {}

WorldCurve.KEY = "curve"
WorldCurve.LABEL = "V-CURVE"

-- The ladder, calibrated against the FAR EDGE of the visible ground -- a
-- little over two view-heights out at the low camera rungs. Since the drop
-- goes as the square, that edge falls `amount * 4` view-heights while the
-- ground within a screen of the player barely moves, which is the whole
-- shape of the effect: flat where you are playing, rolling where you are
-- only looking.
--
-- 1 is a hint of roll at the frame edges, 2 is the Animal Crossing read,
-- 3 is as far as it goes before the horizon closes inside the next block
-- of the town -- which stops being a look and starts being an occlusion
-- bug, since what has rolled away is still there to walk into. (The first
-- cut ran 0.18/0.35/0.60 and every rung of it was a marble.)
WorldCurve.AMOUNTS = { 0, 0.05, 0.10, 0.18 }

WorldCurve.setting = ModSetting.new(WorldCurve.KEY, WorldCurve.LABEL,
                                    { 0, 1, 2, 3 },
                                    { "OFF", "1", "2", "3" })

function WorldCurve.level()
  return WorldCurve.setting:get() or 0
end

function WorldCurve.active()
  return WorldCurve.level() > 0
end

-- The quadratic's coefficient for a view `vh` world pixels tall: the drop
-- in world pixels per squared world pixel of distance. Zero when off, which
-- is also the shader's "skip it" signal.
function WorldCurve.k(vh)
  local amount = WorldCurve.AMOUNTS[WorldCurve.level() + 1] or 0
  if amount <= 0 or not vh or vh <= 0 then return 0 end
  return amount / vh
end

-- The same displacement the vertex shader applies, for the callers that
-- have to agree with it on the CPU -- Voxel3D.project, which anchors the
-- overworld's 2D field FX (the "!" bubble, the fishing rod, the Fly bird)
-- to their ground points. Miss this and every one of them floats off its
-- own feet the moment the ground under it bends.
function WorldCurve.drop(k, cx, cy, wx, wz)
  if k <= 0 then return 0 end
  local dx, dz = wx - cx, wz - cy
  return (dx * dx + dz * dz) * k
end

function WorldCurve.row()
  return WorldCurve.setting:row()
end

function WorldCurve.sync(value)
  WorldCurve.setting:sync(value)
end

return WorldCurve
