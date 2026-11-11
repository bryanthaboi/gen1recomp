-- Only these new preferences opt into physical-pixel scaling/filtering.
-- Every other value retains the legacy backend's interpretation.
local P = {}
local destinations = { auto = true, handheld = true, secondary = true }
local filters = { auto = true, nearest = true, bilinear = true, sharp = true }
function P.explicit(value)
  if type(value) ~= "string" then return nil end
  local destination, sizing, filter = value:match("^([^:]+):([^:]+):([^:]+)$")
  if not destination then destination, sizing = value:match("^([^:]+):([^:]+)$") end
  if not destinations[destination] or sizing ~= "fit" and sizing ~= "integer"
      or filter and not filters[filter] then return nil end
  return destination, sizing, filter
end
return P
