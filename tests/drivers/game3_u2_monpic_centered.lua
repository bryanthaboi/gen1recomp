local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

local failures = 0
local function result(ok, label)
  if ok then
    print("PASS " .. label)
  else
    failures = failures + 1
    print("FAIL " .. label)
  end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS u2_monpic_centered")
    love.event.quit(0)
  else
    print("FAIL u2_monpic_centered failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(120)
  local Map = require("src.core.game3.map")
  Map.load(nil, game, "FR_OAKS_LAB", { x = 8, y = 5, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 8, 5, "up"
  U.wait(90)

  local Chrome = require("src.ui.game3.chrome")
  local MonPic = require("src.ui.game3.mon_pic")
  local frame
  local origStdFrame = Chrome.stdFrame
  Chrome.stdFrame = function(tx, ty, tw, th)
    if MonPic.active and tw == 8 and th == 8 then
      frame = { tx, ty, tw, th }
    end
    return origStdFrame(tx, ty, tw, th)
  end

  MonPic.show(1, 10, 3)
  U.wait(20)
  Chrome.stdFrame = origStdFrame

  result(MonPic.active and MonPic._img ~= nil, "showmonpic 10,3 opened with a front pic")
  if not result(frame ~= nil, "pic window frame drawn") then
    return finish()
  end
  result(frame[1] == 11 and frame[2] == 4,
    ("window content at tiles (11,4), got (%s,%s)"):format(tostring(frame[1]), tostring(frame[2])))
  local picCx, picCy = MonPic.left * 8 + 40, MonPic.top * 8 + 40
  local frameCx, frameCy = (frame[1] + 4) * 8, (frame[2] + 4) * 8
  if result(picCx == frameCx and picCy == frameCy,
    ("pic center (%d,%d) == window center (%d,%d)"):format(picCx, picCy, frameCx, frameCy)) then
    U.shot(game, DIR .. "/u2_01_lab_starter_pic_centered.png")
  end

  MonPic.hide()
  finish()
end
