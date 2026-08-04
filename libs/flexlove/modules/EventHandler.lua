---@class EventHandler
---@field onEvent fun(element:Element, event:InputEvent)?
---@field onEventDeferred boolean?
---@field onTouchEvent fun(element:Element, touchEvent:InputEvent)? -- Touch-specific callback
---@field onTouchEventDeferred boolean? -- Whether onTouchEvent is deferred
---@field onGesture fun(element:Element, gesture:table)? -- Gesture callback
---@field onGestureDeferred boolean? -- Whether onGesture is deferred
---@field touchEnabled boolean -- Whether touch events are processed (default: true)
---@field multiTouchEnabled boolean -- Whether multi-touch is supported (default: false)
---@field _pressed table<number, boolean>
---@field _lastClickTime number?
---@field _lastClickButton number?
---@field _clickCount number
---@field _dragStartX table<number, number>
---@field _dragStartY table<number, number>
---@field _lastMouseX table<number, number>
---@field _lastMouseY table<number, number>
---@field _touches table<string, table> -- Multi-touch state per touch ID
---@field _touchStartPositions table<string, table> -- Touch start positions
---@field _lastTouchPositions table<string, table> -- Last touch positions for delta
---@field _touchHistory table<string, table> -- Touch position history for gestures (last 5)
---@field _hovered boolean
---@field _scrollbarPressHandled boolean
---@field _InputEvent table
---@field _utils table
---@field _Performance Performance? Performance module dependency
---@field _ErrorHandler ErrorHandler
local EventHandler = {}
EventHandler.__index = EventHandler

--- Initialize module with shared dependencies
---@param deps table Dependencies {Performance, ErrorHandler, InputEvent, Context, utils}
function EventHandler.init(deps)
  EventHandler._Performance = deps.Performance
  EventHandler._ErrorHandler = deps.ErrorHandler
  EventHandler._InputEvent = deps.InputEvent
  EventHandler._utils = deps.utils
  EventHandler._Context = deps.Context
end

---@param config table Configuration options
---@return EventHandler
function EventHandler.new(config)
  config = config or {}
  local self = setmetatable({}, EventHandler)

  self.onEvent = config.onEvent
  self.onEventDeferred = config.onEventDeferred
  self.onTouchEvent = config.onTouchEvent
  self.onTouchEventDeferred = config.onTouchEventDeferred or false
  self.onGesture = config.onGesture
  self.onGestureDeferred = config.onGestureDeferred or false
  self.touchEnabled = config.touchEnabled ~= false -- Default true
  self.multiTouchEnabled = config.multiTouchEnabled or false -- Default false

  self._pressed = config._pressed or {}

  self._lastClickTime = config._lastClickTime
  self._lastClickButton = config._lastClickButton
  self._clickCount = config._clickCount or 0

  -- FocusIndicator reference (set after initialization)
  self._FocusIndicator = nil

  self._dragStartX = config._dragStartX or {}
  self._dragStartY = config._dragStartY or {}
  self._lastMouseX = config._lastMouseX or {}
  self._lastMouseY = config._lastMouseY or {}

  -- Multi-touch tracking
  self._touches = config._touches or {}
  self._touchStartPositions = config._touchStartPositions or {}
  self._lastTouchPositions = config._lastTouchPositions or {}
  self._touchHistory = config._touchHistory or {}

  self._hovered = config._hovered or false

  self._scrollbarPressHandled = false

  return self
end

--- Get state for persistence (for immediate mode)
---@return table State data
function EventHandler:getState()
  return {
    _pressed = self._pressed,
    _lastClickTime = self._lastClickTime,
    _lastClickButton = self._lastClickButton,
    _clickCount = self._clickCount,
    _dragStartX = self._dragStartX,
    _dragStartY = self._dragStartY,
    _lastMouseX = self._lastMouseX,
    _lastMouseY = self._lastMouseY,
    _touches = self._touches,
    _touchStartPositions = self._touchStartPositions,
    _lastTouchPositions = self._lastTouchPositions,
    _touchHistory = self._touchHistory,
    _hovered = self._hovered,
  }
