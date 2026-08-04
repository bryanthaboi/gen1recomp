-- modules/PropertySchema.lua
--
-- Declarative source of truth for every Element prop.
--
-- Each entry describes one prop that Element.new / Element:setProperty currently
-- handles inline. Downstream tasks (03 data-driven prop binding, 05 registry-driven
-- setProperty dispatch) read this metadata instead of hardcoding property names.
--
-- Design constraints (locked — tasks 03/05 depend on this API):
--   * Pure Lua — NO `love` import, NO dependency on utils/Color/Units/ErrorHandler.
--     Normalizers/validators are small, dependency-free closures so the module is
--     unit-testable standalone. Color/^/unit/enum *defaults* that require those
--     modules are left as `nil` here and applied by construction-time special
--     handlers in Task 03; only defaults expressible as literals are stored.
--   * O(1) lookup — `get(name)` is a single table index into a pre-built registry;
--     no per-call construction.
--   * Additive — `define(specs)` merges entries by name so build profiles can
--     extend/override without rebuilding the whole table.
--
-- Metadata shape per prop (all fields present, false/nil when not applicable):
--   type         string   — type tag for tooling ("number"|"string"|"boolean"|
--                                    "table"|"function"|"color"|"any")
--   default      any|nil   — literal default value applied when prop is absent
--   normalizer   fn|nil    — pure fn(value) -> value; transforms input before
--                            storage (e.g. single-value padding -> 4-side table)
--   validator    fn|nil    — pure fn(value) -> bool; returns false for invalid
--                            input (Task 03 warns + falls back on false)
--   isDimension  boolean   — true for width/height: setProperty routes these
--                            through _resolveDimensionProperty (unit-string
--                            resolution + border-box sync). Other unit-accepting
--                            props (x/y/gap/padding/etc.) are resolved at
--                            construction via special handlers, NOT via this flag.
--   affectsLayout boolean  — true for props in the legacy setProperty
--                            `layoutProperties` table; setting one invalidates
--                            layout (matches baseline behavior exactly).
--   syncsTheme   boolean   — true for props whose setProperty path must reach
--                            ThemeManager/Renderer (disabled/active/themeComponent)
--   hasDeferred  boolean   — true for callbacks that have an `on<Name>Deferred`
--                            boolean companion prop (auto-wired by Task 03)
--   storageKey   string|nil— when set, the prop is stored on the element under
--                            this key instead of its own name (prop aliases, e.g.
--                            isDisabled -> stored as `disabled`)

local PropertySchema = {}

---@type table<string, table>
local registry = {}

-- ---------------------------------------------------------------------------
-- Pure normalizers (small + dependency-free; hot-pathed during construction)
-- ---------------------------------------------------------------------------

--- Expand a single value to a 4-side table. Leaves tables unchanged. nil passthrough.
--- Used by padding/margin: `padding = 5` -> `{top=5,right=5,bottom=5,left=5}`.
local function expandSides(value)
  if value == nil then
    return nil
  end
  if type(value) == "table" then
    return value
  end
  return { top = value, right = value, bottom = value, left = value }
end

--- Normalize flex direction aliases to internal enum names.
--- "row" -> "horizontal", "column" -> "vertical",
--- "row-reverse" -> "horizontal-reverse", "column-reverse" -> "vertical-reverse";
--- everything else passes through.
local function normalizeFlexDirection(value)
  if value == "row" then
    return "horizontal"
  elseif value == "column" then
    return "vertical"
  elseif value == "row-reverse" then
    return "horizontal-reverse"
  elseif value == "column-reverse" then
    return "vertical-reverse"
  end
  return value
end

--- Replicate Element.new's border-shape normalization (pure).
--- * table with sides: true -> 1, number -> value, false/nil -> false; nil if no
---   truthy side remains.
--- * number / other truthy scalar: kept as-is.
--- * nil / false: nil.
local function normalizeBorder(value)
  if value == nil or value == false then
    return nil
  end
  if type(value) == "table" then
    local function side(v)
      if v == true then
        return 1
      elseif type(v) == "number" then
        return v
      else
        return false
      end
    end
    local t = side(value.top)
    local r = side(value.right)
    local b = side(value.bottom)
    local l = side(value.left)
    if not (t or r or b or l) then
      return nil
    end
    return { top = t, right = r, bottom = b, left = l }
  end
  return value
end

