-- Standalone: luajit mods/pokewalker/tests/pokewalker_test.lua
-- Exercises the stated effect: opt-in gating, the native-bridge seam, and
-- steps converting to EXP through the engine's own growth math.
--
-- Shipped-mod suites are auto-run by the ROM-free T4 tier, so this runs
-- against the committed fixture dataset (T.fixtures), never data/generated.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

-- The native step bridge only exists inside the iOS/Android apps; stand it
-- in so the mod sees the same surface it does on device.
local syncCalls = 0
love.system = love.system or {}
love.system.syncHealthSteps = function()
  syncCalls = syncCalls + 1
  return true
end

local run = T.sdk.loadMod("mods/pokewalker", { data = Data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local events = run.loader.events
local Growth = require("src.pokemon.Growth")
local Pokemon = require("src.pokemon.Pokemon")
local mon = Pokemon.new(Data, "FIXMON_A", 5)
local game = { data = Data, save = { party = { mon } } }

-- Dormant until opted in: seeded steps survive every event untouched and
-- the native bridge is never poked (no permission prompt without consent).
love.filesystem.write("steps_pending.json", '{"steps": 20000}')
events:emit("game.ready", { game = game })
events:emit("map.entered", {})
T.check(love.filesystem.read("steps_pending.json") ~= nil,
  "opt-out leaves pending steps untouched")
T.eq(syncCalls, 0, "opt-out never calls the native bridge")

-- Opted in: 20000 steps at the default 20 steps/EXP credit the lead mon.
run.loader.modOptions.pokewalker = { enabled = true }
local def = Data.pokemon[mon.species]
local expBefore = mon.exp
events:emit("save.loaded", {})
T.eq(mon.exp, expBefore + 1000, "20000 steps at 20 steps/EXP = +1000 EXP")
local expectedLevel = Growth.levelForExp(def.growthRate, mon.exp, 100,
                                         Data.growth_rates)
T.check(mon.level > 5, "enough EXP to actually level (fixture curve)")
T.eq(mon.level, expectedLevel, "level matches the engine growth curve")
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
