local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ops_game_corner"

local CORNER = "FR_CELADON_CITY_GAME_CORNER"
local PRIZE_ROOM = "FR_CELADON_CITY_GAME_CORNER_PRIZE_ROOM"

-- pokefirered/include/constants/flags.h:604
local FLAG_GOT_COIN_CASE = 0x243
-- pokefirered/include/constants/items.h:205
local ITEM_SMOKE_BALL = 194
-- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:357
local SMOKE_BALL_PRICE = 800

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS ops_game_corner")
    love.event.quit(0)
  else
    print("FAIL ops_game_corner failures=" .. failures)
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
  local Gfx = require("src.core.game3.gfx")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function setFlag(id) Flags.setFlag(Space.store, ctx(), id, true) end
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

  local function pick(index, label, shot)
    if not result(waitForChoice(), "a menu opened for " .. label) then return false end
    if shot then
      U.wait(12)
      U.shot(game, DIR .. "/" .. shot)
    end
    for _ = 1, index do
      U.tap(game, "down")
      U.wait(6)
    end
    local want = index + 1
    result(Choice.cursor == want,
      "cursor on entry " .. index .. " for " .. label .. ", got " .. tostring(Choice.cursor))
    local shown = Choice.options and Choice.options[want]
    print("[driver] picking \"" .. tostring(shown) .. "\"")
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

  local function talkTo(x, y, facing)
    place(x, y, facing)
    U.wait(12)
    U.tap(game, "a")
    U.wait(30)
    return busy()
  end

  -- pokefirered/data/maps/CeladonCity_Restaurant/scripts.inc:20
  setFlag(FLAG_GOT_COIN_CASE)
  session.money = 30000
  print("[driver] coin case in hand, wallet " .. tostring(session.money))

  result(type(Gfx.drawUi) == "function", "the field HUD compositor is reachable")

  local paints = 0
  local coinsBoxDraw = CoinsBox.draw
  CoinsBox.draw = function(...)
    paints = paints + 1
    return coinsBoxDraw(...)
  end

  goTo(CORNER, 6, 3, "up")
  result(Space.mapId == CORNER, "entered the Celadon Game Corner, map=" .. tostring(Space.mapId))
  result(coins() == 0, "a fresh coin case is empty, " .. coins())

  -- pokefirered/data/maps/CeladonCity_GameCorner/scripts.inc:21
  if not result(talkTo(6, 3, "up"), "the coins clerk answers") then return finish() end
  U.wait(24)
  result(CoinsBox.isVisible() == true, "showcoinsbox opened the coins window")
  result(CoinsBox.amount() == 0, "the window opened on 0 coins, " .. tostring(CoinsBox.amount()))
  paints = 0
  U.wait(60)
  print("[driver] CoinsBox.draw calls over 60 visible frames: " .. paints)
  result(paints > 0, "the open coins window is painted every frame by Gfx.drawUi")

  -- pokefirered/data/maps/CeladonCity_GameCorner/scripts.inc:44
  pick(1, "the coin purchase counter", "ops_game_corner_01_coin_menu.png")
  runOut()
  print("[driver] after one purchase: coins=" .. coins() .. " money=" .. tostring(session.money))
  result(coins() == 500, "addcoins 500 credited the coin case, " .. coins())
  result(session.money == 20000, "removemoney 10000 left 20000, " .. tostring(session.money))
  result(CoinsBox.isVisible() == false, "hidecoinsbox closed the window at ClerkEnd")

  if not result(talkTo(6, 3, "up"), "the coins clerk answers a second time") then return finish() end
  U.wait(24)
  result(CoinsBox.amount() == 500,
    "showcoinsbox reopened on the 500 coins already held, " .. tostring(CoinsBox.amount()))
  pick(1, "the coin purchase counter again")
  U.wait(24)
  result(CoinsBox.amount() == 1000,
    "updatecoinsbox redrew the window at 1000, " .. tostring(CoinsBox.amount()))
  U.shot(game, DIR .. "/ops_game_corner_02_bought_coins.png")
  runOut()
  print("[driver] after two purchases: coins=" .. coins() .. " money=" .. tostring(session.money))
  result(coins() == 1000, "the coin case holds 1000, " .. coins())
  result(session.money == 10000, "the wallet is down to 10000, " .. tostring(session.money))

  goTo(PRIZE_ROOM, 2, 3, "up")
  result(Space.mapId == PRIZE_ROOM, "entered the prize room, map=" .. tostring(Space.mapId))
  result(Bag.get(session.bag, ITEM_SMOKE_BALL) == 0, "no SMOKE BALL in the bag yet")

  -- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:331
  if not result(talkTo(2, 3, "up"), "the item prize clerk answers") then return finish() end
  U.wait(24)
  result(CoinsBox.isVisible() == true, "showcoinsbox opened the prize room window")
  result(CoinsBox.amount() == 1000,
    "the prize room window shows 1000 coins, " .. tostring(CoinsBox.amount()))

  -- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:341
  pick(0, "the battle item prizes", "ops_game_corner_03_prize_list.png")
  -- pokefirered/data/maps/CeladonCity_GameCorner_PrizeRoom/scripts.inc:305
  pick(0, "the YES/NO on the SMOKE BALL")
  U.wait(36)
  print("[driver] after the prize: coins=" .. coins() ..
    " window=" .. tostring(CoinsBox.amount()))
  result(coins() == 1000 - SMOKE_BALL_PRICE,
    "removecoins 800 left " .. (1000 - SMOKE_BALL_PRICE) .. ", got " .. coins())
  result(CoinsBox.amount() == 1000 - SMOKE_BALL_PRICE,
    "updatecoinsbox decremented the counter to " .. tostring(CoinsBox.amount()))
  U.shot(game, DIR .. "/ops_game_corner_04_counter_decremented.png")

  runOut()
  result(Bag.get(session.bag, ITEM_SMOKE_BALL) == 1,
    "the SMOKE BALL reached the bag, " .. Bag.get(session.bag, ITEM_SMOKE_BALL))
  result(CoinsBox.isVisible() == false, "hidecoinsbox closed the window at EndPrizeExchange")
  result(coins() == 200, "the coin case settled at 200, " .. coins())
  U.wait(30)
  U.shot(game, DIR .. "/ops_game_corner_05_released.png")

  CoinsBox.draw = coinsBoxDraw
  finish()
end
