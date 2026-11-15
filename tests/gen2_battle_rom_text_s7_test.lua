package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle rom text s7")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")
local TextBox = require("src.render.TextBox")
local Fixture = require("tests.fixture_data.gen2_rom_text_s7_a")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, accuracyRaw = 242, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}

local function species(id, index)
  return { id = id, index = index, name = id,
    baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} }
end

local POKEMON = {
  growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1,
    squared = 0, linear = 0, constant = 0 } },
  MACHOP = species("MACHOP", 66),
  PIDGEY = species("PIDGEY", 16),
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function newBattle(text, random)
  local data = { pokemon = POKEMON, moves = MOVES, items = {}, text = text,
    type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(),
      types = TYPES, matchups = {} } }
  local player = Mon.new(data, "MACHOP", 20, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(data, "PIDGEY", 20, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = data, party = { player }, wild = wild,
    random = random or function() return 0 end })
  battle:takeEvents()
  return battle, player, wild
end

local function messages(events)
  local out = {}
  for _, event in ipairs(events) do
    if event.kind == "message" then out[#out + 1] = event.text end
  end
  return out
end

local function has(list, text)
  for _, line in ipairs(list) do
    if line == text then return true end
  end
  return false
end

local function fill(text, label, fills)
  return (TextBox.strip(text[label]):gsub("%b{}", function(token)
    return fills[token:sub(2, -2)] or token
  end))
end

-- engine/battle/effect_commands.asm:2314, :2341, :2343
do
  local text = Fixture.text()
  local battle, player, wild = newBattle(text)
  battle:dealDamage(player, wild, 1, { critical = true, effectiveness = 20 })
  local said = messages(battle:takeEvents())
  check(has(said, fill(text, "CriticalHitText", {})), "CriticalHitText")
  check(has(said, fill(text, "SuperEffectiveText", {})), "SuperEffectiveText")

  local tagged = Fixture.text({
    CriticalHitText = "S7 CRIT{PROMPT}",
    SuperEffectiveText = "S7 SUPER\neffective{PROMPT}",
    NotVeryEffectiveText = "S7 NOT VERY{PROMPT}",
  })
  local tb, tp, tw = newBattle(tagged)
  tb:dealDamage(tp, tw, 1, { critical = true, effectiveness = 20 })
  tb:dealDamage(tp, tw, 1, { effectiveness = 5 })
  eq(table.concat(messages(tb:takeEvents()), "|"), "S7 CRIT|S7 SUPER\neffective|S7 NOT VERY",
    "each line is the dataset's own, whatever it says")
end

-- engine/battle/effect_commands.asm:2221, home/text.asm:374
do
  local text = Fixture.text({
    EnemyText = "FOE ",
    AttackMissedText = "{USER} MISSED{PROMPT}",
  })
  local battle, player, wild = newBattle(text, function(n)
    return (n or 256) - 1
  end)
  battle:useMove(player, wild, "TACKLE")
  check(has(messages(battle:takeEvents()), "MACHOP MISSED"),
    "the player's miss fills <USER> bare")
  battle:useMove(wild, player, "TACKLE")
  check(has(messages(battle:takeEvents()), "FOE PIDGEY MISSED"),
    "the foe's miss takes the cache's EnemyText prefix")

  local gold = Fixture.text()
  local gb, gp, gw = newBattle(gold, function(n) return (n or 256) - 1 end)
  gb:useMove(gp, gw, "TACKLE")
  check(has(messages(gb:takeEvents()),
    fill(gold, "AttackMissedText", { USER = "MACHOP" })),
    "AttackMissedText as the g1r-gold cache spells it")
end

-- ../pokecrystal/engine/battle/core.asm:7685, :7707
-- ../pokecrystal/engine/battle/effect_commands.asm:5662
do
  local gold = newBattle(Fixture.text())
  local crystal = newBattle(Fixture.text(nil, "crystal"))
  eq(gold:goMonText(gold.player), "Go! MACHOP!", "Gold's GoMonText carries the name")
  eq(crystal:goMonText(crystal.player), "Go! MACHOP!",
    "Crystal's GoMonText chains BattleMonNicknameText")
  eq(gold:trapTextLabel("FIRE_SPIN"), "WasTrappedText", "Gold's FIRE SPIN line")
  eq(crystal:trapTextLabel("FIRE_SPIN"), "FireSpinTrapText", "Crystal's FIRE SPIN line")
  eq(crystal:trapTextLabel("WHIRLPOOL"), "WhirlpoolTrapText", "Crystal's WHIRLPOOL line")
end

-- data/battle/stat_names.asm:1, engine/battle/move_effects/curse.asm:88
do
  local text = Fixture.text({ ["StatNames#1"] = "S7 ATK", ["StatNames#8"] = "S7 ABILITY" })
  local battle, player = newBattle(text)
  battle.stages.player.attack = 6
  battle:changeStage(player, "attack", 1)
  check(has(messages(battle:takeEvents()),
    fill(text, "WontRiseAnymoreText", { USER = "MACHOP", STRBUF = "S7 ATK" })),
    "WontRiseAnymoreText names the stat from StatNames")
  eq(battle:statName("ability"), "S7 ABILITY", "Curse's cantraise word is StatNames#8")
  local bare = newBattle(Fixture.without("StatNames#1"))
  check(not pcall(bare.statName, bare, "attack"), "no StatNames#1 is an error")
end

do
  for _, label in ipairs({ "CriticalHitText", "SuperEffectiveText" }) do
    local battle, player, wild = newBattle(Fixture.without(label))
    local ok, err = pcall(battle.dealDamage, battle, player, wild, 1,
      { critical = true, effectiveness = 20 })
    check(not ok and tostring(err):find(label, 1, true) ~= nil,
      "no " .. label .. " is an error")
  end
  local battle, player, wild = newBattle(Fixture.without("AttackMissedText"),
    function(n) return (n or 256) - 1 end)
  local ok, err = pcall(battle.useMove, battle, player, wild, "TACKLE")
  check(not ok and tostring(err):find("AttackMissedText", 1, true) ~= nil,
    "no AttackMissedText is an error")
  local foe = newBattle(Fixture.without("EnemyText"))
  check(not pcall(foe.battlerName, foe, foe.enemy), "no EnemyText is an error")
end

S.finish()
