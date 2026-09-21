local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchsave_continue"

-- pokefirered/data/maps/FuchsiaCity_SafariZone_Entrance/scripts.inc:82
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
    print("PASS stitchsave_continue")
    love.event.quit(0)
  else
    print("FAIL stitchsave_continue failures=" .. failures)
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
  local StartMenu = require("src.ui.game3.start_menu")
  local SaveMenu = require("src.ui.game3.save_menu")
  local SaveData = require("src.core.SaveData")
  local Warp = require("src.core.game3.warp")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  -- pokefirered/src/new_game.c:56 InitPlayerTrainerId
  local secret = session.secretId
  result(type(secret) == "number" and secret >= 0 and secret < 0x10000,
    "New Game rolled a 16 bit secret id (" .. tostring(secret) .. ")")

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
    "inside the Safari Zone, map=" .. tostring(Space.mapId)) then return finish() end
  result(Safari.isActive(session) == true, "EnterSafariMode armed safari mode")
  result(Safari.balls(session) == 30, "30 SAFARI BALLS (" .. Safari.balls(session) .. ")")
  walk("up")
  walk("down")
  U.wait(120)
  U.shot(game, DIR .. "/stitchsave_01_in_the_zone.png")

  U.tap(game, "start")
  U.wait(30)
  if not result(StartMenu.isOpen(), "start menu opened") then return finish() end
  local saveIdx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "save" then saveIdx = i break end
  end
  if not result(saveIdx ~= nil, "SAVE is on the start menu") then return finish() end
  for _ = 1, 20 do
    if StartMenu.cursor == saveIdx then break end
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(40)
  if not result(SaveMenu.isOpen(), "the save dialog opened") then return finish() end
  for _ = 1, 8 do
    if SaveMenu._phase == "saved" then break end
    U.tap(game, "a")
    U.wait(30)
  end
  if not result(SaveMenu._phase == "saved",
    "the save was written, phase=" .. tostring(SaveMenu._phase)) then return finish() end
  U.shot(game, DIR .. "/stitchsave_02_saved_in_the_zone.png")
  mashA(10)
  U.wait(30)

  local raw = SaveData.load()
  if not result(type(raw) == "table" and raw.engine == "game3",
    "the slot holds a game3 save") then return finish() end
  result(raw.secretId == secret,
    "the save block carries the secret id (" .. tostring(raw.secretId) .. ")")
  -- pokefirered/src/safari_zone.c:9
  result(raw.safari == nil, "and no safari counters")
  result(raw.flags[tostring(Safari.FLAG_SYS_SAFARI_MODE)] == true
      or raw.flags[Safari.FLAG_SYS_SAFARI_MODE] == true,
    "FLAG_SYS_SAFARI_MODE rides the saved flag store")

  game:_handleBootAction({ action = "continue" })
  U.wait(60)
  -- pokefirered/src/quest_log.c:448 TryStartQuestLogPlayback
  for _ = 1, 400 do
    if game.phase ~= "quest_log" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  result(game.phase ~= "quest_log", "the Continue recap finished, phase=" .. tostring(game.phase))
  U.wait(180)
  for _ = 1, 120 do
    if Space.mapId == CENTER then break end
    U.wait(4)
  end

  local loaded = Runtime.getSession()
  if not result(loaded ~= nil, "Continue reached the field") then return finish() end
  result(loaded.secretId == secret,
    "the secret id came back off the save (" .. tostring(loaded.secretId) .. ")")
  -- pokefirered/src/overworld.c:1695 CB2_ContinueSavedGame
  local Flags = require("src.core.game3.scripting.flags")
  result(Flags.getFlag(loaded, nil, Safari.FLAG_SYS_SAFARI_MODE) == false,
    "raw FLAG_SYS_SAFARI_MODE is clear before anyone asks Safari.isActive")
  result(Flags.getVar(loaded, nil, Safari.VAR_ENTRANCE_SCENE) == 0, "entrance scene var is 0")
  result(Warp._pending == nil, "no warp pending right after Continue")
  result(Safari.isActive(loaded) == false, "ResetSafariZoneFlag_ cleared safari mode")
  result(Safari.balls(loaded) == 0, "no free thirty balls on Continue")
  result(Safari.steps(loaded) == 0, "and no step counter")
  result(Space.mapId == CENTER,
    "still standing where we saved, map=" .. tostring(Space.mapId))
  U.wait(120)
  U.shot(game, DIR .. "/stitchsave_03_after_continue.png")

  local moved = 0
  for _ = 1, 4 do
    if walk("up") then moved = moved + 1 end
  end
  result(moved > 0, "walked " .. moved .. " steps after Continue")
  result(Safari.isActive(loaded) == false, "walking did not re-arm safari mode")
  result(Warp._pending == nil, "and no PA announcement ejected the player")
  result(Space.mapId == CENTER, "map is still " .. tostring(Space.mapId))
  U.wait(60)
  U.shot(game, DIR .. "/stitchsave_04_walked_after_continue.png")

  finish()
end