end

--- Restore state from persistence (for immediate mode)
---@param state table State data
function EventHandler:setState(state)
  if not state then
    return
  end

  self._pressed = state._pressed or {}
  self._lastClickTime = state._lastClickTime
  self._lastClickButton = state._lastClickButton
  self._clickCount = state._clickCount or 0
  self._dragStartX = state._dragStartX or {}
  self._dragStartY = state._dragStartY or {}
  self._lastMouseX = state._lastMouseX or {}
  self._lastMouseY = state._lastMouseY or {}
  self._touches = state._touches or {}
  self._touchStartPositions = state._touchStartPositions or {}
  self._lastTouchPositions = state._lastTouchPositions or {}
  self._touchHistory = state._touchHistory or {}
  self._hovered = state._hovered or false
end

--- Process mouse button events in the update cycle
---@param element Element The parent element
---@param mx number Mouse X position
---@param my number Mouse Y position
---@param isHovering boolean Whether mouse is over element
---@param isActiveElement boolean Whether this is the top element at mouse position
function EventHandler:processMouseEvents(element, mx, my, isHovering, isActiveElement)
  -- Start performance timing
  -- Performance accessed via EventHandler._Performance
  if EventHandler._Performance and EventHandler._Performance.enabled then
    EventHandler._Performance:startTimer("event_mouse")
  end

  -- Check if currently dragging (allows drag continuation even if occluded)
  local isDragging = false
  for _, button in ipairs({ 1, 2, 3 }) do
    if self._pressed[button] and love.mouse.isDown(button) then
      isDragging = true
      break
    end
  end

  -- Check if any button is currently pressed (tracked state)
  local hasTrackedPress = false
  for _, button in ipairs({ 1, 2, 3 }) do
    if self._pressed[button] then
      hasTrackedPress = true
      break
    end
  end

  -- Can only process events if we have handler, element is enabled, and is active or dragging or has tracked press
  -- Read onEvent from element (source of truth), fallback to handler cache for backwards compat
  local canProcessEvents = (
    element.onEvent
    or self.onEvent
    or element.editable
    or element._selectState
    or element.selectOption
  )
    and element.visibility ~= "hidden"
    and not element.disabled
    and (isActiveElement or isDragging or hasTrackedPress)

  if not canProcessEvents then
    -- If not hovering and no buttons are physically pressed, reset all pressed states
    -- This ensures the pressed state is cleared when mouse leaves without button held
    if not isHovering and not isDragging then
      for _, button in ipairs({ 1, 2, 3 }) do
        if self._pressed[button] and not love.mouse.isDown(button) then
          self._pressed[button] = false
          self._dragStartX[button] = nil
          self._dragStartY[button] = nil
        end
      end
    end

    -- Track hover state changes even when events can't be processed
    -- Fire synthetic unhover when element becomes disabled while hovered
    if element.disabled and self._hovered then
      self._hovered = false
      if element.onEvent or self.onEvent then
        local modifiers = EventHandler._utils.getModifiers()
        local unhoverEvent = EventHandler._InputEvent.new({
          type = "unhover",
          button = 0,
          x = mx,
          y = my,
          modifiers = modifiers,
          clickCount = 0,
        })
        self:_invokeCallback(element, unhoverEvent)
      end
    elseif self._hovered and not isHovering then
      self._hovered = false
      if element.onEvent or self.onEvent then
        local modifiers = EventHandler._utils.getModifiers()
        local unhoverEvent = EventHandler._InputEvent.new({
          type = "unhover",
          button = 0,
          x = mx,
          y = my,
          modifiers = modifiers,
          clickCount = 0,
        })
        self:_invokeCallback(element, unhoverEvent)
      end
    end

    if EventHandler._Performance and EventHandler._Performance.enabled then
      EventHandler._Performance:stopTimer("event_mouse")
    end
    return
  end

  -- Track hover state changes and fire hover/unhover events BEFORE button processing
  -- This ensures hover fires before press when mouse first enters element
  local wasHovered = self._hovered
  local isHoveringAndActive = isHovering and isActiveElement

  if isHoveringAndActive and not wasHovered then
    -- Just started hovering - fire hover event
    self._hovered = true
    local modifiers = EventHandler._utils.getModifiers()
    local hoverEvent = EventHandler._InputEvent.new({
      type = "hover",
      button = 0,
      x = mx,
      y = my,
      modifiers = modifiers,
      clickCount = 0,
    })
    self:_invokeCallback(element, hoverEvent)
  elseif not isHoveringAndActive and wasHovered then
    -- Just stopped hovering - fire unhover event
    self._hovered = false
    local modifiers = EventHandler._utils.getModifiers()
    local unhoverEvent = EventHandler._InputEvent.new({
      type = "unhover",
      button = 0,
      x = mx,
      y = my,
      modifiers = modifiers,
      clickCount = 0,
    })
    self:_invokeCallback(element, unhoverEvent)
  end

  -- Process all three mouse buttons
  local buttons = { 1, 2, 3 } -- left, right, middle

  for _, button in ipairs(buttons) do
    -- Check if this button was tracked as pressed
    local wasPressed = self._pressed[button]
    local isPhysicallyPressed = love.mouse.isDown(button)

    if isHovering or isDragging or wasPressed then
      if isPhysicallyPressed then
        -- Button is pressed down
        if not wasPressed then
          -- Just pressed - fire press event (only if hovering)
          if isHovering then
            self:_handleMousePress(element, mx, my, button)
          end
        else
          -- Button is still pressed - check for drag
          self:_handleMouseDrag(element, mx, my, button, isHovering)
        end
      elseif wasPressed then
        -- Button was just released
        -- Only fire click and release events if mouse is still hovering AND element is active
        -- (not occluded by another element)
        if isHovering and isActiveElement then
          self:_handleMouseRelease(element, mx, my, button)
        else
          -- Mouse left before release OR element is occluded - just clear the pressed state without firing events
          self._pressed[button] = false
          self._dragStartX[button] = nil
          self._dragStartY[button] = nil
        end
      end
    end
  end

  -- After processing events, reset pressed states for buttons that are no longer held
  -- This handles the case where mouse leaves while button is held, then released
  if not isHovering and not isDragging then
    for _, button in ipairs({ 1, 2, 3 }) do
      if self._pressed[button] and not love.mouse.isDown(button) then
        self._pressed[button] = false
        self._dragStartX[button] = nil
        self._dragStartY[button] = nil
      end
    end
  end

  -- Stop performance timing
  if EventHandler._Performance and EventHandler._Performance.enabled then
    EventHandler._Performance:stopTimer("event_mouse")
  end
