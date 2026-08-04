--- Utility module for parsing and resolving CSS-like units (px, %, vw, vh)
--- Provides unit parsing, validation, and conversion to pixel values
---@class Units
---@field _Context table? Context module dependency
---@field _ErrorHandler table? ErrorHandler module dependency
---@field _Calc table? Calc module dependency
local Units = {}

--- Initialize Units module with dependencies
---@param deps table Dependencies: { Context = table?, ErrorHandler = table?, Calc = table? }
function Units.init(deps)
  Units._Context = deps.Context
  Units._ErrorHandler = deps.ErrorHandler
  Units._Calc = deps.Calc
end

--- Parse a unit value into numeric value and unit type
--- Supports: px (pixels), % (percentage), vw/vh (viewport), and calc() expressions
---@param value string|number|table The value to parse (e.g., "50px", "10%", "2vw", 100, or calc object)
---@return number|table numericValue The numeric portion of the value or calc object
---@return string unitType The unit type ("px", "%", "vw", "vh", "calc")
function Units.parse(value)
  -- Check if value is a calc expression
  if Units._Calc and Units._Calc.isCalc(value) then
    return value, "calc"
  end

  if type(value) == "number" then
    return value, "px"
  end

  if type(value) ~= "string" and type(value) ~= "table" then
    Units._ErrorHandler:warn("Units", "VAL_001", {
      property = "unit value",
      expected = "string, number, or calc object",
      got = type(value),
    })
    return 0, "px"
  end

  -- Check for unit-only input (e.g., "px", "%", "vw" without a number)
  local validUnits = { px = true, ["%"] = true, vw = true, vh = true }
  if validUnits[value] then
    Units._ErrorHandler:warn("Units", "VAL_005", {
      input = value,
      expected = "number + unit (e.g., '50" .. value .. "')",
    })
    return 0, "px"
  end

  -- Check for invalid format (space between number and unit)
  if value:match("%d%s+%a") then
    Units._ErrorHandler:warn("Units", "VAL_005", {
      input = value,
      issue = "contains space between number and unit",
    })
    return 0, "px"
  end

  -- Match number followed by optional unit
  local numStr, unit = value:match("^([%-]?[%d%.]+)(.*)$")
  if not numStr then
    Units._ErrorHandler:warn("Units", "VAL_005", {
      input = value,
    })
    return 0, "px"
  end

  local num = tonumber(numStr)
  if not num then
    Units._ErrorHandler:warn("Units", "VAL_005", {
      input = value,
      issue = "numeric value cannot be parsed",
    })
    return 0, "px"
  end

  -- Default to pixels if no unit specified
  if unit == "" then
    unit = "px"
  end

  -- validUnits is already defined at the top of the function
  if not validUnits[unit] then
    Units._ErrorHandler:warn("Units", "VAL_005", {
      input = value,
      unit = unit,
      validUnits = "px, %, vw, vh",
    })
    return num, "px"
  end

  return num, unit
end

--- Convert relative units to absolute pixel values
--- Resolves %, vw, vh units based on viewport and parent dimensions, and evaluates calc() expressions
---@param value number|table Numeric value to convert or calc object
---@param unit string Unit type ("px", "%", "vw", "vh", "calc")
---@param viewportWidth number Current viewport width in pixels
---@param viewportHeight number Current viewport height in pixels
---@param parentSize number? Required for percentage units (parent dimension in pixels)
---@return number resolvedValue Resolved pixel value
function Units.resolve(value, unit, viewportWidth, viewportHeight, parentSize)
  if unit == "calc" then
    -- Resolve calc expression
    if Units._Calc then
      return Units._Calc.resolve(value, viewportWidth, viewportHeight, parentSize)
    else
      Units._ErrorHandler:warn("Units", "VAL_006", {
        unit = "calc",
        issue = "Calc module not available",
      })
      return 0
    end
  elseif unit == "px" then
    return value
  elseif unit == "%" then
    if not parentSize then
      Units._ErrorHandler:warn("Units", "LAY_003", {
        unit = "%",
        issue = "parent dimension not available",
      })
      return 0
    end
    return (value / 100) * parentSize
  elseif unit == "vw" then
    return (value / 100) * viewportWidth
  elseif unit == "vh" then
    return (value / 100) * viewportHeight
  else
    Units._ErrorHandler:warn("Units", "VAL_005", {
      unit = unit,
      validUnits = "px, %, vw, vh, calc",
    })
    return 0
  end
end

--- Get current viewport dimensions
--- Uses cached viewport during resize operations, otherwise queries LÖVE graphics
---@return number width Viewport width in pixels
---@return number height Viewport height in pixels
function Units.getViewport()
  -- Return cached viewport if available (only during resize operations)
  if Units._Context._cachedViewport and Units._Context._cachedViewport.width > 0 then
    return Units._Context._cachedViewport.width, Units._Context._cachedViewport.height
  end

  if love.graphics and love.graphics.getDimensions then
    return love.graphics.getDimensions()
  else
    local w, h = love.window.getMode()
    return w, h
  end
end

