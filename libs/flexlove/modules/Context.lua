---@class Context
local modulePath = (...):match("(.-)[^%.]+$")
local ZIndex = require(modulePath .. "ZIndex")
local Element = require(modulePath .. "Element")
local Context = {
  topElements = {},
  -- Base scale configuration
  baseScale = nil, -- {width: number, height: number}
  -- Current scale factors
  scaleFactors = { x = 1.0, y = 1.0 },
  defaultTheme = nil,
  _focusedElement = nil,
  _focusedElementId = nil, -- Stable id used to rehydrate focus across immediate-mode frames
  _activeEventElement = nil,
  _cachedViewport = { width = 0, height = 0 },
  -- Immediate mode state
  _immediateMode = false,
  _frameNumber = 0,
  _currentFrameElements = {},
  _immediateModeState = nil, -- Will be initialized if immediate mode is enabled
  _frameStarted = false,
  _autoBeganFrame = false,
  -- Z-index ordered element tracking for immediate mode
  _zIndexOrderedElements = {}, -- Array of elements sorted by z-index (lowest to highest)
  -- Focus management guard
  _settingFocus = false,
  -- Hook called whenever focus changes: function(element) or nil
  _onFocusChanged = nil,

  -- Navigation state
  _navigationContext = {
    lastFocusedElement = nil, -- For returning from modals
    navigationMode = "sequential", -- "sequential" or "directional"
    containerElement = nil, -- Current navigation container
  },

  initialized = false,

  -- Expose internal hit-testing helpers for unit testing only.
  -- These are populated below after their local definitions. They are NOT part
  -- of the public API and must not be relied on by callers; they exist so the
  -- shared hit-test core (the single place display:none guarding lives) can be
  -- exercised directly by the test suite. Subsequent unified-event-routing
  -- tasks consume these locals through the mode-agnostic query functions.
  _test = {
    pointHitsElement = nil,
    elementHasScrollableOverflow = nil,
  },

  -- Debug draw overlay
  _debugDraw = false,
  _debugDrawKey = nil,

  -- Initialization state tracking
  ---@type "uninitialized"|"initializing"|"ready"
  _initState = "uninitialized",
  ---@type table[] Queue of {props: ElementProps, callback: function(element)|nil}
  _initQueue = {},

  -- Per-frame cache for findInteractiveAtPosition so Clickable.onUpdate's
  -- per-element call (unified-event-routing task 05) doesn't re-walk the tree
  -- + realloc + sort for every interactive element sharing the same cursor.
  -- Invalidated explicitly by Context.clearInteractiveCache() at the start of
  -- each flexlove.update (both modes) and in clearFrameElements (immediate
  -- mid-frame rebuild). It also self-invalidates when the topElements table
  -- reference changes (tests replace it per-case; immediate-mode beginFrame
  -- reassigns it each frame), so direct callers that never go through
  -- flexlove.update still see fresh results across tree swaps.
  _interactiveLookupCache = {
    valid = false,
    x = nil,
    y = nil,
    result = nil,
    topElementsRef = nil,
    frameNumber = -1,
  },
}

--- Check if a point hits an element, accounting for scroll offsets and display:none.
--- All mode-agnostic query functions use this as their single hit-test entry point,
--- ensuring fixes like display:none guarding apply everywhere.
---
--- This is the single canonical place where `element.display == false` short-
--- circuits hit testing. Parent-chain clipping/scroll-offset accumulation is
--- the caller's responsibility: callers walk the parent chain (using
--- `elementHasScrollableOverflow` to decide which ancestors clip) and pass the
--- accumulated scroll offset in here. Keeping the parent walk outside this core
--- lets retained-mode (recursive tree descent) and immediate-mode (flat
--- z-index list) callers share the exact same primitive bounds/display logic.
---@param element Element
---@param mx number Screen X coordinate
---@param my number Screen Y coordinate
---@param scrollOffsetX number? Accumulated scroll offset from parent chain
---@param scrollOffsetY number? Accumulated scroll offset from parent chain
---@return boolean hits
local function pointHitsElement(element, mx, my, scrollOffsetX, scrollOffsetY)
  scrollOffsetX = scrollOffsetX or 0
  scrollOffsetY = scrollOffsetY or 0

  -- Skip display:none elements entirely
  if element.display == false then
    return false
  end

  local bx = element.x
  local by = element.y
  local bw = element._borderBoxWidth or (element.width + element.padding.left + element.padding.right)
  local bh = element._borderBoxHeight or (element.height + element.padding.top + element.padding.bottom)

  local adjustedX = mx + scrollOffsetX
  local adjustedY = my + scrollOffsetY

  return adjustedX >= bx and adjustedX <= bx + bw and adjustedY >= by and adjustedY <= by + bh
