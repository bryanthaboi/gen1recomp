---@class LayoutEngine
---@field element Element? Reference to the parent element
---@field positioning Positioning Layout positioning mode
---@field flexDirection FlexDirection Direction of flex layout
---@field justifyContent JustifyContent Alignment of items along main axis
---@field alignItems AlignItems Alignment of items along cross axis
---@field alignContent AlignContent Alignment of lines in multi-line flex containers
---@field flexWrap FlexWrap Whether children wrap to multiple lines
---@field gap number Space between children elements
---@field gridRows number? Number of rows in the grid
---@field gridColumns number? Number of columns in the grid
---@field columnGap number? Gap between grid columns
---@field rowGap number? Gap between grid rows
---@field _Grid table
---@field _Units table
---@field _Context table
---@field _Positioning table
---@field _FlexDirection table
---@field _JustifyContent table
---@field _AlignContent table
---@field _AlignItems table
---@field _AlignSelf table
---@field _FlexWrap table
---@field _layoutCount number Track layout recalculations per frame
---@field _lastFrameCount number Last frame number for resetting counters
---@field _ErrorHandler ErrorHandler? ErrorHandler module dependency
---@field _Performance Performance? Performance module dependency
local LayoutEngine = {}
LayoutEngine.__index = LayoutEngine

--- Recursively shift an element and all its descendants by (dx, dy).
--- Used by the row-reverse mirror pass and the `position: relative` offset
--- pass: both run after the rest of layout has placed the subtree, so a single
--- delta walk keeps descendants visually anchored to the parent.
---@param elem Element
---@param dx number
---@param dy number
local function shiftSubtree(elem, dx, dy)
  elem.x = elem.x + dx
  elem.y = elem.y + dy
  for _, c in ipairs(elem.children) do
    shiftSubtree(c, dx, dy)
  end
end

--- Initialize module with shared dependencies
---@param deps table Dependencies {ErrorHandler, Performance, utils}
function LayoutEngine.init(deps)
  LayoutEngine._ErrorHandler = deps.ErrorHandler
  LayoutEngine._Performance = deps.Performance
  LayoutEngine._Utils = deps.utils
end

---@class LayoutEngineProps
---@field positioning Positioning? Layout positioning mode (default: RELATIVE)
---@field flexDirection FlexDirection? Direction of flex layout (default: HORIZONTAL)
---@field justifyContent JustifyContent? Alignment of items along main axis (default: FLEX_START)
---@field alignItems AlignItems? Alignment of items along cross axis (default: STRETCH)
---@field alignContent AlignContent? Alignment of lines in multi-line flex containers (default: STRETCH)
---@field flexWrap FlexWrap? Whether children wrap to multiple lines (default: NOWRAP)
---@field gap number? Space between children elements (default: 10)
---@field gridRows number? Number of rows in the grid
---@field gridColumns number? Number of columns in the grid
---@field columnGap number? Gap between grid columns
---@field rowGap number? Gap between grid rows

--- Create a new LayoutEngine instance
---@param props LayoutEngineProps
---@param deps table Dependencies {utils, Grid, Units, Context}
---@return LayoutEngine
function LayoutEngine.new(props, deps)
  local enums = deps.utils.enums
  local Positioning = enums.Positioning
  local FlexDirection = enums.FlexDirection
  local JustifyContent = enums.JustifyContent
  local AlignContent = enums.AlignContent
  local AlignItems = enums.AlignItems
  local AlignSelf = enums.AlignSelf
  local FlexWrap = enums.FlexWrap

  local self = setmetatable({}, LayoutEngine)

  -- Store dependencies for instance methods
  self._Grid = deps.Grid
  self._Units = deps.Units
  self._Context = deps.Context
  self._ErrorHandler = deps.ErrorHandler
  self._Positioning = Positioning
  self._FlexDirection = FlexDirection
  self._JustifyContent = JustifyContent
  self._AlignContent = AlignContent
  self._AlignItems = AlignItems
  self._AlignSelf = AlignSelf
  self._FlexWrap = FlexWrap

  -- Layout configuration
  self.positioning = props.positioning or Positioning.FLEX
  self.flexDirection = props.flexDirection or FlexDirection.HORIZONTAL
  self.justifyContent = props.justifyContent or JustifyContent.FLEX_START
  self.alignItems = props.alignItems or AlignItems.STRETCH
  self.alignContent = props.alignContent or AlignContent.STRETCH
  self.flexWrap = props.flexWrap or FlexWrap.NOWRAP
  self.gap = props.gap or 10

  -- Grid layout configuration
  self.gridRows = props.gridRows
  self.gridColumns = props.gridColumns

  self.columnGap = props.columnGap
  self.rowGap = props.rowGap

  -- Element reference (will be set via initialize)
  self.element = nil

  -- Performance tracking
  self._layoutCount = 0
  self._lastFrameCount = 0

  -- Layout memoization cache
  self._layoutCache = {
    childrenCount = 0,
    containerWidth = 0,
    containerHeight = 0,
    containerX = 0,
    containerY = 0,
    childrenHash = "",
  }

  return self
end

--- Initialize the LayoutEngine with its parent element
---@param element Element The parent element
function LayoutEngine:initialize(element)
  self.element = element
end

--- True for flex-direction `horizontal` or `horizontal-reverse` (and their
--- `row`/`row-reverse` aliases, which normalize to those at construction).
--- Routes every main-axis orientation check so reverse directions are
--- correctly classified as horizontal.
---@return boolean
function LayoutEngine:_isHorizontal()
  return self.flexDirection == self._FlexDirection.HORIZONTAL
    or self.flexDirection == self._FlexDirection.HORIZONTAL_REVERSE
end

--- True for flex-direction `horizontal-reverse` or `vertical-reverse`
--- (and their `row-reverse`/`column-reverse` aliases).
---@return boolean
function LayoutEngine:_isReverse()
  return self.flexDirection == self._FlexDirection.HORIZONTAL_REVERSE
    or self.flexDirection == self._FlexDirection.VERTICAL_REVERSE
end

