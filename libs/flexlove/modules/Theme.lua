--- Auto-detect the base path where FlexLove is located
---@return string modulePath, string filesystemPath
local function getFlexLoveBasePath()
  -- Get debug info to find where this file is loaded from
  local info = debug.getinfo(1, "S")
  if info and info.source then
    local source = info.source
    -- Remove leading @ if present
    if source:sub(1, 1) == "@" then
      source = source:sub(2)
    end

    -- Extract the directory path (remove Theme.lua and modules/)
    local filesystemPath = source:match("(.*/)")
    if filesystemPath then
      -- Store the original filesystem path for loading assets
      local fsPath = filesystemPath
      -- Remove leading ./ if present
      fsPath = fsPath:gsub("^%./", "")
      -- Remove trailing /
      fsPath = fsPath:gsub("/$", "")
      -- Remove the flexlove subdirectory to get back to base
      fsPath = fsPath:gsub("/modules$", "")

      -- Convert filesystem path to Lua module path
      local modulePath = fsPath:gsub("/", ".")

      return modulePath, fsPath
    end
  end

  -- Fallback: try a common path
  return "libs", "libs"
end

-- Store the base paths when module loads
local FLEXLOVE_BASE_PATH, FLEXLOVE_FILESYSTEM_PATH = getFlexLoveBasePath()

--- Validate theme definition structure
---@param definition ThemeDefinition
---@return boolean, string? -- Returns true if valid, or false with error message
local function validateThemeDefinition(definition)
  if not definition then
    return false, "Theme definition is nil"
  end

  if type(definition) ~= "table" then
    return false, "Theme definition must be a table"
  end

  if not definition.name or type(definition.name) ~= "string" then
    return false, "Theme must have a 'name' field (string)"
  end

  if definition.components and type(definition.components) ~= "table" then
    return false, "Theme 'components' must be a table"
  end

  if definition.colors and type(definition.colors) ~= "table" then
    return false, "Theme 'colors' must be a table"
  end

  if definition.fonts and type(definition.fonts) ~= "table" then
    return false, "Theme 'fonts' must be a table"
  end

  if definition.scrollbars and type(definition.scrollbars) ~= "table" then
    return false, "Theme 'scrollbars' must be a table"
  end

  return true, nil
end

--- Load image data from a file path
---@param imagePath string
---@return love.ImageData
local function loadImageData(imagePath)
  if not imagePath then
    error("Image path cannot be nil")
  end

  local success, result = pcall(function()
    return love.image.newImageData(imagePath)
  end)

  if not success then
    error("Failed to load image data from '" .. imagePath .. "': " .. tostring(result))
  end

  return result
end

--- Extract all pixels from a specific row
---@param imageData love.ImageData
---@param rowIndex number 0-based row index
---@return table Array of {r, g, b, a} values (0-255 range)
local function getRow(imageData, rowIndex)
  if not imageData then
    error("ImageData cannot be nil")
  end

  local width = imageData:getWidth()
  local height = imageData:getHeight()

  if rowIndex < 0 or rowIndex >= height then
    error(string.format("Row index %d out of bounds (height: %d)", rowIndex, height))
  end

  local pixels = {}
  for x = 0, width - 1 do
    local r, g, b, a = imageData:getPixel(x, rowIndex)
    table.insert(pixels, {
      r = math.floor(r * 255 + 0.5),
      g = math.floor(g * 255 + 0.5),
      b = math.floor(b * 255 + 0.5),
      a = math.floor(a * 255 + 0.5),
    })
  end

  return pixels
end

--- Extract all pixels from a specific column
---@param imageData love.ImageData
---@param colIndex number 0-based column index
---@return table Array of {r, g, b, a} values (0-255 range)
local function getColumn(imageData, colIndex)
  if not imageData then
    error("ImageData cannot be nil")
  end

  local width = imageData:getWidth()
  local height = imageData:getHeight()

  if colIndex < 0 or colIndex >= width then
    error(string.format("Column index %d out of bounds (width: %d)", colIndex, width))
  end

  local pixels = {}
  for y = 0, height - 1 do
    local r, g, b, a = imageData:getPixel(colIndex, y)
    table.insert(pixels, {
      r = math.floor(r * 255 + 0.5),
      g = math.floor(g * 255 + 0.5),
      b = math.floor(b * 255 + 0.5),
      a = math.floor(a * 255 + 0.5),
    })
  end

  return pixels
end

--- Check if a pixel is black with full alpha (9-patch marker)
---@param r number Red (0-255)
---@param g number Green (0-255)
---@param b number Blue (0-255)
---@param a number Alpha (0-255)
---@return boolean
local function isBlackPixel(r, g, b, a)
  return r == 0 and g == 0 and b == 0 and a == 255
end

