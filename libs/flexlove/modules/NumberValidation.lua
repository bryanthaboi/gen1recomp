local modulePath = (...):match("(.-)[^%.]+$")
local function req(name)
  return require(modulePath .. name)
end

-- All numeric, range, type, and enum validation lives here.
-- `clamp` is injected via init() to avoid a cross-import into utils.
-- `ErrorHandler` is injected via init() so error reporting routes through
-- the shared handler (matching the pre-split behavior of utils.validate*).

local ErrorHandler = nil
local clamp = nil

--- Initialize dependencies
---@param deps table Dependencies: { ErrorHandler = table, clamp = function }
local function init(deps)
  if type(deps) == "table" then
    ErrorHandler = deps.ErrorHandler or ErrorHandler
    clamp = deps.clamp or clamp
  end
end

-- Numeric validation utilities

--- Check if a value is NaN (not-a-number)
--- @param value any Value to check
--- @return boolean
local function isNaN(value)
  return type(value) == "number" and value ~= value
end

--- Check if a value is Infinity
--- @param value any Value to check
--- @return boolean
local function isInfinity(value)
  return type(value) == "number" and (value == math.huge or value == -math.huge)
end

--- Validate a numeric value with comprehensive checks
--- @param value any Value to validate
--- @param options table? Validation options
--- @return boolean, string?, number? Returns valid, errorMessage, sanitizedValue
local function validateNumber(value, options)
  options = options or {}

  -- Check if value is a number type
  if type(value) ~= "number" then
    if options.default ~= nil then
      return true, nil, options.default
    end
    return false, string.format("Value must be a number, got %s", type(value)), nil
  end

  -- Check for NaN
  if isNaN(value) then
    if not options.allowNaN then
      if options.default ~= nil then
        return true, nil, options.default
      end
      return false, "Value is NaN (not-a-number)", nil
    end
  end

  -- Check for Infinity
  if isInfinity(value) then
    if not options.allowInfinity then
      if options.default ~= nil then
        return true, nil, options.default
      end
      return false, "Value is Infinity", nil
    end
  end

  -- Check for integer requirement
  if options.integer and math.floor(value) ~= value then
    return false, string.format("Value must be an integer, got %s", value), nil
  end

  -- Check for positive requirement
  if options.positive and value <= 0 then
    return false, string.format("Value must be positive, got %s", value), nil
  end

  -- Check bounds
  if options.min and value < options.min then
    return false, string.format("Value %s is below minimum %s", value, options.min), nil
  end

  if options.max and value > options.max then
    return false, string.format("Value %s is above maximum %s", value, options.max), nil
  end

  return true, nil, value
end

--- Sanitize a numeric value (never errors, always returns valid number)
--- @param value any Value to sanitize
--- @param min number? Minimum value
--- @param max number? Maximum value
--- @param default number? Default value for invalid inputs
--- @return number Sanitized value
local function sanitizeNumber(value, min, max, default)
  default = default or 0
  min = min or -math.huge
  max = max or math.huge

  -- Convert to number if possible
  if type(value) == "string" then
    value = tonumber(value)
  end

  -- Handle non-numeric
  if type(value) ~= "number" then
    return default
  end

  -- Handle NaN
  if isNaN(value) then
    return default
  end

  -- Handle Infinity
  if value == math.huge then
    return max
  end
  if value == -math.huge then
    return min
  end

  -- Clamp to range
  return clamp(value, min, max)
end

--- Validate and convert to integer
--- @param value any Value to validate
--- @param min number? Minimum value
--- @param max number? Maximum value
--- @return boolean, string?, number? Returns valid, errorMessage, integerValue
local function validateInteger(value, min, max)
  local valid, err, sanitized = validateNumber(value, {
    min = min,
    max = max,
    integer = true,
  })

  if not valid then
    return false, err, nil
  end

  return true, nil, math.floor(sanitized or value)
end

--- Validate and normalize percentage value
--- @param value any Value to validate (can be "50%", 0.5, or 50)
--- @return boolean, string?, number? Returns valid, errorMessage, normalizedValue (0-1)
local function validatePercentage(value)
  -- Handle string percentage
  if type(value) == "string" then
    local num = value:match("^(%d+%.?%d*)%%$")
    if num then
      value = tonumber(num)
      if value then
        value = value / 100
      end
    else
      value = tonumber(value)
    end
  end

  if type(value) ~= "number" then
    return false, "Percentage must be a number", nil
  end

  if isNaN(value) or isInfinity(value) then
    return false, "Percentage cannot be NaN or Infinity", nil
  end

  -- If value is > 1, assume it's 0-100 range
  if value > 1 then
    value = value / 100
  end

  -- Clamp to 0-1
  value = clamp(value, 0, 1)

  return true, nil, value
