-- modules/behaviors/TextEditable.lua
--
-- Concrete behavior: TextEditor subsystem ownership — text editing, cursor
-- management, text selection, text-related input handling, and text-editor
-- state save/restore.
--
-- This behavior consolidates the legacy `if self._textEditor` nil-guard
-- patterns that previously lived inside Element.lua:
--
--   * TextEditor creation + immediate-mode state restore (formerly
--     Element:_initSubSystems lines ~813-830 — the `if self.editable then
--     self._textEditor = Element._TextEditor.new {...}` block).
--   * Cursor-blink update (formerly Element:update line ~2810 —
--     `if self._textEditor then self._textEditor:update(self, dt) end`).
--   * The 27 text-editor delegate methods (formerly Element:setText /
--     getText / setCursorPosition / setSelection / focus / textinput /
--     keypressed / _handleTextClick / _handleTextDrag / ...). Each was a 3-line
--     nil-guard stub (check `_textEditor`, forward call, end). They are now
--     module-level functions on this behavior; Element retains only 1-line
--     forwarders that route through `Element._TextEditable.<fn>(self, ...)`.
--   * Text-editor state save/restore (formerly the textEditor branch of
--     Element:saveState / Element:restoreState), including the cursor/selection
--     field sync and the text-selection drag-tracking fields
--     (`_mouseDownPosition` / `_textDragOccurred`).
--
-- Element retains the `self._textEditor` field for backward-compat field
-- access (Renderer:drawText reads it directly for cursor/selection rendering);
-- runtime state lives ON THE ELEMENT. The behavior itself is stateless +
-- immutable + shared across elements.
--
-- State ownership (per the locked Behavior contract):
--   * Per-element runtime state lives ON THE ELEMENT (`self._textEditor`,
--     `self._mouseDownPosition`, `self._textDragOccurred`). The behavior
--     instance is stateless + immutable and shared across all editable
--     elements.
--   * Element-class-level dependencies are resolved via `getmetatable(element)`
--     (which IS the Element class set by Element._construct), so the hook
--     signature stays exactly `(element, ...)` with no DI parameters.
--
-- onDraw is a no-op: text/cursor/selection rendering stays in the Renderer's
-- command buffer (Layer 4 "text"), driven by the Thamed behavior's single
-- `Renderer:draw` call. The Renderer's `drawText` already reads
-- `element._textEditor` for cursor/selection, so TextEditable OWNS the
-- subsystem that drawText consumes, but the draw dispatch stays in the
-- renderer to preserve the unified transform/scissor command-buffer ordering
-- (mirrors Selectable.onDraw's no-op precedent, where rendering is owned by a
-- different layer). Hoisting drawText into this behavior's onDraw would
-- double-render text, since the Renderer command buffer already emits a "text"
-- layer for every element.

local _pkg = (...):match("^(.-)behaviors%.") or "modules."
local Behavior = require(_pkg .. "Behavior")

-- Resolve the Element class from an element instance (mirrors Clickable /
-- Selectable). `setmetatable({}, Element)` in `_construct` makes the instance
-- metatable BE the Element class, so this yields Element._TextEditor,
-- Element._textEditorDeps, Element._Context, Element._StateManager, etc.
-- without threading deps through the hook signature.
local function ElementClass(element)
  return getmetatable(element)
end

-- ============================================================================
-- shouldAttach (class-level predicate, no element required)
-- ============================================================================

-- Mirrors the spec predicate: attach when the element is text-editable OR
-- carries text content. onAttach only ALLOCATES a TextEditor when
-- `element.editable` is true (preserving the pre-refactor creation invariant
-- "TextEditor created iff editable"), so non-editable text labels attach the
-- behavior but allocate no TextEditor — their onUpdate/onDraw/saveState are
-- nil-guarded no-ops, and the Element forwarders route them through the
-- non-editable branch of each delegate function (reads/writes `element.text`
-- directly). This keeps shouldAttach faithful to the spec while preserving
-- exact pre-refactor allocation behavior.
local function shouldAttach(props)
  props = props or {}
  return props.editable == true or props.text ~= nil
end

-- ============================================================================
-- onAttach — create the TextEditor (formerly Element:_initSubSystems lines
-- ~813-830) and restore immediate-mode TextEditor state.
-- ============================================================================

