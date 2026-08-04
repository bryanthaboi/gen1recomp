local packageName = ... or "FlexLove"
local modulePath = packageName:match("(.-)[^%.]+$") -- Get the module path prefix (e.g., "libs." or "")
-- If modulePath is empty (e.g., require("FlexLove")), use the package name
if modulePath == "" then
  modulePath = packageName .. "."
end

local function req(name)
  return require(modulePath .. "modules." .. name)
end

---@type ErrorHandler
local ErrorHandler = req("ErrorHandler")
local ModuleLoader = req("ModuleLoader")
ModuleLoader.init({ ErrorHandler = ErrorHandler })

local function safeReq(name, isOptional)
  local module = ModuleLoader.safeRequire(modulePath .. "modules." .. name, isOptional)
  if isOptional and module and module._isStub then
    return nil
  end
  return module
end

-- Required core modules
local utils = req("utils")
local Calc = req("Calc")
local Units = req("Units")
local Context = req("Context")
---@type StateManager
local StateManager = req("StateManager")
local RoundedRect = req("RoundedRect")
local Grid = req("Grid")
local InputEvent = req("InputEvent")
local TextEditor = req("TextEditor")
---@type LayoutEngine
local LayoutEngine = req("LayoutEngine")
local Renderer = req("Renderer")
---@type EventHandler
local EventHandler = req("EventHandler")
local ScrollManager = req("ScrollManager")
---@type ZIndex
local ZIndex = req("ZIndex")
---@type Element
local Element = req("Element")
---@type Color
local Color = req("Color")

-- Lua 5.2+ compatibility for unpack (bare global `unpack` is nil under
-- Lua 5.4, which the stock test runner uses). mirrors the shim in
-- modules/Blur.lua:2 and modules/Element.lua:162.
local unpack = table.unpack or unpack

---@type Select
local Select = req("Select")

-- Behavior: mouse/touch event handling, pressed-state, hit-testing (task 02).
-- Auto-attaches to interactive elements via shouldAttach(props).
local Clickable = req("behaviors.Clickable")

-- Behavior: Renderer ownership + theme-state rendering (task 07). Owns the
-- single Renderer:draw call and creates the per-element Renderer. Attaches to
-- every renderable element (see behaviors/Themed.lua for the always-attach
-- rationale). Must precede Clickable in the registry so its core Renderer:draw
-- runs before Clickable's pressed-state overlay (onDraw layering).
local Themed = req("behaviors.Themed")

-- Behavior: image loading + image rendering config (task 07). Enriches the
-- shared element._renderer with image config, runs the deferred image-load
-- pipeline, and persists _loadedImage across immediate-mode frames. Attaches to
-- elements with imagePath/image.
local Imageable = req("behaviors.Imageable")

-- Behavior: animation update, interpolation, chaining, transition wiring
-- (task 06). Auto-attaches to elements that pre-declare `transitions`, and
-- late-attaches on demand via Animated.ensureAttached when an animation is
-- created post-construction (animateTo/fadeIn/direct assignment/transition fire).
local Animated = req("behaviors.Animated")

-- Behavior: Select state-machine lifecycle (task 05). Owns select subsystem
-- init, managed-frame layout sync each frame, and select save/restore. Auto-
-- attaches to elements with selectParent or selectOption props.
local Selectable = req("behaviors.Selectable")

-- Behavior: TextEditor subsystem ownership — text editing, cursor management,
-- text selection, text-related input handling, and text-editor save/restore
-- (task 04). Auto-attaches to editable elements and text-bearing elements via
-- shouldAttach(props); onAttach allocates the TextEditor (editable only).
-- Element retains 1-line forwarders routed through this module for the 27
-- text-editor delegate methods, eliminating the `if self._textEditor` guards.
local TextEditable = req("behaviors.TextEditable")

-- Behavior: ScrollManager lifecycle (task 03, landed via the task 08 capstone).
-- Owns ScrollManager creation + immediate-mode scrollbar interaction-state
-- restore (formerly Element:_initScrollManager). Auto-attaches to elements that
-- declare overflow / overflowX / overflowY. Placed late in the registry: its
-- onAttach creates the ScrollManager, which no other behavior's onAttach
-- depends on. The ScrollManager update / scrollbar draw / state save-restore
-- stay inline in Element:update / Element:draw / Element:saveState as
-- unconditional 1-line delegates (task 09 folds them into hooks).
local Scrollable = req("behaviors.Scrollable")

-- Behavior: generic public-property persistence across the immediate-mode
-- recreation cycle (task 12). Owns the `_props` snapshot (event-driven mutations
-- to `text` / `display` / `opacity` / ... that must survive per-frame Element
-- recreation). Auto-attaches to every element; placed LAST in the registry so
-- its restoreState overrides subsystem-hydrated state, preserving the legacy
-- restore ordering (behaviors first, `_props` tail). With this behavior in
-- place, Element:saveState / Element:restoreState collapse to a pure
-- behavior-dispatch loop and Element owns zero property-extraction logic.
local Persistable = req("behaviors.Persistable")

-- Optional modules (can be excluded in minimal builds)
local Blur = safeReq("Blur", true)
---@type Performance
local Performance = safeReq("Performance", true)
---@type KeyboardNavigation
local KeyboardNavigation = safeReq("KeyboardNavigation", true)
---@type FocusIndicator
local FocusIndicator = safeReq("FocusIndicator", true)
local ImageRenderer = safeReq("ImageRenderer", true)
local ImageScaler = safeReq("ImageScaler", true)
local NinePatch = safeReq("NinePatch", true)
local ImageCache = safeReq("ImageCache", true)
local GestureRecognizer = safeReq("GestureRecognizer", true)
---@type PropertySchema
local PropertySchema = req("PropertySchema")
---@type Animation
local Animation = safeReq("Animation", true)
---@type Theme
local Theme = safeReq("Theme", true)

-- Handle Animation.Transform safely
local Transform = Animation and Animation.Transform or nil

local enums = utils.enums

local flexlove = Context
flexlove._VERSION = "0.15.0"
flexlove._DESCRIPTION = "UI Library for LÖVE Framework based on flexbox"
flexlove._URL = "https://github.com/mikefreno/FlexLove"
flexlove._LICENSE = [[
  MIT License

  Copyright (c) 2025 Mike Freno

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
]]

-- GC (Garbage Collection) configuration
---@type GCConfig
flexlove._gcConfig = {
  strategy = "auto", -- "auto", "periodic", "manual", "disabled"
  memoryThreshold = 100, -- MB before forcing GC
  interval = 60, -- Frames between GC steps (for periodic mode)
  stepSize = 200, -- Work units per GC step (higher = more aggressive)
}
---@type GCState
flexlove._gcState = {
  framesSinceLastGC = 0,
  lastMemory = 0,
  gcCount = 0,
}

-- Deferred callback queue for operations that cannot run while Canvas is active
---@type function[]
flexlove._deferredCallbacks = {}

-- Track accumulated delta time for immediate mode updates
flexlove._accumulatedDt = 0

-- Touch ownership tracking: maps touch ID (string) to the element that owns it
---@type table<string, Element>
flexlove._touchOwners = {}

-- Touch-drag scroll tracking: survives immediate-mode element recreation.
-- Maps touch ID -> { id, lastX, lastY }. Scroll position is persisted into
-- StateManager on every move (same contract as wheelmoved).
---@type table<string, {id: string, lastX: number, lastY: number}>
flexlove._touchScroll = {}

---@type table<number, boolean>
flexlove._mouseButtonStates = {}

-- Shared GestureRecognizer instance for touch routing (initialized in init())
---@type GestureRecognizer|nil
flexlove._gestureRecognizer = nil

--- Check if FlexLove initialization is complete and ready to create elements
--- Use this before creating elements to avoid automatic queueing
---@return boolean ready True if FlexLove is initialized and ready to use
function flexlove.isReady()
  return flexlove._initState == "ready"
end

