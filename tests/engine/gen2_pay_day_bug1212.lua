-- engine/battle/move_effects/pay_day.asm:13, engine/battle/core.asm:8014-8042

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Effects = require("src.battle.gen2.Effects")
local Mon = require("src.battle.gen2.Mon")
local Prize = require("src.battle.gen2.Prize")

local LEVEL = 15

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  PAY_DAY = { id = "PAY_DAY", name = "PAY DAY", power = 40, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 20, effect = "EFFECT_PAY_DAY" },
}

local POKEMON = {
  growthRates = {
    GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
      linear = 0, constant = 0 },
  },
  MEOWTH = {
    id = "MEOWTH", index = 52, name = "MEOWTH",
    baseStats = { hp = 40, attack = 45, defense = 35, speed = 90,
      specialAttack = 40, specialDefense = 40 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 69,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "PAY_DAY" } }, evolutions = {},
  },
  RATTATA = {
    id = "RATTATA", index = 19, name = "RATTATA",
    baseStats = { hp = 30, attack = 56, defense = 35, speed = 72,
      specialAttack = 25, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 51,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
  items = {},
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function highRoll(n) return 99 % math.max(1, n or 1) end

local function newSave()
  return { player = { name = "GOLD", money = 1000, id = 4242 },
    mom = { savedMoney = 500 }, party = {} }
end

local function newBattle(save)
  local player = Mon.new(DATA, "MEOWTH", LEVEL, { dvs = perfect })
  player.moves = {
    { id = "PAY_DAY", pp = 20, maxPp = 20 },
    { id = "TACKLE", pp = 35, maxPp = 35 },
  }
  local wild = Mon.new(DATA, "RATTATA", LEVEL, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  wild.maxHp = 999
  wild.hp = 999
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = highRoll, save = save })
  return battle, player, wild
end

local function eventWithText(events, text)
  for _, event in ipairs(events or {}) do
    if event.text == text then return event end
  end
  return nil
end

local function findText(events, text)
  return eventWithText(events, text) ~= nil
end

do
  local battle, player, wild = newBattle(newSave())
  battle:useMove(player, wild, "PAY_DAY")
  T.eq(battle.payDay, 2 * LEVEL, "one connected hit is 2 x the user's level")
  T.check(findText(battle:takeEvents(), "Coins scattered\neverywhere!"),
    "CoinsScatteredText rides the hit")
  battle:useMove(player, wild, "PAY_DAY")
  T.eq(battle.payDay, 4 * LEVEL, "a second hit adds the same again")
  battle:useMove(player, wild, "TACKLE")
  T.eq(battle.payDay, 4 * LEVEL, "another move adds nothing")
end

do
  local battle, player, wild = newBattle(newSave())
  battle.stages.enemy.evasion = Effects.MAX_STAGE
  battle:useMove(player, wild, "PAY_DAY")
  T.eq(battle.payDay, nil, "a miss accumulates nothing")
end

do
  local battle, player, wild = newBattle(newSave())
  battle.amuletCoin = true
  battle:useMove(player, wild, "PAY_DAY")
  battle:useMove(player, wild, "PAY_DAY")
  T.eq(battle.payDay, 4 * LEVEL,
    "the Amulet Coin does not double the running counter")
end

do
  local battle, player, wild = newBattle(newSave())
  local enemy = battle.enemy
  enemy.level = 40
  battle:useMove(enemy, player, "PAY_DAY")
  T.eq(battle.payDay, 80, "an enemy's PAY DAY pays the player, at ITS level")
  T.check(wild == battle.enemy, "the enemy is the wild mon")
end

do
  local save = newSave()
  T.eq(Prize.payDay(save, 30, false), 30, "the payout returns what it paid")
  T.eq(save.player.money, 1030, "and writes the wallet directly")
  T.eq(save.mom.savedMoney, 500, "with no Mom split")
end

do
  local save = newSave()
  T.eq(Prize.payDay(save, 30, true), 60, "the Amulet Coin doubles the total")
  T.eq(save.player.money, 1060, "once, at payout")
end

do
  local save = newSave()
  T.eq(Prize.payDay(save, 0, true), nil, "an empty counter pays nothing")
  T.eq(Prize.payDay(save, nil, false), nil, "and neither does an unset one")
  T.eq(save.player.money, 1000, "the wallet is untouched")
  T.eq(Prize.payDay(nil, 30, false), nil, "a save-less battle pays nothing")
end

do
  local save = newSave()
  save.player.money = Prize.MAX_MONEY - 10
  Prize.payDay(save, 500, true)
  T.eq(save.player.money, Prize.MAX_MONEY, "AddBattleMoneyToAccount clamps")
end

do
  local save = newSave()
  local battle, player, wild = newBattle(save)
  battle:useMove(player, wild, "PAY_DAY")
  wild.hp = 0
  T.check(battle:resolveFaints(), "the enemy faint ends the battle")
  T.eq(battle.outcome, "win", "on the win arm")
  T.eq(save.player.money, 1000 + 2 * LEVEL, "which is where CheckPayDay runs")
  T.eq(battle.payDay, nil, "and the counter is cleared")
  local paid = eventWithText(battle:takeEvents(), "GOLD picked up\n¥30!")
  T.check(paid, "BattleText_PlayerPickedUpPayDayMoney")
  T.eq(paid and paid.kind, "money", "on the same event kind the prize uses")
end

do
  local save = newSave()
  local battle, player, wild = newBattle(save)
  battle.amuletCoin = true
  battle:useMove(player, wild, "PAY_DAY")
  wild.hp = 0
  battle:resolveFaints()
  T.eq(save.player.money, 1000 + 4 * LEVEL,
    "the Amulet Coin doubles once on the way out")
end

do
  local save = newSave()
  local battle, player, wild = newBattle(save)
  battle:useMove(player, wild, "PAY_DAY")
  player.hp = 0
  T.check(battle:resolveFaints(), "a whiteout ends the battle")
  T.eq(battle.outcome, "lose", "on the lose arm")
  T.eq(save.player.money, 1000, "which pays nothing")
  T.eq(battle.payDay, 2 * LEVEL, "the counter is dropped, not banked")
end

do
  local save = newSave()
  local battle, player, wild = newBattle(save)
  battle:useMove(player, wild, "PAY_DAY")
  battle:endBattle("run")
  T.eq(save.player.money, 1000, "running away pays nothing")
end

local function newScreen(save, battle, opts)
  opts = opts or {}
  local pushed = {}
  local screen = setmetatable({
    game = { data = DATA },
    save = save, battle = battle, picHidden = {},
    contest = opts.contest, tutorial = opts.tutorial,
    contestCaught = false,
    push = function(self, event) pushed[#pushed + 1] = event end,
    name = function(_, mon) return mon.species end,
    hasPokedex = function() return false end,
    currentBox = function() return 1 end,
    contestCatch = function(self) self.contestCaught = true end,
  }, { __index = BattleState })
  return screen, pushed
end

local function caughtEnemy(battle)
  local enemy = battle.enemy
  enemy.hp = 1
  return enemy
end

do
  local save = newSave()
  local battle, player, wild = newBattle(save)
  battle:useMove(player, wild, "PAY_DAY")
  local screen, pushed = newScreen(save, battle)
  screen:pushCaught(caughtEnemy(battle), "POKE_BALL")
  T.eq(save.player.money, 1000 + 2 * LEVEL, "a capture pays out")
  T.eq(battle.payDay, nil, "and clears the counter")
  T.check(findText(pushed, "GOLD picked up\n¥30!"), "with the payout line")
end

do
  local save = newSave()
  local battle, player, wild = newBattle(save)
  battle:useMove(player, wild, "PAY_DAY")
  local screen = newScreen(save, battle, { contest = true })
  screen:pushCaught(caughtEnemy(battle), "PARK_BALL")
  T.check(screen.contestCaught, "the contest arm still holds the mon")
  T.eq(save.player.money, 1000 + 2 * LEVEL, "and a contest catch pays too")
  T.eq(battle.payDay, nil, "clearing the counter with it")
end

do
  local save = newSave()
  local battle, player, wild = newBattle(save)
  battle:useMove(player, wild, "PAY_DAY")
  local screen = newScreen(save, battle, { tutorial = true })
  screen:pushCaught(caughtEnemy(battle), "POKE_BALL")
  T.eq(save.player.money, 1000, "the catching tutorial pays nothing")
  T.eq(battle.payDay, 2 * LEVEL, "and leaves the counter alone")
end

do
  local save = newSave()
  local battle, player, wild = newBattle(save)
  battle:useMove(player, wild, "PAY_DAY")
  wild.hp = 0
  battle:resolveFaints()
  local screen = newScreen(save, battle, { contest = true })
  screen:pushPayDay()
  T.eq(save.player.money, 1000 + 2 * LEVEL,
    "a contest KO that already paid does not pay a second time")
end

T.finish("gen2 pay day bug 1212")
