---@class ErrorCodes
---@field categories table
---@field codes table
local ErrorCodes = {
  categories = {
    VAL = "Validation",
    LAY = "Layout",
    REN = "Render",
    THM = "Theme",
    EVT = "Event",
    RES = "Resource",
    SYS = "System",
  },
  codes = {
    -- Validation Errors (VAL_001 - VAL_099)
    VAL_001 = {
      code = "FLEXLOVE_VAL_001",
      category = "VAL",
      description = "Invalid property type",
      suggestion = "Check the property type matches the expected type (e.g., number, string, table)",
    },
    VAL_002 = {
      code = "FLEXLOVE_VAL_002",
      category = "VAL",
      description = "Property value out of range",
      suggestion = "Ensure the value is within the allowed min/max range",
    },
    VAL_003 = {
      code = "FLEXLOVE_VAL_003",
      category = "VAL",
      description = "Required property missing",
      suggestion = "Provide the required property in your element definition",
    },
    VAL_004 = {
      code = "FLEXLOVE_VAL_004",
      category = "VAL",
      description = "Invalid color format",
      suggestion = "Use valid color format: {r, g, b, a} with values 0-1, hex string, or Color object",
    },
    VAL_005 = {
      code = "FLEXLOVE_VAL_005",
      category = "VAL",
      description = "Invalid unit format",
      suggestion = "Use valid unit format: number (px), '50%', '10vw', '5vh', etc.",
    },
    VAL_006 = {
      code = "FLEXLOVE_VAL_006",
      category = "VAL",
      description = "Invalid calc() expression or calculation error",
      suggestion = "Check calc() syntax and ensure no division by zero. Format: calc('value1 operator value2') with operators: +, -, *, / and units: px, %, vw, vh",
    },
    VAL_007 = {
      code = "FLEXLOVE_VAL_007",
      category = "VAL",
      description = "Invalid enum value",
      suggestion = "Use one of the allowed enum values for this property",
    },
    VAL_008 = {
      code = "FLEXLOVE_VAL_008",
      category = "VAL",
      description = "Invalid text input",
      suggestion = "Ensure text meets validation requirements (length, pattern, allowed characters)",
    },

    -- Layout Errors (LAY_001 - LAY_099)
    LAY_001 = {
      code = "FLEXLOVE_LAY_001",
      category = "LAY",
      description = "Invalid flex direction",
      suggestion = "Use 'horizontal' or 'vertical' for flexDirection",
    },
    LAY_002 = {
      code = "FLEXLOVE_LAY_002",
      category = "LAY",
      description = "Circular dependency detected",
      suggestion = "Remove circular references in element hierarchy or layout constraints",
    },
    LAY_003 = {
      code = "FLEXLOVE_LAY_003",
      category = "LAY",
      description = "Invalid dimensions (negative or NaN)",
      suggestion = "Ensure width and height are positive numbers",
    },
    LAY_004 = {
      code = "FLEXLOVE_LAY_004",
      category = "LAY",
      description = "Layout calculation overflow",
      suggestion = "Reduce complexity of layout or increase recursion limit",
    },
    LAY_005 = {
      code = "FLEXLOVE_LAY_005",
      category = "LAY",
      description = "Invalid alignment value",
      suggestion = "Use valid alignment values (flex-start, center, flex-end, etc.)",
    },
    LAY_006 = {
      code = "FLEXLOVE_LAY_006",
      category = "LAY",
      description = "Invalid positioning mode",
      suggestion = "Use 'absolute', 'relative', 'flex', or 'grid' for positioning",
    },
    LAY_007 = {
      code = "FLEXLOVE_LAY_007",
      category = "LAY",
      description = "Grid layout error",
      suggestion = "Check grid template columns/rows and item placement",
    },
    LAY_008 = {
      code = "FLEXLOVE_LAY_008",
      category = "LAY",
      description = "Explicit position will be ignored by flex layout",
      suggestion = "Remove x/y properties (flex layout controls position), OR set positioning='absolute' with left/top/right/bottom properties. Additionally, you can use margin/padding for positional offsets in flex layouts.",
    },
    LAY_009 = {
      code = "FLEXLOVE_LAY_009",
      category = "LAY",
      description = "Flex layout properties ignored with grid positioning",
      suggestion = "Remove flexDirection/justifyContent/alignItems properties, or change positioning to 'flex' or 'relative'",
    },
    LAY_010 = {
      code = "FLEXLOVE_LAY_010",
      category = "LAY",
      description = "Grid layout properties ignored without grid positioning",
      suggestion = "Set positioning='grid' to use grid layout properties, or remove grid properties",
    },
    LAY_011 = {
      code = "FLEXLOVE_LAY_011",
      category = "LAY",
      description = "CSS positioning properties ignored",
      suggestion = "Set positioning='absolute' to use top/bottom/left/right properties",
    },

    -- Rendering Errors (REN_001 - REN_099)
    REN_001 = {
      code = "FLEXLOVE_REN_001",
      category = "REN",
      description = "Invalid render state",
      suggestion = "Ensure element is properly initialized before rendering",
    },
    REN_002 = {
      code = "FLEXLOVE_REN_002",
      category = "REN",
      description = "Texture loading failed",
      suggestion = "Check image path and format, ensure file exists",
    },
    REN_003 = {
      code = "FLEXLOVE_REN_003",
      category = "REN",
      description = "Font loading failed",
      suggestion = "Check font path and format, ensure file exists",
    },
    REN_004 = {
      code = "FLEXLOVE_REN_004",
      category = "REN",
      description = "Invalid color value",
      suggestion = "Color components must be numbers between 0 and 1",
    },
    REN_005 = {
      code = "FLEXLOVE_REN_005",
      category = "REN",
      description = "Clipping stack overflow",
      suggestion = "Reduce nesting depth or check for missing scissor pops",
    },
    REN_006 = {
      code = "FLEXLOVE_REN_006",
      category = "REN",
      description = "Shader compilation failed",
      suggestion = "Check shader code for syntax errors",
    },
    REN_007 = {
      code = "FLEXLOVE_REN_007",
      category = "REN",
      description = "Invalid nine-patch configuration",
      suggestion = "Check nine-patch slice values and image dimensions",
    },

    -- Theme Errors (THM_001 - THM_099)
    THM_001 = {
      code = "FLEXLOVE_THM_001",
      category = "THM",
      description = "Theme file not found",
      suggestion = "Check theme file path and ensure file exists",
    },
    THM_002 = {
      code = "FLEXLOVE_THM_002",
      category = "THM",
      description = "Invalid theme structure",
      suggestion = "Theme must return a table with 'name' and component styles",
    },
    THM_003 = {
      code = "FLEXLOVE_THM_003",
      category = "THM",
      description = "Required theme property missing",
      suggestion = "Ensure theme has required properties (name, base styles, etc.)",
    },
    THM_004 = {
      code = "FLEXLOVE_THM_004",
      category = "THM",
      description = "Invalid component style",
      suggestion = "Component styles must be tables with valid properties",
    },
    THM_005 = {
      code = "FLEXLOVE_THM_005",
      category = "THM",
      description = "Theme loading failed",
      suggestion = "Check theme file for Lua syntax errors",
    },
    THM_006 = {
      code = "FLEXLOVE_THM_006",
      category = "THM",
      description = "Invalid theme color",
      suggestion = "Theme colors must be valid color values (hex, rgba, Color object)",
    },
    THM_007 = {
      code = "FLEXLOVE_THM_007",
      category = "THM",
      description = "themeStateLock has no effect without a valid theme component",
      suggestion = "Ensure themeComponent is set and valid when using themeStateLock",
    },
    THM_008 = {
      code = "FLEXLOVE_THM_008",
      category = "THM",
      description = "Theme component has no state variants",
      suggestion = "themeStateLock has no effect on components without state variants",
    },
    THM_009 = {
      code = "FLEXLOVE_THM_009",
      category = "THM",
      description = "Requested theme state does not exist",
      suggestion = "Use one of the available theme states or set themeStateLock to false",
    },
    THM_010 = {
      code = "FLEXLOVE_THM_010",
      category = "THM",
      description = "Invalid themeStateLock type",
      suggestion = "themeStateLock must be boolean or string (state name)",
    },

    -- Event Errors (EVT_001 - EVT_099)
    EVT_001 = {
      code = "FLEXLOVE_EVT_001",
      category = "EVT",
      description = "Invalid event type",
      suggestion = "Use valid event types (mousepressed, textinput, etc.)",
    },
    EVT_002 = {
      code = "FLEXLOVE_EVT_002",
      category = "EVT",
      description = "Event handler error",
      suggestion = "Check event handler function for errors",
    },
    EVT_003 = {
      code = "FLEXLOVE_EVT_003",
      category = "EVT",
      description = "Event propagation error",
      suggestion = "Check event bubbling/capturing logic",
    },
    EVT_004 = {
      code = "FLEXLOVE_EVT_004",
      category = "EVT",
      description = "Invalid event target",
      suggestion = "Ensure event target element exists and is valid",
    },
    EVT_005 = {
      code = "FLEXLOVE_EVT_005",
      category = "EVT",
      description = "Event handler not a function",
      suggestion = "Event handlers must be functions",
    },

    -- Resource Errors (RES_001 - RES_099)
    RES_001 = {
      code = "FLEXLOVE_RES_001",
      category = "RES",
      description = "File not found",
      suggestion = "Check file path and ensure file exists in the filesystem",
    },
    RES_002 = {
      code = "FLEXLOVE_RES_002",
      category = "RES",
      description = "Permission denied",
      suggestion = "Check file permissions and access rights",
    },
    RES_003 = {
      code = "FLEXLOVE_RES_003",
      category = "RES",
      description = "Invalid file format",
      suggestion = "Ensure file format is supported (png, jpg, ttf, etc.)",
    },
    RES_004 = {
      code = "FLEXLOVE_RES_004",
      category = "RES",
      description = "Resource loading failed",
      suggestion = "Check file integrity and format compatibility",
    },
    RES_005 = {
      code = "FLEXLOVE_RES_005",
      category = "RES",
      description = "Image cache error",
      suggestion = "Clear image cache or check memory availability",
    },

    -- System Errors (SYS_001 - SYS_099)
    SYS_001 = {
      code = "FLEXLOVE_SYS_001",
      category = "SYS",
      description = "Memory allocation failed",
      suggestion = "Reduce memory usage or check available memory",
    },
    SYS_002 = {
      code = "FLEXLOVE_SYS_002",
      category = "SYS",
      description = "Stack overflow",
      suggestion = "Reduce recursion depth or check for infinite loops",
    },
    SYS_003 = {
      code = "FLEXLOVE_SYS_003",
      category = "SYS",
      description = "Invalid state",
      suggestion = "Check initialization order and state management",
    },
    SYS_004 = {
      code = "FLEXLOVE_SYS_004",
      category = "SYS",
      description = "Module initialization failed",
      suggestion = "Check module dependencies and initialization order",
    },

    -- Performance Warnings (PERF_001 - PERF_099)
    PERF_001 = {
      code = "FLEXLOVE_PERF_001",
      category = "PERF",
      description = "Performance threshold exceeded",
      suggestion = "Operation took longer than recommended. Monitor for patterns.",
    },
    PERF_002 = {
      code = "FLEXLOVE_PERF_002",
      category = "PERF",
      description = "Critical performance threshold exceeded",
      suggestion = "Operation is causing frame drops. Consider optimizing or reducing frequency.",
    },
    PERF_003 = {
      code = "FLEXLOVE_PERF_003",
      category = "PERF",
      description = "Large blur area in immediate mode",
      suggestion = "Consider using retained mode for this component to avoid recreating blur effects every frame.",
    },

    -- Memory Warnings (MEM_001 - MEM_099)
    MEM_001 = {
      code = "FLEXLOVE_MEM_001",
      category = "MEM",
      description = "Memory leak detected",
      suggestion = "Table is growing consistently. Review cache eviction policies and ensure objects are properly released.",
    },

    -- State Management Warnings (STATE_001 - STATE_099)
    STATE_001 = {
      code = "FLEXLOVE_STATE_001",
      category = "STATE",
      description = "CallSite counters accumulating",
      suggestion = "This indicates incrementFrame() may not be called properly. Check immediate mode frame management.",
    },

    -- Animation Errors (ANIM_001 - ANIM_099)
    ANIM_001 = {
      code = "FLEXLOVE_ANIM_001",
      category = "VAL",
      description = "Invalid animation configuration",
      suggestion = "Animation.new() requires a table argument with duration, start, and final properties",
    },
    ANIM_002 = {
      code = "FLEXLOVE_ANIM_002",
      category = "VAL",
      description = "Invalid animation duration",
      suggestion = "Animation duration must be a positive number in seconds",
    },
    ANIM_003 = {
      code = "FLEXLOVE_ANIM_003",
      category = "VAL",
      description = "Invalid animation target",
      suggestion = "Animation can only be applied to table elements",
    },
    ANIM_004 = {
      code = "FLEXLOVE_ANIM_004",
      category = "VAL",
      description = "Invalid animation chain",
      suggestion = "chain() requires an Animation object or function",
    },
    ANIM_005 = {
      code = "FLEXLOVE_ANIM_005",
      category = "VAL",
      description = "Invalid animation delay",
      suggestion = "delay() requires a non-negative number in seconds",
    },
    ANIM_006 = {
      code = "FLEXLOVE_ANIM_006",
      category = "VAL",
      description = "Invalid repeat count",
      suggestion = "repeatCount() requires a non-negative number",
    },
    ANIM_007 = {
      code = "FLEXLOVE_ANIM_007",
      category = "VAL",
      description = "Invalid keyframes configuration",
      suggestion = "Animation.keyframes() requires a table with duration and keyframes array",
    },
    ANIM_008 = {
      code = "FLEXLOVE_ANIM_008",
      category = "VAL",
      description = "Insufficient keyframes",
      suggestion = "Keyframe animations require at least 2 keyframes",
    },
    ANIM_009 = {
      code = "FLEXLOVE_ANIM_009",
      category = "VAL",
      description = "Invalid animation group configuration",
      suggestion = "AnimationGroup.new() requires a table with animations array",
    },
    ANIM_010 = {
      code = "FLEXLOVE_ANIM_010",
      category = "VAL",
      description = "Empty animation group",
      suggestion = "AnimationGroup requires at least one animation",
    },
    ANIM_011 = {
      code = "FLEXLOVE_ANIM_011",
      category = "VAL",
      description = "Invalid animation group mode",
      suggestion = "AnimationGroup mode must be 'parallel' or 'sequence'",
    },

    -- Blur Errors (BLUR_001 - BLUR_099)
    BLUR_001 = {
      code = "FLEXLOVE_BLUR_001",
      category = "VAL",
      description = "Missing draw function",
      suggestion = "applyToRegion requires a draw function to render the content to be blurred",
    },
    BLUR_002 = {
      code = "FLEXLOVE_BLUR_002",
      category = "VAL",
      description = "Missing backdrop canvas",
      suggestion = "applyBackdrop requires a backdrop canvas parameter",
    },

    -- FlexLove Core Errors (CORE_001 - CORE_099)
    CORE_001 = {
      code = "FLEXLOVE_CORE_001",
      category = "VAL",
      description = "Invalid callback function",
      suggestion = "deferCallback expects a function argument",
    },
    CORE_002 = {
      code = "FLEXLOVE_CORE_002",
      category = "SYS",
      description = "Deferred callback execution failed",
      suggestion = "Check the callback function for errors. Error details included in message.",
    },
    CORE_003 = {
      code = "FLEXLOVE_CORE_003",
      category = "VAL",
      description = "Invalid garbage collection strategy",
      suggestion = "GC strategy must be one of: 'default', 'aggressive', 'conservative'",
    },
    CORE_004 = {
      code = "FLEXLOVE_CORE_004",
      category = "SYS",
      description = "Deferred method retry limit exceeded",
      suggestion = "A deferred method has been retried too many times without succeeding. Check that preconditions are eventually met.",
    },
    CORE_005 = {
      code = "FLEXLOVE_CORE_005",
      category = "VAL",
      description = "Invalid deferred method",
      suggestion = "The method name provided to _deferMethod does not exist on the element.",
    },

    -- Element Errors (ELEM_001 - ELEM_099)
    ELEM_001 = {
      code = "FLEXLOVE_ELEM_001",
      category = "VAL",
      description = "Invalid text size",
      suggestion = "textSize must be greater than 0",
    },
    ELEM_002 = {
      code = "FLEXLOVE_ELEM_002",
      category = "VAL",
      description = "Invalid text size unit",
      suggestion = "textSize unit must be one of: px, %, vw, vh, or presets: xs, sm, md, lg, xl, xxl, 2xl, 3xl, 4xl",
    },
    ELEM_003 = {
      code = "FLEXLOVE_ELEM_003",
      category = "VAL",
      description = "Invalid transition configuration",
      suggestion = "setTransition() requires a table with transition properties",
    },
    ELEM_004 = {
      code = "FLEXLOVE_ELEM_004",
      category = "VAL",
      description = "Invalid transition duration",
      suggestion = "Transition duration must be a non-negative number in seconds",
    },
    ELEM_005 = {
      code = "FLEXLOVE_ELEM_005",
      category = "VAL",
      description = "Invalid transition group",
      suggestion = "setTransitionGroup() requires an array of property names",
    },
    ELEM_006 = {
      code = "FLEXLOVE_ELEM_006",
      category = "VAL",
      description = "Incompatible element configuration",
      suggestion = "passwordMode and multiline cannot be used together. Multiline will be disabled.",
    },
    ELEM_007 = {
      code = "FLEXLOVE_ELEM_007",
      category = "VAL",
      description = "Invalid select frame configuration",
      suggestion = "Pass a fully instantiated Element as selectParent.selectFrame. Create it unattached so the owning select can adopt it safely.",
    },
    ELEM_008 = {
      code = "FLEXLOVE_ELEM_008",
      category = "VAL",
      description = "Select frame was already parented before adoption",
      suggestion = "Create the selectFrame without a parent, or explicitly accept that the select will reparent it during adoption.",
    },
    ELEM_009 = {
      code = "FLEXLOVE_ELEM_009",
      category = "VAL",
      description = "Managed select frame was reparented unexpectedly",
      suggestion = "Avoid moving a managed selectFrame outside its owning select after adoption. Let the select own the frame lifecycle.",
    },
    ELEM_010 = {
      code = "FLEXLOVE_ELEM_010",
      category = "VAL",
      description = "Invalid display property value",
      suggestion = "The display property accepts only boolean values (true/false). Pass `true` to show the element or `false` to hide it from layout, rendering, and hit testing.",
    },

    -- Module Loader Warnings (MOD_001 - MOD_099)
    MOD_001 = {
      code = "FLEXLOVE_MOD_001",
      category = "RES",
      description = "Optional module not found",
      suggestion = "Using stub implementation for optional module. This is expected if the module is not required.",
    },

    -- Utility Errors (UTIL_001 - UTIL_099)
    UTIL_001 = {
      code = "FLEXLOVE_UTIL_001",
      category = "VAL",
      description = "Text truncation warning",
      suggestion = "Text was truncated to fit within the maximum allowed length",
    },

    -- Image/Rendering Errors (IMG_001 - IMG_099)
    IMG_001 = {
      code = "FLEXLOVE_IMG_001",
      category = "REN",
      description = "Stencil buffer not available",
      suggestion = "Cannot apply corner radius to image without stencil buffer support. Check graphics capabilities.",
    },

    -- Navigation Errors (NAV_001 - NAV_099)
    NAV_001 = {
      code = "FLEXLOVE_NAV_001",
      category = "EVT",
      description = "Element focus callback error",
      suggestion = "Check the onFocus callback function for errors. Error details included in message.",
    },
    NAV_002 = {
      code = "FLEXLOVE_NAV_002",
      category = "EVT",
      description = "Element activation callback error",
      suggestion = "Check the onEvent callback function for errors. Error details included in message.",
    },
    NAV_003 = {
      code = "FLEXLOVE_NAV_003",
      category = "EVT",
      description = "Element dismiss callback error",
      suggestion = "Check the onDismiss callback function for errors. Error details included in message.",
    },
  },
}

