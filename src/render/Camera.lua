-- Camera centered on the player.  At the default 160x144 view this is
-- the original framing (player sprite at screen tile (8,8) -> pixel
-- (64, 60) after the -4px sprite offset); wider/taller world-pass views
-- (window-filling survey on phones, wheel zoom-out) keep the player at
-- the same relative center.

local Camera = {}
Camera.__index = Camera

function Camera.new()
  return setmetatable({ x = 0, y = 0 }, Camera)
end

function Camera:follow(px, py, viewW, viewH)
  viewW, viewH = viewW or 160, viewH or 144
  self.x = px - (viewW / 2 - 16)
  self.y = py - (viewH / 2 - 8)
  self.viewW, self.viewH = viewW, viewH
end

-- Re-centre on the same point after the view changes size between follows
-- (the overworld only follows while it updates, not under a menu).
function Camera:refit(viewW, viewH)
  if not (viewW and viewH and self.viewW and self.viewH) then return end
  if viewW == self.viewW and viewH == self.viewH then return end
  self.x = self.x + (self.viewW - viewW) / 2
  self.y = self.y + (self.viewH - viewH) / 2
  self.viewW, self.viewH = viewW, viewH
end

return Camera
