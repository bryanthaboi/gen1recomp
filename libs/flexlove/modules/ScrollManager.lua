---@class ScrollManager
---@field overflow string -- "visible"|"hidden"|"auto"|"scroll"
---@field overflowX string? -- X-axis specific overflow (overrides overflow)
---@field overflowY string? -- Y-axis specific overflow (overrides overflow)
---@field scrollbarWidth number -- Width/height of scrollbar track
---@field scrollbarColor Color -- Scrollbar thumb color
---@field scrollbarTrackColor Color -- Scrollbar track background color
---@field scrollbarRadius number -- Border radius for scrollbars
---@field scrollbarPadding number -- Padding around scrollbar
---@field scrollSpeed number -- Scroll speed for wheel events (pixels per wheel unit)
---@field invertScroll boolean -- Invert mouse wheel scroll direction (default: false)
---@field scrollBarStyle string? -- Scrollbar style name from theme (selects from theme.scrollbars)
---@field scrollbarKnobOffset table -- {x: number, y: number, horizontal: number, vertical: number} -- Offset for scrollbar knob/handle position
---@field hideScrollbars table -- {vertical: boolean, horizontal: boolean}
---@field scrollbarPlacement string -- "reserve-space"|"overlay" -- Whether scrollbar reserves space or overlays content (default: "reserve-space")
---@field scrollbarBalance boolean -- When true, reserve space on both sides of content for visual balance (default: false)
---@field touchScrollEnabled boolean -- Enable touch scrolling
---@field momentumScrollEnabled boolean -- Enable momentum scrolling
---@field bounceEnabled boolean -- Enable bounce effects at boundaries
---@field scrollFriction number -- Friction coefficient for momentum (0.95-0.98)
---@field bounceStiffness number -- Bounce spring constant (0.1-0.3)
---@field maxOverscroll number -- Maximum overscroll distance (pixels)
---@field _overflowX boolean -- True if content overflows horizontally
---@field _overflowY boolean -- True if content overflows vertically
---@field _contentWidth number -- Total content width (including overflow)
---@field _contentHeight number -- Total content height (including overflow)
---@field _scrollX number -- Current horizontal scroll position
---@field _scrollY number -- Current vertical scroll position
---@field _targetScrollX number? -- Target scroll X for smooth scrolling
---@field _targetScrollY number? -- Target scroll Y for smooth scrolling
---@field _smoothScrollSpeed number -- Speed of smooth scroll interpolation (0-1, higher = faster)
---@field _maxScrollX number -- Maximum horizontal scroll (contentWidth - containerWidth)
---@field _maxScrollY number -- Maximum vertical scroll (contentHeight - containerHeight)
---@field _scrollbarHoveredVertical boolean -- True if mouse is over vertical scrollbar
---@field _scrollbarHoveredHorizontal boolean -- True if mouse is over horizontal scrollbar
---@field _scrollbarDragging boolean -- True if currently dragging a scrollbar
---@field _hoveredScrollbar string? -- "vertical" or "horizontal" when dragging
---@field _scrollbarDragOffset number -- DEPRECATED: Offset from thumb top when drag started (kept for compatibility)
---@field _dragStartMouseX number -- Mouse X position when drag started
---@field _dragStartMouseY number -- Mouse Y position when drag started
---@field _dragStartScrollX number -- Scroll X position when drag started
---@field _dragStartScrollY number -- Scroll Y position when drag started
---@field _scrollbarPressHandled boolean -- Track if scrollbar press was handled this frame
---@field _touchScrolling boolean -- True if currently touch scrolling
---@field _scrollVelocityX number -- Current horizontal scroll velocity (px/s)
---@field _scrollVelocityY number -- Current vertical scroll velocity (px/s)
---@field _momentumScrolling boolean -- True if momentum scrolling is active
---@field _lastTouchTime number -- Timestamp of last touch move
---@field _lastTouchX number -- Last touch X position
---@field _lastTouchY number -- Last touch Y position
---@field _Color table
---@field _utils table
---@field _ErrorHandler table? ErrorHandler module dependency
local ScrollManager = {}
ScrollManager.__index = ScrollManager

--- Initialize module with shared dependencies
---@param deps table Dependencies {ErrorHandler}
function ScrollManager.init(deps)
  if type(deps) == "table" then
    ScrollManager._ErrorHandler = deps.ErrorHandler or ScrollManager._ErrorHandler
    ScrollManager._Context = deps.Context or ScrollManager._Context
    ScrollManager._StateManager = deps.StateManager or ScrollManager._StateManager
  end
end

--- Create a new ScrollManager instance
---@param config table Configuration options
---@param deps table Dependencies {Color: Color module, utils: utils module}
---@return ScrollManager
function ScrollManager.new(config, deps)
  local Color = deps.Color
  local self = setmetatable({}, ScrollManager)

  -- Store dependencies for instance methods
  self._Color = Color
  self._utils = deps.utils

  -- Configuration
  self.overflow = config.overflow or "hidden"
  self.overflowX = config.overflowX
  self.overflowY = config.overflowY

  -- Scrollbar appearance
  self.scrollbarWidth = config.scrollbarWidth or 12
  self.scrollbarColor = config.scrollbarColor or Color.new(0.5, 0.5, 0.5, 0.8)
  self.scrollbarTrackColor = config.scrollbarTrackColor or Color.new(0.2, 0.2, 0.2, 0.5)
  self.scrollbarRadius = config.scrollbarRadius or 6
  self.scrollbarPadding = config.scrollbarPadding or 2
  self.scrollSpeed = config.scrollSpeed or 20
  self.invertScroll = config.invertScroll or false
  self.scrollBarStyle = config.scrollBarStyle -- Theme scrollbar style name (nil = use default)

  -- scrollbarKnobOffset can be number or table {x, y} or {horizontal, vertical}
  -- Only normalize if actually provided (nil means use theme default)
  if config.scrollbarKnobOffset ~= nil then
    self.scrollbarKnobOffset = self._utils.normalizeOffsetTable(config.scrollbarKnobOffset, 0)
  else
    self.scrollbarKnobOffset = nil
  end

  -- hideScrollbars can be boolean or table {vertical: boolean, horizontal: boolean}
  self.hideScrollbars = self._utils.normalizeBooleanTable(config.hideScrollbars, false)

  -- Scrollbar placement: "reserve-space" (default) or "overlay"
  self.scrollbarPlacement = config.scrollbarPlacement or "reserve-space"

  -- Scrollbar balance: when true, reserve space on both sides for visual balance
  self.scrollbarBalance = config.scrollbarBalance or false

  -- Touch scrolling configuration
  self.touchScrollEnabled = config.touchScrollEnabled ~= false -- Default true
  self.momentumScrollEnabled = config.momentumScrollEnabled ~= false -- Default true
  self.bounceEnabled = config.bounceEnabled ~= false -- Default true
  self.scrollFriction = config.scrollFriction or 0.95 -- legacy per-frame decay; superseded by _momentumDecel
  self._momentumDecel = config.momentumDecel or 2.0 -- fling decay rate (1/s), dt-based; ~iOS "normal"
  self.bounceStiffness = config.bounceStiffness or 0.2 -- Spring constant
  self.maxOverscroll = config.maxOverscroll or 100 -- pixels

  -- Internal overflow state
  self._overflowX = false
  self._overflowY = false
  self._contentWidth = 0
  self._contentHeight = 0

  -- Scroll state (can be restored from config in immediate mode)
  self._scrollX = config._scrollX or 0
  self._scrollY = config._scrollY or 0
  self._targetScrollX = nil
  self._targetScrollY = nil
  self._smoothScrollSpeed = 0.25 -- Interpolation speed (0-1, higher = faster); legacy, superseded by _smoothScrollRate
  self._smoothScrollRate = config.smoothScrollRate or 30 -- dt-based decay constant (1/s); ~90% converged in 2.3/rate s
  self.smoothScrollEnabled = config.smoothScrollEnabled or false -- Enable smooth wheel scrolling
  self._maxScrollX = 0
  self._maxScrollY = 0

  -- Scrollbar interaction state
  self._scrollbarHoveredVertical = false
  self._scrollbarHoveredHorizontal = false
  self._scrollbarDragging = false
  self._hoveredScrollbar = nil -- "vertical" or "horizontal"
  self._scrollbarDragOffset = 0 -- DEPRECATED: kept for backward compatibility
  self._dragStartMouseX = 0 -- Mouse X position when drag started
  self._dragStartMouseY = 0 -- Mouse Y position when drag started
  self._dragStartScrollX = 0 -- Scroll X position when drag started
  self._dragStartScrollY = 0 -- Scroll Y position when drag started
  self._scrollbarPressHandled = false

  -- Touch scrolling state
  self._touchScrolling = false
  self._scrollVelocityX = 0
  self._scrollVelocityY = 0
  self._momentumScrolling = false
  self._lastTouchTime = 0
  self._lastTouchX = 0
  self._lastTouchY = 0

  return self
