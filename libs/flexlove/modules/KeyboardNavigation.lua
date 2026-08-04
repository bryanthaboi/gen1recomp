local packageName = ... or "KeyboardNavigation"
local modulePath = packageName:match("(.-)[^%.]+$")

local function req(name)
  return require(modulePath .. name)
end

---@class KeyboardNavigation
---@field config KeyboardNavigationConfig
local KeyboardNavigation = {

  config = {
    -- Global settings
    enabled = true,
    debugMode = false,

    -- Key bindings
    keys = {
      next = "tab",
      previous = "shifttab",
      up = "up",
      down = "down",
      left = "left",
      right = "right",
      activate = { "return", "space" },
      dismiss = "escape",
      toggleDebug = "f12",
      inspect = "i",
    },

    -- Navigation behavior
    wrapAround = true,
    directionalNavigation = true,
    focusVisible = true,
    autofocusOnCreate = false,

    --- Drop focus after pressing Enter/Space to activate an element
    --- When false, focus remains on the element after activation
    dropFocusOnSelection = true,

    -- Developer tools
    developerTools = {
      enabled = true,
      showProperties = true,
      highlightColor = { 1, 0.8, 0, 0.5 },
    },

    -- Focus indicator style
    focusIndicator = {
      color = { 0.2, 0.6, 1.0, 0.8 },
      lineWidth = 2,
      inset = -3,
      borderRadius = 4,
      animationDuration = 0.15,
    },
  },

  -- State
  _navigationStack = {},
  _lastNavigationTime = 0,
  _inspectMode = false,
  _deps = nil,

  -- Spatial index for directional navigation (performance optimization)
  _spatialIndex = {
    enabled = false,
    cellSize = 100, -- Grid cell size in pixels
    grid = {}, -- Grid storing element references
    elementPositions = {}, -- Cache of element positions {element = {x, y, w, h}}
    lastUpdateFrame = 0,
  },
}

--- Initialize KeyboardNavigation module
---@param deps table {Context, Element, ErrorHandler, utils, InputEvent}
function KeyboardNavigation.init(deps)
  -- Validate required dependencies
  local required = { Context = true, Element = true, ErrorHandler = true, utils = true, InputEvent = true }
  for depName, _ in pairs(required) do
    if not deps[depName] then
      error(string.format("KeyboardNavigation.init: Missing required dependency: %s", depName))
    end
  end

  KeyboardNavigation._deps = deps
  KeyboardNavigation._ErrorHandler = deps.ErrorHandler
  KeyboardNavigation._InputEvent = deps.InputEvent
  KeyboardNavigation._Context = deps.Context
  KeyboardNavigation._Element = deps.Element
  KeyboardNavigation._utils = deps.utils
end

--- Handle keyboard press for navigation
---@param key string
---@param scancode string
---@param isrepeat boolean
---@return boolean handled
function KeyboardNavigation:handleKeyPress(key, scancode, isrepeat)
  if not KeyboardNavigation._Context then
    return false
  end

  -- Debug logging
  if KeyboardNavigation.config.debugMode then
    print(
      string.format(
        "[KeyboardNavigation] Key pressed: %s (scancode: %s, repeat: %s)",
        key,
        scancode,
        tostring(isrepeat)
      )
    )
    print(string.format("[KeyboardNavigation] Enabled: %s", tostring(KeyboardNavigation.config.enabled)))
  end

  local config = KeyboardNavigation.config
  local keys = config.keys

  -- Check for activation keys
  for _, activateKey in ipairs(keys.activate) do
    if key == activateKey then
      return self:activateElement()
    end
  end

  -- Check for dismiss key
  if key == keys.dismiss then
    return self:dismissElement()
  end

  -- Check for next/previous navigation
  -- Tab with shift held = previous; Tab without shift = next
  if key == keys.next then
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
      return self:previousFocusable()
    end
    return self:nextFocusable()
  end

  if key == keys.previous then
    return self:previousFocusable()
  end

  -- Check for directional navigation
  if config.directionalNavigation then
    if key == keys.up then
      return self:navigateDirectional("up")
    elseif key == keys.down then
      return self:navigateDirectional("down")
    elseif key == keys.left then
      return self:navigateDirectional("left")
    elseif key == keys.right then
      return self:navigateDirectional("right")
    end
  end

  return false
