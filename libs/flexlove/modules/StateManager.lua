---@class StateManager
local StateManager = {}

-- ErrorHandler will be injected via init
local ErrorHandler

-- State storage: ID -> state table
local stateStore = {}

-- Frame tracking metadata: ID -> {lastFrame, createdFrame, accessCount}
local stateMetadata = {}

-- Frame counter
local frameNumber = 0

-- Counter to track multiple elements created at the same source location (e.g., in loops)
local callSiteCounters = {}

-- Stateful element mapping: stateId -> element instance
-- Used in retained mode for cache-through: StateManager resolves id -> element -> field
local statefulElements = {}

-- Dirty state tracking for flushFrame: set of {id, key} pairs modified this frame
local dirtyState = {}

-- Immediate mode flag
local _immediateMode = false

-- Configuration
local config = {
  stateRetentionFrames = 2, -- Keep unused state for 2 frames
  maxStateEntries = 1000, -- Maximum state entries before forced GC
}

-- Default state values (sparse storage - don't store these)
local stateDefaults = {
  -- Interaction states
  hover = false,
  pressed = false,
  focused = false,
  disabled = false,
  active = false,

  -- Scrollbar states
  scrollbarHoveredVertical = false,
  scrollbarHoveredHorizontal = false,
  scrollbarDragging = false,
  hoveredScrollbar = nil,
  scrollbarDragOffset = 0,
  dragStartMouseX = 0,
  dragStartMouseY = 0,
  dragStartScrollX = 0,
  dragStartScrollY = 0,

  -- Scroll position
  scrollX = 0,
  scrollY = 0,
  _scrollX = 0,
  _scrollY = 0,

  -- Click tracking
  _clickCount = 0,
  _lastClickTime = nil,
  _lastClickButton = nil,

  -- Internal states
  _hovered = nil,
  _focused = nil,
  _cursorPosition = nil,
  _selectionStart = nil,
  _selectionEnd = nil,
  _textBuffer = "",
  _cursorBlinkTimer = 0,
  _cursorVisible = true,
  _cursorBlinkPaused = false,
  _cursorBlinkPauseTimer = 0,
}

--- Check if a value equals the default for a key
---@param key string State key
---@param value any Value to check
---@return boolean isDefault True if value equals default
local function isDefaultValue(key, value)
  local defaultVal = stateDefaults[key]

  -- If no default defined, check for common defaults
  if defaultVal == nil then
    -- Empty tables are default
    if type(value) == "table" and next(value) == nil then
      return true
    end
    -- nil values are default
    if value == nil then
      return true
    end
    -- Otherwise, not a default value
    return false
  end

  -- Compare values
  if type(value) == "table" then
    -- Empty tables are considered default
    if next(value) == nil then
      return true
    end
    -- For other tables, compare contents (shallow)
    if type(defaultVal) ~= "table" then
      return false
    end
    for k, v in pairs(value) do
      if defaultVal[k] ~= v then
        return false
      end
    end
    return true
  else
    return value == defaultVal
  end
end

-- ====================
-- ID Generation
-- ====================

--- Generate a hash from a table of properties
---@param props table
---@param visited table|nil Tracking table to prevent circular references
---@param depth number|nil Current recursion depth
---@return string
local function hashProps(props, visited, depth)
  if not props then
    return ""
  end

  -- Initialize visited table on first call
  visited = visited or {}
  depth = depth or 0

  -- Limit recursion depth to prevent deep nesting issues
  if depth > 3 then
    return "[deep]"
  end

  -- Check if we've already visited this table (circular reference)
  if visited[props] then
    return "[circular]"
  end

  -- Mark this table as visited
  visited[props] = true

  local parts = {}
  local keys = {}

  -- Properties to skip (they cause issues or aren't relevant for ID generation)
  local skipKeys = {
    onEvent = true,
    parent = true,
    children = true,
    onFocus = true,
    onBlur = true,
    onTextInput = true,
    onTextChange = true,
    onEnter = true,
    userdata = true,
    -- Dynamic input/state properties that should not affect ID stability
    text = true, -- Text content changes as user types
    placeholder = true, -- Placeholder text is presentational
    editable = true, -- Editable state can be toggled dynamically
    selectOnFocus = true, -- Input behavior flag
    autoGrow = true, -- Auto-grow behavior flag
    passwordMode = true, -- Password mode can be toggled
  }

  -- Collect and sort keys for consistent ordering
  for k in pairs(props) do
    if not skipKeys[k] then
      table.insert(keys, k)
    end
  end
  table.sort(keys)

  -- Build hash string from sorted key-value pairs
  for _, k in ipairs(keys) do
    local v = props[k]
    local vtype = type(v)

    if vtype == "string" or vtype == "number" or vtype == "boolean" then
      table.insert(parts, k .. "=" .. tostring(v))
    elseif vtype == "table" then
      table.insert(parts, k .. "={" .. hashProps(v, visited, depth + 1) .. "}")
    end
  end

  return table.concat(parts, ";")
end

--- Generate a unique ID from call site and properties
---@param props table|nil Optional properties to include in ID generation
---@param parent table|nil Optional parent element for tree-based ID generation
---@return string
function StateManager.generateID(props, parent)
  -- Get call stack information
  local info = debug.getinfo(3, "Sl") -- Level 3: caller of Element.new -> caller of generateID

  if not info then
    -- Fallback to random ID if debug info unavailable
    return "auto_" .. tostring(math.random(1000000, 9999999))
  end

  local source = info.source or "unknown"
  local line = info.currentline or 0

  -- Create base location key from source file and line number
  local filename = source:match("([^/\\]+)$") or source -- Get filename
  filename = filename:gsub("%.lua$", "") -- Remove .lua extension
  local locationKey = filename .. "_L" .. line

  -- If we have a parent, use tree-based ID generation for stability
  if parent and parent.id and parent.id ~= "" then
    -- For child elements, use call-site (file + line) like top-level elements
    -- This ensures the same call site always generates the same ID, even when
    -- retained children persist in parent.children array
    local baseID = parent.id .. "_" .. locationKey

    -- Count how many children have been created at THIS call site
    local callSiteKey = parent.id .. "_" .. locationKey
    callSiteCounters[callSiteKey] = (callSiteCounters[callSiteKey] or 0) + 1
    local instanceNum = callSiteCounters[callSiteKey]

    if instanceNum > 1 then
      baseID = baseID .. "_" .. instanceNum
    end

    -- Add property hash if provided (for additional differentiation)
    if props then
      local propHash = hashProps(props)
      if propHash ~= "" then
        -- Use first 8 chars of a simple hash
        local hash = 0
        for i = 1, #propHash do
          hash = (hash * 31 + string.byte(propHash, i)) % 1000000
        end
        baseID = baseID .. "_" .. hash
      end
    end

    return baseID
  end

  -- No parent (top-level element): use call-site counter approach
  -- Track how many elements have been created at this location
  callSiteCounters[locationKey] = (callSiteCounters[locationKey] or 0) + 1
  local instanceNum = callSiteCounters[locationKey]

  local baseID = locationKey

  -- Add instance number if multiple elements created at same location (e.g., in loops)
  if instanceNum > 1 then
    baseID = baseID .. "_" .. instanceNum
  end

  -- Add property hash if provided (for additional differentiation)
  if props then
    local propHash = hashProps(props)
    if propHash ~= "" then
      -- Use first 8 chars of a simple hash
      local hash = 0
      for i = 1, #propHash do
        hash = (hash * 31 + string.byte(propHash, i)) % 1000000
      end
      baseID = baseID .. "_" .. hash
    end
  end

  return baseID
end

-- ====================
-- State Management
-- ====================

--- Initialize StateManager with dependencies
---@param deps table Dependencies: { ErrorHandler = ErrorHandler }
function StateManager.init(deps)
  if type(deps) == "table" then
    ErrorHandler = deps.ErrorHandler
  end
end

--- Get state for an element ID, creating if it doesn't exist
---@param id string Element ID
---@param defaultState table|nil Default state if creating new
---@return table state State table for the element
function StateManager.getState(id, defaultState)
  if not id then
    ErrorHandler:error("StateManager", "SYS_001", {
      parameter = "id",
      value = "nil",
    })
  end

  -- Create state if it doesn't exist
  if not stateStore[id] then
    -- Start with empty state (sparse storage)
    stateStore[id] = defaultState or {}

    -- Create metadata
    stateMetadata[id] = {
      lastFrame = frameNumber,
      createdFrame = frameNumber,
      accessCount = 0,
    }
  else
    -- Update metadata
    local meta = stateMetadata[id]
    meta.lastFrame = frameNumber
    meta.accessCount = meta.accessCount + 1
  end

  return stateStore[id]
end

--- Set state for an element ID (replaces entire state)
---@param id string Element ID
---@param state table State to store
function StateManager.setState(id, state)
  if not id then
    ErrorHandler:error("StateManager", "SYS_001", {
      parameter = "id",
      value = "nil",
    })
  end

  -- Create sparse state (remove default values)
  local sparseState = {}
  for key, value in pairs(state) do
    if not isDefaultValue(key, value) then
      sparseState[key] = value
    end
  end

  stateStore[id] = sparseState

  -- Update or create metadata
  if not stateMetadata[id] then
    stateMetadata[id] = {
      lastFrame = frameNumber,
      createdFrame = frameNumber,
      accessCount = 1,
    }
  else
    stateMetadata[id].lastFrame = frameNumber
  end
end

--- Update state for an element ID (merges with existing state)
---@param id string Element ID
---@param newState table New state values to merge
function StateManager.updateState(id, newState)
  local state = StateManager.getState(id)

  -- Merge new state into existing state (with diffing optimization)
  local changed = false
  for key, value in pairs(newState) do
    if state[key] ~= value then
      state[key] = value
      changed = true
    end
  end

  -- Only update metadata if something actually changed
  if changed then
    stateMetadata[id].lastFrame = frameNumber
  end
end

--- Update state only if values have changed (optimized for immediate mode)
---@param id string Element ID
---@param newState table New state values to merge
---@return boolean changed True if any values changed
function StateManager.updateStateIfChanged(id, newState)
  local state = StateManager.getState(id)
  local changed = false

  for key, value in pairs(newState) do
    -- Skip if value hasn't changed (optimization)
    if state[key] ~= value then
      state[key] = value
      changed = true
    end
  end

  if changed then
    stateMetadata[id].lastFrame = frameNumber
  end

  return changed
end

--- Clear state for a specific element ID
---@param id string Element ID
function StateManager.clearState(id)
  stateStore[id] = nil
  stateMetadata[id] = nil
end

--- Mark state as used this frame (updates last accessed frame)
---@param id string Element ID
function StateManager.markStateUsed(id)
  if stateMetadata[id] then
    stateMetadata[id].lastFrame = frameNumber
  end
end

-- ====================
-- Frame Management
-- ====================

--- Increment frame counter (called at frame start)
function StateManager.incrementFrame()
  frameNumber = frameNumber + 1
  -- Reset call site counters for new frame
  callSiteCounters = {}
end

--- Get current frame number
---@return number
function StateManager.getFrameNumber()
  return frameNumber
end

-- ====================
-- Granular State Access (Unified API for both modes)
-- ====================

--- Get a single state value by key for a given element ID.
--- Works identically in both modes — the caller does not need to know the mode.
---
--- Immediate mode: reads from persistent state store.
--- Retained mode: resolves through registered element field (cache-through).
---
---@param id string Element state ID
---@param key string State key
---@return any value The stored value, or nil if not found
function StateManager.getStateValue(id, key)
  if not id or not key then
    ErrorHandler:error("StateManager", "SYS_001", {
      parameter = "id and key",
      value = "missing",
    })
  end

  -- Update metadata for access tracking
  if stateMetadata[id] then
    stateMetadata[id].lastFrame = frameNumber
    stateMetadata[id].accessCount = stateMetadata[id].accessCount + 1
  end

  if _immediateMode then
    -- Immediate mode: read from persistent state store
    local state = stateStore[id]
    if state then
      return state[key]
    end
    return nil
  else
    -- Retained mode: resolve through element field
    local element = statefulElements[id]
    if element then
      return element[key]
    end
    return nil
  end
end

--- Set a single state value by key for a given element ID.
--- Works identically in both modes — the caller does not need to know the mode.
---
--- Immediate mode: marks dirty for flushFrame() persistence.
--- Retained mode: writes directly to element field (cache-through).
---
---@param id string Element state ID
---@param key string State key
---@param value any Value to store
function StateManager.setStateValue(id, key, value)
  if not id or not key then
    ErrorHandler:error("StateManager", "SYS_001", {
      parameter = "id and key",
      value = "missing",
    })
  end

  -- Update metadata
  if not stateMetadata[id] then
    stateMetadata[id] = {
      lastFrame = frameNumber,
      createdFrame = frameNumber,
      accessCount = 1,
    }
  else
    stateMetadata[id].lastFrame = frameNumber
  end

  if _immediateMode then
    -- Immediate mode: mark dirty for flushFrame persistence
    local state = StateManager.getState(id)
    state[key] = value
    dirtyState[id] = dirtyState[id] or {}
    dirtyState[id][key] = true
  else
    -- Retained mode: write directly to element field
    local element = statefulElements[id]
    if element then
      element[key] = value
    end
  end
end

-- ====================
-- Stateful Element Registration (Retained Mode Cache-Through)
-- ====================

--- Register an element instance for retained-mode cache-through.
--- After registration, getStateValue/setStateValue will resolve through the element's fields.
---
--- Called by Element in _construct phase.
---
---@param id string State ID (typically element.id)
---@param element table Element instance to link
function StateManager.registerStateful(id, element)
  if not id or not element then
    return
  end
  statefulElements[id] = element
end

--- Unregister an element instance.
--- After unregistration, retained-mode access will fall back to nil.
---
--- Called by Element in _cleanup phase.
---
---@param id string State ID to unregister
function StateManager.unregisterStateful(id)
  if id then
    statefulElements[id] = nil
  end
end

-- ====================
-- Frame Flush (Immediate Mode Dirty State Persistence)
-- ====================

--- Flush dirty state to persistent store at end of frame.
--- Called automatically at frame end in immediate mode.
--- Behaviors call setStateValue during update without knowing the mode.
---
--- In retained mode, this is a no-op (state is written directly to elements).
function StateManager.flushFrame()
  if not _immediateMode then
    return
  end

  -- All dirty writes were already applied to stateStore during setStateValue
  -- This method exists for future extensions (e.g., batching, analytics)
  -- Reset dirty tracking for next frame
  dirtyState = {}
end

-- ====================
-- Mode Configuration
-- ====================

--- Configure immediate mode state.
--- Called by Context when immediate mode is enabled/disabled.
---
---@param enabled boolean Whether immediate mode is active
function StateManager.setImmediateMode(enabled)
  _immediateMode = enabled
end

--- Check if immediate mode is active.
---@return boolean
function StateManager.isImmediateMode()
  return _immediateMode
end

--- Whether at-construction layout / eager initialization should run now.
--- Returns true in retained mode (layout eagerly), false in immediate mode
--- (layout is deferred to `FlexLove.endFrame` / FlexLove so it runs once all
--- elements for the frame have been created). This replaces the scattered
--- `if not _immediateMode then layoutChildren()` mode checks with a single
--- mode-aware query (behavior-mode-unification task 11).
---@return boolean
function StateManager.shouldLayout()
  return not _immediateMode
end

-- ====================
-- Cleanup & Maintenance
-- ====================

--- Clean up stale states (not accessed recently)
---@return number count Number of states cleaned up
function StateManager.cleanup()
  local cleanedCount = 0
  local retentionFrames = config.stateRetentionFrames

  for id, meta in pairs(stateMetadata) do
    local framesSinceAccess = frameNumber - meta.lastFrame

    if framesSinceAccess > retentionFrames then
      stateStore[id] = nil
      stateMetadata[id] = nil
      cleanedCount = cleanedCount + 1
    end
  end

  -- Clean up empty states (sparse storage optimization)
  for id, state in pairs(stateStore) do
    if next(state) == nil then
      stateStore[id] = nil
      stateMetadata[id] = nil
      cleanedCount = cleanedCount + 1
    end
  end

  return cleanedCount
end

--- Force cleanup if state count exceeds maximum
---@return number count Number of states cleaned up
function StateManager.forceCleanupIfNeeded()
  local stateCount = StateManager.getStateCount()

  if stateCount > config.maxStateEntries then
    -- Clean up states not accessed in last 10 frames (aggressive)
    local cleanedCount = 0

    for id, meta in pairs(stateMetadata) do
      local framesSinceAccess = frameNumber - meta.lastFrame

      if framesSinceAccess > 10 then
        stateStore[id] = nil
        stateMetadata[id] = nil
        cleanedCount = cleanedCount + 1
      end
    end

    return cleanedCount
  end

  return 0
end

--- Get total number of stored states
---@return number
function StateManager.getStateCount()
  local count = 0
  for _ in pairs(stateStore) do
    count = count + 1
  end
  return count
end

--- Clear all states
function StateManager.clearAllStates()
  stateStore = {}
  stateMetadata = {}
end

--- Configure state management
---@param newConfig {stateRetentionFrames?: number, maxStateEntries?: number}
function StateManager.configure(newConfig)
  if newConfig.stateRetentionFrames then
    config.stateRetentionFrames = newConfig.stateRetentionFrames
  end
  if newConfig.maxStateEntries then
    config.maxStateEntries = newConfig.maxStateEntries
  end
end

--- Get state statistics for debugging
---@return table stats State usage statistics
function StateManager.getStats()
  local stateCount = StateManager.getStateCount()
  local oldest = nil
  local newest = nil

  for _, meta in pairs(stateMetadata) do
    if not oldest or meta.createdFrame < oldest then
      oldest = meta.createdFrame
    end
    if not newest or meta.createdFrame > newest then
      newest = meta.createdFrame
    end
  end

  -- Count callSiteCounters
  local callSiteCount = 0
  for _ in pairs(callSiteCounters) do
    callSiteCount = callSiteCount + 1
  end

  -- Warn if callSiteCounters is unexpectedly large
  if callSiteCount > 1000 then
    if ErrorHandler then
      ErrorHandler.warn("StateManager", "STATE_001", {
        count = callSiteCount,
        expected = "near 0",
        frameNumber = frameNumber,
      })
    end
  end

  return {
    stateCount = stateCount,
    frameNumber = frameNumber,
    oldestState = oldest,
    newestState = newest,
    callSiteCounterCount = callSiteCount,
  }
end

--- Get internal state (for debugging/profiling only)
---@return table internal {stateStore, stateMetadata, callSiteCounters}
function StateManager._getInternalState()
  return {
    stateStore = stateStore,
    stateMetadata = stateMetadata,
    callSiteCounters = callSiteCounters,
  }
end

--- Reset the entire state system (for testing)
function StateManager.reset()
  stateStore = {}
  stateMetadata = {}
  frameNumber = 0
  callSiteCounters = {}
  statefulElements = {}
  dirtyState = {}
  _immediateMode = false
end

-- ====================
-- Convenience Functions (for backward compatibility)
-- ====================

--- Check if an element is currently hovered
---@param id string Element ID
---@return boolean
function StateManager.isHovered(id)
  local state = StateManager.getState(id)
  return state.hover or false
end

--- Check if an element is currently pressed
---@param id string Element ID
---@return boolean
function StateManager.isPressed(id)
  local state = StateManager.getState(id)
  return state.pressed or false
end

--- Check if an element is currently focused
---@param id string Element ID
---@return boolean
function StateManager.isFocused(id)
  local state = StateManager.getState(id)
  return state.focused or false
end

--- Check if an element is disabled
---@param id string Element ID
---@return boolean
function StateManager.isDisabled(id)
  local state = StateManager.getState(id)
  return state.disabled or false
end

--- Check if an element is active (e.g., input focused)
---@param id string Element ID
---@return boolean
function StateManager.isActive(id)
  local state = StateManager.getState(id)
  return state.active or false
end

return StateManager
