---@class GestureRecognizer
---@field _touches table<string, table> -- Current touch states
---@field _gestureStates table -- Active gesture states
---@field _config table -- Gesture configuration (thresholds, etc.)
---@field _InputEvent table
---@field _utils table
local GestureRecognizer = {}
GestureRecognizer.__index = GestureRecognizer

-- Gesture types enum
local GestureType = {
  TAP = "tap",
  DOUBLE_TAP = "double_tap",
  LONG_PRESS = "long_press",
  SWIPE = "swipe",
  PAN = "pan",
  PINCH = "pinch",
  ROTATE = "rotate",
}

-- Gesture states
local GestureState = {
  POSSIBLE = "possible",
  BEGAN = "began",
  CHANGED = "changed",
  ENDED = "ended",
  CANCELLED = "cancelled",
  FAILED = "failed",
}

-- Default configuration
local defaultConfig = {
  -- Tap gesture
  tapMaxDuration = 0.3, -- seconds
  tapMaxMovement = 10, -- pixels

  -- Double-tap gesture
  doubleTapInterval = 0.3, -- seconds between taps

  -- Long-press gesture
  longPressMinDuration = 0.5, -- seconds
  longPressMaxMovement = 10, -- pixels

  -- Swipe gesture
  swipeMinDistance = 50, -- pixels
  swipeMaxDuration = 0.2, -- seconds
  swipeMinVelocity = 200, -- pixels per second

  -- Pan gesture
  panMinMovement = 5, -- pixels to start pan

  -- Pinch gesture
  pinchMinScaleChange = 0.1, -- 10% scale change

  -- Rotate gesture
  rotateMinAngleChange = 5, -- degrees
}

--- Create a new GestureRecognizer instance
---@param config table? Optional configuration options
---@param deps table Dependencies {InputEvent, utils}
---@return GestureRecognizer
function GestureRecognizer.new(config, deps)
  config = config or {}

  local self = setmetatable({}, GestureRecognizer)

  self._InputEvent = deps.InputEvent
  self._utils = deps.utils

  -- Merge configuration with defaults
  self._config = {}
  for key, value in pairs(defaultConfig) do
    self._config[key] = config[key] or value
  end

  self._touches = {}
  self._gestureStates = {
    tap = nil,
    doubleTap = { lastTapTime = 0, tapCount = 0 },
    longPress = {},
    swipe = {},
    pan = {},
    pinch = {},
    rotate = {},
  }

  return self
end

--- Update gesture recognizer with touch event
---@param event InputEvent Touch event
function GestureRecognizer:processTouchEvent(event)
  if not event.touchId then
    return nil
  end

  local touchId = event.touchId
  local gestures = {}

  -- Update touch state
  if event.type == "touchpress" then
    self._touches[touchId] = {
      startX = event.x,
      startY = event.y,
      x = event.x,
      y = event.y,
      startTime = event.timestamp,
      lastTime = event.timestamp,
      phase = "began",
    }

    -- Initialize gesture detection
    self:_detectTapBegan(touchId, event)
    self:_detectLongPressBegan(touchId, event)
  elseif event.type == "touchmove" then
    local touch = self._touches[touchId]
    if touch then
      touch.x = event.x
      touch.y = event.y
      touch.lastTime = event.timestamp
      touch.phase = "moved"

      -- Update gesture detection
      local panGesture = self:_detectPan(touchId, event)
      if panGesture then
        table.insert(gestures, panGesture)
      end
      local swipeGesture = self:_detectSwipe(touchId, event)
      if swipeGesture then
        table.insert(gestures, swipeGesture)
      end

      -- Multi-touch gestures
      if self:_getTouchCount() >= 2 then
        local pinchGesture = self:_detectPinch(event)
        if pinchGesture then
          table.insert(gestures, pinchGesture)
        end
        local rotateGesture = self:_detectRotate(event)
        if rotateGesture then
          table.insert(gestures, rotateGesture)
        end
      end
    end
  elseif event.type == "touchrelease" then
    local touch = self._touches[touchId]
    if touch then
      touch.phase = "ended"

      -- Finalize gesture detection
      local tapGesture = self:_detectTapEnded(touchId, event)
      if tapGesture then
        table.insert(gestures, tapGesture)
      end
      local swipeGesture = self:_detectSwipeEnded(touchId, event)
      if swipeGesture then
        table.insert(gestures, swipeGesture)
      end
      local panGesture = self:_detectPanEnded(touchId, event)
      if panGesture then
        table.insert(gestures, panGesture)
      end

      -- Cleanup touch
      self._touches[touchId] = nil
    end
  elseif event.type == "touchcancel" then
    -- Cancel all active gestures for this touch
    self._touches[touchId] = nil
    self:_cancelAllGestures()
  end

  return #gestures > 0 and gestures or nil
end

--- Get number of active touches
---@return number
function GestureRecognizer:_getTouchCount()
  local count = 0
  for _ in pairs(self._touches) do
    count = count + 1
  end
  return count
end

--- Detect tap gesture began
---@param touchId string
---@param event InputEvent
function GestureRecognizer:_detectTapBegan(touchId, event)
  -- Tap detection happens on touch end
  -- Just record the touch for now
