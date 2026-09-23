#!/usr/bin/env luajit
-- pokefirered/src/scrcmd.c:719
-- pokefirered/src/field_fadetransition.c:535

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

local MB_WARP_DOOR, MB_CAVE_DOOR, MB_NORMAL = 0x69, 0x60, 0x00

local sounds, musicFades, loads = {}, {}, {}
local Audio = {
  playSe = function(id) sounds[#sounds + 1] = id end,
  fadeOutBgm = function(speed) musicFades[#musicFades + 1] = speed end,
}
package.loaded["src.core.game3.audio"] = Audio

local Player = {
  facing = "up", cellX = 6, cellY = 6, visible = true, spriteYOffset = 0, steps = {},
}
function Player.setVisible(v) Player.visible = v and true or false end
function Player.forceStep(dir, cb)
  Player.facing = dir
  Player.steps[#Player.steps + 1] = { dir = dir, cb = cb, left = 16 }
  return true
end
package.loaded["src.core.game3.player"] = Player

local Fade = require("src.ui.game3.fade")
local Map = { current = "A" }
function Map.load(_, _, id, opts)
  loads[#loads + 1] = { id = id, x = opts.x, y = opts.y, facing = opts.facing,
    fadeT = Fade.t, fadeActive = Fade.active, visible = Player.visible,
    parked = package.loaded["src.core.game3.field"]._fieldCallback }
  Map.current = id
  Player.cellX, Player.cellY = opts.x, opts.y
  Player.facing = opts.facing
end
package.loaded["src.core.game3.map"] = Map

package.loaded["src.ui.game3.map_preview_screen"] = {
  has = function() return false end,
  isForestActive = function() return false end,
  dismiss = function() end,
}
package.loaded["src.import.gba.map_preview_extract"] = { TYPE_CAVE = 1 }

local doorCalls = {}
local Doors = {}
function Doors.open(mapId, x, y, _, cb)
  doorCalls[#doorCalls + 1] = { "open", mapId, x, y }
  if cb then cb() end
end
function Doors.close(mapId, x, y, _, cb)
  doorCalls[#doorCalls + 1] = { "close", mapId, x, y }
  if cb then cb() end
end
function Doors.holdOpen(mapId, x, y)
  doorCalls[#doorCalls + 1] = { "hold", mapId, x, y }
end
function Doors.closeAfterDelay(mapId, x, y, _, _, cb)
  doorCalls[#doorCalls + 1] = { "close", mapId, x, y }
  if cb then cb() end
end
function Doors.getSoundForWarp() return 0 end
Doors.SOUND_EXIT = require("src.core.game3.se_ids").SE_EXIT
function Doors.reset() end
package.loaded["src.core.game3.doors"] = Doors

local Flags = require("src.core.game3.scripting.flags")
package.loaded["src.core.game3.scripting.space"] = { store = Flags.newStore() }
local Field = { _fieldCallback = false, locked = false }
function Field.lock() Field.locked = true end
function Field.unlock() Field.locked = false end
package.loaded["src.core.game3.field"] = Field

local Collision = require("src.core.game3.collision")
local destBehavior = MB_NORMAL
Collision.behavior = function() return destBehavior end

local Task = require("src.core.game3.task")
local SE = require("src.core.game3.se_ids")
local Warp = require("src.core.game3.warp")

local game = { data = { maps = {
  A = { mapType = 3, regionMapSectionId = 1, music = 100 },
  B = { mapType = 8, regionMapSectionId = 1, music = 200 },
  C = { mapType = 3, regionMapSectionId = 1, music = 100 },
} } }

local function frame()
  Fade.tick(1 / 60)
  Task.update(1 / 60)
  for i = #Player.steps, 1, -1 do
    local s = Player.steps[i]
    s.left = s.left - 1
    if s.left <= 0 then
      table.remove(Player.steps, i)
      if s.cb then s.cb() end
    end
  end
end

local function reset(from)
  sounds, musicFades, loads, doorCalls = {}, {}, {}, {}
  Fade.clear()
  Task.clear()
  Warp.clear()
  Map.current = from or "A"
  Player.steps = {}
  Player.visible = true
  Player.facing = "up"
  destBehavior = MB_NORMAL
  Audio._currentSong = { id = 100 }
  Audio._fadeOut = nil
end

local function has(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

local function run(kind, dest, maxFrames)
  local done, doneAt, frames = false, nil, 0
  local fadeAtDone
  local peak = Fade.t or 0
  Warp.scripted(nil, game, kind, dest, 6, 6, "up", function()
    done = true
    doneAt = frames
    fadeAtDone = { t = Fade.t, active = Fade.active, parked = Field._fieldCallback }
  end)
  local startMode, startActive = Fade.mode, Fade.active
  while not done and frames < (maxFrames or 400) do
    frames = frames + 1
    frame()
    if (Fade.t or 0) > peak then peak = Fade.t end
  end
  return { done = done, doneAt = doneAt, fadeAtDone = fadeAtDone, peak = peak,
    startMode = startMode, startActive = startActive }
end

print("[test] 1. warp fades to black with SE_EXIT, swaps the map under black, fades back in")
reset()
local r = run("warp", "B")
check(r.startActive and r.startMode == Fade.MODE.TO_BLACK, "a FADE_TO_BLACK starts on the warp frame")
check(has(sounds, SE.SE_EXIT), "SE_EXIT plays")
check(#musicFades == 1 and musicFades[1] == 2, "the old map music fades at the indoor speed 2")
check(#loads == 1 and loads[1].fadeT == 16 and not loads[1].fadeActive,
  "the map loads only once the screen is fully black (t=" .. tostring(loads[1] and loads[1].fadeT) .. ")")
check(r.done and r.fadeAtDone.t == 0 and not r.fadeAtDone.active,
  "done fires only after the fade-in finishes")
check(r.doneAt and r.doneAt >= 32, "the whole transition takes the fade out + in (frames=" .. tostring(r.doneAt) .. ")")
check(Warp.isBusy() == false, "Warp is released")
check(loads[1] and loads[1].parked == true and r.fadeAtDone.parked == false,
  "ON_FRAME stays parked from the load until the fade-in ends")

print("[test] 2. warpsilent fades without SE_EXIT; same song keeps playing")
reset()
r = run("warpsilent", "C")
check(not has(sounds, SE.SE_EXIT), "no SE_EXIT")
check(#musicFades == 0, "same map song is not faded")
check(#loads == 1 and loads[1].fadeT == 16, "load under black")
check(r.done and r.fadeAtDone.t == 0, "fade-in done before done()")

print("[test] 3. FLAG_DONT_TRANSITION_MUSIC keeps the music")
reset()
local Space = package.loaded["src.core.game3.scripting.space"]
Flags.setFlag(Space.store, nil, "FLAG_DONT_TRANSITION_MUSIC", true)
r = run("warp", "B")
check(#musicFades == 0, "no music fade with the flag set")
Flags.setFlag(Space.store, nil, "FLAG_DONT_TRANSITION_MUSIC", false)

print("[test] 4. a covered screen is not faded out again")
reset()
Fade.t = 16
Fade.mode = Fade.MODE.TO_BLACK
Fade.active = false
r = run("seagallop", "C")
check(#loads == 1 and loads[1].fadeT == 16, "loaded under the existing black")
check(r.peak == 16 and r.done and r.fadeAtDone.t == 0, "faded in once")
check(not has(sounds, SE.SE_EXIT), "the ferry kind leaves SE_EXIT to the ferry")

print("[test] 5. a door destination runs the exit-door step")
reset()
destBehavior = MB_WARP_DOOR
r = run("warp", "C")
check(r.done, "done fired")
local opened, closed = false, false
for _, c in ipairs(doorCalls) do
  if c[1] == "open" and c[2] == "C" and c[3] == 6 and c[4] == 6 then opened = true end
  if c[1] == "close" and c[2] == "C" then closed = true end
end
check(opened and closed, "the destination door opened and closed")
check(Player.facing == "down" and Player.visible, "the player stepped out facing down")
check(r.fadeAtDone and r.fadeAtDone.t == 0, "the slow fade-in finished first")

print("[test] 6. a non-animated door destination steps the player out after the fade")
reset()
destBehavior = MB_CAVE_DOOR
r = run("warp", "C")
check(r.done and Player.visible and #Player.steps == 0, "stepped out and done")

print("[test] 7. warpspinenter loads at once and spins the player in with SE_WARP_OUT")
reset()
Player.facing = "right"
local doneFlag = false
Warp.scripted(nil, game, "warpspinenter", "C", 6, 6, nil, function() doneFlag = true end)
check(#loads == 1, "no fade-out before the load")
check(Fade.mode == Fade.MODE.FROM_BLACK and Fade.active, "fades in from black")
check(has(sounds, SE.SE_WARP_OUT), "SE_WARP_OUT plays")
check(Player.spriteYOffset < 0, "the player starts above the screen")
for _ = 1, 200 do
  if doneFlag then break end
  frame()
end
check(doneFlag and Player.spriteYOffset == 0 and Player.facing == "right",
  "landed facing the saved direction (" .. tostring(Player.facing) .. ")")

print("[test] 8. warpteleport spins out with SE_WARP_IN before fading")
reset()
local tDone = false
Warp.scripted(nil, game, "warpteleport", "C", 6, 6, nil, function() tDone = true end)
check(has(sounds, SE.SE_WARP_IN), "SE_WARP_IN plays")
check(not Fade.active, "no fade while the player rises")
for _ = 1, 400 do
  if tDone then break end
  frame()
end
check(tDone and #loads == 1 and loads[1].fadeT == 16, "loaded under black after the spin-out")

print("[test] 10. the music check compares with the song actually playing")
reset()
Audio._currentSong = { id = 305 }
r = run("warp", "C")
check(#musicFades == 1, "surf music fades into a map whose default matches the old map's default")
reset()
Audio._currentSong = { id = 200 }
r = run("warp", "B")
check(#musicFades == 0, "the destination song already playing is not faded")

print("[test] 11. a scripted warp resets the player to face south")
reset()
Player.facing = "up"
r = run("warp", "C")
check(loads[1] and loads[1].facing == "down",
  "loaded facing down, not the pre-warp facing (got " .. tostring(loads[1] and loads[1].facing) .. ")")
reset()
r = run("warpsilent", "B")
check(loads[1] and loads[1].facing == "down", "warpsilent also faces down")

print("[test] 12. an exit mat runs the same door exit as a scripted warp")
reset()
destBehavior = MB_WARP_DOOR
local exitDone = false
Warp.startDoorExit(nil, game, "C", 6, 6, 3, 7)
check(Field.locked, "the field is locked for the exit")
local exitOpenedAt, exitFrames = nil, 0
for _ = 1, 400 do
  exitFrames = exitFrames + 1
  frame()
  for _, c in ipairs(doorCalls) do
    if not exitOpenedAt and c[1] == "open" and c[2] == "C" and c[3] == 6 and c[4] == 6 then exitOpenedAt = exitFrames end
  end
  if not Warp.isBusy() then exitDone = true break end
end
local exitClosed = false
for _, c in ipairs(doorCalls) do
  if c[1] == "close" and c[2] == "C" and c[3] == 6 and c[4] == 6 then exitClosed = true end
end
check(has(sounds, SE.SE_EXIT), "SE_EXIT plays on the exit mat")
check(exitOpenedAt ~= nil and exitOpenedAt >= 15 + 25, "the destination door opens 25 frames into the fade-in (frame "
  .. tostring(exitOpenedAt) .. ")")
check(exitClosed and Player.facing == "down" and Player.visible, "stepped out facing down and the door closed")
check(exitDone and not Field.locked, "the exit finishes and releases the field")

print("[test] 9. the warp opcode hands its kind to the adapter")
local Vm = require("src.core.game3.scripting.vm")
for _, op in ipairs({ "warp", "warpsilent", "warpspinenter", "warpteleport" }) do
  local gotKind
  local vm = Vm.new({
    store = Flags.newStore(),
    scripts = { s = { { op = op, [1] = 1, [2] = 2, [3] = 255, [4] = 3, [5] = 4 }, { op = "waitstate" }, { op = "end" } } },
    adapters = {
      log = function() end,
      warp = function(_, _, _, _, _, done, kind)
        gotKind = kind
        if done then done() end
      end,
    },
  })
  vm:start("s")
  for _ = 1, 5 do vm:tick() end
  check(gotKind == op, op .. " passes its kind (got " .. tostring(gotKind) .. ")")
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)
