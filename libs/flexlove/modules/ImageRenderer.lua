---@class ImageRenderer
local ImageRenderer = {}

-- ErrorHandler and utils will be injected via init
local ErrorHandler = nil
local utils = nil

--- Initialize ImageRenderer with dependencies
---@param deps table Dependencies table with ErrorHandler and utils
function ImageRenderer.init(deps)
  if deps and deps.ErrorHandler then
    ErrorHandler = deps.ErrorHandler
  end
  if deps and deps.utils then
    utils = deps.utils
  end
end

--- Calculate rendering parameters for object-fit modes
--- Returns source and destination rectangles for rendering
---@param imageWidth number -- Natural width of the image
---@param imageHeight number -- Natural height of the image
---@param boundsWidth number -- Width of the bounds to fit within
---@param boundsHeight number -- Height of the bounds to fit within
---@param fitMode string? -- One of: "fill", "contain", "cover", "scale-down", "none" (default: "fill")
---@param objectPosition string? -- Position like "center center", "top left", "50% 50%" (default: "center center")
---@return {sx: number, sy: number, sw: number, sh: number, dx: number, dy: number, dw: number, dh: number, scaleX: number, scaleY: number}
function ImageRenderer.calculateFit(imageWidth, imageHeight, boundsWidth, boundsHeight, fitMode, objectPosition)
  fitMode = fitMode or "fill"
  objectPosition = objectPosition or "center center"

  if imageWidth <= 0 or imageHeight <= 0 or boundsWidth <= 0 or boundsHeight <= 0 then
    ErrorHandler:error("ImageRenderer", "VAL_002", {
      imageWidth = imageWidth,
      imageHeight = imageHeight,
      boundsWidth = boundsWidth,
      boundsHeight = boundsHeight,
    })
  end

  local result = {
    sx = 0, -- Source X
    sy = 0, -- Source Y
    sw = imageWidth, -- Source width
    sh = imageHeight, -- Source height
    dx = 0, -- Destination X
    dy = 0, -- Destination Y
    dw = boundsWidth, -- Destination width
    dh = boundsHeight, -- Destination height
    scaleX = 1, -- Scale factor X
    scaleY = 1, -- Scale factor Y
  }

  if fitMode == "fill" then
    -- Stretch to fill bounds (may distort)
    result.scaleX = boundsWidth / imageWidth
    result.scaleY = boundsHeight / imageHeight
    result.dw = boundsWidth
    result.dh = boundsHeight
  elseif fitMode == "contain" then
    -- Scale to fit within bounds (preserves aspect ratio)
    local scale = math.min(boundsWidth / imageWidth, boundsHeight / imageHeight)
    result.scaleX = scale
    result.scaleY = scale
    result.dw = imageWidth * scale
    result.dh = imageHeight * scale

    -- Apply object-position for letterbox alignment
    local posX, posY = ImageRenderer._parsePosition(objectPosition)
    result.dx = (boundsWidth - result.dw) * posX
    result.dy = (boundsHeight - result.dh) * posY
  elseif fitMode == "cover" then
    -- Scale to cover bounds (preserves aspect ratio, may crop)
    local scale = math.max(boundsWidth / imageWidth, boundsHeight / imageHeight)
    result.scaleX = scale
    result.scaleY = scale

    local scaledWidth = imageWidth * scale
    local scaledHeight = imageHeight * scale

    -- Apply object-position for crop alignment
    local posX, posY = ImageRenderer._parsePosition(objectPosition)

    -- Calculate which part of the scaled image to show
    local cropX = (scaledWidth - boundsWidth) * posX
    local cropY = (scaledHeight - boundsHeight) * posY

    -- Convert back to source coordinates
    result.sx = cropX / scale
    result.sy = cropY / scale
    result.sw = boundsWidth / scale
    result.sh = boundsHeight / scale

    result.dx = 0
    result.dy = 0
    result.dw = boundsWidth
    result.dh = boundsHeight
  elseif fitMode == "none" then
    -- Use natural size (no scaling)
    result.scaleX = 1
    result.scaleY = 1
    result.dw = imageWidth
    result.dh = imageHeight

    -- Apply object-position
    local posX, posY = ImageRenderer._parsePosition(objectPosition)
    result.dx = (boundsWidth - imageWidth) * posX
    result.dy = (boundsHeight - imageHeight) * posY
  elseif fitMode == "scale-down" then
    -- Use none or contain, whichever is smaller
    if imageWidth <= boundsWidth and imageHeight <= boundsHeight then
      -- Image fits naturally, use "none"
      return ImageRenderer.calculateFit(imageWidth, imageHeight, boundsWidth, boundsHeight, "none", objectPosition)
    else
      -- Image too large, use "contain"
      return ImageRenderer.calculateFit(imageWidth, imageHeight, boundsWidth, boundsHeight, "contain", objectPosition)
    end
  else
    ErrorHandler:warn("ImageRenderer", "VAL_007", {
      fitMode = fitMode,
      fallback = "fill",
    })
    -- Use 'fill' as fallback
    return ImageRenderer.calculateFit(imageWidth, imageHeight, boundsWidth, boundsHeight, "fill", objectPosition)
  end

  return result
