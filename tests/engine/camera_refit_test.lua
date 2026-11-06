-- Camera:refit keeps the framing when the world view changes size between
-- follows (a rotation or foldable posture change under a menu or text box,
-- while the overworld is not updating).  Port-only, no pokered cite.
--   luajit tests/engine/camera_refit_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Camera = require("src.render.Camera")

local function centre(cam, w, h) return cam.x + w / 2, cam.y + h / 2 end

do
  local cam = Camera.new()
  cam:follow(400, 300, 200, 180)
  local cx, cy = centre(cam, 200, 180)
  cam:refit(320, 120)
  local nx, ny = centre(cam, 320, 120)
  eq(nx, cx, "refit keeps the horizontal centre")
  eq(ny, cy, "refit keeps the vertical centre")
  local fresh = Camera.new()
  fresh:follow(400, 300, 320, 120)
  check(fresh.x == cam.x and fresh.y == cam.y, "refit matches a fresh follow")
end

do
  local cam = Camera.new()
  cam:follow(400, 300, 200, 180)
  cam.x, cam.y = cam.x + 24, cam.y - 8 -- a pan offset rides on top
  cam:refit(260, 180)
  local ref = Camera.new()
  ref:follow(400, 300, 260, 180)
  eq(cam.x - ref.x, 24, "refit keeps the pan offset (x)")
  eq(cam.y - ref.y, -8, "refit keeps the pan offset (y)")
end

do
  local cam = Camera.new()
  cam.x, cam.y = 5, 7
  cam:refit(300, 200)
  check(cam.x == 5 and cam.y == 7, "no follow yet: refit leaves the camera alone")
  cam:follow(100, 100, 300, 200)
  local x, y = cam.x, cam.y
  cam:refit(300, 200)
  check(cam.x == x and cam.y == y, "same size: no change")
end

T.finish("camera_refit")
