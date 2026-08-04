---@class Element
---@field id string
---@field children Element[]
---@field parent Element|nil
---@field userdata any|nil
---@field onEvent fun(self: Element, event: table)|nil
---@field onEventDeferred boolean|nil
---@field onFocus fun(self: Element)|nil
---@field onFocusDeferred boolean
---@field dropFocusOnSelection boolean|nil
---@field onBlur fun(self: Element)|nil
---@field onBlurDeferred boolean
---@field onTextInput fun(self: Element, text: string)|nil
---@field onTextInputDeferred boolean
---@field onTextChange fun(self: Element, text: string)|nil
---@field onTextChangeDeferred boolean
---@field onEnter fun(self: Element)|nil
---@field onEnterDeferred boolean
---@field customDraw fun(self: Element)|nil
---@field onTouchEvent fun(self: Element, event: table)|nil
---@field onTouchEventDeferred boolean
---@field onGesture fun(self: Element, gesture: table)|nil
---@field onGestureDeferred boolean
---@field touchEnabled boolean
---@field multiTouchEnabled boolean
---@field theme table|nil
---@field themeComponent string|nil
---@field disabled boolean
---@field active boolean
---@field disableHighlight boolean
---@field contentAutoSizingMultiplier number[]|nil
---@field scaleCorners boolean|nil
---@field scalingAlgorithm string|nil
---@field contentBlur {radius:number, quality?:number}|nil
---@field backdropBlur {radius:number, quality?:number}|nil
---@field editable boolean
---@field multiline boolean
---@field passwordMode boolean
---@field textWrap string|boolean
---@field maxLines number|nil
---@field maxLength number|nil
---@field placeholder string|nil
---@field inputType string
---@field textOverflow string
---@field scrollable boolean
---@field autoGrow boolean
---@field selectOnFocus boolean
---@field cursorColor Color|nil
---@field selectionColor Color|nil
---@field cursorBlinkRate number
---@field selectParent Element|nil
---@field selectOption table|nil
---@field onChange fun(self: Element, value: any, option: Element)|nil
---@field border number|table|nil
---@field borderColor Color
---@field backgroundColor Color
---@field opacity number
---@field visibility string
---@field display boolean
---@field transform table|nil
---@field cornerRadius number|{topLeft:number, topRight:number, bottomLeft:number, bottomRight:number}|nil
---@field text string|nil
---@field textAlign string|table|nil
---@field textAlignHorizontal string
---@field textAlignVertical string
---@field imagePath string|nil
---@field image table|nil
---@field objectFit string
---@field objectPosition string
---@field imageOpacity number
---@field imageRepeat string
---@field imageTint Color|nil
---@field onImageLoad fun(self: Element, image: table)|nil
---@field onImageLoadDeferred boolean
---@field onImageError fun(self: Element, err: string)|nil
---@field onImageErrorDeferred boolean
---@field prevGameSize {width:number, height:number}
---@field autosizing {width:boolean, height:boolean}
---@field units table
---@field minTextSize number|nil
---@field maxTextSize number|nil
---@field autoScaleText boolean
---@field fontFamily string|nil
---@field textSize number
---@field width number
---@field height number
---@field x number
---@field y number
---@field z number
---@field gap number
---@field flexGrow number
---@field flexShrink number
---@field flexBasis number|string
---@field padding {top:number, right:number, bottom:number, left:number}
---@field margin {top:number, right:number, bottom:number, left:number}
---@field tabIndex number|nil
---@field textColor Color
---@field positioning string
---@field top number|nil
---@field right number|nil
---@field bottom number|nil
---@field left number|nil
---@field flexDirection string|nil
---@field flexWrap string|nil
---@field justifyContent string|nil
---@field alignItems string|nil
---@field alignContent string|nil
---@field justifySelf string|nil
---@field alignSelf string
---@field gridRows number|nil
---@field gridColumns number|nil
---@field columnGap number|nil
---@field rowGap number|nil
---@field transition table
---@field transitions table|nil
---@field animation table|nil
---@field overflow string|nil
---@field overflowX string|nil
---@field overflowY string|nil
---@field scrollbarWidth number|nil
---@field scrollbarColor Color|nil
---@field scrollbarBackgroundColor Color|nil
---@field scrollbarTrackColor Color|nil
---@field scrollbarRadius number|nil
---@field scrollbarPadding number|nil
---@field scrollSpeed number|nil
---@field invertScroll boolean|nil
---@field scrollBarStyle string|nil
---@field scrollbarKnobOffset number|nil
---@field hideScrollbars boolean|nil
---@field scrollbarPlacement string|nil
---@field scrollbarBalance number|nil
---@field borderWidth number|nil
---@field fontSize number|nil
---@field lineHeight number|nil
local Element = {}
Element.__index = Element

-- Forward declarations for the special-handler binding helpers used by
-- Element:_applyProps (behavior-mode-unification task 08 capstone). These
-- absorb the former subsystem-init and visual-state phase bodies (ThemeManager
-- creation + theme-field exposure + editable/text/scroll/autoGrow/select-field
-- defaults + parent assignment, and border/cornerRadius/display/text/textAlign
-- normalization). They are now private implementation of the props-binding phase
-- rather than standalone Element methods, so there are no longer per-capability
-- init phases on Element.
local bindThemeAndFields, bindVisualState

-- NOTE: There is intentionally NO custom Element.__newindex for dimension properties.
-- Lua's __newindex fires ONLY when the key is ABSENT from the raw table, but width/
-- height/x/y are all assigned during Element.new, so they already exist post-
-- construction. A __newindex handler therefore CANNOT intercept retained-mode bare
-- writes like `element.width = "42%"` (it just rawsets the broken string).
-- Dimensions are instead validated lazily in Element:_checkDimensionTypes() at the
-- start of each reflow, and must be changed via :setProperty() for resolution +
-- layout invalidation. Keeping the metatable free of __newindex also avoids a
-- per-field-write function call on every absent-key assignment (perf).

local MAX_DEFER_RETRIES = 10
local MAX_DEFERRED_METHODS = 100
local _DEFERRED_NIL = {}
local unpack = table.unpack or unpack

