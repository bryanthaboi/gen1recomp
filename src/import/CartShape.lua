-- Clockwise, normalized shell profiles.
local CartShape = { GBA_ASPECT = 60 / 34.5 }

local GB_BODY = {
  { -0.5, -0.5 + 3 / 65 }, { 0.5, -0.5 + 3 / 65 },
  { 0.5, 0.5 }, { -0.5, 0.5 },
}
local GB_CAP = {
  { -0.5, -0.5 }, { 0.5 - 5 / 57, -0.5 },
  { 0.5 - 5 / 57, -0.5 + 3 / 65 }, { -0.5, -0.5 + 3 / 65 },
}
local GBA_BODY = {
  { -0.472, -0.345 }, { 0.472, -0.345 },
  { 0.472, 0.47 }, { 0.458, 0.5 },
  { -0.458, 0.5 }, { -0.472, 0.47 },
}
local GBA_CAP = {
  { -0.473, -0.5 }, { 0.473, -0.5 },
  { 0.49, -0.482 }, { 0.5, -0.447 },
  { 0.5, -0.32 }, { -0.5, -0.32 },
  { -0.5, -0.447 }, { -0.49, -0.482 },
}

function CartShape.outlines(shape)
  if shape == "gba" then return GBA_BODY, GBA_CAP end
  return GB_BODY, GB_CAP
end

-- Normalized label bounds.
function CartShape.labelRect(shape)
  if shape == "gba" then return { -0.365, -0.265, 0.73, 0.645 } end
  return { -0.33, -0.20, 0.66, 0.55 }
end

return CartShape
