#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

require("src.core.GameVersion").set("firered")

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
_G.love = { graphics = gfx }

package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playSong = function() end,
  playFanfare = function() end,
  stopAll = function() end,
  waitSe = function(_, cb) if cb then cb() end end,
}

-- pokefirered/include/constants/metatile_behaviors.h:17
local MB_SPIN_LEFT = 0x55
local MB_STOP_SPINNING = 0x58

local behaviors = {
  ["4,4"] = 0x00,
  ["3,4"] = MB_SPIN_LEFT,
  ["2,4"] = 0x00,
  ["1,4"] = MB_STOP_SPINNING,
}

package.loaded["src.core.game3.collision"] = {
  _mapId = "FR_ROCKET_HIDEOUT_B2F",
  behavior = function(cx, cy) return behaviors[cx .. "," .. cy] end,
  behaviorOn = function(cx, cy) return behaviors[cx .. "," .. cy] end,
  canEnter = function(_, cx, cy) return behaviors[cx .. "," .. cy] ~= nil end,
  isWater = function() return false end,
  isSurfable = function() return false end,
  isGrass = function() return false end,
  tryWarpAt = function() return false end,
  cell = function() return 0 end,
}

local Player = require("src.core.game3.player")
local Forced = require("src.core.game3.forced_movement")
local Hud = require("src.ui.game3.hud")
local StartMenu = require("src.ui.game3.start_menu")

local session = { party = {}, bag = {}, name = "RED", money = 0 }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  uiBusy = function() return false end,
}

local input = {
  _p = {},
  wasPressed = function(self, key) return self._p[key] == true end,
  isDown = function() return false end,
  press = function(self, key) self._p = { [key] = true } end,
  release = function(self) self._p = {} end,
}
local game = { input = input, session = session }

local function pressStart()
  input:press("start")
  Hud.update(game, 1 / 60)
  input:release()
end

local function stand(cx, cy, facing)
  Player.cellX, Player.cellY = cx, cy
  Player.px, Player.py = cx * 16, cy * 16
  Player.targetX, Player.targetY = cx, cy
  Player.facing = facing or "left"
end

print("[test] 1. START is gated while the spinner owns the player (field_control_avatar.c:108)")
stand(3, 4, "left")
check(Forced.isForced() == false, "the forced flag is clear before the step callback runs")
check(Forced.onStepFinished(game) == true, "MB_SPIN_LEFT takes the player over")
check(Forced.isForced() == true, "PLAYER_AVATAR_FLAG_FORCED is set")
check(Player.moving == true, "the forced step is in flight")
pressStart()
check(StartMenu.isOpen() == false, "START does not open the menu mid-spin")

print("[test] 2. the whole spin run holds the menu shut, frame by frame")
local openedMidSpin, forcedFrames = false, 0
for _ = 1, 480 do
  if not (Player.moving or Forced.isForced()) then break end
  Player.tick(game)
  if Forced.isForced() then
    forcedFrames = forcedFrames + 1
    pressStart()
    if StartMenu.isOpen() then openedMidSpin = true end
  end
end
check(forcedFrames > 1, "the run spanned " .. forcedFrames .. " forced frames")
check(openedMidSpin == false, "no frame of the forced run let the menu through")
check(Player.moving == false, "the run ended")
check(Player.cellX == 1 and Player.cellY == 4,
  string.format("MB_STOP_SPINNING ended the run at (1,4), got (%s,%s)",
    tostring(Player.cellX), tostring(Player.cellY)))

print("[test] 3. the stop tile clears the flag and START works again")
check(Forced.isForced() == false, "the forced flag is cleared on the stop tile")
check(StartMenu.isOpen() == false, "the menu is still shut when the run ends")
pressStart()
check(StartMenu.isOpen() == true, "START opens the menu once the player is free")
StartMenu.close()

print("[test] 4. Field.locked still gates START on its own")
local Field = require("src.core.game3.field")
Field.locked = true
pressStart()
check(StartMenu.isOpen() == false, "a locked field keeps the menu shut")
Field.locked = false
pressStart()
check(StartMenu.isOpen() == true, "unlocking the field lets START through again")
StartMenu.close()

if failed > 0 then
  print(string.format("\n[test] FAILED %d", failed))
  os.exit(1)
end
print("\n[test] all passed")