--- Set up FlexLove for your application's specific needs - configure responsive scaling, theming, rendering mode, and debugging tools
--- Use this to establish a consistent UI foundation that adapts to different screen sizes and provides performance insights
--- After initialization, any queued element creation calls will be automatically processed
---@param config FlexLoveConfig?
function flexlove.init(config)
  flexlove._initState = "initializing"
  config = config or {}

  flexlove._ErrorHandler = ErrorHandler.init({
    includeStackTrace = config.includeStackTrace,
    logLevel = config.reportingLogLevel,
    logTarget = config.errorLogTarget,
    logFile = config.errorLogFile,
    maxLogSize = config.errorLogMaxSize,
    maxLogFiles = config.maxErrorLogFiles,
    enableRotation = config.errorLogRotateEnabled,
  })

  -- Initialize Performance if available
  if Performance then
    flexlove._Performance = Performance.init({
      -- ~= false (not `or true`): `performanceMonitoring = false` must
      -- actually disable the per-frame timers + memory sampling.
      enabled = config.performanceMonitoring ~= false,
      hudEnabled = false, -- Start with HUD disabled
      hudToggleKey = config.performanceHudKey or "f3",
      hudPosition = config.performanceHudPosition or { x = 10, y = 10 },
      warningThresholdMs = config.performanceWarningThreshold or 13.0,
      criticalThresholdMs = config.performanceCriticalThreshold or 16.67,
      logToConsole = config.performanceLogToConsole or false,
      logWarnings = config.performanceWarnings or false,
      warningsEnabled = config.performanceWarnings or false,
      memoryProfiling = config.memoryProfiling or config.immediateMode and true or false,
    }, { ErrorHandler = flexlove._ErrorHandler })

    if config.immediateMode then
      flexlove._Performance:registerTableForMonitoring(
        "StateManager.stateStore",
        StateManager._getInternalState().stateStore
      )
      flexlove._Performance:registerTableForMonitoring(
        "StateManager.stateMetadata",
        StateManager._getInternalState().stateMetadata
      )
    end
  else
    flexlove._Performance = Performance
  end

  -- Initialize optional modules if available
  if ModuleLoader.isModuleLoaded(modulePath .. "modules.ImageRenderer") then
    ImageRenderer.init({ ErrorHandler = flexlove._ErrorHandler, utils = utils })
  end

  if ModuleLoader.isModuleLoaded(modulePath .. "modules.ImageScaler") then
    ImageScaler.init({ ErrorHandler = flexlove._ErrorHandler })
  end

  if ModuleLoader.isModuleLoaded(modulePath .. "modules.NinePatch") then
    NinePatch.init({ ErrorHandler = flexlove._ErrorHandler })
  end

  -- Initialize Blur module with immediate mode optimization config
  if ModuleLoader.isModuleLoaded(modulePath .. "modules.Blur") then
    local blurOptimizations = config.immediateModeBlurOptimizations
    if blurOptimizations == nil then
      blurOptimizations = true -- Default to enabled
    end
    Blur.init({
      ErrorHandler = flexlove._ErrorHandler,
      immediateModeOptimizations = blurOptimizations and config.immediateMode or false,
    })
  end

  -- Initialize required modules
  StateManager.init({ ErrorHandler = flexlove._ErrorHandler })
  Calc.init({ ErrorHandler = flexlove._ErrorHandler })
  Units.init({ Context = Context, ErrorHandler = flexlove._ErrorHandler, Calc = Calc })
  Color.init({ ErrorHandler = flexlove._ErrorHandler })
  utils.init({ ErrorHandler = flexlove._ErrorHandler })

  -- Initialize optional ImageCache module
  if ModuleLoader.isModuleLoaded(modulePath .. "modules.ImageCache") then
    ImageCache.init({ ErrorHandler = flexlove._ErrorHandler })
  end

  -- Initialize optional Animation module
  if ModuleLoader.isModuleLoaded(modulePath .. "modules.Animation") then
    Animation.init({ ErrorHandler = flexlove._ErrorHandler, Color = Color })
  end

  -- Initialize optional Theme module
  if ModuleLoader.isModuleLoaded(modulePath .. "modules.Theme") then
    Theme.init({ ErrorHandler = flexlove._ErrorHandler, Color = Color, utils = utils })
  end

  LayoutEngine.init({ ErrorHandler = flexlove._ErrorHandler, Performance = flexlove._Performance, utils = utils })
  EventHandler.init({
    ErrorHandler = flexlove._ErrorHandler,
    Performance = flexlove._Performance,
    InputEvent = InputEvent,
    utils = utils,
    Context = Context,
  })

  -- Initialize shared GestureRecognizer for touch routing
  if GestureRecognizer then
    flexlove._gestureRecognizer = GestureRecognizer.new({}, { InputEvent = InputEvent, utils = utils })
  end

  -- Initialize KeyboardNavigation and FocusIndicator if enabled
  local keyboardConfig = config.keyboardNavigation
  if
    KeyboardNavigation
    and (keyboardConfig == true or (type(keyboardConfig) == "table" and keyboardConfig.enabled ~= false))
  then
    KeyboardNavigation.init({
      Context = Context,
      Element = Element,
      ErrorHandler = flexlove._ErrorHandler,
      utils = utils,
      InputEvent = InputEvent,
    })

    if FocusIndicator then
      FocusIndicator.init({ Context = Context, Color = Color })
      KeyboardNavigation.FocusIndicator = FocusIndicator
      -- Also set FocusIndicator reference in EventHandler for clearing on mouse click
      EventHandler._FocusIndicator = FocusIndicator
      -- Note: FocusIndicator is only updated from keyboard navigation (_focusElement)
      -- Mouse clicks and activation clear the indicator
    end

    -- Apply configuration if provided
    flexlove._applyKeyboardNavConfig(keyboardConfig)
  end

  flexlove._defaultDependencies = {
    Context = Context,
    Theme = Theme,
    Color = Color,
    Calc = Calc,
    Units = Units,
    Blur = Blur,
    ImageRenderer = ImageRenderer,
    ImageScaler = ImageScaler,
    NinePatch = NinePatch,
    RoundedRect = RoundedRect,
    ImageCache = ImageCache,
    utils = utils,
    Grid = Grid,
    InputEvent = InputEvent,
    GestureRecognizer = GestureRecognizer,
    StateManager = StateManager,
    TextEditor = TextEditor,
    LayoutEngine = LayoutEngine,
    Renderer = Renderer,
    EventHandler = EventHandler,
    ScrollManager = ScrollManager,
    ErrorHandler = flexlove._ErrorHandler,
    Performance = flexlove._Performance,
    Transform = Transform,
    Animation = Animation,
    ZIndex = ZIndex,
    Select = Select,
    PropertySchema = PropertySchema,
    -- Behavior registry (behavior-mode-unification task 09). Two ordering
    -- invariants:
    --   * Update: Animated (geometry) → Scrollable (scroll interaction) →
    --     Clickable (hit-testing) — animated geometry must be current for
    --     hit-testing, and scrollbar press state must be set before Clickable's
    --     EventHandler processes mouse events.
    --   * Draw: Themed (core Renderer:draw) runs before Clickable (pressed-state
    --     overlay); Scrollable (drawLayer="overlay") is dispatched AFTER children
    --     for scrollbar-on-top. Imageable/Animated/Selectable/TextEditable onDraw
    --     are no-ops, so their position is unconstrained for layering.
    -- 7 entries. (task 09 reordered Animated+Scrollable ahead of Clickable.)
    clickableBehaviors = { Themed, Clickable, Imageable },
    -- Persistable is the registry tail (task 12): its restoreState applies the
    -- `_props` override AFTER every subsystem behavior has hydrated, preserving
    -- the legacy restore ordering (behaviors first, `_props` last).
    behaviors = { Themed, Animated, Scrollable, Clickable, Imageable, Selectable, TextEditable, Persistable },
    TextEditable = TextEditable,
  }

  -- Initialize Element module with dependencies
  Element.init(flexlove._defaultDependencies)

  if config.baseScale then
    flexlove.baseScale = {
      width = config.baseScale.width or 1920,
      height = config.baseScale.height or 1080,
    }

    local currentWidth, currentHeight = Units.getViewport()
    flexlove.scaleFactors.x = currentWidth / flexlove.baseScale.width
    flexlove.scaleFactors.y = currentHeight / flexlove.baseScale.height
  end

  if config.theme and ModuleLoader.isModuleLoaded(modulePath .. "modules.Theme") then
    local success, err = pcall(function()
      if type(config.theme) == "string" then
        Theme.load(config.theme)
        Theme.setActive(config.theme)
        flexlove.defaultTheme = config.theme
      elseif type(config.theme) == "table" then
        local theme = Theme.new(config.theme)
        Theme.setActive(theme)
        flexlove.defaultTheme = theme.name
      end
    end)

    if not success then
      flexlove._ErrorHandler:warn("FlexLove", "THM_005", {
        error = tostring(err),
      })
    end
  end

  local immediateMode = config.immediateMode or false
  flexlove.setMode(immediateMode and "immediate" or "retained")

  flexlove._autoFrameManagement = config.autoFrameManagement or false

  -- Configure GC strategy
  if config.gcStrategy then
    flexlove._gcConfig.strategy = config.gcStrategy
  end
  if config.gcMemoryThreshold then
    flexlove._gcConfig.memoryThreshold = config.gcMemoryThreshold
  end
  if config.gcInterval then
    flexlove._gcConfig.interval = config.gcInterval
  end
  if config.gcStepSize then
    flexlove._gcConfig.stepSize = config.gcStepSize
  end

  if config.stateRetentionFrames or config.maxStateEntries then
    StateManager.configure({
      stateRetentionFrames = config.stateRetentionFrames,
      maxStateEntries = config.maxStateEntries,
    })
  end
  flexlove.initialized = true
  flexlove._initState = "ready"

  -- Configure debug draw overlay
  flexlove._debugDraw = config.debugDraw or false
  flexlove._debugDrawKey = config.debugDrawKey or nil

  -- Process all queued element creations
  local queue = flexlove._initQueue
  flexlove._initQueue = {} -- Clear queue before processing to prevent re-entry issues

  for _, item in ipairs(queue) do
    local element = Element.new(item.props)
    if item.callback and type(item.callback) == "function" then
      local success, err = pcall(item.callback, element)
      if not success then
        flexlove._ErrorHandler:warn(
          "FlexLove",
          string.format("Failed to execute queued element callback: %s", tostring(err))
        )
      end
    end
  end