--- Apply base scale factor to a value based on axis
--- Used for responsive scaling of UI elements
---@param value number The value to scale
---@param axis "x"|"y" The axis to scale on
---@param scaleFactors {x:number, y:number} Scale factors for each axis
---@return number scaledValue The scaled value
function Units.applyBaseScale(value, axis, scaleFactors)
  if axis == "x" then
    return value * scaleFactors.x
  else
    return value * scaleFactors.y
  end
end

--- Resolve spacing properties (margin, padding) to pixel values
--- Supports individual sides (top, right, bottom, left) and shortcuts (vertical, horizontal)
---@param spacingProps table? Spacing properties with top/right/bottom/left/vertical/horizontal
---@param parentWidth number Parent element width in pixels
---@param parentHeight number Parent element height in pixels
---@return table resolvedSpacing Table with top, right, bottom, left in pixels
function Units.resolveSpacing(spacingProps, parentWidth, parentHeight)
  if not spacingProps then
    return { top = 0, right = 0, bottom = 0, left = 0 }
  end

  local viewportWidth, viewportHeight = Units.getViewport()
  local result = {}

  local vertical = spacingProps.vertical
  local horizontal = spacingProps.horizontal

  if vertical then
    if type(vertical) == "string" or (Units._Calc and Units._Calc.isCalc(vertical)) then
      local value, unit = Units.parse(vertical)
      vertical = Units.resolve(value, unit, viewportWidth, viewportHeight, parentHeight)
    end
  end

  if horizontal then
    if type(horizontal) == "string" or (Units._Calc and Units._Calc.isCalc(horizontal)) then
      local value, unit = Units.parse(horizontal)
      horizontal = Units.resolve(value, unit, viewportWidth, viewportHeight, parentWidth)
    end
  end

  for _, side in ipairs({ "top", "right", "bottom", "left" }) do
    local value = spacingProps[side]
    if value then
      if type(value) == "string" or (Units._Calc and Units._Calc.isCalc(value)) then
        local numValue, unit = Units.parse(value)
        local parentSize = (side == "top" or side == "bottom") and parentHeight or parentWidth
        result[side] = Units.resolve(numValue, unit, viewportWidth, viewportHeight, parentSize)
      else
        result[side] = value
      end
    else
      if side == "top" or side == "bottom" then
        result[side] = vertical or 0
      else
        result[side] = horizontal or 0
      end
    end
  end

  return result
end

--- Validate a unit string format
--- Checks if the string can be successfully parsed as a valid unit or calc expression
---@param unitStr string|table The unit string to validate (e.g., "50px", "10%") or calc object
---@return boolean isValid True if the unit string is valid, false otherwise
function Units.isValid(unitStr)
  -- Check if it's a calc expression
  if Units._Calc and Units._Calc.isCalc(unitStr) then
    return true
  end

  if type(unitStr) ~= "string" then
    return false
  end

  -- Check for invalid format (space between number and unit)
  if unitStr:match("%d%s+%a") then
    return false
  end

  -- Match number followed by optional unit
  local numStr, unit = unitStr:match("^([%-]?[%d%.]+)(.*)$")
  if not numStr then
    return false
  end

  -- Check if numeric part is valid
  local num = tonumber(numStr)
  if not num then
    return false
  end

  -- Default to pixels if no unit specified
  if unit == "" then
    unit = "px"
  end

  -- Check if unit is valid
  local validUnits = { px = true, ["%"] = true, vw = true, vh = true }
  return validUnits[unit] == true
end

--- Parse CSS flex shorthand into flexGrow, flexShrink, flexBasis
--- Supports: number, "auto", "none", "grow shrink basis"
---@param flexValue number|string The flex shorthand value
---@return number flexGrow
---@return number flexShrink
---@return string|number flexBasis
function Units.parseFlexShorthand(flexValue)
  -- Single number: flex-grow
  if type(flexValue) == "number" then
    return flexValue, 1, 0
  end

  -- String values
  if type(flexValue) == "string" then
    -- "auto" = 1 1 auto
    if flexValue == "auto" then
      return 1, 1, "auto"
    end

    -- "none" = 0 0 auto
    if flexValue == "none" then
      return 0, 0, "auto"
    end

    -- Parse "grow shrink basis" format
    local parts = {}
    for part in flexValue:gmatch("%S+") do
      table.insert(parts, part)
    end

    local grow = 0
    local shrink = 1
    local basis = "auto"

    if #parts == 1 then
      -- Single value: could be grow (number) or basis (with unit)
      local num = tonumber(parts[1])
      if num then
        grow = num
        basis = 0
      else
        basis = parts[1]
      end
    elseif #parts == 2 then
      -- Two values: grow shrink (both numbers) or grow basis
      local num1 = tonumber(parts[1])
      local num2 = tonumber(parts[2])
      if num1 and num2 then
        grow = num1
        shrink = num2
        basis = 0
      elseif num1 then
        grow = num1
        basis = parts[2]
      end
    elseif #parts >= 3 then
      -- Three values: grow shrink basis
      grow = tonumber(parts[1]) or 0
      shrink = tonumber(parts[2]) or 1
      basis = parts[3]
    end

    return grow, shrink, basis
  end

  -- Default fallback
  return 0, 1, "auto"
end

return Units
