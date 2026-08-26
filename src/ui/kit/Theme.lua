-- High-contrast theme for the launcher (src/import/LauncherView.lua).  The
-- save editor keeps its own tools/save-editor/Theme.lua, whose primitives
-- take a radius where these take a colour -- do not cross-wire them.  This
-- replaces the old navy gradient look wholesale: a near-black field with the
-- faintest red cast, cards a few values above it, white hairline outlines,
-- flat fills, no gradients and no glows anywhere.
--
-- That is not only a visual choice.  Every effect this theme drops was a GPU
-- pipeline flush in the old renderer:
--   * gradients needed a stencil pass + a dynamic mesh per card
--     (G.stencil / setStencilTest / draw(mesh) = 3 state changes per card),
--   * glows set blend mode "add", drew 7 stacked rects, then set it back.
-- Flat fills with a 1px outline all share one pipeline state, so LOVE batches
-- an entire panel into a couple of draw calls.  What this theme DOES pay for
-- is extra vertices at the same pipeline state: rounded corners, the
-- two-rect emboss on a control, and the three stacked rounded rects that make
-- a card's drop shadow (Theme.shadow).  Vertices are the tier of expense this
-- theme is willing to pay; the tier above it -- stencils, meshes, blend-mode
-- changes, canvases, shaders -- is the one it will not, and a shadow drawn as
-- a blurred canvas would land squarely in it.
--
-- Emphasis is carried by INVERSION, not by colour weight: a selected or
-- focused control fills white and prints black.  That keeps contrast at
-- maximum for accessibility and costs exactly one extra rect.
--
-- Every colour below is 0-255 RGB; alpha is passed per draw call to col().
-- Everything degrades under the headless love_stub used by tests/ (no fonts,
-- no line, no mesh): each primitive probes for what it needs.

local Theme = {}

local PAL = {
  -- field + surfaces.  The field carries a FAINT red cast (a few points of
  -- red over an otherwise neutral near-black) and cards sit a few steps above
  -- it in the same hue, so a card reads as a raised object rather than as an
  -- outline drawn on the page.  These are still flat fills -- the depth comes
  -- from the value step plus Theme.shadow, not from a gradient.
  field       = { 20, 20, 20 },     -- the page BEHIND the cards
  bg          = { 20, 20, 20 },       -- light black
  surface     = { 28, 21, 24 },    -- card interiors
  rowBg       = { 20, 14, 17 },    -- rows inside a card, one step below it
  raised      = { 44, 34, 38 },    -- hover feedback
  ink         = { 255, 255, 255 }, -- the selected/focused fill
  -- outlines.  Two weights only: a hairline for structure, solid for focus.
  line        = { 255, 255, 255 }, -- hairline, drawn at alpha 0.35
  lineStrong  = { 255, 255, 255 }, -- focus / selection, drawn at alpha 1
  -- text
  heading     = { 255, 255, 255 },
  text        = { 255, 255, 255 },
  detail      = { 200, 200, 200 },
  muted       = { 150, 150, 150 },
  caption     = { 170, 170, 170 }, -- letterspaced section captions
  faint       = { 110, 110, 110 }, -- slot indices, hints
  inverse     = { 0, 0, 0 },       -- ink on a white (selected/focused) fill
  -- semantics.  Used for TEXT and OUTLINES only, never as a large fill, so
  -- the black/white contrast story is never diluted.
  green       = { 0, 255, 140 },   -- safe / confirmed / installed
  yellow      = { 255, 214, 0 },   -- attention / update available
  red         = { 255, 80, 90 },   -- destructive
  blue        = { 90, 190, 255 },  -- links, in-panel navigation
  steel       = { 120, 120, 120 }, -- disabled
  -- the version rail is the one piece of brand colour that stays
  railRed     = { 255, 60, 72 },
  railBlue    = { 70, 150, 255 },
  railGold    = { 255, 203, 5 },   -- Yellow cartridge (bright)
  railAmber   = { 218, 145, 32 },  -- Gold cartridge (deeper metal)
  railSilver  = { 190, 198, 210 }, -- Silver cartridge (cool light metal)
  railCrystal = { 132, 196, 228 }, -- Crystal cartridge (translucent ice blue)
}
-- Semantic aliases kept so ported call sites read the same as before.
PAL.cardBorder = PAL.line
PAL.greenInk   = PAL.inverse
PAL.blueInk    = PAL.blue
PAL.redSoft    = PAL.red
PAL.greenDark  = PAL.green
Theme.PAL = PAL