end

--- Handle mouse button press
---@param element Element The parent element
---@param mx number Mouse X position
---@param my number Mouse Y position
---@param button number Mouse button (1=left, 2=right, 3=middle)
function EventHandler:_handleMousePress(element, mx, my, button)
  -- Check if press is on scrollbar first (skip if already handled)
  if button == 1 and not self._scrollbarPressHandled and element._handleScrollbarPress then
    if element:_handleScrollbarPress(mx, my, button) then
      -- Scrollbar consumed the event, mark as pressed to prevent onEvent
      self._pressed[button] = true
      self._scrollbarPressHandled = true
      return
    end
  end

  -- Fire press event
  local modifiers = EventHandler._utils.getModifiers()
  local pressEvent = EventHandler._InputEvent.new({
    type = "press",
    button = button,
    x = mx,
    y = my,
    modifiers = modifiers,
    clickCount = 1,
  })
  self:_invokeCallback(element, pressEvent)

  self._pressed[button] = true

  -- On left click, set keyboard focus to any focusable element (not just editable).
  -- Clear the focus indicator since mouse navigation doesn't use it.
  local isFocusable
  if type(element.isFocusable) == "function" then
    isFocusable = element:isFocusable()
  else
    isFocusable = (element.editable == true)
      or (type(element.onEvent) == "function")
      or element._selectState ~= nil
      or element.selectOption ~= nil
  end

  if button == 1 and EventHandler._Context and isFocusable then
    EventHandler._Context.setFocused(element)
    -- Hide focus indicator - it's only for keyboard navigation
    if EventHandler._FocusIndicator then
      EventHandler._FocusIndicator.setFocused(nil)
    end
  end
  -- Set mouse down position for text selection on left click
  if button == 1 and element._textEditor then
    element._mouseDownPosition = element._textEditor:mouseToTextPosition(element, mx, my)
    element._textDragOccurred = false -- Reset drag flag on press
  end

  -- Record drag start position per button
  self._dragStartX[button] = mx
  self._dragStartY[button] = my
  self._lastMouseX[button] = mx
  self._lastMouseY[button] = my
