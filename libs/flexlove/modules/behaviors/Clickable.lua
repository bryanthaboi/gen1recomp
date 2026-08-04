-- modules/behaviors/Clickable.lua
--
-- Concrete behavior: mouse/touch event handling, pressed-state tracking,
-- hit-testing, and theme-state sync.
--
-- This is the largest behavior in the behavior-mode-unification refactor
-- (~200 LOC moved out of Element:update / _initSubSystems / saveState).
-- Task 02 extracts the entire `if self.onEvent or self.themeComponent or
-- self.editable or self._selectState or self.selectOption then ... end` block
-- from Element:update (hit-testing, mouse/touch event processing, immediate-
-- mode state save, theme-state update) plus EventHandler creation (formerly the
-- first half of Element:_initSubSystems) plus pressed-state drawing (formerly a
-- render layer in Renderer) plus EventHandler save/restore.
--
-- Attachment rule (shouldAttach): the same predicate that previously guarded
-- mouse-event processing in Element:update. An element owns the EventHandler /
-- gets press feedback exactly when it is interactive: when it declares an
-- `onEvent` callback, a `themeComponent`, is `editable`, or participates in a
-- Select group (selectParent / selectOption). A plain passive element never
-- attaches Clickable and therefore never allocates an EventHandler.
--
-- Element retains only the `self._eventHandler` field; Clickable owns it on
-- attach. All other Element paths that touched the EventHandler (handleTouchEvent,
-- handleGesture, getTouches) already nil-guard `self._eventHandler`, so they keep
-- working unchanged for non-clickable elements.
--
-- State ownership (per the locked Behavior contract):
--   * Per-element runtime state lives ON THE ELEMENT (self._eventHandler etc.).
--   * The behavior instance itself is stateless and shared across elements.
--   * Element-class-level dependencies (EventHandler factory, StateManager,
--     Context) are resolved from the owning element's metatable (the Element
--     class set by Element:_construct). This keeps the behavior stateless while
--     avoiding a dependency-injection parameter that would violate the locked
--     6-hook signature `(element, ...)`.

local _pkg = (...):match("^(.-)behaviors%.") or "modules."
local Behavior = require(_pkg .. "Behavior")

-- Resolve the Element class from an element instance.
-- Element instances are created via `setmetatable({}, Element)` in _construct,
-- so their metatable IS the Element class — giving us Element._EventHandler,
-- Element._eventHandlerDeps, Element._StateManager, Element._Context, etc.
-- without threading deps through the behavior hook signature.
local function ElementClass(element)
  return getmetatable(element)
end

-- ----------------------------------------------------------------------------
-- shouldAttach (class-level predicate, no element required)
-- ----------------------------------------------------------------------------

-- Mirrors the cases that previously caused Element to allocate + use an
-- EventHandler. MUST cover every element that touches the EventHandler at
-- runtime: click (onEvent), theme press-feedback (themeComponent), text mouse
-- interaction (editable), Select groups (selectParent / selectOption), touch
-- callbacks (onTouchEvent), and gesture callbacks (onGesture). selectParent /
-- selectOption are the props that produce _selectState during _initSubSystems;
-- checking the props (rather than the runtime _selectState) lets shouldAttach
-- run before the Select subsystem is initialized.
local function shouldAttach(props)
  props = props or {}
  return props.onEvent ~= nil
    or props.themeComponent ~= nil
    or props.editable == true
    or props.onTouchEvent ~= nil
    or props.onGesture ~= nil
    or props.selectOption ~= nil
    or props.selectParent ~= nil
end

-- ----------------------------------------------------------------------------
-- onAttach — create the EventHandler (formerly Element:_initSubSystems
-- lines ~640-690) and restore immediate-mode EventHandler state.
-- ----------------------------------------------------------------------------

local function onAttach(element)
  local Element = ElementClass(element)

  local eventHandlerConfig = {
    -- element.onEvent is source of truth; not cached on handler
    onEventDeferred = element.onEventDeferred,
    -- element.onTouchEvent is source of truth; not cached on handler
    onTouchEventDeferred = element.onTouchEventDeferred,
    -- element.onGesture is source of truth; not cached on handler
    onGestureDeferred = element.onGestureDeferred,
    touchEnabled = element.touchEnabled,
    multiTouchEnabled = element.multiTouchEnabled,
  }

  -- In immediate mode, restore EventHandler state from StateManager so pressed
  -- / hovered / click-count survive the per-frame element recreation cycle.
  -- Mode-aware via Context.isImmediateMode (behavior-mode-unification task 11):
  -- in retained mode the eventHandler persists, so nothing to restore.
  if Element._Context.isImmediateMode() and element._stateId and element._stateId ~= "" then
    local state = Element._StateManager.getState(element._stateId)
    if state then
      -- Restore EventHandler state from StateManager (sparse storage — provide defaults)
      eventHandlerConfig._pressed = state._pressed or {}
      eventHandlerConfig._lastClickTime = state._lastClickTime
      eventHandlerConfig._lastClickButton = state._lastClickButton
      eventHandlerConfig._clickCount = state._clickCount or 0
      eventHandlerConfig._dragStartX = state._dragStartX or {}
      eventHandlerConfig._dragStartY = state._dragStartY or {}
      eventHandlerConfig._lastMouseX = state._lastMouseX or {}
      eventHandlerConfig._lastMouseY = state._lastMouseY or {}
      eventHandlerConfig._hovered = state._hovered
    end
  end

  element._eventHandler = Element._EventHandler.new(eventHandlerConfig, Element._eventHandlerDeps)
