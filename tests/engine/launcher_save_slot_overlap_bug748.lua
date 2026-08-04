-- Regression for #748: FlexLove propagates a nested child's auto-height
-- change only to its direct parent while the launcher tree is constructed.
-- The two-column grid can therefore retain the shorter left-column height
-- after the save-slot card makes the right column taller, placing the footer
-- over the bottom of that card. Keep this test ROM- and renderer-free.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

-- Element sizing asks the window for its current mode. FlexLove also loads
-- UTF8 helpers for rendering, although this geometry test draws no text.
love.window.getMode = function()
  return 1024, 768, { fullscreen = false }
end
love.window.getDesktopDimensions = function() return 1920, 1080 end
package.loaded["libs.flexlove.modules.UTF8"] = {
  char = string.char,
  charpattern = ".",
  codepoint = string.byte,
  len = string.len,
  offset = function(_, n) return n end,
  codes = function(s)
    local i = 0
    return function()
      i = i + 1
      if i <= #s then return i, s:byte(i) end
    end
  end,
}

local T = require("tests.modkit")
local FlexLove = require("libs.flexlove.FlexLove")
FlexLove.init({
  immediateMode = false,
  performanceMonitoring = false,
  keyboardNavigation = false,
})
local LauncherView = require("src.import.LauncherView")
local refreshAutoHeight = LauncherView._refreshAutoHeight

-- Preserve the launcher's construction order. The left card grows first;
-- adding the right column then refreshes the grid to 220. Growing a card
-- nested inside that right column reaches the column, but not the grid.
local function nestedColumns(leftHeight, rightHeight, gridOverrides)
  local page = FlexLove.new({
    width = 800,
    positioning = "flex",
    flexDirection = "vertical",
    gap = 12,
  })
  local gridProps = {
    parent = page,
    width = 800,
    positioning = "flex",
    flexDirection = "horizontal",
    alignItems = "flex-start",
  }
  for key, value in pairs(gridOverrides or {}) do
    gridProps[key] = value
  end
  local grid = FlexLove.new(gridProps)
  local left = FlexLove.new({
    parent = grid,
    width = 390,
    positioning = "flex",
    flexDirection = "vertical",
  })
  local leftCard = FlexLove.new({
    parent = left,
    width = 390,
    positioning = "flex",
    flexDirection = "vertical",
  })
  FlexLove.new({ parent = leftCard, width = 390, height = leftHeight })
  local right = FlexLove.new({
    parent = grid,
    width = 390,
    positioning = "flex",
    flexDirection = "vertical",
  })
  local rightCard = FlexLove.new({
    parent = right,
    width = 390,
    positioning = "flex",
    flexDirection = "vertical",
  })
  FlexLove.new({ parent = rightCard, width = 390, height = rightHeight })
  return { page = page, grid = grid, left = left, right = right }
end

-- Reported shape: real FlexLove elements finish with a 520px right column,
-- but both the grid and page still reserve only the 220px left extent.
local tallRight = nestedColumns(220, 520)
local gap = 12
T.eq(tallRight.left:getBorderBoxHeight(), 220,
  "the left launcher column finishes at its content height")
T.eq(tallRight.right:getBorderBoxHeight(), 520,
  "the nested save-slot column grows to its completed height")
T.eq(tallRight.grid:getBorderBoxHeight(), 220,
  "FlexLove leaves the outer two-column grid stale")
T.eq(tallRight.page:getBorderBoxHeight(), 220,
  "the page inherits the stale grid extent")
T.eq(tallRight.grid:calculateAutoHeight(), 520,
  "the completed grid can measure the correct taller extent")
T.check(tallRight.grid:getBorderBoxHeight() + gap
    < tallRight.right:getBorderBoxHeight(),
  "the stale grid places the following footer over the save-slot column")

if not T.check(type(refreshAutoHeight) == "function",
    "launcher exports the auto-height reconciliation seam") then
  T.finish("launcher save-slot overlap #748")
end

tallRight.grid._dirty = false
tallRight.page._childrenDirty = false
local refreshedHeight = refreshAutoHeight(tallRight.grid)
T.eq(refreshedHeight, 520, "reconciliation returns the taller border-box height")
T.eq(tallRight.grid.height, 520, "reconciliation updates content height")
T.eq(tallRight.grid:getBorderBoxHeight(), 520,
  "reconciliation updates the cached border-box height")
T.check(tallRight.grid._dirty, "reconciliation invalidates the grid")
T.check(tallRight.page._childrenDirty,
  "reconciliation invalidates ancestor layout")
T.check(tallRight.grid:getBorderBoxHeight() + gap
    >= tallRight.right:getBorderBoxHeight(),
  "the following footer starts below the completed save-slot column")

-- Reconciliation uses the maximum completed column; it must not blindly
-- copy the right side and shrink an already-taller left side.
local shortRight = nestedColumns(420, 220)
T.eq(refreshAutoHeight(shortRight.grid), 420,
  "a shorter right column preserves the taller left extent")
T.eq(shortRight.grid.height, 420,
  "short content keeps its correct content height")
T.eq(shortRight.grid:getBorderBoxHeight(), 420,
  "short content keeps its correct border-box height")

-- Match FlexLove's resize path: clamp the padded border box, then derive and
-- clamp the content box from it.
local constrained = nestedColumns(600, 500, {
  padding = { top = 10, bottom = 20 },
  maxHeight = 550,
})
T.eq(constrained.grid:calculateAutoHeight(), 600,
  "the constrained grid measures its taller child before padding")
T.eq(refreshAutoHeight(constrained.grid), 550,
  "max-height clamps the padded border box")
T.eq(constrained.grid.height, 520,
  "content height subtracts padding from the constrained border box")
T.eq(constrained.grid:getBorderBoxHeight(), 550,
  "the constrained border-box cache stays synchronized")

-- Invalid or inapplicable measurements are fail-closed and leave geometry
-- untouched rather than poisoning the next layout pass.
local notANumber = nestedColumns(220, 520)
notANumber.grid.calculateAutoHeight = function() return 0 / 0 end
notANumber.grid._dirty = false
T.eq(refreshAutoHeight(notANumber.grid), false, "NaN auto height is rejected")
T.eq(notANumber.grid.height, 220, "NaN leaves content height unchanged")
T.eq(notANumber.grid:getBorderBoxHeight(), 220,
  "NaN leaves border-box height unchanged")
T.eq(notANumber.grid._dirty, false, "NaN does not invalidate layout")

local infinite = nestedColumns(220, 520)
infinite.grid.calculateAutoHeight = function() return math.huge end
T.eq(refreshAutoHeight(infinite.grid), false, "infinite auto height is rejected")
T.eq(infinite.grid.height, 220, "infinite height leaves geometry unchanged")

local fixed = FlexLove.new({ width = 800, height = 220 })
T.eq(refreshAutoHeight(fixed), false, "fixed-height elements are ignored")
T.eq(fixed.height, 220, "fixed-height geometry is unchanged")
T.eq(refreshAutoHeight(nil), false, "a missing element is ignored")

T.finish("launcher save-slot overlap #748")