-- Standard alphas, so "hairline" means one thing everywhere.
Theme.A = {
  hairline = 0.35,
  hover    = 0.65,
  focus    = 1.0,
  fillHover= 1.0,
  disabled = 0.30,
}

Theme.BUTTON = {
  radius = 8,
  ringPad = 2,
  ringWidth = 2,
  labelInset = 16,
  labelPad = 10,
  iconPad = 0.24,
  letterGap = 4,
  disabledA = 0.45,
  embossHot = 1.3,
  embossRest = 1,
  embossDisabled = 0.4,
  glowHz = 3,
  glowBase = 0.25,
  glowAmp = 0.75,
  iconRestA = 0.85,
}

Theme.CARD = {
  radius = 14,
  shadow = true,
  fill = PAL.surface,
  fillA = 1,
  stroke = PAL.line,
  strokeA = Theme.A.hairline,
}

Theme.CARD_VARIANT = {
  emphasis = { strokeA = Theme.A.focus },
  muted = {
    fill = PAL.bg, fillA = 0.8, stroke = PAL.muted, strokeA = 0.25, shadow = false,
  },
  mutedHot = {
    fill = PAL.bg, fillA = 0.8, stroke = PAL.muted, strokeA = Theme.A.hover, shadow = false,
  },
  empty = { fillA = 0, strokeA = 0.22, shadow = false, radius = "ctl" },
  warn = {
    fill = PAL.rowBg, stroke = PAL.yellow, strokeA = Theme.A.hover,
    shadow = false, radius = "ctl",
  },
  row = {
    fill = PAL.rowBg, stroke = PAL.line, strokeA = Theme.A.hairline,
    shadow = false, radius = "ctl",
  },
  rowHover = {
    fill = PAL.raised, stroke = PAL.line, strokeA = Theme.A.hover,
    shadow = false, radius = "ctl",
  },
  rowSelected = {
    fill = PAL.ink, strokeA = 0, shadow = false, radius = "ctl",
  },
  hairline = {
    fillA = 0, stroke = PAL.line, strokeA = Theme.A.hairline,
    shadow = false, radius = "ctl",
  },
  badge = {
    fill = PAL.bg, stroke = PAL.yellow, strokeA = Theme.A.hover,
    shadow = false, radius = 0,
  },
}

local G = love and love.graphics or nil

local has = {}
local function probe(name)
  if has[name] == nil then has[name] = (G and type(G[name]) == "function") or false end
  return has[name]
end
Theme.probe = probe

function Theme.col(c, a)
  if not G then return end
  G.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1)
end
local col = Theme.col

function Theme.clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end
local clamp = Theme.clamp

-- --------------------------------------------------------------- primitives
-- Square, flat, snapped to whole pixels.  Snapping matters at 1px line width:
-- a rect on a half pixel renders as a 2px grey smear instead of a crisp white
-- hairline, which is the whole look.
local function snap(v) return math.floor(v + 0.5) end
Theme.snap = snap

function Theme.fill(x, y, w, h, c, a)
  if not G or w <= 0 or h <= 0 then return end
  col(c or PAL.bg, a or 1)
  G.rectangle("fill", snap(x), snap(y), snap(w), snap(h))
end

-- Corner radius for controls.  Fixed rather than scaled: LOVE tessellates a
-- rounded rect by radius, so a scale-driven radius would change the vertex
-- count with the window size, and these are the two tiers the design needs.
-- Controls get the smaller one, containers the larger, so a button never
-- looks like a card and a card never looks like a button.
function Theme.radius()
  return Theme.BUTTON.radius
end

function Theme.cardRadius()
  return Theme.CARD.radius
end

