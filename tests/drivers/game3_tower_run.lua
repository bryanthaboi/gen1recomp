local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_tower_run"

local LOBBY = "FR_TRAINER_TOWER_LOBBY"
local FLOOR_1F = "FR_TRAINER_TOWER_1F"
local HOUSE = "FR_SEVEN_ISLAND_HOUSE_ROOM1"

local MEWTWO, MAGIKARP, SPLASH, PSYCHIC = 150, 129, 150, 94

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS tower_run")
    love.event.quit(0)
  else
    print("FAIL tower_run failures=" .. failures)
    love.event.quit(1)
  end
end

local function run(game)
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
  local Party = require("src.core.game3.party")
  local Battle = require("src.core.game3.battle")
  local Choice = require("src.ui.game3.choice")
  local Message = require("src.ui.game3.message")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local Tower = require("src.core.game3.trainer_tower")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end
  local function vmRunning() return (Space.vm and Space.vm:isRunning()) and true or false end
  local function messageOpen()
    return (Message.isOpen and Message.isOpen()) and true or false
  end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    place(x, y, facing)
    U.wait(90)
  end

  local function mash(frames)
    for _ = 1, (frames or 60) do
      if messageOpen() or Choice.isOpen() then U.tap(game, "a") end
      U.wait(6)
    end
  end

  local function mashUntil(cond, tries)
    for _ = 1, (tries or 80) do
      if cond() then return true end
      if messageOpen() or Choice.isOpen() then U.tap(game, "a") end
      U.wait(6)
    end
    return cond()
  end

  local function partySpecies()
    local out = {}
    for i, mon in ipairs(session.party or {}) do
      out[i] = tostring(mon.species or mon.speciesId)
    end
    return table.concat(out, ",")
  end

  -- pokefirered/src/ereader_helpers.c:1 a card record is written by the e-Reader accessory
  local function insertEReaderCard()
    local mons = {}
    for i = 1, 3 do
      mons[i] = {
        species = MAGIKARP, heldItem = 0, moves = { SPLASH, 0, 0, 0 }, level = 5,
        ppBonuses = 0,
        hpEV = 0, attackEV = 0, defenseEV = 0, speedEV = 0, spAttackEV = 0, spDefenseEV = 0,
        otId = 0,
        hpIV = 4, attackIV = 4, defenseIV = 4, speedIV = 4, spAttackIV = 4, spDefenseIV = 4,
        abilityNum = 0, personality = 3, nickname = "", friendship = 0,
      }
    end
    session.ereaderTrainer = { name = "CARD", facilityClass = 44, party = mons }
  end

  session.party = {}
  Party.giveMon(session, MEWTWO, 50)
  local lead = session.party[1]
  lead.moves, lead.pp, lead.maxPp = { PSYCHIC }, { 10 }, { 10 }
  for _, species in ipairs({ 1, 4, 7, 25, 133 }) do
    Party.giveMon(session, species, 20)
  end
  result(#session.party == 6, "the player has a full party: " .. partySpecies())

  local pack = Tower.pack()
  print("[driver] gTrainerTowerFloors in this cache = " .. tostring(pack ~= nil))
  result(pack ~= nil and Tower.floors(Tower.CHALLENGE_TYPE.SINGLE) ~= nil,
    "the cache carries the real gTrainerTowerFloors table")

  goTo(LOBBY, 9, 12, "up")
  result(session.map == LOBBY, "the player is in the Trainer Tower lobby")

  for _ = 1, 8 do
    if Player.cellY <= 7 or vmRunning() then break end
    U.hold(game, "up", 20)
    U.wait(8)
  end
  local sawYesNo = mashUntil(function() return Choice.isOpen() end, 60)
  result(sawYesNo, "the lobby receptionist asked whether to challenge the trainers")
  U.tap(game, "a")
  U.wait(30)
  local sawModes = mashUntil(function() return Choice.isOpen() end, 60)
  result(sawModes, "the challenge mode list opened")
  U.tap(game, "a")
  mash(30)
  result(Tower.getChallengeId(session) == Tower.CHALLENGE_TYPE.SINGLE,
    "a SINGLE challenge is running")

  -- pokefirered/data/scripts/trainer_tower.inc:7 DISABLE_SINGLES_TRIGGER
  goTo(FLOOR_1F, 10, 14, "up")
  result(session.map == FLOOR_1F, "the player reached 1F")
  mash(10)
  local floor = Tower.floor(Tower.getChallengeId(session), Tower.floorIndexForMap(session.map))
  print(string.format("[driver] floor challengeType=%s trainers=%s VAR_RESULT=%s"
    .. " VAR_TEMP_2=%s singlesTrigger=%s doublesTrigger=%s",
    tostring(floor and floor.challengeType), tostring(floor and floor.trainers and #floor.trainers),
    tostring(getVar(0x800D)), tostring(getVar(0x4002)), tostring(getVar(0x400E)),
    tostring(getVar(0x400F))))
  result(getVar(0x400E) == 0,
    "TrainerTower_EventScript_SetObjectsSingles left the singles trigger armed")
  U.shot(game, DIR .. "/tower_run_01_floor.png")

  for _ = 1, 10 do
    if vmRunning() or Player.cellY <= 13 then break end
    U.hold(game, "up", 20)
    U.wait(8)
  end
  print(string.format("[driver] player at (%d,%d) vm=%s", Player.cellX, Player.cellY,
    tostring(vmRunning())))
  local triggered = mashUntil(function() return Battle.isActive() end, 140)
  result(triggered, "the floor trigger ran the trainer approach and ttower_dobattle")
  if not triggered then
    U.shot(game, DIR .. "/tower_run_02_no_battle.png")
    return
  end

  local st = Battle._st
  result(st ~= nil and st.double ~= true, "1F of a SINGLE challenge is a single battle")
  -- pokefirered/src/trainer_tower.c:735 BATTLE_TYPE_TRAINER_TOWER
  result(st ~= nil and st.trainerTower == true,
    "the engine sees the fight as a tower battle, not an ordinary trainer battle")
  print("[driver] tower battle trainerName=" .. tostring(st and st.trainerName)
    .. " class=" .. tostring(st and st.trainerClassName)
    .. " pic=" .. tostring(st and st.trainerPicId))
  result(st ~= nil and type(st.trainerName) == "string" and st.trainerName ~= ""
    and st.trainerClassName == nil,
    "and shows the floor trainer's own name, not gTrainers[0]")
  local moneyBefore = tonumber(session.money) or 0
  local expBefore = tonumber(session.party[1].exp) or 0
  local foeMon = st and st.enemy and st.enemy.mon
  print("[driver] tower opponent species=" .. tostring(foeMon and (foeMon.species or foeMon.speciesId))
    .. " level=" .. tostring(foeMon and foeMon.level))
  result(foeMon ~= nil and (tonumber(foeMon.level) or 0) == 50,
    "the floor mon is levelled to the player's top level (GetPartyMaxLevel)")
  U.wait(90)
  U.shot(game, DIR .. "/tower_run_02_battle.png")

  local BattleUi = require("src.core.game3.battle.ui")
  local guard = 0
  while Battle.isActive() and guard < 900 do
    guard = guard + 1
    if PartyMenu.isOpen() then
      -- pokefirered/src/party_menu.c:2960 the faint switch picks the first living slot
      local slot = nil
      for i, mon in ipairs(st.playerParty or session.party or {}) do
        if (tonumber(mon.hp) or 0) > 0 then
          slot = i
          break
        end
      end
      if Battle._phase == "switching" and slot then
        for _ = 1, 6 do
          if PartyMenu.cursor == slot then break end
          U.tap(game, "down")
          U.wait(4)
        end
        U.tap(game, "a")
        U.wait(8)
        U.tap(game, "a")
      else
        U.tap(game, "b")
      end
    elseif Battle._phase == "shift_prompt" then
      -- pokefirered/src/battle_script_commands.c:5574 B on the yesnobox is NO
      U.tap(game, "b")
    elseif BattleUi._mode == "menu" then
      -- pokefirered/src/battle_controller_player.c:340 B_ACTION_USE_MOVE
      for _ = 1, 3 do
        if BattleUi._menuIndex == 1 then break end
        U.tap(game, "up")
        U.wait(2)
        U.tap(game, "left")
        U.wait(2)
      end
      U.tap(game, "a")
    else
      U.tap(game, "a")
    end
    U.wait(4)
    if guard % 120 == 0 then
      local b = Battle._st
      print(string.format("[driver] battle guard=%d phase=%s turn=%s foeHp=%s", guard,
        tostring(Battle._phase), tostring(b and b.turn),
        tostring(b and b.enemy and b.enemy.mon and b.enemy.mon.hp)))
    end
  end
  result(not Battle.isActive(), "the tower battle finished")
  mash(40)
  print("[driver] VAR_RESULT=" .. tostring(getVar(0x800D))
    .. " floorsCleared=" .. tostring(Tower.record(session).floorsCleared))
  result(Tower.record(session).floorsCleared == 1,
    "the won battle cleared 1F through TrainerTower_EventScript_SetFloorCleared")
  print("[driver] money " .. tostring(moneyBefore) .. " -> " .. tostring(session.money)
    .. " lead exp " .. tostring(expBefore) .. " -> " .. tostring(session.party[1].exp))
  -- pokefirered/data/battle_scripts_1.s:2991 BattleScript_BattleTowerTrainerBattleWon
  result((tonumber(session.money) or 0) == moneyBefore, "a tower win pays no prize money")
  -- pokefirered/src/battle_script_commands.c:3130
  result((tonumber(session.party[1].exp) or 0) == expBefore, "and hands out no exp")
  U.shot(game, DIR .. "/tower_run_03_floor_cleared.png")

  -- pokefirered/data/maps/SevenIsland_House_Room1/scripts.inc:9 ValidateEReaderTrainer
  print("[driver] an e-Reader card cannot be read on this port, so the driver writes the"
    .. " card record the accessory would have written and lets the real special judge it")
  insertEReaderCard()
  -- pokefirered/data/maps/SevenIsland_House_Room1/scripts.inc:15 setobjectxyperm 4, 2
  goTo(HOUSE, 4, 3, "up")
  result(session.map == HOUSE, "the player is in the Seven Island house")
  result(getVar(0x4001) == 1,
    "the map script set TRAINER_VISITING, so the old woman offers the battle")
  local Objects = require("src.core.game3.objects")
  for _, lid in ipairs(Objects.listActive() or {}) do
    local eo = Objects.find(lid)
    if eo then
      print(string.format("[driver] house object %s at (%s,%s)", tostring(lid),
        tostring(eo.cellX), tostring(eo.cellY)))
    end
  end

  local before = partySpecies()
  U.tap(game, "a")
  U.wait(30)
  local askedToBattle = mashUntil(function() return Choice.isOpen() end, 60)
  result(askedToBattle, "the old woman asked whether to challenge the visiting trainer")
  U.tap(game, "a")
  U.wait(20)
  local picker = mashUntil(function()
    return PartyMenu.isOpen() and PartyMenu.mode == "choose_multi"
  end, 90)
  result(picker, "ChooseHalfPartyForBattle opened the three mon picker")
  result(Tower.savedPlayerParty(session) ~= nil, "SavePlayerParty stashed the six mons first")
  if picker then
    U.wait(20)
    U.shot(game, DIR .. "/tower_run_04_party_picker.png")
    -- pokefirered/src/party_menu.c:3760 CursorCB_Enter
    for slot = 1, 3 do
      for _ = 1, 8 do
        if PartyMenu.cursor == slot then break end
        U.tap(game, "down")
        U.wait(4)
      end
      U.tap(game, "a")
      U.wait(10)
      U.tap(game, "a")
      U.wait(10)
    end
    print("[driver] picked " .. #PartyMenu.chosenOrder() .. " mons, cursor=" ..
      tostring(PartyMenu.cursor))
    -- pokefirered/src/party_menu.c:1133 START jumps to CONFIRM
    U.tap(game, "start")
    U.wait(8)
    U.tap(game, "a")
    U.wait(40)
  end
  print("[driver] selected order = " .. table.concat(Tower.selectedOrder(session), ",")
    .. " VAR_RESULT=" .. tostring(getVar(0x800D)))
  result(Tower.selectedOrder(session)[1] ~= 0, "the pick landed in gSelectedOrderFromParty")

  local reduced = mashUntil(function() return #(session.party or {}) <= 3 end, 120)
  print("[driver] party after the reduce = " .. partySpecies())
  result(reduced, "ReducePlayerPartyToThree cut the party down for the battle")

  local restored = false
  for _ = 1, 400 do
    if session.map == HOUSE and #(session.party or {}) == 6 then
      restored = true
      break
    end
    U.tap(game, "a")
    U.wait(6)
  end
  print("[driver] party on exit = " .. partySpecies() .. " map=" .. tostring(session.map))
  result(restored, "LoadPlayerParty gave the whole party back")
  result(partySpecies() == before, "and it is the same party in the same order")

  StartMenu.show({ session = session, game = game })
  U.wait(20)
  local pokemonRow = nil
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "pokemon" then pokemonRow = i end
  end
  if pokemonRow then
    for _ = 2, pokemonRow do
      U.tap(game, "down")
      U.wait(8)
    end
    U.tap(game, "a")
    U.wait(40)
    result(PartyMenu.isOpen(), "the party screen opened on the restored party")
    U.shot(game, DIR .. "/tower_run_05_party_restored.png")
    U.tap(game, "b")
    U.wait(20)
  end
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    print("FAIL tower_run driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
