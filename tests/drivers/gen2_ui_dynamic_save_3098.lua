-- tools/run_driver.sh crystal <identity> tests/drivers/gen2_ui_dynamic_save_3098.lua [shotdir]
local U = require("tests.drivers.util")
local Chrome = require("src.ui.gen2.Chrome")

return function(game)
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_ui_dynamic_save_3098"
  local fails = 0
  local function check(name, ok, detail)
    print(("%s %s%s"):format(ok and "PASS" or "FAIL", name, detail and ("  " .. detail) or ""))
    if not ok then fails = fails + 1 end
    return ok
  end

  local function resize(w, h)
    love.window.setMode(w, h, { resizable = true, borderless = true })
    if love.window.setPosition then love.window.setPosition(-30000, -30000) end
    U.wait(20)
  end

  local function loadShot(path)
    U.wait(4)
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    local ok, img = pcall(love.image.newImageData,
      love.filesystem.newFileData(bytes, "shot.png"))
    return ok and img or nil
  end

  local function dark(img, x, y)
    local r, g, b = img:getPixel(x, y)
    return 0.299 * r + 0.587 * g + 0.114 * b < 0.35
  end

  local function darkColumnIn(img, x0, x1, y0, y1)
    if not img then return nil end
    local iw, ih = img:getDimensions()
    x0, x1 = math.max(0, math.floor(x0)), math.min(iw, math.floor(x1))
    y0, y1 = math.max(0, math.floor(y0)), math.min(ih, math.floor(y1))
    for x = x0, x1 - 1 do
      local all = y1 > y0
      for y = y0, y1 - 1 do
        if not dark(img, x, y) then all = false break end
      end
      if all then return x end
    end
  end

  local function topId()
    local top = game.stack:top()
    return top and top.screenId
  end

  local function backToWorld()
    for _ = 1, 20 do
      if game.stack:top() == nil then return end
      U.tap(game, "b")
      U.wait(15)
    end
    while game.stack:top() do
      game.stack:pop()
      U.wait(2)
    end
  end

  U.wait(45)
  local world = game.world
  if not check("3098_world_booted", world and world.map) then
    love.event.quit(1)
    return
  end
  world:warpToMapId("ROUTE_29", 48, 3, "down")
  U.wait(30)
  world.noWildEncounters = true

  local shotN = 0
  for _, sz in ipairs({ { 1280, 720 }, { 1000, 700 } }) do
    local w, h = sz[1], sz[2]
    resize(w, h)
    for _, mode in ipairs({ "dynamic", "centered" }) do
      local tag = ("3098_%dx%d_%s"):format(w, h, mode)
      game.options.uiLayout = mode
      U.wait(4)
      game:openStartMenu()
      for _ = 1, 120 do
        if topId() == "Gen2StartMenu" then break end
        U.wait(1)
      end
      U.wait(10)
      local menu = game.stack:top()
      check(tag .. "_start_menu_up", topId() == "Gen2StartMenu")
      local s = world:fitScale()
      local ox, oy = Chrome.fitOrigin(w, h, s)
      local dock = game:uiDock(w, h, s, ox, oy)
      local tile = 8 * s
      local topX = ox + (dock and dock.dx or 0) * s
      local botY = oy + (dock and dock.dy or 0) * s
      local topY = oy + (dock and dock.dt or 0) * s
      if mode == "dynamic" then
        local right, bottom = topX + 160 * s, botY + 144 * s
        check(tag .. "_dock_flush_right", dock ~= nil and right <= w and right > w - s,
          ("right=%s"):format(dock and tostring(right) or "nil"))
        check(tag .. "_dock_bottom_edge", dock ~= nil and bottom <= h and bottom > h - s,
          ("bottom=%s"):format(dock and tostring(bottom) or "nil"))
        check(tag .. "_dock_top_edge", dock ~= nil and topY >= 0 and topY < s,
          ("top=%s"):format(tostring(topY)))
      else
        check(tag .. "_centered_no_dock", dock == nil)
      end
      shotN = shotN + 1
      local path = DIR .. ("/3098_%02d_%dx%d_%s_start_menu.png"):format(shotN, w, h, mode)
      U.still(game, path)
      local img = loadShot(path)
      local right = topX + 160 * s
      local sx = darkColumnIn(img, right - tile, right, topY + tile, topY + 8 * tile)
      check(tag .. "_shot_start_border_at_" .. (mode == "dynamic" and "window" or "letterbox") .. "_right",
        sx ~= nil, ("x=%s"):format(tostring(sx)))

      local saveIdx
      for i, item in ipairs(menu and menu.items or {}) do
        if item.value == "save" then saveIdx = i end
      end
      check(tag .. "_start_menu_has_save", saveIdx ~= nil)
      if saveIdx then
        menu.list.index = saveIdx
        U.tap(game, "a")
        local panel
        for _ = 1, 900 do
          local top = game.stack:top()
          if top and top.screenId == "Gen2SaveMenu" and top:yesNoVisible() then panel = top break end
          U.wait(1)
        end
        check(tag .. "_save_yes_no_up", panel ~= nil)
        if mode == "dynamic" then
          local d = game:uiDock(w, h, s, ox, oy)
          check(tag .. "_save_clips_start_at_row_12", d and d.clipRow == 12,
            ("clip=%s"):format(tostring(d and d.clipRow)))
        end
        U.wait(4)
        shotN = shotN + 1
        path = DIR .. ("/3098_%02d_%dx%d_%s_save_prompt.png"):format(shotN, w, h, mode)
        U.still(game, path)
        img = loadShot(path)
        check(tag .. "_save_shot_loaded", img ~= nil)
        local px = darkColumnIn(img, right - tile, right, topY + 2 * tile, topY + 8 * tile)
        local stx = darkColumnIn(img, right - tile, right, topY + 10 * tile + 2, topY + 12 * tile - 2)
        local tl = darkColumnIn(img, ox, ox + tile, botY + 13 * tile, botY + 17 * tile)
        local tr = darkColumnIn(img, ox + 160 * s - tile, ox + 160 * s, botY + 13 * tile, botY + 17 * tile)
        local yx = darkColumnIn(img, ox, ox + tile, botY + 8 * tile, botY + 11 * tile)
        check(tag .. "_save_shot_panel_border_at_right", px ~= nil, ("x=%s"):format(tostring(px)))
        check(tag .. "_save_shot_start_border_same_column", stx ~= nil and stx == px,
          ("x=%s"):format(tostring(stx)))
        check(tag .. "_save_shot_text_box_left_at_letterbox_left", tl ~= nil, ("x=%s"):format(tostring(tl)))
        check(tag .. "_save_shot_text_box_right_at_letterbox_right", tr ~= nil, ("x=%s"):format(tostring(tr)))
        check(tag .. "_save_shot_yes_no_over_text_box_left", yx ~= nil and tl ~= nil and yx == tl,
          ("yesNo=%s text=%s"):format(tostring(yx), tostring(tl)))
        if mode == "dynamic" and px and right - (ox + 160 * s) >= tile then
          local low = darkColumnIn(img, px, px + 1, topY + 12 * tile + 2, botY + 18 * tile - 2)
          check(tag .. "_save_shot_no_start_box_beside_text_box", low == nil,
            ("x=%s"):format(tostring(low)))
        end
      end
      backToWorld()
      U.wait(10)
    end
    for _, mode in ipairs({ "dynamic", "centered" }) do
      local tag = ("3098_%dx%d_%s_mart"):format(w, h, mode)
      game.options.uiLayout = mode
      U.wait(4)
      world:openMart(0, 0)
      for _ = 1, 120 do
        if topId() == "Gen2MartMenu" then break end
        U.wait(1)
      end
      U.wait(10)
      check(tag .. "_up", topId() == "Gen2MartMenu")
      local s = world:fitScale()
      local ox, oy = Chrome.fitOrigin(w, h, s)
      local dock = game:uiDock(w, h, s, ox, oy)
      local tile = 8 * s
      local botY = oy + (dock and dock.dy or 0) * s
      shotN = shotN + 1
      local path = DIR .. ("/3098_%02d_%dx%d_%s_mart_menu.png"):format(shotN, w, h, mode)
      U.still(game, path)
      local img = loadShot(path)
      check(tag .. "_shot_loaded", img ~= nil)
      local menuL = darkColumnIn(img, ox, ox + tile, botY + tile, botY + 8 * tile)
      local textL = darkColumnIn(img, ox, ox + tile, botY + 13 * tile, botY + 17 * tile)
      local textR = darkColumnIn(img, ox + 160 * s - tile, ox + 160 * s, botY + 13 * tile, botY + 17 * tile)
      check(tag .. "_menu_box_on_text_box_rows", menuL ~= nil, ("x=%s"):format(tostring(menuL)))
      check(tag .. "_text_box_left_at_letterbox_left", textL ~= nil, ("x=%s"):format(tostring(textL)))
      check(tag .. "_text_box_right_at_letterbox_right", textR ~= nil, ("x=%s"):format(tostring(textR)))
      check(tag .. "_menu_and_text_box_share_a_column", menuL ~= nil and menuL == textL,
        ("menu=%s text=%s"):format(tostring(menuL), tostring(textL)))
      if mode == "dynamic" then
        local bottom = botY + 144 * s
        check(tag .. "_text_box_on_window_bottom", bottom <= h and bottom > h - s,
          ("bottom=%s h=%d"):format(tostring(bottom), h))
      end
      backToWorld()
      U.wait(10)
    end
  end
  print(("[3098] done, %d fail(s)"):format(fails))
  love.event.quit(fails == 0 and 0 or 1)
end
