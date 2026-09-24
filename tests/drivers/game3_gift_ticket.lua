local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_gift_ticket"

-- pokefirered/include/constants/vars.h:178
local VAR_MAP_SCENE_VERMILION_CITY = 0x407E
-- pokefirered/include/constants/vars.h:170
local VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F = 0x4076
-- pokefirered/include/constants/flags.h:1408
local FLAG_ENABLE_SHIP_NAVEL_ROCK = 0x84A
-- pokefirered/include/constants/flags.h:705
local FLAG_RECEIVED_MYSTIC_TICKET = 0x2A8
-- pokefirered/include/constants/flags.h:1391
local FLAG_SYS_MYSTERY_GIFT_ENABLED = 0x839
-- pokefirered/include/constants/flags.h:128
local FLAG_HIDE_MG_DELIVERYMEN = 0x70

local PC2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local VERMILION = "FR_VERMILION_CITY"
local NAVEL_HARBOR = "FR_NAVEL_ROCK_HARBOR"
-- pokefirered/data/maps/ViridianCity_PokemonCenter_2F/map.json:72
local DELIVERYMAN_LOCAL_ID = 4

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS gift_ticket")
    love.event.quit(0)
  else
    print("FAIL gift_ticket failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver started")
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
  local Objects = require("src.core.game3.objects")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Boot = require("src.ui.game3.boot")
  local GiftUi = require("src.ui.game3.mystery_gift")
  local MysteryGift = require("src.core.game3.mystery_gift")
  local Bag = require("src.core.game3.bag")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end
  local function getFlag(id) return Flags.getFlag(Space.store, ctx(), id) end
  local function mapId() return Space.mapId end

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
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing or "down")
    U.wait(90)
  end

  local function deliveryman()
    return Objects.find(DELIVERYMAN_LOCAL_ID)
  end

  local function talkTo(x, y, facing)
    place(x, y, facing)
    U.wait(12)
    U.tap(game, "a")
    U.wait(24)
    return (Space.vm and Space.vm:isRunning()) or (Message.isOpen and Message.isOpen())
  end

  -- pokefirered/data/scripts/questionnaire.inc:26
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_MYSTERY_GIFT_ENABLED, true)

  -- pokefirered/data/maps/ViridianCity_PokemonCenter_2F/map.json:21 the stairs warp
  goTo(PC2F, 1, 6, "up")
  local man = deliveryman()
  result(man ~= nil, "the Pokemon Center 2F carries the deliveryman object")
  result(man ~= nil and man.hidden == true,
    "with no WONDER CARD saved he is hidden, hidden=" .. tostring(man and man.hidden))
  result(getFlag(FLAG_HIDE_MG_DELIVERYMEN) == true,
    "FLAG_HIDE_MG_DELIVERYMEN is set by CableClub_OnTransition")
  U.shot(game, DIR .. "/gift_ticket_01_pc2f_no_card.png")

  local mystic
  for _, entry in ipairs(MysteryGift.builtins()) do
    if entry.key == "mystic_ticket" then mystic = entry end
  end
  result(mystic ~= nil, "the built-in set carries the MYSTIC TICKET card")
  result(mystic ~= nil and MysteryGift.receiveCard(session, mystic.card),
    "the Wonder Card saves onto the session")

  result(game:saveGame() ~= false, "the game saved before the Mystery Gift menu")
  U.wait(30)
  game:returnToTitle()
  U.wait(60)

  local function phase() return game.boot and game.boot.phase end
  for _ = 1, 60 do
    if phase() == Boot.PHASE.MENU then break end
    U.tap(game, "start")
    U.wait(30)
  end
  for _ = 1, 120 do
    if (game.boot.fadeT or 0) == 0 then break end
    U.wait(1)
  end
  U.wait(10)
  local rows = Boot.menuItems(game.boot)
  print("[driver] main menu rows: " .. table.concat(rows, " | "))
  result(rows[3] == "MYSTERY GIFT", "the MYSTERY GIFT row is on the main menu")
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "a")
  for _ = 1, 400 do
    if phase() == Boot.PHASE.MYSTERY_GIFT then break end
    U.wait(1)
  end
  if not result(phase() == Boot.PHASE.MYSTERY_GIFT, "the Mystery Gift screen opened") then
    return finish()
  end
  local st = game.boot.gift

  U.tap(game, "a")
  for _ = 1, 300 do
    if st.state == GiftUi.STATE.GIFT_INPUT then break end
    if st.msg then U.tap(game, "a") end
    U.wait(4)
  end
  result(st.state == GiftUi.STATE.GIFT_INPUT, "the saved WONDER CARD opens")
  U.shot(game, DIR .. "/gift_ticket_03_wonder_card.png")
  U.tap(game, "b")
  U.wait(20)
  U.tap(game, "b")
  for _ = 1, 200 do
    if phase() == Boot.PHASE.MENU then break end
    U.wait(1)
  end
  result(phase() == Boot.PHASE.MENU, "back on the main menu")

  for _ = 1, 120 do
    if (game.boot.fadeT or 0) == 0 then break end
    U.wait(1)
  end
  U.wait(10)
  U.tap(game, "a")
  for _ = 1, 900 do
    if game.phase ~= "boot" then break end
    U.wait(1)
  end
  for _ = 1, 400 do
    if game.phase == "field" then break end
    U.tap(game, "b")
    U.wait(10)
  end
  U.wait(120)
  session = Runtime.getSession() or game.session
  if not result(session ~= nil and game.phase == "field",
    "CONTINUE reached the field, phase=" .. tostring(game.phase)) then
    return finish()
  end
  result(MysteryGift.validateSavedCard(session), "the continued save carries the WONDER CARD")

  goTo(PC2F, 1, 6, "up")
  man = deliveryman()
  result(man ~= nil and man.hidden ~= true,
    "the saved card brings the deliveryman out, hidden=" .. tostring(man and man.hidden))
  result(getFlag(FLAG_HIDE_MG_DELIVERYMEN) ~= true,
    "CableClub_OnTransition cleared FLAG_HIDE_MG_DELIVERYMEN")
  U.shot(game, DIR .. "/gift_ticket_04_deliveryman.png")

  local mx = man and man.cellX or 1
  local my = man and man.cellY or 2
  print("[driver] deliveryman at (" .. tostring(mx) .. "," .. tostring(my) .. ")")
  local spoke = talkTo(mx, my + 1, "up")
  if not spoke then spoke = talkTo(mx + 1, my, "left") end
  if not spoke then spoke = talkTo(mx - 1, my, "right") end
  result(spoke, "the deliveryman answers")
  U.wait(30)
  U.shot(game, DIR .. "/gift_ticket_05_deliveryman_message.png")
  for _ = 1, 120 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(6)
  end
  U.wait(30)

  result(Bag.has(session.bag, MysteryGift.ITEM_MYSTIC_TICKET, 1),
    "the deliveryman handed the MYSTIC TICKET over")
  result(getFlag(FLAG_ENABLE_SHIP_NAVEL_ROCK) == true,
    "FLAG_ENABLE_SHIP_NAVEL_ROCK is set in the live store")
  result(getFlag(FLAG_RECEIVED_MYSTIC_TICKET) == true,
    "FLAG_RECEIVED_MYSTIC_TICKET is set in the live store")
  result(not MysteryGift.isGiftNotReceived(session), "the card reads as collected")

  -- pokefirered/data/maps/VermilionCity/scripts.inc:14
  setVar(VAR_MAP_SCENE_VERMILION_CITY, 3)
  -- pokefirered/data/maps/VermilionCity/scripts.inc:79
  setVar(VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F, 5)
  goTo(VERMILION, 24, 34, "up")
  setVar(VAR_MAP_SCENE_VERMILION_CITY, 3)
  setVar(VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F, 5)
  U.wait(30)

  local sailed = talkTo(24, 34, "up")
  if not sailed then sailed = talkTo(23, 33, "right") end
  if not sailed then sailed = talkTo(25, 33, "left") end
  result(sailed, "the Vermilion ferry sailor answers")

  -- pokefirered/data/maps/VermilionCity/scripts.inc:98 MULTICHOICE_SEVII_NAVEL
  local sawMenu = false
  for _ = 1, 40 do
    if Choice.active then sawMenu = true break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(12)
  end
  U.wait(24)
  result(sawMenu, "the Mystic Ticket destination menu opened")
  local labels = {}
  for _, row in ipairs((Choice.active and (Choice.items or Choice.options or Choice.labels)) or {}) do
    labels[#labels + 1] = type(row) == "table" and (row.text or row.label or row[1]) or tostring(row)
  end
  print("[driver] menu rows: " .. table.concat(labels, " | "))
  U.shot(game, DIR .. "/gift_ticket_06_navel_rock_menu.png")

  local hasNavel = false
  for _, label in ipairs(labels) do
    if tostring(label):upper():find("NAVEL") then hasNavel = true end
  end
  result(hasNavel, "NAVEL ROCK is one of the destinations")

  U.tap(game, "down")
  U.wait(18)
  U.tap(game, "a")
  U.wait(60)

  for _ = 1, 200 do
    if mapId() == NAVEL_HARBOR then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(12)
  end
  U.wait(120)
  print("[driver] after the Navel Rock sail: map=" .. tostring(mapId()) ..
    " at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  result(mapId() == NAVEL_HARBOR, "the Seagallop reached Navel Rock Harbor, map=" .. tostring(mapId()))
  U.shot(game, DIR .. "/gift_ticket_07_navel_rock_harbor.png")

  finish()
end
