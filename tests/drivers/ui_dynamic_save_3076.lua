return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Renderer = require("src.render.Renderer")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local fails = 0
  local function check(name, ok, detail)
    print(("%s %s%s"):format(ok and "PASS" or "FAIL", name, detail and ("  " .. detail) or ""))
    if not ok then fails = fails + 1 end
  end

  local draws = 0
  local baseEnd = Renderer.endFrame
  Renderer.endFrame = function(...)
    draws = draws + 1
    return baseEnd(...)
  end
  local function settle(n)
    local target = draws + (n or 3)
    for _ = 1, 20000 do
      if draws >= target then return end
      coroutine.yield()
    end
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

  local function darkRowIn(img, y0, y1, x0, x1)
    if not img then return nil end
    local iw, ih = img:getDimensions()
    x0, x1 = math.max(0, math.floor(x0)), math.min(iw, math.floor(x1))
    y0, y1 = math.max(0, math.floor(y0)), math.min(ih, math.floor(y1))
    for y = y0, y1 - 1 do
      local all = x1 > x0
      for x = x0, x1 - 1 do
        if not dark(img, x, y) then all = false break end
      end
      if all then return y end
    end
  end

  local function split()
    local group, shared = {}, {}
    for _, a in ipairs(Renderer.uiAnchors or {}) do
      if a.canvas == Renderer.canvas then shared[#shared + 1] = a
      else group[#group + 1] = a end
    end
    return group, shared
  end

  local function place(R, a)
    if a.anchor == "topright" then
      return R.vux + R.vuw - (R.uiw - (a.x + a.w)) * R.Ux - a.w * R.Ux,
             R.vuy + a.y * R.Uy
    elseif a.anchor == "bottom" then
      return R.uox + a.x * R.Ux, R.vuy + R.vuh - (R.uih - a.y) * R.Uy
    end
    return R.uox + a.x * R.Ux, R.uoy + a.y * R.Uy
  end

  local function findItem(menu, label)
    for i, it in ipairs(menu.items or {}) do
      if it.label == label then return i end
    end
  end

  local function backToWorld()
    for _ = 1, 10 do
      if game.stack:top() == game.overworld then return end
      U.tap(game, "b")
      U.wait(20)
    end
    while game.stack:top() ~= game.overworld and #game.stack.states > 1 do
      game.stack:pop()
      U.wait(2)
    end
  end

  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(40)

  local shotN = 0
  local function shotPath(w, h, mode, moment)
    shotN = shotN + 1
    return DIR .. ("/3076_%02d_%dx%d_%s_%s.png"):format(shotN, w, h, mode, moment)
  end

  for _, sz in ipairs({ { 1280, 720 }, { 1000, 700 } }) do
    local w, h = sz[1], sz[2]
    resize(w, h)
    settle(3)
    for _, mode in ipairs({ "dynamic", "centered" }) do
      local tag = ("%dx%d_%s"):format(w, h, mode)
      game.save.options.uiLayout = mode
      settle(2)
      U.tap(game, "start")
      U.wait(30)
      settle(3)
      local menu = game.stack:top()
      local R = Renderer:frameRects()
      local winR = R.vux + R.vuw
      local boxR = R.uox + R.uvpw
      local tile = 8 * R.Ux
      local _, shared = split()
      local startAnchor
      for _, a in ipairs(shared) do
        if a.anchor == "topright" then startAnchor = a end
      end
      if mode == "dynamic" then
        local right = startAnchor and (place(R, startAnchor) + startAnchor.w * R.Ux)
        check(tag .. "_start_menu_docks_right",
          right ~= nil and math.abs(right - winR) < 1,
          ("right=%s window=%.0f"):format(tostring(right), winR))
      else
        check(tag .. "_start_menu_in_letterbox", #(Renderer.uiAnchors or {}) == 0)
      end
      U.still(game, shotPath(w, h, mode, "start_menu"))

      local saveIdx = findItem(menu, "SAVE")
      check(tag .. "_start_menu_has_save", saveIdx ~= nil)
      if saveIdx then
        menu.index = saveIdx
        U.tap(game, "a")
        for _ = 1, 600 do
          if getmetatable(game.stack:top()) == ChoiceBox then break end
          U.wait(2)
        end
        U.wait(20)
        settle(3)
        check(tag .. "_save_prompt_up", getmetatable(game.stack:top()) == ChoiceBox)
        R = Renderer:frameRects()
        local ox, oy = R.uox, R.uoy
        local nAnchors = #(Renderer.uiAnchors or {})
        if mode == "dynamic" then
          check(tag .. "_save_no_global_hold", Renderer.uiAnchorHold == false)
          check(tag .. "_save_nothing_docked_alone",
            nAnchors == 0 and Renderer.uiShiftRight == true,
            ("anchors=%d shift=%s"):format(nAnchors, tostring(Renderer.uiShiftRight)))
          check(tag .. "_save_canvas_flush_right",
            math.abs(ox - (winR - R.uiw * R.Ux)) < 1,
            ("uox=%.0f want=%.0f"):format(ox, winR - R.uiw * R.Ux))
        else
          check(tag .. "_save_unchanged_no_anchors", nAnchors == 0
            and not Renderer.uiShiftRight and math.abs(ox - (boxR - R.uvpw)) < 1,
            ("uox=%.0f"):format(ox))
        end
        local path = shotPath(w, h, mode, "save_prompt")
        U.still(game, path)
        local img = loadShot(path)
        check(tag .. "_save_shot_loaded", img ~= nil)
        local right = ox + R.uvpw
        local px = darkColumnIn(img, right - tile, right, oy + 2 * tile, oy + 8 * tile)
        local sx = darkColumnIn(img, right - tile, right, oy + 10 * tile + 2, oy + 12 * tile - 2)
        local tx = darkColumnIn(img, right - tile, right, oy + 13 * tile, oy + 17 * tile)
        local lx = darkColumnIn(img, ox, ox + tile, oy + 13 * tile, oy + 17 * tile)
        local yx = darkColumnIn(img, ox, ox + tile, oy + 8 * tile, oy + 11 * tile)
        local by = darkRowIn(img, oy + R.uvph - tile, oy + R.uvph, ox + 2 * tile, ox + 18 * tile)
        local edge = mode == "dynamic" and "window" or "letterbox"
        check(tag .. "_save_shot_panel_border_at_" .. edge .. "_right", px ~= nil
          and (mode ~= "dynamic" or px >= winR - tile), ("x=%s"):format(tostring(px)))
        check(tag .. "_save_shot_start_border_same_column", sx ~= nil and sx == px,
          ("x=%s"):format(tostring(sx)))
        check(tag .. "_save_shot_text_box_right_same_column", tx ~= nil and tx == px,
          ("x=%s"):format(tostring(tx)))
        check(tag .. "_save_shot_yes_no_flush_with_text_box_left", lx ~= nil and yx == lx,
          ("textLeft=%s yesNoLeft=%s"):format(tostring(lx), tostring(yx)))
        check(tag .. "_save_shot_text_box_bottom_border", by ~= nil,
          ("y=%s"):format(tostring(by)))
      end
      backToWorld()
    end
  end
  print(("[3076] done, %d fail(s)"):format(fails))
  love.event.quit(fails == 0 and 0 or 1)
end