end

--- Detect tap gesture ended
---@param touchId string
---@param event InputEvent
function GestureRecognizer:_detectTapEnded(touchId, event)
  local touch = self._touches[touchId]
  if not touch then
    return
  end

  local duration = event.timestamp - touch.startTime
  local dx = event.x - touch.startX
  local dy = event.y - touch.startY
  local distance = math.sqrt(dx * dx + dy * dy)

  -- Check if it's a valid tap
  if duration < self._config.tapMaxDuration and distance < self._config.tapMaxMovement then
    local currentTime = event.timestamp
    local doubleTapState = self._gestureStates.doubleTap

    -- Check for double-tap
    if currentTime - doubleTapState.lastTapTime < self._config.doubleTapInterval then
      doubleTapState.tapCount = doubleTapState.tapCount + 1

      if doubleTapState.tapCount >= 2 then
        -- Fire double-tap gesture
        return {
          type = GestureType.DOUBLE_TAP,
          state = GestureState.ENDED,
          x = event.x,
          y = event.y,
          timestamp = event.timestamp,
        }
      end
    else
      doubleTapState.tapCount = 1
    end

    doubleTapState.lastTapTime = currentTime

    -- Fire tap gesture
    return {
      type = GestureType.TAP,
      state = GestureState.ENDED,
      x = event.x,
      y = event.y,
      timestamp = event.timestamp,
    }
  end
end

--- Detect long-press gesture began
---@param touchId string
---@param event InputEvent
function GestureRecognizer:_detectLongPressBegan(touchId, event)
  -- Long-press detection happens continuously during touch
  self._gestureStates.longPress[touchId] = {
    startX = event.x,
    startY = event.y,
    startTime = event.timestamp,
    triggered = false,
  }
end

--- Detect pan gesture
---@param touchId string
---@param event InputEvent
---@return table? Gesture event
function GestureRecognizer:_detectPan(touchId, event)
  local touch = self._touches[touchId]
  if not touch then
    return nil
  end

  local dx = event.x - touch.startX
  local dy = event.y - touch.startY
  local distance = math.sqrt(dx * dx + dy * dy)

  local panState = self._gestureStates.pan[touchId]

  if not panState then
    -- Check if pan should begin
    if distance >= self._config.panMinMovement then
      self._gestureStates.pan[touchId] = {
        active = true,
        lastX = touch.startX,
        lastY = touch.startY,
      }
      panState = self._gestureStates.pan[touchId]

      return {
        type = GestureType.PAN,
        state = GestureState.BEGAN,
        x = event.x,
        y = event.y,
        dx = dx,
        dy = dy,
        timestamp = event.timestamp,
      }
    end
  else
    -- Pan is active, fire changed event
    local panDx = event.x - panState.lastX
    local panDy = event.y - panState.lastY

    panState.lastX = event.x
    panState.lastY = event.y

    return {
      type = GestureType.PAN,
      state = GestureState.CHANGED,
      x = event.x,
      y = event.y,
      dx = panDx,
      dy = panDy,
      totalDx = dx,
      totalDy = dy,
      timestamp = event.timestamp,
    }
  end

  return nil
end

--- Detect pan ended
---@param touchId string
---@param event InputEvent
---@return table? Gesture event
function GestureRecognizer:_detectPanEnded(touchId, event)
  local panState = self._gestureStates.pan[touchId]
  if panState and panState.active then
    self._gestureStates.pan[touchId] = nil

    local touch = self._touches[touchId]
    local dx = event.x - touch.startX
    local dy = event.y - touch.startY

    return {
      type = GestureType.PAN,
      state = GestureState.ENDED,
      x = event.x,
      y = event.y,
      dx = dx,
      dy = dy,
      timestamp = event.timestamp,
    }
  end

  return nil
end

--- Detect swipe gesture
---@param touchId string
---@param event InputEvent
function GestureRecognizer:_detectSwipe(touchId, event)
  -- Swipe detection happens on touch end
end

--- Detect swipe ended
---@param touchId string
---@param event InputEvent
---@return table? Gesture event
function GestureRecognizer:_detectSwipeEnded(touchId, event)
  local touch = self._touches[touchId]
  if not touch then
    return nil
  end

  local duration = event.timestamp - touch.startTime
  local dx = event.x - touch.startX
  local dy = event.y - touch.startY
  local distance = math.sqrt(dx * dx + dy * dy)

  -- Check if it's a valid swipe
  if distance >= self._config.swipeMinDistance and duration <= self._config.swipeMaxDuration then
    local velocity = distance / duration

    if velocity >= self._config.swipeMinVelocity then
      -- Determine swipe direction
      local angle = math.atan2(dy, dx)
      local direction = "right"

      if angle >= -math.pi / 4 and angle < math.pi / 4 then
        direction = "right"
      elseif angle >= math.pi / 4 and angle < 3 * math.pi / 4 then
        direction = "down"
      elseif angle >= -3 * math.pi / 4 and angle < -math.pi / 4 then
        direction = "up"
      else
        direction = "left"
      end

      return {
        type = GestureType.SWIPE,
        state = GestureState.ENDED,
        x = event.x,
        y = event.y,
        dx = dx,
        dy = dy,
        direction = direction,
        velocity = velocity,
        timestamp = event.timestamp,
      }
    end
  end

  return nil