--- Apply CSS positioning offsets (top, right, bottom, left) to a child element
---@param child Element The element to apply offsets to
function LayoutEngine:applyPositioningOffsets(child)
  if not child then
    return
  end

  -- For CSS-style positioning, we need the parent's bounds
  local parent = child.parent
  if not parent then
    return
  end

  -- Only apply offsets to explicitly absolute children or children in relative/absolute containers
  -- Flex/grid children ignore positioning offsets as they participate in layout
  local isFlexChild = child.positioning == self._Positioning.FLEX
    or child.positioning == self._Positioning.GRID
    or (child.positioning == self._Positioning.ABSOLUTE and not child._explicitlyAbsolute)

  if not isFlexChild and child._explicitlyAbsolute then
    -- Apply absolute positioning for explicitly absolute children
    -- Apply top offset (distance from parent's content box top edge)
    if child.top then
      child.y = parent.y + parent.padding.top + child.top
    end

    -- Apply bottom offset (distance from parent's content box bottom edge)
    -- BORDER-BOX MODEL: Use border-box dimensions for positioning
    if child.bottom then
      local elementBorderBoxHeight = child:getBorderBoxHeight()
      child.y = parent.y + parent.padding.top + parent.height - child.bottom - elementBorderBoxHeight
    end

    -- Apply left offset (distance from parent's content box left edge)
    if child.left then
      child.x = parent.x + parent.padding.left + child.left
    end

    -- Apply right offset (distance from parent's content box right edge)
    -- BORDER-BOX MODEL: Use border-box dimensions for positioning
    if child.right then
      local elementBorderBoxWidth = child:getBorderBoxWidth()
      child.x = parent.x + parent.padding.left + parent.width - child.right - elementBorderBoxWidth
    end
  end
end

--- Calculate flex item sizes based on flexGrow, flexShrink, flexBasis
--- Implements CSS flexbox sizing algorithm
---@param children table Array of child elements in the flex line
---@param availableMainSize number Available space in main axis
---@param gap number Gap between items
---@param isHorizontal boolean Whether main axis is horizontal
---@param defaultFlexShrink number? Default flex-shrink to use when child.flexShrink is nil
---@return table mainSizes Array of calculated main sizes for each child
function LayoutEngine:_calculateFlexSizes(children, availableMainSize, gap, isHorizontal, defaultFlexShrink)
  local implicitFlexShrink = defaultFlexShrink
  if implicitFlexShrink == nil then
    implicitFlexShrink = 1
  end

  local function getResolvedFlexShrink(child)
    if child._hasExplicitFlexShrink then
      return child.flexShrink
    end
    return implicitFlexShrink
  end

  local childCount = #children
  local totalGaps = math.max(0, childCount - 1) * gap
  local availableForContent = availableMainSize - totalGaps
  local viewportWidth, viewportHeight = self._Units.getViewport()

  -- Step 1: Calculate hypothetical main sizes (flex basis resolution)
  local hypotheticalSizes = {}
  local flexBases = {}
  local totalFlexBasis = 0

  local function resolveDeclaredMainSize(child)
    local axisUnits = nil
    if child.units then
      axisUnits = isHorizontal and child.units.width or child.units.height
    end

    if not axisUnits or axisUnits.unit == "auto" or axisUnits.value == nil then
      return nil
    end

    local resolved =
      self._Units.resolve(axisUnits.value, axisUnits.unit, viewportWidth, viewportHeight, availableMainSize)

    if type(resolved) == "number" then
      return math.max(0, resolved)
    end

    return nil
  end

  for i, child in ipairs(children) do
    local flexBasis = child.flexBasis
    local hypotheticalSize

    -- Resolve flex-basis
    if flexBasis == "auto" then
      -- Use declared main size to avoid reusing a previously flexed runtime size
      hypotheticalSize = resolveDeclaredMainSize(child)
      if hypotheticalSize == nil then
        if isHorizontal then
          hypotheticalSize = child:getBorderBoxWidth()
        else
          hypotheticalSize = child:getBorderBoxHeight()
        end
      end
    elseif type(flexBasis) == "number" then
      hypotheticalSize = flexBasis
    elseif type(flexBasis) == "string" and child.units.flexBasis then
      -- Parse and resolve flex-basis with units
      local value, unit = child.units.flexBasis.value, child.units.flexBasis.unit
      hypotheticalSize = self._Units.resolve(value, unit, viewportWidth, viewportHeight, availableMainSize)
    else
      -- Fallback to element's natural size
      if isHorizontal then
        hypotheticalSize = child:getBorderBoxWidth()
      else
        hypotheticalSize = child:getBorderBoxHeight()
      end
    end

    -- Add margins to hypothetical size
    local childMargin = child.margin
    if isHorizontal then
      hypotheticalSize = hypotheticalSize + childMargin.left + childMargin.right
    else
      hypotheticalSize = hypotheticalSize + childMargin.top + childMargin.bottom
    end

    flexBases[i] = hypotheticalSize
    hypotheticalSizes[i] = hypotheticalSize
    totalFlexBasis = totalFlexBasis + hypotheticalSize
  end

  -- Step 2: Determine if we need to grow or shrink
  local freeSpace = availableForContent - totalFlexBasis

  -- Step 3a: Handle positive free space (GROW)
  if freeSpace > 0 then
    local totalFlexGrow = 0
    for _, child in ipairs(children) do
      totalFlexGrow = totalFlexGrow + (child.flexGrow or 0)
    end

    if totalFlexGrow > 0 then
      -- Distribute free space proportionally to flex-grow values
      for i, child in ipairs(children) do
        local flexGrow = child.flexGrow or 0
        if flexGrow > 0 then
          local growAmount = (flexGrow / totalFlexGrow) * freeSpace
          hypotheticalSizes[i] = hypotheticalSizes[i] + growAmount
        end
      end
    end
    -- Step 3b: Handle negative free space (SHRINK)
  elseif freeSpace < 0 then
    local totalFlexShrink = 0
    local totalScaledShrinkFactor = 0

    for i, child in ipairs(children) do
      local flexShrink = getResolvedFlexShrink(child)
      totalFlexShrink = totalFlexShrink + flexShrink
      -- Scaled shrink factor = flex-shrink × flex-basis
      totalScaledShrinkFactor = totalScaledShrinkFactor + (flexShrink * flexBases[i])
    end

    if totalScaledShrinkFactor > 0 then
      -- Distribute shrinkage proportionally to (flex-shrink × flex-basis)
      for i, child in ipairs(children) do
        local flexShrink = getResolvedFlexShrink(child)
        if flexShrink > 0 then
          local scaledShrinkFactor = flexShrink * flexBases[i]
          local shrinkAmount = (scaledShrinkFactor / totalScaledShrinkFactor) * math.abs(freeSpace)
          hypotheticalSizes[i] = math.max(0, hypotheticalSizes[i] - shrinkAmount)
        end
      end
    end
  end

  -- Step 4: Return final main sizes (excluding margins), clamped to per-child min/max
  local mainSizes = {}
  for i, child in ipairs(children) do
    local childMargin = child.margin
    local marginSum = isHorizontal and (childMargin.left + childMargin.right) or (childMargin.top + childMargin.bottom)
    local minBound = isHorizontal and child.minWidth or child.minHeight
    local maxBound = isHorizontal and child.maxWidth or child.maxHeight
    mainSizes[i] = LayoutEngine._Utils.clamp(math.max(0, hypotheticalSizes[i] - marginSum), minBound, maxBound)
  end

  return mainSizes
end

--- Layout children within this element according to positioning mode
function LayoutEngine:layoutChildren()
  -- Start performance timing first (before any early returns)
  local timerName = nil
  if LayoutEngine._Performance and LayoutEngine._Performance.enabled and self.element then
    -- Use memory address to make timer name unique per element instance
    timerName = "layout_" .. (self.element.id or tostring(self.element):match("0x%x+") or "unknown")
    LayoutEngine._Performance:startTimer(timerName)
  end

  if self.element == nil then
    return
  end

  -- Check if layout can be skipped (memoization optimization)
  if self:_canSkipLayout() then
    if timerName and LayoutEngine._Performance then
      LayoutEngine._Performance:stopTimer(timerName)
    end
    return
  end

  -- Track layout recalculations for performance warnings
  self:_trackLayoutRecalculation()

  -- Handle grid layout
  if self.positioning == self._Positioning.GRID then
    self._Grid.layoutGridItems(self.element)

    -- Stop performance timing
    if timerName and LayoutEngine._Performance then
      LayoutEngine._Performance:stopTimer(timerName)
    end
    return
  end

  local childCount = #self.element.children

  if childCount == 0 then
    -- Stop performance timing
    if timerName and LayoutEngine._Performance then
      LayoutEngine._Performance:stopTimer(timerName)
    end
    return
  end

  -- Get flex children (children that participate in flex layout)
  -- Exclude display=false (CSS display:none) and explicitly absolute children
  local flexChildren = {}
  for _, child in ipairs(self.element.children) do
    local isFlexChild = not (child.positioning == self._Positioning.ABSOLUTE and child._explicitlyAbsolute)
      and child.display ~= false
    if isFlexChild then
      table.insert(flexChildren, child)

      -- Warn if child uses percentage sizing but parent has autosizing
      if child.units and child.units.width then
        if child.units.width.unit == "%" and self.element.autosizing and self.element.autosizing.width then
          self.element:_warnIfPercentageWithAutoSizing(child, "width")
        end
      end
      if child.units and child.units.height then
        if child.units.height.unit == "%" and self.element.autosizing and self.element.autosizing.height then
          self.element:_warnIfPercentageWithAutoSizing(child, "height")
        end
      end
    end
  end

  -- CSS-compliant behavior: absolutely positioned elements are completely removed from normal flow
  -- They do NOT reserve space or affect flex layout calculations at all

  -- If no flex children, skip flex layout but still position absolute children
  if #flexChildren == 0 then
    -- Position absolutely positioned children even when there are no flex children
    for i, child in ipairs(self.element.children) do
      if child.positioning == self._Positioning.ABSOLUTE and child._explicitlyAbsolute and child.display ~= false then
        self:applyPositioningOffsets(child)

        -- If child has children, layout them after position change
        if #child.children > 0 then
          child:layoutChildren()
        end
      end
    end

    -- Detect overflow after children positioning
    if self.element._detectOverflow then
      self.element:_detectOverflow()
    end

    -- Stop performance timing
    if timerName and LayoutEngine._Performance then
      LayoutEngine._Performance:stopTimer(timerName)
    end
    return
  end

  -- Calculate available space (accounting for padding only, NOT absolute children)
  -- BORDER-BOX MODEL: element.width and element.height are already content dimensions (padding subtracted)
  local availableMainSize = 0
  local availableCrossSize = 0

  -- Reserve space for scrollbars if needed (reserve-space mode)
  local scrollbarReservedWidth = 0
  local scrollbarReservedHeight = 0
  if self.element._scrollManager and self.element._scrollManager.scrollbarPlacement == "reserve-space" then
    scrollbarReservedWidth, scrollbarReservedHeight = self.element._scrollManager:getReservedSpace(self.element)
  end

  if self:_isHorizontal() then
    availableMainSize = self.element.width - scrollbarReservedWidth
    availableCrossSize = self.element.height - scrollbarReservedHeight
  else
    availableMainSize = self.element.height - scrollbarReservedHeight
    availableCrossSize = self.element.width - scrollbarReservedWidth
  end

  -- Keep percentage-sized children in sync when container dimensions change.
  -- Managed select frames rely on this so `width = "100%"` options expand with the dropdown.
  if scrollbarReservedWidth > 0 or scrollbarReservedHeight > 0 or self.element:_shouldSyncPercentageDimensions() then
    local isHorizontal = self:_isHorizontal()
    for _, child in ipairs(flexChildren) do
      if isHorizontal then
        -- Horizontal flex: main-axis is width, cross-axis is height
        -- Adjust main-axis width if percentage-based
        if child.units and child.units.width and child.units.width.unit == "%" then
          local newBorderBoxWidth = LayoutEngine._Utils.clamp(
            (child.units.width.value / 100) * availableMainSize,
            child.minWidth,
            child.maxWidth
          )
          child._borderBoxWidth = newBorderBoxWidth
          child.width = math.max(0, newBorderBoxWidth - child.padding.left - child.padding.right)
        end
        -- Adjust cross-axis height if percentage-based
        if child.units and child.units.height and child.units.height.unit == "%" then
          local newBorderBoxHeight = LayoutEngine._Utils.clamp(
            (child.units.height.value / 100) * availableCrossSize,
            child.minHeight,
            child.maxHeight
          )
          child._borderBoxHeight = newBorderBoxHeight
          child.height = math.max(0, newBorderBoxHeight - child.padding.top - child.padding.bottom)
        end
      else
        -- Vertical flex: main-axis is height, cross-axis is width
        -- Adjust main-axis height if percentage-based
        if child.units and child.units.height and child.units.height.unit == "%" then
          local newBorderBoxHeight = LayoutEngine._Utils.clamp(
            (child.units.height.value / 100) * availableMainSize,
            child.minHeight,
            child.maxHeight
          )
          child._borderBoxHeight = newBorderBoxHeight
          child.height = math.max(0, newBorderBoxHeight - child.padding.top - child.padding.bottom)
        end
        -- Adjust cross-axis width if percentage-based
        if child.units and child.units.width and child.units.width.unit == "%" then
          local rawBorderBoxWidth = (child.units.width.value / 100) * availableCrossSize
          local newBorderBoxWidth = LayoutEngine._Utils.clamp(
            self.element:_adjustCrossAxisPercentageWidth(child, rawBorderBoxWidth),
            child.minWidth,
            child.maxWidth
          )
          child._borderBoxWidth = newBorderBoxWidth
          child.width = math.max(0, newBorderBoxWidth - child.padding.left - child.padding.right)
        end
      end
    end
  end

  -- Handle flex wrap: create lines of children
  local lines = {}

  if self.flexWrap == self._FlexWrap.NOWRAP then
    -- All children go on one line
    lines[1] = flexChildren
  else
    -- Wrap children into multiple lines
    local currentLine = {}
    local currentLineSize = 0

    -- Performance optimization: hoist enum comparisons outside loop
    local isHorizontal = self:_isHorizontal()
    local gapSize = self.gap
    local viewportWidth, viewportHeight = self._Units.getViewport()

    local function resolveDeclaredMainSizeForWrap(child)
      local axisUnits = nil
      if child.units then
        axisUnits = isHorizontal and child.units.width or child.units.height
      end

      if not axisUnits or axisUnits.unit == "auto" or axisUnits.value == nil then
        return nil
      end

      local resolved =
        self._Units.resolve(axisUnits.value, axisUnits.unit, viewportWidth, viewportHeight, availableMainSize)

      if type(resolved) == "number" then
        return math.max(0, resolved)
      end

      return nil
    end

    for _, child in ipairs(flexChildren) do
      -- BORDER-BOX MODEL: Use border-box dimensions for layout calculations
      -- Include margins in size calculations
      -- Performance optimization: hoist margin table access
      local childMargin = child.margin
      local childMainSize = 0
      local childMainMargin = 0
      local declaredMainSize = resolveDeclaredMainSizeForWrap(child)
      if isHorizontal then
        childMainSize = declaredMainSize or child:getBorderBoxWidth()
        childMainMargin = childMargin.left + childMargin.right
      else
        childMainSize = declaredMainSize or child:getBorderBoxHeight()
        childMainMargin = childMargin.top + childMargin.bottom
      end
      local childTotalMainSize = childMainSize + childMainMargin

      -- Check if adding this child would exceed the available space
      local lineSpacing = #currentLine > 0 and gapSize or 0
      if #currentLine > 0 and currentLineSize + lineSpacing + childTotalMainSize > availableMainSize then
        -- Start a new line
        if #currentLine > 0 then
          table.insert(lines, currentLine)
        end
        currentLine = { child }
        currentLineSize = childTotalMainSize
      else
        -- Add to current line
        table.insert(currentLine, child)
        currentLineSize = currentLineSize + lineSpacing + childTotalMainSize
      end
    end

    -- Add the last line if it has children
    if #currentLine > 0 then
      table.insert(lines, currentLine)
    end

    -- Handle wrap-reverse: reverse the order of lines
    if self.flexWrap == self._FlexWrap.WRAP_REVERSE then
      local reversedLines = {}
      for i = #lines, 1, -1 do
        table.insert(reversedLines, lines[i])
      end
      lines = reversedLines
    end
  end

  -- Apply flex sizing to each line BEFORE calculating line heights
  -- Performance optimization: hoist enum comparison outside loop
  local isHorizontal = self:_isHorizontal()
  local mainAxisOverflow = nil
  if self:_isHorizontal() then
    mainAxisOverflow = self.element.overflowX or self.element.overflow
  else
    mainAxisOverflow = self.element.overflowY or self.element.overflow
  end
  local preserveMainAxisOverflow = (mainAxisOverflow == "scroll" or mainAxisOverflow == "auto")
  local defaultFlexShrink = preserveMainAxisOverflow and 0 or 1

  for lineIndex, line in ipairs(lines) do
    -- Check if any child in this line needs flex sizing.
    -- For scroll/auto in the main axis, keep implicit shrink at 0 so overflow can scroll.
    local needsFlexSizing = false
    for _, child in ipairs(line) do
      local flexGrow = child.flexGrow or 0
      local flexBasis = child.flexBasis
      local resolvedFlexShrink = defaultFlexShrink
      if child._hasExplicitFlexShrink then
        resolvedFlexShrink = child.flexShrink
      end

      if flexGrow > 0 or (flexBasis and flexBasis ~= "auto") or resolvedFlexShrink > 0 then
        needsFlexSizing = true
        break
      end
    end

    -- Only apply flex sizing if needed
    if needsFlexSizing then
      -- Calculate flex sizes for this line
      local mainSizes = self:_calculateFlexSizes(line, availableMainSize, self.gap, isHorizontal, defaultFlexShrink)

      -- Apply calculated sizes to children
      for i, child in ipairs(line) do
        local mainSize = mainSizes[i]

        if isHorizontal then
          -- Update width for horizontal flex
          child._borderBoxWidth = mainSize
          child.width = math.max(0, mainSize - child.padding.left - child.padding.right)
          -- Invalidate width cache
          child._borderBoxWidthCache = nil
        else
          -- Update height for vertical flex
          child._borderBoxHeight = mainSize
          child.height = math.max(0, mainSize - child.padding.top - child.padding.bottom)
          -- Invalidate height cache
          child._borderBoxHeightCache = nil
        end

        -- Trigger layout for child's children if any
        if #child.children > 0 then
          child:layoutChildren()
        end
      end
    end
  end

  -- Calculate line positions and heights (including child padding)
  -- Performance optimization: preallocate array if possible
  local lineHeights = table.create and table.create(#lines) or {}
  local totalLinesHeight = 0

  -- Performance optimization: hoist enum comparison outside loop (already hoisted above)
  -- local isHorizontal = self.flexDirection == self._FlexDirection.HORIZONTAL

  for lineIndex, line in ipairs(lines) do
    local maxCrossSize = 0
    for _, child in ipairs(line) do
      -- BORDER-BOX MODEL: Use border-box dimensions for layout calculations
      -- Include margins in cross-axis size calculations
      -- Performance optimization: hoist margin table access
      local childMargin = child.margin
      local childCrossSize = 0
      local childCrossMargin = 0
      if isHorizontal then
        childCrossSize = child:getBorderBoxHeight()
        childCrossMargin = childMargin.top + childMargin.bottom
      else
        childCrossSize = child:getBorderBoxWidth()
        childCrossMargin = childMargin.left + childMargin.right
      end
      local childTotalCrossSize = childCrossSize + childCrossMargin
      maxCrossSize = math.max(maxCrossSize, childTotalCrossSize)
    end
    lineHeights[lineIndex] = maxCrossSize
    totalLinesHeight = totalLinesHeight + maxCrossSize
  end

  -- Account for gaps between lines
  local lineGaps = math.max(0, #lines - 1) * self.gap
  totalLinesHeight = totalLinesHeight + lineGaps

  -- For single line layouts, CENTER, FLEX_END and STRETCH should use full cross size
  if #lines == 1 then
    if
      self.alignItems == self._AlignItems.STRETCH
      or self.alignItems == self._AlignItems.CENTER
      or self.alignItems == self._AlignItems.FLEX_END
    then
      -- STRETCH, CENTER, and FLEX_END should use full available cross size
      lineHeights[1] = availableCrossSize
      totalLinesHeight = availableCrossSize
    end
    -- CENTER and FLEX_END should preserve natural child dimensions
    -- and only affect positioning within the available space
  end

  -- Calculate starting position for lines based on alignContent
  local lineStartPos = 0
  local lineSpacing = self.gap
  local freeLineSpace = availableCrossSize - totalLinesHeight

  -- Apply AlignContent logic for both single and multiple lines
  if self.alignContent == self._AlignContent.FLEX_START then
    lineStartPos = 0
  elseif self.alignContent == self._AlignContent.CENTER then
    lineStartPos = freeLineSpace / 2
  elseif self.alignContent == self._AlignContent.FLEX_END then
    lineStartPos = freeLineSpace
  elseif self.alignContent == self._AlignContent.SPACE_BETWEEN then
    lineStartPos = 0
    if #lines > 1 then
      lineSpacing = self.gap + (freeLineSpace / (#lines - 1))
    end
  elseif self.alignContent == self._AlignContent.SPACE_AROUND then
    local spaceAroundEach = freeLineSpace / #lines
    lineStartPos = spaceAroundEach / 2
    lineSpacing = self.gap + spaceAroundEach
  elseif self.alignContent == self._AlignContent.STRETCH then
    lineStartPos = 0
    if #lines > 1 and freeLineSpace > 0 then
      lineSpacing = self.gap + (freeLineSpace / #lines)
      -- Distribute extra space to line heights (only if positive)
      local extraPerLine = freeLineSpace / #lines
      for i = 1, #lineHeights do
        lineHeights[i] = lineHeights[i] + extraPerLine
      end
    end
  end

  -- Position children within each line
  local currentCrossPos = lineStartPos

  for lineIndex, line in ipairs(lines) do
    local lineHeight = lineHeights[lineIndex]

    -- Calculate total size of children in this line (including padding and margins)
    -- BORDER-BOX MODEL: Use border-box dimensions for layout calculations
    -- Performance optimization: hoist flexDirection check outside loop
    local isHorizontal = self:_isHorizontal()
    local totalChildrenSize = 0
    for _, child in ipairs(line) do
      local childMargin = child.margin
      if isHorizontal then
        totalChildrenSize = totalChildrenSize + child:getBorderBoxWidth() + childMargin.left + childMargin.right
      else
        totalChildrenSize = totalChildrenSize + child:getBorderBoxHeight() + childMargin.top + childMargin.bottom
      end
    end

    local totalGapSize = math.max(0, #line - 1) * self.gap
    local totalContentSize = totalChildrenSize + totalGapSize
    local freeSpace = availableMainSize - totalContentSize

    -- Calculate initial position and spacing based on justifyContent
    local startPos = 0
    local itemSpacing = self.gap

    if self.justifyContent == self._JustifyContent.FLEX_START then
      startPos = 0
    elseif self.justifyContent == self._JustifyContent.CENTER then
      startPos = math.max(0, freeSpace / 2)
    elseif self.justifyContent == self._JustifyContent.FLEX_END then
      startPos = math.max(0, freeSpace)
    elseif self.justifyContent == self._JustifyContent.SPACE_BETWEEN then
      startPos = 0
      if #line > 1 and freeSpace > 0 then
        itemSpacing = self.gap + (freeSpace / (#line - 1))
      end
    elseif self.justifyContent == self._JustifyContent.SPACE_AROUND then
      if freeSpace > 0 then
        local spaceAroundEach = freeSpace / #line
        startPos = spaceAroundEach / 2
        itemSpacing = self.gap + spaceAroundEach
      end
    elseif self.justifyContent == self._JustifyContent.SPACE_EVENLY then
      if freeSpace > 0 then
        local spaceBetween = freeSpace / (#line + 1)
        startPos = spaceBetween
        itemSpacing = self.gap + spaceBetween
      end
    end

    -- Position children in this line
    local currentMainPos = startPos

    -- Performance optimization: hoist frequently accessed element properties
    local elementX = self.element.x
    local elementY = self.element.y
    local elementPadding = self.element.padding
    local elementPaddingLeft = elementPadding.left
    local elementPaddingTop = elementPadding.top
    local alignItems = self.alignItems
    local alignSelf_AUTO = self._AlignSelf.AUTO
    local alignItems_FLEX_START = self._AlignItems.FLEX_START
    local alignItems_CENTER = self._AlignItems.CENTER
    local alignItems_FLEX_END = self._AlignItems.FLEX_END
    local alignItems_STRETCH = self._AlignItems.STRETCH

    for _, child in ipairs(line) do
      -- Performance optimization: hoist child table accesses
      local childMargin = child.margin
      local childPadding = child.padding
      local childAutosizing = child.autosizing

      -- Determine effective cross-axis alignment
      local effectiveAlign = child.alignSelf
      if effectiveAlign == nil or effectiveAlign == alignSelf_AUTO then
        effectiveAlign = alignItems
      end

      if self:_isHorizontal() then
        -- Horizontal layout: main axis is X, cross axis is Y
        -- Position child at border box (x, y represents top-left including padding)
        -- CSS-compliant: absolute children don't affect flex positioning, so no reserved space offset
        local childMarginLeft = childMargin.left
        child.x = elementX + elementPaddingLeft + currentMainPos + childMarginLeft

        -- BORDER-BOX MODEL: Use border-box dimensions for alignment calculations
        local childBorderBoxHeight = child:getBorderBoxHeight()
        local childMarginTop = childMargin.top
        local childMarginBottom = childMargin.bottom
        local childTotalCrossSize = childBorderBoxHeight + childMarginTop + childMarginBottom

        if effectiveAlign == alignItems_FLEX_START then
          child.y = elementY + elementPaddingTop + currentCrossPos + childMarginTop
        elseif effectiveAlign == alignItems_CENTER then
          child.y = elementY
            + elementPaddingTop
            + currentCrossPos
            + ((lineHeight - childTotalCrossSize) / 2)
            + childMarginTop
        elseif effectiveAlign == alignItems_FLEX_END then
          child.y = elementY + elementPaddingTop + currentCrossPos + lineHeight - childTotalCrossSize + childMarginTop
        elseif effectiveAlign == alignItems_STRETCH then
          -- STRETCH: Only apply if height was not explicitly set
          if childAutosizing and childAutosizing.height then
            -- STRETCH: Set border-box height to lineHeight minus margins, content area shrinks to fit
            local availableHeight = LayoutEngine._Utils.clamp(
              lineHeight - childMarginTop - childMarginBottom,
              child.minHeight,
              child.maxHeight
            )
            child._borderBoxHeight = availableHeight
            child.height = math.max(0, availableHeight - childPadding.top - childPadding.bottom)
          end
          child.y = elementY + elementPaddingTop + currentCrossPos + childMarginTop
        end

        -- Apply positioning offsets (top, right, bottom, left)
        self:applyPositioningOffsets(child)

        -- If child has children, re-layout them after position change
        if #child.children > 0 then
          child:layoutChildren()
        end

        -- Advance position by child's border-box width plus margins
        currentMainPos = currentMainPos + child:getBorderBoxWidth() + childMarginLeft + childMargin.right + itemSpacing
      else
        -- Vertical layout: main axis is Y, cross axis is X
        -- Position child at border box (x, y represents top-left including padding)
        -- CSS-compliant: absolute children don't affect flex positioning, so no reserved space offset
        local childMarginTop = childMargin.top
        child.y = elementY + elementPaddingTop + currentMainPos + childMarginTop

        -- BORDER-BOX MODEL: Use border-box dimensions for alignment calculations
        local childBorderBoxWidth = child:getBorderBoxWidth()
        local childMarginLeft = childMargin.left
        local childMarginRight = childMargin.right
        local childTotalCrossSize = childBorderBoxWidth + childMarginLeft + childMarginRight
        local elementPaddingLeft = elementPadding.left

        if effectiveAlign == alignItems_FLEX_START then
          child.x = elementX + elementPaddingLeft + currentCrossPos + childMarginLeft
        elseif effectiveAlign == alignItems_CENTER then
          child.x = elementX
            + elementPaddingLeft
            + currentCrossPos
            + ((lineHeight - childTotalCrossSize) / 2)
            + childMarginLeft
        elseif effectiveAlign == alignItems_FLEX_END then
          child.x = elementX + elementPaddingLeft + currentCrossPos + lineHeight - childTotalCrossSize + childMarginLeft
        elseif effectiveAlign == alignItems_STRETCH then
          -- STRETCH: Only apply if width was not explicitly set
          if childAutosizing and childAutosizing.width then
            -- STRETCH: Set border-box width to lineHeight minus margins, content area shrinks to fit
            local availableWidth =
              LayoutEngine._Utils.clamp(lineHeight - childMarginLeft - childMarginRight, child.minWidth, child.maxWidth)
            child._borderBoxWidth = availableWidth
            child.width = math.max(0, availableWidth - childPadding.left - childPadding.right)
          end
          child.x = elementX + elementPaddingLeft + currentCrossPos + childMarginLeft
        end

        -- Apply positioning offsets (top, right, bottom, left)
        self:applyPositioningOffsets(child)

        -- If child has children, re-layout them after position change
        if #child.children > 0 then
          child:layoutChildren()
        end

        -- Advance position by child's border-box height plus margins
        currentMainPos = currentMainPos
          + child:getBorderBoxHeight()
          + child.margin.top
          + child.margin.bottom
          + itemSpacing
      end
    end

    -- Move to next line position
    currentCrossPos = currentCrossPos + lineHeight + lineSpacing
  end

  -- Position explicitly absolute children after flex layout
  for i, child in ipairs(self.element.children) do
    if child.positioning == self._Positioning.ABSOLUTE and child._explicitlyAbsolute and child.display ~= false then
      -- Apply positioning offsets (top, right, bottom, left)
      self:applyPositioningOffsets(child)

      -- If child has children, layout them after position change
      if #child.children > 0 then
        child:layoutChildren()
      end
    end
  end

  -- flex-direction: row-reverse / column-reverse — mirror the main-axis
  -- position of each flex child relative to the container content area, and
  -- shift the child's subtree by the same delta so descendants follow.
  -- Cross-axis positions and absolute children are not affected.
  if self:_isReverse() then
    local parent = self.element
    local padLeft = parent.padding.left
    local padTop = parent.padding.top
    local contentW = parent.width
    local contentH = parent.height
    local mirrorHorizontal = self:_isHorizontal()

    for _, child in ipairs(flexChildren) do
      if mirrorHorizontal then
        local distFromLeft = child.x - parent.x - padLeft
        local childW = child:getBorderBoxWidth()
        local newDistFromLeft = contentW - distFromLeft - childW
        local dx = newDistFromLeft - distFromLeft
        if dx ~= 0 then
          shiftSubtree(child, dx, 0)
        end
      else
        local distFromTop = child.y - parent.y - padTop
        local childH = child:getBorderBoxHeight()
        local newDistFromTop = contentH - distFromTop - childH
        local dy = newDistFromTop - distFromTop
        if dy ~= 0 then
          shiftSubtree(child, 0, dy)
        end
      end
    end
  end

  -- position: relative — shift each in-flow child by (left or -right,
  -- top or -bottom) after the flex flow (and row-reverse mirroring) has
  -- placed it, so the offset is a pure visual delta that doesn't influence
  -- siblings' flow positions. Per CSS, `top` wins over `bottom` and `left`
  -- over `right` when both are set. Static/absolute children are unaffected
  -- (absolute uses applyPositioningOffsets; flex-participating children
  -- dropped the offsets and emitted LAY_011 at construction). Runs for every
  -- container type so relative children in relative containers also honor offsets.
  for _, child in ipairs(self.element.children) do
    if child.positioning == self._Positioning.RELATIVE and child.display ~= false then
      local dx, dy = 0, 0
      if child.top then
        dy = child.top
      elseif child.bottom then
        dy = -child.bottom
      end
      if child.left then
        dx = child.left
      elseif child.right then
        dx = -child.right
      end
      if dx ~= 0 or dy ~= 0 then
        shiftSubtree(child, dx, dy)
      end
    end
  end

  -- Detect overflow after children are laid out
  if self.element._detectOverflow then
    self.element:_detectOverflow()
  end

  -- Stop performance timing
  if timerName and LayoutEngine._Performance then
    LayoutEngine._Performance:stopTimer(timerName)
  end
end

--- Simulate wrapping children into lines for auto-sizing calculations
---@param children table Array of child elements
---@param availableSize number Available space in main axis
---@param isHorizontal boolean True if flex direction is horizontal
---@return table Array of lines, where each line is an array of children
function LayoutEngine:_simulateWrap(children, availableSize, isHorizontal)
  local lines = {}
  local currentLine = {}
  local currentLineSize = 0

  for _, child in ipairs(children) do
    -- Calculate child size in main axis (including margins)
    local childMainSize = 0
    local childMainMargin = 0
    if isHorizontal then
      childMainSize = child:getBorderBoxWidth()
      if child.margin then
        childMainMargin = child.margin.left + child.margin.right
      end
    else
      childMainSize = child:getBorderBoxHeight()
      if child.margin then
        childMainMargin = child.margin.top + child.margin.bottom
      end
    end
    local childTotalMainSize = childMainSize + childMainMargin

    -- Check if adding this child would exceed the available space
    local lineSpacing = #currentLine > 0 and self.gap or 0
    if #currentLine > 0 and currentLineSize + lineSpacing + childTotalMainSize > availableSize then
      -- Start a new line
      table.insert(lines, currentLine)
      currentLine = { child }
      currentLineSize = childTotalMainSize
    else
      -- Add to current line
      table.insert(currentLine, child)
      currentLineSize = currentLineSize + lineSpacing + childTotalMainSize
    end
  end

  -- Add the last line if it has children
  if #currentLine > 0 then
    table.insert(lines, currentLine)
  end

  return lines
end

--- Calculate auto width based on children
---@return number
function LayoutEngine:calculateAutoWidth()
  if self.element == nil then
    return 0
  end

  -- BORDER-BOX MODEL: Calculate content width, caller will add padding to get border-box
  local contentWidth = self.element:calculateTextWidth()
  if not self.element.children or #self.element.children == 0 then
    return contentWidth
  end

  -- Get flex children (children that participate in flex layout)
  -- Exclude display=false (CSS display:none) and explicitly absolute children
  local flexChildren = {}
  for _, child in ipairs(self.element.children) do
    if not child._explicitlyAbsolute and child.display ~= false then
      table.insert(flexChildren, child)
    end
  end

  if #flexChildren == 0 then
    return contentWidth
  end

  local isHorizontal = self:_isHorizontal()

  if isHorizontal then
    -- HORIZONTAL flex with potential wrapping
    if self.flexWrap ~= self._FlexWrap.NOWRAP and self.element.width and self.element.width > 0 then
      -- Container has explicit width and wrapping enabled - calculate based on wrapped lines
      local availableWidth = self.element.width
      local lines = self:_simulateWrap(flexChildren, availableWidth, true)

      -- Find the widest line
      local maxLineWidth = contentWidth
      for _, line in ipairs(lines) do
        local lineWidth = 0
        for i, child in ipairs(line) do
          local childBorderBoxWidth = child:getBorderBoxWidth()
          local childMarginH = 0
          if child.margin then
            childMarginH = child.margin.left + child.margin.right
          end
          lineWidth = lineWidth + childBorderBoxWidth + childMarginH
          if i < #line then
            lineWidth = lineWidth + self.gap
          end
        end
        maxLineWidth = math.max(maxLineWidth, lineWidth)
      end
      return maxLineWidth
    else
      -- No wrapping or no explicit width - sum all children on one line
      local totalWidth = contentWidth
      for i, child in ipairs(flexChildren) do
        local childBorderBoxWidth = child:getBorderBoxWidth()
        local childMarginH = 0
        if child.margin then
          childMarginH = child.margin.left + child.margin.right
        end
        totalWidth = totalWidth + childBorderBoxWidth + childMarginH
        if i < #flexChildren then
          totalWidth = totalWidth + self.gap
        end
      end
      return totalWidth
    end
  else
    -- VERTICAL flex - return max child width (including margins)
    local maxWidth = contentWidth
    for _, child in ipairs(flexChildren) do
      local childBorderBoxWidth = child:getBorderBoxWidth()
      childBorderBoxWidth = self.element:_adjustAutoWidthChildBorderBoxForManagedSelect(child, childBorderBoxWidth)
      local childMarginH = 0
      if child.margin then
        childMarginH = child.margin.left + child.margin.right
      end
      maxWidth = math.max(maxWidth, childBorderBoxWidth + childMarginH)
    end
    return maxWidth
  end
end

---@return number
function LayoutEngine:calculateAutoHeight()
  if self.element == nil then
    return 0
  end

  local height = self.element:calculateTextHeight()
  if not self.element.children or #self.element.children == 0 then
    return height
  end

  -- Get flex children (children that participate in flex layout)
  -- Exclude display=false (CSS display:none) and explicitly absolute children
  local flexChildren = {}
  for _, child in ipairs(self.element.children) do
    if not child._explicitlyAbsolute and child.display ~= false then
      table.insert(flexChildren, child)
    end
  end

  if #flexChildren == 0 then
    return height
  end

  local isVertical = not self:_isHorizontal()

  if isVertical then
    -- VERTICAL flex with potential wrapping
    if self.flexWrap ~= self._FlexWrap.NOWRAP and self.element.height and self.element.height > 0 then
      -- Container has explicit height and wrapping enabled - calculate based on wrapped lines
      local availableHeight = self.element.height
      local lines = self:_simulateWrap(flexChildren, availableHeight, false)

      -- Sum all line heights
      local totalLinesHeight = height
      for i, line in ipairs(lines) do
        local lineHeight = 0
        for _, child in ipairs(line) do
          local childBorderBoxHeight = child:getBorderBoxHeight()
          local childMarginV = 0
          if child.margin then
            childMarginV = child.margin.top + child.margin.bottom
          end
          lineHeight = math.max(lineHeight, childBorderBoxHeight + childMarginV)
        end
        totalLinesHeight = totalLinesHeight + lineHeight
        if i < #lines then
          totalLinesHeight = totalLinesHeight + self.gap
        end
      end
      return totalLinesHeight
    else
      -- No wrapping or no explicit height - sum all children on one line
      local totalHeight = height
      for i, child in ipairs(flexChildren) do
        local childBorderBoxHeight = child:getBorderBoxHeight()
        local childMarginV = 0
        if child.margin then
          childMarginV = child.margin.top + child.margin.bottom
        end
        totalHeight = totalHeight + childBorderBoxHeight + childMarginV
        if i < #flexChildren then
          totalHeight = totalHeight + self.gap
        end
      end
      return totalHeight
    end
  else
    -- HORIZONTAL flex with potential wrapping
    if self.flexWrap ~= self._FlexWrap.NOWRAP and self.element.width and self.element.width > 0 then
      -- Container has explicit width and wrapping enabled - calculate based on wrapped lines
      local availableWidth = self.element.width
      local lines = self:_simulateWrap(flexChildren, availableWidth, true)

      -- Sum all line heights (cross-axis for horizontal flex)
      local totalLinesHeight = height
      for i, line in ipairs(lines) do
        local lineHeight = 0
        for _, child in ipairs(line) do
          local childBorderBoxHeight = child:getBorderBoxHeight()
          local childMarginV = 0
          if child.margin then
            childMarginV = child.margin.top + child.margin.bottom
          end
          lineHeight = math.max(lineHeight, childBorderBoxHeight + childMarginV)
        end
        totalLinesHeight = totalLinesHeight + lineHeight
        if i < #lines then
          totalLinesHeight = totalLinesHeight + self.gap
        end
      end
      return totalLinesHeight
    else
      -- No wrapping or no explicit width - return max child height (including margins)
      local maxHeight = height
      for _, child in ipairs(flexChildren) do
        local childBorderBoxHeight = child:getBorderBoxHeight()
        local childMarginV = 0
        if child.margin then
          childMarginV = child.margin.top + child.margin.bottom
        end
        maxHeight = math.max(maxHeight, childBorderBoxHeight + childMarginV)
      end
      return maxHeight
    end
  end
end

--- Recalculate units based on new viewport dimensions (for vw, vh, % units)
---@param newViewportWidth number
---@param newViewportHeight number
function LayoutEngine:recalculateUnits(newViewportWidth, newViewportHeight)
  if self.element == nil then
    return
  end
  local Units = self._Units

  -- Get updated scale factors
  local scaleX, scaleY = self._Context.getScaleFactors()

  -- Recalculate border-box width if using viewport or percentage units (skip auto-sized)
  -- Store in _borderBoxWidth temporarily, will calculate content width after padding is resolved
  if self.element.units.width.unit ~= "px" and self.element.units.width.unit ~= "auto" then
    local parentWidth = self.element.parent and self.element.parent.width or newViewportWidth
    self.element._borderBoxWidth = Units.resolve(
      self.element.units.width.value,
      self.element.units.width.unit,
      newViewportWidth,
      newViewportHeight,
      parentWidth
    )
  elseif self.element.units.width.unit == "px" and self.element.units.width.value and self._Context.baseScale then
    -- Reapply base scaling to pixel widths (border-box)
    self.element._borderBoxWidth = self.element.units.width.value * scaleX
  end

  -- Recalculate border-box height if using viewport or percentage units (skip auto-sized)
  -- Store in _borderBoxHeight temporarily, will calculate content height after padding is resolved
  if self.element.units.height.unit ~= "px" and self.element.units.height.unit ~= "auto" then
    local parentHeight = self.element.parent and self.element.parent.height or newViewportHeight
    self.element._borderBoxHeight = Units.resolve(
      self.element.units.height.value,
      self.element.units.height.unit,
      newViewportWidth,
      newViewportHeight,
      parentHeight
    )
  elseif self.element.units.height.unit == "px" and self.element.units.height.value and self._Context.baseScale then
    -- Reapply base scaling to pixel heights (border-box)
    self.element._borderBoxHeight = self.element.units.height.value * scaleY
  end

  -- Recalculate position if using viewport or percentage units
  -- Skip position recalculation for flex children (non-explicitly-absolute children with a parent)
  -- Their x/y is entirely controlled by the parent's layoutChildren() call
  local isFlexChild = self.element.parent and not self.element._explicitlyAbsolute
  if not isFlexChild then
    if self.element.units.x.unit ~= "px" then
      local parentWidth = self.element.parent and self.element.parent.width or newViewportWidth
      local baseX = self.element.parent and self.element.parent.x or 0
      local offsetX = Units.resolve(
        self.element.units.x.value,
        self.element.units.x.unit,
        newViewportWidth,
        newViewportHeight,
        parentWidth
      )
      self.element.x = baseX + offsetX
    else
      -- For pixel units, update position relative to parent's new position (with base scaling)
      if self.element.parent then
        local baseX = self.element.parent.x
        local scaledOffset = self._Context.baseScale and (self.element.units.x.value * scaleX)
          or self.element.units.x.value
        self.element.x = baseX + scaledOffset
      elseif self._Context.baseScale then
        -- Top-level element with pixel position - apply base scaling
        self.element.x = self.element.units.x.value * scaleX
      end
    end

    if self.element.units.y.unit ~= "px" then
      local parentHeight = self.element.parent and self.element.parent.height or newViewportHeight
      local baseY = self.element.parent and self.element.parent.y or 0
      local offsetY = Units.resolve(
        self.element.units.y.value,
        self.element.units.y.unit,
        newViewportWidth,
        newViewportHeight,
        parentHeight
      )
      self.element.y = baseY + offsetY
    else
      -- For pixel units, update position relative to parent's new position (with base scaling)
      if self.element.parent then
        local baseY = self.element.parent.y
        local scaledOffset = self._Context.baseScale and (self.element.units.y.value * scaleY)
          or self.element.units.y.value
        self.element.y = baseY + scaledOffset
      elseif self._Context.baseScale then
        -- Top-level element with pixel position - apply base scaling
        self.element.y = self.element.units.y.value * scaleY
      end
    end
  end

  -- Recalculate textSize if auto-scaling is enabled or using viewport/element-relative units
  if self.element.autoScaleText and self.element.units.textSize.value then
    local unit = self.element.units.textSize.unit
    local value = self.element.units.textSize.value

    if unit == "px" and self._Context.baseScale then
      -- With base scaling: scale pixel values relative to base resolution
      self.element.textSize = value * scaleY
    elseif unit == "px" then
      -- Without base scaling but auto-scaling enabled: text doesn't scale
      self.element.textSize = value
    elseif unit == "%" or unit == "vh" then
      -- Percentage and vh are relative to viewport height
      self.element.textSize = Units.resolve(value, unit, newViewportWidth, newViewportHeight, newViewportHeight)
    elseif unit == "vw" then
      -- vw is relative to viewport width
      self.element.textSize = Units.resolve(value, unit, newViewportWidth, newViewportHeight, newViewportWidth)
    else
      self.element.textSize = Units.resolve(value, unit, newViewportWidth, newViewportHeight, nil)
    end

    -- Apply min/max constraints (with base scaling)
    local minSize = self.element.minTextSize
      and (self._Context.baseScale and (self.element.minTextSize * scaleY) or self.element.minTextSize)
    local maxSize = self.element.maxTextSize
      and (self._Context.baseScale and (self.element.maxTextSize * scaleY) or self.element.maxTextSize)

    if minSize and self.element.textSize < minSize then
      self.element.textSize = minSize
    end
    if maxSize and self.element.textSize > maxSize then
      self.element.textSize = maxSize
    end

    -- Protect against too-small text sizes (minimum 1px)
    if self.element.textSize < 1 then
      self.element.textSize = 1 -- Minimum 1px
    end
  elseif self.element.units.textSize.unit == "px" and self.element.units.textSize.value and self._Context.baseScale then
    -- No auto-scaling but base scaling is set: reapply base scaling to pixel text sizes
    self.element.textSize = self.element.units.textSize.value * scaleY

    -- Protect against too-small text sizes (minimum 1px)
    if self.element.textSize < 1 then
      self.element.textSize = 1 -- Minimum 1px
    end
  end

  -- Final protection: ensure textSize is always at least 1px (catches all edge cases)
  if self.element.text and self.element.textSize and self.element.textSize < 1 then
    self.element.textSize = 1 -- Minimum 1px
  end

  -- Recalculate gap if using viewport or percentage units
  if self.element.units.gap.unit ~= "px" then
    local containerSize = (self:_isHorizontal())
        and (self.element.parent and self.element.parent.width or newViewportWidth)
      or (self.element.parent and self.element.parent.height or newViewportHeight)
    self.element.gap = Units.resolve(
      self.element.units.gap.value,
      self.element.units.gap.unit,
      newViewportWidth,
      newViewportHeight,
      containerSize
    )
  end

  -- Recalculate flexBasis if using viewport or percentage units
  if
    self.element.units.flexBasis
    and self.element.units.flexBasis.unit ~= "auto"
    and self.element.units.flexBasis.unit ~= "px"
  then
    local value, unit = self.element.units.flexBasis.value, self.element.units.flexBasis.unit
    -- flexBasis uses parent main-axis size for percentage resolution.
    local parentMainIsHorizontal = true
    if self.element.parent and self.element.parent.flexDirection then
      local pd = self.element.parent.flexDirection
      parentMainIsHorizontal = pd == self._FlexDirection.HORIZONTAL or pd == self._FlexDirection.HORIZONTAL_REVERSE
    end
    local parentSize = newViewportWidth
    if self.element.parent then
      if parentMainIsHorizontal then
        parentSize = self.element.parent.width
      else
        parentSize = self.element.parent.height
      end
    end
    local resolvedBasis = Units.resolve(value, unit, newViewportWidth, newViewportHeight, parentSize)
    if type(resolvedBasis) == "number" then
      self.element.flexBasis = resolvedBasis
    end
  end

  -- Recalculate spacing (padding/margin) if using viewport or percentage units
  -- For percentage-based padding:
  -- - If element has a parent: use parent's border-box dimensions (CSS spec for child elements)
  -- - If element has no parent: use element's own border-box dimensions (CSS spec for root elements)
  local parentBorderBoxWidth = self.element.parent and self.element.parent._borderBoxWidth
    or self.element._borderBoxWidth
    or newViewportWidth
  local parentBorderBoxHeight = self.element.parent and self.element.parent._borderBoxHeight
    or self.element._borderBoxHeight
    or newViewportHeight

  -- Handle shorthand properties first (horizontal/vertical)
  local resolvedHorizontalPadding = nil
  local resolvedVerticalPadding = nil

  if self.element.units.padding.horizontal and self.element.units.padding.horizontal.unit ~= "px" then
    resolvedHorizontalPadding = Units.resolve(
      self.element.units.padding.horizontal.value,
      self.element.units.padding.horizontal.unit,
      newViewportWidth,
      newViewportHeight,
      parentBorderBoxWidth
    )
  elseif self.element.units.padding.horizontal and self.element.units.padding.horizontal.value then
    resolvedHorizontalPadding = self.element.units.padding.horizontal.value
  end

  if self.element.units.padding.vertical and self.element.units.padding.vertical.unit ~= "px" then
    resolvedVerticalPadding = Units.resolve(
      self.element.units.padding.vertical.value,
      self.element.units.padding.vertical.unit,
      newViewportWidth,
      newViewportHeight,
      parentBorderBoxHeight
    )
  elseif self.element.units.padding.vertical and self.element.units.padding.vertical.value then
    resolvedVerticalPadding = self.element.units.padding.vertical.value
  end
  -- Resolve individual padding sides (with fallback to shorthand)
  for _, side in ipairs({ "top", "right", "bottom", "left" }) do
    -- Check if this side was explicitly set or if we should use shorthand
    local useShorthand = false
    if not self.element.units.padding[side].explicit then
      -- Not explicitly set, check if we have shorthand
      if side == "left" or side == "right" then
        useShorthand = resolvedHorizontalPadding ~= nil
      elseif side == "top" or side == "bottom" then
        useShorthand = resolvedVerticalPadding ~= nil
      end
    end

    if useShorthand then
      -- Use shorthand value
      if side == "left" or side == "right" then
        self.element.padding[side] = resolvedHorizontalPadding
      else
        self.element.padding[side] = resolvedVerticalPadding
      end
    elseif self.element.units.padding[side].unit ~= "px" then
      -- Recalculate non-pixel units
      local parentSize = (side == "top" or side == "bottom") and parentBorderBoxHeight or parentBorderBoxWidth
      self.element.padding[side] = Units.resolve(
        self.element.units.padding[side].value,
        self.element.units.padding[side].unit,
        newViewportWidth,
        newViewportHeight,
        parentSize
      )
    end
    -- If unit is "px" and not using shorthand, value stays the same
  end

  -- Handle margin shorthand properties
  local resolvedHorizontalMargin = nil
  local resolvedVerticalMargin = nil

  if self.element.units.margin.horizontal and self.element.units.margin.horizontal.unit ~= "px" then
    resolvedHorizontalMargin = Units.resolve(
      self.element.units.margin.horizontal.value,
      self.element.units.margin.horizontal.unit,
      newViewportWidth,
      newViewportHeight,
      parentBorderBoxWidth
    )
  elseif self.element.units.margin.horizontal and self.element.units.margin.horizontal.value then
    resolvedHorizontalMargin = self.element.units.margin.horizontal.value
  end

  if self.element.units.margin.vertical and self.element.units.margin.vertical.unit ~= "px" then
    resolvedVerticalMargin = Units.resolve(
      self.element.units.margin.vertical.value,
      self.element.units.margin.vertical.unit,
      newViewportWidth,
      newViewportHeight,
      parentBorderBoxHeight
    )
  elseif self.element.units.margin.vertical and self.element.units.margin.vertical.value then
    resolvedVerticalMargin = self.element.units.margin.vertical.value
  end

  -- Resolve individual margin sides (with fallback to shorthand)
  for _, side in ipairs({ "top", "right", "bottom", "left" }) do
    -- Check if this side was explicitly set or if we should use shorthand
    local useShorthand = false
    if not self.element.units.margin[side].explicit then
      -- Not explicitly set, check if we have shorthand
      if side == "left" or side == "right" then
        useShorthand = resolvedHorizontalMargin ~= nil
      elseif side == "top" or side == "bottom" then
        useShorthand = resolvedVerticalMargin ~= nil
      end
    end

    if useShorthand then
      -- Use shorthand value
      if side == "left" or side == "right" then
        self.element.margin[side] = resolvedHorizontalMargin
      else
        self.element.margin[side] = resolvedVerticalMargin
      end
    elseif self.element.units.margin[side].unit ~= "px" then
      -- Recalculate non-pixel units
      local parentSize = (side == "top" or side == "bottom") and parentBorderBoxHeight or parentBorderBoxWidth
      self.element.margin[side] = Units.resolve(
        self.element.units.margin[side].value,
        self.element.units.margin[side].unit,
        newViewportWidth,
        newViewportHeight,
        parentSize
      )
    end
    -- If unit is "px" and not using shorthand, value stays the same
  end

  -- BORDER-BOX MODEL: Calculate content dimensions from border-box dimensions
  -- For explicitly-sized elements (non-auto), _borderBoxWidth/_borderBoxHeight were set earlier
  -- Now we calculate content width/height by subtracting padding
  -- Only recalculate if using viewport/percentage units (where _borderBoxWidth actually changed)
  if self.element.units.width.unit ~= "auto" and self.element.units.width.unit ~= "px" then
    -- _borderBoxWidth was recalculated for viewport/percentage units
    -- Calculate content width by subtracting padding
    self.element.width =
      math.max(0, self.element._borderBoxWidth - self.element.padding.left - self.element.padding.right)
  elseif self.element.units.width.unit == "auto" then
    -- For auto-sized elements, width is content width (calculated in resize method)
    -- Update border-box to include padding
    self.element._borderBoxWidth = self.element.width + self.element.padding.left + self.element.padding.right
  end
  -- For pixel units, width stays as-is (may have been manually modified)

  if self.element.units.height.unit ~= "auto" and self.element.units.height.unit ~= "px" then
    -- _borderBoxHeight was recalculated for viewport/percentage units
    -- Calculate content height by subtracting padding
    self.element.height =
      math.max(0, self.element._borderBoxHeight - self.element.padding.top - self.element.padding.bottom)
  elseif self.element.units.height.unit == "auto" then
    -- For auto-sized elements, height is content height (calculated in resize method)
    -- Update border-box to include padding
    self.element._borderBoxHeight = self.element.height + self.element.padding.top + self.element.padding.bottom
  end
  -- For pixel units, height stays as-is (may have been manually modified)

  -- Detect overflow after layout calculations
  if self.element._detectOverflow then
    self.element:_detectOverflow()
  end
end

--- Check if layout can be skipped based on cached state (memoization)
---@return boolean canSkip True if layout hasn't changed and can be skipped
function LayoutEngine:_canSkipLayout()
  if not self.element then
    return false
  end

  -- Performance optimization: Check dirty flags first (fastest check)
  -- If element or children are marked dirty, we must recalculate
  if self.element._dirty or self.element._childrenDirty then
    -- Clear dirty flags after acknowledging them
    self.element._dirty = false
    self.element._childrenDirty = false
    return false
  end

  -- If not dirty, check if layout inputs have actually changed (secondary check)
  local childrenCount = #self.element.children
  local containerWidth = self.element.width
  local containerHeight = self.element.height
  local containerX = self.element.x
  local containerY = self.element.y

  -- Generate simple hash of children dimensions + display state
  local childrenHash = ""
  for i, child in ipairs(self.element.children) do
    if i <= 5 then -- Only hash first 5 children for performance
      childrenHash = childrenHash .. child.width .. "x" .. child.height .. "d" .. tostring(child.display) .. ","
    end
  end

  local cache = self._layoutCache

  -- Check if layout inputs have changed
  if
    cache.childrenCount == childrenCount
    and cache.containerWidth == containerWidth
    and cache.containerHeight == containerHeight
    and cache.containerX == containerX
    and cache.containerY == containerY
    and cache.childrenHash == childrenHash
  then
    return true -- Layout hasn't changed, can skip
  end

  -- Update cache with current values
  cache.childrenCount = childrenCount
  cache.containerWidth = containerWidth
  cache.containerHeight = containerHeight
  cache.containerX = containerX
  cache.containerY = containerY
  cache.childrenHash = childrenHash

  return false -- Layout has changed, must recalculate
end

--- Track layout recalculations and warn about excessive layouts
function LayoutEngine:_trackLayoutRecalculation()
  if not LayoutEngine._Performance or not LayoutEngine._Performance.warningsEnabled then
    return
  end

  -- Get current frame count from Context
  local currentFrame = self._Context and self._Context._frameNumber or 0

  -- Reset counter on new frame
  if currentFrame ~= self._lastFrameCount then
    self._lastFrameCount = currentFrame
    self._layoutCount = 0
  end

  -- Increment layout count
  self._layoutCount = self._layoutCount + 1

  -- Warn if layout is recalculated excessively this frame
  if self._layoutCount >= 10 then
    local elementId = self.element and self.element.id or "unnamed"
    LayoutEngine._Performance:logWarning(
      string.format("excessive_layout_%s", elementId),
      "LayoutEngine",
      string.format("Layout recalculated %d times this frame for element '%s'", self._layoutCount, elementId),
      { layoutCount = self._layoutCount, elementId = elementId },
      "This may indicate a layout thrashing issue. Check for circular dependencies or dynamic sizing that triggers re-layout"
    )
  end
end

return LayoutEngine
