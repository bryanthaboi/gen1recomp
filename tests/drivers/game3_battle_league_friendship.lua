local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_battle_league_friendship"

local GRASS_MAP = "FR_ROUTE_1"
local GYM_MAP = "FR_PEWTER_CITY_GYM"
-- pokefirered/include/constants/opponents.h:420
local TRAINER_LEADER_BROCK = 414
-- pokefirered/include/constants/items.h:12
local ITEM_MASTER_BALL = 1

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    if fails == 0 then
      print("PASS battle_league_friendship")
      love.event.quit(0)
    else
      print("FAIL battle_league_friendship failures=" .. fails)
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
  local Pokemon = require("src.core.game3.pokemon")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Encounters = require("src.core.game3.encounters")
  local Bag = require("src.core.game3.bag")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Rng = require("src.core.game3.rng")
  local Trainers = require("src.core.game3.scripting.trainers")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local SummaryData = require("src.core.game3.summary_data")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.party = {}
  Party.giveMon(session, 1, 14)
  Party.giveMon(session, 4, 14)
  Bag.add(session.bag, ITEM_MASTER_BALL, 2)

  local function placeAt(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(60)
  end

  local function grassCell()
    local layout = Map._def and Map._def.midLayout
    if not layout then return nil end
    local best, bestScore = nil, -1
    local function ok(cx, cy)
      return Encounters.encounterTypeAt(cx, cy) == 1
        and Collision.isWalkable(cx, cy)
        and Collision.canEnter(game, cx, cy, {}) ~= false
    end
    for cy = 3, layout.height - 4 do
      for cx = 3, layout.width - 4 do
        if ok(cx, cy) then
          local score = 0
          for dy = -2, 2 do
            for dx = -2, 2 do
              if ok(cx + dx, cy + dy) then score = score + 1 end
            end
          end
          if score > bestScore then best, bestScore = { cx, cy }, score end
        end
      end
    end
    if best and bestScore >= 9 then return best[1], best[2] end
    return nil
  end

  local DIRS = { "right", "down", "left", "up" }
  local DELTA = { right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 }, up = { 0, -1 } }

  local function patrol(mapId, maxSteps)
    local steps, stuck, di = 0, 0, 1
    while steps < maxSteps and stuck < 24 do
      if Battle.isActive and Battle.isActive() then return true, steps end
      local d = DELTA[DIRS[di]]
      local tx, ty = Player.cellX + d[1], Player.cellY + d[2]
      if Encounters.encounterTypeAt(tx, ty) ~= 1 or not Collision.isWalkable(tx, ty) then
        stuck = stuck + 1
        di = (di % 4) + 1
      else
        local bx, by = Player.cellX, Player.cellY
        U.hold(game, DIRS[di], 20)
        U.wait(4)
        if Battle.isActive and Battle.isActive() then return true, steps end
        if Map.current ~= mapId then return false, steps end
        if Player.cellX ~= bx or Player.cellY ~= by then
          steps = steps + 1
          stuck = 0
        else
          stuck = stuck + 1
          di = (di % 4) + 1
        end
      end
    end
    return (Battle.isActive and Battle.isActive()) or false, steps
  end

  -- pokefirered/src/wild_encounter.c:355 StandardWildEncounter
  local function forceEncounter(mapId)
    local enc
    for _ = 1, 400 do
      enc = Encounters.rollLand(mapId)
      if enc then break end
    end
    if not enc then return false end
    if not BattleBridge.startWild(Runtime._mod, game, enc, {}) then return false end
    for _ = 1, 600 do
      if Battle.isActive and Battle.isActive() then return true end
      U.wait(1)
    end
    return Battle.isActive and Battle.isActive()
  end

  local function atCommand()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local function pumpTo(pred, limit)
    local idle = 0
    for _ = 1, limit or 1200 do
      if pred() then return true end
      idle = idle + 1
      if Anim.vm() and Anim.vm():busy() then
        U.wait(1)
      -- pokefirered/src/battle_message.c:477
      elseif Battle._phase == "catch_nickname_prompt"
          or (Ui.choiceActive and Ui.choiceActive()) then
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
    return pred()
  end

  local mapSecOf = function(mapId)
    local def = game and game.data and game.data.maps and game.data.maps[mapId]
    return def and tonumber(def.regionMapSectionId)
  end

  Rng.SeedRng(0x2468)
  Rng.SeedWildEncounterRng(0x2468)

  local caught = nil

  placeAt(GRASS_MAP, 9, 9, "down")
  local gx, gy = grassCell()
  if result(gx ~= nil, GRASS_MAP .. " has open tall grass") then
    placeAt(GRASS_MAP, gx, gy, "right")
    Encounters.resetRateModifiers()
    local hit, steps = patrol(GRASS_MAP, 8)
    if not hit then hit = forceEncounter(GRASS_MAP) end
    if result(hit, "walking Route 1 grass started a wild battle (steps=" .. steps .. ")") then
      pumpTo(atCommand, 1500)
      local st = Battle.getState()
      local foeSp = st and st.enemy and (st.enemy.species
        or (st.enemy.mon and (st.enemy.mon.species or st.enemy.mon.speciesId)))
      local foeName = (foeSp and Pokemon.name(foeSp)) or "?"
      local before = #session.party
      -- pokefirered/src/battle_script_commands.c:9496 Cmd_handleballthrow
      Ui._pendingCommand = { kind = "bag", itemId = ITEM_MASTER_BALL, user = "player" }
      Ui._mode = "none"
      pumpTo(function() return #session.party > before end, 2000)
      caught = session.party[#session.party]
      result(caught ~= nil, "the Master Ball caught the wild " .. tostring(foeName))
      pumpTo(function() return not Battle.isActive() end, 1500)
      U.wait(60)
    end
  end

  if caught then
    local sec = mapSecOf(GRASS_MAP)
    U.log(string.format("caught %s: metLocation=%s (route 1 mapsec=%s) metLevel=%s level=%s secret=%s",
      tostring(caught.name), tostring(caught.metLocation), tostring(sec),
      tostring(caught.metLevel), tostring(caught.level), tostring(caught.otSecretId)))
    -- pokefirered/src/pokemon.c:1817 CreateBoxMon
    result(caught.metLocation == sec, "the caught mon was met in the Route 1 map section")
    result(caught.metLevel == caught.level, "the caught mon's met level is its capture level")
    -- pokefirered/src/pokemon.c:3692 GiveMonToPlayer
    result(type(caught.otSecretId) == "number", "the caught mon carries a secret id")
    result(caught.otId == session.trainerId, "the caught mon's visible OT id is the player's")
    local memo = SummaryData.formatTrainerMemo(caught, session)
    U.log("memo: " .. table.concat(memo, " / "):gsub("\n", " "))
    result(table.concat(memo, " "):find("ROUTE 1", 1, true) ~= nil,
      "the trainer memo names ROUTE 1")
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

  local function closeSummary()
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

  if caught and result(openParty(), "party menu opens") then
    if result(openSummary(#session.party), "summary opens on the caught mon") then
      U.wait(50)
      result(U.shot(game, DIR .. "/league_friendship_01_caught_memo.png"),
        "shot the caught mon's trainer memo")
    end
    closeSummary()
  end

  -- pokefirered/src/battle_main.c:713 AdjustFriendship(FRIENDSHIP_EVENT_LEAGUE_BATTLE)
  local brock = Trainers.foeFromId(TRAINER_LEADER_BROCK)
  if result(brock ~= nil, "Brock's party came out of the cache") then
    local info = Trainers.info(TRAINER_LEADER_BROCK)
    U.log("brock class=" .. tostring(info and info.class) .. " name=" .. tostring(info and info.name))
    result(Pokemon.isLeagueTrainerClass(info and info.class), "Brock is TRAINER_CLASS_LEADER")

    placeAt(GYM_MAP, 5, 12, "up")
    local before = {}
    for i, mon in ipairs(session.party) do
      before[i] = Pokemon.friendshipOf(mon)
    end
    local ok = BattleBridge.start(Runtime._mod, game, brock,
      { wild = false, trainerId = TRAINER_LEADER_BROCK, fade = false })
    result(ok == true, "the gym leader battle started")
    pumpTo(atCommand, 2500)
    for i, mon in ipairs(session.party) do
      U.log(string.format("slot %d %s friendship %d -> %d", i, tostring(mon.name),
        before[i], Pokemon.friendshipOf(mon)))
    end
    -- pokefirered/src/pokemon.c:1623 sFriendshipEventDeltas
    result(Pokemon.friendshipOf(session.party[1]) == before[1] + 3,
      "slot 1 gained 3 friendship from the leader battle")
    result(Pokemon.friendshipOf(session.party[2]) == before[2] + 3,
      "slot 2 gained 3 friendship from the leader battle")
    if caught then
      -- pokefirered/src/pokemon.c:5499
      result(Pokemon.friendshipOf(caught) == before[#before] + 3,
        "the caught mon gained 3, with no met-location bonus away from Route 1")
    end
    result(atCommand(), "the leader battle reached the command menu")
    result(U.shot(game, DIR .. "/league_friendship_02_brock_battle.png"),
      "shot the gym leader battle")
    Battle.abort("run")
    pumpTo(function() return not Battle.isActive() end, 1200)
    U.wait(40)
  end

  -- pokefirered/src/pokemon.c:5499
  if caught and brock then
    placeAt(GRASS_MAP, 9, 9, "down")
    local before = Pokemon.friendshipOf(caught)
    local ok = BattleBridge.start(Runtime._mod, game, brock,
      { wild = false, trainerId = TRAINER_LEADER_BROCK, fade = false })
    result(ok == true, "a second leader battle started on Route 1")
    pumpTo(atCommand, 2500)
    U.log(string.format("caught mon on route 1: friendship %d -> %d", before,
      Pokemon.friendshipOf(caught)))
    result(Pokemon.friendshipOf(caught) == before + 4,
      "the caught mon gained 3 plus the met-location bonus on Route 1")
    Battle.abort("run")
    pumpTo(function() return not Battle.isActive() end, 1200)
    U.wait(30)
  end

  finish()
end
