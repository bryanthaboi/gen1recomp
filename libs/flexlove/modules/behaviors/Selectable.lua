-- modules/behaviors/Selectable.lua
--
-- Concrete behavior: Select state-machine lifecycle for dropdown-style
-- select groups. Owns the per-element Select subsystem initialization, the
-- managed-frame layout sync each frame, and select save/restore across the
-- immediate-mode recreation cycle.
--
-- This behavior consolidates the legacy `if self._selectState` / `if
-- self.selectOption` branches that previously lived inside Element.lua:
--
--   * Select subsystem init (formerly Element:_initSubSystems lines ~810-825 —
--     `Select.initSelectParent` / `Select.initSelectOption`).
--   * Managed-frame adoption (formerly Element:_initPositioning lines ~1700-
--     1702 — `Select.adoptSelectFrame`).
--   * Per-frame frame-state sync (formerly Element:update line ~2747 —
--     `Select.ensureFrameState`).
--   * Save/restore of select open/value/label (formerly the `select` branch of
--     Element:saveState / Element:restoreState).
--
-- Element retains `self._selectState` and `self.selectOption` for backward-
-- compat field access; runtime state lives ON THE ELEMENT. The behavior itself
-- is stateless + immutable (a single shared instance attaches to every
-- selectable element).
--
-- The 20 Element select-API delegate methods (openSelect, closeSelect,
-- toggleSelect, isSelectOpen, getSelectValue, setSelectValue, ...) stay as
-- 1-line forwarders into the Select module — the behavior owns the
-- *lifecycle* (attach / update / save / restore / detach), not the API
-- surface (per task 05 spec notes).
--
-- State ownership (per the locked Behavior contract):
--   * Per-element runtime state lives ON THE ELEMENT (self._selectState,
--     self.selectOption, self._selectParentElement, ...).
--   * The behavior instance is stateless + immutable and shared across elements.
--   * Element-class-level dependencies are resolved via `getmetatable(element)`
--     (which IS the Element class set by Element._construct), so the hook
--     signature stays exactly `(element, ...)` with no DI parameters.

local _pkg = (...):match("^(.-)behaviors%.") or "modules."
local Behavior = require(_pkg .. "Behavior")

-- Resolve the Element class from an element instance.
-- `setmetatable({}, Element)` in `_construct` makes the instance metatable BE
-- the Element class, so this yields Element._Select, Element._Context,
-- Element._StateManager, etc. without threading deps through the hook signature.
local function ElementClass(element)
  return getmetatable(element)
end

-- ============================================================================
-- shouldAttach (class-level predicate, no element required)
-- ============================================================================

-- Mirrors the cases that previously caused Element to initialize a Select
-- subsystem. An element owns select state exactly when it declares a
-- `selectParent` config (the dropdown trigger) or a `selectOption` config (an
-- option inside a dropdown). Checking the props (rather than the runtime
-- `_selectState`) lets shouldAttach run before onAttach initializes the
-- subsystem, matching the auto-attach contract established by Clickable /
-- TextEditable.
local function shouldAttach(props)
  props = props or {}
  return type(props.selectParent) == "table" or type(props.selectOption) == "table"
end

-- ============================================================================
-- onAttach — initialize the Select subsystem (formerly Element:_initSubSystems
-- lines ~810-825) and adopt the managed frame (formerly Element:_initPositioning
-- lines ~1700-1702).
-- ============================================================================

