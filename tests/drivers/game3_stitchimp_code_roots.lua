local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchimp_code_roots"

local PC2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local MART = "FR_VIRIDIAN_CITY_MART"
local TOWER = "FR_TRAINER_TOWER_1F"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchimp_code_roots")
    love.event.quit(0)
  else
    print("FAIL stitchimp_code_roots failures=" .. failures)
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
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Flags = require("src.core.game3.scripting.flags")

  -- include/constants/flags.h:1375, include/constants/vars.h:139
  local FLAG_SYS_POKEDEX_GET = 0x829
  local VAR_MAP_SCENE_VIRIDIAN_CITY_MART = 0x4057

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(90)
  end

  local function walkTo(x, y)
    for _ = 1, 20 do
      if Player.cellX == x and Player.cellY == y then break end
      if Player.cellX < x then U.hold(game, "right", 20)
      elseif Player.cellX > x then U.hold(game, "left", 20)
      elseif Player.cellY < y then U.hold(game, "down", 20)
      else U.hold(game, "up", 20) end
      U.wait(6)
    end
    return Player.cellX == x and Player.cellY == y
  end

  local function faceAndPress()
    U.hold(game, "up", 20)
    U.wait(10)
    U.tap(game, "a")
    U.wait(40)
  end

  local function pageText()
    return (Message.currentPage() or ""):lower()
  end

  local function clearMessage()
    for _ = 1, 40 do
      if not Message.isOpen() and not (Space.vm and Space.vm:isRunning()) then break end
      U.tap(game, "a")
      U.wait(14)
    end
    U.wait(20)
  end

  -- src/field_control_avatar.c:573
  goTo(PC2F, 8, 5, "up")
  result(walkTo(8, 4), "walked to the wireless monitor at (8,4), got ("
    .. Player.cellX .. "," .. Player.cellY .. ")")
  faceAndPress()
  local wireless = Message.isOpen()
  print("[driver] wireless monitor page: " .. Message.currentPage())
  result(wireless, "the wireless monitor opened a message box")
  -- data/scripts/cable_club.inc:511
  result(pageText():find("undergoing", 1, true) ~= nil,
    "the wireless monitor shows Text_AppearsToBeUndergoingAdjustments")
  U.shot(game, DIR .. "/stitchimp_code_roots_01_wireless_monitor.png")
  clearMessage()

  -- data/maps/ViridianCity_Mart/scripts.inc:7-15
  local ctx = Space.vm and Space.vm.ctx
  Flags.setFlag(Space.store, ctx, FLAG_SYS_POKEDEX_GET, true)
  Flags.setVar(Space.store, ctx, VAR_MAP_SCENE_VIRIDIAN_CITY_MART, 1)

  -- src/field_control_avatar.c:575
  goTo(MART, 1, 5, "up")
  result(Player.cellX == 1 and Player.cellY == 5, "standing under the mart questionnaire")
  faceAndPress()
  print("[driver] questionnaire page: " .. Message.currentPage())
  result(Message.isOpen() and pageText():find("questionnaire", 1, true) ~= nil,
    "the questionnaire asks Text_FillOutQuestionnaire")
  for _ = 1, 30 do
    if Choice.active then break end
    U.tap(game, "a")
    U.wait(12)
  end
  result(Choice.active and Choice.kind == "yesno", "the questionnaire opened its YES/NO box")
  U.shot(game, DIR .. "/stitchimp_code_roots_02_questionnaire.png")
  -- data/scripts/questionnaire.inc:35
  U.tap(game, "b")
  U.wait(30)
  clearMessage()
  result(not (Space.vm and Space.vm:isRunning()), "declining the questionnaire released control")

  -- src/field_control_avatar.c:539
  goTo(TOWER, 16, 7, "up")
  result(walkTo(16, 6), "walked to the Trainer Tower monitor at (16,6), got ("
    .. Player.cellX .. "," .. Player.cellY .. ")")
  faceAndPress()
  print("[driver] trainer tower monitor page: " .. Message.currentPage())
  result(Message.isOpen(), "the Trainer Tower monitor opened a message box")
  -- data/maps/TrainerTower_Lobby/text.inc:82
  result(pageText():find("sec.", 1, true) ~= nil,
    "the Trainer Tower monitor shows TrainerTower_Text_XMinYZSec")
  U.shot(game, DIR .. "/stitchimp_code_roots_03_trainer_tower_time.png")
  clearMessage()

  -- src/field_control_avatar.c:577, data/scripts/cable_club.inc:566-573
  goTo(PC2F, 12, 5, "up")
  result(walkTo(12, 4), "walked to the battle records board at (12,4), got ("
    .. Player.cellX .. "," .. Player.cellY .. ")")
  faceAndPress()
  U.wait(60)
  result(not (Space.vm and Space.vm:isRunning()),
    "the battle records board released control instead of wedging")
  result(not Message.isOpen(), "the battle records board shows no message box")
  clearMessage()
  result(walkTo(12, 5), "the player can still walk after the battle records board")
  local Fade = require("src.ui.game3.fade")
  if (tonumber(Fade.t) or 0) >= 16 and Fade.mode == Fade.MODE.TO_BLACK then
    print("[driver] HANDOFF special ShowBattleRecords (0xC4) is unimplemented, so the "
      .. "fadescreen FADE_TO_BLACK at data/scripts/cable_club.inc:569 is never taken back. "
      .. "Owner: round 2 trainer-tower step 2, scripting/natives_tower.lua.")
  end

  finish()
end
