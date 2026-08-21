-- JoypadOverworld calls RunMapScript every overworld frame before input is
-- even read (home/overworld.asm:1816-1821), and the gate guards are
-- per-frame "is the player standing on these coords" checks
-- (scripts/Route16Gate1F.asm:16, Route5Gate.asm:19, Route22Gate.asm:21).
-- The port only evaluated them on a completed step, so saving on a guard's
-- tile and reloading walked past the guard (#1547).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
Data.tilesets.FIX_OUT.tilesPerRow = 16
Data.field.flyWarps = Data.field.flyWarps or {}
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER" }
Data.field.waterTilesets = {}
Data.field.forcedMovement = { tiles = {} }
Data.audio = Data.audio or {}
Data.audio.songs = Data.audio.songs or {}
Data.audio.mapSongs = Data.audio.mapSongs or {}

local SaveData = require("src.core.SaveData")
local Game = require("src.core.Game")
local StateStack = require("src.core.StateStack")
local OverworldState = require("src.world.OverworldController")
local MapScripts = require("src.script.MapScripts")

Game.data = Data
Game.save = SaveData.newGame()
Game.save.player.name = "RED"
Game.save.player.map = "FIX_TOWN"
StateStack:init()
Game.stack = StateStack
Game.overworld = OverworldState
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

local TRIGGER_X, TRIGGER_Y = 4, 4
local fired = {}
MapScripts.attachBase("FIX_TOWN", {
  onStep = function(_, _, x, y)
    if x == TRIGGER_X and y == TRIGGER_Y then
      fired[#fired + 1] = { x, y }
      return true
    end
    return false
  end,
})

local function loadedSave()
  local save = SaveData.newGame()
  save.player.map = "FIX_TOWN"
  save.player.x, save.player.y = TRIGGER_X, TRIGGER_Y
  return save
end

-- === the exploit: F2 / CONTINUE onto the guard's tile re-fires the guard
fired = {}
Game:restoreSave(loadedSave(), false, { freshBoot = true })
T.eq(#fired, 1, "a freshBoot restore re-evaluates the standing-tile trigger")
T.same(fired[1], { TRIGGER_X, TRIGGER_Y },
  "at the coords the save left the player on")

-- === an ordinary warp arrival must NOT fire it
fired = {}
OverworldState:setMap("FIX_TOWN", TRIGGER_X, TRIGGER_Y, "up", {})
T.eq(#fired, 0, "a plain warp arrival still leaves the trigger to onStepComplete")

-- === dev tooling reuses opts.via == "boot" WITHOUT freshBoot
fired = {}
OverworldState:setMap("FIX_TOWN", TRIGGER_X, TRIGGER_Y, "up", { via = "boot" })
T.eq(#fired, 0, "the console warp / hot reload shape does not fire it")

-- === checkpoint resume must never re-run map scripts
fired = {}
Game:restoreCheckpointSave(loadedSave())
T.eq(#fired, 0, "a checkpoint resume re-runs nothing")

-- === restoring somewhere harmless fires nothing
fired = {}
local elsewhere = loadedSave()
elsewhere.player.x, elsewhere.player.y = 3, 3
Game:restoreSave(elsewhere, false, { freshBoot = true })
T.eq(#fired, 0, "a restore off the trigger cell is untouched")

T.finish("standing-tile triggers on restore (#1547)")
