local RoundedRect = {}

--- Generate points for a rounded rectangle
---@param x number
---@param y number
---@param width number
---@param height number
---@param cornerRadius {topLeft:number, topRight:number, bottomLeft:number, bottomRight:number}|number
---@param segments number? -- Number of segments per corner arc (default: 10)
---@return table -- Array of vertices for love.graphics.polygon
function RoundedRect.getPoints(x, y, width, height, cornerRadius, segments)
  segments = segments or 10
  local points = {}

  -- Helper to add arc points
  local function addArc(cx, cy, radius, startAngle, endAngle)
    if radius <= 0 then
      table.insert(points, cx)
      table.insert(points, cy)
      return
    end

    for i = 0, segments do
      local angle = startAngle + (endAngle - startAngle) * (i / segments)
      table.insert(points, cx + math.cos(angle) * radius)
      table.insert(points, cy + math.sin(angle) * radius)
    end
  end

  -- Handle uniform corner radius (number)
  if type(cornerRadius) == "number" then
    cornerRadius = {
      topLeft = cornerRadius,
      topRight = cornerRadius,
      bottomLeft = cornerRadius,
      bottomRight = cornerRadius,
    }
  end

  local r1 = math.min(cornerRadius.topLeft, width / 2, height / 2)
  local r2 = math.min(cornerRadius.topRight, width / 2, height / 2)
  local r3 = math.min(cornerRadius.bottomRight, width / 2, height / 2)
  local r4 = math.min(cornerRadius.bottomLeft, width / 2, height / 2)

  -- Top-right corner
  addArc(x + width - r2, y + r2, r2, -math.pi / 2, 0)

  -- Bottom-right corner
  addArc(x + width - r3, y + height - r3, r3, 0, math.pi / 2)

  -- Bottom-left corner
  addArc(x + r4, y + height - r4, r4, math.pi / 2, math.pi)

  -- Top-left corner
  addArc(x + r1, y + r1, r1, math.pi, math.pi * 1.5)

  return points
end

--- Draw a filled rounded rectangle
---@param mode string -- "fill" or "line"
---@param x number
---@param y number
---@param width number
---@param height number
---@param cornerRadius {topLeft:number, topRight:number, bottomLeft:number, bottomRight:number}|number|nil
function RoundedRect.draw(mode, x, y, width, height, cornerRadius)
  -- OPTIMIZATION: Handle nil cornerRadius (no rounding)
  if not cornerRadius then
    love.graphics.rectangle(mode, x, y, width, height)
    return
  end

  -- Handle uniform corner radius (number)
  if type(cornerRadius) == "number" then
    if cornerRadius <= 0 then
      love.graphics.rectangle(mode, x, y, width, height)
      return
    end
    -- Convert to table format for processing
    cornerRadius = {
      topLeft = cornerRadius,
      topRight = cornerRadius,
      bottomLeft = cornerRadius,
      bottomRight = cornerRadius,
    }
  end

  -- Check if any corners are rounded
  local hasRoundedCorners = cornerRadius.topLeft > 0
    or cornerRadius.topRight > 0
    or cornerRadius.bottomLeft > 0
    or cornerRadius.bottomRight > 0

  if not hasRoundedCorners then
    -- No rounded corners, use regular rectangle
    love.graphics.rectangle(mode, x, y, width, height)
    return
  end

  local points = RoundedRect.getPoints(x, y, width, height, cornerRadius)

  if mode == "fill" then
    love.graphics.polygon("fill", points)
  else
    -- For line mode, draw the outline
    love.graphics.polygon("line", points)
  end
end

--- Create a stencil function for rounded rectangle clipping
---@param x number
---@param y number
---@param width number
---@param height number
---@param cornerRadius {topLeft:number, topRight:number, bottomLeft:number, bottomRight:number}|number|nil
---@return function
function RoundedRect.stencilFunction(x, y, width, height, cornerRadius)
  return function()
    RoundedRect.draw("fill", x, y, width, height, cornerRadius)
  end
end

return RoundedRect
