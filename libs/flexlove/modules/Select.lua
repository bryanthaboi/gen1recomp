---@class Select
local Select = {}

---Initialize Select module with required dependencies
---@param deps table
function Select.init(deps)
  Select._ErrorHandler = deps.ErrorHandler
  Select._Context = deps.Context
  Select._StateManager = deps.StateManager
  Select._utils = deps.utils
  Select._Element = deps.Element
end

---Initialize selectParent state on an element
---@param element Element
---@param selectParentConfig table
function Select.initSelectParent(element, selectParentConfig)
  element._selectState = {
    value = selectParentConfig.value,
    open = selectParentConfig.open or false,
    placeholder = selectParentConfig.placeholder,
    selectFrame = nil,
    selectAnchor = nil,
    onChange = selectParentConfig.onChange,
    options = {},
    optionLookup = {},
    expectedFrameParent = nil,
    frameAdopted = false,
  }

  -- Restore select state from StateManager. Mode-aware via
  -- Context.isImmediateMode (behavior-mode-unification task 11).
  if Select._Context.isImmediateMode() and element._stateId and element._stateId ~= "" then
    local state = Select._StateManager.getState(element._stateId)
    if state and state._selectOpen ~= nil then
      element._selectState.open = state._selectOpen
    end
    if state and state._selectValue ~= nil then
      element._selectState.value = state._selectValue
      if element.selectParent then
        element.selectParent.value = state._selectValue
      end
    end
    if state and state._selectSelectedLabel ~= nil then
      element._selectState.selectedLabel = state._selectSelectedLabel
    end
  end
end

---Initialize selectOption on an element
---@param element Element
---@param selectOptionConfig table
function Select.initSelectOption(element, selectOptionConfig)
  element.selectOption = {
    value = selectOptionConfig.value,
    label = selectOptionConfig.label or element.text,
    disabled = selectOptionConfig.disabled or false,
  }
end

---@param selectParent Element
function Select.rebuildOptionLookup(selectParent)
  if not selectParent or not selectParent._selectState then
    return
  end

  selectParent._selectState.optionLookup = {}
  for _, optionElement in ipairs(selectParent._selectState.options) do
    if optionElement and optionElement.selectOption then
      selectParent._selectState.optionLookup[optionElement.selectOption.value] = optionElement
    end
  end
end

---@param selectParent Element
function Select.syncOptionStates(selectParent)
  if not selectParent or not selectParent._selectState then
    return
  end

  local selectedOption = nil
  local selectedLabel = selectParent._selectState.selectedLabel

  for _, optionElement in ipairs(selectParent._selectState.options) do
    local isSelected = optionElement.selectOption
      and optionElement.selectOption.value == selectParent._selectState.value
    optionElement._selectSelected = isSelected
    optionElement.ariaChecked = isSelected

    if isSelected then
      selectedOption = optionElement
      selectedLabel = optionElement.selectOption.label or optionElement.text
    end
  end

  selectParent._selectState.selectedOption = selectedOption
  selectParent._selectState.selectedLabel = selectedLabel
end

---@param element Element
function Select.resetOptions(element)
  if not element._selectState then
    return
  end

  element._selectState.options = {}
  element._selectState.optionLookup = {}
  element._selectState.selectedOption = nil
end

---@param frame any
---@return boolean
function Select.isValidSelectFrame(frame)
  local Element = Select._Element
  return type(frame) == "table" and getmetatable(frame) == Element
end

---@param element Element
---@param code string
---@param details table?
function Select.warnSelectFrame(element, code, details)
  Select._ErrorHandler:warn("Element", code, details or { element = element.id })
end

---@param element Element
---@param frame Element
function Select.trackManagedFrame(element, frame)
  element._selectState.selectFrame = frame
  local expectedParent = element._selectState.selectAnchor or element
  element._selectState.expectedFrameParent = expectedParent
  element._selectState.frameAdopted = frame.parent == expectedParent
  if frame._managedSelectBaseOpacity == nil then
    frame._managedSelectBaseOpacity = frame.opacity
  end
  if frame._managedSelectBaseVisibility == nil then
    frame._managedSelectBaseVisibility = frame.visibility or "visible"
  end
  if frame._managedSelectBaseDisabled == nil then
    frame._managedSelectBaseDisabled = frame.disabled or false
  end
  frame._managedSelectOwner = element
  frame._managedSelectFrame = true
