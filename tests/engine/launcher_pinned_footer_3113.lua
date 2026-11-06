package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end
love.graphics.polygon = love.graphics.polygon or function() end

local Kit = require("src.ui.kit.Kit")
local Layout = require("src.ui.kit.Layout")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

love.mouse.getPosition = function() return -100, -100 end
love.mouse.isDown = function() return false end

local URL = "https://bois.icu"
local urlDraws
local kitText = Kit.text
Kit.text = function(font, text, x, y, ...)
  if urlDraws and text == URL then
    local c = Kit._clipRect
    urlDraws[#urlDraws + 1] = { x = c and c.x or 0, y = y, w = 2,
      h = Kit.textHeight(font), clip = c and { x = c.x, y = c.y, w = c.w, h = c.h } or nil }
  end
  return kitText(font, text, x, y, ...)
end

local checkState = { status = "available", latest = "0.4.1" }
local function stubCheck(imp)
  imp.Check = {
    state = function() return checkState end,
    download = function() end, start = function() end,
    releaseUrl = function() return "" end,
    fullUpdateAction = function() return { label = "Open releases", url = "" } end,
  }
end

local mods = {}
for i = 1, 60 do
  mods[i] = {
    id = "mod" .. i, name = "Mod " .. i, version = "1.0.0",
    status = "ok", badge = "gameplay", description = "a mod",
    enabledByVersion = { red = true },
  }
end
local fewMods = {}
for i = 1, 12 do fewMods[i] = mods[i] end

local SIZES = {
  { 360, 640 }, { 375, 667 },
  { 390, 844, { 0, 59, 390, 751 } },
  { 844, 390, { 59, 0, 726, 369 } },
  { 768, 1024 }, { 834, 1194 }, { 1024, 600 },
  { 1280, 720 }, { 1400, 900 },
}

local CASES = {
  { "red", "red 1 slot", function(imp)
    imp.ready = { red = true }
    imp.slots = { red = { { id = "1", name = "Slot 1" } } }
    imp._ensureSlots = function() end
  end },
  { "red", "red 8 slots", function(imp)
    imp.ready = { red = true }
    imp.slots = { red = {} }
    for i = 1, 8 do imp.slots.red[i] = { id = tostring(i), name = "Slot " .. i } end
    imp._ensureSlots = function() end
  end },
  { "mods", "mods 12", function(imp)
    imp.mods = fewMods
    imp._ensureMods = function() return fewMods end
  end },
  { "mods", "mods 60", function(imp)
    imp.mods = mods
    imp._ensureMods = function() return mods end
  end },
  { "find", "find", function() end },
  { "skins", "skins", function() end },
  { "online", "online", function() end },
  { "box", "box", function() end },
}

local function window(w, h, safe)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
  love.window.getSafeArea = function()
    if safe then return safe[1], safe[2], safe[3], safe[4] end
    return 0, 0, w, h
  end
end

local function fullyOnScreen(r, W, H)
  return r.x >= -0.5 and r.y >= -0.5 and r.x + r.w <= W + 0.5 and r.y + r.h <= H + 0.5
end

local function visibleSpan(r, W, H)
  local x1, y1, x2, y2 = r.x, r.y, r.x + r.w, r.y + r.h
  if r.clip then
    x1, y1 = math.max(x1, r.clip.x), math.max(y1, r.clip.y)
    x2, y2 = math.min(x2, r.clip.x + r.clip.w), math.min(y2, r.clip.y + r.clip.h)
  end
  x1, y1 = math.max(x1, 0), math.max(y1, 0)
  x2, y2 = math.min(x2, W), math.min(y2, H)
  return (x2 - x1) > 1 and (y2 - y1) > 1
end

local function findRow(rows, text)
  for _, r in ipairs(rows) do
    if r.class == "control" and r.label:find(text, 1, true) then return r end
  end
end

local function auditAt(imp, tab, at)
  imp._tabScroll[tab] = at
  Kit.audit = {}
  LauncherView.draw(imp)
  local rows = Kit.audit
  Kit.audit = nil
  return rows
end

