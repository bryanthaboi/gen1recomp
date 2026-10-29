return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Renderer = require("src.render.Renderer")
  local ShaderFX = require("src.render.ShaderFX")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local fails = 0
  local function check(name, ok, detail)
    print(("%s %s%s"):format(ok and "PASS" or "FAIL", name, detail and ("  " .. detail) or ""))
    if not ok then fails = fails + 1 end
  end
  local function finish()
    ShaderFX.deactivate("main")
    print(("[F5] done, %d fail(s)"):format(fails))
    love.event.quit(fails == 0 and 0 or 1)
  end

  local draws = 0
  local baseEnd = Renderer.endFrame
  local worldX, worldY, fxX, fxY
  local baseFx = ShaderFX.render
  ShaderFX.render = function(canvas, rect, source, dpiX, dpiY, opts)
    if not (opts and opts.layer) then
      fxX, fxY = opts and opts.originX, opts and opts.originY
    end
    return baseFx(canvas, rect, source, dpiX, dpiY, opts)
  end
  Renderer.endFrame = function(self, ...)
    draws = draws + 1
    if self.worldActive and self.worldCanvas then
      local R = self:frameRects()
      local vw, vh = self.worldCanvas:getWidth(), self.worldCanvas:getHeight()
      worldX = R.vx + math.floor((R.pw - vw * R.Sp) / 2)
      worldY = R.vy + math.floor((R.ph - vh * R.Sp) / 2) - R.lift
    end
    return baseEnd(self, ...)
  end
  local function settle(n)
    local target = draws + (n or 3)
    for _ = 1, 20000 do
      if draws >= target then return end
      coroutine.yield()
    end
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

  local function sameRegion(a, b, x0, y0, x1, y1)
    if not (a and b) then return nil end
    local diff = 0
    for y = y0, y1 - 1 do
      for x = x0, x1 - 1 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then diff = diff + 1 end
      end
    end
    return diff
  end

  local src = love.filesystem.getSource()
  local ok, err = ShaderFX.activate("main", {
    name = "lcd3x.slangp", converted = true,
    fullPath = src .. "/tests/data/shaderfx/gl/lcd3x.slangp",
  })
  check("lcd3x_grid_preset_active", ok == true, tostring(err))
  if not ok then return finish() end

  love.window.setMode(1920, 1080, { resizable = true, borderless = true })
  if love.window.setPosition then love.window.setPosition(-30000, -30000) end
  U.wait(20)
  local pw, ph = love.graphics.getPixelDimensions()
  check("window_1920x1080_dpi1", pw == 1920 and ph == 1080, ("%dx%d"):format(pw, ph))

  game.save.options.uiLayout = "dynamic"
  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(40)
  settle(3)

  local R = Renderer:frameRects()
  local Up = R.Up
  check("world_seen", worldX ~= nil, ("world=%s,%s Up=%s"):format(tostring(worldX), tostring(worldY), tostring(Up)))
  if not worldX then return finish() end
  local px, py = worldX % Up, worldY % Up

  U.tap(game, "start")
  U.wait(30)
  settle(3)
  local menu = game.stack:top()
  R = Renderer:frameRects()
  local start
  for _, a in ipairs(Renderer.uiAnchors or {}) do
    if a.anchor == "topright" then start = a end
  end
  check("start_menu_docked", start ~= nil)
  if start then
    local place = Renderer.placeUIAnchor or function(r, s)
      return r.vux + r.vuw - (r.uiw - s.x) * r.Ux, r.vuy + s.y * r.Uy, s.w * r.Ux
    end
    local dx, dy, dw = place(R, start)
    check("start_box_on_world_column_phase", dx % Up == px, ("x=%d phase %d want %d"):format(dx, dx % Up, px))
    check("start_box_on_world_row_phase", dy % Up == py, ("y=%d phase %d want %d"):format(dy, dy % Up, py))
    check("start_box_within_a_gb_pixel_of_corner", dx + dw > pw - Up and dx + dw <= pw and dy < Up,
      ("right=%d top=%d"):format(dx + dw, dy))
  end
  check("start_grid_origin_on_world_phase", fxX and fxX % Up == px and fxY % Up == py,
    ("origin=%s,%s"):format(tostring(fxX), tostring(fxY)))
  local startShot = DIR .. "/F5_01_1920x1080_lcd3x_docked_start_menu.png"
  U.still(game, startShot)

  local saveIdx
  for i, it in ipairs(menu.items or {}) do
    if it.label == "SAVE" then saveIdx = i end
  end
  check("start_menu_has_save", saveIdx ~= nil)
  if not saveIdx then return finish() end
  menu.index = saveIdx
  U.tap(game, "a")
  for _ = 1, 600 do
    if getmetatable(game.stack:top()) == ChoiceBox then break end
    U.wait(2)
  end
  U.wait(20)
  settle(3)
  R = Renderer:frameRects()
  check("save_prompt_shifted", Renderer.uiShiftRight == true and getmetatable(game.stack:top()) == ChoiceBox)
  check("save_canvas_on_world_column_phase", R.uox % Up == px, ("uox=%d phase %d want %d"):format(R.uox, R.uox % Up, px))
  check("save_canvas_within_a_gb_pixel_of_edge", R.uox + R.uvpw > pw - Up and R.uox + R.uvpw <= pw,
    ("right=%d"):format(R.uox + R.uvpw))
  check("save_grid_origin_on_world_phase", fxX and fxX % Up == px and fxY % Up == py,
    ("origin=%s,%s"):format(tostring(fxX), tostring(fxY)))
  local saveShot = DIR .. "/F5_02_1920x1080_lcd3x_save_prompt.png"
  U.still(game, saveShot)

  local a, b = loadShot(startShot), loadShot(saveShot)
  check("shots_loaded", a ~= nil and b ~= nil)
  local diff = sameRegion(a, b, 0, 0, 380, 300)
  check("world_does_not_move_when_save_opens", diff == 0, ("changed px in 380x300 world corner=%s"):format(tostring(diff)))

  for _ = 1, 10 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "b")
    U.wait(20)
  end
  finish()
end
