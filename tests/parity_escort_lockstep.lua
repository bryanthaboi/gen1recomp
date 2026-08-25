-- Parity test: escort lockstep cadence.  An NPC walking the player to a
-- destination moves under DoScriptedNPCMovement (engine/overworld/
-- movement.asm:737), whose wScriptedNPCWalkCounter is 8 ticks of 2px --
-- the player's own frames per cell, not MoveSprite's doubled NPC walk.
-- Self-contained: run via `luajit tests/parity_escort_lockstep.lua`; also
-- dofile'd by tests/run_tests.lua's aggregator.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity escort lockstep")
local check, eq = S.check, S.eq

local SaveData = require("src.core.SaveData")
local Game = require("src.core.Game")
local StateStack = require("src.core.StateStack")
local OverworldState = require("src.world.OverworldController")

local prev = { data = Game.data, save = Game.save, stack = Game.stack,
               input = Game.input, renderer = Game.renderer,
               overworld = Game.overworld }
Game.data = Data
Game.save = SaveData.newGame(Data)
Game.save.player.name = "RED"
StateStack:init()
Game.stack = StateStack
Game.input = {
  isDown = function() return false end,
  wasPressed = function() return false end,
  step = function() end, state = {}, pressQueue = {},
}
Game.renderer = {
  beginWorldPass = function() end, endWorldPass = function() end,
  beginUIPass = function() end, endUIPass = function() end,
  worldViewSize = function() return 160, 144 end,
  setSGBZones = function() end,
}
StateStack:push(OverworldState, "PALLET_TOWN", 10, 5, "down")
local ow = OverworldState
Game.overworld = ow

-- A PALLET_TOWN object parked one cell ahead of the player, then walked
-- in the paired-step pattern the escorts use: the NPC's step is queued
-- without a callback and the player's carries the chain.
local function runEscort(sync, steps)
  local npc = ow.npcs[1]
  local p = ow.player
  p.cellX, p.cellY, p.px, p.py = 10, 5, 160, 80
  p.moving, p.progress, p.targetX, p.targetY = false, 0, nil, nil
  npc.cellX, npc.cellY, npc.px, npc.py = 10, 4, 160, 64
  npc.moving, npc.progress, npc.targetX, npc.targetY = false, 0, nil, nil
  ow.scriptMoves = {}
  -- a scripted step re-derives its length from the live walk/bike state
  -- (home/overworld.asm:276, #1754), so sync off that, not a stale latch
  npc.stepFrames = sync and p:stepLength() or nil
  local worstDrift, done, i = 0, false, 0
  local function tick()
    i = i + 1
    if i > steps then done = true; return end
    ow:scriptMove(npc, "down", 1)
    ow:scriptMove(p, "down", 1, tick)
  end
  tick()
  -- NPCs update before updateScriptMoves and the player after, so a
  -- paired step leaves the NPC one frame (1px) behind for its whole cell
  for _ = 1, 60 * steps do
    ow:update(1)
    local drift = math.abs((p.py - npc.py) - 16)
    if drift > worstDrift then worstDrift = drift end
    if done then break end
  end
  npc.stepFrames = nil
  return { done = done, drift = worstDrift,
           npcY = npc.cellY, playerY = p.cellY }
end

local synced = runEscort(true, 6)
check(synced.done, "synced escort finishes")
check(synced.drift <= 2,
      ("synced NPC holds formation (worst drift %dpx)"):format(synced.drift))
eq(synced.playerY - synced.npcY, 1, "synced NPC stays one cell ahead")

-- The default NPC walk is MoveSprite's, half the player's rate: without
-- the sync the escort desyncs, which is the bug this guards.
local plain = runEscort(false, 6)
check(plain.drift >= 16,
      ("unsynced NPC lags a cell or more (worst drift %dpx)"):format(plain.drift))

for k, v in pairs(prev) do Game[k] = v end
S.finish()