--- Get error information by code
--- @param code string Error code (e.g., "VAL_001" or "FLEXLOVE_VAL_001")
--- @return table? errorInfo Error information or nil if not found
function ErrorCodes.get(code)
  -- Handle both short and full format
  local shortCode = code:gsub("^FLEXLOVE_", "")
  return ErrorCodes.codes[shortCode]
end

--- Get human-readable description for error code
--- @param code string Error code
--- @return string description Error description
function ErrorCodes.describe(code)
  local info = ErrorCodes.get(code)
  if info then
    return info.description
  end
  return "Unknown error code: " .. code
end

--- Search error codes by keyword
--- @param keyword string Keyword to search for
--- @return table codes Matching error codes
function ErrorCodes.search(keyword)
  keyword = keyword:lower()
  local result = {}
  for code, info in pairs(ErrorCodes.codes) do
    local searchText = (code .. " " .. info.description .. " " .. info.suggestion):lower()
    if searchText:find(keyword, 1, true) then
      table.insert(result, {
        code = code,
        fullCode = info.code,
        description = info.description,
        suggestion = info.suggestion,
        category = ErrorCodes.categories[info.category],
      })
    end
  end
  return result
end

--- Format error message with code
--- @param code string Error code
--- @param message string Error message
--- @return string formattedMessage Formatted error message with code
function ErrorCodes.formatMessage(code, message)
  local info = ErrorCodes.get(code)
  if info then
    return string.format("[%s] %s", info.code, message)
  end
  return message
