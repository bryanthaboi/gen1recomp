---@class Color
local Color = {}
Color.__index = Color

--- Initialize module with shared dependencies
---@param deps table Dependencies {ErrorHandler}
function Color.init(deps)
  if type(deps) == "table" then
    Color._ErrorHandler = deps.ErrorHandler
  end
end

--- Build type-safe color objects with automatic validation and clamping
--- Use this to avoid invalid color values and ensure consistent LÖVE-compatible colors (0-1 range)
---@param r number? Red component (0-1), defaults to 0
---@param g number? Green component (0-1), defaults to 0
---@param b number? Blue component (0-1), defaults to 0
---@param a number? Alpha component (0-1), defaults to 1
---@return Color color The new color instance
function Color.new(r, g, b, a)
  -- Sanitize and clamp color components
  local _, sanitizedR = Color.validateColorChannel(r or 0, 1)
  local _, sanitizedG = Color.validateColorChannel(g or 0, 1)
  local _, sanitizedB = Color.validateColorChannel(b or 0, 1)
  local _, sanitizedA = Color.validateColorChannel(a or 1, 1)

  -- FFI structs don't support metatables/methods without wrapping
  -- The wrapping overhead negates the FFI benefits
  local self = setmetatable({}, Color)
  self.r = sanitizedR or 0
  self.g = sanitizedG or 0
  self.b = sanitizedB or 0
  self.a = sanitizedA or 1
  return self
end

--- Extract individual color channels for use with love.graphics.setColor()
--- Use this to pass colors to LÖVE's rendering functions
---@return number r Red component (0-1)
---@return number g Green component (0-1)
---@return number b Blue component (0-1)
---@return number a Alpha component (0-1)
function Color:toRGBA()
  return self.r, self.g, self.b, self.a
end

--- Parse CSS-style hex colors into Color objects for designer-friendly workflows
--- Use this to work with colors from design tools that export hex values
---@param hexWithTag string Hex color string (e.g. "#RRGGBB" or "#RRGGBBAA")
---@return Color color The parsed color (returns white on error with warning)
function Color.fromHex(hexWithTag)
  -- Validate input type
  if type(hexWithTag) ~= "string" then
    Color._ErrorHandler:warn("Color", "VAL_004", {
      input = tostring(hexWithTag),
      issue = "not a string",
      fallback = "white (#FFFFFF)",
    })
    return Color.new(1, 1, 1, 1)
  end

  local hex = hexWithTag:gsub("#", "")
  if #hex == 6 then
    local r = tonumber("0x" .. hex:sub(1, 2))
    local g = tonumber("0x" .. hex:sub(3, 4))
    local b = tonumber("0x" .. hex:sub(5, 6))
    if not r or not g or not b then
      Color._ErrorHandler:warn("Color", "VAL_004", {
        input = hexWithTag,
        issue = "invalid hex digits",
        fallback = "white (#FFFFFF)",
      })
      return Color.new(1, 1, 1, 1) -- Return white as fallback
    end
    return Color.new(r / 255, g / 255, b / 255, 1)
  elseif #hex == 8 then
    local r = tonumber("0x" .. hex:sub(1, 2))
    local g = tonumber("0x" .. hex:sub(3, 4))
    local b = tonumber("0x" .. hex:sub(5, 6))
    local a = tonumber("0x" .. hex:sub(7, 8))
    if not r or not g or not b or not a then
      Color._ErrorHandler:warn("Color", "VAL_004", {
        input = hexWithTag,
        issue = "invalid hex digits",
        fallback = "white (#FFFFFFFF)",
      })
      return Color.new(1, 1, 1, 1) -- Return white as fallback
    end
    return Color.new(r / 255, g / 255, b / 255, a / 255)
  else
    Color._ErrorHandler:warn("Color", "VAL_004", {
      input = hexWithTag,
      expected = "#RRGGBB or #RRGGBBAA",
      hexLength = #hex,
      fallback = "white (#FFFFFF)",
    })
    return Color.new(1, 1, 1, 1) -- Return white as fallback
  end
end

--- Verify and sanitize individual color components to prevent rendering errors
--- Use this to safely process user input or external color data
---@param value any Value to validate
---@param max number? Maximum value (255 for 0-255 range, 1 for 0-1 range), defaults to 1
---@return boolean valid True if valid
---@return number? clamped Clamped value in 0-1 range, nil if invalid
function Color.validateColorChannel(value, max)
  max = max or 1

  if type(value) ~= "number" then
    return false, nil
  end

  -- Check for NaN
  if value ~= value then
    return false, nil
  end

  -- Check for Infinity
  if value == math.huge or value == -math.huge then
    return false, nil
  end

  -- Normalize to 0-1 range
  local normalized = value
  if max == 255 then
    normalized = value / 255
  end

  -- Clamp to valid range
  normalized = math.max(0, math.min(1, normalized))

  return true, normalized
end

