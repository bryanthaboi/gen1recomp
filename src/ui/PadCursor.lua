-- Virtual pointer for overlay hosts (save editor, touch-controls editor) on
-- Switch / handhelds / any gamepad.  Mirrors the launcher's RomImporter pad
-- cursor (speeds, deadzone, dual-path raw gate) without sharing that module.
--
-- Stick / D-pad move; real mouse motion yields so desktop stays normal.
-- Callers map A → click, B → close, shoulders → host-specific actions, right
-- stick → wheel notches (save editor lists).

local SafeArea = require("src.core.SafeArea")
local GamepadMap = require("src.core.GamepadMap")

local PAD_DEAD = 0.28
local PAD_SPEED = 560
local PAD_DPAD_SPEED = 420
-- Right stick → Kit wheel notches: ~2 notches/sec at full deflection so lists
-- scroll at a usable pace without flooding one frame.
local PAD_WHEEL_RATE = 2.0

local PadCursor = {}

local cursor = { x = 0, y = 0 }
local active = false
local inited = false
local axis = { leftx = 0, lefty = 0, righty = 0 }
local dir = {}
local rawHatDirs = {}
local lastMouseX, lastMouseY
local wheelAcc = 0

local function activate()
  if active then return end
  local ox, oy, w, h = SafeArea.rect()
  if not inited then
    cursor.x = ox + w * 0.5
    cursor.y = oy + h * 0.45
    inited = true
  end
  active = true
end

function PadCursor.reset()
  cursor.x, cursor.y = 0, 0
  active = false
  inited = false
  axis.leftx, axis.lefty, axis.righty = 0, 0, 0
  for k in pairs(dir) do dir[k] = nil end
  for k in pairs(rawHatDirs) do rawHatDirs[k] = nil end
  lastMouseX, lastMouseY = nil, nil
  wheelAcc = 0
end

-- Touch / mouse press: drop the virtual cursor for this interaction so a tap
-- is not swallowed by the Joy-Con pointer sitting elsewhere on screen.
function PadCursor.yieldToPointer()
  active = false
end

-- Returns mx, my, isActive.  When inactive the caller should use the system
-- mouse; when active these coords feed hit-tests / draws.
function PadCursor.pointer()
  return cursor.x, cursor.y, active
end

function PadCursor.isActive()
  return active
end

-- Consume accumulated right-stick scroll as integer wheel notches (same
-- units App.wheelmoved feeds Kit).  Fractional remainder stays for next frame.
function PadCursor.takeWheel()
  local notches = 0
  if wheelAcc >= 1 or wheelAcc <= -1 then
    notches = wheelAcc > 0 and math.floor(wheelAcc) or math.ceil(wheelAcc)
    wheelAcc = wheelAcc - notches
  end
  return notches
end

function PadCursor.update(dt)
  if not (love and love.mouse and love.mouse.getPosition) then return end
  local mx, my = love.mouse.getPosition()
  if lastMouseX and active then
    if math.abs(mx - lastMouseX) > 3 or math.abs(my - lastMouseY) > 3 then
      active = false
    end
  end
  lastMouseX, lastMouseY = mx, my

  local ax = axis.leftx or 0
  local ay = axis.lefty or 0
  local dx, dy = 0, 0
  if math.abs(ax) > PAD_DEAD then dx = dx + ax end
  if math.abs(ay) > PAD_DEAD then dy = dy + ay end
  if dir.dpleft then dx = dx - 1 end
  if dir.dpright then dx = dx + 1 end
  if dir.dpup then dy = dy - 1 end
  if dir.dpdown then dy = dy + 1 end

  if dx ~= 0 or dy ~= 0 then
    activate()
    local mag = math.sqrt(dx * dx + dy * dy)
    if mag > 1 then dx, dy = dx / mag, dy / mag end
    local speed = (math.abs(ax) > PAD_DEAD or math.abs(ay) > PAD_DEAD)
      and PAD_SPEED or PAD_DPAD_SPEED
    local ox, oy, w, h = SafeArea.rect()
    local nx = cursor.x + dx * speed * dt
    local ny = cursor.y + dy * speed * dt
    cursor.x = math.max(ox, math.min(ox + w, nx))
    cursor.y = math.max(oy, math.min(oy + h, ny))
  end

  local ry = axis.righty or 0
  if math.abs(ry) > PAD_DEAD then
    activate()
    -- Negative righty (stick up) scrolls lists up = positive wheel notches.
    wheelAcc = wheelAcc + (-ry) * PAD_WHEEL_RATE * dt
  end
