---@class SelectOptionProps
---@field value any -- Stable option value owned by the parent select
---@field label string? -- Optional label override, falls back to the element text
---@field disabled boolean? -- Whether the option can be selected
local SelectOptionProps = {}

---@class SelectParentProps
---@field value any -- Currently selected option value
---@field open boolean? -- Initial open state for the select container
---@field placeholder string? -- Fallback text when no option is selected
---@field selectFrame Element? -- Optional pre-instantiated dropdown container; intended to be unattached before being adopted by the select
---@field onChange fun(element:Element, value:any, option:SelectOptionProps)? -- Called when selection changes
local SelectParentProps = {}

---@class Animation
local Animation = {}

---@class Color
local Color = {}

---@class Theme
local Theme = {}

---@class ThemeManager
local ThemeManager = {}

--=====================================--
-- For Animation.lua
--=====================================--
---@alias EasingFunction fun(t:number): number

---@class AnimationProps
---@field duration number -- Duration in seconds
---@field start table -- Starting values (can contain: width, height, opacity, x, y, gap, imageOpacity, backgroundColor, borderColor, textColor, padding, margin, cornerRadius, transform, etc.)
---@field final table -- Final values (same properties as start)
---@field easing string? -- Easing function name: "linear", "easeInQuad", "easeOutQuad", "easeInOutQuad", "easeInCubic", "easeOutCubic", "easeInOutCubic", "easeInQuart", "easeOutQuart", "easeInExpo", "easeOutExpo" (default: "linear")
---@field keyframes AnimationKeyframe[]? -- Array of keyframes for complex animations
---@field onStart fun(animation:Animation, element:Element?)? -- Called when animation starts
---@field onUpdate fun(animation:Animation, element:Element?, progress:number)? -- Called each frame with progress (0-1)
---@field onComplete fun(animation:Animation, element:Element?)? -- Called when animation completes
---@field onCancel fun(animation:Animation, element:Element?)? -- Called when animation is cancelled
---@field transform TransformProps? -- Additional transform properties (legacy support)
---@field transition table? -- Transition properties (legacy support)
local AnimationProps = {}

---@class Transform
---@field rotate number? Rotation in radians (default: 0)
---@field scaleX number? X-axis scale (default: 1)
---@field scaleY number? Y-axis scale (default: 1)
---@field translateX number? X translation in pixels (default: 0)
---@field translateY number? Y translation in pixels (default: 0)
---@field skewX number? X-axis skew in radians (default: 0)
---@field skewY number? Y-axis skew in radians (default: 0)
---@field originX number? Transform origin X (0-1, default: 0.5)
---@field originY number? Transform origin Y (0-1, default: 0.5)
local Transform = {}

---@alias TransformProps Transform

---@class TransitionProps
---@field duration number?
---@field easing string?
---@field delay number?
---@field onComplete fun(element:Element)?

