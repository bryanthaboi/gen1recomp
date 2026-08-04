local modulePath = (...):match("(.-)[^%.]+$")
local function req(name)
  return require(modulePath .. name)
end

-- Focused sub-modules (utils now re-exports their surfaces as backward-compatible
-- aliases so call sites needn't change). Loaded eagerly so the aliases resolve.
local NumberValidation = req("NumberValidation")
local TextSanitizer = req("TextSanitizer")
local PathValidator = req("PathValidator")
local FontCache = req("FontCache")
local Enums = req("Enums")

-- ErrorHandler is injected via init() (safeLoadImage closes over this upvalue).
local ErrorHandler = nil

local enums = Enums.enums

-- Generic math, table, and path helpers (utils' own concern).
-- All validation, font-cache, text-sanitization, and path-validation logic
-- lives in the focused sub-modules above and is re-exported below.

--- Get current keyboard modifiers state
---@return {shift:boolean, ctrl:boolean, alt:boolean, super:boolean}
local function getModifiers()
  return {
    shift = love.keyboard.isDown("lshift", "rshift"),
    ctrl = love.keyboard.isDown("lctrl", "rctrl"),
    alt = love.keyboard.isDown("lalt", "ralt"),
    ---@diagnostic disable-next-line
    super = love.keyboard.isDown("lgui", "rgui"), -- cmd/windows key
  }
end

local TEXT_SIZE_PRESETS = {
  ["2xs"] = 0.75,
  xxs = 0.75,
  xs = 1.25,
  sm = 1.75,
  md = 2.25,
  lg = 2.75,
  xl = 3.5,
  xxl = 4.5,
  ["2xl"] = 4.5,
  ["3xl"] = 5.0,
  ["4xl"] = 7.0,
}

--- Resolve text size preset to viewport units
---@param sizeValue string|number
---@return number?, string?
local function resolveTextSizePreset(sizeValue)
  if type(sizeValue) == "string" then
    local preset = TEXT_SIZE_PRESETS[sizeValue]
    if preset then
      return preset, "vh"
    end
  end
  return nil, nil
end

--- Auto-detect the base path where FlexLove is located
---@return string filesystemPath
local function getFlexLoveBasePath()
  local info = debug.getinfo(1, "S")
  if info and info.source then
    local source = info.source
    if source:sub(1, 1) == "@" then
      source = source:sub(2)
    end

    local filesystemPath = source:match("(.*/)")
    if filesystemPath then
      local fsPath = filesystemPath
      fsPath = fsPath:gsub("^%./", "")
      fsPath = fsPath:gsub("/$", "")
      fsPath = fsPath:gsub("/modules$", "")
      return fsPath
    end
  end
  return "libs"
end

local FLEXLOVE_FILESYSTEM_PATH = getFlexLoveBasePath()

--- Helper function to resolve paths relative to FlexLove
---@param path string
---@return string
local function resolveImagePath(path)
  if path:match("^/") or path:match("^[A-Z]:") then
    return path
  end
  return FLEXLOVE_FILESYSTEM_PATH .. "/" .. path
end

-- Math utilities

--- Clamp a value between optional min/max bounds. Either bound may be nil.
--- When both bounds are inverted (min > max), max wins (matches CSS behavior).
---@param value number Value to clamp
---@param min number|nil Minimum value (nil = no lower bound)
---@param max number|nil Maximum value (nil = no upper bound)
---@return number Clamped value
local function clamp(value, min, max)
  if min and value < min then
    value = min
  end
  if max and value > max then
    value = max
  end
  return value
end

--- Linear interpolation between two values
---@param a number Start value
---@param b number End value
---@param t number Interpolation factor (0-1)
---@return number Interpolated value
local function lerp(a, b, t)
  return a + (b - a) * t
end

--- Round a number to the nearest integer
---@param value number Value to round
---@return number Rounded value
local function round(value)
  return math.floor(value + 0.5)
end

-- Image utilities

--- Safely load an image with error handling
--- Returns both Image and ImageData to avoid deprecated getData() API
---@param imagePath string Path to image file
---@return love.Image?, love.ImageData?, string? Returns image, imageData, or nil with error message
local function safeLoadImage(imagePath)
  local success, imageData = pcall(function()
    return love.image.newImageData(imagePath)
  end)

  if not success then
    local errorMsg = string.format("Failed to load image data: %s - %s", imagePath, tostring(imageData))
    if ErrorHandler then
      ErrorHandler:warn("utils", "RES_004", {
        resourceType = "image data",
        path = imagePath,
        error = tostring(imageData),
      })
    end
    return nil, nil, errorMsg
  end

  local imageSuccess, image = pcall(function()
    return love.graphics.newImage(imageData)
  end)

  if imageSuccess then
    return image, imageData, nil
  else
    local errorMsg = string.format("Failed to create image: %s - %s", imagePath, tostring(image))
    if ErrorHandler then
      ErrorHandler:warn("utils", "RES_004", {
        resourceType = "image",
        path = imagePath,
        error = tostring(image),
      })
    end
    return nil, nil, errorMsg
  end
end

-- Color manipulation utilities

--- Brighten a color by a factor
---@param r number Red component (0-1)
---@param g number Green component (0-1)
---@param b number Blue component (0-1)
---@param a number Alpha component (0-1)
---@param factor number Brightness factor (e.g., 1.2 for 20% brighter)
---@return number, number, number, number Brightened color components
local function brightenColor(r, g, b, a, factor)
  return math.min(1, r * factor), math.min(1, g * factor), math.min(1, b * factor), a
end

-- Property normalization utilities

--- Normalize a boolean or table property with vertical/horizontal fields
---@param value boolean|table|nil Input value (boolean applies to both, table for individual control)
---@param defaultValue boolean Default value if nil (default: false)
---@return table Normalized table with vertical and horizontal fields
local function normalizeBooleanTable(value, defaultValue)
  defaultValue = defaultValue or false

  if value == nil then
    return { vertical = defaultValue, horizontal = defaultValue }
  end

  if type(value) == "boolean" then
    return { vertical = value, horizontal = value }
  end

  if type(value) == "table" then
    return {
      vertical = value.vertical ~= nil and value.vertical or defaultValue,
      horizontal = value.horizontal ~= nil and value.horizontal or defaultValue,
    }
  end

  return { vertical = defaultValue, horizontal = defaultValue }
end

--- Normalize an offset value to {x, y} or {horizontal, vertical} format
---@param value number|table|nil Input value (number applies to both, table for individual control)
---@param defaultValue number Default value if nil (default: 0)
---@return table Normalized table with x/y or horizontal/vertical fields
local function normalizeOffsetTable(value, defaultValue)
  defaultValue = defaultValue or 0

  if value == nil then
    return { x = defaultValue, y = defaultValue, horizontal = defaultValue, vertical = defaultValue }
  end

  if type(value) == "number" then
    return { x = value, y = value, horizontal = value, vertical = value }
  end

  if type(value) == "table" then
    -- Support both {x, y} and {horizontal, vertical} formats
    local x = value.x or value.horizontal or defaultValue
    local y = value.y or value.vertical or defaultValue
    return {
      x = x,
      y = y,
      horizontal = x,
      vertical = y,
    }
  end

  return { x = defaultValue, y = defaultValue, horizontal = defaultValue, vertical = defaultValue }
end

--- Apply content auto-sizing multiplier to a dimension
---@param value number The dimension value
---@param multiplier table? The contentAutoSizingMultiplier table {width:number?, height:number?}
---@param axis "width"|"height" Which axis to apply
---@return number The multiplied value
local function applyContentMultiplier(value, multiplier, axis)
  if multiplier and multiplier[axis] then
    return value * multiplier[axis]
  end
  return value
end

--- Initialize dependencies
---@param deps table Dependencies: { ErrorHandler = ErrorHandler }
local function init(deps)
  if type(deps) == "table" then
    ErrorHandler = deps.ErrorHandler
  end
  -- Propagate shared ErrorHandler to focused sub-modules that need it.
  NumberValidation.init({ ErrorHandler = ErrorHandler, clamp = clamp })
  TextSanitizer.init({ ErrorHandler = ErrorHandler })
  FontCache.init({ ErrorHandler = ErrorHandler, resolveImagePath = resolveImagePath })
  -- PathValidator has no external dependencies.
end

return {
  enums = enums,
  FONT_CACHE = FontCache.FONT_CACHE,
  resolveTextSizePreset = resolveTextSizePreset,
  getModifiers = getModifiers,
  TEXT_SIZE_PRESETS = TEXT_SIZE_PRESETS,
  init = init,
  clamp = clamp,
  -- Alias for `clamp`; exposed under the size-clamping name so Element/LayoutEngine
  -- and tests can reference min/max content-size clamping explicitly.
  clampSize = clamp,
  lerp = lerp,
  round = round,
  safeLoadImage = safeLoadImage,
  brightenColor = brightenColor,
  resolveImagePath = resolveImagePath,
  normalizeBooleanTable = normalizeBooleanTable,
  normalizeOffsetTable = normalizeOffsetTable,
  applyContentMultiplier = applyContentMultiplier,
  -- Backward-compatible aliases (delegated to focused sub-modules)
  validateEnum = NumberValidation.validateEnum,
  validateRange = NumberValidation.validateRange,
  validateType = NumberValidation.validateType,
  isNaN = NumberValidation.isNaN,
  isInfinity = NumberValidation.isInfinity,
  validateNumber = NumberValidation.validateNumber,
  sanitizeNumber = NumberValidation.sanitizeNumber,
  validateInteger = NumberValidation.validateInteger,
  validatePercentage = NumberValidation.validatePercentage,
  validateOpacity = NumberValidation.validateOpacity,
  validateDegrees = NumberValidation.validateDegrees,
  validateCoordinate = NumberValidation.validateCoordinate,
  validateDimension = NumberValidation.validateDimension,
  normalizePath = PathValidator.normalizePath,
  sanitizePath = PathValidator.sanitizePath,
  isPathSafe = PathValidator.isPathSafe,
  validatePath = PathValidator.validatePath,
  getFileExtension = PathValidator.getFileExtension,
  hasAllowedExtension = PathValidator.hasAllowedExtension,
  sanitizeText = TextSanitizer.sanitizeText,
  validateTextInput = TextSanitizer.validateTextInput,
  validateTextRange = TextSanitizer.validateTextRange,
  escapeHtml = TextSanitizer.escapeHtml,
  escapeLuaPattern = TextSanitizer.escapeLuaPattern,
  stripNonPrintable = TextSanitizer.stripNonPrintable,
  resolveFontPath = FontCache.resolveFontPath,
  getFont = FontCache.getFont,
  getFontCacheStats = FontCache.getFontCacheStats,
  setFontCacheSize = FontCache.setFontCacheSize,
  clearFontCache = FontCache.clearFontCache,
  preloadFont = FontCache.preloadFont,
  resetFontCacheStats = FontCache.resetFontCacheStats,
}
