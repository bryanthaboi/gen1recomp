local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_pp_items_2420"

-- pokefirered/include/constants/items.h:38
local ITEM_ETHER = 34
local ITEM_PP_UP = 69
local ITEM_LEPPA_BERRY = 138
local ITEM_BERRY_POUCH = 365
local PALLET = "FR_PALLET_TOWN"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS pp_items_2420")
    love.event.quit(0)
  else
    print("FAIL pp_items_2420 failures=" .. failures)
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
  local Bag = require("src.core.game3.bag")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local BerryPouch = require("src.ui.game3.berry_pouch")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, 7, 15)
  local mon = session.party[1]
  mon.moves = { 33, 39, 145, 110 }
  mon.pp = { 2, 30, 30, 40 }
  mon.maxPp = { 35, 30, 30, 40 }
  mon.ppBonusesPacked = nil
  session.bag = session.bag or {}
  Bag.add(session.bag, ITEM_ETHER, 3)
  Bag.add(session.bag, ITEM_PP_UP, 1)
  Bag.add(session.bag, ITEM_LEPPA_BERRY, 2)
  Bag.add(session.bag, ITEM_BERRY_POUCH, 1)

  Map.load(nil, game, PALLET, { x = 7, y = 10, facing = "down" })
  Player.moving = false
  Player.cellX, Player.cellY = 7, 10
  Player.px, Player.py = 7 * 16, 10 * 16
  Player.targetX, Player.targetY = 7, 10
  U.wait(90)

  local function pickInBag(pocket, itemId)
    for _ = 1, 6 do
      if BagMenu.currentPocket() == pocket then break end
      U.tap(game, "right")
      U.wait(15)
    end
    for _ = 1, 30 do
      local want
      for i, r in ipairs(BagMenu.list() or {}) do
        if tonumber(r.id) == itemId then want = i end
      end
      if not want or BagMenu.cursor == want then break end
      U.tap(game, (BagMenu.cursor > want) and "up" or "down")
      U.wait(8)
    end
    local row = BagMenu.isOpen() and BagMenu.list()[BagMenu.cursor]
    return row and tonumber(row.id) == itemId
  end

  local function openFieldBag(pocket, itemId)
    U.tap(game, "start")
    U.wait(30)
    for _ = 1, 12 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "bag" then break end
      U.tap(game, "down")
      U.wait(8)
    end
    U.tap(game, "a")
    U.wait(60)
    return pickInBag(pocket, itemId)
  end

  local function waitMode(m, n)
    for _ = 1, n or 120 do
      if PartyMenu.isOpen() and PartyMenu.mode == m then return true end
      U.wait(1)
    end
    return false
  end

  local function closeAllField()
    for _ = 1, 20 do
      if not (PartyMenu.isOpen() or BagMenu.isOpen() or (StartMenu.isOpen and StartMenu.isOpen())) then break end
      U.tap(game, "b")
      U.wait(20)
    end
  end

  -- pokefirered/src/party_menu.c:4591 ItemUseCB_TryRestorePP
  if not result(openFieldBag("ITEMS", ITEM_ETHER), "field bag cursor on ETHER") then return finish() end
  U.tap(game, "a")
  U.wait(20)
  U.tap(game, "a")
  if not result(waitMode("use", 120), "USE opened the party menu") then return finish() end
  U.wait(20)
  PartyMenu.cursor = 1
  U.tap(game, "a")
  U.wait(10)
  result(waitMode("forget", 30), "a move-select window opened")
  result(PartyMenu._forgetPrompt == "Restore which move?",
    "prompt is gText_RestoreWhichMove (" .. tostring(PartyMenu._forgetPrompt) .. ")")
  U.wait(10)
  U.shot(game, DIR .. "/2420_field_ether_restore_which_move.png")
  local hp0 = mon.hp
  U.tap(game, "a")
  waitMode("message", 60)
  U.wait(20)
  result((PartyMenu._messageText or ""):find("PP was restored.", 1, true) ~= nil,
    "gText_PPWasRestored shown (" .. tostring(PartyMenu._messageText) .. ")")
  U.shot(game, DIR .. "/2420_field_ether_pp_restored.png")
  result(mon.pp[1] == 12, "field ETHER restored TACKLE 2 -> " .. tostring(mon.pp[1]))
  result(mon.hp == hp0, "and HP unchanged")
  result(Bag.has(session.bag, ITEM_ETHER, 2) and not Bag.has(session.bag, ITEM_ETHER, 3),
    "one ETHER consumed")
  U.tap(game, "a")
  U.wait(20)
  closeAllField()

  -- pokefirered/src/party_menu.c:4709 ItemUseCB_PPUp
  if not result(openFieldBag("ITEMS", ITEM_PP_UP), "field bag cursor on PP UP") then return finish() end
  U.tap(game, "a")
  U.wait(20)
  U.tap(game, "a")
  if not result(waitMode("use", 120), "USE opened the party menu for PP UP") then return finish() end
  U.wait(20)
  PartyMenu.cursor = 1
  U.tap(game, "a")
  U.wait(10)
  result(waitMode("forget", 30) and PartyMenu._forgetPrompt == "Boost PP of which?",
    "prompt is gText_BoostPp (" .. tostring(PartyMenu._forgetPrompt) .. ")")
  U.wait(10)
  U.shot(game, DIR .. "/2420_field_ppup_boost_which.png")
  local base = Pokemon.movePp(33)
  U.tap(game, "a")
  waitMode("message", 60)
  U.wait(20)
  result((PartyMenu._messageText or ""):find("TACKLE's PP increased.", 1, true) ~= nil,
    "gText_MovesPPIncreased shown (" .. tostring(PartyMenu._messageText) .. ")")
  U.shot(game, DIR .. "/2420_field_ppup_pp_increased.png")
  local want = base + math.floor(base * 20 / 100)
  result(mon.maxPp[1] == want, string.format("PP UP max PP %d -> %s (+20%% of base)", base, tostring(mon.maxPp[1])))
  result(mon.pp[1] == 12 + want - base, "and current PP rose by the same step (" .. tostring(mon.pp[1]) .. ")")
  U.tap(game, "a")
  U.wait(20)
  closeAllField()

  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 5 }, { fade = false })
  if not result(ok == true, "wild battle started " .. tostring(err or "")) then return finish() end

  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local lastTap, f = 0, 0
  local function pumpToCommand(n)
    for _ = 1, n or 3000 do
      f = f + 1
      if at_command() then return true end
      if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return at_command()
  end
  if not result(pumpToCommand(), "reached the battle command menu") then return finish() end
  local st = Battle.getState()
  st.enemy.mon.moves = { 150, 0, 0, 0 }
  st.enemy.mon.pp = { 40, 0, 0, 0 }
  local State = require("src.core.game3.battle.state")
  local bmon = State.ensureBattleMoves(st.player)
  bmon.pp[1] = 1
  bmon.pp[2] = 0
  local party = st.playerParty
  local pmon = party[st.player.partyIndex or 1]
  pmon.hp = math.max(1, (tonumber(pmon.maxHp) or 20) - 5)
  st.player.mon.hp = pmon.hp

  local function openBattleBag()
    Ui._menuIndex = 2
    U.tap(game, "a")
    for _ = 1, 120 do
      if BagMenu.isOpen() and BagMenu.mode == "list" then break end
      U.wait(1)
    end
    U.wait(30)
    return BagMenu.isOpen()
  end

  local function pickMonAndMove(moveCursor, shotName, msgShot)
    if not waitMode("use", 120) then return false end
    U.wait(20)
    PartyMenu.cursor = 1
    U.tap(game, "a")
    U.wait(10)
    if not waitMode("forget", 30) then return false end
    for _ = 2, moveCursor do
      U.tap(game, "down")
      U.wait(6)
    end
    U.wait(10)
    U.shot(game, DIR .. "/" .. shotName)
    U.tap(game, "a")
    waitMode("message", 60)
    U.wait(20)
    U.shot(game, DIR .. "/" .. msgShot)
    local txt = PartyMenu._messageText
    U.tap(game, "a")
    return true, txt
  end

  -- pokefirered/src/party_menu.c:4675 TryUsePPItemInBattle
  local hpBefore = pmon.hp
  if not result(openBattleBag(), "battle BAG opened") then return finish() end
  if not result(pickInBag("ITEMS", ITEM_ETHER), "battle bag cursor on ETHER") then return finish() end
  U.tap(game, "a")
  U.wait(20)
  U.tap(game, "a")
  local okE, txtE = pickMonAndMove(1, "2420_battle_ether_restore_which_move.png", "2420_battle_ether_pp_restored.png")
  result(okE and (txtE or ""):find("PP was restored.", 1, true) ~= nil,
    "battle ETHER picked a move and showed PP was restored (" .. tostring(txtE) .. ")")
  pumpToCommand()
  result(st.player.mon.pp[1] == 11, "battle ETHER restored the active battler's PP 1 -> " .. tostring(st.player.mon.pp[1]))
  result(pmon.pp[1] == 11, "and the party mon's PP matches (" .. tostring(pmon.pp[1]) .. ")")
  result(pmon.hp == hpBefore and st.player.mon.hp == hpBefore,
    "HP unchanged " .. tostring(hpBefore) .. " -> " .. tostring(st.player.mon.hp))
  local sawUsed = false
  for _, t in ipairs(Ui.log()) do if t:find("ETHER", 1, true) then sawUsed = true end end
  result(sawUsed, "battle log has RED used the ETHER")

  if not result(openBattleBag(), "battle BAG opened again") then return finish() end
  if not result(pickInBag("KEY_ITEMS", ITEM_BERRY_POUCH), "battle bag cursor on BERRY POUCH") then return finish() end
  BerryPouch.show(session, session.bag, { session = session, bag = session.bag })
  U.wait(30)
  for i, r in ipairs(BerryPouch.list() or {}) do
    if tonumber(r.id) == ITEM_LEPPA_BERRY then BerryPouch.cursor = i end
  end
  U.tap(game, "a")
  U.wait(15)
  U.tap(game, "a")
  local okL, txtL = pickMonAndMove(2, "2420_battle_leppa_restore_which_move.png", "2420_battle_leppa_pp_restored.png")
  result(okL and (txtL or ""):find("PP was restored.", 1, true) ~= nil,
    "battle LEPPA picked a move and showed PP was restored (" .. tostring(txtL) .. ")")
  pumpToCommand()
  result(st.player.mon.pp[2] == 10, "battle LEPPA restored move 2 PP 0 -> " .. tostring(st.player.mon.pp[2]))
  result(pmon.pp[2] == 10, "and the party mon's PP matches (" .. tostring(pmon.pp[2]) .. ")")
  result(pmon.hp == hpBefore, "HP still unchanged (" .. tostring(pmon.hp) .. ")")

  finish()
end
