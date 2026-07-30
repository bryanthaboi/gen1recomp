-- #373: the two faint horizontal lines across the title screen.  Both
-- halves are asserted here: Renderer's zone scissor must hand LOVE rects
-- whose framebuffer pixels stay contiguous across a zone boundary at
-- Android's non-integer DPI, and TitleState's three title zones must share
-- color 0 the way the hardware SuperPals do (pokered data/sgb/
-- sgb_palettes.asm: PAL_LOGO1 / PAL_LOGO2 / PAL_MEWMON all start RGB
-- 31,29,31).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq, same = T.check, T.eq, T.same

-- ---------------------------------------------------------------- scissor
-- scissorClamped is a local in Renderer.lua and the only caller is inside
-- endFrame's blit closure, which needs canvases and a compiled shader.  The
-- source is loaded directly so the rect arithmetic can be exercised with no
-- GPU, the same way parity_picker_pointer_grab reads RomImporter (#254).
local scissorClamped, captured
do
  local f = io.open("src/render/Renderer.lua", "rb")
  check(f ~= nil, "Renderer source is readable")
  local src = f and f:read("*a") or ""
  if f then f:close() end
  local body = src:match("\nlocal function scissorClamped.-\nend\n")
  check(body ~= nil, "scissorClamped is still a single local function")
  local fakeLove = { graphics = { setScissor = function(x, y, w, h)
    captured = { x = x, y = y, w = w, h = h }
  end } }
  local chunk = assert(loadstring("local love = ...\n" .. (body or "")
    .. "\nreturn scissorClamped"))
  scissorClamped = chunk(fakeLove)
  check(type(scissorClamped) == "function", "scissorClamped loads standalone")
end

-- The title's three SGB zones in canvas pixels (PaletteFX.zone turns the
-- ATTR_BLK tile rects rows 0-7 / 8-9 / 10-17 into these).
local ZONES = {
  { x = 0, y = 0, w = 160, h = 64 },
  { x = 0, y = 64, w = 160, h = 16 },
  { x = 0, y = 80, w = 160, h = 64 },
}

-- Mirrors Renderer:endFrame's letterbox geometry and its UI blit call
-- (blit(canvas, Sx, Sy, zones, Sx, Sy, ox, oy, ox, oy, vpw, vph)).
local function viewport(pw, ph, dpiX, dpiY)
  local uiw, uih = 160, 144
  local Sp = math.max(1, math.floor(math.min(pw / uiw, ph / uih)))
  return {
    Sp = Sp, Sx = Sp / dpiX, Sy = Sp / dpiY,
    ox = math.floor((pw - uiw * Sp) / 2) / dpiX,
    oy = math.floor((ph - uih * Sp) / 2) / dpiY,
    vpw = uiw * (Sp / dpiX), vph = uih * (Sp / dpiY),
  }
end

local function zoneRects(v, dpiX, dpiY)
  local out = {}
  for i, z in ipairs(ZONES) do
    captured = nil
    local drew = scissorClamped(v.ox + z.x * v.Sx, v.oy + z.y * v.Sy,
                               z.w * v.Sx, z.h * v.Sy,
                               v.ox, v.oy, v.vpw, v.vph, dpiX, dpiY)
    out[i] = drew and captured or nil
  end
  return out
end

-- What the pre-fix code emitted: the clamp alone, fractional edges and all.
local function clampOnly(v)
  local out = {}
  for i, z in ipairs(ZONES) do
    local x, y = v.ox + z.x * v.Sx, v.oy + z.y * v.Sy
    local x2 = math.min(x + z.w * v.Sx, v.ox + v.vpw)
    local y2 = math.min(y + z.h * v.Sy, v.oy + v.vph)
    x, y = math.max(x, v.ox), math.max(y, v.oy)
    out[i] = { x = x, y = y, w = x2 - x, h = y2 - y }
  end
  return out
end

-- love.graphics.setScissor scales a rect by the DPI scalar and truncates
-- x, y, w and h to whole framebuffer pixels independently, so a rect's
-- covered rows are [floor(y*d), floor(y*d) + floor(h*d)).
local function rowSpan(r, d)
  local top = math.floor(r.y * d)
  return top, top + math.floor(r.h * d)
end
local function colSpan(r, d)
  local left = math.floor(r.x * d)
  return left, left + math.floor(r.w * d)
end

local function seams(rects, d)
  local n = 0
  for k = 1, #rects - 1 do
    local _, bottom = rowSpan(rects[k], d)
    local top = rowSpan(rects[k + 1], d)
    if bottom < top then n = n + 1 end
  end
  return n
end

-- Desktop: dpi 1, integer origin and scale.  Every edge is already whole, so
-- the rounding must land on exactly the pixels the plain clamp did (that path
-- was never broken) and neighbours must abut with no overlap at all.
do
  local v = viewport(1920, 1080, 1, 1)
  local fixed, plain = zoneRects(v, 1, 1), clampOnly(v)
  for i = 1, #ZONES do
    local top, bottom = rowSpan(fixed[i], 1)
    local ptop, pbottom = rowSpan(plain[i], 1)
    eq(top, ptop, "desktop zone " .. i .. " starts on the same row")
    eq(bottom, pbottom, "desktop zone " .. i .. " ends on the same row")
  end
  for k = 1, #fixed - 1 do
    local _, bottom = rowSpan(fixed[k], 1)
    eq(bottom, rowSpan(fixed[k + 1], 1),
      "desktop zone " .. k .. " abuts its neighbour exactly")
  end
end

