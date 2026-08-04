local Easing = {}

---@type EasingFunction
function Easing.linear(t)
  return t
end

---@type EasingFunction
function Easing.easeInQuad(t)
  return t * t
end

---@type EasingFunction
function Easing.easeOutQuad(t)
  return t * (2 - t)
end

---@type EasingFunction
function Easing.easeInOutQuad(t)
  return t < 0.5 and 2 * t * t or -1 + (4 - 2 * t) * t
end

---@type EasingFunction
function Easing.easeInCubic(t)
  return t * t * t
end

---@type EasingFunction
function Easing.easeOutCubic(t)
  local t1 = t - 1
  return t1 * t1 * t1 + 1
end

---@type EasingFunction
function Easing.easeInOutCubic(t)
  return t < 0.5 and 4 * t * t * t or (t - 1) * (2 * t - 2) * (2 * t - 2) + 1
end

---@type EasingFunction
function Easing.easeInQuart(t)
  return t * t * t * t
end

---@type EasingFunction
function Easing.easeOutQuart(t)
  local t1 = t - 1
  return 1 - t1 * t1 * t1 * t1
end

---@type EasingFunction
function Easing.easeInOutQuart(t)
  if t < 0.5 then
    return 8 * t * t * t * t
  else
    local t1 = t - 1
    return 1 - 8 * t1 * t1 * t1 * t1
  end
end

---@type EasingFunction
function Easing.easeInQuint(t)
  return t * t * t * t * t
end

---@type EasingFunction
function Easing.easeOutQuint(t)
  local t1 = t - 1
  return 1 + t1 * t1 * t1 * t1 * t1
end

---@type EasingFunction
function Easing.easeInOutQuint(t)
  if t < 0.5 then
    return 16 * t * t * t * t * t
  else
    local t1 = t - 1
    return 1 + 16 * t1 * t1 * t1 * t1 * t1
  end
end

---@type EasingFunction
function Easing.easeInExpo(t)
  return t == 0 and 0 or math.pow(2, 10 * (t - 1))
end

---@type EasingFunction
function Easing.easeOutExpo(t)
  return t == 1 and 1 or 1 - math.pow(2, -10 * t)
end

---@type EasingFunction
function Easing.easeInOutExpo(t)
  if t == 0 then
    return 0
  end
  if t == 1 then
    return 1
  end

  if t < 0.5 then
    return 0.5 * math.pow(2, 20 * t - 10)
  else
    return 1 - 0.5 * math.pow(2, -20 * t + 10)
  end
end

---@type EasingFunction
function Easing.easeInSine(t)
  return 1 - math.cos(t * math.pi / 2)
end

---@type EasingFunction
function Easing.easeOutSine(t)
  return math.sin(t * math.pi / 2)
end

---@type EasingFunction
function Easing.easeInOutSine(t)
  return -(math.cos(math.pi * t) - 1) / 2
end

---@type EasingFunction
function Easing.easeInCirc(t)
  return 1 - math.sqrt(1 - t * t)
end

---@type EasingFunction
function Easing.easeOutCirc(t)
  local t1 = t - 1
  return math.sqrt(1 - t1 * t1)
end

---@type EasingFunction
function Easing.easeInOutCirc(t)
  if t < 0.5 then
    return (1 - math.sqrt(1 - 4 * t * t)) / 2
  else
    local t1 = -2 * t + 2
    return (math.sqrt(1 - t1 * t1) + 1) / 2
  end
end

---@type EasingFunction
function Easing.easeInBack(t)
  local c1 = 1.70158
  local c3 = c1 + 1
  return c3 * t * t * t - c1 * t * t
end

---@type EasingFunction
function Easing.easeOutBack(t)
  local c1 = 1.70158
  local c3 = c1 + 1
  local t1 = t - 1
  return 1 + c3 * t1 * t1 * t1 + c1 * t1 * t1
end

---@type EasingFunction
function Easing.easeInOutBack(t)
  local c1 = 1.70158
  local c2 = c1 * 1.525

  if t < 0.5 then
    return (2 * t * 2 * t * ((c2 + 1) * 2 * t - c2)) / 2
  else
    local t1 = 2 * t - 2
    return (t1 * t1 * ((c2 + 1) * t1 + c2) + 2) / 2
  end
end

---@type EasingFunction
function Easing.easeInElastic(t)
  if t == 0 then
    return 0
  end
  if t == 1 then
    return 1
  end

  local c4 = (2 * math.pi) / 3
  return -math.pow(2, 10 * t - 10) * math.sin((t * 10 - 10.75) * c4)
end

---@type EasingFunction
function Easing.easeOutElastic(t)
  if t == 0 then
    return 0
  end
  if t == 1 then
    return 1
  end

  local c4 = (2 * math.pi) / 3
  return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c4) + 1
end