local function onAttach(element)
  local Element = ElementClass(element)

  -- Only editable elements own a TextEditor. Preserves the exact pre-refactor
  -- creation guard (`if self.editable then ... end`) — non-editable text
  -- elements attach the behavior (so their forwarders route through a single
  -- code path) but allocate no TextEditor.
  if not element.editable then
    return
  end

  -- Config is sourced from element fields (bound by _applyProps / _initVisualState
  -- before _attachBehaviors runs at the tail of Element.new) — NOT from raw
  -- props. The callbacks (onFocus/onBlur/onTextInput/onTextChange/onEnter) are
  -- schema-bound element fields by this point, and `element.text` is set by
  -- _initVisualState, so no `props` reference is needed here (the hook
  -- signature is `(element)`).
  element._textEditor = Element._TextEditor.new({
    editable = element.editable,
    multiline = element.multiline,
    passwordMode = element.passwordMode,
    textWrap = element.textWrap,
    maxLines = element.maxLines,
    maxLength = element.maxLength,
    placeholder = element.placeholder,
    inputType = element.inputType,
    textOverflow = element.textOverflow,
    scrollable = element.scrollable,
    autoGrow = element.autoGrow,
    selectOnFocus = element.selectOnFocus,
    cursorColor = element.cursorColor,
    selectionColor = element.selectionColor,
    cursorBlinkRate = element.cursorBlinkRate,
    text = element.text or "",
    onFocus = element.onFocus,
    onBlur = element.onBlur,
    onTextInput = element.onTextInput,
    onTextChange = element.onTextChange,
    onEnter = element.onEnter,
  }, Element._textEditorDeps)

  -- Restore TextEditor state from StateManager in immediate mode. Mirrors the
  -- legacy _initSubSystems immediate-mode restore. Safe to run here (after
  -- _construct registered the element with StateManager) — the StateManager
  -- lookup is sparse and returns nil for a fresh element. Mode-aware via
  -- Context.isImmediateMode (behavior-mode-unification task 11).
  if Element._Context.isImmediateMode() and element._stateId and element._stateId ~= "" then
    local state = Element._StateManager.getState(element._stateId)
    if state and state.textEditor then
      element._textEditor:setState(state.textEditor, element)
    end
  end
end