end

--- Detect pinch gesture
---@param event InputEvent
---@return table? Gesture event
function GestureRecognizer:_detectPinch(event)
  -- Get two touches for pinch
  local touches = {}
  for touchId, touch in pairs(self._touches) do
    table.insert(touches, { id = touchId, touch = touch })
    if #touches >= 2 then
      break
    end
  end

  if #touches < 2 then
    return nil
  end

  local t1 = touches[1].touch
  local t2 = touches[2].touch

  -- Calculate current distance
  local currentDx = t2.x - t1.x
  local currentDy = t2.y - t1.y
  local currentDistance = math.sqrt(currentDx * currentDx + currentDy * currentDy)

  -- Calculate initial distance
  local initialDx = t2.startX - t1.startX
  local initialDy = t2.startY - t1.startY
  local initialDistance = math.sqrt(initialDx * initialDx + initialDy * initialDy)

  if initialDistance == 0 then
    return nil
  end

  -- Calculate scale
  local scale = currentDistance / initialDistance
  local pinchState = self._gestureStates.pinch

  if not pinchState.active then
    -- Check if pinch should begin
    if math.abs(scale - 1.0) >= self._config.pinchMinScaleChange then
      pinchState.active = true
      pinchState.initialScale = scale
      pinchState.lastScale = scale

      -- Calculate center point
      local centerX = (t1.x + t2.x) / 2
      local centerY = (t1.y + t2.y) / 2

      return {
        type = GestureType.PINCH,
        state = GestureState.BEGAN,
        scale = scale,
        centerX = centerX,
        centerY = centerY,
        timestamp = event.timestamp,
      }
    end
  else
    -- Pinch is active, fire changed event
    local centerX = (t1.x + t2.x) / 2
    local centerY = (t1.y + t2.y) / 2

    local scaleChange = scale - pinchState.lastScale
    pinchState.lastScale = scale

    return {
      type = GestureType.PINCH,
      state = GestureState.CHANGED,
      scale = scale,
      scaleChange = scaleChange,
      centerX = centerX,
      centerY = centerY,
      timestamp = event.timestamp,
    }
  end

  return nil
end

--- Detect rotate gesture
---@param event InputEvent
---@return table? Gesture event
function GestureRecognizer:_detectRotate(event)
  -- Get two touches for rotation
  local touches = {}
  for touchId, touch in pairs(self._touches) do
    table.insert(touches, { id = touchId, touch = touch })
    if #touches >= 2 then
      break
    end
  end

  if #touches < 2 then
    return nil
  end

  local t1 = touches[1].touch
  local t2 = touches[2].touch

  -- Calculate current angle
  local currentAngle = math.atan2(t2.y - t1.y, t2.x - t1.x)

  -- Calculate initial angle
  local initialAngle = math.atan2(t2.startY - t1.startY, t2.startX - t1.startX)

  -- Calculate rotation (in degrees)
  local rotation = (currentAngle - initialAngle) * 180 / math.pi

  local rotateState = self._gestureStates.rotate

  if not rotateState.active then
    -- Check if rotation should begin
    if math.abs(rotation) >= self._config.rotateMinAngleChange then
      rotateState.active = true
      rotateState.initialRotation = rotation
      rotateState.lastRotation = rotation

      -- Calculate center point
      local centerX = (t1.x + t2.x) / 2
      local centerY = (t1.y + t2.y) / 2

      return {
        type = GestureType.ROTATE,
        state = GestureState.BEGAN,
        rotation = rotation,
        centerX = centerX,
        centerY = centerY,
        timestamp = event.timestamp,
      }
    end
  else
    -- Rotation is active, fire changed event
    local centerX = (t1.x + t2.x) / 2
    local centerY = (t1.y + t2.y) / 2

    local rotationChange = rotation - rotateState.lastRotation
    rotateState.lastRotation = rotation

    return {
      type = GestureType.ROTATE,
      state = GestureState.CHANGED,
      rotation = rotation,
      rotationChange = rotationChange,
      centerX = centerX,
      centerY = centerY,
      timestamp = event.timestamp,
    }
  end

  return nil
end

--- Cancel all active gestures
function GestureRecognizer:_cancelAllGestures()
  for gestureType, state in pairs(self._gestureStates) do
    if type(state) == "table" and state.active then
      state.active = false
    end
  end
end

--- Reset gesture recognizer state
function GestureRecognizer:reset()
  self._touches = {}
  self._gestureStates = {
    tap = nil,
    doubleTap = { lastTapTime = 0, tapCount = 0 },
    longPress = {},
    swipe = {},
    pan = {},
    pinch = { active = false },
    rotate = { active = false },
  }
end

-- Export gesture types and states
GestureRecognizer.GestureType = GestureType
GestureRecognizer.GestureState = GestureState

return GestureRecognizer