end

--- Handle mouse drag (while button is pressed and mouse moves)
---@param element Element The parent element
---@param mx number Mouse X position
---@param my number Mouse Y position
---@param button number Mouse button
---@param isHovering boolean Whether mouse is over element
function EventHandler:_handleMouseDrag(element, mx, my, button, isHovering)
  local lastX = self._lastMouseX[button] or mx
  local lastY = self._lastMouseY[button] or my

  if lastX ~= mx or lastY ~= my then
    -- Handle scrollbar drag if scrollbar was pressed
    if button == 1 and self._scrollbarPressHandled and element._handleScrollbarDrag then
      element:_handleScrollbarDrag(mx, my)
      self._lastMouseX[button] = mx
      self._lastMouseY[button] = my
      return -- Don't process other drag events while dragging scrollbar
    end

    -- Mouse has moved - fire drag event only if still hovering
    if isHovering then
      local modifiers = EventHandler._utils.getModifiers()
      local dx = mx - self._dragStartX[button]
      local dy = my - self._dragStartY[button]

      local dragEvent = EventHandler._InputEvent.new({
        type = "drag",
        button = button,
        x = mx,
        y = my,
        dx = dx,
        dy = dy,
        modifiers = modifiers,
        clickCount = 1,
      })
      self:_invokeCallback(element, dragEvent)
    end

    -- Handle text selection drag for editable elements
    if button == 1 and element.editable and element._focused and element._handleTextDrag then
      element:_handleTextDrag(mx, my)
    end

    -- Update last known position for this button
    self._lastMouseX[button] = mx
    self._lastMouseY[button] = my
  end
end

