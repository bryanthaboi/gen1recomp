return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local Kit = require("src.ui.kit.Kit")
  local Transition = require("src.ui.kit.Transition")
  local GameVersion = require("src.core.GameVersion")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/2437"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  local failed = false
  local function verdict(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
  end

  love.window.setMode(853, 480, { resizable = true, highdpi = true })
  U.wait(2)

  local imp = RomImporter.new(function() end, { launcher = true })
  for _, v in ipairs(GameVersion.ORDER) do imp.ready[v] = true end
  imp._refreshMods = function() end
  imp._refreshFindSources = function() end
  imp._refreshFind = function() end
  imp._pumpFindFetch = function() end
  imp._findFetch = nil
  imp._resetModOrder = function(self) self.didReset = true end

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
      for _ = 1, 4000 do
        imp:update(1 / 60)
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
    verdict(false, "shot " .. name)
    return false
  end

  local function rects()
    audit = true
    frames(1)
    local out = type(audit) == "table" and audit or {}
    audit = nil
    return out
  end

  local function find(label)
    for _, r in ipairs(rects()) do
      if r.label == label then return r end
    end
  end

  local function visible(r)
    local W, H = love.graphics.getDimensions()
    local c = r.clip or { x = 0, y = 0, w = W, h = H }
    return r.y >= c.y - 0.5 and r.y + r.h <= c.y + c.h + 0.5
      and r.y >= 0 and r.y + r.h <= H + 0.5
  end

  local tid = 0
  local function drag(r, fromY, toY)
    tid = tid + 1
    local x = r.x + 20
    imp:touchpressed(tid, x, fromY)
    frames(1)
    local steps = 6
    for i = 1, steps do
      imp:touchmoved(tid, x, fromY + (toY - fromY) * i / steps)
      frames(1)
    end
    imp:touchreleased(tid, x, toY)
    frames(2)
  end

  local function tap(r)
    local after = love.timer.getTime() + 0.4
    while love.timer.getTime() < after do frames(1) end
    tid = tid + 1
    local x, y = r.x + r.w / 2, r.y + r.h / 2
    imp:touchpressed(tid, x, y)
    frames(1)
    imp:touchreleased(tid, x, y)
    frames(3)
  end

  local function closeOnScreen()
    local W, H = love.graphics.getDimensions()
    for _, r in ipairs(rects()) do
      if r.label == "Close" and not r.clip then
        return r.y >= 0 and r.y + r.h <= H + 0.5
      end
    end
    return false
  end

  imp:_switchTab("mods")
  settle()
  imp._modScopePopup = true
  settle()
  shot("2437_scope_853x480_open.png")
  local state = imp._modalScroll and imp._modalScroll._modScopePopup
  verdict(state ~= nil and state.maxScroll > 0, "scope_list_scrolls_853x480")
  verdict(closeOnScreen(), "scope_close_visible_853x480")
  if state then
    local r = state.rect
    drag(r, r.y + r.h - 6, r.y + 6)
    verdict(state.scroll > 0 and imp._modScopePopup ~= nil, "scope_touch_drag_853x480")
    shot("2437_scope_853x480_dragged.png")
    local leaf = find(GameVersion.info("leafgreen").label)
    verdict(leaf ~= nil and visible(leaf), "scope_leafgreen_visible_after_drag")
    if leaf then tap(leaf) end
    verdict(imp.modScope == "leafgreen" and imp._modScopePopup == nil, "scope_tap_leafgreen")
  end

  love.window.setMode(780, 360, { resizable = true, highdpi = true })
  settle()
  imp._modScopePopup = true
  settle()
  shot("2437_scope_780x360_open.png")
  verdict(closeOnScreen(), "scope_close_visible_780x360")
  imp._modScopePopup = nil
  settle()

  imp._sortPopup = "mods"
  settle()
  shot("2437_sort_780x360_open.png")
  verdict(closeOnScreen(), "sort_close_visible_780x360")
  state = imp._modalScroll and imp._modalScroll._sortPopup
  if state and state.maxScroll > 0 then
    local r = state.rect
    drag(r, r.y + r.h - 6, r.y + 6)
    shot("2437_sort_780x360_dragged.png")
  end
  local reset = find("Reset load order")
  verdict(reset ~= nil and visible(reset), "sort_reset_reachable_780x360")
  if reset then tap(reset) end
  verdict(imp.didReset == true, "sort_reset_tapped_780x360")
  imp._sortPopup = nil

  love.window.setMode(853, 480, { resizable = true, highdpi = true })
  imp.findSources = {}
  for i = 1, 6 do
    imp.findSources[i] = { feed = "https://example.invalid/" .. i .. "/index.json",
      label = "example/index-" .. i }
  end
  imp:_switchTab("find")
  settle()
  imp.findIndex = { schemaVersion = 1, mods = {},
    categories = { "graphics", "gameplay", "audio", "qol", "translation", "challenge", "ui" } }
  imp.findLoaded = true
  imp._filterPopup = true
  settle()
  shot("2437_filter_853x480_open.png")
  verdict(closeOnScreen(), "filter_close_visible_853x480")
  state = imp._modalScroll and imp._modalScroll._filterPopup
  verdict(state ~= nil and state.maxScroll > 0, "filter_list_scrolls_853x480")
  if state then
    local r = state.rect
    drag(r, r.y + r.h - 6, r.y + 6)
    verdict(state.scroll > 0 and imp._filterPopup ~= nil, "filter_touch_drag_853x480")
    shot("2437_filter_853x480_dragged.png")
    local ui = find("ui")
    verdict(ui ~= nil and visible(ui), "filter_last_category_visible")
    if ui then tap(ui) end
    verdict(imp.findCategory == "ui", "filter_tap_last_category")
  end
  imp._filterPopup = nil
  settle()

  love.window.setMode(780, 360, { resizable = true, highdpi = true })
  imp._indexManage = true
  settle()
  shot("2437_indexes_780x360_open.png")
  verdict(closeOnScreen(), "indexes_close_visible_780x360")
  state = imp._modalScroll and imp._modalScroll._indexManage
  if state and state.maxScroll > 0 then
    local r = state.rect
    drag(r, r.y + r.h - 6, r.y + 6)
    verdict(state.scroll > 0, "indexes_touch_drag_780x360")
    shot("2437_indexes_780x360_dragged.png")
  end
  imp._indexManage = nil
  settle()

  imp:_switchTab("mods")
  settle()
  imp._modHeaderActionsPopup = true
  settle()
  shot("2437_modheadact_780x360_open.png")
  verdict(closeOnScreen(), "modheadact_close_visible_780x360")
  state = imp._modalScroll and imp._modalScroll._modHeaderActionsPopup
  verdict(state ~= nil and state.maxScroll > 0, "modheadact_list_scrolls_780x360")
  if state then
    local r = state.rect
    drag(r, r.y + r.h - 6, r.y + 6)
    verdict(state.scroll > 0 and imp._modHeaderActionsPopup ~= nil, "modheadact_touch_drag_780x360")
    shot("2437_modheadact_780x360_dragged.png")
    local sortRow = find("Sort mods...")
    verdict(sortRow ~= nil and visible(sortRow), "modheadact_sort_visible_after_drag")
    if sortRow then tap(sortRow) end
    verdict(imp._sortPopup == "mods" and imp._modHeaderActionsPopup == nil, "modheadact_tap_sort_mods")
  end
  imp._sortPopup = nil
  settle()

  local list = {}
  for i = 1, 8 do list[i] = { name = "Profile " .. i } end
  imp._profileCache = { options = {}, list = list, active = "Profile 1" }
  imp._profilesPopup = true
  settle()
  shot("2437_profiles_780x360_open.png")
  verdict(closeOnScreen(), "profiles_close_visible_780x360")
  state = imp._modalScroll and imp._modalScroll._profilesPopup
  if state and state.maxScroll > 0 then
    local r = state.rect
    drag(r, r.y + r.h - 6, r.y + 6)
    verdict(state.scroll > 0, "profiles_touch_drag_780x360")
    shot("2437_profiles_780x360_dragged.png")
  else
    verdict(false, "profiles_touch_drag_780x360")
  end
  imp._profilesPopup = nil
  settle()

  local devices = {}
  for i = 1, 4 do devices[i] = { id = "d" .. i, label = "Device " .. i, current = i == 1 } end
  imp._syncTransportOk = true
  imp._sync = {
    phase = "idle", status = "Last sync a minute ago", devices = devices,
    codes = { code1 = "ABCD-EFGH", code2 = "IJKL-MNOP" }, conflicts = {},
    busy = function() return false end, linked = function() return true end,
    update = function() end,
  }
  imp._syncModal = { view = "home" }
  settle()
  shot("2437_sync_780x360_open.png")
  verdict(closeOnScreen(), "sync_close_visible_780x360")
  state = imp._modalScroll and imp._modalScroll._syncModal
  if state and state.maxScroll > 0 then
    local r = state.rect
    drag(r, r.y + r.h - 6, r.y + 6)
    verdict(state.scroll > 0, "sync_touch_drag_780x360")
    shot("2437_sync_780x360_dragged.png")
    local unlink = find("Unlink this device")
    verdict(unlink ~= nil and visible(unlink), "sync_unlink_visible_after_drag")
  else
    verdict(state ~= nil, "sync_body_fits_780x360")
  end
  imp._syncModal = nil
  imp._sync = false
  settle()

  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  imp:_switchTab("mods")
  settle()
  imp._modScopePopup = true
  settle()
  shot("2437_scope_1280x720_open.png")
  verdict(closeOnScreen(), "scope_close_visible_1280x720")
  imp._modScopePopup = nil

  love.event.quit(failed and 1 or 0)
end
