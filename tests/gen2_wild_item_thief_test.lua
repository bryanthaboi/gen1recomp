-- LoadEnemyMon's `.WildItem` roll (../pokecrystal/engine/battle/core.asm:6009-6039)
-- and BattleCommand_Thief (../pokecrystal/engine/battle/move_effects/thief.asm).
--
--   luajit tests/gen2_wild_item_thief_test.lua
--
-- ROM-free.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 wild item + thief")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  DARK = { id = "DARK", index = 27, category = "special" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, accuracyRaw = 242, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  THIEF = { id = "THIEF", name = "THIEF", power = 40, type = "DARK",
    accuracy = 100, accuracyRaw = 255, pp = 10, effect = "EFFECT_THIEF",
    effectChance = 100, effectChanceRaw = 255 },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local function species(id, index, items, extra)
  local def = {
    id = id, index = index, name = id,
    baseStats = { hp = 50, attack = 60, defense = 50, speed = 60,
      specialAttack = 50, specialDefense = 50 },
    types = { "NORMAL", "NORMAL" }, catchRate = 190, baseExp = 60,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    items = items,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  }
  for k, v in pairs(extra or {}) do def[k] = v end
  return def
end

local POKEMON = {
  growthRates = GROWTH,
  SNEASEL = species("SNEASEL", 215, {}, {
    levelMoves = { { level = 1, move = "THIEF" } } }),
  MAGNEMITE = species("MAGNEMITE", 81, { [2] = "METAL_COAT" }),
  PIDGEY = species("PIDGEY", 16, { "BERRY", "GOLD_BERRY" }),
  RATTATA = species("RATTATA", 19, {}),
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = {
    METAL_COAT = { id = "METAL_COAT", name = "METAL COAT", pocket = "ITEM" },
    BERRY = { id = "BERRY", name = "BERRY", pocket = "ITEM" },
    GOLD_BERRY = { id = "GOLD_BERRY", name = "GOLD BERRY", pocket = "ITEM" },
    FLOWER_MAIL = { id = "FLOWER_MAIL", name = "FLOWER MAIL", pocket = "ITEM" },
    POKE_BALL = { id = "POKE_BALL", name = "POKe BALL", pocket = "BALL" },
  },
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function seq(...)
  local values, i, draws = { ... }, 0, 0
  local fn = function()
    i = i + 1
    draws = draws + 1
    return values[math.min(i, #values)]
  end
  return fn, function() return draws end
end

-- -------------------------------------------------------- the .WildItem roll

do
  local def = POKEMON.PIDGEY
  -- 75 percent + 1 = 192: a first draw below it is NO_ITEM, 192 falls through.
  eq(Mon.WILD_NO_ITEM_THRESHOLD, 192, "75 percent + 1")
  eq(Mon.WILD_ITEM2_THRESHOLD, 20, "8 percent")

  local r, draws = seq(191)
  eq(Mon.wildItem(def, false, r), nil, "191 on the first draw: NO_ITEM")
  eq(draws(), 1, "a NO_ITEM roll draws once")

  r, draws = seq(192, 19)
  eq(Mon.wildItem(def, false, r), "GOLD_BERRY",
    "192 then 19: the second draw under 8 percent takes Item2")
  eq(draws(), 2, "an item roll draws twice")

  r = seq(192, 20)
  eq(Mon.wildItem(def, false, r), "BERRY", "192 then 20: Item1")
  r = seq(255, 255)
  eq(Mon.wildItem(def, false, r), "BERRY", "255 then 255: Item1")
  r = seq(0)
  eq(Mon.wildItem(def, false, r), nil, "0: NO_ITEM")

  r, draws = seq(0)
  eq(Mon.wildItem(def, true, r), "BERRY",
    "BATTLETYPE_FORCEITEM hands over Item1 with no roll")
  eq(draws(), 0, "and draws nothing")

  r = seq(192, 19)
  eq(Mon.wildItem(POKEMON.MAGNEMITE, false, r), "METAL_COAT",
    "MAGNEMITE's Item2 is METAL COAT")
  r = seq(192, 20)
  eq(Mon.wildItem(POKEMON.MAGNEMITE, false, r), nil,
    "and its Item1 slot is NO_ITEM")
  r = seq(192, 19)
  eq(Mon.wildItem(POKEMON.RATTATA, false, r), nil,
    "a species with two empty slots never holds anything")
  eq(Mon.wildItem(POKEMON.RATTATA, true, r), nil,
    "even when the item is forced")
end

-- ------------------------------------------------------- through Mon.new

do
  local r = seq(192, 19)
  local wild = Mon.new(DATA, "MAGNEMITE", 16, { wild = true, random = r })
  eq(wild.item, "METAL_COAT", "a wild Mon.new rolls the held item")

  r = seq(192, 19)
  local gift = Mon.new(DATA, "MAGNEMITE", 16, { random = r })
  eq(gift.item, nil, "a non-wild Mon.new rolls nothing")

  local given = Mon.new(DATA, "MAGNEMITE", 16, { item = "BERRY" })
  eq(given.item, "BERRY", "a scripted gift keeps the item it was given")

  r = seq(0)
  local forced = Mon.new(DATA, "PIDGEY", 5, { wild = true, forceItem = true,
    random = r })
  eq(forced.item, "BERRY", "FORCEITEM through Mon.new")

  r = seq(191)
  local none = Mon.new(DATA, "PIDGEY", 5, { wild = true, random = r })
  eq(none.item, nil, "a NO_ITEM roll through Mon.new")
end

-- ------------------------------------------------------------ catch keeps it

do
  Input:init()
  local pushed = {}
  local player = Mon.new(DATA, "SNEASEL", 30, { dvs = perfect })
  local party = { player }
  local wild = Mon.new(DATA, "MAGNEMITE", 16, { dvs = perfect,
    wild = true, random = seq(192, 0) })
  eq(wild.item, "METAL_COAT", "the wild MAGNEMITE holds METAL COAT")
  local save = { party = party, inventory = { POKE_BALL = 1 },
    pokedex = { seen = {}, caught = {} } }
  local game = {
    data = DATA, save = save, input = Input, options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
    },
  }
  local battle = Battle.new({ data = DATA, party = party, wild = wild,
    save = save, random = function() return 0 end })
  local screen = BattleState.new(game, { battle = battle, save = save })
  screen:pushCaught(battle.enemy, "POKE_BALL")
  eq(#save.party, 2, "the catch joined the party")
  eq(save.party[2].item, "METAL_COAT", "and kept wEnemyMonItem")
end

-- ------------------------------------------------------------------- thief

local function newBattle(opts)
  opts = opts or {}
  local player = Mon.new(DATA, "SNEASEL", 30, { dvs = perfect })
  player.moves = { { id = "THIEF", pp = 10, maxPp = 10 } }
  player.item = opts.playerItem
  local enemy = Mon.new(DATA, opts.enemySpecies or "MAGNEMITE", 16,
    { dvs = perfect })
  enemy.moves = opts.enemyMoves or { { id = "TACKLE", pp = 35, maxPp = 35 } }
  enemy.item = opts.enemyItem
  local battle = Battle.new({
    data = DATA,
    party = { player },
    wild = (not opts.trainer) and enemy or nil,
    trainer = opts.trainer and { class = "YOUNGSTER", name = "JOEY",
      party = { enemy }, attributes = { 0, 0, 0 } } or nil,
    random = opts.random or function(n) return n == 256 and 200 or 0 end,
  })
  battle.linkBattle = opts.link or nil
  if opts.enemyFirst then
    player.stats.speed = 1
    enemy.stats.speed = 500
  end
  return battle, player, enemy
end

local function stoleLine(events)
  for _, event in ipairs(events or {}) do
    if event.kind == "message" and tostring(event.text):find("stole", 1, true) then
      return tostring(event.text)
    end
  end
  return nil
end

do
  local battle, player, enemy = newBattle({ enemyItem = "METAL_COAT" })
  local events = battle:takeTurn({ kind = "move", move = "THIEF" })
  eq(player.item, "METAL_COAT", "the player's THIEF takes the wild item")
  eq(enemy.item, nil, "and the foe no longer holds it")
  eq(stoleLine(events), "SNEASEL\nstole METAL COAT\vfrom its foe!",
    "StoleText names the user and the item")
end

do
  local battle, player, enemy = newBattle({ enemyItem = "METAL_COAT",
    playerItem = "BERRY" })
  local events = battle:takeTurn({ kind = "move", move = "THIEF" })
  eq(player.item, "BERRY", "a holder cannot steal")
  eq(enemy.item, "METAL_COAT", "so the foe keeps its item")
  eq(stoleLine(events), nil, "and nothing is said")
end

do
  local battle, player, enemy = newBattle({})
  local events = battle:takeTurn({ kind = "move", move = "THIEF" })
  eq(player.item, nil, "nothing to steal, nothing gained")
  eq(enemy.item, nil, "the foe still holds nothing")
  eq(stoleLine(events), nil, "silent")
  check((enemy.hp or 0) < (enemy.maxHp or 0), "the hit still landed")
end

do
  local battle, player, enemy = newBattle({ enemyItem = "FLOWER_MAIL" })
  local events = battle:takeTurn({ kind = "move", move = "THIEF" })
  eq(player.item, nil, "mail cannot be stolen")
  eq(enemy.item, "FLOWER_MAIL", "the foe keeps its mail")
  eq(stoleLine(events), nil, "silent")
end

do
  local battle, player, enemy = newBattle({ enemyItem = "METAL_COAT" })
  battle:volatile(enemy).substitute = 50
  local events = battle:takeTurn({ kind = "move", move = "THIEF" })
  eq(player.item, nil, "a SUBSTITUTE fails the effect")
  eq(enemy.item, "METAL_COAT", "and the item stays put")
  eq(stoleLine(events), nil, "silent")
end

do
  -- BattleCommand_EffectChance: `cp 255` fails on the one byte that is not
  -- below it (effect_commands.asm:1864-1868).
  local battle, player, enemy = newBattle({ enemyItem = "METAL_COAT" })
  battle.random = function() return 255 end
  battle:thief(player, enemy, MOVES.THIEF)
  eq(player.item, nil, "a 255 roll against the 255 chance fails")
  eq(enemy.item, "METAL_COAT", "and the foe keeps the item")
  battle.random = function() return 254 end
  battle:thief(player, enemy, MOVES.THIEF)
  eq(player.item, "METAL_COAT", "254 steals")
  eq(enemy.item, nil, "and the foe is emptied")
end

do
  local battle, player, enemy = newBattle({ enemyItem = "METAL_COAT" })
  battle.random = function() return 255 end
  battle:volatile(enemy).substitute = 50
  local draws = 0
  battle.random = function() draws = draws + 1 return 0 end
  battle:thief(player, enemy, MOVES.THIEF)
  eq(draws, 0, "CheckSubstituteOpp fails the effect before the roll")
  eq(player.item, nil, "no steal behind a SUBSTITUTE")
end

do
  local battle, player, enemy = newBattle({ enemyItem = "METAL_COAT",
    link = true })
  local events = battle:takeTurn({ kind = "move", move = "THIEF" })
  eq(player.item, nil, "a link wild battle never steals")
  eq(enemy.item, "METAL_COAT", "the foe keeps it")
  eq(stoleLine(events), nil, "silent")
end

do
  local battle, player, enemy = newBattle({ enemyItem = "METAL_COAT",
    trainer = true, link = true })
  battle:takeLinkTurn({ kind = "move", move = "THIEF" },
    { kind = "move", move = "TACKLE" })
  eq(player.item, "METAL_COAT", "a link trainer battle steals")
  eq(enemy.item, nil, "from the other side's mon")
end

do
  local battle, player, enemy = newBattle({ enemyItem = "METAL_COAT",
    trainer = true })
  battle:takeTurn({ kind = "move", move = "THIEF" })
  eq(player.item, "METAL_COAT", "a trainer's mon can be robbed")
  eq(enemy.item, nil, "and wOTPartyMon item goes with it")
  eq(battle.enemyParty[1].item, nil,
    "the party row the trainer reloads from is the same record")
end

do
  local battle, player, enemy = newBattle({ playerItem = "METAL_COAT",
    enemyMoves = { { id = "THIEF", pp = 10, maxPp = 10 } }, enemyFirst = true })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  eq(enemy.item, "METAL_COAT", "the enemy's THIEF takes the player's item")
  eq(player.item, nil, "and it is gone from the party mon")
  eq(stoleLine(events), "Enemy MAGNEMITE\nstole METAL COAT\vfrom its foe!",
    "StoleText from the enemy side")
end

do
  local battle, player, enemy = newBattle({ playerItem = "METAL_COAT",
    enemyItem = "BERRY",
    enemyMoves = { { id = "THIEF", pp = 10, maxPp = 10 } }, enemyFirst = true })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  battle:takeTurn({ kind = "move", move = "TACKLE" })
  eq(enemy.item, "BERRY", "an enemy that already holds something cannot steal")
  eq(player.item, "METAL_COAT", "so the player keeps the item")
end

do
  local battle, player, enemy = newBattle({ playerItem = "FLOWER_MAIL",
    enemyMoves = { { id = "THIEF", pp = 10, maxPp = 10 } }, enemyFirst = true })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  battle:takeTurn({ kind = "move", move = "TACKLE" })
  eq(enemy.item, nil, "the enemy cannot steal mail either")
  eq(player.item, "FLOWER_MAIL", "the player keeps the mail")
end

do
  local battle, player, enemy = newBattle({ enemyItem = "METAL_COAT" })
  enemy.hp = 1
  local events = battle:takeTurn({ kind = "move", move = "THIEF" })
  eq(player.item, "METAL_COAT", "thief runs ahead of checkfaint: a KO still steals")
  check(stoleLine(events) ~= nil, "and says so")
end

do
  local battle, player, enemy = newBattle({ enemyItem = "METAL_COAT" })
  battle:takeTurn({ kind = "move", move = "THIEF" })
  local caught = battle:caught(enemy)
  eq(caught.item, nil, "a robbed foe is caught holding nothing")
  eq(player.item, "METAL_COAT", "and the thief keeps the loot")
end

S.finish()