end

---@param element Element
---@return Element
function Select.getOrCreateManagedAnchor(element)
  if element._selectState.selectAnchor then
    return element._selectState.selectAnchor
  end

  local Element = Select._Element
  local anchor = Element.new({
    id = string.format("%s__select_anchor", element.id or "select"),
    parent = element,
    positioning = Select._utils.enums.Positioning.ABSOLUTE,
    left = 0,
    top = element:getBorderBoxHeight(),
    width = element:getBorderBoxWidth(),
    opacity = 1,
    visibility = "hidden",
    disabled = true,
  })

  anchor._managedSelectAnchor = true
  anchor._managedSelectOwner = element
  element._selectState.selectAnchor = anchor
  return anchor
end

---@param element Element
---@param frame Element
function Select.applyManagedFrameLayout(element, frame)
  local anchor = Select.getOrCreateManagedAnchor(element)
  local triggerBorderBoxWidth = element:getBorderBoxWidth()
  anchor.left = 0
  anchor.top = element:getBorderBoxHeight()
  anchor.width = triggerBorderBoxWidth
  anchor.units.left = { value = 0, unit = "px" }
  anchor.units.top = { value = element:getBorderBoxHeight(), unit = "px" }
  anchor.units.width = { value = triggerBorderBoxWidth, unit = "px" }
  frame._managedSelectMinimumBorderBoxWidth = triggerBorderBoxWidth

  frame.positioning = frame.positioning or Select._utils.enums.Positioning.RELATIVE
  frame._explicitlyAbsolute = false
  frame.left = nil
  frame.top = nil
  frame.right = nil
  frame.bottom = nil

  if frame.parent ~= anchor then
    frame:setParent(anchor)
  end

  if frame.autosizing and frame.autosizing.width then
    local contentWidth = frame:calculateAutoWidth()
    frame._borderBoxWidth = contentWidth + frame.padding.left + frame.padding.right
    frame.width = contentWidth
  end

  if frame.parent == anchor then
    anchor.width = math.max(triggerBorderBoxWidth, frame:getBorderBoxWidth())
    anchor.units.width = { value = anchor.width, unit = "px" }
  end

  element._selectState.expectedFrameParent = anchor
  element._selectState.frameAdopted = frame.parent == anchor
end

---@param element Element
---@param frame Element
function Select.adoptSelectFrame(element, frame)
  if not element._selectState then
    return
  end

  if not Select.isValidSelectFrame(frame) then
    Select.warnSelectFrame(element, "ELEM_007", {
      element = element.id,
      property = "selectParent.selectFrame",
      got = type(frame),
    })
    return
  end

  if frame == element then
    Select.warnSelectFrame(element, "ELEM_007", {
      element = element.id,
      property = "selectParent.selectFrame",
      reason = "select cannot use itself as its managed frame",
    })
    return
  end

  local anchor = Select.getOrCreateManagedAnchor(element)

  if frame.parent and frame.parent ~= element and frame.parent ~= anchor then
    Select.warnSelectFrame(element, "ELEM_008", {
      element = element.id,
      frame = frame.id,
      parent = frame.parent.id,
    })
  end

  Select.trackManagedFrame(element, frame)
  Select.applyManagedFrameLayout(element, frame)
  Select.syncManagedFrameVisibility(element)

  -- Layout is deferred to endFrame in immediate mode. shouldLayout()
  -- encapsulates the mode check (behavior-mode-unification task 11).
  if Select._StateManager.shouldLayout() then
    anchor:layoutChildren()
    element:layoutChildren()
  end

  local pendingOptions = {}
  for _, child in ipairs(element.children) do
    if child ~= frame and child.selectOption then
      table.insert(pendingOptions, child)
    end
  end

  for _, option in ipairs(pendingOptions) do
    Select.attachOptionToManagedFrame(option)
  end
end

