local packageName = ... or "FocusIndicator"
local modulePath = packageName:match("(.-)[^%.]+$")

local function req(name)
  return require(modulePath .. name)
end

local FocusIndicator = {}

--- Configuration
---@type KeyboardNavigationFocusIndicatorConfig
FocusIndicator.config = {
  enabled = true,

  --- Custom draw function to override default rendering
  ---@type function|nil
  --- Called with: element, bounds, style - return true to skip default drawing
  draw = nil,

  -- Appearance
  color = { 0.2, 0.6, 1.0, 0.8 }, -- Blue with 80% opacity
  lineWidth = 2,
  inset = -3, -- Negative value extends beyond element
  borderRadius = 4,

  -- Animation
  animationDuration = 0.15, -- Seconds for focus animation
  pulseEnabled = false, -- Enable pulsing animation
  pulseDuration = 1.0, -- Seconds per pulse cycle
  pulseScaleMin = 0.95, -- Minimum scale during pulse
  pulseScaleMax = 1.05, -- Maximum scale during pulse
}

--- State
FocusIndicator._focusedElement = nil
FocusIndicator._animationProgress = 0
FocusIndicator._pulsePhase = 0
FocusIndicator._hidden = true
FocusIndicator._deps = nil

--- Initialize FocusIndicator module
---@param deps table Dependencies table containing Context and Color modules
---@field deps.Context table Context module for getting focused element
---@field deps.Color table Color module for color manipulation
function FocusIndicator.init(deps)
  FocusIndicator._deps = deps
  FocusIndicator._Context = deps.Context
  FocusIndicator._Color = deps.Color
end

--- Update animation state for entrance and pulse effects
---@param dt number Delta time in seconds since last frame
function FocusIndicator:update(dt)
  if not FocusIndicator.config.enabled then
    return
  end

  -- Update focus entrance animation
  if FocusIndicator._animationProgress < 1 then
    FocusIndicator._animationProgress =
      math.min(1, FocusIndicator._animationProgress + (dt / FocusIndicator.config.animationDuration))
  end

  -- Update pulse animation
  if FocusIndicator.config.pulseEnabled then
    FocusIndicator._pulsePhase = (FocusIndicator._pulsePhase + dt) % FocusIndicator.config.pulseDuration
  end
end

--- Set the focused element to render indicator around
---@param element Element? The element to show focus indicator around, or nil to hide
function FocusIndicator.setFocused(element)
  FocusIndicator._focusedElement = element
  FocusIndicator._hidden = element == nil
  -- Reset animation when focus changes
  if element then
    FocusIndicator._animationProgress = 0
  end
end

--- Get the current scale factor for animations
--- Combines entrance scale (0.8 to 1.0) with optional pulse scale
---@return number Scale factor (typically 0.8-1.05 range)
function FocusIndicator:getScale()
  local scale = 1

  -- Apply entrance animation (scale up from 0.8)
  local entranceScale = 0.8 + (0.2 * FocusIndicator._animationProgress)
  scale = scale * entranceScale

  -- Apply pulse animation
  if FocusIndicator.config.pulseEnabled then
    local pulseProgress = FocusIndicator._pulsePhase / FocusIndicator.config.pulseDuration
    -- Smooth sine wave pulse
    local pulseScale = FocusIndicator.config.pulseScaleMin
      + (FocusIndicator.config.pulseScaleMax - FocusIndicator.config.pulseScaleMin)
        * (0.5 + 0.5 * math.sin(2 * math.pi * pulseProgress))
    scale = scale * pulseScale
  end

  return scale
end

--- Get the current opacity for the indicator
--- Applies entrance animation fade-in to the configured alpha
---@return number Alpha value (0-1 range)
function FocusIndicator:getOpacity()
  -- Fade in on focus
  return FocusIndicator.config.color[4] * FocusIndicator._animationProgress
end

