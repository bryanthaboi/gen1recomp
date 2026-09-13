-- engine/battle/core.asm:869, engine/battle/core.asm:912, engine/battle/core.asm:1005

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}

local POKEMON = {
  growthRates = {
    GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
      linear = 0, constant = 0 },
  },
  MACHOP = { id = "MACHOP", index = 66, name = "MACHOP",
    baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
    levelMoves = {}, evolutions = {} },
}

local DATA = { pokemon = POKEMON, moves = MOVES,
  type_chart = { types = TYPES, matchups = {} }, items = {} }

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function rng() return 0 end

local function mon(level)
  local m = Mon.new(DATA, "MACHOP", level or 50, { dvs = perfect })
  m.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  return m
end

local TACKLE = { kind = "move", move = "TACKLE" }

local function indexOf(events, pred, from)
  for i = from or 1, #events do
    if pred(events[i]) then return i end
  end
end

local function moveBy(side)
  return function(e) return e.kind == "move" and e.side == side end
end

local function tickOf(side, anim)
  return function(e)
    return e.kind == "damage" and e.side == side and e.anim == anim
  end
end

local function count(events, pred)
  local n = 0
  for _, e in ipairs(events) do if pred(e) then n = n + 1 end end
  return n
end

local function hasText(events, sub)
  for _, e in ipairs(events) do
    if e.text and e.text:find(sub, 1, true) then return true end
  end
  return false
end

do
  local lead, bench = mon(), mon()
  local player = mon()
  local battle = Battle.new({ data = DATA, party = { player },
    trainer = { class = "YOUNGSTER", name = "JOEY", party = { lead, bench } },
    random = rng })
  player.status = "poison"
  player.stats.speed, lead.stats.speed = 200, 1
  lead.hp = 1
  local hpBefore = player.hp
  local events = battle:takeTurn(TACKLE)
  T.eq(battle.enemy, bench, "a: the trainer's second mon is sent out")
  T.check(not hasText(events, "hurt by poison"),
    "a: an OHKO jumps past the attacker's own poison tick")
  T.eq(player.hp, hpBefore, "a: the poisoned player loses no HP that round")
end

do
  local p1, p2 = mon(), mon()
  local lead = mon()
  local battle = Battle.new({ data = DATA, party = { p1, p2 },
    trainer = { class = "YOUNGSTER", name = "JOEY", party = { lead, mon() } },
    random = rng })
  lead.status = "poison"
  lead.stats.speed, p1.stats.speed = 200, 1
  p1.hp = 1
  local hpBefore = lead.hp
  local events = battle:takeTurn(TACKLE)
  T.check((p1.hp or 0) <= 0, "b: the player's lead fainted")
  T.check(not hasText(events, "hurt by poison"),
    "b: the enemy that KOd skips its poison tick")
  T.eq(lead.hp, hpBefore, "b: the poisoned enemy loses no HP that round")
end

do
  local player, wild = mon(), mon()
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = rng })
  player.status, wild.status = "poison", "poison"
  player.stats.speed, wild.stats.speed = 1, 200
  local events = battle:takeTurn(TACKLE)
  local em = indexOf(events, moveBy("enemy"))
  local et = indexOf(events, tickOf("enemy", "ANIM_PSN"))
  local pm = indexOf(events, moveBy("player"))
  local pt = indexOf(events, tickOf("player", "ANIM_PSN"))
  T.check(em and et and pm and pt, "c: both moves and both poison ticks happen")
  T.check(em and et and pm and pt and em < et and et < pm and pm < pt,
    "c: enemy move, enemy poison, player move, player poison")
end

do
  local player, wild = mon(), mon()
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = rng })
  player.status = "poison"
  player.stats.speed, wild.stats.speed = 200, 1
  player.hp = 1
  local events = battle:takeTurn(TACKLE)
  T.eq(player.hp, 0, "d: the player faints to its own poison")
  T.eq(indexOf(events, moveBy("enemy")), nil,
    "d: the slower enemy never gets its move")
end

do
  local player, wild = mon(), mon()
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = rng })
  player.stats.speed, wild.stats.speed = 200, 1
  battle:volatile(player).leechSeed = true
  local events = battle:takeTurn(TACKLE)
  local pm = indexOf(events, moveBy("player"))
  local sap = indexOf(events, tickOf("player", "ANIM_SAP"))
  local em = indexOf(events, moveBy("enemy"))
  T.check(pm and sap and em and pm < sap and sap < em,
    "e: Leech Seed drains between the faster mon's move and the slower one's")
end

do
  local p1, p2 = mon(), mon()
  local wild = mon()
  local battle = Battle.new({ data = DATA, party = { p1, p2 }, wild = wild,
    random = rng })
  p2.status = "poison"
  local events = battle:takeTurn({ kind = "switch", index = 2 })
  local pt = indexOf(events, tickOf("player", "ANIM_PSN"))
  local em = indexOf(events, moveBy("enemy"))
  T.eq(count(events, tickOf("player", "ANIM_PSN")), 1,
    "f: the switched-in mon's poison ticks exactly once")
  T.check(pt and em and pt < em,
    "f: after a switch the player's tick lands before the enemy's move")
end

do
  local player, wild = mon(), mon()
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = rng })
  player.status = "poison"
  local events = battle:takeTurn({ kind = "item", item = "POTION" })
  local pt = indexOf(events, tickOf("player", "ANIM_PSN"))
  local em = indexOf(events, moveBy("enemy"))
  T.eq(count(events, tickOf("player", "ANIM_PSN")), 1,
    "f: an item turn ticks the player's poison exactly once")
  T.check(pt and em and pt < em,
    "f: after an item the player's tick lands before the enemy's move")
end

do
  local player, wild = mon(), mon()
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = rng })
  player.status, wild.status = "poison", "poison"
  player.stats.speed, wild.stats.speed = 200, 1
  battle.weather, battle.weatherTurns = "sandstorm", 5
  local events = battle:takeTurn(TACKLE)
  local pt = indexOf(events, tickOf("player", "ANIM_PSN"))
  local et = indexOf(events, tickOf("enemy", "ANIM_PSN"))
  local sand = indexOf(events, function(e)
    return e.kind == "damage" and e.anim == "ANIM_IN_SANDSTORM"
  end)
  T.check(pt and et and sand and pt < sand and et < sand,
    "g: HandleBetweenTurnEffects' sandstorm lands after both poison ticks")
end

T.finish("gen2 residual timing bug 2257")