--=====================================--
-- For Element.lua
--=====================================--
---@class ElementProps
---@field id string? -- Unique identifier for the element (auto-generated in immediate mode if not provided)
---@field mode "immediate"|"retained"|nil -- Lifecycle mode override: "immediate" (auto-managed state), "retained" (manual state), nil (use global mode from FlexLove.getMode(), default)
---@field parent Element? -- Parent element for hierarchical structure
---@field x number|string|CalcObject? -- X coordinate: number (px), string ("50%", "10vw"), or CalcObject from FlexLove.calc() (default: 0)
---@field y number|string|CalcObject? -- Y coordinate: number (px), string ("50%", "10vh"), or CalcObject from FlexLove.calc() (default: 0)
---@field z number? -- Z-index for layering (default: 0, clamped to -999..999)
---@field tabIndex number? -- Tab navigation order: >0 (explicit order, visited first), 0 or nil (natural document order), -1 (excluded from keyboard navigation)
---@field width number|string|CalcObject? -- Width of the element: number (px), string ("50%", "10vw"), or CalcObject from FlexLove.calc() (default: calculated automatically)
---@field height number|string|CalcObject? -- Height of the element: number (px), string ("50%", "10vh"), or CalcObject from FlexLove.calc() (default: calculated automatically)
---@field minWidth number|string|CalcObject? -- Minimum width constraint: number (px), string ("50%", "10vw"), or CalcObject. Clamps both fixed `width` and the flex-distributed main size when horizontal.
---@field maxWidth number|string|CalcObject? -- Maximum width constraint: number (px), string ("50%", "10vw"), or CalcObject. Clamps both fixed `width` and the flex-distributed main size when horizontal.
---@field minHeight number|string|CalcObject? -- Minimum height constraint: number (px), string ("50%", "10vh"), or CalcObject. Clamps both fixed `height` and the flex-distributed main size when vertical.
---@field maxHeight number|string|CalcObject? -- Maximum height constraint: number (px), string ("50%", "10vh"), or CalcObject. Clamps both fixed `height` and the flex-distributed main size when vertical.
---@field top number|string|CalcObject? -- Offset from top edge: number (px), string ("50%", "10vh"), or CalcObject (CSS-style positioning)
---@field right number|string|CalcObject? -- Offset from right edge: number (px), string ("50%", "10vw"), or CalcObject (CSS-style positioning)
---@field bottom number|string|CalcObject? -- Offset from bottom edge: number (px), string ("50%", "10vh"), or CalcObject (CSS-style positioning)
---@field left number|string|CalcObject? -- Offset from left edge: number (px), string ("50%", "10vw"), or CalcObject (CSS-style positioning)
---@field border Border? -- Border configuration for the element
---@field borderColor Color? -- Color of the border (default: black)
---@field opacity number? -- Element opacity 0-1 (default: 1)
---@field visibility "visible"|"hidden"? -- Element visibility (default: "visible")
---@field display boolean? -- Whether element participates in layout, rendering, and hit testing (default: true). Set false for CSS display:none behavior (zero layout space, no rendering, no hit testing). NOTE: In retained mode, toggling at runtime requires setting the parent's `_dirty = true` or calling `layoutChildren()` on the parent to trigger re-layout.
---@field backgroundColor Color? -- Background color (default: transparent)
---@field cornerRadius number|{topLeft:number?, topRight:number?, bottomLeft:number?, bottomRight:number?}? -- Corner radius: number (all corners) or table for individual corners (default: 0)
---@field gap number|string|CalcObject? -- Space between children elements: number (px), string ("50%", "10vw"), or CalcObject from FlexLove.calc() (default: 0)
---@field padding number|string|CalcObject|{top:number|string|CalcObject?, right:number|string|CalcObject?, bottom:number|string|CalcObject?, left:number|string|CalcObject?, horizontal:number|string|CalcObject?, vertical:number|string|CalcObject?}? -- Padding around children: single value, string, CalcObject for all sides, or table for individual sides (default: {top=0, right=0, bottom=0, left=0})
---@field margin number|string|CalcObject|{top:number|string|CalcObject?, right:number|string|CalcObject?, bottom:number|string|CalcObject?, left:number|string|CalcObject?, horizontal:number|string|CalcObject?, vertical:number|string|CalcObject?}? -- Margin around element: single value, string, CalcObject for all sides, or table for individual sides (default: {top=0, right=0, bottom=0, left=0})
---@field text string? -- Text content to display (default: nil)
---@field textAlign TextAlignSpec? -- Alignment of the text content: simple string, compound string ("top-left"), or {horizontal, vertical} table (default: START)
---@field textColor Color? -- Color of the text content (default: black or theme text color)
---@field textSize number|string? -- Font size: number (px), string with units ("2vh", "10%"), or preset ("xxs"|"xs"|"sm"|"md"|"lg"|"xl"|"xxl"|"3xl"|"4xl") (default: "md" or 12px)
---@field minTextSize number? -- Minimum text size in pixels for auto-scaling
---@field maxTextSize number? -- Maximum text size in pixels for auto-scaling
---@field fontFamily string? -- Font family name from theme or path to font file (default: theme default or system default, inherits from parent)
---@field autoScaleText boolean? -- Whether text should auto-scale with window size (default: true)
---@field positioning Positioning? -- Layout positioning mode: "absolute"|"relative"|"flex"|"grid" (default: RELATIVE)
---@field flexDirection FlexDirection? -- Direction of flex layout: "horizontal"|"vertical"|"row"|"column"|"row-reverse"|"column-reverse"|"horizontal-reverse"|"vertical-reverse" (row→horizontal, column→vertical, row-reverse→horizontal-reverse, column-reverse→vertical-reverse, default: HORIZONTAL)
---@field justifyContent JustifyContent? -- Alignment of items along main axis (default: FLEX_START)
---@field alignItems AlignItems? -- Alignment of items along cross axis (default: STRETCH)
---@field alignContent AlignContent? -- Alignment of lines in multi-line flex containers (default: STRETCH)
---@field flexWrap FlexWrap? -- Whether children wrap to multiple lines: "nowrap"|"wrap"|"wrap-reverse" (default: NOWRAP)
---@field flex number|string? -- Shorthand for flexGrow, flexShrink, flexBasis: number (flex-grow only), string ("1 0 auto"), or nil (default: nil)
---@field flexGrow number? -- How much the element should grow relative to siblings (default: 0)
---@field flexShrink number? -- How much the element should shrink relative to siblings (default: 1)
---@field flexBasis number|string|CalcObject? -- Initial size before growing/shrinking: number (px), string ("50%", "10vw", "auto"), or CalcObject (default: "auto")
---@field justifySelf JustifySelf? -- Alignment of the item itself along main axis (default: AUTO)
---@field alignSelf AlignSelf? -- Alignment of the item itself along cross axis (default: AUTO)
---@field onEvent fun(element:Element, event:InputEvent)? -- Callback function for interaction events
---@field onEventDeferred boolean? -- Whether onEvent callback should be deferred until after canvases are released (default: false)
---@field onFocus fun(element:Element)? -- Callback when element receives focus
---@field onFocusDeferred boolean? -- Whether onFocus callback should be deferred (default: false)
---@field dropFocusOnSelection boolean? -- Override keyboard-navigation focus drop after Enter/Space activation (default: nil, uses KeyboardNavigation.config.dropFocusOnSelection)
---@field onBlur fun(element:Element)? -- Callback when element loses focus
---@field onBlurDeferred boolean? -- Whether onBlur callback should be deferred (default: false)
---@field onTextInput fun(element:Element, text:string)? -- Callback when text is input
---@field onTextInputDeferred boolean? -- Whether onTextInput callback should be deferred (default: false)
---@field onTextChange fun(element:Element, text:string)? -- Callback when text content changes
---@field onTextChangeDeferred boolean? -- Whether onTextChange callback should be deferred (default: false)
---@field onEnter fun(element:Element)? -- Callback when Enter key is pressed
---@field onEnterDeferred boolean? -- Whether onEnter callback should be deferred (default: false)
---@field onCreate fun(element:Element, props:table)? -- Callback when element is created, receives the element and original creation props
---@field onCreateDeferred boolean? -- Whether onCreate callback should be deferred (default: false)
---@field onTouchEvent fun(element:Element, touchEvent:InputEvent)? -- Callback for touch-specific events (touchpress, touchmove, touchrelease)
---@field onTouchEventDeferred boolean? -- Whether onTouchEvent callback should be deferred (default: false)
---@field onGesture fun(element:Element, gesture:table)? -- Callback for recognized gestures (tap, swipe, pinch, etc.)
---@field onGestureDeferred boolean? -- Whether onGesture callback should be deferred (default: false)
---@field touchEnabled boolean? -- Whether the element responds to touch events (default: true)
---@field multiTouchEnabled boolean? -- Whether the element supports multiple simultaneous touches (default: false)
---@field transform TransformProps? -- Transform properties for animations and styling
---@field transition TransitionProps? -- Transition settings for animations
---@field customDraw fun(element:Element)? -- Custom rendering callback called after standard rendering but before visual feedback (default: nil)
---@field gridRows number|table? -- Number of equal 1fr rows, or array of track specs (e.g. {"1fr","100px","auto"})
---@field gridColumns number|table? -- Number of equal 1fr columns, or array of track specs (e.g. {"1fr","100px","auto"})
---@field columnGap number|string|CalcObject? -- Gap between grid columns: number (px), string ("50%", "10vw"), or CalcObject from FlexLove.calc() (default: 0)
---@field rowGap number|string|CalcObject? -- Gap between grid rows: number (px), string ("50%", "10vh"), or CalcObject from FlexLove.calc() (default: 0)
---@field theme string? -- Theme name to use (e.g., "space", "metal"). Defaults to theme from flexlove.init()
---@field themeComponent string? -- Theme component to use (e.g., "panel", "button", "input"). If nil, no theme is applied
---@field disabled boolean? -- Whether the element is disabled (default: false)
---@field active boolean? -- Whether the element is active/focused (for inputs, default: false)
---@field disableHighlight boolean? -- Whether to disable the pressed state highlight overlay (default: false, or true when using themeComponent)
---@field themeStateLock boolean|string? -- Lock theme state: true/"default" = lock to base state, false = normal behavior, string = specific state ("hover", "pressed", "active", "disabled") (default: false)
---@field themeComponentDisabledStates string[]? -- List of theme states to suppress visually (e.g. {"hover", "pressed"}). Interaction logic still fires.
---@field contentAutoSizingMultiplier {width:number?, height:number?}? -- Multiplier for auto-sized content dimensions (default: sourced from theme or {1, 1})
---@field scaleCorners number? -- Scale multiplier for 9-patch corners/edges. E.g., 2 = 2x size (overrides theme setting)
---@field scalingAlgorithm "nearest"|"bilinear"? -- Scaling algorithm for 9-patch corners: "nearest" (sharp/pixelated) or "bilinear" (smooth) (overrides theme setting)
---@field contentBlur {radius:number, quality:number?}? -- Blur the element's content including children (radius: pixels, quality: 1-10, default(quality): 5)
---@field backdropBlur {radius:number, quality:number?}? -- Blur content behind the element (radius: pixels, quality: 1-10, default(quality): 5)
---@field editable boolean? -- Whether the element is editable (default: false)
---@field multiline boolean? -- Whether the element supports multiple lines (default: false)
---@field textWrap boolean|"word"|"char"? -- Text wrapping mode (default: false for single-line, "word" for multi-line)
---@field maxLines number? -- Maximum number of lines (default: nil)
---@field maxLength number? -- Maximum text length in characters (default: nil)
---@field placeholder string? -- Placeholder text when empty (default: nil)
---@field passwordMode boolean? -- Whether to display text as password (default: false, disables multiline)
---@field inputType "text"|"number"|"email"|"url"? -- Input type for validation (default: "text")
---@field textOverflow "clip"|"ellipsis"|"scroll"? -- Text overflow behavior (default: "clip")
---@field scrollable boolean? -- Whether text is scrollable (default: false for single-line, true for multi-line)
---@field autoGrow boolean? -- Whether element auto-grows with text (default: false for single-line, true for multi-line)
---@field selectOnFocus boolean? -- Whether to select all text on focus (default: false)
---@field cursorColor Color? -- Cursor color (default: nil, uses textColor)
---@field selectionColor Color? -- Selection background color (default: nil, uses theme or default)
---@field cursorBlinkRate number? -- Cursor blink rate in seconds (default: 0.5)
---@field selectParent SelectParentProps? -- Parent-owned select/dropdown state and callbacks
---@field selectOption SelectOptionProps? -- Option metadata attached to a child of a select parent
---@field overflow "visible"|"hidden"|"scroll"|"auto"? -- Overflow behavior (default: "hidden")
---@field overflowX "visible"|"hidden"|"scroll"|"auto"? -- X-axis overflow (overrides overflow)
---@field overflowY "visible"|"hidden"|"scroll"|"auto"? -- Y-axis overflow (overrides overflow)
---@field scrollbarWidth number? -- Width of scrollbar track in pixels (default: 12)
---@field scrollbarColor Color? -- Scrollbar thumb color (default: Color.new(0.5, 0.5, 0.5, 0.8))
---@field scrollbarTrackColor Color? -- Scrollbar track color (default: Color.new(0.2, 0.2, 0.2, 0.5))
---@field scrollbarRadius number? -- Corner radius for scrollbar (default: 6)
---@field scrollbarPadding number? -- Padding between scrollbar and edge (default: 2)
---@field scrollSpeed number? -- Pixels per wheel notch (default: 20)
---@field invertScroll boolean? -- Invert mouse wheel scroll direction (default: false)
---@field smoothScrollEnabled boolean? -- Enable smooth scrolling animation for wheel events (default: false)
---@field scrollBarStyle string? -- Scrollbar style name from theme (selects from theme.scrollbars, default: uses first scrollbar or fallback rendering)
---@field scrollbarKnobOffset number|{x:number, y:number}|{horizontal:number, vertical:number}? -- Offset for scrollbar knob/handle position in pixels (number for both axes, or table for per-axis control, default: 0, adds to theme offset)
---@field scrollbarPlacement "reserve-space"|"overlay"? -- Scrollbar rendering mode: "reserve-space" (reduces content area, default) or "overlay" (renders over content)
---@field scrollbarBalance boolean? -- When true, reserve scrollbar space on both sides of content for visual balance (default: false)
---@field hideScrollbars boolean|{vertical:boolean, horizontal:boolean}? -- Hide scrollbars (boolean for both, or table for individual control, default: false)
---@field imagePath string? -- Path to image file (auto-loads via ImageCache)
---@field image love.Image? -- Image object to display
---@field objectFit "fill"|"contain"|"cover"|"scale-down"|"none"? -- Image fit mode (default: "fill")
---@field objectPosition string? -- Image position like "center center", "top left", "50% 50%" (default: "center center")
---@field imageOpacity number? -- Image opacity 0-1 (default: 1, combines with element opacity)
---@field imageRepeat "no-repeat"|"repeat"|"repeat-x"|"repeat-y"|"space"|"round"? -- Image repeat/tiling mode (default: "no-repeat")
---@field imageTint Color? -- Color to tint the image (default: nil/white, no tint)
---@field onImageLoad fun(element:Element, image:love.Image)? -- Callback when image loads successfully
---@field onImageLoadDeferred boolean? -- Whether onImageLoad callback should be deferred (default: false)
---@field onImageError fun(element:Element, error:string)? -- Callback when image fails to load
---@field onImageErrorDeferred boolean? -- Whether onImageError callback should be deferred (default: false)
---@field _scrollX number? -- Internal: scroll X position (restored in immediate mode)
---@field _scrollY number? -- Internal: scroll Y position (restored in immediate mode)
---@field children? ElementProps[]
---@field userdata table? -- User-defined data storage for custom properties
---@field ariaRole ARIA? -- ARIA role for screen readers (e.g., "button", "link", "dialog")
---@field ariaLabel string? -- Accessible name for screen readers (overrides text content)
---@field ariaDescribedBy string? -- ID of element that describes this element
---@field ariaExpanded boolean? -- Whether element is expanded/collapsed (for containers)
---@field ariaPressed boolean? -- Whether element is pressed (for toggle buttons)
---@field ariaChecked boolean? -- Whether element is checked (for checkboxes/radios)
---@field ariaDisabled boolean? -- Whether element is disabled (overrides disabled property)
---@field ariaBusy boolean? -- Whether element is processing (for live regions)
---@field ariaLive "off"|"polite"|"assertive"? -- Live region priority for announcements
local ElementProps = {}