end

-- Returns a string action the host handles:
--   "a" | "b" | "tab_prev" | "tab_next" | nil
function PadCursor.gamepadpressed(_, button)
  activate()
  local action = GamepadMap.mapGamepadButton(button)
  if action == "a" or action == "b" then
    return action
  elseif button == "leftshoulder" then
    return "tab_prev"
  elseif button == "rightshoulder" then
    return "tab_next"
  elseif button == "dpup" or button == "dpdown"
      or button == "dpleft" or button == "dpright" then
    dir[button] = true
  end
  return nil
end

function PadCursor.gamepadreleased(_, button)
  if button == "dpup" or button == "dpdown"
      or button == "dpleft" or button == "dpright" then
    dir[button] = nil
  end
end

function PadCursor.gamepadaxis(_, axisName, value)
  if axisName == "leftx" or axisName == "lefty" or axisName == "righty" then
    axis[axisName] = value
    if math.abs(value) > PAD_DEAD then activate() end
  end
end

function PadCursor.joystickpressed(joystick, button)
  if GamepadMap.ignoreRawForJoystick(joystick) then return nil end
  if GamepadMap.isAccelerometer(joystick) then return nil end
  local padButton = GamepadMap.mapRawToGamepadButton(button)
  if padButton then return PadCursor.gamepadpressed(joystick, padButton) end
  return nil
end

function PadCursor.joystickreleased(joystick, button)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
  local padButton = GamepadMap.mapRawToGamepadButton(button)
  if padButton then PadCursor.gamepadreleased(joystick, padButton) end
end

function PadCursor.joystickaxis(joystick, axisIndex, value)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
  if axisIndex == 1 then
    PadCursor.gamepadaxis(joystick, "leftx", value)
  elseif axisIndex == 2 then
    PadCursor.gamepadaxis(joystick, "lefty", value)
  end
end

function PadCursor.joystickhat(joystick, hat, direction)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
  for _, d in ipairs(rawHatDirs[hat] or {}) do
    dir[d] = nil
  end
  local dirs = ({
    u = { "dpup" }, d = { "dpdown" }, l = { "dpleft" }, r = { "dpright" },
    lu = { "dpleft", "dpup" }, ru = { "dpright", "dpup" },
    ld = { "dpleft", "dpdown" }, rd = { "dpright", "dpdown" },
  })[direction] or {}
  for _, d in ipairs(dirs) do dir[d] = true end
  rawHatDirs[hat] = dirs
  if #dirs > 0 then activate() end
end

function PadCursor.draw()
  if not active then return end
  if not (love and love.graphics) then return end
  local x, y = cursor.x, cursor.y
  love.graphics.push("all")
  if love.graphics.origin then love.graphics.origin() end
  if love.graphics.setLineWidth then love.graphics.setLineWidth(1) end
  love.graphics.setColor(0, 0, 0, 0.45)
  if love.graphics.polygon then
    love.graphics.polygon("fill",
      x + 2, y + 2, x + 2, y + 22, x + 8, y + 16, x + 14, y + 26,
      x + 18, y + 24, x + 11, y + 14, x + 20, y + 14)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.polygon("fill",
      x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
      x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
    love.graphics.setColor(0.05, 0.07, 0.12, 1)
    love.graphics.polygon("line",
      x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
      x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
  else
    love.graphics.rectangle("fill", x, y, 12, 18)
  end
  love.graphics.pop()
end

return PadCursor