---@type EasingFunction
function Easing.easeInOutElastic(t)
  if t == 0 then
    return 0
  end
  if t == 1 then
    return 1
  end

  local c5 = (2 * math.pi) / 4.5

  if t < 0.5 then
    return -(math.pow(2, 20 * t - 10) * math.sin((20 * t - 11.125) * c5)) / 2
  else
    return (math.pow(2, -20 * t + 10) * math.sin((20 * t - 11.125) * c5)) / 2 + 1
  end
end

---@type EasingFunction
function Easing.easeOutBounce(t)
  local n1 = 7.5625
  local d1 = 2.75

  if t < 1 / d1 then
    return n1 * t * t
  elseif t < 2 / d1 then
    local t1 = t - 1.5 / d1
    return n1 * t1 * t1 + 0.75
  elseif t < 2.5 / d1 then
    local t1 = t - 2.25 / d1
    return n1 * t1 * t1 + 0.9375
  else
    local t1 = t - 2.625 / d1
    return n1 * t1 * t1 + 0.984375
  end
end

---@type EasingFunction
function Easing.easeInBounce(t)
  return 1 - Easing.easeOutBounce(1 - t)
end

---@type EasingFunction
function Easing.easeInOutBounce(t)
  if t < 0.5 then
    return (1 - Easing.easeOutBounce(1 - 2 * t)) / 2
  else
    return (1 + Easing.easeOutBounce(2 * t - 1)) / 2
  end
end

--- Create a custom back easing function with configurable overshoot
---@param overshoot number? Overshoot amount (default: 1.70158)
---@return EasingFunction
function Easing.back(overshoot)
  overshoot = overshoot or 1.70158
  local c3 = overshoot + 1

  return function(t)
    return c3 * t * t * t - overshoot * t * t
  end
end

--- Create a custom elastic easing function
---@param amplitude number? Amplitude (default: 1)
---@param period number? Period (default: 0.3)
---@return EasingFunction
function Easing.elastic(amplitude, period)
  amplitude = amplitude or 1
  period = period or 0.3

  return function(t)
    if t == 0 then
      return 0
    end
    if t == 1 then
      return 1
    end

    local s = period / 4
    local a = amplitude

    if a < 1 then
      a = 1
      s = period / 4
    else
      s = period / (2 * math.pi) * math.asin(1 / a)
    end

    return a * math.pow(2, -10 * t) * math.sin((t - s) * (2 * math.pi) / period) + 1
  end
end

-- ============================================================================
-- TRANSFORM
-- ============================================================================

local Transform = {}
Transform.__index = Transform

--- Create a new transform instance
---@param props Transform?
---@return Transform transform
function Transform.new(props)
  props = props or {}

  local self = setmetatable({}, Transform)

  self.rotate = props.rotate or 0
  self.scaleX = props.scaleX or 1
  self.scaleY = props.scaleY or 1
  self.translateX = props.translateX or 0
  self.translateY = props.translateY or 0
  self.skewX = props.skewX or 0
  self.skewY = props.skewY or 0
  self.originX = props.originX or 0.5
  self.originY = props.originY or 0.5

  return self
end

--- Apply transform to LÖVE graphics context
---@param transform Transform Transform instance
---@param x number Element x position
---@param y number Element y position
---@param width number Element width
---@param height number Element height
function Transform.apply(transform, x, y, width, height)
  if not transform then
    return
  end

  local ox = x + width * transform.originX
  local oy = y + height * transform.originY

  love.graphics.push()
  love.graphics.translate(ox, oy)

  if transform.rotate ~= 0 then
    love.graphics.rotate(transform.rotate)
  end

  if transform.scaleX ~= 1 or transform.scaleY ~= 1 then
    love.graphics.scale(transform.scaleX, transform.scaleY)
  end

  if transform.skewX ~= 0 or transform.skewY ~= 0 then
    love.graphics.shear(transform.skewX, transform.skewY)
  end

  love.graphics.translate(-ox, -oy)
  love.graphics.translate(transform.translateX, transform.translateY)
end

--- Remove transform from LÖVE graphics context
function Transform.unapply()
  love.graphics.pop()
end

--- Interpolate between two transforms
---@param from Transform Starting transform
---@param to Transform Ending transform
---@param t number Interpolation factor (0-1)
---@return Transform interpolated
function Transform.lerp(from, to, t)
  if type(from) ~= "table" then
    from = Transform.new()
  end
  if type(to) ~= "table" then
    to = Transform.new()
  end
  if type(t) ~= "number" or t ~= t then
    t = 0
  elseif t == math.huge then
    t = 1
  elseif t == -math.huge then
    t = 0
  else
    t = math.max(0, math.min(1, t))
  end

  return Transform.new({
    rotate = (from.rotate or 0) * (1 - t) + (to.rotate or 0) * t,
    scaleX = (from.scaleX or 1) * (1 - t) + (to.scaleX or 1) * t,
    scaleY = (from.scaleY or 1) * (1 - t) + (to.scaleY or 1) * t,
    translateX = (from.translateX or 0) * (1 - t) + (to.translateX or 0) * t,
    translateY = (from.translateY or 0) * (1 - t) + (to.translateY or 0) * t,
    skewX = (from.skewX or 0) * (1 - t) + (to.skewX or 0) * t,
    skewY = (from.skewY or 0) * (1 - t) + (to.skewY or 0) * t,
    originX = (from.originX or 0.5) * (1 - t) + (to.originX or 0.5) * t,
    originY = (from.originY or 0.5) * (1 - t) + (to.originY or 0.5) * t,
  })
