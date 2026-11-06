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

local mods = {}
for i = 1, 12 do
  mods[i] = {
    id = "mod" .. i, name = "Mod " .. i, version = "1.0.0",
    status = "ok", badge = "gameplay", description = "a mod",
    enabledByVersion = { red = true },
  }
end

local SIZES = {
  { 360, 640 }, { 375, 667 },
  { 390, 844, { 0, 59, 390, 751 } },
  { 844, 390, { 59, 0, 726, 369 } },
  { 768, 1024 }, { 834, 1194 }, { 1024, 600 },
  { 1280, 720 }, { 1400, 900 },
}

local CASES = {
  { "red", function(imp)
    imp.ready = { red = true }
    imp.slots = { red = { { id = "1", name = "Slot 1" } } }
    imp._ensureSlots = function() end
  end },
  { "red", function(imp)
    imp.ready = { red = true }
    imp.slots = { red = {} }
    for i = 1, 8 do imp.slots.red[i] = { id = tostring(i), name = "Slot " .. i } end
    imp._ensureSlots = function() end
  end },
  { "mods", function(imp)
    imp.mods = mods
    imp._ensureMods = function() return mods end
  end },
  { "find", function() end },
  { "skins", function() end },
  { "online", function() end },
  { "box", function() end },
}

local function window(w, h, safe)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
  love.window.getSafeArea = function()
    if safe then return safe[1], safe[2], safe[3], safe[4] end
    return 0, 0, w, h
  end
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

local function auditAt(imp, tab, at)
  imp._tabScroll[tab] = at
  Kit.audit = {}
  LauncherView.draw(imp)
  local rows = Kit.audit
  Kit.audit = nil
  return rows, imp._tabScroll[tab] or 0
end

for _, size in ipairs(SIZES) do
  local W, H, safe = size[1], size[2], size[3]
  window(W, H, safe)
  local m = Layout.metrics(1200)
  for _, case in ipairs(CASES) do
    local tab = case[1]
    local label = ("%dx%d %s"):format(W, H, tab)
    local imp = RomImporter.new(function() end, { launcher = true })
    imp.tab = tab
    case[2](imp)
    LauncherView.draw(imp)
    LauncherView.draw(imp)
    local rect = imp._tabRegionRect
    local pageMax = imp._pageScrollMax or 0
    local regionMax = imp._tabScrollMax[tab] or 0
    check(pageMax == 0, label .. ": no page scroll (page " .. pageMax .. ")")
    check(not (pageMax > 0 and regionMax > 0),
      label .. ": at most one scroller has travel")
    local bar = imp._footerBarRect
    check(bar ~= nil and math.abs(rect.y + rect.h - bar.y) < 0.5,
      label .. ": the tab region runs down to the pinned footer bar")
    check(bar ~= nil and math.abs(bar.y + bar.h - (m.top + m.h)) < 0.5,
      label .. ": the footer bar ends at the bottom of the safe area")
    check(rect.y + rect.h <= H + 0.5, label .. ": the region is never taller than the screen")

    local seen, shown = {}, {}
    local step = math.max(1, math.floor(rect.h * 0.75))
    local at, footerShown = 0, false
    for _ = 1, 60 do
      local rows, real = auditAt(imp, tab, at)
      for _, r in ipairs(rows) do
        if r.class == "control" then
          local inRegion = r.clip and r.clip.y >= rect.y - 0.5
          local key = ("%s|%d|%d"):format(r.label, math.floor(r.x),
            math.floor(r.y + (inRegion and real or 0)))
          seen[key] = true
          if visibleSpan(r, W, H) then
            shown[key] = true
            if r.label == "Patch notes" or r.label:find("Patch notes", 1, true) then
              footerShown = true
            end
          end
        end
      end
      if real >= (imp._tabScrollMax[tab] or 0) then break end
      at = real + step
    end
    local bottom = imp._tabScrollMax[tab] or 0
    for _ = 1, 2 do auditAt(imp, tab, 1e6) end
    urlDraws = {}
    auditAt(imp, tab, 1e6)
    local trustShown = false
    for _, r in ipairs(urlDraws) do
      if visibleSpan(r, W, H) then trustShown = true end
    end
    urlDraws = nil
    check(math.abs((imp._tabScrollMax[tab] or 0) - bottom) < 0.5,
      label .. ": resting at the bottom does not grow the content ("
        .. bottom .. " -> " .. tostring(imp._tabScrollMax[tab]) .. ")")
    local missing = {}
    for key in pairs(seen) do
      if not shown[key] then missing[#missing + 1] = key end
    end
    table.sort(missing)
    check(#missing == 0, label .. ": every control can be scrolled into reach"
      .. (#missing > 0 and (" (" .. table.concat(missing, ", ") .. ")") or ""))
    check(footerShown, label .. ": Patch notes is on screen")
    check(trustShown, label .. ": the trust note link is reachable at the tail of the region")
  end
end

window(390, 844, { 0, 59, 390, 751 })
local pad = RomImporter.new(function() end, { launcher = true })
pad.tab = "red"
CASES[1][2](pad)
LauncherView.draw(pad)
LauncherView.draw(pad)
check((pad._tabScrollMax.red or 0) > 0, "the phone game tab has travel")
check((pad._tabScroll.red or 0) == 0, "and starts at the top")
Kit.setFocus("patch-notes")
LauncherView.draw(pad)
Kit.audit = {}
LauncherView.draw(pad)
local notes
for _, r in ipairs(Kit.audit) do
  if r.label:find("Patch notes", 1, true) then notes = r end
end
Kit.audit = nil
check(notes ~= nil and visibleSpan(notes, 390, 844) and notes.clip == nil,
  "focusing Patch notes shows it without scrolling the region")
check((pad._tabScroll.red or 0) == 0, "and the region stays at the top")
local region = pad._tabRegionRect
local deep
for i = 1, Kit._navN or 0 do
  local slot = Kit._nav[i]
  if slot.y >= region.y + region.h and (not deep or slot.y > deep.y) then
    deep = { id = slot.id, y = slot.y }
  end
end
check(deep ~= nil, "a control sits below the fold of the phone game tab")
Kit.setFocus(deep and deep.id)
LauncherView.draw(pad)
LauncherView.draw(pad)
check((pad._tabScroll.red or 0) > 0,
  "moving the focus ring below the fold scrolls the region to show it")
local parked = pad._tabScroll.red
pad._tabScroll.red = 0
LauncherView.draw(pad)
check(pad._tabScroll.red == 0 and parked > 0,
  "and the ring does not pull the region back once the player scrolls away")
Kit.setFocus(nil)

T.finish("launcher single scroller")