end

--- Validate opacity value (0-1)
--- @param value any Value to validate
--- @return boolean, string?, number? Returns valid, errorMessage, opacityValue
local function validateOpacity(value)
  return validateNumber(value, { min = 0, max = 1, default = 1 })
end

--- Validate degree value (0-360)
--- @param value any Value to validate
--- @return boolean, string?, number? Returns valid, errorMessage, degreeValue
local function validateDegrees(value)
  local valid, err, sanitized = validateNumber(value)
  if not valid then
    return false, err, nil
  end

  -- Normalize to 0-360 range
  local degrees = sanitized or value
  degrees = degrees % 360
  if degrees < 0 then
    degrees = degrees + 360
  end

  return true, nil, degrees
end

--- Validate coordinate value (pixel position)
--- @param value any Value to validate
--- @return boolean, string?, number? Returns valid, errorMessage, coordinateValue
local function validateCoordinate(value)
  return validateNumber(value, {
    allowNaN = false,
    allowInfinity = false,
  })
end

--- Validate dimension value (width/height, must be non-negative)
--- @param value any Value to validate
--- @return boolean, string?, number? Returns valid, errorMessage, dimensionValue
local function validateDimension(value)
  return validateNumber(value, {
    min = 0,
    allowNaN = false,
    allowInfinity = false,
  })
end

--- Validate that a value is in an enum table
---@param value any Value to validate
---@param enumTable table Enum table with valid values
---@param propName string Property name for error messages
---@param moduleName string? Module name for error messages (default: "Element")
---@return boolean True if valid
local function validateEnum(value, enumTable, propName, moduleName)
  if value == nil then
    return true
  end

  for _, validValue in pairs(enumTable) do
    if value == validValue then
      return true
    end
  end

  -- Build list of valid options
  local validOptions = {}
  for _, v in pairs(enumTable) do
    table.insert(validOptions, "'" .. v .. "'")
  end
  table.sort(validOptions)

  if ErrorHandler then
    ErrorHandler:error(moduleName or "Element", "VAL_007", {
      property = propName,
      expected = table.concat(validOptions, ", "),
      got = tostring(value),
    })
  else
    error(
      string.format("%s must be one of: %s. Got: '%s'", propName, table.concat(validOptions, ", "), tostring(value))
    )
  end
end

--- Validate that a numeric value is within a range
---@param value any Value to validate
---@param min number Minimum allowed value
---@param max number Maximum allowed value
---@param propName string Property name for error messages
---@param moduleName string? Module name for error messages (default: "Element")
---@return boolean True if valid
local function validateRange(value, min, max, propName, moduleName)
  if value == nil then
    return true
  end
  if type(value) ~= "number" then
    if ErrorHandler then
      ErrorHandler:error(moduleName or "Element", "VAL_001", {
        property = propName,
        expected = "number",
        got = type(value),
      })
    else
      error(string.format("%s must be a number, got %s", propName, type(value)))
    end
  elseif value < min or value > max then
    if ErrorHandler then
      ErrorHandler:error(moduleName or "Element", "VAL_002", {
        property = propName,
        min = tostring(min),
        max = tostring(max),
        value = tostring(value),
      })
    else
      error(
        string.format("%s must be between %s and %s, got %s", propName, tostring(min), tostring(max), tostring(value))
      )
    end
  end
  return true
end

--- Validate that a value is of the expected type
---@param value any Value to validate
---@param expectedType string Expected type name
---@param propName string Property name for error messages
---@param moduleName string? Module name for error messages (default: "Element")
---@return boolean True if valid
local function validateType(value, expectedType, propName, moduleName)
  if value == nil then
    return true
  end
  local actualType = type(value)
  if actualType ~= expectedType then
    if ErrorHandler then
      ErrorHandler:error(moduleName or "Element", "VAL_001", {
        property = propName,
        expected = expectedType,
        got = actualType,
      })
    else
      error(string.format("%s must be %s, got %s", propName, expectedType, actualType))
    end
  end
  return true
end

return {
  init = init,
  isNaN = isNaN,
  isInfinity = isInfinity,
  validateNumber = validateNumber,
  sanitizeNumber = sanitizeNumber,
  validateInteger = validateInteger,
  validatePercentage = validatePercentage,
  validateOpacity = validateOpacity,
  validateDegrees = validateDegrees,
  validateCoordinate = validateCoordinate,
  validateDimension = validateDimension,
  validateEnum = validateEnum,
  validateRange = validateRange,
  validateType = validateType,
}
