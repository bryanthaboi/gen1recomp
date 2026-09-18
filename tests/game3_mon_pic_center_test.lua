#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local frames = {}
local draws = {}

love = love or {}
love.graphics = love.graphics or {}
love.graphics.setColor = function() end
love.graphics.rectangle = function() end
love.graphics.draw = function(img, x, y)
  draws[#draws + 1] = { img = img, x = x, y = y }
end

package.loaded["src.ui.game3.chrome"] = {
  stdFrame = function(tx, ty, tw, th)
    frames[#frames + 1] = { tx, ty, tw, th }
  end,
}
package.loaded["src.ui.game3.frlg_font"] = { COLOR = {} }

local MonPic = require("src.ui.game3.mon_pic")

local function run(x, y, ex, ey, epx, epy)
  frames, draws = {}, {}
  MonPic.active = true
  MonPic.left, MonPic.top = x, y
  MonPic._img = {}
  MonPic._w, MonPic._h = 64, 64
  MonPic.draw()
  local f = frames[1]
  check(f ~= nil, ("showmonpic %d,%d draws a frame"):format(x, y))
  if not f then return end
  check(f[1] == ex and f[2] == ey and f[3] == 8 and f[4] == 8,
    ("frame content at (%d,%d) 8x8, got (%s,%s)"):format(ex, ey, tostring(f[1]), tostring(f[2])))
  local d = draws[1]
  check(d ~= nil and d.x == epx and d.y == epy,
    ("pic top-left at (%d,%d), got (%s,%s)"):format(epx, epy, tostring(d and d.x), tostring(d and d.y)))
  if d then
    local fcx, fcy = (f[1] + 4) * 8, (f[2] + 4) * 8
    check(d.x + 32 == fcx and d.y + 32 == fcy,
      ("pic center (%d,%d) matches frame center (%d,%d)"):format(d.x + 32, d.y + 32, fcx, fcy))
  end
end

print("[test] showmonpic window centered on its pic")
run(10, 3, 11, 4, 88, 32)
run(0, 0, 1, 1, 8, 8)

if failed > 0 then
  print(string.format("[FAIL] %d test(s) failed", failed))
  os.exit(1)
else
  print("[test] all passed")
end