end

--- Parse object-position string into normalized coordinates (0-1)
--- Supports keywords (center, top, bottom, left, right) and percentages
---@param position string -- Position string like "center center", "top left", "50% 50%"
---@return number, number -- Normalized X and Y positions (0-1)
function ImageRenderer._parsePosition(position)
  if not position or type(position) ~= "string" then
    return 0.5, 0.5 -- Default to center
  end

  -- Split into X and Y components
  local parts = {}
  for part in position:gmatch("%S+") do
    table.insert(parts, part:lower())
  end

  -- If only one value, use it for both axes (with special handling)
  if #parts == 1 then
    local val = parts[1]
    if val == "left" or val == "right" then
      parts = { val, "center" }
    elseif val == "top" or val == "bottom" then
      parts = { "center", val }
    else
      parts = { val, val }
    end
  elseif #parts == 0 then
    return 0.5, 0.5 -- Default to center
  end

  local function parseValue(val)
    -- Handle keywords
    if val == "center" then
      return 0.5
    elseif val == "left" or val == "top" then
      return 0
    elseif val == "right" or val == "bottom" then
      return 1
    end

    -- Handle percentages
    local percent = val:match("^([%d%.]+)%%$")
    if percent then
      return tonumber(percent) / 100
    end

    -- Handle plain numbers (treat as percentage)
    local num = tonumber(val)
    if num then
      return num / 100
    end

    -- Invalid value, default to center
    return 0.5
  end

  local x = parseValue(parts[1])
  local y = parseValue(parts[2] or parts[1])

  -- Clamp to 0-1 range
  x = math.max(0, math.min(1, x))
  y = math.max(0, math.min(1, y))

  return x, y
end

--- Draw an image with specified object-fit mode
---@param image love.Image -- Image to draw
---@param x number -- X position of bounds
---@param y number -- Y position of bounds
---@param width number -- Width of bounds
---@param height number -- Height of bounds
---@param fitMode string? -- Object-fit mode (default: "fill")
---@param objectPosition string? -- Object-position (default: "center center")
---@param opacity number? -- Opacity 0-1 (default: 1)
---@param tintColor Color? -- Color to tint the image (default: white/no tint)
function ImageRenderer.draw(image, x, y, width, height, fitMode, objectPosition, opacity, tintColor)
  if not image then
    return -- Nothing to draw
  end

  opacity = opacity or 1
  fitMode = fitMode or "fill"
  objectPosition = objectPosition or "center center"

  local imgWidth, imgHeight = image:getDimensions()
  local params = ImageRenderer.calculateFit(imgWidth, imgHeight, width, height, fitMode, objectPosition)

  -- Save current color
  local r, g, b, a = love.graphics.getColor()

  -- Apply opacity and tint
  if tintColor then
    love.graphics.setColor(tintColor.r, tintColor.g, tintColor.b, tintColor.a * opacity)
  else
    love.graphics.setColor(1, 1, 1, opacity)
  end

  -- Draw image
  if params.sx ~= 0 or params.sy ~= 0 or params.sw ~= imgWidth or params.sh ~= imgHeight then
    -- Need to use a quad for cropping
    local quad = love.graphics.newQuad(params.sx, params.sy, params.sw, params.sh, imgWidth, imgHeight)
    love.graphics.draw(image, quad, x + params.dx, y + params.dy, 0, params.dw / params.sw, params.dh / params.sh)
  else
    -- Simple draw with scaling
    love.graphics.draw(image, x + params.dx, y + params.dy, 0, params.scaleX, params.scaleY)
  end

  -- Restore color
  love.graphics.setColor(r, g, b, a)
end

