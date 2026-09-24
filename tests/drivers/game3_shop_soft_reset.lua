local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_shop_soft_reset"
local MODE = os.getenv("S1_MODE") or "new_game"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  if failures == 0 then
    print("PASS shop_soft_reset " .. MODE)
    love.event.quit(0)
  else
    print("FAIL shop_soft_reset " .. MODE .. " failures=" .. failures)
    love.event.quit(1)
  end
end

local function run(game)
  local function waitBoot()
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then return true end
      U.wait(1)
    end
    return false
  end
  local function enterField()
    if MODE == "continue" then
      game:_handleBootAction({ action = "continue" })
      for _ = 1, 3000 do
        if game.phase == "field" then break end
        if game.phase == "quest_log" and game.questPlayback then game.questPlayback.done = true end
        U.wait(1)
      end
    else
      game:_handleBootAction({ action = "new_game", name = "RED" })
    end
    U.wait(240)
  end

  waitBoot()
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  if MODE == "continue" then pcall(function() game:saveGame() end) end

  local Map = require("src.core.game3.map")
  local MapCatalog = require("src.import.gba.map_catalog")
  local Player = require("src.core.game3.player")
  local ShopMenu = require("src.ui.game3.shop_menu")
  local Fade = require("src.ui.game3.fade")
  local Hud = require("src.ui.game3.hud")
  local MART = MapCatalog.resolve("VermilionCity_Mart")

  local function placeAtClerk()
    Map.load(nil, game, MART, { x = 2, y = 4, facing = "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = 2, 4, "up"
    end
    Player.cellX, Player.cellY = 2, 4
    Player.px, Player.py = 2 * 16, 4 * 16
    Player.targetX, Player.targetY = 2, 4
    Player.facing = "up"
    U.wait(90)
  end
  local function toShopRoot()
    placeAtClerk()
    for _ = 1, 360 do
      if ShopMenu.isOpen() and ShopMenu.mode == "root" and not ShopMenu._fading then return true end
      U.tap(game, "a")
      U.wait(6)
    end
    return false
  end

  for _, case in ipairs({ "buy_fade", "root" }) do
    if not result(toShopRoot(), case .. ": clerk opened the shop root") then return end
    if case == "buy_fade" then
      ShopMenu.cursor = 1
      U.tap(game, "a")
      U.wait(4)
      result(ShopMenu._fading == true and Fade.isActive(), case .. ": BUY started the shop fade")
      U.still(game, DIR .. "/shop_reset_" .. MODE .. "_buy_midfade.png")
    end
    game.softResetRequested = true
    U.wait(2)
    result(waitBoot(), case .. ": soft reset reached the title")
    enterField()
    result(not ShopMenu.isOpen() and not ShopMenu._fading and not Hud.isMenuOpen(),
      case .. ": shop closed in the new " .. MODE .. " session (open=" .. tostring(ShopMenu.open)
      .. " _fading=" .. tostring(ShopMenu._fading) .. ")")
    local sx, sy = Player.cellX, Player.cellY
    local moved = false
    for _, d in ipairs({ "left", "down", "right", "up" }) do
      U.hold(game, d, 24)
      U.wait(24)
      if Player.cellX ~= sx or Player.cellY ~= sy then moved = true break end
    end
    result(moved, case .. ": player can walk in the new session menuOpen=" .. tostring(Hud.isMenuOpen()))
    U.shot(game, DIR .. "/shop_reset_" .. MODE .. "_" .. case .. "_after.png")
    local opened = toShopRoot()
    result(opened, case .. ": second visit reached the shop root")
    for _ = 1, 10 do
      U.tap(game, "b")
      U.wait(10)
      if not ShopMenu.isOpen() then break end
    end
    result(not ShopMenu.isOpen(), case .. ": B closes the shop on the second visit")
    for _ = 1, 30 do
      if not Hud.busy() then break end
      U.tap(game, "b")
      U.wait(10)
    end
  end
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then result(false, "driver error: " .. tostring(err)) end
  finish()
end