--- Find all continuous runs of black pixels in a pixel array
---@param pixels table Array of {r, g, b, a} pixel values
---@return table Array of {start, end} pairs (1-based indices, inclusive)
local function findBlackPixelRuns(pixels)
  local runs = {}
  local inRun = false
  local runStart = nil

  for i = 1, #pixels do
    local pixel = pixels[i]
    local isBlack = isBlackPixel(pixel.r, pixel.g, pixel.b, pixel.a)

    if isBlack and not inRun then
      -- Start of a new run
      inRun = true
      runStart = i
    elseif not isBlack and inRun then
      -- End of current run
      table.insert(runs, { start = runStart, ["end"] = i - 1 })
      inRun = false
      runStart = nil
    end
  end

  -- Handle case where run extends to end of array
  if inRun then
    table.insert(runs, { start = runStart, ["end"] = #pixels })
  end

  return runs
end

--- Parse a 9-patch PNG image to extract stretch regions and content padding
---@param imagePath string Path to the 9-patch image file
---@return table|nil, string|nil Returns {insets, stretchX, stretchY} or nil, error message
local function parseNinePatch(imagePath)
  if not imagePath then
    return nil, "Image path cannot be nil"
  end

  local success, imageData = pcall(function()
    return loadImageData(imagePath)
  end)

  if not success then
    return nil, "Failed to load image data: " .. tostring(imageData)
  end

  local width = imageData:getWidth()
  local height = imageData:getHeight()

  -- Validate minimum size (must be at least 3x3 with 1px border)
  if width < 3 or height < 3 then
    return nil, string.format("Invalid 9-patch dimensions: %dx%d (minimum 3x3)", width, height)
  end

  -- Extract border pixels (0-based indexing, but we convert to 1-based for processing)
  local topBorder = getRow(imageData, 0)
  local leftBorder = getColumn(imageData, 0)
  local bottomBorder = getRow(imageData, height - 1)
  local rightBorder = getColumn(imageData, width - 1)

  -- Remove corner pixels from borders (they're not part of the stretch/content markers)
  -- Top and bottom borders: remove first and last pixel
  local topStretchPixels = {}
  local bottomContentPixels = {}
  for i = 2, #topBorder - 1 do
    table.insert(topStretchPixels, topBorder[i])
  end
  for i = 2, #bottomBorder - 1 do
    table.insert(bottomContentPixels, bottomBorder[i])
  end

  -- Left and right borders: remove first and last pixel
  local leftStretchPixels = {}
  local rightContentPixels = {}
  for i = 2, #leftBorder - 1 do
    table.insert(leftStretchPixels, leftBorder[i])
  end
  for i = 2, #rightBorder - 1 do
    table.insert(rightContentPixels, rightBorder[i])
  end

  -- Find stretch regions (top and left borders)
  local stretchX = findBlackPixelRuns(topStretchPixels)
  local stretchY = findBlackPixelRuns(leftStretchPixels)

  -- Find content padding regions (bottom and right borders)
  local contentX = findBlackPixelRuns(bottomContentPixels)
  local contentY = findBlackPixelRuns(rightContentPixels)

  -- Validate that we have at least one stretch region
  if #stretchX == 0 or #stretchY == 0 then
    return nil, "No stretch regions found (top or left border has no black pixels)"
  end

  -- Calculate stretch insets from stretch regions (top/left guides)
  -- Use the first stretch region's start and last stretch region's end
  local firstStretchX = stretchX[1]
  local lastStretchX = stretchX[#stretchX]
  local firstStretchY = stretchY[1]
  local lastStretchY = stretchY[#stretchY]

  -- Stretch insets define the 9-patch regions
  local stretchLeft = firstStretchX.start
  local stretchRight = #topStretchPixels - lastStretchX["end"]
  local stretchTop = firstStretchY.start
  local stretchBottom = #leftStretchPixels - lastStretchY["end"]

  -- Calculate content padding from content guides (bottom/right guides)
  -- If content padding is defined, use it; otherwise use stretch regions
  local contentLeft, contentRight, contentTop, contentBottom

  if #contentX > 0 then
    contentLeft = contentX[1].start
    contentRight = #topStretchPixels - contentX[#contentX]["end"]
  else
    contentLeft = stretchLeft
    contentRight = stretchRight
  end

  if #contentY > 0 then
    contentTop = contentY[1].start
    contentBottom = #leftStretchPixels - contentY[#contentY]["end"]
  else
    contentTop = stretchTop
    contentBottom = stretchBottom
  end

  return {
    insets = {
      left = stretchLeft,
      top = stretchTop,
      right = stretchRight,
      bottom = stretchBottom,
    },
    contentPadding = {
      left = contentLeft,
      top = contentTop,
      right = contentRight,
      bottom = contentBottom,
    },
    stretchX = stretchX,
    stretchY = stretchY,
  }
end

---@class Theme
local Theme = {}
Theme.__index = Theme

--- Initialize module with shared dependencies
---@param deps table Dependencies {ErrorHandler, Color, utils}
function Theme.init(deps)
  if type(deps) == "table" then
    Theme._ErrorHandler = deps.ErrorHandler
    Theme._Color = deps.Color
    Theme._utils = deps.utils
  end
end

-- Global theme registry
local themes = {}
local activeTheme = nil

--- Create reusable design systems with consistent styling, 9-patch assets, and component states
--- Use this to build professional-looking UIs with minimal per-element configuration
---@param definition ThemeDefinition Theme definition table
---@return Theme theme The new theme instance
function Theme.new(definition)
  -- Validate input type first
  if type(definition) ~= "table" then
    Theme._ErrorHandler:warn("Theme", "THM_001", {
      error = "Theme definition must be a table, got " .. type(definition),
    })
    return Theme.new({ name = "fallback", components = {}, colors = {}, fonts = {} })
  end

  -- Validate theme definition
  local valid, err = validateThemeDefinition(definition)
  if not valid then
    Theme._ErrorHandler:warn("Theme", "THM_001", {
      error = tostring(err),
    })
    return Theme.new({ name = "fallback", components = {}, colors = {}, fonts = {} })
  end

  local self = setmetatable({}, Theme)
  self.name = definition.name

  -- Load global atlas if it's a string path
  if definition.atlas then
    if type(definition.atlas) == "string" then
      local resolvedPath = Theme._utils.resolveImagePath(definition.atlas)
      local image, imageData, loaderr = Theme._utils.safeLoadImage(resolvedPath)
      if image then
        self.atlas = image
        self.atlasData = imageData
      else
        Theme._ErrorHandler:warn("Theme", "RES_001", {
          theme = definition.name,
          path = resolvedPath,
          error = loaderr,
        })
      end
    else
      self.atlas = definition.atlas
    end
  end

  self.components = definition.components or {}
  self.scrollbars = definition.scrollbars or {}
  self.colors = definition.colors or {}
  self.fonts = definition.fonts or {}
  self.contentAutoSizingMultiplier = definition.contentAutoSizingMultiplier or nil

  -- Helper function to strip 1-pixel guide border from 9-patch ImageData
  ---@param sourceImageData love.ImageData
  ---@return love.ImageData -- New ImageData without guide border
  local function stripNinePatchBorder(sourceImageData)
    local srcWidth = sourceImageData:getWidth()
    local srcHeight = sourceImageData:getHeight()

    -- Content dimensions (excluding 1px border on all sides)
    local contentWidth = srcWidth - 2
    local contentHeight = srcHeight - 2

    if contentWidth <= 0 or contentHeight <= 0 then
      Theme._ErrorHandler:warn("Theme", "RES_002", {
        width = srcWidth,
        height = srcHeight,
        reason = "Image must be larger than 2x2 pixels to have content after stripping 1px border",
      })
      return nil
    end

    -- Create new ImageData for content only
    local strippedImageData = love.image.newImageData(contentWidth, contentHeight)

    -- Copy pixels from source (1,1) to (width-2, height-2)
    for y = 0, contentHeight - 1 do
      for x = 0, contentWidth - 1 do
        local r, g, b, a = sourceImageData:getPixel(x + 1, y + 1)
        strippedImageData:setPixel(x, y, r, g, b, a)
      end
    end

    return strippedImageData
  end

  -- Helper function to load atlas with 9-patch support
  local function loadAtlasWithNinePatch(comp, atlasPath, errorContext)
    ---@diagnostic disable-next-line
    local resolvedPath = Theme._utils.resolveImagePath(atlasPath)
    ---@diagnostic disable-next-line
    local is9Patch = not comp.insets and atlasPath:match("%.9%.png$")

    if is9Patch then
      local parseResult, parseErr = parseNinePatch(resolvedPath)
      if parseResult then
        comp.insets = parseResult.insets
        comp._ninePatchData = parseResult
      else
        Theme._ErrorHandler:warn("Theme", "RES_003", {
          context = errorContext,
          path = resolvedPath,
          error = tostring(parseErr),
        })
      end
    end

    local image, imageData, loaderr = Theme._utils.safeLoadImage(resolvedPath)
    if image then
      -- Strip guide border for 9-patch images
      if is9Patch and imageData then
        local strippedImageData = stripNinePatchBorder(imageData)
        local strippedImage = love.graphics.newImage(strippedImageData)
        comp._loadedAtlas = strippedImage
        comp._loadedAtlasData = strippedImageData
      else
        comp._loadedAtlas = image
        comp._loadedAtlasData = imageData
      end
    else
      Theme._ErrorHandler:warn("Theme", "RES_001", {
        context = errorContext,
        path = resolvedPath,
        error = tostring(loaderr),
      })
    end
  end

  -- Helper function to create regions from insets
  local function createRegionsFromInsets(comp, fallbackAtlas)
    local atlasImage = comp._loadedAtlas or fallbackAtlas
    if not atlasImage or type(atlasImage) == "string" then
      return
    end

    local imgWidth, imgHeight = atlasImage:getDimensions()
    local left = comp.insets.left or 0
    local top = comp.insets.top or 0
    local right = comp.insets.right or 0
    local bottom = comp.insets.bottom or 0

    -- No offsets needed - guide border has been stripped for 9-patch images
    local centerWidth = imgWidth - left - right
    local centerHeight = imgHeight - top - bottom

    comp.regions = {
      topLeft = { x = 0, y = 0, w = left, h = top },
      topCenter = { x = left, y = 0, w = centerWidth, h = top },
      topRight = { x = left + centerWidth, y = 0, w = right, h = top },
      middleLeft = { x = 0, y = top, w = left, h = centerHeight },
      middleCenter = { x = left, y = top, w = centerWidth, h = centerHeight },
      middleRight = { x = left + centerWidth, y = top, w = right, h = centerHeight },
      bottomLeft = { x = 0, y = top + centerHeight, w = left, h = bottom },
      bottomCenter = { x = left, y = top + centerHeight, w = centerWidth, h = bottom },
      bottomRight = { x = left + centerWidth, y = top + centerHeight, w = right, h = bottom },
    }
  end

  -- Load component-specific atlases and process 9-patch definitions
  for componentName, component in pairs(self.components) do
    if component.atlas then
      if type(component.atlas) == "string" then
        loadAtlasWithNinePatch(component, component.atlas, "for component '" .. componentName .. "'")
      else
        -- Direct Image object (no ImageData available - scaleCorners won't work)
        component._loadedAtlas = component.atlas
      end
    end

    if component.insets then
      createRegionsFromInsets(component, self.atlas)
    end

    if component.states then
      for stateName, stateComponent in pairs(component.states) do
        if stateComponent.atlas then
          if type(stateComponent.atlas) == "string" then
            loadAtlasWithNinePatch(stateComponent, stateComponent.atlas, "for state '" .. stateName .. "'")
          else
            -- Direct Image object (no ImageData available - scaleCorners won't work)
            stateComponent._loadedAtlas = stateComponent.atlas
          end
        end

        if stateComponent.insets then
          createRegionsFromInsets(stateComponent, component._loadedAtlas or self.atlas)
        end
      end
    end
  end

  -- Load scrollbar-specific atlases and process 9-patch definitions
  -- Scrollbars can have 'bar' and 'frame' subcomponents
  for scrollbarName, scrollbarDef in pairs(self.scrollbars) do
    -- Handle scrollbar definitions with bar/frame subcomponents
    if scrollbarDef.bar or scrollbarDef.frame then
      -- Process 'bar' subcomponent
      if scrollbarDef.bar then
        if type(scrollbarDef.bar) == "string" then
          -- Convert string path to ThemeComponent structure
          local barComponent = { atlas = scrollbarDef.bar }
          -- Copy knobOffset from parent scrollbarDef if it exists
          if scrollbarDef.knobOffset then
            barComponent.knobOffset = scrollbarDef.knobOffset
          end
          loadAtlasWithNinePatch(barComponent, scrollbarDef.bar, "for scrollbar '" .. scrollbarName .. ".bar'")
          if barComponent.insets then
            createRegionsFromInsets(barComponent, barComponent._loadedAtlas or self.atlas)
          end
          scrollbarDef.bar = barComponent
        elseif type(scrollbarDef.bar) == "table" then
          -- Already a ThemeComponent structure, process it
          -- Copy knobOffset from parent if bar component doesn't have one
          if scrollbarDef.knobOffset and not scrollbarDef.bar.knobOffset then
            scrollbarDef.bar.knobOffset = scrollbarDef.knobOffset
          end
          if scrollbarDef.bar.atlas and type(scrollbarDef.bar.atlas) == "string" then
            loadAtlasWithNinePatch(
              scrollbarDef.bar,
              scrollbarDef.bar.atlas,
              "for scrollbar '" .. scrollbarName .. ".bar'"
            )
          end
          if scrollbarDef.bar.insets then
            createRegionsFromInsets(scrollbarDef.bar, scrollbarDef.bar._loadedAtlas or self.atlas)
          end
        end
      end

      -- Process 'frame' subcomponent
      if scrollbarDef.frame then
        if type(scrollbarDef.frame) == "string" then
          -- Convert string path to ThemeComponent structure
          local frameComponent = { atlas = scrollbarDef.frame }
          loadAtlasWithNinePatch(frameComponent, scrollbarDef.frame, "for scrollbar '" .. scrollbarName .. ".frame'")
          if frameComponent.insets then
            createRegionsFromInsets(frameComponent, frameComponent._loadedAtlas or self.atlas)
          end
          scrollbarDef.frame = frameComponent
        elseif type(scrollbarDef.frame) == "table" then
          -- Already a ThemeComponent structure, process it
          if scrollbarDef.frame.atlas and type(scrollbarDef.frame.atlas) == "string" then
            loadAtlasWithNinePatch(
              scrollbarDef.frame,
              scrollbarDef.frame.atlas,
              "for scrollbar '" .. scrollbarName .. ".frame'"
            )
          end
          if scrollbarDef.frame.insets then
            createRegionsFromInsets(scrollbarDef.frame, scrollbarDef.frame._loadedAtlas or self.atlas)
          end
        end
      end
    else
      -- Treat as a single ThemeComponent (no bar/frame split)
      if scrollbarDef.atlas then
        if type(scrollbarDef.atlas) == "string" then
          loadAtlasWithNinePatch(scrollbarDef, scrollbarDef.atlas, "for scrollbar '" .. scrollbarName .. "'")
        else
          scrollbarDef._loadedAtlas = scrollbarDef.atlas
        end
      end

      if scrollbarDef.insets then
        createRegionsFromInsets(scrollbarDef, self.atlas)
      end

      if scrollbarDef.states then
        for stateName, stateComponent in pairs(scrollbarDef.states) do
          if stateComponent.atlas then
            if type(stateComponent.atlas) == "string" then
              loadAtlasWithNinePatch(
                stateComponent,
                stateComponent.atlas,
                "for scrollbar '" .. scrollbarName .. "' state '" .. stateName .. "'"
              )
            else
              stateComponent._loadedAtlas = stateComponent.atlas
            end
          end

          if stateComponent.insets then
            createRegionsFromInsets(stateComponent, scrollbarDef._loadedAtlas or self.atlas)
          end
        end
      end
    end
  end

  return self
end

--- Import a theme definition from a file to enable hot-reloading and modular design systems
--- Use this to load bundled or user-created themes dynamically
---@param path string Path to theme definition file (e.g., "space" or "mytheme")
---@return Theme? theme The loaded theme, or nil on error
function Theme.load(path)
  local definition
  local themePath = FLEXLOVE_BASE_PATH .. ".themes." .. path

  local success, result = pcall(function()
    return require(themePath)
  end)
  if success then
    definition = result
  else
    success, result = pcall(function()
      return require(path)
    end)
    if success then
      definition = result
    else
      Theme._ErrorHandler:warn("Theme", "RES_004", {
        theme = path,
        tried = themePath,
        error = tostring(result),
        fallback = "nil (no theme loaded)",
      })
      return nil
    end
  end

  local theme = Theme.new(definition)
  themes[theme.name] = theme
  themes[path] = theme

  return theme
end

--- Switch the global theme to instantly restyle all themed UI elements
--- Use this to implement light/dark mode toggles or user-selectable skins
---@param themeOrName Theme|string Theme instance or theme name to activate
function Theme.setActive(themeOrName)
  if type(themeOrName) == "string" then
    -- Try to load if not already loaded
    if not themes[themeOrName] then
      Theme.load(themeOrName)
    end
    activeTheme = themes[themeOrName]
  else
    activeTheme = themeOrName
  end

  if not activeTheme then
    Theme._ErrorHandler:warn("Theme", "THM_002", {
      theme = tostring(themeOrName),
      reason = "Theme not found or not loaded",
      fallback = "current theme unchanged",
    })
    -- Keep current activeTheme unchanged (fallback behavior)
  end
end

--- Access the current theme to query colors, fonts, or create theme-aware components
--- Use this to build UI that adapts to the active design system
---@return Theme? theme The active theme, or nil if none is active
function Theme.getActive()
  return activeTheme
end

--- Retrieve pre-configured visual styles for UI components to maintain consistency
--- Use this to apply theme definitions to custom elements
---@param componentName string Name of the component (e.g., "button", "panel")
---@param state string? Optional state (e.g., "hover", "pressed", "disabled")
---@return ThemeComponent? component Returns component or nil if not found
function Theme.getComponent(componentName, state)
  if not activeTheme then
    return nil
  end

  local component = activeTheme.components[componentName]
  if not component then
    return nil
  end

  -- Check for state-specific override
  if state and component.states and component.states[state] then
    return component.states[state]
  end

  return component
end

--- Get the first (default) scrollbar from the active theme
--- Returns the first scrollbar component in insertion order
---@return ThemeComponent? scrollbar Returns first scrollbar component or nil if no scrollbars defined
function Theme.getDefaultScrollbar()
  if not activeTheme or not activeTheme.scrollbars then
    return nil
  end

  local _, scrollbar = next(activeTheme.scrollbars)
  return scrollbar
end

--- Retrieve themed scrollbar components for consistent scrollbar styling
--- Use this to apply theme-based scrollbar appearance to scrollable elements
---@param scrollbarName string? Name of the scrollbar style (e.g., "v1", "v2"). If nil, returns default (first) scrollbar
---@param state string? Optional state name (e.g., "hover", "pressed") - currently unused for scrollbars
---@return ThemeComponent? scrollbar Returns scrollbar component or nil if not found
function Theme.getScrollbar(scrollbarName, state)
  if not activeTheme or not activeTheme.scrollbars then
    return nil
  end

  -- If no scrollbarName specified, return default (first) scrollbar
  if not scrollbarName then
    return Theme.getDefaultScrollbar()
  end

  local scrollbar = activeTheme.scrollbars[scrollbarName]
  if not scrollbar then
    return nil
  end

  -- Check for state-specific override (if scrollbar supports states in the future)
  if state and scrollbar.states and scrollbar.states[state] then
    return scrollbar.states[state]
  end

  return scrollbar
end

--- Access theme-defined fonts for consistent typography across your UI
--- Use this to load fonts specified in your theme definition
---@param fontName string Name of the font family (e.g., "default", "heading")
---@return string? fontPath Returns font path or nil if not found
function Theme.getFont(fontName)
  if not activeTheme then
    return nil
  end

  return activeTheme.fonts and activeTheme.fonts[fontName]
end

--- Retrieve semantic colors from the theme palette for consistent brand identity
--- Use this instead of hardcoding colors to support themeing and color scheme switches
---@param colorName string Name of the color (e.g., "primary", "secondary")
---@return Color? color Returns Color instance or nil if not found
function Theme.getColor(colorName)
  if not activeTheme then
    return nil
  end

  return activeTheme.colors and activeTheme.colors[colorName]
end

--- Check if a theme is currently active
---@return boolean active Returns true if a theme is active
function Theme.hasActive()
  return activeTheme ~= nil
end

--- Get all registered theme names
---@return string[] themeNames Array of theme names
function Theme.getRegisteredThemes()
  local themeNames = {}
  for name, _ in pairs(themes) do
    table.insert(themeNames, name)
  end
  return themeNames
end

--- Get all available color names from the active theme
---@return string[]? colorNames Array of color names, or nil if no theme active
function Theme.getColorNames()
  if not activeTheme or not activeTheme.colors then
    return nil
  end

  local colorNames = {}
  for name, _ in pairs(activeTheme.colors) do
    table.insert(colorNames, name)
  end
  return colorNames
end

--- Get all colors from the active theme
---@return table<string, Color>? colors Table of all colors, or nil if no theme active
function Theme.getAllColors()
  if not activeTheme then
    return nil
  end

  return activeTheme.colors
end

--- Safely get theme colors with guaranteed fallbacks to prevent missing color errors
--- Use this when you need a color value no matter what
---@param colorName string Name of the color to retrieve
---@param fallback Color? Fallback color if not found (default: white)
---@return Color color The color or fallback (guaranteed non-nil)
function Theme.getColorOrDefault(colorName, fallback)
  local color = Theme.getColor(colorName)
  if color then
    return color
  end

  return fallback or Theme._Color.new(1, 1, 1, 1)
end

--- Get a theme by name
---@param themeName string Name of the theme
---@return Theme? theme Returns theme or nil if not found
function Theme.get(themeName)
  return themes[themeName]
end

--------------------------------------------------------------------------------
-- ThemeManager: Instance-level theme state management
--------------------------------------------------------------------------------

---@class ThemeManager
local ThemeManager = {}
ThemeManager.__index = ThemeManager

---Create a new ThemeManager instance
---@param config table Configuration options {theme: string?, themeComponent: string?, disabled: boolean?, active: boolean?, disableHighlight: boolean?, themeStateLock: boolean|string?, themeComponentDisabledStates: string[]?, scaleCorners: number?, scalingAlgorithm: string?}
---@return ThemeManager manager The new ThemeManager instance
function ThemeManager.new(config)
  local self = setmetatable({}, ThemeManager)

  self.theme = config.theme
  self.themeComponent = config.themeComponent
  self.disabled = config.disabled or false
  self.active = config.active or false
  self.disableHighlight = config.disableHighlight
  self.themeStateLock = config.themeStateLock or false
  self.scaleCorners = config.scaleCorners
  self.scalingAlgorithm = config.scalingAlgorithm

  -- Normalize themeComponentDisabledStates to a lookup set for O(1) checks
  self.themeComponentDisabledStates = {}
  if config.themeComponentDisabledStates then
    for _, state in ipairs(config.themeComponentDisabledStates) do
      if type(state) == "string" then
        self.themeComponentDisabledStates[state] = true
      end
    end
  end

  -- Set initial state based on themeStateLock
  if self.themeStateLock == true or self.themeStateLock == "default" then
    self._themeState = "normal"
  elseif type(self.themeStateLock) == "string" then
    self._themeState = self.themeStateLock
  else
    self._themeState = "normal"
  end

  return self
end

---Update the theme state based on element interaction state
---@param isHovered boolean Whether element is hovered
---@param isPressed boolean Whether element is pressed
---@param isFocused boolean Whether element is focused (keyboard focus)
---@param isDisabled boolean Whether element is disabled
---@return string state The new theme state ("normal", "hover", "pressed", "active", "disabled")
function ThemeManager:updateState(isHovered, isPressed, isFocused, isDisabled)
  -- If themeStateLock is set (and not false), use the locked state
  if self.themeStateLock ~= false and self.themeStateLock ~= nil then
    local lockedState

    if self.themeStateLock == true or self.themeStateLock == "default" then
      -- true or "default" means lock to "normal" (base state)
      lockedState = "normal"
    elseif type(self.themeStateLock) == "string" then
      -- String means lock to specific state
      lockedState = self.themeStateLock

      -- Validate the locked state exists in the theme component (will be done during initialization)
      -- For now, just use the string value
    else
      -- Invalid themeStateLock value, fall back to normal behavior
      lockedState = nil
    end

    if lockedState then
      self._themeState = lockedState
      return lockedState
    end
  end

  -- Normal behavior: calculate state based on interaction
  -- Keyboard focus reuses the hover state so themes only need one visual variant.
  -- Priority: disabled > active > pressed > hover/focus > normal
  -- If a state is in themeComponentDisabledStates, fall through to the next lower-priority state.
  local candidates = {
    { state = "disabled", condition = isDisabled or self.disabled },
    { state = "active", condition = self.active },
    { state = "pressed", condition = isPressed },
    { state = "hover", condition = isHovered or isFocused },
  }

  local newState = "normal"
  for _, candidate in ipairs(candidates) do
    if candidate.condition and not self.themeComponentDisabledStates[candidate.state] then
      newState = candidate.state
      break
    end
  end

  self._themeState = newState
  return newState
end

---Get the current theme state
---@return string state The current theme state
function ThemeManager:getState()
  return self._themeState
end

---Set the theme state explicitly
---@param state string The theme state to set ("normal", "hover", "pressed", "active", "disabled")
function ThemeManager:setState(state)
  if type(state) ~= "string" then
    return
  end
  self._themeState = state
end

---Check if a theme component is set
---@return boolean hasComponent True if a theme component is set
function ThemeManager:hasThemeComponent()
  return self.themeComponent ~= nil
end

---Get the theme (either instance-specific or active theme)
---@return Theme? theme The theme instance, or nil if not found
function ThemeManager:getTheme()
  if self.theme then
    return Theme.get(self.theme)
  end
  return Theme.getActive()
end

---Get the base theme component
---@return ThemeComponent? component The theme component, or nil if not found
function ThemeManager:getComponent()
  if not self.themeComponent then
    return nil
  end

  local themeToUse = self:getTheme()
  if not themeToUse or not themeToUse.components or type(themeToUse.components) ~= "table" then
    return nil
  end

  if not themeToUse.components[self.themeComponent] then
    return nil
  end

  return themeToUse.components[self.themeComponent]
end

---Get the theme component for the current state
---@return ThemeComponent? component The state-specific component, or base component, or nil
function ThemeManager:getStateComponent()
  local component = self:getComponent()
  if not component then
    return nil
  end

  local state = self._themeState
  if
    state
    and state ~= "normal"
    and component.states
    and type(component.states) == "table"
    and component.states[state]
  then
    return component.states[state]
  end

  return component
end

---Get a scrollbar component from the theme
---@param scrollbarName string? The scrollbar style name (e.g., "v1", "v2"). If nil, returns default (first) scrollbar
---@return ThemeComponent? scrollbar The scrollbar component, or nil if not found
function ThemeManager:getScrollbarComponent(scrollbarName)
  local themeToUse = self:getTheme()
  if not themeToUse or not themeToUse.scrollbars or type(themeToUse.scrollbars) ~= "table" then
    return nil
  end

  if not scrollbarName then
    local _, scrollbar = next(themeToUse.scrollbars)
    return scrollbar
  end

  return themeToUse.scrollbars[scrollbarName]
end

---Get a style property from the current state component
---@param property string The property name
---@return any? value The property value, or nil if not found
function ThemeManager:getStyle(property)
  if type(property) ~= "string" then
    return nil
  end

  local stateComponent = self:getStateComponent()
  if not stateComponent or type(stateComponent) ~= "table" then
    return nil
  end

  return stateComponent[property]
end

---Get scaled content padding based on border box dimensions
---@param borderBoxWidth number The border box width
---@param borderBoxHeight number The border box height
---@return table? padding Table with {left, top, right, bottom}, or nil if no contentPadding
function ThemeManager:_getScaledContentPaddingForComponent(component, borderBoxWidth, borderBoxHeight)
  if not component or not component._ninePatchData or not component._ninePatchData.contentPadding then
    return nil
  end

  local contentPadding = component._ninePatchData.contentPadding
  local themeToUse = self:getTheme()
  local atlasImage = component._loadedAtlas or (themeToUse and themeToUse.atlas)

  if atlasImage and type(atlasImage) ~= "string" then
    local originalWidth, originalHeight = atlasImage:getDimensions()

    local insets = component.insets
    if insets and type(insets) == "table" then
      local cornerScale = self.scaleCorners
      if cornerScale == nil then
        cornerScale = component.scaleCorners
      end
      if type(cornerScale) ~= "number" or cornerScale <= 0 then
        cornerScale = 1
      end

      local function mapDistanceFromStart(sourceDistance, sourceSize, targetSize, sourceStartInset, sourceEndInset)
        local sourceStart = sourceStartInset or 0
        local sourceEnd = sourceEndInset or 0

        local sourceCenter = math.max(0, sourceSize - sourceStart - sourceEnd)
        local targetStart = sourceStart * cornerScale
        local targetEnd = sourceEnd * cornerScale
        local targetCenter = math.max(0, targetSize - targetStart - targetEnd)

        if sourceDistance <= sourceStart then
          return sourceDistance * cornerScale
        end

        if sourceDistance >= (sourceSize - sourceEnd) then
          local distanceFromEnd = sourceSize - sourceDistance
          return targetSize - (distanceFromEnd * cornerScale)
        end

        if sourceCenter <= 0 then
          return targetStart
        end

        local t = (sourceDistance - sourceStart) / sourceCenter
        return targetStart + (t * targetCenter)
      end

      local left = mapDistanceFromStart(contentPadding.left, originalWidth, borderBoxWidth, insets.left, insets.right)
      local rightBoundary = mapDistanceFromStart(
        originalWidth - contentPadding.right,
        originalWidth,
        borderBoxWidth,
        insets.left,
        insets.right
      )
      local right = borderBoxWidth - rightBoundary

      local top = mapDistanceFromStart(contentPadding.top, originalHeight, borderBoxHeight, insets.top, insets.bottom)
      local bottomBoundary = mapDistanceFromStart(
        originalHeight - contentPadding.bottom,
        originalHeight,
        borderBoxHeight,
        insets.top,
        insets.bottom
      )
      local bottom = borderBoxHeight - bottomBoundary

      return {
        left = math.max(0, left),
        top = math.max(0, top),
        right = math.max(0, right),
        bottom = math.max(0, bottom),
      }
    end

    local scaleX = borderBoxWidth / originalWidth
    local scaleY = borderBoxHeight / originalHeight
    return {
      left = contentPadding.left * scaleX,
      top = contentPadding.top * scaleY,
      right = contentPadding.right * scaleX,
      bottom = contentPadding.bottom * scaleY,
    }
  end

  return nil
end

---Get scaled content padding for a specific theme state
---@param state string The theme state to resolve (e.g. "normal", "pressed")
---@param borderBoxWidth number The border box width
---@param borderBoxHeight number The border box height
---@return table? padding Table with {left, top, right, bottom}, or nil if no contentPadding
function ThemeManager:_getScaledContentPaddingForState(state, borderBoxWidth, borderBoxHeight)
  if not self.themeComponent then
    return nil
  end

  local themeToUse = self:getTheme()
  if not themeToUse or not themeToUse.components[self.themeComponent] then
    return nil
  end

  local component = themeToUse.components[self.themeComponent]

  local stateToUse = state or "normal"
  if stateToUse ~= "normal" and component.states and component.states[stateToUse] then
    component = component.states[stateToUse]
  end

  return self:_getScaledContentPaddingForComponent(component, borderBoxWidth, borderBoxHeight)
end

---@param state string The theme state to resolve (e.g. "normal", "pressed")
---@param borderBoxWidth number The border box width
---@param borderBoxHeight number The border box height
---@return table? padding Table with {left, top, right, bottom}, or nil if no contentPadding
function ThemeManager:getScaledContentPaddingForState(state, borderBoxWidth, borderBoxHeight)
  Theme._ErrorHandler:warnDeprecated("Theme", "getScaledContentPaddingForState", "getScaledContentPadding")
  return self:getScaledContentPadding(borderBoxWidth, borderBoxHeight)
end

---Get scaled content padding based on current theme state and border box dimensions
---@param borderBoxWidth number The border box width
---@param borderBoxHeight number The border box height
---@return table? padding Table with {left, top, right, bottom}, or nil if no contentPadding
function ThemeManager:getScaledContentPadding(borderBoxWidth, borderBoxHeight)
  local state = self._themeState or "normal"
  return self:_getScaledContentPaddingForState(state, borderBoxWidth, borderBoxHeight)
end

---Get content auto-sizing multiplier from theme or component
---@return table? multiplier Table with {width: number?, height: number?}, or nil if not defined
function ThemeManager:getContentAutoSizingMultiplier()
  if not self.themeComponent then
    return nil
  end

  local themeToUse = self:getTheme()
  if not themeToUse then
    return nil
  end

  if self.themeComponent and themeToUse.components and type(themeToUse.components) == "table" then
    local component = themeToUse.components[self.themeComponent]
    if component and component.contentAutoSizingMultiplier then
      return component.contentAutoSizingMultiplier
    elseif themeToUse.contentAutoSizingMultiplier then
      return themeToUse.contentAutoSizingMultiplier
    end
  end

  if themeToUse.contentAutoSizingMultiplier then
    return themeToUse.contentAutoSizingMultiplier
  end

  return nil
end

---Get the default font family path from the theme
---@return string? fontPath The default font path, or nil if not defined
function ThemeManager:getDefaultFontFamily()
  local themeToUse = self:getTheme()
  if themeToUse and themeToUse.fonts and type(themeToUse.fonts) == "table" and themeToUse.fonts["default"] then
    return themeToUse.fonts["default"]
  end
  return nil
end

---Set the theme and component for this ThemeManager
---@param themeName string? The theme name to use (nil to use active theme)
---@param componentName string? The component name to use
function ThemeManager:setTheme(themeName, componentName)
  self.theme = themeName
  self.themeComponent = componentName
end

---Validate themeStateLock and warn if invalid
---@return boolean isValid True if themeStateLock is valid or false/nil
function ThemeManager:validateThemeStateLock()
  -- false or nil is always valid (no lock)
  if not self.themeStateLock or self.themeStateLock == false then
    return true
  end

  -- true is always valid (lock to normal)
  if self.themeStateLock == true then
    return true
  end

  -- String value needs validation
  if type(self.themeStateLock) == "string" then
    -- "default" is always valid (lock to normal/base state)
    if self.themeStateLock == "default" then
      return true
    end

    local component = self:getComponent()

    -- If no component, warn that themeStateLock has no effect
    if not component then
      if self.themeComponent then
        Theme._ErrorHandler:warn("Theme", "THM_007", {
          themeComponent = self.themeComponent,
          reason = "themeStateLock has no effect without a valid theme component",
        })
      end
      self.themeStateLock = false
      return false
    end

    -- Check if component has any states at all
    if not component.states or type(component.states) ~= "table" or next(component.states) == nil then
      Theme._ErrorHandler:warn("Theme", "THM_008", {
        themeComponent = self.themeComponent,
        reason = "Theme component has no state variants, themeStateLock has no effect",
      })
      self.themeStateLock = false
      return false
    end

    -- Check if the specified state exists
    if not component.states[self.themeStateLock] then
      -- Warn and fall back to false (no lock)
      Theme._ErrorHandler:warn("Theme", "THM_009", {
        themeComponent = self.themeComponent,
        requestedState = self.themeStateLock,
        availableStates = table.concat(self:_getAvailableStates(component), ", "),
        fallback = "themeStateLock disabled (using dynamic state)",
      })
      self.themeStateLock = false
      return false
    end

    return true
  end

  -- Invalid type for themeStateLock
  Theme._ErrorHandler:warn("Theme", "THM_010", {
    themeStateLockType = type(self.themeStateLock),
    reason = "themeStateLock must be boolean or string",
    fallback = "themeStateLock disabled",
  })
  self.themeStateLock = false
  return false
end

---Get available state names for a component
---@param component ThemeComponent The component to check
---@return table stateNames Array of state names
function ThemeManager:_getAvailableStates(component)
  local states = {}
  if component and component.states and type(component.states) == "table" then
    for stateName, _ in pairs(component.states) do
      table.insert(states, stateName)
    end
  end
  return states
end

Theme.Manager = ThemeManager

--- Check theme definitions for correctness before use to catch configuration errors early
--- Use this during development to verify custom themes are properly structured
---@param theme table? The theme to validate
---@param options table? Optional validation options {strict: boolean}
---@return boolean valid, table errors List of validation errors
function Theme.validateTheme(theme, options)
  local errors = {}
  options = options or {}

  -- Basic structure validation
  if theme == nil then
    table.insert(errors, "Theme is nil")
    return false, errors
  end

  if type(theme) ~= "table" then
    table.insert(errors, "Theme must be a table")
    return false, errors
  end

  -- Name validation (only required field)
  if not theme.name then
    table.insert(errors, "Theme must have a 'name' field")
  elseif type(theme.name) ~= "string" then
    table.insert(errors, "Theme 'name' must be a string")
  elseif theme.name == "" then
    table.insert(errors, "Theme 'name' cannot be empty")
  end

  -- Colors validation (optional, but if present must be valid)
  if theme.colors ~= nil then
    if type(theme.colors) ~= "table" then
      table.insert(errors, "Theme 'colors' must be a table")
    else
      for colorName, colorValue in pairs(theme.colors) do
        if type(colorName) ~= "string" then
          table.insert(errors, "Color name must be a string, got " .. type(colorName))
        else
          -- Accept Color objects, hex strings, or named colors
          local colorType = type(colorValue)
          if colorType == "table" then
            -- Assume it's a Color object if it has r,g,b fields
            if not (colorValue.r and colorValue.g and colorValue.b) then
              table.insert(errors, "Color '" .. colorName .. "' is not a valid Color object")
            end
          elseif colorType == "string" then
            -- Validate color string
            local isValid, err = Theme._Color.validateColor(colorValue)
            if not isValid then
              table.insert(errors, "Color '" .. colorName .. "': " .. err)
            end
          else
            table.insert(errors, "Color '" .. colorName .. "' must be a Color object or string")
          end
        end
      end
    end
  end

  -- Fonts validation (optional)
  if theme.fonts ~= nil then
    if type(theme.fonts) ~= "table" then
      table.insert(errors, "Theme 'fonts' must be a table")
    else
      for fontName, fontPath in pairs(theme.fonts) do
        if type(fontName) ~= "string" then
          table.insert(errors, "Font name must be a string, got " .. type(fontName))
        elseif type(fontPath) ~= "string" then
          table.insert(errors, "Font '" .. fontName .. "' path must be a string")
        end
      end
    end
  end

  -- Components validation (optional)
  if theme.components ~= nil then
    if type(theme.components) ~= "table" then
      table.insert(errors, "Theme 'components' must be a table")
    else
      for componentName, component in pairs(theme.components) do
        if type(component) == "table" then
          -- Validate atlas if present
          if component.atlas ~= nil and type(component.atlas) ~= "string" then
            table.insert(errors, "Component '" .. componentName .. "' atlas must be a string")
          end

          -- Validate insets if present
          if component.insets ~= nil then
            if type(component.insets) ~= "table" then
              table.insert(errors, "Component '" .. componentName .. "' insets must be a table")
            else
              -- If insets are provided, all 4 sides must be present
              for _, side in ipairs({ "left", "top", "right", "bottom" }) do
                if component.insets[side] == nil then
                  table.insert(errors, "Component '" .. componentName .. "' insets must have '" .. side .. "' field")
                elseif type(component.insets[side]) ~= "number" then
                  table.insert(errors, "Component '" .. componentName .. "' insets." .. side .. " must be a number")
                elseif component.insets[side] < 0 then
                  table.insert(errors, "Component '" .. componentName .. "' insets." .. side .. " must be non-negative")
                end
              end
            end
          end

          -- Validate states if present
          if component.states ~= nil then
            if type(component.states) ~= "table" then
              table.insert(errors, "Component '" .. componentName .. "' states must be a table")
            else
              for stateName, stateComponent in pairs(component.states) do
                if type(stateComponent) ~= "table" then
                  table.insert(
                    errors,
                    "Component '" .. componentName .. "' state '" .. stateName .. "' must be a table"
                  )
                end
              end
            end
          end

          -- Validate scaleCorners if present
          if component.scaleCorners ~= nil then
            if type(component.scaleCorners) ~= "number" then
              table.insert(errors, "Component '" .. componentName .. "' scaleCorners must be a number")
            elseif component.scaleCorners <= 0 then
              table.insert(errors, "Component '" .. componentName .. "' scaleCorners must be positive")
            end
          end

          -- Validate scalingAlgorithm if present
          if component.scalingAlgorithm ~= nil then
            if type(component.scalingAlgorithm) ~= "string" then
              table.insert(errors, "Component '" .. componentName .. "' scalingAlgorithm must be a string")
            elseif component.scalingAlgorithm ~= "nearest" and component.scalingAlgorithm ~= "bilinear" then
              table.insert(
                errors,
                "Component '" .. componentName .. "' scalingAlgorithm must be 'nearest' or 'bilinear'"
              )
            end
          end
        end
      end
    end
  end

  -- Scrollbars validation (optional)
  if theme.scrollbars ~= nil then
    if type(theme.scrollbars) ~= "table" then
      table.insert(errors, "Theme 'scrollbars' must be a table")
    else
      for scrollbarName, scrollbarDef in pairs(theme.scrollbars) do
        if type(scrollbarDef) == "table" then
          -- Check if it has bar/frame subcomponents
          if scrollbarDef.bar or scrollbarDef.frame then
            -- Validate bar subcomponent
            if scrollbarDef.bar ~= nil then
              if type(scrollbarDef.bar) ~= "string" and type(scrollbarDef.bar) ~= "table" then
                table.insert(errors, "Scrollbar '" .. scrollbarName .. "' bar must be a string or table")
              end
            end
            -- Validate frame subcomponent
            if scrollbarDef.frame ~= nil then
              if type(scrollbarDef.frame) ~= "string" and type(scrollbarDef.frame) ~= "table" then
                table.insert(errors, "Scrollbar '" .. scrollbarName .. "' frame must be a string or table")
              end
            end
          else
            -- Validate as a single ThemeComponent
            -- Validate atlas if present
            if scrollbarDef.atlas ~= nil and type(scrollbarDef.atlas) ~= "string" then
              table.insert(errors, "Scrollbar '" .. scrollbarName .. "' atlas must be a string")
            end

            -- Validate insets if present
            if scrollbarDef.insets ~= nil then
              if type(scrollbarDef.insets) ~= "table" then
                table.insert(errors, "Scrollbar '" .. scrollbarName .. "' insets must be a table")
              else
                for _, side in ipairs({ "left", "top", "right", "bottom" }) do
                  if scrollbarDef.insets[side] == nil then
                    table.insert(errors, "Scrollbar '" .. scrollbarName .. "' insets must have '" .. side .. "' field")
                  elseif type(scrollbarDef.insets[side]) ~= "number" then
                    table.insert(errors, "Scrollbar '" .. scrollbarName .. "' insets." .. side .. " must be a number")
                  elseif scrollbarDef.insets[side] < 0 then
                    table.insert(
                      errors,
                      "Scrollbar '" .. scrollbarName .. "' insets." .. side .. " must be non-negative"
                    )
                  end
                end
              end
            end

            -- Validate states if present
            if scrollbarDef.states ~= nil then
              if type(scrollbarDef.states) ~= "table" then
                table.insert(errors, "Scrollbar '" .. scrollbarName .. "' states must be a table")
              else
                for stateName, stateComponent in pairs(scrollbarDef.states) do
                  if type(stateComponent) ~= "table" then
                    table.insert(
                      errors,
                      "Scrollbar '" .. scrollbarName .. "' state '" .. stateName .. "' must be a table"
                    )
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- contentAutoSizingMultiplier validation (optional)
  if theme.contentAutoSizingMultiplier ~= nil then
    if type(theme.contentAutoSizingMultiplier) ~= "table" then
      table.insert(errors, "Theme 'contentAutoSizingMultiplier' must be a table")
    else
      if theme.contentAutoSizingMultiplier.width ~= nil then
        if type(theme.contentAutoSizingMultiplier.width) ~= "number" then
          table.insert(errors, "contentAutoSizingMultiplier.width must be a number")
        elseif theme.contentAutoSizingMultiplier.width <= 0 then
          table.insert(errors, "contentAutoSizingMultiplier.width must be positive")
        end
      end
      if theme.contentAutoSizingMultiplier.height ~= nil then
        if type(theme.contentAutoSizingMultiplier.height) ~= "number" then
          table.insert(errors, "contentAutoSizingMultiplier.height must be a number")
        elseif theme.contentAutoSizingMultiplier.height <= 0 then
          table.insert(errors, "contentAutoSizingMultiplier.height must be positive")
        end
      end
    end
  end

  -- Global atlas validation (optional)
  if theme.atlas ~= nil then
    if type(theme.atlas) ~= "string" then
      table.insert(errors, "Theme 'atlas' must be a string")
    end
  end

  -- Strict mode: warn about unknown fields
  if options.strict then
    local knownFields = {
      name = true,
      atlas = true,
      components = true,
      scrollbars = true,
      colors = true,
      fonts = true,
      contentAutoSizingMultiplier = true,
    }
    for field in pairs(theme) do
      if not knownFields[field] then
        table.insert(errors, "Unknown field '" .. field .. "' in theme")
      end
    end
  end

  return #errors == 0, errors
end

--- Clean up malformed theme data to make it usable without crashing
--- Use this to robustly handle user-created or external themes
---@param theme table? The theme to sanitize
---@return table sanitized The sanitized theme
function Theme.sanitizeTheme(theme)
  local sanitized = {}

  -- Handle nil theme
  if theme == nil then
    return { name = "Invalid Theme" }
  end

  -- Handle non-table theme
  if type(theme) ~= "table" then
    return { name = "Invalid Theme" }
  end

  -- Sanitize name
  if type(theme.name) == "string" and theme.name ~= "" then
    sanitized.name = theme.name
  else
    sanitized.name = "Unnamed Theme"
  end

  -- Sanitize colors
  if type(theme.colors) == "table" then
    sanitized.colors = {}
    for colorName, colorValue in pairs(theme.colors) do
      if type(colorName) == "string" then
        local colorType = type(colorValue)
        if colorType == "table" and colorValue.r and colorValue.g and colorValue.b then
          -- Valid Color object
          sanitized.colors[colorName] = colorValue
        elseif colorType == "string" then
          -- Try to validate color string
          local isValid = Theme._Color.validateColor(colorValue)
          if isValid then
            sanitized.colors[colorName] = colorValue
          else
            -- Provide fallback color
            sanitized.colors[colorName] = Theme._Color.new(0, 0, 0, 1)
          end
        end
      end
    end
  end

  -- Sanitize fonts
  if type(theme.fonts) == "table" then
    sanitized.fonts = {}
    for fontName, fontPath in pairs(theme.fonts) do
      if type(fontName) == "string" and type(fontPath) == "string" then
        sanitized.fonts[fontName] = fontPath
      end
    end
  end

  -- Sanitize components (preserve as-is, they're complex)
  if type(theme.components) == "table" then
    sanitized.components = theme.components
  end

  -- Sanitize scrollbars (preserve as-is, they're complex like components)
  if type(theme.scrollbars) == "table" then
    sanitized.scrollbars = theme.scrollbars
  end

  -- Sanitize contentAutoSizingMultiplier
  if type(theme.contentAutoSizingMultiplier) == "table" then
    sanitized.contentAutoSizingMultiplier = {}
    if type(theme.contentAutoSizingMultiplier.width) == "number" and theme.contentAutoSizingMultiplier.width > 0 then
      sanitized.contentAutoSizingMultiplier.width = theme.contentAutoSizingMultiplier.width
    end
    if type(theme.contentAutoSizingMultiplier.height) == "number" and theme.contentAutoSizingMultiplier.height > 0 then
      sanitized.contentAutoSizingMultiplier.height = theme.contentAutoSizingMultiplier.height
    end
  end

  -- Sanitize atlas
  if type(theme.atlas) == "string" then
    sanitized.atlas = theme.atlas
  end

  return sanitized
end

return Theme