end

local function onDetach(element)
  -- Clear focus callbacks read by KeyboardNavigation / TextEditor:focus so the
  -- element's closure references can be collected in immediate mode (formerly
  -- part of Element:_cleanup). The EventHandler instance itself is INTENTIONALLY
  -- kept: Element:_cleanup preserves element structure for inspection (the
  -- stale-element refs are released when the element is GC'd). onEvent,
  -- onTouchEvent, onGesture are also left intact — the Renderer/EventHandler
  -- read those directly from the element (not the cache), so clearing them
  -- would break retained mode.
  element.onFocus = nil
  element.onBlur = nil
end

-- ----------------------------------------------------------------------------
-- onUpdate — the mouse hit-testing + event-processing + theme-state +
-- immediate-mode save block (formerly Element:update lines ~2813-2960).
-- ----------------------------------------------------------------------------

local function onUpdate(element, dt)
  local Element = ElementClass(element)
  local eventHandler = element._eventHandler
  if not eventHandler then
    return
  end

  local mx, my = love.mouse.getPosition()

  -- Clickable area is the border box (x, y already includes padding)
  -- BORDER-BOX MODEL: Use stored border-box dimensions for hit detection
  local bx = element.x
  local by = element.y
  local bw = element._borderBoxWidth or (element.width + element.padding.left + element.padding.right)
  local bh = element._borderBoxHeight or (element.height + element.padding.top + element.padding.bottom)

  -- Account for scroll offsets from parent containers
  -- Walk up the parent chain and accumulate scroll offsets. This stays in
  -- Clickable because it's an interaction concern (hit-testing), not layout.
  local scrollOffsetX = 0
  local scrollOffsetY = 0
  local current = element.parent
  while current do
    local overflowX = current.overflowX or current.overflow
    local overflowY = current.overflowY or current.overflow
    local hasScrollableOverflow = (
      overflowX == "scroll"
      or overflowX == "auto"
      or overflowY == "scroll"
      or overflowY == "auto"
      or overflowX == "hidden"
      or overflowY == "hidden"
    )
    if hasScrollableOverflow then
      scrollOffsetX = scrollOffsetX + (current._scrollX or 0)
      scrollOffsetY = scrollOffsetY + (current._scrollY or 0)
    end
    current = current.parent
  end

  -- Adjust mouse position by accumulated scroll offset for hit testing
  local adjustedMx = mx + scrollOffsetX
  local adjustedMy = my + scrollOffsetY
  local isHovering = adjustedMx >= bx and adjustedMx <= bx + bw and adjustedMy >= by and adjustedMy <= by + bh

  -- Check if this is the topmost interactive element at the mouse position
  -- (z-index ordering). This prevents blocked/occluded elements from
  -- receiving interactions or visual feedback. A single mode-agnostic lookup
  -- via `Context.findInteractiveAtPosition` (unified-event-routing task 05)
  -- replaces the previous immediate/retained-mode split that used
  -- `getTopElementAt` in immediate mode and `_activeEventElement` in retained
  -- mode. `findInteractiveAtPosition` routes every hit test through
  -- `pointHitsElement` (the single canonical `display == false` guard) and
  -- resolves occlusion by z-index in both modes, so the active element is the
  -- same one that would receive a hit under the cursor.
  local topElement = Element._Context.findInteractiveAtPosition(mx, my)
  local isActiveElement = (topElement == element or topElement == nil)

  -- Reset scrollbar press flag at start of each frame
  eventHandler:resetScrollbarPressFlag()

  -- Process mouse events through EventHandler FIRST
  -- This ensures pressed states are updated before theme state is calculated
  eventHandler:processMouseEvents(element, mx, my, isHovering, isActiveElement)

  -- In immediate mode, save EventHandler state to StateManager after
  -- processing events so it survives the per-frame recreation.
  if element._stateId and Element._Context.isImmediateMode() and element._stateId ~= "" then
    local eventHandlerState = eventHandler:getState()
    Element._StateManager.updateState(element._stateId, {
      _pressed = eventHandlerState._pressed,
      _lastClickTime = eventHandlerState._lastClickTime,
      _lastClickButton = eventHandlerState._lastClickButton,
      _clickCount = eventHandlerState._clickCount,
      _dragStartX = eventHandlerState._dragStartX,
      _dragStartY = eventHandlerState._dragStartY,
      _lastMouseX = eventHandlerState._lastMouseX,
      _lastMouseY = eventHandlerState._lastMouseY,
      _hovered = eventHandlerState._hovered,
    })
  end

  -- Update theme state based on interaction. themeComponent state update
  -- lives in Clickable because it is driven by hover/press state; the actual
  -- theme RENDERING is the Themed behavior (task 07).
  if element.themeComponent then
    -- Check if any button is pressed via EventHandler
    local anyPressed = eventHandler:isAnyButtonPressed()

    -- Update theme state via ThemeManager
    local isFocused = Element._Context.getFocused() == element
    local newThemeState =
      element._themeManager:updateState(isHovering and isActiveElement, anyPressed, isFocused, element.disabled)

    if element._stateId and Element._Context.isImmediateMode() then
      local hover = newThemeState == "hover"
      local pressed = newThemeState == "pressed"
      local focused = isFocused

      Element._StateManager.updateState(element._stateId, {
        hover = hover,
        pressed = pressed,
        focused = focused,
        disabled = element.disabled,
        active = element.active,
      })
    end

    if element._renderer then
      element._renderer:setThemeState(newThemeState)
    end
  end

  -- Process touch events through EventHandler
  eventHandler:processTouchEvents(element)
end

-- ----------------------------------------------------------------------------
-- onDraw — pressed-state visual feedback (formerly Renderer Layer 5).
-- ----------------------------------------------------------------------------

-- Draws the grey pressed overlay when any mouse button is currently pressed on
-- the element. Delegates the actual pixels to Renderer:drawPressedState (which
-- owns the RoundedRect + opacity math) but drives the DECISION + transform
-- context here, so the renderer no longer needs the `if element.onEvent ...`
-- behavioral branch. Honors disableHighlight (themes handle their own visual
-- feedback) exactly as the old render layer did.
local function onDraw(element)
  if element.disableHighlight then
    return
  end
  local eventHandler = element._eventHandler
  if not eventHandler then
    return
  end

  local anyPressed = false
  local pressedState = eventHandler:getState()._pressed or {}
  for _, pressed in pairs(pressedState) do
    if pressed then
      anyPressed = true
      break
    end
  end
  if not anyPressed then
    return
  end

  local renderer = element._renderer
  if not renderer then
    return
  end

  local bw = element._borderBoxWidth or (element.width + element.padding.left + element.padding.right)
  local bh = element._borderBoxHeight or (element.height + element.padding.top + element.padding.bottom)

  -- Apply the element transform around the overlay, mirroring how the
  -- Renderer wrapped its whole command buffer (pressed state was a render
  -- layer subject to the same transform).
  local Element = ElementClass(element)
  local Transform = Element._Transform
  local hasTransform = element.transform ~= nil and Transform ~= nil and not Transform.isIdentity(element.transform)
  if hasTransform then
    Transform.apply(element.transform, element.x, element.y, element.width, element.height)
  end

  renderer:drawPressedState(element.x, element.y, bw, bh, element.opacity, element.cornerRadius)

  if hasTransform then
    Transform.unapply()
  end
end

-- ----------------------------------------------------------------------------
-- saveState / restoreState — EventHandler state (formerly the eventHandler
-- branches of Element:saveState / Element:restoreState).
-- ----------------------------------------------------------------------------

local function saveState(element)
  if element._eventHandler then
    return { eventHandler = element._eventHandler:getState() }
  end
  return nil
end

local function restoreState(element, state)
  if not state then
    return nil
  end
  if element._eventHandler and state.eventHandler then
    element._eventHandler:setState(state.eventHandler)
  end
  return nil
end

-- ----------------------------------------------------------------------------
-- Build the (stateless, shared, immutable) behavior instance.
-- ----------------------------------------------------------------------------

local Clickable = Behavior.new({
  onAttach = onAttach,
  onDetach = onDetach,
  onUpdate = onUpdate,
  onDraw = onDraw,
  saveState = saveState,
  restoreState = restoreState,
  shouldAttach = shouldAttach,
})

-- Expose the predicate at module level so callers/tests can reference it
-- directly without an element instance (mirrors Behavior.shouldAttach).
Clickable.shouldAttach = shouldAttach

return Clickable
