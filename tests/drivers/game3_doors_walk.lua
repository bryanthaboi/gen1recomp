local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_doors_walk"

local VIRIDIAN = "FR_VIRIDIAN_CITY"
local SAFFRON = "FR_SAFFRON_CITY"

local TARGETS = {
  { label = "viridian_gym", map = VIRIDIAN, x = 36, y = 10, tile = "SlidingDouble", sound = "sliding" },
  { label = "pokecenter", map = VIRIDIAN, x = 26, y = 26, tile = "SlidingSingle", sound = "sliding" },
  { label = "mart", map = VIRIDIAN, x = 36, y = 19, tile = "SlidingSingle", sound = "sliding" },
  { label = "wooden_house", map = VIRIDIAN, x = 25, y = 11, tile = "Viridian", sound = "normal" },
  { label = "silph_co", map = SAFFRON, x = 33, y = 30, tile = "SilphCo", sound = "sliding" },
}

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS doors_walk")
    love.event.quit(0)
  else
    print("FAIL doors_walk failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Doors = require("src.core.game3.doors")
  local Warp = require("src.core.game3.warp")
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local lastSe = nil
  local realPlaySe = Audio.playSe
  Audio.playSe = function(id, ...)
    lastSe = id
    return realPlaySe(id, ...)
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(60)
  end

  local shot = 0
  for _, t in ipairs(TARGETS) do
    for _ = 1, 240 do
      if not Warp.isBusy() then break end
      U.wait(1)
    end
    Doors.reset()
    goTo(t.map, t.x, t.y + 1, "up")

    local entry = Doors.getDoorEntryAt(t.map, t.x, t.y)
    result(entry ~= nil and entry.tile == t.tile,
      string.format("%s door metatile is %s, got %s", t.label, t.tile,
        tostring(entry and entry.tile)))
    result(entry ~= nil and entry.sound == t.sound,
      string.format("%s door sound type is %s, got %s", t.label, t.sound,
        tostring(entry and entry.sound)))

    local Collision = require("src.core.game3.collision")
    print(string.format("[driver] %s standing (%d,%d) doorWarp=%s", t.label,
      Player.cellX, Player.cellY, tostring(Collision.isDoorWarp(game, t.x, t.y) ~= nil)))

    lastSe = nil
    U.hold(game, "up", 3)

    local anim = nil
    for _ = 1, 120 do
      anim = Doors.getActiveAnim(nil, t.x, t.y)
      if anim and anim.frame >= 1 then break end
      U.wait(1)
    end
    result(anim ~= nil, t.label .. " door animation started")
    if anim then
      print(string.format("[driver] %s anim tile=%s size=%s frame=%d mode=%s",
        t.label, tostring(anim.tile), tostring(anim.size), anim.frame, tostring(anim.mode)))
      result(anim.tile == t.tile, t.label .. " animates the " .. t.tile .. " sheet")
    end

    local wantSe = (t.sound == "sliding") and SE.SE_SLIDING_DOOR or SE.SE_DOOR
    result(lastSe == wantSe, string.format("%s played SE %s, got %s", t.label,
      tostring(wantSe), tostring(lastSe)))

    shot = shot + 1
    U.shot(game, string.format("%s/doors_walk_%02d_%s.png", DIR, shot, t.label))

    for _ = 1, 400 do
      if not Warp.isBusy() then break end
      U.wait(1)
    end

    local Message = package.loaded["src.ui.game3.message"]
    local Space = require("src.core.game3.scripting.space")
    for _ = 1, 90 do
      local open = Message and Message.isOpen and Message.isOpen()
      local running = Space.vm and Space.vm:isRunning()
      if not open and not running then break end
      if open then U.tap(game, "a") end
      U.wait(10)
    end
    local Field = require("src.core.game3.field")
    if Field.unlock then Field.unlock() end
    U.wait(20)
    print("[driver] " .. t.label .. " ended on " .. tostring(Runtime.getSession() and Runtime.getSession().map))
  end

  -- src/field_door.c:510
  goTo(SAFFRON, 40, 13, "up")
  local dojo = Doors.getDoorEntryAt(SAFFRON, 40, 12)
  result(dojo == nil, "the Saffron Dojo doorway has no door table entry")

  Audio.playSe = realPlaySe
  finish()
end
