-- ====================
-- ImageScaler
-- ====================

local ImageScaler = {}

-- ErrorHandler will be injected via init
local ErrorHandler = nil

--- Initialize ImageScaler with dependencies
---@param deps table Dependencies table with ErrorHandler
function ImageScaler.init(deps)
  if deps and deps.ErrorHandler then
    ErrorHandler = deps.ErrorHandler
  end
end

--- Scale an ImageData region using nearest-neighbor sampling
--- Produces sharp, pixelated scaling - ideal for pixel art
---@param sourceImageData love.ImageData -- Source image data
---@param srcX number -- Source region X (0-based)
---@param srcY number -- Source region Y (0-based)
---@param srcW number -- Source region width
---@param srcH number -- Source region height
---@param destW number -- Destination width
---@param destH number -- Destination height
---@return love.ImageData -- Scaled image data
function ImageScaler.scaleNearest(sourceImageData, srcX, srcY, srcW, srcH, destW, destH)
  if not sourceImageData then
    ErrorHandler:error("ImageScaler", "VAL_001", {
      parameter = "sourceImageData",
    })
  end

  if srcW <= 0 or srcH <= 0 or destW <= 0 or destH <= 0 then
    ErrorHandler:warn("ImageScaler", "VAL_002", {
      srcW = srcW,
      srcH = srcH,
      destW = destW,
      destH = destH,
      fallback = "1x1 transparent image",
    })
    -- Return a minimal 1x1 transparent image as fallback
    local fallbackImageData = love.image.newImageData(1, 1)
    fallbackImageData:setPixel(0, 0, 0, 0, 0, 0)
    return fallbackImageData
  end

  -- Create destination ImageData
  local destImageData = love.image.newImageData(destW, destH)

  -- Calculate scale ratios (cached outside loops for performance)
  local scaleX = srcW / destW
  local scaleY = srcH / destH

  -- Nearest-neighbor sampling
  for destY = 0, destH - 1 do
    for destX = 0, destW - 1 do
      -- Calculate source pixel coordinates using floor (nearest-neighbor)
      local srcPixelX = math.floor(destX * scaleX) + srcX
      local srcPixelY = math.floor(destY * scaleY) + srcY

      -- Clamp to source bounds (safety check)
      srcPixelX = math.min(srcPixelX, srcX + srcW - 1)
      srcPixelY = math.min(srcPixelY, srcY + srcH - 1)

      -- Sample source pixel
      local r, g, b, a = sourceImageData:getPixel(srcPixelX, srcPixelY)

      -- Write to destination
      destImageData:setPixel(destX, destY, r, g, b, a)
    end
  end

  return destImageData
end

--- Linear interpolation helper
--- Blends between two values based on interpolation factor
---@param a number -- Start value
---@param b number -- End value
---@param t number -- Interpolation factor [0, 1]
---@return number -- Interpolated value
local function lerp(a, b, t)
  return a + (b - a) * t
end

--- Scale an ImageData region using bilinear interpolation
--- Produces smooth, filtered scaling - ideal for high-quality upscaling
---@param sourceImageData love.ImageData -- Source image data
---@param srcX number -- Source region X (0-based)
---@param srcY number -- Source region Y (0-based)
---@param srcW number -- Source region width
---@param srcH number -- Source region height
---@param destW number -- Destination width
---@param destH number -- Destination height
---@return love.ImageData -- Scaled image data
function ImageScaler.scaleBilinear(sourceImageData, srcX, srcY, srcW, srcH, destW, destH)
  if not sourceImageData then
    ErrorHandler:error("ImageScaler", "VAL_001", {
      parameter = "sourceImageData",
    })
  end

  if srcW <= 0 or srcH <= 0 or destW <= 0 or destH <= 0 then
    ErrorHandler:warn("ImageScaler", "VAL_002", {
      srcW = srcW,
      srcH = srcH,
      destW = destW,
      destH = destH,
      fallback = "1x1 transparent image",
    })
    -- Return a minimal 1x1 transparent image as fallback
    local fallbackImageData = love.image.newImageData(1, 1)
    fallbackImageData:setPixel(0, 0, 0, 0, 0, 0)
    return fallbackImageData
  end

  -- Create destination ImageData
  local destImageData = love.image.newImageData(destW, destH)

  -- Calculate scale ratios
  local scaleX = srcW / destW
  local scaleY = srcH / destH

  -- Bilinear interpolation
  for destY = 0, destH - 1 do
    for destX = 0, destW - 1 do
      -- Calculate fractional source position
      local srcXf = destX * scaleX
      local srcYf = destY * scaleY

      -- Get integer coordinates for 2x2 sampling grid
      local x0 = math.floor(srcXf)
      local y0 = math.floor(srcYf)
      local x1 = math.min(x0 + 1, srcW - 1)
      local y1 = math.min(y0 + 1, srcH - 1)

      -- Get fractional parts for interpolation
      local fx = srcXf - x0
      local fy = srcYf - y0

      -- Sample 4 neighboring pixels (with source offset)
      local r00, g00, b00, a00 = sourceImageData:getPixel(srcX + x0, srcY + y0)
      local r10, g10, b10, a10 = sourceImageData:getPixel(srcX + x1, srcY + y0)
      local r01, g01, b01, a01 = sourceImageData:getPixel(srcX + x0, srcY + y1)
      local r11, g11, b11, a11 = sourceImageData:getPixel(srcX + x1, srcY + y1)

      -- Interpolate horizontally (top and bottom rows)
      local rTop = lerp(r00, r10, fx)
      local gTop = lerp(g00, g10, fx)
      local bTop = lerp(b00, b10, fx)
      local aTop = lerp(a00, a10, fx)

      local rBottom = lerp(r01, r11, fx)
      local gBottom = lerp(g01, g11, fx)
      local bBottom = lerp(b01, b11, fx)
      local aBottom = lerp(a01, a11, fx)

      -- Interpolate vertically (final result)
      local r = lerp(rTop, rBottom, fy)
      local g = lerp(gTop, gBottom, fy)
      local b = lerp(bTop, bBottom, fy)
      local a = lerp(aTop, aBottom, fy)

      -- Write to destination
      destImageData:setPixel(destX, destY, r, g, b, a)
    end
  end

  return destImageData
end

return ImageScaler