end

--- Check if an element has scrollable/clipped overflow (for scroll offset accumulation).
--- Returns true for `scroll`, `auto`, and `hidden` on either axis. These are the
--- overflow values that clip/translate descendant content and therefore require
--- scroll-offset compensation when hit testing descendants.
---@param element Element
---@return boolean
local function elementHasScrollableOverflow(element)
  local overflowX = element.overflowX or element.overflow
  local overflowY = element.overflowY or element.overflow
  return overflowX == "scroll"
    or overflowX == "auto"
    or overflowY == "scroll"
    or overflowY == "auto"
    or overflowX == "hidden"
    or overflowY == "hidden"
end

-- Expose the two core helpers for unit testing only (see Context._test above).
Context._test.pointHitsElement = pointHitsElement
Context._test.elementHasScrollableOverflow = elementHasScrollableOverflow

-- Public exposure of the canonical hit-test primitive so other modules
-- (e.g. FlexLove's `getElementAtPosition` / `_getTouchElementAtPosition`
-- tree walks) can share the single implementation of bounds + display:none
-- guarding instead of duplicating the `display == false` check inline.
-- This keeps "display == false" in exactly one place for hit-testing.
Context.pointHitsElement = pointHitsElement
Context.elementHasScrollableOverflow = elementHasScrollableOverflow

--- Find the first scrollable element at a screen position, regardless of mode.
--- This is the mode-agnostic successor to the two duplicated scrollable lookups
--- that previously lived inline in `flexlove.wheelmoved`:
---   * immediate mode — walked `Context._zIndexOrderedElements` in reverse and
---     re-implemented bounds + parent-chain clipping + scroll-offset math; and
---   * retained mode — recursed through `Context.topElements` with a private
---     `findScrollableAtPosition(elements, x, y)` helper.
--- Both paths now collapse into this single function, which routes every
--- hit test through `pointHitsElement` (the single place `display == false`
--- is guarded) and every scroll-offset decision through
--- `elementHasScrollableOverflow`. As a result display:none elements are never
--- returned in either mode, fixing the latent bug where the immediate-mode
--- path's `isPointInElement` did not skip display:none elements.
---
--- The retained-mode branch intentionally mirrors the original
--- `findScrollableAtPosition` helper's tree walk (deepest scrollable wins,
--- children checked before self) but is upgraded to thread accumulated scroll
--- offsets through `pointHitsElement` so nested scrolled containers are tested
--- against their visible position. The original helper is removed once
--- `flexlove.wheelmoved` is rerouted onto this function in task 04.
---@param x number Screen X coordinate
---@param y number Screen Y coordinate
---@return Element|nil The scrollable element, or nil
function Context.findScrollableAtPosition(x, y)
  if Context.isImmediateMode() then
    -- Immediate mode: iterate the z-index ordered list (reverse order =
    -- topmost first). pointHitsElement supplies the bounds + display guard.
    for i = #Context._zIndexOrderedElements, 1, -1 do
      local element = Context._zIndexOrderedElements[i]
      if pointHitsElement(element, x, y) then
        local overflowX = element.overflowX or element.overflow
        local overflowY = element.overflowY or element.overflow
        if
          (overflowX == "scroll" or overflowX == "auto" or overflowY == "scroll" or overflowY == "auto")
          and (element._overflowX or element._overflowY)
        then
          return element
        end
      end
    end
    return nil
  else
    -- Retained mode: recursive tree walk from topElements. Children are
    -- checked before self (deepest scrollable wins); accumulated scroll
    -- offsets are threaded through pointHitsElement so descendants of
    -- scrolled containers are hit-tested against their translated position.
    local function findInTree(elements, scrollOffsetX, scrollOffsetY)
      scrollOffsetX = scrollOffsetX or 0
      scrollOffsetY = scrollOffsetY or 0
      for i = #elements, 1, -1 do
        local element = elements[i]
        if pointHitsElement(element, x, y, scrollOffsetX, scrollOffsetY) then
          if #element.children > 0 then
            local childScrollOffsetX = scrollOffsetX
            local childScrollOffsetY = scrollOffsetY
            if elementHasScrollableOverflow(element) then
              childScrollOffsetX = childScrollOffsetX + (element._scrollX or 0)
              childScrollOffsetY = childScrollOffsetY + (element._scrollY or 0)
            end
            local childResult = findInTree(element.children, childScrollOffsetX, childScrollOffsetY)
            if childResult then
              return childResult
            end
          end
          -- No descendant was scrollable — check self.
          local overflowX = element.overflowX or element.overflow
          local overflowY = element.overflowY or element.overflow
          if
            (overflowX == "scroll" or overflowX == "auto" or overflowY == "scroll" or overflowY == "auto")
            and (element._overflowX or element._overflowY)
          then
            return element
          end
        end
      end
      return nil
    end
    return findInTree(Context.topElements)
  end
