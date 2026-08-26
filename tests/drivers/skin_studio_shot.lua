-- Driver: shoots the desktop Skin Studio (#1386) across its canvas presets
-- and in Test mode.  The studio is a top-level love.draw branch in main.lua,
-- so this stands in for that branch and captures the frames itself.
--   SHOT_DIR=/tmp/studio POKEPORT_DRIVER=tests/drivers/skin_studio_shot.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Studio = require("src.ui.SkinStudio")
  local TouchControls = require("src.core.TouchControls")

  local dir = os.getenv("SHOT_DIR") or "/tmp/studio"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  local shotW = tonumber(os.getenv("STUDIO_SHOT_W")) or 1440
  local shotH = tonumber(os.getenv("STUDIO_SHOT_H")) or 900
  love.window.setMode(shotW, shotH, { resizable = true, highdpi = true })
  U.wait(2)

  local pending = nil
  love.draw = function()
    Studio.draw()
    if pending then
      local path = pending
      pending = nil
      love.graphics.captureScreenshot(function(imagedata)
        local f = io.open(path, "wb")
        if f then f:write(imagedata:encode("png"):getString()) f:close() end
      end)
    end
  end

  local function shot(name)
    pending = dir .. "/" .. name
    for _ = 1, 90 do
      if not pending then break end
      coroutine.yield()
    end
    U.wait(3)
    local f = io.open(dir .. "/" .. name, "rb")
    if f then f:close() U.log("shot", name) else U.log("FAIL shot", name) end
  end

  Studio.load({ skinId = "gb_anim", onClose = function() end })
  U.wait(5)
  U.log("skin:", Studio.skin and Studio.skin.id, "pages:", #(Studio.skin.pages or {}))
  U.log("controls:", #Studio.page().controls, "images:", #(Studio.images or {}))
  shot("studio_open.png")
  Studio.enterEditor()
  U.wait(2)
  shot("studio_editor.png")

  Studio.openPageMenu()
  U.wait(2)
  shot("studio_pages.png")
  Studio.closeModal()

  Studio.selected = 9
  U.wait(3)
  local ctl = Studio.selectedControl()
  U.log("selected:", ctl and ctl.spec, "x", ctl and ctl.x, "y", ctl and ctl.y)
  shot("studio_selected.png")

  Studio.zoomOut()
  U.wait(2)
  shot("studio_zoom_out.png")
  Studio.zoomFit()

  Studio.openScreenMenu()
  U.wait(2)
  shot("studio_screen.png")
  Studio.closeModal()
  Studio.detectDeviceCanvas()
  U.wait(2)
  shot("studio_this_screen.png")

  -- drag the selected control and confirm the model moved
  local r = Studio.lastCanvas
  if r and ctl then
    local before = ctl.x
    Studio.beginCanvasDrag(r.x + ctl.x * r.w, r.y + ctl.y * r.h, r)
    Studio.updateDrag(r.x + ctl.x * r.w - 60, r.y + ctl.y * r.h, r)
    Studio.drag = nil
    U.log("drag moved x:", before, "->", ctl.x)
  end
  U.wait(3)
  shot("studio_dragged.png")

  -- numeric entry: type an exact pixel X
  if ctl then
    Studio.commitField("numX", "100")
    U.log("after numX=100 px, x fraction:", ctl.x, "rangeX:", ctl.rangeX)
  end

  Studio.testing = true
  TouchControls:setPreview(false)
  U.wait(3)
  if r then
    local page = Studio.page()
    local TouchSkin = require("src.core.TouchSkin")
    TouchSkin.setSurface(r.x, r.y, r.w, r.h)
    local cx, cy = TouchSkin.controlGeometry(page, page.controls[13], r.w, r.h, r.x, r.y)
    Studio.mousepressed(cx, cy, 1)
    TouchSkin.setSurface(nil)
    local held = {}
    for btn in pairs(TouchControls.held or {}) do held[#held + 1] = btn end
    U.log("test press held:", table.concat(held, ","))
  end
  U.wait(3)
  shot("studio_test.png")
  Studio.mousereleased(0, 0, 1)
  Studio.testing = false
  TouchControls:setPreview(true)

  -- Super Game Boy border preset: viewport locks to the 160x144 window
  for i, c in ipairs(Studio.CANVASES) do
    if c.id == "sgb_border" then Studio.setCanvas(i) end
  end
  U.wait(3)
  local vp = Studio.page().viewport
  U.log("sgb viewport:", vp.x, vp.y, vp.w, vp.h)
  shot("studio_sgb.png")

  for i, c in ipairs(Studio.CANVASES) do
    if c.id == "ultrawide" then Studio.setCanvas(i) end
  end
  U.wait(3)
  shot("studio_ultrawide.png")

  U.log("done")
  love.event.quit()
  while true do coroutine.yield() end
end
