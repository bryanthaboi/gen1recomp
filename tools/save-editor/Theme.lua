-- Shared look for the save editor: the launcher's palette and its drawing
-- primitives, lifted out so the editor and src/import/RomImporter.lua render
-- the same navy field, the same 16px translucent cards and the same neon
-- accents.  The editor is reachable straight off a launcher save row (Edit),
-- so the two windows have to read as one app -- see SaveEditor.dc.html, which
-- is the design spec these literals come from.
--
-- Every colour below is 0-255 RGB; alpha is passed per draw call to col().
--
-- Everything here degrades when a love.graphics entry point is missing: the
-- headless love_stub used by tests/ has no fonts, stencil, mesh or line, so
-- each primitive checks for its dependency and falls back to a flat fill (or
-- nothing) rather than erroring.  That keeps App.draw callable under the stub.

local Theme = {}

local PAL = {
  -- radial background field: bright navy at top-centre -> near black
  bgTop       = { 22, 34, 74 },    -- #16224a
  bgMid       = { 12, 19, 48 },    -- #0c1330
  bgBot       = { 7, 11, 29 },     -- #070b1d
  -- panel + row surfaces
  cardTint    = { 70, 150, 255 },  -- rgba(70,150,255,0.08) card top light
  cardBody    = { 12, 18, 40 },    -- rgba(12,18,40,0.5)   card interior
  cardBorder  = { 120, 150, 220 }, -- rgba(120,150,220,0.28) hairline
  rowBg       = { 9, 14, 34 },     -- rgba(9,14,34,0.60)   row interior
  -- text
  heading     = { 255, 255, 255 },
  text        = { 223, 230, 245 }, -- #dfe6f5
  detail      = { 198, 208, 230 }, -- #c6d0e6
  muted       = { 159, 176, 208 }, -- #9fb0d0
  caption     = { 143, 163, 200 }, -- #8fa3c8  letterspaced section captions
  faint       = { 111, 130, 168 }, -- #6f82a8  slot indices, hints
  -- semantics: green = safe/confirmed, yellow = attention, red = destructive
  green       = { 62, 224, 138 },  -- #3ee08a
  greenDark   = { 22, 163, 90 },   -- #16a35a
  greenInk    = { 6, 32, 18 },     -- #062012
  yellow      = { 255, 203, 5 },   -- #ffcb05
  red         = { 255, 92, 103 },  -- #ff5c67
  redSoft     = { 255, 143, 150 }, -- #ff8f96  destructive button ink
  blue        = { 70, 150, 255 },  -- #4696ff
  blueInk     = { 207, 224, 255 }, -- #cfe0ff  ink on blue-tinted controls
  steel       = { 149, 161, 189 }, -- #95a1bd  disabled
  -- the tri-colour version rail, identical to the launcher's
  railRed     = { 255, 60, 72 },
  railBlue    = { 70, 150, 255 },
  railGold    = { 255, 203, 5 },
  -- chip / tab tile gradient (the launcher's mod chip)
  chipTop     = { 61, 74, 109 },   -- #3d4a6d
  chipBot     = { 32, 42, 69 },    -- #202a45
  chipInk     = { 207, 224, 255 }, -- #cfe0ff
}
Theme.PAL = PAL

local G = love and love.graphics or nil

-- Feature probes: the headless stub implements only a handful of these.
local has = {}
local function probe(name)
  if has[name] == nil then has[name] = (G and type(G[name]) == "function") or false end
  return has[name]
end

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

-- ---------------------------------------------------------------- gradients
-- One reusable unit-square mesh whose four corner colours are rewritten per
-- call, so a vertical gradient costs a single draw (same trick the launcher
-- uses).  Nil under the stub, where every gradient degrades to a flat fill.
local gradMesh
local function setGrad(cTop, cBot, aTop, aBot)
  if not probe("newMesh") then return false end
  if not gradMesh then
    gradMesh = G.newMesh({
      { 0, 0, 0, 0, 1, 1, 1, 1 },
      { 1, 0, 1, 0, 1, 1, 1, 1 },
      { 1, 1, 1, 1, 1, 1, 1, 1 },
      { 0, 1, 0, 1, 1, 1, 1, 1 },
    }, "fan", "dynamic")
  end
  local t = { cTop[1] / 255, cTop[2] / 255, cTop[3] / 255, aTop }
  local b = { cBot[1] / 255, cBot[2] / 255, cBot[3] / 255, aBot }
  gradMesh:setVertexAttribute(1, 3, t[1], t[2], t[3], t[4])
  gradMesh:setVertexAttribute(2, 3, t[1], t[2], t[3], t[4])
  gradMesh:setVertexAttribute(3, 3, b[1], b[2], b[3], b[4])
  gradMesh:setVertexAttribute(4, 3, b[1], b[2], b[3], b[4])
  return true
end

-- Vertical gradient clipped to a rounded rect.  Falls back to a flat fill of
-- the bottom colour when the stencil buffer or meshes are unavailable.
function Theme.gradRounded(x, y, w, h, r, cTop, cBot, aTop, aBot)
  if not G then return end
  if w <= 0 or h <= 0 then return end
  if not (probe("stencil") and probe("setStencilTest") and setGrad(cTop, cBot, aTop, aBot)) then
    col(cBot, aBot)
    G.rectangle("fill", x, y, w, h, r, r)
    return
  end
  G.stencil(function() G.rectangle("fill", x, y, w, h, r, r) end, "replace", 1)
  G.setStencilTest("greater", 0)
  G.setColor(1, 1, 1, 1)
  G.draw(gradMesh, x, y, 0, w, h)
  G.setStencilTest()
end

-- The design's standard content panel: a faint top-lit blue tint fading into
-- a dark interior behind a 1px cool-gray hairline.  Every card in the editor
-- (and every card in the launcher) is this shape.
function Theme.card(x, y, w, h, r)
  if not G then return end
  r = r or 16
  Theme.gradRounded(x, y, w, h, r, PAL.cardTint, PAL.cardBody, 0.08, 0.5)
  Theme.stroke(x, y, w, h, r, PAL.cardBorder, 0.28, 1)
end

-- A list row / inner surface: flat dark fill, fainter hairline than a card.
function Theme.row(x, y, w, h, r, alpha)
  if not G then return end
  col(PAL.rowBg, alpha or 0.6)
  G.rectangle("fill", x, y, w, h, r or 12, r or 12)
  Theme.stroke(x, y, w, h, r or 12, PAL.cardBorder, 0.22, 1)
end

function Theme.stroke(x, y, w, h, r, c, a, lw)
  if not G then return end
  if probe("setLineWidth") then G.setLineWidth(math.max(1, lw or 1)) end
  col(c, a or 1)
  G.rectangle("line", x, y, w, h, r or 0, r or 0)
  if probe("setLineWidth") then G.setLineWidth(1) end
end

-- Soft additive halo around a rounded rect (LOVE has no blur, so stack
-- progressively larger, fainter rects).  Marks the selected party slot and
-- the hot Save button.
function Theme.glow(x, y, w, h, r, c, strength)
  if not G or not probe("setBlendMode") then return end
  strength = math.max(0, strength or 0)
  if strength == 0 then return end
  G.setBlendMode("add")
  local layers = 7
  for i = 1, layers do
    local g = i * 2.2
    G.setColor(c[1] / 255, c[2] / 255, c[3] / 255,
      strength * 0.05 * (1 - (i - 1) / layers))
    G.rectangle("fill", x - g, y - g, w + 2 * g, h + 2 * g, r + g, r + g)
  end
  G.setBlendMode("alpha")
end

-- Dashed rounded outline (LOVE has no dash pattern): sample the path into a
-- polyline, then walk it toggling on/off.  Used for empty-state boxes and the
-- "add here" slots in the box grid.  Caller sets colour + line width.
function Theme.dashed(x, y, w, h, r, dash, gap)
  if not G or not probe("line") then return end
  if w <= 0 or h <= 0 then return end
  r = math.min(r, w / 2, h / 2)
  local seg = 4
  local pts = {}
  local function arc(cx, cy, a0, a1)
    for i = 0, seg do
      local a = a0 + (a1 - a0) * (i / seg)
      pts[#pts + 1] = cx + math.cos(a) * r
      pts[#pts + 1] = cy + math.sin(a) * r
    end
  end
  arc(x + w - r, y + r, -math.pi / 2, 0)
  arc(x + w - r, y + h - r, 0, math.pi / 2)
  arc(x + r, y + h - r, math.pi / 2, math.pi)
  arc(x + r, y + r, math.pi, math.pi * 1.5)
  pts[#pts + 1] = pts[1]; pts[#pts + 1] = pts[2]
  local remaining, drawing = dash, true
  for i = 1, #pts - 2, 2 do
    local x1, y1 = pts[i], pts[i + 1]
    local dx, dy = pts[i + 2] - x1, pts[i + 3] - y1
    local segLen = math.sqrt(dx * dx + dy * dy)
    local pos = 0
    while pos < segLen do
      local step = math.min(remaining, segLen - pos)
      if drawing then
        local t0, t1 = pos / segLen, (pos + step) / segLen
        G.line(x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1)
      end
      pos = pos + step
      remaining = remaining - step
      if remaining <= 0.0001 then
        drawing = not drawing
        remaining = drawing and dash or gap
      end
    end
  end
end

-- Letterspaced text: the UI font has no tracking control, so advance glyph by
-- glyph.  Section captions are 12px/2px-tracked uppercase throughout.
function Theme.spaced(font, text, x, y, spacing)
  if not G or not font then return 0 end
  local cx = x
  for i = 1, #text do
    local ch = text:sub(i, i)
    G.print(ch, cx, y)
    cx = cx + font:getWidth(ch) + spacing
  end
  return math.max(0, cx - x - spacing)
end

function Theme.spacedWidth(font, text, spacing)
  if not font then return 0 end
  local w = 0
  for i = 1, #text do w = w + font:getWidth(text:sub(i, i)) + spacing end
  return math.max(0, w - spacing)
end

-- Clip text to a pixel width with a trailing ellipsis.  Save paths truncate
-- from the LEFT instead (see Theme.ellipsizeLeft) so the filename survives.
function Theme.ellipsize(font, text, maxW)
  text = tostring(text or "")
  if not font then return text end
  -- A non-positive budget means "nothing fits", not "everything fits": the
  -- old early-out returned the whole string, which is how a phone-width
  -- status bar ended up with two lines of text stacked on top of each other
  -- (#715).
  if maxW <= 0 then return "" end
  if font:getWidth(text) <= maxW then return text end
  local ell = "..."
  local ew = font:getWidth(ell)
  while #text > 0 and font:getWidth(text) + ew > maxW do
    text = text:sub(1, #text - 1)
  end
  return text .. ell
end

function Theme.ellipsizeLeft(font, text, maxW)
  text = tostring(text or "")
  if not font then return text end
  if maxW <= 0 then return "" end  -- same rule as Theme.ellipsize (#715)
  if font:getWidth(text) <= maxW then return text end
  local ell = "..."
  local ew = font:getWidth(ell)
  while #text > 0 and font:getWidth(text) + ew > maxW do
    text = text:sub(2)
  end
  return ell .. text
end

-- ------------------------------------------------------------- backgrounds
-- The radial navy field, drawn as a triangle fan from the top-centre so the
-- falloff matches the CSS radial-gradient in the spec.  The screen is cleared
-- to the outer colour first so the corners the fan misses match seamlessly.
function Theme.field(w, h)
  if not G then return end
  G.clear(PAL.bgBot[1] / 255, PAL.bgBot[2] / 255, PAL.bgBot[3] / 255, 1)
  if not probe("newMesh") then return end
  local cx, cy = w / 2, 0
  local rx, ry = w * 1.3, h * 1.08
  local n = 64
  local verts = { { cx, cy, 0, 0,
    PAL.bgTop[1] / 255, PAL.bgTop[2] / 255, PAL.bgTop[3] / 255, 1 } }
  for i = 0, n do
    local a = (i / n) * math.pi * 2
    verts[#verts + 1] = { cx + math.cos(a) * rx, cy + math.sin(a) * ry, 0, 0,
      PAL.bgBot[1] / 255, PAL.bgBot[2] / 255, PAL.bgBot[3] / 255, 1 }
  end
  local mesh = G.newMesh(verts, "fan", "static")
  G.setColor(1, 1, 1, 1)
  G.draw(mesh)
end

-- The 6px tri-colour rail across the very top of both windows.
function Theme.versionRail(x, y, w, h)
  if not G then return end
  local seg = w / 3
  local bars = { PAL.railRed, PAL.railBlue, PAL.railGold }
  for i, c in ipairs(bars) do
    col(c, 1)
    G.rectangle("fill", x + (i - 1) * seg, y, seg, h)
  end
end

-- A percentage meter (HP, box fill, dex completion, bag slots).  pct is 0-100.
function Theme.meter(x, y, w, h, pct, c)
  if not G then return end
  col(PAL.cardBorder, 0.18)
  G.rectangle("fill", x, y, w, h, h / 2, h / 2)
  local fill = w * clamp((pct or 0) / 100, 0, 1)
  if fill > 0 then
    col(c or PAL.blue, 1)
    G.rectangle("fill", x, y, math.max(fill, h / 2), h, h / 2, h / 2)
  end
end

-- Font set, rebuilt only when the window size changes.  `s` is the same
-- height/768 scale the launcher derives, so both windows step together.
-- Chrome is the default UI face; save DATA is drawn in the mono face, which
-- LOVE only ships as the default vector font -- so "mono" here means the
-- same face at a tighter size, and the distinction is carried by size and
-- colour.  A stub with no newFont returns nil fonts and every draw no-ops.
function Theme.fonts(s)
  if not probe("newFont") then return {} end
  local function f(px) return G.newFont(math.max(8, math.floor(px + 0.5))) end
  return {
    scale     = s,
    wordmark  = f(14 * s),
    brand     = f(11 * s),
    chip      = f(11 * s),   -- RED / BLUE version chip
    tile      = f(13 * s),   -- 2-letter tab glyph
    tab       = f(13 * s),   -- tab label
    button    = f(14 * s),
    small     = f(12 * s),
    tiny      = f(11 * s),
    micro     = f(10 * s),
    caption   = f(12 * s),   -- letterspaced section captions
    mono      = f(12 * s),
    monoRow   = f(13 * s),
    monoBig   = f(18 * s),
    title     = f(24 * s),   -- inspector species name
    headline  = f(26 * s),   -- dex completion / money
    stat      = f(19 * s),
  }
end

return Theme