end

--- Check whether immediate mode is active.
--- This is the single canonical accessor for the mode flag consumed throughout
--- the framework. Mode-aware branches elsewhere call this instead of reading
--- `Context._immediateMode` directly, so the literal mode flag only appears
--- here (its definition) and in StateManager (its mirrored storage) — never
--- scattered across Element / behaviors / managers (behavior-mode-unification
--- task 11).
---@return boolean
function Context.isImmediateMode()
  return Context._immediateMode
end

---@return number, number -- scaleX, scaleY
function Context.getScaleFactors()
  return Context.scaleFactors.x, Context.scaleFactors.y
end

--- Register an element in the z-index ordered tree (for immediate mode)
---@param element Element The element to register
function Context.registerElement(element)
  if not Context.isImmediateMode() then
    return
  end

  table.insert(Context._zIndexOrderedElements, element)
end

function Context.clearFrameElements()
  Context._zIndexOrderedElements = {}
  Context.clearInteractiveCache()
end

--- Compute the composite z-index key for an element.
--- rootZ * ROOT_WEIGHT + depth * DEPTH_WEIGHT + ownZ
---
--- ROOT_WEIGHT (10^10) gives the top-level ancestor's z-index 10 digits of significance.
--- DEPTH_WEIGHT (10^3) gives nesting depth 3 digits, ensuring children always sort above
--- their ancestors. The element's own z (capped to ±999 by ZIndex.clamp) fits within the
--- remaining 3 digits without interfering with the depth component.
---
--- These weights assume |z| <= ZIndex.MAX_Z and practical tree depths (< 10^7), which
--- keeps the composite key well within Lua's exact integer range (2^53 ≈ 9 × 10^15).
---
--- This is the SINGLE canonical z-index ordering function, used by both
--- sortElementsByZIndex (the immediate-mode flat list sort) and
--- findInteractiveAtPosition (the mode-agnostic occlusion sort). Keeping them
--- on the same key ensures the interactive topmost element matches the visual
--- draw order — a button in a z=50 MainMenu window must occlude a button in a
--- z=0 BottomBar even when both buttons default to own z=0.
local function getEffectiveZIndex(elem)
  local ownZ = elem.z or 0
  local rootZ = ownZ
  local depth = 0
  local current = elem.parent
  while current do
    rootZ = current.z or 0
    depth = depth + 1
    current = current.parent
  end
  return rootZ * ZIndex.ROOT_WEIGHT + depth * ZIndex.DEPTH_WEIGHT + ownZ
end

-- Public exposure so FlexLove.getElementAtPosition shares the single
-- implementation instead of duplicating the parent-chain walk as a closure.
Context.getEffectiveZIndex = getEffectiveZIndex

--- Sort elements by z-index (called after all elements are registered)
function Context.sortElementsByZIndex()
  -- Precompute the composite key ONCE per element so the sort comparator is a
  -- pure table lookup (O(1)) instead of re-walking the parent chain on every
  -- O(N log N) comparison. This function runs every frame in immediate mode.
  local elements = Context._zIndexOrderedElements
  local zIndices = {}
  for i = 1, #elements do
    zIndices[elements[i]] = getEffectiveZIndex(elements[i])
  end
  table.sort(elements, function(a, b)
    return zIndices[a] < zIndices[b]
  end)
end

