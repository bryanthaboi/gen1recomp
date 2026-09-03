-- engine/battle/effect_commands.asm:5475

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 dig pic box")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  GROUND = { id = "GROUND", index = 4, category = "physical" },
}

local MOVES = {
  DIG = { id = "DIG", name = "DIG", power = 60, type = "GROUND",
    accuracy = 100, pp = 10, effect = "EFFECT_FLY" },
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  REFLECT = { id = "REFLECT", name = "REFLECT", power = 0, type = "NORMAL",
    accuracy = 0, pp = 20, effect = "EFFECT_REFLECT" },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  FAST = {
    id = "FAST", index = 65, name = "FAST",
    baseStats = { hp = 55, attack = 50, defense = 45, speed = 120,
      specialAttack = 40, specialDefense = 40 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 50,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  DIGGER = {
    id = "DIGGER", index = 237, name = "DIGGER",
    baseStats = { hp = 250, attack = 40, defense = 45, speed = 10,
      specialAttack = 40, specialDefense = 40 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 50,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "DIG" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = {} },
  items = {},
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function detRandom(n)
  if (n or 1) <= 1 then return 0 end
  return 1
end

local function newScreen()
  Input:init()
  local player = Mon.new(DATA, "FAST", 20, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 },
    { id = "REFLECT", pp = 20, maxPp = 20 } }
  local wild = Mon.new(DATA, "DIGGER", 20, { dvs = perfect })
  wild.moves = { { id = "DIG", pp = 10, maxPp = 10 } }
  local save = { party = { player }, inventory = {} }
  local pushed = {}
  local game = {
    data = DATA, save = save, input = Input, options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
    },
  }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = detRandom })
  local screen = BattleState.new(game, { battle = battle, save = save })
  return screen, battle, player, wild
end

local function findMove(events, side)
  for _, event in ipairs(events or {}) do
    if event.kind == "move" and event.side == side then return event end
  end
  return nil
end

local function replay(screen, onEvent)
  while #screen.queue > 0 do
    local head = screen.queue[1]
    screen:advanceQueue()
    onEvent(head)
  end
end

do
  local screen, battle = newScreen()
  local events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  check(findMove(events, "player") ~= nil, "the player's move event is queued")
  local charge = findMove(events, "enemy")
  check(charge ~= nil, "the enemy's charge event is queued")
  eq(charge and charge.animParam, 1, "and it is the charge turn")
  eq(BattleState.isVanished(battle.enemy), true,
    "the live flag is up before anything is replayed")

  screen:pushAll(events)
  eq(screen:isUnderground("enemy"), false,
    "the box is still drawn: the charge has not been replayed")

  local seenPlayer, seenCharge = false, false
  replay(screen, function(head)
    if head.kind == "move" and head.side == "player" then
      seenPlayer = true
      eq(screen:isUnderground("enemy"), false,
        "the enemy's pic stays during the player's move")
    elseif head.kind == "move" and head.side == "enemy" then
      seenCharge = true
      eq(screen:isUnderground("enemy"), true,
        "the box empties once the charge is replayed")
    end
  end)
  check(seenPlayer and seenCharge, "both move events were replayed")
  eq(screen:isUnderground("enemy"), true, "and stays empty after the turn")
  eq(screen:isUnderground("player"), false, "the player's box is untouched")

  events = battle:takeTurn({ kind = "move", move = "REFLECT" })
  local stored = findMove(events, "enemy")
  eq(stored and stored.wasVanished, true, "the stored attack is flagged")
  check((battle.screens.player.reflect or 0) > 0,
    "Reflect went up against the dug-in target")
  screen:pushAll(events)
  eq(screen.picHidden.enemy, true, "latchVanished hides the box")
  eq(screen:isUnderground("enemy"), false, "the live flag is down")
  eq(screen.vanishSeen.enemy, false, "and the seen flag was reset with it")
  replay(screen, function() end)

  events = battle:takeTurn({ kind = "move", move = "TACKLE" })
  charge = findMove(events, "enemy")
  eq(charge and charge.animParam, 1, "the enemy charges again")
  screen:pushAll(events)
  eq(screen:isUnderground("enemy"), false,
    "a stale seen flag does not blank the box early")
  replay(screen, function(head)
    if head.kind == "move" and head.side == "player" then
      eq(screen:isUnderground("enemy"), false,
        "the enemy's pic stays during the player's move again")
    end
  end)
  eq(screen:isUnderground("enemy"), true, "and empties after its own charge")
end

S.finish()
