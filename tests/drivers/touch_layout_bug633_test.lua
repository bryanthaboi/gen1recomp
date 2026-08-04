-- Manual check of the per-orientation touch layouts and button resize (#633):
-- one shared positions table meant a drag in landscape moved the portrait pad,
-- and there was no size setting at all.  No pokered counterpart: the on-screen
-- pad is a port-only affordance (Xelu CC0 art, src/core/TouchControls.lua), the
-- Game Boy had physical buttons, so the coords here come from the editor itself.
--   POKEPORT_DRIVER=tests/drivers/touch_layout_bug633_test.lua POKEPORT_IDENTITY=bug633 POKEPORT_TOUCH=1 POKEPORT_VERSION=red love .
-- Leave POKEPORT_SPEED unset: this one is dragged by hand, at real time, and
-- fast-forward desyncs the driver's frames from the frames that draw the editor.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TouchControls = require("src.core.TouchControls")
  local SafeArea = require("src.core.SafeArea")
  local Editor = require("src.ui.TouchControlsEditor")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- The editor lives in launcher mode, before bootGame, and a POKEPORT_DRIVER
  -- run boots straight past the launcher (main.lua: POKEPORT_DRIVER counts as a
  -- scripted run).  So put the window in landscape ourselves, then open the
  -- editor and take over the frame + pointer handlers it normally gets from
  -- main.lua's TouchEditor branch.  We must not set that global: love.update
  -- returns early on it and the driver coroutine would stop being resumed.
  local ww, wh = love.graphics.getDimensions()
  if ww <= wh then
    love.window.setMode(1024, 768, { resizable = true })
    U.wait(4)
    ww, wh = love.graphics.getDimensions()
  end
  check("the window rendered, and it is wider than tall (landscape)",
        ww > 0 and wh > 0 and ww > wh)

  -- Pre-#633 options.lua kept one top-level positions table.  It has to seed
  -- both orientations as separate copies, or the very bug being fixed comes
  -- straight back through the upgrade path.
  local legacy = TouchControls.normalizeConfig({
    positions = { dpad = { x = 0.2, y = 0.8 } },
  })
  local lp, ll = legacy.layouts.portrait, legacy.layouts.landscape
  check("an old single-layout options.lua seeds both orientations",
        lp.positions ~= nil and ll.positions ~= nil
          and lp.positions.dpad.x == 0.2 and ll.positions.dpad.x == 0.2)
  check("and never as one shared table", lp.positions ~= ll.positions)
  check("a file with no size setting reads back as 100%",
        lp.scale == 1 and ll.scale == 1)

  -- The near miss this guards: a scale that grows the art but not the default
  -- centers, which parks A and B half off the right edge at 160%.  Both the
  -- widths and the centers come out of defaultLayout, so compare them.
  local base = TouchControls.defaultLayout(ww, wh, 0, 0, 1)
  local big = TouchControls.defaultLayout(ww, wh, 0, 0, TouchControls.SCALE_MAX)
  local grew, moved, inside = true, true, true
  for _, name in ipairs(TouchControls.CONTROLS) do
    local b, g = base[name], big[name]
    if not (b and g) then grew = false break end
    if g.w <= b.w then grew = false end
    if g.cx == b.cx and g.cy == b.cy then moved = false end
    if g.cx - g.w / 2 < -0.5 or g.cx + g.w / 2 > ww + 0.5
       or g.cy - g.w / 2 < -0.5 or g.cy + g.w / 2 > wh + 0.5 then
      inside = false
    end
  end
  check("at 160% every control is wider than at 100%", grew)
  check("the default centers move with the art, not just the art", moved)
  check("and nothing at 160% hangs off the window", inside)

  -- The editor owns TouchControls while it is open (load re-inits it and turns
  -- preview on), so open it before touching live state.
  local reopened = 0
  local function openEditor()
    Editor.load({ onClose = function()
      -- Done persists into options.lua; reopening straight away reloads from
      -- that file, which is the whole point of the check the reporter runs.
      reopened = reopened + 1
      U.log("Done saved the layouts; the editor reopened from options.lua"
            .. " (reopen #" .. reopened .. ").")
      openEditor()
    end })
  end
  openEditor()

  local prevDraw = love.draw
  local prevPressed, prevReleased, prevMoved =
    love.mousepressed, love.mousereleased, love.mousemoved
  local prevKey = love.keypressed
  love.draw = function()
    Editor.update(love.timer.getDelta())
    Editor.draw()
    -- main.lua's own love.draw owns the driver frame capture; taking the
    -- handler over means taking that with it, or U.shot waits out its spin
    -- and reports a file that was never written
    if game.capturePath then
      local path = game.capturePath
      game.capturePath = nil
      love.graphics.captureScreenshot(function(imagedata)
        local f = io.open(path, "wb")
        if f then
          f:write(imagedata:encode("png"):getString())
          f:close()
        end
      end)
    end
  end
  love.mousepressed = function(x, y, button) Editor.mousepressed(x, y, button or 1) end
  love.mousereleased = function(x, y, button) Editor.mousereleased(x, y, button or 1) end
  love.mousemoved = function(x, y) Editor.mousemoved(x, y) end
  love.keypressed = function(key) Editor.keypressed(key) end
  local function restore()
    love.draw = prevDraw
    love.mousepressed, love.mousereleased = prevPressed, prevReleased
    love.mousemoved, love.keypressed = prevMoved, prevKey
  end

  check("the overlay art loaded (every control has an image)",
        TouchControls:ensureImages() and TouchControls.img ~= nil
          and TouchControls.img.dpad ~= nil and TouchControls.img.a ~= nil
          and TouchControls.img.b ~= nil and TouchControls.img.start ~= nil
          and TouchControls.img.select ~= nil)
  U.wait(4)   -- chrome hit rects exist only after the panel has drawn once

  check("the editor is in the landscape bucket",
        TouchControls.orientation == "landscape")
  local plus, minus = Editor.rects.sizeUp, Editor.rects.sizeDown
  if not check("the size card drew its -/+ buttons", plus ~= nil and minus ~= nil) then
    U.log("Nothing to click: the size card never drew, so the rest is by hand.")
    restore()
    while true do coroutine.yield() end
  end

  -- Drag the d-pad to mid-screen through the editor's own touch path.  No
  -- yields inside the drag: Editor.update follows the live mouse while a drag
  -- is open, and a rendered frame in the middle would snap it to the cursor.
  local ox, oy, sw, sh = SafeArea.rect()
  local L = TouchControls:layout()
  local target = { x = ox + sw * 0.5, y = oy + sh * 0.5 }
  -- normalizeConfig seeds BOTH buckets (a pre-#633 file's top-level positions
  -- become separate copies), so portrait.positions may already be a table
  -- here; the invariant is that the landscape drag does not touch it
  local portraitBefore = {}
  for name, p in pairs(TouchControls.layouts.portrait.positions or {}) do
    portraitBefore[name] = { x = p.x, y = p.y }
  end
  if L.dpad then
    Editor.touchpressed("probe", L.dpad.cx, L.dpad.cy)
    Editor.touchmoved("probe", target.x, target.y)
    Editor.touchreleased("probe", target.x, target.y)
  else
    -- fallback if the d-pad zone is missing (a mod replaced the layout):
    -- write the same normalized center the drag would have written
    TouchControls:setControlCenter("dpad", target.x, target.y)
  end
  U.wait(2)
  local dragged = TouchControls.layouts.landscape.positions
  check("the drag landed in the landscape bucket",
        dragged ~= nil and dragged.dpad ~= nil)
  local portraitAfter = TouchControls.layouts.portrait.positions or {}
  local portraitSame = true
  for name, p in pairs(portraitAfter) do
    local b = portraitBefore[name]
    if not b or b.x ~= p.x or b.y ~= p.y then portraitSame = false end
    portraitBefore[name] = nil
  end
  if next(portraitBefore) ~= nil then portraitSame = false end
  check("the portrait bucket is still untouched by it", portraitSame)

  for _ = 1, 3 do
    Editor.mousepressed(plus.x + plus.w / 2, plus.y + plus.h / 2, 1)
    U.wait(2)
  end
  check("three taps on + read back as 130% landscape",
        math.abs((TouchControls.layouts.landscape.scale or 1) - 1.3) < 0.001)
  check("portrait is still at 100%",
        math.abs((TouchControls.layouts.portrait.scale or 1) - 1) < 0.001)

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  if U.shot(game, SHOT_DIR .. "/bug633_landscape.png") then
    U.log("captured", SHOT_DIR .. "/bug633_landscape.png")
  end

  U.log("The editor on screen is live and landscape: the d-pad has already been")
  U.log("dragged to mid-screen and + tapped three times, so the card should read")
  U.log("\"Button size (Landscape)\" at 130% with the d-pad, A/B and START/SELECT")
  U.log("all grown together and all still fully on screen. Drag the window taller")
  U.log("than wide and the heading should flip to Portrait with the pad back in")
  U.log("the default bottom corners at 100%; move it there and the landscape one")
  U.log("must not budge when you drag back. Done saves and reopens the editor, so")
  U.log("both rotations should come back exactly as you left them. If the portrait")
  U.log("pad shows up already moved or already at 130% the moment you rotate, the")
  U.log("two orientations are still sharing one bucket; if A and B slide off the")
  U.log("right edge as the size climbs, the size grew the art but not the centers.")

  while true do
    coroutine.yield()
  end
end