end

--- Validate that all error codes are unique and properly formatted
--- @return boolean, string? Returns true if valid, or false with error message
function ErrorCodes.validate()
  local seen = {}
  local fullCodes = {}

  for code, info in pairs(ErrorCodes.codes) do
    -- Check for duplicates
    if seen[code] then
      return false, "Duplicate error code: " .. code
    end
    seen[code] = true

    if fullCodes[info.code] then
      return false, "Duplicate full error code: " .. info.code
    end
    fullCodes[info.code] = true

    -- Check format
    if not code:match("^[A-Z]+_[0-9]+$") then
      return false, "Invalid code format: " .. code .. " (expected CATEGORY_NUMBER)"
    end

    -- Check full code format
    local expectedFullCode = "FLEXLOVE_" .. code
    if info.code ~= expectedFullCode then
      return false, "Mismatched full code for " .. code .. ": expected " .. expectedFullCode .. ", got " .. info.code
    end

    -- Check required fields
    if not info.description or info.description == "" then
      return false, "Missing description for " .. code
    end
    if not info.suggestion or info.suggestion == "" then
      return false, "Missing suggestion for " .. code
    end
    if not info.category or info.category == "" then
      return false, "Missing category for " .. code
    end
  end

  return true, nil
end

---@enum LOG_LEVEL
local LOG_LEVEL = {
  CRITICAL = 1,
  ERROR = 2,
  WARNING = 3,
  INFO = 4,
  DEBUG = 5,
}