--- Find the topmost interactive element at a screen position, regardless of mode.
--- Replaces the former immediate-mode-only `Context.getTopElementAt()` (removed
--- in unified-event-routing task 05) and the retained-mode `_activeEventElement`
--- mechanism — both are now funneled through this single entry point.
---
--- In immediate mode this replaces Context.getTopElementAt() (which only worked
--- in immediate mode). In retained mode this provides the same role as the
--- _activeEventElement set by flexlove.getElementAtPosition().
---
--- An element is "interactive" if it has an onEvent handler, themeComponent, or is editable.
---@param x number Screen X coordinate
---@param y number Screen Y coordinate
---@return Element|nil The topmost interactive element, or nil
function Context.findInteractiveAtPosition(x, y)
  -- Per-frame cache: Clickable.onUpdate runs this for every interactive
  -- element under the same cursor, but the result for a given (x,y) is
  -- identical across all of them within a single update pass. Returning a
  -- cached element restores the old 1x/frame cost of the _activeEventElement
  -- mechanism that task 05 replaced. Cache auto-invalidates when the
  -- topElements table reference changes (so tests and mid-frame rebuilds get
  -- fresh results) and is cleared explicitly per-frame in flexlove.update.
  local cache = Context._interactiveLookupCache
  if
    cache.valid
    and cache.x == x
    and cache.y == y
    and cache.topElementsRef == Context.topElements
    and cache.frameNumber == Context._frameNumber
  then
    return cache.result
  end

  local interactiveCandidates = {}

  local function collectInteractive(element, scrollOffsetX, scrollOffsetY)
    scrollOffsetX = scrollOffsetX or 0
    scrollOffsetY = scrollOffsetY or 0

    if not pointHitsElement(element, x, y, scrollOffsetX, scrollOffsetY) then
      return
    end

    -- Check if this element is interactive
    if element.onEvent or element.themeComponent or element.editable then
      table.insert(interactiveCandidates, element)
    end

    -- Recurse into children with accumulated scroll offset
    local childScrollOffsetX = scrollOffsetX
    local childScrollOffsetY = scrollOffsetY
    if elementHasScrollableOverflow(element) then
      childScrollOffsetX = childScrollOffsetX + (element._scrollX or 0)
      childScrollOffsetY = childScrollOffsetY + (element._scrollY or 0)
    end

    for _, child in ipairs(element.children) do
      collectInteractive(child, childScrollOffsetX, childScrollOffsetY)
    end
  end

  -- Always traverse the tree (works in both modes — topElements exists always)
  for _, element in ipairs(Context.topElements) do
    collectInteractive(element)
  end

  -- Sort by composite z-index descending — topmost wins. The composite key
  -- (rootZ * ROOT_WEIGHT + depth * DEPTH_WEIGHT + ownZ) matches the ordering
  -- used by sortElementsByZIndex / _zIndexOrderedElements, so the interactive
  -- topmost element matches the visual draw order. This is critical for the
  -- game's multi-window layout: a button inside a z=50 MainMenu window must
  -- occlude a button inside a z=0 BottomBar even when both buttons default to
  -- own z=0. Sorting by own-z alone (the original implementation) couldn't
  -- distinguish them, so the wrong window's button could win, leaving the
  -- visible button's isActiveElement=false and clicks/hover dead.
  local zIndices = {}
  for _, el in ipairs(interactiveCandidates) do
    zIndices[el] = getEffectiveZIndex(el)
  end
  table.sort(interactiveCandidates, function(a, b)
    return zIndices[a] > zIndices[b]
  end)

  local result = interactiveCandidates[1]

  cache.x = x
  cache.y = y
  cache.result = result
  cache.topElementsRef = Context.topElements
  cache.frameNumber = Context._frameNumber
  cache.valid = true

  return result
end

--- Invalidate the per-frame `findInteractiveAtPosition` cache.
--- Called once at the top of `flexlove.update` (the natural per-frame boundary
--- in both modes) and from `clearFrameElements` (immediate-mode mid-frame
--- rebuild). After invalidation the next lookup recomputes fresh.
function Context.clearInteractiveCache()
  local cache = Context._interactiveLookupCache
  cache.valid = false
  cache.x = nil
  cache.y = nil
  cache.result = nil
  cache.topElementsRef = nil
  cache.frameNumber = -1
end