end

--- Enable keyboard navigation after initialization (for deferred or conditional setup)
--- Useful when you need to conditionally enable keyboard navigation based on runtime conditions
--- Automatically initializes KeyboardNavigation and FocusIndicator modules if not already initialized
---@param config KeyboardNavigationConfig? Optional configuration table
--- @usage
--- -- Enable with defaults
--- FlexLove.enableKeyboardNavigation()
---
--- -- Enable with custom configuration
--- FlexLove.enableKeyboardNavigation({
---   directionalNavigation = true,
---   wrapAround = false,
---   focusIndicator = {
---     enabled = true,
---     color = {1, 0.8, 0, 0.8},
---     lineWidth = 3,
---   },
--- })
--- Enable debug mode for keyboard navigation
--- Use this to troubleshoot keyboard navigation issues
---@param enabled boolean
function flexlove.setKeyboardNavigationDebug(enabled)
  if KeyboardNavigation and KeyboardNavigation.config then
    KeyboardNavigation.config.debugMode = enabled
    print(string.format("[FlexLove] Keyboard navigation debug mode: %s", tostring(enabled)))
  end
end

--- Apply keyboard navigation configuration (internal helper)
---@param config table
function flexlove._applyKeyboardNavConfig(config)
  if type(config) ~= "table" then
    return
  end

  if config.enabled ~= nil then
    KeyboardNavigation.config.enabled = config.enabled
  end
  if config.directionalNavigation ~= nil then
    KeyboardNavigation.config.directionalNavigation = config.directionalNavigation
  end
  if config.wrapAround ~= nil then
    KeyboardNavigation.config.wrapAround = config.wrapAround
  end
  if config.dropFocusOnSelection ~= nil then
    KeyboardNavigation.config.dropFocusOnSelection = config.dropFocusOnSelection
  end

  if config.focusIndicator and FocusIndicator then
    local fiConfig = config.focusIndicator
    if fiConfig.enabled ~= nil then
      FocusIndicator.config.enabled = fiConfig.enabled
    end
    if fiConfig.draw ~= nil then
      FocusIndicator.config.draw = fiConfig.draw
    end
    if fiConfig.color then
      FocusIndicator.setColor(
        fiConfig.color[1] or 0.2,
        fiConfig.color[2] or 0.6,
        fiConfig.color[3] or 1.0,
        fiConfig.color[4] or 0.8
      )
    end
    if fiConfig.lineWidth ~= nil then
      FocusIndicator.config.lineWidth = fiConfig.lineWidth
    end
    if fiConfig.pulseEnabled ~= nil then
      FocusIndicator.config.pulseEnabled = fiConfig.pulseEnabled
    end
  end
end

--- Enable keyboard navigation after initialization (for deferred or conditional setup)
--- Useful when you need to conditionally enable keyboard navigation based on runtime conditions
--- Automatically initializes KeyboardNavigation and FocusIndicator modules if not already initialized
---@usage
--- -- Enable with defaults
--- FlexLove.enableKeyboardNavigation()
---
--- -- Enable with custom configuration
--- FlexLove.enableKeyboardNavigation({
---   directionalNavigation = true,
---   wrapAround = false,
---   dropFocusOnSelection = false,
---   focusIndicator = {
---     enabled = true,
---     color = {1, 0.8, 0, 0.8},
---     lineWidth = 3,
---     draw = function(element, bounds, style) end,
---   },
--- })
---@param config KeyboardNavigationConfig
function flexlove.enableKeyboardNavigation(config)
  if not KeyboardNavigation then
    return
  end
  config = config or {}

  -- Check if already initialized
  if KeyboardNavigation.config and KeyboardNavigation._deps then
    -- Already initialized, just apply config if provided
    flexlove._applyKeyboardNavConfig(config)
    return
  end

  -- Initialize KeyboardNavigation
  KeyboardNavigation.init({
    Context = Context,
    Element = Element,
    ErrorHandler = flexlove._ErrorHandler,
    utils = utils,
    InputEvent = InputEvent,
  })

  -- Initialize FocusIndicator if available
  if FocusIndicator then
    FocusIndicator.init({ Context = Context, Color = Color })
    KeyboardNavigation.FocusIndicator = FocusIndicator
    -- Also set FocusIndicator reference in EventHandler for clearing on mouse click
    EventHandler._FocusIndicator = FocusIndicator
    -- Note: FocusIndicator is only updated from keyboard navigation (_focusElement)
    -- Mouse clicks and activation clear the indicator
  end

  flexlove._applyKeyboardNavConfig(config)
end

--- Safely schedule operations that modify LÖVE's rendering state (like window mode changes) to execute after all canvas operations complete
--- Prevents crashes from attempting canvas-incompatible operations during rendering
---@param callback function The callback to execute
function flexlove.deferCallback(callback)
  if type(callback) ~= "function" then
    flexlove._ErrorHandler:warn("FlexLove", "CORE_001")
    return
  end
  table.insert(flexlove._deferredCallbacks, callback)
end

--- Execute deferred operations at the safest point in the render cycle - after all canvas operations are complete
--- Call this at the end of love.draw() to enable window resizing and other state-modifying operations without crashes
--- @usage
--- function love.draw()
---   love.graphics.setCanvas(myCanvas)
---   FlexLove.draw()
---   love.graphics.setCanvas() -- Release ALL canvases
---   FlexLove.executeDeferredCallbacks() -- Now safe to execute
--- end
function flexlove.executeDeferredCallbacks()
  if #flexlove._deferredCallbacks == 0 then
    return
  end

  -- Copy callbacks and clear queue before execution
  -- This prevents infinite loops if callbacks defer more callbacks
  local callbacks = flexlove._deferredCallbacks
  flexlove._deferredCallbacks = {}

  for _, callback in ipairs(callbacks) do
    local success, err = xpcall(callback, debug.traceback)
    if not success then
      flexlove._ErrorHandler:warn("FlexLove", "CORE_002", {
        error = tostring(err),
      })
    end
  end
end

--- Recalculate all UI layouts when the window size changes - ensures your interface adapts seamlessly to new dimensions
--- Hook this to love.resize() to maintain proper scaling and positioning across window size changes
function flexlove.resize()
  local newWidth, newHeight = love.window.getMode()

  if flexlove.baseScale then
    flexlove.scaleFactors.x = newWidth / flexlove.baseScale.width
    flexlove.scaleFactors.y = newHeight / flexlove.baseScale.height
  end

  if ModuleLoader.isModuleLoaded(modulePath .. "modules.Blur") then
    Blur.clearCache()
  end

  -- Release old canvases explicitly
  if flexlove._gameCanvas then
    flexlove._gameCanvas:release()
  end
  if flexlove._backdropCanvas then
    flexlove._backdropCanvas:release()
  end

  flexlove._gameCanvas = nil
  flexlove._backdropCanvas = nil
  flexlove._canvasDimensions = { width = 0, height = 0 }

  for _, win in ipairs(flexlove.topElements) do
    win:resize(newWidth, newHeight)
  end
