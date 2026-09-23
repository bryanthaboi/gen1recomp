local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_2425_oran_consume"

local GRASS_MAP = "FR_ROUTE_3"
local ITEM_ORAN_BERRY = 139

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    if fails == 0 then
      print("PASS oran_consume")
      love.event.quit(0)
    else
      print("FAIL oran_consume failures=" .. fails)
      love.event.quit(1)
    end
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local ItemsData = require("src.core.game3.items_data")
  local RomText = require("src.core.game3.rom_text")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  require("src.core.game3.scripting.flags").setFlag(require("src.core.game3.scripting.space").store, nil, 0x828, true) -- data/maps/PalletTown_ProfessorOaksLab/scripts.inc:1120
  session.party = {}
  Party.giveMon(session, 39, 20)
  local mon = session.party[1]
  mon.item, mon.heldItem = ITEM_ORAN_BERRY, ITEM_ORAN_BERRY
  mon.moves = { 1 }
  mon.pp = { 35 }
  mon.maxPp = { 35 }

  local function placeAt(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    session.x, session.y, session.facing = x, y, facing or "down"
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(60)
  end

  local function logText(t)
    if type(t) == "table" then return tostring(t.text or "") end
    return tostring(t or "")
  end

  local function berryLogged(from)
    local log = Ui.log and Ui.log() or Ui._log or {}
    for i = from or 1, #log do
      if logText(log[i]):find("ORAN BERRY", 1, true) then return true end
    end
    return false
  end

  local function pumpBattle(shotPath)
    local idle, shotTaken = 0, false
    for _ = 1, 4000 do
      if not Battle.isActive() then return shotTaken end
      idle = idle + 1
      local log = Ui._log or {}
      local last = logText(log[#log])
      if shotPath and not shotTaken and last:find("ORAN BERRY", 1, true)
          and Message.isOpen and Message.isOpen() then
        U.wait(40)
        shotTaken = U.shot(game, shotPath)
      end
      if Anim.vm() and Anim.vm():busy() then
        U.wait(1)
      elseif Ui.choiceActive and Ui.choiceActive() then
        idle = 0
        U.tap(game, "b")
        U.wait(10)
      elseif idle >= 10 then
        idle = 0
        U.tap(game, "a")
        U.wait(6)
      else
        U.wait(1)
      end
    end
    return shotTaken
  end

  local function openParty()
    for _ = 1, 40 do
      if PartyMenu.isOpen and PartyMenu.isOpen() then return true end
      if StartMenu.isOpen and StartMenu.isOpen() then break end
      U.tap(game, "start")
      U.wait(8)
    end
    for _ = 1, 20 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "pokemon" then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    for _ = 1, 60 do
      if PartyMenu.isOpen and PartyMenu.isOpen() then return true end
      U.wait(4)
    end
    return false
  end

  local function openSummary(slot)
    PartyMenu.cursor = slot
    U.wait(8)
    U.tap(game, "a")
    U.wait(12)
    for _ = 1, 12 do
      if PartyMenu.ACTIONS[PartyMenu.actionCursor] == "SUMMARY" then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    for _ = 1, 60 do
      if SummaryMenu.isOpen() then return true end
      U.wait(4)
    end
    return false
  end

  local function closeAll()
    for _ = 1, 60 do
      if not SummaryMenu.isOpen() then break end
      U.tap(game, "b")
      U.wait(6)
    end
    for _ = 1, 60 do
      if not (PartyMenu.isOpen and PartyMenu.isOpen()) then break end
      U.tap(game, "b")
      U.wait(6)
    end
    for _ = 1, 40 do
      if not (StartMenu.isOpen and StartMenu.isOpen()) then break end
      U.tap(game, "b")
      U.wait(6)
    end
    U.wait(30)
  end

  local function summaryShot(path, want, label)
    if result(openParty(), "party menu opens (" .. label .. ")") then
      if result(openSummary(1), "summary opens (" .. label .. ")") then
        U.wait(50)
        result(SummaryMenu.heldItemText(mon) == want, "summary item reads " .. tostring(want) .. " (" .. label .. ")")
        result(U.still(game, path), "shot " .. path:match("[^/]+$"))
      end
    end
    closeAll()
  end

  placeAt(GRASS_MAP, 10, 10, "down")

  local oranName = ItemsData.displayName(ITEM_ORAN_BERRY)
  local noneText = RomText.plain("gText_PokeSum_Item_None")
  summaryShot(DIR .. "/2425_summary_before.png", oranName, "before battle")

  -- pokefirered/src/battle_util.c:2562
  local function fight(round, shotPath)
    mon.hp = math.floor(mon.maxHp / 2)
    local ok = BattleBridge.start(Runtime._mod, game,
      { species = 129, level = 30, moves = { 150 }, pp = { 40 }, item = 0 },
      { wild = true, fade = false })
    result(ok == true, "battle " .. round .. " started")
    for _ = 1, 600 do
      if Battle.isActive() then break end
      U.wait(1)
    end
    local shot = pumpBattle(shotPath)
    result(not Battle.isActive(), "battle " .. round .. " ended")
    local berry = berryLogged(1)
    U.wait(60)
    return berry, shot
  end

  local berry1, shot1 = fight(1, DIR .. "/2425_battle1_berry.png")
  result(berry1, "battle 1 ate the ORAN BERRY")
  result(shot1, "shot the battle 1 berry message")
  result(mon.item == nil and mon.heldItem == nil, "party mon holds nothing after battle 1")

  summaryShot(DIR .. "/2425_summary_after.png", noneText, "after battle 1")

  local berry2 = fight(2, nil)
  result(not berry2, "battle 2 had no ORAN BERRY message")
  result(mon.item == nil, "party mon still holds nothing after battle 2")

  finish()
end