--- Replicate Element.new's cornerRadius-shape normalization (pure).
--- * number: 0 -> nil, else the number.
--- * table: nil if all four sides are zero/absent, else fill zeros for absent sides.
--- * nil -> nil.
local function normalizeCornerRadius(value)
  if value == nil then
    return nil
  end
  if type(value) == "number" then
    if value == 0 then
      return nil
    end
    return value
  end
  if type(value) == "table" then
    -- Mirrors Element.new: `or` truthiness (0 is truthy in Lua). Only an all-
    -- nil/false table collapses to nil; any present side — including 0 — yields
    -- the 4-side table with zero-filled absent sides.
    local hasAny = value.topLeft or value.topRight or value.bottomLeft or value.bottomRight
    if not hasAny then
      return nil
    end
    return {
      topLeft = value.topLeft or 0,
      topRight = value.topRight or 0,
      bottomLeft = value.bottomLeft or 0,
      bottomRight = value.bottomRight or 0,
    }
  end
  return value
end

-- ---------------------------------------------------------------------------
-- Pure validators (dependency-free; return boolean)
-- ---------------------------------------------------------------------------

--- Range validator factory: returns fn(v) -> bool. nil is treated as valid
--- (absence handling is the default mechanism's job).
local function rangeValidator(min, max)
  return function(v)
    if v == nil then
      return true
    end
    return type(v) == "number" and v >= min and v <= max
  end
end

--- Enum validator factory: returns fn(v) -> bool for membership in `set` (set may
--- be an array or a map of value->truthy).
local function enumValidator(set)
  local lookup = {}
  if type(set) == "table" then
    for k, v in pairs(set) do
      if type(k) == "number" then
        lookup[v] = true
      else
        lookup[k] = true
      end
    end
  end
  return function(v)
    if v == nil then
      return true
    end
    return lookup[v] == true
  end
end

--- Boolean validator: nil is valid (absence); otherwise must be a boolean.
local function booleanValidator(v)
  return v == nil or type(v) == "boolean"
end

-- ---------------------------------------------------------------------------
-- Registry construction
-- ---------------------------------------------------------------------------

--- Build a fully-populated metadata entry, filling omitted fields with defaults.
local function entry(spec)
  return {
    type = spec.type or "any",
    default = spec.default,
    normalizer = spec.normalizer,
    validator = spec.validator,
    isDimension = spec.isDimension == true,
    affectsLayout = spec.affectsLayout == true,
    syncsTheme = spec.syncsTheme == true,
    hasDeferred = spec.hasDeferred == true,
    storageKey = spec.storageKey,
  }
end

--- Merge prop specs into the registry (additive; later entries override earlier).
---@param specs table<string, table> map of prop-name -> spec
---@return table registry the live registry table (for chaining/inspection)
function PropertySchema.define(specs)
  for name, spec in pairs(specs) do
    registry[name] = entry(spec)
  end
  return registry
end

--- O(1) metadata lookup.
---@param name string prop name
---@return table|nil metadata nil for unknown props (no error)
function PropertySchema.get(name)
  return registry[name]
end

--- Return the live registry (for inspection / coverage assertions only — not for
--- per-call construction).
---@return table
function PropertySchema.all()
  return registry
end

--- True if a prop is registered.
---@param name string
---@return boolean
function PropertySchema.has(name)
  return registry[name] ~= nil
end

--- True if setting this prop invalidates layout (legacy `layoutProperties` set).
--- O(1) registry lookup — no per-call table construction. Unknown props return false,
--- matching the legacy `layoutProperties[name]` nil-lookup behavior exactly.
---@param name string prop name
---@return boolean
function PropertySchema.affectsLayout(name)
  local meta = registry[name]
  return meta ~= nil and meta.affectsLayout == true
end

--- True for dimension props (width/height) that `setProperty` routes through
--- `_resolveDimensionProperty` (unit-string resolution + border-box sync).
--- O(1) registry lookup — no per-call table construction. Unknown props return false,
--- matching the legacy `dimensionProperties[name]` nil-lookup behavior exactly.
---@param name string prop name
---@return boolean
function PropertySchema.isDimension(name)
  local meta = registry[name]
  return meta ~= nil and meta.isDimension == true
end

--- True for props whose setProperty path must reach ThemeManager/Renderer
--- (disabled/active/themeComponent). O(1) registry lookup — no per-call table
--- construction. Unknown props return false, matching a legacy nil-lookup exactly.
---@param name string prop name
---@return boolean
function PropertySchema.syncsTheme(name)
  local meta = registry[name]
  return meta ~= nil and meta.syncsTheme == true
end

-- ---------------------------------------------------------------------------
-- Default schema (covers every prop handled in Element.new lines 259-1909 and
-- Element:setProperty lines 4291-4417 of the Task-01 baseline).
-- ---------------------------------------------------------------------------
local function defineDefaults()
  PropertySchema.define({
    -- ------------------------------------------------------------------ identity
    id = { type = "string" },
    userdata = { type = "any" },
    parent = { type = "table", affectsLayout = true },
    children = { type = "table" },

    -- ------------------------------------------------------------------ callbacks
    onEvent = { type = "function", hasDeferred = true },
    onFocus = { type = "function", hasDeferred = true },
    onBlur = { type = "function", hasDeferred = true },
    onTextInput = { type = "function", hasDeferred = true },
    onTextChange = { type = "function", hasDeferred = true },
    onEnter = { type = "function", hasDeferred = true },
    onCreate = { type = "function", hasDeferred = true },
    onTouchEvent = { type = "function", hasDeferred = true },
    onGesture = { type = "function", hasDeferred = true },
    onImageLoad = { type = "function", hasDeferred = true },
    onImageError = { type = "function", hasDeferred = true },

    -- Deferred companion flags (stored directly; no further Deferred companion)
    onEventDeferred = { type = "boolean", default = false },
    onFocusDeferred = { type = "boolean", default = false },
    onBlurDeferred = { type = "boolean", default = false },
    onTextInputDeferred = { type = "boolean", default = false },
    onTextChangeDeferred = { type = "boolean", default = false },
    onEnterDeferred = { type = "boolean", default = false },
    onCreateDeferred = { type = "boolean", default = false },
    onTouchEventDeferred = { type = "boolean", default = false },
    onGestureDeferred = { type = "boolean", default = false },
    onImageLoadDeferred = { type = "boolean", default = false },
    onImageErrorDeferred = { type = "boolean", default = false },

    -- focus / touch behavior
    dropFocusOnSelection = { type = "boolean" },
    customDraw = { type = "function" },
    touchEnabled = { type = "boolean", default = true },
    multiTouchEnabled = { type = "boolean", default = false },

    -- ------------------------------------------------------------------ theme
    theme = { type = "table" },
    themeComponent = { type = "string", syncsTheme = true },
    disabled = { type = "boolean", default = false, syncsTheme = true },
    isDisabled = {
      type = "boolean",
      default = false,
      syncsTheme = true,
      storageKey = "disabled",
    },
    active = { type = "boolean", default = false, syncsTheme = true },
    disableHighlight = { type = "boolean" },
    themeStateLock = { type = "boolean" },
    themeComponentDisabledStates = { type = "table" },
    scaleCorners = { type = "boolean" },
    scalingAlgorithm = { type = "string" },
    contentAutoSizingMultiplier = { type = "table" },
    contentBlur = { type = "table" },
    backdropBlur = { type = "table" },

    -- ------------------------------------------------------------------ text editing
    editable = { type = "boolean", default = false },
    multiline = { type = "boolean", default = false },
    passwordMode = { type = "boolean", default = false },
    textWrap = { type = "string" }, -- default computed from multiline
    maxLines = { type = "number" },
    maxLength = { type = "number" },
    placeholder = { type = "string" },
    inputType = { type = "string", default = "text" },
    textOverflow = { type = "string", default = "clip" },
    scrollable = { type = "boolean" }, -- default = multiline
    autoGrow = { type = "boolean" }, -- default = multiline
    selectOnFocus = { type = "boolean", default = false },
    cursorColor = { type = "color" },
    selectionColor = { type = "color" },
    cursorBlinkRate = { type = "number", default = 0.5 },
    text = { type = "string" },
    textAlign = {
      type = "string",
      default = "start",
      validator = enumValidator({ "start", "center", "end", "justify" }),
    },
    -- textAlignVertical is a derived storage field split out from textAlign
    -- (bindVisualState resolves table/compound-string input into H + V). Its
    -- validator is exposed for bindVisualState to validate the V component; the
    -- prop itself stays in SPECIAL_PROPS because compound parsing needs
    -- ErrorHandler warnings (schema is pure-Lua, cannot warn).
    textAlignVertical = {
      type = "string",
      default = "start",
      validator = enumValidator({ "start", "center", "end" }),
    },
    textColor = { type = "color" },
    fontFamily = { type = "string" },
    textSize = { type = "any" }, -- number | preset string; resolved by special handler
    minTextSize = { type = "number" },
    maxTextSize = { type = "number" },
    autoScaleText = { type = "boolean", default = true },

    -- ------------------------------------------------------------------ dimensions / box model
    width = { type = "any", isDimension = true, affectsLayout = true },
    height = { type = "any", isDimension = true, affectsLayout = true },
    x = { type = "any", affectsLayout = false },
    y = { type = "any", affectsLayout = false },
    minWidth = { type = "any" },
    maxWidth = { type = "any" },
    minHeight = { type = "any" },
    maxHeight = { type = "any" },
    gap = { type = "any", affectsLayout = true },
    padding = {
      type = "any",
      affectsLayout = true,
      normalizer = expandSides,
    },
    margin = {
      type = "any",
      affectsLayout = true,
      normalizer = expandSides,
    },
    flexDirection = {
      type = "string",
      default = "horizontal",
      affectsLayout = true,
      normalizer = normalizeFlexDirection,
    },
    flexWrap = { type = "string", default = "nowrap", affectsLayout = true },
    justifyContent = { type = "string", default = "flex-start", affectsLayout = true },
    alignItems = { type = "string", default = "stretch", affectsLayout = true },
    alignContent = { type = "string", default = "stretch", affectsLayout = true },
    positioning = { type = "string", default = "relative", affectsLayout = true },
    gridRows = { type = "number", affectsLayout = true },
    gridColumns = { type = "number", affectsLayout = true },
    top = { type = "any", affectsLayout = true },
    right = { type = "any", affectsLayout = true },
    bottom = { type = "any", affectsLayout = true },
    left = { type = "any", affectsLayout = true },
    columnGap = { type = "any" },
    rowGap = { type = "any" },
    flex = { type = "any" }, -- shorthand: expands to flexGrow/flexShrink/flexBasis
    flexGrow = { type = "number", default = 0, validator = rangeValidator(0, math.huge) },
    flexShrink = { type = "number", default = 1, validator = rangeValidator(0, math.huge) },
    flexBasis = { type = "any", default = "auto" },
    alignSelf = { type = "string", default = "auto" },
    justifySelf = { type = "string" },
    z = { type = "number", default = 0 },
    tabIndex = { type = "number" },

    -- ------------------------------------------------------------------ border / background / visual
    border = { type = "any", normalizer = normalizeBorder },
    borderColor = { type = "color" }, -- default Color.new(0,0,0,1) via special handler
    backgroundColor = { type = "color" }, -- default transparent via special handler
    opacity = {
      type = "number",
      default = 1,
      validator = rangeValidator(0, 1),
    },
    visibility = { type = "string", default = "visible" },
    display = {
      type = "boolean",
      default = true,
      validator = booleanValidator,
    },
    transform = { type = "table" },
    cornerRadius = { type = "any", normalizer = normalizeCornerRadius },

    -- ------------------------------------------------------------------ image
    imagePath = { type = "string" },
    image = { type = "table" },
    objectFit = {
      type = "string",
      default = "fill",
      validator = enumValidator({ "fill", "contain", "cover", "scale-down", "none" }),
    },
    objectPosition = { type = "string", default = "center center" },
    imageOpacity = {
      type = "number",
      default = 1,
      validator = rangeValidator(0, 1),
    },
    imageRepeat = {
      type = "string",
      default = "no-repeat",
      validator = enumValidator({
        "no-repeat",
        "repeat",
        "repeat-x",
        "repeat-y",
        "space",
        "round",
      }),
    },
    imageTint = { type = "color" },

    -- ------------------------------------------------------------------ scroll / scrollbar
    overflow = { type = "string" },
    overflowX = { type = "string" },
    overflowY = { type = "string" },
    scrollbarWidth = { type = "number" },
    scrollbarColor = { type = "color" },
    scrollbarTrackColor = { type = "color" },
    scrollbarRadius = { type = "number" },
    scrollbarPadding = { type = "number" },
    scrollSpeed = { type = "number" },
    invertScroll = { type = "boolean" },
    smoothScrollEnabled = { type = "boolean" },
    scrollBarStyle = { type = "string" },
    scrollbarKnobOffset = { type = "number" },
    hideScrollbars = { type = "boolean" },
    scrollbarPlacement = { type = "string" },
    scrollbarBalance = { type = "number" },
    _scrollX = { type = "number", storageKey = "_scrollX" },
    _scrollY = { type = "number", storageKey = "_scrollY" },

    -- ------------------------------------------------------------------ select
    selectParent = { type = "table" },
    selectOption = { type = "table" },

    -- ------------------------------------------------------------------ transition
    transition = { type = "table", default = {} },
  })
end

--- (Re)populate the default schema. Idempotent: safe to call from Element.init
--- for build profiles that re-require the module. Returns the live registry.
---@return table registry
function PropertySchema.populate()
  defineDefaults()
  return registry
end

-- Auto-populate on require so the registry is ready without an explicit init call
-- (pure module, no external deps — safe at load time).
PropertySchema.populate()

return PropertySchema
