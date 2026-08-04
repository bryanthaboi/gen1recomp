-- modules/Behavior.lua
--
-- Base module for the pluggable behavior system that drives the Behavior &
-- Mode Unification refactor.
--
-- A *behavior* is a small, stateless table produced by `Behavior.new(spec)`
-- that implements a fixed lifecycle hook set. Concrete behaviors (Clickable,
-- Scrollable, TextEditable, Selectable, ...) each live in their own module and
-- are attached to an Element. The Element's `update`/`draw`/save-restore paths
-- iterate `element.behaviors` and dispatch to the appropriate hooks, replacing
-- the swarm of `if self.scrollable` / immediate-mode-branch checks previously
-- hard-coded in Element.lua.
--
-- Element.new iterates a registry of behavior prototypes and auto-attaches
-- whichever return true from `shouldAttach(props)`. Element therefore never
-- needs to know what an individual behavior does — only that it conforms to
-- this interface.
--
-- Design constraints (locked — tasks 02-13 depend on this API):
--   * Pure Lua — NO `love` import, NO dependency on utils/Color/Units/ErrorHandler.
--     Stays fully stub-testable standalone (see testing/__tests__/behavior_test.lua).
--   * Minimal interface — exactly 6 lifecycle hooks + a `shouldAttach` predicate.
--     Do NOT add hooks "just in case"; new capabilities become new behaviors,
--     not new hooks. Extending HOOK_NAMES is an architectural decision that must
--     be mirrored by every concrete behavior.
--   * Immutable instances — behavior tables are produced once and treated as
--     read-only. Per-element runtime state lives on the element (or a subsystem
--     the behavior attaches), NEVER on the behavior instance itself, so a single
--     behavior instance can be shared across many elements.
--
-- Lifecycle hook contract (each receives the owning element as first argument):
--   onAttach(element)               — called once when the behavior is attached
--                                     (element fully constructed). Allocate
--                                     subsystems / register listeners here.
--   onDetach(element)               — called once when the behavior is detached
--                                     (element destroyed / mode switch). Tear
--                                     down anything onAttach created.
--   onUpdate(element, dt)           — called every frame from Element:update.
--   onDraw(element, ctx)            — called every frame from Element:draw; `ctx`
--                                     is the draw context (viewport transform,
--                                     scissor state, theme renderer, ...).
--   saveState(element) -> state     — called during Element save-state; returns
--                                     a serializable snapshot (or nil) so the
--                                     behavior's runtime state survives the
--                                     immediate-mode recreation cycle.
--   restoreState(element, state)   — called after reconstruction with the
--                                     snapshot previously returned by saveState.
--
-- shouldAttach(props) -> boolean    — class-level predicate (not a hook): given
--                                     an element's props table, return true if
--                                     this behavior should be auto-attached.
--                                     Defaults to false (opt-in).

--- A behavior instance: a frozen table of lifecycle hooks + a shouldAttach
--- predicate. All hooks are always present (custom override or no-op default).
---@class Behavior
---@field onAttach fun(element:table)
---@field onDetach fun(element:table)
---@field onUpdate fun(element:table, dt:number)
---@field onDraw fun(element:table, ctx:table)
---@field saveState fun(element:table):any
---@field restoreState fun(element:table, state:any)
---@field shouldAttach fun(props:table):boolean

local Behavior = {}

-- The fixed, ordered lifecycle hook set. Order is preserved so downstream tasks
-- (Element behavior iteration) can rely on a deterministic dispatch sequence.
-- HOOK_NAMES is intentionally NOT extended casually — see file header.
Behavior.HOOK_NAMES = {
  "onAttach",
  "onDetach",
  "onUpdate",
  "onDraw",
  "saveState",
  "restoreState",
}

-- Allowlist of spec keys accepted by Behavior.new. Anything else is rejected so
-- a typo (e.g. `onUpdat`) surfaces immediately instead of silently no-op'ing.
-- Hook keys (HOOK_NAMES + shouldAttach) MUST be functions; metadata keys
-- (drawLayer) may hold any value.
local ALLOWED_KEYS = {
  onAttach = true,
  onDetach = true,
  onUpdate = true,
  onDraw = true,
  saveState = true,
  restoreState = true,
  shouldAttach = true,
  drawLayer = true,
}

