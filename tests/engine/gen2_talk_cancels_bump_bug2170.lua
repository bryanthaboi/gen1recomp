-- engine/overworld/player_movement.asm:807-816
-- engine/overworld/events.asm:494-510
-- engine/overworld/map_objects.asm:1851-1860

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local Player = require("src.world.gen2.Player")
local World = require("src.world.gen2.World")

local MAP = {
  inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 20 and y < 20 end,
  isWalkable = function(_, x, y) return x == 5 and y == 5 end,
}

local function bumpedPlayer()
  local p = Player.new(5, 5, "right", nil)
  p.turnArmed = false
  p.animClock = 16
  p:tryMove("right", MAP, nil)
  return p
end

do
  local p = bumpedPlayer()
  eq(p.bumpFrames, 1, "the wall armed the in-place bump")
  eq(p:walkPhase(), 1, "and this clock draws the walking pose")
  p:stopForEvent()
  eq(p.bumpFrames, nil, "stopForEvent drops the queued bump")
  eq(p:walkPhase(), 0, "which snaps back to the standing pose")
  eq(p:drawFlip(), p.stepFlip, "with the sprite unmirrored")
end

do
  local peopleTicked = false
  local w = setmetatable({
    map = MAP,
    player = bumpedPlayer(),
    busy = function() return true end,
    pollTimeOfDay = function() end,
    pollCaveFlicker = function() end,
    pollTileAnim = function() end,
    handleCmdQueue = function() return false end,
    updatePeople = function() peopleTicked = true end,
  }, { __index = World })

  eq(w.player:walkPhase(), 1, "the bump pose is live when the script starts")
  w:stepBody()
  check(peopleTicked, "the busy arm still ticks the map objects")
  eq(w.player.bumpFrames, nil, "the held world cleared the bump")
  eq(w.player:walkPhase(), 0, "so the talk draws the standing frame")
end

do
  local w = setmetatable({
    map = MAP,
    player = Player.new(5, 5, "right", nil),
    busy = function() return true end,
    pollTimeOfDay = function() end,
    pollCaveFlicker = function() end,
    pollTileAnim = function() end,
    handleCmdQueue = function() return false end,
    updatePeople = function() end,
    playerStepGrass = function() end,
    grassAt = function() return false end,
  }, { __index = World })
  w.player:scriptStep("right")
  local before = w.player.progress
  w:stepBody()
  check(w.player.progress > before, "a scripted step keeps advancing")
end

T.finish("gen2_talk_cancels_bump_bug2170")