local function pinned(r, rect, W, H)
  if not r then return false end
  local inRegion = r.clip and math.abs(r.clip.y - rect.y) < 0.5
    and math.abs(r.clip.h - rect.h) < 0.5
  return not inRegion and fullyOnScreen(r, W, H)
    and r.y >= rect.y + rect.h - 0.5
end

for _, size in ipairs(SIZES) do
  local W, H, safe = size[1], size[2], size[3]
  window(W, H, safe)
  local m = Layout.metrics(1200)
  for _, case in ipairs(CASES) do
    local tab = case[1]
    local label = ("%dx%d %s"):format(W, H, case[2])
    local imp = RomImporter.new(function() end, { launcher = true })
    stubCheck(imp)
    imp.tab = tab
    case[3](imp)
    LauncherView.draw(imp)
    LauncherView.draw(imp)
    local rect = imp._tabRegionRect
    local bar = imp._footerBarRect
    check(bar ~= nil and math.abs(rect.y + rect.h - bar.y) < 0.5,
      label .. ": the region ends where the footer bar starts")
    check(bar ~= nil and math.abs(bar.y + bar.h - (m.top + m.h)) < 0.5,
      label .. ": the footer bar ends at the safe bottom")
    local maxAt = imp._tabScrollMax[tab] or 0
    local firstUp, firstNotes
    for _, at in ipairs({ 0, math.floor(maxAt / 2), 1e6 }) do
      local rows = auditAt(imp, tab, at)
      local up = findRow(rows, "Update v0.4.1")
      local notes = findRow(rows, "Patch notes")
      local where = (" at scroll %s"):format(at == 1e6 and "max" or tostring(at))
      check(pinned(up, rect, W, H),
        label .. ": the update control is on screen without scrolling" .. where
          .. (up and (" (y " .. up.y .. ")") or " (not drawn)"))
      check(pinned(notes, rect, W, H),
        label .. ": Patch notes is on screen without scrolling" .. where)
      if up then
        firstUp = firstUp or up
        check(math.abs(up.y - firstUp.y) < 0.5 and math.abs(up.x - firstUp.x) < 0.5,
          label .. ": the update control does not move with the scroll" .. where)
      end
      if notes then
        firstNotes = firstNotes or notes
        check(math.abs(notes.y - firstNotes.y) < 0.5,
          label .. ": Patch notes does not move with the scroll" .. where)
      end
    end
    auditAt(imp, tab, 1e6)
    urlDraws = {}
    auditAt(imp, tab, 1e6)
    local trustShown = false
    for _, r in ipairs(urlDraws) do
      if visibleSpan(r, W, H) and r.clip and r.y + r.h <= rect.y + rect.h + 0.5 then
        trustShown = true
      end
    end
    urlDraws = nil
    check(trustShown, label .. ": the trust note link is reachable at the tail of the region")
  end
end

local STATES = {
  { status = "idle" }, { status = "checking" },
  { status = "available", latest = "0.4.1" }, { status = "ready" },
  { status = "downloading", progress = 0.42 }, { status = "full_downloading", progress = 0.5 },
  { status = "needs_full" },
}
window(360, 640)
for _, st in ipairs(STATES) do
  checkState = st
  local imp = RomImporter.new(function() end, { launcher = true })
  stubCheck(imp)
  CASES[1][3](imp)
  imp.tab = "red"
  LauncherView.draw(imp)
  local _, upLabel = LauncherView._updateControl(imp)
  local rows = auditAt(imp, "red", 0)
  local up = findRow(rows, upLabel)
  local notes = findRow(rows, "Patch notes")
  local rect = imp._tabRegionRect
  check(pinned(up, rect, 360, 640),
    "360x640 " .. st.status .. ": the updater chip '" .. upLabel .. "' is on screen at the top")
  check(pinned(notes, rect, 360, 640),
    "360x640 " .. st.status .. ": Patch notes is on screen at the top")
  check(up and notes and (up.y + up.h <= notes.y + 0.5 or notes.y + notes.h <= up.y + 0.5
      or up.x + up.w <= notes.x + 0.5 or notes.x + notes.w <= up.x + 0.5),
    "360x640 " .. st.status .. ": the updater chip and Patch notes do not overlap")
end

T.finish("launcher pinned footer bar")
