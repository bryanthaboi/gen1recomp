local UTF8 = require((...):match("(.-)[^%.]+$") .. "UTF8")

---@class Renderer
---@field backgroundColor Color
---@field borderColor Color
---@field opacity number
---@field border {top:boolean, right:boolean, bottom:boolean, left:boolean}
---@field cornerRadius {topLeft:number, topRight:number, bottomLeft:number, bottomRight:number}
---@field theme string?
---@field themeComponent string?
---@field _themeState string
---@field imagePath string?
---@field image love.Image?
---@field _loadedImage love.Image?
---@field objectFit string
---@field objectPosition string
---@field imageOpacity number
---@field contentBlur {intensity:number, quality:number}?
---@field backdropBlur {intensity:number, quality:number}?
---@field _blurInstance table?
---@field _element Element?
---@field _Color Color
---@field _RoundedRect table
---@field _NinePatch table
---@field _ImageRenderer table
---@field _ImageCache table
---@field _Theme table
---@field _Transform Transform
---@field _Blur Blur
---@field _utils table
---@field _FONT_CACHE table
---@field _TextAlign table
---@field _ErrorHandler ErrorHandler
---@field _Performance Performance? Performance module dependency
local Renderer = {}
Renderer.__index = Renderer

--- Initialize module with shared dependencies
---@param deps table Dependencies {ErrorHandler, Performance}
function Renderer.init(deps)
  Renderer._ErrorHandler = deps.ErrorHandler
  Renderer._Performance = deps.Performance
end

--- Create a new Renderer instance
---@param config table Configuration table with rendering properties
---@param deps table Dependencies {Color, RoundedRect, NinePatch, ImageRenderer, ImageCache, Theme, Blur, Transform, utils}
function Renderer.new(config, deps)
  local Color = deps.Color
  local ImageCache = deps.ImageCache

  local self = setmetatable({}, Renderer)

  -- Store dependencies for instance methods
  self._Color = Color
  self._RoundedRect = deps.RoundedRect
  self._NinePatch = deps.NinePatch
  self._ImageRenderer = deps.ImageRenderer
  self._ImageCache = ImageCache
  self._Theme = deps.Theme
  self._Blur = deps.Blur
  self._Transform = deps.Transform
  self._utils = deps.utils
  self._FONT_CACHE = deps.utils.FONT_CACHE
  self._TextAlign = deps.utils.enums.TextAlign
  self._TextAlignVertical = deps.utils.enums.TextAlignVertical

  -- Visual properties
  self.backgroundColor = config.backgroundColor or Color.new(0, 0, 0, 0)
  self.borderColor = config.borderColor or Color.new(0, 0, 0, 1)
  self.opacity = config.opacity or 1

  -- NOTE: border is intentionally NOT cached here. Renderer:draw resolves it from
  -- element.border (source of truth) so retained-mode bare writes and
  -- setProperty("border", ...) both take effect immediately.

  -- Corner radius
  self.cornerRadius = config.cornerRadius
    or {
      topLeft = 0,
      topRight = 0,
      bottomLeft = 0,
      bottomRight = 0,
    }

  -- Theme properties
  self.theme = config.theme
  self.themeComponent = config.themeComponent
  self._themeState = "normal"

  -- Image properties
  self.imagePath = config.imagePath
  self.image = config.image
  self._loadedImage = nil
  self.objectFit = config.objectFit or "fill"
  self.objectPosition = config.objectPosition or "center center"
  self.imageOpacity = config.imageOpacity or 1
  self.imageRepeat = config.imageRepeat or "no-repeat"
  self.imageTint = config.imageTint

  -- Blur effects
  self.contentBlur = config.contentBlur
  self.backdropBlur = config.backdropBlur
  self._blurInstance = nil

  -- Load image if path provided
  if self.imagePath and not self.image then
    local loadedImage = ImageCache.load(self.imagePath)
    if loadedImage then
      self._loadedImage = loadedImage
    else
      self._loadedImage = nil
    end
  elseif self.image then
    self._loadedImage = self.image
  else
    self._loadedImage = nil
  end

  return self
end

--- Get or create blur instance for this element
---@return table|nil Blur instance or nil
function Renderer:getBlurInstance()
  -- Determine quality from blur settings
  local quality = "medium"
  if self.contentBlur and self.contentBlur.quality then
    quality = self.contentBlur.quality
  elseif self.backdropBlur and self.backdropBlur.quality then
    quality = self.backdropBlur.quality
  end

  -- Map string quality to numeric quality (1-10)
  local numericQuality = 5 -- default medium
  if type(quality) == "string" then
    if quality == "low" then
      numericQuality = 3
    elseif quality == "medium" then
      numericQuality = 5
    elseif quality == "high" then
      numericQuality = 8
    end
  elseif type(quality) == "number" then
    numericQuality = quality
  end

  -- Create or reuse blur instance
  if not self._blurInstance or self._blurInstance.quality ~= numericQuality then
    self._blurInstance = self._Blur.new({ quality = numericQuality })
  end

  return self._blurInstance
end

--- Set theme state (normal, hover, pressed, disabled, active)
---@param state string The theme state
function Renderer:setThemeState(state)
  self._themeState = state
end