---@class Border
---@field top boolean|number -- true sets width to 1px, number sets width to specified pixels (default: 0)
---@field right boolean|number -- true sets width to 1px, number sets width to specified pixels (default: 0)
---@field bottom boolean|number -- true sets width to 1px, number sets width to specified pixels (default: 0)
---@field left boolean|number -- true sets width to 1px, number sets width to specified pixels (default: 0)
local Border = {}

--=====================================--
-- For KeyboardNavigation.lua
--=====================================--
---@class KeyboardNavigationKeyConfig
---@field next string -- Key used to move to the next focusable element
---@field previous string -- Key used to move to the previous focusable element
---@field up string -- Key used for directional navigation upward
---@field down string -- Key used for directional navigation downward
---@field left string -- Key used for directional navigation leftward
---@field right string -- Key used for directional navigation rightward
---@field activate string[] -- Keys that activate the currently focused element
---@field dismiss string -- Key used to dismiss or clear the currently focused element
---@field toggleDebug string -- Key used to toggle keyboard-navigation debug tooling
---@field inspect string -- Key used to inspect the currently focused element in developer tools
local KeyboardNavigationKeyConfig = {}

---@class KeyboardNavigationDeveloperToolsConfig
---@field enabled boolean? -- Enable keyboard-navigation developer tools (default: true)
---@field showProperties boolean? -- Show focused element properties in developer tools (default: true)
---@field highlightColor number[]? -- RGBA color used for keyboard-navigation debug highlighting (default: {1, 0.8, 0, 0.5})
local KeyboardNavigationDeveloperToolsConfig = {}