---Initialize Element module with required dependencies
---@param deps table Dependency table containing all required modules
function Element.init(deps)
  Element._ErrorHandler = deps.ErrorHandler
  Element._Color = deps.Color
  Element._Context = deps.Context
  Element._Units = deps.Units
  Element._Calc = deps.Calc
  Element._utils = deps.utils
  Element._InputEvent = deps.InputEvent
  Element._EventHandler = deps.EventHandler
  Element._Renderer = deps.Renderer
  Element._LayoutEngine = deps.LayoutEngine
  Element._TextEditor = deps.TextEditor
  Element._ScrollManager = deps.ScrollManager
  Element._Theme = deps.Theme
  Element._RoundedRect = deps.RoundedRect
  Element._NinePatch = deps.NinePatch
  Element._ImageRenderer = deps.ImageRenderer
  Element._ImageCache = deps.ImageCache
  Element._ImageScaler = deps.ImageScaler
  Element._Blur = deps.Blur
  Element._Transform = deps.Transform
  Element._Grid = deps.Grid
  Element._StateManager = deps.StateManager
  Element._GestureRecognizer = deps.GestureRecognizer
  Element._Performance = deps.Performance
  Element._Animation = deps.Animation
  Element._ZIndex = deps.ZIndex
  Element._Select = deps.Select
  Element._PropertySchema = deps.PropertySchema or require("modules.PropertySchema")
  Element._Select.init({
    ErrorHandler = Element._ErrorHandler,
    Context = Element._Context,
    StateManager = Element._StateManager,
    utils = Element._utils,
    Element = Element,
  })
  Element._ScrollManager.init({
    ErrorHandler = Element._ErrorHandler,
    Context = Element._Context,
    StateManager = Element._StateManager,
  })

  -- Bind Element scroll/scrollbar API directly onto ScrollManager.
  -- ScrollManager owns all scroll interaction logic; Element retains only
  -- 1-line delegates (no hand-written sync/nil-guard boilerplate).
  local SM = Element._ScrollManager
  Element._syncScrollManagerState = SM.syncToElement
  Element._detectOverflow = SM._detectOverflow
  Element.setScrollPosition = SM.setScrollPosition
  Element._calculateScrollbarDimensions = SM._calculateScrollbarDimensions
  Element._getScrollbarAtPosition = SM._getScrollbarAtPosition
  Element._handleScrollbarPress = SM._handleScrollbarPress
  Element._handleScrollbarDrag = SM._handleScrollbarDrag
  Element._handleScrollbarRelease = SM._handleScrollbarRelease
  Element._handleWheelScroll = SM._handleWheelScroll
  Element.getScrollPosition = SM.getScrollPosition
  Element.getMaxScroll = SM.elementGetMaxScroll
  Element.getScrollPercentage = SM.elementGetScrollPercentage
  Element.hasOverflow = SM.elementHasOverflow
  Element.getContentSize = SM.elementGetContentSize
  Element.scrollBy = SM.elementScrollBy
  Element.scrollToTop = SM.scrollToTop
  Element.scrollToBottom = SM.scrollToBottom
  Element.scrollToLeft = SM.scrollToLeft
  Element.scrollToRight = SM.scrollToRight

  -- Hoist subsystem dependency tables: created once at init time, not rebuilt
  -- per Element.new() call. Staged initializers reference these directly.
  Element._eventHandlerDeps = {
    InputEvent = Element._InputEvent,
    Context = Element._Context,
    utils = Element._utils,
  }

  -- Behavior registry (behavior-mode-unification). Concrete behaviors live in
  -- modules/behaviors/ and auto-attach during Element.new when their
  -- shouldAttach(props) predicate returns true. Element.update/draw/save-restore
  -- dispatch over `element.behaviors` instead of branching on capability flags.
  -- Registry order matters for onDraw layering: Themed (core Renderer:draw) must
  -- run before Clickable (pressed overlay) so pressed feedback paints on top.
  -- Imageable (image config) runs last. Animated (task 06) is late-attach-only.
  -- Task 02 wires Clickable; task 05 Selectable; task 06 Animated; task 07
  -- Themed + Imageable; task 04 TextEditable (cursor blink + TextEditor
  -- ownership + the 27 text-delegate forwarders). Scrollable is pending.
  Element._behaviorRegistry = deps.behaviors or deps.clickableBehaviors or {}
  -- TextEditable module reference: Element's 1-line text-delegate forwarders
  -- route through `Element._TextEditable.<fn>(self, ...)` (task 04). Resolved
  -- from deps (wired by FlexLove alongside the behavior registry) so minimal
  -- builds without TextEditable leave forwarders inert (guarded by their
  -- callers / the behavior's nil-checks).
  Element._TextEditable = deps.TextEditable
  -- Cached lookup of the Animated behavior instance for late-attach. Resolved
  -- lazily (behaviors are optional in minimal builds) the first time an
  -- animation is created on an element.
  Element._animatedBehavior = nil
  Element._rendererDeps = {
    Color = Element._Color,
    RoundedRect = Element._RoundedRect,
    NinePatch = Element._NinePatch,
    ImageRenderer = Element._ImageRenderer,
    ImageCache = Element._ImageCache,
    Theme = Element._Theme,
    Blur = Element._Blur,
    Transform = Element._Transform,
    utils = Element._utils,
  }
  Element._layoutEngineDeps = {
    utils = Element._utils,
    Grid = Element._Grid,
    Units = Element._Units,
    Context = Element._Context,
    ErrorHandler = Element._ErrorHandler,
  }
  Element._textEditorDeps = {
    Context = Element._Context,
    StateManager = Element._StateManager,
    Color = Element._Color,
    utils = Element._utils,
  }
  Element._scrollManagerDeps = {
    utils = Element._utils,
    Color = Element._Color,
  }
end

-- Module-level helper: resolve a dimensional property with CSS-like unit support (px, %, vw, vh, calc)
-- Defined once (not inside new()) to avoid per-element closure allocation.
-- Handles parsing, defensive checks, and storage in both self and self.units tables.
---@param self table Element instance
---@param raw any Raw property value (string, number, CalcObject, or nil)
---@param key string Field name on self and self.units (e.g., "width", "x")
---@param ref number Reference dimension for percentage resolution
---@param ctx {vw:number, vh:number, sx:number, sy:number} Viewport and scale context
---@param opts {offset?: number, scaleAxis?: "x"|"y", default?: number, nullable?: boolean}?
---@return number? resolved Resolved pixel value (or nil if opts.nullable and input is missing/invalid)
local function _resolveUnit(self, raw, key, ref, ctx, opts)
  opts = opts or {}
  if raw == nil then
    if opts.nullable then
      return nil
    end
    local default = opts.default or 0
    self[key] = (opts.offset or 0) + default
    self.units[key] = { value = default, unit = "px" }
    return self[key]
  end
  local isCalc = Element._Calc and Element._Calc.isCalc(raw)
  if type(raw) == "string" or isCalc then
    local value, unit = Element._Units.parse(raw)
    local resolved = Element._Units.resolve(value, unit, ctx.vw, ctx.vh, ref)
    if type(resolved) ~= "number" then
      if opts.nullable then
        return nil
      end
      Element._ErrorHandler:warn("Element", "LAY_003", {
        issue = key .. " resolution returned non-number value",
        type = type(resolved),
        value = tostring(resolved),
      })
      resolved = 0
    end
    self.units[key] = { value = value, unit = unit }
    self[key] = (opts.offset or 0) + resolved
  else
    local val = raw
    if opts.scaleAxis and Element._Context.baseScale then
      val = raw * (opts.scaleAxis == "x" and ctx.sx or ctx.sy)
    end
    self[key] = (opts.offset or 0) + val
    self.units[key] = { value = raw, unit = "px" }
  end
  return self[key]
end

-- Module-level helper: re-resolve a stored unit spec against a new viewport/parent reference.
-- Used by resize() to refresh min/max constraints declared with %/vw/vh units.
local function _refreshUnit(self, key, ref, ctx, scaleAxis)
  local u = self.units[key]
  if not u or u.value == nil then
    return
  end
  if u.unit == "px" then
    self[key] = Element._Context.baseScale and (u.value * (scaleAxis == "x" and ctx.sx or ctx.sy)) or u.value
    return
  end
  local resolved = Element._Units.resolve(u.value, u.unit, ctx.vw, ctx.vh, ref)
  self[key] = type(resolved) == "number" and resolved or nil
end

-- ---------------------------------------------------------------------------
-- Consolidated warn helpers (Task 11).
-- Each duplicated "expecting X, got Y" / guard instrumentation block lived at
-- its own use site; these single-reference helpers centralize the emit so call
-- sites are thin invocations. Validation semantics (warn+fallback vs. throw) are
-- preserved exactly — instrumentation is consolidated, not deleted.
-- ---------------------------------------------------------------------------

-- Emit a VAL_001 invalid-enum warn for a textAlign sub-field and return the
-- fallback. textAlign's schema entry is type "any" (string | table | compound),
-- so this IS the boundary validator for the 4 textAlign parse branches in the
-- props-phase visual-state helper.
local function _warnTextAlign(field, expected, got, fallback)
  Element._ErrorHandler:warn("Element", "VAL_001", {
    property = field,
    expected = expected,
    got = tostring(got),
  })
  return fallback
end

-- Emit a FLEX_00x warn for an invalid flexGrow/flexShrink/flexBasis and return
-- the fallback value. These props are SPECIAL_PROPS (warn+fallback, not throw)
-- so this is their boundary validator.
local function _warnFlexInvalid(self, code, issue, value, fallback)
  Element._ErrorHandler:warn("Element", code, {
    element = self.id or "unnamed",
    issue = issue,
    value = tostring(value),
  })
  return fallback
end

-- Emit an ELEM_010/011/012 warn for malformed declarative children entries.
local function _warnChildrenInvalid(self, code, issue, value)
  local details = { element = self.id or "unnamed", issue = issue }
  if value ~= nil then
    details.value = tostring(value)
  end
  Element._ErrorHandler:warn("Element", code, details)
end

-- Emit LAY_011 when CSS positioning props (top/right/bottom/left) are supplied
-- without absolute positioning. Called from both the no-parent and with-parent
-- branches of _initPositioning.
local function _warnCssPositioningWithoutAbsolute(self, props)
  local properties = {}
  if props.top then
    table.insert(properties, "top")
  end
  if props.bottom then
    table.insert(properties, "bottom")
  end
  if props.left then
    table.insert(properties, "left")
  end
  if props.right then
    table.insert(properties, "right")
  end
  Element._ErrorHandler:warn("Element", "LAY_011", {
    element = self.id or "unnamed",
    positioning = self._originalPositioning or "relative",
    properties = table.concat(properties, ", "),
  })
end

-- Emit an ELEM_003/004/005 guard warn for the animation/transition public API
-- (deps-missing, non-table arg, invalid duration, non-table property list).
-- All warn + fall back rather than throw. `value` nil => warn carries no details.
local function _warnAnimApi(code, value)
  if value ~= nil then
    Element._ErrorHandler:warn("Element", code, { value = tostring(value) })
  else
    Element._ErrorHandler:warn("Element", code)
  end
end

-- Image loading + image callback firing now live in the Imageable behavior
-- (modules/behaviors/Imageable.lua) — moved out of Element per
-- behavior-mode-unification task 07. Element is decoupled from image concern;
-- the Imageable behavior enriches `element._renderer` with image config, runs
-- the deferred load pipeline, and persists `_loadedImage` across immediate-mode
-- frames. The fire-callback helper (formerly `_fireImageCallback` here) is
-- reproduced inside Imageable as `fireImageCallback`.

-- ---------------------------------------------------------------------------
-- Data-driven prop binding (Task 03)
-- ---------------------------------------------------------------------------
-- SPECIAL_PROPS is the documented boundary of the schema-driven _applyProps
-- loop. Props listed here are bound explicitly by bindThemeAndFields /
-- bindVisualState / the staged initializers instead of the generic registry
-- loop, for one of five load-bearing reasons (none represent unfinished
-- migration — moving them into the generic loop would require extending the
-- PropertySchema DSL, which is deliberately kept small and declarative):
--
--   1. SUBSYSTEM ORDERING — the prop needs a subsystem constructed first.
--      Theme props (theme/themeComponent/disabled/active/...) depend on the
--      ThemeManager being alive so their defaults can be read from it; the
--      generic loop runs before subsystem creation in _attachBehaviors.
--
--   2. NON-LITERAL DEFAULTS — the default is not a static value the schema's
--      `default:` field can express. borderColor/backgroundColor/textColor
--      default to Color.new(...); text defaults to "" only when editable;
--      scrollable/autoGrow default from multiline. The schema only stores
--      literal defaults (pure-Lua constraint; see PropertySchema.lua header).
--
--   3. UNIT RESOLUTION / VIEWPORT CONTEXT — dimension props (width/height/x/y
--      /gap/padding/...) accept unit strings ("50%", "10px") or CalcObjects that
--      resolve against parent size and viewport, which a pure-Lua schema cannot
--      see. setProperty routes these via the `isDimension` flag at runtime, but
--      construction-time binding needs the sizing context from _initSizingContext.
--
--   4. WARN-AND-FALLBACK vs. THROW — display and the flex props validate with a
--      non-throwing warn+fallback path; the schema's `validator` field throws
--      (VAL_001) for invalid enum/range values. These need their own boundary
--      validators (_warnFlexInvalid / the display type-check).
--
--   5. SUBSYSTEM OWNERSHIP — overflow/scrollbar* are owned by ScrollManager,
--      selectParent/selectOption by the Select subsystem, border/cornerRadius
--      use schema normalizers but bind with a special shape (all-false→nil).
--      These props' storage is owned by their subsystem, not the element core.
--
-- Adding a new SIMPLE prop requires only a PropertySchema entry; adding a prop
-- that needs any of the above additionally requires listing it here and binding
-- it in the matching special-handler phase. Props NOT listed here (e.g.
-- callbacks, editable, multiline, passwordMode, autoScaleText, cursorColor,
-- selectionColor, opacity, visibility, transform, imagePath/objectFit/...,
-- minTextSize/maxTextSize, alignSelf, transition) are bound generically by
-- _applyProps (defaults + normalizers + validators + onX/onXDeferred
-- auto-wiring).
local function _set(...)
  local t = {}
  for _, name in ipairs({ ... }) do
    t[name] = true
  end
  return t
end

local SPECIAL_PROPS = _set(
  -- identity / tree
  "id",
  "parent",
  "children",
  -- theme-driven (ThemeManager owns these / computes defaults)
  "theme",
  "themeComponent",
  "disabled",
  "isDisabled",
  "active",
  "disableHighlight",
  "themeStateLock",
  "themeComponentDisabledStates",
  "scaleCorners",
  "scalingAlgorithm",
  "contentAutoSizingMultiplier",
  -- color defaults that require the Color module
  "borderColor",
  "backgroundColor",
  "textColor",
  -- display: non-throwing warn+fallback (unlike throwing range/enum validators)
  "display",
  -- text editing (validation side-effects / computed defaults)
  "textWrap",
  "scrollable",
  "autoGrow",
  "text",
  "textAlign",
  "textAlignHorizontal",
  "textAlignVertical",
  "textSize",
  "fontFamily",
  -- box model / dimensions (unit resolution)
  "width",
  "height",
  "x",
  "y",
  "z",
  "minWidth",
  "maxWidth",
  "minHeight",
  "maxHeight",
  "gap",
  "top",
  "right",
  "bottom",
  "left",
  "columnGap",
  "rowGap",
  "padding",
  "margin",
  -- layout enums (positioning-mode validation + LayoutEngine config)
  "positioning",
  "flexDirection",
  "flexWrap",
  "justifyContent",
  "alignItems",
  "alignContent",
  "justifySelf",
  "gridRows",
  "gridColumns",
  -- flex shorthand + validated numerics (custom FLEX_xx warnings)
  "flex",
  "flexGrow",
  "flexShrink",
  "flexBasis",
  -- scroll / scrollbar (ScrollManager owns these)
  "overflow",
  "overflowX",
  "overflowY",
  "scrollbarWidth",
  "scrollbarColor",
  "scrollbarTrackColor",
  "scrollbarRadius",
  "scrollbarPadding",
  "scrollSpeed",
  "invertScroll",
  "smoothScrollEnabled",
  "scrollBarStyle",
  "scrollbarKnobOffset",
  "hideScrollbars",
  "scrollbarPlacement",
  "scrollbarBalance",
  "_scrollX",
  "_scrollY",
  -- select (Select subsystem owns these)
  "selectParent",
  "selectOption",
  -- border / cornerRadius use schema normalizers but are bound as special handlers
  "border",
  "cornerRadius",
  -- misc instance-only fields derived during construction
  "tabIndex"
)

--- Bind every schema-driven, side-effect-free prop onto `self` in one pass.
--- Iterates PropertySchema entries: applies defaults, normalizers, validators,
--- and auto-wires `onX` + `onXDeferred` companion pairs. Props listed in
--- SPECIAL_PROPS are skipped (they are handled explicitly in Element.new).
---@param props table Element construction props
function Element:_applyProps(props)
  local schema = Element._PropertySchema
  local registry = schema.all()
  for name, meta in pairs(registry) do
    -- Skip deferred companion entries (auto-wired by their base callback's
    -- hasDeferred branch below) and SPECIAL_PROPS (handled in Element.new).
    if not (name:match("Deferred$") or SPECIAL_PROPS[name]) then
      local value = props[name]
      if value == nil then
        value = meta.default
      end
      if meta.normalizer then
        value = meta.normalizer(value)
      end
      if meta.validator and value ~= nil and not meta.validator(value) then
        -- Mirror the legacy throwing validateRange/validateEnum behavior: invalid
        -- enum/range values error during construction (validated props: opacity,
        -- imageOpacity, objectFit, imageRepeat). display is a special handler that
        -- warns + falls back instead.
        Element._ErrorHandler:error("Element", "VAL_001", {
          property = name,
          expected = meta.type,
          got = tostring(value),
        })
      end
      local key = meta.storageKey or name
      self[key] = value
      -- Auto-wire deferred companion for callbacks that declare hasDeferred.
      if meta.hasDeferred then
        local deferredName = name .. "Deferred"
        local deferredValue = props[deferredName]
        self[deferredName] = deferredValue ~= nil and deferredValue or false
      end
    end
  end

  -- Special-handler binding (behavior-mode-unification task 08 capstone): the
  -- props below need side-effects, ordering relative to subsystems, non-literal
  -- defaults, or unit resolution, so they cannot be bound by the generic schema
  -- loop above. The two helpers below fold in the former subsystem-init phase
  -- (ThemeManager creation + theme-field exposure + editable/multiline/
  -- passwordMode validation + textWrap/scrollable/autoGrow defaults +
  -- selectParent/selectOption/_selectState + parent assignment) and visual-state
  -- phase (border/cornerRadius/display/text/textAlign normalization). Subsystem
  -- CREATION (EventHandler / TextEditor / ScrollManager / Renderer) is owned by
  -- behavior onAttach hooks dispatched in _attachBehaviors; these helpers only
  -- bind FIELDS that the core sizing/box/positioning phases and the behavior
  -- onAttach hooks read.
  bindThemeAndFields(self, props)
  bindVisualState(self, props)
end

---@param props ElementProps
---@return Element
--- Construct a new Element. Orchestrator only; real work is in the staged
--- initializers below (Task 10). No single phase exceeds ~400 LOC.
function Element.new(props)
  -- Staged initializers (behavior-mode-unification task 08 capstone). The
  -- orchestrator is a thin dispatcher: it runs core-data phases only
  -- (construct → props → sizing → box model → positioning → finalize), then
  -- attaches behaviors. The former behavioral phases (subsystem-init, visual-
  -- state, image/renderer, scroll-manager) are deleted: their field-binding logic
  -- folded into _applyProps and their subsystem creation logic moved into
  -- behavior onAttach hooks (Clickable / TextEditable / Selectable / Themed /
  -- Imageable / Scrollable). _attachBehaviors runs at the tail so
  -- Selectable.onAttach can re-scan declarative children built by
  -- _finalizeConstruction and so onAttach sees all element fields bound.
  local self = Element:_construct(props)
  self:_applyProps(props)
  self:_initSizingContext(props)
  self:_initBoxModel(props)
  self:_initPositioning(props)
  self:_finalizeConstruction(props)
  self:_attachBehaviors(props)
  return self
end

--- Phase 1: metatable, schema-driven prop normalization (for special-handler
--- props), default tables (children, _deferredMethods), and ID generation.
--- Schema-driven binding (_applyProps) is invoked separately by Element.new.
function Element:_construct(props)
  local instance = setmetatable({}, Element)

  -- Stash the construction props so behavior onAttach hooks (which receive only
  -- the element per the locked `(element, ...)` signature) can read SPECIAL_PROPS
  -- config that is NOT bound onto the element by the schema-driven _applyProps
  -- loop (e.g. the scrollbar config consumed by Scrollable.onAttach). Prefixed
  -- with `_` so the immediate-mode saveState public-prop scan skips it.
  instance._initProps = props

  -- Apply schema-driven shape normalizers to props for the special-handler
  -- props (padding/margin/flexDirection) whose downstream unit-resolution logic
  -- reads from `props` directly. Generic props are bound by _applyProps below.
  local schema = Element._PropertySchema
  props.flexDirection = schema.get("flexDirection").normalizer(props.flexDirection)
  props.padding = schema.get("padding").normalizer(props.padding)
  props.margin = schema.get("margin").normalizer(props.margin)

  -- Behavior registry (Task 01 of behavior-mode-unification). Concrete
  -- behaviors (Clickable, Scrollable, ...) are attached here in later tasks;
  -- Element:update/draw/save-restore dispatch over this table instead of
  -- branching on individual capability flags. Initially empty so existing
  -- behavior is identical to pre-refactor until behaviors are wired in.
  instance.children = {}
  instance.behaviors = {}
  instance._deferredMethods = {}

  -- Track whether ID was auto-generated (before ID assignment)
  local idWasAutoGenerated = not props.id or props.id == ""

  -- Auto-generate ID if not provided (for all elements)
  if idWasAutoGenerated then
    instance.id = Element._StateManager.generateID(props, props.parent)
  else
    instance.id = props.id
  end

  -- Initialize state manager ID for immediate mode (use self.id which may be auto-generated)
  instance._stateId = instance.id

  -- Register with StateManager for state access (both immediate and retained modes)
  if instance._stateId and instance._stateId ~= "" then
    Element._StateManager.registerStateful(instance._stateId, instance)
  end
  return instance
end

--- Attach behaviors whose shouldAttach(props) predicate matches this element's
--- props. Runs after prop binding + subsystem init (so Deferred flags and the
--- Select subsystem are in place) and dispatches onAttach for each match. The
--- EventHandler (Clickable) is created here rather than in the former subsystem-
--- init phase so Element never needs to know what an individual behavior does —
--- it only iterates the registry (behavior-mode-unification task 02).
function Element:_attachBehaviors(props)
  local registry = Element._behaviorRegistry
  if registry then
    for _, behavior in ipairs(registry) do
      if behavior.shouldAttach(props) then
        table.insert(self.behaviors, behavior)
        behavior.onAttach(self)
      end
    end
  end
end

--- Resolve the (lazily cached) Animated behavior instance from the registry.
-- task 09: since the behavior loop no longer excludes Animated, elements WITH
-- the behavior attached get the loop dispatch and `_dispatchAnimatedUpdate` no-ops
-- for them.
-- task 09 consolidation: `_ensureAnimatedAttached` / `_isAnimatedBehavior`
-- (dead code) were removed; Animated.ensureAttached remains the late-attach
-- entry point for callers that route through it.
function Element._resolveAnimatedBehavior()
  local animated = Element._animatedBehavior
  if animated == nil then
    local registry = Element._behaviorRegistry
    if registry then
      for _, behavior in ipairs(registry) do
        -- Animated exposes ensureAttached; Clickable/Themed/Imageable do not.
        if type(behavior.ensureAttached) == "function" then
          animated = behavior
          break
        end
      end
    end
    Element._animatedBehavior = animated or false
  end
  return animated
end

--- Dispatch Animated.onUpdate for an element EARLY in Element:update (before
--- the behavior loop) so animated geometry (x/y/width/height) is current for
--- Clickable hit-testing and Scrollable interaction this frame. NO-OPS for
--- elements that already have the Animated behavior attached (the loop
--- dispatches those) to avoid a double update — animation:update(dt) is not
--- idempotent within a frame. This handles the direct-assignment path
--- (`element.animation = ...` / `anim:apply`) that bypasses
--- Animated.ensureAttached; for elements with no animation the behavior's
--- onUpdate reads `element.animation` and returns. Not a behavioral capability
--- branch — iterates `element.behaviors`. (behavior-mode-unification task 09.)
function Element._dispatchAnimatedUpdate(element, dt)
  if not element then
    return
  end
  local animated = Element._resolveAnimatedBehavior()
  if not animated then
    return
  end
  -- Already attached? The behavior loop will dispatch it; bail to avoid a
  -- double update (animation:update advances twice if called twice).
  local behaviors = element.behaviors
  if behaviors then
    for i = 1, #behaviors do
      if behaviors[i] == animated then
        return
      end
    end
  end
  animated.onUpdate(element, dt)
end

--- Special-handler binding helper for the props phase (behavior-mode-
--- unification task 08). Formerly the Element subsystem-init phase. Binds the
--- ThemeManager (or no-op fallback) + exposes theme fields, validates
--- editable/multiline/passwordMode combos, sets textWrap/scrollable/autoGrow
--- defaults, initializes selectParent/selectOption/_selectState fields (the
--- Select subsystem itself is initialized by Selectable.onAttach), and assigns
--- self.parent. EventHandler creation is owned by Clickable.onAttach and
--- TextEditor creation by TextEditable.onAttach — both run in _attachBehaviors at
--- the tail of Element.new, so this helper does not touch either subsystem.
bindThemeAndFields = function(self, props)
  if Element._Theme then
    self._themeManager = Element._Theme.Manager.new({
      theme = props.theme or Element._Context.defaultTheme,
      themeComponent = props.themeComponent or nil,
      disabled = props.isDisabled or props.disabled or false,
      active = props.active or false,
      disableHighlight = props.disableHighlight,
      themeStateLock = props.themeStateLock or false,
      themeComponentDisabledStates = props.themeComponentDisabledStates,
      scaleCorners = props.scaleCorners,
      scalingAlgorithm = props.scalingAlgorithm,
    })
  else
    -- Theme module absent (minimal build) — plain no-op ThemeManager
    local noPadding = { top = 0, right = 0, bottom = 0, left = 0 }
    self._themeManager = {
      theme = nil,
      themeComponent = props.themeComponent or nil,
      disabled = props.isDisabled or props.disabled or false,
      active = props.active or false,
      themeComponentDisabledStates = {},
      scaleCorners = props.scaleCorners,
      scalingAlgorithm = props.scalingAlgorithm,
      validateThemeStateLock = function() end,
      getState = function()
        return "normal"
      end,
      setState = function() end,
      updateState = function()
        return false
      end,
      hasThemeComponent = function()
        return false
      end,
      getTheme = function()
        return nil
      end,
      getComponent = function()
        return nil
      end,
      getStateComponent = function()
        return nil
      end,
      getScrollbarComponent = function()
        return nil
      end,
      getDefaultFontFamily = function()
        return nil
      end,
      getContentAutoSizingMultiplier = function()
        return nil
      end,
      getScaledContentPadding = function()
        return noPadding
      end,
      getScaledContentPaddingForState = function()
        return noPadding
      end,
      _getScaledContentPaddingForState = function()
        return noPadding
      end,
      getStyle = function()
        return nil
      end,
    }
  end

  -- Validate themeStateLock after ThemeManager is created
  if props.themeStateLock and props.themeComponent then
    self._themeManager:validateThemeStateLock()
  end

  -- Expose theme properties for backward compatibility
  self.theme = self._themeManager.theme
  self.themeComponent = self._themeManager.themeComponent
  self.disabled = self._themeManager.disabled
  self.active = self._themeManager.active
  self._themeState = self._themeManager:getState()

  -- disableHighlight defaults to true when using themeComponent (themes handle their own visual feedback)
  -- Can be explicitly overridden by setting props.disableHighlight
  if props.disableHighlight ~= nil then
    self.disableHighlight = props.disableHighlight
  else
    self.disableHighlight = self.themeComponent ~= nil
  end

  -- Initialize contentAutoSizingMultiplier after theme is set
  -- Priority: element props > theme component > theme default
  if props.contentAutoSizingMultiplier then
    self.contentAutoSizingMultiplier = props.contentAutoSizingMultiplier
  else
    local multiplier = self._themeManager:getContentAutoSizingMultiplier()
    self.contentAutoSizingMultiplier = multiplier or { 1, 1 }
  end

  -- Expose 9-patch corner scaling properties for backward compatibility
  self.scaleCorners = self._themeManager.scaleCorners
  self.scalingAlgorithm = self._themeManager.scalingAlgorithm

  self._blurInstance = nil

  -- editable/multiline/passwordMode are bound by _applyProps (default false).
  -- Validate combinations: passwordMode disables multiline.
  if self.passwordMode and self.multiline then
    Element._ErrorHandler:warn("Element", "ELEM_006")
    self.multiline = false
  elseif self.passwordMode then
    self.multiline = false
  end

  self.textWrap = props.textWrap
  if self.textWrap == nil then
    self.textWrap = self.multiline and "word" or false
  end

  self.scrollable = props.scrollable
  if self.scrollable == nil then
    self.scrollable = self.multiline
  end
  -- autoGrow defaults to true for multiline, false for single-line
  if props.autoGrow ~= nil then
    self.autoGrow = props.autoGrow
  else
    self.autoGrow = self.multiline
  end

  self.selectParent = nil
  self.selectOption = nil
  self._selectState = nil

  if type(props.selectParent) == "table" then
    self.selectParent = props.selectParent
  end

  if type(props.selectOption) == "table" then
    self.selectOption = props.selectOption
  end

  -- TextEditor creation + immediate-mode state restore is owned by the
  -- TextEditable behavior's onAttach (task 04), which runs in _attachBehaviors
  -- at the tail of Element.new (after this helper has bound self.text and the
  -- schema-driven callback fields). This subsystem-init helper no longer	touches
  -- the TextEditor.

  -- Set parent first so it's available for size calculations
  self.parent = props.parent
end

--- Special-handler binding helper for the props phase (behavior-mode-
--- unification task 08). Formerly the Element visual-state phase. Normalizes
--- border/cornerRadius/display/text/textAlign. The branch count comment below
--- refers to the 4 textAlign parse branches (table / simple-string / compound-
--- string / invalid).
bindVisualState = function(self, props)
  local schema = Element._PropertySchema
  ------ add non-hereditary ------
  --- self drawing ---
  -- Border shape-normalization via the schema normalizer (special handler: the
  -- number-vs-table-vs-nil shape and the all-false→nil collapse are intentional).
  self.border = schema.get("border").normalizer(props.border)
  self.borderColor = props.borderColor or Element._Color.new(0, 0, 0, 1)
  self.backgroundColor = props.backgroundColor or Element._Color.new(0, 0, 0, 0)

  -- cornerRadius shape-normalization via the schema normalizer (special handler:
  -- number-vs-table-vs-nil and the all-zero→nil collapse are intentional).
  self.cornerRadius = schema.get("cornerRadius").normalizer(props.cornerRadius)

  -- display: default true; invalid (non-boolean) warns + falls back to true
  -- (non-throwing, unlike range/enum validators).
  if props.display ~= nil then
    if type(props.display) == "boolean" then
      self.display = props.display
    else
      self.display = true
      Element._ErrorHandler:warn(
        "Element",
        "ELEM_010",
        "display must be a boolean (true/false), got " .. type(props.display) .. ". Defaulting to true."
      )
    end
  else
    self.display = true
  end

  -- For editable elements, default text to empty string if not provided
  if self.editable and props.text == nil then
    self.text = ""
  else
    self.text = props.text
  end

  -- Validate and set textAlign (supports simple string, compound string, or
  -- table format). Enum membership is checked via PropertySchema validators
  -- (the valid H/V sets live there, matching the objectFit/imageRepeat pattern);
  -- compound-string parsing and warn+fallback stay here because they need
  -- ErrorHandler, which the pure-Lua schema cannot depend on.
  local textAlignMeta = schema.get("textAlign")
  local textVAlignMeta = schema.get("textAlignVertical")
  local textAlignDefault = textAlignMeta.default
  local vAlignDefault = textVAlignMeta.default

  self.textAlign = props.textAlign or textAlignDefault
  self.textAlignHorizontal = textAlignDefault
  self.textAlignVertical = vAlignDefault

  if props.textAlign ~= nil then
    if type(props.textAlign) == "table" then
      -- Table format: {horizontal = "start", vertical = "center"}
      local hAlign = props.textAlign.horizontal or textAlignDefault
      local vAlign = props.textAlign.vertical or vAlignDefault

      if not textAlignMeta.validator(hAlign) then
        hAlign = _warnTextAlign("textAlign.horizontal", "valid TextAlign value", hAlign, textAlignDefault)
      end
      if not textVAlignMeta.validator(vAlign) then
        vAlign = _warnTextAlign("textAlign.vertical", "valid TextAlignVertical value", vAlign, vAlignDefault)
      end

      self.textAlignHorizontal = hAlign
      self.textAlignVertical = vAlign
    elseif type(props.textAlign) == "string" then
      if textAlignMeta.validator(props.textAlign) then
        -- Known simple TextAlign value (backward compatible)
        self.textAlignHorizontal = props.textAlign
        self.textAlignVertical = vAlignDefault
      else
        -- Treat as compound string: "top-left" through "bottom-right"
        local parts = {}
        for part in props.textAlign:gmatch("[^-]+") do
          table.insert(parts, part)
        end

        if #parts == 2 then
          local verticalMap = { top = "start", center = "center", bottom = "end" }
          local horizontalMap = { left = "start", center = "center", right = "end" }

          local vStr = parts[1]:lower()
          local hStr = parts[2]:lower()
          local resolvedV = verticalMap[vStr]
          local resolvedH = horizontalMap[hStr]

          if resolvedV and resolvedH then
            self.textAlignHorizontal = resolvedH
            self.textAlignVertical = resolvedV
          else
            _warnTextAlign(
              "textAlign",
              "valid compound string (e.g., 'top-left', 'center-right')",
              props.textAlign,
              nil
            )
          end
        else
          _warnTextAlign("textAlign", "valid TextAlign value or compound string", props.textAlign, nil)
        end
      end
    end
  end
end

--- Phase 5 (image + renderer init) is owned by the Themed and Imageable
--- behaviors (modules/behaviors/), attached in _attachBehaviors. Themed.onAttach
--- creates the Renderer (theme/blur config); Imageable.onAttach enriches it with
--- image config + deferred image loading. There is no longer a stub Element
--- phase for this — the behavior onAttach hooks ARE the phase
--- (behavior-mode-unification task 07/08).

--- Phase 6a: viewport/scale context, LayoutEngine (defaults), unit specs table,
--- fontFamily, and textSize resolution.
function Element:_initSizingContext(props)
  --- self positioning ---
  local viewportWidth, viewportHeight = Element._Units.getViewport()

  ---- Sizing ----
  local gw, gh = love.window.getMode()
  self.prevGameSize = { width = gw, height = gh }
  self.autosizing = { width = false, height = false }

  -- Initialize LayoutEngine early with default values for auto-sizing calculations
  -- It will be re-configured later with actual layout properties
  self._layoutEngine = Element._LayoutEngine.new({
    positioning = Element._utils.enums.Positioning.RELATIVE,
    flexDirection = Element._utils.enums.FlexDirection.HORIZONTAL,
    flexWrap = Element._utils.enums.FlexWrap.NOWRAP,
    justifyContent = Element._utils.enums.JustifyContent.FLEX_START,
    alignItems = Element._utils.enums.AlignItems.STRETCH,
    alignContent = Element._utils.enums.AlignContent.STRETCH,
    gap = 0,
    gridRows = 1,
    gridColumns = 1,

    columnGap = 0,
    rowGap = 0,
  }, Element._layoutEngineDeps)
  self._layoutEngine:initialize(self)

  -- Store unit specifications for responsive behavior
  self.units = {
    width = { value = nil, unit = "px" },
    height = { value = nil, unit = "px" },
    x = { value = nil, unit = "px" },
    y = { value = nil, unit = "px" },
    textSize = { value = nil, unit = "px" },
    gap = { value = nil, unit = "px" },
    flexBasis = { value = nil, unit = "auto" },
    padding = {
      top = { value = nil, unit = "px" },
      right = { value = nil, unit = "px" },
      bottom = { value = nil, unit = "px" },
      left = { value = nil, unit = "px" },
      horizontal = { value = nil, unit = "px" }, -- Shorthand for left/right
      vertical = { value = nil, unit = "px" }, -- Shorthand for top/bottom
    },
    margin = {
      top = { value = nil, unit = "px" },
      right = { value = nil, unit = "px" },
      bottom = { value = nil, unit = "px" },
      left = { value = nil, unit = "px" },
      horizontal = { value = nil, unit = "px" }, -- Shorthand for left/right
      vertical = { value = nil, unit = "px" }, -- Shorthand for top/bottom
    },
  }

  local _, scaleY = Element._Context.getScaleFactors()

  -- minTextSize/maxTextSize/autoScaleText are bound by _applyProps (autoScaleText
  -- defaults true). They are needed before textSize processing below.

  -- Handle fontFamily (can be font name from theme or direct path to font file)
  -- Priority: explicit props.fontFamily > parent fontFamily > theme default
  if props.fontFamily then
    -- Explicitly set fontFamily takes highest priority
    self.fontFamily = props.fontFamily
  elseif self.parent and self.parent.fontFamily then
    -- Inherit from parent if parent has fontFamily set
    self.fontFamily = self.parent.fontFamily
  elseif props.themeComponent then
    -- If using themeComponent, try to get default from theme via ThemeManager
    local defaultFont = self._themeManager:getDefaultFontFamily()
    self.fontFamily = defaultFont and "default" or nil
  else
    self.fontFamily = nil
  end

  -- Handle textSize BEFORE width/height calculation (needed for auto-sizing)
  if props.textSize then
    if type(props.textSize) == "string" then
      -- Check if it's a preset first
      local presetValue, presetUnit = Element._utils.resolveTextSizePreset(props.textSize)
      local value, unit

      if presetValue then
        -- It's a preset, use the preset value and unit
        value, unit = presetValue, presetUnit
        self.units.textSize = { value = value, unit = unit }
      else
        -- Not a preset, parse normally
        value, unit = Element._Units.parse(props.textSize)
        self.units.textSize = { value = value, unit = unit }
      end

      -- Resolve textSize based on unit type
      if unit == "%" or unit == "vh" then
        -- Percentage and vh are relative to viewport height
        self.textSize = Element._Units.resolve(value, unit, viewportWidth, viewportHeight, viewportHeight)
      elseif unit == "vw" then
        -- vw is relative to viewport width
        self.textSize = Element._Units.resolve(value, unit, viewportWidth, viewportHeight, viewportWidth)
      elseif unit == "px" then
        -- Pixel units
        self.textSize = value
      else
        Element._ErrorHandler:error("Element", "ELEM_002", {
          unit = unit,
        })
      end
    else
      -- Validate pixel textSize value
      if props.textSize <= 0 then
        Element._ErrorHandler:error("Element", "ELEM_001", {
          value = tostring(props.textSize),
        })
      end

      -- Pixel textSize value
      if self.autoScaleText and Element._Context.baseScale then
        -- With base scaling: store original pixel value and scale relative to base resolution
        self.units.textSize = { value = props.textSize, unit = "px" }
        self.textSize = props.textSize * scaleY
      elseif self.autoScaleText then
        -- Without base scaling: convert to viewport units for auto-scaling
        -- Calculate what percentage of viewport height this represents
        local vhValue = (props.textSize / viewportHeight) * 100
        self.units.textSize = { value = vhValue, unit = "vh" }
        self.textSize = props.textSize -- Initial size is the specified pixel value
      else
        -- No auto-scaling: apply base scaling if set, otherwise use raw value
        self.textSize = Element._Context.baseScale and (props.textSize * scaleY) or props.textSize
        self.units.textSize = { value = props.textSize, unit = "px" }
      end
    end
  else
    -- No textSize specified - use auto-scaling default
    if self.autoScaleText and Element._Context.baseScale then
      -- With base scaling: use 12px as default and scale
      self.units.textSize = { value = 12, unit = "px" }
      self.textSize = 12 * scaleY
    elseif self.autoScaleText then
      -- Without base scaling: default to 1.5vh (1.5% of viewport height)
      self.units.textSize = { value = 1.5, unit = "vh" }
      self.textSize = (1.5 / 100) * viewportHeight
    else
      -- No auto-scaling: use 12px with optional base scaling
      self.textSize = Element._Context.baseScale and (12 * scaleY) or 12
      self.units.textSize = { value = nil, unit = "px" }
    end
  end
end

--- Phase 6b: width/height/min-max/clamp, gap, flex shorthand/grow/shrink/basis,
--- 9-patch/border-box model, and padding/margin resolution + unit storage.
function Element:_initBoxModel(props)
  local viewportWidth, viewportHeight = Element._Units.getViewport()
  local scaleX, scaleY = Element._Context.getScaleFactors()
  local _ctx = { vw = viewportWidth, vh = viewportHeight, sx = scaleX, sy = scaleY }
  -- Handle width (both w and width properties, prefer w if both exist)
  -- "auto" is treated as content-sized (same as omitting the property), per CSS semantics.
  local widthProp = props.width
  if widthProp == "auto" then
    widthProp = nil
  end
  local tempWidth -- Temporary width for padding resolution
  if widthProp then
    local parentWidth = self.parent and self.parent.width or viewportWidth
    tempWidth = _resolveUnit(self, widthProp, "width", parentWidth, _ctx, { scaleAxis = "x" })
  else
    self.autosizing.width = true
    -- Special case: if textWrap is enabled and parent exists, constrain width to parent
    -- Text wrapping requires a width constraint, so use parent's content width
    if props.textWrap and self.parent and self.parent.width then
      tempWidth = self.parent.width
      self.width = tempWidth
      self.units.width = { value = 100, unit = "%" } -- Mark as parent-constrained
      self.autosizing.width = false -- Not truly autosizing, constrained by parent
    else
      tempWidth = self:calculateAutoWidth()
      self.width = tempWidth
      self.units.width = { value = nil, unit = "auto" } -- Mark as auto-sized
    end
  end

  -- Handle height (both h and height properties, prefer h if both exist)
  -- "auto" is treated as content-sized (same as omitting the property), per CSS semantics.
  local heightProp = props.height
  if heightProp == "auto" then
    heightProp = nil
  end
  local tempHeight -- Temporary height for padding resolution
  if heightProp then
    local parentHeight = self.parent and self.parent.height or viewportHeight
    tempHeight = _resolveUnit(self, heightProp, "height", parentHeight, _ctx, { scaleAxis = "y" })
  else
    self.autosizing.height = true
    -- Calculate auto-height without padding first
    tempHeight = self:calculateAutoHeight()
    self.height = tempHeight
    self.units.height = { value = nil, unit = "auto" } -- Mark as auto-sized
  end

  local constraintParentW = self.parent and self.parent.width or viewportWidth
  local constraintParentH = self.parent and self.parent.height or viewportHeight
  _resolveUnit(self, props.minWidth, "minWidth", constraintParentW, _ctx, { scaleAxis = "x", nullable = true })
  _resolveUnit(self, props.maxWidth, "maxWidth", constraintParentW, _ctx, { scaleAxis = "x", nullable = true })
  _resolveUnit(self, props.minHeight, "minHeight", constraintParentH, _ctx, { scaleAxis = "y", nullable = true })
  _resolveUnit(self, props.maxHeight, "maxHeight", constraintParentH, _ctx, { scaleAxis = "y", nullable = true })

  if not self.autosizing.width then
    self.width = Element._utils.clamp(tempWidth, self.minWidth, self.maxWidth)
    tempWidth = self.width
  else
    self.width = Element._utils.clamp(self.width, self.minWidth, self.maxWidth)
  end
  if not self.autosizing.height then
    self.height = Element._utils.clamp(tempHeight, self.minHeight, self.maxHeight)
    tempHeight = self.height
  else
    self.height = Element._utils.clamp(self.height, self.minHeight, self.maxHeight)
  end

  --- child positioning ---
  if props.gap then
    local flexDir = props.flexDirection or Element._utils.enums.FlexDirection.HORIZONTAL
    local isHorizontalDir = flexDir == Element._utils.enums.FlexDirection.HORIZONTAL
      or flexDir == Element._utils.enums.FlexDirection.HORIZONTAL_REVERSE
    local containerSize = isHorizontalDir and self.width or self.height
    _resolveUnit(self, props.gap, "gap", containerSize, _ctx)
  else
    self.gap = 0
    self.units.gap = { value = 0, unit = "px" }
  end

  -- Handle flex shorthand property (sets flexGrow, flexShrink, flexBasis)
  if props.flex ~= nil then
    local grow, shrink, basis = Element._Units.parseFlexShorthand(props.flex)

    -- Only set individual properties if they weren't explicitly provided
    if props.flexGrow == nil then
      props.flexGrow = grow
    end
    if props.flexShrink == nil then
      props.flexShrink = shrink
    end
    if props.flexBasis == nil then
      props.flexBasis = basis
    end
  end

  -- Track whether flex-shrink was explicitly provided (directly or via flex shorthand)
  self._hasExplicitFlexShrink = props.flexShrink ~= nil

  -- Handle flexGrow property
  if props.flexGrow ~= nil then
    if type(props.flexGrow) == "number" and props.flexGrow >= 0 then
      self.flexGrow = props.flexGrow
    else
      self.flexGrow = _warnFlexInvalid(self, "FLEX_001", "flexGrow must be a non-negative number", props.flexGrow, 0)
    end
  else
    self.flexGrow = 0
  end

  -- Handle flexShrink property
  if props.flexShrink ~= nil then
    if type(props.flexShrink) == "number" and props.flexShrink >= 0 then
      self.flexShrink = props.flexShrink
    else
      self.flexShrink =
        _warnFlexInvalid(self, "FLEX_002", "flexShrink must be a non-negative number", props.flexShrink, 1)
    end
  else
    self.flexShrink = 1
  end

  -- Handle flexBasis property
  if props.flexBasis ~= nil then
    local isCalc = Element._Calc and Element._Calc.isCalc(props.flexBasis)
    if props.flexBasis == "auto" then
      self.flexBasis = "auto"
      self.units.flexBasis = { value = nil, unit = "auto" }
    elseif type(props.flexBasis) == "string" or isCalc then
      local value, unit = Element._Units.parse(props.flexBasis)
      self.units.flexBasis = { value = value, unit = unit }
      -- Don't resolve yet - LayoutEngine will handle this during layout
      self.flexBasis = props.flexBasis
    elseif type(props.flexBasis) == "number" then
      self.flexBasis = props.flexBasis
      self.units.flexBasis = { value = props.flexBasis, unit = "px" }
    else
      self.flexBasis =
        _warnFlexInvalid(self, "FLEX_003", "flexBasis must be a number, string, or 'auto'", props.flexBasis, "auto")
      self.units.flexBasis = { value = nil, unit = "auto" }
    end
  else
    self.flexBasis = "auto"
    self.units.flexBasis = { value = nil, unit = "auto" }
  end

  -- BORDER-BOX MODEL: For auto-sizing, we need to add padding to content dimensions
  -- For explicit sizing, width/height already include padding (border-box)

  -- Check if we should use 9-patch content padding for auto-sizing
  local use9PatchPadding = false
  local ninePatchContentPadding = nil
  if self._themeManager:hasThemeComponent() then
    local component = self._themeManager:getComponent()
    if component and component._ninePatchData and component._ninePatchData.contentPadding then
      -- Only use 9-patch padding if no explicit padding was provided
      if
        not props.padding
        or (
          not props.padding.top
          and not props.padding.right
          and not props.padding.bottom
          and not props.padding.left
          and not props.padding.horizontal
          and not props.padding.vertical
        )
      then
        use9PatchPadding = true
        ninePatchContentPadding = component._ninePatchData.contentPadding
      end
    end
  end

  -- First, resolve padding using temporary dimensions
  -- For auto-sized elements, this is content width; for explicit sizing, this is border-box width
  local tempPadding
  if use9PatchPadding then
    -- tempWidth/tempHeight are guaranteed numbers by _resolveUnit (which warns +
    -- clamps non-numbers) and calculateAutoWidth/Height; the prior defensive
    -- re-check duplicated that boundary validation (Task 11).

    -- Get scaled 9-patch content padding from ThemeManager
    local scaledPadding = self._themeManager:getScaledContentPadding(tempWidth, tempHeight)
    if scaledPadding then
      tempPadding = scaledPadding
    else
      -- Fallback if scaling fails
      tempPadding = {
        left = ninePatchContentPadding.left,
        top = ninePatchContentPadding.top,
        right = ninePatchContentPadding.right,
        bottom = ninePatchContentPadding.bottom,
      }
    end
  else
    tempPadding = Element._Units.resolveSpacing(props.padding, self.width, self.height)
  end

  -- Margin percentages are relative to parent's dimensions (CSS spec)
  local parentWidth = self.parent and self.parent.width or viewportWidth
  local parentHeight = self.parent and self.parent.height or viewportHeight
  self.margin = Element._Units.resolveSpacing(props.margin, parentWidth, parentHeight)

  -- For auto-sized elements, add padding to get border-box dimensions
  if self.autosizing.width then
    self._borderBoxWidth = self.width + tempPadding.left + tempPadding.right
  else
    -- For explicit sizing, width is already border-box
    self._borderBoxWidth = self.width
  end

  if self.autosizing.height then
    self._borderBoxHeight = self.height + tempPadding.top + tempPadding.bottom
  else
    -- For explicit sizing, height is already border-box
    self._borderBoxHeight = self.height
  end

  -- Set final padding
  if use9PatchPadding then
    -- Use 9-patch content padding
    self.padding = {
      left = ninePatchContentPadding.left,
      top = ninePatchContentPadding.top,
      right = ninePatchContentPadding.right,
      bottom = ninePatchContentPadding.bottom,
    }
  else
    -- Re-resolve padding based on final border-box dimensions (important for percentage padding)
    self.padding = Element._Units.resolveSpacing(props.padding, self._borderBoxWidth, self._borderBoxHeight)
  end

  -- Calculate final content dimensions by subtracting padding from border-box
  self.width = math.max(0, self._borderBoxWidth - self.padding.left - self.padding.right)
  self.height = math.max(0, self._borderBoxHeight - self.padding.top - self.padding.bottom)

  -- Re-resolve textSize presets now that width/height are set
  -- (presets like "vw" need the viewport; others are resolved during constructor)

  -- Apply min/max constraints (also scaled)
  local minSize = self.minTextSize and (Element._Context.baseScale and (self.minTextSize * scaleY) or self.minTextSize)
  local maxSize = self.maxTextSize and (Element._Context.baseScale and (self.maxTextSize * scaleY) or self.maxTextSize)

  if minSize and self.textSize < minSize then
    self.textSize = minSize
  end
  if maxSize and self.textSize > maxSize then
    self.textSize = maxSize
  end

  -- Protect against too-small text sizes (minimum 1px)
  if self.textSize < 1 then
    self.textSize = 1 -- Minimum 1px
  end

  -- Store original spacing values for proper resize handling
  -- Store spacing unit specs (padding + margin share identical structure)
  local sides = { "top", "right", "bottom", "left" }
  for _, kind in ipairs({ "padding", "margin" }) do
    local src = props[kind]
    if src then
      for _, axis in ipairs({ "horizontal", "vertical" }) do
        if src[axis] then
          if type(src[axis]) == "string" then
            local value, unit = Element._Units.parse(src[axis])
            self.units[kind][axis] = { value = value, unit = unit }
          else
            self.units[kind][axis] = { value = src[axis], unit = "px" }
          end
        end
      end
    end
    for _, side in ipairs(sides) do
      if src and src[side] then
        if type(src[side]) == "string" then
          local value, unit = Element._Units.parse(src[side])
          self.units[kind][side] = { value = value, unit = unit, explicit = true }
        else
          self.units[kind][side] = { value = src[side], unit = "px", explicit = true }
        end
      else
        self.units[kind][side] = { value = self[kind][side], unit = "px", explicit = false }
      end
    end
  end

  -- Grid properties are set later in the constructor
end

--- Phase 7: hereditary positioning (no-parent and with-parent), flex/grid
--- container properties, select-frame adopt, and LayoutEngine config update.
function Element:_initPositioning(props)
  local viewportWidth, viewportHeight = Element._Units.getViewport()
  local scaleX, scaleY = Element._Context.getScaleFactors()
  local _ctx = { vw = viewportWidth, vh = viewportHeight, sx = scaleX, sy = scaleY }
  ------ add hereditary ------
  if props.parent == nil then
    table.insert(Element._Context.topElements, self)

    -- Handle x position with units
    _resolveUnit(self, props.x, "x", viewportWidth, _ctx, { scaleAxis = "x", default = 0 })

    -- Handle y position with units
    _resolveUnit(self, props.y, "y", viewportHeight, _ctx, { scaleAxis = "y", default = 0 })

    self.z = Element._ZIndex.clamp(props.z or 0)
    self.tabIndex = props.tabIndex -- nil/0 = document order, >0 = explicit order, -1 = excluded from keyboard nav

    -- Set textColor with priority: props > theme text color > black
    if props.textColor then
      self.textColor = props.textColor
    else
      -- Try to get text color from theme via ThemeManager
      local themeToUse = self._themeManager:getTheme()
      if themeToUse and themeToUse.colors and themeToUse.colors.text then
        self.textColor = themeToUse.colors.text
      else
        -- Fallback to black
        self.textColor = Element._Color.new(0, 0, 0, 1)
      end
    end

    -- Track if positioning was explicitly set
    if props.positioning then
      Element._utils.validateEnum(props.positioning, Element._utils.enums.Positioning, "positioning")
      self.positioning = props.positioning
      self._originalPositioning = props.positioning
      self._explicitlyAbsolute = (props.positioning == Element._utils.enums.Positioning.ABSOLUTE)
    else
      self.positioning = Element._utils.enums.Positioning.RELATIVE
      self._originalPositioning = nil -- No explicit positioning
      self._explicitlyAbsolute = false
    end

    -- Handle positioning properties for elements without parent
    -- Warn if CSS positioning properties are supplied but will be ignored.
    -- Relative elements honor the offsets as visual deltas (see
    -- _applyRelativeOffsets); absolute elements use applyPositioningOffsets.
    -- Only flex-participating children (positioning coerced to ABSOLUTE but not
    -- explicitly absolute) actually drop the offsets and warrant the warning.
    if
      (props.top or props.bottom or props.left or props.right)
      and not self._explicitlyAbsolute
      and self.positioning ~= Element._utils.enums.Positioning.RELATIVE
    then
      _warnCssPositioningWithoutAbsolute(self, props)
    end

    -- Handle top/right/bottom/left positioning with units
    if props.top then
      _resolveUnit(self, props.top, "top", viewportHeight, _ctx)
    end
    if props.right then
      _resolveUnit(self, props.right, "right", viewportWidth, _ctx)
    end
    if props.bottom then
      _resolveUnit(self, props.bottom, "bottom", viewportHeight, _ctx)
    end
    if props.left then
      _resolveUnit(self, props.left, "left", viewportWidth, _ctx)
    end

    -- position: relative offsets are applied as visual deltas in
    -- LayoutEngine:layoutChildren (after the flex flow places children), so
    -- they survive the addChild -> layoutChildren re-entry here.
  else
    -- Set positioning first and track if explicitly set
    self._originalPositioning = props.positioning -- Track original intent
    if props.positioning == Element._utils.enums.Positioning.ABSOLUTE then
      self.positioning = Element._utils.enums.Positioning.ABSOLUTE
      self._explicitlyAbsolute = true -- Explicitly set to absolute by user
    elseif props.positioning == Element._utils.enums.Positioning.FLEX then
      self.positioning = Element._utils.enums.Positioning.FLEX
      self._explicitlyAbsolute = false
    elseif props.positioning == Element._utils.enums.Positioning.GRID then
      self.positioning = Element._utils.enums.Positioning.GRID
      self._explicitlyAbsolute = false
    else
      -- Default: children in flex/grid containers participate in parent's layout
      -- children in relative/absolute containers default to relative
      if
        self.parent.positioning == Element._utils.enums.Positioning.FLEX
        or self.parent.positioning == Element._utils.enums.Positioning.GRID
      then
        self.positioning = Element._utils.enums.Positioning.ABSOLUTE -- They are positioned BY flex/grid, not AS flex/grid
        self._explicitlyAbsolute = false -- Participate in parent's layout
      else
        self.positioning = Element._utils.enums.Positioning.RELATIVE
        self._explicitlyAbsolute = false -- Default for relative/absolute containers
      end
    end

    -- Set initial position
    local parentPadding = self.parent.padding or { left = 0, top = 0 }
    if self.positioning == Element._utils.enums.Positioning.ABSOLUTE then
      -- Absolute positioning is relative to parent's content area (padding box)
      local baseX = self.parent.x + parentPadding.left
      local baseY = self.parent.y + parentPadding.top

      -- Handle x/y position with units
      _resolveUnit(self, props.x, "x", self.parent.width, _ctx, { scaleAxis = "x", offset = baseX, default = 0 })
      _resolveUnit(self, props.y, "y", self.parent.height, _ctx, { scaleAxis = "y", offset = baseY, default = 0 })

      self.z = Element._ZIndex.clamp(props.z or 0)
      self.tabIndex = props.tabIndex
    else
      -- Children in flex containers start at parent position but will be repositioned by layoutChildren
      -- Children in absolute/relative containers start at parent's content area (accounting for padding)
      local baseX = self.parent.x + parentPadding.left
      local baseY = self.parent.y + parentPadding.top

      -- Warn if explicit x/y is set on a child that will be positioned by flex layout
      -- This position will be overridden unless the child has positioning="absolute"
      local parentWillUseFlex = self.parent.positioning ~= "grid"
      local childIsRelative = self.positioning ~= "absolute" or not self._explicitlyAbsolute
      if parentWillUseFlex and childIsRelative and (props.x or props.y) then
        Element._ErrorHandler:warn("Element", "LAY_008", {
          element = self.id or "unnamed",
          parent = self.parent.id or "unnamed",
          properties = (props.x and props.y) and "x, y" or (props.x and "x" or "y"),
        })
      end

      _resolveUnit(self, props.x, "x", self.parent.width, _ctx, { scaleAxis = "x", offset = baseX, default = 0 })
      _resolveUnit(self, props.y, "y", self.parent.height, _ctx, { scaleAxis = "y", offset = baseY, default = 0 })

      self.z = Element._ZIndex.clamp(props.z or self.parent.z or 0)
      self.tabIndex = props.tabIndex
    end

    if props.textColor then
      self.textColor = props.textColor
    elseif self.parent.textColor then
      self.textColor = self.parent.textColor
    else
      local themeToUse = self._themeManager:getTheme()
      if themeToUse and themeToUse.colors and themeToUse.colors.text then
        self.textColor = themeToUse.colors.text
      else
        -- Fallback to black
        self.textColor = Element._Color.new(0, 0, 0, 1)
      end
    end

    -- Handle positioning properties BEFORE adding to parent (so they're available during layout)
    -- Warn if CSS positioning properties are supplied but will be ignored.
    -- Relative elements honor the offsets as visual deltas (see
    -- _applyRelativeOffsets); absolute elements use applyPositioningOffsets.
    -- Only flex-participating children (positioning coerced to ABSOLUTE but not
    -- explicitly absolute) actually drop the offsets and warrant the warning.
    if
      (props.top or props.bottom or props.left or props.right)
      and not self._explicitlyAbsolute
      and self.positioning ~= Element._utils.enums.Positioning.RELATIVE
    then
      _warnCssPositioningWithoutAbsolute(self, props)
    end

    -- Handle top/right/bottom/left positioning with units
    if props.top then
      _resolveUnit(self, props.top, "top", viewportHeight, _ctx)
    end
    if props.right then
      _resolveUnit(self, props.right, "right", viewportWidth, _ctx)
    end
    if props.bottom then
      _resolveUnit(self, props.bottom, "bottom", viewportHeight, _ctx)
    end
    if props.left then
      _resolveUnit(self, props.left, "left", viewportWidth, _ctx)
    end

    -- position: relative offsets are applied as visual deltas in
    -- LayoutEngine:layoutChildren (after the flex flow places children), so
    -- they survive the addChild -> layoutChildren re-entry here.

    props.parent:addChild(self)
  end

  if self.positioning == Element._utils.enums.Positioning.FLEX then
    -- Validate enum properties
    if props.flexDirection then
      Element._utils.validateEnum(props.flexDirection, Element._utils.enums.FlexDirection, "flexDirection")
    end
    if props.flexWrap then
      Element._utils.validateEnum(props.flexWrap, Element._utils.enums.FlexWrap, "flexWrap")
    end
    if props.justifyContent then
      Element._utils.validateEnum(props.justifyContent, Element._utils.enums.JustifyContent, "justifyContent")
    end
    if props.alignItems then
      Element._utils.validateEnum(props.alignItems, Element._utils.enums.AlignItems, "alignItems")
    end
    if props.alignContent then
      Element._utils.validateEnum(props.alignContent, Element._utils.enums.AlignContent, "alignContent")
    end
    if props.justifySelf then
      Element._utils.validateEnum(props.justifySelf, Element._utils.enums.JustifySelf, "justifySelf")
    end

    -- Warn if grid properties are set with flex positioning
    if props.gridRows or props.gridColumns then
      Element._ErrorHandler:warn("Element", "LAY_010", {
        element = self.id or "unnamed",
        positioning = "flex",
        properties = "gridRows/gridColumns",
      })
    end

    self.flexDirection = props.flexDirection or Element._utils.enums.FlexDirection.HORIZONTAL
    self.flexWrap = props.flexWrap or Element._utils.enums.FlexWrap.NOWRAP
    self.justifyContent = props.justifyContent or Element._utils.enums.JustifyContent.FLEX_START
    self.alignItems = props.alignItems or Element._utils.enums.AlignItems.STRETCH
    self.alignContent = props.alignContent or Element._utils.enums.AlignContent.STRETCH
    self.justifySelf = props.justifySelf or Element._utils.enums.JustifySelf.AUTO
  end

  -- Grid container properties
  if self.positioning == Element._utils.enums.Positioning.GRID then
    -- Warn if flex properties are set with grid positioning
    if props.flexDirection or props.flexWrap or props.justifyContent then
      Element._ErrorHandler:warn("Element", "LAY_009", {
        element = self.id or "unnamed",
        positioning = "grid",
        properties = "flexDirection/flexWrap/justifyContent",
      })
    end

    self.gridRows = props.gridRows
    self.gridColumns = props.gridColumns
    self.alignItems = props.alignItems or Element._utils.enums.AlignItems.STRETCH

    -- Handle columnGap and rowGap
    _resolveUnit(self, props.columnGap, "columnGap", self.width, _ctx, { default = 0 })
    _resolveUnit(self, props.rowGap, "rowGap", self.height, _ctx, { default = 0 })
  end

  -- alignSelf is bound by _applyProps (default "auto").

  -- Update the LayoutEngine with actual layout properties
  -- (it was initialized early with defaults for auto-sizing calculations)
  self._layoutEngine.positioning = self.positioning
  if self.flexDirection then
    self._layoutEngine.flexDirection = self.flexDirection
  end
  if self.flexWrap then
    self._layoutEngine.flexWrap = self.flexWrap
  end
  if self.justifyContent then
    self._layoutEngine.justifyContent = self.justifyContent
  end
  if self.alignItems then
    self._layoutEngine.alignItems = self.alignItems
  end
  if self.alignContent then
    self._layoutEngine.alignContent = self.alignContent
  end
  if self.gap then
    self._layoutEngine.gap = self.gap
  end
  if self.gridRows then
    self._layoutEngine.gridRows = self.gridRows
  end
  if self.gridColumns then
    self._layoutEngine.gridColumns = self.gridColumns
  end

  if self.columnGap then
    self._layoutEngine.columnGap = self.columnGap
  end
  if self.rowGap then
    self._layoutEngine.rowGap = self.rowGap
  end

  -- transform is bound by _applyProps; transition is bound by _applyProps (default {}).
  -- (Previously set inline here; both are now registry-driven.)
end

--- Phase 8 (ScrollManager instantiation + immediate-mode scrollbar restore) is
--- owned by the Scrollable behavior (modules/behaviors/Scrollable.lua), attached
--- in _attachBehaviors. There is no longer an Element phase for this — the
--- behavior onAttach hook IS the phase (behavior-mode-unification task 03/08).
--- `overflow` / `overflowX` / `overflowY` are bound onto the element as plain
--- fields by bindThemeAndFields/`_applyProps` so that `Element:addChild`'s
--- scroll-container auto-size guard sees them during declarative-children
--- processing in _finalizeConstruction (which runs before _attachBehaviors);
--- Scrollable.onAttach then overwrites them with the ScrollManager's normalized
--- values, matching the legacy field-exposure order.

--- Phase 9: immediate-mode registration, dirty flags, debug draw color,
--- declarative children tree, onCreate callback, and constructed flag.
function Element:_finalizeConstruction(props)
  -- Register element in z-index tracking. registerElement is a mode-aware
  -- no-op outside immediate mode, so no mode check is needed here
  -- (behavior-mode-unification task 11).
  Element._Context.registerElement(self)

  -- Performance optimization: dirty flags for layout tracking
  -- These flags help skip unnecessary layout recalculations
  self._dirty = false -- Element properties have changed, needs layout
  self._childrenDirty = false -- Children have changed, needs layout

  -- Debug draw: assign a deterministic color for element boundary visualization
  -- Uses a hash of the element ID to produce a stable hue, so colors don't flash each frame
  local function hashStringToHue(str)
    local hash = 5381
    for i = 1, #str do
      hash = ((hash * 33) + string.byte(str, i)) % 360
    end
    return hash
  end
  local hue = hashStringToHue(self.id or tostring(self))
  local function hslToRgb(h)
    local s, l = 0.9, 0.55
    local c = (1 - math.abs(2 * l - 1)) * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = l - c / 2
    local r, g, b
    if h < 60 then
      r, g, b = c, x, 0
    elseif h < 120 then
      r, g, b = x, c, 0
    elseif h < 180 then
      r, g, b = 0, c, x
    elseif h < 240 then
      r, g, b = 0, x, c
    elseif h < 300 then
      r, g, b = x, 0, c
    else
      r, g, b = c, 0, x
    end
    return r + m, g + m, b + m
  end
  local dr, dg, db = hslToRgb(hue)
  self._debugColor = { dr, dg, db }

  -- Process declarative children prop: build child tree from property tables
  -- Placed after all self properties are initialized so children can safely access parent state
  if props.children then
    if type(props.children) ~= "table" then
      _warnChildrenInvalid(self, "ELEM_010", "children must be a table array", props.children)
    else
      for i = 1, #props.children do
        local childProps = props.children[i]
        if childProps == nil then
          _warnChildrenInvalid(self, "ELEM_011", "nil entry in children array, skipping", nil)
        elseif type(childProps) ~= "table" then
          _warnChildrenInvalid(self, "ELEM_012", "non-table entry in children array, skipping", childProps)
        else
          local childCopy = {}
          for k, v in pairs(childProps) do
            childCopy[k] = v
          end
          childCopy.parent = self
          local child = Element.new(childCopy)

          -- Set up state management for declarative children so mutations
          -- made in event callbacks persist across frames. Mode-aware via
          -- StateManager.isImmediateMode (behavior-mode-unification task 11):
          -- this whole block is immediate-mode-only frame bookkeeping.
          if Element._StateManager.isImmediateMode() then
            if not child.id or child.id == "" then
              child.id = Element._StateManager.generateID(childCopy, self)
            end
            local childState = Element._StateManager.getState(child.id, {})
            Element._StateManager.markStateUsed(child.id)
            child:restoreState(childState)
            child._stateId = child.id

            -- Restore theme state from event handler state
            if child.themeComponent then
              local eventState = childState.eventHandler or {}
              if child.disabled or eventState.disabled then
                child._themeState = "disabled"
              elseif child.active or eventState.active then
                child._themeState = "active"
              elseif eventState._pressed and next(eventState._pressed) then
                child._themeState = "pressed"
              elseif eventState._hovered then
                child._themeState = "hover"
              else
                child._themeState = "normal"
              end
            end

            -- Add to current frame elements for saveState tracking
            if Element._Context._currentFrameElements then
              table.insert(Element._Context._currentFrameElements, child)
            end
          end
        end
      end
    end
  end

  -- Fire onCreate callback if provided
  if self.onCreate then
    if self.onCreateDeferred then
      local FlexLove = package.loaded["FlexLove"] or package.loaded["libs.FlexLove"]
      if FlexLove and FlexLove.deferCallback then
        FlexLove.deferCallback(function()
          self.onCreate(self, props)
        end)
      else
        self.onCreate(self, props)
      end
    else
      self.onCreate(self, props)
    end
  end

  -- Mark element as fully constructed.
  -- NOTE: no longer gates an __newindex dimension warning (removed — see comment
  -- at top of file). Retained lazily in case future write-interception is added.
  self._constructed = true
end

--- Retrieve the element's screen-space rectangle for collision detection and positioning calculations
--- Use this for custom layout logic, tooltips, or detecting overlaps between elements
---@return { x:number, y:number, width:number, height:number }
function Element:getBounds()
  return { x = self.x, y = self.y, width = self:getBorderBoxWidth(), height = self:getBorderBoxHeight() }
end

--- Test if a screen coordinate falls within the element's clickable area
--- Use this for custom hit detection or determining which element the mouse is over
--- @param x number
--- @param y number
--- @return boolean
function Element:contains(x, y)
  local bounds = self:getBounds()
  return bounds.x <= x and bounds.y <= y and bounds.x + bounds.width >= x and bounds.y + bounds.height >= y
end

--- Get the element's total width including padding for layout calculations
--- Use this when you need the full visual width rather than just content width
---@return number
function Element:getBorderBoxWidth()
  return self._borderBoxWidth or (self.width + self.padding.left + self.padding.right)
end

--- Get the element's total height including padding for layout calculations
--- Use this when you need the full visual height rather than just content height
---@return number
function Element:getBorderBoxHeight()
  return self._borderBoxHeight or (self.height + self.padding.top + self.padding.bottom)
end

--- Get computed box dimensions (content area position and size)
--- Returns the position and size of the content area (inside padding)
---@return {x: number, y: number, width: number, height: number}
function Element:getComputedBox()
  return {
    x = self.x + self.padding.left,
    y = self.y + self.padding.top,
    width = self.width,
    height = self.height,
  }
end

--- Mark this element and its ancestors as dirty, requiring layout recalculation
--- Call this when element properties change that affect layout
function Element:invalidateLayout()
  self._dirty = true

  -- Invalidate dimension caches
  self._borderBoxWidthCache = nil
  self._borderBoxHeightCache = nil

  -- Mark parent as having dirty children
  if self.parent then
    self.parent._childrenDirty = true
    -- Propagate up the tree (parents need to know their descendants changed)
    local ancestor = self.parent
    while ancestor do
      ancestor._childrenDirty = true
      ancestor = ancestor.parent
    end
  end
end

-- Scroll / scrollbar methods (_syncScrollManagerState, _detectOverflow, setScrollPosition,
-- _calculateScrollbarDimensions, _getScrollbarAtPosition, _handleScrollbarPress/Drag/Release,
-- _handleWheelScroll, getScrollPosition, getMaxScroll, getScrollPercentage, hasOverflow,
-- getContentSize, scrollBy, scrollToTop) are bound to ScrollManager in Element.init. ScrollManager
-- owns all scrollbar interaction logic; Element retains only 1-line delegates (see ScrollManager.lua).

--- Mark a method for deferred retry during the update phase.
--- Methods that depend on layout calculations (e.g., scroll, sizing)
--- can defer themselves when preconditions aren't met. They'll be
--- retried automatically each frame in update() until they succeed.
---@param methodName string The method name to retry
---@param ... any? Arguments to forward on retry
function Element:_deferMethod(methodName, ...)
  if type(self[methodName]) ~= "function" then
    Element._ErrorHandler:warn("Element", "CORE_005", {
      element = self.id,
      method = tostring(methodName),
    })
    return
  end

  if #self._deferredMethods >= MAX_DEFERRED_METHODS then
    Element._ErrorHandler:warn("Element", "CORE_004", {
      element = self.id,
      method = tostring(methodName),
      retryCount = MAX_DEFERRED_METHODS,
    })
    return
  end

  local argc = select("#", ...)
  local args = {}
  for i = 1, argc do
    local val = select(i, ...)
    args[i] = val == nil and _DEFERRED_NIL or val
  end
  table.insert(self._deferredMethods, {
    methodName = methodName,
    args = args,
    argc = argc,
    retryCount = 0,
  })
end

-- Deferred image loading is owned by the Imageable behavior
-- (modules/behaviors/Imageable.lua). Imageable.onAttach installs an instance
-- closure on `element._loadImage` and defers it via _deferMethod; the deferred-
-- method dispatcher (which resolves `self[methodName]`) invokes that closure.
-- Element no longer owns the load logic itself and has zero image-branch logic.
-- (behavior-mode-unification task 07)

-- scrollToBottom / scrollToLeft / scrollToRight are bound to ScrollManager in Element.init.

--- Get the current state's scaled content padding
--- Returns the contentPadding for the current theme state, scaled to the element's size
---@return table|nil -- {left, top, right, bottom} or nil if no contentPadding
function Element:getScaledContentPadding()
  local borderBoxWidth = self._borderBoxWidth or (self.width + self.padding.left + self.padding.right)
  local borderBoxHeight = self._borderBoxHeight or (self.height + self.padding.top + self.padding.bottom)
  return self._themeManager:getScaledContentPadding(borderBoxWidth, borderBoxHeight)
end

--- Get draw-time content offset from state-specific theme padding changes
---@return number offsetX, number offsetY
function Element:getContentStateOffset()
  local borderBoxWidth = self._borderBoxWidth or (self.width + self.padding.left + self.padding.right)
  local borderBoxHeight = self._borderBoxHeight or (self.height + self.padding.top + self.padding.bottom)

  local currentPadding = self:getScaledContentPadding()
  local basePadding = self._themeManager:_getScaledContentPaddingForState("normal", borderBoxWidth, borderBoxHeight)

  if not currentPadding or not basePadding then
    return 0, 0
  end

  local offsetX = currentPadding.left - basePadding.left
  local offsetY = currentPadding.top - basePadding.top

  if math.abs(offsetX) < 0.001 then
    offsetX = 0
  end
  if math.abs(offsetY) < 0.001 then
    offsetY = 0
  end

  return offsetX, offsetY
end

--- Get or create blur instance for this element
---@return table? -- Blur instance or nil if no blur configured
function Element:getBlurInstance()
  -- Determine quality from contentBlur or backdropBlur
  local quality = 5 -- Default quality
  if self.contentBlur and self.contentBlur.quality then
    quality = self.contentBlur.quality
  elseif self.backdropBlur and self.backdropBlur.quality then
    quality = self.backdropBlur.quality
  end

  -- Create blur instance if needed
  if not self._blurInstance or self._blurInstance.quality ~= quality then
    self._blurInstance = Element._Blur.new({ quality = quality })
  end

  return self._blurInstance
end

--- Get available content width for children (accounting for 9-patch content padding)
--- This is the width that children should use when calculating percentage widths
---@return number
function Element:getAvailableContentWidth()
  local availableWidth = self.width

  local scaledContentPadding = self:getScaledContentPadding()
  if scaledContentPadding then
    -- Check if the element is using the scaled 9-patch contentPadding as its padding
    -- Allow small floating point differences (within 0.1 pixels)
    local usingContentPaddingAsPadding = (
      math.abs(self.padding.left - scaledContentPadding.left) < 0.1
      and math.abs(self.padding.right - scaledContentPadding.right) < 0.1
    )

    if not usingContentPaddingAsPadding then
      -- Element has explicit padding different from contentPadding
      -- Subtract scaled contentPadding to get the area children should use
      availableWidth = availableWidth - scaledContentPadding.left - scaledContentPadding.right
    end
  end

  return math.max(0, availableWidth)
end

--- Get available content height for children (accounting for 9-patch content padding)
--- This is the height that children should use when calculating percentage heights
---@return number
function Element:getAvailableContentHeight()
  local availableHeight = self.height

  local scaledContentPadding = self:getScaledContentPadding()
  if scaledContentPadding then
    -- Check if the element is using the scaled 9-patch contentPadding as its padding
    -- Allow small floating point differences (within 0.1 pixels)
    local usingContentPaddingAsPadding = (
      math.abs(self.padding.top - scaledContentPadding.top) < 0.1
      and math.abs(self.padding.bottom - scaledContentPadding.bottom) < 0.1
    )

    if not usingContentPaddingAsPadding then
      -- Element has explicit padding different from contentPadding
      -- Subtract scaled contentPadding to get the area children should use
      availableHeight = availableHeight - scaledContentPadding.top - scaledContentPadding.bottom
    end
  end

  return math.max(0, availableHeight)
end

function Element:openSelect()
  Element._Select.openSelect(self)
end

function Element:closeSelect()
  Element._Select.closeSelect(self)
end

function Element:toggleSelect()
  Element._Select.toggleSelect(self)
end

---@return boolean
function Element:isSelectOpen()
  return Element._Select.isSelectOpen(self)
end

---@return any
function Element:getSelectValue()
  return Element._Select.getSelectValue(self)
end

---@return string?
function Element:getSelectLabel()
  return Element._Select.getSelectLabel(self)
end

---@return boolean
function Element:isSelectedSelectOption()
  return Element._Select.isSelectedOption(self)
end

---@param value any
---@param optionElement Element?
function Element:setSelectValue(value, optionElement)
  Element._Select.setSelectValue(self, value, optionElement)
end

function Element:_handleSelectRelease()
  Element._Select.handleRelease(self)
end

--- Dynamically insert a child element into the hierarchy for runtime UI construction
--- Use this to build interfaces procedurally or add elements based on application state
---@param child Element
function Element:addChild(child)
  if self._managedSelectFrame and child.selectOption and self._managedSelectOwner then
    child._selectParentHint = self._managedSelectOwner
  end

  child.parent = self

  -- Re-evaluate positioning now that we have a parent
  -- If child was created without explicit positioning, inherit from parent
  if child._originalPositioning == nil then
    -- No explicit positioning was set during construction
    if
      self.positioning == Element._utils.enums.Positioning.FLEX
      or self.positioning == Element._utils.enums.Positioning.GRID
    then
      child.positioning = Element._utils.enums.Positioning.ABSOLUTE -- They are positioned BY flex/grid, not AS flex/grid
      child._explicitlyAbsolute = false -- Participate in parent's layout
    else
      child.positioning = Element._utils.enums.Positioning.RELATIVE
      child._explicitlyAbsolute = false -- Default for relative/absolute containers
    end
  end
  -- If child._originalPositioning is set, it means explicit positioning was provided
  -- and _explicitlyAbsolute was already set correctly during construction

  table.insert(self.children, child)
  Element._Select.registerWithSelectParent(child)

  -- Mark parent as having dirty children to trigger layout recalculation
  self._childrenDirty = true

  -- Only recalculate auto-sizing if the child participates in layout
  -- (CSS: absolutely positioned children don't affect parent auto-sizing)
  if not child._explicitlyAbsolute then
    local sizeChanged = false

    local overflowX = self.overflowX or self.overflow
    local overflowY = self.overflowY or self.overflow
    local isScrollContainer = overflowX == "scroll"
      or overflowX == "auto"
      or overflowY == "scroll"
      or overflowY == "auto"

    if self.autosizing.height and not isScrollContainer then
      local oldHeight = self.height
      local contentHeight = self:calculateAutoHeight()
      -- BORDER-BOX MODEL: Add padding to get border-box, then subtract to get content
      self._borderBoxHeight = contentHeight + self.padding.top + self.padding.bottom
      self.height = contentHeight
      if oldHeight ~= self.height then
        sizeChanged = true
      end
    end
    if self.autosizing.width and not isScrollContainer then
      local oldWidth = self.width
      local contentWidth = self:calculateAutoWidth()
      -- BORDER-BOX MODEL: Add padding to get border-box, then subtract to get content
      self._borderBoxWidth = contentWidth + self.padding.left + self.padding.right
      self.width = contentWidth
      if oldWidth ~= self.width then
        sizeChanged = true
      end
    end

    -- Propagate size change up the tree
    if sizeChanged and self.parent and (self.parent.autosizing.width or self.parent.autosizing.height) then
      -- Trigger parent to recalculate its size by re-adding this child's contribution
      -- This ensures grandparents are notified of size changes
      if self.parent.autosizing.height then
        local contentHeight = self.parent:calculateAutoHeight()
        self.parent._borderBoxHeight = contentHeight + self.parent.padding.top + self.parent.padding.bottom
        self.parent.height = contentHeight
      end
      if self.parent.autosizing.width then
        local contentWidth = self.parent:calculateAutoWidth()
        self.parent._borderBoxWidth = contentWidth + self.parent.padding.left + self.parent.padding.right
        self.parent.width = contentWidth
      end
    end
  end

  -- Layout is deferred to FlexLove.endFrame in immediate mode (all elements
  -- for the frame must exist before layout). shouldLayout() encapsulates the
  -- mode check (behavior-mode-unification task 11).
  if Element._StateManager.shouldLayout() then
    self:layoutChildren()
  end

  if
    self._selectState
    and self._selectState.selectFrame
    and child.selectOption
    and child ~= self._selectState.selectFrame
  then
    Element._Select.attachOptionToManagedFrame(child)
  end
end

--- Remove a child element from the hierarchy to dynamically update UIs
--- Use this to delete elements when they're no longer needed or respond to user actions
---@param child Element
function Element:removeChild(child)
  for i, c in ipairs(self.children) do
    if c == child then
      Element._Select.handleChildRemoved(self, child)
      Element._Select.unregisterFromSelectParent(child)
      table.remove(self.children, i)
      child.parent = nil

      -- Recalculate auto-sizing if needed
      if self.autosizing.width or self.autosizing.height then
        if self.autosizing.width then
          local contentWidth = self:calculateAutoWidth()
          self._borderBoxWidth = contentWidth + self.padding.left + self.padding.right
          self.width = contentWidth
        end
        if self.autosizing.height then
          local contentHeight = self:calculateAutoHeight()
          self._borderBoxHeight = contentHeight + self.padding.top + self.padding.bottom
          self.height = contentHeight
        end
      end

      -- Re-layout children after removal (deferred in immediate mode).
      if Element._StateManager.shouldLayout() then
        self:layoutChildren()
      end

      break
    end
  end
end

--- Reparent this element to a new parent, properly detaching from the current location
--- and inserting into the new parent's children hierarchy with correct layout and alignment.
--- If newParent is nil, the element becomes a top-level element.
--- Works whether the element was originally created with or without a parent.
---@param newParent Element?
function Element:setParent(newParent)
  local expectedManagedSelectParent = nil
  if self._managedSelectFrame and self._managedSelectOwner then
    expectedManagedSelectParent = self._managedSelectOwner
    if self._managedSelectOwner._selectState and self._managedSelectOwner._selectState.selectAnchor then
      expectedManagedSelectParent = self._managedSelectOwner._selectState.selectAnchor
    end
  end

  if self._managedSelectFrame and self._managedSelectOwner and newParent ~= expectedManagedSelectParent then
    Element._Select.warnSelectFrame(self._managedSelectOwner, "ELEM_009", {
      element = self._managedSelectOwner.id,
      frame = self.id,
      expectedParent = expectedManagedSelectParent and expectedManagedSelectParent.id or nil,
      actualParent = newParent and newParent.id or nil,
    })
  end

  if self.parent == newParent then
    return -- Already at this parent, no-op
  end

  -- Remove from current location
  if self.parent then
    -- removeChild sets child.parent = nil and recalculates parent layout
    self.parent:removeChild(self)
  else
    -- Remove from topElements (element was created without a parent)
    for i, elem in ipairs(Element._Context.topElements) do
      if elem == self then
        table.remove(Element._Context.topElements, i)
        break
      end
    end
    self.parent = nil
  end

  if newParent then
    -- addChild handles: setting self.parent, re-evaluating positioning,
    -- inserting into children, marking dirty, auto-sizing, and layoutChildren
    newParent:addChild(self)
  else
    -- Become a top-level element
    self.parent = nil
    self.x = self.x or 0
    self.y = self.y or 0
    self.z = Element._ZIndex.clamp(self.z or 0)
    table.insert(Element._Context.topElements, self)
  end
end

--- Delete all child elements at once for resetting containers or clearing lists
--- Use this to efficiently empty containers when rebuilding UI from scratch
function Element:clearChildren()
  -- Clear parent references for all children
  for _, child in ipairs(self.children) do
    Element._Select.unregisterFromSelectParent(child)
    child.parent = nil
  end

  -- Clear the children table
  self.children = {}

  -- Recalculate auto-sizing if needed
  if self.autosizing.width or self.autosizing.height then
    if self.autosizing.width then
      local contentWidth = self:calculateAutoWidth()
      self._borderBoxWidth = contentWidth + self.padding.left + self.padding.right
      self.width = contentWidth
    end
    if self.autosizing.height then
      local contentHeight = self:calculateAutoHeight()
      self._borderBoxHeight = contentHeight + self.padding.top + self.padding.bottom
      self.height = contentHeight
    end
  end

  -- Re-layout (though there are no children now; deferred in immediate mode).
  if Element._StateManager.shouldLayout() then
    self:layoutChildren()
  end
end

--- Get the number of children this element has
---@return number
function Element:getChildCount()
  return #self.children
end

--- Apply positioning offsets (top, right, bottom, left) to an element
-- @param element The element to apply offsets to
function Element:applyPositioningOffsets(element)
  -- Delegate to LayoutEngine
  self._layoutEngine:applyPositioningOffsets(element)
end

function Element:layoutChildren()
  -- Check performance warnings (only on root elements to avoid spam)
  if not self.parent then
    self:_checkPerformanceWarnings()
  end

  -- Catch stale bare dimension writes that bypassed setProperty (e.g.
  -- `element.width = "42%"` stores a raw string). Lua __newindex cannot intercept
  -- these at write time (the keys exist post-construction), so we validate lazily
  -- here, once per element per property, only when a reflow is already pending.
  if self._dirty then
    self:_checkDimensionTypes()
  end

  -- Delegate layout to LayoutEngine
  self._layoutEngine:layoutChildren()
end

--- Warn once per stale dimension property that holds a non-number value, which
--- indicates a bare write (e.g. `element.width = "42%"`) bypassed setProperty.
--- Bare dimension writes neither resolve unit strings nor invalidate layout;
--- the element renders with the wrong size until :setProperty() is used.
function Element:_checkDimensionTypes()
  if not self._dimWarned then
    self._dimWarned = {}
  end
  for _, prop in ipairs({ "width", "height", "x", "y" }) do
    local v = self[prop]
    if v ~= nil and type(v) ~= "number" then
      if not self._dimWarned[prop] then
        self._dimWarned[prop] = true
        Element._ErrorHandler:warn("Element", "ELM_001", {
          property = prop,
          message = string.format(
            'element.%s holds a non-number value (%s); a bare write bypassed setProperty and was not resolved to pixels. Use element:setProperty("%s", value) instead.',
            prop,
            type(v),
            prop
          ),
        })
      end
    end
  end
end

--- Warn about percentage sizing with auto-sizing parent
---@param child Element
---@param axis string "width" or "height"
function Element:_warnIfPercentageWithAutoSizing(child, axis)
  if self._managedSelectFrame then
    return
  end
  Element._ErrorHandler:warn("LayoutEngine", "LAY_004", {
    child = child.id or "unnamed",
    issue = "percentage " .. axis .. " with parent auto-sizing",
  })
end

--- Whether element needs cross-axis percentage dimension syncing
--- Managed select frames sync percentage children with container dimensions
---@return boolean
function Element:_shouldSyncPercentageDimensions()
  return self._managedSelectFrame == true
end

--- Adjust cross-axis percentage width for managed select minimum
---@param child Element
---@param newBorderBoxWidth number
---@return number
function Element:_adjustCrossAxisPercentageWidth(child, newBorderBoxWidth)
  if self._managedSelectFrame and self.autosizing and self.autosizing.width then
    local intrinsicBorderBoxWidth = child:calculateAutoWidth() + child.padding.left + child.padding.right
    return math.max(newBorderBoxWidth, intrinsicBorderBoxWidth)
  end
  return newBorderBoxWidth
end

--- Layout-path delegate: adjust child border-box width for a managed-select frame.
--- Owned by Select; routed through here so the layout path stays free of dropdown details.
---@param child Element
---@param childBorderBoxWidth number
---@return number
function Element:_adjustAutoWidthChildBorderBoxForManagedSelect(child, childBorderBoxWidth)
  return Element._Select.adjustAutoWidthChild(self, child, childBorderBoxWidth)
end

--- Destroy element and its children
function Element:destroy()
  -- Remove from global elements list
  for i, win in ipairs(Element._Context.topElements) do
    if win == self then
      table.remove(Element._Context.topElements, i)
      break
    end
  end

  if self.parent then
    for i, child in ipairs(self.parent.children) do
      if child == self then
        Element._Select.unregisterFromSelectParent(self)
        table.remove(self.parent.children, i)
        break
      end
    end
    self.parent = nil
  end

  -- Destroy all children
  for _, child in ipairs(self.children) do
    child:destroy()
  end

  -- Clear children table
  self.children = {}

  -- Clear parent reference
  if self.parent then
    self.parent = nil
  end

  -- Clear animation reference
  self.animation = nil

  -- Clear onEvent to prevent closure leaks
  self.onEvent = nil

  -- Clear touch callbacks to prevent closure leaks
  self.onTouchEvent = nil
  self.onGesture = nil

  Element._Select.cleanupDestroy(self)
end

--- Retry deferred methods queued via `_deferMethod` during this frame. Each
--- pending entry is invoked through pcall; failures are reported to the
--- ErrorHandler instead of aborting the frame, and entries that re-defer are
--- retried next frame with an incremented retry count up to MAX_DEFER_RETRIES.
--- Extracted from the tail of Element:update so update stays a thin
--- behavior-dispatch orchestrator (behavior-mode-unification task 09).
function Element:_processDeferredMethods()
  if #self._deferredMethods == 0 then
    return
  end
  local pending = self._deferredMethods
  self._deferredMethods = {}
  for _, entry in ipairs(pending) do
    if entry.retryCount >= MAX_DEFER_RETRIES then
      Element._ErrorHandler:warn("Element", "CORE_004", {
        element = self.id,
        method = tostring(entry.methodName),
        retryCount = entry.retryCount,
      })
    else
      local beforeCount = #self._deferredMethods
      local callArgs = {}
      for j = 1, entry.argc do
        local val = entry.args[j]
        if val == _DEFERRED_NIL then
          callArgs[j] = nil
        else
          callArgs[j] = val
        end
      end
      local success, err = pcall(function()
        self[entry.methodName](self, unpack(callArgs, 1, entry.argc))
      end)
      if not success then
        Element._ErrorHandler:warn("Element", "CORE_002", {
          element = self.id,
          method = tostring(entry.methodName),
          error = tostring(err),
        })
      end
      -- Propagate retry count to any new deferred entry for the same method
      for i = beforeCount + 1, #self._deferredMethods do
        if self._deferredMethods[i].methodName == entry.methodName then
          self._deferredMethods[i].retryCount = entry.retryCount + 1
        end
      end
    end
  end
end

--- Draw element and its children
function Element:draw(backdropCanvas)
  -- Early exit if element is display:none or invisible (optimization)
  if self.display == false or self.opacity <= 0 or self.visibility == "hidden" then
    return
  end

  -- Background behaviors (drawLayer ~= "overlay") render BEFORE children in
  -- registry order: Themed (core Renderer:draw), Clickable (pressed overlay),
  -- ... Overlay behaviors (Scrollable scrollbars) render AFTER children below.
  local drawCtx = { backdropCanvas = backdropCanvas }
  local behaviors = self.behaviors
  for i = 1, #behaviors do
    local b = behaviors[i]
    if b.drawLayer ~= "overlay" then
      b.onDraw(self, drawCtx)
    end
  end

  -- Core child hierarchy rendering (clipping, sorting, scroll offset, blur).
  -- Stays in Element: it is structural, not a per-capability behavior.
  self:_drawChildren(backdropCanvas)

  -- Overlay behaviors (drawLayer == "overlay") render AFTER children so they
  -- paint on top, e.g. Scrollable's scrollbars (behavior-mode-unification 09).
  for i = 1, #behaviors do
    local b = behaviors[i]
    if b.drawLayer == "overlay" then
      b.onDraw(self, drawCtx)
    end
  end
end

--- Core child-drawing pipeline extracted from Element:draw so the draw entry
--- point stays a thin behavior-dispatch orchestrator (task 09). Owns z-sort,
--- rounded-corner/overflow clipping (stencil > scissor), scroll/content offset,
--- optional content-blur application, and recursive child:draw. Not a behavior
--- — this is structural hierarchy rendering shared by every element.
function Element:_drawChildren(backdropCanvas)
  local sortedChildren = {}
  for _, child in ipairs(self.children) do
    table.insert(sortedChildren, child)
  end
  if #sortedChildren == 0 then
    return
  end
  table.sort(sortedChildren, function(a, b)
    return a.z < b.z
  end)

  local borderBoxWidth = self._borderBoxWidth or (self.width + self.padding.left + self.padding.right)
  local borderBoxHeight = self._borderBoxHeight or (self.height + self.padding.top + self.padding.bottom)

  -- Check if we need to clip children to rounded corners
  local hasRoundedCorners = false
  if self.cornerRadius then
    if type(self.cornerRadius) == "number" then
      hasRoundedCorners = self.cornerRadius > 0
    else
      hasRoundedCorners = self.cornerRadius.topLeft > 0
        or self.cornerRadius.topRight > 0
        or self.cornerRadius.bottomLeft > 0
        or self.cornerRadius.bottomRight > 0
    end
  end

  -- Render the (possibly clipped + offset) child layer, applying content blur
  -- when configured. The inner closure performs clipping/offset/draw; blur
  -- wraps it in a region pass when a blur instance is available.
  local function renderChildLayer()
    local contentOffsetX, contentOffsetY = self:getContentStateOffset()

    -- Determine overflow behavior per axis (matches HTML/CSS behavior)
    local overflowX = self.overflowX or self.overflow
    local overflowY = self.overflowY or self.overflow
    local needsOverflowClipping = (overflowX ~= "visible" or overflowY ~= "visible")
      and (overflowX ~= nil or overflowY ~= nil)

    -- Apply scroll/content offset after clipping is set
    local hasScrollOffset = needsOverflowClipping and (self._scrollX ~= 0 or self._scrollY ~= 0)
    local hasContentOffset = contentOffsetX ~= 0 or contentOffsetY ~= 0
    local hasOffset = hasScrollOffset or hasContentOffset

    -- Set up clipping: rounded-corners (stencil) > overflow (scissor) > none
    local clipMode = "none"
    local prevSx, prevSy, prevSw, prevSh
    if hasRoundedCorners then
      local roundedBoxWidth = self._borderBoxWidth or (self.width + self.padding.left + self.padding.right)
      local roundedBoxHeight = self._borderBoxHeight or (self.height + self.padding.top + self.padding.bottom)
      local stencilFunc =
        Element._RoundedRect.stencilFunction(self.x, self.y, roundedBoxWidth, roundedBoxHeight, self.cornerRadius)
      local currentCanvas = love.graphics.getCanvas()
      love.graphics.setCanvas()
      love.graphics.stencil(stencilFunc, "replace", 1)
      love.graphics.setCanvas(currentCanvas)
      love.graphics.setStencilTest("greater", 0)
      clipMode = "stencil"
    elseif needsOverflowClipping then
      -- Intersect with (and later restore) any ancestor scissor: replacing
      -- it let a nested scroller widen its parent's clip, and the bare
      -- setScissor() restore then cleared it entirely - scrolled page
      -- content drew straight over the pinned header.
      -- transformPoint: scissor rects live in window coordinates and ignore
      -- the scroll translate an ancestor scroller has pushed, so a nested
      -- scroller's clip sat at its untranslated layout position and cut its
      -- own rows away once the page scrolled.
      prevSx, prevSy, prevSw, prevSh = love.graphics.getScissor()
      local scx, scy = love.graphics.transformPoint(
        self.x + self.padding.left, self.y + self.padding.top)
      love.graphics.intersectScissor(scx, scy, self.width, self.height)
      clipMode = "scissor"
    end

    if hasOffset then
      love.graphics.push()
      love.graphics.translate(
        (hasScrollOffset and -self._scrollX or 0) + contentOffsetX,
        (hasScrollOffset and -self._scrollY or 0) + contentOffsetY
      )
    end

    for _, child in ipairs(sortedChildren) do
      child:draw(backdropCanvas)
    end

    if hasOffset then
      love.graphics.pop()
    end

    -- Restore clipping state
    if clipMode == "stencil" then
      love.graphics.setStencilTest()
    elseif clipMode == "scissor" then
      if prevSx then
        love.graphics.setScissor(prevSx, prevSy, prevSw, prevSh)
      else
        love.graphics.setScissor()
      end
    end
  end

  -- Apply content blur if configured
  if self.contentBlur and self.contentBlur.radius > 0 then
    local blurInstance = self:getBlurInstance()
    if blurInstance then
      Element._Blur.applyToRegion(
        blurInstance,
        self.contentBlur.radius,
        self.x,
        self.y,
        borderBoxWidth,
        borderBoxHeight,
        renderChildLayer
      )
    else
      renderChildLayer()
    end
  else
    renderChildLayer()
  end
end

--- Update element (propagate to children)
---@param dt number
function Element:update(dt)
  if self.display == false then
    return
  end
  if not self.parent then
    self:_trackActiveAnimations()
  end
  for _, child in ipairs(self.children) do
    child:update(dt)
  end
  -- Advance direct-assignment animations before the loop so geometry is current
  -- for hit-testing; no-ops when the Animated behavior is already attached.
  Element._dispatchAnimatedUpdate(self, dt)
  for _, b in ipairs(self.behaviors) do
    b.onUpdate(self, dt)
  end
  self:_processDeferredMethods()
end

--- Handle a touch event directly (for external touch routing)
--- Invokes both onEvent and onTouchEvent callbacks if set
---@param touchEvent InputEvent The touch event to handle
function Element:handleTouchEvent(touchEvent)
  if not self.touchEnabled or self.disabled then
    return
  end
  if self._eventHandler then
    self._eventHandler:_invokeCallback(self, touchEvent)
    self._eventHandler:_invokeTouchCallback(self, touchEvent)
  end
end

--- Handle a gesture event (from GestureRecognizer or external routing)
---@param gesture table The gesture data (type, position, velocity, etc.)
function Element:handleGesture(gesture)
  if not self.touchEnabled or self.disabled then
    return
  end
  if self._eventHandler then
    self._eventHandler:_invokeGestureCallback(self, gesture)
  end
end

--- Get active touches currently tracked on this element
---@return table<string, table> Active touches keyed by touch ID
function Element:getTouches()
  if self._eventHandler then
    return self._eventHandler:getActiveTouches()
  end
  return {}
end

---@param newViewportWidth number
---@param newViewportHeight number
function Element:recalculateUnits(newViewportWidth, newViewportHeight)
  self._layoutEngine:recalculateUnits(newViewportWidth, newViewportHeight)
end

--- Resize element and its children based on game window size change
---@param newGameWidth number
---@param newGameHeight number
function Element:resize(newGameWidth, newGameHeight)
  self:recalculateUnits(newGameWidth, newGameHeight)
  self:_refreshSizeConstraints(newGameWidth, newGameHeight)

  -- For non-auto-sized elements with viewport/percentage units, update content dimensions from border-box
  if not self.autosizing.width and self._borderBoxWidth and self.units.width.unit ~= "px" then
    self._borderBoxWidth = Element._utils.clamp(self._borderBoxWidth, self.minWidth, self.maxWidth)
    self.width = math.max(0, self._borderBoxWidth - self.padding.left - self.padding.right)
  end
  if not self.autosizing.height and self._borderBoxHeight and self.units.height.unit ~= "px" then
    self._borderBoxHeight = Element._utils.clamp(self._borderBoxHeight, self.minHeight, self.maxHeight)
    self.height = math.max(0, self._borderBoxHeight - self.padding.top - self.padding.bottom)
  end

  -- Update children
  for _, child in ipairs(self.children) do
    child:resize(newGameWidth, newGameHeight)
  end

  -- Recalculate auto-sized dimensions after children are resized
  if self.autosizing.width then
    local contentWidth = self:calculateAutoWidth()
    -- BORDER-BOX MODEL: Add padding to get border-box, then subtract to get content
    self._borderBoxWidth =
      Element._utils.clamp(contentWidth + self.padding.left + self.padding.right, self.minWidth, self.maxWidth)
    self.width = math.max(0, self._borderBoxWidth - self.padding.left - self.padding.right)
    -- CONTENT-LEVEL CLAMP: CSS min-width/max-width also bound the content width.
    -- Subtracting padding from the clamped border-box can drop the content width
    -- below minWidth (e.g. minWidth=200, horizontal padding=100 => content=100),
    -- so re-clamp the content dimension with the shared size-clamping utility.
    self.width = Element._utils.clampSize(self.width, self.minWidth, self.maxWidth)
  end
  if self.autosizing.height then
    local contentHeight = self:calculateAutoHeight()
    -- BORDER-BOX MODEL: Add padding to get border-box, then subtract to get content
    self._borderBoxHeight =
      Element._utils.clamp(contentHeight + self.padding.top + self.padding.bottom, self.minHeight, self.maxHeight)
    self.height = math.max(0, self._borderBoxHeight - self.padding.top - self.padding.bottom)
    -- CONTENT-LEVEL CLAMP: CSS min-height/max-height also bound the content height.
    -- Subtracting padding from the clamped border-box can drop the content height
    -- below minHeight (e.g. minHeight=200, vertical padding=100 => content=100),
    -- so re-clamp the content dimension with the shared size-clamping utility.
    self.height = Element._utils.clampSize(self.height, self.minHeight, self.maxHeight)
  end

  -- Re-resolve textSize if it uses viewport-relative units after dimensions are finalized

  self:layoutChildren()
  self.prevGameSize.width = newGameWidth
  self.prevGameSize.height = newGameHeight
end

function Element:_refreshSizeConstraints(newViewportWidth, newViewportHeight)
  local scaleX, scaleY = Element._Context.getScaleFactors()
  local ctx = { vw = newViewportWidth, vh = newViewportHeight, sx = scaleX, sy = scaleY }
  local parentW = self.parent and self.parent.width or newViewportWidth
  local parentH = self.parent and self.parent.height or newViewportHeight
  _refreshUnit(self, "minWidth", parentW, ctx, "x")
  _refreshUnit(self, "maxWidth", parentW, ctx, "x")
  _refreshUnit(self, "minHeight", parentH, ctx, "y")
  _refreshUnit(self, "maxHeight", parentH, ctx, "y")
end

--- Calculate text width for button
---@return number
function Element:calculateTextWidth()
  if self.text == nil then
    return 0
  end

  local font = Element._utils.getFont(self.textSize, self.fontFamily, self.themeComponent, self._themeManager)
  local width = font:getWidth(self.text)
  return Element._utils.applyContentMultiplier(width, self.contentAutoSizingMultiplier, "width")
end

---@return number
function Element:calculateTextHeight()
  if self.text == nil then
    return 0
  end

  local font = Element._utils.getFont(self.textSize, self.fontFamily, self.themeComponent, self._themeManager)
  local height = font:getHeight()

  if self.textWrap and (self.textWrap == "word" or self.textWrap == "char" or self.textWrap == true) then
    local availableWidth = self.width

    if (not availableWidth or availableWidth <= 0) and self.parent then
      availableWidth = self.parent.width
    end

    if availableWidth and availableWidth > 0 then
      local _, wrappedLines = font:getWrap(self.text, availableWidth)
      height = height * #wrappedLines
    end
  end

  return Element._utils.applyContentMultiplier(height, self.contentAutoSizingMultiplier, "height")
end

function Element:calculateAutoWidth()
  local contentWidth = self._layoutEngine:calculateAutoWidth()
  if self._managedSelectMinimumBorderBoxWidth then
    local minimumContentWidth =
      math.max(0, self._managedSelectMinimumBorderBoxWidth - self.padding.left - self.padding.right)
    contentWidth = math.max(contentWidth, minimumContentWidth)
  end
  return contentWidth
end

--- Calculate auto height based on children
function Element:calculateAutoHeight()
  return self._layoutEngine:calculateAutoHeight()
end

---@param newText string
---@param autoresize boolean? --default: false
function Element:updateText(newText, autoresize)
  self.text = newText or self.text
  if autoresize then
    self.width = self:calculateTextWidth()
    self.height = self:calculateTextHeight()
  end
end

---@param newOpacity number
function Element:updateOpacity(newOpacity)
  self.opacity = newOpacity
  for _, child in ipairs(self.children) do
    child:updateOpacity(newOpacity)
  end
end

--- same as calling updateOpacity(0)
function Element:hide()
  self:updateOpacity(0)
end

--- same as calling updateOpacity(1)
function Element:show()
  self:updateOpacity(1)
end

-- ====================
-- Input Handling - Text Editing (behavior-delegated, task 04)
-- ====================
-- All text-editor operations are dispatched through the TextEditable behavior
-- (modules/behaviors/TextEditable.lua). Element retains only thin 1-line
-- forwarders for backward-compat with external callers (EventHandler,
-- KeyboardNavigation, Renderer, game UI). The behavior owns the TextEditor
-- subsystem (onAttach creates it, onUpdate drives cursor blink, saveState /
-- restoreState persist it) AND implements the delegate bodies (text sync,
-- auto-grow, nil-guarding element._textEditor) — so Element carries zero
-- text-editor nil-guard branches and zero text-editor logic.
--
-- `_wrapLine` / `_getFont` remain here: they are RENDERER forwarders (not
-- TextEditor delegates), and the TextEditor has its own implementations.
-- `updateText` (above) is a plain-label text setter, not a TextEditor delegate.
-- ====================

--- Set cursor position (delegates to TextEditable behavior)
---@param position number -- Character index (0-based)
function Element:setCursorPosition(position)
  return Element._TextEditable.setCursorPosition(self, position)
end

--- Get cursor position (delegates to TextEditable behavior)
---@return number -- Character index (0-based)
function Element:getCursorPosition()
  return Element._TextEditable.getCursorPosition(self)
end

--- Move cursor by delta characters (delegates to TextEditable behavior)
---@param delta number -- Number of characters to move (positive or negative)
function Element:moveCursorBy(delta)
  return Element._TextEditable.moveCursorBy(self, delta)
end

--- Move cursor to start of text (delegates to TextEditable behavior)
function Element:moveCursorToStart()
  return Element._TextEditable.moveCursorToStart(self)
end

--- Move cursor to end of text (delegates to TextEditable behavior)
function Element:moveCursorToEnd()
  return Element._TextEditable.moveCursorToEnd(self)
end

--- Move cursor to start of current line (delegates to TextEditable behavior)
function Element:moveCursorToLineStart()
  return Element._TextEditable.moveCursorToLineStart(self)
end

--- Move cursor to end of current line (delegates to TextEditable behavior)
function Element:moveCursorToLineEnd()
  return Element._TextEditable.moveCursorToLineEnd(self)
end

--- Move cursor to start of previous word (delegates to TextEditable behavior)
function Element:moveCursorToPreviousWord()
  return Element._TextEditable.moveCursorToPreviousWord(self)
end

--- Move cursor to start of next word (delegates to TextEditable behavior)
function Element:moveCursorToNextWord()
  return Element._TextEditable.moveCursorToNextWord(self)
end

--- Set selection range (delegates to TextEditable behavior)
---@param startPos number -- Start position (inclusive)
---@param endPos number -- End position (inclusive)
function Element:setSelection(startPos, endPos)
  return Element._TextEditable.setSelection(self, startPos, endPos)
end

--- Get selection range (delegates to TextEditable behavior)
---@return number?, number? -- Start and end positions, or nil if no selection
function Element:getSelection()
  return Element._TextEditable.getSelection(self)
end

--- Check if there is an active selection (delegates to TextEditable behavior)
---@return boolean
function Element:hasSelection()
  return Element._TextEditable.hasSelection(self)
end

--- Clear selection (delegates to TextEditable behavior)
function Element:clearSelection()
  return Element._TextEditable.clearSelection(self)
end

--- Select all text (delegates to TextEditable behavior)
function Element:selectAll()
  return Element._TextEditable.selectAll(self)
end

--- Get selected text (delegates to TextEditable behavior)
---@return string? -- Selected text or nil if no selection
function Element:getSelectedText()
  return Element._TextEditable.getSelectedText(self)
end

--- Delete selected text (delegates to TextEditable behavior, which owns text sync + auto-grow)
---@return boolean -- True if text was deleted
function Element:deleteSelection()
  return Element._TextEditable.deleteSelection(self)
end

--- Give this element keyboard focus to enable text input or keyboard navigation
--- Use this to automatically focus text fields when showing forms or dialogs
function Element:focus()
  return Element._TextEditable.focus(self)
end

--- Remove keyboard focus to stop capturing input events
--- Use this when closing popups or switching focus to other elements
function Element:blur()
  return Element._TextEditable.blur(self)
end

--- Query focus state to conditionally render focus indicators or handle keyboard input
--- Use this to style focused elements or determine which element receives keyboard events
---@return boolean
function Element:isFocused()
  return Element._TextEditable.isFocused(self)
end

--- Retrieve the element's current text content for processing or validation
--- Use this to read user input from text fields or get display text
---@return string
function Element:getText()
  return Element._TextEditable.getText(self)
end

--- Update the element's text content programmatically for dynamic labels or resetting inputs
--- Use this to change text without user input, like clearing fields or updating status messages
---@param text string
function Element:setText(text)
  return Element._TextEditable.setText(self, text)
end

--- Programmatically insert text at any position for autocomplete or text manipulation
--- Use this to implement suggestions, templates, or text snippets
---@param text string -- Text to insert
---@param position number? -- Position to insert at (default: cursor position)
function Element:insertText(text, position)
  return Element._TextEditable.insertText(self, text, position)
end

---@param startPos number -- Start position (inclusive)
---@param endPos number -- End position (inclusive)
function Element:deleteText(startPos, endPos)
  return Element._TextEditable.deleteText(self, startPos, endPos)
end

--- Replace text in range
---@param startPos number -- Start position (inclusive)
---@param endPos number -- End position (inclusive)
---@param newText string -- Replacement text
function Element:replaceText(startPos, endPos, newText)
  return Element._TextEditable.replaceText(self, startPos, endPos, newText)
end

--- Wrap a single line of text
---@param line string -- Line to wrap
---@param maxWidth number -- Maximum width in pixels
---@return table -- Array of wrapped line parts
function Element:_wrapLine(line, maxWidth)
  return self._renderer:wrapLine(self, line, maxWidth)
end

---@return love.Font
function Element:_getFont()
  return self._renderer:getFont(self)
end

-- ====================
-- Input Handling - Mouse Selection
-- ====================

--- Handle mouse click on text (set cursor position or start selection)
--- Delegates to the TextEditable behavior, which owns drag tracking.
---@param mouseX number -- Mouse X coordinate
---@param mouseY number -- Mouse Y coordinate
---@param clickCount number -- Number of clicks (1=single, 2=double, 3=triple)
function Element:_handleTextClick(mouseX, mouseY, clickCount)
  return Element._TextEditable._handleTextClick(self, mouseX, mouseY, clickCount)
end

--- Handle mouse drag for text selection
--- Delegates to the TextEditable behavior, which owns drag tracking.
---@param mouseX number -- Mouse X coordinate
---@param mouseY number -- Mouse Y coordinate
function Element:_handleTextDrag(mouseX, mouseY)
  return Element._TextEditable._handleTextDrag(self, mouseX, mouseY)
end

-- ====================
-- Input Handling - Keyboard Input (behavior-delegated, task 04)
-- ====================

--- Handle text input (character input) — delegates to the TextEditable behavior.
---@param text string -- Character(s) to insert
function Element:textinput(text)
  return Element._TextEditable.textinput(self, text)
end

--- Handle key press (special keys) — delegates to the TextEditable behavior.
---@param key string -- Key name
---@param scancode string -- Scancode
---@param isrepeat boolean -- Whether this is a key repeat
function Element:keypressed(key, scancode, isrepeat)
  return Element._TextEditable.keypressed(self, key, scancode, isrepeat)
end

-- ====================
-- Performance Monitoring
-- ====================

--- Get hierarchy depth of this element
---@return number depth Depth in the element tree (0 for root)
function Element:getHierarchyDepth()
  local depth = 0
  local current = self.parent
  while current do
    depth = depth + 1
    current = current.parent
  end
  return depth
end

--- Count total elements in this tree
---@return number count Total number of elements including this one and all descendants
function Element:countElements()
  local count = 1 -- Count self
  for _, child in ipairs(self.children) do
    count = count + child:countElements()
  end
  return count
end

function Element:_checkPerformanceWarnings()
  if not Element._Performance or not Element._Performance.warningsEnabled then
    return
  end

  -- Check hierarchy depth
  local depth = self:getHierarchyDepth()
  if depth >= 15 then
    Element._Performance:logWarning(
      string.format("hierarchy_depth_%s", self.id),
      "Element",
      string.format("Element hierarchy depth is %d levels for element '%s'", depth, self.id or "unnamed"),
      { depth = depth, elementId = self.id or "unnamed" },
      "Deep nesting can impact performance. Consider flattening the structure or using absolute positioning"
    )
  end

  -- Check total element count (only for root elements)
  if not self.parent then
    local totalElements = self:countElements()
    if totalElements >= 1000 then
      Element._Performance:logWarning(
        "element_count_high",
        "Element",
        string.format("UI contains %d+ elements", totalElements),
        { elementCount = totalElements },
        "Large element counts may impact performance. Consider virtualization for long lists or pagination for large datasets"
      )
    end
  end
end

--- Count active animations in tree
---@return number count Number of active animations
function Element:_countActiveAnimations()
  local count = self.animation and 1 or 0
  for _, child in ipairs(self.children) do
    count = count + child:_countActiveAnimations()
  end
  return count
end

--- Track active animations and warn if too many
function Element:_trackActiveAnimations()
  -- Get Performance instance from deps if available
  if not Element._Performance or not Element._Performance.warningsEnabled then
    return
  end

  local animCount = self:_countActiveAnimations()
  if animCount >= 50 then
    Element._Performance:logWarning(
      "animation_count_high",
      "Element",
      string.format("%d+ animations running simultaneously", animCount),
      { animationCount = animCount },
      "High animation counts may impact frame rate. Consider reducing concurrent animations or using CSS-style transitions"
    )
  end
end

--- Change the tint color of an image element dynamically for hover effects or state indication
--- Use this to recolor images without replacing the asset, like highlighting selected items
---@param color Color Color to tint the image
function Element:setImageTint(color)
  self.imageTint = color
end

--- Adjust image transparency independently from the element for fade effects
--- Use this to create image-specific fade animations or disabled states
---@param opacity number Opacity 0-1
function Element:setImageOpacity(opacity)
  if opacity ~= nil then
    Element._utils.validateRange(opacity, 0, 1, "imageOpacity")
  end
  self.imageOpacity = opacity
end

--- Set image repeat mode
---@param repeatMode string Repeat mode: "no-repeat", "repeat", "repeat-x", "repeat-y", "space", "round"
function Element:setImageRepeat(repeatMode)
  local validImageRepeat = {
    ["no-repeat"] = "no-repeat",
    ["repeat"] = "repeat",
    ["repeat-x"] = "repeat-x",
    ["repeat-y"] = "repeat-y",
    space = "space",
    round = "round",
  }
  Element._utils.validateEnum(repeatMode, validImageRepeat, "imageRepeat")
  self.imageRepeat = repeatMode
end

--- Apply rotation transform to create spinning animations or rotated layouts
--- Use this for loading spinners, compass needles, or angled UI elements
---@param angle number Angle in radians
function Element:rotate(angle)
  if not self.transform then
    self.transform = Element._Transform.new({})
  end
  self.transform.rotate = angle
end

--- Resize element visually using scale transforms for zoom effects
--- Use this for hover magnification, shrinking animations, or responsive scaling
---@param scaleX number X-axis scale
---@param scaleY number? Y-axis scale (defaults to scaleX)
function Element:scale(scaleX, scaleY)
  if not self.transform then
    self.transform = Element._Transform.new({})
  end
  self.transform.scaleX = scaleX
  self.transform.scaleY = scaleY or scaleX
end

--- Offset element position using transforms for smooth movement without layout recalculation
--- Use this for parallax effects, draggable elements, or position animations
---@param x number X translation
---@param y number Y translation
function Element:translate(x, y)
  if not self.transform then
    self.transform = Element._Transform.new({})
  end
  self.transform.translateX = x
  self.transform.translateY = y
end

--- Define the pivot point for rotation and scaling transforms
--- Use this to rotate around corners, edges, or custom points rather than the center
---@param originX number X origin (0-1, where 0.5 is center)
---@param originY number Y origin (0-1, where 0.5 is center)
function Element:setTransformOrigin(originX, originY)
  if not self.transform then
    self.transform = Element._Transform.new({})
  end
  self.transform.originX = originX
  self.transform.originY = originY
end

--- Animate element to new property values with automatic transition
--- Captures current values as start, uses provided values as final, and applies the animation
---@param props table Target property values
---@param duration number? Animation duration in seconds (default: 0.3)
---@param easing string? Easing function name (default: "linear")
---@return Element self For method chaining
function Element:animateTo(props, duration, easing)
  if not Element._Animation then
    _warnAnimApi("ELEM_003")
    return self
  end

  if type(props) ~= "table" then
    _warnAnimApi("ELEM_003")
    return self
  end

  duration = duration or 0.3
  easing = easing or "linear"

  -- Collect current values as start
  local startValues = {}
  for key, _ in pairs(props) do
    startValues[key] = self[key]
  end

  -- Create and apply animation
  local anim = Element._Animation.new({
    duration = duration,
    start = startValues,
    final = props,
    easing = easing,
  })

  anim:apply(self)
  return self
end

--- Fade element to full opacity
---@param duration number? Duration in seconds (default: 0.3)
---@param easing string? Easing function name
---@return Element self For method chaining
function Element:fadeIn(duration, easing)
  return self:animateTo({ opacity = 1 }, duration or 0.3, easing)
end

--- Fade element to zero opacity
---@param duration number? Duration in seconds (default: 0.3)
---@param easing string? Easing function name
---@return Element self For method chaining
function Element:fadeOut(duration, easing)
  return self:animateTo({ opacity = 0 }, duration or 0.3, easing)
end

--- Scale element to target scale value using transforms
---@param targetScale number Target scale multiplier
---@param duration number? Duration in seconds (default: 0.3)
---@param easing string? Easing function name
---@return Element self For method chaining
function Element:scaleTo(targetScale, duration, easing)
  if not Element._Animation or not Element._Transform then
    _warnAnimApi("ELEM_003")
    return self
  end

  -- Ensure element has a transform
  if not self.transform then
    self.transform = Element._Transform.new({})
  end

  local currentScaleX = self.transform.scaleX or 1
  local currentScaleY = self.transform.scaleY or 1

  local anim = Element._Animation.new({
    duration = duration or 0.3,
    start = { scaleX = currentScaleX, scaleY = currentScaleY },
    final = { scaleX = targetScale, scaleY = targetScale },
    easing = easing or "linear",
  })

  anim:apply(self)
  return self
end

--- Move element to target position
---@param x number Target x position
---@param y number Target y position
---@param duration number? Duration in seconds (default: 0.3)
---@param easing string? Easing function name
---@return Element self For method chaining
function Element:moveTo(x, y, duration, easing)
  return self:animateTo({ x = x, y = y }, duration or 0.3, easing)
end

--- Set transition configuration for a property
---@param property string Property name or "all" for all properties
---@param config table Transition config {duration, easing, delay, onComplete}
function Element:setTransition(property, config)
  if not self.transitions then
    self.transitions = {}
  end

  if type(config) ~= "table" then
    _warnAnimApi("ELEM_003")
    config = {}
  end

  -- Validate config
  if config.duration and (type(config.duration) ~= "number" or config.duration < 0) then
    _warnAnimApi("ELEM_004", config.duration)
    config.duration = 0.3
  end

  self.transitions[property] = {
    duration = config.duration or 0.3,
    easing = config.easing or "easeOutQuad",
    delay = config.delay or 0,
    onComplete = config.onComplete,
  }
end

--- Set transition configuration for multiple properties
---@param groupName string Name for this transition group
---@param config table Transition config {duration, easing, delay, onComplete}
---@param properties table Array of property names
function Element:setTransitionGroup(_, config, properties)
  if type(properties) ~= "table" then
    _warnAnimApi("ELEM_005")
    return
  end

  for _, prop in ipairs(properties) do
    self:setTransition(prop, config)
  end
end

--- Remove transition configuration for a property
---@param property string Property name or "all" to remove all
function Element:removeTransition(property)
  if not self.transitions then
    return
  end

  if property == "all" then
    self.transitions = {}
  else
    self.transitions[property] = nil
  end
end

--- Resolve a unit-based dimension property (width/height) from a string or CalcObject
--- Parses the value, updates self.units, resolves to pixels, and updates border-box dimensions
---@param property string "width" or "height"
---@param value string|table The unit string (e.g., "50%", "10vw") or CalcObject
---@return number resolvedValue The resolved pixel value
function Element:_resolveDimensionProperty(property, value)
  local viewportWidth, viewportHeight = Element._Units.getViewport()
  local parsedValue, parsedUnit = Element._Units.parse(value)
  self.units[property] = { value = parsedValue, unit = parsedUnit }

  local parentDimension
  if property == "width" then
    parentDimension = self.parent and self.parent.width or viewportWidth
  else
    parentDimension = self.parent and self.parent.height or viewportHeight
  end

  local resolved = Element._Units.resolve(parsedValue, parsedUnit, viewportWidth, viewportHeight, parentDimension)

  if type(resolved) ~= "number" then
    Element._ErrorHandler:warn("Element", "LAY_003", {
      issue = string.format("%s resolution returned non-number value", property),
      type = type(resolved),
      value = tostring(resolved),
    })
    resolved = 0
  end

  self[property] = resolved

  if property == "width" then
    if self.autosizing and self.autosizing.width then
      self._borderBoxWidth = resolved + self.padding.left + self.padding.right
    else
      self._borderBoxWidth = resolved
    end
  else
    if self.autosizing and self.autosizing.height then
      self._borderBoxHeight = resolved + self.padding.top + self.padding.bottom
    else
      self._borderBoxHeight = resolved
    end
  end

  return resolved
end

--- Resolve a dimension (width/height) prop given a unit-string/Calc value.
--- Handles the unit-sameness short-circuit, transition-on-resolved-pixel-value
--- semantics, and layout invalidation. Exits setProperty (caller returns).
local function _setDimensionWithUnit(self, property, value, transitionConfig)
  -- Check if the unit specification is the same (compare against stored units)
  local currentUnits = self.units[property]
  local newValue, newUnit = Element._Units.parse(value)
  if currentUnits and currentUnits.value == newValue and currentUnits.unit == newUnit then
    return
  end

  if transitionConfig then
    -- For transitions, resolve the target value and transition the pixel value
    local currentPixelValue = self[property]
    local resolvedTarget = self:_resolveDimensionProperty(property, value)

    if currentPixelValue ~= nil and currentPixelValue ~= resolvedTarget then
      -- Reset to current value before animating
      self[property] = currentPixelValue
      local Animation = require("modules.Animation")
      local anim = Animation.new({
        duration = transitionConfig.duration,
        start = { [property] = currentPixelValue },
        final = { [property] = resolvedTarget },
        easing = transitionConfig.easing,
        onComplete = transitionConfig.onComplete,
      })
      anim:apply(self)
    end
  else
    self:_resolveDimensionProperty(property, value)
  end

  self:invalidateLayout()
end

--- Apply a transition animation from the current value to `value` for `property`.
--- Falls back to a direct write when there is no current value to animate from.
local function _animatePropertyTo(self, property, value, transitionConfig)
  local currentValue = self[property]
  if currentValue ~= nil then
    local Animation = require("modules.Animation")
    local anim = Animation.new({
      duration = transitionConfig.duration,
      start = { [property] = currentValue },
      final = { [property] = value },
      easing = transitionConfig.easing,
      onComplete = transitionConfig.onComplete,
    })
    anim:apply(self)
  else
    self[property] = value
  end
end

-- Explicit handler map for the few props with genuinely-different setProperty
-- semantics that cannot be expressed via schema flags alone. Adding a new prop
-- with ordinary behavior requires NO new entry here — it flows through the
-- generic flagged dispatch below. Handlers signal a full-handled early return.
local _specialSetHandlers = {
  parent = function(self, value)
    self:setParent(value)
    return true
  end,
  themeComponent = function(self, value)
    self.themeComponent = value
    self:_syncThemeAndRenderer("themeComponent", value)
    return true
  end,
  -- imagePath / image: setting these must re-run the Imageable load pipeline
  -- (recompute `_loadedImage`, fire onImageLoad/onImageError, defer I/O). The
  -- Imageable behavior installs `element._reloadImage` at construction; if it
  -- is absent the element has no image concern (Imageable only attaches when
  -- imagePath/image is declared at construction), so the field is set but no
  -- load occurs — late image-concern acquisition requires re-attaching the
  -- behavior, which is outside the attach-at-construction contract.
  imagePath = function(self, value)
    self.imagePath = value
    if self._reloadImage then
      self:_reloadImage()
    end
    return true
  end,
  image = function(self, value)
    self.image = value
    if self._reloadImage then
      self:_reloadImage()
    end
    return true
  end,
}

--- Set property with automatic transition.
--- Dispatch is registry-driven: dimension/unit props route through
--- `_setDimensionWithUnit`, the genuinely-special props (parent,
--- themeComponent, imagePath, image) route through `_specialSetHandlers`, and
--- everything else is a single generic path that consults schema flags
--- (`affectsLayout` / `syncsTheme`) for layout invalidation and theme sync. No
--- inline hardcoded property-name branches and no per-call table allocation.
---@param property string Property name
---@param value any New value
function Element:setProperty(property, value)
  local transitionConfig
  if self.transitions then
    transitionConfig = self.transitions[property] or self.transitions["all"]
  end

  local schema = Element._PropertySchema

  -- 1. Dimension prop with a unit string / CalcObject: resolve to pixels.
  if schema.isDimension(property) and (type(value) == "string" or (Element._Calc and Element._Calc.isCalc(value))) then
    _setDimensionWithUnit(self, property, value, transitionConfig)
    return
  end

  -- 2. Genuinely-special props (parent reparenting, themeComponent sync).
  local handler = _specialSetHandlers[property]
  if handler then
    handler(self, value)
    return
  end

  -- 3. Generic flagged dispatch.
  -- Skip write/transition/layout work for unchanged values, but still sync
  -- theme state: disabled/active must reach setThemeState even when the value is
  -- unchanged (renderer/theme state may have been reset out-of-band).
  if self[property] ~= value then
    if transitionConfig then
      _animatePropertyTo(self, property, value, transitionConfig)
    else
      self[property] = value
    end
    if schema.affectsLayout(property) then
      self:invalidateLayout()
    end
  end
  if schema.syncsTheme(property) then
    self:_syncThemeAndRenderer(property, value)
  end
end

---Sync ThemeManager and Renderer when properties change that affect rendering
---@param property string The property name that changed
---@param value any The new value
function Element:_syncThemeAndRenderer(property, value)
  -- Visual props (backgroundColor/borderColor/cornerRadius/opacity) and callbacks
  -- (onEvent/onTouchEvent/onGesture) are intentionally NOT synced here: Renderer:draw
  -- and EventHandler dispatch read them from the element as source of truth, so a
  -- bare `element.<prop> = v` write is immediately consistent with setProperty(...).
  -- Only stateful side effects (theme-state machine + themeManager component) remain.
  if property == "disabled" then
    if self._themeManager then
      self._themeManager.disabled = value
    end
    if self._renderer then
      self._renderer:setThemeState(value and "disabled" or "normal")
    end
  elseif property == "active" then
    if self._themeManager then
      self._themeManager.active = value
    end
    if self._renderer then
      self._renderer:setThemeState(value and "active" or "normal")
    end
  elseif property == "themeComponent" then
    if self._themeManager then
      self._themeManager.themeComponent = value
    end
  end
end

-- ====================
-- State Persistence (behavior-mode-unification task 12)
-- ====================

--- Save all element state for immediate-mode persistence.
--- Each attached behavior owns its own state extraction (saveState hook) and
--- returns a snapshot (or nil) merged into the consolidated state table:
--- Clickable → `eventHandler`, Scrollable → `scrollManager`, TextEditable →
--- `textEditor` + drag tracking, Selectable → `select`, Themed → `blur`,
--- Persistable → `_props` (public scalar mutations). Element owns ZERO
--- per-subsystem extraction logic — this method is a pure dispatch loop.
---@return ElementStateData state Complete state snapshot
function Element:saveState()
  local state = {}
  for i = 1, #self.behaviors do
    local bstate = self.behaviors[i].saveState(self)
    if bstate ~= nil then
      for k, v in pairs(bstate) do
        state[k] = v
      end
    end
  end
  return state
end

--- Restore all element state from StateManager.
--- Each attached behavior owns its own hydration (restoreState hook) and reads
--- only its own slice from the full state table. Registry order places
--- Persistable last so `_props` overrides subsystem-hydrated state, preserving
--- the legacy restore ordering. Element owns ZERO per-subsystem hydration.
---@param state ElementStateData State to restore
function Element:restoreState(state)
  if not state then
    return
  end
  for i = 1, #self.behaviors do
    self.behaviors[i].restoreState(self, state)
  end
end

--- Cleanup method to break circular references (immediate-mode frame end).
--- Iterates each attached behavior's `onDetach` hook so every behavior tears
--- down what its `onAttach` created (Clickable releases the EventHandler,
--- TextEditable the TextEditor, Themed the Renderer, Selectable the select
--- fields, Imageable the image callbacks), then clears the behaviors list and
--- unregisters from StateManager. Does NOT clear onEvent / onTouchEvent /
--- onGesture — the Renderer/EventHandler read those directly from the element
--- (not the cache), so clearing them here would break retained mode.
function Element:_cleanup()
  for i = 1, #self.behaviors do
    self.behaviors[i].onDetach(self)
  end
  self.behaviors = {}
  -- onCreate fires once at construction (already invoked by now); release it.
  self.onCreate = nil
  if self._stateId and self._stateId ~= "" then
    Element._StateManager.unregisterStateful(self._stateId)
  end
end

-- ====================
-- Keyboard Navigation
-- ====================

--- Check if this element can receive keyboard focus
---@return boolean
function Element:isFocusable()
  if self.disabled then
    return false
  end
  -- Capability query: an element is keyboard-focusable when it is editable, has
  -- an event/text handler, participates in the Select subsystem, or is a
  -- touch-interactive element with callbacks. Expressed as a single boolean
  -- expression (not a dispatch branch) because focusability is a query, not a
  -- per-frame behavior.
  return not not (
    self.editable
    or type(self.onEvent) == "function"
    or self._selectState
    or self.selectOption
    or self.onTextInput
    or (self.touchEnabled and (self.onTouchEvent or self.onGesture))
  )
end

--- Get all focusable children in DOM/document order (depth-first traversal)
--- Elements are collected in the order they appear in the children array,
--- with nested children collected after their parent. This matches standard
--- browser tab order behavior where elements are ordered by document position.
---@return Element[]
function Element:getFocusableChildren()
  local focusable = {}

  local function collectFocusable(elem)
    for _, child in ipairs(elem.children) do
      -- Check self first
      if child:isFocusable() then
        table.insert(focusable, child)
      end

      -- Then recurse (depth-first)
      collectFocusable(child)
    end
  end

  collectFocusable(self)
  return focusable
end

--- Get next focusable element in sequence
---@param container Element The container element
---@param currentElement Element? Current focused element
---@param wrap boolean? Whether to wrap around
---@return Element?
function Element.getNextFocusable(container, currentElement, wrap)
  local focusable = container:getFocusableChildren()
  if #focusable == 0 then
    return nil
  end

  -- Find current index
  local currentIndex = 0
  if currentElement then
    for i, elem in ipairs(focusable) do
      if elem == currentElement then
        currentIndex = i
        break
      end
    end
  end

  -- Find next
  local nextIndex = currentIndex + 1
  if nextIndex > #focusable then
    if wrap then
      nextIndex = 1
    else
      return nil
    end
  end

  return focusable[nextIndex]
end

--- Get previous focusable element in sequence
---@param container Element The container element
---@param currentElement Element? Current focused element
---@param wrap boolean? Whether to wrap around
---@return Element?
function Element.getPreviousFocusable(container, currentElement, wrap)
  local focusable = container:getFocusableChildren()
  if #focusable == 0 then
    return nil
  end

  -- Find current index
  local currentIndex = #focusable + 1
  if currentElement then
    for i, elem in ipairs(focusable) do
      if elem == currentElement then
        currentIndex = i
        break
      end
    end
  end

  -- Find previous
  local prevIndex = currentIndex - 1
  if prevIndex < 1 then
    if wrap then
      prevIndex = #focusable
    else
      return nil
    end
  end

  return focusable[prevIndex]
end

return Element
