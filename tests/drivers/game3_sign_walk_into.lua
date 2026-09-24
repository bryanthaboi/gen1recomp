local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_sign_walk_into"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_sign_walk_into")
    love.event.quit(0)
  else
    print("FAIL game3_sign_walk_into failures=" .. failures)
    love.event.quit(1)
  end
end

-- data/maps/PalletTown/map.json:158
local SIGN_X, SIGN_Y = 9, 11

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")
  local MapCatalog = require("src.import.gba.map_catalog")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  local town = MapCatalog.pretToEngine("PalletTown")

  local function placeBelowSign(facing)
    Map.load(nil, game, town, { x = SIGN_X, y = SIGN_Y + 1, facing = facing })
    game.session.x, game.session.y, game.session.facing = SIGN_X, SIGN_Y + 1, facing
    Player.cellX, Player.cellY = SIGN_X, SIGN_Y + 1
    Player.px, Player.py = SIGN_X * 16, (SIGN_Y + 1) * 16
    Player.targetX, Player.targetY = SIGN_X, SIGN_Y + 1
    Player.facing = facing
    U.wait(60)
  end

  local function waitSign(frames)
    for _ = 1, frames do
      if Message.isOpen() and Space.vm:isRunning() then return true end
      U.wait(1)
    end
    return false
  end

  print("[driver] 1. walking into the town sign reads it")
  placeBelowSign("up")
  for _ = 1, 30 do
    table.insert(game.input.pressQueue, "up")
    game.input.state.up = true
    U.wait(1)
    if Message.isOpen() then break end
  end
  game.input.state.up = false
  local opened = waitSign(60)
  result(opened, "holding UP into the sign opened its message")
  result(Player.cellX == SIGN_X and Player.cellY == SIGN_Y + 1, "the player stayed below the sign")
  local ctx = Space.vm and Space.vm.ctx
  result(ctx and ctx.msgBoxIsCancelable == true, "SetWalkingIntoSignVars made the box cancelable")
  local Hud = require("src.ui.game3.hud")
  if opened then
    local armed = false
    for _ = 1, 900 do
      if Hud._waitButton ~= nil and not Message.isTyping() then armed = true break end
      U.wait(1)
    end
    result(armed, "the sign box is fully shown and waiting for A/B")
    result(U.shot(game, DIR .. "/sign_walked_into_waiting.png"), "screenshot sign_walked_into_waiting")
  end

  U.hold(game, "down", 20)
  U.wait(4)
  result(not Message.isOpen(), "pressing DOWN closed the sign")
  result(not Space.vm:isRunning(), "EventScript_CancelMessageBox ended the sign script")
  result(Hud._waitButton == nil, "the cancel dropped the waitbuttonpress wait")
  result(not Hud.busy(), "the field is not held busy after the cancel")
  local walked = false
  for _ = 1, 30 do
    if Player.cellY > SIGN_Y + 1 then walked = true break end
    U.wait(1)
  end
  result(walked or Player.facing == "down", "and the player turned or walked away (y=" .. tostring(Player.cellY) .. ")")
  for _ = 1, 60 do
    if not Player.moving then break end
    U.wait(1)
  end
  local x0, y0 = Player.cellX, Player.cellY
  U.hold(game, "right", 24)
  for _ = 1, 60 do
    if not Player.moving then break end
    U.wait(1)
  end
  result(Player.cellX ~= x0 or Player.cellY ~= y0,
    string.format("the next RIGHT moves the player without an A press (%d,%d -> %d,%d)", x0, y0, Player.cellX, Player.cellY))
  result(U.shot(game, DIR .. "/sign_walked_away_free.png"), "screenshot sign_walked_away_free")

  print("[driver] 2. an A-button read is not cancelable by walking")
  placeBelowSign("up")
  U.tap(game, "a")
  local readA = waitSign(60)
  result(readA, "A opened the sign")
  local ctxA = Space.vm and Space.vm.ctx
  result(not (ctxA and ctxA.msgBoxIsCancelable), "an A read leaves the box non-cancelable")
  U.wait(12)
  U.hold(game, "down", 20)
  result(Message.isOpen(), "DOWN does not close an A-read sign")
  for _ = 1, 200 do
    if not Message.isOpen() and not Space.vm:isRunning() then break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(2)
  end
  result(not Message.isOpen(), "A closes it")

  return finish()
end
