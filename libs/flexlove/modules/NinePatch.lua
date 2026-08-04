local modulePath = (...):match("(.-)[^%.]+$")
local ImageScaler = require(modulePath .. "ImageScaler")

local NinePatch = {}

-- ErrorHandler will be injected via init
local ErrorHandler = nil

--- Initialize NinePatch with dependencies
---@param deps table Dependencies table with ErrorHandler
function NinePatch.init(deps)
  if deps and deps.ErrorHandler then
    ErrorHandler = deps.ErrorHandler
  end
  -- Also initialize ImageScaler since it's a dependency
  if ImageScaler.init then
    ImageScaler.init(deps)
  end
end

--- Draw a 9-patch component using Android-style rendering
--- Corners are scaled by scaleCorners multiplier, edges stretch in one dimension only
---@param component ThemeComponent
---@param atlas love.Image
---@param x number -- X position (top-left corner)
---@param y number -- Y position (top-left corner)
---@param width number -- Total width (border-box)
---@param height number -- Total height (border-box)
---@param opacity number?
---@param elementScaleCorners number? -- Element-level override for scaleCorners (scale multiplier)
---@param elementScalingAlgorithm "nearest"|"bilinear"? -- Element-level override for scalingAlgorithm
function NinePatch.draw(component, atlas, x, y, width, height, opacity, elementScaleCorners, elementScalingAlgorithm)
  if not component or not atlas then
    return
  end

  opacity = opacity or 1
  love.graphics.setColor(1, 1, 1, opacity)

  local regions = component.regions

  -- Extract border dimensions from regions (in pixels)
  local left = regions.topLeft.w
  local right = regions.topRight.w
  local top = regions.topLeft.h
  local bottom = regions.bottomLeft.h
  local centerW = regions.middleCenter.w
  local centerH = regions.middleCenter.h

  -- Calculate content area (space remaining after borders)
  local contentWidth = width - left - right
  local contentHeight = height - top - bottom

  -- Clamp to prevent negative dimensions
  contentWidth = math.max(0, contentWidth)
  contentHeight = math.max(0, contentHeight)

  -- Calculate stretch scales for edges and center
  local scaleX = contentWidth / centerW
  local scaleY = contentHeight / centerH

  -- Create quads for each region
  local atlasWidth, atlasHeight = atlas:getDimensions()

  local function makeQuad(region)
    return love.graphics.newQuad(region.x, region.y, region.w, region.h, atlasWidth, atlasHeight)
  end

  -- Get corner scale multiplier
  -- Priority: element-level override > component setting > default (nil = no scaling)
  local scaleCorners = elementScaleCorners
  if scaleCorners == nil then
    scaleCorners = component.scaleCorners
  end

  -- Priority: element-level override > component setting > default ("bilinear")
  local scalingAlgorithm = elementScalingAlgorithm
  if scalingAlgorithm == nil then
    scalingAlgorithm = component.scalingAlgorithm or "bilinear"
  end

  if scaleCorners and type(scaleCorners) == "number" and scaleCorners > 0 then
    -- Initialize cache if needed
    if not component._scaledRegionCache then
      component._scaledRegionCache = {}
    end

    -- Use the numeric scale multiplier directly
    local scaleFactor = scaleCorners

    -- Helper to get or create scaled region
    local function getScaledRegion(regionName, region, targetWidth, targetHeight)
      local cacheKey = string.format("%s_%.2f_%s", regionName, scaleFactor, scalingAlgorithm)

      if component._scaledRegionCache[cacheKey] then
        return component._scaledRegionCache[cacheKey]
      end

      -- Get ImageData from component (stored during theme loading)
      local atlasData = component._loadedAtlasData
      if not atlasData then
        ErrorHandler.error(
          "NinePatch",
          "REN_007",
          "No ImageData available for atlas. Image must be loaded with safeLoadImage.",
          {
            componentType = component.type,
          }
        )
      end

      local scaledData

      if scalingAlgorithm == "nearest" then
        scaledData =
          ImageScaler.scaleNearest(atlasData, region.x, region.y, region.w, region.h, targetWidth, targetHeight)
      else
        scaledData =
          ImageScaler.scaleBilinear(atlasData, region.x, region.y, region.w, region.h, targetWidth, targetHeight)
      end

      -- Convert to image and cache
      local scaledImage = love.graphics.newImage(scaledData)
      component._scaledRegionCache[cacheKey] = scaledImage

      return scaledImage
    end

    -- Calculate scaled dimensions for corners
    local scaledLeft = math.floor(left * scaleFactor + 0.5)
    local scaledRight = math.floor(right * scaleFactor + 0.5)
    local scaledTop = math.floor(top * scaleFactor + 0.5)
    local scaledBottom = math.floor(bottom * scaleFactor + 0.5)

    -- CORNERS (scaled using algorithm)
    local topLeftScaled = getScaledRegion("topLeft", regions.topLeft, scaledLeft, scaledTop)
    local topRightScaled = getScaledRegion("topRight", regions.topRight, scaledRight, scaledTop)
    local bottomLeftScaled = getScaledRegion("bottomLeft", regions.bottomLeft, scaledLeft, scaledBottom)
    local bottomRightScaled = getScaledRegion("bottomRight", regions.bottomRight, scaledRight, scaledBottom)

    love.graphics.draw(topLeftScaled, x, y)
    love.graphics.draw(topRightScaled, x + width - scaledRight, y)
    love.graphics.draw(bottomLeftScaled, x, y + height - scaledBottom)
    love.graphics.draw(bottomRightScaled, x + width - scaledRight, y + height - scaledBottom)

    -- Update content dimensions to account for scaled borders
    local adjustedContentWidth = width - scaledLeft - scaledRight
    local adjustedContentHeight = height - scaledTop - scaledBottom
    adjustedContentWidth = math.max(0, adjustedContentWidth)
    adjustedContentHeight = math.max(0, adjustedContentHeight)

    -- Recalculate stretch scales
    local adjustedScaleX = adjustedContentWidth / centerW
    local adjustedScaleY = adjustedContentHeight / centerH

    -- TOP/BOTTOM EDGES (stretch horizontally, scale vertically)
    if adjustedContentWidth > 0 then
      local topCenterScaled = getScaledRegion("topCenter", regions.topCenter, regions.topCenter.w, scaledTop)
      local bottomCenterScaled =
        getScaledRegion("bottomCenter", regions.bottomCenter, regions.bottomCenter.w, scaledBottom)

      love.graphics.draw(topCenterScaled, x + scaledLeft, y, 0, adjustedScaleX, 1)
      love.graphics.draw(bottomCenterScaled, x + scaledLeft, y + height - scaledBottom, 0, adjustedScaleX, 1)
    end

    -- LEFT/RIGHT EDGES (stretch vertically, scale horizontally)
    if adjustedContentHeight > 0 then
      local middleLeftScaled = getScaledRegion("middleLeft", regions.middleLeft, scaledLeft, regions.middleLeft.h)
      local middleRightScaled = getScaledRegion("middleRight", regions.middleRight, scaledRight, regions.middleRight.h)

      love.graphics.draw(middleLeftScaled, x, y + scaledTop, 0, 1, adjustedScaleY)
      love.graphics.draw(middleRightScaled, x + width - scaledRight, y + scaledTop, 0, 1, adjustedScaleY)
    end

    -- CENTER (stretch both dimensions, no scaling)
    if adjustedContentWidth > 0 and adjustedContentHeight > 0 then
      love.graphics.draw(
        atlas,
        makeQuad(regions.middleCenter),
        x + scaledLeft,
        y + scaledTop,
        0,
        adjustedScaleX,
        adjustedScaleY
      )
    end
  else
    -- Original rendering logic (no scaling)
    -- CORNERS (no scaling - 1:1 pixel perfect)
    love.graphics.draw(atlas, makeQuad(regions.topLeft), x, y)
    love.graphics.draw(atlas, makeQuad(regions.topRight), x + left + contentWidth, y)
    love.graphics.draw(atlas, makeQuad(regions.bottomLeft), x, y + top + contentHeight)
    love.graphics.draw(atlas, makeQuad(regions.bottomRight), x + left + contentWidth, y + top + contentHeight)

    -- TOP/BOTTOM EDGES (stretch horizontally only)
    if contentWidth > 0 then
      love.graphics.draw(atlas, makeQuad(regions.topCenter), x + left, y, 0, scaleX, 1)
      love.graphics.draw(atlas, makeQuad(regions.bottomCenter), x + left, y + top + contentHeight, 0, scaleX, 1)
    end

    -- LEFT/RIGHT EDGES (stretch vertically only)
    if contentHeight > 0 then
      love.graphics.draw(atlas, makeQuad(regions.middleLeft), x, y + top, 0, 1, scaleY)
      love.graphics.draw(atlas, makeQuad(regions.middleRight), x + left + contentWidth, y + top, 0, 1, scaleY)
    end

    -- CENTER (stretch both dimensions)
    if contentWidth > 0 and contentHeight > 0 then
      love.graphics.draw(atlas, makeQuad(regions.middleCenter), x + left, y + top, 0, scaleX, scaleY)
    end
  end

  -- Reset color
  love.graphics.setColor(1, 1, 1, 1)
end

return NinePatch
