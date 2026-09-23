local U = require("tests.drivers.util")
local FaithfulRes = require("src.core.FaithfulRes")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[ratio] " .. (cond and "PASS " or "FAIL ") .. line)
  end
  local mobile = FaithfulRes.fixedDisplay()
  local tag = mobile and "mobile" or "desktop"

  local row
  for _, r in ipairs(OptionsMenu.ROWS) do
    if r.key == "faithfulRes" then row = r end
  end
  ok(row ~= nil, "gen 2 OPTIONS has FAITHFUL RATIO")

  U.wait(45)
  local world = game.world
  if not (row and world and world.map) then
    print("[ratio] FAIL the gen 2 world did not boot")
    love.event.quit(1)
    return
  end

  game.options.faithfulRes = 0
  FaithfulRes.apply(0)
  local _, _, flags = love.window.getMode()
  flags.resizable, flags.fullscreen = true, false
  flags.minwidth, flags.minheight = 1, 1
  if mobile then
    love.window.setMode(540, 1170, flags)
  else
    love.window.setMode(900, 600, flags)
  end
  world:warpToMapId("NEW_BARK_TOWN", 6, 6, "down")
  U.wait(45)
  U.shot(game, SHOT_DIR .. "/" .. tag .. "_0_off.png")

  local menu = OptionsMenu.new(game, { options = game.options })
  game.stack:push(menu)
  U.wait(2)
  menu:focusRow("faithfulRes")
  U.wait(3)
  U.shot(game, SHOT_DIR .. "/" .. tag .. "_1_row_off.png")
  U.tap(game, "right")
  U.wait(10)
  ok(FaithfulRes.normalize(game.options.faithfulRes) == 1,
    "RIGHT on the row steps it to " .. FaithfulRes.label(1))
  U.shot(game, SHOT_DIR .. "/" .. tag .. "_2_row_on.png")
  for _ = 1, 2 do
    U.tap(game, "b")
    U.wait(10)
  end
  ok(game.stack:top() == nil or game.stack:top() ~= menu, "B closes OPTIONS")
  U.wait(20)

  if mobile then
    ok(FaithfulRes.scaleCap() ~= nil, "mobile lock engaged")
    U.shot(game, SHOT_DIR .. "/" .. tag .. "_3_on.png")
  else
    for level = 1, 4 do
      game.options.faithfulRes = level
      FaithfulRes.apply(level)
      U.wait(20)
      local w, h = love.graphics.getPixelDimensions()
      ok(w == 160 * level and h == 144 * level,
        string.format("%dX window is %dx%d", level, w, h))
      U.shot(game, SHOT_DIR .. "/" .. tag .. "_3_" .. level .. "x.png")
    end
    game.options.faithfulRes = 2
    FaithfulRes.apply(2)
    U.wait(10)
  end

  game:persistOptions()
  local text = love.filesystem.read("options.lua") or ""
  ok(text:find("faithfulRes = " .. (mobile and 1 or 2), 1, true) ~= nil,
    "options.lua holds faithfulRes on the shared key")

  game.options.faithfulRes = 0
  FaithfulRes.apply(0)
  U.wait(10)
  ok(not FaithfulRes.locked, "OFF releases the lock")
  U.shot(game, SHOT_DIR .. "/" .. tag .. "_4_off_again.png")
  game:persistOptions()

  print("[ratio] " .. (fails == 0 and "ALL PASS" or (fails .. " FAILED")))
  love.event.quit(fails == 0 and 0 or 1)
end