---@class KeyboardNavigationFocusIndicatorConfig
---@field enabled boolean? -- Enable the keyboard focus indicator (default: true)
---@field color number[]? -- RGBA color of the focus indicator (default: {0.2, 0.6, 1.0, 0.8})
---@field lineWidth number? -- Focus indicator stroke width in pixels (default: 2)
---@field inset number? -- Offset from the element bounds in pixels (default: -3)
---@field borderRadius number? -- Focus indicator border radius in pixels (default: 4)
---@field animationDuration number? -- Focus indicator entrance animation duration in seconds (default: 0.15)
---@field pulseEnabled boolean? -- Enable pulse animation for the focus indicator when supported
---@field pulseDuration number? -- Seconds per pulse cycle
---@field pulseScaleMin number? -- Minimum scale during pulse animation
---@field pulseScaleMax number? -- Maximum scale during pulse animation
---@field draw fun(element:Element, bounds:table, style:KeyboardNavigationFocusIndicatorConfig)? -- Custom focus indicator renderer
local KeyboardNavigationFocusIndicatorConfig = {}

---@class KeyboardNavigationConfig
---@field enabled boolean? -- Enable or disable keyboard navigation globally (default: true)
---@field debugMode boolean? -- Enable keyboard-navigation debug logging (default: false)
---@field keys KeyboardNavigationKeyConfig? -- Key bindings used by keyboard navigation
---@field wrapAround boolean? -- Allow wrapping from last to first focusable element (default: true)
---@field directionalNavigation boolean? -- Enable arrow-key directional navigation (default: true)
---@field focusVisible boolean? -- Show the focus indicator for keyboard-driven focus (default: true)
---@field autofocusOnCreate boolean? -- Auto-focus the first focusable element on creation (default: false)
---@field dropFocusOnSelection boolean? -- Drop focus after Enter/Space activates an element (default: true)
---@field developerTools KeyboardNavigationDeveloperToolsConfig? -- Developer tool settings for keyboard navigation
---@field focusIndicator KeyboardNavigationFocusIndicatorConfig? -- Focus indicator style configuration
local KeyboardNavigationConfig = {}

