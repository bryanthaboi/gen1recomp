package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local text = require("tests.gen2_battle_text_fixture")()
local capture = require("tests.gen2_capture_text_fixture")()
for _, copied in ipairs({ require("tests.fixture_data.gen2_rom_text_s7_a"),
    require("tests.fixture_data.gen2_rom_text_s7_b") }) do
  for label in pairs(copied.RAW) do capture[label] = true end
  for label in pairs(copied.crystal) do capture[label] = true end
end
for label, line in pairs(text) do
  T.check(not line:find("RAM:", 1, true), label .. " uses the cache's own tokens")
  if not capture[label] then
    T.check(line:find("{PROMPT}$") or line:find("{DONE}$"), label .. " ends like the cache")
  end
end

local pokemon = {
  growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1,
    squared = 0, linear = 0, constant = 0 } },
  TEST = { id = "TEST", index = 1, name = "TEST", baseStats = {
    hp = 100, attack = 100, defense = 100, speed = 100,
    specialAttack = 100, specialDefense = 100 }, types = { "NORMAL", "NORMAL" },
    catchRate = 45, baseExp = 100, growthRate = "GROWTH_MEDIUM_FAST",
    genderRatio = 127, levelMoves = {}, evolutions = {} },
}
local moves = {}
for id, effect in pairs({ MIMIC = "MIMIC", CONVERSION = "CONVERSION",
    DESTINY_BOND = "DESTINY_BOND", TACKLE = "NORMAL_HIT", EMBER = "BURN_HIT" }) do
  moves[id] = { id = id, name = id, effect = "EFFECT_" .. effect, power = 0,
    accuracy = 100, accuracyRaw = 255, pp = 20, type = "NORMAL" }
end
moves.TACKLE.power, moves.EMBER.power, moves.EMBER.type = 40, 40, "FIRE"
local data = { pokemon = pokemon, moves = moves, items = {}, text = text,
  type_chart = { types = { NORMAL = { index = 0, name = "NORMAL", category = "physical" },
    FIRE = { index = 20, name = "FIRE", category = "special" } }, matchups = {},
    battleRules = require("tests.gen2_battle_rules_fixture")() } }

local function fixture(id)
  local dv = { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } }
  local a, b = Mon.new(data, "TEST", 50, dv), Mon.new(data, "TEST", 50, dv)
  a.nickname, b.nickname = "ALPHA", "BRAVO"
  a.moves = { { id = id, pp = 20, maxPp = 20 }, { id = "EMBER", pp = 20, maxPp = 20 } }
  b.moves = { { id = "TACKLE", pp = 20, maxPp = 20 } }
  local battle = Battle.new({ data = data, party = { a }, wild = b,
    random = function() return 0 end })
  battle.accuracyRoll = function() return true end
  battle:takeEvents()
  return battle, a, b
end

local function lines(battle)
  local out = {}
  for _, e in ipairs(battle:takeEvents()) do
    if e.text then out[#out + 1] = e.text end
  end
  return out
end

local function said(out, want)
  for _, line in ipairs(out) do
    if line == want then return true end
  end
  return false
end

local function clean(tag, out)
  T.check(#out > 0, tag .. " prints")
  for _, line in ipairs(out) do
    T.check(not line:find("{", 1, true), tag .. " leaves no token: " .. line)
  end
end

local battle, a, b = fixture("MIMIC")
battle:volatile(b).lastMove = "TACKLE"
battle:useMove(a, b, "MIMIC")
local out = lines(battle)
clean("Mimic", out)
T.check(said(out, "ALPHA\nlearned\vTACKLE!"), "MimicLearnedMoveText carries the move name")

battle, a, b = fixture("CONVERSION")
battle:useMove(a, b, "CONVERSION")
out = lines(battle)
clean("Conversion", out)
T.check(said(out, "ALPHA\ntransformed into\vthe FIRE-type!"),
  "TransformedTypeText carries the type name")

battle, a, b = fixture("DESTINY_BOND")
battle:useMove(b, a, "DESTINY_BOND")
a.hp, b.hp = 500, 1
battle:useMove(a, b, "TACKLE")
out = lines(battle)
clean("Destiny Bond", out)
T.check(said(out, "Enemy BRAVO\ntook down with it,\vALPHA!"),
  "TookDownWithItText: the bond holder is <TARGET>, the attacker <USER>")

battle, a = fixture("TACKLE")
battle:volatile(a).disabled = "TACKLE"
battle:canAct(a, "TACKLE")
out = lines(battle)
clean("Disable", out)
T.check(said(out, "ALPHA's\nTACKLE is\vDISABLED!"), "DisabledMoveText carries the move name")

battle.screens.player.lightScreen = 1
battle:tickScreens()
out = lines(battle)
clean("screens", out)
T.check(said(out, "Your POKéMON's\nLIGHT SCREEN fell!"), "the screen line names the side")

T.finish("gen2 crystal battle text")
