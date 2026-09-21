package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

-- A FireRed mod's species and move patches are merged onto the live
-- src.core.game3.pokemon module when the mods load.  Entering FireRed then
-- runs Pokemon.install(), which swaps every species table for a fresh copy of
-- the ROM pack (src/core/game3/runtime.lua), so without a re-apply the
-- patches -- a translation's species and move names first of all -- never
-- reach a screen.

local T = require("tests.modkit")
local Gen3Compat = require("src.mods.Gen3Compat")
local Pokemon = require("src.core.game3.pokemon")

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

-- The live module, seeded with the SDK's small FireRed pack instead of a ROM.
local rom = T.sdk.gen3Data()
local pristine = {}
for key, value in pairs(rom.gen3Pokemon) do
  pristine[key] = value
  Pokemon[key] = copy(value)
end
rom.gen3Pokemon = Pokemon

local MOD = {
  ["mods/names/manifest.json"] = [[{
    "id": "names", "name": "names", "version": "1.0.0", "entry": "main.lua",
    "api": 2, "games": ["firered"]
  }]],
  ["mods/names/main.lua"] = [[
    local mod = ...
    mod.content.pokemon:patch("CHARMANDER", { name = "SALAMECHE",
      baseStats = { attack = 99 },
      learnset = { { level = 1, move = "SCRATCH" }, { level = 20, move = "SHADOW_CLAW" } } })
    mod.content.moves:patch("SCRATCH", { name = "GRIFFE" })
    -- a move the ROM does not have, which the species above learns
    local base = mod.content.moves:get("SCRATCH")
    local claw = {}
    for key, value in pairs(base) do claw[key] = value end
    claw.id, claw.index, claw.name, claw.power = "SHADOW_CLAW", 354, "SHADOW CLAW", 70
    mod.content.moves:register("SHADOW_CLAW", claw)
  ]],
}

local run = T.sdk.loadMods({ "mods/names" }, {
  fs = T.sdk.memfs(MOD), data = rom, generation = 3,
})
T.eq(#run.errors, 0, "the fixture mod loads (" .. tostring(run.errors[1]) .. ")")
T.eq(Pokemon.name(4), "SALAMECHE", "the merge renames the species on the live module")
T.eq(Pokemon.moveName(10), "GRIFFE", "and the move")

local function learnsAt(level)
  for _, row in ipairs(Pokemon._learnsets[4] or {}) do
    if row[1] == level then return row[2] end
  end
end
-- What the merge made of a learnset row naming the mod's own move; the
-- reinstall must give back the same thing, whatever that is.
local mergedClaw = learnsAt(20)
T.check(mergedClaw ~= nil and mergedClaw ~= 0, "the merge teaches the species the mod's own move")

local game = { mods = run.loader, data = rom }
Gen3Compat.applyMerged(game)

-- What Runtime does on entering FireRed: every table comes back from the pack.
local function reinstall()
  for key, value in pairs(pristine) do Pokemon[key] = copy(value) end
  Pokemon._runReloadHooks()
end

reinstall()
T.eq(Pokemon.name(4), "SALAMECHE", "a species name survives the pack reinstall")
T.eq(Pokemon.moveName(10), "GRIFFE", "so does a move name, which lives in the same pack")
T.eq(Pokemon._stats[4] and Pokemon._stats[4].atk, 99, "and the rest of the species patch")
T.eq(learnsAt(20), mergedClaw,
  "and a learnset naming a move the mod added resolves as it did at the merge, not to move 0")
T.eq(Pokemon.name(5), "CHARMELEON", "an untouched species keeps its ROM name")

reinstall()
T.eq(Pokemon.name(4), "SALAMECHE", "and it holds across a second reinstall")

run.release()
T.finish("game3_mod_names_survive_reload_test")
