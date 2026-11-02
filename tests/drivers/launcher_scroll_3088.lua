return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local Kit = require("src.ui.kit.Kit")
  local Layout = require("src.ui.kit.Layout")
  local Transition = require("src.ui.kit.Transition")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/3088"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  local failed = false
  local function verdict(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
  end

  local safe = { 0, 59, 390, 751 }
  love.window.getSafeArea = function() return safe[1], safe[2], safe[3], safe[4] end
  love.window.setMode(390, 844, { resizable = true, highdpi = true })
  U.wait(2)

  local mods = {}
  for i = 1, 60 do
    mods[i] = {
      id = "mod" .. i, name = "Mod " .. i, version = "1.0.0",
      status = "ok", badge = "gameplay", description = "a mod",
      enabledByVersion = { blue = true },
    }
  end

  local imp = RomImporter.new(function() end, { launcher = true })
  imp.ready.blue = true
  imp.tab = "blue"
  imp.slots.blue = { { id = "1", label = "Save 1", exists = true,
    meta = { badges = 3, timeText = "12:34", dexCount = 40 } } }
  imp.activeSlot.blue = "1"
  imp._ensureSlots = function() end
  imp.mods = mods
  imp._ensureMods = function() return mods end
  imp._refreshMods = function() end

  local drawn, pending, audit, frozen = 0, nil, nil, false
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
      if not frozen then imp:update(1 / 60) end
      for _ = 1, 4000 do
        coroutine.yield()
        if drawn > seen then break end
      end
    end
  end

  local function settle()
    frames(1)
    Transition.reset()
    frames(2)
  end

  local function shot(name, still)
    local path = dir .. "/" .. name
    os.remove(path)
    frozen = still or false
    pending = path
    frames(2)
    for _ = 1, 4000 do
      local f = io.open(path, "rb")
      if f then f:close() U.log("shot", name) frozen = false return true end
      coroutine.yield()
    end
    frozen = false
    verdict(false, "shot " .. name)
    return false
  end

  local function find(label)
    audit = true
    frames(1)
    local rows = type(audit) == "table" and audit or {}
    audit = nil
    for _, r in ipairs(rows) do
      if r.label == label then return r end
    end
  end

  local function onScreen(r)
    if not r then return false end
    local W, H = love.graphics.getDimensions()
    local c = r.clip or { x = 0, y = 0, w = W, h = H }
    local y1, y2 = math.max(r.y, c.y, 0), math.min(r.y + r.h, c.y + c.h, H)
    return y2 - y1 > 1
  end

  local function oneScroller(tag)
    local m = Layout.metrics(1200)
    local rect = imp._tabRegionRect
    local _, H = love.graphics.getDimensions()
    verdict((imp._pageScrollMax or 0) == 0 and rect ~= nil
      and math.abs(rect.y + rect.h - (m.top + m.h)) < 0.5 and rect.y + rect.h <= H + 0.5,
      tag .. "_one_scroller_to_safe_bottom")
  end

  local tid = 0
  local function flick(px, steps)
    tid = tid + 1
    local rect = imp._tabRegionRect
    local x, y = rect.x + 24, rect.y + rect.h - 24
    imp:touchpressed(tid, x, y)
    frames(1)
    for _ = 1, steps do
      y = y - px
      imp:touchmoved(tid, x, y)
      frames(1)
    end
    imp:touchreleased(tid, x, y)
    return x, y
  end

  local function offset() return imp._tabScroll[imp.tab] or 0 end

  settle()
  settle()
  shot("3088_01_games_top.png")
  oneScroller("games_390x844")
  local headerY = imp._tabRegionRect.y
  verdict((imp._tabScrollMax.blue or 0) > 0, "games_390x844_region_has_travel")

  flick(8, 6)
  local released = offset()
  frames(12)
  verdict(offset() > released, "games_offset_keeps_moving_after_release")
  frames(120)
  U.log("games", "released", released, "rest", offset(), "max", imp._tabScrollMax.blue)
  verdict(imp._fling == nil and offset() > released, "games_glide_comes_to_rest")
  flick(30, 6)
  frames(60)
  verdict(imp._fling == nil and offset() == imp._tabScrollMax.blue,
    "games_glide_stops_at_the_end")
  verdict(imp._tabRegionRect.y == headerY, "games_header_stays_pinned")
  verdict(onScreen(find("Patch notes")), "games_footer_visible_at_tail")
  shot("3088_02_games_glide_end_footer.png")

  imp:_switchTab("mods")
  settle()
  settle()
  oneScroller("mods_390x844")
  local x = flick(30, 6)
  frames(4)
  verdict(imp._fling ~= nil, "mods_list_glides_after_release")
  shot("3088_03_mods_mid_glide.png", true)
  local caughtAt = offset()
  tid = tid + 1
  local ty = imp._tabRegionRect.y + 40
  imp:touchpressed(tid, x, ty)
  imp:touchreleased(tid, x, ty)
  local clicked = imp._clickPt ~= nil
  frames(6)
  verdict(not clicked and imp._fling == nil and math.abs(offset() - caughtAt) <= 1,
    "tap_stops_the_glide_without_a_click")

  safe = { 59, 0, 726, 369 }
  love.window.setMode(844, 390, { resizable = true, highdpi = true })
  imp:_switchTab("blue")
  settle()
  settle()
  imp._tabScroll.blue = 0
  settle()
  shot("3088_04_landscape_games.png")
  oneScroller("games_844x390")

  love.event.quit(failed and 1 or 0)
end
