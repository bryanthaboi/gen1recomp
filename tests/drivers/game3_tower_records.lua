local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_tower_records"

local LOBBY = "FR_TRAINER_TOWER_LOBBY"
local FLOOR_1F = "FR_TRAINER_TOWER_1F"
local ROOF = "FR_TRAINER_TOWER_ROOF"

-- pokefirered/include/constants/metatile_behaviors.h:126
local MB_TRAINER_TOWER_MONITOR = 0xA3

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS tower_records")
    love.event.quit(0)
  else
    print("FAIL tower_records failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Collision = require("src.core.game3.collision")
  local Choice = require("src.ui.game3.choice")
  local Message = require("src.ui.game3.message")
  local Fade = require("src.ui.game3.fade")
  local Bag = require("src.core.game3.bag")
  local Tower = require("src.core.game3.trainer_tower")
  local Screen = require("src.ui.game3.trainer_tower_records")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  local function vmRunning() return (Space.vm and Space.vm:isRunning()) and true or false end
  local function messageOpen() return (Message.isOpen and Message.isOpen()) and true or false end

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

  local function mashUntil(cond, tries)
    for _ = 1, (tries or 80) do
      if cond() then return true end
      if messageOpen() or Choice.isOpen() then U.tap(game, "a") end
      U.wait(6)
    end
    return cond()
  end

  local function fadeState()
    return string.format("Fade.t=%s active=%s mode=%s", tostring(Fade.t),
      tostring(Fade.isActive()), tostring(Fade.mode))
  end

  Party.giveMon(session, 1, 20)

  goTo(LOBBY, 9, 12, "up")
  result(session.map == LOBBY, "the player is in the Trainer Tower lobby")

  for _ = 1, 8 do
    if Player.cellY <= 7 or vmRunning() then break end
    U.hold(game, "up", 20)
    U.wait(8)
  end
  result(mashUntil(function() return Choice.isOpen() end, 60),
    "the receptionist asked whether to challenge the trainers")
  U.tap(game, "a")
  U.wait(30)
  result(mashUntil(function() return Choice.isOpen() end, 60), "the challenge mode list opened")
  U.tap(game, "a")
  for _ = 1, 40 do
    if not messageOpen() and not vmRunning() then break end
    if messageOpen() then U.tap(game, "a") end
    U.wait(8)
  end
  result(Tower.getChallengeId(session) == Tower.CHALLENGE_TYPE.SINGLE,
    "a SINGLE challenge is running")
  result(Tower.isTimerRunning(session), "the challenge clock started")
  U.wait(120)

  place(8, 11, "up")
  U.wait(20)
  local clockBefore = Tower.record(session).timer
  U.tap(game, "a")
  local opened = false
  for _ = 1, 120 do
    if Screen.isOpen() then opened = true break end
    U.wait(4)
  end
  result(opened, "the lobby records board opened on A")
  if not opened then
    print("[driver] " .. fadeState() .. " vm=" .. tostring(vmRunning()))
    U.shot(game, DIR .. "/tower_records_00_no_board.png")
    return
  end
  result(Screen.kind() == "tower", "TrainerTower_Lobby_EventScript_ShowRecords set VAR_0x8004 = 1")
  for _ = 1, 60 do
    if not Fade.isActive() then break end
    U.wait(2)
  end
  print("[driver] board up: " .. fadeState())
  result((tonumber(Fade.t) or 0) == 0,
    "the board took the script's FADE_TO_BLACK back instead of leaving a black screen")
  local rows = Screen.rows()
  local labels = {}
  for i, row in ipairs(rows) do labels[i] = tostring(row.label) end
  print("[driver] rows = " .. table.concat(labels, "/") .. "  first time = "
    .. tostring(rows[1] and rows[1].time))
  result(#rows == 4 and table.concat(labels, "/") == "SINGLE/DOUBLE/KNOCKOUT/MIXED",
    "the board lists the four challenge types")
  U.wait(60)
  local clockDuring = Tower.record(session).timer
  print(string.format("[driver] clock %s -> %s behind the board", tostring(clockBefore),
    tostring(clockDuring)))
  result(clockDuring > clockBefore,
    "the challenge clock keeps running behind the board (pokefirered/src/main.c:390)")
  U.shot(game, DIR .. "/tower_records_01_board.png")

  U.tap(game, "a")
  local closed = false
  for _ = 1, 120 do
    if not Screen.isOpen() then closed = true break end
    U.wait(4)
  end
  result(closed, "A closed the board")
  for _ = 1, 90 do
    if not Fade.isActive() and not vmRunning() then break end
    U.wait(2)
  end
  print("[driver] after close: " .. fadeState() .. " vm=" .. tostring(vmRunning()))
  result((tonumber(Fade.t) or 0) == 0, "the lobby is lit again, not the stitch round's black screen")
  result(not vmRunning(), "waitstate released and the script ran releaseall")
  U.shot(game, DIR .. "/tower_records_02_lobby_lit.png")

  -- pokefirered/src/field_control_avatar.c:538 TrainerTower_EventScript_ShowTime
  goTo(FLOOR_1F, 10, 14, "up")
  U.wait(40)
  local mx, my
  for y = 0, 31 do
    for x = 0, 31 do
      if Collision.behavior(x, y) == MB_TRAINER_TOWER_MONITOR then
        mx, my = x, y
        break
      end
    end
    if mx then break end
  end
  print("[driver] trainer tower monitor at " .. tostring(mx) .. "," .. tostring(my))
  if result(mx ~= nil, "1F carries the 0xA3 Trainer Tower monitor tile") then
    place(mx, my + 1, "up")
    U.wait(20)
    U.tap(game, "a")
    local showed = mashUntil(function() return messageOpen() end, 60)
    result(showed, "the monitor ran ttower_gettime and opened the clock message")
    if showed then
      U.wait(45)
      U.shot(game, DIR .. "/tower_records_03_floor_clock.png")
      for _ = 1, 40 do
        if not messageOpen() and not vmRunning() then break end
        U.tap(game, "a")
        U.wait(8)
      end
    end
  end

  -- pokefirered/data/scripts/trainer_tower.inc:265 TrainerTower_EventScript_SpeakToOwner
  goTo(ROOF, 9, 8, "up")
  result(session.map == ROOF, "the player reached the roof")
  U.wait(40)
  local runTime = Tower.record(session).timer
  U.tap(game, "a")
  local spoke = mashUntil(function() return messageOpen() or vmRunning() end, 60)
  result(spoke, "the tower owner answered")
  U.wait(60)
  U.shot(game, DIR .. "/tower_records_04_roof_owner.png")
  local prize = Tower.prizeItem(session, Tower.CHALLENGE_TYPE.SINGLE)
  local shotPrize = false
  for _ = 1, 200 do
    if not shotPrize and messageOpen() and Bag.has(session.bag, prize, 1) then
      shotPrize = true
      -- pokefirered/data/scripts/trainer_tower.inc:287 Text_ObtainedTheX
      for _ = 1, 4 do
        U.tap(game, "a")
        U.wait(30)
      end
      U.wait(120)
      U.shot(game, DIR .. "/tower_records_05_prize.png")
    end
    if not messageOpen() and not vmRunning() then break end
    U.tap(game, "a")
    U.wait(6)
  end
  result(shotPrize, "the prize message was on screen while the item was in the bag")
  local rec = Tower.record(session)
  print(string.format("[driver] prize item %s held=%s spokeToOwner=%s prize=%s"
    .. " checkedFinalTime=%s best=%s runTime=%s", tostring(prize),
    tostring(Bag.has(session.bag, prize, 1)), tostring(rec.spokeToOwner),
    tostring(rec.receivedPrize), tostring(rec.checkedFinalTime), tostring(rec.bestTime),
    tostring(runTime)))
  result(rec.spokeToOwner, "GetOwnerState marked the owner spoken to")
  result(rec.receivedPrize and Bag.has(session.bag, prize, 1),
    "the roof owner handed the SINGLE prize over and it is in the bag")
  result(rec.checkedFinalTime and rec.bestTime < Tower.MAX_TIME,
    "CheckFinalTime took the new record branch")
  result(rec.bestTime >= runTime, "and the record is this run's clock")
  result(not Tower.isTimerRunning(session), "the clock stopped when the owner was reached")

  goTo(LOBBY, 8, 11, "up")
  U.wait(40)
  U.tap(game, "a")
  local reopened = false
  for _ = 1, 120 do
    if Screen.isOpen() then reopened = true break end
    U.wait(4)
  end
  result(reopened, "the board opened again after the run")
  if reopened then
    for _ = 1, 60 do
      if not Fade.isActive() then break end
      U.wait(2)
    end
    rows = Screen.rows()
    print("[driver] SINGLE row now reads " .. tostring(rows[1] and rows[1].time)
      .. ", DOUBLE row " .. tostring(rows[2] and rows[2].time))
    result(rows[1] and rows[1].time ~= "59MIN. 59.99SEC.",
      "the SINGLE row shows the record the run just set")
    result(rows[2] and rows[2].time == "59MIN. 59.99SEC.",
      "and the modes that were never played still show the ceiling")
    U.shot(game, DIR .. "/tower_records_06_new_record.png")
    U.tap(game, "a")
    for _ = 1, 120 do
      if not Screen.isOpen() then break end
      U.wait(4)
    end
    for _ = 1, 90 do
      if not Fade.isActive() then break end
      U.wait(2)
    end
    result(not Screen.isOpen() and (tonumber(Fade.t) or 0) == 0,
      "and it closed back to a lit lobby")
  end
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    print("FAIL tower_records driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