end

--- Find next focusable element in the focusable list
---@param focusableList table<Element> List of focusable elements in tab order
---@param current Element? Currently focused element
---@return Element?
function KeyboardNavigation:_findNextInList(focusableList, current)
  local currentIndex = 0
  if current then
    for i, elem in ipairs(focusableList) do
      if elem.id == current.id then
        currentIndex = i
        break
      end
    end
  end

  -- Search forward
  if currentIndex < #focusableList then
    return focusableList[currentIndex + 1]
  end

  -- Wrap around if enabled
  if KeyboardNavigation.config.wrapAround and #focusableList > 0 then
    return focusableList[1]
  end

  return nil
end

--- Get the focusable element list scoped to the navigation container
---@return Element[]
function KeyboardNavigation:_getScopedFocusableList()
  local Context = KeyboardNavigation._Context
  local container = Context.getNavigationContainer()
  if container then
    return container:getFocusableChildren()
  end
  return Context.getFocusableElements()
end

--- Navigate to next focusable element (Tab)
---@return boolean success
function KeyboardNavigation:nextFocusable()
  local Context = KeyboardNavigation._Context

  local current = Context.getFocused()
  if KeyboardNavigation.config.debugMode then
    print(
      string.format("[KeyboardNavigation] Tab pressed - Current focus: %s", tostring(current and current.id or "nil"))
    )
  end

  local focusableList = self:_getScopedFocusableList()
  local nextElem = self:_findNextInList(focusableList, current)

  if nextElem then
    self:_focusElement(nextElem)
    return true
  end

  return false
end

