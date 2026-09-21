local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_tower_lobby"

local LOBBY = "FR_TRAINER_TOWER_LOBBY"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS tower_lobby")
    love.event.quit(0)
  else
    print("FAIL tower_lobby failures=" .. failures)
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
  local Choice = require("src.ui.game3.choice")
  local Tower = require("src.core.game3.trainer_tower")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

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

  local function messageOpen()
    local Message = package.loaded["src.ui.game3.message"]
    return (Message and Message.isOpen and Message.isOpen()) and true or false
  end

  local function vmRunning()
    return (Space.vm and Space.vm:isRunning()) and true or false
  end

  local function mashUntilChoice(limit)
    for _ = 1, (limit or 80) do
      if Choice.isOpen() then return true end
      if messageOpen() then U.tap(game, "a") end
      U.wait(10)
      if not messageOpen() and not vmRunning() and not Choice.isOpen() then return false end
    end
    return Choice.isOpen()
  end

  goTo(LOBBY, 9, 12, "up")
  result(session.map == LOBBY, "the player is in the Trainer Tower lobby, map=" .. tostring(session.map))
  U.shot(game, DIR .. "/tower_01_lobby.png")

  for _ = 1, 8 do
    if Player.cellY <= 7 or vmRunning() then break end
    U.hold(game, "up", 20)
    U.wait(8)
  end
  print(string.format("[driver] player at (%d,%d), vm=%s", Player.cellX, Player.cellY,
    tostring(vmRunning())))
  result(vmRunning() or messageOpen() or Choice.isOpen(),
    "stepping onto the lobby counter trigger started the entry script")

  local sawYesNo = mashUntilChoice(80)
  result(sawYesNo, "the receptionist asked whether to challenge the trainers")
  if not sawYesNo then
    print("[driver] the entry script stalled before the yes/no box")
    return finish()
  end
  U.tap(game, "a")
  U.wait(30)

  local sawModes = mashUntilChoice(80)
  result(sawModes, "the challenge mode list opened")
  if sawModes then
    print("[driver] mode list options=" .. tostring(Choice.options and #Choice.options))
    result(Choice.options ~= nil and #Choice.options == 5,
      "the mode list has SINGLE / DOUBLE / KNOCKOUT / MIXED / EXIT")
    U.shot(game, DIR .. "/tower_02_mode_choice.png")
    U.tap(game, "a")
    U.wait(30)
  end

  for _ = 1, 60 do
    if not messageOpen() and not vmRunning() then break end
    if messageOpen() then U.tap(game, "a") end
    U.wait(10)
  end

  local state = Tower.state(session)
  print(string.format("[driver] mode=%s timerRunning=%s timer=%s",
    tostring(state.challengeId), tostring(state.timerRunning),
    tostring(Tower.record(session).timer)))
  result(state.challengeId == Tower.CHALLENGE_TYPE.SINGLE,
    "StartTrainerTowerChallenge recorded the SINGLE challenge")
  result(Tower.isTimerRunning(session), "the challenge clock is running")
  local before = Tower.record(session).timer
  U.wait(60)
  local after = Tower.record(session).timer
  print(string.format("[driver] clock %s -> %s", tostring(before), tostring(after)))
  result(after > before, "the challenge clock advances with the field")
  U.shot(game, DIR .. "/tower_03_challenge_started.png")

  place(12, 7, "left")
  U.wait(20)
  U.tap(game, "a")
  U.wait(30)
  local sawReceptionist = messageOpen() or vmRunning()
  result(sawReceptionist, "the receptionist answered instead of a dead script")
  if sawReceptionist then U.shot(game, DIR .. "/tower_04_receptionist.png") end
  for _ = 1, 30 do
    if not messageOpen() and not vmRunning() then break end
    if messageOpen() then U.tap(game, "a") end
    U.wait(10)
  end

  return finish()
end