local function onAttach(element)
  local Element = ElementClass(element)

  -- Initialize the appropriate select role. Mirrors the legacy _initSubSystems
  -- block exactly: selectParent → initSelectParent (sets _selectState +
  -- immediate-mode restore from StateManager); selectOption → initSelectOption
  -- (sets the option value/label/disabled).
  if type(element.selectParent) == "table" then
    Element._Select.initSelectParent(element, element.selectParent)
  end

  if type(element.selectOption) == "table" then
    Element._Select.initSelectOption(element, element.selectOption)
  end

  -- Adopt the managed dropdown frame. This was formerly the tail of
  -- _initPositioning (after the select parent's own addChild). It creates the
  -- select anchor, reparents the frame under it, and syncs visibility. Moving
  -- it here is safe because onAttach runs after _initPositioning: the parent's
  -- own positioning is finalized, so the anchor's geometry can be computed.
  if element._selectState and type(element.selectParent) == "table" and element.selectParent.selectFrame ~= nil then
    Element._Select.adoptSelectFrame(element, element.selectParent.selectFrame)
  end

  -- Backfill option registration for children added BEFORE this behavior
  -- attached. The auto-attach pass runs at the very end of Element.new
  -- (after _finalizeConstruction, which processes declarative `children`).
  -- Declarative select-option children are addChild'd to this element during
  -- _finalizeConstruction — at that point _selectState did not yet exist (this
  -- onAttach had not run), so their registerWithSelectParent call walked the
  -- parent chain, found no _selectState, and returned early. Re-scan now that
  -- _selectState is initialized so these options are registered + reparented
  -- into the managed frame exactly like runtime-added options.
  -- (registerWithSelectParent is idempotent — it skips options already
  -- registered — so this is a no-op for children added after _selectState was
  -- set, e.g. the common `FlexLove.new({ parent = sp, selectOption = {...} })`
  -- pattern.)
  if element._selectState then
    for _, child in ipairs(element.children) do
      if child.selectOption then
        Element._Select.registerWithSelectParent(child)
        Element._Select.attachOptionToManagedFrame(child)
      end
    end
  end
end

local function onDetach(element)
  -- Clear select-managed fields so the element can be GC'd cleanly in immediate
  -- mode (formerly part of Element:_cleanup). This mirrors the select-clearing
  -- block that lived in Element:_cleanup; Element:destroy separately routes
  -- through Select.cleanupDestroy for full teardown (idempotent with this).
  if element.selectParent then
    element.selectParent.onChange = nil
  end
  element._selectState = nil
  element._managedSelectOwner = nil
  element._managedSelectFrame = nil
  element._managedSelectAnchor = nil
  element._managedSelectBaseOpacity = nil
  element._managedSelectBaseVisibility = nil
  element._managedSelectBaseDisabled = nil
end

-- ============================================================================
-- onUpdate — per-frame managed-frame layout sync (formerly Element:update
-- line ~2747 — `Select.ensureFrameState`).
-- ============================================================================

local function onUpdate(element, dt)
  local Element = ElementClass(element)
  Element._Select.ensureFrameState(element)
end

-- ============================================================================
-- onDraw — no-op.
-- ============================================================================

-- Select rendering is driven by the managed frame / anchor elements themselves
-- (visibility synced by Select.syncManagedFrameVisibility), not by the select
-- parent's draw path. The parent's own pixels are the theme/renderer's job.
local function onDraw() end

-- ============================================================================
-- saveState / restoreState — select open/value/label (formerly the `select`
-- branch of Element:saveState / Element:restoreState).
-- ============================================================================

-- Returns a snapshot under the `select` key to match the legacy immediate-mode
-- restoreState contract (Element:restoreState looked up state.select). The
-- behavior-dispatch loop merges behavior snapshots into the top-level state
-- table, so returning { select = ... } slots in identically to the old inline
-- `state.select = selectState` assignment.
local function saveState(element)
  local Element = ElementClass(element)
  local selectState = Element._Select.saveState(element)
  if selectState then
    return { select = selectState }
  end
  return nil
end

-- Consumes the previously-saved snapshot keyed under `select`. The behavior-
-- dispatch loop passes the FULL top-level state table; this hook reads only
-- its own `state.select` slice, mirroring the legacy `if state.select then`
-- guard in Element:restoreState.
local function restoreState(element, state)
  if not state then
    return
  end
  local Element = ElementClass(element)
  if state.select then
    Element._Select.restoreState(element, state.select)
  end
end

-- ============================================================================
-- Build the (stateless, shared, immutable) behavior instance.
-- ============================================================================

local Selectable = Behavior.new({
  onAttach = onAttach,
  onDetach = onDetach,
  onUpdate = onUpdate,
  onDraw = onDraw,
  saveState = saveState,
  restoreState = restoreState,
  shouldAttach = shouldAttach,
})

-- Expose the predicate at module level so callers/tests can reference it
-- directly without an element instance (mirrors Behavior.shouldAttach).
Selectable.shouldAttach = shouldAttach

return Selectable
