local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_hidden_coins"

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
    print("PASS hidden_coins")
    love.event.quit(0)
  else
    print("FAIL hidden_coins failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Field = require("src.core.game3.field")
  local Collision = require("src.core.game3.collision")
  local Bag = require("src.core.game3.bag")
  local Message = require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  Flags.setVar(Space.store, nil, 0x4070, 1)

  local function goTo(x, y, facing)
    Map.load(nil, game, CORNER, { x = x, y = y, facing = facing })
    Player.cellX, Player.cellY, Player.targetX, Player.targetY = x, y, x, y
    Player.px, Player.py, Player.facing = x * 16, y * 16, facing
    session.x, session.y, session.facing = x, y, facing
    U.wait(120)
  end

  local function noneSlot()
    for _, slots in pairs(session.bag.pockets or {}) do
      for _, slot in ipairs(slots) do
        if tonumber(slot.id) == 0 then return true end
      end
    end
    return false
  end

  local function closeMessage()
    for _ = 1, 40 do
      if not Message.isOpen() then return end
      U.tap(game, "a")
      U.wait(10)
    end
  end

  local function waitPage(pattern)
    for _ = 1, 400 do
      if Message.isOpen() and Message.isWaiting()
          and tostring(Message.currentPage()):find(pattern, 1, true) then
        return true
      end
      U.wait(1)
    end
    return false
  end

  local SX, SY = 17, 5
  Map.load(nil, game, CORNER, { x = SX, y = SY + 1, facing = "up" })
  U.wait(60)
  local spot = Field.hiddenItemAt(game, SX, SY, 0)
  if not result(spot ~= nil and (tonumber(spot.item) or -1) == 0 and spot.quantity == 40,
      "the Game Corner hides 40 coins at (17,5)") then return finish() end

  local stand, facing
  for _, c in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
    local x, y = SX + c[1], SY + c[2]
    if Collision.canEnter(game, x, y, { fromX = SX, fromY = SY }) then
      stand, facing = { x, y }, c[3]
      break
    end
  end
  if not result(stand ~= nil, "found a floor cell facing the coins") then return finish() end

  Flags.setFlag(Space.store, nil, FLAG_GOT_COIN_CASE, false)
  session.coins = 0
  goTo(stand[1], stand[2], facing)
  U.tap(game, "a")
  result(waitPage("found\n40 COINS!"), "no case: RED found 40 COINS!")
  U.shot(game, DIR .. "/COIN_no_case_found.png")
  U.tap(game, "a")
  result(waitPage("There's nothing to put them in"), "no case: nothing to put them in")
  U.shot(game, DIR .. "/COIN_no_case_refused.png")
  closeMessage()
  result((session.coins or 0) == 0, "no case: coins unchanged")
  result(not Flags.getFlag(Space.store, nil, spot.flag), "no case: the coins stay on the floor")
  result(not noneSlot(), "no case: no ???????? slot in the bag")

  Flags.setFlag(Space.store, nil, FLAG_GOT_COIN_CASE, true)
  session.coins = 9980
  U.tap(game, "a")
  result(waitPage("found\n40 COINS!"), "full case: RED found 40 COINS!")
  U.tap(game, "a")
  result(waitPage("The COIN CASE is full"), "full case: the COIN CASE is full")
  U.shot(game, DIR .. "/COIN_case_full.png")
  closeMessage()
  result(session.coins == 9980, "full case: coins unchanged")
  result(not Flags.getFlag(Space.store, nil, spot.flag), "full case: the coins stay on the floor")

  session.coins = 100
  U.tap(game, "a")
  result(waitPage("found\n40 COINS!"), "with case: RED found 40 COINS!")
  U.shot(game, DIR .. "/COIN_with_case_found.png")
  result(waitPage("put the COINS away in\nthe COIN CASE."), "with case: put the COINS away")
  U.shot(game, DIR .. "/COIN_with_case_put_away.png")
  closeMessage()
  result(session.coins == 140, "with case: 40 coins added, coins=" .. tostring(session.coins))
  result(Flags.getFlag(Space.store, nil, spot.flag) == true, "with case: the hidden flag is set")
  result(not noneSlot(), "with case: no ???????? slot in the bag")
  U.tap(game, "a")
  U.wait(30)
  result(not Message.isOpen(), "the spot is empty afterwards")

  finish()
end
