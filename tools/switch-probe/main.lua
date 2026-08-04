-- Minimal love-nx hardware probe. NOT FOR RELEASE — dev-only diagnostic.
-- Draws runtime facts and logs input events to help validate Phase 0 on OLED.

local lines = {}
local log = {}
local maxLog = 24

local function push(msg)
  log[#log + 1] = msg
  if #log > maxLog then table.remove(log, 1) end
end

local function refreshStatic()
  lines = {}
  local osName = love.system.getOS()
  lines[#lines + 1] = "switch-probe — NOT FOR RELEASE"
  lines[#lines + 1] = "getOS(): " .. tostring(osName)
  local w, h = love.graphics.getDimensions()
  lines[#lines + 1] = ("dimensions: %d x %d"):format(w, h)
  lines[#lines + 1] = "save: " .. tostring(love.filesystem.getSaveDirectory())
  if love._os then
    lines[#lines + 1] = "love._os: " .. tostring(love._os)
  end
end

function love.load()
  love.graphics.setBackgroundColor(0.08, 0.1, 0.16)
  refreshStatic()
  push("load")
end

function love.gamepadpressed(joystick, button)
  push(("gamepadpressed %s %s"):format(joystick:getName(), tostring(button)))
end

function love.gamepadreleased(joystick, button)
  push(("gamepadreleased %s %s"):format(joystick:getName(), tostring(button)))
end

function love.joystickpressed(joystick, button)
  push(("joystickpressed %s #%s"):format(joystick:getName(), tostring(button)))
end

function love.joystickreleased(joystick, button)
  push(("joystickreleased %s #%s"):format(joystick:getName(), tostring(button)))
end

function love.touchpressed(id, x, y, dx, dy, pressure)
  push(("touchpressed id=%s (%.0f,%.0f)"):format(tostring(id), x, y))
end

function love.touchreleased(id, x, y, dx, dy, pressure)
  push(("touchreleased id=%s (%.0f,%.0f)"):format(tostring(id), x, y))
end

function love.draw()
  refreshStatic()
  love.graphics.setColor(0.9, 0.92, 1)
  local y = 16
  for _, line in ipairs(lines) do
    love.graphics.print(line, 16, y)
    y = y + 22
  end
  love.graphics.print("— event log —", 16, y + 8)
  y = y + 30
  for _, line in ipairs(log) do
    love.graphics.print(line, 16, y)
    y = y + 18
  end
end