--=====================================--
-- For FlexLove.init()
--=====================================--
---@class FlexLoveConfig
---@field baseScale {width:number?, height:number?}? -- Base resolution for responsive scaling (default: nil, no scaling)
---@field theme string|ThemeDefinition? -- Theme name (string) or ThemeDefinition to use (default: nil, no theme)
---@field immediateMode boolean? -- Enable immediate mode (React-like, recreates UI each frame) vs retained mode (default: false)
---@field autoFrameManagement boolean? -- Automatically call beginFrame/endFrame (default: false)
---@field stateRetentionFrames number? -- Number of frames to retain unused state in immediate mode (default: 60)
---@field maxStateEntries number? -- Maximum number of state entries before forcing cleanup (default: 1000)
---@field includeStackTrace boolean? -- Include stack traces in error messages (default: true)
---@field reportingLogLevel LOG_LEVEL? -- Error log level: 1: critical, 2: error, 3: warn, 4: info, 5: debug/all (default: 3:warn)
---@field errorLogTarget string? -- Error log target: "console", "file", "both" (default: "console")
---@field errorLogFile string? -- Path to error log file (default: "flexlove_errors.log")
---@field errorLogMaxSize number? -- Maximum error log file size in bytes (default: 1048576, 1MB)
---@field maxErrorLogFiles number? -- Maximum number of rotated error log files (default: 5)
---@field errorLogRotateEnabled boolean? -- Enable error log rotation (default: true)
---@field performanceMonitoring boolean? -- Enable performance monitoring (default: true)
---@field performanceHudKey string? -- Key to toggle performance HUD (default: "f3")
---@field performanceHudPosition {x:number, y:number}? -- Position of performance HUD (default: {x=10, y=10})
---@field performanceWarningThreshold number? -- Frame time warning threshold in ms (default: 13.0)
---@field performanceCriticalThreshold number? -- Frame time critical threshold in ms (default: 16.67)
---@field performanceLogToConsole boolean? -- Log performance metrics to console (default: false)
---@field performanceWarnings boolean? -- Enable performance warnings (default: false)
---@field memoryProfiling boolean? -- Enable memory profiling (default: false, auto-enabled in immediate mode)
---@field gcStrategy string? -- Garbage collection strategy: "auto", "periodic", "manual", "disabled" (default: "auto")
---@field gcMemoryThreshold number? -- Memory threshold in MB before forcing GC (default: 100)
---@field gcInterval number? -- Frames between GC steps in periodic mode (default: 60)
---@field gcStepSize number? -- Work units per GC step, higher = more aggressive (default: 200)
---@field immediateModeBlurOptimizations boolean? -- Cache blur canvases in immediate mode to avoid re-rendering each frame (default: true)
---@field keyboardNavigation boolean|KeyboardNavigationConfig? -- Enable keyboard navigation with defaults (`true`) or provide configuration overrides
---@field debugDraw boolean? -- Enable debug draw overlay showing element boundaries with random colors (default: false)
---@field debugDrawKey string? -- Key to toggle debug draw overlay at runtime (default: nil, no toggle key)
local FlexLoveConfig = {}

--=====================================--
-- Public FlexLove API
--=====================================--
---@alias TextAlignCompound "top-left" | "top-center" | "top-right" | "center-left" | "center-center" | "center-right" | "bottom-left" | "bottom-center" | "bottom-right"
---@alias TextAlignSpec TextAlign | TextAlignCompound | {horizontal: TextAlign, vertical: TextAlignVertical}