-- Spec keys whose values are NOT required to be functions (passive metadata
-- consumed by dispatch sites, e.g. Element:draw's pre/post-children split).
local NON_FUNCTION_KEYS = {
  drawLayer = true,
}

-- Default no-op hook. Behaviors override only the hooks they need; every other
-- hook resolves to this so dispatch sites never have to nil-check.
local function noop() end

-- Default shouldAttach predicate: never auto-attach unless the behavior opts in
-- by providing its own predicate. This is the safe default — a behavior with no
-- opinion about which elements it applies to stays inert in the auto-attach
-- pass (it can still be attached explicitly by name in a later task).
local function defaultShouldAttach()
  return false
end

-- Module-level default predicate exposed for callers/tests that want to
-- reference the base default directly without constructing an instance.
Behavior.shouldAttach = defaultShouldAttach

--- Factory: create a frozen behavior instance from a spec table.
---
--- `spec` is a table whose keys may be any subset of the 6 lifecycle hook names
--- plus `shouldAttach`; each value (when present) must be a function. The
--- returned table contains every lifecycle hook (custom override OR no-op) and
--- a `shouldAttach` predicate (custom OR always-false default), so dispatch
--- sites can call any hook unconditionally without nil-checking.
---
--- Unknown spec keys and non-function values raise an error immediately so
--- mistakes fail fast at construction rather than as silent no-ops later.
---
---@param spec table|nil spec table overriding select hooks / shouldAttach
---@return Behavior
function Behavior.new(spec)
  spec = spec or {}

  -- Validate spec keys up front so typos surface here, not as silent no-ops.
  for key, value in pairs(spec) do
    if not ALLOWED_KEYS[key] then
      error(string.format("Behavior.new: unknown spec key '%s'", tostring(key)), 2)
    end
    if not NON_FUNCTION_KEYS[key] and type(value) ~= "function" then
      error(string.format("Behavior.new: spec key '%s' must be a function, got %s", tostring(key), type(value)), 2)
    end
  end

  local instance = {}

  -- Populate every lifecycle hook: custom override when provided, no-op default
  -- otherwise. Guarantees `instance.hook` is always callable.
  for _, hook in ipairs(Behavior.HOOK_NAMES) do
    instance[hook] = spec[hook] or noop
  end

  -- shouldAttach defaults to always-false; behaviors opt in by supplying one.
  instance.shouldAttach = spec.shouldAttach or defaultShouldAttach

  -- drawLayer: optional metadata field (default nil = "background"/pre-children).
  -- Dispatch sites (Element:draw) use it to split rendering into pre-children
  -- (background layers) and post-children (overlay layers, e.g. scrollbars).
  instance.drawLayer = spec.drawLayer

  -- Freeze: prevent adding new fields. Behavior instances are shared, stateless
  -- objects; runtime state belongs on the element, never on the behavior.
  -- (Reassigning an existing hook is still possible via direct index write —
  -- Lua metatables cannot intercept that — but the freeze communicates intent
  -- and catches accidental field additions.)
  local mt = {
    __newindex = function(_, key)
      error(string.format("Behavior: behavior instances are immutable (cannot set '%s')", tostring(key)), 2)
    end,
    --- Mark the metatable so consumers can detect a Behavior instance.
    ---@return string
    __tostring = function()
      return "Behavior"
    end,
    __metatable = "Behavior",
  }
  setmetatable(instance, mt)

  return instance
end

--- Type guard: returns true if `value` is a Behavior instance produced by
--- `Behavior.new`. Used by Element's attach path to validate registry entries
--- without depending on identity.
---@param value any
---@return boolean
function Behavior.isBehavior(value)
  return type(value) == "table" and getmetatable(value) == "Behavior"
end

return Behavior