-- DROP SHADOW.  Three stacked rounded rects at low alpha, each one step wider
-- and one step lower than the last -- a cheap falloff that needs no blur, no
-- canvas and no blend-mode change, so it stays inside the pipeline budget the
-- rest of this file is written to.  Drawn BEFORE the surface it belongs to,
-- and never for a control (only containers cast one, or the whole screen
-- reads as floating debris).
function Theme.shadow(x, y, w, h, r)
  if not G or w <= 0 or h <= 0 then return end
  r = r or Theme.cardRadius()
  for i = 1, 3 do
    local spread = i * 2
    col(PAL.bg, 0.13)
    G.rectangle("fill", snap(x - spread), snap(y - spread + i * 3),
      snap(w + 2 * spread), snap(h + 2 * spread), r + spread, r + spread)
  end
end

function Theme.fillRounded(x, y, w, h, c, a, r)
  if not G or w <= 0 or h <= 0 then return end
  r = r or Theme.radius()
  col(c or PAL.bg, a or 1)
  G.rectangle("fill", snap(x), snap(y), snap(w), snap(h), r, r)
end

function Theme.strokeRounded(x, y, w, h, c, a, lw, r)
  if not G or w <= 0 or h <= 0 then return end
  lw = lw or 1
  r = r or Theme.radius()
  if probe("setLineWidth") then G.setLineWidth(lw) end
  col(c or PAL.line, a or Theme.A.hairline)
  G.rectangle("line", snap(x) + lw / 2, snap(y) + lw / 2,
    snap(w) - lw, snap(h) - lw, r, r)
  if probe("setLineWidth") then G.setLineWidth(1) end
end

-- EMBOSS.  A lit top edge and a shaded bottom edge inside the control, which
-- is what makes a flat fill read as a raised key.  Two thin rects on top of
-- the fill -- no gradient mesh, no stencil, no blend-mode change, so it costs
-- the same pipeline state as everything around it.
function Theme.emboss(x, y, w, h, strength)
  if not G or w <= 2 or h <= 2 then return end
  strength = strength or 1
  local t = math.max(1, math.floor(h * 0.10))
  -- The inset must clear the corner arc, but a narrow control (a stepper, a
  -- row chip) is thinner than two radii -- clamp or the highlight rect goes
  -- negative-width and vanishes.
  local r = math.min(Theme.radius(), math.floor(w / 3))
  -- highlight along the top
  col(PAL.ink, 0.28 * strength)
  G.rectangle("fill", snap(x) + r, snap(y) + 1, snap(w) - 2 * r, t)
  -- shadow along the bottom
  col(PAL.bg, 0.30 * strength)
  G.rectangle("fill", snap(x) + r, snap(y + h) - t - 1, snap(w) - 2 * r, t)
end

-- Faux bold: the UI face ships in one weight, so a bold run is the same text
-- drawn a second time one pixel across.  Callers do this only for button
-- labels, where the extra draw is bounded by the number of controls on
-- screen and the text is already a cached Text object.
Theme.BOLD_OFFSET = 1

-- A 1px outline drawn INSIDE the rect, so a bordered control never bleeds
-- into its neighbour's pixel and adjacent outlines never double up to 2px.
function Theme.stroke(x, y, w, h, c, a, lw)
  if not G or w <= 0 or h <= 0 then return end
  lw = lw or 1
  if probe("setLineWidth") then G.setLineWidth(lw) end
  col(c or PAL.line, a or Theme.A.hairline)
  G.rectangle("line", snap(x) + lw / 2, snap(y) + lw / 2,
    snap(w) - lw, snap(h) - lw)
  if probe("setLineWidth") then G.setLineWidth(1) end
end

