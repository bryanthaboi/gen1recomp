package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local data = T.fixtures.fresh()

for i, id in ipairs({ "GUST", "KARATE_CHOP", "SAND_ATTACK", "BITE" }) do
  data.moves[id] = {
    id = id, index = 10 + i, name = id, type = "NORMAL",
    power = id == "SAND_ATTACK" and 0 or 40,
    accuracy = 100, pp = 20, effect = "NO_ADDITIONAL_EFFECT",
    category = id == "SAND_ATTACK" and "status" or "physical",
  }
end
data.type_chart.matchups[#data.type_chart.matchups + 1] = {
  attacker = "GHOST", defender = "PSYCHIC_TYPE", multiplier = 0,
}

local run = T.sdk.loadMod("mods/examples/modern_type_chart", { data = data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")
T.eq(data.moves.GUST.type, "FLYING", "Gust is Flying")
T.eq(data.moves.GUST.category, "special", "Gust is special")
T.eq(data.moves.KARATE_CHOP.type, "FIGHTING", "Karate Chop is Fighting")
T.eq(data.moves.SAND_ATTACK.type, "GROUND", "Sand-Attack is Ground")
T.eq(data.moves.BITE.type, "DARK", "Bite is Dark")
T.eq(data.moves.BITE.category, "physical", "Bite is physical")

local TypeChart = require("src.battle.TypeChart")
TypeChart.load(data)
T.eq(TypeChart.effectiveness("GHOST", { "PSYCHIC_TYPE" }), 20,
  "Ghost is super effective against Psychic")
T.eq(TypeChart.effectiveness("DARK", { "PSYCHIC_TYPE" }), 20,
  "Dark is super effective against Psychic")
T.eq(TypeChart.effectiveness("PSYCHIC_TYPE", { "DARK" }), 0,
  "Dark is immune to Psychic")

run.release()
T.finish("modern_type_chart")
