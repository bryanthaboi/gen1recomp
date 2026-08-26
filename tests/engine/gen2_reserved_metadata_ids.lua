-- Extractor metadata hidden from record id spaces remains engine-owned: mods
-- cannot claim, update, or remove it through the public content registries.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Mon = require("src.battle.gen2.Mon")

local function goldData()
  local data = T.fixtures.fresh()
  data.pokemon.growthRates = {
    GROWTH_MEDIUM_FAST = {
      numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0,
    },
  }
  data.pokemon.tmhmMoves = { "FIX_TACKLE", "FIX_CUT" }
  data.moves.generation, data.moves.source = 2, "ROM:Moves"
  data.items.generation, data.items.source = 2, "ROM:Items"
  data.items.pockets = { "ITEM", "BALL", "KEY_ITEM", "TM_HM" }
  return data
end

local function assertMetadata(data, refs, label)
  T.eq(data.pokemon.growthRates, refs.growthRates,
    label .. ": growth-rate table identity is preserved")
  T.eq(data.pokemon.tmhmMoves, refs.tmhmMoves,
    label .. ": TM/HM order identity is preserved")
  T.eq(data.moves.generation, 2, label .. ": move generation is preserved")
  T.eq(data.moves.source, "ROM:Moves", label .. ": move source is preserved")
  T.eq(data.items.generation, 2, label .. ": item generation is preserved")
  T.eq(data.items.source, "ROM:Items", label .. ": item source is preserved")
  T.eq(data.items.pockets, refs.pockets,
    label .. ": item pocket order identity is preserved")
  T.eq(Mon.experienceForLevel(
      Mon.growthFor(data, "GROWTH_MEDIUM_FAST"), 10), 1000,
    label .. ": active Gold growth behavior is preserved")
end

-- A no-mod load characterizes the unchanged active-boot behavior.
do
  local data = goldData()
  local refs = {
    growthRates = data.pokemon.growthRates,
    tmhmMoves = data.pokemon.tmhmMoves,
    pockets = data.items.pockets,
  }
  local run = T.sdk.loadNone({ data = data, generation = 2 })
  T.eq(#run.errors, 0, "no-mod Gold load remains clean")
  assertMetadata(run.data, refs, "no-mod Gold")
  run.release()
end

local files, paths = {}, {}
local attempts = {
  register_growth_rates = [[
local mod = ...
mod.content.pokemon:register("growthRates", {
  id = "growthRates", name = "CLAIMED", dex = 999,
  types = {},
  baseStats = { hp = 1, attack = 1, defense = 1, speed = 1,
    specialAttack = 1, specialDefense = 1 },
  catchRate = 1, baseExp = 1, growthRate = "GROWTH_MEDIUM_FAST",
  levelMoves = {}, evolutions = {},
  spriteFront = "assets/generated/battle/front/claimed.png",
  spriteBack = "assets/generated/battle/back/claimed.png", picSize = 5,
})
]],
  replace_growth_rates = [[
local mod = ...
mod.content.pokemon:register("growthRates", {
  id = "growthRates", name = "REPLACED", dex = 999,
  types = {},
  baseStats = { hp = 1, attack = 1, defense = 1, speed = 1,
    specialAttack = 1, specialDefense = 1 },
  catchRate = 1, baseExp = 1, growthRate = "GROWTH_MEDIUM_FAST",
  levelMoves = {}, evolutions = {},
  spriteFront = "assets/generated/battle/front/replaced.png",
  spriteBack = "assets/generated/battle/back/replaced.png", picSize = 5,
}, { replace = true })
]],
  override_move_generation = [[
local mod = ...
mod.content.moves:override("generation", {
  id = "generation", name = "CLAIMED", type = "NORMAL",
  power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT",
})
]],
  patch_item_pockets = [[
local mod = ...
mod.content.items:patch("pockets", { price = 999 })
]],
  remove_tmhm_moves = [[
local mod = ...
mod.content.pokemon:remove("tmhmMoves")
]],
}

for id, body in pairs(attempts) do
  files["mods/" .. id .. "/manifest.json"] = ([[{
    "id": %q, "name": %q, "version": "1.0.0", "entry": "main.lua",
    "api": 2, "gen2compat": true
  }]]):format(id, id)
  files["mods/" .. id .. "/main.lua"] = body
  paths[#paths + 1] = "mods/" .. id
end
table.sort(paths)

local data = goldData()
local refs = {
  growthRates = data.pokemon.growthRates,
  tmhmMoves = data.pokemon.tmhmMoves,
  pockets = data.items.pockets,
}
local run = T.sdk.loadMods(paths, {
  fs = T.sdk.memfs(files), data = data, generation = 2,
})
for id in pairs(attempts) do
  local mod = run.loader.mods[id]
  T.eq(mod and mod.state, "failed", id .. " is rejected")
  T.check(mod and tostring(mod.failure):match("reserved") ~= nil,
    id .. " reports the reserved metadata boundary")
end
assertMetadata(run.data, refs, "rejected metadata writes")
run.release()

T.finish("gen2_reserved_metadata_ids")
