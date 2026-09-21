local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ops_moncry"

local HOUSE = "FR_PEWTER_CITY_HOUSE1"
-- pokefirered/include/constants/species.h:36
local SPECIES_NIDORAN_M = 32

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS ops_moncry")
    love.event.quit(0)
  else
    print("FAIL ops_moncry failures=" .. failures)
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
  local Audio = require("src.core.game3.audio")
  local Message = require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function goTo(x, y, facing)
    Map.load(nil, game, HOUSE, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(90)
  end

  local function step(dir)
    local bx, by = Player.cellX, Player.cellY
    for _ = 1, 4 do
      U.hold(game, dir, 8)
      if Player.cellX ~= bx or Player.cellY ~= by then
        while Player.moving do U.wait(1) end
        return true
      end
    end
    return false
  end

  local function parkedOnWaitMonCry()
    local vm = Space.vm
    if not (vm and vm:isRunning()) then return false end
    local ctx = vm.ctx
    if ctx.status ~= "waiting" then return false end
    local pc = ctx.pc
    local rows = pc and vm.scripts and vm.scripts[pc.listKey]
    local row = rows and rows[(pc.index or 1) - 1]
    return row ~= nil and row.op == "waitmoncry"
  end

  goTo(4, 6, "up")
  result(Runtime.getSession().map == HOUSE, "entered the Pewter City Nidoran house")

  local walked = 0
  while Player.cellY > 2 do
    if not step("up") then break end
    walked = walked + 1
  end
  while Player.cellX < 6 do
    if not step("right") then break end
    walked = walked + 1
  end
  print("[driver] walked " .. walked .. " steps to (" .. Player.cellX .. "," .. Player.cellY .. ")")
  result(Player.cellX == 6 and Player.cellY == 2,
    "standing above the Nidoran at (" .. Player.cellX .. "," .. Player.cellY .. ")")
  U.hold(game, "down", 10)
  U.wait(10)
  U.shot(game, DIR .. "/ops_moncry_01_before_talk.png")

  Audio.stopCry()
  Audio._cryParams = nil

  -- pokefirered/data/maps/PewterCity_House1/scripts.inc:27
  U.tap(game, "a")
  local cryFrame = 0
  local sawPark, parkFrames, shot2 = false, 0, false
  for i = 1, 600 do
    U.wait(1)
    if cryFrame == 0 and Audio._cryParams ~= nil then cryFrame = i end
    local boxOpen = Message.isOpen and Message.isOpen()
    if not shot2 and boxOpen and cryFrame > 0 and not Audio.isCryFinished() then
      shot2 = true
      U.shot(game, DIR .. "/ops_moncry_02_cry_with_text.png")
    end
    if parkedOnWaitMonCry() then
      sawPark = true
      parkFrames = parkFrames + 1
    end
    if boxOpen and shot2 and i % 20 == 0 then
      U.tap(game, "a")
    end
    if cryFrame > 0 and not (Space.vm and Space.vm:isRunning()) then break end
  end

  result(cryFrame > 0, "playmoncry fired during the Nidoran script, frame " .. cryFrame)
  result(Audio._cryParams and Audio._cryParams.mode == 0,
    "the cry played in CRY_MODE_NORMAL, mode="
      .. tostring(Audio._cryParams and Audio._cryParams.mode))

  local cryIds = Audio._pack and Audio._pack.index and Audio._pack.index.cryIds
  local wantIndex = cryIds and (cryIds[SPECIES_NIDORAN_M] or cryIds[tostring(SPECIES_NIDORAN_M)])
  print("[driver] cry index wanted=" .. tostring(wantIndex)
    .. " got=" .. tostring(Audio._crySlot and Audio._crySlot.info and Audio._crySlot.info.cryIndex))
  result(wantIndex == nil or (Audio._crySlot and Audio._crySlot.info
    and Audio._crySlot.info.cryIndex == wantIndex),
    "the NIDORAN_M sample is the one that played")

  result(sawPark, "waitmoncry parked the script for " .. parkFrames .. " frames")
  result(not (Space.vm and Space.vm:isRunning()), "the script released after the cry finished")
  result(Audio.isCryFinished(), "the cry had finished by the time the script released")

  local walkedAway = step("left")
  result(walkedAway and Player.cellX < 6,
    "control came back to the player, now at ("
      .. Player.cellX .. "," .. Player.cellY .. ")")
  U.shot(game, DIR .. "/ops_moncry_03_walked_away.png")

  finish()
end
