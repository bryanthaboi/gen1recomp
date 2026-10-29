return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Renderer = require("src.render.Renderer")
  local Bag = require("src.inventory.Bag")
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

  local function findItem(menu, label)
    for i, it in ipairs(menu.items or {}) do
      if it.label == label then return i end
    end
  end

  local function isBag(state)
    return state ~= nil and state.closeStartMenu ~= nil and state.isMenu
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
  Bag.add(game.save, "POTION", 3, game.data)
  local mon = require("src.pokemon.Pokemon").new(game.data, "PIDGEY", 5)
  mon.hp = 1
  game.save.party = { mon }

  local shotN = 0
  local function shotPath(w, h, mode, moment)
    shotN = shotN + 1
    return DIR .. ("/F1_%02d_%dx%d_%s_%s.png"):format(shotN, w, h, mode, moment)
  end

  local function layoutChecks(tag, mode, moment)
    local R = Renderer:frameRects()
    local winR = R.vux + R.vuw
    local nAnchors = #(Renderer.uiAnchors or {})
    if mode == "dynamic" then
      check(tag .. "_" .. moment .. "_no_global_hold", Renderer.uiAnchorHold == false)
      check(tag .. "_" .. moment .. "_nothing_docked_alone",
        nAnchors == 0 and Renderer.uiShiftRight == true,
        ("anchors=%d shift=%s"):format(nAnchors, tostring(Renderer.uiShiftRight)))
      check(tag .. "_" .. moment .. "_canvas_flush_right",
        math.abs(R.uox - (winR - R.uiw * R.Ux)) < 1,
        ("uox=%.0f want=%.0f"):format(R.uox, winR - R.uiw * R.Ux))
    else
      local centred = R.vux + math.floor((R.vuw - R.uiw * R.Ux) / 2)
      check(tag .. "_" .. moment .. "_unchanged_centred", nAnchors == 0
        and not Renderer.uiShiftRight and math.abs(R.uox - centred) < 1,
        ("uox=%.0f want=%.0f"):format(R.uox, centred))
    end
    return R, winR
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
      local itemIdx = findItem(menu, "ITEM")
      check(tag .. "_start_menu_has_item", itemIdx ~= nil)
      if itemIdx then
        menu.index = itemIdx
        U.tap(game, "a")
        for _ = 1, 600 do
          if isBag(game.stack:top()) then break end
          U.wait(2)
        end
        U.wait(20)
        settle(3)
        local list = game.stack:top()
        check(tag .. "_bag_up", isBag(list))
        local R, winR = layoutChecks(tag, mode, "bag")
        local ox, oy, tile = R.uox, R.uoy, 8 * R.Ux
        local right = ox + R.uvpw
        local edgeOk = function(x)
          return x ~= nil and (mode ~= "dynamic" or x >= winR - tile)
        end
        local path = shotPath(w, h, mode, "bag_list_over_start_menu")
        U.still(game, path)
        local img = loadShot(path)
        check(tag .. "_bag_shot_loaded", img ~= nil)
        local lx = darkColumnIn(img, right - tile, right, oy + 3 * tile, oy + 12 * tile)
        check(tag .. "_bag_shot_list_border_at_" .. (mode == "dynamic" and "window" or "letterbox") .. "_right",
          edgeOk(lx), ("x=%s"):format(tostring(lx)))
        local startBottom = menu.ty + menu.th - 1
        if startBottom > 13 then
          local sx = darkColumnIn(img, right - tile, right, oy + 13 * tile,
            oy + startBottom * tile)
          check(tag .. "_bag_shot_start_border_same_column", sx ~= nil and sx == lx,
            ("x=%s list=%s"):format(tostring(sx), tostring(lx)))
        end

        U.tap(game, "a")
        U.wait(20)
        settle(3)
        local top = game.stack:top()
        check(tag .. "_use_toss_up", top ~= list and top.items ~= nil
          and #top.items == 2)
        layoutChecks(tag, mode, "use_toss")
        path = shotPath(w, h, mode, "use_toss_box")
        U.still(game, path)
        img = loadShot(path)
        local ux = darkColumnIn(img, right - tile, right, oy + 11 * tile, oy + 14 * tile)
        check(tag .. "_use_toss_shot_border_same_column_as_list",
          ux ~= nil and ux == lx, ("x=%s list=%s"):format(tostring(ux), tostring(lx)))

        U.tap(game, "a")
        for _ = 1, 300 do
          local t = game.stack:top()
          if t and t.isOpaque and t ~= list then break end
          U.wait(2)
        end
        U.wait(20)
        settle(3)
        top = game.stack:top()
        check(tag .. "_party_menu_up", top ~= nil and top.isOpaque == true and top ~= list)
        R = Renderer:frameRects()
        local centred = R.vux + math.floor((R.vuw - R.uiw * R.Ux) / 2)
        check(tag .. "_party_menu_over_bag_centred",
          not Renderer.uiShiftRight and math.abs(R.uox - centred) < 1,
          ("uox=%.0f want=%.0f shift=%s"):format(R.uox, centred, tostring(Renderer.uiShiftRight)))
        U.still(game, shotPath(w, h, mode, "party_menu_from_bag"))
      end
      backToWorld()
    end
  end
  print(("[F1] done, %d fail(s)"):format(fails))
  love.event.quit(fails == 0 and 0 or 1)
end