---@enum LOG_TARGET
local LOG_TARGET = {
  CONSOLE = "console",
  FILE = "file",
  BOTH = "both",
  NONE = "none",
}

---@class ErrorHandler
---@field errorCodes ErrorCodes
---@field includeStackTrace boolean -- Default: false
---@field logLevel LOG_LEVEL --Default: LOG_LEVEL.WARNING
---@field logTarget "console" | "file" | "both"
---@field logFile string
---@field maxLogSize number in bytes
---@field maxLogFiles number files to rotate
---@field enableRotation boolean see maxLogFiles
---@field _currentLogSize number private
---@field _logFileHandle file* private
local ErrorHandler = {
  errorCodes = ErrorCodes,
}
ErrorHandler.__index = ErrorHandler

---@type ErrorHandler|nil
local instance = nil

---@param config { includeStackTrace?: boolean, logLevel?: LOG_LEVEL, logTarget?: "console" | "file" | "both", logFile?: string, maxLogSize?: number, maxLogFiles?: number, enableRotation?: boolean }|nil
---@return ErrorHandler
function ErrorHandler.init(config)
  if instance == nil then
    local self = setmetatable({}, ErrorHandler)
    self.includeStackTrace = config and config.includeStackTrace or false
    self.logLevel = config and config.logLevel or LOG_LEVEL.WARNING
    self.logTarget = config and config.logTarget or LOG_TARGET.CONSOLE
    self.logFile = config and config.logFile or "flexlove-errors.log"
    self.maxLogSize = config and config.maxLogSize or 10 * 1024 * 1024
    self.maxLogFiles = config and config.maxLogFiles or 5
    self.enableRotation = config and config.enableRotation or true
    self._currentLogSize = 0
    self._logFileHandle = nil
    instance = self
  end
  return instance