--- Draw an image with tiling/repeat mode
---@param image love.Image -- Image to draw
---@param x number -- X position of bounds
---@param y number -- Y position of bounds
---@param width number -- Width of bounds
---@param height number -- Height of bounds
---@param repeatMode string? -- Repeat mode: "repeat", "repeat-x", "repeat-y", "no-repeat", "space", "round" (default: "no-repeat")
---@param opacity number? -- Opacity 0-1 (default: 1)
---@param tintColor Color? -- Color to tint the image (default: white/no tint)
function ImageRenderer.drawTiled(image, x, y, width, height, repeatMode, opacity, tintColor)
  if not image then
    return -- Nothing to draw
  end

  opacity = opacity or 1
  repeatMode = repeatMode or "no-repeat"

  local imgWidth, imgHeight = image:getDimensions()

  -- Save current color
  local r, g, b, a = love.graphics.getColor()

  -- Apply opacity and tint
  if tintColor then
    love.graphics.setColor(tintColor.r, tintColor.g, tintColor.b, tintColor.a * opacity)
  else
    love.graphics.setColor(1, 1, 1, opacity)
  end

  if repeatMode == "no-repeat" then
    -- Just draw once, no tiling
    love.graphics.draw(image, x, y)
  elseif repeatMode == "repeat" then
    -- Tile in both directions
    local tilesX = math.ceil(width / imgWidth)
    local tilesY = math.ceil(height / imgHeight)

    for tileY = 0, tilesY - 1 do
      for tileX = 0, tilesX - 1 do
        local drawX = x + (tileX * imgWidth)
        local drawY = y + (tileY * imgHeight)

        -- Calculate how much of the tile to draw (for partial tiles at edges)
        local drawWidth = math.min(imgWidth, width - (tileX * imgWidth))
        local drawHeight = math.min(imgHeight, height - (tileY * imgHeight))

        if drawWidth < imgWidth or drawHeight < imgHeight then
          -- Use quad for partial tile
          local quad = love.graphics.newQuad(0, 0, drawWidth, drawHeight, imgWidth, imgHeight)
          love.graphics.draw(image, quad, drawX, drawY)
        else
          -- Draw full tile
          love.graphics.draw(image, drawX, drawY)
        end
      end
    end
  elseif repeatMode == "repeat-x" then
    -- Tile horizontally only
    local tilesX = math.ceil(width / imgWidth)

    for tileX = 0, tilesX - 1 do
      local drawX = x + (tileX * imgWidth)
      local drawWidth = math.min(imgWidth, width - (tileX * imgWidth))

      if drawWidth < imgWidth then
        -- Use quad for partial tile
        local quad = love.graphics.newQuad(0, 0, drawWidth, imgHeight, imgWidth, imgHeight)
        love.graphics.draw(image, quad, drawX, y)
      else
        -- Draw full tile
        love.graphics.draw(image, drawX, y)
      end
    end
  elseif repeatMode == "repeat-y" then
    -- Tile vertically only
    local tilesY = math.ceil(height / imgHeight)

    for tileY = 0, tilesY - 1 do
      local drawY = y + (tileY * imgHeight)
      local drawHeight = math.min(imgHeight, height - (tileY * imgHeight))

      if drawHeight < imgHeight then
        -- Use quad for partial tile
        local quad = love.graphics.newQuad(0, 0, imgWidth, drawHeight, imgWidth, imgHeight)
        love.graphics.draw(image, quad, x, drawY)
      else
        -- Draw full tile
        love.graphics.draw(image, x, drawY)
      end
    end
  elseif repeatMode == "space" then
    -- Distribute tiles with even spacing
    local tilesX = math.floor(width / imgWidth)
    local tilesY = math.floor(height / imgHeight)

    if tilesX < 1 then
      tilesX = 1
    end
    if tilesY < 1 then
      tilesY = 1
    end

    local spaceX = tilesX > 1 and (width - (tilesX * imgWidth)) / (tilesX - 1) or 0
    local spaceY = tilesY > 1 and (height - (tilesY * imgHeight)) / (tilesY - 1) or 0

    for tileY = 0, tilesY - 1 do
      for tileX = 0, tilesX - 1 do
        local drawX = x + (tileX * (imgWidth + spaceX))
        local drawY = y + (tileY * (imgHeight + spaceY))
        love.graphics.draw(image, drawX, drawY)
      end
    end
  elseif repeatMode == "round" then
    -- Scale tiles to fit bounds exactly
    local tilesX = math.max(1, utils.round(width / imgWidth))
    local tilesY = math.max(1, utils.round(height / imgHeight))

    local scaleX = width / (tilesX * imgWidth)
    local scaleY = height / (tilesY * imgHeight)

    for tileY = 0, tilesY - 1 do
      for tileX = 0, tilesX - 1 do
        local drawX = x + (tileX * imgWidth * scaleX)
        local drawY = y + (tileY * imgHeight * scaleY)
        love.graphics.draw(image, drawX, drawY, 0, scaleX, scaleY)
      end
    end
  else
    ErrorHandler:warn("ImageRenderer", "VAL_007", {
      repeatMode = repeatMode,
      fallback = "no-repeat",
    })
    love.graphics.draw(image, x, y)
  end

  -- Restore color
  love.graphics.setColor(r, g, b, a)
end

return ImageRenderer
