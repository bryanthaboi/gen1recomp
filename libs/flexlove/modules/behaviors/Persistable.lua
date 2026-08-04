-- modules/behaviors/Persistable.lua
--
-- Concrete behavior: generic public-property persistence across the immediate-
-- mode recreation cycle (behavior-mode-unification task 12).
--
-- Owns the ONE piece of Element save/restore state that is NOT subsystem state:
-- the snapshot of an element's own public scalar fields (`text`, `display`,
-- `opacity`, `x`, `width`, ...). Event-driven mutations to these fields (a
-- release callback changing `text`, a toggle hiding a panel via `display =
-- false`) must survive the per-frame Element recreation that defines immediate
-- mode. Persistable captures them in `saveState` and reapplies them in
-- `restoreState`, so the caller never branches on mode.
--
-- This behavior is the final home for the former `Element:saveState` `_props`
-- block and the former `Element:restoreState` `_props` block (~20 LOC moved out
-- of Element.lua). With it in place, `Element:saveState` / `Element:restoreState`
-- collapse to a pure behavior-dispatch loop and Element owns zero property-
-- extraction logic — every persisted slice is owned by exactly one behavior.
--
-- Attachment rule (shouldAttach): every element. Persistable attaches
-- unconditionally (mirrors the pre-refactor invariant that every element's
-- public scalar props were scanned). The actual snapshot is mode-gated inside
-- `saveState` (immediate-mode-only, matching the legacy contract); in retained
-- mode `saveState` returns nil and `restoreState` is a no-op unless a snapshot
-- is explicitly passed.
--
-- Registry ordering: Persistable is intentionally placed LAST in the behavior
-- registry. `restoreState` applies `_props` AFTER every other behavior has
-- hydrated its subsystem state, so a persisted public-prop mutation (e.g.
-- `text = "mutated"`) overrides the freshly-restored TextEditor/Select state —
-- preserving the legacy restore ordering (behaviors first, `_props` tail).
--
-- State ownership (per the locked Behavior contract):
--   * The persisted props live ON the element (they ARE the element's public
--     fields). The behavior instance is stateless + immutable and shared.
--   * The snapshot is returned under the `_props` key (prefixed with `_` so
--     the public-prop scan itself skips it — avoiding self-recursion).

local _pkg = (...):match("^(.-)behaviors%.") or "modules."
local Behavior = require(_pkg .. "Behavior")

-- Resolve the Element class from an element instance (mirrors Clickable /
-- Themed). Element instances are created via `setmetatable({}, Element)`, so
-- their metatable IS the Element class — giving access to Element._StateManager
-- without threading deps through the hook signature.
local function ElementClass(element)
  return getmetatable(element)
end

-- ============================================================================
-- shouldAttach (class-level predicate, no element required)
-- ============================================================================

-- Every element's public scalar props are persistable, so this behavior
-- attaches unconditionally. The mode gate lives inside saveState (it needs the
-- runtime mode, which is only available with an element via StateManager).
local function shouldAttach()
  return true
end

-- ============================================================================
-- saveState — snapshot public scalar fields (immediate-mode-only).
-- ============================================================================

-- Mirrors the former `Element:saveState` `_props` block exactly:
--   * Only string keys NOT prefixed with `_` (so internal fields like
--     `_renderer`, `_themeState`, `_initProps` are excluded).
--   * Only scalar values (numbers, strings, booleans); tables and functions
--     are excluded (children, padding, onEvent, ...).
-- Returns `{ _props = {...} }` when there is at least one persistable prop and
-- the element is in immediate mode; nil otherwise (retained mode no-op —
-- state lives on the element directly there, so nothing to snapshot).
local function saveState(element)
  local Element = ElementClass(element)
  if not Element._StateManager.isImmediateMode() then
    return nil
  end
  local props = {}
  for k, v in pairs(element) do
    if type(k) == "string" and k:sub(1, 1) ~= "_" and type(v) ~= "table" and type(v) ~= "function" then
      props[k] = v
    end
  end
  if next(props) then
    return { _props = props }
  end
  return nil
end

-- ============================================================================
-- restoreState — reapply the persisted public-prop snapshot onto a fresh
-- element (mode-agnostic; only fires when a `_props` slice is present).
-- ============================================================================

-- Applies persisted mutations on top of whatever the constructor + other
-- behaviors already set, so event-driven changes from the previous frame
-- override the declarative props of the recreated element. Runs last in the
-- behavior dispatch (Persistable is the registry tail) to preserve the legacy
-- restore ordering (subsystem restore first, `_props` override last).
local function restoreState(element, state)
  if not state or not state._props then
    return
  end
  for k, v in pairs(state._props) do
    element[k] = v
  end
end

-- ============================================================================
-- onAttach / onUpdate / onDraw / onDetach — no-ops.
-- ============================================================================

-- Persistable owns no subsystem and allocates no per-element state (the
-- "state" it persists IS the element's own fields). The lifecycle is purely
-- save/restore.

-- ============================================================================
-- Build the (stateless, shared, immutable) behavior instance.
-- ============================================================================

local Persistable = Behavior.new({
  saveState = saveState,
  restoreState = restoreState,
  shouldAttach = shouldAttach,
})

-- Expose the predicate at module level so callers/tests can reference it
-- directly without an element instance (mirrors Behavior.shouldAttach /
-- Clickable.shouldAttach).
Persistable.shouldAttach = shouldAttach

return Persistable
