-- Driver: the studio's side of the alt-tab crash.  Leaving the window mid-drag
-- must drop the drag and the queued click and still draw; main.lua's routing of
-- love.focus / love.visible / pad events while the studio owns the window is
-- pinned by tests/engine/skin_studio_image_import.lua (a driver run boots a
-- game, so main.lua's Studio branch is not live here).
--   POKEPORT_DRIVER=tests/drivers/skin_studio_focus_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Studio = require("src.ui.SkinStudio")
  local TouchControls = require("src.core.TouchControls")

  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(2)

  Studio.load({ version = "red", skinId = "gb_anim", onClose = function() end })
  U.wait(2)
  U.log("skin:", Studio.skin and Studio.skin.id)

  Studio.drag = { kind = "control-move", mx = 1, my = 1, bx = 0, by = 0,
                  bw = 10, bh = 10 }
  Studio.clicked = true
  local okFocus, errFocus = pcall(Studio.focus, false)
  U.log("focus lost:", okFocus, errFocus or "")
  U.log("drag:", tostring(Studio.drag), "click:", tostring(Studio.clicked))
  local droppedDrag = Studio.drag == nil and Studio.clicked == false

  -- a held test press must not survive the trip out of the window either
  Studio.testing = true
  TouchControls:setPreview(false)
  TouchControls.held = TouchControls.held or {}
  TouchControls.held.start = true
  pcall(Studio.focus, false)
  local held = next(TouchControls.held or {})
  U.log("held after focus loss:", tostring(held))

  local okVisible = pcall(Studio.visible, false)
  U.log("minimize:", okVisible)

  local okDraw, errDraw = pcall(Studio.draw)
  U.log("draw after alt-tab:", okDraw, errDraw or "")

  Studio.unload()

  if droppedDrag and held == nil and okVisible and okDraw then
    U.log("RESULT pass")
  else
    U.log("RESULT FAIL")
  end
  love.event.quit()
  while true do coroutine.yield() end
end