end

--- Check if transform is identity (no transformation)
---@param transform Transform
---@return boolean isIdentity
function Transform.isIdentity(transform)
  if not transform then
    return true
  end

  return transform.rotate == 0
    and transform.scaleX == 1
    and transform.scaleY == 1
    and transform.translateX == 0
    and transform.translateY == 0
    and transform.skewX == 0
    and transform.skewY == 0
end

--- Clone a transform
---@param transform Transform
---@return Transform clone
function Transform.clone(transform)
  if not transform then
    return Transform.new()
  end

  return Transform.new({
    rotate = transform.rotate,
    scaleX = transform.scaleX,
    scaleY = transform.scaleY,
    translateX = transform.translateX,
    translateY = transform.translateY,
    skewX = transform.skewX,
    skewY = transform.skewY,
    originX = transform.originX,
    originY = transform.originY,
  })
end

-- ============================================================================
-- INTERPOLATION HELPERS
-- ============================================================================

--- Helper function to interpolate numeric values
---@param startValue number Starting value
---@param finalValue number Final value
---@param easedT number Eased time (0-1)
---@return number interpolated Interpolated value
local function lerpNumber(startValue, finalValue, easedT)
  return startValue * (1 - easedT) + finalValue * easedT
end

--- Helper function to interpolate Color values
---@param startColor any Starting color (Color instance or parseable color)
---@param finalColor any Final color (Color instance or parseable color)
---@param easedT number Eased time (0-1)
---@param ColorModule table Color module reference
---@return any interpolated Interpolated Color instance
local function lerpColor(startColor, finalColor, easedT, ColorModule)
  if not ColorModule or not ColorModule.parse or not ColorModule.lerp then
    return startColor
  end

  local colorA = ColorModule.parse(startColor)
  local colorB = ColorModule.parse(finalColor)

  return ColorModule.lerp(colorA, colorB, easedT)
end

--- Helper function to interpolate table values (padding, margin, cornerRadius)
---@param startTable table Starting table
---@param finalTable table Final table
---@param easedT number Eased time (0-1)
---@return table interpolated Interpolated table
local function lerpTable(startTable, finalTable, easedT)
  local result = {}

  local keys = {}
  for k in pairs(startTable) do
    keys[k] = true
  end
  for k in pairs(finalTable) do
    keys[k] = true
  end

  for key in pairs(keys) do
    local startVal = startTable[key]
    local finalVal = finalTable[key]

    if type(startVal) == "number" and type(finalVal) == "number" then
      result[key] = lerpNumber(startVal, finalVal, easedT)
    elseif startVal ~= nil then
      result[key] = startVal
    else
      result[key] = finalVal
    end
  end

  return result
end

---@class Animation
local Animation = {
  _Transform = Transform,
}
Animation.__index = Animation

--- Build smooth, timed transitions between visual states
---@param props AnimationProps Animation properties
---@return Animation animation The new animation instance
function Animation.new(props)
  if type(props) ~= "table" then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_001")
    end
    props = { duration = 1, start = {}, final = {} }
  end

  if type(props.duration) ~= "number" or props.duration <= 0 then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_002")
    end
    props.duration = 1
  end

  if type(props.start) ~= "table" then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_001")
    end
    props.start = {}
  end

  if type(props.final) ~= "table" then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_001")
    end
    props.final = {}
  end

  local self = setmetatable({}, Animation)
  self.duration = props.duration
  self.start = props.start
  self.final = props.final
  self.keyframes = props.keyframes
  self.transform = props.transform
  self.transition = props.transition
  self.elapsed = 0

  self.onStart = props.onStart
  self.onUpdate = props.onUpdate
  self.onComplete = props.onComplete
  self.onCancel = props.onCancel
  self._hasStarted = false

  self._paused = false
  self._reversed = false
  self._speed = 1.0
  self._state = "pending"

  local easingName = props.easing or "linear"
  if type(easingName) == "string" then
    self.easing = Easing[easingName] or Easing.linear
  elseif type(easingName) == "function" then
    self.easing = easingName
  else
    self.easing = Easing.linear
  end

  self._cachedResult = {}
  self._resultDirty = true

  return self
end