---@class FlexLoveEnums
---@field TextAlign TextAlign
---@field TextAlignVertical TextAlignVertical
---@field Positioning Positioning
---@field FlexDirection FlexDirection
---@field JustifyContent JustifyContent
---@field JustifySelf JustifySelf
---@field AlignItems AlignItems
---@field AlignSelf AlignSelf
---@field AlignContent AlignContent
---@field FlexWrap FlexWrap
---@field TextSize TextSize
---@field ImageRepeat ImageRepeat
---@field ARIA ARIA
local FlexLoveEnums = {}

---@class AnimationKeyframe
---@field at number -- Normalized time position (0-1)
---@field values table -- Property values at this keyframe
---@field easing string|EasingFunction? -- Easing used between this and the next keyframe
local AnimationKeyframe = {}

---@class AnimationGroupProps
---@field animations Animation[] -- Animations to coordinate
---@field mode "parallel"|"sequence"|"stagger"? -- Group playback mode (default: "parallel")
---@field stagger number? -- Delay between staggered animations in seconds (default: 0.1)
---@field onComplete fun(group:AnimationGroup)? -- Called when all animations complete
---@field onStart fun(group:AnimationGroup)? -- Called when the group starts
local AnimationGroupProps = {}

---@class AnimationGroup
---@field animations Animation[]
---@field mode "parallel"|"sequence"|"stagger"
---@field stagger number
---@field onComplete fun(group:AnimationGroup)?
---@field onStart fun(group:AnimationGroup)?
local AnimationGroup = {}

---@class Animation
---@field duration number
---@field start table
---@field final table
---@field elapsed number
---@field easing EasingFunction
---@field keyframes AnimationKeyframe[]?
---@field transform TransformProps?
---@field transition TransitionProps?
---@field onStart fun(animation:Animation, element:Element?)?
---@field onUpdate fun(animation:Animation, element:Element?, progress:number)?
---@field onComplete fun(animation:Animation, element:Element?)?
---@field onCancel fun(animation:Animation, element:Element?)?
---@field update fun(self:Animation, dt:number, element:table?): boolean
---@field findKeyframes fun(self:Animation, progress:number): AnimationKeyframe?, AnimationKeyframe?
---@field lerpKeyframes fun(self:Animation, prevFrame:AnimationKeyframe, nextFrame:AnimationKeyframe, easedT:number): table
---@field interpolate fun(self:Animation): table
---@field apply fun(self:Animation, element:table)
---@field pause fun(self:Animation)
---@field resume fun(self:Animation)
---@field isPaused fun(self:Animation): boolean
---@field reverse fun(self:Animation)
---@field isReversed fun(self:Animation): boolean
---@field setSpeed fun(self:Animation, speed:number)
---@field getSpeed fun(self:Animation): number
---@field seek fun(self:Animation, time:number)
---@field getState fun(self:Animation): string
---@field cancel fun(self:Animation, element:table?)
---@field reset fun(self:Animation)
---@field getProgress fun(self:Animation): number
---@field chain fun(self:Animation, nextAnimation:Animation|function): Animation
---@field delay fun(self:Animation, seconds:number): Animation
---@field repeatCount fun(self:Animation, count:number): Animation
---@field yoyo fun(self:Animation, enabled:boolean?): Animation
---@class AnimationModule
---@field Easing table<string, EasingFunction|fun(...):EasingFunction> -- Built-in easing functions and easing factories
---@field Transform table? -- Animation transform helpers exposed by the animation module
---@field Group AnimationGroup -- Animation group class table
---@field new fun(props:AnimationProps): Animation
---@field fade fun(duration:number, fromOpacity:number, toOpacity:number, easing:string?): Animation
---@field scale fun(duration:number, fromScale:{width:number, height:number}, toScale:{width:number, height:number}, easing:string?): Animation
---@field keyframes fun(props:{duration:number, keyframes:AnimationKeyframe[], onStart:function?, onUpdate:function?, onComplete:function?, onCancel:function?}): Animation
---@field chainSequence fun(animations:Animation[]): Animation
local AnimationModule = {}

---@class ColorInputTable
---@field [1] number?
---@field [2] number?
---@field [3] number?
---@field [4] number?
---@field r number?
---@field g number?
---@field b number?
---@field a number?
local ColorInputTable = {}

---@alias ColorInput string|Color|ColorInputTable

---@class ColorModule
---@field new fun(r:number?, g:number?, b:number?, a:number?): Color
---@field fromHex fun(hexWithTag:string): Color
---@field validateColorChannel fun(value:any, max:number?): boolean, number?
---@field validateHexColor fun(hex:string): boolean, string?
---@field validateRGBColor fun(r:number, g:number, b:number, a:number?, max:number?): boolean, string?
---@field isValidColorFormat fun(value:any): string?
---@field sanitizeColor fun(value:any, default:Color?): Color
---@field parse fun(value:any): Color
---@field lerp fun(colorA:Color, colorB:Color, t:number): Color
local ColorModule = {}

---@class ThemeManagerConfig
---@field theme string? -- Theme name override
---@field themeComponent string? -- Component name to resolve from the theme
---@field disabled boolean? -- Force disabled theme state
---@field active boolean? -- Force active theme state
---@field disableHighlight boolean? -- Disable pressed highlight overlay
---@field themeStateLock boolean|string? -- Lock the theme state to base/default or a named state
---@field themeComponentDisabledStates string[]? -- List of theme states to suppress visually
---@field scaleCorners number? -- Scale multiplier for 9-patch corners and edges
---@field scalingAlgorithm "nearest"|"bilinear"? -- Scaling algorithm for non-stretched theme regions
local ThemeManagerConfig = {}