local function onDetach(element)
  -- Clear text-input callback closures read by TextEditor / KeyboardNavigation
  -- so the element's closure references can be collected in immediate mode
  -- (formerly part of Element:_cleanup). The TextEditor instance itself is
  -- INTENTIONALLY kept: Element:_cleanup preserves element structure for
  -- inspection (released when the element is GC'd).
  element.onTextInput = nil
  element.onTextChange = nil
  element.onEnter = nil
end

-- ============================================================================
-- onUpdate — cursor-blink animation (formerly Element:update line ~2810).
-- ============================================================================

-- Drives TextEditor:update (cursor blink + blink-pause timer). Guarded on
-- `element._textEditor` because non-editable text elements attach this
-- behavior (per shouldAttach) but own no TextEditor. Element:update contains
-- zero text-editor references — the dispatch loop calls this hook.
local function onUpdate(element, dt)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:update(element, dt)
  end
end

-- ============================================================================
-- onDraw — no-op (see file header: text rendering stays in the Renderer
-- command buffer driven by the Thamed behavior's Renderer:draw call).
-- ============================================================================

local function onDraw() end

-- ============================================================================
-- saveState / restoreState — TextEditor state + text-selection drag
-- tracking (formerly the textEditor branch of Element:saveState /
-- Element:restoreState, including the _mouseDownPosition / _textDragOccurred
-- fields).
-- ============================================================================

-- Returns a snapshot under the `textEditor` key to match the legacy immediate-
-- mode restoreState contract (Element:restoreState looked up state.textEditor).
-- The behavior-dispatch loop in Element:saveState merges behavior snapshots
-- into the top-level state table, so returning { textEditor = ... } slots in
-- identically to the old inline `state.textEditor = self._textEditor:getState()`
-- assignment. The drag-tracking fields are merged at the top level too
-- (matching the legacy `state._mouseDownPosition` / `state._textDragOccurred`
-- assignments) since they are text-selection state.
local function saveState(element)
  local textEditor = element._textEditor
  if not textEditor then
    -- Non-editable text element: still persist drag-tracking fields if set
    -- (they are only ever set for editable elements, but persist defensively).
    local hasDragState = element._mouseDownPosition ~= nil or element._textDragOccurred ~= nil
    if not hasDragState then
      return nil
    end
    local snapshot = {}
    if element._mouseDownPosition ~= nil then
      snapshot._mouseDownPosition = element._mouseDownPosition
    end
    if element._textDragOccurred ~= nil then
      snapshot._textDragOccurred = element._textDragOccurred
    end
    return snapshot
  end

  local snapshot = { textEditor = textEditor:getState() }
  if element._mouseDownPosition ~= nil then
    snapshot._mouseDownPosition = element._mouseDownPosition
  end
  if element._textDragOccurred ~= nil then
    snapshot._textDragOccurred = element._textDragOccurred
  end
  return snapshot
end

-- Consumes the previously-saved snapshot keyed under `textEditor` plus the
-- drag-tracking fields. The behavior-dispatch loop passes the FULL top-level
-- state table; this hook reads only its own slices, mirroring the legacy
-- `if self._textEditor and state.textEditor then ... end` guard.
local function restoreState(element, state)
  if not state then
    return
  end
  local textEditor = element._textEditor
  if textEditor and state.textEditor then
    textEditor:setState(state.textEditor, element)
    -- Sync TextEditor's focus/cursor/selection state to Element for theme
    -- management (mirrors the legacy restoreState field sync).
    element._focused = textEditor._focused
    element._cursorPosition = textEditor._cursorPosition
    element._selectionStart = textEditor._selectionStart
    element._selectionEnd = textEditor._selectionEnd
    element._textBuffer = textEditor._textBuffer
  end

  -- Restore drag-tracking state for text selection (top-level keys).
  if state._mouseDownPosition ~= nil then
    element._mouseDownPosition = state._mouseDownPosition
  end
  if state._textDragOccurred ~= nil then
    element._textDragOccurred = state._textDragOccurred
  end
end

-- ============================================================================
-- Text-editor delegate functions.
--
-- These are the module-level implementations of the 27 text-editor delegate
-- methods that previously lived on Element. Each mirrors the pre-refactor
-- Element method body VERBATIM (with `self` → `element`), including the
-- `element._textEditor` nil-guard: the guard is required because (a) non-
-- editable text elements attach this behavior (per shouldAttach) but own no
-- TextEditor, and (b) Element forwards these methods BEFORE onAttach has run
-- (e.g. an `onCreate` callback firing during _finalizeConstruction, which
-- runs before _attachBehaviors). The nil-guards live in THIS file (not in
-- Element.lua), so the Element.lua `if self._textEditor` count drops to 0.
--
-- Element retains 1-line forwarders: `Element.setText = function(self, text)
-- return Element._TextEditable.setText(self, text) end` (etc.), so external
-- callers (EventHandler, KeyboardNavigation, game UI) keep working unchanged.
--
-- The TextEditor API is mixed: most methods take the element as first arg
-- (`te:method(element, ...)` — "passesSelf"); a few getters omit it
-- (`te:method()`). The delegation contract is pinned by
-- subsystem_delegation_test.lua, so this mapping must match TextEditor's
-- method signatures exactly.
-- ============================================================================

-- --- Cursor management (passesSelf = element forwarded) ------------------

local function setCursorPosition(element, position)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:setCursorPosition(element, position)
  end
end

local function getCursorPosition(element)
  local textEditor = element._textEditor
  if textEditor then
    return textEditor:getCursorPosition()
  end
  return 0
end

local function moveCursorBy(element, delta)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:moveCursorBy(element, delta)
  end
end

local function moveCursorToStart(element)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:moveCursorToStart(element)
  end
end

local function moveCursorToEnd(element)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:moveCursorToEnd(element)
  end
end

local function moveCursorToLineStart(element)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:moveCursorToLineStart(element)
  end
end

local function moveCursorToLineEnd(element)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:moveCursorToLineEnd(element)
  end
end

local function moveCursorToPreviousWord(element)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:moveCursorToPreviousWord(element)
  end
end

local function moveCursorToNextWord(element)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:moveCursorToNextWord(element)
  end
end

-- --- Selection management ------------------------------------------------

local function setSelection(element, startPos, endPos)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:setSelection(element, startPos, endPos)
  end
end

local function getSelection(element)
  local textEditor = element._textEditor
  if textEditor then
    return textEditor:getSelection()
  end
  return nil
end

local function hasSelection(element)
  local textEditor = element._textEditor
  if textEditor ~= nil then
    return textEditor:hasSelection()
  end
  return false
end

local function clearSelection(element)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:clearSelection(element)
  end
end

local function selectAll(element)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:selectAll(element)
  end
end

local function getSelectedText(element)
  local textEditor = element._textEditor
  if textEditor then
    return textEditor:getSelectedText()
  end
  return nil
end

local function deleteSelection(element)
  local textEditor = element._textEditor
  if textEditor then
    return textEditor:deleteSelection(element)
  end
  return false
end

-- --- Focus management ----------------------------------------------------

local function focus(element)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:focus(element)
  end
end

local function blur(element)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:blur(element)
  end
end

local function isFocused(element)
  local textEditor = element._textEditor
  if textEditor then
    return textEditor:isFocused()
  end
  return false
end

-- --- Text buffer management (with post-delegation sync) ------------------
-- These methods sync `element.text` from the TextEditor result + drive
-- auto-grow, exactly as the legacy Element methods did.

local function getText(element)
  local textEditor = element._textEditor
  if textEditor then
    return textEditor:getText()
  end
  return element.text or ""
end

local function setText(element, text)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:setText(element, text)
    element.text = textEditor:getText() -- Sync display text
    textEditor:updateAutoGrowHeight(element)
    return
  end
  element.text = text
end

local function insertText(element, text, position)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:insertText(element, text, position)
    element.text = textEditor:getText() -- Sync display text
    textEditor:updateAutoGrowHeight(element)
  end
end

local function deleteText(element, startPos, endPos)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:deleteText(element, startPos, endPos)
    element.text = textEditor:getText() -- Sync display text
    textEditor:updateAutoGrowHeight(element)
  end
end

local function replaceText(element, startPos, endPos, newText)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:replaceText(element, startPos, endPos, newText)
    element.text = textEditor:getText() -- Sync display text
    textEditor:updateAutoGrowHeight(element)
  end
end

-- --- Mouse text selection ------------------------------------------------

local function handleTextClick(element, mouseX, mouseY, clickCount)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:handleTextClick(element, mouseX, mouseY, clickCount)
    -- Store mouse down position on element for drag tracking
    if clickCount == 1 then
      element._mouseDownPosition = textEditor:mouseToTextPosition(element, mouseX, mouseY)
    end
  end
end

local function handleTextDrag(element, mouseX, mouseY)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:handleTextDrag(element, mouseX, mouseY)
    element._textDragOccurred = textEditor._textDragOccurred
  end
end

-- --- Keyboard input ------------------------------------------------------

local function textinput(element, text)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:handleTextInput(element, text)
    element.text = textEditor:getText() -- Sync display text
    textEditor:updateAutoGrowHeight(element)
  end
end

local function keypressed(element, key, scancode, isrepeat)
  local textEditor = element._textEditor
  if textEditor then
    textEditor:handleKeyPress(element, key, scancode, isrepeat)
    element.text = textEditor:getText() -- Sync display text
    textEditor:updateAutoGrowHeight(element)
  end
end

-- ============================================================================
-- Build the (stateless, shared, immutable) behavior instance + thin module
-- table exposing the delegate functions (mirrors the Animated pattern).
-- ============================================================================

local behavior = Behavior.new({
  onAttach = onAttach,
  onDetach = onDetach,
  onUpdate = onUpdate,
  onDraw = onDraw,
  saveState = saveState,
  restoreState = restoreState,
  shouldAttach = shouldAttach,
})

-- Thin module table: exposes the frozen behavior instance (for the registry)
-- plus the text-editor delegate functions (for Element's 1-line forwarders).
-- All hooks delegate to the frozen behavior instance so dispatch sites get
-- the validated, frozen implementation. shouldAttach is also exposed at module
-- level (mirrors Clickable.shouldAttach) for tests/callers without an element.
local TextEditable = {
  behavior = behavior,
  shouldAttach = shouldAttach,
  onAttach = onAttach,
  onUpdate = onUpdate,
  onDraw = onDraw,
  saveState = saveState,
  restoreState = restoreState,
  -- Text-editor delegate functions (Element forwarders route through these):
  setCursorPosition = setCursorPosition,
  getCursorPosition = getCursorPosition,
  moveCursorBy = moveCursorBy,
  moveCursorToStart = moveCursorToStart,
  moveCursorToEnd = moveCursorToEnd,
  moveCursorToLineStart = moveCursorToLineStart,
  moveCursorToLineEnd = moveCursorToLineEnd,
  moveCursorToPreviousWord = moveCursorToPreviousWord,
  moveCursorToNextWord = moveCursorToNextWord,
  setSelection = setSelection,
  getSelection = getSelection,
  hasSelection = hasSelection,
  clearSelection = clearSelection,
  selectAll = selectAll,
  getSelectedText = getSelectedText,
  deleteSelection = deleteSelection,
  focus = focus,
  blur = blur,
  isFocused = isFocused,
  getText = getText,
  setText = setText,
  insertText = insertText,
  deleteText = deleteText,
  replaceText = replaceText,
  _handleTextClick = handleTextClick,
  _handleTextDrag = handleTextDrag,
  textinput = textinput,
  keypressed = keypressed,
}

-- Metatable so the module table itself satisfies the duck-typed registry
-- contract (iterating `Element._behaviorRegistry` calls `behavior.shouldAttach`
-- and `behavior.onAttach` / `behavior.onUpdate` directly). Falls through to the
-- frozen behavior instance for every hook / isBehavior parity.
setmetatable(TextEditable, {
  __index = behavior,
  __tostring = function()
    return "TextEditable"
  end,
})

return TextEditable