end

--- Switch between immediate mode (React-like, recreates UI each frame) and retained mode (persistent elements) to match your architectural needs
--- Use immediate for simpler state management and declarative UIs, retained for performance-critical applications with complex state
---@param mode "immediate"|"retained"
function flexlove.setMode(mode)
  if mode == "immediate" then
    flexlove._immediateMode = true
    flexlove._immediateModeState = StateManager
    flexlove._frameStarted = false
    flexlove._autoBeganFrame = false
    -- Notify StateManager of mode change
    StateManager.setImmediateMode(true)
  elseif mode == "retained" then
    flexlove._immediateMode = false
    flexlove._immediateModeState = nil
    flexlove._frameStarted = false
    flexlove._autoBeganFrame = false
    flexlove._currentFrameElements = {}
    flexlove._frameNumber = 0
    -- Notify StateManager of mode change
    StateManager.setImmediateMode(false)
  else
    error("[FlexLove] Invalid mode: " .. tostring(mode) .. ". Expected 'immediate' or 'retained'")
  end
end

--- Check which rendering mode is active to conditionally handle state management logic
--- Useful for libraries and reusable components that need to adapt to different rendering strategies
---@return "immediate"|"retained"
function flexlove.getMode()
  return flexlove._immediateMode and "immediate" or "retained"
end