--- Advance the animation timeline
---@param dt number Delta time in seconds
---@param element table? Optional element reference for callbacks
---@return boolean completed True if animation is complete
function Animation:update(dt, element)
  if type(dt) ~= "number" or dt < 0 or dt ~= dt or dt == math.huge then
    dt = 0
  end

  if self._paused then
    return false
  end

  if self._delay and self._delayElapsed then
    if self._delayElapsed < self._delay then
      self._delayElapsed = self._delayElapsed + dt
      return false
    end
  end

  if not self._hasStarted then
    self._hasStarted = true
    self._state = "playing"
    if self.onStart and type(self.onStart) == "function" then
      local success, err = pcall(self.onStart, self, element)
      if not success then
        Animation._ErrorHandler:warn("Animation", "EVT_002", {
          callback = "onStart",
          error = tostring(err),
        })
      end
    end
  end

  dt = dt * self._speed

  if self._reversed then
    self.elapsed = self.elapsed - dt
    if self.elapsed <= 0 then
      self.elapsed = 0
      self._state = "completed"
      self._resultDirty = true
      if self.onComplete and type(self.onComplete) == "function" then
        local success, err = pcall(self.onComplete, self, element)
        if not success then
          Animation._ErrorHandler:warn("Animation", "EVT_002", {
            callback = "onComplete",
            error = tostring(err),
          })
        end
      end
      return true
    end
  else
    self.elapsed = self.elapsed + dt
    if self.elapsed >= self.duration then
      self.elapsed = self.duration
      self._resultDirty = true

      if self._repeatCount then
        self._repeatCurrent = (self._repeatCurrent or 0) + 1

        if self._repeatCount == 0 or self._repeatCurrent < self._repeatCount then
          if self._yoyo then
            self._reversed = not self._reversed
            if self._reversed then
              self.elapsed = self.duration
            else
              self.elapsed = 0
            end
          else
            self.elapsed = 0
          end
          return false
        end
      end

      self._state = "completed"
      if self.onComplete and type(self.onComplete) == "function" then
        local success, err = pcall(self.onComplete, self, element)
        if not success then
          Animation._ErrorHandler:warn("Animation", "EVT_002", {
            callback = "onComplete",
            error = tostring(err),
          })
        end
      end
      return true
    end
  end

  self._resultDirty = true

  if self.onUpdate and type(self.onUpdate) == "function" then
    local progress = self.elapsed / self.duration
    local success, err = pcall(self.onUpdate, self, element, progress)
    if not success then
      Animation._ErrorHandler:warn("Animation", "EVT_002", {
        callback = "onUpdate",
        error = tostring(err),
      })
    end
  end

  return false
end

