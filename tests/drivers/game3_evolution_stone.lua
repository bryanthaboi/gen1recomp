local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_evolution_stone"

local PIKACHU, RAICHU = 25, 26
local NIDORINA, NIDOQUEEN = 30, 31
local ITEM_MOON_STONE, ITEM_THUNDER_STONE = 94, 96

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS evolution_stone")
    love.event.quit(0)
  else
    print("FAIL evolution_stone failures=" .. failures)
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
  local Evolution = require("src.core.game3.evolution")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local EvolutionScene = require("src.ui.game3.evolution_scene")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, PIKACHU, 16)
  Party.giveMon(session, NIDORINA, 20)
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_MOON_STONE, 1)
  Bag.add(session.bag, ITEM_THUNDER_STONE, 1)
  result(#session.party == 2, "party holds PIKACHU and NIDORINA")

  local function close_menus()
    for _ = 1, 30 do
      if not PartyMenu.open and not BagMenu.isOpen() and not StartMenu.isOpen() then break end
      U.tap(game, "b")
      U.wait(20)
    end
    return not PartyMenu.open and not BagMenu.isOpen() and not StartMenu.isOpen()
  end

  local function use_from_bag(itemId, label, shotPath)
    U.tap(game, "start")
    U.wait(30)
    if not result(StartMenu.isOpen(), label .. ": start menu opened") then return false end
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
    if not result(BagMenu.isOpen(), label .. ": bag opened from the start menu") then return false end
    local row
    for i, r in ipairs(BagMenu.list()) do
      if tonumber(r.id) == itemId then row = i break end
    end
    if not result(row ~= nil, label .. " is in the ITEMS pocket") then return false end
    for _ = 1, 30 do
      if BagMenu.cursor == row then break end
      U.tap(game, "down")
      U.wait(6)
    end
    if not result(BagMenu.cursor == row, label .. ": cursor on the stone") then return false end
    if shotPath then U.shot(game, shotPath) end
    U.tap(game, "a")
    U.wait(30)
    if not result(BagMenu.mode == "action", label .. ": item action menu opened") then return false end
    for _ = 1, 10 do
      if BagMenu.ACTIONS[BagMenu.actionCursor] == "USE" then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    U.wait(60)
    return result(PartyMenu.open and PartyMenu.mode == "use",
      label .. ": party menu opened for the stone")
  end

  local function move_cursor(slot)
    for _ = 1, 12 do
      if PartyMenu.cursor == slot then break end
      U.tap(game, slot > PartyMenu.cursor and "down" or "up")
      U.wait(8)
    end
    return PartyMenu.cursor == slot
  end

  local function run_scene()
    local guard = 0
    while EvolutionScene.isOpen() and guard < 400 do
      guard = guard + 1
      U.tap(game, "a")
      U.wait(3)
    end
    return not EvolutionScene.isOpen()
  end

  local pika, nido = session.party[1], session.party[2]

  if not use_from_bag(ITEM_MOON_STONE, "MOON STONE", DIR .. "/evolution_stone_01_bag.png") then
    return finish()
  end
  -- pokefirered/src/party_menu.c:872
  result(Evolution.itemCheck(nido, ITEM_MOON_STONE) == NIDOQUEEN,
    "EVO_MODE_ITEM_CHECK says NIDORINA can use a MOON STONE")
  result(Evolution.itemCheck(pika, ITEM_MOON_STONE) == nil,
    "EVO_MODE_ITEM_CHECK says PIKACHU cannot")
  result(PartyMenu.itemIsEvolutionStone(ITEM_MOON_STONE),
    "and the party box treats item 94 as a stone")
  U.shot(game, DIR .. "/evolution_stone_02_no_use.png")

  if not result(move_cursor(2), "cursor on NIDORINA") then return finish() end
  U.tap(game, "a")
  U.wait(120)
  if not result(EvolutionScene.isOpen(), "MOON STONE started the evolution scene") then
    return finish()
  end
  U.shot(game, DIR .. "/evolution_stone_03_scene.png")
  result(run_scene(), "MOON STONE scene closed")
  U.wait(60)
  result(tonumber(session.party[2].species) == NIDOQUEEN, "NIDORINA evolved into NIDOQUEEN")
  result(not Bag.has(session.bag, ITEM_MOON_STONE, 1), "the MOON STONE was consumed")
  result(PartyMenu.mode == "list", "the party list is back with no lingering description")
  if not result(close_menus(), "menus closed after the MOON STONE") then return finish() end

  if not use_from_bag(ITEM_THUNDER_STONE, "THUNDERSTONE") then return finish() end
  result(Evolution.itemCheck(pika, ITEM_THUNDER_STONE) == RAICHU,
    "EVO_MODE_ITEM_CHECK says PIKACHU can use a THUNDERSTONE")
  result(Evolution.itemCheck(session.party[2], ITEM_THUNDER_STONE) == nil,
    "EVO_MODE_ITEM_CHECK says NIDOQUEEN cannot")
  U.shot(game, DIR .. "/evolution_stone_04_no_use_thunder.png")

  if not result(move_cursor(1), "cursor on PIKACHU") then return finish() end
  U.tap(game, "a")
  U.wait(120)
  if not result(EvolutionScene.isOpen(), "THUNDERSTONE started the evolution scene") then
    return finish()
  end
  result(run_scene(), "THUNDERSTONE scene closed")
  result(tonumber(session.party[1].species) == RAICHU, "PIKACHU evolved into RAICHU")
  result(not Bag.has(session.bag, ITEM_THUNDER_STONE, 1), "the THUNDERSTONE was consumed")
  result(PartyMenu.mode == "list", "the party list is back with both HP bars")
  U.wait(150)
  U.shot(game, DIR .. "/evolution_stone_05_after.png")

  finish()
end
