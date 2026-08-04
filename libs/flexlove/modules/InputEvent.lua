---@class InputEvent
---@field type "click"|"press"|"release"|"rightclick"|"middleclick"|"drag"|"hover"|"unhover"|"touchpress"|"touchmove"|"touchrelease"|"touchcancel"
---@field button number -- Mouse button: 1 (left), 2 (right), 3 (middle)
---@field x number -- Mouse/Touch X position
---@field y number -- Mouse/Touch Y position
---@field dx number? -- Delta X from drag/touch start (only for drag/touch events)
---@field dy number? -- Delta Y from drag/touch start (only for drag/touch events)
---@field modifiers {shift:boolean, ctrl:boolean, alt:boolean, super:boolean}
---@field clickCount number -- Number of clicks (for double/triple click detection)
---@field timestamp number -- Time when event occurred
---@field touchId string? -- Touch identifier (for multi-touch)
---@field pressure number? -- Touch pressure (0-1, defaults to 1.0)
---@field phase string? -- Touch phase: "began", "moved", "ended", "cancelled"
local InputEvent = {}
InputEvent.__index = InputEvent

---@class InputEventProps
---@field type "click"|"press"|"release"|"rightclick"|"middleclick"|"drag"|"hover"|"unhover"|"touchpress"|"touchmove"|"touchrelease"|"touchcancel"
---@field button number
---@field x number
---@field y number
---@field dx number?
---@field dy number?
---@field modifiers {shift:boolean, ctrl:boolean, alt:boolean, super:boolean}
---@field clickCount number?
---@field timestamp number?
---@field touchId string?
---@field pressure number?
---@field phase string?

--- Create a new input event
---@param props InputEventProps
---@return InputEvent
function InputEvent.new(props)
  local self = setmetatable({}, InputEvent)
  self.type = props.type
  self.button = props.button
  self.x = props.x
  self.y = props.y
  self.dx = props.dx
  self.dy = props.dy
  self.modifiers = props.modifiers
  self.clickCount = props.clickCount or 1
  self.timestamp = props.timestamp or love.timer.getTime()

  -- Touch-specific properties
  self.touchId = props.touchId
  self.pressure = props.pressure or 1.0
  self.phase = props.phase

  return self
end

--- Create an InputEvent from LÖVE touch data
---@param id userdata Touch ID from LÖVE
---@param x number Touch X position
---@param y number Touch Y position
---@param phase string Touch phase: "began", "moved", "ended", "cancelled"
---@param pressure number? Touch pressure (0-1, defaults to 1.0)
---@return InputEvent
function InputEvent.fromTouch(id, x, y, phase, pressure)
  local touchIdStr = tostring(id)
  local eventType = "touchpress"
  if phase == "moved" then
    eventType = "touchmove"
  elseif phase == "ended" then
    eventType = "touchrelease"
  elseif phase == "cancelled" then
    eventType = "touchcancel"
  end

  return InputEvent.new({
    type = eventType,
    button = 1, -- Treat touch as left button
    x = x,
    y = y,
    dx = 0,
    dy = 0,
    modifiers = { shift = false, ctrl = false, alt = false, super = false },
    clickCount = 1,
    timestamp = love.timer.getTime(),
    touchId = touchIdStr,
    pressure = pressure or 1.0,
    phase = phase,
  })
end

return InputEvent
