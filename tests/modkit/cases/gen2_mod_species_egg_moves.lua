package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Breeding = require("src.core.gen2.Breeding")

local BODY = [[
local mod = ...
mod.content.pokemon:register("MODMON", {
  id = "MODMON", name = "MODMON", dex = 252,
  types = { "NORMAL" }, baseStats = { hp = 50, attack = 50, defense = 50,
    speed = 50, specialAttack = 50, specialDefense = 50 },
  catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST", picSize = 5,
  levelMoves = { { level = 1, move = "POUND" } }, evolutions = {},
  spriteFront = "front.png", spriteBack = "back.png",
})
mod.content.pokemon:register("MODMON2", {
  id = "MODMON2", name = "MODMON2", dex = 253,
  types = { "NORMAL" }, baseStats = { hp = 50, attack = 50, defense = 50,
    speed = 50, specialAttack = 50, specialDefense = 50 },
  catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST", picSize = 5,
  levelMoves = { { level = 1, move = "POUND" } }, evolutions = {},
  eggMoves = { "TACKLE" },
  spriteFront = "front.png", spriteBack = "back.png",
})
mod.content.pokemon:patch("MODMON", { name = "PATCHED" })
]]

local function data()
  return {
    pokemon = { MEW = { id = "MEW", name = "MEW", index = 151, dex = 151,
      types = { "NORMAL" }, baseStats = { hp = 100, attack = 100, defense = 100,
        speed = 100, specialAttack = 100, specialDefense = 100 },
      catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST", picSize = 5,
      levelMoves = { { level = 1, move = "POUND" } }, evolutions = {},
      spriteFront = "front.png", spriteBack = "back.png" } },
    moves = {
      POUND = { id = "POUND", name = "POUND", index = 1, type = "NORMAL",
        power = 40, accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
      TACKLE = { id = "TACKLE", name = "TACKLE", index = 33, type = "NORMAL",
        power = 35, accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
    },
    items = {},
    type_chart = { types = { NORMAL = {} }, matchups = {} }, maps = {},
    growth_rates = { MEDIUM_FAST = { expForLevel = function(level) return level ^ 3 end } },
  }
end

for _, version in ipairs({ "gold", "crystal" }) do
  T.sdk.captureRuntime()
  local files = {
    ["mods/eggs/manifest.json"] = '{"id":"eggs","name":"eggs","version":"1.0.0",'
      .. '"api":2,"games":["all"],"entry":"main.lua"}',
    ["mods/eggs/main.lua"] = BODY,
  }
  local fixture = data()
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 2,
    version = version, dev = true })
  loader:load(fixture)
  local label = version .. " "
  T.eq(loader.mods.eggs.failed, nil, label .. "mod species register")
  local ok, inherit = pcall(Breeding.canInheritMove, fixture, "MODMON", "TACKLE", {})
  T.check(ok, label .. "a mod species with no eggMoves breeds: " .. tostring(inherit))
  T.eq(ok and inherit, false, label .. "and has no egg move to inherit")
  T.same(fixture.pokemon.MODMON and fixture.pokemon.MODMON.eggMoves, {},
    label .. "a mod species with no eggMoves has none")
  T.eq(fixture.pokemon.MODMON and fixture.pokemon.MODMON.name, "PATCHED",
    label .. "a patch keeps the mod species")
  local ok2, inherit2 = pcall(Breeding.canInheritMove, fixture, "MODMON2", "TACKLE", {})
  T.check(ok2 and inherit2 == true, label .. "a mod species keeps its own eggMoves")
  local okVanilla = pcall(Breeding.canInheritMove, fixture, "MEW", "TACKLE", {})
  T.check(not okVanilla, label .. "a vanilla species with no eggMoves is still an error")
  T.sdk.restoreRuntime()
end

T.finish("Gen 2 mod species eggMoves")
