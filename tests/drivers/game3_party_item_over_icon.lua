local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_party_item_over_icon"

-- pokeemerald/include/constants/items.h
local ITEM_POTION = 13

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS party_item_over_icon")
    love.event.quit(0)
  else
    print("FAIL party_item_over_icon failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Oam = require("src.core.game3.oam")
  local PartyMenu = require("src.ui.game3.party_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, 1, 16)
  Party.giveMon(session, 4, 15)
  for i = 1, 2 do
    local mon = session.party[i]
    mon.item, mon.heldItem = ITEM_POTION, ITEM_POTION
  end

  PartyMenu.show(session.party, nil, { session = session })
  U.wait(30)

  local order = {}
  local flushOne = Oam.flushOne
  Oam.flushOne = function(s)
    order[s] = #order + 1
    order[#order + 1] = s
    return flushOne(s)
  end
  PartyMenu.draw()
  Oam.flushOne = flushOne

  -- pokeemerald/src/party_menu.c:3946, :4025, :4125
  for i = 1, 2 do
    local slot = PartyMenu._oam and PartyMenu._oam[i]
    local mon = slot and slot.mon and Oam.get(slot.mon)
    local item = slot and slot.item and Oam.get(slot.item)
    local ball = slot and slot.ball and Oam.get(slot.ball)
    local om, oi, ob = mon and order[mon], item and order[item], ball and order[ball]
    result(om ~= nil and oi ~= nil and oi > om,
      string.format("slot %d held item draws over the mon icon (icon=%s item=%s)", i, tostring(om), tostring(oi)))
    result(om ~= nil and ob ~= nil and om > ob,
      string.format("slot %d mon icon draws over the ball (ball=%s icon=%s)", i, tostring(ob), tostring(om)))
  end
  U.still(game, DIR .. "/party_item_over_icon.png")

  PartyMenu.close()
  U.wait(10)
  finish()
end
