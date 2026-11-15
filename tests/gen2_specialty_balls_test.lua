-- Kurt's balls and the specialty multipliers
-- (engine/items/item_effects.asm BallMultiplierFunctionTable).
--
--   luajit tests/gen2_specialty_balls_test.lua
--
-- ROM-free.  Heavy Ball's dex-weight brackets (Lugia's 4760 tenths-lb turns
-- catch rate 3 into 23, the walkthrough's whole reason to brew one), Level
-- Ball's three rungs, Lure Ball's fishing gate, and the three deliberate
-- cart bugs: Fast Ball knows exactly three species, Love Ball boosts
-- SAME-sex pairs, Moon Ball never boosts.  Friend Ball is happiness only,
-- proven through the real catch in BattleState.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 specialty balls")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Catching = require("src.battle.gen2.Catching")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")

-- ---- Heavy Ball -----------------------------------------------------------
do
  -- Lugia: dex weight 4760 (tenths of a pound) converts to 2158 tenths-kg
  -- through the cart's w/2 - w/32 - w/64 walk; high byte 8 is the +20 rung.
  eq(Catching.heavyBallBoost(4760), 20, "Lugia sits in the +20 bracket")
  eq(Catching.specialtyRate(3, "HEAVY_BALL", { weight = 4760 }), 23,
    "catch rate 3 becomes 23 -- against the Ultra Ball's 6")
  -- A light mon LOSES 20, floored at 1 (`ld b, $1` on underflow).
  eq(Catching.heavyBallBoost(40), -20, "a 4 lb mon is in the -20 bracket")
  eq(Catching.specialtyRate(3, "HEAVY_BALL", { weight = 40 }), 1,
    "and the subtraction floors at 1")
  -- Snorlax: 10140 tenths-lb -> 4599 tenths-kg, high byte 17: +40.
  eq(Catching.heavyBallBoost(10140), 40, "Snorlax earns the +40 rung")
  eq(Catching.specialtyRate(25, "HEAVY_BALL", {}), 25,
    "no weight supplied, no change")
end

-- ---- Level Ball -----------------------------------------------------------
do
  local function level(rate, player, enemy)
    return Catching.specialtyRate(rate, "LEVEL_BALL",
      { playerLevel = player, level = enemy })
  end
  eq(level(30, 10, 10), 30, "an equal level is no boost")
  eq(level(30, 20, 15), 60, "below the player's level: x2")
  eq(level(30, 40, 15), 120, "below half: x4")
  eq(level(30, 44, 10), 240, "below a quarter: x8")
  eq(level(30, 40, 10), 120,
    "the rungs are strict: 10 is NOT below floor(40/4)")
  eq(level(200, 44, 10), 255, "capped at 255 like every sla")
end

-- ---- Lure Ball ------------------------------------------------------------
do
  eq(Catching.specialtyRate(45, "LURE_BALL", { fishing = true }), 135,
    "x3 on a BATTLETYPE_FISH encounter")
  eq(Catching.specialtyRate(45, "LURE_BALL", {}), 45,
    "and nothing anywhere else")
end

-- ---- Fast Ball's bug ------------------------------------------------------
do
  for species in pairs({ MAGNEMITE = 1, GRIMER = 1, TANGELA = 1 }) do
    eq(Catching.specialtyRate(45, "FAST_BALL", { species = species }), 180,
      species .. " is one of the three the bug leaves covered")
  end
  eq(Catching.specialtyRate(45, "FAST_BALL", { species = "DRATINI" }), 45,
    "DRATINI flees on the cart too, but the broken loop never sees it")
end

-- ---- Moon Ball's bug ------------------------------------------------------
do
  eq(Catching.specialtyRate(45, "MOON_BALL",
    { evolveItem = "MOON_STONE" }), 45,
    "a Moon Stone evolver gets nothing: the check reads Gen 1's constant")
  eq(Catching.specialtyRate(45, "MOON_BALL",
    { evolveItem = "MOON_STONE", fixBugs = true }), 180,
    "fixBugs restores the intended x4")
end