---@param element Element
function Select.ensureFrameState(element)
  if not element._selectState or not element._selectState.selectFrame then
    return
  end

  local frame = element._selectState.selectFrame
  local anchor = element._selectState.selectAnchor
  if anchor then
    local triggerBorderBoxWidth = element:getBorderBoxWidth()
    anchor.left = 0
    anchor.top = element:getBorderBoxHeight()
    anchor.width = triggerBorderBoxWidth
    anchor.units.left = { value = 0, unit = "px" }
    anchor.units.top = { value = element:getBorderBoxHeight(), unit = "px" }
    anchor.units.width = { value = triggerBorderBoxWidth, unit = "px" }
    frame._managedSelectMinimumBorderBoxWidth = triggerBorderBoxWidth
    if frame.autosizing and frame.autosizing.width then
      local contentWidth = frame:calculateAutoWidth()
      frame._borderBoxWidth = contentWidth + frame.padding.left + frame.padding.right
      frame.width = contentWidth
    end
    if frame.parent == anchor then
      anchor.width = math.max(triggerBorderBoxWidth, frame:getBorderBoxWidth())
      anchor.units.width = { value = anchor.width, unit = "px" }
    end
    if frame.parent == anchor then
      anchor:layoutChildren()
    end
  elseif frame.parent == element then
    Select.applyManagedFrameLayout(element, frame)
  end

  local expectedParent = anchor or element._selectState.expectedFrameParent
  if frame.parent ~= expectedParent then
    Select.warnSelectFrame(element, "ELEM_009", {
      element = element.id,
      frame = frame.id,
      expectedParent = expectedParent and expectedParent.id or nil,
      actualParent = frame.parent and frame.parent.id or nil,
    })
    element._selectState.expectedFrameParent = frame.parent
    element._selectState.frameAdopted = frame.parent == expectedParent
  end
end

---@param element Element
function Select.syncManagedFrameVisibility(element)
  if not element._selectState or not element._selectState.selectFrame then
    return
  end

  local frame = element._selectState.selectFrame
  local anchor = element._selectState.selectAnchor
  local isOpen = element._selectState.open == true
  frame.visibility = isOpen and (frame._managedSelectBaseVisibility or "visible") or "hidden"
  frame.opacity = frame._managedSelectBaseOpacity or 1
  if isOpen then
    frame.disabled = frame._managedSelectBaseDisabled == true
  else
    frame.disabled = true
  end
  if anchor then
    anchor.visibility = isOpen and "visible" or "hidden"
    anchor.opacity = 1
    anchor.disabled = not isOpen
  end
end

---@param element Element
---@return Element?
function Select.findOwningSelectParent(element)
  if element._selectParentHint and element._selectParentHint._selectState then
    return element._selectParentHint
  end

  local current = element.parent
  while current do
    if current._selectState then
      return current
    end
    current = current.parent
  end

  return nil
end

---@param element Element
function Select.registerWithSelectParent(element)
  if not element.selectOption then
    return
  end

  local selectParent = Select.findOwningSelectParent(element)
  if not selectParent then
    return
  end

  element._selectParentElement = selectParent

  for _, optionElement in ipairs(selectParent._selectState.options) do
    if optionElement == element then
      return
    end
  end

  table.insert(selectParent._selectState.options, element)
  Select.rebuildOptionLookup(selectParent)
  Select.syncOptionStates(selectParent)
end

---@param element Element
function Select.attachOptionToManagedFrame(element)
  if not element.selectOption then
    return
  end

  local selectParent = Select.findOwningSelectParent(element)
  if not selectParent or not selectParent._selectState or not selectParent._selectState.selectFrame then
    return
  end

  local selectFrame = selectParent._selectState.selectFrame
  if element.parent ~= selectFrame then
    element._selectParentHint = selectParent

    if
      element._originalPositioning == Select._utils.enums.Positioning.ABSOLUTE
      and element._managedSelectOptionUsesFrameLayout == nil
    then
      element._managedSelectOptionUsesFrameLayout = true
      element.positioning = Select._utils.enums.Positioning.RELATIVE
      element._originalPositioning = nil
      element._explicitlyAbsolute = false
      element.left = nil
      element.top = nil
      element.right = nil
      element.bottom = nil
    end

    element:setParent(selectFrame)
    -- Ensure frame geometry eagerly only in retained mode; deferred to the
    -- per-frame update in immediate mode (behavior-mode-unification task 11).
    if Select._StateManager.shouldLayout() then
      Select.ensureFrameState(selectParent)
    end
  end
