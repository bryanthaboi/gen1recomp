-- Shared layout metrics for the launcher and the save editor.
--
-- Both windows derive one `m` table per frame from the real window size and
-- the platform safe area, and every panel lays itself out in explicit pixels
-- off that table.  Explicit pixels are the point: the old view expressed
-- widths as "100%" and leaned on a layout engine to resolve them, which is
-- where the launcher's layout bugs lived (percentages resolving against a
-- border box instead of a content box, auto-sized children measuring zero
-- height inside an auto-sized parent, flex-shrink compressing text until it
-- overlapped).  None of those failure modes exist when a column is simply
-- `math.floor((contentW - gap) / 2)`.
--
-- REFLOW, not shrink: a narrow window drops to fewer columns rather than
-- scaling the desktop layout down.  Scale has a floor (Kit.layout clamps to
-- 0.9) so tap targets and text stay legible on a phone.

local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local SafeArea = require("src.core.SafeArea")

local Layout = {}

-- Breakpoints, in safe-area pixels.  Named so panels read intent rather than
-- magic numbers.
Layout.BP = {
  twoCol   = 640,   -- side-by-side columns become possible
  threeCol = 1100,  -- wide desktop: mod list + detail + chrome
}

-- Resolve the column count for an app width and scale.  Shared by the
-- metrics builder and the fit-scale pass below.
local function columnCount(appW, s)
  return (appW >= Layout.BP.threeCol * s and 3)
      or (appW >= Layout.BP.twoCol * s and 2)
      or 1
end

-- Build the frame's metrics.  `maxAppW` caps the content column on an
-- ultrawide monitor so the UI stays a readable measure instead of stretching.
-- `fitH` (optional) is the panel minimum the caller needs to fit vertically,
-- as `{ two = 460, one = 660 }` in unscaled px per column count.  When set,
-- the whole UI fit-scales down so that minimum plus the header/footer chrome
-- lands on screen instead of under the fold (see Kit.layout).
function Layout.metrics(maxAppW, fitH)
  local W, H = 0, 0
  if love and love.graphics and love.graphics.getDimensions then
    W, H = love.graphics.getDimensions()
  end
  local ox, oy, sw, sh = SafeArea.rect()
  local s = Kit.layout(sw, sh)

  -- The column count decides which panel minimum applies, so resolve it
  -- against the resolution scale first, then fit against the matching
  -- minimum.  Fit-shrinking can change the column count -- a 720px square
  -- window drops below the two-column breakpoint and the two-column
  -- minimum (460) replaces the one-column minimum (660) -- so re-fit
  -- against the new minimum until scale and column count stabilise.
  local cols = columnCount(math.min(sw, (maxAppW or 1200) * s), s)
  if fitH then
    for _ = 1, 3 do
      local need = cols >= 2 and fitH.two or fitH.one
      if not need then break end
      s = Kit.layout(sw, sh, need)
      local nextCols = columnCount(math.min(sw, (maxAppW or 1200) * s), s)
      if nextCols == cols then break end
      cols = nextCols
    end
  end

  local appW = math.min(sw, (maxAppW or 1200) * s)
  local m = {
    W = W, H = H, s = s,
    x = math.floor(ox + (sw - appW) / 2),
    top = math.floor(oy),
    w = math.floor(appW),
    h = math.floor(sh),
    pad = math.floor(Theme.clamp(appW * 0.03, 10, 24)),
    gap = math.floor(12 * s),
    colGap = math.floor(16 * s),
    rowH = math.max(Kit.tapMin(), math.floor(44 * s)),
    btnH = math.max(Kit.tapMin(), math.floor(38 * s)),
    chip = math.max(Kit.tapMin(), math.floor(40 * s)),
    railH = math.max(3, math.floor(4 * s)),
    logoH = math.floor(Theme.clamp(sh * 0.10, 36, 84)),
  }
  m.cols = columnCount(appW, s)
  m.twoCol = m.cols >= 2
  m.contentW = m.w - 2 * m.pad
  m.colW = m.twoCol
    and math.floor((m.contentW - m.colGap) / 2)
    or m.contentW
  m.contentX = m.x + m.pad
  return m
end

-- A vertical cursor for stacking blocks down a column.  Immediate mode has
-- no layout pass, so panels advance a y by hand; this makes that explicit
-- and keeps the arithmetic in one place.
local Cursor = {}
Cursor.__index = Cursor

function Layout.cursor(x, y, w)
  return setmetatable({ x = x, y = y, w = w, y0 = y }, Cursor)
end

-- Reserve `h` pixels and return the rect that was reserved.
function Cursor:take(h, gapAfter)
  local x, y = self.x, self.y
  self.y = self.y + h + (gapAfter or 0)
  return x, y, self.w, h
end

function Cursor:skip(h)
  self.y = self.y + h
end

function Cursor:height()
  return self.y - self.y0
end

-- Split the cursor's width into `n` equal columns with `gap` between them,
-- returning a function that yields the i-th column's x and width.
function Layout.columns(x, w, n, gap)
  n = math.max(1, n)
  local cw = math.floor((w - gap * (n - 1)) / n)
  return function(i)
    return x + (i - 1) * (cw + gap), cw
  end
end

-- Lay a row of buttons out right-aligned within [x, x+w], returning a
-- function that yields each button's x as it is consumed right to left.
function Layout.rightCluster(x, w, gap)
  local cursor = x + w
  return function(bw)
    cursor = cursor - bw
    local bx = cursor
    cursor = cursor - gap
    return bx
  end
end

return Layout