---@class ThemeRegion
---@field x number
---@field y number
---@field w number
---@field h number
local ThemeRegion = {}

---@class ThemeComponent
---@field atlas string|love.Image?
---@field insets {left:number, top:number, right:number, bottom:number}?
---@field regions {topLeft:ThemeRegion, topCenter:ThemeRegion, topRight:ThemeRegion, middleLeft:ThemeRegion, middleCenter:ThemeRegion, middleRight:ThemeRegion, bottomLeft:ThemeRegion, bottomCenter:ThemeRegion, bottomRight:ThemeRegion}?
---@field stretch {horizontal:table<integer, string>, vertical:table<integer, string>}?
---@field states table<string, ThemeComponent>?
---@field contentAutoSizingMultiplier {width:number?, height:number?}?
---@field scaleCorners number?
---@field scalingAlgorithm "nearest"|"bilinear"?
---@field knobOffset number|{x:number, y:number}|{horizontal:number, vertical:number}?
local ThemeComponent = {}

---@class ThemeDefinition
---@field name string
---@field atlas string|love.Image?
---@field components table<string, ThemeComponent>
---@field scrollbars table<string, ThemeComponent>?
---@field colors table<string, Color>?
---@field fonts table<string, string>?
---@field contentAutoSizingMultiplier {width:number?, height:number?}?
local ThemeDefinition = {}

---@class Theme
---@field name string
---@field atlas love.Image?
---@field atlasData love.ImageData?
---@field components table<string, ThemeComponent>
---@field scrollbars table<string, ThemeComponent>
---@field colors table<string, Color>
---@field fonts table<string, string>
---@field contentAutoSizingMultiplier {width:number?, height:number?}?
---@class ThemeManager
---@field theme string?
---@field themeComponent string?
---@field disabled boolean
---@field active boolean
---@field disableHighlight boolean?
---@field themeStateLock boolean|string?
---@field themeComponentDisabledStates table<string, boolean>
---@field scaleCorners number?
---@field scalingAlgorithm "nearest"|"bilinear"?
---@field updateState fun(self:ThemeManager, isHovered:boolean, isPressed:boolean, isFocused:boolean, isDisabled:boolean): string
---@field getState fun(self:ThemeManager): string
---@field setState fun(self:ThemeManager, state:string)
---@field hasThemeComponent fun(self:ThemeManager): boolean
---@field getTheme fun(self:ThemeManager): Theme?
---@field getComponent fun(self:ThemeManager): ThemeComponent?
---@field getStateComponent fun(self:ThemeManager): ThemeComponent?
---@field getScrollbarComponent fun(self:ThemeManager, scrollbarName:string?): ThemeComponent?
---@field getStyle fun(self:ThemeManager, property:string): any?
---@field _getScaledContentPaddingForState fun(self:ThemeManager, state:string, borderBoxWidth:number, borderBoxHeight:number): table?
---@field getScaledContentPaddingForState fun(self:ThemeManager, state:string, borderBoxWidth:number, borderBoxHeight:number): table? -- deprecated, use getScaledContentPadding
---@field getScaledContentPadding fun(self:ThemeManager, borderBoxWidth:number, borderBoxHeight:number): table?
---@field getContentAutoSizingMultiplier fun(self:ThemeManager): table?
---@field getDefaultFontFamily fun(self:ThemeManager): string?
---@field setTheme fun(self:ThemeManager, themeName:string?, componentName:string?)
---@field validateThemeStateLock fun(self:ThemeManager): boolean
---@class Color
---@field r number
---@field g number
---@field b number
---@field a number
---@field toRGBA fun(self:Color): number, number, number, number
---@class ThemeModule
---@field Manager ThemeManager -- Theme manager class table
---@field new fun(definition:ThemeDefinition): Theme
---@field load fun(path:string): Theme?
---@field setActive fun(themeOrName:string|Theme)
---@field getActive fun(): Theme?
---@field getComponent fun(componentName:string, state:string?): ThemeComponent?
---@field getDefaultScrollbar fun(): ThemeComponent?
---@field getScrollbar fun(scrollbarName:string, state:string?): ThemeComponent?
---@field getFont fun(fontName:string): string?
---@field getColor fun(colorName:string): Color?
---@field hasActive fun(): boolean
---@field getRegisteredThemes fun(): table<string, Theme>
---@field getColorNames fun(): string[]
---@field getAllColors fun(): table<string, Color>
---@field getColorOrDefault fun(colorName:string, fallback:Color): Color
---@field get fun(themeName:string): Theme?
---@field validateTheme fun(theme:table?, options:table?): boolean, table
---@field sanitizeTheme fun(theme:table?): table
local ThemeModule = {}