--- Execute a single core draw command (background, image, theme, borders).
--- Commands are plain tables: { type = "background"|"image"|"theme"|"borders", ... }
---@param cmd table Command table
---@param ctx table Resolved draw context
function Renderer:_executeDrawCommand(cmd, ctx)
  if cmd.type == "background" then
    local c = self._Color.new(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a * ctx.opacity)
    love.graphics.setColor(c:toRGBA())
    self._RoundedRect.draw("fill", ctx.x, ctx.y, ctx.borderBoxWidth, ctx.borderBoxHeight, ctx.cornerRadius)
  elseif cmd.type == "image" then
    -- Image value props (imageOpacity/imageRepeat/imageTint/objectFit/
    -- objectPosition) and imagePath are read from the element as the single
    -- source of truth, so retained-mode bare writes (`element.imageOpacity = 0.5`),
    -- the setImage* setters, and setProperty(...) are all immediately
    -- consistent. The renderer's own config is a fallback for standalone
    -- Renderer usage with a sparse element (mirrors `element.onEvent or
    -- self.onEvent`); the integrated path always supplies an element whose
    -- _applyProps-bound values take precedence. _loadedImage intentionally
    -- remains on the renderer (the resolved love.Image from the Imageable load
    -- pipeline). See TestRetainedPropertyConsistency.
    local el = self._element
    local imageOpacity = (el and el.imageOpacity) or self.imageOpacity
    local imageRepeat = (el and el.imageRepeat) or self.imageRepeat
    local imageTint = (el and el.imageTint) or self.imageTint
    local objectFit = (el and el.objectFit) or self.objectFit
    local objectPosition = (el and el.objectPosition) or self.objectPosition
    local imagePath = (el and el.imagePath) or self.imagePath
    if not self._loadedImage then
      return
    end
    local img = self._loadedImage
    local imageX = ctx.x + ctx.paddingLeft
    local imageY = ctx.y + ctx.paddingTop
    local finalOpacity = ctx.opacity * imageOpacity
    local hasCornerRadius = false
    if ctx.cornerRadius then
      if type(ctx.cornerRadius) == "number" then
        hasCornerRadius = ctx.cornerRadius > 0
      else
        hasCornerRadius = ctx.cornerRadius.topLeft > 0
          or ctx.cornerRadius.topRight > 0
          or ctx.cornerRadius.bottomLeft > 0
          or ctx.cornerRadius.bottomRight > 0
      end
    end
    if hasCornerRadius then
      local success, err = pcall(function()
        love.graphics.stencil(function()
          self._RoundedRect.draw("fill", ctx.x, ctx.y, ctx.borderBoxWidth, ctx.borderBoxHeight, ctx.cornerRadius)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
      end)
      if not success then
        if err and err:match("stencil") then
          local cr = ctx.cornerRadius
          local crStr = type(cr) == "number" and tostring(cr)
            or string.format("TL:%d TR:%d BL:%d BR:%d", cr.topLeft, cr.topRight, cr.bottomLeft, cr.bottomRight)
          Renderer._ErrorHandler:warn(
            "Renderer",
            "IMG_001",
            { imagePath = imagePath or "unknown", cornerRadius = crStr, error = tostring(err) }
          )
          hasCornerRadius = false
        else
          error(err, 2)
        end
      end
    end
    if imageRepeat and imageRepeat ~= "no-repeat" then
      self._ImageRenderer.drawTiled(
        img,
        imageX,
        imageY,
        ctx.contentWidth,
        ctx.contentHeight,
        imageRepeat,
        finalOpacity,
        imageTint
      )
    else
      self._ImageRenderer.draw(
        img,
        imageX,
        imageY,
        ctx.contentWidth,
        ctx.contentHeight,
        objectFit,
        objectPosition,
        finalOpacity,
        imageTint
      )
    end
    if hasCornerRadius then
      love.graphics.setStencilTest()
    end
  elseif cmd.type == "theme" then
    if not cmd.themeComponent then
      return
    end
    local themeToUse = nil
    if self.theme then
      themeToUse = self._Theme.get(self.theme)
      if not themeToUse then
        pcall(function()
          self._Theme.load(self.theme)
        end)
        themeToUse = self._Theme.get(self.theme)
      end
    else
      themeToUse = self._Theme.getActive()
    end
    if not themeToUse then
      return
    end
    local component = themeToUse.components[cmd.themeComponent]
    if not component then
      return
    end
    local state = self._themeState
    if state and component.states and component.states[state] then
      component = component.states[state]
    end
    local atlasToUse = component._loadedAtlas or themeToUse.atlas
    if atlasToUse and component.regions then
      local r = component.regions
      if
        r.topLeft
        and r.topCenter
        and r.topRight
        and r.middleLeft
        and r.middleCenter
        and r.middleRight
        and r.bottomLeft
        and r.bottomCenter
        and r.bottomRight
      then
        self._NinePatch.draw(
          component,
          atlasToUse,
          ctx.x,
          ctx.y,
          ctx.borderBoxWidth,
          ctx.borderBoxHeight,
          ctx.opacity,
          cmd.scaleCorners,
          cmd.scalingAlgorithm
        )
      end
    end
  elseif cmd.type == "borders" then
    local border = cmd.border
    if not border then
      return
    end
    local bc = cmd.borderColor
    local borderColorWithOpacity = self._Color.new(bc.r, bc.g, bc.b, bc.a * ctx.opacity)
    love.graphics.setColor(borderColorWithOpacity:toRGBA())
    local bw, bh = ctx.borderBoxWidth, ctx.borderBoxHeight
    if type(border) == "number" then
      love.graphics.setLineWidth(border)
      self._RoundedRect.draw("line", ctx.x, ctx.y, bw, bh, ctx.cornerRadius)
      love.graphics.setLineWidth(1)
    else
      local allBorders = border.top and border.bottom and border.left and border.right
      local uniformWidth = allBorders
        and type(border.top) == "number"
        and border.top == border.right
        and border.top == border.bottom
        and border.top == border.left
      if uniformWidth then
        love.graphics.setLineWidth(border.top)
        self._RoundedRect.draw("line", ctx.x, ctx.y, bw, bh, ctx.cornerRadius)
        love.graphics.setLineWidth(1)
      else
        if border.top then
          love.graphics.setLineWidth(type(border.top) == "number" and border.top or 1)
          love.graphics.line(ctx.x, ctx.y, ctx.x + bw, ctx.y)
        end
        if border.bottom then
          love.graphics.setLineWidth(type(border.bottom) == "number" and border.bottom or 1)
          love.graphics.line(ctx.x, ctx.y + bh, ctx.x + bw, ctx.y + bh)
        end
        if border.left then
          love.graphics.setLineWidth(type(border.left) == "number" and border.left or 1)
          love.graphics.line(ctx.x, ctx.y, ctx.x, ctx.y + bh)
        end
        if border.right then
          love.graphics.setLineWidth(type(border.right) == "number" and border.right or 1)
          love.graphics.line(ctx.x + bw, ctx.y, ctx.x + bw, ctx.y + bh)
        end
        love.graphics.setLineWidth(1)
      end
    end
  end
end

--- Build the render command buffer: resolve draw properties once from the
--- element (source of truth) and return a flat command list + draw context.
---@param element table Element instance
---@param backdropCanvas table|nil
---@return table cmds, table ctx Command list and resolved context
function Renderer:_buildCommands(element, backdropCanvas)
  local opacity = element.opacity ~= nil and element.opacity or 1
  local backgroundColor = element.backgroundColor or self._Color.new(0, 0, 0, 0)
  local borderColor = element.borderColor or self._Color.new(0, 0, 0, 1)
  local cornerRadius = element.cornerRadius ~= nil and element.cornerRadius or nil
  local themeComponent = element.themeComponent
  local border = element.border
  local borderBoxWidth = element._borderBoxWidth or (element.width + element.padding.left + element.padding.right)
  local borderBoxHeight = element._borderBoxHeight or (element.height + element.padding.top + element.padding.bottom)

  -- Handle opacity during animation
  local drawBackgroundColor = backgroundColor
  if element.animation then
    local anim = element.animation:interpolate()
    if anim.opacity then
      drawBackgroundColor = self._Color.new(backgroundColor.r, backgroundColor.g, backgroundColor.b, anim.opacity)
    end
  end

  -- Build resolved context (shared by all commands — eliminates per-method params)
  local ctx = {
    x = element.x,
    y = element.y,
    opacity = opacity,
    cornerRadius = cornerRadius,
    borderBoxWidth = borderBoxWidth,
    borderBoxHeight = borderBoxHeight,
    paddingLeft = element.padding.left,
    paddingTop = element.padding.top,
    contentWidth = element.width,
    contentHeight = element.height,
    backdropCanvas = backdropCanvas,
  }

  -- Build command list (conditional — only emit layers that have data)
  local cmds = {}
  local n = 0

  -- LAYER 0.5: backdrop blur (handled separately, not a command — needs canvas access)
  if self.backdropBlur and self.backdropBlur.radius > 0 then
    n = n + 1
    cmds[n] = { type = "backdropBlur", radius = self.backdropBlur.radius } -- executed before background
  end

  -- LAYER 1: background
  n = n + 1
  cmds[n] = { type = "background", color = drawBackgroundColor }

  -- LAYER 1.5: image (always emit; _executeCommand early-exits if no image)
  n = n + 1
  cmds[n] = { type = "image" }

  -- LAYER 2: theme 9-patch
  n = n + 1
  cmds[n] = {
    type = "theme",
    themeComponent = themeComponent,
    scaleCorners = element.scaleCorners,
    scalingAlgorithm = element.scalingAlgorithm,
  }

  -- LAYER 3: borders
  n = n + 1
  cmds[n] = { type = "borders", borderColor = borderColor, border = border }

  -- LAYER 4: text (cursor, selection, placeholder, password masking)
  n = n + 1
  cmds[n] = { type = "text" }

  -- LAYER 4.5: custom draw callback (if provided)
  if element.customDraw then
    n = n + 1
    cmds[n] = { type = "customDraw" }
  end

  -- NOTE: pressed-state overlay (former Layer 5) is now owned by the Clickable
  -- behavior's onDraw, dispatched from Element:draw. The renderer no longer
  -- branches on element.onEvent for press feedback.

  return cmds, ctx
end

--- Execute a special render command (backdropBlur, customDraw, pressedState).
--- These interact with love.graphics state in non-uniform ways and are handled separately
--- from the core draw commands (background/image/theme/borders).
---@param cmd table Command table
---@param ctx table Resolved draw context
function Renderer:_executeSpecialCommand(cmd, ctx)
  if cmd.type == "backdropBlur" then
    if ctx.backdropCanvas then
      local blurInstance = self:getBlurInstance()
      if blurInstance then
        local eid = self._element and self._element.id and self._element.id ~= "" and self._element.id or nil
        blurInstance:applyBackdropCached(
          cmd.radius,
          ctx.x,
          ctx.y,
          ctx.borderBoxWidth,
          ctx.borderBoxHeight,
          ctx.backdropCanvas,
          eid
        )
      end
    end
  elseif cmd.type == "text" then
    self:drawText(self._element)
  elseif cmd.type == "customDraw" then
    love.graphics.push()
    love.graphics.setColor(1, 1, 1, 1)
    self._element.customDraw(self._element)
    love.graphics.pop()
  end
end

--- Main draw method - renders all visual layers via command buffer.
---@param element Element The parent Element instance
---@param backdropCanvas table|nil Backdrop canvas for backdrop blur
function Renderer:draw(element, backdropCanvas)
  self._element = element -- cache for customDraw/pressedState

  if not element then
    Renderer._ErrorHandler:warn("Renderer", "SYS_002", { method = "draw" })
    return
  end

  -- Start performance timing
  local elementId
  if Renderer._Performance and Renderer._Performance.enabled then
    elementId = element.id or "unnamed"
    Renderer._Performance:startTimer("render_" .. elementId)
    Renderer._Performance:incrementCounter("draw_calls", 1)
  end

  -- Early exit if element is invisible (optimization)
  if element.opacity ~= nil and element.opacity <= 0 then
    if Renderer._Performance and Renderer._Performance.enabled and elementId then
      Renderer._Performance:stopTimer("render_" .. elementId)
    end
    return
  end

  -- Build command buffer + resolve draw context once
  local cmds, ctx = self:_buildCommands(element, backdropCanvas)

  -- Apply transform if exists
  local hasTransform = element.transform and self._Transform and not self._Transform.isIdentity(element.transform)
  if hasTransform then
    self._Transform.apply(element.transform, element.x, element.y, element.width, element.height)
  end

  -- Execute all commands in order
  for _, cmd in ipairs(cmds) do
    -- Draw commands (background, image, theme, borders) use the core executor;
    -- special commands (backdropBlur, customDraw, pressedState) are handled in _executeCommand.
    local typ = cmd.type
    if typ == "background" or typ == "image" or typ == "theme" or typ == "borders" then
      self:_executeDrawCommand(cmd, ctx)
    else
      self:_executeSpecialCommand(cmd, ctx)
    end
  end

  -- Unapply transform if it was applied
  if hasTransform then
    self._Transform.unapply()
  end

  -- Stop performance timing
  if Renderer._Performance and Renderer._Performance.enabled and elementId then
    Renderer._Performance:stopTimer("render_" .. elementId)
  end
end

--- Get font for element (resolves from theme or fontFamily)
---@param element table Reference to the parent Element instance
---@return love.Font
function Renderer:getFont(element)
  return self._utils.getFont(element.textSize, element.fontFamily, element.themeComponent, element._themeManager)
end

--- Wrap a line of text based on element's textWrap mode
---@param element table Reference to the parent Element instance
---@param line string The line of text to wrap
---@param maxWidth number Maximum width for wrapping
---@return table Array of {text, startIdx, endIdx}
function Renderer:wrapLine(element, line, maxWidth)
  -- UTF-8 support
  local utf8 = UTF8

  if not element.editable then
    return { { text = line, startIdx = 0, endIdx = utf8.len(line) } }
  end

  local font = self:getFont(element)
  local wrappedParts = {}
  local currentLine = ""
  local startIdx = 0

  -- Helper function to extract a UTF-8 character by character index
  local function getUtf8Char(str, charIndex)
    local byteStart = utf8.offset(str, charIndex)
    if not byteStart then
      return ""
    end
    local byteEnd = utf8.offset(str, charIndex + 1)
    if byteEnd then
      return str:sub(byteStart, byteEnd - 1)
    else
      return str:sub(byteStart)
    end
  end

  if element.textWrap == "word" then
    -- Tokenize into words and whitespace, preserving exact spacing
    local tokens = {}
    local pos = 1
    local lineLen = utf8.len(line)

    while pos <= lineLen do
      -- Check if current position is whitespace
      local char = getUtf8Char(line, pos)
      if char:match("%s") then
        -- Collect whitespace sequence
        local wsStart = pos
        while pos <= lineLen and getUtf8Char(line, pos):match("%s") do
          pos = pos + 1
        end
        table.insert(tokens, {
          type = "space",
          text = line:sub(utf8.offset(line, wsStart), utf8.offset(line, pos) and utf8.offset(line, pos) - 1 or #line),
          startPos = wsStart - 1,
          length = pos - wsStart,
        })
      else
        -- Collect word (non-whitespace sequence)
        local wordStart = pos
        while pos <= lineLen and not getUtf8Char(line, pos):match("%s") do
          pos = pos + 1
        end
        table.insert(tokens, {
          type = "word",
          text = line:sub(utf8.offset(line, wordStart), utf8.offset(line, pos) and utf8.offset(line, pos) - 1 or #line),
          startPos = wordStart - 1,
          length = pos - wordStart,
        })
      end
    end

    -- Process tokens and wrap
    local charPos = 0 -- Track our position in the original line
    for _, token in ipairs(tokens) do
      if token.type == "word" then
        local testLine = currentLine .. token.text
        local width = font:getWidth(testLine)

        if width > maxWidth and currentLine ~= "" then
          -- Current line is full, wrap before this word
          local currentLineLen = utf8.len(currentLine)
          table.insert(wrappedParts, {
            text = currentLine,
            startIdx = startIdx,
            endIdx = startIdx + currentLineLen,
          })
          startIdx = charPos
          currentLine = token.text
          charPos = charPos + token.length

          -- Check if the word itself is too long - if so, break it with character wrapping
          if font:getWidth(token.text) > maxWidth then
            local wordLen = utf8.len(token.text)
            local charLine = ""
            local charStartIdx = startIdx

            for j = 1, wordLen do
              local char = getUtf8Char(token.text, j)
              local testCharLine = charLine .. char
              local charWidth = font:getWidth(testCharLine)

              if charWidth > maxWidth and charLine ~= "" then
                table.insert(wrappedParts, {
                  text = charLine,
                  startIdx = charStartIdx,
                  endIdx = charStartIdx + utf8.len(charLine),
                })
                charStartIdx = charStartIdx + utf8.len(charLine)
                charLine = char
              else
                charLine = testCharLine
              end
            end

            currentLine = charLine
            startIdx = charStartIdx
          end
        elseif width > maxWidth and currentLine == "" then
          -- Word is too long to fit on a line by itself - use character wrapping
          local wordLen = utf8.len(token.text)
          local charLine = ""
          local charStartIdx = startIdx

          for j = 1, wordLen do
            local char = getUtf8Char(token.text, j)
            local testCharLine = charLine .. char
            local charWidth = font:getWidth(testCharLine)

            if charWidth > maxWidth and charLine ~= "" then
              table.insert(wrappedParts, {
                text = charLine,
                startIdx = charStartIdx,
                endIdx = charStartIdx + utf8.len(charLine),
              })
              charStartIdx = charStartIdx + utf8.len(charLine)
              charLine = char
            else
              charLine = testCharLine
            end
          end

          currentLine = charLine
          startIdx = charStartIdx
          charPos = charPos + token.length
        else
          currentLine = testLine
          charPos = charPos + token.length
        end
      else
        -- It's whitespace - add to current line
        currentLine = currentLine .. token.text
        charPos = charPos + token.length
      end
    end
  else
    -- Character wrapping
    local lineLength = utf8.len(line)
    for i = 1, lineLength do
      local char = getUtf8Char(line, i)
      local testLine = currentLine .. char
      local width = font:getWidth(testLine)

      if width > maxWidth and currentLine ~= "" then
        table.insert(wrappedParts, {
          text = currentLine,
          startIdx = startIdx,
          endIdx = startIdx + utf8.len(currentLine),
        })
        currentLine = char
        startIdx = i - 1
      else
        currentLine = testLine
      end
    end
  end

  -- Add remaining text
  if currentLine ~= "" then
    table.insert(wrappedParts, {
      text = currentLine,
      startIdx = startIdx,
      endIdx = startIdx + utf8.len(currentLine),
    })
  end

  -- Ensure at least one part
  if #wrappedParts == 0 then
    table.insert(wrappedParts, {
      text = "",
      startIdx = 0,
      endIdx = 0,
    })
  end

  return wrappedParts
end

--- Draw text content (includes text, cursor, selection, placeholder, password masking)
---@param element table Reference to the parent Element instance
function Renderer:drawText(element)
  -- Update text layout if dirty (for multiline auto-grow)
  if element._textEditor then
    element._textEditor:_updateTextIfDirty(element)
    element._textEditor:updateAutoGrowHeight(element)
  end

  -- For editable elements, use TextEditor buffer; for non-editable, use text
  local displayText = element._textEditor and element._textEditor:getText() or element.text
  local isPlaceholder = false

  -- Show placeholder if editable and empty
  if element.editable and (not displayText or displayText == "") and element.placeholder then
    displayText = element.placeholder
    isPlaceholder = true
  end

  -- Apply password masking if enabled
  if element.passwordMode and displayText and displayText ~= "" and not isPlaceholder then
    local maskedText = string.rep("•", UTF8.len(displayText))
    displayText = maskedText
  end

  if displayText and displayText ~= "" then
    local textColor = isPlaceholder
        and self._Color.new(
          element.textColor.r * 0.5,
          element.textColor.g * 0.5,
          element.textColor.b * 0.5,
          element.textColor.a * 0.5
        )
      or element.textColor
    local textColorOpacity = element.opacity ~= nil and element.opacity or (self.opacity or 1)
    local textColorWithOpacity = self._Color.new(textColor.r, textColor.g, textColor.b, textColor.a * textColorOpacity)
    love.graphics.setColor(textColorWithOpacity:toRGBA())

    local origFont = love.graphics.getFont()
    if element.textSize then
      -- Use cached font instead of creating new one every frame
      local font =
        self._utils.getFont(element.textSize, element.fontFamily, element.themeComponent, element._themeManager)
      love.graphics.setFont(font)
    end
    local font = love.graphics.getFont()
    local textWidth = font:getWidth(displayText)
    local textHeight = font:getHeight()
    local tx, ty

    -- Text is drawn in the content box (inside padding)
    -- For 9-patch components, use contentPadding if available
    local textPaddingLeft = element.padding.left
    local textPaddingTop = element.padding.top
    local textAreaWidth = element.width
    local textAreaHeight = element.height

    -- Check if we should use 9-patch contentPadding for text positioning
    local scaledContentPadding = element:getScaledContentPadding()
    if scaledContentPadding then
      local borderBoxWidth = element._borderBoxWidth or (element.width + element.padding.left + element.padding.right)
      local borderBoxHeight = element._borderBoxHeight
        or (element.height + element.padding.top + element.padding.bottom)

      textPaddingLeft = scaledContentPadding.left
      textPaddingTop = scaledContentPadding.top
      textAreaWidth = borderBoxWidth - scaledContentPadding.left - scaledContentPadding.right
      textAreaHeight = borderBoxHeight - scaledContentPadding.top - scaledContentPadding.bottom
    end

    local contentX = element.x + textPaddingLeft
    local contentY = element.y + textPaddingTop

    -- Resolve horizontal and vertical alignment (new format with backward compatibility)
    local hAlign = element.textAlignHorizontal or element.textAlign or self._TextAlign.START
    local vAlign = element.textAlignVertical or self._TextAlignVertical.START

    -- Check if text wrapping is enabled
    if element.textWrap and (element.textWrap == "word" or element.textWrap == "char" or element.textWrap == true) then
      -- Use printf for wrapped text (horizontal alignment only)
      local align = "left"
      if hAlign == self._TextAlign.CENTER then
        align = "center"
      elseif hAlign == self._TextAlign.END then
        align = "right"
      elseif hAlign == self._TextAlign.JUSTIFY then
        align = "justify"
      end

      tx = contentX
      ty = contentY

      -- Use printf with the available width for wrapping
      love.graphics.printf(displayText, tx, ty, textAreaWidth, align)
    else
      -- Use regular print for non-wrapped text
      -- Horizontal alignment
      if hAlign == self._TextAlign.START then
        tx = contentX
      elseif hAlign == self._TextAlign.CENTER then
        tx = contentX + (textAreaWidth - textWidth) / 2
      elseif hAlign == self._TextAlign.END then
        tx = contentX + textAreaWidth - textWidth - 10
      else -- JUSTIFY or unknown
        tx = contentX
      end

      -- Vertical alignment
      if vAlign == self._TextAlignVertical.START then
        ty = contentY
      elseif vAlign == self._TextAlignVertical.CENTER then
        ty = contentY + (textAreaHeight - textHeight) / 2
      elseif vAlign == self._TextAlignVertical.END then
        ty = contentY + textAreaHeight - textHeight
      else
        ty = contentY
      end

      -- Apply scroll offset for editable single-line inputs
      if element.editable and not element.multiline and element._textScrollX then
        tx = tx - element._textScrollX
      end

      -- Use scissor to clip text to content area for editable inputs
      if element.editable and not element.multiline then
        love.graphics.setScissor(contentX, contentY, textAreaWidth, textAreaHeight)
      end

      love.graphics.print(displayText, tx, ty)

      -- Reset scissor
      if element.editable and not element.multiline then
        love.graphics.setScissor()
      end
    end

    -- Draw cursor for focused editable elements (even if text is empty)
    if element._textEditor and element._textEditor:isFocused() and element._textEditor._cursorVisible then
      local cursorColor = element.cursorColor or element.textColor
      local elemOpacity = element.opacity ~= nil and element.opacity or (self.opacity or 1)
      local cursorWithOpacity =
        self._Color.new(cursorColor.r, cursorColor.g, cursorColor.b, cursorColor.a * elemOpacity)
      love.graphics.setColor(cursorWithOpacity:toRGBA())

      -- Calculate cursor position using TextEditor method
      local cursorRelX, cursorRelY = element._textEditor:_getCursorScreenPosition(element)
      local cursorX = contentX + cursorRelX
      local cursorY = contentY + cursorRelY
      local cursorHeight = textHeight

      -- Apply scroll offset for single-line inputs
      if not element.multiline and element._textEditor._textScrollX then
        cursorX = cursorX - element._textEditor._textScrollX
      end

      -- Apply scissor for single-line editable inputs
      if not element.multiline then
        love.graphics.setScissor(contentX, contentY, textAreaWidth, textAreaHeight)
      end

      -- Draw cursor line
      love.graphics.rectangle("fill", cursorX, cursorY, 2, cursorHeight)

      -- Reset scissor
      if not element.multiline then
        love.graphics.setScissor()
      end
    end

    -- Draw selection highlight for editable elements
    if element._textEditor and element._textEditor:isFocused() and element._textEditor:hasSelection() then
      -- For editable elements, check TextEditor buffer instead of element.text
      local textBuffer = element._textEditor:getText()
      if textBuffer and textBuffer ~= "" then
        local selStart, selEnd = element._textEditor:getSelection()
        local selectionColor = element.selectionColor or self._Color.new(0.3, 0.5, 0.8, 0.5)
        local elemOpacity = element.opacity ~= nil and element.opacity or (self.opacity or 1)
        local selectionWithOpacity =
          self._Color.new(selectionColor.r, selectionColor.g, selectionColor.b, selectionColor.a * elemOpacity)

        -- Get selection rectangles from TextEditor
        local selectionRects = element._textEditor:_getSelectionRects(element, selStart, selEnd)

        -- Apply scissor for single-line editable inputs
        if not element.multiline then
          love.graphics.setScissor(contentX, contentY, textAreaWidth, textAreaHeight)
        end

        -- Draw selection background rectangles
        love.graphics.setColor(selectionWithOpacity:toRGBA())
        for _, rect in ipairs(selectionRects) do
          local rectX = contentX + rect.x
          local rectY = contentY + rect.y
          if not element.multiline and element._textEditor._textScrollX then
            rectX = rectX - element._textEditor._textScrollX
          end
          love.graphics.rectangle("fill", rectX, rectY, rect.width, rect.height)
        end

        -- Reset scissor
        if not element.multiline then
          love.graphics.setScissor()
        end
      end
    end

    if element.textSize then
      love.graphics.setFont(origFont)
    end
  end

  -- Draw cursor for focused editable elements even when empty
  if
    element._textEditor
    and element._textEditor:isFocused()
    and element._textEditor._cursorVisible
    and (not displayText or displayText == "")
  then
    -- Set up font for cursor rendering
    local origFont = love.graphics.getFont()
    if element.textSize then
      local font =
        self._utils.getFont(element.textSize, element.fontFamily, element.themeComponent, element._themeManager)
      love.graphics.setFont(font)
    end

    local font = love.graphics.getFont()
    local textHeight = font:getHeight()

    -- Calculate text area position
    local textPaddingLeft = element.padding.left
    local textPaddingTop = element.padding.top
    local scaledContentPadding = element:getScaledContentPadding()
    if scaledContentPadding then
      textPaddingLeft = scaledContentPadding.left
      textPaddingTop = scaledContentPadding.top
    end

    local contentX = element.x + textPaddingLeft
    local contentY = element.y + textPaddingTop

    -- Draw cursor
    local cursorColor = element.cursorColor or element.textColor
    local elemOpacity = element.opacity ~= nil and element.opacity or (self.opacity or 1)
    local cursorWithOpacity = self._Color.new(cursorColor.r, cursorColor.g, cursorColor.b, cursorColor.a * elemOpacity)
    love.graphics.setColor(cursorWithOpacity:toRGBA())
    love.graphics.rectangle("fill", contentX, contentY, 2, textHeight)

    if element.textSize then
      love.graphics.setFont(origFont)
    end
  end
end

--- Draw scrollbars (both vertical and horizontal)
---@param element table Reference to the parent Element instance
---@param x number X position
---@param y number Y position
---@param w number Width
---@param h number Height
---@param dims table Scrollbar dimensions from _calculateScrollbarDimensions
function Renderer:drawScrollbars(element, x, y, w, h, dims)
  -- Try to get themed scrollbar component
  local scrollbarComponent = nil
  if element.scrollBarStyle or self._Theme.hasActive() then
    scrollbarComponent = self._Theme.getScrollbar(element.scrollBarStyle)
  end

  -- Vertical scrollbar
  if dims.vertical.visible and not element.hideScrollbars.vertical then
    -- Position scrollbar within content area (x, y is border-box origin)
    local contentX = x + element.padding.left
    local contentY = y + element.padding.top
    local trackX = contentX + w - element.scrollbarWidth - element.scrollbarPadding
    local trackY = contentY + element.scrollbarPadding

    -- Check if we should use themed rendering
    if scrollbarComponent then
      -- Themed scrollbar rendering using NinePatch
      local frameComponent = scrollbarComponent.frame or scrollbarComponent
      local barComponent = scrollbarComponent.bar or scrollbarComponent

      -- Calculate knob offset (element overrides theme)
      local knobOffsetX = 0
      local knobOffsetY = 0

      -- Use element offset if provided, otherwise use theme offset
      if element.scrollbarKnobOffset then
        knobOffsetX = element.scrollbarKnobOffset.x or 0
        knobOffsetY = element.scrollbarKnobOffset.vertical or 0
      elseif barComponent and barComponent.knobOffset then
        local themeOffset = self._utils.normalizeOffsetTable(barComponent.knobOffset, 0)
        knobOffsetX = themeOffset.x
        knobOffsetY = themeOffset.vertical
      end

      -- Extract contentPadding top inset from frame for knob sizing.
      -- Vertical scrollbar only consumes framePaddingTop; other insets are unused.
      local framePaddingTop = 0
      if frameComponent and frameComponent._ninePatchData and frameComponent._ninePatchData.contentPadding then
        framePaddingTop = frameComponent._ninePatchData.contentPadding.top or 0
      end

      -- Draw track (frame) if component exists
      if frameComponent and frameComponent._loadedAtlas and frameComponent.regions then
        self._NinePatch.draw(
          frameComponent,
          frameComponent._loadedAtlas,
          trackX,
          trackY,
          element.scrollbarWidth,
          dims.vertical.trackHeight
        )
      end

      -- Draw thumb (bar) if component exists
      if barComponent and barComponent._loadedAtlas and barComponent.regions then
        -- Adjust knob dimensions to account for frame's contentPadding
        -- Vertical scrollbar: width affected by left+right, height affected by top+bottom
        local knobWidth = element.scrollbarWidth
        local knobHeight = dims.vertical.thumbHeight - framePaddingTop / 2
        self._NinePatch.draw(
          barComponent,
          barComponent._loadedAtlas,
          trackX + knobOffsetX,
          trackY + dims.vertical.thumbY + knobOffsetY,
          knobWidth,
          knobHeight
        )
      end
    else
      -- Fallback to color-based rendering
      -- Determine thumb color based on state (independent for vertical)
      local thumbColor = element.scrollbarColor
      if element._scrollbarDragging and element._hoveredScrollbar == "vertical" then
        -- Active state: brighter
        local r, g, b, a = self._utils.brightenColor(thumbColor.r, thumbColor.g, thumbColor.b, thumbColor.a, 1.4)
        thumbColor = self._Color.new(r, g, b, a)
      elseif element._scrollbarHoveredVertical then
        -- Hover state: slightly brighter
        local r, g, b, a = self._utils.brightenColor(thumbColor.r, thumbColor.g, thumbColor.b, thumbColor.a, 1.2)
        thumbColor = self._Color.new(r, g, b, a)
      end

      -- Draw track
      love.graphics.setColor(element.scrollbarTrackColor:toRGBA())
      love.graphics.rectangle(
        "fill",
        trackX,
        trackY,
        element.scrollbarWidth,
        dims.vertical.trackHeight,
        element.scrollbarRadius
      )

      -- Draw thumb with state-based color
      love.graphics.setColor(thumbColor:toRGBA())
      love.graphics.rectangle(
        "fill",
        trackX,
        trackY + dims.vertical.thumbY,
        element.scrollbarWidth,
        dims.vertical.thumbHeight,
        element.scrollbarRadius
      )
    end
  end

  -- Horizontal scrollbar
  if dims.horizontal.visible and not element.hideScrollbars.horizontal then
    -- Position scrollbar within content area (x, y is border-box origin)
    local contentX = x + element.padding.left
    local contentY = y + element.padding.top
    local trackX = contentX + element.scrollbarPadding
    local trackY = contentY + h - element.scrollbarWidth - element.scrollbarPadding

    -- Check if we should use themed rendering
    if scrollbarComponent then
      -- Themed scrollbar rendering using NinePatch
      local frameComponent = scrollbarComponent.frame or scrollbarComponent
      local barComponent = scrollbarComponent.bar or scrollbarComponent

      -- Calculate knob offset (element overrides theme)
      local knobOffsetX = 0
      local knobOffsetY = 0

      -- Use element offset if provided, otherwise use theme offset
      if element.scrollbarKnobOffset then
        knobOffsetX = element.scrollbarKnobOffset.horizontal or 0
        knobOffsetY = element.scrollbarKnobOffset.y or 0
      elseif barComponent and barComponent.knobOffset then
        local themeOffset = self._utils.normalizeOffsetTable(barComponent.knobOffset, 0)
        knobOffsetX = themeOffset.horizontal
        knobOffsetY = themeOffset.y
      end

      -- Extract contentPadding from frame for knob sizing (horizontal: right inset unused).
      local framePaddingLeft = 0
      local framePaddingTop = 0
      local framePaddingBottom = 0
      if frameComponent and frameComponent._ninePatchData and frameComponent._ninePatchData.contentPadding then
        framePaddingLeft = frameComponent._ninePatchData.contentPadding.left or 0
        framePaddingTop = frameComponent._ninePatchData.contentPadding.top or 0
        framePaddingBottom = frameComponent._ninePatchData.contentPadding.bottom or 0
      end

      -- Draw track (frame) if component exists
      if frameComponent and frameComponent._loadedAtlas and frameComponent.regions then
        self._NinePatch.draw(
          frameComponent,
          frameComponent._loadedAtlas,
          trackX,
          trackY,
          dims.horizontal.trackWidth,
          element.scrollbarWidth
        )
      end

      -- Draw thumb (bar) if component exists
      if barComponent and barComponent._loadedAtlas and barComponent.regions then
        -- Adjust knob dimensions to account for frame's contentPadding
        -- Horizontal scrollbar: width affected by left+right, height affected by top+bottom
        local knobWidth = dims.horizontal.thumbWidth - framePaddingLeft / 2
        local knobHeight = element.scrollbarWidth - framePaddingTop - framePaddingBottom
        self._NinePatch.draw(
          barComponent,
          barComponent._loadedAtlas,
          trackX + dims.horizontal.thumbX + knobOffsetX,
          trackY + knobOffsetY,
          knobWidth,
          knobHeight
        )
      end
    else
      -- Fallback to color-based rendering
      -- Determine thumb color based on state (independent for horizontal)
      local thumbColor = element.scrollbarColor
      if element._scrollbarDragging and element._hoveredScrollbar == "horizontal" then
        -- Active state: brighter
        local r, g, b, a = self._utils.brightenColor(thumbColor.r, thumbColor.g, thumbColor.b, thumbColor.a, 1.4)
        thumbColor = self._Color.new(r, g, b, a)
      elseif element._scrollbarHoveredHorizontal then
        -- Hover state: slightly brighter
        local r, g, b, a = self._utils.brightenColor(thumbColor.r, thumbColor.g, thumbColor.b, thumbColor.a, 1.2)
        thumbColor = self._Color.new(r, g, b, a)
      end

      -- Draw track
      love.graphics.setColor(element.scrollbarTrackColor:toRGBA())
      love.graphics.rectangle(
        "fill",
        trackX,
        trackY,
        dims.horizontal.trackWidth,
        element.scrollbarWidth,
        element.scrollbarRadius
      )

      -- Draw thumb with state-based color
      love.graphics.setColor(thumbColor:toRGBA())
      love.graphics.rectangle(
        "fill",
        trackX + dims.horizontal.thumbX,
        trackY,
        dims.horizontal.thumbWidth,
        element.scrollbarWidth,
        element.scrollbarRadius
      )
    end
  end

  -- Reset color
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw visual feedback when element is pressed
---@param x number X position
---@param y number Y position
---@param borderBoxWidth number Border box width
---@param borderBoxHeight number Border box height
---@param opacity number Element opacity
---@param cornerRadius number|table Corner radius
function Renderer:drawPressedState(x, y, borderBoxWidth, borderBoxHeight, opacity, cornerRadius)
  love.graphics.setColor(0.5, 0.5, 0.5, 0.3 * (opacity or 1))
  self._RoundedRect.draw("fill", x, y, borderBoxWidth, borderBoxHeight, cornerRadius)
end

--- Cleanup renderer resources
function Renderer:destroy()
  self._loadedImage = nil
  self._blurInstance = nil
end

return Renderer