--- Validate hex color format
---@param hex string Hex color string (with or without #)
---@return boolean valid True if valid format
---@return string? error Error message if invalid, nil if valid
function Color.validateHexColor(hex)
  if type(hex) ~= "string" then
    return false, "Hex color must be a string"
  end

  -- Remove # prefix
  local cleanHex = hex:gsub("^#", "")

  -- Check length (3, 6, or 8 characters)
  if #cleanHex ~= 3 and #cleanHex ~= 6 and #cleanHex ~= 8 then
    return false, string.format("Invalid hex length: %d. Expected 3, 6, or 8 characters", #cleanHex)
  end

  -- Check for valid hex characters
  if not cleanHex:match("^[0-9A-Fa-f]+$") then
    return false, "Invalid hex characters. Use only 0-9, A-F"
  end

  return true, nil
end

--- Validate RGB/RGBA color values
---@param r number Red component
---@param g number Green component
---@param b number Blue component
---@param a number? Alpha component (optional, defaults to max)
---@param max number? Maximum value (255 or 1), defaults to 1
---@return boolean valid True if valid
---@return string? error Error message if invalid, nil if valid
function Color.validateRGBColor(r, g, b, a, max)
  max = max or 1
  a = a or max

  local rValid = Color.validateColorChannel(r, max)
  local gValid = Color.validateColorChannel(g, max)
  local bValid = Color.validateColorChannel(b, max)
  local aValid = Color.validateColorChannel(a, max)

  if not rValid then
    return false, string.format("Invalid red channel: %s", tostring(r))
  end
  if not gValid then
    return false, string.format("Invalid green channel: %s", tostring(g))
  end
  if not bValid then
    return false, string.format("Invalid blue channel: %s", tostring(b))
  end
  if not aValid then
    return false, string.format("Invalid alpha channel: %s", tostring(a))
  end

  return true, nil
end

--- Check if a value is a valid color format
---@param value any Value to check
---@return string? format Format type ("hex", "named", "table"), nil if invalid
function Color.isValidColorFormat(value)
  local valueType = type(value)

  -- Check for hex string
  if valueType == "string" then
    if value:match("^#?[0-9A-Fa-f]+$") then
      local valid = Color.validateHexColor(value)
      if valid then
        return "hex"
      end
    end

    return nil
  end

  -- Check for table format
  if valueType == "table" then
    -- Check for Color instance
    if getmetatable(value) == Color then
      return "table"
    end

    -- Check for array format {r, g, b, a}
    if value[1] and value[2] and value[3] then
      local valid = Color.validateRGBColor(value[1], value[2], value[3], value[4])
      if valid then
        return "table"
      end
    end

    -- Check for named format {r=, g=, b=, a=}
    if value.r and value.g and value.b then
      local valid = Color.validateRGBColor(value.r, value.g, value.b, value.a)
      if valid then
        return "table"
      end
    end

    return nil
  end

  return nil
end

--- Convert any color format to a valid Color object with graceful fallbacks
--- Use this to robustly handle colors from any source without crashes
---@param value any Color value to sanitize (hex, named, table, or Color instance)
---@param default Color? Default color if invalid (defaults to black)
---@return Color color Sanitized color instance (guaranteed non-nil)
function Color.sanitizeColor(value, default)
  default = default or Color.new(0, 0, 0, 1)

  local format = Color.isValidColorFormat(value)

  if not format then
    return default
  end

  -- Handle hex format
  if format == "hex" then
    local cleanHex = value:gsub("^#", "")

    -- Expand 3-digit hex to 6-digit
    if #cleanHex == 3 then
      cleanHex = cleanHex:gsub("(.)", "%1%1")
    end

    -- Try to parse
    local success, result = pcall(Color.fromHex, "#" .. cleanHex)
    if success then
      return result
    else
      return default
    end
  end

  if format == "table" then
    -- Color instance
    if getmetatable(value) == Color then
      return value
    end

    -- Array format
    if value[1] then
      local _, r = Color.validateColorChannel(value[1], 1)
      local _, g = Color.validateColorChannel(value[2], 1)
      local _, b = Color.validateColorChannel(value[3], 1)
      local _, a = Color.validateColorChannel(value[4] or 1, 1)

      if r and g and b and a then
        return Color.new(r, g, b, a)
      end
    end

    -- Named format
    if value.r then
      local _, r = Color.validateColorChannel(value.r, 1)
      local _, g = Color.validateColorChannel(value.g, 1)
      local _, b = Color.validateColorChannel(value.b, 1)
      local _, a = Color.validateColorChannel(value.a or 1, 1)

      if r and g and b and a then
        return Color.new(r, g, b, a)
      end
    end
  end

  return default
end

--- Universally convert any color format (hex, named, table) into a Color object
--- Use this as your main color input handler to accept flexible color specifications
---@param value any Color value (hex string, named color, table, or Color instance)
---@return Color color Parsed color instance (defaults to black on error)
function Color.parse(value)
  return Color.sanitizeColor(value, Color.new(0, 0, 0, 1))
end

--- Smoothly transition between two colors for animations and gradients
--- Use this to create color-based animations without manual channel calculations
---@param colorA Color Starting color
---@param colorB Color Ending color
---@param t number Interpolation factor (0-1)
---@return Color color Interpolated color
function Color.lerp(colorA, colorB, t)
  -- Sanitize inputs
  if type(colorA) ~= "table" or getmetatable(colorA) ~= Color then
    colorA = Color.new(0, 0, 0, 1)
  end
  if type(colorB) ~= "table" or getmetatable(colorB) ~= Color then
    colorB = Color.new(0, 0, 0, 1)
  end
  if type(t) ~= "number" or t ~= t or t == math.huge or t == -math.huge then
    t = 0
  end

  -- Clamp t to 0-1 range
  t = math.max(0, math.min(1, t))

  -- Linear interpolation for each channel
  local oneMinusT = 1 - t
  local r = colorA.r * oneMinusT + colorB.r * t
  local g = colorA.g * oneMinusT + colorB.g * t
  local b = colorA.b * oneMinusT + colorB.b * t
  local a = colorA.a * oneMinusT + colorB.a * t

  return Color.new(r, g, b, a)
end

return Color