---@class FlexLove
---@field _VERSION string
---@field _DESCRIPTION string
---@field _URL string
---@field _LICENSE string
---@field Animation AnimationModule?
---@field Color ColorModule
---@field Theme ThemeModule?
---@field enums FlexLoveEnums
---@field isReady fun(): boolean
---@field init fun(config:FlexLoveConfig?)
---@field setKeyboardNavigationDebug fun(enabled:boolean)
---@field enableKeyboardNavigation fun(config:KeyboardNavigationConfig?)
---@field deferCallback fun(callback:function)
---@field executeDeferredCallbacks fun()
---@field resize fun()
---@field setMode fun(mode:"immediate"|"retained")
---@field getMode fun(): "immediate"|"retained"
---@field beginFrame fun()
---@field endFrame fun()
---@field draw fun(gameDrawFunc:function|nil, postDrawFunc:function|nil)
---@field getElementAtPosition fun(x:number, y:number): Element?
---@field update fun(dt:number)
---@field collectGarbage fun(mode:string?, stepSize:number?): number?
---@field setGCStrategy fun(strategy:"auto"|"periodic"|"manual"|"disabled")
---@field getGCStats fun(): GCStats
---@field textinput fun(text:string)
---@field keypressed fun(key:string, scancode:string, isrepeat:boolean)
---@field wheelmoved fun(dx:number, dy:number)
---@field touchpressed fun(id:lightuserdata, x:number, y:number, dx:number, dy:number, pressure:number)
---@field touchmoved fun(id:lightuserdata, x:number, y:number, dx:number, dy:number, pressure:number)
---@field touchreleased fun(id:lightuserdata, x:number, y:number, dx:number, dy:number, pressure:number)
---@field getActiveTouchCount fun(): number
---@field getTouchOwner fun(touchId:string): Element?
---@field getById fun(id:string): Element?
---@field destroy fun()
---@field new fun(props:ElementProps, callback:function?): Element?
---@field getStateCount fun(): number
---@field clearState fun(id:string)
---@field clearAllStates fun()
---@field getStateStats fun(): table
---@field calc fun(expr:string): CalcObject
---@field getFocusedElement fun(): Element?
---@field setFocusedElement fun(element:Element?)
---@field clearFocus fun()
---@field setDebugDraw fun(enabled:boolean)
---@field getDebugDraw fun(): boolean
local FlexLove = {}

--=====================================--
-- For State Persistence
--=====================================--
---@class ElementStateData
---@field _focused boolean?
---@field eventHandler table? -- EventHandler state
---@field textEditor table? -- TextEditor state
---@field scrollManager table? -- ScrollManager state
---@field blur BlurCacheData? -- Blur cache invalidation data

---@class BlurCacheData
---@field _blurX number
---@field _blurY number
---@field _blurWidth number
---@field _blurHeight number
---@field _backdropBlurRadius number?
---@field _backdropBlurQuality number?
---@field _contentBlurRadius number?
---@field _contentBlurQuality number?

--=====================================--
-- For Calc.lua
--=====================================--
---@class CalcDependencies
---@field ErrorHandler ErrorHandler? -- Error handler module

---@class CalcToken
---@field type string -- Token type: "NUMBER", "UNIT", "PLUS", "MINUS", "MULTIPLY", "DIVIDE", "LPAREN", "RPAREN", "EOF"
---@field value number? -- Numeric value (for NUMBER tokens)
---@field unit string? -- Unit type: "px", "%", "vw", "vh" (for NUMBER tokens)

---@class CalcASTNode
---@field type string -- Node type: "number", "add", "subtract", "multiply", "divide"
---@field value number? -- Numeric value (for "number" nodes)
---@field unit string? -- Unit type (for "number" nodes)
---@field left CalcASTNode? -- Left operand (for operator nodes)
---@field right CalcASTNode? -- Right operand (for operator nodes)

---@class CalcObject
---@field _isCalc boolean -- Marker to identify calc objects (always true)
---@field _expr string -- Original expression string
---@field _ast CalcASTNode? -- Parsed abstract syntax tree (nil if parsing failed)
---@field _error string? -- Error message if parsing failed

--=====================================--
-- For FlexLove.lua Internals
--=====================================--
---@class GCConfig
---@field strategy string -- "auto", "periodic", "manual", or "disabled"
---@field memoryThreshold number -- MB before forcing GC
---@field interval number -- Frames between GC steps (for periodic mode)
---@field stepSize number -- Work units per GC step (higher = more aggressive)

---@class GCState
---@field framesSinceLastGC number -- Frames elapsed since last GC
---@field lastMemory number -- Last recorded memory usage in MB
---@field gcCount number -- Total number of GC operations performed

---@class GCStats
---@field gcCount number -- Total number of GC operations performed
---@field framesSinceLastGC number -- Frames elapsed since last GC
---@field currentMemoryMB number -- Current memory usage in MB
---@field strategy string -- Current GC strategy
---@field threshold number -- Memory threshold in MB

---@class FlexLoveDependencies
---@field Context table -- Context module
---@field Theme Theme? -- Theme module
---@field Color Color -- Color module
---@field Calc Calc -- Calc module
---@field Units table -- Units module
---@field Blur table? -- Blur module
---@field ImageRenderer table? -- ImageRenderer module
---@field ImageScaler table? -- ImageScaler module
---@field NinePatch table? -- NinePatch module
---@field RoundedRect table -- RoundedRect module
---@field ImageCache table? -- ImageCache module
---@field utils table -- Utils module
---@field Grid table -- Grid module
---@field InputEvent table -- InputEvent module
---@field GestureRecognizer table? -- GestureRecognizer module
---@field StateManager StateManager -- StateManager module
---@field TextEditor table -- TextEditor module
---@field LayoutEngine LayoutEngine -- LayoutEngine module
---@field Renderer table -- Renderer module
---@field EventHandler EventHandler -- EventHandler module
---@field ScrollManager table -- ScrollManager module
---@field ErrorHandler ErrorHandler -- ErrorHandler module
---@field Performance Performance? -- Performance module
---@field Transform table? -- Transform module