end

--- Get the space reserved for scrollbars (width and height reduction)
--- This is called BEFORE layout to reduce available space for children
---@param element Element The parent Element instance
---@return number reservedWidth, number reservedHeight
function ScrollManager:getReservedSpace()
  if self.scrollbarPlacement ~= "reserve-space" then
    return 0, 0
  end

  local overflowX = self.overflowX or self.overflow
  local overflowY = self.overflowY or self.overflow

  local reservedWidth = 0
  local reservedHeight = 0

  -- Reserve space for vertical scrollbar if overflow mode requires it
  if (overflowY == "scroll" or overflowY == "auto") and not self.hideScrollbars.vertical then
    local scrollbarSpace = self.scrollbarWidth + (self.scrollbarPadding * 2)
    reservedWidth = self.scrollbarBalance and (scrollbarSpace * 2) or scrollbarSpace
  end

  -- Reserve space for horizontal scrollbar if overflow mode requires it
  if (overflowX == "scroll" or overflowX == "auto") and not self.hideScrollbars.horizontal then
    local scrollbarSpace = self.scrollbarWidth + (self.scrollbarPadding * 2)
    reservedHeight = self.scrollbarBalance and (scrollbarSpace * 2) or scrollbarSpace
  end

  return reservedWidth, reservedHeight
end

