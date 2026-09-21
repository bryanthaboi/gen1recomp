local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_growth_vitamin"

local PIKACHU = 25
local ITEM_PROTEIN = 64

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS growth_vitamin")
    love.event.quit(0)
  else
    print("FAIL growth_vitamin failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Pokemon = require("src.core.game3.pokemon")
  local StepEvents = require("src.core.game3.step_events")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local PartyMenu = require("src.ui.game3.party_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, PIKACHU, 50)
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_PROTEIN, 2)
  local pika = session.party[1]
  if not result(pika ~= nil, "party holds PIKACHU") then return finish() end
  result(Pokemon.evCount(pika) == 0, "a fresh PIKACHU has 0 EVs")
  result(Pokemon.friendshipOf(pika) == 70, "and its species base friendship")
  result(tonumber(pika.metLocation) ~= nil, "and a met location from the current map")

  local beforeAtk = pika.attack
  local beforeFriendship = Pokemon.friendshipOf(pika)

  U.tap(game, "start")
  U.wait(30)
  if not result(StartMenu.isOpen(), "start menu opened") then return finish() end

  local bagIdx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "bag" then bagIdx = i break end
  end
  for _ = 1, 20 do
    if StartMenu.cursor == bagIdx then break end
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(60)
  if not result(BagMenu.isOpen(), "bag opened from the start menu") then return finish() end

  local row
  for i, r in ipairs(BagMenu.list()) do
    if tonumber(r.id) == ITEM_PROTEIN then row = i break end
  end
  if not result(row ~= nil, "PROTEIN is in the ITEMS pocket") then return finish() end
  for _ = 1, 30 do
    if BagMenu.cursor == row then break end
    U.tap(game, "down")
    U.wait(6)
  end
  result(BagMenu.cursor == row, "cursor on PROTEIN")
  U.shot(game, DIR .. "/growth_vitamin_01_bag.png")

  U.tap(game, "a")
  U.wait(30)
  if not result(BagMenu.mode == "action", "item action menu opened") then return finish() end
  for _ = 1, 10 do
    if BagMenu.ACTIONS[BagMenu.actionCursor] == "USE" then break end
    U.tap(game, "down")
    U.wait(6)
  end
  result(BagMenu.ACTIONS[BagMenu.actionCursor] == "USE", "USE selected")
  U.tap(game, "a")
  U.wait(60)
  if not result(PartyMenu.open and PartyMenu.mode == "use", "party menu opened for PROTEIN") then
    return finish()
  end

  for _ = 1, 10 do
    if PartyMenu.cursor == 1 then break end
    U.tap(game, "up")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(90)
  U.shot(game, DIR .. "/growth_vitamin_02_raised.png")

  result(pika.evs and tonumber(pika.evs.atk) == 10,
    "PROTEIN added 10 ATTACK EVs (" .. tostring(pika.evs and pika.evs.atk) .. ")")
  result(tonumber(pika.attack) > beforeAtk,
    "ATTACK went up (" .. tostring(beforeAtk) .. " -> " .. tostring(pika.attack) .. ")")
  -- pokefirered/src/pokemon.c:3990
  result(Pokemon.friendshipOf(pika) == beforeFriendship + 6,
    "friendship rose by the vitamin amount plus the met-location bonus ("
      .. tostring(Pokemon.friendshipOf(pika)) .. ")")
  result(Bag.get(session.bag, ITEM_PROTEIN) == 1, "one PROTEIN left in the bag")

  local guard = 0
  while (PartyMenu.open or BagMenu.isOpen() or StartMenu.isOpen()) and guard < 200 do
    guard = guard + 1
    U.tap(game, "b")
    U.wait(6)
  end
  result(not PartyMenu.open, "closed back to the overworld")
  U.wait(30)

  -- pokefirered/src/field_control_avatar.c:699 UpdateHappinessStepCounter
  local before = Pokemon.friendshipOf(pika)
  session.vars = session.vars or {}
  local moved = 0
  for _ = 1, 40 do
    session.vars[0x403F] = 127
    StepEvents.onStepTaken(session, game)
    if Pokemon.friendshipOf(pika) ~= before then moved = moved + 1 end
    before = Pokemon.friendshipOf(pika)
  end
  result(moved > 5 and moved < 35,
    "the 128-step walk counter is a coin flip, not a guarantee (" .. moved .. "/40)")

  finish()
end