end

--- Get the singleton instance (lazily initializes if needed)
---@return ErrorHandler
function ErrorHandler.getInstance()
  if instance == nil then
    ErrorHandler.init()
  end
  return instance
end

--- Get current timestamp with milliseconds
---@return string|osdate Formatted timestamp
function ErrorHandler:_getTimestamp()
  local time = os.time()
  local date = os.date("%Y-%m-%d %H:%M:%S", time)
  -- Note: Lua doesn't have millisecond precision by default, so we approximate
  return date
end

--- Rotate log file if needed
function ErrorHandler:_rotateLogIfNeeded()
  if not self.enableRotation then
    return
  end
  if self._currentLogSize < self.maxLogSize then
    return
  end

  -- Close current log
  if self._logFileHandle then
    self._logFileHandle:close()
    self._logFileHandle = nil
  end

  -- Rotate existing logs
  for i = self.maxLogFiles - 1, 1, -1 do
    local oldName = self.logFile .. "." .. i
    local newName = self.logFile .. "." .. (i + 1)
    os.rename(oldName, newName) -- Will fail silently if file doesn't exist
  end

  -- Move current log to .1
  os.rename(self.logFile, self.logFile .. ".1")

  -- Create new log file
  self._logFileHandle = io.open(self.logFile, "a")
  self._currentLogSize = 0
