#!/usr/bin/env luajit
-- pokefirered/src/field_control_avatar.c:94 FieldGetPlayerInput

package.path = "./?.lua;./?/init.lua;" .. package.path
local ROM_TEXT = { ["sStartMenuActionTable[3]"] = "{PLAYER}" }
local function romTextKey(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end
local function romTextPlain(key, ctx) return ((ROM_TEXT[key] or key):gsub("{PLAYER}", ctx and ctx.playerName or "")) end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = romTextKey, at = function(n, i, j, ctx) return romTextPlain(romTextKey(n, i, j), ctx) end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
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
  nextElevation = function(_, cur) return cur, nil end,
  isWater = function() return false end,
  isSurfable = function() return false end,
  isGrass = function() return false end,
  tryWarpAt = function() return false end,
  cell = function() return 0 end,
  ledgeLanding = function() return nil end,
  isJumpEast = function() return false end,
  bindMap = function() end,
}

local Player = require("src.core.game3.player")
local Forced = require("src.core.game3.forced_movement")
local Field = require("src.core.game3.field")
local Runtime = require("src.core.game3.runtime")
local StartMenu = require("src.ui.game3.start_menu")

local session = { party = {}, bag = {}, name = "RED", money = 0,
  map = "FR_ROCKET_HIDEOUT_B2F", flags = {}, vars = {} }

local input = {
  _p = {},
  _d = {},
  wasPressed = function(self, key) return self._p[key] == true end,
  isDown = function(self, key) return self._d[key] == true end,
  press = function(self, key) self._p[key] = true end,
  hold = function(self, key) self._d[key] = true end,
  release = function(self) self._p, self._d = {}, {} end,
}
local game = { input = input, session = session, data = {} }

Field._game = game
Field._session = session
Field.running = true
Field.locked = false
Runtime.active = true
Runtime._game = game
Runtime.session = session

Player.cellX, Player.cellY = 4, 4
Player.px, Player.py = 4 * 16, 4 * 16
Player.targetX, Player.targetY = 4, 4
Player.facing = "left"
Player.moving = false

local function frame(pressStart, holdDir)
  input:release()
  if pressStart then input:press("start") end
  if holdDir then input:hold(holdDir) end
  local forcedBefore = Forced.isForced()
  Runtime.update(1 / 60)
  return forcedBefore
end

print("[test] 1. walking onto the spin tile takes the player over")
check(Forced.isForced() == false, "the forced flag is clear before the first frame")
local walkedOn = false
for _ = 1, 120 do
  frame(false, "left")
  if Forced.isForced() then walkedOn = true break end
end
check(walkedOn, "the walk west onto MB_SPIN_LEFT started a forced run")
check(Forced.isForced() == true, "PLAYER_AVATAR_FLAG_FORCED is set by the step callback")
check(StartMenu.isOpen() == false, "nothing opened the menu yet")

print("[test] 2. START is dropped on the frame the forced run ends")
local endedOn, openedDuringRun = nil, false
for i = 2, 480 do
  local forcedBefore = frame(true)
  if StartMenu.isOpen() and forcedBefore then openedDuringRun = true end
  if forcedBefore and not Forced.isForced() then
    endedOn = i
    break
  end
end
check(endedOn ~= nil, "the forced run ended on frame " .. tostring(endedOn))
check(openedDuringRun == false, "no frame of the run let START through")
check(Forced.isForced() == false, "the forced flag is clear once the run ends")
check(Player.moving == false, "and the avatar is standing still")
-- pokefirered/src/field_control_avatar.c:108
check(StartMenu.isOpen() == false,
  "the press sampled before the avatar update still saw the forced flag")

print("[test] 3. the next frame's press opens it")
frame(true)
check(StartMenu.isOpen() == true, "START opens the start menu on the following frame")
StartMenu.close()

print("[test] 4. an ordinary idle frame is unaffected")
frame(true)
check(StartMenu.isOpen() == true, "START still opens the menu from a standing start")
StartMenu.close()
Field.locked = true
frame(true)
check(StartMenu.isOpen() == false, "a locked field still gates it")
Field.locked = false

done()
