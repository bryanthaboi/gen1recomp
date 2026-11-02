-- encounter.table lets a mod read the effective wild-encounter distribution
-- for a map/terrain, composed with any live encounter.table wrapper, with no
-- RNG and no side effects -- the read side encounter.roll/encounter.species
-- never had. Exercised through mod.world:effectiveEncounters on hand-built
-- fixture data for both generations; the roll hooks themselves are untouched.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local WorldAPI = require("src.world.WorldAPI")
local WorldAPI2 = require("src.world.gen2.WorldAPI")
local Clock = require("src.core.gen2.Clock")

local FIXTURE = {
  ["mods/encounter_probe/manifest.json"] = [[{
    "id": "encounter_probe",
    "name": "Encounter Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/encounter_probe/main.lua"] = [[
    local mod = ...
    mod.exports.calls = 0
    mod.hooks:wrap("encounter.table", function(next, dist, ctx)
      mod.exports.calls = mod.exports.calls + 1
      mod.exports.ctx = ctx
      mod.exports.sawRng = ctx.rng ~= nil
      dist = next(dist, ctx)
      local biased = {}
      for species, weight in pairs(dist) do biased[species] = weight end
      biased.MEW = 999
      return biased
    end)
  ]],
}

-- ------- Gen 1

local gen1Game = {
  data = {
    encounters = {
      PALLET_TOWN = {
        grass = { rate = 156, buckets = { 100, 200, 256 },
          slots = { { level = 3, species = "PIDGEY" },
                    { level = 3, species = "RATTATA" },
                    { level = 4, species = "PIDGEY" } } },
        water = { rate = 20, buckets = { 200, 256 },
          slots = { { level = 10, species = "POLIWAG" },
                    { level = 15, species = "TENTACOOL" } } },
      },
      DEAD_END = {
        grass = { rate = 0, buckets = { 256 },
          slots = { { level = 5, species = "NOTHING" } } },
      },
    },
  },
}
local gen1 = WorldAPI.new(gen1Game, "test")

-- ------- no mod: vanilla weights, exactly

local vanilla = T.sdk.loadNone({})

local grass = gen1:effectiveEncounters("PALLET_TOWN", "grass")
T.check(grass ~= nil, "PALLET_TOWN grass returns a result")
T.eq(grass.chance, 156 / 256, "chance matches the vanilla rate")
T.eq(grass.dist.PIDGEY, 156, "PIDGEY sums both its slots (100 + 56)")
T.eq(grass.dist.RATTATA, 100, "RATTATA keeps its own slot's weight")

local indoor = gen1:effectiveEncounters("PALLET_TOWN", "indoor")
T.eq(indoor.chance, grass.chance, "indoor reuses grass's chance")
T.eq(indoor.dist.PIDGEY, grass.dist.PIDGEY, "and grass's distribution, exactly")

local water = gen1:effectiveEncounters("PALLET_TOWN", "water")
T.eq(water.chance, 20 / 256, "water has its own, separate chance")
T.eq(water.dist.POLIWAG, 200, "and its own distribution")
T.eq(water.dist.TENTACOOL, 56, "second water slot")

local dead = gen1:effectiveEncounters("DEAD_END", "grass")
T.eq(dead.chance, 0, "a zero-rate table reports zero chance")
T.eq(next(dead.dist), nil, "and an empty distribution, not an error")

local unknown = gen1:effectiveEncounters("NOWHERE", "grass")
T.eq(unknown.chance, 0, "an unknown map answers zero rather than nil")
T.eq(next(unknown.dist), nil, "with an empty distribution")

local badTerrain, err = gen1:effectiveEncounters("PALLET_TOWN", "lava")
T.eq(badTerrain, nil, "an invalid terrain returns nil")
T.check(err ~= nil, "and a reason")

vanilla.release()

-- ------- Gen 1, wrapped

local run = T.sdk.loadMods({ "mods/encounter_probe" },
  { fs = T.sdk.memfs(FIXTURE) })
T.eq(#run.errors, 0,
  "the encounter probe loads clean (" .. tostring(run.errors[1]) .. ")")
local probe = run.loader.exports.encounter_probe

local wrapped = gen1:effectiveEncounters("PALLET_TOWN", "grass")
T.eq(wrapped.dist.MEW, 999, "the wrapper's bias comes through")
T.eq(wrapped.dist.PIDGEY, 156, "and the vanilla species are still there")
T.eq(probe.calls, 1, "the hook ran once")
T.eq(probe.ctx.mapId, "PALLET_TOWN", "ctx carries mapId")
T.eq(probe.ctx.terrain, "grass", "and terrain")
T.eq(probe.ctx.preview, true, "and preview = true")
T.eq(probe.sawRng, false, "ctx.rng is absent on a preview call")

run.release()

-- ------- a wrapper that forgets to return anything must not corrupt dist

local CARELESS_FIXTURE = {
  ["mods/careless_probe/manifest.json"] = [[{
    "id": "careless_probe",
    "name": "Careless Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/careless_probe/main.lua"] = [[
    local mod = ...
    mod.hooks:wrap("encounter.table", function(next, dist, ctx)
      -- deliberately no return
    end)
  ]],
}
local carelessRun = T.sdk.loadMods({ "mods/careless_probe" },
  { fs = T.sdk.memfs(CARELESS_FIXTURE) })
T.eq(#carelessRun.errors, 0, "the careless probe loads clean")

local safe = gen1:effectiveEncounters("PALLET_TOWN", "grass")
T.check(safe ~= nil, "a non-returning hook does not blow up the call")
T.eq(safe.dist.PIDGEY, 156, "and the pre-hook dist survives intact")
T.eq(safe.dist.RATTATA, 100, "same vanilla weights as with no mod at all")

carelessRun.release()

-- ------- Gen 2 (grass is 3 distributions per map, one per time of day;
-- water has no time split)

local gen2Game = {
  data = {
    gen2Encounters = {
      grass = {
        NEW_BARK_TOWN = {
          rates = { MORN = 51, DAY = 51, NITE = 51 },
          slots = {
            MORN = { { level = 3, species = "HOOTHOOT" } },
            DAY = { { level = 3, species = "PIDGEY" },
                    { level = 4, species = "PIDGEY" } },
            NITE = { { level = 3, species = "HOOTHOOT" } },
          },
        },
      },
      water = {
        NEW_BARK_TOWN = { rate = 30,
          slots = { { level = 10, species = "POLIWAG" } } },
      },
    },
  },
  save = {},
}
local gen2 = WorldAPI2.new(gen2Game, "test")

local vanilla2 = T.sdk.loadNone({})

-- GRASS_SLOT_CHANCES = {30,60,80,90,95,99,100}; a 2-slot fixture only fills
-- the first two cumulative steps (30, then 60-30=30), the rest go unclaimed.
local day = gen2:effectiveEncounters("NEW_BARK_TOWN", "grass",
  { daytime = "DAY" })
T.eq(day.chance, 51 / 256, "Gen 2 grass chance, DAY")
T.eq(day.dist.PIDGEY, 60, "both DAY slots sum (30 + 30)")

local morn = gen2:effectiveEncounters("NEW_BARK_TOWN", "grass",
  { daytime = "MORN" })
T.eq(morn.dist.PIDGEY, nil, "PIDGEY is a DAY-only species here")
T.eq(morn.dist.HOOTHOOT, 30, "MORN's own single slot")

local dark = gen2:effectiveEncounters("NEW_BARK_TOWN", "grass",
  { daytime = "DARK" })
T.eq(dark.dist.HOOTHOOT, 30, "DARK reads as NITE (same single slot as MORN)")

local waterGen2 = gen2:effectiveEncounters("NEW_BARK_TOWN", "water")
T.eq(waterGen2.chance, 30 / 256, "Gen 2 water chance")
T.eq(waterGen2.dist.POLIWAG, 60, "water's own single slot")

local badDaytime, dErr = gen2:effectiveEncounters("NEW_BARK_TOWN", "grass",
  { daytime = "TEATIME" })
T.eq(badDaytime, nil, "an invalid daytime returns nil")
T.check(dErr ~= nil, "and a reason")

local noIndoor, iErr = gen2:effectiveEncounters("NEW_BARK_TOWN", "indoor")
T.eq(noIndoor, nil, "Gen 2 has no indoor/cave quirk to reuse grass through")
T.check(iErr ~= nil, "so indoor is just an invalid terrain here")

Clock.setTime(gen2Game.save, 14, 0)
local now = gen2:effectiveEncounters("NEW_BARK_TOWN", "grass")
T.eq(now.dist.PIDGEY, day.dist.PIDGEY,
  "omitted daytime resolves the save's actual current time (14:00 = DAY)")

vanilla2.release()

T.finish("encounter table")