-- ---- Love Ball's bug ------------------------------------------------------
do
  local function love_(gender, playerGender, fix)
    return Catching.specialtyRate(30, "LOVE_BALL", {
      species = "NIDORAN_F", playerSpecies = "NIDORAN_F",
      gender = gender, playerGender = playerGender, fixBugs = fix,
    })
  end
  eq(love_("female", "female"), 240,
    "same species, SAME sex: the x8 the `ret nz` bug ships")
  eq(love_("female", "male"), 30, "opposite sexes get nothing")
  eq(love_("female", "male", true), 240, "fixBugs flips it back")
  eq(Catching.specialtyRate(30, "LOVE_BALL", {
    species = "NIDORAN_F", playerSpecies = "PIDGEY",
    gender = "female", playerGender = "female" }), 30,
    "different species never boost")
end

-- ---- through Catching.rate ------------------------------------------------
do
  -- Full HP Lugia at rate 3: (3*maxHp - 2*hp) with the >=256 shift path,
  -- both balls through the same formula; the Heavy Ball's 23 must beat the
  -- Ultra Ball's 6 on the final rate too.
  local heavy = Catching.rate({ maxHp = 200, hp = 200, catchRate = 3,
    ball = "HEAVY_BALL", weight = 4760 })
  local ultra = Catching.rate({ maxHp = 200, hp = 200, catchRate = 3,
    ball = "ULTRA_BALL" })
  check(heavy > ultra,
    ("the brewed ball out-catches the bought one (%d > %d)"):format(
      heavy, ultra))
end

-- ---- Friend Ball happiness through the real catch -------------------------
do
  local TYPES = { NORMAL = { id = "NORMAL", index = 0,
    category = "physical" } }
  local MOVES = { TACKLE = { id = "TACKLE", name = "TACKLE", power = 35,
    type = "NORMAL", accuracy = 95, pp = 35,
    effect = "EFFECT_NORMAL_HIT" } }
  local POKEMON = {
    growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1,
      squared = 0, linear = 0, constant = 0 } },
    CYNDAQUIL = {
      id = "CYNDAQUIL", index = 155, name = "CYNDAQUIL",
      baseStats = { hp = 39, attack = 52, defense = 43, speed = 65,
        specialAttack = 60, specialDefense = 50 },
      types = { "NORMAL", "NORMAL" }, catchRate = 45, baseExp = 65,
      growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 31,
      levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
    },
    PIDGEY = {
      id = "PIDGEY", index = 16, name = "PIDGEY",
      baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
        specialAttack = 35, specialDefense = 35 },
      types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 55,
      growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
      levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
    },
  }
  local DATA = {
    pokemon = POKEMON,
    moves = MOVES,
    text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} },
    items = {
      FRIEND_BALL = { id = "FRIEND_BALL", name = "FRIEND BALL",
        pocket = "BALL" },
      POKE_BALL = { id = "POKE_BALL", name = "POKe BALL", pocket = "BALL" },
    },
  }
  local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
  perfect.hp = Mon.hpDV(perfect)

  local function catchWith(ball)
    Input:init()
    local player = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
    player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
    wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
    local save = { party = { player }, inventory = { [ball] = 1 } }
    local game = {
      data = DATA, save = save, input = Input, options = {},
      stack = { push = function() end, pop = function() end,
        top = function() return nil end },
    }
    -- random 0: the catch roll always lands (rate 255 PIDGEY).
    local battle = Battle.new({ data = DATA, party = { player },
      wild = wild, save = save, random = function() return 0 end })
    local screen = BattleState.new(game, { battle = battle, save = save })
    screen:useItem(ball)
    return battle, save, wild
  end

  local battle, save, wild = catchWith("FRIEND_BALL")
  eq(battle.outcome, "caught", "the Friend Ball catch lands")
  eq(wild.happiness, Catching.FRIEND_BALL_HAPPINESS,
    "and the caught mon's happiness is set to 200")
  eq(save.party[2], wild, "in the party slot it landed in")

  battle, save, wild = catchWith("POKE_BALL")
  eq(battle.outcome, "caught", "the control catch lands too")
  eq(wild.happiness, 70, "an ordinary ball leaves the base 70")
end

S.finish()
