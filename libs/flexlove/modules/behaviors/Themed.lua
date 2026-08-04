-- modules/behaviors/Themed.lua
--
-- Concrete behavior: Renderer ownership + theme-state rendering.
--
-- Themed owns the per-element Renderer instance and the single
-- `Renderer:draw` call that paints the core visual layers (background, image,
-- theme 9-patch, borders, text, customDraw). It is the behavior-mode-unification
-- replacement for the former `_initImageAndRenderer` Renderer creation block and
-- the former first `self._renderer:draw(self, backdropCanvas)` call in
-- Element:draw (behavior-mode-unification task 07).
--
-- Attachment rule (shouldAttach): every renderable Element. The pre-refactor
-- code unconditionally created a Renderer for every Element and unconditionally
-- called `Renderer:draw` in Element:draw; Themed mirrors that invariant so the
-- Renderer is always available to subsystems that depend on it (TextEditor font
-- / wrap delegation, ScrollManager scrollbar drawing) AND so visual rendering of
-- background / border / theme / image layers is preserved for every element.
-- Restricting attachment to `themeComponent`-only elements would break editable
-- text fields and scrollable containers (which need a Renderer for subsystem
-- delegation even when they have no theme component). The 9-patch theme-state
-- rendering within `Renderer:draw` is a no-op for elements without a
-- `themeComponent`, so always-attaching carries no rendering cost.
--
-- Themed and Imageable are paired (both configure the same `element._renderer`):
-- Themed.onAttach creates the Renderer with the theme/blur config; Imageable
-- (attached for imagePath/image elements) enriches the SAME renderer instance with
-- image config + deferred image loading. They share `element._renderer`.
--
-- onUpdate is a no-op: theme-state transitions are DRIVEN by the Clickable
-- behavior (whose onUpdate recomputes hover/press/focus and calls
-- `renderer:setThemeState`). Themed only READS that state for rendering, so it has
-- no per-frame update work.
--
-- saveState owns the blur-region snapshot (`state.blur`): the per-frame blur
-- geometry + radius/quality used by the Blur cache for invalidation (formerly
-- the inline `if self.backdropBlur or self.contentBlur` block of
-- Element:saveState — behavior-mode-unification task 12). restoreState is a
-- no-op: blur cache data is used for invalidation, not restoration (the Blur
-- cache is keyed by element id and cleared via `Blur.clearElementCache` from
-- FlexLove.endFrame, not replayed through restoreState).
--
-- State ownership (per the locked Behavior contract):
--   * Per-element runtime state lives ON THE ELEMENT (`element._renderer`,
--     `element._themeState`, `element.backdropBlur`, `element.contentBlur`).
--     The behavior instance is stateless and shared.
--   * `element._renderer` is recreated on attach; onDetach is a no-op — the
--     reference is released when the element is GC'd (Element:_cleanup keeps
--     element structure for inspection).

local _pkg = (...):match("^(.-)behaviors%.") or "modules."
local Behavior = require(_pkg .. "Behavior")

-- Resolve the Element class from an element instance (mirrors Clickable).
-- Element instances are created via `setmetatable({}, Element)`, so their
-- metatable IS the Element class — giving access to Element._Renderer,
-- Element._rendererDeps, etc. without threading deps through the hook signature.
local function ElementClass(element)
  return getmetatable(element)
end

-- ----------------------------------------------------------------------------
-- shouldAttach (class-level predicate, no element required)
-- ----------------------------------------------------------------------------

-- Returns true for every renderable Element. See file header for the rationale:
-- the pre-refactor invariant was "every Element has a Renderer; Element:draw
-- always calls Renderer:draw", and Thamed is the behavior-system embodiment of
-- that invariant. Returns true for `themeComponent`-bearing props (the spec's
-- headline case) and for every other element so subsystems/rendering stay intact.
local function shouldAttach(props)
  return true
end