-- The design's only container: a rounded surface a few values above the
-- field, its own drop shadow, and a white hairline.  `emphasis` raises the
-- outline to full white (used for the focused/active card).
function Theme.card(x, y, w, h, variant)
  local spec = Theme.CARD
  local v
  if variant == true then
    v = Theme.CARD_VARIANT.emphasis
  elseif type(variant) == "string" then
    v = Theme.CARD_VARIANT[variant]
  elseif type(variant) == "table" then
    v = variant
  end
  local radius = (v and v.radius) or spec.radius
  if radius == "ctl" then radius = Theme.BUTTON.radius end
  local fill = (v and v.fill) or spec.fill
  local fillA = spec.fillA
  if v and v.fillA ~= nil then fillA = v.fillA end
  local stroke = (v and v.stroke) or spec.stroke
  local strokeA = spec.strokeA
  if v and v.strokeA ~= nil then strokeA = v.strokeA end
  local shadow = spec.shadow
  if v and v.shadow ~= nil then shadow = v.shadow end
  local strokeW = (v and v.strokeW) or 1
  if fillA > 0 and fill then
    if shadow then Theme.shadow(x, y, w, h, radius) end
    Theme.fillRounded(x, y, w, h, fill, fillA, radius)
  end
  if strokeA > 0 and stroke then
    Theme.strokeRounded(x, y, w, h, stroke, strokeA, strokeW, radius)
  end
end

function Theme.row(x, y, w, h, state)
  if state == "selected" then
    Theme.card(x, y, w, h, "rowSelected")
    return PAL.inverse
  end
  Theme.card(x, y, w, h, state == "hover" and "rowHover" or "row")
  return PAL.text
end

-- A percentage meter (HP, box fill, dex completion, import progress).
-- pct is 0-100.  Outline + solid fill, rounded to the track's own half-height
-- so a thin bar reads as a capsule instead of a clipped rectangle.
function Theme.meter(x, y, w, h, pct, c)
  if not G then return end
  local r = math.min(Theme.radius(), h / 2)
  Theme.strokeRounded(x, y, w, h, PAL.line, Theme.A.hairline, 1, r)
  local fill = (w - 2) * clamp((pct or 0) / 100, 0, 1)
  if fill > 0 then
    Theme.fillRounded(x + 1, y + 1, fill, h - 2, c or PAL.ink, 1,
      math.min(r, fill / 2))
  end
end

-- The 4px version rail across the top of both windows: the only brand
-- colour on screen (Red / Blue / Yellow / Gold / Silver / Crystal cartridge
-- colours).
function Theme.versionRail(x, y, w, h)
  if not G then return end
  local bars = {
    PAL.railRed, PAL.railBlue, PAL.railGold, PAL.railAmber, PAL.railSilver,
    PAL.railCrystal,
  }
  local seg = w / #bars
  for i, c in ipairs(bars) do
    Theme.fill(x + (i - 1) * seg, y, seg, h, c, 1)
  end
end

-- ------------------------------------------------------------------- text
-- Letterspaced caption text.  The UI font has no tracking control, so this
-- advances glyph by glyph; captions are short by construction.
-- Measuring never throws.  Third-party strings (mod names from an index,
-- translated captions) reach these primitives unvalidated.
local function safeWidthOrZero(font, s)
  local ok, w = pcall(font.getWidth, font, s)
  return ok and w or 0
end

-- Steps CODEPOINTS, not bytes: a translated caption (the JP strings) is
-- multi-byte, and printing half a sequence is a "UTF-8 decoding error" that
-- takes the frame down.
local function eachChar(text, fn)
  local i = 1
  local n = #text
  while i <= n do
    local j = i + 1
    while j <= n do
      local b = text:byte(j)
      if b < 0x80 or b >= 0xC0 then break end
      j = j + 1
    end
    fn(text:sub(i, j - 1))
    i = j
  end
end

function Theme.spaced(font, text, x, y, spacing)
  if not G or not font then return 0 end
  local cx = x
  eachChar(tostring(text), function(ch)
    pcall(G.print, ch, cx, y)
    cx = cx + safeWidthOrZero(font, ch) + spacing
  end)
  return math.max(0, cx - x - spacing)
end

function Theme.spacedWidth(font, text, spacing)
  if not font then return 0 end
  local w = 0
  eachChar(tostring(text), function(ch)
    w = w + safeWidthOrZero(font, ch) + spacing
  end)
  return math.max(0, w - spacing)
end

-- UTF-8 stepping.  Truncation MUST move whole codepoints: LOVE's Font:getWidth
-- raises "UTF-8 decoding error" on a string cut through a multi-byte sequence,
-- and a launcher listing mods with non-ASCII names (the JP index) hits that on
-- the first frame.  A continuation byte is 10xxxxxx (0x80..0xBF).
local function prevCharStart(s, i)
  -- largest j < i where s:byte(j) starts a codepoint
  local j = i - 1
  while j > 1 do
    local b = s:byte(j)
    if b < 0x80 or b >= 0xC0 then break end
    j = j - 1
  end
  return j