--- Draw the focus indicator around the focused element
--- Renders a rounded rectangle border, or calls custom draw function if configured
--- Should be called from within love.draw() after all elements are drawn
function FocusIndicator:draw()
  if not FocusIndicator.config.enabled then
    return
  end

  if FocusIndicator._hidden then
    return
  end

  -- In immediate mode the stored element reference is stale (recreated every frame).
  -- Always resolve through Context so we get the live object with up-to-date positions.
  local element
  if FocusIndicator._Context then
    element = FocusIndicator._Context.getFocused()
  else
    element = FocusIndicator._focusedElement
  end

  if not element then
    return
  end

  -- Get element dimensions (use border-box size which includes padding)
  local x = element.x or 0
  local y = element.y or 0
  local w = element._borderBoxWidth
    or (element.width + (element.padding and (element.padding.left + element.padding.right) or 0))
  local h = element._borderBoxHeight
    or (element.height + (element.padding and (element.padding.top + element.padding.bottom) or 0))

  if w == 0 or h == 0 then
    return
  end

  -- Calculate indicator dimensions with inset and scale
  local inset = FocusIndicator.config.inset
  local scale = self:getScale()

  local indicatorX = x + inset
  local indicatorY = y + inset
  local indicatorW = w - 2 * inset
  local indicatorH = h - 2 * inset

  -- Center the scale around the element
  local offsetX = (indicatorW * (1 - scale)) / 2
  local offsetY = (indicatorH * (1 - scale)) / 2

  indicatorX = indicatorX + offsetX
  indicatorY = indicatorY + offsetY
  indicatorW = indicatorW * scale
  indicatorH = indicatorH * scale

  -- Get color with animated opacity
  local r, g, b = FocusIndicator.config.color[1], FocusIndicator.config.color[2], FocusIndicator.config.color[3]
  local a = self:getOpacity()

  -- Build style table for custom draw callback
  local bounds = {
    x = indicatorX,
    y = indicatorY,
    width = indicatorW,
    height = indicatorH,
  }

  local style = {
    color = { r = r, g = g, b = b, a = a },
    lineWidth = FocusIndicator.config.lineWidth,
    borderRadius = FocusIndicator.config.borderRadius,
    scale = scale,
    opacity = a,
  }

  -- Check for custom draw callback
  if FocusIndicator.config.draw then
    local skipDefault = FocusIndicator.config.draw(element, bounds, style)
    if skipDefault then
      return
    end
  end

  -- Save current love.graphics state
  local prevBlend, prevAlphaMode = love.graphics.getBlendMode()
  local prevR, prevG, prevB, prevA = love.graphics.getColor()
  local prevLineWidth = love.graphics.getLineWidth()

  -- Set blend mode for transparency
  love.graphics.setBlendMode("alpha")

  -- Draw rounded rectangle border
  love.graphics.setColor(r, g, b, a)
  love.graphics.setLineWidth(FocusIndicator.config.lineWidth)

  -- Draw the rounded rectangle border
  local borderRadius = FocusIndicator.config.borderRadius
  love.graphics.rectangle("line", indicatorX, indicatorY, indicatorW, indicatorH, borderRadius)

  -- Restore love.graphics state
  love.graphics.setBlendMode(prevBlend, prevAlphaMode)
  love.graphics.setColor(prevR, prevG, prevB, prevA)
  love.graphics.setLineWidth(prevLineWidth)
end

--- Set the indicator color
---@param r number Red component (0-1 range)
---@param g number Green component (0-1 range)
---@param b number Blue component (0-1 range)
---@param a number|nil Alpha component (0-1 range), defaults to current alpha if omitted
function FocusIndicator.setColor(r, g, b, a)
  FocusIndicator.config.color = { r, g, b, a or FocusIndicator.config.color[4] }
end

--- Set the stroke width for the indicator border
---@param width number Line width in pixels
function FocusIndicator.setLineWidth(width)
  FocusIndicator.config.lineWidth = width
end

return FocusIndicator
