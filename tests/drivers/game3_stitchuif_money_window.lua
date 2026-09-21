local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuif_money_window"

local CORNER = "FR_CELADON_CITY_GAME_CORNER"
-- pokefirered/include/constants/flags.h:604
local FLAG_GOT_COIN_CASE = 0x243

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchuif_money_window")
    love.event.quit(0)
  else
    print("FAIL stitchuif_money_window failures=" .. failures)
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Bag = require("src.core.game3.bag")
  local CoinsBox = require("src.ui.game3.coins_box")
  local MoneyBox = require("src.ui.game3.money_box")
  local FrlgFont = require("src.ui.game3.frlg_font")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

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

  local function lastDraw(exact)
    local hit = nil
    for _, d in ipairs(draws) do
      if d.text == exact then hit = d end
    end
    return hit
  end

  local function lastYen()
    local hit = nil
    for _, d in ipairs(draws) do
      if d.text:sub(1, 2) == "¥" then hit = d end
    end
    return hit
  end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function coins() return Bag.Coins.get(session) end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "up" })
    place(x, y, facing or "up")
    U.wait(90)
  end

  local function busy()
    local running = Space.vm and Space.vm:isRunning()
    local open = Message.isOpen and Message.isOpen()
    return running or open or Choice.active
  end

  local function waitForChoice(limit)
    for _ = 1, (limit or 80) do
      if Choice.active then return true end
      if not busy() then return false end
      U.tap(game, "a")
      U.wait(12)
    end
    return Choice.active
  end

  local function pick(index, label)
    if not result(waitForChoice(), "a menu opened for " .. label) then return false end
    for _ = 1, index do
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    U.wait(24)
    return true
  end

  local function runOut(limit)
    for _ = 1, (limit or 120) do
      if not busy() then return true end
      U.tap(game, "a")
      U.wait(12)
    end
    return not busy()
  end

  -- pokefirered/data/maps/CeladonCity_Restaurant/scripts.inc:20
  Flags.setFlag(Space.store, ctx(), FLAG_GOT_COIN_CASE, true)
  session.money = 30000

  goTo(CORNER, 6, 3, "up")
  result(Space.mapId == CORNER, "entered the Celadon Game Corner, map=" .. tostring(Space.mapId))

  -- pokefirered/data/maps/CeladonCity_GameCorner/scripts.inc:21
  place(6, 3, "up")
  U.wait(12)
  U.tap(game, "a")
  U.wait(60)
  result(MoneyBox.isVisible() == true, "showmoneybox 0, 0 opened the money window")
  result(CoinsBox.isVisible() == true, "showcoinsbox 0, 5 opened the coins window")

  -- pokefirered/src/coins.c:79, pokefirered/src/money.c:123
  local function contentRight(tileX) return (tileX + 1 + 8) * 8 end

  draws = {}
  U.wait(30)
  local money = lastYen()
  result(money ~= nil and money.text == "¥30000",
    "the money amount reached the font, " .. tostring(money and money.text))
  result(money and money.small == true, "the money amount prints in FONT_SMALL (money.c:87)")
  result(money and money.right <= contentRight(0),
    string.format("the money ends at %s, the window content ends at %d",
      tostring(money and money.right), contentRight(0)))

  local count = lastDraw(CoinsBox.countText(0))
  result(count ~= nil, "the coins count reached the font")
  result(count and count.small == true, "the coins count prints in FONT_SMALL (coins.c:76)")
  result(count and count.right <= contentRight(0),
    string.format("the count ends at %s, the window content ends at %d",
      tostring(count and count.right), contentRight(0)))
  U.shot(game, DIR .. "/stitchuif_money_window_01_both_boxes.png")

  -- pokefirered/data/maps/CeladonCity_GameCorner/scripts.inc:44
  pick(1, "the 500 coin counter")
  runOut()
  result(coins() == 500, "addcoins 500 credited the coin case, " .. coins())

  place(6, 3, "up")
  U.wait(12)
  U.tap(game, "a")
  U.wait(60)
  pick(1, "the 500 coin counter again")
  U.wait(36)
  result(CoinsBox.amount() == 1000,
    "updatecoinsbox redrew the window at 1000, " .. tostring(CoinsBox.amount()))

  draws = {}
  U.wait(30)
  count = lastDraw(CoinsBox.countText(1000))
  result(count ~= nil, "the four-digit count reached the font")
  result(count and count.small == true, "1000 COINS prints in FONT_SMALL")
  result(count and count.right <= contentRight(0),
    string.format("1000 COINS ends at %s, the window content ends at %d",
      tostring(count and count.right), contentRight(0)))
  money = lastYen()
  result(money and money.small == true,
    "the spent-down money " .. tostring(money and money.text) .. " stays FONT_SMALL")
  result(money and money.right <= contentRight(0),
    string.format("the spent-down money ends at %s, content ends at %d",
      tostring(money and money.right), contentRight(0)))
  U.shot(game, DIR .. "/stitchuif_money_window_02_four_digit_count.png")

  runOut()
  FrlgFont.draw = realDraw
  finish()
end
