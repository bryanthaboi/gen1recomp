-- Step 1 validation only: proves pixels drawn in Lua reach a real second
-- Android display (love.system.hasSecondaryDisplay / .presentUIFrame,
-- backed by GameActivity's Presentation on the AYN Thor's bottom panel --
-- see mobile/android/love/src/main/java/org/love2d/android/GameActivity.java
-- and src/common/android.cpp).
--
-- Deliberately does NOT touch BattleState or anything real yet. Once this
-- shows a moving test pattern on the second screen, the next step is
-- redirecting the actual battle action-menu / move-select draw calls here
-- instead of this placeholder (see BattleState.lua's "menu"/"moveSelect"
-- phase branches).
--
-- Hooks render.letterbox purely because it's an existing, confirmed
-- per-frame hook point inside Renderer:endFrame -- not because this content
-- has anything to do with letterboxing. A dedicated render.ui_canvas_ready
-- hook (proposed separately) would be the real long-term hook point.

local PixelCanvas = require("src.render.PixelCanvas")

local W, H = 96, 48
local PUSH_EVERY_N_FRAMES = 4 -- throttled: a canvas readback stalls the GPU,
                              -- and the second screen doesn't need 60fps

return function(mod)
  -- LÖVE runs highdpi on Android (conf.lua), so a plain newCanvas(W, H)
  -- allocates its backing texture at the device's DPI-scaled size, not
  -- W x H -- newImageData()'s buffer would then silently mismatch the
  -- w*h*4 presentUIFrame is told to expect (android.cpp's size check) and
  -- every frame gets dropped, leaving the panel showing nothing but its
  -- default white background. PixelCanvas forces dpiscale=1 so the canvas
  -- is really W x H texels.
  local canvas = PixelCanvas.new(W, H)
  local frame = 0
  local haveSecondaryDisplay = false

  mod.hooks:wrap("render.letterbox", function(next, info)
    -- preserve whatever the base engine / other mods draw for the void art
    next(info)

    frame = frame + 1
    if frame % PUSH_EVERY_N_FRAMES ~= 0 then return end

    -- cheap to re-check each throttled tick; a device could plug/unplug a
    -- presentation display (dock, wireless display) mid-session
    haveSecondaryDisplay = love.system.hasSecondaryDisplay()
    if not haveSecondaryDisplay then return end

    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.1, 0.1, 0.15, 1)

    -- moving color bar so it's obvious on the actual device that frames are
    -- actually updating, not just a single static push
    local t = frame / 60
    local barX = (t * 20) % W
    love.graphics.setColor(0.9, 0.2, 0.3, 1)
    love.graphics.rectangle("fill", barX, 0, 8, H)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("2nd screen pipe OK", 4, 4)
    love.graphics.print("frame " .. frame, 4, H - 16)

    love.graphics.setCanvas()
    love.graphics.pop()

    local imageData = canvas:newImageData()
    local ok = love.system.presentUIFrame(imageData:getString(), W, H)
    if not ok then
      mod.log:warn("presentUIFrame rejected the frame (size mismatch or display gone)")
    end
  end)

  mod.events:on("game.ready", function()
    if love.system.hasSecondaryDisplay() then
      mod.log:info("Secondary display detected -- pushing test pattern.")
    else
      mod.log:info("No secondary display detected (expected on desktop/single-screen).")
    end
  end)
end