end

--- Escape string for JSON
---@param str string String to escape
---@return string Escaped string
function ErrorHandler:_escapeJson(str)
  str = tostring(str)
  str = str:gsub("\\", "\\\\")
  str = str:gsub('"', '\\"')
  str = str:gsub("\n", "\\n")
  str = str:gsub("\r", "\\r")
  str = str:gsub("\t", "\\t")
  return str
end

--- Format details as JSON object
---@param details table|nil Details object
---@return string JSON string
function ErrorHandler:_formatDetailsJson(details)
  if not details or type(details) ~= "table" then
    return "{}"
  end

  local parts = {}
  for key, value in pairs(details) do
    local jsonKey = self:_escapeJson(tostring(key))
    local jsonValue = self:_escapeJson(tostring(value))
    table.insert(parts, string.format('"%s":"%s"', jsonKey, jsonValue))
  end

  return "{" .. table.concat(parts, ",") .. "}"
end

--- Format details object as readable key-value pairs
---@param details table|nil Details object
---@return string Formatted details
function ErrorHandler:_formatDetails(details)
  if not details or type(details) ~= "table" then
    return ""
  end

  local lines = {}
  for key, value in pairs(details) do
    local formattedKey = tostring(key):gsub("^%l", string.upper)
    local formattedValue = tostring(value)
    -- Truncate very long values
    if #formattedValue > 100 then
      formattedValue = formattedValue:sub(1, 97) .. "..."
    end
    table.insert(lines, string.format("  %s: %s", formattedKey, formattedValue))
  end

  if #lines > 0 then
    return "\n\nDetails:\n" .. table.concat(lines, "\n")
  end
  return ""
