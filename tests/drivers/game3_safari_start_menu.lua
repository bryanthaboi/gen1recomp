local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_safari_start_menu"

local ENTRANCE = "FR_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE"
local CENTER = "FR_SAFARI_ZONE_CENTER"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS safari_start_menu")
    love.event.quit(0)
  else
    print("FAIL safari_start_menu failures=" .. failures)
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
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local Safari = require("src.core.game3.safari")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local StartMenu = require("src.ui.game3.start_menu")
  local Party = require("src.core.game3.party")
  local Collision = require("src.core.game3.collision")
  local Encounters = require("src.core.game3.encounters")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Rng = require("src.core.game3.rng")
  local Flags = require("src.core.game3.scripting.flags")
  local Bridge = require("src.core.game3.bridge")
  local SaveData = require("src.core.SaveData")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.party = {}
  Party.giveMon(session, 6, 40)
  session.money = 5000
  local secret = session.secretId

  local function place(x, y, facing)
    Player.moving = false
    Player.progress = 0
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
    U.wait(60)
  end

  local function walk(dir)
    local sx, sy = Player.cellX, Player.cellY
    for _ = 1, 30 do
      U.hold(game, dir, 1)
      if Player.moving then break end
    end
    for _ = 1, 90 do
      if not Player.moving then break end
      U.wait(1)
    end
    U.wait(2)
    return Player.cellX ~= sx or Player.cellY ~= sy
  end

  local function mashA(n)
    for _ = 1, n or 40 do
      U.tap(game, "a")
      U.wait(6)
      if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() then break end
    end
  end

  local function ids()
    local t = {}
    for _, e in ipairs(StartMenu.ENTRIES or {}) do t[#t + 1] = e.id end
    return table.concat(t, ",")
  end

  -- pokefirered/data/maps/FuchsiaCity_SafariZone_Entrance/scripts.inc:114
  goTo(ENTRANCE, 4, 6, "up")
  walk("up")
  walk("up")
  walk("up")
  mashA(60)
  for _ = 1, 60 do
    U.wait(4)
    if Space.mapId == CENTER then break end
    if Space.vm and Space.vm:isRunning() then mashA(20) end
  end
  if not result(Space.mapId == CENTER,
    "paid at the gate and entered the zone, map=" .. tostring(Space.mapId)) then return finish() end
  result(Safari.isActive(session) == true, "EnterSafariMode armed safari mode")
  result(Safari.balls(session) == 30, "30 SAFARI BALLS (" .. Safari.balls(session) .. ")")
  walk("up")
  U.wait(60)

  for _ = 1, 40 do
    if StartMenu.isOpen() then break end
    if (Space.vm and Space.vm:isRunning()) or Message.isOpen() then mashA(4) end
    U.tap(game, "start")
    for _ = 1, 30 do
      if StartMenu.isOpen() then break end
      U.wait(1)
    end
  end
  if not result(StartMenu.isOpen(), "start menu opened in the zone") then return finish() end
  -- pokefirered/src/start_menu.c:226
  result(ids() == "retire,pokedex,pokemon,bag,trainer,option,exit",
    "safari start menu list (" .. ids() .. ")")
  result(not ids():find("save", 1, true), "no SAVE in the zone")
  result(StartMenu._safariStats == true, "steps/balls window is up")
  U.shot(game, DIR .. "/2422_safari_start_menu_retire_stats.png")
  U.tap(game, "b")
  U.wait(20)

  local before = SaveData.load()
  game:_hotkey("f1")
  local after = SaveData.load()
  result(not (after and after.map == CENTER) and (after and after.savedAt) == (before and before.savedAt),
    "F1 quick-save refused in the zone")
  result(game:saveOffered() == false, "mod saveGame gate refuses in the zone")

  -- pokefirered/src/wild_encounter.c:712
  local function grassy(cx, cy)
    if Encounters.encounterTypeAt(cx, cy) ~= 1 then return false end
    return Collision.isWalkable(cx, cy) and Collision.canEnter(game, cx, cy, {}) ~= false
  end
  local gx, gy
  do
    local layout = Map._def and Map._def.midLayout
    local bestScore = -1
    for cy = 3, (layout and layout.height or 0) - 4 do
      for cx = 3, layout.width - 4 do
        if grassy(cx, cy) then
          local score = 0
          for dy = -2, 2 do
            for dx = -2, 2 do
              if grassy(cx + dx, cy + dy) then score = score + 1 end
            end
          end
          if score > bestScore then gx, gy, bestScore = cx, cy, score end
        end
      end
    end
  end
  if not result(gx ~= nil, "found safari grass") then return finish() end
  local dir = grassy(gx + 1, gy) and "right" or "down"
  local back = dir == "right" and "left" or "up"
  place(gx, gy, dir)
  U.wait(20)
  Rng.SeedRng(0x2468)
  Rng.SeedWildEncounterRng(0x2468)
  Encounters.resetRateModifiers()
  local d = dir
  for _ = 1, 300 do
    if Battle.isActive and Battle.isActive() then break end
    walk(d)
    d = (d == dir) and back or dir
  end
  if not result(Battle.isActive and Battle.isActive(), "grass encounter started") then return finish() end
  local st = Battle.getState()
  result(st and st.safari == true, "the encounter is a Safari battle")
  local atMenu = false
  for _ = 1, 150 do
    if Battle._phase == "command" and Ui._mode == "menu" then atMenu = true break end
    U.tap(game, "a")
    U.wait(6)
  end
  result(atMenu, "reached the BALL/BAIT/ROCK/RUN menu")
  U.shot(game, DIR .. "/2422_safari_battle_menu.png")
  for _ = 1, 400 do
    if not (Battle.isActive and Battle.isActive()) then break end
    if Battle._phase == "command" and Ui._mode == "menu" then
      -- pokefirered/src/battle_controller_safari.c:162
      U.tap(game, "right") U.wait(6)
      U.tap(game, "down") U.wait(6)
      U.tap(game, "a") U.wait(20)
    else
      U.tap(game, "a")
      U.wait(8)
    end
  end
  if not result(not (Battle.isActive and Battle.isActive()), "ran from the safari battle") then
    return finish()
  end
  U.wait(90)

  U.tap(game, "start")
  U.wait(30)
  StartMenu.cursor = 1
  result(StartMenu.isOpen() and StartMenu.ENTRIES[1].id == "retire", "RETIRE is the first entry")
  U.tap(game, "a")
  for _ = 1, 60 do
    if Choice.active then break end
    U.tap(game, "a")
    U.wait(8)
  end
  result(Choice.active and Choice.cursor == 1, "retire asks YES/NO")
  U.tap(game, "a")
  for _ = 1, 120 do
    if Space.mapId == ENTRANCE then break end
    U.wait(4)
  end
  result(Space.mapId == ENTRANCE, "RETIRE warped back to the gate, map=" .. tostring(Space.mapId))
  result(Safari.isActive(session) == false, "safari mode is off after RETIRE")
  mashA(60)
  U.wait(60)
  U.shot(game, DIR .. "/2422_retire_back_at_gate.png")

  goTo(CENTER, 26, 30, "up")
  result(Safari.isActive(session) == false, "stranded setup: in the zone with safari mode off")
  Bridge.persistSessionOnly(Runtime._mod, game)
  result(game:saveGame() ~= false, "wrote a save standing in the zone")
  local raw = SaveData.load()
  result(type(raw) == "table" and raw.map == CENTER, "the save holds map " .. tostring(raw and raw.map))

  game:_handleBootAction({ action = "continue" })
  U.wait(60)
  for _ = 1, 400 do
    if game.phase ~= "quest_log" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  U.wait(120)
  local loaded = Runtime.getSession()
  if not result(loaded ~= nil, "Continue reached the field") then return finish() end
  result(loaded.secretId == secret, "secret id came back off the save")
  result(Space.mapId == ENTRANCE, "the stranded save resumes at the gate, map=" .. tostring(Space.mapId))
  U.shot(game, DIR .. "/2422_stranded_continue_at_gate.png")
  mashA(60)
  for _ = 1, 60 do
    if Flags.getVar(Space.store, nil, Safari.VAR_ENTRANCE_SCENE) == 0 then break end
    mashA(10)
    U.wait(4)
  end
  result(Flags.getVar(Space.store, nil, Safari.VAR_ENTRANCE_SCENE) == 0, "ExitWarpIn finished")
  result(Safari.isActive(loaded) == false, "safari mode stays off")
  U.wait(30)
  local reload = SaveData.load()
  result(reload and reload.map == CENTER, "the slot itself is untouched until the next save")

  finish()
end