--- Handle mouse button release
---@param mx number Mouse X position
---@param my number Mouse Y position
---@param button number Mouse button
function EventHandler:_handleMouseRelease(element, mx, my, button)
  local currentTime = love.timer.getTime()
  local modifiers = EventHandler._utils.getModifiers()

  -- Handle scrollbar release if scrollbar was pressed
  if button == 1 and self._scrollbarPressHandled and element._handleScrollbarRelease then
    element:_handleScrollbarRelease(button)
    self._scrollbarPressHandled = false -- Reset flag
    self._pressed[button] = false
    self._dragStartX[button] = nil
    self._dragStartY[button] = nil
    return -- Don't process click events for scrollbar release
  end

  -- Determine click count (double-click detection)
  local clickCount
  local doubleClickThreshold = 0.3 -- 300ms for double-click

  if
    self._lastClickTime
    and self._lastClickButton == button
    and (currentTime - self._lastClickTime) < doubleClickThreshold
  then
    clickCount = self._clickCount + 1
  else
    clickCount = 1
  end

  self._clickCount = clickCount
  self._lastClickTime = currentTime
  self._lastClickButton = button

  -- Determine event type based on button
  local eventType = "click"
  if button == 2 then
    eventType = "rightclick"
  elseif button == 3 then
    eventType = "middleclick"
  end

  -- Fire click event
  local clickEvent = EventHandler._InputEvent.new({
    type = eventType,
    button = button,
    x = mx,
    y = my,
    modifiers = modifiers,
    clickCount = clickCount,
  })
  self:_invokeCallback(element, clickEvent)

  self._pressed[button] = false

  -- Clean up drag tracking
  self._dragStartX[button] = nil
  self._dragStartY[button] = nil

  -- Clean up text selection drag tracking
  if button == 1 then
    element._mouseDownPosition = nil
  end

  -- Focus editable elements on left click
  if button == 1 and element.editable then
    -- Only focus if not already focused (to avoid moving cursor to end)
    local wasFocused = element:isFocused()
    if not wasFocused then
      element:focus()
    end

    -- Handle text click for cursor positioning and word selection
    -- Only process click if no text drag occurred (to preserve drag selection)
    if element._handleTextClick and not element._textDragOccurred then
      element:_handleTextClick(mx, my, clickCount)
    end

    -- Reset drag flag after release
    element._textDragOccurred = false
  end

  -- Fire release event
  local releaseEvent = EventHandler._InputEvent.new({
    type = "release",
    button = button,
    x = mx,
    y = my,
    modifiers = modifiers,
    clickCount = clickCount,
  })
  self:_invokeCallback(element, releaseEvent)

  if button == 1 and element._handleSelectRelease then
    element:_handleSelectRelease()
  end
end

--- Process touch events in the update cycle
---@param element Element The parent element
function EventHandler:processTouchEvents(element)
  -- Start performance timing
  if EventHandler._Performance and EventHandler._Performance.enabled then
    EventHandler._Performance:startTimer("event_touch")
  end

  -- Check if element can process events
  local canProcessEvents = (
    element.onEvent
    or self.onEvent
    or element.onTouchEvent
    or self.onTouchEvent
    or element.editable
  )
    and not element.disabled
    and self.touchEnabled

  if not canProcessEvents then
    if EventHandler._Performance and EventHandler._Performance.enabled then
      EventHandler._Performance:stopTimer("event_touch")
    end
    return
  end

  local bx = element.x
  local by = element.y
  local bw = element._borderBoxWidth or (element.width + element.padding.left + element.padding.right)
  local bh = element._borderBoxHeight or (element.height + element.padding.top + element.padding.bottom)

  -- Get current active touches from LÖVE
  local activeTouches = {}
  local touches = love.touch.getTouches()
  for _, id in ipairs(touches) do
    activeTouches[tostring(id)] = true
  end

  -- Count active tracked touches for multi-touch filtering
  local trackedTouchCount = 0
  for _ in pairs(self._touches) do
    trackedTouchCount = trackedTouchCount + 1
  end

  -- Process active touches
  for _, id in ipairs(touches) do
    local touchId = tostring(id)
    local tx, ty = love.touch.getPosition(id)
    local pressure = 1.0 -- LÖVE doesn't provide pressure by default

    -- Check if touch is within element bounds
    local isInside = tx >= bx and tx <= bx + bw and ty >= by and ty <= by + bh

    if isInside then
      if not self._touches[touchId] then
        -- Multi-touch filtering: reject new touches when multiTouchEnabled=false
        -- and we already have an active touch
        if self.multiTouchEnabled or trackedTouchCount == 0 then
          -- New touch began
          self:_handleTouchBegan(element, touchId, tx, ty, pressure)
          trackedTouchCount = trackedTouchCount + 1
        end
      else
        -- Touch moved
        self:_handleTouchMoved(element, touchId, tx, ty, pressure)
      end
    elseif self._touches[touchId] then
      -- Touch moved outside or ended
      if activeTouches[touchId] then
        -- Still active but outside - fire moved event
        self:_handleTouchMoved(element, touchId, tx, ty, pressure)
      else
        -- Touch ended
        self:_handleTouchEnded(element, touchId, tx, ty, pressure)
      end
    end
  end

  -- Check for ended touches (touches that were tracked but are no longer active)
  for touchId, _ in pairs(self._touches) do
    if not activeTouches[touchId] then
      -- Touch ended or cancelled
      local lastPos = self._lastTouchPositions[touchId]
      if lastPos then
        self:_handleTouchEnded(element, touchId, lastPos.x, lastPos.y, 1.0)
      else
        -- Cleanup orphaned touch
        self:_cleanupTouch(touchId)
      end
    end
  end

  -- Stop performance timing
  if EventHandler._Performance and EventHandler._Performance.enabled then
    EventHandler._Performance:stopTimer("event_touch")
  end