--- Find the two keyframes surrounding the current progress
---@param progress number Current animation progress (0-1)
---@return Keyframe? prevFrame The keyframe before current progress
---@return Keyframe? nextFrame The keyframe after current progress
function Animation:findKeyframes(progress)
  if not self.keyframes or #self.keyframes < 2 then
    return nil, nil
  end

  local prevFrame = self.keyframes[1]
  local nextFrame = self.keyframes[#self.keyframes]

  for i = 1, #self.keyframes - 1 do
    if progress >= self.keyframes[i].at and progress <= self.keyframes[i + 1].at then
      prevFrame = self.keyframes[i]
      nextFrame = self.keyframes[i + 1]
      break
    end
  end

  return prevFrame, nextFrame
end

--- Interpolate between two keyframes
---@param prevFrame Keyframe Starting keyframe
---@param nextFrame Keyframe Ending keyframe
---@param easedT number Eased time (0-1) for interpolation
---@return table result Interpolated values
function Animation:lerpKeyframes(prevFrame, nextFrame, easedT)
  local result = {}

  local keys = {}
  for k in pairs(prevFrame.values) do
    keys[k] = true
  end
  for k in pairs(nextFrame.values) do
    keys[k] = true
  end

  local numericSet = {
    width = true,
    height = true,
    opacity = true,
    x = true,
    y = true,
    gap = true,
    imageOpacity = true,
    scrollbarWidth = true,
    borderWidth = true,
    fontSize = true,
    lineHeight = true,
  }

  local colorSet = {
    backgroundColor = true,
    borderColor = true,
    textColor = true,
    scrollbarColor = true,
    scrollbarBackgroundColor = true,
    imageTint = true,
  }

  local tableSet = {
    padding = true,
    margin = true,
    cornerRadius = true,
  }

  for key in pairs(keys) do
    local startVal = prevFrame.values[key]
    local finalVal = nextFrame.values[key]

    if numericSet[key] and type(startVal) == "number" and type(finalVal) == "number" then
      result[key] = lerpNumber(startVal, finalVal, easedT)
    elseif colorSet[key] and Animation._ColorModule then
      if startVal ~= nil and finalVal ~= nil then
        result[key] = lerpColor(startVal, finalVal, easedT, Animation._ColorModule)
      end
    elseif tableSet[key] and type(startVal) == "table" and type(finalVal) == "table" then
      result[key] = lerpTable(startVal, finalVal, easedT)
    elseif type(startVal) == type(finalVal) then
      if type(startVal) == "number" then
        result[key] = lerpNumber(startVal, finalVal, easedT)
      else
        result[key] = finalVal
      end
    end
  end

  return result
end

--- Calculate the current animated values
---@return table result Interpolated values
function Animation:interpolate()
  if not self._resultDirty then
    return self._cachedResult
  end

  local t = math.min(self.elapsed / self.duration, 1)

  if self.keyframes and type(self.keyframes) == "table" and #self.keyframes >= 2 then
    local prevFrame, nextFrame = self:findKeyframes(t)

    if prevFrame and nextFrame then
      local localProgress = 0
      if nextFrame.at > prevFrame.at then
        localProgress = (t - prevFrame.at) / (nextFrame.at - prevFrame.at)
      end

      local easingFn = Easing.linear
      if prevFrame.easing then
        if type(prevFrame.easing) == "string" then
          easingFn = Easing[prevFrame.easing] or Easing.linear
        elseif type(prevFrame.easing) == "function" then
          easingFn = prevFrame.easing
        end
      end

      local success, easedT = pcall(easingFn, localProgress)
      if not success or type(easedT) ~= "number" or easedT ~= easedT or easedT == math.huge or easedT == -math.huge then
        easedT = localProgress
      end

      local keyframeResult = self:lerpKeyframes(prevFrame, nextFrame, easedT)

      local result = self._cachedResult
      for k in pairs(result) do
        result[k] = nil
      end
      for k, v in pairs(keyframeResult) do
        result[k] = v
      end

      self._resultDirty = false
      return result
    end
  end

  local success, easedT = pcall(self.easing, t)
  if not success or type(easedT) ~= "number" or easedT ~= easedT or easedT == math.huge or easedT == -math.huge then
    easedT = t
  end

  local result = self._cachedResult

  for k in pairs(result) do
    result[k] = nil
  end

  local numericProperties = {
    "width",
    "height",
    "opacity",
    "x",
    "y",
    "gap",
    "imageOpacity",
    "scrollbarWidth",
    "borderWidth",
    "fontSize",
    "lineHeight",
  }

  local colorProperties = {
    "backgroundColor",
    "borderColor",
    "textColor",
    "scrollbarColor",
    "scrollbarBackgroundColor",
    "imageTint",
  }

  local tableProperties = {
    "padding",
    "margin",
    "cornerRadius",
  }

  for _, prop in ipairs(numericProperties) do
    local startVal = self.start[prop]
    local finalVal = self.final[prop]

    if type(startVal) == "number" and type(finalVal) == "number" then
      result[prop] = lerpNumber(startVal, finalVal, easedT)
    end
  end

  if Animation._ColorModule then
    for _, prop in ipairs(colorProperties) do
      local startVal = self.start[prop]
      local finalVal = self.final[prop]

      if startVal ~= nil and finalVal ~= nil then
        result[prop] = lerpColor(startVal, finalVal, easedT, Animation._ColorModule)
      end
    end
  end

  for _, prop in ipairs(tableProperties) do
    local startVal = self.start[prop]
    local finalVal = self.final[prop]

    if type(startVal) == "table" and type(finalVal) == "table" then
      result[prop] = lerpTable(startVal, finalVal, easedT)
    end
  end

  if Animation._Transform and self.start.transform and self.final.transform then
    result.transform = Animation._Transform.lerp(self.start.transform, self.final.transform, easedT)
  end

  if self.transform and type(self.transform) == "table" then
    for key, value in pairs(self.transform) do
      result[key] = value
    end
  end

  self._resultDirty = false
  return result
end

--- Attach animation to an element
---@param element table The element to apply animation to
function Animation:apply(element)
  if not element or type(element) ~= "table" then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_003")
    end
    return
  end
  element.animation = self
end

--- Apply interpolated values to an element during update.
--- Called each frame while the animation is active (not yet finished).
---@param element table Element to apply interpolated properties to
function Animation:applyInterpolation(element)
  local anim = self:interpolate()

  -- Numeric properties
  element.width = anim.width or element.width
  element.height = anim.height or element.height
  element.opacity = anim.opacity or element.opacity
  element.x = anim.x or element.x
  element.y = anim.y or element.y
  element.gap = anim.gap or element.gap
  element.imageOpacity = anim.imageOpacity or element.imageOpacity
  element.scrollbarWidth = anim.scrollbarWidth or element.scrollbarWidth
  element.borderWidth = anim.borderWidth or element.borderWidth
  element.fontSize = anim.fontSize or element.fontSize
  element.lineHeight = anim.lineHeight or element.lineHeight

  -- Color properties
  if anim.backgroundColor then
    element.backgroundColor = anim.backgroundColor
  end
  if anim.borderColor then
    element.borderColor = anim.borderColor
  end
  if anim.textColor then
    element.textColor = anim.textColor
  end
  if anim.scrollbarColor then
    element.scrollbarColor = anim.scrollbarColor
  end
  if anim.scrollbarBackgroundColor then
    element.scrollbarBackgroundColor = anim.scrollbarBackgroundColor
  end
  if anim.imageTint then
    element.imageTint = anim.imageTint
  end

  -- Table properties
  if anim.padding then
    element.padding = anim.padding
  end
  if anim.margin then
    element.margin = anim.margin
  end
  if anim.cornerRadius then
    element.cornerRadius = anim.cornerRadius
  end
  if anim.transform then
    element.transform = anim.transform
  end

  -- Backward compatibility: opacity-only animation updates background alpha
  if anim.opacity and not anim.backgroundColor then
    element.backgroundColor.a = anim.opacity
  end
end

--- Pause animation
function Animation:pause()
  if self._state == "playing" or self._state == "pending" then
    self._paused = true
    self._state = "paused"
  end
end

--- Resume animation
function Animation:resume()
  if self._state == "paused" then
    self._paused = false
    self._state = "playing"
  end
end

--- Check if paused
---@return boolean paused
function Animation:isPaused()
  return self._paused
end

--- Reverse animation direction
function Animation:reverse()
  self._reversed = not self._reversed
end

--- Check if reversed
---@return boolean reversed
function Animation:isReversed()
  return self._reversed
end

--- Set playback speed
---@param speed number Speed multiplier
function Animation:setSpeed(speed)
  if type(speed) == "number" and speed > 0 then
    self._speed = speed
  end
end

--- Get playback speed
---@return number speed
function Animation:getSpeed()
  return self._speed
end

--- Seek to specific time
---@param time number Time in seconds
function Animation:seek(time)
  if type(time) == "number" then
    self.elapsed = math.max(0, math.min(time, self.duration))
    self._resultDirty = true
  end
end

--- Get animation state
---@return string state
function Animation:getState()
  return self._state
end

--- Cancel animation
---@param element table? Optional element reference
function Animation:cancel(element)
  if self._state ~= "cancelled" and self._state ~= "completed" then
    self._state = "cancelled"
    if self.onCancel and type(self.onCancel) == "function" then
      local success, err = pcall(self.onCancel, self, element)
      if not success then
        Animation._ErrorHandler:warn("Animation", "EVT_002", {
          callback = "onCancel",
          error = tostring(err),
        })
      end
    end
  end
end

--- Reset animation
function Animation:reset()
  self.elapsed = 0
  self._hasStarted = false
  self._paused = false
  self._state = "pending"
  self._resultDirty = true
end

--- Get animation progress
---@return number progress
function Animation:getProgress()
  return math.min(self.elapsed / self.duration, 1)
end

--- Chain animations
---@param nextAnimation Animation|function
---@return Animation nextAnimation
function Animation:chain(nextAnimation)
  if type(nextAnimation) == "function" then
    self._nextFactory = nextAnimation
    return self
  elseif type(nextAnimation) == "table" then
    self._next = nextAnimation
    return nextAnimation
  else
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_004")
    end
    return self
  end
end

--- Add delay before animation starts
---@param seconds number Delay duration
---@return Animation self
function Animation:delay(seconds)
  if type(seconds) ~= "number" or seconds < 0 then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_005")
    end
    seconds = 0
  end
  self._delay = seconds
  self._delayElapsed = 0
  return self
end

--- Set repeat count
---@param count number Repeat count (0 = infinite)
---@return Animation self
function Animation:repeatCount(count)
  if type(count) ~= "number" or count < 0 then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_006")
    end
    count = 0
  end
  self._repeatCount = count
  self._repeatCurrent = 0
  return self
end

--- Enable yoyo mode
---@param enabled boolean? Enable yoyo (default: true)
---@return Animation self
function Animation:yoyo(enabled)
  if enabled == nil then
    enabled = true
  end
  self._yoyo = enabled
  return self
end

--- Create fade animation
---@param duration number Duration in seconds
---@param fromOpacity number Starting opacity
---@param toOpacity number Ending opacity
---@param easing string? Easing function name
---@return Animation animation
function Animation.fade(duration, fromOpacity, toOpacity, easing)
  if type(duration) ~= "number" or duration <= 0 then
    duration = 1
  end
  if type(fromOpacity) ~= "number" then
    fromOpacity = 1
  end
  if type(toOpacity) ~= "number" then
    toOpacity = 0
  end

  return Animation.new({
    duration = duration,
    start = { opacity = fromOpacity },
    final = { opacity = toOpacity },
    easing = easing,
  })
end

--- Create scale animation
---@param duration number Duration in seconds
---@param fromScale {width:number,height:number} Starting scale
---@param toScale {width:number,height:number} Ending scale
---@param easing string? Easing function name
---@return Animation animation
function Animation.scale(duration, fromScale, toScale, easing)
  if type(duration) ~= "number" or duration <= 0 then
    duration = 1
  end
  if type(fromScale) ~= "table" then
    fromScale = { width = 1, height = 1 }
  end
  if type(toScale) ~= "table" then
    toScale = { width = 1, height = 1 }
  end

  return Animation.new({
    duration = duration,
    start = { width = fromScale.width or 0, height = fromScale.height or 0 },
    final = { width = toScale.width or 0, height = toScale.height or 0 },
    easing = easing,
  })
end

--- Create keyframe animation
---@param props {duration:number, keyframes:Keyframe[], onStart:function?, onUpdate:function?, onComplete:function?, onCancel:function?}
---@return Animation animation
function Animation.keyframes(props)
  if type(props) ~= "table" then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_007")
    end
    props = { duration = 1, keyframes = {} }
  end

  if type(props.duration) ~= "number" or props.duration <= 0 then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_002")
    end
    props.duration = 1
  end

  if type(props.keyframes) ~= "table" or #props.keyframes < 2 then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_008")
    end
    props.keyframes = {
      { at = 0, values = {} },
      { at = 1, values = {} },
    }
  end

  local sortedKeyframes = {}
  for i, kf in ipairs(props.keyframes) do
    if type(kf) == "table" and type(kf.at) == "number" and type(kf.values) == "table" then
      table.insert(sortedKeyframes, kf)
    end
  end

  table.sort(sortedKeyframes, function(a, b)
    return a.at < b.at
  end)

  if #sortedKeyframes > 0 then
    if sortedKeyframes[1].at > 0 then
      table.insert(sortedKeyframes, 1, { at = 0, values = sortedKeyframes[1].values })
    end
    if sortedKeyframes[#sortedKeyframes].at < 1 then
      table.insert(sortedKeyframes, { at = 1, values = sortedKeyframes[#sortedKeyframes].values })
    end
  end

  return Animation.new({
    duration = props.duration,
    start = {},
    final = {},
    keyframes = sortedKeyframes,
    onStart = props.onStart,
    onUpdate = props.onUpdate,
    onComplete = props.onComplete,
    onCancel = props.onCancel,
  })
end

--- Link an array of animations into a chain (static helper)
--- Each animation's completion triggers the next in sequence
---@param animations Animation[] Array of animations to chain
---@return Animation first The first animation in the chain
function Animation.chainSequence(animations)
  if type(animations) ~= "table" or #animations == 0 then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("Animation", "ANIM_004")
    end
    return Animation.new({ duration = 0, start = {}, final = {} })
  end

  for i = 1, #animations - 1 do
    animations[i]:chain(animations[i + 1])
  end

  return animations[1]
end

-- ============================================================================
-- ANIMATION GROUP (Utility)
-- ============================================================================

local AnimationGroup = {}
AnimationGroup.__index = AnimationGroup

--- Coordinate multiple animations
---@param props AnimationGroupProps
---@return AnimationGroup group
function AnimationGroup.new(props)
  if type(props) ~= "table" then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("AnimationGroup", "ANIM_009")
    end
    props = { animations = {} }
  end

  if type(props.animations) ~= "table" or #props.animations == 0 then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("AnimationGroup", "ANIM_010")
    end
    props.animations = {}
  end

  local self = setmetatable({}, AnimationGroup)

  self.animations = props.animations
  self.mode = props.mode or "parallel"
  self.stagger = props.stagger or 0.1
  self.onComplete = props.onComplete
  self.onStart = props.onStart

  if self.mode ~= "parallel" and self.mode ~= "sequence" and self.mode ~= "stagger" then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("AnimationGroup", "ANIM_011", {
        mode = tostring(self.mode),
      })
    end
    self.mode = "parallel"
  end

  self._currentIndex = 1
  self._staggerElapsed = 0
  self._startedAnimations = {}
  self._hasStarted = false
  self._paused = false
  self._state = "ready"

  return self
end

--- Update all animations in parallel
---@param dt number Delta time
---@param element table? Optional element reference
---@return boolean finished
function AnimationGroup:_updateParallel(dt, element)
  local allFinished = true

  for i, anim in ipairs(self.animations) do
    local isCompleted = false
    if type(anim.getState) == "function" then
      isCompleted = anim:getState() == "completed"
    elseif anim._state then
      isCompleted = anim._state == "completed"
    end

    if not isCompleted then
      local finished = anim:update(dt, element)
      if not finished then
        allFinished = false
      end
    end
  end

  return allFinished
end

--- Update animations in sequence
---@param dt number Delta time
---@param element table? Optional element reference
---@return boolean finished
function AnimationGroup:_updateSequence(dt, element)
  if self._currentIndex > #self.animations then
    return true
  end

  local currentAnim = self.animations[self._currentIndex]
  local finished = currentAnim:update(dt, element)

  if finished then
    self._currentIndex = self._currentIndex + 1
    if self._currentIndex > #self.animations then
      return true
    end
  end

  return false
end

--- Update animations with stagger
---@param dt number Delta time
---@param element table? Optional element reference
---@return boolean finished
function AnimationGroup:_updateStagger(dt, element)
  self._staggerElapsed = self._staggerElapsed + dt

  for i, anim in ipairs(self.animations) do
    local startTime = (i - 1) * self.stagger

    if self._staggerElapsed >= startTime and not self._startedAnimations[i] then
      self._startedAnimations[i] = true
    end
  end

  local allFinished = true
  for i, anim in ipairs(self.animations) do
    if self._startedAnimations[i] then
      local isCompleted = false
      if type(anim.getState) == "function" then
        isCompleted = anim:getState() == "completed"
      elseif anim._state then
        isCompleted = anim._state == "completed"
      end

      if not isCompleted then
        local finished = anim:update(dt, element)
        if not finished then
          allFinished = false
        end
      end
    else
      allFinished = false
    end
  end

  return allFinished
end

--- Advance all animations in the group
---@param dt number Delta time
---@param element table? Optional element reference
---@return boolean finished
function AnimationGroup:update(dt, element)
  if type(dt) ~= "number" or dt < 0 or dt ~= dt or dt == math.huge then
    dt = 0
  end

  if self._paused or self._state == "completed" or self._state == "cancelled" then
    return self._state == "completed"
  end

  if not self._hasStarted then
    self._hasStarted = true
    self._state = "playing"
    if self.onStart and type(self.onStart) == "function" then
      local success, err = pcall(self.onStart, self)
      if not success then
        Animation._ErrorHandler:warn("Animation", "EVT_002", {
          callback = "onStart",
          error = tostring(err),
        })
      end
    end
  end

  local finished = false

  if self.mode == "parallel" then
    finished = self:_updateParallel(dt, element)
  elseif self.mode == "sequence" then
    finished = self:_updateSequence(dt, element)
  elseif self.mode == "stagger" then
    finished = self:_updateStagger(dt, element)
  end

  if finished then
    self._state = "completed"
    if self.onComplete and type(self.onComplete) == "function" then
      local success, err = pcall(self.onComplete, self)
      if not success then
        Animation._ErrorHandler:warn("Animation", "EVT_002", {
          callback = "onComplete",
          error = tostring(err),
        })
      end
    end
  end

  return finished
end

--- Pause all animations
function AnimationGroup:pause()
  self._paused = true
  for _, anim in ipairs(self.animations) do
    if type(anim.pause) == "function" then
      anim:pause()
    end
  end
end

--- Resume all animations
function AnimationGroup:resume()
  self._paused = false
  for _, anim in ipairs(self.animations) do
    if type(anim.resume) == "function" then
      anim:resume()
    end
  end
end

--- Check if paused
---@return boolean paused
function AnimationGroup:isPaused()
  return self._paused
end

--- Reverse all animations
function AnimationGroup:reverse()
  for _, anim in ipairs(self.animations) do
    if type(anim.reverse) == "function" then
      anim:reverse()
    end
  end
end

--- Set speed for all animations
---@param speed number Speed multiplier
function AnimationGroup:setSpeed(speed)
  for _, anim in ipairs(self.animations) do
    if type(anim.setSpeed) == "function" then
      anim:setSpeed(speed)
    end
  end
end

--- Cancel all animations
---@param element table? Optional element reference
function AnimationGroup:cancel(element)
  if self._state ~= "cancelled" and self._state ~= "completed" then
    self._state = "cancelled"
    for _, anim in ipairs(self.animations) do
      if type(anim.cancel) == "function" then
        anim:cancel(element)
      end
    end
  end
end

--- Reset all animations
function AnimationGroup:reset()
  self._currentIndex = 1
  self._staggerElapsed = 0
  self._startedAnimations = {}
  self._hasStarted = false
  self._paused = false
  self._state = "ready"

  for _, anim in ipairs(self.animations) do
    if type(anim.reset) == "function" then
      anim:reset()
    end
  end
end

--- Get group state
---@return string state
function AnimationGroup:getState()
  return self._state
end

--- Get group progress
---@return number progress
function AnimationGroup:getProgress()
  if #self.animations == 0 then
    return 1
  end

  if self.mode == "sequence" then
    local completedAnims = self._currentIndex - 1
    local currentProgress = 0

    if self._currentIndex <= #self.animations then
      local currentAnim = self.animations[self._currentIndex]
      if type(currentAnim.getProgress) == "function" then
        currentProgress = currentAnim:getProgress()
      end
    end

    return (completedAnims + currentProgress) / #self.animations
  else
    local totalProgress = 0
    for _, anim in ipairs(self.animations) do
      if type(anim.getProgress) == "function" then
        totalProgress = totalProgress + anim:getProgress()
      else
        totalProgress = totalProgress + 1
      end
    end
    return totalProgress / #self.animations
  end
end

--- Apply group to element
---@param element table The element to apply animations to
function AnimationGroup:apply(element)
  if not element or type(element) ~= "table" then
    if Animation._ErrorHandler then
      Animation._ErrorHandler:warn("AnimationGroup", "ANIM_003")
    end
    return
  end
  element.animationGroup = self
end

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================

--- Initialize Animation module with dependencies
---@param deps table Dependencies: { ErrorHandler = ErrorHandler, Color = Color? }
function Animation.init(deps)
  if type(deps) == "table" then
    Animation._ErrorHandler = deps.ErrorHandler
    Animation._ColorModule = deps.Color
  end
end

Animation.Easing = Easing
Animation.Transform = Transform
Animation.Group = AnimationGroup

return Animation
