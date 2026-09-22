-- Launcher panel reflow.  No pokered cite: the launcher is port-only chrome.
--
-- Three reports from the same round of testing, all of them the same root
-- cause -- a panel laying out more content than its window could hold, with
-- no scrollbar to rescue what fell off:
--
--   * "Import failed only appears in that single line" -- the ROM card's
--     detail paragraph is elastic and got trimmed to zero lines whenever the
--     card's height budget was tight, so a failed import printed a headline
--     with no reason under it.  The reporter's German ROM was rejected for a
--     specific, printable reason and the launcher swallowed it.
--   * "The settings labels are barely visible at all" -- settings rows put
--     the label and the value ladder side by side, and on a portrait phone
--     the ladder took so much of the width that every label ellipsized to
--     three characters ("TEX...", "BAT...", "BAT...").
--   * "these buttons don't appear correctly" / Play walking off the bottom --
--     the game panel pinned Play and a Touch-Controls/Reset-rebinds pair to
--     the bottom of a column whose height was whatever its cards needed, so
--     on a short window the pinned block left the window entirely.
--
-- The audit sweep at the end is the general form of the third: Kit records
-- every control that could take a click (plus the clip that bounds its hit
-- test) while Kit.audit is set, so a window-size sweep can assert that no two
-- controls overlap and that nothing escapes a window which is not scrolling.
-- A window that IS scrolling legitimately draws below the fold -- reachability
-- there is pinned by tests/engine/launcher_one_column_reach_bug852.lua.
--   luajit tests/engine/launcher_panel_reflow.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local Kit = require("src.ui.kit.Kit")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