end

--- Handle touch began event
---@param element Element The parent element
---@param touchId string Touch identifier
---@param x number Touch X position
---@param y number Touch Y position
---@param pressure number Touch pressure (0-1)
function EventHandler:_handleTouchBegan(element, touchId, x, y, pressure)
  -- Create touch state
  self._touches[touchId] = {
    x = x,
    y = y,
    pressure = pressure,
    timestamp = love.timer.getTime(),
    phase = "began",
  }

  -- Record start position
  self._touchStartPositions[touchId] = { x = x, y = y }
  self._lastTouchPositions[touchId] = { x = x, y = y }

  -- Initialize touch history
  self._touchHistory[touchId] = { { x = x, y = y, timestamp = love.timer.getTime() } }

  -- Create and fire touch press event
  local touchEvent = EventHandler._InputEvent.fromTouch(touchId, x, y, "began", pressure)
  touchEvent.type = "touchpress"
  touchEvent.dx = 0
  touchEvent.dy = 0
  self:_invokeCallback(element, touchEvent)
  self:_invokeTouchCallback(element, touchEvent)
end

--- Handle touch moved event
---@param element Element The parent element
---@param touchId string Touch identifier
---@param x number Touch X position
---@param y number Touch Y position
---@param pressure number Touch pressure (0-1)
function EventHandler:_handleTouchMoved(element, touchId, x, y, pressure)
  local touchState = self._touches[touchId]

  if not touchState then
    -- Touch not tracked, ignore
    return
  end

  local lastPos = self._lastTouchPositions[touchId]
  if not lastPos or lastPos.x ~= x or lastPos.y ~= y then
    -- Touch position changed
    local startPos = self._touchStartPositions[touchId]
    local dx = x - startPos.x
    local dy = y - startPos.y

    -- Update touch state
    touchState.x = x
    touchState.y = y
    touchState.pressure = pressure
    touchState.phase = "moved"

    -- Update last position
    self._lastTouchPositions[touchId] = { x = x, y = y }

    -- Add to touch history (keep last 5 positions)
    local history = self._touchHistory[touchId] or {}
    table.insert(history, { x = x, y = y, timestamp = love.timer.getTime() })
    if #history > 5 then
      table.remove(history, 1)
    end
    self._touchHistory[touchId] = history

    -- Create and fire touch move event
    local touchEvent = EventHandler._InputEvent.fromTouch(touchId, x, y, "moved", pressure)
    touchEvent.type = "touchmove"
    touchEvent.dx = dx
    touchEvent.dy = dy
    self:_invokeCallback(element, touchEvent)
    self:_invokeTouchCallback(element, touchEvent)
  end
end

--- Handle touch ended event
---@param element Element The parent element
---@param touchId string Touch identifier
---@param x number Touch X position
---@param y number Touch Y position
---@param pressure number Touch pressure (0-1)
function EventHandler:_handleTouchEnded(element, touchId, x, y, pressure)
  local touchState = self._touches[touchId]

  if not touchState then
    -- Touch not tracked, ignore
    return
  end

  local startPos = self._touchStartPositions[touchId]
  local dx = x - startPos.x
  local dy = y - startPos.y

  -- Create and fire touch release event
  local touchEvent = EventHandler._InputEvent.fromTouch(touchId, x, y, "ended", pressure)
  touchEvent.type = "touchrelease"
  touchEvent.dx = dx
  touchEvent.dy = dy
  self:_invokeCallback(element, touchEvent)
  self:_invokeTouchCallback(element, touchEvent)

  -- Cleanup touch state
  self:_cleanupTouch(touchId)
