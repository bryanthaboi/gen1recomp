-- modules/behaviors/Imageable.lua
--
-- Concrete behavior: image loading + image rendering config.
--
-- Imageable owns the image side of the Renderer: it runs the deferred image-
-- load pipeline (cache check → defer → load → fire onImageLoad/onImageError
-- callbacks), populates the resolved `_loadedImage` cache on both the element
-- and the shared renderer, and persists that cache across immediate-mode
-- recreation. It is the behavior-mode-unification replacement for the image-
-- loading half of Element:_initImageAndRenderer and the deferred
-- Element:_loadImage method (behavior-mode-unification task 07).
--
-- Image value props (imagePath/image/objectFit/objectPosition/imageOpacity/
-- imageRepeat/imageTint) are bound on the ELEMENT by Element:_applyProps and read
-- from the element at draw time (Renderer._executeDrawCommand image branch) —
-- Imageable does NOT mirror them onto the renderer, so bare writes and
-- setProperty(...) are immediately consistent. Only the resolved _loadedImage
-- cache (the love.Image produced by the load pipeline) is renderer-mirrored,
-- because Renderer:draw reads `self._loadedImage`.
--
-- Runtime reload: setProperty("imagePath", ...) / setProperty("image", ...) and
-- the bare-write-equivalent setImage* flows route through element._reloadImage
-- (installed below) which re-runs the load pipeline. See
-- TestRetainedPropertyConsistency (image props) and TestImageableIntegration.
--
-- Attachment rule (shouldAttach): an element owns image concern exactly when it
-- declares an `imagePath` (load-from-path) or a direct `image` (already-loaded
-- love.Image). Mirrors the old `if self.imagePath / if self.image` init branches.
--
-- Pairing with Themed: Themed.onAttach creates the Renderer with theme/blur
-- config; Imageable.onAttach enriches the SAME renderer instance with image
-- config + kicks off loading. They share `element._renderer`. In the registry
-- Imageable runs after Themed, so the renderer already exists; the create-or-
-- reuse guard below covers the defensive case where Imageable attaches first.
--
-- onDraw: the image LAYER is rendered by the integrated `Renderer:draw` call
-- (owned by the Themed behavior) which executes the renderer's `image` draw
-- command using the config Imageable.onAttach wired. Imageable.onDraw is
-- therefore a no-op for the draw call itself — there is no separate
-- `_renderer:_drawImage` entry point; pixel emission lives in the integrated
-- Renderer:draw command buffer. Splitting it out would require Renderer surgery
-- with no behavioral gain (Renderer:draw already conditionally skips the image
-- layer when no image is loaded).
--
-- State ownership (per the locked Behavior contract):
--   * Per-element runtime state lives ON THE ELEMENT (`element._loadedImage`,
--     `element._renderer._loadedImage`). The behavior instance is stateless.
--   * saveState/restoreState persist `_loadedImage` across immediate-mode frames
--     so the image renders even if the ImageCache is cleared between frames and
--     so the renderer's loaded-image cache survives element recreation.

local _pkg = (...):match("^(.-)behaviors%.") or "modules."
local Behavior = require(_pkg .. "Behavior")

-- Lua 5.4 removed the global `unpack`; mirror Element's alias.
local unpack = table.unpack or unpack

-- Resolve the Element class from an element instance (mirrors Clickable/Themed).
local function ElementClass(element)
  return getmetatable(element)
end

-- ----------------------------------------------------------------------------
-- shouldAttach (class-level predicate, no element required)
-- ----------------------------------------------------------------------------

local function shouldAttach(props)
  props = props or {}
  return props.imagePath ~= nil or props.image ~= nil
end

-- ----------------------------------------------------------------------------
-- Image callback helper (moved from Element._fireImageCallback).
-- Fires a user-supplied image callback (onImageLoad/onImageError) under pcall,
-- honoring the onXDeferred flag when `honorDeferred` is true, and emits a single
-- EVT_002 warn on failure. The direct-`image` sync init path passes
-- honorDeferred=false to preserve immediate firing (image is already loaded).
-- ----------------------------------------------------------------------------

local function fireImageCallback(element, callbackField, honorDeferred, ...)
  local cb = element[callbackField]
  if type(cb) ~= "function" then
    return
  end
  local Element = ElementClass(element)
  local argc = select("#", ...)
  local args = { ... }
  local function invoke()
    local ok, err = pcall(cb, element, unpack(args, 1, argc))
    if not ok then
      Element._ErrorHandler:warn("Element", "EVT_002", {
        callback = callbackField,
        error = tostring(err),
      })
    end
  end
  if honorDeferred and element[callbackField .. "Deferred"] then
    Element._Context.deferCallback(invoke)
  else
    invoke()
  end
end

-- ----------------------------------------------------------------------------
-- Deferred image loader (replaces Element:_loadImage).
--
-- Invoked by Element's deferred-method dispatcher via the instance closure that
-- onAttach installs on `element._loadImage`. Loads the image from cache or disk
-- (I/O), updates BOTH the element and renderer `_loadedImage` caches so the
-- image draws after an async load, and fires the load/error callback (deferred,
-- honoring onImageLoadDeferred / onImageErrorDeferred).
-- ----------------------------------------------------------------------------

local function loadImage(element)
  if not element.imagePath or element.image then
    return
  end
  local Element = ElementClass(element)
  local loadedImage, err = Element._ImageCache.load(element.imagePath)
  if loadedImage then
    element._loadedImage = loadedImage
    if element._renderer then
      element._renderer._loadedImage = loadedImage
    end
    fireImageCallback(element, "onImageLoad", true, loadedImage)
  else
    fireImageCallback(element, "onImageError", true, err or "Unknown error")
  end
