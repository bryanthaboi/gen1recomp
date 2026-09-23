-- Per-glyph fallback for the launcher's UI faces.
--
-- The launcher draws with LÖVE's default face, which covers Latin and little
-- else.  That was invisible while the launcher was English-only, but its text
-- now goes through Strings (#767/#791) and a translation mod's catalog is
-- loaded before the first launcher frame (LauncherMods.translationStrings), so
-- the moment one is Japanese every kana lands as a tofu box.
--
-- Font:setFallbacks fills ONLY the codepoints the primary face is missing, so
-- Latin keeps the launcher's own look and nothing about an English install
-- changes; only the glyphs it genuinely cannot draw come from the bundled
-- Plain Pixel (assets/fonts/plainpixel/README.md: CC-BY 4.0, Douglas
-- Vautour), which covers kana and CJK.  That is the same face the in-game TTF
-- text mode uses, so a translated launcher and a translated game agree.
--
-- Measuring and rendering must attach the same fallback or the launcher
-- measures a width it does not draw -- which is how buttons clip.

local UiFont = {}

local FALLBACK_PATH = "assets/fonts/plainpixel/PlainPixel-Regular.ttf"
-- Plain Pixel only rasterizes evenly at multiples of its 15px design em, so
-- snap rather than matching the primary size exactly: a fallback glyph a pixel
-- off its grid is far more obvious than one a pixel off its neighbours.
local DESIGN_EM = 15

local cache = {}
local unavailable = false

local function fallbackFor(size)
  if unavailable then return nil end
  local snapped = math.max(DESIGN_EM,
    math.floor(size / DESIGN_EM + 0.5) * DESIGN_EM)
  local hit = cache[snapped]
  if hit ~= nil then return hit or nil end
  local ok, font = pcall(love.graphics.newFont, FALLBACK_PATH, snapped)
  if not ok or not font then
    -- one failure means the file is absent (a trimmed build); stop retrying
    unavailable = true
    return nil
  end
  if font.setFilter then pcall(font.setFilter, font, "nearest", "nearest") end
  cache[snapped] = font
  return font
end

-- attach(font, size) -> font.  Safe to call on every cache miss; a font whose
-- fallback is already set is left alone, and any failure is swallowed so a
-- missing fallback file can never take the launcher down with it.
local UPM, ASCENT, DESCENT = 2048, 1901, -483
local SYMBOL_CODEPOINTS = { 0x2642, 0x2640 }

local function circle(cx, cy, r, clockwise)
  local pts = {}
  local k = r / math.cos(math.pi / 8)
  for i = 0, 7 do
    local a = math.rad(90 + (clockwise and -45 or 45) * i)
    local m = a + math.rad(clockwise and -22.5 or 22.5)
    pts[#pts + 1] = { cx + r * math.cos(a), cy + r * math.sin(a), true }
    pts[#pts + 1] = { cx + k * math.cos(m), cy + k * math.sin(m), false }
  end
  return pts
end

local function poly(list)
  local pts = {}
  for i = 1, #list, 2 do pts[#pts + 1] = { list[i], list[i + 1], true } end
  return pts
end

local function rect(x0, y0, x1, y1)
  return poly({ x0, y1, x1, y1, x1, y0, x0, y0 })
end

UiFont.SYMBOL_GLYPHS = {
  [0x2642] = {
    advance = 1620,
    contours = {
      circle(620, 560, 480, true),
      circle(620, 560, 300, false),
      poly({ 829, 903, 1333, 1407, 1467, 1273, 963, 769 }),
      poly({ 1000, 1493, 1493, 1493, 1493, 1000, 1313, 1000, 1313, 1313, 1000, 1313 }),
    },
  },
  [0x2640] = {
    advance = 1280,
    contours = {
      circle(640, 1000, 480, true),
      circle(640, 1000, 300, false),
      rect(545, -160, 735, 560),
      rect(340, 150, 940, 330),
    },
  },
}

local function u16(v) v = math.floor(v + 0.5) % 65536 return string.char(math.floor(v / 256), v % 256) end
local function u32(v) return u16(math.floor(v / 65536)) .. u16(v % 65536) end

local function encodeGlyph(g)
  local ends, flags, xs, ys = {}, {}, {}, {}
  local xMin, yMin, xMax, yMax = math.huge, math.huge, -math.huge, -math.huge
  local n, px, py = 0, 0, 0
  for _, contour in ipairs(g.contours) do
    for _, p in ipairs(contour) do
      local x, y = math.floor(p[1] + 0.5), math.floor(p[2] + 0.5)
      xMin, yMin = math.min(xMin, x), math.min(yMin, y)
      xMax, yMax = math.max(xMax, x), math.max(yMax, y)
      flags[#flags + 1] = string.char(p[3] and 1 or 0)
      xs[#xs + 1], ys[#ys + 1] = u16(x - px), u16(y - py)
      px, py = x, y
      n = n + 1
    end
    ends[#ends + 1] = u16(n - 1)
  end
  g.xMin, g.yMin, g.xMax, g.yMax, g.points = xMin, yMin, xMax, yMax, n
  return u16(#g.contours) .. u16(xMin) .. u16(yMin) .. u16(xMax) .. u16(yMax)
    .. table.concat(ends) .. u16(0) .. table.concat(flags)
    .. table.concat(xs) .. table.concat(ys)
end

local function checksum(data)
  local padded = data .. string.rep("\0", (4 - #data % 4) % 4)
  local sum = 0
  for i = 1, #padded, 4 do
    local a, b, c, d = padded:byte(i, i + 3)
    sum = (sum + ((a * 256 + b) * 256 + c) * 256 + d) % 4294967296
  end
  return sum
end

function UiFont.symbolFontData()
  local glyphs = { { advance = 1024, contours = {} } }
  for _, cp in ipairs(SYMBOL_CODEPOINTS) do glyphs[#glyphs + 1] = UiFont.SYMBOL_GLYPHS[cp] end

  local glyf, loca, hmtx = {}, { u32(0) }, {}
  local offset, maxPoints, maxContours = 0, 0, 0
  local xMin, yMin, xMax, yMax, advMax = 0, 0, 0, 0, 0
  for i, g in ipairs(glyphs) do
    local bytes = ""
    if #g.contours > 0 then
      bytes = encodeGlyph(g)
      bytes = bytes .. string.rep("\0", (4 - #bytes % 4) % 4)
      maxPoints = math.max(maxPoints, g.points)
      maxContours = math.max(maxContours, #g.contours)
      xMin, yMin = math.min(xMin, g.xMin), math.min(yMin, g.yMin)
      xMax, yMax = math.max(xMax, g.xMax), math.max(yMax, g.yMax)
    end
    glyf[i] = bytes
    offset = offset + #bytes
    loca[#loca + 1] = u32(offset)
    hmtx[i] = u16(g.advance) .. u16(g.xMin or 0)
    advMax = math.max(advMax, g.advance)
  end

  local segs = {}
  for i, cp in ipairs(SYMBOL_CODEPOINTS) do segs[#segs + 1] = { cp, i } end
  table.sort(segs, function(a, b) return a[1] < b[1] end)
  segs[#segs + 1] = { 0xFFFF, 0 }
  local segX2 = #segs * 2
  local sr, es = 1, 0
  while sr * 2 <= #segs do sr, es = sr * 2, es + 1 end
  local endc, startc, delta, ro = {}, {}, {}, {}
  for i, s in ipairs(segs) do
    endc[i], startc[i], delta[i], ro[i] = u16(s[1]), u16(s[1]), u16(s[2] - s[1]), u16(0)
  end
  local sub = u16(4) .. u16(16 + segX2 * 4) .. u16(0) .. u16(segX2) .. u16(sr * 2)
    .. u16(es) .. u16(segX2 - sr * 2) .. table.concat(endc) .. u16(0)
    .. table.concat(startc) .. table.concat(delta) .. table.concat(ro)
  local cmap = u16(0) .. u16(1) .. u16(3) .. u16(1) .. u32(12) .. sub

  local family = "UiSymbols"
  local utf16 = family:gsub(".", function(c) return "\0" .. c end)
  local name = u16(0) .. u16(1) .. u16(18) .. u16(3) .. u16(1) .. u16(0x409)
    .. u16(1) .. u16(#utf16) .. u16(0) .. utf16

  local tables = {
    cmap = cmap,
    glyf = table.concat(glyf),
    head = u32(0x00010000) .. u32(0x00010000) .. u32(0) .. u32(0x5F0F3CF5)
      .. u16(3) .. u16(UPM) .. string.rep("\0", 16)
      .. u16(xMin) .. u16(yMin) .. u16(xMax) .. u16(yMax)
      .. u16(0) .. u16(8) .. u16(2) .. u16(1) .. u16(0),
    hhea = u32(0x00010000) .. u16(ASCENT) .. u16(DESCENT) .. u16(0)
      .. u16(advMax) .. u16(0) .. u16(0) .. u16(xMax) .. u16(1) .. u16(0)
      .. u16(0) .. string.rep("\0", 8) .. u16(0) .. u16(#glyphs),
    hmtx = table.concat(hmtx),
    loca = table.concat(loca),
    maxp = u32(0x00010000) .. u16(#glyphs) .. u16(maxPoints) .. u16(maxContours)
      .. u16(0) .. u16(0) .. u16(2) .. string.rep("\0", 16),
    name = name,
    post = u32(0x00030000) .. u32(0) .. u16(-200) .. u16(100) .. string.rep("\0", 20),
  }
  local tags = {}
  for tag in pairs(tables) do tags[#tags + 1] = tag end
  table.sort(tags)

  local nt = #tags
  local tsr, tes = 1, 0
  while tsr * 2 <= nt do tsr, tes = tsr * 2, tes + 1 end
  local dir = { u32(0x00010000), u16(nt), u16(tsr * 16), u16(tes), u16(nt * 16 - tsr * 16) }
  local body = {}
  local pos = 12 + nt * 16
  for _, tag in ipairs(tags) do
    local data = tables[tag]
    dir[#dir + 1] = tag .. u32(checksum(data)) .. u32(pos) .. u32(#data)
    local padded = data .. string.rep("\0", (4 - #data % 4) % 4)
    body[#body + 1] = padded
    pos = pos + #padded
  end
  return table.concat(dir) .. table.concat(body)
end

local symbolCache = {}
local symbolData

local function symbolsFor(size)
  size = math.max(1, math.floor(size + 0.5))
  local hit = symbolCache[size]
  if hit ~= nil then return hit or nil end
  local ok, font = pcall(function()
    symbolData = symbolData or love.filesystem.newFileData(UiFont.symbolFontData(), "UiSymbols.ttf")
    return love.graphics.newFont(symbolData, size)
  end)
  symbolCache[size] = ok and font or false
  return ok and font or nil
end

function UiFont.attach(font, size)
  if not (font and font.setFallbacks) then return font end
  local primarySize = size or (font.getHeight and font:getHeight()) or DESIGN_EM
  local chain = {}
  local fallback = fallbackFor(primarySize)
  if fallback and not rawequal(fallback, font) then chain[#chain + 1] = fallback end
  local symbols = symbolsFor(primarySize)
  if symbols and not rawequal(symbols, font) then chain[#chain + 1] = symbols end
  if #chain == 0 then return font end
  pcall(font.setFallbacks, font, unpack(chain))
  return font
end

function UiFont.clear()
  cache, unavailable = {}, false
  symbolCache, symbolData = {}, nil
end

return UiFont
