-- ../pokecrystal/engine/items/item_effects.asm:666-678
-- ../pokecrystal/data/text/common_3.asm:1233-1237
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 sent to pc nickname")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Screens = require("src.ui.Screens")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")
local Runtime = require("src.mods.Runtime")

local TYPES = { NORMAL = { id = "NORMAL", index = 0, category = "physical" } }
local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, accuracyRaw = 242, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}
local function species(id, index)
  return {
    id = id, index = index, name = id,
    baseStats = { hp = 50, attack = 60, defense = 50, speed = 60,
      specialAttack = 50, specialDefense = 50 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 60,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127, items = {},
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  }
end
local DATA = {
  pokemon = {
    growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1,
      squared = 0, linear = 0, constant = 0 } },
    CYNDAQUIL = species("CYNDAQUIL", 155),
    PIDGEY = species("PIDGEY", 16),
  },
  moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(),
  type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(),
    types = TYPES, matchups = {} },
  items = { POKE_BALL = { id = "POKE_BALL", name = "POKe BALL", pocket = "BALL" } },
}
DATA.text._BallSentToPCText = "{STRBUF} was\nsent to BILL's PC.{PROMPT}"
local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local realPush = Screens.push

local function catch(fullParty)
  Input:init()
  local party = {}
  for i = 1, fullParty and 6 or 1 do
    local mon = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
    mon.nickname = "MON" .. i
    party[i] = mon
  end
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  local save = { party = party, inventory = { POKE_BALL = 1 },
    pokedex = { seen = {}, caught = { PIDGEY = true } }, currentBox = 1,
    boxes = {}, boxNames = {} }
  local pushed = {}
  local game = {
    data = DATA, save = save, input = Input, options = {},
    stack = {
      push = function(_, s) pushed[#pushed + 1] = s end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
    },
  }
  local battle = Battle.new({ data = DATA, party = party, wild = wild,
    save = save, random = function() return 0 end })
  local screen = BattleState.new(game, { battle = battle, save = save })
  screen.queue = {}
  screen:pushCaught(battle.enemy, "POKE_BALL")
  return screen, save, battle.enemy
end

local function play(screen, answer, typed)
  Screens.push = function(_, _, opts)
    opts.onDone(typed)
    return nil
  end
  local shown = {}
  screen:advanceQueue()
  for _ = 1, 40 do
    if screen.message and shown[#shown] ~= screen.message then
      shown[#shown + 1] = screen.message
    end
    if screen.phase == "ask-nickname" then
      screen:answerNickname(answer)
    elseif screen.phase == "fadeout" or screen.phase == "done" then
      break
    elseif screen.captureFade then
      screen:stepCaptureFade()
    else
      screen:advanceQueue()
    end
  end
  Screens.push = realPush
  return shown
end

local function pcLine(shown)
  for _, line in ipairs(shown) do
    if line:find("BILL's PC", 1, true) then return line end
  end
end

do
  local screen, save, enemy = catch(true)
  local line = pcLine(play(screen, true, "SPARKY"))
  eq(save.boxes[1] and save.boxes[1][1], enemy, "the catch heads the box")
  eq(enemy.nickname, "SPARKY", "the boxed mon carries the typed name")
  eq(line, "SPARKY was\nsent to BILL's PC.",
    "BallSentToPCText names the typed nickname")
end

do
  local screen = catch(true)
  eq(pcLine(play(screen, false)), "PIDGEY was\nsent to BILL's PC.",
    "NO keeps the species SendMonIntoBox wrote")
end

do
  local screen, _, enemy = catch(true)
  eq(pcLine(play(screen, true, "")), "PIDGEY was\nsent to BILL's PC.",
    "an empty entry falls back to the species through InitName")
  eq(enemy.nickname, nil, "and stores no nickname")
end

do
  local savedHooks = Runtime.hooks
  Runtime.hooks = {
    chains = { ["catch.nickname"] = true },
    call = function(_, name, vanilla, ...)
      if name == "catch.nickname" then return "SPIKE" end
      return vanilla(...)
    end,
  }
  local screen = catch(true)
  local line = pcLine(play(screen, true, "IGNORED"))
  Runtime.hooks = savedHooks
  eq(line, "SPIKE was\nsent to BILL's PC.", "a catch.nickname name reaches the line")
end

do
  local screen = catch(false)
  check(pcLine(play(screen, true, "SPARKY")) == nil,
    "a party catch prints no PC line")
end

S.finish()