--- Set the focused element (centralizes focus management)
--- Automatically blurs the previously focused element if different
---@param element Element|nil The element to focus (nil to clear focus)
function Context.setFocused(element)
  if Context._focusedElement == element then
    return -- Already focused
  end

  -- Prevent re-entry during focus change
  if Context._settingFocus then
    return
  end
  Context._settingFocus = true

  -- Save reference to previously focused element before updating
  local oldFocusedElement = Context._focusedElement

  -- Blur previously focused element
  if oldFocusedElement and oldFocusedElement ~= element then
    if oldFocusedElement._textEditor then
      oldFocusedElement._textEditor:blur(oldFocusedElement)
    end
  end

  -- Set new focused element and persist its id for immediate-mode rehydration
  Context._focusedElement = element
  Context._focusedElementId = element and (element.id ~= "" and element.id or nil) or nil

  -- Notify any registered focus change hook (e.g. FocusIndicator)
  if Context._onFocusChanged then
    Context._onFocusChanged(element)
  end

  -- Focus the new element's text editor if it has one
  if element and element._textEditor then
    element._textEditor._focused = true
  end

  Context._settingFocus = false
end

--- Recursively search for an element by id in an element tree
---@param root Element The root element to start searching from
---@param targetId string The id to search for
---@return Element|nil The element with the matching id, or nil if not found
local function findElementById(root, targetId)
  if root.id == targetId then
    return root
  end
  for _, child in ipairs(root.children or {}) do
    local found = findElementById(child, targetId)
    if found then
      return found
    end
  end
  return nil
end

--- Rehydrate _focusedElement from _focusedElementId by scanning live elements.
--- Called at the start of getFocused() in immediate mode so stale references
--- are always replaced with the current-frame object before use.
function Context._rehydrateFocus()
  if not Context._focusedElementId then
    Context._focusedElement = nil
    return
  end

  -- First, try a fast linear search through all registered elements
  for _, elem in ipairs(Context._zIndexOrderedElements) do
    if elem.id == Context._focusedElementId then
      Context._focusedElement = elem
      return
    end
  end

  -- If not found, recursively search from top-level elements
  -- This handles cases where elements may not be in _zIndexOrderedElements
  for _, topLevel in ipairs(Context.topElements or {}) do
    local found = findElementById(topLevel, Context._focusedElementId)
    if found then
      Context._focusedElement = found
      return
    end
  end

  -- Element with that id is not present this frame (e.g. screen changed)
  Context._focusedElement = nil
end

--- Get the currently focused element
---@return Element|nil The focused element, or nil if none
function Context.getFocused()
  if Context.isImmediateMode() then
    Context._rehydrateFocus()
  end
  return Context._focusedElement
end

--- Clear focus from any element
function Context.clearFocus()
  Context._focusedElementId = nil
  Context.setFocused(nil)
end

--- Get all focusable elements in tab order, regardless of mode.
--- In immediate mode this extracts from _zIndexOrderedElements (flat, z-sorted).
--- In retained mode it walks the element tree (DOM order).
--- In both modes, display:none elements are excluded.
---@return table<Element> List of focusable elements in tab order
function Context.getFocusableElements()
  local focusable = {}

  local function isFocusable(elem)
    if elem.display == false then
      return false
    end
    -- Use Element:isFocusable() for consistent behavior
    return Element.isFocusable(elem)
  end

  local function collectFromTree(elements)
    for _, elem in ipairs(elements) do
      if isFocusable(elem) then
        table.insert(focusable, elem)
      end
      if #elem.children > 0 then
        collectFromTree(elem.children)
      end
    end
  end

  if Context._immediateMode then
    -- Immediate mode: _zIndexOrderedElements is already in z-index order (lowest first),
    -- which approximates tab order for most UIs.
    for _, elem in ipairs(Context._zIndexOrderedElements) do
      if isFocusable(elem) then
        table.insert(focusable, elem)
      end
    end
  else
    -- Retained mode: walk the top element trees in DOM order
    collectFromTree(Context.topElements)
  end

  return focusable
end

-- ====================
-- Navigation Context
-- ====================

--- Push current focus onto stack (for modals/dialogs)
---@param element Element?
function Context.pushFocusStack(element)
  Context._navigationContext.lastFocusedElement = Context._focusedElement
  if element then
    Context.setFocused(element)
  end
end

--- Pop focus from stack (return from modal)
---@return Element?
function Context.popFocusStack()
  local previous = Context._navigationContext.lastFocusedElement
  Context._navigationContext.lastFocusedElement = nil
  Context.setFocused(previous)
  return previous
end

--- Set navigation container (scope for tab navigation)
---@param element Element?
function Context.setNavigationContainer(element)
  Context._navigationContext.containerElement = element
end

--- Get navigation container
---@return Element?
function Context.getNavigationContainer()
  return Context._navigationContext.containerElement
end

return Context