end

local function nextCharStart(s, i)
  local j = i + 1
  while j <= #s do
    local b = s:byte(j)
    if b < 0x80 or b >= 0xC0 then break end
    j = j + 1
  end
  return j
end

-- Width that never throws on malformed input: a mod name can carry anything.
local function safeWidth(font, s)
  local ok, w = pcall(font.getWidth, font, s)
  return ok and w or math.huge
end
Theme.safeWidth = safeWidth

-- Clip text to a pixel width with a trailing ellipsis.  Results are memoised
-- per (font, text, width) in Kit's measurement cache -- this function is the
-- single hottest string operation in a list-heavy frame, and it is O(n) in
-- glyphs with a getWidth call per step.
function Theme.ellipsize(font, text, maxW)
  text = tostring(text or "")
  if not font then return text end
  -- A non-positive budget means "nothing fits", not "everything fits".
  if maxW <= 0 then return "" end
  if safeWidth(font, text) <= maxW then return text end
  local ell = "..."
  local ew = safeWidth(font, ell)
  local last = #text + 1              -- one past the end of the kept prefix
  while last > 1 do
    last = prevCharStart(text, last)
    local head = text:sub(1, last - 1)
    if safeWidth(font, head) + ew <= maxW then return head .. ell end
  end
  return ell
end

-- Save paths truncate from the LEFT so the filename survives.
function Theme.ellipsizeLeft(font, text, maxW)
  text = tostring(text or "")
  if not font then return text end
  if maxW <= 0 then return "" end
  if safeWidth(font, text) <= maxW then return text end
  local ell = "..."
  local ew = safeWidth(font, ell)
  local i = 1
  while i <= #text do
    i = nextCharStart(text, i)
    local tail = text:sub(i)
    if safeWidth(font, tail) + ew <= maxW then return ell .. tail end
  end
  return ell
end

-- The background: one flat clear to the faintly red-cast field colour.  One
-- call, no mesh, no fan, no allocation -- the old radial field built a
-- 66-vertex mesh EVERY frame.  The tint is deliberately small (a handful of
-- points of red at near-black): enough that the cards read as sitting ON
-- something, not enough to compete with the tri-colour rail for brand duty.
function Theme.field()
  if not G then return end
  G.clear(PAL.field[1] / 255, PAL.field[2] / 255, PAL.field[3] / 255, 1)
end

-- ------------------------------------------------------------------- fonts
-- Font set, rebuilt only when the scale changes.  Sizes are integers by
-- construction: fractional sizes measure and render at different widths,
-- which is what made ported launcher text overrun its measured box.
function Theme.fonts(s)
  if not probe("newFont") then return {} end
  -- Every face goes through UiFont.attach, which hangs a kana/CJK fallback
  -- off it.  Without that a translated build renders the entire launcher as
  -- tofu boxes -- LOVE's default face is Latin-only.
  local UiFont
  local okUi, mod = pcall(require, "src.render.UiFont")
  if okUi then UiFont = mod end
  local cache = {}
  local function f(px)
    local n = math.max(8, math.floor(px + 0.5))
    if not cache[n] then
      local face = G.newFont(n)
      if UiFont and UiFont.attach then
        local ok, attached = pcall(UiFont.attach, face, n)
        if ok and attached then face = attached end
      end
      cache[n] = face
    end
    return cache[n]
  end
  return {
    scale     = s,
    wordmark  = f(14 * s),
    brand     = f(11 * s),
    chip      = f(11 * s),
    tile      = f(13 * s),
    tab       = f(13 * s),
    button    = f(14 * s),
    small     = f(12 * s),
    tiny      = f(11 * s),
    micro     = f(10 * s),
    caption   = f(12 * s),
    mono      = f(12 * s),
    monoRow   = f(13 * s),
    monoBig   = f(18 * s),
    title     = f(24 * s),
    headline  = f(26 * s),
    stat      = f(19 * s),
  }
end

return Theme
