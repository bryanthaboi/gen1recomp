-- Per-orientation touch layouts and the button size setting (#633).  The
-- overlay used to keep exactly one positions table, so laying the pad out
-- in landscape rewrote the portrait layout; now each orientation owns a
-- {positions, scale} bucket picked from the safe rect's aspect, and the
-- editor's -/+ scales every control in the active one.  No pokered cite:
-- the on-screen pad is a port-only affordance (Xelu CC0 art).
--   luajit tests/engine/touch_orientation_bug633.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local TC = require("src.core.TouchControls")

-- per-orientation buckets round-trip independently, scale is clamped
local cfg = TC.normalizeConfig({
  layouts = {
    portrait = { positions = { dpad = { x = 0.2, y = 0.9 } }, scale = 1.25 },
    landscape = { positions = { dpad = { x = 0.1, y = 0.5 } }, scale = 99 },
  },
})
eq(cfg.layouts.portrait.positions.dpad.x, 0.2, "portrait bucket kept")
eq(cfg.layouts.landscape.positions.dpad.x, 0.1, "landscape bucket kept")
eq(cfg.layouts.portrait.scale, 1.25, "portrait scale kept")
eq(cfg.layouts.landscape.scale, TC.SCALE_MAX, "out-of-range scale clamps")

-- steer the safe rect by hand: tall = portrait, wide = landscape
love.window = love.window or {}
local oldSafe = love.window.getSafeArea
local function setRect(w, h)
  love.window.getSafeArea = function() return 0, 0, w, h end
  -- getDimensions bounds the safe rect (SafeArea clamps to the drawable
  -- window), so keep both in step
  love.graphics.getDimensions = function() return w, h end
  TC.layoutW, TC.layoutH, TC.layoutOx, TC.layoutOy, TC.L = nil, nil, nil, nil, nil
end

TC:init()
setRect(380, 720)
TC:applyOptions({
  touchControls = {
    enabled = true,
    positions = { dpad = { x = 0.25, y = 0.75 } },
  },
})

-- the size setting scales every control in the active (portrait) bucket
TC:setScale(1.5)
setRect(380, 720)
local big = TC:layout()
eq(TC.orientation, "portrait", "tall safe rect is portrait")
check(big.a.w > TC.defaultLayout(380, 720).a.w, "scale grows buttons")

-- rotating swaps buckets, and a landscape drag leaves portrait alone
TC:setScale(1)
setRect(800, 400)
TC:layout()
eq(TC.orientation, "landscape", "wide safe rect is landscape")
TC:setControlCenter("dpad", 700, 300)
eq(TC.layouts.portrait.positions.dpad.x, 0.25,
   "landscape drag leaves the portrait layout alone (#633)")

-- Reset clears only the orientation on screen
TC:clearPositions()
check(TC.layouts.landscape.positions == nil,
      "Reset wipes the landscape overrides")
eq(TC.layouts.portrait.positions.dpad.x, 0.25,
   "and the portrait layout survives it (#633)")

-- config() snapshots both buckets for the editor's save path
local snap = TC:config()
eq(snap.layouts.portrait.positions.dpad.x, 0.25, "config carries portrait")
check(snap.layouts.landscape.positions == nil, "config carries landscape")

if oldSafe then love.window.getSafeArea = oldSafe
else love.window.getSafeArea = nil end

T.finish("touch_orientation_bug633")