-- ----------------------------------------------------------------------------
-- onAttach — create the Renderer with theme/blur config (formerly the
-- Renderer.new block of Element:_initImageAndRenderer).
-- ----------------------------------------------------------------------------

local function onAttach(element)
  local Element = ElementClass(element)

  -- Create-or-reuse the Renderer. Thamed is the first render behavior in the
  -- registry, so it normally creates the instance; Imageable (if attached) will
  -- reuse this same instance for image config. Guarded so Imageable-onAttach-
  -- first (defensive) does not clobber an existing renderer.
  if element._renderer then
    return
  end

  -- NOTE: backgroundColor/borderColor/opacity/cornerRadius/themeComponent are
  -- intentionally NOT passed here. Renderer:draw() reads them from the element
  -- as the single source of truth (see Renderer.lua draw()). Only renderer-owned
  -- state (theme, blur) is cached on the renderer; image config is added by the
  -- Imageable behavior. border is element-sourced too.
  element._renderer = Element._Renderer.new({
    theme = element.theme,
    scaleCorners = element.scaleCorners,
    scalingAlgorithm = element.scalingAlgorithm,
    contentBlur = element.contentBlur,
    backdropBlur = element.backdropBlur,
  }, Element._rendererDeps)
end

-- ----------------------------------------------------------------------------
-- onDraw — the single Renderer:draw call (formerly the first call in
-- Element:draw). Paints all core visual layers for this element.
-- ----------------------------------------------------------------------------

local function onDraw(element, ctx)
  local renderer = element._renderer
  if not renderer then
    return
  end
  renderer:draw(element, ctx and ctx.backdropCanvas)
end

-- ----------------------------------------------------------------------------
-- onDetach — no-op. Element:_cleanup preserves element structure for
-- inspection (the original invariant), so the Renderer reference is released
-- when the element is GC'd rather than torn down here. Present as an explicit
-- hook so the behavior conforms to the full lifecycle contract.
-- ----------------------------------------------------------------------------

local function onDetach() end

-- ----------------------------------------------------------------------------
-- saveState — blur-region snapshot (formerly the `blur` branch of
-- Element:saveState). Returns `{ blur = {...} }` when the element configures a
-- backdrop or content blur, so the Blur cache can invalidate by element id;
-- nil otherwise. Mode-agnostic to match the legacy contract (the snapshot is
-- only read back by the cache-invalidation path, which itself is
-- immediate-mode-only via FlexLove.endFrame).
-- ----------------------------------------------------------------------------

local function saveState(element)
  if not (element.backdropBlur or element.contentBlur) then
    return nil
  end
  local blur = {
    _blurX = element.x,
    _blurY = element.y,
    _blurWidth = element._borderBoxWidth or (element.width + element.padding.left + element.padding.right),
    _blurHeight = element._borderBoxHeight or (element.height + element.padding.top + element.padding.bottom),
  }
  if element.backdropBlur then
    blur._backdropBlurRadius = element.backdropBlur.radius
    blur._backdropBlurQuality = element.backdropBlur.quality or 5
  end
  if element.contentBlur then
    blur._contentBlurRadius = element.contentBlur.radius
    blur._contentBlurQuality = element.contentBlur.quality or 5
  end
  return { blur = blur }
end

-- restoreState — no-op: blur cache data is used for invalidation, not
-- restoration (see file header). Present so the behavior conforms to the
-- lifecycle contract without replaying geometry that the cache recomputes.

-- ----------------------------------------------------------------------------
-- Build the (stateless, shared, immutable) behavior instance.
-- ----------------------------------------------------------------------------

local Themed = Behavior.new({
  onAttach = onAttach,
  onDetach = onDetach,
  onUpdate = function() end,
  onDraw = onDraw,
  saveState = saveState,
  restoreState = function() end,
})

-- Expose the predicate at module level so callers/tests can reference it
-- directly without an element instance (mirrors Behavior.shouldAttach /
-- Clickable.shouldAttach).
Themed.shouldAttach = shouldAttach

return Themed