--- Manually start a new frame in immediate mode for precise control over the UI lifecycle
--- Only needed when you want explicit frame boundaries; otherwise FlexLove auto-manages frames
function flexlove.beginFrame()
  if not flexlove._immediateMode then
    return
  end

  -- Reset accumulated delta time for new frame
  flexlove._accumulatedDt = 0

  -- Start performance frame timing
  if flexlove._Performance then
    flexlove._Performance:startFrame()
  end

  -- Cleanup elements from PREVIOUS frame (after they've been drawn)
  -- This breaks circular references and allows GC to collect memory
  if flexlove._currentFrameElements then
    local function cleanupChildren(elem)
      for _, child in ipairs(elem.children) do
        cleanupChildren(child)
      end
      elem:_cleanup()
    end

    for _, element in ipairs(flexlove._currentFrameElements) do
      if not element.parent then
        cleanupChildren(element)
      end
    end
  end

  flexlove._frameNumber = flexlove._frameNumber + 1
  StateManager.incrementFrame()
  flexlove._currentFrameElements = {}
  flexlove._frameStarted = true
  flexlove.topElements = {}

  Context.clearFrameElements()
end

--- Finalize the frame in immediate mode, triggering layout calculations and state persistence
--- Only needed when manually controlling frames with beginFrame(); otherwise handled automatically
function flexlove.endFrame()
  if not flexlove._immediateMode then
    return
  end

  Context.sortElementsByZIndex()

  -- Layout all top-level elements now that all children have been added
  for _, element in ipairs(flexlove._currentFrameElements) do
    if not element.parent then
      element:layoutChildren()
    end
  end

  flexlove._handleSelectPointerDismissal()

  -- Update all top-level elements created this frame
  for _, element in ipairs(flexlove._currentFrameElements) do
    if not element.parent then
      element:update(flexlove._accumulatedDt)
    end
  end

  -- Save state for all elements created this frame
  for _, element in ipairs(flexlove._currentFrameElements) do
    if element.id and element.id ~= "" then
      local stateUpdate = element:saveState()
      local stateChanged = StateManager.updateStateIfChanged(element.id, stateUpdate)
      if stateChanged and (element.backdropBlur or element.contentBlur) and Blur then
        Blur.clearElementCache(element.id)
      end
    end
  end

  StateManager.cleanup()
  StateManager.forceCleanupIfNeeded()
  -- Flush dirty state from this frame (no-op in retained mode)
  StateManager.flushFrame()
  flexlove._frameStarted = false

  -- End performance frame timing
  if flexlove._Performance then
    flexlove._Performance:endFrame()
    flexlove._Performance:resetFrameCounters()
  end
end

---@type love.Canvas?
flexlove._gameCanvas = nil
---@type love.Canvas?
flexlove._backdropCanvas = nil
---@type {width: number, height: number}
flexlove._canvasDimensions = { width = 0, height = 0 }

--- Recursively draw debug boundaries for an element and all its children
--- Draws regardless of visibility/opacity to reveal hidden or transparent elements
---@param element Element
local function drawDebugElement(element)
  local color = element._debugColor
  if color then
    local bw = element._borderBoxWidth or (element.width + element.padding.left + element.padding.right)
    local bh = element._borderBoxHeight or (element.height + element.padding.top + element.padding.bottom)

    -- Fill with 0.5 opacity
    love.graphics.setColor(color[1], color[2], color[3], 0.5)
    love.graphics.rectangle("fill", element.x, element.y, bw, bh)

    -- Border with full opacity, 1px line
    love.graphics.setColor(color[1], color[2], color[3], 1)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", element.x, element.y, bw, bh)
  end

  for _, child in ipairs(element.children) do
    drawDebugElement(child)
  end
end

--- Render the debug draw overlay for all elements in the tree
--- Traverses every element regardless of visibility or opacity
function flexlove._renderDebugOverlay()
  -- Save current graphics state
  local prevR, prevG, prevB, prevA = love.graphics.getColor()
  local prevLineWidth = love.graphics.getLineWidth()

  -- Clear any active scissor so debug draws are always visible
  love.graphics.setScissor()

  for _, win in ipairs(flexlove.topElements) do
    drawDebugElement(win)
  end

  -- Restore graphics state
  love.graphics.setColor(prevR, prevG, prevB, prevA)
  love.graphics.setLineWidth(prevLineWidth)
end

--- Render all UI elements with optional backdrop blur support for glassmorphic effects
--- Place your game scene in gameDrawFunc to enable backdrop blur on UI elements; use postDrawFunc for overlays
---@param gameDrawFunc function|nil pass component draws that should be affected by a backdrop blur
---@param postDrawFunc function|nil pass component draws that should NOT be affected by a backdrop blur
function flexlove.draw(gameDrawFunc, postDrawFunc)
  if flexlove._immediateMode and flexlove._autoBeganFrame then
    flexlove.endFrame()
    flexlove._autoBeganFrame = false
  end

  local outerCanvas = love.graphics.getCanvas()
  local gameCanvas = nil

  if type(gameDrawFunc) == "function" then
    local width, height = love.graphics.getDimensions()

    if
      not flexlove._gameCanvas
      or flexlove._canvasDimensions.width ~= width
      or flexlove._canvasDimensions.height ~= height
    then
      -- Release old canvases before creating new ones
      if flexlove._gameCanvas then
        flexlove._gameCanvas:release()
      end
      if flexlove._backdropCanvas then
        flexlove._backdropCanvas:release()
      end

      flexlove._gameCanvas = love.graphics.newCanvas(width, height)
      flexlove._backdropCanvas = love.graphics.newCanvas(width, height)
      flexlove._canvasDimensions.width = width
      flexlove._canvasDimensions.height = height
    end

    gameCanvas = flexlove._gameCanvas

    love.graphics.setCanvas(gameCanvas)
    love.graphics.clear()
    gameDrawFunc()
    love.graphics.setCanvas(outerCanvas)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(gameCanvas, 0, 0)
  end

  table.sort(flexlove.topElements, function(a, b)
    return a.z < b.z
  end)

  local function hasBackdropBlur(element)
    if element.backdropBlur and element.backdropBlur.radius > 0 then
      return true
    end
    for _, child in ipairs(element.children) do
      if hasBackdropBlur(child) then
        return true
      end
    end
    return false
  end

  local needsBackdropCanvas = false
  for _, win in ipairs(flexlove.topElements) do
    if hasBackdropBlur(win) then
      needsBackdropCanvas = true
      break
    end
  end

  if needsBackdropCanvas and gameCanvas then
    local backdropCanvas = flexlove._backdropCanvas
    local prevColor = { love.graphics.getColor() }

    love.graphics.setCanvas(backdropCanvas)
    love.graphics.clear()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(gameCanvas, 0, 0)

    love.graphics.setCanvas(outerCanvas)
    love.graphics.setColor(unpack(prevColor))

    for _, win in ipairs(flexlove.topElements) do
      -- Check if this element tree has backdrop blur
      local needsBackdrop = hasBackdropBlur(win)

      -- Draw element with backdrop blur applied if needed
      if needsBackdrop then
        win:draw(backdropCanvas)
      else
        win:draw(nil)
      end

      -- IMPORTANT: Update backdrop canvas for EVERY element (respecting z-index order)
      -- This ensures that lower z-index elements are visible in the backdrop blur
      -- of higher z-index elements
      love.graphics.setCanvas(backdropCanvas)
      love.graphics.setColor(1, 1, 1, 1)
      win:draw(nil)
      love.graphics.setCanvas(outerCanvas)
    end
  else
    for _, win in ipairs(flexlove.topElements) do
      win:draw(nil)
    end
  end

  if type(postDrawFunc) == "function" then
    postDrawFunc()
  end

  -- Render performance HUD if enabled
  if flexlove._Performance then
    flexlove._Performance:renderHUD()
  end

  -- Render focus indicator if keyboard navigation is enabled
  if KeyboardNavigation and KeyboardNavigation.config and KeyboardNavigation.config.enabled and FocusIndicator then
    FocusIndicator:draw()
  end

  -- Render debug draw overlay if enabled
  if flexlove._debugDraw then
    flexlove._renderDebugOverlay()
  end

  love.graphics.setCanvas(outerCanvas)

  -- NOTE: Deferred callbacks are NOT executed here because the calling code
  -- (e.g., main.lua) might still have a canvas active. Callbacks must be
  -- executed by calling FlexLove.executeDeferredCallbacks() at the very end
  -- of love.draw() after ALL canvases have been released.
end

--- Check if element is an ancestor of target
---@param element Element The potential ancestor element
---@param target Element The target element to check
---@return boolean isAncestor True if element is an ancestor of target
local function isAncestor(element, target)
  local current = target.parent
  while current do
    if current == element then
      return true
    end
    current = current.parent
  end
  return false
end

---@param element Element
---@param results Element[]
local function collectOpenSelects(element, results)
  if element._selectState and element._selectState.open then
    table.insert(results, element)
  end

  for _, child in ipairs(element.children) do
    collectOpenSelects(child, results)
  end
end

function flexlove._handleSelectPointerDismissal()
  local isLeftDown = love.mouse.isDown(1)
  local wasLeftDown = flexlove._mouseButtonStates[1] or false

  if isLeftDown and not wasLeftDown then
    local mx, my = love.mouse.getPosition()
    local target = flexlove.getElementAtPosition(mx, my)
    local openSelects = {}

    for _, element in ipairs(flexlove.topElements) do
      collectOpenSelects(element, openSelects)
    end

    for _, selectParent in ipairs(openSelects) do
      local containsTarget = target and (target == selectParent or isAncestor(selectParent, target))
      if not containsTarget then
        selectParent:closeSelect()
      end
    end
  end

  flexlove._mouseButtonStates[1] = isLeftDown
end

--- Determine which UI element the user is interacting with at a specific screen position
--- Essential for custom input handling, tooltips, or debugging click targets in complex layouts
---@param x number
---@param y number
---@return Element?
function flexlove.getElementAtPosition(x, y)
  local candidates = {}
  local blockingElements = {}

  local function collectHits(element, scrollOffsetX, scrollOffsetY)
    scrollOffsetX = scrollOffsetX or 0
    scrollOffsetY = scrollOffsetY or 0

    -- pointHitsElement is the single canonical bounds + display:none guard.
    if Context.pointHitsElement(element, x, y, scrollOffsetX, scrollOffsetY) then
      -- Skip invisible/transparent elements and their entire subtree
      if element.visibility == "hidden" or element.opacity <= 0 then
        return
      end

      -- Collect interactive elements (those with onEvent handlers)
      if
        (element.onEvent or element.editable or element._selectState or element.selectOption) and not element.disabled
      then
        table.insert(candidates, element)
      end

      -- Collect all visible elements for input blocking
      -- Elements with opacity > 0 block input to elements below them
      if element.opacity > 0 then
        table.insert(blockingElements, element)
      end

      -- Check if this element has scrollable overflow
      local overflowX = element.overflowX or element.overflow
      local overflowY = element.overflowY or element.overflow
      local hasScrollableOverflow = (
        overflowX == "scroll"
        or overflowX == "auto"
        or overflowY == "scroll"
        or overflowY == "auto"
        or overflowX == "hidden"
        or overflowY == "hidden"
      )

      -- Accumulate scroll offset for children if this element has overflow clipping
      local childScrollOffsetX = scrollOffsetX
      local childScrollOffsetY = scrollOffsetY
      if hasScrollableOverflow then
        childScrollOffsetX = childScrollOffsetX + (element._scrollX or 0)
        childScrollOffsetY = childScrollOffsetY + (element._scrollY or 0)
      end

      for _, child in ipairs(element.children) do
        collectHits(child, childScrollOffsetX, childScrollOffsetY)
      end
    end
  end

  for _, element in ipairs(flexlove.topElements) do
    collectHits(element)
  end

  -- Sort both lists by composite z-index (highest first). Uses the same
  -- rootZ * ROOT_WEIGHT + depth * DEPTH_WEIGHT + ownZ key as
  -- Context.sortElementsByZIndex / findInteractiveAtPosition so the hit-test
  -- topmost matches the visual draw order across overlapping windows.
  -- Skip the precompute + sort when there is 0 or 1 element (the common case
  -- for getElementAtPosition which is called on every love.mousemoved event).
  if #candidates > 1 then
    local candidateZ = {}
    for i = 1, #candidates do
      candidateZ[candidates[i]] = Context.getEffectiveZIndex(candidates[i])
    end
    table.sort(candidates, function(a, b)
      return candidateZ[a] > candidateZ[b]
    end)
  end

  if #blockingElements > 1 then
    local blockerZ = {}
    for i = 1, #blockingElements do
      blockerZ[blockingElements[i]] = Context.getEffectiveZIndex(blockingElements[i])
    end
    table.sort(blockingElements, function(a, b)
      return blockerZ[a] > blockerZ[b]
    end)
  end

  -- If we have interactive elements, return the topmost one
  -- But only if there's no blocking element with higher z-index (that isn't an ancestor)
  if #candidates > 0 then
    local topCandidate = candidates[1]

    -- Check if any blocking element would prevent this interaction
    if #blockingElements > 0 then
      local topBlocker = blockingElements[1]
      -- If the top blocker has higher z-index than the top candidate,
      -- and the blocker is NOT an ancestor of the candidate,
      -- return the blocker (even though it has no onEvent, it blocks input)
      if topBlocker.z > topCandidate.z and not isAncestor(topBlocker, topCandidate) then
        return topBlocker
      end
    end

    return topCandidate
  end

  -- No interactive elements, but return topmost blocking element if any
  -- This prevents clicks from passing through non-interactive overlays
  return blockingElements[1]
end

--- Update all UI animations, interactions, and state changes each frame
--- Hook this to love.update() to enable hover effects, animations, text cursors, and scrolling
---@param dt number
function flexlove.update(dt)
  -- Update Performance module with actual delta time for accurate FPS
  if flexlove._Performance then
    flexlove._Performance:updateDeltaTime(dt)
  end

  -- Update keyboard navigation (animations, etc.)
  if KeyboardNavigation then
    KeyboardNavigation:update(dt)
  end

  -- Garbage collection management
  flexlove._manageGC()

  -- Invalidate the per-frame findInteractiveAtPosition cache so Clickable's
  -- per-element occlusion lookup (one per interactive element per frame) is
  -- recomputed fresh for this frame's tree. Within the frame every
  -- Clickable.onUpdate then shares one cached result instead of re-walking
  -- + re-sorting the tree per element (unified-event-routing task 05 fix).
  flexlove.clearInteractiveCache()

  -- Select-pointer dismissal: if the left mouse button was just pressed,
  -- check whether any open Select dropdowns should be closed (click-outside).
  -- This calls getElementAtPosition ONLY on the click frame, not every frame.
  flexlove._handleSelectPointerDismissal()

  -- In immediate mode, accumulate dt and skip updating here - elements will be updated in endFrame after layout
  if flexlove._immediateMode then
    flexlove._accumulatedDt = flexlove._accumulatedDt + dt
  else
    for _, win in ipairs(flexlove.topElements) do
      win:update(dt)
    end
  end

  -- Note: State saving happens in endFrame() after element:update() is called
  -- This ensures all state changes (including cursor blink) are captured once per frame
