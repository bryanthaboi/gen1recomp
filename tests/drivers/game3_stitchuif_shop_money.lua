local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuif_shop_money"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchuif_shop_money")
    love.event.quit(0)
  else
    print("FAIL stitchuif_shop_money failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local MapCatalog = require("src.import.gba.map_catalog")
  local Player = require("src.core.game3.player")
  local Choice = require("src.ui.game3.choice")
  local ShopMenu = require("src.ui.game3.shop_menu")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local Strings = require("src.core.Strings")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local MART = MapCatalog.resolve("VermilionCity_Mart")
  if not result(type(MART) == "string", "the cache knows VermilionCity_Mart") then
    return finish()
  end

  local draws = {}
  local realDraw = FrlgFont.draw
  FrlgFont.draw = function(text, x, y, opts)
    local drawn, endX, endY = realDraw(text, x, y, opts)
    draws[#draws + 1] = {
      text = tostring(text), x = x, y = y,
      small = (opts and opts.small) and true or false,
      right = endX or x,
    }
    return drawn, endX, endY
  end
  local function restore() FrlgFont.draw = realDraw end

  local function lastMatch(pat, atY)
    local hit = nil
    for _, d in ipairs(draws) do
      if d.text:match(pat) and (atY == nil or d.y == atY) then hit = d end
    end
    return hit
  end

  -- pokefirered/data/maps/VermilionCity_Mart/map.json:20
  Map.load(nil, game, MART, { x = 2, y = 4, facing = "up" })
  if game.session then
    game.session.x, game.session.y, game.session.facing = 2, 4, "up"
  end
  Player.cellX, Player.cellY = 2, 4
  Player.px, Player.py = 2 * 16, 4 * 16
  Player.targetX, Player.targetY = 2, 4
  Player.facing = "up"
  U.wait(90)
  U.shot(game, DIR .. "/shop_money_01_counter.png")

  U.tap(game, "a")
  for _ = 1, 360 do
    if Choice.isOpen() or ShopMenu.isOpen() then break end
    U.tap(game, "a")
    U.wait(6)
  end
  if not result(Choice.isOpen() or ShopMenu.isOpen(),
    "talking to the clerk reached the BUY / SELL / QUIT choice") then
    restore()
    return finish()
  end

  -- pokefirered/src/shop.c:216
  for _ = 1, 300 do
    if ShopMenu.isOpen() and ShopMenu.mode ~= "root" then break end
    U.tap(game, "a")
    U.wait(8)
  end
  if not result(ShopMenu.isOpen() and ShopMenu.mode ~= "root",
    "BUY opened the mart stock list, mode=" .. tostring(ShopMenu.mode)) then
    restore()
    return finish()
  end

  draws = {}
  U.wait(30)
  U.shot(game, DIR .. "/shop_money_02_buy_list.png")

  -- pokefirered/src/money.c:87
  local CONTENT_LEFT, CONTENT_TOP = 8, 8
  local money = lastMatch("^¥%d", CONTENT_TOP + 12)
  result(money ~= nil, "the mart money window drew its amount")
  result(money and money.small == true,
    "the amount prints in FONT_SMALL (money.c:87), small=" .. tostring(money and money.small))
  result(money and money.right <= CONTENT_LEFT + 64,
    string.format("the amount ends at %s, the window's right edge is %d",
      tostring(money and money.right), CONTENT_LEFT + 64))
  result(money and money.x >= CONTENT_LEFT,
    "and it starts inside the frame at " .. tostring(money and money.x))

  local label = lastMatch("^" .. Strings("MONEY") .. "$", CONTENT_TOP)
  result(label ~= nil and label.small == false,
    "the MONEY label stays FONT_NORMAL (money.c:110)")

  restore()
  ShopMenu.close()
  U.wait(30)
  finish()
end
