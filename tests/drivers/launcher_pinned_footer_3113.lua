return function()
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local Kit = require("src.ui.kit.Kit")
  local Layout = require("src.ui.kit.Layout")
  local Transition = require("src.ui.kit.Transition")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/3113"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')

  local safe = nil
  love.window.getSafeArea = function()
    if safe then return safe[1], safe[2], safe[3], safe[4] end
    local w, h = love.graphics.getDimensions()
    return 0, 0, w, h
  end

  local mods = {}
  for i = 1, 60 do
    mods[i] = {
      id = "mod" .. i, name = "Mod " .. i, version = "1.0.0",
      status = "ok", badge = "gameplay", description = "a mod",
      enabledByVersion = { blue = true },
    }
  end

  local imp = RomImporter.new(function() end, { launcher = true })
  imp.Check = {
    state = function() return { status = "available", latest = "0.4.1" } end,
    download = function() end, start = function() end,
    releaseUrl = function() return "" end,
  }
  imp.ready.blue = true
  imp.tab = "blue"
  imp.slots.blue = { { id = "1", label = "Save 1", exists = true,
    meta = { badges = 3, timeText = "8:07", dexCount = 40 } } }
  imp.activeSlot.blue = "1"
  imp._ensureSlots = function() end
  imp.mods = mods
  imp._ensureMods = function() return mods end
  imp._refreshMods = function() end

  local drawn, pending, audit = 0, nil, nil
  love.draw = function()
    if audit then Kit.audit = {} end
    imp:draw()
    if audit then audit, Kit.audit = Kit.audit, nil end
    drawn = drawn + 1
    if pending then
      local path = pending
      pending = nil
      love.graphics.captureScreenshot(function(imagedata)
        local f = io.open(path, "wb")
        if f then f:write(imagedata:encode("png"):getString()) f:close() end
      end)
    end
  end

  local function frames(n)
    for _ = 1, n do
      local seen = drawn
      imp:update(1 / 60)
      for _ = 1, 4000 do
        coroutine.yield()
        if drawn > seen then break end
      end
    end
  end

  local function settle()
    frames(1)
    Transition.reset()
    frames(3)
  end

  local failed = false
  local function verdict(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
  end

  local function shot(name)
    local path = dir .. "/" .. name
    os.remove(path)
    pending = path
    frames(2)
    for _ = 1, 4000 do
      local f = io.open(path, "rb")
      if f then f:close() U.log("shot", name) return true end
      coroutine.yield()
    end
    verdict(false, "shot_" .. name)
    return false
  end

  local function snapshot()
    audit = true
    frames(1)
    local rows = type(audit) == "table" and audit or {}
    audit = nil
    local up, notes
    for _, r in ipairs(rows) do
      if r.label == "Update v0.4.1" then up = r end
      if r.label == "Patch notes" then notes = r end
    end
    return up, notes
  end

  local function pinned(r)
    if not r then return false end
    local W, H = love.graphics.getDimensions()
    local rect = imp._tabRegionRect
    return r.x >= 0 and r.y >= 0 and r.x + r.w <= W and r.y + r.h <= H
      and r.y >= rect.y + rect.h - 0.5
  end

  local function apart(a, b)
    return a and b and (a.y + a.h <= b.y or b.y + b.h <= a.y
      or a.x + a.w <= b.x or b.x + b.w <= a.x)
  end

  local cases = {
    { "390x844", 390, 844, { 0, 59, 390, 751 } },
    { "844x390", 844, 390, { 59, 0, 726, 369 } },
    { "768x1024", 768, 1024, { 0, 24, 768, 980 } },
    { "1400x900", 1400, 900, nil },
  }
  local n = 0
  for _, c in ipairs(cases) do
    safe = c[4]
    love.window.setMode(c[2], c[3], { resizable = true, highdpi = true })
    for _, tab in ipairs({ "blue", "mods" }) do
      imp:_switchTab(tab)
      settle()
      settle()
      imp._tabScroll[imp.tab] = 0
      settle()
      local m = Layout.metrics(1200)
      local rect, bar = imp._tabRegionRect, imp._footerBarRect
      local tag = c[1] .. "_" .. tab
      local up, notes = snapshot()
      verdict(pinned(up), tag .. "_update_visible_at_top")
      verdict(pinned(notes), tag .. "_patch_notes_visible_at_top")
      verdict(apart(up, notes), tag .. "_update_and_notes_apart")
      verdict(bar ~= nil and math.abs(rect.y + rect.h - bar.y) < 0.5
        and math.abs(bar.y + bar.h - (m.top + m.h)) < 0.5, tag .. "_region_ends_at_bar")
      if tab == "blue" or c[1] ~= "844x390" then
        n = n + 1
        shot(string.format("3113_%02d_%s_%s_top_update_pinned.png", n, c[1],
          tab == "blue" and "games" or "mods"))
      end
      imp._tabScroll[imp.tab] = 1e6
      settle()
      local up2 = snapshot()
      verdict(pinned(up2), tag .. "_update_visible_at_bottom")
      verdict(up and up2 and up.y == up2.y and up.x == up2.x, tag .. "_update_does_not_move")
      if tab == "blue" and c[1] == "390x844" then
        n = n + 1
        shot(string.format("3113_%02d_390x844_games_bottom_trust_note.png", n))
      end
    end
  end
  love.event.quit(failed and 1 or 0)
end
