-- The touch pad on a foldable: each Duo posture lays the pad out in its own
-- control area and keeps its own saved layout bucket, so editing the
-- clamshell pad never moves the flat or phone layouts.  Port-only
-- affordance, no pokered cite.
--   luajit tests/engine/duo_touch_controls_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Duo = require("src.core.DuoPosture")
local TC = require("src.core.TouchControls")

love.window = love.window or {}
local function setWindow(w, h, sx, sy, sw, sh)
  love.window.getSafeArea = function() return sx or 0, sy or 0, sw or w, sh or h end
  love.graphics.getDimensions = function() return w, h end
  Duo.invalidate()
  TC.layoutW, TC.L = nil, nil
end

TC:init()
TC:applyOptions({ touchControls = { enabled = true } })

-- no hinge: the stock phone layout and the portrait bucket
Duo.forced = nil
setWindow(402, 874)
local L = TC:layout()
eq(TC.bucketKey, "portrait", "no hinge uses the portrait bucket")
check(TC.duo == nil, "no Duo layout without a hinge")

-- clamshell: the whole pad sits in the bottom half, below the fold
Duo.forced = { status = "partial", angle = 100 }
setWindow(669, 951, 0, 0, 669, 917)
L = TC:layout()
eq(TC.bucketKey, "duo_clamshell", "clamshell has its own bucket")
check(TC.duo ~= nil, "clamshell gets a Duo layout")
for _, n in ipairs({ "dpad", "a", "b", "start", "select" }) do
  check(L[n].cy - L[n].w / 2 > 951 / 2, n .. " sits below the fold")
end

-- a drag onto the game half is clamped back into the control area, clear of the fold
TC:setControlCenter("dpad", 120, 100)
local deck = Duo.current().controls[1]
check(L.dpad.cy - L.dpad.w / 2 >= deck.y - 0.5, "dragged d-pad stays inside the control area")

-- editing the clamshell pad leaves flat and phone layouts alone
TC:setControlCenter("dpad", 120, 800)
check(TC.layouts.duo_clamshell.positions.dpad ~= nil, "clamshell edit saved")
check(TC.layouts.portrait.positions == nil, "portrait bucket untouched")
local snap = TC:config()
check(snap.layouts.duo_clamshell ~= nil, "config carries the clamshell bucket")
local round = TC.normalizeConfig(snap)
check(round.layouts.duo_clamshell.positions.dpad ~= nil, "clamshell bucket round-trips")

-- flat open, landscape: two rails, d-pad left of the game, A right of it
Duo.forced = { status = "open", angle = 180 }
setWindow(890, 626, 0, 0, 890, 592)
L = TC:layout()
eq(TC.bucketKey, "duo_flat_landscape", "flat landscape bucket")
check(TC.layouts.duo_flat_landscape.positions == nil, "flat starts from defaults")
local p = Duo.current()
check(L.dpad.cx + L.dpad.w / 2 <= p.game.x, "d-pad left of the game")
check(L.a.cx - L.a.w / 2 >= p.game.x + p.game.w, "A right of the game")

-- cover landscape keeps the stock overlay and the landscape bucket
Duo.forced = { status = "closed", angle = 0 }
setWindow(678, 466, 84, 0, 594, 432)
TC:layout()
eq(TC.bucketKey, "landscape", "cover landscape uses the stock landscape bucket")

-- a posture change re-lays the pad out
Duo.forced = { status = "partial", angle = 100 }
setWindow(669, 951, 0, 0, 669, 917)
TC:layout()
Duo.forced = { status = "open", angle = 180 }
love.graphics.getDimensions = function() return 626, 890 end
love.window.getSafeArea = function() return 0, 0, 626, 856 end
TC.layoutW = nil
TC:layout()
eq(TC.bucketKey, "duo_flat_portrait", "opening flat switches buckets")

-- the key bar strip: without a hinge it sits exactly where upstream puts it
-- (hanging off the menu button); only a Duo posture moves it to the bottom
-- edge of the game picture
local function stockStrip()
  local L0 = TC:layout()
  local zone = L0.hotbar
  local items = TC:hotbarItems()
  local ox, oy, sw, sh = require("src.core.SafeArea").windowRect()
  local h = zone.w * 0.95
  local pad = h * 0.14
  local cw = h * 1.9
  if TC.labelFont then
    for _, ctl in ipairs(items) do
      cw = math.max(cw, TC.labelFont:getWidth(ctl.label) + pad * 3)
    end
  end
  local total = math.min(sw - pad * 2, cw * #items)
  return math.max(ox + pad, math.min(zone.cx - total, ox + sw - pad - total)),
         math.min(zone.cy + zone.w * 0.80, oy + sh - h)
end
for _, win in ipairs({ { 402, 874 }, { 874, 402 }, { 669, 951 } }) do
  Duo.forced = nil
  setWindow(win[1], win[2])
  local cells = TC:hotbarStrip()
  local x0, y0 = stockStrip()
  check(TC.duo == nil, "no hinge at " .. win[1] .. "x" .. win[2])
  eq(cells[1].x, x0, "no hinge: strip x is upstream's at " .. win[1] .. "x" .. win[2])
  eq(cells[1].y, y0, "no hinge: strip y is upstream's at " .. win[1] .. "x" .. win[2])
end
Duo.forced = { status = "partial", angle = 100 }
setWindow(669, 951, 0, 0, 669, 917)
local cells = TC:hotbarStrip()
local g = Duo.current().game
check(cells[1].x >= g.x and cells[#cells].x + cells[#cells].w <= g.x + g.w,
      "clamshell: strip stays within the game picture's width")
check(cells[1].y + cells[1].h <= g.y + g.h, "clamshell: strip sits inside the game picture")

Duo.forced = nil
T.finish("duo_touch_controls")