end

--- Extract and format stack trace
---@param level number Stack level to start from
---@return string Formatted stack trace
function ErrorHandler:_formatStackTrace(level)
  if not self.includeStackTrace then
    return ""
  end

  local lines = {}
  local currentLevel = level or 3

  while true do
    local info = debug.getinfo(currentLevel, "Sl")
    if not info then
      break
    end

    -- Skip internal Lua files
    if info.source:match("^@") and not info.source:match("loveStub") then
      local source = info.source:sub(2) -- Remove @ prefix
      local location = string.format("%s:%d", source, info.currentline)
      table.insert(lines, "  " .. location)
    end

    currentLevel = currentLevel + 1
    if currentLevel > level + 10 then
      break
    end -- Limit depth
  end

  if #lines > 0 then
    return "\n\nStack trace:\n" .. table.concat(lines, "\n")
  end
  return ""
end

--- Format an error or warning message using error code lookup
---@param module string The module name (e.g., "Element", "Units", "Theme")
---@param level string "Error" or "Warning"
---@param code string Error code (e.g., "VAL_001")
---@param details table|nil Optional details object
---@return string Formatted message
function ErrorHandler:_formatMessage(module, level, code, details)
  local codeInfo = ErrorCodes.get(code)

  if not codeInfo then
    return string.format("[FlexLove - %s] %s: Unknown error code: %s", module, level, code)
  end

  -- Build formatted message
  local parts = {}

  -- Header: [FlexLove - Module] Level [CODE]: Description
  table.insert(parts, string.format("[FlexLove - %s] %s [%s]: %s", module, level, codeInfo.code, codeInfo.description))

  -- Details section
  if details and type(details) == "table" then
    table.insert(parts, self:_formatDetails(details))
  end

  -- Suggestion section
  if codeInfo.suggestion and codeInfo.suggestion ~= "" then
    table.insert(parts, string.format("\n\nSuggestion: %s", codeInfo.suggestion))
  end

  return table.concat(parts, "")