local function window(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
end

local function freshLauncher()
  return RomImporter.new(function() end, { launcher = true })
end

-- Every string the frame printed.  The kit falls back to love.graphics.print
-- under the stub (no newText), so recording that call captures the text the
-- panel actually put on screen -- ellipsis and all, which is the point.
local realPrint = love.graphics.print
local function drawAndCapture(imp)
  local seen = {}
  love.graphics.print = function(str, ...)
    seen[#seen + 1] = tostring(str)
    return realPrint(str, ...)
  end
  local ok, err = pcall(LauncherView.draw, imp)
  love.graphics.print = realPrint
  check(ok, "the frame draws: " .. tostring(err))
  return table.concat(seen, "\n")
end

-- ------------------------------------- a failed import explains itself
-- setError stores the reason on imp.detail; the ROM card must print it, not
-- just the "Import failed" headline above it.  Checked on the reporter's
-- phone shape, since a narrow window is exactly where the old budget
-- arithmetic trimmed the paragraph away.
local REASON = "This is a German ROM; only the English releases are supported."
window(360, 780)
local failed = freshLauncher()
failed:setError(REASON, "red")
failed.tab = "red"
local text = drawAndCapture(failed)
check(text:find("Import failed", 1, true) ~= nil,
  "a failed import prints its headline")
check(text:find(REASON, 1, true) ~= nil,
  "a failed import prints the REASON it failed, not just the headline")

-- The same on a desktop window, so the detail is not an artefact of one shape.
window(1280, 720)
local failedWide = freshLauncher()
failedWide:setError(REASON, "red")
failedWide.tab = "red"
check(drawAndCapture(failedWide):find(REASON, 1, true) ~= nil,
  "the failure reason survives on a desktop window too")

-- ------------------------------- settings labels stay readable in portrait
-- Every core row's label must print in FULL.  Side by side they could not,
-- so a narrow panel stacks the label on its own line above its control; the
-- assertion is on the text, not on the layout mode, because "the label is
-- readable" is the property that broke.
local function settingsText(w, h)
  window(w, h)
  local imp = freshLauncher()
  imp:_openSettings()
  check(imp._settings ~= nil, "the gear opens the settings model")
  drawAndCapture(imp)
  local output = {drawAndCapture(imp)}
  for scroll = 200, imp._settings.maxScroll or 0, 200 do
    imp._settings.scroll = scroll
    output[#output + 1] = drawAndCapture(imp)
  end
  return table.concat(output, "\n")
end

local LONG_LABELS = { "Text Speed", "Battle Animation", "Battle Style" }
local portrait = settingsText(360, 780)
for _, label in ipairs(LONG_LABELS) do
  check(portrait:find(label, 1, true) ~= nil,
    ("portrait settings print %q in full"):format(label))
end
check(portrait:find("Bat...", 1, true) == nil,
  "no settings label is clipped to an ellipsis on a portrait phone")

-- A desktop window has room for the side-by-side shape and must not regress.
local desktop = settingsText(1280, 720)
for _, label in ipairs(LONG_LABELS) do
  check(desktop:find(label, 1, true) ~= nil,
    ("desktop settings print %q in full"):format(label))
end

-- ----------------------------------------------- the layout audit sweep
local function clipped(r)
  local x1, y1, x2, y2 = r.x, r.y, r.x + r.w, r.y + r.h
  if r.clip then
    x1 = math.max(x1, r.clip.x); y1 = math.max(y1, r.clip.y)
    x2 = math.min(x2, r.clip.x + r.clip.w); y2 = math.min(y2, r.clip.y + r.clip.h)
  end
  if x2 - x1 <= 1 or y2 - y1 <= 1 then return nil end
  return x1, y1, x2, y2
end

local function overlap(a, b)
  local ax1, ay1, ax2, ay2 = clipped(a)
  if not ax1 then return false end
  local bx1, by1, bx2, by2 = clipped(b)
  if not bx1 then return false end
  return math.min(ax2, bx2) - math.max(ax1, bx1) > 1
     and math.min(ay2, by2) - math.max(ay1, by1) > 1
end

-- `scrolling` windows are allowed to draw below the fold: that is the page
-- scroll doing its job, and the reach test covers it.
local function auditFrame(label, W, H, scrolling)
  local controls = {}
  for _, r in ipairs(Kit.audit or {}) do
    if r.class == "control" then controls[#controls + 1] = r end
  end
  check(#controls > 0, label .. ": the frame dispatched controls at all")
  local collisions, escapes = 0, 0
  for i = 1, #controls do
    local a = controls[i]
    local x1, y1, x2, y2 = clipped(a)
    if x1 and not scrolling
        and (x1 < -0.5 or y1 < -0.5 or x2 > W + 0.5 or y2 > H + 0.5) then
      escapes = escapes + 1
      print(("  escape: %s (%.0f,%.0f %.0fx%.0f)")
        :format(a.label, a.x, a.y, a.w, a.h))
    end
    for j = i + 1, #controls do
      if overlap(a, controls[j]) then
        collisions = collisions + 1
        print(("  overlap: '%s' vs '%s' at (%.0f,%.0f) / (%.0f,%.0f)")
          :format(a.label, controls[j].label, a.x, a.y,
            controls[j].x, controls[j].y))
      end
    end
  end
  check(collisions == 0, label .. ": no two controls overlap")
  check(escapes == 0, label .. ": every control stays inside the window")
end

-- The shapes the reports came from, plus the desktop ones they have to keep
-- serving: portrait phones, a 150%-scaled Linux handheld, 4:3, and widescreen.
local SIZES = {
  { 360, 780 }, { 412, 915 }, { 480, 900 }, { 720, 1280 },
  { 1280, 720 }, { 1024, 768 }, { 900, 700 }, { 1920, 1080 },
}

for _, size in ipairs(SIZES) do
  local W, H = size[1], size[2]
  window(W, H)
  for _, tab in ipairs({ "red", "yellow", "mods", "find" }) do
    local imp = freshLauncher()
    imp.tab = tab
    LauncherView.draw(imp)        -- warm frame: pagination settles
    Kit.audit = {}
    local ok, err = pcall(LauncherView.draw, imp)
    Kit.audit = ok and Kit.audit or nil
    check(ok, ("%dx%d %s draws: %s"):format(W, H, tab, tostring(err)))
    if ok then
      auditFrame(("%dx%d %s"):format(W, H, tab), W, H,
        (imp._pageScrollMax or 0) > 0)
    end
    Kit.audit = nil
  end
  -- The settings panel is its own layout and its own reflow.
  local imp = freshLauncher()
  imp:_openSettings()
  LauncherView.draw(imp)
  Kit.audit = {}
  local ok, err = pcall(LauncherView.draw, imp)
  Kit.audit = ok and Kit.audit or nil
  check(ok, ("%dx%d settings draws: %s"):format(W, H, tostring(err)))
  if ok then auditFrame(("%dx%d settings"):format(W, H), W, H, false) end
  Kit.audit = nil
end

T.finish("launcher panel reflow")