end

-- ----------------------------------------------------------------------------
-- reloadImage — recompute the loaded-image cache from the current image/imagePath.
--
-- This is the single entry point for (re)loading after either initial attach or
-- a runtime property change (see Element._specialSetHandlers.imagePath/image,
-- which call element:_reloadImage()). Precedence matches onAttach: a direct
-- `image` wins over `imagePath`; `nil` for both clears the cache.
--
--   * direct image  → set _loadedImage immediately, fire onImageLoad SYNC (the
--                     image is already loaded; honorDeferred=false preserves the
--                     original synchronous init contract).
--   * imagePath     → cache CHECK only (no I/O) so a cached image can draw this
--                     frame, then defer the loader (_loadImage) for the actual
--                     I/O + deferred callbacks. load bails if `image` is later set.
--   * neither      → clear _loadedImage on both element + renderer.
--
-- Image value props (objectFit/imageOpacity/imageRepeat/imageTint/objectPosition)
-- and imagePath/image themselves live on the ELEMENT as source of truth; the
-- renderer reads them at draw time, so reloadImage does NOT mirror them onto the
-- renderer — only the resolved _loadedImage cache is pushed.
-- ----------------------------------------------------------------------------

local function reloadImage(element)
  local Element = ElementClass(element)
  local renderer = element._renderer
  if element.image then
    element._loadedImage = element.image
    if renderer then
      renderer._loadedImage = element.image
    end
    fireImageCallback(element, "onImageLoad", false, element.image)
  elseif element.imagePath then
    -- Cache check (no I/O). Populate both caches immediately if cached so the
    -- image can draw this frame without waiting for the deferred load.
    local cached = Element._ImageCache.get(element.imagePath)
    element._loadedImage = cached
    if renderer then
      renderer._loadedImage = cached
    end
    -- Kick off the deferred I/O load + callbacks (idempotent: loadImage bails
    -- if image is set or imagePath is nil by the time it runs).
    if element._loadImage then
      element:_deferMethod("_loadImage")
    end
  else
    element._loadedImage = nil
    if renderer then
      renderer._loadedImage = nil
    end
  end
end

-- ----------------------------------------------------------------------------
-- onAttach — enrich the shared renderer with image config + kick off loading
-- (formerly the image block of Element:_initImageAndRenderer).
-- ----------------------------------------------------------------------------

local function onAttach(element)
  local Element = ElementClass(element)

  -- Ensure the renderer exists (Thamed normally creates it; this create-or-reuse
  -- guard is defensive for the Imageable-attaches-first ordering).
  if not element._renderer then
    element._renderer = Element._Renderer.new({
      theme = element.theme,
      scaleCorners = element.scaleCorners,
      scalingAlgorithm = element.scalingAlgorithm,
      contentBlur = element.contentBlur,
      backdropBlur = element.backdropBlur,
    }, Element._rendererDeps)
  end

  -- Install the (re)load hooks as instance methods so Element's
  -- deferred-method dispatcher / setProperty special handlers can trigger a
  -- reload without Element needing a behavior reference. This keeps Element
  -- decoupled from the Imageable behavior (mirrors the stateless-behavior +
  -- element-owned-state contract). Image value props and imagePath/image live
  -- on the element as source of truth (read at draw time); only the resolved
  -- _loadedImage cache is mirrored onto the renderer by reloadImage.
  element._loadImage = function(el)
    loadImage(el)
  end
  element._reloadImage = function(el)
    reloadImage(el)
  end

  -- Initial load: compute _loadedImage + defer the I/O load.
  reloadImage(element)
end

-- ----------------------------------------------------------------------------
-- onDraw — no-op (see file header: the image layer is rendered by the integrated
-- Renderer:draw call owned by the Themed behavior, using the config wired here).
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- saveState / restoreState — `_loadedImage` cache (for immediate-mode).
-- ----------------------------------------------------------------------------

local function saveState(element)
  if element._loadedImage ~= nil then
    return { _loadedImage = element._loadedImage }
  end
  return nil
end

local function restoreState(element, state)
  if not state or state._loadedImage == nil then
    return nil
  end
  local loadedImage = state._loadedImage
  element._loadedImage = loadedImage
  if element._renderer then
    element._renderer._loadedImage = loadedImage
  end
  return nil
end

-- ----------------------------------------------------------------------------
-- onDetach — release image-load callback closures so the element can be GC'd
-- cleanly in immediate mode (formerly part of Element:_cleanup). The cached
-- `_loadedImage` is reproduced on the next attach via the Imageable saveState
-- -> restoreState cycle, so dropping the live references is always safe.
-- ----------------------------------------------------------------------------

local function onDetach(element)
  element.onImageLoad = nil
  element.onImageError = nil
end

-- ----------------------------------------------------------------------------
-- Build the (stateless, shared, immutable) behavior instance.
-- ----------------------------------------------------------------------------

local Imageable = Behavior.new({
  onAttach = onAttach,
  onDetach = onDetach,
  onUpdate = function() end,
  onDraw = function() end,
  saveState = saveState,
  restoreState = restoreState,
  shouldAttach = shouldAttach,
})

-- Expose the predicate at module level so callers/tests can reference it
-- directly without an element instance (mirrors Behavior.shouldAttach /
-- Clickable.shouldAttach). `loadImage` is NOT exposed on the (frozen) behavior
-- instance; it is captured as a module-local upvalue by the onAttach closure that
-- installs `element._loadImage`.
Imageable.shouldAttach = shouldAttach

return Imageable