--- Find previous focusable element in the focusable list
---@param focusableList table<Element> List of focusable elements in tab order
---@param current Element? Currently focused element
---@return Element?
function KeyboardNavigation:_findPreviousInList(focusableList, current)
  local currentIndex = #focusableList + 1
  if current then
    for i, elem in ipairs(focusableList) do
      if elem.id == current.id then
        currentIndex = i
        break
      end
    end
  end

  -- Search backward
  if currentIndex - 1 >= 1 then
    return focusableList[currentIndex - 1]
  end

  -- Wrap around if enabled
  if KeyboardNavigation.config.wrapAround and #focusableList > 0 then
    return focusableList[#focusableList]
  end

  return nil
end

--- Navigate to previous focusable element (Shift+Tab)
---@return boolean success
function KeyboardNavigation:previousFocusable()
  local Context = KeyboardNavigation._Context

  local current = Context.getFocused()

  local focusableList = self:_getScopedFocusableList()
  local prevElem = self:_findPreviousInList(focusableList, current)

  if prevElem then
    self:_focusElement(prevElem)
    return true
  end

  return false
end

--- Navigate using arrow keys
---@param direction "up"|"down"|"left"|"right"
---@return boolean success
function KeyboardNavigation:navigateDirectional(direction)
  local Context = KeyboardNavigation._Context
  local current = Context.getFocused()

  if not current then
    return false
  end

  local nextElem = KeyboardNavigation:_findDirectionalNeighbor(current, direction)

  if nextElem then
    self:_focusElement(nextElem)
    return true
  end

  return false
end

--- Find closest focusable element in the given direction
---@param current Element
---@param direction "up"|"down"|"left"|"right"
---@return Element?
function KeyboardNavigation:_findDirectionalNeighbor(current, direction)
  -- Try spatial index first if enabled
  if KeyboardNavigation._spatialIndex.enabled then
    local spatialResult = self:_findDirectionalNeighborSpatial(current, direction)
    if spatialResult then
      return spatialResult
    end
  end

  -- Collect all focusable elements visible this frame
  local Context = KeyboardNavigation._Context
  local focusable = {}

  local function collectFocusable(elem)
    if elem:isFocusable() and elem ~= current then
      table.insert(focusable, elem)
    end
    for _, child in ipairs(elem.children) do
      collectFocusable(child)
    end
  end

  -- Mode-agnostic: collect from Context's focusable list
  local allFocusable = Context.getFocusableElements()
  for _, elem in ipairs(allFocusable) do
    if elem ~= current then
      table.insert(focusable, elem)
    end
  end

  if #focusable == 0 then
    return nil
  end

  local currentRect = {
    x = current.x,
    y = current.y,
    width = current.width or 0,
    height = current.height or 0,
  }

  local closest = nil
  local closestDistance = math.huge

  for _, elem in ipairs(focusable) do
    local elemRect = {
      x = elem.x,
      y = elem.y,
      width = elem.width or 0,
      height = elem.height or 0,
    }

    local distance, isInDirection = self:_calculateDirectionalDistance(currentRect, elemRect, direction)

    if isInDirection and distance < closestDistance then
      closest = elem
      closestDistance = distance
    end
  end

  -- If no element found in exact direction, try with looser criteria
  if not closest then
    closest = self:_findClosestInDirection(current, focusable, direction)
  end

  return closest
end

--- Calculate distance and direction between elements
---@param from table {x, y, width, height}
---@param to table {x, y, width, height}
---@param direction string
---@return number distance, boolean isInDirection
function KeyboardNavigation:_calculateDirectionalDistance(from, to, direction)
  -- Calculate bounding box edges
  local fromLeft = from.x
  local fromRight = from.x + from.width
  local fromTop = from.y
  local fromBottom = from.y + from.height

  local toLeft = to.x
  local toRight = to.x + to.width
  local toTop = to.y
  local toBottom = to.y + to.height

  local distance = math.huge
  local isInDirection = false

  if direction == "up" then
    if toBottom < fromTop then
      isInDirection = true
      distance = fromTop - toBottom
    end
  elseif direction == "down" then
    if toTop > fromBottom then
      isInDirection = true
      distance = toTop - fromBottom
    end
  elseif direction == "left" then
    if toRight < fromLeft then
      isInDirection = true
      distance = fromLeft - toRight
    end
  elseif direction == "right" then
    if toLeft > fromRight then
      isInDirection = true
      distance = toLeft - fromRight
    end
  end

  return distance, isInDirection
end

--- Find closest element in direction using center-to-center distance
---@param current Element
---@param focusable Element[]
---@param direction string
---@return Element?
function KeyboardNavigation:_findClosestInDirection(current, focusable, direction)
  local currentCenterX = current.x + (current.width or 0) / 2
  local currentCenterY = current.y + (current.height or 0) / 2

  local closest = nil
  local closestDistance = math.huge

  for _, elem in ipairs(focusable) do
    if elem ~= current then
      local elemCenterX = elem.x + (elem.width or 0) / 2
      local elemCenterY = elem.y + (elem.height or 0) / 2

      local dx = elemCenterX - currentCenterX
      local dy = elemCenterY - currentCenterY

      -- Check if element is generally in the right direction
      local isInDirection = false

      if direction == "up" and dy < 0 then
        isInDirection = true
      elseif direction == "down" and dy > 0 then
        isInDirection = true
      elseif direction == "left" and dx < 0 then
        isInDirection = true
      elseif direction == "right" and dx > 0 then
        isInDirection = true
      end

      if isInDirection then
        local distance = math.sqrt(dx * dx + dy * dy)
        if distance < closestDistance then
          closest = elem
          closestDistance = distance
        end
      end
    end
  end

  return closest
end

--- Focus an element
---@param element Element
function KeyboardNavigation:_focusElement(element)
  local Context = KeyboardNavigation._Context

  if element and element:isFocusable() then
    if KeyboardNavigation.config.debugMode then
      print(
        string.format(
          "[KeyboardNavigation] Focusing element: %s (id: %s)",
          element.themeComponent or "unknown",
          tostring(element.id)
        )
      )
    end
    Context.setFocused(element)

    -- Update focus indicator
    if KeyboardNavigation.FocusIndicator then
      KeyboardNavigation.FocusIndicator.setFocused(element)
    end

    -- Call onFocus callback if it exists
    if element.onFocus then
      local success, err = pcall(function()
        if element.onFocusDeferred then
          table.insert(Context._deferredCallbacks or {}, function()
            element:onFocus(element)
          end)
        else
          element:onFocus(element)
        end
      end)

      if not success then
        KeyboardNavigation._ErrorHandler:warn("KeyboardNavigation", "NAV_001", {
          elementId = element.id or "unknown",
          error = tostring(err),
        })
      end
    end
  end
end

---@param element Element
---@return boolean
function KeyboardNavigation:_shouldDropFocusOnSelection(element)
  if element and element.dropFocusOnSelection ~= nil then
    return element.dropFocusOnSelection == true
  end

  return KeyboardNavigation.config.dropFocusOnSelection == true
end

--- Activate currently focused element
---@return boolean success
function KeyboardNavigation:activateElement()
  local Context = KeyboardNavigation._Context
  local focused = Context.getFocused()

  if not focused then
    return false
  end

  if focused.disabled then
    return false
  end

  -- Fire press and release events
  if focused.onEvent then
    local modifiers = KeyboardNavigation._utils.getModifiers()
    local pressEvent = KeyboardNavigation._InputEvent.new({
      type = "press",
      button = 1,
      x = focused.x,
      y = focused.y,
      modifiers = modifiers,
      clickCount = 1,
    })

    local releaseEvent = KeyboardNavigation._InputEvent.new({
      type = "release",
      button = 1,
      x = focused.x,
      y = focused.y,
      modifiers = modifiers,
      clickCount = 1,
    })

    local success, err = pcall(function()
      focused.onEvent(focused, pressEvent)
      focused.onEvent(focused, releaseEvent)
    end)

    if not success then
      KeyboardNavigation._ErrorHandler:warn("KeyboardNavigation", "NAV_002", {
        elementId = focused.id or "unknown",
        error = tostring(err),
      })
    end

    -- Drop focus after selection based on per-element override or global config.
    if KeyboardNavigation:_shouldDropFocusOnSelection(focused) then
      Context.clearFocus()
      if KeyboardNavigation.FocusIndicator then
        KeyboardNavigation.FocusIndicator.setFocused(nil)
      end
    end

    return true
  end

  return false
end

--- Dismiss currently focused element
---@return boolean success
function KeyboardNavigation:dismissElement()
  local Context = KeyboardNavigation._Context
  local focused = Context.getFocused()

  if not focused then
    return false
  end

  -- Check if element has a dismiss handler
  if focused.onDismiss then
    local success, err = pcall(function()
      if focused.onDismissDeferred then
        table.insert(Context._deferredCallbacks or {}, function()
          focused:onDismiss(focused)
        end)
      else
        focused:onDismiss(focused)
      end
    end)

    if not success then
      KeyboardNavigation._ErrorHandler:warn("KeyboardNavigation", "NAV_003", {
        elementId = focused.id or "unknown",
        error = tostring(err),
      })
    end

    return true -- Handler took care of dismissal
  end

  -- Default behavior: blur the element (only if no onDismiss handler)
  Context.clearFocus()
  return true
end

--- Update keyboard navigation (for animations, etc.)
---@param dt number
function KeyboardNavigation:update(dt)
  -- Update focus indicator if it exists
  if KeyboardNavigation.FocusIndicator then
    KeyboardNavigation.FocusIndicator:update(dt)
  end
end

--- Push current focus onto stack (for modals/dialogs)
--- Saves current focus and sets new focus to the given element
---@param element Element? The element to focus (e.g., modal dialog)
function KeyboardNavigation:pushFocus(element)
  local Context = KeyboardNavigation._Context

  table.insert(KeyboardNavigation._navigationStack, Context.getFocused())
  Context.pushFocusStack(element)
end

--- Pop focus from stack (return from modal)
--- Restores previously focused element from the stack
---@return Element? The previously focused element, or nil if stack was empty
function KeyboardNavigation:popFocus()
  local Context = KeyboardNavigation._Context

  local previous = Context.popFocusStack()
  if #KeyboardNavigation._navigationStack > 0 then
    previous = table.remove(KeyboardNavigation._navigationStack)
  end

  return previous
end

-- ====================
-- Spatial Index (Performance Optimization)
-- ====================

--- Enable spatial index for faster directional navigation
---@param enabled boolean
function KeyboardNavigation.enableSpatialIndex(enabled)
  KeyboardNavigation._spatialIndex.enabled = enabled
  if not enabled then
    KeyboardNavigation:_clearSpatialIndex()
  end
end

--- Clear spatial index
function KeyboardNavigation:_clearSpatialIndex()
  KeyboardNavigation._spatialIndex.grid = {}
  KeyboardNavigation._spatialIndex.elementPositions = {}
end

--- Find directional neighbor using spatial index
---@param current Element
---@param direction "up"|"down"|"left"|"right"
---@return Element?
function KeyboardNavigation:_findDirectionalNeighborSpatial(current, direction)
  local index = KeyboardNavigation._spatialIndex
  local cellSize = index.cellSize

  -- Get current element's grid position
  local currentPos = index.elementPositions[current]
  if not currentPos then
    return nil
  end

  local centerX = currentPos.x + currentPos.w / 2
  local centerY = currentPos.y + currentPos.h / 2
  local currentCellX = math.floor(centerX / cellSize)
  local currentCellY = math.floor(centerY / cellSize)

  -- Search in direction, expanding outward
  local maxSearchRadius = 20 -- Maximum cells to search
  local visited = {}

  for radius = 1, maxSearchRadius do
    local candidates = {}

    -- Get cells in the search ring
    if direction == "up" then
      table.insert(candidates, { currentCellX, currentCellY - radius })
      if radius > 1 then
        table.insert(candidates, { currentCellX - 1, currentCellY - radius })
        table.insert(candidates, { currentCellX + 1, currentCellY - radius })
      end
    elseif direction == "down" then
      table.insert(candidates, { currentCellX, currentCellY + radius })
      if radius > 1 then
        table.insert(candidates, { currentCellX - 1, currentCellY + radius })
        table.insert(candidates, { currentCellX + 1, currentCellY + radius })
      end
    elseif direction == "left" then
      table.insert(candidates, { currentCellX - radius, currentCellY })
      if radius > 1 then
        table.insert(candidates, { currentCellX - radius, currentCellY - 1 })
        table.insert(candidates, { currentCellX - radius, currentCellY + 1 })
      end
    elseif direction == "right" then
      table.insert(candidates, { currentCellX + radius, currentCellY })
      if radius > 1 then
        table.insert(candidates, { currentCellX + radius, currentCellY - 1 })
        table.insert(candidates, { currentCellX + radius, currentCellY + 1 })
      end
    end

    -- Check each candidate cell
    for _, cell in ipairs(candidates) do
      local cellKey = string.format("%d,%d", cell[1], cell[2])
      local cellElements = index.grid[cellKey]

      if cellElements then
        for _, elem in ipairs(cellElements) do
          if elem ~= current and not visited[elem] then
            visited[elem] = true
            local elemPos = index.elementPositions[elem]
            if elemPos then
              local elemCenterX = elemPos.x + elemPos.w / 2
              local elemCenterY = elemPos.y + elemPos.h / 2

              -- Check if element is in the correct direction
              local isInDirection = false
              if direction == "up" and elemCenterY < centerY then
                isInDirection = true
              elseif direction == "down" and elemCenterY > centerY then
                isInDirection = true
              elseif direction == "left" and elemCenterX < centerX then
                isInDirection = true
              elseif direction == "right" and elemCenterX > centerX then
                isInDirection = true
              end

              if isInDirection then
                return elem
              end
            end
          end
        end
      end
    end
  end

  return nil
end

return KeyboardNavigation
