-- Reverse channel for src/render/SecondScreen.lua: turns queued touches on
-- the AYN Thor's bottom panel (GameActivity.queueSecondScreenTouch /
-- pollSecondScreenTouch, love::android::pollSecondScreenTouch in
-- android.cpp) into completed taps in the same 160x144 coordinate space
-- SecondScreen draws in.
--
-- poll() drains everything queued since the last call and reports where a
-- press lifted, if one did. Calling it more than once per real frame (a
-- fast-forwarded BattleState:update() can run several times per rendered
-- frame) is safe -- each call only consumes what is queued at that point,
-- so nothing is lost or double-counted.

local SecondScreenInput = {}

-- action codes, matching GameActivity.queueSecondScreenTouch
local PRESS, RELEASE, CANCEL = 0, 2, 3

local down = false

-- Returns x, y (in SecondScreen's 160x144 space) for a tap that completed
-- since the last call, or nil if none did. MOVE events are drained but
-- otherwise ignored: menu taps only care about where a press lifted, not
-- the path a finger took getting there.
function SecondScreenInput.poll()
  if not love.system.pollSecondScreenTouch then return nil end
  local tapX, tapY
  while true do
    local ev = love.system.pollSecondScreenTouch()
    if not ev then break end
    if ev.action == PRESS then
      down = true
    elseif ev.action == RELEASE then
      if down then tapX, tapY = ev.x, ev.y end
      down = false
    elseif ev.action == CANCEL then
      down = false
    end
  end
  return tapX, tapY
end

return SecondScreenInput