-- The reporter's 1920x1080 Android screen, plus DPI values around it.  d is
-- the scalar LOVE applies; it equals the axis ratio on a square-DPI surface
-- and can differ when the window's two ratios do not match.
local CASES = {
  { dpiX = 2.625, dpiY = 2.625 },
  { dpiX = 2.75, dpiY = 2.75 },
  { dpiX = 3.5, dpiY = 3.5 },
  { dpiX = 2.0625, dpiY = 2.0625 },
  { dpiX = 2.625, dpiY = 2.6, d = 2.625 },
  { dpiX = 2.75, dpiY = 2.8, d = 2.75 },
}

local brokenCases = 0
for _, c in ipairs(CASES) do
  local tag = ("dpi %s/%s"):format(c.dpiX, c.dpiY)
  local v = viewport(1920, 1080, c.dpiX, c.dpiY)
  local dy = c.d or c.dpiY
  local dx = c.d or c.dpiX
  local rects = zoneRects(v, c.dpiX, c.dpiY)
  eq(#rects, 3, tag .. ": all three title zones draw")
  eq(seams(rects, dy), 0, tag .. ": no black row between adjacent zones")
  if seams(clampOnly(v), dy) > 0 then brokenCases = brokenCases + 1 end

  for k = 1, #rects - 1 do
    local _, bottom = rowSpan(rects[k], dy)
    local top = rowSpan(rects[k + 1], dy)
    check(bottom - top <= 1,
      tag .. ": zone " .. k .. " overlaps its neighbour by at most one row")
  end

  -- The same truncation was shaving the bottom copyright row and the right
  -- edge of the picture, so the outer edges have to reach the viewport too.
  local firstTop = rowSpan(rects[1], dy)
  local _, lastBottom = rowSpan(rects[#rects], dy)
  check(firstTop <= math.floor(v.oy * dy), tag .. ": top edge is covered")
  check(lastBottom >= math.floor((v.oy + v.vph) * dy),
    tag .. ": the bottom copyright row is covered")
  local left, right = colSpan(rects[#rects], dx)
  check(left <= math.floor(v.ox * dx), tag .. ": left edge is covered")
  check(right >= math.floor((v.ox + v.vpw) * dx),
    tag .. ": the right edge of the picture is covered")
end
check(brokenCases > 0,
  "the plain clamped rects still gap on a fractional-DPI surface, which is"
  .. " the seam the rounding removes")

-- ---------------------------------------------------------------- palettes
local PaletteFX = require("src.render.PaletteFX")
local GameVersion = require("src.core.GameVersion")
local TitleState = require("src.ui.TitleState")

local OFF_WHITE = { 255, 239, 255 }
local function romPack(logo1)
  return { palettes = { palettes = {
    LOGO1 = logo1,
    LOGO2 = { OFF_WHITE, { 247, 247, 140 }, { 148, 156, 148 }, { 57, 57, 132 } },
    MEWMON = { OFF_WHITE, { 247, 181, 140 }, { 132, 115, 156 }, { 24, 16, 16 } },
  } } }
end
local RED_LOGO1 = { OFF_WHITE, { 247, 247, 140 }, { 140, 189, 82 }, { 173, 0, 33 } }
local BLUE_LOGO1 = { OFF_WHITE, { 247, 247, 140 }, { 173, 0, 33 }, { 115, 156, 239 } }

local savedMode, savedVersion = PaletteFX.mode, GameVersion.get()
local title = setmetatable({}, { __index = TitleState })

-- SGB (the default): the ribbon band's white is the neighbouring zones'
-- white, so the two boundaries at y=64 and y=80 draw no brighter strip.
do
  PaletteFX.mode = "gbc"
  GameVersion.set("red")
  local z = title:sgbPalettes({ data = romPack(RED_LOGO1) })
  eq(z and #z, 3, "the title builds three SGB zones")
  eq(z[1].y, 0, "logo zone starts at row 0")
  eq(z[2].y, 64, "the version ribbon starts at tile row 8")
  eq(z[3].y, 80, "the player/mon zone starts at tile row 10")
  eq(z[1].y + z[1].h, z[2].y, "logo and ribbon share a boundary")
  eq(z[2].y + z[2].h, z[3].y, "ribbon and mon zone share a boundary")
  same(z[2].colors[1], z[1].colors[1], "the ribbon band's white is the logo's")
  same(z[3].colors[1], z[1].colors[1], "the mon zone's white matches too")
  same(z[2].colors[4], RED_LOGO1[4], "Red's \"Version\" ink survives")
end

-- RED++ (#128): LOGO2/MEWMON come from the GBC pack, Blue's LOGO1 from the
-- ROM pack.  Taking LOGO2's white must still whiten the ribbon there and
-- must not touch the blue ink.
do
  PaletteFX.mode = "redpp"
  GameVersion.set("blue")
  local z = title:sgbPalettes({ data = romPack(BLUE_LOGO1) })
  eq(z and #z, 3, "RED++ builds three title zones")
  same(z[1].colors[1], { 255, 255, 255 }, "the GBC logo pal is pure white")
  same(z[2].colors[1], { 255, 255, 255 }, "the ribbon band is pure white")
  same(z[3].colors[1], { 255, 255, 255 }, "the mon zone is pure white")
  same(z[2].colors[4], BLUE_LOGO1[4], "Blue's \"Version\" ink stays blue")
  same(z[2].colors[3], BLUE_LOGO1[3], "Blue LOGO1's other inks stay put")
end

PaletteFX.mode = savedMode
GameVersion.set(savedVersion)

T.finish("title zone seams")