end

--- Internal GC management function (called from update)
function flexlove._manageGC()
  local strategy = flexlove._gcConfig.strategy

  if strategy == "disabled" then
    return
  end

  local currentMemory = collectgarbage("count") / 1024 -- Convert to MB
  flexlove._gcState.lastMemory = currentMemory
  flexlove._gcState.framesSinceLastGC = flexlove._gcState.framesSinceLastGC + 1

  -- Check memory threshold (applies to all strategies except disabled)
  if currentMemory > flexlove._gcConfig.memoryThreshold then
    -- Force full GC when exceeding threshold
    collectgarbage("collect")
    flexlove._gcState.gcCount = flexlove._gcState.gcCount + 1
    flexlove._gcState.framesSinceLastGC = 0
    return
  end

  -- Strategy-specific GC
  if strategy == "periodic" then
    -- Run incremental GC step every N frames
    if flexlove._gcState.framesSinceLastGC >= flexlove._gcConfig.interval then
      collectgarbage("step", flexlove._gcConfig.stepSize)
      flexlove._gcState.gcCount = flexlove._gcState.gcCount + 1
      flexlove._gcState.framesSinceLastGC = 0
    end
  elseif strategy == "auto" then
    -- Let Lua's automatic GC handle it, but help with incremental steps
    -- Run a small step every frame to keep memory under control
    if flexlove._gcState.framesSinceLastGC >= 5 then
      collectgarbage("step", 50) -- Small steps to avoid frame drops
      flexlove._gcState.framesSinceLastGC = 0
    end
  end
  -- "manual" strategy: no automatic GC, user must call flexlove.collectGarbage()
end

--- Manually trigger garbage collection to prevent frame drops during critical gameplay moments
--- Use this to control when memory cleanup happens rather than letting it occur unpredictably
---@param mode? string "collect" for full GC, "step" for incremental (default: "collect")
---@param stepSize? number Work units for step mode (default: 200)
function flexlove.collectGarbage(mode, stepSize)
  mode = mode or "collect"
  stepSize = stepSize or 200

  if mode == "collect" then
    collectgarbage("collect")
    flexlove._gcState.gcCount = flexlove._gcState.gcCount + 1
    flexlove._gcState.framesSinceLastGC = 0
  elseif mode == "step" then
    collectgarbage("step", stepSize)
  elseif mode == "count" then
    return collectgarbage("count") / 1024 -- Return memory in MB
  end
end

--- Choose how FlexLove manages memory cleanup to balance performance and memory usage for your app's needs
--- Use "manual" for tight control in performance-critical sections, "auto" for hands-off operation
---@param strategy string "auto", "periodic", "manual", or "disabled"
function flexlove.setGCStrategy(strategy)
  if strategy == "auto" or strategy == "periodic" or strategy == "manual" or strategy == "disabled" then
    flexlove._gcConfig.strategy = strategy
  else
    flexlove._ErrorHandler:warn("FlexLove", "CORE_003", {
      strategy = tostring(strategy),
    })
  end
end

--- Monitor memory management behavior to diagnose performance issues and tune GC settings
--- Use this to identify memory leaks or optimize garbage collection timing
---@return GCStats stats GC statistics
function flexlove.getGCStats()
  return {
    gcCount = flexlove._gcState.gcCount,
    framesSinceLastGC = flexlove._gcState.framesSinceLastGC,
    currentMemoryMB = flexlove._gcState.lastMemory,
    strategy = flexlove._gcConfig.strategy,
    threshold = flexlove._gcConfig.memoryThreshold,
  }
end

--- Forward text input to focused editable elements like text fields and text areas
--- Hook this to love.textinput() to enable text entry in your UI
---@param text string
function flexlove.textinput(text)
  local focusedElement = Context.getFocused()
  if focusedElement and not focusedElement.disabled then
    focusedElement:textinput(text)
  end
end

--- Handle keyboard input for text editing, navigation, and performance overlay toggling
--- Hook this to love.keypressed() to enable text selection, cursor movement, and the performance HUD
---@param key string
---@param scancode string
---@param isrepeat boolean
function flexlove.keypressed(key, scancode, isrepeat)
  if flexlove._Performance then
    flexlove._Performance:keypressed(key)
  end
  if flexlove._debugDrawKey and key == flexlove._debugDrawKey then
    flexlove._debugDraw = not flexlove._debugDraw
  end

  -- Handle keyboard navigation (if module is available and enabled)
  if KeyboardNavigation and KeyboardNavigation.config and KeyboardNavigation.config.enabled then
    -- Debug logging for keyboard navigation entry point
    if KeyboardNavigation.config.debugMode then
      print(string.format("[FlexLove.keypressed] Keyboard nav enabled, handling key: %s", key))
    end

    -- Check if we're in text input mode (editable element focused)
    local focusedElement = Context.getFocused()
    local isTextInputMode = focusedElement and (focusedElement.editable or focusedElement._textEditor)

    -- Only handle navigation if not in text input mode, or if in text input mode without modifiers
    local shouldHandleNav = not isTextInputMode
      or (
        isTextInputMode
        and not (
          love.keyboard.isDown("lctrl")
          or love.keyboard.isDown("rctrl")
          or love.keyboard.isDown("lalt")
          or love.keyboard.isDown("ralt")
        )
      )

    if shouldHandleNav then
      local handled = KeyboardNavigation:handleKeyPress(key, scancode, isrepeat)
      if KeyboardNavigation.config.debugMode and not handled then
        print(string.format("[FlexLove.keypressed] Key %s was NOT handled by keyboard navigation", key))
      end
      if handled then
        return -- Navigation handled the key, don't forward to element
      end
    end
  end

  -- Forward to focused element for text input
  local focusedElement = Context.getFocused()
  if focusedElement and not focusedElement.disabled then
    focusedElement:keypressed(key, scancode, isrepeat)
  end
end

--- Enable mouse wheel scrolling in scrollable containers and lists
--- Hook this to love.wheelmoved() to allow users to scroll through content naturally
---@param dx number
---@param dy number
function flexlove.wheelmoved(dx, dy)
  local mx, my = love.mouse.getPosition()
  local element = Context.findScrollableAtPosition(mx, my)

  if element then
    element:_handleWheelScroll(dx, dy)

    -- In immediate mode, persist scroll manager state for next frame
    if flexlove._immediateMode and element._stateId and element._scrollManager then
      local scrollManagerState = element._scrollManager:getState()
      StateManager.updateState(element._stateId, {
        scrollManager = scrollManagerState,
      })
    end
  end
end

--- Find the touch-interactive element at a given position using z-index ordering
--- Similar to getElementAtPosition but checks for touch-enabled elements
---@param x number Touch X position
---@param y number Touch Y position
---@return Element|nil element The topmost touch-enabled element at position
function flexlove._getTouchElementAtPosition(x, y)
  local candidates = {}

  local function collectTouchHits(element, scrollOffsetX, scrollOffsetY)
    scrollOffsetX = scrollOffsetX or 0
    scrollOffsetY = scrollOffsetY or 0

    -- pointHitsElement is the single canonical bounds + display:none guard.
    if Context.pointHitsElement(element, x, y, scrollOffsetX, scrollOffsetY) then
      -- Check if element is touch-enabled and interactive
      if
        element.touchEnabled
        and not element.disabled
        and (element.onEvent or element.onTouchEvent or element.onGesture)
      then
        table.insert(candidates, element)
      end

      -- Check if this element has scrollable overflow (for touch scrolling)
      local overflowX = element.overflowX or element.overflow
      local overflowY = element.overflowY or element.overflow
      local hasScrollableOverflow = (
        overflowX == "scroll"
        or overflowX == "auto"
        or overflowY == "scroll"
        or overflowY == "auto"
        or overflowX == "hidden"
        or overflowY == "hidden"
      )

      -- Accumulate scroll offset for children
      local childScrollOffsetX = scrollOffsetX
      local childScrollOffsetY = scrollOffsetY
      if hasScrollableOverflow then
        childScrollOffsetX = childScrollOffsetX + (element._scrollX or 0)
        childScrollOffsetY = childScrollOffsetY + (element._scrollY or 0)
      end

      for _, child in ipairs(element.children) do
        collectTouchHits(child, childScrollOffsetX, childScrollOffsetY)
      end
    end
  end

  for _, element in ipairs(flexlove.topElements) do
    collectTouchHits(element)
  end

  -- Sort by z-index (highest first) — topmost element wins
  table.sort(candidates, function(a, b)
    return a.z > b.z
  end)

  return candidates[1]