end

--- Write log entry to file and/or console
---@param level string Log level
---@param levelNum number Log level number
---@param module string Module name
---@param code string|nil Error code
---@param message string Message
---@param details table|nil Details
---@param suggestion string|nil Suggestion
function ErrorHandler:_writeLog(level, levelNum, module, code, message, details, suggestion)
  -- Check if we should log this level
  if not levelNum or not self.logLevel or levelNum > self.logLevel then
    return
  end

  local timestamp = self:_getTimestamp()
  local logEntry

  local jsonParts = {
    string.format('"timestamp":"%s"', self:_escapeJson(timestamp)),
    string.format('"level":"%s"', level),
    string.format('"module":"%s"', self:_escapeJson(module)),
    string.format('"message":"%s"', self:_escapeJson(message)),
  }

  if code then
    table.insert(jsonParts, string.format('"code":"%s"', self:_escapeJson(code)))
  end

  if details then
    table.insert(jsonParts, string.format('"details":%s', self:_formatDetailsJson(details)))
  end

  if suggestion then
    table.insert(jsonParts, string.format('"suggestion":"%s"', self:_escapeJson(suggestion)))
  end

  logEntry = "{" .. table.concat(jsonParts, ",") .. "}\n"

  if self.logTarget == "console" or self.logTarget == "both" then
    io.write(logEntry)
    io.flush()
  end

  -- Write to file
  if self.logTarget == "file" or self.logTarget == "both" then
    -- Lazy file opening: open on first write
    if not self._logFileHandle then
      self._logFileHandle = io.open(self.logFile, "a")
      if self._logFileHandle then
        -- Get current file size
        local currentPos = self._logFileHandle:seek("end")
        self._currentLogSize = currentPos or 0
      end
    end

    if self._logFileHandle then
      self:_rotateLogIfNeeded()

      -- Reopen if rotation closed it
      if not self._logFileHandle then
        self._logFileHandle = io.open(self.logFile, "a")
      end

      if self._logFileHandle then
        self._logFileHandle:write(logEntry)
        self._logFileHandle:flush()
        self._currentLogSize = self._currentLogSize + #logEntry
      end
    end
  end
end

--- Throw a critical error (stops execution)
---@param module string The module name
---@param code string Error code (e.g., "VAL_001")
---@param details table|nil Optional details object
function ErrorHandler:error(module, code, details)
  local formattedMessage = self:_formatMessage(module, "Error", code, details)

  local codeInfo = ErrorCodes.get(code)
  local message = codeInfo and codeInfo.description or code
  local suggestion = codeInfo and codeInfo.suggestion or nil

  -- Log the error
  self:_writeLog("ERROR", LOG_LEVEL.ERROR, module, code, message, details, suggestion)

  if self.includeStackTrace then
    formattedMessage = formattedMessage .. self:_formatStackTrace(3)
  end

  error(formattedMessage, 2)
end

--- Print a warning (non-critical, continues execution)
---@param module string The module name
---@param code string Warning code (e.g., "VAL_001")
---@param details table|nil Optional details object
function ErrorHandler:warn(module, code, details)
  local codeInfo = ErrorCodes.get(code)
  local message = codeInfo and codeInfo.description or code
  local suggestion = codeInfo and codeInfo.suggestion or nil

  -- Log the warning
  self:_writeLog("WARNING", LOG_LEVEL.WARNING, module, code, message, details, suggestion)
end

--- Validate that a value is not nil
---@param module string The module name
---@param value any The value to check
---@param paramName string The parameter name
---@return boolean True if valid
function ErrorHandler:assertNotNil(module, value, paramName)
  if value == nil then
    self:error(module, "VAL_003", "Required parameter missing", {
      parameter = paramName,
    })
    return false
  end
  return true
end

--- Validate that a value is of the expected type
---@param module string The module name
--- Warn if a value is deprecated
---@param module string The module name
---@param oldName string The deprecated name
---@param newName string The new name to use
function ErrorHandler:warnDeprecated(module, oldName, newName)
  self:warn(module, string.format("'%s' is deprecated. Use '%s' instead", oldName, newName))
end

return ErrorHandler