end

--- Cleanup touch state
---@param touchId string Touch ID
function EventHandler:_cleanupTouch(touchId)
  self._touches[touchId] = nil
  self._touchStartPositions[touchId] = nil
  self._lastTouchPositions[touchId] = nil
  self._touchHistory[touchId] = nil
end

--- Get active touches on this element
---@return table<string, table> Active touches
function EventHandler:getActiveTouches()
  return self._touches
end

--- Reset scrollbar press flag (called each frame)
function EventHandler:resetScrollbarPressFlag()
  self._scrollbarPressHandled = false
end

--- Check if any mouse button is pressed
---@return boolean True if any button is pressed
function EventHandler:isAnyButtonPressed()
  for _, pressed in pairs(self._pressed) do
    if pressed then
      return true
    end
  end
  return false
end

--- Check if a specific button is pressed
---@param button number Mouse button (1=left, 2=right, 3=middle)
---@return boolean True if button is pressed
function EventHandler:isButtonPressed(button)
  return self._pressed[button] == true
end

--- Invoke the onEvent callback, optionally deferring it if onEventDeferred is true
---@param element Element The element that triggered the event
---@param event InputEvent The event data
function EventHandler:_invokeCallback(element, event)
  -- Read onEvent from element (source of truth), fallback to handler cache for backwards compat
  local callback = element.onEvent or self.onEvent
  if not callback then
    return
  end

  if self.onEventDeferred then
    -- Get FlexLove module to defer the callback
    local FlexLove = package.loaded["FlexLove"] or package.loaded["libs.FlexLove"]
    if FlexLove and FlexLove.deferCallback then
      FlexLove.deferCallback(function()
        callback(element, event)
      end)
    else
      EventHandler._ErrorHandler:error("EventHandler", "SYS_003", {
        eventType = event.type,
      })
    end
  else
    callback(element, event)
  end
end

--- Invoke the onTouchEvent callback, optionally deferring it
---@param element Element The element that triggered the event
---@param event InputEvent The touch event data
function EventHandler:_invokeTouchCallback(element, event)
  -- Read onTouchEvent from element (source of truth), fallback to handler cache for backwards compat
  local callback = element.onTouchEvent or self.onTouchEvent
  if not callback then
    return
  end

  if self.onTouchEventDeferred then
    local FlexLove = package.loaded["FlexLove"] or package.loaded["libs.FlexLove"]
    if FlexLove and FlexLove.deferCallback then
      FlexLove.deferCallback(function()
        callback(element, event)
      end)
    else
      EventHandler._ErrorHandler:error("EventHandler", "SYS_003", {
        eventType = event.type,
      })
    end
  else
    callback(element, event)
  end
end

--- Invoke the onGesture callback, optionally deferring it
---@param element Element The element that triggered the event
---@param gesture table The gesture data from GestureRecognizer
function EventHandler:_invokeGestureCallback(element, gesture)
  -- Read onGesture from element (source of truth), fallback to handler cache for backwards compat
  local callback = element.onGesture or self.onGesture
  if not callback then
    return
  end

  if self.onGestureDeferred then
    local FlexLove = package.loaded["FlexLove"] or package.loaded["libs.FlexLove"]
    if FlexLove and FlexLove.deferCallback then
      FlexLove.deferCallback(function()
        callback(element, gesture)
      end)
    else
      EventHandler._ErrorHandler:error("EventHandler", "SYS_003", {
        gestureType = gesture.type,
      })
    end
  else
    callback(element, gesture)
  end
end

return EventHandler
