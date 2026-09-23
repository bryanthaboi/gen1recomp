local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_party_held_icons"

-- pokefirered/include/constants/items.h:17, :125
local ITEM_POTION = 13
local ITEM_ORANGE_MAIL = 121

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS party_held_icons")
    love.event.quit(0)
  else
    print("FAIL party_held_icons failures=" .. failures)
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
  Party.giveMon(session, 7, 14)
  local function hold(mon, item) mon.item, mon.heldItem = item, item end
  hold(session.party[1], ITEM_POTION)
  hold(session.party[2], ITEM_ORANGE_MAIL)
  hold(session.party[3], 0)

  local okSheet, sheet = pcall(PartyMenu.heldItemSheet)
  result(okSheet and sheet ~= nil and sheet.w == 8 and sheet.h == 8,
    "the held-item sheet came out of the cache as two 8x8 frames")
  if not okSheet then print("[driver] " .. tostring(sheet)) return finish() end

  PartyMenu.show(session.party, nil, { session = session })
  U.wait(30)

  local function itemSprite(i)
    local slot = PartyMenu._oam and PartyMenu._oam[i]
    return slot and slot.item and Oam.get(slot.item)
  end

  -- pokefirered/src/party_menu.c:2743 CreatePartyMonHeldItemSprite
  local s1, s2, s3 = itemSprite(1), itemSprite(2), itemSprite(3)
  result(s1 ~= nil and s1.quad == sheet.quads[0], "the POTION holder shows the item frame")
  -- pokefirered/src/data/party_menu.h:75 sPartyMenuSpriteCoords
  result(s1 ~= nil and s1.x == 20 and s1.y == 50, "at the lead slot's item coords (20, 50)")
  result(s2 ~= nil and s2.quad == sheet.quads[1], "the ORANGE MAIL holder shows the mail frame")
  result(s2 ~= nil and s2.x == 108 and s2.y == 28, "at slot 2's item coords (108, 28)")
  result(s3 == nil, "an empty hand has no icon")
  U.shot(game, DIR .. "/party_held_icons_menu.png")

  -- pokefirered/src/party_menu.c:2758 UpdatePartyMonHeldItemSprite
  hold(session.party[3], ITEM_POTION)
  hold(session.party[1], 0)
  for _ = 1, 1000 do
    s1, s3 = itemSprite(1), itemSprite(3)
    if s3 and not s1 then break end
    U.wait(1)
  end
  result(s3 ~= nil and s3.quad == sheet.quads[0], "giving slot 3 an item puts the icon up")
  result(s1 == nil, "taking the lead's item takes its icon down")
  U.shot(game, DIR .. "/party_held_icons_after_swap.png")

  PartyMenu.close()
  U.wait(10)
  finish()
end
