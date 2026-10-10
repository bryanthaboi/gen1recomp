-- engine/battle/core.asm:928
-- home/overworld.asm:2344
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Sound = require("src.core.Sound")
local Music = require("src.core.Music")
local GameVersion = require("src.core.GameVersion")

local realStopLoop, realRestore = Sound.stopLoop, Music.restoreMap
local restores = 0
Sound.stopLoop = function() end
Music.restoreMap = function() restores = restores + 1 end

local function makeGame()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
  local stack = { states = {} }
  function stack:push(s) self.states[#self.states + 1] = s end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return { data = Data, save = save, stack = stack,
           input = { wasPressed = function() return false end,
                     isDown = function() return false end } }
end

local function finishWith(kind, result)
  local game = makeGame()
  local b = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  game.stack:push(b)
  b.musicKind = kind
  b.result = result
  b.evolutionsChecked = true
  b.pikachuMoodChecked = true
  b.onFinish = function() end
  restores = 0
  local ok, err = pcall(b.finish, b)
  T.check(ok, kind .. "/" .. result .. ": finish runs" .. (ok and "" or (": " .. tostring(err))))
  return restores
end

GameVersion.set("red")

T.eq(finishWith("final", "win"), 0,
     "beating RIVAL3 keeps the victory theme playing into the overworld")
T.eq(finishWith("trainer", "win"), 1,
     "an ordinary trainer win restores the map theme")
T.eq(finishWith("gym", "win"), 1,
     "a gym leader win restores the map theme")
T.eq(finishWith("final", "lose"), 1,
     "losing to RIVAL3 restores the map theme")

Sound.stopLoop, Music.restoreMap = realStopLoop, realRestore

T.finish()