end

local function elementIsTouchScrollable(element)
  if not element or not element._scrollManager then
    return false
  end
  local overflowX = element.overflowX or element.overflow
  local overflowY = element.overflowY or element.overflow
  return overflowX == "scroll"
    or overflowX == "auto"
    or overflowY == "scroll"
    or overflowY == "auto"
end

-- Walk parents from a hit target so a finger on a button/row still scrolls
-- the containing list. Falls back to the wheel path's scrollable lookup when
-- the press lands on empty space inside a scroller.
local function findTouchScrollTarget(x, y, startElement)
  local el = startElement
  while el do
    if elementIsTouchScrollable(el) then
      return el
    end
    el = el.parent
  end
  return Context.findScrollableAtPosition(x, y)
end

local function findElementByStateId(stateId)
  if not stateId or stateId == "" then
    return nil
  end
  local function walk(element)
    if element.id == stateId or element._stateId == stateId then
      return element
    end
    for _, child in ipairs(element.children or {}) do
      local found = walk(child)
      if found then
        return found
      end
    end
    return nil
  end
  for _, element in ipairs(flexlove.topElements or {}) do
    local found = walk(element)
    if found then
      return found
    end
  end
  for _, element in ipairs(flexlove._currentFrameElements or {}) do
    local found = walk(element)
    if found then
      return found
    end
  end
  return nil
end

local function persistTouchScroll(element)
  if flexlove._immediateMode and element and element._stateId and element._scrollManager then
    StateManager.updateState(element._stateId, {
      scrollManager = element._scrollManager:getState(),
    })
  end
end

local function resolveTouchScrollElement(track)
  if not track then
    return nil
  end
  local element = findElementByStateId(track.id)
  if elementIsTouchScrollable(element) then
    return element
  end
  return nil
end

--- Handle touch press events from LÖVE's touch input system
--- Routes touch to the topmost element at the touch position and assigns touch ownership
--- Hook this to love.touchpressed() to enable touch interaction
---@param id lightuserdata Touch identifier from LÖVE
---@param x number Touch X position in screen coordinates
---@param y number Touch Y position in screen coordinates
---@param dx number X distance moved (usually 0 on press)
---@param dy number Y distance moved (usually 0 on press)
---@param pressure number Touch pressure (0-1, if supported by device)
function flexlove.touchpressed(id, x, y, dx, dy, pressure)
  local touchId = tostring(id)
  pressure = pressure or 1.0

  -- Apply base scaling if configured
  local touchX, touchY = x, y
  if flexlove.baseScale then
    touchX = x / flexlove.scaleFactors.x
    touchY = y / flexlove.scaleFactors.y
  end

  -- Find the topmost touch-enabled element at this position
  local element = flexlove._getTouchElementAtPosition(touchX, touchY)

  if element then
    -- Assign touch ownership: this element receives all subsequent events for this touch
    flexlove._touchOwners[touchId] = element

    -- Create and route touch event
    local touchEvent = InputEvent.fromTouch(id, touchX, touchY, "began", pressure)
    element:handleTouchEvent(touchEvent)

    -- Feed to shared gesture recognizer
    if flexlove._gestureRecognizer then
      local gestures = flexlove._gestureRecognizer:processTouchEvent(touchEvent)
      if gestures then
        for _, gesture in ipairs(gestures) do
          element:handleGesture(gesture)
        end
      end
    end
  end

  -- Scroll target is the nearest scrollable ancestor (or the scroller under
  -- empty space). Tracked by stable id so immediate-mode recreation can resume.
  local scrollEl = findTouchScrollTarget(touchX, touchY, element)
  if scrollEl and scrollEl._scrollManager then
    local scrollId = scrollEl._stateId or scrollEl.id
    if scrollId and scrollId ~= "" then
      flexlove._touchScroll[touchId] = {
        id = scrollId,
        lastX = touchX,
        lastY = touchY,
      }
    end
    scrollEl._scrollManager:handleTouchPress(touchX, touchY)
    persistTouchScroll(scrollEl)
  end
end

--- Handle touch move events from LÖVE's touch input system
--- Routes touch to the element that owns this touch ID (from the original press), regardless of current position
--- Hook this to love.touchmoved() to enable touch drag and gesture tracking
---@param id lightuserdata Touch identifier from LÖVE
---@param x number Touch X position in screen coordinates
---@param y number Touch Y position in screen coordinates
---@param dx number X distance moved since last event
---@param dy number Y distance moved since last event
---@param pressure number Touch pressure (0-1, if supported by device)
function flexlove.touchmoved(id, x, y, dx, dy, pressure)
  local touchId = tostring(id)
  pressure = pressure or 1.0

  -- Apply base scaling if configured
  local touchX, touchY = x, y
  if flexlove.baseScale then
    touchX = x / flexlove.scaleFactors.x
    touchY = y / flexlove.scaleFactors.y
  end

  -- Route to owning element (touch ownership persists from press to release)
  local element = flexlove._touchOwners[touchId]
  if element then
    -- Create and route touch event
    local touchEvent = InputEvent.fromTouch(id, touchX, touchY, "moved", pressure)
    element:handleTouchEvent(touchEvent)

    -- Feed to shared gesture recognizer
    if flexlove._gestureRecognizer then
      local gestures = flexlove._gestureRecognizer:processTouchEvent(touchEvent)
      if gestures then
        for _, gesture in ipairs(gestures) do
          element:handleGesture(gesture)
        end
      end
    end
  end

  local track = flexlove._touchScroll[touchId]
  local scrollEl = resolveTouchScrollElement(track)
  if track and scrollEl then
    local sm = scrollEl._scrollManager
    -- Immediate mode recreates managers each frame; re-arm drag from the
    -- last persisted touch point so a move after beginFrame still scrolls.
    if not sm._touchScrolling then
      sm:handleTouchPress(track.lastX, track.lastY)
    end
    sm:handleTouchMove(touchX, touchY)
    persistTouchScroll(scrollEl)
    track.lastX = touchX
    track.lastY = touchY
  end
end

--- Handle touch release events from LÖVE's touch input system
--- Routes touch to the owning element and cleans up touch ownership tracking
--- Hook this to love.touchreleased() to properly end touch interactions
---@param id lightuserdata Touch identifier from LÖVE
---@param x number Touch X position in screen coordinates
---@param y number Touch Y position in screen coordinates
---@param dx number X distance moved since last event
---@param dy number Y distance moved since last event
---@param pressure number Touch pressure (0-1, if supported by device)
function flexlove.touchreleased(id, x, y, dx, dy, pressure)
  local touchId = tostring(id)
  pressure = pressure or 1.0

  -- Apply base scaling if configured
  local touchX, touchY = x, y
  if flexlove.baseScale then
    touchX = x / flexlove.scaleFactors.x
    touchY = y / flexlove.scaleFactors.y
  end

  -- Route to owning element
  local element = flexlove._touchOwners[touchId]
  if element then
    -- Create and route touch event
    local touchEvent = InputEvent.fromTouch(id, touchX, touchY, "ended", pressure)
    element:handleTouchEvent(touchEvent)

    -- Feed to shared gesture recognizer
    if flexlove._gestureRecognizer then
      local gestures = flexlove._gestureRecognizer:processTouchEvent(touchEvent)
      if gestures then
        for _, gesture in ipairs(gestures) do
          element:handleGesture(gesture)
        end
      end
    end
  end

  local track = flexlove._touchScroll[touchId]
  local scrollEl = resolveTouchScrollElement(track)
  if track and scrollEl then
    local sm = scrollEl._scrollManager
    if not sm._touchScrolling then
      sm:handleTouchPress(track.lastX, track.lastY)
    end
    sm:handleTouchMove(touchX, touchY)
    sm:handleTouchRelease()
    persistTouchScroll(scrollEl)
  end

  -- Clean up touch ownership (touch is complete)
  flexlove._touchOwners[touchId] = nil
  flexlove._touchScroll[touchId] = nil
end

--- Get the number of currently active touches being tracked
---@return number count Number of active touch points
function flexlove.getActiveTouchCount()
  local count = 0
  for _ in pairs(flexlove._touchOwners) do
    count = count + 1
  end
  return count
