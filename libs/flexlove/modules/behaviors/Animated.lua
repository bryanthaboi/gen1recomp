-- modules/behaviors/Animated.lua
--
-- Concrete behavior: animation update, interpolation application, chaining
-- resolution, and transition wiring.
--
-- Task 06 of the behavior-mode-unification refactor. Moves the entire
-- animation-update block out of Element:update (lines ~2761-2800) into
-- `Animated.onUpdate(element, dt)`, and the `_ColorModule`/`_TransformModule`
-- init-time wiring into `Animated.onAttach(element)`.
--
-- This behavior is UNIQUE among the behavior set because it can attach
-- AFTER element creation. Animation is opt-in: a plain Element created without
-- `transitions` and without an `animation` field never attaches Animated.
-- The moment something creates an animation on the element — either directly
-- (`element.animation = Animation.new(...)`, `element:fadeIn(...)`) or via a
-- transition firing in `setProperty` — `Animated.ensureAttached(element)`
-- attaches this behavior on demand so subsequent `Element:update` frames
-- dispatch to `Animated.onUpdate`.
--
-- Attachment rule (shouldAttach): true when `props.transitions` is set OR an
-- `element.animation` already exists at runtime. The runtime arm covers the
-- late-attach case (animateTo / fadeIn / direct animation assignment).
--
-- State ownership (per the locked Behavior contract):
--   * Per-element runtime state lives ON THE ELEMENT (`element.animation`).
--   * The behavior instance itself is stateless and shared across elements.
--   * Element-class-level dependencies (Element._Animation, Element._Color,
--     Element._Transform) are resolved from the owning element's metatable,
--     exactly like Clickable does — keeping the behavior stateless without
--     expanding the 6-hook signature.
--
-- saveState/restoreState are no-ops: animations are ephemeral (an in-flight
-- animation is not part of immediate-mode persisted state — the next frame
-- re-evaluates transitions / re-applies animations fresh). Persisted scalar
-- props (`opacity`, `x`, ...) survive via Element.saveState's `_props` block,
-- not via the animation.

local _pkg = (...):match("^(.-)behaviors%.") or "modules."
local Behavior = require(_pkg .. "Behavior")

-- Resolve the Element class from an element instance.
-- Element instances are created via `setmetatable({}, Element)` in _construct,
-- so their metatable IS the Element class — giving us Element._Animation,
-- Element._Color, Element._Transform, etc. without threading deps through the
-- behavior hook signature.
local function ElementClass(element)
  return getmetatable(element)
end

-- ----------------------------------------------------------------------------
-- ensureAnimationModuleWiring — set Element._Animation._ColorModule /
-- _TransformModule. Idempotent; called from both onAttach and onUpdate so it
-- works even when an animation was assigned by a caller that bypassed
-- onAttach (direct `element.animation = Animation.new(...)`).
-- ----------------------------------------------------------------------------

local function ensureAnimationModuleWiring(element)
  local Element = ElementClass(element)
  local Animation = Element._Animation
  if not Animation then
    return
  end
  -- Ensure animation has Color module reference for color interpolation
  if not Animation._ColorModule and Element._Color then
    Animation._ColorModule = Element._Color
  end
  -- Ensure animation has Transform module reference for transform interpolation
  if not Animation._TransformModule and Element._Transform then
    Animation._TransformModule = Element._Transform
  end
end

-- ----------------------------------------------------------------------------
-- shouldAttach (class-level predicate, no element required)
-- ----------------------------------------------------------------------------

-- True when the element declares transitions up front OR already has an
-- animation attached. The `animation` arm is consulted by ensureAttached at
-- runtime (after creation); the `transitions` arm lets Animated auto-attach
-- during Element.new for elements that pre-declare transitions.
local function shouldAttach(props)
  if not props then
    return false
  end
  if props.transitions ~= nil then
    return true
  end
  -- Late-attach case: an animation was assigned after creation. When ensure
  -- Attached passes the element instance as `props`, this arm catches it.
  if type(props) == "table" and props.animation ~= nil then
    return true
  end
  return false
end

-- ----------------------------------------------------------------------------
-- ensureAttached — dynamic late-attach entry point
-- ----------------------------------------------------------------------------

