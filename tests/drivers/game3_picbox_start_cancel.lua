local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_picbox_start_cancel"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_picbox_start_cancel")
    love.event.quit(0)
  else
    print("FAIL game3_picbox_start_cancel failures=" .. failures)
    love.event.quit(1)
  end
end

-- data/maps/PalletTown/scripts.inc:428 SignLadyShowSign / :444 SignLadyStartShowSign
local function findSignLadyScript(scripts)
  local show
  for key, rows in pairs(scripts) do
    for i, row in ipairs(rows) do
      local nxt = rows[i + 1]
      if row.op == "special" and row.id == 368 and nxt and nxt.op == "special" and nxt.id == 369 then
        show = key
      end
    end
  end
  if not show then return nil end
  for key, rows in pairs(scripts) do
    local first = rows[1]
    if first and first.op == "applymovement" then
      for _, row in ipairs(rows) do
        if row.op == "call" and row.target == show then return key end
      end
    end
  end
  return nil
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local StartMenu = require("src.ui.game3.start_menu")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")
  local MapCatalog = require("src.import.gba.map_catalog")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  local town = MapCatalog.pretToEngine("PalletTown")
  Map.load(nil, game, town, { x = 9, y = 8, facing = "down" })
  game.session.x, game.session.y, game.session.facing = 9, 8, "down"
  U.wait(60)

  local key = findSignLadyScript(Space.vm.scripts)
  if not result(key ~= nil, "sign lady show-sign script found in the cache") then return finish() end
  Space.startScript(key, 1)

  local shown = false
  for _ = 1, 600 do
    local p = Message.currentPage and Message.currentPage() or ""
    if Message.isOpen() and p:find("Press START to open the MENU", 1, true) then shown = true break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(2)
  end
  if not result(shown, "the copied sign is up") then return finish() end
  Message.skipReveal()
  U.wait(20)
  result(U.shot(game, DIR .. "/spec_picbox_sign_before_start.png"), "screenshot spec_picbox_sign_before_start")

  U.tap(game, "start")
  local opened = false
  for _ = 1, 60 do
    if StartMenu.isOpen() then opened = true break end
    U.wait(1)
  end
  result(not Message.isOpen(), "START closed the sign")
  result(not Space.vm:isRunning(), "START ended the sign script")
  result(opened, "START opened the menu")
  if opened then
    U.wait(10)
    result(U.shot(game, DIR .. "/spec_picbox_start_menu_open.png"), "screenshot spec_picbox_start_menu_open")
  end
  return finish()
end