end

--- Get the element that currently owns a specific touch
---@param touchId string|lightuserdata Touch identifier
---@return Element|nil element The element owning this touch, or nil
function flexlove.getTouchOwner(touchId)
  return flexlove._touchOwners[tostring(touchId)]
end

--- Retrieve an element by its ID from the UI tree
--- Works in both immediate and retained modes; searches all known elements including top-level and nested children
---@param id string The element ID to search for
---@return Element|nil element The found element, or nil if not found
function flexlove.getById(id)
  if not id or id == "" then
    return nil
  end

  local function findElementById(element, targetId)
    if element.id == targetId then
      return element
    end

    for _, child in ipairs(element.children) do
      local result = findElementById(child, targetId)
      if result then
        return result
      end
    end

    return nil
  end

  for _, win in ipairs(flexlove.topElements) do
    local result = findElementById(win, id)
    if result then
      return result
    end
  end

  if flexlove._currentFrameElements then
    for _, element in ipairs(flexlove._currentFrameElements) do
      local result = findElementById(element, id)
      if result then
        return result
      end
    end
  end

  if Context._zIndexOrderedElements then
    for _, element in ipairs(Context._zIndexOrderedElements) do
      local result = findElementById(element, id)
      if result then
        return result
      end
    end
  end

  return nil
end

--- Clean up all UI elements and reset FlexLove to initial state when changing scenes or shutting down
--- Use this to prevent memory leaks when transitioning between game states or menus
function flexlove.destroy()
  for _, win in ipairs(flexlove.topElements) do
    win:destroy()
  end
  flexlove.topElements = {}
  flexlove.baseScale = nil
  flexlove.scaleFactors = { x = 1.0, y = 1.0 }
  flexlove._cachedViewport = { width = 0, height = 0 }

  -- Release canvases explicitly before destroying
  if flexlove._gameCanvas then
    flexlove._gameCanvas:release()
  end
  if flexlove._backdropCanvas then
    flexlove._backdropCanvas:release()
  end

  flexlove._gameCanvas = nil
  flexlove._backdropCanvas = nil
  flexlove._canvasDimensions = { width = 0, height = 0 }
  Context.clearFocus()
  StateManager:reset()

  -- Clean up touch state
  flexlove._touchOwners = {}
  flexlove._touchScroll = {}
  flexlove._mouseButtonStates = {}
  if flexlove._gestureRecognizer then
    flexlove._gestureRecognizer:reset()
  end
end

--- Create a new UI element with flexbox layout, styling, and interaction capabilities
--- This is your primary API for building interfaces - buttons, panels, text, images, and containers
--- If called before FlexLove.init(), the element creation will be automatically queued and executed after initialization
---@param props ElementProps
---@param callback? function Optional callback function(element) that will be called with the created element (useful when queued)
---@return Element -- Returns element if initialized, nil if queued for later creation
function flexlove.new(props, callback)
  props = props or {}

  if not flexlove.initialized then
    -- Queue element creation for after initialization
    table.insert(flexlove._initQueue, {
      props = props,
      callback = callback,
    })

    if flexlove._initState == "uninitialized" then
      if flexlove._ErrorHandler then
        flexlove._ErrorHandler:warn(
          "FlexLove",
          "[FlexLove] Element creation queued - FlexLove.init() has not been called yet. Element will be created automatically after init() is called."
        )
      end
    end
    return nil
  end

  -- Use global mode to determine behavior
  if not flexlove._immediateMode then
    return Element.new(props)
  end

  -- Immediate mode - proceed with immediate-mode logic
  -- Auto-begin frame if not manually started (convenience feature)
  if not flexlove._frameStarted then
    flexlove.beginFrame()
    flexlove._autoBeganFrame = true
  end

  -- Immediate mode: generate ID if not provided
  if not props.id then
    props.id = StateManager.generateID(props, props.parent)
  end

  -- Get or create state for this element
  local state = StateManager.getState(props.id, {})

  -- Mark state as used this frame
  StateManager.markStateUsed(props.id)

  -- Inject scroll state into props BEFORE creating element
  -- This ensures scroll position is set before layoutChildren/detectOverflow is called
  -- ScrollManager state uses _scrollX/_scrollY with underscore prefix
  if state.scrollManager then
    props._scrollX = state.scrollManager._scrollX or 0
    props._scrollY = state.scrollManager._scrollY or 0
  else
    -- Fallback to old state structure for backward compatibility
    props._scrollX = state._scrollX or 0
    props._scrollY = state._scrollY or 0
  end

  local element = Element.new(props)

  -- Restore all state from StateManager (delegates to sub-modules)
  element:restoreState(state)

  -- Bind element to StateManager for interactive states
  element._stateId = props.id

  -- Set initial theme state based on StateManager state
  -- This will be updated in Element:update() but we need an initial value
  if element.themeComponent then
    local eventState = state.eventHandler or {}
    if element.disabled or eventState.disabled then
      element._themeState = "disabled"
    elseif element.active or eventState.active then
      element._themeState = "active"
    elseif eventState._pressed and next(eventState._pressed) then
      element._themeState = "pressed"
    elseif eventState._hovered then
      element._themeState = "hover"
    else
      element._themeState = "normal"
    end
  end

  table.insert(flexlove._currentFrameElements, element)

  return element
end

--- Check how many UI element states are being tracked in immediate mode to detect memory leaks
--- Use this during development to ensure states are properly cleaned up
---@return number
function flexlove.getStateCount()
  if not flexlove._immediateMode then
    return 0
  end
  return StateManager.getStateCount()
end

--- Remove stored state for a specific element when you know it won't be rendered again
--- Use this to immediately free memory for elements you've removed from your UI
---@param id string
function flexlove.clearState(id)
  if not flexlove._immediateMode then
    return
  end
  StateManager.clearState(id)
end

--- Wipe all element state when transitioning between completely different UI screens
--- Use this for scene transitions to start with a clean slate and prevent state pollution
function flexlove.clearAllStates()
  if not flexlove._immediateMode then
    return
  end
  StateManager.clearAllStates()
end

--- Inspect state management metrics to diagnose performance issues and optimize immediate mode usage
--- Use this to understand state lifecycle and identify unexpected state accumulation
---@return { stateCount: number, frameNumber: number, oldestState: number|nil, newestState: number|nil }
function flexlove.getStateStats()
  if not flexlove._immediateMode then
    return { stateCount = 0, frameNumber = 0 }
  end
  return StateManager.getStats()
end

--- Create a calc() expression for dynamic CSS-like calculations
--- Use this to create responsive layouts that adapt to viewport and parent dimensions
--- @usage
--- local button = FlexLove.new({
---   x = FlexLove.calc("50% - 10vw"),
---   y = FlexLove.calc("50% - 5vh"),
---   width = "20vw",
---   height = "10vh",
--- })
---@param expr string The calc expression (e.g., "50% - 10vw", "100px + 20%")
---@return CalcObject calcObject A calc expression object that will be evaluated during layout
function flexlove.calc(expr)
  return Calc.new(expr)
end

--- Get the currently focused element
--- Returns the element that is currently receiving keyboard input (e.g., text input, text area)
---@return Element|nil The focused element, or nil if no element has focus
function flexlove.getFocusedElement()
  return Context.getFocused()
end

--- Set focus to a specific element
--- Automatically blurs the previously focused element if different
--- Use this to programmatically focus text inputs or other interactive elements
---@param element Element|nil The element to focus (nil to clear focus)
function flexlove.setFocusedElement(element)
  Context.setFocused(element)
end

--- Clear focus from any element
--- Removes keyboard focus from the currently focused element
function flexlove.clearFocus()
  Context.setFocused(nil)
end

--- Enable or disable the debug draw overlay that renders element boundaries with random colors
--- Each element gets a unique color: full opacity border and 0.5 opacity fill to identify collisions and overlaps
---@param enabled boolean True to enable debug draw overlay, false to disable
function flexlove.setDebugDraw(enabled)
  flexlove._debugDraw = enabled
end

--- Check if the debug draw overlay is currently active
---@return boolean enabled True if debug draw overlay is enabled
function flexlove.getDebugDraw()
  return flexlove._debugDraw
end

flexlove.Animation = Animation
flexlove.Color = Color
flexlove.Theme = Theme
flexlove.enums = enums

return flexlove
