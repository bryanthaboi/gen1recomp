package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local BugContest = require("src.core.gen2.BugContest")

-- data/wild/bug_contest_mons.asm:1 ContestMons
local function vanillaRows()
  return {
    { chance = 20, species = "CATERPIE",   min = 7,  max = 18 },
    { chance = 20, species = "WEEDLE",     min = 7,  max = 18 },
    { chance = 10, species = "METAPOD",    min = 9,  max = 18 },
    { chance = 10, species = "KAKUNA",     min = 9,  max = 18 },
    { chance = 5,  species = "BUTTERFREE", min = 12, max = 15 },
    { chance = 5,  species = "BEEDRILL",   min = 12, max = 15 },
    { chance = 10, species = "VENONAT",    min = 10, max = 16 },
    { chance = 10, species = "PARAS",      min = 10, max = 17 },
    { chance = 5,  species = "SCYTHER",    min = 13, max = 14 },
    { chance = 5,  species = "PINSIR",     min = 13, max = 14 },
    { chance = 255, species = "VENOMOTH",  min = 30, max = 40 },
  }
end

local function bytes(...)
  local list, i = { ... }, 0
  return function() i = i + 1 return list[i] or 0 end
end

local BODY = {
  [2] = [[local mod = ...
mod.content.encounters:override("bugContest", {
  { chance = 100, species = "SCYTHER", min = 20, max = 20 },
})
]],
  [3] = [[local mod = ...
mod.content.encounters:override("bugContest", { kind = "bugContest", entries = {
  { chance = 100, species = "SCYTHER", minLevel = 20, maxLevel = 20 },
} })
]],
}

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  for _, api in ipairs({ 2, 3 }) do
    T.sdk.captureRuntime()
    local data = {
      gen2Encounters = { grass = {}, water = {}, bugContest = vanillaRows() },
      pokemon = { SCYTHER = { id = "SCYTHER", name = "SCYTHER" },
                  CATERPIE = { id = "CATERPIE", name = "CATERPIE" } },
    }
    local label = version .. " API " .. api .. " "

    local vanilla = BugContest.chooseWild(data, bytes(0, 5))
    T.eq(vanilla and vanilla.species, "CATERPIE", label .. "vanilla roll 0 is CATERPIE")
    T.eq(vanilla and vanilla.level, 12, label .. "vanilla level is 7 + 5")

    local files = {
      ["mods/contest/manifest.json"] = ('{"id":"contest","name":"contest","version":"1.0.0",'
        .. '"api":%d,"games":["all"],"entry":"main.lua"}'):format(api),
      ["mods/contest/main.lua"] = BODY[api],
    }
    local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2, version = version, dev = true })
    loader:load(data)
    T.eq(loader.mods.contest and loader.mods.contest.failed, nil, label .. "bugContest override loads")

    local merged = data.gen2Encounters.bugContest
    T.eq(merged and #merged, 1, label .. "the merge lands in gen2Encounters")

    local rows = BugContest.contestMons(data)
    T.eq(#rows, 1, label .. "contestMons reads the merged gen2Encounters list")
    T.eq(rows[1] and rows[1].species, "SCYTHER", label .. "merged row is the mod's")

    local wild = BugContest.chooseWild(data, bytes(0, 0))
    T.eq(wild and wild.species, "SCYTHER", label .. "contest roll uses the mod table")
    T.eq(wild and wild.level, 20, label .. "at the mod's level")
    T.sdk.restoreRuntime()
  end
end

T.eq(#BugContest.contestMons({}), 0, "no cache table rolls nothing")
T.eq(BugContest.chooseWild({}, bytes(0, 0)), nil, "and chooseWild answers nil")

T.finish("Gen 2 bug contest encounters")