end

---@param element Element
function Select.unregisterFromSelectParent(element)
  if not element.selectOption or not element._selectParentElement or not element._selectParentElement._selectState then
    element._selectParentElement = nil
    return
  end

  local selectParent = element._selectParentElement
  for index, optionElement in ipairs(selectParent._selectState.options) do
    if optionElement == element then
      table.remove(selectParent._selectState.options, index)
      break
    end
  end

  Select.rebuildOptionLookup(selectParent)
  Select.syncOptionStates(selectParent)
  element._selectParentElement = nil
end

---@param element Element
function Select.saveStateToStateManager(element)
  if not element._selectState then
    return
  end
  if element._stateId and Select._Context.isImmediateMode() and element._stateId ~= "" then
    Select._StateManager.updateState(element._stateId, {
      _selectOpen = element._selectState.open,
      _selectValue = element._selectState.value,
      _selectSelectedLabel = element._selectState.selectedLabel,
    })
  end
end

---@param element Element
function Select.openSelect(element)
  if not element._selectState then
    return
  end

  Select.ensureFrameState(element)
  element._selectState.open = true
  element.ariaExpanded = true
  if element.selectParent then
    element.selectParent.open = true
  end
  Select.syncManagedFrameVisibility(element)
  Select.saveStateToStateManager(element)
end

---@param element Element
function Select.closeSelect(element)
  if not element._selectState then
    return
  end

  Select.ensureFrameState(element)
  element._selectState.open = false
  element.ariaExpanded = false
  if element.selectParent then
    element.selectParent.open = false
  end
  Select.syncManagedFrameVisibility(element)
  Select.saveStateToStateManager(element)
end

---@param element Element
function Select.toggleSelect(element)
  if not element._selectState then
    return
  end

  if element.disabled then
    return
  end

  if element._selectState.open then
    Select.closeSelect(element)
  else
    Select.openSelect(element)
  end

  if element.onEvent then
    element.onEvent(element, { type = "selecttoggle", open = element._selectState.open })
  end
end

---@param element Element
---@return boolean
function Select.isSelectOpen(element)
  return element._selectState ~= nil and element._selectState.open == true
end

---@param element Element
---@return any
function Select.getSelectValue(element)
  if not element._selectState then
    return nil
  end
  return element._selectState.value
end

---@param element Element
---@return string?
function Select.getSelectLabel(element)
  if not element._selectState then
    return nil
  end

  local selectedOption = element._selectState.selectedOption
    or element._selectState.optionLookup[element._selectState.value]
  if selectedOption and selectedOption.selectOption then
    return selectedOption.selectOption.label or selectedOption.text
  end

  return element._selectState.selectedLabel or element._selectState.placeholder
end

---@param element Element
---@return boolean
function Select.isSelectedOption(element)
  if not element.selectOption or not element._selectParentElement or not element._selectParentElement._selectState then
    return false
  end
  return element._selectParentElement._selectState.value == element.selectOption.value
end

---@param element Element
---@param value any
---@param optionElement Element?
function Select.setSelectValue(element, value, optionElement)
  if not element._selectState then
    return
  end

  if element.disabled then
    return
  end

  local didChange = element._selectState.value ~= value
  element._selectState.value = value
  if element.selectParent then
    element.selectParent.value = value
  end

  if optionElement and optionElement.selectOption then
    element._selectState.selectedLabel = optionElement.selectOption.label or optionElement.text
  end

  Select.syncOptionStates(element)
  Select.closeSelect(element)
  Select.saveStateToStateManager(element)

  if element.onEvent then
    element.onEvent(element, { type = "selectchange", value = value, option = optionElement })
  end

  if didChange and element._selectState.onChange then
    element._selectState.onChange(element, value, optionElement and optionElement.selectOption or nil)
  end
end

