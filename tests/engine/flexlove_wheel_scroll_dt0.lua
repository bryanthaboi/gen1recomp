-- Wheel scrolling must survive the launcher's immediate-mode frame order:
-- FlexLove.update(dt) runs in love.update, but beginFrame (in draw) resets
-- the accumulated dt to 0 BEFORE endFrame updates the elements, so
-- ScrollManager:update always receives dt = 0 there. The smooth-scroll
-- interpolation must still advance (it once used a fixed per-frame
-- fraction; the dt-aware blend has to treat dt <= 0 as one nominal 60 Hz
-- step, or every launcher list stops responding to the wheel entirely).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
love.window.getMode = function() return 1024, 768, { fullscreen = false } end
love.window.getDesktopDimensions = function() return 1920, 1080 end
love.mouse = love.mouse or {}
love.mouse.getPosition = function() return 100, 100 end
love.mouse.isDown = love.mouse.isDown or function() return false end
package.loaded["libs.flexlove.modules.UTF8"] = {
  char = string.char, charpattern = ".", codepoint = string.byte,
  len = string.len, offset = function(_, n) return n end,
  codes = function(s)
    local i = 0
    return function() i = i + 1; if i <= #s then return i, s:byte(i) end end
  end,
}

local T = require("tests.modkit")
local FlexLove = require("libs.flexlove.FlexLove")
FlexLove.init({
  immediateMode = true,
  performanceMonitoring = false,
  keyboardNavigation = false,
})

-- One launcher-shaped frame: update BEFORE beginFrame, exactly like
-- LauncherView.update / draw, so endFrame sees _accumulatedDt == 0.
local function frame(wheelAfterBuild)
  FlexLove.update(1 / 60)
  FlexLove.beginFrame()
  local scroller = FlexLove.new({
    id = "scroller", x = 0, y = 0, width = 400, height = 300,
    overflowY = "scroll", hideScrollbars = true,
    smoothScrollEnabled = true, scrollSpeed = 60,
    positioning = "flex", flexDirection = "vertical",
  })
  for i = 1, 30 do
    FlexLove.new({ parent = scroller, id = "row" .. i, width = 380, height = 40 })
  end
  FlexLove.endFrame()
  if wheelAfterBuild then FlexLove.wheelmoved(0, -1) end
  local sm = scroller._scrollManager
  return sm and sm._scrollY or nil, sm and sm._targetScrollY or nil
end

for _ = 1, 3 do frame(false) end
local y0, t0 = frame(true)
T.eq(t0, 60, "one wheel notch targets one scrollSpeed step")
T.eq(y0, 0, "the notch lands on the frame after input, not the same one")

local y = y0
for _ = 1, 5 do y = frame(false) end
T.check(y ~= nil and y > 30, "smooth scroll advances past halfway within 5 dt=0 frames")
for _ = 1, 60 do y = frame(false) end
T.check(y ~= nil and math.abs(y - 60) < 1, "and converges on the target")

T.finish("flexlove wheel scroll at dt=0")