--- Detect if content overflows container bounds
---@param element Element The parent Element instance
function ScrollManager:detectOverflow(element)
  -- Reset overflow state
  self._overflowX = false
  self._overflowY = false
  self._contentWidth = element.width
  self._contentHeight = element.height

  -- Skip detection if overflow is visible (no clipping needed)
  local overflowX = self.overflowX or self.overflow
  local overflowY = self.overflowY or self.overflow
  if overflowX == "visible" and overflowY == "visible" then
    return
  end

  -- Calculate content bounds based on children
  if #element.children == 0 then
    return -- No children, no overflow
  end

  local maxX, maxY = 0, 0

  -- Content area starts after padding
  local contentX = element.x + element.padding.left
  local contentY = element.y + element.padding.top

  for _, child in ipairs(element.children) do
    -- Skip absolutely positioned children (they don't contribute to overflow)
    if not child._explicitlyAbsolute then
      -- Calculate child's margin box bounds relative to content area
      local childMarginRight = child.x - contentX + child:getBorderBoxWidth() + child.margin.right
      local childMarginBottom = child.y - contentY + child:getBorderBoxHeight() + child.margin.bottom

      -- Track the maximum extents (we ignore negative space from margins)
      maxX = math.max(maxX, childMarginRight)
      maxY = math.max(maxY, childMarginBottom)
    end
  end

  -- Calculate content dimensions
  self._contentWidth = maxX
  self._contentHeight = maxY

  -- Detect overflow (compare against content area, not total element size).
  -- element.width/height semantics depend on unit type:
  --   px units  → border-box size (padding NOT yet subtracted)
  --   %, vh, vw → content size (padding already subtracted by LayoutEngine)
  --   auto      → content size
  -- Using getBorderBoxWidth/Height() normalises both cases: border-box - padding = content.
  local containerWidth = element:getBorderBoxWidth() - element.padding.left - element.padding.right
  local containerHeight = element:getBorderBoxHeight() - element.padding.top - element.padding.bottom

  -- If scrollbarPlacement is "reserve-space", we need to subtract the reserved space
  -- because the layout already accounted for it, but element.width/height are still full size
  if self.scrollbarPlacement == "reserve-space" then
    local reservedWidth, reservedHeight = self:getReservedSpace()
    containerWidth = containerWidth - reservedWidth
    containerHeight = containerHeight - reservedHeight
  end

  self._overflowX = self._contentWidth > containerWidth
  self._overflowY = self._contentHeight > containerHeight

  -- Calculate maximum scroll bounds
  self._maxScrollX = math.max(0, self._contentWidth - containerWidth)
  self._maxScrollY = math.max(0, self._contentHeight - containerHeight)

  -- Clamp current scroll position to new bounds
  self._scrollX = self._utils.clamp(self._scrollX, 0, self._maxScrollX)
  self._scrollY = self._utils.clamp(self._scrollY, 0, self._maxScrollY)
end

--- Set scroll position with bounds clamping
---@param x number? -- X scroll position (nil to keep current)
---@param y number? -- Y scroll position (nil to keep current)
function ScrollManager:setScroll(x, y)
  if x ~= nil then
    self._scrollX = self._utils.clamp(x, 0, self._maxScrollX)
  end
  if y ~= nil then
    self._scrollY = self._utils.clamp(y, 0, self._maxScrollY)
  end
end

--- Get current scroll position
---@return number scrollX, number scrollY
function ScrollManager:getScroll()
  return self._scrollX, self._scrollY
end

--- Scroll by delta amount
---@param dx number? -- X delta (nil for no change)
---@param dy number? -- Y delta (nil for no change)
function ScrollManager:scrollBy(dx, dy)
  if dx then
    self._scrollX = self._utils.clamp(self._scrollX + dx, 0, self._maxScrollX)
  end
  if dy then
    self._scrollY = self._utils.clamp(self._scrollY + dy, 0, self._maxScrollY)
  end
end

--- Get maximum scroll bounds
---@return number maxScrollX, number maxScrollY
function ScrollManager:getMaxScroll()
  return self._maxScrollX, self._maxScrollY
end

--- Get scroll percentage (0-1)
---@return number percentX, number percentY
function ScrollManager:getScrollPercentage()
  local percentX = self._maxScrollX > 0 and (self._scrollX / self._maxScrollX) or 0
  local percentY = self._maxScrollY > 0 and (self._scrollY / self._maxScrollY) or 0
  return percentX, percentY
end

--- Check if element has overflow
---@return boolean hasOverflowX, boolean hasOverflowY
function ScrollManager:hasOverflow()
  return self._overflowX, self._overflowY
end

--- Get content dimensions (including overflow)
---@return number contentWidth, number contentHeight
function ScrollManager:getContentSize()
  return self._contentWidth, self._contentHeight
end

--- Calculate scrollbar dimensions and positions
---@param element Element The parent Element instance
---@return table -- {vertical: {visible, trackHeight, thumbHeight, thumbY}, horizontal: {visible, trackWidth, thumbWidth, thumbX}}
function ScrollManager:calculateScrollbarDimensions(element)
  local result = {
    vertical = { visible = false, trackHeight = 0, thumbHeight = 0, thumbY = 0 },
    horizontal = { visible = false, trackWidth = 0, thumbWidth = 0, thumbX = 0 },
  }

  local overflowX = self.overflowX or self.overflow
  local overflowY = self.overflowY or self.overflow

  -- Vertical scrollbar
  -- Note: overflow="scroll" always shows scrollbar; overflow="auto" only when content overflows
  if overflowY == "scroll" then
    -- Always show scrollbar for "scroll" mode
    result.vertical.visible = true
    result.vertical.trackHeight = element.height - (self.scrollbarPadding * 2)

    if self._overflowY then
      -- Content overflows, calculate proper thumb size
      local contentRatio = element.height / math.max(self._contentHeight, element.height)
      result.vertical.thumbHeight = math.max(20, result.vertical.trackHeight * contentRatio)

      -- Calculate thumb position based on scroll ratio
      local scrollRatio = self._maxScrollY > 0 and (self._scrollY / self._maxScrollY) or 0
      local maxThumbY = result.vertical.trackHeight - result.vertical.thumbHeight
      result.vertical.thumbY = maxThumbY * scrollRatio
    else
      -- No overflow, thumb fills entire track
      result.vertical.thumbHeight = result.vertical.trackHeight
      result.vertical.thumbY = 0
    end
  elseif self._overflowY and overflowY == "auto" then
    -- Only show scrollbar when content actually overflows
    result.vertical.visible = true
    result.vertical.trackHeight = element.height - (self.scrollbarPadding * 2)

    -- Calculate thumb height based on content ratio
    local contentRatio = element.height / math.max(self._contentHeight, element.height)
    result.vertical.thumbHeight = math.max(20, result.vertical.trackHeight * contentRatio)

    -- Calculate thumb position based on scroll ratio
    local scrollRatio = self._maxScrollY > 0 and (self._scrollY / self._maxScrollY) or 0
    local maxThumbY = result.vertical.trackHeight - result.vertical.thumbHeight
    result.vertical.thumbY = maxThumbY * scrollRatio
  end

  -- Horizontal scrollbar
  -- Note: overflow="scroll" always shows scrollbar; overflow="auto" only when content overflows
  if overflowX == "scroll" then
    -- Always show scrollbar for "scroll" mode
    result.horizontal.visible = true
    result.horizontal.trackWidth = element.width - (self.scrollbarPadding * 2)

    if self._overflowX then
      -- Content overflows, calculate proper thumb size
      local contentRatio = element.width / math.max(self._contentWidth, element.width)
      result.horizontal.thumbWidth = math.max(20, result.horizontal.trackWidth * contentRatio)

      -- Calculate thumb position based on scroll ratio
      local scrollRatio = self._maxScrollX > 0 and (self._scrollX / self._maxScrollX) or 0
      local maxThumbX = result.horizontal.trackWidth - result.horizontal.thumbWidth
      result.horizontal.thumbX = maxThumbX * scrollRatio
    else
      -- No overflow, thumb fills entire track
      result.horizontal.thumbWidth = result.horizontal.trackWidth
      result.horizontal.thumbX = 0
    end
  elseif self._overflowX and overflowX == "auto" then
    -- Only show scrollbar when content actually overflows
    result.horizontal.visible = true
    result.horizontal.trackWidth = element.width - (self.scrollbarPadding * 2)

    -- Calculate thumb width based on content ratio
    local contentRatio = element.width / math.max(self._contentWidth, element.width)
    result.horizontal.thumbWidth = math.max(20, result.horizontal.trackWidth * contentRatio)

    -- Calculate thumb position based on scroll ratio
    local scrollRatio = self._maxScrollX > 0 and (self._scrollX / self._maxScrollX) or 0
    local maxThumbX = result.horizontal.trackWidth - result.horizontal.thumbWidth
    result.horizontal.thumbX = maxThumbX * scrollRatio
  end

  return result
end

--- Get scrollbar at mouse position
---@param element Element The parent Element instance
---@param mouseX number
---@param mouseY number
---@return table|nil -- {component: "vertical"|"horizontal", region: "thumb"|"track"}
function ScrollManager:getScrollbarAtPosition(element, mouseX, mouseY)
  local overflowX = self.overflowX or self.overflow
  local overflowY = self.overflowY or self.overflow

  if not (overflowX == "scroll" or overflowX == "auto" or overflowY == "scroll" or overflowY == "auto") then
    return nil
  end

  local dims = self:calculateScrollbarDimensions(element)
  local x, y = element.x, element.y
  local w, h = element.width, element.height

  -- Check vertical scrollbar (only if not hidden)
  if dims.vertical.visible and not self.hideScrollbars.vertical then
    -- Position scrollbar within content area (x, y is border-box origin)
    local contentX = x + element.padding.left
    local contentY = y + element.padding.top
    local trackX = contentX + w - self.scrollbarWidth - self.scrollbarPadding
    local trackY = contentY + self.scrollbarPadding
    local trackW = self.scrollbarWidth
    local trackH = dims.vertical.trackHeight

    if mouseX >= trackX and mouseX <= trackX + trackW and mouseY >= trackY and mouseY <= trackY + trackH then
      -- Check if over thumb
      local thumbY = trackY + dims.vertical.thumbY
      local thumbH = dims.vertical.thumbHeight
      if mouseY >= thumbY and mouseY <= thumbY + thumbH then
        return { component = "vertical", region = "thumb" }
      else
        return { component = "vertical", region = "track" }
      end
    end
  end

  -- Check horizontal scrollbar (only if not hidden)
  if dims.horizontal.visible and not self.hideScrollbars.horizontal then
    -- Position scrollbar within content area (x, y is border-box origin)
    local contentX = x + element.padding.left
    local contentY = y + element.padding.top
    local trackX = contentX + self.scrollbarPadding
    local trackY = contentY + h - self.scrollbarWidth - self.scrollbarPadding
    local trackW = dims.horizontal.trackWidth
    local trackH = self.scrollbarWidth

    if mouseX >= trackX and mouseX <= trackX + trackW and mouseY >= trackY and mouseY <= trackY + trackH then
      -- Check if over thumb
      local thumbX = trackX + dims.horizontal.thumbX
      local thumbW = dims.horizontal.thumbWidth
      if mouseX >= thumbX and mouseX <= thumbX + thumbW then
        return { component = "horizontal", region = "thumb" }
      else
        return { component = "horizontal", region = "track" }
      end
    end
  end

  return nil
end

--- Handle scrollbar mouse press
---@param element Element The parent Element instance
---@param mouseX number
---@param mouseY number
---@param button number
---@return boolean -- True if event was consumed
function ScrollManager:handleMousePress(element, mouseX, mouseY, button)
  if button ~= 1 then
    return false
  end -- Only left click

  local scrollbar = self:getScrollbarAtPosition(element, mouseX, mouseY)
  if not scrollbar then
    return false
  end

  if scrollbar.region == "thumb" then
    -- Start dragging thumb - store start positions for relative movement tracking
    self._scrollbarDragging = true
    self._hoveredScrollbar = scrollbar.component

    -- Store drag start positions for relative movement calculation
    self._dragStartMouseX = mouseX
    self._dragStartMouseY = mouseY
    self._dragStartScrollX = self._scrollX
    self._dragStartScrollY = self._scrollY

    return true -- Event consumed
  elseif scrollbar.region == "track" then
    self:_scrollToTrackPosition(element, mouseX, mouseY, scrollbar.component)
    return true
  end

  return false
end

--- Handle scrollbar drag
---@param element Element The parent Element instance
---@param mouseX number
---@param mouseY number
---@return boolean -- True if event was consumed
function ScrollManager:handleMouseMove(element, mouseX, mouseY)
  if not self._scrollbarDragging then
    return false
  end

  local dims = self:calculateScrollbarDimensions(element)

  if self._hoveredScrollbar == "vertical" then
    local trackH = dims.vertical.trackHeight
    local thumbH = dims.vertical.thumbHeight

    -- Calculate relative mouse movement from drag start
    local mouseDeltaY = mouseY - self._dragStartMouseY

    -- Convert mouse delta to scroll delta
    -- scrollDelta / maxScroll = thumbDelta / (trackHeight - thumbHeight)
    local scrollableTrackHeight = trackH - thumbH
    local scrollDelta = scrollableTrackHeight > 0 and (mouseDeltaY / scrollableTrackHeight) * self._maxScrollY or 0

    local newScrollY = self._dragStartScrollY + scrollDelta
    newScrollY = self._utils.clamp(newScrollY, 0, self._maxScrollY)

    self:setScroll(nil, newScrollY)
    return true
  elseif self._hoveredScrollbar == "horizontal" then
    local trackW = dims.horizontal.trackWidth
    local thumbW = dims.horizontal.thumbWidth

    -- Calculate relative mouse movement from drag start
    local mouseDeltaX = mouseX - self._dragStartMouseX

    -- Convert mouse delta to scroll delta
    local scrollableTrackWidth = trackW - thumbW
    local scrollDelta = scrollableTrackWidth > 0 and (mouseDeltaX / scrollableTrackWidth) * self._maxScrollX or 0

    -- Apply delta to starting scroll position
    local newScrollX = self._dragStartScrollX + scrollDelta
    newScrollX = self._utils.clamp(newScrollX, 0, self._maxScrollX)

    self:setScroll(newScrollX, nil)
    return true
  end

  return false
end

--- Handle scrollbar release
---@param button number
---@return boolean -- True if event was consumed
function ScrollManager:handleMouseRelease(button)
  if button ~= 1 then
    return false
  end

  if self._scrollbarDragging then
    self._scrollbarDragging = false
    return true
  end

  return false
end

--- Scroll to track click position (internal helper)
---@param element Element The parent Element instance
---@param mouseX number
---@param mouseY number
---@param component string -- "vertical" or "horizontal"
function ScrollManager:_scrollToTrackPosition(element, mouseX, mouseY, component)
  local dims = self:calculateScrollbarDimensions(element)

  if component == "vertical" then
    local contentY = element.y + element.padding.top
    local trackY = contentY + self.scrollbarPadding
    local trackH = dims.vertical.trackHeight
    local thumbH = dims.vertical.thumbHeight

    -- Calculate target thumb position (centered on click)
    local targetThumbY = mouseY - trackY - (thumbH / 2)
    targetThumbY = self._utils.clamp(targetThumbY, 0, trackH - thumbH)

    -- Convert to scroll position
    local scrollRatio = (trackH - thumbH) > 0 and (targetThumbY / (trackH - thumbH)) or 0
    local newScrollY = scrollRatio * self._maxScrollY

    self:setScroll(nil, newScrollY)
  elseif component == "horizontal" then
    local contentX = element.x + element.padding.left
    local trackX = contentX + self.scrollbarPadding
    local trackW = dims.horizontal.trackWidth
    local thumbW = dims.horizontal.thumbWidth

    -- Calculate target thumb position (centered on click)
    local targetThumbX = mouseX - trackX - (thumbW / 2)
    targetThumbX = self._utils.clamp(targetThumbX, 0, trackW - thumbW)

    -- Convert to scroll position
    local scrollRatio = (trackW - thumbW) > 0 and (targetThumbX / (trackW - thumbW)) or 0
    local newScrollX = scrollRatio * self._maxScrollX

    self:setScroll(newScrollX, nil)
  end
end

--- Handle mouse wheel scrolling
---@param x number -- Horizontal scroll amount
---@param y number -- Vertical scroll amount
---@return boolean -- True if scroll was handled
function ScrollManager:handleWheel(x, y)
  local overflowX = self.overflowX or self.overflow
  local overflowY = self.overflowY or self.overflow

  if not (overflowX == "scroll" or overflowX == "auto" or overflowY == "scroll" or overflowY == "auto") then
    return false
  end

  -- In immediate mode, overflow might not be calculated yet, so allow scrolling based on maxScroll values
  -- If _overflowY is nil/false but _maxScrollY > 0, we should still allow scrolling (from restored state)
  local hasVerticalOverflow = (self._overflowY and self._maxScrollY > 0) or (self._maxScrollY and self._maxScrollY > 0)
  local hasHorizontalOverflow = (self._overflowX and self._maxScrollX > 0)
    or (self._maxScrollX and self._maxScrollX > 0)

  local scrolled = false

  -- Vertical scrolling
  if y ~= 0 and (overflowY == "scroll" or overflowY == "auto") and hasVerticalOverflow then
    local delta = -y * self.scrollSpeed -- Negative because wheel up = scroll up
    if self.invertScroll then
      delta = -delta -- Invert scroll direction if enabled
    end
    if self.smoothScrollEnabled then
      -- Set target for smooth scrolling instead of instant jump
      self._targetScrollY = self._utils.clamp((self._targetScrollY or self._scrollY) + delta, 0, self._maxScrollY)
    else
      -- Instant scrolling (default behavior)
      local newScrollY = self._scrollY + delta
      self:setScroll(nil, newScrollY)
    end
    scrolled = true
  end

  -- Horizontal scrolling
  if x ~= 0 and (overflowX == "scroll" or overflowX == "auto") and hasHorizontalOverflow then
    local delta = -x * self.scrollSpeed
    if self.invertScroll then
      delta = -delta -- Invert scroll direction if enabled
    end
    if self.smoothScrollEnabled then
      -- Set target for smooth scrolling instead of instant jump
      self._targetScrollX = self._utils.clamp((self._targetScrollX or self._scrollX) + delta, 0, self._maxScrollX)
    else
      -- Instant scrolling (default behavior)
      local newScrollX = self._scrollX + delta
      self:setScroll(newScrollX, nil)
    end
    scrolled = true
  end

  return scrolled
end

--- Update scrollbar hover state based on mouse position
---@param element Element The parent Element instance
---@param mouseX number
---@param mouseY number
function ScrollManager:updateHoverState(element, mouseX, mouseY)
  local scrollbar = self:getScrollbarAtPosition(element, mouseX, mouseY)

  if scrollbar then
    if scrollbar.component == "vertical" then
      self._scrollbarHoveredVertical = true
      self._scrollbarHoveredHorizontal = false
    elseif scrollbar.component == "horizontal" then
      self._scrollbarHoveredVertical = false
      self._scrollbarHoveredHorizontal = true
    end
  else
    self._scrollbarHoveredVertical = false
    self._scrollbarHoveredHorizontal = false
  end
end

--- Reset scrollbar press handled flag (call at start of frame)
function ScrollManager:resetScrollbarPressFlag()
  self._scrollbarPressHandled = false
end

--- Check if scrollbar press was handled this frame
---@return boolean
function ScrollManager:wasScrollbarPressHandled()
  return self._scrollbarPressHandled
end

--- Set scrollbar press handled flag
function ScrollManager:setScrollbarPressHandled()
  self._scrollbarPressHandled = true
end

--- Get state for immediate mode persistence
---@return table State data
function ScrollManager:getState()
  return {
    _scrollX = self._scrollX or 0,
    _scrollY = self._scrollY or 0,
    _targetScrollX = self._targetScrollX,
    _targetScrollY = self._targetScrollY,
    _scrollbarDragging = self._scrollbarDragging or false,
    _hoveredScrollbar = self._hoveredScrollbar,
    _scrollbarDragOffset = self._scrollbarDragOffset or 0, -- Deprecated but kept for compatibility
    _dragStartMouseX = self._dragStartMouseX or 0,
    _dragStartMouseY = self._dragStartMouseY or 0,
    _dragStartScrollX = self._dragStartScrollX or 0,
    _dragStartScrollY = self._dragStartScrollY or 0,
    _scrollbarHoveredVertical = self._scrollbarHoveredVertical or false,
    _scrollbarHoveredHorizontal = self._scrollbarHoveredHorizontal or false,
    scrollBarStyle = self.scrollBarStyle,
    scrollbarKnobOffset = self.scrollbarKnobOffset,
    scrollbarPlacement = self.scrollbarPlacement,
    scrollbarBalance = self.scrollbarBalance,
    _overflowX = self._overflowX,
    _overflowY = self._overflowY,
    _contentWidth = self._contentWidth,
    _contentHeight = self._contentHeight,
    -- Touch fling state: without these, immediate-mode recreation zeroes the
    -- release velocity on the next frame and momentum scrolling never runs.
    _touchScrolling = self._touchScrolling or false,
    _momentumScrolling = self._momentumScrolling or false,
    _scrollVelocityX = self._scrollVelocityX or 0,
    _scrollVelocityY = self._scrollVelocityY or 0,
    _lastTouchTime = self._lastTouchTime or 0,
    _lastTouchX = self._lastTouchX or 0,
    _lastTouchY = self._lastTouchY or 0,
  }
end

--- Set state from immediate mode persistence
---@param state table State data
function ScrollManager:setState(state)
  if not state then
    return
  end

  -- Support both old (scrollX) and new (_scrollX) field names for backward compatibility
  if state._scrollX ~= nil then
    self._scrollX = state._scrollX
  elseif state.scrollX ~= nil then
    self._scrollX = state.scrollX
  end

  if state._scrollY ~= nil then
    self._scrollY = state._scrollY
  elseif state.scrollY ~= nil then
    self._scrollY = state.scrollY
  end

  if state._scrollbarDragging ~= nil then
    self._scrollbarDragging = state._scrollbarDragging
  elseif state.scrollbarDragging ~= nil then
    self._scrollbarDragging = state.scrollbarDragging
  end

  if state._hoveredScrollbar ~= nil then
    self._hoveredScrollbar = state._hoveredScrollbar
  elseif state.hoveredScrollbar ~= nil then
    self._hoveredScrollbar = state.hoveredScrollbar
  end

  if state._scrollbarDragOffset ~= nil then
    self._scrollbarDragOffset = state._scrollbarDragOffset
  elseif state.scrollbarDragOffset ~= nil then
    self._scrollbarDragOffset = state.scrollbarDragOffset
  end

  -- Restore drag start positions for relative movement tracking
  if state._dragStartMouseX ~= nil then
    self._dragStartMouseX = state._dragStartMouseX
  end

  if state._dragStartMouseY ~= nil then
    self._dragStartMouseY = state._dragStartMouseY
  end

  if state._dragStartScrollX ~= nil then
    self._dragStartScrollX = state._dragStartScrollX
  end

  if state._dragStartScrollY ~= nil then
    self._dragStartScrollY = state._dragStartScrollY
  end

  if state._scrollbarHoveredVertical ~= nil then
    self._scrollbarHoveredVertical = state._scrollbarHoveredVertical
  end

  if state._scrollbarHoveredHorizontal ~= nil then
    self._scrollbarHoveredHorizontal = state._scrollbarHoveredHorizontal
  end

  if state.scrollBarStyle ~= nil then
    self.scrollBarStyle = state.scrollBarStyle
  end

  if state.scrollbarKnobOffset ~= nil then
    self.scrollbarKnobOffset = self._utils.normalizeOffsetTable(state.scrollbarKnobOffset, 0)
  end

  if state.scrollbarPlacement ~= nil then
    self.scrollbarPlacement = state.scrollbarPlacement
  end

  if state.scrollbarBalance ~= nil then
    self.scrollbarBalance = state.scrollbarBalance
  end

  if state._overflowX ~= nil then
    self._overflowX = state._overflowX
  end

  if state._overflowY ~= nil then
    self._overflowY = state._overflowY
  end

  if state._contentWidth ~= nil then
    self._contentWidth = state._contentWidth
  end

  if state._contentHeight ~= nil then
    self._contentHeight = state._contentHeight
  end

  if state._targetScrollX ~= nil then
    self._targetScrollX = state._targetScrollX
  end

  if state._targetScrollY ~= nil then
    self._targetScrollY = state._targetScrollY
  end

  -- Touch fling state (see getState): restore so momentum survives
  -- immediate-mode element recreation between frames.
  if state._touchScrolling ~= nil then
    self._touchScrolling = state._touchScrolling
  end
  if state._momentumScrolling ~= nil then
    self._momentumScrolling = state._momentumScrolling
  end
  if state._scrollVelocityX ~= nil then
    self._scrollVelocityX = state._scrollVelocityX
  end
  if state._scrollVelocityY ~= nil then
    self._scrollVelocityY = state._scrollVelocityY
  end
  if state._lastTouchTime ~= nil then
    self._lastTouchTime = state._lastTouchTime
  end
  if state._lastTouchX ~= nil then
    self._lastTouchX = state._lastTouchX
  end
  if state._lastTouchY ~= nil then
    self._lastTouchY = state._lastTouchY
  end
end

--- Handle touch press for scrolling
---@param touchX number
---@param touchY number
---@return boolean -- True if touch scroll started
function ScrollManager:handleTouchPress(touchX, touchY)
  if not self.touchScrollEnabled then
    return false
  end

  local overflowX = self.overflowX or self.overflow
  local overflowY = self.overflowY or self.overflow

  if not (overflowX == "scroll" or overflowX == "auto" or overflowY == "scroll" or overflowY == "auto") then
    return false
  end

  -- Stop momentum scrolling if active
  if self._momentumScrolling then
    self._momentumScrolling = false
    self._scrollVelocityX = 0
    self._scrollVelocityY = 0
  end

  -- Start touch scrolling
  self._touchScrolling = true
  self._lastTouchX = touchX
  self._lastTouchY = touchY
  self._lastTouchTime = love.timer.getTime()

  return true
end

--- Handle touch move for scrolling
---@param touchX number
---@param touchY number
---@return boolean -- True if touch scroll was handled
function ScrollManager:handleTouchMove(touchX, touchY)
  if not self._touchScrolling then
    return false
  end

  local currentTime = love.timer.getTime()
  local dt = currentTime - self._lastTouchTime

  if dt <= 0 then
    return false
  end

  -- Calculate delta and velocity
  local dx = touchX - self._lastTouchX
  local dy = touchY - self._lastTouchY

  -- Invert deltas (touch moves opposite to scroll)
  dx = -dx
  dy = -dy

  -- Velocity tracking (pixels per second).  Not the raw last-sample d/dt:
  -- touch samples jitter, and the final pre-release sample often reads near
  -- zero, which is why single-sample flings feel dead compared to a native
  -- list.  Blend toward the instantaneous velocity with a ~50 ms time
  -- constant instead, like OS velocity trackers that average recent samples.
  local instX, instY = dx / dt, dy / dt
  local blend = math.min(1, dt / 0.05)
  self._scrollVelocityX = self._scrollVelocityX + (instX - self._scrollVelocityX) * blend
  self._scrollVelocityY = self._scrollVelocityY + (instY - self._scrollVelocityY) * blend

  -- Apply scroll with bounce if enabled
  if self.bounceEnabled then
    -- Allow overscroll
    local newScrollX = self._scrollX + dx
    local newScrollY = self._scrollY + dy

    -- Clamp to max overscroll limits
    local minScrollX = -self.maxOverscroll
    local maxScrollX = self._maxScrollX + self.maxOverscroll
    local minScrollY = -self.maxOverscroll
    local maxScrollY = self._maxScrollY + self.maxOverscroll

    newScrollX = self._utils.clamp(newScrollX, minScrollX, maxScrollX)
    newScrollY = self._utils.clamp(newScrollY, minScrollY, maxScrollY)

    self._scrollX = newScrollX
    self._scrollY = newScrollY
  else
    -- Normal clamped scrolling
    self:scrollBy(dx, dy)
  end

  -- Update last touch state
  self._lastTouchX = touchX
  self._lastTouchY = touchY
  self._lastTouchTime = currentTime

  return true
end

--- Handle touch release for scrolling
---@return boolean -- True if touch scroll was active
function ScrollManager:handleTouchRelease()
  if not self._touchScrolling then
    return false
  end

  self._touchScrolling = false

  -- A finger that pauses and then lifts is a stop, not a fling: without
  -- this, the smoothed velocity from the earlier drag still launches the
  -- list after a deliberate hold (native lists kill the tracker the same
  -- way).
  if love.timer.getTime() - (self._lastTouchTime or 0) > 0.1 then
    self._scrollVelocityX = 0
    self._scrollVelocityY = 0
  end

  -- Start momentum scrolling if enabled and velocity is significant
  if self.momentumScrollEnabled then
    local velocityThreshold = 50 -- pixels per second
    local totalVelocity = math.sqrt(self._scrollVelocityX ^ 2 + self._scrollVelocityY ^ 2)

    if totalVelocity > velocityThreshold then
      self._momentumScrolling = true
    else
      self._scrollVelocityX = 0
      self._scrollVelocityY = 0
    end
  else
    self._scrollVelocityX = 0
    self._scrollVelocityY = 0
  end

  return true
end

--- Update momentum scrolling (call every frame with dt)
---@param dt number Delta time in seconds
function ScrollManager:update(dt)
  -- Smooth scroll interpolation.  The blend factor is derived from dt
  -- (exponential approach) rather than a fixed per-frame fraction, so the
  -- animation converges in the same wall-clock time regardless of frame
  -- rate; a fixed fraction made scrolling visibly slower whenever frame
  -- time rose.  _smoothScrollRate is the decay constant in 1/seconds:
  -- ~90% of the remaining distance is covered in 2.3/rate seconds.
  -- dt can legitimately be 0 here: in immediate mode beginFrame resets the
  -- accumulated dt BEFORE endFrame updates the elements, so the launcher's
  -- update order always hands this 0. Treat that (and nil) as one nominal
  -- 60 Hz step so the interpolation still advances one frame's worth.
  local step = (dt and dt > 0) and dt or (1 / 60)
  if self._targetScrollX or self._targetScrollY then
    local alpha = 1 - math.exp(-(self._smoothScrollRate or 30) * step)
    if self._targetScrollY then
      local diff = self._targetScrollY - self._scrollY
      if math.abs(diff) > 0.5 then
        self._scrollY = self._scrollY + diff * alpha
      else
        self._scrollY = self._targetScrollY
        self._targetScrollY = nil
      end
    end

    if self._targetScrollX then
      local diff = self._targetScrollX - self._scrollX
      if math.abs(diff) > 0.5 then
        self._scrollX = self._scrollX + diff * alpha
      else
        self._scrollX = self._targetScrollX
        self._targetScrollX = nil
      end
    end
  end

  if not self._momentumScrolling then
    -- Handle bounce back if overscrolled
    if self.bounceEnabled then
      self:_updateBounce(dt)
    end
    return
  end

  -- Apply velocity to scroll position (step, not dt: dt is 0 in the
  -- immediate-mode endFrame path, which left touch flings completely dead)
  local dx = self._scrollVelocityX * step
  local dy = self._scrollVelocityY * step

  if self.bounceEnabled then
    -- Allow overscroll during momentum, but never past maxOverscroll: an
    -- unclamped fling carried a list hundreds of pixels past its edge
    -- (rows vanished into a blank card until the spring crawled back).
    self._scrollX = self._utils.clamp(self._scrollX + dx,
      -self.maxOverscroll, self._maxScrollX + self.maxOverscroll)
    self._scrollY = self._utils.clamp(self._scrollY + dy,
      -self.maxOverscroll, self._maxScrollY + self.maxOverscroll)
  else
    self:scrollBy(dx, dy)
  end

  -- Frame-rate-independent exponential decay tuned to native list feel:
  -- iOS "normal" deceleration is ~0.998 per millisecond, i.e. exp(-2.0 t).
  -- The old per-frame 0.95 factor killed a fling in a fraction of a second
  -- (and faster the higher the frame rate).  Total fling travel is
  -- velocity / rate.
  local decay = math.exp(-(self._momentumDecel or 2.0) * step)
  -- Past the content edge, kill the fling an order of magnitude faster so
  -- the rubber band absorbs it instead of stretching to the clamp and
  -- sitting there (native lists do the same).
  local overX = self._scrollX < 0 or self._scrollX > self._maxScrollX
  local overY = self._scrollY < 0 or self._scrollY > self._maxScrollY
  if overX or overY then
    decay = decay * math.exp(-20 * step)
  end
  self._scrollVelocityX = self._scrollVelocityX * decay
  self._scrollVelocityY = self._scrollVelocityY * decay

  -- Stop momentum when velocity is very low
  local totalVelocity = math.sqrt(self._scrollVelocityX ^ 2 + self._scrollVelocityY ^ 2)
  if totalVelocity < 5 then
    self._momentumScrolling = false
    self._scrollVelocityX = 0
    self._scrollVelocityY = 0
  end

  -- Handle bounce back if overscrolled
  if self.bounceEnabled then
    self:_updateBounce(dt)
  end
end

--- Update bounce effect when overscrolled (internal)
---@param dt number Delta time in seconds
function ScrollManager:_updateBounce()
  local bounced = false

  -- Bounce back horizontal overscroll
  if self._scrollX < 0 then
    local springForce = -self._scrollX * self.bounceStiffness
    self._scrollX = self._scrollX + springForce
    if math.abs(self._scrollX) < 0.5 then
      self._scrollX = 0
    end
    bounced = true
  elseif self._scrollX > self._maxScrollX then
    local overflow = self._scrollX - self._maxScrollX
    local springForce = -overflow * self.bounceStiffness
    self._scrollX = self._scrollX + springForce
    if math.abs(overflow) < 0.5 then
      self._scrollX = self._maxScrollX
    end
    bounced = true
  end

  -- Bounce back vertical overscroll
  if self._scrollY < 0 then
    local springForce = -self._scrollY * self.bounceStiffness
    self._scrollY = self._scrollY + springForce
    if math.abs(self._scrollY) < 0.5 then
      self._scrollY = 0
    end
    bounced = true
  elseif self._scrollY > self._maxScrollY then
    local overflow = self._scrollY - self._maxScrollY
    local springForce = -overflow * self.bounceStiffness
    self._scrollY = self._scrollY + springForce
    if math.abs(overflow) < 0.5 then
      self._scrollY = self._maxScrollY
    end
    bounced = true
  end

  -- Stop momentum if bouncing
  if bounced and self._momentumScrolling then
    -- Reduce velocity during bounce
    self._scrollVelocityX = self._scrollVelocityX * 0.9
    self._scrollVelocityY = self._scrollVelocityY * 0.9
  end
end

--- Check if currently touch scrolling
---@return boolean
function ScrollManager:isTouchScrolling()
  return self._touchScrolling
end

--- Check if currently momentum scrolling
---@return boolean
function ScrollManager:isMomentumScrolling()
  return self._momentumScrolling
end

-------------------------------------------------------------------------------
-- Element-facing delegates
--
-- These wrappers bind the Element class's scroll API directly onto the
-- ScrollManager instance methods. Each takes the Element as its first argument
-- (the role `self` played when these methods lived on Element), performs the
-- nil-safety guard, invokes the owning ScrollManager instance, and syncs state
-- back onto the element for backward-compatible readers (Renderer, FlexLove,
-- Context hit-testing read these fields from Element).
--
-- Element binds them via direct assignment in Element.init, e.g.
--   Element.scrollToTop = Element._ScrollManager.scrollToTop
-- so Element retains only 1-line delegates and owns no scroll logic.
-------------------------------------------------------------------------------

local _EMPTY_SCROLLBAR_DIMS = {
  vertical = { visible = false, trackHeight = 0, thumbHeight = 0, thumbY = 0 },
  horizontal = { visible = false, trackWidth = 0, thumbWidth = 0, thumbX = 0 },
}

--- Sync internal scroll state onto the element for backward-compatible readers.
---@param element table Element instance whose _scrollManager holds the state
function ScrollManager.syncToElement(element)
  local sm = element._scrollManager
  if not sm then
    return
  end
  element._overflowX = sm._overflowX
  element._overflowY = sm._overflowY
  element._contentWidth = sm._contentWidth
  element._contentHeight = sm._contentHeight
  element._scrollX = sm._scrollX
  element._scrollY = sm._scrollY
  element._maxScrollX = sm._maxScrollX
  element._maxScrollY = sm._maxScrollY
  element._scrollbarHoveredVertical = sm._scrollbarHoveredVertical
  element._scrollbarHoveredHorizontal = sm._scrollbarHoveredHorizontal
  element._scrollbarDragging = sm._scrollbarDragging
  element._hoveredScrollbar = sm._hoveredScrollbar
  element._scrollbarDragOffset = sm._scrollbarDragOffset
end

--- Backward-compatible alias retained by Element internals (update hover/drag).
ScrollManager.syncScrollManagerState = ScrollManager.syncToElement

--- Detect overflow and sync state onto element.
---@param element table Element instance
function ScrollManager._detectOverflow(element)
  local sm = element._scrollManager
  if not sm then
    return
  end
  sm:detectOverflow(element)
  ScrollManager.syncToElement(element)
end

--- Set scroll position (element-facing). Nil args keep the current axis.
---@param element table Element instance
---@param x number? X scroll position
---@param y number? Y scroll position
function ScrollManager.setScrollPosition(element, x, y)
  local sm = element._scrollManager
  if not sm then
    return
  end
  sm:setScroll(x, y)
  ScrollManager.syncToElement(element)
end

--- Calculate scrollbar dimensions (element-facing).
---@param element table Element instance
---@return table dims {vertical, horizontal}
function ScrollManager._calculateScrollbarDimensions(element)
  local sm = element._scrollManager
  if not sm then
    return _EMPTY_SCROLLBAR_DIMS
  end
  return sm:calculateScrollbarDimensions(element)
end

--- Get scrollbar at mouse position (element-facing).
---@param element table Element instance
---@param mouseX number
---@param mouseY number
---@return table|nil {component, region}
function ScrollManager._getScrollbarAtPosition(element, mouseX, mouseY)
  local sm = element._scrollManager
  if not sm then
    return nil
  end
  return sm:getScrollbarAtPosition(element, mouseX, mouseY)
end

--- Handle scrollbar mouse press (element-facing).
---@param element table Element instance
---@param mouseX number
---@param mouseY number
---@param button number
---@return boolean consumed
function ScrollManager._handleScrollbarPress(element, mouseX, mouseY, button)
  local sm = element._scrollManager
  if not sm then
    return false
  end
  local consumed = sm:handleMousePress(element, mouseX, mouseY, button)
  ScrollManager.syncToElement(element)
  return consumed
end

--- Handle scrollbar drag (element-facing).
---@param element table Element instance
---@param mouseX number
---@param mouseY number
---@return boolean consumed
function ScrollManager._handleScrollbarDrag(element, mouseX, mouseY)
  local sm = element._scrollManager
  if not sm then
    return false
  end
  local consumed = sm:handleMouseMove(element, mouseX, mouseY)
  ScrollManager.syncToElement(element)
  return consumed
end

--- Handle scrollbar release (element-facing).
---@param element table Element instance
---@param button number
---@return boolean consumed
function ScrollManager._handleScrollbarRelease(element, button)
  local sm = element._scrollManager
  if not sm then
    return false
  end
  local consumed = sm:handleMouseRelease(button)
  ScrollManager.syncToElement(element)
  return consumed
end

--- Handle mouse wheel scrolling (element-facing).
---@param element table Element instance
---@param x number Horizontal scroll amount
---@param y number Vertical scroll amount
---@return boolean consumed
function ScrollManager._handleWheelScroll(element, x, y)
  local sm = element._scrollManager
  if not sm then
    return false
  end
  local consumed = sm:handleWheel(x, y)
  ScrollManager.syncToElement(element)
  return consumed
end

--- Get current scroll position (element-facing).
---@param element table Element instance
---@return number scrollX, number scrollY
function ScrollManager.getScrollPosition(element)
  local sm = element._scrollManager
  if not sm then
    return 0, 0
  end
  return sm:getScroll()
end

-- The following getters share names with ScrollManager *instance* methods,
-- so the element-facing wrappers use distinct `element`-prefixed names to
-- avoid shadowing the instance API (tests call sm:getMaxScroll() etc.).

--- Get maximum scroll bounds (element-facing).
---@param element table Element instance
---@return number maxScrollX, number maxScrollY
function ScrollManager.elementGetMaxScroll(element)
  local sm = element._scrollManager
  if not sm then
    return 0, 0
  end
  return sm:getMaxScroll()
end

--- Get scroll percentage 0-1 (element-facing).
---@param element table Element instance
---@return number percentX, number percentY
function ScrollManager.elementGetScrollPercentage(element)
  local sm = element._scrollManager
  if not sm then
    return 0, 0
  end
  return sm:getScrollPercentage()
end

--- Check if element has overflow (element-facing).
---@param element table Element instance
---@return boolean hasOverflowX, boolean hasOverflowY
function ScrollManager.elementHasOverflow(element)
  local sm = element._scrollManager
  if not sm then
    return false, false
  end
  return sm:hasOverflow()
end

--- Get content dimensions (element-facing).
---@param element table Element instance
---@return number contentWidth, number contentHeight
function ScrollManager.elementGetContentSize(element)
  local sm = element._scrollManager
  if not sm then
    return 0, 0
  end
  return sm:getContentSize()
end

--- Scroll by relative delta (element-facing).
-- In immediate mode, per-axis deltas whose scroll bound is still 0 are deferred
-- until layout calculates the bound (delegates to Element:_deferMethod).
---@param element table Element instance
---@param dx number? X delta
---@param dy number? Y delta
function ScrollManager.elementScrollBy(element, dx, dy)
  local sm = element._scrollManager
  if not sm then
    return
  end
  local maxScrollX, maxScrollY = sm:getMaxScroll()
  if dx ~= nil and maxScrollX == 0 then
    element:_deferMethod("scrollBy", dx, nil)
    dx = nil
  end
  if dy ~= nil and maxScrollY == 0 then
    element:_deferMethod("scrollBy", nil, dy)
    dy = nil
  end
  if dx ~= nil or dy ~= nil then
    sm:scrollBy(dx, dy)
    ScrollManager.syncToElement(element)
  end
end

--- Jump to the top of scrollable content.
---@param element table Element instance
function ScrollManager.scrollToTop(element)
  element:setScrollPosition(nil, 0)
end

--- Jump to the bottom of scrollable content.
-- Defers until layout has calculated the vertical scroll bound.
---@param element table Element instance
function ScrollManager.scrollToBottom(element)
  local sm = element._scrollManager
  if not sm then
    return
  end
  local _, maxScrollY = sm:getMaxScroll()
  if maxScrollY > 0 then
    element:setScrollPosition(nil, maxScrollY)
  else
    element:_deferMethod("scrollToBottom")
  end
end

--- Jump to the leftmost position of scrollable content.
---@param element table Element instance
function ScrollManager.scrollToLeft(element)
  element:setScrollPosition(0, nil)
end

--- Jump to the rightmost position of scrollable content.
-- Defers until layout has calculated the horizontal scroll bound.
---@param element table Element instance
function ScrollManager.scrollToRight(element)
  local sm = element._scrollManager
  if not sm then
    return
  end
  local maxScrollX, _ = sm:getMaxScroll()
  if maxScrollX > 0 then
    element:setScrollPosition(maxScrollX, nil)
  else
    element:_deferMethod("scrollToRight")
  end
end

--- Restore scrollbar state from StateManager in immediate mode.
---@param element table Element instance
function ScrollManager.restoreImmediateState(element)
  -- Mode-aware guard: only immediate-mode frames keep state in StateManager;
  -- in retained mode the element (and its ScrollManager) persist between
  -- frames, so there is nothing to restore. Routed through StateManager so no
  -- raw mode check lives here (behavior-mode-unification task 11).
  if not element._stateId or not ScrollManager._StateManager.isImmediateMode() then
    return
  end
  local state = ScrollManager._StateManager.getState(element._stateId)
  if not state or not state.scrollManager then
    return
  end
  local sm_state = state.scrollManager
  element._scrollbarHoveredVertical = sm_state._scrollbarHoveredVertical or false
  element._scrollbarHoveredHorizontal = sm_state._scrollbarHoveredHorizontal or false
  element._scrollbarDragging = sm_state._scrollbarDragging or false
  element._hoveredScrollbar = sm_state._hoveredScrollbar
  element._scrollbarDragOffset = sm_state._scrollbarDragOffset or 0

  local sm = element._scrollManager
  if sm then
    sm._scrollbarHoveredVertical = element._scrollbarHoveredVertical
    sm._scrollbarHoveredHorizontal = element._scrollbarHoveredHorizontal
    sm._scrollbarDragging = element._scrollbarDragging
    sm._hoveredScrollbar = element._hoveredScrollbar
    sm._scrollbarDragOffset = element._scrollbarDragOffset
    sm._dragStartMouseX = sm_state._dragStartMouseX or 0
    sm._dragStartMouseY = sm_state._dragStartMouseY or 0
    sm._dragStartScrollX = sm_state._dragStartScrollX or 0
    sm._dragStartScrollY = sm_state._dragStartScrollY or 0
  end
end

--- Update hover, drag, and press interaction for scrollbars during Element:update.
---@param element table Element instance
---@param mx number Mouse X
---@param my number Mouse Y
function ScrollManager.updateInteraction(element, mx, my)
  local sm = element._scrollManager
  if sm then
    sm:updateHoverState(element, mx, my)
    ScrollManager.syncToElement(element)
  end

  if element._scrollbarDragging and love.mouse.isDown(1) then
    ScrollManager._handleScrollbarDrag(element, mx, my)
  elseif element._scrollbarDragging then
    if sm then
      sm:handleMouseRelease(1)
      ScrollManager.syncToElement(element)
    end
    if element._stateId and ScrollManager._StateManager.isImmediateMode() then
      ScrollManager._StateManager.updateState(element._stateId, {
        scrollbarDragging = false,
      })
    end
  end

  -- Handle scrollbar press for elements with scrollable overflow
  local overflowX = element.overflowX or element.overflow
  local overflowY = element.overflowY or element.overflow
  local hasScrollableOverflow = (
    overflowX == "scroll"
    or overflowX == "auto"
    or overflowY == "scroll"
    or overflowY == "auto"
  )

  if hasScrollableOverflow and not element._scrollbarDragging then
    if love.mouse.isDown(1) and not element._scrollbarPressHandled then
      local scrollbarPressed = ScrollManager._handleScrollbarPress(element, mx, my, 1)
      if scrollbarPressed then
        element._scrollbarPressHandled = true
      end
    elseif not love.mouse.isDown(1) then
      element._scrollbarPressHandled = false
    end
  end
end

return ScrollManager