---@param element Element
function Select.handleRelease(element)
  if element.disabled then
    return
  end

  if element.selectOption then
    local selectParent = element._selectParentElement or Select.findOwningSelectParent(element)
    if not selectParent then
      return
    end

    if element.selectOption.disabled then
      Select.closeSelect(selectParent)
      return
    end

    Select.setSelectValue(selectParent, element.selectOption.value, element)
    return
  end

  if element._selectState then
    Select.toggleSelect(element)
  end
end

---Save select state for state persistence (called from Element:saveState)
---@param element Element
---@return table?
function Select.saveState(element)
  if not element._selectState then
    return nil
  end
  return {
    value = element._selectState.value,
    open = element._selectState.open,
    selectedLabel = element._selectState.selectedLabel,
  }
end

---Restore select state (called from Element:restoreState)
---@param element Element
---@param state table
function Select.restoreState(element, state)
  if not element._selectState or not state then
    return
  end
  element._selectState.value = state.value
  element._selectState.open = state.open or false
  element._selectState.selectedLabel = state.selectedLabel
  if element.selectParent then
    element.selectParent.value = state.value
    element.selectParent.open = state.open or false
  end
  element.ariaExpanded = element._selectState.open
  Select.syncOptionStates(element)
end

---Clean up select-related resources (called from Element:destroy)
---@param element Element
function Select.cleanupDestroy(element)
  if element._selectState then
    local frame = element._selectState.selectFrame
    local anchor = element._selectState.selectAnchor
    if frame then
      frame._managedSelectOwner = nil
      frame._managedSelectFrame = nil
      frame._managedSelectBaseOpacity = nil
      frame._managedSelectBaseVisibility = nil
      frame._managedSelectBaseDisabled = nil
    end
    if anchor then
      anchor._managedSelectOwner = nil
      anchor._managedSelectAnchor = nil
    end
    element._selectState = nil
  end
  if element._managedSelectFrame and element._managedSelectOwner then
    if element._managedSelectOwner._selectState then
      element._managedSelectOwner._selectState.selectFrame = nil
      element._managedSelectOwner._selectState.expectedFrameParent = nil
      element._managedSelectOwner._selectState.frameAdopted = false
    end
    element._managedSelectOwner = nil
    element._managedSelectFrame = nil
    element._managedSelectBaseOpacity = nil
    element._managedSelectBaseVisibility = nil
    element._managedSelectBaseDisabled = nil
  end
  if element._managedSelectAnchor and element._managedSelectOwner then
    if element._managedSelectOwner._selectState then
      element._managedSelectOwner._selectState.selectAnchor = nil
    end
    element._managedSelectOwner = nil
    element._managedSelectAnchor = nil
  end
  if element.selectParent then
    element.selectParent.onChange = nil
  end
end

--- Called when a select parent removes a child: clears frame/anchor refs if the removed child was the
--- select-managed frame or anchor. Keeps select state-mutation logic owned by the Select module.
---@param element Element The select parent whose child was removed.
---@param child Element The removed child.
function Select.handleChildRemoved(element, child)
  if not element._selectState then
    return
  end
  if element._selectState.selectFrame == child then
    element._selectState.selectFrame = nil
    element._selectState.expectedFrameParent = nil
    element._selectState.frameAdopted = false
  end
  if element._selectState.selectAnchor == child then
    element._selectState.selectAnchor = nil
  end
end

--- Layout-path hook: adjust an auto-width child's border-box width for a managed-select frame.
--- Invoked from LayoutEngine (via the Element delegate) during vertical-flex auto-width calculation.
---@param element Element The managed-select frame (the dropdown container).
---@param child Element The flex child being measured.
---@param childBorderBoxWidth number Current computed border-box width of `child`.
---@return number Possibly-adjusted border-box width.
function Select.adjustAutoWidthChild(element, child, childBorderBoxWidth)
  if
    element._managedSelectFrame
    and element.autosizing
    and element.autosizing.width
    and child.units
    and child.units.width
    and child.units.width.unit == "%"
  then
    local intrinsicBorderBoxWidth = child:calculateAutoWidth() + child.padding.left + child.padding.right
    return math.max(childBorderBoxWidth, intrinsicBorderBoxWidth)
  end
  return childBorderBoxWidth
end

return Select
