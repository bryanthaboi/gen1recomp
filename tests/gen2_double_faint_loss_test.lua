-- engine/battle/core.asm:2007-2019, :2607-2619, :2915

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 double faint loss")
local eq = S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  SELFDESTRUCT = { id = "SELFDESTRUCT", name = "SELFDESTRUCT", power = 200,
    type = "NORMAL", accuracy = 100, pp = 5, effect = "EFFECT_SELFDESTRUCT" },
  EXPLOSION = { id = "EXPLOSION", name = "EXPLOSION", power = 250,
    type = "NORMAL", accuracy = 100, pp = 5, effect = "EFFECT_SELFDESTRUCT" },
}

local GROWTH = {
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15,
    linear = 100, constant = 140 },
}

local function species(id, index, speed)
  return {
    id = id, index = index, name = id,
    baseStats = { hp = 40, attack = 60, defense = 40, speed = speed,
      specialAttack = 40, specialDefense = 40 },
    types = { "NORMAL", "NORMAL" }, catchRate = 45, baseExp = 100,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } },
    evolutions = {},
  }
end

local DATA = {
  pokemon = {
    growthRates = GROWTH,
    EEVEE = species("EEVEE", 133, 10),
    GRAVELER = species("GRAVELER", 75, 200),
    GOLEM = species("GOLEM", 76, 200),
  },
  moves = MOVES,
  type_chart = { types = TYPES, matchups = {} },
  items = {},
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function zeroRandom() return 0 end

local function mon(id, level, move)
  local m = Mon.new(DATA, id, level, { dvs = perfect })
  m.moves = { { id = move, pp = 5, maxPp = 5 } }
  return m
end

local function faintSides(events)
  local out = {}
  for _, ev in ipairs(events) do
    if ev.kind == "faint" then out[#out + 1] = ev.side end
  end
  return table.concat(out, ",")
end

local function count(events, kind)
  local n = 0
  for _, ev in ipairs(events) do if ev.kind == kind then n = n + 1 end end
  return n
end

do
  local eevee = mon("EEVEE", 10, "TACKLE")
  local graveler = mon("GRAVELER", 30, "SELFDESTRUCT")
  local expBefore = eevee.experience
  local b = Battle.new({ data = DATA, party = { eevee }, wild = graveler,
    random = zeroRandom })
  local events = b:takeTurn({ kind = "move", move = "TACKLE" })
  eq(eevee.hp, 0, "wild selfdestruct knocks out the last mon")
  eq(graveler.hp, 0, "and the graveler faints too")
  eq(b.over, true, "battle ends")
  eq(b.outcome, "lose", "both fainted with no fit mon left is a loss")
  eq(faintSides(events), "player,enemy",
    "HandlePlayerMonFaint announces the player's mon first")
  eq(eevee.experience, expBefore, "no experience on a loss")
end

do
  local eevee = mon("EEVEE", 10, "SELFDESTRUCT")
  eevee.stats.speed = 999
  local graveler = mon("GRAVELER", 5, "TACKLE")
  graveler.stats.speed = 1
  graveler.hp = 1
  local b = Battle.new({ data = DATA, party = { eevee }, wild = graveler,
    random = zeroRandom })
  local events = b:takeTurn({ kind = "move", move = "SELFDESTRUCT" })
  eq(b.outcome, "lose", "the player's own selfdestruct on its last mon loses")
  eq(faintSides(events), "enemy,player",
    "HandleEnemyMonFaint announces the enemy first")
end

do
  local eevee = mon("EEVEE", 10, "TACKLE")
  local golem = mon("GOLEM", 30, "EXPLOSION")
  local backup = mon("GRAVELER", 30, "TACKLE")
  local b = Battle.new({ data = DATA, party = { eevee },
    trainer = { name = "HIKER", party = { golem, backup } },
    random = zeroRandom })
  local events = b:takeTurn({ kind = "move", move = "TACKLE" })
  eq(b.outcome, "lose", "trainer explosion on the last mon is a loss")
  eq(b.enemy, golem, "the trainer never sends the next mon out")
  eq(count(events, "send"), 0, "no send event")
end

do
  local eevee = mon("EEVEE", 10, "TACKLE")
  local golem = mon("GOLEM", 30, "EXPLOSION")
  local b = Battle.new({ data = DATA, party = { eevee },
    trainer = { name = "HIKER", party = { golem } },
    random = zeroRandom })
  b:takeTurn({ kind = "move", move = "TACKLE" })
  eq(b.outcome, "lose", "trainer's last mon exploding on the last mon loses")
end

local function kinds(events, side)
  local out = {}
  for _, ev in ipairs(events) do
    if (ev.kind == "faint" or ev.kind == "send" or ev.kind == "choose-switch")
        and (not side or ev.side == side) then
      out[#out + 1] = ev.kind .. (ev.side and ("(" .. ev.side .. ")") or "")
    end
  end
  return table.concat(out, ",")
end

do
  local eevee = mon("EEVEE", 10, "TACKLE")
  local spare = mon("EEVEE", 10, "TACKLE")
  local graveler = mon("GRAVELER", 30, "SELFDESTRUCT")
  local b = Battle.new({ data = DATA, party = { eevee, spare },
    wild = graveler, random = zeroRandom })
  local events = b:takeTurn({ kind = "move", move = "TACKLE" })
  eq(b.outcome, "win", "a fit mon in reserve keeps the wild double faint a win")
  eq(faintSides(events), "player,enemy",
    "with a reserve the enemy's move still announces the player first")
end

do
  local eevee = mon("EEVEE", 10, "SELFDESTRUCT")
  eevee.stats.speed = 999
  local spare = mon("EEVEE", 10, "TACKLE")
  local graveler = mon("GRAVELER", 5, "TACKLE")
  graveler.stats.speed = 1
  graveler.hp = 1
  local b = Battle.new({ data = DATA, party = { eevee, spare },
    wild = graveler, random = zeroRandom })
  local events = b:takeTurn({ kind = "move", move = "SELFDESTRUCT" })
  eq(b.outcome, "win", "the player's own selfdestruct with a reserve wins")
  eq(faintSides(events), "enemy,player",
    "the player's move announces the enemy first, then the player")
end

do
  local eevee = mon("EEVEE", 10, "TACKLE")
  local spare = mon("EEVEE", 50, "TACKLE")
  local golem = mon("GOLEM", 30, "EXPLOSION")
  local backup = mon("GRAVELER", 50, "TACKLE")
  local b = Battle.new({ data = DATA, party = { eevee, spare },
    trainer = { name = "HIKER", party = { golem, backup } },
    random = zeroRandom })
  local events = b:takeTurn({ kind = "move", move = "TACKLE" })
  eq(b.over, false, "trainer double faint with reserves on both sides goes on")
  eq(kinds(events), "faint(player),faint(enemy),choose-switch",
    "player faint, enemy faint, then the player's pick: no enemy send yet")
  eq(b.enemy, golem, "the trainer's replacement waits for the player's pick")
  eq(b:switch(2), true, "the player picks the reserve")
  local after = b:takeEvents()
  eq(kinds(after), "send(player),send(enemy)",
    "DoubleSwitch: the player's send, then the trainer's")
  eq(b.enemy, backup, "the trainer's reserve is in")
  eq(b.player, spare, "the player's reserve is in")
  local enemySend
  for _, ev in ipairs(after) do
    if ev.kind == "send" and ev.side == "enemy" then enemySend = ev end
  end
  eq(enemySend and enemySend.replacement, false,
    "no shift offer on the double switch send")
  eq(b.pendingEnemySwitch, nil, "the deferred switch is consumed")
  local next = b:takeTurn({ kind = "move", move = "TACKLE" })
  eq(count(next, "send"), 0, "the next turn sends nobody")
  eq(count(next, "faint"), 0, "and nobody faints again")
end

do
  local eevee = mon("EEVEE", 10, "SELFDESTRUCT")
  eevee.stats.speed = 999
  local spare = mon("EEVEE", 10, "TACKLE")
  local golem = mon("GOLEM", 5, "TACKLE")
  golem.stats.speed = 1
  golem.hp = 1
  local backup = mon("GRAVELER", 30, "TACKLE")
  local b = Battle.new({ data = DATA, party = { eevee, spare },
    trainer = { name = "HIKER", party = { golem, backup } },
    random = zeroRandom })
  local events = b:takeTurn({ kind = "move", move = "SELFDESTRUCT" })
  eq(kinds(events), "faint(enemy),faint(player),choose-switch",
    "the player's own explosion: enemy faint, player faint, then the pick")
  b:switch(2)
  eq(kinds(b:takeEvents()), "send(player),send(enemy)",
    "and the same DoubleSwitch order after the pick")
end

S.finish()
