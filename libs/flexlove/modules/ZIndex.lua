---@class ZIndex
local ZIndex = {}

-- The effective z-index formula used for sorting is:
--   rootZ * ROOT_WEIGHT + depth * DEPTH_WEIGHT + ownZ
-- where rootZ is the z-index of the top-level ancestor, depth is the
-- nesting level, and ownZ is the element's own z property.
--
-- Constraints enforced by these weights:
--   |ownZ| <= MAX_Z   (must fit within DEPTH_WEIGHT digits)
--   DEPTH_WEIGHT has enough room for depths well beyond any practical tree
--   ROOT_WEIGHT has enough room for the rootZ without exceeding double-precision
---
---@type integer
ZIndex.MIN_Z = -999
---@type integer
ZIndex.MAX_Z = 999
---@type integer
ZIndex.ROOT_WEIGHT = 10000000000
---@type integer
ZIndex.DEPTH_WEIGHT = 1000

--- Clamp a z-index value to the valid range
---@param value number
---@return integer
function ZIndex.clamp(value)
  if value < ZIndex.MIN_Z then
    return ZIndex.MIN_Z
  elseif value > ZIndex.MAX_Z then
    return ZIndex.MAX_Z
  end
  return value
end

return ZIndex
