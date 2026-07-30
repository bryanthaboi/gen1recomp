-- Standalone: luajit mods/pokewalker/tests/pokewalker_test.lua
-- Exercises the stated effect: opt-in gating, the native-bridge seam, and
-- steps converting to EXP through the engine's own growth math.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = require("src.core.Data")
Data:load()

-- The native Health bridge only exists inside the iOS app; stand it in so
-- the mod sees the same surface it does on device.
local syncCalls = 0
love.system = love.system or {}
love.system.syncHealthSteps = function()
  syncCalls = syncCalls + 1
  return true
end

local run = T.sdk.loadMod("mods/pokewalker", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local events = run.loader.events
local Pokemon = require("src.pokemon.Pokemon")
local mon = Pokemon.new(Data, "PIDGEY", 5)
local game = { data = Data, save = { party = { mon } } }

-- Dormant until opted in: seeded steps survive every event untouched and
-- the native bridge is never poked (no permission prompt without consent).
love.filesystem.write("steps_pending.json", '{"steps": 4000}')
events:emit("game.ready", { game = game })
events:emit("map.entered", {})
T.check(love.filesystem.read("steps_pending.json") ~= nil,
  "opt-out leaves pending steps untouched")
T.eq(syncCalls, 0, "opt-out never calls the native bridge")

-- Opted in: 4000 steps at the default 20 steps/EXP credit the lead mon.
run.loader.modOptions.pokewalker = { enabled = true }
local expBefore = mon.exp
events:emit("save.loaded", {})
T.eq(mon.exp, expBefore + 200, "4000 steps at 20 steps/EXP = +200 EXP")
T.eq(mon.level, 8, "level-ups ride the engine growth curve (5 -> 8)")
T.check(mon.stats.hp > 0 and mon.hp <= mon.stats.hp,
  "stat recalc keeps HP within the new maximum")
T.check(love.filesystem.read("steps_pending.json") == nil,
  "pending file is consumed exactly once")
T.check(syncCalls > 0, "opt-in requests a native sync")

-- A consumed file plus more events must not double-credit.
local expAfter = mon.exp
events:emit("map.entered", {})
T.eq(mon.exp, expAfter, "no pending file, no phantom EXP")

run.release()
T.finish("pokewalker")
