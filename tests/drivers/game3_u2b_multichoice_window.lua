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
    print("PASS u2b_multichoice_window")
    love.event.quit(0)
  else
    print("FAIL u2b_multichoice_window failures=" .. failures)
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
  local Choice = require("src.ui.game3.choice")
  local Adapters = require("src.core.game3.scripting.adapters")
  local adapters = Adapters.host(nil, game, nil)

  local cases = {
    { row = { op = "multichoice", 20, 8, 10, 0 }, ey = 9, right = 29, shot = "u2b_01_multichoice_20_8_window.png" },
    { row = { op = "multichoice", 0, 0, 5, 0 }, ex = 1, ey = 1, shot = "u2b_02_multichoice_0_0_window.png" },
  }

  local origStdFrame = Chrome.stdFrame
  for _, c in ipairs(cases) do
    local frame
    Chrome.stdFrame = function(tx, ty, tw, th)
      if Choice.active then frame = { tx, ty, tw, th } end
      return origStdFrame(tx, ty, tw, th)
    end
    adapters.multichoice(c.row, function() end)
    U.wait(20)
    local label = ("multichoice %d,%d"):format(c.row[1], c.row[2])
    if result(Choice.active and frame ~= nil, label .. " window drawn") then
      local ok, desc
      if c.right then
        ok = frame[1] + frame[3] == c.right and frame[2] == c.ey
        desc = ("%s clamped: content right edge %d top %d, got x=%s w=%s y=%s"):format(label,
          c.right, c.ey, tostring(frame[1]), tostring(frame[3]), tostring(frame[2]))
      else
        ok = frame[1] == c.ex and frame[2] == c.ey
        desc = ("%s content at tiles (%d,%d), got (%s,%s)"):format(label, c.ex, c.ey,
          tostring(frame[1]), tostring(frame[2]))
      end
      if result(ok, desc) then
        U.shot(game, DIR .. "/" .. c.shot)
        U.wait(5)
      end
    end
    Chrome.stdFrame = origStdFrame
    Choice.active = false
    Choice.options = nil
    Choice.done = nil
    U.wait(5)
  end

  finish()
end