-- Idempotently attach the Animated behavior to an element that just gained an
-- animation (via animateTo / fadeIn / direct assignment / a firing transition
-- in setProperty). Called from Element.setProperty when a transition fires and
-- from the transition helper methods on Element. Safe to call when already
-- attached (no-op / returns false).
--
-- `animatedBehavior` is the shared behavior instance resolved lazily by
-- Element (see Element._resolveAnimatedBehavior). The behavior is looked up
-- from the registry once and cached on the class.
--
-- Returns true if the behavior was attached this call, false otherwise.
local function ensureAttached(element, animatedBehavior)
  if not element or not animatedBehavior then
    return false
  end
  -- Already attached? Avoid duplicate entries within one element lifetime
  -- (a behavior may legitimately be re-added across immediate-mode frames
  -- since Element is recreated each frame, but within one lifetime at most
  -- once).
  local behaviors = element.behaviors
  if behaviors then
    for i = 1, #behaviors do
      if behaviors[i] == animatedBehavior then
        return false
      end
    end
  end
  table.insert(element.behaviors, animatedBehavior)
  animatedBehavior.onAttach(element)
  return true
end

-- ----------------------------------------------------------------------------
-- onAttach — initialize Animation module references (formerly the
-- Element._Animation._ColorModule / _TransformModule wiring in Element:update
-- lines ~2772-2778).
-- ----------------------------------------------------------------------------

local function onAttach(element)
  ensureAnimationModuleWiring(element)
end

-- ----------------------------------------------------------------------------
-- onUpdate — the animation update + interpolation + chain-resolution block
-- (formerly Element:update lines ~2761-2800).
-- ----------------------------------------------------------------------------

local function onUpdate(element, dt)
  local animation = element.animation
  if not animation then
    return
  end

  -- (Re)ensure module wiring is present in case the Animation instance was
  -- created by a caller that bypassed onAttach (e.g. direct
  -- `element.animation = Animation.new(...)`). Cheap idempotent writes.
  ensureAnimationModuleWiring(element)

  local finished = animation:update(dt, element)
  if finished then
    -- Animation:update() already called onComplete callback.
    -- Check for chained animation.
    if animation._next then
      element.animation = animation._next
    elseif animation._nextFactory and type(animation._nextFactory) == "function" then
      local success, nextAnim = pcall(animation._nextFactory, element)
      if success and nextAnim then
        element.animation = nextAnim
      else
        element.animation = nil
      end
    else
      element.animation = nil
    end
  else
    -- Apply animation interpolation during update.
    animation:applyInterpolation(element)
  end
end

-- ----------------------------------------------------------------------------
-- saveState / restoreState — no-ops (animations are ephemeral).
-- ----------------------------------------------------------------------------

-- Animations are not persisted across immediate-mode frames — they are
-- re-derived each frame from transitions / direct calls. The element's scalar
-- props (opacity, x, ...) are persisted by Element.saveState's _props block,
-- so a completed animation's final visual state still survives recreation.
-- While an animation is mid-flight in immediate mode, the element is recreated
-- and the animation is NOT carried over (intentional — animating in immediate
-- mode requires setting up the animation each frame).
local function saveState()
  return nil
end

local function restoreState()
  return nil
end

-- ----------------------------------------------------------------------------
-- Build the (stateless, shared) behavior instance.
-- ----------------------------------------------------------------------------

-- onDetach/onDraw omitted: they default to no-ops (the behavior allocates no
-- behavior-local state and animations have no draw pass). Animation state lives
-- on the element (`element.animation`); nothing to tear down on detach.
--
-- We build the immutable behavior via Behavior.new (for validation + freeze +
-- isBehavior parity with Clickable), then expose the late-attach helper on a
-- thin module table since the frozen instance cannot accept new keys. The
-- module table passes the behavior to the registry while making
-- `Animated.ensureAttached` callable from Element.setProperty / the transition
-- helpers — exactly as the task spec requires.
local behavior = Behavior.new({
  onAttach = onAttach,
  onUpdate = onUpdate,
  saveState = saveState,
  restoreState = restoreState,
  shouldAttach = shouldAttach,
})

-- Thin module table: exposes the behavior instance (for the registry) plus the
-- late-attach helper (for Element.setProperty). All hooks delegate to the
-- frozen behavior instance so dispatch sites get the validated, frozen
-- implementation. shouldAttach is also exposed at module level (mirrors
-- Clickable.shouldAttach) for tests/callers without an element.
local Animated = {
  behavior = behavior,
  ensureAttached = ensureAttached,
  shouldAttach = shouldAttach,
  onAttach = onAttach,
  onUpdate = onUpdate,
}

-- Metatable so the module table itself satisfies the duck-typed registry
-- contract (iterating `Element._behaviorRegistry` calls `behavior.shouldAttach`
-- and `behavior.onAttach` / `behavior.onUpdate` directly). Falls through to the
-- frozen behavior instance for every hook.
setmetatable(Animated, {
  __index = behavior,
  __tostring = function()
    return "Animated"
  end,
})

return Animated
