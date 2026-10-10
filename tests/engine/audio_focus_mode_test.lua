package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local mixWithSystemCalls = {}
love.audio = love.audio or {}
love.audio.setMixWithSystem = function(mix)
  table.insert(mixWithSystemCalls, mix)
  return true
end

-- 1. Default options across generations
local SaveData = require("src.core.SaveData")
local Save2 = require("src.core.gen2.Save")

local def1 = SaveData.defaultOptions()
eq(def1.audioMode, "both", "Gen 1 default audioMode is 'both'")

local def2 = Save2.defaultOptions()
eq(def2.audioMode, "both", "Gen 2 default audioMode is 'both'")

local merged = SaveData.mergeOptions({})
eq(merged.audioMode, "both", "mergeOptions retains default 'both'")

local mergedCustom = SaveData.mergeOptions({ audioMode = "external_only" })
eq(mergedCustom.audioMode, "external_only", "mergeOptions retains custom audioMode")

-- 2. Gen 1/2 Music module behavior
local Music = require("src.core.Music")

mixWithSystemCalls = {}
Music.applyOptions({ audioMode = "both", musicVol = 7 })
eq(Music.audioMode(), "both", "Music mode set to 'both'")
eq(mixWithSystemCalls[#mixWithSystemCalls], true, "audioMode 'both' enables mixWithSystem")

mixWithSystemCalls = {}
Music.applyOptions({ audioMode = "both", musicVol = 7 })
eq(#mixWithSystemCalls, 0, "re-applying unchanged options sends no setMixWithSystem (#2844)")

mixWithSystemCalls = {}
Music.applyOptions({ audioMode = "external_only", musicVol = 7 })
eq(Music.audioMode(), "external_only", "Music mode set to 'external_only'")
eq(#mixWithSystemCalls, 0, "'both' -> 'external_only' keeps mixWithSystem on without a resend")
eq(require("src.audio.AudioMix").current(), true, "audioMode 'external_only' enables mixWithSystem")

mixWithSystemCalls = {}
Music.applyOptions({ audioMode = "game_only", musicVol = 7 })
eq(Music.audioMode(), "game_only", "Music mode set to 'game_only'")
eq(mixWithSystemCalls[#mixWithSystemCalls], false, "audioMode 'game_only' disables mixWithSystem")

-- 3. Gen 3 Audio module behavior
local Game3Audio = require("src.core.game3.audio")

mixWithSystemCalls = {}
Game3Audio.applyEngineOptions({ audioMode = "both", musicVol = 7, sfxVol = 7 })
eq(Game3Audio._audioMode, "both", "Game3 audioMode set to 'both'")
check(Game3Audio._bgmVolume > 0, "Game3 'both' keeps BGM volume active")
eq(mixWithSystemCalls[#mixWithSystemCalls], true, "Game3 'both' enables mixWithSystem")

mixWithSystemCalls = {}
Game3Audio.applyEngineOptions({ audioMode = "external_only", musicVol = 7, sfxVol = 7 })
eq(Game3Audio._audioMode, "external_only", "Game3 audioMode set to 'external_only'")
eq(Game3Audio._bgmVolume, 0, "Game3 'external_only' mutes in-game BGM")
check(Game3Audio._sfxVolume > 0, "Game3 'external_only' keeps SFX active")
eq(require("src.audio.AudioMix").current(), true, "Game3 'external_only' enables mixWithSystem")

mixWithSystemCalls = {}
Game3Audio.applyEngineOptions({ audioMode = "game_only", musicVol = 7, sfxVol = 7 })
eq(Game3Audio._audioMode, "game_only", "Game3 audioMode set to 'game_only'")
check(Game3Audio._bgmVolume > 0, "Game3 'game_only' keeps BGM active")
eq(mixWithSystemCalls[#mixWithSystemCalls], false, "Game3 'game_only' disables mixWithSystem")

-- 4. Defensive audio suspension checks in Game3
Game3Audio.setSuspended(false)
check(Game3Audio.isFanfareFinished(), "Fanfare initially finished")

Game3Audio.setSuspended(true)
eq(Game3Audio.isSePlaying(1), false, "isSePlaying returns false when suspended")
eq(Game3Audio.isSePlaying(nil), false, "isSePlaying(nil) returns false when suspended")
eq(Game3Audio.isSpecialSePlaying(), false, "isSpecialSePlaying returns false when suspended")
eq(Game3Audio.isFanfareFinished(), true, "isFanfareFinished returns true when suspended")
Game3Audio.setSuspended(false)

-- 5. waitSe timeout resilience
local waitSeDone = false
Game3Audio._seSources = { { isPlaying = function() return true end } }
Game3Audio._seMeta = { [Game3Audio._seSources[1]] = { id = 42 } }
check(Game3Audio.isSePlaying(42), "Mock source is reporting playing")

Game3Audio.waitSe(42, function() waitSeDone = true end)
check(not waitSeDone, "waitSe callback not called before update")

-- Update for 10 frames - still waiting
for _ = 1, 10 do
  Game3Audio.update(1 / 60)
end
check(not waitSeDone, "waitSe still waiting while sound plays")

-- Update past 180 frames timeout
for _ = 1, 180 do
  Game3Audio.update(1 / 60)
end
check(waitSeDone, "waitSe callback fired after defensive timeout")

-- Test waitSe with suspended audio
local suspendedWaitDone = false
Game3Audio.setSuspended(true)
Game3Audio.waitSe(42, function() suspendedWaitDone = true end)
Game3Audio.update(1 / 60)
check(suspendedWaitDone, "waitSe immediately fires callback when suspended")
Game3Audio.setSuspended(false)
Game3Audio._seSources = {}
Game3Audio._seMeta = {}

-- 6. ops_a.lua waitse resilience
local ops_a = require("src.core.game3.scripting.ops_a")
local ctx = { mode = "bytecode", status = "running" }
local row = { 99 }

-- Simulate stuck playing sound
Game3Audio._seSources = { { isPlaying = function() return true end } }
Game3Audio._seMeta = { [Game3Audio._seSources[1]] = { id = 99 } }

local vm = { ctx = ctx, store = {}, a = {} }
local row = { op = "waitse", 99 }

local waiting = ops_a.dispatch(vm, row)
check(waiting, "waitse paused script execution")
eq(ctx.mode, "native", "ctx mode set to native")
eq(ctx.status, "waiting", "ctx status set to waiting")
check(type(ctx.nativePoll) == "function", "ctx nativePoll registered")

-- Poll for 100 frames - still waiting
for _ = 1, 100 do
  check(not ctx.nativePoll(), "nativePoll waiting")
end

-- At 181 frames, timeout triggers
local timeoutFired = false
for _ = 1, 100 do
  if ctx.nativePoll() then
    timeoutFired = true
    break
  end
end
check(timeoutFired, "ops_a waitse nativePoll unblocks on timeout")

-- If suspended, waitse immediately returns false (no freeze)
Game3Audio.setSuspended(true)
local ctx2 = { mode = "bytecode", status = "running" }
local vm2 = { ctx = ctx2, store = {}, a = {} }
local waiting2 = ops_a.dispatch(vm2, row)
check(not waiting2, "waitse does not block when suspended")
Game3Audio.setSuspended(false)
Game3Audio._seSources = {}
Game3Audio._seMeta = {}

-- 7. Options Menu row checks
local OptionsMenu = require("src.ui.OptionsMenu")
local fakeGame = {
  save = { options = SaveData.defaultOptions() },
  data = { audio = {} },
}
local menu = OptionsMenu.new(fakeGame)
local rows = menu.rows
local audioModeRow = nil
for _, r in ipairs(rows) do
  if r.id == "audioMode" then audioModeRow = r break end
end
check(audioModeRow ~= nil, "Gen 1 OptionsMenu contains audioMode row")
eq(audioModeRow.value(fakeGame), "BOTH", "Initial audioMode label is BOTH")
audioModeRow.step(fakeGame, 1)
eq(fakeGame.save.options.audioMode, "external_only", "Stepped to external_only")
eq(audioModeRow.value(fakeGame), "EXT ONLY", "Label is EXT ONLY")
audioModeRow.step(fakeGame, 1)
eq(fakeGame.save.options.audioMode, "game_only", "Stepped to game_only")
eq(audioModeRow.value(fakeGame), "GAME ONLY", "Label is GAME ONLY")

-- Gen 3 option rows
local Game3Rows = require("src.ui.game3.option_rows")
local g3Ctx = {
  options = { musicVol = 7, sfxVol = 7, audioMode = "both" },
}
local skipCart = {
  textSpeed = true, battleScene = true, battleStyle = true,
  sound = true, buttonMode = true, frameType = true,
}
local builtG3Rows = Game3Rows.build(g3Ctx, skipCart)
local g3AudioModeRow = nil
for _, r in ipairs(builtG3Rows) do
  if r.id == "audioMode" then g3AudioModeRow = r break end
end
check(g3AudioModeRow ~= nil, "Game3 option_rows contains audioMode row")
eq(g3AudioModeRow.value(g3Ctx), "BOTH", "Initial Game3 label is BOTH")
g3AudioModeRow.step(g3Ctx, 1)
eq(g3Ctx.options.audioMode, "external_only", "Game3 stepped to external_only")
eq(g3AudioModeRow.value(g3Ctx), "EXT. ONLY", "Game3 label is EXT. ONLY")
g3AudioModeRow.step(g3Ctx, 1)
eq(g3Ctx.options.audioMode, "game_only", "Game3 stepped to game_only")
eq(g3AudioModeRow.value(g3Ctx), "GAME ONLY", "Game3 label is GAME ONLY")

T.finish("audio_focus_mode_test")
